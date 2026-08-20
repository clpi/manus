#!/usr/bin/env python3
from pathlib import Path
text = Path("/tmp/dnir_clean.zig").read_text()
insert_helpers = r'''
fn siblingModulePath(
    alloc: std.mem.Allocator,
    from_file: []const u8,
    alias: []const u8,
) Error!?[]const u8 {
    const dir = std.fs.path.dirname(from_file) orelse return null;
    return try std.fmt.allocPrint(alloc, "{s}{c}{s}.id", .{ dir, std.fs.path.sep, alias });
}

fn parseSiblingModule(
    alloc: std.mem.Allocator,
    from_file: []const u8,
    alias: []const u8,
) Error!?ast.Module {
    const path = (try siblingModulePath(alloc, from_file, alias)) orelse return null;
    defer alloc.free(path);
    var threaded = std.Io.Threaded.init(alloc, .{});
    const src = std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), threaded.io(), path, alloc, .unlimited) catch return null;
    defer alloc.free(src);
    const facts = @import("lexer_bridge.zig").sourceFacts(path);
    var lex = @import("lexer.zig").Lexer.initFacts(src, path, facts);
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.idol_mode = lex.family == @import("lexer_bridge.zig").family_canon;
    return parser.parse_module() catch null;
}

fn recordNamedIndex(records: []const dnir.RecordDesc, name: []const u8) ?usize {
    for (records, 0..) |record, i| {
        if (std.mem.eql(u8, record.name, name)) return i;
    }
    return null;
}

fn siblingRecordReturnExportName(
    alloc: std.mem.Allocator,
    alias: []const u8,
    fd: *const ast.FuncDecl,
) Error![]const u8 {
    const leaf = if (fd.method and fd.path.len >= 2)
        fd.path[0]
    else
        fd.path[fd.path.len - 1];
    return try std.fmt.allocPrint(alloc, "{s}.{s}", .{ alias, leaf });
}

fn mergeForeignModuleRecordsForFields(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    compiling_path: []const u8,
    records: *std.ArrayList(dnir.RecordDesc),
) Error!void {
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var it = seen.keyIterator();
        while (it.next()) |key| alloc.free(key.*);
        seen.deinit(alloc);
    }
    try blockCollectModuleFieldAliases(alloc, &mod.body, &seen);
    var it = seen.keyIterator();
    while (it.next()) |alias| {
        const sibling = (try parseSiblingModule(alloc, compiling_path, alias.*)) orelse continue;
        var sibling_graph = semantic_graph.SemanticGraph.init(alloc);
        defer sibling_graph.deinit();
        const sibling_path = (try siblingModulePath(alloc, compiling_path, alias.*)) orelse continue;
        defer alloc.free(sibling_path);
        _ = sibling_graph.liftModuleWithCalls(&sibling, sibling_path) catch continue;
        var scratch: std.ArrayList(dnir.RecordDesc) = .empty;
        try collectRecordsFromGraph(alloc, &scratch, &sibling_graph);
        for (scratch.items) |record| {
            if (recordNamedIndex(records.items, record.name)) |idx| {
                if (record.fields.len > records.items[idx].fields.len) {
                    deinitRecord(alloc, records.items[idx]);
                    records.items[idx] = record;
                } else {
                    deinitRecord(alloc, record);
                }
                continue;
            }
            try records.append(alloc, record);
        }
        scratch.deinit(alloc);
    }
}

fn mergeForeignModuleRecordReturns(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    compiling_path: []const u8,
    records: []const dnir.RecordDesc,
    out: *std.StringHashMapUnmanaged([]const u8),
) Error!void {
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var it = seen.keyIterator();
        while (it.next()) |key| alloc.free(key.*);
        seen.deinit(alloc);
    }
    try blockCollectModuleFieldAliases(alloc, &mod.body, &seen);
    var it = seen.keyIterator();
    while (it.next()) |alias| {
        const sibling = (try parseSiblingModule(alloc, compiling_path, alias.*)) orelse continue;
        for (sibling.body.stmts) |*stmt| {
            if (stmt.* != .func_decl) continue;
            const fd = &stmt.func_decl;
            if (!shouldIncludeFuncDecl(fd)) continue;
            const rec = findRecordName(records, fd.func.ret_type) orelse continue;
            const export_name = try siblingRecordReturnExportName(alloc, alias.*, fd);
            defer alloc.free(export_name);
            if (out.contains(export_name)) continue;
            const key = try alloc.dupe(u8, export_name);
            const value = try alloc.dupe(u8, rec.name);
            out.put(alloc, key, value) catch |err| {
                alloc.free(key);
                alloc.free(value);
                return err;
            };
        }
    }
}

fn qualifiedCallExportName(
    alloc: std.mem.Allocator,
    call: ast.Expr,
) Error!?[]const u8 {
    return switch (call) {
        .call => |c| switch (c.func.*) {
            .name => |n| try alloc.dupe(u8, n.ident),
            .field => |f| {
                if (f.obj.* != .name) return null;
                return try std.fmt.allocPrint(alloc, "{s}.{s}", .{ f.obj.name.ident, f.field });
            },
            else => null,
        },
        else => null,
    };
}

'''
text = text.replace('}\n\npub fn lowerModule(alloc: std.mem.Allocator, mod: *const ast.Module) Error!dnir.Module {', '}\n' + insert_helpers + '\npub fn lowerModule(alloc: std.mem.Allocator, mod: *const ast.Module) Error!dnir.Module {', 1)
text = text.replace('    try collectRecordsFromGraph(alloc, &records, graph);\n\n    var relation_edges', '    try collectRecordsFromGraph(alloc, &records, graph);\n    try mergeForeignModuleRecordsForFields(alloc, mod, compiling_path, &records);\n\n    var relation_edges', 1)
text = text.replace('''        func_record_returns.put(alloc, key, value) catch |err| {
            alloc.free(key);
            alloc.free(value);
            return err;
        };
    }

    var skipped: ?[]const u8 = null;''', '''        func_record_returns.put(alloc, key, value) catch |err| {
            alloc.free(key);
            alloc.free(value);
            return err;
        };
    }
    try mergeForeignModuleRecordReturns(alloc, mod, compiling_path, records.items, &func_record_returns);

    var skipped: ?[]const u8 = null;''', 1)
