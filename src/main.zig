const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const Lexer = @import("lexer.zig").Lexer;
const lexer_bridge = @import("lexer_bridge.zig");
const lexer_dispatch = @import("lexer_dispatch.zig");
const Parser = @import("parser.zig").Parser;
const ast = @import("ast.zig");
const Sema = @import("sema.zig").Sema;
const CodeGen = @import("codegen.zig").CodeGen;
const Mono = @import("mono.zig");
const MacroExpand = @import("macro_expand.zig");
const Arc = @import("arc.zig");
const AsyncLower = @import("async_lower.zig");
const escape = @import("escape.zig");
const pretty = @import("pretty.zig");
const PrettyPrinter = @import("pretty.zig").PrettyPrinter;
const term = @import("term.zig");
const debug_trace = @import("debug_trace.zig");
const build_framework = @import("build_framework.zig");
const ml_kernels = @import("ml_kernels.zig");
const native_backend = @import("native_backend.zig");

/// §7 makes "how much of a compile goes through C" a NUMBER this
/// repository owes, so the code that routes each `req`'d module says which way
/// it sent it. One line per module on stderr under `DUO_WAIST_REPORT=1`, which
/// is what a corpus sweep can count; silent otherwise, because this is a
/// measurement and not a diagnostic.
///
/// The dispositions are exclusive and cover every `req` binding a direct-backend
/// compile sees:
///   `splice`  — absorbed into the program's own native object. NOT the waist.
///   `nocall`  — bound but never called through; no object, nothing emitted.
///   `exports`/`collide`/`unbound`/`parse` — declined by the splice, so the
///               module falls to `emitReqModuleC` + a C object if it is called.
///   `cobject` — `directLinkInputs` built a C object for it. THE WAIST.
const waist = struct {
    var on: ?bool = null;

    fn enabled() bool {
        if (on) |v| return v;
        const v = std.c.getenv("DUO_WAIST_REPORT") != null;
        on = v;
        return v;
    }

    fn note(how: []const u8, module: []const u8) void {
        if (!enabled()) return;
        var buf: [512]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "waist\t{s}\t{s}\n", .{ how, module }) catch return;
        _ = std.c.write(2, line.ptr, line.len);
    }
};
const backend_identity = @import("backend_identity.zig");
const benchmark_evidence = @import("benchmark_evidence.zig");
const representation_manifest = @import("representation_manifest.zig");
const target_model = @import("target_model.zig");
const semantic_graph = @import("semantic_graph.zig");
const table_apply = @import("table_apply.zig");
const native_bootstrap = @import("native_bootstrap.zig");
const sim = @import("sim.zig");
const sim_pipeline = @import("sim_pipeline.zig");
const knowledge_snapshot = @import("knowledge_snapshot.zig");
const assumption_guard = @import("assumption_guard.zig");
const repair_candidate = @import("repair_candidate.zig");
const realization = @import("realization.zig");
const persistent_semantic_state = @import("persistent_semantic_state.zig");
const compile_semantic_cache = @import("compile_semantic_cache.zig");
const semantic_invalidation = @import("semantic_invalidation.zig");
const evidence_record = @import("evidence_record.zig");
const proof_carrying = @import("proof_carrying.zig");
const optimization_outcome = @import("optimization_outcome.zig");
const explain_pipeline = @import("explain_pipeline.zig");
const c_sim_import = @import("c_sim_import.zig");
const abi_specialize = @import("abi_specialize.zig");
const semantic_algebra = @import("semantic_algebra.zig");
const transform_engine = @import("transform_engine.zig");
const shell_session = @import("shell_session.zig");
const shell_host = @import("shell_host.zig");
const git_preservation = @import("git_preservation.zig");
const native_barrier_checks = @import("native_barrier_checks.zig");
const host_run = @import("host_run.zig");
const wasm_semantic_gen = @import("wasm_semantic_gen.zig");
const token_classify_gen = @import("token_classify_gen.zig");
const grammar_role_gen = @import("grammar_role_gen.zig");
const semantic_cli = @import("semantic_cli.zig");
const semantic_transaction = @import("semantic_transaction.zig");

var macos_sdkroot_configured = false;
var compiler_lib_root: ?[]const u8 = null;
var forwarded_program_args: []const []const u8 = &.{};
/// argv[0], recorded so the build cache key can include the compiler's own
/// bytes — a rebuilt compiler must invalidate every cached artifact.
var self_argv0: []const u8 = "";
var graph_diag_enabled: bool = false;
var graph_write_enabled: bool = false;
var global_bench_backend: backend_identity.BenchBackend = .c_specialized;
var global_bench_profile_cli: bool = false;
var global_backend_explicit: bool = false;

fn env_value_truthy(value: []const u8) bool {
    if (value.len == 0) return false;
    if (std.ascii.eqlIgnoreCase(value, "0")) return false;
    if (std.ascii.eqlIgnoreCase(value, "false")) return false;
    if (std.ascii.eqlIgnoreCase(value, "no")) return false;
    if (std.ascii.eqlIgnoreCase(value, "off")) return false;
    return true;
}

fn apply_env_flags(init: std.process.Init) void {
    const map = init.environ_map;
    {
        const cg = @import("codegen.zig");
        if (map.get("DUO_NATIVE_DIAG")) |v| {
            if (env_value_truthy(v)) cg.native_diag = true;
        }
        // gap[082]: every derived conversion's A5 witness, on demand. The same
        // witness ships inside the generated artifact unconditionally.
        if (map.get("DUO_WHY_CONVERT")) |v| {
            if (env_value_truthy(v)) cg.why_convert = true;
        }
        if (map.get("DUO_SER")) |v| {
            if (env_value_truthy(v)) cg.ser_census = true;
        }
    }
    {
        const te = @import("transform_engine.zig");
        if (map.get("DUO_PROVENANCE")) |v| {
            if (env_value_truthy(v)) te.setProvenanceEnabled(true);
        }
        if (map.get("DUO_TRANSFORM_GATE")) |v| {
            if (env_value_truthy(v)) te.setMetaDispatchStrict(true);
        }
    }
    if (map.get("DUO_GRAPH")) |v| {
        if (env_value_truthy(v)) graph_diag_enabled = true;
    }
    if (map.get("DUO_GRAPH_WRITE")) |v| {
        if (env_value_truthy(v)) graph_write_enabled = true;
    }
    if (map.get("DUO_BENCH_BACKEND")) |v| {
        if (backend_identity.BenchBackend.parse(v)) |bb| global_bench_backend = bb;
    }
    if (map.get("DUO_TRACE")) |v| {
        if (env_value_truthy(v)) term.trace = true;
    }
    if (map.get("DUO_TRACE_RICH")) |v| {
        if (env_value_truthy(v)) {
            term.trace = true;
            if (term.verbose_level == 0) term.verbose_level = 1;
            if (term.build_report == .pretty) term.setBuildReport(.verbose);
        }
    }
    if (map.get("DUO_INFO")) |v| {
        if (env_value_truthy(v)) term.info = true;
    }
    if (map.get("DUO_HINTS")) |v| {
        if (env_value_truthy(v)) term.hints = true;
    }
    if (map.get("DUO_PLAIN_DIAG")) |v| {
        if (env_value_truthy(v)) term.plain = true;
    }
    if (map.get("DUO_DEBUG")) |v| {
        if (env_value_truthy(v)) {
            term.debug_enabled = true;
            debug_trace.enableAll();
        } else if (v.len > 0) {
            term.debug_enabled = true;
            debug_trace.applyCliList(v);
        }
    }
    if (map.get("DUO_DEBUG_DEPTH")) |v| {
        const d = std.fmt.parseInt(u32, v, 10) catch 0;
        debug_trace.applyDepth(d);
    }
    if (map.get("DUO_TEST_REPORT")) |v| {
        if (term.parseReportStyle(v)) |s| term.setTestReport(s);
    }
    if (map.get("DUO_BUILD_REPORT")) |v| {
        if (term.parseReportStyle(v)) |s| term.setBuildReport(s);
    }
    if (map.get("NO_COLOR")) |v| {
        if (v.len > 0) term.color = false;
    }
    if (map.get("DUO_COLOR")) |v| {
        if (env_value_truthy(v)) term.color = true;
    }
}

fn apply_cli_flags(trace_flag: bool, info_flag: bool, hints_flag: bool, plain_diag: bool, debug_flag: bool, debug_list: ?[]const u8, debug_depth: ?u32, test_report: ?[]const u8, build_report: ?[]const u8, no_color: bool, verbose_count: u8) void {
    if (trace_flag) term.trace = true;
    if (info_flag) term.info = true;
    if (hints_flag) term.hints = true;
    if (plain_diag) term.plain = true;
    if (no_color) term.color = false;
    term.verbose_level = verbose_count;
    if (debug_flag) {
        term.debug_enabled = true;
        debug_trace.enableAll();
    }
    if (debug_list) |list| {
        term.debug_enabled = true;
        debug_trace.applyCliList(list);
    }
    if (debug_depth) |d| debug_trace.applyDepth(d);
    if (test_report) |s| {
        if (term.parseReportStyle(s)) |style| term.setTestReport(style);
    }
    if (build_report) |s| {
        if (term.parseReportStyle(s)) |style| term.setBuildReport(style);
    }
}

fn start_trace_timer(io: Io) ?Io.Timestamp {
    if (!term.trace) return null;
    return Io.Timestamp.now(io, .awake);
}

fn trace_phase(io: Io, start_ns: *const Io.Timestamp, label: []const u8, detail: ?[]const u8) void {
    const now = Io.Timestamp.now(io, .awake);
    const elapsed_ms: u64 = @intCast(@divTrunc(start_ns.*.durationTo(now).nanoseconds, std.time.ns_per_ms));
    term.traceDone(label, elapsed_ms, detail);
}

fn shouldEmitCompileProof(bench_mode: bool) bool {
    if (bench_mode) return true;
    if (std.c.getenv("DUO_EMIT_PROOF")) |p| {
        return p[0] != 0 and p[0] != '0';
    }
    return false;
}

fn shouldEmitRepresentationManifest(bench_mode: bool) bool {
    if (shouldEmitCompileProof(bench_mode)) return true;
    if (std.c.getenv("DUO_EMIT_MANIFEST")) |p| {
        return p[0] != 0 and p[0] != '0';
    }
    return false;
}

fn emitRepresentationManifestFile(
    alloc: std.mem.Allocator,
    io: Io,
    artifact_path: []const u8,
    manifest: backend_identity.Manifest,
    l6_counts: representation_manifest.EmissionCounts,
    bench_mode: bool,
) !void {
    if (!shouldEmitRepresentationManifest(bench_mode)) return;
    const manifest_path = try std.fmt.allocPrint(alloc, "{s}.manifest.json", .{artifact_path});
    defer alloc.free(manifest_path);
    const contamination = representation_manifest.classifyContamination(l6_counts, 0);
    try representation_manifest.writeManifestFile(io, manifest_path, manifest, l6_counts, contamination, null, alloc);
}

fn emitDirectCompileProofArtifact(
    alloc: std.mem.Allocator,
    io: Io,
    src_path: []const u8,
    object_path: []const u8,
    target: []const u8,
) !void {
    if (!shouldEmitCompileProof(false)) return;

    const object_bytes = try Io.Dir.readFileAlloc(Io.Dir.cwd(), io, object_path, alloc, .unlimited);
    defer alloc.free(object_bytes);
    const counters = benchmark_evidence.EvidenceCounters.fromDirectObject(object_bytes);
    const manifest = backend_identity.Manifest{
        .backend = .direct,
        .representation = .native,
        .runtime = .freestanding,
        .target = target,
        .intermediate = "mach-o-arm64",
        .external_compiler = null,
        .boxing_mode = "none",
    };
    const proof_path = try std.fmt.allocPrint(alloc, "{s}.proof.json", .{object_path});
    defer alloc.free(proof_path);

    var prov = std.ArrayListUnmanaged(benchmark_evidence.ManifestProvenance).empty;
    defer prov.deinit(alloc);
    for (transform_engine.provenanceEntries()) |e| {
        try prov.append(alloc, .{
            .transform = e.public_name,
            .site = transform_engine.siteKindName(e.site),
            .inputs_hash = e.inputs_hash,
            .output_hash = e.output_hash,
        });
    }

    try benchmark_evidence.writeCompileProofFile(io, proof_path, .{
        .source_path = src_path,
        .generated_path = object_path,
        .bench_backend = global_bench_backend,
        .manifest = manifest,
        .counters = counters,
    }, prov.items, alloc);

    const l6_counts = representation_manifest.EmissionCounts{
        .boxes = counters.boxes,
        .allocations = counters.allocations,
        .dynamic_dispatches = counters.generic_calls + counters.generic_table_ops,
        .runtime_helpers = counters.runtime_helpers,
    };
    try emitRepresentationManifestFile(alloc, io, object_path, manifest, l6_counts, false);
}

fn emitCompileProofArtifact(
    alloc: std.mem.Allocator,
    io: Io,
    src_path: []const u8,
    generated_c_path: []const u8,
    target: []const u8,
    bench_mode: bool,
    full_native_lowering: bool,
    idol_mode: bool,
) !void {
    if (!shouldEmitCompileProof(bench_mode)) return;

    const source = try Io.Dir.readFileAlloc(Io.Dir.cwd(), io, generated_c_path, alloc, .unlimited);
    defer alloc.free(source);
    const counters = benchmark_evidence.EvidenceCounters.fromGeneratedC(source, source.len);
    const manifest = if (global_bench_profile_cli) blk: {
        const prof = backend_identity.profileForBenchBackend(global_bench_backend);
        break :blk backend_identity.Manifest{
            .backend = prof.backend,
            .representation = prof.representation,
            .runtime = prof.runtime,
            .target = target,
            .intermediate = "generated-c",
            .external_compiler = null,
            .boxing_mode = if (global_bench_backend == .c_dynamic) "boxed" else if (global_bench_backend == .direct) "none" else "specialized",
        };
    } else backend_identity.inferFromCompile(.c, target, full_native_lowering, idol_mode);
    const proof_path = try std.fmt.allocPrint(alloc, "{s}.proof.json", .{generated_c_path});
    defer alloc.free(proof_path);

    var prov = std.ArrayListUnmanaged(benchmark_evidence.ManifestProvenance).empty;
    defer prov.deinit(alloc);
    for (transform_engine.provenanceEntries()) |e| {
        try prov.append(alloc, .{
            .transform = e.public_name,
            .site = transform_engine.siteKindName(e.site),
            .inputs_hash = e.inputs_hash,
            .output_hash = e.output_hash,
        });
    }

    try benchmark_evidence.writeCompileProofFile(io, proof_path, .{
        .source_path = src_path,
        .generated_path = generated_c_path,
        .bench_backend = global_bench_backend,
        .manifest = manifest,
        .counters = counters,
    }, prov.items, alloc);

    const l6_from_c = representation_manifest.EmissionCounts.fromGeneratedC(source);
    try emitRepresentationManifestFile(alloc, io, generated_c_path, manifest, l6_from_c, bench_mode);
}

const usage =
    \\usage: duo [command] [options] [file]
    \\
    \\commands:
    \\  shell              persistent semantic shell (Pass 15; default when no args)
    \\  init       [name]   create a new Idol project
    \\  build      [target] build the default or named target from @build metadata
    \\             list     show all @build.* targets (or: duo build --list)
    \\             all      build every compile target in stage order
    \\             stage S  build targets in stage S (or: duo build all --stage S)
    \\  compile    [file]   compile Idol .id (foreign .lua remains accepted)
    \\  run        [file]   compile and run immediately, or run @build target
    \\  check      <file>   type-check only, no output
    \\  fmt        <file>   format an Idol .id or foreign .lua file
    \\  test       [file]   run inline @test functions (or @build.test target)
    \\  bench      [file]   run @bench-marked functions (or @build.bench target)
    \\  prove               reproduce the seven release proofs and write a proof bundle
    \\  symbols    <file>   glanceable module/test/build symbol map
    \\  graph      <file>   export semantic graph JSON (table_shapes, enum_shapes)
    \\  sim        <file>   export SIM v0 semantic snapshot JSON (Pass 5)
    \\             --import-c <header>  import C declarations into SIM (Pass 5 Layer B)
    \\  explain    <file>   export knowledge snapshots + optimization outcomes (Pass 7)
    \\  realize    <file>   export realization plan + persistent evidence (Pass 8)
    \\  algebra             export Pass 2 convergence catalog JSON
    \\  catalog             export Pass 3 keyword/directive/grammar catalog JSON
    \\  catalog audit       full Pass 1–14 audit JSON (open_items + findings)
    \\  catalog audit check native gate (fast, cross-platform, exit 0/1)
    \\  catalog audit gate [all|pass11|...|pass34|pass36|pass27|foundation|lua-superset|semantic-unification|foundational-closure|proof-bundle|self-hosting-foundation|hpls-frontier|semantic-access] [--barrier] per-pass native gate
    \\  catalog audit summary audit without open_items (medium)
    \\  dev        <sub>    Pass 13 development control plane (snapshot|audit|context|summary|claim|persist|session|validate|integration|coordination)
    \\  semantic   <sub>    Pass 12 semantic projections (intent|compare|proof|preview|validate|transforms|…)
    \\  wasm-tables emit    regenerate lib/wasm/opcode_lookup.id + ward_mvp_opcodes.id
    \\  completion <shell>  generate shell completions (bash, zsh, fish, nu)
    \\
    \\options:
    \\  -o <name>         output binary name (default: <stem>.out or <stem>.wasm)
    \\  -O<n>             optimisation level (default: -O3)
    \\  --cc <path>       C compiler (default: clang)
    \\  --target <triple> target triple (e.g. wasm32-wasi, aarch64-macos, native-exe)
    \\  --emit <kind>     output kind with structured triples: obj, exe, dylib, asm, wasm (default exe)
    \\  --backend <auto|c|direct|native>  lowering: auto (default, machine-first), direct/native (ARM64 Mach-O), c (bootstrap C emit only)
    \\  --bench-backend <c-dynamic|c-specialized|direct>  benchmark representation profile (default c-specialized)
    \\  --load-chunk      compile as shared library for runtime load() (not for run)
    \\  --pgo             use profile-guided optimisation (two-pass clang compile)
    \\  --shared-memory   enable WASM shared memory (-matomics -mbulk-memory; wasm32-wasi only)
    \\  --link <lib>      link against a C library (e.g. --link raylib; repeatable)
    \\  --entry <name>    native-exe linker entry symbol (default: @export, sole zero-arg fn, or main)
    \\  -v, --verbose     show C compiler warnings (run only; off by default)
    \\  --trace           show compiler pipeline steps and timings
    \\  --trace-rich      pipeline tree with timing bars (implies --trace; use with -v)
    \\  --info            show informational compiler notes (opt-in)
    \\  --hints           show compiler hints and suggestions (opt-in)
    \\  --debug           enable all compiler debug channels
    \\  --debug=<list>    debug channels: parse,sema,types,codegen,mono,arc,build,test
    \\  --debug-depth N   max debug nesting depth (default 12)
    \\  --test-report S   test output style: pretty|compact|verbose|plain|json (default pretty)
    \\  --build-report S  build output style: pretty|compact|verbose|plain (default pretty)
    \\  --stage <name>    with `build all`, build only one named/numeric stage
    \\  --no-color        disable ANSI styling
    \\  --canonical       fmt: emit the strongest admitted canonical source face
    \\  --filter <pat>    run only tests whose name contains <pat>
    \\
