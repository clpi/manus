const std = @import("std");
const Io = std.Io;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const ast = @import("ast.zig");
const Sema = @import("sema.zig").Sema;
const CodeGen = @import("codegen.zig").CodeGen;
const Mono = @import("mono.zig");
const MacroExpand = @import("macro_expand.zig");
const Arc = @import("arc.zig");
const AsyncLower = @import("async_lower.zig");
const escape = @import("escape.zig");
const PrettyPrinter = @import("pretty.zig").PrettyPrinter;
const term = @import("term.zig");
const debug_trace = @import("debug_trace.zig");
const build_framework = @import("build_framework.zig");
const ml_kernels = @import("ml_kernels.zig");
const native_backend = @import("native_backend.zig");
const semantic_graph = @import("semantic_graph.zig");
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
const optimization_outcome = @import("optimization_outcome.zig");
const explain_pipeline = @import("explain_pipeline.zig");
const c_sim_import = @import("c_sim_import.zig");
const abi_specialize = @import("abi_specialize.zig");
const semantic_algebra = @import("semantic_algebra.zig");
const transform_engine = @import("transform_engine.zig");
const pass3_catalog = @import("pass3_catalog.zig");
const wasm_semantic_gen = @import("wasm_semantic_gen.zig");

var macos_sdkroot_configured = false;
var compiler_lib_root: ?[]const u8 = null;
var forwarded_program_args: []const []const u8 = &.{};
var graph_diag_enabled: bool = false;
var graph_write_enabled: bool = false;
var semantic_cache_enabled: bool = true;

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
    if (map.get("DUO_SEMANTIC_CACHE")) |v| {
        if (!env_value_truthy(v)) semantic_cache_enabled = false;
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

const usage =
    \\usage: duo [command] [options] [file]
    \\
    \\commands:
    \\  shell              start the interactive Duo shell (default)
    \\  init       [name]   create a new Duo project
    \\  build      [target] build the default or named target from @build metadata
    \\             list     show all @build.* targets (or: duo build --list)
    \\             all      build every compile target in stage order
    \\             stage S  build targets in stage S (or: duo build all --stage S)
    \\  compile    [file]   compile .duo/.lua to a native binary
    \\  run        [file]   compile and run immediately, or run @build target
    \\  check      <file>   type-check only, no output
    \\  fmt        <file>   format a .duo/.lua file (--canonical strips then/do in .duo)
    \\  test       [file]   run inline @test functions (or @build.test target)
    \\  bench      [file]   run @bench-marked functions (or @build.bench target)
    \\  symbols    <file>   glanceable module/test/build symbol map
    \\  graph      <file>   export semantic graph JSON (table_shapes, enum_shapes)
    \\  sim        <file>   export SIM v0 semantic snapshot JSON (Pass 5)
    \\             --import-c <header>  import C declarations into SIM (Pass 5 Layer B)
    \\  explain    <file>   export knowledge snapshots + optimization outcomes (Pass 7)
    \\  realize    <file>   export realization plan + persistent evidence (Pass 8)
    \\  algebra             export Pass 2 convergence catalog JSON
    \\  catalog             export Pass 3 keyword/directive/grammar catalog JSON
    \\  wasm-tables emit    regenerate lib/std/wasm/opcode_lookup.duo + ward_mvp_opcodes.duo
    \\  completion <shell>  generate shell completions (bash, zsh, fish, nu)
    \\
    \\options:
    \\  -o <name>         output binary name (default: <stem>.out or <stem>.wasm)
    \\  -O<n>             optimisation level (default: -O3)
    \\  --cc <path>       C compiler (default: clang)
    \\  --target <triple> target triple for cross-compilation (e.g. wasm32-wasi, native-object, native-exe, native-dylib)
    \\  --load-chunk      compile as shared library for runtime load() (not for run)
    \\  --pgo             use profile-guided optimisation (two-pass clang compile)
    \\  --shared-memory   enable WASM shared memory (-matomics -mbulk-memory; wasm32-wasi only)
    \\  --link <lib>      link against a C library (e.g. --link raylib; repeatable)
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
    \\  --canonical       fmt: omit deprecated then/do keywords in .duo output
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
        try do_shell(alloc, io, false);
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
            std.mem.eql(u8, args[1], "symbols") or
            std.mem.eql(u8, args[1], "graph") or
            std.mem.eql(u8, args[1], "sim") or
            std.mem.eql(u8, args[1], "realize") or
            std.mem.eql(u8, args[1], "explain") or
            std.mem.eql(u8, args[1], "algebra") or
            std.mem.eql(u8, args[1], "catalog") or
            std.mem.eql(u8, args[1], "wasm-tables") or
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

    apply_cli_flags(trace_flag, info_flag, hints_flag, plain_diag, debug_flag, debug_list, debug_depth, test_report_style, build_report_style, no_color, verbose_count);
    if (trace_rich and term.build_report == .pretty) term.setBuildReport(.verbose);

    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        term.printRaw("{s}", .{usage});
        return;
    }

    if (std.mem.eql(u8, cmd, "shell")) {
        try do_shell(alloc, io, verbose);
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
            try do_build_stage(alloc, io, stage_name, output_file, cc, opt_level, target, verbose, load_chunk, pgo, lib_mode, shared_mem, link_flags.items);
            return;
        }
        if (input_file != null and std.mem.eql(u8, input_file.?, "all")) {
            try do_build_all(alloc, io, stage_filter, output_file, cc, opt_level, target, verbose, load_chunk, pgo, lib_mode, shared_mem, link_flags.items);
            return;
        }
        try do_project_build(alloc, io, input_file, output_file, cc, opt_level, target, verbose, load_chunk, pgo, lib_mode, shared_mem, link_flags.items, false);
        return;
    }

    if (std.mem.eql(u8, cmd, "run") and input_file == null) {
        try do_project_build(alloc, io, null, output_file, cc, opt_level, target, verbose, load_chunk, pgo, lib_mode, shared_mem, link_flags.items, true);
        return;
    }

    if (std.mem.eql(u8, cmd, "run")) {
        if (input_file) |maybe_target| {
            if (!is_duo_source_path(maybe_target) and !is_lua_source_path(maybe_target)) {
                try do_project_build(alloc, io, maybe_target, output_file, cc, opt_level, target, verbose, load_chunk, pgo, lib_mode, shared_mem, link_flags.items, true);
                return;
            }
        }
    }

    if (std.mem.eql(u8, cmd, "symbols")) {
        const file = input_file orelse {
            term.err("no input file (duo symbols <file.duo>)", .{});
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
            term.err("no input file (duo graph <file.duo> [--write])", .{});
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
            term.err("no input file (duo sim <file.duo> or duo sim --import-c <header>)", .{});
            std.process.exit(1);
        };
        try do_sim(alloc, io, file);
        return;
    }

    if (std.mem.eql(u8, cmd, "realize")) {
        if (input_file == null) {
            term.err("no input file (duo realize <file.duo>)", .{});
            std.process.exit(1);
        }
        try do_realize(alloc, io, input_file.?);
        return;
    }

    if (std.mem.eql(u8, cmd, "explain")) {
        const file = input_file orelse {
            term.err("no input file (duo explain <file.duo>)", .{});
            std.process.exit(1);
        };
        try do_explain(alloc, io, file);
        return;
    }

    if (std.mem.eql(u8, cmd, "catalog")) {
        if (input_file != null) {
            term.err("duo catalog takes no file argument", .{});
            std.process.exit(1);
        }
        try do_catalog(alloc, io);
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
        try wasm_semantic_gen.emitDuoOpcodeLookupFile(alloc, io, "lib/std/wasm/opcode_lookup.duo");
        try wasm_semantic_gen.emitWardMvpOpcodesFile(alloc, io, "lib/std/wasm/ward_mvp_opcodes.duo");
        term.print("wrote lib/std/wasm/opcode_lookup.duo\n", .{});
        term.print("wrote lib/std/wasm/ward_mvp_opcodes.duo\n", .{});
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
            try run_test_sources(alloc, io, &.{file}, output_file, cc, opt_level, target, verbose, bench_only, test_filter, link_flags.items);
            return;
        }
        if (try maybeReadBuildTarget(alloc, io, null, if (bench_only) .bench else .@"test")) |t| {
            const src = t.src orelse {
                term.err("build target '{s}' has no src= field", .{t.name});
                std.process.exit(1);
            };
            try run_test_sources(alloc, io, &.{src}, output_file, t.cc orelse cc, t.opt orelse opt_level, t.target orelse target, verbose, bench_only or t.bench_mode(), test_filter, t.link);
            return;
        }
        const sources = try scanInlineTestSources(alloc, io, bench_only);
        defer alloc.free(sources);
        if (sources.len == 0) {
            term.err("no inline {s} sources found", .{if (bench_only) "bench" else "test"});
            term.hint("add @test/@test.* to .duo files or --- @test before Lua functions, or define @build.test", .{});
            std.process.exit(1);
        }
        try run_test_sources(alloc, io, sources, output_file, cc, opt_level, target, verbose, bench_only, test_filter, link_flags.items);
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
        try do_compile(alloc, io, file, out, cc, opt_level, target, false, false, false, load_chunk, pgo, lib_mode, shared_mem, false, false, null, link_flags.items);
    } else if (std.mem.eql(u8, cmd, "run")) {
        try do_compile(alloc, io, file, out, cc, opt_level, target, true, false, verbose, false, false, false, false, false, false, null, link_flags.items);
    } else if (std.mem.eql(u8, cmd, "check")) {
        try do_compile(alloc, io, file, out, cc, opt_level, target, false, true, false, false, false, false, false, false, false, null, &.{});
    } else if (std.mem.eql(u8, cmd, "fmt")) {
        try do_fmt(alloc, io, file, fmt_canonical);
    } else if (std.mem.eql(u8, cmd, "dump-c")) {
        try do_dump_c(alloc, io, file, target);
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
    return is_duo_source_path(path) or is_lua_source_path(path);
}

