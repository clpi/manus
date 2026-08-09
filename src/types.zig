const std = @import("std");
const ast = @import("ast.zig");
const directives = @import("directives.zig");

/// A single variant within an enum type.
pub const EnumVariantType = struct {
    name: []const u8,
    payload: ?[]const ResolvedType,
};

/// Table storage strategy for specialization ladder.
/// Controls codegen emission: lua table ops vs direct field access.
pub const StorageClass = enum {
    /// Dynamic table: hash-based field lookup, fully boxed
    dynamic,
    /// Guarded table: shape-guarded inline cache, may deoptimize
    guarded,
    /// Sealed table: known shape, direct offset access, boxed container
    sealed,
    /// Native table: C struct layout, unboxed, direct memory access
    native,
};

/// A field within a typed table/class.
pub const FieldType = struct {
    name: []const u8,
    typ: ResolvedType,
};

/// Human-readable storage class label for `@comp.type.shape` and diagnostics.
pub fn storageClassName(sc: StorageClass) []const u8 {
    return switch (sc) {
        .dynamic => "dynamic",
        .guarded => "guarded",
        .sealed => "sealed",
        .native => "native",
    };
}

/// True when every field type lowers to native C without Lua boxing.
pub fn fieldsAreNative(fields: []const FieldType) bool {
    if (fields.len == 0) return false;
    for (fields) |f| {
        if (!f.typ.is_native()) return false;
    }
    return true;
}

/// Infer table storage class from field types, seal status, and explicit overrides.
///
/// Specialization ladder: dynamic → guarded → sealed → native.
/// Typed records with all-native fields default to `.native` (direct struct access).
pub fn inferStorageClass(
    fields: []const FieldType,
    is_sealed: bool,
    explicit: StorageClass,
) StorageClass {
    if (explicit != .dynamic) return explicit;
    if (fieldsAreNative(fields)) return .native;
    if (is_sealed) return .sealed;
    return .dynamic;
}

/// Read the layout facts a legacy `@packed` / `@align(n)` / `@ffi("x")` /
/// `@sealed` / `@native` / `@guarded` attribute list was storing, starting
/// from `base` (the refinement-spelled facts already carried by the
/// descriptor). The adaptation runs OLD → NEW only: nothing ever converts a
/// refinement back into an `ast.Attribute`.
pub fn layoutFromAttrs(base: ast.TypeExpr.Layout, attributes: []const ast.Attribute) ast.TypeExpr.Layout {
    var layout = base;
    for (attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "packed")) {
            layout.is_packed = true;
        } else if (std.mem.eql(u8, attr.name, "align")) {
            if (attr.args) |args_str| {
                layout.align_given = true;
                // `parseInt` on the untrimmed source text read `@align( 8 )`
                // as garbage and CLEARED the alignment. `attrInt` trims first.
                layout.align_n = directives.attrInt(usize, args_str);
            }
        } else if (std.mem.eql(u8, attr.name, "ffi")) {
            // The foreign name is the FIRST positional. A hand-rolled
            // whole-string quote test kept the rest of the signature in it:
            // `@ffi("memcpy", void, {any})` yielded `"memcpy", void, {any}`.
            if (directives.attrText(attr.args)) |name| layout.ffi = name;
        } else if (std.mem.eql(u8, attr.name, "sealed")) {
            layout.sealed = true;
            layout.storage = .sealed;
        } else if (std.mem.eql(u8, attr.name, "native")) {
            layout.storage = .native;
        } else if (std.mem.eql(u8, attr.name, "guarded")) {
            layout.storage = .guarded;
        }
    }
    return layout;
}

test "layoutFromAttrs: the ffi fact is the foreign NAME, not the argument list" {
    // `@ffi("memcpy", void, {any, any, i64})` is the corpus shape. A whole-string
    // quote test failed on it and stored the entire argument list as the name.
    const attrs = [_]ast.Attribute{.{ .name = "ffi", .args = "\"memcpy\", void, {any, any, i64}" }};
    const layout = layoutFromAttrs(.{}, &attrs);
    try testing.expectEqualStrings("memcpy", layout.ffi.?);

    // Bare and single-argument spellings resolve to the same fact.
    const bare = [_]ast.Attribute{.{ .name = "ffi", .args = "\"llabs\"" }};
    try testing.expectEqualStrings("llabs", layoutFromAttrs(.{}, &bare).ffi.?);
}

test "layoutFromAttrs: align survives spacing and declines garbage" {
    try testing.expectEqual(@as(?usize, 16), layoutFromAttrs(.{}, &[_]ast.Attribute{
        .{ .name = "align", .args = " 16 " },
    }).align_n);
    // `align_given` stays true so the fact reads as "asked for, unreadable"
    // rather than "never asked" — the distinction `applyLayout` depends on.
    const bad = layoutFromAttrs(.{}, &[_]ast.Attribute{.{ .name = "align", .args = "sixteen" }});
    try testing.expect(bad.align_given);
    try testing.expectEqual(@as(?usize, null), bad.align_n);
}

