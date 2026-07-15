const std = @import("std");
const ast = @import("ast.zig");

/// A single variant within an enum type.
pub const EnumVariantType = struct {
    name: []const u8,
    payload: ?[]const ResolvedType,
};

/// A field within a typed table/class.
pub const FieldType = struct {
    name: []const u8,
    typ: ResolvedType,
};

/// Resolved type after semantic analysis.
/// During sema, each expression gets a `ResolvedType` attached.
pub const ResolvedType = union(enum) {
    // Primitive native types (map directly to C types)
    i8,
    i16,
    i32,
    i64,
    u8,
    u16,
    u32,
    u64,
    f32,
    f64,
    bool,
    void,

    // Managed / dynamic types
    str, // immutable C string (const char*)
    any, // dynamic Lua value — opaque at C level
    nil,
    never, // function that never returns (e.g. error())

    // SIMD vector types
    v4f64,
    v4i64,
    v8f32,
    v8i32,

    // Aggregate types
    array: struct { elem: *ResolvedType, size: ?usize },
    pointer: *ResolvedType,
    func: struct {
        params: []ResolvedType,
        ret: *ResolvedType,
        is_native: bool, // fully typed → true; has dynamic params → false
        has_vararg: bool = false,
    },
    @"struct": struct { name: []const u8 },

    // Duo extended types
    result: struct { ok: *ResolvedType, err: *ResolvedType },
    option: *ResolvedType,
    enum_type: struct {
        name: []const u8,
        variants: []EnumVariantType,
        derives: []const []const u8 = &.{},
        is_packed: bool = false,
        align_n: ?usize = null,
        ffi_name: ?[]const u8 = null,
    },
    channel: struct { elem: *ResolvedType, capacity: ?usize },
    generic_param: struct { name: []const u8, constraint: ?[]const u8 },
    table_type: struct {
        fields: []FieldType,
        is_packed: bool = false,
        align_n: ?usize = null,
        ffi_name: ?[]const u8 = null,
    },
    instantiated: struct { base: *ResolvedType, args: []ResolvedType, specialization_key: u64 },
    /// `Tensor[M,N,dtype]` — compile-time shape + element type for ML.
    tensor: struct { dims: []ResolvedType, dtype: *const ResolvedType },

    pub fn is_integer(self: ResolvedType) bool {
        return switch (self) {
            .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 => true,
            else => false,
        };
    }

    pub fn is_float(self: ResolvedType) bool {
        return switch (self) {
            .f32, .f64, .v4f64, .v8f32 => true,
            else => false,
        };
    }

    pub fn is_vector(self: ResolvedType) bool {
        return switch (self) {
            .v4f64, .v4i64, .v8f32, .v8i32 => true,
            else => false,
        };
    }

    /// Integer lane mask for vector comparisons (e.g. v4f64 cmp → v4i64).
    pub fn vector_mask(self: ResolvedType) ?ResolvedType {
        return switch (self) {
            .v4f64 => .v4i64,
            .v4i64 => .v4i64,
            .v8f32 => .v8i32,
            .v8i32 => .v8i32,
            else => null,
        };
    }

    pub fn is_numeric(self: ResolvedType) bool {
        return self.is_integer() or self.is_float();
    }

    pub fn is_native(self: ResolvedType) bool {
        return switch (self) {
            .any, .nil, .never => false,
            .result, .option, .enum_type, .channel, .generic_param, .table_type, .instantiated, .tensor => false,
            .func => |f| f.is_native,
            else => true,
        };
    }

    /// Numeric tensor dimension from a resolved dim (e.g. `Tensor[784, 256, f32]` → `784`).
    pub fn tensor_dim_const(d: ResolvedType) ?usize {
        if (d == .@"struct") {
            const n = d.@"struct".name;
            if (n.len == 0) return null;
            for (n) |c| {
                if (!std.ascii.isDigit(c)) return null;
            }
            return std.fmt.parseInt(usize, n, 10) catch null;
        }
        return null;
    }

    /// Label for a tensor dimension: numeric dims return null; symbolic names return the identifier.
    pub fn tensor_dim_label(d: ResolvedType) ?[]const u8 {
        if (d == .generic_param) return d.generic_param.name;
        if (d == .@"struct") {
            const n = d.@"struct".name;
            if (tensor_dim_const(d) != null) return null;
            return n;
        }
        return null;
    }

    /// True when both operands are 2-D tensors with known, mismatched inner (K) dimensions.
    pub fn tensor_matmul_k_incompatible(a: ResolvedType, b: ResolvedType) bool {
        const ta = switch (a) {
            .tensor => |t| t,
            else => return false,
        };
        const tb = switch (b) {
            .tensor => |t| t,
            else => return false,
        };
        if (ta.dims.len != 2 or tb.dims.len != 2) return false;
        const k_lhs = tensor_dim_const(ta.dims[1]);
        const k_rhs = tensor_dim_const(tb.dims[0]);
        if (k_lhs != null and k_rhs != null) return k_lhs.? != k_rhs.?;
        const k_lhs_l = tensor_dim_label(ta.dims[1]);
        const k_rhs_l = tensor_dim_label(tb.dims[0]);
        if (k_lhs_l != null and k_rhs_l != null and !std.mem.eql(u8, k_lhs_l.?, k_rhs_l.?)) return true;
        return false;
    }

    /// `Tensor[M,K] @ Tensor[K,N]` → `Tensor[M,N]` when both operands are 2-D tensors.
    pub fn tensor_matmul(a: ResolvedType, b: ResolvedType, alloc: std.mem.Allocator) std.mem.Allocator.Error!?ResolvedType {
        const ta = switch (a) {
            .tensor => |t| t,
            else => return null,
        };
        const tb = switch (b) {
            .tensor => |t| t,
            else => return null,
        };
        if (ta.dims.len != 2 or tb.dims.len != 2) return null;
        if (!ta.dtype.*.eql(tb.dtype.*)) return null;
        if (tensor_matmul_k_incompatible(a, b)) return null;
        const dims = try alloc.alloc(ResolvedType, 2);
        dims[0] = ta.dims[0];
        dims[1] = tb.dims[1];
        return ResolvedType{ .tensor = .{ .dims = dims, .dtype = ta.dtype } };
    }

    /// True when both operands are tensors with identical shape and dtype.
    pub fn tensor_same_shape(a: ResolvedType, b: ResolvedType) bool {
        if (a != .tensor or b != .tensor) return false;
        return a.eql(b);
    }

    /// True when concrete tensor dims are known to differ (strict elementwise; no broadcast).
    pub fn tensor_strict_shape_incompatible(a: ResolvedType, b: ResolvedType) bool {
        const ta = switch (a) {
            .tensor => |t| t,
            else => return false,
        };
        const tb = switch (b) {
            .tensor => |t| t,
            else => return false,
        };
        if (ta.dims.len != tb.dims.len or !ta.dtype.*.eql(tb.dtype.*)) return true;
        if (tensor_same_shape(a, b)) return false;
        for (ta.dims, tb.dims) |da, db| {
            if (da.eql(db)) continue;
            const ac = tensor_dim_const(da);
            const bc = tensor_dim_const(db);
            if (ac == null or bc == null) continue;
            return true;
        }
        return false;
    }

    fn tensor_dim_broadcast_compatible(da: ResolvedType, db: ResolvedType) bool {
        if (da.eql(db)) return true;
        if (tensor_dim_const(da) == 1 or tensor_dim_const(db) == 1) return true;
        const ac = tensor_dim_const(da);
        const bc = tensor_dim_const(db);
        if (ac == null or bc == null) return true;
        return false;
    }

    fn tensor_dim_broadcast_result(da: ResolvedType, db: ResolvedType, alloc: std.mem.Allocator) std.mem.Allocator.Error!ResolvedType {
        if (da.eql(db)) return da;
        const ac = tensor_dim_const(da);
        const bc = tensor_dim_const(db);
        if (ac) |a| {
            if (bc) |b| {
                const m = @max(a, b);
                const name = try std.fmt.allocPrint(alloc, "{d}", .{m});
                return ResolvedType{ .@"struct" = .{ .name = name } };
            }
            if (a == 1) return db;
        }
        if (bc) |b| {
            if (b == 1) return da;
        }
        return da;
    }

    /// True when concrete broadcast rules cannot reconcile tensor shapes.
    pub fn tensor_broadcast_shape_incompatible(a: ResolvedType, b: ResolvedType) bool {
        const ta = switch (a) {
            .tensor => |t| t,
            else => return false,
        };
        const tb = switch (b) {
            .tensor => |t| t,
            else => return false,
        };
        if (ta.dims.len != tb.dims.len or !ta.dtype.*.eql(tb.dtype.*)) return true;
        if (tensor_same_shape(a, b)) return false;
        for (ta.dims, tb.dims) |da, db| {
            if (!tensor_dim_broadcast_compatible(da, db)) return true;
        }
        return false;
    }

    /// Broadcast `Tensor` shapes (numpy-style per dim). Returns null if incompatible.
    pub fn tensor_broadcast(a: ResolvedType, b: ResolvedType, alloc: std.mem.Allocator) std.mem.Allocator.Error!?ResolvedType {
        if (tensor_broadcast_shape_incompatible(a, b)) return null;
        if (tensor_same_shape(a, b)) return a;
        const ta = a.tensor;
        const tb = b.tensor;
        const dims = try alloc.alloc(ResolvedType, ta.dims.len);
        for (ta.dims, tb.dims, 0..) |da, db, i| {
            dims[i] = try tensor_dim_broadcast_result(da, db, alloc);
        }
        return ResolvedType{ .tensor = .{ .dims = dims, .dtype = ta.dtype } };
    }

    pub fn eql(a: ResolvedType, b: ResolvedType) bool {
        return switch (a) {
            .i8 => switch (b) {
                .i8 => true,
                else => false,
            },
            .i16 => switch (b) {
                .i16 => true,
                else => false,
            },
            .i32 => switch (b) {
                .i32 => true,
                else => false,
            },
            .i64 => switch (b) {
                .i64 => true,
                else => false,
            },
            .u8 => switch (b) {
                .u8 => true,
                else => false,
            },
            .u16 => switch (b) {
                .u16 => true,
                else => false,
            },
            .u32 => switch (b) {
                .u32 => true,
                else => false,
            },
            .u64 => switch (b) {
                .u64 => true,
                else => false,
            },
            .f32 => switch (b) {
                .f32 => true,
                else => false,
            },
            .f64 => switch (b) {
                .f64 => true,
                else => false,
            },
            .v4f64 => switch (b) {
                .v4f64 => true,
                else => false,
            },
            .v4i64 => switch (b) {
                .v4i64 => true,
                else => false,
            },
            .v8f32 => switch (b) {
                .v8f32 => true,
                else => false,
            },
            .v8i32 => switch (b) {
                .v8i32 => true,
                else => false,
            },
            .bool => switch (b) {
                .bool => true,
                else => false,
            },
            .void => switch (b) {
                .void => true,
                else => false,
            },
            .str => switch (b) {
                .str => true,
                else => false,
            },
            .any => switch (b) {
                .any => true,
                else => false,
            },
            .nil => switch (b) {
                .nil => true,
                else => false,
            },
            .never => switch (b) {
                .never => true,
                else => false,
            },
            .pointer => |pa| switch (b) {
                .pointer => |pb| pa.eql(pb.*),
                else => false,
            },
            .@"struct" => |sa| switch (b) {
                .@"struct" => |sb| std.mem.eql(u8, sa.name, sb.name),
                else => false,
            },
            .result => |ra| switch (b) {
                .result => |rb| ra.ok.eql(rb.ok.*) and ra.err.eql(rb.err.*),
                else => false,
            },
            .option => |oa| switch (b) {
                .option => |ob| oa.eql(ob.*),
                else => false,
            },
            .enum_type => |ea| switch (b) {
                .enum_type => |eb| std.mem.eql(u8, ea.name, eb.name) and
                    ea.is_packed == eb.is_packed and
                    ea.align_n == eb.align_n and
                    eqlOptStr(ea.ffi_name, eb.ffi_name),
                else => false,
            },
            .channel => |ca| switch (b) {
                .channel => |cb| ca.elem.eql(cb.elem.*) and ca.capacity == cb.capacity,
                else => false,
            },
            .generic_param => |ga| switch (b) {
                .generic_param => |gb| std.mem.eql(u8, ga.name, gb.name) and eqlOptStr(ga.constraint, gb.constraint),
                else => false,
            },
            .table_type => |ta| switch (b) {
                .table_type => |tb| blk: {
                    if (ta.is_packed != tb.is_packed) break :blk false;
                    if (ta.align_n != tb.align_n) break :blk false;
                    if (!eqlOptStr(ta.ffi_name, tb.ffi_name)) break :blk false;
                    if (ta.fields.len != tb.fields.len) break :blk false;
                    for (ta.fields, tb.fields) |fa, fb| {
                        if (!std.mem.eql(u8, fa.name, fb.name)) break :blk false;
                        if (!fa.typ.eql(fb.typ)) break :blk false;
                    }
                    break :blk true;
                },
                else => false,
            },
            .instantiated => |ia| switch (b) {
                .instantiated => |ib| ia.specialization_key == ib.specialization_key,
                else => false,
            },
            .tensor => |ta| switch (b) {
                .tensor => |tb| blk: {
                    if (ta.dims.len != tb.dims.len or !ta.dtype.*.eql(tb.dtype.*)) break :blk false;
                    for (ta.dims, tb.dims) |da, db| {
                        if (!da.eql(db)) break :blk false;
                    }
                    break :blk true;
                },
                else => false,
            },
            .array => |aa| switch (b) {
                .array => |ab| aa.elem.eql(ab.elem.*) and aa.size == ab.size,
                else => false,
            },
            .func => |fa| switch (b) {
                .func => |fb| blk: {
                    if (fa.params.len != fb.params.len) break :blk false;
                    for (fa.params, fb.params) |pa, pb| {
                        if (!pa.eql(pb)) break :blk false;
                    }
                    break :blk fa.ret.eql(fb.ret.*);
                },
                else => false,
            },
        };
    }

    fn eqlOptStr(a: ?[]const u8, b_opt: ?[]const u8) bool {
        if (a == null and b_opt == null) return true;
        if (a == null or b_opt == null) return false;
        return std.mem.eql(u8, a.?, b_opt.?);
    }

    /// Deterministic content hash of a record's field set, used to mint a
    /// stable C struct name for anonymous record types. Two records with
    /// the same field set hash to the same value, which is how the codegen
    /// deduplicates `typedef struct { … }` declarations.
    fn record_content_hash(t: anytype) u64 {
        var h = std.hash.Wyhash.init(0xDADBEEF);
        h.update(std.mem.asBytes(&t.is_packed));
        if (t.align_n) |n| h.update(std.mem.asBytes(&n));
        for (t.fields) |f| {
            h.update(f.name);
            // Use the type's `eql` representation rather than the C name, so
            // the hash is stable across codegen changes.
            var name_buf: [64]u8 = undefined;
            h.update(f.typ.c_type(&name_buf));
        }
        return h.final();
    }

    /// Return the C type string for this type.
    /// Returns a user-friendly Duo type name for diagnostics and error messages.
    pub fn duo_name(self: ResolvedType, buf: []u8) []const u8 {
        return switch (self) {
            .i8 => "i8",
            .i16 => "i16",
            .i32 => "i32",
            .i64 => "i64",
            .u8 => "u8",
            .u16 => "u16",
            .u32 => "u32",
            .u64 => "u64",
            .f32 => "f32",
            .f64 => "f64",
            .v4f64 => "v4f64",
            .v4i64 => "v4i64",
            .v8f32 => "v8f32",
            .v8i32 => "v8i32",
            .bool => "bool",
            .void => "void",
            .str => "str",
            .any => "any",
            .nil => "nil",
            .never => "never",
            .pointer => |p| {
                const inner = p.duo_name(buf);
                return std.fmt.bufPrint(buf, "*{s}", .{inner}) catch inner;
            },
            .@"struct" => |s| s.name,
            .array => |a| {
                const inner = a.elem.duo_name(buf);
                if (a.size) |n| {
                    return std.fmt.bufPrint(buf, "[{d}]{s}", .{ n, inner }) catch inner;
                }
                return std.fmt.bufPrint(buf, "[]{s}", .{inner}) catch inner;
            },
            .func => "function",
            .result => "Result",
            .option => |inner| {
                const elem = inner.duo_name(buf);
                return std.fmt.bufPrint(buf, "?{s}", .{elem}) catch "?";
            },
            .enum_type => |e| e.name,
            .channel => "Channel",
            .generic_param => |gp| gp.name,
            .table_type => |t| {
                if (t.fields.len == 0) return "{}";
                return std.fmt.bufPrint(buf, "{{...{d} fields}}", .{t.fields.len}) catch "table";
            },
            .instantiated => "generic",
            .tensor => {
                return "Tensor";
            },
        };
    }

    pub fn c_type(self: ResolvedType, buf: []u8) []const u8 {
        return switch (self) {
            .i8 => "int8_t",
            .i16 => "int16_t",
            .i32 => "int32_t",
            .i64 => "int64_t",
            .u8 => "uint8_t",
            .u16 => "uint16_t",
            .u32 => "uint32_t",
            .u64 => "uint64_t",
            .f32 => "float",
            .f64 => "double",
            .v4f64 => "v4f64",
            .v4i64 => "v4i64",
            .v8f32 => "v8f32",
            .v8i32 => "v8i32",
            .bool => "bool",
            .void => "void",
            .str => "const char*",
            .any => "lua_Value",
            .nil => "void*",
            .never => "void",
            .pointer => |p| {
                var inner_buf: [128]u8 = undefined;
                const inner = p.c_type(&inner_buf);
                return std.fmt.bufPrint(buf, "{s}*", .{inner}) catch inner;
            },
            .@"struct" => |s| {
                return std.fmt.bufPrint(buf, "duo_{s}", .{s.name}) catch s.name;
            },
            .array => |a| {
                var inner_buf: [128]u8 = undefined;
                const inner = a.elem.c_type(&inner_buf);
                if (a.size) |n| {
                    return std.fmt.bufPrint(buf, "{s}[{}]", .{ inner, n }) catch inner;
                }
                return std.fmt.bufPrint(buf, "{s}*", .{inner}) catch inner;
            },
            .func => "/* func */",
            .result => |res| {
                const ok_str = res.ok.c_type(buf);
                _ = ok_str;
                return "duo_Result";
            },
            .option => "lua_Value",
            .enum_type => |e| {
                if (e.ffi_name) |cname| {
                    return std.fmt.bufPrint(buf, "{s}", .{cname}) catch cname;
                }
                return std.fmt.bufPrint(buf, "duo_{s}", .{e.name}) catch e.name;
            },
            .channel => "duo_Channel",
            .generic_param => "/* generic */",
            .table_type => |t| {
                if (t.ffi_name) |cname| {
                    return std.fmt.bufPrint(buf, "{s}", .{cname}) catch cname;
                }
                // Anonymous record type: mint a content-hashed C struct name.
                // The codegen dedupes by content hash to share one struct decl
                // across identical record shapes.
                const hash = record_content_hash(t);
                return std.fmt.bufPrint(buf, "duo_rec_{x}", .{hash}) catch "duo_rec";
            },
            .instantiated => |inst| {
                return std.fmt.bufPrint(buf, "duo_spec_{}", .{inst.specialization_key}) catch "duo_spec";
            },
            .tensor => "lua_Value",
        };
    }

    pub fn format(self: ResolvedType, comptime _: []const u8, _: std.fmt.FormatOptions, w: anytype) !void {
        switch (self) {
            .i8 => try w.writeAll("i8"),
            .i16 => try w.writeAll("i16"),
            .i32 => try w.writeAll("i32"),
            .i64 => try w.writeAll("i64"),
            .u8 => try w.writeAll("u8"),
            .u16 => try w.writeAll("u16"),
            .u32 => try w.writeAll("u32"),
            .u64 => try w.writeAll("u64"),
            .f32 => try w.writeAll("f32"),
            .f64 => try w.writeAll("f64"),
            .v4f64 => try w.writeAll("v4f64"),
            .v4i64 => try w.writeAll("v4i64"),
            .v8f32 => try w.writeAll("v8f32"),
            .v8i32 => try w.writeAll("v8i32"),
            .bool => try w.writeAll("bool"),
            .void => try w.writeAll("void"),
            .str => try w.writeAll("str"),
            .any => try w.writeAll("any"),
            .nil => try w.writeAll("nil"),
            .never => try w.writeAll("never"),
            .pointer => |p| {
                try w.writeByte('*');
                try w.print("{}", .{p.*});
            },
            .@"struct" => |s| try w.print("struct({s})", .{s.name}),
            .array => |a| {
                try w.writeByte('[');
                if (a.size) |n| try w.print("{}", .{n});
                try w.writeByte(']');
                try w.print("{}", .{a.elem.*});
            },
            .func => |f| {
                try w.writeAll("fn(");
                for (f.params, 0..) |p, i| {
                    if (i > 0) try w.writeAll(", ");
                    try w.print("{}", .{p});
                }
                try w.writeAll(") -> ");
                try w.print("{}", .{f.ret.*});
            },
            .result => |res| {
                try w.writeAll("Result[");
                try w.print("{}", .{res.ok.*});
                try w.writeAll(", ");
                try w.print("{}", .{res.err.*});
                try w.writeByte(']');
            },
            .option => |inner| {
                try w.writeAll("Option[");
                try w.print("{}", .{inner.*});
                try w.writeByte(']');
            },
            .enum_type => |e| try w.print("enum({s})", .{e.name}),
            .channel => |ch| {
                try w.writeAll("Channel[");
                try w.print("{}", .{ch.elem.*});
                if (ch.capacity) |cap| {
                    try w.print(", {}", .{cap});
                }
                try w.writeByte(']');
            },
            .generic_param => |gp| {
                try w.print("{s}", .{gp.name});
                if (gp.constraint) |c| {
                    try w.print(": {s}", .{c});
                }
            },
            .table_type => |t| {
                try w.writeAll("{");
                for (t.fields, 0..) |fld, i| {
                    if (i > 0) try w.writeAll(", ");
                    try w.print("{s}: {}", .{ fld.name, fld.typ });
                }
                try w.writeByte('}');
            },
            .instantiated => |inst| {
                try w.print("{}", .{inst.base.*});
                try w.writeByte('[');
                for (inst.args, 0..) |arg, i| {
                    if (i > 0) try w.writeAll(", ");
                    try w.print("{}", .{arg});
                }
                try w.writeByte(']');
            },
            .tensor => |t| {
                try w.writeAll("Tensor[");
                for (t.dims, 0..) |d, i| {
                    if (i > 0) try w.writeAll(", ");
                    try w.print("{}", .{d});
                }
                try w.writeAll(", ");
                try w.print("{}", .{t.dtype.*});
                try w.writeByte(']');
            },
        }
    }
};

