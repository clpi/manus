const std = @import("std");

pub const FieldError = error{StaleIndex};

pub const Write = struct {
    owner: u32,
    name: []const u8,
    field: []const u8,
    kind: u8,
    shadowed: bool,
};

pub const Entry = struct {
    owner: u32,
    name: []const u8,
    field: []const u8,
    kind: u8,
};

pub const FieldIndex = struct {
    entries: []Entry,
    count: usize,
    check: u64,

    pub fn deinit(self: *FieldIndex, alloc: std.mem.Allocator) void {
        alloc.free(self.entries);
        self.* = undefined;
    }
};

fn checksum(entries: []const Entry) u64 {
    var h = std.hash.Wyhash.init(0);
    for (entries) |e| {
        h.update(std.mem.asBytes(&e.owner));
        h.update(e.name);
        h.update(e.field);
        h.update(std.mem.asBytes(&e.kind));
    }
    return h.final();
}

fn sameKey(e: Entry, owner: u32, name: []const u8, field: []const u8) bool {
    return e.owner == owner and std.mem.eql(u8, e.name, name) and std.mem.eql(u8, e.field, field);
}

fn writeMatches(w: Write, owner: u32, name: []const u8, field: []const u8) bool {
    return !w.shadowed and w.owner == owner and std.mem.eql(u8, w.name, name) and std.mem.eql(u8, w.field, field);
}

fn firstSeen(writes: []const Write, i: usize) bool {
    const w = writes[i];
    if (w.shadowed) return false;
    for (writes[0..i]) |v| {
        if (v.shadowed) continue;
        if (v.owner == w.owner and std.mem.eql(u8, v.name, w.name) and std.mem.eql(u8, v.field, w.field)) return false;
    }
    return true;
}

pub fn build(alloc: std.mem.Allocator, writes: []const Write) !FieldIndex {
    var n: usize = 0;
    for (writes, 0..) |_, i| {
        if (firstSeen(writes, i)) n += 1;
    }
    const entries = try alloc.alloc(Entry, n);
    var m: usize = 0;
    for (writes, 0..) |w, i| {
        if (!firstSeen(writes, i)) continue;
        entries[m] = .{ .owner = w.owner, .name = w.name, .field = w.field, .kind = w.kind };
        m += 1;
    }
    return .{ .entries = entries, .count = writes.len, .check = checksum(entries) };
}

fn fresh(index: *const FieldIndex, writes: []const Write) !void {
    if (index.count != writes.len) return FieldError.StaleIndex;
    if (index.check != checksum(index.entries)) return FieldError.StaleIndex;
}

pub fn hasWrite(index: *const FieldIndex, writes: []const Write, owner: u32, name: []const u8, field: []const u8) !bool {
    try fresh(index, writes);
    for (index.entries) |e| {
        if (!sameKey(e, owner, name, field)) continue;
        for (writes) |w| {
            if (writeMatches(w, owner, name, field)) return true;
        }
        return FieldError.StaleIndex;
    }
    for (writes) |w| {
        if (writeMatches(w, owner, name, field)) return FieldError.StaleIndex;
    }
    return false;
}

pub fn writeKind(index: *const FieldIndex, writes: []const Write, owner: u32, name: []const u8, field: []const u8) !?u8 {
    try fresh(index, writes);
    for (index.entries) |e| {
        if (!sameKey(e, owner, name, field)) continue;
        var first: ?u8 = null;
        var mixed = false;
        for (writes) |w| {
            if (!writeMatches(w, owner, name, field)) continue;
            if (first == null) {
                first = w.kind;
            } else if (first != w.kind) {
                mixed = true;
            }
        }
        if (first == null) return FieldError.StaleIndex;
        if (mixed) return null;
        if (first != e.kind) return FieldError.StaleIndex;
        return first;
    }
    for (writes) |w| {
        if (writeMatches(w, owner, name, field)) return FieldError.StaleIndex;
    }
    return null;
}

fn makeCorpus(alloc: std.mem.Allocator) ![]Write {
    const base = [_]Write{
        .{ .owner = 1, .name = "M", .field = "x", .kind = 1, .shadowed = false },
        .{ .owner = 1, .name = "M", .field = "x", .kind = 1, .shadowed = false },
        .{ .owner = 7, .name = "M", .field = "x", .kind = 2, .shadowed = true },
        .{ .owner = 7, .name = "M", .field = "y", .kind = 2, .shadowed = true },
    };
    return try alloc.dupe(Write, &base);
}

fn makeOther(alloc: std.mem.Allocator) ![]Write {
    const base = [_]Write{
        .{ .owner = 5, .name = "N", .field = "z", .kind = 3, .shadowed = false },
        .{ .owner = 5, .name = "N", .field = "z", .kind = 3, .shadowed = false },
        .{ .owner = 6, .name = "N", .field = "z", .kind = 3, .shadowed = true },
    };
    return try alloc.dupe(Write, &base);
}

test "fieldwrite: index agrees with authority and refuses a perturbed entry" {
    const alloc = std.testing.allocator;
    const writes = try makeCorpus(alloc);
    defer alloc.free(writes);
    var index = try build(alloc, writes);
    defer index.deinit(alloc);
    try std.testing.expect(try hasWrite(&index, writes, 1, "M", "x"));
    try std.testing.expectEqual(@as(?u8, 1), try writeKind(&index, writes, 1, "M", "x"));
    try std.testing.expect(!try hasWrite(&index, writes, 1, "M", "y"));
    try std.testing.expectEqual(@as(?u8, null), try writeKind(&index, writes, 1, "M", "y"));
    try std.testing.expect(!try hasWrite(&index, writes, 7, "M", "x"));
    try std.testing.expectEqual(@as(?u8, null), try writeKind(&index, writes, 7, "M", "x"));
    index.entries[0].owner = 9;
    try std.testing.expectError(FieldError.StaleIndex, hasWrite(&index, writes, 1, "M", "x"));
    try std.testing.expectError(FieldError.StaleIndex, writeKind(&index, writes, 1, "M", "x"));
    index.entries[0].owner = 1;
    try std.testing.expect(try hasWrite(&index, writes, 1, "M", "x"));
    writes[0].shadowed = true;
    writes[1].shadowed = true;
    try std.testing.expectError(FieldError.StaleIndex, hasWrite(&index, writes, 1, "M", "x"));
    try std.testing.expectError(FieldError.StaleIndex, writeKind(&index, writes, 1, "M", "x"));
    writes[0].shadowed = false;
    writes[1].shadowed = false;
    try std.testing.expect(try hasWrite(&index, writes, 1, "M", "x"));
    try std.testing.expectEqual(@as(?u8, 1), try writeKind(&index, writes, 1, "M", "x"));
}

test "fieldwrite: index from another write set refuses instead of answering" {
    const alloc = std.testing.allocator;
    const writes = try makeCorpus(alloc);
    defer alloc.free(writes);
    const other = try makeOther(alloc);
    defer alloc.free(other);
    var index = try build(alloc, other);
    defer index.deinit(alloc);
    try std.testing.expectError(FieldError.StaleIndex, hasWrite(&index, writes, 1, "M", "x"));
    try std.testing.expectError(FieldError.StaleIndex, writeKind(&index, writes, 1, "M", "x"));
    var phantom: usize = 0;
    for (index.entries) |e| {
        if (e.kind == 3) phantom += 1;
    }
    try std.testing.expect(phantom > 0);
}
