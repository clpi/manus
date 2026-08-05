//! Pass 9 — Ward readiness matrix: Duo capability ↔ Ward subsystem contract.
//!
//! Canonical owner for machine-readable readiness status. Ward consumes Duo;
//! this module does not duplicate Ward runtime code.
const std = @import("std");

pub const SCHEMA_VERSION = "ward-readiness-v0";

pub const ReadinessStatus = enum(u8) {
    absent,
    spike,
    partial,
    stable_internal,
    public_experimental,
    ward_ready,
    proven_in_ward,

    pub fn name(self: ReadinessStatus) []const u8 {
        return @tagName(self);
    }
};

pub const CapabilityCategory = enum(u8) {
    language,
    semantic_architecture,
    native_compiler,
    runtime,
    tooling,

    pub fn name(self: CapabilityCategory) []const u8 {
        return @tagName(self);
    }
};

pub const DuoCapability = struct {
    id: []const u8,
    title: []const u8,
    category: CapabilityCategory,
    owner: []const u8,
    status: ReadinessStatus,
    ward_consumers: []const []const u8,
    blockers: []const []const u8,
    validation_cmd: ?[]const u8 = null,
    proof_artifact: ?[]const u8 = null,
};

pub const WardSubsystem = struct {
    id: []const u8,
    title: []const u8,
    ladder_level: u8,
    status: ReadinessStatus,
    duo_capability_ids: []const []const u8,
    blockers: []const []const u8,
    owner: ?[]const u8 = null,
    proof_artifact: ?[]const u8 = null,
};

pub const RepositoryTruth = struct {
    id: []const u8,
    path: []const u8,
    role: []const u8,
    notes: []const u8,
};

