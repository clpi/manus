//! Parse preprocessed C headers into function declarations for `@ffi_gen`.
const std = @import("std");
const host_run = @import("host_run.zig");

pub const CDecl = struct {
    name: []const u8,
    ret_type: []const u8,
    params: []const u8,
};

const clang_limits: host_run.CommandLimits = .{
    .stdout_bytes = 128 * 1024 * 1024,
    .stderr_bytes = 1024 * 1024,
    .read_timeout_seconds = 30,
};

/// Run `clang -E -P` on a header and return preprocessed source.
pub fn preprocessHeader(alloc: std.mem.Allocator, header: []const u8) ?[]const u8 {
    var threaded = std.Io.Threaded.init(alloc, .{});
    const io = threaded.io();
    const existing = existing: {
        std.Io.Dir.cwd().access(io, header, .{ .read = true }) catch |err| switch (err) {
            error.FileNotFound => break :existing false,
            else => return null,
        };
        break :existing true;
    };

    var owned_header: ?[]u8 = null;
    defer if (owned_header) |path| alloc.free(path);

    const header_arg: []const u8 = if (existing) path: {
        if (std.fs.path.isAbsolute(header)) break :path header;
        var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
        const cwd_len = std.Io.Dir.cwd().realPath(io, &cwd_buf) catch return null;
        owned_header = std.fs.path.join(alloc, &.{ cwd_buf[0..cwd_len], header }) catch return null;
        break :path owned_header.?;
    } else name: {
        if (!isHeaderSearchName(header)) return null;
        break :name header;
    };

    const clang = [_][]const u8{ "clang", "-E", "-P", "-x", "c", "-include", header_arg, "-" };
    if (commandAvailable(alloc, "clang")) return preprocessWithArgs(alloc, &clang);
    // Clang is not part of every admitted host toolchain. `cc -E` supplies the
    // same preprocessing observation and still receives the header as argv data.
    // Fall back only when clang is absent, never when it rejected the source.
    const cc = [_][]const u8{ "cc", "-E", "-P", "-x", "c", "-include", header_arg, "-" };
    return preprocessWithArgs(alloc, &cc);
}

fn commandAvailable(alloc: std.mem.Allocator, name: []const u8) bool {
    const out = host_run.runHostCommandArgs(alloc, &.{ name, "--version" }) orelse return false;
    defer alloc.free(out.stdout);
    defer alloc.free(out.stderr);
    return out.ok;
}

fn isHeaderSearchName(header: []const u8) bool {
    if (header.len == 0 or header[0] == '-' or header[0] == '@') return false;
    for (header) |byte| switch (byte) {
        'a'...'z', 'A'...'Z', '0'...'9', '_', '.', '/', '+', '-' => {},
        else => return false,
    };
    return true;
}

fn preprocessWithArgs(alloc: std.mem.Allocator, argv: []const []const u8) ?[]const u8 {
    const out = host_run.runHostCommandArgsLimited(alloc, argv, clang_limits) orelse return null;
    alloc.free(out.stderr);
    if (!out.ok or out.stdout.len == 0) {
        alloc.free(out.stdout);
        return null;
    }
    return out.stdout;
}

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn trimLeftBytes(s: []const u8, chars: []const u8) []const u8 {
    var i: usize = 0;
    while (i < s.len and std.mem.indexOfScalar(u8, chars, s[i]) != null) : (i += 1) {}
    return s[i..];
}

fn skipWs(s: []const u8) []const u8 {
    return trimLeftBytes(s, " \t\r\n");
}

fn skipLine(s: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, s, '\n')) |nl| return s[nl + 1 ..];
    return "";
}

fn skipPreprocessor(s: []const u8) []const u8 {
    var rest = skipWs(s);
    while (rest.len > 0 and rest[0] == '#') {
        rest = skipLine(rest);
        rest = skipWs(rest);
    }
    return rest;
}

fn readIdent(s: []const u8) struct { name: []const u8, rest: []const u8 } {
    var rest = skipWs(s);
    if (rest.len == 0 or !isIdentStart(rest[0])) return .{ .name = "", .rest = rest };
    var i: usize = 1;
    while (i < rest.len and isIdentChar(rest[i])) : (i += 1) {}
    return .{ .name = rest[0..i], .rest = rest[i..] };
}

