//! — unified evidence model for realization decisions and persistent facts.
//!
//! Canonical owner for evidence classification. Extends `optimization_outcome.Evidence`
//! without duplicating optimization outcome records.
const std = @import("std");
const optimization_outcome = @import("optimization_outcome.zig");

/// Reliability class for compiler claims (§4.6, §6).
pub const Kind = enum(u8) {
    proven_semantic_fact,
    guarded_fact,
    static_estimate,
    target_model_estimate,
    profile_observation,
    benchmark_measurement,
    production_observation,
    user_assertion,
    foreign_assertion,
    differential_test,
    fuzz_evidence,
    property_test,
    numerical_validation,

    pub fn name(self: Kind) []const u8 {
        return switch (self) {
            .proven_semantic_fact => "proven_semantic_fact",
            .guarded_fact => "guarded_fact",
            .static_estimate => "static_estimate",
            .target_model_estimate => "target_model_estimate",
            .profile_observation => "profile_observation",
            .benchmark_measurement => "benchmark_measurement",
            .production_observation => "production_observation",
            .user_assertion => "user_assertion",
            .foreign_assertion => "foreign_assertion",
            .differential_test => "differential_test",
            .fuzz_evidence => "fuzz_evidence",
            .property_test => "property_test",
            .numerical_validation => "numerical_validation",
        };
    }

    /// Observations must not silently become semantic guarantees.
    pub fn mayAuthorizeOptimization(self: Kind) bool {
        return switch (self) {
            .proven_semantic_fact, .guarded_fact, .differential_test, .property_test, .numerical_validation => true,
            .static_estimate, .target_model_estimate => true,
            .profile_observation, .benchmark_measurement, .production_observation => false,
            .user_assertion, .foreign_assertion => false,
            .fuzz_evidence => false,
        };
    }
};

pub const FrontierStatus = enum(u8) {
    win,
    bound,
    open,
    unknownbound,

    pub fn name(self: FrontierStatus) []const u8 {
        return switch (self) {
            .win => "win",
            .bound => "bound",
            .open => "open",
            .unknownbound => "unknownbound",
        };
    }
};

pub const FrontierDeclaration = enum(u8) {
    absent,
    present,
};

pub const DebtCause = enum(u8) {
    missing_fact,
    missing_demand,
    missing_law,
    missing_candidate,
    missing_search,
    missing_proof,
    wrong_cost_model,
    wrong_placement,
    wrong_algorithm,
    wrong_representation,

    pub fn name(self: DebtCause) []const u8 {
        return switch (self) {
            .missing_fact => "missing-fact",
            .missing_demand => "missing-demand",
            .missing_law => "missing-law",
            .missing_candidate => "missing-candidate",
            .missing_search => "missing-search",
            .missing_proof => "missing-proof",
            .wrong_cost_model => "wrong-cost-model",
            .wrong_placement => "wrong-placement",
            .wrong_algorithm => "wrong-algorithm",
            .wrong_representation => "wrong-representation",
        };
    }
};

pub const Direction = enum(u8) {
    minimize,
    maximize,

    pub fn name(self: Direction) []const u8 {
        return switch (self) {
            .minimize => "minimize",
            .maximize => "maximize",
        };
    }
};

pub const Oracle = struct {
    name: []const u8,
    revision: []const u8,
    configuration: []const u8,
    evidence: []const u8,

    pub fn validate(self: Oracle) FrontierError!void {
        if (self.name.len == 0) return error.MissingOracleName;
        if (self.revision.len == 0) return error.MissingOracleRevision;
        if (self.configuration.len == 0) return error.MissingOracleConfiguration;
        if (self.evidence.len == 0) return error.MissingOracleEvidence;
    }
};

pub const FrontierContext = struct {
    world: []const u8,
    target: []const u8,
    workload: []const u8,
    observations: []const []const u8,

    pub fn validate(self: FrontierContext) FrontierError!void {
        if (self.world.len == 0) return error.MissingWorld;
        if (self.target.len == 0) return error.MissingTarget;
        if (self.workload.len == 0) return error.MissingWorkload;
        if (self.observations.len == 0) return error.MissingObservations;
    }
};

pub const Interval = struct {
    low: f64,
    high: f64,

    pub fn exact(value: f64) Interval {
        return .{ .low = value, .high = value };
    }

    fn valid(self: Interval) bool {
        return std.math.isFinite(self.low) and std.math.isFinite(self.high) and self.low <= self.high;
    }

    fn overlaps(self: Interval, other: Interval) bool {
        return self.low <= other.high and other.low <= self.high;
    }

    fn eql(self: Interval, other: Interval) bool {
        return self.low == other.low and self.high == other.high;
    }
};

pub const FrontierError = error{
    MissingSubjectRevision,
    MissingEvidenceRevision,
    MissingEquivalence,
    MissingRawEvidence,
    MissingIntegration,
    MissingMeasurement,
    MissingCompilerB,
    MissingDimensions,
    MissingRequiredDimensions,
    MissingRequiredDimension,
    UnexpectedDimension,
    MissingCause,
    UnexpectedCause,
    MissingDimensionId,
    MissingUnit,
    InvalidInterval,
    DuplicateDimension,
    MissingOracle,
    MissingOracleName,
    MissingOracleRevision,
    MissingOracleConfiguration,
    MissingOracleEvidence,
    DuplicateOracle,
    MissingWorld,
    MissingTarget,
    MissingWorkload,
    MissingObservations,
    MissingContext,
};

