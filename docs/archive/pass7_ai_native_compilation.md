# Pass 7 — AI-Native Compilation, Semantic Optimization Intelligence

**Status:** Phase 0 bootstrap **partial** (2026-08-04) — `duo catalog` → `pass7` JSON fixed; `duo explain` live
**Principle:** Compiler knowledge explicit, structured, verifiable — AI proposes, compiler verifies  
**Catalog:** `duo catalog` → `pass7` via `src/pass7_catalog.zig`  
**CLI:** `duo explain <file>` — knowledge snapshots + optimization outcomes (Milestone 1 foundation)

Passes 1–6 established convergence, native backends, SIM, and architectural reconciliation. **Pass 7 extends** them toward AI-generated code, agent semantic APIs, and optimization intelligence — without turning Duo into an OS, IDE, or ML framework.

> Repository implementation always overrides architecture documents.

---

## Scope boundary

**In scope:** language semantics, compiler architecture, optimization explainability, contracts, agent MCP/LSP facts, tensor/inference compilation paths, provenance, semantic transactions.

**Out of scope:** Git replacement, issue trackers, cloud control planes, universal package registries, autonomous software companies, broad “semantic operating systems.”

Duo owns **language and compiler semantics**. External tools consume facts through SIM, `duo explain`, and MCP.

---

## Six goals (summary)

| Goal | Direction |
| --- | --- |
| **A** | Best compilation target for AI-generated code — compiler compensates for generic generated code |
| **B** | Compiler knowledge queryable by agents (same facts as LSP) |
| **C** | Enforceable semantic/performance contracts with explicit hardness |
| **D** | Optimization explainable via structured outcome records |
| **E** | AI/inference workloads through descriptors, shapes, SIM import |
| **F** | Semantic transactions for agent edits |

---

## Repo-truth audit (2026-08-04)

| Area | Current owner | Status |
| --- | --- | --- |
| Knowledge lattice | `semantic_algebra.KnowledgeLevel` | partial — sema + codegen gates |
| `@comp.why.*` | `codegen.zig` + `transform_engine` registry | partial — string explanations, provenance hashes |
| Provenance log | `transform_engine.zig` | partial — `DUO_PROVENANCE=1` |
| SIM agent boundary | `sim.zig`, `sim_pipeline.zig` | partial — graph enrichment |
| Contracts `@pure`/`@noalloc` | `contract_model.zig` + `codegen.zig` guard | partial — `@noalloc` enforced at `mem.alloc`/`calloc`/`realloc` + closure malloc |
| Tensor types | `types.zig`, `sema.zig` tensor ops | partial — no full representation selection |
| MCP semantic tools | `duo-mcp/duo_shared.duo` | partial — snapshot, catalog |
| LSP semantic queries | `duo-lsp/server.duo` | blocked — native compile of server |
| Semantic transactions | `semantic_graph.zig` (design only) | open |

---

## Initial milestones

| ID | Title | Status |
| --- | --- | --- |
| **P7-M1** | Structured optimization explanation | **partial** — `duo explain`, snapshots, outcomes |
| **P7-M2** | Enforceable noalloc contract | **partial** — codegen guard + `pass7_contract_tests` |
| **P7-M3** | Semantic agent edit via MCP | open |
| **P7-M4** | Static tensor kernel | open |
| **P7-M5** | Imported inference operator | open |

---

## Implementation order (dependency-driven)

```
canonical compiler facts
    → knowledge snapshots (P7-03) ✅ partial
    → assumption/guard model (P7-04) ✅ partial — `buildFromModule` + `duo explain`
    → optimization outcomes (P7-05) ✅ partial
    → contract hardness (P7-02) ✅ partial — `@noalloc` codegen + repairs
    → semantic fingerprints (P7-07) ✅ partial — entity fingerprints in snapshots
    → @comp.why + repair records (P7-06)
    → MCP queries (P7-11)
    → semantic transactions (P7-10)
```

AI workloads: descriptor stability → tensor descriptor → static shape specialization → SIM model import → operator transforms.

---

## New modules (this session)

| Module | Role |
| --- | --- |
| `src/contract_model.zig` | Hardness enum + contract catalog (`@pure`, `@noalloc`, …) |
| `src/knowledge_snapshot.zig` | Immutable phase snapshots (not a second graph) |
| `src/optimization_outcome.zig` | Structured transform outcomes + provenance bridge |
| `src/explain_pipeline.zig` | Full codegen for `duo explain` provenance |
| `src/assumption_guard.zig` | Assumption/guard catalog + JSON (P7-04 partial) |
| `src/repair_candidate.zig` | Structured repair patterns for diagnostics (P7-06 partial) |
| `src/semantic_fingerprint.zig` | Canonical semantic hashing (P7-07 partial) |
| `src/pass7_contract_tests.zig` | `@noalloc` enforcement tests |

---

## Agent claim tags

`pass7-audit`, `pass7-contracts`, `pass7-snapshots`, `pass7-outcomes`, `pass7-explain`, `pass7-mcp`, `pass7-tensor`, `pass7-tx`

---

## Validation

```bash
zig build
zig test src/pass7_catalog.zig
zig test src/knowledge_snapshot.zig --test-filter "knowledge_snapshot:"
zig test src/contract_model.zig
zig test src/optimization_outcome.zig
./zig-out/bin/duo explain examples/pass4_native_milestone.duo
./zig-out/bin/duo catalog | jq '.pass7.milestones'
```

---

## Rejection criteria (Pass 7)

- Second semantic graph for agents
- Compilation requiring online AI
- Heuristics labeled as proofs
- Direct model import into backend-private IR
- Directives without hardness distinction
- MCP/LSP duplicating compiler analysis

See full spec in agent coordination buffer and Pass 7 prompt §18.
