/// G-061: tier-1 `@comp.*` combinators — registry + 3-site compile parity harness.
///
/// Each tier-1 combinator must fold to identical native C string literals at:
///   - top-level assign (`PARITY = @comp.*(...)`)
///   - nested callback (`@comp.map("q", fun(_) @comp.*(...) end)`)
///   - block body (`fun parity_fn() @comp.*(...) end`)
const std = @import("std");
const testing = std.testing;
const transform_engine = @import("transform_engine.zig");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;
const CodeGen = @import("codegen.zig").CodeGen;

const ParityCase = struct {
    public_name: []const u8,
    preamble: []const u8 = "",
    body: []const u8,
    /// When false, registry/parse tests still run; compile parity skipped (codegen gap).
    compile_parity: bool = true,
};

/// Minimal bodies that fold identically across all three evaluation sites.
const parity_cases = [_]ParityCase{
    .{
        .public_name = "comp.match",
        .body = "@comp.match(\"a|b\", fun(m) m.pattern .. \"\\n\" end)",
    },
    .{
        .public_name = "comp.map",
        .body = "@comp.map(\"a b\", fun(t) t .. \"\\n\" end)",
    },
    .{
        .public_name = "comp.each",
        .body =
            \\@comp.each("a|b", fun(f)
            \\    f.name .. "\n"
            \\end)
        ,
    },
    .{
        .public_name = "comp.tabulate",
        .body = "@comp.tabulate(2, fun(i) tostring(i) .. \"\\n\" end)",
    },
    .{
        .public_name = "comp.interpolate",
        .body = "@comp.interpolate(\"x={v}\", { v = \"1\" })",
    },
    .{
        .public_name = "comp.power",
        .preamble =
            \\concept Has1
            \\    x: i64
            \\end
            \\type T1 = { x: i64 }
            \\fun sig(t) -> str
            \\    t.name .. "\n"
            \\end
            \\
        ,
        .body = "@comp.power(\"Has1\", sig)",
    },
    .{
        .public_name = "comp.derive.power",
        .preamble =
            \\concept Has1
            \\    x: i64
            \\end
            \\type T1 = { x: i64 }
            \\@comp.define.derive("Stub", fun generate(meta) -> str
            \\    meta.name .. "\n"
            \\end)
            \\
        ,
        .body = "@comp.derive.power(\"Has1\", Stub)",
    },
    .{
        .public_name = "comp.fixpoint",
        .body = "@comp.fixpoint(\"s\", fun(state) \"i\" .. tostring(state.iteration) .. \"\\n\" end, 2)",
        .compile_parity = true,
    },
    .{
        .public_name = "comp.zip",
        .body = "@comp.zip(\"a|b\", \"1|2\", fun(p) p.a .. p.b .. \"\\n\" end)",
    },
    .{
        .public_name = "comp.permute",
        .preamble =
            \\concept Has1
            \\    x: i64
            \\end
            \\type T1 = { x: i64 }
            \\type T2 = { x: i64, y: i64 }
            \\
        ,
        .body = "@comp.permute(\"Has1\", fun(ordered) ordered.name .. \"\\n\" end)",
    },
};

fn extractCStringLiteral(alloc: std.mem.Allocator, c_source: []const u8, binding: []const u8) ?[]const u8 {
    var marker_buf: [64]u8 = undefined;
    const marker = std.fmt.bufPrint(&marker_buf, "const char* {s} = \"", .{binding}) catch return null;
    const start = std.mem.indexOf(u8, c_source, marker) orelse return null;
    var i = start + marker.len;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(alloc);
    while (i < c_source.len) {
        const c = c_source[i];
        if (c == '"') break;
        if (c == '\\' and i + 1 < c_source.len) {
            const next = c_source[i + 1];
            const decoded: u8 = switch (next) {
                'n' => '\n',
                't' => '\t',
                'r' => '\r',
                '\\' => '\\',
                '"' => '"',
                else => next,
            };
            out.append(alloc, decoded) catch return null;
            i += 2;
            continue;
        }
        out.append(alloc, c) catch return null;
        i += 1;
    }
    return out.toOwnedSlice(alloc) catch null;
}

