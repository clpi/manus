/// Register `@foreign` and `@pipeline` at sema time.
const std = @import("std");
const ast = @import("ast.zig");
const c_signatures = @import("c_signatures.zig");
const foreign_transpile = @import("foreign_transpile.zig");
const c_header_parse = @import("c_header_parse.zig");
const pipeline_gen = @import("pipeline_gen.zig");
const schema_gen = @import("schema_gen.zig");
const directives = @import("directives.zig");

pub fn registerModuleDirectives(alloc: std.mem.Allocator, mod: *const ast.Module) !void {
    for (mod.body.stmts) |*stmt| {
        switch (stmt.*) {
            .directive => |dir| try registerDirective(alloc, dir.attr),
            .func_decl => |*fd| {
                for (fd.attributes) |attr| try registerDirective(alloc, attr);
            },
            else => {},
        }
    }
}

pub fn registerDirective(alloc: std.mem.Allocator, attr: ast.Attribute) !void {
    const meta_module = @import("meta_module.zig");
    const name = meta_module.normalizeDirective(attr.name);
    if (std.mem.eql(u8, name, "foreign")) {
        try registerForeign(alloc, attr.args orelse "");
    } else if (std.mem.eql(u8, name, "pipeline")) {
        try registerPipeline(alloc, attr.args orelse "");
    } else if (std.mem.eql(u8, name, "ffi.gen")) {
        try registerFfiGen(alloc, attr.args orelse "");
    } else if (std.mem.eql(u8, name, "embed.json")) {
        try registerEmbedJson(alloc, attr.args orelse "");
    } else if (std.mem.eql(u8, name, "sql")) {
        try registerSql(alloc, attr.args orelse "");
    } else if (std.mem.eql(u8, name, "define.derive")) {
        try registerDefineDerive(alloc, attr.args orelse "");
    } else if (std.mem.eql(u8, name, "define.derive.bundle")) {
        try registerDefineDeriveBundle(alloc, attr.args orelse "");
    } else if (std.mem.eql(u8, name, "lua")) {
        try registerLua(alloc, attr.args orelse "");
    } else if (std.mem.eql(u8, name, "wasm")) {
        // @wasm is handled as a file embedding directive
    } else if (std.mem.eql(u8, name, "c.emit.file")) {
        try registerEmitFile(alloc, attr.args orelse "");
    }
}

fn registerForeign(alloc: std.mem.Allocator, raw: []const u8) !void {
    const pair = foreign_transpile.parseForeignArgs(raw) orelse return;
    var owned_code: ?[]const u8 = null;
    defer if (owned_code) |c| alloc.free(c);
    const code = foreign_transpile.unescapeSnippet(alloc, pair.code_raw) catch pair.code_raw;
    if (code.ptr != pair.code_raw.ptr) owned_code = code;
    const c_code = try foreign_transpile.transpileForeign(alloc, pair.lang, code);
    defer alloc.free(c_code);
    try registerDeclsFromC(alloc, c_code);
}

fn pipelineCodeFromArgs(alloc: std.mem.Allocator, raw: []const u8) !struct { text: []const u8, owned: bool } {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len > 0 and trimmed[0] == '{') {
        return .{ .text = try pipeline_gen.generateFromTable(alloc, raw), .owned = true };
    }
    const extracted = directives.extractCRawCode(raw);
    if (std.mem.indexOfScalar(u8, extracted, '\\') != null) {
        return .{ .text = try directives.unescapeCRawCode(alloc, extracted), .owned = true };
    }
    return .{ .text = extracted, .owned = false };
}

fn registerPipeline(alloc: std.mem.Allocator, raw: []const u8) !void {
    const pair = try pipelineCodeFromArgs(alloc, raw);
    defer if (pair.owned) alloc.free(pair.text);
    try registerDeclsFromC(alloc, pair.text);
}