fn usesProjectWorkspace(cmd: []const u8, input_file: ?[]const u8) bool {
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
                    const std_root = try pathJoin2(alloc, lib, "std.duo");
                    defer alloc.free(std_root);
                    if (absPathExists(io, std_root)) return lib;
                    alloc.free(lib);
                }
            }
        }
    }
    const local_std = try pathJoin2(alloc, "lib", "std.duo");
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
                                    const std_root = try pathJoin2(alloc, lib, "std.duo");
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
    const build = try pathJoin2(alloc, dir, "build.duo");
    defer alloc.free(build);
    if (absPathExists(io, build)) return true;
    const src_build = try pathJoin2(alloc, dir, "src/build.duo");
    defer alloc.free(src_build);
    if (absPathExists(io, src_build)) return true;
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
        term.hint("expected build.duo, src/build.duo, src/main.duo, main.duo, src/main.lua, main.lua, src/init.lua, or init.lua", .{});
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
    term.hint("create src/main.duo, main.duo, src/main.lua, main.lua, src/init.lua, or init.lua", .{});
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
    if (project.targets.len == 0 and std.mem.eql(u8, std.fs.path.basename(build_source), "build.duo")) {
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
        term.err("no build targets found — add @build.run {{ src = \"...\" }} or a build.duo target manifest", .{});
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
    term.dim("inline @build.* — targets can live in build.duo, src/build.duo, or the entrypoint", .{});
}

