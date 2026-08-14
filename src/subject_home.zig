//! SUBJECT-ONE: which builtin home owns a relation, so `subject:relation(x)`
//! and `home.relation(subject, x)` resolve to the same application.
//!
//! WHY THIS EXISTS. The canon makes subject-first the PREFERRED face whenever
//! the subject is possessed — `r(subject, a)` and `subject:r(a)` are one edge
//! written from two ends. The operation-first face resolved through per-module
//! name lists; the subject-first face resolved through a hardcoded allow-list of
//! about a dozen method names in `methodCallResolved`. So `math.floor(x)`
//! compiled and `x:floor()` did not, and `string.split(s, ",")` compiled and
//! `s:split(",")` did not — the canonical spelling was the one that failed.
//!
//! That single gap accounted for 202 of the 337 files in this repo that do not
//! type-check: 60% of them, all reporting "'split'/'floor'/'push' is neither a
//! descriptor nor a callable".
//!
//! ONE ORIGIN, consulted by both the resolver and the lowerer, so the two faces
//! cannot drift apart again — which is the whole point of the law.

const std = @import("std");

pub const Home = enum { string, math, table };

const string_members = [_][]const u8{
    "sub",   "match", "byte",    "len",    "char",   "rep",
    "lower", "upper", "reverse", "format", "gsub",   "gmatch",
    "split", "trim",  "has",     "tail",   "starts", "ends",
    "find",  "concat",
};

const math_members = [_][]const u8{
    "sqrt", "sin",  "cos",   "tan", "exp",   "log",
    "ceil", "max",  "min",   "abs", "floor", "fmod",
    "pow",  "sign", "round",
};

const table_members = [_][]const u8{
    "insert", "remove", "sort", "unpack", "push", "pop", "concat",
};

/// `concat` is a member of BOTH homes. A name two homes claim is not resolved
/// from the name alone — the receiver has to say which. Guessing here would
/// silently pick a different relation than the writer meant, which is the one
/// failure mode this convergence exists to avoid.
///
/// A contested name MUST also appear in each home that claims it, or
/// `homeOfWithReceiver` returns null for both receivers and the name resolves
/// nowhere. It did: `concat` was listed here and in neither member list, so the
/// test asserting the receiver settles it panicked on a null.
const contested = [_][]const u8{"concat"};

fn has(list: []const []const u8, name: []const u8) bool {
    for (list) |m| if (std.mem.eql(u8, m, name)) return true;
    return false;
}

pub fn isContested(method: []const u8) bool {
    return has(&contested, method);
}

/// The home that owns `method`, when exactly one does. Null when no home claims
/// it (an ordinary user relation) or when more than one does (see `contested`).
pub fn homeOf(method: []const u8) ?Home {
    if (isContested(method)) return null;
    if (has(&string_members, method)) return .string;
    if (has(&math_members, method)) return .math;
    if (has(&table_members, method)) return .table;
    return null;
}

/// The home for a contested name once the receiver has settled it.
pub fn homeOfWithReceiver(method: []const u8, receiver_is_str: bool) ?Home {
    if (isContested(method)) {
        if (receiver_is_str and has(&string_members, method)) return .string;
        if (!receiver_is_str and has(&table_members, method)) return .table;
        return null;
    }
    return homeOf(method);
}

pub fn homeName(h: Home) []const u8 {
    return switch (h) {
        .string => "string",
        .math => "math",
        .table => "table",
    };
}

test "subject home: uncontested names resolve to one home" {
    try std.testing.expectEqual(Home.math, homeOf("floor").?);
    try std.testing.expectEqual(Home.string, homeOf("split").?);
    try std.testing.expectEqual(Home.table, homeOf("push").?);
}

test "subject home: a name two homes claim is not resolved from the name" {
    try std.testing.expect(homeOf("concat") == null);
    try std.testing.expect(isContested("concat"));
    // The receiver settles it, and only then.
    try std.testing.expectEqual(Home.string, homeOfWithReceiver("concat", true).?);
    try std.testing.expectEqual(Home.table, homeOfWithReceiver("concat", false).?);
}

test "subject home: an ordinary relation belongs to no builtin home" {
    try std.testing.expect(homeOf("recognize") == null);
    try std.testing.expect(!isContested("recognize"));
}
