const std = @import("std");
pub const Loc = @import("lexer.zig").Loc;
const RT = @import("types.zig").ResolvedType;

/// §4.1 — the surface FACE an application was written through.
///
/// c0 §44 `law.apply.one`: "parenthesized, braced and string faces project onto
/// the SAME application relation". The face is therefore a recorded FACT on the
/// one application node (`Expr.call`), never a choice of production. Nothing may
/// switch on it to pick a different object model; it exists so a consumer can
/// tell which face it is looking at without re-deriving it from spelling.
///
/// `braced` was added by APPLY-ONE. Before it, `f{ … }` and `f"…"` both recorded
/// `parenless`, so the brace face had NO face of its own and `f{ x = 1 }` was
/// indistinguishable from `f({ x = 1 })` in the tree — c0 §44a trap 2 ("braces as
/// sugar") already applied and its evidence erased before sema ever ran.
pub const InvocationForm = enum {
    value_reference,
    parenthesized,
    parenless,
    receiver_parenthesized,
    receiver_parenless,
    command,
    indirect,
    /// `subject{ … }` — the brace face. The single operand is a `.table` whose
    /// `pack.applied` is set; it is the subject's structured ARGUMENT PACK.
    braced,

    pub fn name(self: InvocationForm) []const u8 {
        return @tagName(self);
    }
};

/// c0 §44 `law.pack.shape` — "a BRACED ARGUMENT NEED NOT MATERIALIZE A TABLE".
///
/// `{ … }` is one construct with three stances, and they are stances of the SAME
/// form rather than three mechanisms (c0 §43 `anchor.brace`):
///
///     { x = 1 }         an anonymous structured value      applied=0 elided=0
///     point{ x = 1 }    the pack of an application         applied=1 elided=0
///     @{ x = 1 }        the same, subject name elided      applied=1 elided=1
///
/// The FIELDS were never the missing facts — `TableField.named` already carries a
/// label, field ORDER already carries position, `.spread` and `.indexed` already
/// carry their edges. What the tree could not state is the three bits below, and
/// without them `f{ … }` had already been rewritten to `f({ … })` by the time any
/// consumer saw it.
pub const Pack = struct {
    /// Written in APPLICATION position: this brace is a subject's argument pack,
    /// not a free-standing value. Distinguishes `f{ x = 1 }` from `f({ x = 1 })`.
    applied: bool = false,
    /// `@{ … }` — the subject NAME is elided and the enclosing descriptor
    /// supplies it. Not a third mechanism; `home` is where the name comes from.
    elided: bool = false,
    /// The enclosing descriptor this parse was reading for, when there was one.
    /// Null at top level, where `@{ … }` has no name to recover and is honestly
    /// the anonymous pack.
    home: ?[]const u8 = null,
    /// law.pack.shape: "physical representation is selected AFTER semantic
    /// resolution". `undecided` is the resting state and the only value the
    /// PARSER may ever write — the surface having braces is not a demand for a
    /// heap table. A resolving consumer records what demand actually required.
    realized: Realization = .undecided,

    /// Whether this pack is the pack of an application at all.
    pub fn is_argument(self: Pack) bool {
        return self.applied;
    }
};

/// What demand turned out to require of a pack. `undecided` means nobody has
/// asked yet, which is not the same as "a table" and must never be read as one.
pub const Realization = enum { undecided, table, fields };

// ── Type expressions ─────────────────────────────────────────────────────────

