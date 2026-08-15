//! Facts about a positional table binding, and the representation they license.
//!
//! WHAT THIS REPLACES. The representation of a positional table is chosen today
//! by one syntactic test — `dnir_lower.stmtsBindWideTable`, "is any table
//! literal in this function wider than 32 elements". It reads no fact about the
//! table: not whether it escapes, not whether its contents are known, not
//! whether any index is a constant, not whether it is read at all. Measured on
//! this tree (`bin/idol`, AArch64 direct backend), a program whose whole answer
//! is a single addition of two constant-index reads:
//!
//!     size 30 ->   7 instructions      size 33 -> 179
//!     size 32 ->   7                   size 40 -> 214
//!
//! and a 40-element table that is NEVER READ AT ALL still costs 205, against 2
//! for `mov x0,#7 ; ret`. A 4-element table read at a constant index costs 4
//! instructions alone and 230 with an unread 40-element neighbour in the same
//! relation, because the choice is per-relation.
//!
//! WHAT THIS COMPUTES. For each positional table bound in one function body, the
//! facts below, and from them a `Representation`. The facts are collected once,
//! over the whole body, and consumed ONLY at the binding site.
//!
//! WHY THE BINDING SITE. Twice, a representation change on this tree compiled,
//! ran, and gave wrong answers. One materialized a wide table at the ACCESS
//! site, so the copy re-ran on every loop iteration and silently restored the
//! table's initial values. The API here has no access-site entry point at all:
//! `analyze` takes a function body and returns a whole-body decision, and
//! `Decisions.get` takes a name. There is nothing to call from inside a loop.
//!
//! WHY UNIFORMITY SURVIVES. The other wrong answer came from MIXING
//! representations inside one function — a loop loading from a memory-backed
//! table while storing through a select chain read a stale index. So the
//! materialized tables in a function must all share one representation. This
//! module preserves that invariant rather than trading it away: elimination
//! REMOVES tables from the materialized set, and the uniform rule is then
//! applied to what remains. `Decisions.uniform()` asserts it, and a test checks
//! that no decision map ever contains both `.registers` and `.memory`.
//!
//! Elimination is what makes that affordable. A table decided `.absent` has no
//! representation to mix: no registers, no frame region, no index temp, no
//! runtime index at all. It cannot participate in the failure because it does
//! not participate in the loop.

const std = @import("std");
const ast = @import("ast.zig");
const escape = @import("escape.zig");

/// Explicit, not inferred. Every walker below is mutually recursive with at
/// least one other, and Zig cannot infer an error set around a cycle — an
/// inferred set here is a `dependency loop` compile error, not a style choice.
const Error = std.mem.Allocator.Error;

/// Widest table a select chain can physically hold. THIS FILE OWNS IT and
/// `dnir_lower.zig` imports it — there is no second declaration to keep in step.
///
/// The comment here used to read "MUST equal `dnir_lower.select_chain_max`",
/// from when both files declared their own. That sentence was the defect, not a
/// safeguard: a comment asking two constants to agree is a note asking someone
/// to remember, and this project has the scar to prove it — `src/jit.zig` emitted
/// `arch` as `"native"` while `engine.id` compared against `"arm64"`, and roughly
/// 1,700 lines of ARM64 JIT stayed unreachable and undetected. Sharing the value
/// is a mechanism; agreeing on one is a hope.
///
/// NOTE WHAT THIS CONSTANT IS NOT. It no longer selects a representation. The
/// deciding fact is INDEX CONSTANCY, because the ordering inverts with it:
///
///                      constant index      runtime index
///   select chain             2 instrs      O(width) — 305 at width 32
///   frame memory           174 instrs      O(1)     — 206 at width 33
///
/// A runtime index goes to memory AT ANY WIDTH; a determined table with only
/// compile-time indices needs no storage at all. This survives solely as the
/// feasibility bound — registers cannot hold 2048 elements.
pub const select_chain_max: i64 = 32;

/// Compile-time integer value of an index expression, or null.
///
/// THIS IS THE PREDICATE THE LOWERING USES — `dnir_lower.intLiteralStep`, byte
/// for byte. It has to be, and the reason is the specific bug class that has
/// already bitten this tree: if the fact says "every index is constant" and the
/// lowering's own test disagrees about one of them, the binding gets a
/// representation that the access site cannot address. A slot map that disagrees
/// between the decision and the access is exactly how a table starts returning
/// the wrong element.
///
/// Deliberately narrow. It does NOT fold `t(2 + 1)` and it does NOT resolve a
/// module constant, because `intLiteralStep` does neither. Widening it here
/// without widening `intLiteralStep` in the same change would reintroduce the
/// disagreement. The routed edit in `docs/table-elimination.md` makes
/// `intLiteralStep` delegate to this function so that there is one definition.
pub fn constIndex(expr: *const ast.Expr) ?i64 {
    return switch (expr.*) {
        .int_lit => |i| i.val,
        .unop => |u| blk: {
            if (u.op != .neg or u.operand.* != .int_lit) break :blk null;
            break :blk -u.operand.int_lit.val;
        },
        else => null,
    };
}

