//! Which memory-backed positional tables are DATA, and need no code at all.
//!
//! WHAT THIS REPLACES. A table wide enough to need a frame region is built word
//! by word at run time: `alloc_slots` reserves the region and one
//! `store_index` per element fills it, which the backend emits as `mov` the
//! literal / `str` it at a folded offset — TWO INSTRUCTIONS PER ELEMENT, paid
//! before the first read. Measured on this tree, that is the whole residual of
//! the collapse ledger's two runtime-index rows:
//!
//!     width    4    8   16   32   33   64
//!     instrs  38   47   63   95   97  159      slope: exactly 2 per element
//!
//! Nothing about those instructions computes anything. Every word is a compile-
//! time constant that the compiler already holds, being retyped into the frame
//! by the program itself. A table whose contents are known, that nothing writes
//! and nothing escapes, is READ-ONLY DATA; the loop can index it where it lies.
//!
//! THE PRECONDITION IS NOT DECIDED HERE. `table_facts.zig` already computes it
//!
//!     contents_known && !mutated() && !escape.escapes()
//!
//! over the SOURCE, and `licenceForModule` below consumes exactly that — it does
//! not restate the clauses and it does not widen them. Note which clause is
//! absent: index constancy. A table read at a run-time index cannot be folded
//! away (`table_facts.Blocker.variable_index` blocks elimination) but it can
//! still be data, because being read is not being written.
//!
//! WHY THERE IS A SECOND WALK. `recognize` re-establishes the same three facts
//! over the DNIR the backend is about to emit, and a table is promoted only if
//! BOTH agree. That is deliberate redundancy, not distrust of the fact module:
//! the source-level facts are keyed by NAME and the emission is keyed by an
//! `alloc_slots` result temp, so something has to join them, and the join is
//! only sound if it can see that the region it is about to delete really is
//! filled with those constants and really is never written again. This tree has
//! shipped three silent wrong answers, one of them exactly here — a frame table
//! and the spill area overlapped and a scalar read came back 50 instead of 33.
//! A promotion that is wrong does not crash; it returns a number.
//!
//! WHAT MAKES THE JOIN SOUND. `recognize` accepts a base temp only when, over
//! the whole function:
//!
//!   * every element 1..N is stored exactly once, from an i64 LITERAL;
//!   * those stores all precede every other mention of the base;
//!   * every other mention is the base operand of an 8-byte `load_index`;
//!   * nothing else ever defines the base.
//!
//! A write through the base (`t(i) = …`), a second store to one element, a base
//! handed to a call, returned, or copied into a local — each is a mention that
//! is not a read, and each declines. Declining costs instructions; being wrong
//! costs the answer.
//!
//! WHAT THIS DOES NOT DO. It does not decide where the data goes, how it is
//! addressed, or what section holds it. It reports a set of base temps and their
//! words; `native_backend.zig` places them in `__TEXT,__const` and relocates
//! against them.

const std = @import("std");
const ast = @import("ast.zig");
const dnir = @import("native_ir.zig");
const table_facts = @import("table_facts.zig");

const Error = std.mem.Allocator.Error;

/// Widest promotable table, in 8-byte words.
///
/// NOT A NEW LIMIT. It is the bound the frame-region path already enforces —
/// `dnir_lower` refuses a positional table past 4096 elements and the backend's
/// slot-base pass refuses the same — so promotion never widens what the backend
/// accepts. It only changes where an already-accepted table lives.
pub const max_words: i64 = 4096;

/// One promotable table: the `alloc_slots` result temp its base address lives
/// in, and its words in Idol index order (`values[0]` is element 1 — TABLES ARE
/// 1-INDEXED).
pub const Promotion = struct {
    base: u32,
    values: []const i64,
};

pub const Set = struct {
    alloc: std.mem.Allocator,
    items: []Promotion,

    pub fn deinit(self: *Set) void {
        for (self.items) |p| if (p.values.len > 0) self.alloc.free(p.values);
        self.alloc.free(self.items);
        self.* = undefined;
    }
};

