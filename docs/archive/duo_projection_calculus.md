> **HISTORICAL — superseded by `docs/spec/pass100.md`. Not an architecture input.**

# Pass 38 — Maximum Projection Calculus

> **Renumbered 2026-08-05.** This document was drafted as "Pass 36". Pass 40's
> supersession chain (S5) refers to it as **Pass 38**, and Pass 40's citations
> match this file section-for-section (§§1–3, 6, 13 access grammar; §§4–5, 7–12,
> 14–16 retained content; §16's twenty gates). It is renumbered to Pass 38 so the
> chain resolves. A different, larger document is Pass 40's "Pass 36" (Unified
> Algebra, §§10–13 application schema, §21.5, §23, §24 Phases A–H, §25 graveyard);
> it is **not in this repository**. Same for Pass 35 and Pass 39.

> **Surface superseded by Pass 40** ([`duo_universal_semantic_access.md`](duo_universal_semantic_access.md),
> operational: [`pass36_universal_semantic_access.md`](pass36_universal_semantic_access.md)).
> §§1–3, 6, 13 — postfix `value@name`, receiver binding, `expr@(level)@name` — are
> struck by S5 and replaced with `value.@name` and `meta(level)(value)`.
> §§4–5, 7–12, 14–16 are **retained in full**, respelled. §7's ten-rung ladder is
> further compacted to eight rungs by Pass 41 A3, and §8.5's `@x ↔ __x` table is
> relocated to the `@lua` adapter spec by Pass 41 A2.

Canonical spec. Operational projection: [`pass38_projection_calculus.md`](pass38_projection_calculus.md).
Machine-readable catalog: `src/pass36_catalog.zig` (`pass36-semantic-access-catalog-v1`)
— the code still carries the `pass36` name; see the renumbering note above.
Gate: `zig build pass36-gate` (aliases: `semantic-access-gate`, `projection-gate`).
Query: `duo catalog audit gate pass36`.

## Mission

Finalize `@` as Duo's universal bridge between ordinary scope, semantic scope,
descriptors, metatables, metamethods, compiler directives, staging, protocols,
derivations, constraints, generated projections, foreign semantics, optimization
facts, and runtime behavior.

The central rule:

```
.   ordinary access
@   semantic access
```

```
point.x
point@eq
Point@to(str)
@eq
@comp
```

The same access relationship applies to the current lexical scope, an instance, a
descriptor, a function, a module/table, a foreign entity, a compiler semantic
entity, and a generated artifact.

There is no separate protocol API, metatable API, derivation API, directive
namespace mechanism, or trait system. Every one of those is a projection of this
one access principle.

---

## 1. Final meaning of `@`

### 1.1 Bare `@`

A bare `@` denotes the **current effective semantic scope table**: the semantic
entries visible at that source location.

Contents: built-in semantic operations, lexical semantic overrides, module
semantic entries, compiler directives, stage operations, capabilities, locally
generated or injected relationships, imported semantic extensions.

Conceptually `@.eq`, `@.to`, `@.comp`; the canonical compact form is `@eq`,
`@to`, `@comp`. `@eq` means "look up semantic key `eq` in the current effective
semantic scope."

No physical table need exist at runtime when the scope is frozen.

### 1.2 Ordinary accessor

`value.member` accesses an ordinary member/key: `point.x`, `user.name`,
`module.parse`.

### 1.3 Semantic accessor

`value@operation` accesses the effective semantic/metatable entry for
`operation`: `point@eq`, `Point@to`, `stream@iter`, `file@release`,
`function@effects`.

This is the compact replacement for `getmetatable(value).__eq`,
`meta(value).@eq`, and `meta:get(value)(@eq)`. The Lua forms remain supported as
compatibility projections.

### 1.4 Semantic parameterization

`value@operation(parameter)` accesses a parameterized semantic relationship:
`Point@to(str)`, `user@encode(json)`, `message@serialize(wire_v2)`.

Where unambiguous, parenless application is accepted: `Point@to str`. The
formatter preserves the parenless form only when the application spine has one
uniquely valid parse.

