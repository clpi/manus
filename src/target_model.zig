//! WP-18 — structured target triple + emit kind (replaces ambiguous "native-*" names).
const std = @import("std");
const builtin = @import("builtin");

pub const SCHEMA_VERSION = "target-model-v0";

pub const Arch = enum {
    aarch64,
    x86_64,
    wasm32,
    unknown,

    pub fn name(self: Arch) []const u8 {
        return switch (self) {
            .aarch64 => "aarch64",
            .x86_64 => "x86_64",
            .wasm32 => "wasm32",
            .unknown => "unknown",
        };
    }

    pub fn parse(s: []const u8) ?Arch {
        if (std.mem.eql(u8, s, "aarch64") or std.mem.eql(u8, s, "arm64")) return .aarch64;
        if (std.mem.eql(u8, s, "x86_64") or std.mem.eql(u8, s, "x64")) return .x86_64;
        if (std.mem.eql(u8, s, "wasm32")) return .wasm32;
        return null;
    }
};

pub const Os = enum {
    macos,
    linux,
    wasi,
    windows,
    none,
    unknown,

    pub fn name(self: Os) []const u8 {
        return switch (self) {
            .macos => "macos",
            .linux => "linux",
            .wasi => "wasi",
            .windows => "windows",
            .none => "none",
            .unknown => "unknown",
        };
    }

    pub fn parse(s: []const u8) ?Os {
        if (std.mem.eql(u8, s, "macos") or std.mem.eql(u8, s, "darwin")) return .macos;
        if (std.mem.eql(u8, s, "linux")) return .linux;
        if (std.mem.eql(u8, s, "wasi")) return .wasi;
        if (std.mem.eql(u8, s, "windows") or std.mem.eql(u8, s, "win32")) return .windows;
        if (std.mem.eql(u8, s, "none") or std.mem.eql(u8, s, "freestanding")) return .none;
        return null;
    }
};

pub const Abi = enum {
    gnu,
    musl,
    msvc,
    none,
    unknown,

    pub fn name(self: Abi) []const u8 {
        return @tagName(self);
    }

    pub fn parse(s: []const u8) ?Abi {
        if (std.mem.eql(u8, s, "gnu")) return .gnu;
        if (std.mem.eql(u8, s, "musl")) return .musl;
        if (std.mem.eql(u8, s, "msvc")) return .msvc;
        if (std.mem.eql(u8, s, "none")) return .none;
        return null;
    }
};

pub const ObjectFormat = enum {
    macho,
    elf,
    coff,
    wasm,
    unknown,

    pub fn name(self: ObjectFormat) []const u8 {
        return @tagName(self);
    }
};

pub const EmitKind = enum {
    obj,
    exe,
    dylib,
    shared_lib,
    assembly,
    /// Portable C99 source from the graph-backed C physical realizer.
    /// This is output format only; it does not select the realizer.
    c,
    wasm,

    pub fn name(self: EmitKind) []const u8 {
        return switch (self) {
            .obj => "obj",
            .exe => "exe",
            .dylib => "dylib",
            .shared_lib => "so",
            .assembly => "asm",
            .c => "c",
            .wasm => "wasm",
        };
    }

    pub fn parse(s: []const u8) ?EmitKind {
        if (std.mem.eql(u8, s, "obj") or std.mem.eql(u8, s, "object")) return .obj;
        if (std.mem.eql(u8, s, "exe") or std.mem.eql(u8, s, "executable")) return .exe;
        if (std.mem.eql(u8, s, "dylib")) return .dylib;
        if (std.mem.eql(u8, s, "so") or std.mem.eql(u8, s, "shared")) return .shared_lib;
        if (std.mem.eql(u8, s, "asm") or std.mem.eql(u8, s, "assembly")) return .assembly;
        if (std.mem.eql(u8, s, "c")) return .c;
        if (std.mem.eql(u8, s, "wasm")) return .wasm;
        return null;
    }
};