;

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    term.init(init.io);
    apply_env_flags(init);
    if (init.environ_map.get("SDKROOT")) |sdkroot| {
        macos_sdkroot_configured = sdkroot.len > 0;
    }
    const io = init.io;
    const args = try init.minimal.args.toSlice(alloc);
    if (args.len > 0) {
        compiler_lib_root = try detectCompilerLibRoot(alloc, io, init.environ_map, args[0]);
    }

    if (args.len < 2) {
        try do_shell(alloc, io, false, "auto");
        return;
    }
    const known_cmd = args.len >= 2 and
        (std.mem.eql(u8, args[1], "shell") or
            std.mem.eql(u8, args[1], "init") or
            std.mem.eql(u8, args[1], "build") or
            std.mem.eql(u8, args[1], "compile") or
            std.mem.eql(u8, args[1], "run") or
            std.mem.eql(u8, args[1], "check") or
            std.mem.eql(u8, args[1], "fmt") or
            std.mem.eql(u8, args[1], "dump-c") or
            std.mem.eql(u8, args[1], "test") or
            std.mem.eql(u8, args[1], "bench") or
            std.mem.eql(u8, args[1], "prove") or
            std.mem.eql(u8, args[1], "symbols") or
            std.mem.eql(u8, args[1], "graph") or
            std.mem.eql(u8, args[1], "sim") or
            std.mem.eql(u8, args[1], "realize") or
            std.mem.eql(u8, args[1], "explain") or
            std.mem.eql(u8, args[1], "algebra") or
            std.mem.eql(u8, args[1], "catalog") or
            std.mem.eql(u8, args[1], "dev") or
            std.mem.eql(u8, args[1], "semantic") or
            std.mem.eql(u8, args[1], "wasm-tables") or
            std.mem.eql(u8, args[1], "token-tables") or
            std.mem.eql(u8, args[1], "completion") or
            std.mem.eql(u8, args[1], "help") or
            std.mem.eql(u8, args[1], "--help") or
            std.mem.eql(u8, args[1], "-h"));
    const cmd: []const u8 = if (known_cmd) args[1] else "run";
    const start: usize = if (known_cmd) 2 else 1;
    var input_file: ?[]const u8 = null;
    var output_file: ?[]const u8 = null;
    var cc: []const u8 = "clang";
    var opt_level: []const u8 = "-O3";
    var target: []const u8 = "native";
    var emit_kind: target_model.EmitKind = .exe;
    var compile_backend: []const u8 = "auto";
    var verbose = false;
    var trace_flag = false;
    var info_flag = false;
    var hints_flag = false;
    var plain_diag = false;
    var debug_flag = false;
    var debug_list: ?[]const u8 = null;
    var debug_depth: ?u32 = null;
    var test_report_style: ?[]const u8 = null;
    var build_report_style: ?[]const u8 = null;
    var no_color = false;
    var verbose_count: u8 = 0;
    var load_chunk = false;
    var lib_mode = false;
    var pgo = false;
    var shared_mem = false;
    var test_filter: ?[]const u8 = null;
    var list_targets = false;
    var trace_rich = false;
    var stage_filter: ?[]const u8 = null;
    var extra_arg: ?[]const u8 = null;
    var forwarded_args: std.ArrayList([]const u8) = .empty;
    var link_flags: std.ArrayList([]const u8) = .empty;
    var entry_override: ?[]const u8 = null;
    var fmt_canonical = false;
    var i: usize = start;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            while (i < args.len) : (i += 1) {
                try forwarded_args.append(alloc, args[i]);
            }
            break;
        } else if (std.mem.eql(u8, arg, "-o") and i + 1 < args.len) {
            i += 1;
            output_file = args[i];
        } else if (std.mem.startsWith(u8, arg, "-O")) {
            opt_level = arg;
        } else if (std.mem.eql(u8, arg, "--cc") and i + 1 < args.len) {
            i += 1;
            cc = args[i];
        } else if (std.mem.eql(u8, arg, "--target") and i + 1 < args.len) {
            i += 1;
            target = args[i];
        } else if (std.mem.eql(u8, arg, "--emit") and i + 1 < args.len) {
            i += 1;
            emit_kind = target_model.EmitKind.parse(args[i]) orelse {
                term.err("unknown --emit '{s}' (expected obj, exe, dylib, asm, wasm)", .{args[i]});
                std.process.exit(1);
            };
        } else if (std.mem.startsWith(u8, arg, "--emit=")) {
            const val = arg["--emit=".len..];
            emit_kind = target_model.EmitKind.parse(val) orelse {
                term.err("unknown --emit '{s}'", .{val});
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--backend") and i + 1 < args.len) {
            i += 1;
            compile_backend = args[i];
            global_backend_explicit = true;
        } else if (std.mem.startsWith(u8, arg, "--backend=")) {
            compile_backend = arg["--backend=".len..];
            global_backend_explicit = true;
        } else if (std.mem.eql(u8, arg, "--bench-backend") and i + 1 < args.len) {
            i += 1;
            if (backend_identity.BenchBackend.parse(args[i])) |bb| {
                global_bench_backend = bb;
                global_bench_profile_cli = true;
                if (!global_backend_explicit) {
                    compile_backend = if (bb == .direct) "direct" else "c";
                }
            } else {
                term.err("unknown --bench-backend '{s}' (expected c-dynamic, c-specialized, or direct)", .{args[i]});
                std.process.exit(1);
            }
        } else if (std.mem.startsWith(u8, arg, "--bench-backend=")) {
            const val = arg["--bench-backend=".len..];
            if (backend_identity.BenchBackend.parse(val)) |bb| {
                global_bench_backend = bb;
                global_bench_profile_cli = true;
                if (!global_backend_explicit) {
                    compile_backend = if (bb == .direct) "direct" else "c";
                }
            } else {
                term.err("unknown --bench-backend '{s}'", .{val});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--load-chunk")) {
            load_chunk = true;
        } else if (std.mem.eql(u8, arg, "--lib")) {
            // Library mode: compile @export functions as WASM exports,
            // skip main() / _start, for use with wasmtime WAST testing.
            lib_mode = true;
        } else if (std.mem.eql(u8, arg, "--pgo")) {
            pgo = true;
        } else if (std.mem.eql(u8, arg, "--shared-memory")) {
            shared_mem = true;
        } else if (std.mem.eql(u8, arg, "--link") and i + 1 < args.len) {
            i += 1;
            try link_flags.append(alloc, args[i]);
        } else if (std.mem.eql(u8, arg, "--entry") and i + 1 < args.len) {
            i += 1;
            entry_override = args[i];
        } else if (std.mem.startsWith(u8, arg, "--entry=")) {
            entry_override = arg["--entry=".len..];
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
            verbose_count +%= 1;
        } else if (std.mem.eql(u8, arg, "--trace")) {
            trace_flag = true;
        } else if (std.mem.eql(u8, arg, "--trace-rich")) {
            trace_flag = true;
            trace_rich = true;
            verbose_count +%= 1;
        } else if (std.mem.eql(u8, arg, "--list")) {
            list_targets = true;
        } else if (std.mem.eql(u8, arg, "--info")) {
            info_flag = true;
        } else if (std.mem.eql(u8, arg, "--hints")) {
            hints_flag = true;
        } else if (std.mem.eql(u8, arg, "--plain-diagnostics")) {
            plain_diag = true;
        } else if (std.mem.eql(u8, arg, "--debug")) {
            debug_flag = true;
        } else if (std.mem.startsWith(u8, arg, "--debug=")) {
            debug_list = arg["--debug=".len..];
        } else if (std.mem.eql(u8, arg, "--debug-depth") and i + 1 < args.len) {
            i += 1;
            debug_depth = std.fmt.parseInt(u32, args[i], 10) catch null;
        } else if (std.mem.startsWith(u8, arg, "--test-report=")) {
            test_report_style = arg["--test-report=".len..];
        } else if (std.mem.eql(u8, arg, "--test-report") and i + 1 < args.len) {
            i += 1;
            test_report_style = args[i];
        } else if (std.mem.startsWith(u8, arg, "--build-report=")) {
            build_report_style = arg["--build-report=".len..];
        } else if (std.mem.eql(u8, arg, "--build-report") and i + 1 < args.len) {
            i += 1;
            build_report_style = args[i];
        } else if (std.mem.eql(u8, arg, "--no-color")) {
            no_color = true;
        } else if (std.mem.eql(u8, arg, "--filter") and i + 1 < args.len) {
            i += 1;
            test_filter = args[i];
        } else if (std.mem.eql(u8, arg, "--stage") and i + 1 < args.len) {
            i += 1;
            stage_filter = args[i];
        } else if (std.mem.eql(u8, arg, "--canonical")) {
            fmt_canonical = true;
        } else if (arg.len > 0 and arg[0] != '-') {
            if (input_file == null) {
                input_file = arg;
            } else {
                extra_arg = arg;
            }
        }
    }
    forwarded_program_args = forwarded_args.items;
    if (args.len > 0) self_argv0 = args[0];

    if (global_bench_profile_cli and global_backend_explicit) {
        const selected = backend_identity.Backend.parse(compile_backend) orelse {
            term.err("unknown --backend '{s}' (expected auto, c, direct, or native)", .{compile_backend});
            std.process.exit(1);
        };
        const expected: backend_identity.Backend = if (global_bench_backend == .direct) .direct else .c;
        if (selected != expected) {
            term.err("--backend={s} conflicts with --bench-backend={s}", .{ selected.name(), global_bench_backend.name() });
            std.process.exit(1);
        }
    }

    apply_cli_flags(trace_flag, info_flag, hints_flag, plain_diag, debug_flag, debug_list, debug_depth, test_report_style, build_report_style, no_color, verbose_count);
    if (trace_rich and term.build_report == .pretty) term.setBuildReport(.verbose);
    target = resolveCompileTarget(target, emit_kind);
    const backend_mode = compile_backend;
    target = resolveCompileBackend(backend_mode, target);

    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        term.printRaw("{s}", .{usage});
        return;
    }

    if (std.mem.eql(u8, cmd, "shell")) {
        try do_shell(alloc, io, verbose, backend_mode);
        return;
    }

    if (std.mem.eql(u8, cmd, "init")) {
        const name = input_file orelse "duo-app";
        try do_init(alloc, io, name);
        return;
    }

    if (std.mem.eql(u8, cmd, "completion")) {
        try do_completion(io, args[start..]);
        return;
    }

    if (usesProjectWorkspace(cmd, input_file)) {
        try enterWorkspaceRoot(alloc, io);
    }

    if (std.mem.eql(u8, cmd, "prove")) {
        if (input_file != null) {
            term.err("duo prove takes no arguments", .{});
            std.process.exit(2);
        }
        if (!try do_prove(alloc, io)) std.process.exit(1);
        return;
    }

    if (std.mem.eql(u8, cmd, "build")) {
        if (list_targets or (input_file != null and std.mem.eql(u8, input_file.?, "list"))) {
            try do_build_list(alloc, io);
            return;
        }
        if (input_file != null and std.mem.eql(u8, input_file.?, "stage")) {
            const stage_name = extra_arg orelse stage_filter orelse {
                term.err("duo build stage requires a stage name", .{});
                std.process.exit(1);
            };
            try do_build_stage(alloc, io, stage_name, output_file, cc, opt_level, target, backend_mode, verbose, load_chunk, pgo, lib_mode, shared_mem, link_flags.items);
            return;
        }
        if (input_file != null and std.mem.eql(u8, input_file.?, "all")) {
            try do_build_all(alloc, io, stage_filter, output_file, cc, opt_level, target, backend_mode, verbose, load_chunk, pgo, lib_mode, shared_mem, link_flags.items);
            return;
        }
        try do_project_build(alloc, io, input_file, output_file, cc, opt_level, target, backend_mode, verbose, load_chunk, pgo, lib_mode, shared_mem, link_flags.items, false);
        return;
    }

    if (std.mem.eql(u8, cmd, "run") and input_file == null) {
        try do_project_build(alloc, io, null, output_file, cc, opt_level, target, backend_mode, verbose, load_chunk, pgo, lib_mode, shared_mem, link_flags.items, true);
        return;
    }

    if (std.mem.eql(u8, cmd, "run")) {
        if (input_file) |maybe_target| {
            if (lexer_bridge.sourceFacts(maybe_target).law == .unknown) {
                try do_project_build(alloc, io, maybe_target, output_file, cc, opt_level, target, backend_mode, verbose, load_chunk, pgo, lib_mode, shared_mem, link_flags.items, true);
                return;
            }
        }
    }

    if (std.mem.eql(u8, cmd, "symbols")) {
        const file = input_file orelse {
            term.err("no input file (duo symbols <file.id>)", .{});
            std.process.exit(1);
        };
        try do_symbols(alloc, io, file);
        return;
    }

    if (std.mem.eql(u8, cmd, "graph")) {
        var graph_file: ?[]const u8 = null;
        var graph_write = false;
        var ai: usize = 2;
        while (ai < args.len) : (ai += 1) {
            if (std.mem.eql(u8, args[ai], "--write")) {
                graph_write = true;
            } else if (args[ai][0] != '-') {
                graph_file = args[ai];
            } else {
                term.err("unknown graph option: {s}", .{args[ai]});
                std.process.exit(1);
            }
        }
        const file = graph_file orelse {
            term.err("no input file (duo graph <file.id> [--write])", .{});
            std.process.exit(1);
        };
        try do_graph(alloc, io, file, graph_write);
        return;
    }

    if (std.mem.eql(u8, cmd, "sim")) {
        var import_c: ?[]const u8 = null;
        var duo_file: ?[]const u8 = null;
        var ai: usize = 2;
        while (ai < args.len) : (ai += 1) {
            if (std.mem.eql(u8, args[ai], "--import-c")) {
                ai += 1;
                if (ai >= args.len) {
                    term.err("--import-c requires a header path", .{});
                    std.process.exit(1);
                }
                import_c = args[ai];
            } else if (args[ai][0] != '-') {
                duo_file = args[ai];
            } else {
                term.err("unknown sim option: {s}", .{args[ai]});
                std.process.exit(1);
            }
        }
        if (import_c) |header| {
            try do_sim_c_import(alloc, io, header);
            return;
        }
        const file = duo_file orelse {
            term.err("no input file (duo sim <file.id> or duo sim --import-c <header>)", .{});
            std.process.exit(1);
        };
        try do_sim(alloc, io, file);
        return;
    }

    if (std.mem.eql(u8, cmd, "realize")) {
        if (input_file == null) {
            term.err("no input file (duo realize <file.id>)", .{});
            std.process.exit(1);
        }
        try do_realize(alloc, io, input_file.?);
        return;
    }

    if (std.mem.eql(u8, cmd, "explain")) {
        const file = input_file orelse {
            term.err("no input file (duo explain <file.id>)", .{});
            std.process.exit(1);
        };
        try do_explain(alloc, io, file);
        return;
    }

    if (std.mem.eql(u8, cmd, "semantic")) {
        const sub = input_file orelse {
            term.err("usage: duo semantic <intent|compare|proof|obligations|projections|context> [entity]", .{});
            std.process.exit(1);
        };
        try do_semantic(alloc, io, sub, extra_arg);
        return;
    }

    if (std.mem.eql(u8, cmd, "wasm-tables")) {
        const sub = input_file orelse {
            term.err("usage: duo wasm-tables emit", .{});
            std.process.exit(1);
        };
        if (!std.mem.eql(u8, sub, "emit")) {
            term.err("unknown wasm-tables subcommand '{s}' (expected: emit)", .{sub});
            std.process.exit(1);
        }
        try wasm_semantic_gen.emitDuoOpcodeLookupFile(alloc, io, "lib/wasm/opcode_lookup.id");
        try wasm_semantic_gen.emitWardMvpOpcodesFile(alloc, io, "lib/wasm/ward_mvp_opcodes.id");
        term.print("wrote lib/wasm/opcode_lookup.id\n", .{});
        term.print("wrote lib/wasm/ward_mvp_opcodes.id\n", .{});
        return;
    }

    if (std.mem.eql(u8, cmd, "token-tables")) {
        const sub = input_file orelse {
            term.err("usage: duo token-tables emit", .{});
            std.process.exit(1);
        };
        if (!std.mem.eql(u8, sub, "emit")) {
            term.err("unknown token-tables subcommand '{s}' (expected: emit)", .{sub});
            std.process.exit(1);
        }
        try token_classify_gen.emitTokenClassifyFile(alloc, io, "lib/token/classify.id");
        try token_classify_gen.emitKeywordClassifyNativeCFile(alloc, io, "src/keyword_classify.c");
        try grammar_role_gen.emitGrammarRoleFile(alloc, io, "lib/token/grammarrole.id");
        term.print("wrote lib/token/classify.id\n", .{});
        term.print("wrote src/keyword_classify.c\n", .{});
        term.print("wrote lib/token/grammarrole.id\n", .{});
        return;
    }

    if (std.mem.eql(u8, cmd, "algebra")) {
        if (input_file != null) {
            term.err("duo algebra takes no file argument", .{});
            std.process.exit(1);
        }
        try do_algebra(io);
        return;
    }

    if (std.mem.eql(u8, cmd, "test") or std.mem.eql(u8, cmd, "bench")) {
        const bench_only = std.mem.eql(u8, cmd, "bench");
        if (input_file) |file| {
            try run_test_sources(alloc, io, &.{file}, output_file, cc, opt_level, target, backend_mode, verbose, bench_only, test_filter, link_flags.items);
            return;
        }
        if (try maybeReadBuildTarget(alloc, io, null, if (bench_only) .bench else .@"test")) |t| {
            const src = t.src orelse {
                term.err("build target '{s}' has no src= field", .{t.name});
                std.process.exit(1);
            };
            try run_test_sources(alloc, io, &.{src}, output_file, t.cc orelse cc, t.opt orelse opt_level, t.target orelse target, backend_mode, verbose, bench_only or t.bench_mode(), test_filter, t.link);
            return;
        }
        const sources = try scanInlineTestSources(alloc, io, bench_only);
        defer alloc.free(sources);
        if (sources.len == 0) {
            term.err("no inline {s} sources found", .{if (bench_only) "bench" else "test"});
            term.hint("add @test/@test.* to .id files or --- @test before Lua functions, or define @build.test", .{});
            std.process.exit(1);
        }
        try run_test_sources(alloc, io, sources, output_file, cc, opt_level, target, backend_mode, verbose, bench_only, test_filter, link_flags.items);
        return;
    }

    const file = input_file orelse if (std.mem.eql(u8, cmd, "compile") or
        std.mem.eql(u8, cmd, "check") or
        std.mem.eql(u8, cmd, "dump-c"))
        try resolveDefaultSource(alloc, io)
    else {
        term.err("no input file", .{});
        std.process.exit(1);
    };

    const out = output_file orelse out: {
        const stem = std.fs.path.stem(file);
        if (std.mem.eql(u8, target, "wasm32-wasi")) {
            break :out try std.fmt.allocPrint(alloc, "./{s}.wasm", .{stem});
        }
        break :out try std.fmt.allocPrint(alloc, "./{s}.out", .{stem});
    };

    if (std.mem.eql(u8, cmd, "compile")) {
        try do_compile(alloc, io, file, out, cc, opt_level, target, backend_mode, false, false, false, load_chunk, pgo, lib_mode, shared_mem, false, global_bench_profile_cli, null, link_flags.items, entry_override);
    } else if (std.mem.eql(u8, cmd, "run")) {
        try do_compile(alloc, io, file, out, cc, opt_level, target, backend_mode, true, false, verbose, false, false, false, false, false, false, null, link_flags.items, entry_override);
    } else if (std.mem.eql(u8, cmd, "check")) {
        try do_compile(alloc, io, file, out, cc, opt_level, target, backend_mode, false, true, false, false, false, false, false, false, false, null, &.{}, entry_override);
    } else if (std.mem.eql(u8, cmd, "fmt")) {
        try do_fmt(alloc, io, file, fmt_canonical);
    } else if (std.mem.eql(u8, cmd, "dump-c")) {
        try do_dump_c(alloc, io, file, target, lib_mode);
    } else {
        term.err("unknown command '{s}'", .{cmd});
        term.printRaw("{s}", .{usage});
        std.process.exit(1);
    }
}

fn read_source(alloc: std.mem.Allocator, io: Io, path: []const u8) ![]u8 {
    const cwd = Io.Dir.cwd();
    return Io.Dir.readFileAlloc(cwd, io, path, alloc, .unlimited);
}

fn is_source_path(path: []const u8) bool {
    return lexer_bridge.sourceFacts(path).law != .unknown;
}

fn usesProjectWorkspace(cmd: []const u8, input_file: ?[]const u8) bool {
    if (std.mem.eql(u8, cmd, "prove")) return true;
    if (std.mem.eql(u8, cmd, "build")) return true;
    if (std.mem.eql(u8, cmd, "test") or std.mem.eql(u8, cmd, "bench")) return input_file == null;
    if (std.mem.eql(u8, cmd, "compile") or std.mem.eql(u8, cmd, "check") or std.mem.eql(u8, cmd, "dump-c")) return input_file == null;
    if (std.mem.eql(u8, cmd, "run")) {
        if (input_file) |f| return !is_source_path(f);
        return true;
    }
    return false;
}

fn absPathExists(io: Io, path: []const u8) bool {
    if (!std.fs.path.isAbsolute(path)) return false;
    Io.Dir.accessAbsolute(io, path, .{}) catch return false;
    return true;
}

fn pathJoin2(alloc: std.mem.Allocator, a: []const u8, b: []const u8) ![]const u8 {
    return try std.fs.path.join(alloc, &.{ a, b });
}

fn detectCompilerLibRoot(alloc: std.mem.Allocator, io: Io, environ: *std.process.Environ.Map, argv0: []const u8) !?[]const u8 {
    var exe_path: ?[]const u8 = null;
    if (std.fs.path.isAbsolute(argv0)) {
        exe_path = Io.Dir.realPathFileAbsoluteAlloc(io, argv0, alloc) catch try alloc.dupe(u8, argv0);
    } else {
        exe_path = Io.Dir.cwd().realPathFileAlloc(io, argv0, alloc) catch null;
    }
    if (exe_path) |exe| {
        defer alloc.free(exe);
        if (std.fs.path.dirname(exe)) |bin_dir| {
            if (std.fs.path.dirname(bin_dir)) |zig_out| {
                if (std.fs.path.dirname(zig_out)) |repo| {
                    const lib = try pathJoin2(alloc, repo, "lib");
                    const std_root = try pathJoin2(alloc, lib, "std.id");
                    defer alloc.free(std_root);
                    if (absPathExists(io, std_root)) return lib;
                    alloc.free(lib);
                }
            }
        }
    }
    const local_std = try pathJoin2(alloc, "lib", "std.id");
    defer alloc.free(local_std);
    if (Io.Dir.cwd().access(io, local_std, .{})) |_| {
        return try alloc.dupe(u8, "lib");
    } else |_| {}
    if (!std.fs.path.isAbsolute(argv0)) {
        const path_env = environ.get("PATH");
        if (path_env) |path_val| {
            var it = std.mem.splitScalar(u8, path_val, ':');
            while (it.next()) |dir| {
                if (dir.len == 0) continue;
                const candidate = try pathJoin2(alloc, dir, argv0);
                defer alloc.free(candidate);
                if (absPathExists(io, candidate)) {
                    if (Io.Dir.realPathFileAbsoluteAlloc(io, candidate, alloc)) |real| {
                        defer alloc.free(real);
                        if (std.fs.path.dirname(real)) |bin_dir| {
                            if (std.fs.path.dirname(bin_dir)) |zig_out| {
                                if (std.fs.path.dirname(zig_out)) |repo| {
                                    const lib = try pathJoin2(alloc, repo, "lib");
                                    const std_root = try pathJoin2(alloc, lib, "std.id");
                                    defer alloc.free(std_root);
                                    if (absPathExists(io, std_root)) return lib;
                                    alloc.free(lib);
                                }
                            }
                        }
                    } else |_| {}
                }
            }
        }
    }
    return null;
}

fn dirHasWorkspaceMarker(alloc: std.mem.Allocator, io: Io, dir: []const u8) !bool {
    for (build_framework.buildSourceCandidates()[0..4]) |candidate| {
        const path = try pathJoin2(alloc, dir, candidate);
        defer alloc.free(path);
        if (absPathExists(io, path)) return true;
    }
    return false;
}

fn findWorkspaceRoot(alloc: std.mem.Allocator, io: Io) !?[]const u8 {
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = getCwd(&cwd_buf) catch return null;
    var current = try alloc.dupe(u8, cwd);
    while (true) {
        if (try dirHasWorkspaceMarker(alloc, io, current)) return current;
        const parent = std.fs.path.dirname(current) orelse break;
        if (std.mem.eql(u8, parent, current)) break;
        const next = try alloc.dupe(u8, parent);
        alloc.free(current);
        current = next;
    }
    alloc.free(current);
    return null;
}

fn enterWorkspaceRoot(alloc: std.mem.Allocator, io: Io) !void {
    const root = (try findWorkspaceRoot(alloc, io)) orelse return;
    defer alloc.free(root);
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = getCwd(&cwd_buf) catch return;
    if (std.mem.eql(u8, cwd, root)) return;
    const root_z = try alloc.dupeSentinel(u8, root, 0);
    defer alloc.free(root_z);
    if (std.c.chdir(root_z.ptr) != 0) {
        term.err("failed to enter workspace root '{s}'", .{root});
        std.process.exit(1);
    }
    term.infoMsg("workspace root {s}", .{root});
}

fn getCwd(buf: *[std.fs.max_path_bytes]u8) ![]const u8 {
    _ = std.c.getcwd(buf[0..].ptr, buf.len) orelse return error.Unexpected;
    return std.mem.sliceTo(buf[0..], 0);
}

fn buildSourcePath(io: Io, requested: ?[]const u8) []const u8 {
    if (requested) |r| {
        if (is_source_path(r)) return r;
    }
    const path = build_framework.findBuildSource(io, null);
    const cwd = Io.Dir.cwd();
    cwd.access(io, path, .{}) catch {
        term.err("no build source found", .{});
        term.hint("expected build.id, src/build.id, src/main.id, or main.id; .lua remains foreign compatibility input", .{});
        std.process.exit(1);
    };
    return path;
}

fn resolveDefaultSource(alloc: std.mem.Allocator, io: Io) ![]const u8 {
    if (build_framework.findEntrypoint(io)) |path| {
        term.infoMsg("selected default source '{s}'", .{path});
        return try alloc.dupe(u8, path);
    }
    term.err("no input file and no default source found", .{});
    term.hint("create src/main.id or main.id; .lua entrypoints remain foreign compatibility input", .{});
    std.process.exit(1);
}

fn requestedTargetName(requested: ?[]const u8) ?[]const u8 {
    if (requested) |r| {
        if (is_source_path(r)) return null;
        return r;
    }
    return null;
}

fn loadBuildProject(alloc: std.mem.Allocator, io: Io, requested: ?[]const u8) !build_framework.Project {
    const build_source = buildSourcePath(io, requested);
    var ps = try parse_and_check(alloc, io, build_source);
    _ = &ps;
    var project = try build_framework.loadFromSema(alloc, build_source, &ps.sem);
    if (project.targets.len == 0 and std.mem.eql(u8, std.fs.path.basename(build_source), "build.id")) {
        project.deinit(alloc);
        const source = try read_source(alloc, io, build_source);
        defer alloc.free(source);
        return try build_framework.loadLegacyManifest(alloc, build_source, source);
    }
    return project;
}

fn maybeReadBuildTarget(alloc: std.mem.Allocator, io: Io, requested: ?[]const u8, prefer_kind: ?build_framework.TargetKind) !?build_framework.Target {
    var project = try loadBuildProject(alloc, io, requested);
    defer project.deinit(alloc);
    const want = requestedTargetName(requested);
    const resolved = build_framework.resolveTarget(&project, want, prefer_kind) catch |e| switch (e) {
        build_framework.ResolveError.TargetNotFound => {
            term.err("target '{s}' not found in '{s}'", .{ want.?, project.build_source });
            if (build_framework.nearestTargetName(want.?, &project)) |hint| {
                term.hint("did you mean '{s}'? try: duo build {s}", .{ hint, hint });
            } else {
                const names = build_framework.listTargetNames(alloc, &project) catch "";
                defer alloc.free(names);
                if (names.len > 0) term.hint("available targets: {s}", .{names});
            }
            std.process.exit(1);
        },
        build_framework.ResolveError.NoTargets => {
            return null;
        },
    };
    return try build_framework.cloneTarget(alloc, resolved);
}

fn readBuildTarget(alloc: std.mem.Allocator, io: Io, requested: ?[]const u8, prefer_kind: ?build_framework.TargetKind) !build_framework.Target {
    return (try maybeReadBuildTarget(alloc, io, requested, prefer_kind)) orelse {
        term.err("no build targets found — add @build.run {{ src = \"...\" }} or a build.id target manifest", .{});
        std.process.exit(1);
    };
}

fn buildTargetRows(alloc: std.mem.Allocator, project: *const build_framework.Project) ![]term.BuildTargetRow {
    var rows = try alloc.alloc(term.BuildTargetRow, project.targets.len);
    for (project.targets, 0..) |t, i| {
        const is_default = if (project.default_target) |d| std.mem.eql(u8, d, t.name) else i == 0;
        rows[i] = .{
            .name = t.name,
            .kind = build_framework.kindLabel(t.kind),
            .glyph = build_framework.kindGlyph(t.kind),
            .src = t.src,
            .out = t.out,
            .stage = t.stage,
            .stage_name = build_framework.stageLabel(project, t),
            .is_default = is_default,
            .deps = t.deps,
        };
    }
    return rows;
}

fn logBuildStages(project: *const build_framework.Project) void {
    if (project.stages.len == 0 or term.build_report == .plain) return;
    term.section("stages");
    for (project.stages) |stage| {
        var order_buf: [32]u8 = undefined;
        const order = std.fmt.bufPrint(&order_buf, "{d}", .{stage.order}) catch "?";
        if (stage.desc) |desc| {
            term.kv(stage.name, desc);
        } else {
            term.kv(stage.name, order);
        }
    }
}

fn do_build_list(alloc: std.mem.Allocator, io: Io) !void {
    var project = try loadBuildProject(alloc, io, null);
    defer project.deinit(alloc);
    term.buildProjectHero(project.name, project.version, project.build_source);
    logBuildStages(&project);
    const rows = try buildTargetRows(alloc, &project);
    defer alloc.free(rows);
    term.buildTargetTable(rows);
    term.dim("inline @build.* — targets can live in build.id, src/build.id, or the entrypoint", .{});
}

fn do_build_all(
    alloc: std.mem.Allocator,
    io: Io,
    stage_filter: ?[]const u8,
    output_file: ?[]const u8,
    cc_arg: []const u8,
    opt_arg: []const u8,
    target_arg: []const u8,
    backend_mode: []const u8,
    verbose: bool,
    load_chunk_arg: bool,
    pgo_arg: bool,
    lib_mode_arg: bool,
    shared_mem_arg: bool,
    link_flags_arg: []const []const u8,
) !void {
    var project = try loadBuildProject(alloc, io, null);
    defer project.deinit(alloc);
    const order = try build_framework.sortBuildOrder(alloc, &project);
    defer alloc.free(order);
    term.banner("build all");
    term.buildProjectHero(project.name, project.version, project.build_source);
    logBuildStages(&project);
    var built: usize = 0;
    for (order) |idx| {
        const t = project.targets[idx];
        if (stage_filter) |stage| {
            if (!build_framework.targetMatchesStage(&project, t, stage)) continue;
        }
        if (!t.needs_compile()) continue;
        built += 1;
        term.section(t.name);
        try do_project_build_one(alloc, io, t, output_file, cc_arg, opt_arg, target_arg, backend_mode, verbose, load_chunk_arg, pgo_arg, lib_mode_arg, shared_mem_arg, link_flags_arg, false);
    }
    if (built == 0) {
        term.hint("no compile targets — add @build.run or @build.exe", .{});
    } else {
        term.ok("built {d} target(s)", .{built});
    }
}

fn do_build_stage(
    alloc: std.mem.Allocator,
    io: Io,
    stage_filter: []const u8,
    output_file: ?[]const u8,
    cc_arg: []const u8,
    opt_arg: []const u8,
    target_arg: []const u8,
    backend_mode: []const u8,
    verbose: bool,
    load_chunk_arg: bool,
    pgo_arg: bool,
    lib_mode_arg: bool,
    shared_mem_arg: bool,
    link_flags_arg: []const []const u8,
) !void {
    var project = try loadBuildProject(alloc, io, null);
    defer project.deinit(alloc);
    const order = try build_framework.sortBuildOrder(alloc, &project);
    defer alloc.free(order);
    term.banner("build stage");
    term.buildProjectHero(project.name, project.version, project.build_source);
    term.kv("stage", stage_filter);
    var built: usize = 0;
    for (order) |idx| {
        const t = project.targets[idx];
        if (!build_framework.targetMatchesStage(&project, t, stage_filter)) continue;
        built += 1;
        term.section(t.name);
        switch (t.kind) {
            .clean => try do_project_clean(io),
            .fmt => try do_project_fmt(alloc, io, t),
            .check => try do_project_check(alloc, io, t),
            else => try do_project_build_one(alloc, io, t, output_file, cc_arg, opt_arg, target_arg, backend_mode, verbose, load_chunk_arg, pgo_arg, lib_mode_arg, shared_mem_arg, link_flags_arg, false),
        }
    }
    if (built == 0) {
        term.err("no targets in stage '{s}'", .{stage_filter});
        const names = build_framework.listTargetNames(alloc, &project) catch "";
        defer alloc.free(names);
        if (names.len > 0) term.hint("available targets: {s}", .{names});
        std.process.exit(1);
    }
    term.ok("built {d} target(s) in stage {s}", .{ built, stage_filter });
}

fn do_project_clean(io: Io) !void {
    term.banner("clean");
    const argv = [_][]const u8{ "rm", "-rf", "zig-out" };
    try run_child_process(io, &argv, "clean", false);
    term.ok("removed zig-out/", .{});
}

fn fmtTree(alloc: std.mem.Allocator, io: Io, dir_path: []const u8) !void {
    var dir = try Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true });
    defer dir.close(io);
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind == .directory) {
            if (std.mem.eql(u8, entry.name, "zig-out") or std.mem.eql(u8, entry.name, ".git")) continue;
            const sub = try std.fs.path.join(alloc, &.{ dir_path, entry.name });
            defer alloc.free(sub);
            try fmtTree(alloc, io, sub);
            continue;
        }
        if (is_source_path(entry.name)) {
            const path = try std.fs.path.join(alloc, &.{ dir_path, entry.name });
            defer alloc.free(path);
            try do_fmt(alloc, io, path, false);
        }
    }
}

fn do_project_fmt(alloc: std.mem.Allocator, io: Io, t: build_framework.Target) !void {
    term.banner("fmt");
    if (t.src) |src| {
        if (std.mem.eql(u8, src, ".") or std.mem.endsWith(u8, src, "/")) {
            try fmtTree(alloc, io, if (std.mem.eql(u8, src, ".")) "." else src);
        } else {
            try do_fmt(alloc, io, src, false);
        }
    } else {
        try fmtTree(alloc, io, ".");
    }
    term.ok("formatted", .{});
}

fn do_project_check(alloc: std.mem.Allocator, io: Io, t: build_framework.Target) !void {
    term.banner("check");
    if (t.src) |src| {
        const dummy = try std.fmt.allocPrint(alloc, "/tmp/duo_check_{s}.out", .{std.fs.path.stem(src)});
        defer alloc.free(dummy);
        try do_compile(alloc, io, src, dummy, t.cc orelse "clang", t.opt orelse "-O3", t.target orelse "native", "auto", false, true, false, false, false, false, false, false, false, null, t.link, null);
        term.ok("'{s}' ok", .{src});
        return;
    }
    const cwd = Io.Dir.cwd();
    cwd.access(io, "src", .{}) catch {
        term.err("@build.check needs src= or a src/ directory", .{});
        std.process.exit(1);
    };
    try fmtTree(alloc, io, "src");
    term.ok("type-checked project sources", .{});
}