fn skipTypedefPrefix(s: []const u8) []const u8 {
    var rest = skipWs(s);
    while (true) {
        const id = readIdent(rest);
        if (id.name.len == 0) return rest;
        rest = skipWs(id.rest);
        if (std.mem.eql(u8, id.name, "typedef") or
            std.mem.eql(u8, id.name, "extern") or
            std.mem.eql(u8, id.name, "static") or
            std.mem.eql(u8, id.name, "inline") or
            std.mem.eql(u8, id.name, "const") or
            std.mem.eql(u8, id.name, "volatile") or
            std.mem.eql(u8, id.name, "unsigned") or
            std.mem.eql(u8, id.name, "signed") or
            std.mem.eql(u8, id.name, "long") or
            std.mem.eql(u8, id.name, "short") or
            std.mem.eql(u8, id.name, "struct") or
            std.mem.eql(u8, id.name, "enum"))
        {
            if (std.mem.eql(u8, id.name, "struct") or std.mem.eql(u8, id.name, "enum")) {
                const tag = readIdent(rest);
                rest = skipWs(tag.rest);
            }
            continue;
        }
        return id.rest;
    }
}

/// Skip the specifier clauses a C declaration may carry BETWEEN its parameter
/// list and its `;` or `{`.
///
/// This is not a nicety. `parseFunctionDecls` required `)` to be followed
/// immediately by `;` or `{`, and glibc declares essentially everything as
///
///     extern size_t strlen (const char *__s)
///          __attribute__ ((__nothrow__ )) __attribute__ ((__pure__))
///          __attribute__ ((__nonnull__ (1)));
///
/// so every attributed declaration was silently DROPPED and `@comp.ffi` over a
/// system header returned a short list rather than an error. It read as working
/// because Darwin's headers declare `size_t strlen(const char *__s);` with the
/// availability macros consumed by `-P`, so the shape never arose on the host
/// this code was written on. `__asm__` is in the same position and same
/// business: glibc uses it to RENAME the symbol (`__asm__ ("strtof64")`), and a
/// rename we cannot honour must drop the declaration rather than emit an
/// `extern` for a symbol the library does not export under that name.
const TrailingSpecifiers = struct {
    rest: []const u8,
    /// An asm label renames the symbol. The caller must refuse the declaration
    /// instead of emitting a plausible-looking `extern` that will not link.
    renamed: bool,
};

fn skipTrailingSpecifiers(s: []const u8) TrailingSpecifiers {
    var rest = skipWs(s);
    var renamed = false;
    while (true) {
        const id = readIdent(rest);
        if (id.name.len == 0) break;
        const is_attribute = std.mem.eql(u8, id.name, "__attribute__") or
            std.mem.eql(u8, id.name, "__attribute") or
            std.mem.eql(u8, id.name, "__extension__");
        const is_asm = std.mem.eql(u8, id.name, "__asm__") or
            std.mem.eql(u8, id.name, "__asm") or
            std.mem.eql(u8, id.name, "asm");
        if (!is_attribute and !is_asm) break;
        const args = skipWs(id.rest);
        if (args.len == 0 or args[0] != '(') {
            // A bare `__extension__` carries no parenthesised payload.
            if (std.mem.eql(u8, id.name, "__extension__")) {
                rest = args;
                continue;
            }
            break;
        }
        const close = findMatchingParen(args) orelse break;
        if (is_asm) renamed = true;
        rest = skipWs(args[close + 1 ..]);
    }
    return .{ .rest = rest, .renamed = renamed };
}

/// Drop the storage-class and linkage words from a captured return type.
///
/// The return type is captured as the raw span before the function name, so on
/// glibc it came out as `extern size_t` and `emitExternDecls` then wrote
/// `extern extern size_t strlen(...)`, which is not C. Darwin's headers omit
/// `extern` on these declarations, which is why the doubled keyword never
/// appeared. `inline` is dropped for the same reason: it is a definition
/// property, and what is emitted here is a declaration.
fn stripStorageClass(ret: []const u8) []const u8 {
    var rest = ret;
    while (true) {
        const id = readIdent(rest);
        if (id.name.len == 0) break;
        if (std.mem.eql(u8, id.name, "extern") or
            std.mem.eql(u8, id.name, "static") or
            std.mem.eql(u8, id.name, "inline") or
            std.mem.eql(u8, id.name, "__inline") or
            std.mem.eql(u8, id.name, "__inline__") or
            std.mem.eql(u8, id.name, "__extension__"))
        {
            rest = id.rest;
            continue;
        }
        break;
    }
    return std.mem.trim(u8, rest, " \t\r\n");
}

