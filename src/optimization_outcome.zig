//! — structured optimization / transformation outcome records.
//!
//! Complements `transform_engine` provenance hashes with agent-consumable outcomes.
const std = @import("std");
const transform_engine = @import("transform_engine.zig");
const semantic_algebra = @import("semantic_algebra.zig");
const proof_carrying = @import("proof_carrying.zig");
const effect = @import("effect.zig");

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

/// Evidence strength for an optimization claim (§10.1).
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
    /// P2/GAP-137: exact graph coordinates carried from provenance so
    /// transformed applications remain traceable without hash-only reconstruction.
    graph: ?proof_carrying.GraphEntity = null,

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
///
/// GAP-182 graph-owned enforcement face (`law.oracle.bounded`): each entry's
/// own evidence — not a blanket label — decides the outcome. An entry whose
/// evidence maps to an evidence-level epistemic category (profile, benchmark,
/// heuristic, target estimate) can never be recorded as an applied
/// semantics-changing transformation on profile evidence alone: it is
/// converted to a `profile_insufficient` rejection naming the guard or proof
/// the realization still demands. Sound evidence (semantic proof, runtime
/// guard, or an admitted foreign assertion) converts to `.proven` exactly as
/// before, so existing explain output for sound entries is unchanged.
pub fn fromProvenance(alloc: std.mem.Allocator) !OutcomeLog {
    const entries = transform_engine.provenanceEntries();
    var items: std.ArrayListUnmanaged(Outcome) = .empty;
    errdefer {
        for (items.items) |*o| o.deinit(alloc);
        items.deinit(alloc);
    }
    for (entries) |e| {
        const level = effect.levelForTransformEvidence(e.evidence);
        const applied = effect.producesTruthLevel(level);
        try items.append(alloc, .{
            .transformation = try alloc.dupe(u8, e.public_name),
            .entity = null,
            .status = if (applied) .applied else .profile_insufficient,
            .evidence = if (applied) .proven else effect.outcomeEvidenceForTransformEvidence(e.evidence),
            .site = e.site,
            .reason = if (applied) null else try insufficientReason(alloc, e.public_name, e.evidence),
            .before_repr = null,
            .after_repr = null,
            .inputs_hash = e.inputs_hash,
            .output_hash = e.output_hash,
            .graph = e.graph,
        });
    }
    return .{ .items = try items.toOwnedSlice(alloc) };
}

/// The rejection reason names the guard-or-proof demand — one construction
/// seam, structured fields, never a plain status integer crossing the seam
/// (`law.magic.code.zero`).
fn insufficientReason(
    alloc: std.mem.Allocator,
    public_name: []const u8,
    evidence: transform_engine.Evidence,
) ![]const u8 {
    return std.fmt.allocPrint(
        alloc,
        "evidence '{s}' is observation, not truth: realization '{s}' demands a guard or proof before it may apply",
        .{ evidence.name(), public_name },
    );
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
            .graph = src.graph,
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
        if (o.graph) |g| {
            try w.print(
                ",\"graph\":{{\"relation\":{?d},\"application\":{?d},\"subject\":{?d},\"input_value\":{?d},\"output_value\":{?d}}}",
                .{ g.relation, g.application, g.subject, g.input_value, g.output_value },
            );
        }
        try w.print("}}", .{});
    }
    try w.print("]}}", .{});
}

pub fn writeJsonLine(log: *const OutcomeLog, w: *std.Io.Writer) !void {
    try writeJson(log, w);
    try w.print("\n", .{});
}

test "effect: transform evidence levels are refused as outcome truth (GAP-182 order 5)" {
    // Graph-owned enforcement face: the level bridge answers per kind
    // (`law.oracle.bounded`). Sound kinds admit; observation and estimate
    // kinds never do.
    try std.testing.expect(effect.producesTruthLevel(
        effect.levelForTransformEvidence(.semantic_proof),
    ));
    try std.testing.expect(effect.producesTruthLevel(
        effect.levelForTransformEvidence(.imported),
    ));
    try std.testing.expect(!effect.producesTruthLevel(
        effect.levelForTransformEvidence(.guarded),
    ));
    try std.testing.expect(!effect.producesTruthLevel(
        effect.levelForTransformEvidence(.profile),
    ));
    try std.testing.expect(!effect.producesTruthLevel(
        effect.levelForTransformEvidence(.benchmark),
    ));
    try std.testing.expect(!effect.producesTruthLevel(
        effect.levelForTransformEvidence(.static_estimate),
    ));
    try std.testing.expect(!effect.producesTruthLevel(
        effect.levelForTransformEvidence(.target_estimate),
    ));
    try std.testing.expect(!effect.producesTruthLevel(
        effect.levelForTransformEvidence(.user_assertion),
    ));
    try std.testing.expect(!effect.producesTruthLevel(
        effect.levelForTransformEvidence(.heuristic),
    ));
}

test "effect: evidence-level provenance cannot apply (GAP-182 order 5)" {
    const alloc = std.testing.allocator;
    defer deinitSession(alloc);
    transform_engine.deinitProvenance(alloc);
    transform_engine.setProvenanceEnabled(true);
    // The engine log face stamps `heuristic` unless a caller names evidence;
    // `heuristic` is an evidence level, so the conversion must refuse it as
    // applied truth and record the guard-or-proof demand instead.
    transform_engine.logProvenance(alloc, "comp.why.boxed", .emit_call, 1, 2);
    var log = try fromProvenance(alloc);
    defer log.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 1), log.items.len);
    try std.testing.expectEqualStrings("comp.why.boxed", log.items[0].transformation);
    try std.testing.expectEqual(Status.profile_insufficient, log.items[0].status);
    try std.testing.expect(!effect.producesTruthLevel(
        effect.levelForOutcomeEvidence(log.items[0].evidence),
    ));
    try std.testing.expect(log.items[0].reason != null);
    try std.testing.expect(
        std.mem.indexOf(u8, log.items[0].reason.?, "demands a guard or proof") != null,
    );
    // The recorded evidence names WHAT was observed, never the truth it
    // cannot carry (`law.oracle.bounded`).
    try std.testing.expectEqualStrings("estimated", log.items[0].evidence.name());
}
