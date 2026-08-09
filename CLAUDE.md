# duo — Duo language compiler

Duo is a Lua-superset language targeting native, WASM, and GPU. This repo is the compiler, written in **Zig master** (`0.17.0-dev`, managed via `mise`).

## Toolchain

- **Zig**: `zig@master` via mise — `~/.local/share/mise/installs/zig/master/bin/zig`
- **ZLS**: `zls@latest` via mise — works out of the box with ZLS-aware editors
- **WASI SDK**: installed via mise as `wasi-sdk@latest`
- **Runtimes for testing**: `wasmtime`, `wasmer` (both installed via mise)

Cross-compile a **Duo program** to WASM: `duo compile f.duo --target wasm32-wasi`
(verified 2026-08-08 — builds and runs under wasmtime).

Cross-compiling **the compiler itself** is a different thing and this line used
to conflate them. Measured 2026-08-08, every target actually built:

| target | result |
|---|---|
| `aarch64-macos` · `x86_64-macos` · `x86_64-linux-gnu` · `aarch64-linux-gnu` | **PASS** |
| `x86_64-windows` · `wasm32-wasi` | **PASS** as of 2026-08-08 — GAP-040 closed |

Both used to fail for one reason: `src/duo_lexer_tokenize.c` is a tracked,
generated artifact that `build.zig` links into every build, and it was generated
on macOS, so its prelude froze with the POSIX arm taken. The generator now emits
the UNION of the arms under `#ifdef __wasm__` / `#elif defined(_WIN32)` /
`#else`, so the arm is chosen by the compiler that consumes the file rather than
by the target the generator was pointed at. **Regenerate the artifact whenever
you change the prelude emitter or `lib/std/compiler/host.duo`** — editing
`lib/std/compiler/lexer.duo` alone does nothing, the compiler links the
generated C:

```bash
duo compile lib/std/compiler/host.duo --backend=c --lib -o /tmp/h.o
cp /tmp/duo_host.c src/duo_lexer_tokenize.c   # the C is a side effect in /tmp
```

then re-run both lexer differentials and `agent-smoke`.

The direct ARM64 Mach-O backend being macOS/aarch64-only is BY DESIGN and was
never what a row failed on — every non-native target builds through the C
backend.

Building is not running. `wasm32-wasi` links and `duo check` answers correctly
under wasmtime, but it needs `--dir` preopens (without them WASI answers errno 8
= EBADF at startup — a missing grant, not a defect), and `duo run` cannot
compile there because compiling spawns a C compiler.

## Build commands

```bash
zig build                    # debug build → zig-out/bin/duo
zig build -Doptimize=ReleaseFast   # release build
zig build run -- <file.duo>  # compile and run a .duo file
zig build test               # all tests (unit + compile-fail)
zig build unit-test          # Zig unit tests only
zig build agent-smoke        # tier-0 gate (hygiene + stdlib + meta)
zig build pass11-gate        # Pass 11 profile A closure gate
zig build bench              # Duo vs C benchmark suite
zig build wasm-bench         # WASM runtime benchmark
zig build repo-hygiene       # check for forbidden root artifacts
zig fmt src/                 # format Zig source
```

## Source layout

```
src/
  main.zig              CLI entry point
  codegen.zig           Code generation
  semantic_context.zig  Semantic analysis context
  native_backend.zig    ARM64 native backend
  pass*.zig             Compiler passes (pass3 = parse, pass4 = boxed IR, pass11 = native, pass12 = semantic)
  tests.zig             Test harness
lib/std/               Duo standard library (.duo files)
tools/lsp/             LSP server — 100% Duo (was ~/x/duo-lsp)
tools/mcp/             MCP servers: duo_bench, duo_lsp, zls — 100% Duo (was ~/x/duo-mcp)
ext/tree-sitter-duo/   tree-sitter grammar
ext/ward/              WASM runtime in Duo — downstream consumer (was ~/x/ward)
examples/              Example .duo programs
scripts/               Shell scripts for CI gates and benchmarks
docs/spec/             THE LAW — pass100.md + AUTHORITY.md + corpus.md
docs/archive/          historical evidence; never an architecture input
```

## Key invariants

