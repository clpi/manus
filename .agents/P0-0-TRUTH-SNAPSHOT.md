# P0-0 — exact local truth snapshot

**Captured:** 2026-08-20 (UTC) · **Not language law** · refresh before every edit wave

Compare against prior audit anchors: user baseline `idol` **33b36031**, `idol-native` **da649b52**
(historical; local pair has moved — see below).

## Incarnation tuple (measurement belongs to this set)

| Component | Value |
|---|---|
| **Idol HEAD** | `6a4664e6bfbbfb638cab8ef85be60ca28acfeae6` |
| **Idol-native HEAD** | `283c012…` (pin update to `6a4664e6…` pending) |
| **Law blob** | `201b78015e8f463798e50b2e180dc61cda45fcd1` |
| **Constitution blob** | `7406246f170602414d620a01b042ae98768a40b6` |
| **Source projection blob** | `aa4a0eb37260546a3cf4f1eec3bf99a7f19b974a` |
| **Vendored `bin/idol`** | must match Idol pin at measurement time |

If any component changes mid-run: **NOT A MEASUREMENT**.

## `/Volumes/d 1/x/idol`

| Field | Value |
|---|---|
| **HEAD** | `6a4664e6bfbbfb638cab8ef85be60ca28acfeae6` |
| **branch** | `main` synced with `idol/main` |
| **merge note** | P0 architectural rollback landed in `e4a7dc05` + mandate merge `073a60a7` |

### P0 architectural rollback — verified (user audit items 1–3)

| Regression | Status |
|---|---|
| Canonical `arr(i)` aggregate indexing | **removed** — `aggregateIndexSite` accepts `.index` only; `examples/call_index_assign.id` refuses at direct precheck |
| DNIR sibling reparse | **removed** — zero production `readFile` in `dnir_lower.zig`; gate forbids loader helpers |
| Graph fact sanitization | **removed** — gate forbids `filter*Operands` / `callValueForApplication` |
| Export-map bypass on graph-required paths | **guarded** — `tryAssignRecordCallFromExportMap` returns false when `require_graph_facts` |

### Gates

| Gate | Result |
|---|---|
| `gate/architecture-negative.sh` | **PASS** (32 checks) |
| `gate/architecture-companion.sh` | **PASS** |

## `/Volumes/d 1/x/idol-native`

| Field | Value |
|---|---|
| **HEAD** | `283c012…` |
| **pinned Idol authority** | `b189edc5…` (one commit behind idol — repin to `6a4664e6…` before push) |
| **`bin/idol`** | re-vendored ~18.2MB |

### Self-host note

Architecture gates run before self-host in `gate/all.sh`. Fresh binary shows widespread
`DNB001 lowerDynamicIndex()` — lawful next step is graph `[]` projection facts, not
restoring `arr(i)`. bind.id blocked on cross-home constant graph facts (`token.KIND_EOF`).

## Open frontiers

- Graph cross-home constant identity/facts at lowering
- GRAPH-ARG-EXACT producer fix (delete any remaining operand recovery)
- Behavioral companions: GRAPH-ONLY-REALIZATION, HOME-MOVE, ZERO-TEXT-SEMANTICS