/// The single place layout facts land on a resolved table type. Both spellings
/// (`& packed` refinement, `@packed` attribute) arrive here as one `Layout`.
pub fn applyLayout(t: *ResolvedType, layout: ast.TypeExpr.Layout) void {
    if (t.* != .table_type) return;
    if (layout.is_packed) t.table_type.is_packed = true;
    if (layout.align_given) t.table_type.align_n = layout.align_n;
    if (layout.ffi) |name| t.table_type.ffi_name = name;
    if (layout.sealed) t.table_type.is_sealed = true;
    const explicit: StorageClass = switch (layout.storage orelse {
        t.table_type.storage_class = inferStorageClass(
            t.table_type.fields,
            t.table_type.is_sealed,
            t.table_type.storage_class,
        );
        return;
    }) {
        .native => .native,
        .guarded => .guarded,
        .sealed => .sealed,
    };
    t.table_type.storage_class = inferStorageClass(
        t.table_type.fields,
        t.table_type.is_sealed,
        explicit,
    );
}

/// Apply layout/shape attributes (`@packed`, `@align`, `@ffi`, `@sealed`, `@native`).
pub fn applyTableShapeAttrs(t: *ResolvedType, attributes: []const ast.Attribute) void {
    if (t.* != .table_type) return;
    applyLayout(t, layoutFromAttrs(.{}, attributes));
}

/// Resolved storage class for introspection (table types and named aliases).
pub fn tableStorageClass(resolved_type: ResolvedType) ?StorageClass {
    return switch (resolved_type) {
        .table_type => |t| t.storage_class,
        else => null,
    };
}

/// Factual compiler explanation for table storage-class selection (for `@comp.why.shape`).
/// Only states reasons the type system actually recorded — no invented optimizations.
pub fn explainStorageClass(resolved_type: ResolvedType) []const u8 {
    const sc = tableStorageClass(resolved_type) orelse {
        return "not a typed table or record alias; dynamic Lua representation";
    };
    const t = resolved_type.table_type;
    return switch (sc) {
        .native => if (fieldsAreNative(t.fields))
            "all record fields lower to native C scalars; unboxed struct with direct field access"
        else
            "@native directive; unboxed C struct layout",
        .sealed => if (t.is_sealed)
            if (fieldsAreNative(t.fields))
                "@sealed directive; fixed native field layout in sealed container"
            else
                "@sealed directive; fixed shape; non-native fields retain Lua-compatible storage"
        else
            "sealed typed record; known field layout with boxed table container",
        .guarded => "runtime shape may change; guarded inline cache on field access",
        .dynamic => if (t.fields.len == 0)
            "open or empty table shape; hash-based field lookup"
        else if (fieldsAreNative(t.fields))
            "typed record without seal or native override; defaults to dynamic until specialized"
        else
            "record includes non-native field type(s); generic Lua table lookup",
    };
}

/// Stable content hash for table/record shapes (matches codegen `duo_rec_{x}` dedup).
pub fn tableShapeIdentityHash(resolved_type: ResolvedType) ?u64 {
    if (resolved_type != .table_type) return null;
    const t = resolved_type.table_type;
    var h = std.hash.Wyhash.init(0xDADBEEF);
    h.update(std.mem.asBytes(&t.is_packed));
    if (t.align_n) |n| h.update(std.mem.asBytes(&n));
    for (t.fields) |f| {
        h.update(f.name);
        var name_buf: [64]u8 = undefined;
        h.update(f.typ.c_type(&name_buf));
    }
    return h.final();
}

/// Stable content hash for enum descriptor shapes (variant names + enum name).
pub fn enumShapeIdentityHash(resolved_type: ResolvedType) ?u64 {
    if (resolved_type != .enum_type) return null;
    const e = resolved_type.enum_type;
    var h = std.hash.Wyhash.init(0xE0BEEF00);
    h.update(e.name);
    for (e.variants) |v| {
        h.update(v.name);
    }
    return h.final();
}

/// Resolve enum shape from AST for graph lift (no sema required).
pub fn enumShapeFromAst(ed: *const ast.EnumDef, alloc: std.mem.Allocator) !ResolvedType {
    var variants = try alloc.alloc(EnumVariantType, ed.variants.len);
    for (ed.variants, 0..) |v, i| {
        variants[i] = .{ .name = v.name, .payload = null };
    }
    return .{ .enum_type = .{ .name = ed.name, .variants = variants } };
}

