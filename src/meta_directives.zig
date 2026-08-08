/// Register `@foreign`, `@pipeline`, and `@rewrite` at sema time.
const std = @import("std");
const ast = @import("ast.zig");
const c_signatures = @import("c_signatures.zig");
const rewrite_rules = @import("rewrite_rules.zig");
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
    } else if (std.mem.eql(u8, name, "rewrite")) {
        try registerRewrite(alloc, attr.args orelse "");
    } else if (std.mem.eql(u8, name, "rewrite.bundle")) {
        try registerRewriteBundle(alloc, attr.args orelse "");
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
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return;

    // Split on the comma ending the first quoted derive name. Do not scan the
    // whole macro body for commas — generated C in strings contains '(' and ')'.
    const cp: ?usize = blk: {
        if (trimmed.len >= 2 and trimmed[0] == '"') {
            var i: usize = 1;
            while (i < trimmed.len) : (i += 1) {
                if (trimmed[i] == '\\' and i + 1 < trimmed.len) {
                    i += 1;
                    continue;
                }
                if (trimmed[i] == '"') {
                    var j = i + 1;
                    while (j < trimmed.len and std.mem.indexOf(u8, " \t\r\n", &[_]u8{trimmed[j]}) != null) : (j += 1) {}
                    if (j < trimmed.len and trimmed[j] == ',') break :blk j;
                    break :blk null;
                }
            }
        }
        if (trimmed.len >= 2 and trimmed[0] == '\'') {
            var i: usize = 1;
            while (i < trimmed.len) : (i += 1) {
                if (trimmed[i] == '\\' and i + 1 < trimmed.len) {
                    i += 1;
                    continue;
                }
                if (trimmed[i] == '\'') {
                    var j = i + 1;
                    while (j < trimmed.len and std.mem.indexOf(u8, " \t\r\n", &[_]u8{trimmed[j]}) != null) : (j += 1) {}
                    if (j < trimmed.len and trimmed[j] == ',') break :blk j;
                    break :blk null;
                }
            }
        }
        break :blk std.mem.indexOfScalar(u8, trimmed, ',');
    };
    const comma = cp orelse return;
    const name_raw = std.mem.trim(u8, trimmed[0..comma], " \t\r\n");
    const func_raw = std.mem.trim(u8, trimmed[comma + 1 ..], " \t\r\n");

    const name = directives.extractCRawCode(name_raw);
    if (name.len == 0) return;

    const func_source = if (func_raw.len >= 2 and func_raw[0] == '"' and func_raw[func_raw.len - 1] == '"')
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

fn registerRewrite(alloc: std.mem.Allocator, raw: []const u8) !void {
    const parts = try parseQuotedArgs(alloc, raw);
    defer {
        for (parts) |p| alloc.free(p);
        alloc.free(parts);
    }
    if (parts.len < 3) return;
    const priority: i32 = if (parts.len >= 4)
        std.fmt.parseInt(i32, parts[3], 10) catch 0
    else
        0;
    try rewrite_rules.registerRule(alloc, parts[0], parts[1], parts[2], priority);
}

fn registerRewriteBundle(alloc: std.mem.Allocator, raw: []const u8) !void {
    const bundle = directives.extractCRawCode(raw);
    _ = try rewrite_rules.registerBundle(alloc, bundle);
}

fn registerEmitFile(alloc: std.mem.Allocator, raw: []const u8) !void {
    // @c.emit_file("{ path = "file.h", content = "int x;" }")
    // or @c.emit_file("path.h", "int x;")
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    var path: ?[]const u8 = null;
    var content: ?[]const u8 = null;

    if (trimmed.len > 0 and trimmed[0] == '{') {
        var map = try directives.parseAttrArgs(alloc, trimmed);
        defer map.deinit(alloc);
        path = map.get("path");
        content = map.get("content");
    } else {
        // Two positional args: path, content
        var parts = std.mem.splitScalar(u8, trimmed, ',');
        path = std.mem.trim(u8, parts.next() orelse "", " \t\r\n\"");
        content = std.mem.trim(u8, parts.next() orelse "", " \t\r\n\"");
    }

    if (path == null or content == null) return;

    const resolved_path = directives.extractCRawCode(path.?);
    const resolved_content = directives.extractCRawCode(content.?);

    c_signatures.registerEmitFile(alloc, resolved_path, resolved_content) catch {};
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

fn parseQuotedArgs(alloc: std.mem.Allocator, raw: []const u8) ![]const []const u8 {
    var out: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (out.items) |s| alloc.free(s);
        out.deinit(alloc);
    }
    var i: usize = 0;
    while (i < raw.len) {
        while (i < raw.len and (raw[i] == ' ' or raw[i] == '\t' or raw[i] == '\r' or raw[i] == '\n' or raw[i] == ',')) : (i += 1) {}
        if (i >= raw.len) break;
        if (raw[i] != '"' and raw[i] != '\'') {
            const start = i;
            while (i < raw.len and raw[i] != ',' and raw[i] != ' ' and raw[i] != '\t') : (i += 1) {}
            try out.append(alloc, try alloc.dupe(u8, std.mem.trim(u8, raw[start..i], " \t\r\n")));
            continue;
        }
        const quote = raw[i];
        i += 1;
        const start = i;
        while (i < raw.len) {
            if (raw[i] == '\\' and i + 1 < raw.len) {
                i += 2;
                continue;
            }
            if (raw[i] == quote) break;
            i += 1;
        }
        if (i >= raw.len) return error.UnterminatedString;
        try out.append(alloc, try alloc.dupe(u8, raw[start..i]));
        i += 1;
    }
    return out.toOwnedSlice(alloc);
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

test "meta_directives: register rewrite rule" {
    const alloc = std.testing.allocator;
    rewrite_rules.clearRegistry();
    defer rewrite_rules.clearRegistry();
    try registerRewrite(alloc, "\"mul_two\", \"($1 * 2)\", \"$1 << 1\", 5");
    try std.testing.expectEqual(@as(usize, 1), rewrite_rules.ruleCount());
}

test "meta_directives: register rewrite bundle" {
    const alloc = std.testing.allocator;
    rewrite_rules.clearRegistry();
    defer rewrite_rules.clearRegistry();
    try registerRewriteBundle(alloc, "\"algebraic\"");
    try std.testing.expect(rewrite_rules.ruleCount() >= 10);
}
