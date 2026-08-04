//! Best-effort C library function signatures for `@c.call("name", ...)`.
//! Shared by sema (type-check) and codegen (native unboxing). Expand as
//! `@c.import("header.h")` coverage grows.

const std = @import("std");
const RT = @import("types.zig").ResolvedType;

var void_ptr_elem: RT = .void;
const void_ptr: RT = .{ .pointer = &void_ptr_elem };

const HeaderGroup = struct {
    header: []const u8,
    names: []const []const u8,
    rt: RT,
};

/// Signatures exposed only when the matching header was `@c.import`/`@c.include`d.
const header_groups = [_]HeaderGroup{
    .{
        .header = "stdio.h",
        .names = &.{
            "tmpfile", "fopen",  "freopen", "fdopen", "popen",
            "setvbuf", "setbuf",
        },
        .rt = void_ptr,
    },
    .{
        .header = "stdio.h",
        .names = &.{
            "fread", "fwrite", "fgets",  "fputs",  "fgetc",  "fputc",   "ungetc",
            "ftell", "fseek",  "rewind", "remove", "rename", "setvbuf",
        },
        .rt = RT.i64,
    },
    .{
        .header = "stdio.h",
        .names = &.{ "perror", "clearerr" },
        .rt = RT.void,
    },
    .{
        .header = "stdlib.h",
        .names = &.{ "system", "atexit", "abs", "labs", "llabs" },
        .rt = RT.i64,
    },
    .{
        .header = "stdlib.h",
        .names = &.{ "abort", "exit", "_Exit", "quick_exit" },
        .rt = RT.void,
    },
    .{
        .header = "unistd.h",
        .names = &.{ "unlink", "rmdir", "chdir", "isatty", "sleep", "usleep" },
        .rt = RT.i64,
    },
    .{
        .header = "fcntl.h",
        .names = &.{ "creat", "openat", "fcntl" },
        .rt = RT.i64,
    },
    .{
        .header = "math.h",
        .names = &.{
            "sqrt", "pow", "sin", "cos", "tan", "fabs", "floor", "ceil", "hypot",
        },
        .rt = RT.f64,
    },
    .{
        .header = "string.h",
        .names = &.{ "memcpy", "memmove", "memchr" },
        .rt = void_ptr,
    },
    .{
        .header = "string.h",
        .names = &.{
            "strlen", "strcmp", "strncmp", "memcmp",
        },
        .rt = RT.i64,
    },
    .{
        .header = "dlfcn.h",
        .names = &.{ "dlopen", "dlsym", "dlerror" },
        .rt = void_ptr,
    },
    .{
        .header = "dlfcn.h",
        .names = &.{"dlclose"},
        .rt = RT.i64,
    },
    .{
        .header = "pthread.h",
        .names = &.{ "pthread_create", "pthread_self" },
        .rt = RT.i64,
    },
    .{
        .header = "pthread.h",
        .names = &.{ "pthread_join", "pthread_detach", "pthread_mutex_lock", "pthread_mutex_unlock" },
        .rt = RT.i64,
    },
    .{
        .header = "errno.h",
        .names = &.{"__errno_location"},
        .rt = void_ptr,
    },
    .{
        .header = "sys/stat.h",
        .names = &.{ "stat", "fstat", "lstat", "mkdir", "mkfifo" },
        .rt = RT.i64,
    },
    .{
        .header = "signal.h",
        .names = &.{ "signal", "raise", "kill" },
        .rt = void_ptr,
    },
    .{
        .header = "signal.h",
        .names = &.{"sigaction"},
        .rt = RT.i64,
    },
};