fn fileMayContainInlineTest(bytes: []const u8, lua_mode: bool, bench_only: bool) bool {
    if (lua_mode) {
        if (bench_only) return std.mem.indexOf(u8, bytes, "--- @bench") != null or std.mem.indexOf(u8, bytes, "--- @test.bench") != null;
        return std.mem.indexOf(u8, bytes, "--- @test") != null or std.mem.indexOf(u8, bytes, "--- @bench") != null;
    }
    if (bench_only) return std.mem.indexOf(u8, bytes, "@bench") != null or std.mem.indexOf(u8, bytes, "@test.bench") != null;
    return std.mem.indexOf(u8, bytes, "@test") != null or std.mem.indexOf(u8, bytes, "@bench") != null;
}

fn shouldSkipScanDir(name: []const u8) bool {
    return std.mem.eql(u8, name, ".git") or
        std.mem.eql(u8, name, ".zig-cache") or
        std.mem.eql(u8, name, "zig-out") or
        std.mem.eql(u8, name, "node_modules");
}

fn scanInlineTestDir(
    alloc: std.mem.Allocator,
    io: Io,
    rel_dir: []const u8,
    bench_only: bool,
    out: *std.ArrayListUnmanaged([]const u8),
) !void {
    var dir = try Io.Dir.cwd().openDir(io, rel_dir, .{ .iterate = true });
    defer dir.close(io);
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind == .directory) {
            if (shouldSkipScanDir(entry.name)) continue;
            const child = if (std.mem.eql(u8, rel_dir, "."))
                try alloc.dupe(u8, entry.name)
            else
                try std.fs.path.join(alloc, &.{ rel_dir, entry.name });
            defer alloc.free(child);
            try scanInlineTestDir(alloc, io, child, bench_only, out);
            continue;
        }
        if (entry.kind != .file) continue;
        const facts = lexer_bridge.sourceFacts(entry.name);
        if (facts.law == .unknown) continue;
        const path = if (std.mem.eql(u8, rel_dir, "."))
            try alloc.dupe(u8, entry.name)
        else
            try std.fs.path.join(alloc, &.{ rel_dir, entry.name });
        errdefer alloc.free(path);
        const bytes = read_source(alloc, io, path) catch {
            alloc.free(path);
            continue;
        };
        defer alloc.free(bytes);
        if (fileMayContainInlineTest(bytes, facts.law == .lua, bench_only)) {
            try out.append(alloc, path);
        } else {
            alloc.free(path);
        }
    }
}

fn lessTestPath(_: void, a: []const u8, b: []const u8) bool {
    const score = struct {
        fn value(path: []const u8) u8 {
            if (std.mem.eql(u8, path, "test/main.id")) return 0;
            if (std.mem.eql(u8, path, "test/main.id")) return 1;
            if (std.mem.eql(u8, path, "test/main.lua")) return 2;
            if (std.mem.startsWith(u8, path, "test/")) return 3;
            if (std.mem.startsWith(u8, path, "tests/")) return 4;
            if (std.mem.startsWith(u8, path, "src/")) return 5;
            return 6;
        }
    }.value;
    const sa = score(a);
    const sb = score(b);
    if (sa != sb) return sa < sb;
    return std.mem.order(u8, a, b) == .lt;
}

fn scanInlineTestSources(alloc: std.mem.Allocator, io: Io, bench_only: bool) ![]const []const u8 {
    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (list.items) |path| alloc.free(path);
        list.deinit(alloc);
    }
    try scanInlineTestDir(alloc, io, ".", bench_only, &list);
    std.mem.sort([]const u8, list.items, {}, lessTestPath);
    return try list.toOwnedSlice(alloc);
}

fn run_test_sources(
    alloc: std.mem.Allocator,
    io: Io,
    sources: []const []const u8,
    output_file: ?[]const u8,
    cc: []const u8,
    opt_level: []const u8,
    target: []const u8,
    backend_mode: []const u8,
    verbose: bool,
    bench_only: bool,
    test_filter: ?[]const u8,
    link_flags: []const []const u8,
) !void {
    if (term.test_report != .json) {
        term.banner(if (bench_only) "bench" else "test");
        term.kv("report", @tagName(term.test_report));
        if (test_filter) |f| term.kv("filter", f);
    }
    var failures: u32 = 0;
    for (sources, 0..) |file, idx| {
        if (term.test_report != .json) term.kv("source", file);
        const out = if (output_file != null and sources.len == 1)
            output_file.?
        else
            try std.fmt.allocPrint(alloc, "/tmp/duo_{s}_{d}.test.out", .{ std.fs.path.stem(file), idx });
        defer if (!(output_file != null and sources.len == 1)) alloc.free(out);
        try do_compile(alloc, io, file, out, cc, opt_level, target, backend_mode, false, false, verbose, false, false, false, false, true, bench_only, test_filter, link_flags, null);
        const code = try run_pretty_test_runner(alloc, io, out, bench_only);
        if (code != 0) failures += 1;
    }
    if (failures > 0) {
        term.err("{d} test file(s) failed", .{failures});
        std.process.exit(1);
    }
}

fn do_symbols(alloc: std.mem.Allocator, io: Io, src_path: []const u8) !void {
    const ps = try parse_and_check(alloc, io, src_path);
    term.banner("symbols");
    term.kv("source", src_path);
    if (ps.sem.build_directives.items.len > 0) {
        var project = try build_framework.loadFromSema(alloc, src_path, &ps.sem);
        defer project.deinit(alloc);
        term.buildProjectHero(project.name, project.version, project.build_source);
        if (project.targets.len > 0) {
            const rows = try buildTargetRows(alloc, &project);
            defer alloc.free(rows);
            term.buildTargetTable(rows);
        }
    }
    if (ps.sem.test_entries.items.len > 0) {
        term.section("tests");
        for (ps.sem.test_entries.items) |entry| {
            var tags: std.ArrayListUnmanaged(u8) = .empty;
            defer tags.deinit(alloc);
            const opts = entry.options;
            if (opts.skip) try tags.appendSlice(alloc, "skip ");
            if (opts.only) try tags.appendSlice(alloc, "only ");
            if (opts.flaky) try tags.appendSlice(alloc, "flaky ");
            if (opts.should_panic) try tags.appendSlice(alloc, "panic ");
            if (opts.bench) try tags.appendSlice(alloc, "bench ");
            if (opts.time) try tags.appendSlice(alloc, "time ");
            if (opts.tag) |tag| {
                try tags.appendSlice(alloc, tag);
                try tags.append(alloc, ' ');
            }
            const tag_str = if (tags.items.len > 0) tags.items else "";
            term.kv(entry.func_name, tag_str);
        }
    }
    var funcs: usize = 0;
    for (ps.mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        funcs += 1;
    }
    term.section("module");
    var func_buf: [32]u8 = undefined;
    term.kv("functions", std.fmt.bufPrint(&func_buf, "{d}", .{funcs}) catch "?");
    term.divider();
    term.dim("inline tests live in source — duo test {s}", .{src_path});
}

fn hashSourceFile(alloc: std.mem.Allocator, io: Io, src_path: []const u8) !u64 {
    const data = try Io.Dir.readFileAlloc(std.Io.Dir.cwd(), io, src_path, alloc, .unlimited);
    defer alloc.free(data);
    return std.hash.Wyhash.hash(0, data);
}

fn do_graph(alloc: std.mem.Allocator, io: Io, src_path: []const u8, write_sidecar: bool) !void {
    var ps = try parse_and_check(alloc, io, src_path);
    defer ps.sem.deinit();
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ps.mod, &ps.sem, src_path);
    const source_hash = hashSourceFile(alloc, io, src_path) catch null;
    var json: std.ArrayListUnmanaged(u8) = .empty;
    defer json.deinit(alloc);
    try graph.writeJson(alloc, src_path, &json, source_hash);
    const stdout = std.Io.File.stdout();
    var buf: [4096]u8 = undefined;
    var fw: std.Io.File.Writer = .init(stdout, io, &buf);
    try fw.interface.writeAll(json.items);
    try fw.interface.flush();
    if (write_sidecar or graph_write_enabled) {
        if (source_hash) |h| {
            try graph.writeSidecar(alloc, io, src_path, h);
            if (term.info) {
                var path_buf: [512]u8 = undefined;
                const rel = semantic_graph.SemanticGraph.sidecarRelPath(src_path, &path_buf);
                term.infoMsg("graph sidecar: {s}", .{rel});
            }
        }
    }
}

fn do_sim(alloc: std.mem.Allocator, io: Io, src_path: []const u8) !void {
    var ps = try parse_and_check(alloc, io, src_path);
    defer ps.sem.deinit();
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ps.mod, &ps.sem, src_path);
    var snap = try sim_pipeline.exportInterchangeWithGraph(alloc, &ps.mod, src_path, &graph);
    defer snap.deinit(alloc);
    const stdout = std.Io.File.stdout();
    var buf: [8192]u8 = undefined;
    var fw: std.Io.File.Writer = .init(stdout, io, &buf);
    try sim.writeSnapshotJson(&snap, &fw.interface);
    try fw.interface.flush();
}

fn do_sim_c_import(alloc: std.mem.Allocator, io: Io, header_path: []const u8) !void {
    var snap = try c_sim_import.importHeaderFile(alloc, io, header_path);
    defer snap.deinit(alloc);
    try abi_specialize.specializeSnapshot(alloc, &snap);
    const stdout = std.Io.File.stdout();
    var buf: [8192]u8 = undefined;
    var fw: std.Io.File.Writer = .init(stdout, io, &buf);
    try sim.writeSnapshotJson(&snap, &fw.interface);
    try fw.interface.flush();
}

fn do_realize(alloc: std.mem.Allocator, io: Io, src_path: []const u8) !void {
    var ps = try parse_and_check(alloc, io, src_path);
    defer ps.sem.deinit();

    var refresh = try compile_semantic_cache.refreshFromCheckedModule(alloc, io, &ps.mod, src_path, "native");
    defer refresh.deinit(alloc);

    const stdout = std.Io.File.stdout();
    var buf: [16384]u8 = undefined;
    var fw: std.Io.File.Writer = .init(stdout, io, &buf);
    try fw.interface.print("{{\"schema\":\"duo-realize-v0\",\"file\":\"", .{});
    for (src_path) |c| {
        switch (c) {
            '"', '\\' => try fw.interface.print("\\{c}", .{c}),
            else => try fw.interface.writeAll(&.{c}),
        }
    }
    try fw.interface.print("\",\"realization_plan\":", .{});
    try realization.writeJson(&refresh.realizations, &fw.interface);
    try fw.interface.print(",\"evidence_catalog\":", .{});
    try evidence_record.writeCatalogJson(&fw.interface);
    try fw.interface.print(",\"persistent_state\":", .{});
    try persistent_semantic_state.writeJson(&refresh.state, &fw.interface);
    try fw.interface.print(",\"cache_path\":\"", .{});
    for (persistent_semantic_state.DEFAULT_CACHE_PATH) |c| {
        switch (c) {
            '"', '\\' => try fw.interface.print("\\{c}", .{c}),
            else => try fw.interface.writeAll(&.{c}),
        }
    }
    try fw.interface.print("\",\"reuse_audit\":", .{});
    try persistent_semantic_state.writeReuseAuditJson(refresh.audits, &fw.interface);
    try fw.interface.print(",\"invalidation\":", .{});
    try semantic_invalidation.writeJson(&refresh.invalidation, &fw.interface);
    try fw.interface.print("}}\n", .{});
    try fw.interface.flush();
}

fn do_explain(alloc: std.mem.Allocator, io: Io, src_path: []const u8) !void {
    contract_defer_exit = true;
    var ps = try parse_and_check(alloc, io, src_path);
    defer ps.sem.deinit();
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ps.mod, &ps.sem, src_path);

    var snap = try knowledge_snapshot.buildFromModule(alloc, &ps.sem, &graph, src_path);
    defer snap.deinit(alloc);

    var assumptions = try assumption_guard.buildFromModule(alloc, &ps.mod, &ps.sem, &graph);
    defer assumptions.deinit(alloc);

    var realizations = try realization.buildFromGraph(alloc, &graph, src_path);
    defer realizations.deinit(alloc);

    transform_engine.deinitProvenance(alloc);
    explain_pipeline.runForProvenance(alloc, io, &ps.mod, &ps.sem, src_path, compiler_lib_root) catch |e| switch (e) {
        error.NoAllocViolation => {
            term.err("@noalloc contract violated during explain/codegen (see optimization_outcomes)", .{});
        },
        error.MonomorphizationFailed => {
            term.err("explain: monomorphization failed", .{});
            std.process.exit(1);
        },
        error.ArcFailed, error.AsyncLowerFailed => {
            term.err("explain: lowering pass failed", .{});
            std.process.exit(1);
        },
        error.CodegenFailed => {
            term.err("explain: codegen failed", .{});
            std.process.exit(1);
        },
        else => |err| return err,
    };
    defer transform_engine.deinitProvenance(alloc);
    defer optimization_outcome.deinitSession(alloc);

    var outcomes = try optimization_outcome.fromProvenance(alloc);
    defer outcomes.deinit(alloc);
    // Include structured contract rejections logged during codegen.
    try optimization_outcome.mergeSessionInto(alloc, &outcomes);

    var repair_set: ?repair_candidate.RepairSet = null;
    defer if (repair_set) |*rs| rs.deinit(alloc);
    for (outcomes.items) |o| {
        if (std.mem.eql(u8, o.transformation, "contract.noalloc") and o.status == .rejected) {
            repair_set = try repair_candidate.repairsForBlocker("noalloc_heap_alloc", alloc);
            break;
        }
    }

    const stdout = std.Io.File.stdout();
    var buf: [16384]u8 = undefined;
    var fw: std.Io.File.Writer = .init(stdout, io, &buf);
    try fw.interface.print("{{\"schema\":\"duo-explain-v0\",\"file\":\"", .{});
    for (src_path) |c| {
        switch (c) {
            '"', '\\' => try fw.interface.print("\\{c}", .{c}),
            else => try fw.interface.writeAll(&.{c}),
        }
    }
    try fw.interface.print("\",\"knowledge_snapshot\":", .{});
    try knowledge_snapshot.writeJson(&snap, &fw.interface);
    try fw.interface.print(",\"optimization_outcomes\":", .{});
    try optimization_outcome.writeJson(&outcomes, &fw.interface);
    try fw.interface.print(",\"assumptions\":", .{});
    try assumption_guard.writeModuleJson(&assumptions, &fw.interface);
    try fw.interface.print(",\"realizations\":", .{});
    try realization.writeJson(&realizations, &fw.interface);
    // H-8 output totality: the transform engine's provenance and its tier-1
    // registry contract are compiler state with no other projection. Rendering
    // them here is what lets the dispatch gate be asserted from outside the
    // process instead of only from an in-process Zig test.
    try fw.interface.print(",\"transform_provenance\":", .{});
    try transform_engine.writeProvenanceJson(&fw.interface);
    try fw.interface.print(",\"transform_registry\":", .{});
    try transform_engine.writeRegistryJson(&fw.interface);
    if (repair_set) |rs| {
        try fw.interface.print(",\"repair_candidates\":", .{});
        try repair_candidate.writeRepairSetJson(&rs, &fw.interface);
    }
    try fw.interface.print("}}\n", .{});
    try fw.interface.flush();
    // The render is complete; the verdict is still a rejection. GAP-090 measured
    // this verb exiting 0 with the violation present as JSON — an emission with
    // no consequence is what let the contract stay decorative.
    if (contract_violations > 0) std.process.exit(1);
}

fn do_prove(alloc: std.mem.Allocator, io: Io) !bool {
    const cwd = Io.Dir.cwd();
    try cwd.createDirPath(io, proof_carrying.RELEASE_PROOF_BUNDLE_DIR);

    const revision_process = try std.process.run(alloc, io, .{
        .argv = &.{ "git", "rev-parse", "HEAD" },
    });
    defer alloc.free(revision_process.stdout);
    defer alloc.free(revision_process.stderr);
    if (!revision_process.term.success()) {
        term.err("duo prove could not identify the source revision: {s}", .{revision_process.stderr});
        return false;
    }
    const revision = std.mem.trim(u8, revision_process.stdout, " \t\r\n");

    const worktree_process = try std.process.run(alloc, io, .{
        .argv = &.{ "git", "status", "--porcelain=v1", "--untracked-files=all" },
    });
    defer alloc.free(worktree_process.stdout);
    defer alloc.free(worktree_process.stderr);
    if (!worktree_process.term.success()) {
        term.err("duo prove could not inspect the source worktree: {s}", .{worktree_process.stderr});
        return false;
    }
    const worktree_path = try std.fmt.allocPrint(alloc, "{s}/worktree.txt", .{proof_carrying.RELEASE_PROOF_BUNDLE_DIR});
    try Io.Dir.writeFile(cwd, io, .{ .sub_path = worktree_path, .data = worktree_process.stdout });
    const worktree_clean = std.mem.trim(u8, worktree_process.stdout, " \t\r\n").len == 0;

    term.print("Idol release proof\n", .{});
    term.print("  source {s}: {s}\n", .{ revision, if (worktree_clean) "clean" else "dirty" });
    var results: std.ArrayListUnmanaged(proof_carrying.ReleaseGateResult) = .empty;
    defer results.deinit(alloc);
    for (proof_carrying.release_gates) |gate| {
        const log_path = try std.fmt.allocPrint(alloc, "{s}/{s}.log", .{
            proof_carrying.RELEASE_PROOF_BUNDLE_DIR,
            gate,
        });
        const status = try run_release_gate(alloc, io, gate, log_path);
        try results.append(alloc, .{
            .gate = gate,
            .status = status,
            .log_path = log_path,
        });
        term.print("  gate {s}: {s}\n", .{ gate, status.name() });
    }

    var summary: std.Io.Writer.Allocating = .init(alloc);
    defer summary.deinit();
    try proof_carrying.writeReleaseProofJson(&summary.writer, revision, worktree_clean, results.items);
    const summary_path = try std.fmt.allocPrint(alloc, "{s}/summary.json", .{proof_carrying.RELEASE_PROOF_BUNDLE_DIR});
    try Io.Dir.writeFile(cwd, io, .{ .sub_path = summary_path, .data = summary.written() });

    var proven: usize = 0;
    var complete = worktree_clean;
    for (proof_carrying.release_proofs) |domain| {
        const status = proof_carrying.releaseProofStatus(domain, results.items);
        if (status == .proven) {
            proven += 1;
        } else {
            complete = false;
        }
        term.print("  proof {s}: {s} ({s})\n", .{
            domain.kind.id(),
            status.name(),
            domain.readiness.name(),
        });
    }
    term.print("release claims: {}/{} proven\n", .{ proven, proof_carrying.release_proofs.len });
    term.print("proof bundle: {s}\n", .{proof_carrying.RELEASE_PROOF_BUNDLE_DIR});
    if (!worktree_clean) term.err("release proof source worktree is dirty; see {s}", .{worktree_path});
    if (!complete) term.err("release proof is incomplete; unproven domains remain release blockers", .{});
    return complete;
}

fn run_release_gate(
    alloc: std.mem.Allocator,
    io: Io,
    gate: []const u8,
    log_path: []const u8,
) !proof_carrying.ReleaseGateStatus {
    const cwd = Io.Dir.cwd();
    var log_file = try cwd.createFile(io, log_path, .{});
    var child = std.process.spawn(io, .{
        .argv = &.{ "zig", "build", gate },
        .stdin = .ignore,
        .stdout = .{ .file = log_file },
        .stderr = .{ .file = log_file },
    }) catch |err| {
        log_file.close(io);
        const message = try std.fmt.allocPrint(alloc, "unable to start `zig build {s}`: {s}\n", .{ gate, @errorName(err) });
        try Io.Dir.writeFile(cwd, io, .{ .sub_path = log_path, .data = message });
        return .unavailable;
    };
    defer child.kill(io);
    const result = child.wait(io) catch |err| {
        log_file.close(io);
        term.err("duo prove could not wait for gate {s}: {s}", .{ gate, @errorName(err) });
        return .unavailable;
    };
    log_file.close(io);
    return if (result.success()) .passed else .failed;
}

fn do_algebra(io: Io) !void {
    const stdout = std.Io.File.stdout();
    var buf: [8192]u8 = undefined;
    var fw: std.Io.File.Writer = .init(stdout, io, &buf);
    try semantic_algebra.writeCatalogJson(&fw.interface);
    try fw.interface.flush();
}

fn do_semantic(alloc: std.mem.Allocator, io: Io, sub: []const u8, entity_arg: ?[]const u8) !void {
    const stdout = std.Io.File.stdout();
    var buf: [65536]u8 = undefined;
    var fw: std.Io.File.Writer = .init(stdout, io, &buf);
    const entity = entity_arg orelse "duo:lexer:keyword_classifier";
    if (std.mem.eql(u8, sub, "intent")) {
        try semantic_cli.writeIntentJson(&fw.interface, entity);
    } else if (std.mem.eql(u8, sub, "compare") or std.mem.eql(u8, sub, "candidates")) {
        try semantic_cli.writeCandidateCompareJson(&fw.interface, alloc);
    } else if (std.mem.eql(u8, sub, "proof") or std.mem.eql(u8, sub, "bundle")) {
        try semantic_cli.writeProofBundleJson(&fw.interface, alloc, entity);
    } else if (std.mem.eql(u8, sub, "obligations")) {
        try semantic_cli.writeProofObligationsJson(&fw.interface, entity);
    } else if (std.mem.eql(u8, sub, "projections")) {
        try semantic_cli.writeProjectionsJson(&fw.interface);
    } else if (std.mem.eql(u8, sub, "context")) {
        try semantic_cli.writeContextJson(&fw.interface, entity_arg);
    } else if (std.mem.eql(u8, sub, "preview")) {
        try semantic_cli.writeTransactionPreviewJson(&fw.interface, entity_arg);
    } else if (std.mem.eql(u8, sub, "validate")) {
        try semantic_cli.writeTransactionValidateJson(&fw.interface, entity_arg);
    } else if (std.mem.eql(u8, sub, "transforms")) {
        try semantic_cli.writeTransformProofLogJson(&fw.interface);
    } else if (std.mem.eql(u8, sub, "claims")) {
        try semantic_cli.writeClaimsJson(&fw.interface, alloc);
    } else {
        term.err("unknown semantic subcommand '{s}' (expected: intent, compare, proof, obligations, projections, context, preview, validate, transforms, claims)", .{sub});
        std.process.exit(1);
    }
    try fw.interface.writeAll("\n");
    try fw.interface.flush();
}

fn ensureDirForPath(io: Io, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (std.mem.eql(u8, dir, ".")) return;
        const argv = [_][]const u8{ "mkdir", "-p", dir };
        try run_child_process(io, &argv, "mkdir", true);
    }
}

fn writeNewFile(io: Io, path: []const u8, data: []const u8) !void {
    const cwd = Io.Dir.cwd();
    Io.Dir.writeFile(cwd, io, .{ .sub_path = path, .data = data, .flags = .{ .exclusive = true } }) catch |e| switch (e) {
        error.PathAlreadyExists => {
            term.err("refusing to overwrite existing {s}", .{path});
            std.process.exit(1);
        },
        else => return e,
    };
}

fn do_init(alloc: std.mem.Allocator, io: Io, name: []const u8) !void {
    _ = alloc;
    const main_src =
        \\main: i64 = ()
        \\    0
        \\
    ;

    const mkdir_argv = [_][]const u8{ "mkdir", "-p", "src", "zig-out/bin" };
    try run_child_process(io, &mkdir_argv, "mkdir", true);
    try writeNewFile(io, "src/main.id", main_src);
    term.banner("Idol project created");
    term.kv("name", name);
    term.section("files");
    term.kv("•", "src/main.id");
    term.kv("•", "zig-out/bin/");
    term.divider();
    term.dim("next: duo build   # compile default target", .{});
    term.dim("       duo test    # run inline @test functions", .{});
    term.dim("       duo run     # build and run", .{});
    term.dim("       duo shell  # interactive REPL", .{});
    term.ok("ready — project '{s}'", .{name});
}

// Track history for shell
var shell_history: std.ArrayList([]const u8) = .empty;
var shell_history_capacity: usize = 100; // max history entries to keep

/// Track open/close keywords for multi-line input
fn shellBlockDepth(line: []const u8) i32 {
    var depth: i32 = 0;
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        // Skip string literals
        if (line[i] == '"' or line[i] == '\'') {
            const quote = line[i];
            i += 1;
            while (i < line.len) : (i += 1) {
                if (line[i] == '\\' and i + 1 < line.len) i += 1;
                if (line[i] == quote) break;
            }
            continue;
        }
        // Check for block starters (if, fun, for, while, repeat followed by do or condition)
        // These open a block that needs an "end"
        if (std.mem.startsWith(u8, line[i..], "if ") or
            std.mem.startsWith(u8, line[i..], "fun ") or
            std.mem.startsWith(u8, line[i..], "for ") or
            std.mem.startsWith(u8, line[i..], "while ") or
            (std.mem.startsWith(u8, line[i..], "if") and (i + 2 == line.len or !std.ascii.isAlphanumeric(line[i + 2]) and line[i + 2] != '_')) or
            (std.mem.startsWith(u8, line[i..], "fun") and (i + 3 == line.len or !std.ascii.isAlphanumeric(line[i + 3]) and line[i + 3] != '_')) or
            (std.mem.startsWith(u8, line[i..], "for") and (i + 3 == line.len or !std.ascii.isAlphanumeric(line[i + 3]) and line[i + 3] != '_')))
        {
            depth += 1;
            continue;
        }
        // Check for "do" after repeat/while
        if (std.mem.startsWith(u8, line[i..], "do") and (i + 2 == line.len or (!std.ascii.isAlphanumeric(line[i + 2]) and line[i + 2] != '_'))) {
            // Check if preceded by "repeat" or "while"
            var j: usize = i;
            while (j > 0 and line[j - 1] == ' ') j -= 1;
            if (j >= 5 and std.mem.eql(u8, line[j - 5 .. j], "while")) {
                depth += 1;
            } else if (j >= 6 and std.mem.eql(u8, line[j - 6 .. j], "repeat")) {
                depth += 1;
            }
            continue;
        }
        // Check for closing keywords - these close a block
        if (std.mem.startsWith(u8, line[i..], "end") and (i + 3 == line.len or (!std.ascii.isAlphanumeric(line[i + 3]) and line[i + 3] != '_'))) {
            depth -= 1;
            continue;
        }
    }
    return depth;
}

fn startsWithWord(line: []const u8, word: []const u8) bool {
    if (!std.mem.startsWith(u8, line, word)) return false;
    if (line.len == word.len) return true;
    const c = line[word.len];
    return !std.ascii.isAlphanumeric(c) and c != '_';
}

fn shellLineIsStatement(line: []const u8) bool {
    const keywords = [_][]const u8{
        "print",
        "local",
        "global",
        "fun",
        "async",
        "if",
        "for",
        "while",
        "repeat",
        "do",
        "return",
        "match",
        "try",
        "defer",
        "concept",
        "type",
        "alias",
        "enum",
        "struct",
        "impl",
        "use",
        "req",
    };
    if (line.len > 0 and line[0] == '@') return true;
    if (std.mem.startsWith(u8, line, "--")) return true;
    // Check for colon commands
    if (line.len > 0 and line[0] == ':') return true;
    for (keywords) |kw| {
        if (startsWithWord(line, kw)) return true;
    }
    return false;
}

