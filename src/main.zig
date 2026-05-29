const std = @import("std");
const Io = std.Io;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;
const CodeGen = @import("codegen.zig").CodeGen;

const usage =
    \\usage: duo <command> [options] <file>
    \\
    \\commands:
    \\  compile  <file>   compile .duo/.lua to a native binary
    \\  run      <file>   compile and run immediately
    \\  check    <file>   type-check only, no output
    \\  dump-c   <file>   print generated C to stdout
    \\
    \\options:
    \\  -o <name>         output binary name (default: <stem>.out)
    \\  -O<n>             clang optimisation level (default: -O3)
    \\  --cc <path>       C compiler (default: clang)
    \\  --load-chunk      compile as shared library for runtime load() (not for run)
    \\  -v, --verbose     show C compiler warnings (run only; off by default)
    \\
;

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(alloc);

    if (args.len < 3) {
        std.debug.print("{s}", .{usage});
        std.process.exit(1);
    }

    const cmd = args[1];
    var input_file: ?[]const u8 = null;
    var output_file: ?[]const u8 = null;
    var cc: []const u8 = "clang";
    var opt_level: []const u8 = "-O3";
    var verbose = false;
    var load_chunk = false;

    var i: usize = 2;
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
        } else if (std.mem.eql(u8, arg, "--load-chunk")) {
            load_chunk = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (arg.len > 0 and arg[0] != '-') {
            input_file = arg;
        }
    }

    const file = input_file orelse {
        std.debug.print("error: no input file\n", .{});
        std.process.exit(1);
    };

    const out = output_file orelse try std.fmt.allocPrint(
        alloc,
        "./{s}.out",
        .{std.fs.path.stem(file)},
    );

    if (std.mem.eql(u8, cmd, "compile")) {
        try do_compile(alloc, io, file, out, cc, opt_level, false, false, false, load_chunk);
    } else if (std.mem.eql(u8, cmd, "run")) {
        try do_compile(alloc, io, file, out, cc, opt_level, true, false, verbose, false);
    } else if (std.mem.eql(u8, cmd, "check")) {
        try do_compile(alloc, io, file, out, cc, opt_level, false, true, false, false);
    } else if (std.mem.eql(u8, cmd, "dump-c")) {
        try do_dump_c(alloc, io, file);
    } else {
        std.debug.print("error: unknown command '{s}'\n{s}", .{ cmd, usage });
        std.process.exit(1);
    }
}

fn read_source(alloc: std.mem.Allocator, io: Io, path: []const u8) ![]u8 {
    const cwd = Io.Dir.cwd();
    return Io.Dir.readFileAlloc(cwd, io, path, alloc, .unlimited);
}

const ParsedModule = struct {
    mod: @import("ast.zig").Module,
    sem: Sema,
};

fn is_lua_source_path(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".lua");
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

fn do_compile(
    alloc: std.mem.Allocator,
    io: Io,
    src_path: []const u8,
    out_path: []const u8,
    cc: []const u8,
    opt: []const u8,
    run_after: bool,
    check_only: bool,
    verbose: bool,
    load_chunk: bool,
) !void {
    var ps = try parse_and_check(alloc, io, src_path);
    defer ps.sem.deinit();

    if (check_only) {
        std.debug.print("OK\n", .{});
        return;
    }

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
        cg.src_path = src_path;
        cg.load_chunk = load_chunk;
        cg.emit_module(&ps.mod) catch |e| {
            std.debug.print("codegen error: {}\n", .{e});
            std.process.exit(1);
        };
        try fw.interface.flush();
    }

    var cc_args: std.ArrayList([]const u8) = .empty;
    defer cc_args.deinit(alloc);
    try cc_args.appendSlice(alloc, &.{
        cc,
        opt,
        "-ffast-math",
        "-march=native",
        "-flto",
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
    if (load_chunk) {
        try cc_args.append(alloc, "-fPIC");
        if (@import("builtin").os.tag == .macos) {
            try cc_args.append(alloc, "-dynamiclib");
        } else {
            try cc_args.append(alloc, "-shared");
        }
    }
    if (run_after and !verbose) try cc_args.append(alloc, "-w");
    try cc_args.appendSlice(alloc, &.{ "-o", out_path, c_path });

    var cc_child = try std.process.spawn(io, .{
        .argv = cc_args.items,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const cc_term = try cc_child.wait(io);
    switch (cc_term) {
        .exited => |code| if (code != 0) {
            std.debug.print("C compiler failed (exit {})\n", .{code});
            std.process.exit(1);
        },
        else => {
            std.debug.print("C compiler terminated abnormally\n", .{});
            std.process.exit(1);
        },
    }

    if (run_after) {
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

fn do_dump_c(alloc: std.mem.Allocator, io: Io, src_path: []const u8) !void {
    var ps = try parse_and_check(alloc, io, src_path);
    defer ps.sem.deinit();

    const stdout = Io.File.stdout();
    var buf: [65536]u8 = undefined;
    var fw: Io.File.Writer = .init(stdout, io, &buf);
    var cg = CodeGen.init(alloc, io, &ps.sem.type_map, &ps.sem.module_globals, &fw.interface);
    cg.src_path = src_path;
    cg.emit_module(&ps.mod) catch |e| {
        std.debug.print("codegen error: {}\n", .{e});
        std.process.exit(1);
    };
    try fw.interface.flush();
}