pub const TypeExpr = union(enum) {
    inferred, // no annotation; type must be inferred
    named: []const u8, // i32, f64, bool, void, str, etc.
    array: ArrayType,
    pointer: *TypeExpr,
    func: FuncType,
    optional: *TypeExpr, // ?T
    generic: GenericType, // T<U, V>
    tuple: []TypeExpr, // (T, U) — multi-return value type
    /// Inline record-type literal: `{ name: T, name2: U, ... }`. This is the
    /// only mechanism for declaring a typed record in Duo. Records are
    /// structural and anonymous (no name). The codegen mints a C `struct`
    /// for each unique record shape (deduplicated by content hash).
    record: *RecordType,
    /// Generic type parameter with optional concept constraint(s): `T: Hashable` or `T: A + B`.
    constrained: struct { name: []const u8, constraint: *TypeExpr, extra: []TypeExpr },

    pub const RecordType = struct {
        fields: []RecordField,
        /// Layout facts written as refinement edges on the descriptor itself:
        /// `{ x: i8, y: i64 } & packed & align(8)`. §11 ("layout
        /// facts") and LAW-STRATA (`&` = the refinement edge). This is NOT an
        /// attribute list: it is the one fact the old `@packed` / `@align(n)`
        /// attributes were secretly storing, now held where the descriptor is.
        layout: Layout = .{},
    };

    /// Which storage class a refinement names explicitly. `null` means the
    /// class stays inferred from the fields.
    pub const StorageWord = enum { native, guarded, sealed };

    /// The complete set of layout facts a record descriptor can carry. Both
    /// the refinement spelling (`& packed`) and the legacy attribute spelling
    /// (`@packed`) resolve to a value of this type — one ontology, and the
    /// legacy spelling adapts INTO it, never the other way round.
    pub const Layout = struct {
        is_packed: bool = false,
        /// `align_given` distinguishes "no alignment stated" from "alignment
        /// stated but unparseable", which the attribute path treats as a
        /// clear-to-null. Dropping the distinction would change behaviour.
        align_given: bool = false,
        align_n: ?usize = null,
        ffi: ?[]const u8 = null,
        sealed: bool = false,
        storage: ?StorageWord = null,
    };

    pub const GenericType = struct {
        base: *TypeExpr,
        params: []TypeExpr,
    };

    pub const ArrayType = struct {
        elem: *TypeExpr,
        size: ?usize, // null → dynamic slice, non-null → fixed [N]T
    };

    pub const FuncType = struct {
        params: []TypeExpr,
        ret: *TypeExpr,
    };

    pub fn is_numeric(self: TypeExpr) bool {
        return switch (self) {
            .named => |n| for ([_][]const u8{
                "i8",  "i16", "i32", "i64",
                "u8",  "u16", "u32", "u64",
                "f32", "f64",
            }) |t| {
                if (std.mem.eql(u8, n, t)) break true;
            } else false,
            else => false,
        };
    }

    pub fn is_integer(self: TypeExpr) bool {
        return switch (self) {
            .named => |n| for ([_][]const u8{
                "i8", "i16", "i32", "i64",
                "u8", "u16", "u32", "u64",
            }) |t| {
                if (std.mem.eql(u8, n, t)) break true;
            } else false,
            else => false,
        };
    }

    pub fn is_float(self: TypeExpr) bool {
        return switch (self) {
            .named => |n| std.mem.eql(u8, n, "f32") or std.mem.eql(u8, n, "f64"),
            else => false,
        };
    }

    /// Structural equality. Two record types are equal iff their field sets
    /// are equal in name-and-type; field order does not matter.
    pub fn eql(a: TypeExpr, b: TypeExpr) bool {
        return switch (a) {
            .inferred => switch (b) {
                .inferred => true,
                else => false,
            },
            .named => |na| switch (b) {
                .named => |nb| std.mem.eql(u8, na, nb),
                else => false,
            },
            .pointer => |pa| switch (b) {
                .pointer => |pb| pa.eql(pb.*),
                else => false,
            },
            .optional => |pa| switch (b) {
                .optional => |pb| pa.eql(pb.*),
                else => false,
            },
            .array => |aa| switch (b) {
                .array => |ab| aa.size == ab.size and aa.elem.eql(ab.elem.*),
                else => false,
            },
            .record => |ra| switch (b) {
                .record => |rb| record_eql(ra, rb),
                else => false,
            },
            .func => false,
            .generic => false,
            .tuple => |ta| switch (b) {
                .tuple => |tb| blk: {
                    if (ta.len != tb.len) break :blk false;
                    for (ta, tb) |ea, eb| {
                        if (!ea.eql(eb)) break :blk false;
                    }
                    break :blk true;
                },
                else => false,
            },
            .constrained => |ca| switch (b) {
                .constrained => |cb| blk: {
                    if (!std.mem.eql(u8, ca.name, cb.name) or !ca.constraint.eql(cb.constraint.*))
                        break :blk false;
                    if (ca.extra.len != cb.extra.len) break :blk false;
                    for (ca.extra, cb.extra) |ea, eb| {
                        if (!ea.eql(eb)) break :blk false;
                    }
                    break :blk true;
                },
                else => false,
            },
        };
    }

    fn record_eql(a: *RecordType, b: *RecordType) bool {
        if (a.fields.len != b.fields.len) return false;
        for (a.fields) |af| {
            var found = false;
            for (b.fields) |bf| {
                if (std.mem.eql(u8, af.name, bf.name) and af.typ.eql(bf.typ)) {
                    found = true;
                    break;
                }
            }
            if (!found) return false;
        }
        return true;
    }
};

// ── Expressions ───────────────────────────────────────────────────────────────

pub const BinOp = enum {
    add,
    sub,
    mul,
    div,
    idiv,
    mod,
    pow,
    band,
    bor,
    bxor,
    lshift,
    rshift,
    concat,
    eq,
    neq,
    lt,
    gt,
    leq,
    geq,
    @"and",
    @"or",
    contains,
    /// Infix `@` — matrix multiply (`a @ b`), distinct from prefix `@macro`.
    matmul,
    /// Pipeline operator `|>` — `x |> f` desugars to `f(x)`.
    pipeline,
};

pub const UnOp = enum { neg, not, len, bnot, compile };

pub const TableField = union(enum) {
    indexed: struct { key: *Expr, val: *Expr }, // [expr] = expr
    named: struct { key: []const u8, val: *Expr }, // name = expr
    positional: *Expr, // expr
    /// `{ ..source, x = 1 }` — merge table at construction.
    spread: *Expr,
    /// (final surface) — semantic entry in a table literal:
    /// `@eq = impl` or `@to(str) = impl`. `op` is the operation name; `param`
    /// is the optional relationship parameter (e.g. `str` in `@to(str)`); `val`
    /// is the implementation.
    semantic: struct { op: []const u8, param: ?[]const u8, val: *Expr },
};

pub const ListComprehension = struct {
    loc: Loc,
    value: *Expr,
    key_name: ?[]const u8,
    value_name: []const u8,
    iter: *Expr,
    filter: ?*Expr = null,
};

pub const MacroCall = struct {
    loc: Loc,
    name: []const u8,
    args: []*Expr,
};

pub const IfExpr = struct {
    loc: Loc,
    cond: *Expr,
    then_expr: *Expr,
    else_expr: *Expr,
};

pub const FuncParam = struct {
    name: []const u8,
    typ: TypeExpr,
    default_val: ?*Expr = null,
    loc: Loc,
};