/// The physical form a table binding is given.
pub const Representation = enum {
    /// No storage of any kind. Every read was replaced by an immediate at the
    /// access site, and `#t` by the literal width.
    absent,
    /// One frame slot (or register) per element, `t.1`, `t.2`, …; a variable
    /// index becomes a compare-and-select chain. Today's sub-threshold form.
    registers,
    /// A contiguous frame region with a base address; every access is one
    /// scaled load or store. Today's above-threshold form.
    memory,
};

/// Why a table was not eliminated. Carried so the decision can be explained and
/// so a regression in the fact collector shows up as a changed reason rather
/// than as a silently identical instruction count.
pub const Blocker = enum {
    /// Nothing blocks it.
    none,
    /// The name is used as an aggregate, rebound, or sits in a construct this
    /// analysis does not model. See `escape.Reason`.
    escapes,
    /// Some element initializer is not a compile-time integer.
    contents_unknown,
    /// Some read or write uses an index that is not a compile-time integer.
    variable_index,
    /// An element is written after the binding.
    mutated,
    /// A constant index is outside `1..width`. TABLES ARE 1-INDEXED: index 0 is
    /// out of bounds and must trap (gap[063]), not fold.
    index_out_of_range,
    /// Width is 0 — a literal with no elements has no element to fold.
    ///
    /// THE ONLY WIDTH THAT BLOCKS. There is deliberately no upper bound: a table
    /// whose contents are known, whose indices are known, which nothing writes
    /// and nothing escapes, need not exist at 4 elements or at 4,000. A ceiling
    /// here would be exactly the defect the ruling names — a cliff where a
    /// statically-answerable program starts being answered at runtime because of
    /// its size. Size is a fact about how to REALIZE a table that must exist,
    /// never about whether one must.
    unsupported_width,
};

pub const Facts = struct {
    name: []const u8,
    /// Element count of the literal this name was bound to.
    width: u32 = 0,
    /// Every element initializer is a compile-time integer, and `values` holds
    /// them in binding order (`values[0]` is element 1 — TABLES ARE 1-INDEXED).
    contents_known: bool = false,
    values: []const i64 = &.{},

    /// At least one read whose index is a compile-time integer.
    read_const: bool = false,
    /// At least one read whose index is not.
    read_var: bool = false,
    /// At least one element write with a compile-time integer index.
    write_const: bool = false,
    /// At least one element write with a non-constant index.
    write_var: bool = false,
    /// `t:len()` (or `#t` in the compatibility family) appears. Folds to the
    /// width; never touches storage.
    length_read: bool = false,
    /// Count of distinct compile-time indices touched by any access. Input to
    /// the partial rule (§R4), which is specified but NOT enabled here.
    distinct_const_indices: u32 = 0,
    /// Some constant index fell outside `1..width`.
    const_index_out_of_range: bool = false,

    /// Result of `escape.positionalTableEscapes` for this name.
    escape: escape.Escape = .{},

    pub fn readAtAll(self: Facts) bool {
        return self.read_const or self.read_var;
    }

    pub fn mutated(self: Facts) bool {
        return self.write_const or self.write_var;
    }

    pub fn allIndicesConstant(self: Facts) bool {
        return !self.read_var and !self.write_var;
    }

    /// §R1 — the ABSENT precondition, in one place.
    ///
    /// Every clause is load-bearing; the comment on each says what goes wrong
    /// without it.
    pub fn blocker(self: Facts) Blocker {
        // A zero-width literal has no elements to fold, and the lowering already
        // bails on it. NO UPPER BOUND — see `Blocker.unsupported_width`.
        if (self.width == 0) return .unsupported_width;
        // Without this, a table handed to a relation would have no storage to
        // pass the base address of.
        if (self.escape.escapes()) return .escapes;
        // Without this, there is no immediate to fold the read into.
        if (!self.contents_known) return .contents_unknown;
        // Without this, a runtime index has nothing to index. This is the clause
        // that keeps `gate/table.id` on the memory path.
        if (!self.allIndicesConstant()) return .variable_index;
        // Without this, a fold would return the INITIAL value of an element that
        // was later overwritten — precisely the wrong answer the access-site
        // materialization produced. §R2 (below) is where mutation with wholly
        // constant indices could be handled; it is deliberately not handled here.
        if (self.mutated()) return .mutated;
        // Without this, `t(0)` and `t(width + 1)` would fold to whatever
        // `values[k - 1]` happens to address instead of trapping. TABLES ARE
        // 1-INDEXED.
        if (self.const_index_out_of_range) return .index_out_of_range;
        return .none;
    }

    /// The representation this table would get if it were the only one in the
    /// function. `Decisions.analyze` then applies the uniformity rule across the
    /// tables that remain materialized.
    ///
    /// ELIMINATION IS THE FIRST QUESTION, AND IT IS SIZE-BLIND. The `.absent`
    /// clause is tested before any width is looked at, and `blocker()` has no
    /// upper width bound, so a 4,000-element table of constants read at a
    /// constant index is answered statically for the same reason a 4-element one
    /// is. Width enters only BELOW that line, to pick among the forms a table
    /// that must exist can take. Size informs the realization; it never decides
    /// existence.
    pub fn soloRepresentation(self: Facts) Representation {
        if (self.blocker() == .none) return .absent;
        if (@as(i64, self.width) > select_chain_max) return .memory;
        if (self.escape.escapes()) return .memory;
        return .registers;
    }

    /// The immediate a constant-index read folds to, or null if this table is
    /// not eliminable or the index is out of range.
    ///
    /// 1-INDEXED. `at(1)` is `values[0]`. A caller that passes a 0 gets null,
    /// not `values[width - 1]`.
    pub fn at(self: Facts, index: i64) ?i64 {
        if (self.blocker() != .none) return null;
        if (index < 1 or index > @as(i64, self.width)) return null;
        return self.values[@intCast(index - 1)];
    }
};

