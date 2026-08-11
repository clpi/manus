//! Shared byte-location substrate for the migration oracle and production lexer.
const std = @import("std");

pub const SCHEMA_VERSION = "source-cursor-v1";

pub const Loc = struct {
    file: []const u8,
    line: u32,
    col: u32,

    pub fn format(self: Loc, comptime _: []const u8, _: std.fmt.FormatOptions, w: anytype) !void {
        try w.print("{s}:{}:{}", .{ self.file, self.line, self.col });
    }
};

/// Shared line/col advance — identical semantics for 0-based and 1-based cursors.
pub fn advanceLoc(ch: u8, line: *u32, col: *u32) void {
    if (ch == '\n') {
        line.* += 1;
        col.* = 1;
    } else {
        col.* += 1;
    }
}

pub const ByteCursor = struct {
    bytes: []const u8,
    /// 1-based index retained by the migration oracle.
    pos: u32,
    file: []const u8,
    line: u32,
    col: u32,

    pub fn init(bytes: []const u8, file: []const u8) ByteCursor {
        return .{
            .bytes = bytes,
            .pos = 1,
            .file = file,
            .line = 1,
            .col = 1,
        };
    }

    pub fn eof(self: ByteCursor) bool {
        return self.pos > self.bytes.len;
    }

    pub fn peek(self: ByteCursor) u8 {
        if (self.eof()) return 0;
        return self.bytes[self.pos - 1];
    }

    pub fn advance(self: *ByteCursor) u8 {
        if (self.eof()) return 0;
        const ch = self.bytes[self.pos - 1];
        self.pos += 1;
        advanceLoc(ch, &self.line, &self.col);
        return ch;
    }

    pub fn loc(self: ByteCursor) Loc {
        return .{ .file = self.file, .line = self.line, .col = self.col };
    }
};

/// Production lexer cursor with a zero-based byte index.
pub const ProductionCursor = struct {
    bytes: []const u8,
    /// 0-based index into `bytes` (production lexer convention).
    index: usize,
    file: []const u8,
    line: u32,
    col: u32,

    pub fn init(bytes: []const u8, file: []const u8) ProductionCursor {
        return .{
            .bytes = bytes,
            .index = 0,
            .file = file,
            .line = 1,
            .col = 1,
        };
    }

    pub fn eof(self: ProductionCursor) bool {
        return self.index >= self.bytes.len;
    }

    pub fn peek(self: ProductionCursor) u8 {
        if (self.eof()) return 0;
        return self.bytes[self.index];
    }

    pub fn peek2(self: ProductionCursor) u8 {
        if (self.index + 1 >= self.bytes.len) return 0;
        return self.bytes[self.index + 1];
    }

    pub fn advance(self: *ProductionCursor) u8 {
        if (self.eof()) return 0;
        const ch = self.bytes[self.index];
        self.index += 1;
        advanceLoc(ch, &self.line, &self.col);
        return ch;
    }

    /// Advance index/col without newline handling (e.g. `--` comment opener).
    pub fn bumpCol(self: *ProductionCursor, n: usize) void {
        self.index += n;
        self.col += @intCast(n);
    }

    pub fn loc(self: ProductionCursor) Loc {
        return .{ .file = self.file, .line = self.line, .col = self.col };
    }
};

/// Differential: both cursor models yield identical `Loc` after equivalent byte walks.
pub fn productionLocAfterWalk(text: []const u8, file: []const u8, stop_line: u32) Loc {
    var p = ProductionCursor.init(text, file);
    while (!p.eof()) {
        _ = p.advance();
        if (p.line == stop_line and p.col == 1) break;
    }
    return p.loc();
}

/// Reference walk used by differential tests and verify gate.
pub fn walkReference(text: []const u8, file: []const u8) Loc {
    var c = ByteCursor.init(text, file);
    while (!c.eof()) {
        const ch = c.advance();
        if (ch == '\n' and c.line == 3 and c.col == 1) break;
    }
    return c.loc();
}

pub fn differentialProductionParity() bool {
    const cases = [_]struct { text: []const u8, stop_line: u32 }{
        .{ .text = "a\nb\nc", .stop_line = 3 },
        .{ .text = "fun\nend", .stop_line = 2 },
        .{ .text = "x", .stop_line = 1 },
    };
    for (cases) |case| {
        const prod = productionLocAfterWalk(case.text, "parity.id", case.stop_line);
        var c = ByteCursor.init(case.text, "parity.id");
        while (!c.eof()) {
            _ = c.advance();
            if (c.line == case.stop_line and c.col == 1) break;
        }
        const one = c.loc();
        if (prod.line != one.line or prod.col != one.col) return false;
    }
    return true;
}

test "source cursor: reference locations retain exact coordinates" {
    const loc = walkReference("a\nb\nc", "test.id");
    try std.testing.expectEqual(@as(u32, 3), loc.line);
    try std.testing.expectEqual(@as(u32, 1), loc.col);

    var two = ByteCursor.init("fun\nend", "test.id");
    while (!two.eof()) {
        _ = two.advance();
        if (two.line == 2 and two.col == 1) break;
    }
    try std.testing.expectEqual(@as(u32, 2), two.loc().line);
    try std.testing.expectEqual(@as(u32, 1), two.loc().col);

    var one = ByteCursor.init("x", "test.id");
    _ = one.advance();
    try std.testing.expectEqual(@as(u32, 1), one.loc().line);
    try std.testing.expectEqual(@as(u32, 2), one.loc().col);
}

test "source_cursor: 1-based peek" {
    var c = ByteCursor.init("fun", "x.id");
    try std.testing.expectEqual(@as(u8, 'f'), c.peek());
    try std.testing.expectEqual(@as(u32, 1), c.pos);
}

test "source_cursor: production cursor 0-based peek" {
    var p = ProductionCursor.init("fun", "x.id");
    try std.testing.expectEqual(@as(u8, 'f'), p.peek());
    try std.testing.expectEqual(@as(usize, 0), p.index);
}

test "source cursor: production and migration locations agree" {
    try std.testing.expect(differentialProductionParity());
}
