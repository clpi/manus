/// Canonical `@comp.*` compiler module: hierarchical public names for metaprogramming.
///
/// The PRIMARY public surface for compile-time operations is `@comp.*` dotted paths.
/// `@compiler.*`, and `@meta.*` are aliases that map to the same internal handlers.
/// NO underscore aliases (`@comptime_map`, `@define_derive`) — those are removed.
/// A small set of bare-name aliases (`@popcount`, `@clz`, `@likely`, etc.) are kept
/// for ergonomics on extremely common intrinsics that predate the hierarchy.
///
/// Hierarchy:
///   @comp.compile.*     — compile-time control (when, loop, fold, log, warn, error, assert, cached, thread, device, autodiff, unroll, modify, profile)
///   @comp.embed.*       — file embedding (str, file, json, wasm)
///   @comp.bit.*         — bit intrinsics (popcount, ctz, clz, bswap, rotl, rotr, bitcast)
///   @comp.hint.*        — optimization hints (likely, unlikely, prefetch, assume, unreachable, trap, fence)
///   @comp.type.*        — type introspection (name, id, info, is, as)
///   @comp.types         — all module types
///   @comp.types.with    — types matching a concept
///   @comp.fields        — field listing
///   @comp.field.*       — field-level (type, offset, size)
///   @comp.methods       — method listing
///   @comp.has.*         — structural checks (field, method, metamethod)
///   @comp.concepts.*    — concept introspection (methods, fields, members)
///   @comp.satisfies     — concept membership check
///   @comp.diff          — type diff
///   @comp.fields.map    — field metadata expansion
///   @comp.c.*           — C interface (emit, include, import, export, call, type)
///   @comp.derive        — derive application to matching types
///   @comp.derive.*      — derive management (define, register, lookup, list, eval, bundle, all, product, tensor, nfold)
///   @comp.define.derive — user-defined derive macros
///   @comp.rewrite       — rewrite rule registration
///   @comp.rewrite.bundle — rewrite bundle
///   @comp.map           — concept-targeted type sweep with callback (O(n))
///   @comp.expand        — derive sweep + optional concept map (O(n^f))
///   @comp.ceiling       — derive sweep + cartesian product (O(n^f)+O(n2^f))
///   @comp.omni          — ceiling + optional sweep
///   @comp.burst         — derive.all + product (O(n2^f))
///   @comp.transcend     — 3-concept derive + map (O(n3^f))
///   @comp.tensor        — 3-concept type sweep (O(n3))
///   @comp.product       — 2-concept cartesian product (O(n2))
///   @comp.nfold         — N-concept type sweep (O(n^k))
///   @comp.infinity      — transcend + nfold(4) (O(n^4^f))
///   @comp.hyper         — transcend + nfold(5) (O(n^5^f))
///   @comp.tower         — nfold with dynamic k (O(n^k^f), k up to 16)
///   @comp.power         — O(2^n) powerset expansion
///   @comp.permute       — O(n!) permutation expansion
///   @comp.pipeline      — pipeline families
///   @comp.foreign       — cross-language transpilation
///   @comp.sql           — SQL DDL to C struct
///   @comp.lua           — compile-time Lua execution
///   @comp.schema        — schema generation
///   @comp.codegen       — raw codegen injection
///   @comp.ffi           — FFI generation
///   @comp.wasm          — embed WASM bytes as const uint8_t[] (module directive)
///   @comp.make.type     — type construction
///   @comp.as.type       — explicit type cast
///   @comp.bitfield      — bitfield type
///   @comp.union         — union type
///   @comp.select        — compile-time select
///   @comp.run           — compile-time execution
///   @comp.constexpr     — constexpr evaluation
///   @comp.catalog       — self-documenting meta directive catalog
///   @comp.ladder        — exponential scaling reference
///   @comp.agent.*       — agent discoverability (catalog, ladder, hooks, dedupe, gaps)
///   @comp.grammar       — EBNF grammar -> O(b^d) code fragments (generative combinator)
///   @comp.weave         — cross-module type-driven code injection (O(N^M) from 1 type)
///   @comp.template      — parametric code templates that expand at compile time
///   @comp.generate      — constraint-based generative code synthesis
///   @comp.scheme        — declarative program scheme -> full implementation
///   @comp.scheme.clauses — named clause list -> O(clauses) native C fragments
///   @comp.fixpoint      — unbounded iterative combinator (O(1) -> O(max_iter))
///   @comp.fanout        — tree-shaped generative expansion (O(branch^depth))
///
/// Keyword-safe paths: avoid Duo keywords as path segments — use `@comp.when` not
/// `@comp.if`, `@comp.concepts.*` not `@comp.concept.*`, `@comp.compile.warn` not
/// `@comp.comptime.warn`. All `@meta.*` and `@compiler.*` paths are aliases.
const std = @import("std");

const BuiltinEntry = struct { public: []const u8, internal: []const u8 };
const DirectiveEntry = struct { public: []const u8, canonical: []const u8 };

// ─────────────────────────────────────────────────────────────────────────────
// Expression builtins: `@meta.*` canonical paths + bare-name ergonomic aliases
// ─────────────────────────────────────────────────────────────────────────────

