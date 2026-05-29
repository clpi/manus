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

pub const UnOp = enum { neg, not, len, bnot };

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

pub const FuncBody = struct {
    loc: Loc,
    params: []FuncParam,
    vararg: bool,
    ret_type: TypeExpr,
    body: Block,
    // set by sema: is the function fully typed (all params + ret annotated)?
    is_typed: bool = false,
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
