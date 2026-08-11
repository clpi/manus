//! Pass 8 — project-local persistent semantic evidence cache (bounded, invalidatable).
//!
//! Not a general database: compiler fingerprints, outcomes, and reuse keys only.
const std = @import("std");

pub const SCHEMA_VERSION = "persistent-semantic-state-v0";
pub const CACHE_DIR = ".duo/cache/semantic";
pub const DEFAULT_CACHE_PATH = ".duo/cache/semantic/state.json";

/// Classification of persistent facts (Pass 8 §5 / Goal C).
pub const FactKind = enum(u8) {
    semantic_invariant,
    source_derived,
    target_derived,
    profile_derived,
    benchmark_derived,
    user_asserted,
    imported,
    estimated,
    measured,
    stale,
    invalidated,

    pub fn name(self: FactKind) []const u8 {
        return @tagName(self);
    }
};

pub const Entry = struct {
    entity_id: []const u8,
    fingerprint: u64,
    kind: FactKind,
    artifact: []const u8,
    compiler_version: []const u8,
    target: []const u8,
    transform_version: ?[]const u8,
    stale: bool,

    pub fn deinit(self: *Entry, alloc: std.mem.Allocator) void {
        alloc.free(self.entity_id);
        alloc.free(self.artifact);
        alloc.free(self.compiler_version);
        alloc.free(self.target);
        if (self.transform_version) |v| alloc.free(v);
    }
};

pub const ReuseCheck = struct {
    entity_id: []const u8,
    prior_artifact: ?[]const u8,
    allowed: bool,
    reason: []const u8,

    pub fn deinit(self: *ReuseCheck, alloc: std.mem.Allocator) void {
        alloc.free(self.entity_id);
        if (self.prior_artifact) |a| alloc.free(a);
        alloc.free(self.reason);
    }
};

pub const State = struct {
    schema: []const u8 = SCHEMA_VERSION,
    entries: []Entry,

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        for (self.entries) |*e| e.deinit(alloc);
        alloc.free(self.entries);
    }
};

pub const ReuseDecision = struct {
    allowed: bool,
    reason: []const u8,

    pub fn deinit(self: *ReuseDecision, alloc: std.mem.Allocator) void {
        alloc.free(self.reason);
    }
};

/// Validate cross-build reuse (Milestone 2 foundation — Pass 8 §5).
pub fn canReuse(
    alloc: std.mem.Allocator,
    entry: *const Entry,
    fingerprint: u64,
    compiler_version: []const u8,
    target: []const u8,
    transform_version: ?[]const u8,
) !ReuseDecision {
    if (entry.stale or entry.kind == .stale or entry.kind == .invalidated) {
        return .{ .allowed = false, .reason = try alloc.dupe(u8, "entry marked stale or invalidated") };
    }
    if (entry.fingerprint != fingerprint) {
        return .{ .allowed = false, .reason = try alloc.dupe(u8, "semantic fingerprint mismatch") };
    }
    if (!std.mem.eql(u8, entry.compiler_version, compiler_version)) {
        return .{ .allowed = false, .reason = try alloc.dupe(u8, "compiler version mismatch") };
    }
    if (!std.mem.eql(u8, entry.target, target)) {
        return .{ .allowed = false, .reason = try alloc.dupe(u8, "target mismatch") };
    }
    if (entry.transform_version) |ev| {
        const tv = transform_version orelse {
            return .{ .allowed = false, .reason = try alloc.dupe(u8, "missing transform version in request") };
        };
        if (!std.mem.eql(u8, ev, tv)) {
            return .{ .allowed = false, .reason = try alloc.dupe(u8, "transformation registry version mismatch") };
        }
    }
    if (entry.kind == .profile_derived or entry.kind == .benchmark_derived or entry.kind == .measured) {
        return .{ .allowed = true, .reason = try alloc.dupe(u8, "observation reuse allowed; not promoted to semantic invariant") };
    }
    return .{ .allowed = true, .reason = try alloc.dupe(u8, "fingerprint, compiler, target, and transform version match") };
}

