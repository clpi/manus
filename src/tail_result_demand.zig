//! §5.1 — tail-demand propagation (AST resolution, no backward local search).
const std = @import("std");
const ast = @import("ast.zig");
const tail_result_model = @import("tail_result_model.zig");

pub const TailResultRule = tail_result_model.TailResultRule;
pub const ResultDemand = tail_result_model.ResultDemand;

pub const Resolution = struct {
    rule: TailResultRule,
    region: tail_result_model.TailRegionKind = .tail_statement,
    /// Expression used for type-check / lowering (name ref for loop/branch-carried value).
    expr: *ast.Expr,
    /// For `.tail_compound_assignment` only: the assignment TARGET.
    ///
    /// `expr` is the update expression (`x * 2` for `x *= 2`), which is what a
    /// type check wants. A lowering pass must not evaluate it a second time —
    /// the statement has already run, so re-evaluating reads the updated
    /// binding and applies the operator twice: `twice(5)` returned 20 through
    /// the direct backend where C returned 10, and `v.x += amt` returned
    /// 5+3+3. The storage named here already holds the answer.
    target: ?*ast.Expr = null,
    transparent_trailer_count: u8 = 0,
};

/// Build result demand from an explicit function return descriptor.
pub fn demandFromRetType(ret: ast.TypeExpr) ResultDemand {
    return switch (ret) {
        .inferred => .{ .position_count = 1, .latent_inferred = true },
        .named => |n| blk: {
            if (std.mem.eql(u8, n, "void")) {
                break :blk .{ .position_count = 0, .explicit_descriptor = true };
            }
            break :blk .{ .position_count = 1, .explicit_descriptor = true };
        },
        .tuple => |ts| .{
            .position_count = @intCast(@min(ts.len, 255)),
            .explicit_descriptor = true,
        },
        else => .{ .position_count = 1, .explicit_descriptor = true },
    };
}

/// Tail result expression only (legacy sema / hook).
pub fn blockTailResultExpr(blk: *const ast.Block) ?*ast.Expr {
    return if (blockTailResult(blk)) |r| r.expr else null;
}

/// Resolve tail-demand satisfaction for a block body.
pub fn blockTailResult(blk: *const ast.Block) ?Resolution {
    return blockTailResultWithDemand(blk, .{ .position_count = 1, .latent_inferred = true });
}

pub fn blockTailResultWithDemand(blk: *const ast.Block, demand: ResultDemand) ?Resolution {
    if (demand.position_count == 0) return null;

    var trailer_count: u8 = 0;
    var end = blk.stmts.len;
    // Only strip trailers when the block has no explicit tail expression.
    // `blk.tail_expr` is by definition the last thing in the block, so a
    // *statement* preceding it cannot be a trailer that comes after it.
    // Stripping regardless set trailer_count > 0, which discarded the tail
    // expression below and walked back to an earlier statement instead:
    //
    //     h = fun(a: any): any 1 end
    //     print(1)      -- counted as a trailer
    //     0             -- tail_expr, silently ignored
    //
    // made sema check `h = fun …` as the return value — "return type mismatch:
    // expected 'i64', got 'function'". Codegen returned 0 correctly the whole
    // time, so this was a sema-only false positive.
    // …but a tail expression that is itself a discard call carries no value, so
    // stripping must still run for it — `s = new32(); update(s, data); final(s)`
    // in std/hash/fnv.id depends on that walk-back. Only a value-carrying tail
    // expression suppresses stripping.
    const tail_carries_value = if (blk.tail_expr) |e| !isVoidShapedCall(e) else false;
    if (!tail_carries_value) {
        while (end > 0 and isTransparentTrailer(&blk.stmts[end - 1])) {
            end -= 1;
            trailer_count +|= 1;
        }
    }

    const tail_expr = if (trailer_count == 0) blk.tail_expr else null;
    if (tail_expr) |e| {
        if (isVoidShapedCall(e) and end > 0) {
            if (tailStatementResult(blk.stmts[0..end], end - 1)) |anchor| {
                var anchored = anchor;
                anchored.transparent_trailer_count = 1;
                anchored.region = .transparent_trailer_chain;
                return anchored;
            }
        }
        const rule: TailResultRule = switch (e.*) {
            .call, .method_call => .tail_call,
            else => .tail_assignment,
        };
        return .{ .rule = rule, .expr = e };
    }
    // Trailing calls are "transparent" so that `x = f()` / `log(x)` still yields
    // x. But if stripping them leaves nothing that carries a value — an empty
    // prefix, or a `req` module binding — then the final call *is* the result.
    // Yielding null instead left the function body with no terminator at all,
    // which the direct backend then refused as outside its subset.
    if (end == 0) return lastTrailerResult(blk, trailer_count);

    const effective = blk.stmts[0..end];
    var resolution = tailStatementResult(effective, end - 1) orelse
        return lastTrailerResult(blk, trailer_count);
    if (trailer_count > 0) {
        resolution.transparent_trailer_count = trailer_count;
        resolution.region = .transparent_trailer_chain;
    }
    return resolution;
}

