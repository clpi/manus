/// Pass 2.5: call rewrite dispatch — registry, codegen, and provenance harness.
const std = @import("std");
const testing = std.testing;
const transform_engine = @import("transform_engine.zig");
const semantic_algebra = @import("semantic_algebra.zig");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;
const CodeGen = @import("codegen.zig").CodeGen;

fn compileDuoSource(alloc: std.mem.Allocator, source: []const u8) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var lex = Lexer.init(source, "call_transform.duo");
    var p = Parser.init(&lex, a);
    p.duo_mode = true;
    var mod = try p.parse_module();
    var s = Sema.init(a);
    s.duo_mode = true;
    try s.check_module(&mod);

    var aw: std.Io.Writer.Allocating = .init(a);
    defer aw.deinit();
    var cg = CodeGen.init(a, undefined, &s.type_map, &s.module_globals, &aw.writer, s.next_closure_id, &s.table_field_types, &s.concepts);
    cg.duo_mode = true;
    try cg.emit_module(&mod);
    return try alloc.dupe(u8, aw.written());
}

fn provenanceContains(name: []const u8) bool {
    for (transform_engine.provenanceEntries()) |e| {
        if (std.mem.eql(u8, e.public_name, name)) return true;
    }
    return false;
}

test "Pass 2.5: all call algebra transforms registered" {
    inline for (@typeInfo(semantic_algebra.CallTransform).@"enum".field_names, @typeInfo(semantic_algebra.CallTransform).@"enum".field_values) |_, value| {
        const op: semantic_algebra.CallTransform = @enumFromInt(value);
        const id = semantic_algebra.callTransformId(op);
        try testing.expect(transform_engine.isCallTransform(id));
        try testing.expect(transform_engine.isRegisteredTransform(id));
        const d = transform_engine.descriptor(id) orelse return error.TestExpectedEqual;
        try testing.expect(d.contract.native_only);
        try testing.expectEqual(@as(usize, 1), d.contract.parity_sites.len);
        try testing.expectEqual(transform_engine.SiteKind.emit_call, d.contract.parity_sites[0]);
    }
}

test "Pass 2.5: call.inline dispatch emits direct native call" {
    const alloc = testing.allocator;
    const source =
        \\fun add(a: i64, b: i64): i64
        \\    a + b
        \\end
        \\x = add(1, 2)
        \\
    ;
    const c_source = try compileDuoSource(alloc, source);
    defer alloc.free(c_source);
    try testing.expect(std.mem.indexOf(u8, c_source, "lua_invoke") == null);
    try testing.expect(std.mem.indexOf(u8, c_source, "add(") != null);
}

test "Pass 2.5: call.inline provenance logged on dispatch" {
    const alloc = testing.allocator;
    transform_engine.deinitProvenance(alloc);
    defer transform_engine.deinitProvenance(alloc);
    transform_engine.setProvenanceEnabled(true);

    const source =
        \\fun add(a: i64, b: i64): i64
        \\    a + b
        \\end
        \\x = add(1, 2)
        \\
    ;
    const c_source = try compileDuoSource(alloc, source);
    defer alloc.free(c_source);
    try testing.expect(provenanceContains("call.inline"));
}

test "Pass 2.5: call.simd_lower provenance for @hot callee" {
    const alloc = testing.allocator;
    transform_engine.deinitProvenance(alloc);
    defer transform_engine.deinitProvenance(alloc);
    transform_engine.setProvenanceEnabled(true);

    const source =
        \\@hot
        \\fun scale(x: i64): i64
        \\    x * 2
        \\end
        \\y = scale(3)
        \\
    ;
    const c_source = try compileDuoSource(alloc, source);
    defer alloc.free(c_source);
    try testing.expect(provenanceContains("call.simd_lower"));
}
