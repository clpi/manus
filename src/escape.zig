//! Escape analysis query functions.
//! Consumes escape status fields populated by sema and provides queries
//! for ARC pruning and stack/heap allocation decisions.

const std = @import("std");
const Symbol = @import("sema.zig").Symbol;
const RT = @import("types.zig").ResolvedType;

/// A variable can be stack-allocated if it never escapes its scope:
/// - not global
/// - not captured by a closure
/// - not had its address taken (stored in table, passed as pointer)
/// - not assigned after init in a way that escapes
pub fn canStackAllocate(sym: *const Symbol) bool {
    if (sym.is_global) return false;
    if (sym.escapes) return false;
    if (sym.captured_by_closure) return false;
    if (sym.address_taken) return false;
    return true;
}

/// ARC retain/release can be pruned for variables that never escape.
/// If a variable doesn't escape, its retain/release is dead code —
/// the object will be freed when the stack frame unwinds anyway.
pub fn shouldPruneArc(sym: *const Symbol) bool {
    if (sym.is_global) return false;
    if (sym.escapes) return false;
    if (sym.captured_by_closure) return false;
    return true;
}

/// Check if a type needs ARC management (ownership tracking).
/// This mirrors arc.needsArc and codegen.codegen_needs_arc.
pub fn typeNeedsArc(rt: RT) bool {
    return switch (rt) {
        .str, .array, .pointer, .func, .@"struct" => true,
        .result, .option, .channel, .instantiated, .generic_param => true,
        else => false,
    };
}

test "escape: non-escaping local can be stack allocated" {
    var sym = Symbol{
        .typ = .void,
        .is_const = false,
    };
    try std.testing.expect(canStackAllocate(&sym));
    try std.testing.expect(shouldPruneArc(&sym));
}

test "escape: global cannot be stack allocated" {
    var sym = Symbol{
        .typ = .void,
        .is_const = false,
        .is_global = true,
    };
    try std.testing.expect(!canStackAllocate(&sym));
    try std.testing.expect(!shouldPruneArc(&sym));
}

test "escape: captured local cannot be stack allocated" {
    var sym = Symbol{
        .typ = .void,
        .is_const = false,
        .captured_by_closure = true,
        .escapes = true,
    };
    try std.testing.expect(!canStackAllocate(&sym));
    try std.testing.expect(!shouldPruneArc(&sym));
}

test "escape: address-taken local cannot be stack allocated" {
    var sym = Symbol{
        .typ = .void,
        .is_const = false,
        .address_taken = true,
    };
    try std.testing.expect(!canStackAllocate(&sym));
    // address_taken doesn't affect ARC pruning — the value might not escape
    try std.testing.expect(shouldPruneArc(&sym));
}

test "escape: typeNeedsArc for owned types" {
    try std.testing.expect(typeNeedsArc(.str));
    try std.testing.expect(!typeNeedsArc(.i32));
    try std.testing.expect(!typeNeedsArc(.f64));
    try std.testing.expect(!typeNeedsArc(.bool));
    try std.testing.expect(!typeNeedsArc(.void));
}