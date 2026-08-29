/// Canonical `@comp.*` compiler module: hierarchical public names for metaprogramming.
///
/// The PRIMARY public surface for compile-time operations is `@comp.*` dotted paths.
/// `@meta.*` is an alias family that maps to the same internal handlers.
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
///   @comp.ffi           — FFI generation
///   @comp.wasm          — embed WASM bytes as const uint8_t[] (module directive)
///   @comp.make.type     — type construction
///   @comp.as.type       — explicit type cast
///   @comp.bitfield      — bitfield type
///   @comp.union         — union type
///   @comp.select        — compile-time select
///   @comp.run           — compile-time execution
///   @comp.constexpr     — constexpr evaluation
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
/// `@comp.comptime.warn`. All `@meta.*` paths are aliases.
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
    .{ .public = "meta.sweep", .internal = "__comptimemap" },
    .{ .public = "comp.sweep", .internal = "__comptimemap" },
    .{ .public = "meta.expand", .internal = "__metaexpand" },
    .{ .public = "comp.expand", .internal = "__metaexpand" },
    .{ .public = "meta.pow", .internal = "__metaexpand" },
    .{ .public = "comp.pow", .internal = "__metaexpand" },
    .{ .public = "meta.ceiling", .internal = "__metaceiling" },
    .{ .public = "comp.ceiling", .internal = "__metaceiling" },
    .{ .public = "meta.omni", .internal = "__metaomni" },
    .{ .public = "comp.omni", .internal = "__metaomni" },
    .{ .public = "meta.stack", .internal = "__metaomni" },
    .{ .public = "comp.stack", .internal = "__metaomni" },
    .{ .public = "meta.burst", .internal = "__metaburst" },
    .{ .public = "comp.burst", .internal = "__metaburst" },
    .{ .public = "meta.tensor", .internal = "__comptimetensor" },
    .{ .public = "comp.tensor", .internal = "__comptimetensor" },
    .{ .public = "meta.derive.tensor", .internal = "__derivetensor" },
    .{ .public = "comp.derive.tensor", .internal = "__derivetensor" },
    .{ .public = "meta.nfold", .internal = "__comptimenfold" },
    .{ .public = "comp.nfold", .internal = "__comptimenfold" },
    .{ .public = "meta.derive.nfold", .internal = "__derivenfold" },
    .{ .public = "comp.derive.nfold", .internal = "__derivenfold" },
    .{ .public = "meta.transcend", .internal = "__metatranscend" },
    .{ .public = "comp.transcend", .internal = "__metatranscend" },
    .{ .public = "meta.infinity", .internal = "__metainfinity" },
    .{ .public = "comp.infinity", .internal = "__metainfinity" },
    .{ .public = "meta.hyper", .internal = "__metahyper" },
    .{ .public = "comp.hyper", .internal = "__metahyper" },
    .{ .public = "meta.tower", .internal = "__derivetower" },
    .{ .public = "comp.tower", .internal = "__derivetower" },
    .{ .public = "meta.derive", .internal = "__derivemap" },
    .{ .public = "comp.derive", .internal = "__derivemap" },
    .{ .public = "meta.product", .internal = "__comptimeproduct" },
    .{ .public = "comp.product", .internal = "__comptimeproduct" },
    .{ .public = "meta.derive.product", .internal = "__deriveproduct" },
    .{ .public = "comp.derive.product", .internal = "__deriveproduct" },
    // ── Truly exponential (2^n / n!) combinators ──
    .{ .public = "meta.power", .internal = "__comptimepower" },
    .{ .public = "comp.power", .internal = "__comptimepower" },
    .{ .public = "meta.powerset", .internal = "__comptimepower" },
    .{ .public = "comp.powerset", .internal = "__comptimepower" },
    .{ .public = "meta.derive.power", .internal = "__derivepower" },
    .{ .public = "comp.derive.power", .internal = "__derivepower" },
    .{ .public = "comp.derive.powerset", .internal = "__derivepower" },
    .{ .public = "meta.choose", .internal = "__comptimechoose" },
    .{ .public = "comp.choose", .internal = "__comptimechoose" },
    .{ .public = "meta.derive.choose", .internal = "__derivechoose" },
    .{ .public = "comp.derive.choose", .internal = "__derivechoose" },
    .{ .public = "meta.permute", .internal = "__comptimepermute" },
    .{ .public = "comp.permute", .internal = "__comptimepermute" },
    .{ .public = "meta.derive.permute", .internal = "__derivepermute" },
    .{ .public = "comp.derive.permute", .internal = "__derivepermute" },
    // ── Universal composition glue (closes the combinator algebra) ──
    .{ .public = "meta.each", .internal = "__comptimeeach" },
    .{ .public = "comp.each", .internal = "__comptimeeach" },
    // `@comp.chain` — ergonomic alias for `@comp.each` (combinator composition glue)
    .{ .public = "comp.chain", .internal = "__comptimeeach" },

    // `@comp.match` — compile-time pattern-match codegen (switch/case of codegen)
    // Splits pattern spec on `|`, calls callback for each alternative with {pattern, index, count}.
    // One declarative line → N specialized branches. Composes with @comp.each, @comp.burst, etc.
    .{ .public = "comp.match", .internal = "__comptimematch" },

    // `@comp.tabulate` — compile-time lookup table generator (unrolled loop of codegen)
    // Calls callback for 0..count-1 with {index, count}, concatenates comma-separated.
    // O(1) author input → O(count) output. Replaces runtime init with compile-time static.
    .{ .public = "comp.tabulate", .internal = "__comptimetabulate" },

    // `@comp.interpolate` — compile-time string interpolation (code template injection)
    // Takes template with {name} placeholders + {name=value} vars table, substitutes at compile time.
    .{ .public = "comp.interpolate", .internal = "__comptimeinterpolate" },

    // `@comp.zip` — compile-time cartesian zip codegen (quadratic combinator)
    // Two pipe-separated specs, callback for every (a, b) pair with {a, b, index, count}.
    .{ .public = "comp.zip", .internal = "__comptimezip" },

    // ── Type introspection ──
    .{ .public = "comp.type.name", .internal = "__type_name" },
    .{ .public = "comp.type.id", .internal = "__type_id" },
    .{ .public = "comp.type.info", .internal = "__typeinfo" },
    .{ .public = "meta.type.shape", .internal = "__type_shape" },
    .{ .public = "comp.type.shape", .internal = "__type_shape" },
    // Ergonomic alias — same intrinsic as @comp.type.shape (specialization ladder label).
    .{ .public = "meta.shape", .internal = "__type_shape" },
    .{ .public = "comp.shape", .internal = "__type_shape" },
    .{ .public = "meta.why.shape", .internal = "__why_shape" },
    .{ .public = "comp.why.shape", .internal = "__why_shape" },
    .{ .public = "meta.why.boxed", .internal = "__why_boxed" },
    .{ .public = "comp.why.boxed", .internal = "__why_boxed" },
    .{ .public = "meta.why.not.native", .internal = "__why_not_native" },
    .{ .public = "comp.why.not.native", .internal = "__why_not_native" },
    .{ .public = "meta.representation", .internal = "__representation" },
    .{ .public = "comp.representation", .internal = "__representation" },
    .{ .public = "meta.why", .internal = "__why" },
    .{ .public = "comp.why", .internal = "__why" },
    .{ .public = "meta.why.module", .internal = "__why_module" },
    .{ .public = "comp.why.module", .internal = "__why_module" },
    .{ .public = "meta.origin", .internal = "__origin" },
    .{ .public = "comp.origin", .internal = "__origin" },
    .{ .public = "comp.type.is", .internal = "__is_type" },
    .{ .public = "comp.type.of", .internal = "__typeof" },
    .{ .public = "comp.types", .internal = "__moduletypes" },
    .{ .public = "comp.type.names", .internal = "__moduletypenames" },
    .{ .public = "comp.types.with", .internal = "__concepttypenames" },
    .{ .public = "comp.diff", .internal = "__typediff" },
    .{ .public = "comp.satisfies", .internal = "__satisfies" },

    // ── Structural reflection ──
    .{ .public = "comp.fields", .internal = "__fields" },
    .{ .public = "comp.methods", .internal = "__methods" },
    .{ .public = "comp.variants", .internal = "__variants" },
    .{ .public = "comp.has.field", .internal = "__has_field" },
    .{ .public = "comp.has.method", .internal = "__has_method" },
    .{ .public = "comp.has.metamethod", .internal = "__has_metamethod" },
    .{ .public = "comp.field.type", .internal = "__field_type" },
    .{ .public = "comp.field.offset", .internal = "__field_offset" },
    .{ .public = "comp.field.size", .internal = "__field_size" },

    // ── Concept introspection ──
    .{ .public = "comp.concepts.methods", .internal = "__concept_methods" },
    .{ .public = "comp.concepts.fields", .internal = "__concept_fields" },
    .{ .public = "comp.concepts.members", .internal = "__concept_members" },
    .{ .public = "comp.concepts.count", .internal = "__concept_count" },

    // ── Compile-time control ──
    .{ .public = "comp.when", .internal = "__comptimeif" },
    .{ .public = "meta.loop", .internal = "__comptimefor" },
    .{ .public = "comp.loop", .internal = "__comptimefor" },
    .{ .public = "comp.fold", .internal = "__comptimefold" },
    .{ .public = "comp.assert", .internal = "__static_assert" },
    .{ .public = "comp.compile.log", .internal = "__comptimeprint" },
    .{ .public = "comp.compile.warn", .internal = "__comptimewarn" },
    .{ .public = "comp.compile.error", .internal = "__comptimeerror" },
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
    .{ .public = "comp.constexpr", .internal = "__constexpr" },

    // ── Derive management ──
    .{ .public = "meta.define.derive", .internal = "__define_derive" },
    .{ .public = "comp.define.derive", .internal = "__define_derive" },
    .{ .public = "comp.register.derive", .internal = "__register_derive" },
    .{ .public = "comp.register.rewrite", .internal = "__register_rewrite" },
    .{ .public = "comp.derive.lookup", .internal = "__lookup_derive" },
    .{ .public = "comp.derive.list", .internal = "__list_derives" },
    .{ .public = "comp.derive.eval", .internal = "__eval_derive" },

    // ── Embed ──
    .{ .public = "comp.embed.str", .internal = "__embed_str" },
    .{ .public = "comp.embed.file", .internal = "__embed_file" },
    // NOTE: meta.embed.json and meta.wasm are module directives, not expressions;
    // they must lower to C globals, not lua_Value tables (AGENTS.md §6).

    // ── Code generation / transform ──
    .{ .public = "comp.foreign", .internal = "__foreign" },
    .{ .public = "comp.ffi", .internal = "__ffi_gen" },
    .{ .public = "comp.sql", .internal = "__sql" },
    // The last two intrinsics still spelled with a leading `__` in .id source.
    // Every other internal already had a `@comp.*` public name here; these did
    // not, which is the only reason the `__` namespace could not reach zero.
    .{ .public = "comp.native.load.u8", .internal = "__native_load_u8" },
    .{ .public = "comp.id.kind", .internal = "__duo_kind" },
    .{ .public = "comp.lua", .internal = "__lua_exec" },
    .{ .public = "comp.c.emit.file", .internal = "__c_emit_file" },

    // ── Compiler / raw C interface (hierarchical @c.*, @comp.c.*, @meta.c.*) ──
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
    .{ .public = "comp.hint.hot", .internal = "__hot_path" },
    .{ .public = "meta.c.emit", .internal = "__emit" },
    .{ .public = "meta.c.export", .internal = "__c_export" },
    .{ .public = "comp.c.emit", .internal = "__emit" },
    .{ .public = "comp.c.call", .internal = "__c_call" },
    .{ .public = "comp.c.include", .internal = "__c_include" },
    .{ .public = "comp.c.export", .internal = "__c_export" },
    .{ .public = "comp.c.import", .internal = "__c_import" },
    .{ .public = "comp.c.type", .internal = "__c_type" },
    .{ .public = "comp.c.link", .internal = "__c_link" },
    .{ .public = "comp.asm", .internal = "__asm" },

    // ── Type construction ──
    .{ .public = "comp.make.type", .internal = "__make_type" },
    .{ .public = "comp.as.type", .internal = "__as_type" },
    .{ .public = "comp.bitfield", .internal = "__bitfield" },
    .{ .public = "comp.union", .internal = "__union" },
    .{ .public = "comp.select", .internal = "__select" },

    // ── Typeof (type-specifier, not value expression) ──
    .{ .public = "comp.typeof", .internal = "__typeof" },

    // ── Bit intrinsics (bare-name + hierarchy aliases for ergonomics) ──
    .{ .public = "comp.bit.popcount", .internal = "__popcount" },
    .{ .public = "popcount", .internal = "__popcount" },
    .{ .public = "comp.bit.ctz", .internal = "__ctz" },
    .{ .public = "ctz", .internal = "__ctz" },
    .{ .public = "comp.bit.clz", .internal = "__clz" },
    .{ .public = "clz", .internal = "__clz" },
    .{ .public = "comp.bit.bswap", .internal = "__bswap" },
    .{ .public = "bswap", .internal = "__bswap" },
    .{ .public = "comp.bit.rotl", .internal = "__rotl" },
    .{ .public = "rotl", .internal = "__rotl" },
    .{ .public = "comp.bit.rotr", .internal = "__rotr" },
    .{ .public = "comp.bit.bitcast", .internal = "__bitcast" },

    // ── Optimization hints (bare-name + hierarchy aliases for ergonomics) ──
    .{ .public = "comp.hint.likely", .internal = "__likely" },
    .{ .public = "likely", .internal = "__likely" },
    .{ .public = "comp.hint.unlikely", .internal = "__unlikely" },
    .{ .public = "unlikely", .internal = "__unlikely" },
    .{ .public = "comp.hint.prefetch", .internal = "__prefetch" },
    .{ .public = "prefetch", .internal = "__prefetch" },
    .{ .public = "comp.hint.assume", .internal = "__assume" },
    .{ .public = "comp.hint.unreachable", .internal = "__unreachable" },
    .{ .public = "comp.hint.trap", .internal = "__trap" },
    .{ .public = "comp.hint.fence", .internal = "__fence" },
    .{ .public = "fence", .internal = "__fence" },
    .{ .public = "comp.hint.volatile", .internal = "__volatile" },
    .{ .public = "volatile", .internal = "__volatile" },

    // ── Catalog / self-documentation / agent ──
    .{ .public = "meta.str.starts.with", .internal = "__strstartswith" },
    .{ .public = "comp.str.starts.with", .internal = "__strstartswith" },
    .{ .public = "meta.str.ends.with", .internal = "__strendswith" },
    .{ .public = "comp.str.ends.with", .internal = "__strendswith" },
    .{ .public = "comp.str.countlines", .internal = "__strcountlines" },
    .{ .public = "comp.str.splitcount", .internal = "__strsplitcount" },
    .{ .public = "comp.str.len", .internal = "__strcomptelen" },
    .{ .public = "comp.str.eq", .internal = "__streq" },
    .{ .public = "comp.str.join", .internal = "__strjoin" },

    // ── Generative combinators (break the linear ceiling) ──
    // @meta.grammar: EBNF grammar -> O(b^d) code fragments from minimal spec
    .{ .public = "comp.grammar", .internal = "__metagrammar" },
    // @meta.weave: cross-module type-driven code injection (1 type ^ N weaves ^ M derives)
    .{ .public = "comp.weave", .internal = "__metaweave" },
    // @meta.template: parametric code templates that expand at compile time
    .{ .public = "comp.template", .internal = "__metatemplate" },
    // @meta.generate: LLM-free generative code synthesis from constraints
    .{ .public = "comp.generate", .internal = "__metagenerate" },
    // @meta.scheme: declarative program scheme -> full implementation
    .{ .public = "comp.scheme", .internal = "__metascheme" },
    .{ .public = "comp.scheme.clauses", .internal = "__metaschemeclauses" },
    // @meta.fixpoint: unbounded iterative combinator — O(1) input -> O(max_iter) output
    .{ .public = "comp.fixpoint", .internal = "__comptimefixpoint" },
    // @meta.fanout: tree-shaped generative expansion — O(branch^depth) output from O(1) input
    .{ .public = "comp.fanout", .internal = "__comptimefanout" },

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
    .{ .public = "comp.pipeline", .canonical = "pipeline" },
    .{ .public = "comp.foreign", .canonical = "foreign" },
    .{ .public = "comp.embed.json", .canonical = "embed.json" },
    .{ .public = "comp.embed.wasm", .canonical = "wasm" },
    .{ .public = "comp.wasm", .canonical = "wasm" },
    .{ .public = "comp.sql", .canonical = "sql" },
    .{ .public = "comp.lua", .canonical = "lua" },
    .{ .public = "comp.ffi", .canonical = "ffi.gen" },
    .{ .public = "meta.define.derive", .canonical = "define.derive" },
    .{ .public = "comp.define.derive", .canonical = "define.derive" },
    .{ .public = "comp.define.bundle", .canonical = "define.derive.bundle" },
    .{ .public = "comp.derive.all", .canonical = "derive.all" },
    .{ .public = "meta.emit.derive", .canonical = "emit.derive" },
    .{ .public = "comp.emit.derive", .canonical = "emit.derive" },
    .{ .public = "meta.emit.omni", .canonical = "emit.omni" },
    .{ .public = "comp.emit.omni", .canonical = "emit.omni" },
    .{ .public = "meta.burst", .canonical = "burst" },
    .{ .public = "comp.burst", .canonical = "burst" },
    .{ .public = "meta.transcend", .canonical = "transcend" },
    .{ .public = "comp.transcend", .canonical = "transcend" },
    .{ .public = "meta.infinity", .canonical = "infinity" },
    .{ .public = "comp.infinity", .canonical = "infinity" },
    .{ .public = "meta.hyper", .canonical = "hyper" },
    .{ .public = "comp.hyper", .canonical = "hyper" },
    .{ .public = "comp.compile.native", .canonical = "native" },
    .{ .public = "native", .canonical = "native" },
    .{ .public = "comp.compile.cached", .canonical = "cached" },
    .{ .public = "comp.compile.thread", .canonical = "compile.thread" },
    .{ .public = "comp.compile.device", .canonical = "device" },
    .{ .public = "comp.compile.autodiff", .canonical = "autodiff" },
    .{ .public = "comp.compile.differentiable", .canonical = "differentiable" },
    .{ .public = "comp.compile.profile", .canonical = "profile" },
    .{ .public = "comp.compile.unroll", .canonical = "unroll" },
    .{ .public = "comp.compile.modify", .canonical = "modify" },
    .{ .public = "comp.compile.only", .canonical = "compile.only" },
    .{ .public = "comp.emit.file", .canonical = "c.emit.file" },
    // Generative combinators as module-level directives
    .{ .public = "comp.grammar", .canonical = "grammar" },
    .{ .public = "comp.weave", .canonical = "weave" },
    .{ .public = "comp.template", .canonical = "template" },
    .{ .public = "comp.scheme", .canonical = "scheme" },
};

