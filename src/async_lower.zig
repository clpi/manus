//! Async lowering pass (Requirement 19): transforms each `async` function into a
//! description of a stackless state machine that codegen (Task 12.4) turns into
//! a frame struct + step function.
//!
//! ## Model
//!
//! Each `await` expression is a state boundary: the step function runs straight-
//! line code until an await, returns `DUO_POLL_PENDING`, and resumes at the next
//! state when polled again. The frame struct holds the current `state`, the
//! result slot, and every parameter/local that must survive across a suspension
//! (we conservatively capture all of them). `defer` statements are collected so
//! the scheduler can run them in LIFO order if the task is cancelled at an await
//! point (Requirement 19.10).
//!
//! This pass produces only the *descriptor* (`LoweredAsync`); it does not mutate
//! the AST. Codegen consumes the descriptors via the `CodeGen.async_lower` hook.

const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");
const sema_mod = @import("sema.zig");

const Allocator = std.mem.Allocator;
const RT = types.ResolvedType;
const TypeMap = sema_mod.TypeMap;

/// Poll result returned by a step function.
pub const PollResult = enum { pending, ready, error_ };

/// Reserved state numbers; per-function await points are numbered from here.
pub const reserved_states: u32 = 1; // state 0 = start
pub const cancelled_state: u32 = std.math.maxInt(u32);

/// One `await` point — a suspension boundary within an async function.
pub const AwaitPoint = struct {
    /// State value the frame holds while suspended at this point.
    state: u32,
    /// The expression being awaited.
    operand: *const ast.Expr,
    loc: ast.Loc,
};

/// A field that must live in the async frame (parameter or local).
pub const FrameField = struct {
    name: []const u8,
    ty: RT,
};

/// The lowering descriptor for one async function.
pub const LoweredAsync = struct {
    /// Source name (function name, or "lambda" for anonymous async closures).
    name: []const u8,
    /// The async function body this descriptor lowers.
    template: *const ast.FuncBody,
    frame_type_name: []const u8,
    step_func_name: []const u8,
    ret_ty: RT,
    await_points: []AwaitPoint,
    /// `defer` bodies, in source order. Cancellation runs them in reverse.
    defers: []const *const ast.DeferStmt,
    /// Parameters + locals captured into the frame.
    frame_fields: []FrameField,
};

