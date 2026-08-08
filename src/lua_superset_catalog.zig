//! Lua superset maximization catalog — compatibility contract + construct matrix.
//!
//! Governing rule: every valid Lua 5.5 program should remain a valid Duo program
//! with equivalent observable semantics unless a documented, unavoidable conflict
//! makes that impossible.
const std = @import("std");

pub const SCHEMA_VERSION = "lua-superset-catalog-v0";
pub const PLAN_PATH = "docs/archive/pass24_execution_concurrency_lua_supremacy.md";

/// Syntax classification taxonomy (§1.1).
pub const SyntaxClass = enum {
    duo_canonical,
    lua_canonical,
    lua_and_duo_canonical,
    duo_extension,
    legacy_duo_experiment,
    actually_deprecated,
    invalid,

    pub fn name(self: SyntaxClass) []const u8 {
        return @tagName(self);
    }
};

pub const DeprecationThreshold = struct {
    id: []const u8,
    rule: []const u8,
};

/// §1.2 — deprecation requires all six conditions; token reduction alone is insufficient.
pub const deprecation_threshold: []const DeprecationThreshold = &.{
    .{ .id = "DT-1", .rule = "genuine semantic or grammatical conflict" },
    .{ .id = "DT-2", .rule = "contextual disambiguation cannot solve the conflict reliably" },
    .{ .id = "DT-3", .rule = "preserving it materially blocks a higher-value Duo capability" },
    .{ .id = "DT-4", .rule = "migration is exact and automatic" },
    .{ .id = "DT-5", .rule = "compatibility mode remains available where practical" },
    .{ .id = "DT-6", .rule = "decision is explicitly documented as a superset exception" },
};

pub const ConstructEntry = struct {
    id: []const u8,
    construct: []const u8,
    classification: SyntaxClass,
    accepted: bool,
    same_semantics: bool,
    duo_extension_interaction: []const u8,
    formatter_behavior: []const u8,
    test_coverage: []const u8,
    /// When true, this construct must never be classified actually_deprecated.
    permanent_lua: bool = false,
};

/// §1.3 compatibility matrix (minimum coverage; expanded over time).
pub const constructs: []const ConstructEntry = &.{
    .{
        .id = "LS-0",
        .construct = "long string [[...]]",
        .classification = .lua_and_duo_canonical,
        .accepted = true,
        .same_semantics = true,
        .duo_extension_interaction = "raw shell: use [=[ ]=] when Bash contains ]]; outer [[ for bash without ]]",
        .formatter_behavior = "preserve delimiter level and content",
        .test_coverage = "lexer level 0 + parser @c.emit + control_defaults_mem.duo",
        .permanent_lua = true,
    },
    .{
        .id = "LS-1",
        .construct = "long string [=[...]=]",
        .classification = .lua_and_duo_canonical,
        .accepted = true,
        .same_semantics = true,
        .duo_extension_interaction = "nested ]] inside content without closing",
        .formatter_behavior = "preserve delimiter level",
        .test_coverage = "lexer level 1 + control_defaults_mem.duo",
        .permanent_lua = true,
    },
    .{
        .id = "LS-2",
        .construct = "long string [==[...]==] (arbitrary = count)",
        .classification = .lua_and_duo_canonical,
        .accepted = true,
        .same_semantics = true,
        .duo_extension_interaction = "none",
        .formatter_behavior = "preserve delimiter level",
        .test_coverage = "lexer level 2 + mismatch error",
        .permanent_lua = true,
    },
    .{
        .id = "LC-0",
        .construct = "long comment --[[...]]",
        .classification = .lua_and_duo_canonical,
        .accepted = true,
        .same_semantics = true,
        .duo_extension_interaction = "none",
        .formatter_behavior = "preserve",
        .test_coverage = "lexer skip_ws",
        .permanent_lua = true,
    },
    .{
        .id = "LC-1",
        .construct = "long comment --[=[...]=]",
        .classification = .lua_and_duo_canonical,
        .accepted = true,
        .same_semantics = true,
        .duo_extension_interaction = "comment may contain ]] without closing",
        .formatter_behavior = "preserve",
        .test_coverage = "lexer gate",
        .permanent_lua = true,
    },
    .{
        .id = "SS-0",
        .construct = "short quoted strings \"...\" and '...'",
        .classification = .lua_and_duo_canonical,
        .accepted = true,
        .same_semantics = true,
        .duo_extension_interaction = "Duo interpolation in .duo only when not Lua-compat path",
        .formatter_behavior = "preserve escapes",
        .test_coverage = "lexer decode_lua_short_string",
        .permanent_lua = true,
    },
    .{
        .id = "CF-0",
        .construct = "if cond then ... end",
        .classification = .lua_canonical,
        .accepted = true,
        .same_semantics = true,
        .duo_extension_interaction = "Duo prefers omitting then; both accepted permanently",
        .formatter_behavior = "canonical Duo may omit then; never strip from Lua-compat input",
        .test_coverage = "pass21 proveIfWithoutThen + lua superset gate with then",
        .permanent_lua = true,
    },
    .{
        .id = "CF-1",
        .construct = "while/for ... do ... end",
        .classification = .lua_canonical,
        .accepted = true,
        .same_semantics = true,
        .duo_extension_interaction = "Duo prefers omitting loop do",
        .formatter_behavior = "canonical Duo may omit do",
        .test_coverage = "pass21 proveLoopWithoutDo",
        .permanent_lua = true,
    },
    .{
        .id = "FN-0",
        .construct = "local function name(...) ... end",
        .classification = .lua_canonical,
        .accepted = true,
        .same_semantics = true,
        .duo_extension_interaction = "Duo bare declaration add = (a,b) ...",
        .formatter_behavior = "preserve Lua form when present",
        .test_coverage = "partial",
        .permanent_lua = true,
    },
    .{
        .id = "CL-0",
        .construct = "parenthesized call f(a, b)",
        .classification = .lua_and_duo_canonical,
        .accepted = true,
        .same_semantics = true,
        .duo_extension_interaction = "parenless calls extend, do not replace",
        .formatter_behavior = "preserve when required for precedence",
        .test_coverage = "partial",
        .permanent_lua = true,
    },
    .{
        .id = "CR-0",
        .construct = "coroutines coroutine.create/yield/resume",
        .classification = .lua_canonical,
        .accepted = true,
        .same_semantics = true,
        .duo_extension_interaction = "unified execution graph may specialize; never remove API",
        .formatter_behavior = "preserve",
        .test_coverage = "lua_readiness partial",
        .permanent_lua = true,
    },
};

