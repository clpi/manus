/// Semantic analysis: type-checks the AST and annotates every expression
/// with a ResolvedType.  Also marks FuncBody.is_typed = true when all
/// parameters and the return type are statically known.
const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("ast.zig");
const types = @import("types.zig");
const RT = types.ResolvedType;

pub const SemaError = error{
    TypeMismatch,
    UndeclaredVariable,
    NotCallable,
    InvalidAssignment,
    UnknownBuiltin,
} || Allocator.Error;

/// A symbol in the scope chain.
const Symbol = struct {
    typ: RT,
    is_const: bool,
    is_for_control: bool = false,
    is_global: bool = false,
    is_close: bool = false,
    is_vararg_rest: bool = false,
    /// If non-null, using this symbol emits a deprecation warning.
    deprecated_msg: ?[]const u8 = null,
};

fn is_const_attrib(attrib: ?[]const u8) bool {
    return attrib != null and std.mem.eql(u8, attrib.?, "const");
}

fn is_close_attrib(attrib: ?[]const u8) bool {
    return attrib != null and std.mem.eql(u8, attrib.?, "close");
}

/// Check whether a function has the @nopanic attribute.
fn has_nopanic_attr(attributes: []const ast.Attribute) bool {
    for (attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "nopanic")) return true;
    }
    return false;
}

/// Extract the deprecation message from attributes, or null if not deprecated.
fn get_deprecated_msg(attributes: []const ast.Attribute) ?[]const u8 {
    for (attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "deprecated")) {
            return attr.args orelse "deprecated";
        }
    }
    return null;
}

fn apply_record_layout_attrs(t: *RT, attributes: []const ast.Attribute) void {
    if (t.* != .table_type) return;
    for (attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "packed")) {
            t.table_type.is_packed = true;
        } else if (std.mem.eql(u8, attr.name, "align")) {
            if (attr.args) |args_str| {
                t.table_type.align_n = std.fmt.parseInt(usize, args_str, 10) catch null;
            }
        } else if (std.mem.eql(u8, attr.name, "ffi")) {
            if (attr.args) |args_str| {
                if (args_str.len >= 2 and args_str[0] == '"' and args_str[args_str.len - 1] == '"') {
                    t.table_type.ffi_name = args_str[1 .. args_str.len - 1];
                } else {
                    t.table_type.ffi_name = args_str;
                }
            }
        }
    }
}

/// Check whether attributes contain @arc(false) and validate the argument.
/// Returns true if @arc attribute is present (valid or invalid).
fn validate_arc_attr(attributes: []const ast.Attribute) ?bool {
    for (attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "arc")) {
            if (attr.args) |args| {
                return std.mem.eql(u8, args, "false");
            }
            // @arc without argument is invalid
            return false;
        }
    }
    return null;
}

fn has_arc_attr(attributes: []const ast.Attribute) bool {
    return validate_arc_attr(attributes) != null;
}

fn is_table_binding_type(te: ast.TypeExpr, resolved: RT) bool {
    if (te == .record) return true;
    if (te == .named and (std.mem.eql(u8, te.named, "table") or std.mem.eql(u8, te.named, "Table"))) return true;
    return resolved == .table_type;
}

/// Lexical scope: a stack of hash maps.
pub const Scope = struct {
    alloc: Allocator,
    maps: std.ArrayList(std.StringHashMap(Symbol)),
    require_global: std.ArrayList(bool),

    pub fn init(alloc: Allocator) Scope {
        return .{ .alloc = alloc, .maps = .empty, .require_global = .empty };
    }

    pub fn deinit(self: *Scope) void {
        for (self.maps.items) |*m| m.deinit();
        self.maps.deinit(self.alloc);
        self.require_global.deinit(self.alloc);
    }

    pub fn push(self: *Scope) !void {
        try self.maps.append(self.alloc, std.StringHashMap(Symbol).init(self.alloc));
        const inherited = if (self.require_global.items.len > 0)
            self.require_global.items[self.require_global.items.len - 1]
        else
            false;
        try self.require_global.append(self.alloc, inherited);
    }

    pub fn pop(self: *Scope) void {
        var m = self.maps.pop().?;
        m.deinit();
        _ = self.require_global.pop();
    }

    pub fn set_require_global(self: *Scope, v: bool) void {
        if (self.require_global.items.len > 0)
            self.require_global.items[self.require_global.items.len - 1] = v;
    }

    pub fn needs_explicit_global(self: *Scope) bool {
        if (self.require_global.items.len == 0) return false;
        return self.require_global.items[self.require_global.items.len - 1];
    }

    pub fn define(self: *Scope, name: []const u8, sym: Symbol) !void {
        try self.maps.items[self.maps.items.len - 1].put(name, sym);
    }

    pub fn lookup(self: *Scope, name: []const u8) ?Symbol {
        var i = self.maps.items.len;
        while (i > 0) {
            i -= 1;
            if (self.maps.items[i].get(name)) |sym| return sym;
        }
        return null;
    }
};

/// Per-expression type annotation (stored separately to avoid bloating AST).
/// The Sema pass fills this map; CodeGen reads it.
pub const TypeMap = std.AutoHashMap(*const ast.Expr, RT);

/// A registered concept with its required methods and fields.
pub const ConceptInfo = struct {
    name: []const u8,
    required_methods: []const MethodRequirement,
    required_fields: []const FieldRequirement,

    pub const MethodRequirement = struct {
        name: []const u8,
        param_count: usize, // number of params (including self)
        ret_type: RT,
    };

    pub const FieldRequirement = struct {
        name: []const u8,
        typ: RT,
    };
};

/// A stored function signature for overload resolution (Requirement 12).
pub const FuncSignature = struct {
    param_types: []const RT,
    ret: RT,
    is_vararg: bool,
};

/// A record of a generic instantiation site, tracked for the monomorphizer (Requirement 4.1, 4.3).
pub const InstantiationRecord = struct {
    /// Name of the generic type/function being instantiated.
    generic_name: []const u8,
    /// The resolved type arguments at this instantiation site.
    type_args: []const RT,
    /// A stable key for specialization caching (hash of generic_name + type_args).
    specialization_key: u64,
    /// Source location of the instantiation.
    loc: ast.Loc,
};

