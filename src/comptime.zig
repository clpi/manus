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
};

pub const Value = union(enum) {
    unavailable,
    nil,
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,

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
    bindings: Bindings = .{},
    options: Options = .{},
    steps: usize = 0,

    fn step(self: *Evaluator) EvalError!void {
        self.steps += 1;
        if (self.steps > self.options.step_limit) return error.StepLimitExceeded;
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
                const value = self.bindings.get(name.ident) orelse return error.UnsupportedExpression;
                if (value == .unavailable) return error.UnsupportedExpression;
                break :blk value;
            },
            .unop => |unop| try self.evalUnop(unop.op, unop.operand),
            .binop => |binop| try self.evalBinop(binop.op, binop.lhs, binop.rhs),
            else => error.UnsupportedExpression,
        };
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
            .concat => switch (left) {
                .string => |l| switch (right) {
                    .string => |r| .{ .string = if (l.len == 0) r else if (r.len == 0) l else return error.UnsupportedOperator },
                    else => error.UnsupportedOperator,
                },
                else => error.UnsupportedOperator,
            },
            .eq => .{ .bool = left.eql(right) },
            .neq => .{ .bool = !left.eql(right) },
            .lt, .gt, .leq, .geq => try evalComparison(op, left, right),
            .contains, .@"and", .@"or" => error.UnsupportedOperator,
        };
    }
};

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

test "comptime eval: step limit" {
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var one = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    try std.testing.expectError(error.StepLimitExceeded, evalWithBindings(&one, .{}, .{ .step_limit = 0 }));
}