const builtins = [_]BuiltinEntry{
    // ── Exponential combinators ──
    .{ .public = "meta.map", .internal = "__comptimemap" },
    .{ .public = "comp.map", .internal = "__comptimemap" },
    .{ .public = "compiler.map", .internal = "__comptimemap" },
    .{ .public = "meta.sweep", .internal = "__comptimemap" },
    .{ .public = "comp.sweep", .internal = "__comptimemap" },
    .{ .public = "compiler.sweep", .internal = "__comptimemap" },
    .{ .public = "meta.expand", .internal = "__metaexpand" },
    .{ .public = "comp.expand", .internal = "__metaexpand" },
    .{ .public = "compiler.expand", .internal = "__metaexpand" },
    .{ .public = "meta.pow", .internal = "__metaexpand" },
    .{ .public = "comp.pow", .internal = "__metaexpand" },
    .{ .public = "compiler.pow", .internal = "__metaexpand" },
    .{ .public = "meta.ceiling", .internal = "__metaceiling" },
    .{ .public = "comp.ceiling", .internal = "__metaceiling" },
    .{ .public = "compiler.ceiling", .internal = "__metaceiling" },
    .{ .public = "meta.omni", .internal = "__metaomni" },
    .{ .public = "comp.omni", .internal = "__metaomni" },
    .{ .public = "compiler.omni", .internal = "__metaomni" },
    .{ .public = "meta.stack", .internal = "__metaomni" },
    .{ .public = "comp.stack", .internal = "__metaomni" },
    .{ .public = "compiler.stack", .internal = "__metaomni" },
    .{ .public = "meta.burst", .internal = "__metaburst" },
    .{ .public = "comp.burst", .internal = "__metaburst" },
    .{ .public = "compiler.burst", .internal = "__metaburst" },
    .{ .public = "meta.tensor", .internal = "__comptimetensor" },
    .{ .public = "comp.tensor", .internal = "__comptimetensor" },
    .{ .public = "compiler.tensor", .internal = "__comptimetensor" },
    .{ .public = "meta.derive.tensor", .internal = "__derivetensor" },
    .{ .public = "comp.derive.tensor", .internal = "__derivetensor" },
    .{ .public = "compiler.derive.tensor", .internal = "__derivetensor" },
    .{ .public = "meta.nfold", .internal = "__comptimenfold" },
    .{ .public = "comp.nfold", .internal = "__comptimenfold" },
    .{ .public = "compiler.nfold", .internal = "__comptimenfold" },
    .{ .public = "meta.derive.nfold", .internal = "__derivenfold" },
    .{ .public = "comp.derive.nfold", .internal = "__derivenfold" },
    .{ .public = "compiler.derive.nfold", .internal = "__derivenfold" },
    .{ .public = "meta.transcend", .internal = "__metatranscend" },
    .{ .public = "comp.transcend", .internal = "__metatranscend" },
    .{ .public = "compiler.transcend", .internal = "__metatranscend" },
    .{ .public = "meta.infinity", .internal = "__metainfinity" },
    .{ .public = "comp.infinity", .internal = "__metainfinity" },
    .{ .public = "compiler.infinity", .internal = "__metainfinity" },
    .{ .public = "meta.hyper", .internal = "__metahyper" },
    .{ .public = "comp.hyper", .internal = "__metahyper" },
    .{ .public = "compiler.hyper", .internal = "__metahyper" },
    .{ .public = "meta.tower", .internal = "__derivetower" },
    .{ .public = "comp.tower", .internal = "__derivetower" },
    .{ .public = "compiler.tower", .internal = "__derivetower" },
    .{ .public = "meta.derive", .internal = "__derivemap" },
    .{ .public = "comp.derive", .internal = "__derivemap" },
    .{ .public = "compiler.derive", .internal = "__derivemap" },
    .{ .public = "meta.product", .internal = "__comptimeproduct" },
    .{ .public = "comp.product", .internal = "__comptimeproduct" },
    .{ .public = "compiler.product", .internal = "__comptimeproduct" },
    .{ .public = "meta.derive.product", .internal = "__deriveproduct" },
    .{ .public = "comp.derive.product", .internal = "__deriveproduct" },
    .{ .public = "compiler.derive.product", .internal = "__deriveproduct" },
    // ── Truly exponential (2^n / n!) combinators ──
    .{ .public = "meta.power", .internal = "__comptimepower" },
    .{ .public = "comp.power", .internal = "__comptimepower" },
    .{ .public = "compiler.power", .internal = "__comptimepower" },
    .{ .public = "meta.powerset", .internal = "__comptimepower" },
    .{ .public = "comp.powerset", .internal = "__comptimepower" },
    .{ .public = "compiler.powerset", .internal = "__comptimepower" },
    .{ .public = "meta.derive.power", .internal = "__derivepower" },
    .{ .public = "comp.derive.power", .internal = "__derivepower" },
    .{ .public = "compiler.derive.power", .internal = "__derivepower" },
    .{ .public = "meta.derive.powerset", .internal = "__derivepower" },
    .{ .public = "comp.derive.powerset", .internal = "__derivepower" },
    .{ .public = "compiler.derive.powerset", .internal = "__derivepower" },
    .{ .public = "meta.choose", .internal = "__comptimechoose" },
    .{ .public = "comp.choose", .internal = "__comptimechoose" },
    .{ .public = "compiler.choose", .internal = "__comptimechoose" },
    .{ .public = "meta.derive.choose", .internal = "__derivechoose" },
    .{ .public = "comp.derive.choose", .internal = "__derivechoose" },
    .{ .public = "compiler.derive.choose", .internal = "__derivechoose" },
    .{ .public = "meta.permute", .internal = "__comptimepermute" },
    .{ .public = "comp.permute", .internal = "__comptimepermute" },
    .{ .public = "compiler.permute", .internal = "__comptimepermute" },
    .{ .public = "meta.derive.permute", .internal = "__derivepermute" },
    .{ .public = "comp.derive.permute", .internal = "__derivepermute" },
    .{ .public = "compiler.derive.permute", .internal = "__derivepermute" },
    // ── Universal composition glue (closes the combinator algebra) ──
    .{ .public = "meta.each", .internal = "__comptimeeach" },
    .{ .public = "comp.each", .internal = "__comptimeeach" },
    .{ .public = "compiler.each", .internal = "__comptimeeach" },
    // `@comp.chain` — ergonomic alias for `@comp.each` (combinator composition glue)
    .{ .public = "meta.chain", .internal = "__comptimeeach" },
    .{ .public = "comp.chain", .internal = "__comptimeeach" },
    .{ .public = "compiler.chain", .internal = "__comptimeeach" },

    // `@comp.match` — compile-time pattern-match codegen (switch/case of codegen)
    // Splits pattern spec on `|`, calls callback for each alternative with {pattern, index, count}.
    // One declarative line → N specialized branches. Composes with @comp.each, @comp.burst, etc.
    .{ .public = "meta.match", .internal = "__comptimematch" },
    .{ .public = "comp.match", .internal = "__comptimematch" },
    .{ .public = "compiler.match", .internal = "__comptimematch" },

    // `@comp.tabulate` — compile-time lookup table generator (unrolled loop of codegen)
    // Calls callback for 0..count-1 with {index, count}, concatenates comma-separated.
    // O(1) author input → O(count) output. Replaces runtime init with compile-time static.
    .{ .public = "meta.tabulate", .internal = "__comptimetabulate" },
    .{ .public = "comp.tabulate", .internal = "__comptimetabulate" },
    .{ .public = "compiler.tabulate", .internal = "__comptimetabulate" },

    // `@comp.interpolate` — compile-time string interpolation (code template injection)
    // Takes template with {name} placeholders + {name=value} vars table, substitutes at compile time.
    .{ .public = "meta.interpolate", .internal = "__comptimeinterpolate" },
    .{ .public = "comp.interpolate", .internal = "__comptimeinterpolate" },
    .{ .public = "compiler.interpolate", .internal = "__comptimeinterpolate" },

    // `@comp.zip` — compile-time cartesian zip codegen (quadratic combinator)
    // Two pipe-separated specs, callback for every (a, b) pair with {a, b, index, count}.
    .{ .public = "meta.zip", .internal = "__comptimezip" },
    .{ .public = "comp.zip", .internal = "__comptimezip" },
    .{ .public = "compiler.zip", .internal = "__comptimezip" },

    // ── Type introspection ──
    .{ .public = "meta.type.name", .internal = "__type_name" },
    .{ .public = "comp.type.name", .internal = "__type_name" },
    .{ .public = "compiler.type.name", .internal = "__type_name" },
    .{ .public = "meta.type.id", .internal = "__type_id" },
    .{ .public = "comp.type.id", .internal = "__type_id" },
    .{ .public = "compiler.type.id", .internal = "__type_id" },
    .{ .public = "meta.type.info", .internal = "__typeinfo" },
    .{ .public = "comp.type.info", .internal = "__typeinfo" },
    .{ .public = "compiler.type.info", .internal = "__typeinfo" },
    .{ .public = "meta.typeinfo", .internal = "__typeinfo" },
    .{ .public = "meta.type.is", .internal = "__is_type" },
    .{ .public = "comp.type.is", .internal = "__is_type" },
    .{ .public = "compiler.type.is", .internal = "__is_type" },
    .{ .public = "meta.is.type", .internal = "__is_type" },
    .{ .public = "meta.type.of", .internal = "__typeof" },
    .{ .public = "comp.type.of", .internal = "__typeof" },
    .{ .public = "compiler.type.of", .internal = "__typeof" },
    .{ .public = "meta.typeof", .internal = "__typeof" },
    .{ .public = "meta.types", .internal = "__moduletypes" },
    .{ .public = "comp.types", .internal = "__moduletypes" },
    .{ .public = "compiler.types", .internal = "__moduletypes" },
    .{ .public = "meta.type.names", .internal = "__moduletypenames" },
    .{ .public = "comp.type.names", .internal = "__moduletypenames" },
    .{ .public = "compiler.type.names", .internal = "__moduletypenames" },
    .{ .public = "meta.types.with", .internal = "__concepttypenames" },
    .{ .public = "comp.types.with", .internal = "__concepttypenames" },
    .{ .public = "compiler.types.with", .internal = "__concepttypenames" },
    .{ .public = "meta.diff", .internal = "__typediff" },
    .{ .public = "comp.diff", .internal = "__typediff" },
    .{ .public = "compiler.diff", .internal = "__typediff" },
    .{ .public = "meta.satisfies", .internal = "__satisfies" },
    .{ .public = "comp.satisfies", .internal = "__satisfies" },
    .{ .public = "compiler.satisfies", .internal = "__satisfies" },

    // ── Structural reflection ──
    .{ .public = "meta.fields", .internal = "__fields" },
    .{ .public = "comp.fields", .internal = "__fields" },
    .{ .public = "compiler.fields", .internal = "__fields" },
    .{ .public = "meta.fields.map", .internal = "__fieldsmap" },
    .{ .public = "comp.fields.map", .internal = "__fieldsmap" },
    .{ .public = "compiler.fields.map", .internal = "__fieldsmap" },
    .{ .public = "meta.methods", .internal = "__methods" },
    .{ .public = "comp.methods", .internal = "__methods" },
    .{ .public = "compiler.methods", .internal = "__methods" },
    .{ .public = "meta.variants", .internal = "__variants" },
    .{ .public = "comp.variants", .internal = "__variants" },
    .{ .public = "compiler.variants", .internal = "__variants" },
    .{ .public = "meta.has.field", .internal = "__has_field" },
    .{ .public = "comp.has.field", .internal = "__has_field" },
    .{ .public = "compiler.has.field", .internal = "__has_field" },
    .{ .public = "meta.has.method", .internal = "__has_method" },
    .{ .public = "comp.has.method", .internal = "__has_method" },
    .{ .public = "compiler.has.method", .internal = "__has_method" },
    .{ .public = "meta.has.metamethod", .internal = "__has_metamethod" },
    .{ .public = "comp.has.metamethod", .internal = "__has_metamethod" },
    .{ .public = "compiler.has.metamethod", .internal = "__has_metamethod" },
    .{ .public = "meta.field.type", .internal = "__field_type" },
    .{ .public = "comp.field.type", .internal = "__field_type" },
    .{ .public = "compiler.field.type", .internal = "__field_type" },
    .{ .public = "meta.field.offset", .internal = "__field_offset" },
    .{ .public = "comp.field.offset", .internal = "__field_offset" },
    .{ .public = "compiler.field.offset", .internal = "__field_offset" },
    .{ .public = "meta.field.size", .internal = "__field_size" },
    .{ .public = "comp.field.size", .internal = "__field_size" },
    .{ .public = "compiler.field.size", .internal = "__field_size" },

    // ── Concept introspection ──
    .{ .public = "meta.concepts.methods", .internal = "__concept_methods" },
    .{ .public = "comp.concepts.methods", .internal = "__concept_methods" },
    .{ .public = "compiler.concepts.methods", .internal = "__concept_methods" },
    .{ .public = "meta.concepts.fields", .internal = "__concept_fields" },
    .{ .public = "comp.concepts.fields", .internal = "__concept_fields" },
    .{ .public = "compiler.concepts.fields", .internal = "__concept_fields" },
    .{ .public = "meta.concepts.members", .internal = "__concept_members" },
    .{ .public = "comp.concepts.members", .internal = "__concept_members" },
    .{ .public = "compiler.concepts.members", .internal = "__concept_members" },
    .{ .public = "meta.concepts.count", .internal = "__concept_count" },
    .{ .public = "comp.concepts.count", .internal = "__concept_count" },
    .{ .public = "compiler.concepts.count", .internal = "__concept_count" },

    // ── Compile-time control ──
    .{ .public = "meta.when", .internal = "__comptimeif" },
    .{ .public = "comp.when", .internal = "__comptimeif" },
    .{ .public = "compiler.when", .internal = "__comptimeif" },
    .{ .public = "meta.loop", .internal = "__comptimefor" },
    .{ .public = "comp.loop", .internal = "__comptimefor" },
    .{ .public = "compiler.loop", .internal = "__comptimefor" },
    .{ .public = "meta.fold", .internal = "__comptimefold" },
    .{ .public = "comp.fold", .internal = "__comptimefold" },
    .{ .public = "compiler.fold", .internal = "__comptimefold" },
    .{ .public = "meta.assert", .internal = "__static_assert" },
    .{ .public = "comp.assert", .internal = "__static_assert" },
    .{ .public = "compiler.assert", .internal = "__static_assert" },
    .{ .public = "meta.compile.log", .internal = "__comptimeprint" },
    .{ .public = "comp.compile.log", .internal = "__comptimeprint" },
    .{ .public = "compiler.compile.log", .internal = "__comptimeprint" },
    .{ .public = "meta.compile.warn", .internal = "__comptimewarn" },
    .{ .public = "comp.compile.warn", .internal = "__comptimewarn" },
    .{ .public = "compiler.compile.warn", .internal = "__comptimewarn" },
    .{ .public = "meta.compile.error", .internal = "__comptimeerror" },
    .{ .public = "comp.compile.error", .internal = "__comptimeerror" },
    .{ .public = "compiler.compile.error", .internal = "__comptimeerror" },
    // Canonical @comp.* dotted forms for the legacy flat/underscored parser aliases
    // (type introspection, concept/field/embed helpers, comptime control). Same
    // internals as the flat names; flat forms remain as deprecated aliases until
    // call sites migrate, then the parser.zig legacy table + guard-extension remove them.
    .{ .public = "comp.type.name", .internal = "__type_name" },
    .{ .public = "comp.type.id", .internal = "__type_id" },
    .{ .public = "comp.type.is", .internal = "__is_type" },
    .{ .public = "comp.type.info", .internal = "__typeinfo" },
    .{ .public = "comp.fields", .internal = "__fields" },
    .{ .public = "comp.methods", .internal = "__methods" },
    .{ .public = "comp.concepts.methods", .internal = "__concept_methods" },
    .{ .public = "comp.variants", .internal = "__variants" },
    .{ .public = "comp.has.field", .internal = "__has_field" },
    .{ .public = "comp.has.method", .internal = "__has_method" },
    .{ .public = "comp.has.metamethod", .internal = "__has_metamethod" },
    .{ .public = "comp.satisfies", .internal = "__satisfies" },
    .{ .public = "comp.field.type", .internal = "__field_type" },
    .{ .public = "comp.field.offset", .internal = "__field_offset" },
    .{ .public = "comp.field.size", .internal = "__field_size" },
    .{ .public = "comp.embed.str", .internal = "__embed_str" },
    .{ .public = "comp.embed.file", .internal = "__embed_file" },
    .{ .public = "comp.make.type", .internal = "__make_type" },
    .{ .public = "comp.as.type", .internal = "__as_type" },
    .{ .public = "comp.if", .internal = "__comptimeif" },
    .{ .public = "comp.for", .internal = "__comptimefor" },
    .{ .public = "comp.bit.field", .internal = "__bitfield" },
    .{ .public = "meta.constexpr", .internal = "__constexpr" },
    .{ .public = "comp.constexpr", .internal = "__constexpr" },
    .{ .public = "compiler.constexpr", .internal = "__constexpr" },

    // ── Derive management ──
    .{ .public = "meta.define.derive", .internal = "__define_derive" },
    .{ .public = "comp.define.derive", .internal = "__define_derive" },
    .{ .public = "compiler.define.derive", .internal = "__define_derive" },
    .{ .public = "meta.register.derive", .internal = "__register_derive" },
    .{ .public = "comp.register.derive", .internal = "__register_derive" },
    .{ .public = "compiler.register.derive", .internal = "__register_derive" },
    .{ .public = "meta.register.rewrite", .internal = "__register_rewrite" },
    .{ .public = "comp.register.rewrite", .internal = "__register_rewrite" },
    .{ .public = "compiler.register.rewrite", .internal = "__register_rewrite" },
    .{ .public = "meta.derive.lookup", .internal = "__lookup_derive" },
    .{ .public = "comp.derive.lookup", .internal = "__lookup_derive" },
    .{ .public = "compiler.derive.lookup", .internal = "__lookup_derive" },
    .{ .public = "meta.derive.list", .internal = "__list_derives" },
    .{ .public = "comp.derive.list", .internal = "__list_derives" },
    .{ .public = "compiler.derive.list", .internal = "__list_derives" },
    .{ .public = "meta.derive.eval", .internal = "__eval_derive" },
    .{ .public = "comp.derive.eval", .internal = "__eval_derive" },
    .{ .public = "compiler.derive.eval", .internal = "__eval_derive" },

    // ── Embed ──
    .{ .public = "meta.embed.str", .internal = "__embed_str" },
    .{ .public = "comp.embed.str", .internal = "__embed_str" },
    .{ .public = "compiler.embed.str", .internal = "__embed_str" },
    .{ .public = "meta.embed.file", .internal = "__embed_file" },
    .{ .public = "comp.embed.file", .internal = "__embed_file" },
    .{ .public = "compiler.embed.file", .internal = "__embed_file" },
    // NOTE: meta.embed.json and meta.wasm are module directives, not expressions;
    // they must lower to C globals, not lua_Value tables (AGENTS.md §6).

    // ── Code generation / transform ──
    .{ .public = "meta.foreign", .internal = "__foreign" },
    .{ .public = "comp.foreign", .internal = "__foreign" },
    .{ .public = "compiler.foreign", .internal = "__foreign" },
    .{ .public = "meta.codegen", .internal = "__codegen" },
    .{ .public = "comp.codegen", .internal = "__codegen" },
    .{ .public = "compiler.codegen", .internal = "__codegen" },
    .{ .public = "meta.schema", .internal = "__schema" },
    .{ .public = "comp.schema", .internal = "__schema" },
    .{ .public = "compiler.schema", .internal = "__schema" },
    .{ .public = "meta.ffi", .internal = "__ffi_gen" },
    .{ .public = "comp.ffi", .internal = "__ffi_gen" },
    .{ .public = "compiler.ffi", .internal = "__ffi_gen" },
    .{ .public = "meta.pipeline", .internal = "__pipeline" },
    .{ .public = "comp.pipeline", .internal = "__pipeline" },
    .{ .public = "compiler.pipeline", .internal = "__pipeline" },
    .{ .public = "meta.rewrite", .internal = "__rewrite" },
    .{ .public = "comp.rewrite", .internal = "__rewrite" },
    .{ .public = "compiler.rewrite", .internal = "__rewrite" },
    .{ .public = "meta.rewrite.bundle", .internal = "__rewrite_bundle" },
    .{ .public = "comp.rewrite.bundle", .internal = "__rewrite_bundle" },
    .{ .public = "compiler.rewrite.bundle", .internal = "__rewrite_bundle" },
    .{ .public = "meta.rewrite.describe", .internal = "__rewrite_describe" },
    .{ .public = "comp.rewrite.describe", .internal = "__rewrite_describe" },
    .{ .public = "compiler.rewrite.describe", .internal = "__rewrite_describe" },
    .{ .public = "meta.rewrite.rulecount", .internal = "__rewrite_rulecount" },
    .{ .public = "comp.rewrite.rulecount", .internal = "__rewrite_rulecount" },
    .{ .public = "compiler.rewrite.rulecount", .internal = "__rewrite_rulecount" },
    .{ .public = "meta.sql", .internal = "__sql" },
    .{ .public = "comp.sql", .internal = "__sql" },
    .{ .public = "compiler.sql", .internal = "__sql" },
    .{ .public = "meta.lua", .internal = "__lua_exec" },
    .{ .public = "comp.lua", .internal = "__lua_exec" },
    .{ .public = "compiler.lua", .internal = "__lua_exec" },
    .{ .public = "meta.run", .internal = "__run" },
    .{ .public = "comp.run", .internal = "__run" },
    .{ .public = "compiler.run", .internal = "__run" },
    .{ .public = "meta.c.emit.file", .internal = "__c_emit_file" },
    .{ .public = "comp.c.emit.file", .internal = "__c_emit_file" },
    .{ .public = "compiler.c.emit.file", .internal = "__c_emit_file" },

    // ── Compiler / raw C interface (hierarchical @c.*, @comp.c.*, @meta.c.*, @compiler.c.*) ──
    .{ .public = "c.emit", .internal = "__emit" },
    .{ .public = "c.call", .internal = "__c_call" },
    .{ .public = "c.include", .internal = "__c_include" },
    .{ .public = "c.export", .internal = "__c_export" },
    .{ .public = "c.import", .internal = "__c_import" },
    .{ .public = "c.type", .internal = "__c_type" },
    .{ .public = "c.link", .internal = "__c_link" },
    .{ .public = "emit", .internal = "__emit" },
    .{ .public = "asm", .internal = "__asm" },
    .{ .public = "hot", .internal = "__hot_path" },
    .{ .public = "meta.hint.hot", .internal = "__hot_path" },
    .{ .public = "comp.hint.hot", .internal = "__hot_path" },
    .{ .public = "compiler.hint.hot", .internal = "__hot_path" },
    .{ .public = "meta.c.emit", .internal = "__emit" },
    .{ .public = "meta.c.call", .internal = "__c_call" },
    .{ .public = "meta.c.include", .internal = "__c_include" },
    .{ .public = "meta.c.export", .internal = "__c_export" },
    .{ .public = "meta.c.import", .internal = "__c_import" },
    .{ .public = "meta.c.type", .internal = "__c_type" },
    .{ .public = "meta.c.link", .internal = "__c_link" },
    .{ .public = "meta.asm", .internal = "__asm" },
    .{ .public = "comp.c.emit", .internal = "__emit" },
    .{ .public = "comp.c.call", .internal = "__c_call" },
    .{ .public = "comp.c.include", .internal = "__c_include" },
    .{ .public = "comp.c.export", .internal = "__c_export" },
    .{ .public = "comp.c.import", .internal = "__c_import" },
    .{ .public = "comp.c.type", .internal = "__c_type" },
    .{ .public = "comp.c.link", .internal = "__c_link" },
    .{ .public = "comp.asm", .internal = "__asm" },
    .{ .public = "comp.emit", .internal = "__emit" },
    .{ .public = "compiler.c.emit", .internal = "__emit" },
    .{ .public = "compiler.c.call", .internal = "__c_call" },
    .{ .public = "compiler.c.include", .internal = "__c_include" },
    .{ .public = "compiler.c.export", .internal = "__c_export" },
    .{ .public = "compiler.c.import", .internal = "__c_import" },
    .{ .public = "compiler.c.type", .internal = "__c_type" },
    .{ .public = "compiler.c.link", .internal = "__c_link" },
    .{ .public = "compiler.emit", .internal = "__emit" },
    .{ .public = "compiler.asm", .internal = "__asm" },

    // ── Type construction ──
    .{ .public = "meta.make.type", .internal = "__make_type" },
    .{ .public = "comp.make.type", .internal = "__make_type" },
    .{ .public = "compiler.make.type", .internal = "__make_type" },
    .{ .public = "meta.as.type", .internal = "__as_type" },
    .{ .public = "comp.as.type", .internal = "__as_type" },
    .{ .public = "compiler.as.type", .internal = "__as_type" },
    .{ .public = "meta.bitfield", .internal = "__bitfield" },
    .{ .public = "comp.bitfield", .internal = "__bitfield" },
    .{ .public = "compiler.bitfield", .internal = "__bitfield" },
    .{ .public = "meta.union", .internal = "__union" },
    .{ .public = "comp.union", .internal = "__union" },
    .{ .public = "compiler.union", .internal = "__union" },
    .{ .public = "meta.select", .internal = "__select" },
    .{ .public = "comp.select", .internal = "__select" },
    .{ .public = "compiler.select", .internal = "__select" },

    // ── Bit intrinsics (bare-name + hierarchy aliases for ergonomics) ──
    .{ .public = "meta.bit.popcount", .internal = "__popcount" },
    .{ .public = "comp.bit.popcount", .internal = "__popcount" },
    .{ .public = "compiler.bit.popcount", .internal = "__popcount" },
    .{ .public = "popcount", .internal = "__popcount" },
    .{ .public = "meta.bit.ctz", .internal = "__ctz" },
    .{ .public = "comp.bit.ctz", .internal = "__ctz" },
    .{ .public = "compiler.bit.ctz", .internal = "__ctz" },
    .{ .public = "ctz", .internal = "__ctz" },
    .{ .public = "meta.bit.clz", .internal = "__clz" },
    .{ .public = "comp.bit.clz", .internal = "__clz" },
    .{ .public = "compiler.bit.clz", .internal = "__clz" },
    .{ .public = "clz", .internal = "__clz" },
    .{ .public = "meta.bit.bswap", .internal = "__bswap" },
    .{ .public = "comp.bit.bswap", .internal = "__bswap" },
    .{ .public = "compiler.bit.bswap", .internal = "__bswap" },
    .{ .public = "bswap", .internal = "__bswap" },
    .{ .public = "meta.bit.rotl", .internal = "__rotl" },
    .{ .public = "comp.bit.rotl", .internal = "__rotl" },
    .{ .public = "compiler.bit.rotl", .internal = "__rotl" },
    .{ .public = "rotl", .internal = "__rotl" },
    .{ .public = "meta.bit.rotr", .internal = "__rotr" },
    .{ .public = "comp.bit.rotr", .internal = "__rotr" },
    .{ .public = "compiler.bit.rotr", .internal = "__rotr" },
    .{ .public = "rotr", .internal = "__rotr" },
    .{ .public = "meta.bit.bitcast", .internal = "__bitcast" },
    .{ .public = "comp.bit.bitcast", .internal = "__bitcast" },
    .{ .public = "compiler.bit.bitcast", .internal = "__bitcast" },
    .{ .public = "bitcast", .internal = "__bitcast" },

    // ── Optimization hints (bare-name + hierarchy aliases for ergonomics) ──
    .{ .public = "meta.hint.likely", .internal = "__likely" },
    .{ .public = "comp.hint.likely", .internal = "__likely" },
    .{ .public = "compiler.hint.likely", .internal = "__likely" },
    .{ .public = "likely", .internal = "__likely" },
    .{ .public = "meta.hint.unlikely", .internal = "__unlikely" },
    .{ .public = "comp.hint.unlikely", .internal = "__unlikely" },
    .{ .public = "compiler.hint.unlikely", .internal = "__unlikely" },
    .{ .public = "unlikely", .internal = "__unlikely" },
    .{ .public = "meta.hint.prefetch", .internal = "__prefetch" },
    .{ .public = "comp.hint.prefetch", .internal = "__prefetch" },
    .{ .public = "compiler.hint.prefetch", .internal = "__prefetch" },
    .{ .public = "prefetch", .internal = "__prefetch" },
    .{ .public = "meta.hint.assume", .internal = "__assume" },
    .{ .public = "comp.hint.assume", .internal = "__assume" },
    .{ .public = "compiler.hint.assume", .internal = "__assume" },
    .{ .public = "assume", .internal = "__assume" },
    .{ .public = "meta.hint.unreachable", .internal = "__unreachable" },
    .{ .public = "comp.hint.unreachable", .internal = "__unreachable" },
    .{ .public = "compiler.hint.unreachable", .internal = "__unreachable" },
    .{ .public = "unreachable", .internal = "__unreachable" },
    .{ .public = "meta.hint.trap", .internal = "__trap" },
    .{ .public = "comp.hint.trap", .internal = "__trap" },
    .{ .public = "compiler.hint.trap", .internal = "__trap" },
    .{ .public = "trap", .internal = "__trap" },
    .{ .public = "meta.hint.fence", .internal = "__fence" },
    .{ .public = "comp.hint.fence", .internal = "__fence" },
    .{ .public = "compiler.hint.fence", .internal = "__fence" },
    .{ .public = "fence", .internal = "__fence" },
    .{ .public = "meta.hint.volatile", .internal = "__volatile" },
    .{ .public = "comp.hint.volatile", .internal = "__volatile" },
    .{ .public = "compiler.hint.volatile", .internal = "__volatile" },
    .{ .public = "volatile", .internal = "__volatile" },

    // ── Catalog / self-documentation / agent ──
    .{ .public = "meta.catalog", .internal = "__metacatalog" },
    .{ .public = "comp.catalog", .internal = "__metacatalog" },
    .{ .public = "compiler.catalog", .internal = "__metacatalog" },
    .{ .public = "meta.ladder", .internal = "__metaladder" },
    .{ .public = "comp.ladder", .internal = "__metaladder" },
    .{ .public = "compiler.ladder", .internal = "__metaladder" },
    .{ .public = "meta.agent.catalog", .internal = "__metaagentcatalog" },
    .{ .public = "comp.agent.catalog", .internal = "__metaagentcatalog" },
    .{ .public = "compiler.agent.catalog", .internal = "__metaagentcatalog" },
    .{ .public = "meta.agent.ladder", .internal = "__metaagentladder" },
    .{ .public = "comp.agent.ladder", .internal = "__metaagentladder" },
    .{ .public = "compiler.agent.ladder", .internal = "__metaagentladder" },
    .{ .public = "meta.agent.hooks", .internal = "__metaagenthooks" },
    .{ .public = "comp.agent.hooks", .internal = "__metaagenthooks" },
    .{ .public = "compiler.agent.hooks", .internal = "__metaagenthooks" },
    .{ .public = "meta.agent.dedupe", .internal = "__metaagentdedupe" },
    .{ .public = "comp.agent.dedupe", .internal = "__metaagentdedupe" },
    .{ .public = "compiler.agent.dedupe", .internal = "__metaagentdedupe" },
    .{ .public = "meta.agent.gaps", .internal = "__metaagentgaps" },
    .{ .public = "comp.agent.gaps", .internal = "__metaagentgaps" },
    .{ .public = "compiler.agent.gaps", .internal = "__metaagentgaps" },
    .{ .public = "meta.agent.grammar", .internal = "__metaagentgrammar" },
    .{ .public = "comp.agent.grammar", .internal = "__metaagentgrammar" },
    .{ .public = "compiler.agent.grammar", .internal = "__metaagentgrammar" },
    .{ .public = "meta.str.contains", .internal = "__strcontains" },
    .{ .public = "comp.str.contains", .internal = "__strcontains" },
    .{ .public = "compiler.str.contains", .internal = "__strcontains" },
    .{ .public = "meta.str.starts.with", .internal = "__strstartswith" },
    .{ .public = "comp.str.starts.with", .internal = "__strstartswith" },
    .{ .public = "compiler.str.starts.with", .internal = "__strstartswith" },
    .{ .public = "meta.str.ends.with", .internal = "__strendswith" },
    .{ .public = "comp.str.ends.with", .internal = "__strendswith" },
    .{ .public = "compiler.str.ends.with", .internal = "__strendswith" },
    .{ .public = "meta.str.countlines", .internal = "__strcountlines" },
    .{ .public = "comp.str.countlines", .internal = "__strcountlines" },
    .{ .public = "compiler.str.countlines", .internal = "__strcountlines" },
    .{ .public = "meta.str.splitcount", .internal = "__strsplitcount" },
    .{ .public = "comp.str.splitcount", .internal = "__strsplitcount" },
    .{ .public = "compiler.str.splitcount", .internal = "__strsplitcount" },
    .{ .public = "meta.str.len", .internal = "__strcomptelen" },
    .{ .public = "comp.str.len", .internal = "__strcomptelen" },
    .{ .public = "compiler.str.len", .internal = "__strcomptelen" },
    .{ .public = "meta.str.eq", .internal = "__streq" },
    .{ .public = "comp.str.eq", .internal = "__streq" },
    .{ .public = "compiler.str.eq", .internal = "__streq" },
    .{ .public = "meta.str.join", .internal = "__strjoin" },
    .{ .public = "comp.str.join", .internal = "__strjoin" },
    .{ .public = "compiler.str.join", .internal = "__strjoin" },

    // ── Generative combinators (break the linear ceiling) ──
    // @meta.grammar: EBNF grammar -> O(b^d) code fragments from minimal spec
    .{ .public = "meta.grammar", .internal = "__metagrammar" },
    .{ .public = "comp.grammar", .internal = "__metagrammar" },
    .{ .public = "compiler.grammar", .internal = "__metagrammar" },
    // @meta.weave: cross-module type-driven code injection (1 type ^ N weaves ^ M derives)
    .{ .public = "meta.weave", .internal = "__metaweave" },
    .{ .public = "comp.weave", .internal = "__metaweave" },
    .{ .public = "compiler.weave", .internal = "__metaweave" },
    // @meta.template: parametric code templates that expand at compile time
    .{ .public = "meta.template", .internal = "__metatemplate" },
    .{ .public = "comp.template", .internal = "__metatemplate" },
    .{ .public = "compiler.template", .internal = "__metatemplate" },
    // @meta.generate: LLM-free generative code synthesis from constraints
    .{ .public = "meta.generate", .internal = "__metagenerate" },
    .{ .public = "comp.generate", .internal = "__metagenerate" },
    .{ .public = "compiler.generate", .internal = "__metagenerate" },
    // @meta.scheme: declarative program scheme -> full implementation
    .{ .public = "meta.scheme", .internal = "__metascheme" },
    .{ .public = "comp.scheme", .internal = "__metascheme" },
    .{ .public = "compiler.scheme", .internal = "__metascheme" },
    .{ .public = "meta.scheme.clauses", .internal = "__metaschemeclauses" },
    .{ .public = "comp.scheme.clauses", .internal = "__metaschemeclauses" },
    .{ .public = "compiler.scheme.clauses", .internal = "__metaschemeclauses" },
    // @meta.fixpoint: unbounded iterative combinator — O(1) input -> O(max_iter) output
    .{ .public = "meta.fixpoint", .internal = "__comptimefixpoint" },
    .{ .public = "comp.fixpoint", .internal = "__comptimefixpoint" },
    .{ .public = "compiler.fixpoint", .internal = "__comptimefixpoint" },
    // @meta.fanout: tree-shaped generative expansion — O(branch^depth) output from O(1) input
    .{ .public = "meta.fanout", .internal = "__comptimefanout" },
    .{ .public = "comp.fanout", .internal = "__comptimefanout" },
    .{ .public = "compiler.fanout", .internal = "__comptimefanout" },

    // ── Bare @ aliases for ergonomic exponential metaprogramming ──
    // These are short, memorable names with just @ prefix, like @popcount
    .{ .public = "map", .internal = "__comptimemap" },
    .{ .public = "expand", .internal = "__metaexpand" },
    .{ .public = "pow", .internal = "__metaexpand" },
    .{ .public = "ceiling", .internal = "__metaceiling" },
    .{ .public = "omni", .internal = "__metaomni" },
    .{ .public = "stack", .internal = "__metaomni" },
    .{ .public = "burst", .internal = "__metaburst" },
    .{ .public = "tensor", .internal = "__comptimetensor" },
    .{ .public = "transcend", .internal = "__metatranscend" },
    .{ .public = "infinity", .internal = "__metainfinity" },
    .{ .public = "hyper", .internal = "__metahyper" },
    .{ .public = "fixpoint", .internal = "__comptimefixpoint" },
    .{ .public = "fanout", .internal = "__comptimefanout" },
};