/// What the SOURCE-level facts permit, keyed by contents.
///
/// WHY BY CONTENTS AND NOT BY NAME. The DNIR carries no binding name for an
/// `alloc_slots` region, so the two walks cannot be joined on a name. The words
/// are the only thing both sides can see. A vector of words is therefore the
/// key, and the merge rule below is what keeps that sound: if ANY binding in the
/// module with those exact contents fails the precondition, the vector is denied
/// for all of them. A lookalike can only ever make this MORE conservative.
pub const Licence = struct {
    alloc: std.mem.Allocator,
    entries: []Entry,

    pub const Entry = struct {
        values: []const i64,
        /// Every binding in the module with these contents satisfies
        /// `contents_known && !mutated() && !escape.escapes()`.
        clean: bool,
    };

    pub fn deinit(self: *Licence) void {
        for (self.entries) |e| if (e.values.len > 0) self.alloc.free(e.values);
        self.alloc.free(self.entries);
        self.* = undefined;
    }

    pub fn permits(self: *const Licence, values: []const i64) bool {
        if (values.len == 0) return false;
        for (self.entries) |e| {
            if (std.mem.eql(i64, e.values, values)) return e.clean;
        }
        return false;
    }
};

/// The source-level verdict for every positional table bound anywhere in
/// `mod`, taken from `table_facts` and not restated.
pub fn licenceForModule(alloc: std.mem.Allocator, mod: *const ast.Module) Error!Licence {
    var entries: std.ArrayListUnmanaged(Licence.Entry) = .empty;
    errdefer {
        for (entries.items) |e| if (e.values.len > 0) alloc.free(e.values);
        entries.deinit(alloc);
    }
    for (mod.body.stmts) |*st| {
        if (st.* != .func_decl) continue;
        var decisions = try table_facts.analyze(alloc, &st.func_decl.func.body);
        defer decisions.deinit();
        for (decisions.facts) |fact| try note(alloc, &entries, fact);
    }
    return .{ .alloc = alloc, .entries = try entries.toOwnedSlice(alloc) };
}

/// An empty licence — permits nothing. What a caller with no source module in
/// hand gets, so that path keeps today's behaviour exactly.
pub fn emptyLicence(alloc: std.mem.Allocator) Licence {
    return .{ .alloc = alloc, .entries = &.{} };
}

fn note(
    alloc: std.mem.Allocator,
    entries: *std.ArrayListUnmanaged(Licence.Entry),
    fact: table_facts.Facts,
) Error!void {
    // THE PRECONDITION, consumed rather than re-derived. Index constancy is
    // deliberately not among the clauses: a run-time index is why the table has
    // to exist, not a reason it has to be written.
    const clean = fact.width > 0 and
        fact.contents_known and
        !fact.mutated() and
        !fact.escape.escapes();
    for (entries.items) |*e| {
        if (std.mem.eql(i64, e.values, fact.values)) {
            e.clean = e.clean and clean;
            return;
        }
    }
    try entries.append(alloc, .{
        .values = try alloc.dupe(i64, fact.values),
        .clean = clean,
    });
}

// ---------------------------------------------------------------------------
// The DNIR walk.
// ---------------------------------------------------------------------------

/// THE BASE HAS TWO FACES AND THEY ARE ONE STORAGE.
///
/// `lowerPositionalTableIntoMemory` creates the region's base with
/// `freshTemp()` and writes the initializing run against `.temp`, then binds the
/// table's NAME to that same id — so every later read arrives as `.local`. Temps
/// and locals share one id counter and `evalDnirValue` resolves both through the
/// same map, so the two spellings name the same register. A recognizer that
/// matched only `.temp` would see the stores and none of the reads, conclude the
/// base never escapes, and be right by accident; one that matched only `.local`
/// would never see the stores at all.
fn baseOf(v: dnir.Value) ?u32 {
    return switch (v) {
        .temp => |t| t,
        .local => |l| l,
        else => null,
    };
}

/// Any reference to this id at all, through either face.
fn mentions(ins: dnir.Instr, id: u32) bool {
    if (valueMentions(ins.lhs, id)) return true;
    if (valueMentions(ins.rhs, id)) return true;
    if (valueMentions(ins.third, id)) return true;
    for (ins.vals) |v| if (valueMentions(v, id)) return true;
    return false;
}