---

## 2. Three canonical access forms

### 2.1 Current-scope semantic operation

```
@eq(a, b)
```

Resolves equality through the current semantic scope. The operator projection
`a == b` normalizes to the same semantic call.

### 2.2 Descriptor semantic access

```
Point@to(str)
```

Retrieves the conversion implementation or relationship associated with
descriptor `Point` and target `str`. Initially unbound to a runtime `Point`.

```
to_text = Point@to(str)
text = to_text(point)
```

Parenless and collapsed forms:

```
to_text = Point@to str
text = Point@to(str)(point)
```

The canonical formatter prefers the form that makes semantic grouping clearest.

### 2.3 Instance semantic access

```
point@eq
```

Retrieves equality with `point` bound as receiver/first subject. Therefore
`point@eq(true)` means `@eq(point, true)`, which under the active operator
mapping is `point == true`. All three normalize to one call identity.

`point@to(str)` may mean the receiver-bound conversion `@to(str)(point)`. The
distinction between descriptor-owner and runtime-subject roles is resolved from
the semantic graph, **not** from capitalization rules.

---

## 3. Receiver binding rule

Postfix semantic access performs receiver binding when the accessed operation
accepts the left operand as its subject.

```
equal_to_point = point@eq          -- ≡ @eq(point)
same = equal_to_point(other)
same = point@eq(other)
same = @eq(point, other)
same = point == other
```

No closure allocation is implied. For a frozen call shape the compiler may
represent this as *direct implementation identity + known bound receiver* and
inline both.

### 3.1 Descriptor access is not automatically receiver-bound

`Point@eq` retrieves `Point`'s equality implementation as a first-class callable:

```
eq_point = Point@eq
same = eq_point(a, b)
```

### 3.2 Descriptors themselves may have semantics

`Point@eq(OtherDescriptor)` is legal only when the accessed relation is the
equality operation of the descriptor *value* itself. Tooling must distinguish
"operation owned by `Point` instances" from "operation applied to descriptor
`Point`". This is a semantic distinction, not capitalization magic.

---

## 4. Table definition syntax

One table concept remains canonical:

```
Point: {
    x: f64
    y: f64
    @eq = (a, b) a.x == b.x and a.y == b.y
    @to(str) = (p) "({p.x}, {p.y})"
}
```

`@eq = impl` assigns to semantic key `@eq`. `@to(str) = impl` assigns to the
parameterized semantic relationship `@to(str)`. No brackets needed. Bracketed
computed keys (`[computed_key] = value`) remain supported but are noncanonical
where the specialized semantic-key form is exact.

---

## 5. Scope semantics

### 5.1 Lexical assignment

```
@eq = approximate_eq
```

assigns into the current lexical semantic scope. All equality syntax in that
scope uses the new binding unless a more specific instance/descriptor relation
wins per §7.

```
approximately_equal(a, b, epsilon)
    @eq = (left, right) math.abs(left - right) <= epsilon
    a == b
end
```

No `within` abstraction is needed.

### 5.2 Descriptor assignment

`Point@eq = point_eq` assigns or revises the equality relation owned by `Point`,
subject to descriptor mutability and authority. During construction the
in-literal form is preferred.

### 5.3 Instance assignment

`point@eq = instance_eq` installs an instance-specific override when the value's
semantic model allows instance metatables. Replaces
`getmetatable(point).__eq = …`, `meta(instance)(point).@eq = …`,
`meta:install(point)(@eq)(instance_eq)`.

### 5.4 Module/table semantic assignment

`geometry@eq = geometric_eq` installs a semantic relation at the `geometry`
namespace level, importable/inheritable by normal scope rules.

### 5.5 Assignment target determines semantic level

```
@eq = local_eq            -- lexical scope
point@eq = instance_eq    -- instance
Point@eq = descriptor_eq  -- descriptor
geometry@eq = package_eq  -- namespace/module/table
```

This is the highest-value collapse of the previous metatable-level API. No
separate `instance`, `descriptor`, `package`, or dynamic function argument is
required in the common case.

