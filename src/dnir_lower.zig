//! AST → DNIR lowering for typed native programs (no lua_Value, no C-string codegen).
//!
//! Produces `duo_native_ir.Module` for direct machine backends. C emission is bootstrap-only.
//!
//! Entry points: Duo modules export functions at file scope (file-as-M). There is no
//! Python/Lua-style mandatory `main()` or special entry typing — any eligible function
//! lowers the same way; linker entry is `@export` / CLI target, not a magic name.
const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");
const dnir = @import("duo_native_ir.zig");
const native_req_support = @import("native_req_support.zig");
const dnir_hardware = @import("dnir_hardware.zig");
const semantic_graph = @import("semantic_graph.zig");
const tail_result_demand = @import("tail_result_demand.zig");
const RT = types.ResolvedType;

pub const Error = error{
    UnsupportedConstruct,
    OutOfMemory,
};

/// Which of the ~60 bail sites fired, so DNB001 can name a construct.
///
/// DNB001 was one undifferentiated bucket: 60 of 72 native bails across
/// examples/ reported "outside the direct backend subset" and nothing more,
/// which makes the worklist unorderable — you cannot tell whether supporting
/// the next construct buys 30 programs or 1. The ambient mechanism was already
/// wired (`DUO_DNIR_TRACE=1` dumps Zig's error return trace at
/// src/main.zig:3186) and yields "(empty stack trace)" even in Debug, because
/// the error is caught and re-raised before reaching the reporter.
///
/// So the site records itself on the way out. `@src()` makes this mechanical
/// and unforgeable — no hand-authored tag can drift from the code it labels,
/// and a site added later is instrumented by construction if it goes through
/// `bail`. The pair is a plain global rather than lowering state because it is
/// diagnostic-only and read exactly once, immediately after the failing call,
/// on a path that is already single-threaded per compilation.
pub var bail_site: std.builtin.SourceLocation = .{
    .module = "",
    .file = "",
    .fn_name = "",
    .line = 0,
    .column = 0,
};

fn bail(src: std.builtin.SourceLocation) Error {
    bail_site = src;
    bail_note_len = 0;
    return error.UnsupportedConstruct;
}

/// What the site was looking at, when the site alone is not enough.
///
/// A source location says WHERE lowering stopped, never WHAT is missing — the
/// `lowerBinop` site read as "no bitwise ops" when both blocked programs
/// actually used `..`. For a site whose whole content is "this name did not
/// resolve", the name IS the finding.
var bail_note_buf: [96]u8 = undefined;
var bail_note_len: usize = 0;

pub fn bailNote() ?[]const u8 {
    if (bail_note_len == 0) return null;
    return bail_note_buf[0..bail_note_len];
}

fn bailWith(src: std.builtin.SourceLocation, note: []const u8) Error {
    bail_site = src;
    const n = @min(note.len, bail_note_buf.len);
    @memcpy(bail_note_buf[0..n], note[0..n]);
    bail_note_len = n;
    return error.UnsupportedConstruct;
}

const empty_module_consts: std.StringHashMapUnmanaged(i64) = .empty;

/// Collect top-level integer bindings so a function body can fold them.
///
/// `N = 3` and the canonical enum form `Kind = @{ eof = 0, ident = 1 }` are
/// module-level values; nothing registered them as locals, so `Kind.ident`
/// inside a function resolved to a runtime field load and failed with DNB007.
/// Both spellings are compile-time constants and belong as immediates.
fn collectModuleConsts(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
) Error!std.StringHashMapUnmanaged(i64) {
    var map: std.StringHashMapUnmanaged(i64) = .empty;
    errdefer {
        var it = map.iterator();
        while (it.next()) |e| alloc.free(e.key_ptr.*);
        map.deinit(alloc);
    }
    for (mod.body.stmts) |*stmt| {
        var name: ?[]const u8 = null;
        var val: ?*const ast.Expr = null;
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
            else => {},
        }
        const n = name orelse continue;
        const v = val orelse continue;
        if (intLiteralStep(v)) |iv| {
            try map.put(alloc, try alloc.dupe(u8, n), iv);
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
            const fv = intLiteralStep(nf.val) orelse continue;
            const key = try std.fmt.allocPrint(alloc, "{s}.{s}", .{ n, nf.key });
            try map.put(alloc, key, fv);
        }
    }
    return map;
}

pub fn lowerModule(alloc: std.mem.Allocator, mod: *const ast.Module) Error!dnir.Module {
    bail_site.line = 0;
    var req = try native_req_support.collectFromModule(alloc, mod);
    defer req.deinit(alloc);

    var module_consts = try collectModuleConsts(alloc, mod);
    defer {
        var mc_it = module_consts.iterator();
        while (mc_it.next()) |e| alloc.free(e.key_ptr.*);
        module_consts.deinit(alloc);
    }

    var records: std.ArrayList(dnir.RecordDesc) = .empty;
    errdefer {
        for (records.items) |r| {
            alloc.free(r.name);
            for (r.fields) |f| alloc.free(f);
            alloc.free(r.fields);
            alloc.free(r.kinds);
        }
        records.deinit(alloc);
    }
    try collectRecords(alloc, &records, mod);

    var f64_kernels: std.StringHashMapUnmanaged(void) = .empty;
    defer f64_kernels.deinit(alloc);
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        const fd = &stmt.func_decl;
        if (!shouldIncludeFuncDecl(fd) or fd.path.len != 1 or fd.method) continue;
        if (funcFfiName(fd.attributes) != null) continue;
        if (isFloatType(fd.func.ret_type) and functionEligible(fd, records.items)) {
            if (f64AbiParamSlots(fd, records.items)) |slots| {
                if (slots > 0) try f64_kernels.put(alloc, fd.path[0], {});
            }
        }
    }

    var functions: std.ArrayList(dnir.Function) = .empty;
    errdefer functions.deinit(alloc);
    var externs: std.ArrayList(dnir.Extern) = .empty;
    errdefer externs.deinit(alloc);
    var func_record_returns: std.StringHashMapUnmanaged([]const u8) = .empty;
    defer func_record_returns.deinit(alloc);

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
        if (!functionEligible(fd, records.items)) continue;
        const rec = findRecordName(records.items, fd.func.ret_type) orelse continue;
        const export_name = try funcExportName(alloc, fd);
        if (func_record_returns.contains(export_name)) continue;
        try func_record_returns.put(alloc, try alloc.dupe(u8, export_name), try alloc.dupe(u8, rec.name));
    }

    var skipped: ?[]const u8 = null;
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        const fd = &stmt.func_decl;
        if (!shouldIncludeFuncDecl(fd)) continue;
        // Name the function that was refused. "the counts do not match" is a
        // true statement about a module and a useless one about a fix: every
        // one of these bails means exactly one declaration was ineligible, and
        // which one is the entire finding.
        if (!functionEligible(fd, records.items)) {
            if (skipped == null) skipped = if (fd.path.len > 0) fd.path[0] else "?";
            continue;
        }
        const f = try lowerFunction(alloc, fd, records.items, &req, &externs, &func_record_returns, &f64_kernels, &module_consts);
        try functions.append(alloc, f);
    }
    if (functions.items.len == 0) return bail(@src());
    if (functions.items.len != countModuleFunctions(mod))
        return bailWith(@src(), skipped orelse "?");

    const result = dnir.Module{
        .functions = try functions.toOwnedSlice(alloc),
        .records = try records.toOwnedSlice(alloc),
        .externs = try externs.toOwnedSlice(alloc),
    };
    return .{
        .functions = result.functions,
        .records = result.records,
        .externs = result.externs,
        .hardware_tier = dnir.moduleHardwareTier(result),
    };
}

/// Pass 16 hook: optional semantic graph for provenance/transform ordering.
/// Reorders functions callees-before-callers and attaches graph stable IDs.
pub fn lowerModuleWithGraph(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    graph: ?*const semantic_graph.SemanticGraph,
) Error!dnir.Module {
    var m = try lowerModule(alloc, mod);
    if (graph) |g| {
        try applyGraphToModule(alloc, g, &m);
    }
    return m;
}

