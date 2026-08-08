# Duo — Final Semantic Access and Projection Calculus

Canonical spec (Pass 36 algebra, Pass 40 surface ruling, Pass 41 native-first amendment).
Operational projection: [`pass36_universal_semantic_access.md`](pass36_universal_semantic_access.md).
Machine-readable catalog: `src/pass36_catalog.zig` (`pass40-semantic-access-catalog-v2`).
Gate: `zig build pass36-gate` (aliases: `semantic-access-gate`, `projection-gate`).
Query: `duo catalog audit gate pass36`.

## The final principle

```
.        the only access operator
@name    the only semantic marker
meta     the only hierarchy surface — and it is just a curried function
one edge the only truth — everything else is a projection of it
demand   the only reason anything becomes physical
```

---

## 0. Supersession chain (normative)

Pass 39's governance rule stands: **any future contradiction of this canon ships
with a supersession record, or it is not canon.**

| ID | Ruling | Supersedes | Rationale |
| --- | --- | --- | --- |
| **S4** | Prefix `@` only; postfix, infix and `:@` forms rejected permanently | Pass 39's ruling that postfix `value@op` superseded Pass 36's prohibition | Re-scored on surface / power / performance / meaning: everything postfix bought with grammar, composition buys without it |
| **S5** | Pass 38 §§1–3, 6, 13 superseded by §1 below; Pass 38 §§4–5, 7–12, 14–16 retained in full | Pass 38 access grammar, receiver binding, hierarchy-selection syntax | The projection closure is graph-level and independent of spelling, so nothing in it is lost by respelling |
| **S6** | Pass 39 R1 dissolves; R2–R6 carry forward | Pass 39 R1 (descriptor-vs-subject role inference) | Retrieval is never receiver-bound, so the ambiguity class R1 arbitrated cannot arise |
| **S7** | Backwards compatibility removed as a design constraint; Lua is a foreign projection target | Every "public Lua-compatible behavior never changes" clause across Passes 34–40 | Compat was never a decisive input to the scorecard; deleting it removes two ladder rungs, one inheritance mechanism, and the `__` namespace |

### 0.1 The scorecard that produced S4

| Criterion | Postfix surface (`point@eq`, `x@(level)@op`) | Final surface (`point.@eq`, `@eq(a,b)`, `meta(level)(value)`) |
| --- | --- | --- |
| **Surface area** | Full projection closure | **Identical** — the closure is graph-level; nothing is lost |
| **Power** | `@(level)@` is pure syntax; receiver binding is a special rule | **Greater** — `meta(level)` and `meta(level)(value)` are ordinary curried *values*: passable, mappable, storable |
| **Performance** | Foldable, but role inference leaves ambiguity points that resist proof | **Greater** — `.@` retrieval is never receiver-bound, so the descriptor/instance ambiguity class *does not exist*; more sites are trivially provable |
| **Semantic meaning** | `@` becomes an operator with three unrelated jobs | **Greater** — `.` remains the only access operator; `@name` is a key namespace, not an operator; `point.eq` and `point.@eq` coexist |
| **Grammar cost** | Three patch rulings, a precedence table, a staging-collision rule | One token class (`@name`) + one spine rule |

The decisive observation: **everything the postfix surface bought with new
grammar, this surface buys with composition.** Receiver binding is replaced by
operation-first invocation plus operator projection plus declared partial
application — three existing mechanisms. Level selection is replaced by an
ordinary curried function. The one-character ergonomic loss is repaid by the
disappearance of an entire ambiguity class and two patch rulings.

---

## 1. Final surface grammar

The complete surface, exhaustively. Anything not listed is not semantic-access
syntax.

