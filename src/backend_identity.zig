//! Pass 11 — explicit backend / representation / runtime identity (WP-02 split).
//!
//! Artifact manifests must record all three axes; silent conflation is forbidden.
const std = @import("std");

pub const SCHEMA_VERSION = "backend-identity-v0";

pub const Backend = enum {
    c,
    direct,
    wasm,

    pub fn name(self: Backend) []const u8 {
        return switch (self) {
            .c => "c",
            .direct => "direct",
            .wasm => "wasm",
        };
    }

    pub fn parse(s: []const u8) ?Backend {
        if (std.mem.eql(u8, s, "c")) return .c;
        if (std.mem.eql(u8, s, "direct")) return .direct;
        if (std.mem.eql(u8, s, "wasm")) return .wasm;
        return null;
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

/// Benchmark harness profile (WP-01): explicit boxing path selection.
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

    /// Default canonical benchmark path: strongest generally supported C specialization.
    pub fn defaultCanonical() BenchBackend {
        return .c_specialized;
    }
};

pub const Manifest = struct {
    backend: Backend,
    representation: RepresentationProfile,
    runtime: RuntimeProfile,
    target: []const u8,
    intermediate: []const u8,
    external_compiler: ?[]const u8 = null,
    boxing_mode: []const u8 = "unknown",
};

pub fn inferFromCompile(
    backend: Backend,
    target: []const u8,
    native_scalar: bool,
    duo_mode: bool,
) Manifest {
    const repr: RepresentationProfile = if (!duo_mode)
        .generic
    else if (native_scalar)
        .native
    else
        .specialized;

    const runtime: RuntimeProfile = switch (backend) {
        .c => if (native_scalar) .minimal else if (duo_mode) .dynamic else .full,
        .direct => .freestanding,
        .wasm => .minimal,
    };

    const intermediate: []const u8 = switch (backend) {
        .c => "generated-c",
        .direct => "mach-o-arm64",
        .wasm => if (std.mem.eql(u8, target, "wasm32-wasi")) "wasm32-wasi" else "wasm",
    };

    const boxing: []const u8 = if (native_scalar) "none" else if (duo_mode) "typed-mixed" else "full-dynamic";

    return .{
        .backend = backend,
        .representation = repr,
        .runtime = runtime,
        .target = target,
        .intermediate = intermediate,
        .external_compiler = switch (backend) {
            .c => "clang",
            .direct => null,
            .wasm => "zig cc",
        },
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
    try std.testing.expectEqual(Backend.c, Backend.parse("c").?);
    try std.testing.expectEqual(Backend.direct, Backend.parse("direct").?);
    try std.testing.expect(BenchBackend.parse("c-specialized") == .c_specialized);
}

test "backend_identity: manifest for native scalar C path" {
    const m = inferFromCompile(.c, "native", true, true);
    try std.testing.expectEqual(Backend.c, m.backend);
    try std.testing.expectEqual(RepresentationProfile.native, m.representation);
    try std.testing.expect(std.mem.eql(u8, m.boxing_mode, "none"));
}
