# The anchor: who decides what a sigil means

Pass 100 §2 settles the anchor as ONE concept in three stances:

> **bare `@` NAMES it** (the enclosing descriptor: `@{0,0}`, `next: @`),
> **leading `.` WALKS from it** (three anchor contexts: method scope → my field
> `.pos`; argument position → each element `map(.x)`; descriptor-expected
> position → the case `tok.kind == .eof`), **postfix `X@rel` MOVES it and
> retrieves** (never invokes). There is no prefix `@`: **directives do not
> exist**. `:` is operator polymorphism under STRATA-OP: shape-space operand =
> the IS edge (`name: shape`); callable-member = the INVOKE edge (`a:m(x)`,
> leading `:m()` on the ambient subject).

The spec has this settled. The compiler does not, and the shape of the defect is
not "unimplemented" — it is **two subsystems holding different facts about one
token**, which A3 ONE EDGE forbids: a spelling is a projection of one fact.

This file is the measured inventory. Every row was run on a compiler built from
the commit that carries this file; every observable is a value or a diagnostic
that was actually printed, never an argument from reading the source.

## The asymmetry that produces every row below

    parser.zig    19 decision sites on the `@` token
    sema.zig       0

Sema has no belief about `@` at all. That is not a clean division of labour —
it is the *failure mode*, because sema still type-checks the node the parser
produced, and its rules are permissive enough to admit the wrong node. So the
disagreement never surfaces as a diagnostic in the front end. It surfaces as
one of two things:

* **a C compiler error naming identifiers the user never wrote**, from a
  program `duo check` called clean; or
* **a wrong value**, silently.

Both are recorded per row. A row that is only untidy is marked *cleanup*.

---

## Row 1 — leading `.`: which anchor stance  *(1a, 1b, 1c RECONCILED)*

**Parser believed:** every leading `.` is the *element* stance.
`parse_field_projection` (one call site, in `parse_simple_expr`) desugared
`.name` to the lambda `(__proj_v) __proj_v.name`, unconditionally. Position was
never consulted, so the three anchor contexts §2 decides BY POSITION collapsed
to one. It consults position now — see the settlement under 1b/1c.

**Sema believes:** nothing about anchors — it type-checks the lambda as a value.
Its `==` rule admits any two operands and its arithmetic rule admits a closure,
so the collapsed parse is well-typed.

**Codegen believes:** "this is a projection" is re-derived from SHAPE, by
string-comparing the parameter name `__proj_v` at 7 sites outside the parser.
The stance is carried in an identifier spelling.

### 1a — descriptor-expected position → the case  *(bug: accepted, should be rejected)*

```duo
token: { kind: { name, number, eof }, span: i64 }
k = token.kind.eof
if k == .eof      -- §2 stance 3, §0.3 "ENUM CASES WRITE .eof"
```

`duo check` → `✓ checked — no errors`. `duo compile` →

```
error: invalid operands to binary expression ('duo_token__kind' and 'lua_Value')
 if ((k == lua_val_from_closure((lua_Closure*)duo_make_closure_0()))) {
```

An enum compared against a closure. **RECONCILED** — see the settlement below.
Fixture: `examples/spec100/anchor.duo`, asserting `105`.

### 1b — method scope → my field  *(bug: accepted, should be rejected)*

```duo
lexer: { pos: i64 }

bump(l: lexer): i64
    .pos + 1
end
```

`duo check` → clean, and sema accepts the body against the `: i64` contract.
`duo compile` →

```
error: expected expression
 return ((int64_t)lua_to_num((lua_val_from_closure((lua_Closure*)duo_make_closure_0()) + 1)));
```

Closure plus one.

### 1c — leading `:m()` on the ambient subject  *(bug: accepted, should be rejected)*

Same mechanism through `parse_method_reference`:

```duo
step(l: lexer): i64
    :peek() + 1
end
```

clean under `duo check`; the C backend then fails on `lua_to_num` /
`lua_val_from_closure` in a translation unit that carries no Lua runtime.

### 1b / 1c — the settlement  *(RECONCILED, with one context deliberately left alone)*

**The decision, from Pass 108 R2 and R1 rather than from taste.** R2: a leading
`.name` "is a lens in ARGUMENT position always; the CASE in descriptor-expected
position; neither context ⇒ diagnostic". Pass 100 §2 supplies the third context
R2's "always" is measured against — method scope → my field `.pos`. R1 makes a
leading `:name(` a sibling invoke, and its IS/INVOKE split is already total
("IS never takes an argument group; INVOKE always does"), so the open question
under R1 was never IS-vs-INVOKE — it was *which subject*, the same POSITION
question.

