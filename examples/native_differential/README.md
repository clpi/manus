# Native lowering differential corpus

`zig build native-differential` (script: `scripts/native_differential.sh`).

The direct ARM64 backend must produce the **same exit status and the same
stdout** as the C backend for every program in this directory. Each program
returns a computed value from `main`, and any program that prints is compared
byte for byte on what it printed.

**Stdout is not optional and was not always there.** gap[067] — a numeric `for`
whose body's only effect is a call, dropped entirely by the direct backend —
exited 0 on both columns and differed only in what reached the terminal, so a
status-only differential called it agreement. So did a file-scope global whose
read folded to its initializer (gap[066]: c printed 6, direct printed 3, both
exit 0). An entire class of DROPPED-EFFECT defects is invisible to exit status,
because the whole point of a dropped effect is that it was never a value.

## Why this exists

`src/native_backend.zig` already had 26 unit tests when the backend was
miscompiling nearly everything. They passed because they assert that
*instructions are present* — `cmp_count >= 3`, `branch_count >= 3`, `indexOf(asm,
"mul x") != null`. A backend can satisfy every one of those assertions while
computing the wrong answer.

Ten root causes were found by differential testing that no amount of
instruction-counting would have surfaced:

| # | Defect | Effect |
| --- | --- | --- |
| 1 | `br_if_not` branched on stale NZCV instead of the materialized condition (`cset` does not write flags) | every `if <cmp>` became `if (lhs == rhs)` |
| 2 | `CSET` base encoding had cond bit 12 pre-set, so ORing the condition corrupted `ge`/`eq`/`gt` | `cset` emitted the wrong condition; asm listing and encoding disagreed |
| 3 | DNIR param slots were assigned by index without advancing the temp cursor | first temp aliased a parameter; the param's register was silently rebound |
| 4 | `allow_return` propagated into loop bodies | `tryEmitTailDemandReturn` ended each loop body with `return`, so loops ran one iteration |
| 5 | `store_local` allocated a **new** register per store | invisible in straight-line code; across a back-edge the loop head still read the old register → infinite loop |
| 6 | `buildConstSlotMap` recorded any literal store as a constant, ignoring reassignment | loop counters folded to their entry values (`i = i + 1` → `i = 2`) → infinite loop |
| 7 | parameters stayed in x0–x7, which `emitSaveCallerRegs` (x9–x28) never preserves | any call destroyed a live parameter — `fib(n-1) + fib(n-2)` computed `fib(n-1) - 2` |
| 8 | `ret` and call-argument handlers released registers without the `regIsPinned` guard | register allocation is linear and ignores branches, so an early `return n` freed the parameter's register for the fall-through path to reuse |
| 9 | `mov_arg` was emitted while later arguments were still being evaluated | a nested call clobbered already-marshalled arguments: `sum2(sq(5), sq(4))` passed `(16, 16)` |
| 10 | the "did this function return" check was one flag for the whole function | a fall-through path with no terminator still passed; the function ran off its end into the next symbol → SIGSEGV |

Defects 5 and 6 only became observable *after* 4 was fixed, and 8 only after 7 —
each masked the next. A behavioural differential is the only thing that finds a
chain like that. Defect 10 is now a refusal rather than a miscompile: falling off
the end of a function is unrecoverable at runtime, so the backend declines and
the honest `DNB001` path reports the gap.

## Layout

- `*.duo` — the gate. All must agree; a divergence or a hang fails the build.
- `unsupported/` — the direct backend refuses to compile these. That is an
  honest capability gap, not a miscompilation, so it does not block. Current
  gaps: f64 arithmetic, string `#`, record literals, table indexing, closures.