// ─────────────────────────────────────────────────────────────────────────────
// Module-level directives: `@meta.*` paths that normalize to canonical names
// ─────────────────────────────────────────────────────────────────────────────

const directives = [_]DirectiveEntry{
    .{ .public = "meta.pipeline", .canonical = "pipeline" },
    .{ .public = "comp.pipeline", .canonical = "pipeline" },
    .{ .public = "compiler.pipeline", .canonical = "pipeline" },
    .{ .public = "meta.rewrite", .canonical = "rewrite" },
    .{ .public = "comp.rewrite", .canonical = "rewrite" },
    .{ .public = "compiler.rewrite", .canonical = "rewrite" },
    .{ .public = "meta.rewrite.bundle", .canonical = "rewrite.bundle" },
    .{ .public = "comp.rewrite.bundle", .canonical = "rewrite.bundle" },
    .{ .public = "compiler.rewrite.bundle", .canonical = "rewrite.bundle" },
    .{ .public = "meta.foreign", .canonical = "foreign" },
    .{ .public = "comp.foreign", .canonical = "foreign" },
    .{ .public = "compiler.foreign", .canonical = "foreign" },
    .{ .public = "meta.codegen", .canonical = "codegen" },
    .{ .public = "comp.codegen", .canonical = "codegen" },
    .{ .public = "compiler.codegen", .canonical = "codegen" },
    .{ .public = "meta.embed.json", .canonical = "embed.json" },
    .{ .public = "comp.embed.json", .canonical = "embed.json" },
    .{ .public = "compiler.embed.json", .canonical = "embed.json" },
    .{ .public = "meta.embed.wasm", .canonical = "wasm" },
    .{ .public = "comp.embed.wasm", .canonical = "wasm" },
    .{ .public = "compiler.embed.wasm", .canonical = "wasm" },
    .{ .public = "meta.wasm", .canonical = "wasm" },
    .{ .public = "comp.wasm", .canonical = "wasm" },
    .{ .public = "compiler.wasm", .canonical = "wasm" },
    .{ .public = "meta.sql", .canonical = "sql" },
    .{ .public = "comp.sql", .canonical = "sql" },
    .{ .public = "compiler.sql", .canonical = "sql" },
    .{ .public = "meta.lua", .canonical = "lua" },
    .{ .public = "comp.lua", .canonical = "lua" },
    .{ .public = "compiler.lua", .canonical = "lua" },
    .{ .public = "meta.ffi", .canonical = "ffi.gen" },
    .{ .public = "comp.ffi", .canonical = "ffi.gen" },
    .{ .public = "compiler.ffi", .canonical = "ffi.gen" },
    .{ .public = "meta.define.derive", .canonical = "define.derive" },
    .{ .public = "comp.define.derive", .canonical = "define.derive" },
    .{ .public = "compiler.define.derive", .canonical = "define.derive" },
    .{ .public = "meta.define.bundle", .canonical = "define.derive.bundle" },
    .{ .public = "comp.define.bundle", .canonical = "define.derive.bundle" },
    .{ .public = "compiler.define.bundle", .canonical = "define.derive.bundle" },
    .{ .public = "meta.derive.all", .canonical = "derive.all" },
    .{ .public = "comp.derive.all", .canonical = "derive.all" },
    .{ .public = "compiler.derive.all", .canonical = "derive.all" },
    .{ .public = "meta.emit.derive", .canonical = "emit.derive" },
    .{ .public = "comp.emit.derive", .canonical = "emit.derive" },
    .{ .public = "compiler.emit.derive", .canonical = "emit.derive" },
    .{ .public = "meta.emit.omni", .canonical = "emit.omni" },
    .{ .public = "comp.emit.omni", .canonical = "emit.omni" },
    .{ .public = "compiler.emit.omni", .canonical = "emit.omni" },
    .{ .public = "meta.burst", .canonical = "burst" },
    .{ .public = "comp.burst", .canonical = "burst" },
    .{ .public = "compiler.burst", .canonical = "burst" },
    .{ .public = "meta.transcend", .canonical = "transcend" },
    .{ .public = "comp.transcend", .canonical = "transcend" },
    .{ .public = "compiler.transcend", .canonical = "transcend" },
    .{ .public = "meta.infinity", .canonical = "infinity" },
    .{ .public = "comp.infinity", .canonical = "infinity" },
    .{ .public = "compiler.infinity", .canonical = "infinity" },
    .{ .public = "meta.hyper", .canonical = "hyper" },
    .{ .public = "comp.hyper", .canonical = "hyper" },
    .{ .public = "compiler.hyper", .canonical = "hyper" },
    .{ .public = "meta.compile.native", .canonical = "native" },
    .{ .public = "comp.compile.native", .canonical = "native" },
    .{ .public = "compiler.compile.native", .canonical = "native" },
    .{ .public = "native", .canonical = "native" },
    .{ .public = "meta.compile.cached", .canonical = "cached" },
    .{ .public = "comp.compile.cached", .canonical = "cached" },
    .{ .public = "compiler.compile.cached", .canonical = "cached" },
    .{ .public = "meta.compile.thread", .canonical = "compile.thread" },
    .{ .public = "comp.compile.thread", .canonical = "compile.thread" },
    .{ .public = "compiler.compile.thread", .canonical = "compile.thread" },
    .{ .public = "meta.compile.device", .canonical = "device" },
    .{ .public = "comp.compile.device", .canonical = "device" },
    .{ .public = "compiler.compile.device", .canonical = "device" },
    .{ .public = "meta.compile.autodiff", .canonical = "autodiff" },
    .{ .public = "comp.compile.autodiff", .canonical = "autodiff" },
    .{ .public = "compiler.compile.autodiff", .canonical = "autodiff" },
    .{ .public = "meta.compile.differentiable", .canonical = "differentiable" },
    .{ .public = "comp.compile.differentiable", .canonical = "differentiable" },
    .{ .public = "compiler.compile.differentiable", .canonical = "differentiable" },
    .{ .public = "meta.compile.profile", .canonical = "profile" },
    .{ .public = "comp.compile.profile", .canonical = "profile" },
    .{ .public = "compiler.compile.profile", .canonical = "profile" },
    .{ .public = "meta.compile.unroll", .canonical = "unroll" },
    .{ .public = "comp.compile.unroll", .canonical = "unroll" },
    .{ .public = "compiler.compile.unroll", .canonical = "unroll" },
    .{ .public = "meta.compile.modify", .canonical = "modify" },
    .{ .public = "comp.compile.modify", .canonical = "modify" },
    .{ .public = "compiler.compile.modify", .canonical = "modify" },
    .{ .public = "meta.compile.only", .canonical = "compile.only" },
    .{ .public = "comp.compile.only", .canonical = "compile.only" },
    .{ .public = "compiler.compile.only", .canonical = "compile.only" },
    .{ .public = "meta.emit.file", .canonical = "c.emit.file" },
    .{ .public = "comp.emit.file", .canonical = "c.emit.file" },
    .{ .public = "compiler.emit.file", .canonical = "c.emit.file" },
    // Generative combinators as module-level directives
    .{ .public = "meta.grammar", .canonical = "grammar" },
    .{ .public = "comp.grammar", .canonical = "grammar" },
    .{ .public = "compiler.grammar", .canonical = "grammar" },
    .{ .public = "meta.weave", .canonical = "weave" },
    .{ .public = "comp.weave", .canonical = "weave" },
    .{ .public = "compiler.weave", .canonical = "weave" },
    .{ .public = "meta.template", .canonical = "template" },
    .{ .public = "comp.template", .canonical = "template" },
    .{ .public = "compiler.template", .canonical = "template" },
    .{ .public = "meta.scheme", .canonical = "scheme" },
    .{ .public = "comp.scheme", .canonical = "scheme" },
    .{ .public = "compiler.scheme", .canonical = "scheme" },
};

