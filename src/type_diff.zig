const std = @import("std");
const types = @import("types.zig");

const RT = types.ResolvedType;
const FieldType = types.FieldType;

/// Returns true when `new_t` is a safe widening of `old_t` (i32→i64, f32→f64, etc.).
pub fn isWidening(old_t: RT, new_t: RT) bool {
    if (old_t.eql(new_t)) return true;
    return switch (old_t) {
        .i8 => new_t == .i16 or new_t == .i32 or new_t == .i64 or new_t == .f64,
        .i16 => new_t == .i32 or new_t == .i64 or new_t == .f64,
        .i32 => new_t == .i64 or new_t == .f64,
        .u8 => new_t == .u16 or new_t == .u32 or new_t == .u64 or new_t == .i64 or new_t == .f64,
        .u16 => new_t == .u32 or new_t == .u64 or new_t == .i64 or new_t == .f64,
        .u32 => new_t == .u64 or new_t == .i64 or new_t == .f64,
        .f32 => new_t == .f64,
        .str => new_t == .any,
        else => false,
    };
}

fn findField(fields: []const FieldType, name: []const u8) ?FieldType {
    for (fields) |f| {
        if (std.mem.eql(u8, f.name, name)) return f;
    }
    return null;
}

fn defaultInit(rt: RT) []const u8 {
    return switch (rt) {
        .f32, .f64 => "0.0",
        .str => "\"\"",
        .bool => "false",
        else => "0",
    };
}

/// Generate a C migration function from `old_name`/`old_fields` to `new_name`/`new_fields`.
/// Struct typedefs are expected as `duo_<TypeName>` (Duo record alias convention).
pub fn emitMigration(
    alloc: std.mem.Allocator,
    old_name: []const u8,
    old_fields: []const FieldType,
    new_name: []const u8,
    new_fields: []const FieldType,
) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    const old_c = try std.fmt.allocPrint(alloc, "duo_{s}", .{old_name});
    defer alloc.free(old_c);
    const new_c = try std.fmt.allocPrint(alloc, "duo_{s}", .{new_name});
    defer alloc.free(new_c);

    var fn_name_buf: [128]u8 = undefined;
    const fn_name = std.fmt.bufPrint(&fn_name_buf, "duo_migrate_{s}_to_{s}", .{ old_name, new_name }) catch return error.OutOfMemory;

    try buf.appendSlice(alloc, "/* [type_diff] ");
    try buf.appendSlice(alloc, old_name);
    try buf.appendSlice(alloc, " → ");
    try buf.appendSlice(alloc, new_name);
    try buf.appendSlice(alloc, " */\n");
    try buf.appendSlice(alloc, "static ");
    try buf.appendSlice(alloc, new_c);
    try buf.appendSlice(alloc, " ");
    try buf.appendSlice(alloc, fn_name);
    try buf.appendSlice(alloc, "(const ");
    try buf.appendSlice(alloc, old_c);
    try buf.appendSlice(alloc, "* old) {\n    ");
    try buf.appendSlice(alloc, new_c);
    try buf.appendSlice(alloc, " neu = {0};\n");

    for (new_fields) |nf| {
        var cbuf: [64]u8 = undefined;
        const new_ct = nf.typ.c_type(&cbuf);

        if (findField(old_fields, nf.name)) |of| {
            if (of.typ.eql(nf.typ)) {
                try buf.appendSlice(alloc, "    neu.");
                try buf.appendSlice(alloc, nf.name);
                try buf.appendSlice(alloc, " = old->");
                try buf.appendSlice(alloc, nf.name);
                try buf.appendSlice(alloc, ";\n");
            } else if (isWidening(of.typ, nf.typ)) {
                try buf.appendSlice(alloc, "    neu.");
                try buf.appendSlice(alloc, nf.name);
                try buf.appendSlice(alloc, " = (");
                try buf.appendSlice(alloc, new_ct);
                try buf.appendSlice(alloc, ")old->");
                try buf.appendSlice(alloc, nf.name);
                try buf.appendSlice(alloc, ";  /* widening */\n");
            } else {
                try buf.appendSlice(alloc, "    neu.");
                try buf.appendSlice(alloc, nf.name);
                try buf.appendSlice(alloc, " = (");
                try buf.appendSlice(alloc, new_ct);
                try buf.appendSlice(alloc, ")");
                try buf.appendSlice(alloc, defaultInit(nf.typ));
                try buf.appendSlice(alloc, ";  /* type change, default */\n");
            }
        } else {
            try buf.appendSlice(alloc, "    neu.");
            try buf.appendSlice(alloc, nf.name);
            try buf.appendSlice(alloc, " = (");
            try buf.appendSlice(alloc, new_ct);
            try buf.appendSlice(alloc, ")");
            try buf.appendSlice(alloc, defaultInit(nf.typ));
            try buf.appendSlice(alloc, ";  /* added field */\n");
        }
    }

    try buf.appendSlice(alloc, "    return neu;\n}\n");
    return buf.toOwnedSlice(alloc);
}

test "type_diff: emit migration copies shared fields and defaults new" {
    const fields_v1 = [_]FieldType{
        .{ .name = "id", .typ = .i64 },
        .{ .name = "nick", .typ = .str },
    };
    const fields_v2 = [_]FieldType{
        .{ .name = "id", .typ = .i64 },
        .{ .name = "email", .typ = .str },
    };
    const code = try emitMigration(std.testing.allocator, "UserV1", &fields_v1, "UserV2", &fields_v2);
    defer std.testing.allocator.free(code);
    try std.testing.expect(std.mem.indexOf(u8, code, "neu.id = old->id") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "neu.email") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "added field") != null);
}
