//! Conservative facts for positional aggregate realization.
//!
//! This module answers one bounded physical question after syntax has already
//! established meaning: can a positional aggregate disappear, and if not, does
//! its current native realization require a select-chain/register form or a
//! contiguous memory form?
//!
//! It does not reinterpret syntax. `t[k]` is computed/indexed projection;
//! `t(k)` is ordinary application and therefore an aggregate use. It does not
//! consult sema types or `table_apply`, and it never turns one category into the
//! other.
//!
//! The analysis remains deliberately conservative while exact graph access ids
//! replace name/AST provenance under GAP-201. Unknown or unmodelled uses remove
//! elimination freedom rather than inventing a proof.

const std = @import("std");
const ast = @import("ast.zig");
const escape = @import("escape.zig");

const Error = std.mem.Allocator.Error;

/// Physical feasibility threshold for a select-chain representation. This does
/// not decide whether an aggregate exists; elimination is considered first and
/// is independent of width.
pub const select_chain_max: i64 = 32;

/// The exact constant-index predicate shared by this fact collector. Deliberately
/// narrow: widening it requires the access realizer to widen in the same change.
pub fn constIndex(expr: *const ast.Expr) ?i64 {
    return switch (expr.*) {
        .int_lit => |value| value.val,
        .unop => |unary| blk: {
            if (unary.op != .neg or unary.operand.* != .int_lit) break :blk null;
            break :blk -unary.operand.int_lit.val;
        },
        else => null,
    };
}

pub const Representation = enum {
    absent,
    registers,
    memory,
};

pub const Blocker = enum {
    none,
    escapes,
    contents_unknown,
    variable_index,
    mutated,
    index_out_of_range,
    unsupported_width,
};

pub const Facts = struct {
    name: []const u8,
    width: u32 = 0,
    contents_known: bool = false,
    values: []const i64 = &.{},
    read_const: bool = false,
    read_var: bool = false,
    write_const: bool = false,
    write_var: bool = false,
    length_read: bool = false,
    distinct_const_indices: u32 = 0,
    const_index_out_of_range: bool = false,
    escape: escape.Escape = .{},

    pub fn readAtAll(self: Facts) bool {
        return self.read_const or self.read_var;
    }

    pub fn mutated(self: Facts) bool {
        return self.write_const or self.write_var;
    }

    pub fn allIndicesConstant(self: Facts) bool {
        return !self.read_var and !self.write_var;
    }

    pub fn blocker(self: Facts) Blocker {
        if (self.width == 0) return .unsupported_width;
        if (self.escape.escapes()) return .escapes;
        if (!self.contents_known) return .contents_unknown;
        if (!self.allIndicesConstant()) return .variable_index;
        if (self.mutated()) return .mutated;
        if (self.const_index_out_of_range) return .index_out_of_range;
        return .none;
    }

    pub fn soloRepresentation(self: Facts) Representation {
        if (self.blocker() == .none) return .absent;
        if (@as(i64, self.width) > select_chain_max) return .memory;
        if (self.escape.escapes()) return .memory;
        return .registers;
    }

    /// Idol aggregate indexing is one-based on this compatibility realization.
    pub fn at(self: Facts, index: i64) ?i64 {
        if (self.blocker() != .none) return null;
        if (index < 1 or index > @as(i64, self.width)) return null;
        return self.values[@intCast(index - 1)];
    }
};

pub const Decisions = struct {
    alloc: std.mem.Allocator,
    facts: []Facts,
    reps: []Representation,
    unmodelled: bool = false,

    pub fn deinit(self: *Decisions) void {
        for (self.facts) |fact| if (fact.values.len > 0) self.alloc.free(fact.values);
        self.alloc.free(self.facts);
        self.alloc.free(self.reps);
        self.* = undefined;
    }

    pub fn get(self: *const Decisions, name: []const u8) ?Representation {
        for (self.facts, self.reps) |fact, representation| {
            if (std.mem.eql(u8, fact.name, name)) return representation;
        }
        return null;
    }

    pub fn factsFor(self: *const Decisions, name: []const u8) ?Facts {
        for (self.facts) |fact| {
            if (std.mem.eql(u8, fact.name, name)) return fact;
        }
        return null;
    }

    /// Materialized aggregates in one relation currently use one physical
    /// family. Absent aggregates have no representation and do not participate.
    pub fn uniform(self: *const Decisions) bool {
        var registers = false;
        var memory = false;
        for (self.reps) |representation| switch (representation) {
            .absent => {},
            .registers => registers = true,
            .memory => memory = true,
        };
        return !(registers and memory);
    }

    pub fn tablesInMemory(self: *const Decisions) bool {
        for (self.reps) |representation| if (representation == .memory) return true;
        return false;
    }

    pub fn eliminated(self: *const Decisions) u32 {
        var count: u32 = 0;
        for (self.reps) |representation| {
            if (representation == .absent) count += 1;
        }
        return count;
    }
};