/// Every table binding in one function body, with its decided representation.
pub const Decisions = struct {
    alloc: std.mem.Allocator,
    facts: []Facts,
    reps: []Representation,
    /// True when the body contains a construct the collector does not model.
    /// Nothing is eliminated in such a body; the facts are reported anyway so a
    /// caller can say why.
    unmodelled: bool = false,

    pub fn deinit(self: *Decisions) void {
        for (self.facts) |f| if (f.values.len > 0) self.alloc.free(f.values);
        self.alloc.free(self.facts);
        self.alloc.free(self.reps);
        self.* = undefined;
    }

    pub fn get(self: *const Decisions, name: []const u8) ?Representation {
        for (self.facts, self.reps) |f, r| {
            if (std.mem.eql(u8, f.name, name)) return r;
        }
        return null;
    }

    pub fn factsFor(self: *const Decisions, name: []const u8) ?Facts {
        for (self.facts) |f| {
            if (std.mem.eql(u8, f.name, name)) return f;
        }
        return null;
    }

    /// THE INVARIANT. Among the tables that still have a physical form, exactly
    /// one representation is in use.
    ///
    /// This is what the two wrong answers on this tree were about, and it is
    /// checked rather than argued. `.absent` tables are excluded because they
    /// have no physical form to disagree with.
    pub fn uniform(self: *const Decisions) bool {
        var seen_registers = false;
        var seen_memory = false;
        for (self.reps) |r| switch (r) {
            .absent => {},
            .registers => seen_registers = true,
            .memory => seen_memory = true,
        };
        return !(seen_registers and seen_memory);
    }

    /// The single value `dnir_lower.LowerCtx.tables_in_memory` should take, for
    /// callers that adopt elimination without adopting per-table representation.
    /// True when any table that still needs a physical form needs the memory
    /// one.
    pub fn tablesInMemory(self: *const Decisions) bool {
        for (self.reps) |r| if (r == .memory) return true;
        return false;
    }

    pub fn eliminated(self: *const Decisions) u32 {
        var n: u32 = 0;
        for (self.reps) |r| if (r == .absent) {
            n += 1;
        };
        return n;
    }
};

/// Collect the facts for every positional table bound in `body`, then decide.
///
/// ORDER OF OPERATIONS, and it matters:
///   1. find the bindings and their literal contents;
///   2. classify every access, over the WHOLE body — a write in a loop that runs
///      textually after the last read still counts;
///   3. ask `escape.positionalTableEscapes` per name;
///   4. take each table's solo representation;
///   5. apply uniformity to what is left materialized.
///
/// Step 5 is the step that keeps this change conservative. If any surviving
/// table needs memory, they all get memory — the same rule in force today, just
/// evaluated over a smaller set.
pub fn analyze(alloc: std.mem.Allocator, body: *const ast.Block) Error!Decisions {
    var facts: std.ArrayListUnmanaged(Facts) = .empty;
    errdefer {
        for (facts.items) |f| if (f.values.len > 0) alloc.free(f.values);
        facts.deinit(alloc);
    }

    var unmodelled = false;
    try collectBindings(alloc, body, &facts, &unmodelled);

    for (facts.items) |*f| {
        var seen: std.AutoHashMapUnmanaged(i64, void) = .empty;
        defer seen.deinit(alloc);
        try classifyBlock(alloc, body, f, &seen);
        f.distinct_const_indices = @intCast(seen.count());
        f.escape = escape.positionalTableEscapes(body, f.name);
    }

    const reps = try alloc.alloc(Representation, facts.items.len);
    errdefer alloc.free(reps);
    for (facts.items, reps) |f, *r| {
        r.* = if (unmodelled and f.soloRepresentation() == .absent)
            // Fail closed: an unmodelled construct might touch this table in a
            // way the collector never saw.
            fallbackRepresentation(f)
        else
            f.soloRepresentation();
    }

    // Uniformity over the survivors.
    var any_memory = false;
    for (reps) |r| if (r == .memory) {
        any_memory = true;
    };
    if (any_memory) {
        for (reps) |*r| if (r.* == .registers) {
            r.* = .memory;
        };
    }

    return .{
        .alloc = alloc,
        .facts = try facts.toOwnedSlice(alloc),
        .reps = reps,
        .unmodelled = unmodelled,
    };
}

fn fallbackRepresentation(f: Facts) Representation {
    return if (@as(i64, f.width) > select_chain_max) .memory else .registers;
}

// ---------------------------------------------------------------------------
// Pass 1 — bindings
// ---------------------------------------------------------------------------

