# Semantic Graph Design Document

**Created: 2026-08-04**  
**Status: P0 - Architectural Priority**

## Executive Summary

Duo is evolving from "a metaprogramming language" to "an infrastructure for semantic computation." This document defines how the compiler and runtime manage a **persistent semantic graph** where:

- Every type, value, function, and transformation is a **graph node**
- Every `@comp.*` directive is a **graph transformation**
- Agents collaborate by **mutating the shared semantic graph**
- All operations are **capability-bounded** and **auditable**

---

## Core Concepts

### 1. Semantic Nodes

All semantic entities are nodes in the graph:

```
Node Types:
  - Type: record, array, ptr, scalar, tensor, func, concept
  - Value: int, float, str, bool, nil, table, closure
  - Transform: @comp.map, @comp.derive, @comp.product, etc.
  - Storage: module, scope, closure, table, func_body
  - Artifact: C type, asm instruction, GPU kernel
```

Each node has:
- **ID**: Content-addressed (SHA256 of semantic meaning)
- **Kind**: Type/Value/Transform/Storage/etc.
- **Inputs**: List of upstream node IDs
- **Outputs**: List of downstream node IDs
- **Metadata**: cost, capabilities, provenance, cache_key

### 2. Graph Transactions

All mutations to the semantic graph are ACID transactions:

```duo
// Pseudo-code for transaction API
graph.begin("transformation")
  .create(@comp.derive.output)
  .link(input_type, output_type, @comp.derive.transform)
  .commit()
```

Transactions support:
- Rollback on compile error
- Concurrent reads, exclusive writes
- Provenance tracking
- Capability budget enforcement

### 3. Capability System

Every transformation requires a capability token:

```
Capability Types:
  - @capability.type.infer (type checking)
  - @capability.native.lower (native codegen)
  - @capability.ffi.call (C FFI)
  - @capability.ml.kernel (GPU/CPU kernels)
  - @capability.meta.transform (metaprogramming)

Budget enforcement:
  @comp.capability.consume(@capability.native.lower, budget=1000)
  // Fails if budget exceeded
```

---

## Integration with Current @comp.* Hierarchy

### Tier 1: Type Manipulation (@comp.type.*)
- `@comp.type.name`, `@comp.type.info`, etc. become graph queries
- Output nodes are cached by input node ID

### Tier 2: Derive Macros (@comp.derive.*)
- Transform nodes that modify the type graph
- `@comp.derive.all` = batch transform over matching types
- Provenance: which derive, which type, which fields

### Tier 3: Exponential Combinators
- `@comp.map` → graph sweep (O(n))
- `@comp.product` → graph product (O(n²))  
- `@comp.nfold` → graph n-fold product (O(n^k))

All produce **transform nodes** with proper provenance.

---

## Implementation Roadmap

### Phase 1: Core Graph Types (P0)
**Duration:** 2 weeks

Files:
- `lib/std/graph/node.duo` — Node type system
- `lib/std/graph/id.duo` — Content-addressed IDs (SHA256)
- `lib/std/graph/txn.duo` — Transaction system

Deliverables:
- Node creation/query APIs
- Basic transaction semantics
- ID stability guarantees

### Phase 2: Directive Integration (P1)
**Duration:** 3 weeks

Files:
- `src/codegen/graph.zig` — Graph-aware codegen
- `src/sema/zig` — Graph-aware semantic analysis
- Updates to `src/meta_module.zig`

Deliverables:
- `@comp.*` directives produce traceable graph nodes
- Provenance tracking for all transforms
- Cache validity conditions

### Phase 3: Capability System (P2)
**Duration:** 2 weeks

Files:
- `lib/std/capability.duo` — Capability types
- `src/codegen/caps.zig` — Capability enforcement

Deliverables:
- Capability tokens for all operations
- Budget enforcement API
- Security model for third-party code

### Phase 4: Agent Collaboration (P3)
**Duration:** 2 weeks

Files:
- `lib/std/agent/workspace.duo` — Shared graph workspace
- `duo-mcp/duo_graph.duo` — MCP tools for graph operations

Deliverables:
- Transactional editing primitives
- Agent coordination hooks
- Workspace persistence

---

## Coordination Protocol

All agents working on semantic graph infrastructure:

1. **Claim** your area via `.agents/AGENT_COORDINATION.md`
2. **Use MCP tools** (`duo_agent_gaps_update`) to update status
3. **Update performance.md ledger** after benchmark-affecting changes
4. **Never duplicate** node types across implementations
5. **Coordinate** on shared files (node.duo, txn.duo, caps.zig)

---

## Implementation status (2026-08-04)

Phase 1 spine is landing in the compiler (no codegen behavior change required for graph reads):

| Component | Location | Status |
| --- | --- | --- |
| Table shape ladder | `src/types.zig` — `StorageClass`, `inferStorageClass`, `applyTableShapeAttrs` | **Done** — typed all-native records default to `.native` |
| Sema wiring | `src/sema.zig` — `apply_record_layout_attrs` → `types.applyTableShapeAttrs` | **Done** |
| Codegen shape attrs | `src/codegen.zig` — alias/binding record attrs + `@comp.type.shape` (`__type_shape`) | **Done** |
| Shape introspection | `@comp.type.shape(expr)` → `"dynamic"\|"guarded"\|"sealed"\|"native"` | **Done** |
| Graph `table_shape` nodes | `src/semantic_graph.zig` — `liftAliasShapes`, `liftModuleFull` | **Done** — unit tests |
| Graph `enum_shape` nodes | `src/semantic_graph.zig` — `liftEnumShapes` | **Done** — variant names via `ast_ref` |
| Graph JSON export | `duo graph <file>` + `SemanticGraph.writeJson` | **Done** — `table_shapes`, `enum_shapes` arrays |
| MCP shape query | `duo-mcp/duo_lsp.duo` — `duo_table_shapes` | **Done** |
| Transform provenance stub | `src/transform_engine.zig` + `DUO_PROVENANCE=1` + `@comp.match` fold logging | **Partial** — `@comp.match` wired; other combinators next |
| Demo | `examples/table_shape_smoke.duo` | **Done** |

Next: guarded codegen path (shape guards in field access), graph persistence, descriptor `@{}` enum prototype.

| Inline binding lift | `liftFunctionBindings` — `main::pt2@shape`, `type_of` edges | **Done** |
| `@guarded` attribute | `types.applyTableShapeAttrs` + parser | **Done** |
| Enum `shape_id` | `types.enumShapeIdentityHash` | **Done** |

---

## Open Questions

1. **Node persistence**: Where is the graph stored?
   - In-memory with snapshot export
   - SQLite/WebDB with WAL

2. **ID stability**: Do semantically equivalent constructs get the same ID?
   - Content hashing of normalized AST?
   - Semantic fingerprinting

3. **Provenance depth**: How much history to track?
   - Full transformation DAG
   - Just immediate input→output