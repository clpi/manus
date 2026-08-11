//! Pass 26 M1 — descriptor fingerprint interning + recursive fixed-point identity.
//!
//! Wires Pass 26 §5–§7 identity layers and §26 recursive descriptors into a single
//! registry consumed by `semantic_graph` at alias lift time.
const std = @import("std");
const types = @import("types.zig");
const pass26_descriptor_identity = @import("pass26_descriptor_identity.zig");
const pass26_recursive_descriptor = @import("pass26_recursive_descriptor.zig");

pub const SCHEMA_VERSION = "pass26-descriptor-intern-v1";

pub const AliasSpan = struct {
    line: u32,
    col: u32,
};

pub const IdentityRecord = struct {
    /// Layer 1 — canonical semantic content (field-order normalized when pure).
    semantic_fingerprint: u64,
    /// Layer 2 — declaration/provenance identity (never merged across bindings).
    declaration_identity: u64,
    /// Layer 3 — intern slot when pure descriptors collapse (optional).
    intern_slot: ?u32 = null,
    /// Layer 4 — physical layout lives in `shape_id` on graph nodes, not here.
    state: pass26_descriptor_identity.DescriptorState,
    recursion: pass26_recursive_descriptor.RecursionKind,
    completion: pass26_recursive_descriptor.DescriptorCompletion,
};

const FieldEntry = struct {
    name: []const u8,
    type_tag: u64,
};

pub fn declarationIdentityHash(
    module_path: []const u8,
    name: []const u8,
    span: AliasSpan,
) u64 {
    var hasher = std.hash.Wyhash.init(0xDEC1A5E);
    hasher.update(module_path);
    hasher.update("|decl|");
    hasher.update(name);
    hasher.update("|");
    hasher.update(std.mem.asBytes(&span.line));
    hasher.update(std.mem.asBytes(&span.col));
    return hasher.final();
}

fn typeStructureTag(rt: types.ResolvedType) u64 {
    var hasher = std.hash.Wyhash.init(0x7710E000);
    var buf: [64]u8 = undefined;
    switch (rt) {
        .table_type => |t| {
            hasher.update("table");
            for (t.fields) |f| {
                hasher.update(f.name);
                hasher.update(f.typ.c_type(&buf));
            }
        },
        .enum_type => |e| {
            hasher.update("enum");
            hasher.update(e.name);
            for (e.variants) |v| {
                hasher.update(v.name);
                if (v.payload) |payload| {
                    for (payload) |p| hasher.update(p.c_type(&buf));
                }
            }
        },
        else => hasher.update(rt.c_type(&buf)),
    }
    return hasher.final();
}

fn collectFieldEntries(
    rt: types.ResolvedType,
    alloc: std.mem.Allocator,
) ![]FieldEntry {
    switch (rt) {
        .table_type => |t| {
            var out = try alloc.alloc(FieldEntry, t.fields.len);
            for (t.fields, 0..) |f, i| {
                out[i] = .{ .name = f.name, .type_tag = typeStructureTag(f.typ) };
            }
            return out;
        },
        .enum_type => |e| {
            var out = try alloc.alloc(FieldEntry, e.variants.len);
            for (e.variants, 0..) |v, i| {
                var tag: u64 = 0;
                if (v.payload) |payload| {
                    for (payload) |p| tag ^= typeStructureTag(p);
                }
                out[i] = .{ .name = v.name, .type_tag = tag };
            }
            return out;
        },
        else => return &.{},
    }
}