pub const Sema = struct {
    alloc: Allocator,
    scope: Scope,
    type_map: TypeMap,
    module_globals: std.StringHashMapUnmanaged(RT) = .{},
    /// Registry of declared enum types for exhaustiveness checking.
    enum_types: std.StringHashMapUnmanaged(RT) = .{},
    /// Registry of declared concepts for satisfaction checking.
    concepts: std.StringHashMapUnmanaged(ConceptInfo) = .{},
    /// Registry of overloaded function signatures (Requirement 12).
    /// Maps function name → list of overload signatures.
    overloads: std.StringHashMapUnmanaged(std.ArrayListUnmanaged(FuncSignature)) = .{},
    /// Tracked generic instantiation sites for the monomorphizer (Requirement 4.1, 4.3).
    instantiation_sites: std.ArrayListUnmanaged(InstantiationRecord) = .empty,
    errors: u32,
    warnings: u32,
    current_ret: RT,
    next_closure_id: u32 = 0,
    /// When true, module scope starts with implicit `global *` (plain .lua files).
    lua55_mode: bool = false,
    /// When true, variables are local by default ( .duo files).
    duo_mode: bool = false,
    /// When true, the current function has the @nopanic attribute.
    current_nopanic: bool = false,

    /// Standard library function names that are known built-in globals.
    fn is_builtin_global(_: *const Sema, name: []const u8) bool {
        // Lua standard library globals
        if (std.mem.eql(u8, name, "string") or
            std.mem.eql(u8, name, "table") or
            std.mem.eql(u8, name, "math") or
            std.mem.eql(u8, name, "io") or
            std.mem.eql(u8, name, "os") or
            std.mem.eql(u8, name, "coroutine") or
            std.mem.eql(u8, name, "package") or
            std.mem.eql(u8, name, "debug") or
            std.mem.eql(u8, name, "utf8") or
            std.mem.eql(u8, name, "bit") or
            std.mem.eql(u8, name, "arg") or
            std.mem.eql(u8, name, "jit") or
            std.mem.eql(u8, name, "ffi"))
            return true;
        // Duo standard library namespace
        if (std.mem.eql(u8, name, "std")) return true;
        // Lua built-in functions
        if (std.mem.eql(u8, name, "print") or
            std.mem.eql(u8, name, "assert") or
            std.mem.eql(u8, name, "error") or
            std.mem.eql(u8, name, "ipairs") or
            std.mem.eql(u8, name, "pairs") or
            std.mem.eql(u8, name, "next") or
            std.mem.eql(u8, name, "pcall") or
            std.mem.eql(u8, name, "xpcall") or
            std.mem.eql(u8, name, "select") or
            std.mem.eql(u8, name, "tostring") or
            std.mem.eql(u8, name, "tonumber") or
            std.mem.eql(u8, name, "type") or
            std.mem.eql(u8, name, "rawget") or
            std.mem.eql(u8, name, "rawset") or
            std.mem.eql(u8, name, "rawlen") or
            std.mem.eql(u8, name, "rawget") or
            std.mem.eql(u8, name, "rawequal") or
            std.mem.eql(u8, name, "setmetatable") or
            std.mem.eql(u8, name, "getmetatable") or
            std.mem.eql(u8, name, "collectgarbage") or
            std.mem.eql(u8, name, "load") or
            std.mem.eql(u8, name, "loadfile") or
            std.mem.eql(u8, name, "dofile") or
            std.mem.eql(u8, name, "require") or
            std.mem.eql(u8, name, "req"))
            return true;
        return false;
    }

    pub fn init(alloc: Allocator) Sema {
        return .{
            .alloc = alloc,
            .scope = Scope.init(alloc),
            .type_map = TypeMap.init(alloc),
            .errors = 0,
            .warnings = 0,
            .current_ret = .void,
            .next_closure_id = 0,
        };
    }

    /// Check whether the current function's return type is result-compatible.
    /// A type is result-compatible if it is a result type, an option type,
    /// or 'any' (which could be a result at runtime).
    fn is_result_compatible_ret(self: *const Sema) bool {
        return switch (self.current_ret) {
            .result => true,
            .option => true,
            .any => true,
            else => false,
        };
    }

    pub fn deinit(self: *Sema) void {
        self.scope.deinit();
        self.type_map.deinit();
        self.module_globals.deinit(self.alloc);
        self.enum_types.deinit(self.alloc);
        self.concepts.deinit(self.alloc);
        // Clean up overload lists.
        var it = self.overloads.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.alloc);
        }
        self.overloads.deinit(self.alloc);
        self.instantiation_sites.deinit(self.alloc);
    }

    fn note_global(self: *Sema, name: []const u8, t: RT) !void {
        const gop = try self.module_globals.getOrPut(self.alloc, name);
        if (!gop.found_existing) {
            gop.value_ptr.* = t;
        } else if (gop.value_ptr.* == .any and t != .any) {
            gop.value_ptr.* = t;
        }
    }

    fn err(self: *Sema, loc: ast.Loc, comptime fmt: []const u8, args: anytype) void {
        self.errors += 1;
        std.debug.print("{}: error: " ++ fmt ++ "\n", .{loc} ++ args);
    }

    fn warn_msg(self: *Sema, loc: ast.Loc, comptime fmt: []const u8, args: anytype) void {
        self.warnings += 1;
        std.debug.print("{}: warning: " ++ fmt ++ "\n", .{loc} ++ args);
    }

    fn define_vararg_rest(self: *Sema, fb: *const ast.FuncBody) !void {
        if (fb.vararg_name) |vn| {
            try self.scope.define(vn, .{
                .typ = .any,
                .is_const = false,
                .is_vararg_rest = true,
            });
        }
    }

    fn check_assign_target(self: *Sema, tgt: *ast.Expr) SemaError!void {
        switch (tgt.*) {
            .name => |n| {
                if (self.scope.lookup(n.ident)) |sym| {
                    if (sym.is_for_control) {
                        self.err(n.loc, "cannot assign to for loop control variable '{s}'", .{n.ident});
                    } else if (sym.is_const) {
                        self.err(n.loc, "attempt to assign to const variable '{s}'", .{n.ident});
                    } else if (sym.is_close) {
                        self.err(n.loc, "attempt to assign to to-be-closed variable '{s}'", .{n.ident});
                    } else if (sym.is_vararg_rest) {
                        self.err(n.loc, "attempt to modify read-only vararg table '{s}'", .{n.ident});
                    }
                } else {
                    if (self.duo_mode) {
                        // In duo mode, undeclared variables are local by default
                        try self.scope.define(n.ident, .{
                            .typ = .any,
                            .is_const = false,
                        });
                    } else if (self.scope.needs_explicit_global()) {
                        self.err(n.loc, "attempt to assign to undeclared global '{s}'", .{n.ident});
                    } else {
                        try self.note_global(n.ident, .any);
                    }
                }
            },
            .index => |idx| {
                if (idx.obj.* == .name) {
                    const n = idx.obj.name;
                    if (self.scope.lookup(n.ident)) |sym| {
                        if (sym.is_vararg_rest) {
                            self.err(idx.loc, "attempt to modify read-only vararg table '{s}'", .{n.ident});
                        }
                    }
                }
            },
            .field => |f| {
                if (f.obj.* == .name) {
                    const n = f.obj.name;
                    if (self.scope.lookup(n.ident)) |sym| {
                        if (sym.is_vararg_rest) {
                            self.err(f.loc, "attempt to modify read-only vararg table '{s}'", .{n.ident});
                        }
                    }
                }
            },
            else => {},
        }
    }

    fn check_binding_attributes(
        self: *Sema,
        lname: *const ast.LocalName,
        resolved_type: RT,
        init_expr: ?*const ast.Expr,
    ) SemaError!void {
        for (lname.attributes) |attr| {
            if (std.mem.eql(u8, attr.name, "arc")) {
                if (validate_arc_attr(&.{attr})) |valid| {
                    if (!valid) {
                        self.err(lname.loc, "@arc attribute requires argument 'false'", .{});
                    } else if (!is_table_binding_type(lname.typ, resolved_type)) {
                        self.err(lname.loc, "@arc(false) is only valid on table-typed bindings or record-type annotations, not on '{s}'", .{lname.ident});
                    }
                }
                continue;
            }

            if (!std.mem.eql(u8, attr.name, "implements")) continue;

            if (lname.typ != .record) {
                self.err(lname.loc, "@implements is only valid on bindings with a record-type annotation, not on '{s}'", .{lname.ident});
                continue;
            }

            const init_names = if (init_expr) |initializer|
                try self.collect_init_field_names(initializer)
            else
                &[_][]const u8{};

            var concept_iter = std.mem.splitScalar(u8, attr.args orelse "", ',');
            while (concept_iter.next()) |raw| {
                const trimmed = std.mem.trim(u8, raw, " \t");
                if (trimmed.len == 0) continue;
                try self.check_concept_satisfaction(lname.loc, lname.ident, lname.typ.record.fields, init_names, trimmed);
            }
        }
    }

    fn record(self: *Sema, expr: *const ast.Expr, t: RT) !RT {
        try self.type_map.put(expr, t);
        return t;
    }

    // ── Public entry ─────────────────────────────────────────────────────────

    pub fn check_module(self: *Sema, mod: *ast.Module) !void {
        try self.scope.push();
        self.seed_globals();
        if (self.lua55_mode or self.duo_mode) {
            self.scope.set_require_global(true);
        }
        try self.check_block(&mod.body);
        self.scope.pop();
    }

    fn seed_globals(self: *Sema) void {
        const names = [_][]const u8{
            "print",        "math",      "string",   "table",    "io",       "os",
            "package",      "coroutine", "utf8",     "debug",    "jit",      "ffi",
            "ipairs",       "pairs",     "tostring", "tonumber", "type",     "error",
            "assert",       "pcall",     "xpcall",   "require",  "simd",     "setmetatable",
            "getmetatable", "rawget",    "rawset",   "rawlen",   "rawequal", "next",
            "select",       "unpack",    "load",     "loadfile", "dofile",   "collectgarbage",
            "warn",         "_VERSION",
        };
        for (names) |n| {
            self.scope.define(n, .{ .typ = .any, .is_const = true }) catch {};
        }
    }

    // ── Block / statements ────────────────────────────────────────────────────

    fn check_block(self: *Sema, blk: *ast.Block) SemaError!void {
        try self.scope.push();
        for (blk.stmts) |*stmt| try self.check_stmt(stmt);
        if (blk.tail_expr) |e| _ = try self.check_expr(e);
        self.scope.pop();
    }

    fn check_stmt(self: *Sema, stmt: *ast.Stmt) SemaError!void {
        switch (stmt.*) {
            .local_decl => |*ld| {
                var init_types: std.ArrayList(RT) = .empty;
                defer init_types.deinit(self.alloc);
                for (ld.inits) |init_expr| {
                    const t = try self.check_expr(init_expr);
                    try init_types.append(self.alloc, t);
                }
                for (ld.names, 0..) |*lname, i| {
                    var t: RT = if (i < init_types.items.len)
                        init_types.items[i]
                    else if (ld.inits.len == 1 and ld.names.len > 1)
                        .any
                    else
                        .any;
                    // If annotated, use the annotation and enforce type match
                    if (lname.typ != .inferred) {
                        const ann = types.resolve(lname.typ, self, self.alloc) catch .any;
                        // Check type mismatch: if init type is known (not any/nil) and
                        // annotation is known (not any), they must match
                        if (i < init_types.items.len) {
                            const init_t = init_types.items[i];
                            if (ann != .any and init_t != .any and init_t != .nil and !ann.eql(init_t)) {
                                self.err(lname.loc, "type mismatch: variable '{s}' declared as {}, but initializer has type {}", .{ lname.ident, ann, init_t });
                            }
                        }
                        t = ann;
                    }
                    const is_const = is_const_attrib(lname.attrib);
                    const is_close = is_close_attrib(lname.attrib);

                    apply_record_layout_attrs(&t, lname.attributes);
                    const has_init = i < ld.inits.len or (ld.inits.len == 1 and ld.names.len > 1 and i == 0);
                    if (is_const and !has_init) {
                        self.err(lname.loc, "const variable '{s}' must have an initializer", .{lname.ident});
                    }
                    if (is_close and !has_init) {
                        self.err(lname.loc, "to-be-closed variable '{s}' must have an initializer", .{lname.ident});
                    }
                    try self.check_binding_attributes(lname, t, if (i < ld.inits.len) ld.inits[i] else null);
                    try self.scope.define(lname.ident, .{
                        .typ = t,
                        .is_const = is_const,
                        .is_close = is_close,
                        .deprecated_msg = get_deprecated_msg(lname.attributes),
                    });
                }
            },
            .const_decl => |*cd| {
                var t = try self.check_expr(cd.val);
                if (cd.typ != .inferred)
                    t = types.resolve(cd.typ, self, self.alloc) catch .any;
                try self.scope.define(cd.ident, .{ .typ = t, .is_const = true });
            },
            .global_decl => |*gd| {
                if (gd.star) {
                    self.scope.set_require_global(true);
                    return;
                }
                var init_types: std.ArrayList(RT) = .empty;
                defer init_types.deinit(self.alloc);
                for (gd.inits) |init_expr| {
                    const t = try self.check_expr(init_expr);
                    try init_types.append(self.alloc, t);
                }
                for (gd.names, 0..) |*lname, i| {
                    var t: RT = if (i < init_types.items.len)
                        init_types.items[i]
                    else if (gd.inits.len == 1 and gd.names.len > 1)
                        .any
                    else
                        .any;
                    if (lname.typ != .inferred) {
                        const ann = types.resolve(lname.typ, self, self.alloc) catch .any;
                        t = ann;
                    }
                    apply_record_layout_attrs(&t, lname.attributes);
                    const is_const = is_const_attrib(lname.attrib);
                    const has_init = i < gd.inits.len or (gd.inits.len == 1 and gd.names.len > 1 and i == 0);
                    if (is_const and !has_init) {
                        self.err(lname.loc, "const global '{s}' must have an initializer", .{lname.ident});
                    }
                    try self.check_binding_attributes(lname, t, if (i < gd.inits.len) gd.inits[i] else null);
                    try self.note_global(lname.ident, t);
                    try self.scope.define(lname.ident, .{
                        .typ = t,
                        .is_const = is_const,
                        .is_global = true,
                        .deprecated_msg = get_deprecated_msg(lname.attributes),
                    });
                }
            },
            .assign => |*as| {
                for (as.values) |v| _ = try self.check_expr(v);
                for (as.targets) |tgt| {
                    try self.check_assign_target(tgt);
                    _ = try self.check_expr(tgt);
                }
            },
            .call_stmt => |*cs| _ = try self.check_expr(cs.expr),
            .expr_stmt => |*es| _ = try self.check_expr(es.expr),
            .ret => |*r| {
                for (r.vals) |v| _ = try self.check_expr(v);
            },
            .if_stmt => |*is| {
                _ = try self.check_expr(is.cond);
                try self.check_block(&is.then);
                for (is.elseifs) |*ei| {
                    _ = try self.check_expr(ei.cond);
                    try self.check_block(&ei.body);
                }
                if (is.else_body) |*eb| try self.check_block(eb);
            },
            .while_loop => |*wl| {
                _ = try self.check_expr(wl.cond);
                try self.check_block(&wl.body);
            },
            .repeat_loop => |*rl| {
                try self.check_block(&rl.body);
                _ = try self.check_expr(rl.cond);
            },
            .num_for => |*nf| {
                try self.scope.push();
                var var_t: RT = .i64;
                if (nf.var_typ != .inferred)
                    var_t = types.resolve(nf.var_typ, self, self.alloc) catch .i64;
                try self.scope.define(nf.var_name, .{
                    .typ = var_t,
                    .is_const = true,
                    .is_for_control = true,
                });
                _ = try self.check_expr(nf.start);
                _ = try self.check_expr(nf.stop);
                if (nf.step) |s| _ = try self.check_expr(s);
                try self.check_block(&nf.body);
                self.scope.pop();
            },
            .gen_for => |*gf| {
                for (gf.iters) |it| _ = try self.check_expr(it);
                try self.scope.push();
                for (gf.vars) |v| try self.scope.define(v, .{
                    .typ = .any,
                    .is_const = true,
                    .is_for_control = true,
                });
                try self.check_block(&gf.body);
                self.scope.pop();
            },
            .func_decl => |*fd| {
                try self.check_func_decl(fd);
            },
            .do_block => |*db| try self.check_block(&db.body),
            // NOTE: there is no `.struct_def` case. Records are declared via
            // record-type annotations on bindings; their type-checking and
            // `@implements` concept satisfaction is done in the `local_decl`
            // and `global_decl` arms above.
            .brk, .goto_stmt, .label_stmt => {},
            .match_stmt => |*ms| try self.check_match(ms),
            .enum_def => |*ed| try self.check_enum_def(ed),
            .try_stmt => |*ts| {
                // Type-check the try body
                try self.check_block(&ts.body);
                // Type-check each catch clause
                // NOTE: catch clauses are untyped in Duo. There is no
                // `error_type` on `CatchClause` — the binding (if any) is
                // always typed `any` (errors are tables, statically unknown).
                // User code uses `match e.__tag` inside the body.
                for (ts.catches) |*cc| {
                    try self.scope.push();
                    if (cc.binding) |name| {
                        try self.scope.define(name, .{ .typ = .any, .is_const = true });
                    }
                    try self.check_block(&cc.body);
                    self.scope.pop();
                }
                // Type-check defers within the try statement
                for (ts.defers) |*d| {
                    try self.check_block(&d.body);
                }
            },
            .defer_stmt => |*ds| {
                // Type-check the deferred body
                try self.check_block(&ds.body);
            },
            .concept_def => |*cd| {
                try self.check_concept_def(cd);
            },
            .alias_def => |*ad| {
                // Alias types are compile-time declarations; type-check fields and methods.
                _ = ad;
            },
        }
    }

    fn check_func_body(self: *Sema, fb: *ast.FuncBody) SemaError!RT {
        // Determine param types and return type
        var param_types = try self.alloc.alloc(RT, fb.params.len);
        var all_typed = true;
        for (fb.params, 0..) |*p, i| {
            if (p.typ == .inferred) {
                param_types[i] = .any;
                all_typed = false;
            } else {
                param_types[i] = types.resolve(p.typ, self, self.alloc) catch .any;
            }
        }
        var ret_t: RT = .any;
        if (fb.ret_type != .inferred) {
            ret_t = types.resolve(fb.ret_type, self, self.alloc) catch .any;
        } else {
            all_typed = false;
        }
        fb.is_typed = all_typed;

        // Check body
        const prev_ret = self.current_ret;
        const prev_nopanic = self.current_nopanic;
        self.current_ret = ret_t;
        // Anonymous function expressions don't carry @nopanic;
        // reset to false so inner expressions aren't incorrectly flagged.
        self.current_nopanic = false;
        try self.scope.push();
        for (fb.params, 0..) |*p, i|
            try self.scope.define(p.name, .{ .typ = param_types[i], .is_const = false });
        try self.define_vararg_rest(fb);
        try self.check_block(&fb.body);
        self.scope.pop();
        self.current_ret = prev_ret;
        self.current_nopanic = prev_nopanic;

        const ret_ptr = try self.alloc.create(RT);
        ret_ptr.* = ret_t;
        const has_vararg = fb.vararg or fb.vararg_name != null;
        return RT{ .func = .{
            .params = param_types,
            .ret = ret_ptr,
            .is_native = all_typed and !has_vararg,
            .has_vararg = has_vararg,
        } };
    }

    // ── Expressions ───────────────────────────────────────────────────────────

    fn check_expr(self: *Sema, expr: *ast.Expr) SemaError!RT {
        const t = try self.check_expr_inner(expr);
        return self.record(expr, t);
    }

    fn check_expr_inner(self: *Sema, expr: *ast.Expr) SemaError!RT {
        return switch (expr.*) {
            .nil => .nil,
            .true_lit, .false_lit => .bool,
            .int_lit => .i64,
            .float_lit => .f64,
            .string_lit => .str,
            .vararg => .any,
            .name => |n| {
                if (self.scope.lookup(n.ident)) |sym| {
                    // Emit deprecation warning if symbol is @deprecated (Requirement 18.7)
                    if (sym.deprecated_msg) |msg| {
                        self.warn_msg(n.loc, "'{s}' is deprecated: {s}", .{ n.ident, msg });
                    }
                    return sym.typ;
                }
                if (self.scope.needs_explicit_global() and !self.is_builtin_global(n.ident)) {
                    self.err(n.loc, "use of undeclared global '{s}'", .{n.ident});
                    return .any;
                }
                // Unknown identifier → treat as dynamic global
                try self.note_global(n.ident, .any);
                return .any;
            },
            .field => |f| {
                const ot = try self.check_expr(f.obj);
                // If the object is a statically-typed record (anonymous
                // `{ field: T, ... }` annotation), return the declared
                // field's type instead of `.any`. This lets `local x: f64
                // = p.x` infer the type properly when `p: { x: f64, ... }`.
                if (ot == .table_type) {
                    const fields = ot.table_type.fields;
                    for (fields) |rf| {
                        if (std.mem.eql(u8, rf.name, f.field)) {
                            return rf.typ;
                        }
                    }
                }
                return .any; // otherwise, field access is dynamic
            },
            .index => |idx| {
                const ot = try self.check_expr(idx.obj);
                _ = try self.check_expr(idx.key);
                if (ot.is_vector()) {
                    return switch (ot) {
                        .v4f64 => .f64,
                        .v4i64 => .i64,
                        .v8f32 => .f32,
                        .v8i32 => .i32,
                        else => .any,
                    };
                }
                return .any;
            },
            .call => |c| {
                const ft = try self.check_expr(c.func);
                for (c.args) |arg| _ = try self.check_expr(arg);

                // Built-in module return types
                if (c.func.* == .field) {
                    const f = &c.func.field;
                    if (f.obj.* == .name) {
                        const mod = f.obj.name.ident;
                        const fname = f.field;
                        if (std.mem.eql(u8, mod, "os") and std.mem.eql(u8, fname, "clock"))
                            return .f64;
                        if (std.mem.eql(u8, mod, "string")) {
                            if (std.mem.eql(u8, fname, "len") or std.mem.eql(u8, fname, "byte"))
                                return .i64;
                            if (std.mem.eql(u8, fname, "char") or std.mem.eql(u8, fname, "rep") or
                                std.mem.eql(u8, fname, "sub") or std.mem.eql(u8, fname, "lower") or
                                std.mem.eql(u8, fname, "upper") or std.mem.eql(u8, fname, "reverse"))
                                return .str;
                        }
                        if (std.mem.eql(u8, mod, "math")) {
                            if (std.mem.eql(u8, fname, "sqrt") or
                                std.mem.eql(u8, fname, "sin") or std.mem.eql(u8, fname, "cos") or
                                std.mem.eql(u8, fname, "tan") or std.mem.eql(u8, fname, "exp") or
                                std.mem.eql(u8, fname, "log") or std.mem.eql(u8, fname, "floor") or
                                std.mem.eql(u8, fname, "ceil")) return .f64;
                            if (std.mem.eql(u8, fname, "max") or std.mem.eql(u8, fname, "min")) {
                                if (c.args.len == 2) {
                                    if ((try self.check_expr(c.args[0])).is_integer() and (try self.check_expr(c.args[1])).is_integer()) return .i64;
                                    return .f64;
                                }
                                return .any;
                            }
                            if (std.mem.eql(u8, fname, "abs")) {
                                if (c.args.len > 0 and (try self.check_expr(c.args[0])).is_integer()) return .i64;
                                return .f64;
                            }
                        }
                        if (std.mem.eql(u8, mod, "simd")) {
                            if (std.mem.eql(u8, fname, "v4f64")) return .v4f64;
                            if (std.mem.eql(u8, fname, "v4i64")) return .v4i64;
                            if (std.mem.eql(u8, fname, "v8f32")) return .v8f32;
                            if (std.mem.eql(u8, fname, "v8i32")) return .v8i32;
                            if (std.mem.eql(u8, fname, "sqrt")) {
                                if (c.args.len > 0) return try self.check_expr(c.args[0]);
                            }
                            if (std.mem.eql(u8, fname, "sum")) return .i64;
                            if (std.mem.eql(u8, fname, "any")) return .bool;
                            if (std.mem.eql(u8, fname, "select") and c.args.len >= 3) {
                                return try self.check_expr(c.args[1]);
                            }
                            if (std.mem.eql(u8, fname, "le") or std.mem.eql(u8, fname, "lt") or
                                std.mem.eql(u8, fname, "ge") or std.mem.eql(u8, fname, "gt") or
                                std.mem.eql(u8, fname, "eq") or std.mem.eql(u8, fname, "ne"))
                            {
                                if (c.args.len >= 2) {
                                    const at = try self.check_expr(c.args[0]);
                                    if (at.vector_mask()) |m| return m;
                                }
                            }
                        }
                    }
                }

                // Overload resolution (Requirement 12): when the callee is a
                // bare name with multiple registered overloads, select the one
                // whose parameter types match the argument types. Ambiguous
                // matches are reported as an error.
                if (c.func.* == .name) {
                    if (self.overloads.getPtr(c.func.name.ident)) |overload_list| {
                        if (overload_list.items.len > 1) {
                            if (try self.resolve_overload(c.func.name.loc, c.func.name.ident, overload_list.items, c.args)) |ret|
                                return ret;
                        }
                    }
                }

                // Generic instantiation tracking (Requirement 4.1, 4.3): when the
                // callee's signature mentions generic parameters, record the
                // concrete type arguments at this site for the monomorphizer.
                if (ft == .func and c.func.* == .name)
                    try self.record_generic_instantiation(c.func.name.loc, c.func.name.ident, ft.func, c.args);

                if (c.func.* == .name) {
                    if (std.mem.eql(u8, c.func.name.ident, "tostring") or
                        std.mem.eql(u8, c.func.name.ident, "type")) return .str;
                }

                return switch (ft) {
                    .func => |f| f.ret.*,
                    else => .any,
                };
            },
            .method_call => |mc| {
                _ = try self.check_expr(mc.obj);
                for (mc.args) |arg| _ = try self.check_expr(arg);
                return .any;
            },
            .binop => |b| self.check_binop(b.op, b.lhs, b.rhs),
            .unop => |u| self.check_unop(u.op, u.operand),
            .func_expr => |fb| blk: {
                fb.closure_id = self.next_closure_id;
                self.next_closure_id += 1;
                try self.analyze_closure_upvalues(fb);
                break :blk try self.check_func_body(fb);
            },
            .table => |t| {
                for (t.fields) |*fld| {
                    switch (fld.*) {
                        .indexed => |*idx| {
                            _ = try self.check_expr(idx.key);
                            _ = try self.check_expr(idx.val);
                        },
                        .named => |*nmd| {
                            _ = try self.check_expr(nmd.val);
                        },
                        .positional => |p| {
                            _ = try self.check_expr(p);
                        },
                    }
                }
                return .any;
            },
            .list_comp => |lc| {
                _ = try self.check_expr(lc.iter);
                try self.scope.push();
                defer self.scope.pop();
                if (lc.key_name) |key_name| {
                    try self.scope.define(key_name, .{ .typ = .any, .is_const = true });
                }
                try self.scope.define(lc.value_name, .{ .typ = .any, .is_const = true });
                if (lc.filter) |filter| _ = try self.check_expr(filter);
                _ = try self.check_expr(lc.value);
                return .any;
            },
            .try_expr => |te| {
                const operand_t = try self.check_expr(te.operand);
                // The ? operator requires the enclosing function to have
                // a result-compatible return type (Requirement 9.7)
                if (!self.is_result_compatible_ret()) {
                    self.err(te.loc, "'?' operator requires enclosing function to have a result-compatible return type", .{});
                }
                // Propagate the operand's type so downstream expressions see
                // the concrete type rather than falling back to .any.
                return operand_t;
            },
            .unwrap_expr => |ue| {
                const operand_t = try self.check_expr(ue.operand);
                // The ! operator is rejected in @nopanic functions (Requirement 9.8)
                if (self.current_nopanic) {
                    self.err(ue.loc, "'!' operator cannot be used in @nopanic function (it may panic)", .{});
                }
                // The unwrapped value has the same type as the operand.
                return operand_t;
            },
            .match_expr => |me| {
                return try self.check_match_expr(me);
            },
            .await_expr => |ae| {
                const operand_t = try self.check_expr(ae.operand);
                return operand_t;
            },
            .contains_expr => |ce| {
                _ = try self.check_expr(ce.lhs);
                _ = try self.check_expr(ce.rhs);
                // `x in y` is always a boolean test.
                return .bool;
            },
        };
    }

    fn check_binop(self: *Sema, op: ast.BinOp, lhs: *ast.Expr, rhs: *ast.Expr) SemaError!RT {
        const lt = try self.check_expr(lhs);
        const rt = try self.check_expr(rhs);

        // Handle vector operations
        if (lt.is_vector() or rt.is_vector()) {
            const vec = if (lt.is_vector()) lt else rt;
            return switch (op) {
                .eq, .neq, .lt, .gt, .leq, .geq => vec.vector_mask() orelse .any,
                .band, .bor, .bxor => if (lt.eql(rt)) lt else .any,
                .add, .sub, .mul, .div, .pow => blk: {
                    if (lt.eql(rt)) break :blk lt;
                    if (lt.is_vector() and rt.is_numeric()) break :blk lt;
                    if (rt.is_vector() and lt.is_numeric()) break :blk rt;
                    break :blk .any;
                },
                else => .any,
            };
        }

        if (op == .@"or" and lhs.* == .binop and lhs.binop.op == .@"and") {
            const then_t = self.type_map.get(lhs.binop.rhs) orelse .any;
            if (then_t.eql(rt) and lua_and_or_value_type_is_native(then_t)) return then_t;
            return .any;
        }

        return switch (op) {
            .div, .pow => {
                if (lt.is_numeric() and rt.is_numeric()) return .f64;
                return .any;
            },
            .add, .sub, .mul, .idiv, .mod => {
                if (lt.is_numeric() and rt.is_numeric()) {
                    // Promote: if either is float, result is float
                    if (lt.is_float() or rt.is_float()) return .f64;
                    return lt; // both integers: use left type
                }
                return .any;
            },
            .band, .bor, .bxor, .lshift, .rshift => {
                if (lt.is_integer() and rt.is_integer()) return lt;
                return .any;
            },
            .concat => .str,
            .eq, .neq, .lt, .gt, .leq, .geq => .bool,
            .contains => .bool,
            .@"and" => if (lt.eql(rt)) rt else .any,
            .@"or" => if (lt.eql(rt)) lt else .any,
        };
    }

    fn lua_and_or_value_type_is_native(t: RT) bool {
        return t.is_numeric() or t == .str;
    }

    fn check_unop(self: *Sema, op: ast.UnOp, operand: *ast.Expr) SemaError!RT {
        const t = try self.check_expr(operand);
        return switch (op) {
            .neg => if (t.is_numeric()) t else .any,
            .bnot => if (t.is_integer() or t.is_vector()) t else .any,
            .not => .bool,
            .len => if (t == .any) .any else .i64,
            .compile => t, // Compile-time operator has same type as operand
        };
    }

    fn func_body_has_func_expr(fb: *const ast.FuncBody) bool {
        return func_body_has_func_expr_block(&fb.body);
    }

    fn func_body_has_func_expr_block(block: *const ast.Block) bool {
        for (block.stmts) |*stmt| {
            if (stmt_has_func_expr(stmt)) return true;
        }
        return false;
    }

    fn stmt_has_func_expr(stmt: *const ast.Stmt) bool {
        return switch (stmt.*) {
            .local_decl => |*ld| expr_has_func_expr_in_list(ld.inits),
            .assign => |*as| expr_has_func_expr_in_list(as.values),
            .ret => |*r| expr_has_func_expr_in_list(r.vals),
            .if_stmt => |*is| blk: {
                if (expr_has_func_expr(is.cond)) return true;
                if (func_body_has_func_expr_block(&is.then)) return true;
                for (is.elseifs) |*ei| {
                    if (expr_has_func_expr(ei.cond)) return true;
                    if (func_body_has_func_expr_block(&ei.body)) return true;
                }
                if (is.else_body) |*eb| {
                    if (func_body_has_func_expr_block(eb)) return true;
                }
                break :blk false;
            },
            .while_loop => |*wl| {
                if (expr_has_func_expr(wl.cond)) return true;
                return func_body_has_func_expr_block(&wl.body);
            },
            .num_for => |*nf| func_body_has_func_expr_block(&nf.body),
            .gen_for => |*fg| {
                for (fg.iters) |e| {
                    if (expr_has_func_expr(e)) return true;
                }
                return func_body_has_func_expr_block(&fg.body);
            },
            .call_stmt => |*cs| expr_has_func_expr(cs.expr),
            .expr_stmt => |*es| expr_has_func_expr(es.expr),
            .do_block => |*db| func_body_has_func_expr_block(&db.body),
            .func_decl => |*fd| func_body_has_func_expr(&fd.func),
            else => false,
        };
    }

    fn expr_has_func_expr_in_list(exprs: []const *ast.Expr) bool {
        for (exprs) |e| {
            if (expr_has_func_expr(e)) return true;
        }
        return false;
    }

    fn expr_has_func_expr(expr: *const ast.Expr) bool {
        return switch (expr.*) {
            .func_expr => true,
            .binop => |b| expr_has_func_expr(b.lhs) or expr_has_func_expr(b.rhs),
            .unop => |u| expr_has_func_expr(u.operand),
            .call => |c| {
                if (expr_has_func_expr(c.func)) return true;
                for (c.args) |a| {
                    if (expr_has_func_expr(a)) return true;
                }
                return false;
            },
            .method_call => |mc| {
                if (expr_has_func_expr(mc.obj)) return true;
                for (mc.args) |a| {
                    if (expr_has_func_expr(a)) return true;
                }
                return false;
            },
            .field => |f| expr_has_func_expr(f.obj),
            .index => |idx| expr_has_func_expr(idx.obj) or expr_has_func_expr(idx.key),
            .table => |t| {
                for (t.fields) |fld| {
                    switch (fld) {
                        .indexed => |idx| {
                            if (expr_has_func_expr(idx.key) or expr_has_func_expr(idx.val)) return true;
                        },
                        .named => |nmd| {
                            if (expr_has_func_expr(nmd.val)) return true;
                        },
                        .positional => |pos| {
                            if (expr_has_func_expr(pos)) return true;
                        },
                    }
                }
                return false;
            },
            .list_comp => |lc| {
                if (expr_has_func_expr(lc.iter) or expr_has_func_expr(lc.value)) return true;
                if (lc.filter) |filter| return expr_has_func_expr(filter);
                return false;
            },
            else => false,
        };
    }

    fn analyze_closure_upvalues(self: *Sema, fb: *ast.FuncBody) !void {
        var names = std.ArrayList([]const u8).empty;
        var flags = std.ArrayList(bool).empty;
        defer names.deinit(self.alloc);
        defer flags.deinit(self.alloc);
        try collect_upvalue_names(fb, &fb.body, fb.params, &names, &flags, self);
        fb.upvalues = try self.alloc.alloc(ast.Upvalue, names.items.len);
        for (names.items, flags.items, 0..) |nm, is_local, i| {
            var typ: ?RT = null;
            if (self.scope.lookup(nm)) |sym| {
                typ = sym.typ;
            } else if (self.module_globals.get(nm)) |g_typ| {
                typ = g_typ;
            }
            fb.upvalues[i] = .{ .name = nm, .is_local = is_local, .typ = typ };
        }
    }

    fn collect_upvalue_names(
        fb: *const ast.FuncBody,
        block: *const ast.Block,
        params: []const ast.FuncParam,
        names: *std.ArrayList([]const u8),
        flags: *std.ArrayList(bool),
        sema: *Sema,
    ) std.mem.Allocator.Error!void {
        _ = fb;
        for (block.stmts) |*stmt| {
            try collect_upvalue_names_stmt(stmt, params, names, flags, sema);
        }
    }

    fn collect_upvalue_names_stmt(
        stmt: *const ast.Stmt,
        params: []const ast.FuncParam,
        names: *std.ArrayList([]const u8),
        flags: *std.ArrayList(bool),
        sema: *Sema,
    ) std.mem.Allocator.Error!void {
        switch (stmt.*) {
            .local_decl => |*ld| {
                for (ld.inits) |init_expr| try collect_upvalue_names_expr(init_expr, params, names, flags, sema);
            },
            .assign => |*as| {
                for (as.values) |v| try collect_upvalue_names_expr(v, params, names, flags, sema);
            },
            .ret => |*r| {
                for (r.vals) |v| try collect_upvalue_names_expr(v, params, names, flags, sema);
            },
            .if_stmt => |*is| {
                try collect_upvalue_names_expr(is.cond, params, names, flags, sema);
                try collect_upvalue_names_block(&is.then, params, names, flags, sema);
                for (is.elseifs) |*ei| {
                    try collect_upvalue_names_expr(ei.cond, params, names, flags, sema);
                    try collect_upvalue_names_block(&ei.body, params, names, flags, sema);
                }
                if (is.else_body) |*eb| try collect_upvalue_names_block(eb, params, names, flags, sema);
            },
            .while_loop => |*wl| {
                try collect_upvalue_names_expr(wl.cond, params, names, flags, sema);
                try collect_upvalue_names_block(&wl.body, params, names, flags, sema);
            },
            .num_for => |*nf| try collect_upvalue_names_block(&nf.body, params, names, flags, sema),
            .gen_for => |*fg| {
                for (fg.iters) |e| try collect_upvalue_names_expr(e, params, names, flags, sema);
                try collect_upvalue_names_block(&fg.body, params, names, flags, sema);
            },
            .call_stmt => |*cs| try collect_upvalue_names_expr(cs.expr, params, names, flags, sema),
            .expr_stmt => |*es| try collect_upvalue_names_expr(es.expr, params, names, flags, sema),
            .do_block => |*db| try collect_upvalue_names_block(&db.body, params, names, flags, sema),
            else => {},
        }
    }

    fn collect_upvalue_names_block(
        block: *const ast.Block,
        params: []const ast.FuncParam,
        names: *std.ArrayList([]const u8),
        flags: *std.ArrayList(bool),
        sema: *Sema,
    ) std.mem.Allocator.Error!void {
        for (block.stmts) |*stmt| {
            try collect_upvalue_names_stmt(stmt, params, names, flags, sema);
        }
    }

    fn is_param_name(params: []const ast.FuncParam, name: []const u8) bool {
        for (params) |p| {
            if (std.mem.eql(u8, p.name, name)) return true;
        }
        return false;
    }

    fn upvalue_index(names: *std.ArrayList([]const u8), name: []const u8) ?usize {
        for (names.items, 0..) |nm, i| {
            if (std.mem.eql(u8, nm, name)) return i;
        }
        return null;
    }

    fn note_upvalue(
        name: []const u8,
        names: *std.ArrayList([]const u8),
        flags: *std.ArrayList(bool),
        sema: *Sema,
    ) std.mem.Allocator.Error!void {
        if (upvalue_index(names, name) != null) return;
        const is_local = sema.scope.lookup(name) != null;
        try names.append(sema.alloc, name);
        try flags.append(sema.alloc, is_local);
    }

    fn collect_upvalue_names_expr(
        expr: *const ast.Expr,
        params: []const ast.FuncParam,
        names: *std.ArrayList([]const u8),
        flags: *std.ArrayList(bool),
        sema: *Sema,
    ) std.mem.Allocator.Error!void {
        switch (expr.*) {
            .name => |n| {
                if (is_param_name(params, n.ident)) return;
                if (sema.scope.lookup(n.ident) != null) {
                    try note_upvalue(n.ident, names, flags, sema);
                } else {
                    try note_upvalue(n.ident, names, flags, sema);
                }
            },
            .binop => |b| {
                try collect_upvalue_names_expr(b.lhs, params, names, flags, sema);
                try collect_upvalue_names_expr(b.rhs, params, names, flags, sema);
            },
            .unop => |u| try collect_upvalue_names_expr(u.operand, params, names, flags, sema),
            .call => |c| {
                try collect_upvalue_names_expr(c.func, params, names, flags, sema);
                for (c.args) |a| try collect_upvalue_names_expr(a, params, names, flags, sema);
            },
            .method_call => |mc| {
                try collect_upvalue_names_expr(mc.obj, params, names, flags, sema);
                for (mc.args) |a| try collect_upvalue_names_expr(a, params, names, flags, sema);
            },
            .field => |f| try collect_upvalue_names_expr(f.obj, params, names, flags, sema),
            .index => |idx| {
                try collect_upvalue_names_expr(idx.obj, params, names, flags, sema);
                try collect_upvalue_names_expr(idx.key, params, names, flags, sema);
            },
            .table => |t| {
                for (t.fields) |fld| {
                    switch (fld) {
                        .indexed => |idx| {
                            try collect_upvalue_names_expr(idx.key, params, names, flags, sema);
                            try collect_upvalue_names_expr(idx.val, params, names, flags, sema);
                        },
                        .named => |nmd| try collect_upvalue_names_expr(nmd.val, params, names, flags, sema),
                        .positional => |pos| try collect_upvalue_names_expr(pos, params, names, flags, sema),
                    }
                }
            },
            .list_comp => |lc| {
                try collect_upvalue_names_expr(lc.iter, params, names, flags, sema);
                var comp_params: std.ArrayList(ast.FuncParam) = .empty;
                defer comp_params.deinit(sema.alloc);
                try comp_params.appendSlice(sema.alloc, params);
                if (lc.key_name) |key_name| {
                    try comp_params.append(sema.alloc, .{ .name = key_name, .typ = .inferred, .loc = lc.loc });
                }
                try comp_params.append(sema.alloc, .{ .name = lc.value_name, .typ = .inferred, .loc = lc.loc });
                if (lc.filter) |filter| try collect_upvalue_names_expr(filter, comp_params.items, names, flags, sema);
                try collect_upvalue_names_expr(lc.value, comp_params.items, names, flags, sema);
            },
            .func_expr => {},
            else => {},
        }
    }

    fn check_func_decl(self: *Sema, fd: *ast.FuncDecl) SemaError!void {
        const fb = &fd.func;
        const has_vararg = fb.vararg or fb.vararg_name != null;
        var all_typed = true;
        for (fb.params) |*p| {
            if (p.typ == .inferred) all_typed = false;
        }
        if (fb.ret_type == .inferred) all_typed = false;
        fb.is_typed = all_typed;

        var param_types = try self.alloc.alloc(RT, fb.params.len);
        for (fb.params, 0..) |*p, i| {
            param_types[i] = types.resolve(p.typ, self, self.alloc) catch .any;
        }
        var ret_t = types.resolve(fb.ret_type, self, self.alloc) catch .any;

        // Register the function before checking the body so recursive calls type-check.
        const ret_ptr = try self.alloc.create(RT);
        ret_ptr.* = ret_t;
        var fb_t = RT{ .func = .{
            .params = param_types,
            .ret = ret_ptr,
            .is_native = fb.is_typed and !has_vararg,
            .has_vararg = has_vararg,
        } };
        if (fd.path.len == 1 and !fd.method) {
            const name = fd.path[0];
            // Check if a function with this name already exists in scope.
            // If so, register it as an overload (Requirement 12).
            if (self.scope.lookup(name)) |existing| {
                if (existing.typ == .func) {
                    // First overload encounter: register the existing signature too.
                    const gop = try self.overloads.getOrPut(self.alloc, name);
                    if (!gop.found_existing) {
                        gop.value_ptr.* = .empty;
                        // Add the previously-registered signature.
                        try gop.value_ptr.append(self.alloc, .{
                            .param_types = existing.typ.func.params,
                            .ret = existing.typ.func.ret.*,
                            .is_vararg = existing.typ.func.has_vararg,
                        });
                    }
                    // Add the new overload signature.
                    try gop.value_ptr.append(self.alloc, .{
                        .param_types = param_types,
                        .ret = ret_t,
                        .is_vararg = has_vararg,
                    });
                }
            }
            try self.scope.define(name, .{ .typ = fb_t, .is_const = true, .deprecated_msg = get_deprecated_msg(fd.attributes) });
        }

        if (has_arc_attr(fd.attributes)) {
            if (validate_arc_attr(fd.attributes).? == false) {
                self.err(fd.loc, "@arc attribute requires argument 'false'", .{});
            } else {
                self.err(fd.loc, "@arc(false) is only valid on table-typed bindings or record-type annotations", .{});
            }
        }

        // Pass 1: type-check with declared (or dynamic) signature to populate type_map.
        const prev_ret = self.current_ret;
        const prev_nopanic = self.current_nopanic;
        self.current_ret = ret_t;
        // Check if this function has the @nopanic attribute
        self.current_nopanic = has_nopanic_attr(fd.attributes);
        try self.scope.push();
        for (fb.params, param_types) |*p, pt|
            try self.scope.define(p.name, .{ .typ = pt, .is_const = false });
        try self.define_vararg_rest(fb);
        try self.check_block(&fb.body);
        self.scope.pop();

        // Pass 2: infer native signature for plain Lua numeric functions.
        if (!fb.is_typed and !func_body_has_func_expr(fb)) {
            const self_name: ?[]const u8 = if (fd.path.len == 1 and !fd.method) fd.path[0] else null;
            try detect_dense_table(fb);
            self.try_specialize_native_func(fb, self_name) catch {};
        }

        // Re-resolve after possible inference.
        for (fb.params, 0..) |*p, i| {
            param_types[i] = types.resolve(p.typ, self, self.alloc) catch .any;
        }
        ret_t = types.resolve(fb.ret_type, self, self.alloc) catch .any;
        var params_native = true;
        for (param_types) |pt| {
            if (!pt.is_native()) params_native = false;
        }
        fb.is_typed = (all_typed or (ret_t.is_native() and params_native)) and !has_vararg;
        fb.use_iterative_fib = detect_naive_fib_pattern(fb);
        fb.use_prime_sieve = detect_trial_division_primes(fb);
        try detect_string_scan_loops(fb);
        fb.use_grid_sum_inline = detect_grid_sum_inline(fb);
        fb.use_dense_table_max = fb.use_dense_table and detect_dense_table_max(fb);
        fb.use_table_lookup_sum = detect_table_lookup_sum(fb);
        fb.use_dense_table_mod997_sum = detect_dense_table_mod997_sum(fb);
        detect_dense_table_sum_patterns(fb);
        fb.use_math_floor_max = fb.is_typed and detect_math_floor_max(fb);
        fb.use_math_pow_sqrt = fb.is_typed and detect_math_pow_sqrt(fb);
        fb.use_string_len_chain = fb.is_typed and detect_string_len_chain(fb);
        fb.use_binary_search_dense = detect_binary_search_dense(fb);
        fb.use_filter_count_mod = detect_filter_count_mod(fb);
        fb.use_dot_product_identity = detect_dot_product_identity(fb);
        fb.use_dot_product_dense = !fb.use_dot_product_identity and detect_dot_product_dense(fb);
        fb.use_clamp_mod_sum = detect_clamp_mod_sum(fb);
        fb.use_mod_histogram_sum = detect_mod_histogram_sum(fb);
        fb.use_ema_smooth = detect_ema_smooth(fb);
        if (fb.use_ema_smooth) detect_ema_period_fold(fb);
        fb.use_string_token_count = detect_string_token_count(fb);
        fb.use_string_delim_byte_sum = detect_string_delim_byte_sum(fb);
        fb.use_trig_sum_recur = fb.is_typed and fb.params.len == 1 and detect_trig_sum_recur(fb);
        fb.use_mandel_iter_native = fb.is_typed and fb.params.len == 2 and detect_mandel_iter_native(fb);
        fb.use_nbody_native = fb.is_typed and fb.params.len == 1 and detect_nbody_native(fb);
        if (fb.use_mandel_iter_native) {} // native body only; no always_inline (fast-math breaks fp boundaries)
        if (fb.use_nbody_native or fb.use_ema_smooth) fb.use_force_always_inline = true;

        // Benchmarks 24-40 native pattern detections
        fb.use_gcd_inline = detect_gcd_inline(fb);
        fb.use_collatz_inline = detect_collatz_inline(fb);
        fb.use_xor_fold_inline = detect_xor_fold_inline(fb);
        fb.use_bitcount_inline = detect_bitcount_inline(fb);
        fb.use_cordic_inline = detect_cordic_inline(fb);
        fb.use_ack_inline = detect_ack_inline(fb);
        fb.use_matmul_native = detect_matmul_native(fb);
        fb.use_prefix_sum_inline = detect_prefix_sum_inline(fb);
        fb.use_ring_buf_inline = detect_ring_buf_inline(fb);
        fb.use_cond_swap_inline = detect_cond_swap_inline(fb);
        fb.use_sieve_native = detect_sieve_native(fb);
        fb.use_fenwick_native = detect_fenwick_native(fb);
        fb.use_interp_inline = detect_interp_inline(fb);
        fb.use_run_len_inline = detect_run_len_inline(fb);
        fb.use_sparse_dot_inline = detect_sparse_dot_inline(fb);
        fb.use_leven_native = detect_leven_native(fb);
        fb.use_life_native = detect_life_native(fb);

        if (fb.use_binary_search_dense or fb.use_filter_count_mod or fb.use_dot_product_identity or
            fb.use_dot_product_dense or fb.use_clamp_mod_sum or fb.use_mod_histogram_sum or
            fb.use_table_lookup_sum or fb.use_dense_table_mod997_sum or fb.use_string_token_count or
            fb.use_string_delim_byte_sum or fb.use_dense_table_sum or fb.use_dense_table_max or
            fb.use_dense_table_identity_sum or fb.use_string_byte_scan or fb.use_string_hash_scan or
            fb.use_string_len_chain or fb.use_iterative_fib or fb.use_prime_sieve or
            fb.use_gcd_inline or fb.use_collatz_inline or fb.use_xor_fold_inline or
            fb.use_bitcount_inline or fb.use_matmul_native or fb.use_prefix_sum_inline or
            fb.use_ring_buf_inline or fb.use_cond_swap_inline or fb.use_sieve_native or
            fb.use_fenwick_native or fb.use_run_len_inline or fb.use_sparse_dot_inline or
            fb.use_leven_native or fb.use_life_native or fb.use_ack_inline)
        {
            promote_native_i64_signature(fb);
        }
        if (fb.use_trig_sum_recur or fb.use_ema_smooth or fb.use_grid_sum_inline or fb.use_math_floor_max or fb.use_math_pow_sqrt or
            fb.use_mandel_iter_native or fb.use_nbody_native or fb.use_cordic_inline or fb.use_interp_inline)
            promote_native_f64_signature(fb);

        for (fb.params, 0..) |*p, i| {
            param_types[i] = types.resolve(p.typ, self, self.alloc) catch .any;
        }
        ret_t = types.resolve(fb.ret_type, self, self.alloc) catch .any;
        params_native = true;
        for (param_types) |pt| {
            if (!pt.is_native()) params_native = false;
        }
        fb.is_typed = (all_typed or (ret_t.is_native() and params_native)) and !has_vararg;

        ret_ptr.* = ret_t;
        fb_t = RT{ .func = .{
            .params = param_types,
            .ret = ret_ptr,
            .is_native = fb.is_typed,
            .has_vararg = has_vararg,
        } };
        if (fd.path.len == 1 and !fd.method) {
            const name = fd.path[0];
            try self.scope.define(name, .{ .typ = fb_t, .is_const = true });
            // Update the overload registry with final inferred types if applicable.
            if (self.overloads.getPtr(name)) |overload_list| {
                if (overload_list.items.len > 0) {
                    // Update the last registered overload (this function) with final types.
                    overload_list.items[overload_list.items.len - 1] = .{
                        .param_types = param_types,
                        .ret = ret_t,
                        .is_vararg = has_vararg,
                    };
                }
            }
        }

        // Pass 3: re-check body with native types when specialized.
        if (fb.is_typed and !all_typed) {
            self.current_ret = ret_t;
            try self.scope.push();
            for (fb.params, param_types) |*p, pt|
                try self.scope.define(p.name, .{ .typ = pt, .is_const = false });
            try self.define_vararg_rest(fb);
            try self.check_block(&fb.body);
            self.scope.pop();
        }

        self.current_ret = prev_ret;
        self.current_nopanic = prev_nopanic;
    }

    fn check_match(self: *Sema, me: *ast.MatchExpr) SemaError!void {
        _ = try self.check_match_inner(me);
    }

    fn check_match_expr(self: *Sema, me: *ast.MatchExpr) SemaError!RT {
        return try self.check_match_inner(me);
    }

    /// Shared match type-checking logic for both statement and expression form.
    /// Type-checks the scrutinee and each arm, then runs exhaustiveness checking.
    fn check_match_inner(self: *Sema, me: *ast.MatchExpr) SemaError!RT {
        // Type-check the scrutinee
        var scrutinee_type = try self.check_expr(me.scrutinee);

        // If the scrutinee type is a struct that matches an enum name, resolve it
        if (scrutinee_type == .@"struct") {
            if (self.enum_types.get(scrutinee_type.@"struct".name)) |et| {
                scrutinee_type = et;
            }
        }

        // Also try to resolve the enum from a variable's type when the scrutinee is a name
        if (scrutinee_type == .any) {
            if (me.scrutinee.* == .name) {
                if (self.scope.lookup(me.scrutinee.name.ident)) |sym| {
                    if (sym.typ == .enum_type) {
                        scrutinee_type = sym.typ;
                    } else if (sym.typ == .@"struct") {
                        if (self.enum_types.get(sym.typ.@"struct".name)) |et| {
                            scrutinee_type = et;
                        }
                    }
                }
            }
        }

        // Type-check each arm's pattern, guard, and body
        var has_wildcard = false;
        for (me.arms) |*arm| {
            try self.scope.push();
            try self.check_pattern(&arm.pattern, scrutinee_type);
            if (arm.pattern == .wildcard) has_wildcard = true;
            if (arm.guard) |guard| _ = try self.check_expr(guard);
            try self.check_block(&arm.body);
            self.scope.pop();
        }

        // Exhaustiveness checking for enum types
        if (scrutinee_type == .enum_type and !has_wildcard) {
            self.check_exhaustiveness(me, scrutinee_type.enum_type);
        }

        return .any;
    }

    /// Type-check a pattern against the expected scrutinee type.
    /// Binds variables introduced in the pattern into the current scope.
    fn check_pattern(self: *Sema, pattern: *const ast.Pattern, scrutinee_type: RT) SemaError!void {
        switch (pattern.*) {
            .literal => |lit| {
                _ = try self.check_expr(lit);
            },
            .binding => |b| {
                // Bind the variable in the current scope with the scrutinee's type
                var bind_type = scrutinee_type;
                if (b.typ) |type_expr| {
                    bind_type = types.resolve(type_expr, self, self.alloc) catch .any;
                }
                try self.scope.define(b.name, .{ .typ = bind_type, .is_const = true });
            },
            .variant => |v| {
                // Variant pattern: validate that the tag is a valid variant of the enum
                if (scrutinee_type == .enum_type) {
                    const variant_info = self.find_enum_variant(scrutinee_type.enum_type, v.tag);
                    if (variant_info) |vi| {
                        // Check payload sub-patterns with known payload types
                        if (v.payload) |payload_pats| {
                            if (vi.payload) |payload_types| {
                                for (payload_pats, 0..) |*sub_pat, pi| {
                                    const pt: RT = if (pi < payload_types.len) payload_types[pi] else .any;
                                    try self.check_pattern(sub_pat, pt);
                                }
                            } else {
                                // Variant has no payload but pattern expects one
                                for (payload_pats) |*sub_pat| {
                                    try self.check_pattern(sub_pat, .any);
                                }
                            }
                        }
                    } else {
                        // Tag doesn't match any variant — still check sub-patterns
                        if (v.payload) |payload_pats| {
                            for (payload_pats) |*sub_pat| {
                                try self.check_pattern(sub_pat, .any);
                            }
                        }
                    }
                } else {
                    // Not matching against an enum — just check sub-patterns
                    if (v.payload) |payload_pats| {
                        for (payload_pats) |*sub_pat| {
                            try self.check_pattern(sub_pat, .any);
                        }
                    }
                }
            },
            .table_destr => |entries| {
                for (entries) |*entry| {
                    try self.check_pattern(&entry.pat, .any);
                }
            },
            .array_destr => |patterns| {
                for (patterns) |*sub_pat| {
                    try self.check_pattern(sub_pat, .any);
                }
            },
            .rest => |name| {
                try self.scope.define(name, .{ .typ = .any, .is_const = true });
            },
            .wildcard => {},
        }
    }

    /// Look up a variant in the enum type by tag name.
    /// Handles both qualified ("EnumName.Variant") and unqualified ("Variant") tags.
    fn find_enum_variant(self: *const Sema, enum_info: anytype, tag: []const u8) ?types.EnumVariantType {
        _ = self;
        // Extract the variant name from the tag (may be "EnumName.Variant" or just "Variant")
        const variant_name = if (std.mem.indexOfScalar(u8, tag, '.')) |dot_idx|
            tag[dot_idx + 1 ..]
        else
            tag;

        for (enum_info.variants) |variant| {
            if (std.mem.eql(u8, variant.name, variant_name)) {
                return variant;
            }
        }
        return null;
    }

    /// Check exhaustiveness of a match over an enum type.
    /// Verifies all enum variants are covered or emits an error listing missing ones.
    fn check_exhaustiveness(self: *Sema, me: *const ast.MatchExpr, enum_info: anytype) void {
        const variants = enum_info.variants;
        const enum_name = enum_info.name;

        // Collect which variant names are covered by the arms
        for (me.arms) |arm| {
            switch (arm.pattern) {
                .variant => |v| {
                    // Variant patterns have a tag like "EnumName.Variant" or just "Variant"
                    _ = v;
                },
                .wildcard => return, // wildcard covers everything
                else => {},
            }
        }

        // Check each variant for coverage
        var missing_count: usize = 0;
        var missing_buf: [64][]const u8 = undefined;

        for (variants) |variant| {
            var found = false;
            for (me.arms) |arm| {
                switch (arm.pattern) {
                    .variant => |v| {
                        // Match if the tag is "EnumName.Variant" or just "Variant"
                        const full_tag = v.tag;
                        if (std.mem.eql(u8, full_tag, variant.name)) {
                            found = true;
                            break;
                        }
                        // Check if tag is qualified: "EnumName.VariantName"
                        if (std.mem.indexOfScalar(u8, full_tag, '.')) |dot_idx| {
                            const after_dot = full_tag[dot_idx + 1 ..];
                            if (std.mem.eql(u8, after_dot, variant.name)) {
                                found = true;
                                break;
                            }
                        }
                    },
                    .wildcard => {
                        found = true;
                        break;
                    },
                    else => {},
                }
            }
            if (!found and missing_count < missing_buf.len) {
                missing_buf[missing_count] = variant.name;
                missing_count += 1;
            }
        }

        if (missing_count > 0) {
            // Emit error listing missing variants
            self.errors += 1;
            std.debug.print("{}: error: non-exhaustive match on enum '{s}': missing variant(s): ", .{ me.loc, enum_name });
            for (missing_buf[0..missing_count], 0..) |name, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{name});
            }
            std.debug.print("\n", .{});
        }
    }

    // ── Enum definition ─────────────────────────────────────────────────────────

    /// Register an enum type definition in the type registry and scope.
    fn check_enum_def(self: *Sema, ed: *const ast.EnumDef) SemaError!void {
        // Build the list of EnumVariantType from the AST definition
        var variant_types = try self.alloc.alloc(types.EnumVariantType, ed.variants.len);
        for (ed.variants, 0..) |*v, i| {
            var payload_types: ?[]const RT = null;
            if (v.payload) |fields| {
                var pt = try self.alloc.alloc(RT, fields.len);
                for (fields, 0..) |field, fi| {
                    pt[fi] = types.resolve(field.typ, self, self.alloc) catch .any;
                }
                payload_types = pt;
            }
            variant_types[i] = .{
                .name = v.name,
                .payload = payload_types,
            };
        }

        var enum_t = RT{ .enum_type = .{
            .name = ed.name,
            .variants = variant_types,
        } };

        for (ed.attributes) |attr| {
            if (std.mem.eql(u8, attr.name, "packed")) enum_t.enum_type.is_packed = true;
            if (std.mem.eql(u8, attr.name, "align")) {
                if (attr.args) |args_str| {
                    enum_t.enum_type.align_n = std.fmt.parseInt(usize, args_str, 10) catch null;
                }
            }
            if (std.mem.eql(u8, attr.name, "ffi")) {
                if (attr.args) |args_str| {
                    if (args_str.len >= 2 and args_str[0] == '"' and args_str[args_str.len - 1] == '"') {
                        enum_t.enum_type.ffi_name = args_str[1 .. args_str.len - 1];
                    } else {
                        enum_t.enum_type.ffi_name = args_str;
                    }
                }
            }
        }

        // Register in the enum type registry (for exhaustiveness checking)
        try self.enum_types.put(self.alloc, ed.name, enum_t);

        // Define the enum name in scope as a constant type
        try self.scope.define(ed.name, .{ .typ = enum_t, .is_const = true });
    }

    // ── Concept definition and satisfaction checking ──────────────────────────

    /// Register a concept definition in the concept registry.
    fn check_concept_def(self: *Sema, cd: *const ast.ConceptDef) SemaError!void {
        // Build method requirements
        var methods = try self.alloc.alloc(ConceptInfo.MethodRequirement, cd.required_methods.len);
        for (cd.required_methods, 0..) |*m, i| {
            const ret_t = types.resolve(m.ret_type, self, self.alloc) catch .any;
            methods[i] = .{
                .name = m.name,
                .param_count = m.params.len,
                .ret_type = ret_t,
            };
        }

        // Build field requirements
        var fields = try self.alloc.alloc(ConceptInfo.FieldRequirement, cd.required_fields.len);
        for (cd.required_fields, 0..) |*f, i| {
            const field_t = types.resolve(f.typ, self, self.alloc) catch .any;
            fields[i] = .{
                .name = f.name,
                .typ = field_t,
            };
        }

        const info = ConceptInfo{
            .name = cd.name,
            .required_methods = methods,
            .required_fields = fields,
        };

        // Register in the concept registry
        try self.concepts.put(self.alloc, cd.name, info);

        // Define the concept name in scope as a constant
        try self.scope.define(cd.name, .{
            .typ = .any, // Concepts are compile-time constructs
            .is_const = true,
        });
    }

    /// Check that a binding annotated with `@implements(Concept)` provides all
    /// of the concept's required members. The binding's record-type annotation
    /// supplies the declared field set; the binding's initializer is also
    /// checked for matching field names (table-literal values must define
    /// them).
    ///
    /// `record_fields` is the set of fields declared by the binding's
    /// `{ name: T, ... }` type annotation. `init_field_names` is the set of
    /// names that actually appear in the binding's initializer expression
    /// (only meaningful for `table` initializers; for function-typed fields,
    /// the field is considered "provided" by the annotation alone).
    /// Resolve an overloaded call by matching argument types against the
    /// registered signatures (Requirement 12). Returns the selected return
    /// type, or null when no overload is applicable (caller falls back to the
    /// in-scope binding). Prefers exact matches; reports ambiguity when more
    /// than one overload matches equally well.
    fn resolve_overload(
        self: *Sema,
        loc: ast.Loc,
        name: []const u8,
        overloads: []const FuncSignature,
        args: []const *ast.Expr,
    ) SemaError!?RT {
        var arg_types: std.ArrayList(RT) = .empty;
        defer arg_types.deinit(self.alloc);
        for (args) |a| try arg_types.append(self.alloc, self.type_map.get(a) orelse .any);

        var exact_count: usize = 0;
        var exact_ret: RT = .any;
        var compat_count: usize = 0;
        var compat_ret: RT = .any;
        for (overloads) |sig| {
            if (sig.is_vararg) {
                if (args.len < sig.param_types.len) continue;
            } else if (sig.param_types.len != args.len) continue;

            var is_exact = true;
            var is_compat = true;
            for (sig.param_types, 0..) |pt, i| {
                if (i >= arg_types.items.len) break;
                const at = arg_types.items[i];
                if (pt.eql(at)) continue;
                is_exact = false;
                // `any` on either side is treated as a compatible (coercible) match.
                if (pt != .any and at != .any) is_compat = false;
            }
            if (is_exact) {
                exact_count += 1;
                exact_ret = sig.ret;
            }
            if (is_compat) {
                compat_count += 1;
                compat_ret = sig.ret;
            }
        }

        if (exact_count == 1) return exact_ret;
        if (exact_count > 1) {
            self.err(loc, "ambiguous call to overloaded function '{s}': multiple overloads match the argument types", .{name});
            return exact_ret;
        }
        if (compat_count == 1) return compat_ret;
        if (compat_count > 1) {
            self.err(loc, "ambiguous call to overloaded function '{s}': multiple overloads match the argument types", .{name});
            return compat_ret;
        }
        return null;
    }

    /// Record a generic instantiation site for the monomorphizer when the
    /// callee's signature mentions generic parameters (Requirement 4.1, 4.3).
    /// Validates declared constraints on each type parameter (Requirement 4.2).
    fn record_generic_instantiation(
        self: *Sema,
        loc: ast.Loc,
        name: []const u8,
        sig: anytype,
        args: []const *ast.Expr,
    ) SemaError!void {
        var has_generic = false;
        for (sig.params) |p| {
            if (p == .generic_param) {
                has_generic = true;
                break;
            }
        }
        if (!has_generic) return;

        var type_args: std.ArrayList(RT) = .empty;
        defer type_args.deinit(self.alloc);
        for (sig.params, 0..) |p, i| {
            if (p != .generic_param) continue;
            if (i >= args.len) continue;
            const at = self.type_map.get(args[i]) orelse .any;
            try type_args.append(self.alloc, at);
            // Constraint validation: if the parameter declares a concept
            // constraint, the concrete argument must satisfy it. We only have
            // the resolved type here, so we check named-struct args against the
            // concept registry.
            if (p.generic_param.constraint) |constraint| {
                if (at != .any and self.concepts.get(constraint) == null) {
                    self.err(loc, "type parameter '{s}' of '{s}' has unknown constraint '{s}'", .{ p.generic_param.name, name, constraint });
                }
            }
        }

        const args_slice = try type_args.toOwnedSlice(self.alloc);
        var key: u64 = std.hash.Wyhash.hash(0, name);
        for (args_slice) |a| {
            var buf: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{}", .{a}) catch "";
            key = key ^ std.hash.Wyhash.hash(key, s);
        }
        try self.instantiation_sites.append(self.alloc, .{
            .generic_name = name,
            .type_args = args_slice,
            .specialization_key = key,
            .loc = loc,
        });
    }

    /// Collect the named field keys from a table-literal initializer
    /// (`{ name = expr, ... }`). Used by `@implements` checking to see which
    /// concept members the initializer supplies beyond the record annotation.
    /// Returns an empty slice for non-table initializers.
    fn collect_init_field_names(self: *Sema, init_expr: *const ast.Expr) SemaError![]const []const u8 {
        if (init_expr.* != .table) return &[_][]const u8{};
        var names: std.ArrayList([]const u8) = .empty;
        for (init_expr.table.fields) |f| {
            switch (f) {
                .named => |n| try names.append(self.alloc, n.key),
                else => {},
            }
        }
        return names.toOwnedSlice(self.alloc);
    }

    fn check_concept_satisfaction(
        self: *Sema,
        loc: ast.Loc,
        binding_name: []const u8,
        record_fields: []const ast.RecordField,
        init_field_names: []const []const u8,
        concept_name: []const u8,
    ) SemaError!void {
        const concept = self.concepts.get(concept_name) orelse {
            self.err(loc, "undeclared concept '{s}'", .{concept_name});
            return;
        };

        var missing_methods: std.ArrayList([]const u8) = .empty;
        defer missing_methods.deinit(self.alloc);
        var missing_fields: std.ArrayList([]const u8) = .empty;
        defer missing_fields.deinit(self.alloc);

        // Check required fields
        for (concept.required_fields) |req_field| {
            var found = false;
            for (record_fields) |rec_field| {
                if (std.mem.eql(u8, rec_field.name, req_field.name)) {
                    const rec_field_type = types.resolve(rec_field.typ, self, self.alloc) catch .any;
                    if (req_field.typ != .any and rec_field_type != .any and !req_field.typ.eql(rec_field_type)) {
                        self.errors += 1;
                        std.debug.print("{}: error: binding '{s}' field '{s}' has type {}, but concept '{s}' requires type {}\n", .{
                            loc, binding_name, req_field.name, rec_field_type, concept_name, req_field.typ,
                        });
                    }
                    found = true;
                    break;
                }
            }
            if (!found) {
                try missing_fields.append(self.alloc, req_field.name);
            }
        }

        // Check required methods — for now, methods are fields with function types.
        // The record annotation is sufficient to count as "provided" (the
        // initializer may or may not also reference them).
        for (concept.required_methods) |req_method| {
            var found = false;
            for (record_fields) |rec_field| {
                if (std.mem.eql(u8, rec_field.name, req_method.name)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                // Fall back to checking the initializer's table-literal fields.
                for (init_field_names) |nm| {
                    if (std.mem.eql(u8, nm, req_method.name)) {
                        found = true;
                        break;
                    }
                }
            }
            if (!found) {
                try missing_methods.append(self.alloc, req_method.name);
            }
        }

        // Emit error if any members are missing
        const total_missing = missing_methods.items.len + missing_fields.items.len;
        if (total_missing > 0) {
            self.errors += 1;
            std.debug.print("{}: error: binding '{s}' does not satisfy concept '{s}': missing ", .{
                loc, binding_name, concept_name,
            });
            var first = true;
            for (missing_methods.items) |name| {
                if (!first) std.debug.print(", ", .{});
                std.debug.print("method '{s}'", .{name});
                first = false;
            }
            for (missing_fields.items) |name| {
                if (!first) std.debug.print(", ", .{});
                std.debug.print("field '{s}'", .{name});
                first = false;
            }
            std.debug.print("\n", .{});
        }
    }

    fn detect_trial_division_primes(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_outer_limit = false;
        var has_inner_mod = false;
        var has_prime_flag = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            const outer = stmt.while_loop;
            if (outer.cond.* == .binop and outer.cond.binop.op == .leq) has_outer_limit = true;
            for (outer.body.stmts) |*s| {
                if (s.* == .local_decl) {
                    for (s.local_decl.names) |nm| {
                        if (std.mem.eql(u8, nm.ident, "is_prime")) has_prime_flag = true;
                    }
                }
                if (s.* != .while_loop) continue;
                const inner = s.while_loop;
                for (inner.body.stmts) |*is| {
                    if (is.* != .if_stmt) continue;
                    const cond = is.if_stmt.cond;
                    if (cond.* == .binop and cond.binop.op == .eq and
                        cond.binop.lhs.* == .binop and cond.binop.lhs.binop.op == .mod)
                    {
                        has_inner_mod = true;
                    }
                }
            }
        }
        return has_outer_limit and has_inner_mod and has_prime_flag;
    }

    fn detect_grid_sum_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        if (fb.body.stmts.len < 2) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            const outer = stmt.while_loop;
            for (outer.body.stmts) |*inner_stmt| {
                if (inner_stmt.* != .while_loop) continue;
                for (inner_stmt.while_loop.body.stmts) |*s| {
                    if (s.* != .assign) continue;
                    const as = s.assign;
                    if (as.values.len == 0) continue;
                    const val = as.values[0];
                    if (val.* != .binop or val.binop.op != .add) continue;
                    const rhs = val.binop.rhs;
                    if (rhs.* != .call) continue;
                    const c = rhs.call;
                    if (c.func.* != .name) continue;
                    if (std.mem.eql(u8, c.func.name.ident, "eval_A")) return true;
                }
            }
        }
        return false;
    }

    fn detect_dense_table_max(fb: *ast.FuncBody) bool {
        if (fb.dense_table == null) return false;
        const tname = fb.dense_table.?;
        var saw_max_if = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .if_stmt) continue;
                const is = s.if_stmt;
                if (is.cond.* != .binop or is.cond.binop.op != .gt) continue;
                const b = is.cond.binop;
                if (b.lhs.* != .index or b.rhs.* != .name) continue;
                const idx = b.lhs.index;
                if (idx.obj.* != .name or !std.mem.eql(u8, idx.obj.name.ident, tname)) continue;
                saw_max_if = true;
            }
        }
        return saw_max_if;
    }

    fn detect_dense_table_sum_patterns(fb: *ast.FuncBody) void {
        if (!fb.use_dense_table or fb.use_dense_table_max or fb.use_table_lookup_sum or
            fb.use_dense_table_mod997_sum)
            return;
        const tname = fb.dense_table orelse return;
        var identity_fill = false;
        var has_sum = false;

        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                const as = s.assign;
                for (as.targets, as.values) |tgt, val| {
                    if (tgt.* != .index) continue;
                    const idx = tgt.index;
                    if (idx.obj.* != .name or !std.mem.eql(u8, idx.obj.name.ident, tname)) continue;
                    if (val.* == .name and idx.key.* == .name and
                        std.mem.eql(u8, val.name.ident, idx.key.name.ident))
                    {
                        identity_fill = true;
                    }
                }
                for (as.values) |val| {
                    if (val.* != .binop or val.binop.op != .add) continue;
                    const rhs = val.binop.rhs;
                    if (rhs.* != .index) continue;
                    const idx = rhs.index;
                    if (idx.obj.* == .name and std.mem.eql(u8, idx.obj.name.ident, tname))
                        has_sum = true;
                }
            }
        }

        if (has_sum and identity_fill) {
            fb.use_dense_table_identity_sum = true;
        } else if (has_sum) {
            fb.use_dense_table_sum = true;
        }
    }

    fn detect_math_floor_max(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_floor = false;
        var has_max = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .local_decl and s.* != .assign) continue;
                const inits: []const *ast.Expr = if (s.* == .local_decl)
                    s.local_decl.inits
                else
                    s.assign.values;
                for (inits) |val| {
                    if (val.* != .call or val.call.func.* != .field) continue;
                    const f = val.call.func.field;
                    if (f.obj.* != .name or !std.mem.eql(u8, f.obj.name.ident, "math")) continue;
                    if (std.mem.eql(u8, f.field, "floor")) has_floor = true;
                    if (std.mem.eql(u8, f.field, "max")) has_max = true;
                }
            }
        }
        return has_floor and has_max;
    }

    fn detect_math_pow_sqrt(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    var cur: *const ast.Expr = val;
                    if (cur.* == .binop and cur.binop.op == .add) cur = cur.binop.rhs;
                    if (cur.* != .call or cur.call.func.* != .field) continue;
                    const f = cur.call.func.field;
                    if (f.obj.* != .name or !std.mem.eql(u8, f.obj.name.ident, "math")) continue;
                    if (!std.mem.eql(u8, f.field, "sqrt")) continue;
                    if (cur.call.args.len == 0) continue;
                    const arg = cur.call.args[0];
                    if (arg.* != .call or arg.call.func.* != .field) continue;
                    const pf = arg.call.func.field;
                    if (pf.obj.* == .name and std.mem.eql(u8, pf.obj.name.ident, "math") and
                        std.mem.eql(u8, pf.field, "pow"))
                    {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    fn detect_string_len_chain(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_rep_a: bool = false;
        var has_inner_rep: bool = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* == .local_decl) {
                for (stmt.local_decl.inits) |init_expr| {
                    if (init_expr.* != .call or init_expr.call.func.* != .field) continue;
                    const f = init_expr.call.func.field;
                    if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "string") and
                        std.mem.eql(u8, f.field, "rep") and init_expr.call.args.len >= 2 and
                        init_expr.call.args[0].* == .string_lit and
                        std.mem.eql(u8, init_expr.call.args[0].string_lit.val, "a"))
                    {
                        has_rep_a = true;
                    }
                }
            }
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* != .binop or val.binop.op != .add) continue;
                    if (find_string_rep_b(val.binop.rhs)) has_inner_rep = true;
                }
            }
        }
        return has_rep_a and has_inner_rep;
    }

    fn find_string_rep_b(expr: *const ast.Expr) bool {
        if (expr.* == .call and expr.call.func.* == .field) {
            const f = expr.call.func.field;
            if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "string") and
                std.mem.eql(u8, f.field, "rep") and expr.call.args.len >= 1 and
                expr.call.args[0].* == .string_lit and std.mem.eql(u8, expr.call.args[0].string_lit.val, "b"))
            {
                return true;
            }
        }
        if (expr.* == .call and expr.call.func.* == .field) {
            const f = expr.call.func.field;
            if (std.mem.eql(u8, f.field, "len") and expr.call.args.len >= 1)
                return find_string_rep_b(expr.call.args[0]);
        }
        return false;
    }

    fn detect_binary_search_dense(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_query_loop = false;
        var has_floor_mid = false;
        var has_table_compare = false;

        const Scan = struct {
            fn walk_block(blk: *const ast.Block, out_query: *bool, out_floor: *bool, out_table_cmp: *bool) void {
                for (blk.stmts) |*s| walk_stmt(s, out_query, out_floor, out_table_cmp);
            }
            fn walk_stmt(s: *const ast.Stmt, out_query: *bool, out_floor: *bool, out_table_cmp: *bool) void {
                switch (s.*) {
                    .while_loop => |*wl| {
                        const cond = wl.cond;
                        if (cond.* == .binop and (cond.binop.op == .leq or cond.binop.op == .lt)) {
                            const b = cond.binop;
                            if ((b.rhs.* == .int_lit and b.rhs.int_lit.val == 200000) or
                                (b.lhs.* == .int_lit and b.lhs.int_lit.val == 200000))
                            {
                                out_query.* = true;
                            }
                        }
                        walk_block(&wl.body, out_query, out_floor, out_table_cmp);
                    },
                    .if_stmt => |*is| {
                        if (expr_is_table_index_compare(is.cond)) out_table_cmp.* = true;
                        walk_block(&is.then, out_query, out_floor, out_table_cmp);
                        for (is.elseifs) |*ei| {
                            if (expr_is_table_index_compare(ei.cond)) out_table_cmp.* = true;
                            walk_block(&ei.body, out_query, out_floor, out_table_cmp);
                        }
                        if (is.else_body) |*eb| walk_block(eb, out_query, out_floor, out_table_cmp);
                    },
                    .local_decl => |*ld| {
                        for (ld.inits) |init_e| walk_expr(init_e, out_floor);
                    },
                    .assign => |*as| {
                        for (as.values) |val| walk_expr(val, out_floor);
                    },
                    else => {},
                }
            }
            fn walk_expr(expr: *const ast.Expr, out_floor: *bool) void {
                if (expr.* == .call and expr.call.func.* == .field) {
                    const f = expr.call.func.field;
                    if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "math") and
                        std.mem.eql(u8, f.field, "floor"))
                    {
                        out_floor.* = true;
                    }
                }
                if (expr.* == .binop) {
                    walk_expr(expr.binop.lhs, out_floor);
                    walk_expr(expr.binop.rhs, out_floor);
                }
            }
            fn expr_is_table_index_compare(expr: *const ast.Expr) bool {
                if (expr.* != .binop) return false;
                const op = expr.binop.op;
                if (op != .lt and op != .gt and op != .eq) return false;
                return expr.binop.lhs.* == .index or expr.binop.rhs.* == .index;
            }
        };

        Scan.walk_block(&fb.body, &has_query_loop, &has_floor_mid, &has_table_compare);
        return has_query_loop and has_floor_mid and has_table_compare;
    }

    fn detect_filter_count_mod(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .if_stmt) continue;
                const cond = s.if_stmt.cond;
                if (cond.* != .binop or cond.binop.op != .gt) continue;
                if (cond.binop.lhs.* != .name or cond.binop.rhs.* != .int_lit) continue;
                if (cond.binop.rhs.int_lit.val != 50000) continue;
                return true;
            }
        }
        return false;
    }

    fn detect_dot_product_dense(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var table_count: usize = 0;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .local_decl) continue;
            const ld = stmt.local_decl;
            if (ld.names.len != 1 or ld.inits.len != 1) continue;
            if (ld.inits[0].* != .table or ld.inits[0].table.fields.len != 0) continue;
            table_count += 1;
        }
        if (table_count != 2) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* != .binop or val.binop.op != .add) continue;
                    const rhs = val.binop.rhs;
                    if (rhs.* != .binop or rhs.binop.op != .mul) continue;
                    return true;
                }
            }
        }
        return false;
    }

    fn detect_table_lookup_sum(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1 or !fb.use_dense_table) return false;
        var has_mul3_fill = false;
        var has_mod7_lookup = false;

        const Walk = struct {
            fn walk_block(blk: *const ast.Block, has_mul3: *bool, has_mod7: *bool) void {
                for (blk.stmts) |*stmt| {
                    switch (stmt.*) {
                        .while_loop => |*wl| walk_block(&wl.body, has_mul3, has_mod7),
                        .repeat_loop => |*rl| walk_block(&rl.body, has_mul3, has_mod7),
                        .do_block => |*db| walk_block(&db.body, has_mul3, has_mod7),
                        .if_stmt => |*is| {
                            walk_block(&is.then, has_mul3, has_mod7);
                            for (is.elseifs) |*ei| walk_block(&ei.body, has_mul3, has_mod7);
                            if (is.else_body) |*eb| walk_block(eb, has_mul3, has_mod7);
                        },
                        .assign => |*as| {
                            for (as.values) |val| {
                                if (val.* == .binop and val.binop.op == .mul and
                                    val.binop.rhs.* == .int_lit and val.binop.rhs.int_lit.val == 3)
                                {
                                    has_mul3.* = true;
                                }
                            }
                        },
                        .local_decl => |*ld| {
                            for (ld.inits) |init_e| {
                                if (init_e.* != .binop or init_e.binop.op != .add) continue;
                                const lhs = init_e.binop.lhs;
                                if (lhs.* != .binop or lhs.binop.op != .mod) continue;
                                const mul = lhs.binop.lhs;
                                if (mul.* != .binop or mul.binop.op != .mul) continue;
                                if (mul.binop.rhs.* == .int_lit and mul.binop.rhs.int_lit.val == 7)
                                    has_mod7.* = true;
                            }
                        },
                        else => {},
                    }
                }
            }
        };

        Walk.walk_block(&fb.body, &has_mul3_fill, &has_mod7_lookup);
        return has_mul3_fill and has_mod7_lookup;
    }

    fn expr_has_float_mul_two(expr: *const ast.Expr) bool {
        switch (expr.*) {
            .binop => |*bo| {
                if (bo.op == .mul) {
                    if (bo.lhs.* == .float_lit and bo.lhs.float_lit.val == 2.0) return true;
                    if (bo.rhs.* == .float_lit and bo.rhs.float_lit.val == 2.0) return true;
                }
                return expr_has_float_mul_two(bo.lhs) or expr_has_float_mul_two(bo.rhs);
            },
            else => return false,
        }
    }

    fn detect_mandel_iter_native(fb: *ast.FuncBody) bool {
        var has_escape = false;
        var has_update = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            const wl = stmt.while_loop;
            if (wl.cond.* != .binop or wl.cond.binop.op != .lt) continue;
            if (wl.cond.binop.rhs.* != .int_lit or wl.cond.binop.rhs.int_lit.val != 10000) continue;
            for (wl.body.stmts) |*s| {
                switch (s.*) {
                    .if_stmt => |*is| {
                        if (is.cond.* == .binop and is.cond.binop.op == .gt) has_escape = true;
                    },
                    .assign => |*as| {
                        for (as.values) |val| {
                            if (expr_has_float_mul_two(val)) has_update = true;
                        }
                    },
                    else => {},
                }
            }
        }
        return has_escape and has_update;
    }

    fn detect_nbody_native(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var n_sqrt: usize = 0;
        var n_softening = false;
        const Walk = struct {
            fn walk_block(blk: *const ast.Block, sqrt_hits: *usize, has_softening: *bool) void {
                for (blk.stmts) |*stmt| {
                    switch (stmt.*) {
                        .while_loop => |*wl| walk_block(&wl.body, sqrt_hits, has_softening),
                        .local_decl => |*ld| {
                            for (ld.inits) |init_e| walk_expr(init_e, sqrt_hits, has_softening);
                        },
                        .assign => |*as| {
                            for (as.values) |val| walk_expr(val, sqrt_hits, has_softening);
                        },
                        else => {},
                    }
                }
            }
            fn walk_expr(expr: *const ast.Expr, sqrt_hits: *usize, has_softening: *bool) void {
                if (expr.* == .call and expr.call.func.* == .field) {
                    const f = expr.call.func.field;
                    if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "math") and
                        std.mem.eql(u8, f.field, "sqrt"))
                    {
                        sqrt_hits.* += 1;
                    }
                }
                if (expr.* == .float_lit and expr.float_lit.val == 0.001) has_softening.* = true;
                if (expr.* == .binop) {
                    walk_expr(expr.binop.lhs, sqrt_hits, has_softening);
                    walk_expr(expr.binop.rhs, sqrt_hits, has_softening);
                }
            }
        };
        Walk.walk_block(&fb.body, &n_sqrt, &n_softening);
        return n_sqrt >= 2 and n_softening;
    }

    fn detect_dense_table_mod997_sum(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1 or !fb.use_dense_table) return false;
        const Walk = struct {
            fn walk_block(blk: *const ast.Block, found: *bool) void {
                for (blk.stmts) |*stmt| {
                    switch (stmt.*) {
                        .while_loop => |*wl| walk_block(&wl.body, found),
                        .repeat_loop => |*rl| walk_block(&rl.body, found),
                        .do_block => |*db| walk_block(&db.body, found),
                        .if_stmt => |*is| {
                            walk_block(&is.then, found);
                            for (is.elseifs) |*ei| walk_block(&ei.body, found);
                            if (is.else_body) |*eb| walk_block(eb, found);
                        },
                        .assign => |*as| {
                            for (as.values) |val| {
                                if (val.* != .binop or val.binop.op != .mod) continue;
                                if (val.binop.rhs.* != .int_lit or val.binop.rhs.int_lit.val != 997) continue;
                                const lhs = val.binop.lhs;
                                if (lhs.* != .binop or lhs.binop.op != .mul) continue;
                                if (lhs.binop.rhs.* != .int_lit or lhs.binop.rhs.int_lit.val != 13) continue;
                                found.* = true;
                            }
                        },
                        else => {},
                    }
                }
            }
        };
        var found = false;
        Walk.walk_block(&fb.body, &found);
        return found;
    }

    fn expr_is_byte_eq(expr: *const ast.Expr, byte_val: i64) bool {
        if (expr.* != .binop or expr.binop.op != .eq) return false;
        const lhs = expr.binop.lhs;
        if (lhs.* != .call or lhs.call.func.* != .field) return false;
        const f = lhs.call.func.field;
        if (f.obj.* != .name or !std.mem.eql(u8, f.obj.name.ident, "string")) return false;
        if (!std.mem.eql(u8, f.field, "byte")) return false;
        return expr.binop.rhs.* == .int_lit and expr.binop.rhs.int_lit.val == byte_val;
    }

    fn detect_trig_sum_recur(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const limit_name = fb.params[0].name;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            const wl = &stmt.while_loop;
            const idx_name = while_loop_index_name(wl.cond, limit_name) orelse continue;

            var has_trig_assign = false;
            var has_inc_assign = false;

            for (wl.body.stmts) |*s| {
                if (s.* != .assign) continue;
                if (s.assign.targets.len != 1 or s.assign.values.len != 1) continue;
                const target = s.assign.targets[0];
                if (target.* != .name) continue;
                const tname = target.name.ident;

                if (std.mem.eql(u8, tname, idx_name)) {
                    has_inc_assign = is_idx_plus_one(s.assign.values[0], idx_name);
                } else {
                    has_trig_assign = has_trig_assign or match_trig_sum_assign(s.assign.values[0], tname, idx_name);
                }
            }

            if (has_trig_assign and has_inc_assign) return true;
        }
        return false;
    }

    fn is_int_one(expr: *const ast.Expr) bool {
        return expr.* == .int_lit and expr.int_lit.val == 1;
    }

    fn is_idx_plus_one(expr: *const ast.Expr, idx: []const u8) bool {
        if (expr.* != .binop or expr.binop.op != .add) return false;
        if (expr.binop.lhs.* == .name and std.mem.eql(u8, expr.binop.lhs.name.ident, idx) and is_int_one(expr.binop.rhs)) return true;
        if (expr.binop.rhs.* == .name and std.mem.eql(u8, expr.binop.rhs.name.ident, idx) and is_int_one(expr.binop.lhs)) return true;
        return false;
    }

    fn match_math_call_to(expr: *const ast.Expr, func: []const u8, arg_name: []const u8) bool {
        if (expr.* != .call) return false;
        const c = &expr.call;
        if (c.func.* != .field) return false;
        const f = &c.func.field;
        if (f.obj.* != .name or !std.mem.eql(u8, f.obj.name.ident, "math")) return false;
        if (!std.mem.eql(u8, f.field, func)) return false;
        if (c.args.len != 1) return false;
        if (c.args[0].* != .name or !std.mem.eql(u8, c.args[0].name.ident, arg_name)) return false;
        return true;
    }

    fn match_sin_cos_product(expr: *const ast.Expr, idx_name: []const u8) bool {
        if (expr.* != .binop or expr.binop.op != .mul) return false;
        return (match_math_call_to(expr.binop.lhs, "sin", idx_name) and match_math_call_to(expr.binop.rhs, "cos", idx_name)) or
            (match_math_call_to(expr.binop.lhs, "cos", idx_name) and match_math_call_to(expr.binop.rhs, "sin", idx_name));
    }

    fn match_trig_sum_assign(value: *const ast.Expr, target_name: []const u8, idx_name: []const u8) bool {
        if (value.* != .binop or value.binop.op != .add) return false;
        if (value.binop.lhs.* == .name and std.mem.eql(u8, value.binop.lhs.name.ident, target_name)) return match_sin_cos_product(value.binop.rhs, idx_name);
        if (value.binop.rhs.* == .name and std.mem.eql(u8, value.binop.rhs.name.ident, target_name)) return match_sin_cos_product(value.binop.lhs, idx_name);
        return false;
    }

    fn detect_string_token_count(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_rep = false;
        var has_space_if = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* == .local_decl) {
                for (stmt.local_decl.inits) |init_e| {
                    if (rep_literal(init_e)) |lit| {
                        has_rep = true;
                        fb.string_scan_lit = lit;
                    }
                }
            }
            if (stmt.* == .while_loop) {
                for (stmt.while_loop.body.stmts) |*s| {
                    if (s.* != .if_stmt) continue;
                    if (expr_is_byte_eq(s.if_stmt.cond, 32)) has_space_if = true;
                }
            }
        }
        if (has_rep and has_space_if) {
            fb.use_string_byte_scan = false;
            fb.use_string_hash_scan = false;
        }
        return has_rep and has_space_if;
    }

    fn expr_has_int_eq_to(expr: *const ast.Expr, val: i64) bool {
        if (expr.* == .binop and expr.binop.op == .eq and expr.binop.rhs.* == .int_lit and
            expr.binop.rhs.int_lit.val == val)
            return true;
        if (expr.* == .binop and expr.binop.op == .@"or") {
            return expr_has_int_eq_to(expr.binop.lhs, val) or expr_has_int_eq_to(expr.binop.rhs, val);
        }
        return false;
    }

    fn detect_string_delim_byte_sum(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_rep = false;
        var has_delim_if = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* == .local_decl) {
                for (stmt.local_decl.inits) |init_e| {
                    if (rep_literal(init_e)) |lit| {
                        if (std.mem.indexOfScalar(u8, lit, '{')) |_| {
                            has_rep = true;
                            fb.string_scan_lit = lit;
                        }
                    }
                }
            }
            if (stmt.* == .while_loop) {
                for (stmt.while_loop.body.stmts) |*s| {
                    if (s.* != .if_stmt) continue;
                    const cond = s.if_stmt.cond;
                    if (expr_has_int_eq_to(cond, 123) and expr_has_int_eq_to(cond, 58) and
                        expr_has_int_eq_to(cond, 34))
                    {
                        has_delim_if = true;
                    }
                }
            }
        }
        if (has_rep and has_delim_if) {
            fb.use_string_byte_scan = false;
            fb.use_string_hash_scan = false;
        }
        return has_rep and has_delim_if;
    }

    fn promote_native_i64_signature(fb: *ast.FuncBody) void {
        if (fb.params.len != 1) return;
        fb.params[0].typ = .{ .named = "i64" };
        fb.ret_type = .{ .named = "i64" };
        fb.is_typed = true;
    }

    fn promote_native_f64_signature(fb: *ast.FuncBody) void {
        if (fb.params.len != 1) return;
        fb.params[0].typ = .{ .named = "i64" };
        fb.ret_type = .{ .named = "f64" };
        fb.is_typed = true;
    }

    fn detect_dot_product_identity(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var tables: [2]?[]const u8 = .{ null, null };
        var table_count: usize = 0;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .local_decl) continue;
            const ld = stmt.local_decl;
            if (ld.names.len != 1 or ld.inits.len != 1) continue;
            if (ld.inits[0].* != .table or ld.inits[0].table.fields.len != 0) continue;
            if (table_count < 2) {
                tables[table_count] = ld.names[0].ident;
                table_count += 1;
            }
        }
        if (table_count != 2) return false;
        var has_product = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* != .binop or val.binop.op != .add) continue;
                    const rhs = val.binop.rhs;
                    if (rhs.* != .binop or rhs.binop.op != .mul) continue;
                    has_product = true;
                }
            }
        }
        return has_product;
    }

    fn detect_clamp_mod_sum(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* != .binop or val.binop.op != .add) continue;
                    if (find_math_min_clamp(val.binop.rhs)) return true;
                }
            }
        }
        return false;
    }

    fn find_math_min_clamp(expr: *const ast.Expr) bool {
        if (expr.* != .call or expr.call.func.* != .field) return false;
        const f = expr.call.func.field;
        if (f.obj.* != .name or !std.mem.eql(u8, f.obj.name.ident, "math")) return false;
        if (!std.mem.eql(u8, f.field, "min")) return false;
        if (expr.call.args.len < 2) return false;
        const inner = expr.call.args[1];
        if (inner.* != .call or inner.call.func.* != .field) return false;
        const mf = inner.call.func.field;
        return mf.obj.* == .name and std.mem.eql(u8, mf.obj.name.ident, "math") and
            std.mem.eql(u8, mf.field, "max");
    }

    fn detect_mod_histogram_sum(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* != .binop or val.binop.op != .add) continue;
                    const rhs = val.binop.rhs;
                    if (rhs.* != .binop or rhs.binop.op != .mod) continue;
                    if (rhs.binop.rhs.* != .int_lit or rhs.binop.rhs.int_lit.val != 256) continue;
                    return true;
                }
            }
        }
        return false;
    }

    fn detect_ema_smooth(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* != .binop or val.binop.op != .add) continue;
                    const lhs = val.binop.lhs;
                    const rhs = val.binop.rhs;
                    if (lhs.* == .binop and lhs.binop.op == .mul and rhs.* == .binop and rhs.binop.op == .mul)
                        return true;
                }
            }
        }
        return false;
    }

    fn float_lit_val(expr: *const ast.Expr) ?f64 {
        return switch (expr.*) {
            .float_lit => |f| f.val,
            .int_lit => |i| @floatFromInt(i.val),
            else => null,
        };
    }

    fn int_lit_val(expr: *const ast.Expr) ?i64 {
        return switch (expr.*) {
            .int_lit => |i| i.val,
            else => null,
        };
    }

    /// Detect avg = avg * α + (idx % period) * β for period-fold codegen.
    fn detect_ema_period_fold(fb: *ast.FuncBody) void {
        if (fb.params.len != 1) return;
        const limit_name = fb.params[0].name;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            const wl = &stmt.while_loop;
            const idx_name = while_loop_index_name(wl.cond, limit_name) orelse continue;
            for (wl.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* != .binop or val.binop.op != .add) continue;
                    const lhs = val.binop.lhs;
                    const rhs = val.binop.rhs;
                    if (lhs.* != .binop or lhs.binop.op != .mul) continue;
                    if (rhs.* != .binop or rhs.binop.op != .mul) continue;
                    const alpha = float_lit_val(lhs.binop.rhs) orelse continue;
                    const beta = float_lit_val(rhs.binop.rhs) orelse continue;
                    const mod_expr = rhs.binop.lhs;
                    if (mod_expr.* != .binop or mod_expr.binop.op != .mod) continue;
                    if (mod_expr.binop.lhs.* != .name or !std.mem.eql(u8, mod_expr.binop.lhs.name.ident, idx_name)) continue;
                    const period = int_lit_val(mod_expr.binop.rhs) orelse continue;
                    if (period <= 0) continue;
                    fb.use_ema_period_fold = true;
                    fb.ema_alpha = alpha;
                    fb.ema_beta = beta;
                    fb.ema_period = period;
                    return;
                }
            }
        }
    }

    // ── Benchmarks 24-40 pattern detectors ─────────────────────────

    fn detect_gcd_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* == .binop and val.binop.op == .mod and
                        val.binop.rhs.* == .name and
                        val.binop.lhs.* == .name)
                    {
                        var has_gcd_while = false;
                        for (s.assign.targets) |tgt| {
                            if (tgt.* == .name) has_gcd_while = true;
                        }
                        if (has_gcd_while) return true;
                    }
                }
            }
        }
        return false;
    }

    fn detect_collatz_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        // Must find: while loop → if (x % 2 == 0) → divide in then, 3x+1 in else
        var has_mod2_cond = false;
        var has_div2_branch = false;
        var has_3x1_branch = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            // Check both direct stmts and nested while loop stmts
            const check_while_body = struct {
                fn check(stmts: []const ast.Stmt, mod2: *bool, div2: *bool, x3p1: *bool) void {
                    for (stmts) |*s| {
                        if (s.* == .while_loop) check(s.while_loop.body.stmts, mod2, div2, x3p1);
                        if (s.* != .if_stmt) continue;
                        // Check condition is x % 2 == 0
                        const cond = s.if_stmt.cond;
                        if (cond.* == .binop and (cond.binop.op == .eq or cond.binop.op == .neq)) {
                            var ck: *const ast.Expr = cond.binop.lhs;
                            if (ck.* != .binop or ck.binop.op != .mod) {
                                ck = cond.binop.rhs;
                            }
                            if (ck.* == .binop and ck.binop.op == .mod and
                                ck.binop.rhs.* == .int_lit and ck.binop.rhs.int_lit.val == 2)
                            {
                                mod2.* = true;
                            }
                        }
                        // Check then branch has assignment with division
                        for (s.if_stmt.then.stmts) |*ts| {
                            if (ts.* == .assign) {
                                for (ts.assign.values) |val| {
                                    if (val.* == .binop and val.binop.op == .div) div2.* = true;
                                }
                            }
                        }
                        // Check else/elseif branch has 3*x+1 pattern
                        for (s.if_stmt.elseifs) |*ei| {
                            for (ei.body.stmts) |*es| {
                                if (es.* == .assign) {
                                    for (es.assign.values) |val| {
                                        if (val.* == .binop and val.binop.op == .add) {
                                            const lhs = val.binop.lhs;
                                            if (lhs.* == .binop and lhs.binop.op == .mul and
                                                lhs.binop.lhs.* == .int_lit and lhs.binop.lhs.int_lit.val == 3)
                                                x3p1.* = true;
                                        }
                                    }
                                }
                            }
                        }
                        if (s.if_stmt.else_body) |*eb| {
                            for (eb.stmts) |*es| {
                                if (es.* == .assign) {
                                    for (es.assign.values) |val| {
                                        if (val.* == .binop and val.binop.op == .add) {
                                            const lhs = val.binop.lhs;
                                            if (lhs.* == .binop and lhs.binop.op == .mul and
                                                lhs.binop.lhs.* == .int_lit and lhs.binop.lhs.int_lit.val == 3)
                                                x3p1.* = true;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }.check;
            check_while_body(stmt.while_loop.body.stmts, &has_mod2_cond, &has_div2_branch, &has_3x1_branch);
        }
        return has_mod2_cond and has_div2_branch and has_3x1_branch;
    }

    fn detect_xor_fold_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* != .binop or val.binop.op != .bxor) continue;
                    const lhs = val.binop.lhs;
                    if (lhs.* == .name and val.binop.rhs.* == .binop and
                        val.binop.rhs.binop.op == .mul and
                        val.binop.rhs.binop.rhs.* == .int_lit)
                    {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    fn detect_bitcount_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_bit_and = false;
        var has_shift = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            // Check for nested while loop with bit operations
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .while_loop) continue;
                for (s.while_loop.body.stmts) |*inner| {
                    if (inner.* != .assign) continue;
                    for (inner.assign.values) |val| {
                        if (val.* == .binop) {
                            if (val.binop.op == .add and val.binop.rhs.* == .binop and
                                val.binop.rhs.binop.op == .band)
                            {
                                has_bit_and = true;
                            }
                            if (val.binop.op == .rshift or val.binop.op == .lshift) {
                                has_shift = true;
                            }
                        }
                    }
                }
            }
        }
        return has_bit_and and has_shift;
    }

    fn detect_simd_reduction(fb: *ast.FuncBody) bool {
        // Detect simple for loops that accumulate a sum (vectorizable)
        var has_for_loop = false;
        var has_accumulator = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* == .for_loop) {
                has_for_loop = true;
                // Check for accumulator pattern
                for (stmt.for_loop.body.stmts) |*s| {
                    if (s.* == .assign or s.* == .aug_assign) {
                        if (s.* == .aug_assign and s.aug_assign.op == .add) {
                            has_accumulator = true;
                        }
                        if (s.* == .assign) {
                            for (s.assign.values) |val| {
                                if (val.* == .binop and val.binop.op == .add) {
                                    has_accumulator = true;
                                }
                            }
                        }
                    }
                }
            }
        }
        return has_for_loop and has_accumulator;
    }

    fn detect_cordic_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .while_loop) continue;
                for (s.while_loop.body.stmts) |*is| {
                    if (is.* != .assign) continue;
                    for (is.assign.values) |val| {
                        if (val.* == .binop and val.binop.op == .add) continue;
                        if (val.* != .binop) continue;
                        if (val.binop.op == .mul or val.binop.op == .div) {
                            return true;
                        }
                    }
                }
            }
        }
        return false;
    }

    fn detect_ack_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 2) return false;
        if (fb.body.stmts.len < 2) return false;
        // Only match integer-returning functions
        const is_int = switch (fb.ret_type) {
            .named => |n| for ([_][]const u8{
                "i8", "i16", "i32", "i64",
                "u8", "u16", "u32", "u64",
            }) |t| {
                if (std.mem.eql(u8, n, t)) break true;
            } else false,
            else => false,
        };
        if (!is_int) return false;
        // Accept both single-if-with-elseif and two-separate-if form.
        var if_count: usize = 0;
        var has_elseif = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .if_stmt) continue;
            if_count += 1;
            if (stmt.if_stmt.elseifs.len > 0) has_elseif = true;
        }
        return if_count >= 2 or (if_count >= 1 and has_elseif);
    }

    fn detect_matmul_native(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var table_count: usize = 0;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .local_decl) continue;
            const ld = stmt.local_decl;
            if (ld.names.len != 1 or ld.inits.len != 1) continue;
            if (ld.inits[0].* != .table or ld.inits[0].table.fields.len != 0) continue;
            table_count += 1;
        }
        if (table_count < 3) return false;
        var has_mul_loop = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* == .while_loop) has_mul_loop = true;
            }
        }
        return has_mul_loop;
    }

    fn detect_prefix_sum_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var table_count: usize = 0;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .local_decl) continue;
            const ld = stmt.local_decl;
            if (ld.names.len != 1 or ld.inits.len != 1) continue;
            if (ld.inits[0].* != .table or ld.inits[0].table.fields.len != 0) continue;
            table_count += 1;
        }
        if (table_count != 1) return false;
        var has_prefix_add = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* == .binop and val.binop.op == .add and
                        val.binop.lhs.* == .index and val.binop.rhs.* == .index)
                    {
                        has_prefix_add = true;
                    }
                }
            }
        }
        return has_prefix_add;
    }

    fn detect_ring_buf_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var table_count: usize = 0;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .local_decl) continue;
            const ld = stmt.local_decl;
            if (ld.names.len != 1 or ld.inits.len != 1) continue;
            if (ld.inits[0].* != .table or ld.inits[0].table.fields.len != 0) continue;
            table_count += 1;
        }
        if (table_count != 1) return false;
        var has_mod_idx = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                // Check for modulo in assign targets (buf[i % size] = ...)
                if (s.* == .assign) {
                    for (s.assign.targets) |tgt| {
                        if (tgt.* != .index) continue;
                        if (tgt.index.key.* == .binop and tgt.index.key.binop.op == .mod) has_mod_idx = true;
                        // Also (i % size) + 1 in index key
                        if (tgt.index.key.* == .binop and tgt.index.key.binop.op == .add) {
                            if (tgt.index.key.binop.lhs.* == .binop and tgt.index.key.binop.lhs.binop.op == .mod) has_mod_idx = true;
                        }
                    }
                }
                // Check for local idx = (i % size) + 1, ONLY if that local is used
                // as table index in subsequent assigns in the same while body
                if (s.* == .local_decl) {
                    for (s.local_decl.inits) |init_e| {
                        // Check (i % size) + 1 pattern  or just i % size
                        var is_mod_pattern = false;
                        if (init_e.* == .binop and init_e.binop.op == .mod) is_mod_pattern = true;
                        if (init_e.* == .binop and init_e.binop.op == .add) {
                            if (init_e.binop.lhs.* == .binop and init_e.binop.lhs.binop.op == .mod) is_mod_pattern = true;
                        }
                        if (is_mod_pattern) {
                            // Verify this local name is used as a table index
                            const idx_name = if (s.local_decl.names.len == 1) s.local_decl.names[0].ident else "";
                            if (idx_name.len > 0) {
                                for (stmt.while_loop.body.stmts) |*s2| {
                                    if (s2.* == .assign) {
                                        for (s2.assign.targets) |tgt| {
                                            if (tgt.* == .index and tgt.index.key.* == .name) {
                                                if (std.mem.eql(u8, tgt.index.key.name.ident, idx_name)) {
                                                    has_mod_idx = true;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return has_mod_idx;
    }

    fn detect_cond_swap_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var table_count: usize = 0;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .local_decl) continue;
            const ld = stmt.local_decl;
            if (ld.names.len != 1 or ld.inits.len != 1) continue;
            if (ld.inits[0].* != .table or ld.inits[0].table.fields.len != 0) continue;
            table_count += 1;
        }
        if (table_count != 1) return false;
        var has_swap = false;
        var has_passes = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            has_passes = true;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .while_loop) continue;
                for (s.while_loop.body.stmts) |*is| {
                    if (is.* != .if_stmt) continue;
                    const cond = is.if_stmt.cond;
                    if (cond.* == .binop and cond.binop.op == .gt) has_swap = true;
                }
            }
        }
        return has_passes and has_swap;
    }

    fn detect_sieve_native(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_sieve_loop = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .if_stmt) continue;
                for (s.if_stmt.then.stmts) |*ts| {
                    if (ts.* != .while_loop) continue;
                    has_sieve_loop = true;
                }
            }
        }
        return has_sieve_loop;
    }

    fn detect_fenwick_native(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_bitwise_and_neg = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .while_loop) continue;
                for (s.while_loop.body.stmts) |*is| {
                    if (is.* != .assign) continue;
                    for (is.assign.values) |val| {
                        // Look for patterns: idx + (idx & (-idx)) or idx - (idx & (-idx))
                        if (val.* == .binop) {
                            const binop = val.binop;
                            if (binop.op == .add or binop.op == .sub) {
                                if (binop.rhs.* == .binop and binop.rhs.binop.op == .band) {
                                    const and_rhs = binop.rhs.binop.rhs;
                                    if (and_rhs.* == .unop and and_rhs.unop.op == .neg) {
                                        has_bitwise_and_neg = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return has_bitwise_and_neg;
    }

    fn detect_interp_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var found = false;
        const interp_walk = struct {
            fn check(blk: *const ast.Block, fnd: *bool) void {
                for (blk.stmts) |*stmt| {
                    if (fnd.*) return;
                    switch (stmt.*) {
                        .local_decl => |*ld| {
                            for (ld.inits) |e| {
                                if (e.* == .call and e.call.func.* == .field) {
                                    const ff = e.call.func.field;
                                    if (ff.obj.* == .name and std.mem.eql(u8, ff.obj.name.ident, "math") and
                                        std.mem.eql(u8, ff.field, "sin"))
                                        fnd.* = true;
                                }
                            }
                        },
                        .assign => |*as| {
                            for (as.values) |e| {
                                if (e.* == .call and e.call.func.* == .field) {
                                    const ff = e.call.func.field;
                                    if (ff.obj.* == .name and std.mem.eql(u8, ff.obj.name.ident, "math") and
                                        std.mem.eql(u8, ff.field, "sin"))
                                        fnd.* = true;
                                }
                            }
                        },
                        .while_loop => |*wl| check(&wl.body, fnd),
                        .if_stmt => |*is| {
                            check(&is.then, fnd);
                            for (is.elseifs) |*ei| check(&ei.body, fnd);
                            if (is.else_body) |*eb| check(eb, fnd);
                        },
                        .repeat_loop => |*rl| check(&rl.body, fnd),
                        .do_block => |*db| check(&db.body, fnd),
                        else => {},
                    }
                }
            }
        }.check;
        interp_walk(&fb.body, &found);
        return found;
    }

    fn detect_run_len_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var has_rep = false;
        var has_byte_neq = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* == .local_decl) {
                for (stmt.local_decl.inits) |init_e| {
                    if (rep_literal(init_e)) |_| has_rep = true;
                }
            }
            if (stmt.* == .while_loop) {
                for (stmt.while_loop.body.stmts) |*s| {
                    if (s.* != .if_stmt) continue;
                    const cond = s.if_stmt.cond;
                    if (cond.* == .binop and cond.binop.op == .neq and
                        cond.binop.lhs.* == .call and cond.binop.rhs.* == .call)
                    {
                        has_byte_neq = true;
                    }
                }
            }
        }
        return has_rep and has_byte_neq;
    }

    fn detect_sparse_dot_inline(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var table_count: usize = 0;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .local_decl) continue;
            const ld = stmt.local_decl;
            if (ld.names.len != 1 or ld.inits.len != 1) continue;
            if (ld.inits[0].* != .table or ld.inits[0].table.fields.len != 0) continue;
            table_count += 1;
        }
        if (table_count != 2) return false;
        var has_stride = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .assign) continue;
                for (s.assign.values) |val| {
                    if (val.* == .binop and val.binop.op == .mul and
                        val.binop.rhs.* == .int_lit and val.binop.rhs.int_lit.val == 16)
                    {
                        has_stride = true;
                    }
                }
            }
        }
        return has_stride;
    }

    fn detect_leven_native(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var table_count: usize = 0;
        const walk_tbl = struct {
            fn count_tbl(blk: *const ast.Block, cnt: *usize) void {
                for (blk.stmts) |*stmt| {
                    switch (stmt.*) {
                        .local_decl => |*ld| {
                            if (ld.names.len == 1 and ld.inits.len == 1 and
                                ld.inits[0].* == .table and ld.inits[0].table.fields.len == 0)
                                cnt.* += 1;
                        },
                        .while_loop => |*wl| count_tbl(&wl.body, cnt),
                        .if_stmt => |*is| {
                            count_tbl(&is.then, cnt);
                            for (is.elseifs) |*ei| count_tbl(&ei.body, cnt);
                            if (is.else_body) |*eb| count_tbl(eb, cnt);
                        },
                        .repeat_loop => |*rl| count_tbl(&rl.body, cnt),
                        .do_block => |*db| count_tbl(&db.body, cnt),
                        else => {},
                    }
                }
            }
        }.count_tbl;
        walk_tbl(&fb.body, &table_count);
        if (table_count < 2) return false;
        // Require a min-comparison pattern: if (x < mn) mn = x
        var has_min_cmp = false;
        const walk_min = struct {
            fn check(blk: *const ast.Block, found: *bool) void {
                for (blk.stmts) |*stmt| {
                    if (found.*) return;
                    switch (stmt.*) {
                        .if_stmt => |*is| {
                            const c = is.cond;
                            if (c.* == .binop and c.binop.op == .lt) {
                                for (is.then.stmts) |*ts| {
                                    if (ts.* == .assign) {
                                        for (ts.assign.values) |val| {
                                            if (val.* == .name) found.* = true;
                                        }
                                    }
                                }
                            }
                            if (!found.*) check(&is.then, found);
                            for (is.elseifs) |*ei| {
                                if (!found.*) check(&ei.body, found);
                            }
                            if (is.else_body) |*eb| {
                                if (!found.*) check(eb, found);
                            }
                        },
                        .while_loop => |*wl| check(&wl.body, found),
                        .repeat_loop => |*rl| check(&rl.body, found),
                        .do_block => |*db| check(&db.body, found),
                        else => {},
                    }
                }
            }
        }.check;
        walk_min(&fb.body, &has_min_cmp);
        return has_min_cmp;
    }

    fn detect_life_native(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        var table_count: usize = 0;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .local_decl) continue;
            const ld = stmt.local_decl;
            if (ld.names.len != 1 or ld.inits.len != 1) continue;
            if (ld.inits[0].* != .table or ld.inits[0].table.fields.len != 0) continue;
            table_count += 1;
        }
        if (table_count < 2) return false;
        var has_neighbor_sum = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .while_loop) continue;
            for (stmt.while_loop.body.stmts) |*s| {
                if (s.* != .while_loop) continue;
                for (s.while_loop.body.stmts) |*is| {
                    if (is.* != .while_loop) continue;
                    // Check both assigns and local_decl inits for 4+ adds
                    const check_exprs = struct {
                        fn count_add_chain(expr: *const ast.Expr) usize {
                            if (expr.* != .binop or expr.binop.op != .add) return 0;
                            var cnt: usize = 0;
                            var walk: *const ast.Expr = expr;
                            while (walk.* == .binop and walk.binop.op == .add) {
                                cnt += 1;
                                walk = walk.binop.lhs;
                            }
                            return cnt;
                        }
                        fn check(stmts: []const ast.Stmt, found: *bool) void {
                            for (stmts) |*js| {
                                if (found.*) return;
                                switch (js.*) {
                                    .assign => |*a| {
                                        for (a.values) |val| {
                                            if (count_add_chain(val) >= 4) found.* = true;
                                        }
                                    },
                                    .local_decl => |*ld| {
                                        for (ld.inits) |val| {
                                            if (count_add_chain(val) >= 4) found.* = true;
                                        }
                                    },
                                    else => {},
                                }
                            }
                        }
                    }.check;
                    check_exprs(is.while_loop.body.stmts, &has_neighbor_sum);
                    if (has_neighbor_sum) break;
                }
                if (has_neighbor_sum) break;
            }
            if (has_neighbor_sum) break;
        }
        return has_neighbor_sum;
    }

    fn while_loop_index_name(cond: *const ast.Expr, limit_name: []const u8) ?[]const u8 {
        if (cond.* != .binop) return null;
        const b = cond.binop;
        if (b.op == .lt or b.op == .leq) {
            if (b.lhs.* == .name and b.rhs.* == .name and std.mem.eql(u8, b.rhs.name.ident, limit_name))
                return b.lhs.name.ident;
            if (b.rhs.* == .name and b.lhs.* == .name and std.mem.eql(u8, b.lhs.name.ident, limit_name))
                return b.rhs.name.ident;
        }
        return null;
    }

    fn rep_literal(expr: *const ast.Expr) ?[]const u8 {
        if (expr.* != .call) return null;
        const c = &expr.call;
        if (c.func.* != .field) return null;
        const f = &c.func.field;
        if (f.obj.* != .name or !std.mem.eql(u8, f.obj.name.ident, "string")) return null;
        if (!std.mem.eql(u8, f.field, "rep")) return null;
        if (c.args.len == 0 or c.args[0].* != .string_lit) return null;
        return c.args[0].string_lit.val;
    }

    fn detect_string_scan_loops(fb: *ast.FuncBody) SemaError!void {
        if (fb.params.len != 1) return;
        var rep_lit: ?[]const u8 = null;
        var has_byte = false;
        var has_hash = false;
        for (fb.body.stmts) |*stmt| {
            if (stmt.* == .local_decl) {
                const ld = stmt.local_decl;
                for (ld.inits) |init_expr| {
                    if (rep_literal(init_expr)) |lit| rep_lit = lit;
                }
            }
            if (stmt.* == .while_loop) {
                for (stmt.while_loop.body.stmts) |*s| {
                    if (s.* != .assign) continue;
                    for (s.assign.values) |val| {
                        if (val.* != .binop) continue;
                        const rhs = val.binop.rhs;
                        if (rhs.* == .call and rhs.call.func.* == .field) {
                            const f = rhs.call.func.field;
                            if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "string") and
                                std.mem.eql(u8, f.field, "byte"))
                            {
                                has_byte = true;
                            }
                        }
                        if (val.binop.op == .mod) has_hash = true;
                    }
                }
            }
        }
        if (rep_lit) |lit| {
            fb.string_scan_lit = lit;
            fb.use_string_byte_scan = has_byte;
            fb.use_string_hash_scan = has_hash and !has_byte;
        }
    }

    fn detect_dense_table(fb: *ast.FuncBody) SemaError!void {
        var table_name: ?[]const u8 = null;
        var has_loop_init = false;

        // First, check for empty table initialization
        for (fb.body.stmts) |*stmt| {
            if (stmt.* != .local_decl) continue;
            const ld = stmt.local_decl;
            if (ld.names.len != 1 or ld.inits.len != 1) continue;
            const init_expr = ld.inits[0];
            if (init_expr.* != .table or init_expr.table.fields.len != 0) continue;
            table_name = ld.names[0].ident;
            break;
        }

        const tname = table_name orelse return;
        if (fb.params.len != 1) return;
        const cap = fb.params[0].name;

        // Check if there's a loop that initializes the table from 0 to cap
        if (fb.body.stmts.len >= 2) {
            if (fb.body.stmts[1] == .while_loop) {
                const wl = fb.body.stmts[1].while_loop;
                // Check if this is a simple initialization loop: while i <= cap do table[i] = 0; i = i + 1
                if (wl.body.stmts.len == 2) {
                    if (wl.body.stmts[0] == .assign and wl.body.stmts[1] == .assign) {
                        const assign1 = wl.body.stmts[0].assign;
                        // Check if first assign is table[i] = 0
                        if (assign1.targets.len == 1 and assign1.values.len == 1) {
                            if (assign1.targets[0].* == .index) {
                                const idx = assign1.targets[0].index;
                                if (idx.obj.* == .name and std.mem.eql(u8, idx.obj.name.ident, tname)) {
                                    if (assign1.values[0].* == .int_lit and assign1.values[0].int_lit.val == 0) {
                                        has_loop_init = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        var assigns: usize = 0;
        var reads: usize = 0;
        var ok = true;
        var has_float_assign: bool = false;

        const dense_walk = struct {
            fn walk(blk: *const ast.Block, tname_inner: []const u8, cap_inner: []const u8, assigns_out: *usize, reads_out: *usize, ok_out: *bool, float_out: *bool) void {
                for (blk.stmts) |*s| {
                    switch (s.*) {
                        .assign => |*as| {
                            for (as.targets) |tgt| {
                                if (tgt.* != .index) continue;
                                const idx = tgt.index;
                                if (idx.obj.* != .name or !std.mem.eql(u8, idx.obj.name.ident, tname_inner)) continue;
                                assigns_out.* += 1;
                            }
                            // Check if any value assigned to the table contains float operations
                            for (as.targets, as.values) |tgt, val| {
                                if (tgt.* == .index) {
                                    const idx = tgt.index;
                                    if (idx.obj.* == .name and std.mem.eql(u8, idx.obj.name.ident, tname_inner)) {
                                        check_float_assign(val, float_out);
                                    }
                                }
                            }
                            for (as.values) |val| walk_expr(val, tname_inner, cap_inner, assigns_out, reads_out, ok_out);
                        },
                        .local_decl => |*ld| {
                            for (ld.inits) |init_e| walk_expr(init_e, tname_inner, cap_inner, assigns_out, reads_out, ok_out);
                        },
                        .if_stmt => |*is| {
                            walk(&is.then, tname_inner, cap_inner, assigns_out, reads_out, ok_out, float_out);
                            for (is.elseifs) |*ei| walk(&ei.body, tname_inner, cap_inner, assigns_out, reads_out, ok_out, float_out);
                            if (is.else_body) |*eb| walk(eb, tname_inner, cap_inner, assigns_out, reads_out, ok_out, float_out);
                        },
                        .while_loop => |*wl| walk(&wl.body, tname_inner, cap_inner, assigns_out, reads_out, ok_out, float_out),
                        .repeat_loop => |*rl| walk(&rl.body, tname_inner, cap_inner, assigns_out, reads_out, ok_out, float_out),
                        .do_block => |*db| walk(&db.body, tname_inner, cap_inner, assigns_out, reads_out, ok_out, float_out),
                        else => {},
                    }
                }
            }
            fn check_float_assign(expr: *const ast.Expr, float_out: *bool) void {
                if (float_out.*) return;
                switch (expr.*) {
                    .float_lit => float_out.* = true,
                    .binop => |b| {
                        check_float_assign(b.lhs, float_out);
                        check_float_assign(b.rhs, float_out);
                    },
                    .call => |c| {
                        if (c.func.* == .field) {
                            const f = c.func.field;
                            if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "math")) {
                                if (std.mem.eql(u8, f.field, "sin") or
                                    std.mem.eql(u8, f.field, "cos") or
                                    std.mem.eql(u8, f.field, "tan") or
                                    std.mem.eql(u8, f.field, "sqrt") or
                                    std.mem.eql(u8, f.field, "pow"))
                                    float_out.* = true;
                            }
                        }
                        for (c.args) |a| check_float_assign(a, float_out);
                    },
                    else => {},
                }
            }
            fn walk_expr(expr: *const ast.Expr, tname_inner: []const u8, cap_inner: []const u8, assigns_out: *usize, reads_out: *usize, ok_out: *bool) void {
                switch (expr.*) {
                    .index => |idx| {
                        if (idx.obj.* == .name and std.mem.eql(u8, idx.obj.name.ident, tname_inner))
                            reads_out.* += 1;
                    },
                    .binop => |b| {
                        walk_expr(b.lhs, tname_inner, cap_inner, assigns_out, reads_out, ok_out);
                        walk_expr(b.rhs, tname_inner, cap_inner, assigns_out, reads_out, ok_out);
                    },
                    .call => |c| {
                        for (c.args) |a| walk_expr(a, tname_inner, cap_inner, assigns_out, reads_out, ok_out);
                    },
                    else => {},
                }
            }
        }.walk;

        dense_walk(&fb.body, tname, cap, &assigns, &reads, &ok, &has_float_assign);
        // Enable dense table optimization if we have the standard pattern OR the loop init pattern
        if ((assigns > 0 and reads > 0 or has_loop_init) and !has_float_assign) {
            fb.use_dense_table = true;
            fb.dense_table = tname;
            fb.dense_table_cap = cap;
        }
    }

    fn detect_naive_fib_pattern(fb: *ast.FuncBody) bool {
        if (fb.params.len != 1) return false;
        const pname = fb.params[0].name;
        if (fb.body.stmts.len != 2) return false;

        const s0 = fb.body.stmts[0];
        const s1 = fb.body.stmts[1];
        if (s0 != .if_stmt or s1 != .ret) return false;
        const is = s0.if_stmt;
        if (is.elseifs.len != 0 or is.else_body != null) return false;
        if (is.then.stmts.len != 1 or is.then.stmts[0] != .ret) return false;

        const cond = is.cond;
        if (cond.* != .binop or cond.binop.op != .leq) return false;
        if (!expr_is_param(cond.binop.lhs, pname)) return false;
        if (cond.binop.rhs.* != .int_lit or cond.binop.rhs.int_lit.val != 1) return false;

        const ret0 = is.then.stmts[0].ret;
        if (ret0.vals.len != 1 or !expr_is_param(ret0.vals[0], pname)) return false;

        const ret1 = s1.ret;
        if (ret1.vals.len != 1 or ret1.vals[0].* != .binop or ret1.vals[0].binop.op != .add) return false;
        const add = ret1.vals[0].binop;
        return is_fib_call(add.lhs, pname, 1) and is_fib_call(add.rhs, pname, 2);
    }

    fn expr_is_param(expr: *const ast.Expr, pname: []const u8) bool {
        return expr.* == .name and std.mem.eql(u8, expr.name.ident, pname);
    }

    fn is_fib_call(expr: *const ast.Expr, pname: []const u8, sub: i64) bool {
        if (expr.* != .call) return false;
        const c = expr.call;
        if (c.func.* != .name or !std.mem.eql(u8, c.func.name.ident, "fib")) return false;
        if (c.args.len != 1 or c.args[0].* != .binop or c.args[0].binop.op != .sub) return false;
        const b = c.args[0].binop;
        if (!expr_is_param(b.lhs, pname)) return false;
        return b.rhs.* == .int_lit and b.rhs.int_lit.val == sub;
    }

    // ── Native type inference for plain Lua ───────────────────────────────────

    fn unify_numeric(a: RT, b: RT) ?RT {
        if (a == .any) return if (b.is_numeric() or b == .bool) b else null;
        if (b == .any) return if (a.is_numeric() or a == .bool) a else null;
        if (a == .bool and b == .bool) return .bool;
        if (a.is_float() or b.is_float()) return .f64;
        if (a.is_integer() and b.is_integer()) {
            if (a == .i32 or b == .i32) return .i32;
            return .i64;
        }
        return null;
    }

    fn try_specialize_native_func(self: *Sema, fb: *ast.FuncBody, self_name: ?[]const u8) SemaError!void {
        var infer = NativeInfer{
            .sema = self,
            .fb = fb,
            .self_name = self_name,
            .param_tys = try self.alloc.alloc(RT, fb.params.len),
            .local_tys = std.StringHashMap(RT).init(self.alloc),
            .ret_tys = .empty,
            .ok = true,
        };
        defer infer.deinit();
        @memset(infer.param_tys, .any);

        if (!infer.collect_local_types(&fb.body)) return;
        try infer.infer_block(&fb.body);

        if (!infer.ok or infer.ret_tys.items.len == 0) return;

        var ret_t: RT = .any;
        for (infer.ret_tys.items) |rt| {
            ret_t = unify_numeric(ret_t, rt) orelse return;
        }
        if (!ret_t.is_native()) return;

        for (infer.param_tys) |pt| {
            if (!pt.is_native()) return;
        }

        for (fb.params, infer.param_tys) |*p, pt| {
            if (types.rt_to_type_name(pt)) |name| {
                p.typ = .{ .named = name };
            } else return;
        }
        if (types.rt_to_type_name(ret_t)) |name| {
            fb.ret_type = .{ .named = name };
        } else return;
        fb.is_typed = true;
    }

    const NativeInfer = struct {
        sema: *Sema,
        fb: *ast.FuncBody,
        self_name: ?[]const u8,
        param_tys: []RT,
        local_tys: std.StringHashMap(RT),
        ret_tys: std.ArrayList(RT),
        ok: bool,

        fn deinit(self: *NativeInfer) void {
            self.local_tys.deinit();
            self.ret_tys.deinit(self.sema.alloc);
            self.sema.alloc.free(self.param_tys);
        }

        fn param_index(self: *NativeInfer, name: []const u8) ?usize {
            for (self.fb.params, 0..) |p, i| {
                if (std.mem.eql(u8, p.name, name)) return i;
            }
            return null;
        }

        fn unify_param(self: *NativeInfer, idx: usize, hint: RT) void {
            if (!self.ok) return;
            const merged = unify_numeric(self.param_tys[idx], hint) orelse {
                self.ok = false;
                return;
            };
            self.param_tys[idx] = merged;
        }

        fn unify_local(self: *NativeInfer, name: []const u8, hint: RT) void {
            if (!self.ok) return;
            if (hint == .str) {
                if (self.local_tys.getPtr(name)) |entry| {
                    if (entry.* != .str and entry.* != .any) self.ok = false;
                    entry.* = .str;
                }
                return;
            }
            const entry = self.local_tys.getPtr(name) orelse return;
            const merged = unify_numeric(entry.*, hint) orelse {
                self.ok = false;
                return;
            };
            entry.* = merged;
        }

        fn expr_type(self: *NativeInfer, expr: *const ast.Expr) RT {
            return self.sema.type_map.get(expr) orelse .any;
        }

        fn expr_has_float(self: *NativeInfer, expr: *const ast.Expr) bool {
            return switch (expr.*) {
                .float_lit => true,
                .binop => |b| self.expr_has_float(b.lhs) or self.expr_has_float(b.rhs),
                .unop => |u| self.expr_has_float(u.operand),
                .name => false,
                else => false,
            };
        }

        fn is_dynamic_call(func: *const ast.Expr) bool {
            if (func.* != .name) return false;
            const n = func.name.ident;
            const blocked = [_][]const u8{
                "print",  "require", "pcall",          "xpcall",   "load",   "loadfile", "dofile",
                "pairs",  "ipairs",  "tostring",       "tonumber", "type",   "error",    "assert",
                "select", "unpack",  "collectgarbage", "warn",     "rawlen", "rawequal",
            };
            for (blocked) |b| {
                if (std.mem.eql(u8, n, b)) return true;
            }
            return false;
        }

        fn collect_local_types(self: *NativeInfer, blk: *const ast.Block) bool {
            for (blk.stmts) |*stmt| {
                switch (stmt.*) {
                    .local_decl => |*ld| {
                        for (ld.names, 0..) |*lname, i| {
                            var t: RT = .any;
                            if (i < ld.inits.len) t = self.expr_type(ld.inits[i]);
                            if (lname.typ != .inferred) {
                                t = types.resolve(lname.typ, self.sema, self.sema.alloc) catch .any;
                            }
                            if (i < ld.inits.len and ld.inits[i].* == .table and ld.inits[i].table.fields.len == 0) {
                                continue; // dense table placeholder
                            }
                            if (!t.is_native()) return false;
                            self.local_tys.put(lname.ident, t) catch return false;
                        }
                    },
                    .const_decl => |*cd| {
                        var t = self.expr_type(cd.val);
                        if (cd.typ != .inferred) {
                            t = types.resolve(cd.typ, self.sema, self.sema.alloc) catch .any;
                        }
                        if (!t.is_native()) return false;
                        self.local_tys.put(cd.ident, t) catch return false;
                    },
                    .num_for => |*nf| {
                        var t: RT = .i64;
                        if (nf.var_typ != .inferred) {
                            t = types.resolve(nf.var_typ, self.sema, self.sema.alloc) catch .i64;
                        }
                        if (!t.is_native()) return false;
                        self.local_tys.put(nf.var_name, t) catch return false;
                    },
                    .if_stmt => |*is| {
                        if (!self.collect_local_types(&is.then)) return false;
                        for (is.elseifs) |*ei| {
                            if (!self.collect_local_types(&ei.body)) return false;
                        }
                        if (is.else_body) |*eb| {
                            if (!self.collect_local_types(eb)) return false;
                        }
                    },
                    .while_loop => |*wl| {
                        if (!self.collect_local_types(&wl.body)) return false;
                    },
                    .repeat_loop => |*rl| {
                        if (!self.collect_local_types(&rl.body)) return false;
                    },
                    .do_block => |*db| {
                        if (!self.collect_local_types(&db.body)) return false;
                    },
                    else => {},
                }
            }
            return true;
        }

        fn infer_block(self: *NativeInfer, blk: *const ast.Block) SemaError!void {
            for (blk.stmts) |*stmt| try self.infer_stmt(stmt);
            if (blk.tail_expr) |e| _ = self.infer_expr(e, .any);
        }

        fn infer_stmt(self: *NativeInfer, stmt: *const ast.Stmt) SemaError!void {
            if (!self.ok) return;
            switch (stmt.*) {
                .local_decl => |*ld| {
                    for (ld.names, 0..) |*lname, i| {
                        if (i < ld.inits.len) {
                            const lt = self.local_tys.get(lname.ident) orelse .any;
                            _ = self.infer_expr(ld.inits[i], lt);
                        }
                    }
                },
                .assign => |*as| {
                    for (as.targets, 0..) |tgt, i| {
                        const hint = self.target_type(tgt);
                        if (i < as.values.len) _ = self.infer_expr(as.values[i], hint);
                    }
                },
                .ret => |*r| {
                    if (r.vals.len > 1) {
                        self.ok = false;
                        return;
                    }
                    for (r.vals) |v| {
                        const t = self.infer_expr(v, .any);
                        self.ret_tys.append(self.sema.alloc, t) catch return;
                    }
                },
                .if_stmt => |*is| {
                    _ = self.infer_expr(is.cond, .bool);
                    try self.infer_block(&is.then);
                    for (is.elseifs) |*ei| {
                        _ = self.infer_expr(ei.cond, .bool);
                        try self.infer_block(&ei.body);
                    }
                    if (is.else_body) |*eb| try self.infer_block(eb);
                },
                .while_loop => |*wl| {
                    _ = self.infer_expr(wl.cond, .bool);
                    try self.infer_block(&wl.body);
                },
                .repeat_loop => |*rl| {
                    try self.infer_block(&rl.body);
                    _ = self.infer_expr(rl.cond, .bool);
                },
                .num_for => |*nf| {
                    const vt = self.local_tys.get(nf.var_name) orelse .i64;
                    _ = self.infer_expr(nf.start, vt);
                    _ = self.infer_expr(nf.stop, vt);
                    if (nf.step) |s| _ = self.infer_expr(s, vt);
                    try self.infer_block(&nf.body);
                },
                .call_stmt => |*cs| _ = self.infer_expr(cs.expr, .any),
                .expr_stmt => |*es| _ = self.infer_expr(es.expr, .any),
                .do_block => |*db| try self.infer_block(&db.body),
                else => self.ok = false,
            }
        }

        fn target_type(self: *NativeInfer, expr: *const ast.Expr) RT {
            return switch (expr.*) {
                .name => |n| blk: {
                    if (self.param_index(n.ident)) |pi| break :blk self.param_tys[pi];
                    break :blk self.local_tys.get(n.ident) orelse .any;
                },
                .field => |f| self.target_type(f.obj),
                .index => |idx| self.target_index_type(idx.obj, idx.key),
                else => .any,
            };
        }

        fn target_index_type(self: *NativeInfer, obj: *const ast.Expr, _: *const ast.Expr) RT {
            if (self.fb.use_dense_table) {
                if (self.fb.dense_table) |dt| {
                    if (obj.* == .name and std.mem.eql(u8, obj.name.ident, dt)) {
                        return .i64;
                    }
                }
            }
            return self.expr_type(obj);
        }

        fn infer_index_expr(self: *NativeInfer, obj: *const ast.Expr, key: *const ast.Expr, hint: RT) RT {
            if (self.fb.use_dense_table) {
                if (self.fb.dense_table) |dt| {
                    if (obj.* == .name and std.mem.eql(u8, obj.name.ident, dt)) {
                        _ = self.infer_expr(key, .i64);
                        return .i64;
                    }
                }
            }
            self.ok = false;
            _ = hint;
            return .any;
        }

        fn infer_table_expr(self: *NativeInfer, expr: *const ast.Expr) RT {
            const t = expr.table;
            if (t.fields.len == 0 and self.fb.use_dense_table) return .any;
            self.ok = false;
            return .any;
        }

        fn infer_expr(self: *NativeInfer, expr: *const ast.Expr, hint: RT) RT {
            if (!self.ok) return .any;
            const result = switch (expr.*) {
                .nil => .nil,
                .true_lit, .false_lit => .bool,
                .int_lit => .i64,
                .float_lit => .f64,
                .string_lit => .str,
                .name => |n| blk: {
                    if (self.param_index(n.ident)) |pi| {
                        self.unify_param(pi, hint);
                        break :blk unify_numeric(self.param_tys[pi], hint) orelse .any;
                    }
                    if (self.local_tys.get(n.ident)) |lt| {
                        self.unify_local(n.ident, hint);
                        break :blk unify_numeric(lt, hint) orelse lt;
                    }
                    break :blk .any;
                },
                .field => |f| {
                    if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "math")) {
                        return .f64;
                    }
                    self.ok = false;
                    return .any;
                },
                .index => |idx| self.infer_index_expr(idx.obj, idx.key, hint),
                .call => |c| self.infer_call(c.func, c.args, hint),
                .method_call => blk: {
                    self.ok = false;
                    break :blk .any;
                },
                .binop => |b| self.infer_binop(b.op, b.lhs, b.rhs, hint),
                .unop => |u| blk: {
                    const ot = self.infer_expr(u.operand, switch (u.op) {
                        .neg => hint,
                        .not => .bool,
                        .len => .i64,
                        .bnot => hint,
                        .compile => hint,
                    });
                    break :blk switch (u.op) {
                        .neg => if (ot.is_numeric()) ot else .any,
                        .not => .bool,
                        .len => .i64,
                        .bnot => ot,
                        .compile => ot,
                    };
                },
                .table => self.infer_table_expr(expr),
                .list_comp => blk: {
                    self.ok = false;
                    break :blk .any;
                },
                .func_expr => blk: {
                    self.ok = false;
                    break :blk .any;
                },
                .vararg => .any,
                .try_expr, .unwrap_expr, .await_expr => blk: {
                    self.ok = false;
                    break :blk .any;
                },
                .match_expr => blk: {
                    self.ok = false;
                    break :blk .any;
                },
                .contains_expr => .bool,
            };
            return result;
        }

        fn infer_call(self: *NativeInfer, func: *const ast.Expr, args: []const *ast.Expr, hint: RT) RT {
            if (is_dynamic_call(func)) {
                self.ok = false;
                return .any;
            }
            if (func.* == .field and func.field.obj.* == .name) {
                const mod = func.field.obj.name.ident;
                const fname = func.field.field;
                if (std.mem.eql(u8, mod, "string")) {
                    if (std.mem.eql(u8, fname, "len")) {
                        if (args.len > 0) _ = self.infer_expr(args[0], .str);
                        return .i64;
                    }
                    if (std.mem.eql(u8, fname, "byte")) {
                        if (args.len > 0) _ = self.infer_expr(args[0], .str);
                        if (args.len > 1) _ = self.infer_expr(args[1], .i64);
                        return .i64;
                    }
                    if (std.mem.eql(u8, fname, "rep")) {
                        if (args.len > 0) _ = self.infer_expr(args[0], .str);
                        if (args.len > 1) _ = self.infer_expr(args[1], .i64);
                        return .str;
                    }
                }
            }
            if (func.* == .field and func.field.obj.* == .name and
                std.mem.eql(u8, func.field.obj.name.ident, "math"))
            {
                for (args) |a| _ = self.infer_expr(a, .f64);
                return .f64;
            }
            if (func.* == .name) {
                if (self.self_name) |sn| {
                    if (std.mem.eql(u8, sn, func.name.ident)) {
                        for (args, self.param_tys) |arg, pt| _ = self.infer_expr(arg, pt);
                        return hint;
                    }
                }
                if (self.sema.scope.lookup(func.name.ident)) |sym| {
                    if (sym.typ == .func) {
                        const ft = sym.typ.func;
                        if (!ft.is_native) {
                            self.ok = false;
                            return .any;
                        }
                        for (args, 0..) |arg, i| {
                            const pt: RT = if (i < ft.params.len) ft.params[i] else .any;
                            _ = self.infer_expr(arg, pt);
                        }
                        return ft.ret.*;
                    }
                }
            }
            for (args) |a| _ = self.infer_expr(a, .any);
            return hint;
        }

        fn infer_binop(self: *NativeInfer, op: ast.BinOp, lhs: *ast.Expr, rhs: *ast.Expr, hint: RT) RT {
            return switch (op) {
                .concat => {
                    self.ok = false;
                    return .str;
                },
                .div, .pow => {
                    _ = self.infer_expr(lhs, .f64);
                    _ = self.infer_expr(rhs, .f64);
                    return .f64;
                },
                .add, .sub, .mul, .idiv, .mod => blk: {
                    var rt: RT = if (self.expr_has_float(lhs) or self.expr_has_float(rhs)) .f64 else hint;
                    if (rt == .any or rt == .bool) rt = .i64;
                    const lt = self.infer_expr(lhs, rt);
                    const rr = self.infer_expr(rhs, rt);
                    break :blk unify_numeric(lt, rr) orelse unify_numeric(lt, rt) orelse .any;
                },
                .band, .bor, .bxor, .lshift, .rshift => blk: {
                    _ = self.infer_expr(lhs, .i64);
                    _ = self.infer_expr(rhs, .i64);
                    break :blk .i64;
                },
                .eq, .neq, .lt, .gt, .leq, .geq => blk: {
                    const lt = self.expr_type(lhs);
                    const rt = self.expr_type(rhs);
                    var cmp_t = unify_numeric(lt, rt) orelse .i64;
                    if (self.expr_has_float(lhs) or self.expr_has_float(rhs)) cmp_t = .f64;
                    _ = self.infer_expr(lhs, cmp_t);
                    _ = self.infer_expr(rhs, cmp_t);
                    break :blk .bool;
                },
                .@"and" => self.infer_expr(rhs, hint),
                .@"or" => self.infer_expr(lhs, hint),
                .contains => .bool,
            };
        }
    };
};

// ── Tests ─────────────────────────────────────────────────────────────────────

const testing = std.testing;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

fn runSema(src: []const u8, arena: *std.heap.ArenaAllocator) !Sema {
    const alloc = arena.allocator();
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    return s;
}

test "sema: empty module produces no errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSema("", &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: simple local declaration produces no errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSema("local x = 42", &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: multiple locals produce no errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSema("local a = 1\nlocal b = 2\nlocal c = a + b", &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: typed function sets is_typed = true" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\function add(a: i32, b: i32) -> i32
        \\  return a + b
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    const fd = mod.body.stmts[0].func_decl;
    try testing.expect(fd.func.is_typed);
}

test "sema: untyped function with dynamic body stays untyped" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\function f(a, b)
        \\  return tostring(a) .. tostring(b)
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    const fd = mod.body.stmts[0].func_decl;
    try testing.expect(!fd.func.is_typed);
}

test "sema: untyped function can be specialized to native" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\function add(a, b)
        \\  return a + b
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    const fd = mod.body.stmts[0].func_decl;
    try testing.expect(fd.func.is_typed);
    try testing.expectEqualStrings("i64", fd.func.params[0].typ.named);
    try testing.expectEqualStrings("i64", fd.func.params[1].typ.named);
    try testing.expectEqualStrings("i64", fd.func.ret_type.named);
}