- `known_divergent/` — compiles but computes the wrong answer. Open bugs, listed
  on every run so they stay visible. Recursion (`p10_recurse`) was promoted into
  the corpus once defects 7–9 were fixed. Current residents, both of them
  arithmetic and both of them cases where **the C column is the wrong one**:
  `g065_integer_division` (`i64 / i64` is typed f64 against B-4, so C prints the
  bit pattern of a double where the direct backend correctly truncates) and
  `g064_int_div_by_zero` (`7 / 0` answers +inf bits under C and 0 under direct —
  the fourth state `docs/spec/soundness.md` §1 says does not exist).
  Both exit 0 on both columns, so **only the stdout comparison can see them**;
  under the old status-only gate they read as agreement.
- `native_only/` — capabilities the C backend **cannot compile at all**, so it is
  not a valid oracle. Each file declares its expected exit status as
  `-- expect: N` in a header comment. These block like the main corpus.

When a `known_divergent` program starts agreeing, the gate says so and asks you
to promote it into the corpus.

## What lowers natively today

Scalar arithmetic, comparisons, `if`/`elseif`/`else`, `while` and numeric `for`
loops, multi-argument calls, nested calls, mutual recursion, and self-recursion —
all with zero `lua_*` runtime symbols in the emitted binary.

Plus compile-time module resolution: `Alias = req "std.compiler.token"` binds at
compile time and `Alias.CONST` folds to an immediate. `native_only/req_module_constant.duo`
lowers to `mov x9, #14; mov x0, x9; ret` — the whole module reference erased.

Of the Pass 16 self-hosting proofs, `pass16_m1_lexer_proof` and
`pass16_lexer_corpus_proof` compile and run correctly through the direct backend
with zero `lua_*` symbols.

Records lower through an **exploded** model: a record is stored as one local per
field, and passing one means passing its fields in consecutive ABI slots — the
same convention the f64 kernel path already used. Locals, field assignment,
returns, arguments, and token-shaped records with `str` fields all work. `#s` on
a `str` lowers to a `strlen` call.

### Canonical idiom: now proven natively

The canonical form used to be the broken one — bare functions with an explicit
`return` passed while `name = (p): T … end` with a tail-expression record return
returned 7 as 3. That was a **parallel-move bug**: returning a record wrote x0
first and then read a later field that still lived in x0 (a parameter), so the
field picked up the value just stored. Return marshalling now stages every field
through a scratch register before committing to x0..x2.

Module-level bindings fold too: `Kind = @{ eof = 0, ident = 1 }` is collected as
a compile-time constant map, so `Kind.ident` becomes an immediate instead of a
runtime field load (`DNB007`). Both the plain `{…}` and canonical `@{…}`
spellings are handled — `@{}` parses as a `.compile` unop wrapping the table.

Proven in the corpus: `canon1_lambda_record_return`, `canon2_tail_record_return`,
`canon3_descriptor_enum`, `canon4_descriptor_in_record`, `canon5_scan_shape`,
`canon6_call_in_record_literal`.

### Open blocker: call result bound to a local before a tail record return

`unsupported/tokenizer.duo` is a real compiler subsystem written in **canonical,
idiomatic Duo** — functions as value bindings (`name = (params): ret … end`), no
`fun`/`then`/`do`, `@{}` descriptors instead of an `enum` keyword, `if`/`elseif`
rather than `match`, named field projection. It is **semantically correct**:
checksum 162 through the C backend.

#### Resolved: `f{...}` table-call sugar no longer spans a newline

```
scan = (pos: i64): tok
    k = one(pos)                        -- a call statement …
    { kind = k, start = pos, len = 1 }  -- … then a tail record literal
end
```

This used to parse as `one(pos)({ kind = k, … })` — Lua's `f{...}` table-call
sugar absorbed the tail record literal as an *argument* to the preceding call, so
the function never produced a record return. Confirmed against the AST: the
assigned value was a `.call` whose `.func` was itself a `.call`.

**Ruling:** a `{` on a new line starts a fresh expression, not a table-call
argument. This is the rule `(` and string literals already follow in the same
suffix loop (F-13813-1), so it adds no new concept — it removes an inconsistency.
Evidence: `f({...})` expresses the same thing, and a scan of 575 `.duo` files
found **zero** real uses of the sugar. Same-line `f{...}` still parses, so Lua
compatibility is untouched.