---

## 6. Explicit hierarchy selection

Most code relies on the direct left-hand semantic owner. When an exact layer must
be selected, semantic access curries through the level:

```
point@(instance)@eq
Point@(descriptor)@eq
geometry@(namespace)@eq
point@(dynamic)@eq
point@(effective)@eq
```

`left@level` selects a semantic view; `selected@operation` accesses the
operation. The compact form `point@instance@eq` is permitted only if grammar and
ordinary semantic-member lookup make it unambiguous. **`point@(instance)@eq` is
the canonical safe form.** Level values are ordinary lower-case semantic values,
not capitalized types or keywords.

### 6.1 Why explicit level access remains necessary

`point@eq` means the effective resolved relationship. An effective relationship
may be readable but not a valid mutation target, because it may originate from
lexical scope, descriptor inheritance, generated derivation, foreign mapping, or
Lua fallback. Therefore `point@eq = impl` has the defined default of
**instance-local assignment**; broader or exact mutation uses explicit level
selection.

---

## 7. Resolution order

For `point@eq(other)` — equivalently `point == other`:

| Order | Level |
| --- | --- |
| 1 | lexical semantic override |
| 2 | instance-specific relation |
| 3 | exact descriptor relation |
| 4 | descriptor hierarchy projection |
| 5 | namespace/module scoped extension |
| 6 | authorized foreign relation |
| 7 | generated/derived relation |
| 8 | Lua metamethod projection |
| 9 | dynamic fallback |
| 10 | structured failure |

The result is one **semantic call object** carrying: active operation identity,
receiver, remaining arguments, descriptor identities, expected return pack, scope
provenance, effects, stage, target, selected implementation.

This follows Duo's canonical call algebra rather than creating a
metamethod-specific optimizer.

---

## 8. Protocol algebra and maximum projection closure

Every explicit semantic relationship is closed under all valid, authorized
projection rules. The closure is larger than inverse and hierarchy.

### 8.1 Endpoint projections

From `Point@to(str) = point_to_text`, derive the views `Point@to(str)`,
`str@from(Point)`, `@to(str) for Point`, `@from(Point) for str`. One edge,
several orientations.

### 8.2 Invocation projections

`@eq(a, b)`, `a@eq(b)`, `a == b`, `Point@eq(a, b)`, `eq_point(a, b)` — normalized
forms, not separately generated wrappers unless reflection requires physical
values.

### 8.3 Partial-application projections

From `@eq(a, b)` derive `@eq(a)` and `a@eq`, both callables awaiting `b`. From
`@encode(json)(value)` derive `encode_json = @encode(json)`,
`value@encode(json)`, `Type@encode(json)` per descriptor/instance role.

### 8.4 Operator projections

| Root | Syntax |
| --- | --- |
| `@eq` | `==` |
| `@cmp` | `<` `<=` `>` `>=` |
| `@add` | `+` |
| `@sub` | `-` |
| `@mul` | `*` |
| `@div` | `/` |
| `@concat` | `..` |
| `@len` | `#` |
| `@call` | ordinary call |
| `@get` | indexing / member access |
| `@set` | indexed / member assignment |
| `@iter` | generic `for` |

Lua operator semantics remain the dynamic compatibility projection.

### 8.5 Lua metamethod projections

| Root | Lua |
| --- | --- |
| `@eq` | `__eq` |
| `@cmp` | `__lt` / `__le` adapters |
| `@add` | `__add` |
| `@get` | `__index` |
| `@set` | `__newindex` |
| `@call` | `__call` |
| `@len` | `__len` |
| `@concat` | `__concat` |
| `@format` | `__tostring` |
| `@release` | `__close` / `__gc` lifecycle projections |

These mappings preserve Lua behavior at unresolved boundaries — a standing
ecosystem invariant.

### 8.6 Structural product projections

For records, authorized operations project field-wise: `@eq`, `@hash`, `@clone`,
`@format`, `@serialize`, `@validate`, `@diff`.

### 8.7 Variant/sum projections