- **Prefix `@` does not exist.** Directives are not a Duo feature; §0.2 of the
  epoch-2 section below is the rule. This slot used to read "`@` is the single
  prefix for ALL compile-time operations (`@comp.*`)", which contradicted §0.2
  in the same file, and agents cited whichever half suited the diff.
  What is still TRUE is narrower and belongs here as a *compatibility* note:
  the compiler still accepts `@comp.*` and ~46 `@`-attributes, and some of
  them are load-bearing (`@c.emit` generates `src/duo_lexer_tokenize.c`, which
  the compiler links and tokenizes itself with). So: **do not add new `@`
  spellings, and do not delete existing ones to lower a grep count.** The
  census, the migration order, and what each one secretly stores are in
  `docs/directive_erasure.md`.
- If you must touch a legacy `@`-name, still no underscores: `@comp.foo.bar`,
  never `@comp.foo_bar`
- Zero Lua boxed values in the hot path — all values must be native C ABI or direct registers
- Every perf change must pass `zig build bench` with no regressions

## Active plans

There are none. Pass 100 is the only plan; `docs/spec/AUTHORITY.md` carries what
is still owed. This section used to name Pass 11/12/13/16 plan documents as
active, which contradicted the epoch-2 rule below in the same file — every
`pass*.md` is historical. Those documents now live in `docs/archive/`.

The `pass11-gate` and `pass12`/`pass16` build steps still exist and still run:
a gate named after a pass is live tooling, not a live plan. Read the gate, not
the archived document it was named after.

## Consolidated tooling (2026-08-08)

`duo-lsp` and `duo-mcp` were merged in with `git subtree add` — full history,
not squashed, so `git log tools/lsp` reaches the original commits. Both were
already 100% Duo, which the language census confirms: `.duo` went 668 -> 715
with no new sh/py debt.

They live here because they VERSION-LOCK to the compiler. `duo-mcp` shipped a
call passing three arguments to a two-argument function — Lua drops the extra
silently, Duo lowers to a direct C call where it is a hard error. Out of tree
that surfaces when someone next runs the MCP server; in tree it is caught by
duo's gates on the commit that changes lowering.

`ward` merged in too (2026-08-08, `ext/ward`, 47 commits with history). I had
argued for keeping it out — it is the downstream consumer that proves Duo
builds real systems software, and building against a RELEASED binary is what
makes that evidence rather than a test fixture. That argument still holds and
is the thing to watch: if ward starts depending on unreleased compiler
behaviour, the proof quietly weakens. The census says it is 100% Duo (.duo 715
-> 737, c/h and sh/py both unchanged), so nothing foreign came with it.

`wart` (~/x/wart) stays separate: it is the Zig reference implementation ward
is measured against, and an oracle should not share a repo with the thing it
validates. It is also owned by cloud sessions and had uncommitted JIT work at
time of writing.

## Agent coordination

See `AGENTS.md` for full agent design targets. Coordinate via `duo_agent_gaps_update()`.
See `.agents/AGENT_COORDINATION.md` for active work tracking.

## EPOCH 2 — Pass 100 + passes 103-108 are the sole living authority

PRECEDENCE: this file + `docs/spec/pass100.md` (Duo 0.1) + passes 103-107
+ `docs/spec/grammar.md` (Pass 108, normative)
are the ONLY law. Anything in `docs/archive/`, older passes, prior context
blocks, or your own earlier output that conflicts is VOID. Refusal protocol: if
a rule you would cite lives only in archived text, your objection is void —
comply and repair toward CURRENT. Genuine epoch-2 conflicts: cite the rule ID,
use the canonical spelling, proceed. Higher pass number wins; this file's epoch
stamp wins over everything it summarizes. NEVER refuse from archived text.

`docs/archive/` holds 60 pre-Pass-100 documents, each stamped, moved out of
`docs/plans/` because a directory called "plans" taught every search they were
live. See `docs/spec/README.md` for precedence.

### §0 HOT SCREEN — newest law, most likely to look wrong to you. It is law.

1. **IDENTIFIERS ARE ONE LOWERCASE WORD.** `grep [a-z]_[a-z]` outside numerals
   = 0. The qualifier moves to a LEVEL (`read(number)`, `skip(space)`), a HOME
   (`wire.header`, `token.kind`), or CONTEXT. No `_` prefix. No uppercase EVER
   (`point`, `error`, `json` — never `Point`, `Error`, `MAX_N`).