/// Result to use when every value-carrying candidate was stripped as a
/// transparent trailer. A real tail expression outranks the trailers that were
/// scanned before it — `print(1)` then `0` yields 0, not the print — and only
/// when the body is calls all the way down does the final call become the
/// result.
fn lastTrailerResult(blk: *const ast.Block, trailer_count: u8) ?Resolution {
    if (trailer_count == 0) return null;
    if (blk.tail_expr) |e| return .{
        .rule = switch (e.*) {
            .call, .method_call => .tail_call,
            else => .tail_assignment,
        },
        .expr = e,
    };
    if (blk.stmts.len == 0) return null;
    return tailStatementResult(blk.stmts, blk.stmts.len - 1);
}

fn isTransparentTrailer(stmt: *const ast.Stmt) bool {
    return switch (stmt.*) {
        .call_stmt => true,
        .expr_stmt => |es| isDiscardCall(es.expr),
        else => false,
    };
}

fn isDiscardCall(expr: *const ast.Expr) bool {
    return expr.* == .call or expr.* == .method_call;
}

/// gap[102]: the parser promotes ANY trailing call to `blk.tail_expr`, so the
/// AST cannot tell `print value` (an effect) from `d2(p)` (the answer) by shape.
/// Treating both as discards walked the resolver back onto the PRECEDING
/// statement, which is what §0.7 forbids — a body's value is its final
/// expression's:
///
///     t(): i64
///         p = 5
///         d2(p)      -- 25
///
/// resolved to `p = 5`, so sema type-checked the binding as the return (the
/// `Point` mismatch that held agent-smoke red) and the direct backend RETURNED
/// 5 where the C oracle returned 25 — a silent wrong answer, not just a false
/// positive.
///
/// The walk-back is still owed to the effect case, so the discriminator is
/// void-ness rather than call-ness. Only a callee KNOWN to yield nothing is
/// transparent; everything else is the result. `print` is the built-in floor;
/// callers holding signatures widen it through `voidOracle`.
pub fn isVoidShapedCall(expr: *const ast.Expr) bool {
    if (expr.* != .call) return false;
    const callee = expr.call.func;
    if (callee.* == .name and std.mem.eql(u8, callee.name.ident, "print")) return true;
    if (void_oracle) |oracle| return oracle.yieldsNothing(oracle.ctx, expr);
    return false;
}

/// A caller that holds declared return types can answer void-ness for user
/// callables too. Installed for the duration of one check; absent, the built-in
/// floor above is the whole answer.
pub const VoidOracle = struct {
    ctx: *const anyopaque,
    yieldsNothing: *const fn (ctx: *const anyopaque, expr: *const ast.Expr) bool,
};

var void_oracle: ?VoidOracle = null;

pub fn installVoidOracle(oracle: ?VoidOracle) ?VoidOracle {
    const prev = void_oracle;
    void_oracle = oracle;
    return prev;
}

fn tailStatementResult(stmts: []const ast.Stmt, last_index: usize) ?Resolution {
    const last = &stmts[last_index];
    return switch (last.*) {
        .assign => |as| resolveTailAssign(as.targets, as.values),
        .expr_stmt => |es| .{
            .rule = switch (es.expr.*) {
                .call, .method_call => .tail_call,
                else => .tail_assignment,
            },
            .expr = es.expr,
        },
        .call_stmt => |cs| .{ .rule = .tail_call, .expr = cs.expr },
        .num_for, .gen_for => resolveTailLoop(stmts, last_index, last),
        .if_stmt => |is| resolveTailIf(stmts, last_index, &is.then, is.else_body),
        else => null,
    };
}

/// `req "path"` binds a module at compile time. It is spelled like a call, but
/// it never produces a runtime value, so it can never be a block's tail result.
fn isReqBinding(expr: *const ast.Expr) bool {
    if (expr.* != .call) return false;
    const c = expr.call;
    if (c.func.* != .name or !std.mem.eql(u8, c.func.name.ident, "req")) return false;
    return c.args.len == 1 and c.args[0].* == .quoted;
}