pub fn analyze(alloc: std.mem.Allocator, body: *const ast.Block) Error!Decisions {
    var facts: std.ArrayListUnmanaged(Facts) = .empty;
    errdefer {
        for (facts.items) |fact| if (fact.values.len > 0) alloc.free(fact.values);
        facts.deinit(alloc);
    }

    var unmodelled = false;
    try collectBindings(alloc, body, &facts, &unmodelled);

    for (facts.items) |*fact| {
        var seen: std.AutoHashMapUnmanaged(i64, void) = .empty;
        defer seen.deinit(alloc);
        try classifyBlock(alloc, body, fact, &seen);
        fact.distinct_const_indices = @intCast(seen.count());
        fact.escape = escape.positionalTableEscapes(body, fact.name);
    }

    const reps = try alloc.alloc(Representation, facts.items.len);
    errdefer alloc.free(reps);
    for (facts.items, reps) |fact, *representation| {
        representation.* = if (unmodelled and fact.soloRepresentation() == .absent)
            fallbackRepresentation(fact)
        else
            fact.soloRepresentation();
    }

    // Preserve the current native invariant: every aggregate that remains
    // materialized in a relation uses one representation family.
    var any_memory = false;
    for (reps) |representation| if (representation == .memory) {
        any_memory = true;
    };
    if (any_memory) {
        for (reps) |*representation| if (representation.* == .registers) {
            representation.* = .memory;
        };
    }

    return .{
        .alloc = alloc,
        .facts = try facts.toOwnedSlice(alloc),
        .reps = reps,
        .unmodelled = unmodelled,
    };
}

fn fallbackRepresentation(fact: Facts) Representation {
    return if (@as(i64, fact.width) > select_chain_max) .memory else .registers;
}

fn positionalWidth(expr: *const ast.Expr) ?u32 {
    if (expr.* != .table) return null;
    var width: u32 = 0;
    for (expr.table.fields) |field| {
        if (field != .positional) return null;
        width += 1;
    }
    return width;
}

fn recordBinding(
    alloc: std.mem.Allocator,
    name: []const u8,
    init: *const ast.Expr,
    out: *std.ArrayListUnmanaged(Facts),
) Error!void {
    const width = positionalWidth(init) orelse return;

    for (out.items) |*fact| {
        if (std.mem.eql(u8, fact.name, name)) {
            fact.escape.reason = .rebound;
            return;
        }
    }

    var values = try alloc.alloc(i64, width);
    errdefer alloc.free(values);
    var known = true;
    for (init.table.fields, 0..) |field, index| {
        if (constIndex(field.positional)) |value| {
            values[index] = value;
        } else {
            known = false;
            values[index] = 0;
        }
    }
    if (!known) {
        alloc.free(values);
        values = &.{};
    }

    try out.append(alloc, .{
        .name = name,
        .width = width,
        .contents_known = known,
        .values = values,
    });
}

fn collectBindings(
    alloc: std.mem.Allocator,
    block: *const ast.Block,
    out: *std.ArrayListUnmanaged(Facts),
    unmodelled: *bool,
) Error!void {
    for (block.stmts) |statement| switch (statement) {
        .local_decl => |declaration| {
            for (declaration.names, 0..) |local, index| {
                if (index < declaration.inits.len)
                    try recordBinding(alloc, local.ident, declaration.inits[index], out);
            }
        },
        .global_decl => |declaration| {
            for (declaration.names, 0..) |local, index| {
                if (index < declaration.inits.len)
                    try recordBinding(alloc, local.ident, declaration.inits[index], out);
            }
        },
        .const_decl => |declaration| try recordBinding(alloc, declaration.ident, declaration.val, out),
        .assign => |assignment| {
            for (assignment.targets, 0..) |target, index| {
                if (target.* == .name and index < assignment.values.len)
                    try recordBinding(alloc, target.name.ident, assignment.values[index], out);
            }
        },
        .do_block => |nested| try collectBindings(alloc, &nested.body, out, unmodelled),
        .while_loop => |loop| try collectBindings(alloc, &loop.body, out, unmodelled),
        .repeat_loop => |loop| try collectBindings(alloc, &loop.body, out, unmodelled),
        .num_for => |loop| try collectBindings(alloc, &loop.body, out, unmodelled),
        .gen_for => |loop| try collectBindings(alloc, &loop.body, out, unmodelled),
        .if_stmt => |conditional| {
            try collectBindings(alloc, &conditional.then, out, unmodelled);
            for (conditional.elseifs) |alternative|
                try collectBindings(alloc, &alternative.body, out, unmodelled);
            if (conditional.else_body) |body|
                try collectBindings(alloc, &body, out, unmodelled);
        },
        .call_stmt, .expr_stmt, .ret, .brk, .cont, .goto_stmt, .label_stmt => {},
        else => unmodelled.* = true,
    };
}

