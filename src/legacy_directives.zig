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
    .{ .public = "comptime_for", .internal = "__comptimefor", .canonical = "comp.for" },
    .{ .public = "compile_log", .internal = "__comptimeprint", .canonical = "comp.compile.log" },
    .{ .public = "static_assert", .internal = "__static_assert", .canonical = "comp.assert" },
    .{ .public = "typeof", .internal = "__typeof", .canonical = "comp.typeof" },
    .{ .public = "type_name", .internal = "__type_name", .canonical = "comp.type.name" },
    .{ .public = "type_id", .internal = "__type_id", .canonical = "comp.type.id" },
    .{ .public = "is_type", .internal = "__is_type", .canonical = "comp.type.is" },
    .{ .public = "fields", .internal = "__fields", .canonical = "comp.fields" },
    .{ .public = "methods", .internal = "__methods", .canonical = "comp.methods" },
    .{ .public = "concept_methods", .internal = "__concept_methods", .canonical = "comp.concepts.methods" },
    .{ .public = "variants", .internal = "__variants", .canonical = "comp.variants" },
    .{ .public = "satisfies", .internal = "__satisfies", .canonical = "comp.satisfies" },
    .{ .public = "bitfield", .internal = "__bitfield", .canonical = "comp.bit.field" },
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