fn resolveTailAssign(targets: []*ast.Expr, values: []*ast.Expr) ?Resolution {
    if (values.len != 1) return null;
    const val = values[0];
    // Without this, a body ending in a discard-shaped call anchors its result to
    // the preceding statement — and when that statement is `E = req "std.emit"`,
    // the module binding itself became the return expression, lowering to a call
    // to a function literally named `req`.
    if (isReqBinding(val)) return null;
    if (targets.len == 1) {
        // Both spellings of a compound update — `x *= 2` and `v.x += amt` —
        // desugar to `target = target <op> rhs`, so the shape check covers a
        // field target as well as a name. It used to be name-only, which left
        // the field case classified as an ordinary tail assignment and so
        // re-evaluated by the lowerer.
        if (binopUpdatesTarget(val, targets[0])) {
            return .{ .rule = .tail_compound_assignment, .expr = val, .target = targets[0] };
        }
    }
    if (val.* == .call or val.* == .method_call) {
        return .{ .rule = .tail_call, .expr = val };
    }
    return .{ .rule = .tail_assignment, .expr = val };
}

fn resolveTailLoop(stmts: []const ast.Stmt, loop_index: usize, loop_stmt: *const ast.Stmt) ?Resolution {
    const body: *const ast.Block = switch (loop_stmt.*) {
        .num_for => |nf| &nf.body,
        .gen_for => |gf| &gf.body,
        else => return null,
    };

    const carried = findUniqueLoopCarriedName(body) orelse return null;
    if (findSeedBeforeLoop(stmts[0..loop_index], carried) == null) return null;

    const expr = nameExprRef(body, carried) orelse blk: {
        if (findSeedBeforeLoop(stmts[0..loop_index], carried)) |seed| {
            break :blk seed;
        }
        return null;
    };

    return .{
        .rule = .tail_loop_carried,
        .region = .tail_loop,
        .expr = expr,
    };
}

fn resolveTailIf(
    stmts: []const ast.Stmt,
    if_index: usize,
    then_block: *const ast.Block,
    else_body: ?ast.Block,
) ?Resolution {
    if (blockTailResult(then_block)) |then_r| {
        if (else_body) |eb| {
            if (blockTailResult(&eb)) |else_r| {
                if (then_r.rule == else_r.rule and exprsSameShape(then_r.expr, else_r.expr)) {
                    return .{
                        .rule = .tail_branch,
                        .region = .tail_branch,
                        .expr = then_r.expr,
                    };
                }
            }
        }
    }
    var seed_name: ?[]const u8 = null;
    for (stmts[0..if_index]) |*stmt| {
        if (stmt.* != .assign) continue;
        const as = stmt.assign;
        if (as.targets.len != 1) continue;
        if (assignTargetName(as.targets[0])) |n| seed_name = n;
    }
    const name = seed_name orelse return null;
    if (findSeedBeforeLoop(stmts[0..if_index], name) == null) return null;
    if (!branchAssignsName(then_block, name)) return null;
    if (else_body) |eb| {
        if (!branchAssignsName(&eb, name)) return null;
    } else return null;
    return .{
        .rule = .tail_branch_carried,
        .region = .tail_branch,
        .expr = nameExprRef(then_block, name) orelse return null,
    };
}

fn exprsSameShape(a: *const ast.Expr, b: *const ast.Expr) bool {
    if (@intFromEnum(a.*) != @intFromEnum(b.*)) return false;
    return switch (a.*) {
        .name => std.mem.eql(u8, a.name.ident, b.name.ident),
        else => a == b,
    };
}

fn branchAssignsName(block: *const ast.Block, name: []const u8) bool {
    if (block.stmts.len == 0) return false;
    const last = &block.stmts[block.stmts.len - 1];
    if (last.* != .assign) return false;
    const as = last.assign;
    if (as.targets.len != 1) return false;
    const n = assignTargetName(as.targets[0]) orelse return false;
    return std.mem.eql(u8, n, name);
}

fn nameExprRef(block: *const ast.Block, name: []const u8) ?*ast.Expr {
    if (findLastUpdateTargetInBlock(block, name)) |target| return target;
    return null;
}

fn assignTargetName(expr: *const ast.Expr) ?[]const u8 {
    return switch (expr.*) {
        .name => |n| n.ident,
        else => null,
    };
}

