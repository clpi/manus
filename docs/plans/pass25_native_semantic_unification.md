# Pass 25 — Native Semantic Unification, Bidirectional Metaprogramming, Lifetime Model, and Descriptor Reconciliation

**Status:** M0 constitution (2026-08-05)  
**Mission:** Reconcile descriptor construction, lifetimes, views, ownership, return realization, and bidirectional metaprogramming into one coherent semantic model — without fragmenting the language.

> **Numbering:** This document captures the **semantic unification** constitution. **Pass 24** remains the authoritative track for unified calls, Lua superset, and execution-graph concurrency (`pass24_execution_concurrency_lua_supremacy.md`). Pass 25 builds on Pass 23 (metaprotocols), Pass 22 (compiler architecture), Pass 20 (metaprogramming harness), and Pass 24 (concurrency + views).

## Validate

```bash
zig build pass25-gate
duo catalog | jq '.pass25'
```

## Repository owners

| Area | Files |
| --- | --- |
| Constitution + catalog | `docs/plans/pass25_native_semantic_unification.md`, `src/pass25_catalog.zig` |
| Gate proofs (M0) | `src/pass25_gate.zig` |
| Semantic categories | `src/pass25_semantic_category.zig` |
| Lifetime provenance | `src/pass25_lifetime_model.zig` |
| Projection + transactions | `src/pass25_projection_model.zig` |
| Descriptor / return / stage | `src/sema.zig`, `src/types.zig`, `src/semantic_graph.zig` |
| Bidirectional meta | `src/transform_engine.zig`, `src/proof_carrying.zig`, Pass 20 harness |
| Lowering / realization | `src/dnir_lower.zig`, `src/realization.zig`, `src/codegen.zig` |
| Tooling | `~/x/duo-lsp`, `~/x/duo-mcp` |

---

## §0 Purpose

This pass reconciles several architectural directions into a single coherent model.

**Objectives:**

1. Preserve Duo’s philosophy that **types are data**, descriptors are ordinary values, and generic construction is ordinary computation.
2. Remove foreign syntax and unnecessary language categories accumulated during exploration.
3. Define a native, compiler-friendly model for lifetimes, references, ownership, borrowing, views, and pointers.
4. Design bidirectional metaprogramming and projection facilities that integrate with the semantic graph without introducing a second language.
5. Ensure every addition strengthens the **specialization ladder** rather than creating parallel systems.

This pass is foundational. It influences grammar, semantic analysis, lowering, optimization, tooling, MCP, LSP, self-hosting, and future language evolution.

---

## §1 Core philosophy

Duo converges toward one principle:

**Everything is ordinary semantic data.**

There are not separate universes for values, types, generics, compile-time programs, schemas, protocols, effects, hardware descriptions, transformations, or projections.

Instead there are:

- ordinary values
- ordinary functions
- descriptor values
- compiler knowledge
- specialization
- semantic relationships

The compiler becomes smarter. The language does not become more fragmented.

---

## §2 Guiding rules

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

If not, **reject it**.

---

## §3 Descriptor construction

Descriptors remain **ordinary values**. Descriptor constructors remain **ordinary functions**. Never introduce a separate generic language.

**Canonical:**

```duo
Slice = (Element)
    @{
        ptr: Pointer Element
        len: usize
    }
end
Bytes = Slice Byte
```

**Also valid:**

```duo
Bytes = Slice(Byte)
```

Both are ordinary calls. Neither is “generic syntax.”

**Reject canonical forms like:**

```duo
Slice[Byte]
Map<Key, Value>
Result<T, E>
```

*(Parser may accept some bracket forms as compatibility; they must not become canonical Duo.)*

---

## §4 No type parameters — stage is a property of calls

Duo does not have a syntactic category called “type parameter.”

```duo
Map = (Key, Value)
Buffer = (Element, count, alignment)
```

accept ordinary values — descriptors, integers, integers — in one parameter list. The compiler determines descriptor arguments, compile-time-known values, runtime values, and specialization inputs through **semantic analysis**, not punctuation.

**Stage never permanently belongs to a parameter declaration.**

```duo
repeat = (value, count)
```

may specialize differently for `repeat input, n`, `repeat input, 32`, `repeat 0, 64`. The same function may produce runtime, partially specialized, fully specialized, or compile-time realization depending on **call knowledge**.

---

## §5 Return semantics

Named return variables are **not** part of Duo. Reject Nim-style `result` bindings.

```duo
make = (T, value)
    converted: T = value
end
```

The final assignment expression becomes the semantic function result. Do not require `converted` afterwards — the semantic return exists regardless of representation.

**Call-site consumption** determines realization:

| Realization | When |
| --- | --- |
| register return | consumed value, ABI fits |
| stack return / hidden sret | large aggregate |
| forwarded SSA value | inline / tail |
| ignored / removed | dead return, discard consumption |

A closed-world specialized clone may lower to a void calling convention when no reachable caller consumes the result. The **semantic function still returns a value**.

*(Aligns with Pass 23 P23-WS4/WS5; rejects P23-D02 `@return`.)*

### §5.1 Tail-demand propagation (result lineage)

**Name this precisely:** *tail-demand propagation* or *result-demand inference* — **not** “return the last assigned variable.”

Pass 23 correctly rejected arbitrary unique live-out guessing (P23-D01). Pass 25 **supersedes** that deferral with a principled model grounded in the semantic graph and SSA lineage.

#### Every value-producing operation has a result

Assignments yield assigned values. Compound assignments yield updated values. Calls yield return packs. *(Pass 23 established this.)*

#### Only the tail region satisfies result demand

```duo
calculate = (x): i64
    value = expensive x
    log value
end
```

The tail statement is `log value`, not `value = expensive x`. The compiler does **not** search backward for a matching local.

Instead: propagate **result demand** into the tail statement or tail control-flow region.

If `log` is **result-transparent** (zero positions, preserves lineage, ordered after production), `calculate` may still return `value` through proven SSA lineage — not backward heuristics.

#### Explicit return descriptors create demand

```duo
double = (x): i64
    value = x * 2
end
```

Demand: one `i64` on every normal exit. Tail assignment yields `value`. No redundant trailing `value` read.

`:void` → zero positions. `:i64, Error` → two positions. Symmetric and explicit.

#### Caller consumption affects realization, not meaning

| Call | Semantic function | Realization |
| --- | --- | --- |
| `double 10` | still yields `i64` | discard value, preserve effects if any |
| `x = double 10` | still yields `i64` | bind to `x` |
| pure + discard | unchanged meaning | dead call elimination |

`CallShape.return_consumption` and return-pack specialization select representation; they do **not** redefine the callable’s principal semantic pack.

#### Tail control-flow: loop-carried values (supersedes P23-D01)

```duo
factorial = (n): i64
    value = 1
    for i = 2, n
        value *= i
    end
end
```

Demand: one `i64`. Tail region: the loop. Unique loop-carried chain:

`value₀ = 1` → `valueₙ₊₁ = valueₙ * i` → `phi(initial, updated)`.

Zero iterations → seed `1`. This is control-flow proof, not “guess last local.”

**Ambiguity — must diagnose, never guess:**

```duo
bad = (x): i64
    a = compute_a x
    b = compute_b x
    for item in items
        update item
    end
end
```

→ `tail region does not determine one i64 result` with listed live-outs.

#### Tail-demand rules (catalog `TailResultRule`)

| Rule | Pattern |
| --- | --- |
| A | tail assignment |
| B | tail compound assignment |
| C | tail call forwards pack |
| D | tail branch → phi |
| E | tail if with unique carried assign |
| F | tail loop unique carried assign |
| G | multi-position loop-carried chains |
| H | unconsumed tail call: effects only |

Schema: `src/pass25_tail_result_model.zig`. Resolver: `src/tail_result_demand.zig`. Full spec: [`pass25_tail_result_demand.md`](pass25_tail_result_demand.md).

#### What not to do

- Last-compatible-local backward search
- Magic `result =` bindings
- Name/capitalization heuristics
- Caller-defined semantic return packs
- Silent ambiguity resolution
- Forced construction of unused returns

#### Tooling (LSP/MCP)

Expose: semantic return pack, result-demand graph, result lineage, consumed positions, discard specialization, transparent trailers, ambiguity candidates, ABI realization selection.

**Implementation owner:** Pass 25 WS3 + WS17; sema + `semantic_graph.zig` + `dnir_lower.zig`. Gate: `P25-G15`, `P25-G16`.

---

## §6 Values, views, ownership, and pointers

Duo does **not** copy Rust lifetimes, borrow syntax, C pointer syntax, or C++ references. Define **one semantic provenance system**.

### Five semantic categories

| Category | Meaning |
| --- | --- |
| **Value** | Independent semantic value |
| **Alias** | Another binding to the same identity (no syntax required) |
| **View** | Projection into another value via ordinary calls |
| **Owner** | Semantic storage owner (stack, arena, shared, foreign, device, static, heap, compiler-selected) |
| **Pointer** | Explicit raw address value with provenance metadata |

**Views** — created through ordinary calls:

```duo
bytes = buffer:view start, count
-- or
bytes = view buffer, start, count
```

Views carry: origin identity, extent, descriptor, provenance, access capabilities, alias information, escape information, realization candidates. **No separate borrow syntax.**