Equality compares tag then payload; hashing combines tag and payload; formatting
exposes variant and payload; serialization emits discriminant and payload;
visitors project over variant cases; tests generate per-variant coverage.

### 8.8 Hierarchy projections

Relations flow through descriptor spread, refinement, specialization, version
lineage, foreign type mapping, schema inheritance, module export/re-export, and
generated descriptor projection. The graph distinguishes: implementation
inheritance, derivation inheritance, availability inheritance, evidence
inheritance, no inheritance.

### 8.9 Constraint projections

An implementation may imply constraints: `@hash` requires equality-compatible
hashing; `@cmp` may imply equality; `@copy` permits physical duplication;
`@share` permits crossing selected concurrency boundaries; `@release` creates an
ownership obligation. Constraints also project backward: *usage requires
hashable* → demand `@hash` → demand required supporting facts.

### 8.10 Evidence projections

Tests, proofs, fuzzing, foreign metadata, and runtime observations attach
evidence to one edge. That evidence projects to optimization legality, foreign
mapping trust, package substitution, release guarantees, generated test coverage,
and LSP/MCP explanations.

### 8.11 Stage projections

One relation may realize at compile time, startup, runtime, adaptive runtime, or
device stage. `Point@to(str)` may be a compile-time conversion for a constant
`Point`, a direct native formatter, a guarded direct call, or a dynamic metatable
call. Same semantic edge, different realization.

### 8.12 Representation projections

One semantic relation may lower to: no operation, register move, scalar
instruction, direct function, inline graph, SIMD, GPU kernel, foreign ABI call,
or Lua closure. Representation remains independent of semantic identity.

### 8.13 Return-consumption projections

Realizations exist for: all returns consumed, first return consumed, selected
positions consumed, no returns consumed, effect-only execution.

```
value, failure = text@to(i64)
value = text@to(i64)
text@to(i64)
```

Unused result work disappears where semantically legal.

### 8.14 Effect projections

Pure, allocating, no-allocation specialization, synchronous, asynchronous,
unsafe/raw, sandboxed foreign. Effects remain graph facts, not separate protocol
names.

### 8.15 Target projections

Scalar CPU, SIMD, GPU, Wasm, foreign implementation, compile-time evaluation. The
realization planner compares valid candidates.

### 8.16 Cross-language projections

Rust traits, Python dunder methods, C callback tables, C++ operators, Java
interfaces, TypeScript structural contracts, SQL schemas/constraints, OpenAPI,
protobuf, Wasm component interfaces. Foreign semantics retain provenance and
uncertainty; they are not flattened into false equivalence. Cross-language
transformations operate over shared semantic capabilities while preserving
language-specific facts.

### 8.17 Tooling projections

LSP completion, hover, navigation, generated virtual source, diagnostics,
semantic refactors, MCP inspection, semantic transactions, benchmark attribution.
Tooling consumes compiler truth and stable IDs rather than reimplementing
resolution.

### 8.18 Documentation and testing projections

Documentation, examples, property tests, fuzz targets, differential tests,
negative tests, benchmark cases, release claims, coverage obligations. Ward
already requires one descriptor source to generate decoders, validators,
handlers, tests, fuzz seeds, and documentation; this calculus generalizes that
pattern.

### 8.19 Reverse and N-directional projections

Generated or foreign projections may submit candidate updates back into the
relation graph: a Rust `Display` edit → candidate `Point@format` change; an
OpenAPI field edit → candidate descriptor field change; a test addition →
candidate constraint or example fact; benchmark evidence → candidate
realization-priority change. Updates remain **validated semantic transactions**,
never silent source mutation.

---

## 9. Projection demand and erasure

Maximum projection surface does not mean maximum eager code generation.
Projection closure is semantic; physical artifacts are produced only when
consumed.

### 9.1 Demand sources

Source code calls it; reflection observes it; a dynamic Lua boundary requires a
metatable; a foreign build requests an adapter; documentation generation requests
it; tests request it; an export manifest requires it; an LSP/MCP query requests
materialization; a build contract requires proof.

### 9.2 Unconsumed projections remain graph facts