fn valueMentions(v: dnir.Value, id: u32) bool {
    return switch (v) {
        .temp => |t| t == id,
        .local => |l| l == id,
        else => false,
    };
}

const Element = struct { key: i64, word: i64 };

/// `store_index base, #k, #v` — one element of the initializing run, and the
/// ONLY write shape this recognizer tolerates. Both the index and the value must
/// be literals: an index that is not is a run-time write, and a value that is
/// not is a word this pass cannot put in the section.
fn initializingStore(ins: dnir.Instr, base: u32) ?Element {
    if (ins.op != .store_index or ins.ty != .i64) return null;
    if (baseOf(ins.lhs) != base) return null;
    const key = switch (ins.rhs) {
        .i64 => |n| n,
        else => return null,
    };
    const word = switch (ins.third) {
        .i64 => |n| n,
        else => return null,
    };
    return .{ .key = key, .word = word };
}

/// `load_index base, idx` at 8-byte width — the only other mention a promoted
/// base may have. The base must be the BASE: appearing as the index or as a
/// stored value means the address itself is flowing somewhere, which is an
/// escape.
fn elementRead(ins: dnir.Instr, base: u32) bool {
    if (ins.op != .load_index or ins.ty != .i64) return false;
    if (baseOf(ins.lhs) != base) return false;
    if (valueMentions(ins.rhs, base)) return false;
    if (valueMentions(ins.third, base)) return false;
    for (ins.vals) |v| if (valueMentions(v, base)) return false;
    return true;
}

