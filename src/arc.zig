//! ARC insertion pass (Requirement 26): a static analysis over the typed AST
//! that decides where the generated C must `duo_retain` / `duo_release` /
//! `duo_close` heap-allocated values, and which aggregates must be registered
//! with the cycle collector.
//!
//! ## What gets reference-counted
//!
//! Only statically heap-backed types: strings, tables/records, closures,
//! arrays, options/results, enums (with payloads), channels, and instantiated
//! generics. Primitive scalars (ints, floats, bool, SIMD vectors) are never
//! counted. Dynamic `any` values are left to the runtime (they carry their own
//! header), and any binding marked `@arc(false)` is skipped (Requirement 26.8).
//!
//! ## The balance invariant
//!
//! Every heap binding is `retain`ed where it is introduced and `release`d at
//! scope exit; a reassignment `release`s the old value and `retain`s the new
//! one. As a result the retains and releases for any value are balanced, so the
//! reference count returns to zero exactly when no live reference remains
//! (Requirement 26.1, 26.2). To-be-closed bindings (`<close>`) get a `close`
//! emitted immediately before their `release` (Requirement 26.5).
//!
//! Codegen consumes the produced annotations in Task 12.3; until then the pass
//! runs in the pipeline (Task 9.4) and is exercised by its own tests.

const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");
const sema_mod = @import("sema.zig");

const Allocator = std.mem.Allocator;
const RT = types.ResolvedType;
const TypeMap = sema_mod.TypeMap;

pub const ArcOp = enum { retain, release, close };

/// A single ARC action the codegen must emit, attached to a binding.
pub const Annotation = struct {
    op: ArcOp,
    /// Name of the binding this action applies to.
    var_name: []const u8,
    loc: ast.Loc,
    ty: RT,
};

/// A binding currently live in some lexical scope.
const Tracked = struct {
    name: []const u8,
    loc: ast.Loc,
    ty: RT,
    is_close: bool,
};