/// Windows COFF/PE status for release scope.
pub const WindowsStatus = enum {
    supported,
    experimental,
    planned,
    out_of_scope,

    pub fn current() WindowsStatus {
        return .planned;
    }

    pub fn name(self: WindowsStatus) []const u8 {
        return switch (self) {
            .supported => "supported",
            .experimental => "experimental",
            .planned => "planned",
            .out_of_scope => "out_of_release_scope",
        };
    }
};

pub const TargetTriple = struct {
    arch: Arch,
    os: Os,
    abi: Abi,

    pub fn formatTriple(self: TargetTriple, buf: []u8) []const u8 {
        if (self.os == .none)
            return std.fmt.bufPrint(buf, "{s}-none", .{self.arch.name()}) catch self.arch.name();
        if (self.abi == .unknown or self.abi == .none)
            return std.fmt.bufPrint(buf, "{s}-{s}", .{ self.arch.name(), self.os.name() }) catch self.arch.name();
        return std.fmt.bufPrint(buf, "{s}-{s}-{s}", .{ self.arch.name(), self.os.name(), self.abi.name() }) catch self.arch.name();
    }

    pub fn objectFormat(self: TargetTriple) ObjectFormat {
        return switch (self.os) {
            .macos => .macho,
            .linux => .elf,
            .windows => .coff,
            .wasi, .none => .wasm,
            .unknown => .unknown,
        };
    }

    /// Direct backend support matrix (honest status).
    pub fn directBackendSupported(self: TargetTriple) bool {
        return self.arch == .aarch64 and self.os == .macos;
    }
};

pub const ResolvedTarget = struct {
    triple: TargetTriple,
    emit: EmitKind,
    legacy_name: ?[]const u8 = null,

    pub fn requiresDirectBackend(self: ResolvedTarget) bool {
        return self.emit == .obj or self.emit == .assembly or
            (self.emit == .exe and self.triple.directBackendSupported()) or
            self.emit == .dylib;
    }

    /// Map structured target back to legacy CLI name when on direct-backend triple.
    pub fn toLegacyTargetName(self: ResolvedTarget) ?[]const u8 {
        if (self.legacy_name) |n| return n;
        if (self.emit == .c) return "c-source";
        if (!self.triple.directBackendSupported()) return null;
        return switch (self.emit) {
            .obj => "native-object",
            .assembly => "native-asm",
            .exe => "native-exe",
            .dylib => "native-dylib",
            else => null,
        };
    }
};

/// Unified entry: legacy name, structured triple, or wasm alias.
pub fn resolveTargetInput(target: []const u8, emit: EmitKind) ?ResolvedTarget {
    if (resolveLegacyTarget(target)) |r| {
        // A bare `native` is the only legacy name that says nothing about the
        // output format, and resolveLegacyTarget hardcodes `.emit = .exe` for
        // it — so `--emit asm` was overwritten before anything downstream could
        // read it, and `duo compile --emit asm x.id -o out.s` wrote a Mach-O
        // EXECUTABLE while reporting `ok compile`. Every other legacy name
        // (`native-asm`, `native-object`, …) names its own format and keeps it.
        //
        // Same family as gap[015] (--emit obj/dylib) and gap[019] (--emit
        // wasm): the wrong format was silent.
        if (r.legacy_name) |n| {
            if (std.mem.eql(u8, n, "native") and emit != .exe) {
                return .{ .triple = r.triple, .emit = emit, .legacy_name = null };
            }
        }
        return r;
    }
    return parseStructuredTarget(target, emit);
}