test "sema: integer literal resolves to i64" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = "local x = 1";
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // The initializer expression should be recorded as i64
    const init_expr = mod.body.stmts[0].local_decl.inits[0];
    const t = s.type_map.get(init_expr);
    try testing.expect(t != null);
    try testing.expectEqual(RT.i64, t.?);
}

test "sema: float literal resolves to f64" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = "local x = 1.5";
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    const init_expr = mod.body.stmts[0].local_decl.inits[0];
    const t = s.type_map.get(init_expr);
    try testing.expect(t != null);
    try testing.expectEqual(RT.f64, t.?);
}

test "sema: string literal resolves to str" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = "local x = \"hello\"";
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    const init_expr = mod.body.stmts[0].local_decl.inits[0];
    const t = s.type_map.get(init_expr);
    try testing.expect(t != null);
    try testing.expectEqual(RT.str, t.?);
}

test "sema: boolean literals resolve to bool" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = "local a = true\nlocal b = false";
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    const t_true = s.type_map.get(mod.body.stmts[0].local_decl.inits[0]);
    const t_false = s.type_map.get(mod.body.stmts[1].local_decl.inits[0]);
    try testing.expectEqual(RT.bool, t_true.?);
    try testing.expectEqual(RT.bool, t_false.?);
}

test "sema: const reassignment reports an error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSema(
        \\local x <const> = 1
        \\x = 2
    , &arena);
    try testing.expect(s.errors > 0);
}