// ── NOMINAL DESCRIPTORS · law.nominal, constitution §46 ─────────────────────
//
// `feet: f64` declares a descriptor named `feet` whose PHYSICAL REALIZATION is
// `f64`. A `feet` value is a `double` in the emitted C — no box, no wrapper, no
// tag — while being a DIFFERENT SEMANTIC IDENTITY from an `f64`.
//
// THE CARRIER IS THE ONE THAT ALREADY EXISTED (A2 NNS-FIRST). A named
// descriptor already resolves to `ResolvedType.@"struct"{ .name = "feet" }`;
// that node already carries the identity and already flows through every switch
// in the compiler. What was missing was the REPRESENTATION FACT, and that is
// all this map adds. Nothing was added to `ResolvedType`, so no lowering path
// grew a new arm it could get wrong, which is what makes "zero physical
// overhead" provable rather than hoped for: the only way a nominal descriptor
// can box is if `.@"struct"` boxes, and `feet` and `f64` answer `c_type` with
// the same six characters.
//
// NOMINALITY IS THE ABSENCE OF A RULE, NOT THE PRESENCE OF ONE. `eql` already
// compares `.@"struct"` by NAME, so `feet` ≠ `f64` for free. The work is
// entirely in the other direction — teaching the PHYSICAL queries
// (`is_integer`, `is_float`, `is_native`, `c_type`) to look through the
// identity to the representation, while the SEMANTIC queries keep seeing two
// distinct descriptors.
//
// ── DELETION CONTRACT (law.host.projection) ─────────────────────────────────
//
//     authority = false
//     projects  = descriptor
//     bootstrap = true
//     deletion  = when a descriptor is an ordinary graph node carrying its
//                 representation as a FACT, and identities are stable semantic
//                 ids rather than `[]const u8`. gap[091] is the gate.
//
// This is a process-global map keyed by TEXT, and both of those are the same
// bootstrap debt `src/relation.zig` records against itself (`law.relation.debt`
// — "string identities"). It is written down here at the moment the mechanism
// becomes useful, because that is when the pressure to fossilize starts.
var nominal_reprs: std.StringHashMapUnmanaged(ResolvedType) = .empty;

/// Land `name --realized-as--> repr`. Re-declaration REPLACES, so a later
/// module's descriptor wins over an earlier one of the same name, matching
/// `Relation.declare`.
pub fn declareNominal(alloc: std.mem.Allocator, name: []const u8, repr: ResolvedType) !void {
    try nominal_reprs.put(alloc, name, repr);
}

/// The representation of a nominal descriptor NAME, or null when the name is
/// not one. Null is the answer for every ordinary record descriptor, which is
/// what keeps this from changing the meaning of existing `.@"struct"` types.
pub fn nominalRepr(name: []const u8) ?ResolvedType {
    return nominal_reprs.get(name);
}

/// The representation behind a resolved type, when that type IS a nominal
/// descriptor. Every physical query in `ResolvedType` routes through this, and
/// so does the sema rule that refuses `d: feet = x` — one derivation, asked
/// from both directions.
pub fn nominalReprOf(t: ResolvedType) ?ResolvedType {
    return switch (t) {
        .@"struct" => |s| nominal_reprs.get(s.name),
        else => null,
    };
}

/// `feet` as a TYPE, when `feet` is a declared nominal descriptor. Used where a
/// descriptor name arrives as text (a conversion target group, a `mem` level).
pub fn nominalNamed(name: []const u8) ?ResolvedType {
    if (nominal_reprs.get(name) == null) return null;
    return ResolvedType{ .@"struct" = .{ .name = name } };
}