fn positionalWidth(expr: *const ast.Expr) ?u32 {
    if (expr.* != .table) return null;
    var n: u32 = 0;
    for (expr.table.fields) |fld| {
        if (fld != .positional) return null;
        n += 1;
    }
    return n;
}

fn recordBinding(
    alloc: std.mem.Allocator,
    name: []const u8,
    init_expr: *const ast.Expr,
    out: *std.ArrayListUnmanaged(Facts),
) Error!void {
    const width = positionalWidth(init_expr) orelse return;

    // A name bound twice in one body: keep the first and mark it rebound, so it
    // can never be eliminated. `escape.positionalTableEscapes` reports the same
    // thing independently; both are kept because they are separate walks and a
    // disagreement between them is worth catching.
    for (out.items) |*f| {
        if (std.mem.eql(u8, f.name, name)) {
            f.escape.reason = .rebound;
            return;
        }
    }

    var values = try alloc.alloc(i64, width);
    errdefer alloc.free(values);
    var known = true;
    var i: usize = 0;
    for (init_expr.table.fields) |fld| {
        if (constIndex(fld.positional)) |v| {
            values[i] = v;
        } else {
            known = false;
            values[i] = 0;
        }
        i += 1;
    }
    if (!known) {
        alloc.free(values);
        values = &.{};
    }

    try out.append(alloc, .{
        .name = name,
        .width = width,
        .contents_known = known,
        .values = values,
    });
}

fn collectBindings(
    alloc: std.mem.Allocator,
    block: *const ast.Block,
    out: *std.ArrayListUnmanaged(Facts),
    unmodelled: *bool,
) Error!void {
    for (block.stmts) |st| switch (st) {
        .local_decl => |d| {
            for (d.names, 0..) |n, i| {
                if (i < d.inits.len) try recordBinding(alloc, n.ident, d.inits[i], out);
            }
        },
        .global_decl => |d| {
            for (d.names, 0..) |n, i| {
                if (i < d.inits.len) try recordBinding(alloc, n.ident, d.inits[i], out);
            }
        },
        .const_decl => |d| try recordBinding(alloc, d.ident, d.val, out),
        .assign => |a| {
            for (a.targets, 0..) |t, i| {
                if (t.* == .name and i < a.values.len) {
                    try recordBinding(alloc, t.name.ident, a.values[i], out);
                }
            }
        },
        .do_block => |b| try collectBindings(alloc, &b.body, out, unmodelled),
        .while_loop => |w| try collectBindings(alloc, &w.body, out, unmodelled),
        .repeat_loop => |r| try collectBindings(alloc, &r.body, out, unmodelled),
        .num_for => |f| try collectBindings(alloc, &f.body, out, unmodelled),
        .gen_for => |f| try collectBindings(alloc, &f.body, out, unmodelled),
        .if_stmt => |f| {
            try collectBindings(alloc, &f.then, out, unmodelled);
            for (f.elseifs) |ei| try collectBindings(alloc, &ei.body, out, unmodelled);
            if (f.else_body) |eb| try collectBindings(alloc, &eb, out, unmodelled);
        },
        .call_stmt, .expr_stmt, .ret, .brk, .cont, .goto_stmt, .label_stmt => {},
        // A nested function declaration, a match/try/defer body, or a definition
        // form. The collector does not walk it, so it might bind or touch a
        // table it never sees.
        else => unmodelled.* = true,
    };
}

// ---------------------------------------------------------------------------
// Pass 2 — access classification
// ---------------------------------------------------------------------------

const Seen = std.AutoHashMapUnmanaged(i64, void);

fn noteIndex(
    alloc: std.mem.Allocator,
    f: *Facts,
    key: *const ast.Expr,
    is_write: bool,
    seen: *Seen,
) Error!void {
    if (constIndex(key)) |k| {
        try seen.put(alloc, k, {});
        if (k < 1 or k > @as(i64, f.width)) f.const_index_out_of_range = true;
        if (is_write) f.write_const = true else f.read_const = true;
    } else {
        if (is_write) f.write_var = true else f.read_var = true;
    }
}

