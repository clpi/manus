# P0-0 — exact local truth snapshot

**Captured:** 2026-08-20 (UTC) · **Not language law** · refresh before every edit wave

Compare against prior audit anchors: user baseline `idol` **33b36031**, `idol-native` **da649b52**
(historical; local pair has moved — see below).

## Incarnation tuple (measurement belongs to this set)

| Component | Value |
|---|---|
| **Idol HEAD** | pending commit on `059d1f7b` lineage (graph cross-home constants) |
| **Idol-native HEAD** | `7e88eb4c7cfa68b98d552392538b498c8384f785` (repin after idol push) |
| **Law blob** | `201b78015e8f463798e50b2e180dc61cda45fcd1` |
| **Constitution blob** | `7406246f170602414d620a01b042ae98768a40b6` |
| **Source projection blob** | `aa4a0eb37260546a3cf4f1eec3bf99a7f19b974a` |
| **Vendored `bin/idol`** | must match Idol pin at measurement time |

If any component changes mid-run: **NOT A MEASUREMENT**.

## `/Volumes/d 1/x/idol`

| Field | Value |
|---|---|
| **HEAD (pre-commit)** | `059d1f7b7eae50893097eacf47b8bb0fd43bbdae` |
| **branch** | `main` (1 commit ahead of origin before this wave) |
| **merge note** | P0 rollback `e4a7dc05` + mandate merge `073a60a7` + arch gate hardening `059d1f7b` |

### P0 architectural rollback — verified (user audit items 1–3)

| Regression | Status |
|---|---|
| Canonical `arr(i)` aggregate indexing | **removed** — `aggregateIndexSite` accepts `.index` only; `examples/call_index_assign.id` refuses at direct precheck |
| DNIR sibling reparse | **removed** — zero production source IO in `dnir_lower.zig`; gate forbids loader helpers |
| Graph fact sanitization | **removed** — gate forbids `filter*Operands` / `callValueForApplication` |
| Export-map bypass on graph-required paths | **guarded** — `tryAssignRecordCallFromExportMap` returns false when `require_graph_facts` |

### Cross-home constants (audit item 15) — landed this wave

| Layer | Mechanism |
|---|---|
| **sema** | `foreignModuleIntConstant` + `peekForeignHome` (no DNIR filesystem) |
| **graph** | `liftForeignModuleConstants` + `liftForeignConstantFieldSites` → `publishExactI64` |
| **DNIR** | `OccurrenceBridge.exactValue` → `lowerField` when `require_graph_facts` |
| **precheck** | `CodeGen.checked_sema` folds foreign const fields like req-module fields |

### Gates

| Gate | Result |
|---|---|
| `gate/architecture-negative.sh` | **PASS** (36 checks incl. POST-RESOLUTION-PATH-ZERO, LINKAGE-DOES-NOT-DEFINE-MEANING) |
| `gate/architecture-companion.sh` | **PASS** |

### normalizeModule (audit item 13)

`src/table_apply.zig` — compatibility-only world ingress; explicitly **does not** reinterpret `()` as `[]` or use type_map for semantics. No `arr(i)` migration path.

## `/Volumes/d 1/x/idol-native`

| Field | Value |
|---|---|
| **HEAD** | `7e88eb4c7cfa68b98d552392538b498c8384f785` |
| **pinned Idol authority** | `059d1f7b7eae50893097eacf47b8bb0fd43bbdae` (repin required after idol push) |

## Open frontiers

- **GRAPH-ARG-EXACT producer** — graph operand pack still wrong at source; DNIR filters removed
- **bind.id self-host** — passes precheck outside `lib/compiler/` path; under `lib/compiler/` precheck still hits `local-decl-init` (path/home interaction); graph stage needs `lexer.new` application facts
- Behavioral companions: GRAPH-ONLY-REALIZATION, HOME-MOVE, ZERO-TEXT-SEMANTICS
- Decompose `subject_home.Conformance` enum into descriptor/world facts
