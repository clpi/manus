//! AST → DNIR lowering for typed native programs (no lua_Value, no C-string codegen).
//!
//! Produces `duo_native_ir.Module` for direct machine backends. C emission is bootstrap-only.
//!
//! Entry points: Duo modules export functions at file scope (file-as-M). There is no
//! Python/Lua-style mandatory `main()` or special entry typing — any eligible function
//! lowers the same way; linker entry is `@export` / CLI target, not a magic name.
const std = @import("std");
const ast = @import("ast.zig");
const Expr = ast.Expr;
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
/// `.string_lit` arm's `s.val`, and the AST outlives lowering. Keys are duped
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

const CheckedApplication = struct {
    relation: semantic_graph.NodeId,
    subject: ?semantic_graph.NodeId,
    arguments: []semantic_graph.NodeId,
    descriptor: types.ResolvedType,
    relation_identity: dnir.SemanticRef,
    application_identity: dnir.SemanticRef,
    value_identity: dnir.SemanticRef,
    subject_identity: ?dnir.SemanticRef,
    caller_identity: dnir.SemanticRef,
};

const ApplicationEdges = struct {
    relation: ?semantic_graph.NodeId = null,
    result: ?semantic_graph.NodeId = null,
    subject: ?semantic_graph.NodeId = null,
    argument_count: usize = 0,
};

fn containingFunctionFromScope(
    graph: *const semantic_graph.SemanticGraph,
    start: semantic_graph.NodeId,
) ?semantic_graph.NodeId {
    var current = start;
    var depth: u32 = 0;
    while (depth < 64) : (depth += 1) {
        const node = graph.get(current) orelse return null;
        if (node.kind == .func) return current;
        if (!node.scope.isValid()) return null;
        current = node.scope;
    }
    return null;
}

fn semanticReference(
    graph: *const semantic_graph.SemanticGraph,
    node_id: semantic_graph.NodeId,
) Error!dnir.SemanticRef {
    const node = graph.get(node_id) orelse return bail(@src());
    return .{
        .node = node_id.index,
        .fingerprint = (node.stable_id orelse return bail(@src())).hash,
    };
}

/// One module-local query index for checked application facts. This is a
/// bootstrap projection of graph identities, not a replacement application
/// schema; missing owner facts remain missing and are never synthesized.
const CheckedApplicationIndex = struct {
    alloc: std.mem.Allocator,
    applications: std.ArrayListUnmanaged(CheckedApplication) = .empty,
    by_expression: std.AutoHashMapUnmanaged(*const Expr, usize) = .empty,
    by_node: []?usize = &.{},
    has_unresolved_calls: bool = false,

    fn init(
        alloc: std.mem.Allocator,
        graph: *const semantic_graph.SemanticGraph,
    ) Error!CheckedApplicationIndex {
        var index: CheckedApplicationIndex = .{ .alloc = alloc };
        errdefer index.deinit();

        const edges = try alloc.alloc(ApplicationEdges, graph.nodes.items.len);
        defer alloc.free(edges);
        for (edges) |*entry| entry.* = .{};
        for (graph.edges.items) |edge| {
            if (edge.from.index >= edges.len) return bailWith(@src(), "application-edge");
            if (graph.nodes.items[edge.from.index].kind != .call) continue;
            switch (edge.kind) {
                .relation => {
                    if (edges[edge.from.index].relation != null) return bailWith(@src(), "application-relation-count");
                    edges[edge.from.index].relation = edge.to;
                },
                .result => {
                    if (edges[edge.from.index].result != null) return bailWith(@src(), "application-result-count");
                    edges[edge.from.index].result = edge.to;
                },
                .subject => {
                    if (edges[edge.from.index].subject != null) return bailWith(@src(), "application-subject-count");
                    edges[edge.from.index].subject = edge.to;
                },
                .argument => edges[edge.from.index].argument_count += 1,
                else => {},
            }
        }

        index.by_node = try alloc.alloc(?usize, graph.nodes.items.len);
        @memset(index.by_node, null);
        for (graph.nodes.items, 0..) |node, i| {
            if (node.kind != .call) continue;
            const relation = edges[i].relation orelse {
                index.has_unresolved_calls = true;
                continue;
            };
            const result = edges[i].result orelse return bailWith(@src(), "application-result");
            const caller = containingFunctionFromScope(graph, .{ .index = @intCast(i) }) orelse
                return bailWith(@src(), "application-caller");
            const result_node = graph.get(result) orelse return bail(@src());
            const expression_raw = node.ast_ref orelse return bailWith(@src(), "application-provenance");
            const expression: *const Expr = @ptrCast(@alignCast(expression_raw));
            const descriptor = result_node.descriptor orelse
                return bailWith(@src(), "application-result-descriptor");
            const relation_identity = try semanticReference(graph, relation);
            const application_identity = try semanticReference(graph, .{ .index = @intCast(i) });
            const value_identity = try semanticReference(graph, result);
            const subject_identity = if (edges[i].subject) |subject|
                try semanticReference(graph, subject)
            else
                null;
            const caller_identity = try semanticReference(graph, caller);
            const arguments = try alloc.alloc(semantic_graph.NodeId, edges[i].argument_count);
            for (arguments) |*argument| argument.* = semantic_graph.NodeId.invalid;

            const application_index = index.applications.items.len;
            index.applications.append(alloc, .{
                .relation = relation,
                .subject = edges[i].subject,
                .arguments = arguments,
                .descriptor = descriptor,
                .relation_identity = relation_identity,
                .application_identity = application_identity,
                .value_identity = value_identity,
                .subject_identity = subject_identity,
                .caller_identity = caller_identity,
            }) catch |err| {
                alloc.free(arguments);
                return err;
            };
            index.by_node[i] = application_index;
            const slot = try index.by_expression.getOrPut(alloc, expression);
            if (slot.found_existing) return bailWith(@src(), "application-provenance-collision");
            slot.value_ptr.* = application_index;
        }

        for (graph.edges.items) |edge| {
            if (edge.kind != .argument or edge.from.index >= index.by_node.len) continue;
            const application_index = index.by_node[edge.from.index] orelse continue;
            const application = &index.applications.items[application_index];
            const position: usize = edge.position;
            if (position >= application.arguments.len or application.arguments[position].isValid()) {
                return bailWith(@src(), "application-argument-position");
            }
            application.arguments[position] = edge.to;
        }
        for (index.applications.items) |application| {
            for (application.arguments) |argument| {
                if (!argument.isValid()) return bailWith(@src(), "application-argument-position");
            }
        }
        return index;
    }

    fn deinit(self: *CheckedApplicationIndex) void {
        for (self.applications.items) |application| self.alloc.free(application.arguments);
        self.applications.deinit(self.alloc);
        self.by_expression.deinit(self.alloc);
        if (self.by_node.len > 0) self.alloc.free(self.by_node);
    }

    fn get(self: *const CheckedApplicationIndex, expression: *const Expr) ?*const CheckedApplication {
        const application_index = self.by_expression.get(expression) orelse return null;
        return &self.applications.items[application_index];
    }
};