fn classifyExpr(alloc: std.mem.Allocator, expr: *const ast.Expr, f: *Facts, seen: *Seen) Error!void {
    switch (expr.*) {
        .index => |ix| {
            if (ix.obj.* == .name and std.mem.eql(u8, ix.obj.name.ident, f.name)) {
                try noteIndex(alloc, f, ix.key, false, seen);
            } else {
                try classifyExpr(alloc, ix.obj, f, seen);
            }
            try classifyExpr(alloc, ix.key, f, seen);
        },
        .unop => |u| {
            if (u.op == .len and u.operand.* == .name and
                std.mem.eql(u8, u.operand.name.ident, f.name))
            {
                f.length_read = true;
                return;
            }
            try classifyExpr(alloc, u.operand, f, seen);
        },
        .binop => |b| {
            try classifyExpr(alloc, b.lhs, f, seen);
            try classifyExpr(alloc, b.rhs, f, seen);
        },
        .field => |x| try classifyExpr(alloc, x.obj, f, seen),
        .call => |c| {
            try classifyExpr(alloc, c.func, f, seen);
            for (c.args) |a| try classifyExpr(alloc, a, f, seen);
        },
        // `t:len()`. Must agree with `escape.zig`'s exemption 3 — hence the
        // shared predicate rather than two copies of the spelling.
        .method_call => |mc| {
            if (escape.isLengthFace(mc.method, mc.args.len) and
                mc.obj.* == .name and std.mem.eql(u8, mc.obj.name.ident, f.name))
            {
                f.length_read = true;
                return;
            }
            try classifyExpr(alloc, mc.obj, f, seen);
            for (mc.args) |a| try classifyExpr(alloc, a, f, seen);
        },
        .table => |t| for (t.fields) |fld| switch (fld) {
            .indexed => |x| {
                try classifyExpr(alloc, x.key, f, seen);
                try classifyExpr(alloc, x.val, f, seen);
            },
            .named => |x| try classifyExpr(alloc, x.val, f, seen),
            .positional => |p| try classifyExpr(alloc, p, f, seen),
            .spread => |s| try classifyExpr(alloc, s, f, seen),
            .semantic => |s| try classifyExpr(alloc, s.val, f, seen),
        },
        .sequence => |s| for (s.exprs) |x| try classifyExpr(alloc, x, f, seen),
        .range => |r| {
            try classifyExpr(alloc, r.start, f, seen);
            try classifyExpr(alloc, r.end, f, seen);
            if (r.step) |s| try classifyExpr(alloc, s, f, seen);
        },
        .contains_expr => |c| {
            try classifyExpr(alloc, c.lhs, f, seen);
            try classifyExpr(alloc, c.rhs, f, seen);
        },
        .try_expr => |t| try classifyExpr(alloc, t.operand, f, seen),
        .unwrap_expr => |u| try classifyExpr(alloc, u.operand, f, seen),
        .await_expr => |a| try classifyExpr(alloc, a.operand, f, seen),
        .if_expr => |ie| {
            try classifyExpr(alloc, ie.cond, f, seen);
            try classifyExpr(alloc, ie.then_expr, f, seen);
            try classifyExpr(alloc, ie.else_expr, f, seen);
        },
        // Leaves and everything unmodelled. `escape.positionalTableEscapes`
        // carries the fail-closed duty for the unmodelled cases; this pass only
        // has to avoid inventing accesses that are not there.
        else => {},
    }
}

fn classifyBlock(alloc: std.mem.Allocator, block: *const ast.Block, f: *Facts, seen: *Seen) Error!void {
    for (block.stmts) |st| try classifyStmt(alloc, &st, f, seen);
    if (block.tail_expr) |t| try classifyExpr(alloc, t, f, seen);
}

fn classifyStmt(alloc: std.mem.Allocator, st: *const ast.Stmt, f: *Facts, seen: *Seen) Error!void {
    switch (st.*) {
        .local_decl => |d| for (d.inits) |i| try classifyExpr(alloc, i, f, seen),
        .global_decl => |d| for (d.inits) |i| try classifyExpr(alloc, i, f, seen),
        .const_decl => |d| try classifyExpr(alloc, d.val, f, seen),
        .assign => |a| {
            for (a.targets) |t| {
                if (t.* == .index and t.index.obj.* == .name and
                    std.mem.eql(u8, t.index.obj.name.ident, f.name))
                {
                    try noteIndex(alloc, f, t.index.key, true, seen);
                    try classifyExpr(alloc, t.index.key, f, seen);
                } else {
                    try classifyExpr(alloc, t, f, seen);
                }
            }
            for (a.values) |v| try classifyExpr(alloc, v, f, seen);
        },
        .call_stmt => |c| try classifyExpr(alloc, c.expr, f, seen),
        .expr_stmt => |x| try classifyExpr(alloc, x.expr, f, seen),
        .do_block => |b| try classifyBlock(alloc, &b.body, f, seen),
        .while_loop => |w| {
            try classifyExpr(alloc, w.cond, f, seen);
            try classifyBlock(alloc, &w.body, f, seen);
        },
        .repeat_loop => |r| {
            try classifyBlock(alloc, &r.body, f, seen);
            try classifyExpr(alloc, r.cond, f, seen);
        },
        .if_stmt => |x| {
            if (x.binding) |b| try classifyExpr(alloc, b.expr, f, seen);
            try classifyExpr(alloc, x.cond, f, seen);
            try classifyBlock(alloc, &x.then, f, seen);
            for (x.elseifs) |ei| {
                try classifyExpr(alloc, ei.cond, f, seen);
                try classifyBlock(alloc, &ei.body, f, seen);
            }
            if (x.else_body) |eb| try classifyBlock(alloc, &eb, f, seen);
        },
        .num_for => |x| {
            try classifyExpr(alloc, x.start, f, seen);
            try classifyExpr(alloc, x.stop, f, seen);
            if (x.step) |s| try classifyExpr(alloc, s, f, seen);
            try classifyBlock(alloc, &x.body, f, seen);
        },
        .gen_for => |x| {
            for (x.iters) |i| try classifyExpr(alloc, i, f, seen);
            try classifyBlock(alloc, &x.body, f, seen);
        },
        .ret => |r| for (r.vals) |v| try classifyExpr(alloc, v, f, seen),
        else => {},
    }
}

