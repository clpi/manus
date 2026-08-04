//! SQL DDL → C struct generation for `@sql("CREATE TABLE ...")`.
const std = @import("std");

const Field = struct { name: []const u8, c_type: []const u8 };

/// Upper-case a slice into a stack buffer (max 256 chars, truncated).
fn toUpperBuf(buf: *[256]u8, src: []const u8) []const u8 {
    const len = @min(src.len, 256);
    for (src[0..len], 0..) |c, idx| buf[idx] = std.ascii.toUpper(c);
    return buf[0..len];
}

fn sqlTypeToC(sql_type: []const u8) []const u8 {
    var ubuf: [256]u8 = undefined;
    const t = std.mem.trim(u8, toUpperBuf(&ubuf, sql_type), " \t\r\n()");
    // Integer types
    if (std.mem.indexOf(u8, t, "INT") != null) {
        if (std.mem.indexOf(u8, t, "BIG") != null or std.mem.indexOf(u8, t, "64") != null) return "int64_t";
        if (std.mem.indexOf(u8, t, "SMALL") != null or std.mem.indexOf(u8, t, "16") != null) return "int16_t";
        if (std.mem.indexOf(u8, t, "TINY") != null or std.mem.indexOf(u8, t, "8") != null) return "int8_t";
        return "int32_t";
    }
    // Float/Double types
    if (std.mem.indexOf(u8, t, "DOUBLE") != null or std.mem.indexOf(u8, t, "FLOAT8") != null) return "double";
    if (std.mem.indexOf(u8, t, "REAL") != null or std.mem.indexOf(u8, t, "FLOAT") != null or std.mem.indexOf(u8, t, "NUMERIC") != null) return "double";
    // Decimal → string representation
    if (std.mem.indexOf(u8, t, "DECIMAL") != null) return "double";
    // Boolean
    if (std.mem.indexOf(u8, t, "BOOL") != null) return "int";
    // Text types
    if (std.mem.indexOf(u8, t, "TEXT") != null or std.mem.indexOf(u8, t, "VARCHAR") != null or
        std.mem.indexOf(u8, t, "CHAR") != null or std.mem.indexOf(u8, t, "CLOB") != null)
        return "const char*";
    // Binary/Blob
    if (std.mem.indexOf(u8, t, "BLOB") != null or std.mem.indexOf(u8, t, "BYTEA") != null or
        std.mem.indexOf(u8, t, "BINARY") != null or std.mem.indexOf(u8, t, "VARBINARY") != null)
        return "struct { const uint8_t* data; size_t len; }";
    // Date/Time
    if (std.mem.indexOf(u8, t, "DATE") != null) return "const char*";
    if (std.mem.indexOf(u8, t, "TIME") != null) return "const char*";
    if (std.mem.indexOf(u8, t, "TIMESTAMP") != null) return "const char*";
    // Default
    return "int64_t";
}

fn cleanFieldName(raw: []const u8) []const u8 {
    // Strip backticks, quotes, brackets
    const name = std.mem.trim(u8, raw, " \t\r\n`\"[]");
    return name;
}

pub fn generateFromSql(alloc: std.mem.Allocator, sql: []const u8) ![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    const w = &aw.writer;

    // Parse CREATE TABLE statements
    var remaining = std.mem.trim(u8, sql, " \t\r\n;");
    while (remaining.len > 0) {
        // Find CREATE TABLE (case-insensitive via manual uppercasing)
        var upper_buf: [256]u8 = undefined;
        const upper_len = @min(remaining.len, 256);
        for (remaining[0..upper_len], 0..) |c, idx| upper_buf[idx] = std.ascii.toUpper(c);
        const upper = upper_buf[0..upper_len];
        const ct_pos = std.mem.indexOf(u8, upper, "CREATE TABLE") orelse {
            try w.print("/* [sql] no CREATE TABLE found */\n", .{});
            break;
        };
        remaining = remaining[ct_pos + 12 ..];
        remaining = std.mem.trimStart(u8, remaining, " \t\r\n");
        // Skip IF NOT EXISTS
        var ubuf2: [256]u8 = undefined;
        const upper2 = toUpperBuf(&ubuf2, remaining);
        if (std.mem.startsWith(u8, upper2, "IF NOT EXISTS")) {
            remaining = std.mem.trimStart(u8, remaining[13..], " \t\r\n");
        }
        // Get table name
        const name_start = remaining;
        while (remaining.len > 0 and remaining[0] != '(' and remaining[0] != ' ') : (remaining = remaining[1..]) {}
        const table_name = std.mem.trim(u8, name_start[0 .. name_start.len - remaining.len], " \t\r\n`\"[]");
        remaining = std.mem.trimStart(u8, remaining, " \t\r\n");

        // Skip to opening paren
        if (remaining.len == 0 or remaining[0] != '(') break;
        remaining = remaining[1..];

        // Parse column definitions
        var fields: std.ArrayListUnmanaged(Field) = .empty;
        defer {
            for (fields.items) |f| alloc.free(f.name);
            fields.deinit(alloc);
        }

        var depth: u32 = 1;
        var col_start: usize = 0;
        var i: usize = 0;
        while (i < remaining.len and depth > 0) {
            switch (remaining[i]) {
                '(' => depth += 1,
                ')' => {
                    depth -= 1;
                    if (depth == 0) {
                        const col_def = std.mem.trim(u8, remaining[col_start..i], " \t\r\n,");
                        if (col_def.len > 0) {
                            try parseColumnDef(alloc, col_def, &fields);
                        }
                    }
                },
                ',' => {
                    if (depth == 1) {
                        const col_def = std.mem.trim(u8, remaining[col_start..i], " \t\r\n,");
                        if (col_def.len > 0) {
                            try parseColumnDef(alloc, col_def, &fields);
                        }
                        col_start = i + 1;
                    }
                },
                else => {},
            }
            i += 1;
        }

        // Skip past closing paren and any constraints
        remaining = if (i < remaining.len) remaining[i + 1 ..] else "";
        remaining = std.mem.trimStart(u8, remaining, " \t\r\n;");

        // Emit C struct
        try w.print("/* [sql] {s} */\ntypedef struct {{\n", .{table_name});
        for (fields.items) |f| {
            try w.print("    {s} {s};\n", .{ f.c_type, f.name });
        }
        try w.print("}} {s};\n\n", .{table_name});
    }

    return aw.toOwnedSlice();
}