fn registerFfiGen(alloc: std.mem.Allocator, raw: []const u8) !void {
    const header = directives.extractCRawCode(raw);
    const code = c_header_parse.generateFfiFromHeader(alloc, header) catch return;
    defer alloc.free(code);
    try registerDeclsFromC(alloc, code);
}

fn registerEmbedJson(alloc: std.mem.Allocator, raw: []const u8) !void {
    const path = directives.extractCRawCode(raw);
    if (path.len == 0) return;
    // Embed JSON as a C struct definition at module scope
    const schema = schema_gen.jsonSchemaToC(alloc, path) catch return;
    defer alloc.free(schema);
    try registerDeclsFromC(alloc, schema);
}

fn registerSql(alloc: std.mem.Allocator, raw: []const u8) !void {
    const sql = directives.extractCRawCode(raw);
    if (sql.len == 0) return;
    const sql_to_c = @import("sql_to_c.zig");
    const code = sql_to_c.generateFromSql(alloc, sql) catch return;
    defer alloc.free(code);
    try registerDeclsFromC(alloc, code);
}

fn registerLua(alloc: std.mem.Allocator, raw: []const u8) !void {
    const code = directives.extractCRawCode(raw);
    if (code.len == 0) return;

    const unescaped = directives.unescapeCRawCode(alloc, code) catch code;
    defer if (unescaped.ptr != code.ptr) alloc.free(unescaped);

    const host_run = @import("host_run.zig");
    var out_opt = host_run.runHostCommandArgs(alloc, &.{ "luajit", "-e", unescaped });
    if (out_opt == null) {
        out_opt = host_run.runHostCommandArgs(alloc, &.{ "lua", "-e", unescaped });
    }
    const out = out_opt orelse return;
    defer alloc.free(out.stdout);
    defer alloc.free(out.stderr);

    if (out.ok) {
        try registerDeclsFromC(alloc, out.stdout);
    }
}

fn registerDefineDerive(alloc: std.mem.Allocator, raw: []const u8) !void {
    // @meta.define.derive("Name", fun generate(meta) -> str ... end)
    //
    // The second argument is a MACRO BODY, not an argument list: it may hold
    // top-level commas of its own, so only the FIRST argument is tokenized and
    // everything past that comma is taken verbatim. `ArgIter.pos` marks the
    // resume point, which is why this needs no scanner of its own.
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return;

    var it = directives.attrArgs(trimmed);
    const name_arg = it.next() orelse return;
    if (it.pos >= trimmed.len) return; // no comma: nothing to register
    const name = name_arg.text;
    if (name.len == 0) return;

    const func_raw = std.mem.trim(u8, trimmed[it.pos..], " \t\r\n");
    const func_source = if (directives.isRawCEmitLiteral(func_raw))
        directives.extractCRawCode(func_raw)
    else
        func_raw;
    if (func_source.len == 0) return;

    initModuleDeriveRegistry(alloc);
    try module_derive_registry.register(name, func_source, .{ .file = "<directive>", .line = 1, .col = 1 });
}

fn registerDefineDeriveBundle(alloc: std.mem.Allocator, raw: []const u8) !void {
    const derive_bundles_mod = @import("derive_bundles.zig");
    derive_bundles_mod.registerUserBundleFromRaw(alloc, raw) catch {};
}

/// Module-level derive registry for @meta.define.derive directives.
/// This is populated during meta_directives registration and consumed by codegen.
pub var module_derive_registry: derive_registry.DeriveRegistry = undefined;
var module_derive_registry_inited = false;

/// Same lifetime rule as `derive_registry.initNativeDeriveRegistry`: this
/// singleton is initialized once per PROCESS and outlives every compile, so it
/// cannot hold the arena of whichever compile happened to reach it first. It
/// did, and a later `register`/`exists` then wrote through a freed map.
pub fn initModuleDeriveRegistry(alloc: std.mem.Allocator) void {
    _ = alloc;
    if (!module_derive_registry_inited) {
        module_derive_registry = derive_registry.DeriveRegistry.init(std.heap.page_allocator);
        module_derive_registry_inited = true;
    }
}

