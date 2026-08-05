//! Pass 13 — Development Control Plane (canonical schemas + local-first state).
//!
//! Markdown explains; this module owns machine-readable snapshots, work items,
//! claim leases, audit events, and context bundles.
const std = @import("std");
const pass12_catalog = @import("pass12_catalog.zig");
const proof_carrying = @import("proof_carrying.zig");
const host_run = @import("host_run.zig");

pub const SCHEMA_VERSION = "dev-control-plane-v0";
pub const STATE_DIR = ".duo/dev";
pub const STATE_PATH = ".duo/dev/control_plane.json";
pub const EVENTS_PATH = ".duo/dev/events.jsonl";

pub const WorkItemState = enum {
    proposed,
    triaged,
    blocked,
    ready,
    claimed,
    in_progress,
    validating,
    ready_for_integration,
    integrating,
    complete,
    rejected,
    superseded,
    abandoned,
    regressed,

    pub fn name(self: WorkItemState) []const u8 {
        return @tagName(self);
    }
};

pub const ClaimLeaseStatus = enum {
    active,
    suspended,
    expired,
    released,
    rejected,

    pub fn name(self: ClaimLeaseStatus) []const u8 {
        return @tagName(self);
    }
};

pub const ConflictDomain = enum {
    file,
    directory,
    grammar_production,
    descriptor_family,
    directive_path,
    transform_registry,
    target_registry,
    release_claim,
    generated_artifact,
    public_api,
    schema_field,

    pub fn name(self: ConflictDomain) []const u8 {
        return @tagName(self);
    }
};

pub const ScopedTarget = struct {
    domain: ConflictDomain,
    id: []const u8,
};

pub const ProjectSnapshot = struct {
    snapshot_id: []const u8,
    repo_revision: []const u8,
    dirty_fingerprint: []const u8,
    compiler_version: []const u8,
    schema_version: []const u8,
    grammar_version: []const u8,
    semantic_schema_version: []const u8,
    mcp_schema_version: []const u8,
    created_unix: i64,
};

pub const WorkItem = struct {
    id: []const u8,
    title: []const u8,
    owner: []const u8,
    semantic_target: []const u8,
    state: WorkItemState,
    priority: u8,
    /// Work items that must reach integration before this one (P13-WS5).
    depends_on: []const []const u8 = &.{},
    conflict_domains: []const ConflictDomain,
    required_validation: []const []const u8,
    acceptance: []const u8,
    integration_owner: []const u8,
};

pub const ClaimLease = struct {
    claim_id: []const u8,
    owner: []const u8,
    client: []const u8,
    snapshot_id: []const u8,
    work_item_id: ?[]const u8,
    base_revision: []const u8,
    targets: []const ScopedTarget,
    files: []const []const u8,
    permitted: []const []const u8,
    prohibited: []const []const u8,
    required_validation: []const []const u8,
    status: ClaimLeaseStatus,
    acquired_unix: i64,
    expires_unix: i64,
    heartbeat_unix: i64,
};

pub const ContextBundle = struct {
    bundle_id: []const u8,
    snapshot_id: []const u8,
    work_item_id: []const u8,
    fingerprint: u64,
    task: []const u8,
    owner: []const u8,
    semantic_entities: []const []const u8,
    likely_files: []const []const u8,
    active_claims: []const []const u8,
    forbidden: []const []const u8,
    required_validation: []const []const u8,
    completion_gate: []const u8,
    integration_owner: []const u8,
};

pub const AcquireClaimRequest = struct {
    owner: []const u8,
    client: []const u8,
    work_item_id: ?[]const u8 = null,
    files: []const []const u8,
    targets: []const ScopedTarget,
    ttl_seconds: i64 = 7200,
};

pub const OverlapConflict = struct {
    existing_claim_id: []const u8,
    domain: ConflictDomain,
    target_id: []const u8,
    reason: []const u8,
};

pub const ControlPlaneState = struct {
    schema: []const u8 = SCHEMA_VERSION,
    snapshot: ProjectSnapshot,
    work_items: []const WorkItem,
    claims: []ClaimLease,
    integrations: []IntegrationRecord,
};

pub const IntegrationStatus = enum {
    pending,
    ready_for_integration,
    integrating,
    integrated,
    rejected,

    pub fn name(self: IntegrationStatus) []const u8 {
        return @tagName(self);
    }
};

pub const IntegrationRecord = struct {
    integration_id: []const u8,
    work_item_id: []const u8,
    owner: []const u8,
    claim_id: ?[]const u8,
    status: IntegrationStatus,
    submitted_unix: i64,
    integrated_unix: ?i64,
};

