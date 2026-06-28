const std = @import("std");
const ast = @import("ast.zig");

pub const EvalError = error{
    UnsupportedExpression,
    UnsupportedOperator,
    DivisionByZero,
    StepLimitExceeded,
};

pub const Options = struct {
    step_limit: usize = 10_000,
    alloc: ?std.mem.Allocator = null,
};

pub const Value = union(enum) {
    pub const TableEntry = struct {
        key: ?Value = null,
        name: ?[]const u8 = null,
        val: Value,
    };

    unavailable,
    nil,
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,
    table: []const TableEntry,

    fn truthy(self: Value) bool {
        return switch (self) {
            .nil, .unavailable => false,
            .bool => |v| v,
            else => true,
        };
    }

    fn eql(self: Value, other: Value) bool {
        return switch (self) {
            .unavailable => other == .unavailable,
            .nil => other == .nil,
            .bool => |v| other == .bool and other.bool == v,
            .int => |v| other == .int and other.int == v,
            .float => |v| other == .float and other.float == v,
            .string => |v| other == .string and std.mem.eql(u8, other.string, v),
            .table => false,
        };
    }
};

pub const Bindings = struct {
    scopes: []const std.StringHashMapUnmanaged(Value) = &.{},

    fn get(self: Bindings, name: []const u8) ?Value {
        var i = self.scopes.len;
        while (i > 0) {
            i -= 1;
            if (self.scopes[i].get(name)) |value| return value;
        }
        return null;
    }
};