fn applyGraphToModule(
    alloc: std.mem.Allocator,
    graph: *const semantic_graph.SemanticGraph,
    m: *dnir.Module,
) Error!void {
    var names: std.ArrayListUnmanaged([]const u8) = .empty;
    defer names.deinit(alloc);
    for (m.functions) |f| try names.append(alloc, f.name);

    const order = try graph.moduleFunctionEmitOrder(alloc, names.items);
    defer alloc.free(order);

    try reorderFunctions(alloc, m, order);

    const funcs: []dnir.Function = @constCast(m.functions);
    for (funcs) |*f| {
        const id = graph.findByName(f.name) orelse continue;
        const node = graph.get(id) orelse continue;
        if (node.stable_id) |sid| f.graph_stable_id = sid.hash;
    }

    const recs: []dnir.RecordDesc = @constCast(m.records);
    for (recs) |*rec| {
        if (graph.findTableShape(rec.name)) |shape| {
            rec.shape_id = shape.shape_id;
            if (shape.stable_id) |sid| rec.graph_stable_id = sid.hash;
        }
    }
}

fn reorderFunctions(alloc: std.mem.Allocator, m: *dnir.Module, order: []const []const u8) Error!void {
    if (m.functions.len <= 1 or order.len != m.functions.len) return;

    var rank: std.StringHashMapUnmanaged(usize) = .empty;
    defer rank.deinit(alloc);
    for (order, 0..) |name, i| {
        try rank.put(alloc, name, i);
    }

    const funcs: []dnir.Function = @constCast(m.functions);
    const Func = dnir.Function;
    std.mem.sort(Func, funcs, rank, struct {
        fn lessThan(ctx: std.StringHashMapUnmanaged(usize), a: Func, b: Func) bool {
            const ra = ctx.get(a.name) orelse return false;
            const rb = ctx.get(b.name) orelse return true;
            return ra < rb;
        }
    }.lessThan);
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

/// Export symbol for DNIR/backends — `add` or qualified `Vec.xplus`.
fn funcExportName(alloc: std.mem.Allocator, fd: *const ast.FuncDecl) Error![]const u8 {
    if (fd.path.len == 1) return try alloc.dupe(u8, fd.path[0]);
    return std.fmt.allocPrint(alloc, "{s}.{s}", .{ fd.path[0], fd.path[fd.path.len - 1] });
}

fn shouldIncludeFuncDecl(fd: *const ast.FuncDecl) bool {
    if (fd.is_local) return false;
    if (funcFfiName(fd.attributes) != null) return false;
    if (fd.path.len == 1 and !fd.method) return true;
    if (fd.method and fd.path.len >= 2) return true;
    // Pass 23 §3 — math.add = (a, b) … static module members (dot, not colon).
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

fn functionEligible(fd: *const ast.FuncDecl, recs: []const dnir.RecordDesc) bool {
    if (fd.func.vararg or fd.func.vararg_name != null) return false;
    if (findRecordName(recs, fd.func.ret_type)) |rec| {
        if (rec.fields.len == 0 or rec.fields.len > 8) return false;
        for (fd.func.params) |p| {
            if (isF64Record(recs, p.typ)) |_| continue;
            if (findRecordName(recs, p.typ)) |_| continue;
            if (!isIntType(p.typ) and !isStrType(p.typ) and !typeIsPtr(p.typ)) return false;
        }
        return true;
    }
    if (isFloatType(fd.func.ret_type)) {
        const slots = f64AbiParamSlots(fd, recs) orelse return false;
        return slots <= 8;
    }
    if (!isIntType(fd.func.ret_type) and !isStrType(fd.func.ret_type) and
        !isVoidType(fd.func.ret_type)) return false;
    // An all-f64 parameter list with an INT return was refused, while the same
    // parameters with an f64 return were accepted by the branch above. AAPCS
    // puts floats in v0..v7 and integers in x0..x7 — separate register files —
    // so the return class and the parameter classes are independent, and there
    // was never a reason to couple them. `mandel(cx: f64, cy: f64): i64` is the
    // shape: a float kernel that answers with a count.
    if (f64AbiParamSlots(fd, recs)) |slots| {
        if (slots > 0) return slots <= 8;
    }
    if (fd.func.params.len > 8) return false;
    for (fd.func.params) |p| {
        if (findRecordName(recs, p.typ)) |_| continue;
        // `ptr` rides x0..x7 like an i64 — it is the base address of a
        // memory-backed positional table (SH-04).
        if (!isIntType(p.typ) and !isStrType(p.typ) and !typeIsPtr(p.typ)) return false;
    }
    return true;
}

fn collectRecords(alloc: std.mem.Allocator, out: *std.ArrayList(dnir.RecordDesc), mod: *const ast.Module) Error!void {
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .alias_def) continue;
        const ad = &stmt.alias_def;
        if (ad.type_params != null) continue;
        const target = ad.target orelse continue;
        const rec = switch (target) {
            .record => |r| r,
            else => continue,
        };
        if (rec.fields.len == 0 or rec.fields.len > 8) continue;
        var names: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer names.deinit(alloc);
        var kinds: std.ArrayListUnmanaged(dnir.FieldKind) = .empty;
        errdefer kinds.deinit(alloc);
        var ok = true;
        for (rec.fields) |field| {
            const kind: dnir.FieldKind = if (isStrType(field.typ))
                .str
            else if (isIntType(field.typ))
                .i64
            else if (isFloatType(field.typ))
                .f64
            else {
                ok = false;
                break;
            };
            try names.append(alloc, try alloc.dupe(u8, field.name));
            try kinds.append(alloc, kind);
        }
        if (!ok) continue;
        try out.append(alloc, .{
            .name = try alloc.dupe(u8, ad.name),
            .fields = try names.toOwnedSlice(alloc),
            .kinds = try kinds.toOwnedSlice(alloc),
        });
    }
}

fn findRecordName(recs: []const dnir.RecordDesc, t: ast.TypeExpr) ?dnir.RecordDesc {
    if (t != .named) return null;
    for (recs) |r| {
        if (std.mem.eql(u8, r.name, t.named)) return r;
    }
    return null;
}

