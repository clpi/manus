//! COLLECTION-RELATION-ONE — the subject-oriented relation algebra on tables,
//! and the ONE owner of what its shapes are.
//!
//! `subject-section-one.md` §8 measured the hole this fills: `xs:any(…)`,
//! `xs:map(…)`, `xs:filter(…)` all answered *"neither a descriptor nor a
//! callable"*, `:any(`/`:all(`/`:fold(` had ZERO corpus call sites, and a table
//! did not even admit `:len()` while a string did. §8's ordering consequence is
//! why this module exists before any section grammar: a subject section is
//! *defined* as the section whose missing subject is supplied by the CONSUMING
//! RELATION, so with no consuming relation there is nothing to supply the hole.
//!
//! # WHAT A RELATION HERE IS, AND WHAT IT IS NOT
//!
//! Each name states a DIFFERENT QUESTION (`subject-section-one.md` §4,
//! QUESTION-DENSITY-ONE) and that difference is the entire value. `any` is
//! EXISTENTIAL — it may stop at the first witness. Writing it as `filter`
//! followed by a non-empty test would destroy exactly the thing that makes it
//! worth having, so the question is carried all the way to realization and the
//! early exit is emitted from the question, not recovered from a loop.
//!
//! `protocol-projection-one.md` §3 (ITERATION-ONE) binds the other side:
//!
//! > `for(xs) (x)` is ONE iteration application and MUST NOT be defined as
//! > `xs:iter()` followed by repeated `cursor:next()`.
//!
//! So there is no iterator here, no protocol object, no vtable and no indirect
//! dispatch — §6 pins all four at 0. The body relation is a LITERAL AT THE
//! APPLICATION SITE and is FUSED into the iteration; it is never built as a
//! value and never passed. That is not a shortcut around the missing
//! relation-value capability (measured absent — see `docs/collection-relation.md`);
//! it is what §6 requires, and it is why `any` can land without it.
//!
//! # WHY THIS MODULE EXISTS RATHER THAN FOUR PREDICATES
//!
//! Four consumers must agree on exactly which source shapes are collection
//! applications — sema (does it type-check), `native_bootstrap` (is the
//! application resolved), the codegen precheck (is the module native), and
//! `dnir_lower` (emit it). Four copies of one shape test is the drift shape this
//! tree has been bitten by repeatedly (`@c.emit` versus `@comp.c.emit`;
//! `select_chain_max` declared twice "MUST equal"). One owner, four readers.

const std = @import("std");
const ast = @import("ast.zig");

/// The QUESTION a collection relation states. Adding a row here is adding a
/// question, never a synonym: a name earns a row only when no other row can
/// answer what it asks. `find` is not `any` with a different result — `any`
/// admits a representation that answers without producing a witness at all.
pub const Question = enum {
    /// EXISTENTIAL. `xs:any(p)` — does SOME element satisfy `p`?
    /// Result `bool`. May stop at the first witness; may answer at compile
    /// time; may answer with no iteration at all.
    any,

    /// How many operands the relation takes, excluding the subject.
    pub fn arity(self: Question) usize {
        return switch (self) {
            .any => 1,
        };
    }

    /// The source spelling. LAW-16: lowercase, singular, ONE irreducible word.
    pub fn name(self: Question) []const u8 {
        return switch (self) {
            .any => "any",
        };
    }
};

/// The question a relation name states, or null when the name is not one.
///
/// NAME-KEYED AND THAT IS DELIBERATE HERE, unlike protocol inference. This is
/// not "a member named `next` makes a thing iterable" — the forbidden direction
/// in `protocol-projection-one.md` §3.1. These are RELATION IDENTITIES the
/// language declares, the same way `len` is one; the spelling names the
/// question rather than being sniffed for a capability.
pub fn questionOf(relation: []const u8) ?Question {
    for (rostered) |q| {
        if (std.mem.eql(u8, relation, q.name())) return q;
    }
    return null;
}

/// Every question this compiler can answer, in one place. The `name()` switch
/// and this array are the two halves of one roster; the test below walks both
/// so a row added to one and not the other fails a run rather than resolving
/// a relation nothing lowers.
pub const rostered = [_]Question{.any};

/// A collection application, decomposed once.
///
/// `param`/`body` come from the body relation written at the application site.
/// There is no closure here and no value: `body` is an expression to be lowered
/// with `param` bound to the element under test.
pub const Shape = struct {
    question: Question,
    /// The iteration SOURCE.
    subject: *const ast.Expr,
    /// The body relation's single result name — the element under test.
    param: []const u8,
    /// The body relation, as an expression. One expression, no statements.
    body: *const ast.Expr,
};

/// The collection application `expr` is, or null.
///
/// SYNTACTIC ONLY. Whether the subject is actually a table is a DESCRIPTOR
/// question and is asked by the consumers that have descriptors; asking it here
/// would put a second type authority in a shape module.
///
/// FAILS CLOSED on everything it does not yet lower, and each refusal below is
/// a real restriction rather than a formality:
///
///   * a body relation that is not written at the application site cannot be
///     fused, and a relation cannot be passed as a value on this backend at all
///     (measured; `docs/collection-relation.md` §1);
///   * more than one result name is `subject-section-one.md` §1.2's ambiguity
///     case and must be refused, not guessed;
///   * a body with statements is a region with its own exits, and `break` /
///     `continue` inside a fused predicate has no ruling yet.
pub fn shapeOf(expr: *const ast.Expr) ?Shape {
    if (expr.* != .method_call) return null;
    const mc = expr.method_call;
    const question = questionOf(mc.method) orelse return null;
    if (mc.args.len != question.arity()) return null;
    if (mc.args[0].* != .func_expr) return null;
    const fb = mc.args[0].func_expr;
    if (fb.params.len != 1) return null;
    if (fb.vararg or fb.vararg_name != null) return null;
    if (fb.type_params != null) return null;
    if (fb.is_async) return null;
    if (fb.ret_fallible) return null;
    if (fb.params[0].default_val != null) return null;
    if (fb.body.stmts.len != 0) return null;
    const body = fb.body.tail_expr orelse return null;
    return .{
        .question = question,
        .subject = mc.obj,
        .param = fb.params[0].name,
        .body = body,
    };
}

test "collection_relation: the roster answers its own names and nothing else" {
    try std.testing.expectEqual(@as(?Question, .any), questionOf("any"));
    try std.testing.expectEqual(@as(?Question, null), questionOf("anything"));
    try std.testing.expectEqual(@as(?Question, null), questionOf("an"));
    try std.testing.expectEqual(@as(?Question, null), questionOf(""));
    // NOT YET ROSTERED, and the test says so out loud: a lane adding one of
    // these must add its lowering in the same change, because `questionOf`
    // answering is what makes sema stop refusing.
    for ([_][]const u8{ "all", "find", "filter", "map", "fold", "each" }) |pending| {
        try std.testing.expectEqual(@as(?Question, null), questionOf(pending));
    }
}

test "collection_relation: arity and spelling agree with the roster" {
    try std.testing.expectEqual(@as(usize, 1), Question.any.arity());
    try std.testing.expectEqualStrings("any", Question.any.name());
    // Every rostered question resolves from its own spelling. A row added to
    // `rostered` without a `name()` arm, or the reverse, breaks here.
    for (rostered) |q| {
        try std.testing.expectEqual(@as(?Question, q), questionOf(q.name()));
        try std.testing.expect(q.arity() >= 1);
    }
}
