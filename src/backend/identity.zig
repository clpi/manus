//! Explicit backend / representation / runtime identity (WP-02 split).
//!
//! Artifact manifests must record all three axes; silent conflation is forbidden.
//!
//! `direct/linux/elf` is a distinct backend identity fact from
//! `direct/macos/macho`. The intermediate representation identity is derived
//! from the target triple's object format via target_model.BackendTarget,
//! never hardcoded to a single platform.
const std = @import("std");
const target_model = @import("../target/model.zig");

pub const SCHEMA_VERSION = "backend-identity-v0";

pub const Backend = enum {
    /// Canonical direct machine lowering. A refusal never falls back to C.
    auto,
    /// Explicit graph-observed DNIR to C99 source; orthogonal to direct and auto.
    c,
    /// ARM64 Mach-O machine code via `native.zig` (canonical when eligible).
    direct,
    wasm,

    pub fn name(self: Backend) []const u8 {
        return switch (self) {
            .auto => "auto",
            .c => "c",
            .direct => "direct",
            .wasm => "wasm",
        };
    }

    pub fn parse(s: []const u8) ?Backend {
        if (std.mem.eql(u8, s, "auto")) return .auto;
        if (std.mem.eql(u8, s, "c")) return .c;
        if (std.mem.eql(u8, s, "direct") or std.mem.eql(u8, s, "native")) return .direct;
        if (std.mem.eql(u8, s, "wasm")) return .wasm;
        return null;
    }

    pub fn prefersMachineCode(self: Backend) bool {
        return self == .auto or self == .direct;
    }
};

pub const RepresentationProfile = enum {
    generic,
    specialized,
    sealed,
    native,

    pub fn name(self: RepresentationProfile) []const u8 {
        return @tagName(self);
    }
};

pub const RuntimeProfile = enum {
    full,
    dynamic,
    minimal,
    freestanding,

    pub fn name(self: RuntimeProfile) []const u8 {
        return @tagName(self);
    }
};

/// Benchmark harness profile (WP-01). The C identities remain parseable only so
/// old invocations and manifests receive an exact retirement diagnostic; they
/// never select the graph-backed C99 source realizer.
pub const BenchBackend = enum {
    c_dynamic,
    c_specialized,
    direct,

    pub fn name(self: BenchBackend) []const u8 {
        return switch (self) {
            .c_dynamic => "c-dynamic",
            .c_specialized => "c-specialized",
            .direct => "direct",
        };
    }

    pub fn parse(s: []const u8) ?BenchBackend {
        if (std.mem.eql(u8, s, "c-dynamic")) return .c_dynamic;
        if (std.mem.eql(u8, s, "c-specialized")) return .c_specialized;
        if (std.mem.eql(u8, s, "direct")) return .direct;
        return null;
    }

    pub fn runnable(self: BenchBackend) bool {
        return self == .direct;
    }
};

/// Map bench harness profile to backend × representation × runtime axes.
pub fn profileForBenchBackend(bb: BenchBackend) struct {
    backend: Backend,
    representation: RepresentationProfile,
    runtime: RuntimeProfile,
} {
    return switch (bb) {
        .c_dynamic => .{ .backend = .c, .representation = .generic, .runtime = .full },
        .c_specialized => .{ .backend = .c, .representation = .specialized, .runtime = .dynamic },
        .direct => .{ .backend = .direct, .representation = .native, .runtime = .freestanding },
    };
}

pub const Manifest = struct {
    backend: Backend,
    representation: RepresentationProfile,
    runtime: RuntimeProfile,
    target: []const u8,
    intermediate: []const u8,
    external_compiler: ?[]const u8 = null,
    boxing_mode: []const u8 = "unknown",
};

/// Derive the intermediate representation identity from the target triple,
/// using BackendTarget which computes object-format + arch from the real
/// target. Falls back to "mach-o-arm64" only when the target string cannot
/// be parsed (preserving prior behavior for unresolvable inputs).
///
/// No allocator: the identity is computed from enum switches on Arch × Os,
/// producing string literals directly. This makes `direct/linux/elf` produce
/// `elf-x86_64` (or `elf-aarch64`) while `direct/macos/macho` keeps
/// `mach-o-arm64` — a distinct identity fact, never silent conflation.
pub fn inferIntermediateFromTarget(backend: Backend, target: []const u8) []const u8 {
    const backend_name = backend.name();
    if (target_model.BackendTarget.parseTarget(backend_name, target)) |bt| {
        return bt.intermediate();
    }
    return "mach-o-arm64";
}