/// Duo foundations required before Ward milestones (Pass 9 §4).
pub const duo_capabilities: []const DuoCapability = &.{
    // Language
    .{ .id = "duo.lang.native_int_bit", .title = "Native integer and bit operations", .category = .language, .owner = "src/types.zig + lib/std/bit.duo", .status = .partial, .ward_consumers = &.{ "ward.leb128", "ward.instruction_decode" }, .blockers = &.{ "hot LEB128 path still uses dynamic std.bit tables" }, .validation_cmd = "zig build unit-test -- --test-filter bit" },
    .{ .id = "duo.lang.slices_buffers", .title = "Byte slices and bounded buffers", .category = .language, .owner = "lib/std/cursor.duo + lib/std/bytes.duo", .status = .partial, .ward_consumers = &.{ "ward.binary_reader", "ward.section_parse" }, .blockers = &.{ "str+NUL breaks strlen; need slice+len native type; record ctor codegen open" }, .proof_artifact = "examples/pass9/leb128_cursor_smoke.duo", .validation_cmd = "duo run examples/pass9/leb128_cursor_smoke.duo" },
    .{ .id = "duo.lang.descriptors", .title = "Record/table descriptors (@{})", .category = .language, .owner = "src/wasm_semantic.zig + lib/std/wasm/instruction.duo", .status = .partial, .ward_consumers = &.{ "ward.wasm_instruction_model" }, .blockers = &.{ "ward extended opcodes in op.duo; MVP via std.wasm.ward_mvp_opcodes" }, .validation_cmd = "duo run examples/pass9/decode_semantic_smoke.duo", .proof_artifact = "lib/std/wasm/opcode_lookup.duo" },
    .{ .id = "duo.lang.variants", .title = "Compact tagged variants", .category = .language, .owner = "src/types.zig (union/enum)", .status = .partial, .ward_consumers = &.{ "ward.runtime_value" }, .blockers = &.{ "runtime values still often dynamic" } },
    .{ .id = "duo.lang.return_packs", .title = "Direct error/return packs", .category = .language, .owner = "src/sema.zig + src/codegen.zig", .status = .partial, .ward_consumers = &.{ "ward.traps", "ward.host_calls" }, .blockers = &.{ "not uniformly native on proof paths" } },
    .{ .id = "duo.lang.comptime", .title = "Compile-time evaluation (@comp.*)", .category = .language, .owner = "src/comptime.zig + src/wasm_semantic_gen.zig", .status = .stable_internal, .ward_consumers = &.{ "ward.decoder_gen", "ward.validator_gen" }, .blockers = &.{ "Duo-side @comp emission of tables open; Zig comptime tables landed" }, .validation_cmd = "zig test src/wasm_semantic_gen.zig", .proof_artifact = "src/wasm_semantic_gen.zig" },
    .{ .id = "duo.lang.modules", .title = "Modules and req imports", .category = .language, .owner = "src/parser.zig + lib/std.duo", .status = .stable_internal, .ward_consumers = &.{ "ward.all" }, .blockers = &.{} },
    // Semantic architecture
    .{ .id = "duo.sem.graph", .title = "Semantic graph lift", .category = .semantic_architecture, .owner = "src/semantic_graph.zig", .status = .partial, .ward_consumers = &.{ "ward.instruction_provenance" }, .blockers = &.{ "Wasm instructions not lifted" }, .validation_cmd = "duo graph examples/pass8/realization_smoke.duo" },
    .{ .id = "duo.sem.realization", .title = "Realization variables and candidates", .category = .semantic_architecture, .owner = "src/realization.zig", .status = .partial, .ward_consumers = &.{ "ward.dispatch", "ward.interpreter" }, .blockers = &.{ "no dispatch candidate registry for Ward yet" }, .validation_cmd = "duo realize examples/pass8/realization_smoke.duo" },
    .{ .id = "duo.sem.fingerprints", .title = "Semantic fingerprints", .category = .semantic_architecture, .owner = "src/semantic_fingerprint.zig", .status = .partial, .ward_consumers = &.{ "ward.cache", "ward.specialization" }, .blockers = &.{} },
    .{ .id = "duo.sem.evidence", .title = "Evidence and outcome records", .category = .semantic_architecture, .owner = "src/evidence_record.zig + src/optimization_outcome.zig", .status = .partial, .ward_consumers = &.{ "ward.benchmarks" }, .blockers = &.{} },
    .{ .id = "duo.sem.persistence", .title = "Persistent semantic cache", .category = .semantic_architecture, .owner = "src/persistent_semantic_state.zig + src/compile_semantic_cache.zig", .status = .partial, .ward_consumers = &.{ "ward.jit_cache" }, .blockers = &.{ "not yet used by Ward artifacts" } },
    // Native compiler
    .{ .id = "duo.native.repr_select", .title = "Representation selection", .category = .native_compiler, .owner = "src/realization.zig + src/codegen.zig", .status = .partial, .ward_consumers = &.{ "ward.runtime_value", "ward.dispatch" }, .blockers = &.{ "codegen bridge partial for records only" } },
    .{ .id = "duo.native.aggregates", .title = "Native aggregate lowering", .category = .native_compiler, .owner = "src/codegen.zig", .status = .partial, .ward_consumers = &.{ "ward.frames", "ward.memory" }, .blockers = &.{ "Ward hot paths still dynamic" }, .validation_cmd = "DUO_KEEP_C=1 duo compile examples/pass8/realization_smoke.duo" },
    .{ .id = "duo.native.backend", .title = "Native machine-code backend", .category = .native_compiler, .owner = "src/native_backend.zig", .status = .partial, .ward_consumers = &.{ "ward.baseline_jit" }, .blockers = &.{ "limited typed coverage; no Ward JIT yet" }, .validation_cmd = "duo compile --target native-exe examples/native_exe_smoke.duo" },
    .{ .id = "duo.native.bounds", .title = "Bounds checks with explanation", .category = .native_compiler, .owner = "src/codegen.zig + duo explain", .status = .partial, .ward_consumers = &.{ "ward.linear_memory" }, .blockers = &.{} },
    // Runtime
    .{ .id = "duo.rt.arenas", .title = "Arenas and bounded allocation", .category = .runtime, .owner = "lib/std/mem.duo", .status = .partial, .ward_consumers = &.{ "ward.interpreter", "ward.module_instantiate" }, .blockers = &.{ "mem.duo uses __emit malloc stubs; not Ward-ready" } },
    .{ .id = "duo.rt.exec_memory", .title = "Executable memory / code cache", .category = .runtime, .owner = "src/codegen.zig (ward_os hints)", .status = .spike, .ward_consumers = &.{ "ward.jit", "ward.machine_code_cache" }, .blockers = &.{ "Ward JIT exists in ~/x/ward but not proven via Duo native path" } },
    .{ .id = "duo.rt.wasm_stdlib", .title = "Wasm binary stdlib (std.wasm)", .category = .runtime, .owner = "lib/std/wasm.duo", .status = .partial, .ward_consumers = &.{ "ward.module", "ward.decode" }, .blockers = &.{ "dynamic reader; duplicated opcode facts vs ward/src/wasm/op.duo" }, .proof_artifact = "lib/std/wasm.duo" },
    // Tooling
    .{ .id = "duo.tool.catalog", .title = "Machine-readable duo catalog", .category = .tooling, .owner = "src/pass3_catalog.zig", .status = .stable_internal, .ward_consumers = &.{ "ward.coordination" }, .blockers = &.{}, .validation_cmd = "duo catalog | jq '.pass9'" },
    .{ .id = "duo.tool.explain", .title = "Compiler explain pipeline", .category = .tooling, .owner = "src/explain_pipeline.zig", .status = .partial, .ward_consumers = &.{ "ward.hot_path_audit" }, .blockers = &.{ "Ward-specific queries not registered" }, .validation_cmd = "duo explain examples/pass8/realization_smoke.duo" },
    .{ .id = "duo.tool.lsp", .title = "duo-lsp semantic services", .category = .tooling, .owner = "~/x/duo-lsp", .status = .partial, .ward_consumers = &.{ "ward.instruction_hover" }, .blockers = &.{ "no Wasm descriptor navigation" } },
    .{ .id = "duo.tool.mcp", .title = "End-user duo-mcp", .category = .tooling, .owner = "~/x/duo-mcp", .status = .partial, .ward_consumers = &.{ "ward.semantic_query" }, .blockers = &.{ "readiness matrix not exposed yet" } },
};