fn run_shell_binary(io: Io, out_path: []const u8) !void {
    const run_argv = [_][]const u8{out_path};
    var run_child = try std.process.spawn(io, .{
        .argv = &run_argv,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const run_term = try run_child.wait(io);
    switch (run_term) {
        .exited => |code| if (code != 0) {
            term.print("program exited with code {}", .{code});
        },
        .signal => term.print("program terminated by signal", .{}),
        else => term.print("program terminated abnormally", .{}),
    }
}

fn run_host_shell_command(io: Io, command: []const u8) !void {
    const code = try shell_host.runRawShell(io, command);
    if (code != 0) {
        term.print("host command exited with code {}", .{code});
    }
}

fn run_build_command(io: Io, name: []const u8, command: []const u8) !void {
    term.banner("duo build");
    term.buildPhaseStart("command", name);
    term.kv("target", name);
    term.kv("command", command);
    const started = Io.Timestamp.now(io, .awake);
    const argv = [_][]const u8{ "/bin/sh", "-c", command };
    var child = try std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const result = try child.wait(io);
    switch (result) {
        .exited => |code| {
            if (code != 0) {
                term.err("command target '{s}' failed (exit {})", .{ name, code });
                std.process.exit(1);
            }
        },
        else => {
            term.err("command target '{s}' terminated abnormally", .{name});
            std.process.exit(1);
        },
    }
    const elapsed_ms: u64 = @intCast(@divTrunc(started.durationTo(Io.Timestamp.now(io, .awake)).nanoseconds, std.time.ns_per_ms));
    term.buildPhaseDone("command", elapsed_ms, name);
}

fn run_shell_line(
    alloc: std.mem.Allocator,
    io: Io,
    raw_line: []const u8,
    session: *shell_session.Session,
    verbose: bool,
    backend_mode: []const u8,
) !bool {
    const line = std.mem.trim(u8, raw_line, " \t\r\n");
    if (line.len == 0) return true;

    // Handle colon-prefixed shell commands
    if (line[0] == ':') {
        if (std.mem.eql(u8, line, ":quit") or std.mem.eql(u8, line, ":exit") or
            std.mem.eql(u8, line, "quit") or std.mem.eql(u8, line, "exit"))
        {
            return false;
        }
        if (std.mem.eql(u8, line, ":help")) {
            term.section("shell commands");
            term.kv("1 + 2", "evaluate and print expression");
            term.kv("fun f(x) x * 2 end", "define and compile function");
            term.kv("for i in 1..10 print(i) end", "multi-line supported");
            term.kv("!ls -la", "run host shell command");
            term.kv(":time", "show total shell execution time");
            term.kv(":reset", "clear session state (counter)");
            term.kv(":export", "write .id session source");
            term.kv(":snapshot", "print semantic session JSON");
            term.kv(":quit / :exit", "leave the shell");
            term.divider();
            term.dim("Idol compatibility shell; ! prefix is explicit raw {s}", .{shell_host.rawShellLabel()});
            return true;
        }
        if (std.mem.eql(u8, line, ":snapshot")) {
            const stdout = std.Io.File.stdout();
            var snap_buf: [4096]u8 = undefined;
            var fw: std.Io.File.Writer = .init(stdout, io, &snap_buf);
            try shell_session.writeSnapshotJson(&fw.interface, session);
            try fw.interface.writeAll("\n");
            try fw.interface.flush();
            return true;
        }
        if (std.mem.startsWith(u8, line, ":export")) {
            const mod = try shell_session.exportHistoryModule(alloc, session, 64);
            defer alloc.free(mod);
            const out_path = if (line.len > 7) std.mem.trim(u8, line[7..], " \t") else "shell_export.id";
            const cwd = std.Io.Dir.cwd();
            try Io.Dir.writeFile(cwd, io, .{ .sub_path = out_path, .data = mod });
            try shell_session.recordHistory(alloc, session, .@"export", line, mod, 0, null);
            term.ok("exported historical Idol source → {s}", .{out_path});
            return true;
        }
        if (std.mem.eql(u8, line, ":time")) {
            term.section("shell timing");
            var buf: [32]u8 = undefined;
            const lc = std.fmt.bufPrint(&buf, "{}", .{session.compile_counter}) catch "error";
            term.kv("lines compiled", lc);
            var buf2: [32]u8 = undefined;
            const hi = std.fmt.bufPrint(&buf2, "{}", .{session.history.items.len}) catch "error";
            term.kv("history entries", hi);
            term.kv("session", session.session_id);
            return true;
        }
        if (std.mem.eql(u8, line, ":reset")) {
            session.compile_counter = 0;
            if (term.color) {
                term.ok("\x1b[32m✓\x1b[0m session counter reset to 0", .{});
            } else {
                term.ok("session counter reset to 0", .{});
            }
            return true;
        }
        term.err("unknown shell command '{s}'", .{line});
        term.hint("type :help for available commands", .{});
        return true;
    }

    // Handle host shell commands (explicit raw shell — §7.3)
    if (line[0] == '!') {
        const cmd = std.mem.trim(u8, line[1..], " \t");
        const canonical = try std.fmt.allocPrint(alloc, "shell(\"{s}\")\n", .{cmd});
        defer alloc.free(canonical);
        const code = try shell_host.runRawShell(io, cmd);
        try shell_session.recordHistory(alloc, session, .raw_shell, line, canonical, @intCast(code), null);
        return true;
    }

    const is_stmt = shellLineIsStatement(line);
    const source = if (is_stmt)
        try shell_session.wrapStatement(alloc, line)
    else
        try shell_session.wrapExpression(alloc, line);
    defer alloc.free(source);

    const src_path = try shell_session.tempArtifactBasename(alloc, session.compile_counter, "duo");
    const out_path = try shell_session.tempArtifactBasename(alloc, session.compile_counter, "out");
    defer alloc.free(src_path);
    defer alloc.free(out_path);
    session.compile_counter += 1;

    const cwd = Io.Dir.cwd();
    try Io.Dir.writeFile(cwd, io, .{ .sub_path = src_path, .data = source });

    // Compile and run (with timing in verbose mode)
    // Suppress build phase output for cleaner shell experience
    const prev_report = term.build_report;
    term.build_report = .plain;
    defer term.build_report = prev_report;

    const compile_started = Io.Timestamp.now(io, .awake);
    try do_compile(alloc, io, src_path, out_path, "clang", "-O3", "native", backend_mode, false, false, verbose, false, false, false, false, false, false, null, &.{}, null);
    const compile_elapsed: u64 = @intCast(@divTrunc(compile_started.durationTo(Io.Timestamp.now(io, .awake)).nanoseconds, std.time.ns_per_ms));

    try run_shell_binary(io, out_path);
    try shell_session.recordHistory(alloc, session, if (is_stmt) .statement else .expression, line, source, 0, compile_elapsed);
    if (verbose) {
        if (term.color) {
            term.dim("  \x1b[2mcompile: {} ms\x1b[0m\n", .{compile_elapsed});
        } else {
            term.dim("  compile: {} ms\n", .{compile_elapsed});
        }
    }
    return true;
}

fn shellContinuePrompt(depth: i32) void {
    if (term.color) {
        term.printRaw("\x1b[1;36midol\x1b[0m\x1b[2m·{}\x1b[0m ", .{depth + 1});
    } else {
        term.printRaw("idol·{} ", .{depth + 1});
    }
}

fn do_shell(alloc: std.mem.Allocator, io: Io, verbose: bool, backend_mode: []const u8) !void {
    term.banner("Idol compatibility shell");
    term.dim(":help · :export · ! = explicit raw host shell", .{});
    var session = try shell_session.newSession(alloc);
    defer session.deinit(alloc);
    var line: std.ArrayList(u8) = .empty;
    defer line.deinit(alloc);
    var block_depth: i32 = 0;
    var buf: [1024]u8 = undefined;

    // Print initial prompt
    if (term.color) {
        term.printRaw("\x1b[1;36midol\x1b[0m\x1b[2m>\x1b[0m ", .{});
    } else {
        term.printRaw("idol> ", .{});
    }
    while (true) {
        // std.posix.STDIN_FILENO is a comptime_int, which does not coerce to
        // Windows' *anyopaque fd_t; std.Io.File.stdin() picks the right handle
        // per OS and is already this file's idiom for stdout/stderr.
        const n = std.Io.File.stdin().readStreaming(io, &.{buf[0..]}) catch |err| switch (err) {
            error.EndOfStream => 0,
            else => return err,
        };
        if (n == 0) {
            // EOF - run any remaining line
            if (line.items.len > 0) {
                _ = try run_shell_line(alloc, io, line.items, &session, verbose, backend_mode);
            }
            break;
        }
        for (buf[0..n]) |b| {
            if (b == '\n') {
                // Check if we're in a multi-line block
                const line_text = std.mem.trim(u8, line.items, " \t\r\n");
                if (line_text.len > 0) {
                    // Parse to see if we need more lines
                    const new_depth = shellBlockDepth(line_text);
                    block_depth += new_depth;

                    if (block_depth > 0) {
                        // Continue collecting input
                        try line.append(alloc, b);
                        shellContinuePrompt(block_depth);
                    } else {
                        // Execute the complete block
                        _ = try run_shell_line(alloc, io, line.items, &session, verbose, backend_mode);
                        line.clearRetainingCapacity();
                        block_depth = 0;
                        // Print fresh prompt
                        if (term.color) {
                            term.printRaw("\x1b[1;36mduo\x1b[0m\x1b[2m>\x1b[0m ", .{});
                        } else {
                            term.printRaw("duo> ", .{});
                        }
                    }
                } else {
                    // Empty line resets block depth (can't happen mid-block normally)
                    block_depth = 0;
                    line.clearRetainingCapacity();
                    if (term.color) {
                        term.printRaw("\x1b[1;36mduo\x1b[0m\x1b[2m>\x1b[0m ", .{});
                    } else {
                        term.printRaw("duo> ", .{});
                    }
                }
            } else if (b != '\r') {
                try line.append(alloc, b);
            }
        }
    }
}

fn do_project_build(
    alloc: std.mem.Allocator,
    io: Io,
    requested: ?[]const u8,
    output_file: ?[]const u8,
    cc_arg: []const u8,
    opt_arg: []const u8,
    target_arg: []const u8,
    backend_mode: []const u8,
    verbose: bool,
    load_chunk_arg: bool,
    pgo_arg: bool,
    lib_mode_arg: bool,
    shared_mem_arg: bool,
    link_flags_arg: []const []const u8,
    run_after: bool,
) !void {
    const t = try readBuildTarget(alloc, io, requested, null);
    switch (t.kind) {
        .command => {
            const command = t.command orelse {
                term.err("command target '{s}' requires command = \"...\" or cmd = \"...\"", .{t.name});
                std.process.exit(1);
            };
            try run_build_command(io, t.name, command);
            return;
        },
        .clean => {
            try do_project_clean(io);
            return;
        },
        .fmt => {
            try do_project_fmt(alloc, io, t);
            return;
        },
        .check => {
            try do_project_check(alloc, io, t);
            return;
        },
        else => {},
    }
    try do_project_build_one(alloc, io, t, output_file, cc_arg, opt_arg, target_arg, backend_mode, verbose, load_chunk_arg, pgo_arg, lib_mode_arg, shared_mem_arg, link_flags_arg, run_after);
}

fn do_project_build_one(
    alloc: std.mem.Allocator,
    io: Io,
    t: build_framework.Target,
    output_file: ?[]const u8,
    cc_arg: []const u8,
    opt_arg: []const u8,
    target_arg: []const u8,
    backend_mode: []const u8,
    verbose: bool,
    load_chunk_arg: bool,
    pgo_arg: bool,
    lib_mode_arg: bool,
    shared_mem_arg: bool,
    link_flags_arg: []const []const u8,
    run_after: bool,
) !void {
    if (t.kind == .command) {
        const command = t.command orelse {
            term.err("command target '{s}' requires command = \"...\" or cmd = \"...\"", .{t.name});
            std.process.exit(1);
        };
        try run_build_command(io, t.name, command);
        return;
    }
    const src = t.src orelse {
        term.err("target '{s}' requires src = \"...\"", .{t.name});
        std.process.exit(1);
    };
    const target = t.target orelse target_arg;
    const target_lib_mode = lib_mode_arg or t.lib_mode;
    if (run_after and target_lib_mode) {
        term.err("target '{s}' is a library and cannot be run", .{t.name});
        std.process.exit(1);
    }
    const out = output_file orelse t.out orelse out: {
        const stem = std.fs.path.stem(src);
        if (std.mem.eql(u8, target, "wasm32-wasi")) break :out try std.fmt.allocPrint(alloc, "zig-out/bin/{s}.wasm", .{stem});
        break :out try std.fmt.allocPrint(alloc, "zig-out/bin/{s}", .{stem});
    };
    term.banner("duo build");
    if (term.build_report != .plain) {
        term.buildTargetCard(t.name, src, build_framework.kindLabel(t.kind));
    }
    term.kv("target", t.name);
    term.kv("source", src);
    term.kv("output", out);
    if (t.stage_name) |stage| term.kv("stage", stage);
    term.kv("report", @tagName(term.build_report));
    if (term.trace) term.traceStep("resolving @build target", .{});
    try ensureDirForPath(io, out);
    const merged_link = if (t.link.len > 0) blk: {
        var m: std.ArrayList([]const u8) = .empty;
        try m.appendSlice(alloc, link_flags_arg);
        try m.appendSlice(alloc, t.link);
        break :blk m.items;
    } else link_flags_arg;
    try do_compile(
        alloc,
        io,
        src,
        out,
        t.cc orelse cc_arg,
        t.opt orelse opt_arg,
        target,
        backend_mode,
        run_after,
        false,
        verbose,
        load_chunk_arg or t.load_chunk,
        pgo_arg or t.pgo,
        target_lib_mode,
        shared_mem_arg or t.shared_mem,
        t.test_mode(),
        t.bench_mode(),
        null,
        merged_link,
        null,
    );
    if (t.test_mode() and !run_after) {
        _ = try run_pretty_test_runner(alloc, io, out, false);
    } else if (t.bench_mode() and !run_after) {
        _ = try run_pretty_test_runner(alloc, io, out, true);
    }
}

const ParsedModule = struct {
    mod: ast.Module,
    sem: Sema,
};

fn module_has_macro_syntax(mod: *const ast.Module) bool {
    return block_has_macro_syntax(mod.body);
}

fn block_has_macro_syntax(block: ast.Block) bool {
    if (block.tail_expr) |expr| {
        if (expr_has_macro_syntax(expr)) return true;
    }
    for (block.stmts) |*stmt| {
        if (stmt_has_macro_syntax(stmt)) return true;
    }
    return false;
}

fn stmt_has_macro_syntax(stmt: *const ast.Stmt) bool {
    return switch (stmt.*) {
        .local_decl => |ld| expr_slice_has_macro_syntax(ld.inits),
        .const_decl => |cd| expr_has_macro_syntax(cd.val),
        .global_decl => |gd| expr_slice_has_macro_syntax(gd.inits),
        .assign => |as| expr_slice_has_macro_syntax(as.targets) or expr_slice_has_macro_syntax(as.values),
        .call_stmt => |cs| expr_has_macro_syntax(cs.expr),
        .expr_stmt => |es| expr_has_macro_syntax(es.expr),
        .do_block => |db| block_has_macro_syntax(db.body),
        .while_loop => |wl| expr_has_macro_syntax(wl.cond) or block_has_macro_syntax(wl.body),
        .repeat_loop => |rl| block_has_macro_syntax(rl.body) or expr_has_macro_syntax(rl.cond),
        .if_stmt => |is| blk: {
            if (expr_has_macro_syntax(is.cond) or block_has_macro_syntax(is.then)) break :blk true;
            for (is.elseifs) |elseif| {
                if (expr_has_macro_syntax(elseif.cond) or block_has_macro_syntax(elseif.body)) break :blk true;
            }
            if (is.else_body) |body| {
                if (block_has_macro_syntax(body)) break :blk true;
            }
            break :blk false;
        },
        .num_for => |nf| expr_has_macro_syntax(nf.start) or
            expr_has_macro_syntax(nf.stop) or
            (nf.step != null and expr_has_macro_syntax(nf.step.?)) or
            block_has_macro_syntax(nf.body),
        .gen_for => |gf| expr_slice_has_macro_syntax(gf.iters) or block_has_macro_syntax(gf.body),
        .func_decl => |fd| func_body_has_macro_syntax(fd.func),
        .ret => |r| expr_slice_has_macro_syntax(r.vals),
        .match_stmt => |ms| match_has_macro_syntax(ms),
        .try_stmt => |ts| try_stmt_has_macro_syntax(ts),
        .defer_stmt => |ds| block_has_macro_syntax(ds.body),
        .alias_def => |ad| alias_has_macro_syntax(ad),
        .macro_def => true,
        else => false,
    };
}

fn expr_slice_has_macro_syntax(exprs: []const *ast.Expr) bool {
    for (exprs) |expr| {
        if (expr_has_macro_syntax(expr)) return true;
    }
    return false;
}

fn expr_has_macro_syntax(expr: *const ast.Expr) bool {
    return switch (expr.*) {
        .index => |idx| expr_has_macro_syntax(idx.obj) or expr_has_macro_syntax(idx.key),
        .field => |field| expr_has_macro_syntax(field.obj),
        .call => |call| expr_has_macro_syntax(call.func) or expr_slice_has_macro_syntax(call.args),
        .method_call => |call| expr_has_macro_syntax(call.obj) or expr_slice_has_macro_syntax(call.args),
        .binop => |bin| expr_has_macro_syntax(bin.lhs) or expr_has_macro_syntax(bin.rhs),
        .unop => |un| expr_has_macro_syntax(un.operand),
        .func_expr => |func| func_body_has_macro_syntax(func.*),
        .table => |table| table_fields_have_macro_syntax(table.fields),
        .list_comp => |lc| expr_has_macro_syntax(lc.value) or
            expr_has_macro_syntax(lc.iter) or
            (lc.filter != null and expr_has_macro_syntax(lc.filter.?)),
        .try_expr => |try_expr| expr_has_macro_syntax(try_expr.operand),
        .unwrap_expr => |unwrap_expr| expr_has_macro_syntax(unwrap_expr.operand),
        .match_expr => |match| match_has_macro_syntax(match.*),
        .await_expr => |await_expr| expr_has_macro_syntax(await_expr.operand),
        .contains_expr => |contains| expr_has_macro_syntax(contains.lhs) or expr_has_macro_syntax(contains.rhs),
        .quote, .unquote, .macro_call => true,
        else => false,
    };
}

fn table_fields_have_macro_syntax(fields: []const ast.TableField) bool {
    for (fields) |field| {
        switch (field) {
            .indexed => |indexed| {
                if (expr_has_macro_syntax(indexed.key) or expr_has_macro_syntax(indexed.val)) return true;
            },
            .named => |named| if (expr_has_macro_syntax(named.val)) return true,
            .positional => |expr| if (expr_has_macro_syntax(expr)) return true,
            .spread => |expr| if (expr_has_macro_syntax(expr)) return true,
            .semantic => |sm| if (expr_has_macro_syntax(sm.val)) return true,
        }
    }
    return false;
}

fn func_body_has_macro_syntax(func: ast.FuncBody) bool {
    for (func.params) |param| {
        if (param.default_val) |expr| {
            if (expr_has_macro_syntax(expr)) return true;
        }
    }
    return block_has_macro_syntax(func.body);
}

fn match_has_macro_syntax(match: ast.MatchExpr) bool {
    if (expr_has_macro_syntax(match.scrutinee)) return true;
    for (match.arms) |arm| {
        if (pattern_has_macro_syntax(arm.pattern)) return true;
        if (arm.guard) |guard| {
            if (expr_has_macro_syntax(guard)) return true;
        }
        if (block_has_macro_syntax(arm.body)) return true;
    }
    return false;
}

fn pattern_has_macro_syntax(pattern: ast.Pattern) bool {
    return switch (pattern) {
        .literal => |expr| expr_has_macro_syntax(expr),
        .variant => |variant| pattern_slice_has_macro_syntax(variant.payload orelse &.{}),
        .table_destr => |items| blk: {
            for (items) |item| {
                if (pattern_has_macro_syntax(item.pat)) break :blk true;
            }
            break :blk false;
        },
        .array_destr => |items| pattern_slice_has_macro_syntax(items),
        else => false,
    };
}

fn pattern_slice_has_macro_syntax(patterns: []const ast.Pattern) bool {
    for (patterns) |pattern| {
        if (pattern_has_macro_syntax(pattern)) return true;
    }
    return false;
}

fn try_stmt_has_macro_syntax(stmt: ast.TryStmt) bool {
    if (block_has_macro_syntax(stmt.body)) return true;
    for (stmt.catches) |catch_clause| {
        if (block_has_macro_syntax(catch_clause.body)) return true;
    }
    for (stmt.defers) |defer_stmt| {
        if (block_has_macro_syntax(defer_stmt.body)) return true;
    }
    return false;
}

fn alias_has_macro_syntax(alias: ast.AliasDef) bool {
    for (alias.fields) |field| {
        if (field.default_val) |expr| {
            if (expr_has_macro_syntax(expr)) return true;
        }
    }
    for (alias.methods) |method| {
        if (func_body_has_macro_syntax(method.func)) return true;
    }
    return false;
}

// ── Contract enforcement (GAP-091) ────────────────────────────────────────────
//
// WHY THIS LIVES HERE AND NOT IN THE EMITTER. `@noalloc` was checked in exactly
// one place: `codegen.zig`'s `guardNoAlloc`, which only fires while the C
// backend is writing the allocation. Measured 2026-08-09 on `canonical-to-relation`:
//
//     duo check   examples/noalloc_fail.id      -> exit 0
//     duo compile examples/noalloc_fail.id      -> exit 0   (default backend)
//     duo compile --backend=c  … noalloc_fail.id      -> exit 1   (the ONLY red)
//     duo explain examples/noalloc_fail.id      -> exit 0, with the
//                                                        rejection as JSON
//
// The default backend is `direct` (§0b: `--backend=direct` IS the path,
// not an alternative), and the direct backend never runs `emit_module`, so the
// guard was unreachable from the shipping default. A contract that only holds on
// the oracle path is decorative — a user can write `@noalloc`, violate it and
// ship. The Zig test that asserted it (`error.NoAllocViolation` out of
// `explain_pipeline.runForProvenance`) called a pipeline no CLI verb reaches,
// so it was green in the suite and absent in the product for its whole life.
//
// A declared contract is a SEMANTIC fact about the graph, not a property of one
// emitter. Checking it in `parse_and_check` — the single funnel every verb goes
// through — is what makes `check`, `compile`, `run` and `explain` all agree
// without any of them knowing about a backend.
//
// SCOPE, stated so the next reader does not mistake narrowness for completeness:
// this scan is deliberately a SUBSET of `guardNoAlloc`'s sites. It reports the
// four `mem.*` intrinsics, which are unambiguous. It does NOT report
// `closure.malloc` (codegen only allocates a closure that captures upvalues, and
// reproducing that decision here would reject closures the backend accepts) or
// `dense_table.alloc` (a sema-inferred representation choice, not a written
// allocation). Being strictly narrower means this can never reject a program the
// C backend accepts; the C path still catches the rest. A finding here is
// therefore always also a finding there.

/// Set by `do_explain` alone: diagnose the violation, finish the render, exit 1
/// at the end instead of at the scan.
var contract_defer_exit: bool = false;
var contract_violations: usize = 0;

/// `mem.alloc` / `std.mem.alloc` → "alloc". Mirrors `codegen.mem_intrinsic_name`
/// so the two agree on what counts as the intrinsic namespace.
fn contractMemIntrinsic(func: *const ast.Expr) ?[]const u8 {
    if (func.* != .field) return null;
    const f = func.field;
    if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "mem")) return f.field;
    if (f.obj.* == .field) {
        const inner = f.obj.field;
        if (inner.obj.* == .name and
            std.mem.eql(u8, inner.obj.name.ident, "std") and
            std.mem.eql(u8, inner.field, "mem")) return f.field;
    }
    return null;
}

/// The four `mem.*` entries `guardNoAlloc` guards, by name, in the same order
/// codegen tests them. Kept as one list so a future site is added once.
const NOALLOC_INTRINSICS = [_][]const u8{ "alloc", "calloc", "realloc", "dup" };

const ContractCtx = struct {
    noalloc: bool,
    pure: bool,
    fname: []const u8,
    globals: *const std.StringHashMapUnmanaged(void),
    /// Names bound inside the function (params, locals, loop variables). Added
    /// but never removed: over-approximating the scope errs toward NOT
    /// reporting, which is the safe direction for a new rejection.
    bound: *std.StringHashMapUnmanaged(void),
    alloc: std.mem.Allocator,
    findings: *usize,

    fn bind(self: *const ContractCtx, name: []const u8) void {
        _ = self.bound.put(self.alloc, name, {}) catch {};
    }

    fn isGlobal(self: *const ContractCtx, name: []const u8) bool {
        if (self.bound.contains(name)) return false;
        return self.globals.contains(name);
    }

    fn report(self: *const ContractCtx, loc: ast.Loc, comptime what: []const u8, site: []const u8, blocker: []const u8) void {
        self.findings.* += 1;
        term.locErr(loc, what, .{ self.fname, site });
        for (repair_candidate.catalog) |row| {
            if (std.mem.eql(u8, row.blocker, blocker)) {
                term.hint("{s} [{s}]", .{ row.summary, row.kind.name() });
            }
        }
    }
};

fn contractWalkBlock(ctx: *ContractCtx, blk: ast.Block) void {
    for (blk.stmts) |*s| contractWalkStmt(ctx, s);
    if (blk.tail_expr) |e| contractWalkExpr(ctx, e);
}

fn contractWalkStmt(ctx: *ContractCtx, s: *const ast.Stmt) void {
    switch (s.*) {
        .local_decl => |d| {
            for (d.inits) |e| contractWalkExpr(ctx, e);
            for (d.names) |n| ctx.bind(n.ident);
        },
        .const_decl => |d| {
            contractWalkExpr(ctx, d.val);
            ctx.bind(d.ident);
        },
        .global_decl => |d| {
            for (d.inits) |e| contractWalkExpr(ctx, e);
        },
        .assign => |d| {
            for (d.values) |e| contractWalkExpr(ctx, e);
            for (d.targets) |t| {
                // A WRITE to a module global is what `__attribute__((const))`
                // forbids outright; report it before walking the target as a
                // read, so one store is one finding.
                if (ctx.pure and t.* == .name and ctx.isGlobal(t.name.ident)) {
                    ctx.report(t.name.loc, "@pure violated in function '{s}': writes module state '{s}'", t.name.ident, "pure_module_state");
                } else contractWalkExpr(ctx, t);
            }
        },
        .call_stmt => |d| contractWalkExpr(ctx, d.expr),
        .expr_stmt => |d| contractWalkExpr(ctx, d.expr),
        .do_block => |d| contractWalkBlock(ctx, d.body),
        .while_loop => |d| {
            contractWalkExpr(ctx, d.cond);
            contractWalkBlock(ctx, d.body);
        },
        .repeat_loop => |d| {
            contractWalkBlock(ctx, d.body);
            contractWalkExpr(ctx, d.cond);
        },
        .if_stmt => |d| {
            if (d.binding) |b| {
                contractWalkExpr(ctx, b.expr);
                ctx.bind(b.name);
            }
            contractWalkExpr(ctx, d.cond);
            contractWalkBlock(ctx, d.then);
            for (d.elseifs) |ei| {
                contractWalkExpr(ctx, ei.cond);
                contractWalkBlock(ctx, ei.body);
            }
            if (d.else_body) |b| contractWalkBlock(ctx, b);
        },
        .num_for => |d| {
            contractWalkExpr(ctx, d.start);
            contractWalkExpr(ctx, d.stop);
            if (d.step) |e| contractWalkExpr(ctx, e);
            ctx.bind(d.var_name);
            contractWalkBlock(ctx, d.body);
        },
        .gen_for => |d| {
            for (d.iters) |e| contractWalkExpr(ctx, e);
            for (d.vars) |v| ctx.bind(v);
            contractWalkBlock(ctx, d.body);
        },
        // A nested declaration is a DIFFERENT function with its own attributes.
        // `contractScanModule` reaches it through its own walk; inheriting the
        // enclosing contract here would reject a body that never declared one.
        .func_decl => {},
        .ret => |d| for (d.vals) |e| contractWalkExpr(ctx, e),
        .match_stmt => |m| {
            contractWalkExpr(ctx, m.scrutinee);
            for (m.arms) |arm| {
                if (arm.guard) |g| contractWalkExpr(ctx, g);
                contractWalkBlock(ctx, arm.body);
            }
        },
        .try_stmt => |t| {
            contractWalkBlock(ctx, t.body);
            for (t.catches) |c| {
                if (c.binding) |b| ctx.bind(b);
                contractWalkBlock(ctx, c.body);
            }
            for (t.defers) |d| contractWalkBlock(ctx, d.body);
        },
        .defer_stmt => |d| contractWalkBlock(ctx, d.body),
        else => {},
    }
}