pub const FrontierDimension = struct {
    id: []const u8,
    unit: []const u8,
    direction: Direction,
    candidate: Interval,
    competitor: Interval,
    lower_bound: ?Interval = null,
    improvable: bool,
    cause: ?DebtCause = null,

    pub fn status(self: FrontierDimension) FrontierError!FrontierStatus {
        if (self.id.len == 0) return error.MissingDimensionId;
        if (self.unit.len == 0) return error.MissingUnit;
        if (!self.candidate.valid() or !self.competitor.valid()) return error.InvalidInterval;
        if (self.lower_bound) |lower_bound| {
            if (!lower_bound.valid()) return error.InvalidInterval;
        }
        const better = switch (self.direction) {
            .minimize => self.candidate.high < self.competitor.low,
            .maximize => self.candidate.low > self.competitor.high,
        };
        const worse = switch (self.direction) {
            .minimize => self.candidate.low > self.competitor.high,
            .maximize => self.candidate.high < self.competitor.low,
        };

        const open_loss = worse and self.improvable;
        if (!open_loss and self.cause != null) return error.UnexpectedCause;
        if (open_loss) {
            if (self.cause == null) return error.MissingCause;
            return .open;
        }
        if (self.lower_bound) |lower_bound| {
            if (self.candidate.overlaps(lower_bound)) return .bound;
        }
        if (better) return .win;
        return .unknownbound;
    }
};

/// One independently attributed comparator point for a cost dimension.
/// The oracle remains external evidence; it never becomes a semantic producer.
pub const OraclePoint = struct {
    oracle: Oracle,
    interval: Interval,
};

/// A dimension compared against the complete discovered oracle envelope.
/// A candidate is not a frontier win while any attributed oracle still beats it.
pub const OracleFrontierDimension = struct {
    id: []const u8,
    unit: []const u8,
    direction: Direction,
    candidate: Interval,
    oracles: []const OraclePoint,
    lower_bound: ?Interval = null,
    improvable: bool,
    cause: ?DebtCause = null,

    pub fn status(self: OracleFrontierDimension) FrontierError!FrontierStatus {
        if (self.oracles.len == 0) return error.MissingOracle;

        var all_bound = true;
        var saw_win = false;
        var saw_unknown = false;
        for (self.oracles, 0..) |point, index| {
            try point.oracle.validate();
            for (self.oracles[index + 1 ..]) |other| {
                if (std.mem.eql(u8, point.oracle.name, other.oracle.name) and
                    std.mem.eql(u8, point.oracle.revision, other.oracle.revision) and
                    std.mem.eql(u8, point.oracle.configuration, other.oracle.configuration))
                {
                    return error.DuplicateOracle;
                }
            }

            const worse = switch (self.direction) {
                .minimize => self.candidate.low > point.interval.high,
                .maximize => self.candidate.high < point.interval.low,
            };

            const comparison = FrontierDimension{
                .id = self.id,
                .unit = self.unit,
                .direction = self.direction,
                .candidate = self.candidate,
                .competitor = point.interval,
                .lower_bound = self.lower_bound,
                .improvable = self.improvable,
                .cause = if (worse) self.cause else null,
            };
            switch (try comparison.status()) {
                .open => return .open,
                .unknownbound => {
                    all_bound = false;
                    saw_unknown = true;
                },
                .win => {
                    all_bound = false;
                    saw_win = true;
                },
                .bound => {},
            }
        }
        if (self.cause != null) return error.UnexpectedCause;
        if (all_bound) return .bound;
        if (saw_unknown) return .unknownbound;
        if (saw_win) return .win;
        return .unknownbound;
    }
};

