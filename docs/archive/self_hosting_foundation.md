# Duo Self-Hosting Foundation (Operational Projection)

> **Canonical constitution:** [`duo_self_hosting_foundation.md`](duo_self_hosting_foundation.md) — pure spec (§1–§12). **This file** adds repo anchors, F-G status, and cross-references. Where they disagree, the canonical spec wins.

Machine-readable catalog: `src/foundation_catalog.zig`  
Gate: `zig build foundation-gate` (alias `self-hosting-foundation-gate`)

---

## 1. Core Rule: Language Monoculture

All production implementation converges to Duo.

**In scope:** compiler (all phases), parser/lexer, formatter, semantic graph, descriptor + shape system, compile-time system, all IR layers, instruction selection, register allocation, backend(s), runtime, stdlib, build, package system, shell, LSP, MCP, Ward, testing/benchmarking, release tooling.

**Repo anchors:** `dependency_manifest.zig`, `removal_ledger.zig`, Pass 4 (`docs/plans/pass4_native_end_to_end.md`), Pass 16 (`docs/plans/pass16_self_hosted_compiler.md`).

---

## 1.1 Allowed Non-Duo Code (Strictly Bounded)

| Class | Role | Repo anchor |
|-------|------|-------------|
| **A. Bootstrap** | S0 Zig; temporary C/system backends | `dependency_manifest` class `bootstrap`; `build.zig` |
| **B. Foreign boundary** | OS/ABI/ecosystem glue | class `platform_interface`; `foreign_adapter.zig` |
| **C. Differential reference** | Non-authoritative validation | `token_semantic.zig` (oracle); Wasmtime comparisons |
| **D. Disposable utilities** | Scripts/generators/migrations | `removal_ledger.zig`; must have deletion gate |

Rule: **no deletion gate = architectural debt** (`removal_ledger.zig`, §9 below).

---

## 2. Compiler Bootstrap Ladder

| Stage | Role | Status | Anchor |
|-------|------|--------|--------|
| **S0** | Trusted bootstrap (Zig); builds S1; frozen after S1 viability | **current** | `src/*.zig`, `bootstrap_dag.zig` |
| **S1** | First Duo compiler (lexer→HIR→backend subset) | partial | Pass 16 M1; `lib/std/compiler/*` |
| **S2** | S1 compiles itself | open | Pass 16 M4 |
| **S3** | S2 recompiles itself (reproducibility closure) | open | `bootstrap_dag.zig` |

S0 constraints (after S1 viability): correctness, reproducibility, security fixes only — no architectural evolution.

---

## 3. Canonical Semantic Graph (Single Source of Truth)

All meaning lives in one graph. **No subsystem may define independent semantic truth.**

**Implementation:** `src/semantic_graph.zig`, `docs/semantic_universe.md`, Pass 22/26.

Subsystems must consume **projections** only: compiler, formatter, LSP, MCP, Ward, documentation, foreign imports.

Node and edge type registries: `foundation_catalog.zig` (`semantic_node_kinds`, `semantic_edge_kinds`).

---

## 4. IR System (Unified Multi-Layer Model)

Single transformation pipeline over structured graphs. Layer registry: `foundation_catalog.zig` (`ir_layers`).

| Layer | ID | Purpose | Current anchor |
|-------|-----|---------|----------------|
| 4.1 Syntax graph | `IR-01` | Surface truth, trivia, provenance | `parser.zig`, `ast.zig` |
| 4.2 Semantic graph | `IR-02` | Meaning, descriptors, effects | `semantic_graph.zig`, `sema.zig` |
| 4.3 Executable region | `IR-03` | Structured execution pre-linearization | `transform_engine.zig` (partial) |
| 4.4 Specialized graph | `IR-04` | Box/unbox, guards, materialization | `realization`, Pass 27 evidence |
| 4.5 Representation IR | `IR-05` | Physical mapping | `pass26_descriptor_identity.zig` |
| 4.6 SSA / scheduled | `IR-06` | CFG + explicit effects | future / `native_backend` subset |
| 4.7 Low-level IR | `IR-07` | Target-independent machine form | `native_backend.zig` (partial) |
| 4.8 Machine IR | `IR-08` | Target-specific (AArch64 first) | `native_backend.zig`, Ward |
| 4.9 Artifact IR | `IR-09` | Objects, sections, relocations | `native_backend.zig` Mach-O |