**The mechanism.** Two counters, both facts the parser already has rather than
shapes it infers:

* `call_arg_depth` — incremented in `parse_call_args`, `parse_parenless_call_arg`,
  the method-reference argument list, and the right operand of `|>`. That last
  one is not an afterthought: `p |> .x` means *apply the lens `.x` to `p`*, and
  `codegen_pass3_tests` pins both it and the chained `p |> .x |> .y`.
* `subject` — the enclosing function's FIRST parameter, which §0.6 already makes
  the receiver, recorded in `parse_func_body` where the parameters are parsed
  and restored on exit so nesting cannot leak a receiver outward.

Argument position wins when both hold, which is R2's "in ARGUMENT position
ALWAYS". `ast.Expr` is untouched; `sema.zig` and `codegen.zig` are untouched.

**The context deliberately left alone, and why it is not a dodge.** Inside a
DESCRIPTOR body the first parameter of a slot function is emphatically not the
receiver. §20's own golden `shc/lex.duo` is the proof:

```duo
lexer: {
    pos: u32
    here = () span{ .pos, .pos }
    skip = (p) while b = :peek() and p(b) .pos += 1
}
```

`here` has no parameter at all, and `skip`'s first parameter is the PREDICATE.
Taking either as the subject rewrites `.pos` into `p.pos` and `:peek()` into
`p:peek()` — a wrong value dressed up as a fix for wrong values. So
`descriptor_body_depth` holds the subject unset there and the leading `.` keeps
exactly the reading it has today. This is measured, not assumed: the first cut
of this change took blocks from 5/5 to 3/5 and `shc/lex.duo` named the line.

For the same reason the R2 diagnostic ("neither context ⇒ diagnostic") is NOT
raised yet. With the descriptor-body anchor unbuilt, erroring there would reject
the golden corpus. The subject-less case falls back to the lens reading it has
always had. **That is the remaining piece of rows 1b/1c**, and it needs the
descriptor-body anchor first — the coordinator's note that "bare `@` names the
anchor in a slot body" is the thread to pull.

**The fixture.** `examples/spec100/anchorscope.duo`, **429**, forms floor
16 → 17. `bump`'s tail carries all three positions in one expression —
method-scope `.pos`, sibling invoke `:peek()`, and an argument-position lens
`.tab` inside a body that HAS an ambient subject, which is what proves argument
position BEATS method scope rather than merely coexisting. The value kills each
degenerate reading: the old collapse does not compile; `.pos` resolving to `tab`
gives 229; `:peek()` not invoking does not compile; the argument `.tab` read as
my field applies the integer 2; `reach` inheriting `bump`'s receiver looks for
`l.at`; the chain reading `.at.lo` gives 423. `walk.duo` next door pins the lens
alone at 12.

Before: `duo check` clean, then
`error: invalid operands to binary expression ('lua_Value' and 'int')` on
`lua_val_from_closure(...) + 1`.
After: `bump(l)` answers `42`; `step(l)` answers `42`; the fixture answers `429`.

**Corpus-wide before/after** (the measurement this row was required to carry,
because it moves `map(.x)`-shaped code): `duo check` over all 775 tracked `.duo`
files, diffed PER FILE — **identical**, 714 pass / 61 fail before and after. No
existing leading `.` moved, because every one of them is already in argument
position, a case position, or a descriptor body.

**A pre-existing defect found while fixturing this**, recorded rather than
fixed: applying a lens to a NATIVE RECORD segfaults —

```duo
use = (f, v) f(v)
bump(l: lexer): i64
    t = use(.tab, l)
    l.pos * 100 + t
end
```

exits 139 on a compiler built with this change *stashed*, so it is not this
change. The fixture applies its lens to a bare table for that reason.

---

## Row 2 — postfix `X@rel`: the spec's own spelling is the matmul operator  *(RECONCILED)*

**Parser believed:** `@` between two expressions on ONE LINE is the `matmul`
binary operator (`infix_prec` maps `.at → .matmul`). On a NEW LINE the same
token is an attribute prefix. Three separate loops re-decide this by comparing
`tok.loc.line` against the left operand's line.

**Sema believed:** nothing — it admits the binop.