pub const seed_work_items: []const WorkItem = &.{
    .{
        .id = "P13-WS2",
        .title = "Development schema (snapshot, work item, claim, session, validation)",
        .owner = "src/dev_control_plane.zig",
        .semantic_target = "dev-control-plane-v0",
        .state = .in_progress,
        .priority = 1,
        .conflict_domains = &.{ConflictDomain.schema_field},
        .required_validation = &.{ "zig build unit-test --summary all" },
        .acceptance = "duo dev snapshot + duo catalog pass13 export schemas",
        .integration_owner = "pass13_catalog",
    },
    .{
        .id = "P13-WS3",
        .title = "Claim lease service (acquire, heartbeat, overlap, expire)",
        .owner = "src/dev_control_plane.zig",
        .semantic_target = "claim-lease-v0",
        .state = .in_progress,
        .priority = 2,
        .depends_on = &.{"P13-WS2"},
        .conflict_domains = &.{ ConflictDomain.file, ConflictDomain.release_claim },
        .required_validation = &.{ "zig test src/dev_control_plane.zig" },
        .acceptance = "exclusive claims reject semantic overlap; stale snapshot rejected",
        .integration_owner = "duo-mcp/duo_shared.duo",
    },
    .{
        .id = "P13-WS4",
        .title = "Context compiler (bounded task bundles)",
        .owner = "src/dev_control_plane.zig",
        .semantic_target = "context-bundle-v0",
        .state = .in_progress,
        .priority = 3,
        .depends_on = &.{"P13-WS2"},
        .conflict_domains = &.{},
        .required_validation = &.{ "duo dev context P13-WS2" },
        .acceptance = "comprehension gate fields present in JSON bundle",
        .integration_owner = "duo-mcp",
    },
    .{
        .id = "P13-WS7",
        .title = "Impact and validation planner",
        .owner = "src/dev_validation_planner.zig",
        .semantic_target = "dev-validation-plan-v0",
        .state = .in_progress,
        .priority = 7,
        .depends_on = &.{"P13-WS2"},
        .conflict_domains = &.{},
        .required_validation = &.{ "zig test src/dev_validation_planner.zig", "duo dev validate plan --work-item P13-WS7" },
        .acceptance = "file/work-item paths emit deterministic validation gate lists",
        .integration_owner = "duo-mcp",
    },
    .{
        .id = "P13-WS8",
        .title = "Append-only audit log",
        .owner = "src/dev_control_plane.zig",
        .semantic_target = "dev-audit-log-v0",
        .state = .in_progress,
        .priority = 8,
        .depends_on = &.{"P13-WS3"},
        .conflict_domains = &.{},
        .required_validation = &.{ "duo dev claim acquire (writes events.jsonl)" },
        .acceptance = "claim lifecycle events append to .duo/dev/events.jsonl",
        .integration_owner = "pass13_catalog",
    },
    .{
        .id = "P13-WS9",
        .title = "Integration queue (implementation vs merged)",
        .owner = "src/dev_control_plane.zig",
        .semantic_target = "integration-queue-v0",
        .state = .in_progress,
        .priority = 9,
        .depends_on = &.{"P13-WS3"},
        .conflict_domains = &.{ConflictDomain.public_api},
        .required_validation = &.{ "duo dev integration list", "duo dev integration submit --work-item P13-WS9" },
        .acceptance = "submit/complete distinct from claim release; persisted in control_plane.json",
        .integration_owner = "pass13_catalog",
    },
    .{
        .id = "P13-WS10",
        .title = "Semantic presentation engine",
        .owner = "src/presentation_record.zig",
        .semantic_target = "presentation-record-v0",
        .state = .in_progress,
        .priority = 10,
        .depends_on = &.{"P13-WS2"},
        .conflict_domains = &.{ConflictDomain.public_api},
        .required_validation = &.{ "zig test src/presentation_record.zig" },
        .acceptance = "diagnostics derive from DiagnosticRecord; term is renderer",
        .integration_owner = "src/term.zig",
    },
    .{
        .id = "P13-WS18",
        .title = "Coordination migration off markdown buffers",
        .owner = "src/dev_control_plane.zig",
        .semantic_target = "coordination-projection",
        .state = .in_progress,
        .priority = 18,
        .depends_on = &.{ "P13-WS3", "P13-WS8" },
        .conflict_domains = &.{ConflictDomain.file},
        .required_validation = &.{ "5-agent stress test" },
        .acceptance = "active claims in control_plane.json; MD generated read-only",
        .integration_owner = "pass13_catalog",
    },
};

pub fn compilerVersionLabel() []const u8 {
    return "duo-dev";
}

fn nowUnix() i64 {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    const ts = std.Io.Timestamp.now(threaded.io(), .awake);
    return std.Io.Timestamp.toSeconds(ts);
}

pub fn readGitRevision(alloc: std.mem.Allocator) ![]const u8 {
    const out = host_run.runHostCommandArgs(alloc, &.{ "git", "rev-parse", "HEAD" }) orelse {
        return try alloc.dupe(u8, "unknown");
    };
    defer alloc.free(out.stdout);
    defer alloc.free(out.stderr);
    if (!out.ok) return try alloc.dupe(u8, "unknown");
    const rev = std.mem.trim(u8, out.stdout, " \t\n\r");
    return try alloc.dupe(u8, rev);
}

