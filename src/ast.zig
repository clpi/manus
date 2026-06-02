const std = @import("std");
pub const Loc = @import("lexer.zig").Loc;

// ── Type expressions ─────────────────────────────────────────────────────────

pub const TypeExpr = union(enum) {
    inferred, // no annotation; type must be inferred
    named: []const u8, // i32, f64, bool, void, str, or user struct name
    array: ArrayType,
    pointer: *TypeExpr,
    func: FuncType,
    optional: *TypeExpr, // ?T
    generic: GenericType, // T<U, V>

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
                "i8", "i16", "i32", "i64",
                "u8", "u16", "u32", "u64",
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

    pub fn eql(a: TypeExpr, b: TypeExpr) bool {
        return switch (a) {
            .inferred => switch (b) { .inferred => true, else => false },
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
            .func => false,
            .generic => false,
        };
    }
};

// ── Expressions ───────────────────────────────────────────────────────────────

pub const BinOp = enum {
    add, sub, mul, div, idiv, mod, pow,
    band, bor, bxor, lshift, rshift,
    concat,
    eq, neq, lt, gt, leq, geq,
    @"and", @"or",
};

pub const UnOp = enum { neg, not, len, bnot, compile };

pub const TableField = union(enum) {
    indexed: struct { key: *Expr, val: *Expr }, // [expr] = expr
    named: struct { key: []const u8, val: *Expr }, // name = expr
    positional: *Expr, // expr
};

pub const FuncParam = struct {
    name: []const u8,
    typ: TypeExpr,
    loc: Loc,
};

pub const Upvalue = struct {
    name: []const u8,
    /// true when captured from an enclosing local, false for globals
    is_local: bool,
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
    use_mandel_iter_native: bool = false,
    use_nbody_native: bool = false,
    use_force_always_inline: bool = false,
    /// always_inline + no-fast-math region (fp-sensitive natives like mandel_iter)
    use_fp_strict_always_inline: bool = false,
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
        };
    }
};

// ── Statements ────────────────────────────────────────────────────────────────

pub const LocalName = struct {
    ident: []const u8,
    typ: TypeExpr,
    attrib: ?[]const u8, // <const> or <close>
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
};

pub const StructDefPayload = struct {
    loc: Loc,
    name: []const u8,
    fields: []StructField,
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
    struct_def: StructDefPayload,
};

pub const StructField = struct {
    name: []const u8,
    typ: TypeExpr,
    default: ?*Expr,
    loc: Loc,
};

pub const Block = struct {
    loc: Loc,
    stmts: []Stmt,
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
