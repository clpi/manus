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
//                 ids rather than `[]const u8`. gap[097] is the gate.
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

/// Whether this descriptor identity is a SCALAR PHYSICAL REPRESENTATION — one
/// value in one cell, one register wide.
///
/// DERIVED, NOT TABULATED. The twelve-tag switch this replaced was another
/// statement of which identities are scalar, beside the one owner
/// `numericFacts`, and it could not compose: a scalar identity added to the
/// union above was one it silently did not know, which reads as "not a scalar"
/// — the wrong answer in the safe-looking direction. `lanes == 1` is the whole
/// numeric filter, because a vector identity is a numeric fact owner that is
/// not one cell (`v4i32` is four), and `nominalReprOf` is null-checked because
/// a nominal descriptor DELEGATES its numeric facts to its representation on
/// purpose (`law.nominal` §46) while remaining a distinct identity that is not
/// itself a representation.
///
/// `bool` and `str` stay explicit because no numeric owner can answer for
/// them: they are the two scalars that carry no arithmetic. That is a
/// statement about arithmetic, not a roster of widths.
pub fn scalarRepr(repr: ResolvedType) bool {
    if (repr.numericFacts()) |facts| {
        return facts.lanes == 1 and nominalReprOf(repr) == null;
    }
    return repr == .bool or repr == .str;
}

/// Which targets may carry a nominal descriptor. Deliberately narrow: a
/// descriptor over an aggregate is an ordinary record alias and must keep
/// behaving like one, so only the SCALARS — the representations that cost
/// nothing to be nominal over — are admitted.
pub fn nominalReprAdmissible(repr: ResolvedType) bool {
    return scalarRepr(repr);
}

/// A pointer descriptor over `pointee`.
fn pointerTo(alloc: std.mem.Allocator, pointee: ResolvedType) std.mem.Allocator.Error!ResolvedType {
    const ptr = try alloc.create(ResolvedType);
    ptr.* = pointee;
    return ResolvedType{ .pointer = ptr };
}

/// The legacy or foreign SPELLING of a scalar descriptor, mapped to the
/// canonical one. These three are irreducible: `isize`, `usize` and `string`
/// are not `ResolvedType` identities and no owner can derive them, so they are
/// a compatibility spelling face and nothing more. Nothing may be added here
/// that names an identity the union already spells.
fn memSpellingOf(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "isize")) return "i64";
    if (std.mem.eql(u8, name, "usize")) return "u64";
    if (std.mem.eql(u8, name, "string")) return "str";
    return name;
}

/// The descriptor a MEMORY-LEVEL type name projects — the `T` of
/// `mem.store(T)(p, v)` and `mem.load(T)(p)`, in either the canonical type-value
/// spelling or the graveyarded `"T"` string.
///
/// DERIVED, NOT TABULATED, AND OWNED ONCE. This roster of spellings existed
/// TWICE, identically, as `sema.mem_type_from_name` and
/// `codegen.mem_type_from_name` — one deciding which memory type names are
/// ADMITTED and the other deciding what each one REALIZES AS. That is the
/// two-realizations-of-one-fact shape: the two lists agreed only because
/// nobody had edited one of them yet, and a scalar identity added to the union
/// would have been refused by sema for the reason that nobody wrote the line,
/// not for any reason a law states.
///
/// A memory level names a place, so the question is exactly `scalarRepr` — one
/// value in one cell — plus the two compositions a cell address admits: `void`
/// (an untyped cell, which is what `ptr` points at) and a pointer, whose
/// spelling `*T` composes over this same face. Every identity the retired
/// rosters declined is declined here by that fact rather than by absence:
/// `any` is boxed and opaque, `nil` and `never` are not values in cells, and
/// the vector identities are numeric fact owners spanning several cells.
///
/// A NOMINAL DESCRIPTOR IS NOT ADMITTED HERE, and that is the retired
/// divergence made explicit rather than inherited. `codegen` accepted one
/// because the same function also answered the result type of `v:to(inch)`,
/// where the nominal name is the point; `sema` refused one, so no
/// `mem.store(feet)` ever reached `codegen` anyway. The nominal tail belongs to
/// that conversion consumer, which composes it on top of this face, not to the
/// memory level.
pub fn memDescriptorNamed(alloc: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error!?ResolvedType {
    if (name.len == 0) return null;
    if (name[0] == '*') {
        const inner = try memDescriptorNamed(alloc, name[1..]) orelse return null;
        return try pointerTo(alloc, inner);
    }
    if (std.mem.eql(u8, name, "ptr") or std.mem.eql(u8, name, "void*")) {
        return try pointerTo(alloc, .void);
    }
    const descriptor = descriptorNamed(memSpellingOf(name)) orelse return null;
    if (descriptor == .void or scalarRepr(descriptor)) return descriptor;
    return null;
}

/// The C SPELLING of a scalar descriptor, mapped to the canonical one. These two
/// are irreducible for the same reason `memSpellingOf`'s three are: `double` and
/// `float` are C's names for `f64` and `f32`, they are not `ResolvedType`
/// identities, and no owner can derive them. They belong to the FOREIGN INGRESS
/// boundary — a SIM entity imported from C carries C's word — and nothing may be
/// added here that names an identity the union already spells.
fn abiSpellingOf(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "double")) return "f64";
    if (std.mem.eql(u8, name, "float")) return "f32";
    return name;
}

/// The descriptor an ABI TYPE LABEL projects — the `type_name` a SIM record
/// field or function parameter carries, when that label names a value the ABI
/// passes in a register.
///
/// DERIVED, NOT TABULATED. This is the REALIZATION FACE of `scalarRepr`, and the
/// roster it replaced (`abi_specialize.isNativeScalarLabel`) was a sixth
/// statement of which identities are scalar and of their widths, standing at the
/// one seam that decides whether a foreign value is passed by value or by
/// pointer. A roster cannot compose: a scalar identity added to the union above
/// was one the ABI face silently did not know, and "not a native scalar" routes
/// the value to `target-default` — a wrong answer in the safe-looking direction,
/// which is the direction that does not get noticed.
///
/// The question an ABI label asks is exactly `scalarRepr` — one value in one
/// cell — MINUS `str`. That subtraction is not a roster entry: `str` is a
/// managed reference (`const char*`), so its ABI is a POINTER and the pointer
/// spelling is already the next question the consumer asks. Every identity the
/// retired roster declined is declined here by a fact rather than by absence:
/// `void` and `nil` and `never` are not values passed in a register, `any` is
/// boxed and opaque, the vector identities span several registers, and a nominal
/// descriptor is an identity rather than a representation.
pub fn abiDescriptorNamed(name: []const u8) ?ResolvedType {
    const descriptor = descriptorNamed(abiSpellingOf(name)) orelse return null;
    if (descriptor == .str) return null;
    if (!scalarRepr(descriptor)) return null;
    return descriptor;
}

/// The C printf/scanf conversion specifier that renders a scalar of this
/// PHYSICAL representation — `"%d"`, `"%u"`, `"%lld"`, `"%llu"`, `"%.17g"`, or
/// `"%s"` — or null when the identity is not a scalar the emitter formats with
/// a bare specifier.
///
/// DERIVED, NOT TABULATED. This is the RENDERING FACE of `scalarRepr`, and the
/// roster it replaced stood TWICE, verbatim, in `codegen` — the `print` arm and
/// the interpolation arm each kept the same six-arm switch from tag to
/// specifier, two statements of one fact that could only ever agree by hand.
/// The specifier is not a new fact: an integral scalar prints signed or
/// unsigned by `numericFacts.signed`, a real scalar prints `%.17g` by
/// `numericFacts.domain`, and the one distinction the switch added beyond the
/// numeric owner is the REGISTER WIDTH the C variadic ABI needs — a 64-bit
/// integer is passed as `long long` and takes `%lld`/`%llu` where a narrower
/// one takes `%d`/`%u` — which is `numericFacts.width == 64`, a fact the owner
/// already carries.
///
/// A roster could not compose: a scalar identity added to the union gained
/// numeric facts but stayed unknown to the hand-lists, which took the `else`
/// arm and emitted `"%s"` on a numeric value — the exact defect the
/// interpolation site's own comment records against `feet`, where `"%s"` on a
/// `double` segfaulted. Every non-scalar identity is declined by the
/// `numericFacts`/`scalarRepr` fact rather than by absence: the vectors span
/// several cells (`lanes != 1`), `any` is boxed, and `void`/`nil`/`never` are
/// not values a specifier renders. The caller keeps its own `"%s"` default for
/// the null answer, so a boxed or composed value still routes to the string
/// path exactly as before.
///
/// `bool` and `str` answer `"%s"` explicitly for the reason `scalarRepr` names
/// them explicitly: they are the two scalars that carry no arithmetic, so no
/// numeric owner can answer for them.
pub fn cFormatSpec(repr: ResolvedType) ?[]const u8 {
    if (repr.numericFacts()) |facts| {
        if (facts.lanes != 1) return null;
        if (facts.domain == .real) return "%.17g";
        if (facts.width == 64) return if (facts.signed) "%lld" else "%llu";
        return if (facts.signed) "%d" else "%u";
    }
    if (repr == .bool or repr == .str) return "%s";
    return null;
}

/// The scalar descriptor a C TYPE SPELLING projects — the inverse of `c_type`.
/// A foreign ingress site that meets `int32_t`, `const char*` or `double` and
/// has to learn which `ResolvedType` identity it realizes asks this.
///
/// DERIVED, NOT TABULATED. The roster this replaced (`codegen.type_from_c_name`)
/// was a SEVENTH statement of the scalar identity↔spelling correspondence, and
/// the one that ran BACKWARDS: `c_type` already owns "which C spelling does this
/// identity emit as", so a second list answering "which identity does this C
/// spelling name" is the same fact written twice and could only ever agree by
/// hand. It could not compose — a scalar identity added to the union gains a
/// `c_type` spelling but stays unknown here, which reads as "not a C type", the
/// wrong answer in the safe-looking direction that routes a foreign value to
/// `any` and boxes it.
///
/// The question is exactly the inverse of `c_type` over the SCALARS: the scalar
/// identities are the ones whose C spelling is a bare word an ingress label can
/// carry (`scalarRepr`, which is `bool` and `str` plus every one-cell numeric
/// owner), and each such identity's `c_type` spelling is unique, so a spelling
/// match is a scalar identity match. The non-scalar identities are declined by
/// that fact rather than by absence: `void`, `any`, `nil` and `never` are not
/// scalar values, the vectors span several cells, and a payload-carrying
/// identity's C spelling is a composition, not a bare label word.
pub fn descriptorByCSpelling(name: []const u8) ?ResolvedType {
    if (name.len == 0) return null;
    const info = @typeInfo(ResolvedType).@"union";
    inline for (info.field_names, info.field_types) |field_name, field_type| {
        if (field_type == void) {
            const identity = @as(ResolvedType, @field(ResolvedType, field_name));
            if (scalarRepr(identity)) {
                var buf: [32]u8 = undefined;
                if (std.mem.eql(u8, identity.c_type(&buf), name)) return identity;
            }
        }
    }
    return null;
}

/// The C spelling an ASYNC FRAME FIELD carries, when the field holds a value the
/// frame stores BY REPRESENTATION rather than as a dynamic box — or null when the
/// identity is not one a frame carries unboxed, so the caller keeps `lua_Value`.
///
/// DERIVED, NOT TABULATED. This is the ASYNC-FRAME FACE of the scalar roster, and
/// the roster it replaced (`async_lower.cTypeName`) was an EIGHTH statement of the
/// scalar identity↔C-spelling correspondence that `c_type` already owns. An async
/// frame materialises a suspended call's result and locals as C struct fields, so
/// each field's C spelling is the one `c_type` emits — a second hand-kept list of
/// the same eleven scalars plus `void`, agreeing with `c_type` only until someone
/// edits one of them. A roster could not compose: a scalar identity added to the
/// union gained a `c_type` spelling but stayed unknown to the frame list, took its
/// `else` arm, and got boxed to `lua_Value` — a frame field silently widened to a
/// dynamic box on a value that has a register representation, the wrong answer in
/// the safe-looking direction.
///
/// The question a frame field asks is exactly `scalarRepr` — one value in one
/// cell — PLUS `void`, the two identities a frame stores as their own C type. For
/// that set `c_type` returns a bare literal spelling and never touches the buffer,
/// so the spelling is the frame field's type verbatim. Every other identity is
/// declined by that fact rather than by absence and routes to the caller's
/// `lua_Value`: `any` is already boxed, `nil`/`never` are not frame values, the
/// vectors span several cells, and a pointer/struct/array is a composition a frame
/// field does not carry inline.
pub fn cFrameType(repr: ResolvedType) ?[]const u8 {
    if (scalarRepr(repr) or repr == .void) {
        var buf: [1]u8 = undefined;
        return repr.c_type(&buf);
    }
    return null;
}

/// The REFLECTION type-name a concept field row carries — the source word a
/// runtime reflection value reports for a field's declared type — or null when
/// the identity is not one the reflection string names with its own word, so
/// the caller keeps `"any"`.
///
/// DERIVED, NOT TABULATED. This is the REFLECTION FACE of the scalar roster, and
/// the roster it replaced (`codegen.emit_resolved_type_name_string`) was a NINTH
/// statement of the scalar identity↔source-spelling correspondence that
/// `duo_name` already owns. A concept field row emits the declared type's source
/// word as a C string literal, so each identity's word is the one `duo_name`
/// renders — a second hand-kept list of the same ten scalars plus `void`/`any`/
/// `nil` and the struct name, agreeing with `duo_name` only until someone edits
/// one of them. A roster could not compose: a scalar identity added to the union
/// gained a `duo_name` spelling but stayed unknown to the reflection list, took
/// its `else` arm, and reported `"any"` for a field that has a real source
/// word — a reflection value silently widened to the top type, the wrong answer
/// in the safe-looking direction.
///
/// The question a reflection word asks is exactly `scalarRepr` — the identities
/// whose source word is a bare scalar spelling — PLUS the three non-scalar
/// identities `void`, `any` and `nil` that the reflection string still names
/// with their own word, PLUS a struct's declared name. For that set `duo_name`
/// returns the bare word (or the name) and never composes into the buffer, so
/// the word is the reflection field's type verbatim. Every other identity is
/// declined by that fact rather than by absence and routes to the caller's
/// `"any"`: the vectors span several cells (`scalarRepr` is false because
/// `lanes != 1`), `never` is not a value, and a pointer/array/option/result/
/// func/enum/channel/table/generic/instantiated/tensor is a composition whose
/// `duo_name` builds a compound string the reflection roster folded to `"any"`.
pub fn reflectName(repr: ResolvedType) ?[]const u8 {
    if (repr == .@"struct") return repr.@"struct".name;
    if (scalarRepr(repr) or repr == .void or repr == .any or repr == .nil) {
        var buf: [1]u8 = undefined;
        return repr.duo_name(&buf);
    }
    return null;
}

