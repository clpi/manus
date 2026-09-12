| field | value |
|---|---|
| title | P0-0 — exact local truth snapshot |
| captured | 2026-08-20 (UTC) · **Not language law** · refresh before every edit wave |

| # | directive |
|---|---|
| 1 | Compare against prior audit anchors: user baseline `idol` **33b36031**, `idol-native` **da649b52** (historical; local pair has moved — see below). |

| section |
|---|---|
| Incarnation tuple (measurement belongs to this set) |

| Component | Value |
|---|---|
| **Idol HEAD** | `1036c7cfa9684ee3af3c623df0a46ab58e9c214b` |
| **Idol-native HEAD** | `ab0094d` (repin to `1036c7cf`) |
| **Law blob** | `201b78015e8f463798e50b2e180dc61cda45fcd1` |
| **Constitution blob** | `7406246f170602414d620a01b042ae98768a40b6` |
| **Source projection blob** | `aa4a0eb37260546a3cf4f1eec3bf99a7f19b974a` |
| **Vendored `bin/idol`** | must match Idol pin at measurement time |

| # | directive |
|---|---|
| 1 | If any component changes mid-run: **NOT A MEASUREMENT**. |

| section |
|---|---|
| `/Volumes/d 1/x/idol` |

| Field | Value |
|---|---|
| **HEAD** | `1036c7cfa9684ee3af3c623df0a46ab58e9c214b` |
| **branch** | `main` (pushed) |
| **merge note** | P0 rollback `e4a7dc05` + mandate merge `073a60a7` + arch gate hardening `059d1f7b` + graph cross-home constants `1036c7cf` |

| section |
|---|---|
| P0 architectural rollback — verified (user audit items 1–3) |

| Regression | Status |
|---|---|
| Canonical `arr(i)` aggregate indexing | **removed** — `aggregateIndexSite` accepts `.index` only; `examples/call_index_assign.id` refuses at direct precheck |
| DNIR sibling reparse | **removed** — zero production source IO in `dnir_lower.zig`; gate forbids loader helpers |
| Graph fact sanitization | **removed** — gate forbids `filter*Operands` / `callValueForApplication` |
| Export-map bypass on graph-required paths | **guarded** — `tryAssignRecordCallFromExportMap` returns false when `require_graph_facts` |

| section |
|---|---|
| Cross-home constants (audit item 15) — landed this wave |

| Layer | Mechanism |
|---|---|
| **sema** | `foreignModuleIntConstant` + `peekForeignHome` (no DNIR filesystem) |
| **graph** | `liftForeignModuleConstants` + `liftForeignConstantFieldSites` → `publishExactI64` |
| **DNIR** | `OccurrenceBridge.exactValue` → `lowerField` when `require_graph_facts` |
| **precheck** | `CodeGen.checked_sema` folds foreign const fields like req-module fields |

| section |
|---|---|
| Gates |

| Gate | Result |
|---|---|
| `gate/architecture-negative.sh` | **PASS** (36 checks incl. POST-RESOLUTION-PATH-ZERO, LINKAGE-DOES-NOT-DEFINE-MEANING) |
| `gate/architecture-companion.sh` | **PASS** |

| section |
|---|---|
| normalizeModule (audit item 13) |

| # | directive |
|---|---|
| 1 | `src/table_apply.zig` — compatibility-only world ingress; explicitly **does not** reinterpret `()` as `[]` or use type_map for semantics. |
| 2 | No `arr(i)` migration path. |

| section |
|---|---|
| `/Volumes/d 1/x/idol-native` |

| Field | Value |
|---|---|
| **HEAD** | `ab0094d` |
| **pinned Idol authority** | `1036c7cfa9684ee3af3c623df0a46ab58e9c214b` |

| section |
|---|---|
| Open frontiers |

| # | directive |
|---|---|
| 1 | **GRAPH-ARG-EXACT producer** — graph operand pack still wrong at source; DNIR filters removed |
| 2 | **bind.id self-host** — `idol check` passes; direct compile still fails `local-decl-init` at native-scalar precheck under `lib/compiler/` |
| 3 | Behavioral companions: GRAPH-ONLY-REALIZATION, HOME-MOVE, ZERO-TEXT-SEMANTICS |
| 4 | Decompose `subject_home.Conformance` enum into descriptor/world facts |
