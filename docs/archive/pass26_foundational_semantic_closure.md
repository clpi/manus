> **HISTORICAL — superseded by `docs/spec/pass100.md`. Not an architecture input.**

# Pass 26 — Foundational Semantic Closure

> **Mission:** Close unresolved architectural seams before adding capabilities.  
> **North star:** One descriptor system, call model, return-pack model, effect system, transformation registry, provenance model, and semantic graph — with **canonical rules** at every boundary.  
> **Supersedes:** Nothing in Pass 23–25; **extends** them with closure on identity, operations, protocols, boundaries, and decisions.  
> **Numbering:** Pass 26 follows Pass 25 (semantic unification). Pass 24 (calls/concurrency/Lua) and Pass 25 remain active.

## 0. Why this pass exists

Most major Duo ideas now exist. The danger is **fragmentation at seams** where several systems overlap without one canonical semantic rule:

- ordinary library functions vs compiler intrinsics vs `@comp.*`
- Lua metamethods vs Duo protocols vs foreign operators
- descriptor identity vs runtime identity vs representation
- compile-time vs runtime vs foreign vs process boundaries

Pass 26 does **not** add broad syntax. It nails down foundations and defines one **flagship vertical proof** to exercise them.

## 1. Guiding unifier — Semantic boundaries are first-class values

Almost every major Duo goal crosses a boundary. Today these are discussed separately. They converge on one model:

```
semantic boundary
├── source domain
├── destination domain
├── adaptation
├── representation
├── effects
├── ownership
├── lifetime
├── trust
├── failure
├── cost
├── proof
└── eliminability
```

The optimizer's cross-language question becomes: **Can this boundary be removed, fused, specialized, narrowed, guarded, migrated, or realized differently?**

Schema: `src/pass26_semantic_boundary.zig`  
Workstream: **P26-WS17**

## 2. Five critical foundations (M0 → M3 priority)

| # | Foundation | Schema | Gate |
|---|------------|--------|------|
| 1 | Semantic operation identity registry | `pass26_semantic_operation.zig` | P26-G01 |
| 2 | Protocol attachment without namespace pollution | `pass26_protocol_attachment.zig` | P26-G02 |
| 3 | Descriptor identity + normalization | `pass26_descriptor_identity.zig` | P26-G03 |
| 4 | Semantic boundaries + adapter elimination | `pass26_semantic_boundary.zig` | P26-G04 |
| 5 | Decision / contradiction registry | `pass26_decision_registry.zig` | P26-G05 |

## 3. Semantic operation identity registry (§3)

**Problem:** Privileged operations must not rely on magical spellings (`user:set`, `descriptor:with`, `value:take`).

**Rule:** The compiler recognizes **stable semantic operation identity**, not function name, module path, source spelling, method name, or magic attribute.

Example declaration (ordinary Duo):

```duo
memory.view = (origin, start, count)
    ...
end
```

Compiler association:

```
Semantic.Memory.View
```

Core identities (non-exhaustive seed):

- `Semantic.Memory.View`, `Semantic.Memory.Address`, `Semantic.Memory.Pin`
- `Semantic.Ownership.Transfer`
- `Semantic.Task.Spawn`, `Semantic.Task.Join`
- `Semantic.Shape.Project`, `Semantic.Convert`, `Semantic.Iterate`, `Semantic.Release`

Each registry entry defines:

- semantic identity (stable ID)
- accepted argument relationships
- effects
- result provenance
- transformation permissions
- fallback behavior
- dynamic protocol mapping
- Lua metamethod mapping
- LSP/MCP presentation

**Relationship to Pass 23:** `pass23_protocol_registry.zig` provides kernel ops + Lua aliases. Pass 26 elevates these to **full semantic operation records** with effects and provenance. Kernel ops map to `Semantic.*` paths; they are not the identity itself.

**Rejected:** name-based privilege, `@magic` attributes, module-path intrinsics.

## 4. Protocol attachment without namespace pollution (§4)

**Problem:** Language-visible behavior must attach to descriptors without pretending protocols are ordinary fields.

Conceptual model:

```
descriptor + protocol identity + implementation callable
```

The semantic graph owns the relationship. Explicit compiler form:

```
@comp.protocol Point, Protocol.Format, format_point
```

Compact source syntax may follow; **architecture precedes syntax**.

`.protocols` tables are **not** magical by name — attachment is keyed by **protocol semantic identity** in the graph.

Unifies:

- Lua metamethods
- Duo-native protocols
- foreign operator mappings
- lifecycle, formatting, conversion, iteration, calls, indexing, assignment

Pass 23 §11–12 metamethod kernel is the compatibility layer; Pass 26 §4 is the attachment model.