**Observable** *(bug: accepted, should be rejected)*:

```duo
p: point = { x = 3, y = 4 }
q = p@x            -- §2: MOVE the anchor and retrieve
```

`duo check` → clean, with `warning: infix '@' matmul is non-canonical`.
`duo compile` → `error: use of undeclared identifier 'x'`. The canonical postfix
anchor was unreachable, and what it reached instead was a tensor operator.

### The decision

**The postfix anchor takes the token; matmul keeps it only when spaced.** This
was never a two-sided question, and the deciding evidence is that the repository
already contained a parser that got it right: `lib/std/compiler/parser.duo`
reads postfix `@` as a SUFFIX in `proj_suffixed`, right beside `.field`, `[i]`
and `:m()`, building `(anchor base name)` —
and `examples/pass16_parser_corpus_proof.duo` pins `bar = foo@7` →
`(program (assign bar (anchor foo 7)))`. Two parsers in one repository held
different facts about one token. Alongside that: infix `@` warns
"non-canonical" in `.duo` already, and a grep over 770 tracked `.duo` files
finds exactly three infix uses, all spaced `x @ y`, all inside
`examples/compile_fail/`.

### The mechanism

**ADJACENCY**, which is this parser's own precedent — `peek_glued_assign` reads
`>>=` as `>>` glued to `=` and says "ADJACENCY is the whole rule";
`examples/spec100/glued.duo` is that fixture. `at_is_glued_anchor` requires the
relation name to start in the column right after the `@` ends, on the same line,
and the caller keeps the existing `tok.loc.line > e.loc().line` guard so a
new-line `@hot` attribute (glued on the right too — `@` in column 1, `hot` in
column 2) cannot be swallowed. Column arithmetic rather than a source scan,
because under SH-03 the lexer is sometimes a cursor over a token stream and a
byte-level rule would decide differently depending on which lexer ran.

Every `X@rel` in the spec is written glued (`p@x`, `backend@driver`, `shc@wire`,
`ward@allocation_free`, `point@ordering`); every matmul in the repository is
written spaced. So no existing program changes meaning, and the three tensor
fixtures still report `tensor matmul inner dimension mismatch`.

The parser hands down a resolved `field` node — retrieval, never invocation,
never a `method_call`. `ast.Expr` is untouched; sema and codegen are untouched.

### The fixture

`examples/spec100/anchormove.duo`, **353**, and the `forms` floor ratchets
11 → 12. The value kills each degenerate reading: matmul winning the token does
not compile at all; an anchor answering the first field gives 343; `@` binding
looser than `*` gives `p@(x * 100)` and an undeclared identifier; broken
chaining (`b@inner@x`) does not compile. The walk `p.x` is summed beside the
moves on purpose — two stances of one anchor must land on one fact.

Before: `duo check` clean + matmul warning, then
`error: use of undeclared identifier 'x'`.
After: `p@x` answers `3`; the fixture answers `353`.

### What is still owed

§2's relation space — `point@ordering → (bundle, nil) | (nil, missing)`,
protocol satisfaction, distribution over `&` and `|` — does not exist in the
compiler. The reachable half of MOVE is retrieval against the anchored home, and
that is what landed. `scripts/spec_conformance.duo`'s `P48 anchor X@to(T)` row
now *compiles* and answers `false` instead of failing to build: the spelling is
reachable, the relation is not. That row stays red on purpose and now names one
gap instead of two.

---

## Row 3 — `.@name`: the same anchor, spelled with a dot, answering a different value  *(RECONCILED)*

**Parser believed:** `p.@x` is a `field` node whose *field name is the string*
`"@x"`. The stance is stored in a leading character of an identifier.

**Sema believed:** it is an ordinary field access, and does not check it against
the record's declared fields.

**Codegen believed:** re-derives the stance from that string —
`if (f.field.len > 1 and f.field[0] == '@')` (one site, `codegen.zig`) — and
emits `lua_get_metafield_lit` against a BOXED value.

**Observable** *(bug: a wrong VALUE, silently)*:

```duo
point: { x: i64, y: i64 }
p: point = { x = 3, y = 4 }
a = p.x
b = p.@x
```

`duo check` → clean. Running it printed

```
3
nil
```

A native record has no metatable, so the retrieval answered `nil` rather than
failing. Nothing anywhere in the pipeline said the two spellings name one fact.

### The decision