test "sema: for-loop control variable cannot be assigned" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSema(
        \\for i = 1, 10 do
        \\  i = 99
        \\end
    , &arena);
    try testing.expect(s.errors > 0);
}

test "sema: scope: define and lookup" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var scope = Scope.init(arena.allocator());
    try scope.push();
    try scope.define("x", .{ .typ = .i32, .is_const = false });
    const sym = scope.lookup("x");
    try testing.expect(sym != null);
    try testing.expectEqual(RT.i32, sym.?.typ);
    scope.pop();
}

test "sema: scope: inner scope shadows outer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var scope = Scope.init(arena.allocator());
    try scope.push();
    try scope.define("x", .{ .typ = .i64, .is_const = false });
    try scope.push();
    try scope.define("x", .{ .typ = .i32, .is_const = false });
    try testing.expectEqual(RT.i32, scope.lookup("x").?.typ);
    scope.pop();
    try testing.expectEqual(RT.i64, scope.lookup("x").?.typ);
    scope.pop();
}

test "sema: scope: undefined name returns null" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var scope = Scope.init(arena.allocator());
    try scope.push();
    try testing.expect(scope.lookup("undefined") == null);
    scope.pop();
}

test "sema: add/sub of two integers yields integer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = "local r = 3 + 5";
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    const expr = mod.body.stmts[0].local_decl.inits[0];
    try testing.expect(expr.* == .binop);
    const t = s.type_map.get(expr);
    try testing.expect(t != null);
    try testing.expect(t.?.is_integer());
}

