//! Pass 7 — structured optimization / transformation outcome records.
//!
//! Complements `transform_engine` provenance hashes with agent-consumable outcomes.
const std = @import("std");
const transform_engine = @import("transform_engine.zig");
const semantic_algebra = @import("semantic_algebra.zig");

pub const SCHEMA_VERSION = "optimization-outcome-v0";

pub const Status = enum(u8) {
    applied,
    rejected,
    deferred,
    inapplicable,
    budget_exceeded,
    target_unsupported,
    semantically_unsafe,
    profile_insufficient,
    invalidated,

    pub fn name(self: Status) []const u8 {
        return switch (self) {
            .applied => "applied",
            .rejected => "rejected",
            .deferred => "deferred",
            .inapplicable => "inapplicable",
            .budget_exceeded => "budget_exceeded",
            .target_unsupported => "target_unsupported",
            .semantically_unsafe => "semantically_unsafe",
            .profile_insufficient => "profile_insufficient",
            .invalidated => "invalidated",
        };
    }
};

/// Evidence strength for an optimization claim (Pass 7 §10.1).
pub const Evidence = enum(u8) {
    proven,
    guarded,
    assumed,
    profiled,
    estimated,
    measured,

    pub fn name(self: Evidence) []const u8 {
        return switch (self) {
            .proven => "proven",
            .guarded => "guarded",
            .assumed => "assumed",
            .profiled => "profiled",
            .estimated => "estimated",
            .measured => "measured",
        };
    }
};

pub const Outcome = struct {
    transformation: []const u8,
    entity: ?[]const u8,
    status: Status,
    evidence: Evidence,
    site: transform_engine.SiteKind,
    reason: ?[]const u8,
    before_repr: ?[]const u8,
    after_repr: ?[]const u8,
    inputs_hash: u64,
    output_hash: u64,

    pub fn deinit(self: *Outcome, alloc: std.mem.Allocator) void {
        alloc.free(self.transformation);
        if (self.entity) |e| alloc.free(e);
        if (self.reason) |r| alloc.free(r);
        if (self.before_repr) |b| alloc.free(b);
        if (self.after_repr) |a| alloc.free(a);
    }
};

pub const OutcomeLog = struct {
    items: []Outcome,

    pub fn deinit(self: *OutcomeLog, alloc: std.mem.Allocator) void {
        for (self.items) |*o| o.deinit(alloc);
        alloc.free(self.items);
    }
};

var session_log: std.ArrayListUnmanaged(Outcome) = .empty;
var session_enabled: bool = false;
var session_bridge: bool = false;
const session_allocator = std.heap.page_allocator;

pub fn setEnabled(enabled: bool) void {
    session_enabled = enabled;
    if (!enabled and !session_bridge) {
        for (session_log.items) |*o| o.deinit(session_allocator);
        session_log.clearRetainingCapacity();
    }
}

/// Allow contract outcome logging during explain/codegen without global session mode.
pub fn setSessionBridge(enabled: bool) void {
    session_bridge = enabled;
}

pub fn deinitSession(_: std.mem.Allocator) void {
    for (session_log.items) |*o| o.deinit(session_allocator);
    session_log.deinit(session_allocator);
    session_log = .empty;
    session_enabled = false;
}

pub fn logOutcome(
    alloc: std.mem.Allocator,
    transformation: []const u8,
    entity: ?[]const u8,
    status: Status,
    evidence: Evidence,
    site: transform_engine.SiteKind,
    reason: ?[]const u8,
    before_repr: ?[]const u8,
    after_repr: ?[]const u8,
    inputs_hash: u64,
    output_hash: u64,
) !void {
    if (!session_enabled and !session_bridge) return;
    _ = alloc;
    const store = session_allocator;
    const t = try store.dupe(u8, transformation);
    errdefer store.free(t);
    const ent = if (entity) |e| try store.dupe(u8, e) else null;
    errdefer if (ent) |e| store.free(e);
    const rs = if (reason) |r| try store.dupe(u8, r) else null;
    errdefer if (rs) |r| store.free(r);
    const br = if (before_repr) |b| try store.dupe(u8, b) else null;
    errdefer if (br) |b| store.free(b);
    const ar = if (after_repr) |a| try store.dupe(u8, a) else null;
    errdefer if (ar) |a| store.free(a);
    try session_log.append(store, .{
        .transformation = t,
        .entity = ent,
        .status = status,
        .evidence = evidence,
        .site = site,
        .reason = rs,
        .before_repr = br,
        .after_repr = ar,
        .inputs_hash = inputs_hash,
        .output_hash = output_hash,
    });
}