/// Which targets may carry a nominal descriptor. Deliberately narrow: a
/// descriptor over an aggregate is an ordinary record alias and must keep
/// behaving like one, so only the SCALARS — the representations that cost
/// nothing to be nominal over — are admitted.
pub fn nominalReprAdmissible(repr: ResolvedType) bool {
    return switch (repr) {
        .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .f32, .f64, .bool, .str => true,
        else => false,
    };
}

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
        is_compile_only: bool = false,
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
        /// Storage class determines lowering strategy:
        /// - .dynamic: boxed lua table with hash lookup
        /// - .guarded: inline-cached lookup with shape guard
        /// - .sealed: direct field offset access
        /// - .native: C struct layout with direct field access
        storage_class: StorageClass = .dynamic,
        is_sealed: bool = false, // true when no further fields will be added
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
            // law.nominal: a PHYSICAL question about `feet` is a question about
            // the double behind it. The semantic questions (`eql`, and the sema
            // rule that refuses a bare f64 where `feet` is demanded) are the
            // ones that must NOT look through.
            .@"struct" => |s| if (nominal_reprs.get(s.name)) |nr| nr.is_integer() else false,
            else => false,
        };
    }

    pub fn is_float(self: ResolvedType) bool {
        return switch (self) {
            .f32, .f64, .v4f64, .v8f32 => true,
            .@"struct" => |s| if (nominal_reprs.get(s.name)) |nr| nr.is_float() else false,
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

    /// Returns true if this type can be represented as native C without Lua boxing.
    /// Used by codegen to decide whether to emit lua_Value intermediaries.
    pub fn is_native(self: ResolvedType) bool {
        return switch (self) {
            .any, .nil, .never => false,
            .result, .option, .enum_type, .channel, .generic_param, .instantiated, .tensor => false,
            .table_type => |t| t.storage_class == .native,
            .func => |f| f.is_native,
            else => true,
        };
    }

    /// For table types, returns the storage class. For other types, returns false.
    pub fn storage_class(self: ResolvedType) ?StorageClass {
        return switch (self) {
            .table_type => |t| t.storage_class,
            else => null,
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
                    if (ta.is_sealed != tb.is_sealed) break :blk false;
                    if (ta.storage_class != tb.storage_class) break :blk false;
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
                // law.nominal: `feet` IS a double. This one line is the whole
                // of "zero physical overhead" — a nominal descriptor never
                // reaches the C emitter as a type of its own, so there is no
                // wrapper struct to allocate, no tag to test and no boxed
                // fallback to fall into.
                if (nominal_reprs.get(s.name)) |nr| return nr.c_type(buf);
                return std.fmt.bufPrint(buf, "duo_{s}", .{s.name}) catch s.name;
            },
            .array => |a| {
                var inner_buf: [128]u8 = undefined;
                const inner = a.elem.c_type(&inner_buf);
                if (a.size) |n| {
                    return std.fmt.bufPrint(buf, "{s}[{}]", .{ inner, n }) catch inner;
                }
                if (std.mem.eql(u8, inner, "lua_Value")) {
                    return "lua_Value";
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
            .generic_param => "lua_Value",
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
            if (std.mem.eql(u8, n, "ptr") or std.mem.eql(u8, n, "void*")) {
                const ptr = try alloc.create(ResolvedType);
                ptr.* = .void;
                return ResolvedType{ .pointer = ptr };
            }
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
                if (sema_ptr.foreign_records.get(n)) |foreign_rt| return foreign_rt;
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
            var out_rt = ResolvedType{ .table_type = .{ .fields = fields } };
            // `applyLayout` with a default Layout is exactly the old
            // `inferStorageClass(fields, false, .dynamic)`: a fresh table_type
            // has storage_class `.dynamic` and is_sealed `false`.
            applyLayout(&out_rt, rec.layout);
            return out_rt;
        },
        .constrained => |cp| {
            var concepts: std.ArrayListUnmanaged([]const u8) = .empty;
            defer concepts.deinit(alloc);
            switch (cp.constraint.*) {
                .named => |n| try concepts.append(alloc, n),
                else => {},
            }
            for (cp.extra) |extra| {
                switch (extra) {
                    .named => |n| try concepts.append(alloc, n),
                    else => {},
                }
            }
            if (concepts.items.len == 0) {
                return ResolvedType{ .generic_param = .{ .name = cp.name, .constraint = null } };
            }
            if (concepts.items.len == 1) {
                return ResolvedType{ .generic_param = .{ .name = cp.name, .constraint = concepts.items[0] } };
            }
            var combined: std.ArrayListUnmanaged(u8) = .empty;
            defer combined.deinit(alloc);
            for (concepts.items, 0..) |name, i| {
                if (i > 0) try combined.append(alloc, '|');
                try combined.appendSlice(alloc, name);
            }
            const owned = try combined.toOwnedSlice(alloc);
            return ResolvedType{ .generic_param = .{ .name = cp.name, .constraint = owned } };
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

test "inferStorageClass: all-native fields default to native" {
    const fields = [_]FieldType{
        .{ .name = "x", .typ = .f64 },
        .{ .name = "y", .typ = .f64 },
    };
    try testing.expectEqual(StorageClass.native, inferStorageClass(&fields, false, .dynamic));
}

test "inferStorageClass: mixed fields stay dynamic" {
    const fields = [_]FieldType{
        .{ .name = "x", .typ = .f64 },
        .{ .name = "y", .typ = .any },
    };
    try testing.expectEqual(StorageClass.dynamic, inferStorageClass(&fields, false, .dynamic));
}

test "inferStorageClass: sealed non-native becomes sealed" {
    const fields = [_]FieldType{
        .{ .name = "k", .typ = .any },
    };
    try testing.expectEqual(StorageClass.sealed, inferStorageClass(&fields, true, .dynamic));
}

test "applyTableShapeAttrs: @sealed sets sealed class" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(FieldType, 1);
    fields[0] = .{ .name = "x", .typ = .f64 };
    var resolved: ResolvedType = .{ .table_type = .{ .fields = fields } };
    const attrs = [_]ast.Attribute{.{ .name = "sealed", .args = null }};
    applyTableShapeAttrs(&resolved, &attrs);
    try testing.expect(resolved.table_type.is_sealed);
    try testing.expectEqual(StorageClass.sealed, resolved.table_type.storage_class);
}

test "layout: the refinement spelling and the attribute spelling are one fact" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Same descriptor, two spellings. `@packed @align(8) @sealed` (attributes,
    // via ast.Attribute) against `& packed & align(8) & sealed` (refinement
    // edges carried on the descriptor). Ontology collapse means the resolved
    // facts are equal — not merely compatible.
    const attr_fields = try alloc.alloc(FieldType, 1);
    attr_fields[0] = .{ .name = "x", .typ = .f64 };
    var from_attrs: ResolvedType = .{ .table_type = .{ .fields = attr_fields } };
    applyTableShapeAttrs(&from_attrs, &[_]ast.Attribute{
        .{ .name = "packed", .args = null },
        .{ .name = "align", .args = "8" },
        .{ .name = "sealed", .args = null },
    });

    const refined_fields = try alloc.alloc(FieldType, 1);
    refined_fields[0] = .{ .name = "x", .typ = .f64 };
    var from_refinements: ResolvedType = .{ .table_type = .{ .fields = refined_fields } };
    applyLayout(&from_refinements, .{
        .is_packed = true,
        .align_given = true,
        .align_n = 8,
        .sealed = true,
        .storage = .sealed,
    });

    try testing.expectEqual(from_attrs.table_type.is_packed, from_refinements.table_type.is_packed);
    try testing.expectEqual(from_attrs.table_type.align_n, from_refinements.table_type.align_n);
    try testing.expectEqual(from_attrs.table_type.is_sealed, from_refinements.table_type.is_sealed);
    try testing.expectEqual(from_attrs.table_type.storage_class, from_refinements.table_type.storage_class);

    // Positive control: the assertions above would also pass if applyLayout
    // were a no-op and both sides stayed at their defaults. They are not.
    try testing.expect(from_refinements.table_type.is_packed);
    try testing.expectEqual(@as(?usize, 8), from_refinements.table_type.align_n);
    try testing.expectEqual(StorageClass.sealed, from_refinements.table_type.storage_class);
}

test "layout: an empty attribute list still re-infers storage class" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(FieldType, 1);
    fields[0] = .{ .name = "x", .typ = .f64 };
    var resolved: ResolvedType = .{ .table_type = .{ .fields = fields } };
    applyTableShapeAttrs(&resolved, &.{});
    // Rewriting applyTableShapeAttrs in terms of applyLayout must not lose the
    // unconditional inferStorageClass call the old body ended with.
    try testing.expectEqual(StorageClass.native, resolved.table_type.storage_class);
}

test "resolve: inline record type infers native storage" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const rec_fields = try alloc.alloc(ast.RecordField, 2);
    rec_fields[0] = .{ .name = "x", .typ = .{ .named = "f64" }, .loc = .{ .file = "test", .line = 1, .col = 1 } };
    rec_fields[1] = .{ .name = "y", .typ = .{ .named = "f64" }, .loc = .{ .file = "test", .line = 1, .col = 1 } };
    const rec = try alloc.create(ast.TypeExpr.RecordType);
    rec.* = .{ .fields = rec_fields };
    const te: ast.TypeExpr = .{ .record = rec };
    const resolved = try resolve(te, null, alloc);
    try testing.expect(resolved == .table_type);
    try testing.expectEqual(StorageClass.native, resolved.table_type.storage_class);
}

test "applyTableShapeAttrs: @guarded sets guarded class" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(FieldType, 1);
    fields[0] = .{ .name = "x", .typ = .any };
    var resolved: ResolvedType = .{ .table_type = .{ .fields = fields } };
    const attrs = [_]ast.Attribute{.{ .name = "guarded", .args = null }};
    applyTableShapeAttrs(&resolved, &attrs);
    try testing.expectEqual(StorageClass.guarded, resolved.table_type.storage_class);
}

test "enumShapeIdentityHash: stable for same variants" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const variants = try alloc.alloc(EnumVariantType, 2);
    variants[0] = .{ .name = "Red", .payload = null };
    variants[1] = .{ .name = "Green", .payload = null };
    const a: ResolvedType = .{ .enum_type = .{ .name = "Color", .variants = variants } };
    const variants_b = try alloc.alloc(EnumVariantType, 2);
    variants_b[0] = .{ .name = "Red", .payload = null };
    variants_b[1] = .{ .name = "Green", .payload = null };
    const b: ResolvedType = .{ .enum_type = .{ .name = "Color", .variants = variants_b } };
    try testing.expectEqual(enumShapeIdentityHash(a), enumShapeIdentityHash(b));
}

