//! Layer B — frontend-neutral C declaration adapter (bounded subset).
//!
//! Produces frontend-owned records consumed by the semantic importer. Does not
//! construct compiler-internal Duo objects or SIM entities directly.
const std = @import("std");

pub const FRONTEND_VERSION: []const u8 = "c-header-v0";

pub const Span = struct {
    line: u32,
    col: u32,
};

pub const ScalarKind = enum {
    void,
    bool,
    char,
    i8,
    i16,
    i32,
    i64,
    u8,
    u16,
    u32,
    u64,
    f32,
    f64,
    unknown,

    pub fn name(self: ScalarKind) []const u8 {
        return switch (self) {
            .void => "void",
            .bool => "bool",
            .char => "char",
            .f32 => "float",
            .f64 => "double",
            else => @tagName(self),
        };
    }
};

pub const TypeRef = union(enum) {
    scalar: ScalarKind,
    named: []const u8,
    pointer: *TypeRef,
    array: struct { elem: *TypeRef, extent: ?usize },
    opaque_type,
    unknown: []const u8,

    pub fn deinit(self: *TypeRef, alloc: std.mem.Allocator) void {
        switch (self.*) {
            .named, .unknown => |s| alloc.free(s),
            .pointer => |p| {
                p.deinit(alloc);
                alloc.destroy(p);
            },
            .array => |a| {
                a.elem.deinit(alloc);
                alloc.destroy(a.elem);
            },
            else => {},
        }
    }

    pub fn display(self: TypeRef, alloc: std.mem.Allocator) ![]const u8 {
        return switch (self) {
            .scalar => |s| try alloc.dupe(u8, s.name()),
            .named => |n| try alloc.dupe(u8, n),
            .pointer => |p| {
                const inner = try p.display(alloc);
                defer alloc.free(inner);
                return try std.fmt.allocPrint(alloc, "{s}*", .{inner});
            },
            .array => |a| {
                const inner = try a.elem.display(alloc);
                defer alloc.free(inner);
                if (a.extent) |n| return try std.fmt.allocPrint(alloc, "{s}[{d}]", .{ inner, n });
                return try std.fmt.allocPrint(alloc, "{s}[]", .{inner});
            },
            .opaque_type => try alloc.dupe(u8, "opaque"),
            .unknown => |u| try alloc.dupe(u8, u),
        };
    }
};

pub const FieldDecl = struct {
    name: []const u8,
    typ: TypeRef,
    span: ?Span = null,
};

pub const ParamDecl = struct {
    name: []const u8,
    typ: TypeRef,
};

pub const RecordDecl = struct {
    name: []const u8,
    fields: []FieldDecl,
    is_opaque: bool,
    span: ?Span = null,
};

pub const EnumDecl = struct {
    name: []const u8,
    variants: []const []const u8,
};

pub const FunctionDecl = struct {
    name: []const u8,
    ret: TypeRef,
    params: []ParamDecl,
    span: ?Span = null,
};

pub const UnsupportedRegion = struct {
    kind: []const u8,
    snippet: []const u8,
    reason: []const u8,
    span: ?Span = null,
};

pub const FrontendSnapshot = struct {
    artifact: []const u8,
    frontend: []const u8 = FRONTEND_VERSION,
    records: []RecordDecl,
    functions: []FunctionDecl,
    enums: []EnumDecl,
    unsupported: []UnsupportedRegion,

    pub fn deinit(self: *FrontendSnapshot, alloc: std.mem.Allocator) void {
        alloc.free(self.artifact);
        for (self.records) |*rec| {
            alloc.free(rec.name);
            for (rec.fields) |*f| {
                alloc.free(f.name);
                f.typ.deinit(alloc);
            }
            alloc.free(rec.fields);
        }
        alloc.free(self.records);
        for (self.functions) |*fn_| {
            alloc.free(fn_.name);
            fn_.ret.deinit(alloc);
            for (fn_.params) |*p| {
                alloc.free(p.name);
                p.typ.deinit(alloc);
            }
            alloc.free(fn_.params);
        }
        alloc.free(self.functions);
        for (self.enums) |*en| {
            alloc.free(en.name);
            for (en.variants) |v| alloc.free(v);
            alloc.free(en.variants);
        }
        alloc.free(self.enums);
        for (self.unsupported) |*u| {
            alloc.free(u.kind);
            alloc.free(u.snippet);
            alloc.free(u.reason);
        }
        alloc.free(self.unsupported);
    }
};

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn skipWs(s: []const u8) []const u8 {
    var i: usize = 0;
    while (i < s.len and (s[i] == ' ' or s[i] == '\t' or s[i] == '\r' or s[i] == '\n')) : (i += 1) {}
    return s[i..];
}

