# Performance Barrier Catalog

> **Pass 3 tracking.** Locations where Duo still pays boxing/allocation/dispatch costs.  
> **Ledger:** [`docs/performance.md`](../performance.md) (benchmark evidence)

| ID | Barrier | Location | Target transform | Status |
| --- | --- | --- | --- | --- |
| PB-001 | `lua_invoke` on typed callees | `codegen.zig` mixed mode | `call.inline` dispatch | 🔄 partial |
| PB-002 | `lua_to_*` on stdlib paths | `codegen.zig` os/math modules | Native unbox | ⬜ audit |
| PB-003 | `lua_Value` on comptime meta hooks | legacy fold paths | `fold_meta_string_expr` | 🔄 mostly fixed |
| PB-004 | Dynamic field access on sealed tables | codegen table_get | Shape guard + direct field | ⬜ |
| PB-005 | Closure heap env when capture is const | closure emit | Closure specialization | ⬜ |
| PB-006 | Return-pack materialization | dynamic multi-return | Return-pack SSA | ⬜ |
| PB-007 | Pipeline `\|>` → lua_invoke fallback | `try_emit_native_pipeline` | `pipeline.fuse` | 🔄 partial |
| PB-008 | Failed SIMD on Mandelbrot | benchmark row | 4-wide without RESULT drift | ⬜ open |
| PB-009 | Alias metatable on native paths | codegen guards | `native_scalar_mode` lattice | 🔄 guarded |
| PB-010 | Exponential combinator string boxing | tier-1 hooks | bare `const char*` literals | ✅ fixed |
| PB-011 | Universal `lua_Value` center in codegen | `codegen.zig` (~1870 refs) | Explicit dynamic boundaries + native path audit | 🔄 Pass 4 |
| PB-012 | Generated C as primary semantic lowering | `codegen.zig` → clang | Direct backend + Duo LLIR | 🔄 bootstrap |
| PB-013 | Sealed record not in direct backend | `native_backend.zig` | Extend arm64 lowering for structs/f64 | 🔄 partial (f64 sealed records) |
| PB-014 | Runtime preamble linked when unused | `moduleNeedsLuaRuntime` | Pay-for-use runtime profiles | 🔄 partial |
| PB-015 | `@comp.why.*` explanation queries | `dynamic_boundary.zig`, `@comp.why.boxed` / `@comp.representation` | Compiler explanation surface | 🔄 partial |

**Pass 4 plan:** [`docs/plans/pass4_native_end_to_end.md`](../plans/pass4_native_end_to_end.md)  
**Bootstrap catalog:** [`docs/catalogs/bootstrap_dependencies.md`](bootstrap_dependencies.md)  
**First milestone:** `examples/pass4_native_milestone.duo` — C path ✅, direct native-exe/asm ✅ (sealed f64 record + f64 main → int exit wrapper)