pub const Upvalue = struct {
    name: []const u8,
    /// true when captured from an enclosing local, false for globals
    is_local: bool,
    typ: ?RT = null,
    /// true when this upvalue is assigned to inside the closure body or shared
    /// between multiple closures. Requires heap-allocated cell for shared mutation.
    mutable: bool = false,
};

/// Compile-time device target from `@device(...)` on functions.
pub const DeviceTarget = enum {
    none,
    cpu,
    auto,
    metal,
    cuda,
    webgpu,
    wasm,
    tpu,
};

pub const FuncBody = struct {
    loc: Loc,
    params: []FuncParam,
    vararg: bool,
    /// Lua 5.5 named vararg: function f(...args)
    vararg_name: ?[]const u8 = null,
    ret_type: TypeExpr,
    /// §8 B-12 — the contract declared a FAILURE ALTERNATIVE
    /// (`: u64 | error`). The structural nil is UNWRITTEN, so `ret_type` still
    /// carries `u64` alone, and this records that what the function actually
    /// returns is the correlated pack `(value, nil) | (nil, error)`. Without
    /// it `return nil, error.overflow` reads as a plain `u64` return of nil and
    /// sema rejects §20's own leb128 decoder.
    ret_fallible: bool = false,
    body: Block,
    /// Generic type parameters: <T, U>
    type_params: ?[]TypeExpr = null,
    /// Whether the function was declared with the `async` modifier
    is_async: bool = false,
    // set by sema: is the function fully typed (all params + ret annotated)?
    is_typed: bool = false,
    // set by sema: emit O(n) iterative loop instead of naive recursion
    use_iterative_fib: bool = false,
    // set by sema: emit Eratosthenes sieve instead of trial division
    use_prime_sieve: bool = false,
    // set by sema: lower numeric table t[i] to a native int64_t array
    use_dense_table: bool = false,
    dense_table: ?[]const u8 = null,
    dense_table_cap: ?[]const u8 = null,
    /// All empty-table locals detected in the function body. Each one that
    /// receives only integer-indexed writes/reads gets a native `int64_t*`
    /// (or `double*` for float tables) allocation. `dense_table`/
    /// `dense_table_cap` above are set to the first one for backward
    /// compatibility with the specialized single-table emitters.
    dense_tables: []const []const u8 = &.{},
    dense_table_caps: []const []const u8 = &.{},
    /// Parallel to `dense_tables`: true = float table (double*), false = int (int64_t*).
    dense_table_floats: []const bool = &.{},
    /// Parallel to `dense_tables`: true when the matching `dense_table_caps`
    /// entry is a valid C *integer* expression at the allocation point (every
    /// leaf an integer literal or a name known to hold a native number). The cap
    /// is only a reservation — the dense accessors grow on demand — so a false
    /// here costs a few reallocs, never correctness. It exists because
    /// `f(n: any)` produced `calloc((n) + 1, …)` on a `lua_Value`, which is a
    /// hard C compile error.
    dense_table_cap_safe: []const bool = &.{},
    /// Parallel to `dense_tables`: true when the entry is an *alias* — a name
    /// bound by `tmp = grid` rather than by a table literal. An alias owns no
    /// buffer, so it is never allocated and never freed; it only rebinds the
    /// `(pointer, capacity)` pair of whatever it was assigned from.
    dense_table_alias: []const bool = &.{},
    /// Parallel to `dense_tables`: true when the binding that creates the table
    /// sits inside a nested block (a loop or branch), not at the top level of
    /// the body. Such a name cannot be declared at its binding site — the
    /// matching `free` is emitted at the function's return, where a
    /// block-scoped C declaration is not in scope, and re-declaring it once per
    /// iteration would allocate a buffer per iteration with nothing to free
    /// them. The declaration is hoisted to the function prologue instead and
    /// the binding lowers to a *reset* of the one buffer (see
    /// `duo_dt_reset_*`), which is what `t = {}` means: an empty table again.
    dense_table_hoisted: []const bool = &.{},
    // set by sema: emit C-style 0-based string scan loops
    use_string_byte_scan: bool = false,
    use_string_hash_scan: bool = false,
    string_scan_lit: ?[]const u8 = null,
    // set by sema: emit nested for-loops with inlined eval_A
    use_grid_sum_inline: bool = false,
    use_dense_table_max: bool = false,
    use_dense_table_sum: bool = false,
    dense_table_sum_mul: i64 = 1,
    dense_table_sum_add: i64 = 0,
    use_dense_table_square_sum: bool = false,
    use_dense_table_quadratic_sum: bool = false,
    dense_table_sum_square_mul: i64 = 0,
    dense_table_sum_linear_mul: i64 = 0,
    dense_table_sum_const: i64 = 0,
    use_dense_table_cubic_sum: bool = false,
    dense_table_sum_cube_mul: i64 = 0,
    use_dense_table_quartic_sum: bool = false,
    dense_table_sum_quartic_mul: i64 = 0,
    use_dense_table_quintic_sum: bool = false,
    dense_table_sum_quintic_mul: i64 = 0,
    use_dense_table_sextic_sum: bool = false,
    dense_table_sum_sextic_mul: i64 = 0,
    use_dense_table_septic_sum: bool = false,
    dense_table_sum_septic_mul: i64 = 0,
    use_dense_table_octic_sum: bool = false,
    dense_table_sum_octic_mul: i64 = 0,
    use_dense_table_nonic_sum: bool = false,
    dense_table_sum_nonic_mul: i64 = 0,
    use_dense_table_decic_sum: bool = false,
    dense_table_sum_decic_mul: i64 = 0,
    use_dense_table_faulhaber_sum: bool = false,
    dense_table_sum_coeffs: [13]i64 = @splat(0),
    use_dense_table_identity_sum: bool = false,
    use_math_pow_sqrt: bool = false,
    use_string_len_chain: bool = false,
    use_binary_search_dense: bool = false,
    use_filter_count_mod: bool = false,
    use_dot_product_identity: bool = false,
    use_dot_product_dense: bool = false,
    use_clamp_mod_sum: bool = false,
    use_mod_histogram_sum: bool = false,
    use_ema_smooth: bool = false,
    /// avg *= alpha; avg += (i % period) * beta — fold full periods in O(1)
    use_ema_period_fold: bool = false,
    ema_alpha: f64 = 0.95,
    ema_beta: f64 = 0.05,
    ema_period: i64 = 100,
    use_table_lookup_sum: bool = false,
    use_dense_table_mod997_sum: bool = false,
    use_string_token_count: bool = false,
    use_string_delim_byte_sum: bool = false,
    use_trig_sum_recur: bool = false,
    use_mandel_iter_native: bool = false,
    use_nbody_native: bool = false,
    use_force_always_inline: bool = false,
    /// always_inline + no-fast-math region (fp-sensitive natives like mandel_iter)
    use_fp_strict_always_inline: bool = false,
    /// `@comp.compile.only` — function is only available during compilation
    is_compile_only: bool = false,
    // ── New native patterns for benchmarks 24-40 ─────────────────────
    use_gcd_inline: bool = false,
    use_collatz_inline: bool = false,
    use_xor_fold_inline: bool = false,
    use_bitcount_inline: bool = false,
    use_cordic_inline: bool = false,
    use_ack_inline: bool = false,
    use_life_native: bool = false,
    use_matmul_native: bool = false,
    use_prefix_sum_inline: bool = false,
    use_ring_buf_inline: bool = false,
    use_sieve_native: bool = false,
    use_fenwick_native: bool = false,
    use_interp_inline: bool = false,
    use_run_len_inline: bool = false,
    use_sparse_dot_inline: bool = false,
    /// set by sema: for-loop reduction pattern — stronger vectorize pragma in codegen
    use_simd_reduction: bool = false,
    /// `@device(.auto|.metal|…)` — backend selection hint for ML kernels
    device_target: DeviceTarget = .none,
    /// `@autodiff` / `@differentiable` — gradient companion generation (stdlib hooks)
    autodiff: bool = false,
    differentiable: bool = false,
    /// `@profile` — emit timing hooks around the function body
    profile_attr: bool = false,
    /// `@unroll(N)` — loop unroll hint for typed numeric loops
    unroll_count: ?u32 = null,
    // set by sema for anonymous/nested functions (func_expr)
    closure_id: ?u32 = null,
    upvalues: []Upvalue = &.{},
};

