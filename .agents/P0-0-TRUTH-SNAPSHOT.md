| field | value |
|---|---|
| title | P0-0 — exact local truth snapshot |
| captured | 2026-09-15 (UTC) · **Not language law** · refresh before every edit wave |

| # | directive |
|---|---|
| 1 | Compare against prior audit anchors: user baseline `idol` **33b36031**, `idol-native` **da649b52** (historical; local pair has moved — see below). |

| section |
|---|
| Incarnation tuple (measurement belongs to this set) |

| Component | Value |
|---|---|
| **Idol HEAD** | `8b9c202b5120917b3ec58fd9eda809d847e94ca6` |
| **Idol-native HEAD** | `ecc5dbb` (2026-09-09; repin pending against current idol HEAD) |
| **Law blob** | `503eeb5c5027b2dba77e8ba5ec09ade46ab1994b` |
| **Constitution blob** | `3b9caaff7c97295d44a1e5f3f7fc4a190d27954d` |
| **Source projection blob** | `c670c8b72fd135c0c3396e31b4a8ce6c6b985fa1` |
| **Vendored `bin/idol`** | must match Idol pin at measurement time |

| # | directive |
|---|---|
| 1 | If any component changes mid-run: **NOT A MEASUREMENT**. |

| section |
|---|
| `/Users/clp/work/idol-main` (canonical checkout) |

| Field | Value |
|---|---|
| **HEAD** | `8b9c202b5120917b3ec58fd9eda809d847e94ca6` |
| **branch** | `main` (pushed; matches origin/main) |
| **merge note** | summary propagation `e3adad92`/`e933461a` + div-law reconcile `780f321f9` + summary layering `8b9c202b5` |

| section |
|---|
| P0 architectural rollback — verified (user audit items 1–3) |

| Regression | Status |
|---|---|
| Canonical `arr(i)` aggregate indexing | **removed** — `aggregateIndexSite` accepts `.index` only; `examples/call_index_assign.id` refuses at direct precheck |
| DNIR sibling reparse | **removed** — zero production source IO in `dnir_lower.zig`; gate forbids loader helpers |
| Graph fact sanitization | **removed** — gate forbids `filter*Operands` / `callValueForApplication` |
| Export-map bypass on graph-required paths | **guarded** — `tryAssignRecordCallFromExportMap` returns false when `require_graph_facts` |

| section |
|---|
| Cross-home constants (audit item 15) — landed 2026-08-20 wave |

| Layer | Mechanism |
|---|---|
| **sema** | `foreignModuleIntConstant` + `peekForeignHome` (no DNIR filesystem) |
| **graph** | `liftForeignModuleConstants` + `liftForeignConstantFieldSites` → `publishExactI64` |
| **DNIR** | `OccurrenceBridge.exactValue` → `lowerField` when `require_graph_facts` |
| **precheck** | `CodeGen.checked_sema` folds foreign const fields like req-module fields |

| section |
|---|
| Gates (re-verified 2026-09-15; `.sh` drivers migrated to native `.id` via `d766680dd`) |

| Gate | Result |
|---|---|
| `gate/architecture-negative.id` | **PASS** (35 checks incl. POST-RESOLUTION-PATH-ZERO, LINKAGE-DOES-NOT-DEFINE-MEANING) |
| `gate/architecture-companion.id` | **PASS** |
| `gate/table_apply.id` | **PASS** — normalizeModule on all direct lowering paths |

| section |
|---|
| normalizeModule (audit item 13) |

| # | directive |
|---|---|
| 1 | `src/table_apply.zig` — compatibility-only world ingress; explicitly **does not** reinterpret `()` as `[]` or use type_map for semantics. |
| 2 | No `arr(i)` migration path. |

| section |
|---|
| `/Users/clp/work/idol-native` |

| Field | Value |
|---|---|
| **HEAD** | `ecc5dbb` |
| **pinned Idol authority** | `8b9c202b5120917b3ec58fd9eda809d847e94ca6` (pairing recorded; repin pending) |

| section |
|---|
| Open frontiers |

| # | directive |
|---|---|
| 1 | **GRAPH-ARG-EXACT producer** — graph operand pack still wrong at source; DNIR filters removed |
| 2 | **bind.id self-host** — `idol check` passes; direct compile still fails `local-decl-init` at native-scalar precheck under `lib/compiler/` |
| 3 | Behavioral companions: GRAPH-ONLY-REALIZATION, HOME-MOVE, ZERO-TEXT-SEMANTICS |
| 4 | Decompose `subject_home.Conformance` enum into descriptor/world facts |
