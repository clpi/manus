//! Promotion of immutable positional aggregates to read-only native data.
//!
//! Source facts answer whether an aggregate may be immutable data; DNIR facts
//! independently prove that the physical region being deleted is exactly that
//! initialized aggregate and has no write/escape after construction. Both are
//! required while source aggregate identity and DNIR base-temp identity are not
//! yet the same graph id (GAP-201).
//!
//! Source semantics are current Idol: `[]` is indexed projection, `()` is
//! ordinary application. This module never runs the retired call→index
//! normalizer and never consults a sema TypeMap.

const std = @import("std");
const ast = @import("ast.zig");
const dnir = @import("native/ir.zig");
const table_facts = @import("table_facts.zig");

const Error = std.mem.Allocator.Error;

/// Existing native frame/table realization bound. Promotion does not widen the
/// accepted program set; it only removes initialization work for already-legal
/// regions.
pub const max_words: i64 = 4096;

pub const Promotion = struct {
    base: u32,
    values: []const i64,
};

pub const Set = struct {
    alloc: std.mem.Allocator,
    items: []Promotion,

    pub fn deinit(self: *Set) void {
        for (self.items) |item| if (item.values.len > 0) self.alloc.free(item.values);
        self.alloc.free(self.items);
        self.* = undefined;
    }
};

/// Source-side permission keyed by exact constant contents until graph aggregate
/// ids replace the conservative content join. If any binding with the same
/// contents is dirty, all such content is denied; collisions therefore lose an
/// optimization, never correctness.
pub const Licence = struct {
    alloc: std.mem.Allocator,
    entries: []Entry,

    pub const Entry = struct {
        values: []const i64,
        clean: bool,
    };

    pub fn deinit(self: *Licence) void {
        for (self.entries) |entry| if (entry.values.len > 0) self.alloc.free(entry.values);
        self.alloc.free(self.entries);
        self.* = undefined;
    }

    pub fn permits(self: *const Licence, values: []const i64) bool {
        if (values.len == 0) return false;
        for (self.entries) |entry| {
            if (std.mem.eql(i64, entry.values, values)) return entry.clean;
        }
        return false;
    }
};

pub fn licenceForModule(alloc: std.mem.Allocator, module: *const ast.Module) Error!Licence {
    var entries: std.ArrayListUnmanaged(Licence.Entry) = .empty;
    errdefer {
        for (entries.items) |entry| if (entry.values.len > 0) alloc.free(entry.values);
        entries.deinit(alloc);
    }
    for (module.body.stmts) |*statement| {
        if (statement.* != .func_decl) continue;
        var decisions = try table_facts.analyze(alloc, &statement.func_decl.func.body);
        defer decisions.deinit();
        for (decisions.facts) |fact| try note(alloc, &entries, fact);
    }
    return .{ .alloc = alloc, .entries = try entries.toOwnedSlice(alloc) };
}

pub fn emptyLicence(alloc: std.mem.Allocator) Licence {
    return .{ .alloc = alloc, .entries = &.{} };
}

fn note(
    alloc: std.mem.Allocator,
    entries: *std.ArrayListUnmanaged(Licence.Entry),
    fact: table_facts.Facts,
) Error!void {
    // Runtime index is intentionally absent: it prevents full elimination but
    // does not prevent a read-only data realization.
    const clean = fact.width > 0 and fact.contents_known and
        !fact.mutated() and !fact.escape.escapes();
    for (entries.items) |*entry| {
        if (std.mem.eql(i64, entry.values, fact.values)) {
            entry.clean = entry.clean and clean;
            return;
        }
    }
    try entries.append(alloc, .{
        .values = try alloc.dupe(i64, fact.values),
        .clean = clean,
    });
}

fn baseOf(value: dnir.Value) ?u32 {
    return switch (value) {
        .temp => |id| id,
        .local => |id| id,
        else => null,
    };
}

fn valueMentions(value: dnir.Value, id: u32) bool {
    return switch (value) {
        .temp => |candidate| candidate == id,
        .local => |candidate| candidate == id,
        else => false,
    };
}

fn mentions(instruction: dnir.Instr, id: u32) bool {
    if (valueMentions(instruction.lhs, id)) return true;
    if (valueMentions(instruction.rhs, id)) return true;
    if (valueMentions(instruction.third, id)) return true;
    for (instruction.vals) |value| if (valueMentions(value, id)) return true;
    return false;
}

const Element = struct { key: i64, word: i64 };

fn initializingStore(instruction: dnir.Instr, base: u32) ?Element {
    if (instruction.op != .store_index or instruction.ty != .i64) return null;
    if (baseOf(instruction.lhs) != base) return null;
    const key = switch (instruction.rhs) {
        .i64 => |value| value,
        else => return null,
    };
    const word = switch (instruction.third) {
        .i64 => |value| value,
        else => return null,
    };
    return .{ .key = key, .word = word };
}