pub const LowerCtx = struct {
    alloc: std.mem.Allocator,
    records: []const dnir.RecordDesc,
    req: *const native_req_support.Context,
    externs: *std.ArrayList(dnir.Extern),
    func_record_returns: *std.StringHashMapUnmanaged([]const u8),
    f64_kernels: *const std.StringHashMapUnmanaged(void),
    /// When set, tail/table returns lower to `ret_record` for this record name.
    ret_record: ?[]const u8 = null,
    /// Local slots that hold f64 values inside integer kernels.
    f64_slots: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Local slots holding `str` (a `const char*`), so `#s` can lower to strlen.
    str_slots: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Slots holding the base address of a memory-backed positional table —
    /// `ptr` parameters, and locals materialized by `materializeTableSlots`.
    /// `t[i]` on one of these is a scaled 8-byte load, not a select-chain.
    ptr_slots: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Static element count of a positional table, keyed by its `.len` slot, so
    /// `t[i]` with a non-constant `i` knows how many slots to select over.
    table_lens: std.AutoHashMapUnmanaged(u32, i64) = .empty,
    /// Module-level integer constants, keyed `Name` or `Name.field`. Populated
    /// from top-level `N = <int>` and `N = @{ f = <int>, ... }` bindings, which
    /// are otherwise invisible inside a function body.
    module_consts: *const std.StringHashMapUnmanaged(i64) = &empty_module_consts,
    /// Names bound to compile-time-known i64 literals (for numeric for step, etc.).
    const_ints: std.StringHashMapUnmanaged(i64) = .empty,
    next_temp: u32 = 0,
    locals: std.StringHashMapUnmanaged(u32) = .empty,
    instrs: std.ArrayList(dnir.Instr) = .empty,

    pub fn deinit(self: *LowerCtx) void {
        var it = self.locals.iterator();
        while (it.next()) |e| self.alloc.free(e.key_ptr.*);
        self.locals.deinit(self.alloc);
        self.f64_slots.deinit(self.alloc);
        self.str_slots.deinit(self.alloc);
        self.ptr_slots.deinit(self.alloc);
        self.table_lens.deinit(self.alloc);
        var ci = self.const_ints.iterator();
        while (ci.next()) |e| self.alloc.free(e.key_ptr.*);
        self.const_ints.deinit(self.alloc);
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
    for (instrs) |*ins| {
        if (ins.callee.len > 0) ins.callee = try alloc.dupe(u8, ins.callee);
        if (ins.req_alias.len > 0) ins.req_alias = try alloc.dupe(u8, ins.req_alias);
        if (ins.field.len > 0) ins.field = try alloc.dupe(u8, ins.field);
        if (ins.record.len > 0) ins.record = try alloc.dupe(u8, ins.record);
    }
}

fn lowerFunction(
    alloc: std.mem.Allocator,
    fd: *const ast.FuncDecl,
    records: []const dnir.RecordDesc,
    req: *const native_req_support.Context,
    externs: *std.ArrayList(dnir.Extern),
    func_record_returns: *std.StringHashMapUnmanaged([]const u8),
    f64_kernels: *const std.StringHashMapUnmanaged(void),
    module_consts: *const std.StringHashMapUnmanaged(i64),
) Error!dnir.Function {
    var ctx: LowerCtx = .{
        .alloc = alloc,
        .records = records,
        .req = req,
        .externs = externs,
        .func_record_returns = func_record_returns,
        .f64_kernels = f64_kernels,
        .module_consts = module_consts,
        .ret_record = if (findRecordName(records, fd.func.ret_type)) |r| r.name else null,
    };
    defer ctx.deinit();

    // A record parameter arrives as its exploded fields in consecutive argument
    // registers — the same shape records already have as locals — so it consumes
    // one slot per field and shifts the slots of every later parameter.
    var param_slot_cursor: u32 = 0;
    for (fd.func.params) |par| {
        if (findRecordName(records, par.typ)) |rec| {
            var all_scalar = rec.fields.len > 0;
            for (rec.kinds) |k| {
                if (k == .f64) all_scalar = false;
            }
            if (all_scalar) {
                for (rec.fields) |fname| {
                    const key = try std.fmt.allocPrint(alloc, "{s}.{s}", .{ par.name, fname });
                    try ctx.locals.put(alloc, key, param_slot_cursor);
                    param_slot_cursor += 1;
                }
                continue;
            }
        }
        const owned = try alloc.dupe(u8, par.name);
        try ctx.locals.put(alloc, owned, param_slot_cursor);
        // A `str` parameter is a `const char*`, so `#p` inside the body can use
        // strlen just like a str local.
        if (resolveType(par.typ) == .str) try ctx.str_slots.put(alloc, param_slot_cursor, {});
        // A `ptr` parameter carries the base address of a caller's positional
        // table, so `p[i]` in the body is a scaled load off that register.
        if (typeIsPtr(par.typ)) try ctx.ptr_slots.put(alloc, param_slot_cursor, {});
        param_slot_cursor += 1;
    }
    // Locals and temps share one id space (`freshTemp` allocates both), but the
    // parameter slots above were assigned by index rather than through it. Without
    // advancing the cursor the first temps alias the parameters, and the backend's
    // single slot->register map silently rebinds a parameter to a temp's register.
    ctx.next_temp = param_slot_cursor;

    try lowerBlock(&ctx, &fd.func.body, true);

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
    for (fd.func.params) |par| {
        const rec_name = if (findRecordName(records, par.typ)) |r| try alloc.dupe(u8, r.name) else null;
        try params.append(alloc, .{
            .name = try alloc.dupe(u8, par.name),
            .ty = resolveType(par.typ),
            .record = rec_name,
        });
    }

    const blocks = try alloc.alloc(dnir.Block, 1);
    const owned_instrs = try ctx.instrs.toOwnedSlice(alloc);
    try internInstrStrings(alloc, owned_instrs);
    blocks[0] = .{ .instrs = owned_instrs };

    const ret_rec = findRecordName(records, fd.func.ret_type);
    const ret_record_name = if (ret_rec) |r| try alloc.dupe(u8, r.name) else null;
    const export_name = try funcExportName(alloc, fd);
    if (ret_record_name) |rn| {
        try func_record_returns.put(alloc, try alloc.dupe(u8, export_name), rn);
    }

    return .{
        .name = export_name,
        .ret = resolveType(fd.func.ret_type),
        .params = try params.toOwnedSlice(alloc),
        .ret_record = ret_record_name,
        .is_float_kernel = blk: {
            const slots = f64AbiParamSlots(fd, records) orelse break :blk false;
            break :blk slots > 0 and slots <= 8;
        },
        .blocks = blocks,
    };
}

fn resolveType(t: ast.TypeExpr) RT {
    return switch (t) {
        .named => |n| blk: {
            if (std.mem.eql(u8, n, "i64")) break :blk .i64;
            if (std.mem.eql(u8, n, "i32")) break :blk .i32;
            if (std.mem.eql(u8, n, "str")) break :blk .str;
            if (std.mem.eql(u8, n, "bool")) break :blk .bool;
            if (std.mem.eql(u8, n, "f64")) break :blk .f64;
            break :blk .any;
        },
        .inferred => .any,
        else => .any,
    };
}

fn isIntType(t: ast.TypeExpr) bool {
    return t == .named and (std.mem.eql(u8, t.named, "i64") or std.mem.eql(u8, t.named, "i32"));
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

/// A tail call that yields nothing — its value is not a result, it is an effect.
///
/// DEMAND (rule 3) makes the last expression of a block its result, which is
/// right for every expression that HAS one. `print` does not: it is a void
/// runtime global, so an if-body ending in `print(" ")` is a discarded
/// statement that happens to sit in tail position.
///
/// Syntactic rather than type-directed because `LowerCtx` carries no type map;
/// this is the one builtin whose voidness is unconditional. A general rule
/// wants the callee's declared return type, which arrives with the same work
/// that would let user `: void` functions land here too.
fn isVoidTailCall(expr: *const ast.Expr) bool {
    const callee = switch (expr.*) {
        .call => |c| c.func,
        else => return false,
    };
    return callee.* == .name and std.mem.eql(u8, callee.name.ident, "print");
}

fn tryEmitTailDemandReturn(ctx: *LowerCtx, block: *const ast.Block) Error!bool {
    const r = tail_result_demand.blockTailResult(block) orelse return false;
    // gap[033]: emitting `ret` here made `if c print(" ") end` compile to
    // `return print(" ")`, returning whatever register the void call left —
    // exit 59, and 224 with an else, where the C backend exits 0. Lower it as
    // the effect it is and report "no return", so the branch falls through.
    if (isVoidTailCall(r.expr)) {
        _ = try lowerExprCons(ctx, r.expr, .discard);
        return false;
    }
    const ret_ty: RT = if (exprIsF64(ctx, r.expr)) .f64 else .any;
    if (r.expr.* == .table and ctx.ret_record != null) {
        try lowerRecordReturn(ctx, r.expr);
        return true;
    }
    try ctx.emit(.{ .op = .ret, .lhs = try lowerExpr(ctx, r.expr), .ty = ret_ty });
    return true;
}

fn lowerBlock(ctx: *LowerCtx, block: *const ast.Block, allow_return: bool) Error!void {
    for (block.stmts) |*stmt| try lowerStmt(ctx, stmt, allow_return);
    if (allow_return) _ = try tryEmitTailDemandReturn(ctx, block);
}

/// `req "path"` — a compile-time module binding, not a runtime call.
fn isReqCall(expr: *const ast.Expr) bool {
    if (expr.* != .call) return false;
    const c = expr.call;
    if (c.func.* != .name or !std.mem.eql(u8, c.func.name.ident, "req")) return false;
    return c.args.len == 1 and c.args[0].* == .string_lit;
}

fn lowerFieldAssignTarget(ctx: *LowerCtx, obj: *const ast.Expr, field_name: []const u8, value: *const ast.Expr) Error!void {
    if (obj.* != .name) return bail(@src());
    const fk = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ obj.name.ident, field_name });
    defer ctx.alloc.free(fk);
    const v = try lowerExprCons(ctx, value, .single);
    const store_ty: RT = if (exprIsF64(ctx, value)) .f64 else .any;
    if (ctx.locals.get(fk)) |slot| {
        if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, slot, {});
        if (exprIsStr(ctx, value)) try ctx.str_slots.put(ctx.alloc, slot, {});
        if (exprIsStr(ctx, value)) try ctx.str_slots.put(ctx.alloc, slot, {});
        try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = store_ty });
        return;
    }
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
    return ctx.f64_kernels.contains(expr.call.func.name.ident);
}

