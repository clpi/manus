# lua_Value Boxing Audit — Duo Compiler Codegen

Date: 2026-08-02
Auditor: Hermes Agent (subagent)
Scope: src/codegen.zig, src/sema.zig, src/comptime.zig, and all other src/*.zig files

## Summary

Total lua_Value occurrences across active source files (excluding codegen.zig.bak):
  codegen.zig:       1129
  jit.zig:             46
  types.zig:            7
  async_lower.zig:      5
  meta_codegen.zig:     6
  meta_module.zig:       3
  autodiff.zig:          3
  comptime.zig:          2
  sema.zig:              1  (comment only)
  pipeline_gen.zig:      1
  schema_gen.zig:        1
  TOTAL:             1204

lua_push* (pushnumber/pushinteger/pushstring/pushboolean/pushcfunction): 0
lua_to*   (tonumber/tointeger/tostring/toboolean):                       0
lua_table_new / lua_invoke / lua_getfield / lua_setfield / lua_rawget / lua_rawset: 135 (all in codegen.zig + 6 in jit.zig)

## Classification

### DYNAMIC/Lua-compat paths (ACCEPTABLE) — ~1050+ occurrences

The vast majority of lua_Value usage is in the dynamic/Lua-compat code path,
which is active when `native_scalar_mode == false`. This includes:

1. **Lua runtime prelude emission** (emit_module, lines 3008-3579):
   - `lua_package_init()`, `lua_math_init()`, `lua_table_new()`, etc.
   - Gated by `if (!self.native_scalar_mode)` at line 3559.
   - STATUS: Correctly gated.

2. **Lua thunk declarations and definitions** (emit_lua_thunk_decls line 5253,
   emit_lua_thunk line 5568):
   - Bridge functions that unbox lua_Value args into native C params.
   - `emit_lua_thunk_decls`: early-returns when `native_scalar_mode` (line 5254).
   - `emit_lua_thunk`: early-returns when `native_scalar_mode` (line 5569).
   - STATUS: Correctly gated.

3. **Closure runtime** (emit_closure_structs, emit_closure_runtime):
   - `emit_closure_structs` gated by `!native_scalar_mode` at call site (line 3417).
   - `emit_closure_runtime` gated by `!native_scalar_mode` at call site (line 3515).
   - STATUS: Correctly gated.

4. **Required modules / module return table** (emit_required_modules, emit_duo_module_return_table):
   - `emit_required_modules` gated by `!native_scalar_mode` at call site (line 3422).
   - STATUS: Correctly gated.

5. **duo_load_entry** (load_chunk path, line 3549):
   - `can_emit_native_scalar_module` returns false when `load_chunk` is true (line 2086).
   - STATUS: Correctly gated (indirectly).

6. **Dynamic expression emission** (emit_expr, emit_stmt):
   - lua_Value used for `.any` typed expressions, dynamic table operations,
     dynamic string operations, etc.
   - These are the Lua-compat code paths for untyped/dynamic code.
   - STATUS: Acceptable — these only execute when types are `.any` (dynamic).

7. **@comp.* metaprogramming hooks** (code lines 11900-12130):
   - All @comp.* hooks (expand, ceiling, omni, burst, tensor, nfold, transcend,
     infinity, hyper, tower, scheme, template, generate, fixpoint, fanout)
   - These emit C code string literals via `emit_c_string_literal()`.
   - They do NOT emit lua_Value runtime values.
   - STATUS: Clean — no lua_Value intermediaries.

8. **comptime.zig** (2 occurrences, lines 315-316):
   - `__type_id` intrinsic maps compile-time values to C type strings.
   - `.table => "lua_Value"` and `.func => "lua_Value"` — these are type-name
     strings for comptime evaluation, not runtime lua_Value boxing.
   - STATUS: Acceptable — comptime type naming for dynamic types.

9. **jit.zig** (46 occurrences):
   - JIT closure source tables, upvalue pack tables, JIT runtime.
   - All gated by `!native_scalar_mode` at call sites in emit_module (lines 3419-3421).
   - STATUS: Correctly gated.

10. **types.zig, async_lower.zig, meta_codegen.zig, etc.**:
    - Type system definitions (ResolvedType c_type method), async frame type mapping.
    - These reference lua_Value as a C type name for `.any`/dynamic types.
    - STATUS: Acceptable — type system needs to name lua_Value for dynamic types.

### TYPED/comptime path VIOLATIONS — 3 issues found

#### VIOLATION 1: emit_alias_metatable_init — NO native_scalar_mode guard
  File: src/codegen.zig
  Function: emit_alias_metatable_init (line 4065)
  Called from: emit_module line 3592 — UNCONDITIONALLY (no native_scalar_mode check)
  lua_Value occurrences: 21 (lines 4074-4160)
  Also emits: lua_table_new(), lua_table_set_raw_lit(), lua_val_from_func()

  Impact: If a module enters native_scalar_mode (all functions have native-scalar
  params) but also has an alias type with @derive or methods, this function emits
  lua_Value code (lua_table_new, lua_val_from_func, static lua_Value vars) into a
  C file that has NO lua runtime prelude. This would cause:
  - Compilation errors (undefined lua_Value, lua_table_new, lua_val_from_func)
  - OR silent lua_Value boxing on typed record paths

  The alias_def statement kind is explicitly ALLOWED in can_emit_native_scalar_module
  (line 2167: `.enum_def, .alias_def => {}`), so native_scalar_mode CAN be true
  while the module has alias types with @derive.

  SEVERITY: HIGH — latent compilation failure or silent violation

#### VIOLATION 2: emit_alias_metatable_decls — NO native_scalar_mode guard
  File: src/codegen.zig
  Function: emit_alias_metatable_decls (line 4171)
  Called from: emit_module line 3338 — UNCONDITIONALLY
  lua_Value occurrences: 1 (line 4179: `static lua_Value duo_mt_{s};`)

  Impact: Same as VIOLATION 1 — emits `static lua_Value` declaration without
  the lua_Value type being defined in native_scalar_mode.

  SEVERITY: HIGH — latent compilation failure

#### VIOLATION 3: emit_alias_derive_functions — NO native_scalar_mode guard
  File: src/codegen.zig
  Function: emit_alias_derive_functions (line 4184)
  Called from: emit_module line 3341 — UNCONDITIONALLY
  lua_Value occurrences: ~25 across emit_derive_display, emit_derive_eq,
  emit_derive_ord, emit_derive_binop, emit_derive_neg, emit_derive_bitnot,
  emit_derive_len, emit_derive_default, emit_derive_hash, emit_derive_clone

  Impact: Emits full `__lua` wrapper functions (e.g. `duo_Name_tostring__lua`)
  that take/return lua_Value, call lua_table_get_str_lit, lua_table_new_with_capacity,
  etc. — all lua runtime functions — without checking native_scalar_mode.

  SEVERITY: HIGH — latent compilation failure or silent violation

## Native Lowering Infrastructure Status

### native_scalar_mode (codegen.zig)
  STATUS: EXISTS and FUNCTIONAL as a module-level gate.

  Location: src/codegen.zig line 82 (`native_scalar_mode: bool = false`)
  Set at: line 2969 (`self.native_scalar_mode = self.can_emit_native_scalar_module(mod)`)

  How it works:
  - `can_emit_native_scalar_module` (line 2084) scans ALL module statements.
  - Returns true only if EVERY function has native-scalar params/ret/body,
    no varargs, no async, no generics, no test/bench/debug directives.
  - When true: skips lua runtime prelude, skips closure runtime, skips JIT tables,
    skips lua thunks, uses native string helpers (duo_str_concat, duo_str_rep).
  - `type_expr_is_native_scalar` (line 2436) allows: numeric, bool, str, void,
    array, struct, enum_type, table_type, pointer, any, func.

  Gaps:
  - Lives entirely in codegen.zig — NOT in sema.zig.
  - sema.zig has NO awareness of native lowering decisions.
  - Module-level only (all-or-nothing). Partial via `mixed_scalar_mode`.

### mixed_scalar_mode (codegen.zig)
  STATUS: EXISTS and FUNCTIONAL as per-function native emission.

  Location: src/codegen.zig line 86 (`mixed_scalar_mode: bool = false`)
  Set at: line 2972 when `compute_native_scalar_funcs` finds native-eligible funcs
  in a module that can't go fully native.

  How it works:
  - `compute_native_scalar_funcs` (line 2178) populates `native_scalar_funcs` set
    with names of functions that can be emitted as native C.
  - In mixed mode, the lua runtime is still present, but native-eligible functions
    get native C signatures (no lua_Value params).
  - Lua thunks are still emitted for lua-convertible functions (bridge for dynamic callers).

### func_is_compile_only — MISSING ENTIRELY
  STATUS: DOES NOT EXIST anywhere in the compiler source.

  Referenced in: .agents/AGENT_COORDINATION.md line 41:
    "Comptime-only callbacks use `@meta.compile.only` (enforced in `func_is_compile_only`)."

  Reality:
  - `@comp.compile.only` / `@meta.compile.only` is REGISTERED as a directive alias
    in meta_module.zig (lines 696-698, 827).
  - The canonical name "compile.only" is recognized by the directive resolver.
  - BUT: NO function named `func_is_compile_only` exists in ANY source file.
  - NO code in codegen.zig, sema.zig, comptime.zig, directives.zig, parser.zig,
    meta_codegen.zig, or macro_expand.zig checks for the "compile.only" directive
    on functions.
  - The directive is registered but NOT ENFORCED.

  Impact: Comptime-only callbacks marked with `@comp.compile.only` do NOT get
  special treatment. They may still emit runtime lua thunks (`__lua` wrappers)
  if their params are lua-convertible, violating the rule that comptime-only
  callbacks should not emit runtime lua thunks.

  SEVERITY: MEDIUM — the directive exists in the surface syntax but has no
  enforcement in the compiler backend.

## @native functions
  The `@native` directive (canonical name "native", meta_module.zig line 671)
  maps to `is_native` on ResolvedType.func (types.zig line 51):
  `is_native: bool` — true when fully typed, false when has dynamic params.

  This is a TYPE-SYSTEM property, not a codegen gate. Functions with `is_native=true`
  get native C signatures in codegen. The lua thunk is still emitted alongside
  (in mixed mode) as a bridge for dynamic callers.

  STATUS: Working as designed — @native controls type-level nativeness,
  native_scalar_mode controls module-level lua runtime elimination.

## Recommendations

1. **Fix VIOLATIONS 1-3**: Add `if (self.native_scalar_mode) return;` guards to:
   - `emit_alias_metatable_init` (line 4065)
   - `emit_alias_metatable_decls` (line 4171)
   - `emit_alias_derive_functions` (line 4184)
   OR: gate the call sites at lines 3338, 3341, 3592 with `if (!self.native_scalar_mode)`.

2. **Implement func_is_compile_only**: Create the function in codegen.zig or sema.zig
   that checks for the "compile.only" directive on function attributes. Use it to
   suppress lua thunk emission for comptime-only callbacks. The directive alias
   infrastructure already exists in meta_module.zig.

3. **Consider moving native_scalar_mode to sema.zig**: The native lowering decision
   is currently made entirely in codegen.zig. Moving it to sema.zig would allow
   type checking to be aware of native lowering, enabling better type inference
   and earlier error detection.

## Files examined
  - src/codegen.zig (26107 lines) — primary codegen, all lua_Value patterns
  - src/sema.zig (8816 lines) — semantic analysis, 1 lua_Value comment
  - src/comptime.zig (1550 lines) — comptime evaluation, 2 lua_Value type strings
  - src/types.zig — ResolvedType, is_native(), c_type() method
  - src/jit.zig — JIT runtime, gated by native_scalar_mode
  - src/async_lower.zig — async frame type mapping
  - src/meta_codegen.zig — @comp.* hook implementations
  - src/meta_module.zig — directive registration (compile.only, native)
  - src/directives.zig — attribute checking helpers
  - src/autodiff.zig — autodiff transform
  - src/pipeline_gen.zig — pipeline generation
  - src/schema_gen.zig — schema generation
  - .agents/AGENT_COORDINATION.md — references func_is_compile_only
  - AGENTS.md — project rules and conventions