pub fn semanticFingerprint(
    rt: types.ResolvedType,
    state: pass26_descriptor_identity.DescriptorState,
    completion: pass26_recursive_descriptor.DescriptorCompletion,
    recursion: pass26_recursive_descriptor.RecursionKind,
    alloc: std.mem.Allocator,
) !u64 {
    const entries = try collectFieldEntries(rt, alloc);
    defer if (entries.len > 0) alloc.free(entries);

    var sorted: [64]FieldEntry = undefined;
    if (entries.len > sorted.len) return error.TooManyFields;
    @memcpy(sorted[0..entries.len], entries);
    const scratch = sorted[0..entries.len];

    switch (state) {
        .open_semantic, .mutable_builder => {},
        .frozen_snapshot, .sealed, .derived => if (scratch.len > 1) {
            std.mem.sort(FieldEntry, scratch, {}, struct {
                fn less(_: void, a: FieldEntry, b: FieldEntry) bool {
                    return std.mem.order(u8, a.name, b.name) == .lt;
                }
            }.less);
        },
    }

    var hasher = std.hash.Wyhash.init(0x5E4A71C0);
    hasher.update(@tagName(state));
    hasher.update(@tagName(completion));
    hasher.update(@tagName(recursion));
    for (scratch) |e| {
        hasher.update(e.name);
        hasher.update(std.mem.asBytes(&e.type_tag));
    }
    return hasher.final();
}

pub const RegistryError = error{
    TooManyFields,
};

pub fn referencesDescriptorName(rt: types.ResolvedType, name: []const u8) bool {
    switch (rt) {
        .@"struct" => |s| return std.mem.eql(u8, s.name, name),
        .pointer => |p| return referencesDescriptorName(p.*, name),
        .table_type => |t| {
            for (t.fields) |f| {
                if (referencesDescriptorName(f.typ, name)) return true;
            }
            return false;
        },
        .enum_type => |e| {
            if (std.mem.eql(u8, e.name, name)) return true;
            for (e.variants) |v| {
                if (v.payload) |payload| {
                    for (payload) |p| {
                        if (referencesDescriptorName(p, name)) return true;
                    }
                }
            }
            return false;
        },
        else => return false,
    }
}

fn referencesDescriptorInline(rt: types.ResolvedType, name: []const u8) bool {
    switch (rt) {
        .@"struct" => |s| return std.mem.eql(u8, s.name, name),
        .table_type => |t| {
            for (t.fields) |f| {
                if (referencesDescriptorInline(f.typ, name)) return true;
            }
            return false;
        },
        .enum_type => |e| {
            for (e.variants) |v| {
                if (v.payload) |payload| {
                    for (payload) |p| {
                        if (referencesDescriptorInline(p, name)) return true;
                    }
                }
            }
            return false;
        },
        else => return false,
    }
}

pub fn classifyRecursion(name: []const u8, rt: types.ResolvedType) pass26_recursive_descriptor.RecursionKind {
    if (!referencesDescriptorName(rt, name)) return .none;
    if (referencesDescriptorInline(rt, name)) return .inline_fixed_point;
    return .indirect_pointer;
}

pub fn inferDescriptorState(sc: types.StorageClass, is_sealed: bool) pass26_descriptor_identity.DescriptorState {
    if (is_sealed) return .sealed;
    return switch (sc) {
        .native => .sealed,
        .sealed => .sealed,
        .guarded => .open_semantic,
        .dynamic => .open_semantic,
    };
}

pub fn resolveCompletion(
    recursion: pass26_recursive_descriptor.RecursionKind,
    rt: types.ResolvedType,
) pass26_recursive_descriptor.DescriptorCompletion {
    if (recursion == .none) return .complete;
    if (rt == .any) return .invalid_incomplete;
    return .complete;
}