## 5. Identity versus equality versus representation (§5)

Separate notions (never conflate):

| Notion | Purpose |
|--------|---------|
| semantic identity | graph node stable ID |
| runtime object identity | allocation / handle identity |
| descriptor identity | type/schema node |
| structural equality | same shape/fields |
| value equality | same observable value |
| representation equality | same bits/layout |
| foreign identity | imported origin + fingerprint |
| observational equivalence | behaviorally indistinguishable |

Examples:

```duo
A = Slice Byte
B = Slice Byte
```

**Rule (M0):** `A` and `B` share **descriptor semantic fingerprint** when construction is pure and canonicalized; **declaration identity** may differ if provenance differs; **instance identity** is per-evaluation unless interned.

```duo
a = Point{x = 1, y = 2}
b = Point{x = 1, y = 2}
```

Value-equal; not necessarily runtime-identical.

Affects: specialization keys, caches, metatables, open extension, foreign types, hot reload, bidirectional projections, package versioning, semantic merge.

## 6. Canonical descriptor normalization and interning (§6)

Four layers (must not conflate):

1. **descriptor semantic fingerprint** — canonical semantic content hash
2. **descriptor declaration identity** — source/provenance-specific ID
3. **descriptor instance identity** — runtime descriptor value identity
4. **selected physical realization** — layout/ABI/target facts

Rules:

- Normalization is deterministic across builds for pure descriptors
- Source provenance remains separate when semantic identity merges
- Open descriptors prevent interning until sealed
- Target-specific layout belongs to **realization identity**, not semantic fingerprint

## 7. Descriptors versus ordinary mutable tables (§7)

**Rule:** Descriptor construction captures an **immutable semantic snapshot**. Later mutation of source builder tables does **not** mutate the descriptor unless an explicit semantic transaction changes it.

Concepts:

- frozen value, snapshot, open semantic descriptor, mutable builder data
- descriptor revision, derived descriptor, live semantic relationship

`@{}` frozen tables are the straightforward case. `make_descriptor fields` followed by `fields.z = f64` does **not** change `Point`.

## 8. Stage-dependency model (§8)

Stages: parse, expand, semantic, compile, link, load, startup, runtime, adaptive, deploy, device.

Every stage transition is one of:

- evaluate, lift, lower, residualize, persist, serialize, migrate

Each transition records: source stage, destination stage, allowed effects, identity preservation, caching rules, failure behavior, provenance.

`@` is not a universal escape hatch — it participates in this model.

## 9. Effect polymorphism and containment (§9)

Higher-order functions inherit callee effects without generic-effect syntax:

```
effects(each call) = effects(iteration) + effects(operation call shape)
```

Public reflection must express: inherited, contained, transformed, discharged, conditional effects.

Examples: transactional `run`, sandbox containment, cache effect removal.

Priority: high (P26-WS07).

## 10. Failure behavior for metaprogramming (§10)

Reverse projection failures are **descriptor-backed outcomes**, not generic exceptions:

- UnsupportedEdit, Ambiguous, Stale, Lossy, Invalid, Forbidden

Same failure architecture as errors, traps, cancellation, process exits, foreign conventions.

## 11. Text, bytes, and foreign strings (§11)

Do not collapse into one `str`. Distinct descriptors:

- `Slice Byte`, `Text`, `CString`, `Utf16`, `Symbol`

Affects FFI, shell, parsers, paths, semantic hashing, serialization.

## 12. Paths, URLs, commands, identifiers (§12)

Distinct values, not plain text with conventions:

- `Path`, `Url`, `Command`, `PackageId`, `SemanticId`, `Target`, `EnvironmentKey`

## 13. Package and module identity (§13)

Every entity includes: project, package, module, declaration, version lineage, foreign origin, semantic fingerprint.

Cross-language metaprogramming fails if `User` in Rust and `User` in TypeScript are identified only by names.

## 14. Stable source emission and preservation (§14)

Pipeline:

```
semantic edit → language-valid change → concrete syntax preservation
→ formatter integration → minimal native diff
```

Record: semantic target, original concrete node, retained trivia, insertion policy, native formatter, emitted diff, reversibility.

## 15. Cross-language semantic trust levels (§15)

Explicit lattice:

parsed → declared → compiler-reported → ABI-validated → differentially-tested → proven → runtime-observed → user-asserted → opaque

Transformations declare minimum required trust.

## 16. Compiler-derived semantic versioning (§16)

Compute impact dimensions:

- source, binary, behavioral, serialization, effect, performance-contract, target compatibility

Suggest version impact from evidence, not manual labels alone.

## 17. Schema and state migration as general transformation (§17)

One architecture everywhere:

```
old descriptor + new descriptor + transformation + evidence + failure policy + rollback
```