fn do_build_all(
    alloc: std.mem.Allocator,
    io: Io,
    stage_filter: ?[]const u8,
    output_file: ?[]const u8,
    cc_arg: []const u8,
    opt_arg: []const u8,
    target_arg: []const u8,
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
        try do_project_build_one(alloc, io, t, output_file, cc_arg, opt_arg, target_arg, verbose, load_chunk_arg, pgo_arg, lib_mode_arg, shared_mem_arg, link_flags_arg, false);
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
            else => try do_project_build_one(alloc, io, t, output_file, cc_arg, opt_arg, target_arg, verbose, load_chunk_arg, pgo_arg, lib_mode_arg, shared_mem_arg, link_flags_arg, false),
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
        if (std.mem.endsWith(u8, entry.name, ".duo") or std.mem.endsWith(u8, entry.name, ".lua")) {
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
        try do_compile(alloc, io, src, dummy, t.cc orelse "clang", t.opt orelse "-O3", t.target orelse "native", false, true, false, false, false, false, false, false, false, null, t.link);
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
        const is_lua = std.mem.endsWith(u8, entry.name, ".lua");
        const is_duo = std.mem.endsWith(u8, entry.name, ".duo");
        if (!is_lua and !is_duo) continue;
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
        if (fileMayContainInlineTest(bytes, is_lua, bench_only)) {
            try out.append(alloc, path);
        } else {
            alloc.free(path);
        }
    }
}

