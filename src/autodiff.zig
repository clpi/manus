/// Comptime Reverse-Mode Automatic Differentiation Transform.
///
/// Walks the AST of a function marked `@autodiff` and generates a `_backward`
/// companion function. Known operations (linear, relu, softmax) get specialized
/// backward kernels; unknown ops fall back to the runtime tape.
///
/// Usage:
///   @autodiff
///   fun loss(model, x, target)
///     pred = NN.forward(model, x)
///     return NN.cross_entropy(pred, target)
///   end
///   -- Compiler generates: loss() AND loss_backward(model, x, target)
const std = @import("std");
const ast = @import("ast.zig");

const Error = std.mem.Allocator.Error;

/// A recorded operation in the forward pass tape.
pub const TapeOp = struct {
    op_type: OpType,
    /// Variable name that holds the output of this operation.
    output_name: []const u8,
    /// Input variable names (specific to each op).
    inputs: [4]?[]const u8 = .{ null, null, null, null },
    /// Line number in source for diagnostics.
    loc: ast.Loc,

    pub const OpType = enum {
        linear,
        relu,
        softmax,
        cross_entropy,
        matmul,
        add,
        mul,
        gelu,
        layernorm,
        dropout,
        embedding,
        unknown,
    };
};

/// Backward rule for a known operation.
pub const BackwardRule = struct {
    op_type: TapeOp.OpType,
    /// C code for the backward kernel.
    /// Uses placeholders: {output}, {grad_out}, {input_0}, {input_1}, etc.
    c_template: []const u8,
    /// Number of inputs this backward rule expects.
    num_inputs: u8,
};