/// One revision-bound measurement against every discovered oracle point.
/// Each dimension owns its comparator envelope because different systems can
/// establish the frontier for runtime, memory, artifact size, or another cost.
pub const OracleFrontierCase = struct {
    integration: FrontierDeclaration,
    measurement: FrontierDeclaration,
    compiler_b: FrontierDeclaration,
    subject_revision: []const u8,
    evidence_revision: []const u8,
    equivalence: []const u8,
    raw_evidence: []const u8,
    required_dimensions: []const []const u8,
    dimensions: []const OracleFrontierDimension,
    context: ?FrontierContext = null,

    pub fn status(self: OracleFrontierCase) FrontierError!FrontierStatus {
        if (self.integration == .absent) return error.MissingIntegration;
        if (self.measurement == .absent) return error.MissingMeasurement;
        if (self.compiler_b == .absent) return error.MissingCompilerB;
        if (self.subject_revision.len == 0) return error.MissingSubjectRevision;
        if (self.evidence_revision.len == 0) return error.MissingEvidenceRevision;
        if (self.equivalence.len == 0) return error.MissingEquivalence;
        if (self.raw_evidence.len == 0) return error.MissingRawEvidence;
        if (self.required_dimensions.len == 0) return error.MissingRequiredDimensions;
        if (self.dimensions.len == 0) return error.MissingDimensions;
        const context = self.context orelse return error.MissingContext;
        try context.validate();

        for (self.required_dimensions, 0..) |required, index| {
            if (required.len == 0) return error.MissingDimensionId;
            for (self.required_dimensions[index + 1 ..]) |other| {
                if (std.mem.eql(u8, required, other)) return error.DuplicateDimension;
            }
            for (self.dimensions) |dimension| {
                if (std.mem.eql(u8, required, dimension.id)) break;
            } else return error.MissingRequiredDimension;
        }

        var all_bound = true;
        var saw_win = false;
        var saw_unknown = false;
        for (self.dimensions, 0..) |dimension, index| {
            for (self.required_dimensions) |required| {
                if (std.mem.eql(u8, required, dimension.id)) break;
            } else return error.UnexpectedDimension;
            for (self.dimensions[index + 1 ..]) |other| {
                if (std.mem.eql(u8, dimension.id, other.id)) return error.DuplicateDimension;
            }
            switch (try dimension.status()) {
                .open => return .open,
                .unknownbound => {
                    all_bound = false;
                    saw_unknown = true;
                },
                .win => {
                    all_bound = false;
                    saw_win = true;
                },
                .bound => {},
            }
        }
        if (all_bound) return .bound;
        if (saw_unknown) return .unknownbound;
        if (saw_win) return .win;
        return .unknownbound;
    }
};

pub const FrontierCase = struct {
    subject_revision: []const u8,
    evidence_revision: []const u8,
    equivalence: []const u8,
    raw_evidence: []const u8,
    dimensions: []const FrontierDimension,
    oracle: ?Oracle = null,
    context: ?FrontierContext = null,

    pub fn status(self: FrontierCase) FrontierError!FrontierStatus {
        if (self.subject_revision.len == 0) return error.MissingSubjectRevision;
        if (self.evidence_revision.len == 0) return error.MissingEvidenceRevision;
        if (self.equivalence.len == 0) return error.MissingEquivalence;
        if (self.raw_evidence.len == 0) return error.MissingRawEvidence;
        if (self.dimensions.len == 0) return error.MissingDimensions;
        for (self.dimensions, 0..) |dimension, index| {
            for (self.dimensions[index + 1 ..]) |other| {
                if (std.mem.eql(u8, dimension.id, other.id)) return error.DuplicateDimension;
            }
        }
        const oracle = self.oracle orelse return error.MissingOracle;
        try oracle.validate();
        const context = self.context orelse return error.MissingContext;
        try context.validate();
        var all_bound = true;
        var saw_win = false;
        var saw_unknown = false;
        for (self.dimensions) |dimension| {
            switch (try dimension.status()) {
                .open => return .open,
                .unknownbound => {
                    all_bound = false;
                    if (!dimension.candidate.eql(dimension.competitor)) saw_unknown = true;
                },
                .win => {
                    all_bound = false;
                    saw_win = true;
                },
                .bound => {},
            }
        }
        if (all_bound) return .bound;
        if (saw_unknown) return .unknownbound;
        if (saw_win) return .win;
        return .unknownbound;
    }
};

/// Map optimization evidence into evidence kinds.
pub fn fromOptimizationEvidence(ev: optimization_outcome.Evidence) Kind {
    return switch (ev) {
        .proven => .proven_semantic_fact,
        .guarded => .guarded_fact,
        .assumed => .user_assertion,
        .profiled => .profile_observation,
        .estimated => .static_estimate,
        .measured => .benchmark_measurement,
    };
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    const hex = "0123456789abcdef";
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        '\x08' => try w.writeAll("\\b"),
        '\x0c' => try w.writeAll("\\f"),
        '\n' => try w.writeAll("\\n"),
        '\r' => try w.writeAll("\\r"),
        '\t' => try w.writeAll("\\t"),
        else => if (c < 0x20) {
            try w.writeAll("\\u00");
            try w.writeByte(hex[@as(usize, c >> 4)]);
            try w.writeByte(hex[@as(usize, c & 0x0f)]);
        } else {
            try w.writeAll(&.{c});
        },
    };
}

pub const FRONTIER_SCHEMA = "idol.frontier.evidence.v1";

fn writeJsonString(w: *std.Io.Writer, value: []const u8) !void {
    try w.writeByte('"');
    try jsonEscape(w, value);
    try w.writeByte('"');
}

fn writeInterval(w: *std.Io.Writer, interval: Interval) !void {
    try w.writeAll("{\"low\":");
    try w.print("{d}", .{interval.low});
    try w.writeAll(",\"high\":");
    try w.print("{d}", .{interval.high});
    try w.writeByte('}');
}