fn extractBlockSiteLiteral(alloc: std.mem.Allocator, c_source: []const u8) ?[]const u8 {
    const marker = "static inline const char* parity_fn() {\n    return \"";
    const start = std.mem.indexOf(u8, c_source, marker) orelse return null;
    var i = start + marker.len;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(alloc);
    while (i < c_source.len) {
        const c = c_source[i];
        if (c == '"') break;
        if (c == '\\' and i + 1 < c_source.len) {
            const next = c_source[i + 1];
            const decoded: u8 = switch (next) {
                'n' => '\n',
                't' => '\t',
                'r' => '\r',
                '\\' => '\\',
                '"' => '"',
                else => next,
            };
            out.append(alloc, decoded) catch return null;
            i += 2;
            continue;
        }
        out.append(alloc, c) catch return null;
        i += 1;
    }
    return out.toOwnedSlice(alloc) catch null;
}

fn buildCombinedParitySource(alloc: std.mem.Allocator, case: ParityCase) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);
    try buf.appendSlice(alloc, case.preamble);
    try buf.appendSlice(alloc, "TOP = ");
    try buf.appendSlice(alloc, case.body);
    try buf.appendSlice(alloc, "\nNESTED = @comp.map(\"q\", fun(_)\n    ");
    try buf.appendSlice(alloc, case.body);
    try buf.appendSlice(alloc, "\nend)\nfun parity_fn(): str\n    ");
    try buf.appendSlice(alloc, case.body);
    try buf.appendSlice(alloc, "\nend\nBLOCK = parity_fn()\n");
    return buf.toOwnedSlice(alloc);
}

fn compileCombinedParity(alloc: std.mem.Allocator, case: ParityCase) !struct { top: []const u8, nested: []const u8, block: []const u8 } {
    const source = try buildCombinedParitySource(alloc, case);
    defer alloc.free(source);

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var lex = Lexer.init(source, "parity.duo");
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
    meta_directives.deinitModuleDeriveRegistry();
    meta_directives.initModuleDeriveRegistry(alloc);
    try cg.emit_module(&mod);
    meta_directives.deinitModuleDeriveRegistry();

    const c_source = aw.written();
    const top = extractCStringLiteral(alloc, c_source, "TOP") orelse return error.ParityLiteralMissing;
    errdefer alloc.free(top);
    const nested = extractCStringLiteral(alloc, c_source, "NESTED") orelse return error.ParityLiteralMissing;
    errdefer alloc.free(nested);
    const block = extractBlockSiteLiteral(alloc, c_source) orelse return error.ParityLiteralMissing;
    return .{ .top = top, .nested = nested, .block = block };
}

test "G-061: tier-1 parity cases cover registry list" {
    try testing.expectEqual(parity_cases.len, transform_engine.parity_tier1.len);
    for (parity_cases) |case| {
        try testing.expect(transform_engine.isRegisteredTransform(case.public_name));
        try testing.expect(transform_engine.requiresParityTest(case.public_name));
    }
}

test "G-061: tier-1 compile parity across three sites" {
    const alloc = testing.allocator;
    for (parity_cases) |case| {
        if (!case.compile_parity) continue;
        const out = try compileCombinedParity(alloc, case);
        defer alloc.free(out.top);
        defer alloc.free(out.nested);
        defer alloc.free(out.block);

        try testing.expect(out.top.len > 0);
        try testing.expectEqualStrings(out.top, out.nested);
        try testing.expectEqualStrings(out.top, out.block);
    }
}

test "G-061: tier-1 combinators parse as expressions in block bodies" {
    const alloc = testing.allocator;
    for (parity_cases) |case| {
        try testing.expect(transform_engine.mustParseAsExpression(case.public_name));
        const source = try buildCombinedParitySource(alloc, case);
        defer alloc.free(source);

        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        const a = arena.allocator();

        var lex = Lexer.init(source, "parity.duo");
        var p = Parser.init(&lex, a);
        p.duo_mode = true;
        const mod = try p.parse_module();
        for (mod.body.stmts) |stmt| {
            switch (stmt) {
                .directive => |d| {
                    if (std.mem.eql(u8, d.attr.name, "comp.define.derive") or
                        std.mem.eql(u8, d.attr.name, "meta.define.derive"))
                        continue;
                    return error.ParsedAsDirective;
                },
                else => {},
            }
        }
        try testing.expect(blockHasCombinatorCall(mod.body));
    }
}

fn blockHasCombinatorCall(block: ast.Block) bool {
    for (block.stmts) |stmt| {
        switch (stmt) {
            .func_decl => |fd| {
                if (blockHasCombinatorCall(fd.func.body)) return true;
            },
            .assign => |a| {
                for (a.values) |val| {
                    if (exprIsMetaCall(val)) return true;
                }
            },
            .expr_stmt => |e| if (exprIsMetaCall(e.expr)) return true,
            else => {},
        }
    }
    if (block.tail_expr) |expr| {
        if (exprIsMetaCall(expr)) return true;
    }
    return false;
}