/// Quoted source identity. Projects producer token kinds; `.host` is fabricated.
pub const Quote = enum {
    text,
    bytes,
    compat_text,
    compat_long,
    host,
};

/// True when the producer classified this literal as the byte-sequence face
/// (`law.literal.bytes`), not a text face.
pub fn quotedLiteralIsByteSequence(quote: Quote) bool {
    return quote == .bytes;
}

/// THE VALUE OF A WRITTEN LITERAL UNDER UNARY MINUS, or null when it has none.
///
/// THE MAGNITUDE IS THE PRODUCER'S FACT, NOT THIS FUNCTION'S GUESS. The lexer
/// classifies a decimal magnitude (`lexer.DecimalIntegerClass`) and the parser
/// consumes that class: `-9223372036854775808` is normalized to a bare
/// `int_lit` holding `INT_MIN`, and a `.neg` over a literal whose value is
/// already `INT_MIN` is REFUSED at the parse boundary with "integer negation is
/// outside the i64 range" (`src/parser.zig`). So the node this function is
/// asked about cannot come from source, and answering `INT_MIN` here would put
/// a second, quieter numeric law beside the producer's.
///
/// Declining is therefore the agreeing answer AND the safe one. What must never
/// happen is the third thing, which is what stood here: bare host `-v`, which
/// ABORTED the compiler with `panic: integer overflow`. c0 `law.effect.order`
/// fails on "backend decided trap semantics"; `law.ub.zero`: "ordinary integer
/// arithmetic has no C-style undefined behavior and numeric law is fully
/// defined"; law.md §1 keeps unknown distinct from zero.
pub fn negatedIntLiteral(written: i64) ?i64 {
    return std.math.negate(written) catch null;
}

/// THE ONE PRODUCER of "the exact i64 this literal expression denotes", or null
/// when the expression is not an integer literal or the value is not an i64.
///
/// Six copies of this predicate had been written independently — in `sema`,
/// `semantic_graph`, `dnir_lower`, `table_facts`, `region` and
/// `demand_projection` — and they disagreed three ways at `INT_MIN`: panic,
/// decline, or answer. `law.fact.producer.one`: one authoritative producer.
///
/// Null is a real answer here, not the absence of one — law.md §1: "Unknown,
/// absent, false, zero, empty, and not-asked are distinct."
pub fn intLiteralValue(expr: *const Expr) ?i64 {
    return switch (expr.*) {
        .int_lit => |lit| lit.val,
        .unop => |u| if (u.op == .neg)
            negatedIntLiteral(intLiteralValue(u.operand) orelse return null)
        else
            null,
        else => null,
    };
}