pub const ArcPass = struct {
    alloc: Allocator,
    type_map: *const TypeMap,

    /// Ordered list of retain/release/close actions (Task 9.2).
    annotations: std.ArrayListUnmanaged(Annotation) = .empty,
    /// Aggregate literals that may participate in reference cycles (Task 9.3).
    cycle_candidates: std.ArrayListUnmanaged(*const ast.Expr) = .empty,
    /// Lexical scope stack; each scope owns the bindings declared inside it.
    scopes: std.ArrayListUnmanaged(std.ArrayListUnmanaged(Tracked)) = .empty,

    const Self = @This();
    const Error = std.mem.Allocator.Error;

    pub fn init(alloc: Allocator, type_map: *const TypeMap) Self {
        return .{ .alloc = alloc, .type_map = type_map };
    }

    pub fn deinit(self: *Self) void {
        self.annotations.deinit(self.alloc);
        self.cycle_candidates.deinit(self.alloc);
        for (self.scopes.items) |*s| s.deinit(self.alloc);
        self.scopes.deinit(self.alloc);
    }

    pub fn run(self: *Self, module: *const ast.Module) Error!void {
        try self.processBlock(&module.body);
    }

    // ── Counting helpers (used by tests / callers) ──────────────────────────

    pub fn countOp(self: *const Self, op: ArcOp) usize {
        var n: usize = 0;
        for (self.annotations.items) |a| {
            if (a.op == op) n += 1;
        }
        return n;
    }

    pub fn cycleCandidateCount(self: *const Self) usize {
        return self.cycle_candidates.items.len;
    }

    // ── Scope management ────────────────────────────────────────────────────

    fn pushScope(self: *Self) Error!void {
        try self.scopes.append(self.alloc, .empty);
    }

    /// Release every binding in the current scope in reverse (LIFO) order,
    /// closing to-be-closed bindings first, then drop the scope.
    fn popScope(self: *Self) Error!void {
        if (self.scopes.items.len == 0) return;
        var scope = self.scopes.pop().?;
        var i = scope.items.len;
        while (i > 0) {
            i -= 1;
            const t = scope.items[i];
            if (t.is_close) try self.emit(.close, t.name, t.loc, t.ty);
            try self.emit(.release, t.name, t.loc, t.ty);
        }
        scope.deinit(self.alloc);
    }

    fn track(self: *Self, t: Tracked) Error!void {
        if (self.scopes.items.len == 0) return;
        try self.scopes.items[self.scopes.items.len - 1].append(self.alloc, t);
    }

    /// Look up a tracked binding by name across all live scopes (innermost
    /// first). Returns its type if found and heap-managed.
    fn lookup(self: *Self, name: []const u8) ?Tracked {
        var i = self.scopes.items.len;
        while (i > 0) {
            i -= 1;
            const scope = self.scopes.items[i];
            var j = scope.items.len;
            while (j > 0) {
                j -= 1;
                if (std.mem.eql(u8, scope.items[j].name, name)) return scope.items[j];
            }
        }
        return null;
    }

    fn emit(self: *Self, op: ArcOp, name: []const u8, loc: ast.Loc, ty: RT) Error!void {
        try self.annotations.append(self.alloc, .{ .op = op, .var_name = name, .loc = loc, .ty = ty });
    }

    // ── Statement / block walking ───────────────────────────────────────────

    fn processBlock(self: *Self, block: *const ast.Block) Error!void {
        try self.pushScope();
        for (block.stmts) |*stmt| try self.processStmt(stmt);
        if (block.tail_expr) |e| try self.processExpr(e);
        try self.popScope();
    }

    fn processStmt(self: *Self, stmt: *const ast.Stmt) Error!void {
        switch (stmt.*) {
            .local_decl => |d| {
                for (d.inits) |e| try self.processExpr(e);
                for (d.names, 0..) |lname, idx| {
                    if (hasArcFalse(lname.attributes)) continue;
                    const ty = self.bindingType(lname, if (idx < d.inits.len) d.inits[idx] else null);
                    if (!needsArc(ty)) continue;
                    try self.emit(.retain, lname.ident, lname.loc, ty);
                    try self.track(.{
                        .name = lname.ident,
                        .loc = lname.loc,
                        .ty = ty,
                        .is_close = isClose(lname.attrib),
                    });
                }
            },
            .global_decl => |d| {
                // Module globals are roots: retained for the program's lifetime,
                // never released at scope exit.
                for (d.inits) |e| try self.processExpr(e);
                for (d.names, 0..) |lname, idx| {
                    if (hasArcFalse(lname.attributes)) continue;
                    const ty = self.bindingType(lname, if (idx < d.inits.len) d.inits[idx] else null);
                    if (needsArc(ty)) try self.emit(.retain, lname.ident, lname.loc, ty);
                }
            },
            .const_decl => |d| try self.processExpr(d.val),
            .assign => |a| {
                for (a.values) |e| try self.processExpr(e);
                for (a.targets) |t| try self.processExpr(t);
                // Reassignment of a tracked heap binding: release old, retain new.
                for (a.targets) |t| {
                    if (t.* == .name) {
                        if (self.lookup(t.name.ident)) |tracked| {
                            if (needsArc(tracked.ty)) {
                                try self.emit(.release, tracked.name, t.name.loc, tracked.ty);
                                try self.emit(.retain, tracked.name, t.name.loc, tracked.ty);
                            }
                        }
                    }
                }
            },
            .call_stmt => |c| try self.processExpr(c.expr),
            .expr_stmt => |e| try self.processExpr(e.expr),
            .do_block => |d| try self.processBlock(&d.body),
            .while_loop => |w| {
                try self.processExpr(w.cond);
                try self.processBlock(&w.body);
            },
            .repeat_loop => |r| {
                try self.processBlock(&r.body);
                try self.processExpr(r.cond);
            },
            .if_stmt => |i| {
                try self.processExpr(i.cond);
                try self.processBlock(&i.then);
                for (i.elseifs) |ei| {
                    try self.processExpr(ei.cond);
                    try self.processBlock(&ei.body);
                }
                if (i.else_body) |eb| try self.processBlock(&eb);
            },
            .num_for => |f| {
                try self.processExpr(f.start);
                try self.processExpr(f.stop);
                if (f.step) |s| try self.processExpr(s);
                try self.processBlock(&f.body);
            },
            .gen_for => |f| {
                for (f.iters) |e| try self.processExpr(e);
                try self.processBlock(&f.body);
            },
            .func_decl => |fd| try self.processFuncBody(&fd.func),
            .ret => |r| for (r.vals) |e| try self.processExpr(e),
            .match_stmt => |m| try self.processMatch(&m),
            .try_stmt => |t| {
                try self.processBlock(&t.body);
                for (t.catches) |c| try self.processBlock(&c.body);
                for (t.defers) |d| try self.processBlock(&d.body);
            },
            .defer_stmt => |d| try self.processBlock(&d.body),
            .brk, .goto_stmt, .label_stmt, .enum_def, .concept_def, .alias_def => {},
        }
    }

    fn processMatch(self: *Self, m: *const ast.MatchExpr) Error!void {
        try self.processExpr(m.scrutinee);
        for (m.arms) |arm| {
            if (arm.guard) |g| try self.processExpr(g);
            try self.processBlock(&arm.body);
        }
    }

    /// A function body introduces its own scope; parameters are owned by the
    /// caller (retained at the call site), so they are not retained here.
    fn processFuncBody(self: *Self, fb: *const ast.FuncBody) Error!void {
        try self.pushScope();
        // Heap-typed upvalues captured by a closure are retained at the capture.
        for (fb.upvalues) |uv| {
            if (uv.is_local) {
                if (self.lookup(uv.name)) |tracked| {
                    if (needsArc(tracked.ty)) try self.emit(.retain, tracked.name, fb.loc, tracked.ty);
                }
            }
        }
        for (fb.body.stmts) |*stmt| try self.processStmt(stmt);
        try self.popScope();
    }

    // ── Expression walking ──────────────────────────────────────────────────

    fn processExpr(self: *Self, expr: *const ast.Expr) Error!void {
        switch (expr.*) {
            .call => |c| {
                try self.processExpr(c.func);
                for (c.args) |a| try self.processExpr(a);
            },
            .method_call => |m| {
                try self.processExpr(m.obj);
                for (m.args) |a| try self.processExpr(a);
            },
            .index => |i| {
                try self.processExpr(i.obj);
                try self.processExpr(i.key);
            },
            .field => |f| try self.processExpr(f.obj),
            .binop => |b| {
                try self.processExpr(b.lhs);
                try self.processExpr(b.rhs);
            },
            .unop => |u| try self.processExpr(u.operand),
            .func_expr => |fb| try self.processFuncBody(fb),
            .table => |t| {
                var holds_ref = false;
                for (t.fields) |fld| switch (fld) {
                    .indexed => |kv| {
                        try self.processExpr(kv.key);
                        try self.processExpr(kv.val);
                        if (self.exprCanHoldRef(kv.val)) holds_ref = true;
                    },
                    .named => |nv| {
                        try self.processExpr(nv.val);
                        if (self.exprCanHoldRef(nv.val)) holds_ref = true;
                    },
                    .positional => |p| {
                        try self.processExpr(p);
                        if (self.exprCanHoldRef(p)) holds_ref = true;
                    },
                };
                // A table whose fields can themselves hold references may form a
                // cycle and must be registered with the cycle collector.
                if (holds_ref) try self.cycle_candidates.append(self.alloc, expr);
            },
            .try_expr => |t| try self.processExpr(t.operand),
            .unwrap_expr => |u| try self.processExpr(u.operand),
            .match_expr => |m| try self.processMatch(m),
            .await_expr => |a| try self.processExpr(a.operand),
            .contains_expr => |c| {
                try self.processExpr(c.lhs);
                try self.processExpr(c.rhs);
            },
            .nil, .true_lit, .false_lit, .int_lit, .float_lit, .string_lit, .vararg, .name => {},
        }
    }

    // ── Type helpers ────────────────────────────────────────────────────────

    /// Determine a binding's type: prefer its annotation, else the static type
    /// of its initializer, else `any`.
    fn bindingType(self: *Self, lname: ast.LocalName, init_expr: ?*const ast.Expr) RT {
        if (lname.typ != .inferred) {
            return types.resolve(lname.typ, null, self.alloc) catch .any;
        }
        if (init_expr) |e| return self.type_map.get(e) orelse .any;
        return .any;
    }

    /// True if an expression's static type is an aggregate that could itself
    /// hold references (used for cycle-candidate detection).
    fn exprCanHoldRef(self: *Self, e: *const ast.Expr) bool {
        if (e.* == .table) return true;
        const t = self.type_map.get(e) orelse return false;
        return switch (t) {
            .table_type, .@"struct", .array, .instantiated, .any => true,
            else => false,
        };
    }
};