pub fn writeFrontierJson(w: *std.Io.Writer, record: FrontierCase) !void {
    const status = try record.status();
    const oracle = record.oracle.?;
    const context = record.context.?;

    try w.writeAll("{\"schema\":");
    try writeJsonString(w, FRONTIER_SCHEMA);
    try w.writeAll(",\"subject_revision\":");
    try writeJsonString(w, record.subject_revision);
    try w.writeAll(",\"evidence_revision\":");
    try writeJsonString(w, record.evidence_revision);
    try w.writeAll(",\"status\":");
    try writeJsonString(w, status.name());
    try w.writeAll(",\"equivalence\":");
    try writeJsonString(w, record.equivalence);
    try w.writeAll(",\"raw_evidence\":");
    try writeJsonString(w, record.raw_evidence);

    try w.writeAll(",\"context\":{\"world\":");
    try writeJsonString(w, context.world);
    try w.writeAll(",\"target\":");
    try writeJsonString(w, context.target);
    try w.writeAll(",\"workload\":");
    try writeJsonString(w, context.workload);
    try w.writeAll(",\"observations\":[");
    for (context.observations, 0..) |observation, index| {
        if (index != 0) try w.writeByte(',');
        try writeJsonString(w, observation);
    }
    try w.writeAll("]}");

    try w.writeAll(",\"oracle\":{\"name\":");
    try writeJsonString(w, oracle.name);
    try w.writeAll(",\"revision\":");
    try writeJsonString(w, oracle.revision);
    try w.writeAll(",\"configuration\":");
    try writeJsonString(w, oracle.configuration);
    try w.writeAll(",\"evidence\":");
    try writeJsonString(w, oracle.evidence);
    try w.writeByte('}');

    try w.writeAll(",\"dimensions\":[");
    for (record.dimensions, 0..) |dimension, index| {
        if (index != 0) try w.writeByte(',');
        const dimension_status = try dimension.status();
        try w.writeAll("{\"id\":");
        try writeJsonString(w, dimension.id);
        try w.writeAll(",\"unit\":");
        try writeJsonString(w, dimension.unit);
        try w.writeAll(",\"direction\":");
        try writeJsonString(w, dimension.direction.name());
        try w.writeAll(",\"candidate\":");
        try writeInterval(w, dimension.candidate);
        try w.writeAll(",\"competitor\":");
        try writeInterval(w, dimension.competitor);
        try w.writeAll(",\"lower_bound\":");
        if (dimension.lower_bound) |lower_bound| {
            try writeInterval(w, lower_bound);
        } else {
            try w.writeAll("null");
        }
        try w.writeAll(",\"improvable\":");
        try w.writeAll(if (dimension.improvable) "true" else "false");
        try w.writeAll(",\"cause\":");
        if (dimension.cause) |cause| {
            try writeJsonString(w, cause.name());
        } else {
            try w.writeAll("null");
        }
        try w.writeAll(",\"status\":");
        try writeJsonString(w, dimension_status.name());
        try w.writeByte('}');
    }
    try w.writeAll("]}");
}

test "evidence: optimization evidence maps without loss" {
    try std.testing.expectEqual(Kind.proven_semantic_fact, fromOptimizationEvidence(.proven));
    try std.testing.expectEqual(Kind.profile_observation, fromOptimizationEvidence(.profiled));
    try std.testing.expect(!Kind.profile_observation.mayAuthorizeOptimization());
}

test "frontier case opens when one improvable dimension loses" {
    const dimensions = [_]FrontierDimension{
        .{
            .id = "runtime",
            .unit = "ns",
            .direction = .minimize,
            .candidate = Interval.exact(8),
            .competitor = Interval.exact(10),
            .improvable = true,
        },
        .{
            .id = "artifact",
            .unit = "byte",
            .direction = .minimize,
            .candidate = Interval.exact(12),
            .competitor = Interval.exact(10),
            .improvable = true,
            .cause = .wrong_representation,
        },
    };
    const record = FrontierCase{
        .subject_revision = "subject-revision",
        .evidence_revision = "evidence-revision",
        .equivalence = "differential-agree",
        .raw_evidence = "evidence/run.json",
        .dimensions = &dimensions,
        .oracle = .{
            .name = "external-runtime",
            .revision = "oracle-revision",
            .configuration = "release",
            .evidence = "external/run.json",
        },
        .context = .{
            .world = "ordinary",
            .target = "aarch64-linux",
            .workload = "fixture",
            .observations = &.{"exit"},
        },
    };

    try std.testing.expectEqual(FrontierStatus.open, try record.status());
}

test "frontier case preserves a Pareto win beside an exact tie" {
    const dimensions = [_]FrontierDimension{
        .{
            .id = "runtime",
            .unit = "ns",
            .direction = .minimize,
            .candidate = Interval.exact(8),
            .competitor = Interval.exact(10),
            .improvable = true,
        },
        .{
            .id = "memory",
            .unit = "byte",
            .direction = .minimize,
            .candidate = Interval.exact(10),
            .competitor = Interval.exact(10),
            .improvable = true,
        },
    };
    const record = FrontierCase{
        .subject_revision = "subject-revision",
        .evidence_revision = "evidence-revision",
        .equivalence = "differential-agree",
        .raw_evidence = "evidence/run.json",
        .dimensions = &dimensions,
        .oracle = .{
            .name = "external-runtime",
            .revision = "oracle-revision",
            .configuration = "release",
            .evidence = "external/run.json",
        },
        .context = .{
            .world = "ordinary",
            .target = "aarch64-linux",
            .workload = "fixture",
            .observations = &.{"exit"},
        },
    };

    try std.testing.expectEqual(FrontierStatus.win, try record.status());
}