```
@name                     semantic identity in the current world
                          (@eq, @to, @cmp, @hash, @iter, @release, @comp, @target)
@                         the current semantic world itself, as a value
                          (@.eq ≡ @eq; passable: run(world)(input))

@name(args)               invocation through the current world:  @eq(a, b)
@name(param)              parameterized relation selection:      @to(str)
@name(param)(subject)     two-group application spine:           @to(str)(p)
@name param               parenless FIRST group, atomic arg only: @to str
                          (subsequent groups always need parens: (@to str)(p))

value.@name               semantic member access — retrieval, never binding:
                          point.@eq is the effective equality implementation
value.@name(param)        parameterized slot:  point.@to(str)

@name = v                 STATEMENT position: lexical world binding (static)
{ @name = v }             TABLE literal: descriptor slot declaration
value.@name = v           assignment at the value's own level (per mutability)

meta(value)               effective semantic view (ordinary stdlib callable)
meta(level)(value)        exact-level view; level ∈ lexical instance descriptor
                          package foreign dynamic effective all
meta(level)(value).@name  read at level;   ... = v  write at level

@(expr)                   staging application (prefix-only, no collision)
@{ ... }                  staged/frozen table literal
```

### 1.1 The graveyard — permanently rejected

| Form | Reason |
| --- | --- |
| `value@name` | S4: postfix gives `@` three unrelated jobs |
| `value @ name` | infix `@` reads as an arithmetic operator |
| `value:@name` | `:` is sugar for ordinary members; it never touches semantic space |
| `value@(level)@name` | S5: replaced by the ordinary curried value `meta(level)(value)` |
| duplicate `@to`/`@from` storage | one edge, two views; declaring both ends is the duplicate-truth error |
| arity-inferred currying | grouping comes from the declared schema, never punctuation or arity |
| automatic parameter permutation | argument order is part of the operation's identity |
| install/bind APIs | scope and assignment already express every level |
| `within`-style helpers | a lexical world binding names the scope directly |
| `getmetatable` / `setmetatable` | A8: deleted; `meta(dynamic)(v)` does everything |
| `@eq(bool)(comparable)` | static facts as curry levels; result descriptors are graph facts |
| `~=` | A5: `!=` wins on universal intuition |
| `__eq` / `__index` / `__tostring` as canon | A2: the `__` namespace is deleted |
| `__index`-chain inheritance | A4: descriptor hierarchy projection is the only inheritance |

### 1.2 Formatter rules

Prefer `@to(str)(p)` over flattened `@to(str, p)` — the group boundary is the
specialization boundary and should be visible. Prefer `a == b` over `@eq(a, b)`
where the operator projection is active and unambiguous. Preserve the parenless
form only when exactly one parse exists. Never abbreviate `meta(level)(value)`.

---

## 2. Semantic model

* **The edge.** A protocol implementation is one relation — operation +
  parameters + descriptors + implementation + scope + evidence + provenance.
  `point.@to(str)` and `str.@from(point)` are two views of one edge; declaring
  both is the duplicate-truth error. True reverse conversion is a second edge,
  never assumed.
* **The algebra.** Identity, inverse, implication (`@cmp → @eq`; `@hash` never
  from `@eq` alone), hierarchy projection with five inheritance kinds,
  product/sum lifting, parameter hierarchies (`@encode(json)` →
  `@encode(json.pretty)` only via declared policy). All derivation is
  demand-driven, lazy, witnessed, and overridable.
* **The closure.** Endpoint, invocation, partial-application, operator, Lua
  adapter, structural, hierarchy, constraint, evidence, stage, representation,
  return-consumption, effect, target, cross-language, tooling, doc/test, and
  reverse projections — plus capability, privacy, migration, observability,
  hardening, build, compatibility, and agent-action projections. Projection is
  semantic; materialization is demanded: unobserved metatables, wrappers, and
  adapters do not exist physically.
* **The application schema.** Every call normalizes to a spine; grouped/curried
  equivalence comes from the operation's declared schema, *never* from
  punctuation or arity. Implementations stay plain functions; partial
  application is derived.
* **Worlds.** Bare `@` is the current world; directives (`@comp`, `@target`,
  `@stage`) are entries in it; lexical bindings are static; closures capture
  worlds frozen-by-stable-reference by default; `@comp` is shadowable in user
  scopes, protected in bootstrap scopes, always addressable by stable ID.

### 2.1 Resolution ladder — eight rungs

Pass 41 A3 compacted the ladder from ten rungs. The old rungs 8 (Lua metamethod
projection) and 9 (dynamic metatable fallback) were two rungs only because Lua's
lookup rules had to be replayed verbatim.

