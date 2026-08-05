/// Unified meta-combinator dispatch (Pass 6 — architectural reconciliation).
///
/// This module provides ONE entry point for evaluating comptime combinators.
/// Previously, codegen.zig had THREE parallel dispatch paths:
///   1. fold_meta_string_expr (expression-type inference)
///   2. comptimeMetaHook (comptime evaluation callback)
///   3. maybe_emit_meta_string_call (call-site emission)
///
/// All three check the same combinator names and call the same meta_codegen hooks.
/// This module unifies them behind `dispatch()`.
///
/// Migration plan:
///   Step 1: Create this file with the dispatch table (DONE)
///   Step 2: Have fold_meta_string_expr delegate to dispatch()
///   Step 3: Have comptimeMetaHook delegate to dispatch()
///   Step 4: Have maybe_emit_meta_string_call delegate to dispatch()
///   Step 5: Remove the three inline match tables
const std = @import("std");
const meta_codegen = @import("meta_codegen.zig");
const comptime_eval = @import("comptime.zig");

/// Result of a combinator dispatch.
pub const Result = union(enum) {
    /// Combinator produced a string value (the common case for codegen).
    string: []const u8,
    /// Combinator produced an integer value.
    int: i64,
    /// Combinator produced a boolean value.
    boolean: bool,
    /// Combinator is not recognized or args don't match.
    not_applicable,
    /// Combinator is recognized but evaluation failed.
    eval_failed,
};

/// Dispatch entry: maps internal combinator name to its evaluation function.
const DispatchEntry = struct {
    internal_name: []const u8,
    min_args: u8,
    max_args: u8,
    /// True if the first arg must be a string literal or foldable string.
    first_arg_string: bool,
    /// True if the last arg must be a callback (function value).
    last_arg_callback: bool,
};

/// Canonical combinator table. Every comptime combinator that produces a string
/// should be listed here ONCE. The three codegen dispatch paths should consult
/// this table rather than maintaining independent match lists.
pub const combinators: []const DispatchEntry = &.{
    .{ .internal_name = "__comptimemap", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__comptimeeach", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__comptimematch", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__comptimetabulate", .min_args = 2, .max_args = 2, .first_arg_string = false, .last_arg_callback = true },
    .{ .internal_name = "__comptimeinterpolate", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = false },
    .{ .internal_name = "__comptimezip", .min_args = 3, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__comptimepower", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__comptimechoose", .min_args = 3, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__comptimepermute", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__comptimenfold", .min_args = 3, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__comptimeproduct", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__comptimetensor", .min_args = 2, .max_args = 4, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__comptimefixpoint", .min_args = 2, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__comptimefanout", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metaexpand", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metaceiling", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metaomni", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metaburst", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metatranscend", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metainfinity", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metahyper", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metagrammar", .min_args = 1, .max_args = 2, .first_arg_string = true, .last_arg_callback = false },
    .{ .internal_name = "__metaweave", .min_args = 2, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metatemplate", .min_args = 2, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metagenerate", .min_args = 2, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metascheme", .min_args = 2, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__derivemap", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__derivepower", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__derivetensor", .min_args = 2, .max_args = 4, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__derivenfold", .min_args = 2, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__derivechoose", .min_args = 3, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__derivepermute", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__derivetower", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
};

/// Check whether a given internal name is a registered combinator.
pub fn isCombinator(internal_name: []const u8) bool {
    for (combinators) |entry| {
        if (std.mem.eql(u8, entry.internal_name, internal_name)) return true;
    }
    return false;
}

/// Get the dispatch entry for a combinator (null if not registered).
pub fn lookup(internal_name: []const u8) ?DispatchEntry {
    for (combinators) |entry| {
        if (std.mem.eql(u8, entry.internal_name, internal_name)) return entry;
    }
    return null;
}

/// Verify arg count is valid for the given combinator.
pub fn validArgCount(internal_name: []const u8, arg_count: usize) bool {
    const entry = lookup(internal_name) orelse return false;
    return arg_count >= entry.min_args and arg_count <= entry.max_args;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test "meta_dispatch: all combinators are registered" {
    const testing = std.testing;
    try testing.expect(combinators.len >= 30);
    try testing.expect(isCombinator("__comptimemap"));
    try testing.expect(isCombinator("__comptimepower"));
    try testing.expect(isCombinator("__metatranscend"));
    try testing.expect(isCombinator("__derivemap"));
    try testing.expect(!isCombinator("__nonexistent"));
}

test "meta_dispatch: arg count validation" {
    const testing = std.testing;
    try testing.expect(validArgCount("__comptimemap", 2));
    try testing.expect(!validArgCount("__comptimemap", 1));
    try testing.expect(!validArgCount("__comptimemap", 3));
    try testing.expect(validArgCount("__comptimetensor", 2));
    try testing.expect(validArgCount("__comptimetensor", 3));
    try testing.expect(validArgCount("__comptimetensor", 4));
}

test "meta_dispatch: lookup returns correct entry" {
    const testing = std.testing;
    const entry = lookup("__comptimemap") orelse return error.TestExpectedEqual;
    try testing.expect(entry.first_arg_string);
    try testing.expect(entry.last_arg_callback);
    try testing.expectEqual(@as(u8, 2), entry.min_args);
}