/// Return type for a well-known libc/libm name, or null when unknown.
pub fn c_call_result_type(fname: []const u8) ?RT {
    inline for (.{
        .{ .names = [_][]const u8{
            "llabs",  "labs",    "abs",     "strlen",   "strcmp", "strncmp", "memcmp",
            "printf", "fprintf", "sprintf", "snprintf", "atoi",   "atol",    "getchar",
            "close",  "read",    "write",   "fcntl",    "open",   "dup",     "lseek",
            "clock",  "time",    "getpid",  "fork",     "wait",   "waitpid",
        }, .rt = RT.i64 },
        .{ .names = [_][]const u8{
            "sqrt",      "pow",   "sin",   "cos",   "tan",   "asin",      "acos",     "atan",
            "atan2",     "exp",   "log",   "log10", "log2",  "floor",     "ceil",     "fabs",
            "fmod",      "fmax",  "fmin",  "atof",  "sinh",  "cosh",      "tanh",     "hypot",
            "cbrt",      "expm1", "log1p", "trunc", "round", "nearbyint", "copysign", "fdim",
            "remainder",
        }, .rt = RT.f64 },
        .{ .names = [_][]const u8{
            "getenv",  "strerror", "strdup",  "strcpy", "strncpy", "strcat",
            "strncat", "strchr",   "strrchr", "strstr", "strtok",
        }, .rt = RT.str },
        .{ .names = [_][]const u8{ "fclose", "fflush", "fgetc", "fputc", "feof", "ferror" }, .rt = RT.i64 },
    }) |group| {
        for (group.names) |name| {
            if (std.mem.eql(u8, fname, name)) return group.rt;
        }
    }
    inline for (.{
        "malloc", "calloc", "realloc", "mmap", "getcwd", "opendir", "setlocale",
    }) |name| {
        if (std.mem.eql(u8, fname, name)) return void_ptr;
    }
    if (std.mem.eql(u8, fname, "free") or std.mem.eql(u8, fname, "memset") or
        std.mem.eql(u8, fname, "munmap") or std.mem.eql(u8, fname, "closedir"))
        return .void;
    return null;
}

/// Lookup a function signature gated on a specific imported header.
pub fn header_c_call_result_type(header: []const u8, fname: []const u8) ?RT {
    for (header_groups) |group| {
        if (!std.mem.eql(u8, group.header, header)) continue;
        for (group.names) |name| {
            if (std.mem.eql(u8, fname, name)) return group.rt;
        }
    }
    return null;
}

threadlocal var dynamic_registry: std.StringHashMapUnmanaged(DynamicDecl) = .{};
threadlocal var dynamic_registry_alloc: ?std.mem.Allocator = null;

pub const DynamicDecl = struct {
    ret: RT,
    param_count: u16,
};

pub fn clearDynamicRegistry() void {
    if (dynamic_registry_alloc) |alloc| {
        var it = dynamic_registry.keyIterator();
        while (it.next()) |key| alloc.free(key.*);
        dynamic_registry.deinit(alloc);
    }
    dynamic_registry = .{};
    dynamic_registry_alloc = null;
}

pub fn registerDynamicDecl(alloc: std.mem.Allocator, name: []const u8, ret: RT, param_count: u16) !void {
    if (dynamic_registry_alloc == null) dynamic_registry_alloc = alloc;
    const owned = try alloc.dupe(u8, name);
    const gop = try dynamic_registry.getOrPut(alloc, owned);
    if (gop.found_existing) {
        alloc.free(owned);
        gop.value_ptr.* = .{ .ret = ret, .param_count = param_count };
    } else {
        gop.value_ptr.* = .{ .ret = ret, .param_count = param_count };
    }
}

/// Emit file registry for @c.emit_file (compile-time file writing)
var emit_files: std.StringHashMapUnmanaged([]const u8) = .{};
var emit_files_alloc: ?std.mem.Allocator = null;

pub fn clearEmitFiles() void {
    if (emit_files_alloc) |alloc| {
        var it = emit_files.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            alloc.free(entry.value_ptr.*);
        }
        emit_files.deinit(alloc);
    }
    emit_files = .{};
    emit_files_alloc = null;
}