/// Map `@`-prefixed qualified name to internal intrinsic (`__comptimemap`, etc.).
/// Accepts `comp.*` and `meta.*` prefixes interchangeably.
pub fn resolveBuiltin(qualified: []const u8) ?[]const u8 {
    for (builtins) |entry| {
        if (std.mem.eql(u8, qualified, entry.public)) return entry.internal;
    }
    return null;
}

/// Map internal hook (`__comptimemap`, etc.) to canonical `comp.*` public name.
pub fn publicNameForInternal(internal: []const u8) ?[]const u8 {
    var best: ?[]const u8 = null;
    var best_pri: u8 = 255;
    for (builtins) |entry| {
        if (!std.mem.eql(u8, entry.internal, internal)) continue;
        const pri = catalogDisplayPriority(entry.public);
        if (pri < best_pri) {
            best = entry.public;
            best_pri = pri;
        }
    }
    return best;
}

test "meta_module: isStandaloneModuleStatement for define.derive" {
    try std.testing.expect(isStandaloneModuleStatement("comp.define.derive"));
    try std.testing.expect(isStandaloneModuleStatement("meta.define.derive"));
    try std.testing.expect(!isStandaloneModuleStatement("comp.hint.fence"));
    try std.testing.expect(!isStandaloneModuleStatement("comp.map"));
}