pub const c_type_marker_prefix = "__c_type:";

// ── Tests ─────────────────────────────────────────────────────────────────────

const testing = @import("std").testing;

fn rt(tag: anytype) ResolvedType {
    return @as(ResolvedType, tag);
}

// local alias for non-shadowing use
const r = rt;

test "ResolvedType.eql: same primitives" {
    try testing.expect(r(.i8).eql(.i8));
    try testing.expect(r(.i16).eql(.i16));
    try testing.expect(r(.i32).eql(.i32));
    try testing.expect(r(.i64).eql(.i64));
    try testing.expect(r(.u8).eql(.u8));
    try testing.expect(r(.u16).eql(.u16));
    try testing.expect(r(.u32).eql(.u32));
    try testing.expect(r(.u64).eql(.u64));
    try testing.expect(r(.f32).eql(.f32));
    try testing.expect(r(.f64).eql(.f64));
    try testing.expect(r(.bool).eql(.bool));
    try testing.expect(r(.void).eql(.void));
    try testing.expect(r(.str).eql(.str));
    try testing.expect(r(.any).eql(.any));
    try testing.expect(r(.nil).eql(.nil));
}

test "ResolvedType.eql: different primitives" {
    try testing.expect(!r(.i32).eql(.i64));
    try testing.expect(!r(.f32).eql(.f64));
    try testing.expect(!r(.bool).eql(.i32));
    try testing.expect(!r(.str).eql(.any));
}

