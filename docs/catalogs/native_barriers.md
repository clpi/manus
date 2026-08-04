# Native Compilation Barriers Catalog

> **Pass 4 canonical reference.** Every location where Duo still uses boxed/generic paths
> when native lowering is theoretically possible.
> Generated from codegen audit (2026-08-04).

## Barrier Classifications

| Class | Meaning |
| --- | --- |
| **REQUIRED** | Semantically necessary (dynamic boundary, unknown types) |
| **ANALYSIS** | Could be native if compiler had more knowledge |
| **DEBT** | Temporary implementation — replacement planned |
| **BACKEND** | Native backend doesn't support this yet |
| **ARCHITECTURE** | Requires structural change to eliminate |

---

## Active Barriers (by impact)

### 1. Mixed-mode benchmark path

| Field | Value |
| --- | --- |
| **Location** | `codegen.zig:can_emit_native_scalar_module` |
| **Barrier** | `bench_mode = true` forces boxed path |
| **Impact** | All 40 benchmarks route through lua_Value even for typed .duo |
| **Class** | DEBT |
| **Prerequisite** | Allow native-scalar for bench timing harness |
| **Status** | Open |

### 2. Closures as values always box

| Field | Value |
| --- | --- |
| **Location** | `codegen.zig` closure emission (~lines 8700-9000) |
| **Barrier** | Any function stored in a variable becomes `lua_Value` closure |
| **Impact** | Projection callbacks (`.name`), higher-order functions |
| **Class** | ARCHITECTURE |
| **Prerequisite** | Closure specialization in Call Algebra |
| **Status** | Open — field projections work but route through closure allocation |

### 3. Metatable method dispatch

| Field | Value |
| --- | --- |
| **Location** | `codegen.zig:emit_alias_metatable_*` |
| **Barrier** | Method calls on typed aliases use `lua_Value` dispatch |
| **Impact** | All `Point:length()` style calls |
| **Class** | ANALYSIS |
| **Prerequisite** | Stable metatable → direct call devirtualization |
| **Status** | Open |

### 4. String operations

| Field | Value |
| --- | --- |
| **Location** | `codegen.zig` string builtins |
| **Barrier** | `string.len`, `string.sub`, `..` concat use `lua_Value` paths |
| **Impact** | Any string manipulation in typed code |
| **Class** | DEBT |
| **Prerequisite** | Native string representation (pointer + length) |
| **Status** | Partial — some stdlib folds exist (contains, starts_with) |

### 5. Table construction in typed code

| Field | Value |
| --- | --- |
| **Location** | `codegen.zig:emit_table_construction` |
| **Barrier** | Even typed `{ x = 1, y = 2 }` may allocate `lua_table_new` in some contexts |
| **Impact** | Record construction, return values |
| **Class** | ANALYSIS |
| **Prerequisite** | Shape-based scalar replacement or stack allocation |
| **Status** | Partial — `native_scalar_mode` eliminates when whole module is typed |

### 6. Native backend: no struct/record support

| Field | Value |
| --- | --- |
| **Location** | `src/native_backend.zig` |
| **Barrier** | Cannot emit field-offset loads/stores |
| **Impact** | The Pass 4 milestone requires sealed record access |
| **Class** | BACKEND |
| **Prerequisite** | Add memory layout + load/store instructions |
| **Status** | Open — highest priority native backend work |

### 7. Native backend: arm64 only

| Field | Value |
| --- | --- |
| **Location** | `src/native_backend.zig` target gate |
| **Barrier** | Hard-gates on `macos + aarch64` |
| **Impact** | No native path on any other platform |
| **Class** | BACKEND |
| **Prerequisite** | x86_64 instruction encoding + ELF emission |
| **Status** | Open |

### 8. Native backend: no register spills

| Field | Value |
| --- | --- |
| **Location** | `src/native_backend.zig` register allocator |
| **Barrier** | Panics with `RegisterExhausted` at >20 live values |
| **Impact** | Complex functions can't use native backend |
| **Class** | BACKEND |
| **Prerequisite** | Stack-frame spill slots |
| **Status** | Open |

### 9. Per-expression knowledge not used for call dispatch

| Field | Value |
| --- | --- |
| **Location** | `codegen.zig:~10700` call emission |
| **Barrier** | `exprKnowledge()`/`symbolKnowledge()` defined but not consumed |
| **Impact** | Calls that COULD be direct still go through `lua_invoke` in mixed mode |
| **Class** | ANALYSIS |
| **Prerequisite** | Wire lattice queries into call-emission decision |
| **Status** | Open — Pass 2 spine exists, needs codegen wiring |

### 10. Return packs always materialize for >1 value

| Field | Value |
| --- | --- |
| **Location** | `codegen.zig` multi-return handling |
| **Barrier** | Multiple returns use `lua_Value` stack segment |
| **Impact** | `a, b = f()` forces boxing even when types are known |
| **Class** | ARCHITECTURE |
| **Prerequisite** | SSA return-pack dataflow |
| **Status** | Open |

---

## Resolved Barriers (historical)

| ID | Resolved | Description |
| --- | --- | --- |
| NB-001 | 2026-08-04 | `lua_free_mode` — typed .duo modules emit zero lua_Value |
| NB-002 | 2026-08-01 | `native-exe` target — simple typed fns compile to arm64 without C |
| NB-003 | 2026-08-01 | String literal emission in native backend (adrp/add + cstring) |
| NB-004 | 2026-08-01 | Intra-module direct calls (bl patching) |
| NB-005 | 2026-08-01 | External calls via @ffi (BR26 relocations) |
| NB-006 | 2026-07-30 | `req("std.string")` native predicates (strstr/strncmp) |
| NB-007 | 2026-07-30 | `req("std.math")` native math (direct libm) |

---

## Barrier Metrics

| Metric | Value |
| --- | --- |
| Total `lua_Value` in codegen | 1,135 references |
| Total `lua_invoke` sites | 66 |
| Total `lua_table_new` sites | 67 |
| Total `lua_to_*` unboxing | 373 |
| **Active barriers** | 10 |
| **Backend gaps** | 3 (struct, x86, spill) |
| **Analysis gaps** | 3 (metatable, construction, per-call) |
| **Architecture gaps** | 2 (closures, return packs) |
| **Debt** | 2 (bench mode, string ops) |