/// The MANGLED NAME FRAGMENT a monomorphized specialization carries for one
/// type argument, when that argument is an identity whose fragment is its own
/// bare source word — or null when the identity is a composition the mangler
/// must render and sanitize itself, so the caller keeps its debug-render tail.
///
/// DERIVED, NOT TABULATED. This is the MANGLING FACE of the scalar roster, and
/// the roster it replaced (`mono.appendTypeName`'s explicit arms) was a TENTH
/// statement of the scalar identity↔source-spelling correspondence that
/// `duo_name` already owns. A deterministic C symbol appends each type
/// argument's source word after `duo_`, so each scalar's fragment is the word
/// `duo_name` renders — a second hand-kept list of the same ten numeric scalars
/// plus `bool`/`str`/`any`, agreeing with `duo_name` only until someone edits
/// one of them. A roster could not compose: a scalar identity added to the
/// union gained a `duo_name` word but stayed unknown to the mangle list, took
/// its `else` arm, and got a SANITIZED DEBUG rendering instead of its own word
/// — two specializations over two different scalars could then mangle to the
/// same symbol if their debug renderings sanitized alike, the wrong answer in
/// the safe-looking direction that silently merges distinct definitions.
///
/// The question a mangle fragment asks is exactly `scalarRepr` — one value in
/// one cell — PLUS `any`, the identities whose `duo_name` is a bare word that
/// is already a valid C identifier fragment (`[a-z0-9]+`), so no sanitization
/// changes it. Every other identity is declined by that fact rather than by
/// absence and routes to the caller's sanitized-debug tail: `void`/`nil`/
/// `never` are not type arguments a specialization carries, the vectors span
/// several cells, and a struct/enum/pointer/array/composition renders a name or
/// compound the mangler must still sanitize itself. A struct and an enum keep
/// their own arms in the caller because their fragment is a DECLARED NAME that
/// must be sanitized to a C identifier, which `duo_name` does not do.
pub fn mangleFragment(repr: ResolvedType) ?[]const u8 {
    if (scalarRepr(repr) or repr == .any) {
        var buf: [1]u8 = undefined;
        return repr.duo_name(&buf);
    }
    return null;
}

/// The physical cell a scalar descriptor MATERIALIZES IN when it is a field of
/// a natively-lowered record, table row, or parameter — one of the three the
/// native IR carries (`native_ir.FieldKind = { i64, str, f64 }`). This owner
/// names the class as its own three-variant enum rather than the IR one,
/// because `types.zig` is IR and `native_ir.zig` is a codegen carrier below it;
/// the one consumer maps this class to its own `FieldKind` by name at the seam,
/// which is a rename over the same three identities, not a second authority.
///
/// DERIVED, NOT TABULATED. This is the FIELD-CELL FACE of the scalar roster.
/// The partition existed TWICE in `dnir_lower`, as `graphFieldFact` (which also
/// carries the sub-register store width) and `tableFieldKind` (which drops it),
/// each a per-tag switch mapping `str`→str, `f64`→f64, and every integral
/// spelling plus `bool`→i64. Two statements of one fact that agree only until
/// someone edits one: a `ResolvedType` value in one cell has a domain
/// (`numericFacts.domain`) and, if not numeric, is `bool` or `str`
/// (`scalarRepr`). A roster could not compose: a scalar identity added to the
/// union gained numeric facts but stayed unknown to the hand-lists, took their
/// `else` arm, and was silently declared NOT A NATIVE FIELD — a record that
/// should lower natively fell back to a boxed row, the wrong answer in the
/// safe-looking direction.
///
/// The three cells are NOT the whole scalar roster, and this face preserves the
/// two exclusions the retired switches encoded by omission rather than widening
/// them:
///   * only the 64-bit real is a field cell (`f64`); `f32` has NO native field
///     cell and answered `else`/null, so `domain == .real` alone is not the
///     test — `width == 64` is;
///   * a NOMINAL DESCRIPTOR is withheld, not delegated: the retired switches
///     listed only bare scalar tags, so a nominal-over-`i32` (a `.struct` tag)
///     fell to `else`, and `scalarRepr` withholds it identically
///     (`nominalReprOf != null`). This is the one physical face where the
///     nominal takes the caller's boxed row rather than its representation's
///     cell.
/// Every non-scalar identity is declined by the `scalarRepr` fact rather than
/// by absence: the vectors span several cells (`lanes != 1`), `any` is boxed,
/// `void`/`nil`/`never` are not field values, and a pointer/array/struct/
/// composition is not a scalar cell.
pub const ScalarFieldCell = enum { i64, str, f64 };

pub fn scalarFieldCell(repr: ResolvedType) ?ScalarFieldCell {
    if (!scalarRepr(repr)) return null;
    if (repr == .str) return .str;
    // A scalar that is not `str` is `bool` (no numeric facts, register-integer
    // cell) or a one-cell numeric owner. Only the 64-bit real is a field cell;
    // `f32` has no native field cell and is declined here exactly as the retired
    // switches declined it by listing only `f64`.
    const facts = repr.numericFacts() orelse return .i64;
    return switch (facts.domain) {
        .integral => .i64,
        .real => if (facts.width == 64) .f64 else null,
    };
}

/// The `lua_Value` CONSTRUCTOR a scalar descriptor boxes through, when a native
/// value crosses into the dynamic runtime — or null when the identity is not a
/// scalar the runtime boxes with a bare constructor, so the caller keeps its
/// own boxing tail (`lua_val_nil()`, an identity passthrough, or a fallback to
/// `emit_as_lua_value`).
///
/// DERIVED, NOT TABULATED. This is the BOXING FACE of the scalar roster. The
/// constructor↔representation correspondence stood in `codegen` as two per-tag
/// SWITCHES that hand-listed all eight integral tags
/// (`.i8,.i16,.i32,.i64,.u8,.u16,.u32,.u64 => "lua_val_from_int((int64_t)"`,
/// reals → `lua_val_from_num((double)`, then `bool`/`str`, else the box-less
/// tail) — one at a native module-call return boundary and one at a native
/// scalar-global export. Which constructor a scalar boxes through is not a new
/// fact: an integral scalar boxes as an integer (`lua_val_from_int`), a real
/// scalar as a number (`lua_val_from_num`) — that is `numericFacts.domain` —
/// and the two arithmetic-free scalars box as themselves (`bool`, `str`), the
/// same two `scalarRepr` names explicitly.
///
/// The integer arm is not merely a cast: routing an integral through the double
/// constructor SILENTLY ROUNDED every value above 2^53 — the defect
/// `emit_native_scalar_to_lua_value`'s own comment records, where `crc64.final`
/// returned `0x2B9C7EE4E2780C8A` and the number box handed back its low 9 bits
/// cleared. So `domain` is exactly the fact that must decide it, and a switch
/// that lists integral tags by hand is one a new integral identity is silently
/// absent from — folding to `else`, boxing as a passthrough, and losing the
/// integer box.
///
/// A switch could not compose: a scalar identity added to the union gained
/// numeric facts but stayed unknown to the two switch sites, took their box-less
/// tail — the wrong answer in the safe-looking direction. Every non-scalar
/// identity is declined by the `numericFacts`/`scalarRepr` fact rather than by
/// absence: the vectors span several cells (`lanes != 1`) and were absent from
/// the retired switches' bare-tag lists exactly so; `any` is already boxed; and
/// `void`/`nil`/`never`/composed identities are not scalars the runtime boxes
/// with a bare constructor. A NOMINAL DESCRIPTOR is withheld here as an
/// identity, exactly as `scalarRepr` withholds it (`law.nominal` §46); the
/// retired switches listed only bare scalar tags, so a nominal-over-`i32`
/// (a `.struct` tag) fell to the box-less tail identically.
pub const LuaBoxClass = enum {
    int,
    num,
    @"bool",
    str,

    /// The C constructor OPEN this box class emits, including the cast the
    /// integer and number boxes require. The caller closes with its own paren
    /// tail. This is the one place the constructor string is stated.
    pub fn ctor(self: LuaBoxClass) []const u8 {
        return switch (self) {
            .int => "lua_val_from_int((int64_t)",
            .num => "lua_val_from_num((double)",
            .@"bool" => "lua_val_from_bool(",
            .str => "lua_val_from_str(",
        };
    }
};

pub fn luaBoxClass(repr: ResolvedType) ?LuaBoxClass {
    if (!scalarRepr(repr)) return null;
    if (repr == .str) return .str;
    // A scalar that is not `str` is `bool` (no numeric facts) or a one-cell
    // numeric owner. `bool` boxes as itself; a numeric owner boxes by domain —
    // an integral as an integer so a value above 2^53 is not rounded through
    // the double box, a real as a number.
    const facts = repr.numericFacts() orelse return .@"bool";
    return switch (facts.domain) {
        .integral => .int,
        .real => .num,
    };
}

/// How a scalar descriptor UNWRAPS a `lua_Value` back into its native
/// representation — the inverse of `LuaBoxClass`. Where the box class owns the
/// constructor that crosses a native scalar INTO the dynamic runtime, this owns
/// the coercion that crosses a `lua_Value` back OUT into a native place.
///
/// The `num` variant carries the descriptor because its unwrap casts through
/// the scalar's own C spelling — `((int32_t)lua_to_num(...))` — a width the box
/// class did not need (every integral boxes through one `int64_t` cast) but the
/// unwrap does, since it lands in a place of exactly that width. `str` and
/// `bool` carry no width: `lua_to_str`/`lua_to_bool` name their own result.
pub const LuaCoerceClass = union(enum) {
    str,
    @"bool",
    num: ResolvedType,

    /// The C coercion OPEN this class emits. The caller closes with `close()`.
    /// This is the one place the coercion strings are stated. `num` renders the
    /// scalar's C spelling into the caller's buffer, so the value lands in a
    /// place of exactly its declared width rather than the boxed 64-bit ring.
    pub fn open(self: LuaCoerceClass, buf: []u8) []const u8 {
        return switch (self) {
            .str => "lua_to_str(",
            .@"bool" => "lua_to_bool(",
            .num => |repr| blk: {
                var cbuf: [128]u8 = undefined;
                break :blk std.fmt.bufPrint(buf, "(({s})lua_to_num(", .{repr.c_type(&cbuf)}) catch "((lua_to_num(";
            },
        };
    }

    /// The C coercion CLOSE matching `open`. `str`/`bool` unwrap with one call
    /// and close with one paren; `num` opens the cast paren and the call paren
    /// and closes both.
    pub fn close(self: LuaCoerceClass) []const u8 {
        return switch (self) {
            .str, .@"bool" => ")",
            .num => "))",
        };
    }
};

/// The coercion class a scalar descriptor unwraps a `lua_Value` through, or
/// null for an identity coercion (`any`, which is already a `lua_Value`) and
/// for every non-scalar identity. This is the inverse partition of
/// `luaBoxClass`: it gates on the SAME `scalarRepr` fact, answers `str`/`bool`
/// for the two arithmetic-free scalars, and reads `numericFacts` for the
/// numeric owners — but it discards the box class's integral/real DOMAIN split
/// because every scalar leaves the box through one `lua_to_num`, differing only
/// in the C spelling it casts to, which the `num` variant carries.
///
/// A NOMINAL DESCRIPTOR is WITHHELD here as an identity, exactly as `scalarRepr`
/// withholds it and exactly as the retired `codegen` switches' bare scalar tags
/// let a nominal-over-`i32` (a `.struct` tag) fall to their else arm.
pub fn luaCoerceClass(repr: ResolvedType) ?LuaCoerceClass {
    if (!scalarRepr(repr)) return null;
    if (repr == .str) return .str;
    // A scalar that is not `str` is `bool` (no numeric facts) or a one-cell
    // numeric owner. `bool` unwraps as itself; a numeric owner unwraps through
    // `lua_to_num` and casts to its own C spelling.
    if (repr.numericFacts() == null) return .@"bool";
    return LuaCoerceClass{ .num = repr };
}

/// Whether a scalar place ACCEPTS coercion from a `lua_Value`. This is
/// `luaCoerceClass` plus `any`: `any` is accepted but coerces by identity (it
/// already IS a `lua_Value`), so it has no coercion class and the caller emits
/// no wrapper. Every other non-scalar identity is refused.
pub fn luaCoerceAccepts(repr: ResolvedType) bool {
    return repr == .any or luaCoerceClass(repr) != null;
}

/// Resolved type after semantic analysis.
/// During sema, each expression gets a `ResolvedType` attached.
/// The declared width of a sub-64-bit integer descriptor, and whether
/// projecting it into a 64-bit register sign- or zero-extends.
///
/// `i64`, `u64` and `.any` answer NULL: they are already the register width, so
/// nothing on the i64 path may gain an instruction from this. `u64` is out of
/// scope for a different reason — it does not need TRUNCATION at all, only
/// unsigned division/shift/compare, which is a separate defect.
pub const NarrowFit = struct { bits: u7, signed: bool };