fn contractWalkExpr(ctx: *ContractCtx, e: *const ast.Expr) void {
    switch (e.*) {
        .call => |c| {
            if (ctx.noalloc) {
                // `f(type)(rest…)` curries; codegen flattens it before guarding,
                // so unwrap one level here for the same reason.
                const callee = if (c.func.* == .call) c.func.call.func else c.func;
                if (contractMemIntrinsic(callee)) |nm| {
                    for (NOALLOC_INTRINSICS) |bad| {
                        if (std.mem.eql(u8, nm, bad)) {
                            ctx.report(c.loc, "@noalloc violated in function '{s}': heap allocation at mem.{s}", nm, "noalloc_heap_alloc");
                            break;
                        }
                    }
                }
            }
            contractWalkExpr(ctx, c.func);
            for (c.args) |a| contractWalkExpr(ctx, a);
        },
        .name => |n| {
            if (ctx.pure and ctx.isGlobal(n.ident)) {
                ctx.report(n.loc, "@pure violated in function '{s}': reads module state '{s}'", n.ident, "pure_module_state");
            }
        },
        .method_call => |m| {
            contractWalkExpr(ctx, m.obj);
            for (m.args) |a| contractWalkExpr(ctx, a);
        },
        .index => |x| {
            contractWalkExpr(ctx, x.obj);
            contractWalkExpr(ctx, x.key);
        },
        .field => |x| contractWalkExpr(ctx, x.obj),
        .binop => |x| {
            contractWalkExpr(ctx, x.lhs);
            contractWalkExpr(ctx, x.rhs);
        },
        .unop => |x| contractWalkExpr(ctx, x.operand),
        .try_expr => |x| contractWalkExpr(ctx, x.operand),
        .unwrap_expr => |x| contractWalkExpr(ctx, x.operand),
        .await_expr => |x| contractWalkExpr(ctx, x.operand),
        .contains_expr => |x| {
            contractWalkExpr(ctx, x.lhs);
            contractWalkExpr(ctx, x.rhs);
        },
        .sequence => |x| for (x.exprs) |sub| contractWalkExpr(ctx, sub),
        .range => |x| {
            contractWalkExpr(ctx, x.start);
            contractWalkExpr(ctx, x.end);
            if (x.step) |st| contractWalkExpr(ctx, st);
        },
        .table => |t| for (t.fields) |f| switch (f) {
            .indexed => |x| {
                contractWalkExpr(ctx, x.key);
                contractWalkExpr(ctx, x.val);
            },
            .named => |x| contractWalkExpr(ctx, x.val),
            .positional => |x| contractWalkExpr(ctx, x),
            .spread => |x| contractWalkExpr(ctx, x),
            .semantic => |x| contractWalkExpr(ctx, x.val),
        },
        .if_expr => |ie| {
            contractWalkExpr(ctx, ie.cond);
            contractWalkExpr(ctx, ie.then_expr);
            contractWalkExpr(ctx, ie.else_expr);
        },
        .match_expr => |m| {
            contractWalkExpr(ctx, m.scrutinee);
            for (m.arms) |arm| {
                if (arm.guard) |g| contractWalkExpr(ctx, g);
                contractWalkBlock(ctx, arm.body);
            }
        },
        // A closure literal is its own function body. Not descended for the same
        // reason `.func_decl` is not: it does not carry the enclosing contract.
        .func_expr => {},
        else => {},
    }
}

fn contractScanFunc(
    alloc: std.mem.Allocator,
    globals: *const std.StringHashMapUnmanaged(void),
    name: []const u8,
    attrs: []const ast.Attribute,
    fb: *const ast.FuncBody,
    findings: *usize,
) void {
    const effects = semantic_algebra.effectSetFromAttributes(attrs);
    const noalloc = effects.contains(.noalloc);
    // `.pure` enters the set through exactly one door — `effectSetFromAttributes`
    // sets it only when `@pure` (in any of its `comp.`/`meta.`/`compile.`
    // spellings) was written — so membership IS the declaration. Reading the
    // attribute name again here would be a second spelling table to drift.
    const pure = effects.contains(.pure);
    if (!noalloc and !pure) return;

    var bound: std.StringHashMapUnmanaged(void) = .{};
    defer bound.deinit(alloc);
    for (fb.params) |p| _ = bound.put(alloc, p.name, {}) catch {};
    if (fb.vararg_name) |v| _ = bound.put(alloc, v, {}) catch {};

    var ctx = ContractCtx{
        .noalloc = noalloc,
        .pure = pure,
        .fname = name,
        .globals = globals,
        .bound = &bound,
        .alloc = alloc,
        .findings = findings,
    };
    contractWalkBlock(&ctx, fb.body);
}

fn contractScanBlock(
    alloc: std.mem.Allocator,
    globals: *const std.StringHashMapUnmanaged(void),
    blk: ast.Block,
    findings: *usize,
) void {
    for (blk.stmts) |*s| switch (s.*) {
        .func_decl => |fd| {
            const nm = if (fd.path.len > 0) fd.path[fd.path.len - 1] else "?";
            contractScanFunc(alloc, globals, nm, fd.attributes, &fd.func, findings);
            contractScanBlock(alloc, globals, fd.func.body, findings);
        },
        .alias_def => |ad| for (ad.methods) |m| {
            const nm = if (m.path.len > 0) m.path[m.path.len - 1] else "?";
            contractScanFunc(alloc, globals, nm, m.attributes, &m.func, findings);
        },
        .do_block => |d| contractScanBlock(alloc, globals, d.body, findings),
        else => {},
    };
}

/// Names bound at module scope by a binding statement — not by a `func_decl`,
/// because reading a sibling function is a call, not a read of state.
fn collectModuleBindings(alloc: std.mem.Allocator, blk: ast.Block, out: *std.StringHashMapUnmanaged(void)) void {
    for (blk.stmts) |s| switch (s) {
        .local_decl => |d| for (d.names) |n| {
            _ = out.put(alloc, n.ident, {}) catch {};
        },
        .global_decl => |d| for (d.names) |n| {
            _ = out.put(alloc, n.ident, {}) catch {};
        },
        .const_decl => |d| _ = out.put(alloc, d.ident, {}) catch {},
        else => {},
    };
}

/// Every module-scope name the module ever ASSIGNS to. Mutability is what makes
/// a read unsafe under `@pure`: codegen lowers `@pure` to
/// `__attribute__((const))`, which promises the C compiler the function reads
/// nothing but its arguments — so it may cache one call's result and reuse it.
/// Reading an immutable module binding cannot be observed that way; reading a
/// mutable one can, and does. See `contractScanModule`'s measurement.
fn collectAssignedNames(alloc: std.mem.Allocator, blk: ast.Block, out: *std.StringHashMapUnmanaged(void)) void {
    for (blk.stmts) |s| switch (s) {
        .assign => |d| {
            for (d.targets) |t| if (t.* == .name) {
                _ = out.put(alloc, t.name.ident, {}) catch {};
            };
        },
        .func_decl => |fd| collectAssignedNames(alloc, fd.func.body, out),
        .do_block => |d| collectAssignedNames(alloc, d.body, out),
        .while_loop => |d| collectAssignedNames(alloc, d.body, out),
        .repeat_loop => |d| collectAssignedNames(alloc, d.body, out),
        .if_stmt => |d| {
            collectAssignedNames(alloc, d.then, out);
            for (d.elseifs) |ei| collectAssignedNames(alloc, ei.body, out);
            if (d.else_body) |b| collectAssignedNames(alloc, b, out);
        },
        .num_for => |d| collectAssignedNames(alloc, d.body, out),
        .gen_for => |d| collectAssignedNames(alloc, d.body, out),
        .match_stmt => |m| for (m.arms) |arm| collectAssignedNames(alloc, arm.body, out),
        .try_stmt => |t| {
            collectAssignedNames(alloc, t.body, out);
            for (t.catches) |c| collectAssignedNames(alloc, c.body, out);
            for (t.defers) |d| collectAssignedNames(alloc, d.body, out);
        },
        .defer_stmt => |d| collectAssignedNames(alloc, d.body, out),
        .alias_def => |ad| for (ad.methods) |m| collectAssignedNames(alloc, m.func.body, out),
        else => {},
    };
}

/// Every declared contract in `mod`, checked against the body that declared it.
/// Returns the number of violations; the caller decides the exit.
///
/// `sem.module_globals` is deliberately NOT the oracle for module state. It is
/// filled from the Lua-mode "unknown identifier is a dynamic global" path, and
/// measured 2026-08-09 it was wrong in BOTH directions in Idol mode: it held
/// `mem` (the intrinsic namespace, not state) and it did not hold `seed` from
/// `seed: i64 = 7` at file scope, which Idol binds as a module local. The set is
/// therefore derived from the module's own top-level binding statements, which
/// is what "module state" means in Idol.
///
/// WHAT `@pure` COSTS TODAY, by value, measured before this check existed:
///
///     seed: i64 = 7
///     @pure
///     peek(x: i64): i64   seed + x
///     main: a = peek(1); seed = 100; b = peek(1); print(a); print(b)
///
/// printed `8` and `8`. The second call must answer 101. `@pure` lowered to
/// `__attribute__((const))` — an unchecked promise — and the C compiler cashed
/// it by reusing the first result. That is not a decorative contract; it is a
/// wrong answer, and it is why `@pure` is scanned here alongside `@noalloc`.
fn contractScanModule(alloc: std.mem.Allocator, mod: *const ast.Module, sem: *const Sema) usize {
    _ = sem;
    var bindings: std.StringHashMapUnmanaged(void) = .{};
    defer bindings.deinit(alloc);
    collectModuleBindings(alloc, mod.body, &bindings);

    var assigned: std.StringHashMapUnmanaged(void) = .{};
    defer assigned.deinit(alloc);
    collectAssignedNames(alloc, mod.body, &assigned);

    // Module state = bound at module scope AND assigned somewhere.
    var state: std.StringHashMapUnmanaged(void) = .{};
    defer state.deinit(alloc);
    var it = bindings.iterator();
    while (it.next()) |e| {
        if (assigned.contains(e.key_ptr.*)) _ = state.put(alloc, e.key_ptr.*, {}) catch {};
    }

    var findings: usize = 0;
    contractScanBlock(alloc, &state, mod.body, &findings);
    return findings;
}

/// SH-03 production dispatch. When the tokenize authority is Duo, lex the whole
/// source through `lib/compiler/lexer.id` and drive the parser from that
/// stream instead of the host scanner.
///
/// The body moved to `lexer_dispatch.route` so codegen's module-embed paths
/// route through the SAME entry. While it lived here as a private helper the
/// driver tokenized through Duo and codegen's embed paths did not, which meant
/// one compilation ran two scanners.
fn routeThroughDuoLexer(
    alloc: std.mem.Allocator,
    lex: *Lexer,
    src: []const u8,
    src_path: []const u8,
) !void {
    return lexer_dispatch.route(alloc, lex, src, src_path);
}

/// The 1-based `line`th line of `src`, without its terminator.
fn sourceLine(src: []const u8, line: u32) []const u8 {
    var n: u32 = 1;
    var start: usize = 0;
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        if (src[i] != '\n') continue;
        if (n == line) return src[start..i];
        n += 1;
        start = i + 1;
    }
    return if (n == line) src[start..] else "";
}

/// GAP-091 / H-8. A rejection from the Duo lexer used to escape `parse_and_check`
/// as a bare Zig error, so `duo explain` on a file the lexer refuses printed
/// `error: UnexpectedChar` — no file, no span, no repair — and, in a debug build,
/// a return trace. `law.output.total` says an emission is graph data rendered
/// through the role taxonomy; a bare error name is not even plain string with a
/// location.
///
/// `lexer_dispatch.route` already re-lexes on the cold path and leaves the
/// LINE in `lex.last_error_loc`. The column is derived here rather than plumbed
/// through the C ABI: adding a `duo_lexer_error_col` export would mean
/// regenerating the tracked `src/lexer_tokenize.c`, and the derivation is
/// exact for the class of byte that produces `UnexpectedChar` — a byte no token
/// can start with. When nothing on the line qualifies the caret stays at column
/// 1, which is where it was before, rather than pointing somewhere invented.
fn diagnoseLexRejection(lex: *const Lexer, src: []const u8, src_path: []const u8, e: anyerror) void {
    const line: u32 = if (lex.last_error_loc) |l| l.line else 1;
    const text = sourceLine(src, line);

    var col: u32 = 1;
    var offender: ?u8 = null;
    for (text, 0..) |c, i| {
        if (c >= 0x80) {
            col = @intCast(i + 1);
            offender = c;
            break;
        }
    }
    const loc = ast.Loc{ .file = src_path, .line = line, .col = col };

    switch (e) {
        error.UnterminatedString => {
            term.locErr(loc, "unterminated string literal", .{});
            term.hint("close the literal with a matching quote on this line, or use the offside string block for text that spans lines", .{});
        },
        error.UnterminatedLongString => {
            term.locErr(loc, "unterminated long string literal", .{});
            term.hint("close the long-string bracket, or use the offside string block", .{});
        },
        error.InvalidEscape => {
            term.locErr(loc, "invalid escape sequence in string literal", .{});
            term.hint("Idol escapes are \\n \\t \\r \\\\ \\\" \\' \\0 and \\x<hex>; a lone backslash is written \\\\", .{});
        },
        else => {
            const trimmed = std.mem.trimStart(u8, text, " \t");
            if (std.mem.startsWith(u8, trimmed, "//")) {
                // The GAP-090 trigger, by name. `//` is not a comment marker in
                // Idol — it lexes as an operator, so the rest of the line is read
                // as code and the first byte that cannot start a token is where
                // the lexer stops. The repair is the comment marker, not the byte.
                term.locErr(loc, "'//' does not begin a comment in Idol", .{});
                term.hint("a canonical Idol comment starts with `#`; `//` is the floor-division operator, so the rest of this line lexed as code", .{});
            } else if (offender) |b| {
                term.locErr(loc, "no token starts with byte 0x{x:0>2} — a non-ASCII character outside a string or a `#` comment", .{b});
                term.hint("move the text into a `#` comment or a string literal, or delete the character", .{});
            } else {
                term.locErr(loc, "the lexer refused this line ({s})", .{@errorName(e)});
                term.hint("run `idol fmt` on the file, or reduce the line until the rejected construct is isolated", .{});
            }
        },
    }
}

fn parse_and_check(alloc: std.mem.Allocator, io: Io, src_path: []const u8) !ParsedModule {
    const src = try read_source(alloc, io, src_path);
    term.setSource(src_path, src);

    const facts = lexer_bridge.sourceFacts(src_path);
    var lex = Lexer.initFacts(src, src_path, facts);
    routeThroughDuoLexer(alloc, &lex, src, src_path) catch |e| {
        diagnoseLexRejection(&lex, src, src_path, e);
        std.process.exit(1);
    };
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = lex.family == lexer_bridge.family_canon;
    var mod = parser.parse_module() catch |e| {
        // Parser already emitted a source-span diagnostic for token-edge
        // failures; never leak Zig enum names (docs/spec/diagnostics.md §2).
        if (e == error.ExpectedToken or e == error.UnexpectedToken) {
            std.process.exit(1);
        }
        if (lex.last_error_loc) |loc| {
            term.locErr(loc, "lexer failed with {s}", .{@errorName(e)});
        } else {
            term.err("parse failed: {s}", .{@errorName(e)});
        }
        std.process.exit(1);
    };

    var sem = Sema.init(alloc);
    sem.lua55_mode = lex.source_law == .lua;
    sem.idol_mode = lex.family == lexer_bridge.family_canon;
    sem.source_path = try alloc.dupe(u8, src_path);
    sem.hints_enabled = term.hints;
    sem.info_enabled = term.info;
    if (module_has_macro_syntax(&mod)) {
        var expander = MacroExpand.Expander.init(alloc);
        defer expander.deinit();
        expander.expandModule(&mod) catch |e| {
            term.err("macro expansion error: {s}", .{@errorName(e)});
            std.process.exit(1);
        };
    }
    sem.check_module(&mod) catch |e| {
        term.err("sema error: {}", .{e});
        std.process.exit(1);
    };
    if (sem.errors > 0) {
        term.err("{d} error(s)", .{sem.errors});
        std.process.exit(1);
    }
    // GAP-091. A declared contract is checked HERE, in the one funnel every verb
    // shares, so `check`, `compile`, `run` and `explain` all reject the same
    // program. It used to be checked only while the C backend was emitting, and
    // the default backend is `direct`, so the default path never checked at all.
    {
        const violations = contractScanModule(alloc, &mod, &sem);
        if (violations > 0) {
            term.err("{d} contract violation(s)", .{violations});
            // `explain` is the one verb that must still RENDER. Its whole job is
            // to project the graph, and the rejection plus its repair edges are
            // already part of that projection — cutting the render here would
            // trade one hole (silent acceptance) for another (a verb that
            // refuses to explain the thing it just diagnosed). It records the
            // count and exits 1 after the JSON. Every other verb stops now.
            if (contract_defer_exit) {
                contract_violations += violations;
            } else std.process.exit(1);
        }
    }
    if (graph_diag_enabled) {
        var graph = semantic_graph.SemanticGraph.init(alloc);
        defer graph.deinit();
        if (graph.liftModuleWithCheckedCalls(&mod, &sem, src_path)) |_| {
            graph.dumpSummary(io, std.Io.File.stderr(), src_path);
        } else |e| {
            term.dim("[duo graph] lift skipped: {s}", .{@errorName(e)});
        }
    }
    return .{ .mod = mod, .sem = sem };
}

fn run_child_process(io: Io, argv: []const []const u8, label: []const u8, quiet: bool) !void {
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .inherit,
        .stdout = if (quiet) .ignore else .inherit,
        // stderr is ALWAYS inherited, even when quiet. A toolchain child (cc,
        // the native linker) is silent on success, so this costs nothing there
        // — but discarding it left failures as a bare "native linker failed
        // (exit 1)" with no cause, which is what made the SH-03 native-path
        // failure undiagnosable.
        .stderr = .inherit,
    });
    const result = try child.wait(io);
    switch (result) {
        .exited => |code| if (code != 0) {
            term.err("{s} failed (exit {})", .{ label, code });
            std.process.exit(1);
        },
        else => {
            term.err("{s} terminated abnormally", .{label});
            std.process.exit(1);
        },
    }
}

fn link_native_object(
    alloc: std.mem.Allocator,
    io: Io,
    obj_path: []const u8,
    out_path: []const u8,
    cc: []const u8,
    link_flags: []const []const u8,
    quiet: bool,
    shared: bool,
    extra_sources: []const []const u8,
    entry_symbol: ?[]const u8,
) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(alloc);
    if (@import("builtin").os.tag == .macos and !macos_sdkroot_configured) {
        try argv.appendSlice(alloc, &.{ "xcrun", cc });
    } else {
        try argv.append(alloc, cc);
    }
    try argv.append(alloc, obj_path);
    for (extra_sources) |src| try argv.append(alloc, src);
    if (shared) {
        try argv.append(alloc, "-dynamiclib");
    } else if (entry_symbol) |sym| {
        if (!std.mem.eql(u8, sym, "main")) {
            const flag = try std.fmt.allocPrint(alloc, "-Wl,-e,_{s}", .{sym});
            try argv.append(alloc, flag);
        }
    }
    try argv.appendSlice(alloc, &.{ "-o", out_path, "-lm", "-Wl,-dead_strip" });
    for (link_flags) |lib| {
        try argv.append(alloc, try std.fmt.allocPrint(alloc, "-l{s}", .{lib}));
    }
    try run_child_process(io, argv.items, "native linker", quiet);
}

fn run_pretty_test_runner(alloc: std.mem.Allocator, io: Io, out_path: []const u8, bench_mode: bool) !u8 {
    if (term.testUsesStructuredOutput()) {
        const log_ns = Io.Timestamp.now(io, .awake).nanoseconds;
        const log_path = try std.fmt.allocPrint(alloc, "/tmp/duo_test_{x}.log", .{@as(u64, @intCast(log_ns))});
        defer alloc.free(log_path);
        const cmd = if (term.test_report == .json)
            try std.fmt.allocPrint(alloc, "{s} >/dev/null 2>{s}", .{ out_path, log_path })
        else
            try std.fmt.allocPrint(alloc, "{s} 2>{s}", .{ out_path, log_path });
        defer alloc.free(cmd);
        const argv = [_][]const u8{ "/bin/sh", "-c", cmd };
        var child = try std.process.spawn(io, .{
            .argv = &argv,
            .stdin = .inherit,
            .stdout = .inherit,
            .stderr = .inherit,
        });
        const wait_res = try child.wait(io);
        const exit_code: u8 = switch (wait_res) {
            .exited => |c| @truncate(c),
            else => 1,
        };
        term.testSessionBegin(bench_mode);
        const log_bytes = read_source(alloc, io, log_path) catch |e| {
            term.err("could not read test event log '{s}': {}", .{ log_path, e });
            term.testSessionEnd();
            return exit_code;
        };
        defer alloc.free(log_bytes);
        var start: usize = 0;
        for (log_bytes, 0..) |ch, i| {
            if (ch == '\n') {
                term.feedTestLine(std.mem.trim(u8, log_bytes[start..i], "\r"));
                start = i + 1;
            }
        }
        if (start < log_bytes.len) term.feedTestLine(std.mem.trim(u8, log_bytes[start..], "\r"));
        term.testSessionEnd();
        Io.Dir.deleteFileAbsolute(io, log_path) catch {};
        return exit_code;
    }

    const argv = [_][]const u8{out_path};
    var child = try std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const wait_res = try child.wait(io);
    return switch (wait_res) {
        .exited => |c| @truncate(c),
        else => 1,
    };
}

fn resolveCompileTarget(target_in: []const u8, emit: target_model.EmitKind) []const u8 {
    if (target_model.resolveTargetInput(target_in, emit)) |resolved| {
        if (resolved.toLegacyTargetName()) |legacy| return legacy;
        if (term.trace) {
            var triple_buf: [64]u8 = undefined;
            const triple_str = resolved.triple.formatTriple(&triple_buf);
            term.kv("structured_target", triple_str);
            term.kv("emit", resolved.emit.name());
        }
    }
    return target_in;
}

fn resolveCompileBackend(backend: []const u8, target_in: []const u8) []const u8 {
    const parsed = backend_identity.Backend.parse(backend) orelse {
        term.err("unknown --backend '{s}' (expected auto, c, direct, or native)", .{backend});
        std.process.exit(1);
    };
    switch (parsed) {
        .direct => return if (native_backend.isNativeMachineTarget(target_in)) target_in else "native-exe",
        .auto => return target_in,
        .c => {
            if (native_backend.isNativeMachineTarget(target_in)) {
                term.err("machine target '{s}' requires --backend=auto or --backend=direct (C emit is bootstrap-only)", .{target_in});
                std.process.exit(1);
            }
            return target_in;
        },
        .wasm => return target_in,
    }
}

fn wantsMachineLowering(backend_mode: []const u8, target: []const u8) bool {
    const parsed = backend_identity.Backend.parse(backend_mode) orelse return false;
    if (!parsed.prefersMachineCode()) return false;
    if (builtin.cpu.arch != .aarch64 or builtin.os.tag != .macos) return false;
    return std.mem.eql(u8, target, "native") or native_backend.isNativeMachineTarget(target);
}

fn machineTargetForBackend(target: []const u8) []const u8 {
    if (native_backend.isNativeMachineTarget(target)) return target;
    return "native-exe";
}

/// Emit a `req`'d module's C so the direct backend can link the symbols it
/// relocates against.
///
/// The direct backend lowers `E.emit_u32(...)` to a `bl` with a relocation
/// against the module's `@comp.c.export` symbol. Nothing in the program's own
/// object defines that symbol, so without this the link fails on undefined
/// `duo_*` names even though lowering fully succeeded. Mirrors `do_dump_c`, but
/// writes to a file and returns errors instead of exiting: a dependency that
/// cannot be lowered must not kill the build — it just leaves the link to fail
/// with an honest undefined symbol.
/// Absorb `req`-imported Duo modules into the program's OWN native object.
///
/// The prior cross-module story had exactly one shape: a module marked its
/// functions with `@comp.c.export`, `directLinkInputs` built a C object from
/// it, and the linker joined the two. A module written in plain canonical Duo
/// — no directives, which is what asks for — exported nothing, got no
/// object, and every call into it died in `patchCalls` as an undefined symbol.
/// `std.wasm.instruction` is the representative case: four accessors, all bare
/// declarations, all unreachable from native code.
///
/// The fix needs no new naming scheme, because one already lines up. A call
/// `T.count()` lowers to callee `"T.count"` (dnir_lower `lowerCall`), and a
/// declaration whose `path` is `["T", "count"]` exports as `"T.count"`
/// (`funcExportName`), which `shouldIncludeFuncDecl` already admits for any
/// non-method with `path.len >= 2`. Re-rooting each spliced declaration's path
/// under the alias therefore makes definition and call site agree by
/// construction — no mangling, and no change to the backend at all.
///
/// Deliberately conservative: anything this cannot prove safe leaves the module
/// unspliced, which restores the previous honest bail rather than risking a
/// wrong program.
///   * a module that DOES export C symbols is skipped — it supplies its own
///     object, and splicing it too would be a duplicate-symbol link error;
///   * a module top-level name that collides with one already in the program is
///     skipped, since the splice would otherwise silently change which
///     definition wins;
///   * only top-level `func_decl`, `const_decl` and non-`req` `global_decl`
///     come across. Statements with side effects at module scope are not
///     hoisted into a program that never asked to run them.
///
/// Intra-module calls need one rewrite: inside the module, `count()` calls

