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
| **Barrier** | ~~`bench_mode = true` forces boxed path~~ |
| **Impact** | ~~All 40 benchmarks route through lua_Value even for typed .duo~~ |
| **Class** | ~~DEBT~~ RESOLVED (Pass 11 WP-01) |
| **Prerequisite** | Explicit `--bench-backend` profiles: `c-dynamic`, `c-specialized` (default), `direct` |
| **Status** | ✅ Fixed — only `c-dynamic` forces boxing; default is `c-specialized` |

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
| **Status** | Partial — stack f64 records + field load + mixed int/f64 calls (Pass 11 WP-04) |

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
| **Barrier** | Correctly refuses when more values are simultaneously live in lowering than the GP register set can hold |
| **Impact** | Complex functions can't use native backend |
| **Class** | BACKEND |
| **Prerequisite** | Value-keyed register or fixed-frame locations, CFG-aware liveness, and materialization into an available register |
| **Status** | Open — GAP-148. The former Pass 11 WP-03 proof required storage for unread bindings; native lowering now omits those places and retains a genuine live-pressure refusal control |

### 9. Per-expression knowledge now gates call dispatch

| Field | Value |
| --- | --- |
| **Location** | `codegen.zig:~11372` call emission |
| **Barrier** | ~~`exprKnowledge()` defined but not consumed~~ |
| **Impact** | Typed callee signatures now enable direct calls in mixed mode |
| **Class** | ~~ANALYSIS~~ RESOLVED |
| **Status** | ✅ Fixed — `funcTypeIsFullyNative()` added (2026-08-04) |

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
| NB-008 | 2026-08-04 | Byte blob module constants + `__native_load_u8` intrinsic (Pass 11 WP-05 partial) |
| NB-009 | 2026-08-05 | Module dense literal tables → native C arrays + scoped collect (Pass 12 M1 `classify_sorted_lookup`) |

---

## Executable barrier profiles (Pass 11 WP-15)

| Profile | CLI | Expect native | Status |
| --- | --- | --- | --- |
| M1 classifier | `duo dev barrier check pass12_m1` | yes | ✅ green |
| M1 sorted lookup | `duo dev barrier check pass12_m1_sorted` | yes | ✅ green (`strcmp` + `duo_g_*[i]` index) |
| Ward decode (`decode_instruction`) | `duo dev barrier check ward_decode` | no (documents gap) | open — dynamic table return still uses `lua_Value` |
| Ward decode dispatch | `duo dev barrier check ward_decode_dispatch` | yes (`no_dynamic_dispatch`) | **closed** — req-module devirt, zero `lua_invoke` in hot path |
| Ward opcode lookup | `duo dev barrier check ward_opcode_lookup` | yes | ✅ green (dense `OPCODE_TO_INDEX` + native accessors) |

Proof harness: `examples/pass12_m1_diff.duo` (differential validation for all classifier paths).

---

## Barrier Metrics

| Metric | Value |
| --- | --- |
| Total `lua_Value` in codegen | 1,135 references |
| Total `lua_invoke` sites | 66 |
| Total `lua_table_new` sites | 67 |
| Total `lua_to_*` unboxing | 373 |
| **Active barriers** | 9 |
| **Backend gaps** | 3 (struct, x86, spill) |
| **Analysis gaps** | 3 (metatable, construction, per-call) |
| **Architecture gaps** | 2 (closures, return packs) |
| **Debt** | 1 (string ops) |
| **Executable checks** | `src/native_barrier_checks.zig` (Pass 11 §3.4) |
