//! Pass 25 native gate — semantic unification constitution + schema proofs (M0).
const std = @import("std");
const pass25_catalog = @import("pass25_catalog.zig");
const pass25_semantic_category = @import("pass25_semantic_category.zig");
const pass25_lifetime_model = @import("pass25_lifetime_model.zig");
const pass25_projection_model = @import("pass25_projection_model.zig");
const pass25_tail_result_model = @import("pass25_tail_result_model.zig");
const tail_result_demand = @import("tail_result_demand.zig");
const pass23_catalog = @import("pass23_catalog.zig");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;
const ast = @import("ast.zig");

pub const GateError = error{ GateFailed };

pub fn validatePass25Catalog() GateError!void {
    if (!std.mem.eql(u8, pass25_catalog.SCHEMA_VERSION, "pass25-catalog-v0")) return error.GateFailed;
    if (pass25_catalog.workstreams.len != 18) return error.GateFailed;
    if (pass25_catalog.rejected_syntax.len != 10) return error.GateFailed;
    if (pass25_catalog.rejected_alternatives.len != 6) return error.GateFailed;
    if (pass25_catalog.completion_gates.len != 16) return error.GateFailed;
    if (pass25_catalog.guiding_rules.len != 10) return error.GateFailed;
}

pub fn proveGuidingRulesRegistry() GateError!void {
    if (pass25_catalog.guiding_rules[0].id[0] != 'P') return error.GateFailed;
    if (std.mem.indexOf(u8, pass25_catalog.guiding_rules[0].question, "ordinary function") == null) return error.GateFailed;
    if (std.mem.indexOf(u8, pass25_catalog.guiding_rules[9].question, "semantic density") == null) return error.GateFailed;
}

pub fn proveRejectedSyntaxRegistry() GateError!void {
    var saw_bracket: bool = false;
    var saw_lifetime: bool = false;
    var saw_silent_heap: bool = false;
    var saw_backward: bool = false;
    for (pass25_catalog.rejected_syntax) |r| {
        if (std.mem.eql(u8, r.id, "P25-S01")) saw_bracket = true;
        if (std.mem.eql(u8, r.id, "P25-S05")) saw_lifetime = true;
        if (std.mem.eql(u8, r.id, "P25-S09")) saw_silent_heap = true;
        if (std.mem.eql(u8, r.id, "P25-S11")) saw_backward = true;
        if (std.mem.indexOf(u8, r.pattern, "Slice[") != null and !std.mem.eql(u8, r.id, "P25-S01")) return error.GateFailed;
    }
    if (!saw_bracket or !saw_lifetime or !saw_silent_heap or !saw_backward) return error.GateFailed;
}

pub fn proveSemanticCategorySchema() GateError!void {
    if (!std.mem.eql(u8, pass25_semantic_category.SCHEMA_VERSION, "pass25-semantic-category-v0")) return error.GateFailed;
    if (@intFromEnum(pass25_semantic_category.SemanticCategory.pointer) != 4) return error.GateFailed;
    if (pass25_semantic_category.invariants.len < 5) return error.GateFailed;
}

pub fn proveLifetimeModelSchema() GateError!void {
    if (!std.mem.eql(u8, pass25_lifetime_model.SCHEMA_VERSION, "pass25-lifetime-model-v0")) return error.GateFailed;
    if (pass25_lifetime_model.invariants.len < 4) return error.GateFailed;
    for (pass25_lifetime_model.invariants) |inv| {
        if (std.mem.eql(u8, inv.id, "P25-L03") and std.mem.indexOf(u8, inv.rule, "silent") == null) return error.GateFailed;
    }
}

pub fn proveProjectionModelSchema() GateError!void {
    if (!std.mem.eql(u8, pass25_projection_model.SCHEMA_VERSION, "pass25-projection-model-v0")) return error.GateFailed;
    if (@intFromEnum(pass25_projection_model.BidirectionalLevel.automatic_sync) != 3) return error.GateFailed;
    if (pass25_projection_model.invariants.len < 5) return error.GateFailed;
}

/// Pass 25 aligns with Pass 23 — @return / named returns remain rejected.
pub fn provePass23ReturnAlignment() GateError!void {
    var saw_rejected_return = false;
    for (pass23_catalog.deferred_designs) |d| {
        if (std.mem.eql(u8, d.id, "P23-D02") and std.mem.eql(u8, d.status, "rejected")) saw_rejected_return = true;
    }
    for (pass25_catalog.rejected_syntax) |r| {
        if (std.mem.eql(u8, r.id, "P25-S04") and std.mem.indexOf(u8, r.reason, "P23-D02") != null) saw_rejected_return = true;
    }
    if (!saw_rejected_return) return error.GateFailed;
}

pub fn proveTailResultModelSchema() GateError!void {
    if (!std.mem.eql(u8, pass25_tail_result_model.SCHEMA_VERSION, "pass25-tail-result-model-v0")) return error.GateFailed;
    if (pass25_tail_result_model.invariants.len < 7) return error.GateFailed;
    if (pass25_tail_result_model.rejected_heuristics.len < 6) return error.GateFailed;
    if (@typeInfo(pass25_tail_result_model.TailResultRule).@"enum".field_names.len != 8) return error.GateFailed;
    if (std.mem.indexOf(u8, pass25_tail_result_model.PLAN_PATH, "tail_result_demand") == null) return error.GateFailed;
}

