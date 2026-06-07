const std = @import("std");
const lexer_mod = @import("lexer.zig");
const Lexer = lexer_mod.Lexer;
const TokenKind = lexer_mod.TokenKind;
const Parser = @import("parser.zig").Parser;
const ast = @import("ast.zig");
const sema_mod = @import("sema.zig");
const CodeGen = @import("codegen.zig").CodeGen;

// ─── Property 15: `in` Operator Disambiguation (Lexer Level) ─────────────────
//
// **Validates: Requirements 23.10**
//
// For any occurrence of the token `in`: the lexer SHALL always emit `kw_in`
// regardless of whether `in` appears in a for-loop header or an expression
// context. Disambiguation between loop-keyword and binary-operator semantics
// is a parser concern, not a lexer concern.

/// Helper: lex all tokens from source, collecting only their kinds.
fn lex_all_kinds(src: []const u8) !std.ArrayList(TokenKind) {
    var kinds = std.ArrayList(TokenKind).init(std.testing.allocator);
    errdefer kinds.deinit();
    var lex = Lexer.init(src, "test");
    while (true) {
        const tok = try lex.next();
        try kinds.append(tok.kind);
        if (tok.kind == .eof) break;
    }
    return kinds;
}

/// Helper: verify that every `in` token in the source is lexed as `kw_in`.
fn assert_in_is_kw_in(src: []const u8) !void {
    var lex = Lexer.init(src, "test");
    while (true) {
        const tok = try lex.next();
        if (tok.kind == .eof) break;
        // If the token text is "in", it must be kw_in
        if (std.mem.eql(u8, tok.text, "in")) {
            try std.testing.expectEqual(TokenKind.kw_in, tok.kind);
        }
    }
}

/// Generate a random identifier (1-8 lowercase chars, not a keyword).
fn gen_identifier(rng: std.Random, buf: []u8) []const u8 {
    const len = rng.intRangeAtMost(usize, 1, @min(buf.len, 8));
    // Start with a letter that avoids generating keywords like "in", "if", "do", etc.
    // Use a restricted first char to reduce keyword collisions
    const first_chars = "xyzwvqj";
    buf[0] = first_chars[rng.intRangeAtMost(usize, 0, first_chars.len - 1)];
    for (buf[1..len]) |*c| {
        c.* = 'a' + @as(u8, @intCast(rng.intRangeAtMost(u5, 0, 25)));
    }
    return buf[0..len];
}

/// Generate a random integer literal string.
fn gen_int_literal(rng: std.Random, buf: []u8) []const u8 {
    const val = rng.intRangeAtMost(u32, 0, 9999);
    const result = std.fmt.bufPrint(buf, "{}", .{val}) catch "0";
    return result;
}

test "Property 15: `in` always lexes as kw_in in for-loop headers" {
    // Generate for-loop headers: `for <var> in <expr>`
    // The `in` token must always be kw_in.
    var prng = std.Random.DefaultPrng.init(0xDEAD_BEEF);
    const rng = prng.random();

    var src_buf: [256]u8 = undefined;
    var id_buf: [16]u8 = undefined;
    var id_buf2: [16]u8 = undefined;

    for (0..100) |_| {
        const var_name = gen_identifier(rng, &id_buf);
        const iter_name = gen_identifier(rng, &id_buf2);

        // "for <var> in <iter>"
        const src = std.fmt.bufPrint(&src_buf, "for {s} in {s}", .{ var_name, iter_name }) catch continue;
        try assert_in_is_kw_in(src);
    }
}

test "Property 15: `in` always lexes as kw_in in expression contexts" {
    // Generate expression contexts: `<expr> in <expr>`
    // Even when `in` is used as a binary operator (contains), the lexer
    // must still emit kw_in. Parser handles the semantic distinction.
    var prng = std.Random.DefaultPrng.init(0xCAFE_BABE);
    const rng = prng.random();

    var src_buf: [256]u8 = undefined;
    var id_buf: [16]u8 = undefined;
    var id_buf2: [16]u8 = undefined;

    for (0..100) |_| {
        const lhs = gen_identifier(rng, &id_buf);
        const rhs = gen_identifier(rng, &id_buf2);

        // "<lhs> in <rhs>"  -- expression context (contains operator)
        const src = std.fmt.bufPrint(&src_buf, "{s} in {s}", .{ lhs, rhs }) catch continue;
        try assert_in_is_kw_in(src);
    }
}

test "Property 15: `in` always lexes as kw_in with multiple variables in for-loop" {
    // for i, v in pairs(t)
    var prng = std.Random.DefaultPrng.init(0x1234_5678);
    const rng = prng.random();

    var src_buf: [256]u8 = undefined;
    var id_buf1: [16]u8 = undefined;
    var id_buf2: [16]u8 = undefined;
    var id_buf3: [16]u8 = undefined;

    for (0..100) |_| {
        const var1 = gen_identifier(rng, &id_buf1);
        const var2 = gen_identifier(rng, &id_buf2);
        const iter_expr = gen_identifier(rng, &id_buf3);

        // "for <v1>, <v2> in <iter>()"
        const src = std.fmt.bufPrint(&src_buf, "for {s}, {s} in {s}()", .{ var1, var2, iter_expr }) catch continue;
        try assert_in_is_kw_in(src);
    }
}

test "Property 15: `in` always lexes as kw_in mixed contexts" {
    // Generate snippets with `in` appearing in both for-loop and expression
    // contexts within the same source, verifying all occurrences are kw_in.
    var prng = std.Random.DefaultPrng.init(0xBEEF_CAFE);
    const rng = prng.random();

    var src_buf: [512]u8 = undefined;
    var id_buf1: [16]u8 = undefined;
    var id_buf2: [16]u8 = undefined;
    var id_buf3: [16]u8 = undefined;
    var id_buf4: [16]u8 = undefined;

    for (0..100) |_| {
        const v = gen_identifier(rng, &id_buf1);
        const iter = gen_identifier(rng, &id_buf2);
        const lhs = gen_identifier(rng, &id_buf3);
        const rhs = gen_identifier(rng, &id_buf4);

        // Mix: a for-loop `in` and an expression `in` on separate lines
        const src = std.fmt.bufPrint(&src_buf, "for {s} in {s}\n{s} in {s}", .{ v, iter, lhs, rhs }) catch continue;
        try assert_in_is_kw_in(src);
    }
}

test "Property 15: `in` with integer operands lexes as kw_in" {
    // Verify `<int> in <ident>` still gives kw_in for `in`
    var prng = std.Random.DefaultPrng.init(0xABCD_EF01);
    const rng = prng.random();

    var src_buf: [256]u8 = undefined;
    var int_buf: [16]u8 = undefined;
    var id_buf: [16]u8 = undefined;

    for (0..100) |_| {
        const lhs = gen_int_literal(rng, &int_buf);
        const rhs = gen_identifier(rng, &id_buf);

        // "<int> in <ident>"
        const src = std.fmt.bufPrint(&src_buf, "{s} in {s}", .{ lhs, rhs }) catch continue;
        try assert_in_is_kw_in(src);
    }
}

