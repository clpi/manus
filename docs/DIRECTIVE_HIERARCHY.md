# Duo `@` Directive Hierarchy (canonical)

All compile-time and compiler directives use **dotted module paths**, not underscores.

| Prefix | Role | Examples |
| --- | --- | --- |
| `@comp.*` | **Preferred** compiler meta-module (combinators, agent hooks) | `@comp.derive`, `@comp.template`, `@comp.agent.gaps()` |
| `@meta.*` | Alias of `@comp.*` (backward compat) | `@meta.map` ≡ `@comp.map` |
| `@compiler.*` | Alias of `@comp.*` | `@compiler.pipeline` |
| `@c.*` | C ABI / raw injection | `@c.emit`, `@c.import` |
| `@derive(...)` | Type attribute (traits) | `@derive(Add, Eq)` |
| `@hot`, `@inline`, … | Function attributes | desugar to internal `__hot_path` |

## Rules (all agents)

1. **Never add** `@comp.foo_bar` or `@meta_foo` underscore spellings — use `@comp.foo.bar`.
2. **Internal desugar** targets (`__emit`, `__comptimemap`) are Zig-only; not user-facing.
3. **Module directives** (file scope): `@comp.pipeline`, `@comp.embed.json`, `@comp.wasm`.
4. **Expression combinators**: `@comp.map`, `@comp.match`, `@comp.tabulate`, `@comp.interpolate`, `@comp.zip`, `@comp.grammar`, `@comp.template`, `@comp.generate`, `@comp.scheme`, `@comp.scheme.clauses`, `@comp.weave`, `@comp.each`.
5. **Agent hooks** (Duo development): `@comp.agent.catalog()`, `.gaps()`, `.grammar()`, `.dedupe()`.
6. **Bit intrinsics**: prefer `@comp.bit.popcount` or bare `@popcount`; not `@pop_count`.

## Scaling ladder (expression combinators)

| Rung | Construct | Scaling |
| --- | --- | --- |
| Linear | `@comp.map`, `@comp.template`, `@comp.generate`, `@comp.scheme`, `@comp.match`, `@comp.tabulate`, `@comp.interpolate` | O(n) |
| Quadratic | `@comp.product`, `@comp.derive.product`, `@comp.zip` | O(n²) |
| Cubic+ | `@comp.tensor`, `@comp.burst`, `@comp.transcend` | O(n³)+ |
| Grammar | `@comp.grammar` | O(b^d) |
| Subset | `@comp.power`, `@comp.choose` | O(2^n), O(n choose k) |
| Permute | `@comp.permute` | O(n!) |
| Glue | `@comp.each`, `@comp.chain` | composes any combinator output (`chain` ≡ `each`) |
| Introspection | `@comp.str.countlines`, `@comp.str.splitcount`, `@comp.str.len`, `@comp.str.eq`, `@comp.str.join`, `@comp.str.contains`, `@comp.concepts.count`, `@comp.rewrite.describe`, `@comp.rewrite.rulecount` | native comptime utilities (no lua) |
| Combinatorics | `@comp.sweep`, `@comp.pow`, `@comp.stack`, `@comp.powerset` | O(n) sweep, O(2^n) power/powerset, stack-based composition |
| Type introspection | `@comp.type.names`, `@comp.type.of` | list type names, C `typeof` type-specifier |
| C ABI | `@comp.c.link`, `@comp.c.emit.file` | C linkage, C file emission |
| Hints | `@comp.hint.hot`, `@comp.hint.volatile` | hot-path optimization hint, volatile annotation |
| Register/Rewrite | `@comp.register.rewrite`, `@comp.rewrite.describe`, `@comp.rewrite.rulecount` | register rewrite rules, describe bundles, count active rules |
| Compile control | `@comp.compile.native`, `@comp.compile.only`, `@comp.compile.differentiable` | native target, compile-only callback, differentiable function |
| Emit | `@comp.emit.derive`, `@comp.emit.omni`, `@comp.emit.file`, `@comp.emit` (bare) | derive/omni emission, file emission, bare emit (raw C injection) |
| Asm | `@comp.asm` (bare) | inline assembly injection |
| String ops | `@comp.str.*` family (`countlines`, `splitcount`, `len`, `eq`, `join`, `contains`) | native comptime string utilities |

## Exponential-tier ground-truth audit (2026-08-04, pi)

Empirical probe (`duo-safe run` + generated-C inspection, `DUO_KEEP_C=1`) of every
registered combinator at/above O(2^n). Status = does the combinator fold to a
**native `const char*` literal with zero `lua_Value` boxing** (the project rule)?