test "meta_module: publicNameForInternal prefers comp.* alias" {
    try std.testing.expectEqualStrings("comp.match", publicNameForInternal("__comptimematch").?);
    try std.testing.expectEqualStrings("comp.zip", publicNameForInternal("__comptimezip").?);
    try std.testing.expect(publicNameForInternal("__nonexistent") == null);
}

/// Standalone C header `#include` directives (`@comp.c.import`, legacy `@c.import`, …).
pub fn isCHeaderImportDirective(name: []const u8) bool {
    if (std.mem.eql(u8, name, "cinclude")) return true;
    if (resolveBuiltin(name)) |internal| {
        return std.mem.eql(u8, internal, "__c_include") or std.mem.eql(u8, internal, "__c_import");
    }
    return false;
}

/// Standalone raw C injection directives (`@comp.c.emit`, legacy `@c.emit`, …).
///
/// SEVEN SPELLINGS REACH `__emit`: `@comp.c.emit` (canonical), `@c.emit`,
/// `@meta.c.emit`, `@comp.emit`, `@emit`.
/// They are one operation — compiled and run, all seven give the same answer.
/// The table is the only place that fact is written down, so this predicate
/// reads the table instead of restating part of it; restating part of it is
/// what discarded every `@comp.c.emit` statement in `lib/` while `idol check`
/// reported the tree clean.
pub fn isCEmitDirective(name: []const u8) bool {
    if (resolveBuiltin(name)) |internal| {
        return std.mem.eql(u8, internal, "__emit");
    }
    // No literal tail. `emit` HAS a table entry (`.{ .public = "emit",
    // .internal = "__emit" }`), so the `std.mem.eql(u8, name, "emit")` that
    // used to sit here was already unreachable — a literal kept for a spelling
    // the table had absorbed. `isCHeaderImportDirective` above still needs its
    // tail, because `cinclude` genuinely has no entry; this one did not.
    return false;
}

