const std = @import("std");
const Io = std.Io;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;
const CodeGen = @import("codegen.zig").CodeGen;
const Mono = @import("mono.zig");
const Arc = @import("arc.zig");
const AsyncLower = @import("async_lower.zig");

const usage =
    \\usage: duo <command> [options] <file>
    \\
    \\commands:
    \\  init      [name]   create a new Duo project
    \\  build     [target] build the default or named target from build.duo
    \\  compile    <file>   compile .duo/.lua to a native binary
    \\  run        [file]   compile and run immediately, or run build.duo target
    \\  check      <file>   type-check only, no output
    \\  dump-c     <file>   print generated C to stdout
    \\  completion <shell>  generate shell completions (bash, zsh, fish, nu)
    \\
    \\options:
    \\  -o <name>         output binary name (default: <stem>.out or <stem>.wasm)
    \\  -O<n>             optimisation level (default: -O3)
    \\  --cc <path>       C compiler (default: clang)
    \\  --target <triple> target triple for cross-compilation (e.g. wasm32-wasi)
    \\  --load-chunk      compile as shared library for runtime load() (not for run)
    \\  --pgo             use profile-guided optimisation (two-pass clang compile)
    \\  --shared-memory   enable WASM shared memory (-matomics -mbulk-memory; wasm32-wasi only)
    \\  -v, --verbose     show C compiler warnings (run only; off by default)
    \\
;

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(alloc);

    if (args.len < 2) {
        std.debug.print("{s}", .{usage});
        std.process.exit(1);
    }
    const known_cmd = args.len >= 2 and
        (std.mem.eql(u8, args[1], "init") or
            std.mem.eql(u8, args[1], "build") or
            std.mem.eql(u8, args[1], "compile") or
            std.mem.eql(u8, args[1], "run") or
            std.mem.eql(u8, args[1], "check") or
            std.mem.eql(u8, args[1], "dump-c") or
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
    var load_chunk = false;
    var lib_mode = false;
    var pgo = false;
    var shared_mem = false;
    var i: usize = start;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-o") and i + 1 < args.len) {
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
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (arg.len > 0 and arg[0] != '-') {
            input_file = arg;
        }
    }

    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        std.debug.print("{s}", .{usage});
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

    if (std.mem.eql(u8, cmd, "build")) {
        try do_project_build(alloc, io, input_file, output_file, cc, opt_level, target, verbose, load_chunk, pgo, lib_mode, shared_mem, false);
        return;
    }

    if (std.mem.eql(u8, cmd, "run") and input_file == null) {
        try do_project_build(alloc, io, null, output_file, cc, opt_level, target, verbose, load_chunk, pgo, lib_mode, shared_mem, true);
        return;
    }

    if (std.mem.eql(u8, cmd, "run")) {
        if (input_file) |maybe_target| {
            if (!is_duo_source_path(maybe_target) and !is_lua_source_path(maybe_target)) {
                try do_project_build(alloc, io, maybe_target, output_file, cc, opt_level, target, verbose, load_chunk, pgo, lib_mode, shared_mem, true);
                return;
            }
        }
    }

    const file = input_file orelse {
        std.debug.print("error: no input file\n", .{});
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
        try do_compile(alloc, io, file, out, cc, opt_level, target, false, false, false, load_chunk, pgo, lib_mode, shared_mem);
    } else if (std.mem.eql(u8, cmd, "run")) {
        try do_compile(alloc, io, file, out, cc, opt_level, target, true, false, verbose, false, false, false, false);
    } else if (std.mem.eql(u8, cmd, "check")) {
        try do_compile(alloc, io, file, out, cc, opt_level, target, false, true, false, false, false, false, false);
    } else if (std.mem.eql(u8, cmd, "dump-c")) {
        try do_dump_c(alloc, io, file, target);
    } else {
        std.debug.print("error: unknown command '{s}'\n{s}", .{ cmd, usage });
        std.process.exit(1);
    }
}