No separate migration systems for DB, serialization, caches, workflows, foreign APIs.

## 18. Concurrency contract algebra (§18)

Guarantees as canonical semantic data: order preserved/irrelevant, bounded, backpressured, cancellable, idempotent, retryable, partitionable, associative, commutative, deterministic, isolated, realtime.

Example:

```duo
aggregate.laws = @{ associative, commutative }
```

Unlocks parallel reduction, distributed execution, SIMD, GPU, incremental recomputation.

## 19. Semantic manifest artifact (§19)

Every build/package/import emits a compact manifest:

- semantic identities, public descriptors, effects/capabilities, ABI/layout
- runtime requirements, targets, dependencies, safety guarantees
- optimization contracts, provenance, evidence, compatibility fingerprints

Portable surface for Duo, agents, registries, deployment, LSP/MCP, foreign tools.

## 20. Decision / contradiction registry (§20)

Machine-readable decision record with statuses:

`proposed | under_grammar_audit | accepted | implemented | experimental | deferred | rejected | superseded`

Every agent queries before proposing syntax.

Schema: `src/pass26_decision_registry.zig`  
Extends: `docs/catalogs/rejected_ideas.md` (Pass 6 REJ-*)

Known open tensions (seed entries P26-D01–P26-D11):

- calls with parentheses vs whitespace application
- descriptor field syntax `:` vs assignment
- top-level directives vs contract descriptors
- methods on descriptors vs namespace pollution
- dynamic descriptors vs compile-time assumptions
- canonical function syntax variants
- Lua syntax deprecated vs permanently accepted
- tail-demand inference scope beyond tail region
- ~~table literal key forms~~ → **closed** (P26-D11 / GR-006)

## 21. Flagship vertical proof (§21)

One end-to-end slice exercises all critical foundations:

```
C struct
→ imported descriptor
→ generated Duo-safe view
→ generated Rust binding
→ direct ABI call
→ zero-copy adapter elimination
→ semantic diff after C header change
→ reverse proposal from Rust edit
```

Gate: **P26-G20** (open until slice lands).

Workstream: **P26-WS21**

## 22. Implementation ordering

### M0 (this pass) — constitution + schemas + gates

- [x] Pass 26 plan + index
- [x] `pass26_catalog.zig` — 21 workstreams + completion gates
- [x] Schema stubs for foundations 1–5 + decision registry
- [x] `pass26_gate.zig` — M0 proofs
- [x] Wire catalog, build, CLI gate

### M1 (in progress) — wire into sema/graph/foreign

- [x] `pass26_descriptor_intern.zig` — fingerprint + intern registry at alias lift
- [x] Semantic graph nodes carry `semantic_fingerprint`, `declaration_identity`, `intern_slot`, recursion metadata
- [x] `pass26_wiring.zig` — semantic op lookup, foreign boundary metadata, dynamic/mutability helpers
- [x] `ForeignFunc` carries `boundary_id` + `calling_conv` (P26-B02)
- [x] Sema traces semantic ops + foreign boundaries via debug_trace
- [ ] Init graph in sema (P26-G21)
- [ ] Mutability kinds on Symbol assignments (P26-G23)
- [ ] Dynamic value spec side table (P26-G24)
- [ ] Transform engine boundary provenance on foreign calls
- [ ] Flagship vertical proof (P26-G20)

### M2 — protocol attachment in semantic graph

- Graph edges: descriptor ↔ protocol ↔ callable
- Lua metamethod projection from attachment table

### M3 — descriptor fingerprint + interning in types/sema

- `Pair i32, str` collapse rules
- Open vs sealed descriptor interning policy

### M4 — boundary object + adapter elimination pass

- Chain detection: Rust → C ABI → bytes → Wasm → Duo
- Eliminability analysis in transform engine

### M5 — vertical proof slice (§21)

## 23. Non-regression invariants

- Pass 24: bare `a` ≠ `a()`; `[[` long-string
- Pass 25: tail-demand propagation (not backward local search); descriptors as ordinary values; no bracket generics
- Pass 23: kernel protocol registry remains single Lua alias source
- Pass 6: rejected ideas remain unless superseded with evidence in decision registry

## 24. Cross-references

| Pass | Relationship |
|------|--------------|
| Pass 23 | Kernel ops + Lua aliases → upgraded to semantic operation records |
| Pass 25 | Descriptor/lifetime/projection models → identity + normalization closure |
| Pass 20 | Cross-language MP + trust → trust lattice + vertical proof |
| Pass 6 | REJ-* → decision registry extension |
| Pass 5 | C import → vertical proof starting point |

---

## Part II — Extended closure (30 additional seams)