/// Does every module-scope name the spliced declarations READ come across with
/// them? The call closure picks the functions and a literal test picks the
/// bindings; this is the check that makes those two answer together, so a
/// reference cannot outlive its declaration into the emitted C.
///
/// `false` means "not provably self-contained", which includes "the walk met an
/// expression form it does not descend into". A splice that cannot be proved is
/// not taken, and an untaken splice is the honest undefined-symbol bail.
fn spliceIsSelfContained(
    alloc: std.mem.Allocator,
    src: *const ast.Module,
    spliced: []const ast.Stmt,
) bool {
    // What the splice binds. A spliced function's path was re-rooted to
    // `[alias, name]`, so `topLevelName` — which wants `path.len == 1` — does
    // not see it; ask for the last segment instead.
    var bound: std.StringHashMapUnmanaged(void) = .empty;
    defer bound.deinit(alloc);
    for (spliced) |st| {
        const name = switch (st) {
            .func_decl => |fd| if (fd.path.len == 0) continue else fd.path[fd.path.len - 1],
            else => topLevelName(st) orelse continue,
        };
        bound.put(alloc, name, {}) catch return false;
    }

    // What the spliced bodies read. Locals and parameters land in here too;
    // a module-scope name shadowed by one of them only costs a declined
    // splice, never a wrong program.
    var used: std.StringHashMapUnmanaged(void) = .empty;
    defer used.deinit(alloc);
    var scan = CallScan{
        .alias = null,
        .siblings = &empty_name_set,
        .out = &used,
        .alloc = alloc,
        .free = &used,
    };
    // EVERY spliced statement, not only the function bodies. The bindings used
    // to be scalar literals, which read nothing, so walking them would have
    // found nothing — and that is exactly why the omission was invisible. Now
    // that a table constructor comes across, the walk has to cover the form
    // that could carry a name, or the next widening inherits the same hole.
    for (spliced) |*st| {
        collectBareCallsInStmt(st, &scan) catch return false;
    }
    if (scan.blind) return false;

    for (src.body.stmts) |st| {
        const name = topLevelName(st) orelse continue;
        if (used.contains(name) and !bound.contains(name)) return false;
    }
    return true;
}

/// One AST walk, three questions, because they differ only in what counts as a
/// hit and duplicating a twenty-arm statement walker to ask the others is how
/// they drift apart later.
///
///   * `alias` set   — collect `<alias>.<field>(…)`: what the PROGRAM calls
///                     into a module, i.e. what a splice must supply.
///   * `alias` null  — collect bare calls naming a member of `siblings`: what
///                     a spliced function reaches for INSIDE its own module.
///   * `free` set    — collect every bare identifier read, which is how
///                     `spliceIsSelfContained` learns what a spliced body
///                     depends on.
const CallScan = struct {
    alias: ?[]const u8,
    siblings: *const std.StringHashMapUnmanaged(void),
    out: *std.StringHashMapUnmanaged(void),
    alloc: std.mem.Allocator,
    /// Non-null in free-name mode: every bare identifier the walk reads.
    free: ?*std.StringHashMapUnmanaged(void) = null,
    /// Set when the walk meets a node it does not descend into. A free-name
    /// scan that reports "nothing unbound" after skipping part of the body is
    /// exactly the asymmetry this check exists to catch, so it reports its own
    /// blind spots instead.
    blind: bool = false,

    fn hit(self: *const CallScan, c: anytype) std.mem.Allocator.Error!void {
        if (self.alias) |a| {
            const f = c.func;
            if (f.* != .field) return;
            if (f.field.obj.* != .name) return;
            if (!std.mem.eql(u8, f.field.obj.name.ident, a)) return;
            try self.out.put(self.alloc, f.field.field, {});
        } else {
            if (c.func.* != .name) return;
            if (!self.siblings.contains(c.func.name.ident)) return;
            try self.out.put(self.alloc, c.func.name.ident, {});
        }
    }
};

const empty_name_set: std.StringHashMapUnmanaged(void) = .empty;

/// Names called as `<alias>.<field>(…)` anywhere in the program.
fn collectDottedCallsInBlock(
    block: *const ast.Block,
    alias: []const u8,
    out: *std.StringHashMapUnmanaged(void),
    alloc: std.mem.Allocator,
) std.mem.Allocator.Error!void {
    var scan = CallScan{ .alias = alias, .siblings = &empty_name_set, .out = out, .alloc = alloc };
    try collectBareCallsInBlock2(block, &scan);
}

/// Bare calls inside a module that name one of the module's own functions.
fn collectBareCallsInBlock(
    block: *const ast.Block,
    siblings: *const std.StringHashMapUnmanaged(void),
    out: *std.StringHashMapUnmanaged(void),
    alloc: std.mem.Allocator,
) std.mem.Allocator.Error!void {
    var scan = CallScan{ .alias = null, .siblings = siblings, .out = out, .alloc = alloc };
    try collectBareCallsInBlock2(block, &scan);
}

fn collectBareCallsInBlock2(block: *const ast.Block, scan: *CallScan) std.mem.Allocator.Error!void {
    for (block.stmts) |*st| try collectBareCallsInStmt(st, scan);
    if (block.tail_expr) |te| try collectBareCallsInExpr(te, scan);
}

fn collectBareCallsInStmt(
    st: *const ast.Stmt,
    scan: *CallScan,
) std.mem.Allocator.Error!void {
    switch (st.*) {
        .local_decl => |d| for (d.inits) |e| try collectBareCallsInExpr(e, scan),
        .global_decl => |d| for (d.inits) |e| try collectBareCallsInExpr(e, scan),
        .const_decl => |d| try collectBareCallsInExpr(d.val, scan),
        .assign => |d| {
            for (d.targets) |e| try collectBareCallsInExpr(e, scan);
            for (d.values) |e| try collectBareCallsInExpr(e, scan);
        },
        .call_stmt => |d| try collectBareCallsInExpr(d.expr, scan),
        .expr_stmt => |d| try collectBareCallsInExpr(d.expr, scan),
        .do_block => |d| try collectBareCallsInBlock2(&d.body, scan),
        .while_loop => |d| {
            try collectBareCallsInExpr(d.cond, scan);
            try collectBareCallsInBlock2(&d.body, scan);
        },
        .repeat_loop => |d| {
            try collectBareCallsInBlock2(&d.body, scan);
            try collectBareCallsInExpr(d.cond, scan);
        },
        .if_stmt => |d| {
            if (d.binding) |b| try collectBareCallsInExpr(b.expr, scan);
            try collectBareCallsInExpr(d.cond, scan);
            try collectBareCallsInBlock2(&d.then, scan);
            for (d.elseifs) |ei| {
                try collectBareCallsInExpr(ei.cond, scan);
                try collectBareCallsInBlock2(&ei.body, scan);
            }
            if (d.else_body) |eb| try collectBareCallsInBlock2(&eb, scan);
        },
        .num_for => |d| {
            try collectBareCallsInExpr(d.start, scan);
            try collectBareCallsInExpr(d.stop, scan);
            if (d.step) |s| try collectBareCallsInExpr(s, scan);
            try collectBareCallsInBlock2(&d.body, scan);
        },
        .gen_for => |d| {
            for (d.iters) |e| try collectBareCallsInExpr(e, scan);
            try collectBareCallsInBlock2(&d.body, scan);
        },
        .ret => |d| for (d.vals) |e| try collectBareCallsInExpr(e, scan),
        .func_decl => |fd| try collectBareCallsInBlock2(&fd.func.body, scan),
        // Statements that hold no expression to walk.
        .brk, .cont, .goto_stmt, .label_stmt, .cinclude, .directive => {},
        // Everything else can hold a name this walk would not see.
        else => scan.blind = true,
    }
}

fn collectBareCallsInExpr(
    e: *const ast.Expr,
    scan: *CallScan,
) std.mem.Allocator.Error!void {
    switch (e.*) {
        .call => |c| {
            try scan.hit(c);
            try collectBareCallsInExpr(c.func, scan);
            for (c.args) |a| try collectBareCallsInExpr(a, scan);
        },
        .method_call => |mc| {
            try collectBareCallsInExpr(mc.obj, scan);
            for (mc.args) |a| try collectBareCallsInExpr(a, scan);
        },
        .binop => |b| {
            try collectBareCallsInExpr(b.lhs, scan);
            try collectBareCallsInExpr(b.rhs, scan);
        },
        .unop => |u| try collectBareCallsInExpr(u.operand, scan),
        .index => |ix| {
            try collectBareCallsInExpr(ix.obj, scan);
            try collectBareCallsInExpr(ix.key, scan);
        },
        .field => |f| try collectBareCallsInExpr(f.obj, scan),
        .name => |n| if (scan.free) |f| try f.put(scan.alloc, n.ident, {}),
        .table => |t| for (t.fields) |fl| switch (fl) {
            .indexed => |kv| {
                try collectBareCallsInExpr(kv.key, scan);
                try collectBareCallsInExpr(kv.val, scan);
            },
            .named => |kv| try collectBareCallsInExpr(kv.val, scan),
            .positional, .spread => |v| try collectBareCallsInExpr(v, scan),
            .semantic => |s| try collectBareCallsInExpr(s.val, scan),
        },
        .func_expr => |fb| try collectBareCallsInBlock2(&fb.body, scan),
        .if_expr => |ie| {
            try collectBareCallsInExpr(ie.cond, scan);
            try collectBareCallsInExpr(ie.then_expr, scan);
            try collectBareCallsInExpr(ie.else_expr, scan);
        },
        .range => |r| {
            try collectBareCallsInExpr(r.start, scan);
            try collectBareCallsInExpr(r.end, scan);
            if (r.step) |s| try collectBareCallsInExpr(s, scan);
        },
        .contains_expr => |c| {
            try collectBareCallsInExpr(c.lhs, scan);
            try collectBareCallsInExpr(c.rhs, scan);
        },
        .try_expr => |x| try collectBareCallsInExpr(x.operand, scan),
        .unwrap_expr => |x| try collectBareCallsInExpr(x.operand, scan),
        .await_expr => |x| try collectBareCallsInExpr(x.operand, scan),
        .sequence => |s| for (s.exprs) |x| try collectBareCallsInExpr(x, scan),
        // Leaves that carry no identifier.
        .nil, .true_lit, .false_lit, .vararg, .semantic_scope => {},
        .int_lit, .float_lit, .string_lit, .semantic => {},
        // Everything else can hold a name this walk would not see. Saying so
        // is what lets the free-name check decline instead of guessing.
        else => scan.blind = true,
    }
}

/// A literal is a definition with no side effect, so hoisting it into the
/// program that spliced the module cannot change what the program does.
///
/// A TABLE OF LITERALS is one too, and it is the class the splice used to
/// decline. `lib/wasm/opcodes.id` opens with `TYPES = { "i32", … }` and
/// every function in the file indexes it; `opcode_lookup.id` is 63 rows of the
/// same shape. Neither could ever be absorbed, so a program calling one lost
/// the whole native path over a constant array. Two properties make hoisting it
/// as safe as hoisting `4`:
///
///   * every element is itself literal, so the constructor READS NO NAME. That
///     matters beyond side effects: a free name hiding in a hoisted binding
///     would be a use whose declaration never came across — exactly the defect
///     `spliceIsSelfContained` exists to stop. Requiring literal elements means
///     there is nothing left to check.
///   * the constructor allocates, but it allocated once at module scope in the
///     source module too, and the spliced binding runs in the same position.
///
/// `spread` and `semantic` fields are refused: a spread names a table to expand
/// and a semantic field carries an annotation the splice does not reason about.
/// An unprovable case declines rather than guesses.
fn exprIsLiteral(e: *const ast.Expr) bool {
    return switch (e.*) {
        .int_lit, .float_lit, .string_lit, .true_lit, .false_lit => true,
        .unop => |u| u.operand.* == .int_lit or u.operand.* == .float_lit,
        .table => |t| {
            for (t.fields) |f| switch (f) {
                .positional => |v| if (!exprIsLiteral(v)) return false,
                .named => |kv| if (!exprIsLiteral(kv.val)) return false,
                .indexed => |kv| if (!exprIsLiteral(kv.key) or !exprIsLiteral(kv.val)) return false,
                .spread, .semantic => return false,
            };
            return true;
        },
        else => false,
    };
}

fn allInitsAreLiteral(inits: []const *ast.Expr) bool {
    if (inits.len == 0) return false;
    for (inits) |e| {
        if (!exprIsLiteral(e)) return false;
    }
    return true;
}

fn anyInitIsReq(inits: []const *ast.Expr) bool {
    for (inits) |e| {
        if (reqPathOfExpr(e) != null) return true;
    }
    return false;
}

fn allTargetsArePlainNames(targets: []const *ast.Expr) bool {
    if (targets.len == 0) return false;
    for (targets) |t| {
        if (t.* != .name) return false;
    }
    return true;
}

fn reqPathOfExpr(e: *const ast.Expr) ?[]const u8 {
    if (e.* != .call) return null;
    const c = e.call;
    if (c.func.* != .name or !std.mem.eql(u8, c.func.name.ident, "req")) return null;
    if (c.args.len != 1 or c.args[0].* != .string_lit) return null;
    return c.args[0].string_lit.val;
}

fn topLevelName(st: ast.Stmt) ?[]const u8 {
    return switch (st) {
        .func_decl => |fd| if (fd.path.len == 1) fd.path[0] else null,
        .const_decl => |cd| cd.ident,
        .global_decl => |gd| if (gd.names.len == 1) gd.names[0].ident else null,
        .local_decl => |ld| if (ld.names.len == 1) ld.names[0].ident else null,
        // The bare `X = 4` binding form. Without this row it was invisible to
        // the collision check, so a spliced module could shadow a program's own
        // constant of the same name and quietly win.
        .assign => |as| if (as.targets.len == 1 and as.targets[0].* == .name)
            as.targets[0].name.ident
        else
            null,
        else => null,
    };
}

fn collectTopLevelNames(
    alloc: std.mem.Allocator,
    st: ast.Stmt,
    out: *std.StringHashMapUnmanaged(void),
) !void {
    if (topLevelName(st)) |n| try out.put(alloc, n, {});
}

/// Rewrite bare calls to a spliced sibling so they name the re-rooted symbol.
fn rerootCallsInBlock(
    block: *ast.Block,
    alias: []const u8,
    siblings: *const std.StringHashMapUnmanaged(void),
    alloc: std.mem.Allocator,
) std.mem.Allocator.Error!void {
    for (block.stmts) |*st| try rerootCallsInStmt(st, alias, siblings, alloc);
    if (block.tail_expr) |te| try rerootCallsInExpr(te, alias, siblings, alloc);
}

fn rerootCallsInStmt(
    st: *ast.Stmt,
    alias: []const u8,
    siblings: *const std.StringHashMapUnmanaged(void),
    alloc: std.mem.Allocator,
) std.mem.Allocator.Error!void {
    switch (st.*) {
        .local_decl => |*d| for (d.inits) |e| try rerootCallsInExpr(e, alias, siblings, alloc),
        .global_decl => |*d| for (d.inits) |e| try rerootCallsInExpr(e, alias, siblings, alloc),
        .const_decl => |*d| try rerootCallsInExpr(d.val, alias, siblings, alloc),
        .assign => |*d| {
            for (d.targets) |e| try rerootCallsInExpr(e, alias, siblings, alloc);
            for (d.values) |e| try rerootCallsInExpr(e, alias, siblings, alloc);
        },
        .call_stmt => |*d| try rerootCallsInExpr(d.expr, alias, siblings, alloc),
        .expr_stmt => |*d| try rerootCallsInExpr(d.expr, alias, siblings, alloc),
        .do_block => |*d| try rerootCallsInBlock(&d.body, alias, siblings, alloc),
        .while_loop => |*d| {
            try rerootCallsInExpr(d.cond, alias, siblings, alloc);
            try rerootCallsInBlock(&d.body, alias, siblings, alloc);
        },
        .repeat_loop => |*d| {
            try rerootCallsInBlock(&d.body, alias, siblings, alloc);
            try rerootCallsInExpr(d.cond, alias, siblings, alloc);
        },
        .if_stmt => |*d| {
            if (d.binding) |b| try rerootCallsInExpr(b.expr, alias, siblings, alloc);
            try rerootCallsInExpr(d.cond, alias, siblings, alloc);
            try rerootCallsInBlock(&d.then, alias, siblings, alloc);
            for (d.elseifs) |*ei| {
                try rerootCallsInExpr(ei.cond, alias, siblings, alloc);
                try rerootCallsInBlock(&ei.body, alias, siblings, alloc);
            }
            if (d.else_body) |*eb| try rerootCallsInBlock(eb, alias, siblings, alloc);
        },
        .num_for => |*d| {
            try rerootCallsInExpr(d.start, alias, siblings, alloc);
            try rerootCallsInExpr(d.stop, alias, siblings, alloc);
            if (d.step) |s| try rerootCallsInExpr(s, alias, siblings, alloc);
            try rerootCallsInBlock(&d.body, alias, siblings, alloc);
        },
        .gen_for => |*d| {
            for (d.iters) |e| try rerootCallsInExpr(e, alias, siblings, alloc);
            try rerootCallsInBlock(&d.body, alias, siblings, alloc);
        },
        .ret => |*d| for (d.vals) |e| try rerootCallsInExpr(e, alias, siblings, alloc),
        .func_decl => |*fd| try rerootCallsInBlock(&fd.func.body, alias, siblings, alloc),
        else => {},
    }
}

fn rerootCallsInExpr(
    e: *ast.Expr,
    alias: []const u8,
    siblings: *const std.StringHashMapUnmanaged(void),
    alloc: std.mem.Allocator,
) std.mem.Allocator.Error!void {
    switch (e.*) {
        .call => |*c| {
            if (c.func.* == .name and siblings.contains(c.func.name.ident)) {
                // Rewrite `double(x)` to the field access `T.double(x)` — the
                // exact shape `lowerCall` turns into callee `"T.double"`.
                const obj = try alloc.create(ast.Expr);
                obj.* = .{ .name = .{ .loc = c.func.name.loc, .ident = alias } };
                const fld = try alloc.create(ast.Expr);
                fld.* = .{ .field = .{
                    .loc = c.func.name.loc,
                    .obj = obj,
                    .field = c.func.name.ident,
                } };
                c.func = fld;
            } else {
                try rerootCallsInExpr(c.func, alias, siblings, alloc);
            }
            for (c.args) |a| try rerootCallsInExpr(a, alias, siblings, alloc);
        },
        .method_call => |*mc| {
            try rerootCallsInExpr(mc.obj, alias, siblings, alloc);
            for (mc.args) |a| try rerootCallsInExpr(a, alias, siblings, alloc);
        },
        .binop => |*b| {
            try rerootCallsInExpr(b.lhs, alias, siblings, alloc);
            try rerootCallsInExpr(b.rhs, alias, siblings, alloc);
        },
        .unop => |*u| try rerootCallsInExpr(u.operand, alias, siblings, alloc),
        .index => |*ix| {
            try rerootCallsInExpr(ix.obj, alias, siblings, alloc);
            try rerootCallsInExpr(ix.key, alias, siblings, alloc);
        },
        .field => |*f| try rerootCallsInExpr(f.obj, alias, siblings, alloc),
        else => {},
    }
}

/// `needs_runtime`, when non-null, receives the EMITTER'S OWN verdict on the C
/// it just wrote: false when the module lowered fully native (no `lua_*`), true
/// when any part of it went through the boxed runtime.
///
/// Asking the emitter rather than inspecting the text is the whole point. The
/// hazard this answers (gap[023]) is a native `main` linking a C-emitted module
/// object that expects a `package` nobody initialised, and the property that
/// decides it — "did this module emit runtime calls" — is a decision codegen
/// makes and records, not one a caller can re-derive from the source.
fn emitReqModuleC(
    alloc: std.mem.Allocator,
    io: Io,
    mod_src_path: []const u8,
    out_c_path: []const u8,
    target: []const u8,
    needs_runtime: ?*bool,
) !void {
    var ps = try parse_and_check(alloc, io, mod_src_path);
    defer ps.sem.deinit();

    var mono = Mono.Monomorphizer.init(alloc, &ps.sem.type_map);
    defer mono.deinit();
    try mono.run(&ps.mod);

    var arc_pass = Arc.ArcPass.init(alloc, &ps.sem.type_map);
    defer arc_pass.deinit();
    {
        var it = ps.sem.escape_names.iterator();
        while (it.next()) |entry| arc_pass.markEscaping(entry.key_ptr.*) catch {};
    }
    try arc_pass.run(&ps.mod);

    var async_pass = AsyncLower.AsyncLower.init(alloc, &ps.sem.type_map);
    defer async_pass.deinit();
    try async_pass.run(&ps.mod);

    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    var cg = CodeGen.init(alloc, io, &ps.sem.type_map, &ps.sem.module_globals, &aw.writer, ps.sem.next_closure_id, &ps.sem.table_field_types, &ps.sem.concepts);
    cg.table_methods = &ps.sem.table_methods;
    cg.mono = &mono;
    cg.arc = &arc_pass;
    cg.async_lower = &async_pass;
    cg.src_path = mod_src_path;
    cg.stdlib_root = compiler_lib_root;
    cg.target = target;
    cg.idol_mode = ps.sem.idol_mode;
    cg.foreign_records = &ps.sem.foreign_records;
    cg.foreign_functions = &ps.sem.foreign_functions;
    try cg.emit_module(&ps.mod);
    try aw.writer.flush();
    if (needs_runtime) |slot| slot.* = !cg.usesFullNativeLowering();

    try Io.Dir.writeFile(Io.Dir.cwd(), io, .{ .sub_path = out_c_path, .data = aw.written() });
}

/// Compile one `req`'d module's C to an object. Returns false when it does not
/// stand alone, so the caller can leave it out of the link. `-Dmain=` renames
/// the module's synthesized entry point: only the program's own object may
/// define `main`.
fn compileReqModuleObject(
    alloc: std.mem.Allocator,
    io: Io,
    cc: []const u8,
    c_path: []const u8,
    o_path: []const u8,
) bool {
    // Same `xcrun` guard as `link_native_object`: without it the macOS SDK
    // headers are not on the include path and every module fails on <stdio.h>.
    const launcher = if (@import("builtin").os.tag == .macos and !macos_sdkroot_configured) "xcrun " else "";
    const cmd = std.fmt.allocPrint(
        alloc,
        "{s}{s} -O2 -w -Dmain=duo_unused_module_main -c '{s}' -o '{s}' >/dev/null 2>&1",
        .{ launcher, cc, c_path, o_path },
    ) catch return false;
    defer alloc.free(cmd);
    const argv = [_][]const u8{ "/bin/sh", "-c", cmd };
    var child = std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return false;
    const res = child.wait(io) catch return false;
    return switch (res) {
        .exited => |c| c == 0,
        else => false,
    };
}

/// Link inputs for a direct-backend executable: the fixed C helper plus one C
/// file per `req`'d module that exports native symbols. `-Dmain=` renames each
/// module's synthesized entry point — only the program's own object may define
/// `main`, and the direct object is machine code, so the define cannot reach it.
/// `runtime_needing`, when non-null, is set to how many of the returned link
/// inputs are module objects whose C emit went through the Lua runtime. That
/// count — not the input count — is what a native `main` cannot host, because a
/// native main never runs `lua_package_init`. See the `too_many_modules` site.
fn boot(symbol: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, symbol, "duo_keyword_classify")) return "src/keyword_classify.c";
    if (std.mem.eql(u8, symbol, "idol_io_read_stdin") or
        std.mem.eql(u8, symbol, "idol_io_read_line") or
        std.mem.eql(u8, symbol, "idol_io_read_path") or
        std.mem.eql(u8, symbol, "idol_os_arg") or
        std.mem.eql(u8, symbol, "idol_os_cwd") or
        std.mem.eql(u8, symbol, "idol_os_execute") or
        std.mem.eql(u8, symbol, "idol_process_capture"))
        return "src/idol_io_bootstrap.c";
    if (std.mem.eql(u8, symbol, "duo_str_sub") or
        std.mem.eql(u8, symbol, "duo_str_to_i64") or
        std.mem.eql(u8, symbol, "idol_str_at") or
        std.mem.eql(u8, symbol, "idol_str_find") or
        std.mem.eql(u8, symbol, "idol_str_has") or
        std.mem.eql(u8, symbol, "idol_str_match"))
        return "src/idol_str_bootstrap.c";
    return null;
}

fn directLinkInputs(
    alloc: std.mem.Allocator,
    io: Io,
    mod: *const ast.Module,
    target: []const u8,
    cc: []const u8,
    runtime_needing: ?*usize,
    needed: []const []const u8,
) ![]const []const u8 {
    _ = cc;
    _ = target;
    _ = mod;
    if (runtime_needing) |slot| slot.* = 0;
    var inputs: std.ArrayListUnmanaged([]const u8) = .empty;
    var classify = false;
    var io_boot = false;
    var str_boot = false;
    for (needed) |symbol| {
        const source = boot(symbol) orelse continue;
        if (std.mem.eql(u8, source, "src/keyword_classify.c")) classify = true;
        if (std.mem.eql(u8, source, "src/idol_io_bootstrap.c")) io_boot = true;
        if (std.mem.eql(u8, source, "src/idol_str_bootstrap.c")) str_boot = true;
    }
    if (classify) {
        const classify_c = "src/keyword_classify.c";
        if (Io.Dir.cwd().statFile(io, classify_c, .{})) |_| {} else |_| {
            token_classify_gen.emitKeywordClassifyNativeCFile(alloc, io, classify_c) catch {};
        }
        try inputs.append(alloc, classify_c);
    }
    if (io_boot) try inputs.append(alloc, "src/idol_io_bootstrap.c");
    if (str_boot) try inputs.append(alloc, "src/idol_str_bootstrap.c");
    return inputs.toOwnedSlice(alloc);
}

fn reportDirectBackendError(
    io: Io,
    err: anyerror,
    target: []const u8,
    trace: ?*std.builtin.StackTrace,
    link_refusal: usize,
    diagnostic: *const native_backend.Diagnostic,
    native_scalar_precheck: *const CodeGen,
) void {
    var buf: [512]u8 = undefined;
    const msg = native_backend.describeCause(err, target, &buf, diagnostic);
    term.err("direct backend: {s}", .{msg});
    term.hint("{s}", .{native_backend.unsupportedReason(target)});
    // The error name is always reported. Lowering and machine evidence belong
    // to this exact attempt; the scalar precheck belongs to this compilation.
    term.hint("refused with: {s}", .{@errorName(err)});
    if (diagnostic.lowering.site) |at| {
        if (diagnostic.lowering.note()) |note| {
            term.hint("bail site: {s}() at {s}:{d} — {s}", .{ at.fn_name, at.file, at.line, note });
        } else {
            term.hint("bail site: {s}() at {s}:{d}", .{ at.fn_name, at.file, at.line });
        }
    } else {
        var rbuf: [64]u8 = undefined;
        if (native_scalar_precheck.nativeScalarReason(&rbuf)) |why| {
            term.hint("bail site: native-scalar precheck — {s}", .{why});
        } else if (link_refusal > 0) {
            term.hint("bail site: direct link — {d} linked module object(s) call the lua runtime", .{link_refusal});
        } else if (diagnostic.site) |at| {
            if (diagnostic.note()) |note| {
                term.hint("bail site: {s}() at {s}:{d} — {s}", .{ at.fn_name, at.file, at.line, note });
            } else {
                term.hint("bail site: {s}() at {s}:{d}", .{ at.fn_name, at.file, at.line });
            }
        }
    }
    if (std.c.getenv("DUO_DNIR_TRACE") != null) {
        if (trace) |st| {
            term.hint("DUO_DNIR_TRACE: lowering bailed at —", .{});
            std.debug.dumpErrorReturnTrace(st);
        }
    }
    _ = io;
}


