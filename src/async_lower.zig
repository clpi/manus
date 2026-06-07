const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;

/// Async state machine states
pub const AsyncState = enum(u32) {
    start = 0,
    awaiting = 1,
    completed = 2,
    cancelled = 3,
    // User-defined await points start from 4
    first_await_point = 4,
};

/// Represents a lowered async function (state machine)
pub const LoweredAsync = struct {
    /// Original function declaration
    original: *ast.FuncDecl,

    /// Frame struct type name
    frame_type_name: []const u8,

    /// Step function name
    step_func_name: []const u8,

    /// State field index in frame
    state_field_idx: u32,

    /// Result field index in frame
    result_field_idx: u32,

    /// Await points identified in the function
    await_points: std.ArrayList(AwaitPoint),

    /// Deferred statements for cleanup
    deferred_stmts: std.ArrayList(*ast.Stmt),
};

/// An await point in the async function
pub const AwaitPoint = struct {
    /// State number for this await point
    state: u32,

    /// The expression being awaited
    expr: *ast.Expr,

    /// Location in source
    loc: ast.Loc,

    /// Variables captured at this point (for restoration)
    captured_vars: std.StringHashMap(*ast.Expr),
};

/// Async lowering pass
pub const AsyncLower = struct {
    allocator: Allocator,

    /// All lowered async functions
    lowered_funcs: std.ArrayList(LoweredAsync),

    /// Map from original function to its lowered version
    func_map: AutoHashMap(*ast.FuncDecl, *LoweredAsync),

    /// Counter for generating unique names
    name_counter: u64,

    const Self = @This();
    const Error = error{OutOfMemory} || ast.Error;

    /// State tracking during analysis
    const FuncState = struct {
        await_points: std.ArrayList(AwaitPoint),
        deferred: std.ArrayList(*ast.Stmt),
        state_counter: u32,
    };

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .lowered_funcs = std.ArrayList(LoweredAsync).init(allocator),
            .func_map = AutoHashMap(*ast.FuncDecl, *LoweredAsync).init(allocator),
            .name_counter = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.lowered_funcs.items) |*lowered| {
            lowered.await_points.deinit();
            lowered.deferred_stmts.deinit();
        }
        self.lowered_funcs.deinit();
        self.func_map.deinit();
    }

    /// Run async lowering on the entire module
    pub fn run(self: *Self, module: *ast.Module) Error!void {
        // First pass: identify all async functions
        for (module.top_level.items) |decl| {
            switch (decl.*) {
                .func => |func_decl| {
                    if (func_decl.func.is_async) {
                        try self.lowerAsyncFunc(&func_decl.func);
                    }
                },
                else => {},
            }
        }
    }

    /// Lower a single async function to state machine form
    fn lowerAsyncFunc(self: *Self, func: *ast.FuncDecl) Error!void {
        // Generate unique names
        const frame_name = try self.generateFrameName(func);
        const step_name = try self.generateStepName(func);

        // Analyze await points and deferred statements
        var func_state = FuncState{
            .await_points = std.ArrayList(AwaitPoint).init(self.allocator),
            .deferred = std.ArrayList(*ast.Stmt).init(self.allocator),
            .state_counter = AsyncState.first_await_point,
        };
        defer func_state.await_points.deinit();
        defer func_state.deferred.deinit();

        // Scan function body for await expressions and defers
        if (func.body) |body| {
            try self.scanForAwaitsAndDefers(body.body, &func_state);
        }

        // Create the lowered representation
        const lowered = LoweredAsync{
            .original = func,
            .frame_type_name = frame_name,
            .step_func_name = step_name,
            .state_field_idx = 0, // Will be set during frame struct generation
            .result_field_idx = 1,
            .await_points = std.ArrayList(AwaitPoint).init(self.allocator),
            .deferred_stmts = std.ArrayList(*ast.Stmt).init(self.allocator),
        };

        try self.lowered_funcs.append(lowered);
        const lowered_ptr = &self.lowered_funcs.items[self.lowered_funcs.items.len - 1];

        // Copy await points
        for (func_state.await_points.items) |point| {
            try lowered_ptr.await_points.append(point);
        }

        // Copy deferred statements
        for (func_state.deferred.items) |stmt| {
            try lowered_ptr.deferred_stmts.append(stmt);
        }

        // Map original to lowered
        try self.func_map.put(func, lowered_ptr);
    }

    /// Scan a statement for await expressions and deferred statements
    fn scanForAwaitsAndDefers(self: *Self, stmt: *ast.Stmt, state: *FuncState) Error!void {
        switch (stmt.*) {
            .defer_stmt => |defer_stmt| {
                // Collect deferred statement for LIFO execution
                try state.deferred.append(defer_stmt.body);
                // Continue scanning the defer body for nested awaits/defers
                try self.scanForAwaitsAndDefers(defer_stmt.body, state);
            },

            .expr_stmt => |expr_stmt| {
                try self.scanExprForAwaits(expr_stmt.expr, state);
            },

            .local => |local| {
                if (local.init) |init_expr| {
                    try self.scanExprForAwaits(init_expr, state);
                }
            },

            .decl => |decl| {
                if (decl.init) |init_expr| {
                    try self.scanExprForAwaits(init_expr, state);
                }
            },

            .assign => |assign| {
                try self.scanExprForAwaits(assign.rhs, state);
            },

            .compound_assign => |ca| {
                try self.scanExprForAwaits(ca.rhs, state);
            },

            .ret => |ret| {
                if (ret.val) |val| {
                    try self.scanExprForAwaits(val, state);
                }
                // Return is a scope exit - defers will be handled during lowering
            },

            .if_stmt => |if_stmt| {
                try self.scanExprForAwaits(if_stmt.cond, state);
                try self.scanForAwaitsAndDefers(if_stmt.then_body, state);
                if (if_stmt.else_body) |else_body| {
                    try self.scanForAwaitsAndDefers(else_body, state);
                }
            },

            .while_stmt => |while_stmt| {
                try self.scanExprForAwaits(while_stmt.cond, state);
                try self.scanForAwaitsAndDefers(while_stmt.body, state);
            },

            .for_stmt => |for_stmt| {
                try self.scanExprForAwaits(for_stmt.iter, state);
                try self.scanForAwaitsAndDefers(for_stmt.body, state);
            },

            .do_stmt => |do_stmt| {
                try self.scanForAwaitsAndDefers(do_stmt.body, state);
                try self.scanExprForAwaits(do_stmt.cond, state);
            },

            .repeat_stmt => |repeat_stmt| {
                try self.scanForAwaitsAndDefers(repeat_stmt.body, state);
                try self.scanExprForAwaits(repeat_stmt.count, state);
            },

            .block => |block| {
                for (block.stmts.items) |s| {
                    try self.scanForAwaitsAndDefers(s, state);
                }
            },

            .try_stmt => |try_stmt| {
                try self.scanForAwaitsAndDefers(try_stmt.block, state);
                for (try_stmt.catches) |catch_clause| {
                    try self.scanForAwaitsAndDefers(catch_clause.body, state);
                }
            },

            .match_stmt => |match_stmt| {
                try self.scanExprForAwaits(match_stmt.expr, state);
                for (match_stmt.arms) |arm| {
                    if (arm.guard) |guard| {
                        try self.scanExprForAwaits(guard, state);
                    }
                    try self.scanForAwaitsAndDefers(arm.body, state);
                }
            },

            else => {},
        }
    }

    /// Scan an expression for await expressions
    fn scanExprForAwaits(self: *Self, expr: *ast.Expr, state: *FuncState) Error!void {
        switch (expr.*) {
            .await_expr => |await_expr| {
                // Found an await point
                const await_point = AwaitPoint{
                    .state = state.state_counter,
                    .expr = await_expr.expr,
                    .loc = await_expr.loc,
                    .captured_vars = std.StringHashMap(*ast.Expr).init(self.allocator),
                };
                try state.await_points.append(await_point);
                state.state_counter += 1;

                // Continue scanning the awaited expression
                try self.scanExprForAwaits(await_expr.expr, state);
            },

            .call => |call| {
                try self.scanExprForAwaits(call.func, state);
                for (call.args.items) |arg| {
                    try self.scanExprForAwaits(arg, state);
                }
            },

            .bin_op => |bin_op| {
                try self.scanExprForAwaits(bin_op.lhs, state);
                try self.scanExprForAwaits(bin_op.rhs, state);
            },

            .un_op => |un_op| {
                try self.scanExprForAwaits(un_op.expr, state);
            },

            .index => |index| {
                try self.scanExprForAwaits(index.obj, state);
                try self.scanExprForAwaits(index.key, state);
            },

            .field => |field| {
                try self.scanExprForAwaits(field.obj, state);
            },

            .paren => |paren| {
                try self.scanExprForAwaits(paren.expr, state);
            },

            .table => |table| {
                for (table.fields.items) |field| {
                    try self.scanExprForAwaits(field.val, state);
                }
            },

            .array => |array| {
                for (array.elems.items) |elem| {
                    try self.scanExprForAwaits(elem, state);
                }
            },

            .lambda => |lambda| {
                if (lambda.body) |body| {
                    var nested_state = FuncState{
                        .await_points = std.ArrayList(AwaitPoint).init(self.allocator),
                        .deferred = std.ArrayList(*ast.Stmt).init(self.allocator),
                        .state_counter = AsyncState.first_await_point,
                    };
                    defer nested_state.await_points.deinit();
                    defer nested_state.deferred.deinit();

                    try self.scanForAwaitsAndDefers(body.body, &nested_state);
                    // Nested functions get their own lowering
                }
            },

            .match_expr => |match_expr| {
                try self.scanExprForAwaits(match_expr.expr, state);
                for (match_expr.arms) |arm| {
                    if (arm.guard) |guard| {
                        try self.scanExprForAwaits(guard, state);
                    }
                    try self.scanExprForAwaits(arm.body, state);
                }
            },

            .try_expr => |try_expr| {
                try self.scanExprForAwaits(try_expr.expr, state);
            },

            .unwrap_expr => |unwrap_expr| {
                try self.scanExprForAwaits(unwrap_expr.expr, state);
            },

            .contains_expr => |contains_expr| {
                try self.scanExprForAwaits(contains_expr.lhs, state);
                try self.scanExprForAwaits(contains_expr.rhs, state);
            },

            else => {},
        }
    }

    /// Generate the frame struct definition as C code
    pub fn generateFrameStruct(_: *Self, lowered: *LoweredAsync, writer: anytype) !void {
        try writer.print("typedef struct {s} {{", .{lowered.frame_type_name});
        try writer.print("    int state;", .{});

        // Add field for return type
        if (lowered.original.ret_ty) |ret_ty| {
            // We'd generate the C type here
            try writer.print("    /* result field of type */;", .{});
            _ = ret_ty;
        }

        // Add fields for captured locals at each await point
        // This requires analysis of which variables are live across await points

        // Add error field for result types
        const is_result = lowered.original.ret_ty != null and lowered.original.ret_ty.?.* == .result;
        if (is_result) {
            try writer.print("    duo_Error error;", .{});
        }

        try writer.print("}} {s};", .{lowered.frame_type_name});
    }

    /// Generate the step function as C code
    pub fn generateStepFunc(_: *Self, lowered: *LoweredAsync, writer: anytype) !void {
        try writer.print("static duo_Poll {s}({s}* frame) {{", .{
            lowered.step_func_name,
            lowered.frame_type_name,
        });

        try writer.print("    switch (frame->state) {{", .{});

        // Case 0: Initial entry point
        try writer.print("    case 0: /* start */", .{});
        // Generate code from function start until first await

        // Generate cases for each await point
        for (lowered.await_points.items) |point| {
            try writer.print("    case {d}: /* await point */", .{point.state});
            try writer.print("        frame->state = {d};", .{point.state + 1});
            try writer.print("        return DUO_POLL_PENDING;", .{});
        }

        // Completed state
        try writer.print("    default:", .{});
        try writer.print("        return DUO_POLL_READY;", .{});
        try writer.print("    }}", .{});

        try writer.print("}}", .{});
    }

    /// Generate defer cleanup code for cancellation
    pub fn generateDeferCleanup(_: *Self, lowered: *LoweredAsync, writer: anytype) !void {
        // Execute defers in LIFO order
        var i: usize = lowered.deferred_stmts.items.len;
        while (i > 0) : (i -= 1) {
            const stmt = lowered.deferred_stmts.items[i - 1];
            // Generate code for the deferred statement
            _ = stmt;
            try writer.print("    /* deferred statement */;", .{});
        }
    }

    /// Generate poll result enum
    pub fn generatePollEnum(self: *Self, writer: anytype) !void {
        _ = self;
        try writer.print("typedef enum {{", .{});
        try writer.print("    DUO_POLL_PENDING = 0,", .{});
        try writer.print("    DUO_POLL_READY = 1,", .{});
        try writer.print("    DUO_POLL_ERROR = 2,", .{});
        try writer.print("}} duo_Poll;", .{});
    }

    /// Check if a type is a result type
    fn isResultType(self: *Self, ty: ?*types.ResolvedType) bool {
        _ = self;
        if (ty) |t| {
            switch (t.*) {
                .result => return true,
                else => return false,
            }
        }
        return false;
    }

    /// Generate a unique frame struct name
    fn generateFrameName(self: *Self, func: *ast.FuncDecl) ![]const u8 {
        self.name_counter += 1;
        return std.fmt.allocPrint(self.allocator, "duo_frame_{s}_{d}", .{
            func.name,
            self.name_counter,
        });
    }

    /// Generate a unique step function name
    fn generateStepName(self: *Self, func: *ast.FuncDecl) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "duo_step_{s}", .{func.name});
    }

    /// Get the lowered version of an async function
    pub fn getLowered(self: *Self, func: *ast.FuncDecl) ?*LoweredAsync {
        return self.func_map.get(func);
    }

    /// Get all lowered async functions
    pub fn getAllLowered(self: *Self) []const LoweredAsync {
        return self.lowered_funcs.items;
    }
};

/// Integration with the compiler pipeline
pub fn runAsyncLowering(
    allocator: Allocator,
    module: *ast.Module,
) !AsyncLower {
    var async_lower = AsyncLower.init(allocator);
    errdefer async_lower.deinit();

    try async_lower.run(module);

    return async_lower;
}