pub fn inferFromCompile(
    backend: Backend,
    target: []const u8,
    native_scalar: bool,
    idol_mode: bool,
) Manifest {
    const repr: RepresentationProfile = if (!idol_mode)
        .generic
    else if (native_scalar)
        .native
    else
        .specialized;

    const runtime: RuntimeProfile = switch (backend) {
        .auto, .direct => .freestanding,
        .c => if (native_scalar) .minimal else if (idol_mode) .dynamic else .full,
        .wasm => .minimal,
    };

    const intermediate: []const u8 = switch (backend) {
        .auto, .direct => inferIntermediateFromTarget(backend, target),
        .c => "generated-c",
        .wasm => inferIntermediateFromTarget(backend, target),
    };

    const boxing: []const u8 = if (native_scalar) "none" else if (idol_mode) "typed-mixed" else "full-dynamic";

    // The wasm backend writes .wasm bytes directly via wasm_backend.zig — no
    // external C compiler is invoked. The manifest must record null, not a
    // stale "zig cc" that names a bridge that no longer crosses the seam.
    const external_compiler: ?[]const u8 = switch (backend) {
        .auto, .direct, .c => null,
        .wasm => null,
    };

    return .{
        .backend = backend,
        .representation = repr,
        .runtime = runtime,
        .target = target,
        .intermediate = intermediate,
        .external_compiler = external_compiler,
        .boxing_mode = boxing,
    };
}

pub fn writeManifestJson(m: Manifest, w: *std.Io.Writer) !void {
    try w.print(
        "{{\"schema\":\"{s}\",\"backend\":\"{s}\",\"representation\":\"{s}\",\"runtime\":\"{s}\",\"target\":\"",
        .{ SCHEMA_VERSION, m.backend.name(), m.representation.name(), m.runtime.name() },
    );
    try jsonEscape(w, m.target);
    try w.print("\",\"intermediate\":\"", .{});
    try jsonEscape(w, m.intermediate);
    try w.print("\",\"boxing_mode\":\"", .{});
    try jsonEscape(w, m.boxing_mode);
    if (m.external_compiler) |ec| {
        try w.print("\",\"external_compiler\":\"", .{});
        try jsonEscape(w, ec);
        try w.print("\"}}", .{});
    } else {
        try w.print("\",\"external_compiler\":null}}", .{});
    }
}

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

test "backend_identity: parse backend and bench profiles" {
    try std.testing.expectEqual(Backend.auto, Backend.parse("auto").?);
    try std.testing.expectEqual(Backend.c, Backend.parse("c").?);
    try std.testing.expectEqual(Backend.direct, Backend.parse("direct").?);
    try std.testing.expectEqual(Backend.direct, Backend.parse("native").?);
    try std.testing.expect(Backend.parse("c-specialized") == null);
    try std.testing.expect(BenchBackend.parse("c-specialized") == .c_specialized);
    try std.testing.expect(!BenchBackend.c_specialized.runnable());
    try std.testing.expect(!BenchBackend.c_dynamic.runnable());
    try std.testing.expect(BenchBackend.direct.runnable());
    const prof = profileForBenchBackend(.direct);
    try std.testing.expect(prof.backend == .direct);
}

test "backend_identity: explicit C source records no compiler invocation" {
    const m = inferFromCompile(.c, "native", true, true);
    try std.testing.expectEqual(Backend.c, m.backend);
    try std.testing.expectEqual(RepresentationProfile.native, m.representation);
    try std.testing.expect(std.mem.eql(u8, m.boxing_mode, "none"));
    try std.testing.expect(m.external_compiler == null);
}

test "backend_identity: direct/linux/elf produces elf-x86_64 intermediate identity" {
    const m = inferFromCompile(.direct, "x86_64-linux-gnu", true, true);
    try std.testing.expectEqual(Backend.direct, m.backend);
    // The identity must be ELF, not the old hardcoded mach-o-arm64
    try std.testing.expect(std.mem.eql(u8, m.intermediate, "elf-x86_64"));
}

test "backend_identity: direct/macos/macho keeps mach-o-arm64 intermediate identity" {
    const m = inferFromCompile(.direct, "aarch64-macos", true, true);
    try std.testing.expectEqual(Backend.direct, m.backend);
    try std.testing.expect(std.mem.eql(u8, m.intermediate, "mach-o-arm64"));
}

test "backend_identity: elf-x86_64 and mach-o-arm64 identities are distinct" {
    const linux_m = inferFromCompile(.direct, "x86_64-linux-gnu", true, true);
    const macos_m = inferFromCompile(.direct, "aarch64-macos", true, true);
    try std.testing.expect(!std.mem.eql(u8, linux_m.intermediate, macos_m.intermediate));
}