fn read_source(alloc: std.mem.Allocator, io: Io, path: []const u8) ![]u8 {
    const cwd = Io.Dir.cwd();
    return Io.Dir.readFileAlloc(cwd, io, path, alloc, .unlimited);
}

const BuildTarget = struct {
    name: []const u8,
    src: []const u8,
    out: ?[]const u8 = null,
    cc: ?[]const u8 = null,
    opt: ?[]const u8 = null,
    target: ?[]const u8 = null,
    load_chunk: bool = false,
    pgo: bool = false,
    lib_mode: bool = false,
    shared_mem: bool = false,
};

fn firstStringField(src: []const u8, field: []const u8) ?[]const u8 {
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, src, at, field)) |pos| {
        const before_ok = pos == 0 or !std.ascii.isAlphanumeric(src[pos - 1]) and src[pos - 1] != '_';
        const after = pos + field.len;
        const after_ok = after >= src.len or !std.ascii.isAlphanumeric(src[after]) and src[after] != '_';
        if (before_ok and after_ok) {
            var i = after;
            while (i < src.len and std.ascii.isWhitespace(src[i])) : (i += 1) {}
            if (i < src.len and src[i] == '=') {
                i += 1;
                while (i < src.len and std.ascii.isWhitespace(src[i])) : (i += 1) {}
                if (i < src.len and src[i] == '"') {
                    i += 1;
                    const start = i;
                    while (i < src.len) : (i += 1) {
                        if (src[i] == '"' and (i == start or src[i - 1] != '\\')) return src[start..i];
                    }
                }
            }
        }
        at = pos + field.len;
    }
    return null;
}

fn firstBoolField(src: []const u8, field: []const u8, default: bool) bool {
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, src, at, field)) |pos| {
        const before_ok = pos == 0 or !std.ascii.isAlphanumeric(src[pos - 1]) and src[pos - 1] != '_';
        const after = pos + field.len;
        const after_ok = after >= src.len or !std.ascii.isAlphanumeric(src[after]) and src[after] != '_';
        if (!before_ok or !after_ok) {
            at = pos + field.len;
            continue;
        }
        var i = after;
        while (i < src.len and std.ascii.isWhitespace(src[i])) : (i += 1) {}
        if (i < src.len and src[i] == '=') {
            i += 1;
            while (i < src.len and std.ascii.isWhitespace(src[i])) : (i += 1) {}
            if (std.mem.startsWith(u8, src[i..], "true")) return true;
            if (std.mem.startsWith(u8, src[i..], "false")) return false;
        }
        at = pos + field.len;
    }
    return default;
}

fn matchingTable(src: []const u8, open: usize) ?[]const u8 {
    var depth: usize = 0;
    var in_string = false;
    var i = open;
    while (i < src.len) : (i += 1) {
        const c = src[i];
        if (in_string) {
            if (c == '"' and (i == 0 or src[i - 1] != '\\')) in_string = false;
            continue;
        }
        if (c == '"') {
            in_string = true;
        } else if (c == '{') {
            depth += 1;
        } else if (c == '}') {
            depth -= 1;
            if (depth == 0) return src[open + 1 .. i];
        }
    }
    return null;
}

fn parseTargetBlock(block: []const u8, lib_mode: bool) ?BuildTarget {
    const src = firstStringField(block, "src") orelse return null;
    const name = firstStringField(block, "name") orelse std.fs.path.stem(src);
    return .{
        .name = name,
        .src = src,
        .out = firstStringField(block, "out"),
        .cc = firstStringField(block, "cc"),
        .opt = firstStringField(block, "opt"),
        .target = firstStringField(block, "target"),
        .load_chunk = firstBoolField(block, "load_chunk", false),
        .pgo = firstBoolField(block, "pgo", false),
        .lib_mode = lib_mode or firstBoolField(block, "lib", false),
        .shared_mem = firstBoolField(block, "shared_memory", false),
    };
}