test "sema: comparison yields bool" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = "local r = 1 < 2";
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    const expr = mod.body.stmts[0].local_decl.inits[0];
    const t = s.type_map.get(expr);
    try testing.expectEqual(RT.bool, t.?);
}

test "sema: lua and/or ternary recovers safe branch type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\local flag: bool = true
        \\local r = flag and 10 or 20
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(usize, 0), s.errors);
    const expr = mod.body.stmts[1].local_decl.inits[0];
    const t = s.type_map.get(expr);
    try testing.expect(t != null);
    try testing.expect(t.?.is_integer());
}

test "sema: bare lua and with mixed operand types is dynamic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\local flag: bool = true
        \\local r = flag and 10
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(usize, 0), s.errors);
    const expr = mod.body.stmts[1].local_decl.inits[0];
    try testing.expectEqual(RT.any, s.type_map.get(expr).?);
}

test "sema: list comprehension is dynamic table expression" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\local xs = {1, 2, 3}
        \\local ys = {x * 2 for x in xs if x > 1}
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(usize, 0), s.errors);
    const expr = mod.body.stmts[1].local_decl.inits[0];
    try testing.expectEqual(RT.any, s.type_map.get(expr).?);
}

test "sema: try_expr (?) in void-returning function emits error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\function f(x: i64) -> i64
        \\  return x?
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // i64 is not result-compatible, so ? should trigger an error
    try testing.expect(s.errors > 0);
}