**Pointers** — explicit:

```duo
pointer = memory.address value
pointer:load()
pointer:store value
pointer:view count
pointer:offset amount
```

Most user code operates on values and views; pointer operations remain explicit.

Schema: `src/pass25_semantic_category.zig`.

---

## §7 Lifetimes

Lifetimes are **not** source syntax. Lifetimes are **provenance**.

The compiler tracks: origin, escape, ownership, aliasing, access, realization, destruction.

```duo
head = (items)
    items:view 1, 1
end
```

The returned view depends upon `items`. No lifetime annotation required.

**Invalid example:**

```duo
bad = ()
    values = load()
    values:view 1, 1
end
```

Reports a **semantic lifetime violation**. Repairs: copy, promote, transfer ownership, change API. The compiler must **not** silently heap-promote to preserve invalid semantics.

Schema: `src/pass25_lifetime_model.zig`.

---

## §8 Mutation

Mutation is not encoded into reference syntax. Mutation is an **inferred effect**.

```duo
clear = (view)
    for i = 1, view.len
        view[i] = 0
    end
end
```

The compiler knows: writes view, mutates origin, alias effects. No `&mut`. No mutable reference types. Public APIs may expose explicit effect contracts through descriptors.

---

## §9 Ownership transfer

Ownership is usually inferred from **last use**.

```duo
queue:send packet
```

If `packet` is never used again, ownership may transfer. When inference is impossible:

```duo
queue:send packet:take()
```

`take()` is an ordinary compiler-visible operation — not language punctuation.

---

## §10 Regions and pinning

**Regions** remain ordinary values:

```duo
arena = Arena()
tree = parse input, arena
```

Everything allocated within the arena derives lifetime from it. Arena destruction ends all derived lifetimes.

**Pinning** is a realization constraint, not a type modifier:

```duo
pinned = memory.pin buffer
```

Pinning disappears automatically when no longer required.

---

## §11 Pointer provenance

Pointers are not integers. They carry semantic information: origin, alignment, address space, extent, alias class, owner, target, provenance, validity.

Integer conversion is explicit:

```duo
address = pointer:integer()
```

Reconstructing a pointer weakens provenance unless validated.

---

## §12 Descriptor relationships

Relationships are **ordinary descriptor values** — not new syntax.

```duo
Projection = @{
    forward = emit
    reverse = interpret
    validate = validate
}
```

Supports forward generation, reverse interpretation, validation, provenance, and authority. No lens language. No synchronization DSL.

---

## §13 Bidirectional metaprogramming

**Definition:** A semantic relationship may produce projections. Selected edits to those projections may be interpreted as semantic change proposals. Those proposals become **semantic transactions**. Nothing mutates automatically.

### Four levels

| Level | Name | Policy |
| --- | --- | --- |
| 0 | Observation | Always allowed |
| 1 | Forward generation | Normal compilation / codegen |
| 2 | Reverse proposal | Opt-in per projection → semantic transactions |
| 3 | Automatic synchronization | Exceptional; only when proven deterministic and reversible; never global |

Schema: `src/pass25_projection_model.zig`.

---

## §14 Projection classes

Every projection declares:

| Class | Examples | Reverse |
| --- | --- | --- |
| **One-way** | machine code, IR, optimized binaries, generated prose | read-only |
| **Partially reversible** | schemas, bindings, declarations, interfaces | supported edits → proposals |
| **Fully reversible** | only when formally or empirically validated | never assumed |

---

## §15 Semantic transactions

Reverse metaprograms never modify compiler state directly. They return **semantic transactions** containing:

- semantic IDs
- snapshot
- proposed operations
- provenance
- validation state
- ambiguity candidates
- affected projections

Compiler services: **preview**, **validate**, **commit**, **rollback**.

---

## §16 Authority and ambiguity

Every relationship declares **authority**: Duo authoritative, foreign authoritative, shared semantic authority, or multi-master. Default: one canonical semantic source; everything else is a projection.

Reverse edits must **never silently guess**. Return candidate semantic interpretations; users or agents choose. Validation determines legality.

---

## §17 Provenance

Every projection records: semantic IDs, generator, version, inputs, snapshot, output identity, validation, authority, reverse capability. Reuse semantic graph provenance — no separate mapping database.

*(Builds on `transform_engine.zig`, Pass 12 proof-carrying, Pass 20 harness.)*

---

## §18 Syntax-level metaprogramming

Syntax manipulation remains important for formatting, migration, refactoring, and source preservation. It must **not** become the default metaprogramming substrate. Prefer semantic objects. Syntax transformations should usually remain **proposal-only**.

---

## §19 Semantic views

Views are ordinary values:

```duo
PublicUser = view User, @{
    fields = {
        "id"
        "name"
    }
}
```

Views may be read-only, proposal-reversible, or synchronized. No lens operators.

---

## §20 Runtime relationships

Runtime transformations may declare forward/reverse relationships:

```duo
wire = encode value
value = decode wire
```

The compiler may exploit round-trip knowledge, adapter elimination, zero-copy opportunities, and incremental updates. Runtime synchronization remains separate from compile-time bidirectionality.

---

## §21 Incremental bidirectionality

Reverse generation operates on **semantic deltas**, not whole artifacts. Adding one field regenerates only affected projections. Composes with semantic delta compilation (Pass 22).

---

## §22 LSP, MCP, and security

**LSP:** Generated artifacts expose authority, provenance, reverse capability, snapshot, and semantic source. Editing a generated artifact previews semantic transactions.

**MCP agent workflow:**

1. inspect provenance
2. interpret edit
3. preview semantic transaction
4. validate
5. commit
6. regenerate

**Capabilities:** observe, generate, reverse interpret, mutate semantic source, mutate foreign source, regenerate, patch runtime. Observation is broadly available; mutation requires explicit permission.

---

## §23 Performance

Bidirectional support is **zero-cost when unused**:

- lazy reverse loading
- compact provenance
- semantic deltas
- cached projections
- no runtime overhead when unused
- scalable graphs

---

## §24 Syntax audit — rejected unless independently justified

| Rejected | Prefer |
| --- | --- |
| bracket / angle-bracket generic syntax | ordinary descriptor calls |
| descriptor arithmetic operators | ordinary functions |
| arrow-heavy function/type notation | assign-form + descriptors |
| separate query DSL | semantic graph queries |
| lens / synchronization operators | descriptor relationships |
| lifetime syntax | inferred provenance |
| borrow / mutable reference syntax | views + inferred mutation effects |
| Rust/C++ pointer punctuation | explicit pointer values + methods |
| one directive per compiler feature | `@comp.*` namespaces + inference |

Registry: `src/pass25_catalog.zig` → `rejected_syntax`.

---

## §25 Relationship to Pass 24 concurrency

Views compose with structured concurrency:

```duo
left = buffer:view 0, midpoint
right = buffer:view midpoint
@all
    process left
    process right
end
```

The compiler proves disjointness, alias legality, lifetime validity, and escape behavior before parallel realization. Detached tasks require ownership transfer, copying, shared ownership, or proven long-lived origins.

*(Cross-ref: `pass24_execution_concurrency_lua_supremacy.md` §4–§6.)*

---

## §26 Long-term compiler model

The semantic graph tracks: identity, descriptors, provenance, ownership, aliasing, views, effects, realizations, transformations, projections. Everything above becomes different projections of **one semantic system**.

---

## §27 Success criteria

Pass 25 completes when:

1. Types remain ordinary descriptor values.
2. Descriptor constructors remain ordinary functions.
3. Generic syntax disappears from canonical Duo.
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

Tracked as `P25-G01` … `P25-G14` in `src/pass25_catalog.zig`.

---

## §28 Implementation order (M0 → M3)

| Phase | Focus | Owner |
| --- | --- | --- |
| **M0** | Constitution, catalogs, rejected-syntax registry, schema stubs, gates | this pass |
| **M1** | Descriptor-call specialization; bracket generic de-emphasis; return consumption wiring | sema + dnir |
| **M2** | View/owner/pointer semantic graph entities; lifetime violation diagnostics | semantic_graph + sema |
| **M3** | Projection relationships; semantic transactions; LSP/MCP preview | transform_engine + tooling |

---

## §29 Cross-pass reconciliation

| Pass | Pass 25 relationship |
| --- | --- |
| **Pass 23** | Subsumes P23-WS6/WS11; **P23-D01 superseded** by §5.1 tail-demand; P23-D02 rejection preserved |
| **Pass 24** | Views + `@all` disjointness proofs; call consumption unchanged |
| **Pass 22** | Semantic graph as single source; delta compilation for incremental projection |
| **Pass 20** | Foreign snapshot + provenance feeds projection authority model |
| **Pass 12** | Proof-carrying + semantic autonomy align with transaction preview/validate |

---

## Governing principle

The best Duo feature should usually **disappear into ordinary Duo**.

The programmer thinks in: values, functions, tables, descriptors, calls.

The compiler thinks in: stages, specialization, provenance, ownership, realization, transactions, semantic identity.

The more compiler knowledge grows, the fewer language concepts the programmer should need to learn.

---

*Pass 25 is the design constitution for semantic unification. Implementation claims must cite gate IDs (`P25-G*`) and semantic graph evidence — not architecture prose alone.*