fn readBuildTarget(alloc: std.mem.Allocator, io: Io, requested: ?[]const u8) !BuildTarget {
    const src = read_source(alloc, io, "build.duo") catch |e| {
        std.debug.print("error: unable to read build.duo: {}\nrun `duo init` to create one\n", .{e});
        std.process.exit(1);
    };
    const target_name = requested orelse firstStringField(src, "default");
    var first: ?BuildTarget = null;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, src, at, "build.")) |pos| {
        const is_exe = std.mem.startsWith(u8, src[pos..], "build.exe");
        const is_lib = std.mem.startsWith(u8, src[pos..], "build.lib");
        if (!is_exe and !is_lib) {
            at = pos + "build.".len;
            continue;
        }
        const rel_open = std.mem.indexOfScalar(u8, src[pos..], '{') orelse break;
        const open = pos + rel_open;
        const block = matchingTable(src, open) orelse break;
        if (parseTargetBlock(block, is_lib)) |t| {
            if (first == null) first = t;
            if (target_name) |want| {
                if (std.mem.eql(u8, t.name, want)) return t;
            }
        }
        at = open + block.len + 2;
    }
    if (target_name) |want| {
        std.debug.print("error: target '{s}' not found in build.duo\n", .{want});
        std.process.exit(1);
    }
    return first orelse {
        std.debug.print("error: build.duo does not define build.exe({{ src = \"...\" }}) or build.lib({{ src = \"...\" }})\n", .{});
        std.process.exit(1);
    };
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
            std.debug.print("error: refusing to overwrite existing {s}\n", .{path});
            std.process.exit(1);
        },
        else => return e,
    };
}

fn do_init(alloc: std.mem.Allocator, io: Io, name: []const u8) !void {
    const main_src =
        \\print("hello from Duo")
        \\
    ;
    const build_src = try std.fmt.allocPrint(alloc,
        \\build = req "std.build"
        \\
        \\build.project({{
        \\    name = "{s}",
        \\    version = "0.1.0",
        \\    default = "app",
        \\}})
        \\
        \\build.exe({{
        \\    name = "app",
        \\    src = "src/main.duo",
        \\    out = "zig-out/bin/{s}",
        \\    opt = "-O3",
        \\}})
        \\
    , .{ name, name });

    const mkdir_argv = [_][]const u8{ "mkdir", "-p", "src", "zig-out/bin" };
    try run_child_process(io, &mkdir_argv, "mkdir", true);
    try writeNewFile(io, "src/main.duo", main_src);
    try writeNewFile(io, "build.duo", build_src);
    std.debug.print("created Duo project '{s}'\n", .{name});
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
    run_after: bool,
) !void {
    const t = try readBuildTarget(alloc, io, requested);
    const target = t.target orelse target_arg;
    const target_lib_mode = lib_mode_arg or t.lib_mode;
    if (run_after and target_lib_mode) {
        std.debug.print("error: target '{s}' is a library and cannot be run\n", .{t.name});
        std.process.exit(1);
    }
    const out = output_file orelse t.out orelse out: {
        const stem = std.fs.path.stem(t.src);
        if (std.mem.eql(u8, target, "wasm32-wasi")) break :out try std.fmt.allocPrint(alloc, "zig-out/bin/{s}.wasm", .{stem});
        break :out try std.fmt.allocPrint(alloc, "zig-out/bin/{s}", .{stem});
    };
    try ensureDirForPath(io, out);
    try do_compile(
        alloc,
        io,
        t.src,
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
    );
}

const ParsedModule = struct {
    mod: @import("ast.zig").Module,
    sem: Sema,
};

fn is_lua_source_path(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".lua");
}

fn is_duo_source_path(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".duo");
}