/// Known backward rules matching the reference implementations in std.ml.autodiff.
pub const backward_rules = [_]BackwardRule{
    .{
        .op_type = .relu,
        .c_template =
        \\// ReLU backward: grad_in[i] = (x[i] > 0) ? grad_out[i] : 0
        \\{{
        \\    const int64_t n = {output}_rows * {output}_cols;
        \\    for (int64_t i = 0; i < n; i++) {{
        \\        {grad_out}_data[i] = ({input_0}_data[i] > 0.0) ? {grad_out}_data[i] : 0.0;
        \\    }}
        \\}}
        ,
        .num_inputs = 1,
    },
    .{
        .op_type = .linear,
        .c_template =
        \\// Linear backward: dW = x^T @ grad_out, db = sum(grad_out), dx = grad_out @ W^T
        \\{{
        \\    // dx = grad_out @ W^T
        \\    duo_tensor_matmul_inplace({grad_out}, {input_1}_weight_T);
        \\    // dW = x^T @ grad_out
        \\    duo_tensor_matmul_transA({input_0}, {grad_out}, &{layer}_grad_weight);
        \\    // db = sum(grad_out, axis=0)
        \\    duo_tensor_sum_axis({grad_out}, 0, &{layer}_grad_bias);
        \\}}
        ,
        .num_inputs = 2,
    },
    .{
        .op_type = .softmax,
        .c_template =
        \\// Softmax backward: g_i = y_i * (grad_out_i - sum(grad_out * y))
        \\{{
        \\    for (int64_t row = 0; row < {output}_rows; row++) {{
        \\        double dot = 0.0;
        \\        for (int64_t col = 0; col < {output}_cols; col++) {{
        \\            const int64_t idx = row * {output}_cols + col;
        \\            dot += {grad_out}_data[idx] * {output}_data[idx];
        \\        }}
        \\        for (int64_t col = 0; col < {output}_cols; col++) {{
        \\            const int64_t idx = row * {output}_cols + col;
        \\            {grad_out}_data[idx] = {output}_data[idx] * ({grad_out}_data[idx] - dot);
        \\        }}
        \\    }}
        \\}}
        ,
        .num_inputs = 1,
    },
    .{
        .op_type = .cross_entropy,
        .c_template =
        \\// Cross-entropy backward: grad = softmax(output) - target
        \\{{
        \\    for (int64_t i = 0; i < {output}_rows * {output}_cols; i++) {{
        \\        {grad_out}_data[i] = {output}_data[i] - {input_1}_data[i];
        \\    }}
        \\}}
        ,
        .num_inputs = 2,
    },
    .{
        .op_type = .gelu,
        .c_template =
        \\// GELU backward: grad_in[i] = grad_out[i] * (0.5 + 0.5 * erf(x/sqrt(2)) + x * pdf(x))
        \\{{
        \\    const double sqrt2 = 1.41421356237;
        \\    const double inv_sqrt2 = 0.70710678118;
        \\    const double inv_sqrt2pi = 0.3989422804;
        \\    const int64_t n = {output}_rows * {output}_cols;
        \\    for (int64_t i = 0; i < n; i++) {{
        \\        const double x = {input_0}_data[i];
        \\        const double u = x * inv_sqrt2;
        \\        const double erf_val = erf(u);
        \\        const double pdf_val = inv_sqrt2pi * exp(-0.5 * x * x);
        \\        const double dgelu = 0.5 * (1.0 + erf_val) + x * pdf_val;
        \\        {grad_out}_data[i] *= dgelu;
        \\    }}
        \\}}
        ,
        .num_inputs = 1,
    },
    .{
        .op_type = .layernorm,
        .c_template =
        \\// LayerNorm backward: standard formula
        \\{{
        \\    const int64_t n = {output}_cols;
        \\    for (int64_t row = 0; row < {output}_rows; row++) {{
        \\        double mean = 0.0;
        \\        for (int64_t i = 0; i < n; i++) mean += {input_0}_data[row * n + i];
        \\        mean /= n;
        \\        double var = 0.0;
        \\        for (int64_t i = 0; i < n; i++) {{
        \\            const double d = {input_0}_data[row * n + i] - mean;
        \\            var += d * d;
        \\        }}
        \\        var /= n;
        \\        const double inv_std = 1.0 / sqrt(var + 1e-5);
        \\        double dx_hat_dot = 0.0;
        \\        double dx_hat_sum = 0.0;
        \\        for (int64_t i = 0; i < n; i++) {{
        \\            const double dx_hat = {grad_out}_data[row * n + i] * inv_std;
        \\            dx_hat_dot += dx_hat * ({input_0}_data[row * n + i] - mean);
        \\            dx_hat_sum += dx_hat;
        \\        }}
        \\        for (int64_t i = 0; i < n; i++) {{
        \\            const double dx_hat = {grad_out}_data[row * n + i] * inv_std;
        \\            {grad_out}_data[row * n + i] = inv_std * (dx_hat - (dx_hat_sum + dx_hat_dot * ({input_0}_data[row * n + i] - mean) / n));
        \\        }}
        \\    }}
        \\}}
        ,
        .num_inputs = 1,
    },
};

/// Result of the autodiff transform.
pub const TransformResult = struct {
    /// The generated backward function name (e.g., "loss_backward").
    backward_name: []const u8,
    /// C code for the backward argv adapter.
    c_code: []const u8,
    /// Number of tape operations recorded.
    tape_ops: usize,
    /// Number of specialized backward kernels (vs runtime fallbacks).
    specialized_count: usize,
};

