# Pass 7 — AI-Native Compilation & Optimization Intelligence

> **Date:** 2026-08-04
> **Follows:** Passes 1-6 (identity → convergence → grammar → native → interchange → reconciliation)
> **Mission:** Make compiler knowledge, optimization decisions, and semantic constraints directly
> accessible to both humans and AI systems.

---

## Scope Boundary

**Inside Pass 7:**
- Structured optimization explanations
- Enforceable performance contracts (preference vs requirement)
- Knowledge snapshots and assumption objects
- Semantic transactions with diff/rollback
- AI-generated code normalization and validation
- Tensor/inference compilation paths (using existing descriptors)
- Agent semantic API expansion

**Outside Pass 7:**
- Operating systems, IDEs, package managers, deployment
- Non-deterministic compilation (AI proposes, compiler verifies)
- Broad model training infrastructure

---

## Current Foundation (what exists)

| Capability | Status | Location |
| --- | --- | --- |
| `@comp.why.shape` | ✅ Working | codegen.zig |
| `@comp.why` | ✅ Working | codegen.zig |
| `@comp.origin` | ✅ Working | codegen.zig |
| `@comp.why.boxed` | 🔄 Registered, handler exists | codegen.zig (returns C string type mismatch) |
| `@comp.why.not.native` | 🔄 Registered, handler exists | codegen.zig |
| `@comp.representation` | 🔄 Registered, handler exists | codegen.zig |
| Knowledge Lattice | ✅ Full enum + sema bridge | semantic_algebra.zig |
| Transform provenance | ✅ Log + DUO_PROVENANCE=1 | transform_engine.zig |
| SIM v0 export | ✅ `duo sim` command | sim.zig |
| Semantic graph | ✅ `duo graph` command | semantic_graph.zig |
| MCP semantic tools | ✅ 27 tools | duo-mcp/duo_bench.duo |
| Directive registry | ✅ ~130 directives | meta_module.zig |
| Contract hardness | ❌ NOT YET | — |
| Assumption objects | ❌ NOT YET | — |
| Optimization outcomes | ❌ NOT YET | — |
| Semantic transactions | ❌ NOT YET | — |
| Tensor descriptors | ❌ NOT YET | — |

---

## Ranked Implementation Plan

| Priority | Workstream | Prerequisite | Connects |
| --- | --- | --- | --- |
| 1 | **Contract hardness on directives** | Directive registry | Everything |
| 2 | Structured optimization outcomes | Transform engine | Explanations |
| 3 | Knowledge snapshots (per-phase) | Semantic algebra | Agent queries |
| 4 | `@comp.why.*` return structured JSON | Codegen handlers | LSP + MCP |
| 5 | Semantic transaction preconditions | SIM + semantic graph | Agent edits |
| 6 | Generated-code normalization | Formatter + parser | AI target |
| 7 | Tensor descriptor prototype | Descriptors + shapes | AI workloads |
| 8 | Numerical precision contracts | Contract system | AI correctness |
| 9 | Operator transformation registry | Transform engine + SIM | Inference |
| 10 | Learned cost model infrastructure | Benchmarks + outcomes | Future |

---

## First Milestone: Contract Hardness

Every directive should carry a `hardness` field:

```
preference  — compiler may ignore (e.g. @prefer.inline)
expectation — compiler warns when unmet (e.g. @expect.vectorized)
requirement — compilation fails when unmet (e.g. @require.noalloc)
assertion   — programmer claims fact, compiler verifies (e.g. @assert.pure)
budget      — fails when measured/estimated limit exceeded (e.g. @budget.stack(512))
```

This is implemented in `transform_engine.zig` as part of the `Descriptor` struct — adding a
`Hardness` enum that existing directives can use.

---

## Architecture Mapping (no new systems needed)

| Pass 7 Concept | Existing Foundation |
| --- | --- |
| Contract hardness | `transform_engine.Descriptor` + directive registry |
| Knowledge snapshots | `semantic_algebra.KnowledgeLevel` projections |
| Assumption objects | Transform engine preconditions |
| Optimization outcomes | Transform engine provenance log |
| Repair candidates | Diagnostic system (term.zig) |
| Tensor descriptors | `ast.TypeExpr` + `types.ResolvedType` |
| Model import | SIM + `c_frontend.zig` pattern |
| Agent transactions | Semantic graph + SIM mutations |

**Key principle:** Pass 7 adds NO new architectural systems. It enriches existing ones.

---

*Pass 7 is not about building AI infrastructure. It is about making Duo's existing
compiler knowledge so well-structured that AI systems can use it directly.*
