//! Pass 7 — run full codegen pipeline for optimization provenance / explain.
const std = @import("std");
const ast = @import("ast.zig");
const sema = @import("sema.zig");
const codegen = @import("codegen.zig");
const mono = @import("mono.zig");
const arc = @import("arc.zig");
const async_lower = @import("async_lower.zig");
const transform_engine = @import("transform_engine.zig");
const optimization_outcome = @import("optimization_outcome.zig");

pub const EmitError = error{
    MonomorphizationFailed,
    ArcFailed,
    AsyncLowerFailed,
    CodegenFailed,
    NoAllocViolation,
} || std.mem.Allocator.Error || std.Io.Writer.Error;

pub fn runModuleCodegen(
    alloc: std.mem.Allocator,
    io: std.Io,
    mod: *ast.Module,
    sem: *sema.Sema,
    src_path: []const u8,
    target: []const u8,
    compiler_lib_root: ?[]const u8,
    w: *std.Io.Writer,
) EmitError!void {
    var monomorphizer = mono.Monomorphizer.init(alloc, &sem.type_map);
    defer monomorphizer.deinit();
    monomorphizer.run(mod) catch return error.MonomorphizationFailed;

    var arc_pass = arc.ArcPass.init(alloc, &sem.type_map);
    defer arc_pass.deinit();
    {
        var it = sem.escape_names.iterator();
        while (it.next()) |entry| {
            arc_pass.markEscaping(entry.key_ptr.*) catch {};
        }
    }
    arc_pass.run(mod) catch return error.ArcFailed;

    const is_wasm_target = std.mem.eql(u8, target, "wasm32-wasi");
    async_lower.validateTarget(is_wasm_target, false) catch return error.AsyncLowerFailed;
    var async_pass = async_lower.AsyncLower.init(alloc, &sem.type_map);
    defer async_pass.deinit();
    async_pass.run(mod) catch return error.AsyncLowerFailed;

    var cg = codegen.CodeGen.init(
        alloc,
        io,
        &sem.type_map,
        &sem.module_globals,
        w,
        sem.next_closure_id,
        &sem.table_field_types,
        &sem.concepts,
    );
    cg.table_methods = &sem.table_methods;
    cg.mono = &monomorphizer;
    cg.arc = &arc_pass;
    cg.async_lower = &async_pass;
    cg.src_path = src_path;
    cg.stdlib_root = compiler_lib_root;
    cg.target = target;
    cg.duo_mode = sem.duo_mode;
    cg.foreign_records = &sem.foreign_records;
    cg.foreign_functions = &sem.foreign_functions;
    cg.emit_module(mod) catch |e| switch (e) {
        error.NoAllocViolation => return error.NoAllocViolation,
        else => return error.CodegenFailed,
    };
}

/// Run codegen discarding C output; leaves transform provenance populated when enabled.
pub fn runForProvenance(
    alloc: std.mem.Allocator,
    io: std.Io,
    mod: *ast.Module,
    sem: *sema.Sema,
    src_path: []const u8,
    compiler_lib_root: ?[]const u8,
) EmitError!void {
    transform_engine.setProvenanceEnabled(true);
    optimization_outcome.setSessionBridge(true);
    defer optimization_outcome.setSessionBridge(false);
    defer transform_engine.setProvenanceEnabled(false);
    // LIFO: this fires BEFORE `setProvenanceEnabled(false)` clears the log, so
    // the run's provenance survives for rendering. It runs on the error paths
    // too — a rejected contract is exactly when the log is worth reading.
    defer transform_engine.snapshotProvenance();
    var discard: std.Io.Writer.Allocating = .init(alloc);
    defer discard.deinit();
    try runModuleCodegen(alloc, io, mod, sem, src_path, "native", compiler_lib_root, &discard.writer);
}

test "explain_pipeline: typed module completes codegen for provenance" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\add(a: i64, b: i64): i64
        \\    a + b
        \\end
        \\main(): i64
        \\    add(1, 2)
        \\end
    ;
    var lex = Lexer.init(src, "milestone.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    semantic.duo_mode = true;
    try semantic.check_module(&mod);

    transform_engine.deinitProvenance(alloc);
    defer transform_engine.deinitProvenance(alloc);
    defer optimization_outcome.deinitSession(alloc);
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const io = threaded.io();
    try runForProvenance(alloc, io, &mod, &semantic, "milestone.duo", null);
}