/// law.md §40 build cache. A byte-identical source compiled by a byte-identical
/// compiler under identical settings yields a byte-identical artifact, so reuse
/// it rather than redoing the whole module. For a single-file compile the
/// semantic dependency set IS that file, so a content key is exact here — not the
/// "cache by source spelling" §40 warns against, which is about invalidating too
/// coarsely across a dependency graph.
///
/// FAIL-SAFE ON ERROR: every operation returns null/false on any error, so a
/// failure to cache falls through to a normal compile.
///
/// That is NOT the same as "can only make a build faster, never wrong", which is
/// what this comment used to claim, and the claim was false. Compilation outcome
/// is PATH-DEPENDENT — `native_bootstrap.gateTransport` waives graph-fact
/// validation for source under `gate/`, `scripts/ledger/` and a few named files
/// — while the key hashed only the source BYTES. So the same bytes compiled
/// first under `gate/` and then elsewhere hit the cache and were served a binary
/// that the second path's rules would have REFUSED. Measured, cold cache:
///
///     under gate/   ok compile        (validation waived)
///     outside       cached            (served the waived artifact)
///
/// A refusal turned into a running wrong answer, and `sh gate/all.sh` compiles
/// eleven files under `gate/`, so a gate run poisoned the shared /tmp cache for
/// every subsequent compile of the same bytes.
///
/// The fix hashes the TRANSPORT DECISION rather than the path. Hashing the path
/// would also work and is what one would reach for first, but it would miss on
/// every identical file in a different directory for no reason — the path is not
/// what varies, the rule set is. If another path-dependent rule is ever added it
/// must be hashed here too, which is why this is a named call and not a bool
/// literal.
fn buildCacheKey(
    alloc: std.mem.Allocator,
    io: Io,
    src_path: []const u8,
    target: []const u8,
    backend_mode: []const u8,
    opt: []const u8,
) ?[]u8 {
    const cwd = Io.Dir.cwd();
    const src = Io.Dir.readFileAlloc(cwd, io, src_path, alloc, .unlimited) catch return null;
    defer alloc.free(src);
    if (self_argv0.len == 0) return null;
    // Identify the compiler by size+mtime, NOT by hashing its bytes: it is a
    // ~15 MB binary, and reading it on every invocation cost more than the
    // compile the cache exists to avoid (measured: 159 ms -> 258 ms).
    const self_stat = Io.Dir.statFile(cwd, io, self_argv0, .{}) catch return null;
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update(src);
    h.update(target);
    h.update(backend_mode);
    h.update(opt);
    h.update(std.mem.asBytes(&self_stat.size));
    h.update(std.mem.asBytes(&self_stat.mtime));
    // The rule set this path compiles under. See the note above: without it the
    // cache serves a validation-waived artifact to a path that never waived it.
    const waived: u8 = if (native_bootstrap.gateTransport(src_path)) 1 else 0;
    h.update(std.mem.asBytes(&waived));
    var digest: [32]u8 = undefined;
    h.final(&digest);
    // Flat path: no directory to create, so one fewer failure mode.
    return std.fmt.allocPrint(alloc, "idol-cache-{s}", .{std.fmt.bytesToHex(digest, .lower)}) catch null;
}

fn buildCacheDir(io: Io) ?Io.Dir {
    // Open /tmp once as a Dir handle and address entries by BASENAME. The
    // relative readFileAlloc/writeFile entry points take a sub_path, so handing
    // them an absolute "/tmp/..." silently misbehaves — that is what made the
    // first version of this cache never store anything.
    return Io.Dir.openDirAbsolute(io, "/tmp", .{}) catch null;
}

fn buildCacheLoad(io: Io, cache_name: []const u8, out_path: []const u8, alloc: std.mem.Allocator) bool {
    var dir = buildCacheDir(io) orelse return false;
    defer dir.close(io);
    const bytes = Io.Dir.readFileAlloc(dir, io, cache_name, alloc, .unlimited) catch return false;
    defer alloc.free(bytes);
    const cwd = Io.Dir.cwd();

    // WRITE-THEN-RENAME, not write-in-place. Rewriting a Mach-O that was recently
    // executed invalidates its ad-hoc code signature, and the kernel then SIGKILLs
    // it — observed as an intermittent exit 137 from a cache hit. Renaming a fresh
    // file over the old one gives the replacement a new inode and a clean
    // validation, which is the standard fix for this on Apple Silicon.
    const tmp_path = std.fmt.allocPrint(alloc, "{s}.cachetmp", .{out_path}) catch return false;
    defer alloc.free(tmp_path);
    Io.Dir.writeFile(cwd, io, .{ .sub_path = tmp_path, .data = bytes }) catch return false;
    if (Io.Dir.openFile(cwd, io, tmp_path, .{})) |f| {
        defer f.close(io);
        f.setPermissions(io, .executable_file) catch {};
    } else |_| {}
    Io.Dir.rename(cwd, tmp_path, cwd, out_path, io) catch {
        Io.Dir.deleteFile(cwd, io, tmp_path) catch {};
        return false;
    };
    return true;
}

fn buildCacheStore(io: Io, cache_name: []const u8, out_path: []const u8, alloc: std.mem.Allocator) void {
    var dir = buildCacheDir(io) orelse return;
    defer dir.close(io);
    const cwd = Io.Dir.cwd();
    const bytes = Io.Dir.readFileAlloc(cwd, io, out_path, alloc, .unlimited) catch return;
    defer alloc.free(bytes);
    Io.Dir.writeFile(dir, io, .{ .sub_path = cache_name, .data = bytes }) catch return;
}

fn do_compile(
    alloc: std.mem.Allocator,
    io: Io,
    src_path: []const u8,
    out_path: []const u8,
    cc: []const u8,
    opt: []const u8,
    target: []const u8,
    backend_mode: []const u8,
    run_after: bool,
    check_only: bool,
    verbose: bool,
    load_chunk: bool,
    pgo: bool,
    lib_mode: bool,
    shared_mem: bool,
    test_mode: bool,
    bench_mode: bool,
    test_filter: ?[]const u8,
    link_flags: []const []const u8,
    entry_override: ?[]const u8,
) !void {
    const compile_started = Io.Timestamp.now(io, .awake);

    if (term.trace) {
        term.pipelineBegin("compile");
        term.kv("source", src_path);
        term.kv("output", out_path);
        term.kv("target", target);
        term.traceStep("parse + sema", .{});
    } else if (term.build_report != .plain and !test_mode) {
        term.buildPhaseStart("compile", src_path);
    }

    debug_trace.event(.build, .module, "compile {s} -> {s}", .{ src_path, out_path });

    // §40 build cache. Only for a plain executable compile: test/bench/pgo/lib
    // modes have side effects beyond the artifact, so they always rebuild.
    const cacheable = !check_only and !test_mode and !bench_mode and !pgo and
        !lib_mode and !load_chunk and std.mem.indexOf(u8, target, "wasm") == null;
    const cache_path: ?[]u8 = if (cacheable)
        buildCacheKey(alloc, io, src_path, target, backend_mode, opt)
    else
        null;
    if (cache_path) |cp| {
        if (buildCacheLoad(io, cp, out_path, alloc)) {
            if (term.build_report != .plain) term.ok("✓ {s} (cached)", .{out_path});
            if (run_after) {
                var run_args: std.ArrayList([]const u8) = .empty;
                defer run_args.deinit(alloc);
                try run_args.append(alloc, out_path);
                try run_args.appendSlice(alloc, forwarded_program_args);
                var run_child = try std.process.spawn(io, .{
                    .argv = run_args.items,
                    .stdin = .inherit,
                    .stdout = .inherit,
                    .stderr = .inherit,
                });
                switch (try run_child.wait(io)) {
                    .exited => |code| std.process.exit(code),
                    .signal => std.process.exit(128),
                    else => std.process.exit(1),
                }
            }
            return;
        }
    }

    var phase_timer = start_trace_timer(io);
    var ps = try parse_and_check(alloc, io, src_path);
    defer ps.sem.deinit();
    if (phase_timer) |*t| trace_phase(io, t, "parse + sema", null);
    debug_trace.event(.parse, .module, "parsed {s}", .{src_path});
    debug_trace.event(.sema, .module, "checked {s} ({d} test(s))", .{ src_path, ps.sem.test_entries.items.len });

    if (check_only) {
        if (ps.sem.warnings == 0 and ps.sem.hints == 0 and ps.sem.infos == 0) {
            term.ok("✓ checked — no errors", .{});
        } else {
            term.ok("✓ checked — {d} warning(s), {d} hint(s), {d} info(s)", .{
                ps.sem.warnings,
                ps.sem.hints,
                ps.sem.infos,
            });
        }
        return;
    }

    // APPLICATION-ONE (C0 §67): converge canonical `table(key)` onto the `[]`
    // table-access realization before the native suitability precheck, graph
    // lift, and native emit each walk the module — one bounded bridge, deleted
    // when the graph owns the `()` table-access application directly.
    table_apply.normalizeModule(alloc, &ps.mod, &ps.sem.type_map);

    var native_scalar_precheck = CodeGen.init(alloc, io, &ps.sem.type_map, &ps.sem.module_globals, undefined, ps.sem.next_closure_id, &ps.sem.table_field_types, &ps.sem.concepts);
    native_scalar_precheck.src_path = src_path;
    native_scalar_precheck.stdlib_root = compiler_lib_root;
    native_scalar_precheck.target = target;
    native_scalar_precheck.load_chunk = load_chunk;
    native_scalar_precheck.lib_mode = lib_mode;
    native_scalar_precheck.idol_mode = ps.sem.idol_mode;
    native_scalar_precheck.test_mode = test_mode;
    native_scalar_precheck.bench_mode = bench_mode;
    native_scalar_precheck.bench_backend = global_bench_backend;
    native_scalar_precheck.populate_alias_defs(&ps.mod) catch {};
    native_scalar_precheck.populate_record_aliases(&ps.mod) catch {};
    native_scalar_precheck.populate_enum_defs(&ps.mod) catch {};
    native_scalar_precheck.populate_func_bodies(&ps.mod) catch {};
    var link_refusal: usize = 0;
    const native_scalar_candidate = native_scalar_precheck.can_emit_native_scalar_module(&ps.mod);

    const selected_backend = backend_identity.Backend.parse(backend_mode) orelse {
        term.err("unknown --backend '{s}' (expected auto, c, direct, or native)", .{backend_mode});
        std.process.exit(1);
    };
    const effective_machine_target: ?[]const u8 = if (wantsMachineLowering(backend_mode, target))
        machineTargetForBackend(target)
    else
        null;

    if ((selected_backend == .auto or selected_backend == .direct) and effective_machine_target == null) {
        term.err("{s} backend has no native machine realization for target '{s}' on this host; explicitly select --backend=c or --backend=wasm if that realization is intended", .{ selected_backend.name(), target });
        std.process.exit(1);
    }

    if (effective_machine_target) |mt| {
        if (run_after and !native_backend.isNativeExecutableTarget(mt)) {
            term.err("only --target native-exe can run through the native machine-code backend", .{});
            std.process.exit(1);
        } else if (load_chunk or lib_mode or shared_mem or pgo) {
            term.err("native machine-code target does not use C-only compile options yet", .{});
            std.process.exit(1);
        } else if (!native_backend.isNativeExecutableTarget(mt) and !native_backend.isNativeSharedTarget(mt) and link_flags.len != 0) {
            term.err("native object/asm targets do not link libraries; use --target native-exe or native-dylib", .{});
            std.process.exit(1);
        } else {
            if (native_backend.isNativeExecutableTarget(mt)) {
                if (native_backend.abi(&ps.mod, entry_override)) |entry| {
                    // A NATIVE `main` DOES NOT INITIALISE THE LUA RUNTIME. The
                    // C backend's main opens with `package = lua_package_init()`;
                    // the direct backend emits no equivalent, and it cannot --
                    // lua_package_init is `static inline`, so there is no symbol
                    // for machine code to call.
                    //
                    // That is fine for a module that needs no runtime, and fatal
                    // for one that does. Measured: a program calling into
                    // lib/compiler/lexer.id linked and then SIGSEGV'd,
                    //
                    //     main -> duo_lexer_text_fingerprint -> next_tok
                    //          -> lua_require -> lua_table_get_raw_str_lit
                    //          -> KERN_INVALID_ADDRESS at 0x68
                    //
                    // because `next_tok` performs a runtime require and read the
                    // module registry out of a zeroed `package`. The callee is
                    // @c.export'd with a plain C ABI, so the direct backend
                    // happily emitted the call without knowing the callee needs
                    // a runtime nobody started.
                    //
                    // `native_scalar_candidate` is exactly the "runs without the
                    // Lua runtime" predicate, computed above and, until now,
                    // first consulted 160 lines BELOW this block -- so the
                    // machine-code path never asked. A refusal here is terminal;
                    // generated C is selected only by an explicit C request.
                    // `native_scalar_candidate` alone is NOT the predicate: it
                    // judges THIS module, and the module that needs the runtime
                    // is the CALLEE. Measured -- it is true for the program
                    // above, which still segfaulted.
                    //
                    // The honest signal is whether any Duo module object this
                    // native executable links CALLS THE RUNTIME. Not whether one
                    // exists -- see the `too_many_modules` note below, where
                    // counting them refused the supported case for two days --
                    // but whether its C emit went through `lua_*` at all.
                    // `directLinkInputs` asks the emitter that wrote each object
                    // and reports the count.
                    // Absorb plain-Duo `req` modules into this object BEFORE
                    // the link graph is measured. A module that splices in is
                    // no longer a link input, so doing this first is also what
                    // keeps the runtime-needing count from charging for
                    // dependencies that no longer need an object.
                    //
                    // THE SPLICE BELONGS TO THIS OBJECT AND NOTHING ELSE. It
                    // rewrites `ps.mod` in place, and `ps.mod` is also what the
                    // C emit below walks when this path declines — so a
                    // transform that exists only to feed the direct backend was
                    // deciding what the C backend compiled. When the direct
                    // backend then bailed, the spliced declarations survived as
                    // dead C nobody calls, and dead C still has to type-check:
                    // `instruction_descriptor_smoke` died on
                    // `return ((int64_t)lua_to_num(63))` in a spliced body whose
                    // constant had been hoisted to a boxed program global, and
                    // `wasm_opcode_projection_proof` on identifiers the splice
                    // never brought over. Both programs call the module's own
                    // C-emitted function; neither ever reaches the splice.
                    //
                    // So the restore below is the same rule as
                    // `spliceIsSelfContained`, applied one level out: the
                    // predicate that decides a declaration is emitted must be
                    // the one that decides its use is. No object, no splice.
                    const pre_splice_stmts = ps.mod.body.stmts;
                    const spliced: usize = 0;
                    if (spliced != 0 and term.trace) term.traceStep("req-splice", .{});
                    var runtime_needing_modules: usize = 0;
                    const runtime_linked_modules = try directLinkInputs(alloc, io, &ps.mod, mt, cc, &runtime_needing_modules, &.{});
                    // Three ways to end up here and only two of them had a
                    // reason attached. The precheck records its own, the
                    // backend now records its own, and this arm's SECOND
                    // condition — more than one runtime-linked module — was a
                    // silent third: a module that passes the precheck and would
                    // lower fine is refused for a link-graph property, and the
                    // DNB001 named nothing at all.
                    //
                    // COUNTING THE OBJECTS WAS THE WRONG QUESTION. `.len > 1`
                    // means "any Duo module object at all beyond the generated
                    // classifier", and that refused the one cross-module shape
                    // the direct backend was BUILT for: a module exporting C
                    // symbols, called through a `bl` with a relocation.
                    // `examples/duo_emit_machine_code.id` is that shape, and
                    // `zig build direct-module-link` — the gate whose entire
                    // job is to prove it — could not pass at all from the
                    // moment gap[023] landed until now, because `std.emit` is
                    // one object and one is already over the ceiling.
                    //
                    // The hazard gap[023] actually measured is narrower: a
                    // linked module object that CALLS THE RUNTIME (`lua_require`
                    // reading a zeroed `package`). `std.emit` emits no `lua_*`
                    // at all — its own header says so — so linking it into a
                    // native main is exactly as safe as the classifier.
                    // So ask the emitter which kind of object it wrote, and
                    // count only the ones that need a runtime nobody starts.
                    //
                    // THE OLD `.len > 1` STAYS AS A CONJUNCT, deliberately, so
                    // this change can only ever ACCEPT MORE. Dropping it cost
                    // three programs immediately — the M1 lexer proof,
                    // `native_only/lexer_native`, `native_only/parser_blocks` —
                    // and the reason is the `token/classify.id` swap in
                    // directLinkInputs: that module's object REPLACES the
                    // generated classifier at inputs[0], so the link line still
                    // has exactly one entry. Its C is 1774 `lua_*` calls, so the
                    // runtime-needing count says 1 and the object count says
                    // "no change from baseline". They disagree, the three
                    // programs have been shipping on the second answer, and
                    // deciding which is right is a question about that swap, not
                    // about this predicate. Keeping both conditions preserves
                    // the accepted set exactly and adds only the runtime-free
                    // objects — which is the whole intended change.
                    const too_many_modules = runtime_needing_modules > 0 and runtime_linked_modules.len > 1;
                    if (too_many_modules) link_refusal = runtime_needing_modules;
                    var direct_graph = semantic_graph.SemanticGraph.init(alloc);
                    defer direct_graph.deinit();
                    _ = try direct_graph.liftModuleWithCheckedCalls(&ps.mod, &ps.sem, src_path);
                    var native_diagnostic: native_backend.Diagnostic = .{};
                    if (!(native_scalar_candidate and !too_many_modules)) {
                        if (direct_graph.firstUnresolvedApplicationExcludingBootstrap(null)) |occurrence| {
                            native_diagnostic.bindOccurrence(&direct_graph, occurrence);
                        }
                        var reason_buf: [64]u8 = undefined;
                        if (native_scalar_precheck.nativeScalarReason(&reason_buf)) |why| {
                            native_diagnostic.remember(why);
                        } else if (too_many_modules) {
                            native_diagnostic.remember("runtime-linked-modules");
                        } else {
                            native_diagnostic.remember("native-scalar-precheck");
                        }
                    }
                    const artifact_result = if (native_scalar_candidate and !too_many_modules)
                        native_backend.emitObjectForExecutableWithGraphLineageObserved(alloc, &ps.mod, entry, &direct_graph, &native_diagnostic)
                    else
                        @as(@TypeOf(native_backend.emitObjectForExecutableWithGraphLineageObserved(alloc, &ps.mod, entry, &direct_graph, &native_diagnostic)), error.UnsupportedProgram);
                    if (artifact_result) |artifact_value| {
                        var artifact = artifact_value;
                        defer artifact.deinit(alloc);
                        const direct_extra = try directLinkInputs(alloc, io, &ps.mod, mt, cc, null, artifact.need);
                        const obj_path = try std.fmt.allocPrint(alloc, "/tmp/duo_{s}_native.o", .{std.fs.path.stem(src_path)});
                        const cwd = Io.Dir.cwd();
                        try Io.Dir.writeFile(cwd, io, .{ .sub_path = obj_path, .data = artifact.bytes });
                        if (emitDirectCompileProofArtifact(alloc, io, src_path, obj_path, mt)) {
                            if (term.trace) term.traceStep("direct-proof-artifact", .{});
                        } else |_| {}
                        try link_native_object(
                            alloc,
                            io,
                            obj_path,
                            out_path,
                            cc,
                            link_flags,
                            run_after and !verbose,
                            false,
                            direct_extra,
                            entry,
                        );
                        if (phase_timer) |*t| trace_phase(io, t, "native link", out_path);
                        if (term.build_report != .plain and !test_mode) {
                            const total_ms: u64 = @intCast(@divTrunc(compile_started.durationTo(Io.Timestamp.now(io, .awake)).nanoseconds, std.time.ns_per_ms));
                            term.buildPhaseDone("compile", total_ms, out_path);
                        }
                        if (!run_after and !(test_mode and term.test_report == .json)) term.ok("✓ {s}", .{out_path});
                        // The direct backend completes and exits HERE, never
                        // reaching the shared tail, so the cache store lives on
                        // this path too. (Placing it only at the tail made the
                        // cache silently inert for every native compile.)
                        if (cache_path) |cp| buildCacheStore(io, cp, out_path, alloc);
                        if (run_after) {
                            var run_args: std.ArrayList([]const u8) = .empty;
                            try run_args.append(alloc, out_path);
                            try run_args.appendSlice(alloc, forwarded_program_args);
                            defer run_args.deinit(alloc);
                            var run_child = try std.process.spawn(io, .{
                                .argv = run_args.items,
                                .stdin = .inherit,
                                .stdout = .inherit,
                                .stderr = .inherit,
                            });
                            const run_term = try run_child.wait(io);
                            switch (run_term) {
                                .exited => |code| std.process.exit(code),
                                .signal => std.process.exit(128),
                                else => {
                                    term.print("program terminated abnormally", .{});
                                    std.process.exit(1);
                                },
                            }
                        }
                        return;
                    } else |e| {
                        // No object: put the program back the way the C emit
                        // expects to find it.
                        if (spliced != 0) ps.mod.body.stmts = pre_splice_stmts;
                        reportDirectBackendError(io, e, mt, @errorReturnTrace(), link_refusal, &native_diagnostic, &native_scalar_precheck);
                        std.process.exit(1);
                    }
                } else {
                    if (entry_override) |name| {
                        term.err("--entry '{s}': no zero-arg i64/void/f64 function with that name", .{name});
                        std.process.exit(1);
                    } else {
                        term.err("no process: a file-scope tail is the program, or one zero-arg function, or --entry <name>", .{});
                        std.process.exit(1);
                    }
                }
            } else if (native_backend.isNativeSharedTarget(mt)) {
                var direct_graph = semantic_graph.SemanticGraph.init(alloc);
                defer direct_graph.deinit();
                _ = try direct_graph.liftModuleWithCheckedCalls(&ps.mod, &ps.sem, src_path);
                var native_diagnostic: native_backend.Diagnostic = .{};
                var artifact = native_backend.emitSharedObjectInputWithGraphLineageObserved(alloc, &ps.mod, &direct_graph, &native_diagnostic) catch |e| {
                    reportDirectBackendError(io, e, mt, @errorReturnTrace(), link_refusal, &native_diagnostic, &native_scalar_precheck);
                    std.process.exit(1);
                };
                defer artifact.deinit(alloc);
                const obj_path = try std.fmt.allocPrint(alloc, "/tmp/duo_{s}_native_dylib.o", .{std.fs.path.stem(src_path)});
                const cwd = Io.Dir.cwd();
                try Io.Dir.writeFile(cwd, io, .{ .sub_path = obj_path, .data = artifact.bytes });
                try link_native_object(alloc, io, obj_path, out_path, cc, link_flags, false, true, &.{}, null);
                if (phase_timer) |*t| trace_phase(io, t, "native dylib", out_path);
                if (term.build_report != .plain and !test_mode) {
                    const total_ms: u64 = @intCast(@divTrunc(compile_started.durationTo(Io.Timestamp.now(io, .awake)).nanoseconds, std.time.ns_per_ms));
                    term.buildPhaseDone("compile", total_ms, out_path);
                }
                if (!(test_mode and term.test_report == .json)) term.ok("✓ {s}", .{out_path});
                return;
            } else {
                var direct_graph = semantic_graph.SemanticGraph.init(alloc);
                defer direct_graph.deinit();
                _ = try direct_graph.liftModuleWithCheckedCalls(&ps.mod, &ps.sem, src_path);
                const cwd = Io.Dir.cwd();
                if (native_backend.isNativeAsmTarget(mt)) {
                    var native_diagnostic: native_backend.Diagnostic = .{};
                    var assembly = native_backend.emitAssemblyWithGraphLineageObserved(alloc, &ps.mod, mt, &direct_graph, &native_diagnostic) catch |e| {
                        reportDirectBackendError(io, e, mt, @errorReturnTrace(), link_refusal, &native_diagnostic, &native_scalar_precheck);
                        std.process.exit(1);
                    };
                    defer assembly.deinit(alloc);
                    try Io.Dir.writeFile(cwd, io, .{ .sub_path = out_path, .data = assembly.assembly });
                } else {
                    var native_diagnostic: native_backend.Diagnostic = .{};
                    var artifact = native_backend.emitObjectWithGraphLineageObserved(alloc, &ps.mod, mt, &direct_graph, &native_diagnostic) catch |e| {
                        reportDirectBackendError(io, e, mt, @errorReturnTrace(), link_refusal, &native_diagnostic, &native_scalar_precheck);
                        std.process.exit(1);
                    };
                    defer artifact.deinit(alloc);
                    try Io.Dir.writeFile(cwd, io, .{ .sub_path = out_path, .data = artifact.bytes });
                }
                if (phase_timer) |*t| trace_phase(io, t, "native object", out_path);
                if (term.build_report != .plain and !test_mode) {
                    const total_ms: u64 = @intCast(@divTrunc(compile_started.durationTo(Io.Timestamp.now(io, .awake)).nanoseconds, std.time.ns_per_ms));
                    term.buildPhaseDone("compile", total_ms, out_path);
                }
                if (!(test_mode and term.test_report == .json)) term.ok("✓ {s}", .{out_path});
                return;
            }
        }
    }

    if (native_backend.isNativeMachineTarget(target)) {
        term.err("machine target '{s}' requires --backend=auto or --backend=direct on this host", .{target});
        std.process.exit(1);
    }

    phase_timer = start_trace_timer(io);
    if (term.trace) term.traceStep("monomorphize", .{});
    // Monomorphization: expand generic functions into concrete specializations
    // before codegen (Task 8.3). Runs on every compile so generic instantiation
    // is exercised even before codegen consumes the specializations (Task 12.1).
    var mono: ?Mono.Monomorphizer = null;
    defer if (mono) |*m| m.deinit();
    if (!native_scalar_candidate) {
        mono = Mono.Monomorphizer.init(alloc, &ps.sem.type_map);
        mono.?.run(&ps.mod) catch |e| {
            term.err("monomorphization error: {}", .{e});
            std.process.exit(1);
        };
    }
    if (phase_timer) |*t| {
        const detail = if (native_scalar_candidate)
            try std.fmt.allocPrint(alloc, "skipped native-scalar", .{})
        else
            try std.fmt.allocPrint(alloc, "{d} specialization(s)", .{mono.?.count()});
        defer alloc.free(detail);
        trace_phase(io, t, "monomorphize", detail);
    }
    if (!native_scalar_candidate) debug_trace.event(.mono, .module, "{d} specialization(s)", .{mono.?.count()});

    phase_timer = start_trace_timer(io);
    if (term.trace) term.traceStep("ARC analysis", .{});
    // ARC insertion: decide retain/release/close points for heap values, after
    // monomorphization and before codegen (Task 9.4).
    var arc_pass: ?Arc.ArcPass = null;
    defer if (arc_pass) |*a| a.deinit();
    if (!native_scalar_candidate) {
        arc_pass = Arc.ArcPass.init(alloc, &ps.sem.type_map);
        // Populate escaping set from sema escape analysis.
        // Only variables captured by closures are marked as escaping.
        // All other locals are non-escaping and get ARC pruned.
        {
            var it = ps.sem.escape_names.iterator();
            while (it.next()) |entry| {
                arc_pass.?.markEscaping(entry.key_ptr.*) catch {};
            }
        }
        arc_pass.?.run(&ps.mod) catch |e| {
            term.err("ARC analysis error: {}", .{e});
            std.process.exit(1);
        };
    }
    if (phase_timer) |*t| {
        const detail = if (native_scalar_candidate)
            try std.fmt.allocPrint(alloc, "skipped native-scalar", .{})
        else
            try std.fmt.allocPrint(alloc, "{d} annotation(s)", .{arc_pass.?.annotations.items.len});
        defer alloc.free(detail);
        trace_phase(io, t, "ARC analysis", detail);
    }

    phase_timer = start_trace_timer(io);
    if (term.trace) term.traceStep("async lower", .{});
    // Async lowering: describe each `async` function as a state machine, after
    // ARC and before codegen (Task 10.3).
    const is_wasm_target = std.mem.eql(u8, target, "wasm32-wasi");
    // The threaded scheduler is selected by `--threads` / `@concurrent("threaded")`,
    // wired in Task 17.1; for now no threaded mode is requested here.
    const threaded = false;
    AsyncLower.validateTarget(is_wasm_target, threaded) catch {
        term.err("the threaded scheduler is not supported on the wasm32-wasi target", .{});
        std.process.exit(1);
    };
    var async_pass: ?AsyncLower.AsyncLower = null;
    defer if (async_pass) |*a| a.deinit();
    if (!native_scalar_candidate) {
        async_pass = AsyncLower.AsyncLower.init(alloc, &ps.sem.type_map);
        async_pass.?.run(&ps.mod) catch |e| {
            term.err("async lowering error: {}", .{e});
            std.process.exit(1);
        };
    }
    if (phase_timer) |*t| {
        const detail = if (native_scalar_candidate)
            try std.fmt.allocPrint(alloc, "skipped native-scalar", .{})
        else
            try std.fmt.allocPrint(alloc, "{d} async function(s)", .{async_pass.?.count()});
        defer alloc.free(detail);
        trace_phase(io, t, "async lower", detail);
    }

    const is_wasm = std.mem.eql(u8, target, "wasm32-wasi");

    const c_path = try std.fmt.allocPrint(alloc, "/tmp/duo_{s}.c", .{
        std.fs.path.stem(src_path),
    });

    phase_timer = start_trace_timer(io);
    if (term.trace) term.traceStep("codegen", .{});
    var full_native_lowering = false;
    const ml_kernels_sidecar = ml_sidecar: {
        const cwd = Io.Dir.cwd();
        const cf = try Io.Dir.createFile(cwd, io, c_path, .{});
        defer Io.File.close(cf, io);

        var buf: [65536]u8 = undefined;
        var fw: Io.File.Writer = .init(cf, io, &buf);
        var cg = CodeGen.init(alloc, io, &ps.sem.type_map, &ps.sem.module_globals, &fw.interface, ps.sem.next_closure_id, &ps.sem.table_field_types, &ps.sem.concepts);
        cg.table_methods = &ps.sem.table_methods;
        if (mono) |*m| cg.mono = m;
        if (arc_pass) |*a| cg.arc = a;
        if (async_pass) |*a| cg.async_lower = a;
        cg.src_path = src_path;
        cg.stdlib_root = compiler_lib_root;
        cg.target = target;
        cg.load_chunk = load_chunk;
        cg.lib_mode = lib_mode;
        cg.idol_mode = ps.sem.idol_mode;
        cg.test_mode = test_mode;
        cg.bench_mode = bench_mode;
        cg.bench_backend = global_bench_backend;
        cg.test_structured_output = test_mode and term.testUsesStructuredOutput();
        cg.test_filter = test_filter;
        cg.test_entries = ps.sem.test_entries.items;
        cg.foreign_records = &ps.sem.foreign_records;
        cg.foreign_functions = &ps.sem.foreign_functions;
        cg.emit_module(&ps.mod) catch |e| {
            if (e == error.NoAllocViolation) {
                if (cg.noallocViolationMessage()) |msg| term.err("{s}", .{msg});
                std.process.exit(1);
            }
            term.err("codegen error: {}", .{e});
            std.process.exit(1);
        };
        full_native_lowering = cg.usesFullNativeLowering();
        try fw.interface.flush();
        transform_engine.dumpProvenanceSummary(io, std.Io.File.stderr());
        break :ml_sidecar cg.ml_kernels_emitted;
    };
    if (phase_timer) |*t| trace_phase(io, t, "codegen", c_path);

    if (emitCompileProofArtifact(alloc, io, src_path, c_path, target, bench_mode, full_native_lowering, ps.sem.idol_mode)) {
        if (term.trace) term.traceStep("proof-artifact", .{});
    } else |_| {}

    const ml_c_path = if (ml_kernels_sidecar) blk: {
        const path = try std.fmt.allocPrint(alloc, "/tmp/duo_{s}_ml.c", .{
            std.fs.path.stem(src_path),
        });
        const cwd = Io.Dir.cwd();
        const mlf = try Io.Dir.createFile(cwd, io, path, .{});
        defer Io.File.close(mlf, io);
        var ml_buf: [65536]u8 = undefined;
        var ml_fw: Io.File.Writer = .init(mlf, io, &ml_buf);
        ml_kernels.writeTranslationUnit(alloc, &ml_fw.interface) catch |e| {
            term.err("failed to write ML kernel translation unit: {}", .{e});
            std.process.exit(1);
        };
        try ml_fw.interface.flush();
        break :blk path;
    } else null;

    // Build the base set of CC flags shared between all compile passes.
    var base_cc_flags = base: {
        var args: std.ArrayList([]const u8) = .empty;
        if (is_wasm) {
            try args.appendSlice(alloc, &.{
                "zig",                  "cc",
                "--target=wasm32-wasi", opt,
                "-ffast-math",          "-flto",
                "-fomit-frame-pointer", "-funroll-loops",
                "-ffp-contract=fast",   "-fno-trapping-math",
                "-fno-math-errno",      "-Wl,--gc-sections",
                "-Wl,--strip-debug",    "-std=gnu99",
                "-lm",                  "-Wno-deprecated-declarations",
            });
            if (lib_mode) {
                try args.appendSlice(alloc, &.{
                    "-mexec-model=reactor",
                    "-Wl,--no-entry",
                    "-Wl,--export-dynamic",
                });
            }
            if (shared_mem) {
                try args.appendSlice(alloc, &.{ "-matomics", "-mbulk-memory", "-mmutable-globals" });
            }
        } else {
            if (comptime @import("builtin").os.tag == .macos) {
                if (macos_sdkroot_configured) {
                    try args.append(alloc, cc);
                } else {
                    try args.appendSlice(alloc, &.{ "xcrun", cc });
                }
            } else {
                try args.append(alloc, cc);
            }
            try args.appendSlice(alloc, &.{
                opt,
                "-ffast-math",
                "-DNDEBUG",
                "-march=native",
                "-fomit-frame-pointer",
                "-ffp-contract=fast",
                "-fno-trapping-math",
                "-fno-math-errno",
            });
            if (!full_native_lowering) {
                try args.appendSlice(alloc, &.{
                    "-mtune=native",
                    "-fstrict-aliasing",
                    "-funroll-loops",
                    "-ffunction-sections",
                    "-fdata-sections",
                });
            } else {
                // For full native lowering, still enable key optimizations
                // that match the C reference compilation flags.
                try args.appendSlice(alloc, &.{
                    "-funroll-loops",
                });
            }
            try args.appendSlice(alloc, &.{
                "-Wl,-dead_strip",
                "-std=gnu99",
                "-lm",
            });
            if (!full_native_lowering) {
                try args.append(alloc, "-flto");
            } else {
                // Enable LTO for native modules to match C reference flags.
                try args.append(alloc, "-flto");
            }
            for (link_flags) |lib| {
                try args.append(alloc, try std.fmt.allocPrint(alloc, "-l{s}", .{lib}));
            }
            if (load_chunk or lib_mode) {
                try args.append(alloc, "-fPIC");
                if (@import("builtin").os.tag == .macos) {
                    try args.append(alloc, "-dynamiclib");
                } else {
                    try args.append(alloc, "-shared");
                }
            }
            if (!verbose) try args.append(alloc, "-w");
        }
        break :base args;
    };
    defer base_cc_flags.deinit(alloc);

    const silent = run_after and !verbose;
    phase_timer = start_trace_timer(io);
    if (term.trace) term.traceStep("link", .{});
    // PGO two-pass compile (skipped for wasm, load_chunk, or run_after).
    if (pgo and !is_wasm and !load_chunk) {
        const stem = std.fs.path.stem(src_path);
        const profraw_path = try std.fmt.allocPrint(alloc, "/tmp/duo_{s}.profraw", .{stem});
        const profdata_path = try std.fmt.allocPrint(alloc, "/tmp/duo_{s}.profdata", .{stem});
        const instr_out = try std.fmt.allocPrint(alloc, "/tmp/duo_{s}_instr.out", .{stem});

        // instrument.
        var p1_args: std.ArrayList([]const u8) = .empty;
        defer p1_args.deinit(alloc);
        try p1_args.appendSlice(alloc, base_cc_flags.items);
        try p1_args.appendSlice(alloc, &.{ "-fprofile-instr-generate", "-o", instr_out, c_path });
        if (ml_c_path) |ml| try p1_args.append(alloc, ml);
        try run_child_process(io, p1_args.items, "C compiler (PGO pass 1)", silent);

        // Run instrumented binary to collect profile via `env VAR=val binary`.
        const env_kv = try std.fmt.allocPrint(alloc, "LLVM_PROFILE_FILE={s}", .{profraw_path});
        const instr_run_argv = [_][]const u8{ "env", env_kv, instr_out };
        var instr_child = try std.process.spawn(io, .{
            .argv = &instr_run_argv,
            .stdin = .ignore,
            .stdout = .ignore,
            .stderr = .ignore,
        });
        _ = try instr_child.wait(io);

        // Merge profiles with xcrun llvm-profdata (or llvm-profdata if available).
        const profdata_argv = [_][]const u8{
            "xcrun", "llvm-profdata", "merge", "-output", profdata_path, profraw_path,
        };
        try run_child_process(io, &profdata_argv, "llvm-profdata merge", silent);

        // optimise with profile.
        var p2_args: std.ArrayList([]const u8) = .empty;
        defer p2_args.deinit(alloc);
        try p2_args.appendSlice(alloc, base_cc_flags.items);
        const use_flag = try std.fmt.allocPrint(alloc, "-fprofile-instr-use={s}", .{profdata_path});
        try p2_args.appendSlice(alloc, &.{ use_flag, "-o", out_path, c_path });
        if (ml_c_path) |ml| try p2_args.append(alloc, ml);
        try run_child_process(io, p2_args.items, "C compiler (PGO pass 2)", silent);
    } else {
        // Normal single-pass compile.
        var cc_args: std.ArrayList([]const u8) = .empty;
        defer cc_args.deinit(alloc);
        try cc_args.appendSlice(alloc, base_cc_flags.items);
        try cc_args.appendSlice(alloc, &.{ "-o", out_path, c_path });
        if (ml_c_path) |ml| try cc_args.append(alloc, ml);
        try run_child_process(io, cc_args.items, "C compiler", silent);
    }
    if (phase_timer) |*t| trace_phase(io, t, "link", out_path);

    if (term.trace) {
        const total_ms: u64 = @intCast(@divTrunc(compile_started.durationTo(Io.Timestamp.now(io, .awake)).nanoseconds, std.time.ns_per_ms));
        if (term.richPipeline()) {
            term.pipelineEnd(total_ms, out_path);
        } else {
            term.traceSummary("total", "{d} ms", .{total_ms});
        }
    } else if (term.build_report != .plain and !test_mode) {
        const total_ms: u64 = @intCast(@divTrunc(compile_started.durationTo(Io.Timestamp.now(io, .awake)).nanoseconds, std.time.ns_per_ms));
        term.buildPhaseDone("compile", total_ms, out_path);
    }

    if (!run_after and !(test_mode and term.test_report == .json)) {
        term.ok("✓ {s}", .{out_path});
    }

    if (cache_path) |cp| buildCacheStore(io, cp, out_path, alloc);

    if (run_after and !is_wasm) {
        if (test_mode) {
            const code = try run_pretty_test_runner(alloc, io, out_path, bench_mode);
            std.process.exit(code);
        }
        var run_args: std.ArrayList([]const u8) = .empty;
        try run_args.append(alloc, out_path);
        try run_args.appendSlice(alloc, forwarded_program_args);
        defer run_args.deinit(alloc);
        var run_child = try std.process.spawn(io, .{
            .argv = run_args.items,
            .stdin = .inherit,
            .stdout = .inherit,
            .stderr = .inherit,
        });
        const run_term = try run_child.wait(io);
        switch (run_term) {
            .exited => |code| std.process.exit(code),
            .signal => std.process.exit(128),
            else => {
                term.print("program terminated abnormally", .{});
                std.process.exit(1);
            },
        }
    }
}