pub fn appendEntry(
    alloc: std.mem.Allocator,
    state: *State,
    entity_id: []const u8,
    fingerprint: u64,
    kind: FactKind,
    artifact: []const u8,
    compiler_version: []const u8,
    target: []const u8,
    transform_version: ?[]const u8,
) !void {
    var entry = try dupEntry(alloc, entity_id, fingerprint, kind, artifact, compiler_version, target, transform_version);
    errdefer entry.deinit(alloc);
    try appendOwnedEntry(alloc, state, entry);
}

fn dupEntry(
    alloc: std.mem.Allocator,
    entity_id: []const u8,
    fingerprint: u64,
    kind: FactKind,
    artifact: []const u8,
    compiler_version: []const u8,
    target: []const u8,
    transform_version: ?[]const u8,
) !Entry {
    const owned_entity = try alloc.dupe(u8, entity_id);
    errdefer alloc.free(owned_entity);
    const owned_artifact = try alloc.dupe(u8, artifact);
    errdefer alloc.free(owned_artifact);
    const owned_compiler = try alloc.dupe(u8, compiler_version);
    errdefer alloc.free(owned_compiler);
    const owned_target = try alloc.dupe(u8, target);
    errdefer alloc.free(owned_target);
    const owned_transform = if (transform_version) |version|
        try alloc.dupe(u8, version)
    else
        null;
    errdefer if (owned_transform) |version| alloc.free(version);
    return .{
        .entity_id = owned_entity,
        .fingerprint = fingerprint,
        .kind = kind,
        .artifact = owned_artifact,
        .compiler_version = owned_compiler,
        .target = owned_target,
        .transform_version = owned_transform,
        .stale = false,
    };
}

fn appendOwnedEntry(alloc: std.mem.Allocator, state: *State, entry: Entry) !void {
    const old = state.entries;
    const entries = try alloc.alloc(Entry, old.len + 1);
    @memcpy(entries[0..old.len], old);
    entries[old.len] = entry;
    if (old.len > 0) alloc.free(old);
    state.entries = entries;
}

pub fn findEntry(state: *const State, entity_id: []const u8) ?*const Entry {
    const index = findEntryIndex(state, entity_id) orelse return null;
    return &state.entries[index];
}

fn findEntryIndex(state: *const State, entity_id: []const u8) ?usize {
    for (state.entries, 0..) |entry, index| {
        if (std.mem.eql(u8, entry.entity_id, entity_id)) return index;
    }
    return null;
}

pub const AuditAction = enum(u8) {
    fresh,
    reused,
    updated,
    invalidated,

    pub fn name(self: AuditAction) []const u8 {
        return @tagName(self);
    }
};

pub const ReuseAudit = struct {
    entity_id: []const u8,
    action: AuditAction,
    reason: []const u8,
    artifact: []const u8,

    pub fn deinit(self: *ReuseAudit, alloc: std.mem.Allocator) void {
        alloc.free(self.entity_id);
        alloc.free(self.reason);
        alloc.free(self.artifact);
    }
};

fn dupReuseAudit(
    alloc: std.mem.Allocator,
    entity_id: []const u8,
    action: AuditAction,
    reason: []const u8,
    artifact: []const u8,
) !ReuseAudit {
    const owned_entity = try alloc.dupe(u8, entity_id);
    errdefer alloc.free(owned_entity);
    const owned_reason = try alloc.dupe(u8, reason);
    errdefer alloc.free(owned_reason);
    const owned_artifact = try alloc.dupe(u8, artifact);
    errdefer alloc.free(owned_artifact);
    return .{
        .entity_id = owned_entity,
        .action = action,
        .reason = owned_reason,
        .artifact = owned_artifact,
    };
}