fn parse_and_check(alloc: std.mem.Allocator, io: Io, src_path: []const u8) !ParsedModule {
    const src = try read_source(alloc, io, src_path);

    var lex = Lexer.init(src, src_path);
    var parser = Parser.init(&lex, alloc);
    var mod = parser.parse_module() catch |e| {
        std.debug.print("parse error: {}\n", .{e});
        std.process.exit(1);
    };

    var sem = Sema.init(alloc);
    sem.lua55_mode = is_lua_source_path(src_path);
    sem.duo_mode = is_duo_source_path(src_path);
    sem.check_module(&mod) catch |e| {
        std.debug.print("sema error: {}\n", .{e});
        std.process.exit(1);
    };
    if (sem.errors > 0) {
        std.debug.print("{d} error(s)\n", .{sem.errors});
        std.process.exit(1);
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
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) {
            std.debug.print("{s} failed (exit {})\n", .{ label, code });
            std.process.exit(1);
        },
        else => {
            std.debug.print("{s} terminated abnormally\n", .{label});
            std.process.exit(1);
        },
    }
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
) !void {
    var ps = try parse_and_check(alloc, io, src_path);
    defer ps.sem.deinit();

    if (check_only) {
        std.debug.print("OK\n", .{});
        return;
    }

    // Monomorphization: expand generic functions into concrete specializations
    // before codegen (Task 8.3). Runs on every compile so generic instantiation
    // is exercised even before codegen consumes the specializations (Task 12.1).
    var mono = Mono.Monomorphizer.init(alloc, &ps.sem.type_map);
    defer mono.deinit();
    mono.run(&ps.mod) catch |e| {
        std.debug.print("monomorphization error: {}\n", .{e});
        std.process.exit(1);
    };

    // ARC insertion: decide retain/release/close points for heap values, after
    // monomorphization and before codegen (Task 9.4).
    var arc_pass = Arc.ArcPass.init(alloc, &ps.sem.type_map);
    defer arc_pass.deinit();
    arc_pass.run(&ps.mod) catch |e| {
        std.debug.print("ARC analysis error: {}\n", .{e});
        std.process.exit(1);
    };

    // Async lowering: describe each `async` function as a state machine, after
    // ARC and before codegen (Task 10.3).
    const is_wasm_target = std.mem.eql(u8, target, "wasm32-wasi");
    // The threaded scheduler is selected by `--threads` / `@concurrent("threaded")`,
    // wired in Task 17.1; for now no threaded mode is requested here.
    const threaded = false;
    AsyncLower.validateTarget(is_wasm_target, threaded) catch {
        std.debug.print("error: the threaded scheduler is not supported on the wasm32-wasi target\n", .{});
        std.process.exit(1);
    };
    var async_pass = AsyncLower.AsyncLower.init(alloc, &ps.sem.type_map);
    defer async_pass.deinit();
    async_pass.run(&ps.mod) catch |e| {
        std.debug.print("async lowering error: {}\n", .{e});
        std.process.exit(1);
    };

    const is_wasm = std.mem.eql(u8, target, "wasm32-wasi");

    const c_path = try std.fmt.allocPrint(alloc, "/tmp/duo_{s}.c", .{
        std.fs.path.stem(src_path),
    });

    {
        const cwd = Io.Dir.cwd();
        const cf = try Io.Dir.createFile(cwd, io, c_path, .{});
        defer Io.File.close(cf, io);

        var buf: [65536]u8 = undefined;
        var fw: Io.File.Writer = .init(cf, io, &buf);
        var cg = CodeGen.init(alloc, io, &ps.sem.type_map, &ps.sem.module_globals, &fw.interface);
        cg.mono = &mono;
        cg.arc = &arc_pass;
        cg.async_lower = &async_pass;
        cg.src_path = src_path;
        cg.target = target;
        cg.load_chunk = load_chunk;
        cg.lib_mode = lib_mode;
        cg.duo_mode = ps.sem.duo_mode;
        cg.emit_module(&ps.mod) catch |e| {
            std.debug.print("codegen error: {}\n", .{e});
            std.process.exit(1);
        };
        try fw.interface.flush();
    }

    // Build the base set of CC flags shared between all compile passes.
    var base_cc_flags = base: {
        var args: std.ArrayList([]const u8) = .empty;
        if (is_wasm) {
            try args.appendSlice(alloc, &.{
                "zig",                   "cc",
                "--target=wasm32-wasi",  opt,
                "-ffast-math",           "-flto",
                "-fomit-frame-pointer",  "-funroll-loops",
                "-ffp-contract=fast",    "-fno-trapping-math",
                "-fno-math-errno",           "-Wl,--no-entry",
                "-Wl,--gc-sections",         "-Wl,--strip-debug",
                "-std=gnu99",                "-lm",
                "-Wno-deprecated-declarations",
            });
            if (lib_mode) {
                try args.append(alloc, "-Wl,--export-dynamic");
            } else {
                try args.append(alloc, "-Wl,--export=main");
            }
            if (shared_mem) {
                try args.appendSlice(alloc, &.{ "-matomics", "-mbulk-memory", "-mmutable-globals" });
            }
        } else {
            if (comptime @import("builtin").os.tag == .macos) {
                try args.appendSlice(alloc, &.{ "xcrun", cc });
            } else {
                try args.append(alloc, cc);
            }
            try args.appendSlice(alloc, &.{
                opt,
                "-ffast-math",
                "-DNDEBUG",
                "-march=native",
                "-mtune=native",
                "-flto",
                "-fstrict-aliasing",
                "-fomit-frame-pointer",
                "-funroll-loops",
                "-ffp-contract=fast",
                "-fno-trapping-math",
                "-fno-math-errno",
                "-ffunction-sections",
                "-fdata-sections",
                "-Wl,-dead_strip",
                "-std=gnu99",
                "-lm",
            });
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
        try run_child_process(io, p2_args.items, "C compiler (PGO pass 2)", silent);
    } else {
        // Normal single-pass compile.
        var cc_args: std.ArrayList([]const u8) = .empty;
        defer cc_args.deinit(alloc);
        try cc_args.appendSlice(alloc, base_cc_flags.items);
        try cc_args.appendSlice(alloc, &.{ "-o", out_path, c_path });
        try run_child_process(io, cc_args.items, "C compiler", silent);
    }

    if (run_after and !is_wasm) {
        const run_argv = [_][]const u8{out_path};
        var run_child = try std.process.spawn(io, .{
            .argv = &run_argv,
            .stdin = .inherit,
            .stdout = .inherit,
            .stderr = .inherit,
        });
        const run_term = try run_child.wait(io);
        switch (run_term) {
            .exited => |code| std.process.exit(code),
            .signal => std.process.exit(128),
            else => {
                std.debug.print("program terminated abnormally\n", .{});
                std.process.exit(1);
            },
        }
    }
}

fn do_completion(io: Io, args: []const [:0]const u8) !void {
    const shell = if (args.len > 0) args[0] else {
        std.debug.print("error: completion requires a shell: bash, zsh, fish, or nu\n", .{});
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
        std.debug.print("error: unsupported shell '{s}' (expected bash, zsh, fish, or nu)\n", .{shell});
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
    \\    local commands="init build compile run check dump-c completion help"
    \\    local options="-o -O0 -O1 -O2 -O3 --cc --target --load-chunk --lib --pgo --shared-memory -v --verbose -h --help"
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
    \\        --cc|-o) return 0 ;;
    \\    esac
    \\
    \\    case "${COMP_WORDS[1]}" in
    \\        compile|run|check|dump-c)
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
    \\    'init:create a new Duo project'
    \\    'build:build the default or named build.duo target'
    \\    'compile:compile .duo/.lua to a native binary'
    \\    'run:compile and run a file or build target'
    \\    'check:type-check only'
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
    \\    '(-v --verbose)'{-v,--verbose}'[show compiler warnings]'
    \\    '(-h --help)'{-h,--help}'[show help]'
    \\  )
    \\  if (( CURRENT == 2 )); then
    \\    _describe 'command' commands
    \\  else
    \\    case "${words[2]}" in
    \\      completion) _values 'shell' bash zsh fish nu ;;
    \\      compile|run|check|dump-c) _arguments $opts '*:source:_files -g "*.(duo|lua)"' ;;
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
    \\complete -c duo -n '__fish_use_subcommand' -a 'init' -d 'Create a new Duo project'
    \\complete -c duo -n '__fish_use_subcommand' -a 'build' -d 'Build the default or named build.duo target'
    \\complete -c duo -n '__fish_use_subcommand' -a 'compile' -d 'Compile .duo/.lua to a native binary'
    \\complete -c duo -n '__fish_use_subcommand' -a 'run' -d 'Compile and run a file or build target'
    \\complete -c duo -n '__fish_use_subcommand' -a 'check' -d 'Type-check only'
    \\complete -c duo -n '__fish_use_subcommand' -a 'dump-c' -d 'Print generated C'
    \\complete -c duo -n '__fish_use_subcommand' -a 'completion' -d 'Generate shell completions'
    \\complete -c duo -n '__fish_use_subcommand' -a 'help' -d 'Show help'
    \\complete -c duo -s o -r -d 'Output binary name'
    \\complete -c duo -l cc -r -d 'C compiler'
    \\complete -c duo -l target -x -a 'native wasm32-wasi' -d 'Compilation target'
    \\complete -c duo -l load-chunk -d 'Compile as shared library for load()'
    \\complete -c duo -l lib -d 'Compile as library'
    \\complete -c duo -l pgo -d 'Profile-guided optimization'
    \\complete -c duo -l shared-memory -d 'Enable WASM shared memory'
    \\complete -c duo -s v -l verbose -d 'Show compiler warnings'
    \\complete -c duo -s h -l help -d 'Show help'
    \\complete -c duo -n '__fish_seen_subcommand_from completion' -x -a 'bash zsh fish nu'
    \\