test "ResolvedType.is_integer" {
    try testing.expect(r(.i8).is_integer());
    try testing.expect(r(.i16).is_integer());
    try testing.expect(r(.i32).is_integer());
    try testing.expect(r(.i64).is_integer());
    try testing.expect(r(.u8).is_integer());
    try testing.expect(r(.u16).is_integer());
    try testing.expect(r(.u32).is_integer());
    try testing.expect(r(.u64).is_integer());
    try testing.expect(!r(.f32).is_integer());
    try testing.expect(!r(.f64).is_integer());
    try testing.expect(!r(.bool).is_integer());
    try testing.expect(!r(.str).is_integer());
    try testing.expect(!r(.any).is_integer());
}

test "ResolvedType.is_float" {
    try testing.expect(r(.f32).is_float());
    try testing.expect(r(.f64).is_float());
    try testing.expect(r(.v4f64).is_float());
    try testing.expect(r(.v8f32).is_float());
    try testing.expect(!r(.i32).is_float());
    try testing.expect(!r(.bool).is_float());
}

test "ResolvedType.is_numeric" {
    try testing.expect(r(.i32).is_numeric());
    try testing.expect(r(.f64).is_numeric());
    try testing.expect(!r(.str).is_numeric());
    try testing.expect(!r(.bool).is_numeric());
    try testing.expect(!r(.any).is_numeric());
}

