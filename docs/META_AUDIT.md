# Duo Metaprogramming Framework Audit — 2026-07-29

> **Scope:** Identify the 5 highest-leverage improvements to the metaprogramming
> framework. Focus: implemented-but-broken, planned-but-missing, lua_Value
> leakage, linear ceiling removal, and new @meta.* constructs for exponential
> output from minimal input.

---

## Summary of What I Did

I read and analyzed the following files in depth:
- `src/meta_module.zig` (1119 lines) — public builtin table, directive table, catalog, tests
- `src/meta_codegen.zig` (2094 lines) — all combinator implementations (map, derive, expand, ceiling, omni, burst, product, tensor, transcend, nfold, power, permute, each, tower)
- `src/meta_directives.zig` (346 lines) — module directive registration (foreign, pipeline, rewrite, define_derive, embed_json, sql, lua, wasm, ffi)
- `src/comptime.zig` — comptime evaluator, Value type, comptime_cache, comptime_map_hook
- `src/codegen.zig` (26187 lines) — call-site dispatch, emit_expr .call path, emit_native_func_def, emit_embed_json_module_directive, native_scalar_mode
- `docs/AGENT_GAPS.md` — open/closed findings ledger
- `docs/performance.md` — benchmark status and gap analysis
- `src/parser.zig` — @-expression parsing, builtin resolution
- `src/directives.zig` — directive helpers

I also ran `zig build test` and discovered a **build-breaking duplicate test name**.

---

## The 5 Highest-Leverage Improvements

### IMPROVEMENT 1: Fix build-breaking duplicate test name (BLOCKER — `zig build test` fails)

**File:** `src/meta_module.zig`, lines 1013 and 1038

**Problem:** Two tests share the name `"meta_module: directive normalization"`:
- Line 1013: newer test checking `normalizeDirective("meta.define.derive")` returns `"define.derive"` (dotted, not `define_derive`)
- Line 1038: older test checking `normalizeDirective("meta.define.derive")` returns `"define.derive"` plus a wide range of other assertions

Zig rejects duplicate test names as a compilation error. `zig build test` currently fails with:
```
src/meta_module.zig:1013:6: error: duplicate test name 'meta_module: directive normalization'
```

**Fix:** Merge the two tests into one at line 1013, or rename the first test to `"meta_module: directive normalization (prefix-stripping)"`. The first test (lines 1013-1021) tests the newer prefix-stripping behavior; the second (lines 1038-1062) is the comprehensive one. The simplest fix: rename the test at line 1013.

**Impact:** Unblocks all CI. This is a P0 blocker.

---

### IMPROVEMENT 2: Per-function native ABI at call sites (G-025 — eliminates lua_Value boxing of @native functions)

**Files:**
- `src/codegen.zig` line 6558 (`emit_func_def`: `if (fb.native_abi)`)
- `src/codegen.zig` line 6750 (`emit_native_func_def`: emits native C function)
- `src/codegen.zig` lines 11047-11137 (call-site dispatch in `emit_expr` `.call` path)

**Problem:** The `@native` attribute was added (G-025 open). `emit_native_func_def` (line 6750) correctly emits a pure C function with typed params and return — no lua_Value. BUT the call-site dispatch (lines 11082-11137) checks `if (ft == .any)` and then checks `if (self.native_scalar_mode)`. When `native_scalar_mode` is false at the module level (mixed module with both typed and untyped code), calling an `@native` function whose type was not resolved by sema (ft == .any) falls through to `lua_invoke` (line 11132), boxing all arguments through `emit_as_lua_value` and routing through the `lua_Value` dispatch table.

The typed-call path (lines 11186-11223) handles `ft == .func` correctly — it emits a direct C call. But the `ft == .any` fallback at line 11082 never checks `fb.native_abi`.

**Fix:** In the `ft == .any` branch (line 11082), before falling through to `lua_invoke`, check if the callee is a known `@native` function:

```zig
if (ft == .any) {
    if (c.func.* == .name) {
        var name_buf: [256]u8 = undefined;
        if (self.func_bodies.get(self.mangled_name(c.func.name.ident, &name_buf))) |body| {
            if (body.native_abi) {
                // Direct C call with typed args — no lua_Value boxing
                self.p("{s}(", .{self.emit_func_c_name(body.params...)});  // or via emit_func_c_name
                for (c.args, 0..) |arg, i| {
                    if (i > 0) self.p(", ", .{});
                    const pt = self.resolve_type(body.params[i].typ);
                    try self.emit_arg_for_param(arg, pt);
                }
                self.p(")", .{});
                return;
            }
        }
    }
    // ... existing fallback to lua_invoke
}
```

