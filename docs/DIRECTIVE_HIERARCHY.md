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
4. **Expression combinators**: `@comp.map`, `@comp.grammar`, `@comp.template`, `@comp.generate`, `@comp.scheme`, `@comp.scheme.clauses`, `@comp.weave`, `@comp.each`.
5. **Agent hooks** (Duo development): `@comp.agent.catalog()`, `.gaps()`, `.grammar()`, `.dedupe()`.
6. **Bit intrinsics**: prefer `@comp.bit.popcount` or bare `@popcount`; not `@pop_count`.

## Scaling ladder (expression combinators)

| Rung | Construct | Scaling |
| --- | --- | --- |
| Linear | `@comp.map`, `@comp.template`, `@comp.generate`, `@comp.scheme` | O(n) |
| Quadratic | `@comp.product`, `@comp.derive.product` | O(n²) |
| Cubic+ | `@comp.tensor`, `@comp.burst`, `@comp.transcend` | O(n³)+ |
| Grammar | `@comp.grammar` | O(b^d) |
| Subset | `@comp.power`, `@comp.choose` | O(2^n), O(n choose k) |
| Permute | `@comp.permute` | O(n!) |
| Glue | `@comp.each`, `@comp.chain` | composes any combinator output (`chain` ≡ `each`) |
| Introspection | `@comp.str.countlines`, `@comp.str.splitcount`, `@comp.str.len`, `@comp.str.eq`, `@comp.str.join`, `@comp.str.contains`, `@comp.concepts.count`, `@comp.rewrite.describe`, `@comp.rewrite.rulecount` | native comptime utilities (no lua) |

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
