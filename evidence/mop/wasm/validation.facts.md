# Wasm validation facts — mapped onto the existing graph vocabulary

Research lane 3 per the FTCFTW directive: decoder/validator facts in the
CURRENT semantic vocabulary (sim-v0 as measured by `idol-native graph`).
No runtime, no new ontology — every row uses facts the graph already
publishes for Idol source. This is a specification-to-vocabulary
mapping, not an implementation claim.

## Fact vocabulary used (all existing)

- application {relation, subject, operands, results, demand, cards:
  applied/effect/authority/witness/target/realization}
- place {shape, region, determinacy, mutation, escape, lifetime,
  residency, accesses{bind/read, mult, const_index}}
- region {shape: refinement|alternative|recurrence, carried}
- pack {members, roles}
- world {home, reach, members} + draws {application → world card}
- law witness + provenance (origin: wasm)

## Validation → facts

| Wasm validation family | Graph expression |
|---|---|
| value/operand types | application operand cards carry width/kind (i32/i64/f32/f64/v128/ref) as descriptor facts — the operand STACK never exists; each instruction is an application whose operand/result packs are typed descriptors |
| `i32.add` semantics | application {relation: add, operands [a b], width 32, overflow: wrap, origin: wasm} — identical fact shape to native `a + b`; law wasm supplies the wrap witness |
| control frames (block/loop/if) | region facts: refinement (block/if arms), recurrence (loop) — the same region algebra the graph already emits for Idol control; br/br_if = alternative edges with carried places |
| locals | place facts {shape: scalar, region: function, residency: register-candidate, accesses: bind/read with multiplicity} — locals are bindings, not a runtime array |
| function signature | relation descriptor: operand pack + result pack with declared roles (public role identity ≠ local spelling) |
| call / call_indirect | application with target card: exact (direct), one-of table (draw over a callable aggregate — the same card worlds use), unknown (import) |
| tables | aggregate place {members: callable|reference, extent, growth} — dispatch is a DRAW, devirtualization is narrowing the card to one |
| globals | module-scope place {determinacy, mutation, escape} — exactly the F3a/F3b fact family the compiler already demands |
| linear memory | world {home: memory, reach: address} + place classification per object: address-observable / alias / escaped / shared vs internal / sealed / nonaliased — bounds are PROOFS over place extents, not backend hacks |
| memory.grow | mutation fact on the memory world with extent transition — enables the growth-impossibility proof class |
| imports/exports | boundary facts: draws to foreign worlds; a sealed composition narrows the card and the draw disappears |
| validation itself | fact_coverage: every application's cards either published (valid) or unknown (invalid) — the SAME blocker meter already measured (server.id: 37 candidates / 2 published). Wasm validation = admission, not a separate checker kingdom |
| trapping semantics | failure positions in the result pack (the `: t | error` discipline) — trap = rejection alternative, observable only if demanded |
| SIMD (236 ops) | applications over v128 packs with lane roles — no new machinery, pack members carry lane extents |
| threads/atomics | shared places + ordering facts on edges (effect cards carry ordering) |
| GC refs | reference places with lifetime/escape facts — GC proposal semantics ≠ GC runtime (register/stack/region/static selection) |

## The two headline dissolutions, stated in facts

1. **Operand stack**: an instruction sequence is a chain of applications
   where each result pack feeds the next operand pack — the stack is the
   provenance ORDER, which the graph already records as edges. No place,
   no runtime object.
2. **Canonical ABI**: a component boundary is an application whose
   result-pack members carry demand cards (payload 0 / status 1 /
   metadata 0). Sealed composition = the boundary application's witness
   narrows; undemanded slots never realize. This is the existing demand
   machinery, one boundary further out.

## Why this is the right lane now

The graph already publishes every fact family this mapping needs — the
measured blocker matrix (F1 unresolved applications, F3 module globals,
F4 relation shapes) is the SAME admission surface Wasm facts will pass
through. Ingesting Wasm as facts inherits the existing demand,
specialization, and realization machinery instead of forking a second
compiler. Lane 3 delivers this mapping plus prototypes as fixtures; the
production decoder waits on lanes 1–2 closing ingress and grammar.


## Fact-separation ruling (parallel review, 2026-08-17)

Two architecture regressions the review prevented apply directly here:

1. **Semantic runtime need is NEVER inferred from opcodes** — neither
   Wasm opcodes nor DNIR opcodes. Instructions are source-law
   provenance; runtime need comes only from demanded occurrences on the
   graph. The probe's per-instruction applications are provenance
   records; any realization decision reads demand facts, not these.
2. **No bundled boundary records.** law, provider, ABI, ownership, and
   realization are SEPARATE fact families. An application record carries
   provenance (origin: wasm) and operand/result descriptors — never a
   boundary bundle. Component/WIT ingestion must publish each family
   independently (descriptor / pack / ownership / world / effect), and
   consumers demand per family.

Also noted: the WASI lane stripped an accidental 4,000-line formatter
rewrite before history — ingest tooling generates nothing but facts.