| Combinator | Scaling | Folds? | Native emit? | Status |
| --- | --- | --- | --- | --- |
| `@comp.power` | O(2^n) | yes | **yes** bare literal | ✅ working, showcased |
| `@comp.powerset` | O(2^n) (≡ power) | yes | **yes** bare literal | ✅ working, showcased (canonical alias of power) |
| `@comp.permute` | O(n!) | yes | **yes** bare literal | ✅ working, showcased |
| `@comp.tensor` | O(n³) | yes (content correct) | **no** — emits `lua_to_str("<literal>")` | ❌ BLOCKED (codegen emission) — see gap F-2026-08-04-expo-emit |
| `@comp.transcend` | O(n³)+ | yes (content correct) | **no** — same `lua_to_str` wrapper | ❌ BLOCKED — same root cause |
| `@comp.infinity` | O(n⁴) | yes (all 3⁴ 4-tuples present) | **no** — same `lua_to_str` wrapper | ❌ BLOCKED — same root cause |
| `@comp.hyper` | O(n⁵) | yes (all 3⁵ 5-tuples present) | **no** — same `lua_to_str` wrapper | ❌ BLOCKED — same root cause |
| `@comp.nfold` | O(n^k) | n/a | **no** — registered + hook exists but NO codegen dispatch → undeclared `__comptimenfold` | ❌ BLOCKED (codegen unwired) — see gap F-2026-08-04-nfold-unwired |

**Single root cause for the 4 `lua_to_str` blockers** (tensor/transcend/infinity/hyper):
all four fold their exponential expansion **correctly** in `meta_codegen.zig`
(hooks return `.string` with the right content — e.g. hyper emits all 243 five-tuples),
but their fold dispatch in `maybe_emit_meta_string_call` (`src/codegen.zig:11870`,
tensor block ~`:12099`, transcend ~`:12146`, infinity ~`:12188`, hyper ~`:12197`)
does not reach `emit_c_string_literal` for these four, so they fall through to a
generic comptime-`.string`-value emission that wraps in `lua_to_str("<literal>")` —
a C type error (`char[]` passed where `lua_Value` expected) AND a boxing smell.
`@comp.power`/`@comp.powerset`/`@comp.permute` in the **same function** emit bare
literals correctly, proving the hooks + `emit_c_string_literal` path work; only the
reachability/emission for the cubic+ four is broken. **One emission fix unblocks
four exponential combinators (O(n³)–O(n⁵)).** codegen.zig is LOCKED (antigravity,
native lowering) — filed, not self-fixed.

MCP: `duo_directive_hierarchy_read`, `duo_meta_catalog`, `duo_meta_ladder`,
`duo_audit_metaprogramming_smokes`.

## Path mismatch corrections (2026-08-02)

The following directives were documented under `@comp.derive.*` but are actually implemented under different module paths:

| Documented (incorrect) | Actual (correct) |
| --- | --- |
| `@comp.derive.define` | `@comp.define.derive` |
| `@comp.derive.register` | `@comp.register.derive` |
| `@comp.derive.bundle` | `@comp.define.bundle` |

All call sites and documentation should use the actual (correct) forms.

**Generative algebra:** chain `template` / `generate` / `scheme` through `@comp.each` — see `examples/meta_generative_stack_showcase.duo`. Batch native audit: MCP `duo_audit_metaprogramming_smokes()`.

MCP: `duo_directive_hierarchy_read`, `duo_meta_catalog`, `duo_meta_ladder`.

## Legacy flat/underscore alias table (cleanup PENDING — blocked on locked parser.zig)

**Root cause of recurring "`@foo_bar` underscore directive" complaints** (pi audit, 2026-08-02): `src/parser.zig:~3128-3180` holds a ~52-entry **legacy flat/underscore alias table** that maps flat public names directly to `__internal` targets, **bypassing the `meta_module.zig:1397` guard** (that guard only scans the `meta_module` catalog, not the parser table — so it stays green while ~30 violating names survive). Offending public names include `static_assert`, `type_name`, `type_id`, `is_type`, `concept_methods`, `has_field`, `has_method`, `has_metamethod`, `field_type`, `field_offset`, `field_size`, `embed_str`, `embed_file`, `make_type`, `as_type`, and the whole `comptime_*` family (`comptime_if`, `comptime_for`, `comptime_fold`, `comptime_print`, `comptime_warn`, `comptime_error`) — the last group is doubly bad per GR-007 (the `comptime` surface should be gone).

