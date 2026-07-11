const std = @import("std");
const Io = std.Io;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;
const CodeGen = @import("codegen.zig").CodeGen;
const Mono = @import("mono.zig");
const MacroExpand = @import("macro_expand.zig");
const Arc = @import("arc.zig");
const AsyncLower = @import("async_lower.zig");
const escape = @import("escape.zig");
const PrettyPrinter = @import("pretty.zig").PrettyPrinter;
const term = @import("term.zig");

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
    if (map.get("DUO_TRACE")) |v| {
        if (env_value_truthy(v)) term.trace = true;
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
}

fn apply_cli_flags(trace_flag: bool, info_flag: bool, hints_flag: bool, plain_diag: bool) void {
    if (trace_flag) term.trace = true;
    if (info_flag) term.info = true;
    if (hints_flag) term.hints = true;
    if (plain_diag) term.plain = true;
}

fn start_trace_timer() ?u64 {
    if (!term.trace) return null;
    return std.time.nanoTimestamp();
}

fn trace_phase(start_ns: *const u64, label: []const u8, detail: ?[]const u8) void {
    const elapsed_ms = @divTrunc(@as(u64, @intCast(std.time.nanoTimestamp() -% start_ns.*)), std.time.ns_per_ms);
    term.traceDone(label, elapsed_ms, detail);
}

const usage =
    \\usage: duo [command] [options] [file]
    \\
    \\commands:
    \\  shell              start the interactive Duo shell (default)
    \\  init       [name]   create a new Duo project
    \\  build      [target] build the default or named target from build.duo
    \\  compile    <file>   compile .duo/.lua to a native binary
    \\  run        [file]   compile and run immediately, or run build.duo target
    \\  check      <file>   type-check only, no output
    \\  fmt        <file>   format a .duo/.lua file
    \\  test       <file>   run @test / @bench functions in a .duo file
    \\  bench      <file>   run only @bench-marked functions
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
    \\  --link <lib>      link against a C library (e.g. --link raylib; repeatable)
    \\  -v, --verbose     show C compiler warnings (run only; off by default)
    \\  --trace           show compiler pipeline steps and timings
    \\  --info            show informational compiler notes (opt-in)
    \\  --hints           show compiler hints and suggestions (opt-in)
    \\  --filter <pat>    run only tests whose name contains <pat>
    \\
;

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    term.init(init.io);
    apply_env_flags(init);
    const io = init.io;
    const args = try init.minimal.args.toSlice(alloc);

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
    var load_chunk = false;
    var lib_mode = false;
    var pgo = false;
    var shared_mem = false;
    var test_filter: ?[]const u8 = null;
    var link_flags: std.ArrayList([]const u8) = .empty;
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
        } else if (std.mem.eql(u8, arg, "--link") and i + 1 < args.len) {
            i += 1;
            try link_flags.append(alloc, args[i]);
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--trace")) {
            trace_flag = true;
        } else if (std.mem.eql(u8, arg, "--info")) {
            info_flag = true;
        } else if (std.mem.eql(u8, arg, "--hints")) {
            hints_flag = true;
        } else if (std.mem.eql(u8, arg, "--plain-diagnostics")) {
            plain_diag = true;
        } else if (std.mem.eql(u8, arg, "--filter") and i + 1 < args.len) {
            i += 1;
            test_filter = args[i];
        } else if (arg.len > 0 and arg[0] != '-') {
            input_file = arg;
        }
    }

    apply_cli_flags(trace_flag, info_flag, hints_flag, plain_diag);

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

    if (std.mem.eql(u8, cmd, "build")) {
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

    if (std.mem.eql(u8, cmd, "test") or std.mem.eql(u8, cmd, "bench")) {
        const file = input_file orelse {
            term.err("no input file (duo {s} <file.duo>)", .{cmd});
            std.process.exit(1);
        };
        const out = output_file orelse out: {
            const stem = std.fs.path.stem(file);
            break :out try std.fmt.allocPrint(alloc, "/tmp/duo_{s}.test.out", .{stem});
        };
        const bench_only = std.mem.eql(u8, cmd, "bench");
        term.banner(if (bench_only) "bench" else "test");
        term.kv("source", file);
        try do_compile(alloc, io, file, out, cc, opt_level, target, true, false, verbose, false, false, false, false, true, bench_only, test_filter, link_flags.items);
        return;
    }

    const file = input_file orelse {
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
        try do_fmt(alloc, io, file);
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
    link: []const []const u8 = &.{},
    test_mode: bool = false,
    bench_mode: bool = false,
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

fn firstListField(alloc: std.mem.Allocator, src: []const u8, field: []const u8) ![]const []const u8 {
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
                if (i < src.len and src[i] == '{') {
                    const body = matchingTable(src, i) orelse return &.{};
                    var result: std.ArrayList([]const u8) = .empty;
                    var j: usize = 0;
                    while (j < body.len) {
                        while (j < body.len and std.ascii.isWhitespace(body[j])) : (j += 1) {}
                        if (j >= body.len) break;
                        if (body[j] == '"') {
                            j += 1;
                            const start = j;
                            while (j < body.len and body[j] != '"') : (j += 1) {}
                            if (j < body.len) {
                                try result.append(alloc, body[start..j]);
                                j += 1;
                            }
                        } else {
                            break;
                        }
                    }
                    return result.items;
                }
            }
        }
        at = pos + field.len;
    }
    return &.{};
}

