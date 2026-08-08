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

## Row 1 — leading `.`: which anchor stance

**Parser believes:** every leading `.` is the *element* stance. `parse_field_projection`
(one call site, in `parse_simple_expr`) desugars `.name` to the lambda
`(__proj_v) __proj_v.name`, unconditionally. Position is never consulted, so the
three anchor contexts §2 decides BY POSITION collapse to one.

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

### 1b — method scope → my field  *(bug: accepted, should be rejected — OPEN)*

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

Closure plus one. Open: closing this changes what a *bare* leading `.` means and
would move existing `map(.x)`-shaped code, so it is a separate landing.

### 1c — leading `:m()` on the ambient subject  *(bug: accepted, should be rejected — OPEN)*

Same mechanism through `parse_method_reference`:

```duo
step(l: lexer): i64
    :peek() + 1
end
```

clean under `duo check`; the C backend then fails on `lua_to_num` /
`lua_val_from_closure` in a translation unit that carries no Lua runtime.

---

## Row 2 — postfix `X@rel`: the spec's own spelling is the matmul operator

**Parser believes:** `@` between two expressions on ONE LINE is the `matmul`
binary operator (`infix_prec` maps `.at → .matmul`). On a NEW LINE the same
token is an attribute prefix. Three separate loops re-decide this by comparing
`tok.loc.line` against the left operand's line.

**Sema believes:** nothing — it admits the binop.

**Observable** *(bug: accepted, should be rejected)*:

```duo
p: point = { x = 3, y = 4 }
q = p@x            -- §2: MOVE the anchor and retrieve
```

`duo check` → clean, with `warning: infix '@' matmul is non-canonical`.
`duo compile` → `error: use of undeclared identifier 'x'`. The canonical postfix
anchor is unreachable, and what it reaches instead is a tensor operator.

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