// ---------------------------------------------------------------------------
// Tests. Every one parses real source and runs `table_apply.normalizeModule`
// first, because that is what turns `t(k)` into the `.index` node this pass
// reads — the same order the native backend uses (native_backend.zig:5459).
// ---------------------------------------------------------------------------

const testing = std.testing;

const Parsed = struct {
    module: ast.Module,
    fn body(self: *const Parsed) *const ast.Block {
        // Every fixture below declares exactly one relation; its body is the
        // function body the decision is made over.
        for (self.module.body.stmts) |*st| {
            if (st.* == .func_decl) return &st.func_decl.func.body;
        }
        unreachable;
    }
};

fn parseFixture(alloc: std.mem.Allocator, source: []const u8) !Parsed {
    var lexer = @import("lexer.zig").Lexer.init(source, "table-facts-test.id");
    var parser = @import("parser.zig").Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    // `t(k)` is a `.call` until this runs. Without it every access reads as an
    // aggregate use and nothing is ever eliminated — sound, but vacuous.
    const sema = @import("sema.zig");
    var type_map = sema.TypeMap.init(alloc);
    defer type_map.deinit();
    @import("table_apply.zig").normalizeModule(alloc, &module, &type_map);
    return .{ .module = module };
}

test "table_facts: constant contents, constant indices, no writes -> absent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [4]i64 = {10, 20, 30, 40}
        \\    t(1) + t(4)
    );
    var d = try analyze(alloc, parsed.body());
    defer d.deinit();

    try testing.expectEqual(@as(?Representation, .absent), d.get("t"));
    const f = d.factsFor("t").?;
    try testing.expectEqual(Blocker.none, f.blocker());
    try testing.expect(f.contents_known);
    try testing.expect(f.readAtAll());
    try testing.expect(!f.mutated());
    try testing.expectEqual(@as(u32, 2), f.distinct_const_indices);
    // 1-INDEXED. t(1) is 10 and t(4) is 40; the sum the program computes is 50.
    try testing.expectEqual(@as(?i64, 10), f.at(1));
    try testing.expectEqual(@as(?i64, 40), f.at(4));
    try testing.expect(d.uniform());
}

/// `main: i64 = () / t = (1, 2, … n) / t(2)` — the measured shape, at any width.
fn constTableFixture(alloc: std.mem.Allocator, n: u32) ![]const u8 {
    var src: std.ArrayListUnmanaged(u8) = .empty;
    try src.appendSlice(alloc, "main: i64 = ()\n    t = (");
    var digits: [24]u8 = undefined;
    for (1..n + 1) |k| {
        if (k > 1) try src.appendSlice(alloc, ", ");
        try src.appendSlice(alloc, std.fmt.bufPrint(&digits, "{d}", .{k}) catch unreachable);
    }
    try src.appendSlice(alloc, ")\n    t(2)\n");
    return src.toOwnedSlice(alloc);
}

test "table_facts: ELIMINATION HAS NO SIZE BOUND — same verdict at 4 and at 4000" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // THE RULING, restated as a test. Measured on this tree before the fact
    // lattice existed, for exactly this program, answer always the literal 2:
    //
    //      4 ->   4 instructions      33 -> 174   <- a 43x cliff at a SIZE
    //     16 ->   4                   40 -> 209
    //     32 ->   4                   64 -> 329
    //
    // Contents constant, index constant, no writes, no escape — the answer is
    // knowable at compile time in every row, so the table need not exist in any
    // of them. A lattice that stops applying at 33, or at 4096, has the same
    // defect in a new place, which is why the widths below straddle both.
    // Starts at 2: `t = (1)` is a parenthesized integer, not a one-element
    // table, so there is no positional binding at that width to have a verdict.
    for ([_]u32{ 2, 4, 32, 33, 40, 64, 1000, 4096, 4097 }) |n| {
        const src = try constTableFixture(alloc, n);
        const parsed = try parseFixture(alloc, src);
        var d = try analyze(alloc, parsed.body());
        defer d.deinit();

        const f = d.factsFor("t").?;
        try testing.expectEqual(n, f.width);
        try testing.expectEqual(Blocker.none, f.blocker());
        try testing.expectEqual(@as(?Representation, .absent), d.get("t"));
        try testing.expect(!d.tablesInMemory());
        // And the value it folds to is the same one the program computes.
        // 1-INDEXED: element 2 of (1, 2, …) is 2, not 3.
        try testing.expectEqual(@as(?i64, 2), f.at(2));
        try testing.expectEqual(@as(?i64, 1), f.at(1));
        try testing.expectEqual(@as(?i64, null), f.at(0));
        try testing.expectEqual(@as(?i64, null), f.at(@as(i64, n) + 1));
    }
}

test "table_facts: TABLES ARE 1-INDEXED — index 0 is out of range and blocks the fold" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // A 0 index is not "the first element"; it is out of bounds and must trap
    // (gap[063]). Folding it would turn a trap into a value, which is a wrong
    // answer of exactly the kind this design exists to avoid.
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [3]i64 = {7, 8, 9}
        \\    t(0)
    );
    var d = try analyze(alloc, parsed.body());
    defer d.deinit();

    const f = d.factsFor("t").?;
    try testing.expect(f.const_index_out_of_range);
    try testing.expectEqual(Blocker.index_out_of_range, f.blocker());
    try testing.expect(d.get("t").? != .absent);
    // And the accessor refuses both ends rather than wrapping.
    try testing.expectEqual(@as(?i64, null), f.at(0));
    try testing.expectEqual(@as(?i64, null), f.at(4));
}