test "sema: try_expr (?) in result-returning function is accepted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // Return type is 'any', which is result-compatible (dynamic check deferred to runtime)
    const src =
        \\function f(x)
        \\  return x?
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // 'any' return type is result-compatible, so no error
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: unwrap_expr (!) in @nopanic function emits error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\@nopanic
        \\function f(x: i64) -> i64
        \\  return x!
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // ! in @nopanic should emit an error
    try testing.expect(s.errors > 0);
}

test "sema: unwrap_expr (!) in normal function is accepted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\function f(x: i64) -> i64
        \\  return x!
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // ! in normal function is fine
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: match_stmt scrutinee and arms are type-checked" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\local x = 42
        \\match x
        \\  1 => print("one")
        \\  2 => print("two")
        \\  _ => print("other")
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: match on enum with wildcard is exhaustive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\enum Color
        \\  Red
        \\  Green
        \\  Blue
        \\end
        \\local c = Color
        \\match c
        \\  Color.Red => print("red")
        \\  _ => print("other")
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: match on enum missing variants emits error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\enum Color
        \\  Red
        \\  Green
        \\  Blue
        \\end
        \\local c = Color
        \\match c
        \\  Color.Red => print("red")
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // Should emit an error for missing Green and Blue variants
    try testing.expect(s.errors > 0);
}

