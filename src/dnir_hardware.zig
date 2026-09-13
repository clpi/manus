//! DNIR hardware surface — machine intrinsics below the C bootstrap floor.
//!
//! Typed programs lower `@fence`, `@popcount`, `@clz`, `@ctz`, and spin hints
//! into DNIR `hw_*` ops, then straight to ARM64 (or target-specific backends).
//! No `__builtin_*`, no `lua_Value`, no C-string codegen on these paths.
const std = @import("std");

pub const SCHEMA_VERSION = "dnir-hardware-v0";

/// Capability tier of a hardware intrinsic. ONE VARIANT, because the catalog
/// below has one: every intrinsic this compiler can lower is a bit op, a fence
/// or a yield, and all six `HwIntrinsic` variants report `.scalar`.
///
/// THIS ENUM PREVIOUSLY CARRIED `.vector` AND `.system` AND NOTHING PRODUCED
/// EITHER. A tier nothing produces is not a policy, it is a description of one:
/// `functionHardwareTier` provably returned `.scalar`, so the one comparison
/// that read a tier (`region_graph.validateModuleProjection`) was `f(x) == f(x)`
/// and raised `HardwareTierMismatch` for a mismatch that no reachable program
/// state could produce. Both the variants and that check are deleted.
///
/// THE RULE FOR PUTTING A VARIANT BACK: land it in the same change as the first
/// intrinsic that RETURNS it and the first check that REFUSES on it. Landing it
/// earlier gives a refusal-only mechanism with no admit partner, which
/// `gate/claim.sh` §1 measures and `gate/capability.sh` §1 declines to treat as
/// evidence. `.vector` costs three lines the day `hw_simd` lands.
///
/// `.vector` IS STILL DECLINED, BUT THE REASON PRINTED HERE WAS STALE AND IS
/// CORRECTED. This paragraph said the one vector producer this compiler
/// contains — `dnir_lower.tryEmitVectorReductionPrologue`, which drives
/// `native_backend.emitVecReduceAddI64` — "is called from two sites and BOTH
/// read `if (false) try tryEmitVectorReductionPrologue(...)`, so it has been
/// unreachable since the commit that introduced it". THAT IS NO LONGER TRUE.
/// The two tokens were introduced in `168b6afe` and removed in `d58101bd`;
/// both call sites (`dnir_lower.zig:4882`, `:6138`) are live plain `try`, and
/// the producer FIRES ON THE DEFAULT BUILD WITH NO ENV VAR. Measured at
/// `dec7d509` on `gate/occurrence/reduce.id`:
///
///     add.2d  v16, v16, v17
///     addp.2d d16, v16
///
/// THE CENSUS NUMBER SURVIVES; ITS CAUSE DOES NOT. Re-run at `dec7d509` over
/// every `examples/**/*.id` this compiler can emit — 219 of 547 — assembly
/// containing vector ARITHMETIC (`add`/`sub`/`mul`/`addp`/`fadd`/`fmul` on
/// `.2d`/`.4s`/`.8h`/`.16b`/`.2s`): **zero of 219**. Not because the producer
/// is unreachable, but because no example carries the shape it recognizes: a
/// literal-bounded `acc = acc + tbl[idx]` over a MEMORY-BACKED positional
/// table. An all-literal table over a literal range folds before lowering, and
/// a register-exploded table is declined outright, so the recognizer needs a
/// store the compiler cannot settle. `gate/occurrence/reduce.id` is the only
/// subject in the tree that supplies one, and `gate/occurrence/copy.sh` §1b
/// fails if the producer stops emitting `add.2d`.
///
/// SO THE DECLINATION NOW RESTS ON THE RULE ABOVE AND NOTHING ELSE: no
/// intrinsic RETURNS `.vector` and no check REFUSES on it. The reduction is a
/// producer of vector TEXT, not of a tier: it rides `hw_unary` with
/// `hw == .none` and its selection lives in `Instr.field`, so `intrinsicOfOp`
/// below answers `null` for it and it contributes no `Descriptor` to
/// `collectModuleDescriptors`. Landing the variant before its admit partner
/// would restore exactly the `f(x) == f(x)` comparison the deletion removed.
pub const Tier = enum {
    /// Bit ops, fences, yield — every native target.
    scalar,

    pub fn name(self: Tier) []const u8 {
        return @tagName(self);
    }
};