pub const AsyncLower = struct {
    alloc: Allocator,
    type_map: *const TypeMap,

    lowered: std.ArrayListUnmanaged(LoweredAsync) = .empty,
    name_counter: u32 = 0,

    const Self = @This();
    const Error = std.mem.Allocator.Error;

    pub fn init(alloc: Allocator, type_map: *const TypeMap) Self {
        return .{ .alloc = alloc, .type_map = type_map };
    }

    pub fn deinit(self: *Self) void {
        self.lowered.deinit(self.alloc);
    }

    pub fn count(self: *const Self) usize {
        return self.lowered.items.len;
    }

    pub fn getAll(self: *const Self) []const LoweredAsync {
        return self.lowered.items;
    }

    /// Run the pass: find every async function (including nested closures) and
    /// produce a lowering descriptor for each.
    pub fn run(self: *Self, module: *const ast.Module) Error!void {
        try self.discoverBlock(&module.body, "");
    }

    // ── Discovery: find async function bodies anywhere in the tree ───────────

    fn discoverBlock(self: *Self, block: *const ast.Block, enclosing_name: []const u8) Error!void {
        for (block.stmts) |*stmt| try self.discoverStmt(stmt, enclosing_name);
        if (block.tail_expr) |e| try self.discoverExpr(e, enclosing_name);
    }

    fn discoverStmt(self: *Self, stmt: *const ast.Stmt, enclosing_name: []const u8) Error!void {
        switch (stmt.*) {
            .func_decl => |fd| {
                const name = if (fd.path.len > 0) fd.path[fd.path.len - 1] else "fn";
                if (fd.func.is_async) try self.lower(name, &fd.func);
                try self.discoverBlock(&fd.func.body, name);
            },
            .local_decl => |d| for (d.inits) |e| try self.discoverExpr(e, enclosing_name),
            .global_decl => |d| for (d.inits) |e| try self.discoverExpr(e, enclosing_name),
            .const_decl => |d| try self.discoverExpr(d.val, enclosing_name),
            .assign => |a| {
                for (a.values) |e| try self.discoverExpr(e, enclosing_name);
                for (a.targets) |e| try self.discoverExpr(e, enclosing_name);
            },
            .call_stmt => |c| try self.discoverExpr(c.expr, enclosing_name),
            .expr_stmt => |e| try self.discoverExpr(e.expr, enclosing_name),
            .do_block => |d| try self.discoverBlock(&d.body, enclosing_name),
            .while_loop => |w| {
                try self.discoverExpr(w.cond, enclosing_name);
                try self.discoverBlock(&w.body, enclosing_name);
            },
            .repeat_loop => |r| {
                try self.discoverBlock(&r.body, enclosing_name);
                try self.discoverExpr(r.cond, enclosing_name);
            },
            .if_stmt => |i| {
                try self.discoverExpr(i.cond, enclosing_name);
                try self.discoverBlock(&i.then, enclosing_name);
                for (i.elseifs) |ei| {
                    try self.discoverExpr(ei.cond, enclosing_name);
                    try self.discoverBlock(&ei.body, enclosing_name);
                }
                if (i.else_body) |eb| try self.discoverBlock(&eb, enclosing_name);
            },
            .num_for => |f| {
                try self.discoverExpr(f.start, enclosing_name);
                try self.discoverExpr(f.stop, enclosing_name);
                if (f.step) |s| try self.discoverExpr(s, enclosing_name);
                try self.discoverBlock(&f.body, enclosing_name);
            },
            .gen_for => |f| {
                for (f.iters) |e| try self.discoverExpr(e, enclosing_name);
                try self.discoverBlock(&f.body, enclosing_name);
            },
            .ret => |r| for (r.vals) |e| try self.discoverExpr(e, enclosing_name),
            .match_stmt => |m| try self.discoverMatch(&m, enclosing_name),
            .try_stmt => |t| {
                try self.discoverBlock(&t.body, enclosing_name);
                for (t.catches) |c| try self.discoverBlock(&c.body, enclosing_name);
                for (t.defers) |d| try self.discoverBlock(&d.body, enclosing_name);
            },
            .defer_stmt => |d| try self.discoverBlock(&d.body, enclosing_name),
            .brk, .cont, .goto_stmt, .label_stmt, .enum_def, .concept_def, .alias_def, .macro_def, .cinclude, .directive => {},
        }
    }

    fn discoverMatch(self: *Self, m: *const ast.MatchExpr, enclosing_name: []const u8) Error!void {
        try self.discoverExpr(m.scrutinee, enclosing_name);
        for (m.arms) |arm| {
            if (arm.guard) |g| try self.discoverExpr(g, enclosing_name);
            try self.discoverBlock(&arm.body, enclosing_name);
        }
    }

    fn discoverExpr(self: *Self, expr: *const ast.Expr, enclosing_name: []const u8) Error!void {
        switch (expr.*) {
            .func_expr => |fb| {
                if (fb.is_async) try self.lower("lambda", fb);
                try self.discoverBlock(&fb.body, enclosing_name);
            },
            .call => |c| {
                try self.discoverExpr(c.func, enclosing_name);
                for (c.args) |a| try self.discoverExpr(a, enclosing_name);
            },
            .method_call => |m| {
                try self.discoverExpr(m.obj, enclosing_name);
                for (m.args) |a| try self.discoverExpr(a, enclosing_name);
            },
            .index => |i| {
                try self.discoverExpr(i.obj, enclosing_name);
                try self.discoverExpr(i.key, enclosing_name);
            },
            .field => |f| try self.discoverExpr(f.obj, enclosing_name),
            .binop => |b| {
                try self.discoverExpr(b.lhs, enclosing_name);
                try self.discoverExpr(b.rhs, enclosing_name);
            },
            .unop => |u| try self.discoverExpr(u.operand, enclosing_name),
            .table => |t| for (t.fields) |fld| switch (fld) {
                .indexed => |kv| {
                    try self.discoverExpr(kv.key, enclosing_name);
                    try self.discoverExpr(kv.val, enclosing_name);
                },
                .named => |nv| try self.discoverExpr(nv.val, enclosing_name),
                .positional => |p| try self.discoverExpr(p, enclosing_name),
                .spread => |sp| try self.discoverExpr(sp, enclosing_name),
                .semantic => |sm| try self.discoverExpr(sm.val, enclosing_name),
            },
            .list_comp => |lc| {
                try self.discoverExpr(lc.iter, enclosing_name);
                if (lc.filter) |filter| try self.discoverExpr(filter, enclosing_name);
                try self.discoverExpr(lc.value, enclosing_name);
            },
            .try_expr => |t| try self.discoverExpr(t.operand, enclosing_name),
            .unwrap_expr => |u| try self.discoverExpr(u.operand, enclosing_name),
            .if_expr => |ie| {
                try self.discoverExpr(ie.cond, enclosing_name);
                try self.discoverExpr(ie.then_expr, enclosing_name);
                try self.discoverExpr(ie.else_expr, enclosing_name);
            },
            .match_expr => |m| try self.discoverMatch(m, enclosing_name),
            .await_expr => |a| try self.discoverExpr(a.operand, enclosing_name),
            .contains_expr => |c| {
                try self.discoverExpr(c.lhs, enclosing_name);
                try self.discoverExpr(c.rhs, enclosing_name);
            },
            .range => |r| {
                try self.discoverExpr(r.start, enclosing_name);
                try self.discoverExpr(r.end, enclosing_name);
                if (r.step) |s| try self.discoverExpr(s, enclosing_name);
            },
            .quote, .unquote, .macro_call => unreachable,
            .nil, .true_lit, .false_lit, .int_lit, .float_lit, .quoted, .vararg, .name => {},
            // G1/G2: semantic identity and world are leaf nodes with no
            // async body to discover.
            .semantic, .semantic_scope => {},
            .sequence => |seq| {
                for (seq.exprs) |e| try self.discoverExpr(e, enclosing_name);
            },
        }
    }

    // ── Lowering one async function ──────────────────────────────────────────

    fn lower(self: *Self, name: []const u8, fb: *const ast.FuncBody) Error!void {
        self.name_counter += 1;

        var ctx = LowerCtx{
            .awaits = .empty,
            .defers = .empty,
            .fields = .empty,
            .next_state = reserved_states,
        };
        defer {
            ctx.awaits.deinit(self.alloc);
            ctx.defers.deinit(self.alloc);
            ctx.fields.deinit(self.alloc);
        }

        // Parameters are captured into the frame.
        for (fb.params) |p| {
            const ty = types.resolve(p.typ, null, self.alloc) catch .any;
            try ctx.fields.append(self.alloc, .{ .name = p.name, .ty = ty });
        }
        // Scan the body (not crossing nested functions) for awaits, defers, and
        // locals that must be captured.
        try self.scanBlock(&fb.body, &ctx);

        const frame_name = try std.fmt.allocPrint(self.alloc, "duo_frame_{s}_{d}", .{ name, self.name_counter });
        const step_name = try std.fmt.allocPrint(self.alloc, "duo_step_{s}_{d}", .{ name, self.name_counter });

        try self.lowered.append(self.alloc, .{
            .name = name,
            .template = fb,
            .frame_type_name = frame_name,
            .step_func_name = step_name,
            .ret_ty = types.resolve(fb.ret_type, null, self.alloc) catch .any,
            .await_points = try ctx.awaits.toOwnedSlice(self.alloc),
            .defers = try ctx.defers.toOwnedSlice(self.alloc),
            .frame_fields = try ctx.fields.toOwnedSlice(self.alloc),
        });
    }

    const LowerCtx = struct {
        awaits: std.ArrayListUnmanaged(AwaitPoint),
        defers: std.ArrayListUnmanaged(*const ast.DeferStmt),
        fields: std.ArrayListUnmanaged(FrameField),
        next_state: u32,
    };

    /// Scan a block for await points, defers, and local captures. Does NOT
    /// descend into nested function bodies — those get their own lowering.
    fn scanBlock(self: *Self, block: *const ast.Block, ctx: *LowerCtx) Error!void {
        for (block.stmts) |*stmt| try self.scanStmt(stmt, ctx);
        if (block.tail_expr) |e| try self.scanExpr(e, ctx);
    }

    fn scanStmt(self: *Self, stmt: *const ast.Stmt, ctx: *LowerCtx) Error!void {
        switch (stmt.*) {
            .local_decl => |d| {
                for (d.inits) |e| try self.scanExpr(e, ctx);
                for (d.names, 0..) |lname, idx| {
                    const ty = self.bindingType(lname, if (idx < d.inits.len) d.inits[idx] else null);
                    try ctx.fields.append(self.alloc, .{ .name = lname.ident, .ty = ty });
                }
            },
            .const_decl => |d| try self.scanExpr(d.val, ctx),
            .global_decl => |d| for (d.inits) |e| try self.scanExpr(e, ctx),
            .assign => |a| {
                for (a.values) |e| try self.scanExpr(e, ctx);
                for (a.targets) |e| try self.scanExpr(e, ctx);
            },
            .call_stmt => |c| try self.scanExpr(c.expr, ctx),
            .expr_stmt => |e| try self.scanExpr(e.expr, ctx),
            .do_block => |d| try self.scanBlock(&d.body, ctx),
            .while_loop => |w| {
                try self.scanExpr(w.cond, ctx);
                try self.scanBlock(&w.body, ctx);
            },
            .repeat_loop => |r| {
                try self.scanBlock(&r.body, ctx);
                try self.scanExpr(r.cond, ctx);
            },
            .if_stmt => |i| {
                try self.scanExpr(i.cond, ctx);
                try self.scanBlock(&i.then, ctx);
                for (i.elseifs) |ei| {
                    try self.scanExpr(ei.cond, ctx);
                    try self.scanBlock(&ei.body, ctx);
                }
                if (i.else_body) |eb| try self.scanBlock(&eb, ctx);
            },
            .num_for => |f| {
                try self.scanExpr(f.start, ctx);
                try self.scanExpr(f.stop, ctx);
                if (f.step) |s| try self.scanExpr(s, ctx);
                try ctx.fields.append(self.alloc, .{ .name = f.var_name, .ty = self.numForVarType(f) });
                try self.scanBlock(&f.body, ctx);
            },
            .gen_for => |f| {
                for (f.iters) |e| try self.scanExpr(e, ctx);
                for (f.vars) |v| try ctx.fields.append(self.alloc, .{ .name = v, .ty = .any });
                try self.scanBlock(&f.body, ctx);
            },
            // Nested function declarations are lowered separately; do not scan in.
            .func_decl => {},
            .ret => |r| for (r.vals) |e| try self.scanExpr(e, ctx),
            .match_stmt => |m| try self.scanMatch(&m, ctx),
            .try_stmt => |t| {
                try self.scanBlock(&t.body, ctx);
                for (t.catches) |c| try self.scanBlock(&c.body, ctx);
                for (t.defers) |*d| {
                    try ctx.defers.append(self.alloc, d);
                    try self.scanBlock(&d.body, ctx);
                }
            },
            .defer_stmt => |*d| {
                try ctx.defers.append(self.alloc, d);
                try self.scanBlock(&d.body, ctx);
            },
            .brk, .cont, .goto_stmt, .label_stmt, .enum_def, .concept_def, .alias_def, .macro_def, .cinclude, .directive => {},
        }
    }

    fn scanMatch(self: *Self, m: *const ast.MatchExpr, ctx: *LowerCtx) Error!void {
        try self.scanExpr(m.scrutinee, ctx);
        for (m.arms) |arm| {
            if (arm.guard) |g| try self.scanExpr(g, ctx);
            try self.scanBlock(&arm.body, ctx);
        }
    }

    fn scanExpr(self: *Self, expr: *const ast.Expr, ctx: *LowerCtx) Error!void {
        switch (expr.*) {
            .await_expr => |a| {
                try self.scanExpr(a.operand, ctx);
                try ctx.awaits.append(self.alloc, .{
                    .state = ctx.next_state,
                    .operand = a.operand,
                    .loc = a.loc,
                });
                ctx.next_state += 1;
            },
            .call => |c| {
                try self.scanExpr(c.func, ctx);
                for (c.args) |a| try self.scanExpr(a, ctx);
            },
            .method_call => |m| {
                try self.scanExpr(m.obj, ctx);
                for (m.args) |a| try self.scanExpr(a, ctx);
            },
            .index => |i| {
                try self.scanExpr(i.obj, ctx);
                try self.scanExpr(i.key, ctx);
            },
            .field => |f| try self.scanExpr(f.obj, ctx),
            .binop => |b| {
                try self.scanExpr(b.lhs, ctx);
                try self.scanExpr(b.rhs, ctx);
            },
            .unop => |u| try self.scanExpr(u.operand, ctx),
            // Do not cross into nested function bodies.
            .func_expr => {},
            .table => |t| for (t.fields) |fld| switch (fld) {
                .indexed => |kv| {
                    try self.scanExpr(kv.key, ctx);
                    try self.scanExpr(kv.val, ctx);
                },
                .named => |nv| try self.scanExpr(nv.val, ctx),
                .positional => |p| try self.scanExpr(p, ctx),
                .spread => |sp| try self.scanExpr(sp, ctx),
                .semantic => |sm| try self.scanExpr(sm.val, ctx),
            },
            .list_comp => |lc| {
                try self.scanExpr(lc.iter, ctx);
                if (lc.filter) |filter| try self.scanExpr(filter, ctx);
                try self.scanExpr(lc.value, ctx);
            },
            .try_expr => |t| try self.scanExpr(t.operand, ctx),
            .unwrap_expr => |u| try self.scanExpr(u.operand, ctx),
            .if_expr => |ie| {
                try self.scanExpr(ie.cond, ctx);
                try self.scanExpr(ie.then_expr, ctx);
                try self.scanExpr(ie.else_expr, ctx);
            },
            .match_expr => |m| try self.scanMatch(m, ctx),
            .contains_expr => |c| {
                try self.scanExpr(c.lhs, ctx);
                try self.scanExpr(c.rhs, ctx);
            },
            .range => |r| {
                try self.scanExpr(r.start, ctx);
                try self.scanExpr(r.end, ctx);
                if (r.step) |s| try self.scanExpr(s, ctx);
            },
            .quote, .unquote, .macro_call => unreachable,
            .semantic, .semantic_scope => {}, // semantic identity / world: no child exprs
            .nil, .true_lit, .false_lit, .int_lit, .float_lit, .quoted, .vararg, .name => {},
            .sequence => |seq| {
                for (seq.exprs) |e| try self.scanExpr(e, ctx);
            },
        }
    }

    fn bindingType(self: *Self, lname: ast.LocalName, init_expr: ?*const ast.Expr) RT {
        if (lname.typ != .inferred) return types.resolve(lname.typ, null, self.alloc) catch .any;
        if (init_expr) |e| return self.type_map.get(e) orelse .any;
        return .any;
    }

    fn numForVarType(self: *Self, f: anytype) RT {
        if (f.var_typ != .inferred) return types.resolve(f.var_typ, null, self.alloc) catch .any;
        return self.type_map.get(f.start) orelse .i64;
    }

    // ── C emission helpers (skeletons consumed/extended by codegen Task 12.4) ─

    /// Emit the `duo_Poll` enum once per compilation.
    pub fn emitPollEnum(writer: anytype) !void {
        try writer.writeAll(
            \\typedef enum { DUO_POLL_PENDING = 0, DUO_POLL_READY = 1, DUO_POLL_ERROR = 2 } duo_Poll;
            \\
        );
    }

    /// Emit the type-erased cooperative task ABI shared by all generated async
    /// functions. Concrete result storage remains in the function frame.
    pub fn emitTaskRuntime(writer: anytype) !void {
        try writer.writeAll(
            \\typedef enum { DUO_TASK_RUNNABLE = 0, DUO_TASK_READY = 1, DUO_TASK_ERROR = 2, DUO_TASK_CANCELLED = 3 } duo_TaskStatus;
            \\typedef struct duo_Task duo_Task;
            \\struct duo_Task {
            \\    duo_TaskStatus status;
            \\    bool cancel_requested;
            \\    lua_Value error;
            \\    void* frame;
            \\    duo_Poll (*step)(void* frame);
            \\    void (*destroy)(void* frame);
            \\};
            \\static inline void duo_task_cancel(duo_Task* task) {
            \\    if (task && task->status == DUO_TASK_RUNNABLE) task->cancel_requested = true;
            \\}
            \\static inline duo_Poll duo_task_poll(duo_Task* task) {
            \\    if (!task) return DUO_POLL_ERROR;
            \\    if (task->status == DUO_TASK_READY) return DUO_POLL_READY;
            \\    if (task->status == DUO_TASK_ERROR || task->status == DUO_TASK_CANCELLED) return DUO_POLL_ERROR;
            \\    duo_Poll poll = task->step(task->frame);
            \\    if (poll == DUO_POLL_READY) task->status = DUO_TASK_READY;
            \\    else if (poll == DUO_POLL_ERROR) { if (task->cancel_requested) task->status = DUO_TASK_CANCELLED; else task->status = DUO_TASK_ERROR; }
            \\    return poll;
            \\}
        );
    }

    /// Emit the cooperative event loop / run-queue runtime.  These functions
    /// have external linkage (no `static`) so that duo stdlib modules can bind
    /// to them via `@ffi`.  They depend on `duo_Task` / `duo_Poll` / `duo_task_poll`
    /// emitted by `emitTaskRuntime`, so must be called after it.
    pub fn emitEventLoopRuntime(writer: anytype) !void {
        try writer.writeAll(
            \\/* --- Cooperative event loop / run queue --- */
            \\#include <time.h>
            \\typedef struct {
            \\    duo_Task** tasks;
            \\    size_t count;
            \\    size_t capacity;
            \\} duo_RunQueue;
            \\
            \\duo_RunQueue duo_rq_create(void) {
            \\    duo_RunQueue rq = { NULL, 0, 0 };
            \\    return rq;
            \\}
            \\
            \\void duo_rq_push(duo_RunQueue* rq, duo_Task* task) {
            \\    if (rq->count >= rq->capacity) {
            \\        rq->capacity = rq->capacity ? rq->capacity * 2 : 8;
            \\        rq->tasks = (duo_Task**)realloc(rq->tasks, rq->capacity * sizeof(duo_Task*));
            \\    }
            \\    rq->tasks[rq->count++] = task;
            \\}
            \\
            \\int duo_rq_remove(duo_RunQueue* rq, size_t idx) {
            \\    if (idx >= rq->count) return -1;
            \\    rq->tasks[idx] = rq->tasks[rq->count - 1];
            \\    rq->count--;
            \\    return 0;
            \\}
            \\
            \\int duo_event_loop_run(duo_RunQueue* rq) {
            \\    int completed = 0;
            \\    while (rq->count > 0) {
            \\        size_t i = 0;
            \\        int round_completed = 0;
            \\        while (i < rq->count) {
            \\            duo_Poll poll = duo_task_poll(rq->tasks[i]);
            \\            if (poll == DUO_POLL_READY || poll == DUO_POLL_ERROR) {
            \\                round_completed++;
            \\                duo_rq_remove(rq, i);
            \\            } else {
            \\                i++;
            \\            }
            \\        }
            \\        completed += round_completed;
            \\        if (round_completed == 0) {
            \\#ifdef _WIN32
            \\            Sleep(1);
            \\#else
            \\            struct timespec ts = { 0, 1000000 };
            \\            nanosleep(&ts, NULL);
            \\#endif
            \\        }
            \\    }
            \\    return completed;
            \\}
            \\
            \\int duo_event_loop_run_once(duo_RunQueue* rq) {
            \\    int completed = 0;
            \\    size_t i = 0;
            \\    while (i < rq->count) {
            \\        duo_Poll poll = duo_task_poll(rq->tasks[i]);
            \\        if (poll == DUO_POLL_READY || poll == DUO_POLL_ERROR) {
            \\            completed++;
            \\            duo_rq_remove(rq, i);
            \\        } else {
            \\            i++;
            \\        }
            \\    }
            \\    return completed;
            \\}
            \\
            \\void duo_event_loop_spawn(duo_RunQueue* rq, duo_Task* task) {
            \\    if (!task) return;
            \\    duo_rq_push(rq, task);
            \\}
            \\
        );
    }

    /// Emit the frame struct for one lowered async function.
    pub fn emitFrameStruct(la: *const LoweredAsync, writer: anytype) !void {
        try writer.print("typedef struct {s} {{\n", .{la.frame_type_name});
        try writer.writeAll("    int state;\n");
        try writer.writeAll("    bool cancel_requested;\n");
        try writer.writeAll("    lua_Value error;\n");
        try writer.writeAll("    duo_Task* child;\n");
        try writer.print("    {s} result;\n", .{cTypeName(la.ret_ty)});
        for (la.frame_fields) |fld| {
            try writer.print("    {s} {s};\n", .{ cTypeName(fld.ty), fld.name });
        }
        try writer.print("}} {s};\n", .{la.frame_type_name});
    }

    /// Emit the step-function skeleton: a `switch (frame->state)` with one case
    /// per await point.
    pub fn emitStepFunc(la: *const LoweredAsync, writer: anytype) !void {
        try writer.print("static duo_Poll {s}({s}* frame) {{\n", .{ la.step_func_name, la.frame_type_name });
        try writer.writeAll("    if (frame->cancel_requested) {\n");
        try writer.writeAll("        if (frame->child) duo_task_cancel(frame->child);\n");
        try emitCancelCleanup(la, writer);
        try writer.print("        frame->state = {d};\n", .{cancelled_state});
        try writer.writeAll("        return DUO_POLL_ERROR;\n");
        try writer.writeAll("    }\n");
        try writer.writeAll("    switch (frame->state) {\n");
        try writer.writeAll("    case 0: /* start */\n");
        for (la.await_points) |ap| {
            try writer.print("    case {d}: /* await */\n", .{ap.state});
            try writer.writeAll("        {\n");
            try writer.writeAll("        duo_Poll child_poll = duo_task_poll(frame->child);\n");
            try writer.writeAll("        if (child_poll == DUO_POLL_PENDING) return DUO_POLL_PENDING;\n");
            try writer.writeAll("        if (child_poll == DUO_POLL_ERROR) {\n");
            try writer.writeAll("            if (frame->child) frame->error = frame->child->error;\n");
            try writer.writeAll("            return DUO_POLL_ERROR;\n");
            try writer.writeAll("        }\n");
            try writer.writeAll("        frame->child = NULL;\n");
            try writer.print("        frame->state = {d};\n", .{ap.state + 1});
            try writer.writeAll("        break;\n");
            try writer.writeAll("        }\n");
        }
        try writer.writeAll("    default:\n        return DUO_POLL_READY;\n");
        try writer.writeAll("    }\n}\n");
    }

    /// Emit cancellation cleanup: run pending defers in LIFO order
    /// (Requirement 19.10).
    pub fn emitCancelCleanup(la: *const LoweredAsync, writer: anytype) !void {
        var i = la.defers.len;
        while (i > 0) {
            i -= 1;
            try writer.print("    /* defer #{d} cleanup */\n", .{i});
        }
    }
};

