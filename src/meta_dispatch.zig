/// Unified meta-combinator dispatch (— architectural reconciliation).
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
///   Step 2: Have fold_meta_string_expr delegate to dispatch() (DONE)
///   Step 3: Have comptimeMetaHook delegate to dispatch() (DONE)
///   Step 4: Have maybe_emit_meta_string_call delegate to dispatch() (DONE)
///   Step 5: Remove duplicate inline match tables from codegen (DONE — agent/catalog hooks remain)
///   Step 6: Centralize provenance in dispatchAtSite() → transform_engine (DONE)
///   Step 7: Full evaluation ownership in transform_engine Phase 2 (OPEN — execution stays in meta_codegen hooks)
const std = @import("std");
const meta_codegen = @import("meta_codegen.zig");
const comptime_eval = @import("comptime.zig");
const transform_engine = @import("transform_engine.zig");

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
///
/// `min_args`/`max_args` MUST cover every arity `meta_codegen.applyMetaCombinatorHook`
/// implements. `dispatchAtSite` checks this table *before* it calls the hook, so
/// a row that under-declares its arity makes the combinator unreachable — and
/// silently: the fold is skipped, the call falls through to the runtime path,
/// and the generated C invokes an undeclared `__comptimeproduct` symbol. Nine
/// rows were in that state (`__comptimeproduct` said 2 while its hook takes 3;
/// `__comptimenfold` said 3 while its hook takes 2; `__metahyper` said 2 against
/// a 6-argument hook). See the "arity covers every hook form" test below, which
/// is what should catch the next one.
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
    .{ .internal_name = "__comptimenfold", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__comptimeproduct", .min_args = 3, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__comptimetensor", .min_args = 2, .max_args = 4, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__comptimefixpoint", .min_args = 2, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__comptimefanout", .min_args = 3, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metaexpand", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metaceiling", .min_args = 3, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metaomni", .min_args = 3, .max_args = 4, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metaburst", .min_args = 3, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metatranscend", .min_args = 4, .max_args = 5, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metainfinity", .min_args = 5, .max_args = 5, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metahyper", .min_args = 6, .max_args = 6, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metagrammar", .min_args = 1, .max_args = 2, .first_arg_string = true, .last_arg_callback = false },
    .{ .internal_name = "__metaweave", .min_args = 2, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metatemplate", .min_args = 2, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metagenerate", .min_args = 2, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__metascheme", .min_args = 1, .max_args = 3, .first_arg_string = true, .last_arg_callback = false },
    .{ .internal_name = "__metaschemeclauses", .min_args = 1, .max_args = 2, .first_arg_string = true, .last_arg_callback = false },
    .{ .internal_name = "__derivemap", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__derivepower", .min_args = 2, .max_args = 2, .first_arg_string = true, .last_arg_callback = true },
    .{ .internal_name = "__deriveproduct", .min_args = 3, .max_args = 3, .first_arg_string = true, .last_arg_callback = true },
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

/// Unified combinator evaluation — single entry for fold, comptime hook, and emit paths.
pub fn dispatch(
    host: meta_codegen.Host,
    internal_name: []const u8,
    args: []const comptime_eval.Value,
    alloc: std.mem.Allocator,
) Result {
    return dispatchAtSite(host, internal_name, args, alloc, null);
}

/// Like `dispatch`, but logs transform provenance when `site` is set (G-061 / P6-07).
pub fn dispatchAtSite(
    host: meta_codegen.Host,
    internal_name: []const u8,
    args: []const comptime_eval.Value,
    alloc: std.mem.Allocator,
    site: ?transform_engine.SiteKind,
) Result {
    if (!isCombinator(internal_name)) return .not_applicable;
    if (!validArgCount(internal_name, args.len)) return .not_applicable;
    if (!meta_codegen.canApplyMetaCombinatorHook(internal_name)) return .not_applicable;
    const value = meta_codegen.applyMetaCombinatorHook(host, internal_name, args, alloc) orelse return .eval_failed;
    const result: Result = switch (value) {
        .string => .{ .string = value.string },
        .int => .{ .int = value.int },
        .bool => .{ .boolean = value.bool },
        else => .eval_failed,
    };
    if (site) |s| {
        if (result == .string) {
            var ibuf: [128]u8 = undefined;
            const input = meta_codegen.metaCombinatorProvenanceInput(internal_name, args, &ibuf) orelse "";
            transform_engine.dispatchMetaCombinator(alloc, internal_name, s, input, result.string);
        }
    }
    return result;
}

/// True when `dispatch()` can handle this internal hook name.
pub fn canDispatch(internal_name: []const u8) bool {
    return isCombinator(internal_name) and meta_codegen.canApplyMetaCombinatorHook(internal_name);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test "meta_dispatch: canDispatch tier-1 wired hooks" {
    try std.testing.expect(canDispatch("__comptimemap"));
    try std.testing.expect(canDispatch("__deriveproduct"));
    try std.testing.expect(canDispatch("__comptimefixpoint"));
    try std.testing.expect(!canDispatch("__metacatalog"));
    try std.testing.expect(!canDispatch("__nonexistent"));
}

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

test "meta_dispatch: arity covers every hook form" {
    const testing = std.testing;
    // Each row is the arity (or arities) `meta_codegen.applyMetaCombinatorHook`
    // actually implements, read off its `args.len ==` guards. The table above is
    // consulted BEFORE the hook, so any arity here that the table rejects makes
    // the combinator dead — the defect that left `__comptimeproduct` emitting a
    // runtime call to an undeclared symbol instead of folding to a C string.
    const Form = struct { name: []const u8, arity: usize };
    const hook_forms = [_]Form{
        .{ .name = "__comptimemap", .arity = 2 },
        .{ .name = "__comptimeeach", .arity = 2 },
        .{ .name = "__comptimematch", .arity = 2 },
        .{ .name = "__comptimetabulate", .arity = 2 },
        .{ .name = "__comptimeinterpolate", .arity = 2 },
        .{ .name = "__comptimezip", .arity = 3 },
        .{ .name = "__comptimepower", .arity = 2 },
        .{ .name = "__comptimechoose", .arity = 3 },
        .{ .name = "__comptimepermute", .arity = 2 },
        .{ .name = "__comptimenfold", .arity = 2 },
        .{ .name = "__comptimeproduct", .arity = 3 },
        .{ .name = "__deriveproduct", .arity = 3 },
        .{ .name = "__comptimetensor", .arity = 3 },
        .{ .name = "__comptimetensor", .arity = 4 },
        .{ .name = "__comptimefanout", .arity = 3 },
        .{ .name = "__metaceiling", .arity = 3 },
        .{ .name = "__metaomni", .arity = 3 },
        .{ .name = "__metaomni", .arity = 4 },
        .{ .name = "__metaburst", .arity = 3 },
        .{ .name = "__metatranscend", .arity = 4 },
        .{ .name = "__metatranscend", .arity = 5 },
        .{ .name = "__metainfinity", .arity = 5 },
        .{ .name = "__metahyper", .arity = 6 },
        .{ .name = "__metagrammar", .arity = 2 },
    };
    for (hook_forms) |f| {
        if (!isCombinator(f.name)) return error.MissingDispatchRow;
        testing.expect(validArgCount(f.name, f.arity)) catch |e| {
            std.debug.print("combinator {s} implements arity {d}, table rejects it\n", .{ f.name, f.arity });
            return e;
        };
    }
    // Positive control: the check must be able to fail. No combinator declares a
    // 99-argument form, so this must be rejected — otherwise the loop above is
    // asserting nothing.
    try testing.expect(!validArgCount("__comptimeproduct", 99));
}

test "meta_dispatch: wired combinators registered in transform_engine" {
    const testing = std.testing;
    for (combinators) |entry| {
        const public_name = transform_engine.publicNameForInternal(entry.internal_name) orelse
            return error.MissingTransformRegistryEntry;
        try testing.expect(transform_engine.isRegisteredTransform(public_name));
    }
}
