//! Pass 24 native gate — constitution catalog + lua superset P0 + call model P2 proofs.
const std = @import("std");
const pass24_catalog = @import("pass24_catalog.zig");
const pass24_call_model = @import("pass24_call_model.zig");
const pass24_execution_model = @import("pass24_execution_model.zig");
const lua_superset_gate = @import("lua_superset_gate.zig");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const dnir_lower = @import("dnir_lower.zig");
const native_backend = @import("native_backend.zig");
const Sema = @import("sema.zig").Sema;
const builtin = @import("builtin");

pub const GateError = error{ GateFailed };

pub fn validatePass24Catalog() GateError!void {
    if (!std.mem.eql(u8, pass24_catalog.SCHEMA_VERSION, "pass24-catalog-v0")) return error.GateFailed;
    if (pass24_catalog.workstreams.len != 13) return error.GateFailed;
    if (pass24_catalog.ambiguity_fixtures.len != 6) return error.GateFailed;
    if (pass24_catalog.rejected_alternatives.len != 6) return error.GateFailed;
    if (pass24_catalog.completion_gates.len != 15) return error.GateFailed;
}

/// Rejected bare-auto-call must remain documented policy.
pub fn proveRejectedBareAutoCall() GateError!void {
    var found = false;
    for (pass24_catalog.rejected_alternatives) |r| {
        if (std.mem.eql(u8, r.id, "P24-R01")) {
            found = true;
            if (std.mem.indexOf(u8, r.proposal, "a()") == null) return error.GateFailed;
        }
    }
    if (!found) return error.GateFailed;
}

/// Long-bracket ambiguity fixture marked proven.
pub fn proveLongBracketAmbiguityRegistry() GateError!void {
    const fix = pass24_catalog.ambiguity_fixtures[3];
    if (!std.mem.eql(u8, fix.id, "P24-A04")) return error.GateFailed;
    if (!std.mem.eql(u8, fix.status, "proven")) return error.GateFailed;
}

pub fn proveExecutionModelSchema() GateError!void {
    if (!std.mem.eql(u8, pass24_execution_model.SCHEMA_VERSION, "pass24-execution-model-v0")) return error.GateFailed;
    if (pass24_execution_model.invariants.len < 5) return error.GateFailed;
}

/// P24-G07 partial — multi-arg qualified call lowers with mov_arg chain.
pub fn proveMultiArgCallDirect(alloc: std.mem.Allocator) GateError!void {
    const src =
        \\math.add = (a: i64, b: i64): i64
        \\    a + b
        \\end
        \\main(): i64
        \\    math.add(10, 20)
        \\end
    ;
    var lex = Lexer.init(src, "gate24_math_add_call.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = parser.parse_module() catch return error.GateFailed;
    const m = dnir_lower.lowerModule(alloc, &mod) catch return error.GateFailed;
    var mov_args: u32 = 0;
    var saw_call = false;
    for (m.functions) |f| {
        if (!std.mem.eql(u8, f.name, "main")) continue;
        for (f.blocks[0].instrs) |ins| {
            if (ins.op == .mov_arg) mov_args += 1;
            if (ins.op == .call_direct and std.mem.eql(u8, ins.callee, "math.add")) {
                saw_call = true;
                if (ins.lhs != .void) return error.GateFailed;
            }
        }
    }
    if (!saw_call or mov_args != 2) return error.GateFailed;
}

/// P24-G07 partial — AArch64 listing places args in x0/x1 before bl math_add.
pub fn proveMultiArgCallNativeAbi(alloc: std.mem.Allocator) GateError!void {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return;

    const src =
        \\math.add = (a: i64, b: i64): i64
        \\    a + b
        \\end
        \\main(): i64
        \\    math.add(10, 20)
        \\end
    ;
    var lex = Lexer.init(src, "gate24_math_add_native.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = parser.parse_module() catch return error.GateFailed;
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    sem.check_module(&mod) catch return error.GateFailed;

    const listing = native_backend.emitAssembly(alloc, &mod, "native-asm") catch return error.GateFailed;
    defer alloc.free(listing);
    if (std.mem.indexOf(u8, listing, "bl _math_add") == null) return error.GateFailed;
    const main_pos = std.mem.indexOf(u8, listing, "_main:") orelse return error.GateFailed;
    const bl_off = std.mem.indexOf(u8, listing[main_pos..], "bl _math_add") orelse return error.GateFailed;
    const before_bl = listing[main_pos .. main_pos + bl_off];
    if (std.mem.indexOf(u8, before_bl, "mov x0") == null) return error.GateFailed;
    if (std.mem.indexOf(u8, before_bl, "mov x1") == null) return error.GateFailed;
}

/// P24-A02 fixture marked proven in catalog.
pub fn proveAmbiguityA02Registry() GateError!void {
    const fix = pass24_catalog.ambiguity_fixtures[1];
    if (!std.mem.eql(u8, fix.id, "P24-A02")) return error.GateFailed;
    if (!std.mem.eql(u8, fix.status, "proven")) return error.GateFailed;
}

pub fn validatePass24Gate(alloc: std.mem.Allocator) GateError!void {
    try validatePass24Catalog();
    try proveRejectedBareAutoCall();
    try proveLongBracketAmbiguityRegistry();
    try proveAmbiguityA02Registry();
    try proveExecutionModelSchema();
    try pass24_call_model.validateCallModelGate(alloc);
    try proveMultiArgCallDirect(alloc);
    try proveMultiArgCallNativeAbi(alloc);
    try lua_superset_gate.validateLuaSupersetGate();
}

test "pass24_gate: catalog + lua superset P0 + call model P2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try validatePass24Gate(arena.allocator());
}