If no runtime code observes `Point@eq`, Duo emits no runtime metatable, wrapper
function, trait adapter, closure, or symbol.

### 9.3 Collapsing projections

`Point@to(str)`, `Point@format(string_sink)`, Lua `__tostring`, and Rust
`Display` may share one segmented formatting graph with different boundary
adapters.

### 9.4 Adapter elimination

If two projections are ABI-, ownership-, effect-, and representation-compatible,
the boundary vanishes.

### 9.5 Consumption-specific realization

A formatter called only by a sink constructs no string. A converter whose result
is discarded omits result construction. An iterator consumed by a loop becomes a
loop, not an iterator object. A clone immediately transferred and followed by
release may become ownership transfer.

---

## 10. Additional projection categories

### 10.1 Capability projection

Semantic relations may imply deployment capabilities: filesystem, network, unsafe
memory, device access, process spawning. From these Duo derives sandbox policies,
WASI rights, seccomp profiles, MCP scopes, cloud permission suggestions.

### 10.2 Privacy and trust projection

Values and relations may carry: secret, untrusted, personal, sanitized,
logging-forbidden, export-restricted. These project into logging prevention,
serialization restrictions, boundary validation, generated tests, deployment
policy. The semantic-computing pass already calls for information-flow and
attack-surface projections.

### 10.3 Migration projection

A relationship between descriptor versions generates serialized-data migration,
database migration, live-state migration, foreign API adapters, durable-
continuation migration, compiler-cache migration.

### 10.4 Observability projection

Trace spans, metrics, allocation records, causal events, profiling attribution,
replay boundaries. Instrumentation is removable and attached to semantic
identities.

### 10.5 Security-hardening projection

From bounds, trust, ownership, and effect facts: checks, guards, sanitizers,
hardened variants, unchecked proven variants, fuzz inputs, minimal reproductions.

### 10.6 Build projection

Compile-time semantic dependencies project into build edges, cache keys,
invalidation, hermeticity reports, artifact manifests, semantic linking.

### 10.7 Package compatibility projection

Source, ABI, behavior, effect, and serialization compatibility, plus recommended
semantic version impact.

### 10.8 Agent-action projection

Safe semantic transactions: add implementation, override implementation, block
projection, widen projection scope, derive missing capability, replace foreign
adapter, validate laws, benchmark alternatives.

---

## 11. User control

### 11.1 Explicit implementation

`Point@eq = point_eq` wins over generated/inherited projections.

### 11.2 Opt out

`Point@eq = false` blocks equality projection at that semantic level.
`Point@to(str) = false` blocks that conversion specifically.

### 11.3 Removal

`Point@eq = nil` removes the local decision and reveals lower-priority inherited
or generated candidates.

### 11.4 Scope control

See §5.5.

### 11.5 Exact layer control

See §6.

### 11.6 Projection policy

Fine-grained policies — allow native projection, block foreign projection, allow
test derivation, block string formatting, allow runtime reflection, forbid
dynamic installation — belong to semantic graph authority/policy facts. They must
not require one new surface metamethod each.

---

## 12. `@` and compiler directives

Because bare `@` is the current semantic namespace, compiler directives are
ordinary semantic entries under that namespace: `@comp`, `@target`, `@stage`,
`@noalloc`, `@export`. Each means "look up a compiler-visible semantic value in
the current `@` scope." This unifies rather than duplicates directives and
metamethods.

### 12.1 `@comp`

`@comp.why(call)`, `@comp.assert(condition)`, `@comp.target` remain a scoped
compiler semantic table.

### 12.2 `@(expr)`

Reinterpreted consistently: apply the current scope's default staging/evaluation
semantic operation to `expr` — conceptually `@stage(expr)` or `@eval(expr)` —
while retaining `@(expr)` as the compact established spelling.

### 12.3 `@{ ... }`

Apply current-scope staging/freezing to the ordinary table literal. It is not a
separate table kind.

### 12.4 Semantic shadowing safety