/// Step over the pointer stars, and the qualifiers between them, that sit
/// between a return type and the function name.
///
/// `skipTypedefPrefix` stops at the first word that is not a storage class or a
/// base-type keyword — which for `extern void *memcpy (...)` is `void`, leaving
/// `*memcpy`. `readIdent` then found no identifier at `*` and the whole
/// declaration was skipped, so EVERY pointer-returning function was dropped:
/// `strcpy`, `strchr`, `malloc`, `memcpy`, `getenv`. That is host-independent
/// and predates the attribute defect; it showed up here because the GNU fixture
/// happens to include one. The return type is captured as the span before the
/// name, so consuming the stars here is also what puts them in `ret_type`.
fn skipPointerDepth(s: []const u8) []const u8 {
    var rest = skipWs(s);
    while (rest.len > 0) {
        if (rest[0] == '*') {
            rest = skipWs(rest[1..]);
            continue;
        }
        const id = readIdent(rest);
        if (id.name.len == 0) break;
        // Only a qualifier may sit between stars. Anything else is the name.
        if (std.mem.eql(u8, id.name, "const") or
            std.mem.eql(u8, id.name, "volatile") or
            std.mem.eql(u8, id.name, "__restrict") or
            std.mem.eql(u8, id.name, "restrict"))
        {
            rest = skipWs(id.rest);
            continue;
        }
        break;
    }
    return rest;
}