test "frontier case refuses missing equivalence" {
    const dimensions = [_]FrontierDimension{.{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(8),
        .competitor = Interval.exact(10),
        .improvable = true,
    }};
    const record = FrontierCase{
        .subject_revision = "subject-revision",
        .evidence_revision = "evidence-revision",
        .equivalence = "",
        .raw_evidence = "evidence/run.json",
        .dimensions = &dimensions,
    };

    try std.testing.expectError(error.MissingEquivalence, record.status());
}

test "frontier case refuses missing subject revision" {
    const dimensions = [_]FrontierDimension{.{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(8),
        .competitor = Interval.exact(10),
        .improvable = true,
    }};
    const record = FrontierCase{
        .subject_revision = "",
        .evidence_revision = "evidence-revision",
        .equivalence = "differential-agree",
        .raw_evidence = "evidence/run.json",
        .dimensions = &dimensions,
    };

    try std.testing.expectError(error.MissingSubjectRevision, record.status());
}

test "frontier case refuses missing evidence revision" {
    const dimensions = [_]FrontierDimension{.{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(8),
        .competitor = Interval.exact(10),
        .improvable = true,
    }};
    const record = FrontierCase{
        .subject_revision = "subject-revision",
        .evidence_revision = "",
        .equivalence = "differential-agree",
        .raw_evidence = "evidence/run.json",
        .dimensions = &dimensions,
    };

    try std.testing.expectError(error.MissingEvidenceRevision, record.status());
}

test "frontier case refuses missing raw evidence" {
    const dimensions = [_]FrontierDimension{.{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(8),
        .competitor = Interval.exact(10),
        .improvable = true,
    }};
    const record = FrontierCase{
        .subject_revision = "subject-revision",
        .evidence_revision = "evidence-revision",
        .equivalence = "differential-agree",
        .raw_evidence = "",
        .dimensions = &dimensions,
    };

    try std.testing.expectError(error.MissingRawEvidence, record.status());
}

test "frontier case refuses an empty cost vector" {
    const record = FrontierCase{
        .subject_revision = "subject-revision",
        .evidence_revision = "evidence-revision",
        .equivalence = "differential-agree",
        .raw_evidence = "evidence/run.json",
        .dimensions = &.{},
    };

    try std.testing.expectError(error.MissingDimensions, record.status());
}

test "frontier dimension refuses an unexplained loss" {
    const dimension = FrontierDimension{
        .id = "artifact",
        .unit = "byte",
        .direction = .minimize,
        .candidate = Interval.exact(12),
        .competitor = Interval.exact(10),
        .improvable = true,
    };

    try std.testing.expectError(error.MissingCause, dimension.status());
}

test "frontier dimension reaches a proven lower bound" {
    const dimension = FrontierDimension{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(10),
        .competitor = Interval.exact(10),
        .lower_bound = Interval.exact(10),
        .improvable = false,
    };

    try std.testing.expectEqual(FrontierStatus.bound, try dimension.status());
}

test "frontier dimension reports bound before comparator win" {
    const dimension = FrontierDimension{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(8),
        .competitor = Interval.exact(10),
        .lower_bound = Interval.exact(8),
        .improvable = false,
    };

    try std.testing.expectEqual(FrontierStatus.bound, try dimension.status());
}

test "frontier dimension keeps an unknown lower bound distinct" {
    const dimension = FrontierDimension{
        .id = "startup",
        .unit = "ns",
        .direction = .minimize,
        .candidate = .{ .low = 9, .high = 11 },
        .competitor = .{ .low = 9, .high = 11 },
        .improvable = true,
    };

    try std.testing.expectEqual(FrontierStatus.unknownbound, try dimension.status());
}

test "frontier dimension supports higher throughput" {
    const dimension = FrontierDimension{
        .id = "throughput",
        .unit = "byte-per-second",
        .direction = .maximize,
        .candidate = Interval.exact(12),
        .competitor = Interval.exact(10),
        .improvable = true,
    };

    try std.testing.expectEqual(FrontierStatus.win, try dimension.status());
}

test "frontier dimension refuses a missing identity" {
    const dimension = FrontierDimension{
        .id = "",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(8),
        .competitor = Interval.exact(10),
        .improvable = true,
    };

    try std.testing.expectError(error.MissingDimensionId, dimension.status());
}

test "frontier dimension refuses a missing unit" {
    const dimension = FrontierDimension{
        .id = "runtime",
        .unit = "",
        .direction = .minimize,
        .candidate = Interval.exact(8),
        .competitor = Interval.exact(10),
        .improvable = true,
    };

    try std.testing.expectError(error.MissingUnit, dimension.status());
}

test "frontier dimension refuses inverted intervals" {
    const candidate = FrontierDimension{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = .{ .low = 12, .high = 10 },
        .competitor = Interval.exact(20),
        .improvable = true,
    };
    const competitor = FrontierDimension{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(8),
        .competitor = .{ .low = 12, .high = 10 },
        .improvable = true,
    };
    const lower_bound = FrontierDimension{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(10),
        .competitor = Interval.exact(10),
        .lower_bound = .{ .low = 12, .high = 10 },
        .improvable = false,
    };

    try std.testing.expectError(error.InvalidInterval, candidate.status());
    try std.testing.expectError(error.InvalidInterval, competitor.status());
    try std.testing.expectError(error.InvalidInterval, lower_bound.status());
}