/// Ward subsystems (Pass 9 §2 Goal A). Status reflects Duo readiness, not Ward implementation.
pub const ward_subsystems: []const WardSubsystem = &.{
    .{ .id = "ward.sub.byte_bit", .title = "Byte and bit primitives", .ladder_level = 1, .status = .partial, .duo_capability_ids = &.{ "duo.lang.native_int_bit" }, .blockers = &.{ "typed native LEB128 hot path missing" }, .owner = "lib/std/bit.duo" },
    .{ .id = "ward.sub.wasm_schema", .title = "Wasm binary schema", .ladder_level = 2, .status = .partial, .duo_capability_ids = &.{ "duo.rt.wasm_stdlib" }, .blockers = &.{ "constants duplicated across std.wasm and ward/op.duo" }, .owner = "lib/std/wasm.duo" },
    .{ .id = "ward.sub.binary_reader", .title = "Buffered binary reader", .ladder_level = 1, .status = .partial, .duo_capability_ids = &.{ "duo.lang.slices_buffers" }, .blockers = &.{ "dynamic table cursor" } },
    .{ .id = "ward.sub.leb128", .title = "LEB128 decoding", .ladder_level = 1, .status = .partial, .duo_capability_ids = &.{ "duo.lang.native_int_bit", "duo.lang.slices_buffers" }, .blockers = &.{ "numeric LEB128 smoke passes; Ward module.duo still uses @c.emit path" }, .owner = "lib/std/cursor.duo", .proof_artifact = "examples/pass9/leb128_cursor_smoke.duo" },
    .{ .id = "ward.sub.instruction_decode", .title = "Instruction decoding", .ladder_level = 2, .status = .partial, .duo_capability_ids = &.{ "duo.lang.descriptors", "duo.lang.comptime" }, .blockers = &.{ "mvp_opcode_index table in wasm_semantic.zig; P9-06 native lowering + op.duo dedupe open" }, .owner = "src/wasm_semantic.zig", .proof_artifact = "examples/pass9/decoder_table_smoke.duo" },
    .{ .id = "ward.sub.section_parse", .title = "Module section parsing", .ladder_level = 3, .status = .partial, .duo_capability_ids = &.{ "duo.rt.wasm_stdlib" }, .blockers = &.{ "std.wasm section coverage incomplete" } },
    .{ .id = "ward.sub.validation", .title = "Validation", .ladder_level = 3, .status = .partial, .duo_capability_ids = &.{ "duo.lang.descriptors", "duo.sem.graph" }, .blockers = &.{ "validator stack table in wasm_semantic_gen.zig; runtime validator dispatch open" }, .proof_artifact = "examples/pass9/validator_stack_smoke.duo" },
    .{ .id = "ward.sub.runtime_value", .title = "Runtime value representation", .ladder_level = 4, .status = .partial, .duo_capability_ids = &.{ "duo.native.repr_select", "duo.lang.variants" }, .blockers = &.{} , .owner = "~/x/ward/src/wasm/value.duo" },
    .{ .id = "ward.sub.linear_memory", .title = "Linear memory", .ladder_level = 4, .status = .partial, .duo_capability_ids = &.{ "duo.native.bounds", "duo.native.aggregates" }, .blockers = &.{} , .owner = "~/x/ward/src/wasm/memory.duo" },
    .{ .id = "ward.sub.tables_refs", .title = "Tables and references", .ladder_level = 4, .status = .spike, .duo_capability_ids = &.{ "duo.rt.wasm_stdlib" }, .blockers = &.{} , .owner = "~/x/ward/src/wasm/table.duo" },
    .{ .id = "ward.sub.func_sigs", .title = "Function signatures", .ladder_level = 2, .status = .partial, .duo_capability_ids = &.{ "duo.rt.wasm_stdlib" }, .blockers = &.{} },
    .{ .id = "ward.sub.interpreter_frames", .title = "Interpreter frames", .ladder_level = 4, .status = .spike, .duo_capability_ids = &.{ "duo.native.aggregates", "duo.rt.arenas" }, .blockers = &.{} , .owner = "~/x/ward/src/wasm/stack.duo" },
    .{ .id = "ward.sub.dispatch", .title = "Dispatch", .ladder_level = 4, .status = .spike, .duo_capability_ids = &.{ "duo.sem.realization" }, .blockers = &.{ "realization not applied to dispatch" }, .owner = "~/x/ward/src/wasm/runtime.duo" },
    .{ .id = "ward.sub.host_calls", .title = "Host calls", .ladder_level = 4, .status = .partial, .duo_capability_ids = &.{ "duo.lang.return_packs" }, .blockers = &.{} , .owner = "~/x/ward/src/wasm/wasi.duo" },
    .{ .id = "ward.sub.imports_exports", .title = "Imports and exports", .ladder_level = 3, .status = .partial, .duo_capability_ids = &.{ "duo.rt.wasm_stdlib" }, .blockers = &.{} },
    .{ .id = "ward.sub.traps", .title = "Traps", .ladder_level = 4, .status = .spike, .duo_capability_ids = &.{ "duo.lang.return_packs" }, .blockers = &.{} },
    .{ .id = "ward.sub.baseline_compile", .title = "Baseline compilation", .ladder_level = 6, .status = .spike, .duo_capability_ids = &.{ "duo.native.backend" }, .blockers = &.{} , .owner = "~/x/ward/src/wasm/aot.duo" },
    .{ .id = "ward.sub.mc_cache", .title = "Machine-code cache", .ladder_level = 6, .status = .absent, .duo_capability_ids = &.{ "duo.rt.exec_memory", "duo.sem.persistence" }, .blockers = &.{ "Level 6 gate not reached" } },
    .{ .id = "ward.sub.optimizing_jit", .title = "Optimizing JIT", .ladder_level = 7, .status = .spike, .duo_capability_ids = &.{ "duo.native.backend" }, .blockers = &.{ "premature — decoder milestone first" }, .owner = "~/x/ward/src/wasm/jit.duo" },
    .{ .id = "ward.sub.simd", .title = "SIMD", .ladder_level = 5, .status = .absent, .duo_capability_ids = &.{ "duo.native.backend" }, .blockers = &.{ "deferred post-decoder" } },
    .{ .id = "ward.sub.threads_atomics", .title = "Threads and atomics", .ladder_level = 7, .status = .absent, .duo_capability_ids = &.{ "duo.native.backend" }, .blockers = &.{} },
    .{ .id = "ward.sub.exceptions", .title = "Exceptions", .ladder_level = 7, .status = .absent, .duo_capability_ids = &.{ "duo.lang.return_packs" }, .blockers = &.{} },
    .{ .id = "ward.sub.gc_proposals", .title = "GC Wasm proposals", .ladder_level = 8, .status = .absent, .duo_capability_ids = &.{ "duo.rt.arenas" }, .blockers = &.{} },
    .{ .id = "ward.sub.component_model", .title = "Component-model boundaries", .ladder_level = 8, .status = .absent, .duo_capability_ids = &.{ "duo.sem.graph" }, .blockers = &.{} },
};