fn lowerStmt(ctx: *LowerCtx, stmt: *const ast.Stmt, allow_return: bool) Error!void {
    switch (stmt.*) {
        .local_decl => |ld| {
            // Same return-pack case as `.assign` below: `a, b = f()` arrives here
            // with more names than inits. The `i < ld.inits.len` guard kept it from
            // crashing, but silently left every name past the first unassigned —
            // a miscompile, which is worse than a refusal. Decline instead.
            if (ld.names.len != ld.inits.len and ld.inits.len == 1) return bail(@src());
            for (ld.names, 0..) |*ln, i| {
                if (i < ld.inits.len) {
                    try lowerAssignTarget(ctx, ln.ident, ld.inits[i]);
                }
                if (ln.typ != .inferred and isFloatType(ln.typ)) {
                    if (ctx.locals.get(ln.ident)) |slot| try ctx.f64_slots.put(ctx.alloc, slot, {});
                }
            }
        },
        .assign => |as| {
            // `a, b = f()` — one call feeding several targets (a return pack).
            // Zig's multi-object `for` below requires equal lengths, so an
            // unguarded pack panicked the compiler outright
            // ("for loop over objects with non-equal lengths"). Decline the
            // construct instead: DNIR lowering fails, the module falls back to the
            // C backend, and the program still compiles. Pass 42 §3.1 (correlated
            // packs with a native ABI) is what will let this lower here.
            if (as.targets.len != as.values.len) return bail(@src());
            for (as.targets, as.values) |target, value| {
                switch (target.*) {
                    .name => |n| try lowerAssignTarget(ctx, n.ident, value),
                    .field => |f| try lowerFieldAssignTarget(ctx, f.obj, f.field, value),
                    .index => |ix| try lowerIndexAssignTarget(ctx, ix.obj, ix.key, value),
                    else => return bail(@src()),
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
            try ctx.emit(.{ .op = .br_if_not, .lhs = cond, .branch_target = 0 });

            const then_ret = try lowerBlockReturns(ctx, &is.then, allow_return);
            if (!then_ret) {
                try end_branches.append(ctx.alloc, @intCast(ctx.instrs.items.len));
                try ctx.emit(.{ .op = .br, .branch_target = 0 });
            }

            for (is.elseifs) |elseif| {
                const next_idx: u32 = @intCast(ctx.instrs.items.len);
                ctx.instrs.items[fail_idx].branch_target = next_idx;
                const econd = try lowerExpr(ctx, elseif.cond);
                fail_idx = ctx.instrs.items.len;
                try ctx.emit(.{ .op = .br_if_not, .lhs = econd, .branch_target = 0 });
                const branch_ret = try lowerBlockReturns(ctx, &elseif.body, allow_return);
                if (!branch_ret) {
                    try end_branches.append(ctx.alloc, @intCast(ctx.instrs.items.len));
                    try ctx.emit(.{ .op = .br, .branch_target = 0 });
                }
            }

            const else_start: u32 = @intCast(ctx.instrs.items.len);
            ctx.instrs.items[fail_idx].branch_target = else_start;
            if (is.else_body) |*eb| _ = try lowerBlockReturns(ctx, eb, allow_return);

            const end_idx: u32 = @intCast(ctx.instrs.items.len);
            for (end_branches.items) |*br_off| {
                ctx.instrs.items[br_off.*].branch_target = end_idx;
            }
        },
        .while_loop => |ws| {
            const head_idx: u32 = @intCast(ctx.instrs.items.len);
            const cond = try lowerExpr(ctx, ws.cond);
            const fail_idx = ctx.instrs.items.len;
            try ctx.emit(.{ .op = .br_if_not, .lhs = cond, .branch_target = 0 });
            // A loop body is never an implicit-tail position: its last statement
            // runs once per iteration, not once per call. Propagating
            // `allow_return` here makes `tryEmitTailDemandReturn` end the body
            // with `return <last expr>`, so the loop returns after one pass.
            // Explicit `return` inside the body still lowers via the `.ret` arm.
            _ = try lowerBlockReturns(ctx, &ws.body, false);
            try ctx.emit(.{ .op = .br, .branch_target = head_idx });
            const end_idx: u32 = @intCast(ctx.instrs.items.len);
            ctx.instrs.items[fail_idx].branch_target = end_idx;
        },
        .num_for => |nf| try lowerNumFor(ctx, nf),
        .ret => |r| {
            if (r.vals.len == 0) {
                try ctx.emit(.{ .op = .ret, .lhs = .{ .i64 = 0 } });
            } else if (r.vals[0].* == .table) {
                try lowerRecordReturn(ctx, r.vals[0]);
            } else {
                const ret_ty: RT = if (exprIsF64(ctx, r.vals[0])) .f64 else .any;
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
        else => return bail(@src()),
    }
}

fn lowerBlockReturns(ctx: *LowerCtx, block: *const ast.Block, allow_return: bool) Error!bool {
    for (block.stmts) |*stmt| {
        if (stmt.* == .ret) {
            try lowerStmt(ctx, stmt, allow_return);
            return true;
        }
        try lowerStmt(ctx, stmt, allow_return);
    }
    if (allow_return) return try tryEmitTailDemandReturn(ctx, block);
    return false;
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
    return bail(@src());
}

fn lowerNumFor(ctx: *LowerCtx, loop: anytype) Error!void {
    if (loop.var_typ != .inferred and !isIntType(loop.var_typ)) return bail(@src());
    const step_lit: ?i64 = if (loop.step) |step| resolveIntStep(ctx, step) catch null else 1;
    if (step_lit == null) {
        try lowerRuntimeNumFor(ctx, loop);
        return;
    }
    const step = step_lit.?;
    if (step == 0) return bail(@src());
    try lowerConstNumFor(ctx, loop, step);
}

fn lowerConstNumFor(ctx: *LowerCtx, loop: anytype, step_lit: i64) Error!void {
    try lowerAssignTarget(ctx, loop.var_name, loop.start);
    const i_slot = ctx.locals.get(loop.var_name) orelse return bail(@src());
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
    try ctx.emit(.{ .op = .br_if_not, .lhs = .{ .temp = cond_temp }, .branch_target = 0 });
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
    const i_slot = ctx.locals.get(loop.var_name) orelse return bail(@src());

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
    try ctx.emit(.{ .op = .br_if_not, .lhs = .{ .temp = sign_temp }, .branch_target = 0 });

    const neg_cond = ctx.freshTemp();
    try ctx.emit(.{
        .op = .binop,
        .result = neg_cond,
        .binop = .geq,
        .lhs = .{ .local = i_slot },
        .rhs = .{ .local = stop_slot },
    });
    const neg_fail = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br_if_not, .lhs = .{ .temp = neg_cond }, .branch_target = 0 });
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
    try ctx.emit(.{ .op = .br_if_not, .lhs = .{ .temp = pos_cond }, .branch_target = 0 });

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
    const len_slot = ctx.locals.get(len_key) orelse return bail(@src());
    const len = ctx.table_lens.get(len_slot) orelse return bail(@src());
    if (len <= 0 or len > 4096) return bail(@src());

    const base = ctx.freshTemp();
    try ctx.emit(.{ .op = .alloc_slots, .result = base, .lhs = .{ .i64 = len } });
    var i: i64 = 1;
    while (i <= len) : (i += 1) {
        const elem_key = try std.fmt.allocPrint(ctx.alloc, "{s}.{d}", .{ name, i });
        defer ctx.alloc.free(elem_key);
        const elem_slot = ctx.locals.get(elem_key) orelse return bail(@src());
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

/// True when `expr` is known to produce a `str` (a `const char*`), so `#expr`
/// can lower to a `strlen` call rather than a dynamic length probe.
fn exprIsStr(ctx: *LowerCtx, expr: *const ast.Expr) bool {
    return switch (expr.*) {
        .string_lit => true,
        .binop => |bb| bb.op == .concat and exprIsStr(ctx, bb.lhs) and exprIsStr(ctx, bb.rhs),
        // `string.char(n)` PRODUCES a str. Without this the local it binds to
        // never enters str_slots, so the very next `string.byte(s, 1)` does not
        // recognize its own argument and falls through to an undefined
        // `string_byte` symbol — a producer the type tracker does not know
        // about breaks every consumer downstream.
        .call => |c| c.func.* == .field and
            c.func.field.obj.* == .name and
            std.mem.eql(u8, c.func.field.obj.name.ident, "string") and
            std.mem.eql(u8, c.func.field.field, "char"),
        .name => |n| blk: {
            const slot = ctx.locals.get(n.ident) orelse break :blk false;
            break :blk ctx.str_slots.contains(slot);
        },
        else => false,
    };
}

fn lowerAssignTarget(ctx: *LowerCtx, name: []const u8, value: *const ast.Expr) Error!void {
    // `Alias = req "std.compiler.token"` binds a module at compile time; the
    // alias exists only so `Alias.CONST` can fold and `Alias.fn` can resolve to
    // an extern symbol. There is nothing to store at runtime, and lowering it as
    // an ordinary call pushed the whole program outside the direct subset.
    if (isReqCall(value)) return;
    if (value.* == .call and value.call.func.* == .name) {
        if (ctx.func_record_returns.get(value.call.func.name.ident)) |rec_name| {
            try lowerRecordCallAssign(ctx, name, value.call.func.name.ident, value.call.args, rec_name);
            return;
        }
    }
    if (value.* == .table) {
        if (tableIsPositional(value)) {
            try lowerPositionalTableAssign(ctx, name, value);
            return;
        }
        try lowerRecordLiteralAssign(ctx, name, value);
        return;
    }
    const v = try lowerExprCons(ctx, value, .single);
    const store_ty: RT = if (exprIsF64(ctx, value)) .f64 else .any;
    if (ctx.locals.get(name)) |slot| {
        if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, slot, {});
        if (exprIsStr(ctx, value)) try ctx.str_slots.put(ctx.alloc, slot, {});
        if (exprIsStr(ctx, value)) try ctx.str_slots.put(ctx.alloc, slot, {});
        if (intLiteralStep(value)) |n| {
            const gop = try ctx.const_ints.getOrPut(ctx.alloc, name);
            if (!gop.found_existing) gop.key_ptr.* = try ctx.alloc.dupe(u8, name);
            gop.value_ptr.* = n;
        }
        try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = store_ty });
        return;
    }
    const slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, name), slot);
    if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, slot, {});
    if (exprIsStr(ctx, value)) try ctx.str_slots.put(ctx.alloc, slot, {});
    if (intLiteralStep(value)) |n| {
        const gop = try ctx.const_ints.getOrPut(ctx.alloc, name);
        if (!gop.found_existing) gop.key_ptr.* = try ctx.alloc.dupe(u8, name);
        gop.value_ptr.* = n;
    }
    try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = store_ty });
}

