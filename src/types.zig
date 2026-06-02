const std = @import("std");
const ast = @import("ast.zig");

/// Resolved type after semantic analysis.
/// During sema, each expression gets a `ResolvedType` attached.
pub const ResolvedType = union(enum) {
    // Primitive native types (map directly to C types)
    i8, i16, i32, i64,
    u8, u16, u32, u64,
    f32, f64,
    bool,
    void,

    // Managed / dynamic types
    str,       // immutable C string (const char*)
    any,       // dynamic Lua value — opaque at C level
    nil,
    never,     // function that never returns (e.g. error())

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

    pub fn is_integer(self: ResolvedType) bool {
        return switch (self) {
            .i8, .i16, .i32, .i64,
            .u8, .u16, .u32, .u64 => true,
            else => false,
        };
    }

    pub fn is_float(self: ResolvedType) bool {
        return switch (self) { .f32, .f64, .v4f64, .v8f32 => true, else => false };
    }

    pub fn is_vector(self: ResolvedType) bool {
        return switch (self) { .v4f64, .v4i64, .v8f32, .v8i32 => true, else => false };
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
            .func => |f| f.is_native,
            else => true,
        };
    }

    pub fn eql(a: ResolvedType, b: ResolvedType) bool {
        return switch (a) {
            .i8    => switch (b) { .i8    => true, else => false },
            .i16   => switch (b) { .i16   => true, else => false },
            .i32   => switch (b) { .i32   => true, else => false },
            .i64   => switch (b) { .i64   => true, else => false },
            .u8    => switch (b) { .u8    => true, else => false },
            .u16   => switch (b) { .u16   => true, else => false },
            .u32   => switch (b) { .u32   => true, else => false },
            .u64   => switch (b) { .u64   => true, else => false },
            .f32   => switch (b) { .f32   => true, else => false },
            .f64   => switch (b) { .f64   => true, else => false },
            .v4f64 => switch (b) { .v4f64 => true, else => false },
            .v4i64 => switch (b) { .v4i64 => true, else => false },
            .v8f32 => switch (b) { .v8f32 => true, else => false },
            .v8i32 => switch (b) { .v8i32 => true, else => false },
            .bool  => switch (b) { .bool  => true, else => false },
            .void  => switch (b) { .void  => true, else => false },
            .str   => switch (b) { .str   => true, else => false },
            .any   => switch (b) { .any   => true, else => false },
            .nil   => switch (b) { .nil   => true, else => false },
            .never => switch (b) { .never => true, else => false },
            .pointer => |pa| switch (b) {
                .pointer => |pb| pa.eql(pb.*),
                else => false,
            },
            .@"struct" => |sa| switch (b) {
                .@"struct" => |sb| std.mem.eql(u8, sa.name, sb.name),
                else => false,
            },
            else => false,
        };
    }

    /// Return the C type string for this type.
    pub fn c_type(self: ResolvedType, buf: []u8) []const u8 {
        return switch (self) {
            .i8    => "int8_t",
            .i16   => "int16_t",
            .i32   => "int32_t",
            .i64   => "int64_t",
            .u8    => "uint8_t",
            .u16   => "uint16_t",
            .u32   => "uint32_t",
            .u64   => "uint64_t",
            .f32   => "float",
            .f64   => "double",
            .v4f64 => "v4f64",
            .v4i64 => "v4i64",
            .v8f32 => "v8f32",
            .v8i32 => "v8i32",
            .bool  => "bool",
            .void  => "void",
            .str   => "const char*",
            .any   => "lua_Value",
            .nil   => "void*",
            .never => "void",
            .pointer => |p| {
                const inner = p.c_type(buf);
                return std.fmt.bufPrint(buf, "{s}*", .{inner}) catch inner;
            },
            .@"struct" => |s| {
                return std.fmt.bufPrint(buf, "duo_{s}", .{s.name}) catch s.name;
            },
            .array => |a| {
                const inner = a.elem.c_type(buf);
                if (a.size) |n| {
                    return std.fmt.bufPrint(buf, "{s}[{}]", .{ inner, n }) catch inner;
                }
                return std.fmt.bufPrint(buf, "{s}*", .{inner}) catch inner;
            },
            .func => "/* func */",
        };
    }

    pub fn format(self: ResolvedType, comptime _: []const u8, _: std.fmt.FormatOptions, w: anytype) !void {
        switch (self) {
            .i8  => try w.writeAll("i8"),
            .i16 => try w.writeAll("i16"),
            .i32 => try w.writeAll("i32"),
            .i64 => try w.writeAll("i64"),
            .u8  => try w.writeAll("u8"),
            .u16 => try w.writeAll("u16"),
            .u32 => try w.writeAll("u32"),
            .u64 => try w.writeAll("u64"),
            .f32 => try w.writeAll("f32"),
            .f64 => try w.writeAll("f64"),
            .v4f64 => try w.writeAll("v4f64"),
            .v4i64 => try w.writeAll("v4i64"),
            .v8f32 => try w.writeAll("v8f32"),
            .v8i32 => try w.writeAll("v8i32"),
            .bool  => try w.writeAll("bool"),
            .void  => try w.writeAll("void"),
            .str   => try w.writeAll("str"),
            .any   => try w.writeAll("any"),
            .nil   => try w.writeAll("nil"),
            .never => try w.writeAll("never"),
            .pointer => |p| { try w.writeByte('*'); try w.print("{}", .{p.*}); },
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
        }
    }
};

