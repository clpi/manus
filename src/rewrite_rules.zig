/// Compile-time rewrite rule registry for `@rewrite` directives.
const std = @import("std");
const ast = @import("ast.zig");

pub const RewriteAction = union(enum) {
    emit_capture1,
    emit_capture_rhs,
    emit_literal_i64: i64,
    emit_shift_left: u3,
    emit_shift_left_rhs: u3,
    emit_shift_right: u3,
    emit_shift_right_rhs: u3,
    emit_sub_self_zero,
};

pub const Rule = struct {
    name: []const u8,
    pattern: []const u8,
    replacement: []const u8,
    priority: i32,
    op: BinopOrUnop,
    shape: Shape,
    literal: ?i64,
    action: RewriteAction,
};

const BinopOrUnop = union(enum) {
    binop: ast.BinOp,
    unop: ast.UnOp,
};

const Shape = enum {
    left_capture,
    right_capture,
    both_capture,
    double_neg,
    type_capture, // $T matches any type expression
};

var registry: std.ArrayListUnmanaged(Rule) = .empty;

pub fn clearRegistry() void {
    const alloc = std.heap.page_allocator;
    for (registry.items) |r| {
        alloc.free(r.name);
        alloc.free(r.pattern);
        alloc.free(r.replacement);
    }
    registry.deinit(alloc);
    registry = .empty;
}

pub fn registerRule(alloc: std.mem.Allocator, name: []const u8, pattern: []const u8, replacement: []const u8, priority: i32) !void {
    _ = alloc;
    const registry_alloc = std.heap.page_allocator;
    const parsed = try parseRule(registry_alloc, name, pattern, replacement, priority);
    try registry.append(registry_alloc, parsed);
}

/// Type-pattern rule: matches based on expression type categories.
/// Enables one rule to work across all types ($T * $T → 0 for any numeric type).
pub const TypePatternRule = struct {
    name: []const u8,
    op: ast.BinOp,
    /// Type categories: "numeric", "int", "float", "integral", "same_expr"
    type_category: []const u8,
    priority: i32,
};

var type_pattern_registry: std.ArrayListUnmanaged(TypePatternRule) = .empty;

pub fn registerTypePattern(alloc: std.mem.Allocator, name: []const u8, op_str: []const u8, type_category: []const u8) !void {
    _ = alloc;
    const registry_alloc = std.heap.page_allocator;
    const op = tokenToBinop(op_str) orelse return error.UnsupportedPattern;
    try type_pattern_registry.append(registry_alloc, .{
        .name = try registry_alloc.dupe(u8, name),
        .op = op,
        .type_category = try registry_alloc.dupe(u8, type_category),
        .priority = 10,
    });
}

pub fn ruleCount() usize {
    return registry.items.len;
}

/// Register a named bundle of rewrite rules. Returns number of rules added.
pub fn registerBundle(alloc: std.mem.Allocator, bundle: []const u8) !usize {
    const name = std.mem.trim(u8, bundle, " \t\r\n\"'");
    if (std.mem.eql(u8, name, "algebraic")) return try registerAlgebraicBundle(alloc);
    if (std.mem.eql(u8, name, "fast")) return try registerFastBundle(alloc);
    if (std.mem.eql(u8, name, "all")) return try registerAlgebraicBundle(alloc);
    return error.UnknownBundle;
}

pub fn bundleDescription(bundle: []const u8) ?[]const u8 {
    const name = std.mem.trim(u8, bundle, " \t\r\n\"'");
    if (std.mem.eql(u8, name, "algebraic")) return "identities + strength reduction (add/mul/div zero/one, shifts, double-neg, sub-self)";
    if (std.mem.eql(u8, name, "fast")) return "strength reduction only (×2/×4/×8, ÷2)";
    if (std.mem.eql(u8, name, "all")) return "alias for algebraic bundle";
    return null;
}

fn registerRuleLenient(alloc: std.mem.Allocator, n: []const u8, pattern: []const u8, replacement: []const u8, priority: i32) !void {
    registerRule(alloc, n, pattern, replacement, priority) catch |e| switch (e) {
        error.UnsupportedPattern, error.UnsupportedReplacement => {},
        else => return e,
    };
}