/// Merge one realization entry into persistent state; returns reuse audit row (P8-M2).
pub fn mergeRealizationEntry(
    alloc: std.mem.Allocator,
    state: *State,
    entity_id: []const u8,
    fingerprint: u64,
    artifact: []const u8,
    compiler_version: []const u8,
    target: []const u8,
    transform_version: ?[]const u8,
) !ReuseAudit {
    const kind: FactKind = .source_derived;
    if (findEntryIndex(state, entity_id)) |index| {
        const prior = &state.entries[index];
        var decision = try canReuse(alloc, prior, fingerprint, compiler_version, target, transform_version);
        defer decision.deinit(alloc);
        if (decision.allowed and std.mem.eql(u8, prior.artifact, artifact)) {
            return dupReuseAudit(alloc, entity_id, .reused, decision.reason, artifact);
        }
        var replacement = try dupEntry(alloc, entity_id, fingerprint, kind, artifact, compiler_version, target, transform_version);
        errdefer replacement.deinit(alloc);
        var audit = try dupReuseAudit(
            alloc,
            entity_id,
            if (decision.allowed) .updated else .invalidated,
            decision.reason,
            artifact,
        );
        errdefer audit.deinit(alloc);
        const previous = prior.*;
        prior.* = replacement;
        var owned_previous = previous;
        owned_previous.deinit(alloc);
        return audit;
    }
    var entry = try dupEntry(alloc, entity_id, fingerprint, kind, artifact, compiler_version, target, transform_version);
    errdefer entry.deinit(alloc);
    var audit = try dupReuseAudit(alloc, entity_id, .fresh, "no prior cache entry for entity", artifact);
    errdefer audit.deinit(alloc);
    try appendOwnedEntry(alloc, state, entry);
    return audit;
}

pub fn sortEntriesDeterministic(state: *State) void {
    if (state.entries.len < 2) return;
    std.mem.sort(Entry, state.entries, {}, struct {
        fn less(_: void, a: Entry, b: Entry) bool {
            return std.mem.order(u8, a.entity_id, b.entity_id) == .lt;
        }
    }.less);
}

fn parseKind(name: []const u8) !FactKind {
    inline for (@typeInfo(FactKind).@"enum".field_names, @typeInfo(FactKind).@"enum".field_values) |n, v| {
        if (std.mem.eql(u8, n, name)) return @enumFromInt(v);
    }
    return error.UnknownFactKind;
}

const JsonEntry = struct {
    entity_id: []const u8,
    fingerprint: []const u8,
    kind: []const u8,
    artifact: []const u8,
    compiler_version: []const u8,
    target: []const u8,
    stale: bool,
    transform_version: ?[]const u8 = null,
};

const JsonFile = struct {
    schema: []const u8,
    entry_count: usize,
    entries: []JsonEntry,
};

pub fn loadFromPath(alloc: std.mem.Allocator, io: std.Io, path: []const u8) !State {
    const cwd = std.Io.Dir.cwd();
    const data = std.Io.Dir.readFileAlloc(cwd, io, path, alloc, .unlimited) catch |err| switch (err) {
        error.FileNotFound => return .{ .entries = &.{} },
        else => return err,
    };
    defer alloc.free(data);
    return try parseJsonFile(alloc, data);
}

fn parseJsonFile(alloc: std.mem.Allocator, data: []const u8) !State {
    var parsed = try std.json.parseFromSlice(
        JsonFile,
        alloc,
        data,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.schema, SCHEMA_VERSION)) return error.UnsupportedSchema;
    var entries: std.ArrayListUnmanaged(Entry) = .empty;
    errdefer {
        for (entries.items) |*e| e.deinit(alloc);
        entries.deinit(alloc);
    }
    for (parsed.value.entries) |je| {
        const fp = try std.fmt.parseInt(u64, je.fingerprint, 16);
        try appendParsedEntry(alloc, &entries, je, fp, try parseKind(je.kind));
    }
    if (entries.items.len >= 2) {
        std.mem.sort(Entry, entries.items, {}, struct {
            fn less(_: void, a: Entry, b: Entry) bool {
                return std.mem.order(u8, a.entity_id, b.entity_id) == .lt;
            }
        }.less);
    }
    return .{
        .entries = try entries.toOwnedSlice(alloc),
    };
}