test "ast: negating a literal answers or declines — it never aborts" {
    const test_loc = Loc{ .file = "ast.zig", .line = 1, .col = 1 };

    // THE NODE THE PARSER REFUSES TO BUILD, built by hand. `-2^63` reaches the
    // AST as a bare `int_lit` (the parser normalizes the classified magnitude),
    // and a `.neg` over an INT_MIN-valued literal is rejected at the parse
    // boundary. Reading one anyway must decline, not abort: bare `-v` here
    // ended the compiler with `panic: integer overflow`.
    var floor = Expr{ .int_lit = .{ .loc = test_loc, .val = std.math.minInt(i64) } };
    var negated = Expr{ .unop = .{ .loc = test_loc, .op = .neg, .operand = &floor } };
    try std.testing.expectEqual(@as(?i64, null), intLiteralValue(&negated));
    try std.testing.expectEqual(@as(?i64, null), negatedIntLiteral(std.math.minInt(i64)));

    // INT_MIN itself is a value and stays one.
    try std.testing.expectEqual(@as(?i64, std.math.minInt(i64)), intLiteralValue(&floor));

    // Declining propagates rather than resurfacing as a number at depth.
    var twice = Expr{ .unop = .{ .loc = test_loc, .op = .neg, .operand = &negated } };
    try std.testing.expectEqual(@as(?i64, null), intLiteralValue(&twice));

    // Ordinary literals are unaffected, at the boundary and away from it.
    var ordinary = Expr{ .int_lit = .{ .loc = test_loc, .val = 42 } };
    var minus = Expr{ .unop = .{ .loc = test_loc, .op = .neg, .operand = &ordinary } };
    try std.testing.expectEqual(@as(?i64, -42), intLiteralValue(&minus));
    var ceiling = Expr{ .int_lit = .{ .loc = test_loc, .val = std.math.maxInt(i64) } };
    var lowered = Expr{ .unop = .{ .loc = test_loc, .op = .neg, .operand = &ceiling } };
    try std.testing.expectEqual(@as(?i64, std.math.maxInt(i64)), intLiteralValue(&ceiling));
    try std.testing.expectEqual(@as(?i64, -std.math.maxInt(i64)), intLiteralValue(&lowered));
}

pub const Expr = union(enum) {
    nil: Loc,
    true_lit: Loc,
    false_lit: Loc,
    int_lit: struct { loc: Loc, val: i64 },
    float_lit: struct { loc: Loc, val: f64 },
    /// Quoted source or a host-fabricated byte sequence. `quote` is the
    /// producer identity (GAP-145); `.host` is not a source quote.
    quoted: struct { loc: Loc, val: []const u8, quote: Quote = .host },
    vararg: Loc,
    name: struct { loc: Loc, ident: []const u8 },
    index: struct { loc: Loc, obj: *Expr, key: *Expr },
    /// `a.b` and `a@b` build the SAME node — the value of `b` at `a` — so the
    /// AST could not tell them apart and the formatter rewrote every `p@x` into
    /// `p.x`. That is a different operator: the anchor MOVES and retrieves.
    /// `anchored` records the spelling so the printer can write back what was
    /// written; nothing downstream reads it.
    field: struct { loc: Loc, obj: *Expr, field: []const u8, anchored: bool = false },
    call: struct { loc: Loc, func: *Expr, args: []*Expr, form: InvocationForm = .parenthesized },
    method_call: struct { loc: Loc, obj: *Expr, method: []const u8, args: []*Expr, form: InvocationForm = .receiver_parenthesized },
    binop: struct { loc: Loc, op: BinOp, lhs: *Expr, rhs: *Expr },
    unop: struct { loc: Loc, op: UnOp, operand: *Expr },
    func_expr: *FuncBody,
    /// The brace construct, in all three of its stances — see `Pack`. Named
    /// `table` for the bootstrap's own history; a table is one REALIZATION of
    /// it, and `pack.realized` is where that is decided.
    table: struct { loc: Loc, fields: []TableField, pack: Pack = .{} },
    list_comp: ListComprehension,
    try_expr: struct { loc: Loc, operand: *Expr }, // expr?
    unwrap_expr: struct { loc: Loc, operand: *Expr }, // expr!
    if_expr: *IfExpr,
    match_expr: *MatchExpr,
    await_expr: struct { loc: Loc, operand: *Expr },
    contains_expr: struct { loc: Loc, lhs: *Expr, rhs: *Expr }, // x in y
    quote: struct { loc: Loc, expr: *Expr },
    unquote: struct { loc: Loc, expr: *Expr },
    macro_call: MacroCall,
    sequence: struct { loc: Loc, exprs: []*Expr }, // a, b multi-value
    range: struct { loc: Loc, start: *Expr, end: *Expr, step: ?*Expr }, // a..b, a..b by step
    /// (final surface) — semantic identity `@name` in the
    /// current world. `@eq(a, b)` is a `.call` whose `.func` is this node;
    /// `@to(str)` is a `.call` whose schema decides relation-vs-invocation.
    semantic: struct { loc: Loc, op: []const u8 },
    /// (final surface) — bare `@` denotes the current effective
    /// semantic world, as a value.
    semantic_scope: Loc,

    pub fn loc(self: Expr) Loc {
        return switch (self) {
            .nil => |l| l,
            .true_lit => |l| l,
            .false_lit => |l| l,
            .vararg => |l| l,
            .int_lit => |x| x.loc,
            .float_lit => |x| x.loc,
            .quoted => |x| x.loc,
            .name => |x| x.loc,
            .index => |x| x.loc,
            .field => |x| x.loc,
            .call => |x| x.loc,
            .method_call => |x| x.loc,
            .binop => |x| x.loc,
            .unop => |x| x.loc,
            .func_expr => |f| f.loc,
            .table => |x| x.loc,
            .list_comp => |x| x.loc,
            .try_expr => |x| x.loc,
            .unwrap_expr => |x| x.loc,
            .if_expr => |x| x.loc,
            .match_expr => |m| m.loc,
            .await_expr => |x| x.loc,
            .contains_expr => |x| x.loc,
            .quote => |x| x.loc,
            .unquote => |x| x.loc,
            .macro_call => |x| x.loc,
            .sequence => |x| x.loc,
            .range => |x| x.loc,
            .semantic => |x| x.loc,
            .semantic_scope => |l| l,
        };
    }
};

