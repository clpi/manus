//! Pass 7 — contract hardness and performance assertion model.
//!
//! Canonical owner for preference vs requirement vs budget semantics.
//! Surface syntax remains in directives/meta_module; this module owns hardness.
//!
//! WHAT THIS CATALOG IS. A description of what the compiler already does with
//! each contract spelling. It is NOT a plan, NOT a wish list, and nothing in
//! the compiler reads it — `pass7_catalog.writePass7Json` is the only consumer,
//! so every row is a claim about OTHER code that only a test can keep honest.
//!
//! Because of that, every row below is pinned by a test at the bottom of this
//! file that runs the real lexer/parser/sema/codegen and observes the real
//! behavior. Do not add a row without one. A test that reads a field of the
//! literal declared beside it proves only that the catalog says what the
//! catalog says; two such tests lived here until 2026-08-08 and let
//! `contract.pure` and `contract.sealed` claim enforcement that never existed.
const std = @import("std");

/// How strictly the compiler must honor a directive or contract.
pub const Hardness = enum(u8) {
    /// Compiler may ignore (hint only).
    preference = 0,
    /// Compiler warns when unmet.
    expectation = 1,
    /// Compilation fails when unmet.
    requirement = 2,
    /// Programmer claims a fact; compiler verifies or rejects.
    assertion = 3,
    /// Measured/estimated limit; fail or warn when exceeded.
    budget = 4,

    pub fn name(self: Hardness) []const u8 {
        return switch (self) {
            .preference => "preference",
            .expectation => "expectation",
            .requirement => "requirement",
            .assertion => "assertion",
            .budget => "budget",
        };
    }
};

pub const ValidationStage = enum(u8) {
    parse,
    sema,
    transform,
    codegen,
    link,
    runtime,

    pub fn name(self: ValidationStage) []const u8 {
        return switch (self) {
            .parse => "parse",
            .sema => "sema",
            .transform => "transform",
            .codegen => "codegen",
            .link => "link",
            .runtime => "runtime",
        };
    }
};

pub const ContractCategory = enum(u8) {
    effect,
    performance,
    numerical,
    representation,
    staging,
    capability,

    pub fn name(self: ContractCategory) []const u8 {
        return switch (self) {
            .effect => "effect",
            .performance => "performance",
            .numerical => "numerical",
            .representation => "representation",
            .staging => "staging",
            .capability => "capability",
        };
    }
};

pub const ContractRecord = struct {
    id: []const u8,
    spelling: []const u8,
    category: ContractCategory,
    /// What the compiler actually does when the contract is unmet — not what
    /// the spelling sounds like. `.assertion` means a real diagnostic or a real
    /// hard failure exists; anything weaker is `.preference`.
    hardness: Hardness,
    /// The stage that CONSUMES the attribute, verified by the tests below.
    validation_stage: ValidationStage,
    /// True only when the compiler changes its behavior because of the
    /// contract at `validation_stage`. Recognizing the spelling is not wiring;
    /// reporting it in a snapshot is not wiring.
    wired: bool,
    lsp_support: bool = false,
};

/// Repo-truth catalog of contracts. Each row is pinned by a behavior test below.
pub const catalog: []const ContractRecord = &.{
    // Nothing verifies purity: an `@pure` function whose body calls `print`
    // type-checks with zero errors. codegen forwards it to C as
    // `__attribute__((const))`, which the C compiler may ignore. That is a
    // preference consumed at codegen — it was catalogued as an assertion
    // verified at sema, and sema does not read the attribute at all.
    .{ .id = "contract.pure", .spelling = "@pure", .category = .effect, .hardness = .preference, .validation_stage = .codegen, .wired = true },
    // codegen.zig guardNoAlloc: heap emit sites raise error.NoAllocViolation
    // and main.zig exits 1 with the message.
    .{ .id = "contract.noalloc", .spelling = "@noalloc", .category = .effect, .hardness = .assertion, .validation_stage = .codegen, .wired = true },
    // sema.zig rejects the `!` unwrap operator inside a `@nopanic` function.
    .{ .id = "contract.nopanic", .spelling = "@nopanic", .category = .effect, .hardness = .assertion, .validation_stage = .sema, .wired = true },
    // `@sealed` moves the storage class reported by the semantic model
    // (`duo sim`) from dynamic to sealed and stops there: the emitted C is
    // byte-identical with and without it, and nothing verifies the seal. A
    // reporting surface is not enforcement, so this row is unwired.
    .{ .id = "contract.sealed", .spelling = "@sealed", .category = .representation, .hardness = .preference, .validation_stage = .transform, .wired = false },
    .{ .id = "contract.inline", .spelling = "@inline", .category = .performance, .hardness = .preference, .validation_stage = .codegen, .wired = true },
    .{ .id = "contract.hot", .spelling = "@hot", .category = .performance, .hardness = .preference, .validation_stage = .codegen, .wired = true },
    .{ .id = "contract.cold", .spelling = "@cold", .category = .performance, .hardness = .preference, .validation_stage = .codegen, .wired = true },
    // `@simd` is not in directives.validateFuncAttrs, so sema rejects it on a
    // function as an unknown attribute. Unwired, and the test says why.
    .{ .id = "contract.simd", .spelling = "@simd", .category = .performance, .hardness = .expectation, .validation_stage = .codegen, .wired = false },
    // Honored by construction: the definition never reaches the C output.
    .{ .id = "contract.compile.only", .spelling = "@comp.compile.only", .category = .staging, .hardness = .requirement, .validation_stage = .codegen, .wired = true },
};