fn elementRead(instruction: dnir.Instr, base: u32) bool {
    if (instruction.op != .load_index or instruction.ty != .i64) return false;
    if (baseOf(instruction.lhs) != base) return false;
    if (valueMentions(instruction.rhs, base)) return false;
    if (valueMentions(instruction.third, base)) return false;
    for (instruction.vals) |value| if (valueMentions(value, base)) return false;
    return true;
}

/// Return every physical table region that may be replaced by read-only data.
/// The recognizer is intentionally stronger than the source licence: every slot
/// must be initialized once by a literal before any read, the base cannot be
/// redefined, and every subsequent mention must be an i64 indexed read.
pub fn recognize(alloc: std.mem.Allocator, function: dnir.Function, licence: *const Licence) Error!Set {
    var promotions: std.ArrayListUnmanaged(Promotion) = .empty;
    errdefer {
        for (promotions.items) |item| if (item.values.len > 0) alloc.free(item.values);
        promotions.deinit(alloc);
    }
    if (licence.entries.len == 0)
        return .{ .alloc = alloc, .items = try promotions.toOwnedSlice(alloc) };

    var flat: std.ArrayListUnmanaged(dnir.Instr) = .empty;
    defer flat.deinit(alloc);
    for (function.blocks) |block| try flat.appendSlice(alloc, block.instrs);

    for (flat.items, 0..) |candidate, candidate_index| {
        if (candidate.op != .alloc_slots) continue;
        const base = candidate.result orelse continue;
        const extent: i64 = switch (candidate.lhs) {
            .i64 => |value| value,
            else => continue,
        };
        if (extent < 1 or extent > max_words) continue;
        const width: usize = @intCast(extent);

        const values = try alloc.alloc(i64, width);
        var keep = false;
        defer if (!keep) alloc.free(values);
        const filled = try alloc.alloc(bool, width);
        defer alloc.free(filled);
        @memset(filled, false);

        var stored: usize = 0;
        var last_init = candidate_index;
        var first_other: ?usize = null;
        var valid = true;

        for (flat.items, 0..) |instruction, index| {
            if (index == candidate_index) continue;
            if (dnir.definition(instruction)) |definition| {
                if (definition == base) {
                    valid = false;
                    break;
                }
            }
            if (initializingStore(instruction, base)) |element| {
                if (element.key < 1 or element.key > extent) {
                    valid = false;
                    break;
                }
                const slot: usize = @intCast(element.key - 1);
                if (filled[slot]) {
                    valid = false;
                    break;
                }
                filled[slot] = true;
                values[slot] = element.word;
                stored += 1;
                last_init = @max(last_init, index);
                continue;
            }
            if (!mentions(instruction, base)) continue;
            if (!elementRead(instruction, base)) {
                valid = false;
                break;
            }
            if (first_other == null) first_other = index;
        }

        if (!valid or stored != width) continue;
        if (first_other) |first| if (first < last_init) continue;
        if (!licence.permits(values)) continue;

        try promotions.append(alloc, .{ .base = base, .values = values });
        keep = true;
    }

    return .{ .alloc = alloc, .items = try promotions.toOwnedSlice(alloc) };
}

const testing = std.testing;

fn openLicence(alloc: std.mem.Allocator, values: []const i64) !Licence {
    const entries = try alloc.alloc(Licence.Entry, 1);
    entries[0] = .{ .values = try alloc.dupe(i64, values), .clean = true };
    return .{ .alloc = alloc, .entries = entries };
}

fn allocSlots(base: u32, extent: i64) dnir.Instr {
    return .{ .op = .alloc_slots, .result = base, .lhs = .{ .i64 = extent } };
}

fn constStore(base: u32, key: i64, value: i64) dnir.Instr {
    return .{
        .op = .store_index,
        .ty = .i64,
        .lhs = .{ .temp = base },
        .rhs = .{ .i64 = key },
        .third = .{ .i64 = value },
    };
}

fn oneBlock(instructions: []const dnir.Instr) [1]dnir.Block {
    return .{.{ .instrs = instructions }};
}

test "const_table: runtime indexed read promotes determined data" {
    const alloc = testing.allocator;
    var licence = try openLicence(alloc, &.{ 10, 20, 30 });
    defer licence.deinit();
    const instructions = [_]dnir.Instr{
        allocSlots(1, 3),
        constStore(1, 1, 10),
        constStore(1, 2, 20),
        constStore(1, 3, 30),
        .{ .op = .load_index, .ty = .i64, .result = 9, .lhs = .{ .local = 1 }, .rhs = .{ .temp = 7 } },
        .{ .op = .ret, .lhs = .{ .temp = 9 } },
    };
    var blocks = oneBlock(&instructions);
    var set = try recognize(alloc, .{ .name = "main", .ret = .i64, .blocks = &blocks }, &licence);
    defer set.deinit();
    try testing.expectEqual(@as(usize, 1), set.items.len);
    try testing.expectEqualSlices(i64, &.{ 10, 20, 30 }, set.items[0].values);
}