fn lowerRecordCallAssign(ctx: *LowerCtx, name: []const u8, callee: []const u8, args: []const *ast.Expr, rec_name: []const u8) Error!void {
    // Marshal through scalarCallLhs like every other call path. Lowering only
    // `args[0]` meant a record-returning call silently dropped every later
    // argument: `scan_one(src, pos)` reached the callee with `pos` never
    // written, so it read whatever the caller happened to leave in x1.
    const arg0 = try scalarCallLhs(ctx, args);
    try ctx.emit(.{ .op = .call_direct, .callee = callee, .lhs = arg0, .record = rec_name, .field = name });
    const rec_slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, name), rec_slot);
    try ctx.emit(.{ .op = .init_record, .result = rec_slot, .record = rec_name, .field = name });
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
    if (table.* != .table) return bail(@src());
    const t_slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, name), t_slot);
    var idx: usize = 1;
    for (table.table.fields) |fld| {
        const val = switch (fld) {
            .positional => |v| v,
            else => return bail(@src()),
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
/// An out-of-range index stores nowhere, rather than writing over an adjacent
/// local.
fn lowerIndexAssignTarget(
    ctx: *LowerCtx,
    obj: *const ast.Expr,
    key_expr: *const ast.Expr,
    value: *const ast.Expr,
) Error!void {
    if (obj.* != .name) return bail(@src());
    const table_name = obj.name.ident;

    // Memory-backed table: a real scaled store, so writes through a shared base
    // are visible to every function holding it.
    if (ptrSlotOf(ctx, obj)) |base| {
        const idx = try lowerExpr(ctx, key_expr);
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
        const slot = ctx.locals.get(key) orelse return bail(@src());
        const v = try lowerExprCons(ctx, value, .single);
        try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = .any });
        return;
    }

    const len_key = try std.fmt.allocPrint(ctx.alloc, "{s}.len", .{table_name});
    defer ctx.alloc.free(len_key);
    const len_slot = ctx.locals.get(len_key) orelse return bail(@src());
    const len = ctx.table_lens.get(len_slot) orelse return bail(@src());
    if (len == 0 or len > 32) return bail(@src());

    // Evaluate index and value once, before any store, so a select-chain cannot
    // re-run side effects per candidate slot.
    const idx_slot = ctx.freshTemp();
    try ctx.emit(.{ .op = .store_local, .result = idx_slot, .lhs = try lowerExpr(ctx, key_expr), .ty = .any });
    const val_slot = ctx.freshTemp();
    try ctx.emit(.{ .op = .store_local, .result = val_slot, .lhs = try lowerExprCons(ctx, value, .single), .ty = .any });

    var i: i64 = 1;
    while (i <= len) : (i += 1) {
        const elem_key = try std.fmt.allocPrint(ctx.alloc, "{s}.{d}", .{ table_name, i });
        defer ctx.alloc.free(elem_key);
        const elem_slot = ctx.locals.get(elem_key) orelse return bail(@src());

        const cmp = ctx.freshTemp();
        try ctx.emit(.{
            .op = .binop,
            .result = cmp,
            .binop = .eq,
            .lhs = .{ .local = idx_slot },
            .rhs = .{ .i64 = i },
        });
        const skip = ctx.instrs.items.len;
        try ctx.emit(.{ .op = .br_if_not, .lhs = .{ .temp = cmp }, .branch_target = 0 });
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
/// An out-of-range index yields 0, matching the `nil`-ish reading of a missing
/// positional entry rather than reading adjacent storage.
///
/// A genuinely dynamic, growable table still needs base-pointer addressing;
/// this handles the fixed-length case, which is what fits in registers.
fn lowerDynamicIndex(ctx: *LowerCtx, table_name: []const u8, key_expr: *const ast.Expr) Error!dnir.Value {
    const len_key = try std.fmt.allocPrint(ctx.alloc, "{s}.len", .{table_name});
    defer ctx.alloc.free(len_key);
    const len_slot = ctx.locals.get(len_key) orelse return bail(@src());
    const len = ctx.table_lens.get(len_slot) orelse return bail(@src());
    if (len == 0 or len > 32) return bail(@src());

    const idx_slot = ctx.freshTemp();
    try ctx.emit(.{ .op = .store_local, .result = idx_slot, .lhs = try lowerExpr(ctx, key_expr), .ty = .any });

    const out_slot = ctx.freshTemp();
    try ctx.emit(.{ .op = .store_local, .result = out_slot, .lhs = .{ .i64 = 0 }, .ty = .any });

    var i: i64 = 1;
    while (i <= len) : (i += 1) {
        const elem_key = try std.fmt.allocPrint(ctx.alloc, "{s}.{d}", .{ table_name, i });
        defer ctx.alloc.free(elem_key);
        const elem_slot = ctx.locals.get(elem_key) orelse return bail(@src());

        const cmp = ctx.freshTemp();
        try ctx.emit(.{
            .op = .binop,
            .result = cmp,
            .binop = .eq,
            .lhs = .{ .local = idx_slot },
            .rhs = .{ .i64 = i },
        });
        const skip = ctx.instrs.items.len;
        try ctx.emit(.{ .op = .br_if_not, .lhs = .{ .temp = cmp }, .branch_target = 0 });
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
    if (table.* != .table) return bail(@src());
    const rec_slot = ctx.freshTemp();
    try ctx.locals.put(ctx.alloc, try ctx.alloc.dupe(u8, name), rec_slot);
    for (table.table.fields) |fld| {
        const nf = switch (fld) {
            .named => |n| n,
            else => return bail(@src()),
        };
        const v = try lowerExpr(ctx, nf.val);
        const fslot = ctx.freshTemp();
        const fk = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ name, nf.key });
        try ctx.locals.put(ctx.alloc, fk, fslot);
        const store_ty: RT = if (exprIsF64(ctx, nf.val)) .f64 else .any;
        if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, fslot, {});
        try ctx.emit(.{ .op = .store_local, .result = fslot, .lhs = v, .ty = store_ty });
    }
    const rec_name = inferRecordNameFromTable(ctx.records, table) orelse "";
    try ctx.emit(.{ .op = .init_record, .result = rec_slot, .record = rec_name });
}

/// Match a table literal's named fields to a module record descriptor.
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
    if (table.* != .table) return bail(@src());
    const rec_slot = ctx.freshTemp();
    const anon = try std.fmt.allocPrint(ctx.alloc, "__rec{d}", .{rec_slot});
    defer ctx.alloc.free(anon);
    for (table.table.fields) |fld| {
        const nf = switch (fld) {
            .named => |n| n,
            else => return bail(@src()),
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

fn recordFieldsPresent(ctx: *LowerCtx, name: []const u8, rec: dnir.RecordDesc) bool {
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
            const field_slot = ctx.locals.get(key) orelse return bail(@src());
            ctx.alloc.free(key);
            const t = ctx.freshTemp();
            try ctx.emit(.{
                .op = .load_local,
                .result = t,
                .lhs = .{ .local = field_slot },
                .ty = .f64,
            });
            try ctx.emit(.{ .op = .fp_mov_arg, .result = slot.*, .lhs = .{ .temp = t } });
            slot.* += 1;
            if (slot.* > 8) return bail(@src());
        }
        return true;
    }
    return false;
}