**Impact:** Eliminates the last lua_Value boxing path for `@native` functions in mixed-mode modules. This is the P0 native gap (G-025) and directly improves performance on any module using `@native` functions alongside dynamic code.

---

### IMPROVEMENT 3: `@comp.embed.json` schema-aware typed C struct emission (G-002)

**Files:**
- `src/codegen.zig` lines 906-928 (`emit_embed_json_module_directive`)
- `src/meta_directives.zig` lines 90-97 (`registerEmbedJson`)
- `src/schema_gen.zig` line 105 (`jsonSchemaToC`)

**Problem:** `@comp.embed.json` has two code paths:
1. `meta_directives.zig:90` — calls `schema_gen.jsonSchemaToC()` which generates typed C structs from the JSON schema. This is correct.
2. `codegen.zig:906` — `emit_embed_json_module_directive` emits the JSON as raw `uint8_t[]` bytes only (`static const uint8_t <sym>_json[] = {...}`), ignoring the schema. The typed struct path from `schema_gen.zig` is not invoked at codegen time.

So `@comp.embed.json` at the codegen level produces untyped byte arrays, not typed C structs. The `registerEmbedJson` in `meta_directives.zig` does generate structs, but those go through `registerDeclsFromC` (C header parsing for function decls) — which only extracts function signatures, not struct definitions. The struct definitions from `jsonSchemaToC` are lost.

**Fix:** In `emit_embed_json_module_directive` (codegen.zig:906), after emitting the raw bytes, also call `schema_gen.jsonSchemaToC()` and emit the generated typed C struct definitions inline:

```zig
fn emit_embed_json_module_directive(self: *CodeGen, attr: ast.Attribute, loc: ast.Loc) void {
    // ... existing path resolution ...
    const bytes = Io.Dir.readFileAlloc(...) catch ...;
    
    // Emit raw bytes (existing)
    self.p("static const uint8_t {s}_json[] = {{", .{symbol});
    // ... byte emission ...
    
    // NEW: also emit typed C struct if schema can be parsed
    const schema_gen = @import("schema_gen.zig");
    if (schema_gen.jsonSchemaToC(self.alloc, bytes)) |c_structs| {
        defer self.alloc.free(c_structs);
        self.p("\n", .{});
        self.p("{s}", .{c_structs});
    } else |_| {}
}
```

**Impact:** Closes G-002. Users get typed C structs from `@comp.embed.json` instead of raw byte arrays. Enables compile-time JSON schema → typed struct → native code access without lua_Value.

---

### IMPROVEMENT 4: `@meta.grammar` — grammar-driven exponential code generation (NEW construct)

**Problem:** The framework has combinators that enumerate types (map, product, tensor, nfold, power, permute) and composition glue (each). But all of them enumerate over *types matching concepts*. There is no construct that generates code from a *grammar* or *production rule system*, which is the key to exponential output from minimal specification.

**Proposal:** Add `@meta.grammar(grammar_spec, fn)` — a construct that:
1. Takes a grammar specification (either a table of production rules or a string in EBNF-like syntax)
2. Enumerates all strings/ASTs derivable from the grammar (with a depth/size cap)
3. Invokes the callback once per derivation, concatenating results

This is the true "exponential from minimal input" primitive: a 5-line grammar can generate 2^n or n! derivations. It subsumes power/permute (which are special cases of grammar enumeration over type sets) and extends to arbitrary code patterns.

**Example:**
```duo
@meta.grammar({
    expr = "term + expr | term",
    term = "factor * term | factor",
    factor = "number | (expr)",
}, fn(derivation) -> str
    "/* generated: " .. derivation.string .. " */\n"
end)
```

**Implementation sketch:**
- New file `src/meta_grammar.zig` — CFG parser, enumeration via recursive descent with memoization and depth cap
- New entry in `meta_module.zig` builtins: `.{ .public = "meta.grammar", .internal = "__metagrammar" }`
- Hook in `meta_codegen.zig`: `comptimeGrammarHook` — enumerates derivations, calls callback per derivation
- Cap: `MAX_GRAMMAR_DERIVATIONS = 1 << 20` (same sanity scale as powerset)

**Impact:** Enables exponential code generation from a grammar specification. A single `@meta.grammar` declaration with k production rules can generate O(b^d) code fragments where b is branching factor and d is depth. This is the missing "generative" combinator — all existing combinators are enumerative (over existing types), not generative.

---

### IMPROVEMENT 5: `@meta.weave` — cross-module type-driven code injection (NEW construct)

**Problem:** The existing combinators (map, derive, product, tensor, nfold, power, permute) all operate within a single module's type set. `@meta.each` provides composition glue but only for string-level splitting. There is no construct that:
1. Takes a type from module A
2. Takes a derive/generator from module B
3. Injects the generated code into module C

