//! Emit `lib/std/token/grammarrole.id` from `src/grammar_roles.zig`.
const std = @import("std");
const grammar_roles = @import("grammar_roles.zig");
const lexer = @import("lexer.zig");

pub const PROVENANCE = "src/grammar_role_gen.zig";

pub fn emitGrammarRoleFile(alloc: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (!std.mem.eql(u8, dir, ".")) {
            const cwd = std.Io.Dir.cwd();
            try cwd.createDirPath(io, dir);
        }
    }
    var buf: std.Io.Writer.Allocating = .init(alloc);
    defer buf.deinit();
    try emitGrammarRole(&buf.writer);
    const cwd = std.Io.Dir.cwd();
    try std.Io.Dir.writeFile(cwd, io, .{ .sub_path = path, .data = buf.written() });
}

fn emitGrammarRole(w: *std.Io.Writer) !void {
    const enum_info = @typeInfo(lexer.TokenKind).@"enum";
    try w.print(
        \\-- GENERATED from src/grammar_role_gen.zig — do not edit by hand.
        \\-- Regenerate: duo token-tables emit
        \\-- Canonical grammar-role facts: src/grammar_roles.zig
        \\
        \\grammar = req "std.compiler.token"
        \\
        \\ROLECOUNT = {d}
        \\KINDEOF = {d}
        \\
    , .{ enum_info.field_names.len, @intFromEnum(lexer.TokenKind.eof) });

    try emitBoolTable(w, "BEGINEXPR", &grammar_roles.rows, "begin_expr");
    try emitBoolTable(w, "PREFIX", &grammar_roles.rows, "prefix");
    try emitBoolTable(w, "POSTFIX", &grammar_roles.rows, "postfix");
    try emitBoolTable(w, "PARAMETER", &grammar_roles.rows, "parameter");
    try emitBoolTable(w, "LITERALKIND", &grammar_roles.rows, "literal_kind");
    try emitBoolTable(w, "COMPATONLY", &grammar_roles.rows, "compat_only");
    try emitI64Table(w, "PRECEDENCE", &grammar_roles.rows, "precedence");
    try emitI64Table(w, "ASSOC", &grammar_roles.rows, "assoc");

    try w.writeAll(
        \\
        \\rolebeginexpr: bool = (kind: i64)
        \\    kind >= 0 and kind < ROLECOUNT and BEGINEXPR[kind + 1] != 0
        \\end
        \\
        \\roleprefix: bool = (kind: i64)
        \\    kind >= 0 and kind < ROLECOUNT and PREFIX[kind + 1] != 0
        \\end
        \\
        \\rolepostfix: bool = (kind: i64)
        \\    kind >= 0 and kind < ROLECOUNT and POSTFIX[kind + 1] != 0
        \\end
        \\
        \\roleparameter: bool = (kind: i64)
        \\    kind >= 0 and kind < ROLECOUNT and PARAMETER[kind + 1] != 0
        \\end
        \\
        \\roleliteral: bool = (kind: i64)
        \\    kind >= 0 and kind < ROLECOUNT and LITERALKIND[kind + 1] != 0
        \\end
        \\
        \\rolecompatonly: bool = (kind: i64)
        \\    kind >= 0 and kind < ROLECOUNT and COMPATONLY[kind + 1] != 0
        \\end
        \\
        \\roleprecedence: i64 = (kind: i64)
        \\    if kind < 0 or kind >= ROLECOUNT
        \\        0
        \\    else
        \\        PRECEDENCE[kind + 1]
        \\    end
        \\end
        \\
        \\roleassoc: i64 = (kind: i64)
        \\    if kind < 0 or kind >= ROLECOUNT
        \\        0
        \\    else
        \\        ASSOC[kind + 1]
        \\    end
        \\end
        \\
    );
}

fn emitBoolTable(
    w: *std.Io.Writer,
    name: []const u8,
    rows: []const grammar_roles.RoleRow,
    comptime field: []const u8,
) !void {
    try w.print("{s} = {{\n", .{name});
    for (rows, 0..) |row, i| {
        const v = @field(row, field);
        try w.print("    {s}{d},\n", .{ if (i == 0) "" else "", @intFromBool(v) });
    }
    try w.writeAll("}\n");
}

fn emitI64Table(
    w: *std.Io.Writer,
    name: []const u8,
    rows: []const grammar_roles.RoleRow,
    comptime field: []const u8,
) !void {
    try w.print("{s} = {{\n", .{name});
    for (rows, 0..) |row, i| {
        const v = @field(row, field);
        const n: i64 = switch (@TypeOf(v)) {
            i8 => @intCast(v),
            grammar_roles.Associativity => @intFromEnum(v),
            else => @compileError("unsupported field"),
        };
        try w.print("    {s}{d},\n", .{ if (i == 0) "" else "", n });
    }
    try w.writeAll("}\n");
}

test "grammar role generator includes begin_expr lookup" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try emitGrammarRole(&aw.writer);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "rolebeginexpr") != null);
}

test "grammar role generator preserves token cardinality and eof identity" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try emitGrammarRole(&aw.writer);

    const enum_info = @typeInfo(lexer.TokenKind).@"enum";
    var count_buf: [32]u8 = undefined;
    const count_text = try std.fmt.bufPrint(&count_buf, "ROLECOUNT = {d}", .{enum_info.field_names.len});
    var eof_buf: [32]u8 = undefined;
    const eof_text = try std.fmt.bufPrint(&eof_buf, "KINDEOF = {d}", .{@intFromEnum(lexer.TokenKind.eof)});
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), count_text) != null);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), eof_text) != null);
}

test "grammar role generator: emit when EMIT_GRAMMAR_ROLE set" {
    const path_z = std.c.getenv("EMIT_GRAMMAR_ROLE") orelse return;
    const path = std.mem.span(path_z);
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    try emitGrammarRoleFile(std.testing.allocator, threaded.io(), path);
}