The original 20 seams (§3–§21) address operation identity, protocols, descriptor identity, boundaries, and decisions. **Part II** closes the high-leverage holes that determine whether Duo becomes one semantic architecture or subtly incompatible systems.

### Second unifier — Semantic domains (§55)

After **semantic boundaries**, the next broad unifier is **semantic domains**. Every value, call, descriptor, resource, effect, and transformation operates within one or more domains:

- language, stage, ownership, execution, trust, target, failure, representation, authority

A **boundary connects domains**. A **transformation** changes or removes a boundary. A **proof** justifies movement. A **realization** selects concrete domains.

Schema: `src/pass26_semantic_domain.zig`  
Workstream: **P26-WS52**

Domains are internal structure — not required user syntax.

### Extended seams summary (§25–§54)

| § | Seam | WS | Priority |
|---|------|-----|----------|
| 25 | Initialization graph | P26-WS22 | critical |
| 26 | Recursive descriptors + fixed points | P26-WS23 | critical |
| 27 | Mutability semantics | P26-WS24 | critical |
| 28 | Canonical dynamic value model | P26-WS25 | critical |
| 29 | GC/native ownership interop | P26-WS26 | critical |
| 30 | Hashing model | P26-WS27 | critical |
| 31 | Deterministic iteration | P26-WS28 | high |
| 32 | Reflection authority | P26-WS29 | high |
| 33 | Meta-circular dependency control | P26-WS30 | critical |
| 34 | Transformation composition | P26-WS31 | high |
| 35 | Evidence invalidation | P26-WS32 | critical |
| 36 | Numerical semantics as descriptors | P26-WS33 | high |
| 37 | Units/dimensions | P26-WS34 | high |
| 38 | Calling convention descriptors | P26-WS35 | critical |
| 39 | Unwind/stack semantics | P26-WS36 | critical |
| 40 | Debug under optimization | P26-WS37 | high |
| 41 | Reproducible builds | P26-WS38 | high |
| 42 | Supply-chain authenticity | P26-WS39 | high |
| 43 | Partial/degraded operation | P26-WS40 | high |
| 44 | Query DoS control | P26-WS41 | high |
| 45 | Language evolution migration | P26-WS42 | high |
| 46 | Capability negotiation | P26-WS43 | high |
| 47 | Multi-target divergence | P26-WS44 | high |
| 48 | Resource model | P26-WS45 | critical |
| 49 | Semantic test identity | P26-WS46 | high |
| 50 | Negative capability proofs | P26-WS47 | high |
| 51 | Cost model interface | P26-WS48 | high |
| 52 | Optimization stability | P26-WS49 | high |
| 53 | Semantic privacy | P26-WS50 | high |
| 54 | Certainty terminology | P26-WS51 | high |

### Top-ten closure priorities (§56)

Force closure on these **before** expanding syntax or headline features:

1. Descriptor normalization, identity, and recursion
2. Canonical dynamic representation
3. Mutability and initialization semantics
4. GC/native ownership interoperability
5. Semantic operation and protocol identity
6. Semantic domains and boundaries
7. Stage dependency and meta-circular convergence
8. Evidence invalidation
9. ABI/calling convention descriptors
10. Resource and unwind semantics

Catalog: `pass26_catalog.ten_closure_priorities`

### M1 extended — schema → sema/graph wiring (in progress)

Priority order follows §56 top-ten, then remaining Part II seams, then flagship proof (§21).

- [x] `pass26_descriptor_intern.zig` — fingerprint normalization, intern registry, recursion classification
- [x] `semantic_graph` alias lift — `semantic_fingerprint`, `declaration_identity`, `intern_slot`, `recursion`, `completion`
- [x] `pass26_wiring.zig` — delegates fingerprint to intern module; semantic op + foreign lift metadata
- [ ] Initialization graph in sema (P26-G21)
- [ ] Recursive fixed-point body resolution at seal time (P26-G22 completion)

**Do not** add broad syntax until top-ten gates P26-G21–G30 reach `partial` or better.

### Table literal key forms (§57)

**Decision:** P26-D11 (accepted) · **Grammar:** GR-006

| Form | Syntax | Meaning |
| --- | --- | --- |
| Identifier | `name = value` | Literal field name |
| Quoted string | `"key" = value` | Literal non-identifier key |
| Computed | `[expr] = value` | Evaluate `expr` as key |

- No alternate computed-key operator — Lua `[ ]` is canonical.
- Canonical examples avoid brackets for identifier-like keys.
- Formatter preserves brackets when semantically necessary.

This is syntax closure, not a new type system — it keeps descriptor/table literals aligned with Lua while making the literal-vs-computed distinction explicit for hashing, iteration order, and serialization workstreams (P26-WS27–WS28).