pub fn dirtyFingerprint(alloc: std.mem.Allocator) ![]const u8 {
    const out = host_run.runHostCommandArgs(alloc, &.{ "git", "status", "--porcelain" }) orelse {
        return try alloc.dupe(u8, "0000000000000000");
    };
    defer alloc.free(out.stdout);
    defer alloc.free(out.stderr);
    var h = std.hash.Wyhash.init(0);
    h.update(out.stdout);
    return try std.fmt.allocPrint(alloc, "{x:0>16}", .{h.final()});
}

pub fn buildProjectSnapshot(alloc: std.mem.Allocator) !ProjectSnapshot {
    const rev = try readGitRevision(alloc);
    errdefer alloc.free(rev);
    const dirty = try dirtyFingerprint(alloc);
    errdefer alloc.free(dirty);
    const snap_id = try std.fmt.allocPrint(alloc, "snap-{s}-{s}", .{ rev[0..@min(rev.len, 12)], dirty[0..8] });
    return .{
        .snapshot_id = snap_id,
        .repo_revision = rev,
        .dirty_fingerprint = dirty,
        .compiler_version = compilerVersionLabel(),
        .schema_version = SCHEMA_VERSION,
        .grammar_version = pass12_catalog.SCHEMA_VERSION,
        .semantic_schema_version = proof_carrying.SCHEMA_VERSION,
        .mcp_schema_version = "duo-mcp-adhoc",
        .created_unix = nowUnix(),
    };
}

pub fn fingerprintContext(parts: []const []const u8) u64 {
    var h = std.hash.Wyhash.init(0xD130DC00);
    for (parts) |p| h.update(p);
    return h.final();
}

pub fn findWorkItem(id: []const u8) ?WorkItem {
    for (seed_work_items) |wi| {
        if (std.mem.eql(u8, wi.id, id)) return wi;
    }
    return null;
}

pub fn detectOverlap(existing: ClaimLease, req: AcquireClaimRequest) ?OverlapConflict {
    if (existing.status != .active) return null;
    for (req.files) |f| {
        for (existing.files) |ef| {
            if (std.mem.eql(u8, f, ef) or std.mem.startsWith(u8, f, ef) or std.mem.startsWith(u8, ef, f)) {
                return .{
                    .existing_claim_id = existing.claim_id,
                    .domain = .file,
                    .target_id = f,
                    .reason = "file path overlaps active exclusive claim",
                };
            }
        }
    }
    for (req.targets) |t| {
        for (existing.targets) |et| {
            if (t.domain == et.domain and std.mem.eql(u8, t.id, et.id)) {
                return .{
                    .existing_claim_id = existing.claim_id,
                    .domain = t.domain,
                    .target_id = t.id,
                    .reason = "semantic target overlaps active exclusive claim",
                };
            }
        }
    }
    return null;
}

pub fn acquireClaim(alloc: std.mem.Allocator, state: *ControlPlaneState, req: AcquireClaimRequest) !ClaimLease {
    for (state.claims) |c| {
        if (detectOverlap(c, req)) |_| return error.ClaimOverlap;
    }
    const now = nowUnix();
    const claim_id = try std.fmt.allocPrint(alloc, "claim-{s}-{d}", .{ req.owner, now });
    var files = try alloc.alloc([]const u8, req.files.len);
    for (req.files, 0..) |f, i| files[i] = try alloc.dupe(u8, f);
    var targets = try alloc.alloc(ScopedTarget, req.targets.len);
    for (req.targets, 0..) |t, i| targets[i] = .{ .domain = t.domain, .id = try alloc.dupe(u8, t.id) };

    const lease = ClaimLease{
        .claim_id = claim_id,
        .owner = try alloc.dupe(u8, req.owner),
        .client = try alloc.dupe(u8, req.client),
        .snapshot_id = try alloc.dupe(u8, state.snapshot.snapshot_id),
        .work_item_id = if (req.work_item_id) |w| try alloc.dupe(u8, w) else null,
        .base_revision = try alloc.dupe(u8, state.snapshot.repo_revision),
        .targets = targets,
        .files = files,
        .permitted = &.{},
        .prohibited = &.{ "silent_backend_fallback", "markdown_claim_authority", "git_stash" },
        .required_validation = &.{},
        .status = .active,
        .acquired_unix = now,
        .expires_unix = now + req.ttl_seconds,
        .heartbeat_unix = now,
    };
    const new_claims = try alloc.alloc(ClaimLease, state.claims.len + 1);
    @memcpy(new_claims[0..state.claims.len], state.claims);
    new_claims[state.claims.len] = lease;
    alloc.free(state.claims);
    state.claims = new_claims;
    return lease;
}

pub fn activeClaimIds(alloc: std.mem.Allocator, state: ControlPlaneState) ![]const []const u8 {
    var ids: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer ids.deinit(alloc);
    for (state.claims) |c| {
        if (c.status == .active) try ids.append(alloc, c.claim_id);
    }
    return try ids.toOwnedSlice(alloc);
}