pub const Evaluator = struct {
    const LocalBinding = struct {
        name: []const u8,
        value: Value,
    };

    bindings: Bindings = .{},
    options: Options = .{},
    locals: std.ArrayListUnmanaged(LocalBinding) = .empty,
    steps: usize = 0,

    fn step(self: *Evaluator) EvalError!void {
        self.steps += 1;
        if (self.steps > self.options.step_limit) return error.StepLimitExceeded;
    }

    fn lookup(self: *const Evaluator, name: []const u8) ?Value {
        var i = self.locals.items.len;
        while (i > 0) {
            i -= 1;
            const binding = self.locals.items[i];
            if (std.mem.eql(u8, binding.name, name)) return binding.value;
        }
        return self.bindings.get(name);
    }

    fn pushLocal(self: *Evaluator, name: []const u8, value: Value) EvalError!usize {
        const alloc = self.options.alloc orelse return error.UnsupportedExpression;
        const mark = self.locals.items.len;
        self.locals.append(alloc, .{ .name = name, .value = value }) catch return error.UnsupportedExpression;
        return mark;
    }

    fn popLocals(self: *Evaluator, mark: usize) void {
        self.locals.shrinkRetainingCapacity(mark);
    }

    pub fn eval(self: *Evaluator, expr: *const ast.Expr) EvalError!Value {
        try self.step();
        return switch (expr.*) {
            .nil => .nil,
            .true_lit => .{ .bool = true },
            .false_lit => .{ .bool = false },
            .int_lit => |lit| .{ .int = lit.val },
            .float_lit => |lit| .{ .float = lit.val },
            .string_lit => |lit| .{ .string = lit.val },
            .name => |name| blk: {
                const value = self.lookup(name.ident) orelse return error.UnsupportedExpression;
                if (value == .unavailable) return error.UnsupportedExpression;
                break :blk value;
            },
            .call => |call| blk: {
                if (call.func.* == .name and std.mem.eql(u8, call.func.name.ident, "__constexpr") and call.args.len == 1) {
                    break :blk try self.eval(call.args[0]);
                }
                return error.UnsupportedExpression;
            },
            .index => |index| blk: {
                const obj = try self.eval(index.obj);
                const key = try self.eval(index.key);
                break :blk try tableLookup(obj, key);
            },
            .field => |field| blk: {
                const obj = try self.eval(field.obj);
                break :blk try tableFieldLookup(obj, field.field);
            },
            .unop => |unop| try self.evalUnop(unop.op, unop.operand),
            .binop => |binop| try self.evalBinop(binop.op, binop.lhs, binop.rhs),
            .table => |table| try self.evalTable(table.fields),
            .match_expr => |match_expr| try self.evalMatch(match_expr),
            else => error.UnsupportedExpression,
        };
    }

    fn evalTable(self: *Evaluator, fields: []const ast.TableField) EvalError!Value {
        const alloc = self.options.alloc orelse return error.UnsupportedExpression;
        const entries = alloc.alloc(Value.TableEntry, fields.len) catch return error.UnsupportedExpression;
        var pos: i64 = 1;
        for (fields, 0..) |field, i| {
            entries[i] = switch (field) {
                .positional => |expr| blk: {
                    const value = try self.eval(expr);
                    const entry = Value.TableEntry{ .key = .{ .int = pos }, .val = value };
                    pos += 1;
                    break :blk entry;
                },
                .named => |named| .{ .name = named.key, .val = try self.eval(named.val) },
                .indexed => |indexed| .{ .key = try self.eval(indexed.key), .val = try self.eval(indexed.val) },
            };
        }
        return .{ .table = entries };
    }

    fn evalUnop(self: *Evaluator, op: ast.UnOp, operand: *const ast.Expr) EvalError!Value {
        const value = try self.eval(operand);
        return switch (op) {
            .compile => value,
            .not => .{ .bool = !value.truthy() },
            .neg => switch (value) {
                .int => |v| .{ .int = -v },
                .float => |v| .{ .float = -v },
                else => error.UnsupportedOperator,
            },
            .bnot => switch (value) {
                .int => |v| .{ .int = ~v },
                else => error.UnsupportedOperator,
            },
            .len => switch (value) {
                .string => |v| .{ .int = @intCast(v.len) },
                else => error.UnsupportedOperator,
            },
        };
    }

    fn evalBinop(self: *Evaluator, op: ast.BinOp, lhs: *const ast.Expr, rhs: *const ast.Expr) EvalError!Value {
        if (op == .@"and") {
            const left = try self.eval(lhs);
            return if (left.truthy()) try self.eval(rhs) else left;
        }
        if (op == .@"or") {
            const left = try self.eval(lhs);
            return if (left.truthy()) left else try self.eval(rhs);
        }

        const left = try self.eval(lhs);
        const right = try self.eval(rhs);
        return switch (op) {
            .add, .sub, .mul, .div, .idiv, .mod, .pow => try evalNumeric(op, left, right),
            .band, .bor, .bxor, .lshift, .rshift => try evalInteger(op, left, right),
            .concat => try self.evalConcat(left, right),
            .eq => .{ .bool = left.eql(right) },
            .neq => .{ .bool = !left.eql(right) },
            .lt, .gt, .leq, .geq => try evalComparison(op, left, right),
            .contains, .@"and", .@"or" => error.UnsupportedOperator,
        };
    }

    fn evalConcat(self: *Evaluator, left: Value, right: Value) EvalError!Value {
        if (left != .string or right != .string) return error.UnsupportedOperator;
        if (left.string.len == 0) return right;
        if (right.string.len == 0) return left;
        const alloc = self.options.alloc orelse return error.UnsupportedOperator;
        const joined = alloc.alloc(u8, left.string.len + right.string.len) catch return error.UnsupportedExpression;
        @memcpy(joined[0..left.string.len], left.string);
        @memcpy(joined[left.string.len..], right.string);
        return .{ .string = joined };
    }

    fn evalMatch(self: *Evaluator, match_expr: *const ast.MatchExpr) EvalError!Value {
        const scrutinee = try self.eval(match_expr.scrutinee);
        for (match_expr.arms) |arm| {
            const mark = self.locals.items.len;
            const matched = try self.matchPattern(arm.pattern, scrutinee);
            if (!matched) {
                self.popLocals(mark);
                continue;
            }
            if (arm.guard) |guard| {
                if (!(try self.eval(guard)).truthy()) {
                    self.popLocals(mark);
                    continue;
                }
            }
            const result = self.evalBlockResult(&arm.body);
            self.popLocals(mark);
            return result;
        }
        return error.UnsupportedExpression;
    }

    fn matchPattern(self: *Evaluator, pattern: ast.Pattern, value: Value) EvalError!bool {
        return switch (pattern) {
            .wildcard => true,
            .literal => |lit| (try self.eval(lit)).eql(value),
            .binding => |binding| blk: {
                _ = try self.pushLocal(binding.name, value);
                break :blk true;
            },
            .table_destr => |entries| try self.matchTablePattern(entries, value),
            .array_destr => |patterns| try self.matchArrayPattern(patterns, value),
            .rest => |name| blk: {
                _ = try self.pushLocal(name, value);
                break :blk true;
            },
            else => error.UnsupportedExpression,
        };
    }

    fn matchTablePattern(self: *Evaluator, entries: []const ast.Pattern.TableDestrEntry, value: Value) EvalError!bool {
        if (value != .table) return false;
        for (entries) |entry| {
            const field_value = try tableFieldLookup(value, entry.key);
            if (!(try self.matchPattern(entry.pat, field_value))) return false;
        }
        return true;
    }

    fn matchArrayPattern(self: *Evaluator, patterns: []const ast.Pattern, value: Value) EvalError!bool {
        if (value != .table) return false;
        for (patterns, 0..) |pattern, i| {
            if (pattern == .rest) {
                const rest = try self.arrayRest(value, @intCast(i + 1));
                _ = try self.pushLocal(pattern.rest, rest);
                return true;
            }
            const elem = try tableLookup(value, .{ .int = @intCast(i + 1) });
            if (!(try self.matchPattern(pattern, elem))) return false;
        }
        return true;
    }

    fn arrayRest(self: *Evaluator, value: Value, start_index: i64) EvalError!Value {
        const alloc = self.options.alloc orelse return error.UnsupportedExpression;
        if (value != .table) return error.UnsupportedExpression;
        var count: usize = 0;
        for (value.table) |entry| {
            if (entry.key) |key| {
                if (key == .int and key.int >= start_index) count += 1;
            }
        }
        const entries = alloc.alloc(Value.TableEntry, count) catch return error.UnsupportedExpression;
        var out_i: usize = 0;
        for (value.table) |entry| {
            if (entry.key) |key| {
                if (key == .int and key.int >= start_index) {
                    entries[out_i] = .{ .key = .{ .int = key.int - start_index + 1 }, .val = entry.val };
                    out_i += 1;
                }
            }
        }
        return .{ .table = entries };
    }

    fn evalBlockResult(self: *Evaluator, block: *const ast.Block) EvalError!Value {
        if (block.tail_expr) |expr| return self.eval(expr);
        if (block.stmts.len != 1) return error.UnsupportedExpression;
        return switch (block.stmts[0]) {
            .ret => |ret| blk: {
                if (ret.vals.len != 1) return error.UnsupportedExpression;
                break :blk try self.eval(ret.vals[0]);
            },
            .expr_stmt => |expr_stmt| self.eval(expr_stmt.expr),
            .call_stmt => |call_stmt| self.eval(call_stmt.expr),
            else => error.UnsupportedExpression,
        };
    }
};