Proven by `canon7_call_local_then_record`.

#### Resolved: `and` / `or` had no DNIR lowering

The "second function breaks the module" symptom was a misread. `lowerBinop` had
no arm for `and`/`or`, so **any** function containing one failed DNIR lowering
and dragged the whole module onto the AST backend — which lacks `#s`,
`string.byte` and record lowering. The helper was not interacting with the scan;
it simply contained an `and`.

`and`/`or` now lower with real short-circuit branches (not a bitwise fold —
`i <= n and string.byte(src, i)` must not read past the end):

```
and:  S = lhs;  if !S goto END;  S = rhs;  END:
or:   S = lhs;  if !S goto RHS;  goto END;  RHS: S = rhs;  END:
```

`or` uses `br_if_not` + `br` because the backend has no `br_if`. Scoped to
integer contexts: when either operand's subtree touches f64, lowering refuses so
the AST backend keeps handling `cond and a or b` over f64 records (Pass 11
WP-04). Proven by `canon11_and_short_circuit`, `canon13_or_short_circuit`,
`canon10_helper_plus_record_scan`, `canon12_helper_call_record_scan`.

Also fixed alongside: `validateFunction` rejected `str` parameters on the general
path even though the record-returning path accepted them — so every
`f(s: str): i64` reaching the AST backend was `DNB002`. `str` is a `const char*`
and rides x0..x7 like an i64.

#### Achieved: a real compiler subsystem compiles end to end natively

`tokenizer.duo` is in the corpus and passes. It is a tokenizer written in
canonical Duo — value-binding functions, no `fun`/`then`/`do`, `@{}` descriptor
enum, `if`/`elseif`, named projection — that scans a source string byte by byte
and classifies identifiers, numbers and punctuation. It compiles through the
direct ARM64 backend and returns checksum 162, matching the C backend.

The emitted binary's entire text section is the program:

```
_scan_one  _tokenize_checksum  _is_space  _is_alpha  _is_digit  _main
```

**Zero `lua_*` runtime symbols.** No boxing, no dynamic dispatch, no interpreter.

#### Self-application: the tokenizer scans its own source

`tokenizer_selfscan.duo` compiles natively and scans a verbatim copy of its own
`is_digit` definition, returning **26** — the exact token count, matching the C
backend. The scanned text exercises the digit-terminates-identifier path (`i64`
splits into `i` + `64`), so it is real Duo syntax, not a toy string.

**This is not self-hosting.** Duo's compiler is Zig-hosted at bootstrap stage S0
and `canonical_compiler_in_duo` is still false. What it establishes is narrower
and still worth stating: a compiler front-end component, written in canonical Duo
and compiled to native ARM64, correctly processes Duo compiler source.

Source is embedded rather than read from disk because `std.os.read_file` lowers
on neither backend today; the scanner logic is identical either way.

#### SH-03 step: a Duo lexer emitting canonical token ids, natively compiled

`native_only/lexer_native.duo` compiles to native ARM64 and emits the **same
token kind ids as `src/lexer.zig`**. The ids are not restated here — they are
consumed via `req "std.token.classify"` from `lib/std/token/classify.duo`
(SH-02, already `duo_canonical`, generated from `src/token_classify_gen.zig`) and
fold to immediates. Duo lexer and host lexer therefore agree on token identity by
construction rather than by convention: if an id ever moved, the gated total
would move with it.

It returns 84 for `local x = 1 if x and x return x end end` —
`local(19) + if(17) + and(4) + return(24) + end(10) + end(10)`. Text section is
`_next_token _classify_word _is_alpha _is_digit _is_space _main` plus the linked
`_duo_keyword_classify`; **zero `lua_*` symbols**.