/// C-interface attributes that attach to the following declaration (export, type, …).
///
/// `__c_call` IS IN THIS SET, and leaving it out cost a silent wrong answer of
/// exactly the `@comp.c.emit` kind. `parser.zig` compensated with a literal
/// `or std.mem.eql(u8, attr.name, "c.call")` beside the call to this predicate,
/// so only the SHORT spelling attached. Measured, with `twice_c` emitted and a
/// function body consisting of one call to it:
///
///     twice: i64 = ()
///         @c.call("twice_c", @(21))        -> error: unknown or misplaced attribute
///         @comp.c.call("twice_c", @(21))   -> compiles clean, `return 0;`
///
/// The canonical spelling — the one `warnDeprecatedAtQualified` tells you to
/// write — fell through to `isMetaAttribute`, which resolves `comp.c.call` in
/// the builtin table and answers "module directive", so the body was parsed as
/// a standalone directive statement and the function was left empty. `idol
/// check` reported no errors, because there were none: the function compiled,
/// it just did nothing. Resolving `__c_call` here makes both spellings attach,
/// and both then reach the same diagnostic.
pub fn isAttachingCInterfaceAttribute(name: []const u8) bool {
    if (resolveBuiltin(name)) |internal| {
        return std.mem.eql(u8, internal, "__c_export") or
            std.mem.eql(u8, internal, "__c_type") or
            std.mem.eql(u8, internal, "__c_link") or
            std.mem.eql(u8, internal, "__c_call") or
            std.mem.eql(u8, internal, "__ffi_gen");
    }
    // `@ffi` AND `@c.ffi` HAVE NO ENTRY IN THE ALIAS TABLE, so this tail is
    // load-bearing, not a leftover — but it is also the place the two `ffi`
    // spellings come to look interchangeable, and they are NOT one operation:
    //
    //   @ffi("llabs")       binds the declaration to the external C symbol.
    //                       Measured: the body is discarded, the call returns 5.
    //   @comp.ffi("llabs")  resolves to `__ffi_gen` = the `ffi.gen` module
    //                       directive, which SCANS A C HEADER
    //                       (meta_directives.zig:83 registerFfiGen). Given a
    //                       symbol name it finds no header, registers nothing,
    //                       and the Idol body runs. Measured: returns 0.
    //
    // Both answer TRUE here, which is why nothing notices. 33 sites in
    // `lib/os/linux.id` write the `@ffi` binding form as `@comp.ffi(name, ret,
    // {args})`; `gate/dialect.sh` reports them as `divergent`. The real repair
    // is a `@comp.*` spelling for the BINDING that does not collide with
    // `ffi.gen` — it is not a rename, and it is not made here.
    return std.mem.eql(u8, name, "c.ffi") or std.mem.eql(u8, name, "ffi");
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
    // Check the directives array (handles meta.*, comp.* prefixed names)
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
        "foreign",
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

/// True when `@comp.*` / `@meta.*` must parse as a standalone module statement
/// (e.g. `@comp.define.derive(...)`, `@comp.pipeline(...)`) rather than an
/// expression call like `@comp.hint.fence()` at statement scope.
pub fn isStandaloneModuleStatement(name: []const u8) bool {
    for (directives) |entry| {
        if (std.mem.eql(u8, name, entry.public)) return true;
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
    // attributed declarations.
    const expression_combinators = [_][]const u8{
        "comp.match",
        "comp.tabulate",
        "comp.interpolate",
        "comp.zip",
        "comp.assert",
        "comp.compile.log",
        "comp.compile.warn",
        "comp.compile.error",
        "comp.each",            "meta.each",
        "comp.chain",
        "comp.map",             "meta.map",
        "comp.sweep",           "meta.sweep",
        "comp.grammar",
        "comp.template",
        "comp.generate",
        "comp.scheme",
        "comp.scheme.clauses",
        "comp.weave",
        "comp.product",         "meta.product",
        "comp.power",           "meta.power",
        "comp.powerset",        "meta.powerset",
        "comp.permute",         "meta.permute",
        "comp.choose",          "meta.choose",
        "comp.fixpoint",
        "comp.fanout",
        // @comp.derive.* expression combinators (G-060: must parse as expr in blocks)
        "comp.derive.power",    "meta.derive.power",
        "comp.derive.powerset",
        "comp.derive.choose",   "meta.derive.choose",
        "comp.derive.permute",  "meta.derive.permute",
        "comp.derive.product",  "meta.derive.product",
        "comp.derive.tensor",   "meta.derive.tensor",
        "comp.derive.nfold",    "meta.derive.nfold",
        "comp.derive",          "meta.derive",
        "comp.expand",          "meta.expand",
        "comp.ceiling",         "meta.ceiling",
        "comp.omni",            "meta.omni",
        "comp.stack",           "meta.stack",
        "comp.burst",           "meta.burst",
        "comp.transcend",       "meta.transcend",
        "comp.infinity",        "meta.infinity",
        "comp.hyper",           "meta.hyper",
        "comp.tower",           "meta.tower",
    };
    for (expression_combinators) |expr_name| {
        if (std.mem.eql(u8, name, expr_name)) return false;
    }
    // Declaration-attaching attributes must also return false here so they
    // associate with the following declaration instead of being parsed
    // as standalone module-level directives.
    if (isAttachingMetaAttribute(name) or isTypeLevelDeriveAttribute(name)) return false;
    if (isCHeaderImportDirective(name) or isCEmitDirective(name)) return false;

    return isModuleDirective(name);
}

/// True for metaprogramming attributes that attach to declarations (functions, types, etc.)
/// rather than being standalone module-level directives.
pub fn isAttachingMetaAttribute(name: []const u8) bool {
    const norm = normalizeCompileAttribute(name);
    return std.mem.eql(u8, norm, "compile.only") or
        std.mem.eql(u8, norm, "device") or
        std.mem.eql(u8, norm, "autodiff") or
        std.mem.eql(u8, norm, "differentiable") or
        std.mem.eql(u8, norm, "profile") or
        std.mem.eql(u8, norm, "unroll") or
        std.mem.eql(u8, norm, "inline") or
        std.mem.eql(u8, norm, "noinline") or
        std.mem.eql(u8, norm, "hot") or
        std.mem.eql(u8, norm, "cold") or
        std.mem.eql(u8, norm, "pure") or
        std.mem.eql(u8, norm, "noalloc") or
        std.mem.eql(u8, norm, "nopanic") or
        std.mem.eql(u8, norm, "raw") or
        std.mem.eql(u8, norm, "packed");
}

/// Normalize type-level derive attributes to canonical names.
/// Accepts `comp.*` and `meta.*` prefixes interchangeably.
pub fn normalizeTypeAttribute(name: []const u8) []const u8 {
    // Strip prefix to get canonical dotted form (comp.* is primary)
    const stripped = if (std.mem.startsWith(u8, name, "comp."))
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

/// True for `@derive` / `@comp.derive` / `@comp.derive.bundle` attributes that attach
/// to the following type declaration — not expression-position `@comp.derive.*` combinators.
pub fn isTypeLevelDeriveAttribute(name: []const u8) bool {
    const norm = normalizeTypeAttribute(name);
    return std.mem.eql(u8, norm, "derive") or std.mem.eql(u8, norm, "derive.bundle");
}

/// Normalize function/type compiler hint attributes under @comp.compile.* / @meta.compile.*
/// Accepts `comp.*` and `meta.*` prefixes interchangeably.
/// Canonical prefix is `comp.*` — returns bare dotted form `compile.only`, `inline`, etc.
pub fn normalizeCompileAttribute(name: []const u8) []const u8 {
    // Strip prefix to get canonical dotted form
    const stripped = if (std.mem.startsWith(u8, name, "comp."))
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
        "comp.derive.permute", "comp.each",            "comp.chain",
        "comp.match",          "comp.tabulate",        "comp.interpolate",
        "comp.zip",
    };
    for (combinators) |c| {
        if (std.mem.eql(u8, path, c)) return "combinators";
    }
    if (std.mem.startsWith(u8, path, "meta.emit.") or
        std.mem.startsWith(u8, path, "comp.emit."))
        return "emit";
    if (std.mem.eql(u8, path, "meta.burst") or
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
    if (std.mem.startsWith(u8, path, "comp.compile."))
        return "compile";
    if (std.mem.indexOf(u8, path, ".concepts.") != null or
        std.mem.startsWith(u8, path, "meta.type.") or
        std.mem.startsWith(u8, path, "comp.type.") or
        std.mem.startsWith(u8, path, "comp.types") or
        std.mem.startsWith(u8, path, "comp.has.") or
        std.mem.startsWith(u8, path, "comp.field.") or
        std.mem.eql(u8, path, "comp.fields") or
        std.mem.eql(u8, path, "comp.methods") or
        std.mem.eql(u8, path, "comp.variants") or
        std.mem.eql(u8, path, "comp.satisfies") or
        std.mem.eql(u8, path, "meta.catalog") or
        std.mem.eql(u8, path, "comp.catalog") or
        std.mem.eql(u8, path, "meta.ladder") or
        std.mem.eql(u8, path, "comp.ladder") or
        std.mem.startsWith(u8, path, "meta.agent.") or
        std.mem.startsWith(u8, path, "comp.agent.") or
        std.mem.eql(u8, path, "meta.str.starts.with") or
        std.mem.eql(u8, path, "meta.str.ends.with") or
        std.mem.eql(u8, path, "comp.str.splitcount") or
        std.mem.eql(u8, path, "comp.str.len") or
        std.mem.eql(u8, path, "comp.str.eq") or
        std.mem.eql(u8, path, "comp.str.join") or
        std.mem.eql(u8, path, "comp.diff"))
        return "introspection";
    if (std.mem.eql(u8, path, "comp.pipeline") or
        std.mem.eql(u8, path, "comp.foreign") or
        std.mem.eql(u8, path, "comp.ffi"))
        return "transform";
    return "other";
}

/// Prefer `comp.*` > `meta.*` when deduping catalog aliases.
fn catalogDisplayPriority(path: []const u8) u8 {
    if (std.mem.startsWith(u8, path, "comp.")) return 0;
    if (std.mem.startsWith(u8, path, "meta.")) return 1;
    return 3;
}

/// Newline-separated list of canonical parseable `@comp.*` paths, optionally filtered by category.
/// Aliases (`@meta.*`) dedupe by internal handler — one row per construct.
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

/// Scaling ladder reference for agents. It mirrored `lib/meta/hierarchy.id`,
/// which this branch deletes, so this is now the sole owner of the ladder text.
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

/// Stable routes for agents invoking the historical hook surface.
pub fn agentHooksText() []const u8 {
    return
    \\AGENTS.md — repository entry and mechanical preflight
    \\docs/spec/law.md — supreme law
    \\docs/spec/constitution.md — structured expansion of the supreme law
    \\CLAUDE.md — operative projection
    \\docs/spec/grammar.md — grammar projection
    \\.agents/AGENT_CANONICAL.md — stable path router
    \\.agents/AGENT_COORDINATION.md — ownership and serialized gates
    \\docs/bootstrap.md — executed compiler frontier
    \\gaps/GAP-0NN.md — open obligations; verify the live census
    \\MCP duo_agent_session_start and duo_dev_claim_* — live state and ownership
    \\Canonical implementation is .id; new canonical .id is admitted; host code is migration debt
    \\The process world (os.execute / os.env / process.capture) is canonical; the legacy `lib/script.id` home is frozen debt until GAP-157
    \\Missing relation or world vocabulary is SEMANTIC-VOCABULARY-BLOCKED
    ;
}

/// Duplication-prevention protocol for 5+ parallel agents.
pub fn agentDedupeText() []const u8 {
    return
    \\1. Read AGENTS.md, docs/spec/constitution.md, and docs/bootstrap.md
    \\2. Inspect exact HEAD, dirty state, live claims, open gaps, and current evidence
    \\3. Claim exact paths before editing and never absorb another owner's work
    \\4. Request an owner's fact or projection instead of creating a substitute authority
    \\5. Add no syntax, semantic namespace, predicate helper, or host semantic owner
    \\6. Run the focused gate, then serialize any required aggregate under the repository lock
    \\7. Bind every claim to the exact tree, command, inner outcome, and evidence
    \\8. Commit explicit owned paths and release only claims held by this session
    ;
}

/// Cross-session expressiveness / performance / native-lowering gaps index.
pub fn agentGapsText() []const u8 {
    return
    \\gaps/GAP-0NN.md — canonical numbered obligations
    \\MCP duo_agent_gaps_read and duo_agent_gaps_update — live gap projection
    \\docs/bootstrap.md — earliest host-owned production boundary
    \\docs/performance.md — FTCFTW evidence protocol
    \\Before work: verify the exact tree, live claims, production owner, and current gate outcome
    \\If an owner or admitted vocabulary is missing, record the blocker and do not invent one
    ;
}

/// Helper function to compute the exponential complexity class for a combinator path.
/// Returns a tuple (base_complexity, has_derive_field, is_module_directive).
pub const ComplexityInfo = struct {
    complexity: []const u8, // e.g., "O(n)", "O(n2)", "O(n^k)", "O(2^n)", "O(n!)"
    has_derive_multiplier: bool, // true if there's a derive^fields component (f)
    is_module_directive: bool, // true if it emits code (burst, transcend, etc.)
    base_combinator: []const u8, // e.g., "map", "product", "tensor", "nfold"
};

/// Get complexity information for a @comp.* path to help agents understand scale.
pub fn combinatorComplexity(path: []const u8) ?ComplexityInfo {
    // Strip prefix to get the core path
    const core = if (std.mem.startsWith(u8, path, "comp."))
        path["comp.".len..]
    else if (std.mem.startsWith(u8, path, "meta."))
        path["meta.".len..]
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
    else
        path;

    for (next_level) |nl| {
        if (std.mem.endsWith(u8, core, nl.name) or std.mem.eql(u8, core, nl.name)) {
            return nl.suggestions;
        }
    }

    return "@comp.product, @comp.burst";
}

/// Current grammar routes exposed through the historical hook surface.
pub fn agentGrammarText() []const u8 {
    return
    \\docs/spec/law.md — supreme law
    \\docs/spec/constitution.md — structured expansion of the supreme law
    \\docs/spec/grammar.md — grammar projection
    \\GAP-134 and GAP-145 — generated grammar roles and lexical identity blockers
    \\Lexer owns token identity, grammar owns role, parser owns recognition and provenance
    \\Do not infer grammar or semantic meaning from token text or parser-local spelling lists
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

/// Exponential scaling reference for agents (O(1) -> O(n^k) multiplier).
pub fn agentMultiplierText() []const u8 {
    return
    \\O(1)   -> authorship (manual code)
    \\O(n)   -> map/sweep/each/derive
    \\O(n^2) -> product/burst
    \\O(n^3) -> tensor/transcend
    \\O(n^k) -> nfold/tower/grammar
    \\O(2^n) -> power/powerset
    \\O(n!)  -> permute
    \\
    \\Leverage @comp.* to move authoring work from O(n) to O(1) input.
    ;
}

fn goalContains(goal: []const u8, needle: []const u8) bool {
    var buf: [512]u8 = undefined;
    if (goal.len > buf.len) return std.mem.indexOf(u8, goal, needle) != null;
    const lower = std.ascii.lowerString(&buf, goal);
    return std.mem.indexOf(u8, lower, needle) != null;
}

/// Goal-specific multiplier hint (mirrors lib/agent.id multiplier_for).
pub fn agentMultiplierFor(goal: []const u8) []const u8 {
    if (goalContains(goal, "trait") or goalContains(goal, "derive") or goalContains(goal, "impl"))
        return "@comp.derive / @comp.derive.all / @comp.derive.bundle — O(types×fields)";
    if (goalContains(goal, "pair") or goalContains(goal, "cartesian") or goalContains(goal, "product"))
        return "@comp.product / @comp.derive.product — O(types²)";
    if (goalContains(goal, "triple") or goalContains(goal, "tensor"))
        return "@comp.tensor / @comp.derive.tensor — O(types³)";
    if (goalContains(goal, "subset") or goalContains(goal, "powerset") or goalContains(goal, "power"))
        return "@comp.power / @comp.derive.power — O(2^n)";
    if (goalContains(goal, "combination") or goalContains(goal, "choose") or goalContains(goal, "fixed subset"))
        return "@comp.choose / @comp.derive.choose — O(n choose k), controlled exponential subset generation";
    if (goalContains(goal, "permute") or goalContains(goal, "order"))
        return "@comp.permute / @comp.derive.permute — O(n!)";
    if (goalContains(goal, "compose") or goalContains(goal, "chain") or goalContains(goal, "nest") or
        goalContains(goal, "combine") or goalContains(goal, "glue") or goalContains(goal, "cascade") or
        goalContains(goal, "exponential"))
        return "@comp.each(src, fn) / @comp.chain(src, fn) — composition glue: split any combinator output into fragments, re-expand each; chains any two combinators (closes the algebra)";
    if (goalContains(goal, "module") or goalContains(goal, "file") or goalContains(goal, "emit"))
        return "@comp.burst → @comp.transcend → @comp.infinity → @comp.hyper";
    if (goalContains(goal, "pipeline") or goalContains(goal, "fuse"))
        return "@comp.pipeline({ variants = ... }) — typed kernel family";
    if (goalContains(goal, "template") or goalContains(goal, "parametric"))
        return "@comp.template / @comp.generate — O(n) or O(ops×types) native C fragments; chain with @comp.each";
    if (goalContains(goal, "scheme") or goalContains(goal, "declarative"))
        return "@comp.scheme(declarations, template) — pipe-separated type/fn units → O(units) C";
    if (goalContains(goal, "grammar") or goalContains(goal, "ebnf") or goalContains(goal, "language"))
        return "@comp.grammar(spec, fn) — O(b^d) EBNF expansion";
    if (goalContains(goal, "weave") or goalContains(goal, "cross-module") or goalContains(goal, "cross module"))
        return "@comp.weave(module, concept, fn) — O(N×M) cross-module concept sweep";
    if (goalContains(goal, "dedupe") or goalContains(goal, "duplicate") or goalContains(goal, "coord"))
        return "read .agents/AGENT_COORDINATION.md; claim before edit";
    if (goalContains(goal, "gap") or goalContains(goal, "script") or goalContains(goal, "ergonomic"))
        return ".agents/AGENT_COORDINATION.md#cross-agent-gap-buffer; record finding before adding one-off tooling";
    return "@comp.map / @comp.sweep — O(types); stack @comp.ceiling / @comp.omni for quadratic+";
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

test "meta_module: canonical @meta.* builtins" {
    try std.testing.expectEqualStrings("__comptimemap", resolveBuiltin("meta.map").?);
    try std.testing.expectEqualStrings("__derivemap", resolveBuiltin("meta.derive").?);
    // `__schema`, `__run`, `__pipeline`, `__fieldsmap` were deleted (GAP-234
    // 1b): each appeared in this table and NOWHERE else — no sema arm, no
    // codegen arm, no comptime arm — so every one parsed, passed the blanket
    // `__` admission, and was consumed by nobody. The negatives keep the dead
    // aliases from drifting back in, per the `meta.register.derive` precedent
    // below; the parser's compiler-namespace guard (GAP-234 1a) is what makes
    // these deletions a truthful refusal at the site instead of a silent
    // reroute into macro expansion.
    try std.testing.expect(resolveBuiltin("meta.fields.map") == null);
    try std.testing.expect(resolveBuiltin("comp.fields.map") == null);
    try std.testing.expect(resolveBuiltin("comp.schema") == null);
    try std.testing.expect(resolveBuiltin("comp.pipeline") == null);
    try std.testing.expect(resolveBuiltin("comp.run") == null);
    try std.testing.expectEqualStrings("__register_derive", resolveBuiltin("comp.register.derive").?);
    // `meta.register.derive` was deleted: no `.id` site and no host caller ever
    // named it. The negative keeps the alias from drifting back in.
    try std.testing.expect(resolveBuiltin("meta.register.derive") == null);
    try std.testing.expectEqualStrings("__comptimemap", resolveBuiltin("meta.sweep").?);
    try std.testing.expectEqualStrings("__comptimeeach", resolveBuiltin("comp.chain").?);
    try std.testing.expectEqualStrings("__comptimeeach", resolveBuiltin("meta.each").?);
}

test "meta_module: direct module directives remain canonical" {
    try std.testing.expect(isModuleDirective("pipeline"));
    try std.testing.expect(isModuleDirective("foreign"));
    // `@rewrite` was programmer-written optimizer syntax whose registry no
    // instruction selection ever read (`HPLS` §90, §105). Deleted, and this row
    // is the negative control that keeps it deleted.
    try std.testing.expect(!isModuleDirective("rewrite"));
    try std.testing.expectEqualStrings("pipeline", normalizeDirective("pipeline"));
}

test "meta_module: agentMultiplierFor goal hints" {
    const hint = agentMultiplierFor("compose exponential cascade");
    try std.testing.expect(std.mem.indexOf(u8, hint, "@comp.each") != null);
    try std.testing.expect(std.mem.indexOf(u8, agentMultiplierFor("derive traits"), "@comp.derive") != null);
}

test "meta_module: directive normalization" {
    try std.testing.expectEqualStrings("pipeline", normalizeDirective("comp.pipeline"));
    try std.testing.expectEqualStrings("meta.pipeline", normalizeDirective("meta.pipeline"));
    try std.testing.expectEqualStrings("define.derive", normalizeDirective("meta.define.derive"));
    try std.testing.expectEqualStrings("derive.all", normalizeDirective("comp.derive.all"));
    try std.testing.expect(directiveMatches("comp.derive.all", "derive.all"));
    try std.testing.expect(isMetaAttribute("meta.define.derive"));
    // G-060: derive combinators are expression-position, not block directives
    try std.testing.expect(!isMetaAttribute("comp.derive.power"));
    try std.testing.expect(!isMetaAttribute("meta.derive.power"));
    try std.testing.expectEqualStrings("__metaexpand", resolveBuiltin("meta.expand").?);
    try std.testing.expectEqualStrings("__metaexpand", resolveBuiltin("meta.pow").?);
    try std.testing.expectEqualStrings("__metaceiling", resolveBuiltin("meta.ceiling").?);
    try std.testing.expectEqualStrings("__metaomni", resolveBuiltin("meta.omni").?);
    try std.testing.expectEqualStrings("__metaomni", resolveBuiltin("meta.stack").?);
    try std.testing.expectEqualStrings("__metaburst", resolveBuiltin("meta.burst").?);
    try std.testing.expectEqualStrings("burst", normalizeDirective("meta.burst"));
    try std.testing.expectEqualStrings("emit.omni", normalizeDirective("meta.emit.omni"));
    try std.testing.expectEqualStrings("wasm", normalizeDirective("comp.wasm"));
    try std.testing.expectEqualStrings("__comptimemap", resolveBuiltin("meta.sweep").?);
    try std.testing.expectEqualStrings("derive.bundle", normalizeTypeAttribute("meta.derive.bundle"));
    try std.testing.expectEqualStrings("derive.bundle", normalizeTypeAttribute("comp.derive.bundle"));
    try std.testing.expect(isTypeLevelDeriveAttribute("derive"));
    try std.testing.expect(isTypeLevelDeriveAttribute("comp.derive"));
    try std.testing.expect(isTypeLevelDeriveAttribute("meta.derive.bundle"));
    try std.testing.expect(isTypeLevelDeriveAttribute("comp.derive.bundle"));
    try std.testing.expect(!isTypeLevelDeriveAttribute("comp.derive.power"));
    try std.testing.expect(!isMetaAttribute("comp.derive.bundle"));
    // The self-describing family is DELETED. `@comp.catalog`, `@comp.ladder`
    // and `@comp.agent.*` described the directive namespace, not any program,
    // so they had no referent left once the namespace they enumerate stopped
    // being authority. These negatives are what keep them deleted.
    try std.testing.expect(resolveBuiltin("comp.catalog") == null);
    try std.testing.expect(resolveBuiltin("comp.ladder") == null);
    try std.testing.expect(resolveBuiltin("comp.agent.catalog") == null);
    try std.testing.expect(resolveBuiltin("comp.agent.hooks") == null);
    try std.testing.expect(resolveBuiltin("comp.agent.dedupe") == null);
    try std.testing.expect(resolveBuiltin("comp.agent.gaps") == null);
    try std.testing.expect(catalogPathParseable("comp.map"));
    try std.testing.expect(isCHeaderImportDirective("comp.c.import"));
    try std.testing.expect(isCHeaderImportDirective("c.import"));
    // `meta.c.include` was deleted with the rest of the referent-free `meta.*`
    // rows; the negative is what keeps the alias from drifting back.
    try std.testing.expect(!isCHeaderImportDirective("meta.c.include"));
    try std.testing.expect(!isCHeaderImportDirective("comp.c.export"));
    try std.testing.expect(isCEmitDirective("comp.c.emit"));
    try std.testing.expect(!isMetaAttribute("comp.c.import"));
}

test "meta_module: catalog lists canonical comp paths (deduped)" {
    const alloc = std.testing.allocator;
    const catalog = try formatCatalog(alloc);
    defer alloc.free(catalog);
    try std.testing.expect(std.mem.indexOf(u8, catalog, "comp.map") != null);
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
    try std.testing.expectEqualStrings("define", catalogCategory("comp.derive.all"));
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
    // The fallback may name only LIVE combinators. It used to answer
    // `@comp.ladder()`, which this branch deletes -- advice for a directive
    // with no handler is the host publishing authority it no longer has.
    try std.testing.expectEqualStrings("@comp.product, @comp.burst", suggestNextCombinators("comp.unknown"));
    try std.testing.expect(resolveBuiltin("comp.product") != null);
    try std.testing.expect(resolveBuiltin("comp.burst") != null);
}

test "meta_module: every spelling of one operation gets one answer" {
    // ONE OPERATION, ONE ANSWER. Each row is a set of spellings the alias table
    // resolves to a single internal hook. A predicate that says yes to some of
    // a row and no to the rest is the shape of the `@comp.c.emit` defect: the
    // function compiles, the payload is discarded, and `idol check` is clean.
    const emit = [_][]const u8{ "comp.c.emit", "c.emit", "meta.c.emit", "emit" };
    // `comp.emit` was a fourth spelling of the SAME `__emit` hook with zero
    // `.id` users. Deleted; the negative keeps it from drifting back.
    try std.testing.expect(!isCEmitDirective("comp.emit"));
    for (emit) |s| try std.testing.expect(isCEmitDirective(s));
    try std.testing.expect(!isCEmitDirective("comp.c.emit.file"));
    try std.testing.expect(!isCEmitDirective("comp.c.include"));

    const include = [_][]const u8{ "comp.c.include", "c.include", "comp.c.import", "c.import", "cinclude" };
    for (include) |s| try std.testing.expect(isCHeaderImportDirective(s));
    try std.testing.expect(!isCHeaderImportDirective("comp.c.emit"));

    // `__c_call` BELONGS IN THE ATTACHING SET. Without it `@comp.c.call` on a
    // declaration was not an attribute at all — it resolved as a module
    // directive and the function body vanished, compiling to `return 0` while
    // `@c.call` in the same position raised "unknown or misplaced attribute".
    const attaching = [_][]const u8{
        "comp.c.export", "c.export",  "meta.c.export",
        "comp.c.type",   "c.type",    "comp.c.link",
        "c.link",        "comp.c.call", "c.call",
    };
    for (attaching) |s| try std.testing.expect(isAttachingCInterfaceAttribute(s));
    // Negative controls: the standalone C-interface statements must NOT attach,
    // or every `@comp.c.emit(...)` becomes an attribute on the next declaration.
    try std.testing.expect(!isAttachingCInterfaceAttribute("comp.c.emit"));
    try std.testing.expect(!isAttachingCInterfaceAttribute("comp.c.include"));
    try std.testing.expect(!isAttachingCInterfaceAttribute("comp.map"));

    // `@ffi` AND `@comp.ffi` ARE NOT ONE OPERATION, measured by running:
    // `@ffi("llabs")` binds the external symbol (answer 5); `@comp.ffi("llabs")`
    // is `ffi.gen`, scans for a C HEADER, finds none, and lets the Idol body run
    // (answer 0). Both answer true here — that is recorded, not endorsed, and it
    // is why `gate/dialect.sh` reports the `@comp.ffi(name, ret, {args})` shape
    // as `divergent` rather than renaming it.
    try std.testing.expect(isAttachingCInterfaceAttribute("ffi"));
    try std.testing.expect(isAttachingCInterfaceAttribute("comp.ffi"));
    try std.testing.expect(!std.mem.eql(u8, resolveBuiltin("comp.ffi").?, "__c_call"));
    try std.testing.expectEqualStrings("__ffi_gen", resolveBuiltin("comp.ffi").?);
    try std.testing.expect(resolveBuiltin("ffi") == null);
}

test "meta_module: the alias table admits no spelling it cannot resolve back" {
    // A DUPLICATE SPELLING IS A LATENT DEFECT, so the ones that exist should at
    // least be reachable from the canonical name. Every `comp.*` public entry
    // must resolve, and its internal must map back to a `comp.*` name — the
    // property `publicNameForInternal` exists to provide and that
    // `gate/dialect.sh` relies on when it names the canonical spelling.
    var checked: usize = 0;
    for (builtins) |entry| {
        if (!std.mem.startsWith(u8, entry.public, "comp.")) continue;
        checked += 1;
        try std.testing.expectEqualStrings(entry.internal, resolveBuiltin(entry.public).?);
        const back = publicNameForInternal(entry.internal) orelse return error.NoPublicName;
        try std.testing.expect(std.mem.startsWith(u8, back, "comp."));
    }
    // A zero count here would make the loop above a vacuous pass — the same
    // failure `gate/all.sh` refuses for a gate that examined no files.
    try std.testing.expect(checked > 100);
}