// ── Match / Try / Defer / Enum / Concept ──────────────────────────────────────

pub const MatchExpr = struct {
    loc: Loc,
    scrutinee: *Expr,
    arms: []MatchArm,
};

pub const MatchArm = struct {
    pattern: Pattern,
    guard: ?*Expr,
    body: Block,
};

pub const Pattern = union(enum) {
    literal: *Expr,
    binding: struct { name: []const u8, typ: ?TypeExpr },
    variant: struct { tag: []const u8, payload: ?[]Pattern },
    table_destr: []TableDestrEntry,
    array_destr: []Pattern,
    rest: []const u8, // ...name
    wildcard, // _

    pub const TableDestrEntry = struct { key: []const u8, pat: Pattern };
};

pub const TryStmt = struct {
    loc: Loc,
    body: Block,
    catches: []CatchClause,
    defers: []DeferStmt,
};

/// A catch clause always binds the caught error to a single name. There is
/// no typed `catch MyError e` form — errors are table values and any caller-
/// supplied `__tag` check is performed inside the body with `match` / `if`.
pub const CatchClause = struct {
    loc: Loc,
    binding: ?[]const u8,
    body: Block,
};

pub const DeferStmt = struct {
    loc: Loc,
    body: Block,
};

pub const EnumDef = struct {
    loc: Loc,
    name: []const u8,
    type_params: ?[]TypeExpr,
    variants: []EnumVariant,
    attributes: []Attribute,
};

pub const EnumVariant = struct {
    name: []const u8,
    payload: ?[]PayloadField,

    pub const PayloadField = struct { name: ?[]const u8, typ: TypeExpr };
};

pub const Attribute = struct {
    name: []const u8,
    args: ?[]const u8, // raw string for now; parsed by sema
};

pub const FuncSignature = struct {
    name: []const u8,
    params: []FuncParam,
    ret_type: TypeExpr,
    type_params: ?[]TypeExpr,
};

pub const ConceptDef = struct {
    loc: Loc,
    name: []const u8,
    type_params: ?[]TypeExpr,
    required_methods: []FuncSignature,
    required_fields: []RequiredField,
    attributes: []Attribute = &.{},

    pub const RequiredField = struct { name: []const u8, typ: TypeExpr };
};

pub const MacroDef = struct {
    loc: Loc,
    name: []const u8,
    params: []const []const u8,
    body: MacroBody,
    hygiene: bool = true,
};

pub const MacroBody = union(enum) {
    expr: *Expr,
    block: Block,

    pub fn loc(self: MacroBody) Loc {
        return switch (self) {
            .expr => |expr| expr.loc(),
            .block => |block| block.loc,
        };
    }
};

// ── Statements ────────────────────────────────────────────────────────────────

pub const LocalName = struct {
    ident: []const u8,
    typ: TypeExpr,
    attrib: ?[]const u8, // <const> or <close>
    /// Attribute annotations on this binding (e.g. `@implements(Concept)`,
    /// `@arc(false)`, `@packed`, `@align(N)`, `@deprecated("msg")`).
    attributes: []Attribute = &.{},
    loc: Loc,
};

pub const ElseIf = struct {
    cond: *Expr,
    body: Block,
};

pub const FuncDecl = struct {
    loc: Loc,
    path: [][]const u8,
    method: bool,
    is_local: bool,
    func: FuncBody,
    attributes: []Attribute = &.{},
};