/// Convert transform_engine provenance entries into applied outcomes.
pub fn fromProvenance(alloc: std.mem.Allocator) !OutcomeLog {
    const entries = transform_engine.provenanceEntries();
    var items: std.ArrayListUnmanaged(Outcome) = .empty;
    errdefer {
        for (items.items) |*o| o.deinit(alloc);
        items.deinit(alloc);
    }
    for (entries) |e| {
        try items.append(alloc, .{
            .transformation = try alloc.dupe(u8, e.public_name),
            .entity = null,
            .status = .applied,
            .evidence = .proven,
            .site = e.site,
            .reason = null,
            .before_repr = null,
            .after_repr = null,
            .inputs_hash = e.inputs_hash,
            .output_hash = e.output_hash,
        });
    }
    return .{ .items = try items.toOwnedSlice(alloc) };
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

/// Append session-scoped outcomes (e.g. contract rejections) into `dest`.
pub fn mergeSessionInto(alloc: std.mem.Allocator, dest: *OutcomeLog) !void {
    if (session_log.items.len == 0) return;
    const old = dest.items;
    const combined = try alloc.alloc(Outcome, old.len + session_log.items.len);
    errdefer alloc.free(combined);
    @memcpy(combined[0..old.len], old);
    for (session_log.items, 0..) |src, i| {
        combined[old.len + i] = .{
            .transformation = try alloc.dupe(u8, src.transformation),
            .entity = if (src.entity) |e| try alloc.dupe(u8, e) else null,
            .status = src.status,
            .evidence = src.evidence,
            .site = src.site,
            .reason = if (src.reason) |r| try alloc.dupe(u8, r) else null,
            .before_repr = if (src.before_repr) |b| try alloc.dupe(u8, b) else null,
            .after_repr = if (src.after_repr) |a| try alloc.dupe(u8, a) else null,
            .inputs_hash = src.inputs_hash,
            .output_hash = src.output_hash,
        };
    }
    alloc.free(old);
    dest.items = combined;
}

pub fn writeJson(log: *const OutcomeLog, w: *std.Io.Writer) !void {
    try w.print(
        "{{\"schema\":\"{s}\",\"outcome_count\":{d},\"outcomes\":[",
        .{ SCHEMA_VERSION, log.items.len },
    );
    for (log.items, 0..) |o, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"transformation\":\"", .{});
        try jsonEscape(w, o.transformation);
        try w.print(
            "\",\"status\":\"{s}\",\"evidence\":\"{s}\",\"site\":\"{s}\",\"inputs_hash\":{x},\"output_hash\":{x}",
            .{ o.status.name(), o.evidence.name(), transform_engine.siteKindName(o.site), o.inputs_hash, o.output_hash },
        );
        if (o.reason) |r| {
            try w.print(",\"reason\":\"", .{});
            try jsonEscape(w, r);
            try w.print("\"", .{});
        }
        // H-8: the outcome already CARRIES its subject and its chosen
        // representation. Printing only `reason` left both readable solely as
        // prose inside one string, so nothing outside the process could assert
        // which entity was realized as what.
        if (o.entity) |e| {
            try w.print(",\"entity\":\"", .{});
            try jsonEscape(w, e);
            try w.print("\"", .{});
        }
        if (o.before_repr) |b| {
            try w.print(",\"before_repr\":\"", .{});
            try jsonEscape(w, b);
            try w.print("\"", .{});
        }
        if (o.after_repr) |a| {
            try w.print(",\"after_repr\":\"", .{});
            try jsonEscape(w, a);
            try w.print("\"", .{});
        }
        try w.print("}}", .{});
    }
    try w.print("]}}", .{});
}

pub fn writeJsonLine(log: *const OutcomeLog, w: *std.Io.Writer) !void {
    try writeJson(log, w);
    try w.print("\n", .{});
}

test "optimization_outcome: provenance converts to applied outcomes" {
    const alloc = std.testing.allocator;
    defer deinitSession(alloc);
    transform_engine.deinitProvenance(alloc);
    transform_engine.setProvenanceEnabled(true);
    transform_engine.logProvenance(alloc, "comp.why.boxed", .emit_call, 1, 2);
    var log = try fromProvenance(alloc);
    defer log.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 1), log.items.len);
    try std.testing.expectEqualStrings("comp.why.boxed", log.items[0].transformation);
    try std.testing.expectEqual(Status.applied, log.items[0].status);
    try std.testing.expectEqual(Evidence.proven, log.items[0].evidence);
}
