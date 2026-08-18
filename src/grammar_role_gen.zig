//! Emit `lib/token/grammarrole.id` from `src/grammar_roles.zig`.
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
        \\# GENERATED from src/grammar_role_gen.zig — do not edit by hand.
        \\# Regenerate: idol token-tables emit
        \\# Bootstrap grammar-role projection: src/grammar_roles.zig
        \\
        \\grammar = req("std.compiler.token")
        \\
        \\ROLECOUNT = {d}
        \\KINDEOF = {d}
        \\
    , .{ enum_info.field_names.len, @backingInt(lexer.TokenKind.eof) });

    try emitBoolTable(w, "BEGINEXPR", &grammar_roles.rows, "begin_expr");
    try emitBoolTable(w, "prefix", &grammar_roles.rows, "prefix");
    try emitBoolTable(w, "postfix", &grammar_roles.rows, "postfix");
    try emitBoolTable(w, "parameter", &grammar_roles.rows, "parameter");
    try emitBoolTable(w, "LITERALKIND", &grammar_roles.rows, "literal_kind");
    try emitBoolTable(w, "quoted", &grammar_roles.rows, "quoted");
    try emitBoolTable(w, "projection", &grammar_roles.rows, "projection");
    try emitBoolTable(w, "BODYSTART", &grammar_roles.rows, "body_start");
    try emitBoolTable(w, "descriptor", &grammar_roles.rows, "descriptor");
    try emitBoolTable(w, "pattern", &grammar_roles.rows, "pattern");
    try emitBoolTable(w, "COMPATONLY", &grammar_roles.rows, "compat_only");
    try emitI64Table(w, "precedence", &grammar_roles.rows, "precedence");
    try emitI64Table(w, "assoc", &grammar_roles.rows, "assoc");

    try w.writeAll(
        \\
        \\rolebeginexpr: bool = (kind: i64)
        \\  kind >= 0 and kind < ROLECOUNT and BEGINEXPR(kind + 1) != 0
        \\
        \\roleprefix: bool = (kind: i64)
        \\  kind >= 0 and kind < ROLECOUNT and prefix(kind + 1) != 0
        \\
        \\rolepostfix: bool = (kind: i64)
        \\  kind >= 0 and kind < ROLECOUNT and postfix(kind + 1) != 0
        \\
        \\roleparameter: bool = (kind: i64)
        \\  kind >= 0 and kind < ROLECOUNT and parameter(kind + 1) != 0
        \\
        \\roleliteral: bool = (kind: i64)
        \\  kind >= 0 and kind < ROLECOUNT and LITERALKIND(kind + 1) != 0
        \\
        \\rolequoted: bool = (kind: i64)
        \\  kind >= 0 and kind < ROLECOUNT and quoted(kind + 1) != 0
        \\
        \\rolebodystart: bool = (kind: i64)
        \\  kind >= 0 and kind < ROLECOUNT and BODYSTART(kind + 1) != 0
        \\
        \\roledescriptor: bool = (kind: i64)
        \\  kind >= 0 and kind < ROLECOUNT and descriptor(kind + 1) != 0
        \\
        \\rolepattern: bool = (kind: i64)
        \\  kind >= 0 and kind < ROLECOUNT and pattern(kind + 1) != 0
        \\
        \\rolecompatonly: bool = (kind: i64)
        \\  kind >= 0 and kind < ROLECOUNT and COMPATONLY(kind + 1) != 0
        \\
        \\roleprecedence: i64 = (kind: i64)
        \\  if kind < 0 or kind >= ROLECOUNT
        \\    0
        \\  else
        \\    precedence(kind + 1)
        \\
        \\roleassoc: i64 = (kind: i64)
        \\  if kind < 0 or kind >= ROLECOUNT
        \\    0
        \\  else
        \\    assoc(kind + 1)
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
        try w.print("  {s}{d},\n", .{ if (i == 0) "" else "", @intFromBool(v) });
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
            grammar_roles.Associativity => @backingInt(v),
            else => @compileError("unsupported field"),
        };
        try w.print("  {s}{d},\n", .{ if (i == 0) "" else "", n });
    }
    try w.writeAll("}\n");
}

test "grammar role generator includes begin_expr lookup" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try emitGrammarRole(&aw.writer);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "rolebeginexpr") != null);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "rolebodystart") != null);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "rolequoted") != null);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "roledescriptor") != null);
}

test "grammar role generator emits the canonical Idol source face" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try emitGrammarRole(&aw.writer);
    const output = aw.written();

    try std.testing.expect(std.mem.startsWith(u8, output, "# GENERATED"));
    try std.testing.expect(std.mem.indexOf(u8, output, "grammar = req(\"std.compiler.token\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "BEGINEXPR(kind + 1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "BEGINEXPR[") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\nend\n") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\n--") == null);
}

test "grammar role generator preserves token cardinality and eof identity" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try emitGrammarRole(&aw.writer);

    const enum_info = @typeInfo(lexer.TokenKind).@"enum";
    var count_buf: [32]u8 = undefined;
    const count_text = try std.fmt.bufPrint(&count_buf, "ROLECOUNT = {d}", .{enum_info.field_names.len});
    var eof_buf: [32]u8 = undefined;
    const eof_text = try std.fmt.bufPrint(&eof_buf, "KINDEOF = {d}", .{@backingInt(lexer.TokenKind.eof)});
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
