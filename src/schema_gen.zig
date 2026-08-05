//! Minimal JSON Schema → C struct generation for `@schema`.
const std = @import("std");
const host_run = @import("host_run.zig");
const Io = std.Io;

fn trimLeftBytes(s: []const u8, chars: []const u8) []const u8 {
    var i: usize = 0;
    while (i < s.len and std.mem.indexOfScalar(u8, chars, s[i]) != null) : (i += 1) {}
    return s[i..];
}

fn jsonUnescape(alloc: std.mem.Allocator, raw: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, raw, '\\') == null) return try alloc.dupe(u8, raw);
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);
    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] == '\\' and i + 1 < raw.len) {
            try buf.append(alloc, raw[i + 1]);
            i += 2;
        } else {
            try buf.append(alloc, raw[i]);
            i += 1;
        }
    }
    return try buf.toOwnedSlice(alloc);
}

fn extractJsonString(alloc: std.mem.Allocator, src: []const u8, key: []const u8) ?[]const u8 {
    const needle = std.fmt.allocPrint(alloc, "\"{s}\"", .{key}) catch return null;
    defer alloc.free(needle);
    const pos = std.mem.indexOf(u8, src, needle) orelse return null;
    var rest = src[pos + needle.len ..];
    rest = trimLeftBytes(rest, " \t\r\n:");
    rest = trimLeftBytes(rest, " \t\r\n");
    if (rest.len == 0 or rest[0] != '"') return null;
    var i: usize = 1;
    while (i < rest.len) {
        if (rest[i] == '\\' and i + 1 < rest.len) {
            i += 2;
            continue;
        }
        if (rest[i] == '"') {
            return jsonUnescape(alloc, rest[1..i]) catch null;
        }
        i += 1;
    }
    return null;
}

fn jsonTypeToC(json_type: []const u8) []const u8 {
    if (std.mem.eql(u8, json_type, "string")) return "const char*";
    if (std.mem.eql(u8, json_type, "integer")) return "int64_t";
    if (std.mem.eql(u8, json_type, "number")) return "double";
    if (std.mem.eql(u8, json_type, "boolean")) return "bool";
    return "int64_t";
}

const Field = struct { name: []const u8, c_type: []const u8 };

fn parseProperties(alloc: std.mem.Allocator, src: []const u8) ![]Field {
    const props_key = "\"properties\"";
    const pos = std.mem.indexOf(u8, src, props_key) orelse return &.{};
    var rest = src[pos + props_key.len ..];
    const open = std.mem.indexOfScalar(u8, rest, '{') orelse return &.{};
    rest = rest[open + 1 ..];
    var list: std.ArrayListUnmanaged(Field) = .empty;
    errdefer {
        for (list.items) |f| {
            alloc.free(f.name);
        }
        list.deinit(alloc);
    }
    while (rest.len > 0) {
        rest = trimLeftBytes(rest, " \t\r\n,");
        if (rest.len == 0 or rest[0] == '}') break;
        if (rest[0] != '"') break;
        var i: usize = 1;
        while (i < rest.len and rest[i] != '"') : (i += 1) {}
        if (i >= rest.len) break;
        const fname = try alloc.dupe(u8, rest[1..i]);
        rest = rest[i + 1 ..];
        const type_key = "\"type\"";
        const tpos = std.mem.indexOf(u8, rest, type_key) orelse {
            alloc.free(fname);
            break;
        };
        var trest = rest[tpos + type_key.len ..];
        trest = trimLeftBytes(trest, " \t\r\n:");
        trest = trimLeftBytes(trest, " \t\r\n");
        if (trest.len == 0 or trest[0] != '"') {
            alloc.free(fname);
            break;
        }
        var j: usize = 1;
        while (j < trest.len and trest[j] != '"') : (j += 1) {}
        const jtype = trest[1..j];
        try list.append(alloc, .{ .name = fname, .c_type = jsonTypeToC(jtype) });
        const next_obj = std.mem.indexOfScalar(u8, rest, '}') orelse break;
        rest = rest[next_obj + 1 ..];
    }
    return try list.toOwnedSlice(alloc);
}

pub fn extractJsonTitle(alloc: std.mem.Allocator, json: []const u8) ?[]const u8 {
    return extractJsonString(alloc, json, "title");
}

pub fn isJsonSchema(json: []const u8) bool {
    return std.mem.indexOf(u8, json, "\"properties\"") != null;
}

const DataField = struct {
    name: []const u8,
    c_type: []const u8,
    c_init: []const u8,
};