pub const Registry = struct {
    alloc: std.mem.Allocator,
    records: std.ArrayListUnmanaged(IdentityRecord) = .empty,
    fingerprint_slots: std.AutoHashMapUnmanaged(u64, u32) = .empty,

    pub fn init(alloc: std.mem.Allocator) Registry {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *Registry) void {
        self.records.deinit(self.alloc);
        self.fingerprint_slots.deinit(self.alloc);
    }

    pub fn get(self: *const Registry, index: u32) ?*const IdentityRecord {
        if (index >= self.records.items.len) return null;
        return &self.records.items[index];
    }

    pub fn registerAlias(
        self: *Registry,
        module_path: []const u8,
        name: []const u8,
        span: AliasSpan,
        rt: types.ResolvedType,
        sc: types.StorageClass,
    ) !u32 {
        const is_sealed = if (rt == .table_type) rt.table_type.is_sealed else false;
        const state = inferDescriptorState(sc, is_sealed);
        const recursion = classifyRecursion(name, rt);
        const completion = resolveCompletion(recursion, rt);

        const fingerprint = try semanticFingerprint(rt, state, completion, recursion, self.alloc);
        const decl_id = declarationIdentityHash(module_path, name, span);
        try self.records.ensureUnusedCapacity(self.alloc, 1);

        var intern_slot: ?u32 = null;

        switch (state) {
            .sealed, .frozen_snapshot, .derived => {
                if (self.fingerprint_slots.get(fingerprint)) |existing| {
                    intern_slot = existing;
                } else {
                    const slot: u32 = @intCast(self.records.items.len);
                    try self.fingerprint_slots.put(self.alloc, fingerprint, slot);
                    intern_slot = slot;
                }
            },
            .open_semantic, .mutable_builder => {},
        }

        const record = IdentityRecord{
            .semantic_fingerprint = fingerprint,
            .declaration_identity = decl_id,
            .intern_slot = intern_slot,
            .state = state,
            .recursion = recursion,
            .completion = completion,
        };
        self.records.appendAssumeCapacity(record);
        return @intCast(self.records.items.len - 1);
    }
};

test "pass26_descriptor_intern: field order normalization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields_a = try alloc.alloc(types.FieldType, 2);
    fields_a[0] = .{ .name = "x", .typ = .i64 };
    fields_a[1] = .{ .name = "y", .typ = .i64 };
    const fields_b = try alloc.alloc(types.FieldType, 2);
    fields_b[0] = .{ .name = "y", .typ = .i64 };
    fields_b[1] = .{ .name = "x", .typ = .i64 };

    const a: types.ResolvedType = .{ .table_type = .{ .fields = fields_a, .storage_class = .native, .is_sealed = true } };
    const b: types.ResolvedType = .{ .table_type = .{ .fields = fields_b, .storage_class = .native, .is_sealed = true } };

    const fp_a = try semanticFingerprint(a, .sealed, .complete, .none, alloc);
    const fp_b = try semanticFingerprint(b, .sealed, .complete, .none, alloc);
    try std.testing.expectEqual(fp_a, fp_b);
}

test "pass26_descriptor_intern: pure pair interning" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.alloc(types.FieldType, 2);
    fields[0] = .{ .name = "first", .typ = .i32 };
    fields[1] = .{ .name = "second", .typ = .str };
    const rt: types.ResolvedType = .{ .table_type = .{ .fields = fields, .storage_class = .native, .is_sealed = true } };

    var reg = Registry.init(alloc);
    defer reg.deinit();

    const x = try reg.registerAlias("mod.duo", "X", .{ .line = 1, .col = 1 }, rt, .native);
    const y = try reg.registerAlias("mod.duo", "Y", .{ .line = 2, .col = 1 }, rt, .native);

    const rx = reg.get(x).?;
    const ry = reg.get(y).?;
    try std.testing.expectEqual(rx.semantic_fingerprint, ry.semantic_fingerprint);
    try std.testing.expect(rx.declaration_identity != ry.declaration_identity);
    try std.testing.expect(rx.intern_slot != null);
    try std.testing.expectEqual(rx.intern_slot, ry.intern_slot);
}