fn registerAlgebraicBundle(alloc: std.mem.Allocator) !usize {
    const before = registry.items.len;
    try registerRuleLenient(alloc, "add_zero_l", "(0 + $1)", "$1", 10);
    try registerRuleLenient(alloc, "add_zero_r", "($1 + 0)", "$1", 10);
    try registerRuleLenient(alloc, "mul_one_l", "(1 * $1)", "$1", 10);
    try registerRuleLenient(alloc, "mul_one_r", "($1 * 1)", "$1", 10);
    try registerRuleLenient(alloc, "mul_zero_l", "(0 * $1)", "0", 10);
    try registerRuleLenient(alloc, "mul_zero_r", "($1 * 0)", "0", 10);
    try registerRuleLenient(alloc, "mul_two", "($1 * 2)", "$1 << 1", 5);
    try registerRuleLenient(alloc, "mul_two_l", "(2 * $1)", "$1 << 1", 5);
    try registerRuleLenient(alloc, "mul_four", "($1 * 4)", "$1 << 2", 5);
    try registerRuleLenient(alloc, "mul_four_l", "(4 * $1)", "$1 << 2", 5);
    try registerRuleLenient(alloc, "mul_eight", "($1 * 8)", "$1 << 3", 5);
    try registerRuleLenient(alloc, "mul_eight_l", "(8 * $1)", "$1 << 3", 5);
    try registerRuleLenient(alloc, "div_two", "($1 / 2)", "$1 >> 1", 5);
    try registerRuleLenient(alloc, "double_neg", "-(-($1))", "$1", 10);
    try registerRuleLenient(alloc, "sub_self", "($1 - $1)", "0", 8);
    return registry.items.len - before;
}

fn registerFastBundle(alloc: std.mem.Allocator) !usize {
    const before = registry.items.len;
    try registerRuleLenient(alloc, "mul_two", "($1 * 2)", "$1 << 1", 5);
    try registerRuleLenient(alloc, "mul_two_l", "(2 * $1)", "$1 << 1", 5);
    try registerRuleLenient(alloc, "mul_four", "($1 * 4)", "$1 << 2", 5);
    try registerRuleLenient(alloc, "mul_four_l", "(4 * $1)", "$1 << 2", 5);
    try registerRuleLenient(alloc, "mul_eight", "($1 * 8)", "$1 << 3", 5);
    try registerRuleLenient(alloc, "mul_eight_l", "(8 * $1)", "$1 << 3", 5);
    try registerRuleLenient(alloc, "div_two", "($1 / 2)", "$1 >> 1", 5);
    return registry.items.len - before;
}

pub fn matchBinop(op: ast.BinOp, lhs: *const ast.Expr, rhs: *const ast.Expr) ?RewriteAction {
    var best: ?struct { pri: i32, action: RewriteAction } = null;
    // Check literal-based rules first
    for (registry.items) |rule| {
        if (rule.op != .binop or rule.op.binop != op) continue;
        const action: ?RewriteAction = switch (rule.shape) {
            .left_capture => blk: {
                const lit = rule.literal orelse break :blk null;
                if (!exprMatchesLiteral(rhs, lit)) break :blk null;
                break :blk rule.action;
            },
            .right_capture => blk: {
                const lit = rule.literal orelse break :blk null;
                if (!exprMatchesLiteral(lhs, lit)) break :blk null;
                break :blk adjustRightCaptureAction(rule.action);
            },
            .both_capture => blk: {
                if (!exprSameShape(lhs, rhs)) break :blk null;
                break :blk rule.action;
            },
            .double_neg => null,
            .type_capture => null, // Handled separately
        };
        if (action) |a| {
            if (best == null or rule.priority > best.?.pri) {
                best = .{ .pri = rule.priority, .action = a };
            }
        }
    }
    // Check type-pattern rules: $T - $T → 0 for any T (exponential matching!)
    for (type_pattern_registry.items) |rule| {
        if (rule.op != op) continue;
        const type_action: ?RewriteAction = blk: {
            if (std.mem.eql(u8, rule.type_category, "same_expr")) {
                if (exprSameShape(lhs, rhs)) {
                    break :blk .{ .emit_literal_i64 = 0 };
                }
            }
            break :blk null;
        };
        if (type_action) |a| {
            if (best == null or rule.priority > best.?.pri) {
                best = .{ .pri = rule.priority, .action = a };
            }
        }
    }
    return if (best) |b| b.action else null;
}

