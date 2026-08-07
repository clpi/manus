# Pass 34 — HPLS Frontier (operational projection)

Operational projection of the canonical HPLS barrier catalog (v2).

- Machine-readable catalog: `src/pass34_catalog.zig` (`pass34-hpls-catalog-v1`)
- Canonical spec: [`duo_hpls_frontier.md`](duo_hpls_frontier.md)
- Human index: [`docs/catalogs/hpls_barriers.md`](../catalogs/hpls_barriers.md)
- Gate: `zig build pass34-gate` (alias: `hpls-frontier-gate`)
- Query: `duo catalog audit gate pass34`

## Phase 0 exit gate

- Every Tier C/E/L/U/T item (53 records) has a barrier record with explicit `rank_inputs`
- Every prerequisite carries a named bridge in `prerequisite_bridges`
- `bounded_fix != NONE` implies non-`NONE` `witness`
- §8 canonical-home mapping table (20 entries) adopted as normative
- §13 agent idiom enforcement: 6 projections, every `homes` entry a valid barrier ID
- Catalog queryable via aggregate JSON export and gate proofs
- Zero speculative barrier-removal code in Phase 0
- All records `status = DISCOVERED`

## Cross-links

| Item | Related artifact |
| --- | --- |
| L6 manifest | `pass27_benchmark_evidence.zig`, `bench-proof-gate` |
| L1 module sealing | `sema.zig`, knowledge lattice |
| E5 fact-loss ledger | extends L6 / `@comp.why` |
| C3 semantic graph | `semantic_graph.zig` |
| C5 interrogation surface | `@comp.why`, explain pipeline, MCP |
| Foundation IR | `foundation_catalog.zig`, `foundation-gate` |
| §13 agent idiom enforcement | `agent_idiom_projections`, T8 |
| T8 text-linter supersession | `scripts/duo_idiom_gate.duo` (closes on deletion) |

## Execution phases (summary)

| Phase | ID | Focus |
| --- | --- | --- |
| 0 | P34-PH0 | Record everything (current) |
| 1 | P34-PH1 | L6 → L1 → L2 |
| 2 | P34-PH2 | Tier-E decision records + bridge adoption |
| 3 | P34-PH3 | Cash levers in rank order |
| 4 | P34-PH4 | Prove U1 or U4 or U11 |
| 5 | P34-PH5 | U5 closed-world Ward decoder |
| 6 | P34-PH6 | C5 views: heat map, history, replay, diff |

See canonical spec for ranked order, dependency graph, witness invariant, and validation discipline.