fn tableFieldLookup(obj: Value, field: []const u8) EvalError!Value {
    if (obj != .table) return error.UnsupportedOperator;
    for (obj.table) |entry| {
        if (entry.name) |name| {
            if (std.mem.eql(u8, name, field)) return entry.val;
        } else if (entry.key) |key| {
            if (key == .string and std.mem.eql(u8, key.string, field)) return entry.val;
        }
    }
    return .nil;
}

fn tableLookup(obj: Value, key: Value) EvalError!Value {
    if (obj != .table) return error.UnsupportedOperator;
    for (obj.table) |entry| {
        if (entry.name) |name| {
            if (key == .string and std.mem.eql(u8, key.string, name)) return entry.val;
        } else if (entry.key) |entry_key| {
            if (entry_key.eql(key)) return entry.val;
        }
    }
    return .nil;
}

fn numericAsFloat(value: Value) ?f64 {
    return switch (value) {
        .int => |v| @floatFromInt(v),
        .float => |v| v,
        else => null,
    };
}

fn numericAsInt(value: Value) ?i64 {
    return switch (value) {
        .int => |v| v,
        else => null,
    };
}

fn evalNumeric(op: ast.BinOp, left: Value, right: Value) EvalError!Value {
    if (left == .int and right == .int and op != .div and op != .pow) {
        const l = left.int;
        const r = right.int;
        return switch (op) {
            .add => .{ .int = l +% r },
            .sub => .{ .int = l -% r },
            .mul => .{ .int = l *% r },
            .idiv => if (r == 0) error.DivisionByZero else .{ .int = @divFloor(l, r) },
            .mod => if (r == 0) error.DivisionByZero else .{ .int = @mod(l, r) },
            else => error.UnsupportedOperator,
        };
    }

    const l = numericAsFloat(left) orelse return error.UnsupportedOperator;
    const r = numericAsFloat(right) orelse return error.UnsupportedOperator;
    return switch (op) {
        .add => .{ .float = l + r },
        .sub => .{ .float = l - r },
        .mul => .{ .float = l * r },
        .div => if (r == 0.0) error.DivisionByZero else .{ .float = l / r },
        .pow => .{ .float = std.math.pow(f64, l, r) },
        else => error.UnsupportedOperator,
    };
}