fn skipJsonValueEnd(rest: []const u8) []const u8 {
    var r = trimLeftBytes(rest, " \t\r\n,");
    if (r.len == 0) return r;
    switch (r[0]) {
        '"', 't', 'f', 'n' => {
            // string / true / false / null — scan to delimiter
            if (r[0] == '"') {
                var i: usize = 1;
                while (i < r.len) {
                    if (r[i] == '\\' and i + 1 < r.len) {
                        i += 2;
                        continue;
                    }
                    if (r[i] == '"') return trimLeftBytes(r[i + 1 ..], " \t\r\n,");
                    i += 1;
                }
                return r;
            }
            const comma = std.mem.indexOfScalar(u8, r, ',') orelse r.len;
            const end = std.mem.indexOfScalar(u8, r[0..comma], '}') orelse comma;
            return trimLeftBytes(r[end..], " \t\r\n,");
        },
        '{' => {
            var depth: u32 = 0;
            var i: usize = 0;
            while (i < r.len) : (i += 1) {
                if (r[i] == '{') depth += 1;
                if (r[i] == '}') {
                    depth -= 1;
                    if (depth == 0) return trimLeftBytes(r[i + 1 ..], " \t\r\n,");
                }
            }
            return r;
        },
        '[' => {
            var depth: u32 = 0;
            var i: usize = 0;
            while (i < r.len) : (i += 1) {
                if (r[i] == '[') depth += 1;
                if (r[i] == ']') {
                    depth -= 1;
                    if (depth == 0) return trimLeftBytes(r[i + 1 ..], " \t\r\n,");
                }
            }
            return r;
        },
        else => {
            const comma = std.mem.indexOfScalar(u8, r, ',') orelse r.len;
            const end = std.mem.indexOfScalar(u8, r[0..comma], '}') orelse comma;
            return trimLeftBytes(r[end..], " \t\r\n,");
        },
    }
}

fn parseJsonDataField(alloc: std.mem.Allocator, rest: []const u8) !?struct { field: DataField, rest: []const u8 } {
    var r = trimLeftBytes(rest, " \t\r\n,");
    if (r.len == 0 or r[0] == '}') return null;
    if (r[0] != '"') return null;
    var i: usize = 1;
    while (i < r.len and r[i] != '"') : (i += 1) {}
    if (i >= r.len) return null;
    const fname = try alloc.dupe(u8, r[1..i]);
    r = trimLeftBytes(r[i + 1 ..], " \t\r\n,");
    if (r.len == 0 or r[0] != ':') {
        alloc.free(fname);
        return null;
    }
    r = trimLeftBytes(r[1..], " \t\r\n");
    if (r.len == 0) {
        alloc.free(fname);
        return null;
    }
    const c_init = if (r[0] == '"') blk: {
        var j: usize = 1;
        while (j < r.len) {
            if (r[j] == '\\' and j + 1 < r.len) {
                j += 2;
                continue;
            }
            if (r[j] == '"') break;
            j += 1;
        }
        const raw = r[1..j];
        const escaped = try jsonUnescape(alloc, raw);
        defer alloc.free(escaped);
        break :blk try std.fmt.allocPrint(alloc, "\"{s}\"", .{escaped});
    } else if (std.mem.startsWith(u8, r, "true")) blk: {
        break :blk try alloc.dupe(u8, "true");
    } else if (std.mem.startsWith(u8, r, "false")) blk: {
        break :blk try alloc.dupe(u8, "false");
    } else if (std.mem.indexOf(u8, r, ".") != null) blk: {
        const end = std.mem.indexOfAny(u8, r, ",}") orelse r.len;
        break :blk try alloc.dupe(u8, trimLeftBytes(r[0..end], " \t\r\n"));
    } else blk: {
        const end = std.mem.indexOfAny(u8, r, ",}") orelse r.len;
        break :blk try alloc.dupe(u8, trimLeftBytes(r[0..end], " \t\r\n"));
    };
    const inferred_type: []const u8 = if (c_init[0] == '"') "const char*" else if (std.mem.eql(u8, c_init, "true") or std.mem.eql(u8, c_init, "false")) "bool" else if (std.mem.indexOf(u8, c_init, ".") != null) "double" else "int64_t";
    const next = skipJsonValueEnd(r);
    return .{ .field = .{ .name = fname, .c_type = inferred_type, .c_init = c_init }, .rest = next };
}

fn isDataMetaKey(name: []const u8) bool {
    return std.mem.eql(u8, name, "title") or
        std.mem.eql(u8, name, "$schema") or
        std.mem.eql(u8, name, "type");
}