// ── Tests ─────────────────────────────────────────────────────────────────────

const testing = @import("std").testing;

test "ResolvedType.eql: same primitives" {
    try testing.expect(ResolvedType.i8.eql(.i8));
    try testing.expect(ResolvedType.i16.eql(.i16));
    try testing.expect(ResolvedType.i32.eql(.i32));
    try testing.expect(ResolvedType.i64.eql(.i64));
    try testing.expect(ResolvedType.u8.eql(.u8));
    try testing.expect(ResolvedType.u16.eql(.u16));
    try testing.expect(ResolvedType.u32.eql(.u32));
    try testing.expect(ResolvedType.u64.eql(.u64));
    try testing.expect(ResolvedType.f32.eql(.f32));
    try testing.expect(ResolvedType.f64.eql(.f64));
    try testing.expect(ResolvedType.bool.eql(.bool));
    try testing.expect(ResolvedType.void.eql(.void));
    try testing.expect(ResolvedType.str.eql(.str));
    try testing.expect(ResolvedType.any.eql(.any));
    try testing.expect(ResolvedType.nil.eql(.nil));
}

test "ResolvedType.eql: different primitives" {
    try testing.expect(!ResolvedType.i32.eql(.i64));
    try testing.expect(!ResolvedType.f32.eql(.f64));
    try testing.expect(!ResolvedType.bool.eql(.i32));
    try testing.expect(!ResolvedType.str.eql(.any));
}

test "ResolvedType.is_integer" {
    try testing.expect(ResolvedType.i8.is_integer());
    try testing.expect(ResolvedType.i16.is_integer());
    try testing.expect(ResolvedType.i32.is_integer());
    try testing.expect(ResolvedType.i64.is_integer());
    try testing.expect(ResolvedType.u8.is_integer());
    try testing.expect(ResolvedType.u16.is_integer());
    try testing.expect(ResolvedType.u32.is_integer());
    try testing.expect(ResolvedType.u64.is_integer());
    try testing.expect(!ResolvedType.f32.is_integer());
    try testing.expect(!ResolvedType.f64.is_integer());
    try testing.expect(!ResolvedType.bool.is_integer());
    try testing.expect(!ResolvedType.str.is_integer());
    try testing.expect(!ResolvedType.any.is_integer());
}

test "ResolvedType.is_float" {
    try testing.expect(ResolvedType.f32.is_float());
    try testing.expect(ResolvedType.f64.is_float());
    try testing.expect(ResolvedType.v4f64.is_float());
    try testing.expect(ResolvedType.v8f32.is_float());
    try testing.expect(!ResolvedType.i32.is_float());
    try testing.expect(!ResolvedType.bool.is_float());
}

test "ResolvedType.is_numeric" {
    try testing.expect(ResolvedType.i32.is_numeric());
    try testing.expect(ResolvedType.f64.is_numeric());
    try testing.expect(!ResolvedType.str.is_numeric());
    try testing.expect(!ResolvedType.bool.is_numeric());
    try testing.expect(!ResolvedType.any.is_numeric());
}

