# Pass 1 — Identity: Lua Semantics with Progressive Compiler Knowledge

> **Date:** 2026-08-04  
> **Mission:** Duo is Lua with progressively stronger compiler knowledge — dynamic paths stay Lua-correct; typed paths lower to native C without `lua_Value`.  
> **North star docs:** `docs/semantic_universe.md`, `docs/plans/semantic_graph_architecture.md`

## Audit export

```bash
duo catalog | jq '.pass1'
duo catalog | jq '.pass1.readiness_summary'
```

| Owner | Role |
| --- | --- |
| `src/pass1_catalog.zig` | Milestones, workstreams, acceptance criteria |
| `src/semantic_graph.zig` | Phase 1 graph spine |
| `src/transform_engine.zig` | Phase 0 transform registry |
| `src/meta_transform_tests.zig` | G-061 tier-1 parity harness |

## Milestones

| ID | Title | Status |
| --- | --- | --- |
| P1-M0 | Canonical identity plan + catalog | done |
| P1-M1 | Phase 0 alignment (transform registry, parity, provenance) | partial |
| P1-M2 | Phase 1 graph spine (stable IDs, JSON dump) | partial |
| P1-M3 | Lua semantic parity (missing args, nil, truthiness) | done |
| P1-M4 | Progressive specialization ladder documented + smoke | partial |

## Workstreams (ordered)

| ID | Title | Status |
| --- | --- | --- |
| P1-WS1 | Semantic universe + agent alignment docs | done |
| P1-WS2 | Transform engine stub + tier-1 registry | partial |
| P1-WS3 | G-061 parity harness (3-site compile tests) | partial |
| P1-WS4 | Provenance log (`DUO_PROVENANCE=1`) | done |
| P1-WS5 | Semantic graph lift + `duo graph` JSON | partial |
| P1-WS6 | StorageClass ladder + `@comp.type.shape` | done |
| P1-WS7 | Lua call semantics (missing args, and/or truthiness) | done |
| P1-WS8 | Architecture proof example | done |

## Acceptance criteria

1. Identity statement is canonical in docs and `duo catalog pass1`
2. Phase 0 checklist in `semantic_universe.md` tracked with evidence
3. Tier-1 combinators registered + parity-tested
4. `duo graph` exports table/enum shapes for any `.duo` module
5. Missing trailing call args default to nil; bool `and`/`or` compiles
6. No new `@comp.*` without registry entry (G-061 moratorium)
7. Dynamic Lua paths preserve semantics; typed paths avoid boxing where proven

## Validation

```bash
zig test src/meta_transform_tests.zig
zig test src/semantic_graph.zig
./zig-out/bin/duo run examples/architecture_proof.duo
./zig-out/bin/duo run examples/missing_args_nil_smoke.duo
./zig-out/bin/duo graph examples/table_shape_smoke.duo
duo catalog | jq '.pass1'
```
