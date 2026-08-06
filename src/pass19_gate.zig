//! Pass 19 native gate — catalog invariants + umbrella foundation checks.
const std = @import("std");
const pass19_catalog = @import("pass19_catalog.zig");
const command_descriptor = @import("command_descriptor.zig");
const pass15_catalog = @import("pass15_catalog.zig");

pub const GateError = error{ GateFailed };

pub fn validatePass19Catalog() GateError!void {
    if (!std.mem.eql(u8, pass19_catalog.SCHEMA_VERSION, "pass19-catalog-v0")) return error.GateFailed;
    if (pass19_catalog.workstreams.len != 33) return error.GateFailed;
    if (pass19_catalog.required_audits.len != 6) return error.GateFailed;
    if (pass19_catalog.success_criteria.len < 10) return error.GateFailed;
}

/// Gate P19-G0 — umbrella foundations wired (command descriptors + shell catalog).
pub fn proveGateUmbrellaFoundations() GateError!void {
    if (command_descriptor.duo_commands.len < 8) return error.GateFailed;
    if (pass15_catalog.workstreams.len != 20) return error.GateFailed;
    const build = command_descriptor.findById("duo.build") orelse return error.GateFailed;
    if (build.effects.len == 0) return error.GateFailed;
    const shell = command_descriptor.findById("duo.shell") orelse return error.GateFailed;
    if (!std.mem.eql(u8, shell.output, "ShellSession")) return error.GateFailed;
}

pub fn validatePass19Gate() GateError!void {
    try validatePass19Catalog();
    try proveGateUmbrellaFoundations();
}

test "pass19_gate: catalog + umbrella foundations" {
    try validatePass19Gate();
}