pub fn deinitModuleDeriveRegistry() void {
    if (module_derive_registry_inited) {
        module_derive_registry.deinit();
        module_derive_registry_inited = false;
    }
}

const derive_registry = @import("derive_registry.zig");

fn registerEmitFile(alloc: std.mem.Allocator, raw: []const u8) !void {
    // @c.emit_file("{ path = "file.h", content = "int x;" }")
    // or @c.emit_file("path.h", "int x;")
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");

    if (trimmed.len > 0 and trimmed[0] == '{') {
        var map = try directives.parseAttrArgs(alloc, trimmed);
        defer map.deinit(alloc);
        const path = map.get("path") orelse return;
        const content = map.get("content") orelse return;
        c_signatures.registerEmitFile(
            alloc,
            directives.extractCRawCode(path),
            directives.extractCRawCode(content),
        ) catch {};
        return;
    }

    // Two positional args: path, content. A plain `splitScalar(',')` used to
    // cut the CONTENT at its first comma, so `@c.emit.file("h.h", "int a, b;")`
    // wrote the file `int a`. The tokenizer keeps a quoted argument whole;
    // `extractCRawCode` still unwraps the `[[ … ]]` spelling of a body.
    const path = directives.attrArg(trimmed, 0) orelse return;
    const content = directives.attrArg(trimmed, 1) orelse return;
    c_signatures.registerEmitFile(
        alloc,
        directives.extractCRawCode(path.raw),
        directives.extractCRawCode(content.raw),
    ) catch {};
}

fn registerDeclsFromC(alloc: std.mem.Allocator, c_code: []const u8) !void {
    const decls = try c_header_parse.parseFunctionDecls(alloc, c_code);
    defer freeDecls(alloc, decls);
    for (decls) |d| {
        try c_signatures.registerDynamicDecl(
            alloc,
            d.name,
            c_signatures.rtFromCRetType(d.ret_type),
            c_signatures.paramCountFromCParams(d.params),
        );
    }
}

fn freeDecls(alloc: std.mem.Allocator, decls: []const c_header_parse.CDecl) void {
    for (decls) |d| {
        alloc.free(d.name);
        alloc.free(d.ret_type);
        alloc.free(d.params);
    }
    alloc.free(decls);
}

pub fn isMetaModuleDirective(name: []const u8) bool {
    return @import("meta_module.zig").isMetaModuleDirective(name);
}

test "meta_directives: register define_derive" {
    const alloc = std.testing.allocator;
    deinitModuleDeriveRegistry();
    initModuleDeriveRegistry(alloc);
    defer deinitModuleDeriveRegistry();
    try registerDefineDerive(alloc, "\"TouchApi\", fun generate(meta) -> str\n    \"ok\"\nend");
    try std.testing.expect(module_derive_registry.exists("TouchApi"));
    try registerDefineDerive(
        alloc,
        "\"LayoutApi\", fun generate(meta) -> str\n    acc .. \"(void)v->\" .. f.name\nend",
    );
    try std.testing.expect(module_derive_registry.exists("LayoutApi"));
}

test "meta_directives: emit.file content keeps a comma inside its quoted argument" {
    const alloc = std.testing.allocator;
    c_signatures.clearEmitFiles();
    defer c_signatures.clearEmitFiles();
    try registerEmitFile(alloc, "\"hdr.h\", \"int a, b;\"");
    try std.testing.expectEqualStrings("int a, b;", c_signatures.emitFilesMap().get("hdr.h").?);
    // Positive control: the table spelling reaches the same registry entry.
    try registerEmitFile(alloc, "{ path = \"tbl.h\", content = \"int c, d;\" }");
    try std.testing.expectEqualStrings("int c, d;", c_signatures.emitFilesMap().get("tbl.h").?);
}