pub const HwIntrinsic = enum {
    none,
    fence,
    spin_wait,
    popcount,
    clz,
    ctz,

    pub fn tier(self: HwIntrinsic) Tier {
        return switch (self) {
            .none => .scalar,
            .fence, .spin_wait, .popcount, .clz, .ctz => .scalar,
        };
    }

    pub fn duoName(self: HwIntrinsic) []const u8 {
        return switch (self) {
            .none => "none",
            .fence => "fence",
            .spin_wait => "spin_wait",
            .popcount => "popcount",
            .clz => "clz",
            .ctz => "ctz",
        };
    }
};

/// Map internal / bare @-directive callee names to hardware intrinsics.
pub fn parseIntrinsic(name: []const u8) ?HwIntrinsic {
    if (std.mem.eql(u8, name, "__fence") or std.mem.eql(u8, name, "fence")) return .fence;
    if (std.mem.eql(u8, name, "__spin_wait") or std.mem.eql(u8, name, "spin_wait")) return .spin_wait;
    if (std.mem.eql(u8, name, "__popcount") or std.mem.eql(u8, name, "popcount")) return .popcount;
    if (std.mem.eql(u8, name, "__clz") or std.mem.eql(u8, name, "clz")) return .clz;
    if (std.mem.eql(u8, name, "__ctz") or std.mem.eql(u8, name, "ctz")) return .ctz;
    return null;
}

/// Fixed ARM64 A64 encodings (no assembler pass — sovereign object bytes).
pub fn arm64FixedWord(h: HwIntrinsic) ?u32 {
    return switch (h) {
        .fence => 0xd5033bbf, // dmb ish
        .spin_wait => 0xd503203f, // yield
        .none, .popcount, .clz, .ctz => null,
    };
}

/// ONE ARM, because one is live. `emitHwUnary` intercepts `.popcount` into a
/// Kernighan loop and `.ctz` into rbit+clz BEFORE this function is asked, so
/// `.clz` is the only value that ever reaches it.
///
/// THE POPCOUNT ARM IS DELETED, and not merely as dead code. It read
///
///     .popcount => 0x5ac02000 | (rn << 5) | rd, // cnt xd, xn
///
/// and the comment was wrong twice. Assembled and handed to the system
/// disassembler, 0x5ac02000 does not decode at all — `otool -tvV` prints it back
/// as `.long 0x5ac02000` — while 0x5ac01000 on the line below it correctly
/// prints `clz`. `cnt` on a general-purpose register is 0x5ac01c00 (32-bit) /
/// 0xdac01c00 (64-bit) and those do not decode either, because scalar CNT is
/// FEAT_CSSC and `hw.optional.arm.FEAT_CSSC` is **0** on this machine. Bit 31
/// was also clear, so even the intended instruction would have been the 32-bit
/// form under a comment claiming `xd, xn`.
///
/// A wrong encoding behind an unreachable branch is the quietest defect this
/// file can hold: nothing type-checks it, no test executes it, and the day
/// someone routes popcount through here the program takes SIGILL rather than
/// answering wrong. `gate/simd.sh` §1 in idol-native now censuses every word the
/// backend emits for exactly this shape — an instruction the machine's own
/// disassembler cannot name.
pub fn arm64UnaryWord(h: HwIntrinsic, dst: u5, src: u5) ?u32 {
    const rn: u32 = src;
    const rd: u32 = dst;
    return switch (h) {
        .clz => 0xdac01000 | (rn << 5) | rd, // clz xd, xn
        // .popcount — Kernighan loop in the backend, see above.
        // .ctz      — rbit + clz in the backend.
        else => null,
    };
}