fn findMatchingParen(s: []const u8) ?usize {
    if (s.len == 0 or s[0] != '(') return null;
    var depth: usize = 1;
    var i: usize = 1;
    while (i < s.len) : (i += 1) {
        if (s[i] == '(') depth += 1;
        if (s[i] == ')') {
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    return null;
}

/// Best-effort scan for `ret name(params);` declarations in preprocessed C.
pub fn parseFunctionDecls(alloc: std.mem.Allocator, src: []const u8) ![]CDecl {
    var list: std.ArrayListUnmanaged(CDecl) = .empty;
    errdefer {
        for (list.items) |d| {
            alloc.free(d.name);
            alloc.free(d.ret_type);
            alloc.free(d.params);
        }
        list.deinit(alloc);
    }

    var rest = skipPreprocessor(src);
    while (rest.len > 0) {
        rest = skipPreprocessor(rest);
        if (rest.len == 0) break;
        if (rest[0] == '#') {
            rest = skipLine(rest);
            continue;
        }
        if (std.mem.startsWith(u8, rest, "typedef") or std.mem.startsWith(u8, rest, "struct") or std.mem.startsWith(u8, rest, "enum")) {
            if (std.mem.indexOf(u8, rest, ";")) |semi| {
                rest = rest[semi + 1 ..];
            } else break;
            continue;
        }

        const after_type = skipPointerDepth(skipTypedefPrefix(rest));
        const fn_name = readIdent(after_type);
        if (fn_name.name.len == 0) {
            rest = skipLine(rest);
            continue;
        }
        var params_rest = skipWs(fn_name.rest);
        if (params_rest.len == 0 or params_rest[0] != '(') {
            rest = skipLine(rest);
            continue;
        }
        const close = findMatchingParen(params_rest) orelse {
            rest = skipLine(rest);
            continue;
        };
        const params = std.mem.trim(u8, params_rest[1..close], " \t\r\n");
        const trailing = skipTrailingSpecifiers(params_rest[close + 1 ..]);
        var after = trailing.rest;
        const is_def = after.len > 0 and after[0] == '{';
        if (!is_def and (after.len == 0 or after[0] != ';')) {
            rest = skipLine(rest);
            continue;
        }
        // An asm label means the emitted `extern` would name a symbol the
        // library does not export. Refusing is the only honest answer.
        if (trailing.renamed) {
            rest = if (is_def) after else after[1..];
            continue;
        }

        const ret_end = @intFromPtr(fn_name.name.ptr) - @intFromPtr(rest.ptr);
        if (ret_end == 0 or ret_end > rest.len) {
            if (is_def) {
                if (std.mem.indexOfScalar(u8, after, '}')) |end| rest = after[end + 1 ..];
            } else rest = after[1..];
            continue;
        }
        const ret_type = stripStorageClass(std.mem.trim(u8, rest[0..ret_end], " \t\r\n"));
        if (ret_type.len == 0 or std.mem.indexOf(u8, ret_type, "(") != null) {
            if (is_def) {
                if (std.mem.indexOfScalar(u8, after, '}')) |end| rest = after[end + 1 ..];
            } else rest = after[1..];
            continue;
        }

        try list.append(alloc, .{
            .name = try alloc.dupe(u8, fn_name.name),
            .ret_type = try alloc.dupe(u8, ret_type),
            .params = try alloc.dupe(u8, if (params.len == 0) "void" else params),
        });
        if (is_def) {
            var depth: u32 = 0;
            var i: usize = 0;
            while (i < after.len) : (i += 1) {
                if (after[i] == '{') depth += 1;
                if (after[i] == '}') {
                    depth -= 1;
                    if (depth == 0) {
                        rest = after[i + 1 ..];
                        break;
                    }
                }
            } else rest = skipLine(rest);
        } else {
            rest = after[1..];
        }
    }
    return try list.toOwnedSlice(alloc);
}

pub fn emitExternDecls(w: *std.Io.Writer, decls: []const CDecl) !void {
    for (decls) |d| {
        try w.print("/* [ffi_gen] {s} */\n", .{d.name});
        // Guard against macro redefinitions (e.g. macOS FORTIFY wrappers
        // that redefine strlcat, strlcpy, bcopy, bzero as macros).
        try w.print("#ifdef {s}\n#undef {s}\n#endif\n", .{ d.name, d.name });
        try w.print("extern {s} {s}({s});\n", .{ d.ret_type, d.name, d.params });
    }
}

pub fn generateFfiFromHeader(alloc: std.mem.Allocator, header: []const u8) ![]const u8 {
    const pre = preprocessHeader(alloc, header) orelse return error.CHeaderPreprocessFailed;
    defer alloc.free(pre);
    const decls = try parseFunctionDecls(alloc, pre);
    defer {
        for (decls) |d| {
            alloc.free(d.name);
            alloc.free(d.ret_type);
            alloc.free(d.params);
        }
        alloc.free(decls);
    }
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try aw.writer.print("/* [ffi_gen] {d} declaration(s) */\n", .{decls.len});
    try emitExternDecls(&aw.writer, decls);
    return try alloc.dupe(u8, aw.written());
}

test "c_header_parse: parses function definitions" {
    const alloc = std.testing.allocator;
    const src =
        \\int64_t add(int64_t a, int64_t b) {
        \\    return a + b;
        \\}
        \\static inline int64_t sub(int64_t a, int64_t b) { return a - b; }
    ;
    const decls = try parseFunctionDecls(alloc, src);
    defer {
        for (decls) |d| {
            alloc.free(d.name);
            alloc.free(d.ret_type);
            alloc.free(d.params);
        }
        alloc.free(decls);
    }
    try std.testing.expectEqual(@as(usize, 2), decls.len);
    try std.testing.expectEqualStrings("add", decls[0].name);
    try std.testing.expectEqualStrings("sub", decls[1].name);
}

// The GNU declaration shape, as a FIXTURE rather than as whatever the host's
// libc happens to ship. The system-header test below is the integration half
// and needs a C preprocessor to say anything; this half needs nothing, so the
// two repairs it covers stay measured on every host including the one that
// cannot run clang. Both spellings are copied from glibc's preprocessed
// `string.h` and `stdlib.h`.
test "c_header_parse: a GNU-attributed declaration is neither dropped nor doubly extern" {
    const alloc = std.testing.allocator;
    const src =
        \\extern size_t strlen (const char *__s)
        \\     __attribute__ ((__nothrow__ )) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));
        \\extern void *memcpy (void *__restrict __dest, const void *__restrict __src, size_t __n)
        \\     __attribute__ ((__nothrow__ )) __attribute__ ((__nonnull__ (1, 2)));
        \\extern float strtof32 (const char *__restrict __nptr, char **__restrict __endptr)
        \\     __asm__ ("" "strtof") __attribute__ ((__nothrow__ ));
    ;
    const decls = try parseFunctionDecls(alloc, src);
    defer {
        for (decls) |d| {
            alloc.free(d.name);
            alloc.free(d.ret_type);
            alloc.free(d.params);
        }
        alloc.free(decls);
    }

    // Two admitted, and the asm-renamed one REFUSED: emitting `extern float
    // strtof32(...)` would name a symbol glibc exports as `strtof`.
    try std.testing.expectEqual(@as(usize, 2), decls.len);
    try std.testing.expectEqualStrings("strlen", decls[0].name);
    try std.testing.expectEqualStrings("size_t", decls[0].ret_type);
    try std.testing.expectEqualStrings("memcpy", decls[1].name);
    try std.testing.expectEqualStrings("void *", decls[1].ret_type);

    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    try emitExternDecls(&aw.writer, decls);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "extern extern") == null);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "extern size_t strlen(const char *__s);") != null);
}

