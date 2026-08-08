> **HISTORICAL — superseded by `docs/spec/pass100.md`. Not an architecture input.**

# Pass 8 — Persistent Semantic Computing, Negotiated Realization

**Status:** Phase 0 bootstrap **partial** (2026-08-04)  
**Principle:** The canonical artifact is a versioned semantic program; machine code and source are projections  
**Catalog:** `duo catalog` → `pass8` via `src/pass8_catalog.zig`

Pass 7 made compiler knowledge explicit for agents. **Pass 8** extends that into persistent realization: what remains free, what was selected, why, and what invalidates prior choices.

> Repository implementation always overrides architecture documents.

---

## Scope boundary

**In:** realization freedom, deterministic planning, persistent evidence, invalidation, dependencies, continuations, evolution, replay, MCP/LSP facts.

**Out:** OS, cluster manager, Git replacement, deployment service, cloud control plane, online AI compiler, general database.

Duo owns **semantics and valid realizations**. External systems supply machines, storage, and schedulers.

---

## Central thesis

```
Lua-shaped source / imported semantics
  → canonical semantic entities
  → constraints + degrees of freedom
  → candidate realizations
  → deterministic selection
  → native projection
  → observations
  → knowledge refinement / invalidation
  → improved realization
```

---

## Repo-truth audit (2026-08-04)

| Area | Owner | Status |
| --- | --- | --- |
| Stable semantic IDs | `knowledge_snapshot`, `semantic_graph` | partial |
| Fingerprints | `semantic_fingerprint.zig` | partial |
| Evidence | `evidence_record.zig` (+ Pass 7 `optimization_outcome`) | partial |
| Assumptions / invalidation strings | `assumption_guard.zig` | partial |
| Realization variables | `realization.zig` | partial — `selectDeterministic`, graph lift, `duo realize` / `duo explain`, codegen `realization.representation` outcomes |
| Persistent cache schema | `persistent_semantic_state.zig` | partial — disk cache + `mergeRealizationEntry` + `reuse_audit` |
| `duo realize` | `main.zig` + `compile_semantic_cache.zig` | partial — plan + persistent entries + invalidation edges |
| `duo explain` | `main.zig` | partial — snapshots, outcomes (incl. codegen realization), assumptions, realizations |
| Invalidation (shape drift) | `semantic_invalidation.zig` | partial — fingerprint mismatch → `invalidated`; demo `realization_point_v2.duo` |
| MCP / LSP realization queries | duo-mcp / duo-lsp | open |

---

## Milestones

| ID | Title | Status |
| --- | --- | --- |
| **P8-M2** | Persistent semantic evidence reuse | **partial** — disk cache at `.duo/cache/semantic/state.json`, `canReuse`, `reuse_audit` |
| **P8-M1** | Explicit realization decision | **partial** — `duo realize`, repr candidates + `selectDeterministic` |
| **P8-M3** | Derived execution plan | open |
| **P8-M4** | Semantic replay | open |
| **P8-M5** | Semantic evolution report | open |
| **P8-M6** | Bidirectional descriptor proof | open |

---

## New modules (this session)

| Module | Role |
| --- | --- |
| `src/evidence_record.zig` | Unified evidence kinds; maps Pass 7 outcomes |
| `src/realization.zig` | Freedom state, candidates, deterministic `selectDeterministic` |
| `src/persistent_semantic_state.zig` | Cross-build cache entry schema + reuse rules |
| `src/pass8_catalog.zig` | Machine-readable tracking JSON |

---

## Implementation order

```
semantic fingerprints (Pass 7)
  → evidence_record (P8-06) ✅ partial
  → realization.zig (P8-02/05/11) ✅ partial
  → persistent_semantic_state (P8-07) ✅ partial (disk cache + reuse audit)
  → wire into codegen selection
  → cross-build reuse (P8-M2) ✅ partial
  → invalidation graph (P8-08)
  → dependency/conflict edges (P8-09)
  → determinism + replay (P8-M3/M4)
```

---

## Agent claim tags

`pass8-audit`, `pass8-realization`, `pass8-evidence`, `pass8-persistence`, `pass8-invalidation`, `pass8-dependencies`, `pass8-replay`, `pass8-ward`, `pass8-mcp`

---

## Validation

```bash
zig build
zig test src/pass8_catalog.zig
zig test src/realization.zig
zig test src/evidence_record.zig
zig test src/persistent_semantic_state.zig
zig test src/pass8_realization_tests.zig
./zig-out/bin/duo realize examples/pass8/realization_smoke.duo  # run twice: fresh → reused
./zig-out/bin/duo catalog | jq '.pass8.milestones'
```

---

## Rejection criteria

- Profile observations as semantic guarantees
- Unbounded global solver before finite candidate selection
- Second semantic graph for persistence
- Compilation depending on online AI
- Persistent continuations without version compatibility
- Separate async/workflow sublanguage