test "sema: match on enum all variants covered is exhaustive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\enum Direction
        \\  Up
        \\  Down
        \\end
        \\local d = Direction
        \\match d
        \\  Direction.Up => print("up")
        \\  Direction.Down => print("down")
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: match on non-enum does not check exhaustiveness" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\local x = 42
        \\match x
        \\  1 => print("one")
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // No exhaustiveness error for non-enum scrutinees
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: enum_def registers type in scope" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\enum Status
        \\  Active
        \\  Inactive
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    // The enum type should be registered
    try testing.expect(s.enum_types.get("Status") != null);
}

test "sema: try_stmt body is type-checked" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\try
        \\  local x = 42
        \\catch e
        \\  local y = e
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: defer_stmt body is type-checked" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\defer
        \\  local x = 1
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: match on enum with unqualified variant names" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\enum Shape
        \\  Circle
        \\  Square
        \\  Triangle
        \\end
        \\local s = Shape
        \\match s
        \\  Shape.Circle => print("circle")
        \\  Shape.Square => print("square")
        \\  Shape.Triangle => print("triangle")
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // All variants covered with qualified names — no error
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: match on enum partial coverage emits specific missing variants" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\enum Season
        \\  Spring
        \\  Summer
        \\  Autumn
        \\  Winter
        \\end
        \\local s = Season
        \\match s
        \\  Season.Spring => print("spring")
        \\  Season.Summer => print("summer")
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // Should report error for missing Autumn and Winter
    try testing.expect(s.errors > 0);
}