pub fn findBySpelling(spelling: []const u8) ?ContractRecord {
    for (catalog) |c| {
        if (std.mem.eql(u8, c.spelling, spelling)) return c;
    }
    return null;
}

pub fn findById(id: []const u8) ?ContractRecord {
    for (catalog) |c| {
        if (std.mem.eql(u8, c.id, id)) return c;
    }
    return null;
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

pub fn writeCatalogJson(w: *std.Io.Writer) !void {
    try w.print("[", .{});
    for (catalog, 0..) |c, i| {
        if (i > 0) try w.print(",", .{});
        try w.print(
            "{{\"id\":\"{s}\",\"spelling\":\"",
            .{c.id},
        );
        try jsonEscape(w, c.spelling);
        try w.print(
            "\",\"category\":\"{s}\",\"hardness\":\"{s}\",\"validation_stage\":\"{s}\",\"wired\":",
            .{ c.category.name(), c.hardness.name(), c.validation_stage.name() },
        );
        try w.print("{s}", .{if (c.wired) "true" else "false"});
        try w.print(",\"lsp_support\":", .{});
        try w.print("{s}", .{if (c.lsp_support) "true" else "false"});
        try w.print("}}", .{});
    }
    try w.print("]", .{});
}

// ── Behavior tests ────────────────────────────────────────────────────────────
//
// These drive the real compiler. Each one observes what the compiler does with
// a contract spelling and then asserts the catalog row matches that
// observation, so a row goes red both when the enforcement is removed and when
// the row is edited to overclaim.

const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;
const CodeGen = @import("codegen.zig").CodeGen;
const sim = @import("sim.zig");

const Compiled = struct {
    c: []const u8,
    sema_errors: u32,
    emit_error: ?anyerror,
    noalloc_message: ?[]const u8,
};

/// Full duo-mode pipeline: lex → parse → sema → C codegen. Never swallows a
/// codegen failure; it is reported so a test can assert on it.
fn compileDuo(alloc: std.mem.Allocator, src: []const u8) !Compiled {
    var lex = Lexer.init(src, "contract.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var module = try parser.parse_module();
    var semantic = Sema.init(alloc);
    semantic.duo_mode = true;
    try semantic.check_module(&module);

    var aw: std.Io.Writer.Allocating = .init(alloc);
    var cg = CodeGen.init(
        alloc,
        undefined,
        &semantic.type_map,
        &semantic.module_globals,
        &aw.writer,
        semantic.next_closure_id,
        &semantic.table_field_types,
        &semantic.concepts,
    );
    cg.duo_mode = true;
    cg.emit_module(&module) catch |e| return .{
        .c = "",
        .sema_errors = semantic.errors,
        .emit_error = e,
        .noalloc_message = cg.noallocViolationMessage(),
    };
    return .{
        .c = aw.written(),
        .sema_errors = semantic.errors,
        .emit_error = null,
        .noalloc_message = cg.noallocViolationMessage(),
    };
}

/// The first emitted C line mentioning `needle` (the prototype carries the
/// `__attribute__((…))` list), or null when the symbol was never emitted.
fn cLine(out: []const u8, needle: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, out, '\n');
    while (it.next()) |line| {
        if (std.mem.indexOf(u8, line, needle) != null) return line;
    }
    return null;
}

/// Storage class the semantic model (`duo sim`) reports for a record alias.
fn simStorageClass(alloc: std.mem.Allocator, src: []const u8, record: []const u8) ![]const u8 {
    var lex = Lexer.init(src, "contract.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var module = try parser.parse_module();
    const snap = try sim.exportNativeModule(alloc, &module, "contract.duo");
    for (snap.entities) |e| {
        if (std.mem.eql(u8, e.name, record)) return e.storage_class orelse "<none>";
    }
    return error.TestExpectedEqual;
}

test "contract.pure: no verification exists, so the row may not claim one" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // A `@pure` function that prints. If `@pure` were an assertion verified at
    // sema, this is the program that would be rejected.
    const impure_pure =
        \\@pure
        \\fun shout(x: i64): i64
        \\    print(x)
        \\    x
        \\end
        \\
        \\main(): i64
        \\    shout(1)
        \\end
    ;
    const pure_build = try compileDuo(alloc, impure_pure);
    try std.testing.expectEqual(@as(u32, 0), pure_build.sema_errors);

    // Positive control for that zero: the same shape carrying an attribute
    // sema DOES reject must not report zero, or the counter above proves
    // nothing. `@simd` is not accepted on a function (see the simd test).
    const rejected_attr =
        \\@simd
        \\fun shout(x: i64): i64
        \\    print(x)
        \\    x
        \\end
        \\
        \\main(): i64
        \\    shout(1)
        \\end
    ;
    const control_build = try compileDuo(alloc, rejected_attr);
    try std.testing.expect(control_build.sema_errors > 0);

    const row = findBySpelling("@pure") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(Hardness.preference, row.hardness);

    // What `@pure` DOES do: reach the C attribute list at codegen.
    const with_pure = cLine(pure_build.c, "int64_t shout(int64_t x)") orelse
        return error.TestExpectedEqual;
    try std.testing.expect(std.mem.indexOf(u8, with_pure, "__attribute__((const))") != null);

    const without =
        \\fun shout(x: i64): i64
        \\    print(x)
        \\    x
        \\end
        \\
        \\main(): i64
        \\    shout(1)
        \\end
    ;
    const plain = try compileDuo(alloc, without);
    const no_pure = cLine(plain.c, "int64_t shout(int64_t x)") orelse
        return error.TestExpectedEqual;
    try std.testing.expect(std.mem.indexOf(u8, no_pure, "__attribute__") == null);

    try std.testing.expectEqual(ValidationStage.codegen, row.validation_stage);
    try std.testing.expect(row.wired);
}

test "contract.noalloc: the assertion is enforced at codegen" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const violating =
        \\@noalloc
        \\fun leak(): i64
        \\    raw: *u8 = mem.alloc(64)
        \\    mem.free(raw)
        \\    0
        \\end
        \\
        \\main(): i64
        \\    leak()
        \\end
    ;
    const build = try compileDuo(alloc, violating);
    try std.testing.expectEqual(@as(?anyerror, error.NoAllocViolation), build.emit_error);
    const msg = build.noalloc_message orelse return error.TestExpectedEqual;
    try std.testing.expect(std.mem.indexOf(u8, msg, "@noalloc violated in function 'leak'") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "mem.alloc") != null);

    // Control: the same allocation without the contract compiles.
    const allowed =
        \\fun leak(): i64
        \\    raw: *u8 = mem.alloc(64)
        \\    mem.free(raw)
        \\    0
        \\end
        \\
        \\main(): i64
        \\    leak()
        \\end
    ;
    const ok = try compileDuo(alloc, allowed);
    try std.testing.expectEqual(@as(?anyerror, null), ok.emit_error);
    try std.testing.expect(ok.noalloc_message == null);

    const row = findBySpelling("@noalloc") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(Hardness.assertion, row.hardness);
    try std.testing.expectEqual(ValidationStage.codegen, row.validation_stage);
    try std.testing.expect(row.wired);
}

