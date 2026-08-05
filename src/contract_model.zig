//! Pass 7 — contract hardness and performance assertion model.
//!
//! Canonical owner for preference vs requirement vs budget semantics.
//! Surface syntax remains in directives/meta_module; this module owns hardness.
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
    hardness: Hardness,
    validation_stage: ValidationStage,
    wired: bool,
    mcp_query: ?[]const u8 = null,
    lsp_support: bool = false,
};

/// Repo-truth catalog of contracts (expand as wiring lands).
pub const catalog: []const ContractRecord = &.{
    .{ .id = "contract.pure", .spelling = "@pure", .category = .effect, .hardness = .assertion, .validation_stage = .sema, .wired = true, .lsp_support = false },
    .{ .id = "contract.noalloc", .spelling = "@noalloc", .category = .effect, .hardness = .assertion, .validation_stage = .codegen, .wired = true, .lsp_support = false },
    .{ .id = "contract.nopanic", .spelling = "@nopanic", .category = .effect, .hardness = .assertion, .validation_stage = .sema, .wired = true, .lsp_support = false },
    .{ .id = "contract.sealed", .spelling = "@sealed", .category = .representation, .hardness = .assertion, .validation_stage = .sema, .wired = true, .lsp_support = false },
    .{ .id = "contract.inline", .spelling = "@inline", .category = .performance, .hardness = .preference, .validation_stage = .codegen, .wired = true, .lsp_support = false },
    .{ .id = "contract.hot", .spelling = "@hot", .category = .performance, .hardness = .preference, .validation_stage = .codegen, .wired = true, .lsp_support = false },
    .{ .id = "contract.cold", .spelling = "@cold", .category = .performance, .hardness = .preference, .validation_stage = .codegen, .wired = true, .lsp_support = false },
    .{ .id = "contract.simd", .spelling = "@simd", .category = .performance, .hardness = .expectation, .validation_stage = .codegen, .wired = false, .lsp_support = false },
    .{ .id = "contract.compile.only", .spelling = "@comp.compile.only", .category = .staging, .hardness = .requirement, .validation_stage = .codegen, .wired = true, .lsp_support = false },
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

test "contract_model: pure is assertion at sema" {
    const c = findBySpelling("@pure") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(Hardness.assertion, c.hardness);
    try std.testing.expect(c.wired);
}

test "contract_model: noalloc enforced at codegen" {
    const c = findBySpelling("@noalloc") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(Hardness.assertion, c.hardness);
    try std.testing.expect(c.wired);
}