test "ResolvedType.is_vector" {
    try testing.expect(ResolvedType.v4f64.is_vector());
    try testing.expect(ResolvedType.v4i64.is_vector());
    try testing.expect(ResolvedType.v8f32.is_vector());
    try testing.expect(ResolvedType.v8i32.is_vector());
    try testing.expect(!ResolvedType.f64.is_vector());
    try testing.expect(!ResolvedType.i32.is_vector());
}

test "ResolvedType.vector_mask" {
    try testing.expectEqual(ResolvedType.v4i64, ResolvedType.v4f64.vector_mask().?);
    try testing.expectEqual(ResolvedType.v4i64, ResolvedType.v4i64.vector_mask().?);
    try testing.expectEqual(ResolvedType.v8i32, ResolvedType.v8f32.vector_mask().?);
    try testing.expectEqual(ResolvedType.v8i32, ResolvedType.v8i32.vector_mask().?);
    try testing.expect(ResolvedType.f64.vector_mask() == null);
    try testing.expect(ResolvedType.i32.vector_mask() == null);
}

test "ResolvedType.is_native" {
    try testing.expect(ResolvedType.i32.is_native());
    try testing.expect(ResolvedType.f64.is_native());
    try testing.expect(ResolvedType.bool.is_native());
    try testing.expect(ResolvedType.str.is_native());
    try testing.expect(!ResolvedType.any.is_native());
    try testing.expect(!ResolvedType.nil.is_native());
    try testing.expect(!ResolvedType.never.is_native());
}

test "ResolvedType.c_type primitive names" {
    var buf: [64]u8 = undefined;
    try testing.expectEqualStrings("int8_t",   ResolvedType.i8.c_type(&buf));
    try testing.expectEqualStrings("int16_t",  ResolvedType.i16.c_type(&buf));
    try testing.expectEqualStrings("int32_t",  ResolvedType.i32.c_type(&buf));
    try testing.expectEqualStrings("int64_t",  ResolvedType.i64.c_type(&buf));
    try testing.expectEqualStrings("uint8_t",  ResolvedType.u8.c_type(&buf));
    try testing.expectEqualStrings("uint16_t", ResolvedType.u16.c_type(&buf));
    try testing.expectEqualStrings("uint32_t", ResolvedType.u32.c_type(&buf));
    try testing.expectEqualStrings("uint64_t", ResolvedType.u64.c_type(&buf));
    try testing.expectEqualStrings("float",       ResolvedType.f32.c_type(&buf));
    try testing.expectEqualStrings("double",      ResolvedType.f64.c_type(&buf));
    try testing.expectEqualStrings("bool",        ResolvedType.bool.c_type(&buf));
    try testing.expectEqualStrings("void",        ResolvedType.void.c_type(&buf));
    try testing.expectEqualStrings("const char*", ResolvedType.str.c_type(&buf));
    try testing.expectEqualStrings("lua_Value",   ResolvedType.any.c_type(&buf));
}

test "resolve: primitive named types" {
    const alloc = testing.allocator;
    const ATE = @import("ast.zig").TypeExpr;

    try testing.expectEqual(ResolvedType.i8,   try resolve(.{ .named = "i8" },   alloc));
    try testing.expectEqual(ResolvedType.i16,  try resolve(.{ .named = "i16" },  alloc));
    try testing.expectEqual(ResolvedType.i32,  try resolve(.{ .named = "i32" },  alloc));
    try testing.expectEqual(ResolvedType.i64,  try resolve(.{ .named = "i64" },  alloc));
    try testing.expectEqual(ResolvedType.u8,   try resolve(.{ .named = "u8" },   alloc));
    try testing.expectEqual(ResolvedType.u16,  try resolve(.{ .named = "u16" },  alloc));
    try testing.expectEqual(ResolvedType.u32,  try resolve(.{ .named = "u32" },  alloc));
    try testing.expectEqual(ResolvedType.u64,  try resolve(.{ .named = "u64" },  alloc));
    try testing.expectEqual(ResolvedType.f32,  try resolve(.{ .named = "f32" },  alloc));
    try testing.expectEqual(ResolvedType.f64,  try resolve(.{ .named = "f64" },  alloc));
    try testing.expectEqual(ResolvedType.bool, try resolve(.{ .named = "bool" }, alloc));
    try testing.expectEqual(ResolvedType.void, try resolve(.{ .named = "void" }, alloc));
    try testing.expectEqual(ResolvedType.str,  try resolve(.{ .named = "str" },  alloc));
    try testing.expectEqual(ResolvedType.any,  try resolve(.{ .named = "any" },  alloc));
    _ = ATE;
}

