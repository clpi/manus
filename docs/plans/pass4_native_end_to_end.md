# Pass 4 — Native End-to-End Compilation, Runtime Independence, and Self-Hosting

> **Date:** 2026-08-04  
> **Follows:** Pass 1 (Lua + compiler knowledge), Pass 2 (convergence algebras), Pass 3 (directive surface + semantic graph spine)  
> **Mission:** Duo owns the full path from source to machine code. Preserve observable Lua semantics; replace boxed Lua VM architecture wherever specialization permits.

---

## A. Executive findings (repository state)

1. **C bootstrap backend is mature but must not become permanent semantic IR.** `src/codegen.zig` (~27k lines) lowers typed paths to native C scalars/structs when `native_scalar_mode` applies; ~1360 references to `lua_Value` / `lua_invoke` / boxing helpers remain (mostly dynamic fallback and stdlib).
2. **Direct native backend exists for bounded programs.** `src/native_backend.zig` emits arm64 Mach-O objects on macOS without generated C — integer arithmetic, branches, loops, direct calls, string literals. Not yet wired for sealed record types like `Point: @{ x: f64, y: f64 }`.
3. **First milestone C path is already native for sealed records.** `Point` + `distance2` lowers to a C struct + direct field access + native `double` return with no `lua_invoke` in the function body (see `examples/pass4_native_milestone.duo`).
4. **Semantic graph spine is in place (Pass 2–3)** but representation selection is implicit in codegen, not a visible IR phase.
5. **Self-hosting stage 0:** compiler implemented in Zig; clang required at link time; no Duo-hosted compiler components yet.
6. **Runtime is embedded in generated C preamble** when `moduleNeedsLuaRuntime`; pay-for-use linking is partial (`native_scalar_mode` skips much of it).
7. **Barrier catalog started** (`docs/catalogs/performance_barriers.md` PB-001–010); Pass 4 extends with representation, pipeline, and backend rows.
8. **Explanation surface (`@comp.why.*`) is planned, not implemented** for boxing/allocation/ABI queries.

---

## B. Governing invariants (non-negotiable)

| ID | Invariant |
| --- | --- |
| P4-01 | No universal boxed root representation on typed/comptime paths |
| P4-02 | No mandatory Lua value stack for specialized calls |
| P4-03 | No mandatory generic hash table for known shapes |
| P4-04 | No mandatory heap closure when captures are constant/non-escaping |
| P4-05 | Multiple returns stay compiler dataflow until dynamic boundary |
| P4-06 | Generated Lua is never native compilation dependency |
| P4-07 | Generated C is bootstrap/portability backend, not semantic IR |
| P4-08 | Third-party IR/types must not define Duo semantics |
| P4-09 | Dynamic boundaries must be explicit (box, guard, runtime call) |

Full spec: agent Pass 4 prompt (§4–§9).

---

## C. Compilation pipeline (target vs current)

| Layer | Target | Current implementation |
| --- | --- | --- |
| Source | tokens + spans | `lexer.zig`, `parser.zig` |
| Syntax graph | AST | `ast.zig` |
| Semantic graph | durable IDs, transforms | `semantic_graph.zig` 🔄 |
| High-level semantic IR | Lua-shaped, not VM-shaped | implicit in `sema.zig` + graph lift ⬜ |
| Specialized IR | guards, assumptions | partial in `codegen.zig` knowledge lattice 🔄 |
| Representation IR | explicit box/unbox | implicit in codegen ⬜ |
| Low-level IR | target-neutral ops | ⬜ (C/asm string emission today) |
| Machine IR | vregs, relocations | `native_backend.zig` 🔄 (arm64 Mach-O) |
| Object emission | Duo-owned | `native_backend.zig` macOS arm64 only |
| Runtime | modular, pay-for-use | monolithic C preamble 🔄 |

---

## D. First milestone (P4-M1)

**Goal:** A typed, sealed, non-escaping Duo function compiles without universal boxing, generic Lua table, Lua value stack, generic call dispatcher, runtime closure, return tuple, or generated-C as the *semantic* dependency.

**Demonstration:** `examples/pass4_native_milestone.duo`

```duo
Point: @{ x: f64, y: f64 }

distance2(p: Point): f64
    p.x * p.x + p.y * p.y
end

main(): f64
    distance2({ x = 3.0, y = 4.0 })
end
```