test "contract.nopanic: the assertion is enforced at sema" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const panicking =
        \\@nopanic
        \\function f(x: i64) -> i64
        \\  return x!
        \\end
    ;
    var lex = Lexer.init(panicking, "contract.duo");
    var parser = Parser.init(&lex, alloc);
    var mod = try parser.parse_module();
    var semantic = Sema.init(alloc);
    try semantic.check_module(&mod);
    try std.testing.expect(semantic.errors > 0);

    // Control: the same `!` without the contract is accepted, so the rejection
    // above is caused by `@nopanic` and not by the operator.
    const allowed =
        \\function f(x: i64) -> i64
        \\  return x!
        \\end
    ;
    var lex2 = Lexer.init(allowed, "contract.duo");
    var parser2 = Parser.init(&lex2, alloc);
    var mod2 = try parser2.parse_module();
    var semantic2 = Sema.init(alloc);
    try semantic2.check_module(&mod2);
    try std.testing.expectEqual(@as(u32, 0), semantic2.errors);

    const row = findBySpelling("@nopanic") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(Hardness.assertion, row.hardness);
    try std.testing.expectEqual(ValidationStage.sema, row.validation_stage);
    try std.testing.expect(row.wired);
}

test "contract.sealed: reported by the semantic model, ignored by codegen" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // `items: any` keeps the record off the all-native path, so the storage
    // class is free to differ. It does — in the semantic model only.
    const sealed_src =
        \\@sealed
        \\alias Box = { label: str, items: any }
        \\
        \\main(): i64
        \\    b = Box { label = "a", items = 1 }
        \\    0
        \\end
    ;
    const plain_src =
        \\alias Box = { label: str, items: any }
        \\
        \\main(): i64
        \\    b = Box { label = "a", items = 1 }
        \\    0
        \\end
    ;

    try std.testing.expectEqualStrings("sealed", try simStorageClass(alloc, sealed_src, "Box"));
    try std.testing.expectEqualStrings("dynamic", try simStorageClass(alloc, plain_src, "Box"));

    // …and the generated code is the same byte for byte. `@sealed` changes
    // nothing the compiler emits and verifies nothing, which is why the row is
    // unwired. When that stops being true this test fails, and the row must be
    // re-stated rather than the test relaxed.
    const sealed_build = try compileDuo(alloc, sealed_src);
    const plain_build = try compileDuo(alloc, plain_src);
    try std.testing.expect(sealed_build.c.len > 0);
    try std.testing.expectEqualStrings(plain_build.c, sealed_build.c);

    const row = findBySpelling("@sealed") orelse return error.TestExpectedEqual;
    try std.testing.expect(!row.wired);
    try std.testing.expectEqual(Hardness.preference, row.hardness);
    try std.testing.expectEqual(ValidationStage.transform, row.validation_stage);
}