fn lowerRecordReturn(ctx: *LowerCtx, table: *const ast.Expr) Error!void {
    if (table.* != .table) return bail(@src());
    var vals: [8]dnir.Value = undefined;
    var ni: usize = 0;
    while (ni < vals.len) : (ni += 1) vals[ni] = .void;
    var count: u32 = 0;
    for (table.table.fields) |fld| {
        const nf = switch (fld) {
            .named => |n| n,
            else => return bail(@src()),
        };
        if (count >= vals.len) return bail(@src());
        vals[count] = try lowerExpr(ctx, nf.val);
        count += 1;
    }
    try ctx.emit(.{
        .op = .ret_record,
        .record = ctx.ret_record orelse "",
        .lhs = vals[0],
        .rhs = if (count > 1) vals[1] else .void,
        .third = if (count > 2) vals[2] else .void,
        .result = count,
    });
}

fn lowerExpr(ctx: *LowerCtx, expr: *const ast.Expr) Error!dnir.Value {
    return lowerExprCons(ctx, expr, .single);
}

fn lowerExprCons(
    ctx: *LowerCtx,
    expr: *const ast.Expr,
    consumption: types.ReturnConsumption,
) Error!dnir.Value {
    return switch (expr.*) {
        .int_lit => |i| .{ .i64 = i.val },
        .float_lit => |fl| .{ .f64 = fl.val },
        .true_lit => .{ .i64 = 1 },
        .false_lit => .{ .i64 = 0 },
        .string_lit => |s| .{ .str = s.val },
        .name => |n| blk: {
            const slot = ctx.locals.get(n.ident) orelse {
                // Not a local — a module-level integer constant folds here.
                if (ctx.module_consts.get(n.ident)) |mv| break :blk dnir.Value{ .i64 = mv };
                return bailWith(@src(), n.ident);
            };
            if (ctx.f64_slots.contains(slot)) {
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .load_local, .result = t, .lhs = .{ .local = slot }, .ty = .f64 });
                break :blk dnir.Value{ .temp = t };
            }
            break :blk dnir.Value{ .local = slot };
        },
        .binop => |b| if (b.op == .@"and" or b.op == .@"or")
            try lowerShortCircuit(ctx, b.op, b.lhs, b.rhs)
        else
            try lowerBinop(ctx, b.op, b.lhs, b.rhs),
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
            return bailWith(@src(), @tagName(u.op));
        },
        .index => |ix| blk: {
            // `t[2]` on a positional table resolves to the element's own local,
            // so a constant index costs nothing at runtime. A non-constant index
            // needs a base pointer and computed offset — the native table
            // milestone — and is refused rather than mis-lowered.
            // Pass 101 §2: `s[i]` IS the byte, 0-based — there is no string
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
            if (exprIsStr(ctx, ix.obj)) {
                const sbase = try lowerExpr(ctx, ix.obj);
                const raw = try lowerExpr(ctx, ix.key);
                const one = ctx.freshTemp();
                try ctx.emit(.{ .op = .binop, .result = one, .binop = .add, .lhs = raw, .rhs = .{ .i64 = 1 } });
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .load_index, .result = t, .lhs = sbase, .rhs = .{ .temp = one } });
                break :blk dnir.Value{ .temp = t };
            }
            if (ix.obj.* != .name) return bail(@src());
            // A memory-backed table indexes for real: one scaled load, constant
            // or not. This is the path that makes a shared token array work.
            if (ptrSlotOf(ctx, ix.obj)) |base| {
                const idx = try lowerExpr(ctx, ix.key);
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
            const slot = ctx.locals.get(key) orelse return bail(@src());
            if (ctx.f64_slots.contains(slot)) {
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .load_local, .result = t, .lhs = .{ .local = slot }, .ty = .f64 });
                break :blk dnir.Value{ .temp = t };
            }
            break :blk dnir.Value{ .local = slot };
        },
        .call => try lowerCall(ctx, expr, consumption),
        .method_call => try lowerCall(ctx, try faceAsCall(ctx, expr), consumption),
        .field => try lowerField(ctx, expr),
        .macro_call => |mc| {
            if (dnir_hardware.parseIntrinsic(mc.name)) |hw| {
                return try lowerHwIntrinsic(ctx, hw, mc.args);
            }
            return bail(@src());
        },
        else => bail(@src()),
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
    const args = try ctx.alloc.alloc(*ast.Expr, mc.args.len + 1);
    args[0] = mc.obj;
    @memcpy(args[1..], mc.args);

    const func = try ctx.alloc.create(ast.Expr);
    if (exprIsStr(ctx, mc.obj)) {
        const recv = try ctx.alloc.create(ast.Expr);
        recv.* = .{ .name = .{ .loc = mc.loc, .ident = "string" } };
        func.* = .{ .field = .{ .loc = mc.loc, .obj = recv, .field = mc.method } };
    } else {
        func.* = .{ .name = .{ .loc = mc.loc, .ident = mc.method } };
    }

    const call = try ctx.alloc.create(ast.Expr);
    call.* = .{ .call = .{ .loc = mc.loc, .func = func, .args = args } };
    return call;
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
            if (c.func.* == .name and ctx.f64_kernels.contains(c.func.name.ident)) break :blk true;
            for (c.args) |a| {
                if (exprTouchesF64(ctx, a)) break :blk true;
            }
            break :blk false;
        },
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
/// `or` is expressed with `br_if_not` + `br` because the backend has no `br_if`.
fn lowerShortCircuit(ctx: *LowerCtx, op: ast.BinOp, lhs: *const ast.Expr, rhs: *const ast.Expr) Error!dnir.Value {
    // Integer contexts only. When an operand's subtree touches f64 — an f64
    // kernel call, a float literal, an f64 slot — the AST backend already lowers
    // the whole `cond and a or b` ternary correctly against f64 records, and
    // taking it over here regressed Pass 11 WP-04. Refusing keeps that fallback.
    if (exprTouchesF64(ctx, lhs) or exprTouchesF64(ctx, rhs)) return bail(@src());

    const slot = ctx.freshTemp();
    try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = try lowerExpr(ctx, lhs), .ty = .any });

    const test_idx = ctx.instrs.items.len;
    try ctx.emit(.{ .op = .br_if_not, .lhs = .{ .local = slot }, .branch_target = 0 });

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

fn lowerConcat(ctx: *LowerCtx, lhs: *const ast.Expr, rhs: *const ast.Expr) Error!dnir.Value {
    const a = try lowerExpr(ctx, lhs);
    const b = try lowerExpr(ctx, rhs);
    try ensureExtern(ctx, "string", "len", "strlen");
    try ensureExtern(ctx, "mem", "alloc", "malloc");
    try ensureExtern(ctx, "string", "copy", "strcpy");
    try ensureExtern(ctx, "string", "cat", "strcat");
    const la = ctx.freshTemp();
    try ctx.emit(.{ .op = .call_extern, .result = la, .callee = "strlen", .lhs = a });
    const lb = ctx.freshTemp();
    try ctx.emit(.{ .op = .call_extern, .result = lb, .callee = "strlen", .lhs = b });
    const sum = ctx.freshTemp();
    try ctx.emit(.{ .op = .binop, .result = sum, .binop = .add, .lhs = .{ .temp = la }, .rhs = .{ .temp = lb } });
    const total = ctx.freshTemp();
    try ctx.emit(.{ .op = .binop, .result = total, .binop = .add, .lhs = .{ .temp = sum }, .rhs = .{ .i64 = 1 } });
    const buf = ctx.freshTemp();
    try ctx.emit(.{ .op = .call_extern, .result = buf, .callee = "malloc", .lhs = .{ .temp = total } });
    try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = .{ .temp = buf } });
    try ctx.emit(.{ .op = .mov_arg, .result = 1, .lhs = a });
    try ctx.emit(.{ .op = .call_extern, .callee = "strcpy" });
    try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = .{ .temp = buf } });
    try ctx.emit(.{ .op = .mov_arg, .result = 1, .lhs = b });
    try ctx.emit(.{ .op = .call_extern, .callee = "strcat" });
    return .{ .temp = buf };
}