test "ResolvedType.is_vector" {
    try testing.expect(r(.v4f64).is_vector());
    try testing.expect(r(.v4i64).is_vector());
    try testing.expect(r(.v8f32).is_vector());
    try testing.expect(r(.v8i32).is_vector());
    try testing.expect(!r(.f64).is_vector());
    try testing.expect(!r(.i32).is_vector());
}

test "ResolvedType.vector_mask" {
    try testing.expectEqual(r(.v4i64), r(.v4f64).vector_mask().?);
    try testing.expectEqual(r(.v4i64), r(.v4i64).vector_mask().?);
    try testing.expectEqual(r(.v8i32), r(.v8f32).vector_mask().?);
    try testing.expectEqual(r(.v8i32), r(.v8i32).vector_mask().?);
    try testing.expect(r(.f64).vector_mask() == null);
    try testing.expect(r(.i32).vector_mask() == null);
    try testing.expect(r(.bool).vector_mask() == null);
    try testing.expect(r(.str).vector_mask() == null);
    try testing.expect(r(.any).vector_mask() == null);
}

test "ResolvedType.is_native" {
    try testing.expect(r(.i32).is_native());
    try testing.expect(r(.f64).is_native());
    try testing.expect(r(.bool).is_native());
    try testing.expect(r(.str).is_native());
    try testing.expect(!r(.any).is_native());
    try testing.expect(!r(.nil).is_native());
    try testing.expect(!r(.never).is_native());
}

