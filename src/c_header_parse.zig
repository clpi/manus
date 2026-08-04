//! Parse preprocessed C headers into function declarations for `@ffi_gen`.
const std = @import("std");
const host_run = @import("host_run.zig");

pub const CDecl = struct {
    name: []const u8,
    ret_type: []const u8,
    params: []const u8,
};

/// Run `clang -E -P` on a header and return preprocessed source.
pub fn preprocessHeader(alloc: std.mem.Allocator, header: []const u8) ?[]const u8 {
    const cmd = std.fmt.allocPrint(
        alloc,
        "printf '' | clang -E -P -x c -include {s} - 2>/dev/null || printf '' | clang -E -P -x c {s} - 2>/dev/null",
        .{ header, header },
    ) catch return null;
    defer alloc.free(cmd);
    const out = host_run.runHostCommand(alloc, cmd) orelse return null;
    if (!out.ok or out.stdout.len == 0) return null;
    return out.stdout;
}

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn trimLeftBytes(s: []const u8, chars: []const u8) []const u8 {
    var i: usize = 0;
    while (i < s.len and std.mem.indexOfScalar(u8, chars, s[i]) != null) : (i += 1) {}
    return s[i..];
}

fn skipWs(s: []const u8) []const u8 {
    return trimLeftBytes(s, " \t\r\n");
}

fn skipLine(s: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, s, '\n')) |nl| return s[nl + 1 ..];
    return "";
}

fn skipPreprocessor(s: []const u8) []const u8 {
    var rest = skipWs(s);
    while (rest.len > 0 and rest[0] == '#') {
        rest = skipLine(rest);
        rest = skipWs(rest);
    }
    return rest;
}

fn readIdent(s: []const u8) struct { name: []const u8, rest: []const u8 } {
    var rest = skipWs(s);
    if (rest.len == 0 or !isIdentStart(rest[0])) return .{ .name = "", .rest = rest };
    var i: usize = 1;
    while (i < rest.len and isIdentChar(rest[i])) : (i += 1) {}
    return .{ .name = rest[0..i], .rest = rest[i..] };
}

fn skipTypedefPrefix(s: []const u8) []const u8 {
    var rest = skipWs(s);
    while (true) {
        const id = readIdent(rest);
        if (id.name.len == 0) return rest;
        rest = skipWs(id.rest);
        if (std.mem.eql(u8, id.name, "typedef") or
            std.mem.eql(u8, id.name, "extern") or
            std.mem.eql(u8, id.name, "static") or
            std.mem.eql(u8, id.name, "inline") or
            std.mem.eql(u8, id.name, "const") or
            std.mem.eql(u8, id.name, "volatile") or
            std.mem.eql(u8, id.name, "unsigned") or
            std.mem.eql(u8, id.name, "signed") or
            std.mem.eql(u8, id.name, "long") or
            std.mem.eql(u8, id.name, "short") or
            std.mem.eql(u8, id.name, "struct") or
            std.mem.eql(u8, id.name, "enum"))
        {
            if (std.mem.eql(u8, id.name, "struct") or std.mem.eql(u8, id.name, "enum")) {
                const tag = readIdent(rest);
                rest = skipWs(tag.rest);
            }
            continue;
        }
        return id.rest;
    }
}