/// Numeric meaning projected by one descriptor.
///
/// `ResolvedType` remains the bootstrap carrier, but consumers no longer have
/// to reconstruct numeric law from its tag. Width is the lane width; `lanes`
/// keeps vector cardinality orthogonal to it. An absent range is unknown, not a
/// sentinel (notably the scalar `u64` range does not fit in an `i64` pair).
pub const NumericFacts = struct {
    pub const Domain = enum { integral, real };
    pub const Format = enum { twos_complement, ieee754_binary };
    pub const Overflow = enum { wrap, ieee754 };
    pub const Rounding = enum { exact, nearest_even };
    pub const Range = struct { min: i64, max: i64 };

    domain: Domain,
    width: u7,
    lanes: u8 = 1,
    signed: bool,
    format: Format,
    overflow: Overflow,
    rounding: Rounding,
    range: ?Range = null,

    /// Whether a descriptor carrying these facts can satisfy the domain a bare
    /// numeric source face contributes. An integral face may be realized by an
    /// integral or real demand; a real face requires a real demand. Width,
    /// signedness and representation come from the demand, never the token.
    pub fn acceptsSource(self: NumericFacts, source: Domain) bool {
        return source == .integral or self.domain == .real;
    }

    /// Whether this descriptor demand accepts a value that already carries the
    /// supplied numeric facts. Existing values do not regain the freedom of a
    /// bare source face: only one numeric domain satisfies another. Width and
    /// signedness remain realization facts handled by the existing projection.
    pub fn acceptsDescriptor(self: NumericFacts, supplied: NumericFacts) bool {
        return self.domain == supplied.domain;
    }

    /// Whether a value carrying `self`'s facts widens without loss into a place
    /// carrying `target`'s facts. This is a single-lane scalar question: a
    /// vector spans several cells and a field migration does not cast one lane
    /// count into another, so `lanes != 1` on either side has no widening
    /// answer. `self == target` is not this projection's to answer — a value
    /// already of the target descriptor is not a WIDENING, and the caller owns
    /// that equal-descriptor case ahead of asking.
    ///
    /// The three arms are the numeric containment lattice, not a roster:
    ///   * real → real widens to a strictly wider real (`f32` → `f64`);
    ///   * integral → real widens a SUB-REGISTER integral (width < 64) into the
    ///     double, whose mantissa represents every such value exactly; a
    ///     register-width integral (`i64`/`u64`) does NOT widen into `f64`,
    ///     because a 64-bit integer exceeds the double's 53-bit exact-integer
    ///     range and the cast loses precision, and no integral widens into
    ///     `f32` at all;
    ///   * integral → integral widens to a strictly wider integral of the same
    ///     signedness, and an unsigned source additionally widens into the
    ///     register-width signed integral that dominates its whole range.
    /// A real never narrows into an integral, and a signed source never crosses
    /// into unsigned. Every one of these is a fact `self`/`target` already
    /// carry (`domain`, `width`, `signed`), so a scalar identity added to the
    /// numeric owner gains its widening answer here rather than staying unknown
    /// to a hand-kept list.
    pub fn widensTo(self: NumericFacts, target: NumericFacts) bool {
        if (self.lanes != 1 or target.lanes != 1) return false;
        return switch (self.domain) {
            .real => target.domain == .real and target.width > self.width,
            .integral => switch (target.domain) {
                .real => target.width >= 64 and self.width < 64,
                .integral => if (self.signed == target.signed)
                    target.width > self.width
                else if (!self.signed and target.signed)
                    target.width >= 64 and self.width < 64
                else
                    false,
            },
        };
    }
};

/// The value a write of `v` to a place of type `ty` leaves behind.
///
/// `native_backend.emitNarrowFit` MUST agree with this bit for bit, and
/// `comptime`'s folder now calls it rather than answering in the 64-bit ring.
/// A folded constant that skipped the projection the register path performs is
/// a decision computed against one state and read against another — the shape
/// behind every silent wrong answer in this tree.
pub fn narrowFitConst(v: i64, ty: ResolvedType) i64 {
    const fit = ty.narrowFit() orelse return v;
    const shift: u6 = @intCast(64 - @as(u7, fit.bits));
    const kept: u64 = @as(u64, @bitCast(v)) << shift;
    if (fit.signed) return @as(i64, @bitCast(kept)) >> shift;
    return @bitCast(kept >> shift);
}

/// The descriptor a bare type NAME projects, or null when no descriptor answers
/// to that spelling.
///
/// THE ROSTER OF SCALAR DESCRIPTOR IDENTITIES IS THE ONE PRODUCER OF THE ROSTER
/// OF THEIR SPELLINGS. A payload-free `ResolvedType` identity *is* its own
/// source face — `i32` the tag and `i32` the annotation are one identity read
/// from two sides — so this projects the union's own tag names rather than
/// writing a second list beside them. A second list is what drifts: a new
/// scalar identity added to the union above would be a type the annotation face
/// silently did not know, and there is no such possibility here.
///
/// Payload-carrying identities (`array`, `pointer`, `struct`, `result`,
/// `option`, `table_type`, ...) are refused: their spelling in source is a
/// COMPOSITION and cannot be reconstructed from a bare word. A declared nominal
/// descriptor is the one non-scalar word that names a descriptor, and it
/// projects through the same single owner (`nominalNamed`) every other nominal
/// query already uses.
pub fn descriptorNamed(name: []const u8) ?ResolvedType {
    const Tag = @typeInfo(ResolvedType).@"union".tag_type.?;
    const tag = std.meta.stringToEnum(Tag, name) orelse return nominalNamed(name);
    switch (tag) {
        inline else => |t| {
            if (@FieldType(ResolvedType, @tagName(t)) != void) return nominalNamed(name);
            return @unionInit(ResolvedType, @tagName(t), {});
        },
    }
}

