//! Pass 11 WP-15 — Ward / M1 native-barrier proofs on generated C artifacts.
const std = @import("std");
const testing = std.testing;
const native_barrier_checks = @import("native_barrier_checks.zig");

const duo_bin = "zig-out/bin/duo";

fn runProfile(alloc: std.mem.Allocator, profile: native_barrier_checks.BarrierProfile) !void {
    const result = try native_barrier_checks.evaluateProfile(alloc, profile, duo_bin);
    defer alloc.free(result.checks);
    defer for (result.checks) |c| native_barrier_checks.freeSymbolCheck(alloc, c);
    try testing.expect(result.profile_ok);
}

test "Pass 11 WP-15: pass12 M1 classifier paths are no-boxing" {
    try runProfile(testing.allocator, native_barrier_checks.pass12_m1_profile);
}

test "Pass 27 P1: ward direct cursor + leb128 profile" {
    try runProfile(testing.allocator, native_barrier_checks.pass27_ward_direct_profile);
}

test "Pass 11 WP-15: pass12 M1 sorted lookup is no-boxing" {
    try runProfile(testing.allocator, native_barrier_checks.pass12_m1_sorted_lookup_profile);
}

test "Pass 11 WP-15: ward opcode lookup tables are no-boxing" {
    try runProfile(testing.allocator, native_barrier_checks.ward_opcode_lookup_profile);
}

test "Pass 11 WP-15: ward decode hot path documents boxing gap" {
    try runProfile(testing.allocator, native_barrier_checks.ward_decode_profile);
}

test "Pass 12 M2: ward decode_instruction has no dynamic dispatch" {
    try runProfile(testing.allocator, native_barrier_checks.ward_decode_dispatch_profile);
}