// ─── Property 15: `in` Operator Disambiguation (Parser Level) ────────────────
//
// **Validates: Requirements 23.10**
//
// For any occurrence of the token `in`: when it appears after a `for` header's
// variable list it SHALL be parsed as the loop keyword (producing a gen_for
// statement); in all other expression contexts it SHALL be parsed as a binary
// operator invoking `__contains` (producing a binop with BinOp.contains).

/// Helper: parse source using an arena allocator and return the module AST.
fn parse_source(arena: std.mem.Allocator, src: []const u8) !ast.Module {
    var lex = Lexer.init(src, "test");
    var parser = Parser.init(&lex, arena);
    return parser.parse_module();
}

/// Generate a random identifier that cannot collide with Duo/Lua keywords.
/// Uses prefix "v_" followed by 1-6 lowercase chars.
fn gen_safe_identifier(rng: std.Random, buf: []u8) []const u8 {
    buf[0] = 'v';
    buf[1] = '_';
    const len = rng.intRangeAtMost(usize, 1, @min(buf.len - 2, 6));
    for (buf[2 .. 2 + len]) |*c| {
        c.* = 'a' + @as(u8, @intCast(rng.intRangeAtMost(u5, 0, 25)));
    }
    return buf[0 .. 2 + len];
}

test "Property 15 (parser): `for VAR in ITER do end` parses as gen_for" {
    var prng = std.Random.DefaultPrng.init(0xA15_F001);
    const rng = prng.random();

    var src_buf: [256]u8 = undefined;
    var id_buf1: [16]u8 = undefined;
    var id_buf2: [16]u8 = undefined;

    for (0..100) |_| {
        const var_name = gen_safe_identifier(rng, &id_buf1);
        const iter_name = gen_safe_identifier(rng, &id_buf2);

        const src = std.fmt.bufPrint(&src_buf, "for {s} in {s} do end", .{ var_name, iter_name }) catch continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const module = parse_source(arena.allocator(), src) catch |err| {
            std.debug.print("Parse error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        // Module body should have exactly one statement: gen_for
        try std.testing.expectEqual(@as(usize, 1), module.body.stmts.len);
        const stmt = module.body.stmts[0];
        try std.testing.expect(stmt == .gen_for);

        // The variable list should contain our var_name
        const gf = stmt.gen_for;
        try std.testing.expectEqual(@as(usize, 1), gf.vars.len);
        try std.testing.expectEqualStrings(var_name, gf.vars[0]);
    }
}

test "Property 15 (parser): `for V1, V2 in ITER do end` parses as gen_for with multiple vars" {
    var prng = std.Random.DefaultPrng.init(0xA15_F002);
    const rng = prng.random();

    var src_buf: [256]u8 = undefined;
    var id_buf1: [16]u8 = undefined;
    var id_buf2: [16]u8 = undefined;
    var id_buf3: [16]u8 = undefined;

    for (0..100) |_| {
        const v1 = gen_safe_identifier(rng, &id_buf1);
        const v2 = gen_safe_identifier(rng, &id_buf2);
        const iter_name = gen_safe_identifier(rng, &id_buf3);

        const src = std.fmt.bufPrint(&src_buf, "for {s}, {s} in {s} do end", .{ v1, v2, iter_name }) catch continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const module = parse_source(arena.allocator(), src) catch |err| {
            std.debug.print("Parse error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        try std.testing.expectEqual(@as(usize, 1), module.body.stmts.len);
        const stmt = module.body.stmts[0];
        try std.testing.expect(stmt == .gen_for);

        const gf = stmt.gen_for;
        try std.testing.expectEqual(@as(usize, 2), gf.vars.len);
        try std.testing.expectEqualStrings(v1, gf.vars[0]);
        try std.testing.expectEqualStrings(v2, gf.vars[1]);
    }
}

test "Property 15 (parser): `return EXPR in EXPR` parses as binop with BinOp.contains" {
    var prng = std.Random.DefaultPrng.init(0xA15_F003);
    const rng = prng.random();

    var src_buf: [256]u8 = undefined;
    var id_buf1: [16]u8 = undefined;
    var id_buf2: [16]u8 = undefined;

    for (0..100) |_| {
        const lhs = gen_safe_identifier(rng, &id_buf1);
        const rhs = gen_safe_identifier(rng, &id_buf2);

        const src = std.fmt.bufPrint(&src_buf, "return {s} in {s}", .{ lhs, rhs }) catch continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const module = parse_source(arena.allocator(), src) catch |err| {
            std.debug.print("Parse error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        // Module body should have one return statement
        try std.testing.expectEqual(@as(usize, 1), module.body.stmts.len);
        const stmt = module.body.stmts[0];
        try std.testing.expect(stmt == .ret);

        // The return value should be a binop with .contains
        const ret = stmt.ret;
        try std.testing.expectEqual(@as(usize, 1), ret.vals.len);
        const expr = ret.vals[0];
        try std.testing.expect(expr.* == .binop);
        try std.testing.expectEqual(ast.BinOp.contains, expr.binop.op);

        // LHS should be a name matching our generated identifier
        try std.testing.expect(expr.binop.lhs.* == .name);
        try std.testing.expectEqualStrings(lhs, expr.binop.lhs.name.ident);

        // RHS should be a name matching our generated identifier
        try std.testing.expect(expr.binop.rhs.* == .name);
        try std.testing.expectEqualStrings(rhs, expr.binop.rhs.name.ident);
    }
}

test "Property 15 (parser): `return INT in IDENT` parses as binop with BinOp.contains" {
    var prng = std.Random.DefaultPrng.init(0xA15_F004);
    const rng = prng.random();

    var src_buf: [256]u8 = undefined;
    var int_buf: [16]u8 = undefined;
    var id_buf: [16]u8 = undefined;

    for (0..100) |_| {
        const lhs_int = gen_int_literal(rng, &int_buf);
        const rhs = gen_safe_identifier(rng, &id_buf);

        const src = std.fmt.bufPrint(&src_buf, "return {s} in {s}", .{ lhs_int, rhs }) catch continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const module = parse_source(arena.allocator(), src) catch |err| {
            std.debug.print("Parse error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        try std.testing.expectEqual(@as(usize, 1), module.body.stmts.len);
        const stmt = module.body.stmts[0];
        try std.testing.expect(stmt == .ret);

        const ret = stmt.ret;
        try std.testing.expectEqual(@as(usize, 1), ret.vals.len);
        const expr = ret.vals[0];
        try std.testing.expect(expr.* == .binop);
        try std.testing.expectEqual(ast.BinOp.contains, expr.binop.op);

        // LHS should be an int literal
        try std.testing.expect(expr.binop.lhs.* == .int_lit);

        // RHS should be a name
        try std.testing.expect(expr.binop.rhs.* == .name);
        try std.testing.expectEqualStrings(rhs, expr.binop.rhs.name.ident);
    }
}

test "Property 15 (parser): for-loop `in` vs expression `in` in same program" {
    // Generate a program with both `for x in iter do end` and `return a in b`
    // Verify the for-loop produces gen_for and the return produces binop.contains
    var prng = std.Random.DefaultPrng.init(0xA15_F005);
    const rng = prng.random();

    var src_buf: [512]u8 = undefined;
    var id_buf1: [16]u8 = undefined;
    var id_buf2: [16]u8 = undefined;
    var id_buf3: [16]u8 = undefined;
    var id_buf4: [16]u8 = undefined;

    for (0..100) |_| {
        const loop_var = gen_safe_identifier(rng, &id_buf1);
        const iter_name = gen_safe_identifier(rng, &id_buf2);
        const expr_lhs = gen_safe_identifier(rng, &id_buf3);
        const expr_rhs = gen_safe_identifier(rng, &id_buf4);

        const src = std.fmt.bufPrint(&src_buf, "for {s} in {s} do end\nreturn {s} in {s}", .{
            loop_var, iter_name, expr_lhs, expr_rhs,
        }) catch continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const module = parse_source(arena.allocator(), src) catch |err| {
            std.debug.print("Parse error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        // Should have 2 statements: gen_for followed by return
        try std.testing.expectEqual(@as(usize, 2), module.body.stmts.len);

        // First statement: gen_for
        const stmt1 = module.body.stmts[0];
        try std.testing.expect(stmt1 == .gen_for);
        try std.testing.expectEqual(@as(usize, 1), stmt1.gen_for.vars.len);
        try std.testing.expectEqualStrings(loop_var, stmt1.gen_for.vars[0]);

        // Second statement: return with binop.contains
        const stmt2 = module.body.stmts[1];
        try std.testing.expect(stmt2 == .ret);
        const ret_expr = stmt2.ret.vals[0];
        try std.testing.expect(ret_expr.* == .binop);
        try std.testing.expectEqual(ast.BinOp.contains, ret_expr.binop.op);
        try std.testing.expect(ret_expr.binop.lhs.* == .name);
        try std.testing.expectEqualStrings(expr_lhs, ret_expr.binop.lhs.name.ident);
        try std.testing.expect(ret_expr.binop.rhs.* == .name);
        try std.testing.expectEqualStrings(expr_rhs, ret_expr.binop.rhs.name.ident);
    }
}

// ─── Property 5: Type Inference Soundness ────────────────────────────────────
//
// **Validates: Requirements 3.2, 3.5**
//
// For any expression with a statically determinable type, if no type annotation
// is provided, the inferred type SHALL equal the expression's actual type.
// Specifically: integer literals → i64, float literals → f64, string literals → str,
// boolean literals → bool.

const Sema = @import("sema.zig").Sema;
const types = @import("types.zig");
const RT = types.ResolvedType;

/// Generate a random integer literal string (positive integers only for simplicity).
fn gen_random_int(rng: std.Random, buf: []u8) []const u8 {
    const val = rng.intRangeAtMost(u32, 0, 999_999);
    return std.fmt.bufPrint(buf, "{}", .{val}) catch "42";
}

/// Generate a random float literal string.
/// Produces values like "3.14", "0.5", "123.456"
fn gen_random_float(rng: std.Random, buf: []u8) []const u8 {
    const whole = rng.intRangeAtMost(u16, 0, 9999);
    const frac = rng.intRangeAtMost(u16, 1, 999); // at least 1 to ensure non-zero decimal
    return std.fmt.bufPrint(buf, "{}.{}", .{ whole, frac }) catch "1.5";
}

/// Generate a random string literal (with surrounding quotes).
/// Content is 1-10 alphanumeric chars.
fn gen_random_string(rng: std.Random, buf: []u8) []const u8 {
    const content_len = rng.intRangeAtMost(usize, 1, @min(buf.len - 3, 10));
    buf[0] = '"';
    for (buf[1 .. 1 + content_len]) |*c| {
        const choice = rng.intRangeAtMost(u8, 0, 35);
        if (choice < 26) {
            c.* = 'a' + choice;
        } else {
            c.* = '0' + (choice - 26);
        }
    }
    buf[1 + content_len] = '"';
    return buf[0 .. 2 + content_len];
}

/// Run sema on source code and return the module + sema state.
/// Caller must manage the arena lifetime.
fn parse_and_check(alloc: std.mem.Allocator, src: []const u8) !struct { mod: ast.Module, sema: Sema } {
    var lex = Lexer.init(src, "test");
    var parser = Parser.init(&lex, alloc);
    var mod = try parser.parse_module();
    var sema = Sema.init(alloc);
    try sema.check_module(&mod);
    return .{ .mod = mod, .sema = sema };
}

test "Property 5: integer literals infer to i64" {
    // Feature: duo-language-spec, Property 5: Type Inference Soundness
    // Generate random integer literals and verify they infer to i64.
    var prng = std.Random.DefaultPrng.init(0xA5_1001);
    const rng = prng.random();

    var src_buf: [256]u8 = undefined;
    var lit_buf: [32]u8 = undefined;

    for (0..100) |_| {
        const int_lit = gen_random_int(rng, &lit_buf);
        const src = std.fmt.bufPrint(&src_buf, "local x = {s}", .{int_lit}) catch continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const result = parse_and_check(arena.allocator(), src) catch |err| {
            std.debug.print("Error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        try std.testing.expectEqual(@as(u32, 0), result.sema.errors);

        // The initializer expression should be in the type map as i64
        const init_expr = result.mod.body.stmts[0].local_decl.inits[0];
        const inferred = result.sema.type_map.get(init_expr);
        try std.testing.expect(inferred != null);
        try std.testing.expectEqual(RT.i64, inferred.?);
    }
}

test "Property 5: float literals infer to f64" {
    // Feature: duo-language-spec, Property 5: Type Inference Soundness
    // Generate random float literals and verify they infer to f64.
    var prng = std.Random.DefaultPrng.init(0xA5_2002);
    const rng = prng.random();

    var src_buf: [256]u8 = undefined;
    var lit_buf: [32]u8 = undefined;

    for (0..100) |_| {
        const float_lit = gen_random_float(rng, &lit_buf);
        const src = std.fmt.bufPrint(&src_buf, "local x = {s}", .{float_lit}) catch continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const result = parse_and_check(arena.allocator(), src) catch |err| {
            std.debug.print("Error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        try std.testing.expectEqual(@as(u32, 0), result.sema.errors);

        const init_expr = result.mod.body.stmts[0].local_decl.inits[0];
        const inferred = result.sema.type_map.get(init_expr);
        try std.testing.expect(inferred != null);
        try std.testing.expectEqual(RT.f64, inferred.?);
    }
}

test "Property 5: string literals infer to str" {
    // Feature: duo-language-spec, Property 5: Type Inference Soundness
    // Generate random string literals and verify they infer to str.
    var prng = std.Random.DefaultPrng.init(0xA5_3003);
    const rng = prng.random();

    var src_buf: [256]u8 = undefined;
    var lit_buf: [32]u8 = undefined;

    for (0..100) |_| {
        const str_lit = gen_random_string(rng, &lit_buf);
        const src = std.fmt.bufPrint(&src_buf, "local x = {s}", .{str_lit}) catch continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const result = parse_and_check(arena.allocator(), src) catch |err| {
            std.debug.print("Error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        try std.testing.expectEqual(@as(u32, 0), result.sema.errors);

        const init_expr = result.mod.body.stmts[0].local_decl.inits[0];
        const inferred = result.sema.type_map.get(init_expr);
        try std.testing.expect(inferred != null);
        try std.testing.expectEqual(RT.str, inferred.?);
    }
}

test "Property 5: boolean literals infer to bool" {
    // Feature: duo-language-spec, Property 5: Type Inference Soundness
    // Generate random boolean literals (true/false) and verify they infer to bool.
    var prng = std.Random.DefaultPrng.init(0xA5_4004);
    const rng = prng.random();

    var src_buf: [256]u8 = undefined;

    for (0..100) |_| {
        const bool_val = if (rng.boolean()) "true" else "false";
        const src = std.fmt.bufPrint(&src_buf, "local x = {s}", .{bool_val}) catch continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const result = parse_and_check(arena.allocator(), src) catch |err| {
            std.debug.print("Error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        try std.testing.expectEqual(@as(u32, 0), result.sema.errors);

        const init_expr = result.mod.body.stmts[0].local_decl.inits[0];
        const inferred = result.sema.type_map.get(init_expr);
        try std.testing.expect(inferred != null);
        try std.testing.expectEqual(RT.bool, inferred.?);
    }
}

test "Property 5: mixed literal types infer correctly without annotations" {
    // Feature: duo-language-spec, Property 5: Type Inference Soundness
    // Generate programs with multiple declarations using different literal types,
    // verify each declaration's initializer gets the correct inferred type.
    var prng = std.Random.DefaultPrng.init(0xA5_5005);
    const rng = prng.random();

    var src_buf: [512]u8 = undefined;
    var lit_buf: [32]u8 = undefined;

    for (0..100) |_| {
        const int_lit = gen_random_int(rng, &lit_buf);
        var float_buf: [32]u8 = undefined;
        const float_lit = gen_random_float(rng, &float_buf);
        const bool_val = if (rng.boolean()) "true" else "false";

        // Build a program with int, float, string, and bool declarations
        const src = std.fmt.bufPrint(&src_buf,
            \\local a = {s}
            \\local b = {s}
            \\local c = "hello"
            \\local d = {s}
        , .{ int_lit, float_lit, bool_val }) catch continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const result = parse_and_check(arena.allocator(), src) catch |err| {
            std.debug.print("Error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        try std.testing.expectEqual(@as(u32, 0), result.sema.errors);

        // Verify each declaration's initializer type
        const stmts = result.mod.body.stmts;
        try std.testing.expect(stmts.len >= 4);

        // a = int_lit → i64
        const t_a = result.sema.type_map.get(stmts[0].local_decl.inits[0]);
        try std.testing.expect(t_a != null);
        try std.testing.expectEqual(RT.i64, t_a.?);

        // b = float_lit → f64
        const t_b = result.sema.type_map.get(stmts[1].local_decl.inits[0]);
        try std.testing.expect(t_b != null);
        try std.testing.expectEqual(RT.f64, t_b.?);

        // c = "hello" → str
        const t_c = result.sema.type_map.get(stmts[2].local_decl.inits[0]);
        try std.testing.expect(t_c != null);
        try std.testing.expectEqual(RT.str, t_c.?);

        // d = bool_val → bool
        const t_d = result.sema.type_map.get(stmts[3].local_decl.inits[0]);
        try std.testing.expect(t_d != null);
        try std.testing.expectEqual(RT.bool, t_d.?);
    }
}

test "Property 5: nil literal infers to nil" {
    // Feature: duo-language-spec, Property 5: Type Inference Soundness
    // **Validates: Requirements 3.2, 3.5**
    // Verify that `nil` literal infers to the `.nil` type across 100 iterations.
    // Each iteration varies the variable name to exercise different parsing paths.
    var prng = std.Random.DefaultPrng.init(0xA5_6006);
    const rng = prng.random();

    var src_buf: [256]u8 = undefined;
    var id_buf: [16]u8 = undefined;

    for (0..100) |_| {
        const var_name = gen_safe_identifier(rng, &id_buf);
        const src = std.fmt.bufPrint(&src_buf, "local {s} = nil", .{var_name}) catch continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const result = parse_and_check(arena.allocator(), src) catch |err| {
            std.debug.print("Error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        try std.testing.expectEqual(@as(u32, 0), result.sema.errors);

        const init_expr = result.mod.body.stmts[0].local_decl.inits[0];
        const inferred = result.sema.type_map.get(init_expr);
        try std.testing.expect(inferred != null);
        try std.testing.expectEqual(RT.nil, inferred.?);
    }
}

// ─── Property 4: Type Annotation Enforcement ─────────────────────────────────
//
// **Validates: Requirements 3.1, 3.4**
//
// For any variable declaration with an explicit type annotation T and
// initializer expression of type U where T ≠ U and no implicit coercion
// exists, the Type_Checker SHALL emit a type error. Conversely, for any
// declaration where annotation matches the initializer type, the
// Type_Checker SHALL accept it without errors.

/// Type annotation strings and the literal expressions that produce them.
const TypeLiteralPair = struct {
    type_name: []const u8,
    literal: []const u8,
    resolved: RT,
};

/// All valid type-annotation-to-literal combinations that should pass.
const matching_pairs = [_]TypeLiteralPair{
    .{ .type_name = "i64", .literal = "42", .resolved = .i64 },
    .{ .type_name = "i64", .literal = "0", .resolved = .i64 },
    .{ .type_name = "i64", .literal = "999", .resolved = .i64 },
    .{ .type_name = "f64", .literal = "3.14", .resolved = .f64 },
    .{ .type_name = "f64", .literal = "0.0", .resolved = .f64 },
    .{ .type_name = "f64", .literal = "1.5", .resolved = .f64 },
    .{ .type_name = "str", .literal = "\"hello\"", .resolved = .str },
    .{ .type_name = "str", .literal = "\"\"", .resolved = .str },
    .{ .type_name = "str", .literal = "\"world\"", .resolved = .str },
    .{ .type_name = "bool", .literal = "true", .resolved = .bool },
    .{ .type_name = "bool", .literal = "false", .resolved = .bool },
};

/// All type annotations we can test with (annotation name + resolved type).
const all_annotations = [_]struct { name: []const u8, resolved: RT }{
    .{ .name = "i64", .resolved = .i64 },
    .{ .name = "f64", .resolved = .f64 },
    .{ .name = "str", .resolved = .str },
    .{ .name = "bool", .resolved = .bool },
};

/// All literal expressions and their inferred types.
const all_literals = [_]struct { literal: []const u8, resolved: RT }{
    .{ .literal = "42", .resolved = .i64 },
    .{ .literal = "0", .resolved = .i64 },
    .{ .literal = "3.14", .resolved = .f64 },
    .{ .literal = "0.0", .resolved = .f64 },
    .{ .literal = "\"hello\"", .resolved = .str },
    .{ .literal = "\"\"", .resolved = .str },
    .{ .literal = "true", .resolved = .bool },
    .{ .literal = "false", .resolved = .bool },
};

test "Property 4: type checker accepts matching type annotations" {
    // Feature: duo-language-spec, Property 4: Type Annotation Enforcement
    // For each matching (annotation, literal) pair, verify sema produces 0 errors.
    // Run randomized selection of matching pairs, minimum 100 iterations.
    var prng = std.Random.DefaultPrng.init(0xA4_4001);
    const rng = prng.random();

    var src_buf: [256]u8 = undefined;

    for (0..100) |_| {
        const pair = matching_pairs[rng.intRangeAtMost(usize, 0, matching_pairs.len - 1)];

        const src = std.fmt.bufPrint(&src_buf, "local x: {s} = {s}", .{ pair.type_name, pair.literal }) catch continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const result = parse_and_check(arena.allocator(), src) catch |err| {
            std.debug.print("Parse/sema error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        // Matching type + literal should produce no errors
        if (result.sema.errors != 0) {
            std.debug.print("FAIL: expected 0 errors for `{s}`, got {}\n", .{ src, result.sema.errors });
            return error.TestUnexpectedResult;
        }
    }
}

test "Property 4: type checker rejects mismatched type annotations" {
    // Feature: duo-language-spec, Property 4: Type Annotation Enforcement
    // For each (annotation, literal) pair where types don't match,
    // verify sema produces at least 1 error.
    var prng = std.Random.DefaultPrng.init(0xA4_4002);
    const rng = prng.random();

    var src_buf: [256]u8 = undefined;
    var iterations: usize = 0;

    while (iterations < 100) {
        const ann_idx = rng.intRangeAtMost(usize, 0, all_annotations.len - 1);
        const lit_idx = rng.intRangeAtMost(usize, 0, all_literals.len - 1);

        const ann = all_annotations[ann_idx];
        const lit = all_literals[lit_idx];

        // Skip if types match — we only want mismatches
        if (ann.resolved.eql(lit.resolved)) continue;

        iterations += 1;

        const src = std.fmt.bufPrint(&src_buf, "local x: {s} = {s}", .{ ann.name, lit.literal }) catch continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const result = parse_and_check(arena.allocator(), src) catch |err| {
            std.debug.print("Parse/sema error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        // Mismatched types should produce at least 1 error
        if (result.sema.errors == 0) {
            std.debug.print("FAIL: expected error for `{s}` (annotation={s}, literal type={}), got 0 errors\n", .{ src, ann.name, lit.resolved });
            return error.TestUnexpectedResult;
        }
    }
}

test "Property 4: random (type, literal) pairs - acceptance and rejection" {
    // Feature: duo-language-spec, Property 4: Type Annotation Enforcement
    // Generate random combinations of type annotations and literal values.
    // Verify: matching -> 0 errors, mismatching -> >0 errors.
    var prng = std.Random.DefaultPrng.init(0xA4_4003);
    const rng = prng.random();

    var src_buf: [256]u8 = undefined;

    for (0..100) |_| {
        const ann_idx = rng.intRangeAtMost(usize, 0, all_annotations.len - 1);
        const lit_idx = rng.intRangeAtMost(usize, 0, all_literals.len - 1);

        const ann = all_annotations[ann_idx];
        const lit = all_literals[lit_idx];

        const src = std.fmt.bufPrint(&src_buf, "local x: {s} = {s}", .{ ann.name, lit.literal }) catch continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const result = parse_and_check(arena.allocator(), src) catch |err| {
            std.debug.print("Parse/sema error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        const types_match = ann.resolved.eql(lit.resolved);

        if (types_match) {
            // Should accept
            if (result.sema.errors != 0) {
                std.debug.print("FAIL: expected 0 errors for matching `{s}`, got {}\n", .{ src, result.sema.errors });
                return error.TestUnexpectedResult;
            }
        } else {
            // Should reject
            if (result.sema.errors == 0) {
                std.debug.print("FAIL: expected error for mismatching `{s}`, got 0 errors\n", .{src});
                return error.TestUnexpectedResult;
            }
        }
    }
}

test "Property 4: annotation 'any' accepts all literal types" {
    // Feature: duo-language-spec, Property 4: Type Annotation Enforcement
    // The `any` type annotation should accept all initializer types.
    var src_buf: [256]u8 = undefined;

    for (all_literals) |lit| {
        const src = std.fmt.bufPrint(&src_buf, "local x: any = {s}", .{lit.literal}) catch continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const result = parse_and_check(arena.allocator(), src) catch |err| {
            std.debug.print("Parse/sema error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        if (result.sema.errors != 0) {
            std.debug.print("FAIL: 'any' annotation should accept all types, but `{s}` produced {} errors\n", .{ src, result.sema.errors });
            return error.TestUnexpectedResult;
        }
    }
}

test "Property 4: nil literal is accepted by all type annotations" {
    // Feature: duo-language-spec, Property 4: Type Annotation Enforcement
    // nil can be assigned to any typed variable (it represents absence).
    var src_buf: [256]u8 = undefined;

    for (all_annotations) |ann| {
        const src = std.fmt.bufPrint(&src_buf, "local x: {s} = nil", .{ann.name}) catch continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const result = parse_and_check(arena.allocator(), src) catch |err| {
            std.debug.print("Parse/sema error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        if (result.sema.errors != 0) {
            std.debug.print("FAIL: nil should be accepted by '{s}' annotation, but got {} errors\n", .{ ann.name, result.sema.errors });
            return error.TestUnexpectedResult;
        }
    }
}

// ─── Property 4: Type Annotation Enforcement (ResolvedType.eql level) ────────
//
// **Validates: Requirements 3.1, 3.4**
//
// Generate random pairs of ResolvedType values. Verify that:
// 1. When annotation type == expression type, eql() returns true (type check passes)
// 2. When annotation type != expression type, eql() returns false (type check fails)
// 3. `any` type accepts any value (special case for dynamic typing)

/// All primitive ResolvedType values that can appear as type annotations.
const primitive_types = [_]RT{
    .i8,  .i16, .i32,  .i64,
    .u8,  .u16, .u32,  .u64,
    .f32, .f64, .bool, .void,
    .str, .any, .nil,
};

/// Generate a random primitive ResolvedType from the set of available primitives.
fn gen_random_resolved_type(rng: std.Random) RT {
    const idx = rng.intRangeAtMost(usize, 0, primitive_types.len - 1);
    return primitive_types[idx];
}

/// Simulate type annotation enforcement: returns true if a value of type `expr_type`
/// is accepted by an annotation of `ann_type`. This mirrors the type checker's logic:
/// - If annotation is `any`, accept everything (dynamic typing)
/// - If expression is `any`, accept (runtime check deferred)
/// - Otherwise, types must be equal via eql()
fn type_annotation_accepts(ann_type: RT, expr_type: RT) bool {
    // `any` annotation accepts all types (Requirement 3.3)
    if (ann_type == .any) return true;
    // Expression of type `any` is accepted by any annotation (deferred to runtime)
    if (expr_type == .any) return true;
    // `nil` is assignable to any type (absence value)
    if (expr_type == .nil) return true;
    // Otherwise, strict type equality
    return ann_type.eql(expr_type);
}

test "Property 4 (eql): matching types always produce eql() == true" {
    // Feature: duo-language-spec, Property 4: Type Annotation Enforcement
    // Generate random ResolvedType values and verify reflexivity:
    // for any type T, T.eql(T) must be true (same annotation and expression type).
    var prng = std.Random.DefaultPrng.init(0xA4_E001);
    const rng = prng.random();

    for (0..100) |_| {
        const t = gen_random_resolved_type(rng);
        // Same type on both sides: type checker must accept
        if (!t.eql(t)) {
            std.debug.print("FAIL: {}.eql({}) returned false (reflexivity violated)\n", .{ t, t });
            return error.TestUnexpectedResult;
        }
        // type_annotation_accepts must also return true for matching types
        if (!type_annotation_accepts(t, t)) {
            std.debug.print("FAIL: type_annotation_accepts({}, {}) returned false\n", .{ t, t });
            return error.TestUnexpectedResult;
        }
    }
}

test "Property 4 (eql): mismatched types produce eql() == false" {
    // Feature: duo-language-spec, Property 4: Type Annotation Enforcement
    // Generate random pairs of different ResolvedType values (excluding `any` and `nil`
    // which have special acceptance rules). Verify that eql() returns false.
    var prng = std.Random.DefaultPrng.init(0xA4_E002);
    const rng = prng.random();

    // Types that follow strict equality (no special acceptance rules)
    const strict_types = [_]RT{
        .i8,  .i16, .i32,  .i64,
        .u8,  .u16, .u32,  .u64,
        .f32, .f64, .bool, .void,
        .str,
    };

    var iterations: usize = 0;
    while (iterations < 100) {
        const idx_a = rng.intRangeAtMost(usize, 0, strict_types.len - 1);
        const idx_b = rng.intRangeAtMost(usize, 0, strict_types.len - 1);

        // Only test distinct pairs
        if (idx_a == idx_b) continue;
        iterations += 1;

        const type_a = strict_types[idx_a];
        const type_b = strict_types[idx_b];

        // Different types: eql() must return false
        if (type_a.eql(type_b)) {
            std.debug.print("FAIL: {}.eql({}) returned true for distinct types\n", .{ type_a, type_b });
            return error.TestUnexpectedResult;
        }

        // type_annotation_accepts with strict types must also reject
        if (type_annotation_accepts(type_a, type_b)) {
            std.debug.print("FAIL: type_annotation_accepts({}, {}) returned true for mismatched strict types\n", .{ type_a, type_b });
            return error.TestUnexpectedResult;
        }
    }
}

test "Property 4 (eql): `any` annotation accepts all expression types" {
    // Feature: duo-language-spec, Property 4: Type Annotation Enforcement
    // The `any` type annotation defers type checking to runtime, so it accepts
    // any initializer type without error.
    var prng = std.Random.DefaultPrng.init(0xA4_E003);
    const rng = prng.random();

    for (0..100) |_| {
        const expr_type = gen_random_resolved_type(rng);

        // `any` annotation should accept any expression type
        if (!type_annotation_accepts(.any, expr_type)) {
            std.debug.print("FAIL: type_annotation_accepts(any, {}) returned false\n", .{expr_type});
            return error.TestUnexpectedResult;
        }
    }
}

test "Property 4 (eql): `any` expression type is accepted by all annotations" {
    // Feature: duo-language-spec, Property 4: Type Annotation Enforcement
    // An expression of type `any` (dynamically typed) should be accepted by any
    // annotation because type checking is deferred to runtime.
    var prng = std.Random.DefaultPrng.init(0xA4_E004);
    const rng = prng.random();

    for (0..100) |_| {
        const ann_type = gen_random_resolved_type(rng);

        // Any expression of type `any` should be accepted by all annotations
        if (!type_annotation_accepts(ann_type, .any)) {
            std.debug.print("FAIL: type_annotation_accepts({}, any) returned false\n", .{ann_type});
            return error.TestUnexpectedResult;
        }
    }
}

test "Property 4 (eql): random type pairs - acceptance iff types compatible" {
    // Feature: duo-language-spec, Property 4: Type Annotation Enforcement
    // Generate fully random (annotation, expression) pairs from all primitive types.
    // Verify the combined acceptance logic: accept when types match, or when
    // either side is `any`, or when expression is `nil`; reject otherwise.
    var prng = std.Random.DefaultPrng.init(0xA4_E005);
    const rng = prng.random();

    for (0..100) |_| {
        const ann_type = gen_random_resolved_type(rng);
        const expr_type = gen_random_resolved_type(rng);

        const accepted = type_annotation_accepts(ann_type, expr_type);

        // Determine expected acceptance
        const should_accept = (ann_type == .any) or
            (expr_type == .any) or
            (expr_type == .nil) or
            ann_type.eql(expr_type);

        if (accepted != should_accept) {
            std.debug.print("FAIL: type_annotation_accepts({}, {}) = {}, expected {}\n", .{ ann_type, expr_type, accepted, should_accept });
            return error.TestUnexpectedResult;
        }
    }
}

// ─── Property 3: Scoping Invariant ───────────────────────────────────────────
//
// **Validates: Requirements 1.3, 1.4**
//
// In `.duo` mode, a bare assignment (`x = ...`) at a new-binding position SHALL
// create a local binding (not visible as a module global), while the `global`
// keyword SHALL create a module-global binding.

/// Run sema in `.duo` mode and return the sema state.
fn parse_and_check_duo(alloc: std.mem.Allocator, src: []const u8) !Sema {
    var lex = Lexer.init(src, "test");
    var parser = Parser.init(&lex, alloc);
    var mod = try parser.parse_module();
    var sema = Sema.init(alloc);
    sema.duo_mode = true;
    try sema.check_module(&mod);
    return sema;
}

test "Property 3: bare assignment creates a local, not a module global" {
    // Feature: duo-language-spec, Property 3: Scoping Invariant
    var prng = std.Random.DefaultPrng.init(0xA3_0001);
    const rng = prng.random();

    var src_buf: [256]u8 = undefined;
    var id_buf: [16]u8 = undefined;

    for (0..100) |_| {
        const ident = gen_safe_identifier(rng, &id_buf);
        // Bare assignment followed by a use so the name is referenced.
        const src = std.fmt.bufPrint(&src_buf, "{s} = 1\nprint({s})", .{ ident, ident }) catch continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        var sema = parse_and_check_duo(arena.allocator(), src) catch |err| {
            std.debug.print("Error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        try std.testing.expectEqual(@as(u32, 0), sema.errors);
        // A bare local must NOT be registered as a module global.
        try std.testing.expect(sema.module_globals.get(ident) == null);
    }
}

test "Property 3: `global` keyword creates a module-global binding" {
    // Feature: duo-language-spec, Property 3: Scoping Invariant
    var prng = std.Random.DefaultPrng.init(0xA3_0002);
    const rng = prng.random();

    var src_buf: [256]u8 = undefined;
    var id_buf: [16]u8 = undefined;

    for (0..100) |_| {
        const ident = gen_safe_identifier(rng, &id_buf);
        const src = std.fmt.bufPrint(&src_buf, "global {s} = 1\nprint({s})", .{ ident, ident }) catch continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        var sema = parse_and_check_duo(arena.allocator(), src) catch |err| {
            std.debug.print("Error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        try std.testing.expectEqual(@as(u32, 0), sema.errors);
        // A `global` binding MUST be registered as a module global.
        try std.testing.expect(sema.module_globals.get(ident) != null);
    }
}

// ─── Property 7: Match Exhaustiveness ────────────────────────────────────────
//
// **Validates: Requirements 5.5, 6.2**
//
// For a `match` on an enum with N variants, the compiler SHALL emit an error
// when fewer than N variants are covered (and no wildcard is present), and
// SHALL accept the match when all variants are covered or a wildcard is given.

/// Emit `enum NAME V0 V1 ... end` plus `local v = NAME` and a `match` covering
/// the first `covered` variants (optionally with a trailing wildcard).
/// A tiny append helper over a fixed buffer (std.io is unavailable here).
const BufWriter = struct {
    buf: []u8,
    len: usize = 0,
    fn print(self: *BufWriter, comptime fmt: []const u8, args: anytype) bool {
        const s = std.fmt.bufPrint(self.buf[self.len..], fmt, args) catch return false;
        self.len += s.len;
        return true;
    }
    fn written(self: *const BufWriter) []const u8 {
        return self.buf[0..self.len];
    }
};

fn build_enum_match_src(
    buf: []u8,
    enum_name: []const u8,
    variants: usize,
    covered: usize,
    wildcard: bool,
) ?[]const u8 {
    var w = BufWriter{ .buf = buf };
    if (!w.print("enum {s}\n", .{enum_name})) return null;
    for (0..variants) |i| if (!w.print("  V{d}\n", .{i})) return null;
    if (!w.print("end\nlocal v = {s}\nmatch v\n", .{enum_name})) return null;
    for (0..covered) |i| if (!w.print("  {s}.V{d} => print(1)\n", .{ enum_name, i })) return null;
    if (wildcard) if (!w.print("  _ => print(0)\n", .{})) return null;
    if (!w.print("end\n", .{})) return null;
    return w.written();
}

test "Property 7: partial match on an enum is rejected" {
    // Feature: duo-language-spec, Property 7: Match Exhaustiveness
    var prng = std.Random.DefaultPrng.init(0xA7_0001);
    const rng = prng.random();

    var src_buf: [1024]u8 = undefined;

    for (0..100) |_| {
        const variants = rng.intRangeAtMost(usize, 2, 6);
        const covered = rng.intRangeAtMost(usize, 1, variants - 1); // strictly fewer
        const src = build_enum_match_src(&src_buf, "E", variants, covered, false) orelse continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const result = parse_and_check(arena.allocator(), src) catch |err| {
            std.debug.print("Error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        // Missing variants with no wildcard → at least one exhaustiveness error.
        if (result.sema.errors == 0) {
            std.debug.print("FAIL: expected exhaustiveness error for:\n{s}\n", .{src});
            return error.TestUnexpectedResult;
        }
    }
}

test "Property 7: full coverage or wildcard is exhaustive" {
    // Feature: duo-language-spec, Property 7: Match Exhaustiveness
    var prng = std.Random.DefaultPrng.init(0xA7_0002);
    const rng = prng.random();

    var src_buf: [1024]u8 = undefined;

    for (0..100) |_| {
        const variants = rng.intRangeAtMost(usize, 2, 6);
        // Half the time cover all variants; otherwise cover a subset + wildcard.
        const use_wildcard = rng.boolean();
        const covered = if (use_wildcard) rng.intRangeAtMost(usize, 0, variants) else variants;
        const src = build_enum_match_src(&src_buf, "E", variants, covered, use_wildcard) orelse continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const result = parse_and_check(arena.allocator(), src) catch |err| {
            std.debug.print("Error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        if (result.sema.errors != 0) {
            std.debug.print("FAIL: unexpected error for exhaustive match:\n{s}\n", .{src});
            return error.TestUnexpectedResult;
        }
    }
}

// ─── Property 14: Concept Constraint Checking ────────────────────────────────
//
// **Validates: Requirements 15.1, 15.2, 15.4**
//
// A binding annotated `@implements(Concept)` SHALL be accepted iff its
// record-type annotation supplies every member the concept requires.

/// Build a concept with `required` i64 fields and a binding whose record
/// annotation supplies the first `provided` of them.
fn build_concept_impl_src(buf: []u8, required: usize, provided: usize) ?[]const u8 {
    var w = BufWriter{ .buf = buf };
    if (!w.print("concept C\n", .{})) return null;
    for (0..required) |i| if (!w.print("  f{d}: i64\n", .{i})) return null;
    if (!w.print("end\n@implements(C)\nlocal x: {{ ", .{})) return null;
    for (0..provided) |i| {
        if (i > 0) if (!w.print(", ", .{})) return null;
        if (!w.print("f{d}: i64", .{i})) return null;
    }
    if (!w.print(" }} = {{ ", .{})) return null;
    for (0..provided) |i| {
        if (i > 0) if (!w.print(", ", .{})) return null;
        if (!w.print("f{d} = {d}", .{ i, i })) return null;
    }
    if (!w.print(" }}\n", .{})) return null;
    return w.written();
}

test "Property 14: @implements accepted iff all required members provided" {
    // Feature: duo-language-spec, Property 14: Concept Constraint Checking
    var prng = std.Random.DefaultPrng.init(0xA14_0001);
    const rng = prng.random();

    var src_buf: [1024]u8 = undefined;

    for (0..100) |_| {
        const required = rng.intRangeAtMost(usize, 1, 5);
        const provided = rng.intRangeAtMost(usize, 1, required);
        const src = build_concept_impl_src(&src_buf, required, provided) orelse continue;

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const result = parse_and_check(arena.allocator(), src) catch |err| {
            std.debug.print("Error for source: `{s}`: {}\n", .{ src, err });
            return err;
        };

        const fully_satisfied = (provided == required);
        const accepted = (result.sema.errors == 0);
        if (accepted != fully_satisfied) {
            std.debug.print("FAIL: required={d} provided={d} accepted={} for:\n{s}\n", .{ required, provided, accepted, src });
            return error.TestUnexpectedResult;
        }
    }
}

// ─── Property 6: Monomorphization Uniqueness ─────────────────────────────────
//
// **Validates: Requirements 4.1, 4.3**
//
// For a generic function instantiated at several call sites, distinct tuples of
// concrete type arguments SHALL produce distinct specializations, while
// identical tuples SHALL reuse a single specialization. Equivalently: the number
// of specializations equals the number of *distinct* type-argument tuples seen.

const Mono = @import("mono.zig");

/// One of the four literal kinds the property generator chooses among, paired
/// with the source text used to produce an argument of that type.
const LitKind = enum(u3) { int, float, str, boolean };

fn lit_source(kind: LitKind) []const u8 {
    return switch (kind) {
        .int => "1",
        .float => "1.0",
        .str => "\"s\"",
        .boolean => "true",
    };
}

test "Property 6: specialization count equals number of distinct type args" {
    // Feature: duo-language-spec, Property 6: Monomorphization Uniqueness
    var prng = std.Random.DefaultPrng.init(0xA6_0001);
    const rng = prng.random();

    var src_buf: [4096]u8 = undefined;

    for (0..100) |_| {
        const num_calls = rng.intRangeAtMost(usize, 1, 12);

        // Choose a literal kind per call and track which distinct kinds appear.
        var kinds: [12]LitKind = undefined;
        var seen = [_]bool{ false, false, false, false };
        for (0..num_calls) |c| {
            const k: LitKind = @enumFromInt(rng.intRangeAtMost(u3, 0, 3));
            kinds[c] = k;
            seen[@intFromEnum(k)] = true;
        }
        var distinct: usize = 0;
        for (seen) |b| {
            if (b) distinct += 1;
        }

        // Build the source: a generic identity function plus one binding per call.
        var w = BufWriter{ .buf = &src_buf };
        if (!w.print("fun id<T>(x: T) -> T\n  return x\nend\n", .{})) continue;
        for (0..num_calls) |c| {
            if (!w.print("local v{d} = id({s})\n", .{ c, lit_source(kinds[c]) })) continue;
        }
        const src = w.written();

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        const result = parse_and_check(alloc, src) catch |err| {
            std.debug.print("Error for source:\n{s}\n{}\n", .{ src, err });
            return err;
        };

        var mod = result.mod;
        var sema = result.sema;
        var mono = Mono.Monomorphizer.init(alloc, &sema.type_map);
        try mono.run(&mod);

        if (mono.count() != distinct) {
            std.debug.print("FAIL: expected {d} specializations, got {d} for:\n{s}\n", .{ distinct, mono.count(), src });
            return error.TestUnexpectedResult;
        }
    }
}

test "Property 6: identical type args always reuse one specialization" {
    // Feature: duo-language-spec, Property 6: Monomorphization Uniqueness
    var prng = std.Random.DefaultPrng.init(0xA6_0002);
    const rng = prng.random();

    var src_buf: [4096]u8 = undefined;

    for (0..100) |_| {
        const num_calls = rng.intRangeAtMost(usize, 2, 12);
        const k: LitKind = @enumFromInt(rng.intRangeAtMost(u3, 0, 3));

        // Every call uses the SAME literal kind → exactly one specialization.
        var w = BufWriter{ .buf = &src_buf };
        if (!w.print("fun id<T>(x: T) -> T\n  return x\nend\n", .{})) continue;
        for (0..num_calls) |c| {
            if (!w.print("local v{d} = id({s})\n", .{ c, lit_source(k) })) continue;
        }
        const src = w.written();

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        const result = parse_and_check(alloc, src) catch |err| {
            std.debug.print("Error for source:\n{s}\n{}\n", .{ src, err });
            return err;
        };

        var mod = result.mod;
        var sema = result.sema;
        var mono = Mono.Monomorphizer.init(alloc, &sema.type_map);
        try mono.run(&mod);

        if (mono.count() != 1) {
            std.debug.print("FAIL: expected 1 specialization, got {d} for:\n{s}\n", .{ mono.count(), src });
            return error.TestUnexpectedResult;
        }
    }
}

// ─── Property 13: ARC Refcount Correctness ───────────────────────────────────
//
// **Validates: Requirements 26.1, 26.2**
//
// Across any sequence of heap-binding declarations, reassignments, and scope
// exits, the retain and release annotations SHALL be balanced — equivalently,
// every heap value's reference count returns to zero exactly when no live
// reference to it remains.

const Arc = @import("arc.zig");

test "Property 13: retains and releases are balanced over random sequences" {
    // Feature: duo-language-spec, Property 13: ARC Refcount Correctness
    var prng = std.Random.DefaultPrng.init(0xA13_0001);
    const rng = prng.random();

    var src_buf: [8192]u8 = undefined;

    for (0..100) |_| {
        const num_bindings = rng.intRangeAtMost(usize, 1, 6);
        const num_reassigns = rng.intRangeAtMost(usize, 0, 6);

        var w = BufWriter{ .buf = &src_buf };
        // Declare `num_bindings` heap (str) locals.
        for (0..num_bindings) |i| {
            if (!w.print("local h{d}: str = \"v\"\n", .{i})) continue;
        }
        // Reassign random existing bindings to new heap values.
        var reassigns_done: usize = 0;
        for (0..num_reassigns) |_| {
            const target = rng.intRangeAtMost(usize, 0, num_bindings - 1);
            if (!w.print("h{d} = \"w\"\n", .{target})) continue;
            reassigns_done += 1;
        }
        const src = w.written();

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        const result = parse_and_check(alloc, src) catch |err| {
            std.debug.print("Error for source:\n{s}\n{}\n", .{ src, err });
            return err;
        };

        var mod = result.mod;
        var sema = result.sema;
        var arc = Arc.ArcPass.init(alloc, &sema.type_map);
        try arc.run(&mod);

        const retains = arc.countOp(.retain);
        const releases = arc.countOp(.release);
        // Balance invariant: refcount returns to zero.
        if (retains != releases) {
            std.debug.print("FAIL: retains={d} releases={d} for:\n{s}\n", .{ retains, releases, src });
            return error.TestUnexpectedResult;
        }
        // Each binding and each reassignment contributes exactly one retain.
        const expected = num_bindings + reassigns_done;
        if (retains != expected) {
            std.debug.print("FAIL: expected {d} retains, got {d} for:\n{s}\n", .{ expected, retains, src });
            return error.TestUnexpectedResult;
        }
    }
}

test "Property 13: balance holds across nested scopes" {
    // Feature: duo-language-spec, Property 13: ARC Refcount Correctness
    var prng = std.Random.DefaultPrng.init(0xA13_0002);
    const rng = prng.random();

    var src_buf: [8192]u8 = undefined;

    for (0..100) |_| {
        const outer = rng.intRangeAtMost(usize, 0, 4);
        const inner = rng.intRangeAtMost(usize, 1, 4);

        var w = BufWriter{ .buf = &src_buf };
        for (0..outer) |i| {
            if (!w.print("local o{d}: str = \"o\"\n", .{i})) continue;
        }
        if (!w.print("do\n", .{})) continue;
        for (0..inner) |i| {
            if (!w.print("  local i{d}: str = \"i\"\n", .{i})) continue;
        }
        if (!w.print("end\n", .{})) continue;
        const src = w.written();

        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        const result = parse_and_check(alloc, src) catch |err| {
            std.debug.print("Error for source:\n{s}\n{}\n", .{ src, err });
            return err;
        };

        var mod = result.mod;
        var sema = result.sema;
        var arc = Arc.ArcPass.init(alloc, &sema.type_map);
        try arc.run(&mod);

        try std.testing.expectEqual(arc.countOp(.retain), arc.countOp(.release));
        try std.testing.expectEqual(outer + inner, arc.countOp(.retain));
    }
}

