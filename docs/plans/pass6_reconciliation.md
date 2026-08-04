# Pass 6 — Architectural Reconciliation

> **Date:** 2026-08-04
> **Purpose:** Ensure architecture converges before implementation expands further.
> **Principle:** If a subsystem disappeared tomorrow and the compiler became simpler, merge/remove it.

---

## Executive Summary

### Top 5 Architectural Risks

1. **codegen.zig is 28K lines** — contains embedded re-parsing (imports lexer+parser 80+ times), inline runtime, mixed-mode thunk generation, comptime evaluation, meta-hook dispatch, and native-scalar detection. Should be 5-6 smaller files.

2. **Three parallel meta-dispatch systems** — `fold_meta_string_expr`, `comptimeMetaHook`, `maybe_emit_meta_string_call` in codegen all do the same job (evaluate comptime combinators and emit native strings). Pass 2 identified this; it's still unfixed.

3. **Codegen re-imports parser/lexer 80+ times** — to re-parse embedded modules at codegen time. This creates a massive cyclic coupling (codegen → parser → lexer; parser → meta_module; codegen → sema → parser). The embedded-module parsing should be moved to a pre-pass.

4. **SIM (sim.zig) and semantic_graph.zig overlap** — both export typed entities with names, shapes, and metadata. SIM should be a projection of the semantic graph, not a parallel system.

5. **Pass-specific catalogs proliferate** — `pass3_catalog.zig`, `pass4_catalog.zig`, `pass5_catalog.zig` each maintain separate runtime catalogs. Should be one catalog system with pass-tagged entries.

### Top 5 Simplification Opportunities

1. **Extract embedded runtime from codegen.zig** — the `duo_runtime` C preamble (~5000 lines of C-in-Zig-strings) should be a separate file, not inline in codegen.
2. **Merge the three meta-dispatch paths** — one `applyComptimeCombinator()` function.
3. **SIM derives from semantic_graph** — `sim.zig:exportNativeModule` should call `semantic_graph.zig` not duplicate sema queries.
4. **One catalog system** — merge `pass3_catalog`, `pass4_catalog`, `pass5_catalog` into `src/catalog.zig`.
5. **Codegen split** — native-scalar emission, lua-thunk emission, runtime preamble, and embedded-module handling should be separate modules.

---

## Compiler Dependency DAG

```
lexer.zig (1309 lines)
    ↓
parser.zig (6144 lines)
    ↓ ↗ meta_module.zig (1760)
ast.zig (785)
    ↓
types.zig (1855)
    ↓
sema.zig (9116) ← semantic_algebra.zig (1224)
    ↓               ↓
    ↓         transform_engine.zig (668)
    ↓               ↓
    ↓         semantic_graph.zig (1492)
    ↓               ↓
    ↓           sim.zig (454)
    ↓
codegen.zig (27975) ← comptime.zig (1634)
    ↓                 ← meta_codegen.zig (3657)
    ↓                 ← mono.zig (1124)
    ↓                 ← dynamic_boundary.zig (135)
    ↓
native_backend.zig (2140) [alternative to codegen C output]
    ↓
main.zig (2779) [orchestration]
```

### Critical Coupling Issues

| Issue | Files | Severity |
| --- | --- | --- |
| codegen imports parser/lexer 80+ times | codegen ↔ parser/lexer | Critical |
| sema imports foreign_adapter which imports sim | sema ↔ sim (circular risk) | High |
| codegen has inline 5000-line C runtime | codegen self-contained but massive | High |
| meta_codegen is really "codegen comptime helpers" | naming confusion | Medium |

---

## Canonical Source-of-Truth Table

