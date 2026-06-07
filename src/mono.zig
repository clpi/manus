const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;

/// Specialization key: generic function ID + type arguments hash
pub const SpecKey = struct {
    generic_id: u64,
    type_args_hash: u64,

    pub fn hash(self: SpecKey) u64 {
        return std.hash.Crc32.hash(&std.mem.toBytes(self));
    }

    pub fn eql(self: SpecKey, other: SpecKey) bool {
        return self.generic_id == other.generic_id and
            self.type_args_hash == other.type_args_hash;
    }
};

pub const SpecKeyContext = struct {
    pub fn hash(self: @This(), s: SpecKey) u64 {
        _ = self;
        return s.hash();
    }

    pub fn eql(self: @This(), a: SpecKey, b: SpecKey) bool {
        _ = self;
        return a.eql(b);
    }
};

/// A request to specialize a generic function
pub const SpecRequest = struct {
    generic_decl: *ast.FuncDecl,
    type_args: []const *types.ResolvedType,
    specialization_key: SpecKey,
    mangled_name: []const u8,
};

/// Represents a specialized (monomorphized) function
pub const Specialization = struct {
    request: SpecRequest,
    specialized_body: *ast.FuncBody,
    /// Type parameter substitutions: param_name -> concrete_type
    substitutions: std.StringHashMap(*types.ResolvedType),
};