pub fn generateContextBundle(alloc: std.mem.Allocator, snapshot: ProjectSnapshot, work_id: []const u8, state: ?ControlPlaneState) !ContextBundle {
    const wi = findWorkItem(work_id) orelse return error.WorkItemNotFound;
    const bundle_id = try std.fmt.allocPrint(alloc, "ctx-{s}-{s}", .{ work_id, snapshot.snapshot_id[0..@min(snapshot.snapshot_id.len, 16)] });
    const fp = fingerprintContext(&.{ snapshot.snapshot_id, work_id, wi.semantic_target, wi.owner });
    const active = if (state) |s| try activeClaimIds(alloc, s) else &[_][]const u8{};
    return .{
        .bundle_id = bundle_id,
        .snapshot_id = try alloc.dupe(u8, snapshot.snapshot_id),
        .work_item_id = try alloc.dupe(u8, work_id),
        .fingerprint = fp,
        .task = try alloc.dupe(u8, wi.title),
        .owner = try alloc.dupe(u8, wi.owner),
        .semantic_entities = &.{wi.semantic_target},
        .likely_files = &.{wi.owner},
        .active_claims = active,
        .forbidden = &.{
            "duplicate coordination markdown authority",
            "unregistered @comp.* combinators",
            "lua_Value on typed paths",
        },
        .required_validation = wi.required_validation,
        .completion_gate = wi.acceptance,
        .integration_owner = wi.integration_owner,
    };
}

pub fn freshState(alloc: std.mem.Allocator) !ControlPlaneState {
    const snap = try buildProjectSnapshot(alloc);
    return .{
        .snapshot = snap,
        .work_items = seed_work_items,
        .claims = try alloc.alloc(ClaimLease, 0),
        .integrations = try alloc.alloc(IntegrationRecord, 0),
    };
}

pub fn writeSnapshotJson(w: *std.Io.Writer, snap: ProjectSnapshot) !void {
    try w.print(
        "{{\"snapshot_id\":\"{s}\",\"repo_revision\":\"{s}\",\"dirty_fingerprint\":\"{s}\",\"compiler_version\":\"{s}\",\"schema_version\":\"{s}\",\"grammar_version\":\"{s}\",\"semantic_schema_version\":\"{s}\",\"mcp_schema_version\":\"{s}\",\"created_unix\":{d}}}",
        .{
            snap.snapshot_id,
            snap.repo_revision,
            snap.dirty_fingerprint,
            snap.compiler_version,
            snap.schema_version,
            snap.grammar_version,
            snap.semantic_schema_version,
            snap.mcp_schema_version,
            snap.created_unix,
        },
    );
}

pub fn writeContextBundleJson(w: *std.Io.Writer, b: ContextBundle) !void {
    try w.print("{{\"bundle_id\":\"{s}\",\"snapshot_id\":\"{s}\",\"work_item_id\":\"{s}\",\"fingerprint\":\"{x}\",\"task\":\"{s}\",\"owner\":\"{s}\",\"completion_gate\":\"{s}\",\"integration_owner\":\"{s}\",\"forbidden\":[", .{
        b.bundle_id, b.snapshot_id, b.work_item_id, b.fingerprint, b.task, b.owner, b.completion_gate, b.integration_owner,
    });
    for (b.forbidden, 0..) |f, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("\"{s}\"", .{f});
    }
    try w.writeAll("],\"required_validation\":[");
    for (b.required_validation, 0..) |v, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("\"{s}\"", .{v});
    }
    try w.writeAll("],\"active_claims\":[");
    for (b.active_claims, 0..) |c, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("\"{s}\"", .{c});
    }
    try w.writeAll("]}");
}

pub fn writeControlPlaneSummaryJson(w: *std.Io.Writer, state: ControlPlaneState) !void {
    try w.print("{{\"schema\":\"{s}\",\"snapshot\":", .{state.schema});
    try writeSnapshotJson(w, state.snapshot);
    try w.print(",\"active_claims\":{d},\"integrations\":{d},\"work_items\":{d}", .{ state.claims.len, state.integrations.len, state.work_items.len });
    try w.writeAll("}");
}

pub const AuditEvent = struct {
    event_id: []const u8,
    kind: []const u8,
    agent: []const u8,
    detail: []const u8,
    unix: i64,
};

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

fn parseClaimStatus(name: []const u8) ClaimLeaseStatus {
    inline for (@typeInfo(ClaimLeaseStatus).@"enum".field_names, @typeInfo(ClaimLeaseStatus).@"enum".field_values) |n, v| {
        if (std.mem.eql(u8, n, name)) return @enumFromInt(v);
    }
    return .expired;
}

fn parseConflictDomain(name: []const u8) ?ConflictDomain {
    inline for (@typeInfo(ConflictDomain).@"enum".field_names, @typeInfo(ConflictDomain).@"enum".field_values) |n, v| {
        if (std.mem.eql(u8, n, name)) return @enumFromInt(v);
    }
    return null;
}

const JsonScopedTarget = struct {
    domain: []const u8,
    id: []const u8,
};

const JsonClaim = struct {
    claim_id: []const u8,
    owner: []const u8,
    client: []const u8,
    snapshot_id: []const u8,
    work_item_id: ?[]const u8 = null,
    base_revision: []const u8,
    files: []const []const u8,
    targets: []const JsonScopedTarget = &.{},
    status: []const u8,
    acquired_unix: i64,
    expires_unix: i64,
    heartbeat_unix: i64,
};

