# Pass 9 — Ward Readiness, Vertical Proof, and Runtime Supremacy

**Status:** Phase 0 bootstrap **started** (2026-08-04)  
**Mission:** Make Duo capable of producing **Ward** — a Duo-native WebAssembly runtime faster than Wart, substantially smaller and clearer, generated through Duo's canonical semantic, staging, specialization, representation, and realization systems.  
**Catalog:** `duo catalog` → `pass9` via `src/pass9_catalog.zig`

> Repository implementation always overrides architecture documents.

---

## Scope boundary

**In:** Ward readiness matrix, capability ladder, first vertical kernel (descriptor-generated Wasm decode/validate), Duo systems-programming gaps exposed by Ward, semantic-density and differential proof harnesses, LSP/MCP Ward facts.

**Out:** Broad Wart port before Duo readiness; Ward-only language features; separate Wasm semantic graph; optimizing JIT before decoder/validator foundations; benchmark claims without comparable semantics.

**Repositories:**

| Repo | Path | Role |
| --- | --- | --- |
| Duo compiler/stdlib | `~/x/duo` | Canonical semantics, codegen, realization, tooling |
| Ward runtime | `~/x/ward` | Vertical proof consumer (must not fork Duo architecture) |
| Wart reference | `~/x/wart` | Performance/conformance reference (do not copy line-for-line) |
| duo-mcp | `~/x/duo-mcp` | Development MCP — coordination + proof tracking (not second semantic authority) |
| duo-lsp | `~/x/duo-lsp` | Editor integration — same facts as compiler |

---

## Governing principles

1. **Ward is a consumer, not an architectural fork** — no Ward-specific descriptors, staging, IR, planner, or semantic graph.
2. **Duo readiness precedes Ward dependence** — capabilities below `WARD_READY` require an explicit work item to reach readiness.
3. **Beat Wart through leverage** — equivalent semantics, validation, safety; win via compile-time generation, representation negotiation, specialized dispatch, semantic density.
4. **No hidden delegation** — no embedding Wart, generic Lua boxing on hot paths, or generated-C as canonical implementation without disclosure.

---

## Primary goals

| Goal | Description | Status |
| --- | --- | --- |
| **A** | Machine-readable Ward readiness contract | **partial** — `pass9_catalog.zig` |
| **B** | End-to-end Ward kernel (descriptor-generated decode + validate) | **open** — P9-M1 |
| **C** | Close Duo systems-programming gaps (bytes, cursors, LEB128, arenas, …) | **partial** |
| **D** | Semantic density metrics | **open** |
| **E** | Superior realization selection for dispatch | **partial** — Pass 8 `realization.zig` |
| **F** | LSP/MCP share Ward semantics | **open** |

---

## Capability ladder (Ward levels)

| Level | Title | Exit gate (summary) | Status |
| --- | --- | --- | --- |
| **L0** | Repository and benchmark truth | Wart/Ward/Duo maps; no stale perf claims | **partial** |
| **L1** | Duo-native systems substrate | Binary parser in accepted Duo → direct native hot loop | **open** |
| **L2** | Wasm semantic model | One descriptor source → decoder + validator + tooling | **open** |
| **L3** | Decoder and validator proof | Differential + fuzz; no generic table ops in hot loop | **open** |
| **L4** | Baseline interpreter | Conformance + explainable dispatch | **open** |
| **L5** | Specialization-aware interpreter | Guarded specialization with fallback | **open** |
| **L6** | Baseline native compiler/JIT | Duo-owned lowering, no foreign compiler intermediary | **open** |
| **L7** | Optimizing compiler | Repeatable gains over Wart in comparable modes | **open** |
| **L8** | Persistent adaptive Ward | Pass 8 evidence reuse on Ward artifacts | **open** |

---

## First implementation milestone — P9-M1

**Descriptor-generated, Duo-native LEB128 and instruction decoder for a bounded WebAssembly subset, with integrated validation metadata.**

Must demonstrate:

- One semantic instruction descriptor source (no duplicated opcode facts)
- Generated decoder tables + validator metadata via `@comp.*` staging
- Native hot path: direct byte loads, no universal boxing, no generic Lua call stack
- Positive + malformed fixtures; differential reference comparison
- `duo explain` / `duo catalog` / MCP readiness projection

**Bounded subset (initial):** MVP opcodes already listed in `~/x/ward/src/wasm/op.duo` (i32/i64/f32/f64 arith, memory, control, calls) — freeze before generator work.

---

## Repo-truth audit (2026-08-04)

### Ward current state (`~/x/ward`)

| File | Lines | Notes |
| --- | ---: | --- |
| `src/wasm/module.duo` | 328 | Section decoder; **hot reader uses `@c.emit` + `lua_Value`** |
| `src/wasm/runtime.duo` | 2410 | Interpreter; exceeds README "~263 lines" claim |
| `src/wasm/op.duo` | 156 | Handwritten opcode constants (duplicated facts) |
| `src/wasm/jit.duo` | 119 | JIT stub — C codegen path, not descriptor-generated |
| `src/wasm/aot.duo` | 10 | Stub |