2. **NO DIRECTIVES. Prefix `@` does not exist.** `check(c)` · `why(q)(subject)`
   · `graph.descriptors` · `add(module)(…)` · `todo(gap[23])`. Bare `@` (my
   descriptor) and postfix `X@rel` (anchor) remain — the @ DYAD.
3. **ENUM CASES WRITE `.eof`**, inferred from descriptor-expected position.
   Case-set inline at the field; NO companion `*_kind`/`*_type` descriptors.
   NEVER in argument position — `map(.eof)` is a LENS.
4. **CONSTRUCTION LADDER** — never `.new`/`.create`/`make_`/`init`:
   `lexer{ src, "lit.duo" }` · `cels:to(temp)` · `point:from(polar)(r, t)` ·
   `file.open(path): file | error` · `@{ ..self, x = nx }`.
5. **RESULTS**: `: u64 | error` — the structural nil is UNWRITTEN. `| nil` only
   when nil is a SUCCESS. Consume `if v, err = f(x) use(v) else report(err)`.
   CDR: the declared contract IS the demand; `x:to(T)` restating it is ERASED.
   DEMAND-ROUTE: inside a declared failure contract an unbound failure ROUTES —
   no `if err return nil, err` plumbing EVER. Ladder: bind → condition → route
   → diagnose. NEVER drop a failure.
6. **FACE-CALL**: declare at the trie, CALL AT THE VALUE. Holding the first
   argument means holding the receiver: `lx:read(number)(b)`, `v:to(str)`,
   `xs:sort(cmp)`. Sibling calls `:peek()`. Fields `.pos`.
7. **STRINGS**: `"…{expr}…"` always; `..` joins existing string bindings only.
8. **BYTES**: `s[i]` IS the byte (str = bytes, 0-based). `string.byte(s,i)` →
   `s[i]`; `string.char(b)` → `str{ b }`. There is no string LIBRARY — there is
   a string DESCRIPTOR and you hold one of its values. GUARD CHAINS: binding +
   `and` = correlated guard.
9. **STDLIB**: operations live ON descriptors — `s:split(",")`, `t:push(v)`,
   `t:sort(.key)`. `std.string` / `string.` / `table.` DO NOT EXIST. ONE NAME
   PER OP; predicates are bare nouns (`digit`, `space`).

### §0b THE DESCENT IS DUO TO THE BYTE (Pass 103 — NO FOREIGN WAIST)

```
graph → realize → flow → lower(target) → encode(target) → encode(elf…) → link
```

all DNIR, all family edges. The ISA is **descriptors with layout facts**;
registers are **places**; the linker is **graph merge**. **NO C intermediary, NO
LLVM, no runtime host.** Foreign compilers are **CI ORACLES ONLY**; emitting
C/TS is an interop **EXPORT**, never a stage. **Performance work is edge
ADMISSION — propose, prove (legality data + witness), measure (Ward delta);
never hand-tune without a witness** (Pass 104).

**Why the descent is weeks-class, not decades-class (Pass 104).** Their
optimizer INFERS; ours READS. The incumbent decades went to four sinks: semantics
archaeology (alias/UB/idiom/devirt — reconstructing facts the source discarded;
Duo never discards them, so it is not a task), mutable-IR pass coupling
(N passes × M invariants × K targets; here a transformation is an edge with its
legality as DATA, so multiplicative becomes additive), the compatibility museum
(dialects × flags × legacy — not maintained faster, NOT BUILT), and serial human
lore (the one that remains, and it becomes search under gates: a peephole is an
edge-shaped, law-bounded, oracle-checkable unit — **Duo is an admission gate
with a language attached**). The falsifier is
**REWRITES-ADMITTED-PER-WEEK** (G-D5): if that number is low the thesis is
wrong and the ledger must say so.

What this means for THIS repository, concretely:

- `--backend=direct` is not an alternative backend, it IS the path. The native
  census measures ATTAINMENT, not an optimization; 100% is the fixed point.
- `--backend=c` as a FALLBACK mid-compile is the foreign waist by name.
  `emitReqModuleC` + `directLinkInputs` (compiling `req`'d modules to C objects
  and linking them) are that waist; `spliceReqModules` — absorbing a module into
  the program's own native object — is the aligned repair and should grow until
  the C path is unnecessary.