fn evalInteger(op: ast.BinOp, left: Value, right: Value) EvalError!Value {
    const l = numericAsInt(left) orelse return error.UnsupportedOperator;
    const r = numericAsInt(right) orelse return error.UnsupportedOperator;
    return switch (op) {
        .band => .{ .int = l & r },
        .bor => .{ .int = l | r },
        .bxor => .{ .int = l ^ r },
        .lshift => if (r >= 0 and r < 64) .{ .int = l << @intCast(r) } else error.UnsupportedOperator,
        .rshift => if (r >= 0 and r < 64) .{ .int = @as(i64, @bitCast(@as(u64, @bitCast(l)) >> @intCast(r))) } else error.UnsupportedOperator,
        else => error.UnsupportedOperator,
    };
}

fn evalComparison(op: ast.BinOp, left: Value, right: Value) EvalError!Value {
    if (numericAsFloat(left)) |l| {
        const r = numericAsFloat(right) orelse return error.UnsupportedOperator;
        return .{ .bool = switch (op) {
            .lt => l < r,
            .gt => l > r,
            .leq => l <= r,
            .geq => l >= r,
            else => unreachable,
        } };
    }
    if (left == .string and right == .string) {
        const order = std.mem.order(u8, left.string, right.string);
        return .{ .bool = switch (op) {
            .lt => order == .lt,
            .gt => order == .gt,
            .leq => order != .gt,
            .geq => order != .lt,
            else => unreachable,
        } };
    }
    return error.UnsupportedOperator;
}

pub fn eval(expr: *const ast.Expr) EvalError!Value {
    var evaluator: Evaluator = .{};
    return evaluator.eval(expr);
}

pub fn evalWithBindings(expr: *const ast.Expr, bindings: Bindings, options: Options) EvalError!Value {
    var evaluator: Evaluator = .{ .bindings = bindings, .options = options };
    defer if (options.alloc) |alloc| evaluator.locals.deinit(alloc);
    return evaluator.eval(expr);
}