fn readIdent(s: []const u8) struct { name: []const u8, rest: []const u8 } {
    const rest = skipWs(s);
    if (rest.len == 0 or !isIdentStart(rest[0])) return .{ .name = "", .rest = rest };
    var i: usize = 1;
    while (i < rest.len and isIdentChar(rest[i])) : (i += 1) {}
    return .{ .name = rest[0..i], .rest = rest[i..] };
}

fn startsWithWord(s: []const u8, word: []const u8) bool {
    if (!std.mem.startsWith(u8, s, word)) return false;
    if (s.len == word.len) return true;
    const next = s[word.len];
    return !isIdentChar(next);
}

fn findMatchingBrace(s: []const u8) ?usize {
    if (s.len == 0 or s[0] != '{') return null;
    var depth: usize = 1;
    var i: usize = 1;
    while (i < s.len) : (i += 1) {
        if (s[i] == '{') depth += 1;
        if (s[i] == '}') {
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    return null;
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

fn parseScalar(name: []const u8) ScalarKind {
    if (std.mem.eql(u8, name, "void")) return .void;
    if (std.mem.eql(u8, name, "bool") or std.mem.eql(u8, name, "_Bool")) return .bool;
    if (std.mem.eql(u8, name, "char")) return .char;
    if (std.mem.eql(u8, name, "signed") or std.mem.eql(u8, name, "int")) return .i32;
    if (std.mem.eql(u8, name, "unsigned")) return .u32;
    if (std.mem.eql(u8, name, "short")) return .i16;
    if (std.mem.eql(u8, name, "long")) return .i64;
    if (std.mem.eql(u8, name, "float")) return .f32;
    if (std.mem.eql(u8, name, "double")) return .f64;
    if (std.mem.eql(u8, name, "int8_t")) return .i8;
    if (std.mem.eql(u8, name, "int16_t")) return .i16;
    if (std.mem.eql(u8, name, "int32_t")) return .i32;
    if (std.mem.eql(u8, name, "int64_t")) return .i64;
    if (std.mem.eql(u8, name, "uint8_t")) return .u8;
    if (std.mem.eql(u8, name, "uint16_t")) return .u16;
    if (std.mem.eql(u8, name, "uint32_t")) return .u32;
    if (std.mem.eql(u8, name, "uint64_t")) return .u64;
    if (std.mem.eql(u8, name, "size_t")) return .u64;
    return .unknown;
}

fn dupeTypeRef(alloc: std.mem.Allocator, tr: TypeRef) !TypeRef {
    return switch (tr) {
        .named, .unknown => |s| .{ .named = try alloc.dupe(u8, s) },
        .scalar => |s| .{ .scalar = s },
        .opaque_type => .opaque_type,
        .pointer => |p| blk: {
            const copy = try alloc.create(TypeRef);
            copy.* = try dupeTypeRef(alloc, p.*);
            break :blk .{ .pointer = copy };
        },
        .array => |a| blk: {
            const copy = try alloc.create(TypeRef);
            copy.* = try dupeTypeRef(alloc, a.elem.*);
            break :blk .{ .array = .{ .elem = copy, .extent = a.extent } };
        },
    };
}

fn parseTypeSpec(alloc: std.mem.Allocator, raw: []const u8) !TypeRef {
    // Strip leading qualifiers for the core type.
    var core = std.mem.trim(u8, raw, " \t\r\n");
    while (true) {
        const id = readIdent(core);
        if (id.name.len == 0) break;
        if (std.mem.eql(u8, id.name, "const") or std.mem.eql(u8, id.name, "volatile") or std.mem.eql(u8, id.name, "restrict") or std.mem.eql(u8, id.name, "struct") or std.mem.eql(u8, id.name, "enum")) {
            core = skipWs(id.rest);
            continue;
        }
        break;
    }
    if (core.len == 0) return .{ .unknown = try alloc.dupe(u8, raw) };

    var base_end = core.len;
    var ptr_depth: usize = 0;
    var array_extent: ?usize = null;
    var i = core.len;
    while (i > 0) {
        i -= 1;
        if (core[i] == ' ') continue;
        if (core[i] == '*') {
            ptr_depth += 1;
            base_end = i;
            continue;
        }
        if (core[i] == ']') {
            const open = std.mem.lastIndexOfScalar(u8, core[0..i], '[') orelse break;
            const ext = std.mem.trim(u8, core[open + 1 .. i], " \t");
            if (ext.len > 0) array_extent = std.fmt.parseInt(usize, ext, 10) catch null;
            base_end = open;
            i = open;
            continue;
        }
        break;
    }
    const base = std.mem.trim(u8, core[0..base_end], " \t\r\n");
    if (base.len == 0) return .{ .unknown = try alloc.dupe(u8, raw) };

    var tr: TypeRef = blk: {
        const sc = parseScalar(base);
        if (sc != .unknown) break :blk .{ .scalar = sc };
        if (std.mem.eql(u8, base, "opaque")) break :blk .opaque_type;
        break :blk .{ .named = try alloc.dupe(u8, base) };
    };

    if (array_extent != null) {
        const elem = try alloc.create(TypeRef);
        elem.* = tr;
        tr = .{ .array = .{ .elem = elem, .extent = array_extent } };
    }
    var p: usize = 0;
    while (p < ptr_depth) : (p += 1) {
        const inner = try alloc.create(TypeRef);
        inner.* = tr;
        tr = .{ .pointer = inner };
    }
    return tr;
}

const TypeAndName = struct { type_raw: []const u8, name: []const u8 };

fn splitTypeAndName(decl: []const u8) TypeAndName {
    var end: usize = decl.len;
    while (end > 0 and std.ascii.isWhitespace(decl[end - 1])) end -= 1;
    if (end == 0) return .{ .type_raw = decl, .name = "" };

    var start = end;
    while (start > 0) {
        const c = decl[start - 1];
        if (std.ascii.isAlphanumeric(c) or c == '_') {
            start -= 1;
            continue;
        }
        break;
    }
    if (start == end) return .{ .type_raw = decl, .name = "" };

    const name = decl[start..end];
    const type_raw = std.mem.trim(u8, decl[0..start], " \t\r\n");
    if (type_raw.len == 0) return .{ .type_raw = decl, .name = "" };
    return .{ .type_raw = type_raw, .name = name };
}

fn isSupportedFieldDeclarator(
    decl: []const u8,
    split: TypeAndName,
) bool {
    if (split.name.len == 0 or !isIdentStart(split.name[0])) return false;
    for (split.name[1..]) |c| {
        if (!isIdentChar(c)) return false;
    }

    if (split.type_raw.len == 0) return false;
    var saw_pointer = false;
    for (split.type_raw) |c| {
        if (c == '*') {
            saw_pointer = true;
            continue;
        }
        if (std.ascii.isWhitespace(c)) continue;
        if (!isIdentChar(c)) return false;
        // parseTypeSpec only represents qualifiers before the base type. Do not
        // accept a post-pointer qualifier and silently turn it into a named type.
        if (saw_pointer) return false;
    }

    // The supported subset is one plain named field. Commas, bitfields,
    // arrays, callbacks, attributes, and nested declarations all contain a
    // declarator token excluded above and must not become truncated ABI facts.
    return std.mem.indexOfScalar(u8, decl, ',') == null;
}

fn appendUnsupported(
    alloc: std.mem.Allocator,
    list: *std.ArrayListUnmanaged(UnsupportedRegion),
    kind: []const u8,
    snippet: []const u8,
    reason: []const u8,
) !void {
    const max = @min(snippet.len, 120);
    try list.append(alloc, .{
        .kind = try alloc.dupe(u8, kind),
        .snippet = try alloc.dupe(u8, snippet[0..max]),
        .reason = try alloc.dupe(u8, reason),
    });
}

fn parseStructFields(alloc: std.mem.Allocator, body: []const u8) ![]FieldDecl {
    var fields: std.ArrayListUnmanaged(FieldDecl) = .empty;
    errdefer {
        for (fields.items) |*f| {
            alloc.free(f.name);
            f.typ.deinit(alloc);
        }
        fields.deinit(alloc);
    }

    var rest = skipWs(body);
    while (rest.len > 0) {
        const semi = std.mem.indexOfScalar(u8, rest, ';') orelse
            return error.UnsupportedCFieldDeclarator;
        const decl = std.mem.trim(u8, rest[0..semi], " \t\r\n");
        if (decl.len > 0) {
            const split = splitTypeAndName(decl);
            if (!isSupportedFieldDeclarator(decl, split))
                return error.UnsupportedCFieldDeclarator;
            var typ = try parseTypeSpec(alloc, split.type_raw);
            if (typ == .unknown) {
                typ.deinit(alloc);
                return error.UnsupportedCFieldDeclarator;
            }
            errdefer typ.deinit(alloc);
            const name = try alloc.dupe(u8, split.name);
            errdefer alloc.free(name);
            try fields.append(alloc, .{ .name = name, .typ = typ });
        }
        rest = skipWs(rest[semi + 1 ..]);
    }
    return try fields.toOwnedSlice(alloc);
}

fn parseParams(alloc: std.mem.Allocator, params_raw: []const u8) ![]ParamDecl {
    if (params_raw.len == 0 or std.mem.eql(u8, params_raw, "void")) return &.{};
    var params: std.ArrayListUnmanaged(ParamDecl) = .empty;
    errdefer {
        for (params.items) |*p| {
            alloc.free(p.name);
            p.typ.deinit(alloc);
        }
        params.deinit(alloc);
    }

    var depth: u32 = 0;
    var start: usize = 0;
    for (params_raw, 0..) |c, i| {
        if (c == '(') depth += 1;
        if (c == ')') depth -= 1;
        if (c == ',' and depth == 0) {
            try appendParam(alloc, &params, params_raw[start..i]);
            start = i + 1;
        }
    }
    if (start < params_raw.len) try appendParam(alloc, &params, params_raw[start..]);
    return try params.toOwnedSlice(alloc);
}

fn appendParam(alloc: std.mem.Allocator, params: *std.ArrayListUnmanaged(ParamDecl), raw: []const u8) !void {
    const decl = std.mem.trim(u8, raw, " \t\r\n");
    if (decl.len == 0) return;
    const split = splitTypeAndName(decl);
    try params.append(alloc, .{
        .name = try alloc.dupe(u8, split.name),
        .typ = try parseTypeSpec(alloc, if (split.type_raw.len > 0) split.type_raw else decl),
    });
}

/// Parse a bounded C header subset into frontend-neutral declarations.
pub fn parseHeader(alloc: std.mem.Allocator, artifact: []const u8, src: []const u8) !FrontendSnapshot {
    const owned_artifact = try alloc.dupe(u8, artifact);
    var records: std.ArrayListUnmanaged(RecordDecl) = .empty;
    var functions: std.ArrayListUnmanaged(FunctionDecl) = .empty;
    var enums: std.ArrayListUnmanaged(EnumDecl) = .empty;
    var unsupported: std.ArrayListUnmanaged(UnsupportedRegion) = .empty;
    errdefer {
        alloc.free(owned_artifact);
        for (records.items) |*rec| {
            alloc.free(rec.name);
            for (rec.fields) |*field| {
                alloc.free(field.name);
                field.typ.deinit(alloc);
            }
            alloc.free(rec.fields);
        }
        records.deinit(alloc);
        for (functions.items) |*function| {
            alloc.free(function.name);
            function.ret.deinit(alloc);
            for (function.params) |*param| {
                alloc.free(param.name);
                param.typ.deinit(alloc);
            }
            alloc.free(function.params);
        }
        functions.deinit(alloc);
        for (enums.items) |*en| {
            alloc.free(en.name);
            for (en.variants) |variant| alloc.free(variant);
            alloc.free(en.variants);
        }
        enums.deinit(alloc);
        for (unsupported.items) |*region| {
            alloc.free(region.kind);
            alloc.free(region.snippet);
            alloc.free(region.reason);
        }
        unsupported.deinit(alloc);
    }

    var rest = skipWs(src);
    while (rest.len > 0) {
        rest = skipWs(rest);
        if (rest.len == 0) break;

        if (rest[0] == '#') {
            const line_end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
            const line = rest[0..line_end];
            if (std.mem.indexOf(u8, line, "#if") != null or std.mem.indexOf(u8, line, "#endif") != null) {
                // include guards / conditionals — skip
            } else if (std.mem.indexOf(u8, line, "#define") != null) {
                if (std.mem.indexOf(u8, line, "_H") == null) {
                    try appendUnsupported(alloc, &unsupported, "macro", line, "macros with arbitrary expressions deferred");
                }
            }
            rest = if (line_end < rest.len) rest[line_end + 1 ..] else "";
            continue;
        }

        if (startsWithWord(rest, "typedef")) {
            var after = skipWs(rest["typedef".len..]);
            if (startsWithWord(after, "struct")) {
                after = skipWs(after["struct".len..]);
                const tag = readIdent(after);
                after = skipWs(tag.rest);
                if (after.len > 0 and after[0] == '{') {
                    const close = findMatchingBrace(after) orelse {
                        try appendUnsupported(alloc, &unsupported, "struct", rest[0..@min(rest.len, 80)], "unterminated struct body");
                        break;
                    };
                    const body = after[1..close];
                    after = skipWs(after[close + 1 ..]);
                    if (after.len > 0 and after[0] == ',') after = skipWs(after[1..]);
                    const alias = readIdent(after);
                    if (alias.name.len == 0) {
                        try appendUnsupported(alloc, &unsupported, "typedef", rest[0..@min(rest.len, 80)], "typedef struct missing alias name");
                    } else {
                        const fields = try parseStructFields(alloc, body);
                        try records.append(alloc, .{
                            .name = try alloc.dupe(u8, alias.name),
                            .fields = fields,
                            .is_opaque = fields.len == 0,
                        });
                    }
                    const semi = std.mem.indexOfScalar(u8, after, ';') orelse break;
                    rest = after[semi + 1 ..];
                    continue;
                }
            }
            if (startsWithWord(after, "enum")) {
                const semi = std.mem.indexOfScalar(u8, after, ';') orelse break;
                try appendUnsupported(alloc, &unsupported, "enum", after[0..semi], "plain enum typedef parsing deferred in v0 spike");
                rest = after[semi + 1 ..];
                continue;
            }
            const semi = std.mem.indexOfScalar(u8, after, ';') orelse break;
            try appendUnsupported(alloc, &unsupported, "typedef", after[0..semi], "unsupported typedef form");
            rest = after[semi + 1 ..];
            continue;
        }

        if (startsWithWord(rest, "enum")) {
            const semi = std.mem.indexOfScalar(u8, rest, ';') orelse break;
            try appendUnsupported(alloc, &unsupported, "enum", rest[0..semi], "plain enum parsing deferred in v0 spike");
            rest = rest[semi + 1 ..];
            continue;
        }

        // Function declaration: ret name(params);
        var after_prefix = blk: {
            var s = rest;
            while (true) {
                const id = readIdent(s);
                if (id.name.len == 0) break :blk s;
                if (std.mem.eql(u8, id.name, "extern") or std.mem.eql(u8, id.name, "static") or std.mem.eql(u8, id.name, "inline")) {
                    s = skipWs(id.rest);
                    continue;
                }
                break :blk s;
            }
        };
        var scan = after_prefix;
        var fn_name_ident: []const u8 = "";
        var fn_name_rest: []const u8 = "";
        while (true) {
            const id = readIdent(scan);
            if (id.name.len == 0) break;
            const after = skipWs(id.rest);
            if (after.len > 0 and after[0] == '(') {
                fn_name_ident = id.name;
                fn_name_rest = after;
                break;
            }
            scan = after;
        }
        if (fn_name_ident.len > 0) {
            const close = findMatchingParen(fn_name_rest) orelse {
                rest = rest[1..];
                continue;
            };
            const params_raw = std.mem.trim(u8, fn_name_rest[1..close], " \t\r\n");
            var after = skipWs(fn_name_rest[close + 1 ..]);
            if (after.len > 0 and after[0] == '{') {
                try appendUnsupported(alloc, &unsupported, "function", fn_name_ident, "function body import deferred");
                if (findMatchingBrace(after)) |end| after = after[end + 1 ..] else after = "";
            } else if (after.len > 0 and after[0] == ';') {
                const ret_end = @intFromPtr(fn_name_ident.ptr) - @intFromPtr(after_prefix.ptr);
                if (ret_end > 0 and ret_end <= after_prefix.len) {
                    const ret_raw = std.mem.trim(u8, after_prefix[0..ret_end], " \t\r\n");
                    const params = try parseParams(alloc, params_raw);
                    try functions.append(alloc, .{
                        .name = try alloc.dupe(u8, fn_name_ident),
                        .ret = try parseTypeSpec(alloc, ret_raw),
                        .params = params,
                    });
                }
                rest = after[1..];
                continue;
            }
        }

        const next_semi = std.mem.indexOfScalar(u8, rest, ';') orelse break;
        try appendUnsupported(alloc, &unsupported, "declaration", rest[0..next_semi], "unrecognized declaration form");
        rest = rest[next_semi + 1 ..];
    }

    return .{
        .artifact = owned_artifact,
        .records = try records.toOwnedSlice(alloc),
        .functions = try functions.toOwnedSlice(alloc),
        .enums = try enums.toOwnedSlice(alloc),
        .unsupported = try unsupported.toOwnedSlice(alloc),
    };
}

test "c_frontend: parse point.h fixture" {
    const src =
        \\#ifndef DUO_PASS5_POINT_H
        \\#define DUO_PASS5_POINT_H
        \\
        \\typedef struct {
        \\    double x;
        \\    double y;
        \\} CPoint;
        \\
        \\double distance2(CPoint point);
        \\
        \\#endif
    ;
    var snap = try parseHeader(std.testing.allocator, "point.h", src);
    defer snap.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), snap.records.len);
    try std.testing.expectEqualStrings("CPoint", snap.records[0].name);
    try std.testing.expectEqual(@as(usize, 2), snap.records[0].fields.len);
    try std.testing.expectEqual(@as(usize, 1), snap.functions.len);
    try std.testing.expectEqualStrings("distance2", snap.functions[0].name);
    try std.testing.expect(snap.functions[0].ret == .scalar);
    try std.testing.expect(snap.functions[0].ret.scalar == .f64);
}

test "c_frontend: parse pointer parameter type" {
    const src =
        \\typedef struct { double a; double b; double c; double d; } CBigRect;
        \\double sum4(CBigRect *rect);
    ;
    var snap = try parseHeader(std.testing.allocator, "big_rect.h", src);
    defer snap.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), snap.functions.len);
    try std.testing.expectEqualStrings("sum4", snap.functions[0].name);
    try std.testing.expectEqual(@as(usize, 1), snap.functions[0].params.len);
    try std.testing.expectEqualStrings("rect", snap.functions[0].params[0].name);
    try std.testing.expect(snap.functions[0].params[0].typ == .pointer);
}

