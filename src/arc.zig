const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;

/// ARC annotation types for memory management
pub const ARCAnnotation = union(enum) {
    /// Retain a reference (increment refcount)
    retain: struct {
        ptr: *ast.Expr,
        loc: ast.Loc,
    },
    /// Release a reference (decrement refcount, may free)
    release: struct {
        ptr: *ast.Expr,
        loc: ast.Loc,
    },
    /// Close resource before release (call __close method)
    close: struct {
        ptr: *ast.Expr,
        loc: ast.Loc,
    },
};

/// ARC insertion pass state
pub const ARCPass = struct {
    allocator: Allocator,

    /// Annotations to insert at specific program points
    annotations: std.ArrayList(ARCAnnotation),

    /// Track variables that need ARC management in current scope
    tracked_vars: std.StringHashMap(*types.ResolvedType),

    /// Stack of scopes for proper cleanup ordering
    scope_stack: std.ArrayList(std.StringHashMap(*types.ResolvedType)),

    /// Objects that need cycle collector registration
    cycle_candidates: std.ArrayList(*ast.Expr),

    const Self = @This();
    const Error = error{OutOfMemory} || ast.Error;

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .annotations = std.ArrayList(ARCAnnotation).init(allocator),
            .tracked_vars = std.StringHashMap(*types.ResolvedType).init(allocator),
            .scope_stack = std.ArrayList(std.StringHashMap(*types.ResolvedType)).init(allocator),
            .cycle_candidates = std.ArrayList(*ast.Expr).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.annotations.deinit();

        // Clean up scope stack
        for (self.scope_stack.items) |*scope| {
            scope.deinit();
        }
        self.scope_stack.deinit();

        self.tracked_vars.deinit();
        self.cycle_candidates.deinit();
    }

    /// Run ARC insertion pass on the entire module
    pub fn run(self: *Self, module: *ast.Module) Error!void {
        for (module.top_level.items) |decl| {
            try self.processDecl(decl);
        }
    }

    /// Process a top-level declaration.
    /// NOTE: there is no `.struct_def` arm. Records are anonymous and are
    /// handled inline at the binding site (via table-type annotations on
    /// `local_decl`/`global_decl` and on parameters).
    fn processDecl(self: *Self, decl: *ast.TopLevel) Error!void {
        switch (decl.*) {
            .func => |func_decl| try self.processFunc(&func_decl.func),
            .enum_def => |enum_def| try self.processEnum(enum_def),
            else => {},
        }
    }

    /// Process a function declaration
    fn processFunc(self: *Self, func: *ast.FuncDecl) Error!void {
        // Create new scope for function
        try self.pushScope();
        defer self.popScope();

        // Track parameters that are heap-allocated
        for (func.params.items) |param| {
            if (param.ty) |ty| {
                if (self.needsARC(ty)) {
                    try self.tracked_vars.put(param.name, ty);
                    // Parameters are retained by caller, no retain needed here
                }
            }
        }

        // Process function body
        if (func.body) |body| {
            try self.processStmt(body.body);
        }

        // Release all remaining tracked variables at function exit
        try self.releaseAllAtScopeExit();
    }

    /// Process a struct definition.
    /// NOTE: removed. Duo has no `struct` keyword; record types are
    /// declared via inline type-literal annotations on bindings. ARC for
    /// record-typed bindings is handled by `processStmt` (the
    /// `local_decl`/`global_decl` arms) and by the parameter-tracking loop
    /// in `processFunc`.

    /// Process an enum definition
    fn processEnum(self: *Self, enum_def: *ast.EnumDef) Error!void {
        // Process methods
        for (enum_def.methods.items) |method| {
            try self.processFunc(method);
        }
    }

    /// Process a statement
    fn processStmt(self: *Self, stmt: *ast.Stmt) Error!void {
        switch (stmt.*) {
            .expr_stmt => |expr_stmt| {
                try self.processExpr(expr_stmt.expr);
                // Result of expression statement is dropped - release if heap allocated
                try self.releaseIfHeapAllocated(expr_stmt.expr);
            },
            .decl => |decl| {
                if (decl.init) |init_expr| {
                    try self.processExpr(init_expr);

                    // Check if this is a new binding that needs tracking
                    if (decl.ty) |ty| {
                        if (self.needsARC(ty)) {
                            // Insert retain for the initial value
                            try self.insertRetain(init_expr);
                            try self.tracked_vars.put(decl.name, ty);
                        }
                    }
                }
            },
            .local => |local| {
                if (local.init) |init_expr| {
                    try self.processExpr(init_expr);

                    if (local.ty) |ty| {
                        if (self.needsARC(ty)) {
                            try self.insertRetain(init_expr);
                            try self.tracked_vars.put(local.name, ty);
                        }
                    }
                }
            },
            .assign => |assign| {
                // Process RHS first
                try self.processExpr(assign.rhs);

                // If assigning to a tracked variable, handle the lifecycle
                if (self.getVarType(assign.var_name)) |old_ty| {
                    if (self.needsARC(old_ty)) {
                        // Release old value
                        // (This is a simplified version - we'd need the actual expression)
                        // try self.insertReleaseForVar(assign.var_name);

                        // Retain new value
                        try self.insertRetain(assign.rhs);
                    }
                }
            },
            .compound_assign => |ca| {
                try self.processExpr(ca.rhs);
            },
            .if_stmt => |if_stmt| {
                try self.processExpr(if_stmt.cond);

                // Process then and else branches with new scopes
                try self.pushScope();
                try self.processStmt(if_stmt.then_body);
                try self.releaseScopeLocals();
                self.popScope();

                if (if_stmt.else_body) |else_body| {
                    try self.pushScope();
                    try self.processStmt(else_body);
                    try self.releaseScopeLocals();
                    self.popScope();
                }
            },
            .while_stmt => |while_stmt| {
                try self.processExpr(while_stmt.cond);

                try self.pushScope();
                try self.processStmt(while_stmt.body);
                try self.releaseScopeLocals();
                self.popScope();
            },
            .for_stmt => |for_stmt| {
                try self.processExpr(for_stmt.iter);

                try self.pushScope();

                // Track loop variable if it's a binding
                // (The iter variable would be handled by the iterator protocol)

                try self.processStmt(for_stmt.body);
                try self.releaseScopeLocals();
                self.popScope();
            },
            .do_stmt => |do_stmt| {
                try self.pushScope();
                try self.processStmt(do_stmt.body);
                try self.releaseScopeLocals();
                self.popScope();

                try self.processExpr(do_stmt.cond);
            },
            .repeat_stmt => |repeat_stmt| {
                try self.pushScope();
                try self.processStmt(repeat_stmt.body);
                try self.releaseScopeLocals();
                self.popScope();

                try self.processExpr(repeat_stmt.count);
            },
            .block => |block| {
                try self.pushScope();
                for (block.stmts.items) |s| {
                    try self.processStmt(s);
                }
                try self.releaseScopeLocals();
                self.popScope();
            },
            .ret => |ret| {
                if (ret.val) |val| {
                    try self.processExpr(val);
                    // Return value is retained by caller, no release needed
                }

                // Release all tracked variables before returning
                try self.releaseAllAtScopeExit();
            },
            .defer_stmt => |defer_stmt| {
                // Defer statements are tricky - their body runs at scope exit
                // We'll need to track this for later processing
                // For now, just process the body
                try self.processStmt(defer_stmt.body);
            },
            .try_stmt => |try_stmt| {
                try self.pushScope();
                try self.processStmt(try_stmt.block);
                try self.releaseScopeLocals();
                self.popScope();

                for (try_stmt.catches) |catch_clause| {
                    try self.pushScope();
                    if (catch_clause.var_name) |var_name| {
                        // The error value is owned by the catch clause
                        // Track it but don't retain (it's already retained from propagation)
                        if (catch_clause.error_ty) |ty| {
                            try self.tracked_vars.put(var_name, ty);
                        }
                    }
                    try self.processStmt(catch_clause.body);
                    try self.releaseScopeLocals();
                    self.popScope();
                }
            },
            .match_stmt => |match_stmt| {
                try self.processExpr(match_stmt.expr);

                for (match_stmt.arms) |arm| {
                    try self.pushScope();

                    // Bind pattern variables
                    try self.bindPatternVars(arm.pattern);

                    if (arm.guard) |guard| {
                        try self.processExpr(guard);
                    }

                    try self.processStmt(arm.body);
                    try self.releaseScopeLocals();
                    self.popScope();
                }
            },
            else => {},
        }
    }

    /// Process an expression
    fn processExpr(self: *Self, expr: *ast.Expr) Error!void {
        switch (expr.*) {
            .call => |call| {
                // Process function and arguments
                try self.processExpr(call.func);
                for (call.args.items) |arg| {
                    try self.processExpr(arg);
                    // Arguments are retained by callee (convention)
                }

                // The result of a call may need retain if heap allocated
                // This will be handled by the caller context
            },
            .index => |index| {
                try self.processExpr(index.obj);
                try self.processExpr(index.key);
            },
            .field => |field| try self.processExpr(field.obj),
            .bin_op => |bin_op| {
                try self.processExpr(bin_op.lhs);
                try self.processExpr(bin_op.rhs);
            },
            .un_op => |un_op| try self.processExpr(un_op.expr),
            .paren => |paren| try self.processExpr(paren.expr),
            .table => |table| {
                // Table creation - this is a heap allocation
                for (table.fields.items) |field| {
                    try self.processExpr(field.val);
                }

                // Mark as needing cycle collection if it can hold references
                if (self.tableCanContainRefs(table)) {
                    try self.markAsCycleCandidate(expr);
                }
            },
            .array => |array| {
                for (array.elems.items) |elem| {
                    try self.processExpr(elem);
                }

                if (self.arrayCanContainRefs(array)) {
                    try self.markAsCycleCandidate(expr);
                }
            },
            .lambda => |lambda| {
                // Lambda creation - captures variables
                if (lambda.body) |body| {
                    try self.pushScope();

                    // Track captured variables
                    for (lambda.captures.items) |capture| {
                        if (self.getVarType(capture.name)) |ty| {
                            // Captured variables need retain
                            if (self.needsARC(ty)) {
                                // We'd need the actual expression for the capture
                                // try self.insertRetain(capture_expr);
                            }
                        }
                    }

                    try self.processStmt(body.body);
                    try self.releaseScopeLocals();
                    self.popScope();
                }
            },
            .match_expr => |match_expr| {
                try self.processExpr(match_expr.expr);
                for (match_expr.arms) |arm| {
                    try self.pushScope();
                    try self.bindPatternVars(arm.pattern);
                    if (arm.guard) |guard| {
                        try self.processExpr(guard);
                    }
                    try self.processExpr(arm.body);
                    try self.releaseScopeLocals();
                    self.popScope();
                }
            },
            .try_expr => |try_expr| {
                try self.processExpr(try_expr.expr);
                // The ? operator may propagate errors
                // The result type is the ok type of the result
            },
            .unwrap_expr => |unwrap_expr| {
                try self.processExpr(unwrap_expr.expr);
                // The ! operator unwraps option/result types
            },
            .await_expr => |await_expr| {
                try self.processExpr(await_expr.expr);
            },
            .contains_expr => |contains_expr| {
                try self.processExpr(contains_expr.lhs);
                try self.processExpr(contains_expr.rhs);
            },
            .ident => |ident| {
                // When loading a variable, we may need to retain depending on context
                // For now, we assume the caller handles retain for loaded values
                _ = ident;
            },
            else => {},
        }
    }

    /// Check if a type needs ARC management
    fn needsARC(self: *Self, ty: *types.ResolvedType) bool {
        _ = self;
        // Primitive types don't need ARC
        switch (ty.*) {
            .i64, .f64, .bool, .nil => return false,
            // Reference types need ARC
            .str, .table, .arr, .fun, .user, .option, .result => return true,
            // Generic params may need ARC depending on constraint
            .generic_param => |gp| {
                // Check if it has @arc(false) attribute
                if (gp.constraint) |constraint| {
                    // Parse constraint for @arc attribute
                    // This is simplified - real impl would parse properly
                    if (std.mem.indexOf(u8, constraint, "@arc(false)") != null) {
                        return false;
                    }
                }
                return true; // Default to true for safety
            },
            // Channel types need ARC
            .channel => return true,
            // Enum types may need ARC if variants have payloads
            .enum_type => |enum_ty| {
                for (enum_ty.variants) |variant| {
                    if (variant.payload_ty != null) {
                        return true;
                    }
                }
                return false;
            },
            else => return true, // Conservative default
        }
    }

    /// Check if a table can contain reference types (cycles possible)
    fn tableCanContainRefs(self: *Self, table: ast.Table) bool {
        _ = self;
        _ = table;
        // Conservative: assume any table can hold references
        // In a real implementation, we'd check the field types
        return true;
    }

    /// Check if an array can contain reference types
    fn arrayCanContainRefs(self: *Self, array: ast.ArrayLiteral) bool {
        _ = self;
        _ = array;
        // Conservative default
        return true;
    }

    /// Mark an expression as a cycle collection candidate
    fn markAsCycleCandidate(self: *Self, expr: *ast.Expr) Error!void {
        try self.cycle_candidates.append(expr);
    }

    /// Get the type of a variable if tracked
    fn getVarType(self: *Self, name: []const u8) ?*types.ResolvedType {
        if (self.tracked_vars.get(name)) |ty| {
            return ty;
        }

        // Check parent scopes
        for (self.scope_stack.items) |scope| {
            if (scope.get(name)) |ty| {
                return ty;
            }
        }

        return null;
    }

    /// Push a new scope
    fn pushScope(self: *Self) Error!void {
        const new_scope = std.StringHashMap(*types.ResolvedType).init(self.allocator);
        try self.scope_stack.append(new_scope);
    }

    /// Pop the current scope (without releasing - use releaseScopeLocals first)
    fn popScope(self: *Self) void {
        const scope = self.scope_stack.pop();
        scope.deinit();
    }

    /// Release all locals in the current scope
    fn releaseScopeLocals(self: *Self) Error!void {
        if (self.scope_stack.items.len == 0) return;

        var current_scope = &self.scope_stack.items[self.scope_stack.items.len - 1];

        var iter = current_scope.iterator();
        while (iter.next()) |entry| {
            // Insert release for each tracked variable
            const var_name = entry.key_ptr.*;
            const ty = entry.value_ptr.*;

            if (self.needsARC(ty)) {
                // We'd create an identifier expression and release it
                // try self.insertReleaseForVar(var_name);
                _ = var_name;
            }
        }
    }

    /// Release all tracked variables at function/scope exit
    fn releaseAllAtScopeExit(self: *Self) Error!void {
        // Release current scope
        try self.releaseScopeLocals();

        // Also release parent scopes (for early returns)
        // In reverse order (LIFO for defers)
        var i: usize = self.scope_stack.items.len;
        while (i > 0) : (i -= 1) {
            var scope = &self.scope_stack.items[i - 1];

            var iter = scope.iterator();
            while (iter.next()) |entry| {
                const var_name = entry.key_ptr.*;
                const ty = entry.value_ptr.*;

                if (self.needsARC(ty)) {
                    // try self.insertReleaseForVar(var_name);
                    _ = var_name;
                }
            }
        }
    }

    /// Insert a retain annotation
    fn insertRetain(self: *Self, ptr: *ast.Expr) Error!void {
        try self.annotations.append(.{ .retain = .{
            .ptr = ptr,
            .loc = ptr.loc(),
        } });
    }

    /// Insert a release annotation
    fn insertRelease(self: *Self, ptr: *ast.Expr) Error!void {
        try self.annotations.append(.{ .release = .{
            .ptr = ptr,
            .loc = ptr.loc(),
        } });
    }

    /// Insert a close annotation (before release)
    fn insertClose(self: *Self, ptr: *ast.Expr) Error!void {
        try self.annotations.append(.{ .close = .{
            .ptr = ptr,
            .loc = ptr.loc(),
        } });
    }

    /// Release if expression evaluates to a heap-allocated type
    fn releaseIfHeapAllocated(self: *Self, expr: *ast.Expr) Error!void {
        if (expr.getType()) |ty| {
            if (self.needsARC(ty)) {
                try self.insertRelease(expr);
            }
        }
    }

    /// Bind pattern variables from a match pattern
    fn bindPatternVars(self: *Self, pattern: ast.Pattern) Error!void {
        _ = self;
        _ = pattern;
        // TODO: Extract variable names from patterns and track them
    }

    /// Get all generated annotations
    pub fn getAnnotations(self: *Self) []const ARCAnnotation {
        return self.annotations.items;
    }

    /// Get all cycle collection candidates
    pub fn getCycleCandidates(self: *Self) []const *ast.Expr {
        return self.cycle_candidates.items;
    }
};

/// Integration with the compiler pipeline
pub fn runARCPass(
    allocator: Allocator,
    module: *ast.Module,
) !ARCPass {
    var arc_pass = ARCPass.init(allocator);
    errdefer arc_pass.deinit();

    try arc_pass.run(module);

    return arc_pass;
}