```
1 lexical override          (static — costs nothing if absent)
2 instance semantic layer   (capability-gated: sealed records forbid,
                             plain tables allow)
3 exact descriptor relation
4 descriptor hierarchy projection   (the only inheritance mechanism)
5 package/namespace extension
6 authorized foreign relation       ← Lua values enter HERE, like all foreign values
7 generated/derived relation
8 dynamic semantic layer    (Duo-defined @get/@set/@call lookups in the value's
                             dynamic table — not Lua metatable walk rules)
→ structured failure (nil, err — a return pack, never an exception)
```

Every rung is visible to tooling; every selection is witnessed; `@comp.why`
explains the rung and the reason for every skip.

The sealed-world collapse condition gets *simpler* — two fewer rungs to disprove
— so more sites reach the rung-3 proof with less evidence. A performance win
purchased purely by deleting inherited semantics.

### 2.2 Sealed-world collapse

```
no lexical overrides (static) ∧ instance semantics forbidden by descriptor
∧ descriptor sealed ∧ package layer frozen (L1) ∧ world frozen-captured
⇒ rungs 1, 2, 4–8 provably empty
⇒ the ladder collapses to rung 3 as a PROOF
```

Guarantees: identity conversion = 0 instructions; `point.@to(str)` and `@to(str)`
are compile-time constants; sealed `@iter` = native loop with zero iterator
allocation; `@release` tier 1 inlined at last use; derived structural ops become
direct field code; no closure, wrapper, metatable, registry search, or
intermediate string.

**G5 fails any compiler hot region resolving above rung 3.** Three-valued slots
(implementation / `false` blocked / `nil` reveal) carry witnesses; blocked-slot
hits are manifest counters.

---

## 3. The native-first amendment (Pass 41)

Backwards compatibility is removed as a design constraint. Design inputs are now
only: HPLS, power, surface area, projection logic and algebra, semantic clarity,
intuitiveness, elegance.

* **A1 — compat reclassified.** Duo semantics are canonical. Lua is a supported
  foreign projection with provenance, trust, and an adapter boundary — the same
  machinery as every other foreign target. `__eq`, `__index`, `__tostring`
  adapters are emitted **on demand at the boundary only**, exactly as a Rust
  `Display` impl would be.
* **A2 — the `__` namespace is deleted from canon.** There is one semantic
  namespace: `@name`. Double-underscore names survive solely inside the `@lua`
  adapter as emission targets. Consequence of real weight: the dynamic semantic
  layer becomes **ordinary Duo data** — `meta(dynamic)(v)` returns a plain table
  whose keys are semantic identities. No shadow key convention, no string-name
  registry, no reserved-prefix rules.
* **A3 — the ladder compacts 10 → 8 rungs.** See §2.1.
* **A4 — one inheritance mechanism.** Descriptor hierarchy projection is the
  only inheritance in the language. `@get` on the dynamic layer is a lookup
  operation, not a delegation chain; chained delegation is a library pattern
  written *with* `@get`, never a semantic rule the compiler must honor.
* **A5 — operator inventory chosen on merit.** Operators remain a closed,
  compiler-owned projection set (no user-defined operators — that guard is
  elegance, not compat), but the contents are selected: `!=` replaces `~=`;
  `== < <= > >= + - * / % ^ .. #` retained on merit; integer/float division and
  future operator questions are decided by numeric speciation (L8), free of
  precedent. The operator↔root mapping lives in `duo-b/spec.duo` as descriptor
  data.
* **A6 — `:` retained, on merit.** `value:method(args)` receiver-binding sugar
  for **ordinary members** stays; it earns its place independent of its origin.
  It never touches semantic space: `value:@eq` remains in the graveyard.
* **A7 — errors are return packs, canonically.** `nil, err` is the one canonical
  error surface. `pcall`-style dynamic unwinding is demoted to the `@lua`
  boundary adapter and the E3 bridge.
* **A8 — `getmetatable` / `setmetatable` deleted.** `meta(dynamic)(v)` and
  assignment do everything they did.

### 3.1 The gains ledger

Enumerated so the price of ever reversing this amendment is visible.

