const std = @import("std");
pub const Loc = @import("lexer.zig").Loc;
const types = @import("types.zig");
const RT = types.ResolvedType;
const decimal = @import("decimal.zig");

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
/// `{ … }` is one construct with two stances, and they are stances of the SAME
/// form rather than two mechanisms:
///
///     { x = 1 }         an anonymous structured value      applied=0
///     point{ x = 1 }    the pack of an application         applied=1
///
/// THERE WAS A THIRD ROW — `@{ x = 1 }`, "the same, subject name elided",
/// carried by an `elided` flag beside `applied`. `law.injection.only` rules the
/// sigil EXCLUSIVELY world-deriving, fd85e7b8 made the parser refuse the
/// descriptor reading, and the flag was left behind with ZERO producers: no
/// path ever set it, and its only remaining mention was a test asserting it was
/// false. A stance no reader can enter is not a stance, and a teaching row for
/// a spelling the compiler refuses is worse than no row (gap[223]).
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
    /// The enclosing descriptor this parse was reading for, when there was one.
    /// Null at top level. Unlike `elided`, this one still has a producer:
    /// `parse_pack` reads `descriptor_home`, which the copula descriptor reader
    /// sets while it is reading a body.
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

    /// The scalar numeric facts a bare TYPE-EXPRESSION SPELLING names, or null.
    ///
    /// DERIVED, NOT TABULATED — this is the SOURCE FACE of `numericFacts`, and
    /// the three name rosters below (`is_numeric`, `is_integer`, `is_float`)
    /// were three further statements of which spellings are numeric, integral
    /// and real, beside the one owner in `types.zig`. They are now one query
    /// through `descriptorNamed`, exactly as `narrowIntOfType` — the annotation
    /// face of the WRITE projection — already derives its width from the same
    /// facts. A roster cannot compose: a spelling added to the `ResolvedType`
    /// union is one these switches silently did not know, and a fact answered
    /// three ways drifts three ways.
    ///
    /// The face this preserves is the scalar-SPELLING face, so two filters keep
    /// it exact rather than widening it. `nominalReprOf` is null-checked because
    /// a nominal descriptor DELEGATES `numericFacts` to its representation on
    /// purpose (physics is a representation question, `law.nominal` §46) — but
    /// `feet` is not a numeric SPELLING and never answered these three, so the
    /// source face must not look through it. `lanes == 1` is required because a
    /// vector identity (`v4f64`) is a numeric fact owner the old roster also did
    /// not list; its bare spelling is not a scalar type expression.
    fn scalarFacts(self: TypeExpr) ?types.NumericFacts {
        if (self != .named) return null;
        const named = types.descriptorNamed(self.named) orelse return null;
        if (types.nominalReprOf(named) != null) return null;
        const facts = named.numericFacts() orelse return null;
        if (facts.lanes != 1) return null;
        return facts;
    }

    pub fn is_numeric(self: TypeExpr) bool {
        return self.scalarFacts() != null;
    }

    pub fn is_integer(self: TypeExpr) bool {
        const facts = self.scalarFacts() orelse return false;
        return facts.domain == .integral;
    }

    pub fn is_float(self: TypeExpr) bool {
        const facts = self.scalarFacts() orelse return false;
        return facts.domain == .real;
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

/// Relation identity is NOT the tree's to own (gate/layers.manifest: "AST
/// owns shape. Owns NO semantic relation identity"). These are ALIASES of the
/// one grammar owner's ontology, generated from `lib/compiler/token.id` into
/// `src/grammar_role_table.zig`. The row that gives `.plus` its binding power
/// is the row that names its relation `add`, so a tree node and a parser
/// decision cannot come to different conclusions about which operation
/// occurred. `matmul` is infix `@` (distinct from prefix `@macro`);
/// `pipeline` is `|>`, where `x |> f` desugars to `f(x)`.
pub const BinOp = @import("grammar_role_table.zig").Relation;

pub const UnOp = @import("grammar_role_table.zig").Prefix;

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
    /// Set by sema when it rewrites an `.inferred` type to a concrete guess
    /// (NativeInfer specialization, shape-based signature promotion, method
    /// self seeding). The spelling no longer shows the inference, but backend
    /// admission must still treat the type as a guess and verify call sites
    /// against it instead of trusting it like a declaration.
    specialized: bool = false,
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
    use_iterative_fact: bool = false,
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
/// The two operands named by the XOR idiom `x + y - 2*(x & y)`, or null.
///
/// `x + y - 2*(x&y)` is exactly `x ^ y` over wrapping bit-vector arithmetic:
/// `x + y = (x ^ y) + 2*(x & y)`, so the difference is the xor. The identity
/// is bit-local, hence width-agnostic. Either `add` operand order and either
/// `mul` operand order are admitted; the four operand positions must be bare
/// names and the `add` pair must name the same two bindings as the `band`
/// pair (in either order), so both occurrences of each name read the same
/// value. Anything else -- a non-2 literal, `x | y` under the `2*`, operands
/// that are not bare names, mismatched pairs -- declines, and the expression
/// lowers as written.
pub fn xorIdiomOperands(sub_lhs: *const Expr, sub_rhs: *const Expr) ?struct { a: *const Expr, b: *const Expr } {
    if (sub_lhs.* != .binop or sub_lhs.binop.op != .add) return null;
    if (sub_rhs.* != .binop or sub_rhs.binop.op != .mul) return null;
    const m = sub_rhs.binop;
    const band_e = if (intLiteralValue(m.lhs)) |v|
        (if (v == 2) m.rhs else return null)
    else if (intLiteralValue(m.rhs)) |v|
        (if (v == 2) m.lhs else return null)
    else
        return null;
    if (band_e.* != .binop or band_e.binop.op != .band) return null;
    const add_a = sub_lhs.binop.lhs;
    const add_b = sub_lhs.binop.rhs;
    const band_a = band_e.binop.lhs;
    const band_b = band_e.binop.rhs;
    if (add_a.* != .name or add_b.* != .name or band_a.* != .name or band_b.* != .name) return null;
    const a1 = add_a.name.ident;
    const b1 = add_b.name.ident;
    const a2 = band_a.name.ident;
    const b2 = band_b.name.ident;
    const same = (std.mem.eql(u8, a1, a2) and std.mem.eql(u8, b1, b2)) or
        (std.mem.eql(u8, a1, b2) and std.mem.eql(u8, b1, a2));
    if (!same) return null;
    return .{ .a = add_a, .b = add_b };
}

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

/// Does an expression subtree name `ident` anywhere? Used to decide whether a
/// relation-edge projection level (`family(level) = (…)`, mangled `family__level`)
/// is a runtime subject parameter or a compile-time-only qualifier.
///
///   `len(path) = (min)` body reads `path` → the level is a runtime subject slot;
///     it is applied `len(value)(min)` / `value:len(min)` (level passed as an arg).
///   `subject(tail) = (code)` body never reads `tail` → the level is a pure
///     compile-time marker baked into the mangled callee `subject__tail`; the call
///     `subject(tail)(code)` lowers to `subject__tail(code)` with the level absent
///     from the operand list, so allocating a level slot would misplace `code`.
pub fn exprMentionsIdent(expr: *const Expr, ident: []const u8) bool {
    return switch (expr.*) {
        .name => |n| std.mem.eql(u8, n.ident, ident),
        .index => |x| exprMentionsIdent(x.obj, ident) or exprMentionsIdent(x.key, ident),
        .field => |x| exprMentionsIdent(x.obj, ident),
        .call => |c| blk: {
            if (exprMentionsIdent(c.func, ident)) break :blk true;
            for (c.args) |a| if (exprMentionsIdent(a, ident)) break :blk true;
            break :blk false;
        },
        .method_call => |m| blk: {
            if (exprMentionsIdent(m.obj, ident)) break :blk true;
            for (m.args) |a| if (exprMentionsIdent(a, ident)) break :blk true;
            break :blk false;
        },
        .binop => |b| exprMentionsIdent(b.lhs, ident) or exprMentionsIdent(b.rhs, ident),
        .unop => |u| exprMentionsIdent(u.operand, ident),
        .if_expr => |ie| exprMentionsIdent(ie.cond, ident) or
            exprMentionsIdent(ie.then_expr, ident) or exprMentionsIdent(ie.else_expr, ident),
        .try_expr => |x| exprMentionsIdent(x.operand, ident),
        .unwrap_expr => |x| exprMentionsIdent(x.operand, ident),
        .await_expr => |x| exprMentionsIdent(x.operand, ident),
        .contains_expr => |x| exprMentionsIdent(x.lhs, ident) or exprMentionsIdent(x.rhs, ident),
        .sequence => |s| blk: {
            for (s.exprs) |e| if (exprMentionsIdent(e, ident)) break :blk true;
            break :blk false;
        },
        .range => |r| exprMentionsIdent(r.start, ident) or exprMentionsIdent(r.end, ident) or
            (if (r.step) |st| exprMentionsIdent(st, ident) else false),
        else => false,
    };
}

pub fn blockMentionsIdent(block: *const Block, ident: []const u8) bool {
    for (block.stmts) |*s| if (stmtMentionsIdent(s, ident)) return true;
    if (block.tail_expr) |t| return exprMentionsIdent(t, ident);
    return false;
}

pub fn stmtMentionsIdent(stmt: *const Stmt, ident: []const u8) bool {
    return switch (stmt.*) {
        .local_decl => |d| blk: {
            for (d.inits) |e| if (exprMentionsIdent(e, ident)) break :blk true;
            break :blk false;
        },
        .const_decl => |d| exprMentionsIdent(d.val, ident),
        .global_decl => |d| blk: {
            for (d.inits) |e| if (exprMentionsIdent(e, ident)) break :blk true;
            break :blk false;
        },
        .assign => |a| blk: {
            for (a.targets) |e| if (exprMentionsIdent(e, ident)) break :blk true;
            for (a.values) |e| if (exprMentionsIdent(e, ident)) break :blk true;
            break :blk false;
        },
        .call_stmt => |c| exprMentionsIdent(c.expr, ident),
        .expr_stmt => |c| exprMentionsIdent(c.expr, ident),
        .do_block => |d| blockMentionsIdent(&d.body, ident),
        .while_loop => |w| exprMentionsIdent(w.cond, ident) or blockMentionsIdent(&w.body, ident),
        .repeat_loop => |r| blockMentionsIdent(&r.body, ident) or exprMentionsIdent(r.cond, ident),
        .if_stmt => |f| blk: {
            if (f.binding) |b| if (exprMentionsIdent(b.expr, ident)) break :blk true;
            if (exprMentionsIdent(f.cond, ident)) break :blk true;
            if (blockMentionsIdent(&f.then, ident)) break :blk true;
            for (f.elseifs) |ei| {
                if (exprMentionsIdent(ei.cond, ident)) break :blk true;
                if (blockMentionsIdent(&ei.body, ident)) break :blk true;
            }
            if (f.else_body) |eb| if (blockMentionsIdent(&eb, ident)) break :blk true;
            break :blk false;
        },
        .num_for => |n| exprMentionsIdent(n.start, ident) or exprMentionsIdent(n.stop, ident) or
            (if (n.step) |st| exprMentionsIdent(st, ident) else false) or blockMentionsIdent(&n.body, ident),
        .gen_for => |g| blk: {
            for (g.iters) |e| if (exprMentionsIdent(e, ident)) break :blk true;
            break :blk blockMentionsIdent(&g.body, ident);
        },
        .ret => |r| blk: {
            for (r.vals) |e| if (exprMentionsIdent(e, ident)) break :blk true;
            break :blk false;
        },
        else => false,
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
    /// `val` is the f64 REALIZATION of this spelling; `dec` is what the
    /// spelling MEANS. `dec` is absent exactly when the carrier declined the
    /// spelling (hex float, out-of-band exponent, more digits than it holds),
    /// and a consumer that reads `val` in its absence is reading a realization
    /// it has no exact fact for.
    float_lit: struct { loc: Loc, val: f64, dec: ?decimal.Decimal = null },
    /// Quoted source or a host-fabricated byte sequence. `quote` is the
    /// producer identity (GAP-145); `.host` is not a source quote.
    quoted: struct { loc: Loc, val: []const u8, quote: Quote = .host },
    vararg: Loc,
    /// A NAME, and WHICH FACT SET RESOLVED IT.
    ///
    /// `x` and `@x` denote the same semantic thing whenever the current world
    /// is what supplies `x` — `law.md` §1, one semantic thing, one exact id —
    /// so the world face is a FACT ON THE NAME, not a second node kind. What
    /// the flag changes is which fact set is consulted: `world = false` reads
    /// the lexical scope first and the current world only when no binding
    /// answers; `world = true` reads the CURRENT WORLD and never the lexical
    /// scope, which is the whole capability (`world.md`: "Lexical binding wins
    /// for a bare lexical name; `@x` accesses the world member explicitly").
    ///
    /// Unlike `field.anchored`, this IS read downstream: sema resolves it,
    /// `semantic_graph.worldOfApplication` refuses to let a same-named module
    /// relation claim the occurrence, and `pretty` writes the sigil back.
    name: struct { loc: Loc, ident: []const u8, world: bool = false },
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
    /// A PREFIX OPERATION, and for `.compile` also WHICH SOURCE FACE spelled it.
    ///
    /// `@(expr)` and `expr@{ stage = compile }` are the SAME NODE, deliberately.
    /// `law.stage.world` (C0 §52) rules them one meaning — the current world
    /// applied to an expression, resolved at the stage that world carries — and
    /// `law.md` §9 says of exactly this situation that faces denoting the same
    /// application "share one occurrence identity and one relation identity;
    /// provenance records the face used". `world_face` is that provenance: the
    /// printer writes back the spelling that was written, and nothing else
    /// reads it. Making them two nodes would have been a second authority for
    /// one meaning, and every downstream pass would have had to learn that the
    /// two agree.
    unop: struct { loc: Loc, op: UnOp, operand: *Expr, world_face: bool = false },
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

    /// A zero-operand module relation whose result a process can EXIT with.
    /// `f64` is admitted because the link step coerces it (`fcvtzs x0, d0`).
    ///
    /// ONE DEFINITION. `native_backend.isZeroArgEntryFunction` is this function
    /// — entry eligibility decides both which relation an executable may be
    /// pointed at and which relation owns the bare process symbol, and two
    /// spellings of that predicate is how those two answers drift apart.
    pub fn processEntryEligible(self: *const FuncDecl) bool {
        if (self.path.len != 1 or self.method or self.is_local) return false;
        if (self.func.params.len != 0) return false;
        return switch (self.func.ret_type) {
            .named => |n| @import("std").mem.eql(u8, n, "i32") or
                @import("std").mem.eql(u8, n, "i64") or
                @import("std").mem.eql(u8, n, "u32") or
                @import("std").mem.eql(u8, n, "u64") or
                @import("std").mem.eql(u8, n, "void") or
                self.func.ret_type.is_float(),
            else => false,
        };
    }

    /// Is this the relation spelled `main` AND eligible to be the process?
    /// The spelling alone is not the fact: `main: i64 = (x: i64)` is an
    /// ordinary relation that happens to share a word with the C runtime.
    pub fn namesProcessEntry(self: *const FuncDecl) bool {
        if (!self.processEntryEligible()) return false;
        return @import("std").mem.eql(u8, self.path[0], "main");
    }
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
        for (self.body.stmts, 0..) |*stmt, at| switch (stmt.*) {
            // A MODULE-SCOPE `name = expr` IS A BINDING, NOT EXECUTION.
            //
            // idol has no `local` keyword, so the untyped spelling of a module
            // binding parses as `.assign` — the same node a relation body
            // produces — while the annotated spelling `name: T = expr` parses
            // as `.local_decl`, which this predicate has always read as a
            // declaration. Counting one and not the other made the ANNOTATION
            // decide whether the file is a program.
            //
            // Measured (gap[228]): `m = 7` beside `main: i64 = () m` selected
            // the root over `main` in `selectProcessEntry`, and the root has
            // no tail, so the process exited 0 with no diagnostic; the
            // identical file spelled `m: i64 = 7` exited 7. Every expression
            // over such a binding collapsed the same way, because the relation
            // computing it was simply never called.
            .assign => if (!self.assignOnlyBinds(at)) return true,
            .call_stmt,
            .expr_stmt,
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

    /// Is the file-scope assignment at `at` the DECLARATION of its names, and
    /// nothing more?
    ///
    /// Only the FIRST binding of a bare name qualifies, so this arm says
    /// exactly what the `.local_decl` arm says and no more:
    ///
    ///   * a target that is not a bare name (`M.x = 1`, `xs[1] = 2`) writes
    ///     into something that already exists — execution;
    ///   * a name this module already bound above is a REBINDING the module
    ///     body has to run to be correct — execution;
    ///   * `closed_loop` marks an assignment a loop closure put here in place
    ///     of a `while` (GAP-215). It carries a loop's residue, never a
    ///     declaration.
    fn assignOnlyBinds(self: *const Module, at: usize) bool {
        const a = self.body.stmts[at].assign;
        if (a.closed_loop) return false;
        if (a.targets.len == 0) return false;
        for (a.targets) |t| {
            if (t.* != .name) return false;
            if (self.bindsNameBefore(at, t.name.ident)) return false;
        }
        return true;
    }

    /// Does any file-scope statement STRICTLY BEFORE `at` bind `ident`?
    fn bindsNameBefore(self: *const Module, at: usize, ident: []const u8) bool {
        const eql = @import("std").mem.eql;
        for (self.body.stmts[0..at]) |*stmt| switch (stmt.*) {
            .local_decl => |ld| for (ld.names) |n| {
                if (eql(u8, n.ident, ident)) return true;
            },
            .global_decl => |gd| for (gd.names) |n| {
                if (eql(u8, n.ident, ident)) return true;
            },
            .const_decl => |cd| if (eql(u8, cd.ident, ident)) return true,
            .func_decl => |fd| if (fd.path.len == 1 and eql(u8, fd.path[0], ident)) return true,
            .assign => |a| for (a.targets) |t| {
                if (t.* == .name and eql(u8, t.name.ident, ident)) return true;
            },
            else => {},
        };
        return false;
    }

    /// THE PROCESS ENTRY THIS SOURCE MODULE OFFERS, and null when it offers
    /// none.
    ///
    /// WHY THIS IS A MODULE QUESTION AND NOT A NAME QUESTION. The symbol law in
    /// `home_resolve.zig` says a relation is `(home, name)` and lists the
    /// process entry as its first foreign-boundary exemption: `main` is the C
    /// runtime's name, not ours. The exemption used to be applied by comparing
    /// the NAME to `"main"` inside `relationSymbol`, and that was wrong in one
    /// direction — a module that is ITSELF the program already owns the bare
    /// symbol through its root, so a relation named `main` beside file-scope
    /// execution produced the symbol twice in one object.
    ///
    /// Deleting the exemption instead of narrowing it lost the other direction,
    /// and this is the measurement: with `helper` and `main` in one home,
    /// `--emit obj` emitted `_idol_<home>__helper _idol_<home>__main` and NO
    /// `_main` at all, so `ld -r` over two independent programs each declaring
    /// `main` merged cleanly, rc 0. Home qualification exists to remove the
    /// collisions two homes must not have; it deliberately KEEPS this one,
    /// because two programs cannot share a process entry.
    ///
    /// So the exemption is narrowed, not deleted: a source relation named
    /// `main` owns the bare process symbol exactly when the module root does
    /// NOT — which is to say, exactly when that relation IS the process. One
    /// object, one `main`, in every artifact kind.
    ///
    /// `native_backend.selectProcessEntry` may still select some OTHER relation
    /// as an executable's entry (`--entry r`, or the sole zero-arg relation of
    /// a body-less module). That is a LINK-LINE choice, carried by `-Wl,-e`,
    /// and it does not rename the relation: an object is not a program, so a
    /// library that happens to hold one zero-arg relation must not start
    /// exporting `_main`.
    pub fn sourceProcessEntry(self: *const Module) ?*const FuncDecl {
        if (self.program()) return null;
        for (self.body.stmts) |*stmt| {
            if (stmt.* != .func_decl) continue;
            const fd = &stmt.func_decl;
            if (!fd.namesProcessEntry()) continue;
            return fd;
        }
        return null;
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

// The derived source face equals the retired roster on the ten scalar
// spellings it listed AND on the spellings it declined. The old switches
// enumerated i8..u64/f32/f64; the derivation reads `descriptorNamed` →
// `numericFacts` and filters nominal and vector identities so that no numeric
// fact owner the roster did not list leaks in. A vector identity (`v4f64`) is
// a numeric fact owner whose bare spelling must stay non-numeric here, and a
// declared nominal name delegates its facts on purpose yet is not a numeric
// SPELLING — both are pinned so a scalar added to the union cannot change the
// source face silently.
test "TypeExpr numeric face: derived equals retired roster, declines vectors and nominals" {
    const numeric = [_][]const u8{
        "i8", "i16", "i32", "i64",
        "u8", "u16", "u32", "u64",
        "f32", "f64",
    };
    const integral = [_][]const u8{
        "i8", "i16", "i32", "i64",
        "u8", "u16", "u32", "u64",
    };
    const real = [_][]const u8{ "f32", "f64" };

    for (numeric) |n| {
        const t = TypeExpr{ .named = n };
        try testing.expect(t.is_numeric());
        const want_int = for (integral) |m| {
            if (std.mem.eql(u8, n, m)) break true;
        } else false;
        try testing.expectEqual(want_int, t.is_integer());
        const want_real = for (real) |m| {
            if (std.mem.eql(u8, n, m)) break true;
        } else false;
        try testing.expectEqual(want_real, t.is_float());
    }

    // Declined: vector identities own numeric facts but are not scalar
    // spellings, non-numeric words, and structural faces.
    const declined = [_][]const u8{ "v4f64", "v4i64", "v8f32", "v8i32", "bool", "str", "void", "any", "nil" };
    for (declined) |n| {
        const t = TypeExpr{ .named = n };
        try testing.expect(!t.is_numeric());
        try testing.expect(!t.is_integer());
        try testing.expect(!t.is_float());
    }
    try testing.expect(!((@as(TypeExpr, .inferred)).is_numeric()));
    try testing.expect(!((@as(TypeExpr, .inferred)).is_integer()));
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