| Criterion | C backend (`dump-c`) | Direct backend (`native-asm` / `native-object`) |
| --- | --- | --- |
| Native struct for Point | ✅ `duo_rec_*` with `double x, y` | ✅ f64 params in d0–d1 (decomposed record) |
| Direct field access | ✅ `p.x`, `p.y` | ✅ FP locals `p.x`, `p.y` |
| No `lua_invoke` in `distance2` | ✅ | ✅ no runtime symbols |
| Native scalar return | ✅ `double` | ✅ `f64` in d0 |
| Object code without clang semantic role | ⬜ (C is bootstrap) | ✅ Mach-O via `native_backend.zig` |

Verified machine ops for `distance2` on arm64:

```
fmul d2, d0, d0    ; p.x * p.x
fmul d3, d1, d1    ; p.y * p.y
fadd d4, d2, d3
```

**Tests:** `src/pass4_native_tests.zig`, `src/dynamic_boundary.zig`, `src/pass4_boxed_inventory.zig`

**Explanation surface (P4-03/P4-10 partial):**
- `@comp.representation(expr)` — selected representation facts
- `@comp.why.boxed(expr)` — why a value is or is not boxed
- `@comp.why.not.native(expr)` — remaining native-path barriers
- Demo: `examples/pass4_boundary_demo.duo`

---

## E. Ranked workstreams

| ID | Workstream | Status | Priority |
| --- | --- | --- | --- |
| P4-01 | Native-path audit + barrier catalog | partial | 1 |
| P4-02 | Semantic value model foundation | ⬜ | 2 |
| P4-03 | Explicit box/unbox IR boundaries | ⬜ | 3 |
| P4-04 | Native table + field-offset lowering | partial | 4 |
| P4-05 | Native call ABI foundation | partial | 5 |
| P4-06 | Return-pack native dataflow | ⬜ | 6 |
| P4-07 | Backend-independent low-level IR | ⬜ | 7 |
| P4-08 | Direct scalar backend (extend `native_backend.zig`) | partial | 8 |
| P4-09 | Modular runtime + pay-for-use linking | partial | 9 |
| P4-10 | Compiler explanation (`@comp.why.*`) | ⬜ | 10 |
| P4-11 | Dependency + bootstrap catalog | partial | 11 |
| P4-12 | Compiler-capable Duo profile | ⬜ | 12 |
| P4-13 | Bootstrappable core library | ⬜ | 13 |
| P4-14 | First compiler component in Duo | ⬜ | 14 |
| P4-15 | Multi-generation bootstrap harness | ⬜ | 15 |

Machine-readable: `src/pass4_catalog.zig`, `duo catalog`.

---

## F. Self-hosting stages (tracking)

| Stage | Description | Status |
| --- | --- | --- |
| 0 | Zig bootstrap compiler builds Duo | ✅ |
| 1 | Compiler-capable Duo subset | ⬜ |
| 2 | Core libs in Duo (bytes, spans, diagnostics) | ⬜ |
| 3 | Front end in Duo | ⬜ |
| 4 | Semantic core in Duo | ⬜ |
| 5 | Specialization + representation in Duo | ⬜ |
| 6 | Low-level IR + backend in Duo | ⬜ |
| 7 | Runtime in Duo | ⬜ |
| 8 | Bootstrap closure (A→B→C) | ⬜ |
| 9 | Reproducible self-hosting | ⬜ |
| 10 | Minimal trusted seed | ⬜ |

Catalog: `docs/catalogs/bootstrap_dependencies.md`

---

## G. Agent workflow

1. Read this plan + `docs/catalogs/performance_barriers.md` + `docs/catalogs/bootstrap_dependencies.md`
2. Claim one workstream in `.agents/AGENT_COORDINATION.md` (tag `pass4-*`)
3. Implement smallest durable seam; add tests + barrier row update
4. Do **not** claim "native" without disassembly / IR inspection
5. Release claim when done or blocked

---

## H. Validation gates

- `zig build` / `zig build unit-test`
- `zig build test` (full gate)
- `zig build bench` (no regressions on codegen changes)
- `zig test src/pass4_native_tests.zig` (Pass 4 milestone)
- `native_backend.zig` tests on macOS arm64
