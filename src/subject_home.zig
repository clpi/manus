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

pub const Home = enum { string, math, table, io, testing, os };

const string_members = [_][]const u8{
    "sub",   "match", "byte",    "len",    "char",   "rep",
    "lower", "upper", "reverse", "format", "gsub",   "gmatch",
    "split", "trim",  "has",     "tail",   "starts", "ends",
    "find",  "concat",
};

const math_members = [_][]const u8{
    "sqrt", "sin",  "cos",   "tan", "exp",   "log",
    "ceil", "max",  "min",   "abs", "floor", "fmod",
    "pow",  "sign", "round", "random", "sinh", "cosh", "tanh",
    "asin", "acos", "atan", "atan2",
};

/// `io` is an ordinary world VALUE and a legitimate subject (world
/// reconciliation v2), so its relations resolve subject-first like any other.
///
/// These were held out while the ruling was open, because the checked-in spec
/// and the incoming ruling disagreed and a live gate failed on `io:read(`.
/// Settling that here, in a table nobody would think to look in, would have
/// decided a language question as a side effect. The ruling is now closed and
/// the three conflicting sites are retracted, so they resolve.
///
/// WHAT THIS TABLE IS, AND WHAT IT IS NOT. `io:write(x)` is not a world-specific
/// call. `io` PROJECTS to whatever writable-conformant instance the world
/// supplies, and `:write` dispatches on that instance's conformance — so
/// `io:write(x)` and `file:write(x)` are ONE relation applied to different
/// subjects, and the compiler infers which instance.
///
/// That means the right model is conformance, not a name list: a subject
/// answers `:write` because its descriptor conforms to a writable protocol, not
/// because "write" appears in a table keyed by home. This list is therefore a
/// BOOTSTRAP BRIDGE with the same shape as the namespace it replaces, one level
/// up — it resolves the face without yet resolving it for the right reason.
///
/// The distinction is observable, not academic: two files reverted during the
/// io migration precisely because `io.write(stream, x)` already had the concrete
/// instance as its subject and meant `stream:write(x)`. A conformance-driven
/// resolver would have taken those without a per-site rescue.
///
/// DELETION CONDITION: delete this table once descriptor conformance drives
/// subject-first dispatch. Until then a stream that genuinely IS the subject
/// still takes the relation directly — `file:write(data)`, never
/// `io:write(file, data)`.
const io_members = [_][]const u8{
    "flush", "seek", "lines", "setvbuf",
};

/// The TEST world's relations. Reached as `test:assert(...)`, and only in a
/// file the test world is injected into — which sema derives from where the
/// file LIVES (`test/`, `*_test.id`), not from an import or an attribute.
///
/// This is what `@comp.assert` should have been. A directive namespace is a
/// namespace; a world is a subject, and an assertion is a relation on it.
/// The `os` world's projections, reached subject-first as `os:arg(i)`.
///
/// Canonically these need no anchor: `os` is injected in the standard world, so
/// `arg(i)` at root scope is the canonical face. The subject-first spelling
/// exists for where the anchor disambiguates, and resolves to the SAME
/// projection rather than being a second mechanism. `args` is the legacy plural
/// — an identity is singular — kept only so existing source keeps working.
const os_members = [_][]const u8{
    "arg", "args", "env", "cwd", "exit", "clock", "time",
};

const testing_members = [_][]const u8{
    "assert", "refute", "equal", "differs", "raises", "near",
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
    if (has(&io_members, method)) return .io;
    if (has(&testing_members, method)) return .testing;
    if (has(&os_members, method)) return .os;
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
        .io => "io",
        .testing => "test",
        .os => "os",
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