pub const Workstream = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,
    priority: u8,
};

/// Priority order from superset expansion spec (P0–P9).
pub const workstreams: []const Workstream = &.{
    .{ .id = "LS-P0", .title = "Preserve Lua long strings/comments; audit accidental subset decisions", .status = "partial", .priority = 0 },
    .{ .id = "LS-P1", .title = "Lua 5.5 compatibility corpus + differential testing", .status = "partial", .priority = 1 },
    .{ .id = "LS-P2", .title = "Unified call architecture; shell tails cannot break long lexing", .status = "partial", .priority = 2 },
    .{ .id = "LS-P3", .title = "Execution graph + task semantics", .status = "open", .priority = 3 },
    .{ .id = "LS-P4", .title = "@spawn @all @race on ordinary calls", .status = "open", .priority = 4 },
    .{ .id = "LS-P5", .title = "@parallel regions + legality proof", .status = "open", .priority = 5 },
    .{ .id = "LS-P6", .title = "Scheduler and representation candidates", .status = "open", .priority = 6 },
    .{ .id = "LS-P7", .title = "Streams, channels, selection via race", .status = "open", .priority = 7 },
    .{ .id = "LS-P8", .title = "Determinism, replay, real-time policies", .status = "open", .priority = 8 },
    .{ .id = "LS-P9", .title = "Ward + Go benchmark proofs", .status = "open", .priority = 9 },
};

pub fn findConstruct(id: []const u8) ?ConstructEntry {
    for (constructs) |c| {
        if (std.mem.eql(u8, c.id, id)) return c;
    }
    return null;
}

pub fn permanentLuaConstructCount() usize {
    var n: usize = 0;
    for (constructs) |c| {
        if (c.permanent_lua) n += 1;
    }
    return n;
}

test "lua_superset_catalog: schema and matrix" {
    try std.testing.expectEqualStrings("lua-superset-catalog-v0", SCHEMA_VERSION);
    try std.testing.expect(constructs.len >= 10);
    try std.testing.expect(deprecation_threshold.len == 6);
    try std.testing.expect(workstreams.len == 10);
    const ls0 = findConstruct("LS-0").?;
    try std.testing.expect(ls0.permanent_lua);
    try std.testing.expectEqual(.lua_and_duo_canonical, ls0.classification);
}