pub const Stmt = union(enum) {
    local_decl: struct {
        loc: Loc,
        names: []LocalName,
        inits: []*Expr,
    },
    const_decl: struct {
        loc: Loc,
        ident: []const u8,
        typ: TypeExpr,
        val: *Expr,
    },
    global_decl: struct {
        loc: Loc,
        /// true for `global *` (void implicit global-by-default in this block)
        star: bool,
        names: []LocalName,
        inits: []*Expr,
    },
    assign: struct {
        loc: Loc,
        targets: []*Expr,
        values: []*Expr,
        /// TRUE ONLY WHERE A `while` STOOD, and it answers ONE question:
        /// does this statement carry the enclosing block's value?
        ///
        /// A loop does not. `tail_result_demand.tailStatementResult` has no
        /// `.while_loop` arm, so a body whose last statement is a loop yields
        /// its tail expression (or nothing) — and the module entry's exit
        /// status is the low byte of exactly that answer.
        /// `loop_closure` replaces a `while` with the store its live-out
        /// holds, so WITHOUT this fact the same program in two spellings
        /// exits differently: `a = 0 ; i = 0 ; while i < 5 … ; print(a)`
        /// printed 5 and exited 5 once the loop closed, and 5/0 when the
        /// body's temporary made the loop unclosable (GAP-215). At 300 trips
        /// it exited 44 — `300 & 0xff`, the loop's trip count reaching the
        /// process status.
        ///
        /// It is a SEMANTIC fact about this statement, not provenance about
        /// where it came from: the residue of a value-less statement is
        /// value-less. `false` is the default so every parsed assignment —
        /// the only kind a source file can contain — carries a value exactly
        /// as before.
        closed_loop: bool = false,
    },
    call_stmt: struct { loc: Loc, expr: *Expr },
    expr_stmt: struct { loc: Loc, expr: *Expr },
    do_block: struct { loc: Loc, body: Block },
    while_loop: struct { loc: Loc, cond: *Expr, body: Block },
    repeat_loop: struct { loc: Loc, body: Block, cond: *Expr },
    if_stmt: struct {
        loc: Loc,
        /// `if name = expr` binding condition (evaluated before truth test).
        binding: ?struct { name: []const u8, expr: *Expr } = null,
        cond: *Expr,
        then: Block,
        elseifs: []ElseIf,
        else_body: ?Block,
    },
    num_for: struct {
        loc: Loc,
        var_name: []const u8,
        var_typ: TypeExpr,
        start: *Expr,
        stop: *Expr,
        step: ?*Expr,
        body: Block,
        unroll: ?u32 = null,
    },
    gen_for: struct {
        loc: Loc,
        vars: [][]const u8,
        iters: []*Expr,
        body: Block,
    },
    func_decl: FuncDecl,
    ret: struct { loc: Loc, vals: []*Expr },
    brk: Loc,
    cont: Loc,
    goto_stmt: struct { loc: Loc, label: []const u8 },
    label_stmt: struct { loc: Loc, label: []const u8 },
    // NOTE: there is no `struct_def` variant. Typed records are expressed as
    // anonymous record-type annotations on bindings (LocalName.typ or
    // FuncParam.typ). See the `record` variant of `TypeExpr`.
    match_stmt: MatchExpr,
    try_stmt: TryStmt,
    defer_stmt: DeferStmt,
    enum_def: EnumDef,
    concept_def: ConceptDef,
    alias_def: AliasDef,
    macro_def: MacroDef,
    cinclude: struct { loc: Loc, header: []const u8 },
    /// Module-level `@build.*` directive (e.g. `@build.exe({ name = "app", ... })`).
    directive: struct { loc: Loc, attr: Attribute },
};

/// A user-defined table type (like a class/struct), declared with `alias`.
pub const AliasDef = struct {
    loc: Loc,
    name: []const u8,
    /// Optional type parameters for generic aliases such as `type Vec<T> = List[T]`.
    type_params: ?[]TypeExpr = null,
    /// Type alias target for `type Name = Type` / `alias Name = Type`.
    target: ?TypeExpr = null,
    /// Optional parent alias for single inheritance (extends Parent).
    parent: ?[]const u8 = null,
    /// Additional parent aliases for multi-parent composition (GP-012).
    extra_parents: []const []const u8 = &.{},
    /// Fields: name, type, and whether private.
    fields: []AliasField,
    /// Methods defined on this alias.
    methods: []FuncDecl,
    /// Attributes (@packed, @align, etc.)
    attributes: []Attribute = &.{},
};

pub const AliasField = struct {
    name: []const u8,
    typ: TypeExpr,
    is_private: bool,
    default_val: ?*Expr = null,
    loc: Loc,
};

/// One field of an inline record type literal: `{ name: T, name2: U, ... }`.
pub const RecordField = struct {
    name: []const u8,
    typ: TypeExpr,
    loc: Loc,
};

// DELETED by APPLY-ONE (c0 §44 `law.construct.zero` deny-list `recordinit`):
// `TableLitField { name, val, loc }` was a second spelling of
// `TableField.named { key, val }` with a `loc`. Its doc-comment asserted "the
// sema pass uses these to verify that an initializer matches its record-type
// annotation"; sema does not, and never did — a repo-wide grep found the type
// declared here and referenced NOWHERE. A dead duplicate of the pack's field
// shape is exactly where a second construction path grows back, so it goes.

pub const Block = struct {
    loc: Loc,
    stmts: []Stmt,
    tail_expr: ?*Expr = null,
};

pub const Module = struct {
    file: []const u8,
    body: Block,

    /// File-scope statements or a tail expression that *do* something, as
    /// opposed to declarations that only bind. The tail is the program.
    pub fn program(self: *const Module) bool {
        if (self.body.tail_expr != null) return true;
        for (self.body.stmts) |*stmt| switch (stmt.*) {
            .call_stmt,
            .expr_stmt,
            .assign,
            .do_block,
            .while_loop,
            .repeat_loop,
            .if_stmt,
            .num_for,
            .gen_for,
            .ret,
            .match_stmt,
            .try_stmt,
            .defer_stmt,
            => return true,
            else => {},
        };
        return false;
    }
};

// ── Tests ─────────────────────────────────────────────────────────────────────

const testing = @import("std").testing;