fn appendParsedEntry(
    alloc: std.mem.Allocator,
    entries: *std.ArrayListUnmanaged(Entry),
    json: JsonEntry,
    fingerprint: u64,
    kind: FactKind,
) !void {
    var entry = try dupEntry(
        alloc,
        json.entity_id,
        fingerprint,
        kind,
        json.artifact,
        json.compiler_version,
        json.target,
        json.transform_version,
    );
    errdefer entry.deinit(alloc);
    try entries.append(alloc, entry);
}

pub fn saveToPath(alloc: std.mem.Allocator, io: std.Io, path: []const u8, state: *State) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (!std.mem.eql(u8, dir, ".")) {
            const cwd = std.Io.Dir.cwd();
            try cwd.createDirPath(io, dir);
        }
    }
    sortEntriesDeterministic(state);
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try writeJson(state, &aw.writer);
    const cwd = std.Io.Dir.cwd();
    try std.Io.Dir.writeFile(cwd, io, .{ .sub_path = path, .data = aw.written() });
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

pub fn writeJson(state: *const State, w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"entry_count\":{d},\"entries\":[", .{ state.schema, state.entries.len });
    for (state.entries, 0..) |e, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"entity_id\":\"", .{});
        try jsonEscape(w, e.entity_id);
        try w.print("\",\"fingerprint\":\"{x}\",\"kind\":\"{s}\",\"artifact\":\"", .{ e.fingerprint, e.kind.name() });
        try jsonEscape(w, e.artifact);
        try w.print("\",\"compiler_version\":\"", .{});
        try jsonEscape(w, e.compiler_version);
        try w.print("\",\"target\":\"", .{});
        try jsonEscape(w, e.target);
        try w.print("\",\"stale\":", .{});
        try w.print("{s}", .{if (e.stale) "true" else "false"});
        if (e.transform_version) |tv| {
            try w.print(",\"transform_version\":\"", .{});
            try jsonEscape(w, tv);
            try w.print("\"", .{});
        }
        try w.print("}}", .{});
    }
    try w.print("]}}", .{});
}

pub fn writeReuseAuditJson(rows: []const ReuseAudit, w: *std.Io.Writer) !void {
    try w.print("[", .{});
    for (rows, 0..) |row, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"entity_id\":\"", .{});
        try jsonEscape(w, row.entity_id);
        try w.print("\",\"action\":\"{s}\",\"reason\":\"", .{row.action.name()});
        try jsonEscape(w, row.reason);
        try w.print("\",\"artifact\":\"", .{});
        try jsonEscape(w, row.artifact);
        try w.print("\"}}", .{});
    }
    try w.print("]", .{});
}

fn expectEntryUnchanged(expected: Entry, actual: Entry) !void {
    try std.testing.expect(expected.entity_id.ptr == actual.entity_id.ptr);
    try std.testing.expectEqual(expected.entity_id.len, actual.entity_id.len);
    try std.testing.expectEqual(expected.fingerprint, actual.fingerprint);
    try std.testing.expectEqual(expected.kind, actual.kind);
    try std.testing.expect(expected.artifact.ptr == actual.artifact.ptr);
    try std.testing.expectEqual(expected.artifact.len, actual.artifact.len);
    try std.testing.expect(expected.compiler_version.ptr == actual.compiler_version.ptr);
    try std.testing.expectEqual(expected.compiler_version.len, actual.compiler_version.len);
    try std.testing.expect(expected.target.ptr == actual.target.ptr);
    try std.testing.expectEqual(expected.target.len, actual.target.len);
    try std.testing.expectEqual(expected.stale, actual.stale);
    try std.testing.expectEqual(expected.transform_version == null, actual.transform_version == null);
    if (expected.transform_version) |expected_version| {
        const actual_version = actual.transform_version.?;
        try std.testing.expect(expected_version.ptr == actual_version.ptr);
        try std.testing.expectEqual(expected_version.len, actual_version.len);
    }
}

