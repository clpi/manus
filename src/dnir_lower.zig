//! AST → DNIR lowering for typed native programs (no lua_Value, no C-string codegen).
//!
//! Produces graph-observed `native_ir.Module` input for physical realizers. Direct
//! remains canonical; the orthogonal C99 realizer consumes the same DNIR only when
//! explicitly selected and is never an auto, fallback, self-host, or release path.
//!
//! Entry points: Idol modules export functions at file scope (file-as-M). There is no
//! Python/Lua-style mandatory `main()` or special entry typing — any eligible function
//! lowers the same way; linker entry is `@export` / CLI target, not a magic name.
const std = @import("std");
const ast = @import("ast.zig");
const Expr = ast.Expr;
const types = @import("types.zig");
const comptime_eval = @import("comptime.zig");
const subject_home = @import("subject_home.zig");
const dnir = @import("native_ir.zig");
const dnir_hardware = @import("dnir_hardware.zig");
const semantic_graph = @import("semantic_graph.zig");
const place = @import("place.zig");
const home_resolve = @import("home_resolve.zig");
const tail_result_demand = @import("tail_result_demand.zig");
const table_facts = @import("table_facts.zig");
const collection_relation = @import("collection_relation.zig");
const host_taint = @import("host_taint.zig");
const RT = types.ResolvedType;

// DNIR only needs the machine class of a pointer. Its exact pointee descriptor
// remains on the semantic graph and on checked application instructions.
var pointer_pointee: RT = .void;
const physical_pointer: RT = .{ .pointer = &pointer_pointee };

pub const Error = error{
    UnsupportedConstruct,
    GraphFactsInvalid,
    OutOfMemory,
};

/// Caller-owned physical evidence for one lowering attempt.
///
/// The fixed buffer keeps refusal reporting allocation-free. A caller may run
/// several lowerings concurrently or sequentially because no evidence lives in
/// process-global state.
pub const Diagnostic = struct {
    site: ?std.builtin.SourceLocation = null,
    note_buffer: [96]u8 = undefined,
    note_len: u8 = 0,
    /// Exact application id when the refusal is about one occurrence.
    /// Null is unknown — never a sentinel zero.
    application: ?semantic_graph.id = null,
    /// Diagnostic projection of the occurrence's relation/method face.
    /// Borrowed from the resident graph or AST; not a second identity.
    relation: ?[]const u8 = null,
    /// Per-outcome host/bridge taint witnesses for this lowering attempt.
    taint: host_taint.Ledger = .{},

    pub fn deinit(self: *Diagnostic, alloc: std.mem.Allocator) void {
        self.taint.deinit(alloc);
    }

    pub fn reset(self: *Diagnostic) void {
        self.site = null;
        self.note_len = 0;
        self.application = null;
        self.relation = null;
    }

    pub fn note(self: *const Diagnostic) ?[]const u8 {
        if (self.note_len == 0) return null;
        return self.note_buffer[0..self.note_len];
    }

    pub fn writeTaintLedger(self: *const Diagnostic, io: std.Io, file: std.Io.File) void {
        var buf: [4096]u8 = undefined;
        var fw: std.Io.File.Writer = .init(file, io, &buf);
        self.taint.writeLedgerLines(&fw.interface) catch {};
        fw.interface.flush() catch {};
    }

    pub fn printTaintLedger(self: *const Diagnostic) void {
        self.taint.printLedgerLines();
    }


    /// Structured missing-fact refusal for agents and gates (`missingApplicationFact`).
    /// Shape: `application N [relation: R] missing: F consumer: C producer: P`.
    pub fn formatMissingApplicationFact(self: *const Diagnostic, buf: []u8) []const u8 {
        const missing = self.note() orelse "unspecified";
        const consumer = "dnir.lower";
        const producer = missingFactProducer(missing);
        if (self.application) |id| {
            if (self.relation) |rel| {
                return std.fmt.bufPrint(
                    buf,
                    "application {d} relation: {s} missing: {s} consumer: {s} producer: {s}",
                    .{ id, rel, missing, consumer, producer },
                ) catch missing;
            }
            return std.fmt.bufPrint(
                buf,
                "application {d} missing: {s} consumer: {s} producer: {s}",
                .{ id, missing, consumer, producer },
            ) catch missing;
        }
        if (self.relation) |rel| {
            return std.fmt.bufPrint(
                buf,
                "application unknown relation: {s} missing: {s} consumer: {s} producer: {s}",
                .{ rel, missing, consumer, producer },
            ) catch missing;
        }
        return std.fmt.bufPrint(
            buf,
            "application unknown missing: {s} consumer: {s} producer: {s}",
            .{ missing, consumer, producer },
        ) catch missing;
    }

    fn record(self: *Diagnostic, site: std.builtin.SourceLocation, detail: ?[]const u8) void {
        self.site = site;
        const text = detail orelse {
            self.note_len = 0;
            return;
        };
        const len = @min(text.len, self.note_buffer.len);
        @memcpy(self.note_buffer[0..len], text[0..len]);
        self.note_len = @intCast(len);
    }
};


fn missingFactProducer(missing: []const u8) []const u8 {
    if (std.mem.startsWith(u8, missing, "aggregate-")) return "graph.aggregate";
    if (std.mem.eql(u8, missing, "missing-application-id")) return "graph.occurrenceBridge";
    if (std.mem.eql(u8, missing, "missing-function-id")) return "graph.functionEntity";
    if (std.mem.eql(u8, missing, "unresolved-application")) return "sema.resolveApplication";
    if (std.mem.eql(u8, missing, "function-order-id")) return "graph.functionOrder";
    return "graph";
}

fn noteHostTaint(
    ctx: *LowerCtx,
    channel: host_taint.Channel,
    site: []const u8,
    application: ?semantic_graph.id,
) void {
    if (!ctx.require_graph_facts) return;
    ctx.diagnostic.taint.record(ctx.alloc, .{
        .stage = .lower,
        .class = .host_tainted,
        .channel = channel,
        .site = site,
        .application = application,
    }) catch {};
}

fn noteHostTaintDiagnostic(
    diagnostic: *Diagnostic,
    alloc: std.mem.Allocator,
    require_graph_facts: bool,
    channel: host_taint.Channel,
    site: []const u8,
    application: ?semantic_graph.id,
) void {
    if (!require_graph_facts) return;
    diagnostic.taint.record(alloc, .{
        .stage = .lower,
        .class = .host_tainted,
        .channel = channel,
        .site = site,
        .application = application,
    }) catch {};
}

fn bail(diagnostic: *Diagnostic, site: std.builtin.SourceLocation) Error {
    diagnostic.record(site, null);
    return error.UnsupportedConstruct;
}

fn bailWith(diagnostic: *Diagnostic, site: std.builtin.SourceLocation, note: []const u8) Error {
    diagnostic.record(site, note);
    return error.UnsupportedConstruct;
}

fn invalidGraphFacts(diagnostic: *Diagnostic, site: std.builtin.SourceLocation, note: []const u8) Error {
    diagnostic.record(site, note);
    return error.GraphFactsInvalid;
}

fn applicationFace(graph: *const semantic_graph.SemanticGraph, entity: semantic_graph.id) ?[]const u8 {
    const node = graph.get(entity) orelse return null;
    if (node.ast_ref) |raw| {
        const expr: *const Expr = @ptrCast(@alignCast(raw));
        return switch (expr.*) {
            .call => |c| switch (c.func.*) {
                .name => |n| n.ident,
                .field => |f| f.field,
                else => node.name,
            },
            .method_call => |mc| mc.method,
            else => node.name,
        };
    }
    if (graph.application(entity)) |fact| {
        const relation_id = graph.applicationRelation(fact.application) orelse return node.name;
        const relation = graph.get(relation_id) orelse return node.name;
        return relation.name;
    }
    return node.name;
}

fn bindOccurrence(
    diagnostic: *Diagnostic,
    graph: *const semantic_graph.SemanticGraph,
    occurrence: semantic_graph.id,
) void {
    diagnostic.application = occurrence;
    diagnostic.relation = applicationFace(graph, occurrence);
}

fn refuseApplication(
    diagnostic: *Diagnostic,
    graph: *const semantic_graph.SemanticGraph,
    site: std.builtin.SourceLocation,
    note: []const u8,
    application: semantic_graph.id,
) Error {
    bindOccurrence(diagnostic, graph, application);
    return invalidGraphFacts(diagnostic, site, note);
}

fn exprFace(expr: *const Expr) ?[]const u8 {
    return switch (expr.*) {
        .call => |c| switch (c.func.*) {
            .name => |n| n.ident,
            .field => |f| f.field,
            else => null,
        },
        .method_call => |mc| mc.method,
        else => null,
    };
}

fn refuseMissingApplication(
    ctx: *LowerCtx,
    site: std.builtin.SourceLocation,
    expr: *const Expr,
) Error {
    if (ctx.occurrences.get(expr)) |application| {
        bindOccurrence(ctx.diagnostic, ctx.graph, application.application);
    } else if (ctx.diagnostic.relation == null) {
        ctx.diagnostic.relation = exprFace(expr);
    }
    return invalidGraphFacts(ctx.diagnostic, site, "missing-application-id");
}

/// Module-level compile-time bindings, split by the DNIR value they fold to.
///
/// `ints` came first and was the whole table; a module-level STRING constant
/// had nowhere to live, so `return SEMANTIC_OWNER` fell through the `.name`
/// arm's integer lookup and bailed. `dnir.Value` has carried a `.str` variant
/// all along — a string literal already lowers to one — so the gap was the
/// constant table, not the value representation.
///
/// Two maps rather than a tagged union because every consumer knows which kind
/// it wants: `exprIsStr` asks only `strs`, the numeric-for step asks only
/// `ints`, and a union would make each of them re-check a tag they can't act on.
///
/// String VALUES are not duped: they point into the AST, exactly like the
/// `.quoted` arm's `s.val`, and the AST outlives lowering. Keys are duped
/// because the `Name.field` spelling is formatted, not borrowed.
const ModuleConsts = struct {
    ints: std.StringHashMapUnmanaged(i64) = .empty,
    strs: std.StringHashMapUnmanaged([]const u8) = .empty,

    fn deinit(self: *ModuleConsts, alloc: std.mem.Allocator) void {
        var it = self.ints.iterator();
        while (it.next()) |e| alloc.free(e.key_ptr.*);
        self.ints.deinit(alloc);
        var sit = self.strs.iterator();
        while (sit.next()) |e| alloc.free(e.key_ptr.*);
        self.strs.deinit(alloc);
    }
};

const empty_module_consts: ModuleConsts = .{};
const empty_fp_params: std.StringHashMapUnmanaged([]bool) = .empty;
const empty_relation_edges: std.StringHashMapUnmanaged([]const u8) = .empty;

fn deinitRecord(alloc: std.mem.Allocator, record: dnir.RecordDesc) void {
    alloc.free(record.name);
    for (record.fields) |field| alloc.free(field);
    alloc.free(record.fields);
    alloc.free(record.kinds);
    alloc.free(record.widths);
}

fn deinitFunction(alloc: std.mem.Allocator, function: dnir.Function) void {
    alloc.free(function.name);
    for (function.params) |param| {
        alloc.free(param.name);
        if (param.record) |record| alloc.free(record);
    }
    alloc.free(function.params);
    if (function.ret_pack.len > 0) alloc.free(function.ret_pack);
    if (function.ret_record) |record| alloc.free(record);
    for (function.blocks) |block| {
        for (block.instrs) |instruction| dnir.deinitInstr(alloc, instruction);
        alloc.free(block.instrs);
    }
    alloc.free(function.blocks);
}

fn deinitExtern(alloc: std.mem.Allocator, external: dnir.Extern) void {
    alloc.free(external.duo_name);
    alloc.free(external.symbol);
}

fn deinitParam(alloc: std.mem.Allocator, param: dnir.Param) void {
    alloc.free(param.name);
    if (param.record) |record| alloc.free(record);
}

/// Temporary occurrence bridge for the AST-driven realization walker. It
/// carries only the exact graph id already published by semantic resolution;
/// all application facts and packed values remain graph-owned. Delete this
/// bridge when resolver/lowering work items carry the application id directly.
const OccurrenceBridge = struct {
    alloc: std.mem.Allocator,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
    by_expression: std.AutoHashMapUnmanaged(*const Expr, semantic_graph.id) = .empty,
    by_exact_value: std.AutoHashMapUnmanaged(*const Expr, semantic_graph.id) = .empty,
    unresolved: usize = 0,

    fn init(
        alloc: std.mem.Allocator,
        graph: *const semantic_graph.SemanticGraph,
        diagnostic: *Diagnostic,
    ) Error!OccurrenceBridge {
        var index: OccurrenceBridge = .{
            .alloc = alloc,
            .graph = graph,
            .diagnostic = diagnostic,
        };
        errdefer index.deinit();

        for (graph.nodes.items, 0..) |node, coordinate| {
            if (node.kind != .call) continue;
            const application: semantic_graph.id = @intCast(coordinate);
            if (graph.application(application) == null) {
                if (graph.isBootstrapApplicationNode(application)) continue;
                index.unresolved += 1;
                if (diagnostic.application == null) {
                    bindOccurrence(diagnostic, graph, application);
                }
                continue;
            }
            _ = graph.applicationResults(application) orelse
                return refuseApplication(diagnostic, graph, @src(), "application-result-pack", application);
            const expression_raw = node.ast_ref orelse
                return refuseApplication(diagnostic, graph, @src(), "application-provenance", application);
            const expression: *const Expr = @ptrCast(@alignCast(expression_raw));
            const slot = try index.by_expression.getOrPut(alloc, expression);
            if (slot.found_existing)
                return refuseApplication(diagnostic, graph, @src(), "application-provenance-collision", application);
            slot.value_ptr.* = application;
        }
        for (graph.nodes.items, 0..) |node, coordinate| {
            if (node.kind != .value) continue;
            if (graph.exactI64(@intCast(coordinate)) == null) continue;
            const expression_raw = node.ast_ref orelse continue;
            const expression: *const Expr = @ptrCast(@alignCast(expression_raw));
            const slot = try index.by_exact_value.getOrPut(alloc, expression);
            if (slot.found_existing) continue;
            slot.value_ptr.* = @intCast(coordinate);
        }
        return index;
    }

    fn deinit(self: *OccurrenceBridge) void {
        self.by_expression.deinit(self.alloc);
        self.by_exact_value.deinit(self.alloc);
    }

    fn get(self: *const OccurrenceBridge, expression: *const Expr) ?*const semantic_graph.ApplicationFact {
        const application = self.by_expression.get(expression) orelse return null;
        return self.graph.application(application);
    }

    fn exactValue(self: *const OccurrenceBridge, expression: *const Expr) ?semantic_graph.id {
        return self.by_exact_value.get(expression);
    }
};

/// Collect top-level constant bindings so a function body can fold them.
///
/// `N = 3` and the canonical enum form `Kind = @{ eof = 0, ident = 1 }` are
/// module-level values; nothing registered them as locals, so `Kind.ident`
/// inside a function resolved to a runtime field load and failed with DNB007.
/// Both spellings are compile-time constants and belong as immediates.
/// The module-scope bindings that need REAL STORAGE, and their initializers.
///
/// A file-scope binding nothing writes is correctly folded to its initializer —
/// that is what `ModuleConsts` does and it stays. A binding a FUNCTION writes is
/// one storage location shared by every reader, and folding it is a wrong
/// answer: measured on `examples/native_differential/unsupported/`, `total` read
/// 0 where C read 6, and 5 where C read 8, with exit 0 and no diagnostic.
///
/// The set used to be kept arm-for-arm with `codegen.zig`'s
/// `module_top_level_written_binding`, because that predicate refused these
/// programs while this type had no storage behind it. The storage landed and
/// the refusal is deleted (2026-08-18), so THIS type is now the sole owner of
/// the written-binding set: a name it registers gets a `__bss` word and
/// prologue-store initializer, and every read answers through the map.
const ModuleGlobals = struct {
    /// Name -> the DNIR type its word holds.
    types: std.StringHashMapUnmanaged(RT) = .empty,
    /// Declaration order, so the entry's prologue runs initializers in source
    /// order. A `__bss` word starts zeroed, so only a non-zero initializer
    /// costs an instruction — but the store is emitted for all of them, because
    /// "the zero case happens to need no code" is not a rule anyone can read
    /// off the emitted text later.
    order: std.ArrayListUnmanaged(GlobalInit) = .empty,

    fn deinit(self: *ModuleGlobals, alloc: std.mem.Allocator) void {
        self.types.deinit(alloc);
        self.order.deinit(alloc);
    }

    fn has(self: *const ModuleGlobals, name: []const u8) bool {
        return self.types.contains(name);
    }
};

const GlobalInit = struct { name: []const u8, init: ?*const Expr };

const empty_module_globals: ModuleGlobals = .{};

/// Does any FUNCTION in this module assign `name`? Module-level code alone does
/// not force storage: those statements run in order in one entry frame, where a
/// register-resident binding is already correct.
fn moduleFunctionsAssignName(mod: *const ast.Module, name: []const u8) bool {
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        if (stmtsAssignName(stmt.func_decl.func.body.stmts, name)) return true;
    }
    return false;
}

fn stmtsAssignName(stmts: []const ast.Stmt, name: []const u8) bool {
    for (stmts) |*st| {
        switch (st.*) {
            .assign => |a| for (a.targets) |t| {
                if (t.* == .name and std.mem.eql(u8, t.name.ident, name)) return true;
            },
            // A `local`/parameter of the same name SHADOWS the global for the
            // rest of that body, so a write to it is not a write to the global.
            // Answering "true" here would give storage to a name that never
            // needed it; answering "false" for the assign arm would miscompile.
            .local_decl => |ld| for (ld.names) |n| {
                if (std.mem.eql(u8, n.ident, name)) return false;
            },
            .do_block => |b| if (stmtsAssignName(b.body.stmts, name)) return true,
            .while_loop => |w| if (stmtsAssignName(w.body.stmts, name)) return true,
            .repeat_loop => |r| if (stmtsAssignName(r.body.stmts, name)) return true,
            .num_for => |f| if (stmtsAssignName(f.body.stmts, name)) return true,
            .gen_for => |f| if (stmtsAssignName(f.body.stmts, name)) return true,
            .if_stmt => |is| {
                if (stmtsAssignName(is.then.stmts, name)) return true;
                for (is.elseifs) |ei| if (stmtsAssignName(ei.body.stmts, name)) return true;
                if (is.else_body) |eb| if (stmtsAssignName(eb.stmts, name)) return true;
            },
            else => {},
        }
    }
    return false;
}

fn typeOfGlobal(t: ast.TypeExpr, init: ?*const Expr) RT {
    // THE FULL WIDTH TABLE, not the shared `resolveType` shortcut: a declared
    // width is a property of the PLACE (gate/narrow.sh), and the shortcut
    // erases i8/i16/u8/u16/u32 to `.any` — which `typeOfGlobal` then defaulted
    // to `.i64`, so `g: i8 = 0` registered as a full-width global and the
    // narrow-width store refusal never fired. Measured: GLOBAL g ty=i64 for a
    // declared i8.
    if (t == .named) {
        const n = t.named;
        if (std.mem.eql(u8, n, "i8")) return .i8;
        if (std.mem.eql(u8, n, "i16")) return .i16;
        if (std.mem.eql(u8, n, "i32")) return .i32;
        if (std.mem.eql(u8, n, "u8")) return .u8;
        if (std.mem.eql(u8, n, "u16")) return .u16;
        if (std.mem.eql(u8, n, "u32")) return .u32;
    }
    const declared = resolveType(t);
    if (declared != .any) return declared;
    const e = init orelse return .i64;
    return switch (e.*) {
        .quoted => .str,
        .float_lit => .f64,
        else => .i64,
    };
}

fn collectModuleGlobals(alloc: std.mem.Allocator, mod: *const ast.Module) Error!ModuleGlobals {
    var out: ModuleGlobals = .{};
    errdefer out.deinit(alloc);
    for (mod.body.stmts) |*stmt| {
        switch (stmt.*) {
            .local_decl => |ld| for (ld.names, 0..) |n, i| {
                if (!moduleFunctionsAssignName(mod, n.ident)) continue;
                const init: ?*const Expr = if (i < ld.inits.len) ld.inits[i] else null;
                try out.types.put(alloc, n.ident, typeOfGlobal(n.typ, init));
                try out.order.append(alloc, .{ .name = n.ident, .init = init });
            },
            .global_decl => |gd| for (gd.names, 0..) |n, i| {
                // Explicit `global` declarations always get module storage.
                // Function-body assigns to the same name are `store_global`, not
                // a reason to drop the binding — asm_for resetting `_p2` must
                // not erase `global _p2` from the map other functions read.
                const init: ?*const Expr = if (i < gd.inits.len) gd.inits[i] else null;
                try out.types.put(alloc, n.ident, typeOfGlobal(n.typ, init));
                try out.order.append(alloc, .{ .name = n.ident, .init = init });
            },
            // gap[108]. `total = 5` with no annotation is not a declaration at
            // all — idol has no `local` keyword, so module scope gets an
            // `.assign`, the same node a function body produces. Missing this
            // arm is what let the untyped spelling run natively and answer
            // wrongly while the annotated one was refused.
            .assign => |as| for (as.targets, 0..) |t, i| {
                if (t.* != .name) continue;
                const name = t.name.ident;
                if (out.types.contains(name)) continue;
                if (!moduleFunctionsAssignName(mod, name)) continue;
                const init: ?*const Expr = if (i < as.values.len) as.values[i] else null;
                try out.types.put(alloc, name, typeOfGlobal(.inferred, init));
                try out.order.append(alloc, .{ .name = name, .init = init });
            },
            else => {},
        }
    }
    return out;
}

/// THE INITIAL CONTENT OF A MODULE GLOBAL'S WORD, AS A LOAD-TIME FACT.
///
/// A module-scope initializer that the compile-time evaluator can run is not an
/// instruction: it is what the storage HOLDS before anything executes. Returning
/// it here is what lets `__DATA,__data` carry it, which is the only realization
/// that is correct in an object, a dylib and an executable at once — the entry
/// prologue that used to carry it existed only when a `main` did.
///
/// FAILS CLOSED, and the caller REFUSES on null rather than emitting a store: an
/// initializer nobody can evaluate at compile time has no load-time image, and a
/// wrong answer outranks a refusal (`law.fallback.zero`).
///
/// `str` is NOT admitted, and that is a REFUSAL rather than an omission. A `str`
/// value in this backend is an ADDRESS into `__cstring`, so its data word needs
/// a relocation in `__DATA`, which the object writer does not emit for that
/// section. Admitting it would put a link-time-unresolved pointer in a word the
/// program dereferences — the confident-wrong-number class this whole change is
/// about. It refuses until the relocation exists.

fn globalInitIsSubjectBinding(init: *const Expr) bool {
    return switch (init.*) {
        .name => true,
        .field => |f| globalInitIsSubjectBinding(f.obj),
        else => false,
    };
}

fn constGlobalInit(init: *const Expr, ty: RT) ?dnir.Value {
    const v = comptime_eval.eval(init) catch return null;
    return switch (v) {
        .int => |n| if (ty == .f64)
            dnir.Value{ .f64 = @floatFromInt(n) }
        else
            dnir.Value{ .i64 = n },
        .float => |f| if (ty == .f64) dnir.Value{ .f64 = f } else null,
        .bool => |b| if (ty == .f64) null else dnir.Value{ .i64 = @intFromBool(b) },
        .nil => dnir.Value{ .i64 = 0 },
        else => null,
    };
}

fn collectModuleConsts(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
) Error!ModuleConsts {
    var out: ModuleConsts = .{};
    errdefer out.deinit(alloc);
    const map = &out.ints;
    for (mod.body.stmts) |*stmt| {
        var name: ?[]const u8 = null;
        var val: ?*const Expr = null;
        switch (stmt.*) {
            .assign => |as| {
                if (as.targets.len == 1 and as.values.len == 1 and as.targets[0].* == .name) {
                    name = as.targets[0].name.ident;
                    val = as.values[0];
                }
            },
            .local_decl => |ld| {
                if (ld.names.len == 1 and ld.inits.len == 1) {
                    name = ld.names[0].ident;
                    val = ld.inits[0];
                }
            },
            // `const WIDTH: i64 = 80` — the DECLARED form of the same thing
            // `WIDTH = 80` says, and the only one of the three that was not
            // collected. So a module using the explicit spelling had every
            // reference to it fail to resolve in lowering (mandelbrot bailed on
            // `HEIGHT`), while the bare assignment folded fine.
            .const_decl => |cd| {
                name = cd.ident;
                val = cd.val;
            },
            .global_decl => |gd| {
                if (gd.names.len == 1 and gd.inits.len == 1) {
                    name = gd.names[0].ident;
                    val = gd.inits[0];
                }
            },
            .enum_def => |ed| {
                for (ed.variants, 0..) |v, i| {
                    const key = try std.fmt.allocPrint(alloc, "{s}.{s}", .{ ed.name, v.name });
                    try map.put(alloc, key, @intCast(i));
                }
                continue;
            },
            else => {},
        }
        const n = name orelse continue;
        const v = val orelse continue;
        if (intLiteralStep(v)) |iv| {
            try map.put(alloc, try alloc.dupe(u8, n), iv);
            continue;
        }
        if (v.* == .quoted) {
            try out.strs.put(alloc, try alloc.dupe(u8, n), v.quoted.val);
            continue;
        }
        // `@{ ... }` is the canonical descriptor spelling and parses as a
        // `.compile` unop wrapping the table, so unwrap before reading fields.
        const tbl = switch (v.*) {
            .table => v,
            .unop => |u| if (u.op == .compile and u.operand.* == .table) u.operand else continue,
            else => continue,
        };
        for (tbl.table.fields) |fld| {
            const nf = switch (fld) {
                .named => |x| x,
                else => continue,
            };
            if (intLiteralStep(nf.val)) |fv| {
                const key = try std.fmt.allocPrint(alloc, "{s}.{s}", .{ n, nf.key });
                try map.put(alloc, key, fv);
                continue;
            }
            if (nf.val.* == .quoted) {
                const key = try std.fmt.allocPrint(alloc, "{s}.{s}", .{ n, nf.key });
                try out.strs.put(alloc, key, nf.val.quoted.val);
            }
        }
    }
    return out;
}


fn qualifiedExportNameFromExpr(
    alloc: std.mem.Allocator,
    expr: *const ast.Expr,
) Error!?[]const u8 {
    return switch (expr.*) {
        .call => |c| switch (c.func.*) {
            .name => |n| try alloc.dupe(u8, n.ident),
            .field => |f| {
                if (f.obj.* != .name) return null;
                return try std.fmt.allocPrint(alloc, "{s}.{s}", .{ f.obj.name.ident, f.field });
            },
            else => null,
        },
        .method_call => |m| {
            if (m.obj.* != .name) return null;
            return try std.fmt.allocPrint(alloc, "{s}.{s}", .{ m.obj.name.ident, m.method });
        },
        else => null,
    };
}

fn recordExportMapAssignable(ctx: *const LowerCtx, value: *const ast.Expr) bool {
    if (ctx.require_graph_facts) return false;
    const export_name = qualifiedExportNameFromExpr(ctx.alloc, value) catch return false;
    defer if (export_name) |n| ctx.alloc.free(n);
    if (export_name) |n| return ctx.func_record_returns.contains(n);
    return false;
}

pub fn lowerModule(alloc: std.mem.Allocator, mod: *const ast.Module) Error!dnir.Module {
    var diagnostic: Diagnostic = .{};
    return lowerModuleObserved(alloc, mod, &diagnostic);
}

pub fn lowerModuleObserved(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    diagnostic: *Diagnostic,
) Error!dnir.Module {
    diagnostic.reset();
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = graph.liftModuleWithCalls(mod, mod.file) catch return error.OutOfMemory;
    var occurrences = try OccurrenceBridge.init(alloc, &graph, diagnostic);
    defer occurrences.deinit();
    const module = try lowerModuleFromGraph(alloc, mod, &graph, &occurrences, diagnostic, false);
    errdefer dnir.deinitModule(alloc, module);
    var detached = module;
    detached.graph = null;

    // This convenience path does not return the graph owner. Any handles it
    // used while lowering are therefore intentionally erased before that
    // owner is destroyed. Checked consumers must use
    // `lowerModuleWithGraph` and retain the graph for the module's lifetime.
    const functions: []dnir.Function = @constCast(detached.functions);
    for (functions) |*function| {
        function.id = null;
        for (function.blocks) |block| {
            const instructions: []dnir.Instr = @constCast(block.instrs);
            for (instructions) |*instruction| {
                instruction.relation = null;
                instruction.application = null;
                instruction.value = null;
                instruction.subject = null;
                instruction.realization_start = null;
            }
        }
    }
    return detached;
}

/// relation level edge `len(path) = (min) …` → symbol `len__path`.
fn relationEdgeLevel(symbol: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, symbol, "__")) |sep| {
        if (sep + 2 < symbol.len) return symbol[sep + 2 ..];
    }
    return null;
}

/// Does an expression subtree name `ident` anywhere? Used to decide whether a
/// relation-edge projection level (`family(level) = (…)`, mangled `family__level`)
/// is a runtime subject parameter or a compile-time-only qualifier.
///
///   `len(path) = (min)` body reads `path` → the level is a runtime subject slot;
///     it is applied `len(value)(min)` / `value:len(min)` (level passed as an arg).
///   `subject(tail) = (code)` body never reads `tail` → the level is a pure
///     compile-time marker baked into the mangled callee `subject__tail`; the call
///     `subject(tail)(code)` lowers to `subject__tail(code)` with the level absent
///     from the operand list, so allocating a level slot would misplace `code`.
fn exprMentionsIdent(expr: *const ast.Expr, ident: []const u8) bool {
    return switch (expr.*) {
        .name => |n| std.mem.eql(u8, n.ident, ident),
        .index => |x| exprMentionsIdent(x.obj, ident) or exprMentionsIdent(x.key, ident),
        .field => |x| exprMentionsIdent(x.obj, ident),
        .call => |c| blk: {
            if (exprMentionsIdent(c.func, ident)) break :blk true;
            for (c.args) |a| if (exprMentionsIdent(a, ident)) break :blk true;
            break :blk false;
        },
        .method_call => |m| blk: {
            if (exprMentionsIdent(m.obj, ident)) break :blk true;
            for (m.args) |a| if (exprMentionsIdent(a, ident)) break :blk true;
            break :blk false;
        },
        .binop => |b| exprMentionsIdent(b.lhs, ident) or exprMentionsIdent(b.rhs, ident),
        .unop => |u| exprMentionsIdent(u.operand, ident),
        .if_expr => |ie| exprMentionsIdent(ie.cond, ident) or
            exprMentionsIdent(ie.then_expr, ident) or exprMentionsIdent(ie.else_expr, ident),
        .try_expr => |x| exprMentionsIdent(x.operand, ident),
        .unwrap_expr => |x| exprMentionsIdent(x.operand, ident),
        .await_expr => |x| exprMentionsIdent(x.operand, ident),
        .contains_expr => |x| exprMentionsIdent(x.lhs, ident) or exprMentionsIdent(x.rhs, ident),
        .sequence => |s| blk: {
            for (s.exprs) |e| if (exprMentionsIdent(e, ident)) break :blk true;
            break :blk false;
        },
        .range => |r| exprMentionsIdent(r.start, ident) or exprMentionsIdent(r.end, ident) or
            (if (r.step) |st| exprMentionsIdent(st, ident) else false),
        else => false,
    };
}

fn blockMentionsIdent(block: *const ast.Block, ident: []const u8) bool {
    for (block.stmts) |*s| if (stmtMentionsIdent(s, ident)) return true;
    if (block.tail_expr) |t| return exprMentionsIdent(t, ident);
    return false;
}

fn stmtMentionsIdent(stmt: *const ast.Stmt, ident: []const u8) bool {
    return switch (stmt.*) {
        .local_decl => |d| blk: {
            for (d.inits) |e| if (exprMentionsIdent(e, ident)) break :blk true;
            break :blk false;
        },
        .const_decl => |d| exprMentionsIdent(d.val, ident),
        .global_decl => |d| blk: {
            for (d.inits) |e| if (exprMentionsIdent(e, ident)) break :blk true;
            break :blk false;
        },
        .assign => |a| blk: {
            for (a.targets) |e| if (exprMentionsIdent(e, ident)) break :blk true;
            for (a.values) |e| if (exprMentionsIdent(e, ident)) break :blk true;
            break :blk false;
        },
        .call_stmt => |c| exprMentionsIdent(c.expr, ident),
        .expr_stmt => |c| exprMentionsIdent(c.expr, ident),
        .do_block => |d| blockMentionsIdent(&d.body, ident),
        .while_loop => |w| exprMentionsIdent(w.cond, ident) or blockMentionsIdent(&w.body, ident),
        .repeat_loop => |r| blockMentionsIdent(&r.body, ident) or exprMentionsIdent(r.cond, ident),
        .if_stmt => |f| blk: {
            if (f.binding) |b| if (exprMentionsIdent(b.expr, ident)) break :blk true;
            if (exprMentionsIdent(f.cond, ident)) break :blk true;
            if (blockMentionsIdent(&f.then, ident)) break :blk true;
            for (f.elseifs) |ei| {
                if (exprMentionsIdent(ei.cond, ident)) break :blk true;
                if (blockMentionsIdent(&ei.body, ident)) break :blk true;
            }
            if (f.else_body) |eb| if (blockMentionsIdent(&eb, ident)) break :blk true;
            break :blk false;
        },
        .num_for => |n| exprMentionsIdent(n.start, ident) or exprMentionsIdent(n.stop, ident) or
            (if (n.step) |st| exprMentionsIdent(st, ident) else false) or blockMentionsIdent(&n.body, ident),
        .gen_for => |g| blk: {
            for (g.iters) |e| if (exprMentionsIdent(e, ident)) break :blk true;
            break :blk blockMentionsIdent(&g.body, ident);
        },
        .ret => |r| blk: {
            for (r.vals) |e| if (exprMentionsIdent(e, ident)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

fn collectRelationEdges(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
) Error!std.StringHashMapUnmanaged([]const u8) {
    var edges: std.StringHashMapUnmanaged([]const u8) = .empty;
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        const fd = &stmt.func_decl;
        if (fd.path.len != 1) continue;
        const sym = fd.path[0];
        if (relationEdgeLevel(sym)) |level| {
            _ = level;
            if (std.mem.indexOf(u8, sym, "__")) |sep| {
                const family = try alloc.dupe(u8, sym[0..sep]);
                errdefer alloc.free(family);
                const gop = try edges.getOrPut(alloc, family);
                if (gop.found_existing) {
                    alloc.free(family);
                } else {
                    gop.value_ptr.* = sym;
                }
            }
        }
    }
    return edges;
}

fn immutableAggregate(graph: *const semantic_graph.SemanticGraph, aggregate: semantic_graph.id) bool {
    const fact = graph.aggregate(aggregate) orelse return false;
    if (fact.contents_known != .yes) return false;
    const p = graph.aggregatePlace(aggregate) orelse return false;
    if (p.shape != .collection or p.facts.contents_known != .yes) return false;
    if (p.facts.mutation != .no or p.facts.immutability != .yes) return false;
    if (p.facts.alias != .no or p.facts.escape != .no) return false;
    return switch (p.bindCount()) {
        .exact => |count| count == 1,
        .bounded, .unknown => false,
    };
}

fn immutableNestedAggregateRoot(graph: *const semantic_graph.SemanticGraph, aggregate: semantic_graph.id) bool {
    if (!immutableAggregate(graph, aggregate)) return false;
    const node = graph.get(aggregate) orelse return false;
    const descriptor = node.descriptor orelse return false;
    return descriptor == .array and descriptor.array.elem.* == .array;
}

/// Whether the exact graph place named by this transitional AST binding already
/// has a selected static aggregate realization. The name is only the current
/// walker's bridge to the graph place; aggregate identity, contents, legality,
/// and physical selection all come from graph facts. Delete the name bridge
/// when parser work items carry place ids directly.
fn skipStaticAggregateBinding(ctx: *LowerCtx, binding_name: []const u8) Error!bool {
    const owner = ctx.function orelse return false;
    const owner_node = ctx.graph.get(owner) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-owner");
    const bound_place = if (owner_node.scope == null)
        ctx.graph.placeNamed(binding_name)
    else if (ctx.graph.bodyOf(owner)) |body|
        body.places.find(binding_name)
    else
        null;
    const site = (bound_place orelse return false).id;
    const aggregate = ctx.graph.boundAggregateAtPlace(owner, site) orelse return false;
    if (ctx.graph.aggregateProducer(aggregate) != null) return false;
    const fact = ctx.graph.aggregate(aggregate) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-member-pack");
    const node = ctx.graph.get(aggregate) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-root");
    const descriptor = node.descriptor orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-root-descriptor");
    if (descriptor != .array or descriptor.array.elem.* != .array) return false;
    if (fact.contents_known != .yes or ctx.graph.aggregatePlace(aggregate) == null)
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-static-place");
    return immutableNestedAggregateRoot(ctx.graph, aggregate);
}

fn appendAggregateWords(
    graph: *const semantic_graph.SemanticGraph,
    aggregate: semantic_graph.id,
    words: *std.ArrayListUnmanaged(i64),
    stack: *std.AutoHashMapUnmanaged(semantic_graph.id, void),
    alloc: std.mem.Allocator,
) Error!void {
    const entry = try stack.getOrPut(alloc, aggregate);
    if (entry.found_existing) return error.GraphFactsInvalid;
    defer _ = stack.remove(aggregate);

    const fact = graph.aggregate(aggregate) orelse return error.GraphFactsInvalid;
    if (fact.contents_known != .yes) return error.GraphFactsInvalid;
    const members = graph.aggregateMembers(aggregate) orelse return error.GraphFactsInvalid;
    for (members) |member| {
        const node = graph.get(member) orelse return error.GraphFactsInvalid;
        const descriptor = node.descriptor orelse return error.GraphFactsInvalid;
        switch (descriptor) {
            .i64 => try words.append(alloc, graph.exactI64(member) orelse return error.GraphFactsInvalid),
            .array => try appendAggregateWords(graph, member, words, stack, alloc),
            else => return error.GraphFactsInvalid,
        }
    }
}

fn collectDenseTables(
    alloc: std.mem.Allocator,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error![]const dnir.DenseTable {
    var tables: std.ArrayListUnmanaged(dnir.DenseTable) = .empty;
    errdefer {
        for (tables.items) |table| alloc.free(table.values);
        tables.deinit(alloc);
    }
    var stack: std.AutoHashMapUnmanaged(semantic_graph.id, void) = .empty;
    defer stack.deinit(alloc);
    var row: usize = 0;
    while (row < graph.aggregateCount()) : (row += 1) {
        const fact = graph.aggregateAt(row) orelse
            return invalidGraphFacts(diagnostic, @src(), "aggregate-member-pack");
        if (graph.aggregateProducer(fact.aggregate) != null) continue;
        if (!immutableNestedAggregateRoot(graph, fact.aggregate)) continue;
        var words: std.ArrayListUnmanaged(i64) = .empty;
        errdefer words.deinit(alloc);
        appendAggregateWords(graph, fact.aggregate, &words, &stack, alloc) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return invalidGraphFacts(diagnostic, @src(), "aggregate-member-pack"),
        };
        if (words.items.len == 0) {
            words.deinit(alloc);
            return invalidGraphFacts(diagnostic, @src(), "aggregate-member-pack");
        }
        const values = try words.toOwnedSlice(alloc);
        errdefer alloc.free(values);
        try tables.append(alloc, .{
            .value = fact.aggregate,
            .elem_ty = .i64,
            .values = values,
        });
    }
    return try tables.toOwnedSlice(alloc);
}

fn validateAggregateFacts(
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error!void {
    var row: usize = 0;
    while (row < graph.aggregateCount()) : (row += 1) {
        const fact = graph.aggregateAt(row) orelse
            return invalidGraphFacts(diagnostic, @src(), "aggregate-member-pack");
        const descriptor = (graph.get(fact.aggregate) orelse
            return invalidGraphFacts(diagnostic, @src(), "aggregate-member-pack")).descriptor orelse
            return invalidGraphFacts(diagnostic, @src(), "aggregate-member-pack");
        if (descriptor != .array) continue;
        const extent = descriptor.array.size orelse
            return invalidGraphFacts(diagnostic, @src(), "aggregate-member-pack");
        const members = graph.aggregateMembers(fact.aggregate) orelse
            return invalidGraphFacts(diagnostic, @src(), "aggregate-member-pack");
        if (members.len != extent)
            return invalidGraphFacts(diagnostic, @src(), "aggregate-member-pack");
        for (members) |member| {
            const member_descriptor = (graph.get(member) orelse
                return invalidGraphFacts(diagnostic, @src(), "aggregate-member-pack")).descriptor orelse
                return invalidGraphFacts(diagnostic, @src(), "aggregate-member-pack");
            if (!member_descriptor.eql(descriptor.array.elem.*))
                return invalidGraphFacts(diagnostic, @src(), "aggregate-member-pack");
        }
    }
}

fn lowerModuleFromGraph(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    graph: *const semantic_graph.SemanticGraph,
    occurrences: *const OccurrenceBridge,
    diagnostic: *Diagnostic,
    require_graph_facts: bool,
) Error!dnir.Module {
    try validateAggregateFacts(graph, diagnostic);
    // THE HOME THIS MODULE IS. Read once, here, and handed to every place that
    // names a symbol, so a definition and a same-home call site cannot be
    // computed from two different answers.
    const self_home = graph.selfHome();

    // ORDER MATTERS. The globals are collected FIRST and then removed from the
    // constant pool: a name that is written is not a constant, and leaving it in
    // both would let a read fold to the initializer while a write went to
    // storage — the two halves of the same binding disagreeing, which is worse
    // than either the old folding or the new storage alone.
    var module_globals = try collectModuleGlobals(alloc, mod);
    defer module_globals.deinit(alloc);
    {
        // A DECLARED WIDTH IS A PROPERTY OF THE PLACE and applies at EVERY
        // WRITE (gate/narrow.sh). The `__DATA,__bss` word behind a written
        // module global is a full i64 slot and the store path does not yet
        // mask to the declared width, so a written global narrower than the
        // word would accept out-of-width values silently. Those stay REFUSED
        // with the refusal narrow.sh pins as OWED (`mod-global-written:`),
        // while full-width written globals keep the storage that landed with
        // g066/g108. Deleting this check admits 36 oracle rows that answer
        // wrong — measured when the guard was first removed.
        var it = module_globals.types.iterator();
        while (it.next()) |entry| {
            switch (entry.value_ptr.*) {
                .i8, .i16, .i32, .u8, .u16, .u32 => {
                    var name_buf: [64]u8 = undefined;
                    const note = std.fmt.bufPrint(&name_buf, "mod-global-written:{s}", .{entry.key_ptr.*}) catch
                        "mod-global-written:<name>";
                    return bailWith(diagnostic, @src(), note);
                },
                else => {},
            }
        }
    }
    var module_consts = try collectModuleConsts(alloc, mod);
    defer module_consts.deinit(alloc);
    {
        var it = module_globals.types.keyIterator();
        while (it.next()) |name| {
            if (module_consts.ints.fetchRemove(name.*)) |e| alloc.free(e.key);
            if (module_consts.strs.fetchRemove(name.*)) |e| alloc.free(e.key);
        }
    }
    var records: std.ArrayList(dnir.RecordDesc) = .empty;
    errdefer {
        for (records.items) |record| deinitRecord(alloc, record);
        records.deinit(alloc);
    }
    try collectRecordsFromGraph(alloc, &records, graph);
    try collectRecordsFromModuleAliases(alloc, &records, mod);
    var relation_edges = try collectRelationEdges(alloc, mod);
    defer {
        var edge_it = relation_edges.iterator();
        while (edge_it.next()) |entry| alloc.free(entry.key_ptr.*);
        relation_edges.deinit(alloc);
    }

    // Join declarations to graph ids by exact provenance.
    var declarations: std.AutoHashMapUnmanaged(*const ast.FuncDecl, semantic_graph.id) = .empty;
    defer declarations.deinit(alloc);
    var entity_linkage: std.AutoHashMapUnmanaged(semantic_graph.id, []const u8) = .empty;
    defer {
        var linkage_it = entity_linkage.iterator();
        while (linkage_it.next()) |entry| alloc.free(entry.value_ptr.*);
        entity_linkage.deinit(alloc);
    }
    for (graph.nodes.items, 0..) |node, i| {
        if (node.result_descriptor == null) continue;
        const raw = node.ast_ref orelse continue;
        const declaration: *const ast.FuncDecl = @ptrCast(@alignCast(raw));
        const slot = try declarations.getOrPut(alloc, declaration);
        if (slot.found_existing) return invalidGraphFacts(diagnostic, @src(), "function-provenance-collision");
        slot.value_ptr.* = @intCast(i);
    }
    var decl_it = declarations.iterator();
    while (decl_it.next()) |entry| {
        const fd = entry.key_ptr.*;
        const entity_id = entry.value_ptr.*;
        // THE MANGLING LAW, BOTH SIDES, THROUGH ONE FUNCTION.
        //
        // A relation is realized as `idol_<home>__<name>`. The only thing that
        // differs between the two arms is WHICH home: a foreign target's home
        // is the one sema resolved and the graph carried here as
        // `foreign_home`; this module's own is `selfHome`. Both then call
        // `home_resolve.relationSymbol`, so the caller cannot spell a symbol
        // the definer would not.
        //
        // The `else` arm was `funcExportName(alloc, fd)` with no home at all —
        // the bare spelling — which is why `lib/compiler/record.id` exported
        // `_field` and collided with every other home naming a relation
        // `field`. That arm is the DEFINER side of the law, and it is what this
        // change lands.
        const export_name = if (graph.foreignHome(entity_id)) |h| blk: {
            // THE `c` WORLD IS A FOREIGN BOUNDARY: roster members link as their
            // C names (`abs`), not `idol_c__abs` mangling.
            if (std.mem.eql(u8, h, "c")) break :blk try alloc.dupe(u8, fd.path[0]);
            break :blk try home_resolve.homeSymbol(alloc, h, fd.path[0]);
        } else
            try funcExportName(alloc, self_home, fd);
        errdefer alloc.free(export_name);
        const slot = try entity_linkage.getOrPut(alloc, entity_id);
        if (slot.found_existing) {
            alloc.free(export_name);
            return invalidGraphFacts(diagnostic, @src(), "function-linkage-collision");
        }
        slot.value_ptr.* = export_name;
    }

    // GAP-056: which ABI slots each callee expects in v0..v7, so the CALLER
    // marshals into the register file the CALLEE reads from. Keyed by
    // `funcExportName` — the same string `lowerCall` emits as the callee — so a
    // spliced `T.count` resolves as readily as a bare `count`.
    var fp_params: std.StringHashMapUnmanaged([]bool) = .empty;
    defer {
        var fp_it = fp_params.iterator();
        while (fp_it.next()) |e| {
            alloc.free(e.key_ptr.*);
            alloc.free(e.value_ptr.*);
        }
        fp_params.deinit(alloc);
    }
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        const fd = &stmt.func_decl;
        if (!shouldIncludeFuncDecl(fd)) continue;
        if (!functionEligible(fd, records.items, graph, mod)) continue;
        const slots = f64AbiParamSlots(fd, records.items) orelse continue;
        if (slots == 0 or slots > 8) continue;
        const key = try funcExportName(alloc, self_home, fd);
        if (fp_params.contains(key)) {
            alloc.free(key);
            continue;
        }
        const slots_are_fp = paramSlotIsFp(alloc, fd, records.items) catch |err| {
            alloc.free(key);
            return err;
        };
        fp_params.put(alloc, key, slots_are_fp) catch |err| {
            alloc.free(key);
            alloc.free(slots_are_fp);
            return err;
        };
    }

    var functions: std.ArrayList(dnir.Function) = .empty;
    errdefer {
        for (functions.items) |function| deinitFunction(alloc, function);
        functions.deinit(alloc);
    }
    var externs: std.ArrayList(dnir.Extern) = .empty;
    errdefer {
        for (externs.items) |external| deinitExtern(alloc, external);
        externs.deinit(alloc);
    }
    var func_record_returns: std.StringHashMapUnmanaged([]const u8) = .empty;
    defer {
        var returns = func_record_returns.iterator();
        while (returns.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            alloc.free(entry.value_ptr.*);
        }
        func_record_returns.deinit(alloc);
    }

    // Register every record-returning function BEFORE lowering any body.
    //
    // This map was populated as each function finished lowering, so a forward
    // reference could not see it: in a recursive-descent parser `parse_factor`
    // calls `parse_expr` for a parenthesised group, and `parse_expr` had not
    // been lowered yet, so the call was not recognised as record-returning and
    // failed with DNB007. Mutual recursion is the normal shape of a parser, not
    // an edge case, so the map has to be complete up front.
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        const fd = &stmt.func_decl;
        if (!shouldIncludeFuncDecl(fd)) continue;
        if (!functionEligible(fd, records.items, graph, mod)) continue;
        const rec_name = recordReturnNameForDecl(records.items, graph, fd) orelse continue;
        const export_name = try funcExportName(alloc, self_home, fd);
        defer alloc.free(export_name);
        if (func_record_returns.contains(export_name)) continue;
        const key = try alloc.dupe(u8, export_name);
        const value = alloc.dupe(u8, rec_name) catch |err| {
            alloc.free(key);
            return err;
        };
        func_record_returns.put(alloc, key, value) catch |err| {
            alloc.free(key);
            alloc.free(value);
            return err;
        };
    }
    var skipped: ?[]const u8 = null;
    defer if (skipped) |name| alloc.free(name);
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        const fd = &stmt.func_decl;
        if (!shouldIncludeFuncDecl(fd)) continue;
        // Name the function that was refused. "the counts do not match" is a
        // true statement about a module and a useless one about a fix: every
        // one of these bails means exactly one declaration was ineligible, and
        // which one is the entire finding.
        if (!functionEligible(fd, records.items, graph, mod)) {
            // The WHOLE path, not `path[0]`. A spliced `req` module contributes
            // `os.exit`, `os.clock`, `os.time` … and every one of them reported
            // as plain `os`, so the row named a module where the finding is one
            // declaration inside it.
            if (skipped == null) skipped = if (fd.path.len > 0)
                try std.mem.join(alloc, ".", fd.path)
            else
                "?";
            continue;
        }
        const function = declarations.get(fd) orelse if (require_graph_facts)
            return invalidGraphFacts(diagnostic, @src(), "missing-function-id")
        else
            null;
        const f = try lowerFunction(
            alloc,
            fd,
            function,
            records.items,
            graph,
            occurrences,
            diagnostic,
            require_graph_facts,
            &externs,
            &func_record_returns,
            &fp_params,
            &module_consts,
            &module_globals,
            &entity_linkage,
            &relation_edges,
        );
        functions.append(alloc, f) catch |err| {
            deinitFunction(alloc, f);
            return err;
        };
    }
    const want = mod.program() and !wrap(mod);
    if (want) {
        const module_id = if (require_graph_facts)
            (home(graph) orelse return invalidGraphFacts(diagnostic, @src(), "missing-function-id"))
        else
            null;
        const body = try root(
            alloc,
            mod,
            module_id,
            records.items,
            graph,
            occurrences,
            diagnostic,
            require_graph_facts,
            &externs,
            &func_record_returns,
            &fp_params,
            &module_consts,
            &module_globals,
            &entity_linkage,
            &relation_edges,
        );
        functions.append(alloc, body) catch |err| {
            deinitFunction(alloc, body);
            return err;
        };
    }
    // THE MODULE SYSTEM'S BASE CASE. A module that DECLARES nothing lowers to
    // a module that CONTAINS nothing — an object with no text symbols, which is
    // exactly what it means. `if (functions.items.len == 0) return bail(…)` used
    // to sit here and refused that module with `DNB001 lowerModuleFromGraph()`,
    // so `lib/compiler/application.id` — 29 lines of fact-closure documentation
    // and zero lines of code — could not be built by the compiler it documents.
    //
    // The guard was also REDUNDANT for the case it was defending. Zero functions
    // has two causes and the line below already separates them: nothing was
    // declared (`expected == 0`, legal, an empty object) versus everything
    // declared was refused (`expected > 0`, a bail that NAMES the declaration in
    // `skipped`). The deleted line answered both with one unattributed refusal,
    // so it destroyed the better diagnostic in the failing case and forbade the
    // legal one. HPLS §99: consumed but no candidate generated — the empty
    // module reached lowering and no realization was ever proposed for it.
    const expected = countModuleFunctions(mod) + @as(usize, @intFromBool(want));
    if (functions.items.len != expected)
        return bailWith(diagnostic, @src(), skipped orelse "?");

    const owned_functions = try functions.toOwnedSlice(alloc);
    errdefer {
        for (owned_functions) |function| deinitFunction(alloc, function);
        alloc.free(owned_functions);
    }
    const owned_records = try records.toOwnedSlice(alloc);
    errdefer {
        for (owned_records) |record| deinitRecord(alloc, record);
        alloc.free(owned_records);
    }
    const owned_externs = try externs.toOwnedSlice(alloc);
    errdefer {
        for (owned_externs) |external| deinitExtern(alloc, external);
        alloc.free(owned_externs);
    }

    // THE INITIALIZERS, AS LOAD-TIME CONTENT OF THE STORAGE.
    //
    // `dnir.Module.globals` existed with zero producers and zero consumers —
    // scenery under `AGENTS.md`'s standing rule. It gains both here, because it
    // is exactly the fact the backend was missing: WHAT EACH WORD HOLDS BEFORE
    // ANYTHING RUNS. Publishing it is what lets `__DATA,__data` answer, and what
    // deleted the `main`-only prologue store that made a library object wrong.
    //
    // A global with no initializer is not published: its word is zero, and a
    // zero word is `__DATA,__bss` — no file bytes, no relocation, nothing. That
    // is the same rule `has_cstring`/`has_const` follow, and it is why this
    // change costs a module with no non-zero initializer literally nothing.
    var globals: std.ArrayListUnmanaged(dnir.Global) = .empty;
    errdefer globals.deinit(alloc);
    for (module_globals.order.items) |g| {
        const init = g.init orelse continue;
        const ty = module_globals.types.get(g.name) orelse continue;
        const value = constGlobalInit(init, ty) orelse {
            // String-typed globals with string-literal initializers cannot be
            // published as a compile-time constant word (the address is a
            // link-time fact). Skip the initializer: the global gets zero
            // storage and the string is materialized at the read site.
            if (ty == .str and init.* == .quoted) continue;
            // A module-home alias (`global A = compiler.arm64`) is a subject
            // binding, not a load-time word. Calls resolve through graph
            // application facts; the initializer has no `__DATA` image.
            if (globalInitIsSubjectBinding(init)) {
                noteHostTaintDiagnostic(
                    diagnostic,
                    alloc,
                    require_graph_facts,
                    .ast_name,
                    "global_init.subject_binding",
                    null,
                );
                continue;
            }
            var buf: [96]u8 = undefined;
            const note = std.fmt.bufPrint(&buf, "global-init-not-constant:{s}", .{g.name}) catch
                "global-init-not-constant";
            return bailWith(diagnostic, @src(), note);
        };
        const zero = switch (value) {
            .i64 => |n| n == 0,
            .f64 => |f| @as(u64, @bitCast(f)) == 0,
            else => false,
        };
        if (zero) continue;
        try globals.append(alloc, .{ .name = g.name, .ty = ty, .init = value });
    }
    const owned_globals = try globals.toOwnedSlice(alloc);
    errdefer alloc.free(owned_globals);

    const owned_dense_tables = try collectDenseTables(alloc, graph, diagnostic);
    errdefer {
        for (owned_dense_tables) |table| alloc.free(table.values);
        alloc.free(owned_dense_tables);
    }

    const result = dnir.Module{
        .graph = graph,
        .functions = owned_functions,
        .records = owned_records,
        .globals = owned_globals,
        .dense_tables = owned_dense_tables,
        .externs = owned_externs,
    };
    return .{
        .graph = graph,
        .functions = result.functions,
        .records = result.records,
        .globals = result.globals,
        .dense_tables = result.dense_tables,
        .externs = result.externs,
        .hardware_tier = dnir.moduleHardwareTier(result),
    };
}

/// Graph facts control checked call ordering and provenance.
pub fn lowerModuleWithGraph(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    graph: *const semantic_graph.SemanticGraph,
) Error!dnir.Module {
    var diagnostic: Diagnostic = .{};
    return lowerModuleWithGraphObserved(alloc, mod, graph, &diagnostic);
}

pub fn lowerModuleWithGraphObserved(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error!dnir.Module {
    diagnostic.taint.reset(alloc);
    diagnostic.reset();
    var occurrences = try OccurrenceBridge.init(alloc, graph, diagnostic);
    defer occurrences.deinit();
    if (!graph.gateTransportModule() and occurrences.unresolved != 0)
        return invalidGraphFacts(diagnostic, @src(), "missing-application-id");
    const require_graph_facts = !graph.gateTransportModule();
    var m = try lowerModuleFromGraph(alloc, mod, graph, &occurrences, diagnostic, require_graph_facts);
    errdefer dnir.deinitModule(alloc, m);
    try applyGraphToModule(alloc, graph, &m, diagnostic);
    return m;
}

fn applyGraphToModule(
    alloc: std.mem.Allocator,
    graph: *const semantic_graph.SemanticGraph,
    m: *dnir.Module,
    diagnostic: *Diagnostic,
) Error!void {
    if (graph.gateTransportModule()) return;
    try reorderFunctionsByGraphFacts(alloc, graph, m, diagnostic);
}

/// Place checked callees before callers using graph facts only.
fn reorderFunctionsByGraphFacts(
    alloc: std.mem.Allocator,
    graph: *const semantic_graph.SemanticGraph,
    m: *dnir.Module,
    diagnostic: *Diagnostic,
) Error!void {
    if (m.functions.len <= 1) return;

    const function_ids = try alloc.alloc(semantic_graph.id, m.functions.len);
    defer alloc.free(function_ids);
    var functions: std.AutoHashMapUnmanaged(semantic_graph.id, usize) = .empty;
    defer functions.deinit(alloc);
    for (m.functions, 0..) |entry, i| {
        const function = entry.id orelse
            return invalidGraphFacts(diagnostic, @src(), "missing-function-id");
        function_ids[i] = function;
        const slot = try functions.getOrPut(alloc, function);
        if (slot.found_existing) return invalidGraphFacts(diagnostic, @src(), "duplicate-function-id");
        slot.value_ptr.* = i;
    }

    const order = graph.moduleFunctionEmitOrder(alloc, function_ids) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.DuplicateFunctionEntity => return invalidGraphFacts(diagnostic, @src(), "duplicate-function-id"),
        error.InvalidFunctionEntity => return invalidGraphFacts(diagnostic, @src(), "invalid-function-id"),
        error.UnresolvedApplication => return invalidGraphFacts(diagnostic, @src(), "unresolved-application"),
    };
    defer alloc.free(order);

    var changed = false;
    for (order, function_ids) |ordered_id, current_id| {
        if (ordered_id != current_id) {
            changed = true;
            break;
        }
    }
    if (!changed) return;

    const ordered = try alloc.alloc(dnir.Function, m.functions.len);
    defer alloc.free(ordered);
    for (order, 0..) |function, destination_index| {
        const source_index = functions.get(function) orelse
            return invalidGraphFacts(diagnostic, @src(), "function-order-id");
        ordered[destination_index] = m.functions[source_index];
    }
    @memcpy(@constCast(m.functions), ordered);
}

fn funcFfiName(attrs: []const ast.Attribute) ?[]const u8 {
    for (attrs) |attr| {
        if (!std.mem.eql(u8, attr.name, "ffi")) continue;
        const raw = attr.args orelse return null;
        if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"') return raw[1 .. raw.len - 1];
        return raw;
    }
    return null;
}

/// The name a FOREIGN BOUNDARY declares for itself: `@ffi("n")`,
/// `@c.export("n")` or its canonical spelling `@comp.c.export("n")`. Null when
/// the relation has no foreign boundary and is therefore ours to name.
///
/// `@export` with no argument is here too, and it means "this bare spelling is
/// the boundary" — the same claim `@c.export("x")` makes about `x`.
/// `native_backend.funcExportName` reads the identical three attributes when it
/// picks a process entry; the two agree because they read the same declaration.
fn foreignBoundaryName(fd: *const ast.FuncDecl) ?[]const u8 {
    for (fd.attributes) |attr| {
        const is_boundary = std.mem.eql(u8, attr.name, "ffi") or
            std.mem.eql(u8, attr.name, "export") or
            std.mem.eql(u8, attr.name, "c.export") or
            std.mem.eql(u8, attr.name, "comp.c.export");
        if (!is_boundary) continue;
        const raw = attr.args orelse return fd.path[0];
        if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"') return raw[1 .. raw.len - 1];
        return raw;
    }
    return null;
}

/// THE SYMBOL A RELATION IS REALIZED AS — a function of its IDENTITY, and its
/// identity is `(home, name)`.
///
/// This returned `fd.path[0]` — the BARE name — for as long as the direct
/// backend has existed, and the direct backend is the only backend there is. It
/// is not merely inelegant. MEASURED, 2026-08-15: `lib/compiler/record.id`
/// exports `_field`; an ordinary second module that names one relation `field`
/// exports `_field`; and `xcrun ld -r` over the two objects answers `duplicate
/// symbol '_field'`. Across this corpus, 411 of 652 non-`main` exported symbols
/// (63%) sit in a class where two or more homes export the same spelling. Self
/// hosting REQUIRES linking the eighteen `lib/compiler` modules into one image,
/// so under home-blind symbols that link could not exist — independently of
/// every sema and graph question in front of it.
///
/// ONE AUTHORITY, TWO SIDES. `home_resolve.relationSymbol` decides; the CALLER
/// side (`entity_linkage` for a foreign target, below) and the DEFINER side
/// (this, for everything else) both go through it, so they agree by
/// construction rather than by test. The exemptions live there too and are
/// exactly two — the process entry and a declared foreign boundary.
///
/// The dotted spelling for a method (`Vec.xplus`) is the NAME half, unchanged;
/// `native_backend.linkerSymbolName` still folds its dot to an underscore.
pub fn funcExportName(
    alloc: std.mem.Allocator,
    self_home: ?[]const u8,
    fd: *const ast.FuncDecl,
) Error![]const u8 {
    const name = if (fd.path.len == 1)
        try alloc.dupe(u8, fd.path[0])
    else
        try std.fmt.allocPrint(alloc, "{s}.{s}", .{ fd.path[0], fd.path[fd.path.len - 1] });
    defer alloc.free(name);
    return home_resolve.relationSymbol(alloc, self_home, name, foreignBoundaryName(fd));
}

fn shouldIncludeFuncDecl(fd: *const ast.FuncDecl) bool {
    if (fd.is_local) return false;
    if (funcFfiName(fd.attributes) != null) return false;
    if (fd.path.len == 1 and !fd.method) return true;
    if (fd.method and fd.path.len >= 2) return true;
    // §3 — math.add = (a, b) … static module members (dot, not colon).
    if (fd.path.len >= 2 and !fd.method) return true;
    return false;
}

fn countModuleFunctions(mod: *const ast.Module) usize {
    var n: usize = 0;
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        if (shouldIncludeFuncDecl(&stmt.func_decl)) n += 1;
    }
    return n;
}

fn wrap(mod: *const ast.Module) bool {
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        const fd = &stmt.func_decl;
        if (fd.path.len == 1 and std.mem.eql(u8, fd.path[0], "main") and shouldIncludeFuncDecl(fd))
            return true;
    }
    return false;
}

fn home(graph: *const semantic_graph.SemanticGraph) ?semantic_graph.id {
    for (graph.nodes.items, 0..) |node, i| {
        if (node.scope == null) return @intCast(i);
    }
    return null;
}

fn isFloatType(t: ast.TypeExpr) bool {
    return t == .named and std.mem.eql(u8, t.named, "f64");
}

fn isF64Record(recs: []const dnir.RecordDesc, t: ast.TypeExpr) ?dnir.RecordDesc {
    const r = findRecordName(recs, t) orelse return null;
    if (r.fields.len == 0) return null;
    for (r.kinds) |k| {
        if (k != .f64) return null;
    }
    return r;
}

fn recordKindsMixed(record: dnir.RecordDesc) bool {
    var saw_fp = false;
    var saw_gp = false;
    for (record.kinds) |kind| {
        if (kind == .f64) saw_fp = true else saw_gp = true;
    }
    return saw_fp and saw_gp;
}

/// One entry per ABI argument SLOT: true when the slot travels in v0..v7.
///
/// GAP-056. `emitScalarCallArgs` marshalled every argument with `mov_arg`, which
/// writes x0..x7, no matter what the callee declared. `p(x: f64, y: f64): i64`
/// compiled to a flawless callee (`fcmp d0, d1`) fed by a caller that had put
/// both doubles in x0/x1, so the comparison read whatever d0/d1 happened to
/// hold: `p(3.5, 1.5)` answered 1 where C answered 9. It compiled, ran, and
/// exited cleanly with the wrong number.
///
/// The deleted caller-side f64 result map additionally required an f64 return,
/// while the callee-side `is_float_kernel` flag does not. Parameter placement
/// remains this separate ABI fact; result descriptors now come from the graph.
///
/// Per-SLOT rather than a single all-or-nothing answer because AAPCS64 counts
/// the two register files separately: `f(a: i64, b: f64, c: i64)` is x0, d0, x1
/// — not x0, d1, x2. A shared counter is right for uniform signatures and
/// quietly wrong for every mixture. Mixed signatures are refused by
/// `functionEligible` today, so this is correct by construction rather than by
/// an invariant that has to hold somewhere else.
///
/// Caller owns the returned slice. Null when a record parameter is not one this
/// pass can explode, which is the same refusal the eligibility check makes.
fn paramSlotIsFp(
    alloc: std.mem.Allocator,
    fd: *const ast.FuncDecl,
    recs: []const dnir.RecordDesc,
) Error![]bool {
    var list: std.ArrayListUnmanaged(bool) = .empty;
    errdefer list.deinit(alloc);
    for (fd.func.params) |p| {
        if (isFloatType(p.typ)) {
            try list.append(alloc, true);
        } else if (isF64Record(recs, p.typ)) |r| {
            try list.appendNTimes(alloc, true, r.fields.len);
        } else if (findRecordName(recs, p.typ)) |r| {
            try list.appendNTimes(alloc, false, r.fields.len);
        } else {
            try list.append(alloc, false);
        }
    }
    return list.toOwnedSlice(alloc);
}

fn f64AbiParamSlots(fd: *const ast.FuncDecl, recs: []const dnir.RecordDesc) ?usize {
    var slots: usize = 0;
    for (fd.func.params) |p| {
        if (isFloatType(p.typ)) {
            slots += 1;
        } else if (isF64Record(recs, p.typ)) |r| {
            slots += r.fields.len;
        } else return null;
    }
    return slots;
}

/// A record crossing a function boundary is exploded into one field per
/// argument register, and there are eight of them (x0..x7). Eight is therefore
/// the register file, not a conservative cap.
pub const max_reg_record_fields = 8;

pub fn scalRecordParamSlotCount(field_count: usize) u32 {
    if (field_count > max_reg_record_fields) return 1;
    return @intCast(field_count);
}

pub fn recordUsesOpaquePointer(field_count: usize) bool {
    return field_count > max_reg_record_fields;
}

/// Past `max_reg_record_fields` a record return uses the AAPCS64 indirect-result
/// convention: the CALLER reserves the buffer and passes its address in x8, and
/// the callee writes the fields through it. Bounded so the caller's frame
/// reservation stays a small `sub sp` immediate.
pub const max_record_fields = 32;

/// AAPCS64 passes the first eight general-purpose scalar arguments in x0..x7;
/// arguments past the eighth travel on the stack at [sp,#(i-8)*8] (see
/// `emitPushVarargs` on the caller and the callee prologue's stack-arg load).
/// Sixteen is the total the backend's stack-arg block (`pending_varargs[8]`)
/// can carry: eight registers plus eight stack slots. This retires the
/// application-argument-pack refusal for wide integer relations (e.g. a general
/// order-k linear recurrence passing k coefficients + k seeds + N) — no packing.
/// Floating-point and record arguments stay capped at the eight-register file.
pub const max_direct_scalar_args = 16;

fn gpPackType(t: ast.TypeExpr) ?RT {
    const resolved = resolveType(t);
    return switch (resolved) {
        .i8,
        .i16,
        .i32,
        .i64,
        .u8,
        .u16,
        .u32,
        .u64,
        .bool,
        .str,
        .pointer,
        => resolved,
        else => null,
    };
}

fn resultPackTypes(alloc: std.mem.Allocator, t: ast.TypeExpr) Error![]const RT {
    if (t != .tuple) return &.{};
    if (t.tuple.len == 0 or t.tuple.len > max_reg_record_fields) return error.UnsupportedConstruct;
    const out = try alloc.alloc(RT, t.tuple.len);
    errdefer alloc.free(out);
    for (t.tuple, 0..) |item, i| {
        out[i] = gpPackType(item) orelse return error.UnsupportedConstruct;
    }
    return out;
}

/// AAPCS64 §6.9: a composite RESULT larger than 16 bytes is returned through a
/// caller-allocated buffer whose address the caller passes in x8. At or under 16
/// bytes it comes back in x0/x1. Every field this backend puts in a scalar record
/// occupies 8 bytes — i64, str-as-address, and f64 materialized as its bit
/// pattern all store at an 8-byte stride — so the size test is a field count.
pub const foreign_reg_record_bytes = 16;

/// True when a record return must use the x8 indirect-result convention rather
/// than the x0..x7 explosion.
///
/// THE THRESHOLD IS A PROPERTY OF THE BOUNDARY, NOT OF THE RECORD, and that is
/// the whole content of this function. Two conventions meet here:
///
///     internal (foreign = false)   > max_reg_record_fields, i.e. > 64 bytes
///     foreign  (foreign = true)    > foreign_reg_record_bytes, i.e. > 16 bytes
///
/// Idol's own convention is the wider one ON PURPOSE: a 24-byte result stays in
/// x0..x2 with no buffer, no stores and no reload, which is strictly cheaper
/// than C's, and `AGENTS.md` forbids the C ABI from becoming the internal
/// application ABI. But a relation that declares `@comp.c.export("n")` has told
/// a C compiler what convention to expect, and C's answer is 16.
///
/// MEASURED, and this is why the parameter exists rather than a constant. A
/// relation exporting a 3..8-field record answered a C caller with GARBAGE —
/// `ok compile`, exit 0, no diagnostic:
///
///     fields  bytes   before            after
///     1..2     8..16  correct           correct   (x0/x1 either way)
///     3..8    24..64  SILENT GARBAGE    correct   (x8 indirect)
///     9..    72..     correct           correct   (x8 either way)
///
/// The window is exactly the span where the two conventions disagree, which is
/// what a single hardcoded threshold read at a boundary must produce.
///
/// ONE FUNCTION, TWO READERS, BY CONSTRUCTION. This predicate had ZERO consumers
/// while `native_backend` compared against `max_reg_record_fields` inline in
/// three places — a fact with no consumer beside three copies of itself, which
/// is how the callee and the caller are able to disagree at all. The callee
/// prologue and `indirectResultBuffer` both read it now, so the convention
/// cannot fork again without editing the sentence that defines it.
pub fn recordReturnIsIndirectFields(fields: usize, foreign: bool) bool {
    if (foreign) return fields * 8 > foreign_reg_record_bytes;
    return fields > max_reg_record_fields;
}

pub fn recordReturnIsIndirect(rec: dnir.RecordDesc, foreign: bool) bool {
    return recordReturnIsIndirectFields(rec.fields.len, foreign);
}

/// A payload-free case-set used as a type: ABI-identical to an integer, because
/// its values ARE the module constants `Home.case` folds to. A case-set with
/// payloads carries content and has no scalar ABI here, so it stays ineligible
/// rather than being silently truncated to its tag.
fn typeIsScalarCaseSet(mod: *const ast.Module, typ: ast.TypeExpr) bool {
    const name = switch (typ) {
        .named => |n| n,
        else => return false,
    };
    for (mod.body.stmts) |*st| {
        if (st.* != .enum_def) continue;
        if (!std.mem.eql(u8, st.enum_def.name, name)) continue;
        for (st.enum_def.variants) |v| if (v.payload != null) return false;
        return true;
    }
    return false;
}

fn functionEligible(
    fd: *const ast.FuncDecl,
    recs: []const dnir.RecordDesc,
    graph: *const semantic_graph.SemanticGraph,
    mod: *const ast.Module,
) bool {
    if (fd.func.vararg or fd.func.vararg_name != null) return false;
    if (recordForTypeExpr(recs, fd.func.ret_type, graph)) |rec| {
        if (rec.fields.len == 0 or rec.fields.len > max_record_fields) return false;
        // The caller-side indirect buffer understands a mixed exact shape, but
        // this backend does not yet have mixed GP/FP stores for an INDIRECT
        // callee return. Keep only that case refused. A two-word C result and
        // an up-to-eight-word internal result already travel in registers and
        // are pinned by recordabi's mixed-result controls.
        // Mixed GP/FP indirect returns are lowered through x8 + per-field
        // stores (see native_backend ret_record indirect arm). Foreign-boundary
        // mixed indirect shapes stay refused until the C ABI path exists.
        if (foreignBoundaryName(fd) != null and recordKindsMixed(rec) and
            recordReturnIsIndirectFields(rec.fields.len, true)) return false;
        // An f64 record rides v0..v7 as a homogeneous float aggregate; there is
        // no indirect form for it here, so its own eight stays a hard limit.
        if (isF64Record(recs, fd.func.ret_type)) |_| {
            if (rec.fields.len > max_reg_record_fields) return false;
        }
        for (fd.func.params) |p| {
            // A record PARAMETER is still one field per argument register —
            // only the RETURN gained an indirect form. Admitting a wide record
            // here would explode past x7 and read caller garbage.
            if (recordForTypeExpr(recs, p.typ, graph)) |r| {
                var all_f64 = r.fields.len > 0;
                for (r.kinds) |k| {
                    if (k != .f64) {
                        all_f64 = false;
                        break;
                    }
                }
                if (all_f64) {
                    if (r.fields.len > max_reg_record_fields) return false;
                    continue;
                }
                continue;
            }
            if (isFloatType(p.typ)) continue;
            if (p.typ == .named) continue;
            if (!isIntType(p.typ) and !isBoolType(p.typ) and !isStrType(p.typ) and !typeIsPtr(p.typ) and
                !typeIsScalarCaseSet(mod, p.typ)) return false;
        }
        return true;
    }
    if (fd.func.ret_type == .tuple) {
        if (foreignBoundaryName(fd) != null or fd.func.ret_type.tuple.len == 0 or
            fd.func.ret_type.tuple.len > max_reg_record_fields) return false;
        for (fd.func.ret_type.tuple) |item| if (gpPackType(item) == null) return false;
    } else if (!isFloatType(fd.func.ret_type) and !isIntType(fd.func.ret_type) and !isBoolType(fd.func.ret_type) and
        !isStrType(fd.func.ret_type) and !isVoidType(fd.func.ret_type) and !typeIsPtr(fd.func.ret_type) and
        !typeIsScalarCaseSet(mod, fd.func.ret_type) and
        fd.func.ret_type != .inferred) return false;
    // AAPCS64 assigns the result and argument register classes independently.
    // Determine the parameter file from parameter descriptors, never from the
    // result descriptor.
    if (f64AbiParamSlots(fd, recs)) |slots| {
        if (slots > 0) return slots <= 8;
    }
    var gp_slots: usize = 0;
    for (fd.func.params) |p| {
        if (isFloatType(p.typ)) return false;
        if (recordForTypeExpr(recs, p.typ, graph)) |r| {
            var all_f64 = r.fields.len > 0;
            for (r.kinds) |k| {
                if (k != .f64) {
                    all_f64 = false;
                    break;
                }
            }
            if (all_f64) return false;
        }
        if (recordForTypeExpr(recs, p.typ, graph)) |r| {
            // Wide module tables (`lexer`, …) cross calls as one opaque handle,
            // matching `checkedScalarOperand`'s `.table_type` local path.
            if (r.fields.len > max_reg_record_fields) {
                gp_slots += 1;
            } else {
                gp_slots += r.fields.len;
            }
            // A record parameter is homed from the argument registers only; its
            // fields are never stacked, so it must fit inside x0..x7.
            if (gp_slots > max_reg_record_fields) return false;
            continue;
        }
        // `ptr` rides x0..x7 like an i64 — it is the base address of a
        // memory-backed positional table (SH-04).
        if (p.typ == .named) {
            gp_slots += 1;
            if (gp_slots > max_reg_record_fields) return false;
            continue;
        }
        if (!isIntType(p.typ) and !isBoolType(p.typ) and !isStrType(p.typ) and !typeIsPtr(p.typ) and
            !typeIsScalarCaseSet(mod, p.typ)) return false;
        gp_slots += 1;
        if (gp_slots > max_direct_scalar_args) return false;
    }
    return true;
}

const GraphFieldFact = struct {
    kind: dnir.FieldKind,
    width: ?RT,
};

fn graphFieldFact(descriptor: RT) ?GraphFieldFact {
    return switch (descriptor) {
        .str => .{ .kind = .str, .width = null },
        .f64 => .{ .kind = .f64, .width = null },
        .i8, .i16, .i32, .u8, .u16, .u32 => .{ .kind = .i64, .width = descriptor },
        .i64, .u64, .bool => .{ .kind = .i64, .width = null },
        else => null,
    };
}

fn shapeOnStack(stack: []const semantic_graph.id, shape: semantic_graph.id) bool {
    for (stack) |candidate| if (candidate == shape) return true;
    return false;
}


fn memberDescriptorFromShapeAst(
    graph: *const semantic_graph.SemanticGraph,
    shape: semantic_graph.id,
    member_name: []const u8,
    alloc: std.mem.Allocator,
) Error!?types.ResolvedType {
    const shape_node = graph.get(shape) orelse return null;
    const raw = shape_node.ast_ref orelse return null;
    const ad: *const ast.AliasDef = @ptrCast(@alignCast(raw));
    for (ad.fields) |field| {
        if (!std.mem.eql(u8, field.name, member_name)) continue;
        return try types.resolve(field.typ, null, alloc);
    }
    return null;
}

fn appendGraphRecordFields(
    alloc: std.mem.Allocator,
    graph: *const semantic_graph.SemanticGraph,
    shape: semantic_graph.id,
    prefix: []const u8,
    stack: *std.ArrayListUnmanaged(semantic_graph.id),
    names: *std.ArrayListUnmanaged([]const u8),
    kinds: *std.ArrayListUnmanaged(dnir.FieldKind),
    widths: *std.ArrayListUnmanaged(?RT),
) Error!bool {
    if (shapeOnStack(stack.items, shape)) return false;
    try stack.append(alloc, shape);
    defer _ = stack.pop();
    const members = try graph.membersOf(shape, alloc);
    defer alloc.free(members);
    if (members.len == 0) return false;
    for (members) |member| {
        const node = graph.get(member) orelse return false;
        const member_name = node.name orelse return false;
        const path = if (prefix.len == 0)
            try alloc.dupe(u8, member_name)
        else
            try std.fmt.allocPrint(alloc, "{s}.{s}", .{ prefix, member_name });
        if (graph.descriptorShape(member, 0)) |nested| {
            defer alloc.free(path);
            if (!try appendGraphRecordFields(alloc, graph, nested, path, stack, names, kinds, widths)) return false;
            continue;
        }
        const descriptor = if (node.descriptor) |existing|
            existing
        else
            (try memberDescriptorFromShapeAst(graph, shape, member_name, alloc)) orelse {
                alloc.free(path);
                return false;
            };
        const fact = graphFieldFact(descriptor) orelse {
            alloc.free(path);
            return false;
        };
        names.append(alloc, path) catch |err| {
            alloc.free(path);
            return err;
        };
        try kinds.append(alloc, fact.kind);
        try widths.append(alloc, fact.width);
        if (names.items.len > max_record_fields) return false;
    }
    return true;
}

fn moduleAliasByName(mod: *const ast.Module, name: []const u8) ?*const ast.AliasDef {
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .alias_def) continue;
        if (std.mem.eql(u8, stmt.alias_def.name, name)) return &stmt.alias_def;
    }
    return null;
}

fn astFieldFact(typ: ast.TypeExpr) ?GraphFieldFact {
    return switch (typ) {
        .named => |n| blk: {
            if (std.mem.eql(u8, n, "str")) break :blk .{ .kind = .str, .width = null };
            if (std.mem.eql(u8, n, "f64")) break :blk .{ .kind = .f64, .width = null };
            if (isIntType(typ) or isBoolType(typ)) break :blk .{ .kind = .i64, .width = null };
            break :blk null;
        },
        .array, .pointer => .{ .kind = .i64, .width = null },
        else => null,
    };
}

fn aliasNameOnStack(stack: []const []const u8, name: []const u8) bool {
    for (stack) |candidate| if (std.mem.eql(u8, candidate, name)) return true;
    return false;
}

fn appendModuleAliasFields(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    alias: *const ast.AliasDef,
    prefix: []const u8,
    stack: *std.ArrayListUnmanaged([]const u8),
    names: *std.ArrayListUnmanaged([]const u8),
    kinds: *std.ArrayListUnmanaged(dnir.FieldKind),
    widths: *std.ArrayListUnmanaged(?RT),
) Error!bool {
    if (aliasNameOnStack(stack.items, alias.name)) return false;
    try stack.append(alloc, alias.name);
    defer _ = stack.pop();
    for (alias.fields) |field| {
        if (field.is_private) continue;
        const path = if (prefix.len == 0)
            try alloc.dupe(u8, field.name)
        else
            try std.fmt.allocPrint(alloc, "{s}.{s}", .{ prefix, field.name });
        if (field.typ == .named) {
            if (moduleAliasByName(mod, field.typ.named)) |nested| {
                if (!try appendModuleAliasFields(alloc, mod, nested, path, stack, names, kinds, widths)) {
                    alloc.free(path);
                    return false;
                }
                continue;
            }
        }
        const fact = astFieldFact(field.typ) orelse {
            alloc.free(path);
            return false;
        };
        try names.append(alloc, path);
        try kinds.append(alloc, fact.kind);
        try widths.append(alloc, fact.width);
        if (names.items.len > max_record_fields) return false;
    }
    return true;
}


fn appendModuleRecordTypeFields(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    prefix: []const u8,
    stack: *std.ArrayListUnmanaged([]const u8),
    fields: []const ast.RecordField,
    names: *std.ArrayListUnmanaged([]const u8),
    kinds: *std.ArrayListUnmanaged(dnir.FieldKind),
    widths: *std.ArrayListUnmanaged(?RT),
) Error!bool {
    for (fields) |field| {
        const path = if (prefix.len == 0)
            try alloc.dupe(u8, field.name)
        else
            try std.fmt.allocPrint(alloc, "{s}.{s}", .{ prefix, field.name });
        if (field.typ == .named) {
            if (moduleAliasByName(mod, field.typ.named)) |nested| {
                if (!try appendModuleAliasFields(alloc, mod, nested, path, stack, names, kinds, widths)) {
                    alloc.free(path);
                    return false;
                }
                continue;
            }
        }
        const fact = astFieldFact(field.typ) orelse {
            alloc.free(path);
            return false;
        };
        try names.append(alloc, path);
        try kinds.append(alloc, fact.kind);
        try widths.append(alloc, fact.width);
        if (names.items.len > max_record_fields) return false;
    }
    return true;
}

/// File-level `alias` tables (`pack`, `token`, `lexer`, …) are physical layouts
/// even when sema did not publish a graph table shape for them. Graph shapes win
/// on name collision; aliases fill the gap for module-local record params/returns.
fn collectRecordsFromModuleAliases(
    alloc: std.mem.Allocator,
    out: *std.ArrayList(dnir.RecordDesc),
    mod: *const ast.Module,
) Error!void {
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .alias_def) continue;
        const ad = &stmt.alias_def;
        var names: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (names.items) |name| alloc.free(name);
            names.deinit(alloc);
        }
        var kinds: std.ArrayListUnmanaged(dnir.FieldKind) = .empty;
        defer kinds.deinit(alloc);
        var widths: std.ArrayListUnmanaged(?RT) = .empty;
        defer widths.deinit(alloc);
        var stack: std.ArrayListUnmanaged([]const u8) = .empty;
        defer stack.deinit(alloc);
        const appended = if (ad.fields.len > 0)
            try appendModuleAliasFields(alloc, mod, ad, "", &stack, &names, &kinds, &widths)
        else if (ad.target) |target|
            target == .record and try appendModuleRecordTypeFields(
                alloc,
                mod,
                "",
                &stack,
                target.record.fields,
                &names,
                &kinds,
                &widths,
            )
        else
            false;
        if (!appended) continue;
        const owned_fields = try names.toOwnedSlice(alloc);
        errdefer {
            for (owned_fields) |name| alloc.free(name);
            alloc.free(owned_fields);
        }
        const owned_kinds = try kinds.toOwnedSlice(alloc);
        errdefer alloc.free(owned_kinds);
        const owned_widths = try widths.toOwnedSlice(alloc);
        errdefer alloc.free(owned_widths);
        if (findRecordName(out.items, .{ .named = ad.name })) |existing| {
            if (owned_fields.len <= existing.fields.len) {
                for (owned_fields) |name| alloc.free(name);
                alloc.free(owned_fields);
                alloc.free(owned_kinds);
                alloc.free(owned_widths);
                continue;
            }
            removeRecordByExactName(alloc, out, ad.name);
        }
        const name = try alloc.dupe(u8, ad.name);
        const record: dnir.RecordDesc = .{
            .name = name,
            .fields = owned_fields,
            .kinds = owned_kinds,
            .widths = owned_widths,
        };
        out.append(alloc, record) catch |err| {
            deinitRecord(alloc, record);
            return err;
        };
    }
}

/// Physical record layouts are a projection of exact graph descriptor edges.
/// The retired implementation walked local alias AST and then matched result
/// descriptor names downstream; that made imported and nested result shapes
/// unknowable even though sema had already resolved their homes.
fn collectRecordsFromGraph(
    alloc: std.mem.Allocator,
    out: *std.ArrayList(dnir.RecordDesc),
    graph: *const semantic_graph.SemanticGraph,
) Error!void {
    const shapes = try graph.tableDescriptorHomes(alloc);
    defer alloc.free(shapes);
    for (shapes) |shape| {
        const node = graph.tableShapeEntity(shape) orelse continue;
        const semantic_name = node.name orelse continue;
        var names: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (names.items) |name| alloc.free(name);
            names.deinit(alloc);
        }
        var kinds: std.ArrayListUnmanaged(dnir.FieldKind) = .empty;
        defer kinds.deinit(alloc);
        var widths: std.ArrayListUnmanaged(?RT) = .empty;
        defer widths.deinit(alloc);
        var stack: std.ArrayListUnmanaged(semantic_graph.id) = .empty;
        defer stack.deinit(alloc);
        if (!try appendGraphRecordFields(alloc, graph, shape, "", &stack, &names, &kinds, &widths)) continue;
        const owned_fields = try names.toOwnedSlice(alloc);
        errdefer {
            for (owned_fields) |name| alloc.free(name);
            alloc.free(owned_fields);
        }
        const owned_kinds = try kinds.toOwnedSlice(alloc);
        errdefer alloc.free(owned_kinds);
        const owned_widths = try widths.toOwnedSlice(alloc);
        errdefer alloc.free(owned_widths);
        const name = if (node.foreign_home != null)
            try std.fmt.allocPrint(alloc, "$shape.{d}", .{shape})
        else
            try alloc.dupe(u8, semantic_name);
        const record: dnir.RecordDesc = .{
            .semantic_shape = shape,
            .name = name,
            .fields = owned_fields,
            .kinds = owned_kinds,
            .widths = owned_widths,
        };
        out.append(alloc, record) catch |err| {
            deinitRecord(alloc, record);
            return err;
        };
    }
}

/// Colon-method declarations park result type in `path[1]` while ret stays inferred.
fn recordReturnNameForDecl(
    records: []const dnir.RecordDesc,
    graph: *const semantic_graph.SemanticGraph,
    fd: *const ast.FuncDecl,
) ?[]const u8 {
    if (findRecordName(records, fd.func.ret_type)) |rec| return rec.name;
    if (fd.func.ret_type == .named) {
        if (findRecordByNominal(records, fd.func.ret_type.named, graph)) |rec| return rec.name;
    }
    if (fd.method and fd.path.len >= 2 and fd.func.ret_type == .inferred) {
        const parked: ast.TypeExpr = .{ .named = fd.path[1] };
        if (findRecordName(records, parked)) |rec| return rec.name;
        if (findRecordByNominal(records, fd.path[1], graph)) |rec| return rec.name;
    }
    return null;
}

fn findRecordName(recs: []const dnir.RecordDesc, t: ast.TypeExpr) ?dnir.RecordDesc {
    if (t != .named) return null;
    for (recs) |r| {
        if (std.mem.eql(u8, r.name, t.named)) return r;
    }
    return null;
}


fn removeRecordByExactName(
    alloc: std.mem.Allocator,
    out: *std.ArrayList(dnir.RecordDesc),
    name: []const u8,
) void {
    for (out.items, 0..) |record, i| {
        if (std.mem.eql(u8, record.name, name)) {
            deinitRecord(alloc, record);
            _ = out.orderedRemove(i);
            return;
        }
    }
}

fn richestRecordForNominal(
    recs: []const dnir.RecordDesc,
    graph: *const semantic_graph.SemanticGraph,
    name: []const u8,
) ?dnir.RecordDesc {
    var best: ?dnir.RecordDesc = null;
    for (recs) |record| {
        if (!checkedRecordResultSupported(record)) continue;
        const matches_name = std.mem.eql(u8, record.name, name);
        const matches_nominal = blk: {
            const shape = record.semantic_shape orelse break :blk false;
            const shape_node = graph.tableShapeEntity(shape) orelse break :blk false;
            break :blk shape_node.name != null and std.mem.eql(u8, shape_node.name.?, name);
        };
        if (!matches_name and !matches_nominal) continue;
        if (best == null or record.fields.len > best.?.fields.len) best = record;
    }
    return best;
}

fn physicalRecordName(ctx: *const LowerCtx, record: dnir.RecordDesc) []const u8 {
    if (record.semantic_shape) |shape| {
        if (ctx.graph.tableShapeEntity(shape)) |node| {
            if (node.name) |nominal| {
                if (richestRecordForNominal(ctx.records, ctx.graph, nominal)) |rich| {
                    if (!std.mem.startsWith(u8, rich.name, "$shape.")) return rich.name;
                }
                if (findRecordName(ctx.records, .{ .named = nominal })) |by_name| return by_name.name;
            }
        }
    }
    return record.name;
}

fn findRecordByNominal(
    recs: []const dnir.RecordDesc,
    name: []const u8,
    graph: ?*const semantic_graph.SemanticGraph,
) ?dnir.RecordDesc {
    for (recs) |r| {
        if (std.mem.eql(u8, r.name, name)) return r;
    }
    if (graph) |g| {
        for (recs) |record| {
            const shape = record.semantic_shape orelse continue;
            const shape_node = g.get(shape) orelse continue;
            if (shape_node.name) |n| {
                if (std.mem.eql(u8, n, name) and checkedRecordResultSupported(record)) return record;
            }
        }
    }
    return null;
}

fn recordForTypeExpr(
    recs: []const dnir.RecordDesc,
    t: ast.TypeExpr,
    graph: *const semantic_graph.SemanticGraph,
) ?dnir.RecordDesc {
    if (findRecordName(recs, t)) |rec| return rec;
    if (t == .named) {
        if (findRecordByNominal(recs, t.named, graph)) |rec| return rec;
    }
    return null;
}

fn recordFieldKindForParam(
    ctx: *const LowerCtx,
    obj_name: []const u8,
    field_name: []const u8,
) ?dnir.FieldKind {
    if (ctx.param_record_types.get(obj_name)) |rec_name| {
        const rec = blk: {
            for (ctx.records) |r| {
                if (std.mem.eql(u8, r.name, rec_name)) break :blk r;
            }
            if (findRecordByNominal(ctx.records, rec_name, ctx.graph)) |r| break :blk r;
            break :blk null;
        } orelse return null;
        for (rec.fields, rec.kinds) |fname, kind| {
            if (std.mem.eql(u8, fname, field_name)) return kind;
        }
    }
    return null;
}

fn tableFieldKind(field: types.FieldType) ?dnir.FieldKind {
    return switch (field.typ) {
        .str => .str,
        .f64 => .f64,
        .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .bool => .i64,
        else => null,
    };
}

fn recordDescForParamName(ctx: *const LowerCtx, obj_name: []const u8) ?dnir.RecordDesc {
    const rec_name = ctx.param_record_types.get(obj_name) orelse return null;
    for (ctx.records) |rec| {
        if (std.mem.eql(u8, rec.name, rec_name)) return rec;
    }
    return findRecordByNominal(ctx.records, rec_name, ctx.graph);
}

const OpaqueRecordParam = struct { slot: u32, rec_name: []const u8 };

const OpaqueRecordCopySrc = union(enum) {
    opaque_param: OpaqueRecordParam,
    local_base: []const u8,
};

fn copyOpaqueRecordNestedFields(
    ctx: *LowerCtx,
    dest: OpaqueRecordParam,
    src: OpaqueRecordCopySrc,
    prefix: []const u8,
) Error!void {
    const dest_rec = blk: {
        for (ctx.records) |rec| {
            if (std.mem.eql(u8, rec.name, dest.rec_name)) break :blk rec;
        }
        break :blk findRecordByNominal(ctx.records, dest.rec_name, ctx.graph) orelse
            return bail(ctx.diagnostic, @src());
    };
    var prefix_buf: [512]u8 = undefined;
    const prefix_pat = std.fmt.bufPrint(&prefix_buf, "{s}.", .{prefix}) catch return bail(ctx.diagnostic, @src());
    for (dest_rec.fields, dest_rec.kinds) |fname, kind| {
        if (!std.mem.startsWith(u8, fname, prefix_pat)) continue;
        const rt: RT = switch (kind) {
            .f64 => .f64,
            .str => .str,
            .i64 => .any,
        };
        const v: dnir.Value = switch (src) {
            .opaque_param => |src_opaque| blk: {
                const t = ctx.freshTemp();
                try ctx.emit(.{
                    .op = .load_field,
                    .result = t,
                    .rhs = .{ .local = src_opaque.slot },
                    .record = src_opaque.rec_name,
                    .field = try ctx.alloc.dupe(u8, fname),
                    .ty = rt,
                });
                if (rt == .f64) try ctx.f64_slots.put(ctx.alloc, t, {});
                if (rt == .str) try ctx.str_slots.put(ctx.alloc, t, {});
                break :blk .{ .temp = t };
            },
            .local_base => |base| blk: {
                const suffix = fname[prefix_pat.len..];
                const nested_key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ base, fname });
                defer ctx.alloc.free(nested_key);
                if (ctx.locals.get(nested_key)) |slot| break :blk .{ .local = slot };
                const flat_key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ base, suffix });
                defer ctx.alloc.free(flat_key);
                if (ctx.locals.get(flat_key)) |slot| break :blk .{ .local = slot };
                if (try loadFieldFromOpaquePath(ctx, nested_key, null)) |loaded| break :blk loaded;
                if (try loadFieldFromOpaquePath(ctx, flat_key, null)) |loaded| break :blk loaded;
                return bail(ctx.diagnostic, @src());
            },
        };
        try ctx.emit(.{
            .op = .store_field,
            .rhs = .{ .local = dest.slot },
            .record = dest.rec_name,
            .field = try ctx.alloc.dupe(u8, fname),
            .lhs = v,
            .ty = rt,
        });
    }
    subsumeProducerRefit(ctx);
}

fn recordFieldPrefixPresent(record: dnir.RecordDesc, prefix: []const u8) bool {
    if (prefix.len == 0) return false;
    var dotted: [512]u8 = undefined;
    const pat = std.fmt.bufPrint(&dotted, "{s}.", .{prefix}) catch return false;
    for (record.fields) |name| {
        if (std.mem.eql(u8, name, prefix)) return true;
        if (std.mem.startsWith(u8, name, pat)) return true;
    }
    return false;
}

fn recordFieldHasNestedFields(record: dnir.RecordDesc, prefix: []const u8) bool {
    if (prefix.len == 0) return false;
    var dotted: [512]u8 = undefined;
    const pat = std.fmt.bufPrint(&dotted, "{s}.", .{prefix}) catch return false;
    for (record.fields) |name| {
        if (std.mem.startsWith(u8, name, pat)) return true;
    }
    return false;
}

fn recordDescForOpaqueParam(ctx: *const LowerCtx, opaque_param: OpaqueRecordParam) ?dnir.RecordDesc {
    for (ctx.records) |rec| {
        if (std.mem.eql(u8, rec.name, opaque_param.rec_name)) return rec;
    }
    return findRecordByNominal(ctx.records, opaque_param.rec_name, ctx.graph);
}

fn copyOpaqueToFlatPrefixedFields(
    ctx: *LowerCtx,
    dest_prefix: []const u8,
    src: OpaqueRecordParam,
    prefix: []const u8,
) Error!void {
    const src_rec = recordDescForOpaqueParam(ctx, src) orelse return bail(ctx.diagnostic, @src());
    var prefix_buf: [512]u8 = undefined;
    const prefix_pat = std.fmt.bufPrint(&prefix_buf, "{s}.", .{prefix}) catch return bail(ctx.diagnostic, @src());
    for (src_rec.fields, src_rec.kinds) |fname, kind| {
        if (!std.mem.startsWith(u8, fname, prefix_pat)) continue;
        const suffix = fname[prefix_pat.len..];
        const dest_key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ dest_prefix, suffix });
        defer ctx.alloc.free(dest_key);
        const rt: RT = switch (kind) {
            .f64 => .f64,
            .str => .str,
            .i64 => .any,
        };
        const t = ctx.freshTemp();
        try ctx.emit(.{
            .op = .load_field,
            .result = t,
            .rhs = .{ .local = src.slot },
            .record = src.rec_name,
            .field = try ctx.alloc.dupe(u8, fname),
            .ty = rt,
        });
        if (rt == .f64) try ctx.f64_slots.put(ctx.alloc, t, {});
        if (rt == .str) try ctx.str_slots.put(ctx.alloc, t, {});
        const v: dnir.Value = .{ .temp = t };
        if (ctx.locals.get(dest_key)) |dest_slot| {
            try ctx.emit(.{ .op = .store_local, .result = dest_slot, .lhs = v, .ty = rt });
        } else {
            const slot = ctx.freshTemp();
            try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, dest_key), slot);
            if (rt == .f64) try ctx.f64_slots.put(ctx.alloc, slot, {});
            if (rt == .str) try ctx.str_slots.put(ctx.alloc, slot, {});
            try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = rt });
        }
    }
    subsumeProducerRefit(ctx);
}

fn copyFlatToOpaquePrefixedFields(
    ctx: *LowerCtx,
    dest: OpaqueRecordParam,
    src_base: []const u8,
    prefix: []const u8,
) Error!void {
    const dest_rec = recordDescForOpaqueParam(ctx, dest) orelse return bail(ctx.diagnostic, @src());
    var prefix_buf: [512]u8 = undefined;
    const prefix_pat = std.fmt.bufPrint(&prefix_buf, "{s}.", .{prefix}) catch return bail(ctx.diagnostic, @src());
    for (dest_rec.fields, dest_rec.kinds) |fname, kind| {
        if (!std.mem.startsWith(u8, fname, prefix_pat)) continue;
        const suffix = fname[prefix_pat.len..];
        const src_key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ src_base, suffix });
        defer ctx.alloc.free(src_key);
        const v: dnir.Value = if (ctx.locals.get(src_key)) |slot| .{ .local = slot } else blk: {
            if (try loadFieldFromOpaquePath(ctx, src_key, null)) |loaded| break :blk loaded;
            return bail(ctx.diagnostic, @src());
        };
        const rt: RT = switch (kind) {
            .f64 => .f64,
            .str => .str,
            .i64 => .any,
        };
        try ctx.emit(.{
            .op = .store_field,
            .rhs = .{ .local = dest.slot },
            .record = dest.rec_name,
            .field = try ctx.alloc.dupe(u8, fname),
            .lhs = v,
            .ty = rt,
        });
    }
    subsumeProducerRefit(ctx);
}

fn storeOpaqueParamScalarField(
    ctx: *LowerCtx,
    dest: OpaqueRecordParam,
    field_name: []const u8,
    value: dnir.Value,
    store_ty: RT,
) Error!void {
    try ctx.emit(.{
        .op = .store_field,
        .rhs = .{ .local = dest.slot },
        .record = dest.rec_name,
        .field = try ctx.alloc.dupe(u8, field_name),
        .lhs = value,
        .ty = store_ty,
    });
    subsumeProducerRefit(ctx);
}

fn loadOpaqueParamScalarField(
    ctx: *LowerCtx,
    src_name: []const u8,
    src: OpaqueRecordParam,
    field_name: []const u8,
) Error!dnir.Value {
    const rt: RT = switch (recordFieldKindForParam(ctx, src_name, field_name) orelse .i64) {
        .f64 => .f64,
        .str => .str,
        .i64 => .any,
    };
    const t = ctx.freshTemp();
    try ctx.emit(.{
        .op = .load_field,
        .result = t,
        .rhs = .{ .local = src.slot },
        .record = src.rec_name,
        .field = try ctx.alloc.dupe(u8, field_name),
        .ty = rt,
    });
    if (rt == .f64) try ctx.f64_slots.put(ctx.alloc, t, {});
    if (rt == .str) try ctx.str_slots.put(ctx.alloc, t, {});
    return .{ .temp = t };
}

fn recordCoversTableFields(record: dnir.RecordDesc, fields: []const types.FieldType) bool {
    if (!checkedRecordResultSupported(record)) return false;
    for (fields) |field| {
        if (tableFieldKind(field)) |want_kind| {
            var found = false;
            for (record.fields, record.kinds) |name, kind| {
                if (!std.mem.eql(u8, name, field.name)) continue;
                if (kind != want_kind) return false;
                found = true;
                break;
            }
            if (!found) return false;
        } else if (!recordFieldPrefixPresent(record, field.name)) {
            return false;
        }
    }
    return true;
}


pub const LowerCtx = struct {
    alloc: std.mem.Allocator,
    diagnostic: *Diagnostic,
    records: []const dnir.RecordDesc,
    graph: *const semantic_graph.SemanticGraph,
    occurrences: *const OccurrenceBridge,
    require_graph_facts: bool,
    /// Some table in this function is too wide for a select chain, so EVERY
    /// positional table here is materialized into frame memory. See
    /// `stmtsBindWideTable` for why the choice is per-function, not per-table.
    tables_in_memory: bool = false,
    externs: *std.ArrayList(dnir.Extern),
    func_record_returns: *std.StringHashMapUnmanaged([]const u8),
    /// GAP-056: per-callee ABI slot classes, so a caller marshals f64 arguments
    /// into v0..v7 instead of x0..x7. Empty means no callee needs FP slots.
    fp_params: *const std.StringHashMapUnmanaged([]bool) = &empty_fp_params,
    /// GAP-056: this function's own f64 parameters are homed in d0..d7, so
    /// staging an outgoing f64 argument would overwrite one of them.
    self_fp_params: bool = false,
    /// Whether the block currently being lowered is a return context — i.e. its
    /// value is the function's answer. A guard `if` in NON-tail position uses
    /// this to know its value-carrying branches are function exits (guard
    /// clauses) that must early-return, without disturbing the tail-slot rule
    /// that keeps trailing assignments/effects falling through.
    block_answering: bool = false,
    /// When set, tail/table returns lower to `ret_record` for this record name.
    ret_record: ?[]const u8 = null,
    /// Ordered physical classes for a graph-owned multi-result pack. Empty for
    /// scalar/void functions; no tuple representation is introduced.
    ret_pack: []const RT = &.{},
    /// Local slots that hold f64 values inside integer kernels.
    f64_slots: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Local slots holding `str` (a `const char*`), so `#s` can lower to strlen.
    str_slots: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Positional tables whose every element is text — `{ "M", "CM", … }` —
    /// and which the rest of the body only READS. `t(k)` on one of these is a
    /// `str` at every index, constant or not.
    ///
    /// Without this set the ELEMENT lowered correctly and its TYPE was lost:
    /// `exprIsStr` had no arm for a table read, so `g = glyph(i)` never entered
    /// `str_slots`, `planConcat` chose `%lld` for `"{out}{g}"`, and printf
    /// printed the literal's ADDRESS. `examples/boring/roman.id` therefore
    /// printed a different answer on every run — the address moves with ASLR —
    /// which is the same defect class as the `v = "set" or "FB"` note on
    /// `exprIsStr` below, reached through the table surface instead.
    str_tables: std.StringHashMapUnmanaged(void) = .empty,
    /// Local slots holding `bool`. A bool rides an integer register, so nothing
    /// downstream can tell one from an i64 by its representation — only this
    /// set can, and `..` needs the answer to choose between `true` and `1`.
    bool_slots: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Local slots whose DECLARED type is narrower than the register that holds
    /// them, keyed slot -> declared width. Set at the declaration and NEVER
    /// cleared: unlike `bool_slots`, which tracks what a slot currently holds,
    /// this is what the source said the binding IS, and a later assignment does
    /// not retype a C `uint32_t`. Every store into one of these carries the
    /// width so the backend can refit — that store is the exact place
    /// `--backend=c` writes `((uint32_t)(...))`.
    narrow_slots: std.AutoHashMapUnmanaged(u32, RT) = .empty,
    /// Slots holding a pointer value — pointer parameters/results and locals
    /// materialized by `materializeTableSlots`. `t[i]` on one of these is a
    /// scaled 8-byte load, not a select-chain.
    ptr_slots: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Wide/opaque record parameters keyed by the parameter name.
    param_record_types: std.StringHashMapUnmanaged([]const u8) = .empty,
    /// Graph aggregate identity to the one physical base temp selected for this
    /// function. The identity and contents stay graph-owned; this map only
    /// avoids emitting a second address materialization for another access.
    aggregate_bases: std.AutoHashMapUnmanaged(semantic_graph.id, u32) = .empty,
    /// Static element count of a positional table, keyed by its `.len` slot, so
    /// `t[i]` with a non-constant `i` knows how many slots to select over.
    table_lens: std.AutoHashMapUnmanaged(u32, i64) = .empty,
    /// Positional tables this function proved DETERMINED: every element is an
    /// integer literal, and the whole body neither writes the name nor lets it
    /// escape. `t(k)` on one of these with a compile-time `k` is the literal,
    /// AT ANY EXTENT — see `noteConstTable`. Owns both key and value.
    const_tables: std.StringHashMapUnmanaged([]i64) = .empty,
    /// The body being lowered, so a binding can ask what the REST of the
    /// function does with the name it is about to bind. `tables_in_memory`
    /// already establishes that a realization choice is allowed to read the
    /// whole body; this makes the same body reachable from the binding site,
    /// which is the only place a representation decision may be taken.
    body: ?*const ast.Block = null,
    /// Module-level integer constants, keyed `Name` or `Name.field`. Populated
    /// from top-level `N = <int>` and `N = @{ f = <int>, ... }` bindings, which
    /// are otherwise invisible inside a function body.
    module_consts: *const ModuleConsts = &empty_module_consts,
    module_globals: *const ModuleGlobals = &empty_module_globals,
    /// Names bound to compile-time-known i64 literals (for numeric for step, etc.).
    const_ints: std.StringHashMapUnmanaged(i64) = .empty,
    /// THE RESULT NAME OF A FUSED BODY RELATION, WHEN THE ELEMENT IT NAMES IS A
    /// LITERAL. Non-empty only while a collection relation is being lowered.
    ///
    /// It exists because a SLOT is not a VALUE to the folder. `xs(1) == 7` on a
    /// determined table folds to two instructions (`constTableRead` answers
    /// `.i64 = 7`, and `binop` over two immediates settles), while the same
    /// comparison against a slot that was just stored `7` does not — measured,
    /// `a = 7 · if a == 7` is 12 instructions today. Storing the element and
    /// binding the name to the slot would therefore have made `xs:any(…)` the
    /// SLOWER way to ask a question with a compile-time answer.
    ///
    /// Consulted BEFORE `locals` in the `.name` arm, which is what makes it a
    /// SHADOW: the element name wins for the length of the body relation, and
    /// an outer binding of the same name means exactly what it meant before and
    /// after. `gate/collection.sh`'s shadow row is the check.
    fused_literals: std.StringHashMapUnmanaged(i64) = .empty,
    next_temp: u32 = 0,
    locals: std.StringHashMapUnmanaged(u32) = .empty,
    instrs: std.ArrayList(dnir.Instr) = .empty,
    /// Exact function entity being lowered. Name resolve walks this home only.
    function: ?semantic_graph.id = null,
    /// The function being lowered, when a self-call in TAIL position can be
    /// turned into a jump. Empty disables the rewrite — see `tryEmitSelfTail`.
    self_name: []const u8 = "",
    /// Its parameter slots, in order. One slot per parameter, which is what
    /// makes the reassign-and-jump legal: a record parameter occupies several
    /// slots and is excluded rather than partially written.
    self_param_slots: []const u32 = &.{},
    /// Instruction indices of `break` branches waiting for the innermost loop end.
    loop_breaks: std.ArrayListUnmanaged(std.ArrayListUnmanaged(u32)) = .empty,
    /// Back-edge targets for `continue` in the innermost loop.
    loop_heads: std.ArrayListUnmanaged(u32) = .empty,
    /// Module-level graph entity id → linker symbol from declaration provenance.
    entity_linkage: *const std.AutoHashMapUnmanaged(semantic_graph.id, []const u8),
    /// Relation level edges declared as `family(level) = (…) …` → `family__level`.
    relation_edges: *const std.StringHashMapUnmanaged([]const u8) = &empty_relation_edges,

    pub fn deinit(self: *LowerCtx) void {
        var it = self.locals.iterator();
        while (it.next()) |e| self.alloc.free(e.key_ptr.*);
        self.locals.deinit(self.alloc);
        self.f64_slots.deinit(self.alloc);
        self.str_slots.deinit(self.alloc);
        self.bool_slots.deinit(self.alloc);
        self.narrow_slots.deinit(self.alloc);
        self.ptr_slots.deinit(self.alloc);
        var pr = self.param_record_types.iterator();
        while (pr.next()) |entry| self.alloc.free(entry.key_ptr.*);
        self.param_record_types.deinit(self.alloc);
        self.aggregate_bases.deinit(self.alloc);
        self.table_lens.deinit(self.alloc);
        var ct = self.const_tables.iterator();
        while (ct.next()) |e| {
            self.alloc.free(e.key_ptr.*);
            self.alloc.free(e.value_ptr.*);
        }
        self.const_tables.deinit(self.alloc);
        var st = self.str_tables.iterator();
        while (st.next()) |e| self.alloc.free(e.key_ptr.*);
        self.str_tables.deinit(self.alloc);
        var ci = self.const_ints.iterator();
        while (ci.next()) |e| self.alloc.free(e.key_ptr.*);
        self.const_ints.deinit(self.alloc);
        // Normally already empty — `ResultName.release` gives the name back at
        // the end of every collection relation. Drained here so a bail out of a
        // half-lowered body relation does not leak the key.
        var fl = self.fused_literals.iterator();
        while (fl.next()) |e| self.alloc.free(e.key_ptr.*);
        self.fused_literals.deinit(self.alloc);
        if (self.self_param_slots.len > 0) self.alloc.free(self.self_param_slots);
        while (self.loop_breaks.pop()) |breaks| {
            var pending = breaks;
            pending.deinit(self.alloc);
        }
        self.loop_breaks.deinit(self.alloc);
        self.loop_heads.deinit(self.alloc);
        self.instrs.deinit(self.alloc);
    }

    fn freshTemp(self: *LowerCtx) u32 {
        const t = self.next_temp;
        self.next_temp += 1;
        return t;
    }

    fn emit(self: *LowerCtx, instr: dnir.Instr) Error!void {
        try self.instrs.append(self.alloc, instr);
    }
};

fn internInstrStrings(alloc: std.mem.Allocator, instrs: []dnir.Instr) Error!void {
    const Strings = struct {
        callee: []const u8 = "",
        req_alias: []const u8 = "",
        field: []const u8 = "",
        record: []const u8 = "",

        fn deinit(self: @This(), allocator: std.mem.Allocator) void {
            if (self.callee.len > 0) allocator.free(self.callee);
            if (self.req_alias.len > 0) allocator.free(self.req_alias);
            if (self.field.len > 0) allocator.free(self.field);
            if (self.record.len > 0) allocator.free(self.record);
        }
    };

    const strings = try alloc.alloc(Strings, instrs.len);
    defer alloc.free(strings);
    for (strings) |*entry| entry.* = .{};
    errdefer for (strings) |entry| entry.deinit(alloc);

    for (instrs, strings) |instruction, *entry| {
        if (instruction.callee.len > 0) entry.callee = try alloc.dupe(u8, instruction.callee);
        if (instruction.req_alias.len > 0) entry.req_alias = try alloc.dupe(u8, instruction.req_alias);
        if (instruction.field.len > 0) entry.field = try alloc.dupe(u8, instruction.field);
        if (instruction.record.len > 0) entry.record = try alloc.dupe(u8, instruction.record);
    }
    for (instrs, strings) |*instruction, entry| {
        instruction.callee = entry.callee;
        instruction.req_alias = entry.req_alias;
        instruction.field = entry.field;
        instruction.record = entry.record;
    }
}

// LAWFUL NONEXECUTION LIVES IN `comptime.zig`, NOT HERE.
//
// `bodyHasNoApplication` / `stmtHasNoApplication` / `exprHasNoApplication` /
// `bodyHasLoop` / `foldWholeBody` stood here and stand there now, verbatim,
// behind `comptime.foldRelationBody`. Keeping a copy on this side would be a
// SECOND IMPLEMENTATION OF ONE PREDICATE — the shape that produced three
// defects on this surface in a day — and the two would only have to disagree
// once for a body to be folded under one rule and lowered under the other.

fn lowerFunction(
    alloc: std.mem.Allocator,
    fd: *const ast.FuncDecl,
    id: ?semantic_graph.id,
    records: []const dnir.RecordDesc,
    graph: *const semantic_graph.SemanticGraph,
    occurrences: *const OccurrenceBridge,
    diagnostic: *Diagnostic,
    require_graph_facts: bool,
    externs: *std.ArrayList(dnir.Extern),
    func_record_returns: *std.StringHashMapUnmanaged([]const u8),
    fp_params: *const std.StringHashMapUnmanaged([]bool),
    module_consts: *const ModuleConsts,
    module_globals: *const ModuleGlobals,
    entity_linkage: *const std.AutoHashMapUnmanaged(semantic_graph.id, []const u8),
    relation_edges: *const std.StringHashMapUnmanaged([]const u8),
) Error!dnir.Function {
    const ret_pack = try resultPackTypes(alloc, fd.func.ret_type);
    errdefer if (ret_pack.len > 0) alloc.free(ret_pack);
    var ctx: LowerCtx = .{
        .alloc = alloc,
        .diagnostic = diagnostic,
        .records = records,
        .graph = graph,
        .function = id,
        .occurrences = occurrences,
        .require_graph_facts = require_graph_facts,
        .externs = externs,
        .func_record_returns = func_record_returns,
        .fp_params = fp_params,
        .entity_linkage = entity_linkage,
        .relation_edges = relation_edges,
        .self_fp_params = blk: {
            const slots = f64AbiParamSlots(fd, records) orelse break :blk false;
            break :blk slots > 0;
        },
        .module_consts = module_consts,
        .module_globals = module_globals,
        .ret_record = if (findRecordName(records, fd.func.ret_type)) |r| r.name else null,
        .ret_pack = ret_pack,
        .tables_in_memory = blockNeedsMemoryTables(&fd.func.body),
        .body = &fd.func.body,
    };
    defer ctx.deinit();

    // A record parameter arrives as its exploded fields in consecutive argument
    // registers — the same shape records already have as locals — so it consumes
    // one slot per field and shifts the slots of every later parameter.
    var param_slot_cursor: u32 = 0;
    // A relation-edge / projection variant (`subject(tail) = (code)`, mangled to
    // `subject__tail`) receives the projection level (`tail`) as an implicit
    // slot-0 parameter. It occupies a real slot, so the flat-frame test below and
    // the self-param set must count it alongside the declared operand params.
    var edge_level_slots: u32 = 0;
    // A relation-edge projection level (`family(level) = (…)`, mangled
    // `family__level`) is a runtime subject parameter ONLY when the body actually
    // reads the level identifier — e.g. `len(path) = (min)` whose body uses
    // `path`, applied `len(value)(min)` / `value:len(min)` with the level passed
    // as an argument. A compile-time-only projection marker — `subject(tail)`,
    // `dot(io)`, `rules(q)` whose bodies never mention the level — is baked into
    // the mangled callee and the call passes only the real operands, so a level
    // slot here would shift every operand by one register.
    if (fd.path.len == 1) {
        if (relationEdgeLevel(fd.path[0])) |level| {
            if (blockMentionsIdent(&fd.func.body, level)) {
                const owned = try alloc.dupe(u8, level);
                ctx.locals.put(alloc, owned, param_slot_cursor) catch |err| {
                    alloc.free(owned);
                    return err;
                };
                try ctx.str_slots.put(alloc, param_slot_cursor, {});
                param_slot_cursor += 1;
                edge_level_slots = 1;
            }
        }
    }
    for (fd.func.params) |par| {
        if (blk: {
            if (findRecordName(records, par.typ)) |r| break :blk r;
            if (par.typ == .named) {
                if (findRecordByNominal(records, par.typ.named, graph)) |r| break :blk r;
            }
            break :blk null;
        }) |rec| {
            const param_key = try alloc.dupe(u8, par.name);
            try ctx.param_record_types.put(alloc, param_key, rec.name);
            if (recordUsesOpaquePointer(rec.fields.len)) {
                const owned = try alloc.dupe(u8, par.name);
                ctx.locals.put(alloc, owned, param_slot_cursor) catch |err| {
                    alloc.free(owned);
                    return err;
                };
                try ctx.ptr_slots.put(alloc, param_slot_cursor, {});
                param_slot_cursor += 1;
                continue;
            }
            // Flatten every record parameter into per-field ABI slots. Nested
            // record shapes are already descriptor-flattened (`peeked_token.kind`,
            // etc.); f64 fields use the f64 slot path below. Treating any f64
            // as "non-scalar" and keeping one opaque param slot broke stack keys
            // like `self.peeked_token.kind` while the backend still expected
            // exploded register slots.
            const all_scalar = rec.fields.len > 0;
            if (all_scalar) {
                for (rec.fields, 0..) |fname, fi| {
                    const key = try std.fmt.allocPrint(alloc, "{s}.{s}", .{ par.name, fname });
                    ctx.locals.put(alloc, key, param_slot_cursor) catch |err| {
                        alloc.free(key);
                        return err;
                    };
                    if (fi < rec.kinds.len) switch (rec.kinds[fi]) {
                        .str => try ctx.str_slots.put(alloc, param_slot_cursor, {}),
                        .f64 => try ctx.f64_slots.put(alloc, param_slot_cursor, {}),
                        .i64 => {},
                    };
                    if (fi < rec.widths.len) if (rec.widths[fi]) |width| {
                        try ctx.narrow_slots.put(alloc, param_slot_cursor, width);
                    };
                    param_slot_cursor += 1;
                }
                continue;
            }
        }
        const owned = try alloc.dupe(u8, par.name);
        ctx.locals.put(alloc, owned, param_slot_cursor) catch |err| {
            alloc.free(owned);
            return err;
        };
        // A `str` parameter is a `const char*`, so `#p` inside the body can use
        // strlen just like a str local.
        if (resolveType(par.typ) == .str) try ctx.str_slots.put(alloc, param_slot_cursor, {});
        // A `bool` parameter is an integer register the printer must not read as
        // a number.
        if (isBoolType(par.typ)) try ctx.bool_slots.put(alloc, param_slot_cursor, {});
        // A `ptr` parameter carries the base address of a caller's positional
        // table, so `p[i]` in the body is a scaled load off that register.
        if (typeIsPtr(par.typ)) try ctx.ptr_slots.put(alloc, param_slot_cursor, {});
        if (ctx.param_record_types.get(par.name) != null) {
            try ctx.ptr_slots.put(alloc, param_slot_cursor, {});
        }
        // A parameter's declared width is a declared width like any other. Only
        // `i32` can reach here — `functionEligible` refuses `u8`/`u16`/`u32`
        // parameters outright — but the body's arithmetic must still see it as
        // a 32-bit binding rather than as an i64.
        if (narrowIntOfType(par.typ)) |width| {
            try ctx.narrow_slots.put(alloc, param_slot_cursor, width);
        }
        param_slot_cursor += 1;
    }
    // Locals and temps share one id space (`freshTemp` allocates both), but the
    // parameter slots above were assigned by index rather than through it. Without
    // advancing the cursor the first temps alias the parameters, and the backend's
    // single slot->register map silently rebinds a parameter to a temp's register.
    ctx.next_temp = param_slot_cursor;

    // §12 TAIL, armed only for a flat scalar frame. `param_slot_cursor` counts
    // the slots actually assigned above, so this equality IS the test for "one
    // slot per parameter" — a record parameter exploded into several and the
    // cursor runs ahead of the parameter list.
    // The flat scalar frame is "one slot per declared operand plus the implicit
    // projection level, if any" — a record parameter exploded into several fields
    // runs the cursor ahead of that and disqualifies the frame.
    if (param_slot_cursor == fd.func.params.len + edge_level_slots) {
        const slots = try alloc.alloc(u32, param_slot_cursor);
        for (0..param_slot_cursor) |i| slots[i] = @intCast(i);
        ctx.self_param_slots = slots;
        // Bare-name self-tail-recursion applies only to a single-path relation;
        // a method or projection-variant body reaches its own entity through a
        // mangled/qualified name, never a bare identifier, so leaving self_name
        // unset for those keeps isSelfTailCall() unchanged while operand-ABI
        // recognition (self_param_slots) still covers every declared operand.
        if (fd.path.len == 1 and edge_level_slots == 0) ctx.self_name = fd.path[0];
    }

    // LAWFUL NONEXECUTION. A relation that takes no operands and whose body the
    // compile-time evaluator can run to an integer does not need a body at
    // runtime — the value IS the answer, so emit it and lower nothing.
    //
    // This is the elimination frontier's first instance: the evaluator already
    // executes `while` and `for` (evalWhile / evalNumFor), so a bounded loop
    // folds here even though the backend has no loop-folding pass of its own.
    // Measured before this: `while i <= 100 : s += i` emitted 15 instructions
    // and a real branch.
    //
    // Fails CLOSED: any evaluator error — an unsupported construct, a world
    // effect, the step limit — falls through to ordinary lowering. Nothing is
    // assumed foldable; it is folded only when it actually evaluated.
    // THE MODULE'S INITIALIZERS ARE NOT AN ENTRY'S JOB, AND THEY USED TO BE.
    //
    // This is where a store of every module-global initializer was emitted,
    // guarded on `fd.path[0] == "main"`. A LIBRARY OBJECT HAS NO `main`, so the
    // store existed nowhere and `global G: i64 = 7` started at 0 — `ok compile`,
    // exit 0, no diagnostic, and a C driver calling `bump(); bump(); peek()`
    // read `1 2 2` where the answer is `8 9 9`. Measured at 3260b1e5, `--emit
    // obj` and `--emit dylib` alike.
    //
    // An initializer that is a compile-time constant is a PROPERTY OF THE
    // STORAGE, not an instruction anybody runs: it belongs in the image the
    // loader maps, which is what `dnir.Module.globals` now carries and what
    // `__DATA,__data` realizes. `HPLS.md` §31 — absence is a representation —
    // and §76-77, where startup and loader work are first-class costs: the
    // right number of instructions for a load-time constant is zero, in EVERY
    // artifact kind, which is also the only way exe and obj can agree by
    // construction rather than by a guard naming one function.
    //
    // An initializer that does NOT fold is refused in `lowerModuleFromGraph`,
    // so nothing reaches here needing a store.

    try lowerBlock(&ctx, &fd.func.body, true);

    // LAWFUL NONEXECUTION. A relation taking no operands whose body the
    // compile-time evaluator runs to an integer does not need that body at
    // runtime — the value IS the answer. The evaluator already executes `while`
    // and `for`, so a bounded loop folds here although the backend has no
    // loop-folding pass of its own. Measured before: `while i <= 100 : s += i`
    // emitted 15 instructions and a real branch; now 2 and none.
    //
    // THE BODY IS LOWERED FIRST AND ONLY THEN DISCARDED. Skipping `lowerBlock`
    // also skips the graph bookkeeping it performs, and an application that was
    // never lowered is never resolved: a body reading `os.args` folded to a
    // constant while leaving an unresolved application behind, and a call that
    // could NOT resolve would have been hidden rather than diagnosed. Lowering
    // first keeps every check; only the emitted instructions are replaced.
    //
    // Fails CLOSED: any evaluator error — an unsupported construct, an unbound
    // name like `os.args`, the step limit — leaves the lowered body in place.
    //
    // APPLICATIONS ARE ADMITTED NOW, and the predicate that decides it lives
    // ONCE, in `comptime.zig`. `foldRelationBody` keeps the old behaviour
    // VERBATIM for a body that applies nothing — same two guards, same budget,
    // same evaluator, empty bindings — so routing it in here cannot move a case
    // that folded before; the new capability is confined to the branch where the
    // body does apply something, and that branch is gated on
    // `ApplicationFact.effect` through `graph_query.effectFreeCalleeClosure`.
    var folded = false;
    if (fd.func.params.len == 0 and !fd.func.vararg and fd.func.vararg_name == null) {
        if (comptime_eval.foldRelationBody(alloc, graph, id, &fd.func)) |k| {
            ctx.instrs.clearRetainingCapacity();
            try ctx.emit(.{ .op = .ret, .lhs = .{ .i64 = k } });
            // THE APPLICATIONS INSIDE THIS BODY ARE NOW REALIZED NOWHERE, and
            // that has to be SAID. `native_backend` requires every published
            // application to be realized exactly once; a folded relation
            // realizes none of its own, and without this fact the count check
            // reads the difference as a dropped call (DNB011). Published on the
            // function rather than back onto the graph — see
            // `native_ir.Function.folded_to_constant`.
            folded = true;
        }
    }

    // A void body has no tail result to return from, so nothing emitted `ret`
    // and the backend's "did this function return?" check failed the module.
    // The value is never read by any caller; it exists so the epilogue runs.
    if (isVoidType(fd.func.ret_type)) {
        const ends_in_ret = ctx.instrs.items.len > 0 and
            ctx.instrs.items[ctx.instrs.items.len - 1].op == .ret;
        if (!ends_in_ret) try ctx.emit(.{ .op = .ret, .lhs = .{ .i64 = 0 }, .ty = .any });
    }

    var params: std.ArrayList(dnir.Param) = .empty;
    defer params.deinit(alloc);
    errdefer for (params.items) |param| deinitParam(alloc, param);
    if (fd.path.len == 1) {
        if (relationEdgeLevel(fd.path[0])) |level| {
            if (blockMentionsIdent(&fd.func.body, level)) {
                const param_name = try alloc.dupe(u8, level);
                params.append(alloc, .{
                    .name = param_name,
                    .ty = .str,
                    .record = null,
                }) catch |err| {
                    alloc.free(param_name);
                    return err;
                };
            }
        }
    }
    for (fd.func.params) |par| {
        const rec_name = if (findRecordName(records, par.typ)) |r| try alloc.dupe(u8, r.name) else null;
        const param_name = alloc.dupe(u8, par.name) catch |err| {
            if (rec_name) |record| alloc.free(record);
            return err;
        };
        params.append(alloc, .{
            .name = param_name,
            .ty = resolveType(par.typ),
            .record = rec_name,
        }) catch |err| {
            alloc.free(param_name);
            if (rec_name) |record| alloc.free(record);
            return err;
        };
    }

    const owned_params = try params.toOwnedSlice(alloc);
    errdefer {
        for (owned_params) |param| deinitParam(alloc, param);
        alloc.free(owned_params);
    }
    const owned_instrs = try ctx.instrs.toOwnedSlice(alloc);
    var strings_interned = false;
    errdefer {
        if (strings_interned) {
            for (owned_instrs) |instruction| dnir.deinitInstr(alloc, instruction);
        } else {
            for (owned_instrs) |instruction| {
                if (instruction.vals.len > 0) alloc.free(instruction.vals);
                if (instruction.pack_results.len > 0) alloc.free(instruction.pack_results);
            }
        }
        alloc.free(owned_instrs);
    }
    try internInstrStrings(alloc, owned_instrs);
    strings_interned = true;

    const blocks = try alloc.alloc(dnir.Block, 1);
    errdefer alloc.free(blocks);
    blocks[0] = .{ .instrs = owned_instrs };

    const ret_rec = findRecordName(records, fd.func.ret_type);
    const ret_record_name = if (ret_rec) |r| try alloc.dupe(u8, r.name) else null;
    errdefer if (ret_record_name) |record| alloc.free(record);
    const export_name = try funcExportName(alloc, graph.selfHome(), fd);
    errdefer alloc.free(export_name);
    return .{
        .name = export_name,
        .ret = resolveType(fd.func.ret_type),
        .ret_pack = ret_pack,
        .params = owned_params,
        .ret_record = ret_record_name,
        // The SAME declaration that already exempted this relation from home
        // mangling two lines up (`funcExportName` consults `foreignBoundaryName`)
        // also decides its result convention. Reading it once, here, is what
        // makes "the name is C's" and "the ABI is C's" impossible to hold apart.
        .foreign_boundary = foreignBoundaryName(fd) != null,
        .is_float_kernel = blk: {
            const slots = f64AbiParamSlots(fd, records) orelse break :blk false;
            break :blk slots > 0 and slots <= 8;
        },
        .id = id,
        .folded_to_constant = folded,
        .blocks = blocks,
    };
}

/// Physical process entry from the file-scope tail. The DNIR name `main` is
/// the linker ABI, not a source binding.
fn root(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    id: ?semantic_graph.id,
    records: []const dnir.RecordDesc,
    graph: *const semantic_graph.SemanticGraph,
    occurrences: *const OccurrenceBridge,
    diagnostic: *Diagnostic,
    require_graph_facts: bool,
    externs: *std.ArrayList(dnir.Extern),
    func_record_returns: *std.StringHashMapUnmanaged([]const u8),
    fp_params: *const std.StringHashMapUnmanaged([]bool),
    module_consts: *const ModuleConsts,
    module_globals: *const ModuleGlobals,
    entity_linkage: *const std.AutoHashMapUnmanaged(semantic_graph.id, []const u8),
    relation_edges: *const std.StringHashMapUnmanaged([]const u8),
) Error!dnir.Function {
    var ctx: LowerCtx = .{
        .alloc = alloc,
        .diagnostic = diagnostic,
        .records = records,
        .graph = graph,
        .function = id,
        .occurrences = occurrences,
        .require_graph_facts = require_graph_facts,
        .externs = externs,
        .func_record_returns = func_record_returns,
        .fp_params = fp_params,
        .entity_linkage = entity_linkage,
        .relation_edges = relation_edges,
        .module_consts = module_consts,
        .module_globals = module_globals,
        .ret_record = null,
    };
    defer ctx.deinit();
    for (mod.body.stmts) |*stmt| switch (stmt.*) {
        .func_decl,
        .const_decl,
        .global_decl,
        .alias_def,
        .enum_def,
        .macro_def,
        .concept_def,
        .cinclude,
        .directive,
        => {},
        else => try lowerStmt(&ctx, stmt, false),
    };
    if (tail_result_demand.blockTailResult(&mod.body)) |tail| {
        if (status(&ctx, tail.expr)) {
            _ = try tryEmitTailDemandReturn(&ctx, &mod.body);
        } else if (tailAnchoredAway(&mod.body, tail)) {
            // The resolved value anchored to an earlier statement that has
            // ALREADY been lowered by the loop above, so re-lowering it here
            // buys nothing and re-evaluates it; the file's tail expression is
            // the only thing still owed an emission. See `tailAnchoredAway`.
            try lowerBlockTailEffect(&ctx, &mod.body);
        } else {
            _ = try lowerExprCons(&ctx, tail.expr, .discard);
        }
    }
    if (ctx.instrs.items.len == 0 or ctx.instrs.items[ctx.instrs.items.len - 1].op != .ret) {
        try ctx.emit(.{ .op = .ret, .lhs = .{ .i64 = 0 }, .ty = .any });
    }
    const owned_instrs = try ctx.instrs.toOwnedSlice(alloc);
    var strings_interned = false;
    errdefer {
        if (strings_interned) {
            for (owned_instrs) |instruction| dnir.deinitInstr(alloc, instruction);
        } else {
            for (owned_instrs) |instruction| {
                if (instruction.vals.len > 0) alloc.free(instruction.vals);
                if (instruction.pack_results.len > 0) alloc.free(instruction.pack_results);
            }
        }
        alloc.free(owned_instrs);
    }
    try internInstrStrings(alloc, owned_instrs);
    strings_interned = true;
    const blocks = try alloc.alloc(dnir.Block, 1);
    errdefer alloc.free(blocks);
    blocks[0] = .{ .instrs = owned_instrs };
    const export_name = try alloc.dupe(u8, "main");
    errdefer alloc.free(export_name);
    return .{
        .name = export_name,
        .ret = .i64,
        .params = &.{},
        .ret_record = null,
        .id = id,
        .blocks = blocks,
    };
}

fn resolveType(t: ast.TypeExpr) RT {
    return switch (t) {
        .named => |n| blk: {
            if (std.mem.eql(u8, n, "i64")) break :blk .i64;
            if (isIntAlias(n)) break :blk .i64;
            if (std.mem.eql(u8, n, "i32")) break :blk .i32;
            if (std.mem.eql(u8, n, "str")) break :blk .str;
            if (std.mem.eql(u8, n, "bool")) break :blk .bool;
            if (std.mem.eql(u8, n, "f64")) break :blk .f64;
            if (std.mem.eql(u8, n, "ptr") or std.mem.eql(u8, n, "void*")) break :blk physical_pointer;
            break :blk .any;
        },
        .inferred => .any,
        .pointer => physical_pointer,
        else => .any,
    };
}

/// `int` and `integer` ARE `i64`, and this is not a courtesy: `types.zig`
/// resolves both to `.i64` under "Common aliases", so they are the same type by
/// the language's own answer. This pass matched the two spellings `i64` and
/// `i32` literally, so `exit(code: int)` in `lib/os.id` was ineligible —
/// and because `lowerModule` requires EVERY function in a module to lower, one
/// spliced `os.exit` refused the whole program. Two spellings of one type, and
/// the narrower reading cost every program that touches `std.os`.
///
/// Only the exact aliases. `i8`, `u32` and friends resolve to their own widths
/// and would need truncation this pass does not emit, so they stay out.
fn isIntAlias(n: []const u8) bool {
    return std.mem.eql(u8, n, "int") or std.mem.eql(u8, n, "integer");
}

// ---------------------------------------------------------------------------
// DECLARED INTEGER WIDTH
//
// `resolveType` above answers `.any` for `u8`/`u16`/`u32` and `.i32` for `i32`,
// and until this section existed NOTHING downstream ever read a width: every
// value lived at 64 bits from the literal to the exit status. So
//
//     h: u32 = 4294967295
//     h = h + 5
//
// answered 4294967300 under the DEFAULT backend and 4 under `--backend=c`,
// which emits a real `uint32_t` and a real `((uint32_t)(...))` cast. The same
// silence produced 79 instead of 118 from `tools/wasm/bench/hash.id`, a
// 200M-iteration FNV hash whose true answer (1899277430, low byte 118) is
// recorded in its own header and was recomputed independently.
//
// THE WIDTH IS KNOWN HERE AND ONLY HERE. Sema types the binding, but the DNIR
// instruction stream had no field carrying it to the arithmetic — `Instr.ty`
// existed and was written `.any` for every integer op. These helpers put the
// declared width INTO `Instr.ty`, and `native_backend.emitNarrowFit` reads it
// back out. Nothing is reconstructed from context.
// ---------------------------------------------------------------------------

/// THE PROJECTION MOVED TO `types.zig`, BESIDE THE DESCRIPTOR IT BELONGS TO.
///
/// It had to. `comptime.zig`'s folder must apply the SAME projection this file
/// hands to the store, and `dnir_lower` already imports `comptime.zig`, so the
/// folder could not import this one. It answered in the full 64-bit ring
/// instead and `t: i32` folded to a value no store could ever hold.
///
/// These are ALIASES, not copies — `native_backend` already reaches the
/// projection this way (`const narrowFit = dnir_lower.narrowFit;`) and keeps
/// doing so unchanged.
pub const NarrowFit = types.NarrowFit;

pub fn narrowFit(ty: RT) ?NarrowFit {
    return ty.narrowFit();
}

/// DO THE LOW 32 BITS OF THIS OPERATION DEPEND ONLY ON THE LOW 32 BITS OF ITS
/// OPERANDS?
///
/// True for exactly `add`, `sub`, `mul`, `band`, `bor` and `bxor`: carries and
/// borrows travel upward and the bitwise three are bit-local, so the answer
/// modulo 2^32 is a function of the operands modulo 2^32. That is the ONLY
/// property a 32-bit destination form needs — no known-bits lattice, no
/// canonical operands, no range fact.
///
/// FALSE FOR EVERYTHING ELSE, and the exclusions are the load-bearing part:
/// `shl`/`shr` are ranked `.int64` by `exprCRank` because the operand is
/// WIDENED before the shift, and the two forms mask the amount to a different
/// number of bits besides; `div`/`idiv`/`mod` are realized with SIGNED
/// division, which reads bit 31 as a sign in the narrow form; comparisons carry
/// no width at all.
///
/// Shared with `native_backend`, which selects the realization from it, so the
/// rule that admits the transform and the rule that emits it are one function.
pub fn lowThirtyTwoExact(op: dnir.BinOpTag) bool {
    return switch (op) {
        .add, .sub, .mul, .band, .bor, .bxor => true,
        else => false,
    };
}

/// The compile-time half of `native_backend.emitNarrowFit`: the value the refit
/// instruction would produce, for a literal that never reaches a register.
///
/// The two MUST agree bit for bit. A folded constant that skipped the
/// truncation the register path performs is a decision computed against one
/// state and read against another — the shape behind every silent wrong answer
/// in this tree. `native_backend` calls THIS function rather than carrying its
/// own copy.
pub const narrowFitConst = types.narrowFitConst;

/// The declared narrow width of a type expression, or null for everything else.
///
/// `i32` is included even though `resolveType` already answers `.i32`: nothing
/// downstream had ever acted on that answer, so `h: i32 = 2147483647; h = h + 1`
/// printed 2147483648 where C printed -2147483648.
const narrowIntOfType = types.narrowIntOfType;

/// C's integer-promotion rank for an operand, as `--backend=c` computes it —
/// because that backend emits real C and real C types, so its arithmetic IS
/// C's usual arithmetic conversions and the differential is decided by them.
///
/// Measured, not assumed. `uint8_t e = 250` then `print(e + 10)` prints **260**
/// under `--backend=c`: `u8` and `u16` promote to `int`, so the addition is not
/// narrow at all and must not be truncated. `uint32_t a` then `print(a + 5)`
/// prints **4**: `u32` promotes to `unsigned int`, which is where the wrap
/// lives. `int32_t b` then `print(b + 1)` prints 2147483648 — signed overflow
/// is undefined in C and the emitted program does not wrap it, so neither does
/// this. `.int32` therefore means "promoted to a 32-bit type whose overflow is
/// not defined", and only `.uint32` earns a refit.
const CRank = enum { int32, uint32, int64 };

fn crankOfNarrow(ty: RT) CRank {
    return switch (ty) {
        .u32 => .uint32,
        // `u8`, `u16`, `i8`, `i16`, `i32` all promote to `int`.
        .u8, .u16, .i8, .i16, .i32 => .int32,
        else => .int64,
    };
}

/// C's usual arithmetic conversions over two promoted operands.
fn crankJoin(a: CRank, b: CRank) CRank {
    if (a == .int64 or b == .int64) return .int64;
    if (a == .uint32 or b == .uint32) return .uint32;
    return .int32;
}

fn isIntType(t: ast.TypeExpr) bool {
    return t == .named and (std.mem.eql(u8, t.named, "i64") or
        std.mem.eql(u8, t.named, "i32") or std.mem.eql(u8, t.named, "u64") or
        isIntAlias(t.named));
}

/// `bool` rides an integer register like any other scalar.
///
/// It was absent from the eligibility predicate entirely, so one `bool`
/// parameter refused the WHOLE module (lowerModule requires every function to
/// lower) — `branch_sum(cond: bool): i64` reported DNB002 while the identical
/// function taking `i64` lowered. Nothing downstream needed teaching: `true`
/// and `false` already lower to `.i64` 1 and 0, `resolveType` already maps the
/// name to `RT.bool`, and the backend routes every non-`.f64` parameter through
/// x0..x7. Only the gate was missing.
///
/// Kept SEPARATE from `isIntType` rather than folded into it: `isIntType` also
/// answers "may this be a record field kind" and "may this be a numeric-for
/// index", and a boolean loop counter is not a thing this admits by accident.
fn isBoolType(t: ast.TypeExpr) bool {
    return t == .named and std.mem.eql(u8, t.named, "bool");
}

fn isStrType(t: ast.TypeExpr) bool {
    return t == .named and std.mem.eql(u8, t.named, "str");
}

/// `: void` — a function that exists for its effects.
///
/// Rejecting these made a whole MODULE ineligible, not just the function:
/// lowerModule requires every function to lower, so one `render(): void`
/// alongside natively-lowerable helpers bailed the lot (mandelbrot, test_sql).
fn isVoidType(t: ast.TypeExpr) bool {
    return t == .named and std.mem.eql(u8, t.named, "void");
}

/// True when the file-scope tail *is* the process status (integer, bool, or
/// f64 that the ABI widens). A str or other value is produced for its effects
/// and must not leak a register as `_main`'s i64.
fn status(ctx: *LowerCtx, expr: *const ast.Expr) bool {
    if (effect(expr)) return false;
    if (exprIsStr(ctx, expr)) return false;
    return exprIsIntegral(ctx, expr) or exprIsBoolish(ctx, expr) or exprIsF64(ctx, expr);
}

/// A tail call that yields nothing — its value is not a result, it is an effect.
///
/// DEMAND (rule 3) makes the last expression of a block its result, which is
/// right for every expression that HAS one. `print` and `stdout:write` do not:
/// they are egress. An if-body ending in `print(" ")` or a file whose tail is
/// `stdout:write("hi")` is a discarded statement in tail position. Returning
/// the `puts` register made write-only roots exit 61.
///
/// Syntactic rather than type-directed because `LowerCtx` carries no type map.
/// A general rule wants the callee's declared return type.
fn effect(expr: *const ast.Expr) bool {
    switch (expr.*) {
        .call => |c| {
            const callee = c.func;
            return callee.* == .name and std.mem.eql(u8, callee.name.ident, "print");
        },
        .method_call => |mc| {
            if (mc.obj.* != .name or mc.args.len != 1) return false;
            return std.mem.eql(u8, mc.obj.name.ident, "stdout") and
                std.mem.eql(u8, mc.method, "write");
        },
        else => return false,
    }
}

/// §12 TAIL — a self-call in tail position is a JUMP, not a frame.
///
/// `tail = (n, acc) … tail(n - 1, acc + 1)` at ten million deep is the
/// fixture; the direct backend pushed ten million frames and took SIGSEGV
/// where the C backend answered 10000000, because clang does the sibling call
/// and this pass did not. The rewrite is the standard one: evaluate the
/// arguments, write them over the parameter slots, branch to instruction 0.
///
/// Every argument lands in a FRESH TEMP before any slot is written. Writing
/// them in place would make `tail(acc, n)` — a swap — read the parameter it had
/// already overwritten, which is a wrong answer rather than a crash.
///
/// Declined, not guessed, whenever the frame is not a flat row of scalar slots:
/// a record parameter occupies several slots, an f64 parameter arrives in the
/// FP file, and a record return leaves through x8. Each of those needs its own
/// reassignment and none of them is this rewrite.
fn tryEmitSelfTail(ctx: *LowerCtx, expr: *const ast.Expr) Error!bool {
    if (ctx.self_name.len == 0) return false;
    if (expr.* != .call) return false;
    // A checked application cannot become a branch until the semantic graph
    // supplies a transform id and witness. Let ordinary checked-call
    // lowering retain the application instead of authorizing a rewrite from
    // the callee spelling.
    if (ctx.occurrences.get(expr) != null) return false;
    if (ctx.require_graph_facts and !ctx.graph.bootstrapApplicationExpr(expr))
        return refuseMissingApplication(ctx, @src(), expr);
    const c = expr.call;
    if (c.func.* != .name) return false;
    if (!std.mem.eql(u8, c.func.name.ident, ctx.self_name)) return false;
    if (c.args.len != ctx.self_param_slots.len) return false;
    if (ctx.ret_record != null) return false;
    if (ctx.self_fp_params) return false;
    for (c.args) |a| {
        if (exprTouchesF64(ctx, a)) return false;
    }

    var staged: [8]u32 = undefined;
    if (c.args.len > staged.len) return false;
    for (c.args, 0..) |a, i| {
        const v = try lowerExprCons(ctx, a, .single);
        staged[i] = ctx.freshTemp();
        try ctx.emit(.{ .op = .store_local, .result = staged[i], .lhs = v, .ty = .any });
    }
    for (ctx.self_param_slots, 0..) |slot, i| {
        try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = .{ .local = staged[i] }, .ty = .any });
    }
    try ctx.emit(.{ .op = .br, .branch_target = 0 });
    return true;
}

fn tryEmitTailDemandReturn(ctx: *LowerCtx, block: *const ast.Block) Error!bool {
    const r = tail_result_demand.blockTailResult(block) orelse return false;
    // The tail expression still runs even when the block's VALUE came from an
    // earlier statement. See `tailAnchoredAway`.
    if (tailAnchoredAway(block, r)) try lowerBlockTailEffect(ctx, block);
    // gap[033]: emitting `ret` here made `if c print(" ") end` compile to
    // `return print(" ")`, returning whatever register the void call left —
    // exit 59, and 224 with an else, where the C backend exits 0. Lower it as
    // the effect it is and report "no return", so the branch falls through.
    if (effect(r.expr)) {
        _ = try lowerExprCons(ctx, r.expr, .discard);
        return false;
    }
    const ret_ty: RT = if (exprIsF64(ctx, r.expr))
        .f64
    else if (exprIsPointer(ctx, r.expr))
        physical_pointer
    else
        .any;
    if (ctx.ret_record != null and (r.expr.* == .table or isRecordLocalName(ctx, r.expr))) {
        try lowerRecordReturn(ctx, r.expr);
        return true;
    }
    // A trailing compound assignment has ALREADY been lowered as a statement,
    // so its storage holds the answer. Lowering `r.expr` here would evaluate
    // `x * 2` a second time against the updated `x` — `twice(5)` returned 20
    // where the C backend returned 10, and `v.x += amt` returned 5+3+3 for
    // 5+3. Return the slot, not the expression.
    if (r.rule == .tail_compound_assignment) {
        if (r.target) |target| {
            if (compoundTargetSlot(ctx, target)) |slot| {
                try ctx.emit(.{ .op = .ret, .lhs = .{ .local = slot }, .ty = ret_ty });
                return true;
            }
            // A MODULE GLOBAL IS STORAGE THIS PASS CAN NAME — it just is not a
            // LOCAL SLOT. `compoundTargetSlot` asks `ctx.locals` and nothing
            // else, so `A = A .. line` and `N = N + 1` as a function's tail
            // both fell to the refusal below even though the assignment above
            // had already emitted a `store_global` for exactly that name. The
            // invariant the comment demands is satisfied by reading the
            // storage back, not by re-evaluating: `load_global` after
            // `store_global` is the value that was stored, once.
            if (target.* == .name) {
                if (ctx.locals.get(target.name.ident) == null) {
                    if (ctx.module_globals.types.get(target.name.ident)) |gty| {
                        const t = ctx.freshTemp();
                        try ctx.emit(.{
                            .op = .load_global,
                            .result = t,
                            .field = target.name.ident,
                            .ty = gty,
                        });
                        if (gty == .str) try ctx.str_slots.put(ctx.alloc, t, {});
                        try ctx.emit(.{
                            .op = .ret,
                            .lhs = .{ .temp = t },
                            .ty = if (gty == .f64) .f64 else ret_ty,
                        });
                        return true;
                    }
                }
            }
            if (try tryEmitTailAssignStorageReturn(ctx, target, ret_ty)) return true;
        }
        // No storage this pass can name. Re-evaluating would be a miscompile,
        // so the function is declined rather than mis-lowered.
        return bail(ctx.diagnostic, @src());
    }
    if (ctx.occurrences.get(r.expr)) |occ| {
        if (applicationRealizationEmitted(ctx, occ.application)) {
            if (try tryEmitTailAssignStorageReturnForApplication(ctx, block, occ.application, ret_ty))
                return true;
            if (r.rule == .tail_call and block.stmts.len > 0) {
                const last = &block.stmts[block.stmts.len - 1];
                if (last.* == .assign) {
                    const as = last.assign;
                    if (as.values.len == 1 and as.values[0] == r.expr) return false;
                }
            }
        }
    }
    if (try tryEmitSelfTail(ctx, r.expr)) return true;
    try ctx.emit(.{ .op = .ret, .lhs = try lowerExpr(ctx, r.expr), .ty = ret_ty });
    return true;
}

fn applicationRealizationEmitted(ctx: *const LowerCtx, application: semantic_graph.id) bool {
    for (ctx.instrs.items) |instr| {
        if (instr.op != .call_direct) continue;
        const app = instr.application orelse continue;
        if (std.meta.eql(app, application)) return true;
    }
    return false;
}

fn tryEmitTailAssignStorageReturn(
    ctx: *LowerCtx,
    target: *const ast.Expr,
    retTy: RT,
) Error!bool {
    switch (target.*) {
        .name => |n| {
            if (ctx.locals.get(n.ident)) |slot| {
                try ctx.emit(.{ .op = .ret, .lhs = .{ .local = slot }, .ty = retTy });
                return true;
            }
            if (ctx.module_globals.types.get(n.ident)) |gty| {
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .load_global, .result = t, .field = n.ident, .ty = gty });
                try ctx.emit(.{ .op = .ret, .lhs = .{ .temp = t }, .ty = if (gty == .f64) .f64 else retTy });
                return true;
            }
        },
        .field => |f| {
            if (compoundTargetSlot(ctx, target)) |slot| {
                try ctx.emit(.{ .op = .ret, .lhs = .{ .local = slot }, .ty = retTy });
                return true;
            }
            if (f.obj.* == .name) {
                var buf: [512]u8 = undefined;
                const path = std.fmt.bufPrint(&buf, "{s}.{s}", .{ f.obj.name.ident, f.field }) catch return false;
                if (try loadFieldFromOpaquePath(ctx, path, null)) |v| {
                    try ctx.emit(.{ .op = .ret, .lhs = v, .ty = retTy });
                    return true;
                }
            }
        },
        else => {},
    }
    return false;
}

fn tryEmitTailAssignStorageReturnForApplication(
    ctx: *LowerCtx,
    block: *const ast.Block,
    application: semantic_graph.id,
    retTy: RT,
) Error!bool {
    if (block.stmts.len == 0) return false;
    const last = &block.stmts[block.stmts.len - 1];
    if (last.* != .assign) return false;
    const as = last.assign;
    if (as.values.len != 1 or as.targets.len != 1) return false;
    const val = as.values[0];
    const occ = ctx.occurrences.get(val) orelse return false;
    if (!std.meta.eql(occ.application, application)) return false;
    return try tryEmitTailAssignStorageReturn(ctx, as.targets[0], retTy);
}

/// The local slot a compound-assignment target was stored into. Field targets
/// live under the `obj.field` key `lowerFieldAssignTarget` writes.
fn compoundTargetSlot(ctx: *LowerCtx, target: *const ast.Expr) ?u32 {
    switch (target.*) {
        .name => |n| return ctx.locals.get(n.ident),
        .field => |f| {
            if (f.obj.* != .name) return null;
            var buf: [512]u8 = undefined;
            const fk = std.fmt.bufPrint(&buf, "{s}.{s}", .{ f.obj.name.ident, f.field }) catch return null;
            return ctx.locals.get(fk);
        },
        else => return null,
    }
}

fn lowerBlock(ctx: *LowerCtx, block: *const ast.Block, allow_return: bool) Error!void {
    const saved_answering = ctx.block_answering;
    ctx.block_answering = allow_return;
    defer ctx.block_answering = saved_answering;
    for (block.stmts, 0..) |*stmt, i| {
        try tryEmitVectorReductionPrologue(ctx, block.stmts, i);
        try lowerStmt(ctx, stmt, allow_return and stmtIsTailSlot(block, i));
    }
    if (allow_return) {
        _ = try tryEmitTailDemandReturn(ctx, block);
        return;
    }
    // gap[104], same hole as `lowerBlockReturns`: without this the tail
    // expression of a non-answering block is lowered by nobody.
    try lowerBlockTailEffect(ctx, block);
}

/// `req "path"` — a compile-time module binding, not a runtime call.
fn isReqCall(expr: *const ast.Expr) bool {
    if (expr.* != .call) return false;
    const c = expr.call;
    if (c.func.* != .name or !std.mem.eql(u8, c.func.name.ident, "req")) return false;
    return c.args.len == 1 and c.args[0].* == .quoted;
}

fn opaqueRecordParam(ctx: *const LowerCtx, obj_name: []const u8) ?OpaqueRecordParam {
    const rec_name = ctx.param_record_types.get(obj_name) orelse return null;
    const slot = ctx.locals.get(obj_name) orelse return null;
    if (!ctx.ptr_slots.contains(slot)) return null;
    return .{ .slot = slot, .rec_name = rec_name };
}

fn lowerFieldAssignTarget(ctx: *LowerCtx, obj: *const ast.Expr, field_name: []const u8, value: *const ast.Expr) Error!void {
    if (obj.* != .name) return bail(ctx.diagnostic, @src());
    const dest_name = obj.name.ident;
    const dest_opaque = opaqueRecordParam(ctx, dest_name);
    if (value.* == .field and value.field.obj.* == .name and
        std.mem.eql(u8, value.field.field, field_name))
    {
        const src_name = value.field.obj.name.ident;
        const src_opaque = opaqueRecordParam(ctx, src_name);
        if (dest_opaque == null and src_opaque == null and nestedRecordPrefixHasLocals(ctx, src_name)) {
            const src_key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ src_name, field_name });
            defer ctx.alloc.free(src_key);
            const dest_key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ dest_name, field_name });
            defer ctx.alloc.free(dest_key);
            try copyPrefixedLocalsFromRecordRef(ctx, dest_key, src_key);
            subsumeProducerRefit(ctx);
            return;
        }
        if (dest_opaque != null or src_opaque != null) {
            const rec = blk: {
                if (dest_opaque) |d| {
                    if (recordDescForOpaqueParam(ctx, d)) |r| break :blk r;
                }
                if (src_opaque) |s| {
                    if (recordDescForOpaqueParam(ctx, s)) |r| break :blk r;
                }
                if (recordDescForParamName(ctx, dest_name)) |r| break :blk r;
                if (recordDescForParamName(ctx, src_name)) |r| break :blk r;
                break :blk null;
            } orelse return bail(ctx.diagnostic, @src());
            if (recordFieldHasNestedFields(rec, field_name)) {
                if (dest_opaque) |dest_o| {
                    if (src_opaque) |src_o| {
                        try copyOpaqueRecordNestedFields(ctx, dest_o, .{ .opaque_param = src_o }, field_name);
                    } else {
                        try copyOpaqueRecordNestedFields(ctx, dest_o, .{ .local_base = src_name }, field_name);
                    }
                } else {
                    const dest_prefix = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ dest_name, field_name });
                    defer ctx.alloc.free(dest_prefix);
                    const src_o = src_opaque orelse return bail(ctx.diagnostic, @src());
                    try copyOpaqueToFlatPrefixedFields(ctx, dest_prefix, src_o, field_name);
                }
                return;
            }
            if (dest_opaque) |dest_o| {
                const v = if (src_opaque) |src_o|
                    try loadOpaqueParamScalarField(ctx, src_name, src_o, field_name)
                else
                    try lowerExprCons(ctx, value, .single);
                const store_ty: RT = switch (recordFieldKindForParam(ctx, dest_name, field_name) orelse .i64) {
                    .f64 => .f64,
                    .str => .str,
                    .i64 => .any,
                };
                try storeOpaqueParamScalarField(ctx, dest_o, field_name, v, store_ty);
                return;
            }
        }
    }
    if (dest_opaque) |dest_o| {
        const dest_rec = recordDescForOpaqueParam(ctx, dest_o) orelse
            return bail(ctx.diagnostic, @src());
        if (recordFieldHasNestedFields(dest_rec, field_name)) {
            if (value.* == .field and value.field.obj.* == .name and
                std.mem.eql(u8, value.field.field, field_name))
            {
                const src_name = value.field.obj.name.ident;
                if (opaqueRecordParam(ctx, src_name)) |src_opaque| {
                    try copyOpaqueRecordNestedFields(ctx, dest_o, .{ .opaque_param = src_opaque }, field_name);
                } else {
                    try copyOpaqueRecordNestedFields(ctx, dest_o, .{ .local_base = src_name }, field_name);
                }
                return;
            }
            if (value.* == .name) {
                var suffix_buf: [512]u8 = undefined;
                const suffix = std.fmt.bufPrint(&suffix_buf, ".{s}", .{field_name}) catch return bail(ctx.diagnostic, @src());
                if (std.mem.endsWith(u8, value.name.ident, suffix)) {
                    const base = value.name.ident[0 .. value.name.ident.len - suffix.len];
                    try copyOpaqueRecordNestedFields(ctx, dest_o, .{ .local_base = base }, field_name);
                    return;
                }
            }
            const tmp_base = try std.fmt.allocPrint(ctx.alloc, "__opq{d}", .{ctx.freshTemp()});
            defer ctx.alloc.free(tmp_base);
            if (value.* == .field and value.field.obj.* == .name) {
                const src_name = value.field.obj.name.ident;
                if (opaqueRecordParam(ctx, src_name)) |src_o| {
                    try copyOpaqueToFlatPrefixedFields(ctx, tmp_base, src_o, field_name);
                } else {
                    try copyPrefixedLocalsFromRecordRef(ctx, tmp_base, src_name);
                }
            } else {
                try lowerAssignTarget(ctx, tmp_base, value);
            }
            try copyOpaqueRecordNestedFields(ctx, dest_o, .{ .local_base = tmp_base }, field_name);
            return;
        }
        const v = try lowerExprCons(ctx, value, .single);
        const store_ty: RT = if (exprIsF64(ctx, value))
            .f64
        else blk: {
            if (recordFieldKindForParam(ctx, dest_name, field_name)) |kind| {
                break :blk switch (kind) {
                    .f64 => .f64,
                    .str => .str,
                    .i64 => .any,
                };
            }
            break :blk .any;
        };
        try storeOpaqueParamScalarField(ctx, dest_o, field_name, v, store_ty);
        return;
    }
    if (value.* == .field and value.field.obj.* == .name and
        std.mem.eql(u8, value.field.field, field_name))
    {
        const src_name = value.field.obj.name.ident;
        if (opaqueRecordParam(ctx, src_name)) |src_o| {
            const src_rec = recordDescForOpaqueParam(ctx, src_o) orelse return bail(ctx.diagnostic, @src());
            if (recordFieldHasNestedFields(src_rec, field_name)) {
                const dest_prefix = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ dest_name, field_name });
                defer ctx.alloc.free(dest_prefix);
                try copyOpaqueToFlatPrefixedFields(ctx, dest_prefix, src_o, field_name);
                return;
            }
            const v = try loadOpaqueParamScalarField(ctx, src_name, src_o, field_name);
            const fk = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ dest_name, field_name });
            defer ctx.alloc.free(fk);
            const store_ty: RT = switch (recordFieldKindForParam(ctx, src_name, field_name) orelse .i64) {
                .f64 => .f64,
                .str => .str,
                .i64 => .any,
            };
            if (ctx.locals.get(fk)) |slot| {
                try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = store_ty });
            } else {
                const slot = ctx.freshTemp();
                try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, fk), slot);
                if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, slot, {});
                if (store_ty == .str) try ctx.str_slots.put(ctx.alloc, slot, {});
                try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = store_ty });
            }
            subsumeProducerRefit(ctx);
            return;
        }
    }
    const fk = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ dest_name, field_name });
    defer ctx.alloc.free(fk);
    const v = try lowerExprCons(ctx, value, .single);
    if (ctx.locals.get(fk)) |slot| {
        // THE FIELD'S DECLARED WIDTH APPLIES AT EVERY WRITE, not only at the
        // literal that created the storage. This read is the whole repair:
        // `store_ty` was unconditionally `.any` here, so `r.f = r.f + K` on an
        // `f: i32` emitted a full 64-bit `str` and answered a value the place
        // cannot hold — at all six widths, folded and emitted alike.
        const store_ty: RT = if (exprIsF64(ctx, value))
            .f64
        else
            ctx.narrow_slots.get(slot) orelse .any;
        if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, slot, {});
        if (exprIsStr(ctx, value)) try ctx.str_slots.put(ctx.alloc, slot, {});
        try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = store_ty });
        subsumeProducerRefit(ctx);
        return;
    }
    const store_ty: RT = if (exprIsF64(ctx, value)) .f64 else .any;
    const slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, fk), slot);
    if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, slot, {});
    if (exprIsStr(ctx, value)) try ctx.str_slots.put(ctx.alloc, slot, {});
    try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = store_ty });
}

fn exprCallConsumption(expr: *const ast.Expr) types.ReturnConsumption {
    return switch (expr.*) {
        .call, .method_call => .discard,
        else => .single,
    };
}

fn exprReturnsF64(ctx: *LowerCtx, expr: *const ast.Expr) bool {
    if (applicationResultIs(ctx, expr, .f64)) return true;
    if (expr.* != .call) return false;
    // `math.sqrt(x)` and friends are libm: f64 in, f64 out. Without this the
    // binding `r: f64 = math.sqrt(x)` stores through the INTEGER path — the
    // assembly showed `fmov d1, d0` for the result and then `mov x9, x1` for
    // the store, so the f64 local was never written and the consumer read a
    // register nothing had touched.
    //
    // Third time this exact lesson: a producer the type tracker does not know
    // about breaks every consumer downstream. exprIsStr needed it for
    // string.char, then again for concat; this is the f64 twin.
    if (expr.call.func.* == .field) {
        const f = expr.call.func.field;
        if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "math") and
            expr.call.args.len == 1) return true;
    }
    if (expr.call.func.* != .name) return false;
    return functionResultIs(ctx, expr.call.func.name.ident, .f64);
}

fn storePackName(
    ctx: *LowerCtx,
    name: []const u8,
    value: dnir.Value,
    descriptor: types.ResolvedType,
) Error!void {
    if (ctx.locals.get(name)) |slot| {
        const store_ty: RT = if (descriptor == .f64)
            .f64
        else
            ctx.narrow_slots.get(slot) orelse .any;
        if (descriptor == .f64) try ctx.f64_slots.put(ctx.alloc, slot, {}) else _ = ctx.f64_slots.remove(slot);
        if (descriptor == .str) try ctx.str_slots.put(ctx.alloc, slot, {}) else _ = ctx.str_slots.remove(slot);
        if (descriptor == .bool) try ctx.bool_slots.put(ctx.alloc, slot, {}) else _ = ctx.bool_slots.remove(slot);
        if (descriptor == .pointer) try ctx.ptr_slots.put(ctx.alloc, slot, {}) else _ = ctx.ptr_slots.remove(slot);
        try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = value, .ty = store_ty });
        return;
    }
    if (ctx.module_globals.types.get(name)) |ty| {
        try ctx.emit(.{ .op = .store_global, .field = name, .lhs = value, .ty = ty });
        return;
    }
    const slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, name), slot);
    const store_ty: RT = if (descriptor == .f64) .f64 else .any;
    if (descriptor == .f64) try ctx.f64_slots.put(ctx.alloc, slot, {});
    if (descriptor == .str) try ctx.str_slots.put(ctx.alloc, slot, {});
    if (descriptor == .bool) try ctx.bool_slots.put(ctx.alloc, slot, {});
    if (descriptor == .pointer) try ctx.ptr_slots.put(ctx.alloc, slot, {});
    try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = value, .ty = store_ty });
}

fn prepareLocalPackSlots(ctx: *LowerCtx, names: []const ast.LocalName) Error!void {
    for (names) |name| {
        const width = narrowIntOfType(name.typ) orelse continue;
        const slot = ctx.locals.get(name.ident) orelse blk: {
            const fresh = ctx.freshTemp();
            const owned = try ctx.alloc.dupe(u8, name.ident);
            ctx.locals.put(ctx.alloc, owned, fresh) catch |err| {
                ctx.alloc.free(owned);
                return err;
            };
            break :blk fresh;
        };
        try ctx.narrow_slots.put(ctx.alloc, slot, width);
    }
}

fn lowerOneToManyPackDeclaration(
    ctx: *LowerCtx,
    names: []const ast.LocalName,
    initializers: []const *ast.Expr,
) Error!bool {
    if (initializers.len != 1 or names.len <= 1) return false;
    const source = initializers[0];
    const application_fact = ctx.occurrences.get(source) orelse return false;
    const adjustment = ctx.graph.packAdjustment(application_fact.application) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "declaration-pack-adjustment");
    const sources = ctx.graph.packMembers(adjustment.source_pack) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "declaration-source-pack");
    const targets = ctx.graph.packMembers(adjustment.target_pack) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "declaration-target-pack");
    if (sources.len == 0 or targets.len != names.len) return false;
    for (targets, names) |target_id, *name| {
        const node = ctx.graph.get(target_id) orelse
            return invalidGraphFacts(ctx.diagnostic, @src(), "declaration-target-member");
        const raw = node.ast_ref orelse
            return invalidGraphFacts(ctx.diagnostic, @src(), "declaration-target-provenance");
        const published: *const ast.LocalName = @ptrCast(@alignCast(raw));
        if (node.kind != .local or published != name or node.name == null or
            !std.mem.eql(u8, node.name.?, name.ident))
        {
            return invalidGraphFacts(ctx.diagnostic, @src(), "declaration-target-place");
        }
    }

    try prepareLocalPackSlots(ctx, names);
    if (sources.len == 1) {
        const source_node = ctx.graph.get(sources[0]) orelse
            return invalidGraphFacts(ctx.diagnostic, @src(), "declaration-source-member");
        const descriptor = source_node.descriptor orelse
            return invalidGraphFacts(ctx.diagnostic, @src(), "declaration-source-descriptor");
        const first = try lowerExprCons(ctx, source, .single);
        try storePackName(ctx, names[0].ident, first, descriptor);
        for (names[1..]) |name| {
            try storePackName(ctx, name.ident, .{ .i64 = 0 }, .nil);
        }
        return true;
    }

    var temps: [max_reg_record_fields]?u32 = @splat(null);
    try lowerCheckedPackCall(ctx, application_fact, @min(sources.len, names.len), &temps);
    for (names, 0..) |name, i| {
        if (i >= sources.len) {
            try storePackName(ctx, name.ident, .{ .i64 = 0 }, .nil);
            continue;
        }
        const node = ctx.graph.get(sources[i]) orelse
            return invalidGraphFacts(ctx.diagnostic, @src(), "declaration-source-member");
        const descriptor = node.descriptor orelse
            return invalidGraphFacts(ctx.diagnostic, @src(), "declaration-source-descriptor");
        const temp = temps[i] orelse
            return invalidGraphFacts(ctx.diagnostic, @src(), "declaration-pack-demand");
        try storePackName(ctx, name.ident, .{ .temp = temp }, descriptor);
    }
    return true;
}

/// Realize binding adjustment directly from graph packs. The call runs once;
/// ordered demanded members are stored, surplus source members disappear, and
/// missing target members are nil-filled. No target count or result shape is
/// reconstructed from the callee spelling.
fn lowerOneToManyPackAssign(
    ctx: *LowerCtx,
    assignment_targets: []const *ast.Expr,
    assignment_values: []const *ast.Expr,
) Error!bool {
    if (assignment_values.len != 1 or assignment_targets.len <= 1) return false;
    const source = assignment_values[0];
    const application_fact = ctx.occurrences.get(source) orelse return false;
    const adjustment = ctx.graph.packAdjustment(application_fact.application) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "binding-pack-adjustment");
    const sources = ctx.graph.packMembers(adjustment.source_pack) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "binding-source-pack");
    const targets = ctx.graph.packMembers(adjustment.target_pack) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "binding-target-pack");
    if (sources.len == 0 or targets.len != assignment_targets.len) return false;
    for (targets, assignment_targets) |target_id, target| {
        const node = ctx.graph.get(target_id) orelse
            return invalidGraphFacts(ctx.diagnostic, @src(), "binding-target-member");
        const raw = node.ast_ref orelse
            return invalidGraphFacts(ctx.diagnostic, @src(), "binding-target-provenance");
        const published: *const ast.Expr = @ptrCast(@alignCast(raw));
        if (published != target or target.* != .name) {
            return invalidGraphFacts(ctx.diagnostic, @src(), "binding-target-place");
        }
    }

    if (sources.len == 1) {
        const source_node = ctx.graph.get(sources[0]) orelse
            return invalidGraphFacts(ctx.diagnostic, @src(), "binding-source-member");
        const descriptor = source_node.descriptor orelse
            return invalidGraphFacts(ctx.diagnostic, @src(), "binding-source-descriptor");
        const first = try lowerExprCons(ctx, source, .single);
        try storePackName(ctx, assignment_targets[0].name.ident, first, descriptor);
        for (assignment_targets[1..]) |target| {
            try storePackName(ctx, target.name.ident, .{ .i64 = 0 }, .nil);
        }
        return true;
    }

    var temps: [max_reg_record_fields]?u32 = @splat(null);
    try lowerCheckedPackCall(ctx, application_fact, @min(sources.len, assignment_targets.len), &temps);
    for (assignment_targets, 0..) |target, i| {
        if (i >= sources.len) {
            try storePackName(ctx, target.name.ident, .{ .i64 = 0 }, .nil);
            continue;
        }
        const node = ctx.graph.get(sources[i]) orelse
            return invalidGraphFacts(ctx.diagnostic, @src(), "binding-source-member");
        const descriptor = node.descriptor orelse
            return invalidGraphFacts(ctx.diagnostic, @src(), "binding-source-descriptor");
        const temp = temps[i] orelse
            return invalidGraphFacts(ctx.diagnostic, @src(), "binding-pack-demand");
        try storePackName(ctx, target.name.ident, .{ .temp = temp }, descriptor);
    }
    return true;
}

fn functionResultIs(
    ctx: *const LowerCtx,
    name: []const u8,
    expected: std.meta.Tag(types.ResolvedType),
) bool {
    const start = ctx.function orelse return false;
    const entity = ctx.graph.resolveInHome(start, name, .func) orelse return false;
    const descriptor = ctx.graph.functionResultDescriptor(entity) orelse return false;
    return std.meta.activeTag(descriptor) == expected;
}

fn lowerStmt(ctx: *LowerCtx, stmt: *const ast.Stmt, allow_return: bool) Error!void {
    switch (stmt.*) {
        .local_decl => |ld| {
            if (try lowerOneToManyPackDeclaration(ctx, ld.names, ld.inits)) return;
            if (ld.names.len != ld.inits.len and ld.inits.len == 1) return bail(ctx.diagnostic, @src());
            for (ld.names, 0..) |*ln, i| {
                // The declared width has to be on record BEFORE the initializer
                // is lowered, because the initializer's store is the first place
                // it applies: `h: u8 = 300` is 44 under `--backend=c`, which
                // writes `uint8_t h = ((uint8_t)(300))`. Marking the slot after
                // `lowerAssignTarget` would have left exactly the first store
                // unrefitted — a wrong answer visible only on the declaration.
                if (narrowIntOfType(ln.typ)) |width| {
                    const slot = ctx.locals.get(ln.ident) orelse blk: {
                        const fresh = ctx.freshTemp();
                        const owned = try ctx.alloc.dupe(u8, ln.ident);
                        ctx.locals.put(ctx.alloc, owned, fresh) catch |err| {
                            ctx.alloc.free(owned);
                            return err;
                        };
                        break :blk fresh;
                    };
                    try ctx.narrow_slots.put(ctx.alloc, slot, width);
                }
                if (blk: {
                    if (findRecordName(ctx.records, ln.typ)) |rec| break :blk rec;
                    if (ln.typ == .named) {
                        if (findRecordByNominal(ctx.records, ln.typ.named, ctx.graph)) |rec| break :blk rec;
                    }
                    break :blk null;
                }) |rec| {
                    try ensureRecordLocalFieldSlots(ctx, ln.ident, rec);
                }
                if (i < ld.inits.len) {
                    if (try skipStaticAggregateBinding(ctx, ln.ident)) continue;
                    try lowerAssignTarget(ctx, ln.ident, ld.inits[i]);
                }
                if (ln.typ != .inferred and isFloatType(ln.typ)) {
                    if (ctx.locals.get(ln.ident)) |slot| try ctx.f64_slots.put(ctx.alloc, slot, {});
                }
                // `ok: bool = f()` where `f` is not declared `: bool`. The
                // ANNOTATION is the answer here and the initializer is not, so
                // the mark has to follow the declared type as well.
                if (isBoolType(ln.typ)) {
                    if (ctx.locals.get(ln.ident)) |slot| try ctx.bool_slots.put(ctx.alloc, slot, {});
                }
                if (typeIsPtr(ln.typ)) {
                    if (ctx.locals.get(ln.ident)) |slot| try ctx.ptr_slots.put(ctx.alloc, slot, {});
                }
            }
        },
        .assign => |as| {
            if (try lowerOneToManyPackAssign(ctx, as.targets, as.values)) return;
            if (as.targets.len != as.values.len) return bail(ctx.diagnostic, @src());
            for (as.targets, as.values) |target, value| {
                if (target.* == .name and try skipStaticAggregateBinding(ctx, target.name.ident)) continue;
                // The environment is a PLACE. This runs before the switch below
                // because `os.env[k]` is an `.index` whose object is a `.field`,
                // which `lowerIndexAssignTarget` rejects outright, and
                // `env(k)`/`os.env(k)` are `.call` targets, which the switch has
                // no arm for at all.
                if (envPlaceKey(ctx, target)) |key| {
                    try lowerEnvStore(ctx, key, value);
                    continue;
                }
                switch (target.*) {
                    .name => |n| try lowerAssignTarget(ctx, n.ident, value),
                    .field => |f| try lowerFieldAssignTarget(ctx, f.obj, f.field, value),
                    .index => |ix| try lowerIndexAssignTarget(ctx, ix.obj, ix.key, value),
                    else => return bail(ctx.diagnostic, @src()),
                }
            }
        },
        .if_stmt => |is| {
            if (is.binding) |b| {
                try lowerAssignTarget(ctx, b.name, b.expr);
            }
            var end_branches: std.ArrayListUnmanaged(u32) = .empty;
            defer end_branches.deinit(ctx.alloc);

            const cond = try lowerExpr(ctx, is.cond);
            var fail_idx = ctx.instrs.items.len;
            try ctx.emit(.{ .op = .br, .lhs = cond, .branch_target = 0, .branch_condition = .when_false });

            // A branch early-returns when the `if` is itself the block's tail
            // slot (`allow_return`), OR when the enclosing block is a return
            // context and the branch is a value guard — `if n < 2 \n n` exits
            // the function even though the recursive tail follows it. Trailing
            // assignments/effects still fall through (see `branchIsValueGuard`).
            const answering = ctx.block_answering;
            const then_gate = allow_return or (answering and branchIsValueGuard(&is.then));
            const then_ret = try lowerBlockReturns(ctx, &is.then, then_gate);
            if (!then_ret) {
                try end_branches.append(ctx.alloc, @intCast(ctx.instrs.items.len));
                try ctx.emit(.{ .op = .br, .branch_target = 0 });
            }

            for (is.elseifs) |elseif| {
                const next_idx: u32 = @intCast(ctx.instrs.items.len);
                ctx.instrs.items[fail_idx].branch_target = next_idx;
                const econd = try lowerExpr(ctx, elseif.cond);
                fail_idx = ctx.instrs.items.len;
                try ctx.emit(.{ .op = .br, .lhs = econd, .branch_target = 0, .branch_condition = .when_false });
                const ei_gate = allow_return or (answering and branchIsValueGuard(&elseif.body));
                const branch_ret = try lowerBlockReturns(ctx, &elseif.body, ei_gate);
                if (!branch_ret) {
                    try end_branches.append(ctx.alloc, @intCast(ctx.instrs.items.len));
                    try ctx.emit(.{ .op = .br, .branch_target = 0 });
                }
            }

            const else_start: u32 = @intCast(ctx.instrs.items.len);
            ctx.instrs.items[fail_idx].branch_target = else_start;
            if (is.else_body) |*eb| {
                const else_gate = allow_return or (answering and branchIsValueGuard(eb));
                _ = try lowerBlockReturns(ctx, eb, else_gate);
            }

            const end_idx: u32 = @intCast(ctx.instrs.items.len);
            for (end_branches.items) |*br_off| {
                ctx.instrs.items[br_off.*].branch_target = end_idx;
            }
        },
        .while_loop => |ws| {
            try ctx.loop_breaks.append(ctx.alloc, std.ArrayListUnmanaged(u32).empty);
            const head_idx: u32 = @intCast(ctx.instrs.items.len);
            try ctx.loop_heads.append(ctx.alloc, head_idx);
            defer _ = ctx.loop_heads.pop();
            const cond = try lowerExpr(ctx, ws.cond);
            const fail_idx = ctx.instrs.items.len;
            try ctx.emit(.{ .op = .br, .lhs = cond, .branch_target = 0, .branch_condition = .when_false });
            // A loop body is never an implicit-tail position: its last statement
            // runs once per iteration, not once per call. Propagating
            // `allow_return` here makes `tryEmitTailDemandReturn` end the body
            // with `return <last expr>`, so the loop returns after one pass.
            // Explicit `return` inside the body still lowers via the `.ret` arm.
            _ = try lowerBlockReturns(ctx, &ws.body, false);
            try ctx.emit(.{ .op = .br, .branch_target = head_idx });
            const end_idx: u32 = @intCast(ctx.instrs.items.len);
            ctx.instrs.items[fail_idx].branch_target = end_idx;
            var breaks = ctx.loop_breaks.pop() orelse return bail(ctx.diagnostic, @src());
            defer breaks.deinit(ctx.alloc);
            for (breaks.items) |br_idx| {
                ctx.instrs.items[br_idx].branch_target = end_idx;
            }
        },
        .num_for => |nf| try lowerNumFor(ctx, nf),
        .ret => |r| {
            if (r.vals.len == 0) {
                try ctx.emit(.{ .op = .ret, .lhs = .{ .i64 = 0 } });
            } else if (r.vals.len > 1) {
                if (ctx.ret_pack.len != r.vals.len) {
                    return bailWith(ctx.diagnostic, @src(), "result-pack-arity");
                }
                const vals = try ctx.alloc.alloc(dnir.Value, r.vals.len);
                errdefer ctx.alloc.free(vals);
                for (r.vals, 0..) |value, i| {
                    const expected = ctx.ret_pack[i];
                    if (expected == .f64 or expected == .any or expected == .void or
                        expected == .@"struct" or expected == .table_type)
                    {
                        return bailWith(ctx.diagnostic, @src(), "result-pack-abi");
                    }
                    vals[i] = try lowerExpr(ctx, value);
                }
                try ctx.emit(.{ .op = .ret_pack, .vals = vals });
            } else if (r.vals[0].* == .table or
                (ctx.ret_record != null and isRecordLocalName(ctx, r.vals[0])))
            {
                try lowerRecordReturn(ctx, r.vals[0]);
            } else if (!try tryEmitSelfTail(ctx, r.vals[0])) {
                const ret_ty: RT = if (exprIsF64(ctx, r.vals[0]))
                    .f64
                else if (exprIsPointer(ctx, r.vals[0]))
                    physical_pointer
                else
                    .any;
                try ctx.emit(.{ .op = .ret, .lhs = try lowerExpr(ctx, r.vals[0]), .ty = ret_ty });
            }
        },
        .expr_stmt => |es| {
            // A bare table expression statement is the block's tail result —
            // `tryEmitTailDemandReturn` turns it into the record return. When a
            // preceding statement pushes it out of `blk.tail_expr` and into
            // `stmts`, lowering it here as an ordinary expression hit
            // `lowerExprCons`, which has no `.table` arm, and failed the whole
            // function. Leave it for the tail handler.
            if (es.expr.* == .table) return;
            _ = try lowerExprCons(ctx, es.expr, exprCallConsumption(es.expr));
        },
        .call_stmt => |cs| {
            _ = try lowerExprCons(ctx, cs.expr, .discard);
        },
        .brk => {
            if (ctx.loop_breaks.items.len == 0) return bail(ctx.diagnostic, @src());
            const br_idx: u32 = @intCast(ctx.instrs.items.len);
            try ctx.emit(.{ .op = .br, .branch_target = 0 });
            try ctx.loop_breaks.items[ctx.loop_breaks.items.len - 1].append(ctx.alloc, br_idx);
        },
        .cont => {
            if (ctx.loop_heads.items.len == 0) return bail(ctx.diagnostic, @src());
            try ctx.emit(.{ .op = .br, .branch_target = ctx.loop_heads.items[ctx.loop_heads.items.len - 1] });
        },
        else => return bailWith(ctx.diagnostic, @src(), @tagName(stmt.*)),
    }
}

fn lowerBlockReturns(ctx: *LowerCtx, block: *const ast.Block, allow_return: bool) Error!bool {
    const saved_answering = ctx.block_answering;
    ctx.block_answering = allow_return;
    defer ctx.block_answering = saved_answering;
    for (block.stmts, 0..) |*stmt, i| {
        const tail_here = allow_return and stmtIsTailSlot(block, i);
        if (stmt.* == .ret) {
            try lowerStmt(ctx, stmt, tail_here);
            return true;
        }
        try tryEmitVectorReductionPrologue(ctx, block.stmts, i);
        try lowerStmt(ctx, stmt, tail_here);
    }
    if (allow_return) return try tryEmitTailDemandReturn(ctx, block);
    try lowerBlockTailEffect(ctx, block);
    return false;
}

/// gap[104] — a block's tail expression whose value NOBODY DEMANDS is a
/// STATEMENT, and it has to be lowered like one.
///
/// `blk.tail_expr` is the parser's home for a final expression, and the ONLY
/// thing that ever lowered it was `tryEmitTailDemandReturn`, which the two
/// callers here reach exclusively under `allow_return`. A branch body or a loop
/// body is lowered with `allow_return = false` — correctly, since neither is
/// the function's answer — so its tail expression was walked past by the
/// statement loop (it is not in `block.stmts`) and then never lowered at all.
/// Two paths, each right on its own, with the tail expression falling between:
///
///     if 42 > 10
///         print("first")   -- a statement; emitted
///         print("last")    -- the tail expression; SILENTLY DROPPED
///     end
///
///     while n < 3
///         n += 1           -- a statement; emitted
///         print("b")       -- the tail expression; SILENTLY DROPPED
///     end
///
/// Both printed nothing where the C backend printed. This is not about `print`,
/// not about constant conditions and not about branching: the branch is taken
/// (`if 42 > 10 return 7` answers 7 on both backends) and the loop iterates the
/// right number of times. Only the tail slot of a non-answering block is lost.
/// A tail ASSIGNMENT was always fine because an assignment is a `stmt`, so it
/// rides the loop above — which is exactly why the defect looked like it was
/// about void calls.
///
/// The C backend is the oracle and already states the rule: its `.statement`
/// tail mode emits `expr;` for the same position. `.discard` consumption is the
/// DNIR spelling of that semicolon.
///
/// `.table` is skipped for the reason `lowerStmt`'s `.expr_stmt` arm skips it —
/// `lowerExprCons` has no `.table` arm, so lowering one fails the whole
/// function. A bare table in a discarded position carries no effect, so
/// dropping it is the right answer rather than a second hole.
fn lowerBlockTailEffect(ctx: *LowerCtx, block: *const ast.Block) Error!void {
    const e = block.tail_expr orelse return;
    if (e.* == .table) return;
    _ = try lowerExprCons(ctx, e, exprCallConsumption(e));
}

/// gap[104] at the ANSWERING end of a block — the third home of the same hole.
///
/// `blockTailResult` treats a void-shaped tail call as transparent and walks
/// BACK to the preceding statement for the block's value, which is right: a
/// file ending in `print(…)` still answers with whatever it computed. But the
/// resolution it hands back then names that EARLIER statement, and both
/// consumers used it as the whole answer — so the tail expression itself,
/// which is not in `block.stmts` and is no longer the resolved result, was
/// lowered by nobody:
///
///     a = 64
///     print("{a}")
///
/// compiled, exited 64, and printed NOTHING, where the C oracle printed 64 and
/// exited 0. Every shape in `examples/table/` is this: a binding, then a tail
/// `print`. It stayed invisible while `print` refused outside gate transport —
/// a refusal cannot answer wrong — and became a SILENT WRONG ANSWER the moment
/// egress compiled everywhere.
///
/// `lowerBlockTailEffect` already states the rule for a non-answering block.
/// This is the same rule where the block does answer: the anchored value is the
/// result, and the tail expression is a discarded statement that still runs.
fn tailAnchoredAway(block: *const ast.Block, r: tail_result_demand.Resolution) bool {
    const tail = block.tail_expr orelse return false;
    return tail != r.expr;
}

/// Whether statement `i` occupies the slot the block's result comes out of.
///
/// `allow_return` means "this block's value is the function's answer", and it
/// was handed to EVERY statement in the block rather than only the last one.
/// The `.if_stmt` arm passes it straight into each branch body, so a branch
/// whose last statement is an assignment had that assignment rewritten into a
/// `return` by `tryEmitTailDemandReturn` — correct when the `if` really is the
/// block's tail, a miscompile when anything follows it:
///
///     r: i64 = 0
///     if r == 0
///         r = 5        -- lowered to `mov x0, #5 ; ret`
///     end
///     r += 100      -- unreachable
///     print(r)         -- unreachable
///
/// printed nothing and returned 5, where the C backend printed 105. The whole
/// remainder of the enclosing block was dead code behind a `ret` that the
/// branch had no business emitting. `while_loop` already forced `false` here
/// for the same reason, with the same comment; the `if` arm needed the rule
/// too, but conditionally, because an `if` CAN be a block's tail.
///
/// A trailing `tail_expr` is by definition the last thing in the block, so when
/// one is present NO statement is the tail slot — the branches join and the
/// tail expression is what returns.
fn stmtIsTailSlot(block: *const ast.Block, i: usize) bool {
    if (block.tail_expr != null) return false;
    return i + 1 == block.stmts.len;
}

/// A branch is a value guard when its tail is an explicit value-carrying
/// expression — `if n < 2 \n n`, `if x < 0 \n -x`. Taking such a branch is a
/// function exit whose value is the answer, even when the `if` is not the
/// block's syntactic tail (a guard clause preceding the fall-through result).
///
/// This is deliberately narrow. A branch whose tail is a trailing ASSIGNMENT
/// (`if r == 0 \n r = 5`) or a void-shaped effect (`if c \n print(" ")`) is NOT
/// a guard: it must fall through so the rest of the enclosing block still runs
/// (see the miscompiles catalogued at `stmtIsTailSlot`). Only an explicit
/// `tail_expr` that carries a value qualifies; an assignment lives in
/// `block.stmts` and has no `tail_expr`.
fn branchIsValueGuard(block: *const ast.Block) bool {
    const e = block.tail_expr orelse return false;
    return !tail_result_demand.isVoidShapedCall(e);
}

fn intLiteralStep(expr: *const ast.Expr) ?i64 {
    return switch (expr.*) {
        .int_lit => |i| i.val,
        .unop => |u| blk: {
            if (u.op != .neg or u.operand.* != .int_lit) break :blk null;
            break :blk -u.operand.int_lit.val;
        },
        else => null,
    };
}

fn resolveIntStep(ctx: *LowerCtx, step: *const ast.Expr) Error!i64 {
    if (intLiteralStep(step)) |v| return v;
    if (step.* == .name) {
        if (ctx.const_ints.get(step.name.ident)) |v| return v;
    }
    return bail(ctx.diagnostic, @src());
}

fn lowerNumFor(ctx: *LowerCtx, loop: anytype) Error!void {
    if (loop.var_typ != .inferred and !isIntType(loop.var_typ)) return bail(ctx.diagnostic, @src());
    const step_lit: ?i64 = if (loop.step) |step| resolveIntStep(ctx, step) catch null else 1;
    if (step_lit == null) {
        try lowerRuntimeNumFor(ctx, loop);
        return;
    }
    const step = step_lit.?;
    if (step == 0) return bail(ctx.diagnostic, @src());
    try lowerConstNumFor(ctx, loop, step);
}

fn lowerConstNumFor(ctx: *LowerCtx, loop: anytype, step_lit: i64) Error!void {
    try lowerAssignTarget(ctx, loop.var_name, loop.start);
    const i_slot = ctx.locals.get(loop.var_name) orelse return bail(ctx.diagnostic, @src());
    const head_idx: u32 = @intCast(ctx.instrs.items.len);
    const cond_temp = ctx.freshTemp();
    const cmp_op: dnir.BinOpTag = if (step_lit > 0) .leq else .geq;
    try ctx.emit(.{
        .op = .binop,
        .result = cond_temp,
        .binop = cmp_op,
        .lhs = .{ .local = i_slot },
        .rhs = try lowerExpr(ctx, loop.stop),
    });
    const fail_idx = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br, .lhs = .{ .temp = cond_temp }, .branch_target = 0, .branch_condition = .when_false });
    // Loop bodies are not implicit-tail positions — see the while_loop arm.
    _ = try lowerBlockReturns(ctx, &loop.body, false);
    const next_temp = ctx.freshTemp();
    try ctx.emit(.{
        .op = .binop,
        .result = next_temp,
        .binop = .add,
        .lhs = .{ .local = i_slot },
        .rhs = .{ .i64 = step_lit },
    });
    try ctx.emit(.{ .op = .store_local, .result = i_slot, .lhs = .{ .temp = next_temp } });
    try ctx.emit(.{ .op = .br, .branch_target = head_idx });
    const end_idx: u32 = @intCast(ctx.instrs.items.len);
    ctx.instrs.items[fail_idx].branch_target = end_idx;
}

fn lowerRuntimeNumFor(ctx: *LowerCtx, loop: anytype) Error!void {
    try lowerAssignTarget(ctx, loop.var_name, loop.start);
    const i_slot = ctx.locals.get(loop.var_name) orelse return bail(ctx.diagnostic, @src());

    const stop_key = try ctx.alloc.dupe(u8, "__dnir_stop");
    const stop_slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, stop_key, stop_slot);
    const stop_v = try lowerExpr(ctx, loop.stop);
    try ctx.emit(.{ .op = .store_local, .result = stop_slot, .lhs = stop_v });

    const step_key = try ctx.alloc.dupe(u8, "__dnir_step");
    const step_slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, step_key, step_slot);
    const step_v = if (loop.step) |step| try lowerExpr(ctx, step) else @as(dnir.Value, .{ .i64 = 1 });
    try ctx.emit(.{ .op = .store_local, .result = step_slot, .lhs = step_v });

    const head_idx: u32 = @intCast(ctx.instrs.items.len);

    const sign_temp = ctx.freshTemp();
    try ctx.emit(.{
        .op = .binop,
        .result = sign_temp,
        .binop = .lt,
        .lhs = .{ .local = step_slot },
        .rhs = .{ .i64 = 0 },
    });
    const to_pos_idx = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br, .lhs = .{ .temp = sign_temp }, .branch_target = 0, .branch_condition = .when_false });

    const neg_cond = ctx.freshTemp();
    try ctx.emit(.{
        .op = .binop,
        .result = neg_cond,
        .binop = .geq,
        .lhs = .{ .local = i_slot },
        .rhs = .{ .local = stop_slot },
    });
    const neg_fail = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br, .lhs = .{ .temp = neg_cond }, .branch_target = 0, .branch_condition = .when_false });
    const to_body_from_neg = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br, .branch_target = 0 });

    const pos_check_idx: u32 = @intCast(ctx.instrs.items.len);
    ctx.instrs.items[to_pos_idx].branch_target = pos_check_idx;

    const pos_cond = ctx.freshTemp();
    try ctx.emit(.{
        .op = .binop,
        .result = pos_cond,
        .binop = .leq,
        .lhs = .{ .local = i_slot },
        .rhs = .{ .local = stop_slot },
    });
    const pos_fail = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br, .lhs = .{ .temp = pos_cond }, .branch_target = 0, .branch_condition = .when_false });

    const body_idx: u32 = @intCast(ctx.instrs.items.len);
    ctx.instrs.items[to_body_from_neg].branch_target = body_idx;

    // Loop bodies are not implicit-tail positions — see the while_loop arm.
    _ = try lowerBlockReturns(ctx, &loop.body, false);

    const next_temp = ctx.freshTemp();
    try ctx.emit(.{
        .op = .binop,
        .result = next_temp,
        .binop = .add,
        .lhs = .{ .local = i_slot },
        .rhs = .{ .local = step_slot },
    });
    try ctx.emit(.{ .op = .store_local, .result = i_slot, .lhs = .{ .temp = next_temp } });
    try ctx.emit(.{ .op = .br, .branch_target = head_idx });

    const exit_idx: u32 = @intCast(ctx.instrs.items.len);
    ctx.instrs.items[neg_fail].branch_target = exit_idx;
    ctx.instrs.items[pos_fail].branch_target = exit_idx;
}

fn exprIsF64(ctx: *LowerCtx, expr: *const ast.Expr) bool {
    if (applicationResultIs(ctx, expr, .f64)) return true;
    return switch (expr.*) {
        .float_lit => true,
        .call => exprReturnsF64(ctx, expr),
        .name => |n| blk: {
            const slot = ctx.locals.get(n.ident) orelse break :blk false;
            break :blk ctx.f64_slots.contains(slot);
        },
        else => false,
    };
}

/// True for the `ptr` / `void*` annotation — the base address of a
/// memory-backed positional table.
fn typeIsPtr(t: ast.TypeExpr) bool {
    return switch (t) {
        .named => |name| std.mem.eql(u8, name, "ptr") or std.mem.eql(u8, name, "void*"),
        .pointer => true,
        else => false,
    };
}

/// The expression produces an address value. Exact pointee identity stays in
/// the graph descriptor; this predicate selects the one-register physical
/// representation and propagates it through local storage.
fn exprIsPointer(ctx: *const LowerCtx, expr: *const ast.Expr) bool {
    if (applicationResultIs(ctx, expr, .pointer)) return true;
    return switch (expr.*) {
        .name => |n| blk: {
            const slot = ctx.locals.get(n.ident) orelse break :blk false;
            break :blk ctx.ptr_slots.contains(slot);
        },
        .call => |call| blk: {
            if (call.func.* != .field or call.func.field.obj.* != .name) break :blk false;
            const field = call.func.field;
            if (!std.mem.eql(u8, field.obj.name.ident, "mem")) break :blk false;
            break :blk std.mem.eql(u8, field.field, "alloc") or
                std.mem.eql(u8, field.field, "ptr_from_addr");
        },
        .if_expr => |branch| exprIsPointer(ctx, branch.then_expr) and
            exprIsPointer(ctx, branch.else_expr),
        else => false,
    };
}

/// True when `name` binds a positional table — either already memory-backed, or
/// register-exploded with a recorded length.
fn nameIsPositionalTable(ctx: *LowerCtx, name: []const u8) bool {
    if (ctx.locals.get(name)) |s| {
        if (ctx.ptr_slots.contains(s)) return true;
    }
    var buf: [256]u8 = undefined;
    const len_key = std.fmt.bufPrint(&buf, "{s}.len", .{name}) catch return false;
    const len_slot = ctx.locals.get(len_key) orelse return false;
    return ctx.table_lens.contains(len_slot);
}

/// True when any positional table bound anywhere in `stmts` is wider than the
/// select chain serves.
///
/// One table crossing the threshold decides the representation for EVERY table
/// in the function, because the two representations must not be mixed. A loop
/// that both loads from a memory-backed table and stores into a select-chain
/// one reads a stale index — `x = w(i) ; r(i) = x` kept yielding `w(1)`. That
/// is a real backend defect independent of this pass, but it was unreachable
/// while wide tables simply refused to compile, and making them compile is what
/// exposed it. Choosing one representation per function keeps this change to
/// what it is meant to be: strictly more programs accepted, none altered.
fn stmtsBindWideTable(stmts: []const ast.Stmt) bool {
    for (stmts) |st| {
        const wide = switch (st) {
            .local_decl => |d| exprsBindWideTable(d.inits),
            .global_decl => |d| exprsBindWideTable(d.inits),
            .const_decl => |d| exprIsWideTable(d.val),
            .assign => |a| exprsBindWideTable(a.values),
            .do_block => |b| stmtsBindWideTable(b.body.stmts),
            .while_loop => |w| stmtsBindWideTable(w.body.stmts),
            .repeat_loop => |r| stmtsBindWideTable(r.body.stmts),
            .num_for => |f| stmtsBindWideTable(f.body.stmts),
            .gen_for => |f| stmtsBindWideTable(f.body.stmts),
            .if_stmt => |f| blk: {
                if (stmtsBindWideTable(f.then.stmts)) break :blk true;
                for (f.elseifs) |ei| if (stmtsBindWideTable(ei.body.stmts)) break :blk true;
                break :blk if (f.else_body) |eb| stmtsBindWideTable(eb.stmts) else false;
            },
            else => false,
        };
        if (wide) return true;
    }
    return false;
}

fn exprsBindWideTable(exprs: []const *ast.Expr) bool {
    for (exprs) |e| if (exprIsWideTable(e)) return true;
    return false;
}

// ---------------------------------------------------------------------------
// THE FACT THAT DECIDES A TABLE'S REPRESENTATION IS INDEX CONSTANCY, NOT WIDTH.
//
// A select chain answers `t(i)` with one compare-and-select PER ELEMENT. For a
// compile-time index that is free — the chain collapses to the element's own
// slot, or to the literal. For a RUNTIME index it is a LINEAR SCAN, O(width) on
// every single access, and it is the dominant cost of this whole project:
// profiled on `native.out`, 62,587,868 of 94,458,056 executed instructions —
// 66.3% — are array subscripts lowered to if-chains. One subscript into a
// 16-element array costs exactly 60 instructions; into an 8-element array,
// exactly 29. Memory costs one scaled load, at any width.
//
// So the ordering INVERTS with index constancy, which is why a width threshold
// could never be tuned into the right answer:
//
//                        constant index      runtime index
//     select chain              2 instrs      O(width) — 305 at width 32
//     frame memory            174 instrs      O(1)     — 206 at width 33
//
// The decision, in the order it is taken:
//
//   1. DETERMINED and read only at compile-time indices -> no table at all
//      (`noteConstTable`); the value is the answer, at any extent.
//   2. Read or written at a RUNTIME index -> frame memory, AT ANY WIDTH. This
//      function.
//   3. Wider than the register file can hold -> frame memory. `select_chain_max`
//      survives ONLY as this feasibility bound; it no longer selects a strategy.
//   4. Otherwise -> one slot per element.
//
// Uniform per function, as before: mixing the two representations inside one
// relation is what made `x = w(i) ; r(i) = x` read a stale index.
// ---------------------------------------------------------------------------

const max_tracked_tables = 64;

/// Names bound to a positional table literal in the function being lowered.
/// Overflow answers "assume everything", which costs speed and never an answer.
const TableNames = struct {
    names: [max_tracked_tables][]const u8 = undefined,
    len: usize = 0,
    overflow: bool = false,

    fn add(self: *TableNames, n: []const u8) void {
        if (self.has(n)) return;
        if (self.len == max_tracked_tables) {
            self.overflow = true;
            return;
        }
        self.names[self.len] = n;
        self.len += 1;
    }

    fn has(self: *const TableNames, n: []const u8) bool {
        if (self.overflow) return true;
        for (self.names[0..self.len]) |e| if (std.mem.eql(u8, e, n)) return true;
        return false;
    }
};

fn collectTableNamesExpr(name: []const u8, init: *const ast.Expr, out: *TableNames) void {
    if (init.* == .table and tableIsPositional(init)) out.add(name);
}

fn collectTableNames(stmts: []const ast.Stmt, out: *TableNames) void {
    for (stmts) |st| switch (st) {
        .local_decl => |d| for (d.names, 0..) |n, i| {
            if (i < d.inits.len) collectTableNamesExpr(n.ident, d.inits[i], out);
        },
        .global_decl => |d| for (d.names, 0..) |n, i| {
            if (i < d.inits.len) collectTableNamesExpr(n.ident, d.inits[i], out);
        },
        .const_decl => |d| collectTableNamesExpr(d.ident, d.val, out),
        .assign => |a| for (a.targets, 0..) |t, i| {
            if (t.* == .name and i < a.values.len) collectTableNamesExpr(t.name.ident, a.values[i], out);
        },
        .do_block => |b| collectTableNames(b.body.stmts, out),
        .while_loop => |w| collectTableNames(w.body.stmts, out),
        .repeat_loop => |r| collectTableNames(r.body.stmts, out),
        .num_for => |f| collectTableNames(f.body.stmts, out),
        .gen_for => |f| collectTableNames(f.body.stmts, out),
        .if_stmt => |f| {
            collectTableNames(f.then.stmts, out);
            for (f.elseifs) |ei| collectTableNames(ei.body.stmts, out);
            if (f.else_body) |eb| collectTableNames(eb.stmts, out);
        },
        else => {},
    };
}

/// `t(k)` on a tracked table with `k` not a compile-time literal.
fn exprRuntimeIndexes(expr: *const ast.Expr, tables: *const TableNames) bool {
    return switch (expr.*) {
        .index => |ix| blk: {
            if (ix.obj.* == .name and tables.has(ix.obj.name.ident) and
                intLiteralStep(ix.key) == null) break :blk true;
            break :blk exprRuntimeIndexes(ix.obj, tables) or exprRuntimeIndexes(ix.key, tables);
        },
        .field => |f| exprRuntimeIndexes(f.obj, tables),
        .call => |c| blk: {
            if (exprRuntimeIndexes(c.func, tables)) break :blk true;
            for (c.args) |a| if (exprRuntimeIndexes(a, tables)) break :blk true;
            break :blk false;
        },
        .method_call => |m| blk: {
            if (exprRuntimeIndexes(m.obj, tables)) break :blk true;
            for (m.args) |a| if (exprRuntimeIndexes(a, tables)) break :blk true;
            break :blk false;
        },
        .binop => |b| exprRuntimeIndexes(b.lhs, tables) or exprRuntimeIndexes(b.rhs, tables),
        .unop => |u| exprRuntimeIndexes(u.operand, tables),
        .try_expr => |x| exprRuntimeIndexes(x.operand, tables),
        .unwrap_expr => |x| exprRuntimeIndexes(x.operand, tables),
        .await_expr => |x| exprRuntimeIndexes(x.operand, tables),
        .contains_expr => |c| exprRuntimeIndexes(c.lhs, tables) or exprRuntimeIndexes(c.rhs, tables),
        .if_expr => |ie| exprRuntimeIndexes(ie.cond, tables) or
            exprRuntimeIndexes(ie.then_expr, tables) or exprRuntimeIndexes(ie.else_expr, tables),
        .sequence => |s| blk: {
            for (s.exprs) |e| if (exprRuntimeIndexes(e, tables)) break :blk true;
            break :blk false;
        },
        .range => |r| exprRuntimeIndexes(r.start, tables) or exprRuntimeIndexes(r.end, tables) or
            (if (r.step) |st| exprRuntimeIndexes(st, tables) else false),
        .macro_call => |mc| blk: {
            for (mc.args) |a| if (exprRuntimeIndexes(a, tables)) break :blk true;
            break :blk false;
        },
        .table => |t| blk: {
            for (t.fields) |fld| {
                const hit = switch (fld) {
                    .positional => |v| exprRuntimeIndexes(v, tables),
                    .named => |nf| exprRuntimeIndexes(nf.val, tables),
                    .semantic => |sf| exprRuntimeIndexes(sf.val, tables),
                    .spread => |sp| exprRuntimeIndexes(sp, tables),
                    .indexed => |ix| exprRuntimeIndexes(ix.key, tables) or exprRuntimeIndexes(ix.val, tables),
                };
                if (hit) break :blk true;
            }
            break :blk false;
        },
        .match_expr => |m| blk: {
            if (exprRuntimeIndexes(m.scrutinee, tables)) break :blk true;
            for (m.arms) |arm| {
                if (arm.guard) |g| if (exprRuntimeIndexes(g, tables)) break :blk true;
                if (blockRuntimeIndexes(&arm.body, tables)) break :blk true;
            }
            break :blk false;
        },
        // Unmodeled shapes answer "no runtime index seen", which keeps today's
        // representation. This question only trades speed for speed — either
        // answer compiles and both are correct — so the safe default here is the
        // one that changes nothing.
        else => false,
    };
}

fn blockRuntimeIndexes(block: *const ast.Block, tables: *const TableNames) bool {
    for (block.stmts) |*s| if (stmtRuntimeIndexes(s, tables)) return true;
    if (block.tail_expr) |t| return exprRuntimeIndexes(t, tables);
    return false;
}

fn stmtRuntimeIndexes(stmt: *const ast.Stmt, tables: *const TableNames) bool {
    return switch (stmt.*) {
        .local_decl => |d| blk: {
            for (d.inits) |e| if (exprRuntimeIndexes(e, tables)) break :blk true;
            break :blk false;
        },
        .const_decl => |d| exprRuntimeIndexes(d.val, tables),
        .global_decl => |d| blk: {
            for (d.inits) |e| if (exprRuntimeIndexes(e, tables)) break :blk true;
            break :blk false;
        },
        // The STORE face counts too: `t(i) = v` with a runtime `i` is a
        // select-chain of stores, the same linear scan from the other side.
        .assign => |a| blk: {
            for (a.targets) |t| if (exprRuntimeIndexes(t, tables)) break :blk true;
            for (a.values) |e| if (exprRuntimeIndexes(e, tables)) break :blk true;
            break :blk false;
        },
        .call_stmt => |c| exprRuntimeIndexes(c.expr, tables),
        .expr_stmt => |c| exprRuntimeIndexes(c.expr, tables),
        .do_block => |d| blockRuntimeIndexes(&d.body, tables),
        .while_loop => |w| exprRuntimeIndexes(w.cond, tables) or blockRuntimeIndexes(&w.body, tables),
        .repeat_loop => |r| blockRuntimeIndexes(&r.body, tables) or exprRuntimeIndexes(r.cond, tables),
        .if_stmt => |f| blk: {
            if (f.binding) |b| if (exprRuntimeIndexes(b.expr, tables)) break :blk true;
            if (exprRuntimeIndexes(f.cond, tables)) break :blk true;
            if (blockRuntimeIndexes(&f.then, tables)) break :blk true;
            for (f.elseifs) |ei| {
                if (exprRuntimeIndexes(ei.cond, tables)) break :blk true;
                if (blockRuntimeIndexes(&ei.body, tables)) break :blk true;
            }
            if (f.else_body) |eb| if (blockRuntimeIndexes(&eb, tables)) break :blk true;
            break :blk false;
        },
        .num_for => |n| blk: {
            if (exprRuntimeIndexes(n.start, tables) or exprRuntimeIndexes(n.stop, tables)) break :blk true;
            if (n.step) |st| if (exprRuntimeIndexes(st, tables)) break :blk true;
            break :blk blockRuntimeIndexes(&n.body, tables);
        },
        .gen_for => |g| blk: {
            for (g.iters) |e| if (exprRuntimeIndexes(e, tables)) break :blk true;
            break :blk blockRuntimeIndexes(&g.body, tables);
        },
        .ret => |r| blk: {
            for (r.vals) |e| if (exprRuntimeIndexes(e, tables)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

/// The per-function representation decision. See the block comment above.
fn blockNeedsMemoryTables(body: *const ast.Block) bool {
    if (stmtsBindWideTable(body.stmts)) return true;
    var tables: TableNames = .{};
    collectTableNames(body.stmts, &tables);
    if (tables.len == 0 and !tables.overflow) return false;
    return blockRuntimeIndexes(body, &tables);
}

fn exprIsWideTable(expr: *const ast.Expr) bool {
    if (expr.* != .table) return false;
    var n: i64 = 0;
    for (expr.table.fields) |fld| {
        if (fld != .positional) return false;
        n += 1;
    }
    return n > select_chain_max;
}

/// Widest table whose variable-index access still lowers as a select chain.
///
/// A register-exploded table answers `t(i)` with one compare-and-select per
/// element, so the chain is O(len) instructions for a single access. That is a
/// win while the table is small — no memory traffic at all — and a loss once it
/// is not. Past this width both access paths materialize the table into frame
/// memory and issue one scaled load/store instead, which is also what lifts the
/// old order-8 ceiling on `rec`: nothing about the recurrence needed 8, the
/// coefficients simply had nowhere wider to live.
///
/// ONE SOURCE, NOT TWO IN AGREEMENT. This was declared here AND in
/// `table_facts.zig`, the second carrying a comment saying the two "MUST equal"
/// each other. Two declarations that must be kept equal is the shape that gave
/// this project a JIT emitting "native" while its caller compared against
/// "arm64" — nothing detects the day they stop matching. The FACT module owns
/// the decision; this pass consumes it.
///
/// Note what the threshold does and does not decide any more. It chooses how to
/// REALIZE a table that must exist. Whether one must exist at all is answered
/// before it, by `noteConstTable`, and that answer holds at every extent.
const select_chain_max: i64 = table_facts.select_chain_max;

/// The slot holding a table base address, when `expr` names one.
fn ptrSlotOf(ctx: *LowerCtx, expr: *const ast.Expr) ?u32 {
    if (expr.* != .name) return null;
    const slot = ctx.locals.get(expr.name.ident) orelse return null;
    if (!ctx.ptr_slots.contains(slot)) return null;
    return slot;
}

/// Copy a register-exploded positional table into a contiguous frame region and
/// return the slot holding its base address.
///
/// This is the bridge between the two representations. Elements stay in
/// registers for local use (which is faster and is what the existing select-chain
/// lowering depends on); memory is materialized only where a base pointer is
/// actually needed — at a call site. A table already living in memory (a `ptr`
/// param being forwarded) is passed straight through.
fn materializeTableSlots(ctx: *LowerCtx, name: []const u8) Error!u32 {
    if (ctx.locals.get(name)) |s| {
        if (ctx.ptr_slots.contains(s)) return s;
    }
    const len_key = try std.fmt.allocPrint(ctx.alloc, "{s}.len", .{name});
    defer ctx.alloc.free(len_key);
    const len_slot = ctx.locals.get(len_key) orelse return bail(ctx.diagnostic, @src());
    const len = ctx.table_lens.get(len_slot) orelse return bail(ctx.diagnostic, @src());
    if (len <= 0 or len > 4096) return bail(ctx.diagnostic, @src());

    const base = ctx.freshTemp();
    try ctx.emit(.{ .op = .alloc_slots, .result = base, .lhs = .{ .i64 = len } });
    var i: i64 = 1;
    while (i <= len) : (i += 1) {
        const elem_key = try std.fmt.allocPrint(ctx.alloc, "{s}.{d}", .{ name, i });
        defer ctx.alloc.free(elem_key);
        const elem_slot = ctx.locals.get(elem_key) orelse return bail(ctx.diagnostic, @src());
        try ctx.emit(.{
            .op = .store_index,
            .ty = .i64,
            .lhs = .{ .temp = base },
            .rhs = .{ .i64 = i },
            .third = .{ .local = elem_slot },
        });
    }
    try ctx.ptr_slots.put(ctx.alloc, base, {});
    // From here on the name *is* the memory. Rebinding it means every later
    // read, write and argument in this function goes through the same base, so a
    // callee's `t[2] = 99` is visible to the caller. Without this, each call site
    // materialized a fresh copy from the (now stale) element registers and
    // mutations were silently lost. Reads before this point are still correct:
    // materialization happens at the first call that takes the table, so nothing
    // could have mutated it yet.
    try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, name), base);
    return base;
}

// ---------------------------------------------------------------------------
// The vector beachhead: one integer reduction over a memory-backed table.
// ---------------------------------------------------------------------------

/// Marks a DNIR `hw_unary` as a VECTOR REDUCTION rather than a scalar bit
/// intrinsic. `native_backend.zig` reads the same constant.
///
/// This rides `hw_unary` + `.field` because a vector op is not expressible in
/// `native_ir.zig`'s `Op` set and that file is not this pass's to change. The
/// convention is not invented here: `mov_arg` already discriminates its
/// variadic-tail form with `.field = "vararg"`. The tag is checked FIRST in the
/// backend's `hw_unary` arm, so `.hw` stays `.none` and every existing consumer
/// — `intrinsicOfOp`, `functionHardwareTier`, `definition` — reads exactly what
/// it read before. That also means the module's hardware tier still reports
/// `.scalar`; making it report `.vector` needs an `Op`, which is the first item
/// in "what remains".
pub const vec_reduce_add_i64_tag = "vec.reduce.add.i64";

/// One 128-bit ARM64 vector register holds two i64 lanes. Everything below is
/// written against this number rather than a literal 2, because the number is
/// the only target-specific thing in the recognizer — the FACTS it checks
/// (contiguity, element type, extent, associativity) are not.
const vec_i64_lanes: i64 = 2;

fn identOf(e: *const ast.Expr) ?[]const u8 {
    return switch (e.*) {
        .name => |n| n.ident,
        else => null,
    };
}

const IndexNames = struct { tbl: []const u8, idx: []const u8 };

/// `tbl[idx]` with both sides plain names, or null.
fn indexNames(e: *const ast.Expr) ?IndexNames {
    const ix = switch (e.*) {
        .index => |x| x,
        else => return null,
    };
    return .{
        .tbl = identOf(ix.obj) orelse return null,
        .idx = identOf(ix.key) orelse return null,
    };
}

const ReduceStep = struct { acc: []const u8, tbl: []const u8, idx: []const u8 };

/// `acc = acc + tbl[idx]` in either operand order (which is also what `+=`
/// desugars to), or null.
fn reduceStep(st: *const ast.Stmt) ?ReduceStep {
    const a = switch (st.*) {
        .assign => |x| x,
        else => return null,
    };
    if (a.targets.len != 1 or a.values.len != 1) return null;
    const acc = identOf(a.targets[0]) orelse return null;
    const b = switch (a.values[0].*) {
        .binop => |x| x,
        else => return null,
    };
    if (b.op != .add) return null;
    if (identOf(b.lhs)) |l| {
        if (std.mem.eql(u8, l, acc)) {
            if (indexNames(b.rhs)) |ix| return .{ .acc = acc, .tbl = ix.tbl, .idx = ix.idx };
        }
    }
    if (identOf(b.rhs)) |r| {
        if (std.mem.eql(u8, r, acc)) {
            if (indexNames(b.lhs)) |ix| return .{ .acc = acc, .tbl = ix.tbl, .idx = ix.idx };
        }
    }
    return null;
}

/// `idx = idx + 1` in either operand order.
fn stepIsIncrementOfOne(st: *const ast.Stmt, idx: []const u8) bool {
    const a = switch (st.*) {
        .assign => |x| x,
        else => return false,
    };
    if (a.targets.len != 1 or a.values.len != 1) return false;
    const t = identOf(a.targets[0]) orelse return false;
    if (!std.mem.eql(u8, t, idx)) return false;
    const b = switch (a.values[0].*) {
        .binop => |x| x,
        else => return false,
    };
    if (b.op != .add) return false;
    if (identOf(b.lhs)) |l| {
        if (std.mem.eql(u8, l, idx) and b.rhs.* == .int_lit and b.rhs.int_lit.val == 1) return true;
    }
    if (identOf(b.rhs)) |r| {
        if (std.mem.eql(u8, r, idx) and b.lhs.* == .int_lit and b.lhs.int_lit.val == 1) return true;
    }
    return false;
}

/// Inclusive last index of `while idx <= N` / `while idx < N`, or null.
fn loopUpperBound(cond: *const ast.Expr, idx: []const u8) ?i64 {
    const b = switch (cond.*) {
        .binop => |x| x,
        else => return null,
    };
    const l = identOf(b.lhs) orelse return null;
    if (!std.mem.eql(u8, l, idx)) return null;
    if (b.rhs.* != .int_lit) return null;
    const n = b.rhs.int_lit.val;
    return switch (b.op) {
        .leq => n,
        .lt => n - 1,
        else => null,
    };
}

/// `name = <int literal>` as the whole of `st`, or null.
///
/// The start index is read from the STATEMENT IMMEDIATELY BEFORE THE LOOP, not
/// from `ctx.const_ints`. That map records a name's last literal binding and is
/// never invalidated by a non-literal reassignment, so after `i = 1 ; i = i + 5`
/// it still answers 1. Reading it here would start the vector run at the wrong
/// element and produce a wrong answer that still compiles — the exact failure
/// mode this beachhead is required to avoid. The preceding statement is the one
/// place where the literal is provably the current value.
fn literalBindingOf(st: *const ast.Stmt, name: []const u8) ?i64 {
    switch (st.*) {
        .assign => |a| {
            if (a.targets.len != 1 or a.values.len != 1) return null;
            const t = identOf(a.targets[0]) orelse return null;
            if (!std.mem.eql(u8, t, name)) return null;
            return if (a.values[0].* == .int_lit) a.values[0].int_lit.val else null;
        },
        .local_decl => |d| {
            if (d.names.len != 1 or d.inits.len != 1) return null;
            if (!std.mem.eql(u8, d.names[0].ident, name)) return null;
            return if (d.inits[0].* == .int_lit) d.inits[0].int_lit.val else null;
        },
        else => return null,
    }
}

/// True when `slot` holds something other than a plain i64.
fn slotIsNonInteger(ctx: *const LowerCtx, slot: u32) bool {
    return ctx.f64_slots.contains(slot) or
        ctx.str_slots.contains(slot) or
        ctx.bool_slots.contains(slot) or
        ctx.ptr_slots.contains(slot);
}

/// THE BEACHHEAD. Emit a NEON prologue for
///
///     idx = LO
///     while idx <= HI
///         acc = acc + tbl[idx]
///         idx = idx + 1
///
/// and nothing else. `stmts[at]` is the loop; `stmts[at - 1]` supplies `LO`.
///
/// The prologue is ADDITIVE: it sums a whole number of LANE-SIZED groups into
/// `acc`, advances `idx` past them, and then the ordinary scalar lowering of the
/// SAME loop runs unchanged and finishes the (at most one) remaining element.
/// Nothing is replaced, so every existing behaviour of that loop — bounds
/// handling, break/continue, the value of `idx` on exit — is whatever it already
/// was. When any condition below fails, this emits nothing at all and the loop
/// lowers exactly as it does today.
///
/// What has to be true, and where each fact comes from:
///
///   CONTIGUITY and ELEMENT TYPE — `tbl` resolves to a `ptr_slot`, i.e. an
///   `alloc_slots` region of 8-byte words. That representation was chosen at the
///   BINDING (`lowerPositionalTableIntoMemory`, or `materializeTableSlots` which
///   rebinds the name), never here. This pass only READS the decision; a
///   register-exploded table is declined, not materialized, so no copy can be
///   emitted at an access site and no loop can restore a table to its initial
///   value.
///
///   EXTENT — `tbl.len` carries the static element count, so `1 <= LO` and
///   `HI <= len` prove every lane load is in bounds without a per-element guard.
///
///   ASSOCIATIVITY — i64 addition. Two's-complement `add` is associative and
///   commutative including on overflow, and `add.2d` wraps identically to `add`,
///   so regrouping the summation is EXACT. This is why the case is integer and
///   not float: a float reduction reassociated this way changes the answer, and
///   that would need an explicit fact this compiler does not have.
///
///   REPRESENTATION UNIFORMITY — no BINDING changes representation. `acc` and
///   `idx` stay ordinary integer locals for the whole function; the vector
///   accumulator is a register private to one instruction's expansion, created
///   and consumed inside it, and never named by any slot.
fn tryEmitVectorReductionPrologue(ctx: *LowerCtx, stmts: []const ast.Stmt, at: usize) Error!void {
    if (at == 0) return;
    const ws = switch (stmts[at]) {
        .while_loop => |w| w,
        else => return,
    };
    // Exactly the two statements, and no tail expression. Anything else in the
    // body could read `acc`, rebind `idx`, or store into `tbl`, and each of
    // those makes the regrouping observable.
    if (ws.body.tail_expr != null) return;
    if (ws.body.stmts.len != 2) return;

    const step = reduceStep(&ws.body.stmts[0]) orelse return;
    if (!stepIsIncrementOfOne(&ws.body.stmts[1], step.idx)) return;
    if (std.mem.eql(u8, step.acc, step.idx)) return;
    if (std.mem.eql(u8, step.acc, step.tbl)) return;
    if (std.mem.eql(u8, step.idx, step.tbl)) return;

    const hi = loopUpperBound(ws.cond, step.idx) orelse return;
    const lo = literalBindingOf(&stmts[at - 1], step.idx) orelse return;
    if (lo < 1 or hi < lo) return;

    const base_slot = ctx.locals.get(step.tbl) orelse return;
    if (!ctx.ptr_slots.contains(base_slot)) return;

    var key_buf: [512]u8 = undefined;
    const len_key = std.fmt.bufPrint(&key_buf, "{s}.len", .{step.tbl}) catch return;
    const len_slot = ctx.locals.get(len_key) orelse return;
    const len = ctx.table_lens.get(len_slot) orelse return;
    if (hi > len) return;

    const acc_slot = ctx.locals.get(step.acc) orelse return;
    if (slotIsNonInteger(ctx, acc_slot)) return;
    const idx_slot = ctx.locals.get(step.idx) orelse return;
    if (slotIsNonInteger(ctx, idx_slot)) return;
    if (acc_slot == idx_slot or acc_slot == base_slot or idx_slot == base_slot) return;

    // Whole lane groups only. A trip count below one group (which includes the
    // empty range) leaves this to the scalar loop entirely.
    const count = hi - lo + 1;
    const vectored = @divTrunc(count, vec_i64_lanes) * vec_i64_lanes;
    if (vectored < vec_i64_lanes) return;

    const sum = ctx.freshTemp();
    try ctx.emit(.{
        .op = .hw_unary,
        .hw = .none,
        .field = vec_reduce_add_i64_tag,
        .ty = .i64,
        .result = sum,
        .lhs = .{ .local = base_slot },
        .rhs = .{ .i64 = lo },
        .third = .{ .i64 = vectored },
    });
    const folded = ctx.freshTemp();
    try ctx.emit(.{
        .op = .binop,
        .result = folded,
        .binop = .add,
        .lhs = .{ .local = acc_slot },
        .rhs = .{ .temp = sum },
        .ty = .any,
    });
    try ctx.emit(.{ .op = .store_local, .result = acc_slot, .lhs = .{ .temp = folded }, .ty = .any });
    try ctx.emit(.{ .op = .store_local, .result = idx_slot, .lhs = .{ .i64 = lo + vectored }, .ty = .any });

    // `idx` is no longer the literal the preceding statement bound. Dropping the
    // entry keeps `const_ints` from answering `LO` for it downstream; every
    // consumer of that map treats a miss as "not compile-time known" and stays
    // conservative.
    if (ctx.const_ints.fetchRemove(step.idx)) |kv| ctx.alloc.free(kv.key);
}

/// True when `expr` holds a BOOLEAN rather than a number.
///
/// A bool rides an integer register, so no representation downstream can tell
/// `true` from `1`. The distinction is only visible where a value is RENDERED:
/// `"{ok}"` must print `true`, and `"%lld"` on the same register prints `1`.
/// That is a wrong answer, not a bail, so every renderer asks this first and
/// refuses whatever it cannot place.
///
/// The predicate is POSITIVE and deliberately narrow — the shapes that are
/// provably bool. Anything outside it is not "known integer"; `exprIsIntegral`
/// still has to prove that separately, and the two together are what admit an
/// operand.
fn exprIsBoolish(ctx: *LowerCtx, expr: *const ast.Expr) bool {
    if (applicationResultIs(ctx, expr, .bool)) return true;
    return switch (expr.*) {
        .true_lit, .false_lit => true,
        .unop => |u| u.op == .not,
        .binop => |b| switch (b.op) {
            .eq, .neq, .lt, .gt, .leq, .geq => true,
            // `a and b` / `a or b` yield an OPERAND in Lua, not a truth value,
            // so they are bool only when both arms are.
            .@"and", .@"or" => exprIsBoolish(ctx, b.lhs) and exprIsBoolish(ctx, b.rhs),
            else => false,
        },
        .call => |c| c.func.* == .name and functionResultIs(ctx, c.func.name.ident, .bool),
        .name => |n| blk: {
            const slot = ctx.locals.get(n.ident) orelse break :blk false;
            break :blk ctx.bool_slots.contains(slot);
        },
        // The expression-if is bool only when BOTH arms are — same rule the
        // `and`/`or` arm above applies, and for the same reason.
        .if_expr => |ie| exprIsBoolish(ctx, ie.then_expr) and exprIsBoolish(ctx, ie.else_expr),
        else => false,
    };
}

/// An operand of `..` this pass can render without changing the answer.
///
/// Either it is already text, or it is provably an integer that is not a bool.
/// `#s`, `s[i]`, an i64 local and an i64-returning call all qualify; an f64, a
/// bool, a record, a table base and anything unproven do not, and each of those
/// is a bail rather than a guess.
fn concatOperandOk(ctx: *LowerCtx, expr: *const ast.Expr) bool {
    if (exprIsStr(ctx, expr)) return true;
    if (exprIsBoolish(ctx, expr)) return false;
    return exprIsIntegral(ctx, expr);
}

fn sameIndex(a: *const ast.Expr, b: *const ast.Expr) bool {
    if (a.* == .name and b.* == .name)
        return std.mem.eql(u8, a.name.ident, b.name.ident);
    if (a.* == .int_lit and b.* == .int_lit)
        return a.int_lit.val == b.int_lit.val;
    return false;
}

/// True when `expr` is known to produce a `str` (a `const char*`), so `#expr`
/// can lower to a `strlen` call rather than a dynamic length probe.
fn exprIsStr(ctx: *LowerCtx, expr: *const ast.Expr) bool {
    if (applicationResultIs(ctx, expr, .str)) return true;
    return switch (expr.*) {
        .quoted => true,
        // `..` ALWAYS produces text, including where one side is a number —
        // which is the shape `"{a} {b}"` desugars to. Requiring both sides to
        // be str was what made every interpolation of an integer answer "not a
        // string" and take the whole enclosing function to the C backend. At
        // least one side must still be a str: two integers concatenated is a
        // shape this pass has never lowered, and claiming it here would let
        // `lowerConcat` produce text where the answer was never checked.
        // `and`/`or` SELECT A VALUE, they do not compute one, so the result is
        // text exactly when every arm that can be selected is text. Without
        // these two arms the value lowered CORRECTLY and was tagged `.i64`, and
        // `lowerPrint` then chose `%lld` and printed the string's ADDRESS:
        //
        //     v = "set" or "FB"            print(v) -> 4304880776
        //     v = c and "yes" or "no"      print(v) -> 4343350452
        //
        // Both are accepted by the native-scalar precheck, whose `expr_type`
        // answers `.str` for the same two shapes (`codegen.zig`, the
        // `.@"and"`/`.@"or"` arms) — so the precheck claimed the shape and the
        // lowering disagreed, which is gap[034] (the precheck and the lowering
        // must claim the SAME set) failing in its dangerous direction: not a
        // refusal, a wrong answer that compiles and runs.
        //
        // The ternary `c and X or Y` needs its own case: it parses as
        // `(c and X) or Y`, and the recursive rule asks whether `c and X` is
        // text, which it is not — `c` is a bool. The reachable arms are X and
        // Y, which is exactly the pair `codegen.expr_type` inspects.
        .binop => |bb| switch (bb.op) {
            .concat => concatOperandOk(ctx, bb.lhs) and concatOperandOk(ctx, bb.rhs) and
                (exprIsStr(ctx, bb.lhs) or exprIsStr(ctx, bb.rhs)),
            .@"or" => if (bb.lhs.* == .binop and bb.lhs.binop.op == .@"and")
                exprIsStr(ctx, bb.lhs.binop.rhs) and exprIsStr(ctx, bb.rhs)
            else
                exprIsStr(ctx, bb.lhs) and exprIsStr(ctx, bb.rhs),
            .@"and" => exprIsStr(ctx, bb.lhs) and exprIsStr(ctx, bb.rhs),
            else => false,
        },
        // Two producers of str, one arm. A producer the type tracker does not
        // know about breaks every consumer downstream, so both belong here:
        //   * a call to a function declared `: str` — without it,
        //     `m = mk(...)` then `#m` bails because the local never entered
        //     str_slots;
        //   * `string.char(n)` — without it the very next `string.byte(s, 1)`
        //     does not recognize its own argument and falls through to an
        //     undefined `string_byte` symbol.
        .call => |c| switch (c.func.*) {
            .name => |n| blk: {
                if (std.mem.eql(u8, n.ident, "to") and c.args.len == 2 and
                    c.args[1].* == .name and std.mem.eql(u8, c.args[1].name.ident, "str") and
                    exprIsIntegral(ctx, c.args[0]))
                    break :blk true;
                // `gatecap(cmd)` captures process stdout as text (GAP-155).
                if (std.mem.eql(u8, n.ident, "gatecap") and c.args.len == 1)
                    break :blk true;
                break :blk functionResultIs(ctx, n.ident, .str);
            },
            // `to(str)(n)` — the relation surface's own producer of str. It is
            // spelled as a call whose CALLEE is a call, so neither the
            // declared-return arm nor the `string.char` arm sees it, and every
            // consumer downstream (`#s`, `s[i]`, `..`) refused its result.
            .call => |inner| c.args.len == 1 and inner.func.* == .name and
                std.mem.eql(u8, inner.func.name.ident, "to") and
                inner.args.len == 1 and inner.args[0].* == .name and
                std.mem.eql(u8, inner.args[0].name.ident, "str"),
            .field => |f| f.obj.* == .name and
                std.mem.eql(u8, f.obj.name.ident, "string") and
                std.mem.eql(u8, f.field, "char"),
            else => false,
        },
        .name => |n| blk: {
            // A module-level string constant is not a local, so the slot lookup
            // below can never see it. Without this arm the VALUE lowered fine
            // and every consumer still read it as an integer: `print(OWNER)`
            // chose `%lld` and printed the pointer, and `OWNER != "x"` compared
            // addresses. The type answer has to follow the value.
            const slot = ctx.locals.get(n.ident) orelse {
                // A WRITTEN module-scope binding is not a constant EITHER — and
                // that is not an oversight, it is the deliberate act of the
                // change that gave globals storage: `lowerModuleFromGraph`
                // removes every written global from `module_consts` because "a
                // name that is written is not a constant". That removal deleted
                // the only path by which this predicate could see a `global S:
                // str`, so the fact remained TRUE and REPRESENTED — in
                // `module_globals.types`, which the `.name` LOWERING arm reads
                // one screen up and even uses to seed `str_slots` — while every
                // predicate that gates a str candidate answered "not text".
                // HPLS §99: represented but not propagated.
                //
                // The declared type is asked EXACTLY, never "not i64": a `%s`
                // hole fed an integer prints an address, which is the concat
                // failure mode this tree has already paid for twice.
                if (ctx.module_globals.types.get(n.ident)) |ty| break :blk ty == .str;
                break :blk ctx.module_consts.strs.contains(n.ident);
            };
            break :blk ctx.str_slots.contains(slot);
        },
        // `Kind.owner` where the descriptor field holds a string literal — the
        // qualified spelling of the same module-level constant.
        .field => |f| blk: {
            // A member edge whose face is a VALUE is that value at its own
            // node, and the roster declares what it is. `cwd(expr)` alone was
            // the one member spelled out; the face is the general fact.
            if (osMemberOf(expr)) |m| {
                if (m.face == .value and m.result == .str) break :blk true;
            }
            if (checkedScalarFieldProjection(ctx, expr)) |ty| break :blk ty == .str;
            if (f.obj.* != .name) break :blk false;
            var buf: [512]u8 = undefined;
            const key = std.fmt.bufPrint(&buf, "{s}.{s}", .{ f.obj.name.ident, f.field }) catch break :blk false;
            if (ctx.module_consts.strs.contains(key)) break :blk true;
            if (ctx.locals.get(key)) |slot| break :blk ctx.str_slots.contains(slot);
            break :blk false;
        },
        // The expression-if produces text only when BOTH arms do. One str arm
        // and one integer arm is a slot whose type depends on the branch taken,
        // which no consumer downstream can read correctly.
        .if_expr => |ie| exprIsStr(ctx, ie.then_expr) and exprIsStr(ctx, ie.else_expr),
        // `t(i)` on a table of text is text at every index. `table_apply`
        // rewrites the application into `.index` before this pass runs, so the
        // dynamic read and the constant read arrive at the SAME node and get
        // the same answer — which is what the select chain, the memory-backed
        // load and `constTableRead` all need, since none of the three can
        // carry an element type in the value it returns.
        // A WORLD PROJECTION IS TEXT WHEN THE ROSTER SAYS SO. This was
        // `argv(ix.obj) or env(ix.obj)` — the two member names spelled out
        // here, and a third member added to the world would have been text at
        // the emit site and not-text at this predicate.
        .index => |ix| (if (osMemberOf(ix.obj)) |m| m.face == .projection and m.result == .str else false) or
            (ix.obj.* == .name and ctx.str_tables.contains(ix.obj.name.ident)),
        .method_call => |mc| blk: {
            if (mc.obj.* == .name and std.mem.eql(u8, mc.obj.name.ident, "io") and
                std.mem.eql(u8, mc.method, "read"))
                break :blk true;
            if (mc.obj.* == .name and std.mem.eql(u8, mc.obj.name.ident, "stdin") and
                std.mem.eql(u8, mc.method, "read") and mc.args.len == 0)
                break :blk true;
            if (mc.obj.* == .name and std.mem.eql(u8, mc.obj.name.ident, "stdin") and
                std.mem.eql(u8, mc.method, "line") and mc.args.len == 0)
                break :blk true;
            if (std.mem.eql(u8, mc.method, "read") and mc.args.len == 0 and
                exprIsStr(ctx, mc.obj))
                break :blk true;
            if (std.mem.eql(u8, mc.method, "to") and mc.args.len == 1 and
                mc.args[0].* == .name and std.mem.eql(u8, mc.args[0].name.ident, "str") and
                exprIsIntegral(ctx, mc.obj))
                break :blk true;
            if (std.mem.eql(u8, mc.method, "sub") and mc.args.len >= 1 and mc.args.len <= 2)
                break :blk exprIsStr(ctx, mc.obj);
            // `has` answers a BOOL, never text. This arm used to answer
            // `exprIsStr(mc.obj)` — copied from `sub` two arms up, where the
            // subject IS the result type — which made `print(s:has(n))`
            // classify the boolean as text, lower through `puts` with the
            // raw 0/1 as the format pointer, and SEGFAULT before any output
            // (measured: exit 139, no stdout, `ok compile` both). Bool prints
            // take the `%lld` path like every other integral answer.
            if (std.mem.eql(u8, mc.method, "has") and mc.args.len == 1)
                break :blk false;
            break :blk false;
        },
        else => false,
    };
}

/// The realized value is text. Print/write must not reconstruct i64 from a
/// pointer just because the AST classifier missed a producer.
fn holds(ctx: *const LowerCtx, v: dnir.Value) bool {
    return switch (v) {
        .str => true,
        .temp => |t| blk: {
            var i = ctx.instrs.items.len;
            while (i > 0) {
                i -= 1;
                const ins = ctx.instrs.items[i];
                if (ins.result) |r| {
                    if (r == t) break :blk ins.ty == .str;
                }
            }
            break :blk false;
        },
        .local => |slot| ctx.str_slots.contains(slot),
        else => false,
    };
}

/// `pack.kinds(i)` on a parameter record is a scaled indexed load, not a graph
/// application. Skip the occurrence requirement so `lowerCall` can take the
/// direct `load_index` path without a published application id.
fn paramRecordSliceFieldCall(ctx: *const LowerCtx, expr: *const ast.Expr) bool {
    const obj = switch (expr.*) {
        .call => |c| blk: {
            if (c.args.len != 1) return false;
            if (c.func.* != .field) return false;
            const f = c.func.field;
            if (f.obj.* != .name) return false;
            break :blk f.obj.name.ident;
        },
        .method_call => |mc| blk: {
            if (mc.args.len != 1) return false;
            if (mc.obj.* != .name) return false;
            break :blk mc.obj.name.ident;
        },
        else => return false,
    };
    if (ctx.param_record_types.get(obj) != null) return true;
    for (ctx.records) |rec| {
        if (rec.fields.len == 0) continue;
        for (rec.fields) |fname| {
            const key = std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ obj, fname }) catch return false;
            defer ctx.alloc.free(key);
            if (ctx.locals.get(key) != null) return true;
        }
    }
    return false;
}


fn applicationNeedsGraphOccurrence(ctx: *const LowerCtx, expr: *const ast.Expr) bool {
    if (!ctx.require_graph_facts) return false;
    if (expr.* != .call and expr.* != .method_call) return false;
    if (ctx.occurrences.get(expr) != null) return false;
    if (paramRecordSliceFieldCall(ctx, expr)) return false;
    return !ctx.graph.bootstrapApplicationExpr(expr);
}

fn lowerAssignTarget(ctx: *LowerCtx, name: []const u8, value: *const ast.Expr) Error!void {
    if (applicationNeedsGraphOccurrence(ctx, value) and !recordExportMapAssignable(ctx, value)) {
        return refuseMissingApplication(ctx, @src(), value);
    }
    // `Alias = req "std.compiler.token"` binds a module at compile time; the
    // alias exists only so `Alias.CONST` can fold and `Alias.fn` can resolve to
    // an extern symbol. There is nothing to store at runtime, and lowering it as
    // an ordinary call pushed the whole program outside the direct subset.
    if (isReqCall(value)) return;
    // THE SOURCE FACE IS NOT THE ABI. `t: pt = mk(3, 2)` and `t: pt = 3:mk(2)`
    // are ONE application — same relation, same operands, same result — and
    // everything below this line reads them from the graph, which already
    // publishes them orientation-free: `applicationTarget` takes the `.binding`
    // edge, `checkedScalarOperands` projects the `.projection` subject and then
    // the position-ordered arguments. NOTHING in the record-result path asks
    // which face was written.
    //
    // This guard did, and that was the whole of the record row's refusal. A
    // `.method_call` skipped the block entirely and fell through to
    // `lowerExprCons` -> `lowerCheckedScalarCall`, whose FIRST act is
    // `checkedScalarResult` — a predicate that admits `i32 i64 bool str f64
    // void any` and nothing else. So the canonical face reached a SCALAR-ONLY
    // consumer for a RECORD result and answered DNB011 `application-result-abi`
    // while the retired operand-first face answered 5, measured. That is a
    // capability tax on canonical syntax, which `protocol-projection-one.md`
    // §10.2 forbids.
    //
    // ADMITTING THE FACE COSTS NO NEW ABI. `record-operand-register-abi`
    // already made record OPERANDS cross in registers, and this is the RESULT
    // side of the same call: `lowerCheckedRecordCallAssign` emits the identical
    // `call_direct` it emits for the operand-first face — measured
    // instruction-identical, and a normalized disassembly diff differs only in
    // the module tag on symbol names.
    //
    // A SCALAR-RESULT `.method_call` IS UNCHANGED, deliberately.
    // `recordForDescriptor` declines, `checkedScalarResult` runs the same
    // predicate `lowerCheckedScalarCall` was about to run on it, and the fall
    // through below reaches the same lowering it always did.
    if (value.* == .call or value.* == .method_call) {
        if (ctx.occurrences.get(value)) |application| {
            bindOccurrence(ctx.diagnostic, ctx.graph, application.application);
            if (recordForApplicationResult(ctx, application)) |record| {
                try lowerCheckedRecordCallAssign(ctx, name, application, record, value);
                return;
            }
            const result_desc = try checkedApplicationResultDescriptor(ctx, application);
            if (try tryAssignRecordCallFromExportMap(ctx, name, value)) return;
            try checkedScalarResult(ctx.diagnostic, result_desc);
            const v = try lowerCheckedScalarCall(ctx, application, .single);
            if (ctx.locals.get(name)) |slot| {
                try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = .any });
            } else {
                const slot = ctx.freshTemp();
                try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, name), slot);
                try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = .any });
            }
            subsumeProducerRefit(ctx);
            return;
        }
    }
    if (try tryAssignRecordCallFromExportMap(ctx, name, value)) return;
    if (value.* == .table) {
        if (tableIsPositional(value)) {
            try lowerPositionalTableAssign(ctx, name, value);
            return;
        }
        try lowerRecordLiteralAssign(ctx, name, value);
        return;
    }
    if (value.* == .field and value.field.obj.* == .name) {
        const src_name = value.field.obj.name.ident;
        const nested = value.field.field;
        if (opaqueRecordParam(ctx, src_name)) |src_o| {
            if (recordDescForOpaqueParam(ctx, src_o)) |rec| {
                if (recordFieldHasNestedFields(rec, nested)) {
                    try copyOpaqueToFlatPrefixedFields(ctx, name, src_o, nested);
                    return;
                }
            }
        }
    }
    const v = try lowerExprCons(ctx, value, .single);
    const f64_store = exprIsF64(ctx, value);
    const pointer_store = exprIsPointer(ctx, value);
    if (ctx.locals.get(name)) |slot| {
        // THE STORE IS WHERE THE DECLARED WIDTH APPLIES — the exact place
        // `--backend=c` writes `((uint32_t)(...))`. The declared type wins over
        // whatever the initializer's own type is, which is the same rule the
        // `bool` mark above follows for the same reason.
        const store_ty: RT = if (f64_store)
            .f64
        else
            ctx.narrow_slots.get(slot) orelse .any;
        if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, slot, {});
        if (exprIsStr(ctx, value)) try ctx.str_slots.put(ctx.alloc, slot, {});
        // Both directions. A slot REASSIGNED from a bool to an integer is no
        // longer a bool, and leaving the mark set would refuse a legal
        // interpolation for the rest of the function.
        if (exprIsBoolish(ctx, value))
            try ctx.bool_slots.put(ctx.alloc, slot, {})
        else
            _ = ctx.bool_slots.remove(slot);
        if (pointer_store)
            try ctx.ptr_slots.put(ctx.alloc, slot, {})
        else
            _ = ctx.ptr_slots.remove(slot);
        if (intLiteralStep(value)) |n| {
            const gop = try ctx.const_ints.getOrPut(ctx.alloc, name);
            if (!gop.found_existing) gop.key_ptr.* = try ctx.alloc.dupe(u8, name);
            // The COMPILE-TIME copy of the binding's value has to be the value
            // the store leaves behind, or a numeric-for step reads 300 from a
            // `u8` that holds 44 — a decision computed against one state and
            // read against another.
            gop.value_ptr.* = narrowFitConst(n, store_ty);
        }
        try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = store_ty });
        subsumeProducerRefit(ctx);
        return;
    }
    // A WRITTEN MODULE-SCOPE BINDING GOES TO ITS STORAGE, and this arm must sit
    // above the fresh-local fallback below — that fallback IS the defect. With
    // no local of this name in scope it minted one, so `total = total + i`
    // inside a function wrote a register nobody else could see, and the module's
    // other readers went on folding the initializer.
    if (ctx.module_globals.types.get(name)) |ty| {
        try ctx.emit(.{ .op = .store_global, .field = name, .lhs = v, .ty = ty });
        return;
    }
    const slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, name), slot);
    // A slot created HERE was never declared with a type, so it carries no
    // width. `.local_decl` pre-creates the slot for every narrow declaration
    // precisely so that path never reaches this one.
    const store_ty: RT = if (f64_store) .f64 else .any;
    if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, slot, {});
    if (exprIsStr(ctx, value)) try ctx.str_slots.put(ctx.alloc, slot, {});
    if (exprIsBoolish(ctx, value)) try ctx.bool_slots.put(ctx.alloc, slot, {});
    if (pointer_store) try ctx.ptr_slots.put(ctx.alloc, slot, {});
    if (intLiteralStep(value)) |n| {
        const gop = try ctx.const_ints.getOrPut(ctx.alloc, name);
        if (!gop.found_existing) gop.key_ptr.* = try ctx.alloc.dupe(u8, name);
        gop.value_ptr.* = n;
    }
    try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = store_ty });
    subsumeProducerRefit(ctx);
}

fn recordForDescriptor(
    records: []const dnir.RecordDesc,
    descriptor: types.ResolvedType,
    graph: ?*const semantic_graph.SemanticGraph,
) ?dnir.RecordDesc {
    if (descriptor == .@"struct") {
        const want = descriptor.@"struct".name;
        if (graph) |g| {
            if (richestRecordForNominal(records, g, want)) |record| return record;
        }
        if (findRecordName(records, .{ .named = want })) |record| {
            if (checkedRecordResultSupported(record)) return record;
        }
        if (findRecordByNominal(records, want, graph)) |record| return record;
        return null;
    }
    if (descriptor != .table_type) return null;
    const fields = descriptor.table_type.fields;
    for (records) |record| {
        if (record.fields.len != fields.len) continue;
        var matches = true;
        for (record.fields, record.kinds, fields) |name, kind, field| {
            if (!std.mem.eql(u8, name, field.name)) {
                matches = false;
                break;
            }
            const field_kind = tableFieldKind(field) orelse {
                matches = false;
                break;
            };
            if (field_kind != kind) {
                matches = false;
                break;
            }
        }
        if (matches and checkedRecordResultSupported(record)) return record;
    }
    for (records) |record| {
        if (recordCoversTableFields(record, fields)) return record;
    }
    return null;
}

fn recordForApplicationResult(
    ctx: *const LowerCtx,
    application: *const semantic_graph.ApplicationFact,
) ?dnir.RecordDesc {
    // Native validation keys record ABI on `applicationResultShape`. Inferring a
    // record from function return spelling alone emits `.record` without that
    // witness and dies at `validateDnirApplications` with `application-result-abi`.
    const shape = ctx.graph.applicationResultShape(application.application, 0) orelse return null;
    var best: ?dnir.RecordDesc = null;
    for (ctx.records) |record| {
        if (record.semantic_shape == shape and checkedRecordResultSupported(record)) {
            if (best == null or record.fields.len > best.?.fields.len) best = record;
        }
    }
    const shape_node = ctx.graph.tableShapeEntity(shape) orelse return best;
    const shape_name = shape_node.name orelse return best;
    if (richestRecordForNominal(ctx.records, ctx.graph, shape_name)) |record| {
        if (best == null or record.fields.len > best.?.fields.len) best = record;
    }
    return best;
}

fn checkedRecordResultSupported(record: dnir.RecordDesc) bool {
    return record.fields.len > 0 and record.fields.len <= max_record_fields;
}

/// Selected callable entity id. Semantic analysis publishes both the applied
/// value and the selected implementation. This direct realization is lawful
/// only when they coincide; relation identity remains a separate graph edge.
fn applicationTarget(
    ctx: *const LowerCtx,
    application: *const semantic_graph.ApplicationFact,
) Error!semantic_graph.id {
    const applied = ctx.graph.applicationApplied(application.application) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "missing-application-applied");
    const target = ctx.graph.applicationTarget(application.application) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "missing-application-target");
    if (applied != target) {
        return invalidGraphFacts(ctx.diagnostic, @src(), "application-applied-target");
    }
    return target;
}

fn applicationRelation(
    ctx: *const LowerCtx,
    application: *const semantic_graph.ApplicationFact,
) Error!semantic_graph.id {
    return ctx.graph.applicationRelation(application.application) orelse
        invalidGraphFacts(ctx.diagnostic, @src(), "missing-application-relation");
}

fn linkageForTarget(ctx: *LowerCtx, target: semantic_graph.id) Error![]const u8 {
    return ctx.entity_linkage.get(target) orelse
        invalidGraphFacts(ctx.diagnostic, @src(), "missing-application-target");
}



fn checkedRecordForApplication(
    ctx: *LowerCtx,
    application: *const semantic_graph.ApplicationFact,
) Error!?dnir.RecordDesc {
    return recordForApplicationResult(ctx, application);
}

fn checkedApplicationResultDescriptor(
    ctx: *const LowerCtx,
    application: *const semantic_graph.ApplicationFact,
) Error!types.ResolvedType {
    const results = ctx.graph.applicationResults(application.application) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "application-result-pack");
    if (results.len != 1) return invalidGraphFacts(ctx.diagnostic, @src(), "application-result-pack");
    const result_node = ctx.graph.get(results[0]) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "application-result-member");
    return result_node.descriptor orelse
        invalidGraphFacts(ctx.diagnostic, @src(), "application-result-descriptor");
}

fn lowerCheckedRecordCall(
    ctx: *LowerCtx,
    application: *const semantic_graph.ApplicationFact,
    record: dnir.RecordDesc,
    consumption: types.ReturnConsumption,
) Error!dnir.Value {
    bindOccurrence(ctx.diagnostic, ctx.graph, application.application);
    const relation = try applicationRelation(ctx, application);
    const target = try applicationTarget(ctx, application);
    const callee = try linkageForTarget(ctx, target);
    if (ctx.graph.foreignHome(target)) |foreign_home| {
        try ensureExtern(ctx, foreign_home, callee, callee);
    }
    const result = try checkedApplicationResult(ctx, application);
    var operand_storage: [max_direct_scalar_args]CheckedScalarOperand = undefined;
    const operands = try checkedScalarOperands(ctx, application, &operand_storage, true);
    var values: [max_direct_scalar_args]dnir.Value = undefined;
    const staged = try evaluateCheckedScalarOperands(ctx, operands, &values);
    const realization_start: u32 = @intCast(ctx.instrs.items.len);
    const stage_n = boundedOperandStageCount(staged, operands);
    try stageCheckedScalarOperands(ctx, operands[0..stage_n], values[0..stage_n]);
    const descriptor = try publishedDescriptor(ctx, application);
    if (consumption == .discard) {
        try ctx.emit(.{
            .op = .call_direct,
            .relation = relation,
            .application = application.application,
            .value = result,
            .subject = ctx.graph.applicationSubject(application.application),
            .target = target,
            .realization_start = realization_start,
            .callee = callee,
            .record = record.name,
            .field = "",
            .ty = descriptor,
        });
        return .void;
    }
    const rec_slot = ctx.freshTemp();
    const anon = try std.fmt.allocPrint(ctx.alloc, "__rec{d}", .{rec_slot});
    defer ctx.alloc.free(anon);
    try ctx.emit(.{
        .op = .call_direct,
        .relation = relation,
        .application = application.application,
        .value = result,
        .subject = ctx.graph.applicationSubject(application.application),
        .target = target,
        .realization_start = realization_start,
        .result = rec_slot,
        .callee = callee,
        .record = record.name,
        .field = anon,
        .ty = descriptor,
    });
    try ctx.emit(.{ .op = .init_record, .result = rec_slot, .record = record.name, .field = anon });
    for (record.fields, 0..) |fname, fi| {
        const fk = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ anon, fname });
        defer ctx.alloc.free(fk);
        if (ctx.locals.contains(fk)) continue;
        const fslot = ctx.freshTemp();
        try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, fk), fslot);
        if (fi < record.kinds.len) switch (record.kinds[fi]) {
            .str => try ctx.str_slots.put(ctx.alloc, fslot, {}),
            .f64 => try ctx.f64_slots.put(ctx.alloc, fslot, {}),
            .i64 => {},
        };
    }
    return .{ .temp = rec_slot };
}


fn boundedOperandStageCount(staged: StagedOperands, operands: []const CheckedScalarOperand) usize {
    return @min(staged.count, operands.len);
}

fn ensureRecordLocalFieldSlots(ctx: *LowerCtx, name: []const u8, record: dnir.RecordDesc) Error!void {
    for (record.fields, 0..) |fname, fi| {
        const fk = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ name, fname });
        defer ctx.alloc.free(fk);
        if (ctx.locals.contains(fk)) continue;
        const fslot = ctx.freshTemp();
        try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, fk), fslot);
        if (fi < record.kinds.len) switch (record.kinds[fi]) {
            .str => try ctx.str_slots.put(ctx.alloc, fslot, {}),
            .f64 => try ctx.f64_slots.put(ctx.alloc, fslot, {}),
            .i64 => {},
        };
        if (fi < record.widths.len) if (record.widths[fi]) |width| {
            try ctx.narrow_slots.put(ctx.alloc, fslot, width);
        };
    }
}

fn emitRecordFieldLoadsFromBase(
    ctx: *LowerCtx,
    prefix: []const u8,
    record: dnir.RecordDesc,
    base: dnir.Value,
) Error!void {
    _ = base;
    for (record.fields, record.kinds, 0..) |fname, kind, fi| {
        const fk = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ prefix, fname });
        defer ctx.alloc.free(fk);
        const fslot = ctx.locals.get(fk) orelse continue;
        const rt: RT = switch (kind) {
            .f64 => .f64,
            .str => .str,
            .i64 => .any,
        };
        const t = ctx.freshTemp();
        try ctx.emit(.{
            .op = .load_field,
            .result = t,
            .req_alias = try ctx.alloc.dupe(u8, prefix),
            .record = record.name,
            .field = try ctx.alloc.dupe(u8, fname),
            .ty = rt,
        });
        try ctx.emit(.{
            .op = .store_local,
            .result = fslot,
            .lhs = .{ .temp = t },
            .record = record.name,
            .field = fname,
            .ty = rt,
        });
        if (rt == .f64) try ctx.f64_slots.put(ctx.alloc, fslot, {});
        if (rt == .str) try ctx.str_slots.put(ctx.alloc, fslot, {});
        if (fi < record.widths.len) if (record.widths[fi]) |width| {
            try ctx.narrow_slots.put(ctx.alloc, fslot, width);
        };
    }
}

fn nestedRecordPrefixHasLocals(ctx: *const LowerCtx, prefix: []const u8) bool {
    var buf: [256]u8 = undefined;
    const pat = std.fmt.bufPrint(&buf, "{s}.", .{prefix}) catch return false;
    var it = ctx.locals.keyIterator();
    while (it.next()) |key| {
        if (std.mem.startsWith(u8, key.*, pat)) return true;
    }
    return false;
}

fn lowerCheckedRecordCallAssign(
    ctx: *LowerCtx,
    name: []const u8,
    application: *const semantic_graph.ApplicationFact,
    record: dnir.RecordDesc,
    _call_value: *const Expr,
) Error!void {
    _ = _call_value;
    bindOccurrence(ctx.diagnostic, ctx.graph, application.application);
    const relation = try applicationRelation(ctx, application);
    const target = try applicationTarget(ctx, application);
    const callee = try linkageForTarget(ctx, target);
    if (ctx.graph.foreignHome(target)) |foreign_home| {
        try ensureExtern(ctx, foreign_home, callee, callee);
    }
    const result = try checkedApplicationResult(ctx, application);
    const rec_slot = if (ctx.locals.get(name)) |existing| existing else blk: {
        const slot = ctx.freshTemp();
        try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, name), slot);
        break :blk slot;
    };
    var operand_storage: [max_direct_scalar_args]CheckedScalarOperand = undefined;
    // Graph projection subject is the assignee, not a callee operand.
    const operands = try checkedScalarOperands(ctx, application, &operand_storage, false);
    var values: [max_direct_scalar_args]dnir.Value = undefined;
    const staged = try evaluateCheckedScalarOperands(ctx, operands, &values);
    const realization_start: u32 = @intCast(ctx.instrs.items.len);
    const stage_n = boundedOperandStageCount(staged, operands);
    try stageCheckedScalarOperands(ctx, operands[0..stage_n], values[0..stage_n]);
    const descriptor = try publishedDescriptor(ctx, application);
    const emit_record = physicalRecordName(ctx, record);
    try ctx.emit(.{
        .op = .call_direct,
        .relation = relation,
        .application = application.application,
        .value = result,
        .subject = ctx.graph.applicationSubject(application.application),
        .target = target,
        .realization_start = realization_start,
        .callee = callee,
        .record = emit_record,
        .field = name,
        .ty = descriptor,
    });
    try ctx.emit(.{ .op = .init_record, .result = rec_slot, .record = emit_record, .field = name });
    try ctx.param_record_types.put(ctx.alloc, try ctx.alloc.dupe(u8, name), emit_record);
    try ensureRecordLocalFieldSlots(ctx, name, record);
    try emitRecordFieldLoadsFromBase(ctx, name, record, .{ .local = rec_slot });
}

fn lowerRecordCallAssign(ctx: *LowerCtx, name: []const u8, callee: []const u8, args: []const *ast.Expr, rec_name: []const u8) Error!void {
    // Marshal through scalarCallLhs like every other call path. Lowering only
    // `args[0]` meant a record-returning call silently dropped every later
    // argument: `scan_one(src, pos)` reached the callee with `pos` never
    // written, so it read whatever the caller happened to leave in x1.
    const arg0 = try scalarCallLhs(ctx, args, callee);
    try ctx.emit(.{ .op = .call_direct, .callee = callee, .lhs = arg0, .record = rec_name, .field = name });
    const rec_slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, name), rec_slot);
    try ctx.emit(.{ .op = .init_record, .result = rec_slot, .record = rec_name, .field = name });
    try ctx.param_record_types.put(ctx.alloc, try ctx.alloc.dupe(u8, name), rec_name);
}

fn tryAssignRecordCallFromExportMap(ctx: *LowerCtx, name: []const u8, value: *const ast.Expr) Error!bool {
    if (ctx.require_graph_facts) return false;
    const export_name = try qualifiedExportNameFromExpr(ctx.alloc, value) orelse return false;
    defer ctx.alloc.free(export_name);
    const rec_name = ctx.func_record_returns.get(export_name) orelse return false;
    const args = switch (value.*) {
        .call => |c| c.args,
        .method_call => |m| m.args,
        else => return false,
    };
    try lowerRecordCallAssign(ctx, name, export_name, args, rec_name);
    return true;
}

// ---------------------------------------------------------------------------
// REPRESENTATION IS A DECISION, AND SIZE IS NOT THE FACT THAT DECIDES IT.
//
// `select_chain_max` used to be the whole decision, and it produced a 43x cliff
// between two programs that differ only in how many literals were written:
//
//     t = (1 … 32) ; t(2)   ->    4 instructions
//     t = (1 … 33) ; t(2)   ->  174 instructions      same answer, the literal 2
//
// Both answers were fully determined before the program ran — constant contents,
// constant index, no writes, no escape — and one of them was computed at run time
// out of frame memory anyway. Extent is a fact about how to REALIZE a table that
// must exist; it says nothing about whether one must exist at all. That question
// is answered below, from the uses, and its answer holds at every extent.
//
// What is asked here is deliberately narrow and entirely local: does the rest of
// this function ever do anything to this name other than read it at a
// compile-time index? Anything else at all — a write, a bare mention, an
// unrecognized construct — declines. Declining costs speed; being wrong costs the
// answer, and this tree has already paid that twice (materialization re-run per
// loop iteration, and two representations live in one function). So the walker
// below has NO permissive default: an expression kind it does not model returns
// `.opaque_use` whether or not it mentions the name.
// ---------------------------------------------------------------------------

/// How a function body uses one bound name, worst case. Ordered: a later variant
/// subsumes an earlier one.
const TableUse = enum {
    /// Never mentioned after the binding.
    none,
    /// Only ever `t(k)` with `k` a compile-time integer.
    const_read,
    /// Also read at an index only known at run time.
    dyn_read,
    /// Written, rebound, shadowed, passed on, or used in a shape not modeled
    /// here. NOTHING may be assumed about the table.
    opaque_use,
};

fn worseUse(a: TableUse, b: TableUse) TableUse {
    return if (@intFromEnum(b) > @intFromEnum(a)) b else a;
}

/// `k` as a compile-time integer, for an index expression. Literals only — a
/// name resolved through `const_ints` is NOT accepted, because that map records
/// a name's last literal binding and is never invalidated by a later
/// non-literal assignment, so it would answer for a variable that has since
/// moved. A wrong element is a wrong answer that still compiles.
fn constIndexOf(key: *const ast.Expr) ?i64 {
    return intLiteralStep(key);
}

fn tableUseInExpr(expr: *const ast.Expr, name: []const u8) TableUse {
    return switch (expr.*) {
        .nil, .true_lit, .false_lit, .int_lit, .float_lit, .quoted, .vararg => .none,
        .semantic, .semantic_scope => .none,
        .name => |n| if (std.mem.eql(u8, n.ident, name)) .opaque_use else .none,
        .index => |ix| blk: {
            // The READ face. `t(k)` and `t[k]` are the same node by the time
            // lowering sees them (`table_apply.zig` canonicalizes the call form),
            // so this one arm covers both spellings.
            const in_key = tableUseInExpr(ix.key, name);
            if (ix.obj.* == .name and std.mem.eql(u8, ix.obj.name.ident, name)) {
                const here: TableUse = if (constIndexOf(ix.key) != null) .const_read else .dyn_read;
                break :blk worseUse(here, in_key);
            }
            break :blk worseUse(tableUseInExpr(ix.obj, name), in_key);
        },
        .field => |f| tableUseInExpr(f.obj, name),
        .call => |c| blk: {
            var u = tableUseInExpr(c.func, name);
            for (c.args) |a| u = worseUse(u, tableUseInExpr(a, name));
            break :blk u;
        },
        .method_call => |m| blk: {
            // COLLECTION-RELATION-ONE. `xs:any(p)` is NOT an opaque mention of
            // `xs`: it reads each element at a FIXED position, writes none,
            // rebinds nothing and lets nothing escape — which is exactly the
            // `const_read` verdict `t(1)`, `t(2)`, … would earn written out.
            //
            // WITHOUT THIS ARM THE STRONGER RELATION IS THE SLOWER ONE.
            // Measured before it existed: the flag-and-scan loop this relation
            // replaces folded to **2 instructions** while `xs:any(…)` emitted
            // **65**, because the bare receiver read as `.opaque_use` and
            // materialized all six elements into registers. That is HPLS §2
            // exactly — a true fact making the best realization worse — and
            // §3's negative abstraction tax says the richer form owes the
            // cheaper code, not the same code.
            if (collection_relation.shapeOf(expr)) |shape| {
                if (shape.subject.* == .name and
                    std.mem.eql(u8, shape.subject.name.ident, name))
                {
                    break :blk worseUse(.const_read, tableUseInExpr(shape.body, name));
                }
            }
            var u = tableUseInExpr(m.obj, name);
            for (m.args) |a| u = worseUse(u, tableUseInExpr(a, name));
            break :blk u;
        },
        .binop => |b| worseUse(tableUseInExpr(b.lhs, name), tableUseInExpr(b.rhs, name)),
        .unop => |u| tableUseInExpr(u.operand, name),
        .try_expr => |x| tableUseInExpr(x.operand, name),
        .unwrap_expr => |x| tableUseInExpr(x.operand, name),
        .await_expr => |x| tableUseInExpr(x.operand, name),
        .quote => |q| tableUseInExpr(q.expr, name),
        .unquote => |q| tableUseInExpr(q.expr, name),
        .contains_expr => |c| worseUse(tableUseInExpr(c.lhs, name), tableUseInExpr(c.rhs, name)),
        .if_expr => |ie| worseUse(
            tableUseInExpr(ie.cond, name),
            worseUse(tableUseInExpr(ie.then_expr, name), tableUseInExpr(ie.else_expr, name)),
        ),
        .sequence => |s| blk: {
            var u: TableUse = .none;
            for (s.exprs) |e| u = worseUse(u, tableUseInExpr(e, name));
            break :blk u;
        },
        .range => |r| blk: {
            var u = worseUse(tableUseInExpr(r.start, name), tableUseInExpr(r.end, name));
            if (r.step) |st| u = worseUse(u, tableUseInExpr(st, name));
            break :blk u;
        },
        .macro_call => |mc| blk: {
            var u: TableUse = .none;
            for (mc.args) |a| u = worseUse(u, tableUseInExpr(a, name));
            break :blk u;
        },
        .table => |t| blk: {
            var u: TableUse = .none;
            for (t.fields) |fld| {
                u = worseUse(u, switch (fld) {
                    .positional => |v| tableUseInExpr(v, name),
                    .named => |nf| tableUseInExpr(nf.val, name),
                    .semantic => |sf| tableUseInExpr(sf.val, name),
                    .spread => |sp| tableUseInExpr(sp, name),
                    .indexed => |ix| worseUse(tableUseInExpr(ix.key, name), tableUseInExpr(ix.val, name)),
                });
            }
            break :blk u;
        },
        .match_expr => |m| blk: {
            var u = tableUseInExpr(m.scrutinee, name);
            for (m.arms) |arm| {
                if (arm.guard) |g| u = worseUse(u, tableUseInExpr(g, name));
                // A pattern that BINDS this name shadows the table from here on.
                if (patternBinds(arm.pattern, name)) break :blk .opaque_use;
                u = worseUse(u, tableUseInBlock(&arm.body, name, m.scrutinee));
            }
            break :blk u;
        },
        // `func_expr` and `list_comp` introduce their own scope and their own
        // capture rules. Neither is modeled, so neither is assumed about.
        .func_expr, .list_comp => .opaque_use,
    };
}

fn patternBinds(pat: ast.Pattern, name: []const u8) bool {
    return switch (pat) {
        .binding => |b| std.mem.eql(u8, b.name, name),
        .rest => |r| std.mem.eql(u8, r, name),
        .variant => |v| blk: {
            const payload = v.payload orelse break :blk false;
            for (payload) |p| if (patternBinds(p, name)) break :blk true;
            break :blk false;
        },
        .table_destr => |entries| blk: {
            for (entries) |e| if (patternBinds(e.pat, name)) break :blk true;
            break :blk false;
        },
        .array_destr => |pats| blk: {
            for (pats) |p| if (patternBinds(p, name)) break :blk true;
            break :blk false;
        },
        .literal, .wildcard => false,
    };
}

/// An assignment TARGET naming this table is a WRITE, whatever its shape:
/// `t = …` rebinds it and `t(k) = …` mutates it. Either way the initializer's
/// literals stop being the whole truth.
fn targetWrites(target: *const ast.Expr, name: []const u8) bool {
    return switch (target.*) {
        .name => |n| std.mem.eql(u8, n.ident, name),
        .index => |ix| targetWrites(ix.obj, name),
        .field => |f| targetWrites(f.obj, name),
        else => true,
    };
}

/// `bound` is the initializer expression of the binding being judged. That one
/// occurrence is THE binding and is not a use of it; every other binding of the
/// same name — a second declaration, a reassignment, a loop variable, a pattern
/// capture — replaces the table and is `.opaque_use`. Identity is by POINTER,
/// not by name, so "the binding" cannot be confused with a later one.
fn tableUseInBlock(block: *const ast.Block, name: []const u8, bound: *const ast.Expr) TableUse {
    var u: TableUse = .none;
    for (block.stmts) |*s| {
        u = worseUse(u, tableUseInStmt(s, name, bound));
        if (u == .opaque_use) return u;
    }
    if (block.tail_expr) |t| u = worseUse(u, tableUseInExpr(t, name));
    return u;
}

/// Uses contributed by a name/value binding pair. `.none` for the one pair that
/// IS this binding; `.opaque_use` for any other pair that binds the name.
fn bindingPairUse(
    n: []const u8,
    init: ?*const ast.Expr,
    name: []const u8,
    bound: *const ast.Expr,
) TableUse {
    const init_use: TableUse = if (init) |e| tableUseInExpr(e, name) else .none;
    if (!std.mem.eql(u8, n, name)) return init_use;
    if (init) |e| if (e == bound) return .none;
    return .opaque_use;
}

fn tableUseInStmt(stmt: *const ast.Stmt, name: []const u8, bound: *const ast.Expr) TableUse {
    return switch (stmt.*) {
        .local_decl => |d| blk: {
            var u: TableUse = .none;
            for (d.names, 0..) |n, i| {
                const init: ?*const ast.Expr = if (i < d.inits.len) d.inits[i] else null;
                u = worseUse(u, bindingPairUse(n.ident, init, name, bound));
            }
            // An initializer with no name of its own is still evaluated.
            if (d.inits.len > d.names.len) {
                for (d.inits[d.names.len..]) |e| u = worseUse(u, tableUseInExpr(e, name));
            }
            break :blk u;
        },
        .const_decl => |d| blk: {
            if (std.mem.eql(u8, d.ident, name)) break :blk .opaque_use;
            break :blk tableUseInExpr(d.val, name);
        },
        .global_decl => |d| blk: {
            var u: TableUse = .none;
            for (d.names, 0..) |n, i| {
                const init: ?*const ast.Expr = if (i < d.inits.len) d.inits[i] else null;
                u = worseUse(u, bindingPairUse(n.ident, init, name, bound));
            }
            if (d.inits.len > d.names.len) {
                for (d.inits[d.names.len..]) |e| u = worseUse(u, tableUseInExpr(e, name));
            }
            break :blk u;
        },
        .assign => |a| blk: {
            var u: TableUse = .none;
            for (a.targets, 0..) |t, i| {
                const val: ?*const ast.Expr = if (i < a.values.len) a.values[i] else null;
                if (t.* == .name) {
                    u = worseUse(u, bindingPairUse(t.name.ident, val, name, bound));
                    continue;
                }
                // `t(k) = …` / `t.f = …` mutate the table in place.
                if (targetWrites(t, name)) break :blk .opaque_use;
                u = worseUse(u, tableUseInExpr(t, name));
                if (val) |v| u = worseUse(u, tableUseInExpr(v, name));
            }
            if (a.values.len > a.targets.len) {
                for (a.values[a.targets.len..]) |e| u = worseUse(u, tableUseInExpr(e, name));
            }
            break :blk u;
        },
        .call_stmt => |c| tableUseInExpr(c.expr, name),
        .expr_stmt => |c| tableUseInExpr(c.expr, name),
        .do_block => |d| tableUseInBlock(&d.body, name, bound),
        .while_loop => |w| worseUse(tableUseInExpr(w.cond, name), tableUseInBlock(&w.body, name, bound)),
        .repeat_loop => |r| worseUse(tableUseInBlock(&r.body, name, bound), tableUseInExpr(r.cond, name)),
        .if_stmt => |f| blk: {
            var u: TableUse = .none;
            if (f.binding) |b| {
                if (std.mem.eql(u8, b.name, name)) break :blk .opaque_use;
                u = worseUse(u, tableUseInExpr(b.expr, name));
            }
            u = worseUse(u, tableUseInExpr(f.cond, name));
            u = worseUse(u, tableUseInBlock(&f.then, name, bound));
            for (f.elseifs) |ei| {
                u = worseUse(u, tableUseInExpr(ei.cond, name));
                u = worseUse(u, tableUseInBlock(&ei.body, name, bound));
            }
            if (f.else_body) |eb| u = worseUse(u, tableUseInBlock(&eb, name, bound));
            break :blk u;
        },
        .num_for => |n| blk: {
            if (std.mem.eql(u8, n.var_name, name)) break :blk .opaque_use;
            var u = worseUse(tableUseInExpr(n.start, name), tableUseInExpr(n.stop, name));
            if (n.step) |st| u = worseUse(u, tableUseInExpr(st, name));
            break :blk worseUse(u, tableUseInBlock(&n.body, name, bound));
        },
        .gen_for => |g| blk: {
            for (g.vars) |v| if (std.mem.eql(u8, v, name)) break :blk .opaque_use;
            var u: TableUse = .none;
            for (g.iters) |e| u = worseUse(u, tableUseInExpr(e, name));
            break :blk worseUse(u, tableUseInBlock(&g.body, name, bound));
        },
        .ret => |r| blk: {
            var u: TableUse = .none;
            for (r.vals) |e| u = worseUse(u, tableUseInExpr(e, name));
            break :blk u;
        },
        .brk, .cont, .goto_stmt, .label_stmt => .none,
        // Same rule as the expression walker: an unmodeled statement is not
        // evidence of absence.
        else => .opaque_use,
    };
}

/// Every element as a compile-time integer, or null.
///
/// Integers only. A float table would need the same treatment on the f64 side,
/// and a `.f64` slot and an `.i64` immediate are different representations —
/// mixing them is exactly the confusion that produced this tree's other
/// wrong-answer regression, so the float case is DECLINED here rather than
/// approximated.
fn constTableValues(ctx: *LowerCtx, table: *const ast.Expr) Error!?[]i64 {
    if (table.* != .table) return null;
    var n: usize = 0;
    for (table.table.fields) |fld| {
        if (fld != .positional) return null;
        if (intLiteralStep(fld.positional) == null) return null;
        n += 1;
    }
    if (n == 0) return null;
    const out = try ctx.alloc.alloc(i64, n);
    var i: usize = 0;
    for (table.table.fields) |fld| {
        out[i] = intLiteralStep(fld.positional).?;
        i += 1;
    }
    return out;
}

/// Decide, AT THE BINDING, what is known about `name`, and record it.
///
/// Returns the use verdict so the caller can also decide whether to emit any
/// storage at all. The decision is taken here and nowhere else: an access site
/// is routinely inside a loop, and a representation chosen there re-runs its
/// setup per iteration — which is how a previous attempt at this silently
/// restored tables to their initial values every trip.
fn noteConstTable(ctx: *LowerCtx, name: []const u8, table: *const ast.Expr) Error!TableUse {
    const body = ctx.body orelse return .opaque_use;
    const use = tableUseInBlock(body, name, table);
    if (use == .opaque_use) return use;
    const values = (try constTableValues(ctx, table)) orelse return .opaque_use;
    errdefer ctx.alloc.free(values);
    // A name bound twice in one body is `.opaque_use` above, so this cannot
    // overwrite a live entry.
    const key = try ctx.alloc.dupe(u8, name);
    errdefer ctx.alloc.free(key);
    try ctx.const_tables.put(ctx.alloc, key, values);
    return use;
}

/// `t(k)` where `t` was proved determined and `k` is compile-time — the element,
/// as an immediate, at any extent.
///
/// A constant index OUTSIDE the extent returns an error rather than a value.
/// Tables are 1-indexed, so `t(0)` is out of range as surely as `t(len + 1)` is,
/// and both are refused at compile time. That refusal is not new — a
/// register-exploded table already refused it by failing to find the element's
/// local — but it now holds at every width, where the memory-backed path used to
/// emit an unguarded load of whatever lay next to the region.
fn constTableRead(ctx: *LowerCtx, expr: *const ast.Expr) Error!?dnir.Value {
    if (expr.* != .index) return null;
    const ix = expr.index;
    if (ix.obj.* != .name) return null;
    const values = ctx.const_tables.get(ix.obj.name.ident) orelse return null;
    const k = constIndexOf(ix.key) orelse return null;
    if (k < 1 or k > @as(i64, @intCast(values.len))) return bail(ctx.diagnostic, @src());
    return dnir.Value{ .i64 = values[@intCast(k - 1)] };
}

/// Bind `t.len`. The length of a positional table is static in every
/// realization, so it is a foldable constant whichever way the elements go —
/// including the realization that emits no elements.
fn bindTableLen(ctx: *LowerCtx, name: []const u8, len: i64) Error!void {
    const len_key = try std.fmt.allocPrint(ctx.alloc, "{s}.len", .{name});
    const len_slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, len_key, len_slot);
    try ctx.emit(.{ .op = .store_local, .result = len_slot, .lhs = .{ .i64 = len }, .ty = .any });
    try ctx.table_lens.put(ctx.alloc, len_slot, len);
}

/// Record `name` as a table whose every element is text.
///
/// The verdict is taken AT THE BINDING for the same reason `noteConstTable`'s
/// is: a read site is routinely inside a loop, and the answer must not depend
/// on which of the three storage paths the binding chose. `tableUseInBlock`
/// supplies the safety — a table that is written, rebound, shadowed or passed
/// on is `.opaque_use`, and nothing may be assumed about what a later read of
/// it holds.
fn noteStrTable(ctx: *LowerCtx, name: []const u8, table: *const ast.Expr) Error!void {
    const body = ctx.body orelse return;
    if (table.* != .table or table.table.fields.len == 0) return;
    for (table.table.fields) |fld| {
        if (fld != .positional) return;
        if (!exprIsStr(ctx, fld.positional)) return;
    }
    if (@intFromEnum(tableUseInBlock(body, name, table)) > @intFromEnum(TableUse.dyn_read)) return;
    const key = try ctx.alloc.dupe(u8, name);
    errdefer ctx.alloc.free(key);
    try ctx.str_tables.put(ctx.alloc, key, {});
}

/// `t = { 10, 20, 30 }` — a positional table with a statically known length.
///
/// Elements become one local per slot, keyed `t.1`, `t.2`, … exactly as record
/// fields are. That makes constant indexing (`t[2]`) a compile-time slot lookup
/// with no memory traffic at all — the element lives in a register.
///
/// Dynamic indexing (`t[i]`) is deliberately NOT handled here: it needs a real
/// base pointer and a computed offset, which is the native table-lowering
/// milestone. Constant indexing is the slice that fits the proven subset today.
fn lowerPositionalTableAssign(ctx: *LowerCtx, name: []const u8, table: *const ast.Expr) Error!void {
    if (table.* != .table) return bail(ctx.diagnostic, @src());
    try noteStrTable(ctx, name, table);
    const use = try noteConstTable(ctx, name, table);
    if (@intFromEnum(use) <= @intFromEnum(TableUse.const_read)) {
        // DETERMINED, and read only at compile-time indices: the table itself is
        // not a thing this function needs. Bind the length (still a foldable
        // constant, so `#t` costs nothing) and emit no elements at all — every
        // read is answered by `constTableRead`. This is the branch that makes the
        // width irrelevant, because it is taken at 4 elements and at 4096.
        try bindTableLen(ctx, name, @intCast(ctx.const_tables.get(name).?.len));
        return;
    }
    if (ctx.tables_in_memory) return lowerPositionalTableIntoMemory(ctx, name, table);
    const t_slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, name), t_slot);
    var idx: usize = 1;
    for (table.table.fields) |fld| {
        const val = switch (fld) {
            .positional => |v| v,
            else => return bail(ctx.diagnostic, @src()),
        };
        const v = try lowerExpr(ctx, val);
        const eslot = ctx.freshTemp();
        const key = try std.fmt.allocPrint(ctx.alloc, "{s}.{d}", .{ name, idx });
        try ctx.locals.put(ctx.alloc, key, eslot);
        const store_ty: RT = if (exprIsF64(ctx, val)) .f64 else .any;
        if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, eslot, {});
        try ctx.emit(.{ .op = .store_local, .result = eslot, .lhs = v, .ty = store_ty });
        idx += 1;
    }
    // Length as a foldable constant, so `#t` can resolve without memory.
    const len_key = try std.fmt.allocPrint(ctx.alloc, "{s}.len", .{name});
    const len_slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, len_key, len_slot);
    try ctx.emit(.{ .op = .store_local, .result = len_slot, .lhs = .{ .i64 = @intCast(idx - 1) }, .ty = .any });
    try ctx.table_lens.put(ctx.alloc, len_slot, @intCast(idx - 1));

    // Wider than the select chain pays for: move it to frame memory NOW, at the
    // binding, so every access lowers to one scaled load/store.
    //
    // It has to happen here rather than at the first dynamic access, because
    // materialization emits `alloc_slots` plus a copy from the element
    // registers, and an access site is routinely inside a loop — emitting it
    // there re-runs the copy every iteration and silently restores the table to
    // its initial value, discarding all prior writes. That is exactly what a
    // first attempt did: orders 17+ stopped bailing and started returning wrong
    // answers. The binding executes once, so this placement cannot.
}

/// The same binding, built straight into frame memory.
///
/// Going through the element registers first and copying afterwards (what
/// `materializeTableSlots` does for a table that only later turns out to need a
/// base pointer) costs one live register per element. At the widths this path
/// exists to serve that is hundreds of them, and the backend correctly refused
/// with DNB003 register pressure. Here the element value is stored to its slot
/// and dropped, so a table of any width costs a constant number of registers.
fn lowerPositionalTableIntoMemory(ctx: *LowerCtx, name: []const u8, table: *const ast.Expr) Error!void {
    var len: i64 = 0;
    for (table.table.fields) |fld| {
        if (fld != .positional) return bail(ctx.diagnostic, @src());
        len += 1;
    }
    if (len <= 0 or len > 4096) return bail(ctx.diagnostic, @src());

    const base = ctx.freshTemp();
    try ctx.emit(.{ .op = .alloc_slots, .result = base, .lhs = .{ .i64 = len } });

    var i: i64 = 1;
    for (table.table.fields) |fld| {
        const v = try lowerExpr(ctx, fld.positional);
        try ctx.emit(.{
            .op = .store_index,
            .ty = .i64,
            .lhs = .{ .temp = base },
            .rhs = .{ .i64 = i },
            .third = v,
        });
        i += 1;
    }

    // Bound after the initializers, so an element expression naming the table
    // resolves to whatever it meant before this binding rather than to the
    // half-filled region being built here.
    try ctx.ptr_slots.put(ctx.alloc, base, {});
    try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, name), base);

    // `#t` still folds to a constant; the length never needs memory.
    const len_key = try std.fmt.allocPrint(ctx.alloc, "{s}.len", .{name});
    const len_slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, len_key, len_slot);
    try ctx.emit(.{ .op = .store_local, .result = len_slot, .lhs = .{ .i64 = len }, .ty = .any });
    try ctx.table_lens.put(ctx.alloc, len_slot, len);
}

/// gap[063] — `abort()` when a dynamic index leaves a register-exploded table's
/// range, instead of silently doing nothing.
///
/// A positional table lowered to registers has a FIXED capacity; an Idol table
/// GROWS. The select-chain below matched no slot for an out-of-range index and
/// simply fell through, so `t = { 0 }` followed by `t[i] = i` for i in 1..3 kept
/// only the first write and the program printed 1 where the C oracle printed 6 —
/// a wrong answer, reported as `ok compile`, exit 0. Nine ordinary lines.
///
/// The trap does not make the program work; it makes the limit OBSERVABLE. A
/// program that stays inside the capacity — every fixture that motivated the
/// select-chain does — never reaches it, and pays two compares. The real repair
/// is a growable native table, which is a representation change, not a patch
/// here; until then the choice is between a loud stop and a quiet lie.
///
/// Emitted for the STORE and for the dynamic READ, because the read has the same
/// defect from the other side: an out-of-range read answered 0 where the table
/// has no such element at all.
/// `test:assert(cond, msg)` and `test:equal(a, b, msg)` — the test world's
/// relations, lowered to a real trap.
///
/// An assertion that only type-checks is not an assertion. These become a
/// branch and an `abort`, the same shape the index bounds trap already uses, so
/// a failing assertion stops the process rather than being decoration. The
/// message operand is checked for arity and is not otherwise realized here —
/// there is no output channel in this subset to carry it.
fn lowerTestRelation(ctx: *LowerCtx, method: []const u8, args: []const *const ast.Expr) Error!?dnir.Value {
    const cond: dnir.Value = blk: {
        if (std.mem.eql(u8, method, "assert")) {
            if (args.len < 1) return bail(ctx.diagnostic, @src());
            break :blk try lowerExpr(ctx, args[0]);
        }
        if (std.mem.eql(u8, method, "refute")) {
            if (args.len < 1) return bail(ctx.diagnostic, @src());
            const v = try lowerExpr(ctx, args[0]);
            const t = ctx.freshTemp();
            try ctx.emit(.{ .op = .binop, .result = t, .binop = .eq, .lhs = v, .rhs = .{ .i64 = 0 } });
            break :blk .{ .temp = t };
        }
        if (std.mem.eql(u8, method, "equal") or std.mem.eql(u8, method, "differs")) {
            if (args.len < 2) return bail(ctx.diagnostic, @src());
            const a = try lowerExpr(ctx, args[0]);
            const b = try lowerExpr(ctx, args[1]);
            const t = ctx.freshTemp();
            const op: dnir.BinOpTag = if (std.mem.eql(u8, method, "equal")) .eq else .neq;
            try ctx.emit(.{ .op = .binop, .result = t, .binop = op, .lhs = a, .rhs = b });
            break :blk .{ .temp = t };
        }
        return null;
    };
    try ensureExtern(ctx, "os", "abort", "abort");
    const bad = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br, .lhs = cond, .branch_target = 0, .branch_condition = .when_false });
    const skip = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br, .branch_target = 0 });
    const trap: u32 = @intCast(ctx.instrs.items.len);
    ctx.instrs.items[bad].branch_target = trap;
    try ctx.emit(.{ .op = .call_extern, .callee = "abort" });
    ctx.instrs.items[skip].branch_target = @intCast(ctx.instrs.items.len);
    return .void;
}

/// Marks a DNIR `hw_unary` as a TERMINATING TRAP rather than a scalar bit
/// intrinsic. `native_backend.zig` reads the same constant and expands it to an
/// inline instruction sequence that raises SIGABRT.
///
/// TRAP, DON'T CALL. This used to be `call_extern abort`, and the cost of that
/// was not the two words at the trap site — it was everything the word CALL
/// means to the rest of the backend:
///
///   1. `dnirFunctionHasCall` counts `call_extern`, so a never-taken bounds
///      check made the whole function "a function with a call".
///   2. `gate_spill_all_locals = body_has_call`, so EVERY local lost its
///      register home and became a stack slot reloaded per use.
///   3. `dnirNeedsCalleeSave` followed, dragging in the full x19–x28
///      save/restore block a leaf never needs.
///   4. `spill_reserve` opened an unconditional ~8 KB stack pit.
///   5. The `bl` itself needed `emitSaveCallerRegs` around it — nine stores and
///      nine loads guarding registers across a call that never returns.
///
/// Measured on `s += t(i)` over an eight-element table: 142 instructions, one
/// dynamic import, against 2 for the same loop with no table at all.
///
/// A trap is not a call. It does not return, so nothing needs preserving across
/// it; it does not use x30, so nothing needs a frame; and it resolves no symbol,
/// so the artifact keeps no import. The four gates above all key off
/// `call_extern` and none of them fire.
///
/// It rides `hw_unary` + `.field` because a trap is not expressible in
/// `native_ir.zig`'s `Op` set and that file is not this pass's to change. The
/// convention is not invented here: `mov_arg` already discriminates its
/// variadic-tail form with `.field = "vararg"`, and the vector reduction above
/// uses the same seam. `.hw` stays `.none`, so `intrinsicOfOp`,
/// `functionHardwareTier` and `moduleHardwareTier` all read exactly what they
/// read before — a trap is not a hardware intrinsic and must not raise a
/// module's reported tier. `.result` is null, so `definition` establishes no
/// slot, which is right: control never leaves this instruction.
pub const trap_abort_tag = "trap.abort";

/// The one place a trap is emitted. Both trap sites — the index bounds check and
/// a failed `test:assert` — mean the same thing (stop the process, do not
/// return), so they emit the same instruction rather than two spellings of it.
fn emitTrap(ctx: *LowerCtx) Error!void {
    try ctx.emit(.{ .op = .hw_unary, .hw = .none, .field = trap_abort_tag });
}

/// Static element count of a positional table bound in this function, or null
/// when the extent is not known here — which is exactly the case for a `ptr`
/// PARAMETER, where the table was bound in some other function and only its base
/// address crossed the boundary. No extent, no guard: a check against a length
/// this function does not have would be a guess.
fn staticTableLen(ctx: *const LowerCtx, name: []const u8) ?i64 {
    var buf: [512]u8 = undefined;
    const len_key = std.fmt.bufPrint(&buf, "{s}.len", .{name}) catch return null;
    const len_slot = ctx.locals.get(len_key) orelse return null;
    return ctx.table_lens.get(len_slot);
}

/// The index to use for a MEMORY-BACKED access, with the range decided first.
///
/// The register-exploded representation has always refused a statically
/// out-of-range index (there is no element local to name) and trapped a dynamic
/// one (gap[063]). The memory-backed representation, which the same table falls
/// into purely by being wider, did NEITHER: `t(0)` on a 40-element table read the
/// word below the region and answered with it, and `t(41)` read the word above.
/// Same program, same index, same table — a different answer decided by how many
/// literals were written. That is the size threshold showing up as a CORRECTNESS
/// difference rather than a speed one, and it is the reason the two paths are
/// brought level here.
///
///   constant, in range   — nothing emitted; the extent already proved it.
///   constant, out of range — REFUSED at compile time, as the narrow path does.
///   dynamic              — the bounds trap, as the narrow path does.
///
/// Affordable now precisely because the trap stopped being a call: before
/// `trap_abort_tag` this guard would have set `body_has_call` on every function
/// that touches a wide table and cost each one its entire register allocation,
/// which is why "check the wide path too" was not a small change until now.
fn guardedTableIndex(ctx: *LowerCtx, table_name: []const u8, key_expr: *const ast.Expr) Error!dnir.Value {
    const len = staticTableLen(ctx, table_name) orelse return try lowerExpr(ctx, key_expr);
    if (intLiteralStep(key_expr)) |k| {
        if (k < 1 or k > len) return bail(ctx.diagnostic, @src());
        return .{ .i64 = k };
    }
    const idx_slot = ctx.freshTemp();
    const raw = try lowerExpr(ctx, key_expr);
    try ctx.emit(.{ .op = .store_local, .result = idx_slot, .lhs = raw, .ty = .any });
    try emitIndexBoundsTrap(ctx, idx_slot, len);
    return .{ .local = idx_slot };
}

/// `1 <= i <= len`, as ONE instruction for the backend to expand.
///
/// It used to be two `binop` comparisons and three `br`s, which the backend
/// fused into five machine instructions on the path that is taken plus two
/// hoisted constants. Written that way the range test was FOUR DNIR values wide
/// — two comparison temps and two immediates — and the register allocator paid
/// for all of them inside the loop that reads the table.
///
/// The pair of bounds is not two facts. It is one range, and one UNSIGNED
/// compare of `i - 1` against `len - 1` decides it, because `i <= 0` wraps to
/// the top of the unsigned range and fails the same test `i > len` fails. That
/// expansion belongs to the backend (`emitIndexBoundsCheck`), because unsigned
/// comparison has no `dnir.BinOpTag` and inventing one would put a second,
/// nearly-identical comparison family into every consumer of DNIR for the sake
/// of one call site.
///
/// The tag convention is the one `trap_abort_tag` already established: a
/// `hw_unary` with `.hw = .none` and a `.field` the backend matches. `.result`
/// is null — this instruction defines no value, it only decides whether control
/// continues.
pub const index_bounds_tag = "index.bounds";

/// Widest extent whose `len - 1` still fits the compare's 12-bit immediate.
/// Past it the fused form would need a register for the limit and would stop
/// being one instruction, so the portable two-comparison expansion below is
/// used instead — it is correct at every extent and is what every table used
/// before this seam existed.
const fused_bounds_max: i64 = 4096;

fn emitIndexBoundsTrap(ctx: *LowerCtx, idx_slot: u32, len: i64) Error!void {
    if (len >= 1 and len <= fused_bounds_max) {
        try ctx.emit(.{
            .op = .hw_unary,
            .hw = .none,
            .field = index_bounds_tag,
            .lhs = .{ .local = idx_slot },
            .rhs = .{ .i64 = len },
        });
        return;
    }

    const lo = ctx.freshTemp();
    try ctx.emit(.{ .op = .binop, .result = lo, .binop = .geq, .lhs = .{ .local = idx_slot }, .rhs = .{ .i64 = 1 } });
    const lo_bad = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br, .lhs = .{ .temp = lo }, .branch_target = 0, .branch_condition = .when_false });

    const hi = ctx.freshTemp();
    try ctx.emit(.{ .op = .binop, .result = hi, .binop = .leq, .lhs = .{ .local = idx_slot }, .rhs = .{ .i64 = len } });
    const hi_bad = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br, .lhs = .{ .temp = hi }, .branch_target = 0, .branch_condition = .when_false });

    const skip = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br, .branch_target = 0 });

    const trap: u32 = @intCast(ctx.instrs.items.len);
    ctx.instrs.items[lo_bad].branch_target = trap;
    ctx.instrs.items[hi_bad].branch_target = trap;
    try emitTrap(ctx);
    ctx.instrs.items[skip].branch_target = @intCast(ctx.instrs.items.len);
}

/// `t[k] = v` on a positional table.
///
/// The mirror of `lowerDynamicIndex`. A constant index stores straight into the
/// element's own local. A non-constant index becomes a select-chain of stores —
/// `if k == 1 { t.1 = v }  if k == 2 { t.2 = v }  …` — which needs no memory,
/// because the elements are registers. Together with dynamic reads this makes a
/// fixed-size table genuinely *mutable*, which is what a bounded symbol table
/// needs: declare into a slot, look it up later.
///
/// An out-of-range index TRAPS — see `emitIndexBoundsTrap`. It used to store
/// nowhere, which is gap[063].
fn lowerIndexAssignTarget(
    ctx: *LowerCtx,
    obj: *const ast.Expr,
    key_expr: *const ast.Expr,
    value: *const ast.Expr,
) Error!void {
    if (obj.* != .name) return bail(ctx.diagnostic, @src());
    const table_name = obj.name.ident;

    // Memory-backed table: a real scaled store, so writes through a shared base
    // are visible to every function holding it.
    if (ptrSlotOf(ctx, obj)) |base| {
        const idx = try guardedTableIndex(ctx, table_name, key_expr);
        const v = try lowerExprCons(ctx, value, .single);
        try ctx.emit(.{
            .op = .store_index,
            .ty = .i64,
            .lhs = .{ .local = base },
            .rhs = idx,
            .third = v,
        });
        return;
    }

    if (intLiteralStep(key_expr)) |n| {
        const key = try std.fmt.allocPrint(ctx.alloc, "{s}.{d}", .{ table_name, n });
        defer ctx.alloc.free(key);
        const slot = ctx.locals.get(key) orelse return bail(ctx.diagnostic, @src());
        const v = try lowerExprCons(ctx, value, .single);
        try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = .any });
        return;
    }

    const len_key = try std.fmt.allocPrint(ctx.alloc, "{s}.len", .{table_name});
    defer ctx.alloc.free(len_key);
    const len_slot = ctx.locals.get(len_key) orelse return bail(ctx.diagnostic, @src());
    const len = ctx.table_lens.get(len_slot) orelse return bail(ctx.diagnostic, @src());
    // A table wider than this is materialized into memory at its BINDING, so it
    // reaches the `ptrSlotOf` path above and never arrives here.
    if (len == 0 or len > select_chain_max) return bail(ctx.diagnostic, @src());

    // Evaluate index and value once, before any store, so a select-chain cannot
    // re-run side effects per candidate slot.
    const idx_slot = ctx.freshTemp();
    try ctx.emit(.{ .op = .store_local, .result = idx_slot, .lhs = try lowerExpr(ctx, key_expr), .ty = .any });
    try emitIndexBoundsTrap(ctx, idx_slot, len);
    const val_slot = ctx.freshTemp();
    try ctx.emit(.{ .op = .store_local, .result = val_slot, .lhs = try lowerExprCons(ctx, value, .single), .ty = .any });

    var i: i64 = 1;
    while (i <= len) : (i += 1) {
        const elem_key = try std.fmt.allocPrint(ctx.alloc, "{s}.{d}", .{ table_name, i });
        defer ctx.alloc.free(elem_key);
        const elem_slot = ctx.locals.get(elem_key) orelse return bail(ctx.diagnostic, @src());

        const cmp = ctx.freshTemp();
        try ctx.emit(.{
            .op = .binop,
            .result = cmp,
            .binop = .eq,
            .lhs = .{ .local = idx_slot },
            .rhs = .{ .i64 = i },
        });
        const skip = ctx.instrs.items.len;
        try ctx.emit(.{ .op = .br, .lhs = .{ .temp = cmp }, .branch_target = 0, .branch_condition = .when_false });
        try ctx.emit(.{ .op = .store_local, .result = elem_slot, .lhs = .{ .local = val_slot }, .ty = .any });
        ctx.instrs.items[skip].branch_target = @intCast(ctx.instrs.items.len);
    }
}

/// `t[i]` where `i` is not a compile-time constant.
///
/// The elements of a positional table live in registers, not memory, so there is
/// no base pointer to offset from. For a table of statically known length the
/// correct lowering is a select over the element slots:
///
///     S = 0;  if i == 1 { S = t.1 }  if i == 2 { S = t.2 }  …  S
///
/// That is O(n) compares, which is the right trade for the small fixed-size
/// tables a compiler actually uses — and it needs no memory traffic at all.
/// An out-of-range index TRAPS (gap[063]); it used to yield 0, which reads as
/// "a missing positional entry" and is indistinguishable from a stored zero.
///
/// A genuinely dynamic, growable table still needs base-pointer addressing;
/// this handles the fixed-length case, which is what fits in registers.
fn lowerDynamicIndex(ctx: *LowerCtx, table_name: []const u8, key_expr: *const ast.Expr) Error!dnir.Value {
    const len_key = try std.fmt.allocPrint(ctx.alloc, "{s}.len", .{table_name});
    defer ctx.alloc.free(len_key);
    const len_slot = ctx.locals.get(len_key) orelse return bail(ctx.diagnostic, @src());
    const len = ctx.table_lens.get(len_slot) orelse return bail(ctx.diagnostic, @src());
    // As on the write side: wide tables are memory-backed from their binding and
    // resolve through `ptrSlotOf` before reaching this chain.
    if (len == 0 or len > select_chain_max) return bail(ctx.diagnostic, @src());

    const idx_slot = ctx.freshTemp();
    try ctx.emit(.{ .op = .store_local, .result = idx_slot, .lhs = try lowerExpr(ctx, key_expr), .ty = .any });
    try emitIndexBoundsTrap(ctx, idx_slot, len);

    const out_slot = ctx.freshTemp();
    try ctx.emit(.{ .op = .store_local, .result = out_slot, .lhs = .{ .i64 = 0 }, .ty = .any });
    // The select chain returns a SLOT, not an expression, so `holds` is the
    // only thing a consumer that never sees the AST node can ask. It has to
    // agree with `exprIsStr`'s `.index` arm or the two classifiers disagree on
    // one read — which is the shape that printed a pointer.
    if (ctx.str_tables.contains(table_name)) try ctx.str_slots.put(ctx.alloc, out_slot, {});

    var i: i64 = 1;
    while (i <= len) : (i += 1) {
        const elem_key = try std.fmt.allocPrint(ctx.alloc, "{s}.{d}", .{ table_name, i });
        defer ctx.alloc.free(elem_key);
        const elem_slot = ctx.locals.get(elem_key) orelse return bail(ctx.diagnostic, @src());

        const cmp = ctx.freshTemp();
        try ctx.emit(.{
            .op = .binop,
            .result = cmp,
            .binop = .eq,
            .lhs = .{ .local = idx_slot },
            .rhs = .{ .i64 = i },
        });
        const skip = ctx.instrs.items.len;
        try ctx.emit(.{ .op = .br, .lhs = .{ .temp = cmp }, .branch_target = 0, .branch_condition = .when_false });
        try ctx.emit(.{ .op = .store_local, .result = out_slot, .lhs = .{ .local = elem_slot }, .ty = .any });
        ctx.instrs.items[skip].branch_target = @intCast(ctx.instrs.items.len);
    }
    return .{ .local = out_slot };
}

/// True when every field of a table literal is positional.
fn tableIsPositional(table: *const ast.Expr) bool {
    if (table.* != .table) return false;
    if (table.table.fields.len == 0) return false;
    for (table.table.fields) |fld| {
        if (fld != .positional) return false;
    }
    return true;
}

fn lowerRecordLiteralAssign(ctx: *LowerCtx, name: []const u8, table: *const ast.Expr) Error!void {
    if (table.* != .table) return bail(ctx.diagnostic, @src());
    const rec_slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, name), rec_slot);
    try lowerRecordLiteralFields(ctx, name, table);
    const rec_name = inferRecordNameFromTable(ctx.records, table) orelse "";
    try ctx.emit(.{ .op = .init_record, .result = rec_slot, .record = rec_name });
}

/// Write one local per field under `prefix`, recursing through nested records.
///
/// Explosion keys a field as `"<prefix>.<field>"`, and a field whose value is
/// itself a record literal simply extends the prefix: `o = { i = { x = 40 } }`
/// stores `o.i.x`. Before this, the inner `{ x = 40 }` was handed to
/// `lowerExpr`, which has no `.table` arm, so a record holding a record refused
/// the whole module.
///
/// The recursion carries no depth limit because the key is what bounds it — a
/// record type cannot contain itself by value, so the nesting is as finite as
/// the type declarations that produced it.
///
/// Field order comes from the LITERAL here, which is safe only because these
/// are keyed locals rather than ABI slots: `o.y` names the same storage no
/// matter where `y` was written. A record crossing a function boundary takes
/// its order from the DESCRIPTOR instead — that is `recordFieldOrder`'s job,
/// not this one, and conflating the two is the field-ordering miscompile this
/// backend has already had twice.

fn copyPrefixedLocalsFromRecordRef(
    ctx: *LowerCtx,
    dest_prefix: []const u8,
    src_base: []const u8,
) Error!void {
    var src_buf: [256]u8 = undefined;
    const src_pat = std.fmt.bufPrint(&src_buf, "{s}.", .{src_base}) catch return bail(ctx.diagnostic, @src());
    var it = ctx.locals.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (!std.mem.startsWith(u8, key, src_pat)) continue;
        const suffix = key[src_pat.len..];
        const dest_key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ dest_prefix, suffix });
        defer ctx.alloc.free(dest_key);
        const src_slot = entry.value_ptr.*;
        if (ctx.locals.get(dest_key)) |dest_slot| {
            try ctx.emit(.{ .op = .store_local, .result = dest_slot, .lhs = .{ .local = src_slot }, .ty = .any });
        } else {
            const slot = ctx.freshTemp();
            try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, dest_key), slot);
            try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = .{ .local = src_slot }, .ty = .any });
        }
    }
    if (ctx.locals.get(dest_prefix) == null) {
        const marker = try ctx.alloc.dupe(u8, dest_prefix);
        const sub_slot = ctx.freshTemp();
        try ctx.locals.put(ctx.alloc, marker, sub_slot);
        try ctx.emit(.{ .op = .init_record, .result = sub_slot, .record = "" });
    }
}

fn lowerRecordLiteralFields(ctx: *LowerCtx, prefix: []const u8, table: *const ast.Expr) Error!void {
    if (table.* != .table) return bail(ctx.diagnostic, @src());
    for (table.table.fields) |fld| {
        const nf = switch (fld) {
            .named => |n| n,
            else => return bail(ctx.diagnostic, @src()),
        };
        const fk = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ prefix, nf.key });
        if (nf.val.* == .table) {
            // A nested record owns no storage of its own — only its leaves do.
            // The marker slot exists so `isRecordLocalName` and the field-key
            // lookups can still see that `o.i` is a bound record name.
            const sub_slot = ctx.freshTemp();
            try ctx.locals.put(ctx.alloc, fk, sub_slot);
            try lowerRecordLiteralFields(ctx, fk, nf.val);
            const sub_name = inferRecordNameFromTable(ctx.records, nf.val) orelse "";
            try ctx.emit(.{ .op = .init_record, .result = sub_slot, .record = sub_name });
            continue;
        } else if (nf.val.* == .name) {
            try copyPrefixedLocalsFromRecordRef(ctx, fk, nf.val.name.ident);
            continue;
        }
        const v = try lowerExpr(ctx, nf.val);
        const fslot = ctx.freshTemp();
        try ctx.locals.put(ctx.alloc, fk, fslot);
        // A FIELD IS A PLACE AND ITS DESCRIPTOR APPLIES HERE — the literal
        // that creates the storage is a write like any later `r.f = …`, and
        // registering the width now is what makes every one of those later
        // writes find it: `lowerFieldAssignTarget` reads `narrow_slots` off
        // the slot exactly as `lowerAssign` does for a narrow local.
        const declared = fieldWidth(ctx, table, nf.key);
        if (declared) |width| try ctx.narrow_slots.put(ctx.alloc, fslot, width);
        const store_ty: RT = if (exprIsF64(ctx, nf.val)) .f64 else (declared orelse .any);
        if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, fslot, {});
        if (exprIsStr(ctx, nf.val)) try ctx.str_slots.put(ctx.alloc, fslot, {});
        try ctx.emit(.{ .op = .store_local, .result = fslot, .lhs = v, .ty = store_ty });
    }
}

/// Match a table literal's named fields to a module record descriptor.
/// The declared narrow width of `field` in the record `table` is a literal of,
/// or null when the record is unknown, the field is absent, or the field is
/// full-width.
///
/// FAILS CLOSED, and the failure is the pre-existing behaviour rather than a
/// new refusal: an unrecognised literal answers null and the store stays
/// `.any`, which is exactly what every field store did before.
fn fieldWidth(ctx: *LowerCtx, table: *const ast.Expr, field: []const u8) ?RT {
    for (ctx.records) |rec| {
        if (!tableMatchesRecord(table, rec)) continue;
        if (rec.widths.len != rec.fields.len) return null;
        for (rec.fields, 0..) |name, i| {
            if (std.mem.eql(u8, name, field)) return rec.widths[i];
        }
        return null;
    }
    return null;
}

fn inferRecordNameFromTable(records: []const dnir.RecordDesc, table: *const ast.Expr) ?[]const u8 {
    if (table.* != .table) return null;
    for (records) |rec| {
        if (tableMatchesRecord(table, rec)) return rec.name;
    }
    return null;
}

fn tableMatchesRecord(table: *const ast.Expr, rec: dnir.RecordDesc) bool {
    if (table.* != .table) return false;
    if (table.table.fields.len != rec.fields.len) return false;
    for (rec.fields) |fname| {
        var found = false;
        for (table.table.fields) |fld| {
            const nf = switch (fld) {
                .named => |n| n,
                else => return false,
            };
            if (std.mem.eql(u8, nf.key, fname)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

/// Lower inline table literal as a temp record value for call arguments.
fn lowerInlineRecordArg(ctx: *LowerCtx, table: *const ast.Expr, rec_name: []const u8) Error!dnir.Value {
    if (table.* != .table) return bail(ctx.diagnostic, @src());
    const rec_slot = ctx.freshTemp();
    const anon = try std.fmt.allocPrint(ctx.alloc, "__rec{d}", .{rec_slot});
    defer ctx.alloc.free(anon);
    for (table.table.fields) |fld| {
        const nf = switch (fld) {
            .named => |n| n,
            else => return bail(ctx.diagnostic, @src()),
        };
        const v = try lowerExpr(ctx, nf.val);
        const fslot = ctx.freshTemp();
        const fk = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ anon, nf.key });
        try ctx.locals.put(ctx.alloc, fk, fslot);
        const store_ty: RT = if (exprIsF64(ctx, nf.val)) .f64 else .any;
        if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, fslot, {});
        try ctx.emit(.{ .op = .store_local, .result = fslot, .lhs = v, .ty = store_ty });
    }
    try ctx.emit(.{ .op = .init_record, .result = rec_slot, .record = rec_name });
    return .{ .temp = rec_slot };
}


fn recordLocalDesc(ctx: *LowerCtx, name: []const u8) ?dnir.RecordDesc {
    for (ctx.records) |rec| {
        if (rec.fields.len == 0) continue;
        if (recordFieldsPresent(ctx, name, rec)) return rec;
    }
    if (ctx.locals.get(name)) |_| {
        if (ctx.param_record_types.get(name)) |rec_name| {
            for (ctx.records) |rec| {
                if (std.mem.eql(u8, rec.name, rec_name)) return rec;
            }
            if (findRecordByNominal(ctx.records, rec_name, ctx.graph)) |rec| return rec;
        }
    }
    return null;
}

fn materializeRecordBase(ctx: *LowerCtx, name: []const u8) Error!u32 {
    if (ctx.locals.get(name)) |s| {
        if (ctx.ptr_slots.contains(s)) return s;
    }
    const rec = recordLocalDesc(ctx, name) orelse return bail(ctx.diagnostic, @src());
    const count: i64 = @intCast(rec.fields.len);
    const base = ctx.freshTemp();
    try ctx.emit(.{ .op = .alloc_slots, .result = base, .lhs = .{ .i64 = count } });
    for (rec.fields, rec.kinds, 0..) |fname, kind, i| {
        const t = ctx.freshTemp();
        try ctx.emit(.{
            .op = .load_field,
            .result = t,
            .req_alias = name,
            .field = fname,
        });
        const ty: RT = switch (kind) {
            .str => .str,
            .f64 => .f64,
            .i64 => .any,
        };
        try ctx.emit(.{
            .op = .store_index,
            .ty = ty,
            .lhs = .{ .temp = base },
            .rhs = .{ .i64 = @intCast(i + 1) },
            .third = .{ .temp = t },
        });
    }
    try ctx.ptr_slots.put(ctx.alloc, base, {});
    try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, name), base);
    return base;
}

fn lowerOpaqueRecordLocalArg(ctx: *LowerCtx, expr: *const ast.Expr) Error!?dnir.Value {
    if (expr.* != .name) return null;
    if (recordLocalDesc(ctx, expr.name.ident) == null) return null;
    return .{ .local = try materializeRecordBase(ctx, expr.name.ident) };
}

fn recordFieldsPresent(ctx: *LowerCtx, name: []const u8, rec: dnir.RecordDesc) bool {
    if (rec.fields.len == 0) return false;
    for (rec.fields) |fname| {
        const key = std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ name, fname }) catch return false;
        defer ctx.alloc.free(key);
        if (ctx.locals.get(key) == null) return false;
    }
    return true;
}

fn emitF64RecordFieldsFromName(ctx: *LowerCtx, name: []const u8, slot: *u32) Error!bool {
    for (ctx.records) |rec| {
        var all_f64 = rec.fields.len > 0;
        for (rec.kinds) |k| {
            if (k != .f64) all_f64 = false;
        }
        if (!all_f64 or !recordFieldsPresent(ctx, name, rec)) continue;
        for (rec.fields) |fname| {
            const key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ name, fname });
            const field_slot = ctx.locals.get(key) orelse return bail(ctx.diagnostic, @src());
            ctx.alloc.free(key);
            try ctx.emit(.{ .op = .fp_mov_arg, .result = slot.*, .lhs = .{ .local = field_slot } });
            slot.* += 1;
            if (slot.* > 8) return bail(ctx.diagnostic, @src());
        }
        return true;
    }
    return false;
}

/// Does this name refer to a local of the function's RETURN record type?
/// Checked by the presence of its first exploded field slot, which is the same
/// evidence `lowerRecordReturn` then relies on — so the dispatch cannot admit
/// a shape the arm would refuse.
fn isRecordLocalName(ctx: *LowerCtx, e: *const ast.Expr) bool {
    if (e.* != .name) return false;
    const rec_name = ctx.ret_record orelse return false;
    const rec = findRecordName(ctx.records, .{ .named = rec_name }) orelse return false;
    if (rec.fields.len == 0) return false;
    var buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}.{s}", .{ e.name.ident, rec.fields[0] }) catch return false;
    return ctx.locals.get(key) != null;
}

fn lowerRecordReturn(ctx: *LowerCtx, table: *const ast.Expr) Error!void {
    const rec_name = ctx.ret_record orelse return bail(ctx.diagnostic, @src());
    const rec = findRecordName(ctx.records, .{ .named = rec_name }) orelse return bail(ctx.diagnostic, @src());
    const count: u32 = @intCast(rec.fields.len);
    if (count == 0 or count > max_record_fields) return bail(ctx.diagnostic, @src());

    // `return r` where `r` is a record-typed LOCAL rather than a literal.
    //
    // A record local is stored EXPLODED — one local per field, keyed
    // "name.field" — and those slots already hold the values (reading `r.a`
    // works). They only need gathering in DESCRIPTOR order, the same order the
    // literal path below is careful to use.
    if (table.* == .name) {
        const base = table.name.ident;
        const nvals = try ctx.alloc.alloc(dnir.Value, count);
        errdefer ctx.alloc.free(nvals);
        for (rec.fields, 0..) |fname, i| {
            const key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ base, fname });
            defer ctx.alloc.free(key);
            const slot = ctx.locals.get(key) orelse return bailWith(ctx.diagnostic, @src(), fname);
            nvals[i] = .{ .local = slot };
        }
        try ctx.emit(.{
            .op = .ret_record,
            .record = rec_name,
            .lhs = nvals[0],
            .rhs = if (count > 1) nvals[1] else .void,
            .third = if (count > 2) nvals[2] else .void,
            .vals = nvals,
            .result = count,
        });
        return;
    }
    if (table.* != .table) return bail(ctx.diagnostic, @src());

    // Order by the DESCRIPTOR, not by the literal.
    //
    // The consumer reads field i out of ABI slot i (or buffer offset i*8), and
    // the descriptor is the only thing that agrees with it. Walking the
    // literal's own order instead meant `return { c = 3, a = 1, b = 2 }` for
    // `@{ a, b, c }` shipped 3 in the slot the caller reads as `a`. Every
    // literal that happened to be written in declaration order hid it.
    const vals = try ctx.alloc.alloc(dnir.Value, count);
    errdefer ctx.alloc.free(vals);
    var seen = try ctx.alloc.alloc(bool, count);
    defer ctx.alloc.free(seen);
    @memset(seen, false);
    for (table.table.fields) |fld| {
        const nf = switch (fld) {
            .named => |n| n,
            else => return bail(ctx.diagnostic, @src()),
        };
        if (fieldIndexIn(rec, nf.key)) |idx| {
            if (seen[idx]) return bailWith(ctx.diagnostic, @src(), nf.key);
            vals[idx] = try lowerExpr(ctx, nf.val);
            seen[idx] = true;
        } else if (nf.val.* == .table) {
            try lowerNestedRecordTableFields(ctx, rec, nf.key, nf.val, vals, seen);
        } else if (nf.val.* == .name) {
            try lowerNestedRecordFromLocal(ctx, rec, nf.key, nf.val.name.ident, vals, seen);
        } else if (nf.val.* == .field) {
            try lowerNestedRecordFromFieldRef(ctx, rec, nf.key, nf.val, vals, seen);
        } else {
            return bailWith(ctx.diagnostic, @src(), nf.key);
        }
    }
    // A partially-written buffer is the exact failure this convention has to
    // rule out: the caller reads all `count` slots either way, so an omitted
    // field is caller-visible garbage rather than a missing value.
    for (seen, 0..) |s, i| {
        if (!s) return bailWith(ctx.diagnostic, @src(), rec.fields[i]);
    }

    try ctx.emit(.{
        .op = .ret_record,
        .record = rec_name,
        .lhs = vals[0],
        .rhs = if (count > 1) vals[1] else .void,
        .third = if (count > 2) vals[2] else .void,
        .vals = vals,
        .result = count,
    });
}



fn lowerNestedRecordFromLocal(
    ctx: *LowerCtx,
    rec: dnir.RecordDesc,
    prefix: []const u8,
    base: []const u8,
    vals: []dnir.Value,
    seen: []bool,
) Error!void {
    var prefix_buf: [256]u8 = undefined;
    const prefix_pat = std.fmt.bufPrint(&prefix_buf, "{s}.", .{prefix}) catch return bail(ctx.diagnostic, @src());
    for (rec.fields, 0..) |fname, idx| {
        if (!std.mem.startsWith(u8, fname, prefix_pat)) continue;
        const suffix = fname[prefix_pat.len..];
        const local_key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ base, suffix });
        defer ctx.alloc.free(local_key);
        const slot = ctx.locals.get(local_key) orelse return bailWith(ctx.diagnostic, @src(), local_key);
        if (seen[idx]) return bailWith(ctx.diagnostic, @src(), fname);
        vals[idx] = .{ .local = slot };
        seen[idx] = true;
    }
}

fn lowerNestedRecordTableFields(
    ctx: *LowerCtx,
    rec: dnir.RecordDesc,
    prefix: []const u8,
    table_expr: *const ast.Expr,
    vals: []dnir.Value,
    seen: []bool,
) Error!void {
    if (table_expr.* != .table) return bail(ctx.diagnostic, @src());
    for (table_expr.table.fields) |sub| {
        const sn = switch (sub) {
            .named => |n| n,
            else => return bail(ctx.diagnostic, @src()),
        };
        var buf: [512]u8 = undefined;
        const flat_name = std.fmt.bufPrint(&buf, "{s}.{s}", .{ prefix, sn.key }) catch return bail(ctx.diagnostic, @src());
        if (fieldIndexIn(rec, flat_name)) |idx| {
            if (seen[idx]) return bailWith(ctx.diagnostic, @src(), flat_name);
            vals[idx] = try lowerExpr(ctx, sn.val);
            seen[idx] = true;
        } else if (sn.val.* == .table) {
            try lowerNestedRecordTableFields(ctx, rec, flat_name, sn.val, vals, seen);
        } else if (sn.val.* == .name) {
            try lowerNestedRecordFromLocal(ctx, rec, flat_name, sn.val.name.ident, vals, seen);
        } else if (sn.val.* == .field) {
            try lowerNestedRecordFromFieldRef(ctx, rec, flat_name, sn.val, vals, seen);
        } else {
            return bailWith(ctx.diagnostic, @src(), flat_name);
        }
    }
}

fn fieldIndexIn(rec: dnir.RecordDesc, name: []const u8) ?usize {
    for (rec.fields, 0..) |f, i| {
        if (std.mem.eql(u8, f, name)) return i;
    }
    return null;
}

fn recordFieldRootName(expr: *const ast.Expr) ?[]const u8 {
    return switch (expr.*) {
        .name => |n| n.ident,
        .field => |f| recordFieldRootName(f.obj),
        else => null,
    };
}

fn loadFieldFromOpaquePath(
    ctx: *LowerCtx,
    path: []const u8,
    application: ?semantic_graph.id,
) Error!?dnir.Value {
    if (ctx.locals.get(path)) |slot| return .{ .local = slot };
    const dot = std.mem.indexOfScalar(u8, path, '.') orelse return null;
    const obj_name = path[0..dot];
    const field = path[dot + 1 ..];
    if (nestedRecordPrefixHasLocals(ctx, path)) return null;
    if (opaqueRecordParam(ctx, obj_name)) |opaque_rec| {
        if (recordFieldKindForParam(ctx, obj_name, field) == null) {
            if (recordDescForParamName(ctx, obj_name)) |rec| {
                if (recordFieldPrefixPresent(rec, field)) return null;
            }
        }
        const t = ctx.freshTemp();
        const rt: RT = switch (recordFieldKindForParam(ctx, obj_name, field) orelse .i64) {
            .f64 => .f64,
            .str => .str,
            .i64 => .any,
        };
        noteHostTaint(ctx, .opaque_path, "opaque_path.load_field", application);
        try ctx.emit(.{
            .op = .load_field,
            .result = t,
            .rhs = .{ .local = opaque_rec.slot },
            .record = opaque_rec.rec_name,
            .field = try ctx.alloc.dupe(u8, field),
            .ty = rt,
        });
        if (rt == .f64) try ctx.f64_slots.put(ctx.alloc, t, {});
        if (rt == .str) try ctx.str_slots.put(ctx.alloc, t, {});
        return .{ .temp = t };
    }
    if (ctx.locals.get(obj_name) == null and ctx.param_record_types.get(obj_name) == null) return null;
    const rec_name = ctx.param_record_types.get(obj_name) orelse blk: {
        if (recordLocalDesc(ctx, obj_name)) |rec| break :blk rec.name;
        break :blk "";
    };
    const t = ctx.freshTemp();
    noteHostTaint(ctx, .opaque_path, "opaque_path.load_field", application);
    try ctx.emit(.{
        .op = .load_field,
        .result = t,
        .req_alias = try ctx.alloc.dupe(u8, obj_name),
        .field = try ctx.alloc.dupe(u8, field),
        .record = if (rec_name.len > 0) try ctx.alloc.dupe(u8, rec_name) else "",
    });
    return .{ .temp = t };
}

fn lowerNestedRecordFromFieldRef(
    ctx: *LowerCtx,
    rec: dnir.RecordDesc,
    prefix: []const u8,
    base_expr: *const ast.Expr,
    vals: []dnir.Value,
    seen: []bool,
) Error!void {
    const obj_name = recordFieldRootName(base_expr) orelse return bail(ctx.diagnostic, @src());
    var base_path: std.ArrayList(u8) = .empty;
    defer base_path.deinit(ctx.alloc);
    if (!try flattenNames(ctx.alloc, base_expr, &base_path)) return bail(ctx.diagnostic, @src());
    var prefix_buf: [512]u8 = undefined;
    const prefix_pat = std.fmt.bufPrint(&prefix_buf, "{s}.", .{prefix}) catch return bail(ctx.diagnostic, @src());
    for (rec.fields, 0..) |fname, idx| {
        if (!std.mem.startsWith(u8, fname, prefix_pat)) continue;
        if (seen[idx]) return bailWith(ctx.diagnostic, @src(), fname);
        const suffix = fname[prefix_pat.len..];
        const local_key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ base_path.items, suffix });
        defer ctx.alloc.free(local_key);
        if (try loadFieldFromOpaquePath(ctx, local_key, null)) |v| {
            vals[idx] = v;
        } else if (ctx.locals.get(local_key)) |slot| {
            vals[idx] = .{ .local = slot };
        } else {
            const t = ctx.freshTemp();
            try ctx.emit(.{ .op = .load_field, .result = t, .req_alias = obj_name, .field = fname });
            vals[idx] = .{ .temp = t };
        }
        seen[idx] = true;
    }
}

fn callFieldSuffixFromExpr(
    ctx: *LowerCtx,
    expr: *const ast.Expr,
) Error!?struct { call: *const ast.Expr, suffix: []const u8 } {
    var parts: std.ArrayList([]const u8) = .empty;
    defer parts.deinit(ctx.alloc);
    var cur: *const ast.Expr = expr;
    while (cur.* == .field) {
        try parts.append(ctx.alloc, cur.field.field);
        cur = cur.field.obj;
    }
    if (cur.* != .call and cur.* != .method_call or parts.items.len == 0) return null;
    var suffix: std.ArrayList(u8) = .empty;
    defer suffix.deinit(ctx.alloc);
    var i: usize = parts.items.len;
    while (i > 0) {
        i -= 1;
        if (suffix.items.len > 0) try suffix.append(ctx.alloc, '.');
        try suffix.appendSlice(ctx.alloc, parts.items[i]);
    }
    return .{ .call = cur, .suffix = try ctx.alloc.dupe(u8, suffix.items) };
}

fn lowerCallRecordFieldProjection(
    ctx: *LowerCtx,
    call_expr: *const ast.Expr,
    field_name: []const u8,
) Error!?dnir.Value {
    if (!ctx.require_graph_facts) return null;
    const application = ctx.occurrences.get(call_expr) orelse return null;
    const record = try checkedRecordForApplication(ctx, application) orelse return null;
    const tmp_slot = ctx.freshTemp();
    const tmp = try std.fmt.allocPrint(ctx.alloc, "__rf{d}", .{tmp_slot});
    // Keep `tmp` alive until `internInstrStrings` copies `.field` / `.req_alias`.
    try lowerCheckedRecordCallAssign(ctx, tmp, application, record, call_expr);
    const fk = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ tmp, field_name });
    if (ctx.locals.get(fk)) |slot| return .{ .local = slot };
    if (try loadFieldFromOpaquePath(ctx, fk, application.application)) |v| return v;
    return null;
}

fn lowerExpr(ctx: *LowerCtx, expr: *const ast.Expr) Error!dnir.Value {
    return lowerExprCons(ctx, expr, .single);
}

/// The module-scope place a name denotes HERE, when the graph ruled that it
/// has no runtime location at all.
///
/// BINDING ORDER IS THE WHOLE SAFETY ARGUMENT, and it is the same order the
/// `.name` arm below already states: a local, a parameter or a WRITTEN module
/// global is a NAME THAT IS TAKEN, and only a name nothing else has taken can
/// still mean a place. Every existing resolution path therefore wins over this
/// one, so no program that lowers today reaches it.
fn absentModulePlace(ctx: *LowerCtx, name: []const u8) ?*const place.Place {
    if (ctx.graph.placeCount() == 0) return null;
    if (ctx.locals.contains(name)) return null;
    if (ctx.module_globals.has(name)) return null;
    const p = ctx.graph.placeNamed(name) orelse return null;
    if (place.residencyRefusal(p) != .none) return null;
    return p;
}

/// `t(k)` / `t[k]` on a module-scope collection whose §18 residency is
/// `.absent` — the element, as an immediate, with no storage anywhere.
fn placeElement(ctx: *LowerCtx, name: []const u8, key: *const Expr) ?dnir.Value {
    const p = absentModulePlace(ctx, name) orelse return null;
    if (p.shape != .collection) return null;
    if (p.facts.contents_known != .yes) return null;
    const init = p.init orelse return null;
    if (init.* != .table) return null;
    const fields = init.table.fields;
    // §19 CONSTANT INDEX — the per-access half, separate from the place-wide
    // determinacy `residencyRefusal` already checked.
    const k = intLiteralStep(key) orelse return null;
    // TABLES ARE 1-INDEXED. `t(0)` is out of range as surely as `t(len + 1)`,
    // and folding either to `fields[k - 1]` is the wrong-answer class this
    // whole ruling exists to avoid.
    if (k < 1 or k > @as(i64, @intCast(fields.len))) return null;
    const f = fields[@intCast(k - 1)];
    if (f != .positional) return null;
    const v = intLiteralStep(f.positional) orelse return null;
    return dnir.Value{ .i64 = v };
}

/// §18 RESIDENCY, CONSUMED — the fact `place.zig` produces reaching emitted
/// machine code.
///
/// A module-scope binding that nothing writes, aliases, escapes or indexes at a
/// runtime offset has NO RUNTIME LOCATION: every read of it IS its initializer.
/// Measured on this tree before this existed, `global k = 7` and
/// `global t = (10, 20, 30)` were both outside the direct backend subset —
/// `DNB001 … missing: k` and `DNB001 … missing: graph-dnir-unsupported` — so
/// the fold is not a cheaper path to an answer the compiler already had.
///
/// WHY IT IS NOT A FOURTH NAME-KEYED TABLE. `ModuleConsts` answers one spelling
/// with one boolean and cannot say why it declined; `place.residencyRefusal`
/// names ten distinct reasons, is three-valued so `unknown` never reads as
/// `no`, and is read from the SAME array `observation.zig` and `eqspace.zig`
/// read. Deleting any one of its five §19 clauses re-admits a candidate the
/// other four forbid, which `gate/place.sh` measures in `__text`.
fn placeFold(ctx: *LowerCtx, expr: *const Expr) ?dnir.Value {
    switch (expr.*) {
        .name => |n| {
            const p = absentModulePlace(ctx, n.ident) orelse return null;
            if (p.shape != .scalar) return null;
            const init = p.init orelse return null;
            const v = intLiteralStep(init) orelse return null;
            return dnir.Value{ .i64 = v };
        },
        .call => |c| {
            if (c.func.* != .name or c.args.len != 1) return null;
            return placeElement(ctx, c.func.name.ident, c.args[0]);
        },
        .index => |ix| {
            if (ix.obj.* != .name) return null;
            return placeElement(ctx, ix.obj.name.ident, ix.key);
        },
        else => return null,
    }
}

const AggregateAccessStep = struct {
    application: *const semantic_graph.ApplicationFact,
    subject: semantic_graph.id,
    key: semantic_graph.id,
    result: semantic_graph.id,
    extent: i64,
    result_descriptor: RT,
};

fn collectAggregateAccessPath(
    ctx: *LowerCtx,
    application: *const semantic_graph.ApplicationFact,
    steps: *std.ArrayListUnmanaged(AggregateAccessStep),
    seen: *std.AutoHashMapUnmanaged(semantic_graph.id, void),
) Error!void {
    const fact = ctx.graph.aggregateAccess(application.application) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-access-fact");
    const entry = try seen.getOrPut(ctx.alloc, fact.application);
    if (entry.found_existing) return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-access-cycle");

    const subject = ctx.graph.applicationSubject(fact.application) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-access-subject");
    if (ctx.graph.aggregateProducer(subject)) |producer| {
        const parent = ctx.graph.aggregateAccess(producer) orelse
            return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-access-producer");
        try collectAggregateAccessPath(ctx, parent, steps, seen);
    }
    const operands = ctx.graph.applicationArguments(fact.application) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-operand-pack");
    const results = ctx.graph.applicationResults(fact.application) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-result-pack");
    if (operands.len != 1 or results.len != 1)
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-access-pack-arity");
    const subject_node = ctx.graph.get(subject) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-access-subject");
    const descriptor = subject_node.descriptor orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-access-descriptor");
    if (descriptor != .array or descriptor.array.size == null)
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-access-descriptor");
    const result_node = ctx.graph.get(results[0]) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-result-member");
    const result_descriptor = result_node.descriptor orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-result-descriptor");
    if (!result_descriptor.eql(descriptor.array.elem.*))
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-result-descriptor");
    try steps.append(ctx.alloc, .{
        .application = fact,
        .subject = subject,
        .key = operands[0],
        .result = results[0],
        .extent = @intCast(descriptor.array.size.?),
        .result_descriptor = result_descriptor,
    });
}

fn aggregateLeafCount(descriptor: RT) ?i64 {
    var current = descriptor;
    var count: u64 = 1;
    while (current == .array) {
        const extent = current.array.size orelse return null;
        count = std.math.mul(u64, count, extent) catch return null;
        current = current.array.elem.*;
    }
    if (current != .i64 or count == 0 or count > std.math.maxInt(i64)) return null;
    return @intCast(count);
}

fn aggregateBase(ctx: *LowerCtx, root_aggregate: semantic_graph.id) Error!u32 {
    if (ctx.aggregate_bases.get(root_aggregate)) |base| return base;
    if (!immutableNestedAggregateRoot(ctx.graph, root_aggregate))
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-static-place");
    const node = ctx.graph.get(root_aggregate) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-root");
    const descriptor = node.descriptor orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-root-descriptor");
    const words = aggregateLeafCount(descriptor) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-root-descriptor");
    const base = ctx.freshTemp();
    try ctx.emit(.{
        .op = .alloc_slots,
        .result = base,
        .lhs = .{ .i64 = words },
        .aggregate = root_aggregate,
        .ty = .i64,
    });
    try ctx.aggregate_bases.put(ctx.alloc, root_aggregate, base);
    return base;
}

fn setAggregateLineage(
    ctx: *LowerCtx,
    step: AggregateAccessStep,
    start: u32,
    instruction: *dnir.Instr,
) Error!void {
    instruction.relation = ctx.graph.applicationRelation(step.application.application) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-access-relation");
    instruction.application = step.application.application;
    instruction.value = step.result;
    instruction.subject = step.subject;
    instruction.target = ctx.graph.applicationTarget(step.application.application) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-access-target");
    instruction.realization_start = start;
    instruction.ty = step.result_descriptor;
}

fn aggregateKey(ctx: *LowerCtx, step: AggregateAccessStep) Error!dnir.Value {
    if (ctx.graph.exactI64(step.key)) |constant| {
        if (constant < 1 or constant > step.extent) return bailWith(ctx.diagnostic, @src(), "aggregate-index-bounds");
        return .{ .i64 = constant };
    }
    const expression = ctx.graph.valueExpression(step.key) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-key-provenance");
    const raw = try lowerExpr(ctx, expression);
    const slot = ctx.freshTemp();
    try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = raw, .ty = .i64 });
    try emitIndexBoundsTrap(ctx, slot, step.extent);
    return .{ .local = slot };
}

fn lowerAggregateAccess(
    ctx: *LowerCtx,
    application: *const semantic_graph.ApplicationFact,
    consumption: types.ReturnConsumption,
) Error!dnir.Value {
    var steps: std.ArrayListUnmanaged(AggregateAccessStep) = .empty;
    defer steps.deinit(ctx.alloc);
    var seen: std.AutoHashMapUnmanaged(semantic_graph.id, void) = .empty;
    defer seen.deinit(ctx.alloc);
    try collectAggregateAccessPath(ctx, application, &steps, &seen);
    if (steps.items.len < 2)
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-access-depth");
    const root_aggregate = steps.items[0].subject;
    if (ctx.graph.aggregateProducer(root_aggregate) != null)
        return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-access-root");
    const base = try aggregateBase(ctx, root_aggregate);

    var prefix: dnir.Value = .void;
    for (steps.items, 0..) |step, i| {
        const start: u32 = @intCast(ctx.instrs.items.len);
        const key = try aggregateKey(ctx, step);
        if (i == 0) {
            const slot = ctx.freshTemp();
            var instruction: dnir.Instr = .{
                .op = .store_local,
                .result = slot,
                .lhs = key,
            };
            try setAggregateLineage(ctx, step, start, &instruction);
            try ctx.emit(instruction);
            prefix = .{ .local = slot };
            continue;
        }

        const biased = ctx.freshTemp();
        try ctx.emit(.{ .op = .binop, .result = biased, .binop = .sub, .lhs = prefix, .rhs = .{ .i64 = 1 } });
        const scaled = ctx.freshTemp();
        try ctx.emit(.{ .op = .binop, .result = scaled, .binop = .mul, .lhs = .{ .temp = biased }, .rhs = .{ .i64 = step.extent } });
        const offset = ctx.freshTemp();
        try ctx.emit(.{ .op = .binop, .result = offset, .binop = .add, .lhs = .{ .temp = scaled }, .rhs = key });

        const last = i + 1 == steps.items.len;
        if (last) {
            if (step.result_descriptor != .i64)
                return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-leaf-descriptor");
            const result = ctx.freshTemp();
            var instruction: dnir.Instr = .{
                .op = .load_index,
                .result = result,
                .lhs = .{ .temp = base },
                .rhs = .{ .temp = offset },
                .ty = .i64,
            };
            try setAggregateLineage(ctx, step, start, &instruction);
            try ctx.emit(instruction);
            return if (consumption == .discard) .void else .{ .temp = result };
        }
        const slot = ctx.freshTemp();
        var instruction: dnir.Instr = .{
            .op = .store_local,
            .result = slot,
            .lhs = .{ .temp = offset },
        };
        try setAggregateLineage(ctx, step, start, &instruction);
        try ctx.emit(instruction);
        prefix = .{ .local = slot };
    }
    return invalidGraphFacts(ctx.diagnostic, @src(), "aggregate-access-result");
}

fn lowerExprCons(
    ctx: *LowerCtx,
    expr: *const Expr,
    consumption: types.ReturnConsumption,
) Error!dnir.Value {
    // A PLACE ACCESS IS NOT AN APPLICATION. `t(2)` on a module-scope collection
    // reads a location; the graph could not tell that from a relation call
    // because it had no places, which is why the refusal below fired on it.
    if (placeFold(ctx, expr)) |folded| return folded;
    if (ctx.occurrences.get(expr)) |application| {
        if (ctx.graph.aggregateAccess(application.application) != null)
            return lowerAggregateAccess(ctx, application, consumption);
    }
    if (applicationNeedsGraphOccurrence(ctx, expr)) {
        return refuseMissingApplication(ctx, @src(), expr);
    }
    return switch (expr.*) {
        .nil => .{ .i64 = 0 },
        .int_lit => |i| .{ .i64 = i.val },
        .float_lit => |fl| .{ .f64 = fl.val },
        .true_lit => .{ .i64 = 1 },
        .false_lit => .{ .i64 = 0 },
        .quoted => |s| .{ .str = s.val },
        // AN INJECTED WORLD ADDS REACH; IT NEVER TAKES A NAME.
        //
        // The world test used to run BEFORE `ctx.locals`, so any program that
        // bound `io`, `os` or `std` got the world DESCRIPTOR — whose address is
        // what a `.str` value carries — returned in place of its own value:
        //
        //     io: i64 = 5 ; io                 direct 56, C 5
        //     io: i64 = 5 ; io + 0             direct 64, C 5   (tracks layout)
        //     f: i64 = (io: i64) io + 1 ; f(4) direct 121, C 5
        //     zz: i64 = 5 ; zz                 direct 5,  C 5   (control)
        //
        // Compiled clean, ran, and answered a pointer. Sema resolves these
        // correctly — the two backends disagreeing is what localized it here.
        // Binding order is the whole fix: a local, a parameter or a module
        // constant is a NAME THAT IS TAKEN, and only a free name can still mean
        // the world. `tryLowerRelationEdgeCall` already asks the question this
        // way (`if (ctx.locals.contains("os")) return null;`).
        .name => |n| blk: {
            // A FUSED BODY RELATION'S RESULT NAME, standing for a literal
            // element. Asked FIRST because it is an active shadow: it is
            // non-empty only inside one collection relation's body, and inside
            // it the name means the element and nothing else.
            if (ctx.fused_literals.get(n.ident)) |element| break :blk dnir.Value{ .i64 = element };
            if (ctx.locals.get(n.ident)) |slot| break :blk dnir.Value{ .local = slot };
            // A WRITTEN module-scope binding is READ FROM ITS STORAGE, never
            // folded. `ctx.locals` still wins: a parameter or local of the same
            // name shadows the global, exactly as it shadows the world below.
            if (ctx.module_globals.types.get(n.ident)) |ty| {
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .load_global, .result = t, .field = n.ident, .ty = ty });
                if (ty == .str) try ctx.str_slots.put(ctx.alloc, t, {});
                break :blk dnir.Value{ .temp = t };
            }
            if (ctx.module_consts.ints.get(n.ident)) |mv| break :blk dnir.Value{ .i64 = mv };
            if (ctx.module_consts.strs.get(n.ident)) |sv| break :blk dnir.Value{ .str = sv };
            if (std.mem.eql(u8, n.ident, "io") or std.mem.eql(u8, n.ident, "os") or
                std.mem.eql(u8, n.ident, "std"))
            {
                noteHostTaint(ctx, .ast_name, "world_symbol", null);
                break :blk dnir.Value{ .str = n.ident };
            }
            return bailWith(ctx.diagnostic, @src(), n.ident);
        },
        .binop => |b| if (b.op == .@"and" or b.op == .@"or")
            try lowerShortCircuit(ctx, b.op, b.lhs, b.rhs)
        else
            try lowerBinop(ctx, b.op, b.lhs, b.rhs),
        .if_expr => |ie| try lowerIfExpr(ctx, ie),
        .unop => |u| blk: {
            if (u.op == .neg and u.operand.* == .int_lit) {
                break :blk dnir.Value{ .i64 = -u.operand.int_lit.val };
            }
            // `#s` on a known `str` is C `strlen` — a plain libc call, no
            // dynamic length probe and no boxed value. Any other `#` operand
            // needs the dynamic runtime and stays outside the direct subset.
            if (u.op == .len and exprIsStr(ctx, u.operand)) {
                const arg = try lowerExpr(ctx, u.operand);
                try ensureExtern(ctx, "string", "len", "strlen");
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .call_extern, .result = t, .callee = "strlen", .lhs = arg });
                break :blk dnir.Value{ .temp = t };
            }
            if (u.op == .not) {
                const operand = try lowerExpr(ctx, u.operand);
                const t = ctx.freshTemp();
                try ctx.emit(.{
                    .op = .binop,
                    .result = t,
                    .binop = .eq,
                    .lhs = operand,
                    .rhs = .{ .i64 = 0 },
                    .ty = .any,
                });
                break :blk dnir.Value{ .temp = t };
            }
            // PREFIX `~` — bitwise NOT. `~x == x ^ -1` over the FULL i64
            // domain, with no range, sign or known-bits fact required, so the
            // capability is expressed in the tag set DNIR already has rather
            // than by adding a unary tag that every consumer would have to
            // learn. `native_backend.constBinopRealization` recognises the
            // `-1` operand and selects the single instruction AArch64 has for
            // it (`mvn`, i.e. `orn xd, xzr, xn`), so this costs one
            // instruction, not a materialised constant plus an `eor`.
            //
            // An integral operand is REQUIRED. `~` on text or on an f64 has no
            // meaning this backend can realize, and `exprIsIntegral` already
            // excludes both; refusing here keeps the wrong answer from being
            // computed on a bit pattern that is an address or a mantissa.
            if (u.op == .bnot and exprIsIntegral(ctx, u.operand)) {
                const operand = try lowerExpr(ctx, u.operand);
                const t = ctx.freshTemp();
                try ctx.emit(.{
                    .op = .binop,
                    .result = t,
                    .binop = .bxor,
                    .lhs = operand,
                    .rhs = .{ .i64 = -1 },
                    // The SAME width the infix spelling `x ~ -1` would get:
                    // `binopResultWidth(.bxor, x, -1)` joins `uint32` with the
                    // literal's `int32` to `uint32`, and `bxor` refits unless
                    // BOTH sides are canonical at that width — which `-1` is
                    // not. Anything else stays 64-bit, where `~` is the plain
                    // complement.
                    .ty = if (exprCRank(ctx, u.operand) == .uint32) RT.u32 else RT.any,
                });
                break :blk dnir.Value{ .temp = t };
            }
            return bailWith(ctx.diagnostic, @src(), @tagName(u.op));
        },
        .index => |ix| blk: {
            if (argv(ix.obj)) {
                try ensureExtern(ctx, "os", "args", "idol_os_arg");
                const i = try lowerExpr(ctx, ix.key);
                const ty = osResult("args");
                if (consumption == .discard) {
                    try ctx.emit(.{ .op = .call_extern, .callee = "idol_os_arg", .lhs = i, .ty = ty });
                    break :blk .void;
                }
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .call_extern, .result = t, .callee = "idol_os_arg", .lhs = i, .ty = ty });
                break :blk .{ .temp = t };
            }
            if (env(ix.obj)) {
                try ensureExtern(ctx, "os", "env", "getenv");
                const k = try lowerExpr(ctx, ix.key);
                const ty = osResult("env");
                if (consumption == .discard) {
                    try ctx.emit(.{ .op = .call_extern, .callee = "getenv", .lhs = k, .ty = ty });
                    break :blk .void;
                }
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .call_extern, .result = t, .callee = "getenv", .lhs = k, .ty = ty });
                break :blk .{ .temp = t };
            }
            // `t[2]` on a positional table resolves to the element's own local,
            // so a constant index costs nothing at runtime. A non-constant index
            // needs a base pointer and computed offset — the native table
            // milestone — and is refused rather than mis-lowered.
            // §2: `s[i]` IS the byte, 0-based — there is no string
            // library, only a string descriptor. This is the CANONICAL byte
            // access, and it did not lower while the deny-listed
            // `string.byte(s, i)` did. Sixth instance of that pattern this
            // session, after string.byte, s:byte, @{…}, mem and math.
            //
            // The index is emitted as `i + 1` because the backend's byte load
            // computes `base + (idx - 1)` for string.byte's 1-based convention.
            // Normalizing here keeps ONE origin in the backend rather than
            // giving it a second — the same decision the byte STORE required,
            // where two origins on one opcode would be a wrong address.
            // A DETERMINED table read at a compile-time index is its element,
            // whatever the table's extent and whatever realization the rest of
            // the function forced on it. Checked first, so the answer does not
            // depend on which of the three storage paths below would have run.
            if (try constTableRead(ctx, expr)) |v| break :blk v;
            if (exprIsStr(ctx, ix.obj)) {
                const sbase = try lowerExpr(ctx, ix.obj);
                const raw = try lowerExpr(ctx, ix.key);
                const one = ctx.freshTemp();
                try ctx.emit(.{ .op = .binop, .result = one, .binop = .add, .lhs = raw, .rhs = .{ .i64 = 1 } });
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .load_index, .result = t, .lhs = sbase, .rhs = .{ .temp = one } });
                break :blk dnir.Value{ .temp = t };
            }
            if (ix.obj.* != .name) return bail(ctx.diagnostic, @src());
            // A memory-backed table indexes for real: one scaled load, constant
            // or not. This is the path that makes a shared token array work.
            if (ptrSlotOf(ctx, ix.obj)) |base| {
                const idx = try guardedTableIndex(ctx, ix.obj.name.ident, ix.key);
                const t = ctx.freshTemp();
                try ctx.emit(.{
                    .op = .load_index,
                    .ty = .i64,
                    .result = t,
                    .lhs = .{ .local = base },
                    .rhs = idx,
                });
                break :blk dnir.Value{ .temp = t };
            }
            const n = intLiteralStep(ix.key) orelse
                break :blk try lowerDynamicIndex(ctx, ix.obj.name.ident, ix.key);
            const key = try std.fmt.allocPrint(ctx.alloc, "{s}.{d}", .{ ix.obj.name.ident, n });
            defer ctx.alloc.free(key);
            const slot = ctx.locals.get(key) orelse return bail(ctx.diagnostic, @src());
            break :blk dnir.Value{ .local = slot };
        },
        .call => try lowerCall(ctx, expr, consumption),
        .method_call => try lowerSubjectCall(ctx, expr, consumption),
        .field => try lowerField(ctx, expr),
        .macro_call => |mc| {
            if (dnir_hardware.parseIntrinsic(mc.name)) |hw| {
                return try lowerHwIntrinsic(ctx, hw, mc.args);
            }
            return bail(ctx.diagnostic, @src());
        },
        else => bailWith(ctx.diagnostic, @src(), @tagName(expr.*)),
    };
}

/// Normalize the canonical receiver face `a:m(x)` into the call form the rest
/// of this file already lowers.
///
/// ONE EDGE: `a:m(x)` and `m(a, x)` are the same edge written from the two ends
/// — declaration spelling versus call spelling. Rather than teach every arm
/// below about receivers, the face is rewritten once here and every existing
/// lowering applies unchanged. Without it, `.method_call` fell into the `else`
/// bail, so the spelling the canon mandates everywhere (rule 6, FACE-CALL) was
/// the one shape that could not lower natively — `s:byte(1)` bailed while
/// `string.byte(s, 1)`, which the deny list forbids, lowered to an indexed load.
///
/// String primitives rebuild the `string.m(a, …)` field form specifically,
/// because their lowering is an indexed load / length scan keyed on that
/// shape, not a call to a symbol that exists.
fn faceAsCall(ctx: *LowerCtx, expr: *const ast.Expr) Error!*const ast.Expr {
    const mc = expr.method_call;
    noteHostTaint(ctx, .method_string, "faceAsCall.method", null);
    const args = try ctx.alloc.alloc(*ast.Expr, mc.args.len + 1);
    args[0] = mc.obj;
    @memcpy(args[1..], mc.args);

    const func = try ctx.alloc.create(ast.Expr);
    const string_method =
        std.mem.eql(u8, mc.method, "sub") or
        std.mem.eql(u8, mc.method, "match") or
        std.mem.eql(u8, mc.method, "byte") or
        std.mem.eql(u8, mc.method, "len");
    if (exprIsStr(ctx, mc.obj) or string_method) {
        const recv = try ctx.alloc.create(ast.Expr);
        recv.* = .{ .name = .{ .loc = mc.loc, .ident = "string" } };
        func.* = .{ .field = .{ .loc = mc.loc, .obj = recv, .field = mc.method } };
    } else if (subject_home.homeOfWithReceiver(mc.method, exprIsStr(ctx, mc.obj))) |owner| {
        // The subject-first face rebuilt as `home.relation(subject, …)`, the
        // same node the operation-first face builds. One edge, two spellings.
        const recv = try ctx.alloc.create(ast.Expr);
        recv.* = .{ .name = .{ .loc = mc.loc, .ident = subject_home.homeName(owner) } };
        func.* = .{ .field = .{ .loc = mc.loc, .obj = recv, .field = mc.method } };
    } else {
        func.* = .{ .name = .{ .loc = mc.loc, .ident = mc.method } };
    }

    const call = try ctx.alloc.create(ast.Expr);
    call.* = .{ .call = .{ .loc = mc.loc, .func = func, .args = args } };
    return call;
}

fn applicationResultIs(
    ctx: *const LowerCtx,
    expr: *const Expr,
    expected: std.meta.Tag(types.ResolvedType),
) bool {
    const descriptor = applicationFirstResultDescriptor(ctx, expr) orelse return false;
    return std.meta.activeTag(descriptor) == expected;
}

fn applicationFirstResultDescriptor(ctx: *const LowerCtx, expr: *const Expr) ?types.ResolvedType {
    const application = ctx.occurrences.get(expr) orelse return null;
    const results = ctx.graph.applicationResults(application.application) orelse return null;
    if (results.len == 0) return null;
    return (ctx.graph.get(results[0]) orelse return null).descriptor;
}

fn applicationDescriptor(ctx: *const LowerCtx, expr: *const Expr) ?types.ResolvedType {
    const application = ctx.occurrences.get(expr) orelse return null;
    return ctx.graph.applicationDescriptor(application.application);
}

fn publishedDescriptor(
    ctx: *const LowerCtx,
    application: *const semantic_graph.ApplicationFact,
) Error!types.ResolvedType {
    return ctx.graph.applicationDescriptor(application.application) orelse
        invalidGraphFacts(ctx.diagnostic, @src(), "application-result-descriptor");
}

const CheckedScalarOperand = struct {
    value: semantic_graph.id,
    expression: *Expr,
    descriptor: types.ResolvedType,
};

fn exprBinopDepth(expr: *const ast.Expr) usize {
    return switch (expr.*) {
        .binop => |b| 1 + @max(exprBinopDepth(b.lhs), exprBinopDepth(b.rhs)),
        else => 0,
    };
}

fn nameIsCurrentParam(ctx: *const LowerCtx, name: []const u8) bool {
    const slot = ctx.locals.get(name) orelse return false;
    for (ctx.self_param_slots) |param_slot| {
        if (param_slot == slot) return true;
    }
    return false;
}

fn checkedOperandAdmitsDirectGp(ctx: *const LowerCtx, expr: *const Expr) bool {
    if (ctx.occurrences.get(expr) != null) return true;
    return switch (expr.*) {
        .int_lit, .true_lit, .false_lit, .float_lit => true,
        .binop => exprBinopDepth(expr) <= 1,
        .name => |n| nameIsCurrentParam(ctx, n.ident),
        else => false,
    };
}

/// The record an operand NAMES, when that name's fields are already resident in
/// exploded slots — or null when the operand is not one.
///
/// THIS ASKS `scalarRecordForName`, IT DOES NOT RE-DERIVE IT. That function is
/// already the authority on "this name is a record stored as one local per
/// field", and the unchecked call path has expanded record arguments through it
/// for as long as it has existed (`emitScalarCallArgs`). A second predicate
/// here would be a second opinion about the same fact, and the two ends of a
/// call disagreeing about how many registers a record occupies is a wrong
/// ANSWER rather than a refusal — both sides still compile.
fn homogeneousF64Record(rec: dnir.RecordDesc) bool {
    if (rec.fields.len == 0 or rec.kinds.len != rec.fields.len) return false;
    for (rec.kinds) |k| {
        if (k != .f64) return false;
    }
    return true;
}

/// Record operand selected from graph-published descriptor/shape facts.
fn recordForGraphOperand(ctx: *const LowerCtx, value: semantic_graph.id) ?dnir.RecordDesc {
    if (ctx.graph.descriptorShape(value, 0)) |shape| {
        for (ctx.records) |rec| {
            if (rec.semantic_shape == shape and !homogeneousF64Record(rec) and
                rec.fields.len > 0 and rec.fields.len <= max_reg_record_fields and
                checkedRecordResultSupported(rec))
            {
                return rec;
            }
        }
    }
    const node = ctx.graph.get(value) orelse return null;
    const descriptor = node.descriptor orelse return null;
    const rec = recordForDescriptor(ctx.records, descriptor, ctx.graph) orelse return null;
    if (homogeneousF64Record(rec) or rec.fields.len > max_reg_record_fields) return null;
    return rec;
}

fn operandRecordStorage(ctx: *LowerCtx, operand: CheckedScalarOperand) ?dnir.RecordDesc {
    return recordForGraphOperand(ctx, operand.value);
}

/// Does this operand name a record AT ALL — including one whose fields the
/// argument registers cannot carry?
///
/// THIS IS A DIFFERENT FACT FROM `operandRecordStorage`, NOT A SECOND OPINION
/// ABOUT IT, and the difference is exactly the set that must still be REFUSED.
/// An f64 record is the live case: its fields are resident under the same
/// "name.field" keys, but `scalarRecordForName` declines it because the
/// homogeneous-float aggregate is a different ABI. Without this the name falls
/// through to the scalar path, which stages the record's OWN slot — a slot that
/// never holds a value — and the backend reports `DNB007 local 0 has no
/// register` instead of naming the operand law. Measured: that is precisely
/// what happened when this predicate was deleted rather than narrowed.
fn operandNamesRecord(ctx: *LowerCtx, expr: *const Expr) bool {
    if (expr.* != .name) return false;
    for (ctx.records) |rec| {
        if (!homogeneousF64Record(rec)) continue;
        if (recordFieldsPresent(ctx, expr.name.ident, rec)) return true;
    }
    return false;
}


fn checkedScalarFieldProjection(
    ctx: *const LowerCtx,
    expr: *const Expr,
) ?types.ResolvedType {
    if (expr.* != .field or expr.field.obj.* != .name) return null;
    var buf: [512]u8 = undefined;
    const fk = std.fmt.bufPrint(&buf, "{s}.{s}", .{ expr.field.obj.name.ident, expr.field.field }) catch return null;
    if (ctx.locals.get(fk)) |slot| {
        if (ctx.str_slots.contains(slot)) return .str;
        if (ctx.f64_slots.contains(slot)) return .f64;
        if (ctx.bool_slots.contains(slot)) return .bool;
        if (ctx.ptr_slots.contains(slot)) return physical_pointer;
        if (ctx.narrow_slots.get(slot)) |ty| return ty;
        return .any;
    }
    if (recordFieldKindForParam(ctx, expr.field.obj.name.ident, expr.field.field)) |kind| {
        return switch (kind) {
            .str => .str,
            .f64 => .f64,
            .i64 => .any,
        };
    }
    return null;
}

fn checkedScalarOperand(
    ctx: *const LowerCtx,
    value: semantic_graph.id,
) Error!CheckedScalarOperand {
    const node = ctx.graph.get(value) orelse return invalidGraphFacts(ctx.diagnostic, @src(), "application-value");
    const descriptor = node.descriptor orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-descriptor");
    const raw = node.ast_ref orelse return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-provenance");
    const expression: *Expr = @ptrCast(@alignCast(raw));
    if (expression.* == .table) {
        return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-abi");
    }
    var effective = descriptor;
    switch (descriptor) {
        .i32, .i64, .bool, .str, .f64, .pointer, .any => {},
        .enum_type => |e| {
            for (e.variants) |v| {
                if (v.payload != null) return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-abi");
            }
        },
        .@"struct" => {
            if (checkedScalarFieldProjection(ctx, expression)) |field_ty| {
                effective = field_ty;
            } else if (expression.* == .name) {
                if (ctx.locals.get(expression.name.ident)) |_| {
                    effective = .any;
                } else if (recordForDescriptor(ctx.records, descriptor, ctx.graph)) |rec| {
                    if (rec.fields.len == 0) {
                        return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-abi");
                    }
                    effective = .any;
                } else {
                    effective = .any;
                }
            } else if (recordForDescriptor(ctx.records, descriptor, ctx.graph)) |rec| {
                if (rec.fields.len == 0) {
                    return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-abi");
                }
                if (expression.* == .field) {
                    effective = checkedScalarFieldProjection(ctx, expression) orelse .any;
                }
            } else if (expression.* == .field) {
                effective = checkedScalarFieldProjection(ctx, expression) orelse .any;
            } else {
                return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-abi");
            }
        },
        .table_type => {
            // A local table binding (`lx: lexer = …`) crosses home as one opaque
            // pointer operand — same treatment struct locals already get above.
            if (expression.* == .name and ctx.locals.get(expression.name.ident) != null) {
                effective = .any;
            } else {
                return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-abi");
            }
        },
        else => return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-abi"),
    }
    return .{
        .value = value,
        .expression = expression,
        .descriptor = effective,
    };
}

fn checkedScalarResult(diagnostic: *Diagnostic, descriptor: types.ResolvedType) Error!void {
    switch (descriptor) {
        .i8,
        .i16,
        .i32,
        .i64,
        .u8,
        .u16,
        .u32,
        .u64,
        .f32,
        .f64,
        .bool,
        .str,
        .pointer,
        .void,
        .any,
        .nil,
        => {},
        .@"struct" => |s| {
if (types.nominalRepr(s.name)) |nr| {
                if (types.nominalReprAdmissible(nr)) return;
            }
            return invalidGraphFacts(diagnostic, @src(), "application-result-abi");
        },
        else => return invalidGraphFacts(diagnostic, @src(), "application-result-abi"),
    }
}

/// Project the semantic subject, when present, followed by position-ordered
/// arguments. Subject absence stays absence; it is not reconstructed as
/// argument zero for operation-first source faces.
fn checkedScalarOperands(
    ctx: *LowerCtx,
    application: *const semantic_graph.ApplicationFact,
    storage: *[max_direct_scalar_args]CheckedScalarOperand,
    include_subject: bool,
) Error![]const CheckedScalarOperand {
    var count: usize = 0;
    if (include_subject) {
        if (ctx.graph.applicationSubject(application.application)) |subject| {
            storage[count] = try checkedScalarOperand(ctx, subject);
            count += 1;
        }
    }
    const arguments = ctx.graph.applicationArguments(application.application) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "application-argument-pack");
    for (arguments) |argument| {
        if (count >= storage.len) return invalidGraphFacts(ctx.diagnostic, @src(), "application-argument-pack");
        storage[count] = try checkedScalarOperand(ctx, argument);
        count += 1;
    }
    return storage[0..count];
}

fn checkedApplicationResult(
    ctx: *const LowerCtx,
    application: *const semantic_graph.ApplicationFact,
) Error!semantic_graph.id {
    const results = ctx.graph.applicationResults(application.application) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "application-result-pack");
    if (results.len != 1) return invalidGraphFacts(ctx.diagnostic, @src(), "application-result-pack");
    return results[0];
}

fn checkedGpPackResultType(
    ctx: *const LowerCtx,
    value: semantic_graph.id,
) Error!RT {
    const descriptor = (ctx.graph.get(value) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "application-result-member")).descriptor orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "application-result-descriptor");
    return switch (descriptor) {
        .i8,
        .i16,
        .i32,
        .i64,
        .u8,
        .u16,
        .u32,
        .u64,
        .bool,
        .str,
        .pointer,
        => descriptor,
        else => invalidGraphFacts(ctx.diagnostic, @src(), "application-result-abi"),
    };
}

/// How many argument slots the operands actually occupy, and whether they are
/// the floating file. THE COUNT IS NOT `operands.len`: one semantic operand may
/// realize as several registers, which is the whole point of the record case
/// below.
const StagedOperands = struct {
    count: usize,
    floating: bool,
};

fn evaluateCheckedScalarOperands(
    ctx: *LowerCtx,
    operands: []const CheckedScalarOperand,
    values: *[max_direct_scalar_args]dnir.Value,
) Error!StagedOperands {
    var fp_count: usize = 0;
    var count: usize = 0;
    for (operands) |operand| {
        // ONE SEMANTIC VALUE, A CONSUMER-DIRECTED REALIZATION. A record operand
        // is not materialized into an aggregate and it is not given an address:
        // this consumer wants scalar fields in registers, so the fields are what
        // crosses. Nothing is stored, nothing is copied, and no struct exists.
        //
        // The fields are ALREADY resident, one local per field, keyed
        // "name.field" — the same storage `p.a` reads and the same storage
        // `lowerRecordReturn` gathers from for `return p`. So this arm adds no
        // representation; it spends the one that is already there.
        //
        // DESCRIPTOR ORDER IS THE CONTRACT, and it is the same order the callee
        // homes its parameter from (`rec.fields`, one register each). The two
        // ends read the same list, which is why they cannot drift.
        if (operandRecordStorage(ctx, operand)) |rec| {
            if (rec.fields.len > max_reg_record_fields) {
                if (operand.expression.* != .name) {
                    return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-abi");
                }
                const slot = ctx.locals.get(operand.expression.name.ident) orelse
                    return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-abi");
                if (!ctx.ptr_slots.contains(slot)) {
                    return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-abi");
                }
                values[count] = .{ .local = slot };
                count += 1;
                continue;
            }
            // THE REGISTER FILE IS THE BOUND, and it is the same bound the
            // CALLEE applies when it homes the parameter (`functionEligible`
            // refuses a record parameter past `max_reg_record_fields`, because
            // record fields have no stack-argument extension). Stating it here
            // in the same terms is what keeps a record that the callee would
            // refuse from being staged by the caller as if it fit.
            if (count + rec.fields.len <= max_reg_record_fields) {
                for (rec.fields) |fname| {
                    const key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ operand.expression.name.ident, fname });
                    defer ctx.alloc.free(key);
                    const slot = ctx.locals.get(key) orelse
                        return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-abi");
                    values[count] = .{ .local = slot };
                    count += 1;
                }
                continue;
            }
            return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-abi");
        }
        // A RECORD-DESCRIPTOR OPERAND WITH NO RESIDENT FIELDS IS REFUSED BY
        // NAME, never lowered as if it were a scalar. `checkedScalarOperand`
        // admits a record whose SHAPE fits the argument registers; whether its
        // fields are actually resident is a different fact, and only the
        // storage above can answer it. A record produced straight into a call
        // (`take(mk(1))`) has a backend record region rather than exploded
        // locals, so it lands here — refused, with the operand law named.
        if (operand.descriptor == .@"struct") {
            if (operand.expression.* == .name) {
                if (try lowerOpaqueRecordLocalArg(ctx, operand.expression)) |materialized| {
                    values[count] = materialized;
                    count += 1;
                    continue;
                }
            }
            return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-abi");
        }
        // AND A RECORD THE ARGUMENT REGISTERS CANNOT CARRY IS STILL REFUSED BY
        // NAME — an f64 record is the live case. Its fields are resident, so it
        // looks like the expandable case from every angle except the one that
        // matters: it is a homogeneous float aggregate with a different ABI.
        // Falling through would stage the record's own slot, which holds no
        // value.
        if (operandNamesRecord(ctx, operand.expression)) {
            return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-abi");
        }
        if (count >= values.len) {
            return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-abi");
        }
        if (try lowerOpaqueRecordLocalArg(ctx, operand.expression)) |materialized| {
            values[count] = materialized;
            count += 1;
            continue;
        }
        values[count] = try lowerExprCons(ctx, operand.expression, .single);
        if (operand.descriptor == .f64) fp_count += 1;
        count += 1;
    }
    // Only the eight FP argument registers (v0..v7) are marshaled; wide integer
    // relations get the stack-arg extension, floating-point ones do not.
    if (fp_count == count and count > 8) {
        return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-abi");
    }
    return .{ .count = count, .floating = fp_count != 0 and fp_count == count };
}

fn stageCheckedScalarOperands(
    ctx: *LowerCtx,
    operands: []const CheckedScalarOperand,
    values: []const dnir.Value,
) Error!void {
    var gp: u32 = 0;
    var fp: u32 = 0;
    for (operands, values) |operand, value| {
        if (operand.descriptor == .f64) {
            if (fp >= 8) return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-abi");
            try ctx.emit(.{ .op = .fp_mov_arg, .result = fp, .lhs = value });
            fp += 1;
        } else {
            if (gp >= max_direct_scalar_args) return invalidGraphFacts(ctx.diagnostic, @src(), "application-operand-abi");
            try ctx.emit(.{ .op = .mov_arg, .result = gp, .lhs = value });
            gp += 1;
        }
    }
}

/// Realize an ordered graph result pack directly in ABI result registers.
/// `demanded` is a prefix because binding adjustment preserves Lua/Idol pack
/// order; undemanded members retain their ABI positions but gain no DNIR temp.
fn lowerCheckedPackCall(
    ctx: *LowerCtx,
    application: *const semantic_graph.ApplicationFact,
    demanded: usize,
    out_temps: *[max_reg_record_fields]?u32,
) Error!void {
    bindOccurrence(ctx.diagnostic, ctx.graph, application.application);
    const results = ctx.graph.applicationResults(application.application) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "application-result-pack");
    if (results.len <= 1 or results.len > max_reg_record_fields or demanded > results.len) {
        return invalidGraphFacts(ctx.diagnostic, @src(), "application-result-abi");
    }
    const target = try applicationTarget(ctx, application);
    const relation = try applicationRelation(ctx, application);
    const callee = try linkageForTarget(ctx, target);
    if (ctx.graph.foreignHome(target)) |foreign_home| {
        try ensureExtern(ctx, foreign_home, callee, callee);
    }

    var operand_storage: [max_direct_scalar_args]CheckedScalarOperand = undefined;
    const raw_operands = try checkedScalarOperands(ctx, application, &operand_storage, true);
    const operands = raw_operands;
    var values: [max_direct_scalar_args]dnir.Value = undefined;
    const staged = try evaluateCheckedScalarOperands(ctx, operands, &values);
    const first_ty = try checkedGpPackResultType(ctx, results[0]);
    const direct_gp = operands.len == 1 and staged.count == 1 and
        operands[0].descriptor == .i64 and first_ty == .i64 and
        checkedOperandAdmitsDirectGp(ctx, operands[0].expression);
    const realization_start: u32 = @intCast(ctx.instrs.items.len);
    const stage_n = boundedOperandStageCount(staged, operands);
    if (!direct_gp) try stageCheckedScalarOperands(ctx, operands[0..stage_n], values[0..stage_n]);

    const projected = try ctx.alloc.alloc(dnir.PackResult, results.len);
    errdefer ctx.alloc.free(projected);
    @memset(out_temps, null);
    for (results, 0..) |value, i| {
        const descriptor = try checkedGpPackResultType(ctx, value);
        const temp = if (i < demanded) ctx.freshTemp() else null;
        out_temps[i] = temp;
        projected[i] = .{ .value = value, .temp = temp, .ty = descriptor };
    }
    try ctx.emit(.{
        .op = .call_direct,
        .relation = relation,
        .application = application.application,
        // `value` remains the first member for the compact lineage row. The
        // application id names the authoritative entire result pack, and
        // `pack_results` proves every ordered member against it.
        .value = results[0],
        .subject = ctx.graph.applicationSubject(application.application),
        .target = target,
        .realization_start = realization_start,
        .callee = callee,
        .lhs = if (direct_gp) values[0] else .void,
        .ty = try publishedDescriptor(ctx, application),
        .pack_results = projected,
    });
}

/// Realize one checked scalar application. Source call orientation has already
/// disappeared: relation, subject role, ordered operands, result and occurrence
/// all come from the graph. Physical linkage resolves from the target entity id
/// through the module linkage map — never from relation node names here.
fn lowerCheckedScalarCall(
    ctx: *LowerCtx,
    application: *const semantic_graph.ApplicationFact,
    consumption: types.ReturnConsumption,
) Error!dnir.Value {
    const result_members = ctx.graph.applicationResults(application.application) orelse
        return invalidGraphFacts(ctx.diagnostic, @src(), "application-result-pack");
    if (result_members.len > 1) {
        var temps: [max_reg_record_fields]?u32 = @splat(null);
        const demanded: usize = if (consumption == .discard) 0 else if (consumption == .single) 1 else return invalidGraphFacts(ctx.diagnostic, @src(), "application-result-consumption");
        try lowerCheckedPackCall(ctx, application, demanded, &temps);
        return if (temps[0]) |temp| .{ .temp = temp } else .void;
    }
    bindOccurrence(ctx.diagnostic, ctx.graph, application.application);
    const relation = try applicationRelation(ctx, application);
    const target = try applicationTarget(ctx, application);
    const callee = try linkageForTarget(ctx, target);
    // A CROSS-HOME CALL IS A RELOCATION, NOT A BRANCH. Nothing in this module
    // defines the symbol, so `patchCalls` would find it neither among the
    // defined symbols nor among the externs and report DNB007 `undefined
    // symbol` — the correct observation with no way to act on it. Registering
    // the extern here is the only place that knows the target is foreign.
    if (ctx.graph.foreignHome(target)) |h| {
        try ensureExtern(ctx, h, callee, callee);
    }
    const descriptor = try publishedDescriptor(ctx, application);
    if (try checkedRecordForApplication(ctx, application)) |record| {
        return try lowerCheckedRecordCall(ctx, application, record, consumption);
    }
    try checkedScalarResult(ctx.diagnostic, descriptor);

    var operand_storage: [max_direct_scalar_args]CheckedScalarOperand = undefined;
    const raw_operands = try checkedScalarOperands(ctx, application, &operand_storage, true);
    const operands = raw_operands;
    var values: [max_direct_scalar_args]dnir.Value = undefined;
    const staged = try evaluateCheckedScalarOperands(ctx, operands, &values);
    const realization_start: u32 = @intCast(ctx.instrs.items.len);
    // Admit only the fixed-width integer contract with byte-equivalence proof.
    // Other general-register descriptors remain staged until their result and
    // operand laws have the same focused control.
    //
    // `staged.count == 1` is what keeps a record out of this path without
    // naming records here: the fast path hands ONE value straight to
    // `call_direct.lhs` and skips staging entirely, so any operand that
    // realized as more than one register must not reach it.
    const direct_gp = operands.len == 1 and
        staged.count == 1 and
        operands[0].descriptor == .i64 and
        descriptor == .i64 and
        checkedOperandAdmitsDirectGp(ctx, operands[0].expression);
    // A record operand is STAGED AS ITS FIELDS by `evaluateCheckedScalarOperands`
    // above, which refuses by name anything it could not expand. The loop that
    // stood here refused EVERY record equally — including the ones the argument
    // registers already hold perfectly well, and which the unchecked path had
    // been passing that way all along.
    //
    // A scalar local passed as an operand (`word(before)` where `before` is a
    // body binding) is safe for the same reason a record field is: any body
    // containing a call spills all GP locals to the stack frame
    // (`planGpStackLocals`, gate_spill_all_locals = body_has_call), so the
    // operand load/reload survives the call's caller-saved clobber.
    const stage_n = boundedOperandStageCount(staged, operands);
    if (!direct_gp) try stageCheckedScalarOperands(ctx, operands[0..stage_n], values[0..stage_n]);
    const has_result = consumption != .discard and descriptor != .void;
    const result = if (has_result) ctx.freshTemp() else null;
    const value = try checkedApplicationResult(ctx, application);
    try ctx.emit(.{
        .op = .call_direct,
        .relation = relation,
        .application = application.application,
        .value = value,
        .subject = ctx.graph.applicationSubject(application.application),
        .target = target,
        .realization_start = realization_start,
        .result = result,
        .callee = callee,
        .lhs = if (direct_gp) values[0] else .void,
        .ty = descriptor,
    });
    return if (result) |temp| .{ .temp = temp } else .void;
}

/// `os.args` — the root-projected argument table, not a call.
fn argv(expr: *const ast.Expr) bool {
    if (expr.* != .field) return false;
    const f = expr.field;
    return f.obj.* == .name and
        std.mem.eql(u8, f.obj.name.ident, "os") and
        std.mem.eql(u8, f.field, "args");
}

/// The `os` world's member edge an anchored node names, or null.
///
/// THE ROSTER IS ASKED, NOT RESTATED — the same shape `isCMember` already uses
/// for the `c` world's roster in this file. Which extern a member lowers to is
/// this file's business; what the member RESULTS IN is the world's, and it is
/// declared in `subject_home.os_dot_members`, which `codegen.expr_type` reads
/// for the very same row. A literal `.str` here and a literal `.str` there
/// would be two authorities on one fact — and they were, and they disagreed:
/// this file gave `arg(i)` `.ty = .str` while the type side answered `any`, so
/// `arg(1):len()` could not resolve a receiver whose realization was already
/// text.
fn osMemberOf(expr: *const ast.Expr) ?subject_home.OsMember {
    if (expr.* != .field) return null;
    const f = expr.field;
    if (f.obj.* != .name) return null;
    if (!std.mem.eql(u8, f.obj.name.ident, "os")) return null;
    return subject_home.osDotMember(f.field);
}

/// The declared result of an `os` member edge, by name. `.any` where the roster
/// declares nothing, which is the honest answer and not a claim.
fn osResult(name: []const u8) RT {
    const m = subject_home.osDotMember(name) orelse return .any;
    return m.result;
}

/// `os.env` — the root-projected environment table, not `getenv` / `os.env()`.
fn env(expr: *const ast.Expr) bool {
    if (expr.* != .field) return false;
    const f = expr.field;
    return f.obj.* == .name and
        std.mem.eql(u8, f.obj.name.ident, "os") and
        std.mem.eql(u8, f.field, "env");
}

/// The KEY of an environment projection used as an assignment TARGET, or null.
///
/// The environment is a PLACE, not only a value, so `env(k)` has to be writable
/// as well as readable. All three spellings that name the same edge reach here:
///
///     env("K")     = v     canonical — `os` is injected, so the anchor adds
///                          nothing (only reachable once sema admits bare `env`)
///     os.env("K")  = v     lawful where the anchor genuinely disambiguates
///     os.env["K"]  = v     legacy bracket accessor
///
/// A LOCAL named `env` or `os` shadows the projection. That guard is not
/// hypothetical: `a[i]` canonicalizes to `a(i)`, so `env(k) = v` is also exactly
/// how a positional table named `env` is written to, and without the check a
/// local table store would be silently rewritten into a `setenv` call.
fn envPlaceKey(ctx: *const LowerCtx, expr: *const ast.Expr) ?*const ast.Expr {
    switch (expr.*) {
        .index => |ix| {
            if (!env(ix.obj)) return null;
            if (ctx.locals.contains("os")) return null;
            return ix.key;
        },
        .call => |c| {
            if (c.args.len != 1) return null;
            if (env(c.func)) return if (ctx.locals.contains("os")) null else c.args[0];
            if (c.func.* == .name and std.mem.eql(u8, c.func.name.ident, "env")) {
                return if (ctx.locals.contains("env")) null else c.args[0];
            }
            return null;
        },
        else => return null,
    }
}

/// `env(k) = v` — POSIX `setenv(k, v, 1)`.
///
/// `setenv` and not `putenv`: `putenv` takes one `"K=V"` string, which would
/// mean building and OWNING a concatenation at run time, and it installs the
/// caller's buffer rather than copying it.
///
/// The overwrite flag is 1, so a write always takes effect. Nothing here treats
/// the empty string specially — `env("K") = ""` sets `K` to the empty value and
/// does NOT remove it. That matters: the READ side currently cannot distinguish
/// absent from empty (both answer `""`, the §17 fake-nil identity written up in
/// idol-native/docs/env-identity.md), and if the write side collapsed the two as
/// well, the distinction would be unrecoverable rather than merely unobservable.
/// REMOVAL is `unsetenv`, a different edge, and is deliberately not spelled as
/// an assignment of `""` here.
fn lowerEnvStore(ctx: *LowerCtx, key_expr: *const ast.Expr, value: *const ast.Expr) Error!void {
    const k = try lowerExprCons(ctx, key_expr, .single);
    const v = try lowerExprCons(ctx, value, .single);
    try ensureExtern(ctx, "os", "setenv", "setenv");
    try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = k });
    try ctx.emit(.{ .op = .mov_arg, .result = 1, .lhs = v });
    try ctx.emit(.{ .op = .mov_arg, .result = 2, .lhs = .{ .i64 = 1 } });
    try ctx.emit(.{ .op = .call_extern, .callee = "setenv", .ty = .i64 });
}

/// `env:remove(k)` — POSIX `unsetenv(k)`. THE REMOVAL EDGE.
///
/// `lowerEnvStore` above states that removal is `unsetenv`, "a different edge,
/// and is deliberately not spelled as an assignment". It had nowhere to point;
/// this is where. The distinction is observable and not stylistic:
///
///     env("K") = ""        K is PRESENT and empty      setenv(K, "", 1)
///     env:remove("K")      K is ABSENT                 unsetenv(K)
///
/// Collapsing them onto `env("K") = nil` would destroy the one distinction the
/// read face already cannot express (the §17 fake-nil identity written up in
/// idol-native/docs/env-identity.md), so the assignment spelling is REFUSED in
/// sema and names this edge in its diagnostic rather than being lowered here.
///
/// `unsetenv` returns int and the result is discarded, exactly as the `setenv`
/// store's is: a store is a statement, not a value.
fn lowerEnvRemove(ctx: *LowerCtx, key_expr: *const ast.Expr) Error!dnir.Value {
    const k = try lowerExprCons(ctx, key_expr, .single);
    try ensureExtern(ctx, "os", "unsetenv", "unsetenv");
    try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = k });
    try ctx.emit(.{ .op = .call_extern, .callee = "unsetenv", .ty = .i64 });
    return .void;
}

/// `os.cwd` — the root-projected working directory, not `getcwd` / `os.cwd()`.
fn cwd(expr: *const ast.Expr) bool {
    if (expr.* != .field) return false;
    const f = expr.field;
    return f.obj.* == .name and
        std.mem.eql(u8, f.obj.name.ident, "os") and
        std.mem.eql(u8, f.field, "cwd");
}

fn lowerStdinRead(
    ctx: *LowerCtx,
    consumption: types.ReturnConsumption,
) Error!dnir.Value {
    _ = consumption;
    try ensureExtern(ctx, "stdin", "read", "idol_io_read_stdin");
    const t = ctx.freshTemp();
    try ctx.emit(.{ .op = .call_extern, .result = t, .callee = "idol_io_read_stdin", .ty = .str });
    return .{ .temp = t };
}

/// `stdin:line()` — one newline-delimited message for a persistent server loop.
/// End of input is the empty string, not a null sentinel (GAP-155).
fn lowerStdinLine(
    ctx: *LowerCtx,
    consumption: types.ReturnConsumption,
) Error!dnir.Value {
    _ = consumption;
    try ensureExtern(ctx, "stdin", "line", "idol_io_read_line");
    const t = ctx.freshTemp();
    try ctx.emit(.{ .op = .call_extern, .result = t, .callee = "idol_io_read_line", .ty = .str });
    return .{ .temp = t };
}

fn lowerSubjectRead(
    ctx: *LowerCtx,
    expr: *const Expr,
    consumption: types.ReturnConsumption,
) Error!dnir.Value {
    _ = consumption;
    const subject = try lowerExpr(ctx, expr.method_call.obj);
    try ensureExtern(ctx, "idol", "read", "idol_io_read_path");
    try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = subject });
    const t = ctx.freshTemp();
    try ctx.emit(.{ .op = .call_extern, .result = t, .callee = "idol_io_read_path", .ty = .str });
    return .{ .temp = t };
}

/// Subject-first `hay:has(needle)` — lowers the held subject and needle directly
/// to a bootstrap extern. No `string.*`, `std.*`, or operation-first rewrite.
fn lowerSubjectHas(
    ctx: *LowerCtx,
    expr: *const Expr,
    consumption: types.ReturnConsumption,
) Error!dnir.Value {
    const mc = expr.method_call;
    if (mc.args.len != 1) return bail(ctx.diagnostic, @src());
    const hay = try lowerExpr(ctx, mc.obj);
    const needle = try lowerExpr(ctx, mc.args[0]);
    try ensureExtern(ctx, "idol", "has", "idol_str_has");
    try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = hay });
    try ctx.emit(.{ .op = .mov_arg, .result = 1, .lhs = needle });
    if (consumption == .discard) {
        try ctx.emit(.{ .op = .call_extern, .callee = "idol_str_has", .ty = .i64 });
        return .void;
    }
    const t = ctx.freshTemp();
    try ctx.emit(.{ .op = .call_extern, .result = t, .callee = "idol_str_has", .ty = .i64 });
    return .{ .temp = t };
}

fn lowerSubjectFind(
    ctx: *LowerCtx,
    expr: *const Expr,
    consumption: types.ReturnConsumption,
) Error!dnir.Value {
    const mc = expr.method_call;
    if (mc.args.len != 3) return bail(ctx.diagnostic, @src());
    const hay = try lowerExpr(ctx, mc.obj);
    const needle = try lowerExpr(ctx, mc.args[0]);
    const start = try lowerExpr(ctx, mc.args[1]);
    const plain = try lowerExpr(ctx, mc.args[2]);
    try ensureExtern(ctx, "idol", "find", "idol_str_find");
    try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = hay });
    try ctx.emit(.{ .op = .mov_arg, .result = 1, .lhs = needle });
    try ctx.emit(.{ .op = .mov_arg, .result = 2, .lhs = start });
    try ctx.emit(.{ .op = .mov_arg, .result = 3, .lhs = plain });
    if (consumption == .discard) {
        try ctx.emit(.{ .op = .call_extern, .callee = "idol_str_find", .ty = .i64 });
        return .void;
    }
    const t = ctx.freshTemp();
    try ctx.emit(.{ .op = .call_extern, .result = t, .callee = "idol_str_find", .ty = .i64 });
    return .{ .temp = t };
}

fn lowerSubjectTail(
    ctx: *LowerCtx,
    expr: *const Expr,
    consumption: types.ReturnConsumption,
) Error!dnir.Value {
    const subject = try lowerExpr(ctx, expr.method_call.obj);
    if (consumption == .discard) {
        try ctx.emit(.{ .op = .call_direct, .callee = "tail", .lhs = subject });
        return .void;
    }
    const t = ctx.freshTemp();
    try ctx.emit(.{ .op = .call_direct, .result = t, .callee = "tail", .lhs = subject });
    return .{ .temp = t };
}

/// COLLECTION-RELATION-ONE — realize `xs:any(p)` as ONE iteration application.
///
/// Answers null when `expr` is not a collection application, so every existing
/// path below is untouched.
///
/// THE QUESTION REACHES REALIZATION INTACT, which is the whole point of having
/// separate relation words (`subject-section-one.md` §4). `any` is EXISTENTIAL,
/// so the emitted shape leaves at the FIRST WITNESS and the elements after it
/// are never examined. An `any` built as `filter` then a non-empty test would
/// answer the same and be a different program.
///
/// THREE REALIZATIONS, ONE QUESTION, chosen from facts already in hand and
/// none of them an iterator:
///
///   extent 0            no iteration at all — the answer is `false`, and the
///                       emitted form is a constant. `protocol-projection-one.md`
///                       §3's "or **nothing**".
///   register-exploded   a SHORT-CIRCUIT CHAIN over the element slots. No loop,
///                       no induction variable, no bounds check, no memory
///                       traffic — the elements are already in slots, so asking
///                       the question costs one predicate and one branch each
///                       until one answers yes.
///   memory-backed       an indexed scan whose body branches OUT of the loop on
///                       the first witness. The early exit is emitted from the
///                       QUESTION; nothing has to rediscover it from a flag.
///
/// Iterator object 0, protocol object 0, vtable 0, indirect dispatch 0,
/// closure 0 — §6's pins, and they hold BY CONSTRUCTION here rather than by
/// later elimination: the body relation is an expression lowered in place with
/// its one result name bound to the element, and no value is ever built for it.
fn lowerCollectionRelation(ctx: *LowerCtx, expr: *const Expr) Error!?dnir.Value {
    const shape = collection_relation.shapeOf(expr) orelse return null;
    // IT NEVER TAKES THE NAME. If the graph resolved this application to a
    // relation, the program declared its own `any` and that declaration owns
    // every call to it — the same rule `worldSubject` follows for `stdout` and
    // `table_apply` follows for `arg`. Both were defects first: a user relation
    // named `arg` silently became an argument read and answered 0 instead of
    // 42, with no diagnostic anywhere. Sema declines the same case for the same
    // reason, and this is the half that matters, because here the wrong answer
    // would COMPILE.
    if (ctx.occurrences.get(expr)) |occurrence| {
        if (ctx.graph.applicationRelation(occurrence.application) != null) return null;
    }
    return switch (shape.question) {
        .any => try lowerAnyRelation(ctx, shape),
    };
}

/// Bind the body relation's single result name to `slot` for the duration of
/// one predicate lowering, and give the name back exactly as it was found.
///
/// A SHADOW, NOT A SCOPE. `subject-section-one.md` §1 requires the body
/// relation to create "no lexical binding, no scope mutation, no implicit
/// identifier" — so an outer `x` must still be an outer `x` after the
/// application, and the check that proves it is `gate/any.id`'s shadow row.
const ResultName = struct {
    ctx: *LowerCtx,
    name: []const u8,
    /// What the name meant OUTSIDE, so it can mean that again afterwards.
    previous: ?u32,
    shadowed_slot: bool = false,
    shadowed_literal: bool = false,

    fn bind(ctx: *LowerCtx, name: []const u8) ResultName {
        return .{ .ctx = ctx, .name = name, .previous = ctx.locals.get(name) };
    }

    /// The element lives in a slot — the loaded or exploded realizations.
    ///
    /// `put` on a key already present keeps the stored key and replaces only
    /// the value, so re-pointing the name at the next element allocates
    /// nothing after the first.
    fn point(self: *ResultName, slot: u32) Error!void {
        if (self.shadowed_slot or self.previous != null) {
            try self.ctx.locals.put(self.ctx.alloc, self.name, slot);
        } else {
            try self.ctx.locals.put(self.ctx.alloc, try self.ctx.alloc.dupe(u8, self.name), slot);
        }
        self.shadowed_slot = true;
    }

    /// The element IS a literal — the determined realization, where the folder
    /// must see an immediate rather than a slot that happens to hold one.
    fn pointLiteral(self: *ResultName, element: i64) Error!void {
        if (self.shadowed_literal) {
            try self.ctx.fused_literals.put(self.ctx.alloc, self.name, element);
        } else {
            try self.ctx.fused_literals.put(self.ctx.alloc, try self.ctx.alloc.dupe(u8, self.name), element);
        }
        self.shadowed_literal = true;
    }

    fn release(self: *ResultName) void {
        if (self.shadowed_literal) {
            if (self.ctx.fused_literals.fetchRemove(self.name)) |entry| self.ctx.alloc.free(entry.key);
            self.shadowed_literal = false;
        }
        if (!self.shadowed_slot) return;
        self.shadowed_slot = false;
        if (self.previous) |slot| {
            self.ctx.locals.put(self.ctx.alloc, self.name, slot) catch {};
            return;
        }
        if (self.ctx.locals.fetchRemove(self.name)) |entry| self.ctx.alloc.free(entry.key);
    }
};

/// EXTENT ZERO IS A FACT, AND `staticTableLen` CANNOT CARRY IT.
///
/// A zero-element positional literal is not `tableIsPositional` (that predicate
/// requires at least one field), so it binds through the record path and no
/// `<name>.len` slot is ever created — `staticTableLen` then answers null, which
/// is the same null a `ptr` PARAMETER answers, and those two are opposite
/// facts. One means "the extent is zero"; the other means "the extent is not
/// known here". Reading the first as the second refuses a question with a
/// trivial answer; reading the second as the first would answer `false` about a
/// table this function has never seen the size of. So the empty binding is
/// identified from the source that stated it, and nothing else is assumed.
fn boundEmptyTable(ctx: *const LowerCtx, name: []const u8) bool {
    const body = ctx.body orelse return false;
    for (body.stmts) |stmt| {
        switch (stmt) {
            .local_decl => |decl| {
                for (decl.names, 0..) |local, i| {
                    if (!std.mem.eql(u8, local.ident, name)) continue;
                    if (i >= decl.inits.len) return false;
                    const init = decl.inits[i];
                    return init.* == .table and init.table.fields.len == 0;
                }
            },
            else => {},
        }
    }
    return false;
}

/// The body relation, EVALUATED, with its result name standing for `element`.
///
/// Deliberately tiny and deliberately conservative — it answers null for
/// everything it is not certain about, and a null anywhere means the relation
/// is realized as a scan instead. Three exclusions are the interesting ones,
/// and each is a place a second opinion would become a WRONG ANSWER rather than
/// a refusal:
///
///   * `ctx.const_ints` is NOT consulted. Its own doc comment says it records a
///     name's last literal binding and is never invalidated by a later
///     non-literal assignment — fine for a loop step read at the binding, fatal
///     for a predicate read anywhere in a body.
///   * `/`, `//` and `%` are NOT folded. `docs/rulings.md` settles them as
///     FLOORED, the backend inherited truncating behaviour from `msub`, and a
///     folder that picked either would be a second definition of an operator
///     whose first definition is still being repaired.
///   * `and` / `or` are NOT folded. They are value-selecting in the Lua law
///     this language descends from, and `0` is TRUTHY there while this
///     backend's branches treat it as false. That disagreement is a live
///     question, not something to answer inside a folder.
fn foldBodyRelation(ctx: *const LowerCtx, expr: *const ast.Expr, name: []const u8, element: i64) ?i64 {
    const truth = struct {
        fn of(b: bool) i64 {
            return if (b) 1 else 0;
        }
    }.of;
    switch (expr.*) {
        .int_lit => |lit| return lit.val,
        .true_lit => return 1,
        .false_lit => return 0,
        .name => |n| {
            if (std.mem.eql(u8, n.ident, name)) return element;
            if (ctx.module_consts.ints.get(n.ident)) |value| return value;
            return null;
        },
        .unop => |u| {
            const operand = foldBodyRelation(ctx, u.operand, name, element) orelse return null;
            return switch (u.op) {
                .neg => -%operand,
                .not => truth(operand == 0),
                .bnot => ~operand,
                else => null,
            };
        },
        .binop => |b| {
            const lhs = foldBodyRelation(ctx, b.lhs, name, element) orelse return null;
            const rhs = foldBodyRelation(ctx, b.rhs, name, element) orelse return null;
            return switch (b.op) {
                .add => lhs +% rhs,
                .sub => lhs -% rhs,
                .mul => lhs *% rhs,
                .band => lhs & rhs,
                .bor => lhs | rhs,
                .bxor => lhs ^ rhs,
                .eq => truth(lhs == rhs),
                .neq => truth(lhs != rhs),
                .lt => truth(lhs < rhs),
                .gt => truth(lhs > rhs),
                .leq => truth(lhs <= rhs),
                .geq => truth(lhs >= rhs),
                else => null,
            };
        },
        else => return null,
    }
}

fn lowerAnyRelation(ctx: *LowerCtx, shape: collection_relation.Shape) Error!dnir.Value {
    if (shape.subject.* != .name) return bail(ctx.diagnostic, @src());
    const source = shape.subject.name.ident;
    const extent = staticTableLen(ctx, source) orelse
        (if (boundEmptyTable(ctx, source)) @as(i64, 0) else return bail(ctx.diagnostic, @src()));

    // TERMINATION, stated as a fact rather than discovered by running: a known
    // extent bounds the scan, and an extent of zero bounds it at zero. An
    // existential over an EMPTY source is FALSE, and the answer is an immediate
    // — no slot, no scan, no source. `protocol-projection-one.md` §3's last
    // realization, "or **nothing**", reached from the extent alone.
    if (extent <= 0) return .{ .i64 = 0 };

    // DETERMINED SOURCE — every element is a compile-time literal, nothing
    // writes the name and nothing lets it escape (`noteConstTable`'s verdict,
    // not this pass's opinion). Then the question has a compile-time ANSWER
    // whenever the body relation is one this folder is certain of, and the
    // whole iteration is an immediate: no table, no loop, no branch.
    //
    // THIS IS WHAT MAKES THE STRONGER RELATION THE CHEAPER ONE. `xs:any(…)`
    // states existence; the flag-and-scan loop it replaces states "scan and
    // mutate a flag", and the compiler has to rediscover the question from the
    // loop before it can do this. Same answer, and the relation form gets there
    // without the rediscovery.
    const determined: ?[]const i64 = ctx.const_tables.get(source);
    if (determined) |values| {
        var settled = true;
        var witness = false;
        for (values) |element| {
            const verdict = foldBodyRelation(ctx, shape.body, shape.param, element) orelse {
                settled = false;
                break;
            };
            if (verdict != 0) {
                witness = true;
                break;
            }
        }
        if (settled) return .{ .i64 = if (witness) 1 else 0 };
    }

    const answer = ctx.freshTemp();
    try ctx.emit(.{ .op = .store_local, .result = answer, .lhs = .{ .i64 = 0 }, .ty = .i64 });

    var witnesses: std.ArrayListUnmanaged(usize) = .empty;
    defer witnesses.deinit(ctx.alloc);

    var result_name = ResultName.bind(ctx, shape.param);
    defer result_name.release();

    // The source is determined but the body relation is not foldable — a
    // capture, a call, an operator this pass refuses to define. The elements
    // are still literals, so the chain is emitted against IMMEDIATES and the
    // table is never materialized.
    if (determined) |values| {
        for (values) |element| {
            try result_name.pointLiteral(element);
            const verdict = try lowerExpr(ctx, shape.body);
            const rejected = ctx.instrs.items.len;
            try ctx.emit(.{ .op = .br, .lhs = verdict, .branch_target = 0, .branch_condition = .when_false });
            try ctx.emit(.{ .op = .store_local, .result = answer, .lhs = .{ .i64 = 1 }, .ty = .i64 });
            try witnesses.append(ctx.alloc, ctx.instrs.items.len);
            try ctx.emit(.{ .op = .br, .branch_target = 0 });
            ctx.instrs.items[rejected].branch_target = @intCast(ctx.instrs.items.len);
        }
        const done: u32 = @intCast(ctx.instrs.items.len);
        for (witnesses.items) |index| ctx.instrs.items[index].branch_target = done;
        return .{ .local = answer };
    }

    if (ptrSlotOf(ctx, shape.subject)) |base| {
        // MEMORY-BACKED: one scan, one scaled load per step, and a branch out
        // of the loop the moment the predicate answers yes. The index is this
        // pass's own induction variable and is in range by construction, so no
        // bounds guard is emitted — `guardedTableIndex` exists for indexes the
        // SOURCE supplies, and this one has no source.
        const step = ctx.freshTemp();
        try ctx.emit(.{ .op = .store_local, .result = step, .lhs = .{ .i64 = 1 }, .ty = .i64 });

        const head: u32 = @intCast(ctx.instrs.items.len);
        const in_range = ctx.freshTemp();
        try ctx.emit(.{
            .op = .binop,
            .result = in_range,
            .binop = .leq,
            .lhs = .{ .local = step },
            .rhs = .{ .i64 = extent },
        });
        const exhausted = ctx.instrs.items.len;
        try ctx.emit(.{ .op = .br, .lhs = .{ .temp = in_range }, .branch_target = 0, .branch_condition = .when_false });

        const loaded = ctx.freshTemp();
        try ctx.emit(.{
            .op = .load_index,
            .ty = .i64,
            .result = loaded,
            .lhs = .{ .local = base },
            .rhs = .{ .local = step },
        });
        const element = ctx.freshTemp();
        try ctx.emit(.{ .op = .store_local, .result = element, .lhs = .{ .temp = loaded }, .ty = .i64 });
        try result_name.point(element);

        const verdict = try lowerExpr(ctx, shape.body);
        const rejected = ctx.instrs.items.len;
        try ctx.emit(.{ .op = .br, .lhs = verdict, .branch_target = 0, .branch_condition = .when_false });
        try ctx.emit(.{ .op = .store_local, .result = answer, .lhs = .{ .i64 = 1 }, .ty = .i64 });
        try witnesses.append(ctx.alloc, ctx.instrs.items.len);
        try ctx.emit(.{ .op = .br, .branch_target = 0 });

        ctx.instrs.items[rejected].branch_target = @intCast(ctx.instrs.items.len);
        const next = ctx.freshTemp();
        try ctx.emit(.{
            .op = .binop,
            .result = next,
            .binop = .add,
            .lhs = .{ .local = step },
            .rhs = .{ .i64 = 1 },
        });
        try ctx.emit(.{ .op = .store_local, .result = step, .lhs = .{ .temp = next }, .ty = .i64 });
        try ctx.emit(.{ .op = .br, .branch_target = head });

        const done: u32 = @intCast(ctx.instrs.items.len);
        ctx.instrs.items[exhausted].branch_target = done;
        for (witnesses.items) |index| ctx.instrs.items[index].branch_target = done;
        return .{ .local = answer };
    }

    // REGISTER-EXPLODED: the elements are already in slots, so there is nothing
    // to load and nothing to index. The chain short-circuits, which is the same
    // early exit the loop above emits, reached without a loop existing.
    if (extent > select_chain_max) return bail(ctx.diagnostic, @src());
    var index: i64 = 1;
    while (index <= extent) : (index += 1) {
        const element_key = try std.fmt.allocPrint(ctx.alloc, "{s}.{d}", .{ source, index });
        defer ctx.alloc.free(element_key);
        const element = ctx.locals.get(element_key) orelse return bail(ctx.diagnostic, @src());
        try result_name.point(element);

        const verdict = try lowerExpr(ctx, shape.body);
        const rejected = ctx.instrs.items.len;
        try ctx.emit(.{ .op = .br, .lhs = verdict, .branch_target = 0, .branch_condition = .when_false });
        try ctx.emit(.{ .op = .store_local, .result = answer, .lhs = .{ .i64 = 1 }, .ty = .i64 });
        try witnesses.append(ctx.alloc, ctx.instrs.items.len);
        try ctx.emit(.{ .op = .br, .branch_target = 0 });
        ctx.instrs.items[rejected].branch_target = @intCast(ctx.instrs.items.len);
    }
    const done: u32 = @intCast(ctx.instrs.items.len);
    for (witnesses.items) |i| ctx.instrs.items[i].branch_target = done;
    return .{ .local = answer };
}

fn lowerSubjectCall(
    ctx: *LowerCtx,
    expr: *const Expr,
    consumption: types.ReturnConsumption,
) Error!dnir.Value {
    if (try lowerCollectionRelation(ctx, expr)) |value| return value;
    // The test world's relations become a real trap rather than a call into a
    // module that does not exist at runtime. Gated on the SUBJECT being `test`,
    // so a user relation named `assert` on any other subject is untouched.
    if (expr.* == .method_call and expr.method_call.obj.* == .name and
        std.mem.eql(u8, expr.method_call.obj.name.ident, "test"))
    {
        if (try lowerTestRelation(ctx, expr.method_call.method, expr.method_call.args)) |v| return v;
    }
    // THE ENVIRONMENT'S REMOVAL EDGE, asked before the graph-fact path for the
    // same reason the test world's relations are: it is a WORLD projection, not
    // an application of a relation the graph can see. `table_apply` has already
    // converged `env:remove(k)` onto the anchored subject `os.env`, so exactly
    // one shape arrives here — and the bare face reaches this only where the
    // program does not bind `env`, which that pass decides.
    if (expr.* == .method_call and env(expr.method_call.obj) and
        std.mem.eql(u8, expr.method_call.method, "remove") and
        expr.method_call.args.len == 1 and !ctx.locals.contains("os"))
    {
        return lowerEnvRemove(ctx, expr.method_call.args[0]);
    }
    if (ctx.occurrences.get(expr)) |application| {
        if (ctx.require_graph_facts and !ctx.graph.isBootstrapApplicationNode(application.application)) {
            if (ctx.graph.applicationSubject(application.application) == null) {
                bindOccurrence(ctx.diagnostic, ctx.graph, application.application);
                return invalidGraphFacts(ctx.diagnostic, @src(), "application-subject");
            }
            return lowerCheckedScalarCall(ctx, application, consumption);
        }
    }
    if (expr.* == .method_call) {
        const mc = expr.method_call;
        if (try tryLowerSubjectRelationEdgeCall(ctx, expr, consumption)) |value| return value;
        if (mc.obj.* == .name and std.mem.eql(u8, mc.obj.name.ident, "stdin") and
            std.mem.eql(u8, mc.method, "read") and mc.args.len == 0)
        {
            return lowerStdinRead(ctx, consumption);
        }
        if (mc.obj.* == .name and std.mem.eql(u8, mc.obj.name.ident, "stdin") and
            std.mem.eql(u8, mc.method, "line") and mc.args.len == 0)
        {
            return lowerStdinLine(ctx, consumption);
        }
        if (mc.obj.* == .name and std.mem.eql(u8, mc.obj.name.ident, "stdout") and
            std.mem.eql(u8, mc.method, "write") and mc.args.len == 1)
        {
            return lowerWrite(ctx, mc.args);
        }
        if (subject_home.streamRelation(mc.method)) {
            {
                const app_id: ?semantic_graph.id = if (ctx.occurrences.get(expr)) |occ| occ.application else null;
                noteHostTaint(ctx, .method_string, "stream_method.arity", app_id);
            }
            const is_stdout = mc.obj.* == .name and std.mem.eql(u8, mc.obj.name.ident, "stdout");
            if (std.mem.eql(u8, mc.method, "write") and mc.args.len == 1 and !is_stdout) {
                return lowerStreamWrite(ctx, mc.obj, mc.args[0]);
            }
            if (std.mem.eql(u8, mc.method, "close") and mc.args.len == 0) {
                return lowerStreamClose(ctx, mc.obj);
            }
        }
        if (std.mem.eql(u8, mc.method, "read") and mc.args.len == 0 and exprIsStr(ctx, mc.obj)) {
            return lowerSubjectRead(ctx, expr, consumption);
        }
        if (!ctx.require_graph_facts and mc.args.len == 1) {
            if (ctx.relation_edges.get(mc.method)) |sym| {
                const args = [_]*ast.Expr{ mc.obj, mc.args[0] };
                return try lowerNamedDirectCall(ctx, sym, &args, consumption);
            }
        }
        if (std.mem.eql(u8, mc.method, "len") and mc.args.len == 0) {
            const base = try lowerExpr(ctx, mc.obj);
            if (consumption == .discard) {
                try ctx.emit(.{ .op = .str_len, .lhs = base });
                return .void;
            }
            const t = ctx.freshTemp();
            try ctx.emit(.{ .op = .str_len, .result = t, .lhs = base });
            return .{ .temp = t };
        }
        if (std.mem.eql(u8, mc.method, "has") and mc.args.len == 1) {
            return lowerSubjectHas(ctx, expr, consumption);
        }
        if (std.mem.eql(u8, mc.method, "find") and mc.args.len == 3) {
            return lowerSubjectFind(ctx, expr, consumption);
        }
        if (std.mem.eql(u8, mc.method, "tail") and mc.args.len == 0 and exprIsStr(ctx, mc.obj)) {
            // IT NEVER TAKES THE NAME — the rule `lowerCollectionRelation`
            // follows for `any` and `worldSubject` for `stdout`: if the graph
            // resolved this application to a declared relation, that
            // declaration owns the call. Measured on gate/idiom.id: its own
            // `tail` relation was stolen here by the builtin's bare
            // `call_direct "tail"` — no lineage, and the callee would collide
            // with the module's mangled symbol at link. The declared case
            // takes the checked call with the ORIGINAL occurrence, because the
            // generic fall-through synthesizes a fresh expr the occurrence map
            // has never seen.
            if (ctx.occurrences.get(expr)) |occurrence| {
                if (ctx.graph.applicationRelation(occurrence.application) != null) {
                    return lowerCheckedScalarCall(ctx, occurrence, consumption);
                }
            }
            return lowerSubjectTail(ctx, expr, consumption);
        }
        if (std.mem.eql(u8, mc.method, "to") and mc.args.len == 1 and ctx.graph.bootstrapApplicationExpr(expr)) {
            return lowerSubjectTo(ctx, mc.obj, mc.args[0], consumption);
        }
        // String descriptor primitives are bootstrap lowering rules, not
        // declared ordinary relations yet. Admit them before graph-fact bail
        // so gate transport can run on direct without Lua/C bridges.
        if (exprIsStr(ctx, mc.obj) or
            (std.mem.eql(u8, mc.method, "sub") and mc.args.len >= 1 and mc.args.len <= 2 and
                exprIsStr(ctx, mc.obj)))
        {
            return lowerCall(ctx, try faceAsCall(ctx, expr), consumption);
        }
        if (ctx.graph.bootstrapApplicationExpr(expr)) {
            return lowerCall(ctx, try faceAsCall(ctx, expr), consumption);
        }
    }
    return refuseMissingApplication(ctx, @src(), expr);
}

/// Whether any part of `expr` involves f64. `exprIsF64` only inspects the node
/// itself; short-circuit lowering needs to know about the whole subtree, since
/// `length2(p) == 25` is an integer-valued comparison over f64 operands.
fn exprTouchesF64(ctx: *LowerCtx, expr: *const ast.Expr) bool {
    if (exprIsF64(ctx, expr)) return true;
    return switch (expr.*) {
        .float_lit => true,
        .binop => |b| exprTouchesF64(ctx, b.lhs) or exprTouchesF64(ctx, b.rhs),
        .unop => |u| exprTouchesF64(ctx, u.operand),
        .call => |c| blk: {
            if (c.func.* == .name and functionResultIs(ctx, c.func.name.ident, .f64)) break :blk true;
            for (c.args) |a| {
                if (exprTouchesF64(ctx, a)) break :blk true;
            }
            break :blk false;
        },
        // Either arm of an expression-if can carry the float, and both are
        // reachable — so the whole expression touches f64 if either does.
        .if_expr => |ie| exprTouchesF64(ctx, ie.cond) or
            exprTouchesF64(ctx, ie.then_expr) or exprTouchesF64(ctx, ie.else_expr),
        else => false,
    };
}

/// `and` / `or` with real short-circuit semantics.
///
/// These had no arm in `lowerBinop`, so every function containing one fell back
/// to the AST backend — which lacks `#s`, `string.byte` and record lowering. A
/// tokenizer's `while i <= n and is_space(string.byte(src, i)) == 1` therefore
/// could never lower natively, and short-circuit is not optional there: without
/// it the guarded `string.byte` reads past the end of the string.
///
/// Both forms funnel through one slot so the result is a single value:
///
///   and:  S = lhs;  if !S goto END;  S = rhs;  END:
///   or:   S = lhs;  if !S goto RHS;  goto END;  RHS: S = rhs;  END:
///
/// `or` uses a false-polarity branch followed by an unconditional branch.
fn lowerShortCircuit(ctx: *LowerCtx, op: ast.BinOp, lhs: *const ast.Expr, rhs: *const ast.Expr) Error!dnir.Value {
    // Integer contexts only. When an operand's subtree touches f64 — an f64
    // kernel call, a float literal, an f64 slot — the AST backend already lowers
    // the whole `cond and a or b` ternary correctly against f64 records, and
    // taking it over here regressed WP-04. Refusing keeps that fallback.
    if (exprTouchesF64(ctx, lhs) or exprTouchesF64(ctx, rhs)) return bail(ctx.diagnostic, @src());

    const slot = ctx.freshTemp();
    try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = try lowerExpr(ctx, lhs), .ty = .any });

    const test_idx = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br, .lhs = .{ .local = slot }, .branch_target = 0, .branch_condition = .when_false });

    if (op == .@"and") {
        try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = try lowerExpr(ctx, rhs), .ty = .any });
        ctx.instrs.items[test_idx].branch_target = @intCast(ctx.instrs.items.len);
        return .{ .local = slot };
    }

    const skip_idx = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br, .branch_target = 0 });
    ctx.instrs.items[test_idx].branch_target = @intCast(ctx.instrs.items.len);
    try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = try lowerExpr(ctx, rhs), .ty = .any });
    ctx.instrs.items[skip_idx].branch_target = @intCast(ctx.instrs.items.len);
    return .{ .local = slot };
}

/// `k = if n > 3 10 else 20` — §6's expression-if, which IS the ternary.
///
/// Same single-slot shape `lowerShortCircuit` uses, and for the same reason:
/// the result has to be ONE value, so both arms store into one slot and the
/// slot is the answer.
///
///   if !cond goto ELSE;  S = then;  goto END;  ELSE: S = else;  END:
///
/// f64 is refused rather than guessed, exactly as short-circuit refuses it: the
/// slot is stored `.any`, and an f64 arm through an integer slot is a wrong
/// number, not a bail. The AST backend already lowers the f64 ternary.
fn lowerIfExpr(ctx: *LowerCtx, ie: *const ast.IfExpr) Error!dnir.Value {
    if (exprTouchesF64(ctx, ie.cond) or
        exprTouchesF64(ctx, ie.then_expr) or
        exprTouchesF64(ctx, ie.else_expr)) return bailWith(ctx.diagnostic, @src(), "if-expr-f64");

    const slot = ctx.freshTemp();
    const cond = try lowerExpr(ctx, ie.cond);
    const test_idx = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br, .lhs = cond, .branch_target = 0, .branch_condition = .when_false });

    try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = try lowerExpr(ctx, ie.then_expr), .ty = .any });
    const skip_idx = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br, .branch_target = 0 });

    ctx.instrs.items[test_idx].branch_target = @intCast(ctx.instrs.items.len);
    try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = try lowerExpr(ctx, ie.else_expr), .ty = .any });
    ctx.instrs.items[skip_idx].branch_target = @intCast(ctx.instrs.items.len);

    // The slot inherits the arms' TYPE, not just their value. Without this a
    // `if c "a" else "b"` lands in an untyped slot and every consumer
    // downstream — `..`, `#s`, `s[i]` — reads the pointer as an integer.
    if (exprIsStr(ctx, ie.then_expr) and exprIsStr(ctx, ie.else_expr))
        try ctx.str_slots.put(ctx.alloc, slot, {});
    if (exprIsBoolish(ctx, ie.then_expr) and exprIsBoolish(ctx, ie.else_expr))
        try ctx.bool_slots.put(ctx.alloc, slot, {});
    return .{ .local = slot };
}

/// The variadic tail the backend can stage. Eight is `pending_varargs`' width,
/// not a guess.
const max_concat_holes = 8;

/// A `..` chain read as a printf FORMAT plus the arguments it consumes.
///
/// Both consumers of a chain — `print`, and a chain in value position — need
/// exactly this, and they need to AGREE on it: two renderers for "how does an
/// operand become text" is two chances to disagree with each other and with the
/// C backend.
const ConcatPlan = struct {
    /// The literal parts with `%` doubled and each hole replaced by its
    /// conversion. Owned by `ctx.alloc`.
    fmt: []const u8,
    /// The same text with NO conversions, valid only when `count == 0`.
    literal: []const u8,
    holes: [max_concat_holes]*const ast.Expr,
    count: usize,
};

/// Read a flattened `..` chain as a format string, or answer null when a part
/// is a shape this cannot render. Null is not a failure — the caller decides
/// whether that is a bail or a fallback.
fn planConcat(ctx: *LowerCtx, parts: []const *const ast.Expr, newline: bool) Error!?ConcatPlan {
    var fmt: std.ArrayListUnmanaged(u8) = .empty;
    defer fmt.deinit(ctx.alloc);
    var literal: std.ArrayListUnmanaged(u8) = .empty;
    defer literal.deinit(ctx.alloc);
    var plan: ConcatPlan = .{ .fmt = "", .literal = "", .holes = undefined, .count = 0 };

    for (parts) |p| {
        if (p.* == .quoted) {
            try literal.appendSlice(ctx.alloc, p.quoted.val);
            // A `%` in the program's own text is TEXT. Left alone it reads the
            // following byte as a conversion and prints an argument that was
            // never passed — a wrong answer produced by a correct-looking
            // literal.
            for (p.quoted.val) |ch| {
                if (ch == '%') try fmt.append(ctx.alloc, '%');
                try fmt.append(ctx.alloc, ch);
            }
            continue;
        }
        if (plan.count == max_concat_holes) return null;
        if (exprIsStr(ctx, p)) {
            try fmt.appendSlice(ctx.alloc, "%s");
        } else if (concatOperandOk(ctx, p)) {
            // `concatOperandOk` has already refused f64 and bool — the two
            // shapes `%lld` renders into a plausible wrong answer.
            try fmt.appendSlice(ctx.alloc, "%lld");
        } else return null;
        plan.holes[plan.count] = p;
        plan.count += 1;
    }
    if (newline) {
        try fmt.append(ctx.alloc, '\n');
        try literal.append(ctx.alloc, '\n');
    }
    plan.fmt = try ctx.alloc.dupe(u8, fmt.items);
    plan.literal = try ctx.alloc.dupe(u8, literal.items);
    return plan;
}

/// Stage a plan's holes in the variadic tail. Emitted immediately before the
/// call that reads them.
fn stageConcatHoles(ctx: *LowerCtx, vals: []const dnir.Value) Error!void {
    for (vals, 0..) |v, i| {
        try ctx.emit(.{ .op = .mov_arg, .result = @intCast(i), .field = "vararg", .lhs = v });
    }
}

/// A `..` chain in VALUE position — `s = "a={a}"` — as one buffer.
///
/// The chain used to lower pairwise: strlen, strlen, malloc, strcpy, strcat per
/// `..`, with every intermediate buffer live across every later call. Three
/// holes is 26 values live at once against 19 allocatable registers, and the
/// backend leaks one more per result-less call, so the ladder ASSEMBLED and
/// then answered wrong — `a .. "-" .. b .. "-" .. c` printed the right text and
/// exited 240, and a three-hole interpolation segfaulted. Measuring the chain
/// once and filling it once removes the pressure instead of budgeting for it:
/// live values drop to one per hole, and those ride the variadic tail, which
/// Apple's ARM64 ABI passes in memory rather than in registers.
///
/// MEASURE, THEN FILL — the buffer is the size of the answer.
///
/// It used to be `malloc(4096)` and `snprintf(buf, 4096, …)`, one fixed
/// capacity for every chain in every program, and that is three defects in one
/// line:
///
///   1. IT TRUNCATED AT 4095 BYTES, silently. Measured at the boundary: a
///      4094-byte chain agreed with `--backend=c`, a 4096-byte chain produced
///      4095 bytes where C produced 4096, and an 8192-byte chain produced 4095
///      where C produced 8192. Exit 0 both times, `ok compile` both times. Two
///      backends, one source, DIFFERENT ANSWERS — which is strictly worse than
///      a bug, because neither side reports anything.
///   2. IT ALLOCATED 4 KB PER EVALUATION regardless of the answer's size, so a
///      loop concatenating short strings grew RSS by 4 KB an iteration.
///   3. It made the cost of a chain independent of its length, which hid both.
///
/// C's `snprintf` answers question 1 itself: called with a null destination and
/// a zero size it WRITES NOTHING and RETURNS THE LENGTH THE RESULT NEEDS. So
/// the sequence is measure, allocate exactly that many bytes plus the NUL, fill.
/// No cap, so nothing to exceed and nothing to refuse; the allocation is the
/// size of the string, so a short chain costs a short buffer.
///
/// THE HOLES ARE LOWERED ONCE and staged twice. That distinction is the whole
/// safety of the second call: `vals` holds already-computed DNIR values, and
/// `stageConcatHoles` only moves them into the variadic tail, so an operand
/// carrying an effect still runs exactly once. An earlier attempt at this shape
/// was abandoned after `print(p)` segfaulted on a register that held snprintf's
/// integer return instead of the malloc pointer; the boundary and byte
/// comparisons below are what makes the difference between then and now
/// checkable rather than remembered.
fn lowerConcatChain(ctx: *LowerCtx, lhs: *const ast.Expr, rhs: *const ast.Expr) Error!dnir.Value {
    var parts: std.ArrayListUnmanaged(*const ast.Expr) = .empty;
    defer parts.deinit(ctx.alloc);
    try flattenConcat(ctx.alloc, lhs, &parts);
    try flattenConcat(ctx.alloc, rhs, &parts);

    const plan = (try planConcat(ctx, parts.items, false)) orelse return bailWith(ctx.diagnostic, @src(), "concat");
    // Every part was a literal, so the chain IS its own answer — determined at
    // compile time, and it must not reach the allocator at all.
    if (plan.count == 0) return .{ .str = plan.literal };

    var vals: [max_concat_holes]dnir.Value = undefined;
    for (plan.holes[0..plan.count], 0..) |h, i| vals[i] = try lowerExpr(ctx, h);

    try ensureExtern(ctx, "mem", "alloc", "malloc");
    try ensureExtern(ctx, "string", "format", "snprintf");

    // MEASURE: `snprintf(NULL, 0, fmt, …)` writes nothing and answers the
    // length. This is the C standard's own answer to "how big is it", not an
    // estimate this pass invents.
    try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = .{ .i64 = 0 } });
    try ctx.emit(.{ .op = .mov_arg, .result = 1, .lhs = .{ .i64 = 0 } });
    try ctx.emit(.{ .op = .mov_arg, .result = 2, .lhs = .{ .str = plan.fmt } });
    try stageConcatHoles(ctx, vals[0..plan.count]);
    const need = ctx.freshTemp();
    try ctx.emit(.{ .op = .call_extern, .result = need, .callee = "snprintf", .ty = .i64 });

    // One more byte for the NUL `snprintf` excludes from its answer.
    const size = ctx.freshTemp();
    try ctx.emit(.{
        .op = .binop,
        .result = size,
        .binop = .add,
        .lhs = .{ .temp = need },
        .rhs = .{ .i64 = 1 },
    });

    const buf = ctx.freshTemp();
    try ctx.emit(.{ .op = .call_extern, .result = buf, .callee = "malloc", .lhs = .{ .temp = size } });

    // FILL: the same format and the same already-lowered holes, into a buffer
    // that cannot be too small because it was measured from them.
    try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = .{ .temp = buf } });
    try ctx.emit(.{ .op = .mov_arg, .result = 1, .lhs = .{ .temp = size } });
    try ctx.emit(.{ .op = .mov_arg, .result = 2, .lhs = .{ .str = plan.fmt } });
    try stageConcatHoles(ctx, vals[0..plan.count]);
    try ctx.emit(.{ .op = .call_extern, .callee = "snprintf" });
    try ctx.str_slots.put(ctx.alloc, buf, {});
    return .{ .temp = buf };
}

fn lowerStrCompare(ctx: *LowerCtx, op: ast.BinOp, lhs: *const ast.Expr, rhs: *const ast.Expr) Error!dnir.Value {
    const l = try lowerExpr(ctx, lhs);
    const r = try lowerExpr(ctx, rhs);
    try ensureExtern(ctx, "libc", "strcmp", "strcmp");
    try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = l });
    try ctx.emit(.{ .op = .mov_arg, .result = 1, .lhs = r });
    const cmp = ctx.freshTemp();
    try ctx.emit(.{ .op = .call_extern, .result = cmp, .callee = "strcmp", .ty = .i64 });
    const t = ctx.freshTemp();
    try ctx.emit(.{
        .op = .binop,
        .result = t,
        .binop = switch (op) {
            .eq => .eq,
            .neq => .neq,
            .lt => .lt,
            .gt => .gt,
            .leq => .leq,
            .geq => .geq,
            else => return bailWith(ctx.diagnostic, @src(), @tagName(op)),
        },
        .lhs = .{ .temp = cmp },
        .rhs = .{ .i64 = 0 },
        .ty = .any,
    });
    return .{ .temp = t };
}

/// The C rank of an already-lowered operand's SOURCE expression.
///
/// Conservative in one direction only: anything this pass cannot type answers
/// `.int64`, which never asks for a refit. A missing refit leaves today's
/// behaviour; a spurious one would be a NEW wrong answer, so the unknown case
/// has to fall on the side that changes nothing.
///
/// Known gap, recorded rather than guessed: a CALL answers `.int64` even when
/// the callee is declared `i32`, so `u32_expr + i32_call()` is not wrapped
/// where C would wrap it. Closing it needs the callee's declared return at this
/// site; `u32` returns are already ineligible for this backend, so the gap is
/// exactly one shape wide.
fn exprCRank(ctx: *LowerCtx, e: *const ast.Expr) CRank {
    return switch (e.*) {
        .int_lit => |i| if (i.val >= std.math.minInt(i32) and i.val <= std.math.maxInt(i32))
            .int32
        else
            .int64,
        .true_lit, .false_lit => .int32,
        .name => |n| blk: {
            const slot = ctx.locals.get(n.ident) orelse break :blk .int64;
            const declared = ctx.narrow_slots.get(slot) orelse break :blk .int64;
            break :blk crankOfNarrow(declared);
        },
        .unop => |u| switch (u.op) {
            .neg, .bnot => exprCRank(ctx, u.operand),
            .not => .int32,
            else => .int64,
        },
        .binop => |b| switch (b.op) {
            // `--backend=c` emits `((int64_t)(x)) << k` and
            // `lua_imod_i64((int64_t)(a), (int64_t)(b))` — the operands are
            // WIDENED before the operation, so the result is not narrow and
            // must not be refitted. Measured: `a << 4` on a `u32` holding
            // 4294967295 prints 68719476720 under both backends today.
            .lshift, .rshift, .div, .idiv, .mod, .pow => .int64,
            .eq, .neq, .lt, .gt, .leq, .geq, .@"and", .@"or", .contains => .int32,
            .add, .sub, .mul, .band, .bor, .bxor => crankJoin(
                exprCRank(ctx, b.lhs),
                exprCRank(ctx, b.rhs),
            ),
            else => .int64,
        },
        else => .int64,
    };
}

/// The declared width an operation's RESULT carries, or `.any` when it carries
/// none. Only `unsigned int` earns one — see `CRank`.
fn binopResultWidth(ctx: *LowerCtx, op: ast.BinOp, lhs: *const ast.Expr, rhs: *const ast.Expr) RT {
    switch (op) {
        .add, .sub, .mul, .band, .bor, .bxor => {},
        else => return .any,
    }
    const l = exprCRank(ctx, lhs);
    const r = exprCRank(ctx, rhs);
    if (crankJoin(l, r) != .uint32) return .any;
    // BITWISE OPS THAT CANNOT LEAVE THE WIDTH ARE NOT REFITTED, and this is a
    // proof rather than a tolerance. A `.uint32` operand is canonical — its top
    // 32 bits are zero — so:
    //   AND needs only ONE canonical operand: it cannot set a bit that operand
    //   does not have.
    //   OR and XOR need BOTH: a sign-extended negative on the other side would
    //   otherwise leak its high bits through.
    // Everything else (add, sub, mul) carries out of bit 31 and must be refit.
    switch (op) {
        .band => return .any,
        .bor, .bxor => if (l == .uint32 and r == .uint32) return .any,
        else => {},
    }
    return .u32;
}

/// A store's refit SUBSUMES the refit of the instruction that produced its
/// value, when that producer is the instruction immediately before it and both
/// refit to the same width.
///
/// This is what keeps the repair free on the shape it exists for. `h = h * K`
/// on a `u32` lowers to `binop mul -> t` then `store_local h <- t`; refitting
/// both emits two `ubfx` where the store's alone is enough, and on
/// `tools/wasm/bench/hash.id` that is three extra instructions per iteration
/// across 200 million iterations.
///
/// SINGLE-CONSUMER IS BY CONSTRUCTION, not by search: `t` was allocated by the
/// expression just lowered and handed straight to this store, so no earlier
/// instruction can name it and no later one exists yet. The two positional
/// checks below (producer is at `len-2`, its result is exactly what the store
/// reads) are the whole precondition.
fn subsumeProducerRefit(ctx: *LowerCtx) void {
    const items = ctx.instrs.items;
    if (items.len < 2) return;
    const store = items[items.len - 1];
    if (store.op != .store_local) return;
    if (store.lhs != .temp) return;
    const want = narrowFit(store.ty) orelse return;
    const producer = &items[items.len - 2];
    if (producer.op != .binop) return;
    const result = producer.result orelse return;
    if (result != store.lhs.temp) return;

    // WHICH SIDE ABSORBS THE OTHER IS A REALIZATION QUESTION, AND AT 32
    // UNSIGNED BITS THE PRODUCER WINS.
    //
    // A store's refit is an INSTRUCTION — `ubfx xd, xs, #0, #32` — and it sits
    // on the recurrence of every loop that carries a `u32`. A producer's refit
    // at that width is not an instruction at all: `native_backend.wForm32`
    // selects the 32-bit destination form, whose zero-extension IS the
    // narrowing. So handing the width to the PRODUCER deletes the chain node
    // and leaves the store an ordinary register move, which this machine
    // renames away (`docs/dependence-height.md` §1.2, measured at -0.016 cyc).
    //
    // Measured on `tools/wasm/bench/hash2b.id`, the single largest consumer of
    // cycles in this corpus: 9.09 -> 6.04 cycles per iteration, same answer.
    //
    // Only at 32 unsigned bits, and only for the operations whose low half is
    // a function of the operands' low halves — see `lowThirtyTwoExact`. `u8`,
    // `u16` and every signed width keep the store-side refit below, because
    // their narrowing is a real mask or a real sign extension and no
    // destination form performs it for free.
    if (want.bits == 32 and !want.signed and lowThirtyTwoExact(producer.binop) and
        (producer.ty == .any or producer.ty == .u32))
    {
        producer.ty = .u32;
        items[items.len - 1].ty = .any;
        return;
    }

    // Otherwise the store absorbs the producer's, which is what this function
    // was written for: refitting both emits two `ubfx` where the store's alone
    // is enough.
    const have = narrowFit(producer.ty) orelse return;
    if (have.bits != want.bits or have.signed != want.signed) return;
    producer.ty = .any;
}

/// Refit a lowered value to a declared width, folding when it is a literal.
///
/// The register form is a `store_local` into a fresh slot, which the backend
/// realizes as exactly one extend instruction — the same instruction any other
/// refit emits, through the same code path, so there is one origin for the
/// machine behaviour and not two.
fn refitValue(ctx: *LowerCtx, v: dnir.Value, ty: RT) Error!dnir.Value {
    if (narrowFit(ty) == null) return v;
    switch (v) {
        .i64 => |n| return .{ .i64 = narrowFitConst(n, ty) },
        .void, .f64, .str, .record => return v,
        else => {},
    }
    const t = ctx.freshTemp();
    try ctx.emit(.{ .op = .store_local, .result = t, .lhs = v, .ty = ty });
    return .{ .temp = t };
}

/// law §62 — `x / y` and `x % y` where `y` is zero AT RUN TIME.
///
/// AArch64 `sdiv` does not fault: it answers 0. That is a property of the chip,
/// not a decision this language made, and §62 requires division by zero to be
/// DEFINED and DETERMINISTIC. Measured before this guard, one source and two
/// answers — `--backend direct` printed `0` and `--backend=c` printed
/// `9218868437227405312` (the bits of +inf) — with exit 0 and no message on
/// either. A value that changes with the target is not a definition.
///
/// The literal-zero divisor is settled earlier and elsewhere: `sema.zig`'s
/// `check_literal_zero_divisor` refuses it with a diagnostic, because there is
/// nothing to guard when the divisor IS zero. What reaches here is the case the
/// compiler cannot decide, and `soundness.md` names the handling for exactly
/// that: "realization selects an explicit guard whose failure is a semantic
/// case". The guard is the same shape `emitIndexBoundsTrap` already uses — a
/// compare, a branch and `abort` — so the two runtime faults this backend can
/// raise are one mechanism, not two.
///
/// Cost is one `cmp` and one conditional branch per division whose divisor is
/// not a nonzero constant. A constant nonzero divisor — every `/ 2`, `/ 8`,
/// `% 10` in the corpus — pays nothing at all.
fn emitDivisorZeroTrap(ctx: *LowerCtx, divisor: dnir.Value) Error!void {
    if (divisor == .i64 and divisor.i64 != 0) return;

    const ok = ctx.freshTemp();
    try ctx.emit(.{ .op = .binop, .result = ok, .binop = .neq, .lhs = divisor, .rhs = .{ .i64 = 0 } });
    const bad = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br, .lhs = .{ .temp = ok }, .branch_target = 0, .branch_condition = .when_false });

    const skip = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br, .branch_target = 0 });

    ctx.instrs.items[bad].branch_target = @intCast(ctx.instrs.items.len);
    try emitTrap(ctx);
    ctx.instrs.items[skip].branch_target = @intCast(ctx.instrs.items.len);
}

fn lowerBinop(ctx: *LowerCtx, op: ast.BinOp, lhs: *const ast.Expr, rhs: *const ast.Expr) Error!dnir.Value {
    if (op == .concat and concatOperandOk(ctx, lhs) and concatOperandOk(ctx, rhs) and
        (exprIsStr(ctx, lhs) or exprIsStr(ctx, rhs)))
    {
        return try lowerConcatChain(ctx, lhs, rhs);
    }
    const str_cmp = switch (op) {
        .eq, .neq, .lt, .gt, .leq, .geq => exprIsStr(ctx, lhs) and exprIsStr(ctx, rhs),
        else => false,
    };
    if (str_cmp) return try lowerStrCompare(ctx, op, lhs, rhs);
    const f64_op = exprIsF64(ctx, lhs) or exprIsF64(ctx, rhs);
    // Selected BEFORE either operand is lowered: an unsupported operator has to
    // refuse without having emitted the operands' instructions, which is what
    // the struct-literal field order used to guarantee.
    const tag: dnir.BinOpTag = switch (op) {
        .add => .add,
        .sub => .sub,
        .mul => .mul,
        .div => .div,
        // `//` KEEPS ITS OWN IDENTITY. This read `.div, .idiv => .div`, which
        // is where floor division was lost: the two operators became one tag
        // and the backend then emitted `sdiv` for both. `(0-7) // 10` answered
        // 0; the law answers -1. HPLS §92 — the host may not define relation
        // law — and §4: the optimizer uses the LAW, so the tag has to be able
        // to carry it.
        .idiv => .idiv,
        .mod => .mod,
        .eq => .eq,
        .neq => .neq,
        .lt => .lt,
        .gt => .gt,
        .leq => .leq,
        .geq => .geq,
        .band => .band,
        .bor => .bor,
        .bxor => .bxor,
        .lshift => .shl,
        .rshift => .shr,
        else => return bailWith(ctx.diagnostic, @src(), @tagName(op)),
    };
    const t = ctx.freshTemp();
    var a = try lowerExpr(ctx, lhs);
    var b = try lowerExpr(ctx, rhs);
    // Integer division only. IEEE-754 DEFINES `x / 0.0` as ±inf and §62 lists
    // infinities among the defined outcomes, so the float path has an answer
    // already and must not be given a fault instead.
    if (!f64_op and (tag == .div or tag == .mod)) try emitDivisorZeroTrap(ctx, b);
    var result_ty: RT = if (f64_op) .f64 else .any;
    if (!f64_op) {
        if (unsignedComparison(ctx, op, lhs, rhs)) |conv| {
            // C converts BOTH operands to the common type before comparing, so
            // `a < -1` on a `uint32_t` is `a < 4294967295u` — true — and the
            // 64-bit signed compare this backend emits answers false. Refit the
            // operand that is not already canonical at the common width and the
            // existing signed compare then gives C's answer, with no new
            // condition codes to get backwards.
            if (conv.fit_lhs) a = try refitValue(ctx, a, conv.ty);
            if (conv.fit_rhs) b = try refitValue(ctx, b, conv.ty);
        } else {
            result_ty = binopResultWidth(ctx, op, lhs, rhs);
        }
    }
    try ctx.emit(.{
        .op = .binop,
        .result = t,
        .binop = tag,
        .lhs = a,
        .rhs = b,
        .ty = result_ty,
    });
    return .{ .temp = t };
}

const UnsignedComparison = struct { ty: RT, fit_lhs: bool, fit_rhs: bool };

/// A comparison whose C common type is `unsigned int`, and which of its
/// operands is not already canonical at that width.
///
/// A `.uint32` operand IS canonical by construction: it is either a `u32`
/// binding (every store refits) or a `u32`-ranked arithmetic result (every such
/// result refits, and `band` is proven not to need one). So only the `.int32`
/// side — a literal, an `i32`/`u8`/`i16` binding, a boolean — can carry bits
/// the comparison must drop.
fn unsignedComparison(
    ctx: *LowerCtx,
    op: ast.BinOp,
    lhs: *const ast.Expr,
    rhs: *const ast.Expr,
) ?UnsignedComparison {
    switch (op) {
        .eq, .neq, .lt, .gt, .leq, .geq => {},
        else => return null,
    }
    const l = exprCRank(ctx, lhs);
    const r = exprCRank(ctx, rhs);
    if (crankJoin(l, r) != .uint32) return null;
    return .{ .ty = .u32, .fit_lhs = l != .uint32, .fit_rhs = r != .uint32 };
}

/// FP argument staging was UNSAFE until the backend stopped homing f64 values in
/// the staging registers, and this is the note left where the guard used to be.
///
/// d0-d7 are both the f64 argument registers and the staging registers, and the
/// backend homed f64 params and locals there, so `p: f64 = 9.0; one(2.0)`
/// destroyed p's home and `two(4.0, p)` swapped two registers through each other
/// and passed (4.0, 4.0). This pass cannot see home assignments, so it could not
/// order the moves; it refused the shapes it could not prove safe instead.
///
/// `allocFpReg` now allocates from d16-d30 and parameters are copied out of
/// d0-d7 on entry whenever the body can call — the same move the integer side
/// has always made out of x0-x7 into x9+. Values and staging no longer share
/// registers, so the hazard is gone at its source and the refusal is retired.
/// Whether this callee takes at least one argument in v0..v7.
fn calleeWantsFpSlots(ctx: *LowerCtx, callee: ?[]const u8) bool {
    const name = callee orelse return false;
    const slots = ctx.fp_params.get(name) orelse return false;
    for (slots) |is_fp| {
        if (is_fp) return true;
    }
    return false;
}

fn emitScalarCallArgs(ctx: *LowerCtx, args: []const *ast.Expr, callee: ?[]const u8) Error!void {
    if (args.len == 0) return;
    if (args.len > max_direct_scalar_args) return bail(ctx.diagnostic, @src());

    // Two phases, deliberately. `mov_arg` writes x0..x7, and evaluating a later
    // argument may itself contain a call that clobbers them: in
    // `sum2(sq(5), sq(4))` argument 0 was parked in x0 and then destroyed by the
    // call for argument 1, so both arguments arrived as sq(4). Evaluate every
    // argument first (into temps/locals, which live in the caller-saved range and
    // survive calls), then marshal them all.
    //
    // A record argument contributes one slot per field, so the slot count is not
    // the argument count.
    var values: [max_direct_scalar_args]dnir.Value = undefined;
    var count: u32 = 0;
    for (args) |arg| {
        if (arg.* == .name) {
            if (scalarRecordForName(ctx, arg.name.ident)) |rec| {
                for (rec.fields) |fname| {
                    if (count >= 8) return bail(ctx.diagnostic, @src());
                    const key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ arg.name.ident, fname });
                    defer ctx.alloc.free(key);
                    const field_slot = ctx.locals.get(key) orelse return bail(ctx.diagnostic, @src());
                    values[count] = .{ .local = field_slot };
                    count += 1;
                }
                continue;
            }
            // A positional table argument is passed as one base address. It has
            // to be materialized into frame memory first — the elements are
            // registers until something needs a pointer to them.
            if (nameIsPositionalTable(ctx, arg.name.ident)) {
                if (count >= 8) return bail(ctx.diagnostic, @src());
                values[count] = .{ .local = try materializeTableSlots(ctx, arg.name.ident) };
                count += 1;
                continue;
            }
            if (recordLocalDesc(ctx, arg.name.ident)) |_| {
                if (count >= 8) return bail(ctx.diagnostic, @src());
                values[count] = .{ .local = try materializeRecordBase(ctx, arg.name.ident) };
                count += 1;
                continue;
            }
        }
        if (count >= max_direct_scalar_args) return bail(ctx.diagnostic, @src());
        values[count] = try lowerExpr(ctx, arg);
        count += 1;
    }
    // GAP-056: place each slot in the register FILE its callee reads from.
    // AAPCS64 numbers the two files independently, so they get independent
    // cursors: `f(a: i64, b: f64, c: i64)` is x0, d0, x1.
    const fp_slots: []const bool = if (callee) |name|
        ctx.fp_params.get(name) orelse &.{}
    else
        &.{};
    var gp: u32 = 0;
    var fp: u32 = 0;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        if (i < fp_slots.len and fp_slots[i]) {
            // Only v0..v7 are marshaled; there is no FP stack-arg extension.
            if (fp >= 8) return bail(ctx.diagnostic, @src());
            try ctx.emit(.{ .op = .fp_mov_arg, .result = fp, .lhs = values[i] });
            fp += 1;
        } else {
            try ctx.emit(.{ .op = .mov_arg, .result = gp, .lhs = values[i] });
            gp += 1;
        }
    }
}

/// The scalar record whose fields are all bound as `name.field` locals, if any.
/// Records are stored exploded — one local per field — so "passing a record"
/// means passing its fields in consecutive argument slots, the same convention
/// the f64 kernel path already uses.
fn scalarRecordForName(ctx: *LowerCtx, name: []const u8) ?dnir.RecordDesc {
    _ = ctx;
    _ = name;
    return null;
}

fn scalarCallLhs(ctx: *LowerCtx, args: []const *ast.Expr, callee: ?[]const u8) Error!dnir.Value {
    if (args.len == 0) return .void;
    // GAP-056, one-argument form. A lone argument is normally handed back as the
    // call's `.lhs`, which the backend stages in x0 — right for an integer,
    // wrong for a double. `p1(x: f64): i64` was as broken as the two-argument
    // case and would have survived a fix aimed only at the loop below.
    if (calleeWantsFpSlots(ctx, callee)) {
        try emitScalarCallArgs(ctx, args, callee);
        return .void;
    }
    if (args.len == 1) {
        const arg = args[0];
        if (arg.* == .table) {
            if (inferRecordNameFromTable(ctx.records, arg)) |rec_name| {
                return try lowerInlineRecordArg(ctx, arg, rec_name);
            }
        }
        // A lone record argument still expands to several slots, so it needs the
        // multi-slot path rather than the single-value one.
        if (arg.* == .name and scalarRecordForName(ctx, arg.name.ident) != null) {
            try emitScalarCallArgs(ctx, args, callee);
            return .void;
        }
        // A lone table argument is passed as its base address, which means
        // materializing the register-exploded elements into frame memory first.
        // `lowerExpr` would hand back the table's own slot, which never holds a
        // value — the elements live in `a.1`, `a.2`, … — so the backend reported
        // it as an undefined name.
        if (arg.* == .name and nameIsPositionalTable(ctx, arg.name.ident)) {
            return .{ .local = try materializeTableSlots(ctx, arg.name.ident) };
        }
        if (try lowerOpaqueRecordLocalArg(ctx, arg)) |materialized| return materialized;
        return try lowerExpr(ctx, arg);
    }
    try emitScalarCallArgs(ctx, args, callee);
    return .void;
}

/// Whether `expr` is provably an integer, which is the constant the `"%lld"`
/// emitter below assumes. It is a POSITIVE test on purpose: "not f64 and not
/// str" accepted a table base and a pointer, and `to(str)` on either printed
/// the ADDRESS in decimal — a plausible-looking string with no relation to the
/// value. Anything this cannot prove declines to the general path.
fn exprIsIntegral(ctx: *LowerCtx, expr: *const ast.Expr) bool {
    if (exprTouchesF64(ctx, expr)) return false;
    if (exprIsStr(ctx, expr)) return false;
    if (applicationFirstResultDescriptor(ctx, expr)) |descriptor| return descriptor.is_integer();
    return switch (expr.*) {
        .int_lit, .true_lit, .false_lit => true,
        // `#s` is a length and `s[i]` is a byte — both integers.
        .unop => |u| if (u.op == .len)
            exprIsStr(ctx, u.operand)
        else
            exprIsIntegral(ctx, u.operand),
        .binop => |b| b.op != .concat and
            exprIsIntegral(ctx, b.lhs) and exprIsIntegral(ctx, b.rhs),
        .index => true,
        // A plain call to a function that returns neither str nor f64 nor a
        // record. `exprTouchesF64` above already excluded the float kernels.
        .call => |cc| cc.func.* == .name and
            !functionResultIs(ctx, cc.func.name.ident, .str) and
            !ctx.func_record_returns.contains(cc.func.name.ident),
        .name => |n| blk: {
            const slot = ctx.locals.get(n.ident) orelse break :blk false;
            break :blk !ctx.f64_slots.contains(slot) and
                !ctx.str_slots.contains(slot) and
                !ctx.ptr_slots.contains(slot) and
                !nameIsPositionalTable(ctx, n.ident);
        },
        .if_expr => |ie| exprIsIntegral(ctx, ie.then_expr) and exprIsIntegral(ctx, ie.else_expr),
        .method_call => |mc| blk: {
            if (std.mem.eql(u8, mc.method, "len") and mc.args.len == 0)
                break :blk exprIsStr(ctx, mc.obj);
            if (std.mem.eql(u8, mc.method, "byte") and mc.args.len >= 1 and mc.args.len <= 2)
                break :blk exprIsStr(ctx, mc.obj);
            break :blk false;
        },
        else => false,
    };
}

/// `value:to(i64)` — bootstrap text-to-integer edge for gate transport scripts.
fn lowerSubjectTo(
    ctx: *LowerCtx,
    subject: *const ast.Expr,
    target: *const ast.Expr,
    consumption: types.ReturnConsumption,
) Error!dnir.Value {
    if (target.* != .name) {
        return invalidGraphFacts(ctx.diagnostic, @src(), "unsupported-conversion");
    }
    if (std.mem.eql(u8, target.name.ident, "i64")) {
        // THE SUBJECT MUST BE TEXT, and this arm did not ask. `duo_str_to_i64`
        // takes a `const char*` (`src/idol_str_bootstrap.c`), so a non-text
        // subject is DEREFERENCED AS AN ADDRESS: `x = 42 ; x:to(i64)` built,
        // linked, and SEGFAULTED (exit 139, reproduced 3 of 3 — measured in
        // idol-native/docs/edge-canon.md §2.6).
        //
        // The `str` arm below is the template: it refuses a subject it cannot
        // prove integral, for exactly this reason and with exactly this
        // diagnostic. The two arms of one conversion table disagreed about
        // whether checking the subject was their job, and the arm that did not
        // check is the one that produced undefined behaviour rather than a
        // refusal. A conversion that cannot be performed must be REFUSED, not
        // emitted and left to the loader.
        if (!exprIsStr(ctx, subject)) {
            return invalidGraphFacts(ctx.diagnostic, @src(), "unsupported-conversion");
        }
        const s = try lowerExpr(ctx, subject);
        try ensureExtern(ctx, "compat", "str", "duo_str_to_i64");
        if (consumption == .discard) {
            try ctx.emit(.{ .op = .call_extern, .callee = "duo_str_to_i64", .lhs = s, .ty = .i64 });
            return .void;
        }
        const t = ctx.freshTemp();
        try ctx.emit(.{ .op = .call_extern, .result = t, .callee = "duo_str_to_i64", .lhs = s, .ty = .i64 });
        return .{ .temp = t };
    }
    // THE OTHER HALF OF THE SAME EDGE. `str -> i64` was here and `str -> f64`
    // was nowhere, in either spelling, so a lexer could scan a well-formed
    // float literal and had no way to say what it was worth —
    // `lib/compiler/lexer.id` refuses on exactly this, at its ONE `to(f64)`.
    //
    // The subject check is the `i64` arm's, for the reason that arm records at
    // length: `duo_str_to_f64` takes a `const char*`, so a non-text subject is
    // DEREFERENCED AS AN ADDRESS. A conversion that cannot be performed is
    // refused, never emitted and left to the loader.
    if (std.mem.eql(u8, target.name.ident, "f64")) {
        if (!exprIsStr(ctx, subject)) {
            return invalidGraphFacts(ctx.diagnostic, @src(), "unsupported-conversion");
        }
        const s = try lowerExpr(ctx, subject);
        try ensureExtern(ctx, "compat", "str", "duo_str_to_f64");
        if (consumption == .discard) {
            try ctx.emit(.{ .op = .call_extern, .callee = "duo_str_to_f64", .lhs = s, .ty = .f64 });
            return .void;
        }
        const t = ctx.freshTemp();
        try ctx.emit(.{ .op = .call_extern, .result = t, .callee = "duo_str_to_f64", .lhs = s, .ty = .f64 });
        return .{ .temp = t };
    }
    if (std.mem.eql(u8, target.name.ident, "str")) {
        if (!exprIsIntegral(ctx, subject)) {
            return invalidGraphFacts(ctx.diagnostic, @src(), "unsupported-conversion");
        }
        const n = try lowerExpr(ctx, subject);
        const buf = try emitIntToStr(ctx, n);
        if (consumption == .discard) return .void;
        return .{ .temp = buf };
    }
    return invalidGraphFacts(ctx.diagnostic, @src(), "unsupported-conversion");
}

/// A CALLER'S BYTE OFFSET AS THE BACKEND'S 1-BASED ELEMENT INDEX.
///
/// `load_index`/`store_index` at `.ty = .i64` address `base + (idx - 1) * 8`;
/// the `mem` faces take a 0-based BYTE offset, the same one `codegen.zig`
/// spells `(uint8_t*)p + off`. Both conversions therefore have to happen — the
/// scale down by 8 and the 1-based bias — and they have to happen in ONE place,
/// because the read and the write of the same buffer disagreeing about its
/// origin is exactly the defect this helper was extracted to end.
fn lowerScaledElementIndex(ctx: *LowerCtx, off_expr: *const ast.Expr) Error!dnir.Value {
    const off = try lowerExpr(ctx, off_expr);
    const scaled = ctx.freshTemp();
    try ctx.emit(.{ .op = .binop, .result = scaled, .binop = .div, .lhs = off, .rhs = .{ .i64 = 8 } });
    const idx = ctx.freshTemp();
    try ctx.emit(.{ .op = .binop, .result = idx, .binop = .add, .lhs = .{ .temp = scaled }, .rhs = .{ .i64 = 1 } });
    return .{ .temp = idx };
}

/// `to(str)(n)` — integer to decimal text. malloc(24) + snprintf(buf, 24,
/// "%lld", n): three named arguments in x0..x2 and the value in the VARIADIC
/// TAIL, which on Apple ARM64 travels on the stack.
fn lowerToStr(ctx: *LowerCtx, c: anytype) Error!?dnir.Value {
    if (c.args.len != 1) return null;
    if (c.func.* != .call) return null;
    const inner = c.func.call;
    if (inner.func.* != .name or !std.mem.eql(u8, inner.func.name.ident, "to")) return null;
    if (inner.args.len != 1 or inner.args[0].* != .name) return null;
    if (!std.mem.eql(u8, inner.args[0].name.ident, "str")) return null;
    // Decline rather than mis-lower. `"%lld"` is a constant this emitter
    // ASSUMES, and it held for exactly one argument shape: `to(str)(1.5)`
    // printed 4378777232 and `to(str)("hi")` printed 4343729785 — both the
    // operand's ADDRESS, both indistinguishable from a real answer.
    if (!exprIsIntegral(ctx, c.args[0])) return null;

    const n = try lowerExpr(ctx, c.args[0]);
    return .{ .temp = try emitIntToStr(ctx, n) };
}

/// Render an already-lowered INTEGER value as decimal text, and answer the temp
/// holding the buffer.
///
/// Shared by `to(str)(n)` and by `..`, on purpose: two emitters for "number to
/// decimal" is two chances to disagree with the C backend, and the caller is
/// responsible for having proved the value is an integer — `"%lld"` is a
/// constant this assumes and cannot check from a register.
fn emitIntToStr(ctx: *LowerCtx, n: dnir.Value) Error!u32 {
    try ensureExtern(ctx, "mem", "alloc", "malloc");
    try ensureExtern(ctx, "string", "format", "snprintf");
    const buf = ctx.freshTemp();
    try ctx.emit(.{ .op = .call_extern, .result = buf, .callee = "malloc", .lhs = .{ .i64 = 24 } });
    try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = .{ .temp = buf } });
    try ctx.emit(.{ .op = .mov_arg, .result = 1, .lhs = .{ .i64 = 24 } });
    try ctx.emit(.{ .op = .mov_arg, .result = 2, .lhs = .{ .str = "%lld" } });
    // `n` is past snprintf's last NAMED parameter, so it is a VARIADIC-tail
    // argument. Apple's ARM64 ABI passes that tail on the stack, not in x3;
    // `.field = "vararg"` tells the backend to stage it there. Staging it as
    // an ordinary fourth register argument assembles to textbook-correct code
    // and still prints a pointer, because snprintf never reads x3.
    try ctx.emit(.{ .op = .mov_arg, .result = 0, .field = "vararg", .lhs = n });
    try ctx.emit(.{ .op = .call_extern, .callee = "snprintf" });
    return buf;
}

/// `a.b.c` -> "a.b.c" into `out`. False for anything not a pure name chain.
fn flattenNames(alloc: std.mem.Allocator, e: *const ast.Expr, out: *std.ArrayList(u8)) !bool {
    switch (e.*) {
        .name => |n| {
            try out.appendSlice(alloc, n.ident);
            return true;
        },
        .field => |fl| {
            if (!try flattenNames(alloc, fl.obj, out)) return false;
            try out.append(alloc, '.');
            try out.appendSlice(alloc, fl.field);
            return true;
        },
        else => return false,
    }
}

fn lowerNamedDirectCall(
    ctx: *LowerCtx,
    callee: []const u8,
    args: []const *ast.Expr,
    consumption: types.ReturnConsumption,
) Error!dnir.Value {
    const discard = consumption == .discard;
    try emitScalarCallArgs(ctx, args, callee);
    if (discard) {
        try ctx.emit(.{ .op = .call_direct, .callee = callee, .lhs = .void });
        return .void;
    }
    const t = ctx.freshTemp();
    try ctx.emit(.{ .op = .call_direct, .result = t, .callee = callee, .lhs = .void });
    return .{ .temp = t };
}

fn tryLowerRelationEdgeCall(
    ctx: *LowerCtx,
    expr: *const ast.Expr,
    consumption: types.ReturnConsumption,
) Error!?dnir.Value {
    if (ctx.require_graph_facts) return null;
    if (expr.* != .call) return null;
    const c = expr.call;
    if (c.func.* != .call) return null;
    const inner = c.func.call;
    if (inner.func.* != .name or inner.args.len != 1 or c.args.len != 1) return null;
    const sym = ctx.relation_edges.get(inner.func.name.ident) orelse return null;
    const args = [_]*ast.Expr{ inner.args[0], c.args[0] };
    return try lowerNamedDirectCall(ctx, sym, &args, consumption);
}

/// Subject-first relation edge — `path:len(min)` fuses to `len__path(path, min)`.
fn tryLowerSubjectRelationEdgeCall(
    ctx: *LowerCtx,
    expr: *const ast.Expr,
    consumption: types.ReturnConsumption,
) Error!?dnir.Value {
    if (ctx.require_graph_facts) return null;
    if (expr.* != .method_call) return null;
    const mc = expr.method_call;
    const sym = ctx.relation_edges.get(mc.method) orelse return null;
    if (mc.args.len != 1) return null;
    const args = [_]*ast.Expr{ mc.obj, mc.args[0] };
    return try lowerNamedDirectCall(ctx, sym, &args, consumption);
}

/// `print(v)` spelled as host egress — the same node `stdout:write(v)` reaches.
///
/// This is a SHAPE test, never an identity. It is consulted only to decide
/// which of two available lowerings wins, and THE PUBLISHED APPLICATION FACT
/// ALWAYS WINS: `native_bootstrap` recognizes this shape in every module now,
/// so a module that declares its own `print` relation would otherwise have its
/// call answered with host output — one relation silently swapped for another,
/// which is the class that passes `idol check`.
fn hostEgressCall(expr: *const ast.Expr) bool {
    if (expr.* != .call) return false;
    const c = expr.call;
    if (c.func.* != .name) return false;
    return std.mem.eql(u8, c.func.name.ident, "print");
}

fn lowerCall(ctx: *LowerCtx, expr: *const ast.Expr, consumption: types.ReturnConsumption) Error!dnir.Value {
    if (expr.* != .call) return bail(ctx.diagnostic, @src());
    if (ctx.occurrences.get(expr)) |application| {
        if (ctx.require_graph_facts and
            !paramRecordSliceFieldCall(ctx, expr) and
            (hostEgressCall(expr) or !ctx.graph.isBootstrapApplicationNode(application.application)))
        {
            return lowerCheckedScalarCall(ctx, application, consumption);
        }
    }
    if (ctx.require_graph_facts and !ctx.graph.bootstrapApplicationExpr(expr) and
        !paramRecordSliceFieldCall(ctx, expr))
    {
        return refuseMissingApplication(ctx, @src(), expr);
    }
    const c = expr.call;
    if (c.func.* == .name and std.mem.eql(u8, c.func.name.ident, "write") and c.args.len == 2) {
        return lowerStreamWrite(ctx, c.args[0], c.args[1]);
    }
    if (c.func.* == .name and std.mem.eql(u8, c.func.name.ident, "close") and c.args.len == 1) {
        return lowerStreamClose(ctx, c.args[0]);
    }
    if (try tryLowerRelationEdgeCall(ctx, expr, consumption)) |value| return value;
    const discard = consumption == .discard;
    if (c.func.* == .name and std.mem.eql(u8, c.func.name.ident, "gatecap") and c.args.len == 1) {
        const arg = try lowerExpr(ctx, c.args[0]);
        try ensureExtern(ctx, "gate", "cap", "idol_process_capture");
        const t = ctx.freshTemp();
        try ctx.emit(.{ .op = .call_extern, .result = t, .callee = "idol_process_capture", .lhs = arg, .ty = .str });
        return .{ .temp = t };
    }
    if (try lowerToStr(ctx, c)) |v| return v;
    if (c.func.* == .name and std.mem.eql(u8, c.func.name.ident, "to") and c.args.len == 2) {
        return lowerSubjectTo(ctx, c.args[0], c.args[1], consumption);
    }
    // `to(T)(x)` FOR EVERY OTHER T. `lowerToStr` above answers the one target
    // it was written for and declines the rest by returning null, which left
    // the curried face with no route to the conversion table `x:to(T)` and
    // `to(x, T)` both already reach. Three spellings of one edge, and only two
    // of them arrived — so the same conversion refused or answered depending on
    // how it was written, which is the capability tax §10.2 forbids.
    if (c.args.len == 1 and c.func.* == .call) {
        const inner = c.func.call;
        if (inner.func.* == .name and std.mem.eql(u8, inner.func.name.ident, "to") and
            inner.args.len == 1 and inner.args[0].* == .name)
        {
            return lowerSubjectTo(ctx, c.args[0], inner.args[0], consumption);
        }
    }
    if (c.func.* == .field) {
        const f = c.func.field;
        // A DOTTED callee — `std.compiler.lexer.new` has `f.obj` as a `.field`,
        // so the whole alias-based body below was skipped and the call fell to
        // the generic bail. The module is now collected by
        // native_req_support.collectDottedCallee, so resolve by PATH.
        if (f.obj.* == .field) {
            var pbuf: std.ArrayList(u8) = .empty;
            defer pbuf.deinit(ctx.alloc);
            if (flattenNames(ctx.alloc, f.obj, &pbuf) catch false) {
                // native_req_support removed, no dotted callee path lookup
            }
        }
        if (f.obj.* == .name) {
            // `os.exit(n)` is libc `exit` — a plain extern call, the same shape
            // `#s` already uses for strlen. It was refused only because `os` is
            // a runtime global by name, not because the call needs a runtime.
            //
            // Deliberately just this one. `os.clock` is NOT here: Lua's returns
            // seconds as a float and C's returns ticks, so lowering it to the
            // libc symbol would change what the program measures — a silent
            // semantic swap, not a lowering.
            // `mem.alloc/free/zero/addr` are libc, not a runtime. alloc and free are
            // single-argument extern calls -- the same shape `#s` uses for
            // strlen -- and `mem.read(p, i)` is a byte load, the same shape
            // `string.byte` uses. The rest of the family (cast, load with a
            // type argument, store, copy, zero) is a TYPED POINTER surface that
            // needs a pointer type in DNIR; these three do not, and were
            // refused only because `mem` is a runtime global by name.
            // `string.char(n)` — malloc(2), the character, the NUL. Allocation
            // was never the blocker; the byte-width STORE was. Indices are
            // 1-BASED because store_index shares one origin with the byte load.
            if (std.mem.eql(u8, f.obj.name.ident, "string") and
                std.mem.eql(u8, f.field, "char") and c.args.len == 1)
            {
                const code = try lowerExpr(ctx, c.args[0]);
                try ensureExtern(ctx, "mem", "alloc", "malloc");
                const buf = ctx.freshTemp();
                try ctx.emit(.{ .op = .call_extern, .result = buf, .callee = "malloc", .lhs = .{ .i64 = 2 } });
                try ctx.emit(.{ .op = .store_index, .ty = .any, .lhs = .{ .temp = buf }, .rhs = .{ .i64 = 1 }, .third = code });
                try ctx.emit(.{ .op = .store_index, .ty = .any, .lhs = .{ .temp = buf }, .rhs = .{ .i64 = 2 }, .third = .{ .i64 = 0 } });
                return .{ .temp = buf };
            }
            // THE `c` WORLD. `c.abs(0 - 7)` is anchored access on a world
            // value — no directive, and the same shape `math.sqrt(x)` below has
            // always had. `docs/foreign-world.md` §9.6 measured the machinery as
            // already present: "the direct backend already emits `call_extern`
            // with a relocation — `print` proves it by importing `_puts` — so
            // what is missing is the fact, not the machinery." This is the fact.
            //
            // THE ROSTER IS ASKED, NOT RESTATED. `subject_home.isCMember` is
            // the one place the membership lives, so this cannot drift from what
            // sema believes the world provides. A world that forwarded any name
            // would not be a capability at all.
            //
            // A MODULE THAT BINDS `c` ITSELF KEEPS IT, and the `ctx.locals`
            // test is what makes that true rather than lucky. Injection adds
            // reach, it never takes a name, so a local called `c` shadows the
            // world exactly as it shadows `os`. Measured before adding it: zero
            // corpus files call `c.abs` or `c.labs`, but 168 bind a name `c`,
            // so the collision was one `abs` away and the comment claiming
            // shadowing worked would have been the only thing implementing it.
            if (!ctx.require_graph_facts and
                std.mem.eql(u8, f.obj.name.ident, "c") and c.args.len == 1 and
                subject_home.isCMember(f.field) and ctx.locals.get("c") == null)
            {
                const arg = try lowerExpr(ctx, c.args[0]);
                try ensureExtern(ctx, "c", f.field, f.field);
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .call_extern, .result = t, .callee = f.field, .lhs = arg, .ty = .i64 });
                return .{ .temp = t };
            }
            if (std.mem.eql(u8, f.obj.name.ident, "math") and c.args.len == 1) {
                const fname = f.field;
                const known = std.mem.eql(u8, fname, "sqrt") or std.mem.eql(u8, fname, "sin") or
                    std.mem.eql(u8, fname, "cos") or std.mem.eql(u8, fname, "fabs") or
                    std.mem.eql(u8, fname, "floor") or std.mem.eql(u8, fname, "ceil");
                if (known) {
                    const arg = try lowerExpr(ctx, c.args[0]);
                    try ensureExtern(ctx, "math", fname, fname);
                    const t = ctx.freshTemp();
                    try ctx.emit(.{ .op = .call_extern, .result = t, .callee = fname, .lhs = arg, .ty = .f64 });
                    return .{ .temp = t };
                }
            }
            if (std.mem.eql(u8, f.obj.name.ident, "mem")) {
                if (std.mem.eql(u8, f.field, "alloc") and c.args.len == 1) {
                    const n = try lowerExpr(ctx, c.args[0]);
                    try ensureExtern(ctx, "mem", "alloc", "malloc");
                    const t = ctx.freshTemp();
                    try ctx.emit(.{ .op = .call_extern, .result = t, .callee = "malloc", .lhs = n });
                    return .{ .temp = t };
                }
                if (std.mem.eql(u8, f.field, "free") and c.args.len == 1) {
                    const ptr = try lowerExpr(ctx, c.args[0]);
                    try ensureExtern(ctx, "mem", "free", "free");
                    try ctx.emit(.{ .op = .call_extern, .callee = "free", .lhs = ptr });
                    return .void;
                }
                // `mem.zero(p, n)` is memset(p, 0, n) — three arguments through
                // mov_arg, the same marshalling concat proved works for two.
                // `mem.read_byte(p, off)` and `mem.read_i64(p, off)` are indexed
                // loads — the same shape `string.byte` and `s[i]` already use.
                // The byte one goes through the BYTE-width arm (`.ty = .any`),
                // the i64 one through the scaled 8-byte arm (`.ty = .i64`);
                // that distinction is the whole difference between them.
                //
                // Both offsets are BYTE offsets from the caller's view, and the
                // backend's byte path computes `base + (i - 1)`, so the byte
                // read normalizes with +1 here exactly as `s[i]` does. The i64
                // arm scales by 8, so its offset is divided first.
                if (std.mem.eql(u8, f.field, "read_byte") and c.args.len == 2) {
                    const base = try lowerExpr(ctx, c.args[0]);
                    const off = try lowerExpr(ctx, c.args[1]);
                    const one = ctx.freshTemp();
                    try ctx.emit(.{ .op = .binop, .result = one, .binop = .add, .lhs = off, .rhs = .{ .i64 = 1 } });
                    const t = ctx.freshTemp();
                    try ctx.emit(.{ .op = .load_index, .result = t, .lhs = base, .rhs = .{ .temp = one } });
                    return .{ .temp = t };
                }
                // `mem.read_i64(p, byteoff)` is the SCALED load: the backend's
                // `.ty = .i64` indexed access computes `[base, idx, lsl #3]`,
                // i.e. it multiplies by 8 itself. The caller passes a BYTE
                // offset, so divide here rather than teaching the backend a
                // second addressing mode. A non-8-aligned offset is already
                // undefined for an i64 read, so the division loses nothing real.
                //
                // THE `+ 1` IS THE SAME 1-BASED BIAS THE BYTE ARM ABOVE PAYS,
                // and this arm did not pay it. The scaled path is `base +
                // (idx - 1) * 8`, so a divided-only offset read EIGHT BYTES
                // BELOW the address the caller named. MEASURED, against the
                // semantics `codegen.zig` gives the same face
                // (`*(int64_t*)((uint8_t*)p + off)`, a 0-based byte offset):
                //
                //     s = "ABCDEFGHIJKLMNOP" ; p = mem.addr(s)
                //     mem.read_byte(p, 0)  ->  65 ('A')          correct
                //     mem.read_byte(p, 8)  ->  73 ('I')          correct
                //     mem.read_i64(p, 8)   ->  "ABCDEFGH"        OFF BY ONE ELEMENT
                //     mem.read_i64(p, 0)   ->  the 8 bytes BEFORE the string
                //
                // The comment three lines up already stated the rule the code
                // broke — "the byte read normalizes with +1 here exactly as
                // `s[i]` does" — so the two halves of one face disagreed about
                // the origin of the same buffer, and only the half without a
                // scale factor was right. `read_i64(p, 0)` reading out of
                // bounds is not a subset boundary; it is a wrong answer, and it
                // was reachable from any module that could name a pointer.
                if (std.mem.eql(u8, f.field, "read_i64") and c.args.len == 2) {
                    const base = try lowerExpr(ctx, c.args[0]);
                    const idx = try lowerScaledElementIndex(ctx, c.args[1]);
                    const t = ctx.freshTemp();
                    try ctx.emit(.{ .op = .load_index, .result = t, .ty = .i64, .lhs = base, .rhs = idx });
                    return .{ .temp = t };
                }
                // THE WRITE HALF. `store_index` is the exact mirror of
                // `load_index` at both widths and both share the backend's
                // 1-based origin, so each store normalizes its offset with the
                // SAME helper its load uses — one origin, computed in one
                // place, which is the only reason the pair can be trusted to
                // agree. A buffer the direct backend can read and cannot fill
                // is not a subset of the language, it is a half of a face.
                if (std.mem.eql(u8, f.field, "write_byte") and c.args.len == 3) {
                    const base = try lowerExpr(ctx, c.args[0]);
                    const off = try lowerExpr(ctx, c.args[1]);
                    const one = ctx.freshTemp();
                    try ctx.emit(.{ .op = .binop, .result = one, .binop = .add, .lhs = off, .rhs = .{ .i64 = 1 } });
                    const val = try lowerExpr(ctx, c.args[2]);
                    try ctx.emit(.{ .op = .store_index, .ty = .any, .lhs = base, .rhs = .{ .temp = one }, .third = val });
                    return .void;
                }
                if (std.mem.eql(u8, f.field, "write_i64") and c.args.len == 3) {
                    const base = try lowerExpr(ctx, c.args[0]);
                    const idx = try lowerScaledElementIndex(ctx, c.args[1]);
                    const val = try lowerExpr(ctx, c.args[2]);
                    try ctx.emit(.{ .op = .store_index, .ty = .i64, .lhs = base, .rhs = idx, .third = val });
                    return .void;
                }
                if (std.mem.eql(u8, f.field, "write_f64") and c.args.len == 3) {
                    const base = try lowerExpr(ctx, c.args[0]);
                    const idx = try lowerScaledElementIndex(ctx, c.args[1]);
                    const val = try lowerExpr(ctx, c.args[2]);
                    try ctx.emit(.{ .op = .store_index, .ty = .i64, .lhs = base, .rhs = idx, .third = val });
                    return .void;
                }
                // `mem.ptr_from_addr(T, a)` is `mem.addr` read backwards, and
                // at this width it is the same no-op: the address IS the
                // pointer. `T` is a DESCRIPTOR, not a value, so it is never
                // lowered — asking for its register is what a type operand in
                // an argument position always looks like when it is wrong.
                if (std.mem.eql(u8, f.field, "ptr_from_addr") and c.args.len == 2) {
                    return try lowerExpr(ctx, c.args[1]);
                }
                if (std.mem.eql(u8, f.field, "zero") and c.args.len == 2) {
                    const ptr = try lowerExpr(ctx, c.args[0]);
                    const n = try lowerExpr(ctx, c.args[1]);
                    try ensureExtern(ctx, "mem", "zero", "memset");
                    try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = ptr });
                    try ctx.emit(.{ .op = .mov_arg, .result = 1, .lhs = .{ .i64 = 0 } });
                    try ctx.emit(.{ .op = .mov_arg, .result = 2, .lhs = n });
                    try ctx.emit(.{ .op = .call_extern, .callee = "memset" });
                    return .void;
                }
                // `mem.addr(x)` on a pointer-shaped value IS that value: a str
                // is already a `const char*` and an alloc result is already the
                // address. No instruction, just the value.
                if (std.mem.eql(u8, f.field, "addr") and c.args.len == 1) {
                    return try lowerExpr(ctx, c.args[0]);
                }
            }
            if (std.mem.eql(u8, f.obj.name.ident, "os") and
                std.mem.eql(u8, f.field, "execute") and c.args.len == 1)
            {
                const arg = try lowerExpr(ctx, c.args[0]);
                try ensureExtern(ctx, "os", "execute", "idol_os_execute");
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .call_extern, .result = t, .callee = "idol_os_execute", .lhs = arg, .ty = .i64 });
                return .{ .temp = t };
            }
            if (std.mem.eql(u8, f.obj.name.ident, "io") and
                std.mem.eql(u8, f.field, "open") and c.args.len == 2)
            {
                const path = try lowerExpr(ctx, c.args[0]);
                const mode = try lowerExpr(ctx, c.args[1]);
                try ensureExtern(ctx, "io", "open", "idol_io_open");
                try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = path });
                try ctx.emit(.{ .op = .mov_arg, .result = 1, .lhs = mode });
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .call_extern, .result = t, .callee = "idol_io_open", .ty = .i64 });
                return .{ .temp = t };
            }
            if (std.mem.eql(u8, f.obj.name.ident, "os") and
                std.mem.eql(u8, f.field, "remove") and c.args.len == 1)
            {
                const path = try lowerExpr(ctx, c.args[0]);
                try ensureExtern(ctx, "os", "remove", "idol_os_remove");
                try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = path });
                try ctx.emit(.{ .op = .call_extern, .callee = "idol_os_remove", .ty = .i64 });
                return .void;
            }
            if (std.mem.eql(u8, f.obj.name.ident, "os") and
                std.mem.eql(u8, f.field, "exit") and c.args.len == 1)
            {
                const arg = try lowerExpr(ctx, c.args[0]);
                try ensureExtern(ctx, "os", "exit", "exit");
                try ctx.emit(.{ .op = .call_extern, .callee = "exit", .lhs = arg });
                return .void;
            }
            // native_req_support removed, no module alias callee export lookup
            // `string.byte(s, i)` is a byte load from a `const char*`, not a
            // call. Lowering it as an indexed load keeps a tokenizer's inner
            // loop as plain native code with no runtime helper.
            if (std.mem.eql(u8, f.obj.name.ident, "string") and
                std.mem.eql(u8, f.field, "byte") and
                c.args.len >= 1 and c.args.len <= 2)
            {
                const base = try lowerExpr(ctx, c.args[0]);
                const t = ctx.freshTemp();
                if (c.args.len == 1) {
                    try ctx.emit(.{ .op = .load_index, .result = t, .lhs = base, .rhs = .{ .i64 = 1 } });
                } else {
                    const idx = try lowerExpr(ctx, c.args[1]);
                    try ctx.emit(.{ .op = .load_index, .result = t, .lhs = base, .rhs = idx });
                }
                return .{ .temp = t };
            }
            if (std.mem.eql(u8, f.obj.name.ident, "string") and
                std.mem.eql(u8, f.field, "sub") and
                c.args.len == 3)
            {
                const s = try lowerExpr(ctx, c.args[0]);
                const i = try lowerExpr(ctx, c.args[1]);
                const one = sameIndex(c.args[1], c.args[2]);
                if (one) {
                    try ensureExtern(ctx, "str", "at", "idol_str_at");
                    try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = s });
                    try ctx.emit(.{ .op = .mov_arg, .result = 1, .lhs = i });
                    const t = ctx.freshTemp();
                    try ctx.emit(.{ .op = .call_extern, .result = t, .callee = "idol_str_at", .ty = .str });
                    try ctx.str_slots.put(ctx.alloc, t, {});
                    return .{ .temp = t };
                }
                const j = try lowerExpr(ctx, c.args[2]);
                try ensureExtern(ctx, "str", "sub", "duo_str_sub");
                try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = s });
                try ctx.emit(.{ .op = .mov_arg, .result = 1, .lhs = i });
                try ctx.emit(.{ .op = .mov_arg, .result = 2, .lhs = j });
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .call_extern, .result = t, .callee = "duo_str_sub", .ty = .str });
                try ctx.str_slots.put(ctx.alloc, t, {});
                return .{ .temp = t };
            }
            if (std.mem.eql(u8, f.obj.name.ident, "string") and
                std.mem.eql(u8, f.field, "match") and
                c.args.len == 2)
            {
                const s = try lowerExpr(ctx, c.args[0]);
                const pat = try lowerExpr(ctx, c.args[1]);
                try ensureExtern(ctx, "str", "match", "idol_str_match");
                try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = s });
                try ctx.emit(.{ .op = .mov_arg, .result = 1, .lhs = pat });
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .call_extern, .result = t, .callee = "idol_str_match", .ty = .str });
                return .{ .temp = t };
            }
            // `string.len(s)` is a byte-length scan over a `const char*`, not a
            // call. Lowering it as `str_len` (an inline loop in the backend)
            // keeps the lexer's `while self.pos <= string.len(self.src)` guard
            // inside the direct subset instead of forcing the C backend.
            if (std.mem.eql(u8, f.obj.name.ident, "string") and
                std.mem.eql(u8, f.field, "len") and
                c.args.len == 1)
            {
                const base = try lowerExpr(ctx, c.args[0]);
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .str_len, .result = t, .lhs = base });
                return .{ .temp = t };
            }
            // `pack.kinds(i)` — slice field on a bound parameter record. Same
            // scaled indexed load as `mem.read_i64`, without graph aggregate
            // facts. Module-qualified calls (`lexer.last_kind(lx)`) must not
            // take this path — they are published applications.
            if (c.args.len == 1 and recordLocalDesc(ctx, f.obj.name.ident) != null) {
                const base = try lowerField(ctx, c.func);
                const idx = try lowerScaledElementIndex(ctx, c.args[0]);
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .load_index, .result = t, .ty = .i64, .lhs = base, .rhs = idx });
                return .{ .temp = t };
            }
            // Static module member: math.add(a, b) → call_direct math.add
            const qualified = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ f.obj.name.ident, f.field });
            const arg0 = try scalarCallLhs(ctx, c.args, qualified);
            if (discard) {
                try ctx.emit(.{ .op = .call_direct, .callee = qualified, .lhs = arg0 });
                return .void;
            }
            const t = ctx.freshTemp();
            try ctx.emit(.{ .op = .call_direct, .result = t, .callee = qualified, .lhs = arg0 });
            return .{ .temp = t };
        }
    }
    if (c.func.* == .name) {
        if (dnir_hardware.parseIntrinsic(c.func.name.ident)) |hw| {
            return try lowerHwIntrinsic(ctx, hw, c.args);
        }
        const callee = c.func.name.ident;
        if (functionResultIs(ctx, callee, .f64)) {
            return try lowerF64KernelCall(ctx, callee, c.args);
        }
        if (std.mem.eql(u8, callee, "print")) {
            return lowerPrint(ctx, c.args);
        }
        const arg0 = try scalarCallLhs(ctx, c.args, callee);
        if (discard) {
            try ctx.emit(.{
                .op = .call_direct,
                .callee = callee,
                .lhs = arg0,
            });
            return .void;
        }
        const t = ctx.freshTemp();
        try ctx.emit(.{
            .op = .call_direct,
            .result = t,
            .callee = callee,
            .lhs = arg0,
        });
        return .{ .temp = t };
    }
    if (ctx.require_graph_facts) return refuseMissingApplication(ctx, @src(), expr);
    // Name the callee. Every row this session that reported only a location
    // turned out to be covering more than one cause, and a call site's whole
    // content is "I could not resolve this callee" — the name IS the finding.
    return bailWith(ctx.diagnostic, @src(), switch (c.func.*) {
        .name => |n| n.ident,
        .field => |f| f.field,
        else => @tagName(c.func.*),
    });
}

/// `print(v)` — sovereign native output (DNIR `print_value`). Zero-arg prints a
/// blank line; one typed scalar arg lowers to `puts`/`printf` in the backend.
/// Unsupported arg shapes (multi-arg, tables, records) fall through to the AST
/// path, which reports the honest DNB001 — the direct subset still refuses
/// rather than boxing.
/// Flatten a left-leaning `..` chain into its parts, in evaluation order.
fn flattenConcat(alloc: std.mem.Allocator, e: *const ast.Expr, out: *std.ArrayListUnmanaged(*const ast.Expr)) Error!void {
    if (e.* == .binop and e.binop.op == .concat) {
        try flattenConcat(alloc, e.binop.lhs, out);
        try flattenConcat(alloc, e.binop.rhs, out);
        return;
    }
    try out.append(alloc, e);
}

/// `print("{a} {b} {c}")` as ONE `printf`, with the literal text as the format.
///
/// The parser desugars an interpolated literal into a left-leaning chain of
/// `..`, and lowering that chain literally costs one malloc, one strcpy and one
/// strcat per hole with every intermediate buffer live across all of them.
/// Three holes is 26 values live at once; the backend has 19 allocatable
/// registers and leaks one more per result-less call, so the ladder assembled,
/// printed the right text, and then returned a wrong exit code or walked off
/// the stack. Measured on `a .. "-" .. b .. "-" .. c`: correct output, exit 240
/// where the answer is 0 — a WRONG ANSWER reached by a construct that compiled.
///
/// The format string removes the problem rather than budgeting around it. The
/// literal parts ARE the format, each hole contributes one conversion, and
/// nothing is allocated at all: live values drop to one per hole, and those
/// travel in the variadic tail, which Apple's ARM64 ABI passes in memory.
///
/// Returns null — not a bail — when the shape is not one this can render. The
/// caller then lowers the argument the ordinary way.
fn lowerPrintFormat(ctx: *LowerCtx, arg: *const ast.Expr, newline: bool) Error!?dnir.Value {
    if (arg.* != .binop or arg.binop.op != .concat) return null;

    var parts: std.ArrayListUnmanaged(*const ast.Expr) = .empty;
    defer parts.deinit(ctx.alloc);
    try flattenConcat(ctx.alloc, arg, &parts);

    // `print` ends a line. `print_value` gets that from `puts`; here it is one
    // more byte of format. `stdout:write` ends NOTHING — see `lowerWrite`.
    const plan = (try planConcat(ctx, parts.items, newline)) orelse return null;

    var vals: [max_concat_holes]dnir.Value = undefined;
    for (plan.holes[0..plan.count], 0..) |h, i| vals[i] = try lowerExpr(ctx, h);

    try ensureExtern(ctx, "io", "printf", "printf");
    try stageConcatHoles(ctx, vals[0..plan.count]);
    try ctx.emit(.{ .op = .call_extern, .callee = "printf", .lhs = .{ .str = plan.fmt } });
    return .void;
}

fn lowerPrint(ctx: *LowerCtx, args: []const *ast.Expr) Error!dnir.Value {
    if (args.len == 0) {
        try ctx.emit(.{ .op = .print_value });
        return .void;
    }
    if (args.len != 1) return bail(ctx.diagnostic, @src());
    const arg = args[0];
    if (try lowerPrintFormat(ctx, arg, true)) |v| return v;
    const v = try lowerExpr(ctx, arg);
    const ty: RT = if (exprIsStr(ctx, arg) or holds(ctx, v)) .str else if (exprIsF64Value(ctx, arg)) .f64 else .i64;
    try ctx.emit(.{ .op = .print_value, .lhs = v, .ty = ty });
    return .void;
}

/// `stdout:write(v)` — the SAME egress as `print`, MINUS the line ending.
///
/// These two shared one lowering, and the shared one was `print`'s: `.str`
/// reached `print_value`, `print_value` calls `puts`, and `puts` APPENDS A
/// NEWLINE THE PROGRAM DID NOT WRITE. Measured on the canonical backend against
/// `--backend=c`, one source, two answers:
///
///     stdout:write("A=V\n")      direct: A = V \n \n   c: A = V \n
///     stdout:write("XY") ; …("Z")  direct: X Y \n Z \n   c: X Y Z
///
/// The second is the one that shows it is not a trailing-newline cosmetic: the
/// bytes are INTERLEAVED wrongly, so a program that composes output from
/// several writes cannot produce its answer at all under the canonical backend.
/// `--backend=c` is right here — `write` writes what it is given, which is also
/// what `io.write` means everywhere this dialect borrows from, and what the
/// refuse gate's own note records (`stdout:write("A") -> A`).
///
/// The line ending was never a `print_value` property, so it is not removed by
/// one: `.field = "nonl"` says the ending belongs to the CALLER, and `print`
/// keeps `puts` untouched. A concat argument takes the same route it always
/// took, with `newline` false, so the format string carries no `\n` either.
fn lowerStreamWrite(ctx: *LowerCtx, obj: *const ast.Expr, text: *const ast.Expr) Error!dnir.Value {
    const handle = try lowerExpr(ctx, obj);
    const arg = try lowerExpr(ctx, text);
    try ensureExtern(ctx, "io", "write", "idol_io_write_handle");
    try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = handle });
    try ctx.emit(.{ .op = .mov_arg, .result = 1, .lhs = arg });
    try ctx.emit(.{ .op = .call_extern, .callee = "idol_io_write_handle", .ty = .i64 });
    return .void;
}

fn lowerStreamClose(ctx: *LowerCtx, obj: *const ast.Expr) Error!dnir.Value {
    const handle = try lowerExpr(ctx, obj);
    try ensureExtern(ctx, "io", "close", "idol_io_close_handle");
    try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = handle });
    try ctx.emit(.{ .op = .call_extern, .callee = "idol_io_close_handle", .ty = .i64 });
    return .void;
}

fn lowerWrite(ctx: *LowerCtx, args: []const *ast.Expr) Error!dnir.Value {
    if (args.len != 1) return bail(ctx.diagnostic, @src());
    const arg = args[0];
    if (try lowerPrintFormat(ctx, arg, false)) |v| return v;
    const v = try lowerExpr(ctx, arg);
    const ty: RT = if (exprIsStr(ctx, arg) or holds(ctx, v)) .str else if (exprIsF64Value(ctx, arg)) .f64 else .i64;
    try ctx.emit(.{ .op = .print_value, .lhs = v, .ty = ty, .field = "nonl" });
    return .void;
}

/// True when a `print` argument is a known f64 value: float literal, an f64
/// local slot, or a recognized f64 kernel call.
fn exprIsF64Value(ctx: *LowerCtx, expr: *const ast.Expr) bool {
    return switch (expr.*) {
        .float_lit => true,
        .name => |n| blk: {
            const slot = ctx.locals.get(n.ident) orelse break :blk false;
            break :blk ctx.f64_slots.contains(slot);
        },
        .call => exprReturnsF64(ctx, expr),
        else => false,
    };
}

fn lowerF64KernelCall(ctx: *LowerCtx, callee: []const u8, args: []const *ast.Expr) Error!dnir.Value {
    var slot: u32 = 0;
    for (args) |arg| {
        switch (arg.*) {
            .table => {
                if (inferRecordNameFromTable(ctx.records, arg)) |rec_name| {
                    _ = try lowerInlineRecordArg(ctx, arg, rec_name);
                }
                for (arg.table.fields) |fld| {
                    const val = switch (fld) {
                        .named => |nf| nf.val,
                        .positional => |v| v,
                        else => return bail(ctx.diagnostic, @src()),
                    };
                    try ctx.emit(.{ .op = .fp_mov_arg, .result = slot, .lhs = try lowerExpr(ctx, val) });
                    slot += 1;
                    if (slot > 8) return bail(ctx.diagnostic, @src());
                }
            },
            .name => |n| {
                if (try emitF64RecordFieldsFromName(ctx, n.ident, &slot)) {} else {
                    try ctx.emit(.{ .op = .fp_mov_arg, .result = slot, .lhs = try lowerExpr(ctx, arg) });
                    slot += 1;
                    if (slot > 8) return bail(ctx.diagnostic, @src());
                }
            },
            else => {
                try ctx.emit(.{ .op = .fp_mov_arg, .result = slot, .lhs = try lowerExpr(ctx, arg) });
                slot += 1;
                if (slot > 8) return bail(ctx.diagnostic, @src());
            },
        }
    }
    const t = ctx.freshTemp();
    try ctx.emit(.{ .op = .call_direct, .result = t, .callee = callee, .ty = .f64 });
    return .{ .temp = t };
}

fn lowerHwIntrinsic(ctx: *LowerCtx, hw: dnir.HwIntrinsic, args: []const *const ast.Expr) Error!dnir.Value {
    return switch (hw) {
        .fence => {
            try ctx.emit(.{ .op = .hw_fence, .hw = .fence });
            return .{ .i64 = 0 };
        },
        .spin_wait => {
            try ctx.emit(.{ .op = .hw_spin, .hw = .spin_wait });
            return .{ .i64 = 0 };
        },
        .popcount, .clz, .ctz => {
            if (args.len != 1) return bail(ctx.diagnostic, @src());
            const t = ctx.freshTemp();
            try ctx.emit(.{
                .op = .hw_unary,
                .hw = hw,
                .result = t,
                .lhs = try lowerExpr(ctx, args[0]),
            });
            return .{ .temp = t };
        },
        .none => bail(ctx.diagnostic, @src()),
    };
}

fn ensureExtern(ctx: *LowerCtx, alias: []const u8, field: []const u8, sym: []const u8) Error!void {
    for (ctx.externs.items) |e| {
        if (std.mem.eql(u8, e.symbol, sym)) return;
    }
    const duo = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ alias, field });
    const symbol = ctx.alloc.dupe(u8, sym) catch |err| {
        ctx.alloc.free(duo);
        return err;
    };
    ctx.externs.append(ctx.alloc, .{ .duo_name = duo, .symbol = symbol }) catch |err| {
        ctx.alloc.free(duo);
        ctx.alloc.free(symbol);
        return err;
    };
}

fn lowerField(ctx: *LowerCtx, expr: *const ast.Expr) Error!dnir.Value {
    if (expr.* != .field) return bail(ctx.diagnostic, @src());
    if (ctx.require_graph_facts) {
        if (ctx.occurrences.exactValue(expr)) |value_id| {
            if (ctx.graph.exactI64(value_id)) |mv| return .{ .i64 = mv };
        }
        if (ctx.occurrences.get(expr)) |application| {
            if (ctx.graph.aggregateAccess(application.application) != null)
                return lowerAggregateAccess(ctx, application, .single);
            if (ctx.graph.applicationResults(application.application)) |rs| {
                if (rs.len == 1) {
                    if (ctx.graph.exactI64(rs[0])) |mv| return .{ .i64 = mv };
                }
            }
        }
    }
    if (cwd(expr)) {
        try ensureExtern(ctx, "os", "cwd", "idol_os_cwd");
        const t = ctx.freshTemp();
        try ctx.emit(.{ .op = .call_extern, .result = t, .callee = "idol_os_cwd", .ty = osResult("cwd") });
        return .{ .temp = t };
    }
    const fld = expr.field;
    if (fld.obj.* == .name) {
        // Module-level descriptor constant: `Kind.ident` folds to an immediate.
        const mk = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ fld.obj.name.ident, fld.field });
        defer ctx.alloc.free(mk);
        if (ctx.module_consts.ints.get(mk)) |mv| return .{ .i64 = mv };
        if (ctx.module_consts.strs.get(mk)) |sv| return .{ .str = sv };
        // native_req_support removed, no constant fallback lookup
        const key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ fld.obj.name.ident, fld.field });
        defer ctx.alloc.free(key);
        if (ctx.locals.get(key)) |slot| return .{ .local = slot };
        if (try loadFieldFromOpaquePath(ctx, key, null)) |v| return v;
        if (opaqueRecordParam(ctx, fld.obj.name.ident)) |op| {
            if (recordDescForOpaqueParam(ctx, op)) |rec| {
                if (recordFieldHasNestedFields(rec, fld.field)) {
                    return bail(ctx.diagnostic, @src());
                }
            }
        }
    }
    if (fld.obj.* == .call or fld.obj.* == .method_call) {
        if (try lowerCallRecordFieldProjection(ctx, fld.obj, fld.field)) |v| return v;
        if (try callFieldSuffixFromExpr(ctx, expr)) |cf| {
            if (try lowerCallRecordFieldProjection(ctx, cf.call, cf.suffix)) |v| return v;
        }
        return bail(ctx.diagnostic, @src());
    }
    // `o.i.x` — a read through a NESTED record. The explosion wrote the leaf
    // under the dotted key `o.i.x`, so the whole chain resolves to one local
    // and costs nothing at runtime.
    //
    // Bailing when the chain does not resolve is the point of this arm. The
    // fallthrough below sets `req_alias` to "" for any non-name base, emitting
    // a `load_field` against an empty object — an address this pass cannot
    // name. A refusal sends the module to the C backend intact; the alternative
    // is a load from nowhere.
    if (fld.obj.* == .field) {
        if (try callFieldSuffixFromExpr(ctx, expr)) |cf| {
            if (try lowerCallRecordFieldProjection(ctx, cf.call, cf.suffix)) |v| return v;
        }
        var path: std.ArrayList(u8) = .empty;
        defer path.deinit(ctx.alloc);
        if (try flattenNames(ctx.alloc, expr, &path)) {
            if (try loadFieldFromOpaquePath(ctx, path.items, null)) |v| return v;
            if (ctx.locals.get(path.items)) |slot| {
                return .{ .local = slot };
            }
        }
        return bail(ctx.diagnostic, @src());
    }
    const t = ctx.freshTemp();
    const base: []const u8 = if (fld.obj.* == .name) fld.obj.name.ident else "";
    try ctx.emit(.{
        .op = .load_field,
        .result = t,
        .req_alias = base,
        .field = fld.field,
    });
    return .{ .temp = t };
}

test "dnir_lower: hardware direct module" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    @comp.hint.fence()
        \\    bits = @comp.bit.popcount(47)
        \\    if bits != 5 return 1 end
        \\    @comp.hint.fence()
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "hardware_direct.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    try std.testing.expect(m.hardware_tier == .scalar);
    try std.testing.expect(dnir.moduleIsNativeDirectReady(m));
    var saw_fence = false;
    var saw_pop = false;
    for (m.functions[0].blocks[0].instrs) |ins| {
        if (ins.op == .hw_fence) saw_fence = true;
        if (ins.op == .hw_unary and ins.hw == .popcount) saw_pop = true;
    }
    try std.testing.expect(saw_fence and saw_pop);
}

test "dnir_lower: hardware popcount" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    return @popcount(47)
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "test.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    const ins = m.functions[0].blocks[0].instrs[0];
    try std.testing.expect(ins.op == .hw_unary and ins.hw == .popcount);
    try std.testing.expect(m.hardware_tier == .scalar);
}

test "dnir_lower: f64 record kernel" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "dnir_kernel.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    try std.testing.expect(m.functions.len == 2);
    try std.testing.expect(m.functions[0].is_float_kernel or m.functions[1].is_float_kernel);
    try std.testing.expect(dnir.moduleIsNativeDirectReady(m));
    var saw_fmul = false;
    for (m.functions) |f| {
        if (!f.is_float_kernel) continue;
        for (f.blocks[0].instrs) |ins| {
            if (ins.op == .binop and ins.binop == .mul) saw_fmul = true;
            if (ins.op == .load_field) try std.testing.expect(ins.field.len > 0);
        }
    }
    try std.testing.expect(saw_fmul);
}

test "dnir_lower: f64 kernel call with table literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    distance2({ x = 3.0, y = 4.0 })
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "f64_call.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    try std.testing.expect(m.functions.len == 2);
    var saw_fp_mov = false;
    var saw_f64_call = false;
    for (m.functions) |f| {
        if (std.mem.eql(u8, f.name, "main")) {
            for (f.blocks[0].instrs) |ins| {
                if (ins.op == .fp_mov_arg) saw_fp_mov = true;
                if (ins.op == .call_direct and ins.ty == .f64) saw_f64_call = true;
            }
        }
    }
    try std.testing.expect(saw_fp_mov and saw_f64_call);
}

test "dnir_lower: while loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main: i64 = (n: i64)
        \\    i = 0
        \\    while i < n
        \\        i += 1
        \\    end
        \\    i
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "while.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_back_branch = false;
    for (m.functions[0].blocks[0].instrs) |ins| {
        if (ins.op == .br and ins.branch_target < m.functions[0].blocks[0].instrs.len) saw_back_branch = true;
    }
    try std.testing.expect(saw_back_branch);
}

test "dnir_lower: numeric for" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main: i64 = (n: i64)
        \\    sum = 0
        \\    for i = 0, n
        \\        sum += i
        \\    end
        \\    sum
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "num_for.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_inc = false;
    var saw_back = false;
    for (m.functions[0].blocks[0].instrs) |ins| {
        if (ins.op == .binop and ins.binop == .add) saw_inc = true;
        if (ins.op == .br and ins.branch_target < m.functions[0].blocks[0].instrs.len) saw_back = true;
    }
    try std.testing.expect(saw_inc and saw_back);
}

test "dnir_lower: f64 local in integer main" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    r: f64 = distance2({ x = 3.0, y = 4.0 })
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "f64_local.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var main_fn: ?dnir.Function = null;
    for (m.functions) |f| {
        if (std.mem.eql(u8, f.name, "main")) main_fn = f;
    }
    const main = main_fn orelse return error.TestUnexpectedResult;
    var saw_f64_store = false;
    for (main.blocks[0].instrs) |ins| {
        if (ins.op == .store_local and ins.ty == .f64) saw_f64_store = true;
    }
    try std.testing.expect(saw_f64_store);
}

test "dnir_lower: multi-arg f64 kernel" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\add2(a: f64, b: f64): f64
        \\    a + b
        \\end
        \\main(): i64
        \\    add2(1.0, 2.0)
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "add2.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var fp_movs: u32 = 0;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks[0].instrs) |ins| {
            if (ins.op == .fp_mov_arg) fp_movs += 1;
        }
    }
    try std.testing.expect(fp_movs == 2);
}

test "dnir_lower: multi-arg i64 call_direct uses mov_arg" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\math.add = (a: i64, b: i64): i64
        \\    a + b
        \\end
        \\main(): i64
        \\    math.add(10, 20)
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "math_add_call.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var mov_args: u32 = 0;
    var saw_call: bool = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks[0].instrs) |ins| {
            if (ins.op == .mov_arg) mov_args += 1;
            if (ins.op == .call_direct and std.mem.eql(u8, ins.callee, "math.add")) {
                saw_call = true;
                try std.testing.expect(ins.lhs == .void);
            }
        }
    }
    try std.testing.expect(saw_call);
    try std.testing.expect(mov_args == 2);
}

test "dnir_lower: to(str)(n) stages the value as a variadic tail argument" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    s = to(str)(42)
        \\    return s:len()
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "to_str.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var named: u32 = 0;
    var varargs: u32 = 0;
    var saw_snprintf = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks[0].instrs) |ins| {
            if (ins.op == .call_extern and std.mem.eql(u8, ins.callee, "snprintf")) saw_snprintf = true;
            if (ins.op != .mov_arg) continue;
            if (std.mem.eql(u8, ins.field, "vararg")) varargs += 1 else named += 1;
        }
    }
    try std.testing.expect(saw_snprintf);
    // buf, size, format in registers; the value in the tail. Staging all four
    // in x0..x3 is what made snprintf print a pointer.
    try std.testing.expectEqual(@as(u32, 3), named);
    try std.testing.expectEqual(@as(u32, 1), varargs);
}

// A `..` chain sizes its buffer from the ANSWER, and no constant appears in it.
//
// The differential this pins is a runtime one: the same source under
// `--backend=c` and under direct produced different bytes past 4095, because
// the chain lowered to `malloc(4096)` + `snprintf(buf, 4096, …)`. A DNIR-level
// test is the part of that a unit test can hold — the SHAPE that made the
// divergence possible. If a fixed capacity ever comes back, it comes back as a
// literal size operand, and that is what this refuses.
//
// The behavioural half is measured by running both backends at 4094 / 4095 /
// 4096 / 8192 / 40000 bytes and comparing the bytes, not the lengths.
test "dnir_lower: a concat chain measures before it allocates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(seed: i64): i64
        \\    a = "left"
        \\    s = a .. "right"
        \\    return s:len()
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "concat_measure.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);

    var snprintfs: u32 = 0;
    var mallocs: u32 = 0;
    var malloc_size_is_literal = false;
    var measure_destination: ?dnir.Value = null;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks[0].instrs, 0..) |ins, i| {
            if (ins.op != .call_extern) continue;
            if (std.mem.eql(u8, ins.callee, "malloc")) {
                mallocs += 1;
                if (ins.lhs == .i64) malloc_size_is_literal = true;
            }
            if (!std.mem.eql(u8, ins.callee, "snprintf")) continue;
            snprintfs += 1;
            if (snprintfs != 1) continue;
            // The measuring call's destination and size are the two arguments
            // staged immediately before it.
            // Skipping the variadic tail matters: `stageConcatHoles` numbers
            // the holes from 0 too, so hole zero is also `result == 0`.
            var j = i;
            while (j > 0) : (j -= 1) {
                const prev = f.blocks[0].instrs[j - 1];
                if (prev.op == .mov_arg and prev.result == 0 and
                    !std.mem.eql(u8, prev.field, "vararg"))
                {
                    measure_destination = prev.lhs;
                    break;
                }
            }
        }
    }
    // Measure, then fill.
    try std.testing.expectEqual(@as(u32, 2), snprintfs);
    try std.testing.expectEqual(@as(u32, 1), mallocs);
    // The buffer is the size the measurement answered, never a constant.
    try std.testing.expect(!malloc_size_is_literal);
    // The measuring call writes nowhere: a null destination.
    try std.testing.expect(measure_destination != null);
    try std.testing.expectEqual(@as(i64, 0), measure_destination.?.i64);
}

// The other half of the same rule: a chain whose every part is a literal is
// DETERMINED, so it must not reach the allocator at all.
test "dnir_lower: a determined concat chain allocates nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    s = "abc" .. "def"
        \\    return s:len()
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "concat_determined.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks[0].instrs) |ins| {
            if (ins.op != .call_extern) continue;
            try std.testing.expect(!std.mem.eql(u8, ins.callee, "malloc"));
            try std.testing.expect(!std.mem.eql(u8, ins.callee, "snprintf"));
        }
    }
}

// An injected world adds reach; it never takes a name. A bound `io` is the
// binding, and the world spelling only survives where nothing is bound.
test "dnir_lower: a local named io is the local, not the world descriptor" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    io = 5
        \\    return io
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "world_shadow.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_ret = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks[0].instrs) |ins| {
            if (ins.op != .ret) continue;
            saw_ret = true;
            // The world arm answers `.str`, whose ADDRESS is what reached the
            // exit status: `io = 5 ; io` exited 56 rather than 5.
            try std.testing.expect(ins.lhs != .str);
        }
    }
    try std.testing.expect(saw_ret);
}

test "dnir_lower: to(str) declines a non-integer argument rather than mis-lowering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    x: f64 = 1.5
        \\    s = to(str)(x)
        \\    return s:len()
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "to_str_f64.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    // `"%lld"` is a constant the emitter assumes; an f64 there printed the
    // operand's ADDRESS. The whole program leaves the subset instead.
    try std.testing.expectError(error.GraphFactsInvalid, lowerModule(alloc, &mod));
}

test "dnir_lower: f64 kernel call with record variable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\point: {
        \\    x: f64
        \\    y: f64
        \\}
        \\distance2: f64 = (p: point)
        \\    p.x * p.x + p.y * p.y
        \\main: i64 = ()
        \\    p = { x = 3.0, y = 4.0 }
        \\    distance2(p)
        \\    0
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "record-variable.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var main_fn: ?dnir.Function = null;
    for (m.functions) |f| {
        if (std.mem.eql(u8, f.name, "main")) main_fn = f;
    }
    const main = main_fn orelse return error.TestUnexpectedResult;
    var fp_movs: u32 = 0;
    var local_fp_movs: u32 = 0;
    for (main.blocks[0].instrs) |ins| {
        if (ins.op != .fp_mov_arg) continue;
        fp_movs += 1;
        if (ins.lhs == .local) local_fp_movs += 1;
    }
    try std.testing.expect(fp_movs == 2);
    try std.testing.expect(local_fp_movs == 2);
}

test "dnir_lower: main returns f64 kernel tail" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\distance2: f64 = (x: f64, y: f64)
        \\    x * x + y * y
        \\main: f64 = ()
        \\    distance2(3.0, 4.0)
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "main-f64.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var checked = @import("sema.zig").Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&mod);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&mod, &checked, "main-f64.id");
    const m = try lowerModuleWithGraph(alloc, &mod, &graph);
    defer dnir.deinitModule(alloc, m);
    try std.testing.expect(dnir.moduleIsNativeDirectReady(m));
    var main_fn: ?dnir.Function = null;
    for (m.functions) |f| {
        if (std.mem.eql(u8, f.name, "main")) main_fn = f;
    }
    const main = main_fn orelse return error.TestUnexpectedResult;
    try std.testing.expect(main.ret == .f64);
    try std.testing.expect(!main.is_float_kernel);
    const last = main.blocks[0].instrs[main.blocks[0].instrs.len - 1];
    try std.testing.expect(last.op == .ret and last.ty == .f64);
}

test "dnir_lower: pointer descriptors cross checked applications" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\make: *u8 = (size: i64)
        \\    mem.alloc(size)
        \\pass: *u8 = (value: *u8)
        \\    value
        \\poke: i64 = (value: *u8)
        \\    mem.write_byte(value, 3, 77)
        \\    0
        \\main: i64 = ()
        \\    first: *u8 = make(8)
        \\    second: *u8 = pass(first)
        \\    mem.zero(second, 8)
        \\    ignored = poke(second)
        \\    answer = mem.read_byte(first, 3)
        \\    mem.free(first)
        \\    answer + ignored
    ;
    var lexer = @import("lexer.zig").Lexer.init(source, "pointer-transport.id");
    var parser = @import("parser.zig").Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = @import("sema.zig").Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, "pointer-transport.id");

    var diagnostic: Diagnostic = .{};
    const lowered = try lowerModuleWithGraphObserved(alloc, &module, &graph, &diagnostic);
    defer dnir.deinitModule(alloc, lowered);

    var pointer_returns: usize = 0;
    var pointer_parameters: usize = 0;
    var pointer_applications: usize = 0;
    for (lowered.functions) |function| {
        if (function.ret == .pointer) pointer_returns += 1;
        for (function.params) |parameter| {
            if (parameter.ty == .pointer) pointer_parameters += 1;
        }
        for (function.blocks) |block| {
            for (block.instrs) |instruction| {
                if (instruction.application != null and instruction.ty == .pointer) {
                    pointer_applications += 1;
                    try std.testing.expect(instruction.ty.eql(
                        graph.applicationDescriptor(instruction.application.?).?,
                    ));
                }
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 2), pointer_returns);
    try std.testing.expectEqual(@as(usize, 2), pointer_parameters);
    try std.testing.expectEqual(@as(usize, 2), pointer_applications);

    // Damage control: the operand descriptor is the authority. If it no longer
    // says pointer, physical lowering must refuse rather than infer an address
    // from the source annotation or the register that happens to carry it.
    var pass_application: ?semantic_graph.id = null;
    for (graph.application_facts.items) |fact| {
        const relation = graph.applicationRelation(fact.application) orelse continue;
        const name = (graph.get(relation) orelse continue).name orelse continue;
        if (std.mem.eql(u8, name, "pass")) pass_application = fact.application;
    }
    const application = pass_application orelse return error.TestExpectedEqual;
    // SLOT-ROLE-ONE: `pass(first)` promotes `first` to the subject slot, so the
    // pointer travels as the subject, not an ordinary operand.
    const subject = graph.applicationSubject(application) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 0), graph.applicationArguments(application).?.len);
    graph.nodes.items[subject].descriptor = .nil;
    diagnostic.reset();
    try std.testing.expectError(
        error.GraphFactsInvalid,
        lowerModuleWithGraphObserved(alloc, &module, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("application-operand-abi", diagnostic.note().?);
}

test "dnir_lower: graph result pack crosses one checked application" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\pair(n: i64): (i64, i64)
        \\    return n, n + 1
        \\main: i64 = ()
        \\    a, b = pair(40)
        \\    a + b
    ;
    var lexer = @import("lexer.zig").Lexer.init(source, "result-pack.id");
    var parser = @import("parser.zig").Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = @import("sema.zig").Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, "result-pack.id");

    var diagnostic: Diagnostic = .{};
    const lowered = try lowerModuleWithGraphObserved(alloc, &module, &graph, &diagnostic);
    defer dnir.deinitModule(alloc, lowered);
    const application = graph.applications()[0];
    const results = graph.applicationResults(application.application) orelse
        return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 2), results.len);

    var saw_return = false;
    var saw_call = false;
    for (lowered.functions) |function| {
        if (std.mem.indexOf(u8, function.name, "pair") != null) {
            try std.testing.expectEqual(@as(usize, 2), function.ret_pack.len);
            for (function.blocks[0].instrs) |instruction| {
                if (instruction.op == .ret_pack) {
                    saw_return = true;
                    try std.testing.expectEqual(@as(usize, 2), instruction.vals.len);
                }
            }
        }
        for (function.blocks[0].instrs) |instruction| {
            if (instruction.application != application.application) continue;
            saw_call = true;
            try std.testing.expectEqual(@as(usize, 2), instruction.pack_results.len);
            try std.testing.expect(instruction.result == null);
            for (instruction.pack_results, results) |projected, result| {
                try std.testing.expectEqual(result, projected.value);
                try std.testing.expect(projected.temp != null);
                try std.testing.expect(projected.ty.eql(graph.get(result).?.descriptor.?));
            }
        }
    }
    try std.testing.expect(saw_return);
    try std.testing.expect(saw_call);
    try std.testing.expect(dnir.moduleIsNativeDirectReady(lowered));

    // Damage control: a floating member belongs to the FP result file, which
    // this GP realization does not implement. Changing the graph fact must turn
    // the lowering red instead of silently reading x1 as if it were d1.
    const saved = graph.nodes.items[results[1]].descriptor;
    graph.nodes.items[results[1]].descriptor = .f64;
    defer graph.nodes.items[results[1]].descriptor = saved;
    diagnostic.reset();
    try std.testing.expectError(
        error.GraphFactsInvalid,
        lowerModuleWithGraphObserved(alloc, &module, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("application-result-abi", diagnostic.note().?);
}

test "dnir_lower: checked aggregate operand requires graph ABI facts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\point: {
        \\    x: f64
        \\    y: f64
        \\}
        \\distance: f64 = (value: point)
        \\    value.x * value.x + value.y * value.y
        \\main: f64 = ()
        \\    value = { x = 3.0, y = 4.0 }
        \\    distance(value)
    ;
    var lexer = @import("lexer.zig").Lexer.init(source, "aggregate-operand.id");
    var parser = @import("parser.zig").Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = @import("sema.zig").Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, "aggregate-operand.id");

    var diagnostic: Diagnostic = .{};
    try std.testing.expectError(
        error.GraphFactsInvalid,
        lowerModuleWithGraphObserved(alloc, &module, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("application-operand-abi", diagnostic.note().?);
    try std.testing.expect(diagnostic.application != null);
    try std.testing.expectEqualStrings("distance", diagnostic.relation.?);
}

test "dnir_lower: graph aggregate facts select one immutable nested layout" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const Sema = @import("sema.zig").Sema;
    const table_apply = @import("table_apply.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const cases = [_]struct { file: []const u8, source: []const u8 }{
        .{
            .file = "aggregate-module.id",
            .source =
            \\pairs = {{10, 11}, {20, 21}, {30, 31}}
            \\pick: i64 = (i: i64)
            \\    pairs(i)(2)
            \\main: i64 = ()
            \\    pick(2)
            ,
        },
        .{
            .file = "aggregate-local.id",
            .source =
            \\pick: i64 = (i: i64)
            \\    pairs = {{10, 11}, {20, 21}, {30, 31}}
            \\    pairs(i)(2)
            \\main: i64 = ()
            \\    pick(2)
            ,
        },
    };
    for (cases) |case| {
        var lexer = Lexer.init(case.source, case.file);
        var parser = Parser.init(&lexer, alloc);
        parser.idol_mode = true;
        var module = try parser.parse_module();
        var checked = Sema.init(alloc);
        defer checked.deinit();
        checked.idol_mode = true;
        try checked.check_module(&module);
        table_apply.normalizeModule(alloc, &module, &checked.type_map);
        var graph = semantic_graph.SemanticGraph.init(alloc);
        defer graph.deinit();
        _ = try graph.liftModuleWithCheckedCalls(&module, &checked, case.file);
        const lowered = try lowerModuleWithGraph(alloc, &module, &graph);
        defer dnir.deinitModule(alloc, lowered);

        try std.testing.expectEqual(@as(usize, 1), lowered.dense_tables.len);
        try std.testing.expectEqualSlices(
            i64,
            &.{ 10, 11, 20, 21, 30, 31 },
            lowered.dense_tables[0].values,
        );
        const root_aggregate = lowered.dense_tables[0].value;
        const root_fact = graph.aggregate(root_aggregate) orelse return error.TestExpectedEqual;
        try std.testing.expectEqual(place.Tri.yes, root_fact.contents_known);
        const root_place = graph.aggregatePlace(root_aggregate) orelse return error.TestExpectedEqual;
        try std.testing.expectEqual(
            root_aggregate,
            graph.boundAggregateAtPlace(root_fact.owner, root_place.id).?,
        );
        try std.testing.expect(graph.boundAggregateAtPlace(root_fact.owner, root_place.id + 1000) == null);

        var saw_base = false;
        var saw_outer_bounds = false;
        var saw_projection = false;
        var saw_load = false;
        for (lowered.functions) |function| {
            if (std.mem.indexOf(u8, function.name, "pick") == null) continue;
            for (function.blocks) |block| {
                for (block.instrs) |instruction| {
                    if (instruction.op == .alloc_slots and instruction.aggregate == root_aggregate) {
                        saw_base = true;
                        try std.testing.expectEqual(dnir.Value{ .i64 = 6 }, instruction.lhs);
                    }
                    if (instruction.op == .hw_unary and std.mem.eql(u8, instruction.field, index_bounds_tag)) {
                        saw_outer_bounds = true;
                        try std.testing.expectEqual(dnir.Value{ .i64 = 3 }, instruction.rhs);
                    }
                    if (instruction.op == .store_local and instruction.application != null) {
                        saw_projection = true;
                        try std.testing.expect(graph.aggregateAccess(instruction.application.?) != null);
                        try std.testing.expect(instruction.value != null);
                    }
                    if (instruction.op == .load_index and instruction.application != null) {
                        saw_load = true;
                        try std.testing.expect(graph.aggregateAccess(instruction.application.?) != null);
                        try std.testing.expect(instruction.value != null);
                        try std.testing.expectEqual(types.ResolvedType.i64, instruction.ty);
                    }
                }
            }
        }
        try std.testing.expect(saw_base);
        try std.testing.expect(saw_outer_bounds);
        try std.testing.expect(saw_projection);
        try std.testing.expect(saw_load);

        // The initializer expression is provenance after graph publication.
        // Poison its AST tag while retaining the exact graph aggregate/place
        // facts: realization must keep the same dense contents and instruction
        // shape. This fails if lowering again uses the source initializer as
        // the key that selects static aggregate realization.
        var baseline_instructions: usize = 0;
        for (lowered.functions) |function| {
            for (function.blocks) |block| baseline_instructions += block.instrs.len;
        }
        const source_initializer = @constCast(graph.valueExpression(root_aggregate) orelse
            return error.TestExpectedEqual);
        const saved_initializer = source_initializer.*;
        source_initializer.* = .{ .nil = saved_initializer.loc() };
        const relowered = try lowerModuleWithGraph(alloc, &module, &graph);
        defer dnir.deinitModule(alloc, relowered);
        source_initializer.* = saved_initializer;
        try std.testing.expectEqual(@as(usize, 1), relowered.dense_tables.len);
        try std.testing.expectEqualSlices(
            i64,
            lowered.dense_tables[0].values,
            relowered.dense_tables[0].values,
        );
        var relowered_instructions: usize = 0;
        for (relowered.functions) |function| {
            for (function.blocks) |block| relowered_instructions += block.instrs.len;
        }
        try std.testing.expectEqual(baseline_instructions, relowered_instructions);

        // Damage the member descriptor fact. The access path must fail before
        // the AST literal can be consulted as a replacement authority.
        const root_members = graph.aggregateMembers(root_aggregate) orelse return error.TestExpectedEqual;
        const saved_descriptor = graph.nodes.items[root_members[0]].descriptor;
        graph.nodes.items[root_members[0]].descriptor = .i64;
        var diagnostic: Diagnostic = .{};
        try std.testing.expectError(
            error.GraphFactsInvalid,
            lowerModuleWithGraphObserved(alloc, &module, &graph, &diagnostic),
        );
        try std.testing.expectEqualStrings("aggregate-member-pack", diagnostic.note().?);
        graph.nodes.items[root_members[0]].descriptor = saved_descriptor;

        const aggregate_row = graph.aggregate_rows.get(root_aggregate).?;
        const saved_contents = graph.aggregate_facts.items[aggregate_row].contents_known;
        graph.aggregate_facts.items[aggregate_row].contents_known = .unknown;
        diagnostic.reset();
        try std.testing.expectError(
            error.GraphFactsInvalid,
            lowerModuleWithGraphObserved(alloc, &module, &graph, &diagnostic),
        );
        try std.testing.expectEqualStrings("aggregate-static-place", diagnostic.note().?);
        graph.aggregate_facts.items[aggregate_row].contents_known = saved_contents;

        // Damage one result pack range. Access lowering must not reconstruct
        // the result from the source's outer index node.
        var outer: ?*const semantic_graph.ApplicationFact = null;
        for (graph.applications()) |application| {
            const access = graph.aggregateAccess(application.application) orelse continue;
            const result = graph.applicationResults(access.application).?[0];
            if (graph.get(result).?.descriptor.? == .i64) outer = access;
        }
        const outer_fact = outer orelse return error.TestExpectedEqual;
        const result_pack_row = graph.pack_rows.get(outer_fact.result_pack).?;
        const saved_range = graph.pack_facts.items[result_pack_row].members;
        graph.pack_facts.items[result_pack_row].members.start = std.math.maxInt(u32);
        diagnostic.reset();
        try std.testing.expectError(
            error.GraphFactsInvalid,
            lowerModuleWithGraphObserved(alloc, &module, &graph, &diagnostic),
        );
        graph.pack_facts.items[result_pack_row].members = saved_range;
    }
}

test "dnir_lower: nested aggregate constant bounds fail closed" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const Sema = @import("sema.zig").Sema;
    const table_apply = @import("table_apply.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\pairs = {{10, 11}, {20, 21}, {30, 31}}
        \\main: i64 = ()
        \\    pairs(2)(3)
    ;
    var lexer = Lexer.init(source, "aggregate-bounds.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    table_apply.normalizeModule(alloc, &module, &checked.type_map);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, "aggregate-bounds.id");
    var diagnostic: Diagnostic = .{};
    try std.testing.expectError(
        error.UnsupportedConstruct,
        lowerModuleWithGraphObserved(alloc, &module, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("aggregate-index-bounds", diagnostic.note().?);
}

test "dnir_lower: checked aggregate result consumes exact graph shape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\point: {
        \\    x: f64
        \\    y: f64
        \\}
        \\make: point = ()
        \\    { x = 1.0, y = 2.0 }
        \\main: i64 = ()
        \\    value = make()
        \\    0
    ;
    var lexer = @import("lexer.zig").Lexer.init(source, "aggregate-result.id");
    var parser = @import("parser.zig").Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = @import("sema.zig").Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, "aggregate-result.id");

    var diagnostic: Diagnostic = .{};
    const lowered = try lowerModuleWithGraphObserved(alloc, &module, &graph, &diagnostic);
    try std.testing.expectEqual(@as(usize, 1), lowered.records.len);
    const shape = lowered.records[0].semantic_shape orelse return error.TestExpectedEqual;
    var make_application: ?semantic_graph.id = null;
    for (graph.application_facts.items) |fact| {
        const relation = graph.applicationRelation(fact.application) orelse continue;
        const name = (graph.get(relation) orelse continue).name orelse continue;
        if (std.mem.eql(u8, name, "make")) make_application = fact.application;
    }
    const application = make_application orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(shape, graph.applicationResultShape(application, 0).?);

    // Damage control: deleting the exact result-value -> shape edge makes the
    // production consumer refuse. It does not recover `point` from the AST.
    const result = graph.applicationResults(application).?[0];
    var deleted = false;
    for (graph.edges.items) |*edge| {
        if (edge.from == result and edge.kind == .descriptor) {
            edge.kind = .provenance;
            deleted = true;
            break;
        }
    }
    try std.testing.expect(deleted);
    diagnostic.reset();
    try std.testing.expectError(
        error.GraphFactsInvalid,
        lowerModuleWithGraphObserved(alloc, &module, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("application-result-abi", diagnostic.note().?);
}


test "dnir_lower: typed record call assign emits field locals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\Res: @{ val: i64, pos: i64 }
        \\parse_expr: Res = (src: str, pos: i64)
        \\    return { val = 1, pos = pos + 1 }
        \\parse_factor: Res = (src: str, pos: i64)
        \\    inner: Res = parse_expr(src, pos)
        \\    return { val = inner.val, pos = inner.pos }
    ;
    var lexer = @import("lexer.zig").Lexer.init(source, "inner-res.id");
    var parser = @import("parser.zig").Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = @import("sema.zig").Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, "inner-res.id");
    var diagnostic: Diagnostic = .{};
    const lowered = try lowerModuleWithGraphObserved(alloc, &module, &graph, &diagnostic);
    var saw_call_assign = false;
    var saw_inner_val_store = false;
    for (lowered.functions) |f| {
        if (!std.mem.eql(u8, f.name, "parse_factor")) continue;
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.op == .call_direct and std.mem.eql(u8, ins.field, "inner") and ins.record.len > 0)
                    saw_call_assign = true;
                if (ins.op == .store_local and ins.field.len > 0 and std.mem.eql(u8, ins.field, "val")) {
                    if (ins.record.len > 0) saw_inner_val_store = true;
                }
            }
        }
    }
    try std.testing.expect(saw_call_assign);
    try std.testing.expect(saw_inner_val_store);
}

test "dnir_lower: no mandatory main — entry function lowers uniformly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\run(): i64
        \\    42
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "run.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    try std.testing.expect(m.functions.len == 1);
    try std.testing.expect(std.mem.eql(u8, m.functions[0].name, "run"));
}

test "dnir_lower: implicit f64 assign" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    r = distance2({ x = 3.0, y = 4.0 })
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "implicit_f64.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var main_fn: ?dnir.Function = null;
    for (m.functions) |f| {
        if (std.mem.eql(u8, f.name, "main")) main_fn = f;
    }
    const main = main_fn orelse return error.TestUnexpectedResult;
    var saw_f64_store = false;
    for (main.blocks[0].instrs) |ins| {
        if (ins.op == .store_local and ins.ty == .f64) saw_f64_store = true;
    }
    try std.testing.expect(saw_f64_store);
}

test "dnir_lower: numeric for negative step" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main: i64 = (n: i64)
        \\    sum = 0
        \\    for i = 3, n, -1
        \\        sum += i
        \\    end
        \\    sum
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "neg_for.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_geq = false;
    for (m.functions[0].blocks[0].instrs) |ins| {
        if (ins.op == .binop and ins.binop == .geq) saw_geq = true;
    }
    try std.testing.expect(saw_geq);
}

test "dnir_lower: numeric for const step binding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main: i64 = (n: i64)
        \\    step = -1
        \\    sum = 0
        \\    for i = 3, n, step
        \\        sum += i
        \\    end
        \\    sum
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "const_step.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_geq = false;
    for (m.functions[0].blocks[0].instrs) |ins| {
        if (ins.op == .binop and ins.binop == .geq) saw_geq = true;
    }
    try std.testing.expect(saw_geq);
}

test "dnir_lower: ret zero" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "test.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    try std.testing.expect(m.functions[0].blocks[0].instrs[m.functions[0].blocks[0].instrs.len - 1].op == .ret);
}

test "dnir_lower: f64 compare in integer main" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\length2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    if length2({ x = 3.0, y = 4.0 }) == 25.0
        \\        return 0
        \\    else
        \\        return 1
        \\    end
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "f64_cmp.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_f64_eq = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.op == .binop and ins.binop == .eq and ins.ty == .f64) saw_f64_eq = true;
            }
        }
    }
    try std.testing.expect(saw_f64_eq);
}

test "dnir_lower: if elseif else chain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\pick(n: i64): i64
        \\    out = 0
        \\    if n < 0
        \\        out = 11
        \\    elseif n == 0
        \\        out = 13
        \\    elseif n > 10
        \\        out = 17
        \\    else
        \\        out = 19
        \\    end
        \\    out
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "elseif.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var when_false: u32 = 0;
    for (m.functions[0].blocks[0].instrs) |ins| {
        if (ins.op == .br and ins.branch_condition == .when_false) when_false += 1;
    }
    try std.testing.expect(when_false >= 3);
}

test "dnir_lower: numeric for runtime step parameter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\sum_to(n: i64, step: i64): i64
        \\    s = 0
        \\    for i = 1, n, step
        \\        s += i
        \\    end
        \\    s
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "runtime_step.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_step_local = false;
    var saw_dynamic_add = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "sum_to")) continue;
        for (f.blocks[0].instrs) |ins| {
            if (ins.op == .store_local and ins.lhs == .local and ins.lhs.local > 0) saw_step_local = true;
            if (ins.op == .binop and ins.binop == .add and ins.rhs == .local) saw_dynamic_add = true;
        }
    }
    try std.testing.expect(saw_step_local);
    try std.testing.expect(saw_dynamic_add);
}

test "dnir_lower: lowerModuleWithGraph matches lowerModule" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\run(): i64
        \\    42
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "test.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m_direct = try lowerModule(alloc, &mod);
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCalls(&mod, "test.id");
    const m_graph = try lowerModuleWithGraph(alloc, &mod, &g);
    defer dnir.deinitModule(alloc, m_graph);
    try std.testing.expect(m_direct.graph == null);
    try std.testing.expect(m_graph.graph == &g);
    try std.testing.expect(m_direct.functions.len == m_graph.functions.len);
    try std.testing.expect(m_direct.hardware_tier == m_graph.hardware_tier);
    try std.testing.expect(m_direct.functions[0].blocks[0].instrs.len == m_graph.functions[0].blocks[0].instrs.len);
    try std.testing.expect(m_graph.functions[0].id != null);
}

test "dnir_lower: call census without application facts refuses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\observe: i64 = (value: i64)
        \\    value
        \\main: i64 = (seed: i64)
        \\    observe(42)
    ;
    var lexer = @import("lexer.zig").Lexer.init(source, "missing-application.id");
    var parser = @import("parser.zig").Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    const module = try parser.parse_module();
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCalls(&module, "missing-application.id");

    try std.testing.expectEqual(@as(usize, 0), graph.applications().len);
    var diagnostic: Diagnostic = .{};
    try std.testing.expectError(
        error.GraphFactsInvalid,
        lowerModuleWithGraphObserved(alloc, &module, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("missing-application-id", diagnostic.note().?);
}

test "dnir_lower: uncensused condition call refuses in graph mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\ready: bool = ()
        \\    true
        \\main: i64 = ()
        \\    if ready()
        \\        1
        \\    else
        \\        0
    ;
    var lexer = @import("lexer.zig").Lexer.init(source, "condition-application.id");
    var parser = @import("parser.zig").Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    const module = try parser.parse_module();
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCalls(&module, "condition-application.id");

    var diagnostic: Diagnostic = .{};
    var occurrences = try OccurrenceBridge.init(alloc, &graph, &diagnostic);
    defer occurrences.deinit();
    // The uncensused lift (`liftModuleWithCalls`, no sema census) cannot mint an
    // application id for the `ready()` condition call, so the bridge flags exactly
    // that one occurrence as unresolved — and the lowering refuses it with
    // `missing-application-id`. Both facts together are the guard: the call is not
    // silently transported without a resolved application identity.
    try std.testing.expectEqual(@as(usize, 1), occurrences.unresolved);
    try std.testing.expectError(
        error.GraphFactsInvalid,
        lowerModuleWithGraphObserved(alloc, &module, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("missing-application-id", diagnostic.note().?);
}

test "dnir_lower: diagnostics are isolated and reset by their own run" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const application_source =
        \\observe: i64 = (value: i64)
        \\    value
        \\main: i64 = (seed: i64)
        \\    observe(42)
    ;
    var application_lexer = @import("lexer.zig").Lexer.init(application_source, "application-failure.id");
    var application_parser = @import("parser.zig").Parser.init(&application_lexer, alloc);
    application_parser.idol_mode = true;
    const application_module = try application_parser.parse_module();
    var application_graph = semantic_graph.SemanticGraph.init(alloc);
    defer application_graph.deinit();
    _ = try application_graph.liftModuleWithCalls(&application_module, "application-failure.id");

    var application_diagnostic: Diagnostic = .{};
    try std.testing.expectError(
        error.GraphFactsInvalid,
        lowerModuleWithGraphObserved(
            alloc,
            &application_module,
            &application_graph,
            &application_diagnostic,
        ),
    );
    try std.testing.expectEqualStrings("missing-application-id", application_diagnostic.note().?);
    const application_site = application_diagnostic.site orelse return error.TestExpectedEqual;

    const name_source =
        \\main: i64 = ()
        \\    unknown
    ;
    var name_lexer = @import("lexer.zig").Lexer.init(name_source, "name-failure.id");
    var name_parser = @import("parser.zig").Parser.init(&name_lexer, alloc);
    name_parser.idol_mode = true;
    const name_module = try name_parser.parse_module();
    var name_graph = semantic_graph.SemanticGraph.init(alloc);
    defer name_graph.deinit();
    _ = try name_graph.liftModuleWithCalls(&name_module, "name-failure.id");

    var retry_diagnostic: Diagnostic = .{};
    try std.testing.expectError(
        error.UnsupportedConstruct,
        lowerModuleWithGraphObserved(alloc, &name_module, &name_graph, &retry_diagnostic),
    );
    try std.testing.expectEqualStrings("unknown", retry_diagnostic.note().?);
    const name_site = retry_diagnostic.site orelse return error.TestExpectedEqual;
    try std.testing.expect(!std.mem.eql(u8, application_site.fn_name, name_site.fn_name));
    try std.testing.expectEqualStrings("missing-application-id", application_diagnostic.note().?);
    try std.testing.expectEqual(application_site.line, application_diagnostic.site.?.line);

    const success_source =
        \\main: i64 = ()
        \\    0
    ;
    var success_lexer = @import("lexer.zig").Lexer.init(success_source, "success.id");
    var success_parser = @import("parser.zig").Parser.init(&success_lexer, alloc);
    success_parser.idol_mode = true;
    const success_module = try success_parser.parse_module();
    var success_graph = semantic_graph.SemanticGraph.init(alloc);
    defer success_graph.deinit();
    _ = try success_graph.liftModuleWithCalls(&success_module, "success.id");

    const lowered = try lowerModuleWithGraphObserved(
        alloc,
        &success_module,
        &success_graph,
        &retry_diagnostic,
    );
    defer dnir.deinitModule(alloc, lowered);
    try std.testing.expect(retry_diagnostic.site == null);
    try std.testing.expect(retry_diagnostic.note() == null);
    try std.testing.expectEqualStrings("missing-application-id", application_diagnostic.note().?);
}

test "dnir_lower: graph module ownership is transactional on allocation failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\first: i64 = ()
        \\    1
        \\second: i64 = ()
        \\    2
    ;
    var lexer = @import("lexer.zig").Lexer.init(source, "allocation.id");
    var parser = @import("parser.zig").Parser.init(&lexer, arena.allocator());
    parser.idol_mode = true;
    const module = try parser.parse_module();
    var graph = semantic_graph.SemanticGraph.init(arena.allocator());
    defer graph.deinit();
    _ = try graph.liftModuleWithCalls(&module, "allocation.id");

    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(
            alloc: std.mem.Allocator,
            input: *const ast.Module,
            resident: *const semantic_graph.SemanticGraph,
        ) !void {
            const lowered = try lowerModuleWithGraph(alloc, input, resident);
            defer dnir.deinitModule(alloc, lowered);
        }
    }.run, .{ &module, &graph });
}

test "dnir_lower: call result class comes from graph descriptor" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\measure: f64 = ()
        \\    1.5
        \\count: i64 = ()
        \\    1
        \\label: str = "ok"
        \\length: i64 = (seed: i64)
        \\    label:len()
        \\floating: f64 = ()
        \\    measure()
        \\integer: i64 = (seed: i64)
        \\    count()
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "result_query.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var checked = @import("sema.zig").Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&mod);
    const m = try lowerModule(alloc, &mod);

    var saw_float = false;
    var saw_integer = false;
    var saw_string = false;
    var saw_length = false;
    for (m.functions) |f| {
        for (f.blocks[0].instrs) |ins| {
            if (ins.op == .call_direct and std.mem.eql(u8, ins.callee, "measure")) {
                saw_float = true;
                try std.testing.expectEqual(RT.f64, ins.ty);
            }
            if (ins.op == .call_direct and std.mem.eql(u8, ins.callee, "count")) {
                saw_integer = true;
                try std.testing.expect(ins.ty != .f64);
            }
            if (ins.op == .call_direct and std.mem.eql(u8, ins.callee, "label")) saw_string = true;
            if (ins.op == .str_len) {
                saw_string = true;
                saw_length = true;
            }
            if (ins.op == .call_extern and std.mem.eql(u8, ins.callee, "strlen")) saw_length = true;
        }
    }
    try std.testing.expect(saw_float);
    try std.testing.expect(saw_integer);
    try std.testing.expect(saw_string);
    try std.testing.expect(saw_length);
}

test "dnir_lower: checked subject call retains semantic facts" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const Sema = @import("sema.zig").Sema;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\read: i64 = (subject: i64)
        \\    subject
        \\main: i64 = (seed: i64)
        \\    42:read()
    ;
    var lex = Lexer.init(src, "application.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&mod);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&mod, &checked, "application.id");

    try std.testing.expectEqual(@as(usize, 1), graph.applications().len);
    const fact = &graph.applications()[0];
    const application = fact.application;
    const relation = graph.applicationRelation(application) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(relation, graph.applicationApplied(application).?);
    try std.testing.expectEqual(relation, graph.applicationTarget(application).?);
    const results = graph.applicationResults(application) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), results.len);
    const value = results[0];
    const expected_subject = graph.applicationSubject(fact.application) orelse return error.TestExpectedEqual;

    const module = try lowerModuleWithGraph(alloc, &mod, &graph);
    defer dnir.deinitModule(alloc, module);
    var found = false;
    var mov_args: usize = 0;
    for (module.functions) |function| {
        var instruction_index: u32 = 0;
        for (function.blocks[0].instrs) |instruction| {
            const current_index = instruction_index;
            instruction_index += 1;
            if (instruction.op == .mov_arg) mov_args += 1;
            // THE MANGLING LAW: `read` in home `application` (the lift file
            // is `application.id`) is realized as `idol_application__read`.
            if (instruction.op != .call_direct or
                !std.mem.eql(u8, instruction.callee, "idol_application__read")) continue;
            found = true;
            try std.testing.expect(std.meta.eql(relation, instruction.relation.?));
            try std.testing.expect(std.meta.eql(relation, instruction.target.?));
            try std.testing.expect(std.meta.eql(application, instruction.application.?));
            try std.testing.expect(std.meta.eql(value, instruction.value.?));
            try std.testing.expect(std.meta.eql(expected_subject, instruction.subject.?));
            try std.testing.expect(std.meta.eql(dnir.Value{ .i64 = 42 }, instruction.lhs));
            try std.testing.expectEqual(current_index, instruction.realization_start.?);
        }
    }
    try std.testing.expect(found);
    try std.testing.expectEqual(@as(usize, 0), mov_args);

    const row = graph.application_rows.items[application];
    const saved = graph.application_facts.items[row];
    graph.application_facts.items[row].applied = .unknown;
    try std.testing.expectError(error.GraphFactsInvalid, lowerModuleWithGraph(alloc, &mod, &graph));
    graph.application_facts.items[row] = saved;
    graph.application_facts.items[row].applied = .none;
    try std.testing.expectError(error.GraphFactsInvalid, lowerModuleWithGraph(alloc, &mod, &graph));
    graph.application_facts.items[row] = saved;
    graph.application_facts.items[row].applied = .{ .one = value };
    try std.testing.expectError(error.GraphFactsInvalid, lowerModuleWithGraph(alloc, &mod, &graph));
    graph.application_facts.items[row] = saved;
    graph.application_facts.items[row].target = .unknown;
    try std.testing.expectError(error.GraphFactsInvalid, lowerModuleWithGraph(alloc, &mod, &graph));
    graph.application_facts.items[row] = saved;
    graph.application_facts.items[row].target = .none;
    try std.testing.expectError(error.GraphFactsInvalid, lowerModuleWithGraph(alloc, &mod, &graph));
    graph.application_facts.items[row] = saved;
    graph.application_facts.items[row].target = .{ .one = value };
    try std.testing.expectError(error.GraphFactsInvalid, lowerModuleWithGraph(alloc, &mod, &graph));
    graph.application_facts.items[row] = saved;

    const alternate = graph.applicationCaller(application) orelse return error.TestExpectedEqual;
    try std.testing.expect(alternate != relation);
    graph.application_facts.items[row].applied = .{ .one = alternate };
    graph.application_facts.items[row].target = .{ .one = alternate };
    const split = try lowerModuleWithGraph(alloc, &mod, &graph);
    defer dnir.deinitModule(alloc, split);
    var saw_split = false;
    for (split.functions) |function| {
        for (function.blocks[0].instrs) |instruction| {
            if (instruction.application != application) continue;
            try std.testing.expectEqual(relation, instruction.relation.?);
            try std.testing.expectEqual(alternate, instruction.target.?);
            saw_split = true;
        }
    }
    try std.testing.expect(saw_split);
    graph.application_facts.items[row] = saved;
}

test "dnir_lower: applications share relation without sharing occurrence id" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const Sema = @import("sema.zig").Sema;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\read: i64 = (subject: i64)
        \\    subject
        \\main: i64 = (seed: i64)
        \\    41:read()
        \\    42:read()
    ;
    var lex = Lexer.init(src, "application-occurrence.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&mod);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&mod, &checked, "application-occurrence.id");

    const module = try lowerModuleWithGraph(alloc, &mod, &graph);
    defer dnir.deinitModule(alloc, module);
    var relations: [2]semantic_graph.id = undefined;
    var applications: [2]semantic_graph.id = undefined;
    var values: [2]semantic_graph.id = undefined;
    var subjects: [2]semantic_graph.id = undefined;
    var count: usize = 0;
    for (module.functions) |function| {
        for (function.blocks[0].instrs) |instruction| {
            if (instruction.application == null) continue;
            if (count >= applications.len) return error.TestExpectedEqual;
            relations[count] = instruction.relation.?;
            applications[count] = instruction.application.?;
            values[count] = instruction.value.?;
            subjects[count] = instruction.subject.?;
            count += 1;
        }
    }
    try std.testing.expectEqual(applications.len, count);
    try std.testing.expect(std.meta.eql(relations[0], relations[1]));
    try std.testing.expect(!std.meta.eql(applications[0], applications[1]));
    try std.testing.expect(!std.meta.eql(values[0], values[1]));
    try std.testing.expect(!std.meta.eql(subjects[0], subjects[1]));
}

test "dnir_lower: checked ordinary calls consume graph facts" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const Sema = @import("sema.zig").Sema;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\observe: i64 = (value: i64)
        \\    value
        \\main: i64 = (seed: i64)
        \\    observe(41)
        \\    observe(42)
    ;
    var lexer = Lexer.init(source, "ordinary-application.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "ordinary-application.id");

    const module = try lowerModuleWithGraph(alloc, &ast_module, &graph);
    defer dnir.deinitModule(alloc, module);
    var relation: ?semantic_graph.id = null;
    var applications: [2]semantic_graph.id = undefined;
    var values: [2]semantic_graph.id = undefined;
    var count: usize = 0;
    var mov_args: usize = 0;
    for (module.functions) |function| {
        if (!std.mem.eql(u8, function.name, "main")) continue;
        var instruction_index: u32 = 0;
        for (function.blocks[0].instrs) |instruction| {
            const current_index = instruction_index;
            instruction_index += 1;
            if (instruction.op == .mov_arg) mov_args += 1;
            if (instruction.application == null) continue;
            if (count >= applications.len) return error.TestExpectedEqual;
            if (relation) |first| {
                try std.testing.expect(std.meta.eql(first, instruction.relation.?));
            } else {
                relation = instruction.relation.?;
            }
            applications[count] = instruction.application.?;
            values[count] = instruction.value.?;
            // SLOT-ROLE-ONE: `observe(41)` promotes `41` to the subject slot.
            try std.testing.expect(instruction.subject != null);
            try std.testing.expectEqual(types.ResolvedType.i64, instruction.ty);
            const expected: i64 = if (count == 0) 41 else 42;
            try std.testing.expect(std.meta.eql(dnir.Value{ .i64 = expected }, instruction.lhs));
            try std.testing.expectEqual(current_index, instruction.realization_start.?);
            count += 1;
        }
    }
    try std.testing.expectEqual(applications.len, count);
    try std.testing.expect(!std.meta.eql(applications[0], applications[1]));
    try std.testing.expect(!std.meta.eql(values[0], values[1]));
    try std.testing.expectEqual(@as(usize, 0), mov_args);
}

test "dnir_lower: graph pack adjusts one result into several bindings" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const Sema = @import("sema.zig").Sema;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\one: i64 = (value: i64)
        \\    value
        \\main: i64 = ()
        \\    a, b = one(7)
        \\    a * 10 + b
    ;
    var lexer = Lexer.init(source, "one-many-pack.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "one-many-pack.id");

    const application = graph.applications()[0];
    const adjustment = graph.packAdjustment(application.application) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), graph.packMembers(adjustment.source_pack).?.len);
    try std.testing.expectEqual(@as(usize, 2), graph.packMembers(adjustment.target_pack).?.len);

    const module = try lowerModuleWithGraph(alloc, &ast_module, &graph);
    defer dnir.deinitModule(alloc, module);
    var calls: usize = 0;
    var stores: usize = 0;
    var saw_nil_fill = false;
    for (module.functions) |function| {
        if (!std.mem.eql(u8, function.name, "main")) continue;
        for (function.blocks[0].instrs) |instruction| {
            if (instruction.op == .call_direct) calls += 1;
            if (instruction.op == .store_local) {
                stores += 1;
                if (std.meta.eql(dnir.Value{ .i64 = 0 }, instruction.lhs)) saw_nil_fill = true;
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 1), calls);
    try std.testing.expect(stores >= 2);
    try std.testing.expect(saw_nil_fill);

    // Negative control: the same source shape is not authority. Removing the
    // graph adjustment must refuse instead of reconstructing Lua pack law from
    // target/value counts in DNIR.
    try std.testing.expect(graph.adjustment_rows.remove(application.application));
    try std.testing.expectError(error.GraphFactsInvalid, lowerModuleWithGraph(alloc, &ast_module, &graph));
}

test "dnir_lower: graph pack adjusts one result into several local declarations" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const Sema = @import("sema.zig").Sema;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\one: i64 = (value: i64)
        \\    value
        \\main: i64 = ()
        \\    local a, b = one(7)
        \\    a * 10 + b
    ;
    var lexer = Lexer.init(source, "one-many-local-pack.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "one-many-local-pack.id");

    const application = graph.applications()[0];
    const adjustment = graph.packAdjustment(application.application) orelse return error.TestExpectedEqual;
    const targets = graph.packMembers(adjustment.target_pack) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 2), targets.len);
    for (targets) |target| try std.testing.expectEqual(semantic_graph.NodeKind.local, graph.get(target).?.kind);

    const module = try lowerModuleWithGraph(alloc, &ast_module, &graph);
    defer dnir.deinitModule(alloc, module);
    var calls: usize = 0;
    var stores: usize = 0;
    var saw_nil_fill = false;
    for (module.functions) |function| {
        if (!std.mem.eql(u8, function.name, "main")) continue;
        for (function.blocks[0].instrs) |instruction| {
            if (instruction.op == .call_direct) calls += 1;
            if (instruction.op == .store_local) {
                stores += 1;
                if (std.meta.eql(dnir.Value{ .i64 = 0 }, instruction.lhs)) saw_nil_fill = true;
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 1), calls);
    try std.testing.expect(stores >= 2);
    try std.testing.expect(saw_nil_fill);
}

test "dnir_lower: checked multi-operand call retains ABI staging" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const Sema = @import("sema.zig").Sema;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\add: i64 = (left: i64, right: i64)
        \\    left + right
        \\main: i64 = (seed: i64)
        \\    add(20, 22)
    ;
    var lexer = Lexer.init(source, "multi-application.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "multi-application.id");

    const module = try lowerModuleWithGraph(alloc, &ast_module, &graph);
    defer dnir.deinitModule(alloc, module);
    var mov_args: usize = 0;
    var found = false;
    for (module.functions) |function| {
        if (!std.mem.eql(u8, function.name, "main")) continue;
        var instruction_index: u32 = 0;
        for (function.blocks[0].instrs) |instruction| {
            if (instruction.op == .mov_arg) mov_args += 1;
            if (instruction.application != null) {
                found = true;
                try std.testing.expect(instruction.relation != null);
                try std.testing.expect(instruction.value != null);
                // SLOT-ROLE-ONE: `add(20, 22)` promotes `20` to the subject slot.
                try std.testing.expect(instruction.subject != null);
                try std.testing.expectEqual(dnir.Value.void, instruction.lhs);
                try std.testing.expect(instruction.realization_start.? < instruction_index);
            }
            instruction_index += 1;
        }
    }
    try std.testing.expect(found);
    try std.testing.expectEqual(@as(usize, 2), mov_args);
}

test "dnir_lower: checked scalar ABI boundaries retain staging" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const Sema = @import("sema.zig").Sema;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\choose: f64 = (value: i64)
        \\    1.5
        \\count: i64 = (value: f64)
        \\    1
        \\main: f64 = (seed: i64)
        \\    count(2.5)
        \\    choose(1)
    ;
    var lexer = Lexer.init(source, "scalar-boundary.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "scalar-boundary.id");

    const module = try lowerModuleWithGraph(alloc, &ast_module, &graph);
    defer dnir.deinitModule(alloc, module);
    var gp_moves: usize = 0;
    var fp_moves: usize = 0;
    var calls: usize = 0;
    for (module.functions) |function| {
        if (!std.mem.eql(u8, function.name, "main")) continue;
        var instruction_index: u32 = 0;
        for (function.blocks[0].instrs) |instruction| {
            if (instruction.op == .mov_arg) gp_moves += 1;
            if (instruction.op == .fp_mov_arg) fp_moves += 1;
            if (instruction.application != null) {
                calls += 1;
                try std.testing.expectEqual(dnir.Value.void, instruction.lhs);
                try std.testing.expect(instruction.realization_start.? < instruction_index);
            }
            instruction_index += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), calls);
    try std.testing.expectEqual(@as(usize, 1), gp_moves);
    try std.testing.expectEqual(@as(usize, 1), fp_moves);
}

test "dnir_lower: checked f64 call derives ABI staging from descriptors" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const Sema = @import("sema.zig").Sema;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\add: f64 = (left: f64, right: f64)
        \\    left + right
        \\main: f64 = ()
        \\    add(1.5, 2.5)
    ;
    var lexer = Lexer.init(source, "ordinary-f64-application.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "ordinary-f64-application.id");

    const module = try lowerModuleWithGraph(alloc, &ast_module, &graph);
    defer dnir.deinitModule(alloc, module);
    var fp_moves: usize = 0;
    var call_index: ?u32 = null;
    for (module.functions) |function| {
        var instruction_index: u32 = 0;
        for (function.blocks[0].instrs) |instruction| {
            if (instruction.op == .fp_mov_arg) fp_moves += 1;
            if (instruction.application != null) {
                call_index = instruction_index;
                try std.testing.expectEqual(types.ResolvedType.f64, instruction.ty);
                // SLOT-ROLE-ONE: `add(1.5, 2.5)` promotes `1.5` to the subject slot.
                try std.testing.expect(instruction.subject != null);
                try std.testing.expect(instruction.realization_start.? < instruction_index);
            }
            instruction_index += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), fp_moves);
    try std.testing.expect(call_index != null);
}

test "dnir_lower: bool result descriptor prevents integer interpolation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\ready(): bool
        \\    true
        \\render(): str
        \\    "ready=" .. ready()
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "bool_result_query.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();

    try std.testing.expectError(error.UnsupportedConstruct, lowerModule(alloc, &mod));
}

test "dnir_lower: graph orders callees before callers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\distance2(value: i64): i64
        \\    value
        \\main(): i64
        \\    distance2(3)
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "graph-order.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var checked = @import("sema.zig").Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&mod);
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCheckedCalls(&mod, &checked, "graph-order.id");
    const m = try lowerModuleWithGraph(alloc, &mod, &g);
    defer dnir.deinitModule(alloc, m);
    var idx_distance: ?usize = null;
    var idx_main: ?usize = null;
    for (m.functions, 0..) |f, i| {
        // `graph-order.id` is home `graph-order`, and a symbol is an
        // identifier, so the hyphen folds: `idol_graph_order__distance2`.
        // `main` is the process entry and keeps its name.
        if (std.mem.eql(u8, f.name, "idol_graph_order__distance2")) idx_distance = i;
        if (std.mem.eql(u8, f.name, "main")) idx_main = i;
        try std.testing.expect(f.id != null);
    }
    try std.testing.expect(idx_distance != null and idx_main != null);
    try std.testing.expect(idx_distance.? < idx_main.?);
}

test "dnir_lower: checked ids use graph coordinates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\observe: i64 = (value: i64)
        \\    value
        \\main: i64 = (seed: i64)
        \\    observe(42)
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "hash-free.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var checked = @import("sema.zig").Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&mod);
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCheckedCalls(&mod, &checked, "hash-free.id");

    const m = try lowerModuleWithGraph(alloc, &mod, &g);
    defer dnir.deinitModule(alloc, m);
    var identified = false;
    for (m.functions) |function| {
        for (function.blocks) |block| {
            for (block.instrs) |instruction| {
                if (instruction.application == null) continue;
                identified = true;
                try std.testing.expect(g.get(instruction.relation.?) != null);
                try std.testing.expect(g.get(instruction.application.?) != null);
                try std.testing.expect(g.get(instruction.value.?) != null);
            }
        }
    }
    try std.testing.expect(identified);
}

test "dnir_lower: graphless convenience returns no orphan handles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\observe: i64 = (value: i64)
        \\    value
        \\main: i64 = (seed: i64)
        \\    observe(42)
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "graphless.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const module = try lowerModule(alloc, &mod);

    try std.testing.expect(module.graph == null);
    for (module.functions) |function| {
        try std.testing.expect(function.id == null);
        for (function.blocks) |block| {
            for (block.instrs) |instruction| {
                try std.testing.expect(instruction.relation == null);
                try std.testing.expect(instruction.application == null);
                try std.testing.expect(instruction.value == null);
                try std.testing.expect(instruction.subject == null);
                try std.testing.expect(instruction.realization_start == null);
            }
        }
    }
}

test "dnir_lower: record-return tail and call assign emit init_record" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: i64, y: i64 }
        \\make(): Point
        \\    { x = 1, y = 2 }
        \\end
        \\main(): i64
        \\    local p = make()
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "rec.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_init_record = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.op == .init_record and std.mem.eql(u8, ins.record, "Point")) {
                    saw_init_record = true;
                }
            }
        }
    }
    try std.testing.expect(saw_init_record);
}

test "dnir_lower: f64 record-return tail lowers ret_record" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\make(): Point
        \\    { x = 1.0, y = 2.0 }
        \\end
        \\main(): i64
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "f64ret.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    try std.testing.expect(m.functions.len == 2);
    var saw_ret_record = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "make")) continue;
        try std.testing.expect(f.ret_record != null);
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.op == .ret_record and std.mem.eql(u8, ins.record, "Point")) saw_ret_record = true;
            }
        }
    }
    try std.testing.expect(saw_ret_record);
}

test "dnir_lower: f64 kernel inline table emits init_record" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    distance2({ x = 3.0, y = 4.0 })
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "f64tbl.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_init = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.op == .init_record and std.mem.eql(u8, ins.record, "Point")) saw_init = true;
            }
        }
    }
    try std.testing.expect(saw_init);
}

test "dnir_lower: discard call_stmt omits call result temp" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\side(): i64
        \\    0
        \\end
        \\main(): i64
        \\    side();
        \\    1
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "discard.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_discard_call = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.op == .call_direct and std.mem.eql(u8, ins.callee, "side") and ins.result == null) {
                    saw_discard_call = true;
                }
            }
        }
    }
    try std.testing.expect(saw_discard_call);
}

test "dnir_lower: trailing compound assign returns assigned local" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\double(x: i64): i64
        \\    x *= 2
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "trail.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    const f = m.functions[0];
    var ret_count: usize = 0;
    var ret_from_param = false;
    for (f.blocks) |b| {
        for (b.instrs) |ins| {
            if (ins.op != .ret) continue;
            ret_count += 1;
            if (ins.lhs == .local and ins.lhs.local == 0) ret_from_param = true;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), ret_count);
    try std.testing.expect(ret_from_param);
}

test "dnir_lower: dot static member exports module.method" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\math.add = (a: i64, b: i64): i64
        \\    a + b
        \\end
        \\main(): i64
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "static.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    try std.testing.expectEqual(@as(usize, 2), m.functions.len);
    var saw = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "math.add")) continue;
        saw = true;
        try std.testing.expectEqual(@as(usize, 2), f.params.len);
        try std.testing.expect(f.ret == .i64);
    }
    try std.testing.expect(saw);
}

test "dnir_lower: colon method compound field assign exports Type.method" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = "Vec: @{ x: i32 }\nVec:xplus = (amt): i32\n    self.x += amt\nend";
    var lex = @import("lexer.zig").Lexer.init(src, "method.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var sema = @import("sema.zig").Sema.init(alloc);
    try sema.check_module(&mod);
    try std.testing.expectEqual(@as(u32, 0), sema.errors);
    const m = try lowerModule(alloc, &mod);
    try std.testing.expectEqual(@as(usize, 1), m.functions.len);
    try std.testing.expectEqualStrings("Vec.xplus", m.functions[0].name);
    try std.testing.expect(m.functions[0].ret == .i32);
}

test "dnir_lower: trailing compound field assign returns updated field slot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Vec: @{ x: i32 }
        \\bump = (v: Vec, amt: i32): i32
        \\    v.x += amt
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "field.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    const f = m.functions[0];
    // "The updated field slot" is whatever slot the compound assignment STORED
    // into — under the exploded-record model a one-field record parameter owns
    // slot 0, so the old proxy for it (`local != 0 and local != 1`) named a slot
    // that cannot exist here and failed on a correct lowering. Compare the ret
    // against the store instead; that is the property, and it cannot pass by
    // accident.
    var ret_count: usize = 0;
    var ret_slot: ?u32 = null;
    var store_slot: ?u32 = null;
    for (f.blocks) |b| {
        for (b.instrs) |ins| {
            if (ins.op == .store_local) store_slot = ins.result;
            if (ins.op != .ret) continue;
            ret_count += 1;
            if (ins.lhs == .local) ret_slot = ins.lhs.local;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), ret_count);
    try std.testing.expect(store_slot != null);
    try std.testing.expectEqual(store_slot.?, ret_slot orelse return error.RetIsNotALocal);
}

test "dnir_lower: if binding assigns before branch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\get(): i64
        \\    5
        \\end
        \\main(): i64
        \\    if v = get() v > 0
        \\        v
        \\    else
        \\        0
        \\    end
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "ifbind.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var saw_get_call = false;
    var saw_v_store = false;
    var br_after_store = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks) |b| {
            var i: usize = 0;
            while (i < b.instrs.len) : (i += 1) {
                const ins = b.instrs[i];
                if (ins.op == .call_direct and std.mem.eql(u8, ins.callee, "get")) saw_get_call = true;
                if (ins.op == .store_local and ins.result != null) saw_v_store = true;
                if (saw_v_store and ins.op == .br and ins.branch_condition != .unconditional) br_after_store = true;
            }
        }
    }
    try std.testing.expect(saw_get_call);
    try std.testing.expect(saw_v_store);
    try std.testing.expect(br_after_store);
}

test "dnir_lower: ret_record carries every field in DESCRIPTOR order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // The literal is written OUT of declaration order on purpose. The consumer
    // reads field i from ABI slot i (or buffer offset i*8), so the descriptor
    // is the only ordering that agrees with it; walking the literal's own order
    // shipped `c`'s value in the slot the caller reads as `a`.
    const src =
        \\rec: @{ a: i64, b: i64, c: i64, d: i64, e: i64 }
        \\mk(): rec
        \\    return { c = 30, e = 50, a = 10, d = 40, b = 20 }
        \\end
        \\main(): i64
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "retorder.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);

    var saw = false;
    for (m.functions) |f| {
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.op != .ret_record) continue;
                saw = true;
                // One entry per DECLARED field, not per written field.
                try std.testing.expectEqual(@as(usize, 5), ins.vals.len);
                const want = [_]i64{ 10, 20, 30, 40, 50 };
                for (ins.vals, want) |v, w| {
                    try std.testing.expectEqual(w, v.i64);
                }
            }
        }
    }
    try std.testing.expect(saw);
}



test "dnir_lower: host taint records method world and subject-binding sites" {
    var diagnostic: Diagnostic = .{};
    defer diagnostic.deinit(std.testing.allocator);
    noteHostTaintDiagnostic(
        &diagnostic,
        std.testing.allocator,
        true,
        .ast_name,
        "global_init.subject_binding",
        null,
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        diagnostic.taint.count(.lower, .ast_name, .host_tainted),
    );
}

test "dnir_lower: formatMissingApplicationFact names application missing consumer producer" {
    var diagnostic: Diagnostic = .{};
    diagnostic.application = 382;
    diagnostic.relation = "write";
    diagnostic.record(@src(), "result-descriptor");
    var buf: [256]u8 = undefined;
    const msg = diagnostic.formatMissingApplicationFact(&buf);
    try std.testing.expectEqualStrings(
        "application 382 relation: write missing: result-descriptor consumer: dnir.lower producer: graph",
        msg,
    );
}

test "dnir_lower: a nine-field record return is eligible, a nine-field param is not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const wide = "big: @{ a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64, i: i64 }\n";
    const lit = "{ a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7, h = 8, i = 9 }";

    // Nine fields RETURNED: the x8 indirect-result convention covers it.
    {
        const src = wide ++ "mk(): big\n    return " ++ lit ++ "\nend\nmain(): i64\n    0\nend\n";
        var lex = @import("lexer.zig").Lexer.init(src, "wideret.id");
        var parser = @import("parser.zig").Parser.init(&lex, alloc);
        parser.idol_mode = true;
        const mod = try parser.parse_module();
        const m = try lowerModule(alloc, &mod);
        try std.testing.expectEqual(@as(usize, 2), m.functions.len);
    }

    // Nine fields PASSED: still one field per argument register, and there is
    // no ninth. Refusing beats exploding past x7 into caller garbage.
    {
        const src = wide ++ "take(v: big): i64\n    return v.a\nend\nmain(): i64\n    0\nend\n";
        var lex = @import("lexer.zig").Lexer.init(src, "wideparam.id");
        var parser = @import("parser.zig").Parser.init(&lex, alloc);
        parser.idol_mode = true;
        const mod = try parser.parse_module();
        try std.testing.expectError(error.UnsupportedConstruct, lowerModule(alloc, &mod));
    }
}