Rule: **backend limitations may not introduce semantic dynamism** (Pass 27 `provisional-boxed-path` vs `direct-native-subset`).

---

## 5. IR Invariants (Global Laws)

Encoded in `foundation_catalog.zig` (`ir_invariants`). Enforced incrementally via Pass 27 proof bundles and native barrier checks.

1. Identity preserved across all lowering  
2. Knowledge is monotonic (no silent loss)  
3. All loss must be explicit  
4. Boxing/allocation is explicit IR  
5. Return packs are first-class  
6. Calls retain full metadata  
7. Every transformation produces evidence  
8. Machine code is a projection, not truth  

---

## 6. Compiler Foundation Freeze (Minimal Stable Core)

Overlaps Pass 26 foundational closure. Freeze only what S1 requires — see `foundation_catalog.zig` (`foundation_freeze_domains`).

---

## 7. Self-Hosting Execution Plan (Phases 1–10)

Mapped to `execution_phases` in catalog; primary owner Pass 16 workstreams (`pass16_catalog.zig`).

1. Substrate (Byte/Slice/Cursor/IDs/arenas)  
2. Lexer  
3. Parser + syntax graph  
4. Semantic graph  
5. HIR  
6. Compile-time system  
7. Representation + SSA  
8. Bootstrap backend (S0 boundary or C)  
9. Native backend (AArch64 + Mach-O)  
10. Object + linker  

---

## 8. Repository Roles

| Repo | Role |
|------|------|
| **duo** | S0 bootstrap, compiler, runtime, stdlib, IR, backends |
| **ward** | Execution validation, ABI/memory/JIT testing |
| **duo-lsp** | Fully Duo; no JS semantic core |
| **duo-mcp** | Semantic graph + IR service layer |

---

## 9. Foreign Code Elimination Ledger

Each foreign file must declare: role, authority, replacement, prerequisites, migration stage, **deletion gate**, status.

**Anchors:** `dependency_manifest.zig` (dependencies), `removal_ledger.zig` (host retirement).  
Gate **F-G08** tracks ledger completeness.

---

## 10. Immediate Work Program

See `foundation_catalog.zig` (`immediate_workstreams`) — ordered foundation → IR → self-hosting → migration control.

**Pass 27** provides §5 evidence infrastructure (honest benchmarks, emission counters, Ward direct micro-proofs) — prerequisite for claiming IR invariant compliance, not self-hosting progress itself.

---

## 11. Foundation Completion Gate

Met when **F-G01..F-G10** all pass (see catalog). Staged gates — not a single monolithic milestone.

| Gate | Title | Status |
|------|-------|--------|
| F-G01 | Semantic graph + stable IDs | partial |
| F-G02 | Syntax→semantic lowering | partial |
| F-G03 | Explicit specialization (no silent boxing) | partial |
| F-G04 | SSA→LIR→MIR one target | partial |
| F-G05 | Artifact IR (Mach-O) | partial |
| F-G06 | S1 compiler subset in Duo | open |
| F-G07 | S2 self-host | open |
| F-G08 | Foreign elimination ledger complete | partial |
| F-G09 | MCP/LSP/Ward same graph view | open |
| F-G10 | No permanent foreign without gate | partial |

Validate schema: `zig build foundation-gate`.

---

## 12. Core Principle

**Do not translate Zig.**

Build in order: semantic graph → executable region graph → representation IR → SSA → LIR → machine IR → native substrate → bootstrap boundary.

The self-hosted compiler is the first full realization of a **graph-native, multi-layer semantic compiler** built directly in Duo — not a Zig port.

---

## Cross-References

- Bootstrap DAG: `src/bootstrap_dag.zig`
- Self-hosting matrix: `src/selfhosting_matrix.zig`
- Proof carrying: `src/proof_carrying.zig`
- Pass 27 evidence: `docs/plans/pass27_proof_bundle.md`, `zig build bench-proof-gate`
- Agent alignment: `docs/AGENT_ALIGNMENT.md`