This means cross-module metaprogramming requires manual coordination — each module must independently declare its own `@meta.*` sweeps. The "linear ceiling on agent code production" comes from the fact that each module is a separate metaprogramming context.

**Proposal:** Add `@meta.weave(source_module, concept, derive_or_fn, target_module)` — a construct that:
1. Reads types matching `concept` from `source_module` (resolved at compile time via the module system)
2. Applies `derive_or_fn` to each matching type (or each product/tensor combination)
3. Injects the generated C code into `target_module`'s output

This is the cross-module generalization of `@meta.derive` + `@meta.map`. It removes the single-module ceiling: a type defined in one module can trigger code generation in any other module that declares a `@meta.weave` for it.

**Implementation sketch:**
- Requires the module system (`src/codegen.zig` embedded module support, lines ~16090) to expose `record_aliases` and `concepts` across module boundaries
- New entry in `meta_module.zig`: `.{ .public = "meta.weave", .internal = "__metaweave" }`
- Hook in `meta_codegen.zig`: `weaveHook` — takes a module path, resolves it via the embedded module registry, runs the combinator, and emits into the current module's output
- The `Host` struct (meta_codegen.zig:23) already accepts `mod`, `record_aliases`, `concepts` — extend it to accept a *foreign* module's data

**Impact:** Removes the linear ceiling. With `@meta.weave`, one agent can define types in module A, and N other modules can each declare `@meta.weave` that generates type-driven code from A. The output is multiplicative: 1 type definition × N weave declarations × M derives = O(N×M) generated code fragments from 1+N lines of source. Combined with `@meta.grammar`, this gives O(b^d × N × M) — true exponential output.

---

## lua_Value Routing Audit

### Where the framework still routes through lua_Value when it shouldn't:

1. **`@native` function call sites in mixed-mode modules** (G-025, IMPROVEMENT 2 above)
   - `src/codegen.zig:11132` — `lua_invoke(__fn, c.args.len, __argv)` for `@native` functions when `native_scalar_mode` is false
   - Fix: IMPROVEMENT 2

2. **`@comp.embed.json` raw byte emission** (G-002, IMPROVEMENT 3 above)
   - `src/codegen.zig:921` — emits `uint8_t[]` instead of typed C struct; runtime access requires `lua_table` construction
   - Fix: IMPROVEMENT 3

3. **Comptime eval `Value.table` for meta metadata** (comptime.zig:572)
   - `src/comptime.zig:572` — `.table => "lua_Value"` in `typeNameOf`
   - This is the comptime evaluator's internal representation. The meta hooks (`metaValueFromFields`) construct `comptime_eval.Value.table` to pass field metadata to derive callbacks. This is *compile-time only* and does not leak to runtime, but it means derive callbacks written in Duo see a `lua_Value`-shaped table instead of a typed struct.
   - **Verdict:** Acceptable for now (compile-time only, no runtime cost), but a future improvement would be to pass typed `derive_eval.Metadata` structs directly to native derive callbacks, bypassing the `Value.table` intermediary.

4. **Unconditional `duo_runtime` prelude** (performance.md §3.1)
   - `src/codegen.zig:3662-3747` — the full `lua_Value` runtime (`lua_table_new`, `lua_invoke`, etc.) is emitted unconditionally even for typed-only programs
   - **Verdict:** Listed in performance.md as a known structural gap. The `native_scalar_mode` flag skips most of it, but not all modules qualify. A `--no-runtime` flag for typed-only programs would eliminate this.

5. **Metatable construction for types with methods** (codegen.zig:4738)
   - `src/codegen.zig:4738` — `duo_mt_TypeName = lua_table_new()` for types with methods, even in modules that could use direct dispatch
   - **Verdict:** Already gated by `if (self.native_scalar_mode) return;` at line 4725. Correct behavior — skipped in native mode.

---

## Underscore-Style Public Directives Audit

**Finding:** No underscore-style public directives remain in the active public API.

**Verification:**
- `src/meta_module.zig` builtins table (lines 76-483): All public names use dot hierarchy (`meta.map`, `comp.derive`, etc.). No underscores in any public name. A test at line 1076-1086 explicitly verifies this: it iterates all builtins and panics if any public name contains `_`.
- `src/meta_module.zig` directives table (lines 489-587): All public names use dot hierarchy. Canonical names (like `define_derive`, `derive_all`) are internal canonicalization targets, not public API.
- `src/parser.zig` lines 3295-3298: The test strings `@comptime_if` and `@static_assert` are inside test literals that verify the parser correctly resolves legacy underscore names to `__` internal targets. These are **test-only** and represent the desugar path, not the public API. The public API uses `@meta.when` (not `@comptime_if`) and `@meta.assert` (not `@static_assert`).
- `src/meta_module.zig` line 5 comment: explicitly states "NO underscore aliases (`@comptime_map`, `@define_derive`) — those are removed."