test "resolve: inferred becomes any" {
    const alloc = testing.allocator;
    try testing.expectEqual(ResolvedType.any, try resolve(.inferred, alloc));
}

test "resolve: user struct" {
    const alloc = testing.allocator;
    const rt = try resolve(.{ .named = "MyStruct" }, alloc);
    try testing.expect(rt == .@"struct");
    try testing.expectEqualStrings("MyStruct", rt.@"struct".name);
}

test "resolve: pointer type" {
    const alloc = testing.allocator;
    var inner = @import("ast.zig").TypeExpr{ .named = "i32" };
    const rt = try resolve(.{ .pointer = &inner }, alloc);
    defer alloc.destroy(rt.pointer);
    try testing.expect(rt == .pointer);
    try testing.expectEqual(ResolvedType.i32, rt.pointer.*);
}

/// Map a native resolved type back to an annotation name (for inferred signatures).
pub fn rt_to_type_name(rt: ResolvedType) ?[]const u8 {
    return switch (rt) {
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
pub fn resolve(te: ast.TypeExpr, alloc: std.mem.Allocator) !ResolvedType {
    return switch (te) {
        .inferred => .any,
        .named => |n| {
            // Check for common single-letter type parameter names (heuristic)
            if (n.len == 1) {
                const c = n[0];
                if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                    // Likely a type parameter, resolve to any for now
                    return .any;
                }
            }
            if (std.mem.eql(u8, n, "i8"))   return .i8;
            if (std.mem.eql(u8, n, "i16"))  return .i16;
            if (std.mem.eql(u8, n, "i32"))  return .i32;
            if (std.mem.eql(u8, n, "i64"))  return .i64;
            if (std.mem.eql(u8, n, "u8"))   return .u8;
            if (std.mem.eql(u8, n, "u16"))  return .u16;
            if (std.mem.eql(u8, n, "u32"))  return .u32;
            if (std.mem.eql(u8, n, "u64"))  return .u64;
            if (std.mem.eql(u8, n, "f32"))  return .f32;
            if (std.mem.eql(u8, n, "f64"))  return .f64;
            if (std.mem.eql(u8, n, "v4f64")) return .v4f64;
            if (std.mem.eql(u8, n, "v4i64")) return .v4i64;
            if (std.mem.eql(u8, n, "v8f32")) return .v8f32;
            if (std.mem.eql(u8, n, "v8i32")) return .v8i32;
            if (std.mem.eql(u8, n, "bool")) return .bool;
            if (std.mem.eql(u8, n, "void")) return .void;
            if (std.mem.eql(u8, n, "str"))  return .str;
            if (std.mem.eql(u8, n, "any"))  return .any;
            return ResolvedType{ .@"struct" = .{ .name = n } };
        },
        .pointer => |inner| {
            const p = try alloc.create(ResolvedType);
            p.* = try resolve(inner.*, alloc);
            return ResolvedType{ .pointer = p };
        },
        .optional => |inner| {
            _ = inner;
            return .any; // simplification: optional → any for now
        },
        .array => |a| {
            const elem = try alloc.create(ResolvedType);
            elem.* = try resolve(a.elem.*, alloc);
            return ResolvedType{ .array = .{ .elem = elem, .size = a.size } };
        },
        .func => |f| {
            var params = try alloc.alloc(ResolvedType, f.params.len);
            for (f.params, 0..) |p, i| params[i] = try resolve(p, alloc);
            const ret = try alloc.create(ResolvedType);
            ret.* = try resolve(f.ret.*, alloc);
            return ResolvedType{ .func = .{ .params = params, .ret = ret, .is_native = true } };
        },
        .generic => |g| {
            // For now, just resolve to the base type as a simplification
            // Full monomorphization would require more complex handling
            return try resolve(g.base.*, alloc);
        },
    };
}