test "frontier case refuses duplicate dimension identities" {
    const dimensions = [_]FrontierDimension{
        .{
            .id = "runtime",
            .unit = "ns",
            .direction = .minimize,
            .candidate = Interval.exact(8),
            .competitor = Interval.exact(10),
            .improvable = true,
        },
        .{
            .id = "runtime",
            .unit = "cycle",
            .direction = .minimize,
            .candidate = Interval.exact(8),
            .competitor = Interval.exact(10),
            .improvable = true,
        },
    };
    const record = FrontierCase{
        .subject_revision = "subject-revision",
        .evidence_revision = "evidence-revision",
        .equivalence = "differential-agree",
        .raw_evidence = "evidence/run.json",
        .dimensions = &dimensions,
    };

    try std.testing.expectError(error.DuplicateDimension, record.status());
}

test "frontier dimension refuses non-finite intervals" {
    const dimension = FrontierDimension{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(std.math.inf(f64)),
        .competitor = Interval.exact(10),
        .improvable = true,
    };

    try std.testing.expectError(error.InvalidInterval, dimension.status());
}

test "frontier case refuses a missing oracle" {
    const dimensions = [_]FrontierDimension{.{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(8),
        .competitor = Interval.exact(10),
        .improvable = true,
    }};
    const record = FrontierCase{
        .subject_revision = "subject-revision",
        .evidence_revision = "evidence-revision",
        .equivalence = "differential-agree",
        .raw_evidence = "evidence/run.json",
        .dimensions = &dimensions,
    };

    try std.testing.expectError(error.MissingOracle, record.status());
}

test "external oracle requires complete provenance" {
    const complete = Oracle{
        .name = "external-runtime",
        .revision = "oracle-revision",
        .configuration = "release",
        .evidence = "external/run.json",
    };

    var oracle = complete;
    oracle.name = "";
    try std.testing.expectError(error.MissingOracleName, oracle.validate());
    oracle = complete;
    oracle.revision = "";
    try std.testing.expectError(error.MissingOracleRevision, oracle.validate());
    oracle = complete;
    oracle.configuration = "";
    try std.testing.expectError(error.MissingOracleConfiguration, oracle.validate());
    oracle = complete;
    oracle.evidence = "";
    try std.testing.expectError(error.MissingOracleEvidence, oracle.validate());
}

test "frontier context requires world target workload and observations" {
    const observations = [_][]const u8{"exit"};
    const complete = FrontierContext{
        .world = "ordinary",
        .target = "aarch64-linux",
        .workload = "fixture",
        .observations = &observations,
    };

    var context = complete;
    context.world = "";
    try std.testing.expectError(error.MissingWorld, context.validate());
    context = complete;
    context.target = "";
    try std.testing.expectError(error.MissingTarget, context.validate());
    context = complete;
    context.workload = "";
    try std.testing.expectError(error.MissingWorkload, context.validate());
    context = complete;
    context.observations = &.{};
    try std.testing.expectError(error.MissingObservations, context.validate());
}

test "frontier case refuses a missing execution context" {
    const dimensions = [_]FrontierDimension{.{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(8),
        .competitor = Interval.exact(10),
        .improvable = true,
    }};
    const record = FrontierCase{
        .subject_revision = "subject-revision",
        .evidence_revision = "evidence-revision",
        .equivalence = "differential-agree",
        .raw_evidence = "evidence/run.json",
        .dimensions = &dimensions,
        .oracle = .{
            .name = "external-runtime",
            .revision = "oracle-revision",
            .configuration = "release",
            .evidence = "external/run.json",
        },
    };

    try std.testing.expectError(error.MissingContext, record.status());
}

test "frontier evidence projects machine-readable JSON" {
    const alloc = std.testing.allocator;
    const dimensions = [_]FrontierDimension{.{
        .id = "artifact",
        .unit = "byte",
        .direction = .minimize,
        .candidate = Interval.exact(12),
        .competitor = Interval.exact(10),
        .improvable = true,
        .cause = .wrong_representation,
    }};
    const record = FrontierCase{
        .subject_revision = "subject-revision",
        .evidence_revision = "evidence-revision",
        .equivalence = "differential-agree",
        .raw_evidence = "evidence/run.json",
        .dimensions = &dimensions,
        .oracle = .{
            .name = "external-runtime",
            .revision = "oracle-revision",
            .configuration = "release",
            .evidence = "external/run.json",
        },
        .context = .{
            .world = "ordinary",
            .target = "aarch64-linux",
            .workload = "fixture",
            .observations = &.{"exit"},
        },
    };

    var output: std.Io.Writer.Allocating = .init(alloc);
    defer output.deinit();
    try writeFrontierJson(&output.writer, record);
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, output.written(), .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try std.testing.expectEqualStrings("idol.frontier.evidence.v1", root.get("schema").?.string);
    try std.testing.expectEqualStrings("subject-revision", root.get("subject_revision").?.string);
    try std.testing.expectEqualStrings("evidence-revision", root.get("evidence_revision").?.string);
    try std.testing.expectEqualStrings("open", root.get("status").?.string);
    try std.testing.expectEqualStrings("external-runtime", root.get("oracle").?.object.get("name").?.string);
    try std.testing.expectEqualStrings("ordinary", root.get("context").?.object.get("world").?.string);
    try std.testing.expectEqual(@as(usize, 1), root.get("context").?.object.get("observations").?.array.items.len);
    const dimension = root.get("dimensions").?.array.items[0].object;
    try std.testing.expectEqualStrings("artifact", dimension.get("id").?.string);
    try std.testing.expectEqualStrings("wrong-representation", dimension.get("cause").?.string);
    try std.testing.expectEqualStrings("open", dimension.get("status").?.string);
}