const Seen = std.AutoHashMapUnmanaged(i64, void);

fn noteIndex(
    alloc: std.mem.Allocator,
    fact: *Facts,
    key: *const ast.Expr,
    write: bool,
    seen: *Seen,
) Error!void {
    if (constIndex(key)) |index| {
        try seen.put(alloc, index, {});
        if (index < 1 or index > @as(i64, fact.width)) fact.const_index_out_of_range = true;
        if (write) fact.write_const = true else fact.read_const = true;
    } else {
        if (write) fact.write_var = true else fact.read_var = true;
    }
}

fn classifyExpr(alloc: std.mem.Allocator, expr: *const ast.Expr, fact: *Facts, seen: *Seen) Error!void {
    switch (expr.*) {
        .index => |index| {
            if (index.obj.* == .name and std.mem.eql(u8, index.obj.name.ident, fact.name)) {
                try noteIndex(alloc, fact, index.key, false, seen);
            } else {
                try classifyExpr(alloc, index.obj, fact, seen);
            }
            try classifyExpr(alloc, index.key, fact, seen);
        },
        .unop => |unary| {
            if (unary.op == .len and unary.operand.* == .name and
                std.mem.eql(u8, unary.operand.name.ident, fact.name))
            {
                fact.length_read = true;
                return;
            }
            try classifyExpr(alloc, unary.operand, fact, seen);
        },
        .binop => |binary| {
            try classifyExpr(alloc, binary.lhs, fact, seen);
            try classifyExpr(alloc, binary.rhs, fact, seen);
        },
        .field => |field| try classifyExpr(alloc, field.obj, fact, seen),
        .call => |call| {
            // Ordinary application is never converted into an index. Escape
            // legality is decided independently by `escape.zig`.
            try classifyExpr(alloc, call.func, fact, seen);
            for (call.args) |arg| try classifyExpr(alloc, arg, fact, seen);
        },
        .method_call => |call| {
            if (escape.isLengthFace(call.method, call.args.len) and
                call.obj.* == .name and std.mem.eql(u8, call.obj.name.ident, fact.name))
            {
                fact.length_read = true;
                return;
            }
            try classifyExpr(alloc, call.obj, fact, seen);
            for (call.args) |arg| try classifyExpr(alloc, arg, fact, seen);
        },
        .table => |table| for (table.fields) |field| switch (field) {
            .indexed => |value| {
                try classifyExpr(alloc, value.key, fact, seen);
                try classifyExpr(alloc, value.val, fact, seen);
            },
            .named => |value| try classifyExpr(alloc, value.val, fact, seen),
            .positional => |value| try classifyExpr(alloc, value, fact, seen),
            .spread => |value| try classifyExpr(alloc, value, fact, seen),
            .semantic => |value| try classifyExpr(alloc, value.val, fact, seen),
        },
        .sequence => |sequence| for (sequence.exprs) |value| try classifyExpr(alloc, value, fact, seen),
        .range => |range| {
            try classifyExpr(alloc, range.start, fact, seen);
            try classifyExpr(alloc, range.end, fact, seen);
            if (range.step) |step| try classifyExpr(alloc, step, fact, seen);
        },
        .contains_expr => |contains| {
            try classifyExpr(alloc, contains.lhs, fact, seen);
            try classifyExpr(alloc, contains.rhs, fact, seen);
        },
        .try_expr => |value| try classifyExpr(alloc, value.operand, fact, seen),
        .unwrap_expr => |value| try classifyExpr(alloc, value.operand, fact, seen),
        .await_expr => |value| try classifyExpr(alloc, value.operand, fact, seen),
        .if_expr => |conditional| {
            try classifyExpr(alloc, conditional.cond, fact, seen);
            try classifyExpr(alloc, conditional.then_expr, fact, seen);
            try classifyExpr(alloc, conditional.else_expr, fact, seen);
        },
        else => {},
    }
}

fn classifyBlock(alloc: std.mem.Allocator, block: *const ast.Block, fact: *Facts, seen: *Seen) Error!void {
    for (block.stmts) |statement| try classifyStmt(alloc, &statement, fact, seen);
    if (block.tail_expr) |tail| try classifyExpr(alloc, tail, fact, seen);
}