test "explainStorageClass: native all-scalar record" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(FieldType, 2);
    fields[0] = .{ .name = "x", .typ = .f64 };
    fields[1] = .{ .name = "y", .typ = .f64 };
    const resolved: ResolvedType = .{ .table_type = .{
        .fields = fields,
        .storage_class = .native,
    } };
    try testing.expect(std.mem.indexOf(u8, explainStorageClass(resolved), "native C scalars") != null);
}

test "explainStorageClass: non-table expression" {
    try testing.expectEqualStrings(
        "not a typed table or record alias; dynamic Lua representation",
        explainStorageClass(.i64),
    );
}

test "tableShapeIdentityHash: identical layouts match" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = try alloc.alloc(FieldType, 1);
    fields[0] = .{ .name = "x", .typ = .f64 };
    const a: ResolvedType = .{ .table_type = .{ .fields = fields } };
    const b: ResolvedType = .{ .table_type = .{ .fields = fields } };
    try testing.expectEqual(tableShapeIdentityHash(a), tableShapeIdentityHash(b));
    try testing.expect(tableShapeIdentityHash(.i64) == null);
}

// ── Call-Shape Specialization ─────────────────────────────────────────────────
//
// A CallShape captures the compile-time-knowable properties of a call site.
// Used by the semantic graph to represent specialization opportunities and
// enable future devirtualization, return-pack specialization, closure
// specialization, and pipeline fusion.
//
// See §11 of docs/plans/semantic_graph_architecture.md.