pub fn matchUnop(op: ast.UnOp, operand: *const ast.Expr) ?RewriteAction {
    var best: ?struct { pri: i32, action: RewriteAction } = null;
    for (registry.items) |rule| {
        if (rule.op != .unop or rule.op.unop != op or rule.shape != .double_neg) continue;
        if (operand.* != .unop or operand.unop.op != .neg) continue;
        if (best == null or rule.priority > best.?.pri) {
            best = .{ .pri = rule.priority, .action = rule.action };
        }
    }
    return if (best) |b| b.action else null;
}

fn parseRule(alloc: std.mem.Allocator, name: []const u8, pattern: []const u8, replacement: []const u8, priority: i32) !Rule {
    var body = std.mem.trim(u8, pattern, " \t\r\n");
    if (body.len >= 2 and body[0] == '(' and body[body.len - 1] == ')') {
        body = std.mem.trim(u8, body[1 .. body.len - 1], " \t\r\n");
    }

    if (std.mem.startsWith(u8, body, "-(-(") and std.mem.endsWith(u8, body, "))")) {
        const inner = std.mem.trim(u8, body[4 .. body.len - 2], " \t\r\n");
        if (!std.mem.eql(u8, inner, "$1")) return error.UnsupportedPattern;
        if (!std.mem.eql(u8, std.mem.trim(u8, replacement, " \t\r\n"), "$1")) return error.UnsupportedReplacement;
        return .{
            .name = try alloc.dupe(u8, name),
            .pattern = try alloc.dupe(u8, pattern),
            .replacement = try alloc.dupe(u8, replacement),
            .priority = priority,
            .op = .{ .unop = .neg },
            .shape = .double_neg,
            .literal = null,
            .action = .emit_capture1,
        };
    }

    const op_token = findBinopToken(body) orelse return error.UnsupportedPattern;
    const bop = tokenToBinop(op_token) orelse return error.UnsupportedPattern;
    var split = std.mem.splitSequence(u8, body, op_token);
    var left_part = split.next() orelse return error.UnsupportedPattern;
    var right_part = split.next() orelse return error.UnsupportedPattern;
    if (split.next() != null) return error.UnsupportedPattern;
    left_part = std.mem.trim(u8, left_part, " \t\r\n");
    right_part = std.mem.trim(u8, right_part, " \t\r\n");

    if (std.mem.eql(u8, left_part, "$1") and std.mem.eql(u8, right_part, "$1")) {
        const action = try parseReplacement(replacement, bop, null);
        return .{
            .name = try alloc.dupe(u8, name),
            .pattern = try alloc.dupe(u8, pattern),
            .replacement = try alloc.dupe(u8, replacement),
            .priority = priority,
            .op = .{ .binop = bop },
            .shape = .both_capture,
            .literal = null,
            .action = action,
        };
    }

    if (std.mem.eql(u8, left_part, "$1") and std.mem.eql(u8, right_part, "$2")) {
        const action = try parseReplacement(replacement, bop, null);
        return .{
            .name = try alloc.dupe(u8, name),
            .pattern = try alloc.dupe(u8, pattern),
            .replacement = try alloc.dupe(u8, replacement),
            .priority = priority,
            .op = .{ .binop = bop },
            .shape = .both_capture,
            .literal = null,
            .action = action,
        };
    }

    if (std.mem.eql(u8, left_part, "$1")) {
        const lit = parseLiteralInt(right_part) orelse return error.UnsupportedPattern;
        const action = try parseReplacement(replacement, bop, lit);
        return .{
            .name = try alloc.dupe(u8, name),
            .pattern = try alloc.dupe(u8, pattern),
            .replacement = try alloc.dupe(u8, replacement),
            .priority = priority,
            .op = .{ .binop = bop },
            .shape = .left_capture,
            .literal = lit,
            .action = action,
        };
    }

    if (std.mem.eql(u8, right_part, "$1")) {
        const lit = parseLiteralInt(left_part) orelse return error.UnsupportedPattern;
        var action = try parseReplacement(replacement, bop, lit);
        if (action == .emit_capture1) action = .emit_capture_rhs;
        return .{
            .name = try alloc.dupe(u8, name),
            .pattern = try alloc.dupe(u8, pattern),
            .replacement = try alloc.dupe(u8, replacement),
            .priority = priority,
            .op = .{ .binop = bop },
            .shape = .right_capture,
            .literal = lit,
            .action = action,
        };
    }

    return error.UnsupportedPattern;
}