;

const nu_completion =
    \\# nushell completion for duo
    \\def "nu-complete duo commands" [] {
    \\  [init build compile run check dump-c completion help]
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
        std.debug.print("monomorphization error: {}\n", .{e});
        std.process.exit(1);
    };

    var arc_pass = Arc.ArcPass.init(alloc, &ps.sem.type_map);
    defer arc_pass.deinit();
    arc_pass.run(&ps.mod) catch |e| {
        std.debug.print("ARC analysis error: {}\n", .{e});
        std.process.exit(1);
    };

    const is_wasm_target = std.mem.eql(u8, target, "wasm32-wasi");
    const threaded = false;
    AsyncLower.validateTarget(is_wasm_target, threaded) catch {
        std.debug.print("error: the threaded scheduler is not supported on the wasm32-wasi target\n", .{});
        std.process.exit(1);
    };
    var async_pass = AsyncLower.AsyncLower.init(alloc, &ps.sem.type_map);
    defer async_pass.deinit();
    async_pass.run(&ps.mod) catch |e| {
        std.debug.print("async lowering error: {}\n", .{e});
        std.process.exit(1);
    };

    const stdout = Io.File.stdout();
    var buf: [65536]u8 = undefined;
    var fw: Io.File.Writer = .init(stdout, io, &buf);
    var cg = CodeGen.init(alloc, io, &ps.sem.type_map, &ps.sem.module_globals, &fw.interface);
    cg.mono = &mono;
    cg.arc = &arc_pass;
    cg.async_lower = &async_pass;
    cg.src_path = src_path;
    cg.target = target;
    cg.emit_module(&ps.mod) catch |e| {
        std.debug.print("codegen error: {}\n", .{e});
        std.process.exit(1);
    };
    try fw.interface.flush();
}
