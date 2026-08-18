//! Emit `lib/token/grammarrole.id` from `src/grammar_roles.zig`.
const std = @import("std");
const grammar_roles = @import("grammar_roles.zig");
const lexer = @import("lexer.zig");

pub const MANIFEST_PATH = "lib/token/grammarrole.tsv";

pub fn renderGrammarRole(alloc: std.mem.Allocator) ![]u8 {
    var buf: std.Io.Writer.Allocating = .init(alloc);
    errdefer buf.deinit();
    try emitGrammarRole(&buf.writer);
    return buf.toOwnedSlice();
}

pub fn renderGrammarRoleManifest(alloc: std.mem.Allocator) ![]u8 {
    var buf: std.Io.Writer.Allocating = .init(alloc);
    errdefer buf.deinit();
    try buf.writer.print("# schema\t{s}\n# authority\tfnv1a64:{x:0>16}\n", .{ grammar_roles.SCHEMA_VERSION, grammar_roles.AUTHORITY });
    try emitGrammarRolePayload(&buf.writer);
    return buf.toOwnedSlice();
}

pub fn emitGrammarRoleFile(alloc: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (!std.mem.eql(u8, dir, ".")) {
            const cwd = std.Io.Dir.cwd();
            try cwd.createDirPath(io, dir);
        }
    }
    const projection = try renderGrammarRole(alloc);
    defer alloc.free(projection);
    const cwd = std.Io.Dir.cwd();
    try std.Io.Dir.writeFile(cwd, io, .{ .sub_path = path, .data = projection });
}

pub fn emitGrammarRoleManifestFile(alloc: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (!std.mem.eql(u8, dir, ".")) {
            const cwd = std.Io.Dir.cwd();
            try cwd.createDirPath(io, dir);
        }
    }
    const manifest = try renderGrammarRoleManifest(alloc);
    defer alloc.free(manifest);
    try std.Io.Dir.writeFile(std.Io.Dir.cwd(), io, .{ .sub_path = path, .data = manifest });
}

fn emitGrammarRolePayload(w: *std.Io.Writer) !void {
    try w.writeAll(
        "slot\tkind\tspelling\tbegin\tprefix\tpostfix\tparameter\tliteral\tquoted\tprojection\tbody\tdescriptor\tpattern\tbinary\tprecedence\tassoc\tcompat\n",
    );
    for (grammar_roles.rows, 0..) |role, slot| {
        const kind = role.kind;
        try w.print(
            "{d}\t{s}\t{s}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\n",
            .{
                slot,
                if (kind) |value| @tagName(value) else "-",
                if (kind) |value| value.spelling() else "-",
                @intFromBool(role.roles.begin_expr),
                @intFromBool(role.roles.prefix),
                @intFromBool(role.roles.postfix),
                @intFromBool(role.roles.parameter),
                @intFromBool(role.roles.literal_kind),
                @intFromBool(role.roles.quoted),
                @intFromBool(role.roles.projection),
                @intFromBool(role.roles.body_start),
                @intFromBool(role.roles.descriptor),
                @intFromBool(role.roles.pattern),
                @intFromBool(role.roles.binary),
                role.precedence,
                @backingInt(role.assoc),
                @intFromBool(role.roles.compat_only),
            },
        );
    }
}

