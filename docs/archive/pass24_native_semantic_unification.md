> **HISTORICAL — superseded by `docs/spec/pass100.md`. Not an architecture input.**

# Pass 24 — Native Semantic Unification, Bidirectional Metaprogramming, Lifetime Model, and Descriptor Reconciliation

Status: **specified 2026-08-05**, not yet implemented.

This pass reconciles several architectural directions into a single coherent model. It is
foundational and should influence grammar, semantic analysis, lowering, optimization,
tooling, MCP, LSP, self-hosting, and future language evolution.

## Objectives

1. Preserve Duo's philosophy that types are data, descriptors are ordinary values, and
   generic construction is ordinary computation.
2. Remove foreign syntax and unnecessary language categories accumulated during exploration.
3. Define a native, compiler-friendly model for lifetimes, references, ownership,
   borrowing, views, and pointers.
4. Design bidirectional metaprogramming and projection facilities that integrate with the
   semantic graph without introducing a second language.
5. Ensure every addition strengthens the specialization ladder rather than creating
   parallel systems.

## Core philosophy

**Everything is ordinary semantic data.**

There are not separate universes for values, types, generics, compile-time programs,
schemas, protocols, effects, hardware descriptions, transformations, or projections.
There are only: ordinary values, ordinary functions, descriptor values, compiler
knowledge, specialization, and semantic relationships.

The compiler becomes smarter. The language does not become more fragmented.

## Guiding rules

Before adding any syntax or subsystem, ask:

1. Can this be expressed as an ordinary function?
2. Can this be expressed as an ordinary descriptor?
3. Can this be expressed as a protocol or metatable?
4. Can the compiler infer it?
5. Can this reuse `@` rather than inventing new syntax?
6. Does this reduce concepts?
7. Does it preserve Lua familiarity?
8. Does it improve optimization opportunities?
9. Does it improve AI reasoning?
10. Does it improve semantic density?

If not, reject it.

## Descriptor construction

Descriptors remain ordinary values; descriptor constructors remain ordinary functions.
Never introduce a separate generic language.

```duo
Slice = (Element)
    @{
        ptr: Pointer Element
        len: usize
    }
end
Bytes = Slice Byte
```

`Bytes = Slice(Byte)` is equally valid. Both are ordinary calls; neither is "generic
syntax."

**Rejected:** `Slice[Byte]`, `Map<Key, Value>`, `Result<T, E>`.

## There are no type parameters

Duo has no syntactic category called "type parameter." `Map = (Key, Value)` accepts two
ordinary values that happen to be descriptors. `Buffer = (Element, count, alignment)`
mixes a descriptor and two integers with no reason to split them into different parameter
lists.

The compiler determines descriptor arguments, compile-time-known values, runtime values,
and specialization inputs through semantic analysis — not punctuation.

## Stage is a property of calls

Stage never permanently belongs to a parameter declaration. `repeat = (value, count)` may
specialize differently for `repeat input, n`, `repeat input, 32`, `repeat 0, 64` —
producing runtime, partially specialized, fully specialized, or compile-time realizations
depending entirely on call knowledge.

## Return semantics

Named return variables are **not** part of Duo. Reject Nim-style result bindings.

```duo
make = (T, value)
    converted: T = value
end
```

The final assignment expression becomes the semantic function result; no trailing
`converted` is required. The semantic return exists regardless of representation.

Call-site consumption determines realization: register return, stack return, hidden sret,
forwarded SSA value, ignored value, or removed entirely if dead. A closed-world
specialized clone may lower to a void calling convention when no reachable caller consumes
the result — the semantic function still returns a value.

## Values, views, ownership, and pointers

Do not copy Rust lifetimes, Rust borrow syntax, C pointer syntax, or C++ references.
Define one semantic provenance system with five categories:

- **Value** — independent semantic value.
- **Alias** — another binding to the same identity. No syntax required.
- **View** — a projection into another value, created through ordinary calls:
  `bytes = buffer:view start, count` or `bytes = view buffer, start, count`.
  Views carry origin identity, extent, descriptor, provenance, access capabilities, alias
  information, escape information, and realization candidates. No separate borrow syntax.
- **Owner** — semantic storage owner, usually inferred: stack, arena, shared, foreign,
  device, static, heap, or compiler selected. Ownership is responsibility for lifetime,
  not another source-level type.
- **Pointer** — explicit raw address value, created explicitly via `memory.address value`
  and used through ordinary methods (`:load()`, `:store v`, `:view n`, `:offset n`).
  Pointer operations remain explicit; most user code should operate on values and views.

## Lifetimes

Lifetimes are not source syntax. Lifetimes are provenance. The compiler tracks origin,
escape, ownership, aliasing, access, realization, and destruction.

```duo
head = (items)
    items:view 1, 1
end
```

The returned view derives its lifetime from `items`. No annotation required. When validity
cannot be proven:

```duo
bad = ()
    values = load()
    values:view 1, 1
end
```

the compiler reports a semantic lifetime violation. Repairs: copy, promote, transfer
ownership, or change the API. **The compiler must not silently heap-promote to preserve
invalid semantics.**

## Mutation

Mutation is an inferred effect, not reference syntax. No `&mut`, no mutable reference
types. The compiler knows a function writes a view, mutates its origin, and what the alias
effects are. Public APIs may expose explicit effect contracts through descriptors.

## Ownership transfer

Usually inferred from last use — `queue:send packet` may transfer if `packet` is never
used again. When inference is impossible, `queue:send packet:take()`. `take()` is an
ordinary compiler-visible operation, not language punctuation.

## Regions

Regions are ordinary values. `arena = Arena()`, `tree = parse input, arena`. Everything
allocated within the arena derives lifetime from it; arena destruction ends all derived
lifetimes.

## Pinning

A realization constraint, not a type modifier: `pinned = memory.pin buffer`. Pinning
disappears automatically when no longer required.

## Pointer provenance

Pointers are not integers. They carry origin, alignment, address space, extent, alias
class, owner, target, provenance, and validity. Integer conversion is explicit:
`address = pointer:integer()`. Reconstructing a pointer weakens provenance unless
validated.

## Descriptor relationships

Ordinary descriptor values, not new syntax:

```duo
Projection = @{
    forward = emit
    reverse = interpret
    validate = validate
}
```

Supports forward generation, reverse interpretation, validation, provenance, and
authority. No lens language, no synchronization DSL.

## Bidirectional metaprogramming

A semantic relationship may produce projections. Selected edits to those projections may
be interpreted as semantic change proposals, which become semantic transactions. **Nothing
mutates automatically.**

### Four levels

- **Level 0** — observation. Always allowed.
- **Level 1** — forward generation. Normal.
- **Level 2** — reverse proposal. Opt-in per projection; produces semantic transactions.
- **Level 3** — automatic synchronization. Exceptional; only for relationships proven
  deterministic and reversible. Never global.

### Projection classes

- **One-way** — machine code, IR, optimized binaries, generated prose. Read-only.
- **Partially reversible** — schemas, bindings, declarations, interfaces. Supported edits
  become semantic proposals; unsupported edits remain local.
- **Fully reversible** — only when formally or empirically validated. Never assumed.

### Semantic transactions

Reverse metaprograms never modify compiler state directly; they return transactions
containing semantic IDs, snapshot, proposed operations, provenance, validation, ambiguity,
and affected projections. Compiler services: preview, validate, commit, rollback.

### Authority

Every relationship declares authority: Duo authoritative, foreign authoritative, shared
semantic authority, or multi-master. Default: one canonical semantic source; everything
else is a projection.

### Ambiguity

Reverse edits must never silently guess. Return candidate semantic interpretations; users
or agents choose; validation determines legality.

### Provenance

Every projection records semantic IDs, generator, version, inputs, snapshot, output
identity, validation, authority, and reverse capability. No separate mapping database —
reuse semantic graph provenance.

## Syntax-level metaprogramming

Syntax manipulation remains important for formatting, migration, refactoring, and source
preservation, but must not become the default metaprogramming substrate. Prefer semantic
objects; syntax transformations should usually remain proposal-only.

## Semantic views

Ordinary values:

```duo
PublicUser = view User, @{
    fields = {
        "id"
        "name"
    }
}
```

May be read-only, proposal reversible, or synchronized. No lens operators.

## Runtime relationships

Runtime transformations may declare forward/reverse relationships (`wire = encode value`,
`value = decode wire`). The compiler may exploit round-trip knowledge, adapter
elimination, zero-copy opportunities, and incremental updates. Runtime synchronization
remains separate.

## Incremental bidirectionality

Reverse generation operates on semantic deltas, not whole artifacts. Adding one field
regenerates only affected projections. Composes directly with semantic delta compilation.

## LSP

Generated artifacts expose authority, provenance, reverse capability, snapshot, and
semantic source. Editing a generated artifact previews semantic transactions.

## MCP

Agents never blindly edit generated files. Workflow: inspect provenance → interpret edit →
preview semantic transaction → validate → commit → regenerate.

## Security

Capabilities distinguish observe, generate, reverse interpret, mutate semantic source,
mutate foreign source, regenerate, and patch runtime. Observation is broadly available;
mutation requires explicit permission.

## Performance

Bidirectional support must remain zero-cost when unused: lazy reverse loading, compact
provenance, semantic deltas, cached projections, no runtime overhead, scalable graphs.

## Syntax audit

Reject unless independently justified: bracket generic syntax, angle-bracket generics,
descriptor arithmetic operators, arrow-heavy function/type notation, separate query DSL,
lens operators, synchronization operators, lifetime syntax, borrow syntax, mutable
reference syntax, pointer punctuation imported from Rust or C++, one directive per
compiler feature.