fn parseDataFields(alloc: std.mem.Allocator, src: []const u8) ![]DataField {
    const open = std.mem.indexOfScalar(u8, src, '{') orelse return &.{};
    var rest = src[open + 1 ..];
    var list: std.ArrayListUnmanaged(DataField) = .empty;
    errdefer {
        for (list.items) |f| {
            alloc.free(f.name);
            alloc.free(f.c_init);
        }
        list.deinit(alloc);
    }
    while (true) {
        const parsed = try parseJsonDataField(alloc, rest) orelse break;
        rest = parsed.rest;
        if (isDataMetaKey(parsed.field.name)) {
            alloc.free(parsed.field.name);
            alloc.free(parsed.field.c_init);
            continue;
        }
        try list.append(alloc, parsed.field);
    }
    return try list.toOwnedSlice(alloc);
}

/// JSON data object → typedef + `static const` struct literal (native C, no lua_Value).
pub fn jsonDataToC(alloc: std.mem.Allocator, data_json: []const u8, struct_name: []const u8, symbol: []const u8) ![]const u8 {
    const fields = try parseDataFields(alloc, data_json);
    defer {
        for (fields) |f| {
            alloc.free(f.name);
            alloc.free(f.c_init);
        }
        alloc.free(fields);
    }
    if (fields.len == 0) return error.EmptyJsonData;

    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try aw.writer.print("/* [embed.json data] {s} */\n", .{struct_name});
    try aw.writer.print("typedef struct {{\n", .{});
    for (fields) |f| {
        try aw.writer.print("    {s} {s};\n", .{ f.c_type, f.name });
    }
    try aw.writer.print("}} {s};\n", .{struct_name});
    try aw.writer.print("static const {s} {s} = {{\n", .{ struct_name, symbol });
    for (fields, 0..) |f, i| {
        if (i > 0) try aw.writer.print(",\n", .{});
        if (f.c_type[0] == 'c') {
            try aw.writer.print("    .{s} = {s}", .{ f.name, f.c_init });
        } else {
            try aw.writer.print("    .{s} = {s}", .{ f.name, f.c_init });
        }
    }
    try aw.writer.print("\n}};\n", .{});
    return try alloc.dupe(u8, aw.written());
}

pub fn jsonSchemaToC(alloc: std.mem.Allocator, schema_json: []const u8) ![]const u8 {
    const title = extractJsonString(alloc, schema_json, "title") orelse try alloc.dupe(u8, "Generated");
    defer alloc.free(title);
    const fields = try parseProperties(alloc, schema_json);
    defer {
        for (fields) |f| alloc.free(f.name);
        alloc.free(fields);
    }

    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try aw.writer.print("/* [schema] {s} from JSON Schema */\ntypedef struct {{\n", .{title});
    for (fields) |f| {
        try aw.writer.print("    {s} {s};\n", .{ f.c_type, f.name });
    }
    try aw.writer.print("}} {s};\n", .{title});
    return try alloc.dupe(u8, aw.written());
}

pub fn generateSchemaFromFile(alloc: std.mem.Allocator, io: Io, cwd: Io.Dir, path: []const u8) ![]const u8 {
    const json = try Io.Dir.readFileAlloc(cwd, io, path, alloc, .unlimited);
    defer alloc.free(json);
    return jsonSchemaToC(alloc, json);
}

pub fn generateSchemaFromRun(alloc: std.mem.Allocator, cmd: []const u8) ![]const u8 {
    const out = host_run.runHostCommand(alloc, cmd) orelse return error.SchemaCommandFailed;
    if (!out.ok) return error.SchemaCommandFailed;
    return jsonSchemaToC(alloc, out.stdout);
}

test "schema_gen: json data emits struct literal" {
    const alloc = std.testing.allocator;
    const json =
        \\{"title":"Point","x":1.5,"y":2.5,"label":"origin"}
    ;
    const c = try jsonDataToC(alloc, json, "Point", "point_data");
    defer alloc.free(c);
    try std.testing.expect(std.mem.indexOf(u8, c, "typedef struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "static const Point point_data") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, ".x = 1.5") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, ".label = \"origin\"") != null);
}

test "schema_gen: pretty-printed point.json" {
    const alloc = std.testing.allocator;
    const json =
        \\{
        \\  "title": "Point",
        \\  "type": "object",
        \\  "properties": {
        \\    "x": { "type": "number" },
        \\    "y": { "type": "number" },
        \\    "label": { "type": "string" }
        \\  }
        \\}
    ;
    const c = try jsonSchemaToC(alloc, json);
    defer alloc.free(c);
    try std.testing.expect(std.mem.indexOf(u8, c, "double x;") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "double y;") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "const char* label;") != null);
}

test "schema_gen: simple object schema" {
    const alloc = std.testing.allocator;
    const json =
        \\{"title":"Point","properties":{"x":{"type":"number"},"y":{"type":"number"},"label":{"type":"string"}}}
    ;
    const c = try jsonSchemaToC(alloc, json);
    defer alloc.free(c);
    try std.testing.expect(std.mem.indexOf(u8, c, "typedef struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "double x;") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "const char* label;") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "Point;") != null);
}