/// Map `@`-prefixed qualified name to internal intrinsic (`__comptimemap`, etc.).
/// Accepts `comp.*`, `compiler.*`, and `meta.*` prefixes interchangeably.
pub fn resolveBuiltin(qualified: []const u8) ?[]const u8 {
    for (builtins) |entry| {
        if (std.mem.eql(u8, qualified, entry.public)) return entry.internal;
    }
    return null;
}

/// Normalize module-level directive names (`meta.pipeline` -> `pipeline`).
pub fn normalizeDirective(name: []const u8) []const u8 {
    for (directives) |entry| {
        if (std.mem.eql(u8, name, entry.public)) return entry.canonical;
    }
    return name;
}

pub fn directiveMatches(name: []const u8, canonical: []const u8) bool {
    return std.mem.eql(u8, normalizeDirective(name), canonical);
}

pub fn isModuleDirective(name: []const u8) bool {
    // Check the directives array (handles meta.*, comp.*, compiler.* prefixed names)
    for (directives) |entry| {
        if (std.mem.eql(u8, name, entry.public)) return true;
    }
    // Check builtins for bare @ aliases (e.g., @map, @expand, @popcount)
    for (builtins) |entry| {
        if (std.mem.eql(u8, name, entry.public)) return true;
    }
    // Bare-name aliases for backward compatibility — users expect @pipeline,
    // @foreign, etc. to work without the @comp.* prefix.
    const bare_aliases = [_][]const u8{
        "pipeline",
        "rewrite",
        "foreign",
        "codegen",
        "wasm",
        "sql",
        "lua",
        // Exponential combinator bare aliases
        "map",
        "expand",
        "pow",
        "ceiling",
        "omni",
        "stack",
        "burst",
        "tensor",
        "transcend",
        "infinity",
        "hyper",
        "fixpoint",
        "fanout",
    };
    for (bare_aliases) |entry| {
        if (std.mem.eql(u8, name, entry)) return true;
    }
    return false;
}