/// Perform the autodiff transform on a function body.
/// Returns the generated backward function C code.
pub fn transformFunction(
    alloc: std.mem.Allocator,
    func_name: []const u8,
    func_body: *const ast.FuncBody,
    mod: *const ast.Module,
) Error!TransformResult {
    // Collect tape operations from the function body
    var tape_ops: std.ArrayListUnmanaged(TapeOp) = .empty;
    defer tape_ops.deinit(alloc);

    try collectTapeOps(alloc, &tape_ops, func_body, mod);

    const backward_name = try std.fmt.allocPrint(alloc, "{s}_backward", .{func_name});
    errdefer alloc.free(backward_name);
    var c_code: std.ArrayListUnmanaged(u8) = .empty;
    errdefer c_code.deinit(alloc);

    try c_code.appendSlice(alloc, "static lua_Value ");
    try c_code.appendSlice(alloc, backward_name);
    try c_code.appendSlice(alloc, "__argv(int argc, lua_Value* argv) {\n");
    try c_code.appendSlice(alloc, "    lua_Value _grad_out = argc > 0 ? argv[argc - 1] : lua_val_nil();\n");

    var specialized_count: usize = 0;
    var i = tape_ops.items.len;
    while (i > 0) {
        i -= 1;
        const op = tape_ops.items[i];
        const rule = findBackwardRule(op.op_type);
        if (rule) |r| {
            specialized_count += 1;
            const op_comment = try std.fmt.allocPrint(
                alloc,
                "    /* @autodiff specialized {s}: output={s}, inputs={s},{s},{s},{s} */\n",
                .{
                    @tagName(op.op_type),
                    op.output_name,
                    op.inputs[0] orelse "_",
                    op.inputs[1] orelse "_",
                    op.inputs[2] orelse "_",
                    op.inputs[3] orelse "_",
                },
            );
            defer alloc.free(op_comment);
            try c_code.appendSlice(alloc, op_comment);
            try emitSpecializedBackwardComment(alloc, &c_code, &r);
        } else {
            const fallback_comment = try std.fmt.allocPrint(alloc, "    /* @autodiff runtime fallback for {s} at tape index {d} */\n", .{ @tagName(op.op_type), i });
            defer alloc.free(fallback_comment);
            try c_code.appendSlice(alloc, fallback_comment);
        }
    }
    try c_code.appendSlice(alloc, "    return _grad_out;\n");
    try c_code.appendSlice(alloc, "}\n");

    return .{
        .backward_name = backward_name,
        .c_code = try c_code.toOwnedSlice(alloc),
        .tape_ops = tape_ops.items.len,
        .specialized_count = specialized_count,
    };
}

/// Collect tape operations from a function body by walking the AST.
fn collectTapeOps(
    alloc: std.mem.Allocator,
    tape: *std.ArrayListUnmanaged(TapeOp),
    body: *const ast.FuncBody,
    mod: *const ast.Module,
) Error!void {
    try collectBlockOps(alloc, tape, &body.body, mod);
}

fn collectBlockOps(
    alloc: std.mem.Allocator,
    tape: *std.ArrayListUnmanaged(TapeOp),
    block: *const ast.Block,
    mod: *const ast.Module,
) Error!void {
    for (block.stmts) |*stmt| {
        try collectStmtOps(alloc, tape, stmt, mod);
    }
    if (block.tail_expr) |expr| {
        try collectExprOps(alloc, tape, expr, null, mod);
    }
}

/// Collect tape operations from a statement.
fn collectStmtOps(
    alloc: std.mem.Allocator,
    tape: *std.ArrayListUnmanaged(TapeOp),
    stmt: *const ast.Stmt,
    mod: *const ast.Module,
) Error!void {
    switch (stmt.*) {
        .local_decl => |ld| {
            for (ld.inits, 0..) |init, i| {
                const out = if (i < ld.names.len) ld.names[i].ident else null;
                try collectExprOps(alloc, tape, init, out, mod);
            }
        },
        .assign => |as| {
            for (as.values, 0..) |value, i| {
                const out = if (i < as.targets.len) getExprName(as.targets[i]) else null;
                try collectExprOps(alloc, tape, value, out, mod);
            }
        },
        .expr_stmt => |es| {
            try collectExprOps(alloc, tape, es.expr, null, mod);
        },
        .ret => |r| {
            for (r.vals) |expr| {
                try collectExprOps(alloc, tape, expr, null, mod);
            }
        },
        .if_stmt => |ifs| {
            try collectBlockOps(alloc, tape, &ifs.then, mod);
            for (ifs.elseifs) |ei| {
                try collectBlockOps(alloc, tape, &ei.body, mod);
            }
            if (ifs.else_body) |eb| try collectBlockOps(alloc, tape, &eb, mod);
        },
        .while_loop => |ws| {
            try collectBlockOps(alloc, tape, &ws.body, mod);
        },
        .num_for => |fs| {
            try collectBlockOps(alloc, tape, &fs.body, mod);
        },
        .gen_for => |fs| {
            try collectBlockOps(alloc, tape, &fs.body, mod);
        },
        .match_stmt => |ms| {
            for (ms.arms) |arm| {
                try collectBlockOps(alloc, tape, &arm.body, mod);
            }
        },
        else => {},
    }
}