fn expectSingleEntryUnchanged(expected_ptr: [*]Entry, expected: Entry, state: *const State) !void {
    try std.testing.expect(state.entries.ptr == expected_ptr);
    try std.testing.expectEqual(@as(usize, 1), state.entries.len);
    try expectEntryUnchanged(expected, state.entries[0]);
}

fn appendEmptyAllocationProbe(alloc: std.mem.Allocator) !void {
    var state: State = .{ .entries = &.{} };
    defer state.deinit(alloc);
    const expected_ptr = state.entries.ptr;
    appendEntry(
        alloc,
        &state,
        "duo:record:Point",
        0xabc,
        .source_derived,
        "native_aggregate",
        "duo-test",
        "native",
        "transform-registry-v0",
    ) catch |err| {
        try std.testing.expect(state.entries.ptr == expected_ptr);
        try std.testing.expectEqual(@as(usize, 0), state.entries.len);
        return err;
    };
    try std.testing.expectEqual(@as(usize, 1), state.entries.len);
}

fn appendNonemptyAllocationProbe(alloc: std.mem.Allocator) !void {
    var state: State = .{ .entries = &.{} };
    defer state.deinit(alloc);
    try appendEntry(alloc, &state, "duo:record:Point", 0xabc, .source_derived, "native_aggregate", "duo-test", "native", null);
    const expected_ptr = state.entries.ptr;
    const expected_entry = state.entries[0];
    appendEntry(
        alloc,
        &state,
        "duo:record:Vector",
        0xdef,
        .source_derived,
        "native_struct",
        "duo-test",
        "native",
        "transform-registry-v0",
    ) catch |err| {
        try expectSingleEntryUnchanged(expected_ptr, expected_entry, &state);
        return err;
    };
    try std.testing.expectEqual(@as(usize, 2), state.entries.len);
}

fn mergeAllocationProbe(alloc: std.mem.Allocator, expected_action: AuditAction) !void {
    var state: State = .{ .entries = &.{} };
    defer state.deinit(alloc);
    if (expected_action != .fresh) {
        try appendEntry(
            alloc,
            &state,
            "duo:record:Point",
            if (expected_action == .invalidated) 0xdef else 0xabc,
            .source_derived,
            if (expected_action == .updated) "native_struct" else "native_aggregate",
            "duo-test",
            "native",
            "transform-registry-v0",
        );
    }
    const expected_ptr = state.entries.ptr;
    const expected_entry = if (state.entries.len == 1) state.entries[0] else null;
    const audit = mergeRealizationEntry(
        alloc,
        &state,
        "duo:record:Point",
        0xabc,
        "native_aggregate",
        "duo-test",
        "native",
        "transform-registry-v0",
    ) catch |err| {
        if (expected_entry) |entry| {
            try expectSingleEntryUnchanged(expected_ptr, entry, &state);
        } else {
            try std.testing.expect(state.entries.ptr == expected_ptr);
            try std.testing.expectEqual(@as(usize, 0), state.entries.len);
        }
        return err;
    };
    var owned_audit = audit;
    defer owned_audit.deinit(alloc);
    try std.testing.expectEqual(expected_action, audit.action);
    try std.testing.expectEqual(@as(usize, 1), state.entries.len);
    if (expected_action == .reused) {
        try expectSingleEntryUnchanged(expected_ptr, expected_entry.?, &state);
    } else {
        try std.testing.expectEqual(@as(u64, 0xabc), state.entries[0].fingerprint);
        try std.testing.expectEqualStrings("native_aggregate", state.entries[0].artifact);
    }
}