test "c_header_parse: finds strlen in string.h preprocessed output" {
    const alloc = std.testing.allocator;
    // No C preprocessor means this host cannot supply the observation. That is
    // a missing capability, not a wrong answer, and the fixture test above
    // keeps the same two repairs measured when this arm is taken.
    const pre = preprocessHeader(alloc, "string.h") orelse return error.SkipZigTest;
    defer alloc.free(pre);
    const decls = try parseFunctionDecls(alloc, pre);
    defer {
        for (decls) |d| {
            alloc.free(d.name);
            alloc.free(d.ret_type);
            alloc.free(d.params);
        }
        alloc.free(decls);
    }
    var found = false;
    for (decls) |d| {
        if (std.mem.eql(u8, d.name, "strlen")) found = true;
        // Whatever the host libc spells, no captured return type may carry a
        // storage class into the emitted declaration.
        try std.testing.expect(!std.mem.startsWith(u8, d.ret_type, "extern"));
        try std.testing.expect(!std.mem.startsWith(u8, d.ret_type, "static"));
    }
    try std.testing.expect(found);
}

test "c_header_parse: header paths are argv data, never shell source" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const header_name = "fixture ; dollar $ quote '.h";
    try tmp.dir.writeFile(io, .{
        .sub_path = header_name,
        .data = "long idol_header_probe(long value);\n",
    });
    var root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buf[0..try tmp.dir.realPath(io, &root_buf)];
    const header = try std.fmt.allocPrint(alloc, "{s}{c}{s}", .{ root, std.fs.path.sep, header_name });
    defer alloc.free(header);

    const pre = preprocessHeader(alloc, header) orelse return error.TestExpectedPreprocessedHeader;
    defer alloc.free(pre);
    try std.testing.expect(std.mem.indexOf(u8, pre, "idol_header_probe") != null);

    try tmp.dir.writeFile(io, .{
        .sub_path = "refuses-include.h",
        .data =
        \\#if __INCLUDE_LEVEL__ > 0
        \\#error this source refuses header inclusion
        \\#endif
        \\long must_not_arrive_through_fallback(long value);
        ,
    });
    const refuses_include = try std.fmt.allocPrint(alloc, "{s}/refuses-include.h", .{root});
    defer alloc.free(refuses_include);
    try std.testing.expect(preprocessHeader(alloc, refuses_include) == null);

    try tmp.dir.symLink(io, header_name, "linked.h", .{});
    const linked = try std.fmt.allocPrint(alloc, "{s}/linked.h", .{root});
    defer alloc.free(linked);
    const linked_pre = preprocessHeader(alloc, linked) orelse return error.TestExpectedSymlinkHeader;
    defer alloc.free(linked_pre);
    try std.testing.expect(std.mem.indexOf(u8, linked_pre, "idol_header_probe") != null);

    const injected = try std.fmt.allocPrint(
        alloc,
        "{s}/missing.h; /usr/bin/touch '{s}/injected'; #",
        .{ root, root },
    );
    defer alloc.free(injected);
    try std.testing.expect(preprocessHeader(alloc, injected) == null);
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(io, "injected", .{}));

    const response_body = try std.fmt.allocPrint(alloc, "-o {s}/response-output\nstring.h\n", .{root});
    defer alloc.free(response_body);
    try tmp.dir.writeFile(io, .{ .sub_path = "clang-args.rsp", .data = response_body });
    const response = try std.fmt.allocPrint(alloc, "@{s}/clang-args.rsp", .{root});
    defer alloc.free(response);
    try std.testing.expect(preprocessHeader(alloc, response) == null);
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(io, "response-output", .{}));
    try std.testing.expect(preprocessHeader(alloc, "--version") == null);

    try std.testing.expectError(
        error.CHeaderPreprocessFailed,
        generateFfiFromHeader(alloc, "x */\nlong forged(long);\n/*"),
    );
}