fn do_completion(io: Io, args: []const [:0]const u8) !void {
    const shell = if (args.len > 0) args[0] else {
        term.err("completion requires a shell: bash, zsh, fish, or nu", .{});
        std.process.exit(2);
    };

    const script: []const u8 = if (std.mem.eql(u8, shell, "bash"))
        bash_completion
    else if (std.mem.eql(u8, shell, "zsh"))
        zsh_completion
    else if (std.mem.eql(u8, shell, "fish"))
        fish_completion
    else if (std.mem.eql(u8, shell, "nu") or std.mem.eql(u8, shell, "nushell"))
        nu_completion
    else {
        term.err("unsupported shell '{s}' (expected bash, zsh, fish, or nu)", .{shell});
        std.process.exit(2);
    };

    const stdout = Io.File.stdout();
    var buf: [8192]u8 = undefined;
    var fw: Io.File.Writer = .init(stdout, io, &buf);
    try fw.interface.writeAll(script);
    try fw.interface.flush();
}

const bash_completion =
    \\# bash completion for duo
    \\_duo()
    \\{
    \\    local cur prev
    \\    COMPREPLY=()
    \\    cur="${COMP_WORDS[COMP_CWORD]}"
    \\    prev="${COMP_WORDS[COMP_CWORD-1]}"
    \\
    \\    local commands="shell init build compile run check test bench prove dump-c completion help"
    \\    local options="-o -O0 -O1 -O2 -O3 --cc --target --load-chunk --lib --pgo --shared-memory --link --filter --trace --info --hints --plain-diagnostics --debug --debug-depth --test-report --build-report --no-color -v --verbose -h --help"
    \\    local shells="bash zsh fish nu"
    \\    local targets="native wasm32-wasi"
    \\
    \\    if [[ ${COMP_CWORD} -eq 1 ]]; then
    \\        COMPREPLY=( $(compgen -W "${commands}" -- "${cur}") )
    \\        return 0
    \\    fi
    \\
    \\    case "${prev}" in
    \\        completion) COMPREPLY=( $(compgen -W "${shells}" -- "${cur}") ); return 0 ;;
    \\        --target) COMPREPLY=( $(compgen -W "${targets}" -- "${cur}") ); return 0 ;;
    \\        --test-report|--build-report) COMPREPLY=( $(compgen -W "pretty compact verbose plain json" -- "${cur}") ); return 0 ;;
    \\        --cc|-o) return 0 ;;
    \\    esac
    \\
    \\    case "${COMP_WORDS[1]}" in
    \\        compile|run|check|test|bench|dump-c)
    \\            COMPREPLY=( $(compgen -f -X '!*.id' -- "${cur}") $(compgen -f -X '!*.lua' -- "${cur}") $(compgen -W "${options}" -- "${cur}") )
    \\            ;;
    \\        *)
    \\            COMPREPLY=( $(compgen -W "${options}" -- "${cur}") )
    \\            ;;
    \\    esac
    \\}
    \\complete -F _duo duo
    \\
;

const zsh_completion =
    \\#compdef duo
    \\_duo() {
    \\  local -a commands opts shells targets
    \\  commands=(
    \\    'shell:start the interactive Duo shell'
    \\    'init:create a new Duo project'
    \\    'build:build the default or named build.id target'
    \\    'compile:compile .id/.lua to a native binary'
    \\    'run:compile and run a file or build target'
    \\    'check:type-check only'
    \\    'test:run @test functions in a .id file'
    \\    'bench:run @bench functions only'
    \\    'prove:reproduce the seven release proofs'
    \\    'dump-c:print generated C'
    \\    'completion:generate shell completions'
    \\    'help:show help'
    \\  )
    \\  opts=(
    \\    '-o[output binary]:output:_files'
    \\    '(-O0 -O1 -O2 -O3)-O0[no optimization]'
    \\    '(-O0 -O1 -O2 -O3)-O1[basic optimization]'
    \\    '(-O0 -O1 -O2 -O3)-O2[standard optimization]'
    \\    '(-O0 -O1 -O2 -O3)-O3[aggressive optimization]'
    \\    '--cc[C compiler]:compiler:_command_names'
    \\    '--target[target triple]:(native wasm32-wasi)'
    \\    '--load-chunk[compile as shared library for load()]'
    \\    '--lib[compile as library]'
    \\    '--pgo[profile-guided optimization]'
    \\    '--shared-memory[enable WASM shared memory]'
    \\    '--link[link against C library]:library:'
    \\    '--filter[test name substring filter]:pattern:'
    \\    '--trace[show compiler pipeline steps]'
    \\    '--info[show informational compiler notes]'
    \\    '--hints[show compiler hints]'
    \\    '--plain-diagnostics[one-line diagnostics for LSP/CI]'
    \\    '--debug[enable all compiler debug channels]'
    \\    '--debug=[debug channels]:channels:(parse sema types codegen mono arc build test link)'
    \\    '--debug-depth[max debug nesting depth]:depth:'
    \\    '--test-report[test output style]:(pretty compact verbose plain json)'
    \\    '--build-report[build output style]:(pretty compact verbose plain json)'
    \\    '--no-color[disable ANSI styling]'
    \\    '(-v --verbose)'{-v,--verbose}'[show compiler warnings]'
    \\    '(-h --help)'{-h,--help}'[show help]'
    \\  )
    \\  if (( CURRENT == 2 )); then
    \\    _describe 'command' commands
    \\  else
    \\    case "${words[2]}" in
    \\      completion) _values 'shell' bash zsh fish nu ;;
    \\      compile|run|check|test|bench|dump-c) _arguments $opts '*:source:_files -g "*.(duo|lua)"' ;;
    \\      *) _arguments $opts ;;
    \\    esac
    \\  fi
    \\}
    \\_duo "$@"
    \\
;

const fish_completion =
    \\# fish completion for duo
    \\complete -c duo -f
    \\complete -c duo -n '__fish_use_subcommand' -a 'shell' -d 'Start the interactive Duo shell'
    \\complete -c duo -n '__fish_use_subcommand' -a 'init' -d 'Create a new Duo project'
    \\complete -c duo -n '__fish_use_subcommand' -a 'build' -d 'Build the default or named build.id target'
    \\complete -c duo -n '__fish_use_subcommand' -a 'compile' -d 'Compile .id/.lua to a native binary'
    \\complete -c duo -n '__fish_use_subcommand' -a 'run' -d 'Compile and run a file or build target'
    \\complete -c duo -n '__fish_use_subcommand' -a 'check' -d 'Type-check only'
    \\complete -c duo -n '__fish_use_subcommand' -a 'test' -d 'Run @test functions in a .id file'
    \\complete -c duo -n '__fish_use_subcommand' -a 'bench' -d 'Run @bench functions only'
    \\complete -c duo -n '__fish_use_subcommand' -a 'prove' -d 'Reproduce the seven release proofs'
    \\complete -c duo -n '__fish_use_subcommand' -a 'dump-c' -d 'Print generated C'
    \\complete -c duo -n '__fish_use_subcommand' -a 'symbols' -d 'Glanceable module symbol map'
    \\complete -c duo -n '__fish_use_subcommand' -a 'graph' -d 'Export semantic graph JSON'
    \\complete -c duo -n '__fish_use_subcommand' -a 'completion' -d 'Generate shell completions'
    \\complete -c duo -n '__fish_use_subcommand' -a 'help' -d 'Show help'
    \\complete -c duo -s o -r -d 'Output binary name'
    \\complete -c duo -l cc -r -d 'C compiler'
    \\complete -c duo -l target -x -a 'native wasm32-wasi' -d 'Compilation target'
    \\complete -c duo -l load-chunk -d 'Compile as shared library for load()'
    \\complete -c duo -l lib -d 'Compile as library'
    \\complete -c duo -l pgo -d 'Profile-guided optimization'
    \\complete -c duo -l shared-memory -d 'Enable WASM shared memory'
    \\complete -c duo -l link -r -d 'Link against C library'
    \\complete -c duo -l filter -r -d 'Run only tests whose name contains pattern'
    \\complete -c duo -l trace -d 'Show compiler pipeline steps'
    \\complete -c duo -l info -d 'Show informational compiler notes'
    \\complete -c duo -l hints -d 'Show compiler hints'
    \\complete -c duo -l plain-diagnostics -d 'One-line diagnostics for LSP/CI'
    \\complete -c duo -l debug -d 'Enable all compiler debug channels'
    \\complete -c duo -l debug-depth -r -d 'Max debug nesting depth'
    \\complete -c duo -l test-report -x -a 'pretty compact verbose plain json' -d 'Test output style'
    \\complete -c duo -l build-report -x -a 'pretty compact verbose plain json' -d 'Build output style'
    \\complete -c duo -l no-color -d 'Disable ANSI styling'
    \\complete -c duo -s v -l verbose -d 'Show compiler warnings'
    \\complete -c duo -s h -l help -d 'Show help'
    \\complete -c duo -n '__fish_seen_subcommand_from completion' -x -a 'bash zsh fish nu'
    \\
;

const nu_completion =
    \\# nushell completion for duo
    \\def "nu-complete duo commands" [] {
    \\  [shell init build compile run check test bench prove dump-c completion help]
    \\}
    \\def "nu-complete duo shells" [] {
    \\  [bash zsh fish nu]
    \\}
    \\def "nu-complete duo targets" [] {
    \\  [native wasm32-wasi]
    \\}
    \\export extern "duo" [
    \\  command?: string@"nu-complete duo commands"
    \\  arg?: string
    \\  -o: string
    \\  --cc: string
    \\  --target: string@"nu-complete duo targets"
    \\  --load-chunk
    \\  --lib
    \\  --pgo
    \\  --shared-memory
    \\  --link: string
    \\  --trace
    \\  --info
    \\  --hints
    \\  --plain-diagnostics
    \\  --debug
    \\  --debug-depth: int
    \\  --test-report: string
    \\  --build-report: string
    \\  --no-color
    \\  -v
    \\  --verbose
    \\  -h
    \\  --help
    \\]
    \\export extern "duo completion" [
    \\  shell: string@"nu-complete duo shells"
    \\]
    \\
;

fn do_dump_c(alloc: std.mem.Allocator, io: Io, src_path: []const u8, target: []const u8, lib_mode: bool) !void {
    var ps = try parse_and_check(alloc, io, src_path);
    defer ps.sem.deinit();

    var mono = Mono.Monomorphizer.init(alloc, &ps.sem.type_map);
    defer mono.deinit();
    mono.run(&ps.mod) catch |e| {
        term.err("monomorphization error: {}", .{e});
        std.process.exit(1);
    };

    var arc_pass = Arc.ArcPass.init(alloc, &ps.sem.type_map);
    defer arc_pass.deinit();
    {
        var it = ps.sem.escape_names.iterator();
        while (it.next()) |entry| {
            arc_pass.markEscaping(entry.key_ptr.*) catch {};
        }
    }
    arc_pass.run(&ps.mod) catch |e| {
        term.err("ARC analysis error: {}", .{e});
        std.process.exit(1);
    };

    const is_wasm_target = std.mem.eql(u8, target, "wasm32-wasi");
    const threaded = false;
    AsyncLower.validateTarget(is_wasm_target, threaded) catch {
        term.err("the threaded scheduler is not supported on the wasm32-wasi target", .{});
        std.process.exit(1);
    };
    var async_pass = AsyncLower.AsyncLower.init(alloc, &ps.sem.type_map);
    defer async_pass.deinit();
    async_pass.run(&ps.mod) catch |e| {
        term.err("async lowering error: {}", .{e});
        std.process.exit(1);
    };

    const stdout = Io.File.stdout();
    var buf: [65536]u8 = undefined;
    var fw: Io.File.Writer = .init(stdout, io, &buf);
    var cg = CodeGen.init(alloc, io, &ps.sem.type_map, &ps.sem.module_globals, &fw.interface, ps.sem.next_closure_id, &ps.sem.table_field_types, &ps.sem.concepts);
    cg.table_methods = &ps.sem.table_methods;
    cg.mono = &mono;
    cg.arc = &arc_pass;
    cg.async_lower = &async_pass;
    cg.src_path = src_path;
    cg.stdlib_root = compiler_lib_root;
    cg.target = target;
    cg.idol_mode = ps.sem.idol_mode;
    cg.lib_mode = lib_mode;
    cg.foreign_records = &ps.sem.foreign_records;
    cg.foreign_functions = &ps.sem.foreign_functions;
    cg.emit_module(&ps.mod) catch |e| {
        if (e == error.NoAllocViolation) {
            if (cg.noallocViolationMessage()) |msg| term.err("{s}", .{msg});
            std.process.exit(1);
        }
        term.err("codegen error: {}", .{e});
        std.process.exit(1);
    };
    try fw.interface.flush();
    transform_engine.dumpProvenanceSummary(io, std.Io.File.stderr());
}

fn do_fmt(alloc: std.mem.Allocator, io: Io, src_path: []const u8, canonical: bool) !void {
    const src = read_source(alloc, io, src_path) catch |err| {
        term.err("failed to read source file '{s}': {s}", .{ src_path, @errorName(err) });
        std.process.exit(1);
    };
    term.setSource(src_path, src);
    const facts = lexer_bridge.sourceFacts(src_path);
    var lex = Lexer.initFacts(src, src_path, facts);
    routeThroughDuoLexer(alloc, &lex, src, src_path) catch |e| {
        diagnoseLexRejection(&lex, src, src_path, e);
        std.process.exit(1);
    };
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = lex.family == lexer_bridge.family_canon;
    parser.formatting = true;
    const mod = parser.parse_module() catch |err| {
        if (lex.last_error_loc) |loc| {
            term.locErr(loc, "lexer failed with {s}", .{@errorName(err)});
        } else {
            term.err("failed to parse '{s}': {s}", .{ src_path, @errorName(err) });
        }
        std.process.exit(1);
    };

    // The comment tokens are still in the producer stream — the reader SKIPS
    // them, it does not drop them — so the formatter can preserve them without
    // trivia in the AST. Without this the formatter deletes every comment in
    // the file, including `# expect:` test directives, and `idol check` cannot
    // notice, so the obvious oracle passes a gutted file.
    var comments: std.ArrayList(pretty.SourceComment) = .empty;
    defer comments.deinit(alloc);
    if (lex.duo_tokens) |toks| {
        for (toks) |t| {
            switch (t.kind) {
                .comment, .compat_comment, .compat_long_comment => {
                    try comments.append(alloc, .{ .line = t.loc.line, .text = t.text });
                },
                else => {},
            }
        }
    }

    var buf: std.ArrayList(u8) = .empty;
    var pp = PrettyPrinter.init(alloc, &buf, .idol);
    pp.canonical = canonical and parser.idol_mode;
    pp.comments = comments.items;
    // The `#!` line is its OWN token identity, not a comment, so the loop above
    // never collects it and the formatter used to delete it outright. The lexer
    // already retained it; it just had nowhere to go.
    pp.shebang = lex.shebang;
    // Which lines are genuinely empty. Derived from the SOURCE, not inferred
    // from gaps between statement lines — see `blank_lines`.
    var blanks: std.ArrayList(u32) = .empty;
    defer blanks.deinit(alloc);
    {
        var line: u32 = 1;
        var it = std.mem.splitScalar(u8, src, '\n');
        while (it.next()) |ln| : (line += 1) {
            if (std.mem.trim(u8, ln, " \t\r").len == 0) try blanks.append(alloc, line);
        }
    }
    pp.blank_lines = blanks.items;
    pp.printModule(&mod) catch {
        term.err("failed to format '{s}'", .{src_path});
        std.process.exit(1);
    };

    const cwd = Io.Dir.cwd();
    Io.Dir.writeFile(cwd, io, .{ .sub_path = src_path, .data = buf.items }) catch |err| {
        term.err("failed to write formatted source to '{s}': {s}", .{ src_path, @errorName(err) });
        std.process.exit(1);
    };
    term.ok("Formatted {s}", .{src_path});
}