/// True for `@meta.*` module directives.
pub fn isMetaModuleDirective(name: []const u8) bool {
    return isModuleDirective(name);
}

/// True when an attribute prefix refers to a module-level @meta directive (not expression builtins).
pub fn isMetaAttribute(name: []const u8) bool {
    // Expression combinators are NOT declaration attributes — they are
    // expression-position calls that should be parsed as expr_stmt, not
    // attributed declarations. G-059: without this exclusion, @comp.match(...)
    // inside a callback body is misclassified as a declaration attribute.
    const expression_combinators = [_][]const u8{
        "comp.match", "meta.match", "compiler.match",
        "comp.tabulate", "meta.tabulate", "compiler.tabulate",
        "comp.interpolate", "meta.interpolate", "compiler.interpolate",
        "comp.zip", "meta.zip", "compiler.zip",
        "comp.each", "meta.each", "compiler.each",
        "comp.chain", "meta.chain", "compiler.chain",
        "comp.map", "meta.map", "compiler.map",
        "comp.sweep", "meta.sweep", "compiler.sweep",
        "comp.grammar", "meta.grammar", "compiler.grammar",
        "comp.template", "meta.template", "compiler.template",
        "comp.generate", "meta.generate", "compiler.generate",
        "comp.scheme", "meta.scheme", "compiler.scheme",
        "comp.scheme.clauses", "meta.scheme.clauses", "compiler.scheme.clauses",
        "comp.weave", "meta.weave", "compiler.weave",
        "comp.product", "meta.product", "compiler.product",
        "comp.power", "meta.power", "compiler.power",
        "comp.powerset", "meta.powerset", "compiler.powerset",
        "comp.permute", "meta.permute", "compiler.permute",
        "comp.choose", "meta.choose", "compiler.choose",
        "comp.fixpoint", "meta.fixpoint", "compiler.fixpoint",
    };
    for (expression_combinators) |expr_name| {
        if (std.mem.eql(u8, name, expr_name)) return false;
    }
    return isModuleDirective(name);
}

/// Normalize type-level derive attributes to canonical names.
/// Accepts `comp.*`, `compiler.*`, `meta.*` prefixes interchangeably.
pub fn normalizeTypeAttribute(name: []const u8) []const u8 {
    // Strip prefix to get canonical dotted form (comp.* is primary)
    const stripped = if (std.mem.startsWith(u8, name, "compiler."))
        name["compiler.".len..]
    else if (std.mem.startsWith(u8, name, "comp."))
        name["comp.".len..]
    else if (std.mem.startsWith(u8, name, "meta."))
        name["meta.".len..]
    else
        name;
    if (std.mem.eql(u8, stripped, "derive.bundle")) return "derive.bundle";
    if (std.mem.eql(u8, stripped, "define.bundle")) return "define.derive.bundle";
    if (std.mem.eql(u8, stripped, "rewrite.bundle")) return "rewrite.bundle";
    return stripped;
}

/// Normalize function/type compiler hint attributes under @comp.compile.* / @meta.compile.*
/// Accepts `comp.*`, `compiler.*`, `meta.*` prefixes interchangeably.
/// Canonical prefix is `comp.*` — returns bare dotted form `compile.only`, `inline`, etc.
pub fn normalizeCompileAttribute(name: []const u8) []const u8 {
    // Strip prefix to get canonical dotted form
    const stripped = if (std.mem.startsWith(u8, name, "compiler."))
        name["compiler.".len..]
    else if (std.mem.startsWith(u8, name, "comp."))
        name["comp.".len..]
    else if (std.mem.startsWith(u8, name, "meta."))
        name["meta.".len..]
    else
        name;
    if (std.mem.eql(u8, stripped, "compile.cached")) return "cached";
    if (std.mem.eql(u8, stripped, "compile.thread")) return "compile.thread";
    if (std.mem.eql(u8, stripped, "compile.device")) return "device";
    if (std.mem.eql(u8, stripped, "compile.autodiff")) return "autodiff";
    if (std.mem.eql(u8, stripped, "compile.differentiable")) return "differentiable";
    if (std.mem.eql(u8, stripped, "compile.profile")) return "profile";
    if (std.mem.eql(u8, stripped, "compile.unroll")) return "unroll";
    if (std.mem.eql(u8, stripped, "compile.modify")) return "modify";
    if (std.mem.eql(u8, stripped, "compile.only")) return "compile.only";
    if (std.mem.eql(u8, stripped, "compile.inline")) return "inline";
    if (std.mem.eql(u8, stripped, "compile.noinline")) return "noinline";
    if (std.mem.eql(u8, stripped, "compile.hot")) return "hot";
    if (std.mem.eql(u8, stripped, "compile.cold")) return "cold";
    if (std.mem.eql(u8, stripped, "compile.raw")) return "raw";
    if (std.mem.eql(u8, stripped, "compile.packed")) return "packed";
    return stripped;
}

