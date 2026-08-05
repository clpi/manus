//! Pass 16 §12.2 — minimum Duo subset required to compile the next compiler stage.
const std = @import("std");

pub const SCHEMA_VERSION = "bootstrap-subset-v0";

pub const Feature = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    notes: []const u8,
};

/// Staged capability level — canonical Duo, not a permanent second language.
pub const features: []const Feature = &.{
    .{ .id = "BS-01", .title = "Bare functions and blocks", .status = "proven", .notes = "lib/std/compiler/lexer.duo" },
    .{ .id = "BS-02", .title = "Typed params i64/f64/bool/str", .status = "proven", .notes = "classify.duo + lexer" },
    .{ .id = "BS-03", .title = "Tables with identifier keys", .status = "proven", .notes = "Token/Lexer records" },
    .{ .id = "BS-04", .title = "req imports", .status = "proven", .notes = "std.compiler.* modules" },
    .{ .id = "BS-05", .title = "while/if/end control flow", .status = "proven", .notes = "lexer implementation" },
    .{ .id = "BS-06", .title = "string byte access", .status = "partial", .notes = "string.byte in lexer; native slice type open" },
    .{ .id = "BS-07", .title = "error()/pcall", .status = "partial", .notes = "lexer uses pcall; native error propagation open" },
    .{ .id = "BS-08", .title = "comptime @comp.* subset", .status = "partial", .notes = "classify.duo generation only" },
    .{ .id = "BS-09", .title = "native structs without boxing", .status = "partial", .notes = "typed paths; dynamic any still used in lexer" },
    .{ .id = "BS-10", .title = "file I/O for compiler driver", .status = "open", .notes = "required for S1 compiler binary" },
    .{ .id = "BS-11", .title = "object emission", .status = "open", .notes = "P16-M3" },
    .{ .id = "BS-12", .title = "freestanding runtime profile", .status = "open", .notes = "P16-WS22" },
    .{ .id = "BS-13", .title = "Embedded module record calls across req", .status = "partial", .notes = "Lexer.new + Lexer.next proven (MP4-B01 closed); production dispatch still host MP4-B02" },
};

pub const unsupported_now: []const []const u8 = &.{
    "full dynamic Lua compatibility in compiler hot path",
    "coroutines in compiler batch path",
    "GPU / WASM compiler backends in S1",
    "full semantic graph in Duo",
};

pub fn writeSubsetJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"stage\":\"S1\",\"features\":[", .{SCHEMA_VERSION});
    for (features, 0..) |f, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"title\":\"{s}\",\"status\":\"{s}\",\"notes\":\"{s}\"}}",
            .{ f.id, f.title, f.status, f.notes },
        );
    }
    try w.writeAll("],\"unsupported\":[");
    for (unsupported_now, 0..) |u, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("\"{s}\"", .{u});
    }
    try w.writeAll("]}");
}

test "bootstrap_subset: features tracked" {
    try std.testing.expect(features.len >= 10);
}