old = '''                if (result_node.descriptor) |result_desc| {
                    if (recordForDescriptor(ctx.records, result_desc)) |record| {
                        try lowerCheckedRecordCallAssign(ctx, name, application, record, value);
                        return;
                    }
                }
                try checkedScalarResult(ctx.diagnostic, descriptor);
            }
        }
    }
    if (!ctx.require_graph_facts and value.* == .call and value.call.func.* == .name) {
        if (ctx.func_record_returns.get(value.call.func.name.ident)) |rec_name| {
            try lowerRecordCallAssign(ctx, name, value.call.func.name.ident, value.call.args, rec_name);
            return;
        }
    }
    if (value.* == .table) {'''
new = '''                if (result_node.descriptor) |result_desc| {
                    if (recordForDescriptor(ctx.records, result_desc)) |record| {
                        try lowerCheckedRecordCallAssign(ctx, name, application, record, value);
                        return;
                    }
                }
                if (try tryAssignRecordCallFromExportMap(ctx, name, value)) return;
                try checkedScalarResult(ctx.diagnostic, descriptor);
            }
            if (try tryAssignRecordCallFromExportMap(ctx, name, value)) return;
        }
    }
    if (try tryAssignRecordCallFromExportMap(ctx, name, value)) return;
    if (value.* == .table) {'''
text = text.replace(old, new, 1)
anchor = '''    try ctx.emit(.{ .op = .init_record, .result = rec_slot, .record = rec_name, .field = name });
}

// ---------------------------------------------------------------------------
// REPRESENTATION IS A DECISION, AND SIZE IS NOT THE FACT THAT DECIDES IT.'''
text = text.replace(anchor, anchor.replace('}\n\n// ---------------------------------------------------------------------------', '''}

fn tryAssignRecordCallFromExportMap(ctx: *LowerCtx, name: []const u8, value: *const ast.Expr) Error!bool {
    if (value.* != .call) return false;
    const callee = try qualifiedCallExportName(ctx.alloc, value.*);
    defer if (callee) |c| ctx.alloc.free(c);
    if (callee) |export_name| {
        if (ctx.func_record_returns.get(export_name)) |rec_name| {
            try lowerRecordCallAssign(ctx, name, export_name, value.call.args, rec_name);
            return true;
        }
    }
    return false;
}

// ---------------------------------------------------------------------------'''), 1)
Path('/tmp/dnir_patched.zig').write_text(text)
print('patched lines', len(text.splitlines()))