test "TypeExpr.is_numeric" {
    try testing.expect((TypeExpr{ .named = "i32" }).is_numeric());
    try testing.expect((TypeExpr{ .named = "i64" }).is_numeric());
    try testing.expect((TypeExpr{ .named = "u8" }).is_numeric());
    try testing.expect((TypeExpr{ .named = "f32" }).is_numeric());
    try testing.expect((TypeExpr{ .named = "f64" }).is_numeric());
    try testing.expect(!(TypeExpr{ .named = "bool" }).is_numeric());
    try testing.expect(!(TypeExpr{ .named = "str" }).is_numeric());
    try testing.expect(!((@as(TypeExpr, .inferred)).is_numeric()));
}

test "TypeExpr.is_integer" {
    try testing.expect((TypeExpr{ .named = "i8" }).is_integer());
    try testing.expect((TypeExpr{ .named = "i16" }).is_integer());
    try testing.expect((TypeExpr{ .named = "i32" }).is_integer());
    try testing.expect((TypeExpr{ .named = "i64" }).is_integer());
    try testing.expect((TypeExpr{ .named = "u8" }).is_integer());
    try testing.expect((TypeExpr{ .named = "u64" }).is_integer());
    try testing.expect(!(TypeExpr{ .named = "f32" }).is_integer());
    try testing.expect(!(TypeExpr{ .named = "bool" }).is_integer());
}

test "TypeExpr.is_float" {
    try testing.expect((TypeExpr{ .named = "f32" }).is_float());
    try testing.expect((TypeExpr{ .named = "f64" }).is_float());
    try testing.expect(!(TypeExpr{ .named = "i32" }).is_float());
    try testing.expect(!((@as(TypeExpr, .inferred)).is_float()));
}

test "TypeExpr.eql: identical named types" {
    const a = TypeExpr{ .named = "i32" };
    const b = TypeExpr{ .named = "i32" };
    try testing.expect(a.eql(b));
}

test "TypeExpr.eql: different named types" {
    const a = TypeExpr{ .named = "i32" };
    const b = TypeExpr{ .named = "i64" };
    try testing.expect(!a.eql(b));
}

test "TypeExpr.eql: inferred == inferred" {
    try testing.expect((@as(TypeExpr, .inferred)).eql(.inferred));
}

test "TypeExpr.eql: inferred != named" {
    try testing.expect(!((@as(TypeExpr, .inferred)).eql(.{ .named = "i32" })));
}

test "Expr.loc returns correct location for all variants" {
    const loc = Loc{ .line = 42, .col = 10, .file = "test.id" };
    var dummy_expr = Expr{ .nil = loc };
    var dummy_func_body = FuncBody{
        .loc = loc,
        .params = &.{},
        .vararg = false,
        .ret_type = .inferred,
        .body = Block{ .loc = loc, .stmts = &.{} },
    };
    var dummy_match_expr = MatchExpr{
        .loc = loc,
        .scrutinee = &dummy_expr,
        .arms = &.{},
    };

    const exprs = [_]Expr{
        .{ .nil = loc },
        .{ .true_lit = loc },
        .{ .false_lit = loc },
        .{ .int_lit = .{ .loc = loc, .val = 42 } },
        .{ .float_lit = .{ .loc = loc, .val = 3.14 } },
        .{ .quoted = .{ .loc = loc, .val = "hello" } },
        .{ .vararg = loc },
        .{ .name = .{ .loc = loc, .ident = "foo" } },
        .{ .index = .{ .loc = loc, .obj = &dummy_expr, .key = &dummy_expr } },
        .{ .field = .{ .loc = loc, .obj = &dummy_expr, .field = "bar" } },
        .{ .call = .{ .loc = loc, .func = &dummy_expr, .args = &.{} } },
        .{ .method_call = .{ .loc = loc, .obj = &dummy_expr, .method = "meth", .args = &.{} } },
        .{ .binop = .{ .loc = loc, .op = .add, .lhs = &dummy_expr, .rhs = &dummy_expr } },
        .{ .unop = .{ .loc = loc, .op = .neg, .operand = &dummy_expr } },
        .{ .func_expr = &dummy_func_body },
        .{ .table = .{ .loc = loc, .fields = &.{} } },
        .{ .list_comp = .{ .loc = loc, .value = &dummy_expr, .key_name = null, .value_name = "x", .iter = &dummy_expr } },
        .{ .try_expr = .{ .loc = loc, .operand = &dummy_expr } },
        .{ .unwrap_expr = .{ .loc = loc, .operand = &dummy_expr } },
        .{ .match_expr = &dummy_match_expr },
        .{ .await_expr = .{ .loc = loc, .operand = &dummy_expr } },
        .{ .contains_expr = .{ .loc = loc, .lhs = &dummy_expr, .rhs = &dummy_expr } },
    };

    for (exprs) |expr| {
        try testing.expectEqual(loc, expr.loc());
    }
}

test "Expr has no collapsed string literal identity" {
    try testing.expect(!@hasField(Expr, "string_lit"));
    try testing.expect(@hasField(Expr, "quoted"));

    const loc = Loc{ .line = 1, .col = 1, .file = "quote.id" };
    const text = Expr{ .quoted = .{ .loc = loc, .val = "x", .quote = .text } };
    const bytes = Expr{ .quoted = .{ .loc = loc, .val = "x", .quote = .bytes } };
    try testing.expectEqual(Quote.text, text.quoted.quote);
    try testing.expectEqual(Quote.bytes, bytes.quoted.quote);
}