/// THE ARM64 BASELINE THIS BACKEND COMPILES AGAINST — every optional CPU
/// feature that any word it can emit requires, named exactly as Darwin's
/// `sysctl hw.optional.arm.<name>` reports it.
///
/// WHY A FIXED BASELINE AND NOT RUNTIME DETECTION. This compiler's builds are
/// reproducible — measured at 0 of 108,744 bytes differing — and a
/// runtime-detected code path buys that away twice over: the binary carries
/// both paths, so the bytes depend on what the *builder's* CPU could see, and
/// the answer depends on what the *runner's* CPU has. A fixed baseline keeps
/// one program with one instruction stream, and turns "does this machine have
/// the feature" from a branch taken a billion times into a question asked once,
/// by a gate, at build time.
///
/// WHY THE LIST IS SHORT. ARMv8-A mandates AdvSIMD, so baseline NEON needs no
/// detection on Apple Silicon and every vector word the backend can emit —
/// `ldr q`, `eor.16b`, `add.2d`, `addp.2d` — is ARMv8.0 base. The features that
/// are genuinely optional and genuinely absent here are the ones worth naming:
/// measured on this machine, FEAT_CSSC = 0 (no scalar CNT/CTZ/ABS/SMAX on GPRs
/// — the reason `arm64UnaryWord`'s deleted popcount arm could never have
/// worked), FEAT_SME = 0, and there is no SVE at all. FEAT_DotProd = 1 and
/// FEAT_I8MM = 1 and neither is used by anything this compiler emits, so
/// neither belongs on this list until a word needs it.
///
/// THIS LIST IS BOTH HALVES OF A MECHANISM. The names are the producer;
/// `gate/simd.sh` §4 is the refusal — it looks each one up through sysctl and
/// fails the run if the machine lacks it, which also means a typo'd name fails
/// rather than silently asserting nothing. Adding a word that needs a feature
/// means adding its name here in the same change.
pub const arm64_required_features: []const []const u8 = &.{
    "AdvSIMD",
};

pub const CatalogEntry = struct {
    intrinsic: HwIntrinsic,
    tier: Tier,
    arm64: []const u8,
    duo_surface: []const u8,
};

pub const catalog: []const CatalogEntry = &.{
    .{ .intrinsic = .fence, .tier = .scalar, .arm64 = "dmb ish", .duo_surface = "@fence / @comp.hint.fence" },
    .{ .intrinsic = .spin_wait, .tier = .scalar, .arm64 = "yield", .duo_surface = "std.hardware.spin_wait" },
    .{ .intrinsic = .popcount, .tier = .scalar, .arm64 = "neon-cnt-addv", .duo_surface = "@popcount / @comp.bit.popcount" },
    .{ .intrinsic = .clz, .tier = .scalar, .arm64 = "clz", .duo_surface = "@clz / @comp.bit.clz" },
    .{ .intrinsic = .ctz, .tier = .scalar, .arm64 = "rbit+clz", .duo_surface = "@ctz / @comp.bit.ctz" },
};

/// Module-level hardware descriptor — one row per intrinsic exercised (WS23).
pub const Descriptor = struct {
    intrinsic: HwIntrinsic,
    tier: Tier,
    arm64_hint: []const u8,
    use_count: u32,
};

pub fn catalogEntry(h: HwIntrinsic) ?CatalogEntry {
    for (catalog) |e| {
        if (e.intrinsic == h) return e;
    }
    return null;
}

pub fn intrinsicOfOp(op: @import("native/ir.zig").Op, hw: HwIntrinsic) ?HwIntrinsic {
    const dnir = @import("native/ir.zig");
    return switch (op) {
        dnir.Op.hw_fence => .fence,
        dnir.Op.hw_spin => .spin_wait,
        dnir.Op.hw_unary => if (hw != .none) hw else null,
        else => null,
    };
}

// `functionHardwareTier` lived here. Its only caller was
// `region_graph.validateModuleProjection`, which compared its result against a
// field that `region_graph.buildFromDnirFunction` had just SET from the same
// call on the same function — a tautology wearing the name of a hardware-policy
// check. With `Tier` reduced to its one real variant the function could only
// ever `return .scalar`, so both it and the check are gone. See `Tier` above for
// the condition under which this comes back.