test "frontier JSON escapes control characters" {
    const alloc = std.testing.allocator;
    const value = "line\n\t\"\\\x01";
    var output: std.Io.Writer.Allocating = .init(alloc);
    defer output.deinit();
    try writeJsonString(&output.writer, value);
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, output.written(), .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings(value, parsed.value.string);
}

test "frontier dimension refuses a debt cause without an open loss" {
    const dimension = FrontierDimension{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(8),
        .competitor = Interval.exact(10),
        .improvable = true,
        .cause = .wrong_algorithm,
    };

    try std.testing.expectError(error.UnexpectedCause, dimension.status());
}

test "oracle frontier refuses a win hidden by a weaker oracle" {
    const points = [_]OraclePoint{
        .{
            .oracle = .{
                .name = "baseline-compiler",
                .revision = "baseline-revision",
                .configuration = "release",
                .evidence = "evidence/baseline.json",
            },
            .interval = Interval.exact(10),
        },
        .{
            .oracle = .{
                .name = "domain-champion",
                .revision = "champion-revision",
                .configuration = "tuned",
                .evidence = "evidence/champion.json",
            },
            .interval = Interval.exact(7),
        },
    };
    const dimension = OracleFrontierDimension{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(8),
        .oracles = &points,
        .improvable = true,
        .cause = .wrong_algorithm,
    };

    try std.testing.expectEqual(FrontierStatus.open, try dimension.status());
}

test "oracle frontier admits a win only against every oracle" {
    const points = [_]OraclePoint{
        .{
            .oracle = .{
                .name = "compiler-a",
                .revision = "revision-a",
                .configuration = "tuned-a",
                .evidence = "evidence/a.json",
            },
            .interval = Interval.exact(10),
        },
        .{
            .oracle = .{
                .name = "compiler-b",
                .revision = "revision-b",
                .configuration = "tuned-b",
                .evidence = "evidence/b.json",
            },
            .interval = Interval.exact(9),
        },
    };
    const dimension = OracleFrontierDimension{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(8),
        .oracles = &points,
        .improvable = true,
    };

    try std.testing.expectEqual(FrontierStatus.win, try dimension.status());
}

test "oracle frontier requires attributed unique comparators" {
    const oracle = Oracle{
        .name = "compiler",
        .revision = "revision",
        .configuration = "tuned",
        .evidence = "evidence/compiler.json",
    };
    const duplicate = [_]OraclePoint{
        .{ .oracle = oracle, .interval = Interval.exact(10) },
        .{ .oracle = oracle, .interval = Interval.exact(9) },
    };
    const empty = OracleFrontierDimension{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(8),
        .oracles = &.{},
        .improvable = true,
    };
    const repeated = OracleFrontierDimension{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(8),
        .oracles = &duplicate,
        .improvable = true,
    };

    try std.testing.expectError(error.MissingOracle, empty.status());
    try std.testing.expectError(error.DuplicateOracle, repeated.status());
}

test "oracle frontier case binds the complete comparison to its measured subject" {
    const runtime_oracles = [_]OraclePoint{
        .{
            .oracle = .{
                .name = "compiler-a",
                .revision = "revision-a",
                .configuration = "release",
                .evidence = "evidence/a-runtime.json",
            },
            .interval = Interval.exact(10),
        },
        .{
            .oracle = .{
                .name = "compiler-b",
                .revision = "revision-b",
                .configuration = "tuned",
                .evidence = "evidence/b-runtime.json",
            },
            .interval = Interval.exact(7),
        },
    };
    const dimensions = [_]OracleFrontierDimension{.{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(8),
        .oracles = &runtime_oracles,
        .improvable = true,
        .cause = .wrong_algorithm,
    }};
    const measurement = OracleFrontierCase{
        .integration = .present,
        .measurement = .present,
        .compiler_b = .present,
        .subject_revision = "candidate-revision",
        .evidence_revision = "evidence-revision",
        .equivalence = "evidence/equivalence.json",
        .raw_evidence = "evidence/runtime.json",
        .required_dimensions = &.{"runtime"},
        .dimensions = &dimensions,
        .context = .{
            .world = "linux-aarch64",
            .target = "aarch64-native",
            .workload = "compiler-build",
            .observations = &.{ "answer", "runtime" },
        },
    };

    try std.testing.expectEqual(FrontierStatus.open, try measurement.status());
}