test "c_frontend: scalar and pointer record fields remain representable" {
    const src =
        \\typedef struct { const int count; char **data; } View;
    ;
    var snap = try parseHeader(std.testing.allocator, "view.h", src);
    defer snap.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), snap.records.len);
    try std.testing.expectEqual(@as(usize, 2), snap.records[0].fields.len);
    try std.testing.expect(snap.records[0].fields[0].typ == .scalar);
    try std.testing.expect(snap.records[0].fields[1].typ == .pointer);
    try std.testing.expect(snap.records[0].fields[1].typ.pointer.* == .pointer);
}

test "c_frontend: array fields refuse instead of publishing a truncated record" {
    const src =
        \\typedef struct { int prefix; int values[4]; int tail; } Packet;
    ;
    try std.testing.expectError(
        error.UnsupportedCFieldDeclarator,
        parseHeader(std.testing.allocator, "array-field.h", src),
    );
}

test "c_frontend: callback fields refuse instead of publishing a truncated record" {
    const src =
        \\typedef struct { int (*callback)(int); int tail; } Handler;
    ;
    try std.testing.expectError(
        error.UnsupportedCFieldDeclarator,
        parseHeader(std.testing.allocator, "callback-field.h", src),
    );
}

test "c_frontend: comma and bitfield declarators refuse instead of publishing false fields" {
    const comma_src =
        \\typedef struct { int first, second; int tail; } Pair;
    ;
    try std.testing.expectError(
        error.UnsupportedCFieldDeclarator,
        parseHeader(std.testing.allocator, "comma-fields.h", comma_src),
    );

    const bitfield_src =
        \\typedef struct { unsigned flags:3; int tail; } Bits;
    ;
    try std.testing.expectError(
        error.UnsupportedCFieldDeclarator,
        parseHeader(std.testing.allocator, "bitfield.h", bitfield_src),
    );
}