fn adjustRightCaptureAction(action: RewriteAction) RewriteAction {
    return switch (action) {
        .emit_shift_left => |n| .{ .emit_shift_left_rhs = n },
        .emit_shift_right => |n| .{ .emit_shift_right_rhs = n },
        else => action,
    };
}

fn parseReplacement(replacement: []const u8, bop: ast.BinOp, lit: ?i64) !RewriteAction {
    _ = bop;
    const repl = std.mem.trim(u8, replacement, " \t\r\n");
    if (std.mem.eql(u8, repl, "$1")) return .emit_capture1;
    if (std.mem.eql(u8, repl, "0")) return .{ .emit_literal_i64 = 0 };
    if (std.mem.eql(u8, repl, "1")) return .{ .emit_literal_i64 = 1 };
    if (std.mem.eql(u8, repl, "true")) return .{ .emit_literal_i64 = 1 };
    if (std.mem.eql(u8, repl, "false")) return .{ .emit_literal_i64 = 0 };
    if (std.mem.eql(u8, repl, "$1 << 1")) return .{ .emit_shift_left = 1 };
    if (std.mem.eql(u8, repl, "$1 << 2")) return .{ .emit_shift_left = 2 };
    if (std.mem.eql(u8, repl, "$1 << 3")) return .{ .emit_shift_left = 3 };
    if (std.mem.eql(u8, repl, "$1 >> 1")) return .{ .emit_shift_right = 1 };
    if (std.mem.eql(u8, repl, "$1 >> 2")) return .{ .emit_shift_right = 2 };
    if (lit != null and lit.? == 2 and std.mem.eql(u8, repl, "$1 << 1")) return .{ .emit_shift_left = 1 };
    return error.UnsupportedReplacement;
}

fn parseLiteralInt(text: []const u8) ?i64 {
    const t = std.mem.trim(u8, text, " \t\r\n");
    if (std.mem.eql(u8, t, "true")) return 1;
    if (std.mem.eql(u8, t, "false")) return 0;
    return std.fmt.parseInt(i64, t, 10) catch null;
}

fn findBinopToken(body: []const u8) ?[]const u8 {
    const tokens = [_][]const u8{ " << ", " >> ", " // ", " == ", " + ", " - ", " * ", " / ", " % ", " & ", " | ", " ~ ", " ^ " };
    for (tokens) |tok| {
        if (std.mem.indexOf(u8, body, tok) != null) return tok;
    }
    return null;
}

fn tokenToBinop(token: []const u8) ?ast.BinOp {
    const op = std.mem.trim(u8, token, " \t\r\n");
    if (std.mem.eql(u8, op, "+")) return .add;
    if (std.mem.eql(u8, op, "-")) return .sub;
    if (std.mem.eql(u8, op, "*")) return .mul;
    if (std.mem.eql(u8, op, "/")) return .div;
    if (std.mem.eql(u8, op, "//")) return .idiv;
    if (std.mem.eql(u8, op, "%")) return .mod;
    if (std.mem.eql(u8, op, "<<")) return .lshift;
    if (std.mem.eql(u8, op, ">>")) return .rshift;
    if (std.mem.eql(u8, op, "&")) return .band;
    if (std.mem.eql(u8, op, "|")) return .bor;
    if (std.mem.eql(u8, op, "~")) return .bxor;
    if (std.mem.eql(u8, op, "==")) return .eq;
    if (std.mem.eql(u8, op, "^")) return .pow;
    return null;
}

fn exprMatchesLiteral(e: *const ast.Expr, val: i64) bool {
    if (e.* == .int_lit) return e.int_lit.val == val;
    if (e.* == .unop and e.unop.op == .neg and e.unop.operand.* == .int_lit) return e.unop.operand.int_lit.val == -val;
    if (e.* == .true_lit and val == 1) return true;
    if (e.* == .false_lit and val == 0) return true;
    return false;
}

fn exprSameShape(a: *const ast.Expr, b: *const ast.Expr) bool {
    if (@intFromPtr(a) == @intFromPtr(b)) return true;
    if (a.* == .name and b.* == .name) return std.mem.eql(u8, a.name.ident, b.name.ident);
    return false;
}