test "oracle frontier case refuses an unbound measurement envelope" {
    const dimensions = [_]OracleFrontierDimension{.{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(8),
        .oracles = &.{},
        .improvable = true,
    }};
    const measurement = OracleFrontierCase{
        .integration = .present,
        .measurement = .present,
        .compiler_b = .present,
        .subject_revision = "candidate-revision",
        .evidence_revision = "evidence-revision",
        .equivalence = "evidence/equivalence.json",
        .raw_evidence = "evidence/runtime.json",
        .required_dimensions = &.{"runtime"},
        .dimensions = &dimensions,
        .context = .{
            .world = "linux-aarch64",
            .target = "aarch64-native",
            .workload = "compiler-build",
            .observations = &.{ "answer", "runtime" },
        },
    };

    try std.testing.expectError(error.MissingOracle, measurement.status());
}

test "oracle frontier case refuses an absent measurement declaration" {
    const measurement = OracleFrontierCase{
        .integration = .present,
        .measurement = .absent,
        .compiler_b = .present,
        .subject_revision = "candidate-revision",
        .evidence_revision = "evidence-revision",
        .equivalence = "evidence/equivalence.json",
        .raw_evidence = "evidence/runtime.json",
        .required_dimensions = &.{"runtime"},
        .dimensions = &.{},
        .context = null,
    };

    try std.testing.expectError(error.MissingMeasurement, measurement.status());
}

test "oracle frontier case refuses an absent compiler b declaration" {
    const measurement = OracleFrontierCase{
        .integration = .present,
        .measurement = .present,
        .compiler_b = .absent,
        .subject_revision = "candidate-revision",
        .evidence_revision = "evidence-revision",
        .equivalence = "evidence/equivalence.json",
        .raw_evidence = "evidence/runtime.json",
        .required_dimensions = &.{"runtime"},
        .dimensions = &.{},
        .context = null,
    };

    try std.testing.expectError(error.MissingCompilerB, measurement.status());
}

test "oracle frontier case refuses an absent integration declaration" {
    const measurement = OracleFrontierCase{
        .integration = .absent,
        .measurement = .present,
        .compiler_b = .present,
        .subject_revision = "candidate-revision",
        .evidence_revision = "evidence-revision",
        .equivalence = "evidence/equivalence.json",
        .raw_evidence = "evidence/runtime.json",
        .required_dimensions = &.{"runtime"},
        .dimensions = &.{},
        .context = null,
    };

    try std.testing.expectError(error.MissingIntegration, measurement.status());
}

test "oracle frontier case refuses an incomplete dimension envelope" {
    const oracle = OraclePoint{
        .oracle = .{
            .name = "compiler",
            .revision = "revision",
            .configuration = "tuned",
            .evidence = "evidence/compiler.json",
        },
        .interval = Interval.exact(10),
    };
    const dimensions = [_]OracleFrontierDimension{.{
        .id = "runtime",
        .unit = "ns",
        .direction = .minimize,
        .candidate = Interval.exact(8),
        .oracles = &.{oracle},
        .improvable = true,
    }};
    const measurement = OracleFrontierCase{
        .integration = .present,
        .measurement = .present,
        .compiler_b = .present,
        .subject_revision = "candidate-revision",
        .evidence_revision = "evidence-revision",
        .equivalence = "evidence/equivalence.json",
        .raw_evidence = "evidence/runtime.json",
        .required_dimensions = &.{ "runtime", "memory" },
        .dimensions = &dimensions,
        .context = .{
            .world = "linux-aarch64",
            .target = "aarch64-native",
            .workload = "compiler-build",
            .observations = &.{ "answer", "runtime", "memory" },
        },
    };

    try std.testing.expectError(error.MissingRequiredDimension, measurement.status());
}

test "oracle frontier case refuses a dimension outside its envelope" {
    const oracle = OraclePoint{
        .oracle = .{
            .name = "compiler",
            .revision = "revision",
            .configuration = "tuned",
            .evidence = "evidence/compiler.json",
        },
        .interval = Interval.exact(10),
    };
    const dimensions = [_]OracleFrontierDimension{
        .{
            .id = "runtime",
            .unit = "ns",
            .direction = .minimize,
            .candidate = Interval.exact(8),
            .oracles = &.{oracle},
            .improvable = true,
        },
        .{
            .id = "memory",
            .unit = "bytes",
            .direction = .minimize,
            .candidate = Interval.exact(8),
            .oracles = &.{oracle},
            .improvable = true,
        },
    };
    const measurement = OracleFrontierCase{
        .integration = .present,
        .measurement = .present,
        .compiler_b = .present,
        .subject_revision = "candidate-revision",
        .evidence_revision = "evidence-revision",
        .equivalence = "evidence/equivalence.json",
        .raw_evidence = "evidence/runtime.json",
        .required_dimensions = &.{"memory"},
        .dimensions = &dimensions,
        .context = .{
            .world = "linux-aarch64",
            .target = "aarch64-native",
            .workload = "compiler-build",
            .observations = &.{ "answer", "runtime" },
        },
    };

    try std.testing.expectError(error.UnexpectedDimension, measurement.status());
}