fn findMatchingParen(s: []const u8) ?usize {
    if (s.len == 0 or s[0] != '(') return null;
    var depth: usize = 1;
    var i: usize = 1;
    while (i < s.len) : (i += 1) {
        if (s[i] == '(') depth += 1;
        if (s[i] == ')') {
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    return null;
}

/// Best-effort scan for `ret name(params);` declarations in preprocessed C.
pub fn parseFunctionDecls(alloc: std.mem.Allocator, src: []const u8) ![]CDecl {
    var list: std.ArrayListUnmanaged(CDecl) = .empty;
    errdefer {
        for (list.items) |d| {
            alloc.free(d.name);
            alloc.free(d.ret_type);
            alloc.free(d.params);
        }
        list.deinit(alloc);
    }

    var rest = skipPreprocessor(src);
    while (rest.len > 0) {
        rest = skipPreprocessor(rest);
        if (rest.len == 0) break;
        if (rest[0] == '#') {
            rest = skipLine(rest);
            continue;
        }
        if (std.mem.startsWith(u8, rest, "typedef") or std.mem.startsWith(u8, rest, "struct") or std.mem.startsWith(u8, rest, "enum")) {
            if (std.mem.indexOf(u8, rest, ";")) |semi| {
                rest = rest[semi + 1 ..];
            } else break;
            continue;
        }

        const after_type = skipTypedefPrefix(rest);
        const fn_name = readIdent(after_type);
        if (fn_name.name.len == 0) {
            rest = skipLine(rest);
            continue;
        }
        var params_rest = skipWs(fn_name.rest);
        if (params_rest.len == 0 or params_rest[0] != '(') {
            rest = skipLine(rest);
            continue;
        }
        const close = findMatchingParen(params_rest) orelse {
            rest = skipLine(rest);
            continue;
        };
        const params = std.mem.trim(u8, params_rest[1..close], " \t\r\n");
        var after = skipWs(params_rest[close + 1 ..]);
        const is_def = after.len > 0 and after[0] == '{';
        if (!is_def and (after.len == 0 or after[0] != ';')) {
            rest = skipLine(rest);
            continue;
        }

        const ret_end = @intFromPtr(fn_name.name.ptr) - @intFromPtr(rest.ptr);
        if (ret_end == 0 or ret_end > rest.len) {
            if (is_def) {
                if (std.mem.indexOfScalar(u8, after, '}')) |end| rest = after[end + 1 ..];
            } else rest = after[1..];
            continue;
        }
        const ret_type = std.mem.trim(u8, rest[0..ret_end], " \t\r\n");
        if (ret_type.len == 0 or std.mem.indexOf(u8, ret_type, "(") != null) {
            if (is_def) {
                if (std.mem.indexOfScalar(u8, after, '}')) |end| rest = after[end + 1 ..];
            } else rest = after[1..];
            continue;
        }

        try list.append(alloc, .{
            .name = try alloc.dupe(u8, fn_name.name),
            .ret_type = try alloc.dupe(u8, ret_type),
            .params = try alloc.dupe(u8, if (params.len == 0) "void" else params),
        });
        if (is_def) {
            var depth: u32 = 0;
            var i: usize = 0;
            while (i < after.len) : (i += 1) {
                if (after[i] == '{') depth += 1;
                if (after[i] == '}') {
                    depth -= 1;
                    if (depth == 0) {
                        rest = after[i + 1 ..];
                        break;
                    }
                }
            } else rest = skipLine(rest);
        } else {
            rest = after[1..];
        }
    }
    return try list.toOwnedSlice(alloc);
}

pub fn emitExternDecls(w: *std.Io.Writer, decls: []const CDecl) !void {
    for (decls) |d| {
        try w.print("/* [ffi_gen] {s} */\n", .{d.name});
        // Guard against macro redefinitions (e.g. macOS FORTIFY wrappers
        // that redefine strlcat, strlcpy, bcopy, bzero as macros).
        try w.print("#ifdef {s}\n#undef {s}\n#endif\n", .{ d.name, d.name });
        try w.print("extern {s} {s}({s});\n", .{ d.ret_type, d.name, d.params });
    }
}

pub fn generateFfiFromHeader(alloc: std.mem.Allocator, header: []const u8) ![]const u8 {
    const pre = preprocessHeader(alloc, header) orelse return try std.fmt.allocPrint(alloc, "/* [ffi_gen] could not preprocess {s} */\n", .{header});
    const decls = try parseFunctionDecls(alloc, pre);
    defer {
        for (decls) |d| {
            alloc.free(d.name);
            alloc.free(d.ret_type);
            alloc.free(d.params);
        }
        alloc.free(decls);
    }
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try aw.writer.print("/* [ffi_gen] from {s} — {d} declaration(s) */\n", .{ header, decls.len });
    try emitExternDecls(&aw.writer, decls);
    return try alloc.dupe(u8, aw.written());
}

test "c_header_parse: parses function definitions" {
    const alloc = std.testing.allocator;
    const src =
        \\int64_t add(int64_t a, int64_t b) {
        \\    return a + b;
        \\}
        \\static inline int64_t sub(int64_t a, int64_t b) { return a - b; }
    ;
    const decls = try parseFunctionDecls(alloc, src);
    defer {
        for (decls) |d| {
            alloc.free(d.name);
            alloc.free(d.ret_type);
            alloc.free(d.params);
        }
        alloc.free(decls);
    }
    try std.testing.expectEqual(@as(usize, 2), decls.len);
    try std.testing.expectEqualStrings("add", decls[0].name);
    try std.testing.expectEqualStrings("sub", decls[1].name);
}

test "c_header_parse: finds strlen in string.h preprocessed output" {
    const alloc = std.testing.allocator;
    const pre = preprocessHeader(alloc, "string.h") orelse return;
    defer alloc.free(pre);
    const decls = try parseFunctionDecls(alloc, pre);
    defer {
        for (decls) |d| {
            alloc.free(d.name);
            alloc.free(d.ret_type);
            alloc.free(d.params);
        }
        alloc.free(decls);
    }
    var found = false;
    for (decls) |d| {
        if (std.mem.eql(u8, d.name, "strlen")) found = true;
    }
    try std.testing.expect(found);
}