test "comptime eval: pure arithmetic" {
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var two = ast.Expr{ .int_lit = .{ .loc = loc, .val = 2 } };
    var three = ast.Expr{ .int_lit = .{ .loc = loc, .val = 3 } };
    var four = ast.Expr{ .int_lit = .{ .loc = loc, .val = 4 } };
    var mul = ast.Expr{ .binop = .{ .loc = loc, .op = .mul, .lhs = &three, .rhs = &four } };
    var add = ast.Expr{ .binop = .{ .loc = loc, .op = .add, .lhs = &two, .rhs = &mul } };
    try std.testing.expectEqual(Value{ .int = 14 }, try eval(&add));
}

test "comptime eval: scoped bindings and shadowing" {
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var outer: std.StringHashMapUnmanaged(Value) = .empty;
    defer outer.deinit(std.testing.allocator);
    var inner: std.StringHashMapUnmanaged(Value) = .empty;
    defer inner.deinit(std.testing.allocator);
    try outer.put(std.testing.allocator, "base", .{ .int = 10 });
    try inner.put(std.testing.allocator, "base", .{ .int = 20 });
    try inner.put(std.testing.allocator, "offset", .{ .int = 2 });
    const scopes = [_]std.StringHashMapUnmanaged(Value){ outer, inner };
    var base = ast.Expr{ .name = .{ .loc = loc, .ident = "base" } };
    var offset = ast.Expr{ .name = .{ .loc = loc, .ident = "offset" } };
    var add = ast.Expr{ .binop = .{ .loc = loc, .op = .add, .lhs = &base, .rhs = &offset } };
    try std.testing.expectEqual(Value{ .int = 22 }, try evalWithBindings(&add, .{ .scopes = &scopes }, .{}));
}

test "comptime eval: runtime-only names are unsupported" {
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var name = ast.Expr{ .name = .{ .loc = loc, .ident = "x" } };
    try std.testing.expectError(error.UnsupportedExpression, eval(&name));
}

test "comptime eval: pure table literals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var one = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    var two = ast.Expr{ .int_lit = .{ .loc = loc, .val = 2 } };
    var key = ast.Expr{ .string_lit = .{ .loc = loc, .val = "answer" } };
    var forty_two = ast.Expr{ .int_lit = .{ .loc = loc, .val = 42 } };
    const fields = try alloc.alloc(ast.TableField, 3);
    fields[0] = .{ .positional = &one };
    fields[1] = .{ .named = .{ .key = "name", .val = &two } };
    fields[2] = .{ .indexed = .{ .key = &key, .val = &forty_two } };
    var table = ast.Expr{ .table = .{ .loc = loc, .fields = fields } };

    const value = try evalWithBindings(&table, .{}, .{ .alloc = alloc });
    try std.testing.expect(value == .table);
    try std.testing.expectEqual(@as(usize, 3), value.table.len);
    try std.testing.expectEqual(Value{ .int = 1 }, value.table[0].key.?);
    try std.testing.expectEqual(Value{ .int = 1 }, value.table[0].val);
    try std.testing.expectEqualStrings("name", value.table[1].name.?);
    try std.testing.expectEqual(Value{ .int = 2 }, value.table[1].val);
    try std.testing.expectEqual(Value{ .string = "answer" }, value.table[2].key.?);
    try std.testing.expectEqual(Value{ .int = 42 }, value.table[2].val);
}