test "ResolvedType.c_type primitive names" {
    var buf: [64]u8 = undefined;
    try testing.expectEqualStrings("int8_t", r(.i8).c_type(&buf));
    try testing.expectEqualStrings("int16_t", r(.i16).c_type(&buf));
    try testing.expectEqualStrings("int32_t", r(.i32).c_type(&buf));
    try testing.expectEqualStrings("int64_t", r(.i64).c_type(&buf));
    try testing.expectEqualStrings("uint8_t", r(.u8).c_type(&buf));
    try testing.expectEqualStrings("uint16_t", r(.u16).c_type(&buf));
    try testing.expectEqualStrings("uint32_t", r(.u32).c_type(&buf));
    try testing.expectEqualStrings("uint64_t", r(.u64).c_type(&buf));
    try testing.expectEqualStrings("float", r(.f32).c_type(&buf));
    try testing.expectEqualStrings("double", r(.f64).c_type(&buf));
    try testing.expectEqualStrings("bool", r(.bool).c_type(&buf));
    try testing.expectEqualStrings("void", r(.void).c_type(&buf));
    try testing.expectEqualStrings("const char*", r(.str).c_type(&buf));
    try testing.expectEqualStrings("lua_Value", r(.any).c_type(&buf));
}

test "ResolvedType.c_type pointer to external C type" {
    var buf: [64]u8 = undefined;
    var file = ResolvedType{ .table_type = .{ .fields = &.{}, .ffi_name = "FILE" } };
    const ptr = ResolvedType{ .pointer = &file };
    try testing.expectEqualStrings("FILE*", ptr.c_type(&buf));
}

test "resolve: primitive named types" {
    const alloc = testing.allocator;
    const ATE = @import("ast.zig").TypeExpr;

    try testing.expectEqual(r(.i8), try resolve(.{ .named = "i8" }, null, alloc));
    try testing.expectEqual(r(.i16), try resolve(.{ .named = "i16" }, null, alloc));
    try testing.expectEqual(r(.i32), try resolve(.{ .named = "i32" }, null, alloc));
    try testing.expectEqual(r(.i64), try resolve(.{ .named = "i64" }, null, alloc));
    try testing.expectEqual(r(.u8), try resolve(.{ .named = "u8" }, null, alloc));
    try testing.expectEqual(r(.u16), try resolve(.{ .named = "u16" }, null, alloc));
    try testing.expectEqual(r(.u32), try resolve(.{ .named = "u32" }, null, alloc));
    try testing.expectEqual(r(.u64), try resolve(.{ .named = "u64" }, null, alloc));
    try testing.expectEqual(r(.f32), try resolve(.{ .named = "f32" }, null, alloc));
    try testing.expectEqual(r(.f64), try resolve(.{ .named = "f64" }, null, alloc));
    try testing.expectEqual(r(.bool), try resolve(.{ .named = "bool" }, null, alloc));
    try testing.expectEqual(r(.void), try resolve(.{ .named = "void" }, null, alloc));
    try testing.expectEqual(r(.str), try resolve(.{ .named = "str" }, null, alloc));
    try testing.expectEqual(r(.any), try resolve(.{ .named = "any" }, null, alloc));
    try testing.expectEqual(r(.any), try resolve(.{ .named = "Table" }, null, alloc));
    try testing.expectEqual(r(.any), try resolve(.{ .named = "table" }, null, alloc));
    _ = ATE;
}

test "resolve: inferred becomes any" {
    const alloc = testing.allocator;
    try testing.expectEqual(r(.any), try resolve(.inferred, null, alloc));
}