/// Classification of how many return values a call site consumes.
pub const ReturnConsumption = enum {
    /// No return value used (statement position)
    discard,
    /// Single value consumed
    single,
    /// Multiple values consumed (e.g. `a, b = f()`)
    multi,
    /// Unknown at compile time
    unknown,
};

/// Classification of the callee identity known at the call site.
pub const CalleeKind = enum {
    /// Direct named function call: `foo(x)`
    direct,
    /// Method call on an object: `obj:method(x)`
    method,
    /// Indirect call through a variable or expression: `f(x)` where f is dynamic
    indirect,
    /// Known compile-time function (e.g. @comp.* or inlined constant)
    comptime_known,
};

/// Represents the compile-time-observable shape of a call site.
/// This is the key for specialization decisions — two call sites with the
/// same CallShape can share the same specialization.
pub const CallShape = struct {
    /// How the callee is referenced
    callee_kind: CalleeKind,
    /// Pass 24 §4.1 — parenthesized vs parenless vs command surface form.
    invocation_form: ast.InvocationForm = .parenthesized,
    /// Callee name if statically known (null for indirect calls)
    callee_name: ?[]const u8 = null,
    /// Method name if method call
    method_name: ?[]const u8 = null,
    /// Number of explicit arguments (not counting self for methods)
    arg_count: u8,
    /// Which argument positions have compile-time-known values
    known_args_mask: u32 = 0,
    /// Which argument positions have statically known types
    typed_args_mask: u32 = 0,
    /// Whether the call uses varargs (trailing `...`)
    has_varargs: bool = false,
    /// How many return values the call site consumes
    return_consumption: ReturnConsumption = .unknown,
    /// Whether the receiver's table shape is known (for method calls)
    receiver_shape_known: bool = false,

    /// Stable identity hash for call-shape deduplication and caching.
    /// Two CallShapes with the same hash are considered equivalent for
    /// specialization purposes.
    pub fn identityHash(self: CallShape) u64 {
        var h = std.hash.Wyhash.init(0xCA115A9E);
        h.update(std.mem.asBytes(&self.callee_kind));
        h.update(std.mem.asBytes(&self.invocation_form));
        h.update(std.mem.asBytes(&self.arg_count));
        h.update(std.mem.asBytes(&self.known_args_mask));
        h.update(std.mem.asBytes(&self.typed_args_mask));
        h.update(std.mem.asBytes(&self.has_varargs));
        h.update(std.mem.asBytes(&self.return_consumption));
        h.update(std.mem.asBytes(&self.receiver_shape_known));
        if (self.callee_name) |n| h.update(n);
        if (self.method_name) |m| h.update(m);
        return h.final();
    }

    /// True when this call shape could benefit from specialization.
    /// A call with all-unknown properties cannot be specialized.
    pub fn isSpecializable(self: CallShape) bool {
        if (self.callee_kind == .comptime_known) return true;
        if (self.known_args_mask != 0) return true;
        if (self.typed_args_mask != 0) return true;
        if (self.receiver_shape_known) return true;
        if (self.return_consumption != .unknown) return true;
        return false;
    }

    /// Human-readable summary for `@comp.why` and diagnostic output.
    pub fn explain(self: CallShape, buf: []u8) []const u8 {
        const kind_str: []const u8 = switch (self.callee_kind) {
            .direct => "direct",
            .method => "method",
            .indirect => "indirect",
            .comptime_known => "comptime",
        };
        const form_str = self.invocation_form.name();
        const callee_str = self.callee_name orelse "";
        const method_str = self.method_name orelse "";
        const known_count = @popCount(self.known_args_mask);
        const typed_count = @popCount(self.typed_args_mask);

        // Build explanation string incrementally
        var pos: usize = 0;
        const base = std.fmt.bufPrint(buf[pos..], "{s} {s} call", .{ kind_str, form_str }) catch return buf[0..0];
        pos += base.len;

        if (self.callee_name != null) {
            const s = std.fmt.bufPrint(buf[pos..], " to '{s}'", .{callee_str}) catch return buf[0..pos];
            pos += s.len;
        }
        if (self.method_name != null) {
            const s = std.fmt.bufPrint(buf[pos..], ":{s}", .{method_str}) catch return buf[0..pos];
            pos += s.len;
        }
        {
            const s = std.fmt.bufPrint(buf[pos..], ", {d} args", .{self.arg_count}) catch return buf[0..pos];
            pos += s.len;
        }
        if (self.known_args_mask != 0) {
            const s = std.fmt.bufPrint(buf[pos..], ", {d} known", .{known_count}) catch return buf[0..pos];
            pos += s.len;
        }
        if (self.typed_args_mask != 0) {
            const s = std.fmt.bufPrint(buf[pos..], ", {d} typed", .{typed_count}) catch return buf[0..pos];
            pos += s.len;
        }
        if (self.receiver_shape_known) {
            const s = std.fmt.bufPrint(buf[pos..], ", receiver sealed", .{}) catch return buf[0..pos];
            pos += s.len;
        }
        switch (self.return_consumption) {
            .discard => {
                const s = std.fmt.bufPrint(buf[pos..], ", result discarded", .{}) catch return buf[0..pos];
                pos += s.len;
            },
            .single => {
                const s = std.fmt.bufPrint(buf[pos..], ", single return", .{}) catch return buf[0..pos];
                pos += s.len;
            },
            .multi => {
                const s = std.fmt.bufPrint(buf[pos..], ", multi return", .{}) catch return buf[0..pos];
                pos += s.len;
            },
            .unknown => {},
        }
        return buf[0..pos];
    }

    /// Check if two CallShapes are equivalent for specialization.
    pub fn eql(a: CallShape, b: CallShape) bool {
        return a.identityHash() == b.identityHash();
    }
};