const JsonIntegration = struct {
    integration_id: []const u8,
    work_item_id: []const u8,
    owner: []const u8,
    claim_id: ?[]const u8 = null,
    status: []const u8,
    submitted_unix: i64,
    integrated_unix: ?i64 = null,
};

const JsonStateFile = struct {
    schema: []const u8,
    snapshot: struct {
        snapshot_id: []const u8,
        repo_revision: []const u8,
        dirty_fingerprint: []const u8,
        compiler_version: []const u8,
        schema_version: []const u8,
        grammar_version: []const u8,
        semantic_schema_version: []const u8,
        mcp_schema_version: []const u8,
        created_unix: i64,
    },
    claims: []JsonClaim = &.{},
    integrations: []JsonIntegration = &.{},
};

fn parseIntegrationStatus(name: []const u8) IntegrationStatus {
    inline for (@typeInfo(IntegrationStatus).@"enum".field_names, @typeInfo(IntegrationStatus).@"enum".field_values) |n, v| {
        if (std.mem.eql(u8, n, name)) return @enumFromInt(v);
    }
    return .pending;
}

fn dupIntegration(alloc: std.mem.Allocator, ji: JsonIntegration) !IntegrationRecord {
    return .{
        .integration_id = try alloc.dupe(u8, ji.integration_id),
        .work_item_id = try alloc.dupe(u8, ji.work_item_id),
        .owner = try alloc.dupe(u8, ji.owner),
        .claim_id = if (ji.claim_id) |c| try alloc.dupe(u8, c) else null,
        .status = parseIntegrationStatus(ji.status),
        .submitted_unix = ji.submitted_unix,
        .integrated_unix = ji.integrated_unix,
    };
}

pub fn submitIntegration(alloc: std.mem.Allocator, state: *ControlPlaneState, work_item_id: []const u8, owner: []const u8, claim_id: ?[]const u8) !IntegrationRecord {
    _ = findWorkItem(work_item_id) orelse return error.WorkItemNotFound;
    const now = nowUnix();
    const integration_id = try std.fmt.allocPrint(alloc, "int-{s}-{d}", .{ work_item_id, now });
    const rec = IntegrationRecord{
        .integration_id = integration_id,
        .work_item_id = try alloc.dupe(u8, work_item_id),
        .owner = try alloc.dupe(u8, owner),
        .claim_id = if (claim_id) |c| try alloc.dupe(u8, c) else null,
        .status = .ready_for_integration,
        .submitted_unix = now,
        .integrated_unix = null,
    };
    const new_list = try alloc.alloc(IntegrationRecord, state.integrations.len + 1);
    @memcpy(new_list[0..state.integrations.len], state.integrations);
    new_list[state.integrations.len] = rec;
    alloc.free(state.integrations);
    state.integrations = new_list;
    return rec;
}

pub fn completeIntegration(state: *ControlPlaneState, integration_id: []const u8) !void {
    for (state.integrations) |*r| {
        if (std.mem.eql(u8, r.integration_id, integration_id)) {
            r.status = .integrated;
            r.integrated_unix = nowUnix();
            return;
        }
    }
    return error.IntegrationNotFound;
}

pub fn writeIntegrationJson(w: *std.Io.Writer, r: IntegrationRecord) !void {
    try w.print("{{\"integration_id\":\"{s}\",\"work_item_id\":\"{s}\",\"owner\":\"{s}\",\"status\":\"{s}\",\"submitted_unix\":{d}", .{
        r.integration_id, r.work_item_id, r.owner, r.status.name(), r.submitted_unix,
    });
    if (r.claim_id) |c| try w.print(",\"claim_id\":\"{s}\"", .{c});
    if (r.integrated_unix) |t| try w.print(",\"integrated_unix\":{d}", .{t});
    try w.writeAll("}");
}

pub fn writeIntegrationsListJson(w: *std.Io.Writer, state: ControlPlaneState) !void {
    try w.writeAll("[");
    for (state.integrations, 0..) |r, i| {
        if (i > 0) try w.writeAll(",");
        try writeIntegrationJson(w, r);
    }
    try w.writeAll("]");
}

pub fn ensureStateDir(io: std.Io) !void {
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, STATE_DIR);
}

pub fn expireStaleClaims(state: *ControlPlaneState) void {
    const now = nowUnix();
    for (state.claims) |*c| {
        if (c.status == .active and c.expires_unix <= now) c.status = .expired;
    }
}

pub fn releaseClaim(state: *ControlPlaneState, claim_id: []const u8) !void {
    for (state.claims) |*c| {
        if (std.mem.eql(u8, c.claim_id, claim_id)) {
            c.status = .released;
            return;
        }
    }
    return error.ClaimNotFound;
}

/// Release lease and enqueue integration when the claim carries a work item.
pub fn releaseClaimWithIntegration(alloc: std.mem.Allocator, state: *ControlPlaneState, claim_id: []const u8) !?IntegrationRecord {
    for (state.claims) |*c| {
        if (std.mem.eql(u8, c.claim_id, claim_id)) {
            const owner = c.owner;
            const work_item = c.work_item_id;
            c.status = .released;
            if (work_item) |wi| return try submitIntegration(alloc, state, wi, owner, claim_id);
            return null;
        }
    }
    return error.ClaimNotFound;
}