**Blockers for Pass 9:** Ward binary reader violates "no universal boxing" (see `mr_mod_read_byte` in `module.duo`). Opcode table in `op.duo` duplicates facts that must become one descriptor source.

### Duo substrate (relevant to Ward)

| Capability | Owner | Readiness | Ward consumer |
| --- | --- | --- | --- |
| LEB128 encode/decode | `lib/std/bit.duo` | PARTIAL — dynamic `any` tables | P9-WS3, P9-M1 |
| Byte buffer | `lib/std/bytes.duo` | PARTIAL — growable buffer, not native slice type | P9-WS3 |
| `mem.load` / `mem.store` intrinsics | `src/sema.zig`, `src/codegen.zig` | PARTIAL — typed paths exist | P9-WS6 |
| Native aggregates | `codegen.zig` + `@{}` | STABLE_INTERNAL | Ward structs |
| Realization planner | `realization.zig` | PARTIAL | dispatch candidate selection (P9-WS5+) |
| Semantic graph + fingerprints | `semantic_graph.zig` | PARTIAL | instruction descriptor IDs |
| `@comp.*` codegen | `meta_codegen.zig` | STABLE_INTERNAL | descriptor → tables |
| Native backend (asm/object) | `src/native_backend/` | SPIKE | L6+ |

### Wart reference (`~/x/wart`)

- Exists at `~/x/wart`; README in Ward cites ~1.3M LOC — **not yet audited file-by-file in Pass 9** (Workstream 1).
- Treat Ward README performance claims as **unverified** until harness exists.

---

## Workstreams

| ID | Title | Status | Owner area |
| --- | --- | --- | --- |
| P9-WS1 | Wart and Ward truth audit | **partial** | cross-repo |
| P9-WS2 | Ward readiness registry | **partial** | `pass9_catalog.zig` |
| P9-WS3 | Native bytes and cursor substrate | open | `lib/std/bytes.duo`, `lib/std/bit.duo` |
| P9-WS4 | Wasm semantic descriptor | open | `lib/std/wasm/` or `ward` descriptor module |
| P9-WS5 | Compile-time generator (decoder/validator) | open | `@comp.*` + `meta_codegen.zig` |
| P9-WS6 | Native decoder lowering | open | `codegen.zig` |
| P9-WS7 | Differential and fuzz harness | open | `examples/pass9/`, `ward/test/` |
| P9-WS8 | Performance and complexity harness | open | `docs/performance.md` |
| P9-WS9 | Semantic tooling (LSP + end-user MCP) | open | duo-lsp, duo-mcp |
| P9-WS10 | Development MCP integration | open | duo-mcp coordination tools |
| P9-WS11 | Baseline interpreter design gate | open | blocked on P9-M1 |

---

## Agent execution order

1. repository truth audit (P9-WS1)
2. readiness registry (P9-WS2) ← **this session**
3. choose supported Wasm subset
4. native byte and cursor substrate (P9-WS3)
5. semantic instruction descriptor (P9-WS4)
6. compile-time generation (P9-WS5)
7. native decoder lowering (P9-WS6)
8. validator integration
9. differential/fuzz testing (P9-WS7)
10. LSP/MCP exposure (P9-WS9/10)
11. performance + semantic-density comparison (P9-WS8)

**Parallelism:** only when file and semantic ownership do not conflict.

---

## Rejection criteria

- Port Wart before Duo readiness
- Ward-only language features
- Duplicated instruction facts (handwritten `op.duo` + generated tables)
- Generated C as canonical Ward implementation path
- Hidden foreign runtime on hot paths
- Incomparable benchmarks
- Optimizing JIT before decoder/validator correct
- Separate Wasm semantic graph for Ward

---

## Validation

```bash
zig build
zig test src/pass9_catalog.zig
./zig-out/bin/duo catalog | jq '.pass9'
./zig-out/bin/duo catalog | jq '.pass9.milestones'
./zig-out/bin/duo catalog | jq '.pass9.ward_subsystems[] | select(.readiness != "WARD_READY")'
```

---

## Success criteria (Pass 9 complete)

1. Machine-readable Ward readiness matrix ✅ (bootstrap)
2. Ward depends only on canonical Duo capabilities
3. One complete Wasm subsystem in accepted Duo syntax
4. One semantic descriptor source
5. Generated artifacts retain provenance
6. Hot paths without universal boxing
7. Differential + fuzz correctness
8. LSP/MCP expose same semantic facts
9. Development MCP exposes coordination without semantic duplication
10. Reproducible performance + semantic-density comparisons
11. At least one general Duo fix driven by Ward
12. Next Ward subsystem reuses same foundations