pub fn registerEmitFile(alloc: std.mem.Allocator, path: []const u8, content: []const u8) !void {
    if (emit_files_alloc == null) emit_files_alloc = alloc;
    const owned_path = try alloc.dupe(u8, path);
    const owned_content = try alloc.dupe(u8, content);
    const gop = try emit_files.getOrPut(alloc, owned_path);
    if (gop.found_existing) {
        alloc.free(owned_path);
        alloc.free(owned_content);
    } else {
        gop.value_ptr.* = owned_content;
    }
}

pub fn getEmitFiles() []const []const u8 {
    _ = emit_files;
    return &.{};
}

pub fn emitFilesMap() *std.StringHashMapUnmanaged([]const u8) {
    return &emit_files;
}

pub fn dynamicDecl(fname: []const u8) ?DynamicDecl {
    return dynamic_registry.get(fname);
}

pub fn isKnownCFn(fname: []const u8, imported_headers: []const []const u8) bool {
    if (dynamicDecl(fname) != null) return true;
    return c_call_result_type_imported(fname, imported_headers) != null;
}

/// Map C return-type spellings from `@foreign` / `@ffi_gen` scans to Duo RT.
pub fn rtFromCRetType(c_type: []const u8) RT {
    var t = std.mem.trim(u8, c_type, " \t\r\n");
    while (true) {
        if (std.mem.startsWith(u8, t, "static ")) {
            t = std.mem.trim(u8, t[7..], " \t");
        } else if (std.mem.startsWith(u8, t, "inline ")) {
            t = std.mem.trim(u8, t[7..], " \t");
        } else if (std.mem.startsWith(u8, t, "extern ")) {
            t = std.mem.trim(u8, t[7..], " \t");
        } else if (std.mem.startsWith(u8, t, "const ")) {
            t = std.mem.trim(u8, t[6..], " \t");
        } else if (std.mem.startsWith(u8, t, "volatile ")) {
            t = std.mem.trim(u8, t[9..], " \t");
        } else if (std.mem.startsWith(u8, t, "unsigned ")) {
            t = std.mem.trim(u8, t[9..], " \t");
        } else if (std.mem.startsWith(u8, t, "signed ")) {
            t = std.mem.trim(u8, t[7..], " \t");
        } else if (std.mem.startsWith(u8, t, "long ")) {
            t = std.mem.trim(u8, t[5..], " \t");
        } else if (std.mem.startsWith(u8, t, "short ")) {
            t = std.mem.trim(u8, t[6..], " \t");
        } else {
            break;
        }
    }
    if (std.mem.eql(u8, t, "void")) return .void;
    if (std.mem.eql(u8, t, "double")) return .f64;
    if (std.mem.eql(u8, t, "float")) return .f32;
    if (std.mem.eql(u8, t, "bool") or std.mem.eql(u8, t, "_Bool")) return .bool;
    if (std.mem.eql(u8, t, "size_t")) return .u64;
    if (std.mem.eql(u8, t, "ssize_t")) return .i64;
    if (std.mem.indexOfScalar(u8, t, '*') != null) return void_ptr;
    if (std.mem.eql(u8, t, "char") or std.mem.endsWith(u8, t, "_t") or
        std.mem.eql(u8, t, "int") or std.mem.eql(u8, t, "long"))
        return .i64;
    return .any;
}

pub fn paramCountFromCParams(params: []const u8) u16 {
    const p = std.mem.trim(u8, params, " \t\r\n");
    if (p.len == 0 or std.mem.eql(u8, p, "void")) return 0;
    var count: u16 = 1;
    var depth: u16 = 0;
    for (p) |ch| {
        if (ch == '(') depth += 1;
        if (ch == ')') {
            if (depth > 0) depth -= 1;
        }
        if (ch == ',' and depth == 0) count += 1;
    }
    return count;
}