fn parseTargetBlock(alloc: std.mem.Allocator, block: []const u8, kind: enum { exe, lib, test, bench }) ?BuildTarget {
    const src = firstStringField(block, "src") orelse return null;
    const name = firstStringField(block, "name") orelse std.fs.path.stem(src);
    const lib_mode = kind == .lib;
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
        .link = firstListField(alloc, block, "link") catch &.{},
        .test_mode = kind == .test,
        .bench_mode = kind == .bench,
    };
}

fn readBuildProjectDefault(src: []const u8) ?[]const u8 {
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, src, at, "build.project")) |pos| {
        const rel_open = std.mem.indexOfScalar(u8, src[pos..], '{') orelse {
            at = pos + "build.project".len;
            continue;
        };
        const open = pos + rel_open;
        const block = matchingTable(src, open) orelse {
            at = pos + "build.project".len;
            continue;
        };
        if (firstStringField(block, "default")) |d| return d;
        at = open + block.len + 2;
    }
    return firstStringField(src, "default");
}

fn readBuildTarget(alloc: std.mem.Allocator, io: Io, requested: ?[]const u8) !BuildTarget {
    const src = read_source(alloc, io, "build.duo") catch |e| {
        term.err("unable to read build.duo: {}", .{e});
        term.print("run `duo init` to create one", .{});
        std.process.exit(1);
    };
    const target_name = requested orelse readBuildProjectDefault(src);
    var first: ?BuildTarget = null;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, src, at, "build.")) |pos| {
        const slice = src[pos..];
        const kind: enum { exe, lib, test, bench, skip } = blk: {
            if (std.mem.startsWith(u8, slice, "build.exe")) break :blk .exe;
            if (std.mem.startsWith(u8, slice, "build.lib")) break :blk .lib;
            if (std.mem.startsWith(u8, slice, "build.test")) break :blk .test;
            if (std.mem.startsWith(u8, slice, "build.bench")) break :blk .bench;
            break :blk .skip;
        };
        if (kind == .skip) {
            at = pos + "build.".len;
            continue;
        }
        const rel_open = std.mem.indexOfScalar(u8, slice, '{') orelse break;
        const open = pos + rel_open;
        const block = matchingTable(src, open) orelse break;
        if (parseTargetBlock(alloc, block, kind)) |t| {
            if (first == null) first = t;
            if (target_name) |want| {
                if (std.mem.eql(u8, t.name, want)) return t;
            }
        }
        at = open + block.len + 2;
    }
    if (target_name) |want| {
        term.err("target '{s}' not found in build.duo", .{want});
        std.process.exit(1);
    }
    return first orelse {
        term.err("build.duo does not define build.exe({{ src = \"...\" }}) or build.lib({{ src = \"...\" }})", .{});
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
            term.err("refusing to overwrite existing {s}", .{path});
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
    term.banner("Duo project created");
    term.kv("name", name);
    term.section("files");
    term.kv("•", "src/main.duo");
    term.kv("•", "build.duo");
    term.kv("•", "zig-out/bin/");
    term.divider();
    term.dim("next: duo build   # compile default target", .{});
    term.dim("       duo run    # build and run", .{});
    term.dim("       duo shell  # interactive REPL", .{});
    term.ok("ready — project '{s}'", .{name});
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
    if (line[0] == '@' or std.mem.startsWith(u8, line, "--")) return true;
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

fn run_shell_line(alloc: std.mem.Allocator, io: Io, raw_line: []const u8, counter: *usize, verbose: bool) !bool {
    const line = std.mem.trim(u8, raw_line, " \t\r\n");
    if (line.len == 0) return true;
    if (std.mem.eql(u8, line, ":quit") or
        std.mem.eql(u8, line, ":exit") or
        std.mem.eql(u8, line, "quit") or
        std.mem.eql(u8, line, "exit"))
    {
        return false;
    }
    if (std.mem.eql(u8, line, ":help")) {
        term.section("shell commands");
        term.kv("expr", "evaluate and print (e.g. 1 + 2)");
        term.kv("stmt", "compile and run Duo code");
        term.kv("!cmd", "run a host shell command");
        term.kv(":quit / :exit", "leave the shell");
        return true;
    }
    if (line[0] == '!' and line.len > 1) {
        try run_host_shell_command(io, std.mem.trim(u8, line[1..], " \t"));
        return true;
    }

    const source = if (shellLineIsStatement(line))
        try std.fmt.allocPrint(alloc, "{s}\n", .{line})
    else
        try std.fmt.allocPrint(alloc, "print({s})\n", .{line});
    const src_path = try std.fmt.allocPrint(alloc, "/tmp/duo_shell_{d}.duo", .{counter.*});
    const out_path = try std.fmt.allocPrint(alloc, "/tmp/duo_shell_{d}.out", .{counter.*});
    counter.* += 1;

    const cwd = Io.Dir.cwd();
    try Io.Dir.writeFile(cwd, io, .{ .sub_path = src_path, .data = source });
    try do_compile(alloc, io, src_path, out_path, "clang", "-O3", "native", false, false, verbose, false, false, false, false, false, false, null, &.{});
    try run_shell_binary(io, out_path);
    return true;
}

fn do_shell(alloc: std.mem.Allocator, io: Io, verbose: bool) !void {
    term.banner("Duo shell");
    term.dim("expressions print results · statements compile+run · :help for commands", .{});
    var line: std.ArrayList(u8) = .empty;
    defer line.deinit(alloc);
    var counter: usize = 0;
    var buf: [1024]u8 = undefined;

    if (term.color) {
        term.printRaw("\x1b[1;36mduo\x1b[0m\x1b[2m>\x1b[0m ", .{});
    } else {
        term.printRaw("duo> ", .{});
    }
    while (true) {
        const n = try std.posix.read(std.posix.STDIN_FILENO, buf[0..]);
        if (n == 0) {
            if (line.items.len > 0) {
                _ = try run_shell_line(alloc, io, line.items, &counter, verbose);
            }
            break;
        }
        for (buf[0..n]) |b| {
            if (b == '\n') {
                const keep_running = try run_shell_line(alloc, io, line.items, &counter, verbose);
                line.clearRetainingCapacity();
                if (!keep_running) return;
                if (term.color) {
                    term.printRaw("\x1b[1;36mduo\x1b[0m\x1b[2m>\x1b[0m ", .{});
                } else {
                    term.printRaw("duo> ", .{});
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
    const t = try readBuildTarget(alloc, io, requested);
    const target = t.target orelse target_arg;
    const target_lib_mode = lib_mode_arg or t.lib_mode;
    if (run_after and target_lib_mode) {
        term.err("target '{s}' is a library and cannot be run", .{t.name});
        std.process.exit(1);
    }
    const out = output_file orelse t.out orelse out: {
        const stem = std.fs.path.stem(t.src);
        if (std.mem.eql(u8, target, "wasm32-wasi")) break :out try std.fmt.allocPrint(alloc, "zig-out/bin/{s}.wasm", .{stem});
        break :out try std.fmt.allocPrint(alloc, "zig-out/bin/{s}", .{stem});
    };
    term.banner("duo build");
    term.kv("target", t.name);
    term.kv("source", t.src);
    term.kv("output", out);
    if (term.trace) term.traceStep("reading build.duo target", .{});
    try ensureDirForPath(io, out);
    // Merge CLI link flags with link flags from build.duo
    const merged_link = if (t.link.len > 0) blk: {
        var m: std.ArrayList([]const u8) = .empty;
        try m.appendSlice(alloc, link_flags_arg);
        try m.appendSlice(alloc, t.link);
        break :blk m.items;
    } else link_flags_arg;
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
        t.test_mode,
        t.bench_mode,
        null,
        merged_link,
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
    sem.hints_enabled = term.hints;
    sem.info_enabled = term.info;
    var expander = MacroExpand.Expander.init(alloc);
    defer expander.deinit();
    expander.expandModule(&mod) catch |e| {
        term.err("macro expansion error: {s}", .{@errorName(e)});
        std.process.exit(1);
    };
    sem.check_module(&mod) catch |e| {
        term.err("sema error: {}", .{e});
        std.process.exit(1);
    };
    if (sem.errors > 0) {
        term.err("{d} error(s)", .{sem.errors});
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
    const compile_started = if (term.trace) std.time.nanoTimestamp() else 0;

    if (term.trace) {
        term.banner("compile");
        term.kv("source", src_path);
        term.kv("output", out_path);
        term.kv("target", target);
        term.traceStep("parse + sema", .{});
    }

    var phase_timer = start_trace_timer();
    var ps = try parse_and_check(alloc, io, src_path);
    defer ps.sem.deinit();
    if (phase_timer) |*t| trace_phase(t, "parse + sema", null);

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

    phase_timer = start_trace_timer();
    if (term.trace) term.traceStep("monomorphize", .{});
    // Monomorphization: expand generic functions into concrete specializations
    // before codegen (Task 8.3). Runs on every compile so generic instantiation
    // is exercised even before codegen consumes the specializations (Task 12.1).
    var mono = Mono.Monomorphizer.init(alloc, &ps.sem.type_map);
    defer mono.deinit();
    mono.run(&ps.mod) catch |e| {
        term.err("monomorphization error: {}", .{e});
        std.process.exit(1);
    };
    if (phase_timer) |*t| {
        const detail = try std.fmt.allocPrint(alloc, "{d} specialization(s)", .{mono.count()});
        defer alloc.free(detail);
        trace_phase(t, "monomorphize", detail);
    }

    phase_timer = start_trace_timer();
    if (term.trace) term.traceStep("ARC analysis", .{});
    // ARC insertion: decide retain/release/close points for heap values, after
    // monomorphization and before codegen (Task 9.4).
    var arc_pass = Arc.ArcPass.init(alloc, &ps.sem.type_map);
    defer arc_pass.deinit();
    // Populate escaping set from sema escape analysis.
    // Only variables captured by closures are marked as escaping.
    // All other locals are non-escaping and get ARC pruned.
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
    if (phase_timer) |*t| {
        const detail = try std.fmt.allocPrint(alloc, "{d} annotation(s)", .{arc_pass.annotations.items.len});
        defer alloc.free(detail);
        trace_phase(t, "ARC analysis", detail);
    }

    phase_timer = start_trace_timer();
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
    var async_pass = AsyncLower.AsyncLower.init(alloc, &ps.sem.type_map);
    defer async_pass.deinit();
    async_pass.run(&ps.mod) catch |e| {
        term.err("async lowering error: {}", .{e});
        std.process.exit(1);
    };
    if (phase_timer) |*t| {
        const detail = try std.fmt.allocPrint(alloc, "{d} async function(s)", .{async_pass.count()});
        defer alloc.free(detail);
        trace_phase(t, "async lower", detail);
    }

    const is_wasm = std.mem.eql(u8, target, "wasm32-wasi");

    const c_path = try std.fmt.allocPrint(alloc, "/tmp/duo_{s}.c", .{
        std.fs.path.stem(src_path),
    });

    phase_timer = start_trace_timer();
    if (term.trace) term.traceStep("codegen", .{});
    {
        const cwd = Io.Dir.cwd();
        const cf = try Io.Dir.createFile(cwd, io, c_path, .{});
        defer Io.File.close(cf, io);

        var buf: [65536]u8 = undefined;
        var fw: Io.File.Writer = .init(cf, io, &buf);
        var cg = CodeGen.init(alloc, io, &ps.sem.type_map, &ps.sem.module_globals, &fw.interface, ps.sem.next_closure_id);
        cg.mono = &mono;
        cg.arc = &arc_pass;
        cg.async_lower = &async_pass;
        cg.src_path = src_path;
        cg.target = target;
        cg.load_chunk = load_chunk;
        cg.lib_mode = lib_mode;
        cg.duo_mode = ps.sem.duo_mode;
        cg.test_mode = test_mode;
        cg.bench_mode = bench_mode;
        cg.test_filter = test_filter;
        cg.test_entries = ps.sem.test_entries.items;
        cg.emit_module(&ps.mod) catch |e| {
            term.err("codegen error: {}", .{e});
            std.process.exit(1);
        };
        try fw.interface.flush();
    }
    if (phase_timer) |*t| trace_phase(t, "codegen", c_path);

    // Build the base set of CC flags shared between all compile passes.
    var base_cc_flags = base: {
        var args: std.ArrayList([]const u8) = .empty;
        if (is_wasm) {
            try args.appendSlice(alloc, &.{
                "zig",                          "cc",
                "--target=wasm32-wasi",         opt,
                "-ffast-math",                  "-flto",
                "-fomit-frame-pointer",         "-funroll-loops",
                "-ffp-contract=fast",           "-fno-trapping-math",
                "-fno-math-errno",              "-Wl,--no-entry",
                "-Wl,--gc-sections",            "-Wl,--strip-debug",
                "-std=gnu99",                   "-lm",
                "-Wno-deprecated-declarations",
            });
            if (lib_mode) {
                try args.appendSlice(alloc, &.{
                    "-mexec-model=reactor",
                    "-Wl,--export-dynamic",
                });
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
    phase_timer = start_trace_timer();
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
    if (phase_timer) |*t| trace_phase(t, "link", out_path);

    if (term.trace) {
        const total_ms = @divTrunc(@as(u64, @intCast(std.time.nanoTimestamp() -% compile_started)), std.time.ns_per_ms);
        term.traceSummary("total", "{d} ms", .{total_ms});
    }

    if (!run_after) {
        term.ok("✓ {s}", .{out_path});
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
    \\    local options="-o -O0 -O1 -O2 -O3 --cc --target --load-chunk --lib --pgo --shared-memory --link --filter --trace --info --hints --plain-diagnostics -v --verbose -h --help"
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
    var cg = CodeGen.init(alloc, io, &ps.sem.type_map, &ps.sem.module_globals, &fw.interface, ps.sem.next_closure_id);
    cg.mono = &mono;
    cg.arc = &arc_pass;
    cg.async_lower = &async_pass;
    cg.src_path = src_path;
    cg.target = target;
    cg.emit_module(&ps.mod) catch |e| {
        term.err("codegen error: {}", .{e});
        std.process.exit(1);
    };
    try fw.interface.flush();
}

fn do_fmt(alloc: std.mem.Allocator, io: Io, src_path: []const u8) !void {
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