fn exprIsMetaCall(expr: *const ast.Expr) bool {
    if (expr.* != .call) return false;
    const c = expr.call;
    if (c.func.* != .name) return false;
    return std.mem.startsWith(u8, c.func.name.ident, "__comptime") or
        std.mem.eql(u8, c.func.name.ident, "__derivepower");
}

const ast = @import("ast.zig");
const meta_directives = @import("meta_directives.zig");

fn compilePipelineNative(alloc: std.mem.Allocator) ![]const u8 {
    const source =
        \\fun double(x: i64): i64
        \\  x * 2
        \\end
        \\fun main()
        \\  y = 21 |> double
        \\end
    ;

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var lex = Lexer.init(source, "pipeline.duo");
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
    meta_directives.deinitModuleDeriveRegistry();
    meta_directives.initModuleDeriveRegistry(alloc);
    try cg.emit_module(&mod);
    meta_directives.deinitModuleDeriveRegistry();
    return alloc.dupe(u8, aw.written());
}

test "Pass 2.4: tier-1 compile provenance observes all parity sites" {
    const alloc = testing.allocator;
    transform_engine.deinitProvenance(alloc);
    defer transform_engine.deinitProvenance(alloc);
    transform_engine.setProvenanceEnabled(true);

    for (parity_cases) |case| {
        if (!case.compile_parity) continue;
        transform_engine.deinitProvenance(alloc);
        transform_engine.setProvenanceEnabled(true);

        const out = try compileCombinedParity(alloc, case);
        defer alloc.free(out.top);
        defer alloc.free(out.nested);
        defer alloc.free(out.block);

        try testing.expect(transform_engine.tier1ParityObserved(case.public_name));
    }
}

fn compileDuoSource(alloc: std.mem.Allocator, source: []const u8) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var lex = Lexer.init(source, "test.duo");
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
    meta_directives.deinitModuleDeriveRegistry();
    meta_directives.initModuleDeriveRegistry(alloc);
    try cg.emit_module(&mod);
    meta_directives.deinitModuleDeriveRegistry();
    return alloc.dupe(u8, aw.written());
}

test "Pass 2.5: call.inline dispatches direct native C call" {
    const alloc = testing.allocator;
    const source =
        \\fun add(a: i64, b: i64): i64
        \\  a + b
        \\end
        \\fun main()
        \\  x = add(1, 2)
        \\end
    ;
    const c_source = try compileDuoSource(alloc, source);
    defer alloc.free(c_source);
    try testing.expect(std.mem.indexOf(u8, c_source, "add(") != null);
    try testing.expect(std.mem.indexOf(u8, c_source, "lua_invoke(") == null);
}

test "Pass 2.5: call.simd_lower dispatches @hot callee natively" {
    const alloc = testing.allocator;
    const source =
        \\@hot
        \\fun scale(x: i64): i64
        \\  x * 2
        \\end
        \\fun main()
        \\  y = scale(21)
        \\end
    ;
    const c_source = try compileDuoSource(alloc, source);
    defer alloc.free(c_source);
    try testing.expect(std.mem.indexOf(u8, c_source, "scale(") != null);
    try testing.expect(std.mem.indexOf(u8, c_source, "lua_invoke(") == null);
}

test "Pass 2.5: call transform provenance logs inline dispatch" {
    const alloc = testing.allocator;
    transform_engine.deinitProvenance(alloc);
    defer transform_engine.deinitProvenance(alloc);
    transform_engine.setProvenanceEnabled(true);

    const source =
        \\fun add(a: i64, b: i64): i64
        \\  a + b
        \\end
        \\fun main()
        \\  x = add(1, 2)
        \\end
    ;
    const c_source = try compileDuoSource(alloc, source);
    defer alloc.free(c_source);
    const observed = transform_engine.provenanceSitesObserved("call.inline");
    try testing.expect(observed.contains(.emit_call));
}

test "Pass 2.4: native pipeline |> lowers to direct C call" {
    const alloc = testing.allocator;
    const c_source = try compilePipelineNative(alloc);
    defer alloc.free(c_source);
    try testing.expect(std.mem.indexOf(u8, c_source, "double(") != null);
    try testing.expect(std.mem.indexOf(u8, c_source, "lua_invoke(") == null);
}