/// Resolve `@c.call` return type using globally-known names plus any imported headers.
pub fn c_call_result_type_imported(fname: []const u8, imported_headers: []const []const u8) ?RT {
    if (dynamicDecl(fname)) |d| return d.ret;
    if (c_call_result_type(fname)) |rt| return rt;
    for (imported_headers) |header| {
        if (header_c_call_result_type(header, fname)) |rt| return rt;
    }
    return null;
}

/// If `fname` is header-gated, return the header that declares it (for diagnostics).
pub fn suggest_header_for(fname: []const u8) ?[]const u8 {
    if (c_call_result_type(fname) != null) return null;
    for (header_groups) |group| {
        for (group.names) |name| {
            if (std.mem.eql(u8, fname, name)) return group.header;
        }
    }
    return null;
}

/// Headers whose declarations are commonly pulled in via `@c.import`.
pub fn header_exports_pointer_types(header: []const u8) bool {
    inline for (.{ "stdio.h", "stdlib.h", "string.h", "unistd.h", "fcntl.h", "dirent.h", "math.h", "dlfcn.h", "pthread.h", "errno.h", "sys/stat.h", "signal.h" }) |known| {
        if (std.mem.eql(u8, header, known)) return true;
    }
    return false;
}

test "c_signatures: dynamic registry" {
    const testing = std.testing;
    const alloc = std.testing.allocator;
    clearDynamicRegistry();
    defer clearDynamicRegistry();
    try registerDynamicDecl(alloc, "add", .i64, 2);
    try testing.expectEqual(RT.i64, dynamicDecl("add").?.ret);
    try testing.expectEqual(@as(u16, 2), dynamicDecl("add").?.param_count);
    try testing.expectEqual(RT.i64, c_call_result_type_imported("add", &.{}).?);
    try testing.expect(isKnownCFn("add", &.{}));
}

test "c_signatures: rtFromCRetType" {
    const testing = std.testing;
    try testing.expectEqual(RT.i64, rtFromCRetType("int64_t"));
    try testing.expectEqual(RT.f64, rtFromCRetType("static inline double"));
    try testing.expectEqual(RT.void, rtFromCRetType("void"));
}

test "c_signatures: libc names resolve" {
    const testing = std.testing;
    try testing.expectEqual(RT.i64, c_call_result_type("memcmp").?);
    try testing.expectEqual(RT.f64, c_call_result_type("fabs").?);
    try testing.expectEqual(RT.str, c_call_result_type("getenv").?);
    try testing.expectEqual(RT.i64, c_call_result_type("fclose").?);
    try testing.expect(c_call_result_type("unknown_c_fn_xyz") == null);
}

test "c_signatures: allocator helpers return opaque pointer" {
    const testing = std.testing;
    try testing.expect(c_call_result_type("malloc").? == .pointer);
    try testing.expect(c_call_result_type("tmpfile") == null);
    try testing.expectEqual(RT.void, c_call_result_type("free").?);
}

test "c_signatures: header-gated stdio signatures" {
    const testing = std.testing;
    try testing.expect(c_call_result_type("tmpfile") == null);
    try testing.expect(header_c_call_result_type("stdio.h", "tmpfile").? == .pointer);
    try testing.expect(header_c_call_result_type("stdlib.h", "tmpfile") == null);
    try testing.expectEqual(RT.i64, header_c_call_result_type("stdio.h", "fread").?);
    try testing.expect(c_call_result_type_imported("tmpfile", &.{"stdio.h"}).? == .pointer);
    try testing.expect(c_call_result_type_imported("tmpfile", &.{}) == null);
}

test "c_signatures: suggest_header_for guides imports" {
    const testing = std.testing;
    try testing.expectEqualStrings("stdio.h", suggest_header_for("tmpfile").?);
    try testing.expectEqualStrings("dlfcn.h", suggest_header_for("dlopen").?);
    try testing.expect(suggest_header_for("llabs") == null);
}