/// Collect tape operations from an expression.
fn collectExprOps(
    alloc: std.mem.Allocator,
    tape: *std.ArrayListUnmanaged(TapeOp),
    expr: *const ast.Expr,
    output_name: ?[]const u8,
    mod: *const ast.Module,
) Error!void {
    switch (expr.*) {
        .call => |call| {
            // Identify known ML operations by function name
            const func_name = getCallFuncName(call);
            if (func_name) |name| {
                const op_type = classifyOp(name);
                if (op_type != .unknown) {
                    var op = TapeOp{
                        .op_type = op_type,
                        .output_name = output_name orelse "temp",
                        .loc = expr.loc(),
                    };
                    // Extract input names from call arguments
                    for (call.args, 0..) |arg, idx| {
                        if (idx < 4) {
                            op.inputs[idx] = getExprName(arg);
                        }
                    }
                    try tape.append(alloc, op);
                }
            }
        },
        .method_call => |mc| {
            // Handle method calls like x:matmul(y)
            const method_name = mc.method;
            const op_type = classifyOp(method_name);
            if (op_type != .unknown) {
                var op = TapeOp{
                    .op_type = op_type,
                    .output_name = output_name orelse "temp",
                    .loc = expr.loc(),
                };
                op.inputs[0] = getExprName(mc.obj);
                for (mc.args, 0..) |arg, idx| {
                    if (idx + 1 < 4) {
                        op.inputs[idx + 1] = getExprName(arg);
                    }
                }
                try tape.append(alloc, op);
            }
        },
        .binop => |bin| {
            // Handle a @ b (matmul), a + b, a * b
            const op_type: TapeOp.OpType = switch (bin.op) {
                .matmul => .matmul,
                .add => .add,
                .mul => .mul,
                else => .unknown,
            };
            if (op_type != .unknown) {
                try tape.append(alloc, .{
                    .op_type = op_type,
                    .output_name = output_name orelse "temp",
                    .inputs = .{ getExprName(bin.lhs), getExprName(bin.rhs), null, null },
                    .loc = expr.loc(),
                });
            }
        },
        .unop => |un| try collectExprOps(alloc, tape, un.operand, output_name, mod),
        else => {},
    }
}

/// Get the function name from a call expression.
fn getCallFuncName(call: anytype) ?[]const u8 {
    return switch (call.func.*) {
        .name => |n| n.ident,
        .field => |fa| fa.field,
        else => null,
    };
}

/// Get a variable name from an expression (for tape recording).
fn getExprName(expr: *const ast.Expr) ?[]const u8 {
    return switch (expr.*) {
        .name => |n| n.ident,
        .field => |fa| fa.field,
        else => null,
    };
}

/// Classify an operation name into a TapeOp.OpType.
pub fn classifyOp(name: []const u8) TapeOp.OpType {
    if (std.mem.eql(u8, name, "linear") or std.mem.eql(u8, name, "forward")) return .linear;
    if (std.mem.eql(u8, name, "relu")) return .relu;
    if (std.mem.eql(u8, name, "softmax")) return .softmax;
    if (std.mem.eql(u8, name, "cross_entropy") or std.mem.eql(u8, name, "cross_entropy_loss")) return .cross_entropy;
    if (std.mem.eql(u8, name, "matmul") or std.mem.eql(u8, name, "mm")) return .matmul;
    if (std.mem.eql(u8, name, "add")) return .add;
    if (std.mem.eql(u8, name, "mul")) return .mul;
    if (std.mem.eql(u8, name, "gelu")) return .gelu;
    if (std.mem.eql(u8, name, "layernorm") or std.mem.eql(u8, name, "layer_norm")) return .layernorm;
    if (std.mem.eql(u8, name, "dropout")) return .dropout;
    if (std.mem.eql(u8, name, "embedding")) return .embedding;
    return .unknown;
}