pub fn heartbeatClaim(state: *ControlPlaneState, claim_id: []const u8, ttl_seconds: i64) !void {
    const now = nowUnix();
    for (state.claims) |*c| {
        if (std.mem.eql(u8, c.claim_id, claim_id)) {
            if (c.status != .active) return error.ClaimNotActive;
            c.heartbeat_unix = now;
            c.expires_unix = now + ttl_seconds;
            return;
        }
    }
    return error.ClaimNotFound;
}

fn dupClaimLease(alloc: std.mem.Allocator, jc: JsonClaim) !ClaimLease {
    var files = try alloc.alloc([]const u8, jc.files.len);
    for (jc.files, 0..) |f, i| files[i] = try alloc.dupe(u8, f);
    var targets = try alloc.alloc(ScopedTarget, jc.targets.len);
    for (jc.targets, 0..) |t, i| {
        const domain = parseConflictDomain(t.domain) orelse .file;
        targets[i] = .{ .domain = domain, .id = try alloc.dupe(u8, t.id) };
    }
    return .{
        .claim_id = try alloc.dupe(u8, jc.claim_id),
        .owner = try alloc.dupe(u8, jc.owner),
        .client = try alloc.dupe(u8, jc.client),
        .snapshot_id = try alloc.dupe(u8, jc.snapshot_id),
        .work_item_id = if (jc.work_item_id) |w| try alloc.dupe(u8, w) else null,
        .base_revision = try alloc.dupe(u8, jc.base_revision),
        .targets = targets,
        .files = files,
        .permitted = &.{},
        .prohibited = &.{ "silent_backend_fallback", "markdown_claim_authority", "git_stash" },
        .required_validation = &.{},
        .status = parseClaimStatus(jc.status),
        .acquired_unix = jc.acquired_unix,
        .expires_unix = jc.expires_unix,
        .heartbeat_unix = jc.heartbeat_unix,
    };
}

pub fn writeClaimJson(w: *std.Io.Writer, c: ClaimLease) !void {
    try w.print("{{\"claim_id\":\"{s}\",\"owner\":\"{s}\",\"client\":\"{s}\",\"snapshot_id\":\"{s}\",\"base_revision\":\"{s}\",\"status\":\"{s}\",\"acquired_unix\":{d},\"expires_unix\":{d},\"heartbeat_unix\":{d}", .{
        c.claim_id, c.owner, c.client, c.snapshot_id, c.base_revision, c.status.name(), c.acquired_unix, c.expires_unix, c.heartbeat_unix,
    });
    if (c.work_item_id) |witem| {
        try w.print(",\"work_item_id\":\"{s}\"", .{witem});
    }
    try w.writeAll(",\"files\":[");
    for (c.files, 0..) |f, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("\"{s}\"", .{f});
    }
    try w.writeAll("],\"targets\":[");
    for (c.targets, 0..) |t, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"domain\":\"{s}\",\"id\":\"{s}\"}}", .{ t.domain.name(), t.id });
    }
    try w.writeAll("]}");
}

pub fn writeStateJson(w: *std.Io.Writer, state: ControlPlaneState) !void {
    try w.print("{{\"schema\":\"{s}\",\"snapshot\":", .{state.schema});
    try writeSnapshotJson(w, state.snapshot);
    try w.writeAll(",\"claims\":[");
    for (state.claims, 0..) |c, i| {
        if (i > 0) try w.writeAll(",");
        try writeClaimJson(w, c);
    }
    try w.writeAll("],\"integrations\":[");
    for (state.integrations, 0..) |r, i| {
        if (i > 0) try w.writeAll(",");
        try writeIntegrationJson(w, r);
    }
    try w.writeAll("]}");
}

pub fn loadState(alloc: std.mem.Allocator, io: std.Io) !ControlPlaneState {
    const cwd = std.Io.Dir.cwd();
    const data = std.Io.Dir.readFileAlloc(cwd, io, STATE_PATH, alloc, .unlimited) catch |err| switch (err) {
        error.FileNotFound => return try freshState(alloc),
        else => return err,
    };
    defer alloc.free(data);
    var parsed = try std.json.parseFromSlice(JsonStateFile, alloc, data, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.schema, SCHEMA_VERSION)) return try freshState(alloc);
    var claims = try alloc.alloc(ClaimLease, parsed.value.claims.len);
    errdefer alloc.free(claims);
    for (parsed.value.claims, 0..) |jc, i| claims[i] = try dupClaimLease(alloc, jc);
    var integrations = try alloc.alloc(IntegrationRecord, parsed.value.integrations.len);
    errdefer alloc.free(integrations);
    for (parsed.value.integrations, 0..) |ji, i| integrations[i] = try dupIntegration(alloc, ji);
    const snap = try buildProjectSnapshot(alloc);
    var state = ControlPlaneState{
        .snapshot = snap,
        .work_items = seed_work_items,
        .claims = claims,
        .integrations = integrations,
    };
    expireStaleClaims(&state);
    return state;
}