fn binopUpdatesName(val: *const ast.Expr, name: []const u8) bool {
    if (val.* != .binop) return false;
    return switch (val.binop.lhs.*) {
        .name => |n| std.mem.eql(u8, n.ident, name),
        else => false,
    };
}

/// `target <op> rhs` assigned back to `target` — the desugaring of `target op= rhs`.
fn binopUpdatesTarget(val: *const ast.Expr, target: *const ast.Expr) bool {
    if (val.* != .binop) return false;
    const lhs = val.binop.lhs;
    return switch (target.*) {
        .name => |n| lhs.* == .name and std.mem.eql(u8, lhs.name.ident, n.ident),
        .field => |f| lhs.* == .field and std.mem.eql(u8, lhs.field.field, f.field) and
            f.obj.* == .name and lhs.field.obj.* == .name and
            std.mem.eql(u8, lhs.field.obj.name.ident, f.obj.name.ident),
        else => false,
    };
}

fn findUniqueLoopCarriedName(body: *const ast.Block) ?[]const u8 {
    var name: ?[]const u8 = null;
    for (body.stmts) |*stmt| {
        if (stmt.* != .assign) continue;
        const as = stmt.assign;
        if (as.targets.len != 1) return null;
        const n = assignTargetName(as.targets[0]) orelse return null;
        if (name) |prev| {
            if (!std.mem.eql(u8, prev, n)) return null;
        } else {
            name = n;
        }
    }
    return name;
}

fn findSeedBeforeLoop(stmts: []const ast.Stmt, name: []const u8) ?*ast.Expr {
    for (stmts) |*stmt| {
        if (stmt.* != .assign) continue;
        const as = stmt.assign;
        if (as.targets.len != 1 or as.values.len != 1) continue;
        if (assignTargetName(as.targets[0])) |n| {
            if (std.mem.eql(u8, n, name)) return as.values[0];
        }
    }
    return null;
}

fn findLastUpdateTargetInBlock(body: *const ast.Block, name: []const u8) ?*ast.Expr {
    var found: ?*ast.Expr = null;
    for (body.stmts) |*stmt| {
        if (stmt.* != .assign) continue;
        const as = stmt.assign;
        if (as.targets.len != 1) continue;
        if (assignTargetName(as.targets[0])) |n| {
            if (std.mem.eql(u8, n, name)) found = as.targets[0];
        }
    }
    return found;
}

test "tail_result_demand: tail assignment rule A" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const mod = try parseDuo(
        \\double = (x): i64
        \\    value = x * 2
        \\end
    , &arena);
    const body = mod.body.stmts[0].func_decl.func.body;
    const r = blockTailResult(&body) orelse return error.TestExpectedEqual;
    try std.testing.expect(r.rule == .tail_assignment);
    try std.testing.expect(r.expr.* == .binop);
}

test "tail_result_demand: loop-carried factorial rule F" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const mod = try parseDuo(
        \\factorial = (n: i64): i64
        \\    value = 1
        \\    for i = 2, n
        \\        value *= i
        \\    end
        \\end
    , &arena);
    const body = mod.body.stmts[0].func_decl.func.body;
    const r = blockTailResult(&body) orelse return error.TestExpectedEqual;
    try std.testing.expect(r.rule == .tail_loop_carried);
    try std.testing.expect(r.expr.* == .name);
    try std.testing.expectEqualStrings("value", r.expr.name.ident);
}

test "tail_result_demand: transparent trailer preserves anchor" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const mod = try parseDuo(
        \\calculate = (x): i64
        \\    value = x * 2
        \\    print value
        \\end
    , &arena);
    const body = mod.body.stmts[0].func_decl.func.body;
    const r = blockTailResult(&body) orelse return error.TestExpectedEqual;
    try std.testing.expect(r.rule == .tail_assignment);
    try std.testing.expect(r.transparent_trailer_count >= 1);
}

test "tail_result_demand: ambiguous pre-loop locals + effect loop returns null" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const mod = try parseDuo(
        \\bad = (x): i64
        \\    a = compute_a(x)
        \\    b = compute_b(x)
        \\    for item in items
        \\        update(item)
        \\    end
        \\end
    , &arena);
    const body = mod.body.stmts[0].func_decl.func.body;
    try std.testing.expect(blockTailResult(&body) == null);
}

fn parseDuo(src: []const u8, arena: *std.heap.ArenaAllocator) !ast.Module {
    var lex = @import("lexer.zig").Lexer.init(src, "test.id");
    var parser = @import("parser.zig").Parser.init(&lex, arena.allocator());
    parser.idol_mode = true;
    return parser.parse_module();
}