/// Legacy CLI names retained for compatibility; map to structured triple + emit.
pub fn resolveLegacyTarget(name: []const u8) ?ResolvedTarget {
    if (std.mem.eql(u8, name, "native")) {
        return .{
            .triple = hostTriple(),
            .emit = .exe,
            .legacy_name = name,
        };
    }
    if (std.mem.eql(u8, name, "native-object") or std.mem.eql(u8, name, "native-mach-o")) {
        return .{
            .triple = .{ .arch = .aarch64, .os = .macos, .abi = .gnu },
            .emit = .obj,
            .legacy_name = name,
        };
    }
    if (std.mem.eql(u8, name, "native-asm")) {
        return .{
            .triple = .{ .arch = .aarch64, .os = .macos, .abi = .gnu },
            .emit = .assembly,
            .legacy_name = name,
        };
    }
    if (std.mem.eql(u8, name, "native-exe")) {
        return .{
            .triple = .{ .arch = .aarch64, .os = .macos, .abi = .gnu },
            .emit = .exe,
            .legacy_name = name,
        };
    }
    if (std.mem.eql(u8, name, "native-dylib")) {
        return .{
            .triple = .{ .arch = .aarch64, .os = .macos, .abi = .gnu },
            .emit = .dylib,
            .legacy_name = name,
        };
    }
    if (std.mem.eql(u8, name, "wasm32-wasi")) {
        return .{
            .triple = .{ .arch = .wasm32, .os = .wasi, .abi = .none },
            .emit = .wasm,
            .legacy_name = name,
        };
    }
    return null;
}

/// Parse `--target aarch64-macos --emit exe` style (emit defaults to exe for bare triples).
pub fn parseStructuredTarget(triple_str: []const u8, emit: EmitKind) ?ResolvedTarget {
    var parts: [4][]const u8 = undefined;
    var n: usize = 0;
    var iter = std.mem.splitScalar(u8, triple_str, '-');
    while (iter.next()) |p| {
        if (n >= parts.len) return null;
        parts[n] = p;
        n += 1;
    }
    if (n < 2) return null;
    const arch = Arch.parse(parts[0]) orelse return null;
    const os = Os.parse(parts[1]) orelse return null;
    const abi: Abi = if (n >= 3) Abi.parse(parts[2]) orelse .unknown else .unknown;
    return .{
        .triple = .{ .arch = arch, .os = os, .abi = abi },
        .emit = emit,
        .legacy_name = null,
    };
}

pub fn hostTriple() TargetTriple {
    const arch: Arch = switch (builtin.cpu.arch) {
        .aarch64 => .aarch64,
        .x86_64 => .x86_64,
        else => .unknown,
    };
    const os_tag: Os = switch (builtin.os.tag) {
        .macos => .macos,
        .linux => .linux,
        .wasi => .wasi,
        .windows => .windows,
        else => .unknown,
    };
    return .{ .arch = arch, .os = os_tag, .abi = .gnu };
}

pub fn writeJson(w: *std.Io.Writer) !void {
    const host = hostTriple();
    var triple_buf: [64]u8 = undefined;
    const host_str = host.formatTriple(&triple_buf);
    try w.print(
        "{{\"schema\":\"{s}\",\"host_triple\":\"{s}\",\"windows_status\":\"{s}\",\"direct_supported_triples\":[\"aarch64-macos\"],\"planned_triples\":[\"x86_64-linux-gnu\",\"x86_64-macos\",\"aarch64-linux-gnu\",\"x86_64-windows-msvc\",\"aarch64-windows-msvc\"],\"legacy_aliases\":{{\"native-exe\":\"aarch64-macos/exe\",\"native-object\":\"aarch64-macos/obj\",\"wasm32-wasi\":\"wasm32-wasi/wasm\"}}}}",
        .{ SCHEMA_VERSION, host_str, WindowsStatus.current().name() },
    );
}

pub const ArchitectureCell = struct {
    feature_id: []const u8,
    target: []const u8,
    backend: []const u8,
    status: []const u8,
};