/// The declared narrow width of a TYPE EXPRESSION, or null for everything else.
///
/// `i32` is included even though `resolveType` already answers `.i32`: nothing
/// downstream had ever acted on that answer, so `h: i32 = 2147483647; h = h + 1`
/// printed 2147483648 where C printed -2147483648.
///
/// DERIVED, NOT TABULATED — this is the ANNOTATION FACE of `narrowFit`, and the
/// name roster it replaced was a second statement of which widths are narrow
/// and a fifth statement of width and signedness. `narrowFit` already composes
/// through a nominal descriptor while this list could not see one, so a place
/// declared `p: tick = ...` over a nominal-over-`i32` reached `codegen` as
/// `int32_t` and truncated while `dnir_lower` and `comptime` were handed no
/// width at all and kept the full 64-bit ring. That is the same
/// two-realizations-of-one-fact defect `narrowFit`'s own comment records
/// against itself, arriving one seam earlier through the AST annotation.
///
/// The answer is the PHYSICAL descriptor, because the width of a place is a
/// physical question (`law.nominal` §46): a nominal identity delegates it to
/// its representation exactly as `narrowFit`, `c_type` and ARC already do, and
/// the caller receives a scalar it can put in an `Instr.ty`. Filtering on
/// `narrowFit` is why no wider or real name can leak: the fit exists only for
/// an integral, single-lane, sub-register width.
pub fn narrowIntOfType(t: ast.TypeExpr) ?ResolvedType {
    if (t != .named) return null;
    const named = descriptorNamed(t.named) orelse return null;
    const physical = nominalReprOf(named) orelse named;
    if (physical.narrowFit() == null) return null;
    return physical;
}
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

    // SIMD vector types.
    //
    // THESE FOUR ARE 32 BYTES WIDE AND THE CANONICAL BACKEND'S REGISTER IS 16.
    // Measured, not inferred: `--backend=direct` emits AArch64 for Apple
    // Silicon, where the NEON register file is 128 bits and there is no SVE
    // (`hw.optional.arm.FEAT_SME` = 0, no SVE control at all on this part). So
    // the native widths are v2f64 / v2i64 / v4f32 / v4i32, and every type below
    // names TWO registers.
    //
    // They are not a mistake; they are C-backend types that outlived their
    // backend. `codegen.zig` lowers each one to a 32-byte `vector_size` typedef
    // — four f64/i64 lanes or eight f32/i32 lanes — where any width is legal
    // because the C compiler splits it; that spelling replaced a clang-only
    // `ext_vector_type` which gcc silently ignored, decaying the typedefs to
    // their scalar element types. `codegen.zig` also gives them a 32-byte
    // alignment, which is the tell:
    // 32 is the AVX register, not the NEON one. Read as a declaration of what
    // the language can vectorize, they claim 4- and 8-wide on a machine whose
    // widest lane group is 2 for f64/i64 and 4 for f32/i32.
    //
    // WHAT THE MEASUREMENT SAYS THE RIGHT ANSWER IS. `benchmarks/simd/` puts the
    // i64 reduction ceiling at 4.06x scalar, reached at EIGHT i64 lanes — which
    // on this machine is four q registers, not one v8i64 type. Width in the type
    // system and width in a register are different facts, and fusing them is how
    // a 32-byte type ends up describing a 16-byte machine. An honest native
    // spelling declares the REGISTER (v2i64, v4i32, ...) and lets the unroll
    // factor be an unroll factor.
    //
    // NOT DELETED HERE because `sema.zig` and `codegen.zig` both construct and
    // consume them and neither is this change's to edit; the direct backend has
    // no lowering for any of them, so no `--backend=direct` program can reach
    // one today. Recorded so the next reader does not take `v8i32` as evidence
    // that this compiler emits an eight-wide anything.
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

    /// THE PROJECTION OF THIS DESCRIPTOR — the value a semantic write to a
    /// place of this type LEAVES BEHIND, exactly, at every write.
    ///
    /// It lives HERE, beside the descriptor it is a property of, because three
    /// independent consumers must agree on it bit for bit and any two of them
    /// disagreeing is a silent wrong answer:
    ///
    ///     `dnir_lower`      chooses `Instr.ty` for the store
    ///     `native_backend`  realizes it as `sxtb`/`sxth`/`sxtw`/`ubfx`/`w`-form
    ///     `comptime`        folds it when the loop never reaches emission
    ///
    /// The third was MISSING and answered in the full 64-bit ring, so
    /// `t: i32 = 0; while i < 2: t = t + 2000000000` folded to `mov x0, #7`
    /// where the same program with a runtime bound emitted `sxtw` and answered
    /// 9. Two implementations of one fact, one of them absent — which is the
    /// failure `dnir_lower`'s own `narrowFitConst` comment names and then could
    /// not prevent, because the folder could not see the function.
    ///
    /// SO IT IS DERIVED, NOT TABULATED. The tag switch this replaced was a
    /// FOURTH statement of width and signedness, which `numericFacts` already
    /// owns — and a table cannot compose. `c_type` delegates a nominal
    /// descriptor to its representation (`feet` and `f64` answer the same six
    /// characters), so a place declared over a nominal-over-`i32` reached the C
    /// emitter as `int32_t` and truncated, while the same place reached
    /// `dnir_lower` and `native_backend` with no fit at all and kept the full
    /// 64-bit ring. Two realizations of one descriptor's write projection
    /// disagreeing is the same defect one paragraph up, arriving through a
    /// wrapper the table could not see.
    ///
    /// Width alone does not settle it: `lanes` keeps vector cardinality
    /// orthogonal, so `v8i32` carries width 32 and is not a narrow scalar, and
    /// `i64`/`u64` are already the register width and must not gain an
    /// instruction from this.
    pub fn narrowFit(self: ResolvedType) ?NarrowFit {
        const facts = self.numericFacts() orelse return null;
        if (facts.domain != .integral or facts.lanes != 1) return null;
        if (facts.width >= 64) return null;
        return .{ .bits = facts.width, .signed = facts.signed };
    }

    /// The compositional numeric facts carried by this descriptor.
    ///
    /// This is the sole host-bootstrap projection from `ResolvedType` tags. A
    /// nominal descriptor delegates only its numeric facts to its
    /// representation; its semantic identity remains nominal and `eql` does
    /// not look through it.
    pub fn numericFacts(self: ResolvedType) ?NumericFacts {
        return switch (self) {
            .i8 => .{ .domain = .integral, .width = 8, .signed = true, .format = .twos_complement, .overflow = .wrap, .rounding = .exact, .range = .{ .min = -128, .max = 127 } },
            .i16 => .{ .domain = .integral, .width = 16, .signed = true, .format = .twos_complement, .overflow = .wrap, .rounding = .exact, .range = .{ .min = -32768, .max = 32767 } },
            .i32 => .{ .domain = .integral, .width = 32, .signed = true, .format = .twos_complement, .overflow = .wrap, .rounding = .exact, .range = .{ .min = -2147483648, .max = 2147483647 } },
            .i64 => .{ .domain = .integral, .width = 64, .signed = true, .format = .twos_complement, .overflow = .wrap, .rounding = .exact, .range = .{ .min = std.math.minInt(i64), .max = std.math.maxInt(i64) } },
            .u8 => .{ .domain = .integral, .width = 8, .signed = false, .format = .twos_complement, .overflow = .wrap, .rounding = .exact, .range = .{ .min = 0, .max = 255 } },
            .u16 => .{ .domain = .integral, .width = 16, .signed = false, .format = .twos_complement, .overflow = .wrap, .rounding = .exact, .range = .{ .min = 0, .max = 65535 } },
            .u32 => .{ .domain = .integral, .width = 32, .signed = false, .format = .twos_complement, .overflow = .wrap, .rounding = .exact, .range = .{ .min = 0, .max = 4294967295 } },
            .u64 => .{ .domain = .integral, .width = 64, .signed = false, .format = .twos_complement, .overflow = .wrap, .rounding = .exact },
            .f32 => .{ .domain = .real, .width = 32, .signed = true, .format = .ieee754_binary, .overflow = .ieee754, .rounding = .nearest_even },
            .f64 => .{ .domain = .real, .width = 64, .signed = true, .format = .ieee754_binary, .overflow = .ieee754, .rounding = .nearest_even },
            .v4f64 => .{ .domain = .real, .width = 64, .lanes = 4, .signed = true, .format = .ieee754_binary, .overflow = .ieee754, .rounding = .nearest_even },
            .v4i64 => .{ .domain = .integral, .width = 64, .lanes = 4, .signed = true, .format = .twos_complement, .overflow = .wrap, .rounding = .exact },
            .v8f32 => .{ .domain = .real, .width = 32, .lanes = 8, .signed = true, .format = .ieee754_binary, .overflow = .ieee754, .rounding = .nearest_even },
            .v8i32 => .{ .domain = .integral, .width = 32, .lanes = 8, .signed = true, .format = .twos_complement, .overflow = .wrap, .rounding = .exact },
            .@"struct" => |s| if (nominal_reprs.get(s.name)) |repr| repr.numericFacts() else null,
            else => null,
        };
    }

    /// Project descriptor compatibility from the two fact sets. Null means this
    /// projection has no answer — either descriptor is not numeric, or the
    /// question is not the numeric facts' to answer. It never stands for
    /// rejection; the caller owns the default.
    ///
    /// law.nominal (§46) — A NOMINAL DESCRIPTOR HAS NO NUMERIC FACTS TO OFFER
    /// *THIS* QUESTION. `numericFacts` delegates `feet` to the double behind it
    /// deliberately, because every PHYSICAL query — `narrowFit`, `is_float`,
    /// ARC, rendering — is a question about the representation. Acceptance is
    /// not one of those: it is a question about IDENTITY, and answering it from
    /// the representation is precisely the shortcut that makes `feet`
    /// decorative.
    ///
    /// The guard lives HERE, beside the derivation, rather than at each
    /// consumer — because a consumer has to REMEMBER it and one already forgot.
    /// `sema` refused `d: feet = x` at the top level and then admitted
    /// `d: ?feet = x` and `d: result[feet, str] = x`, since neither `?feet` nor
    /// `result[feet, str]` is itself nominal and the guard only ever looked at
    /// the outer descriptor. One derivation, asked by every wrapper, is the
    /// only shape of this rule that a new wrapper cannot reopen.
    pub fn numericAcceptsDescriptor(self: ResolvedType, supplied: ResolvedType) ?bool {
        if (nominalReprOf(self) != null or nominalReprOf(supplied) != null) return null;
        const demand = self.numericFacts() orelse return null;
        const value = supplied.numericFacts() orelse return null;
        return demand.acceptsDescriptor(value);
    }

    /// Whether `self` widens without loss into `new_t`. Null means this
    /// projection has no answer — one side is not numeric — and never stands
    /// for rejection; the caller owns the non-numeric widenings (`str` → `any`)
    /// and the non-widening default.
    ///
    /// DERIVED, NOT TABULATED — the widening lattice this replaced was a
    /// per-tag switch that restated numeric containment a fourth time beside
    /// `numericFacts`, `narrowFit` and `acceptsDescriptor`. Unlike acceptance,
    /// widening delegates a nominal descriptor to its representation on purpose:
    /// a C field migration casts the physical value, so a place over a
    /// nominal-over-`i32` widens exactly as `i32` (`law.nominal` §46, the same
    /// delegation `narrowFit` and `c_type` already make). The equal-descriptor
    /// case is the caller's, ahead of this call, because two identical
    /// descriptors are a COPY, not a widening.
    pub fn widensTo(self: ResolvedType, new_t: ResolvedType) ?bool {
        const from = self.numericFacts() orelse return null;
        const to = new_t.numericFacts() orelse return null;
        return from.widensTo(to);
    }

    pub fn is_integer(self: ResolvedType) bool {
        const facts = self.numericFacts() orelse return false;
        return facts.domain == .integral;
    }

    pub fn is_float(self: ResolvedType) bool {
        const facts = self.numericFacts() orelse return false;
        return facts.domain == .real;
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

/// Element storage for the GAP-145 byte-sequence descriptor (`law.text.byte`).
var quoted_byte_sequence_elem: ResolvedType = .u8;

/// Resolved descriptor for a quoted literal from its producer quote identity.
/// Text faces remain `.str`; the byte-sequence face is a dynamic `[u8]`-shaped
/// value, not a collapsed text identity.
pub fn quotedLiteralType(quote: ast.Quote) ResolvedType {
    if (ast.quotedLiteralIsByteSequence(quote)) {
        return .{ .array = .{ .elem = &quoted_byte_sequence_elem, .size = null } };
    }
    return .str;
}

/// Does this resolved descriptor CARRY the byte-sequence face?
///
/// The shape belongs to `quotedLiteralType` above and is asked of it here, so a
/// consumer never spells `elem == .u8 and size == null` for itself. A consumer
/// that restates the shape is a second answer to `law.text.byte`, and the one
/// this repairs (`src/dnir_lower.zig`) had been answering the question by
/// ELIMINATION — "not f64, not str, not a pointer, therefore an integer" — over
/// a `const char*`.
pub fn isQuotedByteSequence(descriptor: ResolvedType) bool {
    return quotedLiteralType(.bytes).eql(descriptor);
}

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
            // A DECLARED DESCRIPTOR OUTRANKS THE LETTER HEURISTIC.
            //
            // Single uppercase letters are type parameters (`Tensor[M, K, f32]`),
            // and that convention is worth keeping — but it was being applied
            // BEFORE the module's own declarations were consulted, so a name the
            // program DECLARED was overruled by how it happened to be spelled.
            //
            // MEASURED before this: `R: { a: i64, b: i64 }` with `mk: R = (n)`
            // resolved `R` to `generic_param` — which `c_type` spells
            // `"lua_Value"`, the box every ruling in this tree forbids — and the
            // program was refused `DNB011 application-result-abi`, a diagnostic
            // that never mentions the name. `point: {…}` with `mk: point = (n)`
            // answered 100. Same program, one letter apart, two different
            // meanings, and the lowercase branch returned `.any` — also not the
            // record — so lowercasing alone did not repair it.
            //
            // LAW-16 makes a one-letter UPPERCASE descriptor a naming violation,
            // so the corpus should not contain one; that is a separate ratchet
            // (`gate/design.sh`). This is the semantic half: a lexical heuristic
            // must not outrank a declaration. C0 §19 — do not create identity
            // from source spelling.
            if (n.len == 1) {
                const declared = if (sema) |s| blk: {
                    const sema_mod = @import("sema.zig");
                    const sema_ptr: *const sema_mod.Sema = @ptrCast(@alignCast(s));
                    break :blk sema_ptr.alias_defs.contains(n) or
                        sema_ptr.foreign_records.contains(n) or
                        sema_ptr.enum_types.contains(n);
                } else false;
                if (!declared) {
                    const c = n[0];
                    if (c >= 'A' and c <= 'Z') {
                        return ResolvedType{ .generic_param = .{ .name = n, .constraint = null } };
                    }
                    if (c >= 'a' and c <= 'z') {
                        return .any;
                    }
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

/// Compile-time-observable facts projected from a call site. This is legacy
/// specialization input, not semantic identity; a resolved application keeps
/// its exact graph entity instead.
pub const CallShape = struct {
    /// How the callee is referenced
    callee_kind: CalleeKind,
    /// Source delimiter provenance. It never participates in semantic
    /// equality or specialization candidate fingerprints.
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

    /// Derived acceleration for specialization candidate retrieval and
    /// provenance. Every candidate still requires exact fact comparison.
    pub fn fingerprint(self: CallShape) u64 {
        var h = std.hash.Wyhash.init(0xCA115A9E);
        h.update(std.mem.asBytes(&self.callee_kind));
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

    /// Physical bridge for the remaining codegen provenance consumer. Delete
    /// with its three `identityHash` call sites; this value never owns meaning.
    pub fn identityHash(self: CallShape) u64 {
        return self.fingerprint();
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

    fn optionalTextEql(a: ?[]const u8, b: ?[]const u8) bool {
        if (a == null or b == null) return a == null and b == null;
        return std.mem.eql(u8, a.?, b.?);
    }

    /// Exact specialization-fact comparison. Delimiter form is provenance;
    /// fingerprints may retrieve candidates but cannot make this decision.
    pub fn eql(a: CallShape, b: CallShape) bool {
        return a.callee_kind == b.callee_kind and
            optionalTextEql(a.callee_name, b.callee_name) and
            optionalTextEql(a.method_name, b.method_name) and
            a.arg_count == b.arg_count and
            a.known_args_mask == b.known_args_mask and
            a.typed_args_mask == b.typed_args_mask and
            a.has_varargs == b.has_varargs and
            a.return_consumption == b.return_consumption and
            a.receiver_shape_known == b.receiver_shape_known;
    }
};

/// Classify return consumption from assignment target count (§6).
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

/// Derived call-shape fingerprint (convenience wrapper).
pub fn callShapeFingerprint(shape: CallShape) u64 {
    return shape.fingerprint();
}

// ── CallShape Tests ──────────────────────────────────────────────────────────

test "CallShape: delimiter provenance does not change specialization facts" {
    const paren = CallShape{ .callee_kind = .direct, .callee_name = "f", .arg_count = 1, .invocation_form = .parenthesized };
    const plain = CallShape{ .callee_kind = .direct, .callee_name = "f", .arg_count = 1, .invocation_form = .parenless };
    try testing.expectEqual(paren.fingerprint(), plain.fingerprint());
    try testing.expect(CallShape.eql(paren, plain));
}

test "CallShape: direct call fingerprint is stable" {
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
    try testing.expectEqual(a.fingerprint(), b.fingerprint());
    try testing.expect(CallShape.eql(a, b));
}

test "CallShape: exact facts reject different argument counts" {
    const a = CallShape{ .callee_kind = .direct, .callee_name = "f", .arg_count = 1 };
    const b = CallShape{ .callee_kind = .direct, .callee_name = "f", .arg_count = 2 };
    try testing.expect(!CallShape.eql(a, b));
}

test "CallShape: equal fingerprints cannot select semantic facts" {
    const a = CallShape{
        .callee_kind = .direct,
        .callee_name = "ab",
        .method_name = "c",
        .arg_count = 1,
    };
    const b = CallShape{
        .callee_kind = .direct,
        .callee_name = "a",
        .method_name = "bc",
        .arg_count = 1,
    };
    try testing.expectEqual(a.fingerprint(), b.fingerprint());
    try testing.expect(!CallShape.eql(a, b));
}

test "numeric descriptor facts compose domain width sign format and range" {
    const signed_type: ResolvedType = .i32;
    const signed = signed_type.numericFacts().?;
    try testing.expectEqual(NumericFacts.Domain.integral, signed.domain);
    try testing.expectEqual(@as(u7, 32), signed.width);
    try testing.expectEqual(@as(u8, 1), signed.lanes);
    try testing.expect(signed.signed);
    try testing.expectEqual(NumericFacts.Format.twos_complement, signed.format);
    try testing.expectEqual(NumericFacts.Overflow.wrap, signed.overflow);
    try testing.expectEqual(NumericFacts.Rounding.exact, signed.rounding);
    try testing.expectEqual(@as(i64, -2147483648), signed.range.?.min);
    try testing.expectEqual(@as(i64, 2147483647), signed.range.?.max);

    const float_type: ResolvedType = .f32;
    const float = float_type.numericFacts().?;
    try testing.expectEqual(NumericFacts.Domain.real, float.domain);
    try testing.expectEqual(@as(u7, 32), float.width);
    try testing.expectEqual(NumericFacts.Format.ieee754_binary, float.format);
    try testing.expectEqual(NumericFacts.Overflow.ieee754, float.overflow);
    try testing.expectEqual(NumericFacts.Rounding.nearest_even, float.rounding);
    try testing.expect(float.range == null);

    const vector_type: ResolvedType = .v8i32;
    const vector = vector_type.numericFacts().?;
    try testing.expectEqual(NumericFacts.Domain.integral, vector.domain);
    try testing.expectEqual(@as(u7, 32), vector.width);
    try testing.expectEqual(@as(u8, 8), vector.lanes);

    const unsigned_type: ResolvedType = .u64;
    const unsigned = unsigned_type.numericFacts().?;
    try testing.expect(!unsigned.signed);
    try testing.expect(unsigned.range == null);
    const text_type: ResolvedType = .str;
    try testing.expect(text_type.numericFacts() == null);

    try testing.expect(signed.acceptsSource(.integral));
    try testing.expect(!signed.acceptsSource(.real));
    try testing.expect(float.acceptsSource(.integral));
    try testing.expect(float.acceptsSource(.real));

    try testing.expect(signed.acceptsDescriptor(unsigned));
    try testing.expect(float.acceptsDescriptor((ResolvedType{ .f32 = {} }).numericFacts().?));
    try testing.expect(!signed.acceptsDescriptor(float));
    try testing.expect(!float.acceptsDescriptor(signed));

    try testing.expectEqual(true, signed_type.numericAcceptsDescriptor(.u64).?);
    try testing.expectEqual(false, signed_type.numericAcceptsDescriptor(.f64).?);
    try testing.expect(signed_type.numericAcceptsDescriptor(.str) == null);
}

test "types: a nominal descriptor delegates its physics and withholds its acceptance" {
    // NOT AN ARENA — `declareNominal` writes a process-global map keyed by text
    // that outlives this test, so an arena leaves it holding a freed store.
    const alloc = std.heap.page_allocator;
    try declareNominal(alloc, "league", .f64);
    const league = nominalNamed("league").?;

    // PHYSICAL queries delegate, and must keep delegating: this is what lets
    // `d:floor()` resolve and what `narrowFit`/ARC/rendering all read.
    try testing.expectEqual(NumericFacts.Domain.real, league.numericFacts().?.domain);
    try testing.expect(league.is_float());

    // ACCEPTANCE does not. Null is "not this projection's question", which is
    // the answer the caller turns into a refusal — in both directions, and
    // through any wrapper that composes this one derivation.
    try testing.expect(league.numericAcceptsDescriptor(.f64) == null);
    try testing.expect((ResolvedType{ .f64 = {} }).numericAcceptsDescriptor(league) == null);
    try testing.expect(league.numericAcceptsDescriptor(league) == null);

    // Ordinary descriptors are untouched by the guard.
    try testing.expectEqual(true, (ResolvedType{ .f64 = {} }).numericAcceptsDescriptor(.f32).?);
}

test "types: the write projection is derived from the facts so a descriptor inherits it" {
    // Every non-nominal answer is what the retired tag table answered, so no
    // program on the scalar path can gain or lose an instruction from this.
    try testing.expectEqual(@as(u7, 8), (ResolvedType{ .i8 = {} }).narrowFit().?.bits);
    try testing.expect((ResolvedType{ .i8 = {} }).narrowFit().?.signed);
    try testing.expectEqual(@as(u7, 16), (ResolvedType{ .i16 = {} }).narrowFit().?.bits);
    try testing.expectEqual(@as(u7, 32), (ResolvedType{ .i32 = {} }).narrowFit().?.bits);
    try testing.expect((ResolvedType{ .i32 = {} }).narrowFit().?.signed);
    try testing.expectEqual(@as(u7, 8), (ResolvedType{ .u8 = {} }).narrowFit().?.bits);
    try testing.expect(!(ResolvedType{ .u8 = {} }).narrowFit().?.signed);
    try testing.expectEqual(@as(u7, 16), (ResolvedType{ .u16 = {} }).narrowFit().?.bits);
    try testing.expectEqual(@as(u7, 32), (ResolvedType{ .u32 = {} }).narrowFit().?.bits);
    try testing.expect(!(ResolvedType{ .u32 = {} }).narrowFit().?.signed);

    // Already the register width: a fit here would be a wasted instruction on
    // the i64 path.
    try testing.expect((ResolvedType{ .i64 = {} }).narrowFit() == null);
    try testing.expect((ResolvedType{ .u64 = {} }).narrowFit() == null);
    // Real, and not integral, so no truncation ring exists.
    try testing.expect((ResolvedType{ .f32 = {} }).narrowFit() == null);
    try testing.expect((ResolvedType{ .f64 = {} }).narrowFit() == null);
    // `lanes` is why width alone cannot decide: `v8i32` carries width 32 and is
    // not a narrow scalar place.
    try testing.expect((ResolvedType{ .v8i32 = {} }).narrowFit() == null);
    try testing.expect((ResolvedType{ .v4i64 = {} }).narrowFit() == null);
    try testing.expect((ResolvedType{ .str = {} }).narrowFit() == null);
    try testing.expect((ResolvedType{ .bool = {} }).narrowFit() == null);
    try testing.expect((ResolvedType{ .any = {} }).narrowFit() == null);

    // THE REPAIR. `c_type` already delegates a nominal descriptor to its
    // representation, so a place declared over `tick` reached the C emitter as
    // `int32_t` and truncated while the tag table left `dnir_lower` and
    // `native_backend` with no fit at all — two realizations of one
    // descriptor's write projection, disagreeing.
    const alloc = std.heap.page_allocator; // process-global map; see above
    try declareNominal(alloc, "tick", .i32);
    const tick = nominalNamed("tick").?;
    try testing.expectEqual(@as(u7, 32), tick.narrowFit().?.bits);
    try testing.expect(tick.narrowFit().?.signed);
    try testing.expectEqual(@as(i64, -2147483648), narrowFitConst(2147483648, tick));

    var cbuf: [64]u8 = undefined;
    try testing.expectEqualStrings("int32_t", tick.c_type(&cbuf));

    // A nominal descriptor over a full-width or real representation inherits
    // the absence just as exactly.
    try declareNominal(alloc, "stamp", .i64);
    try testing.expect(nominalNamed("stamp").?.narrowFit() == null);
    try declareNominal(alloc, "furlong", .f64);
    try testing.expect(nominalNamed("furlong").?.narrowFit() == null);

    // Identity is still withheld: inheriting the physics is not accepting the
    // representation.
    try testing.expect(tick.numericAcceptsDescriptor(.i32) == null);
}

test "types: the annotation face of the write projection is derived from the same facts" {
    // EVERY payload-free descriptor identity answers to its own tag name, and
    // this control is written over the union's tags rather than over a list, so
    // a scalar identity added above cannot be one the annotation face does not
    // know. A payload-carrying identity is refused: `array` is a composition.
    const Tag = @typeInfo(ResolvedType).@"union".tag_type.?;
    const info = @typeInfo(ResolvedType).@"union";
    inline for (info.field_names, info.field_types) |field_name, field_type| {
        const named = descriptorNamed(field_name);
        if (field_type == void) {
            try testing.expect(named != null);
            try testing.expectEqual(@field(Tag, field_name), @as(Tag, named.?));
        } else {
            try testing.expect(named == null);
        }
    }

    // PINNED EQUAL TO THE RETIRED NAME ROSTER on every spelling it listed, so
    // no program on the scalar annotation path can gain or lose a truncation.
    try testing.expectEqual(ResolvedType.u8, narrowIntOfType(.{ .named = "u8" }).?);
    try testing.expectEqual(ResolvedType.u16, narrowIntOfType(.{ .named = "u16" }).?);
    try testing.expectEqual(ResolvedType.u32, narrowIntOfType(.{ .named = "u32" }).?);
    try testing.expectEqual(ResolvedType.i8, narrowIntOfType(.{ .named = "i8" }).?);
    try testing.expectEqual(ResolvedType.i16, narrowIntOfType(.{ .named = "i16" }).?);
    try testing.expectEqual(ResolvedType.i32, narrowIntOfType(.{ .named = "i32" }).?);

    // And equal on everything it declined. `i64`/`u64` are the register width,
    // the reals have no truncation ring, and `lanes` keeps `v8i32` off the
    // scalar place path even though it carries width 32.
    try testing.expect(narrowIntOfType(.{ .named = "i64" }) == null);
    try testing.expect(narrowIntOfType(.{ .named = "u64" }) == null);
    try testing.expect(narrowIntOfType(.{ .named = "f32" }) == null);
    try testing.expect(narrowIntOfType(.{ .named = "f64" }) == null);
    try testing.expect(narrowIntOfType(.{ .named = "v8i32" }) == null);
    try testing.expect(narrowIntOfType(.{ .named = "bool" }) == null);
    try testing.expect(narrowIntOfType(.{ .named = "str" }) == null);
    try testing.expect(narrowIntOfType(.{ .named = "any" }) == null);
    try testing.expect(narrowIntOfType(.{ .named = "void" }) == null);
    try testing.expect(narrowIntOfType(.{ .named = "Missing" }) == null);
    try testing.expect(narrowIntOfType(.inferred) == null);
    var elem: ResolvedType = .i32;
    _ = &elem;
    try testing.expect(narrowIntOfType(.{ .array = .{
        .elem = @constCast(&ast.TypeExpr{ .named = "i32" }),
        .size = 4,
    } }) == null);

    // THE REPAIR. The annotation face and `narrowFit` now answer one question
    // from one derivation, so a nominal-over-narrow place carries its width
    // into `dnir_lower` and `comptime` instead of only into `c_type`.
    const alloc = std.heap.page_allocator; // process-global map; see above
    try declareNominal(alloc, "beat", .i32);
    try testing.expectEqual(ResolvedType.i32, narrowIntOfType(.{ .named = "beat" }).?);
    try testing.expectEqual(
        nominalNamed("beat").?.narrowFit().?.bits,
        narrowIntOfType(.{ .named = "beat" }).?.narrowFit().?.bits,
    );
    try testing.expectEqual(@as(i64, -2147483648), narrowFitConst(
        2147483648,
        narrowIntOfType(.{ .named = "beat" }).?,
    ));

    // A nominal descriptor inherits the ABSENCE just as exactly, and a nominal
    // name is still not a scalar identity.
    try declareNominal(alloc, "epoch", .i64);
    try testing.expect(narrowIntOfType(.{ .named = "epoch" }) == null);
    try declareNominal(alloc, "chain", .f64);
    try testing.expect(narrowIntOfType(.{ .named = "chain" }) == null);
    try testing.expect(descriptorNamed("beat").? == .@"struct");
}

// The retired memory-level roster, verbatim, as the oracle. It existed TWICE —
// `sema.mem_type_from_name` deciding which memory type names are ADMITTED, and
// `codegen.mem_type_from_name` deciding what each one REALIZES AS — from two
// hand-kept lists that could only ever agree by hand. This is the `sema` copy,
// which is the one with no nominal tail; `codegen`'s nominal tail belonged to
// the `v:to(T)` conversion consumer and is composed there on top of the derived
// face.
fn retiredMemTypeFromName(alloc: std.mem.Allocator, name: []const u8) !?ResolvedType {
    if (name.len == 0) return null;
    if (name[0] == '*') {
        const inner = try retiredMemTypeFromName(alloc, name[1..]) orelse return null;
        const ptr = try alloc.create(ResolvedType);
        ptr.* = inner;
        return ResolvedType{ .pointer = ptr };
    }
    if (std.mem.eql(u8, name, "void")) return .void;
    if (std.mem.eql(u8, name, "i8")) return .i8;
    if (std.mem.eql(u8, name, "i16")) return .i16;
    if (std.mem.eql(u8, name, "i32")) return .i32;
    if (std.mem.eql(u8, name, "i64") or std.mem.eql(u8, name, "isize")) return .i64;
    if (std.mem.eql(u8, name, "u8")) return .u8;
    if (std.mem.eql(u8, name, "u16")) return .u16;
    if (std.mem.eql(u8, name, "u32")) return .u32;
    if (std.mem.eql(u8, name, "u64") or std.mem.eql(u8, name, "usize")) return .u64;
    if (std.mem.eql(u8, name, "f32")) return .f32;
    if (std.mem.eql(u8, name, "f64")) return .f64;
    if (std.mem.eql(u8, name, "bool")) return .bool;
    if (std.mem.eql(u8, name, "str") or std.mem.eql(u8, name, "string")) return .str;
    if (std.mem.eql(u8, name, "ptr") or std.mem.eql(u8, name, "void*")) {
        const ptr = try alloc.create(ResolvedType);
        ptr.* = .void;
        return ResolvedType{ .pointer = ptr };
    }
    return null;
}

test "types: the memory-level face is derived from the same facts and owned once" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // PINNED EQUAL TO THE RETIRED ROSTER on every spelling it listed AND every
    // spelling it declined, so no memory level can gain or lose a type from
    // this. The declined half carries the load: the derivation reaches
    // `descriptorNamed`, which answers for identities the roster never listed,
    // and `scalarRepr` is what refuses them — `any` is boxed and opaque, `nil`
    // and `never` are not values in cells, and the vector identities are
    // numeric fact owners spanning several cells, not one.
    const spellings = [_][]const u8{
        // listed: scalars, the untyped cell, and the legacy spellings
        "void",  "i8",     "i16",    "i32",    "i64",     "isize",
        "u8",    "u16",    "u32",    "u64",    "usize",   "f32",
        "f64",   "bool",   "str",    "string",
        // listed: pointer compositions, which compose over the same face
         "ptr",     "void*",
        "*i32",  "*u8",    "*bool",  "*str",   "**i64",   "*ptr",
        "*void", "*isize",
        // declined: numeric fact owners and non-representational identities
          "any",     "nil",
        "never", "v4f64",  "v4i64",  "v8f32",  "v8i32",   "*any",
        "*v4f64",
        // declined: payload-carrying identities, whose source spelling is a
        // composition and not a bare word
        "array",  "pointer", "func",   "struct", "result",
        "option", "table",  "foreign",
        // declined: foreign spellings, the empty name, a bare star, unknowns
         "int32_t", "double", "float",   "",
        "*",     "*",      "nosuch", "*nosuch",
    };
    for (spellings) |name| {
        const retired = try retiredMemTypeFromName(alloc, name);
        const derived = try memDescriptorNamed(alloc, name);
        if (retired) |want| {
            try testing.expect(derived != null);
            try testing.expect(want.eql(derived.?));
        } else {
            try testing.expect(derived == null);
        }
    }

    // A NOMINAL DESCRIPTOR IS NOT A MEMORY LEVEL, which is the retired
    // divergence made explicit: `sema` refused one and `codegen` accepted one,
    // from the same duplicated roster, because `codegen`'s copy also answered
    // the result type of `v:to(inch)`. The conversion consumer keeps that tail;
    // the memory level does not have it.
    //
    // NOT AN ARENA for the declaration — `declareNominal` writes a
    // process-global map keyed by text that outlives this test.
    try declareNominal(std.heap.page_allocator, "fathom", .f64);
    try testing.expect(nominalNamed("fathom") != null);
    try testing.expect((try memDescriptorNamed(alloc, "fathom")) == null);
    try testing.expect((try retiredMemTypeFromName(alloc, "fathom")) == null);
    // Its PHYSICS still delegates, so refusing it here is an identity ruling
    // and not a claim that it has no representation.
    try testing.expect(nominalNamed("fathom").?.numericFacts() != null);

    // `scalarRepr` is the one owner both questions ask, and it is derived from
    // `numericFacts` rather than tabulated: this control is written over the
    // union's own tags, so a scalar identity added above cannot be one the
    // memory level or the nominal-target rule silently does not know.
    const info = @typeInfo(ResolvedType).@"union";
    inline for (info.field_names, info.field_types) |field_name, field_type| {
        if (field_type != void) continue;
        const identity = @as(ResolvedType, @field(ResolvedType, field_name));
        // Retired twelve-tag switch, verbatim.
        const want = switch (identity) {
            .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .f32, .f64, .bool, .str => true,
            else => false,
        };
        try testing.expectEqual(want, scalarRepr(identity));
        try testing.expectEqual(want, nominalReprAdmissible(identity));
        // Every scalar identity is a memory level under its own tag name, and
        // `void` is the one non-scalar that is: an untyped cell.
        const level = try memDescriptorNamed(alloc, field_name);
        try testing.expectEqual(want or identity == .void, level != null);
    }
}

// The retired ABI scalar-label roster, verbatim, as the oracle. It stood in
// `abi_specialize.isNativeScalarLabel` and decided, at the foreign ingress seam,
// whether a record has a native layout and whether a parameter is passed by
// value or by pointer.
fn retiredIsNativeScalarLabel(label: []const u8) bool {
    return std.mem.eql(u8, label, "f64") or
        std.mem.eql(u8, label, "f32") or
        std.mem.eql(u8, label, "i64") or
        std.mem.eql(u8, label, "i32") or
        std.mem.eql(u8, label, "i16") or
        std.mem.eql(u8, label, "i8") or
        std.mem.eql(u8, label, "u64") or
        std.mem.eql(u8, label, "u32") or
        std.mem.eql(u8, label, "u16") or
        std.mem.eql(u8, label, "u8") or
        std.mem.eql(u8, label, "bool") or
        std.mem.eql(u8, label, "double") or
        std.mem.eql(u8, label, "float");
}

test "types: the realization face of the scalar roster is derived from the same facts" {
    // PINNED EQUAL TO THE RETIRED ROSTER on every label it listed AND every
    // label it declined, so no foreign record layout and no pass-by decision
    // can change from this. The declined half carries the load: the derivation
    // reaches `descriptorNamed`, which answers for identities the roster never
    // listed, and `scalarRepr` plus the `str` subtraction are what refuse them.
    const labels = [_][]const u8{
        // listed: the eleven scalar identities and the two C spellings
        "i8",     "i16",     "i32",   "i64",    "u8",      "u16",
        "u32",    "u64",     "f32",   "f64",    "bool",    "double",
        "float",
        // declined: scalar-adjacent identities that are not register values
              "str",     "void",  "any",    "nil",     "never",
        // declined: numeric fact owners spanning several registers
        "v4f64",  "v4i64",   "v8f32", "v8i32",
        // declined: payload-carrying identities, whose source spelling is a
        // composition and not a bare word
                                              "array",   "pointer",
        "func",   "struct",  "result", "option", "table_type",
        // declined: legacy and foreign spellings this face does not own, the
        // empty name, a pointer spelling, and unknowns
        "isize",  "usize",   "string", "int32_t", "long",  "char",
        "",       "i32*",    "*i32",   "ptr",     "void*", "nosuch",
    };
    for (labels) |label| {
        try testing.expectEqual(
            retiredIsNativeScalarLabel(label),
            abiDescriptorNamed(label) != null,
        );
    }

    // The label projects the DESCRIPTOR, not a boolean, so the seam that decides
    // pass-by can read the facts it is deciding from. A roster could only ever
    // answer yes or no.
    try testing.expect(abiDescriptorNamed("double").?.eql(.f64));
    try testing.expect(abiDescriptorNamed("float").?.eql(.f32));
    try testing.expectEqual(@as(u7, 16), abiDescriptorNamed("u16").?.numericFacts().?.width);

    // A NOMINAL DESCRIPTOR IS NOT AN ABI LABEL. It is an identity, not a
    // representation, and admitting one here would let a foreign field named
    // after a declared descriptor claim a native layout it was never checked
    // for. Its PHYSICS still delegates, so this is an identity ruling.
    //
    // NOT AN ARENA — `declareNominal` writes a process-global map keyed by text.
    try declareNominal(std.heap.page_allocator, "furlong", .i32);
    try testing.expect(nominalNamed("furlong") != null);
    try testing.expect(abiDescriptorNamed("furlong") == null);
    try testing.expect(!retiredIsNativeScalarLabel("furlong"));
    try testing.expect(nominalNamed("furlong").?.numericFacts() != null);

    // Written over the union's own tags rather than over a list, so a scalar
    // identity added above cannot be one the ABI face silently does not know.
    // `str` is the one scalar this face subtracts, and it subtracts it for a
    // stated reason rather than by omission.
    const info = @typeInfo(ResolvedType).@"union";
    inline for (info.field_names, info.field_types) |field_name, field_type| {
        if (field_type != void) continue;
        const identity = @as(ResolvedType, @field(ResolvedType, field_name));
        const want = scalarRepr(identity) and identity != .str;
        try testing.expectEqual(want, abiDescriptorNamed(field_name) != null);
        try testing.expectEqual(want, retiredIsNativeScalarLabel(field_name));
    }
}

// The retired C-spelling roster, verbatim, as the oracle. It stood in
// `codegen.type_from_c_name` and decided, at the foreign ingress seam, which
// `ResolvedType` identity a C type spelling realizes. It was the SEVENTH
// statement of the scalar identity↔spelling correspondence and the one that ran
// backwards from `c_type`.
fn retiredTypeFromCName(name: []const u8) ?ResolvedType {
    if (std.mem.eql(u8, name, "int8_t")) return .i8;
    if (std.mem.eql(u8, name, "int16_t")) return .i16;
    if (std.mem.eql(u8, name, "int32_t")) return .i32;
    if (std.mem.eql(u8, name, "int64_t")) return .i64;
    if (std.mem.eql(u8, name, "uint8_t")) return .u8;
    if (std.mem.eql(u8, name, "uint16_t")) return .u16;
    if (std.mem.eql(u8, name, "uint32_t")) return .u32;
    if (std.mem.eql(u8, name, "uint64_t")) return .u64;
    if (std.mem.eql(u8, name, "float")) return .f32;
    if (std.mem.eql(u8, name, "double")) return .f64;
    if (std.mem.eql(u8, name, "bool")) return .bool;
    if (std.mem.eql(u8, name, "const char*")) return .str;
    return null;
}

test "types: the C-spelling face of the scalar roster is derived from the same facts" {
    // PINNED EQUAL TO THE RETIRED ROSTER on every spelling it listed AND every
    // spelling it declined, so no foreign ingress site can gain or lose an
    // identity from this. The retired roster's scalar arm is the whole of what
    // `descriptorByCSpelling` owns; the graveyarded/pointer/void spellings that
    // used to fall through to the memory level are still the memory level's and
    // are declined HERE by the same `scalarRepr` fact `abiDescriptorNamed` uses.
    const spellings = [_][]const u8{
        // listed: the twelve scalar C spellings the roster mapped by hand
        "int8_t",  "int16_t", "int32_t", "int64_t", "uint8_t",  "uint16_t",
        "uint32_t", "uint64_t", "float",  "double",  "bool",    "const char*",
        // declined: spellings the roster fell through to the memory level for,
        // the C spellings of non-scalar identities, the empty name, unknowns
        "void",    "void*",   "lua_Value", "v4f64",  "v8i32",   "duo_furlong",
        "i32",     "isize",   "usize",   "string",  "",        "nosuch",
        "int8_t*", "*int32_t",
    };
    for (spellings) |name| {
        const retired = retiredTypeFromCName(name);
        const derived = descriptorByCSpelling(name);
        if (retired) |want| {
            try testing.expect(derived != null);
            try testing.expect(want.eql(derived.?));
        } else {
            try testing.expect(derived == null);
        }
    }

    // The face projects the SCALAR IDENTITY, and it is the exact inverse of
    // `c_type`: for every scalar identity, its C spelling round-trips back to
    // it. Written over the union's own tags rather than over a list, so a
    // scalar identity added above cannot be one this face silently does not
    // know. Every non-scalar identity is declined by that fact, not by absence.
    const info = @typeInfo(ResolvedType).@"union";
    inline for (info.field_names, info.field_types) |field_name, field_type| {
        if (field_type != void) continue;
        const identity = @as(ResolvedType, @field(ResolvedType, field_name));
        if (scalarRepr(identity)) {
            var buf: [32]u8 = undefined;
            const spelling = identity.c_type(&buf);
            const back = descriptorByCSpelling(spelling);
            try testing.expect(back != null);
            try testing.expect(identity.eql(back.?));
        }
    }

    // A NOMINAL DESCRIPTOR IS NOT A C SPELLING. Its bare word is not a C type
    // name at all (`c_type` emits `duo_<name>` or its representation), so the
    // ingress face never meets one; the `v:to(inch)` conversion tail that does
    // is composed by its consumer, not here.
    try declareNominal(std.heap.page_allocator, "cubit", .i32);
    try testing.expect(nominalNamed("cubit") != null);
    try testing.expect(descriptorByCSpelling("cubit") == null);
}

// The retired printf-specifier roster, verbatim, as the oracle. It stood TWICE
// in `codegen` — once in the `print` arm and once in the string-interpolation
// arm — each mapping a scalar's PHYSICAL representation to the C conversion
// specifier that renders it. The two copies agreed on every scalar and both
// answered `"%s"` for everything else (the interpolation copy spelled `bool`
// and `str` out; the print copy folded them into its `else`), so this single
// oracle stands for both.
fn retiredFormatSpec(repr: ResolvedType) []const u8 {
    return switch (repr) {
        .i8, .i16, .i32 => "%d",
        .i64 => "%lld",
        .u8, .u16, .u32 => "%u",
        .u64 => "%llu",
        .f32, .f64 => "%.17g",
        else => "%s",
    };
}

test "types: the rendering face of the scalar roster is derived from the same facts" {
    // PINNED EQUAL TO THE RETIRED ROSTER on every identity it mapped AND every
    // identity it folded into `else`, so no emitter site can gain or lose a
    // specifier from this. The caller keeps `"%s"` as its default for the null
    // answer, so `cFormatSpec(x) orelse "%s"` is `retiredFormatSpec(x)` for
    // every `x`: this is the exact substitution the two `codegen` sites made.
    const info = @typeInfo(ResolvedType).@"union";
    inline for (info.field_names, info.field_types) |field_name, field_type| {
        if (field_type != void) continue;
        const identity = @as(ResolvedType, @field(ResolvedType, field_name));
        const derived = cFormatSpec(identity) orelse "%s";
        try testing.expect(std.mem.eql(u8, derived, retiredFormatSpec(identity)));
    }

    // The specifier is the numeric owner's facts, not a fourth statement of
    // width and signedness: an integral scalar reads `signed`, a real scalar
    // reads `domain`, and the register-width `%lld`/`%llu` split reads
    // `width == 64`. Every scalar that carries facts answers a non-null
    // specifier; the two arithmetic-free scalars answer `"%s"`.
    try testing.expect(std.mem.eql(u8, cFormatSpec(.i16).?, "%d"));
    try testing.expect(std.mem.eql(u8, cFormatSpec(.u16).?, "%u"));
    try testing.expect(std.mem.eql(u8, cFormatSpec(.i64).?, "%lld"));
    try testing.expect(std.mem.eql(u8, cFormatSpec(.u64).?, "%llu"));
    try testing.expect(std.mem.eql(u8, cFormatSpec(.f32).?, "%.17g"));
    try testing.expect(std.mem.eql(u8, cFormatSpec(.bool).?, "%s"));
    try testing.expect(std.mem.eql(u8, cFormatSpec(.str).?, "%s"));

    // DECLINED BY A FACT, NOT BY ABSENCE. The vectors are numeric fact owners
    // that are not one cell (`lanes != 1`), and the boxed/void/composed
    // identities carry no facts and are not `bool`/`str`. Each answers null and
    // the caller's `"%s"` default renders it exactly as the retired `else` did.
    try testing.expect(cFormatSpec(.v4i64) == null);
    try testing.expect(cFormatSpec(.v8f32) == null);
    try testing.expect(cFormatSpec(.any) == null);
    try testing.expect(cFormatSpec(.void) == null);

    // A NOMINAL DESCRIPTOR RENDERS AS THE THING IT IS. Its facts delegate to
    // its representation on purpose (`law.nominal` §46), so a nominal-over-`i32`
    // takes `"%d"` — the exact repair the interpolation site's own comment
    // records against `feet`, where the retired `else` emitted `"%s"` on a
    // `double` and segfaulted. The `codegen` sites pass `nominalReprOf(t) orelse
    // t`, so the physical repr reaches this face; a bare nominal identity here
    // still answers through the same delegation.
    try declareNominal(std.heap.page_allocator, "tick", .i32);
    try testing.expect(std.mem.eql(u8, cFormatSpec(nominalNamed("tick").?).?, "%d"));
}

fn retiredCFrameType(t: ResolvedType) []const u8 {
    return switch (t) {
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
        .bool => "bool",
        .void => "void",
        .str => "const char*",
        else => "lua_Value",
    };
}

test "types: the async-frame face of the scalar roster is derived from the same facts" {
    // PINNED EQUAL TO THE RETIRED ROSTER on every identity it mapped AND every
    // identity it folded into `else`, so no async frame field can gain or lose a
    // C spelling from this. The caller keeps `lua_Value` as its default for the
    // null answer, so `cFrameType(x) orelse "lua_Value"` is `retiredCFrameType(x)`
    // for every `x`: this is the exact substitution `async_lower.cTypeName` made.
    const info = @typeInfo(ResolvedType).@"union";
    inline for (info.field_names, info.field_types) |field_name, field_type| {
        if (field_type != void) continue;
        const identity = @as(ResolvedType, @field(ResolvedType, field_name));
        const derived = cFrameType(identity) orelse "lua_Value";
        try testing.expect(std.mem.eql(u8, derived, retiredCFrameType(identity)));
    }

    // The spelling is `c_type` over the frame set, not an eighth statement of
    // it: every scalar plus `void` answers the exact spelling `c_type` emits.
    try testing.expect(std.mem.eql(u8, cFrameType(.i32).?, "int32_t"));
    try testing.expect(std.mem.eql(u8, cFrameType(.u64).?, "uint64_t"));
    try testing.expect(std.mem.eql(u8, cFrameType(.f32).?, "float"));
    try testing.expect(std.mem.eql(u8, cFrameType(.f64).?, "double"));
    try testing.expect(std.mem.eql(u8, cFrameType(.bool).?, "bool"));
    try testing.expect(std.mem.eql(u8, cFrameType(.void).?, "void"));
    try testing.expect(std.mem.eql(u8, cFrameType(.str).?, "const char*"));

    // DECLINED BY A FACT, NOT BY ABSENCE. `any` is already boxed, `nil`/`never`
    // are not frame values, the vectors span several cells (`lanes != 1`), and a
    // pointer/struct is a composition a frame field does not carry inline. Each
    // answers null and the caller's `lua_Value` default carries it exactly as the
    // retired `else` did.
    try testing.expect(cFrameType(.any) == null);
    try testing.expect(cFrameType(.nil) == null);
    try testing.expect(cFrameType(.never) == null);
    try testing.expect(cFrameType(.v4i64) == null);
    try testing.expect(cFrameType(.v8f32) == null);

    // A NOMINAL DESCRIPTOR IS NOT A REPRESENTATION, so it declines here and the
    // frame carries the boxed default — `scalarRepr` withholds a nominal identity
    // on purpose (`law.nominal` §46), exactly as it does for `abiDescriptorNamed`.
    try declareNominal(std.heap.page_allocator, "beat", .i32);
    try testing.expect(cFrameType(nominalNamed("beat").?) == null);
}

fn retiredReflectName(t: ResolvedType) []const u8 {
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
        .str => "str",
        .void => "void",
        .any => "any",
        .nil => "nil",
        .@"struct" => |s| s.name,
        else => "any",
    };
}

test "types: the reflection face of the scalar roster is derived from the same facts" {
    // PINNED EQUAL TO THE RETIRED ROSTER on every identity it mapped AND every
    // identity it folded into `else`, so no concept field row can gain or lose a
    // reported type word from this. The caller keeps `"any"` as its default for
    // the null answer, so `reflectName(x) orelse "any"` is `retiredReflectName(x)`
    // for every payload-free `x`: this is the exact substitution
    // `codegen.emit_resolved_type_name_string` made.
    const info = @typeInfo(ResolvedType).@"union";
    inline for (info.field_names, info.field_types) |field_name, field_type| {
        if (field_type != void) continue;
        const identity = @as(ResolvedType, @field(ResolvedType, field_name));
        const derived = reflectName(identity) orelse "any";
        try testing.expect(std.mem.eql(u8, derived, retiredReflectName(identity)));
    }

    // The word is `duo_name` over the reflection set, not a ninth statement of
    // it: every scalar reports its source spelling, and the three non-scalar
    // identities the reflection string names with their own word report it too.
    try testing.expect(std.mem.eql(u8, reflectName(.i32).?, "i32"));
    try testing.expect(std.mem.eql(u8, reflectName(.u64).?, "u64"));
    try testing.expect(std.mem.eql(u8, reflectName(.f64).?, "f64"));
    try testing.expect(std.mem.eql(u8, reflectName(.bool).?, "bool"));
    try testing.expect(std.mem.eql(u8, reflectName(.str).?, "str"));
    try testing.expect(std.mem.eql(u8, reflectName(.void).?, "void"));
    try testing.expect(std.mem.eql(u8, reflectName(.any).?, "any"));
    try testing.expect(std.mem.eql(u8, reflectName(.nil).?, "nil"));

    // DECLINED BY A FACT, NOT BY ABSENCE. The vectors are numeric fact owners
    // that are not one cell (`scalarRepr` is false because `lanes != 1`), `never`
    // is not a value, and a composed identity's `duo_name` builds a compound the
    // roster folded to `"any"`. Each answers null and the caller's `"any"`
    // default reports it exactly as the retired `else` did.
    try testing.expect(reflectName(.v4f64) == null);
    try testing.expect(reflectName(.v8i32) == null);
    try testing.expect(reflectName(.never) == null);

    // A STRUCT REPORTS ITS DECLARED NAME, the one payload the reflection roster
    // carried through — `duo_name` returns `s.name`, so the face names it
    // directly rather than folding it to `"any"`.
    try declareNominal(std.heap.page_allocator, "cadence", .i32);
    try testing.expect(std.mem.eql(u8, reflectName(nominalNamed("cadence").?).?, "cadence"));
}

/// The retired `mono.appendTypeName` scalar roster: the explicit arms that
/// mapped an identity directly to a bare mangle-fragment word, null for every
/// identity that fell to `appendSanitized`'s struct/enum/debug tail.
fn retiredMangleFragment(t: ResolvedType) ?[]const u8 {
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
        .str => "str",
        .any => "any",
        else => null,
    };
}

test "types: the mangling face of the scalar roster is derived from the same facts" {
    // PINNED EQUAL TO THE RETIRED ROSTER on every identity it mapped to a bare
    // word AND every identity it folded into the struct/enum/debug tail, so no
    // monomorphized specialization can gain or lose a name fragment from this.
    // The caller keeps its own sanitized-debug rendering for the null answer, so
    // `mangleFragment(x)` is the retired explicit arm for every payload-free `x`
    // and null exactly where the retired switch fell through to `else`.
    const info = @typeInfo(ResolvedType).@"union";
    inline for (info.field_names, info.field_types) |field_name, field_type| {
        if (field_type != void) continue;
        const identity = @as(ResolvedType, @field(ResolvedType, field_name));
        const derived = mangleFragment(identity);
        const retired = retiredMangleFragment(identity);
        if (retired) |word| {
            try testing.expect(derived != null);
            try testing.expect(std.mem.eql(u8, derived.?, word));
        } else {
            try testing.expect(derived == null);
        }
    }

    // The fragment is `duo_name` over the mangle set, not a tenth statement of
    // it: every scalar mangles to its own source word, and `any` — the one
    // non-numeric identity the roster carried — mangles to `any`.
    try testing.expect(std.mem.eql(u8, mangleFragment(.i8).?, "i8"));
    try testing.expect(std.mem.eql(u8, mangleFragment(.u32).?, "u32"));
    try testing.expect(std.mem.eql(u8, mangleFragment(.f64).?, "f64"));
    try testing.expect(std.mem.eql(u8, mangleFragment(.bool).?, "bool"));
    try testing.expect(std.mem.eql(u8, mangleFragment(.str).?, "str"));
    try testing.expect(std.mem.eql(u8, mangleFragment(.any).?, "any"));

    // Every mangle fragment is a valid C identifier fragment, so appending it
    // verbatim after `duo_` needs no sanitization — the property that lets the
    // scalar arms drop into one owner while struct/enum keep theirs.
    inline for (info.field_names, info.field_types) |field_name, field_type| {
        if (field_type != void) continue;
        const identity = @as(ResolvedType, @field(ResolvedType, field_name));
        if (mangleFragment(identity)) |word| {
            for (word) |ch| {
                const ok = (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9') or ch == '_';
                try testing.expect(ok);
            }
        }
    }

    // DECLINED BY A FACT, NOT BY ABSENCE. The vectors are numeric fact owners
    // that are not one cell (`scalarRepr` is false because `lanes != 1`), and
    // `void`/`nil`/`never` are not type arguments a specialization carries; each
    // answers null and the caller renders and sanitizes it exactly as the retired
    // `else` arm did.
    try testing.expect(mangleFragment(.v4f64) == null);
    try testing.expect(mangleFragment(.v8i32) == null);
    try testing.expect(mangleFragment(.void) == null);
    try testing.expect(mangleFragment(.nil) == null);
    try testing.expect(mangleFragment(.never) == null);
}

/// The retired per-tag widening lattice, verbatim, as the negative control's
/// oracle. It answers the NUMERIC arms only — the `str` → `any` arm was never
/// this projection's, it is the caller's non-numeric widening — so the derived
/// `ResolvedType.widensTo` (which returns null for a non-numeric side) is pinned
/// equal to it on every ordered pair of payload-free identities.
fn retiredNumericWidening(old_t: ResolvedType, new_t: ResolvedType) ?bool {
    return switch (old_t) {
        .i8 => new_t == .i16 or new_t == .i32 or new_t == .i64 or new_t == .f64,
        .i16 => new_t == .i32 or new_t == .i64 or new_t == .f64,
        .i32 => new_t == .i64 or new_t == .f64,
        .u8 => new_t == .u16 or new_t == .u32 or new_t == .u64 or new_t == .i64 or new_t == .f64,
        .u16 => new_t == .u32 or new_t == .u64 or new_t == .i64 or new_t == .f64,
        .u32 => new_t == .u64 or new_t == .i64 or new_t == .f64,
        .f32 => new_t == .f64,
        .i64, .u64, .f64 => false,
        else => null,
    };
}

test "types: the widening face of the scalar roster is derived from the same facts" {
    // PINNED EQUAL TO THE RETIRED LATTICE on every ORDERED PAIR of payload-free
    // identities — the pairs it declared widening AND the pairs it declined —
    // so no field migration can gain or lose a safe cast from this. The retired
    // lattice named only numeric sources; where it has a numeric answer, the
    // derived `widensTo` must equal it, and where a side is not numeric the
    // derived face returns null and the caller (`type_diff.isWidening`) owns the
    // default, which is exactly where the retired switch fell to `else`.
    @setEvalBranchQuota(20000);
    const info = @typeInfo(ResolvedType).@"union";
    inline for (info.field_names, info.field_types) |old_name, old_type| {
        if (old_type != void) continue;
        const old_t = @as(ResolvedType, @field(ResolvedType, old_name));
        inline for (info.field_names, info.field_types) |new_name, new_type| {
            if (new_type != void) continue;
            const new_t = @as(ResolvedType, @field(ResolvedType, new_name));
            const derived = old_t.widensTo(new_t);
            const both_numeric = old_t.numericFacts() != null and new_t.numericFacts() != null;
            if (both_numeric) {
                // Both sides numeric: the derived face must have an answer, and
                // it must equal the retired lattice bit for bit. The lattice
                // named the widening source arms explicitly and declined
                // `i64`/`u64`/`f64` (and the vectors) as sources; the derived
                // face declines them by the `lanes`/`width` fact, not by absence.
                const retired = retiredNumericWidening(old_t, new_t) orelse false;
                try testing.expect(derived != null);
                try testing.expectEqual(retired, derived.?);
            } else {
                // A non-numeric side: this projection has no answer and the
                // caller (`type_diff.isWidening`) owns the default, including the
                // `str` → `any` non-numeric widening. This is exactly where the
                // retired per-tag switch fell through to `else`.
                try testing.expect(derived == null);
            }
        }
    }

    // DERIVED, NOT TABULATED — the lattice is numeric containment over
    // `numericFacts`: a real widens to a strictly wider real, an integral
    // widens into the double, a same-sign integral widens to a strictly wider
    // one, and an unsigned integral additionally widens into the register-width
    // signed integral that dominates its range.
    try testing.expectEqual(@as(?bool, true), ResolvedType.widensTo(.i32, .i64));
    try testing.expectEqual(@as(?bool, true), ResolvedType.widensTo(.f32, .f64));
    try testing.expectEqual(@as(?bool, true), ResolvedType.widensTo(.u8, .i64));
    try testing.expectEqual(@as(?bool, true), ResolvedType.widensTo(.i8, .f64));

    // DECLINED BY A FACT, NOT BY ABSENCE. A signed source never crosses into
    // unsigned; a real never narrows into an integral; an unsigned source
    // reaches only the register-width signed integral, not a narrower one; and
    // the equal-descriptor case is a COPY, not a widening, so this projection
    // answers false and the caller short-circuits it ahead of the call.
    try testing.expectEqual(@as(?bool, false), ResolvedType.widensTo(.i8, .u16));
    try testing.expectEqual(@as(?bool, false), ResolvedType.widensTo(.f32, .i64));
    try testing.expectEqual(@as(?bool, false), ResolvedType.widensTo(.u8, .i16));
    try testing.expectEqual(@as(?bool, false), ResolvedType.widensTo(.i64, .i64));

    // A NOMINAL DESCRIPTOR DELEGATES its physical widening on purpose — a field
    // migration casts the value, and the C cast is over the representation
    // (`law.nominal` §46), the same delegation `narrowFit` and `c_type` make.
    // `str` → `any` stays the caller's non-numeric arm: the numeric owner has no
    // facts for either side, so `widensTo` returns null and `isWidening` owns it.
    try testing.expect(ResolvedType.widensTo(.str, .any) == null);
}

test "types: the field-cell face of the scalar roster is derived from the same facts" {
    // PINNED EQUAL TO THE RETIRED SWITCHES on every payload-free identity — the
    // scalars each one placed in a cell AND the vector, boxed, void and
    // composed identities they folded into `else` — iterated over the union's
    // own tags rather than a list, so a scalar identity added to the union
    // cannot be one the field-cell face silently does not know. Two functions
    // (`dnir_lower.graphFieldFact` and `dnir_lower.tableFieldKind`) shared this
    // partition; `retiredFieldCell` is their common non-width answer.
    const retiredFieldCell = struct {
        fn f(t: ResolvedType) ?ScalarFieldCell {
            return switch (t) {
                .str => .str,
                .f64 => .f64,
                .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .bool => .i64,
                else => null,
            };
        }
    }.f;
    const info = @typeInfo(ResolvedType).@"union";
    inline for (info.field_names, info.field_types) |name, ty| {
        if (ty != void) continue;
        const t = @as(ResolvedType, @field(ResolvedType, name));
        try testing.expectEqual(retiredFieldCell(t), scalarFieldCell(t));
    }

    // DERIVED, NOT TABULATED — a 64-bit real takes the double cell, an integral
    // or `bool` value the register-integer cell, and `str` the reference cell.
    // `f32` has NO native field cell: the retired switches listed only `f64`,
    // so `domain == .real` is not enough and `width == 64` is the test.
    try testing.expectEqual(@as(?ScalarFieldCell, .f64), scalarFieldCell(.f64));
    try testing.expectEqual(@as(?ScalarFieldCell, null), scalarFieldCell(.f32));
    try testing.expectEqual(@as(?ScalarFieldCell, .i64), scalarFieldCell(.i32));
    try testing.expectEqual(@as(?ScalarFieldCell, .i64), scalarFieldCell(.bool));
    try testing.expectEqual(@as(?ScalarFieldCell, .str), scalarFieldCell(.str));

    // DECLINED BY THE `scalarRepr` FACT, NOT BY ABSENCE: the vectors span
    // several cells, `any` is boxed, and `void`/`nil`/`never` are not field
    // values, so none of them is a scalar cell.
    try testing.expectEqual(@as(?ScalarFieldCell, null), scalarFieldCell(.v4i64));
    try testing.expectEqual(@as(?ScalarFieldCell, null), scalarFieldCell(.any));
    try testing.expectEqual(@as(?ScalarFieldCell, null), scalarFieldCell(.void));

    // A NOMINAL DESCRIPTOR IS WITHHELD, not delegated — the retired switches
    // listed only bare scalar tags, so a nominal-over-`i32` (a `.struct` tag)
    // fell to `else`, and `scalarRepr` withholds it identically. This is the
    // one physical field face where the nominal takes the caller's boxed row
    // rather than its representation's cell, matching the retired switch bit for
    // bit. Uses the process-global map with `page_allocator`, the pattern the
    // `narrowFit` nominal test above already established.
    const alloc = std.heap.page_allocator;
    try declareNominal(alloc, "tick", .i32);
    const nominal = nominalNamed("tick").?;
    try testing.expectEqual(@as(?ScalarFieldCell, null), scalarFieldCell(nominal));

    // Planting a vector widening in `scalarFieldCell` (via `scalarRepr`) is
    // refused by the `lanes != 1` fact: no non-scalar cell is invented here.
    try testing.expect(!scalarRepr(.v8i32));
}

test "types: the module-global-written narrow face is derived from the same facts" {
    // THE WRITTEN-MODULE-GLOBAL REFUSAL FACE — whether a written module global
    // is NARROWER THAN THE i64 WORD, the question `dnir_lower.lowerModuleFromGraph`
    // asks per global before it refuses `mod-global-written:` — is now derived
    // from the same owner. It stood there as a bare-tag switch
    // (`.i8,.i16,.i32,.u8,.u16,.u32 => refuse`, else keep) that restated which
    // integral scalars are narrower than the register word beside `narrowFit`,
    // `numericFacts` and every scalar-roster face above. A switch could not
    // compose: a scalar identity added to the union stayed unknown to the list,
    // took its `else` arm, and its written global kept full-word storage while
    // the mask path does not yet cover the declared width — an out-of-width
    // store admitted by absence, the wrong answer in the safe-looking direction.
    //
    // The composed predicate is `scalarRepr(t) and t.narrowFit() != null`:
    // `narrowFit` is non-null only for an integral, single-lane descriptor of
    // width < 64, and `scalarRepr` gates the nominal exactly as the retired
    // bare-tag switch did.
    const retiredNarrowGlobal = struct {
        fn f(t: ResolvedType) bool {
            return switch (t) {
                .i8, .i16, .i32, .u8, .u16, .u32 => true,
                else => false,
            };
        }
    }.f;
    const derivedNarrowGlobal = struct {
        fn f(t: ResolvedType) bool {
            return scalarRepr(t) and t.narrowFit() != null;
        }
    }.f;

    // PINNED EQUAL TO THE RETIRED SWITCH on every payload-free identity — the
    // six narrow integrals it refused AND the `i64`/`u64` (register width),
    // `f32`/`f64` (reals), `bool`/`str` (no numeric owner), vector, boxed, void
    // and composed identities it kept — iterated over the union's own tags
    // rather than a list, so a scalar identity added to the union cannot be one
    // the written-global face silently does not know.
    const info = @typeInfo(ResolvedType).@"union";
    inline for (info.field_names, info.field_types) |name, ty| {
        if (ty != void) continue;
        const t = @as(ResolvedType, @field(ResolvedType, name));
        try testing.expectEqual(retiredNarrowGlobal(t), derivedNarrowGlobal(t));
    }

    // DERIVED, NOT TABULATED — the six narrow integrals refuse; `i64`/`u64` are
    // already the register width and keep their storage; `f32` is real (a real
    // slot is not a masked integer write) and keeps it too, the one place
    // `width < 64` alone would over-refuse but `narrowFit`'s `domain` filter
    // does not.
    try testing.expect(derivedNarrowGlobal(.i8));
    try testing.expect(derivedNarrowGlobal(.u32));
    try testing.expect(!derivedNarrowGlobal(.i64));
    try testing.expect(!derivedNarrowGlobal(.u64));
    try testing.expect(!derivedNarrowGlobal(.f32));
    try testing.expect(!derivedNarrowGlobal(.f64));
    try testing.expect(!derivedNarrowGlobal(.bool));
    try testing.expect(!derivedNarrowGlobal(.v8i32));

    // A NOMINAL DESCRIPTOR IS WITHHELD, not delegated — the retired switch
    // listed only bare scalar tags, so a nominal-over-`i32` (a `.struct` tag)
    // fell to `else` and was NOT refused, and `scalarRepr` withholds it
    // identically even though its representation `narrowFit`s narrow. Uses the
    // process-global map with `page_allocator`, the pattern the field-cell test
    // above already established.
    const alloc = std.heap.page_allocator;
    try declareNominal(alloc, "beat", .i32);
    const nominal = nominalNamed("beat").?;
    try testing.expect(nominal.narrowFit() != null); // representation is narrow
    try testing.expect(!derivedNarrowGlobal(nominal)); // identity is withheld
}

test "types: the boxing face of the scalar roster is derived from the same facts" {
    // The retired boxing partition, verbatim, as the oracle. It stood at two
    // `codegen` per-tag SWITCHES that hand-listed all eight integral tags
    // (`.i8,.i16,.i32,.i64,.u8,.u16,.u32,.u64 => "lua_val_from_int(...)"`, reals
    // → `lua_val_from_num`, then `bool`/`str`) — one at a native module-call
    // return boundary and one at a native scalar-global export. This oracle is
    // the constructor OPEN each retired switch emitted for a scalar and null for
    // everything they folded into their box-less tail. It boxes an integral as
    // an integer, a real as a number, and the two arithmetic-free scalars as
    // themselves.
    const retiredBoxCtor = struct {
        fn f(t: ResolvedType) ?[]const u8 {
            return switch (t) {
                .str => "lua_val_from_str(",
                .bool => "lua_val_from_bool(",
                .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 => "lua_val_from_int((int64_t)",
                .f32, .f64 => "lua_val_from_num((double)",
                else => null,
            };
        }
    }.f;

    // PINNED EQUAL TO THE RETIRED PARTITION on every payload-free identity — the
    // four scalar box classes it named AND the vector, boxed, void and composed
    // identities it folded into its box-less tail — iterated over the union's
    // own tags rather than a list, so a scalar identity added to the union
    // cannot be one the boxing face silently does not know. `luaBoxClass(t)`
    // composed with `LuaBoxClass.ctor` is the retired constructor for every `t`.
    const info = @typeInfo(ResolvedType).@"union";
    inline for (info.field_names, info.field_types) |name, ty| {
        if (ty != void) continue;
        const t = @as(ResolvedType, @field(ResolvedType, name));
        const want = retiredBoxCtor(t);
        const got: ?[]const u8 = if (luaBoxClass(t)) |cls| cls.ctor() else null;
        if (want) |w| {
            try testing.expect(got != null);
            try testing.expect(std.mem.eql(u8, w, got.?));
        } else {
            try testing.expect(got == null);
        }
    }

    // DERIVED, NOT TABULATED — the constructor is `numericFacts.domain` plus the
    // two arithmetic-free scalars. An integral boxes as an integer so a value
    // above 2^53 is not rounded through the number box (the `crc64.final`
    // defect the site comments record); a real boxes as a number.
    try testing.expectEqual(@as(?LuaBoxClass, .int), luaBoxClass(.i16));
    try testing.expectEqual(@as(?LuaBoxClass, .int), luaBoxClass(.u64));
    try testing.expectEqual(@as(?LuaBoxClass, .num), luaBoxClass(.f32));
    try testing.expectEqual(@as(?LuaBoxClass, .num), luaBoxClass(.f64));
    try testing.expectEqual(@as(?LuaBoxClass, .@"bool"), luaBoxClass(.bool));
    try testing.expectEqual(@as(?LuaBoxClass, .str), luaBoxClass(.str));

    // DECLINED BY THE `numericFacts`/`scalarRepr` FACT, NOT BY ABSENCE: the
    // vectors span several cells (`lanes != 1`), `any` is already boxed, and
    // `void`/`nil`/`never` are not scalars the runtime boxes with a bare
    // constructor. Each answers null and the caller keeps its own box-less tail.
    try testing.expectEqual(@as(?LuaBoxClass, null), luaBoxClass(.v4i64));
    try testing.expectEqual(@as(?LuaBoxClass, null), luaBoxClass(.v8f32));
    try testing.expectEqual(@as(?LuaBoxClass, null), luaBoxClass(.any));
    try testing.expectEqual(@as(?LuaBoxClass, null), luaBoxClass(.void));

    // A NOMINAL DESCRIPTOR is WITHHELD by this owner, exactly as `scalarRepr`
    // withholds it: the box class is a question about identity. The two retired
    // switch sites listed only bare scalar tags, so a nominal-over-`i32`
    // (a `.struct` tag) fell to their box-less tail identically, and the global
    // export site's `luaBoxClass(grt) orelse .str` maps it to a null wrap the
    // same way. This is the one behavioural pin the derivation must match.
    const alloc = std.heap.page_allocator;
    try declareNominal(alloc, "beat", .i32);
    const nominal = nominalNamed("beat").?;
    try testing.expectEqual(@as(?LuaBoxClass, null), luaBoxClass(nominal));
    // Its PHYSICS still delegates, so withholding it here is an identity ruling
    // and not a claim that its representation has no box class.
    try testing.expectEqual(@as(?LuaBoxClass, .int), luaBoxClass(nominalReprOf(nominal).?));

    // Planting a widening — treating a real as an integer box — is refused by
    // the `domain` fact: a real answers `.num`, never `.int`.
    try testing.expect(luaBoxClass(.f64).? == .num);
}

test "types: the coercion face of the scalar roster is derived from the same facts" {
    // The retired coercion partition, verbatim, as the oracle. It stood at three
    // `codegen` per-tag switches — `rt_accepts_lua_value_coercion` (accept set),
    // `emit_lua_value_coercion_start` (the unwrap OPEN) and
    // `emit_lua_value_coercion_end` (its CLOSE) — the inverse of the boxing face
    // above: where the box ctor crosses a native scalar INTO a `lua_Value`, this
    // coerces a `lua_Value` back OUT into a native place. The oracle reproduces
    // each retired arm: `str`/`bool` unwrap with a named call and one paren, a
    // numeric scalar casts through `lua_to_num` to its own C spelling and closes
    // two parens, `any` is accepted with an empty (identity) wrap, everything
    // else is refused.
    const OracleArm = struct { accept: bool, open: []const u8, close: []const u8 };
    const retiredCoerce = struct {
        fn f(t: ResolvedType) OracleArm {
            return switch (t) {
                .str => .{ .accept = true, .open = "lua_to_str(", .close = ")" },
                .bool => .{ .accept = true, .open = "lua_to_bool(", .close = ")" },
                .f32, .f64, .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 => blk: {
                    var buf: [64]u8 = undefined;
                    const c = t.c_type(&buf);
                    // Compare on the fixed structure and the C spelling separately
                    // below; the open string is rebuilt from `c` at the callsite.
                    break :blk .{ .accept = true, .open = c, .close = "))" };
                },
                .any => .{ .accept = true, .open = "", .close = "" },
                else => .{ .accept = false, .open = "", .close = "" },
            };
        }
    }.f;

    // PINNED EQUAL TO THE RETIRED PARTITION on every payload-free identity — the
    // scalars it accepted and wrapped, `any` (accepted, identity wrap) AND the
    // vector, void, nil, never and composed identities it refused — iterated
    // over the union's own tags rather than a list, so a scalar identity added
    // to the union cannot be one the coercion face silently does not know.
    const info = @typeInfo(ResolvedType).@"union";
    inline for (info.field_names, info.field_types) |name, ty| {
        if (ty != void) continue;
        const t = @as(ResolvedType, @field(ResolvedType, name));
        const want = retiredCoerce(t);

        // Accept set = `luaCoerceAccepts`.
        try testing.expectEqual(want.accept, luaCoerceAccepts(t));

        const cls = luaCoerceClass(t);
        if (cls) |c| {
            var buf: [160]u8 = undefined;
            const open = c.open(&buf);
            const close = c.close();
            switch (c) {
                // A numeric scalar rebuilds the retired open from its own C
                // spelling; the oracle carried that spelling in `want.open`.
                .num => {
                    var ob: [160]u8 = undefined;
                    const wo = std.fmt.bufPrint(&ob, "(({s})lua_to_num(", .{want.open}) catch unreachable;
                    try testing.expect(std.mem.eql(u8, wo, open));
                    try testing.expect(std.mem.eql(u8, "))", close));
                },
                else => {
                    try testing.expect(std.mem.eql(u8, want.open, open));
                    try testing.expect(std.mem.eql(u8, want.close, close));
                },
            }
        } else {
            // No class means either `any` (accepted, identity wrap — the retired
            // switches' empty else arm) or a refused identity. Either way the
            // retired open and close were empty.
            try testing.expect(std.mem.eql(u8, "", want.open));
            try testing.expect(std.mem.eql(u8, "", want.close));
        }
    }

    // DERIVED, NOT TABULATED — the accept set gates on `scalarRepr` (plus `any`),
    // and the numeric variant reads the descriptor so the unwrap casts to its
    // OWN C spelling: an `i32` place lands as `((int32_t)lua_to_num(...))`, not
    // the boxed 64-bit ring. The box class discarded that width because every
    // integral boxes through one `int64_t` cast; the unwrap cannot.
    {
        var buf: [160]u8 = undefined;
        const c32 = luaCoerceClass(.i32).?;
        try testing.expect(std.mem.eql(u8, "((int32_t)lua_to_num(", c32.open(&buf)));
        try testing.expect(std.mem.eql(u8, "))", c32.close()));
        const cf = luaCoerceClass(.f32).?;
        try testing.expect(std.mem.eql(u8, "((float)lua_to_num(", cf.open(&buf)));
    }

    // `any` is ACCEPTED but has no class: it is already a `lua_Value`, so the
    // coercion is identity and the caller emits no wrapper.
    try testing.expect(luaCoerceAccepts(.any));
    try testing.expect(luaCoerceClass(.any) == null);

    // DECLINED BY THE `scalarRepr` FACT, NOT BY ABSENCE: the vectors span
    // several cells (`lanes != 1`), `void`/`nil`/`never` are not scalar values,
    // and a composed identity is not a bare scalar the runtime coerces.
    try testing.expect(!luaCoerceAccepts(.v4i64));
    try testing.expect(!luaCoerceAccepts(.void));
    try testing.expect(luaCoerceClass(.v8f32) == null);

    // A NOMINAL DESCRIPTOR is WITHHELD by this owner, exactly as `scalarRepr`
    // withholds it and exactly as the retired switches' bare scalar tags let a
    // nominal-over-`i32` (a `.struct` tag) fall to their else arm — refused.
    const alloc = std.heap.page_allocator;
    try declareNominal(alloc, "gain", .i32);
    const nominal = nominalNamed("gain").?;
    try testing.expect(!luaCoerceAccepts(nominal));
    try testing.expect(luaCoerceClass(nominal) == null);
    // Its PHYSICS still coerces, so withholding it here is an identity ruling.
    try testing.expect(luaCoerceClass(nominalReprOf(nominal).?) != null);
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
    try testing.expectEqual(@as(u64, shape.fingerprint()), callShapeFingerprint(shape));
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
