/// Evaluate user-defined @meta.define.derive macros at compile time.
const std = @import("std");
const ast = @import("ast.zig");
const comptime_eval = @import("comptime.zig");
const derive_registry = @import("derive_registry.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const types = @import("types.zig");

pub const EvalError = error{
    ParseFailed,
    NoFunction,
    EvalFailed,
    NotString,
    OutOfMemory,
};

/// Evaluate a registered derive macro against type metadata and return generated C code.
/// `bindings` and `options` are forwarded to the comptime evaluator so macros can
/// access compile-time state and use registration hooks (`__register_derive`,
/// `__register_rewrite`) to extend the metaprogramming framework.
pub fn evalDeriveMacro(
    alloc: std.mem.Allocator,
    func_source: []const u8,
    meta: derive_registry.TypeMetadata,
    bindings: comptime_eval.Bindings,
    options: comptime_eval.Options,
) EvalError![]const u8 {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const func_body = parseDeriveFunction(arena_alloc, func_source) catch return EvalError.ParseFailed;
    const meta_value = try metadataToValue(arena_alloc, meta);
    // The macro evaluator needs an allocator; use the arena for temporary work
    // while propagating the caller's hooks and bindings. Registration hooks are
    // expected to copy any durable state out of the arena using ctx/alloc.
    var macro_options = options;
    macro_options.alloc = arena_alloc;
    macro_options.comptime_cache_alloc = alloc;
    const fn_value = comptime_eval.funcValue(func_body, bindings, macro_options) catch return EvalError.EvalFailed;
    const result = comptime_eval.callFunctionValue(fn_value, &.{meta_value}, bindings, macro_options) catch return EvalError.EvalFailed;
    if (result != .string) return EvalError.NotString;
    return try alloc.dupe(u8, result.string);
}

/// Evaluate a registered derive macro against an already-built comptime metadata value.
/// Used by `__eval_derive` so higher-order derive macros can compose existing derives.
pub fn evalDeriveMacroValue(
    alloc: std.mem.Allocator,
    func_source: []const u8,
    meta_value: comptime_eval.Value,
    bindings: comptime_eval.Bindings,
    options: comptime_eval.Options,
) EvalError![]const u8 {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const func_body = parseDeriveFunction(arena_alloc, func_source) catch return EvalError.ParseFailed;
    var macro_options = options;
    macro_options.alloc = arena_alloc;
    macro_options.comptime_cache_alloc = alloc;
    const fn_value = comptime_eval.funcValue(func_body, bindings, macro_options) catch return EvalError.EvalFailed;
    const result = comptime_eval.callFunctionValue(fn_value, &.{meta_value}, bindings, macro_options) catch return EvalError.EvalFailed;
    if (result != .string) return EvalError.NotString;
    return try alloc.dupe(u8, result.string);
}

/// Build TypeMetadata from codegen field types with accurate C type names.
pub fn metadataFromFields(
    alloc: std.mem.Allocator,
    type_name: []const u8,
    fields: []const types.FieldType,
) EvalError!derive_registry.TypeMetadata {
    var field_metas: std.ArrayListUnmanaged(derive_registry.TypeMetadata.FieldMeta) = .empty;
    errdefer field_metas.deinit(alloc);
    for (fields) |f| {
        var buf: [128]u8 = undefined;
        const type_str = f.typ.c_type(&buf);
        const owned_type = try alloc.dupe(u8, type_str);
        try field_metas.append(alloc, .{
            .name = f.name,
            .type_name = owned_type,
        });
    }
    return .{
        .type_name = type_name,
        .fields = try field_metas.toOwnedSlice(alloc),
        .methods = &.{},
    };
}

pub fn parseDeriveFunction(alloc: std.mem.Allocator, source: []const u8) !*const ast.FuncBody {
    var lex = lexer.Lexer.init(source, "<derive>");
    var p = parser.Parser.init(&lex, alloc);
    p.duo_mode = true; // Enable Duo mode for derive macro syntax
    const module = try p.parse_module();
    for (module.body.stmts) |*stmt| {
        if (stmt.* == .func_decl) return &stmt.func_decl.func;
    }
    return error.NoFunction;
}

fn metadataToValue(alloc: std.mem.Allocator, meta: derive_registry.TypeMetadata) !comptime_eval.Value {
    var field_entries: std.ArrayListUnmanaged(comptime_eval.Value.TableEntry) = .empty;
    defer field_entries.deinit(alloc);

    for (meta.fields, 0..) |field, i| {
        const name_owned = try alloc.dupe(u8, field.name);
        const type_owned = try alloc.dupe(u8, field.type_name);
        var field_table: std.ArrayListUnmanaged(comptime_eval.Value.TableEntry) = .empty;
        defer field_table.deinit(alloc);
        try field_table.append(alloc, .{ .name = "name", .val = .{ .string = name_owned } });
        try field_table.append(alloc, .{ .name = "type", .val = .{ .string = type_owned } });
        const field_table_owned = try field_table.toOwnedSlice(alloc);
        try field_entries.append(alloc, .{
            .key = .{ .int = @intCast(i + 1) },
            .val = .{ .table = field_table_owned },
        });
    }

    var root: std.ArrayListUnmanaged(comptime_eval.Value.TableEntry) = .empty;
    defer root.deinit(alloc);
    const type_name_owned = try alloc.dupe(u8, meta.type_name);
    try root.append(alloc, .{ .name = "name", .val = .{ .string = type_name_owned } });
    const fields_owned = try field_entries.toOwnedSlice(alloc);
    try root.append(alloc, .{ .name = "fields", .val = .{ .table = fields_owned } });
    try root.append(alloc, .{ .name = "methods", .val = .{ .table = &.{} } });

    const root_owned = try root.toOwnedSlice(alloc);
    return .{ .table = root_owned };
}

/// Build a comptime meta table `{ name, fields, methods }` from codegen field types.
pub fn metaValueFromFields(
    alloc: std.mem.Allocator,
    type_name: []const u8,
    fields: []const types.FieldType,
) EvalError!comptime_eval.Value {
    const meta = try metadataFromFields(alloc, type_name, fields);
    return metadataToValue(alloc, meta);
}

test "derive_eval: string accumulator macro" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Use a single string literal to avoid concatenation issues
    const source = "fun generate(meta) -> str\n  acc = \"\"\n  for i = 1, #meta.fields\n    f = meta.fields[i]\n    acc = acc .. \"field_\" .. f.name .. \":\" .. f.type .. \";\"\n  end\n  acc\nend\n";

    const meta = derive_registry.TypeMetadata{
        .type_name = "Point",
        .fields = &.{
            .{ .name = "x", .type_name = "double" },
            .{ .name = "y", .type_name = "double" },
        },
        .methods = &.{},
    };

    const code = try evalDeriveMacro(alloc, source, meta, .{}, .{ .alloc = alloc });
    try std.testing.expectEqualStrings("field_x:double;field_y:double;", code);
}

test "derive_eval: metadataFromFields uses c_type names" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = [_]types.FieldType{
        .{ .name = "n", .typ = .i64 },
        .{ .name = "v", .typ = .f64 },
    };
    const meta = try metadataFromFields(alloc, "Pair", &fields);
    try std.testing.expectEqualStrings("int64_t", meta.fields[0].type_name);
    try std.testing.expectEqualStrings("double", meta.fields[1].type_name);
}