/// Monomorphizer state
pub const Monomorphizer = struct {
    allocator: Allocator,

    /// Cache of already-specialized functions: SpecKey -> Specialization
    specializations: AutoHashMap(SpecKey, *Specialization),

    /// Work queue of pending specialization requests
    pending: std.ArrayList(SpecRequest),

    /// Map from original generic function to its specializations
    generic_specs: AutoHashMap(*ast.FuncDecl, std.ArrayList(SpecKey)),

    /// Name mangling counter for unique specialization names
    name_counter: u64,

    const Self = @This();
    const Error = error{OutOfMemory} || ast.Error;

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .specializations = AutoHashMap(SpecKey, *Specialization).init(allocator),
            .pending = std.ArrayList(SpecRequest).init(allocator),
            .generic_specs = AutoHashMap(*ast.FuncDecl, std.ArrayList(SpecKey)).init(allocator),
            .name_counter = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up all specializations
        var spec_iter = self.specializations.valueIterator();
        while (spec_iter.next()) |spec_ptr| {
            const spec = spec_ptr.*;
            spec.substitutions.deinit();
            self.allocator.destroy(spec);
        }

        // Clean up generic spec lists
        var generic_iter = self.generic_specs.valueIterator();
        while (generic_iter.next()) |list| {
            list.deinit();
        }

        self.specializations.deinit();
        self.pending.deinit();
        self.generic_specs.deinit();
    }

    /// Request a specialization of a generic function with concrete type arguments
    pub fn requestSpecialization(
        self: *Self,
        generic_decl: *ast.FuncDecl,
        type_args: []const *types.ResolvedType,
    ) Error![]const u8 {
        // Compute hash of type arguments
        const type_args_hash = self.hashTypeArgs(type_args);
        const key = SpecKey{
            .generic_id = @intFromPtr(generic_decl),
            .type_args_hash = type_args_hash,
        };

        // Check if already specialized
        if (self.specializations.get(key)) |existing| {
            return existing.request.mangled_name;
        }

        // Generate mangled name
        const mangled_name = try self.mangleName(generic_decl, type_args);

        // Create request
        const request = SpecRequest{
            .generic_decl = generic_decl,
            .type_args = try self.allocator.dupe(*types.ResolvedType, type_args),
            .specialization_key = key,
            .mangled_name = mangled_name,
        };

        // Add to pending queue
        try self.pending.append(request);

        // Track that this generic has this specialization
        const gop = try self.generic_specs.getOrPut(generic_decl);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayList(SpecKey).init(self.allocator);
        }
        try gop.value_ptr.append(key);

        return mangled_name;
    }

    /// Process all pending specialization requests until fixed point
    pub fn monomorphize(self: *Self, module: *ast.Module) Error!void {
        // First pass: collect all instantiation sites from the typed AST
        try self.collectInstantiationSites(module);

        // Process work queue iteratively (fixed-point iteration)
        while (self.pending.items.len > 0) {
            const request = self.pending.pop();
            try self.specialize(request);
        }
    }

    /// Collect all generic instantiation sites from the module
    fn collectInstantiationSites(self: *Self, module: *ast.Module) Error!void {
        for (module.top_level.items) |decl| {
            switch (decl.*) {
                .func => |func_decl| {
                    try self.collectInFunc(&func_decl.func);
                },
                .enum_def => |enum_def| {
                    try self.collectInEnum(enum_def);
                },
                else => {},
            }
        }
    }

    /// Collect instantiation sites within a function
    fn collectInFunc(self: *Self, func: *ast.FuncDecl) Error!void {
        if (func.body) |body| {
            try self.collectInStmt(body.body);
        }
    }

    /// NOTE: `collectInStruct` was removed. Duo has no `struct` keyword —
    /// record types are declared as inline type-literal annotations on
    /// bindings and on parameters. The monomorphizer reaches the relevant
    /// call sites through `collectInStmt` (which walks the function body
    /// and visits every parameter/argument expression).

    /// Collect instantiation sites within an enum definition
    fn collectInEnum(self: *Self, enum_def: *ast.EnumDef) Error!void {
        for (enum_def.methods.items) |method| {
            try self.collectInFunc(method);
        }
    }

    /// Collect instantiation sites within a statement
    fn collectInStmt(self: *Self, stmt: *ast.Stmt) Error!void {
        switch (stmt.*) {
            .expr_stmt => |expr| try self.collectInExpr(expr.expr),
            .decl => |decl| {
                if (decl.init) |init_expr| {
                    try self.collectInExpr(init_expr);
                }
            },
            .assign => |assign| try self.collectInExpr(assign.rhs),
            .compound_assign => |ca| try self.collectInExpr(ca.rhs),
            .if_stmt => |if_stmt| {
                try self.collectInExpr(if_stmt.cond);
                try self.collectInStmt(if_stmt.then_body);
                if (if_stmt.else_body) |else_body| {
                    try self.collectInStmt(else_body);
                }
            },
            .while_stmt => |while_stmt| {
                try self.collectInExpr(while_stmt.cond);
                try self.collectInStmt(while_stmt.body);
            },
            .for_stmt => |for_stmt| {
                try self.collectInExpr(for_stmt.iter);
                try self.collectInStmt(for_stmt.body);
            },
            .do_stmt => |do_stmt| {
                try self.collectInStmt(do_stmt.body);
                try self.collectInExpr(do_stmt.cond);
            },
            .repeat_stmt => |repeat_stmt| {
                try self.collectInExpr(repeat_stmt.count);
                try self.collectInStmt(repeat_stmt.body);
            },
            .local => |local| {
                if (local.init) |init_expr| {
                    try self.collectInExpr(init_expr);
                }
            },
            .ret => |ret| {
                if (ret.val) |val| {
                    try self.collectInExpr(val);
                }
            },
            .block => |block| {
                for (block.stmts.items) |s| {
                    try self.collectInStmt(s);
                }
            },
            .match_stmt => |match_stmt| {
                try self.collectInExpr(match_stmt.expr);
                for (match_stmt.arms) |arm| {
                    try self.collectInExpr(arm.body);
                    if (arm.guard) |guard| {
                        try self.collectInExpr(guard);
                    }
                }
            },
            .try_stmt => |try_stmt| {
                try self.collectInStmt(try_stmt.block);
                for (try_stmt.catches) |catch_clause| {
                    try self.collectInStmt(catch_clause.body);
                }
            },
            .defer_stmt => |defer_stmt| {
                try self.collectInStmt(defer_stmt.body);
            },
            else => {},
        }
    }

    /// Collect instantiation sites within an expression
    fn collectInExpr(self: *Self, expr: *ast.Expr) Error!void {
        switch (expr.*) {
            .call => |call| {
                try self.collectInExpr(call.func);
                for (call.args.items) |arg| {
                    try self.collectInExpr(arg);
                }

                // Check if this is a generic function call
                if (call.generic_inst) |inst| {
                    try self.handleGenericInstantiation(call.func, inst.type_args);
                }
            },
            .index => |index| {
                try self.collectInExpr(index.obj);
                try self.collectInExpr(index.key);
            },
            .field => |field| try self.collectInExpr(field.obj),
            .bin_op => |bin_op| {
                try self.collectInExpr(bin_op.lhs);
                try self.collectInExpr(bin_op.rhs);
            },
            .un_op => |un_op| try self.collectInExpr(un_op.expr),
            .paren => |paren| try self.collectInExpr(paren.expr),
            .table => |table| {
                for (table.fields.items) |field| {
                    try self.collectInExpr(field.val);
                }
            },
            .array => |array| {
                for (array.elems.items) |elem| {
                    try self.collectInExpr(elem);
                }
            },
            .lambda => |lambda| {
                if (lambda.body) |body| {
                    try self.collectInStmt(body.body);
                }
            },
            .match_expr => |match_expr| {
                try self.collectInExpr(match_expr.expr);
                for (match_expr.arms) |arm| {
                    try self.collectInExpr(arm.body);
                    if (arm.guard) |guard| {
                        try self.collectInExpr(guard);
                    }
                }
            },
            .try_expr => |try_expr| try self.collectInExpr(try_expr.expr),
            .unwrap_expr => |unwrap_expr| try self.collectInExpr(unwrap_expr.expr),
            .await_expr => |await_expr| try self.collectInExpr(await_expr.expr),
            .contains_expr => |contains_expr| {
                try self.collectInExpr(contains_expr.lhs);
                try self.collectInExpr(contains_expr.rhs);
            },
            else => {},
        }
    }

    /// Handle a generic function instantiation
    fn handleGenericInstantiation(
        self: *Self,
        func_expr: *ast.Expr,
        type_args: []const *types.ResolvedType,
    ) Error!void {
        // Get the generic function declaration from the expression
        const generic_decl = self.getGenericDecl(func_expr) orelse return;

        // Request specialization
        _ = try self.requestSpecialization(generic_decl, type_args);
    }

    /// Extract generic function declaration from a call expression
    fn getGenericDecl(self: *Self, func_expr: *ast.Expr) ?*ast.FuncDecl {
        _ = self;
        switch (func_expr.*) {
            .ident => |ident| {
                // Look up the identifier to find if it refers to a generic function
                // This would need access to the symbol table/semantic analysis results
                // For now, simplified: check if the ident has generic info attached
                if (ident.resolved_decl) |decl| {
                    switch (decl.*) {
                        .func => |*func_decl| {
                            if (func_decl.generic_params.items.len > 0) {
                                return func_decl;
                            }
                        },
                        else => {},
                    }
                }
                return null;
            },
            .field => |field| {
                // Method call like obj.method() - check if method is generic
                if (field.method_decl) |method_decl| {
                    if (method_decl.generic_params.items.len > 0) {
                        return method_decl;
                    }
                }
                return null;
            },
            else => return null,
        }
    }

    /// Create a specialized version of a generic function
    fn specialize(self: *Self, request: SpecRequest) Error!void {
        const generic_decl = request.generic_decl;

        // Create substitution map: type param name -> concrete type
        var substitutions = std.StringHashMap(*types.ResolvedType).init(self.allocator);

        for (generic_decl.generic_params.items, request.type_args) |param, ty| {
            try substitutions.put(param.name, ty);
        }

        // Clone and specialize the function body
        const specialized_body = try self.specializeBody(
            generic_decl.body.?,
            &substitutions,
        );

        // Create the specialization record
        const spec = try self.allocator.create(Specialization);
        spec.* = .{
            .request = request,
            .specialized_body = specialized_body,
            .substitutions = substitutions,
        };

        // Store in cache
        try self.specializations.put(request.specialization_key, spec);

        // Scan specialized body for new instantiation sites
        try self.collectNewInstantiationSites(specialized_body);
    }

    /// Clone and specialize a function body
    fn specializeBody(
        self: *Self,
        original: *ast.FuncBody,
        substitutions: *std.StringHashMap(*types.ResolvedType),
    ) Error!*ast.FuncBody {
        // Deep clone the body and replace type references
        const cloned = try self.allocator.create(ast.FuncBody);
        cloned.* = .{
            .body = try self.specializeStmt(original.body, substitutions),
            .is_expr = original.is_expr,
        };
        return cloned;
    }

    /// Specialize a statement by cloning and replacing type references
    fn specializeStmt(
        self: *Self,
        stmt: *ast.Stmt,
        substitutions: *std.StringHashMap(*types.ResolvedType),
    ) Error!*ast.Stmt {
        _ = substitutions;

        // Deep clone statement
        // This is a simplified version - full implementation would:
        // 1. Clone all child nodes
        // 2. Replace type parameter references with concrete types
        // 3. Update any type annotations

        const cloned = try self.allocator.create(ast.Stmt);
        cloned.* = stmt.*; // Shallow copy - full impl needs deep clone

        return cloned;
    }

    /// Scan specialized body for new generic instantiation sites
    fn collectNewInstantiationSites(self: *Self, body: *ast.FuncBody) Error!void {
        try self.collectInStmt(body.body);
    }

    /// Get all specializations for a given generic function
    pub fn getSpecializations(self: *Self, generic_decl: *ast.FuncDecl) ?[]const SpecKey {
        if (self.generic_specs.get(generic_decl)) |list| {
            return list.items;
        }
        return null;
    }

    /// Get a specific specialization by key
    pub fn getSpecialization(self: *Self, key: SpecKey) ?*Specialization {
        return self.specializations.get(key);
    }

    /// Generate a unique mangled name for a specialization
    fn mangleName(
        self: *Self,
        generic_decl: *ast.FuncDecl,
        type_args: []const *types.ResolvedType,
    ) Error![]const u8 {
        self.name_counter += 1;

        var buf: std.ArrayList(u8) = .init(self.allocator);
        defer buf.deinit();

        // Base name
        const base_name = generic_decl.name;
        try buf.appendSlice("duo_");
        try buf.appendSlice(base_name);

        // Add type argument names
        for (type_args) |ty| {
            try buf.append('_');
            try self.appendTypeName(&buf, ty);
        }

        // Ensure uniqueness
        try buf.append('_');
        try std.fmt.format(buf.writer(), "{d}", .{self.name_counter});

        return buf.toOwnedSlice();
    }

    /// Append a type's name to a buffer for mangling
    fn appendTypeName(self: *Self, buf: *std.ArrayList(u8), ty: *types.ResolvedType) Error!void {
        _ = self;
        switch (ty.*) {
            .i64 => try buf.appendSlice("i64"),
            .f64 => try buf.appendSlice("f64"),
            .bool => try buf.appendSlice("bool"),
            .str => try buf.appendSlice("str"),
            .table => |tbl| {
                try buf.appendSlice("tbl_");
                if (tbl.key) |key| {
                    // Simplified: just use type tag
                    _ = key;
                    try buf.appendSlice("kv");
                }
            },
            .user => |user| {
                try buf.appendSlice(user.name);
            },
            .generic_param => |gp| {
                try buf.appendSlice(gp.name);
            },
            .instantiated => |inst| {
                try buf.appendSlice("inst_");
                try buf.appendSlice(inst.base.user.name);
            },
            else => try buf.appendSlice("unknown"),
        }
    }

    /// Hash a list of types for use in specialization key
    fn hashTypeArgs(self: *Self, type_args: []const *types.ResolvedType) u64 {
        _ = self;
        var hasher = std.hash.XxHash3.init(0);
        for (type_args) |ty| {
            const tag = @intFromEnum(ty.*);
            hasher.update(std.mem.asBytes(&tag));
            // TODO: Include type-specific data in hash
        }
        return hasher.final();
    }
};

/// Integration with the compiler pipeline
pub fn monomorphizeModule(
    allocator: Allocator,
    module: *ast.Module,
) !Monomorphizer {
    var mono = Monomorphizer.init(allocator);
    errdefer mono.deinit();

    try mono.monomorphize(module);

    return mono;
}