test "table_facts: past-the-end constant index is out of range too" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [3]i64 = {7, 8, 9}
        \\    t(4)
    );
    var d = try analyze(alloc, parsed.body());
    defer d.deinit();
    try testing.expectEqual(Blocker.index_out_of_range, d.factsFor("t").?.blocker());
}

test "table_facts: a never-read table is still eliminable — the purest case" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Measured on this tree: 40 elements bound and never read costs 205
    // instructions. The answer is `mov x0,#7 ; ret`.
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [4]i64 = {1, 2, 3, 4}
        \\    7
    );
    var d = try analyze(alloc, parsed.body());
    defer d.deinit();

    const f = d.factsFor("t").?;
    try testing.expect(!f.readAtAll());
    try testing.expectEqual(Blocker.none, f.blocker());
    try testing.expectEqual(@as(?Representation, .absent), d.get("t"));
}

test "table_facts: a variable index blocks elimination" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [4]i64 = {10, 20, 30, 40}
        \\    i = 2
        \\    t(i)
    );
    var d = try analyze(alloc, parsed.body());
    defer d.deinit();

    const f = d.factsFor("t").?;
    try testing.expect(f.read_var);
    try testing.expect(!f.allIndicesConstant());
    try testing.expectEqual(Blocker.variable_index, f.blocker());
    try testing.expectEqual(@as(?Representation, .registers), d.get("t"));
}

test "table_facts: a write after binding blocks elimination" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // The fold would answer 10 for `t(1)`, which was true only until the write.
    // This is the shape that made an earlier attempt silently restore initial
    // values.
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [4]i64 = {10, 20, 30, 40}
        \\    t(1) = 99
        \\    t(1)
    );
    var d = try analyze(alloc, parsed.body());
    defer d.deinit();

    const f = d.factsFor("t").?;
    try testing.expect(f.write_const);
    try testing.expect(f.mutated());
    try testing.expectEqual(Blocker.mutated, f.blocker());
    try testing.expect(d.get("t").? != .absent);
}

test "table_facts: non-constant contents block elimination" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    n = 5
        \\    t: [3]i64 = {1, n, 3}
        \\    t(2)
    );
    var d = try analyze(alloc, parsed.body());
    defer d.deinit();

    const f = d.factsFor("t").?;
    try testing.expect(!f.contents_known);
    try testing.expectEqual(Blocker.contents_unknown, f.blocker());
}

test "table_facts: t:len() is a length read, not an escape" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // SPELLING NOTE. The fixture reads `t:len()`, not `#t`, because `#` opens a
    // COMMENT in the canon lexer family (lexer.zig:828) — `#t` in a .id source
    // is not a length operator, it is the rest of the line thrown away, and a
    // fixture written that way silently tests an empty body. `#t` remains a
    // length read in the compatibility family and `escape.zig` still exempts it;
    // this is the face .id programs actually have.
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [4]i64 = {10, 20, 30, 40}
        \\    t:len()
    );
    var d = try analyze(alloc, parsed.body());
    defer d.deinit();

    const f = d.factsFor("t").?;
    try testing.expect(f.length_read);
    try testing.expect(!f.escape.escapes());
    try testing.expectEqual(@as(?Representation, .absent), d.get("t"));
}

test "table_facts: passing the table to a relation is an escape" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [4]i64 = {10, 20, 30, 40}
        \\    sink(t)
    );
    var d = try analyze(alloc, parsed.body());
    defer d.deinit();

    const f = d.factsFor("t").?;
    try testing.expect(f.escape.escapes());
    try testing.expectEqual(escape.Reason.aggregate_use, f.escape.reason);
    try testing.expectEqual(Blocker.escapes, f.blocker());
    try testing.expectEqual(@as(?Representation, .memory), d.get("t"));
}

test "table_facts: naming the table as the answer is an escape" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [4]i64 = {10, 20, 30, 40}
        \\    t
    );
    var d = try analyze(alloc, parsed.body());
    defer d.deinit();

    try testing.expect(d.factsFor("t").?.escape.escapes());
    try testing.expect(d.get("t").? != .absent);
}

test "table_facts: rebinding the whole table blocks elimination" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [2]i64 = {1, 2}
        \\    t = {3, 4}
        \\    t(1)
    );
    var d = try analyze(alloc, parsed.body());
    defer d.deinit();

    const f = d.factsFor("t").?;
    try testing.expectEqual(escape.Reason.rebound, f.escape.reason);
    try testing.expectEqual(Blocker.escapes, f.blocker());
}