Compiler-critical roots such as `@comp` may be lexically shadowable in ordinary
user scopes, protected in compiler/bootstrap scopes, and addressable through
stable semantic IDs even when shadowed. Tooling must show when a semantic root
has been shadowed.

---

## 13. Grammar

| Form | Meaning |
| --- | --- |
| `@` | current semantic scope expression |
| `@name` | semantic lookup in current scope |
| `expr@name` | semantic lookup on `expr` |
| `expr@name(args)` | parameterized semantic lookup/call |
| `expr@(level)@name` | exact hierarchy-level semantic lookup |
| `@name = value` | semantic binding/assignment |
| `expr@name = value` | semantic assignment |

### 13.1 Precedence

Binding order, tightest last:

```
assignment
boolean
comparison
additive
multiplicative
unary
call/application
semantic access
ordinary member/index access
```

Thus `point@eq(true)` parses as `(point@eq)(true)`, and `Point@to str` parses as
`(Point@to)(str)` — never `Point@(to(str))`.

### 13.2 Parentheses

Parentheses are mandatory whenever multiple parses remain possible:
`Point@to(str)`, `@eq(a, b)`, `point@(instance)@eq`. Parenless `Point@to str` is
accepted only if `str` is one atomic argument with no competing parse. Grammar
decisions must remain formatter-stable and shared with Tree-sitter fixtures.

### 13.3 Incumbent supersession — infix `@` matmul

`src/parser.zig` currently maps the `.at` token to `BinOp.matmul` at precedence
band 19/20, so `point@eq` parses today as `point matmul eq`. `src/sema.zig`
type-checks that operator (tensor inner-dimension inference). The parser already
emits a non-canonical warning for it in `duo_mode`, and two line-based heuristics
(`@` on a later line is an attribute prefix) paper over the ambiguity.

Per the convergence rule, **§13 closes only when infix `@` matmul is deleted** —
not when `expr@name` is merely added alongside it. Tensor products move to
explicit APIs (`Tensor.matmul(a, b)`), which `lib/std/ml/nn.duo` and
`lib/std/simd.duo` already use.

---

## 14. Idiomatic examples

### 14.1 Point

```
Point: {
    x: f64
    y: f64
    @eq = (a, b) a.x == b.x and a.y == b.y
    @cmp = (a, b) compare(a.x, b.x) or compare(a.y, b.y)
    @hash = (p) hash(p.x, p.y)
    @to(str) = (p) "({p.x}, {p.y})"
    @format(sink) = (out, p) out:write("({p.x}, {p.y})")
}
```

```
same = a == b
same = a@eq(b)
same = @eq(a, b)
to_text = Point@to(str)
text = to_text(a)
text = a@to(str)
print("point: {a}")
```

### 14.2 Instance override

```
point@format(sink) = custom_point_format
```

Only `point` receives this override.

### 14.3 Lexical operation world

```
compare_approximately(a, b, epsilon)
    @eq = (left, right) math.abs(left - right) <= epsilon
    a == b
end
```

### 14.4 Conversion inverse

```
Point@to(str) = point_to_text
to_text = Point@to(str)
from_point = str@from(Point)
```

Both reference the same directed edge.

### 14.5 Numeric semantic table

```
numeric_meta = {
    @eq = numeric_eq
    @cmp = numeric_cmp
    @hash = numeric_hash
}

number = { ..number, ..numeric_meta }

@eq = numeric_meta@eq
@cmp = numeric_meta@cmp
```

### 14.6 Runtime hierarchy

```
point@(instance)@eq = instance_eq
Point@(descriptor)@eq = point_eq
geometry@(namespace)@eq = geometric_eq
```

### 14.7 JSON

```
User: {
    id: user_id
    name: str
    @encode(json) = encode_user_json
}

encode_json = User@encode(json)
bytes = encode_json(user)
bytes = user@encode(json)
```

### 14.8 Demand-driven synthesis

```
Point: { x: f64, y: f64 }
set[point] = value
```

demands compatible equality/hash semantics; Duo may synthesize them structurally
when authorized and provable. Opt out with `Point@hash = false`.

### 14.9 Formatting