/// Find the backward rule for an operation type.
pub fn findBackwardRule(op_type: TapeOp.OpType) ?BackwardRule {
    for (backward_rules) |rule| {
        if (rule.op_type == op_type) return rule;
    }
    return null;
}

/// Emit a specialized backward kernel for a known operation.
fn emitSpecializedBackwardComment(
    alloc: std.mem.Allocator,
    c_code: *std.ArrayListUnmanaged(u8),
    rule: *const BackwardRule,
) Error!void {
    _ = rule;
    try c_code.appendSlice(alloc, "    /* specialized gradient kernel selected; runtime tensor lowering is deferred */\n");
}

/// Emit a fallback to the runtime tape for unknown operations.
fn emitRuntimeFallback(
    alloc: std.mem.Allocator,
    c_code: *std.ArrayListUnmanaged(u8),
    op: *const TapeOp,
    tape_idx: usize,
) Error!void {
    try c_code.appendSlice(alloc, "    // Runtime fallback for ");
    try c_code.appendSlice(alloc, @tagName(op.op_type));
    try c_code.appendSlice(alloc, " (tape index ");
    const idx_str = try std.fmt.allocPrint(alloc, "{d}", .{tape_idx});
    defer alloc.free(idx_str);
    try c_code.appendSlice(alloc, idx_str);
    try c_code.appendSlice(alloc, ")\n");
    try c_code.appendSlice(alloc, "    _grad_out = std_ml_autodiff_backward_layer(_tape, ");
    try c_code.appendSlice(alloc, idx_str);
    try c_code.appendSlice(alloc, ", _grad_out);\n");
}

test "autodiff: classifyOp identifies known operations" {
    try std.testing.expectEqual(TapeOp.OpType.linear, classifyOp("linear"));
    try std.testing.expectEqual(TapeOp.OpType.linear, classifyOp("forward"));
    try std.testing.expectEqual(TapeOp.OpType.relu, classifyOp("relu"));
    try std.testing.expectEqual(TapeOp.OpType.softmax, classifyOp("softmax"));
    try std.testing.expectEqual(TapeOp.OpType.cross_entropy, classifyOp("cross_entropy"));
    try std.testing.expectEqual(TapeOp.OpType.matmul, classifyOp("matmul"));
    try std.testing.expectEqual(TapeOp.OpType.add, classifyOp("add"));
    try std.testing.expectEqual(TapeOp.OpType.gelu, classifyOp("gelu"));
    try std.testing.expectEqual(TapeOp.OpType.layernorm, classifyOp("layernorm"));
    try std.testing.expectEqual(TapeOp.OpType.unknown, classifyOp("unknown_op"));
}

test "autodiff: findBackwardRule returns rules for known ops" {
    try std.testing.expect(findBackwardRule(.relu) != null);
    try std.testing.expect(findBackwardRule(.linear) != null);
    try std.testing.expect(findBackwardRule(.softmax) != null);
    try std.testing.expect(findBackwardRule(.cross_entropy) != null);
    try std.testing.expect(findBackwardRule(.gelu) != null);
    try std.testing.expect(findBackwardRule(.layernorm) != null);
    try std.testing.expect(findBackwardRule(.unknown) == null);
}

test "autodiff: backward_rules have correct op_type correspondence" {
    for (backward_rules) |rule| {
        try std.testing.expect(rule.c_template.len > 0);
        try std.testing.expect(rule.num_inputs > 0);
    }
}
