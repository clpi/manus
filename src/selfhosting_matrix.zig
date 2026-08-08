//! Pass 16 §22.1 — self-hosting matrix: host vs Duo ownership per compiler subsystem.
const std = @import("std");

pub const SCHEMA_VERSION = "selfhosting-matrix-v0";

/// Pass 16 §13 migration status for each subsystem.
pub const MigrationStatus = enum {
    seed_only,
    differential_oracle,
    porting,
    duo_canonical,
    retired,
    rejected,
    external_optional,

    pub fn name(self: MigrationStatus) []const u8 {
        return @tagName(self);
    }
};

pub const Subsystem = struct {
    id: []const u8,
    title: []const u8,
    host_impl: []const u8,
    duo_impl: ?[]const u8,
    production_status: MigrationStatus,
    bootstrap_required: bool,
    migration_blocker: ?[]const u8,
    removal_gate: ?[]const u8,
};

/// Honest ownership map at Pass 16 introduction. Update when a subsystem moves to `duo_canonical`.
pub const subsystems: []const Subsystem = &.{
    .{
        .id = "SH-01",
        .title = "Source bytes and cursor",
        .host_impl = "src/lexer.zig → source_cursor.ProductionCursor",
        .duo_impl = "lib/std/compiler/source.duo",
        .production_status = .differential_oracle,
        .bootstrap_required = false,
        .migration_blocker = null,
        .removal_gate = "P16-M1 full Duo ByteCursor dispatch (optional; ProductionCursor integrated)",
    },
    .{
        .id = "SH-02",
        .title = "Token definitions and keyword table",
        .host_impl = "src/token_semantic.zig (differential oracle)",
        .duo_impl = "lib/std/token/classify.duo → src/duo_keyword_classify.c",
        .production_status = .duo_canonical,
        .bootstrap_required = false,
        .migration_blocker = null,
        .removal_gate = "Host branch_chain oracle retained until S1 bootstrap closure",
    },
    .{
        .id = "SH-03",
        .title = "Lexer",
        .host_impl = "src/lexer.zig",
        .duo_impl = "lib/std/compiler/lexer.duo",
        .production_status = .porting,
        .bootstrap_required = false,
        .migration_blocker = "Remaining for duo_canonical: ROUTE the compile driver's lexing through the Duo path. Everything under that is now built and proven. EQUIVALENCE: token-for-token equal to src/lexer.zig on kinds and on TEXT (fingerprint differentials), and now FIELD FOR FIELD -- src/duo_lexer_dispatch.zig differentials kind, line, col, text, int_val and float_val against src/lexer.zig over 8 sources, in the compiler's own unit-test suite, passing. ARTIFACT: src/duo_lexer_tokenize.c is generated from lib/std/compiler/host.duo and LINKED INTO THE PRODUCTION BINARY (build.zig linkProductionDuoLexer); it supplies a strong duo_keyword_classify that overrides the weak one in src/duo_keyword_classify.c, which that file was written weak to permit. It is bootstrap-ledger foreign code, the sanctioned exception, and must be regenerated when lexer.duo changes. ABI: duo_lexer_tokenize_full carries all seven fields the host Token holds; tokenize_text is one field short and dispatch must NOT use it -- GAP-021 showed float_val was wrong for EVERY float literal (`or` on native numerics lowers to C `||`, returning 0/1), undetected because no differential read that field. THE ONE REMAINING STEP: lexer.Lexer.init(src, file) takes no allocator, and a Duo-backed Lexer needs one for the token buffer and text arena. Routing therefore needs either an allocator threaded through ~30 Lexer.init call sites or a Lexer-owned arena with a deinit the API does not currently have. That is a deliberate design change, not a flag flip; tokenizeAuthority() stays .host_zig until the driver genuinely tokenizes through Duo, because flipping it earlier would make the matrix lie.",
        .removal_gate = "Lexer allocator/arena + driver routing + tokenizeAuthority() -> .duo_native; gates: pass16-m1-smoke, selfhost_proofs SH-03, duo_lexer_dispatch differential",
    },
    .{
        .id = "SH-04",
        .title = "Parser",
        .host_impl = "src/parser.zig",
        .duo_impl = "lib/std/compiler/parser.duo",
        .production_status = .porting,
        .bootstrap_required = true,
        .migration_blocker = "Seed only: lib/std/compiler/parser.duo is a recursive-descent expression parser (precedence climbing, mutual recursion between parse_expr and parse_factor, results returned as an ABI-register record with no allocation). It parses characters, not tokens, and covers only the arithmetic subset. Runs on BOTH backends: an @comp.c.export `eval` entry point returns i64 so the record never crosses the module boundary, and the parser -- mutual recursion included -- lowers to native ARM64 (zig build direct-module-link). Cross-module *record* returns still have no C ABI export form. Statements, declarations, types, attributes and the std.compiler.lexer token-stream interface are all still absent. Measured constraints on the token-stream step -- three probes, all on the direct backend. A table lowers natively as a *function local* with dynamic indexing (t = {5,7,9}; t[i] works). But every way of sharing one between functions fails: a table parameter is DNB002 (signature incompatible with the direct ARM64 ABI), a module-scope table is DNB001, and a record with a table field is DNB001. Recursive descent needs the token array shared across mutually recursive functions, so the native subset must gain one of those three before a token-driven parser can lower. Root cause, confirmed in dnir_lower.zig: a table in the native subset has no runtime memory representation at all. It is *exploded* into one local per element (see table_lens and lowerPositionalTableAssign), the same way a record becomes one local per field. That is why indexing a local table works and every sharing form fails -- there is no contiguous array and therefore no pointer to hand across a call. So this is not an ABI rule to relax: it needs a real memory-backed table representation in DNIR plus the ARM64 load/store to match, and no stdlib-primitive detour exists (unlike string.sub, where the obstruction was allocation and could be exported from a module). RESOLVED 2026-08-06 -- the memory-backed representation now exists. `alloc_slots` (duo_native_ir.zig) reserves a frame region sized by a pre-pass, exactly like the record path, so a table built inside a loop does not walk sp; a `ptr` parameter carries the base address in x0..x7 as an integer-class argument; and load_index/store_index with ty == .i64 are scaled 8-byte accesses (`[base, idx, lsl #3]`), the byte semantics of string.byte staying on the other ty. Materialization is lazy -- elements stay in registers for local use and are copied to the frame only at the first call that takes the table -- after which the name is rebound to the base so later reads see callee writes rather than stale registers. Three register-lifetime bugs had to be fixed alongside it (single-arg call, mov_arg, and the indexed ops themselves each released a register the slot map still owned; see releaseDnirTemp). Proven by examples/native_differential/native_only/table_shared_param.duo and parser_token_stream.duo -- the latter is a mutually recursive token-driven expression parser over a shared token array plus a shared cursor, respecting precedence, lowered entirely to native ARM64. Remaining for SH-04: the parser still parses characters rather than a std.compiler.lexer token stream, and statements, declarations, types and attributes are all still absent; cross-module *record* returns still have no C ABI export form. L3 RESOLVED 2026-08-06: lib/std/compiler/parser.duo now has a statement-level, token-stream recursive-descent family (proj_program/proj_stmt/proj_expr + precedence climbing) producing s-expression syntax-graph projections over std.compiler.lexer, gated by examples/pass16_parser_corpus_proof.duo (18 positive exact-sexpr cases + 6 compile-fail rejections) in the pass16-m1-smoke gate. Typed Lexer/Tok params lower to native records; the codegen req-module call emitter now passes record-pointer params through instead of re-address-taking them (src/codegen.zig try_emit_req_module_field_call).",
        .removal_gate = "P16-WS6 + syntax graph",
    },
    .{
        .id = "SH-05",
        .title = "Formatter / canonicalizer",
        .host_impl = "src/fmt.zig",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = false,
        .migration_blocker = "Depends on parser + grammar descriptor convergence",
        .removal_gate = "P16-WS7",
    },
    .{
        .id = "SH-06",
        .title = "Binding and scopes",
        .host_impl = "src/sema.zig",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = true,
        .migration_blocker = "Semantic graph substrate incomplete in Duo",
        .removal_gate = "P16-WS9",
    },
    .{
        .id = "SH-07",
        .title = "Semantic graph",
        .host_impl = "src/semantic_graph.zig",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = true,
        .migration_blocker = "Graph is Zig-hosted partial implementation",
        .removal_gate = "P16-M2",
    },
    .{
        .id = "SH-08",
        .title = "Compile-time evaluator",
        .host_impl = "src/comptime.zig + codegen folds",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = true,
        .migration_blocker = "Compiler-capable Duo profile undefined (P4-12)",
        .removal_gate = "P16-WS11",
    },
    .{
        .id = "SH-09",
        .title = "Transformation registry",
        .host_impl = "src/transform_engine.zig",
        .duo_impl = null,
        .production_status = .porting,
        .bootstrap_required = false,
        .migration_blocker = "Stub + proof hooks; not full optimizer",
        .removal_gate = "P16-WS13",
    },
    .{
        .id = "SH-10",
        .title = "C code generation backend",
        .host_impl = "src/codegen.zig",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = true,
        .migration_blocker = "Canonical path today; must become explicit bootstrap backend",
        .removal_gate = "P16-M3 native loop on one target",
    },
    .{
        .id = "SH-11",
        .title = "Direct native backend (ARM64 Mach-O)",
        .host_impl = "src/native_backend.zig",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = false,
        .migration_blocker = "Scalar subset plus records, u64, string.byte and string.len (DNIR str_len, inline scan, no libc), and — new — calls into separately compiled Duo modules: a qualified call lowers to a bl with a relocation against the module's @comp.c.export symbol, and the compiler emits, builds and links that module itself (zig build direct-module-link). Output is now sovereign too: print (str/i64/f64/blank) lowers to Mach-O _puts/_printf externs via DNIR print_value using the Apple arm64 stack-vararg convention, so a program whose only dynamic surface is output compiles to pure machine code with no C fallback (2026-08-07). string.sub is the next gap: it needs writable data and only read-only __TEXT sections are emitted. That gap is now bypassed, not closed: lib/std/str.duo exports string.sub as a @comp.c.export primitive, so the allocation happens in the module's C and the backend only emits a relocation. Proven on both backends by zig build direct-module-link. A writable __DATA arena / L4 borrowed strings would still be needed to lower string.sub in the backend itself",
        .removal_gate = "P16-WS19 + object writers in Duo",
    },
    .{
        .id = "SH-12",
        .title = "Object writers / link substrate",
        .host_impl = "src/native_backend.zig + platform linker",
        .duo_impl = null,
        .production_status = .external_optional,
        .bootstrap_required = true,
        .migration_blocker = "Mach-O partial; ELF/COFF open",
        .removal_gate = "P16-WS21",
    },
    .{
        .id = "SH-13",
        .title = "Runtime profile",
        .host_impl = "generated duo_runtime preamble",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = true,
        .migration_blocker = "Full dynamic runtime linked for most builds",
        .removal_gate = "P16-WS22 freestanding compiler profile",
    },
    .{
        .id = "SH-14",
        .title = "Build orchestration",
        .host_impl = "build.zig",
        .duo_impl = null,
        .production_status = .external_optional,
        .bootstrap_required = true,
        .migration_blocker = "Zig build is bootstrap orchestrator until S2",
        .removal_gate = "P16-WS23 bootstrap DAG executor",
    },
    .{
        .id = "SH-15",
        .title = "LSP compiler service",
        .host_impl = "~/x/duo-lsp (separate repo)",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = false,
        .migration_blocker = "Must consume shared compiler facts, not re-parse",
        .removal_gate = "P16-WS25",
    },
    .{
        .id = "SH-16",
        .title = "MCP semantic service",
        .host_impl = "~/x/duo-mcp",
        .duo_impl = null,
        .production_status = .seed_only,
        .bootstrap_required = false,
        .migration_blocker = "Development MCP lacks bootstrap stage state",
        .removal_gate = "P16-WS26",
    },
};