/// P23-D01 superseded — tail-demand replaces naive live-out deferral.
pub fn proveP23D01SupersededByTailDemand() GateError!void {
    for (pass23_catalog.deferred_designs) |d| {
        if (std.mem.eql(u8, d.id, "P23-D01")) {
            if (!std.mem.eql(u8, d.status, "superseded")) return error.GateFailed;
            return;
        }
    }
    return error.GateFailed;
}

/// P25-R07 rejects naive P23-D01 live-out search.
pub fn proveNaiveLiveOutRejected() GateError!void {
    for (pass25_catalog.rejected_alternatives) |r| {
        if (std.mem.eql(u8, r.id, "P25-R07") and std.mem.indexOf(u8, r.proposal, "P23-D01") != null) return;
    }
    return error.GateFailed;
}

/// P25-G15 partial — factorial body parses without trailing `value` read (lineage target for sema).
pub fn proveFactorialBodyParsesWithoutTrailingRead(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\factorial = (n: i64): i64
        \\    value = 1
        \\    for i = 2, n
        \\        value *= i
        \\    end
        \\end
    ;
    const mod = try parseDuoModule(alloc, src, "gate25_factorial.duo");
    const fd = mod.body.stmts[0].func_decl;
    if (fd.func.body.stmts.len < 2) return error.GateFailed;
    if (fd.func.body.tail_expr != null) return error.GateFailed;
    const last = fd.func.body.stmts[fd.func.body.stmts.len - 1];
    if (last != .gen_for and last != .num_for) return error.GateFailed;
}

/// P25-G15 — factorial resolves via tail_loop_carried (not backward local search).
pub fn proveFactorialTailLoopCarried(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\factorial = (n: i64): i64
        \\    value = 1
        \\    for i = 2, n
        \\        value *= i
        \\    end
        \\end
    ;
    const mod = try parseDuoModule(alloc, src, "gate25_factorial_tail.duo");
    const body = mod.body.stmts[0].func_decl.func.body;
    const r = tail_result_demand.blockTailResultWithDemand(
        &body,
        tail_result_demand.demandFromRetType(.{ .named = "i64" }),
    ) orelse return error.GateFailed;
    if (r.rule != .tail_loop_carried) return error.GateFailed;
    if (r.expr.* != .name or !std.mem.eql(u8, r.expr.name.ident, "value")) return error.GateFailed;
}

fn parseDuoModule(alloc: std.mem.Allocator, src: []const u8, file: []const u8) GateError!ast.Module {
    var lex = Lexer.init(src, file);
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    return parser.parse_module() catch return error.GateFailed;
}

/// P25-G16 partial — factorial sema accepts loop-carried tail without trailing read.
pub fn proveFactorialTailDemandSema(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\factorial = (n: i64): i64
        \\    value = 1
        \\    for i = 2, n
        \\        value *= i
        \\    end
        \\end
    ;
    var mod = try parseDuoModule(alloc, src, "gate25_factorial_sema.duo");
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    sem.check_module(&mod) catch return error.GateFailed;
    const fd = mod.body.stmts[0].func_decl;
    if (!fd.func.is_typed) return error.GateFailed;
}

/// P25-G01 partial — descriptor constructor via ordinary call: Bytes = Slice(Point).
pub fn proveDescriptorCallConstructor(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\Point: @{ x: f64, y: f64 }
        \\Slice = (Element: any): any
        \\    Element
        \\end
        \\Bytes = Slice(Point)
    ;
    const mod = try parseDuoModule(alloc, src, "gate25_descriptor.duo");
    if (mod.body.stmts.len != 3) return error.GateFailed;
    if (mod.body.stmts[2] != .assign) return error.GateFailed;
    const val = mod.body.stmts[2].assign.values[0];
    if (val.* != .call) return error.GateFailed;
    if (val.call.args.len != 1) return error.GateFailed;
    if (val.call.func.* != .name or !std.mem.eql(u8, val.call.func.name.ident, "Slice")) return error.GateFailed;
    if (val.call.args[0].* != .name or !std.mem.eql(u8, val.call.args[0].name.ident, "Point")) return error.GateFailed;
}

/// P25-G03 partial — tail assignment return (Pass 25 §5 / Pass 23 G02).
pub fn proveTailAssignmentReturn(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\make = (T, value)
        \\    converted = value
        \\end
    ;
    const mod = try parseDuoModule(alloc, src, "gate25_make.duo");
    const fd = mod.body.stmts[0].func_decl;
    if (fd.func.body.stmts.len != 1) return error.GateFailed;
    if (fd.func.body.tail_expr != null) return error.GateFailed;
    const stmt = fd.func.body.stmts[0];
    if (stmt != .assign and stmt != .local_decl) return error.GateFailed;
}

pub fn validatePass25Gate(alloc: std.mem.Allocator) GateError!void {
    try validatePass25Catalog();
    try proveGuidingRulesRegistry();
    try proveRejectedSyntaxRegistry();
    try proveSemanticCategorySchema();
    try proveLifetimeModelSchema();
    try proveProjectionModelSchema();
    try provePass23ReturnAlignment();
    try proveP23D01SupersededByTailDemand();
    try proveNaiveLiveOutRejected();
    try proveTailResultModelSchema();
    try proveDescriptorCallConstructor(alloc);
    try proveTailAssignmentReturn(alloc);
    try proveFactorialBodyParsesWithoutTrailingRead(alloc);
    try proveFactorialTailLoopCarried(alloc);
    try proveFactorialTailDemandSema(alloc);
}

test "pass25_gate: catalog + schema M0 + descriptor parse proofs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try validatePass25Gate(arena.allocator());
}
