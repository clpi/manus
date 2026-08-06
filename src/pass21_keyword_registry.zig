//! Pass 21 §45A — machine-readable canonical keyword registry.
//!
//! Compiler-owned grammar facts consumed by catalog, gates, LSP, and MCP.
//! Source of truth for classification until self-hosted `lib/std/token/classify.duo`
//! exports lifecycle metadata directly.
const std = @import("std");

pub const SCHEMA_VERSION = "pass21-keyword-registry-v0";

pub const Classification = enum {
    core,
    readability,
    contextual,
    lua_compatibility,
    legacy_duo,
    @"type",
    experimental,
    deprecate,
    remove,
    not_a_keyword,
};

pub const Lifecycle = enum {
    supported_canonical,
    supported_compatibility,
    deprecated,
    error_with_fix,
    removed,
};

pub const KeywordEntry = struct {
    name: []const u8,
    classification: Classification,
    lifecycle: Lifecycle,
    canonical_replacement: ?[]const u8 = null,
    notes: []const u8 = "",
};

/// Pass 21 Audit A — full lexer keyword inventory with canonical status.
pub const keywords: []const KeywordEntry = &.{
    .{ .name = "if", .classification = .core, .lifecycle = .supported_canonical, .notes = "conditional + if-expression" },
    .{ .name = "else", .classification = .core, .lifecycle = .supported_canonical },
    .{ .name = "elseif", .classification = .readability, .lifecycle = .supported_canonical, .notes = "audit: else if vs elseif (Pass 21 §9)" },
    .{ .name = "for", .classification = .core, .lifecycle = .supported_canonical },
    .{ .name = "while", .classification = .core, .lifecycle = .supported_canonical },
    .{ .name = "in", .classification = .core, .lifecycle = .supported_canonical },
    .{ .name = "return", .classification = .core, .lifecycle = .supported_canonical },
    .{ .name = "break", .classification = .core, .lifecycle = .supported_canonical },
    .{ .name = "continue", .classification = .core, .lifecycle = .supported_canonical },
    .{ .name = "end", .classification = .core, .lifecycle = .supported_canonical, .notes = "Pass 21 §26 — retained" },
    .{ .name = "and", .classification = .core, .lifecycle = .supported_canonical },
    .{ .name = "or", .classification = .core, .lifecycle = .supported_canonical },
    .{ .name = "not", .classification = .core, .lifecycle = .supported_canonical },
    .{ .name = "true", .classification = .core, .lifecycle = .supported_canonical },
    .{ .name = "false", .classification = .core, .lifecycle = .supported_canonical },
    .{ .name = "nil", .classification = .core, .lifecycle = .supported_canonical },
    .{ .name = "global", .classification = .core, .lifecycle = .supported_canonical },
    .{ .name = "then", .classification = .lua_compatibility, .lifecycle = .supported_compatibility, .canonical_replacement = "(omit in Duo canonical)", .notes = "Lua canonical; permanently accepted — lua_superset §1.1" },
    .{ .name = "do", .classification = .lua_compatibility, .lifecycle = .supported_compatibility, .canonical_replacement = "(omit after while/for in Duo canonical)", .notes = "Lua canonical loop form; permanently accepted" },
    .{ .name = "local", .classification = .lua_compatibility, .lifecycle = .supported_compatibility, .canonical_replacement = "(omit binding in Duo canonical)", .notes = "Lua canonical; permanently accepted in .lua and compat paths" },
    .{ .name = "function", .classification = .lua_compatibility, .lifecycle = .supported_compatibility, .canonical_replacement = "bare declaration", .notes = "GR-001" },
    .{ .name = "fun", .classification = .legacy_duo, .lifecycle = .deprecated, .canonical_replacement = "bare declaration or typed param", .notes = "GR-001 untyped bare ambiguity" },
    .{ .name = "repeat", .classification = .readability, .lifecycle = .supported_canonical, .notes = "Pass 21 §24 — audit retained" },
    .{ .name = "until", .classification = .readability, .lifecycle = .supported_canonical },
    .{ .name = "goto", .classification = .lua_compatibility, .lifecycle = .supported_compatibility, .notes = "Pass 21 §25 — noncanonical style" },
    .{ .name = "const", .classification = .contextual, .lifecycle = .supported_canonical, .notes = "module constants" },
    .{ .name = "match", .classification = .contextual, .lifecycle = .deprecated, .canonical_replacement = "dispatch table + call", .notes = "Pass 21 §5 — retire; table-native dispatch" },
    .{ .name = "enum", .classification = .contextual, .lifecycle = .deprecated, .canonical_replacement = "@{...} descriptor", .notes = "Pass 21 §23 — descriptor syntax" },
    .{ .name = "concept", .classification = .contextual, .lifecycle = .deprecated, .canonical_replacement = "descriptor", .notes = "migrate to @comp.* / @{} " },
    .{ .name = "alias", .classification = .contextual, .lifecycle = .deprecated, .canonical_replacement = "descriptor", .notes = "migrate to @{} " },
    .{ .name = "extends", .classification = .contextual, .lifecycle = .deprecated, .canonical_replacement = "..spread in descriptor", .notes = "Pass 21 §20" },
    .{ .name = "try", .classification = .experimental, .lifecycle = .supported_compatibility, .notes = "Pass 21 §15 — ? unapproved" },
    .{ .name = "catch", .classification = .experimental, .lifecycle = .supported_compatibility },
    .{ .name = "defer", .classification = .experimental, .lifecycle = .supported_compatibility },
    .{ .name = "async", .classification = .experimental, .lifecycle = .supported_compatibility },
    .{ .name = "await", .classification = .experimental, .lifecycle = .supported_compatibility },
    .{ .name = "by", .classification = .experimental, .lifecycle = .supported_compatibility, .notes = "numeric for step" },
    .{ .name = "private", .classification = .experimental, .lifecycle = .deprecated, .canonical_replacement = "_ prefix", .notes = "file-private convention" },
    .{ .name = "macro", .classification = .remove, .lifecycle = .error_with_fix, .canonical_replacement = "@comp.*", .notes = "not implemented" },
    .{ .name = "comptime", .classification = .remove, .lifecycle = .error_with_fix, .canonical_replacement = "@(expr)", .notes = "invalid @-directive name" },
    .{ .name = "let", .classification = .remove, .lifecycle = .error_with_fix, .canonical_replacement = "implicit local", .notes = "Pass 21 §10" },
    .{ .name = "i8", .classification = .@"type", .lifecycle = .supported_canonical },
    .{ .name = "i16", .classification = .@"type", .lifecycle = .supported_canonical },
    .{ .name = "i32", .classification = .@"type", .lifecycle = .supported_canonical },
    .{ .name = "i64", .classification = .@"type", .lifecycle = .supported_canonical },
    .{ .name = "u8", .classification = .@"type", .lifecycle = .supported_canonical },
    .{ .name = "u16", .classification = .@"type", .lifecycle = .supported_canonical },
    .{ .name = "u32", .classification = .@"type", .lifecycle = .supported_canonical },
    .{ .name = "u64", .classification = .@"type", .lifecycle = .supported_canonical },
    .{ .name = "f32", .classification = .@"type", .lifecycle = .supported_canonical },
    .{ .name = "f64", .classification = .@"type", .lifecycle = .supported_canonical },
    .{ .name = "bool", .classification = .@"type", .lifecycle = .supported_canonical },
    .{ .name = "void", .classification = .@"type", .lifecycle = .supported_canonical },
    .{ .name = "str", .classification = .@"type", .lifecycle = .supported_canonical },
};