fn lessTestPath(_: void, a: []const u8, b: []const u8) bool {
    const score = struct {
        fn value(path: []const u8) u8 {
            if (std.mem.eql(u8, path, "test/main.duo")) return 0;
            if (std.mem.eql(u8, path, "test/main.lua")) return 1;
            if (std.mem.startsWith(u8, path, "test/")) return 2;
            if (std.mem.startsWith(u8, path, "tests/")) return 3;
            if (std.mem.startsWith(u8, path, "src/")) return 4;
            return 5;
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
        try do_compile(alloc, io, file, out, cc, opt_level, target, false, false, verbose, false, false, false, false, true, bench_only, test_filter, link_flags);
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
    const ps = try parse_and_check(alloc, io, src_path);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCalls(&ps.mod, src_path);
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
    const ps = try parse_and_check(alloc, io, src_path);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCalls(&ps.mod, src_path);
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
    var ps = try parse_and_check(alloc, io, src_path);
    defer ps.sem.deinit();
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCalls(&ps.mod, src_path);

    var snap = try knowledge_snapshot.buildFromModule(alloc, &ps.mod, &ps.sem, &graph, src_path);
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
    if (repair_set) |rs| {
        try fw.interface.print(",\"repair_candidates\":", .{});
        try repair_candidate.writeRepairSetJson(&rs, &fw.interface);
    }
    try fw.interface.print("}}\n", .{});
    try fw.interface.flush();
}

fn do_algebra(io: Io) !void {
    const stdout = std.Io.File.stdout();
    var buf: [8192]u8 = undefined;
    var fw: std.Io.File.Writer = .init(stdout, io, &buf);
    try semantic_algebra.writeCatalogJson(&fw.interface);
    try fw.interface.flush();
}

fn do_catalog(alloc: std.mem.Allocator, io: Io) !void {
    const stdout = std.Io.File.stdout();
    var buf: [65536]u8 = undefined;
    var fw: std.Io.File.Writer = .init(stdout, io, &buf);
    try pass3_catalog.writeCatalogJson(&fw.interface, alloc);
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
    const main_src = try std.fmt.allocPrint(alloc,
        \\@build.project({{
        \\    name = "{s}",
        \\    version = "0.1.0",
        \\    default = "app"
        \\}})
        \\@build.run({{
        \\    name = "app",
        \\    src = "src/main.duo",
        \\    out = "zig-out/bin/{s}",
        \\    opt = "-O3"
        \\}})
        \\@build.test({{
        \\    name = "test",
        \\    src = "src/main.duo",
        \\    out = "zig-out/bin/{s}_test"
        \\}})
        \\
        \\@test
        \\fun smoke(): void
        \\    assert(1 + 1 == 2)
        \\end
        \\
        \\print("hello from Duo")
        \\
    , .{ name, name, name });

    const mkdir_argv = [_][]const u8{ "mkdir", "-p", "src", "zig-out/bin" };
    try run_child_process(io, &mkdir_argv, "mkdir", true);
    try writeNewFile(io, "src/main.duo", main_src);
    term.banner("Duo project created");
    term.kv("name", name);
    term.section("files");
    term.kv("•", "src/main.duo");
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
    const argv = [_][]const u8{ "/bin/sh", "-c", command };
    var child = try std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const result = try child.wait(io);
    switch (result) {
        .exited => |code| if (code != 0) {
            term.print("host command exited with code {}", .{code});
        },
        .signal => term.print("host command terminated by signal", .{}),
        else => term.print("host command terminated abnormally", .{}),
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

fn run_shell_line(alloc: std.mem.Allocator, io: Io, raw_line: []const u8, counter: *usize, verbose: bool) !bool {
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
            term.kv(":quit / :exit", "leave the shell");
            term.divider();
            term.dim("Duo compiles each line to native code via clang", .{});
            return true;
        }
        if (std.mem.eql(u8, line, ":time")) {
            term.section("shell timing");
            var buf: [32]u8 = undefined;
            const lc = std.fmt.bufPrint(&buf, "{}", .{counter.*}) catch "error";
            term.kv("lines compiled", lc);
            var buf2: [32]u8 = undefined;
            const hi = std.fmt.bufPrint(&buf2, "{}", .{shell_history.items.len}) catch "error";
            term.kv("history entries", hi);
            return true;
        }
        if (std.mem.eql(u8, line, ":reset")) {
            counter.* = 0;
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

    // Handle host shell commands
    if (line[0] == '!') {
        try run_host_shell_command(io, std.mem.trim(u8, line[1..], " \t"));
        return true;
    }

    // Track history
    if (shell_history.items.len >= shell_history_capacity) {
        // Remove oldest entry
        alloc.free(shell_history.items[0]);
        _ = shell_history.orderedRemove(0);
    }
    try shell_history.append(alloc, try alloc.dupe(u8, line));

    // Determine if this is a statement or expression
    const source = if (shellLineIsStatement(line))
        try std.fmt.allocPrint(alloc, "{s}\n", .{line})
    else
        try std.fmt.allocPrint(alloc, "print({s})\n", .{line});

    const src_path = try std.fmt.allocPrint(alloc, "/tmp/duo_shell_{d}.duo", .{counter.*});
    const out_path = try std.fmt.allocPrint(alloc, "/tmp/duo_shell_{d}.out", .{counter.*});
    counter.* += 1;

    const cwd = Io.Dir.cwd();
    try Io.Dir.writeFile(cwd, io, .{ .sub_path = src_path, .data = source });

    // Compile and run (with timing in verbose mode)
    // Suppress build phase output for cleaner shell experience
    const prev_report = term.build_report;
    term.build_report = .plain;
    defer term.build_report = prev_report;

    const compile_started = Io.Timestamp.now(io, .awake);
    try do_compile(alloc, io, src_path, out_path, "clang", "-O3", "native", false, false, verbose, false, false, false, false, false, false, null, &.{});
    const compile_elapsed: u64 = @intCast(@divTrunc(compile_started.durationTo(Io.Timestamp.now(io, .awake)).nanoseconds, std.time.ns_per_ms));

    try run_shell_binary(io, out_path);
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
        term.printRaw("\x1b[1;36mduo\x1b[0m\x1b[2m·{}\x1b[0m ", .{depth + 1});
    } else {
        term.printRaw("duo·{} ", .{depth + 1});
    }
}

fn do_shell(alloc: std.mem.Allocator, io: Io, verbose: bool) !void {
    term.banner("Duo shell");
    term.dim("expressions print results · statements compile+run · :help for commands", .{});
    var line: std.ArrayList(u8) = .empty;
    defer line.deinit(alloc);
    var counter: usize = 0;
    var block_depth: i32 = 0;
    var buf: [1024]u8 = undefined;

    // Print initial prompt
    if (term.color) {
        term.printRaw("\x1b[1;36mduo\x1b[0m\x1b[2m>\x1b[0m ", .{});
    } else {
        term.printRaw("duo> ", .{});
    }
    while (true) {
        const n = try std.posix.read(std.posix.STDIN_FILENO, buf[0..]);
        if (n == 0) {
            // EOF - run any remaining line
            if (line.items.len > 0) {
                _ = try run_shell_line(alloc, io, line.items, &counter, verbose);
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
                        _ = try run_shell_line(alloc, io, line.items, &counter, verbose);
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
    try do_project_build_one(alloc, io, t, output_file, cc_arg, opt_arg, target_arg, verbose, load_chunk_arg, pgo_arg, lib_mode_arg, shared_mem_arg, link_flags_arg, run_after);
}

fn do_project_build_one(
    alloc: std.mem.Allocator,
    io: Io,
    t: build_framework.Target,
    output_file: ?[]const u8,
    cc_arg: []const u8,
    opt_arg: []const u8,
    target_arg: []const u8,
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

fn is_lua_source_path(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".lua");
}

fn is_duo_source_path(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".duo");
}

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

fn parse_and_check(alloc: std.mem.Allocator, io: Io, src_path: []const u8) !ParsedModule {
    const src = try read_source(alloc, io, src_path);
    term.setSource(src_path, src);

    var lex = Lexer.init(src, src_path);
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = is_duo_source_path(src_path);
    var mod = parser.parse_module() catch |e| {
        if (lex.last_error_loc) |loc| {
            term.locErr(loc, "lexer failed with {s}", .{@errorName(e)});
        } else {
            term.err("parse failed: {s}", .{@errorName(e)});
        }
        std.process.exit(1);
    };

    var sem = Sema.init(alloc);
    sem.lua55_mode = is_lua_source_path(src_path);
    sem.duo_mode = is_duo_source_path(src_path);
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
    if (graph_diag_enabled) {
        var graph = semantic_graph.SemanticGraph.init(alloc);
        defer graph.deinit();
        if (graph.liftModuleWithCalls(&mod, src_path)) |_| {
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
        .stderr = if (quiet) .ignore else .inherit,
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

fn link_native_object(alloc: std.mem.Allocator, io: Io, obj_path: []const u8, out_path: []const u8, cc: []const u8, link_flags: []const []const u8, quiet: bool, shared: bool) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(alloc);
    if (@import("builtin").os.tag == .macos and !macos_sdkroot_configured) {
        try argv.appendSlice(alloc, &.{ "xcrun", cc });
    } else {
        try argv.append(alloc, cc);
    }
    try argv.append(alloc, obj_path);
    if (shared) try argv.append(alloc, "-dynamiclib");
    try argv.appendSlice(alloc, &.{ "-o", out_path, "-lm" });
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

fn do_compile(
    alloc: std.mem.Allocator,
    io: Io,
    src_path: []const u8,
    out_path: []const u8,
    cc: []const u8,
    opt: []const u8,
    target: []const u8,
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

    if (semantic_cache_enabled and ps.sem.duo_mode) {
        if (compile_semantic_cache.refreshFromCheckedModule(alloc, io, &ps.mod, src_path, target)) |refresh| {
            var cache_refresh = refresh;
            defer cache_refresh.deinit(alloc);
            if (term.info) {
                var reused: u32 = 0;
                var fresh: u32 = 0;
                var invalidated: u32 = 0;
                for (cache_refresh.audits) |row| {
                    switch (row.action) {
                        .reused => reused += 1,
                        .fresh => fresh += 1,
                        .invalidated => invalidated += 1,
                        .updated => {},
                    }
                }
                term.infoMsg("semantic cache: {d} reused, {d} fresh, {d} invalidated, {d} removal edge(s)", .{
                    reused,
                    fresh,
                    invalidated,
                    cache_refresh.invalidation.edges.len,
                });
            }
        } else |e| {
            if (term.info) term.infoMsg("semantic cache refresh skipped: {}", .{e});
        }
    }

    var native_scalar_precheck = CodeGen.init(alloc, io, &ps.sem.type_map, &ps.sem.module_globals, undefined, ps.sem.next_closure_id, &ps.sem.table_field_types, &ps.sem.concepts);
    native_scalar_precheck.src_path = src_path;
    native_scalar_precheck.stdlib_root = compiler_lib_root;
    native_scalar_precheck.target = target;
    native_scalar_precheck.load_chunk = load_chunk;
    native_scalar_precheck.lib_mode = lib_mode;
    native_scalar_precheck.duo_mode = ps.sem.duo_mode;
    native_scalar_precheck.test_mode = test_mode;
    native_scalar_precheck.bench_mode = bench_mode;
    native_scalar_precheck.populate_alias_defs(&ps.mod) catch {};
    native_scalar_precheck.populate_record_aliases(&ps.mod) catch {};
    native_scalar_precheck.populate_enum_defs(&ps.mod) catch {};
    native_scalar_precheck.populate_func_bodies(&ps.mod) catch {};
    const native_scalar_candidate = native_scalar_precheck.can_emit_native_scalar_module(&ps.mod);

    if (native_backend.isNativeMachineTarget(target)) {
        if (run_after and !native_backend.isNativeExecutableTarget(target)) {
            term.err("only --target native-exe can run through the native machine-code backend", .{});
            std.process.exit(1);
        }
        if (load_chunk or lib_mode or shared_mem or pgo) {
            term.err("native machine-code target does not use C-only compile options yet", .{});
            std.process.exit(1);
        }
        if (!native_backend.isNativeExecutableTarget(target) and !native_backend.isNativeSharedTarget(target) and link_flags.len != 0) {
            term.err("native object/asm targets do not link libraries; use --target native-exe or native-dylib", .{});
            std.process.exit(1);
        }
        if (!native_scalar_candidate) {
            term.err("native machine-code backend requires a fully typed native-scalar module", .{});
            term.hint("{s}", .{native_backend.unsupportedReason(target)});
            std.process.exit(1);
        }
        if (native_backend.isNativeExecutableTarget(target)) {
            const obj = native_backend.emitObject(alloc, &ps.mod, "native-object") catch |e| {
                term.err("native machine-code backend error: {}", .{e});
                term.hint("{s}", .{native_backend.unsupportedReason(target)});
                std.process.exit(1);
            };
            const obj_path = try std.fmt.allocPrint(alloc, "/tmp/duo_{s}_native.o", .{std.fs.path.stem(src_path)});
            const cwd = Io.Dir.cwd();
            try Io.Dir.writeFile(cwd, io, .{ .sub_path = obj_path, .data = obj });
            try link_native_object(alloc, io, obj_path, out_path, cc, link_flags, run_after and !verbose, false);
            if (phase_timer) |*t| trace_phase(io, t, "native link", out_path);
            if (term.build_report != .plain and !test_mode) {
                const total_ms: u64 = @intCast(@divTrunc(compile_started.durationTo(Io.Timestamp.now(io, .awake)).nanoseconds, std.time.ns_per_ms));
                term.buildPhaseDone("compile", total_ms, out_path);
            }
            if (!run_after and !(test_mode and term.test_report == .json)) term.ok("✓ {s}", .{out_path});
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
        }
        if (native_backend.isNativeSharedTarget(target)) {
            const obj = native_backend.emitSharedObjectInput(alloc, &ps.mod) catch |e| {
                term.err("native machine-code backend error: {}", .{e});
                term.hint("{s}", .{native_backend.unsupportedReason(target)});
                std.process.exit(1);
            };
            const obj_path = try std.fmt.allocPrint(alloc, "/tmp/duo_{s}_native_dylib.o", .{std.fs.path.stem(src_path)});
            const cwd = Io.Dir.cwd();
            try Io.Dir.writeFile(cwd, io, .{ .sub_path = obj_path, .data = obj });
            try link_native_object(alloc, io, obj_path, out_path, cc, link_flags, false, true);
            if (phase_timer) |*t| trace_phase(io, t, "native dylib", out_path);
            if (term.build_report != .plain and !test_mode) {
                const total_ms: u64 = @intCast(@divTrunc(compile_started.durationTo(Io.Timestamp.now(io, .awake)).nanoseconds, std.time.ns_per_ms));
                term.buildPhaseDone("compile", total_ms, out_path);
            }
            if (!(test_mode and term.test_report == .json)) term.ok("✓ {s}", .{out_path});
            return;
        }
        const native_output = if (native_backend.isNativeAsmTarget(target))
            native_backend.emitAssembly(alloc, &ps.mod, target)
        else
            native_backend.emitObject(alloc, &ps.mod, target);
        const obj = native_output catch |e| {
            term.err("native machine-code backend error: {}", .{e});
            term.hint("{s}", .{native_backend.unsupportedReason(target)});
            std.process.exit(1);
        };
        const cwd = Io.Dir.cwd();
        try Io.Dir.writeFile(cwd, io, .{ .sub_path = out_path, .data = obj });
        if (phase_timer) |*t| trace_phase(io, t, "native object", out_path);
        if (term.build_report != .plain and !test_mode) {
            const total_ms: u64 = @intCast(@divTrunc(compile_started.durationTo(Io.Timestamp.now(io, .awake)).nanoseconds, std.time.ns_per_ms));
            term.buildPhaseDone("compile", total_ms, out_path);
        }
        if (!(test_mode and term.test_report == .json)) term.ok("✓ {s}", .{out_path});
        return;
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
        cg.duo_mode = ps.sem.duo_mode;
        cg.test_mode = test_mode;
        cg.bench_mode = bench_mode;
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

        // Pass 1: instrument.
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

        // Pass 2: optimise with profile.
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
    \\    local commands="shell init build compile run check test bench dump-c completion help"
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
    \\            COMPREPLY=( $(compgen -f -X '!*.duo' -- "${cur}") $(compgen -f -X '!*.lua' -- "${cur}") $(compgen -W "${options}" -- "${cur}") )
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
    \\    'build:build the default or named build.duo target'
    \\    'compile:compile .duo/.lua to a native binary'
    \\    'run:compile and run a file or build target'
    \\    'check:type-check only'
    \\    'test:run @test functions in a .duo file'
    \\    'bench:run @bench functions only'
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
    \\complete -c duo -n '__fish_use_subcommand' -a 'build' -d 'Build the default or named build.duo target'
    \\complete -c duo -n '__fish_use_subcommand' -a 'compile' -d 'Compile .duo/.lua to a native binary'
    \\complete -c duo -n '__fish_use_subcommand' -a 'run' -d 'Compile and run a file or build target'
    \\complete -c duo -n '__fish_use_subcommand' -a 'check' -d 'Type-check only'
    \\complete -c duo -n '__fish_use_subcommand' -a 'test' -d 'Run @test functions in a .duo file'
    \\complete -c duo -n '__fish_use_subcommand' -a 'bench' -d 'Run @bench functions only'
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
    \\  [shell init build compile run check test bench dump-c completion help]
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

fn do_dump_c(alloc: std.mem.Allocator, io: Io, src_path: []const u8, target: []const u8) !void {
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
    cg.duo_mode = ps.sem.duo_mode;
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
    var lex = Lexer.init(src, src_path);
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = is_duo_source_path(src_path);
    const mod = parser.parse_module() catch |err| {
        if (lex.last_error_loc) |loc| {
            term.locErr(loc, "lexer failed with {s}", .{@errorName(err)});
        } else {
            term.err("failed to parse '{s}': {s}", .{ src_path, @errorName(err) });
        }
        std.process.exit(1);
    };

    var buf: std.ArrayList(u8) = .empty;
    var pp = PrettyPrinter.init(alloc, &buf, .duo);
    pp.canonical = canonical and parser.duo_mode;
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
