/// Parser-only compatibility transport for flat/underscore @-directive aliases.
/// A dotted peer records an already-accepted compatibility route to the same
/// internal handler. It is never a canonical-source recommendation: prefix
/// compiler directives have no canonical Idol spelling.
const std = @import("std");
const meta_module = @import("meta_module.zig");

pub const Entry = struct {
    public: []const u8,
    internal: []const u8,
    /// Existing dotted compatibility peer, retained only to prove route identity.
    compatibility: ?[]const u8 = null,
};

pub const entries = [_]Entry{
    .{ .public = "constexpr", .internal = "__constexpr" },
    // Legacy underscore spellings retain their existing compatibility peers.
    .{ .public = "comptime_if", .internal = "__comptimeif", .compatibility = "comp.if" },
    .{ .public = "comptime_fold", .internal = "__comptimefold", .compatibility = "comp.fold" },
    .{ .public = "comptime_for", .internal = "__comptimefor", .compatibility = "comp.for" },
    .{ .public = "compile_log", .internal = "__comptimeprint", .compatibility = "comp.compile.log" },
    .{ .public = "static_assert", .internal = "__static_assert", .compatibility = "comp.assert" },
    .{ .public = "typeof", .internal = "__typeof", .compatibility = "comp.typeof" },
    .{ .public = "type_name", .internal = "__type_name", .compatibility = "comp.type.name" },
    .{ .public = "type_id", .internal = "__type_id", .compatibility = "comp.type.id" },
    .{ .public = "is_type", .internal = "__is_type", .compatibility = "comp.type.is" },
    .{ .public = "fields", .internal = "__fields", .compatibility = "comp.fields" },
    .{ .public = "methods", .internal = "__methods", .compatibility = "comp.methods" },
    .{ .public = "concept_methods", .internal = "__concept_methods", .compatibility = "comp.concepts.methods" },
    .{ .public = "satisfies", .internal = "__satisfies", .compatibility = "comp.satisfies" },
    .{ .public = "bitfield", .internal = "__bitfield", .compatibility = "comp.bit.field" },
    .{ .public = "likely", .internal = "__likely", .compatibility = "comp.hint.likely" },
    .{ .public = "unlikely", .internal = "__unlikely", .compatibility = "comp.hint.unlikely" },
    .{ .public = "prefetch", .internal = "__prefetch", .compatibility = "comp.hint.prefetch" },
    .{ .public = "fence", .internal = "__fence", .compatibility = "comp.hint.fence" },
    .{ .public = "ctz", .internal = "__ctz", .compatibility = "comp.bit.ctz" },
    .{ .public = "clz", .internal = "__clz", .compatibility = "comp.bit.clz" },
    .{ .public = "popcount", .internal = "__popcount", .compatibility = "comp.bit.popcount" },
    .{ .public = "bswap", .internal = "__bswap", .compatibility = "comp.bit.bswap" },
    .{ .public = "rotl", .internal = "__rotl", .compatibility = "comp.bit.rotl" },
    .{ .public = "volatile", .internal = "__volatile", .compatibility = "comp.hint.volatile" },
    .{ .public = "hot_path", .internal = "__hot_path", .compatibility = "hot" },
};

pub fn resolvePublic(name: []const u8) ?Entry {
    for (entries) |entry| {
        if (std.mem.eql(u8, name, entry.public)) return entry;
    }
    return null;
}

test "legacy_directives: underscore ingress retains an explicit compatibility peer" {
    for (entries) |entry| {
        if (std.mem.indexOfScalar(u8, entry.public, '_') != null) {
            try std.testing.expect(entry.compatibility != null);
        }
    }
}

test "legacy_directives: compatibility peers preserve the exact internal route" {
    var checked: usize = 0;
    for (entries) |entry| {
        const compatibility = entry.compatibility orelse continue;
        try std.testing.expectEqualStrings(entry.internal, meta_module.resolveBuiltin(compatibility) orelse return error.MissingCompatibilityRoute);
        checked += 1;
    }
    try std.testing.expect(checked > 0);
}