```
"hi {name}"
out:write("Point: {point}")
```

The compiler may stream formatting directly to `out`, eliminating temporary
strings.

---

## 15. Structural requirements

### 15.1 Projection provenance identity

Every projected form needs its own stable view identity while pointing to one
canonical relation. Without this, reverse edits and diagnostics cannot
distinguish canonical relation / generated Rust projection / Lua metatable
projection / direct native specialization.

### 15.2 Projection conflict algebra

When two projection paths produce competing implementations, Duo needs
deterministic conflict classes: `equivalent`, `more_specific`, `higher_authority`,
`commuting`, `mergeable`, `ambiguous`, `incompatible`, `explicitly_blocked`.

### 15.3 Projection invalidation

Changing `Point@eq` must invalidate only dependent hashes, maps, generated
foreign equality, tests, specialized calls, and proofs — not unrelated `Point`
behavior.

### 15.4 Projection budget and explosion control

Every projection family needs: demand-driven generation, memoization, cycle
detection, depth budget, cost estimate, cancellation, provenance, materialization
threshold.

### 15.5 Projection authority

Each projection records whether it is canonical, source-owned, target-owned,
imported authoritative, generated, local override, runtime override, observed, or
asserted.

### 15.6 Semantic world capture

Closures, tasks, generated functions, and compile-time artifacts may capture the
active `@` semantic scope. The compiler must decide whether a callable captures
semantic identities by stable reference, a frozen semantic environment, dynamic
lookup, or selected implementations. This affects determinism and specialization.

### 15.7 Semantic-world parameters

A function may explicitly accept a semantic environment as data: `run(world)(input)`.
This enables deterministic alternate semantics, testing, simulation, sandboxing,
foreign compatibility, target policy, and replay. No new language mechanism is
required because `@` already denotes the current world.

### 15.8 Projection equality

Duo must distinguish: same canonical relation, same semantic behavior, same
source implementation, same generated projection, same physical realization.
Required for caching and bootstrap reproducibility.

---

## 16. HPLS completion gates

| # | Gate |
| --- | --- |
| 1 | Bare `@` denotes the current semantic scope |
| 2 | `@eq` accesses current-scope equality |
| 3 | `Point@to(str)` accesses `Point`'s conversion relation |
| 4 | `point@eq(true)` binds `point` and calls equality |
| 5 | `point == true` normalizes to the same call |
| 6 | `Point@to(str)` and `str@from(Point)` share one edge |
| 7 | Scope and assignment replace install/bind APIs |
| 8 | Exact hierarchy levels are selectable through curried `@` access |
| 9 | Descriptor, instance, namespace, lexical, foreign, and dynamic semantics share one model |
| 10 | Protocol implications and hierarchy projection are demand-driven |
| 11 | Every projected artifact retains canonical provenance |
| 12 | Generated projections collapse where consumption allows |
| 13 | Unobserved metatables and wrappers are not emitted |
| 14 | Return-pack and effect consumption specialize each projection |
| 15 | Cross-language traits and adapters map to the same relation graph |
| 16 | Reverse edits produce transactions rather than silent mutation |
| 17 | Projection conflicts, invalidation, authority, and budgets are formalized |
| 18 | `@` staging/directive syntax is reinterpreted consistently under the semantic-namespace model |
| 19 | Lua compatibility forms remain supported |
| 20 | Ward and the self-hosted compiler prove zero dynamic semantic dispatch on hot paths |

---

## Final thesis

```
.   ordinary access
@   semantic access
```

One explicit relation:

```
Point@to(str) = point_to_text
```

projects into `point@to(str)`, `@to(str)(point)`, `str@from(Point)`, string
interpolation, direct sink formatting, Lua `__tostring`, Rust `Display`, Python
`__str__`, tests, docs, MCP/LSP facts, and native direct code.

The semantic graph carries the full projection surface. Consumption analysis
decides what physically survives. That is the maximum-HPLS outcome: one character
distinction → ordinary versus semantic access → arbitrary extensibility →
hierarchical scope → metaprogramming → cross-language projection → native
erasure.
