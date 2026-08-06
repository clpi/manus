//! Pass 20 §4–§5 / Pass 22 §22.1 — foreign import strength classification.
//!
//! Every imported fact must identify its strength and evidence. Text inference is never
//! proven semantic truth.
const std = @import("std");
const sim = @import("sim.zig");

pub const SCHEMA_VERSION = "pass20-import-strength-v0";

/// Weakest → strongest semantic representation available for an import.
pub const ImportStrength = enum(u8) {
    textual = 0, // Level 0 — textual only
    structural = 1, // Level 1 — syntax structure
    declared_semantic = 2, // Level 2 — declared names/types
    typed_executable = 3, // Level 3 — calls, effects, layouts
    lowered_semantic = 4, // Level 4 — lowered IR
    binary_semantic = 5, // Level 5 — binary/debug/object
};

pub const StrengthReport = struct {
    strength: ImportStrength,
    language: []const u8,
    artifact: []const u8,
    entity_count: usize,
    evidence: []const u8,
};

pub fn strengthName(s: ImportStrength) []const u8 {
    return switch (s) {
        .textual => "textual",
        .structural => "structural",
        .declared_semantic => "declared_semantic",
        .typed_executable => "typed_executable",
        .lowered_semantic => "lowered_semantic",
        .binary_semantic => "binary_semantic",
    };
}

/// Classify a SIM snapshot imported through a Duo frontend.
pub fn classifySnapshot(snap: *const sim.Snapshot) StrengthReport {
    const lang = if (snap.entities.len > 0) snap.entities[0].origin.language else "unknown";
    var has_record = false;
    var has_function = false;
    var has_layout = false;
    var has_abi = false;

    for (snap.entities) |ent| {
        switch (ent.kind) {
            .record => has_record = true,
            .function => has_function = true,
            else => {},
        }
        if (ent.size_bytes != null or ent.align_bytes != null) has_layout = true;
        if (ent.abi != null) has_abi = true;
    }

    const strength: ImportStrength = if (has_function and has_abi and has_layout)
        .typed_executable
    else if (has_record and has_function)
        .declared_semantic
    else if (snap.entities.len > 0)
        .structural
    else
        .textual;

    const evidence = switch (strength) {
        .typed_executable => "records+functions+layout+abi facts in SIM",
        .declared_semantic => "records and functions with origin metadata",
        .structural => "entities present without full declaration semantics",
        .textual => "empty or text-only import",
        .lowered_semantic, .binary_semantic => "not classified from SIM v0",
    };

    return .{
        .strength = strength,
        .language = lang,
        .artifact = snap.file,
        .entity_count = snap.entities.len,
        .evidence = evidence,
    };
}

test "pass20_import_strength: C point.h reaches declared_semantic" {
    const c_sim_import = @import("c_sim_import.zig");
    const point_h = @import("pass5_fixtures.zig").point_h;
    var snap = try c_sim_import.importHeaderSource(std.testing.allocator, "examples/pass5/fixtures/point.h", point_h);
    defer snap.deinit(std.testing.allocator);
    const report = classifySnapshot(&snap);
    try std.testing.expect(@intFromEnum(report.strength) >= @intFromEnum(ImportStrength.declared_semantic));
    try std.testing.expectEqualStrings("c", report.language);
}