fn classifyStmt(alloc: std.mem.Allocator, statement: *const ast.Stmt, fact: *Facts, seen: *Seen) Error!void {
    switch (statement.*) {
        .local_decl => |declaration| for (declaration.inits) |init| try classifyExpr(alloc, init, fact, seen),
        .global_decl => |declaration| for (declaration.inits) |init| try classifyExpr(alloc, init, fact, seen),
        .const_decl => |declaration| try classifyExpr(alloc, declaration.val, fact, seen),
        .assign => |assignment| {
            for (assignment.targets) |target| {
                if (target.* == .index and target.index.obj.* == .name and
                    std.mem.eql(u8, target.index.obj.name.ident, fact.name))
                {
                    try noteIndex(alloc, fact, target.index.key, true, seen);
                    try classifyExpr(alloc, target.index.key, fact, seen);
                } else {
                    try classifyExpr(alloc, target, fact, seen);
                }
            }
            for (assignment.values) |value| try classifyExpr(alloc, value, fact, seen);
        },
        .call_stmt => |call| try classifyExpr(alloc, call.expr, fact, seen),
        .expr_stmt => |expression| try classifyExpr(alloc, expression.expr, fact, seen),
        .do_block => |nested| try classifyBlock(alloc, &nested.body, fact, seen),
        .while_loop => |loop| {
            try classifyExpr(alloc, loop.cond, fact, seen);
            try classifyBlock(alloc, &loop.body, fact, seen);
        },
        .repeat_loop => |loop| {
            try classifyBlock(alloc, &loop.body, fact, seen);
            try classifyExpr(alloc, loop.cond, fact, seen);
        },
        .if_stmt => |conditional| {
            if (conditional.binding) |binding| try classifyExpr(alloc, binding.expr, fact, seen);
            try classifyExpr(alloc, conditional.cond, fact, seen);
            try classifyBlock(alloc, &conditional.then, fact, seen);
            for (conditional.elseifs) |alternative| {
                try classifyExpr(alloc, alternative.cond, fact, seen);
                try classifyBlock(alloc, &alternative.body, fact, seen);
            }
            if (conditional.else_body) |body| try classifyBlock(alloc, &body, fact, seen);
        },
        .num_for => |loop| {
            try classifyExpr(alloc, loop.start, fact, seen);
            try classifyExpr(alloc, loop.stop, fact, seen);
            if (loop.step) |step| try classifyExpr(alloc, step, fact, seen);
            try classifyBlock(alloc, &loop.body, fact, seen);
        },
        .gen_for => |loop| {
            for (loop.iters) |iter| try classifyExpr(alloc, iter, fact, seen);
            try classifyBlock(alloc, &loop.body, fact, seen);
        },
        .ret => |result| for (result.vals) |value| try classifyExpr(alloc, value, fact, seen),
        else => {},
    }
}

const testing = std.testing;

const Parsed = struct {
    module: ast.Module,

    fn body(self: *const Parsed) *const ast.Block {
        for (self.module.body.stmts) |*statement| {
            if (statement.* == .func_decl) return &statement.func_decl.func.body;
        }
        unreachable;
    }
};

fn parseFixture(alloc: std.mem.Allocator, source: []const u8) !Parsed {
    var lexer = @import("lexer.zig").Lexer.init(source, "table-facts-test.id");
    var parser = @import("parser.zig").Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    return .{ .module = try parser.parse_module() };
}

fn constTableFixture(alloc: std.mem.Allocator, width: u32) ![]const u8 {
    var source: std.ArrayListUnmanaged(u8) = .empty;
    var digits: [24]u8 = undefined;
    try source.appendSlice(alloc, "main: i64 = ()\n    t: [");
    try source.appendSlice(alloc, std.fmt.bufPrint(&digits, "{d}", .{width}) catch unreachable);
    try source.appendSlice(alloc, "]i64 = {");
    for (1..width + 1) |value| {
        if (value > 1) try source.appendSlice(alloc, ", ");
        try source.appendSlice(alloc, std.fmt.bufPrint(&digits, "{d}", .{value}) catch unreachable);
    }
    try source.appendSlice(alloc, "}\n    t[2]\n");
    return source.toOwnedSlice(alloc);
}