/// True when every segment of a `@meta.*` path is a valid identifier (not a Duo keyword).
pub fn catalogPathParseable(path: []const u8) bool {
    const rest = if (std.mem.startsWith(u8, path, "comp."))
        path["comp.".len..]
    else if (std.mem.startsWith(u8, path, "meta."))
        path["meta.".len..]
    else if (std.mem.startsWith(u8, path, "compiler."))
        path["compiler.".len..]
    else
        return false;
    var tail = rest;
    while (tail.len > 0) {
        const dot = std.mem.indexOfScalar(u8, tail, '.') orelse tail.len;
        const seg = tail[0..dot];
        if (seg.len == 0) return false;
        if (isKeywordSegment(seg)) return false;
        if (dot >= tail.len) break;
        tail = tail[dot + 1 ..];
    }
    return true;
}

fn isKeywordSegment(seg: []const u8) bool {
    const keywords = [_][]const u8{
        "if",      "else",     "elseif",   "then",     "for",    "while",  "do",
        "end",     "fun",      "function", "return",   "local",  "global", "in",
        "concept", "comptime", "match",    "enum",     "async",  "await",  "try",
        "catch",   "defer",    "break",    "continue", "repeat", "until",  "and",
        "or",      "not",      "nil",      "true",     "false",  "const",  "alias",
        "private", "extends",  "macro",    "by",       "let",    "goto",
    };
    for (keywords) |kw| {
        if (std.mem.eql(u8, seg, kw)) return true;
    }
    return false;
}

/// Category for `@comp.catalog("category")` / `@meta.catalog("category")` filtering.
pub fn catalogCategory(path: []const u8) []const u8 {
    const combinators = [_][]const u8{
        "meta.map",            "meta.sweep",           "meta.derive",
        "meta.expand",         "meta.pow",             "meta.ceiling",
        "meta.omni",           "meta.stack",           "meta.burst",
        "meta.product",        "meta.derive.product",  "meta.tensor",
        "meta.derive.tensor",  "meta.nfold",           "meta.derive.nfold",
        "meta.transcend",      "meta.infinity",        "meta.hyper",
        "meta.tower",          "meta.power",           "meta.powerset",
        "meta.derive.power",   "meta.derive.powerset", "meta.choose",
        "meta.derive.choose",  "meta.permute",         "meta.derive.permute",
        "meta.each",
        // comp.* aliases (canonical lookup after prefix normalization)
                  "comp.map",             "comp.sweep",
        "comp.derive",         "comp.expand",          "comp.pow",
        "comp.ceiling",        "comp.omni",            "comp.stack",
        "comp.burst",          "comp.product",         "comp.derive.product",
        "comp.tensor",         "comp.derive.tensor",   "comp.nfold",
        "comp.derive.nfold",   "comp.transcend",       "comp.infinity",
        "comp.hyper",          "comp.tower",           "comp.power",
        "comp.powerset",       "comp.derive.power",    "comp.derive.powerset",
        "comp.choose",         "comp.derive.choose",   "comp.permute",
        "comp.derive.permute",
        "comp.each",           "comp.chain",           "comp.match",
        "comp.tabulate",
        "comp.interpolate",
        "comp.zip",
    };
    for (combinators) |c| {
        if (std.mem.eql(u8, path, c)) return "combinators";
    }
    if (std.mem.startsWith(u8, path, "meta.emit.") or
        std.mem.startsWith(u8, path, "comp.emit."))
        return "emit";
    if (std.mem.eql(u8, path, "meta.derive.all") or
        std.mem.eql(u8, path, "meta.burst") or
        std.mem.eql(u8, path, "meta.transcend") or
        std.mem.eql(u8, path, "meta.infinity") or
        std.mem.eql(u8, path, "meta.hyper") or
        std.mem.startsWith(u8, path, "meta.define.") or
        std.mem.eql(u8, path, "comp.derive.all") or
        std.mem.eql(u8, path, "comp.burst") or
        std.mem.eql(u8, path, "comp.transcend") or
        std.mem.eql(u8, path, "comp.infinity") or
        std.mem.eql(u8, path, "comp.hyper") or
        std.mem.startsWith(u8, path, "comp.define."))
        return "define";
    if (std.mem.startsWith(u8, path, "meta.compile.") or
        std.mem.startsWith(u8, path, "comp.compile."))
        return "compile";
    if (std.mem.indexOf(u8, path, ".concepts.") != null or
        std.mem.startsWith(u8, path, "meta.type.") or
        std.mem.startsWith(u8, path, "comp.type.") or
        std.mem.startsWith(u8, path, "meta.types") or
        std.mem.startsWith(u8, path, "comp.types") or
        std.mem.startsWith(u8, path, "meta.has.") or
        std.mem.startsWith(u8, path, "comp.has.") or
        std.mem.startsWith(u8, path, "meta.field.") or
        std.mem.startsWith(u8, path, "comp.field.") or
        std.mem.eql(u8, path, "meta.fields") or
        std.mem.eql(u8, path, "comp.fields") or
        std.mem.eql(u8, path, "meta.methods") or
        std.mem.eql(u8, path, "comp.methods") or
        std.mem.eql(u8, path, "meta.variants") or
        std.mem.eql(u8, path, "comp.variants") or
        std.mem.eql(u8, path, "meta.type.info") or
        std.mem.eql(u8, path, "meta.type.of") or
        std.mem.eql(u8, path, "meta.satisfies") or
        std.mem.eql(u8, path, "comp.satisfies") or
        std.mem.eql(u8, path, "meta.catalog") or
        std.mem.eql(u8, path, "comp.catalog") or
        std.mem.eql(u8, path, "meta.ladder") or
        std.mem.eql(u8, path, "comp.ladder") or
        std.mem.startsWith(u8, path, "meta.agent.") or
        std.mem.startsWith(u8, path, "comp.agent.") or
        std.mem.startsWith(u8, path, "compiler.agent.") or
        std.mem.eql(u8, path, "meta.str.contains") or
        std.mem.eql(u8, path, "meta.str.starts.with") or
        std.mem.eql(u8, path, "meta.str.ends.with") or
        std.mem.eql(u8, path, "meta.str.countlines") or
        std.mem.eql(u8, path, "meta.str.splitcount") or
        std.mem.eql(u8, path, "comp.str.splitcount") or
        std.mem.eql(u8, path, "meta.str.len") or
        std.mem.eql(u8, path, "comp.str.len") or
        std.mem.eql(u8, path, "meta.str.eq") or
        std.mem.eql(u8, path, "comp.str.eq") or
        std.mem.eql(u8, path, "meta.str.join") or
        std.mem.eql(u8, path, "comp.str.join") or
        std.mem.eql(u8, path, "meta.concepts.count") or
        std.mem.eql(u8, path, "meta.rewrite.describe") or
        std.mem.eql(u8, path, "comp.rewrite.describe") or
        std.mem.eql(u8, path, "meta.rewrite.rulecount") or
        std.mem.eql(u8, path, "comp.rewrite.rulecount") or
        std.mem.eql(u8, path, "meta.diff") or
        std.mem.eql(u8, path, "comp.diff"))
        return "introspection";
    if (std.mem.eql(u8, path, "meta.pipeline") or
        std.mem.eql(u8, path, "comp.pipeline") or
        std.mem.eql(u8, path, "meta.rewrite") or
        std.mem.eql(u8, path, "comp.rewrite") or
        std.mem.startsWith(u8, path, "meta.rewrite.") or
        std.mem.startsWith(u8, path, "comp.rewrite.") or
        std.mem.eql(u8, path, "meta.foreign") or
        std.mem.eql(u8, path, "comp.foreign") or
        std.mem.eql(u8, path, "meta.codegen") or
        std.mem.eql(u8, path, "comp.codegen") or
        std.mem.eql(u8, path, "meta.ffi") or
        std.mem.eql(u8, path, "comp.ffi"))
        return "transform";
    return "other";
}

/// Prefer `comp.*` > `meta.*` > `compiler.*` when deduping catalog aliases.
fn catalogDisplayPriority(path: []const u8) u8 {
    if (std.mem.startsWith(u8, path, "comp.")) return 0;
    if (std.mem.startsWith(u8, path, "meta.")) return 1;
    if (std.mem.startsWith(u8, path, "compiler.")) return 2;
    return 3;
}

/// Newline-separated list of canonical parseable `@comp.*` paths, optionally filtered by category.
/// Aliases (`@meta.*`, `@compiler.*`) dedupe by internal handler — one row per construct.
/// Pass category `"grouped"` for section headers (`# combinators`, etc.) over all categories.
pub fn formatCatalogFiltered(alloc: std.mem.Allocator, category: ?[]const u8) ![]const u8 {
    if (category) |c| {
        if (std.mem.eql(u8, c, "grouped")) return formatCatalogGrouped(alloc);
    }
    return formatCatalogSection(alloc, category);
}

fn formatCatalogSection(alloc: std.mem.Allocator, category: ?[]const u8) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);
    var order: std.ArrayListUnmanaged([]const u8) = .empty;
    defer order.deinit(alloc);
    var best_public: std.StringHashMapUnmanaged([]const u8) = .empty;
    defer best_public.deinit(alloc);

    const filter = if (category) |c| blk: {
        if (std.mem.eql(u8, c, "all")) break :blk null;
        break :blk c;
    } else null;

    const ingest = struct {
        fn add(
            a: std.mem.Allocator,
            key: []const u8,
            public: []const u8,
            ord: *std.ArrayListUnmanaged([]const u8),
            best: *std.StringHashMapUnmanaged([]const u8),
        ) !void {
            if (best.get(key)) |prev| {
                if (catalogDisplayPriority(public) < catalogDisplayPriority(prev)) {
                    try best.put(a, key, public);
                }
            } else {
                try best.put(a, key, public);
                try ord.append(a, key);
            }
        }
    };

    for (builtins) |entry| {
        if (!catalogPathParseable(entry.public)) continue;
        if (filter) |cat| {
            if (!std.mem.eql(u8, catalogCategory(entry.public), cat)) continue;
        }
        try ingest.add(alloc, entry.internal, entry.public, &order, &best_public);
    }
    for (directives) |entry| {
        if (!catalogPathParseable(entry.public)) continue;
        if (filter) |cat| {
            if (!std.mem.eql(u8, catalogCategory(entry.public), cat)) continue;
        }
        try ingest.add(alloc, entry.canonical, entry.public, &order, &best_public);
    }

    for (order.items) |key| {
        const public = best_public.get(key) orelse continue;
        if (buf.items.len > 0) try buf.append(alloc, '\n');
        try buf.appendSlice(alloc, public);
    }
    return try buf.toOwnedSlice(alloc);
}

/// Newline-separated list of all canonical parseable `@comp.*` paths (deduped).
pub fn formatCatalog(alloc: std.mem.Allocator) ![]const u8 {
    return formatCatalogFiltered(alloc, null);
}

const catalog_section_order = [_][]const u8{
    "combinators", "define", "emit", "introspection", "transform", "compile", "other",
};

/// All parseable `@meta.*` paths grouped by category with `# category` section headers.
pub fn formatCatalogGrouped(alloc: std.mem.Allocator) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    for (catalog_section_order) |cat| {
        const section = try formatCatalogSection(alloc, cat);
        defer alloc.free(section);
        if (section.len == 0) continue;
        if (buf.items.len > 0) try buf.append(alloc, '\n');
        try buf.appendSlice(alloc, "# ");
        try buf.appendSlice(alloc, cat);
        try buf.append(alloc, '\n');
        try buf.appendSlice(alloc, section);
    }
    return try buf.toOwnedSlice(alloc);
}

