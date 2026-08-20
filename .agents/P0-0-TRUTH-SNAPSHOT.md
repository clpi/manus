# P0-0 — exact local truth snapshot

**Captured:** 2026-08-20 (UTC) · **Not language law** · refresh before every edit wave

Compare against prior audit anchors: `idol` **7ae7dc2d**, `idol-native` **63c87425**
(historical; remote has moved — see below).

## `/Users/clp/x/idol` (also `/Volumes/d 1/x/idol`)

| Field | Value |
|---|---|
| **HEAD** | `073a60a7ea717aa77477d8dc4b2c5002cca89728` |
| **branch** | `main` (ahead **12** / behind **0** vs `idol/main` @ `5e24796a…`) |
| **merge note** | `fix/dnir-sibling-record-export` merged — architectural mandate rollback landed |
| **worktrees** | single |
| **stashes** | 6 |
| **compiler build** | `zig build` **PASS** |
| **`zig-out/bin/idol`** | 18.2MB · Aug 20 03:40 |
| **evidence `HEAD.txt`** | `073a60a7…` · Integration present · Measurement absent · Performance_admission denied |
| **working tree** | clean except derived `evidence/HEAD.txt` refresh |

### P0 architectural rollback — verified

| Regression | Status |
|---|---|
| Canonical `arr(i)` aggregate indexing | **removed** — `examples/call_index_assign.id` refuses at native-scalar precheck (assign-target) |
| DNIR sibling reparse (`loadSiblingModuleConsts`, `parseSiblingModule`, …) | **removed** — gate forbids |
| Graph fact sanitization (`filterCheckedCallOperands`, `callValueForApplication`, …) | **removed** — gate forbids |
| Export-map bypass without graph facts | **guarded** — `require_graph_facts` barrier present |

### Gates this session

| Gate | Result |
|---|---|
| `gate/architecture-negative.sh` | **PASS** (27 checks; WARN debt: `recordFieldsPresent`, `exprIsStr`) |
| `gate/architecture-companion.sh` | **PASS** — AMBIGUITY-FAILS, GRAPH-ARG-EXACT, FORMAT-FIXPOINT, CHECK-NOT-DIRECT-ADMISSION |
| `gate/delimiter-projection-law.sh` | **PASS** |
| `gate/authority.sh` | run before push |
| `zig build test` | **1645/1664 pass** — known unrelated failures (defaults ReleaseFast, agent-smoke, some direct-native examples) |

**Graph lift:** `verifyCheckedApplicationOperandPacks` present; DNIR trusts packs. **`idol check` ≠ direct admission** — companion probe documents the split.

## `/Volumes/d 1/x/idol-native`

| Field | Value |
|---|---|
| **HEAD** | `37982a6ae490adea59ee1aea829bf63aacb87454` |
| **branch** | `main` |
| **`origin/main`** | `371bf4c191d1132c01f7d0cf14f65f0072ff62e5` |
| **ahead/behind** | **+1** / **0** (unpushed) |
| **pinned Idol authority** | `073a60a7ea717aa77477d8dc4b2c5002cca89728` (`docs/spec/AUTHORITY.json`) |
| **law blob pin** | `201b78015e8f463798e50b2e180dc61cda45fcd1` |
| **constitution blob pin** | `7406246f170602414d620a01b042ae98768a40b6` |

### Paired checkout (`IDOL_ROOT=../idol`)

| Check | Status |
|---|---|
| `gate/authority.sh` with paired idol | **PASS** — sibling HEAD matches pin `073a60a7…` |
| Role | evidence / gate / differential consumer of Idol authority — **not** parallel language |

## Redress before push

1. **Push idol `main`** — local **+12** commits including architectural mandate merge.
2. **Push native `main`** — **+1** unpushed pin-alignment commit.
3. **Do not treat** native vendored projections as independent semantic authority.

## Open frontiers (not P0 blockers)

- Module composition as graph-only home/binding facts (filesystem disappears post-ingress)
- Self-host corpus classification: canonical vs compatibility vs bootstrap debt
- GAP-145 downstream observers (Tree-sitter / realization paths ignoring `sourceQuote`)
- GAP-134 single machine-readable grammar authority
- `recordFieldsPresent` / `exprIsStr` lowering-history and type-guess debt (WARN in architecture-negative)

## Agent coordination

- **Frontier map:** `docs/history/optimization-frontier-census.md`
- **Architecture mandate:** `.agents/ARCHITECTURE_INJECTION.md`
- **Negative controls:** `docs/architecture-negative-controls.md` · `gate/architecture-negative.sh`
- **Supreme law:** `docs/spec/law.md` then `docs/spec/constitution.md`
