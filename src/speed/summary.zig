//! Function summaries as first-class facts.
//!
//! For each callable in the semantic graph, computes and retains:
//! - terminates: yes/no/unknown
//! - has_observable_effects: yes/no
//! - const_result: exact i64 value or null
//! - arg_independent: yes/no
//!
//! Consumers (call-site lowering) read these WITHOUT the callee body.
//! All facts are derived from existing authorities:
//! - purity from `graph_query.effectFreeCalleeClosure`
//! - const/arg-independence from `comptime.foldRelationBody`
//! - param mentions from `lower.exprMentionsIdent` (syntactic, conservative)
//!
//! This module introduces no new semantic authority. It only caches and
//! re-exposes what the graph and evaluator already prove.

const std = @import("std");
const ast = @import("../ast.zig");
const semantic_graph = @import("../graph.zig");
const graph_query = @import("../graph_query.zig");
const comptime_eval = @import("../comptime.zig");
const lower = @import("../graph/lower.zig");

/// Whether a callable terminates.
pub const Termination = enum { yes, no, unknown };

/// A first-class summary of a callable, retained for consumers.
pub const Summary = struct {
    /// Does the callable terminate?
    terminates: Termination,
    /// Does it have observable effects?
    has_effects: bool,
    /// If the result is a known constant, its value.
    const_value: ?i64,
    /// Is the result independent of the arguments?
    arg_independent: bool,
};

/// Cache of computed summaries, keyed by callable entity.
/// Owned by the lowering context; lives for one module lowering.
pub const Cache = struct {
    alloc: std.mem.Allocator,
    map: std.AutoHashMapUnmanaged(semantic_graph.id, Summary) = .empty,

    pub fn init(alloc: std.mem.Allocator) Cache {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *Cache) void {
        self.map.deinit(self.alloc);
    }

    /// Get the summary for a callable, computing and retaining it if needed.
    /// Returns null if the callable has no declaration (cannot summarize).
    pub fn getOrCompute(
        self: *Cache,
        graph: *const semantic_graph.SemanticGraph,
        callable: semantic_graph.id,
    ) ?Summary {
        if (self.map.get(callable)) |s| return s;
        const s = computeSummary(self.alloc, graph, callable) orelse return null;
        self.map.put(self.alloc, callable, s) catch return null;
        return s;
    }
};

/// Compute the summary for a callable from existing authorities.
/// Returns null if the callable cannot be summarized (no declaration).
fn computeSummary(
    alloc: std.mem.Allocator,
    graph: *const semantic_graph.SemanticGraph,
    callable: semantic_graph.id,
) ?Summary {
    // Provenance, not lookup: the graph recorded the declaration at lift.
    const decl = graph_query.relationDeclaration(graph, callable) orelse return null;
    const body = &decl.func.body;

    // PURITY from the effect authority. If the closure is provably effect-free,
    // the body has no observable effects. Null means refused (may have effects).
    var has_effects: bool = true;
    if (graph_query.effectFreeCalleeClosure(graph, alloc, callable, body)) |maybe_closure| {
        if (maybe_closure) |closure| {
            alloc.free(closure);
            has_effects = false;
        } else {
            // Null means refused: may have effects.
            has_effects = true;
        }
    } else |_| {
        // On error, fail closed: assume effects.
        has_effects = true;
    }

    var const_value: ?i64 = null;
    var terminates: Termination = .unknown;
    var arg_independent: bool = false;

    if (!has_effects) {
        // CONSTANT: try the authoritative fold. A successful fold proves
        // the result is constant, arg-independent (params were unbound but
        // never referenced), and terminating (we just evaluated it).
        if (comptime_eval.foldRelationBody(alloc, graph, callable, &decl.func)) |k| {
            const_value = k;
            terminates = .yes;
            arg_independent = true;
        } else {
            // Pure but not foldable to a constant (e.g., references params).
            // ARG-INDEPENDENCE via syntactic check: if no param is mentioned,
            // the result cannot depend on arguments.
            arg_independent = true;
            for (decl.func.params) |param| {
                if (lower.blockMentionsIdent(body, param.name)) {
                    arg_independent = false;
                    break;
                }
            }
            // Pure and arg-independent but not const? That means the fold
            // failed for another reason (e.g., unsupported construct).
            // Keep const_value=null; the summary is still useful for DCE.
        }
    }

    return .{
        .terminates = terminates,
        .has_effects = has_effects,
        .const_value = const_value,
        .arg_independent = arg_independent,
    };
}

/// Try to fold a call site to a constant using the callee's summary.
/// Returns the constant if the call is pure and its result is known.
///
/// This is the consumer entry point. It does NOT need the callee body —
/// only the retained summary. For arg-dependent pure calls with constant
/// arguments, it falls back to `foldValueExpr` (the authoritative folder).
pub fn foldCallSite(
    cache: *Cache,
    graph: *const semantic_graph.SemanticGraph,
    caller: ?semantic_graph.id,
    call_expr: *const ast.Expr,
) ?i64 {
    if (call_expr.* != .call) return null;
    const c = call_expr.call;

    // The callee must be a named function for summary lookup.
    if (c.func.* != .name) return null;
    const name = c.func.name.ident;

    // Resolve the name to a callable entity via the graph.
    // We need the caller for home resolution; if absent, we cannot resolve.
    const caller_id = caller orelse return null;
    const callee = graph.resolveInHome(caller_id, name, .func) orelse return null;

    // Get the retained summary (compute if needed).
    const summary = cache.getOrCompute(graph, callee) orelse return null;

    // Effectful calls are never folded.
    if (summary.has_effects) return null;

    // Pure and arg-independent with known const: the answer.
    // This handles `sum45(0)` → 45 without evaluating at the call site.
    if (summary.const_value) |k| return k;

    // Pure but arg-dependent: if the authoritative folder can evaluate
    // the call with its actual arguments, use it. This handles
    // `double(21)` → 42.
    if (!summary.arg_independent) {
        return comptime_eval.foldValueExpr(cache.alloc, graph, caller_id, call_expr);
    }

    return null;
}