test "resolve: numeric family aliases" {
    const alloc = testing.allocator;
    try testing.expectEqual(r(.i64), try resolve(.{ .named = "int" }, null, alloc));
    try testing.expectEqual(r(.u64), try resolve(.{ .named = "uint" }, null, alloc));
    try testing.expectEqual(r(.f64), try resolve(.{ .named = "float" }, null, alloc));
    try testing.expectEqual(r(.f64), try resolve(.{ .named = "num" }, null, alloc));
    try testing.expectEqual(r(.f64), try resolve(.{ .named = "f128" }, null, alloc));
}

test "resolve: user struct" {
    const alloc = testing.allocator;
    const result = try resolve(.{ .named = "MyStruct" }, null, alloc);
    try testing.expect(result == .@"struct");
    try testing.expectEqualStrings("MyStruct", result.@"struct".name);
}

test "resolve: pointer type" {
    const alloc = testing.allocator;
    var inner = @import("ast.zig").TypeExpr{ .named = "i32" };
    const result = try resolve(.{ .pointer = &inner }, null, alloc);
    defer alloc.destroy(result.pointer);
    try testing.expect(result == .pointer);
    try testing.expectEqual(r(.i32), result.pointer.*);
}

test "resolve: List generic aliases dynamic array type" {
    const alloc = testing.allocator;
    var base = @import("ast.zig").TypeExpr{ .named = "List" };
    const elem = @import("ast.zig").TypeExpr{ .named = "i64" };
    const params = [_]@import("ast.zig").TypeExpr{elem};
    const result = try resolve(.{ .generic = .{ .base = &base, .params = @constCast(&params) } }, null, alloc);
    defer alloc.destroy(result.array.elem);
    try testing.expect(result == .array);
    try testing.expect(result.array.size == null);
    try testing.expectEqual(r(.i64), result.array.elem.*);
}

test "resolve: list generic aliases dynamic array type" {
    const alloc = testing.allocator;
    var base = @import("ast.zig").TypeExpr{ .named = "list" };
    const elem = @import("ast.zig").TypeExpr{ .named = "str" };
    const params = [_]@import("ast.zig").TypeExpr{elem};
    const result = try resolve(.{ .generic = .{ .base = &base, .params = @constCast(&params) } }, null, alloc);
    defer alloc.destroy(result.array.elem);
    try testing.expect(result == .array);
    try testing.expectEqual(r(.str), result.array.elem.*);
}

/// Map a native resolved type back to an annotation name (for inferred signatures).
pub fn rt_to_type_name(t: ResolvedType) ?[]const u8 {
    return switch (t) {
        .i8 => "i8",
        .i16 => "i16",
        .i32 => "i32",
        .i64 => "i64",
        .u8 => "u8",
        .u16 => "u16",
        .u32 => "u32",
        .u64 => "u64",
        .f32 => "f32",
        .f64 => "f64",
        .bool => "bool",
        .void => "void",
        .str => "str",
        else => null,
    };
}