| # | Gain | Kind |
| --- | --- | --- |
| 1 | One semantic namespace (`@name`); `__` deleted | clarity |
| 2 | Dynamic layer is ordinary Duo data | elegance, power |
| 3 | Ladder 10 → 8 rungs; simpler sealed-world proof | performance, provability |
| 4 | One inheritance mechanism | clarity, provability |
| 5 | Operator set on merit (`!=`, future L8 freedom) | intuitiveness |
| 6 | Error surface singular (`nil, err`) | clarity, performance |
| 7 | Duo-B shrinks: no compat-replay semantics to freeze | self-hosting |
| 8 | Conformance shrinks: Lua parity moves to the adapter suite | stabilization |
| 9 | Ward differentials become foreign-boundary tests | measurement honesty |
| 10 | Every future design question loses one veto-holder | velocity |

### 3.2 Kept even though compat no longer demands it

Recorded so these survive future zealotry: tables as the one aggregate; `nil`;
1-based indexing *as the default realization of sequence descriptors*
(revisitable by L5/L8 evidence, not by taste); `..` for concat; the stateless
iterator triple as `@iter`'s canonical projection (genuinely the zero-allocation
design, independent of origin); `:` sugar.

**Heritage is not a reason to keep anything — but neither is it a reason to
delete what independently wins.**

---

## 4. Idiomatic guidelines

### 4.1 The ten idioms

1. **Operators first.** Write `a == b`, `a < b`, `#t`, `s1 .. s2`. The operator
   *is* the semantic call; reaching for `@eq(a, b)` in ordinary code is noise.
2. **`@op(...)` when the operation is the subject.** Comparators as values
   (`sort(items, @cmp)`), explicit invocation in generic code, lexical-world work.
3. **`value.@op` to hold an implementation.** Retrieval is for reflection,
   composition, and mapping — never for ordinary calling.
4. **Declare at the source, in the constructor.** Post-hoc assignment is for
   revision and instrumentation, not primary definition.
5. **Never declare both ends.** `@to(str)` on the source *is* `str.@from(point)`.
6. **Let demand synthesize.** Don't hand-write structural `@eq`/`@hash`/`@clone`
   for plain sealed records; use them and let derivation fire, or block with
   `= false`.
7. **`@format(sink)` is primary; `@to(str)` is its projection.** A hand-written
   `@to(str)` that just concatenates is the smell.
8. **Name the scope, not a helper.** The function whose *name* states the
   semantic variation owns the `@eq = ...` binding.
9. **`meta(level)` only when the level matters.** Code littered with
   `meta(descriptor)` is fighting the resolution ladder instead of using it.
10. **`false` to forbid, `nil` to yield, silence to inherit.** Three intentional
    states; choosing none is also a choice.

### 4.2 The five smells

* An `@` form where an operator exists (`@eq(a,b)` mid-expression).
* `getmetatable`/`setmetatable` in Duo-authored code (they do not exist).
* A curry level carrying a static fact (`@eq(bool)(...)`).
* Eager materialization: building metatables, wrappers, or adapters "just in
  case" — demand does it, erasure removes it.
* Manual reimplementation of a derivable operation with no semantic difference —
  it forfeits structural lifting through future descriptor evolution.

---

## 5. Worked examples

### 5.1 The canonical record

```
point: {
    x: f64
    y: f64
    @eq = (a, b) a.x == b.x and a.y == b.y
    @cmp = (a, b) compare(a.x, b.x) or compare(a.y, b.y)
    @format(sink) = (out, p) out:write("({p.x}, {p.y})")
}
```

Everything below is derived, demanded, or projected — none of it is written:

```
same   = a == b                        -- operator → rung 3, direct, inlined
order  = a < b                         -- projected from @cmp
text   = @to(str)(a)                   -- projected from @format(sink)
print("point: {a}")                    -- interpolation → sink segments, no temp string
h      = set[a]                        -- demands @hash → structural synthesis
copy   = a:clone()                     -- @copy on a sealed f64 record → register/memcpy
from_p = str.@from(point)              -- same edge as @to(str), no second entry
__tostring, __eq                       -- materialized ONLY at a dynamic Lua boundary
Rust Display / tests / docs            -- projections on demand, provenance-linked
```

### 5.2 Holding and composing implementations