| Concept | Canonical Owner | Status |
| --- | --- | --- |
| Token/keyword definitions | `lexer.zig` | ✅ Single owner |
| AST node types | `ast.zig` | ✅ Single owner |
| Type resolution | `types.zig` | ✅ Single owner |
| Type checking / scoping | `sema.zig` | ✅ Single owner |
| Grammar rules | `parser.zig` | ✅ Single owner |
| Directive registry | `meta_module.zig` | ✅ Single owner |
| Knowledge lattice | `semantic_algebra.zig` | ✅ Single owner |
| Transform registration | `transform_engine.zig` | ✅ Single owner |
| Semantic graph | `semantic_graph.zig` | ⚠️ Overlaps with sim.zig |
| SIM export | `sim.zig` | ⚠️ Duplicates semantic_graph queries |
| Comptime evaluation | `comptime.zig` | ⚠️ Also in codegen's inline hooks |
| Meta-combinator execution | 3 OWNERS: codegen fold paths | ❌ DUPLICATE |
| C code generation | `codegen.zig` | ✅ But too large |
| Native arm64 emission | `native_backend.zig` | ✅ Single owner |
| Formatting | `pretty.zig` | ✅ Single owner |
| Mono specialization | `mono.zig` | ✅ Single owner |
| Derive evaluation | `derive_registry.zig` + `derive_eval.zig` | ⚠️ Split across 2 |
| Pipeline generation | `pipeline_gen.zig` | ✅ Single owner |
| Foreign transpilation | `foreign_transpile.zig` | ✅ Single owner |
| C import (Pass 5) | `c_frontend.zig` + `c_sim_import.zig` | 🔄 New, evolving |
| ABI specialization | `abi_specialize.zig` | ✅ Single owner (new) |

---

## Duplication Matrix

| Duplicated Concept | Implementation A | Implementation B | Implementation C | Priority |
| --- | --- | --- | --- | --- |
| Comptime string generation | `fold_meta_string_expr` | `comptimeMetaHook` | `maybe_emit_meta_string_call` | **Critical** |
| Semantic entity export | `semantic_graph.writeJson` | `sim.exportNativeModule` | — | High |
| Pass catalogs | `pass3_catalog.zig` | `pass4_catalog.zig` | `pass5_catalog.zig` | Medium |
| Directive alias lookup | `meta_module.resolveBuiltin` | `parser.zig` flat table | — | Medium |
| Embedded module parse | codegen inline `Parser.init` | — | — | Medium |
| Derive infrastructure | `derive_registry.zig` | `derive_eval.zig` | — | Low |

---

## Convergence Scorecard (0-5)

| Subsystem | Simplicity | Consistency | Optim | Tooling | Agent | Extensible | Ready |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Lexer | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| Parser | 4 | 4 | 4 | 4 | 4 | 4 | 5 |
| AST | 4 | 4 | 4 | 4 | 4 | 4 | 5 |
| Types | 4 | 4 | 4 | 3 | 3 | 4 | 5 |
| Sema | 3 | 3 | 4 | 3 | 3 | 3 | 4 |
| Knowledge Lattice | 5 | 5 | 5 | 5 | 5 | 5 | 4 |
| Transform Engine | 4 | 5 | 4 | 4 | 5 | 5 | 3 |
| Semantic Graph | 4 | 4 | 3 | 4 | 4 | 4 | 4 |
| SIM | 4 | 4 | 3 | 5 | 5 | 4 | 3 |
| Codegen | **1** | 2 | 3 | 2 | 2 | 2 | 5 |
| Meta-dispatch | **1** | 1 | 3 | 1 | 1 | 1 | 5 |
| Native Backend | 4 | 4 | 4 | 3 | 3 | 3 | 3 |
| Comptime | 3 | 3 | 4 | 2 | 2 | 3 | 4 |
| Pretty/Formatter | 4 | 4 | N/A | 4 | 4 | 4 | 5 |
| MCP | 4 | 4 | N/A | 5 | 5 | 4 | 4 |

**Lowest scores:** Codegen (1/5 simplicity), Meta-dispatch (1/5 everything).

---

## Required Refactors (by priority)

### 1. Unify meta-dispatch (Critical)

**Current:** Three codegen paths evaluate comptime combinators:
- `fold_meta_string_expr` (~line 11870) — string-value fold
- `comptimeMetaHook` (~line varies) — hook-based dispatch
- `maybe_emit_meta_string_call` — call-site emission

**Target:** One `applyComptimeCombinator(name, args, site) → ?string` that all three paths delegate to.

**Benefit:** Eliminates the G-060 class of bugs (inconsistent parse between sites), reduces codegen by ~500 lines, makes new combinators one-site additions.

### 2. Extract runtime preamble (High)

**Current:** ~5000 lines of C runtime (lua_Value, lua_table_*, gc, etc.) are embedded as Zig string literals inside codegen.zig.

**Target:** `src/runtime.c` or `src/runtime_preamble.zig` — a separate file that codegen includes.

**Benefit:** codegen.zig drops from 28K to 23K lines. Runtime becomes independently testable.

### 3. SIM derives from semantic_graph (High)

**Current:** `sim.zig:exportNativeModule` re-queries sema directly.

**Target:** `sim.exportFromGraph(graph)` — SIM is a JSON projection of the semantic graph, not a parallel query system.

