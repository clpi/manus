# P0-0 — exact local truth snapshot

**Captured:** 2026-08-20 (UTC) · **Not language law** · refresh before every edit wave

Compare against prior audit anchors: `idol` **7ae7dc2d**, `idol-native` **63c87425**
(historical; remote has moved — see below).

## `/Volumes/d 1/x/idol`

| Field | Value |
|---|---|
| **HEAD** | `31b4a3a28d49f37be74399a1aef2d0474ebf55d9` |
| **branch** | `fix/dnir-sibling-record-export` (no upstream) |
| **local `main`** | `9b84d2e9fe54479e00a9d86ab46207f57ea24165` |
| **`idol/main` remote** | `332945610881f01201177bf1320586ec72435571` |
| **ahead/behind remote** | local `main` **+1** / **0** vs `idol/main` |
| **worktrees** | single: `/Volumes/d 1/x/idol` |
| **stashes** | 6 |
| **active claims** | run `tools/node/dev/claim list` (not copied here) |
| **compiler build** | `zig build` **PASS** (session) |
| **`bin/idol`** | symlink → `out/bin/idol` · `zig-out/bin/idol` 7.5MB Aug 20 03:26 |
| **evidence `HEAD.txt`** | **STALE** `aff3d0fe…` — must refresh on next evidence commit |
| **last aggregate subject** | not run this session (`gate/all.sh` absent in tree) |

### Dirty (tracked)

- `docs/AGENT_ALIGNMENT.md`
- `docs/history/optimization-frontier-census.md`
- `lib/compiler/monolith.id`
- `src/codegen.zig`, `src/dnir_lower.zig`, `src/sema.zig`, `src/semantic_graph.zig`

### Untracked (high-signal)

- `docs/architecture-negative-controls.md`, `gate/architecture-negative.sh`, `gate/architecture-companion.sh`
- many `examples/bind_*` bisect probes, `lib/compiler/bind_bisect*.id`
- `docs/projections/` (new)
- `out/bin/` build artifact tree

### Gates this session (post architecture redress)

| Gate | Result |
|---|---|
| `gate/authority.sh` | run before push |
| `gate/architecture-negative.sh` | **PASS** (23 checks; WARN debt: `recordFieldsPresent`, `exprIsStr`) |
| `gate/architecture-companion.sh` | **PASS** — AMBIGUITY-FAILS, GRAPH-ARG-EXACT, FORMAT-FIXPOINT, CHECK-NOT-DIRECT-ADMISSION |
| `gate/gap-111-subject-first.sh` | **PASS** — `iter.map(xs, twice)` explicit form |
| `gate/selfhost.sh` | **missing** from tree (stale references in agent docs) |

**Local HEAD note:** sema subject-first uses order-independent home scan + ambiguity (no conformance→home registry). Graph lift enforces `verifyCheckedApplicationOperandPacks`; DNIR trusts packs (`filterCallArgumentOperands` / `filterRecordAssignOperands` / `expandableRecordForName` removed). **`idol check` ≠ direct admission** — sema-only today; companion probe documents the split until structured outcomes close it.

## `/Volumes/d 1/x/idol-native`

| Field | Value |
|---|---|
| **HEAD** | `d77d78fab8af7ffc6bfb23af8a803e92aeb5b639` |
| **branch** | `main` |
| **`origin/main`** | `365aa028b6691e67b782624758e2e5024c79a8d8` |
| **ahead/behind** | **+2** / **0** (unpushed) |
| **stashes** | 2 |
| **worktrees** | single |
| **pinned Idol authority** | `9b84d2e9fe54479e00a9d86ab46207f57ea24165` (`docs/spec/AUTHORITY.json`) |
| **law blob pin** | `201b78015e8f463798e50b2e180dc61cda45fcd1` |
| **constitution blob pin** | `7406246f170602414d620a01b042ae98768a40b6` |

### Paired checkout (`IDOL_ROOT=../idol`)

| Check | Status |
|---|---|
| `gate/authority.sh` with paired idol | **FAIL** — sibling HEAD `31b4a3a2…` ≠ pin `9b84d2e9…` |
| Role | evidence / gate / differential consumer of Idol authority — **not** parallel language |

## Redress required before merge/push

1. **Land idol `main`**: merge `fix/dnir-sibling-record-export` → `main`, push to `idol/main`.
2. **Refresh native pin**: after idol settles, bump `idol-native/docs/spec/AUTHORITY.json` commit + law/constitution blobs; push native **+2** commits.
3. **Refresh `evidence/HEAD.txt`** to match the revision that owns new evidence rows.
4. **Restore or replace `gate/selfhost.sh`** references — ledger probe currently absent.
5. **Do not treat** native vendored projections as independent semantic authority.

## Agent coordination

- **Frontier map:** `docs/history/optimization-frontier-census.md` (XXXIX–XLV + ranked list).
- **Architecture mandate:** `.agents/ARCHITECTURE_INJECTION.md`
- **Negative controls:** `docs/architecture-negative-controls.md` · `gate/architecture-negative.sh`
- **Supreme law:** `docs/spec/law.md` then `docs/spec/constitution.md`