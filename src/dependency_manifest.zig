//! Pass 14 §8, §18 Audit 3, Milestone 3 — dependency manifest.
//!
//! Every dependency Duo currently relies on is classified (§8) and given an
//! explicit exit path. This is the sovereignty ledger: nothing may become a
//! *hidden semantic authority*. The direct native backend, semantic graph, and
//! transform engine are OWNED (not dependencies) and so are not listed here.
//!
//! The seed records below are the *real* current dependencies of this
//! repository (Pass 4 §A + Pass 11 release profile). They turn "we depend on
//! Zig/Clang/libc" from folklore into a machine-readable removal plan.
const std = @import("std");

pub const SCHEMA_VERSION = "dependency-manifest-v0";

/// Pass 14 §8 dependency classes.
pub const Class = enum {
    bootstrap,
    optional_backend,
    optional_integration,
    development_tool,
    platform_interface,
    imported_source,
    forbidden_architectural,

    pub fn name(self: Class) []const u8 {
        return @tagName(self);
    }
};

pub const Record = struct {
    id: []const u8,
    name: []const u8,
    class: Class,
    owner: []const u8,
    purpose: []const u8,
    semantic_authority: []const u8,
    runtime_cost: []const u8,
    compile_cost: []const u8,
    replacement_plan: []const u8,
    removal_gate: []const u8,
    permanence: []const u8,
};

/// Pass 14 §18 Audit 3 — real current dependencies, classified.
pub const records: []const Record = &.{
    .{
        .id = "dep-zig-bootstrap-host",
        .name = "Zig (master toolchain)",
        .class = .bootstrap,
        .owner = "build.zig",
        .purpose = "Host language for the bootstrap compiler (src/*.zig); `zig build` drives everything.",
        .semantic_authority = "none — Zig is the implementation host, not a semantic model. Duo semantics are defined in .duo, descriptors, and the transform engine.",
        .runtime_cost = "none in generated artifacts (Zig is a build-time host only).",
        .compile_cost = "full build host; compiler itself is ~27k-line codegen + front end compiled by Zig.",
        .replacement_plan = "Self-hosting (Pass 4 stages 0→10): compiler-capable Duo subset → front end in Duo → semantic core → backend → runtime → bootstrap closure.",
        .removal_gate = "Pass 4 P4-12..P4-15 (compiler-capable profile, bootstrappable core, first compiler component in Duo, multi-generation harness).",
        .permanence = "Temporary bootstrap; exit path exists but is multi-stage. Pass 14 §1.2: the canonical toolchain must not REQUIRE Zig.",
    },
    .{
        .id = "dep-clang-c-backend",
        .name = "Clang / `zig cc`",
        .class = .optional_backend,
        .owner = "src/main.zig (backend dispatch), docs/plans/pass11_release_proof.md",
        .purpose = "Profile A default release backend: translates generated C into object code / executables for any Clang target.",
        .semantic_authority = "none — generated C is a bootstrap/portability backend, not semantic IR (Pass 4 invariant P4-07).",
        .runtime_cost = "none beyond standard C runtime of the produced binary.",
        .compile_cost = "one clang invocation per compile; dominates compile latency today.",
        .replacement_plan = "Direct native backend (`native_backend.zig`) maturation: extend past the ARM64 Mach-O subset to more ISAs/object formats; then make direct the default for proven targets.",
        .removal_gate = "Pass 4 P4-08 (extend direct scalar backend) + Milestone 7 (architecture-specific realization proof across ≥2 targets).",
        .permanence = "Optional portability backend. Must never be canonical for direct-backend proofs (Pass 14 §19: no generated C in direct-backend proofs).",
    },
    .{
        .id = "dep-libc-platform",
        .name = "libc (platform C runtime)",
        .class = .platform_interface,
        .owner = "src/codegen.zig (embedded runtime preamble)",
        .purpose = "Standard C library functions used by generated runtime (malloc/free, memcpy, I/O, libm) and by native FFI calls.",
        .semantic_authority = "none — libc is a platform surface Duo targets, not a definition of Duo semantics.",
        .runtime_cost = "pay-for-use: the embedded C preamble pulls libc symbols only when `moduleNeedsLuaRuntime` or FFI requires them; `native_scalar_mode` skips much of it.",
        .compile_cost = "link-time only.",
        .replacement_plan = "Freestanding runtime profile for embedded/no-libc targets; Duo-owned allocator + minimal runtime (Pass 4 P4-09).",
        .removal_gate = "Pass 4 P4-09 (modular runtime + pay-for-use linking) + Pass 9 L1 (Duo-native systems substrate).",
        .permanence = "Platform interface for hosted targets; optional on freestanding/embedded. Acceptable per §8 — adapters conform libc to Duo, not vice versa.",
    },
    .{
        .id = "dep-macho-linker",
        .name = "macOS Mach-O linker (`ld`) + system assembler",
        .class = .platform_interface,
        .owner = "src/native_backend.zig (direct backend, macOS AArch64)",
        .purpose = "Links Duo-owned Mach-O objects into executables for the direct backend proof path.",
        .semantic_authority = "none.",
        .runtime_cost = "none (link-time only).",
        .compile_cost = "one link step when targeting native-exe.",
        .replacement_plan = "Duo-owned object writer already emits Mach-O directly (sovereign); next: Duo-owned linker/relocation resolution so `ld` is not required.",
        .removal_gate = "Pass 4 P4-08 + Milestone 5 (direct low-level substrate proof — object emission / executable memory without external linker).",
        .permanence = "Temporary for the direct-backend proof; the object bytes are already Duo-owned.",
    },
    .{
        .id = "dep-git-cli",
        .name = "git CLI",
        .class = .development_tool,
        .owner = "src/host_run.zig (subprocess), src/git_preservation.zig, src/dev_control_plane.zig",
        .purpose = "Read-only repository state queries for snapshots, preservation reports, dirty fingerprints.",
        .semantic_authority = "none — git state is evidence rank #6 in the authority order (Pass 13), below compiler facts.",
        .runtime_cost = "none in generated artifacts.",
        .compile_cost = "none.",
        .replacement_plan = "None required — git is a development tool, not a build/compile dependency. Preservation queries degrade gracefully if git is absent.",
        .removal_gate = "N/A (development tool; §8 explicitly permits dev tools).",
        .permanence = "Permanent as a dev tool; never on the compile/release path.",
    },
};