pub const repository_truth: []const RepositoryTruth = &.{
    .{ .id = "repo.duo", .path = "~/x/duo", .role = "compiler + stdlib", .notes = "Canonical language; Pass 9 readiness owner" },
    .{ .id = "repo.ward", .path = "~/x/ward", .role = "Duo-native Wasm runtime (vertical proof)", .notes = "3554 LOC in src/wasm/*.duo; opcodes duplicated in op.duo; module.duo hot reader uses @c.emit+lua_Value" },
    .{ .id = "repo.wart", .path = "~/x/wart", .role = "reference Wasm runtime (Zig)", .notes = "Performance baseline; cmd/, wasm/, conformance/" },
    .{ .id = "repo.duo_mcp", .path = "~/x/duo-mcp", .role = "end-user MCP", .notes = "Coordination + compile tools; Pass 9 dev tracking via catalog" },
    .{ .id = "repo.duo_lsp", .path = "~/x/duo-lsp", .role = "LSP", .notes = "Descriptor hover/navigation not yet Wasm-aware" },
};

fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"', '\\' => try w.print("\\{c}", .{c}),
        else => try w.writeAll(&.{c}),
    };
}

fn writeStringArray(w: *std.Io.Writer, items: []const []const u8) !void {
    try w.print("[", .{});
    for (items, 0..) |item, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("\"", .{});
        try jsonEscape(w, item);
        try w.print("\"", .{});
    }
    try w.print("]", .{});
}

