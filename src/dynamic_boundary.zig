/// Pass 4 — explicit dynamic-boundary facts and compiler explanations.
///
/// Factual only: states what the compiler knows from types, knowledge lattice,
/// and module/function native eligibility — no invented optimizations.
const std = @import("std");
const types = @import("types.zig");
const semantic_algebra = @import("semantic_algebra.zig");

pub const BoundaryKind = enum {
    box,
    unbox,
    dynamic_call,
    generic_table_lookup,
    runtime_helper,
    lua_thunk,
    return_pack_materialize,
    closure_heap,
};

pub const ExprFacts = struct {
    rt: types.ResolvedType,
    knowledge: semantic_algebra.KnowledgeLevel,
    storage_class: types.StorageClass,
    /// Module qualifies for full native lowering (native_scalar_mode or equivalent).
    module_native: bool,
    /// Current function is in the native_scalar_funcs set.
    func_native: bool,
    /// Type can lower to native C without lua_Value (knowledgeOfType >= native).
    lowers_native: bool,
    /// Module will link the dynamic Lua runtime preamble.
    module_needs_runtime: bool,
};

pub fn explainRepresentation(f: ExprFacts) []const u8 {
    if (f.module_native and f.func_native and f.lowers_native and f.knowledge.dominates(.stable)) {
        if (types.tableStorageClass(f.rt)) |_| {
            return types.explainStorageClass(f.rt);
        }
        return "native C scalar or payload-free enum; no lua_Value on this specialization path";
    }
    if (f.lowers_native and f.knowledge.dominates(.native)) {
        if (types.tableStorageClass(f.rt)) |_| {
            return types.explainStorageClass(f.rt);
        }
        return "native-eligible type; representation follows function/module knowledge gate";
    }
    if (types.tableStorageClass(f.rt)) |_| {
        return types.explainStorageClass(f.rt);
    }
    return "dynamic Lua-compatible representation; may use lua_Value or runtime helpers";
}

pub fn explainBoxed(f: ExprFacts) []const u8 {
    if (f.module_native and f.func_native and f.lowers_native and f.knowledge.dominates(.stable)) {
        return "not boxed on this path; value lowers to native C";
    }
    if (!f.lowers_native) {
        return "type cannot lower to native C; boxed at dynamic boundary for Lua semantics";
    }
    if (f.module_needs_runtime) {
        return "module links dynamic runtime; values cross lua_Value boundary";
    }
    if (!f.func_native) {
        return "function outside native_scalar set; dynamic convention uses lua_Value";
    }
    if (!f.knowledge.dominates(.stable)) {
        return "compiler knowledge below stable; boxing preserves observable Lua semantics";
    }
    return "boxed for dynamic compatibility; further specialization may remove this boundary";
}

pub fn explainNotNative(f: ExprFacts) []const u8 {
    if (f.module_native and f.func_native and f.lowers_native and f.knowledge.dominates(.stable)) {
        return "native lowering applies; no remaining barrier on this expression";
    }
    if (!f.lowers_native) return "type is not native-eligible (aggregate, any, or dynamic table)";
    if (f.module_needs_runtime) return "module requires dynamic runtime components";
    if (!f.func_native) return "function not specialized into native_scalar_funcs";
    if (!f.knowledge.dominates(.stable)) return "expression knowledge below stable specialization threshold";
    return "native path blocked by mixed module mode or unresolved dynamic use";
}

pub fn boundaryKindName(kind: BoundaryKind) []const u8 {
    return switch (kind) {
        .box => "box",
        .unbox => "unbox",
        .dynamic_call => "dynamic_call",
        .generic_table_lookup => "generic_table_lookup",
        .runtime_helper => "runtime_helper",
        .lua_thunk => "lua_thunk",
        .return_pack_materialize => "return_pack_materialize",
        .closure_heap => "closure_heap",
    };
}

test "dynamic_boundary: native Point facts are not boxed" {
    var fields = [_]types.FieldType{
        .{ .name = "x", .typ = .f64 },
        .{ .name = "y", .typ = .f64 },
    };
    const native_table = types.ResolvedType{ .table_type = .{
        .fields = fields[0..],
        .is_sealed = true,
        .is_packed = false,
        .storage_class = .native,
        .align_n = null,
    } };
    const f = ExprFacts{
        .rt = native_table,
        .knowledge = .native,
        .storage_class = .native,
        .module_native = true,
        .func_native = true,
        .lowers_native = true,
        .module_needs_runtime = false,
    };
    try std.testing.expectEqualStrings(
        "not boxed on this path; value lowers to native C",
        explainBoxed(f),
    );
    try std.testing.expect(std.mem.indexOf(u8, explainNotNative(f), "native lowering applies") != null);
}

test "dynamic_boundary: dynamic module explains boxing" {
    const f = ExprFacts{
        .rt = .i64,
        .knowledge = .stable,
        .storage_class = .dynamic,
        .module_native = false,
        .func_native = false,
        .lowers_native = true,
        .module_needs_runtime = true,
    };
    try std.testing.expect(std.mem.indexOf(u8, explainBoxed(f), "dynamic runtime") != null);
}