test "table_facts: THE UNIFORMITY INVARIANT — no decision map mixes registers and memory" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // `wide` has a variable index, so it must be memory-backed. `narrow` is
    // written, so it is not eliminable, and at 3 elements it would be happy in
    // registers on its own. Mixing the two inside one function is what produced
    // a stale-index wrong answer, so `narrow` joins `wide` in memory — the rule
    // in force today, evaluated over the survivors.
    //
    // THE WRITE IS LOAD-BEARING. Without `narrow(1) = 5` this table is
    // eliminable outright and leaves the materialized set, and the test would
    // pass while exercising nothing: there would be no second representation to
    // disagree with `wide`.
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    wide: [33]i64 = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33}
        \\    narrow: [3]i64 = {7, 8, 9}
        \\    i = 2
        \\    narrow(1) = 5
        \\    wide(i) + narrow(1)
    );
    var d = try analyze(alloc, parsed.body());
    defer d.deinit();

    try testing.expectEqual(Blocker.variable_index, d.factsFor("wide").?.blocker());
    try testing.expectEqual(Blocker.mutated, d.factsFor("narrow").?.blocker());
    // Solo, `narrow` prefers registers. Uniformity is what overrides that.
    try testing.expectEqual(Representation.registers, d.factsFor("narrow").?.soloRepresentation());
    try testing.expectEqual(@as(?Representation, .memory), d.get("wide"));
    try testing.expectEqual(@as(?Representation, .memory), d.get("narrow"));
    try testing.expect(d.uniform());
    try testing.expect(d.tablesInMemory());
}

test "table_facts: eliminating the wide table frees its neighbour from memory" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Measured on this tree: `narrow` alone is 4 instructions; with this unread
    // 40-element neighbour it is 230, because the neighbour drags the whole
    // relation into memory. The neighbour is eliminable, so it leaves the
    // materialized set entirely — and uniformity still holds over what remains,
    // because what remains is one table.
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    narrow: [4]i64 = {10, 20, 30, 40}
        \\    w: [33]i64 = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
        \\    narrow(2)
    );
    var d = try analyze(alloc, parsed.body());
    defer d.deinit();

    try testing.expectEqual(@as(?Representation, .absent), d.get("w"));
    try testing.expectEqual(@as(?Representation, .absent), d.get("narrow"));
    try testing.expectEqual(@as(u32, 2), d.eliminated());
    try testing.expect(!d.tablesInMemory());
    try testing.expect(d.uniform());
}

test "table_facts: a wide table with a variable index still goes to memory — gate/table.id shape" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // This is the shape `gate/table.id` pins at 8. Nothing here may change.
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    wide: [33]i64 = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
        \\    i = 1
        \\    while i <= 33
        \\        wide(i) = i
        \\        i += 1
        \\    wide(33)
    );
    var d = try analyze(alloc, parsed.body());
    defer d.deinit();

    const f = d.factsFor("wide").?;
    try testing.expect(f.write_var);
    try testing.expect(f.read_const);
    try testing.expectEqual(Blocker.variable_index, f.blocker());
    try testing.expectEqual(@as(?Representation, .memory), d.get("wide"));
}

test "table_facts: writes inside a loop are seen even when they follow the last read textually" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // The facts are collected over the WHOLE body, not up to the access. A pass
    // that stopped at the read would eliminate this table and answer 10.
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [2]i64 = {10, 20}
        \\    r = t(1)
        \\    i = 1
        \\    while i <= 2
        \\        t(i) = 0
        \\        i += 1
        \\    r
    );
    var d = try analyze(alloc, parsed.body());
    defer d.deinit();

    const f = d.factsFor("t").?;
    try testing.expect(f.write_var);
    try testing.expect(f.blocker() != .none);
}

test "table_facts: an unmodelled construct fails closed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // A nested relation could capture the table. The collector does not walk
    // into it, so nothing in this body is eliminated.
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [2]i64 = {1, 2}
        \\    inner: i64 = ()
        \\        t(1)
        \\    inner()
    );
    var d = try analyze(alloc, parsed.body());
    defer d.deinit();

    try testing.expect(d.unmodelled);
    try testing.expect(d.get("t").? != .absent);
}

test "table_facts: constIndex matches dnir_lower.intLiteralStep exactly" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Narrow on purpose. `2 + 1` is NOT a constant index to the lowering, so it
    // must not be one here either — a fact that claims more constants than the
    // access site can address is how a slot map goes wrong.
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [4]i64 = {10, 20, 30, 40}
        \\    t(2 + 1)
    );
    var d = try analyze(alloc, parsed.body());
    defer d.deinit();

    const f = d.factsFor("t").?;
    try testing.expect(f.read_var);
    try testing.expectEqual(Blocker.variable_index, f.blocker());
}

test "table_facts: the escape walk and the access walk agree on every access" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Two independent walks answer two different questions over the same AST.
    // A table with accesses and no other mention must be seen as accessed by one
    // and as non-escaping by the other; a disagreement means one walker learned
    // a construct the other did not.
    const parsed = try parseFixture(alloc,
        \\main: i64 = ()
        \\    t: [4]i64 = {10, 20, 30, 40}
        \\    a = t(1)
        \\    b = t(2)
        \\    if t(3) == 30
        \\        a += 1
        \\    a + b + t:len()
    );
    var d = try analyze(alloc, parsed.body());
    defer d.deinit();

    const f = d.factsFor("t").?;
    try testing.expect(f.read_const);
    try testing.expect(f.length_read);
    try testing.expectEqual(@as(u32, 3), f.distinct_const_indices);
    try testing.expect(!f.escape.escapes());
    try testing.expectEqual(@as(?Representation, .absent), d.get("t"));
}