pub const CANONICAL_TARGET_COUNT: u32 = 30;

pub fn find(name: []const u8) ?KeywordEntry {
    for (keywords) |kw| {
        if (std.mem.eql(u8, kw.name, name)) return kw;
    }
    return null;
}

pub fn countCanonical() u32 {
    var n: u32 = 0;
    for (keywords) |kw| {
        if (kw.lifecycle == .supported_canonical) n += 1;
    }
    return n;
}

pub fn countDeprecated() u32 {
    var n: u32 = 0;
    for (keywords) |kw| {
        if (kw.lifecycle == .deprecated) n += 1;
    }
    return n;
}

pub fn classificationName(c: Classification) []const u8 {
    return @tagName(c);
}

pub fn lifecycleName(l: Lifecycle) []const u8 {
    return @tagName(l);
}

test "pass21_keyword_registry: inventory size" {
    try std.testing.expectEqual(@as(usize, 54), keywords.len);
    try std.testing.expect(find("then") != null);
    try std.testing.expect(find("match") != null);
    try std.testing.expectEqual(.supported_compatibility, find("then").?.lifecycle);
    try std.testing.expectEqual(.supported_compatibility, find("do").?.lifecycle);
    try std.testing.expectEqual(.supported_compatibility, find("local").?.lifecycle);
}