**Note on bare-name aliases:** A small set of bare-name aliases without dots are kept for ergonomics on extremely common intrinsics: `popcount`, `ctz`, `clz`, `bswap`, `rotl`, `rotr`, `bitcast`, `likely`, `unlikely`, `prefetch`, `assume`, `unreachable`, `trap`, `fence`, `volatile`, `emit`, `asm`, `hot`. These do NOT contain underscores and are documented as ergonomic exceptions (meta_module.zig lines 6-7). This is correct and intentional.

**Conclusion:** No underscore-style public directives need conversion. The migration is complete.

---

## Constructs Implemented But Not Fully Functional

1. **`@comp.compile.cached` (G-010)** — `src/comptime.zig` lines 153-159, 2300-2332
   - The comptime cache (`comptime_cache`) works within a single compilation unit. Cross-build persistence (G-010) is not implemented. The cache is an in-memory `StringHashMap` that is discarded after each build. For incremental builds, this means `@cached` functions are re-evaluated every time.
   - **Fix:** Persist the cache to a `.duo_cache/` directory keyed by function signature + argument hash, loaded at build start.

2. **`@comp.embed.json` codegen path** (G-002, IMPROVEMENT 3)
   - `meta_directives.zig` generates typed structs but `codegen.zig` emits raw bytes. The two paths are disconnected.

3. **Nested `req` from exported `std.*` function bodies (G-003)**
   - `src/codegen.zig:16090` — "Recursively collect nested require names from the embedded module"
   - When an exported `std.*` function body contains a `req` (require) call, the codegen module binding fails at runtime. The embedded module system collects require names but the binding for nested requires inside exported function bodies is broken.
   - **Fix:** The embedded module binding path (`emit_embedded_module` in codegen.zig ~16366) needs to recursively bind nested requires, not just top-level module requires.

---

## Constructs Planned But Missing

From `docs/performance.md` §3.5 and `docs/AGENT_GAPS.md`:

1. **`@trace` (graph capture)** — performance.md §3.5: "not implemented"
2. **`@memory_plan`** — performance.md §3.5: "not implemented"
3. **`@device` routing to backends** — performance.md §3.1: "@device is parsed in src/directives.zig but not routed to a backend in src/codegen.zig" (only emits a comment)
4. **Direct asm / object / machine-code emission (G-008, G-020, G-021)** — C is the only backend; the ultimate goal of direct machine code is not reached
5. **PGO for user binaries (G-022)** — `--pgo` only on the 40-benchmark gate, not exposed for general `duo compile`
6. **LTO in build pipeline (G-023)** — not wired into `duo build`
7. **`@meta.grammar` (IMPROVEMENT 4)** — grammar-driven generation
8. **`@meta.weave` (IMPROVEMENT 5)** — cross-module type-driven injection

---

## What Would Remove the Linear Ceiling on Agent Code Production

The linear ceiling exists because:
1. Each module is a separate metaprogramming context — no cross-module type-driven generation (IMPROVEMENT 5)
2. All combinators enumerate over *existing types* — none generate *new* code patterns from a specification (IMPROVEMENT 4)
3. `@comp.compile.cached` doesn't persist across builds, so agents can't accumulate metaprogramming results (G-010)

Removing the ceiling requires:
- **`@meta.weave`** (IMPROVEMENT 5) — 1 type definition → N modules generate code
- **`@meta.grammar`** (IMPROVEMENT 4) — k production rules → O(b^d) generated patterns
- **Cross-build cache persistence** (G-010) — agents accumulate generated code across sessions
- **`@meta.weave` + `@meta.grammar` combined** — grammar-driven generation applied across modules = O(b^d × N) exponential output

---

## Files I Created/Modified

- **Created:** `docs/META_AUDIT.md` — this audit report
- **Did not modify any source files** — the duplicate test name (IMPROVEMENT 1) is a trivial fix but I've documented it for the responsible agent to claim in `.agents/AGENT_COORDINATION.md` to avoid conflicts.

## Issues Encountered

1. **Build failure:** `zig build test` fails due to duplicate test name in `src/meta_module.zig` (lines 1013 and 1038). This blocks all CI and should be fixed immediately.
2. **Large file handling:** `src/codegen.zig` is 26K+ lines / 1.2MB — read targeted sections via search and offset reading.
3. **`docs/performance.md` is 13K lines / 625KB** — read the first 500 lines which contain the current snapshot and gap analysis.