fn lowerBinop(ctx: *LowerCtx, op: ast.BinOp, lhs: *const ast.Expr, rhs: *const ast.Expr) Error!dnir.Value {
    if (op == .concat and exprIsStr(ctx, lhs) and exprIsStr(ctx, rhs)) {
        return try lowerConcat(ctx, lhs, rhs);
    }
    const f64_op = exprIsF64(ctx, lhs) or exprIsF64(ctx, rhs);
    const t = ctx.freshTemp();
    try ctx.emit(.{
        .op = .binop,
        .result = t,
        .binop = switch (op) {
            .add => .add,
            .sub => .sub,
            .mul => .mul,
            .div, .idiv => .div,
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
            else => return bailWith(@src(), @tagName(op)),
        },
        .lhs = try lowerExpr(ctx, lhs),
        .rhs = try lowerExpr(ctx, rhs),
        .ty = if (f64_op) .f64 else .any,
    });
    return .{ .temp = t };
}

fn emitScalarCallArgs(ctx: *LowerCtx, args: []const *ast.Expr) Error!void {
    if (args.len == 0) return;
    if (args.len > 8) return bail(@src());

    // Two phases, deliberately. `mov_arg` writes x0..x7, and evaluating a later
    // argument may itself contain a call that clobbers them: in
    // `sum2(sq(5), sq(4))` argument 0 was parked in x0 and then destroyed by the
    // call for argument 1, so both arguments arrived as sq(4). Evaluate every
    // argument first (into temps/locals, which live in the caller-saved range and
    // survive calls), then marshal them all.
    //
    // A record argument contributes one slot per field, so the slot count is not
    // the argument count.
    var values: [8]dnir.Value = undefined;
    var count: u32 = 0;
    for (args) |arg| {
        if (arg.* == .name) {
            if (scalarRecordForName(ctx, arg.name.ident)) |rec| {
                for (rec.fields) |fname| {
                    if (count >= 8) return bail(@src());
                    const key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ arg.name.ident, fname });
                    defer ctx.alloc.free(key);
                    const field_slot = ctx.locals.get(key) orelse return bail(@src());
                    values[count] = .{ .local = field_slot };
                    count += 1;
                }
                continue;
            }
            // A positional table argument is passed as one base address. It has
            // to be materialized into frame memory first — the elements are
            // registers until something needs a pointer to them.
            if (nameIsPositionalTable(ctx, arg.name.ident)) {
                if (count >= 8) return bail(@src());
                values[count] = .{ .local = try materializeTableSlots(ctx, arg.name.ident) };
                count += 1;
                continue;
            }
        }
        if (count >= 8) return bail(@src());
        values[count] = try lowerExpr(ctx, arg);
        count += 1;
    }
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        try ctx.emit(.{ .op = .mov_arg, .result = i, .lhs = values[i] });
    }
}

/// The scalar record whose fields are all bound as `name.field` locals, if any.
/// Records are stored exploded — one local per field — so "passing a record"
/// means passing its fields in consecutive argument slots, the same convention
/// the f64 kernel path already uses.
fn scalarRecordForName(ctx: *LowerCtx, name: []const u8) ?dnir.RecordDesc {
    for (ctx.records) |rec| {
        if (rec.fields.len == 0) continue;
        var all_scalar = true;
        for (rec.kinds) |k| {
            if (k == .f64) all_scalar = false;
        }
        if (!all_scalar) continue;
        if (!recordFieldsPresent(ctx, name, rec)) continue;
        return rec;
    }
    return null;
}

fn scalarCallLhs(ctx: *LowerCtx, args: []const *ast.Expr) Error!dnir.Value {
    if (args.len == 0) return .void;
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
            try emitScalarCallArgs(ctx, args);
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
        return try lowerExpr(ctx, arg);
    }
    try emitScalarCallArgs(ctx, args);
    return .void;
}

fn lowerCall(ctx: *LowerCtx, expr: *const ast.Expr, consumption: types.ReturnConsumption) Error!dnir.Value {
    if (expr.* != .call) return bail(@src());
    const c = expr.call;
    const discard = consumption == .discard;
    if (c.func.* == .field) {
        const f = c.func.field;
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
                // address. No instruction, just the identity.
                if (std.mem.eql(u8, f.field, "addr") and c.args.len == 1) {
                    return try lowerExpr(ctx, c.args[0]);
                }
            }
            if (std.mem.eql(u8, f.obj.name.ident, "os") and
                std.mem.eql(u8, f.field, "exit") and c.args.len == 1)
            {
                const arg = try lowerExpr(ctx, c.args[0]);
                try ensureExtern(ctx, "os", "exit", "exit");
                try ctx.emit(.{ .op = .call_extern, .callee = "exit", .lhs = arg });
                return .void;
            }
            if (ctx.req.exportSymbol(f.obj.name.ident, f.field)) |sym| {
                try ensureExtern(ctx, f.obj.name.ident, f.field, sym);
                // Marshal through scalarCallLhs like the static-module path
                // below. Lowering only `c.args[0]` silently dropped every later
                // argument, so `Lexer.new("fun", "proof.duo")` reached the callee
                // with one argument and garbage in x1.
                const arg0 = try scalarCallLhs(ctx, c.args);
                if (discard) {
                    try ctx.emit(.{
                        .op = .call_extern,
                        .callee = sym,
                        .lhs = arg0,
                    });
                    return .void;
                }
                const t = ctx.freshTemp();
                try ctx.emit(.{
                    .op = .call_extern,
                    .result = t,
                    .callee = sym,
                    .lhs = arg0,
                });
                return .{ .temp = t };
            }
            // `string.byte(s, i)` is a byte load from a `const char*`, not a
            // call. Lowering it as an indexed load keeps a tokenizer's inner
            // loop as plain native code with no runtime helper.
            if (std.mem.eql(u8, f.obj.name.ident, "string") and
                std.mem.eql(u8, f.field, "byte") and
                c.args.len == 2 and exprIsStr(ctx, c.args[0]))
            {
                const base = try lowerExpr(ctx, c.args[0]);
                const idx = try lowerExpr(ctx, c.args[1]);
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .load_index, .result = t, .lhs = base, .rhs = idx });
                return .{ .temp = t };
            }
            // `string.len(s)` is a byte-length scan over a `const char*`, not a
            // call. Lowering it as `str_len` (an inline loop in the backend)
            // keeps the lexer's `while self.pos <= string.len(self.src)` guard
            // inside the direct subset instead of forcing the C backend.
            if (std.mem.eql(u8, f.obj.name.ident, "string") and
                std.mem.eql(u8, f.field, "len") and
                c.args.len == 1 and exprIsStr(ctx, c.args[0]))
            {
                const base = try lowerExpr(ctx, c.args[0]);
                const t = ctx.freshTemp();
                try ctx.emit(.{ .op = .str_len, .result = t, .lhs = base });
                return .{ .temp = t };
            }
            // Static module member: math.add(a, b) → call_direct math.add
            const qualified = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ f.obj.name.ident, f.field });
            const arg0 = try scalarCallLhs(ctx, c.args);
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
        if (ctx.f64_kernels.contains(callee)) {
            return try lowerF64KernelCall(ctx, callee, c.args);
        }
        if (std.mem.eql(u8, callee, "print")) {
            return lowerPrint(ctx, c.args);
        }
        const arg0 = try scalarCallLhs(ctx, c.args);
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
    // Name the callee. Every row this session that reported only a location
    // turned out to be covering more than one cause, and a call site's whole
    // content is "I could not resolve this callee" — the name IS the finding.
    return bailWith(@src(), switch (c.func.*) {
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
fn lowerPrint(ctx: *LowerCtx, args: []const *ast.Expr) Error!dnir.Value {
    if (args.len == 0) {
        try ctx.emit(.{ .op = .print_value });
        return .void;
    }
    if (args.len != 1) return bail(@src());
    const arg = args[0];
    const v = try lowerExpr(ctx, arg);
    const ty: RT = if (exprIsStr(ctx, arg)) .str else if (exprIsF64Value(ctx, arg)) .f64 else .i64;
    try ctx.emit(.{ .op = .print_value, .lhs = v, .ty = ty });
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
    if (args.len == 0) return bail(@src());
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
                        else => return bail(@src()),
                    };
                    try ctx.emit(.{ .op = .fp_mov_arg, .result = slot, .lhs = try lowerExpr(ctx, val) });
                    slot += 1;
                    if (slot > 8) return bail(@src());
                }
            },
            .name => |n| {
                if (try emitF64RecordFieldsFromName(ctx, n.ident, &slot)) {} else {
                    try ctx.emit(.{ .op = .fp_mov_arg, .result = slot, .lhs = try lowerExpr(ctx, arg) });
                    slot += 1;
                    if (slot > 8) return bail(@src());
                }
            },
            else => {
                try ctx.emit(.{ .op = .fp_mov_arg, .result = slot, .lhs = try lowerExpr(ctx, arg) });
                slot += 1;
                if (slot > 8) return bail(@src());
            },
        }
    }
    if (slot == 0) return bail(@src());
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
            if (args.len != 1) return bail(@src());
            const t = ctx.freshTemp();
            try ctx.emit(.{
                .op = .hw_unary,
                .hw = hw,
                .result = t,
                .lhs = try lowerExpr(ctx, args[0]),
            });
            return .{ .temp = t };
        },
        .none => bail(@src()),
    };
}