// ── Free helpers ──────────────────────────────────────────────────────────

/// Heap-allocated types are reference-counted; scalars and runtime-managed
/// `any` values are not.
pub fn needsArc(t: RT) bool {
    return switch (t) {
        .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .f32, .f64 => false,
        .bool, .void, .nil, .never => false,
        .v4f64, .v4i64, .v8f32, .v8i32 => false,
        .any => false, // dynamic values carry their own runtime header
        .str, .array, .pointer, .func, .@"struct" => true,
        .result, .option, .enum_type, .channel, .table_type, .instantiated, .generic_param => true,
    };
}

fn isClose(attrib: ?[]const u8) bool {
    const a = attrib orelse return false;
    return std.mem.eql(u8, a, "close");
}

fn hasArcFalse(attributes: []const ast.Attribute) bool {
    for (attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "arc")) {
            if (attr.args) |args| {
                if (std.mem.eql(u8, args, "false")) return true;
            }
        }
    }
    return false;
}

// ── Tests ─────────────────────────────────────────────────────────────────

const testing = std.testing;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = sema_mod.Sema;

const Harness = struct {
    arena: std.heap.ArenaAllocator,
    mod: ast.Module,
    sema: Sema,

    fn run(src: []const u8) !Harness {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        const alloc = arena.allocator();
        var lex = Lexer.init(src, "test");
        var p = Parser.init(&lex, alloc);
        const mod = try p.parse_module();
        var s = Sema.init(alloc);
        try s.check_module(@constCast(&mod));
        return .{ .arena = arena, .mod = mod, .sema = s };
    }

    fn deinit(self: *Harness) void {
        self.arena.deinit();
    }
};