test "pass26_descriptor_intern: descriptor state controls candidate sharing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const fields = try alloc.alloc(types.FieldType, 1);
    fields[0] = .{ .name = "value", .typ = .i64 };
    const open: types.ResolvedType = .{ .table_type = .{
        .fields = fields,
        .storage_class = .guarded,
        .is_sealed = false,
    } };
    const sealed: types.ResolvedType = .{ .table_type = .{
        .fields = fields,
        .storage_class = .sealed,
        .is_sealed = true,
    } };

    var reg = Registry.init(alloc);
    defer reg.deinit();

    const first_open = try reg.registerAlias("graph.id", "OpenA", .{ .line = 1, .col = 1 }, open, .guarded);
    const second_open = try reg.registerAlias("graph.id", "OpenB", .{ .line = 2, .col = 1 }, open, .guarded);
    try std.testing.expect(reg.get(first_open).?.intern_slot == null);
    try std.testing.expect(reg.get(second_open).?.intern_slot == null);

    const first = try reg.registerAlias("graph.id", "First", .{ .line = 3, .col = 1 }, sealed, .sealed);
    const second = try reg.registerAlias("graph.id", "Second", .{ .line = 4, .col = 1 }, sealed, .sealed);
    try std.testing.expect(reg.get(first).?.intern_slot != null);
    try std.testing.expectEqual(reg.get(first).?.intern_slot, reg.get(second).?.intern_slot);
}

test "pass26_descriptor_intern: allocation failure cannot retain a candidate slot" {
    var first_fields = [_]types.FieldType{.{ .name = "first", .typ = .i64 }};
    var second_fields = [_]types.FieldType{.{ .name = "second", .typ = .i64 }};
    const first_type: types.ResolvedType = .{ .table_type = .{
        .fields = &first_fields,
        .storage_class = .sealed,
        .is_sealed = true,
    } };
    const second_type: types.ResolvedType = .{ .table_type = .{
        .fields = &second_fields,
        .storage_class = .sealed,
        .is_sealed = true,
    } };

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 2,
    });
    var reg = Registry.init(failing.allocator());
    errdefer reg.deinit();

    try std.testing.expectError(
        error.OutOfMemory,
        reg.registerAlias("graph.id", "First", .{ .line = 1, .col = 1 }, first_type, .sealed),
    );
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 0), reg.records.items.len);

    failing.fail_index = std.math.maxInt(usize);
    const second = try reg.registerAlias("graph.id", "Second", .{ .line = 2, .col = 1 }, second_type, .sealed);
    const first = try reg.registerAlias("graph.id", "First", .{ .line = 1, .col = 1 }, first_type, .sealed);
    try std.testing.expect(reg.get(second).?.intern_slot != null);
    try std.testing.expect(reg.get(first).?.intern_slot != null);
    try std.testing.expect(reg.get(second).?.intern_slot != reg.get(first).?.intern_slot);

    reg.deinit();
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}

test "pass26_descriptor_intern: recursive pointer classification" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const node_struct: types.ResolvedType = .{ .@"struct" = .{ .name = "Node" } };
    const next_ptr = try alloc.create(types.ResolvedType);
    next_ptr.* = node_struct;
    const fields = try alloc.alloc(types.FieldType, 2);
    fields[0] = .{ .name = "value", .typ = .i64 };
    fields[1] = .{ .name = "next", .typ = .{ .pointer = next_ptr } };
    const rt: types.ResolvedType = .{ .table_type = .{ .fields = fields, .storage_class = .native, .is_sealed = true } };

    var reg = Registry.init(alloc);
    defer reg.deinit();

    const span = AliasSpan{ .line = 4, .col = 2 };
    const index = try reg.registerAlias("graph.id", "Node", span, rt, .native);
    const record = reg.get(index).?;
    const recursion = classifyRecursion("Node", rt);

    try std.testing.expectEqual(@as(usize, 1), reg.records.items.len);
    try std.testing.expectEqual(pass26_recursive_descriptor.RecursionKind.indirect_pointer, recursion);
    try std.testing.expectEqual(recursion, record.recursion);
    try std.testing.expectEqual(pass26_recursive_descriptor.DescriptorCompletion.complete, record.completion);
    try std.testing.expectEqual(pass26_descriptor_identity.DescriptorState.sealed, record.state);
    try std.testing.expect(record.intern_slot != null);
}

test "pass26_descriptor_intern: declaration identity differs from fingerprint" {
    const a = declarationIdentityHash("a.duo", "Point", .{ .line = 10, .col = 1 });
    const b = declarationIdentityHash("b.duo", "Point", .{ .line = 10, .col = 1 });
    try std.testing.expect(a != b);
}