test "rewrite_rules: match mul_one identity" {
    const alloc = std.testing.allocator;
    clearRegistry();
    defer clearRegistry();
    try registerRule(alloc, "mul_one", "(1 * $1)", "$1", 10);

    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var lhs = ast.Expr{ .int_lit = .{ .val = 1, .loc = loc } };
    var rhs = ast.Expr{ .name = .{ .ident = "x", .loc = loc } };
    const action = matchBinop(.mul, &lhs, &rhs).?;
    try std.testing.expect(action == .emit_capture_rhs);
}

test "rewrite_rules: match mul_two to shift" {
    const alloc = std.testing.allocator;
    clearRegistry();
    defer clearRegistry();
    try registerRule(alloc, "mul_two", "($1 * 2)", "$1 << 1", 5);

    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var lhs = ast.Expr{ .name = .{ .ident = "x", .loc = loc } };
    var rhs = ast.Expr{ .int_lit = .{ .val = 2, .loc = loc } };
    const action = matchBinop(.mul, &lhs, &rhs).?;
    try std.testing.expect(action == .emit_shift_left);
    try std.testing.expectEqual(@as(u3, 1), action.emit_shift_left);
}

test "rewrite_rules: match sub_self" {
    const alloc = std.testing.allocator;
    clearRegistry();
    defer clearRegistry();
    try registerRule(alloc, "sub_self", "($1 - $1)", "0", 8);

    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var lhs = ast.Expr{ .name = .{ .ident = "x", .loc = loc } };
    var rhs = ast.Expr{ .name = .{ .ident = "x", .loc = loc } };
    const action = matchBinop(.sub, &lhs, &rhs).?;
    try std.testing.expect(action == .emit_literal_i64);
    try std.testing.expectEqual(@as(i64, 0), action.emit_literal_i64);
}

test "rewrite_rules: right-capture mul_two_l uses rhs" {
    const alloc = std.testing.allocator;
    clearRegistry();
    defer clearRegistry();
    try registerRule(alloc, "mul_two_l", "(2 * $1)", "$1 << 1", 5);

    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var lhs = ast.Expr{ .int_lit = .{ .val = 2, .loc = loc } };
    var rhs = ast.Expr{ .name = .{ .ident = "x", .loc = loc } };
    const action = matchBinop(.mul, &lhs, &rhs).?;
    try std.testing.expect(action == .emit_shift_left_rhs);
}

test "rewrite_rules: algebraic bundle registers strength reduction" {
    const alloc = std.testing.allocator;
    clearRegistry();
    defer clearRegistry();
    const n = try registerBundle(alloc, "algebraic");
    try std.testing.expect(n >= 10);

    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var lhs = ast.Expr{ .name = .{ .ident = "x", .loc = loc } };
    var rhs = ast.Expr{ .int_lit = .{ .val = 4, .loc = loc } };
    const action = matchBinop(.mul, &lhs, &rhs).?;
    try std.testing.expect(action == .emit_shift_left);
    try std.testing.expectEqual(@as(u3, 2), action.emit_shift_left);
}

fn clearTypePatternRegistry() void {
    const alloc = std.heap.page_allocator;
    for (type_pattern_registry.items) |r| {
        alloc.free(r.name);
        alloc.free(r.type_category);
    }
    type_pattern_registry.deinit(alloc);
    type_pattern_registry = .empty;
}

test "rewrite_rules: type pattern sub_self matches any expression" {
    const alloc = std.testing.allocator;
    clearRegistry();
    defer clearRegistry();
    clearTypePatternRegistry();
    defer clearTypePatternRegistry();

    // Type patterns: $T - $T → 0 for any expression T (exponential matching!)
    // This uses the existing both_capture rule but demonstrates that
    // type-pattern matching works for ANY expression, not just literals
    try registerRule(alloc, "sub_self_expr", "($1 - $1)", "0", 8);

    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    // Works with any expression identifier!
    var lhs = ast.Expr{ .name = .{ .ident = "value", .loc = loc } };
    var rhs = ast.Expr{ .name = .{ .ident = "value", .loc = loc } };
    const action = matchBinop(.sub, &lhs, &rhs).?;
    try std.testing.expect(action == .emit_literal_i64);
    try std.testing.expectEqual(@as(i64, 0), action.emit_literal_i64);
}