It is gated `native_only` because the **C backend cannot compile it** — as with
`req_module_constant`, the direct backend is strictly more capable here, so C is
not a valid oracle.

Why not `lib/std/compiler/lexer.duo` (the existing SH-03 differential oracle):
its `lexer` record has 18 fields including strings, nested records and floats,
exceeding the 8-slot register ABI for aggregates. Keeping lexer state in scalars
and a 3-field token record puts the whole thing inside the proven native subset.
**The 18-field design is a choice, not a requirement** — which is the useful
finding, because it means SH-03 is not blocked on the aggregate-ABI milestone.

#### SH-04 step: a recursive-descent parser, natively compiled

`native_only/parser_native.duo` is a precedence-climbing expression parser —
the core shape of `src/parser.zig` — written in Duo and compiled to native ARM64:

```
expr   := term   (('+' | '-') term)*
term   := factor (('*' | '/') factor)*
factor := NUMBER | '(' expr ')'
```

It returns **7** for `1 + 2 * 3`, so `*` binds tighter than `+`. Text section is
`_parse_expr _parse_term _parse_factor _skip_spaces _is_digit _main`; **zero
`lua_*` symbols**.

Two things it proves beyond arithmetic. Each grammar level must return *both* a
value and the position it consumed to, and there are no tuples in the native
subset — so the parse result is a 2-field record riding the ABI registers with no
allocation. And `factor` calls `expr` for a parenthesised group while `expr`
reaches `factor` through `term`: **mutual recursion across record-returning
functions**, which is what a recursive-descent parser is made of.

That second point required a compiler fix. `func_record_returns` was populated as
each function *finished* lowering, so a forward reference could not see it —
`parse_factor` calling the not-yet-lowered `parse_expr` failed with `DNB007`. The
map is now filled by a pre-pass over all functions before any body lowers.

#### SH-04 step 2: block structure over real Duo source

`native_only/parser_blocks.duo` moves from arithmetic to actual Duo syntax. It
scans a Duo function body, recognises the reserved words that open and close
blocks, and reports maximum nesting depth — the same bookkeeping `src/parser.zig`
does to match an `end` against its opener. Returns **3** for

```
function f(n) while n > 0 if n == 1 return 1 end end end
```

`function` → `while` → `if`, closed by three matching `end`s. Max depth is a
*structural* property: it cannot be produced by miscounting tokens, only by
correctly pairing openers with closers. Unbalanced input (an `end` with no
opener) returns −1 rather than a plausible-looking number.

Keyword identity again comes from `classify.duo` via `req`, so "what counts as
`if`" is the compiler's own fact folded to an immediate.

`do` is deliberately **not** an opener: in `while cond do … end` it belongs to
the `while`, and canonical Duo omits it (`then`/`do` are deprecated). Counting it
gave depth 4 for the sample above — a good illustration that these components are
checked against Duo's grammar rules, not against my expectations.

#### SH-06 step: name resolution, natively compiled

`native_only/resolver_native.duo` answers the question a binder answers: which
identifiers in a source fragment are **not** bound in the enclosing scope. It
returns **2** for `x + total + y + z` against scope `x total` — `y` and `z` are
the two "undefined name" diagnostics a real binder would emit. Zero `lua_*`
symbols.

Whole-token matching, not prefix matching: a candidate must be the same length,
so `n` does not match `name`.

**The interesting part is the constraint.** SH-06 normally wants a growable
symbol table, and the native subset has no dynamic collections — no arrays, no
tables, records are fixed-arity. So the scope is a delimited string, searched
linearly. That is a real technique (early C compilers did it) and fits the proven
subset exactly: string bytes, nested loops, byte comparison.

What it does **not** do is declare bindings at runtime. Duo strings are immutable
`const char*`, so a scope cannot grow without allocation. Resolution against a
*given* scope is the honest slice available today; growable scopes need native
table lowering, which is the actual SH-06 milestone and is shared with
`unsupported/rec6_nested` and the aggregate ABI.

