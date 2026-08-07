# HPLS Frontier barrier index (Pass 34 v2)

Machine-readable catalog: `src/pass34_catalog.zig` (`pass34-hpls-catalog-v1`)  
Plan: [`docs/plans/pass34_hpls_frontier.md`](../plans/pass34_hpls_frontier.md)  
Gate: `zig build pass34-gate`

## Tier counts (53 records)

| Tier | Count | IDs |
| --- | ---: | --- |
| C — Convergences | 5 | C1–C5 |
| E — Elephants | 10 | E1–E10 |
| L — Levers | 15 | L1–L15 |
| U — Unicorns | 15 | U1–U15 |
| T — Traps | 8 | T1–T8 |

Phase 0: every record `status = DISCOVERED`.

## Top ranked items (v2 — measurement first)

| Rank | ID | Title |
| ---: | --- | --- |
| 1 | **L6** | Representation manifest as build artifact |
| 2 | **L1** | Module sealing after load |
| 3 | E1 | Memory reclamation is unspecified |
| 4 | E8 | No canonical alias model |
| 5 | L2 | Interned field identity in the fallback path |
| 6 | C1 | One frame-map artifact (E2+E7) |
| 7 | E9 | ABI is nobody's subsystem |

Full ordinal list: `ranked_item_ids` in `pass34_catalog.zig`.

## Tier C — Convergences

| ID | Title | Owner |
| --- | --- | --- |
| C1 | One frame-map artifact | provenance + native backend |
| C2 | One descriptor identity | descriptor registry |
| C3 | One semantic graph | semantic_graph |
| C4 | One representation lattice | representation selection |
| C5 | One interrogation surface | explain_pipeline + semantic_graph |

Convergence rule: DONE only when redundant implementation is **deleted**.

## Tier E — Elephants

| ID | Title | Bridge (summary) |
| --- | --- | --- |
| E1 | Memory reclamation unspecified | provisional non-moving contract |
| E2 | Deoptimization hand-waved | proofs-over-guards via C1 |
| E3 | Error unwinding across native frames | out-of-band error flag (E9) |
| E4 | Compile time unpriced | U10 + E10 + L13 |
| E5 | C boundary leaks semantic facts | L6 ledger + E9 ABI |
| E6 | No concurrency memory model | isolate-per-thread + immutable sharing |
| E7 | Debug identity dies at specialization | same artifact as C1 |
| E8 | No canonical alias model | sealed-immutable alias-free subset |
| E9 | ABI is nobody's subsystem | ABI v0 document |
| E10 | Incremental semantic invalidation | coarse module invalidation now |

## Tier L — Levers

L1 module sealing · L2 interned fallback IDs · L3 non-nil facts · L4 string ladder · L5 dense arrays · **L6 manifest** · L7 metatable identity · L8 numeric speciation · L9 allocation sinking · L10 write barriers · L11 closure flattening · L12 effect elimination · L13 call-shape caching · L14 descriptor folding · L15 semantic coverage

## Tier U — Unicorns

U1 verified agent hints · U2 AoS→SoA · U3 deopt queries · U4 perf blame · U5 closed-world · U6 snapshot images · U7 tests as fuel · U8 native coroutines · U9 zero-marshal FFI · U10 compile budget · U11 contracts/negotiation · U12 history/bisect · U13 semantic replay · U14 proof minimization · U15 semantic diff/patch/merge

## Tier T — Traps

T1 string concat in loops · T2 missing backend tags · T3 helper-dominated microbenches · T4 representation-observing tests · T5 cache-resident fixtures · T6 benchmark drift · T7 semantic benchmark pollution · **T8 idiom enforced by text linter**

## §13 — Agent idiom enforcement

Idiomatic Duo = manifest-clean + facts-provable. Six projections, zero new subsystems (`agent_idiom_projections`):

| Mechanism | Home |
| --- | --- |
| Manifest is the style guide | L6 |
| Goals are the agent contract, not hints | U11 |
| Assert-and-verify replaces write-and-hope | U1 + U14 |
| Semantic edits close the text loophole | U15 + C3 |
| Golden corpus ships manifests, not comments | L15 + L6 |
| Idiom served by query, not source reading | C5 |

T8 supersedes `scripts/duo_idiom_gate.duo` (regex-over-text linter). Convergence rule applies: closes only on deletion, gate-enforced by `proveT8ClosesOnlyOnDeletion`.

## Canonical-home mapping (§8 — 20 entries)

Normative table in `canonical_home_mappings` (`pass34_catalog.zig`). Pattern: nearly every “new feature” is a projection of graph + witnesses + provenance + cost model (C3/C5/L6/U11).

## Execution phases

| ID | Focus items |
| --- | --- |
| P34-PH0 | Catalog only (current) |
| P34-PH1 | L6, L1, L2 |
| P34-PH2 | E1, E8, C1, E2, E7, E3, E9, E6, E5, E10 |
| P34-PH3 | L3, L12, L7, L4, L8, L13, L5, L9, L10, L11, L14 |
| P34-PH4 | U1 or U4 or U11 |
| P34-PH5 | U5 |
| P34-PH6 | C5, U12, U13, U15 |

## Agent pick-up

1. `zig build pass34-gate` must pass before claiming Phase 0 complete.
2. Phase 1 starts with **L6** (rank #1), then L1, then L2.
3. Respect §8 canonical homes — no duplicate subsystems for mapped proposals.
4. Every fix deposits a **witness**; `bounded_fix != NONE` requires non-`NONE` witness.