```
to_text  = point.@to(str)              -- retrieval (never receiver-bound)
labels   = points:map(to_text)
sort(points, @cmp)                     -- operation as ordinary value
sort(points, meta(descriptor)(point).@cmp)   -- exact-level, bypass overrides
```

### 5.3 Lexical world

```
compare_approximately(a, b, epsilon)
    @eq = (l, r) math.abs(l - r) <= epsilon
    a == b                             -- rung 1, resolved at compile time
end
```

Outside this function, rung 1 is provably empty and costs nothing.

### 5.4 Hierarchy, override, blocking

```
entity: { id: id, @eq = entity_eq }
user:   { ..entity, name: str }        -- @eq inherits ONLY if valid/liftable
admin:  { ..user, @eq = admin_eq }     -- explicit wins
secret: { ..user, @eq = false }        -- no equality: not inherited, not derived,
                                       --   no foreign projection
meta(package)(geometry).@eq = geo_eq   -- package extension, policy-gated
meta(instance)(p).@format = debug_fmt  -- one value only
```

### 5.5 Parameter hierarchy

```
user: {
    @encode(json) = encode_json
    @encode(json.pretty) = encode_pretty
}
bytes = @encode(json)(u)               -- exact
bytes = @encode(json.compact)(u)       -- parent-parameter projection, if policy allows
enc   = @encode(json)                  -- first group only: a converter value
many  = users:map(enc)
```

### 5.6 The performance trio

```
stream: {
    @iter = (s) cursor_iter(s)         -- sealed ⇒ the loop IS the realization,
}                                      --   no iterator object

file: {
    @release = (f) os.close(f.fd)      -- tier 1: inlined at proven last use
}                                      -- tier 2: lexical close
                                       -- tier 3: managed — @comp.why.drop explains

view = buffer.@ref(Slice)(0, n)        -- proven ⇒ raw pointer;
                                       -- unproven ⇒ boxed handle + @comp.why.boxed
```

### 5.7 The compiler eating its own calculus

```
diagnostic: {
    severity: severity
    span: span
    @format(sink) = (out, d) render_diag(out, d)
}
-- Hot-path requirement: resolves at rung 3 under the sealed-world proof.
-- G5 fails the build if the manifest shows otherwise.
```

---

## 6. Conformance and sequencing

* **Gates:** the twenty completion gates are retained, respelled — gate 1: bare
  `@` is the world; gate 3: `point.@to(str)` accesses the relation; gate 4:
  `@eq(point, true)` and `point == true` normalize to one call; gate 8: exact
  levels via `meta(level)(value)`; gate 19: Lua is a foreign projection with its
  own adapter test suite. Each gains positive, negative, and guarantee
  (manifest-row) conformance entries.
* **Implementation sequence:** the phases in
  [`pass36_universal_semantic_access.md`](pass36_universal_semantic_access.md).
  Phase 1 buries the graveyard in the grammar corpus before any new form is
  added; application normalization proves the parenless spine rule; `meta` /
  `meta(level)` land before exact-level writes.
* **Duo-B entry:** the §1 grammar goes into `duo-b/spec.duo` + Tree-sitter
  fixtures first; the sealed-world subset enters Duo-B by self-application;
  the dynamic layer (rung 8) last.
* **Witness requirements:** edge identity, projection path, hierarchy path,
  inverse view, synthesis path, selection, scope, guards, allocation, return
  demand, erased intermediates, fallback — feeding L6, C5, U11, and U12
  unchanged.

---

## 7. Closing

The language stops carrying a second language inside it. Lua becomes what Rust
and Python already were: a projection target with an adapter, provenance, and a
test suite.

One explicit relation:

```
point: { @to(str) = point_to_text }
```

projects into `point.@to(str)`, `@to(str)(point)`, `str.@from(point)`, string
interpolation, direct sink formatting, a Lua `__tostring` adapter, Rust
`Display`, Python `__str__`, tests, docs, MCP/LSP facts, and native direct code.

The source stays as small as the `point` example. The compiler derives the rest —
only when justified, each derivation witnessed, each projection traceable to its
edge, and each hot path provably collapsed to a direct call.

**Maximum surface, maximum power, maximum performance, one character of syntax.**