/// Collect deduplicated hardware descriptors used in a DNIR module.
pub fn collectModuleDescriptors(alloc: std.mem.Allocator, m: @import("native/ir.zig").Module) ![]Descriptor {
    var counts: std.AutoHashMapUnmanaged(HwIntrinsic, u32) = .{};
    defer counts.deinit(alloc);

    for (m.functions) |f| {
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                const h = intrinsicOfOp(ins.op, ins.hw) orelse continue;
                const gop = try counts.getOrPut(alloc, h);
                if (!gop.found_existing) gop.value_ptr.* = 0;
                gop.value_ptr.* += 1;
            }
        }
    }

    var out: std.ArrayListUnmanaged(Descriptor) = .empty;
    errdefer out.deinit(alloc);
    var it = counts.iterator();
    while (it.next()) |e| {
        const entry = catalogEntry(e.key_ptr.*) orelse continue;
        try out.append(alloc, .{
            .intrinsic = e.key_ptr.*,
            .tier = entry.tier,
            .arm64_hint = entry.arm64,
            .use_count = e.value_ptr.*,
        });
    }
    return try out.toOwnedSlice(alloc);
}

pub fn freeModuleDescriptors(alloc: std.mem.Allocator, descs: []Descriptor) void {
    alloc.free(descs);
}

test "dnir_hardware: parse bare intrinsics" {
    try std.testing.expect(parseIntrinsic("__popcount") == .popcount);
    try std.testing.expect(parseIntrinsic("fence") == .fence);
    try std.testing.expect(parseIntrinsic("nope") == null);
}

test "dnir_hardware: arm64 fence word" {
    try std.testing.expect(arm64FixedWord(.fence) == 0xd5033bbf);
}

test "dnir_hardware: arm64UnaryWord answers for clz and refuses for everything else" {
    // `.clz` is the ONE live case. `.popcount` and `.ctz` are lowered in the
    // backend before this is asked; a non-null here would mean a word nobody
    // checked is reachable again. See the doc comment for what the popcount
    // arm's constant actually decoded to.
    try std.testing.expect(arm64UnaryWord(.clz, 0, 0) == 0xdac01000);
    try std.testing.expect(arm64UnaryWord(.popcount, 0, 0) == null);
    try std.testing.expect(arm64UnaryWord(.ctz, 0, 0) == null);
    try std.testing.expect(arm64UnaryWord(.fence, 0, 0) == null);
    try std.testing.expect(arm64UnaryWord(.spin_wait, 0, 0) == null);
    try std.testing.expect(arm64UnaryWord(.none, 0, 0) == null);
}

test "dnir_hardware: the declared baseline is non-empty and sysctl-shaped" {
    // An empty list would make `gate/simd.sh` §4 examine zero features, and a
    // gate that examined zero things has not passed. Each name is spliced into
    // `hw.optional.arm.<name>`, so a name with a dot or a space cannot resolve
    // and would assert nothing rather than fail.
    try std.testing.expect(arm64_required_features.len > 0);
    for (arm64_required_features) |f| {
        try std.testing.expect(f.len > 0);
        try std.testing.expect(std.mem.indexOfAny(u8, f, ". \t") == null);
    }
}

test "dnir_hardware: collectModuleDescriptors" {
    const dnir = @import("native/ir.zig");
    const m = dnir.Module{
        .functions = &.{
            .{
                .name = "main",
                .ret = .i64,
                .blocks = &.{
                    .{
                        .instrs = &.{
                            .{ .op = .hw_fence },
                            .{ .op = .hw_unary, .hw = .popcount, .result = 0, .lhs = .{ .i64 = 47 } },
                            .{ .op = .hw_fence },
                        },
                    },
                },
            },
        },
    };
    const descs = try collectModuleDescriptors(std.testing.allocator, m);
    defer freeModuleDescriptors(std.testing.allocator, descs);
    try std.testing.expect(descs.len >= 2);
    var saw_fence = false;
    var saw_pop = false;
    for (descs) |d| {
        if (d.intrinsic == .fence) {
            saw_fence = true;
            try std.testing.expectEqual(@as(u32, 2), d.use_count);
        }
        if (d.intrinsic == .popcount) {
            saw_pop = true;
            try std.testing.expectEqual(@as(u32, 1), d.use_count);
        }
    }
    try std.testing.expect(saw_fence and saw_pop);
}