/// Collect top-level constant bindings so a function body can fold them.
///
/// `N = 3` and the canonical enum form `Kind = @{ eof = 0, ident = 1 }` are
/// module-level values; nothing registered them as locals, so `Kind.ident`
/// inside a function resolved to a runtime field load and failed with DNB007.
/// Both spellings are compile-time constants and belong as immediates.
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
            else => {},
        }
        const n = name orelse continue;
        const v = val orelse continue;
        if (intLiteralStep(v)) |iv| {
            try map.put(alloc, try alloc.dupe(u8, n), iv);
            continue;
        }
        if (v.* == .string_lit) {
            try out.strs.put(alloc, try alloc.dupe(u8, n), v.string_lit.val);
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
            if (nf.val.* == .string_lit) {
                const key = try std.fmt.allocPrint(alloc, "{s}.{s}", .{ n, nf.key });
                try out.strs.put(alloc, key, nf.val.string_lit.val);
            }
        }
    }
    return out;
}

pub fn lowerModule(alloc: std.mem.Allocator, mod: *const ast.Module) Error!dnir.Module {
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = graph.liftModuleWithCalls(mod, "<dnir>") catch return error.OutOfMemory;
    return lowerModuleWithGraph(alloc, mod, &graph);
}

fn lowerModuleFromGraph(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    graph: *const semantic_graph.SemanticGraph,
    applications: *const CheckedApplicationIndex,
) Error!dnir.Module {
    bail_site.line = 0;
    var req = try native_req_support.collectFromModule(alloc, mod);
    defer req.deinit(alloc);

    var module_consts = try collectModuleConsts(alloc, mod);
    defer module_consts.deinit(alloc);

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

    // Join declarations to graph identities by exact provenance. The exported
    // function name remains a linker/debug symbol; it is not an identity key.
    var function_identities: std.AutoHashMapUnmanaged(*const ast.FuncDecl, dnir.SemanticRef) = .empty;
    defer function_identities.deinit(alloc);
    for (graph.nodes.items, 0..) |node, i| {
        if (node.kind != .func) continue;
        const raw = node.ast_ref orelse continue;
        const declaration: *const ast.FuncDecl = @ptrCast(@alignCast(raw));
        try function_identities.put(
            alloc,
            declaration,
            try semanticReference(graph, .{ .index = @intCast(i) }),
        );
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
        if (!functionEligible(fd, records.items)) continue;
        const slots = f64AbiParamSlots(fd, records.items) orelse continue;
        if (slots == 0 or slots > 8) continue;
        const key = try funcExportName(alloc, fd);
        if (fp_params.contains(key)) {
            alloc.free(key);
            continue;
        }
        try fp_params.put(alloc, key, try paramSlotIsFp(alloc, fd, records.items));
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
        const f = try lowerFunction(
            alloc,
            fd,
            function_identities.get(fd),
            records.items,
            graph,
            applications,
            &req,
            &externs,
            &func_record_returns,
            &fp_params,
            &module_consts,
        );
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

/// Pass 16 hook: graph identity controls checked call ordering and provenance.
pub fn lowerModuleWithGraph(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    graph: *const semantic_graph.SemanticGraph,
) Error!dnir.Module {
    var applications = try CheckedApplicationIndex.init(alloc, graph);
    defer applications.deinit();
    var m = try lowerModuleFromGraph(alloc, mod, graph, &applications);
    errdefer dnir.deinitModule(alloc, m);
    try applyGraphToModule(alloc, graph, &applications, &m);
    return m;
}

fn applyGraphToModule(
    alloc: std.mem.Allocator,
    graph: *const semantic_graph.SemanticGraph,
    applications: *const CheckedApplicationIndex,
    m: *dnir.Module,
) Error!void {
    try reorderFunctionsByGraphIdentity(alloc, applications, m);

    const recs: []dnir.RecordDesc = @constCast(m.records);
    for (recs) |*rec| {
        if (graph.findTableShape(rec.name)) |shape| {
            rec.shape_id = shape.shape_id;
            if (shape.stable_id) |sid| rec.graph_stable_id = sid.hash;
        }
    }
}

/// Place checked callees before callers using graph identities only. If any
/// in-module application is unresolved, retaining source order is safer than
/// completing the dependency graph from its spelling.
fn reorderFunctionsByGraphIdentity(
    alloc: std.mem.Allocator,
    applications: *const CheckedApplicationIndex,
    m: *dnir.Module,
) Error!void {
    if (m.functions.len <= 1) return;
    if (applications.has_unresolved_calls) return;

    var functions_by_identity: std.AutoHashMapUnmanaged(u32, usize) = .empty;
    defer functions_by_identity.deinit(alloc);
    for (m.functions, 0..) |function, i| {
        const identity = function.semantic_identity orelse return;
        const slot = try functions_by_identity.getOrPut(alloc, identity.node);
        if (slot.found_existing) return bailWith(@src(), "function-identity-collision");
        slot.value_ptr.* = i;
    }

    const in_degree = try alloc.alloc(usize, m.functions.len);
    defer alloc.free(in_degree);
    @memset(in_degree, 0);
    const unlocks = try alloc.alloc(std.ArrayListUnmanaged(usize), m.functions.len);
    defer {
        for (unlocks) |*list| list.deinit(alloc);
        alloc.free(unlocks);
    }
    for (unlocks) |*list| list.* = .empty;
    var dependency_edges: std.AutoHashMapUnmanaged(u128, void) = .empty;
    defer dependency_edges.deinit(alloc);

    var checked_edges: usize = 0;
    for (applications.applications.items) |application| {
        const caller_index = functions_by_identity.get(application.caller_identity.node) orelse continue;
        const relation_index = functions_by_identity.get(application.relation_identity.node) orelse continue;
        const dependency = (@as(u128, relation_index) << 64) | @as(u128, caller_index);
        const slot = try dependency_edges.getOrPut(alloc, dependency);
        if (slot.found_existing) continue;
        try unlocks[relation_index].append(alloc, caller_index);
        in_degree[caller_index] += 1;
        checked_edges += 1;
    }
    if (checked_edges == 0) return;

    var ready: std.ArrayListUnmanaged(usize) = .empty;
    defer ready.deinit(alloc);
    for (in_degree, 0..) |degree, i| {
        if (degree == 0) try ready.append(alloc, i);
    }
    var order: std.ArrayListUnmanaged(usize) = .empty;
    defer order.deinit(alloc);
    while (ready.items.len > 0) {
        const function_index = ready.pop().?;
        try order.append(alloc, function_index);
        for (unlocks[function_index].items) |caller_index| {
            in_degree[caller_index] -= 1;
            if (in_degree[caller_index] == 0) try ready.append(alloc, caller_index);
        }
    }
    if (order.items.len != m.functions.len) return;

    const ordered = try alloc.alloc(dnir.Function, m.functions.len);
    defer alloc.free(ordered);
    for (order.items, 0..) |source_index, destination_index| {
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

/// Past `max_reg_record_fields` a record return uses the AAPCS64 indirect-result
/// convention: the CALLER reserves the buffer and passes its address in x8, and
/// the callee writes the fields through it. Bounded so the caller's frame
/// reservation stays a small `sub sp` immediate.
pub const max_record_fields = 32;

/// True when a record return must use the x8 indirect-result convention rather
/// than the x0..x7 explosion.
pub fn recordReturnIsIndirect(rec: dnir.RecordDesc) bool {
    return rec.fields.len > max_reg_record_fields;
}

fn functionEligible(fd: *const ast.FuncDecl, recs: []const dnir.RecordDesc) bool {
    if (fd.func.vararg or fd.func.vararg_name != null) return false;
    if (findRecordName(recs, fd.func.ret_type)) |rec| {
        if (rec.fields.len == 0 or rec.fields.len > max_record_fields) return false;
        // An f64 record rides v0..v7 as a homogeneous float aggregate; there is
        // no indirect form for it here, so its own eight stays a hard limit.
        if (isF64Record(recs, fd.func.ret_type)) |_| {
            if (rec.fields.len > max_reg_record_fields) return false;
        }
        for (fd.func.params) |p| {
            // A record PARAMETER is still one field per argument register —
            // only the RETURN gained an indirect form. Admitting a wide record
            // here would explode past x7 and read caller garbage.
            if (isF64Record(recs, p.typ)) |r| {
                if (r.fields.len > max_reg_record_fields) return false;
                continue;
            }
            if (findRecordName(recs, p.typ)) |r| {
                if (r.fields.len > max_reg_record_fields) return false;
                continue;
            }
            if (!isIntType(p.typ) and !isBoolType(p.typ) and !isStrType(p.typ) and !typeIsPtr(p.typ)) return false;
        }
        return true;
    }
    if (isFloatType(fd.func.ret_type)) {
        const slots = f64AbiParamSlots(fd, recs) orelse return false;
        return slots <= 8;
    }
    if (!isIntType(fd.func.ret_type) and !isBoolType(fd.func.ret_type) and
        !isStrType(fd.func.ret_type) and !isVoidType(fd.func.ret_type) and
        fd.func.ret_type != .inferred) return false;
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
        if (findRecordName(recs, p.typ)) |r| {
            if (r.fields.len > max_reg_record_fields) return false;
            continue;
        }
        // `ptr` rides x0..x7 like an i64 — it is the base address of a
        // memory-backed positional table (SH-04).
        if (!isIntType(p.typ) and !isBoolType(p.typ) and !isStrType(p.typ) and !typeIsPtr(p.typ)) return false;
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
        if (rec.fields.len == 0 or rec.fields.len > max_record_fields) continue;
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
    graph: *const semantic_graph.SemanticGraph,
    applications: *const CheckedApplicationIndex,
    req: *const native_req_support.Context,
    externs: *std.ArrayList(dnir.Extern),
    func_record_returns: *std.StringHashMapUnmanaged([]const u8),
    /// GAP-056: per-callee ABI slot classes, so a caller marshals f64 arguments
    /// into v0..v7 instead of x0..x7. Empty means no callee needs FP slots.
    fp_params: *const std.StringHashMapUnmanaged([]bool) = &empty_fp_params,
    /// GAP-056: this function's own f64 parameters are homed in d0..d7, so
    /// staging an outgoing f64 argument would overwrite one of them.
    self_fp_params: bool = false,
    /// When set, tail/table returns lower to `ret_record` for this record name.
    ret_record: ?[]const u8 = null,
    /// Local slots that hold f64 values inside integer kernels.
    f64_slots: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Local slots holding `str` (a `const char*`), so `#s` can lower to strlen.
    str_slots: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Local slots holding `bool`. A bool rides an integer register, so nothing
    /// downstream can tell one from an i64 by its representation — only this
    /// set can, and `..` needs the answer to choose between `true` and `1`.
    bool_slots: std.AutoHashMapUnmanaged(u32, void) = .empty,
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
    module_consts: *const ModuleConsts = &empty_module_consts,
    /// Names bound to compile-time-known i64 literals (for numeric for step, etc.).
    const_ints: std.StringHashMapUnmanaged(i64) = .empty,
    next_temp: u32 = 0,
    locals: std.StringHashMapUnmanaged(u32) = .empty,
    instrs: std.ArrayList(dnir.Instr) = .empty,
    /// The function being lowered, when a self-call in TAIL position can be
    /// turned into a jump. Empty disables the rewrite — see `tryEmitSelfTail`.
    self_name: []const u8 = "",
    /// Its parameter slots, in order. One slot per parameter, which is what
    /// makes the reassign-and-jump legal: a record parameter occupies several
    /// slots and is excluded rather than partially written.
    self_param_slots: []const u32 = &.{},

    pub fn deinit(self: *LowerCtx) void {
        var it = self.locals.iterator();
        while (it.next()) |e| self.alloc.free(e.key_ptr.*);
        self.locals.deinit(self.alloc);
        self.f64_slots.deinit(self.alloc);
        self.str_slots.deinit(self.alloc);
        self.bool_slots.deinit(self.alloc);
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
    semantic_identity: ?dnir.SemanticRef,
    records: []const dnir.RecordDesc,
    graph: *const semantic_graph.SemanticGraph,
    applications: *const CheckedApplicationIndex,
    req: *const native_req_support.Context,
    externs: *std.ArrayList(dnir.Extern),
    func_record_returns: *std.StringHashMapUnmanaged([]const u8),
    fp_params: *const std.StringHashMapUnmanaged([]bool),
    module_consts: *const ModuleConsts,
) Error!dnir.Function {
    var ctx: LowerCtx = .{
        .alloc = alloc,
        .records = records,
        .graph = graph,
        .applications = applications,
        .req = req,
        .externs = externs,
        .func_record_returns = func_record_returns,
        .fp_params = fp_params,
        .self_fp_params = blk: {
            const slots = f64AbiParamSlots(fd, records) orelse break :blk false;
            break :blk slots > 0;
        },
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
        // A `bool` parameter is an integer register the printer must not read as
        // a number.
        if (isBoolType(par.typ)) try ctx.bool_slots.put(alloc, param_slot_cursor, {});
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

    // §12 TAIL, armed only for a flat scalar frame. `param_slot_cursor` counts
    // the slots actually assigned above, so this equality IS the test for "one
    // slot per parameter" — a record parameter exploded into several and the
    // cursor runs ahead of the parameter list.
    if (fd.path.len == 1 and param_slot_cursor == fd.func.params.len) {
        const slots = try alloc.alloc(u32, fd.func.params.len);
        for (0..fd.func.params.len) |i| slots[i] = @intCast(i);
        ctx.self_name = fd.path[0];
        ctx.self_param_slots = slots;
    }

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
        .semantic_identity = semantic_identity,
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
            break :blk .any;
        },
        .inferred => .any,
        else => .any,
    };
}

/// `int` and `integer` ARE `i64`, and this is not a courtesy: `types.zig`
/// resolves both to `.i64` under "Common aliases", so they are the same type by
/// the language's own answer. This pass matched the two spellings `i64` and
/// `i32` literally, so `exit(code: int)` in `lib/std/os.duo` was ineligible —
/// and because `lowerModule` requires EVERY function in a module to lower, one
/// spliced `os.exit` refused the whole program. Two spellings of one type, and
/// the narrower reading cost every program that touches `std.os`.
///
/// Only the exact aliases. `i8`, `u32` and friends resolve to their own widths
/// and would need truncation this pass does not emit, so they stay out.
fn isIntAlias(n: []const u8) bool {
    return std.mem.eql(u8, n, "int") or std.mem.eql(u8, n, "integer");
}

fn isIntType(t: ast.TypeExpr) bool {
    return t == .named and (std.mem.eql(u8, t.named, "i64") or
        std.mem.eql(u8, t.named, "i32") or isIntAlias(t.named));
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
    // supplies a transform identity and witness. Let ordinary checked-call
    // lowering retain the application instead of authorizing a rewrite from
    // the callee spelling.
    if (ctx.applications.get(expr) != null) return false;
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
    // gap[033]: emitting `ret` here made `if c print(" ") end` compile to
    // `return print(" ")`, returning whatever register the void call left —
    // exit 59, and 224 with an else, where the C backend exits 0. Lower it as
    // the effect it is and report "no return", so the branch falls through.
    if (isVoidTailCall(r.expr)) {
        _ = try lowerExprCons(ctx, r.expr, .discard);
        return false;
    }
    const ret_ty: RT = if (exprIsF64(ctx, r.expr)) .f64 else .any;
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
        }
        // No slot means the statement did not lower to storage this pass can
        // name. Re-evaluating would be a miscompile, so decline the function
        // instead and let the C backend take it.
        return bail(@src());
    }
    if (try tryEmitSelfTail(ctx, r.expr)) return true;
    try ctx.emit(.{ .op = .ret, .lhs = try lowerExpr(ctx, r.expr), .ty = ret_ty });
    return true;
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
    for (block.stmts, 0..) |*stmt, i| {
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

fn functionResultIs(
    ctx: *const LowerCtx,
    name: []const u8,
    expected: std.meta.Tag(types.ResolvedType),
) bool {
    const descriptor = ctx.graph.funcResultDescriptor(name) orelse return false;
    return std.meta.activeTag(descriptor) == expected;
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
                // `ok: bool = f()` where `f` is not declared `: bool`. The
                // ANNOTATION is the answer here and the initializer is not, so
                // the mark has to follow the declared type as well.
                if (isBoolType(ln.typ)) {
                    if (ctx.locals.get(ln.ident)) |slot| try ctx.bool_slots.put(ctx.alloc, slot, {});
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
            try ctx.emit(.{ .op = .br, .lhs = cond, .branch_target = 0, .branch_condition = .when_false });

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
                try ctx.emit(.{ .op = .br, .lhs = econd, .branch_target = 0, .branch_condition = .when_false });
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
        },
        .num_for => |nf| try lowerNumFor(ctx, nf),
        .ret => |r| {
            if (r.vals.len == 0) {
                try ctx.emit(.{ .op = .ret, .lhs = .{ .i64 = 0 } });
            } else if (r.vals[0].* == .table or
                (ctx.ret_record != null and isRecordLocalName(ctx, r.vals[0])))
            {
                try lowerRecordReturn(ctx, r.vals[0]);
            } else if (!try tryEmitSelfTail(ctx, r.vals[0])) {
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
    for (block.stmts, 0..) |*stmt, i| {
        const tail_here = allow_return and stmtIsTailSlot(block, i);
        if (stmt.* == .ret) {
            try lowerStmt(ctx, stmt, tail_here);
            return true;
        }
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
///     r = r + 100      -- unreachable
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

/// True when `expr` is known to produce a `str` (a `const char*`), so `#expr`
/// can lower to a `strlen` call rather than a dynamic length probe.
fn exprIsStr(ctx: *LowerCtx, expr: *const ast.Expr) bool {
    if (applicationResultIs(ctx, expr, .str)) return true;
    return switch (expr.*) {
        .string_lit => true,
        // `..` ALWAYS produces text, including where one side is a number —
        // which is the shape `"{a} {b}"` desugars to. Requiring both sides to
        // be str was what made every interpolation of an integer answer "not a
        // string" and take the whole enclosing function to the C backend. At
        // least one side must still be a str: two integers concatenated is a
        // shape this pass has never lowered, and claiming it here would let
        // `lowerConcat` produce text where the answer was never checked.
        .binop => |bb| bb.op == .concat and
            concatOperandOk(ctx, bb.lhs) and concatOperandOk(ctx, bb.rhs) and
            (exprIsStr(ctx, bb.lhs) or exprIsStr(ctx, bb.rhs)),
        // Two producers of str, one arm. A producer the type tracker does not
        // know about breaks every consumer downstream, so both belong here:
        //   * a call to a function declared `: str` — without it,
        //     `m = mk(...)` then `#m` bails because the local never entered
        //     str_slots;
        //   * `string.char(n)` — without it the very next `string.byte(s, 1)`
        //     does not recognize its own argument and falls through to an
        //     undefined `string_byte` symbol.
        .call => |c| switch (c.func.*) {
            .name => |n| functionResultIs(ctx, n.ident, .str),
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
            const slot = ctx.locals.get(n.ident) orelse
                break :blk ctx.module_consts.strs.contains(n.ident);
            break :blk ctx.str_slots.contains(slot);
        },
        // `Kind.owner` where the descriptor field holds a string literal — the
        // qualified spelling of the same module-level constant.
        .field => |f| blk: {
            if (f.obj.* != .name) break :blk false;
            var buf: [512]u8 = undefined;
            const key = std.fmt.bufPrint(&buf, "{s}.{s}", .{ f.obj.name.ident, f.field }) catch break :blk false;
            break :blk ctx.module_consts.strs.contains(key);
        },
        // The expression-if produces text only when BOTH arms do. One str arm
        // and one integer arm is a slot whose type depends on the branch taken,
        // which no consumer downstream can read correctly.
        .if_expr => |ie| exprIsStr(ctx, ie.then_expr) and exprIsStr(ctx, ie.else_expr),
        else => false,
    };
}

fn lowerAssignTarget(ctx: *LowerCtx, name: []const u8, value: *const ast.Expr) Error!void {
    // `Alias = req "std.compiler.token"` binds a module at compile time; the
    // alias exists only so `Alias.CONST` can fold and `Alias.fn` can resolve to
    // an extern symbol. There is nothing to store at runtime, and lowering it as
    // an ordinary call pushed the whole program outside the direct subset.
    if (isReqCall(value)) return;
    if (value.* == .call) {
        if (ctx.applications.get(value)) |application| {
            if (recordForDescriptor(ctx.records, application.descriptor)) |record| {
                try lowerCheckedRecordCallAssign(ctx, name, application, record);
                return;
            }
        }
    }
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
        // Both directions. A slot REASSIGNED from a bool to an integer is no
        // longer a bool, and leaving the mark set would refuse a legal
        // interpolation for the rest of the function.
        if (exprIsBoolish(ctx, value))
            try ctx.bool_slots.put(ctx.alloc, slot, {})
        else
            _ = ctx.bool_slots.remove(slot);
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
    if (exprIsBoolish(ctx, value)) try ctx.bool_slots.put(ctx.alloc, slot, {});
    if (intLiteralStep(value)) |n| {
        const gop = try ctx.const_ints.getOrPut(ctx.alloc, name);
        if (!gop.found_existing) gop.key_ptr.* = try ctx.alloc.dupe(u8, name);
        gop.value_ptr.* = n;
    }
    try ctx.emit(.{ .op = .store_local, .result = slot, .lhs = v, .ty = store_ty });
}

fn recordForDescriptor(
    records: []const dnir.RecordDesc,
    descriptor: types.ResolvedType,
) ?dnir.RecordDesc {
    if (descriptor == .@"struct") {
        for (records) |record| {
            if (std.mem.eql(u8, record.name, descriptor.@"struct".name) and
                checkedRecordResultSupported(record)) return record;
        }
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
            const field_kind: ?dnir.FieldKind = switch (field.typ) {
                .str => .str,
                .f64 => .f64,
                .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .bool => .i64,
                else => null,
            };
            if (field_kind == null or field_kind.? != kind) {
                matches = false;
                break;
            }
        }
        if (matches and checkedRecordResultSupported(record)) return record;
    }
    return null;
}

fn checkedRecordResultSupported(record: dnir.RecordDesc) bool {
    for (record.kinds) |kind| {
        if (kind == .f64) return false;
    }
    return true;
}

fn lowerCheckedRecordCallAssign(
    ctx: *LowerCtx,
    name: []const u8,
    application: *const CheckedApplication,
    record: dnir.RecordDesc,
) Error!void {
    const relation = ctx.graph.get(application.relation) orelse return bail(@src());
    const callee = relation.name orelse return bailWith(@src(), "application-link-symbol");
    var operand_storage: [8]CheckedScalarOperand = undefined;
    const operands = try checkedScalarOperands(ctx, application, &operand_storage);
    var values: [8]dnir.Value = undefined;
    const floating = try evaluateCheckedScalarOperands(ctx, operands, &values);
    const realization_start: u32 = @intCast(ctx.instrs.items.len);
    try stageCheckedScalarOperands(ctx, values[0..operands.len], floating);
    try ctx.emit(.{
        .op = .call_direct,
        .relation = application.relation_identity,
        .application = application.application_identity,
        .value = application.value_identity,
        .subject = application.subject_identity,
        .realization_start = realization_start,
        .callee = callee,
        .record = record.name,
        .field = name,
        .ty = application.descriptor,
    });
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

/// gap[063] — `abort()` when a dynamic index leaves a register-exploded table's
/// range, instead of silently doing nothing.
///
/// A positional table lowered to registers has a FIXED capacity; a Duo table
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
fn emitIndexBoundsTrap(ctx: *LowerCtx, idx_slot: u32, len: i64) Error!void {
    try ensureExtern(ctx, "os", "abort", "abort");

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
    try ctx.emit(.{ .op = .call_extern, .callee = "abort" });
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
    try emitIndexBoundsTrap(ctx, idx_slot, len);
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
    const len_slot = ctx.locals.get(len_key) orelse return bail(@src());
    const len = ctx.table_lens.get(len_slot) orelse return bail(@src());
    if (len == 0 or len > 32) return bail(@src());

    const idx_slot = ctx.freshTemp();
    try ctx.emit(.{ .op = .store_local, .result = idx_slot, .lhs = try lowerExpr(ctx, key_expr), .ty = .any });
    try emitIndexBoundsTrap(ctx, idx_slot, len);

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
    if (table.* != .table) return bail(@src());
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
fn lowerRecordLiteralFields(ctx: *LowerCtx, prefix: []const u8, table: *const ast.Expr) Error!void {
    if (table.* != .table) return bail(@src());
    for (table.table.fields) |fld| {
        const nf = switch (fld) {
            .named => |n| n,
            else => return bail(@src()),
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
        }
        const v = try lowerExpr(ctx, nf.val);
        const fslot = ctx.freshTemp();
        try ctx.locals.put(ctx.alloc, fk, fslot);
        const store_ty: RT = if (exprIsF64(ctx, nf.val)) .f64 else .any;
        if (store_ty == .f64) try ctx.f64_slots.put(ctx.alloc, fslot, {});
        if (exprIsStr(ctx, nf.val)) try ctx.str_slots.put(ctx.alloc, fslot, {});
        try ctx.emit(.{ .op = .store_local, .result = fslot, .lhs = v, .ty = store_ty });
    }
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
    const rec_name = ctx.ret_record orelse return bail(@src());
    const rec = findRecordName(ctx.records, .{ .named = rec_name }) orelse return bail(@src());
    const count: u32 = @intCast(rec.fields.len);
    if (count == 0 or count > max_record_fields) return bail(@src());

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
            const slot = ctx.locals.get(key) orelse return bailWith(@src(), fname);
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
    if (table.* != .table) return bail(@src());

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
            else => return bail(@src()),
        };
        const idx = fieldIndexIn(rec, nf.key) orelse return bailWith(@src(), nf.key);
        // A field written twice would leave the earlier expression's side
        // effects in the stream with no home; a field written once is the
        // whole contract here.
        if (seen[idx]) return bailWith(@src(), nf.key);
        vals[idx] = try lowerExpr(ctx, nf.val);
        seen[idx] = true;
    }
    // A partially-written buffer is the exact failure this convention has to
    // rule out: the caller reads all `count` slots either way, so an omitted
    // field is caller-visible garbage rather than a missing value.
    for (seen, 0..) |s, i| {
        if (!s) return bailWith(@src(), rec.fields[i]);
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

fn fieldIndexIn(rec: dnir.RecordDesc, name: []const u8) ?usize {
    for (rec.fields, 0..) |f, i| {
        if (std.mem.eql(u8, f, name)) return i;
    }
    return null;
}

fn lowerExpr(ctx: *LowerCtx, expr: *const ast.Expr) Error!dnir.Value {
    return lowerExprCons(ctx, expr, .single);
}

fn lowerExprCons(
    ctx: *LowerCtx,
    expr: *const Expr,
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
                if (ctx.module_consts.ints.get(n.ident)) |mv| break :blk dnir.Value{ .i64 = mv };
                if (ctx.module_consts.strs.get(n.ident)) |sv| break :blk dnir.Value{ .str = sv };
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
        .method_call => try lowerSubjectCall(ctx, expr, consumption),
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

fn applicationResultIs(
    ctx: *const LowerCtx,
    expr: *const Expr,
    expected: std.meta.Tag(types.ResolvedType),
) bool {
    const descriptor = applicationDescriptor(ctx, expr) orelse return false;
    return std.meta.activeTag(descriptor) == expected;
}

fn applicationDescriptor(ctx: *const LowerCtx, expr: *const Expr) ?types.ResolvedType {
    if (ctx.applications.get(expr)) |application| return application.descriptor;
    return ctx.graph.applicationDescriptorForExpr(expr);
}

const CheckedScalarOperand = struct {
    expression: *Expr,
    descriptor: types.ResolvedType,
};

fn checkedScalarOperand(
    ctx: *const LowerCtx,
    value_id: semantic_graph.NodeId,
) Error!CheckedScalarOperand {
    const value = ctx.graph.get(value_id) orelse return bail(@src());
    const descriptor = value.descriptor orelse
        return bailWith(@src(), "application-operand-descriptor");
    switch (descriptor) {
        .i32, .i64, .bool, .str, .f64 => {},
        else => return bailWith(@src(), "application-operand-abi"),
    }
    const raw = value.ast_ref orelse return bailWith(@src(), "application-operand-provenance");
    return .{
        .expression = @ptrCast(@alignCast(raw)),
        .descriptor = descriptor,
    };
}

fn checkedScalarResult(descriptor: types.ResolvedType) Error!void {
    switch (descriptor) {
        .i32, .i64, .bool, .str, .f64, .void => {},
        else => return bailWith(@src(), "application-result-abi"),
    }
}

/// Project the semantic subject, when present, followed by position-ordered
/// arguments. Subject absence stays absence; it is not reconstructed as
/// argument zero for operation-first source faces.
fn checkedScalarOperands(
    ctx: *LowerCtx,
    application: *const CheckedApplication,
    storage: *[8]CheckedScalarOperand,
) Error![]const CheckedScalarOperand {
    var count: usize = 0;
    if (application.subject) |subject| {
        storage[count] = try checkedScalarOperand(ctx, subject);
        count += 1;
    }
    for (application.arguments) |argument| {
        if (count >= storage.len) return bailWith(@src(), "application-argument-pack");
        storage[count] = try checkedScalarOperand(ctx, argument);
        count += 1;
    }
    return storage[0..count];
}

fn evaluateCheckedScalarOperands(
    ctx: *LowerCtx,
    operands: []const CheckedScalarOperand,
    values: *[8]dnir.Value,
) Error!bool {
    var fp_count: usize = 0;
    for (operands, 0..) |operand, i| {
        values[i] = try lowerExprCons(ctx, operand.expression, .single);
        if (operand.descriptor == .f64) fp_count += 1;
    }
    if (fp_count != 0 and fp_count != operands.len) {
        return bailWith(@src(), "application-operand-abi");
    }
    return fp_count != 0;
}

fn stageCheckedScalarOperands(
    ctx: *LowerCtx,
    values: []const dnir.Value,
    floating: bool,
) Error!void {
    if (floating) {
        for (values, 0..) |value, i| {
            try ctx.emit(.{ .op = .fp_mov_arg, .result = @intCast(i), .lhs = value });
        }
        return;
    }
    for (values, 0..) |value, i| {
        try ctx.emit(.{ .op = .mov_arg, .result = @intCast(i), .lhs = value });
    }
}

/// Realize one checked scalar application. Source call orientation has already
/// disappeared: relation, subject role, ordered operands, result and occurrence
/// all come from the graph. The relation's name is retained only as the current
/// physical link-symbol projection and is validated against the target
/// callable identity before machine emission.
fn lowerCheckedScalarCall(
    ctx: *LowerCtx,
    application: *const CheckedApplication,
    consumption: types.ReturnConsumption,
) Error!dnir.Value {
    const relation = ctx.graph.get(application.relation) orelse return bail(@src());
    const callee = relation.name orelse return bailWith(@src(), "application-link-symbol");
    try checkedScalarResult(application.descriptor);

    var operand_storage: [8]CheckedScalarOperand = undefined;
    const operands = try checkedScalarOperands(ctx, application, &operand_storage);
    var values: [8]dnir.Value = undefined;
    const floating = try evaluateCheckedScalarOperands(ctx, operands, &values);
    const realization_start: u32 = @intCast(ctx.instrs.items.len);
    try stageCheckedScalarOperands(ctx, values[0..operands.len], floating);
    const has_result = consumption != .discard and application.descriptor != .void;
    const result = if (has_result) ctx.freshTemp() else null;
    try ctx.emit(.{
        .op = .call_direct,
        .relation = application.relation_identity,
        .application = application.application_identity,
        .value = application.value_identity,
        .subject = application.subject_identity,
        .realization_start = realization_start,
        .result = result,
        .callee = callee,
        .ty = application.descriptor,
    });
    return if (result) |temp| .{ .temp = temp } else .void;
}

/// Lower the canonical subject face from the relation identity selected by
/// semantic analysis. The exact source expression remains the lookup key, so
/// realization never recreates a call and never resolves its spelling again.
fn lowerSubjectCall(
    ctx: *LowerCtx,
    expr: *const Expr,
    consumption: types.ReturnConsumption,
) Error!dnir.Value {
    if (ctx.applications.get(expr)) |application| {
        if (application.subject == null) return bailWith(@src(), "application-subject");
        return lowerCheckedScalarCall(ctx, application, consumption);
    }

    // String descriptor primitives are bootstrap lowering rules, not declared
    // ordinary relations yet. Preserve their current realization until the
    // standard vocabulary owns those identities.
    if (expr.* == .method_call and exprIsStr(ctx, expr.method_call.obj)) {
        return lowerCall(ctx, try faceAsCall(ctx, expr), consumption);
    }

    return bailWith(@src(), "application-identity");
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
    // taking it over here regressed Pass 11 WP-04. Refusing keeps that fallback.
    if (exprTouchesF64(ctx, lhs) or exprTouchesF64(ctx, rhs)) return bail(@src());

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
        exprTouchesF64(ctx, ie.else_expr)) return bailWith(@src(), "if-expr-f64");

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
        if (p.* == .string_lit) {
            try literal.appendSlice(ctx.alloc, p.string_lit.val);
            // A `%` in the program's own text is TEXT. Left alone it reads the
            // following byte as a conversion and prints an argument that was
            // never passed — a wrong answer produced by a correct-looking
            // literal.
            for (p.string_lit.val) |ch| {
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
/// `snprintf(nil, 0, fmt, …)` is the measurement — it writes nothing and
/// answers the length the same format with the same arguments will produce, so
/// the buffer cannot be the wrong size for the fill that follows.
fn lowerConcatChain(ctx: *LowerCtx, lhs: *const ast.Expr, rhs: *const ast.Expr) Error!dnir.Value {
    var parts: std.ArrayListUnmanaged(*const ast.Expr) = .empty;
    defer parts.deinit(ctx.alloc);
    try flattenConcat(ctx.alloc, lhs, &parts);
    try flattenConcat(ctx.alloc, rhs, &parts);

    const plan = (try planConcat(ctx, parts.items, false)) orelse return bailWith(@src(), "concat");
    // Every part was a literal, so the chain IS its own answer.
    if (plan.count == 0) return .{ .str = plan.literal };

    // Lower each hole ONCE. The values are staged twice — once to measure, once
    // to fill — and re-lowering would evaluate the operand twice.
    var vals: [max_concat_holes]dnir.Value = undefined;
    for (plan.holes[0..plan.count], 0..) |h, i| vals[i] = try lowerExpr(ctx, h);

    try ensureExtern(ctx, "mem", "alloc", "malloc");
    try ensureExtern(ctx, "string", "format", "snprintf");

    try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = .{ .i64 = 0 } });
    try ctx.emit(.{ .op = .mov_arg, .result = 1, .lhs = .{ .i64 = 0 } });
    try ctx.emit(.{ .op = .mov_arg, .result = 2, .lhs = .{ .str = plan.fmt } });
    try stageConcatHoles(ctx, vals[0..plan.count]);
    const wide = ctx.freshTemp();
    try ctx.emit(.{ .op = .call_extern, .result = wide, .callee = "snprintf" });

    // snprintf answers an `int`, so only w0 is defined; the upper half of x0 is
    // whatever the callee left there. Sign-extending garbage into a malloc size
    // is not a hazard worth leaving to the platform's habits.
    const len = ctx.freshTemp();
    try ctx.emit(.{ .op = .binop, .result = len, .binop = .band, .lhs = .{ .temp = wide }, .rhs = .{ .i64 = 0xFFFFFFFF } });
    const total = ctx.freshTemp();
    try ctx.emit(.{ .op = .binop, .result = total, .binop = .add, .lhs = .{ .temp = len }, .rhs = .{ .i64 = 1 } });
    const buf = ctx.freshTemp();
    try ctx.emit(.{ .op = .call_extern, .result = buf, .callee = "malloc", .lhs = .{ .temp = total } });

    try ctx.emit(.{ .op = .mov_arg, .result = 0, .lhs = .{ .temp = buf } });
    try ctx.emit(.{ .op = .mov_arg, .result = 1, .lhs = .{ .temp = total } });
    try ctx.emit(.{ .op = .mov_arg, .result = 2, .lhs = .{ .str = plan.fmt } });
    try stageConcatHoles(ctx, vals[0..plan.count]);
    try ctx.emit(.{ .op = .call_extern, .callee = "snprintf" });
    return .{ .temp = buf };
}

fn lowerBinop(ctx: *LowerCtx, op: ast.BinOp, lhs: *const ast.Expr, rhs: *const ast.Expr) Error!dnir.Value {
    if (op == .concat and concatOperandOk(ctx, lhs) and concatOperandOk(ctx, rhs) and
        (exprIsStr(ctx, lhs) or exprIsStr(ctx, rhs)))
    {
        return try lowerConcatChain(ctx, lhs, rhs);
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
    if (applicationDescriptor(ctx, expr)) |descriptor| return descriptor.is_integer();
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
        else => false,
    };
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

fn lowerCall(ctx: *LowerCtx, expr: *const ast.Expr, consumption: types.ReturnConsumption) Error!dnir.Value {
    if (expr.* != .call) return bail(@src());
    if (ctx.applications.get(expr)) |application| {
        return lowerCheckedScalarCall(ctx, application, consumption);
    }
    const c = expr.call;
    const discard = consumption == .discard;
    if (try lowerToStr(ctx, c)) |v| return v;
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
                if (ctx.req.exportSymbolByPath(ctx.alloc, pbuf.items, f.field)) |sym| {
                    try ensureExtern(ctx, pbuf.items, f.field, sym);
                    const arg0 = try scalarCallLhs(ctx, c.args, null);
                    if (discard) {
                        try ctx.emit(.{ .op = .call_direct, .callee = sym, .lhs = arg0 });
                        return .void;
                    }
                    const t = ctx.freshTemp();
                    try ctx.emit(.{ .op = .call_direct, .result = t, .callee = sym, .lhs = arg0 });
                    return .{ .temp = t };
                }
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
                if (std.mem.eql(u8, f.field, "read_i64") and c.args.len == 2) {
                    const base = try lowerExpr(ctx, c.args[0]);
                    const off = try lowerExpr(ctx, c.args[1]);
                    const idx = ctx.freshTemp();
                    try ctx.emit(.{ .op = .binop, .result = idx, .binop = .div, .lhs = off, .rhs = .{ .i64 = 8 } });
                    const t = ctx.freshTemp();
                    try ctx.emit(.{ .op = .load_index, .result = t, .ty = .i64, .lhs = base, .rhs = .{ .temp = idx } });
                    return .{ .temp = t };
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
                const arg0 = try scalarCallLhs(ctx, c.args, null);
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
fn lowerPrintFormat(ctx: *LowerCtx, arg: *const ast.Expr) Error!?dnir.Value {
    if (arg.* != .binop or arg.binop.op != .concat) return null;

    var parts: std.ArrayListUnmanaged(*const ast.Expr) = .empty;
    defer parts.deinit(ctx.alloc);
    try flattenConcat(ctx.alloc, arg, &parts);

    // `print` ends a line. `print_value` gets that from `puts`; here it is one
    // more byte of format.
    const plan = (try planConcat(ctx, parts.items, true)) orelse return null;

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
    if (args.len != 1) return bail(@src());
    const arg = args[0];
    if (try lowerPrintFormat(ctx, arg)) |v| return v;
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
        if (ctx.module_consts.ints.get(mk)) |mv| return .{ .i64 = mv };
        if (ctx.module_consts.strs.get(mk)) |sv| return .{ .str = sv };
        if (ctx.req.constant(fld.obj.name.ident, fld.field)) |val| {
            const t = ctx.freshTemp();
            try ctx.emit(.{ .op = .const_req, .result = t, .req_alias = fld.obj.name.ident, .field = fld.field, .lhs = .{ .i64 = val } });
            return .{ .temp = t };
        }
        const key = try std.fmt.allocPrint(ctx.alloc, "{s}.{s}", .{ fld.obj.name.ident, fld.field });
        defer ctx.alloc.free(key);
        if (ctx.locals.get(key)) |slot| return .{ .local = slot };
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
        var path: std.ArrayList(u8) = .empty;
        defer path.deinit(ctx.alloc);
        if (try flattenNames(ctx.alloc, expr, &path)) {
            if (ctx.locals.get(path.items)) |slot| {
                if (ctx.f64_slots.contains(slot)) {
                    const ft = ctx.freshTemp();
                    try ctx.emit(.{ .op = .load_local, .result = ft, .lhs = .{ .local = slot }, .ty = .f64 });
                    return .{ .temp = ft };
                }
                return .{ .local = slot };
            }
        }
        return bail(@src());
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

test "dnir_lower: to(str)(n) stages the value as a variadic tail argument" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    s = to(str)(42)
        \\    return #s
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "to_str.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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

test "dnir_lower: to(str) declines a non-integer argument rather than mis-lowering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main(): i64
        \\    x: f64 = 1.5
        \\    s = to(str)(x)
        \\    return #s
        \\end
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "to_str_f64.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    // `"%lld"` is a constant the emitter assumes; an f64 there printed the
    // operand's ADDRESS. The whole program leaves the subset instead.
    try std.testing.expectError(error.UnsupportedConstruct, lowerModule(alloc, &mod));
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
    try std.testing.expect(m_graph.functions[0].semantic_identity != null);
}

test "dnir_lower: call result class comes from graph descriptor" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\measure(): f64
        \\    1.5
        \\count(): i64
        \\    1
        \\label(): str
        \\    "ok"
        \\length(): i64
        \\    #label()
        \\floating(): f64
        \\    measure()
        \\integer(): i64
        \\    count()
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "result_query.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
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
            if (ins.op == .call_extern and std.mem.eql(u8, ins.callee, "strlen")) saw_length = true;
        }
    }
    try std.testing.expect(saw_float);
    try std.testing.expect(saw_integer);
    try std.testing.expect(saw_string);
    try std.testing.expect(saw_length);
}

test "dnir_lower: checked subject call retains semantic identities" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const Sema = @import("sema.zig").Sema;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\read: i64 = (subject: i64)
        \\    subject
        \\main: i64 = ()
        \\    42:read()
    ;
    var lex = Lexer.init(src, "application.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&mod);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&mod, &checked, "application.duo");

    var application_id: ?semantic_graph.NodeId = null;
    for (graph.nodes.items, 0..) |node, i| {
        if (node.kind != .call) continue;
        const id = semantic_graph.NodeId{ .index = @intCast(i) };
        if (graph.applicationRelation(id) != null) application_id = id;
    }
    const application = application_id orelse return error.TestExpectedEqual;
    const relation = graph.applicationRelation(application) orelse return error.TestExpectedEqual;
    const value = graph.applicationResult(application) orelse return error.TestExpectedEqual;
    var subject: ?semantic_graph.NodeId = null;
    for (graph.edges.items) |edge| {
        if (edge.from.index != application.index or edge.kind != .subject) continue;
        subject = edge.to;
    }
    const application_identity = try semanticReference(&graph, application);
    const relation_identity = try semanticReference(&graph, relation);
    const value_identity = try semanticReference(&graph, value);
    const subject_identity = try semanticReference(&graph, subject orelse return error.TestExpectedEqual);

    const module = try lowerModuleWithGraph(alloc, &mod, &graph);
    var found = false;
    for (module.functions) |function| {
        for (function.blocks[0].instrs) |instruction| {
            if (instruction.op != .call_direct or !std.mem.eql(u8, instruction.callee, "read")) continue;
            found = true;
            try std.testing.expect(relation_identity.eql(instruction.relation.?));
            try std.testing.expect(application_identity.eql(instruction.application.?));
            try std.testing.expect(value_identity.eql(instruction.value.?));
            try std.testing.expect(subject_identity.eql(instruction.subject.?));
            try std.testing.expect(instruction.realization_start != null);
        }
    }
    try std.testing.expect(found);
}

test "dnir_lower: applications share relation without sharing occurrence identity" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const Sema = @import("sema.zig").Sema;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\read: i64 = (subject: i64)
        \\    subject
        \\main: i64 = ()
        \\    41:read()
        \\    42:read()
    ;
    var lex = Lexer.init(src, "application-occurrence.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&mod);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&mod, &checked, "application-occurrence.duo");

    const module = try lowerModuleWithGraph(alloc, &mod, &graph);
    var relations: [2]dnir.SemanticRef = undefined;
    var applications: [2]dnir.SemanticRef = undefined;
    var values: [2]dnir.SemanticRef = undefined;
    var subjects: [2]dnir.SemanticRef = undefined;
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
    try std.testing.expect(relations[0].eql(relations[1]));
    try std.testing.expect(!applications[0].eql(applications[1]));
    try std.testing.expect(!values[0].eql(values[1]));
    try std.testing.expect(!subjects[0].eql(subjects[1]));
}

test "dnir_lower: checked ordinary calls consume graph identity" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const Sema = @import("sema.zig").Sema;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\observe: i64 = (value: i64)
        \\    value
        \\main: i64 = ()
        \\    observe(41)
        \\    observe(42)
    ;
    var lexer = Lexer.init(source, "ordinary-application.duo");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "ordinary-application.duo");

    const module = try lowerModuleWithGraph(alloc, &ast_module, &graph);
    var relation: ?dnir.SemanticRef = null;
    var applications: [2]dnir.SemanticRef = undefined;
    var values: [2]dnir.SemanticRef = undefined;
    var count: usize = 0;
    for (module.functions) |function| {
        for (function.blocks[0].instrs) |instruction| {
            if (instruction.application == null) continue;
            if (count >= applications.len) return error.TestExpectedEqual;
            if (relation) |first| {
                try std.testing.expect(first.eql(instruction.relation.?));
            } else {
                relation = instruction.relation.?;
            }
            applications[count] = instruction.application.?;
            values[count] = instruction.value.?;
            try std.testing.expectEqual(@as(?dnir.SemanticRef, null), instruction.subject);
            try std.testing.expectEqual(types.ResolvedType.i64, instruction.ty);
            count += 1;
        }
    }
    try std.testing.expectEqual(applications.len, count);
    try std.testing.expect(!applications[0].eql(applications[1]));
    try std.testing.expect(!values[0].eql(values[1]));
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
    var lexer = Lexer.init(source, "ordinary-f64-application.duo");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "ordinary-f64-application.duo");

    const module = try lowerModuleWithGraph(alloc, &ast_module, &graph);
    var fp_moves: usize = 0;
    var call_index: ?u32 = null;
    for (module.functions) |function| {
        var instruction_index: u32 = 0;
        for (function.blocks[0].instrs) |instruction| {
            if (instruction.op == .fp_mov_arg) fp_moves += 1;
            if (instruction.application != null) {
                call_index = instruction_index;
                try std.testing.expectEqual(types.ResolvedType.f64, instruction.ty);
                try std.testing.expectEqual(@as(?dnir.SemanticRef, null), instruction.subject);
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
    var lex = @import("lexer.zig").Lexer.init(src, "bool_result_query.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();

    try std.testing.expectError(error.UnsupportedConstruct, lowerModule(alloc, &mod));
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
        try std.testing.expect(f.semantic_identity != null);
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
    var lex = @import("lexer.zig").Lexer.init(src, "retorder.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
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

test "dnir_lower: a nine-field record return is eligible, a nine-field param is not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const wide = "big: @{ a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64, i: i64 }\n";
    const lit = "{ a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7, h = 8, i = 9 }";

    // Nine fields RETURNED: the x8 indirect-result convention covers it.
    {
        const src = wide ++ "mk(): big\n    return " ++ lit ++ "\nend\nmain(): i64\n    0\nend\n";
        var lex = @import("lexer.zig").Lexer.init(src, "wideret.duo");
        var parser = @import("parser.zig").Parser.init(&lex, alloc);
        parser.duo_mode = true;
        const mod = try parser.parse_module();
        const m = try lowerModule(alloc, &mod);
        try std.testing.expectEqual(@as(usize, 2), m.functions.len);
    }

    // Nine fields PASSED: still one field per argument register, and there is
    // no ninth. Refusing beats exploding past x7 into caller garbage.
    {
        const src = wide ++ "take(v: big): i64\n    return v.a\nend\nmain(): i64\n    0\nend\n";
        var lex = @import("lexer.zig").Lexer.init(src, "wideparam.duo");
        var parser = @import("parser.zig").Parser.init(&lex, alloc);
        parser.duo_mode = true;
        const mod = try parser.parse_module();
        try std.testing.expectError(error.UnsupportedConstruct, lowerModule(alloc, &mod));
    }
}