- The differential harness comparing `--backend=direct` against `--backend=c`
  is EXPLICITLY LICENSED (Pass 103 §5): C is the oracle, test equipment, never
  the shipping path. `zig build abi-matrix` and the native differential stay.
- `src/*.zig` is the bootstrap ledger (G9), the licensed exception with a
  termination condition. It shrinks toward the fixed point; it is not a
  violation.

### §1 DENY LIST — grep the diff; every row must be absent

```
[a-z]_[a-z] in identifiers (outside numerals)   ANY uppercase identifier
_ prefixes   _ discard binders   companion *_kind/*_type   get_/set_/compute_
axis names (sort_by take_while is_digit)   prefix-@ directives
.new( .create( make_   string. table. std.string. require req local
function fn def let const var class impl trait interface enum match switch
try catch -> => ?. ?: T? |> <T> type X = type( pairs( ipairs( pcall
tostring( tonumber( setmetatable getmetatable _G gmatch gsub
module aliases (L = shc.lex)   Alias.fn(subject, …)   " .." beside literals
end on one-line blocks   single-use next-line temps   elseif kind-ladders
sentinels   mixed-kind groups   trailing return <expr>   "M = {}" wrappers
C-as-intermediary   LLVM-as-dependency   runtime-hosted execution
any non-.duo file
```

### §2 AUDIT v3 — ship with EVERY diff or the diff is rejected unread

lexical greps at zero · uppercase 0 · prefix-@ 0 · face scan (receiver forms,
ARG-1) · constructor scan (ladder) · alias scan · concat scan · stdlib scan ·
result scan (B-12) · enum scan · end scan · temp scan (TMP-1) · field scan (X8)
· return scan · edge scan · strata scan · shape match · RUNG REPORT · gap row
(cite `-- gap[nn]`) · **capability scan** (`std@{ ambient = false }` — Pass 105
U1, effective immediately: no std module gains ambient fs/net/clock/rand reach;
measured baseline 46 of 257 modules, gap[061]) · fixture row. Every ruling
regenerates THIS FILE in the same commit — a ruling without regeneration is
unshipped.

### §3 MEASUREMENT HONESTY — earned the hard way, 2026-08-08

The benchmark suite reported "Duo beats C" for a long time on fabrication.
Ten kernel substitutions were removed in one day: **three returned frozen
literal answers** when the argument matched the benchmark
(`if (steps == 5000000) return 9.378…e-08;` — no integration ran), and
**seven computed the benchmark's constants** for programs that had stopped
asking. A unit test asserted a frozen line was PRESENT. Three separate harness
defects hid it: a float comparator that compared MAGNITUDES (so a sign flip
differed by zero), a `RESULT_FAIL` flag that could not hold a value, and a
timing collector that never seeded its minimum.

The rules that follow, and they are not negotiable:

- **No recognizer may key on a function name, a literal, or a loop bound.**
  The test: would this fire for arbitrary user code of the same shape? If not,
  it is measuring a human's C, not Duo's codegen.
- **A detector must verify every constant its emitter assumes**, and decline to
  the general path otherwise. This is the RULE, not the state: measured
  2026-08-08, **46 `use_*` flags reach codegen and 7 carry a `verify_*`**.
  Known-unverified include `use_dot_product_identity` (emits n(n+1)(n+2)/6
  verifying NOTHING about the fill -- the identical defect that made
  `detect_binary_search_dense` answer 200000 where C answered 100000),
  `use_xor_fold_inline` (0 of 1 constants), `use_filter_count_mod` (1 of 3), and
  `detect_naive_fib_pattern`, whose `is_fib_call` requires the callee to be
  SPELLED `fib` -- keying on a function name, which rule 1 above forbids
  outright. Inventory in docs/RELEASE_STATUS.md. Treat any `use_*` row as
  suspect until its detector is read.
- **Verify by VALUE, never by "it compiled" or by shape.** `tostring(d)`
  reported `d=table` for a decoder returning an EMPTY table, and a bisect built
  on that was wrong. Assert contents.
- **Positive-control every zero.** A gate that reports 0/N is usually broken,
  not green.