Prefer ordinary functions, ordinary descriptors, ordinary methods, compiler namespaces,
and semantic relationships.

## Relationship to concurrency

Views compose with structured concurrency:

```duo
left = buffer:view 0, midpoint
right = buffer:view midpoint
@all
    process left
    process right
end
```

The compiler proves disjointness, alias legality, lifetime validity, and escape behavior
before parallel realization. Detached tasks require ownership transfer, copying, shared
ownership, or proven long-lived origins.

## Long-term compiler model

The semantic graph tracks identity, descriptors, provenance, ownership, aliasing, views,
effects, realizations, transformations, and projections. Everything above becomes
different projections of one semantic system.

## Success criteria

1. Types remain ordinary descriptor values.
2. Descriptor constructors remain ordinary functions.
3. Generic syntax disappears.
4. Return semantics remain tail-assignment based.
5. Call-site consumption drives realization.
6. Lifetimes remain inferred provenance.
7. Ownership remains semantic responsibility.
8. Views replace explicit borrow syntax.
9. Pointers remain explicit ordinary values.
10. Bidirectional metaprogramming reuses descriptors, transactions, and provenance.
11. Reverse synchronization is opt-in per relationship.
12. No separate lens, schema, generic, ownership, or metaprogramming language is introduced.
13. Existing compiler architecture becomes simpler rather than more fragmented.
14. Lua compatibility and Duo semantic density are both strengthened.

## Governing principle

**The best Duo feature should usually disappear into ordinary Duo.**

The programmer thinks in values, functions, tables, descriptors, and calls. The compiler
thinks in stages, specialization, provenance, ownership, realization, transactions, and
semantic identity. The more compiler knowledge grows, the fewer language concepts the
programmer should need to learn.

---

## Baseline audit against the current tree (measured 2026-08-05)

Measured, not estimated. These are the concrete gaps between Pass 24 and `main`.

### Criterion 3 — "generic syntax disappears": **real parser surface, small blast radius**

This is a genuine breaking language change, not dead example code. `examples/generic_test.duo`
containing `fun identity<T>(value: T): T` **compiles today**, and `src/parser.zig` builds
`type_params` at **6 sites** (function decls, record decls, methods, and three others).

| measure | count |
| --- | ---: |
| `.duo` files using `<T>` generics | 7 |
| `<T>` declaration sites | 13 |
| `parser.zig` sites building `type_params` | 6 |

Tractable. The migration target is already legal Duo — `Slice = (Element) @{...} end` — so
this is deletion plus rewriting 13 call sites, not new design work.

### Syntax audit — "arrow-heavy function/type notation": **the expensive one**

| measure | count |
| --- | ---: |
| stdlib files using `->` | 5 (`agent`, `pool`, `onnx`, `sqlite`, `net`) |
| example files using `->` | 46 |
| total `->` return sites | **147** |

This is ~10x the generics migration and reaches into the standard library, so it changes
published API surface. Sequence it after generics: generics are self-contained, `->` is not.

### Criteria 12/13 — "no fragmentation", "architecture becomes simpler"

**112 distinct `@comp.*` directives** currently exist. This is precisely the "one directive
per compiler feature" antipattern the syntax audit rejects. Pass 24's guiding rules imply
consolidating these into fewer compiler namespaces; today the directive surface grows once
per feature, which is the fragmentation the pass exists to reverse. Reducing this number is
the single clearest measurable proxy for criterion 13.

### Criteria 6-9 — lifetimes, ownership, views, pointers: **greenfield**

| facility | hits in tree |
| --- | ---: |
| `:view` | **0** |
| `memory.address` | **0** |
| `memory.pin` | **0** |

None of the value/alias/view/owner/pointer model exists yet. This is new construction, and
it is the largest body of work in the pass — but it conflicts with nothing, so it can begin
immediately and in parallel with the syntax migrations.

### Criteria 10/11 — bidirectional metaprogramming: **partial foundation already present**

| facility | files referencing |
| --- | ---: |
| provenance | 32 |
| semantic transactions | 6 |

Pass 24 says to reuse semantic-graph provenance rather than build a separate mapping
database — and the provenance substrate is already the most widely established of the new
concepts. The transaction layer (preview/validate/commit/rollback) is the thin missing piece.

### Recommended sequencing

1. **Generics removal** — 13 sites, 6 parser sites, self-contained, immediately closes criterion 3.
2. **View/ownership/provenance model** — greenfield, conflicts with nothing, largest payoff, start in parallel.
3. **Semantic transactions** — build on the 32-file provenance substrate that already exists.
4. **`->` migration** — 147 sites incl. published stdlib API; sequence last, needs a deprecation path.
5. **`@comp.*` consolidation** — 112 → fewer namespaces; the measurable proxy for criterion 13.
