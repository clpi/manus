# Pass 8 — Persistent Semantic Computing & Negotiated Realization

> **Date:** 2026-08-04
> **Follows:** Passes 1-7
> **Thesis:** Programs are persistent semantic systems whose realizations evolve under constraints.
> **First milestone:** One realization variable with two candidates, deterministic selection, MCP inspection.

---

## Current Foundation (what exists to build on)

| Pass 8 Concept | Existing Foundation | Gap |
| --- | --- | --- |
| Realization freedom | `native_scalar_mode` / `mixed_scalar_mode` (binary) | Need per-entity granularity |
| Candidate selection | `can_emit_native_scalar_module` (one check) | Need registered alternatives |
| Evidence | `transform_engine.ProvenanceEntry` (log only) | Need classified evidence records |
| Semantic fingerprints | `types.tableShapeIdentityHash` | Need entity-level fingerprints |
| Persistent state | `.duo/cache/comptime/*.ducache` | Need cross-build semantic cache |
| Assumptions | Implicit in `native_scalar_mode` guards | Need explicit objects |
| Invalidation | None (full recompile always) | Need dependency-based |
| Dependencies | Implicit in codegen ordering | Need explicit graph |
| Continuations | Coroutines (codegen-specific) | Need unified model |
| Determinism | Not tracked | Need classification |
| Laws | Concept satisfies checks only | Need operational laws |
| Evolution | Not tracked | Need version lineage |

---

## What Pass 8 Adds (mapped to existing architecture)

| New Concept | Canonical Owner | Reuses |
| --- | --- | --- |
| Realization variable | `transform_engine.zig` | Descriptor + Hardness + CostVector |
| Realization candidate | `transform_engine.zig` | Transform contracts |
| Evidence record | `transform_engine.zig` | ProvenanceEntry (extended) |
| Degree of freedom | `semantic_algebra.zig` | KnowledgeLevel (extended) |
| Semantic fingerprint | `types.zig` / `sim.zig` | tableShapeIdentityHash pattern |
| Invalidation edge | `semantic_graph.zig` | Edge model (new edge kind) |
| Law | Descriptor contracts | Concept satisfies pattern |
| Determinism class | `semantic_algebra.zig` | New enum alongside Stage |
| Persistent cache | `.duo/cache/` | Existing comptime cache pattern |
| Continuation record | `ast.zig` coroutine + closures | Unified representation |

**Key principle:** Pass 8 adds NO new subsystems. It extends `transform_engine`, `semantic_algebra`, and `semantic_graph` with richer metadata.

---

## First Milestone (bounded, achievable)

**One realization variable with two candidates:**

For a table used as a lookup (`handlers[key]`), the compiler should expose:
- Variable: "dispatch representation for `handlers`"
- Candidate A: generic hash-table lookup (current default)
- Candidate B: compile-time perfect hash (when keys are frozen string literals)
- Constraint: keys must be compile-time-known
- Selection: based on key count + knowledge level
- Evidence: static analysis (keys are string literals in source)
- MCP query: `duo_realization_inspect("handlers")`
- Fallback: generic table (always valid)

This maps directly onto existing infrastructure:
- The transform engine already has `Descriptor` with `BudgetClass` and `CostVector`
- The knowledge lattice already classifies values (unknown → frozen → comptime)
- `duo sim` already exports entity metadata

---

## Ranked Implementation Plan

| Priority | Work | Prerequisite | Enables |
| --- | --- | --- | --- |
| 1 | Evidence enum in transform_engine | None | All decisions |
| 2 | Semantic fingerprint for functions/records | types.zig hash | Cross-build cache |
| 3 | Invalidation edge kind in semantic_graph | Graph exists | Incremental |
| 4 | Determinism classification enum | semantic_algebra | Replay, parallelism |
| 5 | Realization variable record | Transform engine + evidence | Selection |
| 6 | Two-candidate selection for table dispatch | Realization var | First demo |
| 7 | Persistent fingerprint store (`.duo/cache/sem/`) | Fingerprints | Cross-build |
| 8 | MCP realization_inspect tool | Variable + candidates | Agent access |
| 9 | Law enum on descriptors | Concept system | Transformations |
| 10 | Continuation record unification | Coroutine + closure analysis | Persistence |

---

## Architectural Convergence (Pass 6 alignment)

Pass 8 must NOT:
- Create a separate planner subsystem (use transform_engine)
- Create a separate evidence store (extend ProvenanceEntry)
- Create a separate dependency graph (extend semantic_graph edges)
- Create a separate fingerprint system (extend types.zig hashing)
- Create a separate persistence layer (extend .duo/cache/)

Pass 8 MUST:
- Extend existing `Descriptor` with realization metadata
- Extend existing `ProvenanceEntry` with evidence classification
- Extend existing `SemanticGraph.Edge` with invalidation kinds
- Extend existing `KnowledgeLevel` concepts for determinism

---

*Pass 8 is not about building a new system. It is about making existing compiler
decisions explicit, persistent, and negotiable — so the compiler can remember what
it learned and choose better next time.*