test "comptime eval: table field and index lookups" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var one = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    var name_value = ast.Expr{ .string_lit = .{ .loc = loc, .val = "duo" } };
    var key = ast.Expr{ .string_lit = .{ .loc = loc, .val = "answer" } };
    var forty_two = ast.Expr{ .int_lit = .{ .loc = loc, .val = 42 } };
    const fields = try alloc.alloc(ast.TableField, 3);
    fields[0] = .{ .positional = &one };
    fields[1] = .{ .named = .{ .key = "name", .val = &name_value } };
    fields[2] = .{ .indexed = .{ .key = &key, .val = &forty_two } };
    var table = ast.Expr{ .table = .{ .loc = loc, .fields = fields } };

    var field = ast.Expr{ .field = .{ .loc = loc, .obj = &table, .field = "name" } };
    var index_key = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    var index = ast.Expr{ .index = .{ .loc = loc, .obj = &table, .key = &index_key } };
    var named_index_key = ast.Expr{ .string_lit = .{ .loc = loc, .val = "answer" } };
    var named_index = ast.Expr{ .index = .{ .loc = loc, .obj = &table, .key = &named_index_key } };
    var missing = ast.Expr{ .field = .{ .loc = loc, .obj = &table, .field = "missing" } };

    try std.testing.expectEqual(Value{ .string = "duo" }, try evalWithBindings(&field, .{}, .{ .alloc = alloc }));
    try std.testing.expectEqual(Value{ .int = 1 }, try evalWithBindings(&index, .{}, .{ .alloc = alloc }));
    try std.testing.expectEqual(Value{ .int = 42 }, try evalWithBindings(&named_index, .{}, .{ .alloc = alloc }));
    try std.testing.expectEqual(Value.nil, try evalWithBindings(&missing, .{}, .{ .alloc = alloc }));
}

test "comptime eval: string concat allocates deterministic literals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var left = ast.Expr{ .string_lit = .{ .loc = loc, .val = "du" } };
    var right = ast.Expr{ .string_lit = .{ .loc = loc, .val = "o" } };
    var concat = ast.Expr{ .binop = .{ .loc = loc, .op = .concat, .lhs = &left, .rhs = &right } };
    const value = try evalWithBindings(&concat, .{}, .{ .alloc = alloc });
    try std.testing.expect(value == .string);
    try std.testing.expectEqualStrings("duo", value.string);
}

test "comptime eval: match expression with literal and guarded binding arms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };

    var scrutinee = ast.Expr{ .int_lit = .{ .loc = loc, .val = 4 } };
    var one = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    var one_result = ast.Expr{ .string_lit = .{ .loc = loc, .val = "one" } };
    var binding_name = ast.Expr{ .name = .{ .loc = loc, .ident = "n" } };
    var guard_min = ast.Expr{ .int_lit = .{ .loc = loc, .val = 2 } };
    var guard = ast.Expr{ .binop = .{ .loc = loc, .op = .gt, .lhs = &binding_name, .rhs = &guard_min } };
    var forty = ast.Expr{ .int_lit = .{ .loc = loc, .val = 40 } };
    var body_name = ast.Expr{ .name = .{ .loc = loc, .ident = "n" } };
    var add = ast.Expr{ .binop = .{ .loc = loc, .op = .add, .lhs = &body_name, .rhs = &forty } };

    const first_stmts = try alloc.alloc(ast.Stmt, 1);
    first_stmts[0] = .{ .ret = .{ .loc = loc, .vals = try alloc.dupe(*ast.Expr, &.{&one_result}) } };
    const second_stmts = try alloc.alloc(ast.Stmt, 1);
    second_stmts[0] = .{ .ret = .{ .loc = loc, .vals = try alloc.dupe(*ast.Expr, &.{&add}) } };
    const arms = try alloc.alloc(ast.MatchArm, 2);
    arms[0] = .{
        .pattern = .{ .literal = &one },
        .guard = null,
        .body = .{ .loc = loc, .stmts = first_stmts },
    };
    arms[1] = .{
        .pattern = .{ .binding = .{ .name = "n", .typ = null } },
        .guard = &guard,
        .body = .{ .loc = loc, .stmts = second_stmts },
    };
    var match_expr = ast.MatchExpr{ .loc = loc, .scrutinee = &scrutinee, .arms = arms };
    var expr = ast.Expr{ .match_expr = &match_expr };

    try std.testing.expectEqual(Value{ .int = 44 }, try evalWithBindings(&expr, .{}, .{ .alloc = alloc }));
}

test "comptime eval: step limit" {
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var one = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    try std.testing.expectError(error.StepLimitExceeded, evalWithBindings(&one, .{}, .{ .step_limit = 0 }));
}
