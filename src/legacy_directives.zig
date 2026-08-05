/// Parser-only legacy flat/underscore @-directive aliases.
/// Each underscore form MUST carry a `canonical` dotted `@comp.*` replacement;
/// `meta_module` tests scan this table so flat names cannot bypass the catalog guard.
const std = @import("std");
const meta_module = @import("meta_module.zig");

pub const Entry = struct {
    public: []const u8,
    internal: []const u8,
    /// Dotted `@comp.*` (or `hot`) replacement shown in deprecation warnings.
    canonical: ?[]const u8 = null,
};

pub const entries = [_]Entry{
    .{ .public = "constexpr", .internal = "__constexpr" },
    // Legacy underscore spellings — each maps to canonical @comp.* (warn on use).
    .{ .public = "comptime_if", .internal = "__comptimeif", .canonical = "comp.if" },
    .{ .public = "comptimeif", .internal = "__comptimeif" },
    .{ .public = "comptime_fold", .internal = "__comptimefold", .canonical = "comp.fold" },
    .{ .public = "comptimefold", .internal = "__comptimefold" },
    .{ .public = "comptime_for", .internal = "__comptimefor", .canonical = "comp.for" },
    .{ .public = "comptimefor", .internal = "__comptimefor" },
    .{ .public = "comptime_print", .internal = "__comptimeprint", .canonical = "comp.compile.log" },
    .{ .public = "comptimeprint", .internal = "__comptimeprint" },
    .{ .public = "comptime_warn", .internal = "__comptimewarn", .canonical = "comp.compile.warn" },
    .{ .public = "comptimewarn", .internal = "__comptimewarn" },
    .{ .public = "compile_log", .internal = "__comptimeprint", .canonical = "comp.compile.log" },
    .{ .public = "compile_error", .internal = "__comptimeerror", .canonical = "comp.compile.error" },
    .{ .public = "comptime_error", .internal = "__comptimeerror", .canonical = "comp.compile.error" },
    .{ .public = "comptimeerror", .internal = "__comptimeerror" },
    .{ .public = "static_assert", .internal = "__static_assert", .canonical = "comp.assert" },
    .{ .public = "typeinfo", .internal = "__typeinfo", .canonical = "comp.type.info" },
    .{ .public = "typeof", .internal = "__typeof", .canonical = "comp.typeof" },
    .{ .public = "type_name", .internal = "__type_name", .canonical = "comp.type.name" },
    .{ .public = "type_id", .internal = "__type_id", .canonical = "comp.type.id" },
    .{ .public = "is_type", .internal = "__is_type", .canonical = "comp.type.is" },
    .{ .public = "fields", .internal = "__fields", .canonical = "comp.fields" },
    .{ .public = "methods", .internal = "__methods", .canonical = "comp.methods" },
    .{ .public = "concept_methods", .internal = "__concept_methods", .canonical = "comp.concepts.methods" },
    .{ .public = "variants", .internal = "__variants", .canonical = "comp.variants" },
    .{ .public = "has_field", .internal = "__has_field", .canonical = "comp.has.field" },
    .{ .public = "has_method", .internal = "__has_method", .canonical = "comp.has.method" },
    .{ .public = "has_metamethod", .internal = "__has_metamethod", .canonical = "comp.has.metamethod" },
    .{ .public = "satisfies", .internal = "__satisfies", .canonical = "comp.satisfies" },
    .{ .public = "field_type", .internal = "__field_type", .canonical = "comp.field.type" },
    .{ .public = "field_offset", .internal = "__field_offset", .canonical = "comp.field.offset" },
    .{ .public = "field_size", .internal = "__field_size", .canonical = "comp.field.size" },
    .{ .public = "embed_str", .internal = "__embed_str", .canonical = "comp.embed.str" },
    .{ .public = "embed_file", .internal = "__embed_file", .canonical = "comp.embed.file" },
    .{ .public = "make_type", .internal = "__make_type", .canonical = "comp.make.type" },
    .{ .public = "as_type", .internal = "__as_type", .canonical = "comp.as.type" },
    .{ .public = "bitfield", .internal = "__bitfield", .canonical = "comp.bit.field" },
    .{ .public = "union", .internal = "__union", .canonical = "comp.union" },
    .{ .public = "select", .internal = "__select", .canonical = "comp.select" },
    .{ .public = "likely", .internal = "__likely", .canonical = "comp.hint.likely" },
    .{ .public = "unlikely", .internal = "__unlikely", .canonical = "comp.hint.unlikely" },
    .{ .public = "prefetch", .internal = "__prefetch", .canonical = "comp.hint.prefetch" },
    .{ .public = "assume", .internal = "__assume", .canonical = "comp.hint.assume" },
    .{ .public = "unreachable", .internal = "__unreachable", .canonical = "comp.hint.unreachable" },
    .{ .public = "trap", .internal = "__trap", .canonical = "comp.hint.trap" },
    .{ .public = "fence", .internal = "__fence", .canonical = "comp.hint.fence" },
    .{ .public = "ctz", .internal = "__ctz", .canonical = "comp.bit.ctz" },
    .{ .public = "clz", .internal = "__clz", .canonical = "comp.bit.clz" },
    .{ .public = "popcount", .internal = "__popcount", .canonical = "comp.bit.popcount" },
    .{ .public = "bswap", .internal = "__bswap", .canonical = "comp.bit.bswap" },
    .{ .public = "rotl", .internal = "__rotl", .canonical = "comp.bit.rotl" },
    .{ .public = "rotr", .internal = "__rotr", .canonical = "comp.bit.rotr" },
    .{ .public = "bitcast", .internal = "__bitcast", .canonical = "comp.bit.bitcast" },
    .{ .public = "volatile", .internal = "__volatile", .canonical = "comp.hint.volatile" },
    .{ .public = "hot_path", .internal = "__hot_path", .canonical = "hot" },
};

pub fn resolvePublic(name: []const u8) ?Entry {
    for (entries) |entry| {
        if (std.mem.eql(u8, name, entry.public)) return entry;
    }
    return null;
}

test "legacy_directives: underscore public names require canonical mapping" {
    for (entries) |entry| {
        if (std.mem.indexOfScalar(u8, entry.public, '_') != null) {
            try std.testing.expect(entry.canonical != null);
        }
    }
}

test "legacy_directives: canonical @comp.* forms registered in meta_module" {
    for (entries) |entry| {
        const canonical = entry.canonical orelse continue;
        if (!std.mem.startsWith(u8, canonical, "comp.")) continue;
        try std.testing.expect(meta_module.resolveBuiltin(canonical) != null);
    }
}

test "legacy_directives: no underscore in canonical paths" {
    for (entries) |entry| {
        const canonical = entry.canonical orelse continue;
        try std.testing.expect(std.mem.indexOfScalar(u8, canonical, '_') == null);
    }
}