test "arc: primitive bindings produce no ARC annotations" {
    var h = try Harness.run(
        \\local a: i64 = 1
        \\local b: f64 = 2.0
        \\local c: bool = true
    );
    defer h.deinit();

    var arc = ArcPass.init(h.arena.allocator(), &h.sema.type_map);
    defer arc.deinit();
    try arc.run(&h.mod);

    try testing.expectEqual(@as(usize, 0), arc.annotations.items.len);
}

test "arc: a heap binding is retained once and released once (balanced)" {
    var h = try Harness.run(
        \\local s: str = "hello"
    );
    defer h.deinit();

    var arc = ArcPass.init(h.arena.allocator(), &h.sema.type_map);
    defer arc.deinit();
    try arc.run(&h.mod);

    try testing.expectEqual(@as(usize, 1), arc.countOp(.retain));
    try testing.expectEqual(@as(usize, 1), arc.countOp(.release));
}

test "arc: retains and releases are always balanced (refcount returns to zero)" {
    var h = try Harness.run(
        \\local a: str = "x"
        \\local p: { x: i64 } = { x = 1 }
        \\local b: str = "y"
    );
    defer h.deinit();

    var arc = ArcPass.init(h.arena.allocator(), &h.sema.type_map);
    defer arc.deinit();
    try arc.run(&h.mod);

    // Three heap bindings → 3 retains, all released at block exit.
    try testing.expectEqual(@as(usize, 3), arc.countOp(.retain));
    try testing.expectEqual(arc.countOp(.retain), arc.countOp(.release));
}

test "arc: reassignment releases the old value and retains the new one" {
    var h = try Harness.run(
        \\local s: str = "a"
        \\s = "b"
    );
    defer h.deinit();

    var arc = ArcPass.init(h.arena.allocator(), &h.sema.type_map);
    defer arc.deinit();
    try arc.run(&h.mod);

    // bind retain + reassign retain = 2; reassign release + scope-exit release = 2.
    try testing.expectEqual(@as(usize, 2), arc.countOp(.retain));
    try testing.expectEqual(@as(usize, 2), arc.countOp(.release));
}

test "arc: @arc(false) binding is skipped" {
    var h = try Harness.run(
        \\@arc(false)
        \\local p: { x: i64 } = { x = 1 }
    );
    defer h.deinit();

    var arc = ArcPass.init(h.arena.allocator(), &h.sema.type_map);
    defer arc.deinit();
    try arc.run(&h.mod);

    try testing.expectEqual(@as(usize, 0), arc.annotations.items.len);
}

test "arc: to-be-closed binding emits close before release" {
    var h = try Harness.run(
        \\local p: { x: i64 } <close> = { x = 1 }
    );
    defer h.deinit();

    var arc = ArcPass.init(h.arena.allocator(), &h.sema.type_map);
    defer arc.deinit();
    try arc.run(&h.mod);

    try testing.expectEqual(@as(usize, 1), arc.countOp(.close));
    try testing.expectEqual(@as(usize, 1), arc.countOp(.release));
    // The close must be emitted before the release.
    var close_idx: ?usize = null;
    var release_idx: ?usize = null;
    for (arc.annotations.items, 0..) |a, idx| {
        if (a.op == .close) close_idx = idx;
        if (a.op == .release) release_idx = idx;
    }
    try testing.expect(close_idx.? < release_idx.?);
}

test "arc: nested table is registered as a cycle candidate" {
    var h = try Harness.run(
        \\local outer = { inner = { v = 1 } }
    );
    defer h.deinit();

    var arc = ArcPass.init(h.arena.allocator(), &h.sema.type_map);
    defer arc.deinit();
    try arc.run(&h.mod);

    try testing.expect(arc.cycleCandidateCount() >= 1);
}