pub fn summary() struct { total: usize, by_class: [7]usize } {
    var by_class = [_]usize{ 0, 0, 0, 0, 0, 0, 0 };
    for (records) |r| by_class[@intFromEnum(r.class)] += 1;
    return .{ .total = records.len, .by_class = by_class };
}

pub fn writeManifestJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"dependencies\":[", .{SCHEMA_VERSION});
    for (records, 0..) |r, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"name\":\"{s}\",\"class\":\"{s}\",\"owner\":\"{s}\",\"purpose\":\"{s}\",\"semantic_authority\":\"{s}\",\"runtime_cost\":\"{s}\",\"compile_cost\":\"{s}\",\"replacement_plan\":\"{s}\",\"removal_gate\":\"{s}\",\"permanence\":\"{s}\"}}",
            .{ r.id, r.name, r.class.name(), r.owner, r.purpose, r.semantic_authority, r.runtime_cost, r.compile_cost, r.replacement_plan, r.removal_gate, r.permanence },
        );
    }
    const s = summary();
    try w.print("],\"summary\":{{\"total\":{d},\"bootstrap\":{d},\"optional_backend\":{d},\"optional_integration\":{d},\"development_tool\":{d},\"platform_interface\":{d},\"imported_source\":{d},\"forbidden_architectural\":{d}}}}}", .{
        s.total, s.by_class[0], s.by_class[1], s.by_class[2], s.by_class[3], s.by_class[4], s.by_class[5], s.by_class[6],
    });
}

test "dependency_manifest: records are non-empty and classified" {
    try std.testing.expect(records.len >= 4);
    for (records) |r| {
        try std.testing.expect(r.id.len > 0);
        try std.testing.expect(r.purpose.len > 0);
        try std.testing.expect(r.replacement_plan.len > 0);
        // Pass 14 §1.2: no dependency may be an unqualified permanent semantic authority.
        try std.testing.expect(r.semantic_authority.len > 0);
    }
}

test "dependency_manifest: every record has a removal gate (exit path)" {
    for (records) |r| {
        try std.testing.expect(r.removal_gate.len > 0);
    }
}

test "dependency_manifest: JSON parses with all classes" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeManifestJson(&aw.writer);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, aw.written(), .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    try std.testing.expectEqual(@as(usize, records.len), parsed.value.object.get("dependencies").?.array.items.len);
    try std.testing.expect(parsed.value.object.get("summary").? == .object);
}