/// Convert a `ast.TypeExpr` (parsed annotation) to a `ResolvedType`.
pub fn resolve(te: ast.TypeExpr, sema: ?*anyopaque, alloc: std.mem.Allocator) !ResolvedType {
    return switch (te) {
        .inferred => .any,
        .named => |n| {
            if (std.mem.startsWith(u8, n, c_type_marker_prefix)) {
                return ResolvedType{ .table_type = .{
                    .fields = &.{},
                    .ffi_name = n[c_type_marker_prefix.len..],
                } };
            }
            // Single uppercase letters are type parameters (e.g. Tensor[M, K, f32]).
            if (n.len == 1) {
                const c = n[0];
                if (c >= 'A' and c <= 'Z') {
                    return ResolvedType{ .generic_param = .{ .name = n, .constraint = null } };
                }
                if (c >= 'a' and c <= 'z') {
                    return .any;
                }
            }
            if (std.mem.eql(u8, n, "i8")) return .i8;
            if (std.mem.eql(u8, n, "i16")) return .i16;
            if (std.mem.eql(u8, n, "i32")) return .i32;
            if (std.mem.eql(u8, n, "i64")) return .i64;
            if (std.mem.eql(u8, n, "u8")) return .u8;
            if (std.mem.eql(u8, n, "u16")) return .u16;
            if (std.mem.eql(u8, n, "u32")) return .u32;
            if (std.mem.eql(u8, n, "u64")) return .u64;
            if (std.mem.eql(u8, n, "f32")) return .f32;
            if (std.mem.eql(u8, n, "f64")) return .f64;
            if (std.mem.eql(u8, n, "v4f64")) return .v4f64;
            if (std.mem.eql(u8, n, "v4i64")) return .v4i64;
            if (std.mem.eql(u8, n, "v8f32")) return .v8f32;
            if (std.mem.eql(u8, n, "v8i32")) return .v8i32;
            if (std.mem.eql(u8, n, "bool")) return .bool;
            if (std.mem.eql(u8, n, "void")) return .void;
            if (std.mem.eql(u8, n, "str")) return .str;
            if (std.mem.eql(u8, n, "any")) return .any;
            // Common aliases
            if (std.mem.eql(u8, n, "int") or std.mem.eql(u8, n, "integer")) return .i64;
            if (std.mem.eql(u8, n, "uint")) return .u64;
            if (std.mem.eql(u8, n, "float") or std.mem.eql(u8, n, "number") or
                std.mem.eql(u8, n, "num") or std.mem.eql(u8, n, "f128"))
                return .f64;
            if (std.mem.eql(u8, n, "string")) return .str;
            if (std.mem.eql(u8, n, "Table") or std.mem.eql(u8, n, "table")) return .any;
            // Self type: resolves to the enclosing type scope (enum, alias, concept)
            if (std.mem.eql(u8, n, "Self")) {
                if (sema) |s| {
                    const sema_mod = @import("sema.zig");
                    const self_ptr: *const sema_mod.Sema = @ptrCast(@alignCast(s));
                    if (self_ptr.current_type_name) |type_name| {
                        return ResolvedType{ .@"struct" = .{ .name = type_name } };
                    }
                }
                return ResolvedType{ .@"struct" = .{ .name = n } };
            }
            if (sema) |s| {
                const sema_mod = @import("sema.zig");
                const sema_ptr: *const sema_mod.Sema = @ptrCast(@alignCast(s));
                if (sema_ptr.enum_types.get(n)) |enum_t| return enum_t;
            }
            return ResolvedType{ .@"struct" = .{ .name = n } };
        },
        .pointer => |inner| {
            const p = try alloc.create(ResolvedType);
            p.* = try resolve(inner.*, sema, alloc);
            return ResolvedType{ .pointer = p };
        },
        .optional => |inner| {
            const elem = try alloc.create(ResolvedType);
            elem.* = try resolve(inner.*, sema, alloc);
            return ResolvedType{ .option = elem };
        },
        .array => |a| {
            const elem = try alloc.create(ResolvedType);
            elem.* = try resolve(a.elem.*, sema, alloc);
            return ResolvedType{ .array = .{ .elem = elem, .size = a.size } };
        },
        .func => |f| {
            var params = try alloc.alloc(ResolvedType, f.params.len);
            for (f.params, 0..) |p, i| params[i] = try resolve(p, sema, alloc);
            const ret = try alloc.create(ResolvedType);
            ret.* = try resolve(f.ret.*, sema, alloc);
            return ResolvedType{ .func = .{ .params = params, .ret = ret, .is_native = true } };
        },
        .generic => |g| {
            const base = try alloc.create(ResolvedType);
            base.* = try resolve(g.base.*, sema, alloc);
            var args = try alloc.alloc(ResolvedType, g.params.len);
            for (g.params, 0..) |p, i| {
                args[i] = try resolve(p, sema, alloc);
            }
            if (base.* == .@"struct" and
                (std.mem.eql(u8, base.@"struct".name, "List") or
                    std.mem.eql(u8, base.@"struct".name, "list")))
            {
                if (args.len != 1) {
                    alloc.destroy(base);
                    alloc.free(args);
                    return .any;
                }
                const elem = try alloc.create(ResolvedType);
                elem.* = args[0];
                alloc.destroy(base);
                alloc.free(args);
                return ResolvedType{ .array = .{ .elem = elem, .size = null } };
            }
            if (base.* == .@"struct" and std.mem.eql(u8, base.@"struct".name, "Result")) {
                if (args.len != 2) {
                    alloc.destroy(base);
                    alloc.free(args);
                    return .any;
                }
                const ok_ptr = try alloc.create(ResolvedType);
                ok_ptr.* = args[0];
                const err_ptr = try alloc.create(ResolvedType);
                err_ptr.* = args[1];
                alloc.destroy(base);
                alloc.free(args);
                return ResolvedType{ .result = .{ .ok = ok_ptr, .err = err_ptr } };
            }
            if (base.* == .@"struct" and std.mem.eql(u8, base.@"struct".name, "Option")) {
                if (args.len != 1) {
                    alloc.destroy(base);
                    alloc.free(args);
                    return .any;
                }
                const opt_ptr = try alloc.create(ResolvedType);
                opt_ptr.* = args[0];
                alloc.destroy(base);
                alloc.free(args);
                return ResolvedType{ .option = opt_ptr };
            }
            if (base.* == .@"struct" and std.mem.eql(u8, base.@"struct".name, "Tensor")) {
                if (args.len < 2) {
                    alloc.destroy(base);
                    alloc.free(args);
                    return .any;
                }
                const dtype: ResolvedType = if (args.len >= 3 and (args[args.len - 1] == .f32 or args[args.len - 1] == .f64))
                    args[args.len - 1]
                else
                    .f64;
                const dim_len = if (args.len >= 3 and (args[args.len - 1] == .f32 or args[args.len - 1] == .f64))
                    args.len - 1
                else
                    args.len;
                const dims = try alloc.alloc(ResolvedType, dim_len);
                @memcpy(dims, args[0..dim_len]);
                alloc.destroy(base);
                alloc.free(args);
                const dtype_ptr = try alloc.create(ResolvedType);
                dtype_ptr.* = dtype;
                return ResolvedType{ .tensor = .{ .dims = dims, .dtype = dtype_ptr } };
            }
            var key: u64 = std.hash.Wyhash.hash(0, "generic");
            if (base.* == .enum_type) key = std.hash.Wyhash.hash(0, base.enum_type.name);
            if (base.* == .@"struct") key = std.hash.Wyhash.hash(0, base.@"struct".name);
            for (args) |a| {
                var buf: [128]u8 = undefined;
                const s = std.fmt.bufPrint(&buf, "{}", .{a}) catch "";
                key = key ^ std.hash.Wyhash.hash(key, s);
            }
            return ResolvedType{ .instantiated = .{ .base = base, .args = args, .specialization_key = key } };
        },
        .record => |rec| {
            // Translate a record-type literal `{ name: T, ... }` to a
            // `table_type` ResolvedType, resolving each field's type.
            var fields = try alloc.alloc(FieldType, rec.fields.len);
            for (rec.fields, 0..) |f, i| {
                fields[i] = .{
                    .name = f.name,
                    .typ = try resolve(f.typ, sema, alloc),
                };
            }
            return ResolvedType{ .table_type = .{ .fields = fields } };
        },
        .tuple => {
            // Tuple types represent multi-return values. At the runtime level
            // Duo uses Lua-style multi-return (caller assigns to multiple locals),
            // so the resolved type is just `any` — type checking for individual
            // elements happens at sema time if needed.
            return .any;
        },
    };
}

test "resolve: Tensor[M,N,f32]" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const base = try alloc.create(ast.TypeExpr);
    base.* = .{ .named = "Tensor" };
    const params = try alloc.alloc(ast.TypeExpr, 3);
    params[0] = .{ .named = "784" };
    params[1] = .{ .named = "256" };
    params[2] = .{ .named = "f32" };
    const te: ast.TypeExpr = .{ .generic = .{ .base = base, .params = params } };
    const resolved_type = try resolve(te, null, alloc);
    try testing.expect(resolved_type == .tensor);
    try testing.expectEqual(@as(usize, 2), resolved_type.tensor.dims.len);
    try testing.expect(resolved_type.tensor.dtype.* == .f32);
}