test "table_facts: known immutable constant projections are absent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [4]i64 = {10, 20, 30, 40}
        \\    t[1] + t[4]
    );
    var decisions = try analyze(alloc, parsed.body());
    defer decisions.deinit();
    const fact = decisions.factsFor("t").?;
    try testing.expectEqual(Blocker.none, fact.blocker());
    try testing.expectEqual(@as(u32, 2), fact.distinct_const_indices);
    try testing.expectEqual(@as(?i64, 10), fact.at(1));
    try testing.expectEqual(@as(?i64, 40), fact.at(4));
    try testing.expectEqual(@as(?Representation, .absent), decisions.get("t"));
}

test "table_facts: elimination has no size bound" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    for ([_]u32{ 2, 4, 32, 33, 64, 1000, 4096, 4097 }) |width| {
        const source = try constTableFixture(alloc, width);
        const parsed = try parseFixture(alloc, source);
        var decisions = try analyze(alloc, parsed.body());
        defer decisions.deinit();
        const fact = decisions.factsFor("t").?;
        try testing.expectEqual(Blocker.none, fact.blocker());
        try testing.expectEqual(@as(?Representation, .absent), decisions.get("t"));
        try testing.expectEqual(@as(?i64, 2), fact.at(2));
    }
}

test "table_facts: bounds preserve trap obligation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [3]i64 = {7, 8, 9}
        \\    t[0]
    );
    var decisions = try analyze(alloc, parsed.body());
    defer decisions.deinit();
    const fact = decisions.factsFor("t").?;
    try testing.expect(fact.const_index_out_of_range);
    try testing.expectEqual(Blocker.index_out_of_range, fact.blocker());
    try testing.expectEqual(@as(?i64, null), fact.at(0));
}

test "table_facts: runtime index blocks elimination" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [4]i64 = {10, 20, 30, 40}
        \\    i = 2
        \\    t[i]
    );
    var decisions = try analyze(alloc, parsed.body());
    defer decisions.deinit();
    const fact = decisions.factsFor("t").?;
    try testing.expect(fact.read_var);
    try testing.expectEqual(Blocker.variable_index, fact.blocker());
    try testing.expectEqual(@as(?Representation, .registers), decisions.get("t"));
}

test "table_facts: indexed write blocks elimination" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [4]i64 = {10, 20, 30, 40}
        \\    t[1] = 99
        \\    t[1]
    );
    var decisions = try analyze(alloc, parsed.body());
    defer decisions.deinit();
    const fact = decisions.factsFor("t").?;
    try testing.expect(fact.write_const);
    try testing.expectEqual(Blocker.mutated, fact.blocker());
}

test "table_facts: ordinary application is aggregate escape, never index" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [4]i64 = {10, 20, 30, 40}
        \\    t(2)
    );
    var decisions = try analyze(alloc, parsed.body());
    defer decisions.deinit();
    const fact = decisions.factsFor("t").?;
    try testing.expect(!fact.readAtAll());
    try testing.expectEqual(escape.Reason.aggregate_use, fact.escape.reason);
    try testing.expectEqual(Blocker.escapes, fact.blocker());
}

test "table_facts: extent read does not force storage" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [4]i64 = {10, 20, 30, 40}
        \\    t:len()
    );
    var decisions = try analyze(alloc, parsed.body());
    defer decisions.deinit();
    const fact = decisions.factsFor("t").?;
    try testing.expect(fact.length_read);
    try testing.expect(!fact.escape.escapes());
    try testing.expectEqual(@as(?Representation, .absent), decisions.get("t"));
}

test "table_facts: passing aggregate escapes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [4]i64 = {10, 20, 30, 40}
        \\    sink(t)
        \\    0
    );
    var decisions = try analyze(alloc, parsed.body());
    defer decisions.deinit();
    const fact = decisions.factsFor("t").?;
    try testing.expectEqual(escape.Reason.aggregate_use, fact.escape.reason);
    try testing.expectEqual(Blocker.escapes, fact.blocker());
}

test "table_facts: materialized tables remain uniform" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    wide: [33]i64 = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33}
        \\    narrow: [3]i64 = {7, 8, 9}
        \\    i = 2
        \\    narrow[1] = 5
        \\    wide[i] + narrow[1]
    );
    var decisions = try analyze(alloc, parsed.body());
    defer decisions.deinit();
    try testing.expectEqual(@as(?Representation, .memory), decisions.get("wide"));
    try testing.expectEqual(@as(?Representation, .memory), decisions.get("narrow"));
    try testing.expect(decisions.uniform());
}

test "table_facts: unmodelled construct fails closed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [2]i64 = {1, 2}
        \\    inner: i64 = ()
        \\        t[1]
        \\    inner()
    );
    var decisions = try analyze(alloc, parsed.body());
    defer decisions.deinit();
    try testing.expect(decisions.unmodelled);
    try testing.expect(decisions.get("t").? != .absent);
}