fn parseColumnDef(alloc: std.mem.Allocator, def: []const u8, fields: *std.ArrayListUnmanaged(Field)) !void {
    const trimmed = std.mem.trim(u8, def, " \t\r\n");
    if (trimmed.len == 0) return;

    // Skip constraints (PRIMARY KEY, CONSTRAINT, UNIQUE, CHECK, FOREIGN KEY, etc.)
    var ubuf3: [256]u8 = undefined;
    const upper = toUpperBuf(&ubuf3, trimmed);
    if (std.mem.startsWith(u8, upper, "PRIMARY") or
        std.mem.startsWith(u8, upper, "CONSTRAINT") or
        std.mem.startsWith(u8, upper, "UNIQUE") or
        std.mem.startsWith(u8, upper, "CHECK") or
        std.mem.startsWith(u8, upper, "FOREIGN") or
        std.mem.startsWith(u8, upper, "INDEX"))
        return;

    // Parse: column_name TYPE [constraints...]
    var parts = std.mem.splitScalar(u8, trimmed, ' ');
    const col_name = std.mem.trim(u8, parts.next() orelse return, "`\"[]");
    if (col_name.len == 0) return;

    // Get the type (may be multiple words like "VARCHAR(255)")
    var type_buf: [128]u8 = undefined;
    var type_len: usize = 0;
    var first_type = true;
    while (parts.next()) |part| {
        const p = std.mem.trim(u8, part, " \t\r\n");
        if (p.len == 0) continue;
        // Stop at constraints
        var ubuf4: [64]u8 = undefined;
        const pu4_len = @min(p.len, 64);
        for (p[0..pu4_len], 0..) |ch, idx| ubuf4[idx] = std.ascii.toUpper(ch);
        const pu = ubuf4[0..pu4_len];
        if (std.mem.eql(u8, pu, "NOT") or std.mem.eql(u8, pu, "NULL") or
            std.mem.eql(u8, pu, "DEFAULT") or std.mem.eql(u8, pu, "PRIMARY") or
            std.mem.eql(u8, pu, "KEY") or std.mem.eql(u8, pu, "UNIQUE") or
            std.mem.eql(u8, pu, "CHECK") or std.mem.eql(u8, pu, "REFERENCES") or
            std.mem.eql(u8, pu, "AUTO_INCREMENT") or std.mem.eql(u8, pu, "AUTOINCREMENT") or
            std.mem.eql(u8, pu, "GENERATED") or std.mem.eql(u8, pu, "IDENTITY"))
            break;
        if (first_type) {
            first_type = false;
        } else {
            if (type_len < type_buf.len) type_buf[type_len] = ' ';
            type_len += 1;
        }
        const copy_len = @min(p.len, type_buf.len - type_len);
        @memcpy(type_buf[type_len .. type_len + copy_len], p[0..copy_len]);
        type_len += copy_len;
    }

    if (type_len == 0) return;

    try fields.append(alloc, .{
        .name = try alloc.dupe(u8, col_name),
        .c_type = sqlTypeToC(type_buf[0..type_len]),
    });
}

test "sql_to_c: simple table" {
    const alloc = std.testing.allocator;
    const sql = "CREATE TABLE users (id INTEGER PRIMARY KEY, name VARCHAR(255) NOT NULL, email TEXT, age INT DEFAULT 0);";
    const c = try generateFromSql(alloc, sql);
    defer alloc.free(c);
    try std.testing.expect(std.mem.indexOf(u8, c, "typedef struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "int32_t id;") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "const char* name;") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "const char* email;") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "int32_t age;") != null);
}

test "sql_to_c: bigint and blob" {
    const alloc = std.testing.allocator;
    const sql = "CREATE TABLE events (id BIGINT, payload BLOB, created_at TIMESTAMP);";
    const c = try generateFromSql(alloc, sql);
    defer alloc.free(c);
    try std.testing.expect(std.mem.indexOf(u8, c, "int64_t id;") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "struct { const uint8_t* data; size_t len; } payload;") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "const char* created_at;") != null);
}

test "sql_to_c: multiple tables" {
    const alloc = std.testing.allocator;
    const sql =
        \\CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
        \\CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INTEGER, title TEXT);
    ;
    const c = try generateFromSql(alloc, sql);
    defer alloc.free(c);
    try std.testing.expect(std.mem.indexOf(u8, c, "users;") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "posts;") != null);
}