test "backend_identity: wasm32-wasi intermediate identity is distinct from direct" {
    const wasm_m = inferFromCompile(.wasm, "wasm32-wasi", true, true);
    try std.testing.expectEqual(Backend.wasm, wasm_m.backend);
    try std.testing.expectEqual(RepresentationProfile.native, wasm_m.representation);
    try std.testing.expectEqual(RuntimeProfile.minimal, wasm_m.runtime);
    // The wasm backend identity is the WASM intermediate, never ELF or Mach-O
    try std.testing.expect(std.mem.eql(u8, wasm_m.intermediate, "wasm32-wasi"));
    // The wasm backend writes .wasm bytes directly via wasm_backend.zig — no
    // external C compiler is invoked, so external_compiler must be null.
    try std.testing.expect(wasm_m.external_compiler == null);

    const direct_m = inferFromCompile(.direct, "x86_64-linux-gnu", true, true);
    // The two identities must differ — wasm32-wasi != elf-x86_64
    try std.testing.expect(!std.mem.eql(u8, wasm_m.intermediate, direct_m.intermediate));
}

test "backend_identity: wasm intermediate identity is consistent across inferFromCompile and inferIntermediateFromTarget" {
    // The wasm backend must route through BackendTarget.intermediate(), not a
    // string comparison, so every wasm target gets the same identity fact from
    // both code paths. wasm32-wasi is distinct from bare wasm, which is distinct
    // from every direct backend.
    const wasi_target = "wasm32-wasi";
    const wasm_intermediate = inferIntermediateFromTarget(.wasm, wasi_target);
    const compile_intermediate = inferFromCompile(.wasm, wasi_target, true, true).intermediate;
    try std.testing.expectEqualSlices(u8, wasm_intermediate, compile_intermediate);
    try std.testing.expectEqualStrings("wasm32-wasi", compile_intermediate);

    // Direct backend identities must differ from wasm32-wasi
    const linux_m = inferIntermediateFromTarget(.direct, "x86_64-linux-gnu");
    const macos_m = inferIntermediateFromTarget(.direct, "aarch64-macos");
    try std.testing.expect(!std.mem.eql(u8, compile_intermediate, linux_m));
    try std.testing.expect(!std.mem.eql(u8, compile_intermediate, macos_m));
}

test "backend_identity: direct/freebsd/elf produces elf-freebsd-x86_64 intermediate identity" {
    const m = inferFromCompile(.direct, "x86_64-freebsd", true, true);
    try std.testing.expectEqual(Backend.direct, m.backend);
    // The identity must be freebsd ELF, not conflated with linux ELF
    try std.testing.expect(std.mem.eql(u8, m.intermediate, "elf-freebsd-x86_64"));

    const linux_m = inferFromCompile(.direct, "x86_64-linux-gnu", true, true);
    // The two identities must differ — freebsd ELF != linux ELF
    try std.testing.expect(!std.mem.eql(u8, m.intermediate, linux_m.intermediate));
}

test "backend_identity: direct/windows/coff produces coff-x86_64 identity distinct from ELF and Mach-O" {
    const m = inferFromCompile(.direct, "x86_64-windows-msvc", true, true);
    try std.testing.expectEqual(Backend.direct, m.backend);
    // The identity must be COFF, not ELF or Mach-O
    try std.testing.expectEqualStrings("coff-x86_64", m.intermediate);

    // Must differ from direct/linux/elf
    const linux_m = inferFromCompile(.direct, "x86_64-linux-gnu", true, true);
    try std.testing.expect(!std.mem.eql(u8, m.intermediate, linux_m.intermediate));

    // Must differ from direct/macos/macho
    const macos_m = inferFromCompile(.direct, "aarch64-macos", true, true);
    try std.testing.expect(!std.mem.eql(u8, m.intermediate, macos_m.intermediate));
}

test "backend_identity: direct/windows/coff on aarch64 produces coff-aarch64 identity distinct from coff-x86_64" {
    const m = inferFromCompile(.direct, "aarch64-windows-msvc", true, true);
    try std.testing.expectEqual(Backend.direct, m.backend);
    // The identity must be aarch64 COFF, not x86_64 COFF
    try std.testing.expectEqualStrings("coff-aarch64", m.intermediate);

    // Must differ from direct/windows/coff on x86_64 — same object format, different arch
    const x86_m = inferFromCompile(.direct, "x86_64-windows-msvc", true, true);
    try std.testing.expect(!std.mem.eql(u8, m.intermediate, x86_m.intermediate));
}
