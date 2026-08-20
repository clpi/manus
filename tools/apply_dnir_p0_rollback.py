#!/usr/bin/env python3
"""Reapply P0 architectural rollback to src/dnir_lower.zig."""
from pathlib import Path

def main() -> None:
    p = Path(__file__).resolve().parents[1] / "src/dnir_lower.zig"
    text = p.read_text()
    start = text.index("fn mergeAliasModuleConsts(")
    end = text.index("fn qualifiedCallExportName(")
    text = text[:start] + text[end:]
    old = """    const compiling_path = if (graph.module_path) |p|
        if (std.mem.indexOf(u8, p, \"<\") != null) mod.file else p
    else
        mod.file;
    try mergeForeignModuleConstsForFields(alloc, mod, compiling_path, &module_consts);

    var records: std.ArrayList(dnir.RecordDesc) = .empty;
"""
    text = text.replace(old, "    var records: std.ArrayList(dnir.RecordDesc) = .empty;\n", 1)
    text = text.replace("    try mergeForeignModuleRecordsForFields(alloc, mod, compiling_path, &records);\n\n", "", 1)
    text = text.replace("    try mergeForeignModuleRecordReturns(alloc, mod, compiling_path, records.items, &func_record_returns);\n\n", "", 1)
    for b in [
        "    if (shouldLowerAsArrayIndex(ctx, expr)) return false;\n",
        """                if (shouldLowerAsArrayIndex(ctx, target)) {
                    const site = arrayIndexSite(target).?;
                    try lowerIndexAssignTarget(ctx, site.obj, site.key, value);
                    continue;
                }
""",
    ]:
        text = text.replace(b, "", 1)
    text = text.replace(
        """        .call => blk: {
            if (shouldLowerAsArrayIndex(ctx, expr)) {
                const site = arrayIndexSite(expr).?;
                break :blk try lowerPositionalIndexExpr(ctx, expr, site.obj, site.key, consumption);
            }
            break :blk try lowerCall(ctx, expr, consumption);
        },

""",
        "        .call => try lowerCall(ctx, expr, consumption),\n",
        1,
    )
    text = text.replace(
        """        .call => |c| blk: {
            if (arrayIndexSite(expr)) |site| {
                if (site.obj.* == .name and std.mem.eql(u8, site.obj.name.ident, name)) {
                    const here: TableUse = if (constIndexOf(site.key) != null) .const_read else .dyn_read;
                    var u = here;
                    u = worseUse(u, tableUseInExpr(site.key, name));
                    break :blk u;
                }
            }
            var u = tableUseInExpr(c.func, name);
            for (c.args) |a| u = worseUse(u, tableUseInExpr(a, name));
            break :blk u;
        },""",
        """        .call => |c| blk: {
            var u = tableUseInExpr(c.func, name);
            for (c.args) |a| u = worseUse(u, tableUseInExpr(a, name));
            break :blk u;
        },""",
        1,
    )
    old_block = """const ArrayIndexSite = struct {
    obj: *const ast.Expr,
    key: *const ast.Expr,
};

/// Demagix canonicalizes `a[i]` to `a(i)` for fixed positional arrays. Treat
/// that call form as the same index edge on read and assign without converting
/// every post-sema application into a projection.
fn arrayIndexSite(expr: *const ast.Expr) ?ArrayIndexSite {
    return switch (expr.*) {
        .index => |ix| .{ .obj = ix.obj, .key = ix.key },
        .call => |c| blk: {
            if (c.args.len != 1) return null;
            if (c.func.* != .name) return null;
            break :blk .{ .obj = c.func, .key = c.args[0] };
        },
        else => null,
    };
}

fn shouldLowerAsArrayIndex(ctx: *const LowerCtx, expr: *const ast.Expr) bool {
    if (envPlaceKey(ctx, expr) != null) return false;
    const site = arrayIndexSite(expr) orelse return false;
    if (site.obj.* != .name) return false;
    const name = site.obj.name.ident;
    if (argv(site.obj) or env(site.obj)) return false;
    // Demagix registers `a(i)` as a bootstrap application even when `a` is a
    // bound positional table or fixed array — index/store wins over that face.
    if (ctx.locals.contains(name)) return true;
    if (ctx.occurrences.get(expr)) |_| {
        if (ctx.require_graph_facts and ctx.graph.bootstrapApplicationExpr(expr))
            return false;
    }
    return true;
}

"""
    new_block = """const IndexProjectionSite = struct {
    obj: *const ast.Expr,
    key: *const ast.Expr,
};

fn indexProjectionSite(expr: *const ast.Expr) ?IndexProjectionSite {
    return switch (expr.*) {
        .index => |ix| .{ .obj = ix.obj, .key = ix.key },
        else => null,
    };
}

"""
    text = text.replace(old_block, new_block, 1)
    text = text.replace("arrayIndexSite", "indexProjectionSite")
    text = text.replace(
        """/// Keep graph-projected operands that the source call actually passes. The
/// semantic graph may attach nearby bindings (e.g. `st = lexer.save_state(lx)`)
/// to an application argument pack even when they are not call arguments.
fn filterCheckedCallOperands(""",
        """/// @debt GRAPH-ARG-EXACT — DNIR must not recover operands from AST when the
/// graph application pack is wrong. Fix the graph producer so exported arguments
/// match resolved semantic operands exactly; then delete this filter (goal: 0).
fn filterCheckedCallOperands(""",
        1,
    )
    text = text.replace(
        """fn tryAssignRecordCallFromExportMap(ctx: *LowerCtx, name: []const u8, value: *const ast.Expr) Error!bool {
    if (value.* != .call) return false;""",
        """fn tryAssignRecordCallFromExportMap(ctx: *LowerCtx, name: []const u8, value: *const ast.Expr) Error!bool {
    if (ctx.require_graph_facts) return false;
    if (value.* != .call) return false;""",
        1,
    )
    p.write_text(text)
    print(f"dnir P0 rollback applied ({len(text.splitlines())} lines)")

if __name__ == "__main__":
    main()