/// Scaling ladder reference for agents (mirrors `std.meta.hierarchy.scaling_ladder`).
pub fn scalingLadderText() []const u8 {
    return
    \\map:O(n)
    \\derive:O(n^f)
    \\product:O(n2)
    \\derive.product:O(n2^f)
    \\tensor:O(n3)
    \\derive.tensor:O(n3^f)
    \\nfold:O(n^k)
    \\derive.nfold:O(n^k^f)
    \\ceiling:O(n^f)+O(n2^f)
    \\omni:ceiling+sweep
    \\burst:derive.all+product
    \\transcend:burst+tensor
    \\infinity:transcend+nfold(4)
    \\hyper:transcend+nfold(5)
    \\tower:O(n^k)^f (k≤16)
    \\power:O(2^n)
    \\derive.power:O(2^n^f)
    \\choose:O(n choose k)
    \\derive.choose:O(n choose k^f)
    \\permute:O(n!)
    \\derive.permute:O(n!^f)
    \\each:composition glue — chains any two combinators (closes the algebra)
    \\chain:alias of each — split combinator output into fragments, re-expand each
    \\template:O(n) parametric instance axis
    \\generate:O(n) comma-list or O(ops^types) constraint cartesian -> template
    \\scheme:O(decls) declarative type/fn units -> native C fragments
    \\scheme.clauses:O(clauses) named clause list -> native C fragments
    \\grammar:O(b^d) EBNF expansion
    \\weave:O(N^M) cross-module concept sweep
    ;
}

/// Agent-oriented hook index (coordination + std.agent + key combinators).
pub fn agentHooksText() []const u8 {
    return
    \\docs/AGENT_CANONICAL.md — single router for all agents/CLIs (read first)
    \\docs/AGENT_COORDINATION.md — coordination buffer (claims, build tiers)
    \\@comp.agent.catalog / @meta.agent.catalog — grouped @comp.* paths (deduped)
    \\@comp.agent.ladder — scaling ladder + workflow hints
    \\@comp.agent.hooks — this index
    \\@comp.agent.dedupe — duplication-prevention checklist for parallel agents
    \\@comp.agent.gaps — expressiveness/perf/native gaps index -> docs/AGENT_COORDINATION.md#cross-agent-gap-buffer
    \\@comp.agent.grammar — surface-syntax index -> docs/GRAMMAR_SPEC.md
    \\docs/DIRECTIVE_HIERARCHY.md — dotted @comp.* paths (no underscores)
    \\docs/AGENT_COORDINATION.md#cross-agent-gap-buffer — canonical findings ledger (MCP duo_agent_gaps_*)
    \\std.agent — recipes, build_gates, native_policy, multiplier_for, smoke_targets
    \\std.script — Duo-first scripting; prefer over bash/python
    \\combinators: map->derive->product->tensor->nfold->power->permute
    \\module stack: burst->transcend->infinity->hyper
    \\native: no lua_Value; C is intermediate -> machine code ceiling
    ;
}

/// Duplication-prevention protocol for 5+ parallel agents.
pub fn agentDedupeText() []const u8 {
    return
    \\1. Read docs/AGENT_COORDINATION.md + claim area before editing shared surfaces
    \\2. Search codebase/MCP catalog before adding new @comp.* / std.* modules
    \\3. Extend existing hooks (std.agent, meta_module) — do not fork parallel copies
    \\4. One agent owns codegen.zig OR sema.zig at a time; release when done
    \\5. Check Session log + Activity log — skip work already marked complete
    \\6. Prefer @comp.derive / @comp.burst over hand-written boilerplate (exponential, not duplicate)
    \\7. MCP: duo_coordination_update(claim) before edit; duo_meta_catalog before new directives
    \\8. Never run tier-3 bench in parallel; dedupe build runs via coordination buffer
    ;
}

/// Cross-session expressiveness / performance / native-lowering gaps index.
pub fn agentGapsText() []const u8 {
    return
    \\docs/AGENT_COORDINATION.md#cross-agent-gap-buffer — canonical gaps ledger (read + append at session start)
    \\MCP: duo_agent_gaps_read / duo_agent_gaps_update (duo-bench MCP)
    \\Categories: perf | native | meta | script | agent | backend
    \\Before new feature: search Cross-Agent Gap Buffer + @comp.catalog + claim coordination row
    \\P0 native: eliminate lua_Value on typed/comptime paths (grep codegen.zig)
    \\P0 perf: zig build bench after codegen; zero regressions ever
    \\P1 meta: prefer @comp.burst/derive.all over linear hand-written copies
    \\P2 backend: Duo-native asm/object emission beyond C; no LLVM IR dependency
    \\Close gaps: move Open->Closed, append Findings log, update performance.md if bench-affecting
    ;
}

/// Helper function to compute the exponential complexity class for a combinator path.
/// Returns a tuple (base_complexity, has_derive_field, is_module_directive).
pub const ComplexityInfo = struct {
    complexity: []const u8,      // e.g., "O(n)", "O(n2)", "O(n^k)", "O(2^n)", "O(n!)"
    has_derive_multiplier: bool, // true if there's a derive^fields component (f)
    is_module_directive: bool,      // true if it emits code (burst, transcend, etc.)
    base_combinator: []const u8,    // e.g., "map", "product", "tensor", "nfold"
};

/// Get complexity information for a @comp.* path to help agents understand scale.
pub fn combinatorComplexity(path: []const u8) ?ComplexityInfo {
    // Strip prefix to get the core path
    const core = if (std.mem.startsWith(u8, path, "comp."))
        path["comp.".len..]
    else if (std.mem.startsWith(u8, path, "meta."))
        path["meta.".len..]
    else if (std.mem.startsWith(u8, path, "compiler."))
        path["compiler.".len..]
    else
        return null;

    // Module-level directives that emit code
    const module_directives = [_]struct { name: []const u8, complexity: []const u8, base: []const u8 }{
        .{ .name = "burst", .complexity = "O(n^2xf)", .base = "burst" },
        .{ .name = "transcend", .complexity = "O(n^3xf)", .base = "transcend" },
        .{ .name = "infinity", .complexity = "O(n^4xf)", .base = "infinity" },
        .{ .name = "hyper", .complexity = "O(n^5xf)", .base = "hyper" },
        .{ .name = "tower", .complexity = "O(n^kxf)", .base = "tower" },
        .{ .name = "grammar", .complexity = "O(b^d)", .base = "grammar" },
        .{ .name = "weave", .complexity = "O(N^M)", .base = "weave" },
        .{ .name = "scheme", .complexity = "O(units)", .base = "scheme" },
    };

    for (module_directives) |md| {
        if (std.mem.startsWith(u8, core, md.name) or std.mem.eql(u8, core, md.name)) {
            return .{
                .complexity = md.complexity,
                .has_derive_multiplier = std.mem.startsWith(u8, core, md.name) and
                    !std.mem.eql(u8, md.base, "grammar") and !std.mem.eql(u8, md.base, "weave"),
                .is_module_directive = true,
                .base_combinator = md.base,
            };
        }
    }

    // Check if it's a derive variant (specific variants first, then general derive)
    const derive_specific = [_]struct { name: []const u8, complexity: []const u8, base: []const u8 }{
        .{ .name = "derive.product", .complexity = "O(n2xf)", .base = "product" },
        .{ .name = "derive.tensor", .complexity = "O(n3xf)", .base = "tensor" },
        .{ .name = "derive.nfold", .complexity = "O(n^kxf)", .base = "nfold" },
        .{ .name = "derive.power", .complexity = "O(2^nxf)", .base = "power" },
        .{ .name = "derive.choose", .complexity = "O(nchoosekxf)", .base = "choose" },
        .{ .name = "derive.permute", .complexity = "O(n!xf)", .base = "permute" },
        .{ .name = "derive.bundle", .complexity = "8traits", .base = "bundle" },
    };

    for (derive_specific) |ds| {
        if (std.mem.startsWith(u8, core, ds.name)) {
            return .{
                .complexity = ds.complexity,
                .has_derive_multiplier = true,
                .is_module_directive = false,
                .base_combinator = ds.base,
            };
        }
    }

    // General derive (exact match only)
    if (std.mem.eql(u8, core, "derive")) {
        return .{
            .complexity = "O(nxf)",
            .has_derive_multiplier = true,
            .is_module_directive = false,
            .base_combinator = "derive",
        };
    }

    // derive.all is a special case
    if (std.mem.startsWith(u8, core, "derive.all")) {
        return .{
            .complexity = "O(nxf)",
            .has_derive_multiplier = true,
            .is_module_directive = false,
            .base_combinator = "derive",
        };
    }

    // Core combinators
    const core_combinators = [_]struct { name: []const u8, complexity: []const u8 }{
        .{ .name = "map", .complexity = "O(n)" },
        .{ .name = "sweep", .complexity = "O(n)" },
        .{ .name = "expand", .complexity = "O(n)" },
        .{ .name = "pow", .complexity = "O(2^n)" },
        .{ .name = "product", .complexity = "O(n2)" },
        .{ .name = "tensor", .complexity = "O(n3)" },
        .{ .name = "nfold", .complexity = "O(n^k)" },
        .{ .name = "ceiling", .complexity = "O(n^f)+O(n2^f)" },
        .{ .name = "omni", .complexity = "O(n3^f)" },
        .{ .name = "power", .complexity = "O(2^n)" },
        .{ .name = "powerset", .complexity = "O(2^n)" },
        .{ .name = "choose", .complexity = "O(n choose k)" },
        .{ .name = "permute", .complexity = "O(n!)" },
        .{ .name = "each", .complexity = "O(1)->O(output)" },
        .{ .name = "chain", .complexity = "O(1)->O(output)" },
        .{ .name = "template", .complexity = "O(n)" },
        .{ .name = "generate", .complexity = "O(n) or O(ops^types)" },
        .{ .name = "fixpoint", .complexity = "O(1)->O(max_iter)" },
        .{ .name = "fanout", .complexity = "O(branch^depth)" },
    };

    for (core_combinators) |cc| {
        if (std.mem.eql(u8, core, cc.name)) {
            return .{
                .complexity = cc.complexity,
                .has_derive_multiplier = false,
                .is_module_directive = false,
                .base_combinator = cc.name,
            };
        }
    }

    return null;
}

/// Suggest the next-level combinator for a given path (composability hint).
/// E.g., for "map" suggests "product" or "burst"; for "tensor" suggests "nfold" or "tower".
pub fn suggestNextCombinators(path: []const u8) []const u8 {
    // Mapping of current combinator -> suggestions for higher-order patterns
    const NextLevel = struct { name: []const u8, suggestions: []const u8 };
    const next_level = [_]NextLevel{
        .{ .name = "map", .suggestions = "@comp.product, @comp.burst" },
        .{ .name = "derive", .suggestions = "@comp.derive.product, @comp.derive.all, @comp.burst" },
        .{ .name = "product", .suggestions = "@comp.tensor, @comp.derive.product, @comp.ceiling" },
        .{ .name = "tensor", .suggestions = "@comp.nfold, @comp.derive.tensor, @comp.transcend" },
        .{ .name = "nfold", .suggestions = "@comp.tower, @comp.infinity, @comp.hyper" },
        .{ .name = "burst", .suggestions = "@comp.transcend, @comp.infinity, @comp.hyper" },
        .{ .name = "grammar", .suggestions = "@comp.each" },
        .{ .name = "weave", .suggestions = "@comp.each, @comp.product" },
        .{ .name = "template", .suggestions = "@comp.generate, @comp.each" },
        .{ .name = "scheme", .suggestions = "@comp.each, @comp.scheme.clauses" },
    };

    const core = if (std.mem.startsWith(u8, path, "comp."))
        path["comp.".len..]
    else if (std.mem.startsWith(u8, path, "meta."))
        path["meta.".len..]
    else if (std.mem.startsWith(u8, path, "compiler."))
        path["compiler.".len..]
    else
        path;

    for (next_level) |nl| {
        if (std.mem.endsWith(u8, core, nl.name) or std.mem.eql(u8, core, nl.name)) {
            return nl.suggestions;
        }
    }

    return "see @comp.ladder() for full scaling hierarchy";
}