fn ensureExtern(ctx: *LowerCtx, alias: []const u8, field: []const u8, sym: []const u8) Error!void {
    for (ctx.externs.items) |e| {
        if (std.mem.eql(u8, e.symbol, sym)) return;
    }
    const duo = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ alias, field });
    try ctx.externs.append(ctx.alloc, .{ .duo_name = duo, .symbol = try ctx.alloc.dupe(u8, sym) });
}

fn lowerField(ctx: *LowerCtx, expr: *const ast.Expr) Error!dnir.Value {
    if (expr.* != .field) return bail(@src());
    const fld = expr.field;
    if (fld.obj.* == .name) {
        // Module-level descriptor constant: `Kind.ident` folds to an immediate.
        const mk = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ fld.obj.name.ident, fld.field });
        defer ctx.alloc.free(mk);
        if (ctx.module_consts.get(mk)) |mv| return .{ .i64 = mv };
        if (ctx.req.constant(fld.obj.name.ident, fld.field)) |val| {
            const t = ctx.freshTemp();
            try ctx.emit(.{ .op = .const_req, .result = t, .req_alias = fld.obj.name.ident, .field = fld.field, .lhs = .{ .i64 = val } });
            return .{ .temp = t };
        }
        const key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ fld.obj.name.ident, fld.field });
        defer ctx.alloc.free(key);
        if (ctx.locals.get(key)) |slot| return .{ .local = slot };
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
        \\    if bits ~= 5 return 1 end
        \\    @comp.hint.fence()
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "pass16_hardware_direct.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
    var lex = @import("lexer.zig").Lexer.init(src, "test.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
    var lex = @import("lexer.zig").Lexer.init(src, "pass4_dnir.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
    var lex = @import("lexer.zig").Lexer.init(src, "pass4_call.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
        \\main(): i64
        \\    i = 0
        \\    while i < 3
        \\        i = i + 1
        \\    end
        \\    i
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "while.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
        \\main(): i64
        \\    sum = 0
        \\    for i = 0, 2
        \\        sum = sum + i
        \\    end
        \\    sum
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "num_for.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
    var lex = @import("lexer.zig").Lexer.init(src, "f64_local.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
    var lex = @import("lexer.zig").Lexer.init(src, "add2.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
    var lex = @import("lexer.zig").Lexer.init(src, "math_add_call.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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

test "dnir_lower: f64 kernel call with record variable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    p = { x = 3.0, y = 4.0 }
        \\    r: f64 = distance2(p)
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "record_var.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var main_fn: ?dnir.Function = null;
    for (m.functions) |f| {
        if (std.mem.eql(u8, f.name, "main")) main_fn = f;
    }
    const main = main_fn orelse return error.TestUnexpectedResult;
    var fp_movs: u32 = 0;
    var load_f64_fields: u32 = 0;
    for (main.blocks[0].instrs) |ins| {
        if (ins.op == .fp_mov_arg) fp_movs += 1;
        if (ins.op == .load_local and ins.ty == .f64) load_f64_fields += 1;
    }
    try std.testing.expect(fp_movs == 2);
    try std.testing.expect(load_f64_fields == 2);
}

test "dnir_lower: main returns f64 kernel tail" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): f64
        \\    distance2({ x = 3.0, y = 4.0 })
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "main_f64.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
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

test "dnir_lower: no mandatory main — entry function lowers uniformly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\run(): i64
        \\    42
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "run.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
    var lex = @import("lexer.zig").Lexer.init(src, "implicit_f64.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
        \\main(): i64
        \\    sum = 0
        \\    for i = 3, 1, -1
        \\        sum = sum + i
        \\    end
        \\    sum
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "neg_for.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
        \\main(): i64
        \\    step = -1
        \\    sum = 0
        \\    for i = 3, 1, step
        \\        sum = sum + i
        \\    end
        \\    sum
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "const_step.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
    var lex = @import("lexer.zig").Lexer.init(src, "test.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
    var lex = @import("lexer.zig").Lexer.init(src, "f64_cmp.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
    var lex = @import("lexer.zig").Lexer.init(src, "elseif.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    var br_if_not: u32 = 0;
    for (m.functions[0].blocks[0].instrs) |ins| {
        if (ins.op == .br_if_not) br_if_not += 1;
    }
    try std.testing.expect(br_if_not >= 3);
}

test "dnir_lower: numeric for runtime step parameter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\sum_to(n: i64, step: i64): i64
        \\    s = 0
        \\    for i = 1, n, step
        \\        s = s + i
        \\    end
        \\    s
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "runtime_step.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
    var lex = @import("lexer.zig").Lexer.init(src, "test.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m_direct = try lowerModule(alloc, &mod);
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCalls(&mod, "test.duo");
    const m_graph = try lowerModuleWithGraph(alloc, &mod, &g);
    try std.testing.expect(m_direct.functions.len == m_graph.functions.len);
    try std.testing.expect(m_direct.hardware_tier == m_graph.hardware_tier);
    try std.testing.expect(m_direct.functions[0].blocks[0].instrs.len == m_graph.functions[0].blocks[0].instrs.len);
    try std.testing.expect(m_graph.functions[0].graph_stable_id != null);
}

test "dnir_lower: graph orders callees before callers" {
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
    var lex = @import("lexer.zig").Lexer.init(src, "graph_order.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCalls(&mod, "graph_order.duo");
    const m = try lowerModuleWithGraph(alloc, &mod, &g);
    var idx_distance: ?usize = null;
    var idx_main: ?usize = null;
    for (m.functions, 0..) |f, i| {
        if (std.mem.eql(u8, f.name, "distance2")) idx_distance = i;
        if (std.mem.eql(u8, f.name, "main")) idx_main = i;
        try std.testing.expect(f.graph_stable_id != null);
    }
    try std.testing.expect(idx_distance != null and idx_main != null);
    try std.testing.expect(idx_distance.? < idx_main.?);
}

test "dnir_lower: graph attaches shape_id to native records" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\main(): i64
        \\    0
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "shape.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    var g = semantic_graph.SemanticGraph.init(alloc);
    defer g.deinit();
    _ = try g.liftModuleWithCalls(&mod, "shape.duo");
    const shape_node = g.findTableShape("Point") orelse return error.TestExpectedEqual;
    const m = try lowerModuleWithGraph(alloc, &mod, &g);
    try std.testing.expect(m.records.len >= 1);
    var found = false;
    for (m.records) |rec| {
        if (!std.mem.eql(u8, rec.name, "Point")) continue;
        found = true;
        try std.testing.expect(rec.shape_id != null);
        try std.testing.expectEqual(shape_node.shape_id.?, rec.shape_id.?);
        try std.testing.expect(rec.graph_stable_id != null);
    }
    try std.testing.expect(found);
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
    var lex = @import("lexer.zig").Lexer.init(src, "rec.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
    var lex = @import("lexer.zig").Lexer.init(src, "f64ret.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
    var lex = @import("lexer.zig").Lexer.init(src, "f64tbl.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
    var lex = @import("lexer.zig").Lexer.init(src, "discard.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
    var lex = @import("lexer.zig").Lexer.init(src, "trail.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
    var lex = @import("lexer.zig").Lexer.init(src, "static.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
    var lex = @import("lexer.zig").Lexer.init(src, "method.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
    var lex = @import("lexer.zig").Lexer.init(src, "field.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const m = try lowerModule(alloc, &mod);
    const f = m.functions[0];
    var ret_count: usize = 0;
    var ret_from_field = false;
    for (f.blocks) |b| {
        for (b.instrs) |ins| {
            if (ins.op != .ret) continue;
            ret_count += 1;
            if (ins.lhs == .local and ins.lhs.local != 0 and ins.lhs.local != 1) ret_from_field = true;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), ret_count);
    try std.testing.expect(ret_from_field);
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
    var lex = @import("lexer.zig").Lexer.init(src, "ifbind.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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
                if (saw_v_store and (ins.op == .br_if_not or ins.op == .br_if)) br_after_store = true;
            }
        }
    }
    try std.testing.expect(saw_get_call);
    try std.testing.expect(saw_v_store);
    try std.testing.expect(br_after_store);
}