pub fn saveState(alloc: std.mem.Allocator, io: std.Io, state: *ControlPlaneState) !void {
    try ensureStateDir(io);
    expireStaleClaims(state);
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try writeStateJson(&aw.writer, state.*);
    const cwd = std.Io.Dir.cwd();
    try std.Io.Dir.writeFile(cwd, io, .{ .sub_path = STATE_PATH, .data = aw.written() });
}

pub fn appendAuditEvent(alloc: std.mem.Allocator, io: std.Io, kind: []const u8, agent: []const u8, detail: []const u8) !void {
    try ensureStateDir(io);
    const event_id = try std.fmt.allocPrint(alloc, "evt-{d}", .{nowUnix()});
    defer alloc.free(event_id);
    var line: std.Io.Writer.Allocating = .init(alloc);
    defer line.deinit();
    try line.writer.print(
        "{{\"event_id\":\"{s}\",\"kind\":\"{s}\",\"agent\":\"{s}\",\"detail\":\"",
        .{ event_id, kind, agent },
    );
    try jsonEscape(&line.writer, detail);
    try line.writer.print("\",\"unix\":{d}}}\n", .{nowUnix()});
    const cwd = std.Io.Dir.cwd();
    const prior = std.Io.Dir.readFileAlloc(cwd, io, EVENTS_PATH, alloc, .unlimited) catch |err| switch (err) {
        error.FileNotFound => try alloc.dupe(u8, ""),
        else => return err,
    };
    defer alloc.free(prior);
    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    try out.writer.writeAll(prior);
    try out.writer.writeAll(line.written());
    try std.Io.Dir.writeFile(cwd, io, .{ .sub_path = EVENTS_PATH, .data = out.written() });
}

pub fn writeClaimsListJson(w: *std.Io.Writer, state: ControlPlaneState) !void {
    try w.writeAll("[");
    for (state.claims, 0..) |c, i| {
        if (i > 0) try w.writeAll(",");
        try writeClaimJson(w, c);
    }
    try w.writeAll("]");
}

pub fn devFlagValue(args: []const []const u8, flag: []const u8) ?[]const u8 {
    for (args, 0..) |a, i| {
        if (std.mem.eql(u8, a, flag) and i + 1 < args.len) return args[i + 1];
        if (std.mem.startsWith(u8, a, flag)) {
            if (a.len > flag.len and a[flag.len] == '=') return a[flag.len + 1 ..];
        }
    }
    return null;
}

pub fn writeWorkGraphJson(w: *std.Io.Writer) !void {
    try w.writeAll("{\"schema\":\"work-graph-v0\",\"items\":[");
    for (seed_work_items, 0..) |wi, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"state\":\"{s}\",\"priority\":{d},\"depends_on\":[", .{
            wi.id, wi.state.name(), wi.priority,
        });
        for (wi.depends_on, 0..) |dep, di| {
            if (di > 0) try w.writeAll(",");
            try w.print("\"{s}\"", .{dep});
        }
        try w.writeAll("]}");
    }
    try w.writeAll("]}");
}

pub fn writeCoordinationExportJson(w: *std.Io.Writer, state: ControlPlaneState) !void {
    try w.print("{{\"schema\":\"coordination-export-v0\",\"authority\":\"dev_control_plane\",\"markdown_buffer\":\".agents/AGENT_COORDINATION.md\",\"markdown_authority\":false,\"snapshot\":", .{});
    try writeSnapshotJson(w, state.snapshot);
    try w.writeAll(",\"active_claims\":[");
    var first = true;
    for (state.claims) |c| {
        if (c.status != .active) continue;
        if (!first) try w.writeAll(",");
        first = false;
        try writeClaimJson(w, c);
    }
    try w.writeAll("],\"work_items\":[");
    for (seed_work_items, 0..) |wi, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"id\":\"{s}\",\"state\":\"{s}\",\"owner\":\"{s}\"}}", .{ wi.id, wi.state.name(), wi.owner });
    }
    try w.writeAll("]}");
}

/// P13-WS18 — generated markdown view (machine authority remains JSON state).
pub fn writeCoordinationMarkdown(w: *std.Io.Writer, state: ControlPlaneState) !void {
    try w.writeAll("<!-- GENERATED by duo dev coordination render — do not edit claims here -->\n");
    try w.writeAll("## Active claim leases (machine authority: .duo/dev/control_plane.json)\n\n");
    var any = false;
    for (state.claims) |c| {
        if (c.status != .active) continue;
        any = true;
        try w.print("- **{s}** owner=`{s}` client=`{s}` expires={d}", .{ c.claim_id, c.owner, c.client, c.expires_unix });
        if (c.work_item_id) |wi| try w.print(" work_item=`{s}`", .{wi});
        try w.writeAll("\n  files:");
        for (c.files) |f| try w.print(" `{s}`", .{f});
        try w.writeAll("\n");
    }
    if (!any) try w.writeAll("_No active claims._\n");
    try w.writeAll("\n## Seed work items\n\n");
    for (seed_work_items) |wi| {
        try w.print("- **{s}** — {s} (`{s}`)\n", .{ wi.id, wi.title, wi.state.name() });
    }
    try w.print("\n_snapshot: `{s}` @ `{s}`_\n", .{ state.snapshot.snapshot_id, state.snapshot.repo_revision });
}