test "tensor_matmul: compatible 2-D tensors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const f32p = try alloc.create(ResolvedType);
    f32p.* = .f32;
    const a_dims = try alloc.alloc(ResolvedType, 2);
    a_dims[0] = .{ .@"struct" = .{ .name = "784" } };
    a_dims[1] = .{ .@"struct" = .{ .name = "256" } };
    const b_dims = try alloc.alloc(ResolvedType, 2);
    b_dims[0] = .{ .@"struct" = .{ .name = "256" } };
    b_dims[1] = .{ .@"struct" = .{ .name = "10" } };
    const a = ResolvedType{ .tensor = .{ .dims = a_dims, .dtype = f32p } };
    const b = ResolvedType{ .tensor = .{ .dims = b_dims, .dtype = f32p } };
    const out = (try ResolvedType.tensor_matmul(a, b, alloc)) orelse return error.TestExpectedSuccess;
    try testing.expect(out == .tensor);
    try testing.expectEqual(@as(usize, 2), out.tensor.dims.len);
    try testing.expectEqualStrings("784", out.tensor.dims[0].@"struct".name);
    try testing.expectEqualStrings("10", out.tensor.dims[1].@"struct".name);
}

test "tensor_matmul: K mismatch returns null" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const f32p = try alloc.create(ResolvedType);
    f32p.* = .f32;
    const a_dims = try alloc.alloc(ResolvedType, 2);
    a_dims[0] = .{ .@"struct" = .{ .name = "784" } };
    a_dims[1] = .{ .@"struct" = .{ .name = "256" } };
    const b_dims = try alloc.alloc(ResolvedType, 2);
    b_dims[0] = .{ .@"struct" = .{ .name = "128" } };
    b_dims[1] = .{ .@"struct" = .{ .name = "10" } };
    const a = ResolvedType{ .tensor = .{ .dims = a_dims, .dtype = f32p } };
    const b = ResolvedType{ .tensor = .{ .dims = b_dims, .dtype = f32p } };
    try testing.expect(try ResolvedType.tensor_matmul(a, b, alloc) == null);
    try testing.expect(ResolvedType.tensor_matmul_k_incompatible(a, b));
}

test "tensor_matmul: symbolic K mismatch" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const f32p = try alloc.create(ResolvedType);
    f32p.* = .f32;
    const k = try alloc.dupe(u8, "K");
    const j = try alloc.dupe(u8, "J");
    const m = try alloc.dupe(u8, "M");
    const n = try alloc.dupe(u8, "N");
    const a_dims = try alloc.alloc(ResolvedType, 2);
    a_dims[0] = .{ .generic_param = .{ .name = m, .constraint = null } };
    a_dims[1] = .{ .generic_param = .{ .name = k, .constraint = null } };
    const b_dims = try alloc.alloc(ResolvedType, 2);
    b_dims[0] = .{ .generic_param = .{ .name = j, .constraint = null } };
    b_dims[1] = .{ .generic_param = .{ .name = n, .constraint = null } };
    const a = ResolvedType{ .tensor = .{ .dims = a_dims, .dtype = f32p } };
    const b = ResolvedType{ .tensor = .{ .dims = b_dims, .dtype = f32p } };
    try testing.expect(ResolvedType.tensor_matmul_k_incompatible(a, b));
    try testing.expect((try ResolvedType.tensor_matmul(a, b, alloc)) == null);
}

test "tensor_matmul: symbolic K match infers output" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const f32p = try alloc.create(ResolvedType);
    f32p.* = .f32;
    const k = try alloc.dupe(u8, "K");
    const m = try alloc.dupe(u8, "M");
    const n = try alloc.dupe(u8, "N");
    const a_dims = try alloc.alloc(ResolvedType, 2);
    a_dims[0] = .{ .generic_param = .{ .name = m, .constraint = null } };
    a_dims[1] = .{ .generic_param = .{ .name = k, .constraint = null } };
    const b_dims = try alloc.alloc(ResolvedType, 2);
    b_dims[0] = .{ .generic_param = .{ .name = k, .constraint = null } };
    b_dims[1] = .{ .generic_param = .{ .name = n, .constraint = null } };
    const a = ResolvedType{ .tensor = .{ .dims = a_dims, .dtype = f32p } };
    const b = ResolvedType{ .tensor = .{ .dims = b_dims, .dtype = f32p } };
    try testing.expect(!ResolvedType.tensor_matmul_k_incompatible(a, b));
    const out = (try ResolvedType.tensor_matmul(a, b, alloc)) orelse return error.TestExpectedSuccess;
    try testing.expect(out.tensor.dims[0].eql(a_dims[0]));
    try testing.expect(out.tensor.dims[1].eql(b_dims[1]));
}

test "tensor_broadcast: 1 x N with M x N" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const f32p = try alloc.create(ResolvedType);
    f32p.* = .f32;
    const a_dims = try alloc.alloc(ResolvedType, 2);
    a_dims[0] = .{ .@"struct" = .{ .name = "1" } };
    a_dims[1] = .{ .@"struct" = .{ .name = "10" } };
    const b_dims = try alloc.alloc(ResolvedType, 2);
    b_dims[0] = .{ .@"struct" = .{ .name = "784" } };
    b_dims[1] = .{ .@"struct" = .{ .name = "10" } };
    const a = ResolvedType{ .tensor = .{ .dims = a_dims, .dtype = f32p } };
    const b = ResolvedType{ .tensor = .{ .dims = b_dims, .dtype = f32p } };
    const out = (try ResolvedType.tensor_broadcast(a, b, alloc)) orelse return error.TestExpectedSuccess;
    try testing.expectEqualStrings("784", out.tensor.dims[0].@"struct".name);
    try testing.expectEqualStrings("10", out.tensor.dims[1].@"struct".name);
}

test "tensor_broadcast: incompatible 2 x 3 + 3 x 4" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const f32p = try alloc.create(ResolvedType);
    f32p.* = .f32;
    const mk = struct {
        fn t(rows: []const u8, cols: []const u8, dtype: *ResolvedType, a: std.mem.Allocator) !ResolvedType {
            const dims = try a.alloc(ResolvedType, 2);
            dims[0] = .{ .@"struct" = .{ .name = rows } };
            dims[1] = .{ .@"struct" = .{ .name = cols } };
            return ResolvedType{ .tensor = .{ .dims = dims, .dtype = dtype } };
        }
    }.t;
    const a = try mk("2", "3", f32p, alloc);
    const b = try mk("3", "4", f32p, alloc);
    try testing.expect(ResolvedType.tensor_broadcast_shape_incompatible(a, b));
    try testing.expect((try ResolvedType.tensor_broadcast(a, b, alloc)) == null);
}