pub const Manifest = struct {
    schema: []const u8 = SCHEMA_VERSION,
    self_hosting_level: u8,
    canonical_compiler_in_duo: bool,
    bootstrap_stage_reached: []const u8,
    production_duo_frontend: bool,
    silent_c_fallback: bool,
    claim_self_hosted_status: []const u8,
};

pub fn publicManifest() Manifest {
    return .{
        .self_hosting_level = 1,
        .canonical_compiler_in_duo = false,
        .bootstrap_stage_reached = "S0",
        .production_duo_frontend = true,
        .silent_c_fallback = true,
        .claim_self_hosted_status = "partial",
    };
}

pub fn countByStatus(status: MigrationStatus) usize {
    var n: usize = 0;
    for (subsystems) |s| {
        if (s.production_status == status) n += 1;
    }
    return n;
}

pub fn writeMatrixJson(w: *std.Io.Writer) !void {
    try w.print("{{\"schema\":\"{s}\",\"subsystems\":[", .{SCHEMA_VERSION});
    for (subsystems, 0..) |s, i| {
        if (i > 0) try w.writeAll(",");
        try w.print(
            "{{\"id\":\"{s}\",\"title\":\"{s}\",\"host_impl\":\"{s}\",\"duo_impl\":",
            .{ s.id, s.title, s.host_impl },
        );
        if (s.duo_impl) |d| {
            try w.print("\"{s}\"", .{d});
        } else {
            try w.writeAll("null");
        }
        try w.print(
            ",\"production_status\":\"{s}\",\"bootstrap_required\":{},\"migration_blocker\":",
            .{ s.production_status.name(), s.bootstrap_required },
        );
        if (s.migration_blocker) |b| {
            try w.print("\"{s}\"", .{b});
        } else {
            try w.writeAll("null");
        }
        try w.print(",\"removal_gate\":", .{});
        if (s.removal_gate) |g| {
            try w.print("\"{s}\"", .{g});
        } else {
            try w.writeAll("null");
        }
        // `writeAll` is raw — unlike `print`, it does not collapse `}}` to `}`.
        // One object was opened per subsystem, so exactly one brace closes it.
        try w.writeAll("}");
    }
    try w.writeAll("],\"manifest\":");
    const m = publicManifest();
    try w.print(
        "{{\"self_hosting_level\":{d},\"canonical_compiler_in_duo\":{},\"bootstrap_stage_reached\":\"{s}\",\"production_duo_frontend\":{},\"silent_c_fallback\":{},\"claim_self_hosted_status\":\"{s}\"}}",
        .{ m.self_hosting_level, m.canonical_compiler_in_duo, m.bootstrap_stage_reached, m.production_duo_frontend, m.silent_c_fallback, m.claim_self_hosted_status },
    );
    try w.writeAll("}");
}

// Structural, not substring: an extra closing brace per subsystem element made
// this writer emit invalid JSON without any existing assertion noticing.
test "selfhosting_matrix: writeMatrixJson emits parseable JSON" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeMatrixJson(&aw.writer);

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, aw.written(), .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);

    const subs = parsed.value.object.get("subsystems") orelse return error.TestExpectedEqual;
    try std.testing.expect(subs == .array);
    try std.testing.expectEqual(subsystems.len, subs.array.items.len);
    try std.testing.expect(parsed.value.object.get("manifest").? == .object);
}

test "selfhosting_matrix: honest manifest level 1 keyword component" {
    const m = publicManifest();
    try std.testing.expectEqual(@as(u8, 1), m.self_hosting_level);
    try std.testing.expect(!m.canonical_compiler_in_duo);
    try std.testing.expect(m.production_duo_frontend);
    try std.testing.expect(std.mem.eql(u8, m.claim_self_hosted_status, "partial"));
    try std.testing.expect(std.mem.eql(u8, m.bootstrap_stage_reached, "S0"));
    try std.testing.expect(subsystems.len >= 10);
}
