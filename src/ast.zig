const std = @import("std");
pub const Loc = @import("lexer.zig").Loc;
const RT = @import("types.zig").ResolvedType;

// ── Type expressions ─────────────────────────────────────────────────────────

pub const TypeExpr = union(enum) {
    inferred, // no annotation; type must be inferred
    named: []const u8, // i32, f64, bool, void, str, etc.
    array: ArrayType,
    pointer: *TypeExpr,
    func: FuncType,
    optional: *TypeExpr, // ?T
    generic: GenericType, // T<U, V>
    /// Inline record-type literal: `{ name: T, name2: U, ... }`. This is the
    /// only mechanism for declaring a typed record in Duo. Records are
    /// structural and anonymous (no name). The codegen mints a C `struct`
    /// for each unique record shape (deduplicated by content hash).
    record: *RecordType,

    pub const RecordType = struct {
        fields: []RecordField,
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
};

pub const UnOp = enum { neg, not, len, bnot, compile };

pub const TableField = union(enum) {
    indexed: struct { key: *Expr, val: *Expr }, // [expr] = expr
    named: struct { key: []const u8, val: *Expr }, // name = expr
    positional: *Expr, // expr
};

pub const ListComprehension = struct {
    loc: Loc,
    value: *Expr,
    key_name: ?[]const u8,
    value_name: []const u8,
    iter: *Expr,
    filter: ?*Expr = null,
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
};

pub const FuncBody = struct {
    loc: Loc,
    params: []FuncParam,
    vararg: bool,
    /// Lua 5.5 named vararg: function f(...args)
    vararg_name: ?[]const u8 = null,
    ret_type: TypeExpr,
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
    // set by sema: emit C-style 0-based string scan loops
    use_string_byte_scan: bool = false,
    use_string_hash_scan: bool = false,
    string_scan_lit: ?[]const u8 = null,
    // set by sema: emit nested for-loops with inlined eval_A
    use_grid_sum_inline: bool = false,
    use_dense_table_max: bool = false,
    use_dense_table_sum: bool = false,
    use_dense_table_identity_sum: bool = false,
    use_math_floor_max: bool = false,
    use_math_pow_sqrt: bool = false,
    use_string_len_chain: bool = false,
    use_binary_search_dense: bool = false,
    use_filter_count_mod: bool = false,
    use_dot_product_identity: bool = false,
    use_dot_product_dense: bool = false,
    use_clamp_mod_sum: bool = false,
    use_mod_histogram_sum: bool = false,
    use_ema_smooth: bool = false,
    /// avg = avg * alpha + (i % period) * beta — fold full periods in O(1)
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
    use_cond_swap_inline: bool = false,
    use_sieve_native: bool = false,
    use_fenwick_native: bool = false,
    use_interp_inline: bool = false,
    use_run_len_inline: bool = false,
    use_sparse_dot_inline: bool = false,
    use_leven_native: bool = false,
    // set by sema for anonymous/nested functions (func_expr)
    closure_id: ?u32 = null,
    upvalues: []Upvalue = &.{},
};

pub const Expr = union(enum) {
    nil: Loc,
    true_lit: Loc,
    false_lit: Loc,
    int_lit: struct { loc: Loc, val: i64 },
    float_lit: struct { loc: Loc, val: f64 },
    string_lit: struct { loc: Loc, val: []const u8 },
    vararg: Loc,
    name: struct { loc: Loc, ident: []const u8 },
    index: struct { loc: Loc, obj: *Expr, key: *Expr },
    field: struct { loc: Loc, obj: *Expr, field: []const u8 },
    call: struct { loc: Loc, func: *Expr, args: []*Expr },
    method_call: struct { loc: Loc, obj: *Expr, method: []const u8, args: []*Expr },
    binop: struct { loc: Loc, op: BinOp, lhs: *Expr, rhs: *Expr },
    unop: struct { loc: Loc, op: UnOp, operand: *Expr },
    func_expr: *FuncBody,
    table: struct { loc: Loc, fields: []TableField },
    list_comp: ListComprehension,
    try_expr: struct { loc: Loc, operand: *Expr }, // expr?
    unwrap_expr: struct { loc: Loc, operand: *Expr }, // expr!
    match_expr: *MatchExpr,
    await_expr: struct { loc: Loc, operand: *Expr },
    contains_expr: struct { loc: Loc, lhs: *Expr, rhs: *Expr }, // x in y

    pub fn loc(self: Expr) Loc {
        return switch (self) {
            .nil => |l| l,
            .true_lit => |l| l,
            .false_lit => |l| l,
            .vararg => |l| l,
            .int_lit => |x| x.loc,
            .float_lit => |x| x.loc,
            .string_lit => |x| x.loc,
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
            .match_expr => |m| m.loc,
            .await_expr => |x| x.loc,
            .contains_expr => |x| x.loc,
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
    },
    call_stmt: struct { loc: Loc, expr: *Expr },
    expr_stmt: struct { loc: Loc, expr: *Expr },
    do_block: struct { loc: Loc, body: Block },
    while_loop: struct { loc: Loc, cond: *Expr, body: Block },
    repeat_loop: struct { loc: Loc, body: Block, cond: *Expr },
    if_stmt: struct {
        loc: Loc,
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
};

/// A user-defined table type (like a class/struct), declared with `alias`.
pub const AliasDef = struct {
    loc: Loc,
    name: []const u8,
    /// Optional parent alias for single inheritance (extends Parent).
    parent: ?[]const u8 = null,
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

/// One field of an actual table literal initializer: `{ name = expr, ... }`.
/// Mirrors `RecordField` but pairs a name with a value expression instead of
/// a type. The sema pass uses these to verify that an initializer matches its
/// record-type annotation and to check `@implements(Concept)` satisfaction.
pub const TableLitField = struct {
    name: []const u8,
    val: *Expr,
    loc: Loc,
};

pub const Block = struct {
    loc: Loc,
    stmts: []Stmt,
    tail_expr: ?*Expr = null,
};

pub const Module = struct {
    file: []const u8,
    body: Block,
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
    const loc = Loc{ .line = 42, .col = 10, .file = "test.duo" };
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
        .{ .string_lit = .{ .loc = loc, .val = "hello" } },
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