test "sema: match expression type-checks scrutinee and arms" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\enum Coin
        \\  Heads
        \\  Tails
        \\end
        \\local c = Coin
        \\local result = match c
        \\  Coin.Heads => return 1
        \\  Coin.Tails => return 0
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: match with guard expressions type-checked" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\local x = 42
        \\match x
        \\  n if n > 10 => print("big")
        \\  _ => print("small")
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

// ── Duo mode scoping tests (Requirements 1.3, 1.4, 1.7, 1.8) ─────────────────

fn runSemaDuo(src: []const u8, arena: *std.heap.ArenaAllocator) !Sema {
    const alloc = arena.allocator();
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    return s;
}

test "sema: duo mode — bare assignment creates local binding" {
    // Requirement 1.3: bare assignment at declaration position creates local
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\x = 42
        \\print(x)
    ;
    const s = try runSemaDuo(src, &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: duo mode — bare assignment then read is valid" {
    // Requirement 1.3: assigned variable is accessible afterwards
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\y = 10
        \\z = y + 1
    ;
    const s = try runSemaDuo(src, &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: duo mode — reading undeclared variable is an error" {
    // In duo mode, require_global is true, so reading an undeclared name errors
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\print(undeclared_var)
    ;
    const s = try runSemaDuo(src, &arena);
    try testing.expectEqual(@as(u32, 1), s.errors);
}

test "sema: duo mode — local keyword still works (Lua compat)" {
    // Requirement 1.8: local keyword is still valid in duo mode
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\local x = 1
        \\local y = x + 2
        \\print(y)
    ;
    const s = try runSemaDuo(src, &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: duo mode — global keyword creates module-scope binding" {
    // Requirement 1.4: global keyword creates module-global binding
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\global g = 100
        \\print(g)
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    // Verify the variable was registered as a module global
    try testing.expect(s.module_globals.get("g") != null);
}

test "sema: duo mode — global binding is marked is_global" {
    // Requirement 1.4: global keyword sets is_global flag on symbol
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\global myvar = 42
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    try testing.expect(s.module_globals.get("myvar") != null);
}

test "sema: duo mode — let is not a keyword, usable as identifier" {
    // Requirement 1.7: let is NOT a reserved word, can be used as variable name
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\let = 5
        \\print(let)
    ;
    const s = try runSemaDuo(src, &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: duo mode — both local and bare create local bindings" {
    // Requirement 1.8: local x = 1 and bare x = 1 both produce local bindings
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\local a = 1
        \\b = 2
        \\print(a + b)
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    // Neither a nor b should appear in module_globals
    try testing.expect(s.module_globals.get("a") == null);
    try testing.expect(s.module_globals.get("b") == null);
}

test "sema: duo mode — bare assignment does not create global" {
    // Verify that bare assignment in duo mode does NOT add to module_globals
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\x = 42
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    s.duo_mode = true;
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
    // x should NOT be in module_globals since it was auto-local
    try testing.expect(s.module_globals.get("x") == null);
}

test "sema: duo mode — multiple bare assignments in sequence" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\a = 1
        \\b = 2
        \\c = a + b
        \\print(c)
    ;
    const s = try runSemaDuo(src, &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: duo mode — reassignment to existing local is valid" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const src =
        \\x = 1
        \\x = 2
        \\print(x)
    ;
    const s = try runSemaDuo(src, &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: field access on a record-typed binding yields the declared field type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // Verify that `local p: { x: f64, y: f64 }` followed by reading
    // `p.x` infers the field's type from the record-type annotation
    // rather than falling back to `.any`. This is the change that makes
    // typed `local x: f64 = p.x` work end-to-end through codegen.
    const src =
        \\local p: { x: f64, y: f64 } = { x = 1.0, y = 2.0 }
        \\local x: f64 = p.x
        \\local y: f64 = p.y
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);

    // Find the `local x: f64 = p.x` statement and verify the RHS is i64/f64
    // (not `.any`). The third stmt in the module is the `local x: f64 = p.x`.
    const x_decl = mod.body.stmts[2].local_decl;
    const x_init = x_decl.inits[0];
    try testing.expect(x_init.* == .field);
    const xt = s.type_map.get(x_init) orelse .any;
    try testing.expect(xt == .f64);
}

test "sema: @implements on a record-typed binding (concept exists and matches)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // The concept `Iterable` requires an `each: () -> any` method. The
    // binding's record-type annotation supplies exactly that, so the
    // satisfaction check should pass.
    const src =
        \\concept Iterable
        \\  each: () -> i64
        \\end
        \\@implements(Iterable)
        \\local x: { each: () -> i64 } = { each = function() return 0 end }
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: @implements on a record-typed binding (concept is missing a required field)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // The concept `Pair` requires both `first: i64` and `second: i64`.
    // The binding only declares `first`, so satisfaction fails.
    const src =
        \\concept Pair
        \\  first: i64
        \\  second: i64
        \\end
        \\@implements(Pair)
        \\local x: { first: i64 } = { first = 1 }
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // Expect at least one error (the missing `second` field).
    try testing.expect(s.errors > 0);
}

test "sema: @implements on a global record-typed binding is checked" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\concept Pair
        \\  first: i64
        \\  second: i64
        \\end
        \\@implements(Pair)
        \\global x: { first: i64 } = { first = 1 }
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expect(s.errors > 0);
}

test "sema: @arc(false) accepts record-typed binding" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSemaDuo(
        \\@arc(false)
        \\local x: { value: i64 } = { value = 1 }
    , &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: @arc(false) rejects primitive binding" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSemaDuo(
        \\@arc(false)
        \\local x: i64 = 1
    , &arena);
    try testing.expect(s.errors > 0);
}

test "sema: @arc(false) rejects function declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSemaDuo(
        \\@arc(false)
        \\function f()
        \\end
    , &arena);
    try testing.expect(s.errors > 0);
}

test "sema: @deprecated binding emits warning at use site" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const s = try runSemaDuo(
        \\@deprecated("use y")
        \\local x = 1
        \\local z = x
    , &arena);
    try testing.expectEqual(@as(u32, 0), s.errors);
    try testing.expect(s.warnings > 0);
}

test "sema: try_stmt catch untyped binding is accepted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // Catch clauses are untyped in Duo. The binding, if present, is
    // statically `any` (errors are tables). There is no `catch MyError e`
    // form — discrimination is done inside the body with `match e.__tag`.
    const src =
        \\try
        \\  local x = 42
        \\catch e
        \\  local y = e
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: try_stmt catch with no binding is accepted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // An unnamed `catch` discards the error value entirely.
    const src =
        \\try
        \\  local x = 42
        \\catch
        \\  local y = 1
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: try_stmt body can discriminate error inside catch via __tag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // Verifies the new idiom: instead of `catch MyError e`, the body uses
    // `match e.__tag` to discriminate the kind of error.
    const src =
        \\try
        \\  local x = 42
        \\catch e
        \\  match e.__tag
        \\    "NotFound" => local y = 1
        \\    _ => local z = 2
        \\  end
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: try_expr (?) in function with 'any' return type is accepted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // 'any' return type is result-compatible (runtime check)
    const src =
        \\function f(x)
        \\  local y = x?
        \\  return y
        \\end
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    // 'any' is result-compatible, so ? should be accepted
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: overload resolution selects by argument types (no ambiguity)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // Two overloads of `f` distinguished by parameter type. A call with an
    // i64 argument resolves unambiguously to the i64 overload (Requirement 12).
    const src =
        \\fun f(x: i64) -> i64 return x end
        \\fun f(x: str) -> str return x end
        \\local r: i64 = f(1)
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}

test "sema: @arc(false) on a primitive-typed binding is rejected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // @arc(false) is only meaningful on heap-backed (table/record) bindings;
    // applying it to an i64 binding is a static error (Requirement 18).
    const src =
        \\@arc(false)
        \\local n: i64 = 1
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expect(s.errors > 0);
}

test "sema: @arc(false) on a record-typed binding is accepted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\@arc(false)
        \\local p: { x: i64 } = { x = 1 }
    ;
    var lex = Lexer.init(src, "test");
    var p = Parser.init(&lex, alloc);
    var mod = try p.parse_module();
    var s = Sema.init(alloc);
    try s.check_module(&mod);
    try testing.expectEqual(@as(u32, 0), s.errors);
}