/// Map a resolved type to a C type name for frame fields. DERIVED FROM THE ONE
/// OWNER: `types.cFrameType` is the async-frame face of the scalar roster, so the
/// eleven scalars plus `void` spell exactly as `c_type` emits them and every
/// dynamic value falls back to `lua_Value` — the retired hand-kept subset that
/// could only agree with `c_type` by hand.
fn cTypeName(t: RT) []const u8 {
    return types.cFrameType(t) orelse "lua_Value";
}

/// Pipeline guard (Requirement 25.4 / Task 10.3): async + WASM cannot use the
/// threaded scheduler. Returns an error when both are requested. The `--threads`
/// CLI flag that drives `threaded` is wired in Task 17.1.
pub fn validateTarget(is_wasm: bool, threaded: bool) error{WasmThreadsUnsupported}!void {
    if (is_wasm and threaded) return error.WasmThreadsUnsupported;
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

test "async: non-async functions are not lowered" {
    var h = try Harness.run(
        \\fun f(x: i64): i64 x
    );
    defer h.deinit();

    var al = AsyncLower.init(h.arena.allocator(), &h.sema.type_map);
    defer al.deinit();
    try al.run(&h.mod);

    try testing.expectEqual(@as(usize, 0), al.count());
}

test "async: an async function is lowered with one descriptor" {
    var h = try Harness.run(
        \\async fun f() -> i64
        \\  return 1
        \\end
    );
    defer h.deinit();

    var al = AsyncLower.init(h.arena.allocator(), &h.sema.type_map);
    defer al.deinit();
    try al.run(&h.mod);

    try testing.expectEqual(@as(usize, 1), al.count());
    const la = al.getAll()[0];
    try testing.expectEqualStrings("f", la.name);
}

test "async: each await becomes a state boundary with increasing states" {
    var h = try Harness.run(
        \\async fun g() -> i64
        \\  local a = await h()
        \\  local b = await h()
        \\  return a + b
        \\end
    );
    defer h.deinit();

    var al = AsyncLower.init(h.arena.allocator(), &h.sema.type_map);
    defer al.deinit();
    try al.run(&h.mod);

    const la = al.getAll()[0];
    try testing.expectEqual(@as(usize, 2), la.await_points.len);
    try testing.expectEqual(reserved_states, la.await_points[0].state);
    try testing.expectEqual(reserved_states + 1, la.await_points[1].state);
}

test "async: parameters and locals are captured into the frame" {
    var h = try Harness.run(
        \\async fun g(x: i64) -> i64
        \\  local y: i64 = 2
        \\  return x + y
        \\end
    );
    defer h.deinit();

    var al = AsyncLower.init(h.arena.allocator(), &h.sema.type_map);
    defer al.deinit();
    try al.run(&h.mod);

    const la = al.getAll()[0];
    var has_x = false;
    var has_y = false;
    for (la.frame_fields) |fld| {
        if (std.mem.eql(u8, fld.name, "x")) has_x = true;
        if (std.mem.eql(u8, fld.name, "y")) has_y = true;
    }
    try testing.expect(has_x and has_y);
}

test "async: emitted runtime and frame carry task lifecycle state" {
    var h = try Harness.run(
        \\async fun g() -> i64
        \\  return await h()
        \\end
    );
    defer h.deinit();
    var al = AsyncLower.init(h.arena.allocator(), &h.sema.type_map);
    defer al.deinit();
    try al.run(&h.mod);

    var aw: std.Io.Writer.Allocating = .init(h.arena.allocator());
    defer aw.deinit();
    try AsyncLower.emitTaskRuntime(&aw.writer);
    try AsyncLower.emitFrameStruct(&al.getAll()[0], &aw.writer);
    try AsyncLower.emitStepFunc(&al.getAll()[0], &aw.writer);
    const output = aw.written();
    try testing.expect(std.mem.indexOf(u8, output, "typedef struct duo_Task duo_Task;") != null);
    try testing.expect(std.mem.indexOf(u8, output, "duo_TaskStatus status;") != null);
    try testing.expect(std.mem.indexOf(u8, output, "bool cancel_requested;") != null);
    try testing.expect(std.mem.indexOf(u8, output, "lua_Value error;") != null);
    try testing.expect(std.mem.indexOf(u8, output, "duo_Task* child;") != null);
    try testing.expect(std.mem.indexOf(u8, output, "if (frame->cancel_requested)") != null);
    try testing.expect(std.mem.indexOf(u8, output, "duo_task_cancel(frame->child);") != null);
    try testing.expect(std.mem.indexOf(u8, output, "duo_task_poll(frame->child)") != null);
    try testing.expect(std.mem.indexOf(u8, output, "frame->error = frame->child->error;") != null);
    try testing.expect(std.mem.indexOf(u8, output, "DUO_POLL_ERROR") != null);
}

test "async: defers are collected for LIFO cancellation cleanup" {
    var h = try Harness.run(
        \\async fun g() -> i64
        \\  defer cleanup1() end
        \\  defer cleanup2() end
        \\  return await h()
        \\end
    );
    defer h.deinit();

    var al = AsyncLower.init(h.arena.allocator(), &h.sema.type_map);
    defer al.deinit();
    try al.run(&h.mod);

    const la = al.getAll()[0];
    try testing.expectEqual(@as(usize, 2), la.defers.len);
    try testing.expectEqual(@as(usize, 1), la.await_points.len);
}

test "async: nested async closure is lowered separately" {
    var h = try Harness.run(
        \\async fun outer() -> i64
        \\  async fun inner() -> i64
        \\    return await h()
        \\  end
        \\  return 0
        \\end
    );
    defer h.deinit();

    var al = AsyncLower.init(h.arena.allocator(), &h.sema.type_map);
    defer al.deinit();
    try al.run(&h.mod);

    // Both `outer` and the inner async closure are lowered.
    try testing.expectEqual(@as(usize, 2), al.count());
}

test "async: validateTarget rejects wasm + threads" {
    try testing.expectError(error.WasmThreadsUnsupported, validateTarget(true, true));
    try validateTarget(true, false);
    try validateTarget(false, true);
    try validateTarget(false, false);
}
