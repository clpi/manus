//! Pass 23 — deferred design registry (§5 — rejected until general mechanism exists).
const std = @import("std");

pub const SCHEMA_VERSION = "deferred-design-v0";

pub const Status = enum {
    deferred,
    rejected,
    candidate,
    superseded,
};

pub const Entry = struct {
    id: []const u8,
    title: []const u8,
    status: Status,
    reason: []const u8,
};

/// Pass 23 §5.2 — explicitly deferred mechanisms (must not ship accidentally).
pub const entries: []const Entry = &.{
    .{
        .id = "P23-DEF-ACCUM",
        .title = "Implicit accumulator / live-out return inference",
        .status = .superseded,
        .reason = "Pass 25 §5.1 tail-demand propagation + result lineage (not backward local search)",
    },
    .{
        .id = "P23-REJ-RETURN-SRC",
        .title = "@return / named return bindings / return-source annotations",
        .status = .rejected,
        .reason = "adds binding category; less compact than explicit tail",
    },
    .{
        .id = "P23-REJ-INDENT-SEM",
        .title = "Indentation-only multiline semantics",
        .status = .rejected,
        .reason = "end/do remain authoritative delimiters",
    },
    .{
        .id = "P23-CAND-LOOP-RESULT",
        .title = "Loop-expression accumulator result",
        .status = .superseded,
        .reason = "Pass 25 §5.1 Rule F tail_loop_carried + phi proof",
    },
};

pub fn isDeferred(id: []const u8) bool {
    for (entries) |e| {
        if (std.mem.eql(u8, e.id, id)) return e.status == .deferred or e.status == .rejected;
    }
    return false;
}

pub fn statusOf(id: []const u8) ?Status {
    for (entries) |e| {
        if (std.mem.eql(u8, e.id, id)) return e.status;
    }
    return null;
}

test "deferred_design: accumulator return superseded by Pass 25 tail-demand" {
    const st = statusOf("P23-DEF-ACCUM") orelse return error.TestExpectedEqual;
    try std.testing.expect(st == .superseded);
}