/// Surface-syntax evolution index for all agents.
pub fn agentGrammarText() []const u8 {
    return
    \\docs/GRAMMAR_SPEC.md — canonical GR-* rules (bare func, if-expressions, etc.)
    \\MCP: duo_grammar_spec_read / duo_grammar_spec_update (duo-lsp MCP)
    \\Comptime: @comp.agent.grammar() / std.agent.grammar_index()
    \\Prefer dotted @comp.* paths; never introduce @comp.foo_bar underscore spellings
    ;
}

/// Grouped catalog with agent section header.
pub fn formatAgentCatalog(alloc: std.mem.Allocator) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);
    try buf.appendSlice(alloc, "# agent @comp.* catalog (@meta.* aliases)\n");
    const grouped = try formatCatalogGrouped(alloc);
    defer alloc.free(grouped);
    try buf.appendSlice(alloc, grouped);
    return try buf.toOwnedSlice(alloc);
}

/// Scaling ladder with agent workflow hints.
pub fn formatAgentLadder(alloc: std.mem.Allocator) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);
    try buf.appendSlice(alloc, "# agent exponential ladder\n");
    try buf.appendSlice(alloc, scalingLadderText());
    try buf.appendSlice(alloc, "# module emit stack: burst->transcend->infinity->hyper\n");
    return try buf.toOwnedSlice(alloc);
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

test "meta_module: canonical @meta.* builtins" {
    try std.testing.expectEqualStrings("__comptimemap", resolveBuiltin("meta.map").?);
    try std.testing.expectEqualStrings("__derivemap", resolveBuiltin("meta.derive").?);
    try std.testing.expectEqualStrings("__fieldsmap", resolveBuiltin("meta.fields.map").?);
    try std.testing.expectEqualStrings("__register_derive", resolveBuiltin("meta.register.derive").?);
    try std.testing.expectEqualStrings("__comptimemap", resolveBuiltin("meta.sweep").?);
    try std.testing.expectEqualStrings("__comptimeeach", resolveBuiltin("comp.chain").?);
    try std.testing.expectEqualStrings("__comptimeeach", resolveBuiltin("meta.each").?);
}

test "meta_module: direct module directives remain canonical" {
    try std.testing.expect(isModuleDirective("pipeline"));
    try std.testing.expect(isModuleDirective("rewrite"));
    try std.testing.expect(isModuleDirective("foreign"));
    try std.testing.expectEqualStrings("pipeline", normalizeDirective("pipeline"));
}

test "meta_module: directive normalization" {
    try std.testing.expectEqualStrings("pipeline", normalizeDirective("meta.pipeline"));
    try std.testing.expectEqualStrings("define.derive", normalizeDirective("meta.define.derive"));
    try std.testing.expectEqualStrings("derive.all", normalizeDirective("meta.derive.all"));
    try std.testing.expect(directiveMatches("meta.derive.all", "derive.all"));
    try std.testing.expect(isMetaAttribute("meta.define.derive"));
    try std.testing.expectEqualStrings("__metaexpand", resolveBuiltin("meta.expand").?);
    try std.testing.expectEqualStrings("__metaexpand", resolveBuiltin("meta.pow").?);
    try std.testing.expectEqualStrings("__metaceiling", resolveBuiltin("meta.ceiling").?);
    try std.testing.expectEqualStrings("__metaomni", resolveBuiltin("meta.omni").?);
    try std.testing.expectEqualStrings("__metaomni", resolveBuiltin("meta.stack").?);
    try std.testing.expectEqualStrings("__metaburst", resolveBuiltin("meta.burst").?);
    try std.testing.expectEqualStrings("burst", normalizeDirective("meta.burst"));
    try std.testing.expectEqualStrings("emit.omni", normalizeDirective("meta.emit.omni"));
    try std.testing.expectEqualStrings("wasm", normalizeDirective("meta.wasm"));
    try std.testing.expectEqualStrings("__comptimemap", resolveBuiltin("meta.sweep").?);
    try std.testing.expectEqualStrings("derive.bundle", normalizeTypeAttribute("meta.derive.bundle"));
    try std.testing.expectEqualStrings("__metaagentcatalog", resolveBuiltin("meta.agent.catalog").?);
    try std.testing.expectEqualStrings("__metaagentcatalog", resolveBuiltin("comp.agent.catalog").?);
    try std.testing.expectEqualStrings("__metaagenthooks", resolveBuiltin("meta.agent.hooks").?);
    try std.testing.expectEqualStrings("__metaagentdedupe", resolveBuiltin("comp.agent.dedupe").?);
    try std.testing.expectEqualStrings("__metaagentgaps", resolveBuiltin("comp.agent.gaps").?);
    try std.testing.expect(catalogPathParseable("comp.map"));
    try std.testing.expect(catalogPathParseable("comp.agent.dedupe"));
}

test "meta_module: catalog lists canonical comp paths (deduped)" {
    const alloc = std.testing.allocator;
    const catalog = try formatCatalog(alloc);
    defer alloc.free(catalog);
    try std.testing.expect(std.mem.indexOf(u8, catalog, "comp.map") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog, "comp.catalog") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog, "comp.pipeline") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog, "comp.str.starts.with") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog, "comp.str.ends.with") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog, "comp.choose") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog, "comp.derive.choose") != null);
    // Aliases dedupe — one row per internal handler
    try std.testing.expect(std.mem.indexOf(u8, catalog, "meta.map") == null);
    try std.testing.expect(std.mem.indexOf(u8, catalog, "compiler.map") == null);
    // Underscore aliases must NOT appear in catalog
    try std.testing.expect(std.mem.indexOf(u8, catalog, "comptime_map") == null);
    try std.testing.expect(std.mem.indexOf(u8, catalog, "define_derive") == null);
    try std.testing.expect(std.mem.indexOf(u8, catalog, "static_assert") == null);
    try std.testing.expect(std.mem.indexOf(u8, catalog, "meta.if") == null);
    try std.testing.expect(std.mem.indexOf(u8, catalog, "meta.concept.methods") == null);
}

test "meta_module: no underscore aliases in builtins" {
    // Verify no public name contains an underscore (all use dot hierarchy)
    for (builtins) |entry| {
        // Bare-name ergonomic aliases (no dots) are allowed: popcount, clz, etc.
        // But names with underscores in them are NOT allowed.
        if (std.mem.indexOfScalar(u8, entry.public, '_') != null) {
            @panic("underscore in public builtin name");
        }
    }
}

test "meta_module: no underscore aliases in directives" {
    for (directives) |entry| {
        if (std.mem.indexOfScalar(u8, entry.public, '_') != null) {
            @panic("underscore in public directive name");
        }
    }
}

test "meta_module: catalogPathParseable rejects keywords" {
    try std.testing.expect(catalogPathParseable("meta.map"));
    try std.testing.expect(catalogPathParseable("meta.concepts.methods"));
    try std.testing.expect(!catalogPathParseable("meta.if"));
    try std.testing.expect(!catalogPathParseable("meta.concept.methods"));
    try std.testing.expect(!catalogPathParseable("meta.comptime.warn"));
}

test "meta_module: catalogCategory and filtered catalog" {
    try std.testing.expectEqualStrings("combinators", catalogCategory("meta.map"));
    try std.testing.expectEqualStrings("combinators", catalogCategory("meta.burst"));
    try std.testing.expectEqualStrings("define", catalogCategory("meta.derive.all"));
    try std.testing.expectEqualStrings("emit", catalogCategory("meta.emit.omni"));

    const alloc = std.testing.allocator;
    const combos = try formatCatalogFiltered(alloc, "combinators");
    defer alloc.free(combos);
    try std.testing.expect(std.mem.indexOf(u8, combos, "comp.map") != null);
    try std.testing.expect(std.mem.indexOf(u8, combos, "comp.burst") != null);
    try std.testing.expect(std.mem.indexOf(u8, combos, "comp.tensor") != null);
    try std.testing.expect(std.mem.indexOf(u8, combos, "meta.map") == null);

    const grouped = try formatCatalogGrouped(alloc);
    defer alloc.free(grouped);
    try std.testing.expect(std.mem.indexOf(u8, grouped, "# combinators") != null);
    try std.testing.expect(std.mem.indexOf(u8, grouped, "comp.tensor") != null);

    try std.testing.expectEqualStrings("combinators", catalogCategory("meta.tensor"));
    try std.testing.expectEqualStrings("combinators", catalogCategory("meta.transcend"));
    try std.testing.expectEqualStrings("introspection", catalogCategory("meta.str.starts.with"));
    try std.testing.expectEqualStrings("introspection", catalogCategory("meta.str.ends.with"));
}


test "meta_module: combinatorComplexity for linear combinators" {
    const info = combinatorComplexity("comp.map") orelse return;
    try std.testing.expectEqualStrings("O(n)", info.complexity);
    try std.testing.expect(!info.has_derive_multiplier);
    try std.testing.expect(!info.is_module_directive);
    try std.testing.expectEqualStrings("map", info.base_combinator);

    const info2 = combinatorComplexity("meta.tensor") orelse return;
    try std.testing.expectEqualStrings("O(n3)", info2.complexity);
    try std.testing.expect(!info2.has_derive_multiplier);
    try std.testing.expect(!info2.is_module_directive);
}

test "meta_module: combinatorComplexity for derive variants" {
    const info = combinatorComplexity("comp.derive.product") orelse return;
    try std.testing.expectEqualStrings("O(n2xf)", info.complexity);
    try std.testing.expect(info.has_derive_multiplier);
    try std.testing.expect(!info.is_module_directive);
    try std.testing.expectEqualStrings("product", info.base_combinator);

    const info2 = combinatorComplexity("comp.derive.all") orelse return;
    try std.testing.expectEqualStrings("O(nxf)", info2.complexity);
    try std.testing.expect(info2.has_derive_multiplier);
}

test "meta_module: combinatorComplexity for module directives" {
    const info = combinatorComplexity("comp.burst") orelse return;
    try std.testing.expectEqualStrings("O(n^2xf)", info.complexity);
    try std.testing.expect(info.has_derive_multiplier);
    try std.testing.expect(info.is_module_directive);
    try std.testing.expectEqualStrings("burst", info.base_combinator);

    const info2 = combinatorComplexity("comp.transcend") orelse return;
    try std.testing.expectEqualStrings("O(n^3xf)", info2.complexity);
    try std.testing.expect(info2.is_module_directive);
}

test "meta_module: suggestNextCombinators" {
    try std.testing.expectEqualStrings("@comp.product, @comp.burst", suggestNextCombinators("comp.map"));
    try std.testing.expectEqualStrings("@comp.product, @comp.burst", suggestNextCombinators("meta.map"));
    try std.testing.expectEqualStrings("see @comp.ladder() for full scaling hierarchy", suggestNextCombinators("comp.unknown"));
}