/// Classify return consumption from assignment target count (Pass 23 §6).
pub fn returnConsumptionForTargets(target_count: usize) ReturnConsumption {
    return switch (target_count) {
        0 => .unknown,
        1 => .single,
        else => .multi,
    };
}

/// Attach return consumption to an inferred call shape.
pub fn callShapeWithConsumption(shape: CallShape, consumption: ReturnConsumption) CallShape {
    var s = shape;
    s.return_consumption = consumption;
    return s;
}

/// Infer a CallShape from an AST call expression.
/// This is a conservative first pass — sema can refine later with type info.
pub fn inferCallShape(expr: *const ast.Expr) ?CallShape {
    switch (expr.*) {
        .call => |c| {
            const callee_name: ?[]const u8 = switch (c.func.*) {
                .name => |n| n.ident,
                .field => |f| f.field,
                else => null,
            };
            const kind: CalleeKind = if (callee_name != null) .direct else .indirect;
            return .{
                .callee_kind = kind,
                .callee_name = callee_name,
                .arg_count = @intCast(@min(c.args.len, 255)),
                .invocation_form = c.form,
            };
        },
        .method_call => |mc| {
            return .{
                .callee_kind = .method,
                .callee_name = null,
                .method_name = mc.method,
                .arg_count = @intCast(@min(mc.args.len, 255)),
                .invocation_form = mc.form,
            };
        },
        else => return null,
    }
}

/// Stable identity hash for a call shape (convenience wrapper).
pub fn callShapeIdentityHash(shape: CallShape) u64 {
    return shape.identityHash();
}

// ── CallShape Tests ──────────────────────────────────────────────────────────