/// P14-A4 — honest feature×target×backend matrix (subset; grows with proofs).
pub const architecture_matrix: []const ArchitectureCell = &.{
    .{ .feature_id = "native_scalar_codegen", .target = "aarch64-macos", .backend = "c", .status = "partial" },
    .{ .feature_id = "native_scalar_codegen", .target = "aarch64-macos", .backend = "direct", .status = "partial" },
    .{ .feature_id = "native_object_emission", .target = "aarch64-macos", .backend = "direct", .status = "proven" },
    .{ .feature_id = "sealed_record_access", .target = "aarch64-macos", .backend = "direct", .status = "proven" },
    .{ .feature_id = "keyword_classifier", .target = "host", .backend = "c", .status = "proven" },
    .{ .feature_id = "wasm_decode_hot", .target = "host", .backend = "c", .status = "partial" },
    .{ .feature_id = "wasm_module", .target = "wasm32-wasi", .backend = "c", .status = "partial" },
    .{ .feature_id = "wasm_module", .target = "wasm32-wasi", .backend = "wasmtime", .status = "partial" },
    .{ .feature_id = "direct_backend", .target = "x86_64-linux-gnu", .backend = "direct", .status = "open" },
    .{ .feature_id = "direct_backend", .target = "x86_64-windows-msvc", .backend = "direct", .status = "open" },
};

pub fn writeArchitectureMatrixJson(w: *std.Io.Writer) !void {
    try w.writeAll("[");
    for (architecture_matrix, 0..) |cell, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"feature\":\"{s}\",\"target\":\"{s}\",\"backend\":\"{s}\",\"status\":\"{s}\"}}", .{
            cell.feature_id,
            cell.target,
            cell.backend,
            cell.status,
        });
    }
    try w.writeAll("]");
}

test "target_model: legacy native-exe resolves to aarch64-macos exe" {
    const r = resolveLegacyTarget("native-exe").?;
    try std.testing.expectEqual(Arch.aarch64, r.triple.arch);
    try std.testing.expectEqual(Os.macos, r.triple.os);
    try std.testing.expectEqual(EmitKind.exe, r.emit);
    try std.testing.expect(r.triple.directBackendSupported());
}

test "target_model: structured triple parse" {
    const r = parseStructuredTarget("x86_64-linux-gnu", .obj).?;
    try std.testing.expectEqual(Arch.x86_64, r.triple.arch);
    try std.testing.expectEqual(Os.linux, r.triple.os);
    try std.testing.expectEqual(ObjectFormat.elf, r.triple.objectFormat());
    try std.testing.expect(!r.triple.directBackendSupported());
}

test "target_model: structured aarch64-macos maps to native-exe" {
    const r = parseStructuredTarget("aarch64-macos", .exe).?;
    try std.testing.expectEqualStrings("native-exe", r.toLegacyTargetName().?);
}

test "target_model: structured aarch64-macos obj maps to native-object" {
    const r = parseStructuredTarget("aarch64-macos", .obj).?;
    try std.testing.expectEqualStrings("native-object", r.toLegacyTargetName().?);
}

test "target_model: portable C output is independent of direct-native support" {
    try std.testing.expectEqual(EmitKind.c, EmitKind.parse("c").?);
    const target = parseStructuredTarget("x86_64-linux-gnu", .c).?;
    try std.testing.expectEqualStrings("c-source", target.toLegacyTargetName().?);
    try std.testing.expect(!target.requiresDirectBackend());
}

test "target_model: resolveTargetInput accepts legacy names" {
    const r = resolveTargetInput("native-exe", .exe).?;
    try std.testing.expectEqualStrings("native-exe", r.toLegacyTargetName().?);
}

test "target_model: windows status is planned" {
    try std.testing.expectEqual(WindowsStatus.planned, WindowsStatus.current());
}

test "target_model: architecture matrix includes wasm decode row" {
    var found = false;
    for (architecture_matrix) |cell| {
        if (std.mem.eql(u8, cell.feature_id, "wasm_decode_hot")) found = true;
    }
    try std.testing.expect(found);
}