fn parseAllocationProbe(alloc: std.mem.Allocator) !void {
    const data =
        \\{"schema":"persistent-semantic-state-v0","entry_count":2,"entries":[
        \\{"entity_id":"duo:record:Point","fingerprint":"abc","kind":"source_derived","artifact":"native_aggregate","compiler_version":"duo-test","target":"native","stale":false,"transform_version":"transform-registry-v0"},
        \\{"entity_id":"duo:record:Vector","fingerprint":"def","kind":"target_derived","artifact":"native_struct","compiler_version":"duo-test","target":"wasm","stale":false}
        \\]}
    ;
    var state = try parseJsonFile(alloc, data);
    defer state.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 2), state.entries.len);
}

test "persistent_semantic_state: reuse rejects stale" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var entry = Entry{
        .entity_id = try alloc.dupe(u8, "duo:record:Point"),
        .fingerprint = 0xabc,
        .kind = .semantic_invariant,
        .artifact = try alloc.dupe(u8, "specialization:v1"),
        .compiler_version = try alloc.dupe(u8, "duo-test"),
        .target = try alloc.dupe(u8, "native"),
        .transform_version = null,
        .stale = true,
    };
    defer entry.deinit(alloc);
    var d = try canReuse(alloc, &entry, 0xabc, "duo-test", "native", null);
    defer d.deinit(alloc);
    try std.testing.expect(!d.allowed);
}

test "persistent_semantic_state: reuse accepts matching invariant" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var entry = Entry{
        .entity_id = try alloc.dupe(u8, "duo:record:Point"),
        .fingerprint = 0xabc,
        .kind = .semantic_invariant,
        .artifact = try alloc.dupe(u8, "repr.native_aggregate"),
        .compiler_version = try alloc.dupe(u8, "duo-test"),
        .target = try alloc.dupe(u8, "native"),
        .transform_version = try alloc.dupe(u8, "transform-registry-v0"),
        .stale = false,
    };
    defer entry.deinit(alloc);
    var d = try canReuse(alloc, &entry, 0xabc, "duo-test", "native", "transform-registry-v0");
    defer d.deinit(alloc);
    try std.testing.expect(d.allowed);
}

test "persistent_semantic_state: save and load round trip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var state = State{ .entries = &.{} };
    try appendEntry(alloc, &state, "duo:record:Point", 0xabc, .source_derived, "native_aggregate", "duo-test", "native", "transform-registry-v0");
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try writeJson(&state, &aw.writer);
    var loaded = try parseJsonFile(alloc, aw.written());
    defer loaded.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 1), loaded.entries.len);
    try std.testing.expectEqualStrings("duo:record:Point", loaded.entries[0].entity_id);
    try std.testing.expectEqual(@as(u64, 0xabc), loaded.entries[0].fingerprint);
}

test "persistent_semantic_state: merge reports reused on second compile" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var state = State{ .entries = &.{} };
    var a1 = try mergeRealizationEntry(alloc, &state, "duo:record:Point", 0xabc, "native_aggregate", "duo-test", "native", "transform-registry-v0");
    defer a1.deinit(alloc);
    try std.testing.expect(a1.action == .fresh);
    var a2 = try mergeRealizationEntry(alloc, &state, "duo:record:Point", 0xabc, "native_aggregate", "duo-test", "native", "transform-registry-v0");
    defer a2.deinit(alloc);
    try std.testing.expect(a2.action == .reused);
}

test "persistent_semantic_state: empty append is transactional under allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, appendEmptyAllocationProbe, .{});
}

test "persistent_semantic_state: nonempty append is transactional under allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, appendNonemptyAllocationProbe, .{});
}

test "persistent_semantic_state: fresh merge is transactional under allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, mergeAllocationProbe, .{AuditAction.fresh});
}

test "persistent_semantic_state: reused merge is transactional under allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, mergeAllocationProbe, .{AuditAction.reused});
}

test "persistent_semantic_state: updated merge is transactional under allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, mergeAllocationProbe, .{AuditAction.updated});
}

test "persistent_semantic_state: invalidated merge is transactional under allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, mergeAllocationProbe, .{AuditAction.invalidated});
}

test "persistent_semantic_state: parsed entries release every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, parseAllocationProbe, .{});
}