**`.@name` is a diagnostic.** §2 gives the anchor exactly three stances and this
is not one of them; §0.2 says prefix `@` does not exist. It was never a ruling
in dispute either — Pass 48 put `value.@name` in the GRAVEYARD alongside
`point:@to` and `Point.@to`, and `scripts/spec_conformance.duo` has carried a
row asserting the form ABSENT, *failing on purpose*, since the day the form
landed. The same file also carried a row asserting it PRESENT. Two rows of one
conformance suite demanded opposite answers about one spelling; that row is
retired and the ABSENT row now passes.

### The mechanism

The parser rejects `.@` where it used to build the sigil-carrying field name,
and codegen's `f.field[0] == '@'` arm is deleted with it — with no producer, a
re-derivation from an identifier's spelling is dead weight that can only come
back by accident. Sema is untouched, as in row 1a. `emit_as_lua_value` sites go
188 → 187 (`src/pass4_catalog.zig`), and `pass36_catalog` G6 goes
`.implemented` → `.recorded`, putting `implementedGrammarForms()` back to the
honest 0.

### The fixture

`examples/compile_fail/anchor_metafield.duo` + a `run_fail` row asserting the
message `is not an anchor stance`. **Deliberately not a `forms` value fixture**:
the failure mode was a wrong value that type-checked, so there is no value for a
corpus fixture to compare — that is exactly what made it the dangerous row. The
pin has to be the diagnostic.

Before: `duo check` clean, program prints `3` then `nil`.
After: `row3.duo:4:7: error: '.@x' is not an anchor stance`, with a hint naming
the three stances and pointing at `.x`.

`examples/pass38_semantic_access_g6.duo` is deleted — its entire subject was the
retired form. `ext/tree-sitter-duo/grammar.js` still carries a
`semantic_field_expression` rule; a grammar that accepts more than the compiler
is a lint rather than a wrong value, and that file has a live owner, so it is
left as named follow-up.

---

## Row 4 — `:` IS vs INVOKE  *(bug: a legal form rejected)*

**Parser believes:** `:` is INVOKE unless one of five lookahead tests fires
(type keyword / `{` / `@` / `*` or `?` / a name followed by `=`). The IS edge is
therefore recognised only when an initializer follows.

**Sema believes:** nothing — the decision never reaches it.

**Observable:**

```duo
p: point       -- §2: shape-space operand = the IS edge
```

→ `error: expected function arguments`. The declaration-without-initializer form
of the IS edge is read as a method call. This one fails loudly, so it is the
least dangerous row on the page — but it is the same defect: a positional
decision made by lookahead in one subsystem, with no second opinion available.

---

## Row 5 — prefix `@`: five surfaces sharing a sigil  *(cleanup)*

`docs/directive_erasure.md` already inventories this: `ast.Attribute` plus ~70
`std.mem.eql` reads across 19 `.zig` files carry a prefix-`@` directive ontology
that §2 says does not exist. Thirteen files read attribute names by string
comparison. No value is wrong today — the spellings are compatibility surface
and some are load-bearing — so this is a cleanup, not a bug, and it is out of
scope here beyond naming it as the fifth `@` surface.

---

## The settlement, and who owns the decision now

Under the pipeline the owner gave —

    lexical compatibility -> one canonical syntax graph -> one semantic graph -> …

— the owner of "which anchor stance is this token" is the **canonical syntax
graph**, i.e. the parser. It is the only component that knows the position, and
for the case stance it is also the component that *declared the cases*, in
`stmt_from_descriptor`.

So row 1a is settled there and only there:

* `stmt_from_descriptor` records each case it declares against its case-set. A
  name a SECOND case-set claims is marked ambiguous rather than overwritten.
* `at_anchor_case` recognises descriptor-expected position as a POSITION — the
  operator just consumed is an equality and the next token is `.` — not as a
  shape.
* `parse_anchor_case` resolves the case and emits the *same resolved `field`
  node* that the long-hand `token.kind.eof` produces.

Sema and codegen are unchanged. They consume a fact that is already decided;
there is nothing left for them to re-derive and therefore nothing left to
disagree about. Unknown and ambiguous cases are two distinct diagnostics — the
ambiguous one is the case where a silent pick would have produced a wrong value
rather than a failed build.

Gated on the parse having SEEN a case-set, so a file that declares none keeps
the element stance it had. That is deliberate scope control, and it is also the
honest boundary: rows 1b, 1c, 2, 3 and 4 are still open, and each one above
carries the program that shows it.