**Atomic rename plan (for the parser.zig/meta_module.zig owners):**
1. Add canonical `@comp.*` dotted entries for each legacy name (model: `comp.assert`→`__static_assert` at `meta_module.zig:269` already exists). Proposed: `type_name`→`@comp.type.name`, `is_type`→`@comp.type.is`, `type_id`→`@comp.type.id`, `concept_methods`→`@comp.concepts.methods`, `has_metamethod`→`@comp.has.metamethod`, `field_type`→`@comp.field.type`, `embed_str`→`@comp.embed.str`, `as_type`→`@comp.as.type`, `comptime_if`→`@comp.if`, `comptime_for`→`@comp.for`, `comptime_fold`→`@comp.fold`, `compile_error`→`@comp.error`.
2. **Extend the `meta_module.zig:1397` guard to ALSO scan `parser.zig`'s legacy table** so flat/underscore names can't sneak back.
3. Make flat forms emit a GR-007-style deprecation hint pointing to `@comp.*`, then eventually hard-remove.

**Done (non-colliding):** all `@static_assert` call sites migrated to `@comp.assert` (6 example files; verified `duo check` clean).

**Canonical `@comp.*` dotted forms now REGISTERED** (meta_module.zig catalog; verified `zig build` green + 696/696 unit tests; `@comp.type.name(x)`→`"int64_t"`, `@comp.type.is`→bool, `@comp.type.id`→i64 all fold correctly). Migration mapping (legacy flat → canonical, same internal):

| Legacy flat | Canonical `@comp.*` |
| --- | --- |
| `static_assert` | `@comp.assert` |
| `type_name` | `@comp.type.name` |
| `type_id` | `@comp.type.id` |
| `is_type` | `@comp.type.is` |
| `typeinfo` | `@comp.type.info` |
| `concept_methods` | `@comp.concepts.methods` |
| `has_field` / `has_method` / `has_metamethod` | `@comp.has.field` / `.method` / `.metamethod` |
| `field_type` / `field_offset` / `field_size` | `@comp.field.type` / `.offset` / `.size` |
| `embed_str` / `embed_file` | `@comp.embed.str` / `.file` |
| `make_type` / `as_type` | `@comp.make.type` / `@comp.as.type` |
| `comptime_if` / `comptime_for` | `@comp.if` / `@comp.for` |
| `bitfield` | `@comp.bit.field` |
| `compile_log` / `comptime_warn` / `compile_error` | `@comp.compile.log` / `@comp.compile.warn` / `@comp.compile.error` (pre-existing) |
| `fields` / `methods` / `variants` / `satisfies` | `@comp.fields` / `@comp.methods` / `@comp.variants` / `@comp.satisfies` |

Example call sites migrated to canonical forms: `metaprogramming_test.duo`, `metaprogramming_showcase.duo`, `concept_introspect.duo` (all `duo check` clean). The flat aliases in `parser.zig` still work (deprecated); removing them + extending the `meta_module.zig:1397` guard to scan `parser.zig` is the remaining cleanup. NOTE: `@comp.type.of` was NOT added — `__typeof` emits the C `typeof` keyword (a type-specifier, not a value expression), same quirk as legacy `@typeof`.

## G-056 reconciliation (2026-08-03) — one canonical name per intrinsic

`__comptimeif` / `__comptimefor` had **two** public names each (`@comp.when`/`@comp.loop` AND `@comp.if`/`@comp.for`).

**Decision — canonical forms (matching the migration table above):**

| Internal | Canonical | Alias (kept, working) |
| --- | --- | --- |
| `__comptimeif` | `@comp.if` | `@comp.when`, `@comp.meta.when`, `@comp.compiler.when` |
| `__comptimefor` | `@comp.for` | `@comp.loop`, `@comp.meta.loop`, `@comp.compiler.loop` |

- Parser legacy deprecation hints (`@comptime_if`, `@comptime_for`) now point at `@comp.if` / `@comp.for`.
- The alias forms remain registered in `meta_module.zig` (no call-site breakage); they are not advertised in docs/catalog.
- Pending (needs build verification when machine load permits): confirm no unit test asserts the old `comp.when`/`comp.loop` hint text.
- NOTE: AGENTS.md §2 sketches the future `@comp.compile.*` home (`when`/`loop`/`fold`/…). A future coordinated rename `comp.if`→`comp.compile.when` etc. would be a breaking change; do NOT do it piecemeal — track as one atomic migration.