pub fn writeCoordinationStatusJson(w: *std.Io.Writer, state: ControlPlaneState) !void {
    var active: usize = 0;
    for (state.claims) |c| {
        if (c.status == .active) active += 1;
    }
    try w.print(
        "{{\"schema\":\"coordination-status-v0\",\"machine_authority\":\"{s}\",\"event_log\":\"{s}\",\"markdown_buffer\":\".agents/AGENT_COORDINATION.md\",\"markdown_claim_authority\":false,\"migration_workstream\":\"P13-WS18\",\"active_claims\":{d},\"seed_work_items\":{d},\"recommended_session\":\"duo dev session start --owner <agent> --work-item P13-WS3\"}}",
        .{ STATE_PATH, EVENTS_PATH, active, seed_work_items.len },
    );
}

test "dev_control_plane: work graph includes dependencies" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try writeWorkGraphJson(&buf.writer);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "P13-WS3") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "P13-WS2") != null);
}

test "dev_control_plane: claim overlap on file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var state = try freshState(alloc);
    _ = try acquireClaim(alloc, &state, .{
        .owner = "agent-a",
        .client = "cursor",
        .files = &.{"src/codegen.zig"},
        .targets = &.{},
    });
    const result = acquireClaim(alloc, &state, .{
        .owner = "agent-b",
        .client = "codex",
        .files = &.{"src/codegen.zig"},
        .targets = &.{},
    });
    try std.testing.expectError(error.ClaimOverlap, result);
}

test "dev_control_plane: context bundle for P13-WS2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const snap = try buildProjectSnapshot(alloc);
    const bundle = try generateContextBundle(alloc, snap, "P13-WS2", null);
    try std.testing.expect(std.mem.eql(u8, bundle.work_item_id, "P13-WS2"));
    try std.testing.expect(bundle.fingerprint != 0);
}

test "dev_control_plane: save and load round trip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var threaded = std.Io.Threaded.init(alloc, .{});
    const io = threaded.io();
    var state = try freshState(alloc);
    _ = try acquireClaim(alloc, &state, .{
        .owner = "cursor",
        .client = "test",
        .files = &.{"src/dev_control_plane.zig"},
        .targets = &.{.{ .domain = .file, .id = "dev-control-plane-v0" }},
    });
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try writeStateJson(&aw.writer, state);
    var parsed = try std.json.parseFromSlice(JsonStateFile, alloc, aw.written(), .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 1), parsed.value.claims.len);
    try std.testing.expectEqualStrings("cursor", parsed.value.claims[0].owner);
    _ = io;
}

test "dev_control_plane: heartbeat extends lease" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var state = try freshState(alloc);
    const lease = try acquireClaim(alloc, &state, .{
        .owner = "agent-a",
        .client = "cursor",
        .files = &.{"src/codegen.zig"},
        .targets = &.{},
        .ttl_seconds = 60,
    });
    const before = lease.expires_unix;
    try heartbeatClaim(&state, lease.claim_id, 3600);
    try std.testing.expect(state.claims[0].expires_unix > before);
}

test "dev_control_plane: release claim" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var state = try freshState(alloc);
    const lease = try acquireClaim(alloc, &state, .{
        .owner = "agent-a",
        .client = "cursor",
        .files = &.{"src/codegen.zig"},
        .targets = &.{},
    });
    try releaseClaim(&state, lease.claim_id);
    try std.testing.expectEqual(ClaimLeaseStatus.released, state.claims[0].status);
}

test "dev_control_plane: integration submit and complete" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var state = try freshState(alloc);
    const rec = try submitIntegration(alloc, &state, "P13-WS9", "cursor", null);
    try std.testing.expectEqual(IntegrationStatus.ready_for_integration, rec.status);
    try completeIntegration(&state, rec.integration_id);
    try std.testing.expectEqual(IntegrationStatus.integrated, state.integrations[0].status);
    try std.testing.expect(state.integrations[0].integrated_unix != null);
}

test "dev_control_plane: semantic overlap on domain" {
    const existing = ClaimLease{
        .claim_id = "c1",
        .owner = "a",
        .client = "x",
        .snapshot_id = "s",
        .work_item_id = null,
        .base_revision = "r",
        .targets = &.{.{ .domain = .directive_path, .id = "comp.tensor" }},
        .files = &.{},
        .permitted = &.{},
        .prohibited = &.{},
        .required_validation = &.{},
        .status = .active,
        .acquired_unix = 0,
        .expires_unix = 999,
        .heartbeat_unix = 0,
    };
    const req = AcquireClaimRequest{
        .owner = "b",
        .client = "y",
        .files = &.{},
        .targets = &.{.{ .domain = .directive_path, .id = "comp.tensor" }},
    };
    const conflict = detectOverlap(existing, req);
    try std.testing.expect(conflict != null);
}