test "CallShape: parenless vs parenthesized differ in identity hash" {
    const paren = CallShape{ .callee_kind = .direct, .callee_name = "f", .arg_count = 1, .invocation_form = .parenthesized };
    const plain = CallShape{ .callee_kind = .direct, .callee_name = "f", .arg_count = 1, .invocation_form = .parenless };
    try testing.expect(paren.identityHash() != plain.identityHash());
}

test "CallShape: direct call identity hash is stable" {
    const a = CallShape{
        .callee_kind = .direct,
        .callee_name = "add",
        .arg_count = 2,
        .typed_args_mask = 0b11,
    };
    const b = CallShape{
        .callee_kind = .direct,
        .callee_name = "add",
        .arg_count = 2,
        .typed_args_mask = 0b11,
    };
    try testing.expectEqual(a.identityHash(), b.identityHash());
}

test "CallShape: different arg counts produce different hashes" {
    const a = CallShape{ .callee_kind = .direct, .callee_name = "f", .arg_count = 1 };
    const b = CallShape{ .callee_kind = .direct, .callee_name = "f", .arg_count = 2 };
    try testing.expect(a.identityHash() != b.identityHash());
}

test "CallShape: method call shape" {
    const shape = CallShape{
        .callee_kind = .method,
        .method_name = "length",
        .arg_count = 0,
        .receiver_shape_known = true,
        .return_consumption = .single,
    };
    try testing.expect(shape.isSpecializable());
    try testing.expectEqual(@as(u64, shape.identityHash()), callShapeIdentityHash(shape));
}

test "CallShape: indirect with no info is not specializable" {
    const shape = CallShape{ .callee_kind = .indirect, .arg_count = 1 };
    try testing.expect(!shape.isSpecializable());
}

test "CallShape: comptime_known is always specializable" {
    const shape = CallShape{ .callee_kind = .comptime_known, .callee_name = "Vector", .arg_count = 2 };
    try testing.expect(shape.isSpecializable());
}

test "CallShape: explain produces readable output" {
    const shape = CallShape{
        .callee_kind = .direct,
        .callee_name = "scale",
        .arg_count = 1,
        .known_args_mask = 0b1,
        .return_consumption = .single,
    };
    var buf: [256]u8 = undefined;
    const explanation = shape.explain(&buf);
    // "direct call" became "direct parenthesized call" when CallShape grew an
    // invocation_form field and explain() started printing it. The form is real
    // output, not noise, so the test asserts the two words it actually cares
    // about rather than re-pinning a whole prefix that will move again.
    try testing.expect(std.mem.indexOf(u8, explanation, "direct") != null);
    try testing.expect(std.mem.indexOf(u8, explanation, "call") != null);
    try testing.expect(std.mem.indexOf(u8, explanation, "scale") != null);
    try testing.expect(std.mem.indexOf(u8, explanation, "1 known") != null);
    try testing.expect(std.mem.indexOf(u8, explanation, "single return") != null);
}

test "returnConsumptionForTargets: assign arity" {
    try testing.expect(returnConsumptionForTargets(1) == .single);
    try testing.expect(returnConsumptionForTargets(2) == .multi);
    try testing.expect(returnConsumptionForTargets(0) == .unknown);
}

test "inferCallShape: call expression" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\function main()
        \\  add(1, 2)
        \\  return 0
        \\end
    , "test.lua");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();
    const func_stmt = module.body.stmts[0];
    const body = func_stmt.func_decl.func.body;
    if (body.stmts.len == 0) return error.TestExpectedEqual;
    const stmt = body.stmts[0];
    // Standalone calls parse as call_stmt
    const expr = if (stmt == .call_stmt) stmt.call_stmt.expr else stmt.expr_stmt.expr;
    const shape = inferCallShape(expr) orelse return error.TestExpectedEqual;
    try testing.expectEqual(CalleeKind.direct, shape.callee_kind);
    try testing.expectEqualStrings("add", shape.callee_name.?);
    try testing.expectEqual(@as(u8, 2), shape.arg_count);
}

test "inferCallShape: method call expression" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var lex = Lexer.init(
        \\function main()
        \\  obj:method(x, y, z)
        \\  return 0
        \\end
    , "test.lua");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();
    const func_stmt = module.body.stmts[0];
    const body = func_stmt.func_decl.func.body;
    if (body.stmts.len == 0) return error.TestExpectedEqual;
    const stmt = body.stmts[0];
    // Standalone method calls parse as call_stmt
    const expr = if (stmt == .call_stmt) stmt.call_stmt.expr else stmt.expr_stmt.expr;
    const shape = inferCallShape(expr) orelse return error.TestExpectedEqual;
    try testing.expectEqual(CalleeKind.method, shape.callee_kind);
    try testing.expectEqualStrings("method", shape.method_name.?);
    try testing.expectEqual(@as(u8, 3), shape.arg_count);
}