**Benefit:** One entity model, one export path, consistent IDs.

### 4. Merge pass catalogs (Medium)

**Current:** `pass3_catalog.zig`, `pass4_catalog.zig`, `pass5_catalog.zig` — separate files with overlapping patterns.

**Target:** One `src/catalog.zig` with tagged entries (pass, category, status).

### 5. Move embedded-module parse to pre-pass (Medium)

**Current:** codegen imports parser/lexer to re-parse `req()` modules inline during emission.

**Target:** A sema pre-pass resolves all `req()` modules and produces a module-graph before codegen starts. Codegen receives a resolved module tree, not raw source paths.

---

## Architecture Risk Register

| Risk | Severity | Cause | Mitigation |
| --- | --- | --- | --- |
| codegen.zig becomes unmaintainable | **Critical** | 28K lines, 3 dispatch paths, inline runtime | Split into modules |
| New combinators added without parity | High | G-060 class — 3 independent fold paths | Unify dispatch |
| SIM and semantic_graph diverge | High | Parallel implementations | SIM derives from graph |
| Mixed-mode codegen has subtle bugs | High | Thunk registration, mode selection logic | Test matrix needed |
| Cursor agent may reintroduce `.any` as native | Medium | No CI gate for this specific invariant | Add unit test |
| Pass catalogs grow unbounded | Medium | Each pass adds its own catalog file | Merge into one |
| Knowledge lattice underutilized | Medium | Only module-level + one per-call site | Wire more decisions |

---

## True Dependency Order (corrected roadmap)

```
1. Lexer → Parser → AST                    [COMPLETE]
2. Types → Sema                             [COMPLETE]
3. Knowledge Lattice (semantic_algebra)     [COMPLETE - wired partially]
4. Descriptor Algebra (convergence types)   [COMPLETE - spine exists]
5. Shape Algebra (storage class + ops)      [COMPLETE - wired]
6. Transform Engine (contracts + registry)  [COMPLETE - partial dispatch]
7. Semantic Graph (persistent entities)     [COMPLETE - DUO_GRAPH=1, duo graph]
8. Codegen split (prerequisite for clean backend) [NOT STARTED - highest leverage]
9. Meta-dispatch unification                [NOT STARTED - second highest]
10. SIM as graph projection                 [IN PROGRESS - Cursor agent]
11. Native backend expansion (struct access) [PROVEN for f64 records]
12. C import (Parse → SIM → descriptors)   [IN PROGRESS - Cursor agent]
13. Shared transformations (abi.specialize) [IN PROGRESS - Cursor agent]
14. Runtime extraction and modularization   [NOT STARTED]
15. Self-hosting Stage 2 (core libraries)   [FUTURE]
```

**Key insight:** Steps 8-9 (codegen split + meta-dispatch unification) should happen BEFORE steps 10-13 expand further. The Cursor agent's Pass 5 work is good but building on an unstable 28K-line codegen base.

---

## Canonical Glossary

| Term | Definition | Owner |
| --- | --- | --- |
| Descriptor | Semantic declaration of a type/concept/protocol/enum | descriptor algebra |
| Shape | Structural storage layout (storage class + fields) | types.zig + semantic_algebra |
| Knowledge Level | How much the compiler knows (unknown→native) | semantic_algebra.KnowledgeLevel |
| Stage | Evaluation phase (parse→compile→runtime→gpu) | semantic_algebra.Stage |
| Effect | Side-effect category (pure, io, alloc, etc.) | semantic_algebra.EffectSet |
| SIM | Semantic Interchange Model (versioned export boundary) | sim.zig |
| Transform | Registered graph→graph operation with contract | transform_engine |
| CallSite | Semantic call object (callee, args, effects, stage) | semantic_algebra.CallSite |
| CostVector | Multi-dimensional optimization objective | semantic_algebra.CostVector |
| Native scalar | Value that lowers to bare C scalar (no lua_Value) | codegen native path |
| Mixed mode | Module with both native and dynamic functions | codegen.mixed_scalar_mode |
| Provenance | Origin + transformation history of any entity | transform_engine.ProvenanceEntry |
| Directive | `@name` or `@comp.*` compiler instruction | meta_module.zig |
| Combinator | Comptime code-generation transform (O(n)→O(n!)) | meta_codegen.zig |

---

*Pass 6 reveals: Duo's architecture is sound in design but the 28K-line codegen is
the bottleneck for everything. Splitting it and unifying meta-dispatch are prerequisites
for clean expansion of Pass 4-5 work.*