#### Native tables, step 1: positional literals with constant indexing

`native_only/table_const_index.duo` — `t = { 10, 20, 30 }` then `t[1] + t[2]`
returns **30** natively, zero `lua_*` symbols.

Elements become one local per slot (`t.1`, `t.2`, …), exactly as record fields
do, so a constant index is a compile-time slot lookup with **no memory traffic
at all** — the element lives in a register. `#t` folds from a stored length.

Gated `native_only` because **the C backend is wrong here**: it returns 0 for
`t[1]` where both reference Lua and the direct backend give 10. That makes the
direct backend strictly more correct than the bootstrap backend on this
construct, and C an invalid oracle.

#### Native tables, step 2: dynamic indexing

`native_only/table_dynamic_index.duo` — `t[i]` where `i` is a **loop variable**.
Returns **60**, matching the `lua` reference exactly. Zero `lua_*` symbols. The C
backend cannot compile it, so the gate uses Lua's answer.

The insight is that this needed no memory at all. Positional elements live in
registers, so there is no base pointer to offset from — and for a statically
known length the correct lowering is a *select over the element slots*:

```
S = 0;  if i == 1 { S = t.1 }  if i == 2 { S = t.2 }  …  S
```

O(n) compares, zero memory traffic, which is the right trade for the small
fixed-size tables a compiler actually uses. An out-of-range index yields 0 rather
than reading adjacent storage.

What this does **not** give you is a *growable* table — that still needs
base-pointer addressing and allocation. So SH-06 can now use a bounded symbol
table, but not an unbounded one.

#### Native tables, step 3: mutable stores — and SH-06 completed

`native_only/table_mutable_store.duo` — `t[i] = v` with `i` a loop variable
returns **100**, matching the `lua` reference. The mirror of dynamic reads: a
select-chain of *stores* over register-resident slots. Still no memory, no
allocation.

That closes the capability that was blocking SH-06. `native_only/symtab_native.duo`
is a genuinely **mutable symbol table** — declare a symbol into a slot, look it
up, get 0 for unbound, overwrite a slot and re-query. Returns **21**, zero
`lua_*` symbols.

`resolver_native.duo` could only resolve against a scope fixed at compile time,
because strings are immutable and there was no mutable collection. There is one
now, for bounded scopes — which is what a compiler frontend actually uses. An
*unbounded* table still needs real allocation.

#### SH-11 step: ARM64 instruction encoding, in Duo

`native_only/arm64_encoder.duo` encodes MOVZ, ADD, SUB, CSET and RET and checks
each against the word the Zig backend emits — verified against `objdump` during
this session's work on `src/native_backend.zig`. Returns **5**, zero `lua_*`
symbols. It is compiled to ARM64 by the very backend whose encodings it
reproduces.

A code generator's correctness-critical core is not file I/O — it is turning
(opcode, registers, immediate) into a 32-bit word, which is pure integer
arithmetic and fits the native subset exactly. The CSET case is present
deliberately: the Zig backend had bit 12 of the base constant pre-set, so ORing
the condition corrupted `ge`/`eq`/`gt` and every `cset` with an even condition
encoded the wrong test. That defect is defect #2 of this session.

#### SH-11 step 2: a code generator

`native_only/codegen_native.duo` takes the program `return 42` and emits the
*sequence* of ARM64 instructions for it into a mutable table — `code[n] = word;
n = n + 1`, exactly the shape of `emitFmt` in `src/native_backend.zig` — then
verifies both emitted words against what `objdump` shows:

```
mov x0, #42   -> 0xd2800540
ret           -> 0xd65f03c0
```

Returns **2**, zero `lua_*` symbols. So encoding *and* sequencing are both
demonstrated in Duo, natively.

**The one remaining gap is persistence — and it is smaller than it looks.**

`os.write_file` does not lower natively (`DNB007`), but the reason is not that
file I/O is hard. Look at its implementation in `lib/std/os.duo`:

```
fun os_write_file(path: str, data: any): bool
    … @c.emit([[ … lua_to_str(data); lua_str_byte_len(data) … ]])
```

`data: any` is a boxed `lua_Value`, and the body calls `lua_to_str` /
`lua_str_byte_len`. **The stdlib's file I/O is written against the boxed
runtime**, which is exactly what the native path forbids. Every I/O entry point
in `lib/std` is the same shape — there is no native-typed byte writer anywhere.

So the blocker is a missing *stdlib primitive*, not a missing backend capability:
something like `write_u32(path: str, word: i64): bool` over raw `fwrite`, with no
`lua_to_str` in it.

And the runtime-sized buffer requirement dissolves with it. An emitter that can
**append** does not need a buffer at all — open, write each word as it is
encoded, close. That is how plenty of assemblers work, and it is a sequential
loop the native subset already handles.

Adding that primitive means `@c.emit` inside `lib/std`, which the repo's own
rules permit ("C-level primitives belong in duo's stdlib"), but it is C and was
not attempted here.

#### Open defect: `@comp.why` in a function body

`@comp.why(...)` is a compile-time annotation and should lower to nothing, but
placing it in a function body makes that function's ARM64 emission fail with
`UnsupportedProgram` — it was the last thing blocking the tokenizer. DNIR
lowering succeeds; emission does not. The tokenizer therefore carries its
optimization note as a comment rather than as `@comp.why`, which is a workaround,
not a fix.

Two further compile-time gaps found while writing it:

* `@comp.assert` is compile-time, so `@comp.assert(t.len >= 1)` on a runtime
  field is a misuse and is rejected — correctly.
* `@comp.assert` also cannot fold a **descriptor field projection**:
  `@comp.assert(Kind.eof == 0)` fails even though `Kind` is a `@{}` descriptor
  with literal fields. Only literal expressions fold, so descriptor-level
  constraints cannot be machine-checked yet.

### Open blocker: records produced inside a loop

`unsupported/tokenizer.duo` is a real compiler subsystem written in spec'd Duo —
it scans a source string byte by byte and classifies identifiers, numbers and
punctuation. It is **semantically correct** (checksum 162 through the C backend)
and uses only constructs the direct backend otherwise proves: `str` parameters,
`#s`, `string.byte`, while loops, `and`, records passed and returned by value.

It does not compile on the direct backend because of one defect:
`assignRecordFromAbiRegs` reserves a record's stack slot by emitting `sub sp` at
the point of use. When the record is produced inside a loop that instruction
re-executes every iteration and is never balanced before the back-edge, so the
stack pointer walks down a frame per iteration and every field offset shifts.
The reservation must move to the function prologue, sized by a pre-pass over the
DNIR — offsets are `sp`-relative and only valid against a frame reserved once.

A partial fix is in place (a record local no longer reserves twice), but the
prologue move is still required. This is the single defect standing between the
current backend and natively compiling a real tokenizer.

### The next boundary

The exploded model is capped at **8 ABI slots**, and every field must be scalar.
`lexer.new()` returns an 18-field record containing strings, nested records
(`Loc`, `tok`), floats and booleans, so no amount of exploding reaches it —
records that large need a memory model: stack allocation, field-offset
addressing, and a hidden-pointer return convention. Worse, `lexer.new` is an
*extern* call into a separately-compiled module, so the direct backend would also
have to match that module's struct ABI exactly.

That is milestone work (P4-04 native table/field-offset lowering, P16-WS15
representation selection), not a defect. Until it lands the backend refuses
honestly with `DNB001` rather than emitting wrong code. Nested records
(`rec6_nested`) sit behind the same boundary.

## Adding a case

Drop a `.duo` file here whose `main` returns an `i64` (exit statuses are `mod
256`, so keep expected values under 256 and away from 124, which marks a
timeout). The script picks it up automatically.