pub fn writeCapabilitiesJson(w: *std.Io.Writer) !void {
    try w.print("[", .{});
    for (duo_capabilities, 0..) |cap, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"", .{});
        try jsonEscape(w, cap.id);
        try w.print("\",\"title\":\"", .{});
        try jsonEscape(w, cap.title);
        try w.print("\",\"category\":\"{s}\",\"owner\":\"", .{cap.category.name()});
        try jsonEscape(w, cap.owner);
        try w.print("\",\"status\":\"{s}\",\"ward_consumers\":", .{cap.status.name()});
        try writeStringArray(w, cap.ward_consumers);
        try w.print(",\"blockers\":", .{});
        try writeStringArray(w, cap.blockers);
        if (cap.validation_cmd) |cmd| {
            try w.print(",\"validation_cmd\":\"", .{});
            try jsonEscape(w, cmd);
            try w.print("\"", .{});
        }
        if (cap.proof_artifact) |art| {
            try w.print(",\"proof_artifact\":\"", .{});
            try jsonEscape(w, art);
            try w.print("\"", .{});
        }
        try w.print("}}", .{});
    }
    try w.print("]", .{});
}

pub fn writeSubsystemsJson(w: *std.Io.Writer) !void {
    try w.print("[", .{});
    for (ward_subsystems, 0..) |sub, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"", .{});
        try jsonEscape(w, sub.id);
        try w.print("\",\"title\":\"", .{});
        try jsonEscape(w, sub.title);
        try w.print("\",\"ladder_level\":{d},\"status\":\"{s}\",\"duo_capability_ids\":", .{
            sub.ladder_level, sub.status.name(),
        });
        try writeStringArray(w, sub.duo_capability_ids);
        try w.print(",\"blockers\":", .{});
        try writeStringArray(w, sub.blockers);
        if (sub.owner) |own| {
            try w.print(",\"owner\":\"", .{});
            try jsonEscape(w, own);
            try w.print("\"", .{});
        }
        if (sub.proof_artifact) |art| {
            try w.print(",\"proof_artifact\":\"", .{});
            try jsonEscape(w, art);
            try w.print("\"", .{});
        }
        try w.print("}}", .{});
    }
    try w.print("]", .{});
}

pub fn writeRepositoryTruthJson(w: *std.Io.Writer) !void {
    try w.print("[", .{});
    for (repository_truth, 0..) |row, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"id\":\"", .{});
        try jsonEscape(w, row.id);
        try w.print("\",\"path\":\"", .{});
        try jsonEscape(w, row.path);
        try w.print("\",\"role\":\"", .{});
        try jsonEscape(w, row.role);
        try w.print("\",\"notes\":\"", .{});
        try jsonEscape(w, row.notes);
        try w.print("\"}}", .{});
    }
    try w.print("]", .{});
}

pub fn countByStatus(comptime which: enum { capabilities, subsystems }, status: ReadinessStatus) usize {
    var n: usize = 0;
    switch (which) {
        .capabilities => for (duo_capabilities) |c| {
            if (c.status == status) n += 1;
        },
        .subsystems => for (ward_subsystems) |s| {
            if (s.status == status) n += 1;
        },
    }
    return n;
}

test "ward_readiness: capability ids unique" {
    for (duo_capabilities, 0..) |a, i| {
        for (duo_capabilities[i + 1 ..]) |b| {
            try std.testing.expect(!std.mem.eql(u8, a.id, b.id));
        }
    }
}

test "ward_readiness: subsystem ids unique" {
    for (ward_subsystems, 0..) |a, i| {
        for (ward_subsystems[i + 1 ..]) |b| {
            try std.testing.expect(!std.mem.eql(u8, a.id, b.id));
        }
    }
}