/// Every table in `f` that can become read-only data, given what the source
/// facts permit.
pub fn recognize(alloc: std.mem.Allocator, f: dnir.Function, lic: *const Licence) Error!Set {
    var items: std.ArrayListUnmanaged(Promotion) = .empty;
    errdefer {
        for (items.items) |p| if (p.values.len > 0) alloc.free(p.values);
        items.deinit(alloc);
    }
    if (lic.entries.len == 0) return .{ .alloc = alloc, .items = try items.toOwnedSlice(alloc) };

    var flat: std.ArrayListUnmanaged(dnir.Instr) = .empty;
    defer flat.deinit(alloc);
    for (f.blocks) |b| try flat.appendSlice(alloc, b.instrs);

    for (flat.items, 0..) |cand, ci| {
        if (cand.op != .alloc_slots) continue;
        const base = cand.result orelse continue;
        const extent: i64 = switch (cand.lhs) {
            .i64 => |v| v,
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
        var last_init: usize = ci;
        var first_other: ?usize = null;
        var ok = true;

        for (flat.items, 0..) |ins, i| {
            if (i == ci) continue;
            // Nothing may redefine the base. `dnir.definition` is the authority
            // on which ops establish a slot, so this cannot drift as ops are
            // added.
            if (dnir.definition(ins)) |d| {
                if (d == base) {
                    ok = false;
                    break;
                }
            }
            if (initializingStore(ins, base)) |elem| {
                if (elem.key < 1 or elem.key > extent) {
                    ok = false;
                    break;
                }
                const slot: usize = @intCast(elem.key - 1);
                // A second store to one element is a MUTATION, and folding it
                // away would publish the first value.
                if (filled[slot]) {
                    ok = false;
                    break;
                }
                filled[slot] = true;
                values[slot] = elem.word;
                stored += 1;
                if (i > last_init) last_init = i;
                continue;
            }
            if (!mentions(ins, base)) continue;
            if (!elementRead(ins, base)) {
                ok = false;
                break;
            }
            if (first_other == null) first_other = i;
        }

        if (!ok or stored != width) continue;
        // A read BEFORE the region is filled reads whatever the frame held. The
        // lowering never emits one, and a promotion would silently change such a
        // read's answer from garbage to the literal, so decline instead.
        if (first_other) |o| {
            if (o < last_init) continue;
        }
        if (!lic.permits(values)) continue;

        try items.append(alloc, .{ .base = base, .values = values });
        keep = true;
    }

    return .{ .alloc = alloc, .items = try items.toOwnedSlice(alloc) };
}

// ---------------------------------------------------------------------------
// Tests.
// ---------------------------------------------------------------------------

const testing = std.testing;

fn openLicence(alloc: std.mem.Allocator, values: []const i64) !Licence {
    const entries = try alloc.alloc(Licence.Entry, 1);
    entries[0] = .{ .values = try alloc.dupe(i64, values), .clean = true };
    return .{ .alloc = alloc, .entries = entries };
}

fn allocSlots(base: u32, n: i64) dnir.Instr {
    return .{ .op = .alloc_slots, .result = base, .lhs = .{ .i64 = n } };
}

fn constStore(base: u32, k: i64, v: i64) dnir.Instr {
    return .{
        .op = .store_index,
        .ty = .i64,
        .lhs = .{ .temp = base },
        .rhs = .{ .i64 = k },
        .third = .{ .i64 = v },
    };
}

fn constLoad(base: u32, k: i64, result: u32) dnir.Instr {
    return .{
        .op = .load_index,
        .ty = .i64,
        .result = result,
        .lhs = .{ .temp = base },
        .rhs = .{ .i64 = k },
    };
}

fn oneBlock(instrs: []const dnir.Instr) [1]dnir.Block {
    return .{.{ .instrs = instrs }};
}

test "const_table: a determined table read at a run-time index is promoted" {
    const alloc = testing.allocator;
    var lic = try openLicence(alloc, &.{ 10, 20, 30 });
    defer lic.deinit();

    const instrs = [_]dnir.Instr{
        allocSlots(1, 3),
        constStore(1, 1, 10),
        constStore(1, 2, 20),
        constStore(1, 3, 30),
        // The index is a temp, not a literal — this is exactly the case
        // elimination cannot reach and data can.
        .{ .op = .load_index, .ty = .i64, .result = 9, .lhs = .{ .temp = 1 }, .rhs = .{ .temp = 7 } },
        .{ .op = .ret, .lhs = .{ .temp = 9 } },
    };
    var blocks = oneBlock(&instrs);
    var set = try recognize(alloc, .{ .name = "main", .ret = .i64, .blocks = &blocks }, &lic);
    defer set.deinit();

    try testing.expectEqual(@as(usize, 1), set.items.len);
    try testing.expectEqual(@as(u32, 1), set.items[0].base);
    try testing.expectEqualSlices(i64, &.{ 10, 20, 30 }, set.items[0].values);
}

test "const_table: THE READ FACE IS `.local` — the real lowering's shape" {
    const alloc = testing.allocator;
    var lic = try openLicence(alloc, &.{ 10, 20 });
    defer lic.deinit();

    // `lowerPositionalTableIntoMemory` writes the initializing run against the
    // `.temp` the region was created as, then binds the table's NAME to that same
    // id — so every read afterwards arrives as `.local`. Matching only `.temp`
    // sees the stores and none of the reads, which is how this recognizer first
    // declined every table it exists to promote.
    const instrs = [_]dnir.Instr{
        allocSlots(1, 2),
        constStore(1, 1, 10),
        constStore(1, 2, 20),
        .{ .op = .load_index, .ty = .i64, .result = 9, .lhs = .{ .local = 1 }, .rhs = .{ .temp = 7 } },
        .{ .op = .ret, .lhs = .{ .temp = 9 } },
    };
    var blocks = oneBlock(&instrs);
    var set = try recognize(alloc, .{ .name = "main", .ret = .i64, .blocks = &blocks }, &lic);
    defer set.deinit();
    try testing.expectEqual(@as(usize, 1), set.items.len);
    try testing.expectEqualSlices(i64, &.{ 10, 20 }, set.items[0].values);
}

test "const_table: a write through the `.local` face declines too" {
    const alloc = testing.allocator;
    var lic = try openLicence(alloc, &.{ 10, 20 });
    defer lic.deinit();

    const instrs = [_]dnir.Instr{
        allocSlots(1, 2),
        constStore(1, 1, 10),
        constStore(1, 2, 20),
        .{ .op = .store_index, .ty = .i64, .lhs = .{ .local = 1 }, .rhs = .{ .temp = 7 }, .third = .{ .temp = 8 } },
        .{ .op = .ret, .lhs = .{ .i64 = 0 } },
    };
    var blocks = oneBlock(&instrs);
    var set = try recognize(alloc, .{ .name = "main", .ret = .i64, .blocks = &blocks }, &lic);
    defer set.deinit();
    try testing.expectEqual(@as(usize, 0), set.items.len);
}

test "const_table: A WRITTEN TABLE IS NOT DATA — a run-time store declines it" {
    const alloc = testing.allocator;
    var lic = try openLicence(alloc, &.{ 10, 20, 30 });
    defer lic.deinit();

    const instrs = [_]dnir.Instr{
        allocSlots(1, 3),
        constStore(1, 1, 10),
        constStore(1, 2, 20),
        constStore(1, 3, 30),
        // `t(i) = v`
        .{ .op = .store_index, .ty = .i64, .lhs = .{ .temp = 1 }, .rhs = .{ .temp = 7 }, .third = .{ .temp = 8 } },
        .{ .op = .ret, .lhs = .{ .i64 = 0 } },
    };
    var blocks = oneBlock(&instrs);
    var set = try recognize(alloc, .{ .name = "main", .ret = .i64, .blocks = &blocks }, &lic);
    defer set.deinit();
    try testing.expectEqual(@as(usize, 0), set.items.len);
}

test "const_table: a second store to ONE element is a mutation and declines" {
    const alloc = testing.allocator;
    var lic = try openLicence(alloc, &.{ 10, 20 });
    defer lic.deinit();

    const instrs = [_]dnir.Instr{
        allocSlots(1, 2),
        constStore(1, 1, 10),
        constStore(1, 2, 20),
        constStore(1, 2, 99),
        .{ .op = .ret, .lhs = .{ .i64 = 0 } },
    };
    var blocks = oneBlock(&instrs);
    var set = try recognize(alloc, .{ .name = "main", .ret = .i64, .blocks = &blocks }, &lic);
    defer set.deinit();
    try testing.expectEqual(@as(usize, 0), set.items.len);
}

test "const_table: AN ESCAPING TABLE IS NOT DATA — the base reaching a call declines it" {
    const alloc = testing.allocator;
    var lic = try openLicence(alloc, &.{ 10, 20 });
    defer lic.deinit();

    const instrs = [_]dnir.Instr{
        allocSlots(1, 2),
        constStore(1, 1, 10),
        constStore(1, 2, 20),
        // `sum(t)` — the base address is handed to a callee, which may write it.
        .{ .op = .mov_arg, .result = 0, .lhs = .{ .temp = 1 } },
        .{ .op = .call_direct, .result = 9, .callee = "sum" },
        .{ .op = .ret, .lhs = .{ .temp = 9 } },
    };
    var blocks = oneBlock(&instrs);
    var set = try recognize(alloc, .{ .name = "main", .ret = .i64, .blocks = &blocks }, &lic);
    defer set.deinit();
    try testing.expectEqual(@as(usize, 0), set.items.len);
}

test "const_table: a partly-filled region declines" {
    const alloc = testing.allocator;
    var lic = try openLicence(alloc, &.{ 10, 20, 30 });
    defer lic.deinit();

    const instrs = [_]dnir.Instr{
        allocSlots(1, 3),
        constStore(1, 1, 10),
        constStore(1, 3, 30),
        constLoad(1, 1, 9),
        .{ .op = .ret, .lhs = .{ .temp = 9 } },
    };
    var blocks = oneBlock(&instrs);
    var set = try recognize(alloc, .{ .name = "main", .ret = .i64, .blocks = &blocks }, &lic);
    defer set.deinit();
    try testing.expectEqual(@as(usize, 0), set.items.len);
}

test "const_table: contents built from registers (not literals) decline" {
    const alloc = testing.allocator;
    var lic = try openLicence(alloc, &.{ 10, 20 });
    defer lic.deinit();

    const instrs = [_]dnir.Instr{
        allocSlots(1, 2),
        constStore(1, 1, 10),
        // `materializeTableSlots` copies from element LOCALS, not literals.
        .{ .op = .store_index, .ty = .i64, .lhs = .{ .temp = 1 }, .rhs = .{ .i64 = 2 }, .third = .{ .local = 5 } },
        .{ .op = .ret, .lhs = .{ .i64 = 0 } },
    };
    var blocks = oneBlock(&instrs);
    var set = try recognize(alloc, .{ .name = "main", .ret = .i64, .blocks = &blocks }, &lic);
    defer set.deinit();
    try testing.expectEqual(@as(usize, 0), set.items.len);
}

test "const_table: a read BEFORE the region is filled declines" {
    const alloc = testing.allocator;
    var lic = try openLicence(alloc, &.{ 10, 20 });
    defer lic.deinit();

    const instrs = [_]dnir.Instr{
        allocSlots(1, 2),
        constLoad(1, 1, 9),
        constStore(1, 1, 10),
        constStore(1, 2, 20),
        .{ .op = .ret, .lhs = .{ .temp = 9 } },
    };
    var blocks = oneBlock(&instrs);
    var set = try recognize(alloc, .{ .name = "main", .ret = .i64, .blocks = &blocks }, &lic);
    defer set.deinit();
    try testing.expectEqual(@as(usize, 0), set.items.len);
}

test "const_table: AN EMPTY LICENCE PROMOTES NOTHING — the source facts are required" {
    const alloc = testing.allocator;
    var lic = emptyLicence(alloc);
    defer lic.deinit();

    const instrs = [_]dnir.Instr{
        allocSlots(1, 2),
        constStore(1, 1, 10),
        constStore(1, 2, 20),
        constLoad(1, 1, 9),
        .{ .op = .ret, .lhs = .{ .temp = 9 } },
    };
    var blocks = oneBlock(&instrs);
    var set = try recognize(alloc, .{ .name = "main", .ret = .i64, .blocks = &blocks }, &lic);
    defer set.deinit();
    try testing.expectEqual(@as(usize, 0), set.items.len);
}

// --- the source side: what `table_facts` licenses ---------------------------

fn parseFixture(alloc: std.mem.Allocator, source: []const u8) !ast.Module {
    var lexer = @import("lexer.zig").Lexer.init(source, "const-table-test.id");
    var parser = @import("parser.zig").Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    // `t(k)` is a `.call` until this runs, and every access would then read as
    // an aggregate use — sound, but vacuous.
    const sema = @import("sema.zig");
    var type_map = sema.TypeMap.init(alloc);
    defer type_map.deinit();
    @import("table_apply.zig").normalizeModule(alloc, &module, &type_map);
    return module;
}

test "const_table: the licence follows table_facts — determined permits, written denies" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var mod = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t = (7, 8, 9)
        \\    i = 1
        \\    t(i)
        \\
    );
    var lic = try licenceForModule(alloc, &mod);
    defer lic.deinit();
    try testing.expect(lic.permits(&.{ 7, 8, 9 }));
    try testing.expect(!lic.permits(&.{ 7, 8 }));
}