test "const_table: runtime write declines promotion" {
    const alloc = testing.allocator;
    var licence = try openLicence(alloc, &.{ 10, 20 });
    defer licence.deinit();
    const instructions = [_]dnir.Instr{
        allocSlots(1, 2),
        constStore(1, 1, 10),
        constStore(1, 2, 20),
        .{ .op = .store_index, .ty = .i64, .lhs = .{ .local = 1 }, .rhs = .{ .temp = 7 }, .third = .{ .temp = 8 } },
        .{ .op = .ret, .lhs = .{ .i64 = 0 } },
    };
    var blocks = oneBlock(&instructions);
    var set = try recognize(alloc, .{ .name = "main", .ret = .i64, .blocks = &blocks }, &licence);
    defer set.deinit();
    try testing.expectEqual(@as(usize, 0), set.items.len);
}

test "const_table: duplicate initialization declines promotion" {
    const alloc = testing.allocator;
    var licence = try openLicence(alloc, &.{ 10, 20 });
    defer licence.deinit();
    const instructions = [_]dnir.Instr{
        allocSlots(1, 2),
        constStore(1, 1, 10),
        constStore(1, 2, 20),
        constStore(1, 2, 99),
        .{ .op = .ret, .lhs = .{ .i64 = 0 } },
    };
    var blocks = oneBlock(&instructions);
    var set = try recognize(alloc, .{ .name = "main", .ret = .i64, .blocks = &blocks }, &licence);
    defer set.deinit();
    try testing.expectEqual(@as(usize, 0), set.items.len);
}

test "const_table: base escape declines promotion" {
    const alloc = testing.allocator;
    var licence = try openLicence(alloc, &.{ 10, 20 });
    defer licence.deinit();
    const instructions = [_]dnir.Instr{
        allocSlots(1, 2),
        constStore(1, 1, 10),
        constStore(1, 2, 20),
        .{ .op = .mov_arg, .result = 0, .lhs = .{ .temp = 1 } },
        .{ .op = .call_direct, .result = 9, .callee = "sink" },
        .{ .op = .ret, .lhs = .{ .temp = 9 } },
    };
    var blocks = oneBlock(&instructions);
    var set = try recognize(alloc, .{ .name = "main", .ret = .i64, .blocks = &blocks }, &licence);
    defer set.deinit();
    try testing.expectEqual(@as(usize, 0), set.items.len);
}

test "const_table: empty licence promotes nothing" {
    const alloc = testing.allocator;
    var licence = emptyLicence(alloc);
    defer licence.deinit();
    const instructions = [_]dnir.Instr{
        allocSlots(1, 1),
        constStore(1, 1, 10),
        .{ .op = .load_index, .ty = .i64, .result = 9, .lhs = .{ .temp = 1 }, .rhs = .{ .i64 = 1 } },
        .{ .op = .ret, .lhs = .{ .temp = 9 } },
    };
    var blocks = oneBlock(&instructions);
    var set = try recognize(alloc, .{ .name = "main", .ret = .i64, .blocks = &blocks }, &licence);
    defer set.deinit();
    try testing.expectEqual(@as(usize, 0), set.items.len);
}

fn parseFixture(alloc: std.mem.Allocator, source: []const u8) !ast.Module {
    var lexer = @import("lexer.zig").Lexer.init(source, "const-table-test.id");
    var parser = @import("parser.zig").Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    return try parser.parse_module();
}

test "const_table: source licence permits clean canonical indexed aggregate" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var module = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [3]i64 = {7, 8, 9}
        \\    i = 1
        \\    t[i]
    );
    var licence = try licenceForModule(alloc, &module);
    defer licence.deinit();
    try testing.expect(licence.permits(&.{ 7, 8, 9 }));
}

test "const_table: source licence denies mutation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var module = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [3]i64 = {7, 8, 9}
        \\    t[2] = 5
        \\    t[1]
    );
    var licence = try licenceForModule(alloc, &module);
    defer licence.deinit();
    try testing.expect(!licence.permits(&.{ 7, 8, 9 }));
}

test "const_table: source licence denies aggregate escape" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var module = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [3]i64 = {7, 8, 9}
        \\    sink(t)
        \\    0
    );
    var licence = try licenceForModule(alloc, &module);
    defer licence.deinit();
    try testing.expect(!licence.permits(&.{ 7, 8, 9 }));
}