test "contract.inline/hot/cold: preferences reach the C attribute list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const cases = [_]struct { spelling: []const u8, c_attr: []const u8 }{
        .{ .spelling = "@inline", .c_attr = "always_inline" },
        .{ .spelling = "@hot", .c_attr = "hot" },
        .{ .spelling = "@cold", .c_attr = "cold" },
    };
    for (cases) |case| {
        const src = try std.fmt.allocPrint(alloc,
            \\{s}
            \\fun chill(x: i64): i64
            \\    x + 1
            \\end
            \\
            \\main(): i64
            \\    chill(1)
            \\end
        , .{case.spelling});
        const build = try compileDuo(alloc, src);
        const line = cLine(build.c, "int64_t chill(int64_t x)") orelse
            return error.TestExpectedEqual;
        try std.testing.expect(std.mem.indexOf(u8, line, case.c_attr) != null);

        const row = findBySpelling(case.spelling) orelse return error.TestExpectedEqual;
        try std.testing.expectEqual(Hardness.preference, row.hardness);
        try std.testing.expectEqual(ValidationStage.codegen, row.validation_stage);
        try std.testing.expect(row.wired);
    }

    // Control: no attribute, no attribute list.
    const bare =
        \\fun chill(x: i64): i64
        \\    x + 1
        \\end
        \\
        \\main(): i64
        \\    chill(1)
        \\end
    ;
    const plain = try compileDuo(alloc, bare);
    const line = cLine(plain.c, "int64_t chill(int64_t x)") orelse
        return error.TestExpectedEqual;
    try std.testing.expect(std.mem.indexOf(u8, line, "__attribute__") == null);
}

test "contract.compile.only: the runtime definition is removed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const staged =
        \\@comp.compile.only
        \\fun helper(x: i64): i64
        \\    x + 1
        \\end
        \\
        \\main(): i64
        \\    0
        \\end
    ;
    const build = try compileDuo(alloc, staged);
    try std.testing.expect(build.c.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, build.c, "helper") == null);

    // Control: without the contract the same function IS emitted, so the
    // absence above is the contract at work and not an empty output.
    const runtime =
        \\fun helper(x: i64): i64
        \\    x + 1
        \\end
        \\
        \\main(): i64
        \\    0
        \\end
    ;
    const plain = try compileDuo(alloc, runtime);
    try std.testing.expect(cLine(plain.c, "int64_t helper(int64_t x)") != null);

    const row = findById("contract.compile.only") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(Hardness.requirement, row.hardness);
    try std.testing.expectEqual(ValidationStage.codegen, row.validation_stage);
    try std.testing.expect(row.wired);
}

test "contract.simd: unwired — sema rejects the spelling on a function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const with_simd =
        \\@simd
        \\fun vec(x: i64): i64
        \\    x + 1
        \\end
    ;
    const build = try compileDuo(alloc, with_simd);
    try std.testing.expect(build.sema_errors > 0);

    const without =
        \\fun vec(x: i64): i64
        \\    x + 1
        \\end
    ;
    const plain = try compileDuo(alloc, without);
    try std.testing.expectEqual(@as(u32, 0), plain.sema_errors);

    const row = findBySpelling("@simd") orelse return error.TestExpectedEqual;
    try std.testing.expect(!row.wired);
}