test "c_frontend: nested and unterminated field declarations refuse" {
    const nested_src =
        \\typedef struct { struct { int value; } nested; int tail; } Outer;
    ;
    try std.testing.expectError(
        error.UnsupportedCFieldDeclarator,
        parseHeader(std.testing.allocator, "nested-field.h", nested_src),
    );

    const unterminated_src =
        \\typedef struct { int first; int tail } MissingSemi;
    ;
    try std.testing.expectError(
        error.UnsupportedCFieldDeclarator,
        parseHeader(std.testing.allocator, "missing-semicolon.h", unterminated_src),
    );
}

test "c_frontend: prior declarations are cleaned when a later field refuses" {
    const src =
        \\typedef struct { int x; int y; } Point;
        \\int point_x(Point *point);
        \\typedef struct { int prefix; int values[4]; int tail; } Packet;
    ;
    try std.testing.expectError(
        error.UnsupportedCFieldDeclarator,
        parseHeader(std.testing.allocator, "partial-header.h", src),
    );
}

test "c_frontend: missing base field types refuse instead of publishing unknown types" {
    const pointer_only_src =
        \\typedef struct { *ptr; int tail; } MissingBase;
    ;
    try std.testing.expectError(
        error.UnsupportedCFieldDeclarator,
        parseHeader(std.testing.allocator, "missing-base.h", pointer_only_src),
    );

    const qualifier_only_src =
        \\typedef struct { const value; int tail; } MissingQualifiedBase;
    ;
    try std.testing.expectError(
        error.UnsupportedCFieldDeclarator,
        parseHeader(std.testing.allocator, "qualifier-only.h", qualifier_only_src),
    );

    const tag_only_src =
        \\typedef struct { struct value; int tail; } MissingTag;
    ;
    try std.testing.expectError(
        error.UnsupportedCFieldDeclarator,
        parseHeader(std.testing.allocator, "tag-only.h", tag_only_src),
    );
}