test "const_table: A MUTATED TABLE IS DENIED BY THE SOURCE FACTS" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var mod = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t = (7, 8, 9)
        \\    t(2) = 5
        \\    t(1)
        \\
    );
    var lic = try licenceForModule(alloc, &mod);
    defer lic.deinit();
    try testing.expect(!lic.permits(&.{ 7, 8, 9 }));
}

test "const_table: AN ESCAPING TABLE IS DENIED BY THE SOURCE FACTS" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var mod = try parseFixture(alloc,
        \\sum: i64 = (xs: [3]i64)
        \\    xs(1)
        \\
        \\main: i64 = ()
        \\    t = (7, 8, 9)
        \\    sum(t)
        \\
    );
    var lic = try licenceForModule(alloc, &mod);
    defer lic.deinit();
    try testing.expect(!lic.permits(&.{ 7, 8, 9 }));
}

test "const_table: ONE DIRTY LOOKALIKE DENIES THE CONTENTS FOR EVERY BINDING" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var mod = try parseFixture(alloc,
        \\clean: i64 = ()
        \\    a = (7, 8, 9)
        \\    i = 1
        \\    a(i)
        \\
        \\dirty: i64 = ()
        \\    b = (7, 8, 9)
        \\    b(2) = 5
        \\    b(1)
        \\
    );
    var lic = try licenceForModule(alloc, &mod);
    defer lic.deinit();
    // Contents are the only key the two walks share, so a lookalike that fails
    // the precondition has to deny the vector for both. Conservative by
    // construction: the merge can only ever take a `clean` away.
    try testing.expect(!lic.permits(&.{ 7, 8, 9 }));
}