fn emitGrammarRole(w: *std.Io.Writer) !void {
    const enum_info = @typeInfo(lexer.TokenKind).@"enum";
    try w.print(
        \\# GENERATED from src/grammar_role_gen.zig — do not edit by hand.
        \\# Regenerate: zig build grammar-role-emit
        \\# Bootstrap grammar-role projection: src/grammar_roles.zig
        \\
        \\grammar = req("std.compiler.token")
        \\
        \\GRAMMARSCHEMA = "{s}"
        \\GRAMMARHASH = "fnv1a64:{x:0>16}"
        \\ROLEIDENTITYCOUNT = {d}
        \\ROLECOUNT = {d}
        \\KINDEOF = {d}
        \\
    , .{ grammar_roles.SCHEMA_VERSION, grammar_roles.AUTHORITY, enum_info.field_names.len, grammar_roles.rows.len, @backingInt(lexer.TokenKind.eof) });

    try emitBoolTable(w, "BEGINEXPR", &grammar_roles.rows, "begin_expr");
    try emitBoolTable(w, "COMPATONLY", &grammar_roles.rows, "compat_only");
    try emitI8Table(w, "precedence", &grammar_roles.rows, "precedence");

    try w.writeAll(
        \\
        \\rolebeginexpr: bool = (kind: i64)
        \\  kind >= 0 and kind < ROLECOUNT and BEGINEXPR(kind + 1) != 0
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
        const v = @field(row.roles, field);
        try w.print("  {s}{d},\n", .{ if (i == 0) "" else "", @intFromBool(v) });
    }
    try w.writeAll("}\n");
}

fn emitI8Table(
    w: *std.Io.Writer,
    name: []const u8,
    rows: []const grammar_roles.RoleRow,
    comptime field: []const u8,
) !void {
    try w.print("{s} = {{\n", .{name});
    for (rows, 0..) |row, i| {
        const n: i64 = @intCast(@field(row, field));
        try w.print("  {s}{d},\n", .{ if (i == 0) "" else "", n });
    }
    try w.writeAll("}\n");
}

test "grammar role generator includes begin_expr lookup" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try emitGrammarRole(&aw.writer);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "rolebeginexpr") != null);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "rolecompatonly") != null);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "roleprecedence") != null);
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

test "grammar role generator distinguishes semantic identities from physical slots" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try emitGrammarRole(&aw.writer);

    const enum_info = @typeInfo(lexer.TokenKind).@"enum";
    var count_buf: [32]u8 = undefined;
    const count_text = try std.fmt.bufPrint(&count_buf, "ROLECOUNT = {d}", .{grammar_roles.rows.len});
    var identity_buf: [40]u8 = undefined;
    const identity_text = try std.fmt.bufPrint(&identity_buf, "ROLEIDENTITYCOUNT = {d}", .{enum_info.field_names.len});
    var eof_buf: [32]u8 = undefined;
    const eof_text = try std.fmt.bufPrint(&eof_buf, "KINDEOF = {d}", .{@backingInt(lexer.TokenKind.eof)});
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), count_text) != null);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), identity_text) != null);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), eof_text) != null);
    try std.testing.expectEqual(enum_info.field_names.len + 1, grammar_roles.rows.len);
}

test "grammar role generator: emit when EMIT_GRAMMAR_ROLE set" {
    const path_z = std.c.getenv("EMIT_GRAMMAR_ROLE") orelse return;
    const path = std.mem.span(path_z);
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    try emitGrammarRoleFile(std.testing.allocator, threaded.io(), path);
}

test "grammar role generator emits one full hashed payload" {
    const manifest = try renderGrammarRoleManifest(std.testing.allocator);
    defer std.testing.allocator.free(manifest);
    const projection = try renderGrammarRole(std.testing.allocator);
    defer std.testing.allocator.free(projection);

    try std.testing.expect(std.mem.startsWith(u8, manifest, "# schema\tgrammar-role-v2\n# authority\tfnv1a64:"));
    try std.testing.expect(std.mem.indexOf(u8, manifest, "\nslot\tkind\tspelling\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "\n3\t-\t-\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "\tplus\t+\t") != null);

    const hash_start = std.mem.indexOf(u8, manifest, "# authority\tfnv1a64:").? + "# authority\tfnv1a64:".len;
    const hash_end = std.mem.indexOfPos(u8, manifest, hash_start, "\n").?;
    try std.testing.expectEqual(@as(usize, 16), hash_end - hash_start);
    try std.testing.expect(std.mem.indexOf(u8, projection, "GRAMMARHASH = \"fnv1a64:") != null);
    try std.testing.expect(std.mem.indexOf(u8, projection, manifest[hash_start..hash_end]) != null);
    try std.testing.expect(std.mem.indexOf(u8, projection, "GRAMMARSCHEMA = \"grammar-role-v2\"") != null);
}
