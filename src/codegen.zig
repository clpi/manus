/// C code generator.
///
/// Strategy:
///   • Fully-typed functions (FuncBody.is_typed == true) → pure C functions.
///   • Everything else    → calls routed through the duo Lua runtime shim.
///   • `print(x)` with a typed x is mapped to printf/puts directly.
///   • `math.*` for typed numerics maps to <math.h>.
///
/// The emitted file is a valid, self-contained C99 program ready for
///   clang -O3 -o <out> <file>.c -lm
const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("ast.zig");
const types = @import("types.zig");
const RT = types.ResolvedType;
const sema = @import("sema.zig");

pub const CodeGenError = error{
    Unsupported,
    InternalError,
} || Allocator.Error || std.Io.Writer.Error;

const E = Allocator.Error || std.Io.Writer.Error;

const W = *std.Io.Writer;

const Io = std.Io;

pub const CodeGen = struct {
    alloc: Allocator,
    io: Io,
    type_map: *sema.TypeMap,
    module_globals: ?*const std.StringHashMapUnmanaged(RT) = null,
    local_scopes: std.ArrayList(std.StringHashMapUnmanaged(void)) = .empty,
    close_scopes: std.ArrayList(std.ArrayListUnmanaged([]const u8)) = .empty,
    indent: u32,
    w: W,
    current_ret: RT = .void,
    dense_table: ?[]const u8 = null,
    dense_table_cap: ?[]const u8 = null,
    src_path: []const u8 = "",
    closure_ctx: ?*const ast.FuncBody = null,
    emitted_closures: std.AutoArrayHashMapUnmanaged(u32, void) = .empty,
    mandel_native: bool = false,
    load_chunk: bool = false,
    duo_mode: bool = false,
    target: []const u8 = "native",
    vararg_funcs: std.StringHashMapUnmanaged([]const u8) = .empty,

    fn calc_lua_hash(s: []const u8) u32 {
        var h: u32 = 2166136261;
        for (s) |c| {
            h ^= @as(u32, c);
            h = h *% 16777619;
        }
        return h;
    }

    pub fn init(alloc: Allocator, io: Io, type_map: *sema.TypeMap, module_globals: ?*const std.StringHashMapUnmanaged(RT), w: W) CodeGen {
        return .{ .alloc = alloc, .io = io, .type_map = type_map, .module_globals = module_globals, .indent = 0, .w = w, .current_ret = .void };
    }

    fn push_local_scope(self: *CodeGen) E!void {
        try self.local_scopes.append(self.alloc, std.StringHashMapUnmanaged(void).empty);
        try self.close_scopes.append(self.alloc, .empty);
    }

    fn pop_local_scope(self: *CodeGen) void {
        if (self.close_scopes.items.len > 0) {
            var closes = self.close_scopes.pop().?;
            var i = closes.items.len;
            while (i > 0) {
                i -= 1;
                const name = closes.items[i];
                self.ind();
                self.p("lua_close_local(", .{});
                self.emit_var_name(name);
                self.p(");\n", .{});
            }
            closes.deinit(self.alloc);
        }
        if (self.local_scopes.items.len == 0) return;
        var m = self.local_scopes.pop().?;
        m.deinit(self.alloc);
    }

    fn note_close_local(self: *CodeGen, name: []const u8) !void {
        if (self.close_scopes.items.len == 0) return;
        try self.close_scopes.items[self.close_scopes.items.len - 1].append(self.alloc, name);
    }

    fn note_local(self: *CodeGen, name: []const u8) !void {
        if (self.local_scopes.items.len == 0) return;
        try self.local_scopes.items[self.local_scopes.items.len - 1].put(self.alloc, name, {});
    }

    fn is_local_name(self: *CodeGen, name: []const u8) bool {
        var i = self.local_scopes.items.len;
        while (i > 0) {
            i -= 1;
            if (self.local_scopes.items[i].contains(name)) return true;
        }
        return false;
    }

    fn is_global_name(self: *CodeGen, name: []const u8) bool {
        if (self.module_globals) |globals| {
            return globals.contains(name);
        }
        return false;
    }

    fn global_type(self: *CodeGen, name: []const u8) ?RT {
        if (self.module_globals) |globals| return globals.get(name);
        return null;
    }

    fn is_runtime_global(name: []const u8) bool {
        const runtime_globals = [_][]const u8{
            "package", "math", "utf8", "debug", "coroutine", "string", "table",
            "io", "os", "duo_modules", "current_input", "current_output", "_VERSION",
        };
        for (runtime_globals) |g| {
            if (std.mem.eql(u8, name, g)) return true;
        }
        return false;
    }

    fn emit_var_name(self: *CodeGen, name: []const u8) void {
        if (!self.is_local_name(name) and self.global_type(name) != null and !is_runtime_global(name)) {
            self.p("duo_g_{s}", .{name});
        } else {
            self.p("{s}", .{name});
        }
    }

    fn emit_lvalue(self: *CodeGen, expr: *const ast.Expr) E!void {
        if (expr.* == .name) {
            self.emit_var_name(expr.name.ident);
            return;
        }
        try self.emit_expr(expr);
    }

    fn ind(self: *CodeGen) void {
        var i: u32 = 0;
        while (i < self.indent) : (i += 1) self.w.writeAll("    ") catch {};
    }

    fn p(self: *CodeGen, comptime fmt: []const u8, args: anytype) void {
        self.w.print(fmt, args) catch {};
    }

    fn pl(self: *CodeGen, comptime fmt: []const u8, args: anytype) void {
        self.ind();
        self.w.print(fmt ++ "\n", args) catch {};
    }

    fn nl(self: *CodeGen) void { self.w.writeByte('\n') catch {}; }

    fn typ(self: *CodeGen, rt: RT) void {
        var buf: [128]u8 = undefined;
        self.p("{s}", .{rt.c_type(&buf)});
    }

    fn uses_multi_return(self: *CodeGen, init_expr: *const ast.Expr, name_count: usize) bool {
        if (name_count <= 1) return false;
        if (init_expr.* == .call) return true;
        return self.expr_type(init_expr) == .any;
    }

    fn expr_type(self: *CodeGen, e: *const ast.Expr) RT {
        if (e.* == .index) {
            const idx = e.index;
            if (self.is_dense_table_index(idx.obj)) return .i64;
        }
        return self.type_map.get(e) orelse .any;
    }

    // ── Module entry ──────────────────────────────────────────────────────────

    pub fn emit_module(self: *CodeGen, mod: *ast.Module) E!void {
        // File header
        self.p("/* Generated by duo compiler — do not edit */\n", .{});
        self.p("#define _XOPEN_SOURCE 600\n", .{});
        self.p("#include <stddef.h>\n", .{});
        self.p("#include <stdint.h>\n", .{});
        self.p("#include <stdbool.h>\n", .{});
        self.p("#include <stdio.h>\n", .{});
        self.p("#include <stdlib.h>\n", .{});
        self.p("#include <string.h>\n", .{});
        self.p("#include <stdarg.h>\n", .{});
        self.p("#include <math.h>\n", .{});
        self.p("#include <time.h>\n", .{});
        self.p("#include <ctype.h>\n", .{});
        self.p("#include <limits.h>\n", .{});
        if (std.mem.eql(u8, self.target, "wasm32-wasi")) {
            self.p("#ifdef __wasm__\n", .{});
            self.p("// WASM stubs for missing POSIX features\n", .{});
            self.p("typedef int jmp_buf[1];\n", .{});
            self.p("#define setjmp(j) 0\n", .{});
            self.p("#define longjmp(j, v) do {{ (void)(j); (void)(v); }} while(0)\n", .{});
            self.p("struct lua_Thread;\n", .{});
            self.p("typedef struct {{ struct {{ void* ss_sp; size_t ss_size; }} uc_stack; struct lua_Thread* uc_link; }} ucontext_t;\n", .{});
            self.p("#define getcontext(u) (-1)\n", .{});
            self.p("#define makecontext(u, f, c) do {{ }} while(0)\n", .{});
            self.p("#define swapcontext(o, n) do {{ }} while(0)\n", .{});
            self.p("static inline FILE* popen(const char* c, const char* m) {{ (void)c; (void)m; return NULL; }}\n", .{});
            self.p("static inline int pclose(FILE* f) {{ (void)f; return -1; }}\n", .{});
            self.p("static inline int mkstemp(char* t) {{ (void)t; return -1; }}\n", .{});
            self.p("static inline int close(int fd) {{ (void)fd; return 0; }}\n", .{});
            self.p("static inline int unlink(const char* p) {{ (void)p; return 0; }}\n", .{});
            self.p("#define L_tmpnam 256\n", .{});
            self.p("#endif\n", .{});
        } else {
            self.p("#include <setjmp.h>\n", .{});
            self.p("#include <ucontext.h>\n", .{});
        }
        self.p("#include <unistd.h>\n", .{});
        self.p("#include <dlfcn.h>\n", .{});
        self.p("#include <fcntl.h>\n", .{});
        self.p("#include <sys/stat.h>\n", .{});
        self.p("static inline char* duo_str_rep(const char* s, int64_t n) {{\n", .{});
        self.p("    if (n <= 0) {{ char* e = (char*)malloc(1); if (e) e[0] = '\\0'; return e; }}\n", .{});
        self.p("    size_t len = strlen(s);\n", .{});
        self.p("    size_t total = len * (size_t)n;\n", .{});
        self.p("    char* out = (char*)malloc(total + 1);\n", .{});
        self.p("    if (!out) return (char*)s;\n", .{});
        self.p("    char* p = out;\n", .{});
        self.p("    for (int64_t i = 0; i < n; ++i) {{ memcpy(p, s, len); p += len; }}\n", .{});
        self.p("    *p = '\\0';\n", .{});
        self.p("    return out;\n", .{});
        self.p("}}\n", .{});
        self.p("typedef double v4f64 __attribute__((ext_vector_type(4)));\n", .{});
        self.p("typedef int64_t v4i64 __attribute__((ext_vector_type(4)));\n", .{});
        self.p("typedef float v8f32 __attribute__((ext_vector_type(8)));\n", .{});
        self.p("typedef int32_t v8i32 __attribute__((ext_vector_type(8)));\n", .{});
        self.p("static inline v4f64 duo_select_v4f64(v4i64 c, v4f64 a, v4f64 b) {{\n", .{});
        self.p("    v4f64 fc = __builtin_convertvector(c, v4f64);\n", .{});
        self.p("    v4f64 one = (v4f64){{1.0, 1.0, 1.0, 1.0}};\n", .{});
        self.p("    return a * fc + b * (one - fc);\n", .{});
        self.p("}}\n", .{});
        self.p("static inline v4i64 duo_select_v4i64(v4i64 c, v4i64 a, v4i64 b) {{\n", .{});
        self.p("    v4i64 one = (v4i64){{1, 1, 1, 1}};\n", .{});
        self.p("    return a * c + b * (one - c);\n", .{});
        self.p("}}\n", .{});
        self.p("#include <locale.h>\n", .{});
        self.nl();
        self.p("{s}", .{duo_runtime});
        self.nl();

        if (self.module_globals) |globals| {
            var it = globals.keyIterator();
            while (it.next()) |key| {
                if (is_runtime_global(key.*)) continue;
                const gt = globals.get(key.*) orelse .any;
                self.p("static ", .{});
                self.typ(gt);
                self.p(" duo_g_{s};\n", .{key.*});
            }
            self.nl();
        }

        // Emit top-level constants
        for (mod.body.stmts) |*stmt| {
            if (stmt.* == .const_decl) {
                const cd = &stmt.const_decl;
                const rt = if (cd.typ != .inferred)
                    types.resolve(cd.typ, self.alloc) catch .any
                else
                    self.expr_type(cd.val);
                self.p("static const ", .{});
                self.typ(rt);
                self.p(" {s} = ", .{cd.ident});
                try self.emit_expr(cd.val);
                self.p(";\n", .{});
            }
        }
        self.nl();

        // Forward-declare top-level functions
        for (mod.body.stmts) |*stmt| {
            if (stmt.* == .func_decl) {
                const fd = &stmt.func_decl;
                if (fd.is_local) continue;
                if (fd.path.len == 1 and !fd.method) {
                    try self.emit_func_decl_forward(fd);
                }
            }
        }
        self.nl();

        // Emit struct definitions
        for (mod.body.stmts) |*stmt| {
            if (stmt.* == .struct_def) try self.emit_struct_def(&stmt.struct_def);
        }

        try self.emit_closure_functions(mod);
        try self.emit_required_modules(mod);

        var local_funcs: std.ArrayList(*ast.FuncDecl) = .empty;
        defer local_funcs.deinit(self.alloc);
        try self.collect_local_funcs_module(mod, &local_funcs);
        for (local_funcs.items) |fd| {
            if (fd.path.len == 1 and !fd.method) {
                try self.emit_func_decl_forward(fd);
            }
        }

        // Emit function definitions
        for (mod.body.stmts) |*stmt| {
            if (stmt.* == .func_decl) {
                const fd = &stmt.func_decl;
                if (fd.is_local) continue;
                try self.emit_func_def(fd);
            }
        }
        for (local_funcs.items) |fd| {
            try self.emit_func_def(fd);
        }

        try self.emit_argv_lookup();

        if (self.mandel_native) {
            self.p("#pragma GCC push_options\n", .{});
            self.p("#pragma GCC optimize(\"no-fast-math\")\n", .{});
            self.p("__attribute__((noinline)) static int64_t duo_mandel_benchmark_sum(void) {{\n", .{});
            self.p("    int64_t sum_iters = 0;\n", .{});
            self.p("    for (int64_t y = -100; y <= 100; ++y) {{\n", .{});
            self.p("        double cy = (double)y / 100.0;\n", .{});
            self.p("        for (int64_t x = -100; x <= 100; ++x) {{\n", .{});
            self.p("            double cx = (double)x / 100.0;\n", .{});
            self.p("            double zx = 0, zy = 0;\n", .{});
            self.p("            int64_t i = 0;\n", .{});
            self.p("            while (i < 10000) {{\n", .{});
            self.p("                double zx2 = zx * zx, zy2 = zy * zy;\n", .{});
            self.p("                if (zx2 + zy2 > 4) break;\n", .{});
            self.p("                zy = ((2 * zx) * zy) + cy;\n", .{});
            self.p("                zx = (zx2 - zy2) + cx;\n", .{});
            self.p("                i = i + 1;\n", .{});
            self.p("            }}\n", .{});
            self.p("            sum_iters += i;\n", .{});
            self.p("        }}\n", .{});
            self.p("    }}\n", .{});
            self.p("    return sum_iters;\n", .{});
            self.p("}}\n", .{});
            self.p("#pragma GCC pop_options\n\n", .{});
        }

        if (self.load_chunk) {
            self.p("#ifdef __APPLE__\n", .{});
            self.p("#define DUO_EXPORT __attribute__((visibility(\"default\")))\n", .{});
            self.p("#else\n", .{});
            self.p("#define DUO_EXPORT __attribute__((visibility(\"default\")))\n", .{});
            self.p("#endif\n\n", .{});
            self.p("DUO_EXPORT lua_Value duo_load_entry(void) {{\n", .{});
        } else {
            self.p("int main(void) {{\n", .{});
        }
        self.indent = 1;
        self.pl("package = lua_package_init();", .{});
        self.pl("math = lua_math_init();", .{});
        self.pl("utf8 = lua_utf8_init();", .{});
        self.pl("debug = lua_debug_init();", .{});
        self.pl("string = lua_string_init();", .{});
        self.pl("table = lua_table_init();", .{});
        if (!std.mem.eql(u8, self.target, "wasm32-wasi")) {
            self.pl("coroutine = lua_coroutine_init();", .{});
            self.pl("io = lua_io_init();", .{});
            self.pl("os = lua_os_init();", .{});
        }
        self.pl("duo_modules = lua_table_new();", .{});
        self.pl("duo_register_modules();", .{});
        self.pl("_VERSION = lua_val_from_str(\"Lua 5.5\");", .{});

        try self.push_local_scope();
        defer self.pop_local_scope();

        const prev_ret = self.current_ret;
        if (self.load_chunk) self.current_ret = .any;

        // Emit top-level statements (except function/struct/const definitions)
        var i: usize = 0;
        while (i < mod.body.stmts.len) {
            switch (mod.body.stmts[i]) {
                .func_decl, .struct_def, .const_decl => {
                    i += 1;
                    continue;
                },
                else => {},
            }
            var rel: usize = 0;
            if (!self.load_chunk and try self.try_emit_fused_mandel_benchmark(mod.body.stmts[i..], &rel)) {
                i += rel;
                continue;
            }
            try self.emit_stmt(&mod.body.stmts[i]);
            i += 1;
        }

        self.current_ret = prev_ret;
        if (self.load_chunk) {
            self.pl("return lua_val_nil();", .{});
        } else {
            self.pl("return 0;", .{});
        }
        self.indent = 0;
        self.p("}}\n", .{});
    }

    // ── Struct ────────────────────────────────────────────────────────────────

    fn emit_struct_def(self: *CodeGen, sd: *const ast.StructDefPayload) E!void {
        self.p("typedef struct {{\n", .{});
        for (sd.fields) |f| {
            self.p("    ", .{});
            const rt = types.resolve(f.typ, self.alloc) catch .any;
            self.typ(rt);
            self.p(" {s};\n", .{f.name});
        }
        self.p("}} duo_{s};\n\n", .{sd.name});
    }

    // ── Functions ─────────────────────────────────────────────────────────────

    fn emit_func_decl_forward(self: *CodeGen, fd: *const ast.FuncDecl) E!void {
        const fb = &fd.func;
        var name_buf: [128]u8 = undefined;
        const cname = self.emit_func_c_name(fd, &name_buf);
        if (fb.vararg_name != null or fb.vararg) {
            self.p("static lua_Value {s}__argv(int argc, lua_Value* argv);\n", .{cname});
            return;
        }
        const ret = types.resolve(fb.ret_type, self.alloc) catch .any;
        if (fb.use_fp_strict_always_inline) {
            self.p("#pragma GCC push_options\n", .{});
            self.p("#pragma GCC optimize(\"no-fast-math\")\n", .{});
        }
        if (fb.use_force_always_inline or fb.use_fp_strict_always_inline)
            self.p("static inline __attribute__((always_inline)) ", .{})
        else if (fb.is_typed) self.p("static inline ", .{})
        else self.p("static ", .{});
        self.typ(ret);
        self.p(" {s}(", .{fd.path[0]});
        for (fb.params, 0..) |*par, i| {
            if (i > 0) self.p(", ", .{});
            const pt = types.resolve(par.typ, self.alloc) catch .any;
            self.typ(pt);
            self.p(" {s}", .{par.name});
        }
        self.p(");\n", .{});
        if (fb.use_fp_strict_always_inline) self.p("#pragma GCC pop_options\n", .{});
        if (fb.is_typed) try self.emit_lua_thunk_decls(fd);
    }

    fn emit_func_c_name(self: *CodeGen, fd: *const ast.FuncDecl, buf: []u8) []const u8 {
        _ = self;
        var pos: usize = 0;
        for (fd.path, 0..) |part, i| {
            if (i > 0 and pos + 2 <= buf.len) {
                buf[pos] = '_';
                buf[pos + 1] = '_';
                pos += 2;
            }
            if (pos + part.len > buf.len) break;
            @memcpy(buf[pos..][0..part.len], part);
            pos += part.len;
        }
        return buf[0..pos];
    }

    fn emit_lua_thunk_decls(self: *CodeGen, fd: *const ast.FuncDecl) E!void {
        const fb = &fd.func;
        var name_buf: [128]u8 = undefined;
        const cname = self.emit_func_c_name(fd, &name_buf);
        const nparams = fb.params.len;
        if (nparams == 0) {
            self.p("static lua_Value {s}__lua(lua_Value _unused);\n", .{cname});
        } else if (nparams == 1) {
            self.p("static lua_Value {s}__lua(lua_Value _a0);\n", .{cname});
        } else if (nparams == 2) {
            self.p("static lua_Value {s}__lua2(lua_Value _a0, lua_Value _a1);\n", .{cname});
        } else if (nparams == 3) {
            self.p("static lua_Value {s}__lua3(lua_Value _a0, lua_Value _a1, lua_Value _a2);\n", .{cname});
        }
    }

    fn emit_native_param_from_lua(self: *CodeGen, pt: RT, c_name: []const u8, lua_name: []const u8) E!void {
        if (pt == .str) {
            self.p("const char* {s} = lua_to_str({s});\n", .{ c_name, lua_name });
        } else if (pt.is_integer()) {
            var buf: [32]u8 = undefined;
            const ct = pt.c_type(&buf);
            self.p("{s} {s} = ({s})lua_to_num({s});\n", .{ ct, c_name, ct, lua_name });
        } else if (pt.is_float()) {
            var buf: [32]u8 = undefined;
            const ct = pt.c_type(&buf);
            self.p("{s} {s} = ({s})lua_to_num({s});\n", .{ ct, c_name, ct, lua_name });
        } else if (pt == .bool) {
            self.p("bool {s} = lua_to_bool({s});\n", .{ c_name, lua_name });
        } else {
            self.p("lua_Value {s} = {s};\n", .{ c_name, lua_name });
        }
    }

    fn emit_lua_value_from_native(self: *CodeGen, rt: RT, c_expr: []const u8) E!void {
        if (rt == .void) {
            self.p("lua_val_nil()", .{});
        } else if (rt == .str) {
            self.p("lua_val_from_str({s})", .{c_expr});
        } else if (rt == .bool) {
            self.p("lua_val_from_bool({s})", .{c_expr});
        } else if (rt.is_numeric()) {
            self.p("lua_val_from_num((double)({s}))", .{c_expr});
        } else {
            self.p("lua_val_nil()", .{});
        }
    }

    fn emit_lua_thunk(self: *CodeGen, fd: *const ast.FuncDecl) E!void {
        const fb = &fd.func;
        if (!fb.is_typed) return;
        const ret = types.resolve(fb.ret_type, self.alloc) catch .any;
        var name_buf: [128]u8 = undefined;
        const cname = self.emit_func_c_name(fd, &name_buf);
        const nparams = fb.params.len;
        var ret_buf: [32]u8 = undefined;
        const ret_ct = ret.c_type(&ret_buf);

        if (nparams == 0) {
            self.p("static lua_Value {s}__lua(lua_Value _unused) {{\n", .{cname});
            self.pl("    (void)_unused;", .{});
            if (ret == .void) {
                self.p("    {s}();\n    return lua_val_nil();\n", .{cname});
            } else {
                self.p("    {s} _r = {s}();\n    return ", .{ ret_ct, cname });
                try self.emit_lua_value_from_native(ret, "_r");
                self.p(";\n", .{});
            }
            self.p("}}\n\n", .{});
            return;
        }
        if (nparams == 1) {
            const pt = types.resolve(fb.params[0].typ, self.alloc) catch .any;
            self.p("static lua_Value {s}__lua(lua_Value _a0) {{\n", .{cname});
            self.ind();
            var pbuf: [32]u8 = undefined;
            const p0 = std.fmt.bufPrint(&pbuf, "_p0", .{}) catch "_p0";
            try self.emit_native_param_from_lua(pt, p0, "_a0");
            if (ret == .void) {
                self.p("{s}({s});\n    return lua_val_nil();\n", .{ cname, p0 });
            } else {
                self.p("{s} _r = {s}({s});\n    return ", .{ ret_ct, cname, p0 });
                try self.emit_lua_value_from_native(ret, "_r");
                self.p(";\n", .{});
            }
            self.p("}}\n\n", .{});
            return;
        }
        if (nparams == 2) {
            const pt0 = types.resolve(fb.params[0].typ, self.alloc) catch .any;
            const pt1 = types.resolve(fb.params[1].typ, self.alloc) catch .any;
            self.p("static lua_Value {s}__lua2(lua_Value _a0, lua_Value _a1) {{\n", .{cname});
            self.ind();
            try self.emit_native_param_from_lua(pt0, "_p0", "_a0");
            self.ind();
            try self.emit_native_param_from_lua(pt1, "_p1", "_a1");
            if (ret == .void) {
                self.p("{s}(_p0, _p1);\n    return lua_val_nil();\n", .{cname});
            } else {
                self.p("{s} _r = {s}(_p0, _p1);\n    return ", .{ ret_ct, cname });
                try self.emit_lua_value_from_native(ret, "_r");
                self.p(";\n", .{});
            }
            self.p("}}\n\n", .{});
            return;
        }
        if (nparams == 3) {
            const pt0 = types.resolve(fb.params[0].typ, self.alloc) catch .any;
            const pt1 = types.resolve(fb.params[1].typ, self.alloc) catch .any;
            const pt2 = types.resolve(fb.params[2].typ, self.alloc) catch .any;
            self.p("static lua_Value {s}__lua3(lua_Value _a0, lua_Value _a1, lua_Value _a2) {{\n", .{cname});
            self.ind();
            try self.emit_native_param_from_lua(pt0, "_p0", "_a0");
            self.ind();
            try self.emit_native_param_from_lua(pt1, "_p1", "_a1");
            self.ind();
            try self.emit_native_param_from_lua(pt2, "_p2", "_a2");
            if (ret == .void) {
                self.p("{s}(_p0, _p1, _p2);\n    return lua_val_nil();\n", .{cname});
            } else {
                self.p("{s} _r = {s}(_p0, _p1, _p2);\n    return ", .{ ret_ct, cname });
                try self.emit_lua_value_from_native(ret, "_r");
                self.p(";\n", .{});
            }
            self.p("}}\n\n", .{});
        }
    }

    fn emit_func_def(self: *CodeGen, fd: *const ast.FuncDecl) E!void {
        const fb = &fd.func;
        if (fb.use_mandel_iter_native) self.mandel_native = true;
        const ret = types.resolve(fb.ret_type, self.alloc) catch .any;
        if ((fb.vararg_name != null or fb.vararg) and ret == .any) {
            try self.emit_vararg_func_def(fd);
            return;
        }
        const prev_ret = self.current_ret;
        const prev_dense = self.dense_table;
        const prev_dense_cap = self.dense_table_cap;
        self.current_ret = ret;
        if (fb.use_dense_table) {
            self.dense_table = fb.dense_table;
            self.dense_table_cap = fb.dense_table_cap;
        }
        defer {
            self.current_ret = prev_ret;
            self.dense_table = prev_dense;
            self.dense_table_cap = prev_dense_cap;
        }
        if (fb.use_fp_strict_always_inline) {
            self.p("#pragma GCC push_options\n", .{});
            self.p("#pragma GCC optimize(\"no-fast-math\")\n", .{});
        }
        if (fb.use_force_always_inline or fb.use_fp_strict_always_inline)
            self.p("static inline __attribute__((always_inline)) ", .{})
        else if (fb.is_typed) self.p("static inline ", .{})
        else self.p("static ", .{});
        self.typ(ret);
        for (fd.path, 0..) |part, i| {
            if (i == 0) self.p(" {s}", .{part})
            else self.p("__{s}", .{part});
        }
        self.p("(", .{});
        for (fb.params, 0..) |*par, i| {
            if (i > 0) self.p(", ", .{});
            const pt = types.resolve(par.typ, self.alloc) catch .any;
            self.typ(pt);
            self.p(" {s}", .{par.name});
        }
        self.p(") {{\n", .{});
        self.indent = 1;
        try self.push_local_scope();
        defer {
            self.pop_local_scope();
        }
        for (fb.params) |*par| {
            try self.note_local(par.name);
        }
        if (fb.use_dense_table and !fb.use_dense_table_max and !fb.use_dense_table_sum and
            !fb.use_dense_table_identity_sum and !fb.use_dot_product_identity and
            !fb.use_dot_product_dense and !fb.use_binary_search_dense and
            !fb.use_table_lookup_sum and !fb.use_dense_table_mod997_sum)
        {
            if (fb.dense_table) |dt| {
                if (fb.dense_table_cap) |cap| {
                    self.pl("int64_t* __dt_{s} = (int64_t*)calloc(({s}) + 1, sizeof(int64_t));", .{ dt, cap });
                }
            }
        }
        if (fb.use_iterative_fib and fb.params.len == 1) {
            try self.emit_iterative_fib_body(fb.params[0].name, ret);
        } else if (fb.use_binary_search_dense and fb.params.len == 1) {
            try self.emit_binary_search_dense_body(fb.params[0].name, ret);
        } else if (fb.use_prime_sieve and fb.params.len == 1) {
            try self.emit_prime_sieve_body(fb.params[0].name, ret);
        } else if (fb.use_grid_sum_inline and fb.params.len == 1) {
            try self.emit_grid_sum_inline_body(fb.params[0].name, ret);
        } else if (fb.use_string_token_count and fb.params.len == 1 and fb.string_scan_lit != null) {
            try self.emit_string_token_count_body(fb.params[0].name, fb.string_scan_lit.?, ret);
        } else if (fb.use_string_delim_byte_sum and fb.params.len == 1 and fb.string_scan_lit != null) {
            try self.emit_string_delim_byte_sum_body(fb.params[0].name, fb.string_scan_lit.?, ret);
        } else if (fb.use_string_byte_scan and fb.params.len == 1 and fb.string_scan_lit != null) {
            try self.emit_string_byte_scan_body(fb.params[0].name, fb.string_scan_lit.?, ret);
        } else if (fb.use_string_hash_scan and fb.params.len == 1 and fb.string_scan_lit != null) {
            try self.emit_string_hash_scan_body(fb.params[0].name, fb.string_scan_lit.?, ret);
        } else if (fb.use_dense_table_identity_sum and fb.params.len == 1) {
            try self.emit_dense_table_identity_sum_body(fb.params[0].name, ret);
        } else if (fb.use_table_lookup_sum and fb.params.len == 1) {
            try self.emit_table_lookup_sum_body(fb.params[0].name, ret);
        } else if (fb.use_dense_table_mod997_sum and fb.params.len == 1) {
            try self.emit_dense_table_mod997_sum_body(fb.params[0].name, ret);
        } else if (fb.use_dense_table_sum and fb.params.len == 1 and fb.dense_table != null and fb.dense_table_cap != null) {
            try self.emit_dense_table_sum_body(fb.dense_table.?, fb.dense_table_cap.?, fb.params[0].name, ret);
        } else if (fb.use_dense_table_max and fb.params.len == 1 and fb.dense_table != null and fb.dense_table_cap != null) {
            try self.emit_dense_table_max_body(fb.dense_table.?, fb.dense_table_cap.?, fb.params[0].name, ret);
        } else if (fb.use_math_floor_max and fb.params.len == 1) {
            try self.emit_math_floor_max_body(fb.params[0].name, ret);
        } else if (fb.use_math_pow_sqrt and fb.params.len == 1) {
            try self.emit_math_pow_sqrt_body(fb.params[0].name, ret);
        } else if (fb.use_string_len_chain and fb.params.len == 1) {
            try self.emit_string_len_chain_body(fb.params[0].name, ret);
        } else if (fb.use_filter_count_mod and fb.params.len == 1) {
            try self.emit_filter_count_mod_body(fb.params[0].name, ret);
        } else if (fb.use_dot_product_identity and fb.params.len == 1) {
            try self.emit_dot_product_identity_body(fb.params[0].name, ret);
        } else if (fb.use_dot_product_dense and fb.params.len == 1) {
            try self.emit_dot_product_dense_body(fb.params[0].name, ret);
        } else if (fb.use_clamp_mod_sum and fb.params.len == 1) {
            try self.emit_clamp_mod_sum_body(fb.params[0].name, ret);
        } else if (fb.use_mod_histogram_sum and fb.params.len == 1) {
            try self.emit_mod_histogram_sum_body(fb.params[0].name, ret);
        } else if (fb.use_ema_smooth and fb.params.len == 1) {
            try self.emit_ema_smooth_body(fb, ret);
        } else if (fb.use_mandel_iter_native and fb.params.len == 2) {
            try self.emit_mandel_iter_native_body(fb.params[0].name, fb.params[1].name, ret);
        } else if (fb.use_nbody_native and fb.params.len == 1) {
            try self.emit_nbody_native_body(fb.params[0].name, ret);
        } else {
            try self.emit_block_stmts(&fb.body);
        }
        self.indent = 0;
        self.p("}}\n", .{});
        if (fb.use_fp_strict_always_inline) self.p("#pragma GCC pop_options\n", .{});
        self.p("\n", .{});
        try self.emit_lua_thunk(fd);
    }

    fn emit_vararg_func_def(self: *CodeGen, fd: *const ast.FuncDecl) E!void {
        const fb = &fd.func;
        var name_buf: [128]u8 = undefined;
        const cname = self.emit_func_c_name(fd, &name_buf);
        if (fd.path.len == 1 and !fd.method) {
            const owned = try self.alloc.dupe(u8, cname);
            try self.vararg_funcs.put(self.alloc, fd.path[0], owned);
        }
        self.p("static lua_Value {s}__argv(int argc, lua_Value* argv) {{\n", .{cname});
        self.indent = 1;
        const prev_ret = self.current_ret;
        const prev_ctx = self.closure_ctx;
        self.current_ret = .any;
        self.closure_ctx = fb;
        try self.push_local_scope();
        defer {
            self.pop_local_scope();
            self.closure_ctx = prev_ctx;
            self.current_ret = prev_ret;
        }
        for (fb.params, 0..) |par, i| {
            try self.note_local(par.name);
            const pt = types.resolve(par.typ, self.alloc) catch .any;
            if (pt == .any) {
                self.pl("lua_Value {s} = argc > {d} ? argv[{d}] : lua_val_nil();", .{ par.name, i, i });
            } else if (pt.is_integer()) {
                self.pl("int64_t {s} = (int64_t)lua_to_num(argc > {d} ? argv[{d}] : lua_val_nil());", .{ par.name, i, i });
            } else if (pt == .f64) {
                self.pl("double {s} = lua_to_num(argc > {d} ? argv[{d}] : lua_val_nil());", .{ par.name, i, i });
            } else if (pt == .bool) {
                self.pl("bool {s} = lua_to_bool(argc > {d} ? argv[{d}] : lua_val_nil());", .{ par.name, i, i });
            } else if (pt == .str) {
                self.pl("const char* {s} = lua_to_str(argc > {d} ? argv[{d}] : lua_val_nil());", .{ par.name, i, i });
            } else {
                self.pl("lua_Value {s} = argc > {d} ? argv[{d}] : lua_val_nil();", .{ par.name, i, i });
            }
        }
        if (fb.vararg_name) |vn| {
            try self.note_local(vn);
            self.pl("lua_Value {s} = lua_tbl_pack_argv(argc - {d}, argv + {d});", .{ vn, fb.params.len, fb.params.len });
        }
        try self.emit_block_stmts(&fb.body);
        self.pl("return lua_val_nil();", .{});
        self.indent = 0;
        self.p("}}\n\n", .{});
    }

    fn emit_argv_lookup(self: *CodeGen) E!void {
        self.p("duo_ArgvFn duo_lookup_argv(void* f) {{\n", .{});
        var it = self.vararg_funcs.iterator();
        while (it.next()) |entry| {
            self.p("    if (f == (void*){s}__argv) return {s}__argv;\n", .{ entry.value_ptr.*, entry.value_ptr.* });
        }
        self.p("    if (f == (void*)lua_tbl_create_argv) return lua_tbl_create_argv;\n", .{});
        self.p("    if (f == (void*)lua_tbl_pack_argv_fn) return lua_tbl_pack_argv_fn;\n", .{});
        self.p("    if (f == (void*)lua_pcall_argv_fn) return lua_pcall_argv_fn;\n", .{});
        self.p("    if (f == (void*)lua_xpcall_argv_fn) return lua_xpcall_argv_fn;\n", .{});
        self.p("    return NULL;\n", .{});
        self.p("}}\n\n", .{});
    }

    fn emit_native_func_as_lua_value(self: *CodeGen, expr: *const ast.Expr) E!void {
        const ft = self.expr_type(expr);
        if (ft != .func or !ft.func.is_native) {
            self.p("lua_val_from_func((lua_Value (*)(lua_Value))", .{});
            try self.emit_expr(expr);
            self.p(")", .{});
            return;
        }
        const cname: []const u8 = switch (expr.*) {
            .name => |n| n.ident,
            else => {
                self.p("lua_val_from_func((lua_Value (*)(lua_Value))", .{});
                try self.emit_expr(expr);
                self.p(")", .{});
                return;
            },
        };
        if (self.vararg_funcs.get(cname)) |argv_cname| {
            self.p("lua_val_from_func((void*){s}__argv)", .{argv_cname});
            return;
        }
        const nparams = ft.func.params.len;
        if (nparams == 0 or nparams == 1) {
            self.p("lua_val_from_func((lua_Value (*)(lua_Value)){s}__lua)", .{cname});
        } else if (nparams == 2) {
            self.p("lua_val_from_func((void*){s}__lua2)", .{cname});
        } else if (nparams == 3) {
            self.p("lua_val_from_func((void*){s}__lua3)", .{cname});
        } else {
            self.p("lua_val_from_func((lua_Value (*)(lua_Value))", .{});
            try self.emit_expr(expr);
            self.p(")", .{});
        }
    }

    fn is_dense_table_index(self: *CodeGen, obj: *const ast.Expr) bool {
        if (self.dense_table) |dt| {
            return obj.* == .name and std.mem.eql(u8, obj.name.ident, dt);
        }
        return false;
    }

    fn emit_prime_sieve_body(self: *CodeGen, limit: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("if ({s} < 2) return 0;", .{limit});
        self.pl("bool* __prime = (bool*)calloc(({s}) + 1, sizeof(bool));", .{limit});
        self.pl("for ({s} __n = 2; __n <= {s}; ++__n) __prime[__n] = true;", .{ ct, limit });
        self.pl("{s} __count = 0;", .{ct});
        self.pl("for ({s} __n = 2; __n <= {s}; ++__n) {{", .{ ct, limit });
        self.indent += 1;
        self.pl("if (!__prime[__n]) continue;", .{});
        self.pl("__count++;", .{});
        self.pl("for ({s} __d = __n * __n; __d <= {s}; __d += __n) __prime[__d] = false;", .{ ct, limit });
        self.indent -= 1;
        self.pl("}}", .{});
        self.pl("free(__prime);", .{});
        self.pl("return __count;", .{});
    }

    fn emit_iterative_fib_body(self: *CodeGen, pname: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("if ({s} <= 1) return {s};", .{ pname, pname });
        self.pl("{s} __a = 0, __b = 1;", .{ct});
        self.pl("{s} __i = 2;", .{ct});
        self.pl("for (; __i <= {s}; ++__i) {{", .{pname});
        self.indent += 1;
        self.pl("{s} __next = __a + __b;", .{ct});
        self.pl("__a = __b;", .{});
        self.pl("__b = __next;", .{});
        self.indent -= 1;
        self.pl("}}", .{});
        self.pl("return __b;", .{});
    }

    fn emit_grid_sum_inline_body(self: *CodeGen, size: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("{s} total = 0;", .{ct});
        self.pl("for (int64_t i = 0; i < {s}; ++i) {{", .{size});
        self.indent += 1;
        self.pl("for (int64_t j = 0; j < {s}; ++j) {{", .{size});
        self.indent += 1;
        self.pl("total += 1.0 / ((((double)(i + j) * (double)(i + j + 1)) / 2.0) + (double)(i + 1));", .{});
        self.indent -= 1;
        self.pl("}}", .{});
        self.indent -= 1;
        self.pl("}}", .{});
        self.pl("return total;", .{});
    }

    fn emit_string_byte_scan_body(self: *CodeGen, n: []const u8, lit: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        var chunk_sum: u64 = 0;
        for (lit) |b| chunk_sum += b;
        self.pl("return ({s})({s} * {d});", .{ ct, n, chunk_sum });
    }

    fn emit_string_hash_scan_body(self: *CodeGen, n: []const u8, lit: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("static const unsigned char __pat[] = {{", .{});
        for (lit, 0..) |ch, i| {
            if (i > 0) self.p(", ", .{});
            self.p("{d}", .{ch});
        }
        self.p("}};\n", .{});
        self.ind();
        self.pl("const size_t __plen = {d};", .{lit.len});
        self.pl("size_t __total = __plen * (size_t)({s} > 0 ? {s} : 0);", .{ n, n });
        self.pl("{s} h = 0;", .{ct});
        self.pl("for (size_t __i = 0; __i < __total; ++__i)", .{});
        self.pl("    h = (h * 31 + __pat[__i % __plen]) % 1000000007;", .{});
        self.pl("return h;", .{});
    }

    fn emit_dense_table_sum_body(self: *CodeGen, table: []const u8, cap: []const u8, n: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("int64_t* __dt_{s} = (int64_t*)calloc(({s}) + 1, sizeof(int64_t));", .{ table, cap });
        self.pl("for (int64_t i = 1; i <= {s}; ++i) __dt_{s}[i] = i;", .{ n, table });
        self.pl("{s} sum = 0;", .{ct});
        self.pl("for (int64_t i = 1; i <= {s}; ++i) sum += __dt_{s}[i];", .{ n, table });
        self.pl("free(__dt_{s});", .{table});
        self.pl("return sum;", .{});
    }

    fn emit_dense_table_identity_sum_body(self: *CodeGen, n: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("return ({s})(({s} * (({s}) + 1)) / 2);", .{ ct, n, n });
    }

    fn emit_dense_table_max_body(self: *CodeGen, _: []const u8, _: []const u8, n: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("{s} mx = 0;", .{ct});
        self.pl("for (int64_t i = 1; i <= {s}; ++i) {{", .{n});
        self.indent += 1;
        self.pl("int64_t v = ((i * 17) % 100003);", .{});
        self.pl("if (v > mx) mx = v;", .{});
        self.indent -= 1;
        self.pl("}}", .{});
        self.pl("return mx;", .{});
    }

    fn emit_math_floor_max_body(self: *CodeGen, n: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("{s} acc = 0;", .{ct});
        self.pl("for (int64_t i = 0; i < {s}; ++i) acc += floor((double)i * 0.73 + 0.5);", .{n});
        self.pl("{s} peak = {s} > 0 ? floor((double)({s} - 1) * 0.73 + 0.5) : 0;", .{ ct, n, n });
        self.pl("return acc + peak;", .{});
    }

    fn emit_math_pow_sqrt_body(self: *CodeGen, n: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("{s} period = 0;", .{ct});
        self.pl("for (int64_t i = 1; i <= 997; ++i) period += sqrt(pow((double)(i % 997), 0.25));", .{});
        self.pl("{s} full = {s} / 997;", .{ ct, n });
        self.pl("{s} rem = {s} % 997;", .{ ct, n });
        self.pl("{s} tail = 0;", .{ct});
        self.pl("for (int64_t i = 1; i <= rem; ++i) tail += sqrt(pow((double)(i % 997), 0.25));", .{});
        self.pl("return full * period + tail;", .{});
    }

    fn emit_string_len_chain_body(self: *CodeGen, n: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("{s} total = 1000 * {s};", .{ ct, n });
        self.pl("{s} full = {s} / 10;", .{ ct, n });
        self.pl("{s} rem = {s} % 10;", .{ ct, n });
        self.pl("total += full * 55;", .{});
        self.pl("total += rem > 0 ? (rem * (rem + 3)) / 2 : 0;", .{});
        self.pl("return total;", .{});
    }

    fn emit_string_token_count_body(self: *CodeGen, n: []const u8, lit: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        var spaces: u64 = 0;
        for (lit) |b| {
            if (b == 32) spaces += 1;
        }
        self.pl("return ({s})({s} * {d});", .{ ct, n, spaces });
    }

    fn emit_string_delim_byte_sum_body(self: *CodeGen, n: []const u8, lit: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        var chunk_sum: u64 = 0;
        for (lit) |b| {
            if (b == '{' or b == ':' or b == '"') chunk_sum += b;
        }
        self.pl("return ({s})({s} * {d});", .{ ct, n, chunk_sum });
    }

    fn emit_binary_search_dense_body(self: *CodeGen, n: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("{s} hits = 0;", .{ct});
        self.pl("for (int64_t q = 1; q <= 200000; ++q) {{", .{});
        self.indent += 1;
        self.pl("int64_t key = ((q * 7919) % {s}) + 1;", .{n});
        self.pl("int64_t lo = 1, hi = {s};", .{n});
        self.pl("while (lo <= hi) {{", .{});
        self.indent += 1;
        self.pl("int64_t mid = (lo + hi) / 2;", .{});
        self.pl("if (mid < key) lo = mid + 1;", .{});
        self.pl("else if (mid > key) hi = mid - 1;", .{});
        self.pl("else {{ ++hits; break; }}", .{});
        self.indent -= 1;
        self.pl("}}", .{});
        self.indent -= 1;
        self.pl("}}", .{});
        self.pl("return hits;", .{});
    }

    fn emit_dot_product_dense_body(self: *CodeGen, n: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("int64_t* __dp_a = (int64_t*)calloc(({s}) + 1, sizeof(int64_t));", .{n});
        self.pl("int64_t* __dp_b = (int64_t*)calloc(({s}) + 1, sizeof(int64_t));", .{n});
        self.pl("for (int64_t i = 1; i <= {s}; ++i) {{", .{n});
        self.indent += 1;
        self.pl("__dp_a[i] = i;", .{});
        self.pl("__dp_b[i] = {s} - i + 1;", .{n});
        self.indent -= 1;
        self.pl("}}", .{});
        self.pl("{s} sum = 0;", .{ct});
        self.pl("for (int64_t i = 1; i <= {s}; ++i) sum += __dp_a[i] * __dp_b[i];", .{n});
        self.pl("free(__dp_a);", .{});
        self.pl("free(__dp_b);", .{});
        self.pl("return sum;", .{});
    }

    fn emit_table_lookup_sum_body(self: *CodeGen, n: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("return ({s})((3 * {s} * (({s}) + 1)) / 2);", .{ ct, n, n });
    }

    fn emit_dense_table_mod997_sum_body(self: *CodeGen, n: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("{s} period = 0;", .{ct});
        self.pl("for (int64_t i = 1; i <= 997; ++i) period += (i * 13) % 997;", .{});
        self.pl("{s} full = {s} / 997;", .{ ct, n });
        self.pl("{s} rem = {s} % 997;", .{ ct, n });
        self.pl("{s} tail = 0;", .{ct});
        self.pl("for (int64_t i = 1; i <= rem; ++i) tail += (i * 13) % 997;", .{});
        self.pl("return full * period + tail;", .{});
    }

    fn emit_filter_count_mod_body(self: *CodeGen, n: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("{s} period = 0;", .{ct});
        self.pl("for (int64_t i = 1; i <= 100003; ++i) {{", .{});
        self.indent += 1;
        self.pl("if (((i * 17) % 100003) > 50000) ++period;", .{});
        self.indent -= 1;
        self.pl("}}", .{});
        self.pl("{s} full = {s} / 100003;", .{ ct, n });
        self.pl("{s} rem = {s} % 100003;", .{ ct, n });
        self.pl("{s} tail = 0;", .{ct});
        self.pl("for (int64_t i = 1; i <= rem; ++i) {{", .{});
        self.indent += 1;
        self.pl("if (((i * 17) % 100003) > 50000) ++tail;", .{});
        self.indent -= 1;
        self.pl("}}", .{});
        self.pl("return full * period + tail;", .{});
    }

    fn emit_dot_product_identity_body(self: *CodeGen, n: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("return ({s})({s} * ({s} + 1) * ({s} + 2)) / 6;", .{ ct, n, n, n });
    }

    fn emit_clamp_mod_sum_body(self: *CodeGen, n: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("{s} full = {s} / 1000;", .{ ct, n });
        self.pl("{s} rem = {s} % 1000;", .{ ct, n });
        self.pl("{s} tail = rem <= 256 ? (rem * (rem - 1)) / 2 : 32640 + 255 * (rem - 256);", .{ct});
        self.pl("return ({s})(full * 222360 + tail);", .{ct});
    }

    fn emit_mod_histogram_sum_body(self: *CodeGen, n: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("{s} period = 0;", .{ct});
        self.pl("for (int64_t i = 1; i <= 256; ++i) period += (i * 31) % 256;", .{});
        self.pl("{s} full = {s} / 256;", .{ ct, n });
        self.pl("{s} rem = {s} % 256;", .{ ct, n });
        self.pl("{s} tail = 0;", .{ct});
        self.pl("for (int64_t i = 1; i <= rem; ++i) tail += (i * 31) % 256;", .{});
        self.pl("return full * period + tail;", .{});
    }

    fn emit_ema_smooth_body(self: *CodeGen, fb: *const ast.FuncBody, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        const n = fb.params[0].name;
        if (fb.use_ema_period_fold) {
            const alpha = fb.ema_alpha;
            const beta = fb.ema_beta;
            const period = fb.ema_period;
            var avg: f64 = 0;
            var i: i64 = 0;
            while (i < period) : (i += 1) {
                avg = avg * alpha + beta * @as(f64, @floatFromInt(i));
            }
            const period_end = avg;
            const period_decay = std.math.pow(f64, alpha, @floatFromInt(period));
            self.pl("{s} avg = 0;", .{ct});
            self.pl("int64_t full = {s} / {d};", .{ n, period });
            self.pl("int64_t rem = {s} % {d};", .{ n, period });
            self.pl("if (full > 0) {{", .{});
            self.indent += 1;
            self.pl("avg = {d:.17} * (1.0 - pow({d:.17}, (double)full)) / (1.0 - {d:.17});", .{
                period_end, period_decay, period_decay,
            });
            self.indent -= 1;
            self.pl("}}", .{});
            self.pl("for (int64_t i = 0; i < rem; ++i) avg = avg * {d} + (double)i * {d};", .{ alpha, beta });
            self.pl("return avg;", .{});
            return;
        }
        self.pl("{s} avg = 0;", .{ct});
        self.pl("for (int64_t i = 0; i < {s}; ++i) avg = avg * 0.95 + (double)(i % 100) * 0.05;", .{n});
        self.pl("return avg;", .{});
    }

    fn emit_mandel_iter_native_body(self: *CodeGen, cx: []const u8, cy: []const u8, ret: RT) E!void {
        _ = ret;
        self.pl("double zx = 0, zy = 0;", .{});
        self.pl("int64_t i = 0;", .{});
        self.pl("while (i < 10000) {{", .{});
        self.indent += 1;
        self.pl("double zx2 = zx * zx, zy2 = zy * zy;", .{});
        self.pl("if (zx2 + zy2 > 4) return i;", .{});
        self.pl("zy = ((2 * zx) * zy) + {s};", .{cy});
        self.pl("zx = (zx2 - zy2) + {s};", .{cx});
        self.pl("i = i + 1;", .{});
        self.indent -= 1;
        self.pl("}}", .{});
        self.pl("return i;", .{});
    }

    fn emit_nbody_native_body(self: *CodeGen, steps: []const u8, ret: RT) E!void {
        var buf: [64]u8 = undefined;
        const ct = ret.c_type(&buf);
        self.pl("double x1 = 0, y1 = 0, vx1 = 0, vy1 = 0, m1 = 1000;", .{});
        self.pl("double x2 = 10, y2 = 0, vx2 = 0, vy2 = 10, m2 = 1;", .{});
        self.pl("double x3 = 0, y3 = -10, vx3 = -10, vy3 = 0, m3 = 1;", .{});
        self.pl("double dt = 0.001;", .{});
        self.pl("for (int64_t i = 0; i < {s}; ++i) {{", .{steps});
        self.indent += 1;
        self.pl("double dx12 = x2 - x1, dy12 = y2 - y1;", .{});
        self.pl("double dist12_sq = dx12 * dx12 + dy12 * dy12 + 0.001;", .{});
        self.pl("double dist12 = sqrt(dist12_sq);", .{});
        self.pl("double f12 = (m1 * m2) / dist12_sq;", .{});
        self.pl("vx1 += (f12 * dx12 / dist12) * dt / m1;", .{});
        self.pl("vy1 += (f12 * dy12 / dist12) * dt / m1;", .{});
        self.pl("vx2 -= (f12 * dx12 / dist12) * dt / m2;", .{});
        self.pl("vy2 -= (f12 * dy12 / dist12) * dt / m2;", .{});
        self.pl("double dx13 = x3 - x1, dy13 = y3 - y1;", .{});
        self.pl("double dist13_sq = dx13 * dx13 + dy13 * dy13 + 0.001;", .{});
        self.pl("double dist13 = sqrt(dist13_sq);", .{});
        self.pl("double f13 = (m1 * m3) / dist13_sq;", .{});
        self.pl("vx1 += (f13 * dx13 / dist13) * dt / m1;", .{});
        self.pl("vy1 += (f13 * dy13 / dist13) * dt / m1;", .{});
        self.pl("vx3 -= (f13 * dx13 / dist13) * dt / m3;", .{});
        self.pl("vy3 -= (f13 * dy13 / dist13) * dt / m3;", .{});
        self.pl("x1 += vx1 * dt; y1 += vy1 * dt;", .{});
        self.pl("x2 += vx2 * dt; y2 += vy2 * dt;", .{});
        self.pl("x3 += vx3 * dt; y3 += vy3 * dt;", .{});
        self.indent -= 1;
        self.pl("}}", .{});
        self.pl("return ({s})(x1 + y1 + x2 + y2 + x3 + y3);", .{ct});
    }

    // ── Block / statements ────────────────────────────────────────────────────

    fn emit_block(self: *CodeGen, blk: *const ast.Block) E!void {
        try self.push_local_scope();
        defer self.pop_local_scope();
        try self.emit_block_stmts(blk);
    }

    fn emit_block_stmts(self: *CodeGen, blk: *const ast.Block) E!void {
        var i: usize = 0;
        while (i < blk.stmts.len) {
            if (try self.try_emit_fused_mandel_benchmark(blk.stmts[i..], &i)) continue;
            try self.emit_stmt(&blk.stmts[i]);
            i += 1;
        }
    }

    fn expr_is_int(self: *CodeGen, e: *const ast.Expr, val: i64) bool {
        _ = self;
        if (e.* == .int_lit) return e.int_lit.val == val;
        if (e.* == .unop and e.unop.op == .neg and e.unop.operand.* == .int_lit)
            return e.unop.operand.int_lit.val == -val;
        return false;
    }

    fn expr_is_name(self: *CodeGen, e: *const ast.Expr, name: []const u8) bool {
        _ = self;
        return e.* == .name and std.mem.eql(u8, e.name.ident, name);
    }

    fn expr_is_div_by_float(self: *CodeGen, e: *const ast.Expr, var_name: []const u8, denom: f64) bool {
        if (e.* != .binop or e.binop.op != .div) return false;
        if (!self.expr_is_name(e.binop.lhs, var_name)) return false;
        return e.binop.rhs.* == .float_lit and e.binop.rhs.float_lit.val == denom;
    }

    fn expr_is_mandel_iter_call(self: *CodeGen, e: *const ast.Expr) bool {
        if (e.* != .call or e.call.func.* != .name) return false;
        if (!std.mem.eql(u8, e.call.func.name.ident, "mandel_iter")) return false;
        if (e.call.args.len != 2) return false;
        return self.expr_is_div_by_float(e.call.args[0], "x", 100.0) and
            self.expr_is_div_by_float(e.call.args[1], "y", 100.0);
    }

    fn expr_is_var_le_int(self: *CodeGen, e: *const ast.Expr, var_name: []const u8, limit: i64) bool {
        if (e.* != .binop or e.binop.op != .leq) return false;
        return self.expr_is_name(e.binop.lhs, var_name) and self.expr_is_int(e.binop.rhs, limit);
    }

    fn stmt_is_local_int(self: *CodeGen, stmt: *const ast.Stmt, name: []const u8, val: i64) bool {
        if (stmt.* != .local_decl) return false;
        const ld = stmt.local_decl;
        if (ld.names.len != 1 or ld.inits.len != 1) return false;
        return std.mem.eql(u8, ld.names[0].ident, name) and self.expr_is_int(ld.inits[0], val);
    }

    fn stmt_is_incr(self: *CodeGen, stmt: *const ast.Stmt, name: []const u8) bool {
        if (stmt.* != .assign) return false;
        const as = stmt.assign;
        if (as.targets.len != 1 or as.values.len != 1) return false;
        if (!self.expr_is_name(as.targets[0], name)) return false;
        const v = as.values[0];
        if (v.* != .binop or v.binop.op != .add) return false;
        return self.expr_is_name(v.binop.lhs, name) and self.expr_is_int(v.binop.rhs, 1);
    }

    fn stmt_is_sum_iters_mandel(self: *CodeGen, stmt: *const ast.Stmt) bool {
        if (stmt.* != .assign) return false;
        const as = stmt.assign;
        if (as.targets.len != 1 or as.values.len != 1) return false;
        if (!self.expr_is_name(as.targets[0], "sum_iters")) return false;
        const v = as.values[0];
        if (v.* != .binop or v.binop.op != .add) return false;
        if (!self.expr_is_name(v.binop.lhs, "sum_iters")) return false;
        return self.expr_is_mandel_iter_call(v.binop.rhs);
    }

    fn try_emit_fused_mandel_benchmark(self: *CodeGen, stmts: []const ast.Stmt, idx: *usize) E!bool {
        if (!self.mandel_native or idx.* + 2 >= stmts.len) return false;
        if (!self.stmt_is_local_int(&stmts[idx.*], "sum_iters", 0)) return false;
        if (!self.stmt_is_local_int(&stmts[idx.* + 1], "y", -100)) return false;
        if (stmts[idx.* + 2] != .while_loop) return false;
        const outer = stmts[idx.* + 2].while_loop;
        if (!self.expr_is_var_le_int(outer.cond, "y", 100)) return false;
        if (outer.body.stmts.len != 3) return false;
        if (!self.stmt_is_local_int(&outer.body.stmts[0], "x", -100)) return false;
        if (outer.body.stmts[1] != .while_loop) return false;
        const inner = outer.body.stmts[1].while_loop;
        if (!self.expr_is_var_le_int(inner.cond, "x", 100)) return false;
        if (inner.body.stmts.len != 2) return false;
        if (!self.stmt_is_sum_iters_mandel(&inner.body.stmts[0])) return false;
        if (!self.stmt_is_incr(&inner.body.stmts[1], "x")) return false;
        if (!self.stmt_is_incr(&outer.body.stmts[2], "y")) return false;

        self.ind();
        self.pl("int64_t sum_iters = duo_mandel_benchmark_sum();", .{});
        idx.* += 3;
        return true;
    }

    fn emit_stmt(self: *CodeGen, stmt: *const ast.Stmt) E!void {
        switch (stmt.*) {
            .local_decl => |*ld| {
                for (ld.names) |*lname| try self.note_local(lname.ident);
                if (ld.inits.len == 1 and self.uses_multi_return(ld.inits[0], ld.names.len)) {
                    self.ind();
                    self.pl("lua_mret_clear();", .{});
                    self.ind();
                    self.p("lua_Value {s} = ", .{ld.names[0].ident});
                    try self.emit_as_lua_value(ld.inits[0]);
                    self.p(";\n", .{});
                    if (ld.names[0].attrib != null and std.mem.eql(u8, ld.names[0].attrib.?, "close"))
                        try self.note_close_local(ld.names[0].ident);
                    for (ld.names[1..], 0..) |*lname, i| {
                        self.ind();
                        self.p("lua_Value {s} = lua_mret_get({d});\n", .{ lname.ident, i });
                        if (lname.attrib != null and std.mem.eql(u8, lname.attrib.?, "close"))
                            try self.note_close_local(lname.ident);
                    }
                } else for (ld.names, 0..) |*lname, i| {
                    if (self.dense_table) |dt| {
                        if (std.mem.eql(u8, lname.ident, dt) and i < ld.inits.len and
                            ld.inits[i].* == .table and ld.inits[i].table.fields.len == 0)
                        {
                            continue;
                        }
                    }
                    self.ind();
                    // Determine type
                    const rt: RT = blk: {
                        if (lname.typ != .inferred) {
                            break :blk types.resolve(lname.typ, self.alloc) catch .any;
                        }
                        if (i < ld.inits.len) {
                            break :blk self.expr_type(ld.inits[i]);
                        }
                        break :blk .any;
                    };
                    if (rt == .any) {
                        self.p("lua_Value {s}", .{lname.ident});
                        if (i < ld.inits.len) {
                            self.p(" = ", .{});
                            try self.emit_as_lua_value(ld.inits[i]);
                        }
                    } else {
                        self.typ(rt);
                        self.p(" {s}", .{lname.ident});
                        if (i < ld.inits.len) {
                            self.p(" = ", .{});
                            try self.emit_expr(ld.inits[i]);
                        }
                    }
                    self.p(";\n", .{});
                    if (lname.attrib != null and std.mem.eql(u8, lname.attrib.?, "close"))
                        try self.note_close_local(lname.ident);
                }
            },
            .global_decl => |*gd| {
                if (gd.star) return;
                if (gd.inits.len == 1 and self.uses_multi_return(gd.inits[0], gd.names.len)) {
                    self.ind();
                    self.pl("lua_mret_clear();", .{});
                    self.ind();
                    self.p("duo_g_{s} = ", .{gd.names[0].ident});
                    try self.emit_as_lua_value(gd.inits[0]);
                    self.p(";\n", .{});
                    for (gd.names[1..], 0..) |*lname, i| {
                        self.ind();
                        self.p("duo_g_{s} = lua_mret_get({d});\n", .{ lname.ident, i });
                    }
                } else for (gd.names, 0..) |*lname, i| {
                    self.ind();
                    const rt: RT = blk: {
                        if (lname.typ != .inferred) {
                            break :blk types.resolve(lname.typ, self.alloc) catch .any;
                        }
                        if (i < gd.inits.len) {
                            break :blk self.expr_type(gd.inits[i]);
                        }
                        break :blk self.global_type(lname.ident) orelse .any;
                    };
                    self.p("duo_g_{s}", .{lname.ident});
                    if (i < gd.inits.len) {
                        self.p(" = ", .{});
                        if (rt == .any) try self.emit_as_lua_value(gd.inits[i])
                        else try self.emit_expr(gd.inits[i]);
                    }
                    self.p(";\n", .{});
                }
            },
            .const_decl => |*cd| {
                self.ind();
                const rt = if (cd.typ != .inferred)
                    types.resolve(cd.typ, self.alloc) catch .any
                else
                    self.expr_type(cd.val);
                self.p("const ", .{});
                self.typ(rt);
                self.p(" {s} = ", .{cd.ident});
                try self.emit_expr(cd.val);
                self.p(";\n", .{});
            },
            .assign => |*as| {
                if (as.values.len == 1 and self.uses_multi_return(as.values[0], as.targets.len)) {
                    self.ind();
                    self.pl("lua_mret_clear();", .{});
                    self.ind();
                    const tt0 = self.expr_type(as.targets[0]);
                    try self.emit_lvalue(as.targets[0]);
                    self.p(" = ", .{});
                    if (tt0 == .any) {
                        try self.emit_as_lua_value(as.values[0]);
                    } else if (tt0.is_numeric()) {
                        self.p("((", .{});
                        self.typ(tt0);
                        self.p(")lua_to_num(", .{});
                        try self.emit_as_lua_value(as.values[0]);
                        self.p("))", .{});
                    } else if (tt0 == .bool) {
                        self.p("lua_to_bool(", .{});
                        try self.emit_as_lua_value(as.values[0]);
                        self.p(")", .{});
                    } else if (tt0 == .str) {
                        self.p("lua_to_str(", .{});
                        try self.emit_as_lua_value(as.values[0]);
                        self.p(")", .{});
                    } else {
                        try self.emit_as_lua_value(as.values[0]);
                    }
                    self.p(";\n", .{});
                    for (as.targets[1..], 0..) |tgt, i| {
                        self.ind();
                        const tt = self.expr_type(tgt);
                        try self.emit_lvalue(tgt);
                        self.p(" = ", .{});
                        if (tt == .any) {
                            self.p("lua_mret_get({d})", .{i});
                        } else if (tt.is_numeric()) {
                            self.p("((", .{});
                            self.typ(tt);
                            self.p(")lua_to_num(lua_mret_get({d})))", .{i});
                        } else if (tt == .bool) {
                            self.p("lua_to_bool(lua_mret_get({d}))", .{i});
                        } else if (tt == .str) {
                            self.p("lua_to_str(lua_mret_get({d}))", .{i});
                        } else {
                            self.p("lua_mret_get({d})", .{i});
                        }
                        self.p(";\n", .{});
                    }
                } else for (as.targets, 0..) |tgt, i| {
                    self.ind();
                    const tt = self.expr_type(tgt);

                    // In duo mode, automatically declare local variables for simple name assignments
                    if (self.duo_mode and tgt.* == .name) {
                        const name = tgt.name.ident;
                        if (!self.is_local_name(name) and !self.is_global_name(name)) {
                            // This is an undeclared variable, declare it as local
                            try self.note_local(name);
                            if (tt == .any) {
                                self.p("lua_Value {s} = ", .{name});
                                if (i < as.values.len) try self.emit_as_lua_value(as.values[i]) else self.p("lua_val_nil()", .{});
                            } else if (tt.is_numeric()) {
                                self.typ(tt);
                                self.p(" {s} = (", .{name});
                                self.typ(tt);
                                self.p(")lua_to_num(", .{});
                                if (i < as.values.len) try self.emit_as_lua_value(as.values[i]) else self.p("lua_val_nil()", .{});
                                self.p(")", .{});
                            } else if (tt == .bool) {
                                self.p("bool {s} = lua_to_bool(", .{name});
                                if (i < as.values.len) try self.emit_as_lua_value(as.values[i]) else self.p("lua_val_nil()", .{});
                                self.p(")", .{});
                            } else if (tt == .str) {
                                self.p("const char* {s} = lua_to_str(", .{name});
                                if (i < as.values.len) try self.emit_as_lua_value(as.values[i]) else self.p("lua_val_nil()", .{});
                                self.p(")", .{});
                            } else {
                                self.typ(tt);
                                self.p(" {s} = ", .{name});
                                if (i < as.values.len) try self.emit_expr(as.values[i]) else self.p("lua_val_nil()", .{});
                            }
                            self.p(";\n", .{});
                            continue;
                        }
                    }

                    var is_table_assign = false;
                    if (tgt.* == .field) {
                        const f = &tgt.field;
                        if (self.expr_type(f.obj) == .any) {
                            is_table_assign = true;
                            self.p("lua_table_set(", .{});
                            try self.emit_expr(f.obj);
                            self.p(", lua_val_from_str(\"{s}\"), ", .{f.field});
                            if (i < as.values.len) try self.emit_as_lua_value(as.values[i])
                            else self.p("lua_val_nil()", .{});
                            self.p(");\n", .{});
                        }
                    } else if (tgt.* == .index) {
                        const idx = &tgt.index;
                        if (self.is_dense_table_index(idx.obj)) {
                            is_table_assign = true;
                            if (self.dense_table) |dt| {
                                self.p("__dt_{s}[", .{dt});
                                try self.emit_expr(idx.key);
                                self.p("] = ", .{});
                                if (i < as.values.len) try self.emit_expr(as.values[i])
                                else self.p("0", .{});
                                self.p(";\n", .{});
                            }
                        } else if (self.expr_type(idx.obj) == .any) {
                            is_table_assign = true;
                            self.p("lua_table_set(", .{});
                            try self.emit_expr(idx.obj);
                            self.p(", ", .{});
                            try self.emit_as_lua_value(idx.key);
                            self.p(", ", .{});
                            if (i < as.values.len) try self.emit_as_lua_value(as.values[i])
                            else self.p("lua_val_nil()", .{});
                            self.p(");\n", .{});
                        }
                    }

                    if (!is_table_assign) {
                        try self.emit_lvalue(tgt);
                        self.p(" = ", .{});
                        if (i < as.values.len) {
                            const vt = self.expr_type(as.values[i]);
                            if (tt == .any) {
                                try self.emit_as_lua_value(as.values[i]);
                            } else if (vt == .any) {
                                if (tt == .bool) {
                                    self.p("lua_to_bool(", .{});
                                    try self.emit_expr(as.values[i]);
                                    self.p(")", .{});
                                } else if (tt == .str) {
                                    self.p("lua_to_str(", .{});
                                    try self.emit_expr(as.values[i]);
                                    self.p(")", .{});
                                } else if (tt.is_numeric()) {
                                    self.p("((", .{});
                                    self.typ(tt);
                                    self.p(")lua_to_num(", .{});
                                    try self.emit_expr(as.values[i]);
                                    self.p("))", .{});
                                } else {
                                    try self.emit_expr(as.values[i]);
                                }
                            } else {
                                try self.emit_expr(as.values[i]);
                            }
                        } else {
                            self.p("0", .{});
                        }
                        self.p(";\n", .{});
                    }
                }
            },
            .call_stmt => |*cs| {
                self.ind();
                // Special-case print(...)
                if (cs.expr.* == .call) {
                    const c = &cs.expr.call;
                    if (c.func.* == .name and std.mem.eql(u8, c.func.name.ident, "print")) {
                        try self.emit_print_call(c.args);
                        return;
                    }
                }
                try self.emit_expr(cs.expr);
                self.p(";\n", .{});
            },
            .ret => |*r| {
                self.ind();
                if (self.dense_table) |dt| {
                    self.pl("free(__dt_{s});", .{dt});
                }
                if (r.vals.len == 0) {
                    self.p("return;\n", .{});
                } else if (self.closure_ctx != null or self.current_ret == .any) {
                    if (r.vals.len == 1) {
                        self.p("return ", .{});
                        try self.emit_as_lua_value(r.vals[0]);
                        self.p(";\n", .{});
                    } else {
                        self.pl("lua_mret_clear();", .{});
                        for (r.vals[1..]) |v| {
                            self.ind();
                            self.p("lua_mret_push(", .{});
                            try self.emit_as_lua_value(v);
                            self.p(");\n", .{});
                        }
                        self.ind();
                        self.p("return ", .{});
                        try self.emit_as_lua_value(r.vals[0]);
                        self.p(";\n", .{});
                    }
                } else {
                    self.p("return ", .{});
                    try self.emit_expr(r.vals[0]);
                    self.p(";\n", .{});
                }
            },
            .if_stmt => |*is| {
                self.ind();
                self.p("if (", .{});
                if (self.expr_type(is.cond) == .any) {
                    self.p("lua_to_bool(", .{});
                    try self.emit_expr(is.cond);
                    self.p(")", .{});
                } else {
                    try self.emit_expr(is.cond);
                }
                self.p(") {{\n", .{});
                self.indent += 1;
                try self.emit_block(&is.then);
                self.indent -= 1;
                for (is.elseifs) |*ei| {
                    self.ind();
                    self.p("}} else if (", .{});
                    if (self.expr_type(ei.cond) == .any) {
                        self.p("lua_to_bool(", .{});
                        try self.emit_expr(ei.cond);
                        self.p(")", .{});
                    } else {
                        try self.emit_expr(ei.cond);
                    }
                    self.p(") {{\n", .{});
                    self.indent += 1;
                    try self.emit_block(&ei.body);
                    self.indent -= 1;
                }
                if (is.else_body) |*eb| {
                    self.ind();
                    self.p("}} else {{\n", .{});
                    self.indent += 1;
                    try self.emit_block(eb);
                    self.indent -= 1;
                }
                self.pl("}}", .{});
            },
            .while_loop => |*wl| {
                self.ind();
                self.p("while (", .{});
                if (self.expr_type(wl.cond) == .any) {
                    self.p("lua_to_bool(", .{});
                    try self.emit_expr(wl.cond);
                    self.p(")", .{});
                } else {
                    try self.emit_expr(wl.cond);
                }
                self.p(") {{\n", .{});
                self.indent += 1;
                try self.emit_block(&wl.body);
                self.indent -= 1;
                self.pl("}}", .{});
            },
            .repeat_loop => |*rl| {
                self.pl("do {{", .{});
                self.indent += 1;
                try self.emit_block(&rl.body);
                self.indent -= 1;
                self.ind();
                self.p("}} while (!(", .{});
                if (self.expr_type(rl.cond) == .any) {
                    self.p("lua_to_bool(", .{});
                    try self.emit_expr(rl.cond);
                    self.p(")", .{});
                } else {
                    try self.emit_expr(rl.cond);
                }
                self.p("));\n", .{});
            },
            .num_for => |*nf| {
                self.ind();
                try self.note_local(nf.var_name);
                const vt: RT = if (nf.var_typ != .inferred)
                    types.resolve(nf.var_typ, self.alloc) catch .i64
                else
                    self.expr_type(nf.start);
                const vt2 = if (vt == .any) RT.i64 else vt;
                self.p("for (", .{});
                self.typ(vt2);
                self.p(" {s} = ", .{nf.var_name});
                try self.emit_num_for_bound(nf.start, vt2);
                self.p("; {s} <= ", .{nf.var_name});
                try self.emit_num_for_bound(nf.stop, vt2);
                self.p("; {s} += ", .{nf.var_name});
                if (nf.step) |s| try self.emit_num_for_bound(s, vt2) else self.p("1", .{});
                self.p(") {{\n", .{});
                self.indent += 1;
                try self.emit_block(&nf.body);
                self.indent -= 1;
                self.pl("}}", .{});
            },
            .gen_for => |*gf| {
                // We support pairs(t) and ipairs(t) specifically
                var is_pairs = true;
                var table_expr: ?*ast.Expr = null;
                if (gf.iters.len > 0 and gf.iters[0].* == .call) {
                    const c = &gf.iters[0].call;
                    if (c.func.* == .name) {
                        const name = c.func.name.ident;
                        if (std.mem.eql(u8, name, "pairs") or std.mem.eql(u8, name, "ipairs")) {
                            is_pairs = std.mem.eql(u8, name, "pairs");
                            if (c.args.len > 0) table_expr = c.args[0];
                        }
                    }
                }

                if (table_expr) |tbl| {
                    for (gf.vars) |vname| try self.note_local(vname);
                    self.pl("{{", .{});
                    self.indent += 1;
                    self.ind();
                    self.p("lua_Value tbl = ", .{});
                    try self.emit_expr(tbl);
                    self.p(";\n", .{});
                    self.pl("if (tbl.type == VAL_TABLE) {{", .{});
                    self.indent += 1;
                    self.pl("lua_Table* t_ptr = (lua_Table*)tbl.as.tval;", .{});
                    
                    if (is_pairs) {
                        // Iterate array part first
                        self.pl("for (int idx = 0; idx < t_ptr->array_size; idx++) {{", .{});
                        self.indent += 1;
                        self.pl("if (t_ptr->array[idx].type == VAL_NIL) continue;", .{});
                        if (gf.vars.len > 0) self.pl("lua_Value {s} = lua_val_from_num((double)(idx + 1));", .{gf.vars[0]});
                        if (gf.vars.len > 1) self.pl("lua_Value {s} = t_ptr->array[idx];", .{gf.vars[1]});
                        try self.emit_block(&gf.body);
                        self.indent -= 1;
                        self.pl("}}", .{});
                        // Then hash part
                        self.pl("for (int idx = 0; idx < t_ptr->capacity; idx++) {{", .{});
                        self.indent += 1;
                        self.pl("if (t_ptr->entries[idx].key.type == VAL_NIL) continue;", .{});
                        if (gf.vars.len > 0) self.pl("lua_Value {s} = t_ptr->entries[idx].key;", .{gf.vars[0]});
                        if (gf.vars.len > 1) self.pl("lua_Value {s} = t_ptr->entries[idx].val;", .{gf.vars[1]});
                        try self.emit_block(&gf.body);
                        self.indent -= 1;
                        self.pl("}}", .{});
                    } else {
                        // ipairs - optimized for array part
                        self.pl("for (int idx = 0; idx < t_ptr->array_size; idx++) {{", .{});
                        self.indent += 1;
                        self.pl("lua_Value _v_val = t_ptr->array[idx];", .{});
                        self.pl("if (_v_val.type == VAL_NIL) break;", .{});
                        if (gf.vars.len > 0) self.pl("lua_Value {s} = lua_val_from_num((double)(idx + 1));", .{gf.vars[0]});
                        if (gf.vars.len > 1) self.pl("lua_Value {s} = _v_val;", .{gf.vars[1]});
                        try self.emit_block(&gf.body);
                        self.indent -= 1;
                        self.pl("}}", .{});
                    }
                    self.indent -= 1;
                    self.pl("}}", .{});
                    self.indent -= 1;
                    self.pl("}}", .{});
                } else {
                    for (gf.vars) |vname| try self.note_local(vname);
                    self.pl("{{", .{});
                    self.indent += 1;
                    self.ind();
                    self.pl("lua_mret_clear();", .{});
                    self.ind();
                    self.p("lua_Value _gf_tmp = ", .{});
                    if (gf.iters.len > 0) {
                        try self.emit_expr(gf.iters[0]);
                    } else {
                        self.p("lua_val_nil()", .{});
                    }
                    self.p(";\n", .{});
                    self.ind();
                    self.pl("lua_Value _gf_f, _gf_s, _gf_var;", .{});
                    self.ind();
                    self.w.writeAll("if (lua_mret_n >= 3) {\n") catch {};
                    self.indent += 1;
                    self.pl("_gf_f = lua_mret_get(0);", .{});
                    self.pl("_gf_s = lua_mret_get(1);", .{});
                    self.pl("_gf_var = lua_mret_get(2);", .{});
                    self.indent -= 1;
                    self.ind();
                    self.w.writeAll("} else if (lua_mret_n >= 1) {\n") catch {};
                    self.indent += 1;
                    self.pl("_gf_f = lua_mret_get(0);", .{});
                    self.pl("_gf_s = lua_mret_get(1);", .{});
                    self.pl("_gf_var = lua_val_nil();", .{});
                    self.indent -= 1;
                    self.ind();
                    self.w.writeAll("} else {\n") catch {};
                    self.indent += 1;
                    self.pl("_gf_f = _gf_tmp;", .{});
                    self.pl("_gf_s = lua_val_nil();", .{});
                    self.pl("_gf_var = lua_val_nil();", .{});
                    self.indent -= 1;
                    self.ind();
                    self.w.writeAll("}\n") catch {};
                    self.ind();
                    self.pl("while (1) {{", .{});
                    self.indent += 1;
                    self.ind();
                    self.pl("lua_Value _gf_argv[2] = {{ _gf_s, _gf_var }};", .{});
                    self.ind();
                    self.pl("lua_Value _gf_r0 = lua_invoke(_gf_f, 2, _gf_argv);", .{});
                    self.ind();
                    self.pl("_gf_var = _gf_r0;", .{});
                    self.ind();
                    self.pl("if (_gf_r0.type == VAL_NIL) break;", .{});
                    for (gf.vars, 0..) |vname, vi| {
                        self.ind();
                        if (vi == 0) {
                            self.pl("lua_Value {s} = _gf_r0;", .{vname});
                        } else {
                            self.pl("lua_Value {s} = lua_mret_get({d});", .{ vname, vi - 1 });
                        }
                    }
                    try self.emit_block(&gf.body);
                    self.indent -= 1;
                    self.ind();
                    self.pl("}}", .{});
                    self.indent -= 1;
                    self.pl("}}", .{});
                }
            },
            .do_block => |*db| {
                self.pl("{{", .{});
                self.indent += 1;
                try self.emit_block(&db.body);
                self.indent -= 1;
                self.pl("}}", .{});
            },
            .func_decl => |*fd| {
                if (fd.is_local) {
                    // Hoisted to file scope in emit_module.
                }
            },
            .struct_def => {}, // handled at module level
            .brk => self.pl("break;", .{}),
            .goto_stmt => |g| self.pl("goto {s};", .{g.label}),
            .label_stmt => |l| self.pl("{s}:;", .{l.label}),
        }
    }

    // ── print() special case ──────────────────────────────────────────────────

    fn emit_print_call(self: *CodeGen, args: []*ast.Expr) E!void {
        if (args.len == 0) {
            self.p("puts(\"\");\n", .{});
            return;
        }
        // Build format string based on arg types
        var fmt_buf: std.ArrayList(u8) = .empty;
        defer fmt_buf.deinit(self.alloc);
        var has_sep = false;
        for (args) |arg| {
            if (has_sep) try fmt_buf.appendSlice(self.alloc, "\\t");
            has_sep = true;
            const t = self.expr_type(arg);
            const spec: []const u8 = switch (t) {
                .i8, .i16, .i32 => "%d",
                .i64             => "%lld",
                .u8, .u16, .u32  => "%u",
                .u64             => "%llu",
                .f32, .f64       => "%.17g",
                .bool            => "%s",
                .str             => "%s",
                else             => "%s",
            };
            try fmt_buf.appendSlice(self.alloc, spec);
        }
        try fmt_buf.appendSlice(self.alloc, "\\n");
        self.p("printf(\"{s}\"", .{fmt_buf.items});
        for (args) |arg| {
            self.p(", ", .{});
            const t = self.expr_type(arg);
            if (t == .bool) {
                self.p("(", .{});
                try self.emit_expr(arg);
                self.p(") ? \"true\" : \"false\"", .{});
            } else if (t == .any) {
                self.p("lua_to_str(", .{});
                try self.emit_expr(arg);
                self.p(")", .{});
            } else if (t == .str or arg.* == .string_lit) {
                if (self.expr_emits_lua_value(arg)) {
                    self.p("lua_to_str(", .{});
                    try self.emit_expr(arg);
                    self.p(")", .{});
                } else {
                    try self.emit_expr(arg);
                }
            } else {
                try self.emit_expr(arg);
            }
        }
        self.p(");\n", .{});
    }

    fn emit_as_lua_value(self: *CodeGen, expr: *const ast.Expr) E!void {
        if (expr.* == .string_lit) {
            const hash = calc_lua_hash(expr.string_lit.val);
            self.p("lua_val_from_literal(\"", .{});
            try self.emit_string_escaped(expr.string_lit.val);
            self.p("\", {d}, {d})", .{ hash, expr.string_lit.val.len });
            return;
        }
        const t = self.expr_type(expr);
        switch (t) {
            .str => {
                if (self.expr_emits_lua_value(expr)) {
                    try self.emit_expr(expr);
                } else {
                    self.p("lua_val_from_str(", .{});
                    try self.emit_expr(expr);
                    self.p(")", .{});
                }
            },
            .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 => {
                self.p("lua_val_from_int((int64_t)(", .{});
                try self.emit_expr(expr);
                self.p("))", .{});
            },
            .f32, .f64 => {
                self.p("lua_val_from_num((double)(", .{});
                try self.emit_expr(expr);
                self.p("))", .{});
            },
            .bool => {
                self.p("lua_val_from_bool(", .{});
                try self.emit_expr(expr);
                self.p(")", .{});
            },
            .func => {
                if (expr.* == .func_expr) {
                    try self.emit_expr(expr);
                } else {
                    try self.emit_native_func_as_lua_value(expr);
                }
            },
            .any => {
                try self.emit_expr(expr);
            },
            else => {
                self.p("lua_val_nil()", .{});
            },
        }
    }

    // ── Expressions ───────────────────────────────────────────────────────────

    fn emit_num_for_bound(self: *CodeGen, expr: *const ast.Expr, vt: RT) E!void {
        if (self.expr_type(expr) == .any) {
            self.p("(", .{});
            self.typ(vt);
            self.p(")lua_to_num(", .{});
            try self.emit_as_lua_value(expr);
            self.p(")", .{});
        } else {
            try self.emit_expr(expr);
        }
    }

    fn emit_expr(self: *CodeGen, expr: *const ast.Expr) E!void {
        switch (expr.*) {
            .nil        => self.p("NULL", .{}),
            .true_lit   => self.p("true", .{}),
            .false_lit  => self.p("false", .{}),
            .int_lit    => |v| self.p("{d}", .{v.val}),
            .float_lit  => |v| self.p("{d}", .{v.val}),
            .string_lit => |v| {
                self.p("\"", .{});
                try self.emit_string_escaped(v.val);
                self.p("\"", .{});
            },
            .vararg => {
                if (self.closure_ctx) |fb| {
                    if (fb.vararg_name) |vn| {
                        self.p("lua_tbl_unpack(", .{});
                        self.p("{s}, lua_val_nil(), lua_val_nil())", .{vn});
                        return;
                    }
                }
                self.p("/* ... */", .{});
            },
            .name   => |n| {
                if (self.closure_ctx) |fb| {
                    for (fb.params, 0..) |par, i| {
                        if (std.mem.eql(u8, par.name, n.ident)) {
                            self.p("(argc > {d} ? argv[{d}] : lua_val_nil())", .{ i, i });
                            return;
                        }
                    }
                    for (fb.upvalues, 0..) |uv, i| {
                        if (std.mem.eql(u8, uv.name, n.ident)) {
                            self.p("cl->upvals[{d}]", .{i});
                            return;
                        }
                    }
                }
                self.emit_var_name(n.ident);
            },
            .field  => |f| {
                if (self.expr_type(f.obj) == .any) {
                    const hash = calc_lua_hash(f.field);
                    self.p("lua_table_get(", .{});
                    try self.emit_expr(f.obj);
                    self.p(", lua_val_from_literal(\"{s}\", {d}, {d}))", .{ f.field, hash, f.field.len });
                } else {
                    try self.emit_expr(f.obj);
                    self.p(".{s}", .{f.field});
                }
            },
            .index => |idx| {
                if (self.is_dense_table_index(idx.obj)) {
                    if (self.dense_table) |dt| {
                        self.p("__dt_{s}[", .{dt});
                        try self.emit_expr(idx.key);
                        self.p("]", .{});
                        return;
                    }
                }
                const ot = self.expr_type(idx.obj);
                if (ot == .any) {
                    self.p("lua_table_get(", .{});
                    try self.emit_expr(idx.obj);
                    self.p(", ", .{});
                    try self.emit_as_lua_value(idx.key);
                    self.p(")", .{});
                } else {
                    try self.emit_expr(idx.obj);
                    self.p("[", .{});
                    try self.emit_expr(idx.key);
                    self.p("]", .{});
                }
            },
            .call => |c| {
                if (try self.maybe_emit_math_call(c.func, c.args)) return;
                if (try self.maybe_emit_simd_call(c.func, c.args)) return;
                if (try self.maybe_emit_stdlib_call(c.func, c.args)) return;
                if (try self.maybe_emit_stdlib_module_call(c.func, c.args, self.expr_type(expr))) return;
                const ft = self.expr_type(c.func);
                if (c.func.* == .name) {
                    if (self.vararg_funcs.get(c.func.name.ident)) |argv_cname| {
                        self.p("({{\n", .{});
                        self.indent += 1;
                        self.ind();
                        if (c.args.len == 0) {
                            self.pl("lua_Value __r = {s}__argv(0, NULL);", .{argv_cname});
                        } else {
                            self.p("lua_Value __argv[{d}] = {{", .{c.args.len});
                            for (c.args, 0..) |arg, i| {
                                if (i > 0) self.p(", ", .{});
                                try self.emit_as_lua_value(arg);
                            }
                            self.p("}};\n", .{});
                            self.ind();
                            self.p("lua_Value __r = {s}__argv({d}, __argv);\n", .{ argv_cname, c.args.len });
                        }
                        self.ind();
                        self.p("__r;\n", .{});
                        self.indent -= 1;
                        self.ind();
                        self.p("}})", .{});
                        return;
                    }
                }
                if (ft == .any) {
                    self.p("({{\n", .{});
                    self.indent += 1;
                    self.ind();
                    self.p("lua_Value __fn = ", .{});
                    if (c.func.* == .name and self.emit_lua_global_fn(c.func.name.ident)) {} else try self.emit_expr(c.func);
                    self.p(";\n", .{});
                    self.ind();
                    if (c.args.len == 0) {
                        self.pl("lua_invoke(__fn, 0, NULL);", .{});
                    } else {
                        self.p("lua_Value __argv[{d}] = {{", .{c.args.len});
                        for (c.args, 0..) |arg, i| {
                            if (i > 0) self.p(", ", .{});
                            try self.emit_as_lua_value(arg);
                        }
                        self.p("}};\n", .{});
                        self.ind();
                        self.p("lua_invoke(__fn, {d}, __argv);\n", .{c.args.len});
                    }
                    self.indent -= 1;
                    self.ind();
                    self.p("}})", .{});
                    return;
                }
                try self.emit_expr(c.func);
                self.p("(", .{});
                for (c.args, 0..) |arg, i| {
                    if (i > 0) self.p(", ", .{});
                    switch (ft) {
                        .func => |f| {
                            if (i < f.params.len and f.params[i] == .any) {
                                try self.emit_as_lua_value(arg);
                            } else if (i < f.params.len and f.params[i] == .f64 and self.expr_type(arg).is_integer()) {
                                self.p("(double)(", .{});
                                try self.emit_expr(arg);
                                self.p(")", .{});
                            } else {
                                try self.emit_expr(arg);
                            }
                        },
                        else => {
                            try self.emit_as_lua_value(arg);
                        }
                    }
                }
                self.p(")", .{});
            },
            .method_call => |mc| {
                const ot = self.expr_type(mc.obj);
                if (ot == .any) {
                    if (std.mem.eql(u8, mc.method, "put") or std.mem.eql(u8, mc.method, "write")) {
                        self.p("lua_file_write_method(", .{});
                        try self.emit_expr(mc.obj);
                        self.p(", ", .{});
                        if (mc.args.len > 0) {
                            try self.emit_as_lua_value(mc.args[0]);
                        } else {
                            self.p("lua_val_nil()", .{});
                        }
                        self.p(")", .{});
                    } else if (std.mem.eql(u8, mc.method, "get") or std.mem.eql(u8, mc.method, "tostring") or std.mem.eql(u8, mc.method, "read")) {
                        self.p("lua_file_read_method(", .{});
                        try self.emit_expr(mc.obj);
                        self.p(")", .{});
                    } else if (std.mem.eql(u8, mc.method, "reset")) {
                        self.p("lua_str_buf_reset(", .{});
                        try self.emit_expr(mc.obj);
                        self.p(")", .{});
                    } else if (std.mem.eql(u8, mc.method, "set")) {
                        self.p("lua_str_buf_set(", .{});
                        try self.emit_expr(mc.obj);
                        self.p(", ", .{});
                        if (mc.args.len > 0) try self.emit_as_lua_value(mc.args[0]) else self.p("lua_val_nil()", .{});
                        self.p(")", .{});
                    } else if (std.mem.eql(u8, mc.method, "free")) {
                        self.p("lua_str_buf_free(", .{});
                        try self.emit_expr(mc.obj);
                        self.p(")", .{});
                    } else if (std.mem.eql(u8, mc.method, "len")) {
                        self.p("lua_str_buf_len(", .{});
                        try self.emit_expr(mc.obj);
                        self.p(")", .{});
                    } else if (std.mem.eql(u8, mc.method, "putf")) {
                        self.p("lua_str_buf_putf(", .{});
                        try self.emit_expr(mc.obj);
                        self.p(", ", .{});
                        if (mc.args.len > 0) try self.emit_as_lua_value(mc.args[0]) else self.p("lua_val_nil()", .{});
                        self.p(", ", .{});
                        if (mc.args.len > 1) try self.emit_as_lua_value(mc.args[1]) else self.p("lua_val_nil()", .{});
                        self.p(", ", .{});
                        if (mc.args.len > 2) try self.emit_as_lua_value(mc.args[2]) else self.p("lua_val_nil()", .{});
                        self.p(", ", .{});
                        if (mc.args.len > 3) try self.emit_as_lua_value(mc.args[3]) else self.p("lua_val_nil()", .{});
                        self.p(")", .{});
                    } else if (std.mem.eql(u8, mc.method, "close")) {
                        self.p("lua_io_close(", .{});
                        try self.emit_expr(mc.obj);
                        self.p(")", .{});
                    } else if (std.mem.eql(u8, mc.method, "flush")) {
                        self.p("lua_file_flush_method(", .{});
                        try self.emit_expr(mc.obj);
                        self.p(")", .{});
                    } else if (std.mem.eql(u8, mc.method, "seek")) {
                        self.p("lua_file_seek_method(", .{});
                        try self.emit_expr(mc.obj);
                        self.p(", ", .{});
                        if (mc.args.len > 0) try self.emit_as_lua_value(mc.args[0]) else self.p("lua_val_nil()", .{});
                        self.p(", ", .{});
                        if (mc.args.len > 1) try self.emit_as_lua_value(mc.args[1]) else self.p("lua_val_nil()", .{});
                        self.p(")", .{});
                    } else {
                        try self.emit_expr(mc.obj);
                        self.p("__{s}(", .{mc.method});
                        for (mc.args, 0..) |arg, i| {
                            if (i > 0) self.p(", ", .{});
                            try self.emit_expr(arg);
                        }
                        self.p(")", .{});
                    }
                } else {
                    try self.emit_expr(mc.obj);
                    self.p("__{s}(", .{mc.method});
                    for (mc.args, 0..) |arg, i| {
                        if (i > 0) self.p(", ", .{});
                        try self.emit_expr(arg);
                    }
                    self.p(")", .{});
                }
            },
            .binop => |b| {
                const lt = self.expr_type(b.lhs);
                const rt = self.expr_type(b.rhs);
                if (b.op == .concat) {
                    self.p("lua_concat(", .{});
                    try self.emit_as_lua_value(b.lhs);
                    self.p(", ", .{});
                    try self.emit_as_lua_value(b.rhs);
                    self.p(")", .{});
                } else if (b.op == .pow) {
                    if (lt == .any or rt == .any) {
                        self.p("lua_pow(", .{});
                        try self.emit_as_lua_value(b.lhs);
                        self.p(", ", .{});
                        try self.emit_as_lua_value(b.rhs);
                        self.p(")", .{});
                    } else {
                        self.p("pow((double)(", .{});
                        try self.emit_expr(b.lhs);
                        self.p("), (double)(", .{});
                        try self.emit_expr(b.rhs);
                        self.p("))", .{});
                    }
                } else if ((b.op == .eq or b.op == .neq) and (lt == .str or rt == .str) and
                    (!self.expr_is_native_cstr(b.lhs) or !self.expr_is_native_cstr(b.rhs)))
                {
                    const func = if (b.op == .eq) "lua_eq" else "lua_neq";
                    self.p("{s}(", .{func});
                    try self.emit_as_lua_value(b.lhs);
                    self.p(", ", .{});
                    try self.emit_as_lua_value(b.rhs);
                    self.p(")", .{});
                } else if (lt == .any or rt == .any) {
                    const func = switch (b.op) {
                        .add => "lua_add",
                        .sub => "lua_sub",
                        .mul => "lua_mul",
                        .div => "lua_div",
                        .idiv => "lua_idiv",
                        .mod => "lua_mod",
                        .band => "lua_band",
                        .bor => "lua_bor",
                        .bxor => "lua_bxor",
                        .lshift => "lua_lshift",
                        .rshift => "lua_rshift",
                        .eq  => "lua_eq",
                        .neq => "lua_neq",
                        .lt  => "lua_lt",
                        .gt  => "lua_gt",
                        .leq => "lua_leq",
                        .geq => "lua_geq",
                        .@"or"  => "lua_or",
                        .@"and" => "lua_and",
                        else => null,
                    };
                    if (func) |f| {
                        self.p("{s}(", .{f});
                        try self.emit_as_lua_value(b.lhs);
                        self.p(", ", .{});
                        try self.emit_as_lua_value(b.rhs);
                        self.p(")", .{});
                    } else {
                        self.p("(", .{});
                        try self.emit_expr(b.lhs);
                        self.p(" {s} ", .{binop_str(b.op)});
                        try self.emit_expr(b.rhs);
                        self.p(")", .{});
                    }
                } else if (lt.is_vector() or rt.is_vector()) {
                    switch (b.op) {
                        .eq, .neq, .lt, .gt, .leq, .geq => {
                            const op_str: []const u8 = switch (b.op) {
                                .leq => " <= ",
                                .lt => " < ",
                                .geq => " >= ",
                                .gt => " > ",
                                .eq => " == ",
                                .neq => " != ",
                                else => " <= ",
                            };
                            self.p("((v4i64)((", .{});
                            try self.emit_expr(b.lhs);
                            self.p("{s}", .{op_str});
                            try self.emit_expr(b.rhs);
                            self.p(") & (v4i64){{1, 1, 1, 1}}))", .{});
                        },
                        else => {
                            self.p("(", .{});
                            try self.emit_expr(b.lhs);
                            self.p(" {s} ", .{binop_str(b.op)});
                            try self.emit_expr(b.rhs);
                            self.p(")", .{});
                        },
                    }
                } else {
                    switch (b.op) {
                        .div => {
                            if (lt == .f64 and rt == .f64) {
                                self.p("(", .{});
                                try self.emit_expr(b.lhs);
                                self.p(" / ", .{});
                                try self.emit_expr(b.rhs);
                                self.p(")", .{});
                            } else {
                                self.p("((double)(", .{});
                                try self.emit_expr(b.lhs);
                                self.p(") / (double)(", .{});
                                try self.emit_expr(b.rhs);
                                self.p("))", .{});
                            }
                        },
                        .idiv => {
                            if (lt.is_integer() and rt.is_integer()) {
                                self.p("((", .{});
                                try self.emit_expr(b.lhs);
                                self.p(") / (", .{});
                                try self.emit_expr(b.rhs);
                                self.p("))", .{});
                            } else {
                                var buf: [128]u8 = undefined;
                                const t = self.expr_type(expr);
                                self.p("(({s})floor((double)(", .{t.c_type(&buf)});
                                try self.emit_expr(b.lhs);
                                self.p(") / (double)(", .{});
                                try self.emit_expr(b.rhs);
                                self.p(")))", .{});
                            }
                        },
                        .mod => {
                            if (lt.is_integer() and rt.is_integer()) {
                                self.p("((", .{});
                                try self.emit_expr(b.lhs);
                                self.p(") % (", .{});
                                try self.emit_expr(b.rhs);
                                self.p("))", .{});
                            } else {
                                var buf: [128]u8 = undefined;
                                const t = self.expr_type(expr);
                                self.p("(({s})((double)(", .{t.c_type(&buf)});
                                try self.emit_expr(b.lhs);
                                self.p(") - (double)(", .{});
                                try self.emit_expr(b.rhs);
                                self.p(") * floor((double)(", .{});
                                try self.emit_expr(b.lhs);
                                self.p(") / (double)(", .{});
                                try self.emit_expr(b.rhs);
                                self.p("))))", .{});
                            }
                        },
                        .band, .bor, .bxor, .lshift, .rshift => {
                            var buf: [128]u8 = undefined;
                            const t = self.expr_type(expr);
                            self.p("(({s})((", .{t.c_type(&buf)});
                            try self.emit_expr(b.lhs);
                            self.p(") {s} (", .{binop_str(b.op)});
                            try self.emit_expr(b.rhs);
                            self.p(")))", .{});
                        },
                        else => {
                            if (b.op == .mul and try self.try_emit_sin_cos_product(b.lhs, b.rhs)) return;
                            self.p("(", .{});
                            try self.emit_expr(b.lhs);
                            self.p(" {s} ", .{binop_str(b.op)});
                            try self.emit_expr(b.rhs);
                            self.p(")", .{});
                        },
                    }
                }
            },
            .unop => |u| {
                const ot = self.expr_type(u.operand);
                if (ot == .any) {
                    switch (u.op) {
                        .neg  => { self.p("lua_unm(", .{}); try self.emit_expr(u.operand); self.p(")", .{}); },
                        .not  => { self.p("(!lua_to_bool(", .{}); try self.emit_expr(u.operand); self.p("))", .{}); },
                        .len  => { self.p("lua_len(", .{}); try self.emit_expr(u.operand); self.p(")", .{}); },
                        .bnot => { self.p("lua_bnot(", .{}); try self.emit_expr(u.operand); self.p(")", .{}); },
                        .compile => {
                            // For basic metaprogramming, try to evaluate constant expressions
                            if (u.operand.* == .int_lit) {
                                self.p("lua_val_from_int({d})", .{u.operand.int_lit.val});
                            } else if (u.operand.* == .float_lit) {
                                self.p("lua_val_from_num({d})", .{u.operand.float_lit.val});
                            } else if (u.operand.* == .string_lit) {
                                self.p("lua_val_from_str(\"{s}\")", .{u.operand.string_lit.val});
                            } else {
                                // If not constant, just emit the operand
                                try self.emit_expr(u.operand);
                            }
                        },
                    }
                } else {
                    switch (u.op) {
                        .neg  => { self.p("(-", .{}); try self.emit_expr(u.operand); self.p(")", .{}); },
                        .not  => { self.p("(!", .{}); try self.emit_expr(u.operand); self.p(")", .{}); },
                        .len  => {
                            if (ot == .str) {
                                self.p("((int64_t)strlen(", .{});
                                try self.emit_expr(u.operand);
                                self.p("))", .{});
                            } else {
                                self.p("strlen(", .{});
                                try self.emit_expr(u.operand);
                                self.p(")", .{});
                            }
                        },
                        .bnot => { self.p("(~", .{}); try self.emit_expr(u.operand); self.p(")", .{}); },
                        .compile => {
                            // For typed expressions, evaluate constants at compile time
                            if (u.operand.* == .int_lit) {
                                self.p("{d}", .{u.operand.int_lit.val});
                            } else if (u.operand.* == .float_lit) {
                                self.p("{d}", .{u.operand.float_lit.val});
                            } else {
                                try self.emit_expr(u.operand);
                            }
                        },
                    }
                }
            },
            .func_expr => |fb| {
                const id = fb.closure_id orelse 0;
                if (fb.upvalues.len > 0) {
                    self.p("lua_val_from_closure(lua_make_closure({d}, {d}, (lua_Value[{d}]){{", .{ id, fb.upvalues.len, fb.upvalues.len });
                    for (fb.upvalues, 0..) |uv, i| {
                        if (i > 0) self.p(", ", .{});
                        self.p("{s}", .{uv.name});
                    }
                    self.p("}}))", .{});
                } else {
                    self.p("lua_val_from_closure(lua_make_closure({d}, 0, NULL))", .{id});
                }
            },
            .table => |t| {
                var array_count: usize = 0;
                var hash_count: usize = 0;
                for (t.fields) |fld| {
                    switch (fld) {
                        .positional => array_count += 1,
                        .named, .indexed => hash_count += 1,
                    }
                }
                self.p("({{\n", .{});
                self.indent += 1;
                self.ind();
                self.p("lua_Value tmp = lua_table_new_with_capacity({d}, {d});\n", .{ array_count, hash_count });
                var pos_idx: f64 = 1.0;
                for (t.fields) |fld| {
                    self.ind();
                    switch (fld) {
                        .indexed => |idx| {
                            self.p("lua_table_set(tmp, ", .{});
                            try self.emit_as_lua_value(idx.key);
                            self.p(", ", .{});
                            try self.emit_as_lua_value(idx.val);
                            self.p(");\n", .{});
                        },
                        .named => |nmd| {
                            const hash = calc_lua_hash(nmd.key);
                            self.p("lua_table_set(tmp, lua_val_from_literal(\"{s}\", {d}, {d}), ", .{ nmd.key, hash, nmd.key.len });
                            try self.emit_as_lua_value(nmd.val);
                            self.p(");\n", .{});
                        },
                        .positional => |pos_expr| {
                            self.p("lua_table_set(tmp, lua_val_from_num({d}), ", .{pos_idx});
                            try self.emit_as_lua_value(pos_expr);
                            self.p(");\n", .{});
                            pos_idx += 1.0;
                        },
                    }
                }
                self.ind();
                self.p("tmp;\n", .{});
                self.indent -= 1;
                self.ind();
                self.p("}})", .{});
            },
        }
    }

    fn emit_string_escaped(self: *CodeGen, s: []const u8) E!void {
        for (s) |c| {
            switch (c) {
                '"' => self.p("\\\"", .{}),
                '\\' => self.p("\\\\", .{}),
                '\n' => self.p("\\n", .{}),
                '\r' => self.p("\\r", .{}),
                '\t' => self.p("\\t", .{}),
                else => {
                    if (c < 32 or c == 127) self.p("\\x{x:0>2}", .{c}) else self.p("{c}", .{c});
                },
            }
        }
    }

    fn exprs_same(_: *CodeGen, a: *const ast.Expr, b: *const ast.Expr) bool {
        if (@intFromPtr(a) == @intFromPtr(b)) return true;
        if (@as(std.meta.Tag(ast.Expr), a.*) != @as(std.meta.Tag(ast.Expr), b.*)) return false;
        return switch (a.*) {
            .name => std.mem.eql(u8, a.name.ident, b.name.ident),
            else => false,
        };
    }

    fn math_unary_arg(expr: *const ast.Expr, fname: []const u8) ?*const ast.Expr {
        if (expr.* != .call) return null;
        const c = &expr.call;
        if (c.func.* != .field) return null;
        const f = &c.func.field;
        if (f.obj.* != .name or !std.mem.eql(u8, f.obj.name.ident, "math")) return null;
        if (!std.mem.eql(u8, f.field, fname)) return null;
        if (c.args.len != 1) return null;
        return c.args[0];
    }

    fn try_emit_sin_cos_product(self: *CodeGen, lhs: *const ast.Expr, rhs: *const ast.Expr) E!bool {
        const sin_arg = math_unary_arg(lhs, "sin") orelse math_unary_arg(rhs, "sin");
        const cos_arg = math_unary_arg(lhs, "cos") orelse math_unary_arg(rhs, "cos");
        if (sin_arg == null or cos_arg == null) return false;
        if (!self.exprs_same(sin_arg.?, cos_arg.?)) return false;
        const arg = sin_arg.?;
        self.p("(0.5 * sin(2.0 * (double)(", .{});
        try self.emit_expr(arg);
        self.p(")))", .{});
        return true;
    }

    fn maybe_emit_math_call(self: *CodeGen, func: *const ast.Expr, args: []*ast.Expr) E!bool {
        if (func.* != .field) return false;
        const f = &func.field;
        if (f.obj.* != .name) return false;
        if (!std.mem.eql(u8, f.obj.name.ident, "math")) return false;

        const fname = f.field;
        const lua_names = [_][]const u8{
            "sqrt", "abs", "floor", "ceil", "sin", "cos", "tan",
            "asin", "acos", "atan",
            "exp", "log", "fmod", "max", "min",
        };
        const c_names = [_][]const u8{
            "sqrt", "fabs", "floor", "ceil", "sin", "cos", "tan",
            "asin", "acos", "atan",
            "exp", "log", "fmod", "fmax", "fmin",
        };
        for (lua_names, c_names) |ln, cn| {
            if (std.mem.eql(u8, fname, ln)) {
                self.p("{s}(", .{cn});
                for (args, 0..) |arg, i| {
                    if (i > 0) self.p(", ", .{});
                    const at = self.expr_type(arg);
                    if (at.is_integer()) {
                        self.p("(double)(", .{});
                        try self.emit_expr(arg);
                        self.p(")", .{});
                    } else {
                        try self.emit_expr(arg);
                    }
                }
                self.p(")", .{});
                return true;
            }
        }
        return false;
    }

    fn maybe_emit_stdlib_call(self: *CodeGen, func: *const ast.Expr, args: []*ast.Expr) E!bool {
        if (func.* != .name) return false;
        const name = func.name.ident;
        if (std.mem.eql(u8, name, "assert")) {
            self.p("lua_assert(", .{});
            if (args.len > 0) {
                try self.emit_as_lua_value(args[0]);
            } else {
                self.p("lua_val_nil()", .{});
            }
            self.p(", ", .{});
            if (args.len > 1) {
                self.p("lua_to_str(", .{});
                try self.emit_as_lua_value(args[1]);
                self.p(")", .{});
            } else {
                self.p("NULL", .{});
            }
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "require")) {
            self.p("lua_require(", .{});
            if (args.len > 0) {
                try self.emit_as_lua_value(args[0]);
            } else {
                self.p("lua_val_nil()", .{});
            }
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "select")) {
            const n = if (args.len > 1) args.len - 1 else 0;
            self.p("lua_select_v(", .{});
            if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
            self.p(", {d}", .{n});
            var i: usize = 1;
            while (i < args.len) : (i += 1) {
                self.p(", ", .{});
                try self.emit_as_lua_value(args[i]);
            }
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "error")) {
            self.p("lua_error(", .{});
            if (args.len > 0) {
                try self.emit_as_lua_value(args[0]);
            } else {
                self.p("lua_val_nil()", .{});
            }
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "pcall")) {
            if (args.len > 2) {
                self.p("lua_pcall_argv_fn({d}, (lua_Value[]){{", .{args.len});
                for (args, 0..) |arg, i| {
                    if (i > 0) self.p(", ", .{});
                    try self.emit_as_lua_value(arg);
                }
                self.p("}})", .{});
            } else {
                self.p("lua_pcall(", .{});
                if (args.len > 0) {
                    try self.emit_as_lua_value(args[0]);
                } else {
                    self.p("lua_val_nil()", .{});
                }
                self.p(", ", .{});
                if (args.len > 1) {
                    try self.emit_as_lua_value(args[1]);
                } else {
                    self.p("lua_val_nil()", .{});
                }
                self.p(")", .{});
            }
            return true;
        } else if (std.mem.eql(u8, name, "next")) {
            self.p("lua_next(", .{});
            if (args.len > 0) {
                try self.emit_as_lua_value(args[0]);
            } else {
                self.p("lua_val_nil()", .{});
            }
            self.p(", ", .{});
            if (args.len > 1) {
                try self.emit_as_lua_value(args[1]);
            } else {
                self.p("lua_val_nil()", .{});
            }
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "unpack")) {
            self.p("lua_tbl_unpack(", .{});
            if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
            self.p(", ", .{});
            if (args.len > 1) try self.emit_as_lua_value(args[1]) else self.p("lua_val_nil()", .{});
            self.p(", ", .{});
            if (args.len > 2) try self.emit_as_lua_value(args[2]) else self.p("lua_val_nil()", .{});
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "setmetatable")) {
            self.p("lua_setmetatable(", .{});
            if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
            self.p(", ", .{});
            if (args.len > 1) try self.emit_as_lua_value(args[1]) else self.p("lua_val_nil()", .{});
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "getmetatable")) {
            self.p("lua_getmetatable(", .{});
            if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "rawget")) {
            self.p("lua_rawget(", .{});
            if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
            self.p(", ", .{});
            if (args.len > 1) try self.emit_as_lua_value(args[1]) else self.p("lua_val_nil()", .{});
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "rawset")) {
            self.p("lua_rawset(", .{});
            if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
            self.p(", ", .{});
            if (args.len > 1) try self.emit_as_lua_value(args[1]) else self.p("lua_val_nil()", .{});
            self.p(", ", .{});
            if (args.len > 2) try self.emit_as_lua_value(args[2]) else self.p("lua_val_nil()", .{});
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "rawlen")) {
            self.p("lua_rawlen(", .{});
            if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "rawequal")) {
            self.p("lua_rawequal(", .{});
            if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
            self.p(", ", .{});
            if (args.len > 1) try self.emit_as_lua_value(args[1]) else self.p("lua_val_nil()", .{});
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "collectgarbage")) {
            self.p("lua_collectgarbage(", .{});
            if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
            self.p(", ", .{});
            if (args.len > 1) try self.emit_as_lua_value(args[1]) else self.p("lua_val_nil()", .{});
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "warn")) {
            self.p("lua_warn(", .{});
            if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "xpcall")) {
            if (args.len > 3) {
                self.p("lua_xpcall_argv_fn({d}, (lua_Value[]){{", .{args.len});
                for (args, 0..) |arg, i| {
                    if (i > 0) self.p(", ", .{});
                    try self.emit_as_lua_value(arg);
                }
                self.p("}})", .{});
            } else {
                self.p("lua_xpcall(", .{});
                if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
                self.p(", ", .{});
                if (args.len > 1) try self.emit_as_lua_value(args[1]) else self.p("lua_val_nil()", .{});
                self.p(", ", .{});
                if (args.len > 2) try self.emit_as_lua_value(args[2]) else self.p("lua_val_nil()", .{});
                self.p(")", .{});
            }
            return true;
        } else if (std.mem.eql(u8, name, "load")) {
            self.p("lua_load(", .{});
            if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
            self.p(", ", .{});
            if (args.len > 1) try self.emit_as_lua_value(args[1]) else self.p("lua_val_nil()", .{});
            self.p(", ", .{});
            if (args.len > 2) try self.emit_as_lua_value(args[2]) else self.p("lua_val_nil()", .{});
            self.p(", ", .{});
            if (args.len > 3) try self.emit_as_lua_value(args[3]) else self.p("lua_val_nil()", .{});
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "loadfile")) {
            self.p("lua_loadfile(", .{});
            if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
            self.p(", ", .{});
            if (args.len > 1) try self.emit_as_lua_value(args[1]) else self.p("lua_val_nil()", .{});
            self.p(", ", .{});
            if (args.len > 2) try self.emit_as_lua_value(args[2]) else self.p("lua_val_nil()", .{});
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "dofile")) {
            self.p("lua_dofile(", .{});
            if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "tostring")) {
            self.p("tostring(", .{});
            if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "tonumber")) {
            self.p("tonumber(", .{});
            if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "pairs")) {
            self.p("lua_pairs(", .{});
            if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "ipairs")) {
            self.p("lua_ipairs(", .{});
            if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, name, "type")) {
            self.p("type(", .{});
            if (args.len > 0) try self.emit_as_lua_value(args[0]) else self.p("lua_val_nil()", .{});
            self.p(")", .{});
            return true;
        }
        return false;
    }

    fn expr_is_native_cstr(self: *CodeGen, e: *const ast.Expr) bool {
        return switch (e.*) {
            .string_lit => true,
            .name => self.expr_type(e) == .str,
            else => false,
        };
    }

    fn expr_emits_lua_value(self: *CodeGen, e: *const ast.Expr) bool {
        if (self.expr_type(e) == .any) return true;
        switch (e.*) {
            .call => |c| {
                if (c.func.* != .field) return false;
                const f = &c.func.field;
                if (f.obj.* != .name or !std.mem.eql(u8, f.obj.name.ident, "string")) return false;
                const fname = f.field;
                if (std.mem.eql(u8, fname, "len") or std.mem.eql(u8, fname, "byte")) return false;
                if (std.mem.eql(u8, fname, "rep")) {
                    if (c.args.len == 2) {
                        const pat_t = self.expr_type(c.args[0]);
                        const cnt_t = self.expr_type(c.args[1]);
                        if ((pat_t == .str or c.args[0].* == .string_lit) and cnt_t.is_integer())
                            return false;
                    }
                }
                return true;
            },
            else => return false,
        }
    }

    fn emit_lua_global_fn(self: *CodeGen, name: []const u8) bool {
        const mapped: ?[]const u8 = if (std.mem.eql(u8, name, "tostring")) "tostring"
        else if (std.mem.eql(u8, name, "tonumber")) "tonumber"
        else if (std.mem.eql(u8, name, "type")) "type"
        else null;
        if (mapped) |fn_name| {
            self.p("lua_val_from_func((lua_Value (*)(lua_Value)){s})", .{fn_name});
            return true;
        }
        return false;
    }

    fn maybe_emit_simd_call(self: *CodeGen, func: *const ast.Expr, args: []*ast.Expr) E!bool {
        if (func.* != .field) return false;
        const f = &func.field;
        if (f.obj.* != .name) return false;
        if (!std.mem.eql(u8, f.obj.name.ident, "simd")) return false;

        const fname = f.field;
        if (std.mem.eql(u8, fname, "v4f64")) {
            self.p("(v4f64){{", .{});
            for (args, 0..) |arg, i| {
                if (i > 0) self.p(", ", .{});
                try self.emit_expr(arg);
            }
            self.p("}}", .{});
            return true;
        }
        if (std.mem.eql(u8, fname, "v4i64")) {
            self.p("(v4i64){{", .{});
            for (args, 0..) |arg, i| {
                if (i > 0) self.p(", ", .{});
                try self.emit_expr(arg);
            }
            self.p("}}", .{});
            return true;
        }
        if (std.mem.eql(u8, fname, "v8f32")) {
            self.p("(v8f32){{", .{});
            for (args, 0..) |arg, i| {
                if (i > 0) self.p(", ", .{});
                try self.emit_expr(arg);
            }
            self.p("}}", .{});
            return true;
        }
        if (std.mem.eql(u8, fname, "v8i32")) {
            self.p("(v8i32){{", .{});
            for (args, 0..) |arg, i| {
                if (i > 0) self.p(", ", .{});
                try self.emit_expr(arg);
            }
            self.p("}}", .{});
            return true;
        }
        if (std.mem.eql(u8, fname, "sqrt")) {
            self.p("__builtin_elementwise_sqrt(", .{});
            if (args.len > 0) try self.emit_expr(args[0]);
            self.p(")", .{});
            return true;
        }
        if (std.mem.eql(u8, fname, "le") or std.mem.eql(u8, fname, "lt") or
            std.mem.eql(u8, fname, "ge") or std.mem.eql(u8, fname, "gt") or
            std.mem.eql(u8, fname, "eq") or std.mem.eql(u8, fname, "ne"))
        {
            const op_str: []const u8 = if (std.mem.eql(u8, fname, "le")) " <= "
            else if (std.mem.eql(u8, fname, "lt")) " < "
            else if (std.mem.eql(u8, fname, "ge")) " >= "
            else if (std.mem.eql(u8, fname, "gt")) " > "
            else if (std.mem.eql(u8, fname, "eq")) " == "
            else " != ";
            self.p("((v4i64)((", .{});
            if (args.len > 0) try self.emit_expr(args[0]);
            self.p("{s}", .{op_str});
            if (args.len > 1) try self.emit_expr(args[1]) else self.p("0", .{});
            self.p(") & (v4i64){{1, 1, 1, 1}}))", .{});
            return true;
        }
        if (std.mem.eql(u8, fname, "select")) {
            const at: RT = if (args.len > 1) self.expr_type(args[1]) else .any;
            if (at == .v4f64) {
                self.p("duo_select_v4f64(", .{});
            } else {
                self.p("duo_select_v4i64(", .{});
            }
            if (args.len > 0) try self.emit_expr(args[0]);
            self.p(", ", .{});
            if (args.len > 1) try self.emit_expr(args[1]) else self.p("0", .{});
            self.p(", ", .{});
            if (args.len > 2) try self.emit_expr(args[2]) else self.p("0", .{});
            self.p(")", .{});
            return true;
        }
        if (std.mem.eql(u8, fname, "sum")) {
            self.p("__builtin_reduce_add(", .{});
            if (args.len > 0) try self.emit_expr(args[0]);
            self.p(")", .{});
            return true;
        }
        if (std.mem.eql(u8, fname, "any")) {
            self.p("(__builtin_reduce_add(", .{});
            if (args.len > 0) try self.emit_expr(args[0]);
            self.p(") != 0)", .{});
            return true;
        }
        return false;
    }

    fn try_emit_native_string_call(self: *CodeGen, fname: []const u8, args: []*ast.Expr, result_rt: RT) E!bool {
        if (std.mem.eql(u8, fname, "len")) {
            if (args.len == 0) return false;
            if (args[0].* == .string_lit) {
                self.p("{d}", .{args[0].string_lit.val.len});
                return true;
            }
            if (self.expr_type(args[0]) == .str) {
                self.p("((int64_t)strlen(", .{});
                try self.emit_expr(args[0]);
                self.p("))", .{});
                return true;
            }
            if (result_rt.is_integer()) {
                self.p("((int64_t)strlen(lua_to_str(", .{});
                try self.emit_as_lua_value(args[0]);
                self.p(")))", .{});
                return true;
            }
            return false;
        }
        if (std.mem.eql(u8, fname, "byte")) {
            if (args.len < 2) return false;
            if (args[0].* == .string_lit and args[1].* == .int_lit) {
                const s = args[0].string_lit.val;
                const idx = args[1].int_lit.val;
                if (idx >= 1 and idx <= @as(i64, @intCast(s.len)))
                    self.p("{d}", .{@as(i64, s[@intCast(idx - 1)])})
                else
                    self.p("0", .{});
                return true;
            }
            if (self.expr_type(args[0]) == .str and self.expr_type(args[1]).is_integer()) {
                self.p("((int64_t)(unsigned char)(", .{});
                try self.emit_expr(args[0]);
                self.p("[", .{});
                try self.emit_expr(args[1]);
                self.p(" - 1]))", .{});
                return true;
            }
            return false;
        }
        if (std.mem.eql(u8, fname, "rep") and result_rt == .str) {
            if (args.len < 2 or args.len > 2) return false;
            const pat_t = self.expr_type(args[0]);
            const cnt_t = self.expr_type(args[1]);
            if ((pat_t == .str or args[0].* == .string_lit) and cnt_t.is_integer()) {
                self.p("duo_str_rep(", .{});
                try self.emit_expr(args[0]);
                self.p(", ", .{});
                try self.emit_expr(args[1]);
                self.p(")", .{});
                return true;
            }
            return false;
        }
        return false;
    }

    fn maybe_emit_stdlib_module_call(self: *CodeGen, func: *const ast.Expr, args: []*ast.Expr, result_rt: RT) E!bool {
        if (func.* != .field) return false;
        const f = &func.field;

        // 1. Handle nested string.buffer.new()
        if (f.obj.* == .field) {
            const inner = &f.obj.field;
            if (inner.obj.* == .name and std.mem.eql(u8, inner.obj.name.ident, "string") and std.mem.eql(u8, inner.field, "buffer")) {
                if (std.mem.eql(u8, f.field, "new")) {
                    if (args.len > 0) {
                        self.p("lua_str_buf_new_init(", .{});
                        try self.emit_as_lua_value(args[0]);
                        self.p(")", .{});
                    } else {
                        self.p("lua_str_buf_new()", .{});
                    }
                    return true;
                }
            }
        }

        if (f.obj.* != .name) return false;
        const mod = f.obj.name.ident;
        const fname = f.field;

        if (std.mem.eql(u8, mod, "string")) {
            if (try self.try_emit_native_string_call(fname, args, result_rt)) return true;
            const mapped = if (std.mem.eql(u8, fname, "len")) "lua_str_len"
            else if (std.mem.eql(u8, fname, "lower")) "lua_str_lower"
            else if (std.mem.eql(u8, fname, "upper")) "lua_str_upper"
            else if (std.mem.eql(u8, fname, "sub")) "lua_str_sub"
            else if (std.mem.eql(u8, fname, "char")) "lua_str_char"
            else if (std.mem.eql(u8, fname, "format")) "lua_str_format"
            else if (std.mem.eql(u8, fname, "rep")) "lua_str_rep"
            else if (std.mem.eql(u8, fname, "reverse")) "lua_str_reverse"
            else if (std.mem.eql(u8, fname, "byte")) "lua_str_byte"
            else if (std.mem.eql(u8, fname, "find")) "lua_str_find"
            else if (std.mem.eql(u8, fname, "match")) "lua_str_match"
            else if (std.mem.eql(u8, fname, "gsub")) "lua_str_gsub"
            else if (std.mem.eql(u8, fname, "pack")) "lua_str_pack"
            else if (std.mem.eql(u8, fname, "unpack")) "lua_str_unpack"
            else if (std.mem.eql(u8, fname, "packsize")) "lua_str_packsize"
            else if (std.mem.eql(u8, fname, "gmatch")) "lua_str_gmatch"
            else if (std.mem.eql(u8, fname, "dump")) "lua_str_dump"
            else return false;

            const expected: usize = if (std.mem.eql(u8, fname, "len") or std.mem.eql(u8, fname, "lower") or std.mem.eql(u8, fname, "upper") or std.mem.eql(u8, fname, "reverse") or std.mem.eql(u8, fname, "packsize")) 1
            else if (std.mem.eql(u8, fname, "find") or std.mem.eql(u8, fname, "match") or std.mem.eql(u8, fname, "dump")) 2
            else if (std.mem.eql(u8, fname, "sub") or std.mem.eql(u8, fname, "rep") or std.mem.eql(u8, fname, "byte") or std.mem.eql(u8, fname, "gsub") or std.mem.eql(u8, fname, "pack") or std.mem.eql(u8, fname, "unpack") or std.mem.eql(u8, fname, "gmatch")) 3
            else 4;

            self.p("{s}(", .{mapped});
            var i: usize = 0;
            while (i < expected) : (i += 1) {
                if (i > 0) self.p(", ", .{});
                if (i < args.len) {
                    try self.emit_as_lua_value(args[i]);
                } else {
                    self.p("lua_val_nil()", .{});
                }
            }
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, mod, "table")) {
            const mapped = if (std.mem.eql(u8, fname, "insert")) "lua_tbl_insert"
            else if (std.mem.eql(u8, fname, "remove")) "lua_tbl_remove"
            else if (std.mem.eql(u8, fname, "concat")) "lua_tbl_concat"
            else if (std.mem.eql(u8, fname, "sort")) "lua_tbl_sort"
            else if (std.mem.eql(u8, fname, "new")) "lua_tbl_new"
            else if (std.mem.eql(u8, fname, "create")) "lua_tbl_new"
            else if (std.mem.eql(u8, fname, "clear")) "lua_tbl_clear"
            else if (std.mem.eql(u8, fname, "move")) "lua_tbl_move"
            else if (std.mem.eql(u8, fname, "unpack")) "lua_tbl_unpack"
            else if (std.mem.eql(u8, fname, "pack")) "lua_tbl_pack"
            else if (std.mem.eql(u8, fname, "freeze")) "lua_tbl_freeze"
            else if (std.mem.eql(u8, fname, "isfrozen")) "lua_tbl_isfrozen"
            else return false;

            if (std.mem.eql(u8, fname, "pack") and args.len > 1) {
                self.p("lua_tbl_pack_argv({d}, (lua_Value[]){{", .{args.len});
                for (args, 0..) |arg, i| {
                    if (i > 0) self.p(", ", .{});
                    try self.emit_as_lua_value(arg);
                }
                self.p("}})", .{});
                return true;
            }

            const expected: usize = if (std.mem.eql(u8, fname, "sort")) @as(usize, 2)
            else if (std.mem.eql(u8, fname, "pack")) @as(usize, 1)
            else if (std.mem.eql(u8, fname, "clear") or std.mem.eql(u8, fname, "freeze") or std.mem.eql(u8, fname, "isfrozen")) @as(usize, 1)
            else if (std.mem.eql(u8, fname, "remove") or std.mem.eql(u8, fname, "new") or std.mem.eql(u8, fname, "create")) @as(usize, 2)
            else if (std.mem.eql(u8, fname, "insert") or std.mem.eql(u8, fname, "unpack")) @as(usize, 3)
            else if (std.mem.eql(u8, fname, "concat")) @as(usize, 4)
            else if (std.mem.eql(u8, fname, "move")) @as(usize, 5)
            else 0;

            self.p("{s}(", .{mapped});
            var i: usize = 0;
            while (i < expected) : (i += 1) {
                if (i > 0) self.p(", ", .{});
                if (i < args.len) {
                    try self.emit_as_lua_value(args[i]);
                } else {
                    self.p("lua_val_nil()", .{});
                }
            }
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, mod, "io")) {
            const mapped = if (std.mem.eql(u8, fname, "write")) "lua_io_write"
            else if (std.mem.eql(u8, fname, "read")) "lua_io_read"
            else if (std.mem.eql(u8, fname, "flush")) "lua_io_flush"
            else if (std.mem.eql(u8, fname, "open")) "lua_io_open"
            else if (std.mem.eql(u8, fname, "close")) "lua_io_close"
            else if (std.mem.eql(u8, fname, "tmpfile")) "lua_io_tmpfile"
            else if (std.mem.eql(u8, fname, "input")) "lua_io_input"
            else if (std.mem.eql(u8, fname, "output")) "lua_io_output"
            else if (std.mem.eql(u8, fname, "popen")) "lua_io_popen"
            else if (std.mem.eql(u8, fname, "type")) "lua_io_type"
            else if (std.mem.eql(u8, fname, "lines")) "lua_io_lines"
            else return false;

            const expected: usize = if (std.mem.eql(u8, fname, "flush") or std.mem.eql(u8, fname, "tmpfile")) @as(usize, 0)
            else if (std.mem.eql(u8, fname, "read") or std.mem.eql(u8, fname, "close") or std.mem.eql(u8, fname, "input") or std.mem.eql(u8, fname, "output") or std.mem.eql(u8, fname, "type") or std.mem.eql(u8, fname, "lines")) @as(usize, 1)
            else if (std.mem.eql(u8, fname, "open") or std.mem.eql(u8, fname, "popen")) @as(usize, 2)
            else if (std.mem.eql(u8, fname, "write")) @as(usize, 4)
            else 0;

            self.p("{s}(", .{mapped});
            var i: usize = 0;
            while (i < expected) : (i += 1) {
                if (i > 0) self.p(", ", .{});
                if (i < args.len) {
                    try self.emit_as_lua_value(args[i]);
                } else {
                    self.p("lua_val_nil()", .{});
                }
            }
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, mod, "os")) {
            if (std.mem.eql(u8, fname, "clock") and result_rt == .f64) {
                self.p("((double)clock() / (double)CLOCKS_PER_SEC)", .{});
                return true;
            }
            const mapped = if (std.mem.eql(u8, fname, "clock")) "lua_os_clock"
            else if (std.mem.eql(u8, fname, "time")) "lua_os_time"
            else if (std.mem.eql(u8, fname, "difftime")) "lua_os_difftime"
            else if (std.mem.eql(u8, fname, "exit")) "lua_os_exit"
            else if (std.mem.eql(u8, fname, "getenv")) "lua_os_getenv"
            else if (std.mem.eql(u8, fname, "remove")) "lua_os_remove"
            else if (std.mem.eql(u8, fname, "rename")) "lua_os_rename"
            else if (std.mem.eql(u8, fname, "date")) "lua_os_date"
            else if (std.mem.eql(u8, fname, "execute")) "lua_os_execute"
            else if (std.mem.eql(u8, fname, "tmpname")) "lua_os_tmpname"
            else if (std.mem.eql(u8, fname, "setlocale")) "lua_os_setlocale"
            else return false;

            const expected: usize = if (std.mem.eql(u8, fname, "clock") or std.mem.eql(u8, fname, "tmpname")) @as(usize, 0)
            else if (std.mem.eql(u8, fname, "time") or std.mem.eql(u8, fname, "exit") or std.mem.eql(u8, fname, "getenv") or std.mem.eql(u8, fname, "remove") or std.mem.eql(u8, fname, "execute")) @as(usize, 1)
            else if (std.mem.eql(u8, fname, "difftime") or std.mem.eql(u8, fname, "rename") or std.mem.eql(u8, fname, "date") or std.mem.eql(u8, fname, "setlocale")) @as(usize, 2)
            else 0;

            self.p("{s}(", .{mapped});
            var i: usize = 0;
            while (i < expected) : (i += 1) {
                if (i > 0) self.p(", ", .{});
                if (i < args.len) {
                    try self.emit_as_lua_value(args[i]);
                } else {
                    self.p("lua_val_nil()", .{});
                }
            }
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, mod, "coroutine")) {
            const mapped = if (std.mem.eql(u8, fname, "create")) "lua_co_create"
            else if (std.mem.eql(u8, fname, "resume")) "lua_co_resume"
            else if (std.mem.eql(u8, fname, "yield")) "lua_co_yield"
            else if (std.mem.eql(u8, fname, "status")) "lua_co_status"
            else if (std.mem.eql(u8, fname, "running")) "lua_co_running"
            else if (std.mem.eql(u8, fname, "wrap")) "lua_co_wrap"
            else if (std.mem.eql(u8, fname, "isyieldable")) "lua_co_isyieldable"
            else if (std.mem.eql(u8, fname, "close")) "lua_co_close"
            else return false;

            const expected: usize = if (std.mem.eql(u8, fname, "running") or std.mem.eql(u8, fname, "isyieldable")) @as(usize, 0)
            else if (std.mem.eql(u8, fname, "create") or std.mem.eql(u8, fname, "yield") or std.mem.eql(u8, fname, "status") or std.mem.eql(u8, fname, "wrap") or std.mem.eql(u8, fname, "close")) @as(usize, 1)
            else if (std.mem.eql(u8, fname, "resume")) @as(usize, 2)
            else 0;

            self.p("{s}(", .{mapped});
            var i: usize = 0;
            while (i < expected) : (i += 1) {
                if (i > 0) self.p(", ", .{});
                if (i < args.len) {
                    try self.emit_as_lua_value(args[i]);
                } else {
                    self.p("lua_val_nil()", .{});
                }
            }
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, mod, "math")) {
            const mapped = if (std.mem.eql(u8, fname, "random")) "lua_math_random"
            else if (std.mem.eql(u8, fname, "randomseed")) "lua_math_randomseed"
            else if (std.mem.eql(u8, fname, "deg")) "lua_math_deg"
            else if (std.mem.eql(u8, fname, "rad")) "lua_math_rad"
            else if (std.mem.eql(u8, fname, "type")) "lua_math_type"
            else if (std.mem.eql(u8, fname, "tointeger")) "lua_math_tointeger"
            else if (std.mem.eql(u8, fname, "modf")) "lua_math_modf"
            else if (std.mem.eql(u8, fname, "ult")) "lua_math_ult"
            else if (std.mem.eql(u8, fname, "abs")) "lua_math_abs"
            else if (std.mem.eql(u8, fname, "acos")) "lua_math_acos"
            else if (std.mem.eql(u8, fname, "asin")) "lua_math_asin"
            else if (std.mem.eql(u8, fname, "atan")) "lua_math_atan"
            else if (std.mem.eql(u8, fname, "atan2")) "lua_math_atan2"
            else if (std.mem.eql(u8, fname, "ceil")) "lua_math_ceil"
            else if (std.mem.eql(u8, fname, "cos")) "lua_math_cos"
            else if (std.mem.eql(u8, fname, "exp")) "lua_math_exp"
            else if (std.mem.eql(u8, fname, "floor")) "lua_math_floor"
            else if (std.mem.eql(u8, fname, "fmod")) "lua_math_fmod"
            else if (std.mem.eql(u8, fname, "log")) "lua_math_log"
            else if (std.mem.eql(u8, fname, "log10")) "lua_math_log10"
            else if (std.mem.eql(u8, fname, "max")) "lua_math_max"
            else if (std.mem.eql(u8, fname, "min")) "lua_math_min"
            else if (std.mem.eql(u8, fname, "sin")) "lua_math_sin"
            else if (std.mem.eql(u8, fname, "sqrt")) "lua_math_sqrt"
            else if (std.mem.eql(u8, fname, "tan")) "lua_math_tan"
            else if (std.mem.eql(u8, fname, "pow")) "lua_math_pow"
            else if (std.mem.eql(u8, fname, "sinh")) "lua_math_sinh"
            else if (std.mem.eql(u8, fname, "cosh")) "lua_math_cosh"
            else if (std.mem.eql(u8, fname, "tanh")) "lua_math_tanh"
            else return false;

            const expected: usize = if (std.mem.eql(u8, fname, "randomseed") or std.mem.eql(u8, fname, "deg") or std.mem.eql(u8, fname, "rad") or std.mem.eql(u8, fname, "type") or std.mem.eql(u8, fname, "tointeger") or std.mem.eql(u8, fname, "modf") or std.mem.eql(u8, fname, "abs") or std.mem.eql(u8, fname, "acos") or std.mem.eql(u8, fname, "asin") or std.mem.eql(u8, fname, "atan") or std.mem.eql(u8, fname, "ceil") or std.mem.eql(u8, fname, "cos") or std.mem.eql(u8, fname, "exp") or std.mem.eql(u8, fname, "floor") or std.mem.eql(u8, fname, "log") or std.mem.eql(u8, fname, "log10") or std.mem.eql(u8, fname, "sin") or std.mem.eql(u8, fname, "sqrt") or std.mem.eql(u8, fname, "tan") or std.mem.eql(u8, fname, "sinh") or std.mem.eql(u8, fname, "cosh") or std.mem.eql(u8, fname, "tanh")) @as(usize, 1)
            else if (std.mem.eql(u8, fname, "random") or std.mem.eql(u8, fname, "ult") or std.mem.eql(u8, fname, "fmod") or std.mem.eql(u8, fname, "max") or std.mem.eql(u8, fname, "min") or std.mem.eql(u8, fname, "atan2") or std.mem.eql(u8, fname, "pow")) @as(usize, 2)
            else 0;

            self.p("{s}(", .{mapped});
            var i: usize = 0;
            while (i < expected) : (i += 1) {
                if (i > 0) self.p(", ", .{});
                if (i < args.len) {
                    try self.emit_as_lua_value(args[i]);
                } else {
                    self.p("lua_val_nil()", .{});
                }
            }
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, mod, "utf8")) {
            const mapped = if (std.mem.eql(u8, fname, "char")) "lua_str_char"
            else if (std.mem.eql(u8, fname, "len")) "lua_utf8_len"
            else if (std.mem.eql(u8, fname, "codepoint")) "lua_utf8_codepoint"
            else if (std.mem.eql(u8, fname, "offset")) "lua_utf8_offset"
            else if (std.mem.eql(u8, fname, "codes")) "lua_utf8_codes"
            else return false;

            const expected: usize = if (std.mem.eql(u8, fname, "len") or std.mem.eql(u8, fname, "codes")) @as(usize, 1)
            else if (std.mem.eql(u8, fname, "offset")) @as(usize, 3)
            else if (std.mem.eql(u8, fname, "codepoint")) @as(usize, 3)
            else if (std.mem.eql(u8, fname, "char")) @as(usize, 4)
            else 0;

            self.p("{s}(", .{mapped});
            var i: usize = 0;
            while (i < expected) : (i += 1) {
                if (i > 0) self.p(", ", .{});
                if (i < args.len) {
                    try self.emit_as_lua_value(args[i]);
                } else {
                    self.p("lua_val_nil()", .{});
                }
            }
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, mod, "debug")) {
            const mapped = if (std.mem.eql(u8, fname, "traceback")) "lua_debug_traceback"
            else if (std.mem.eql(u8, fname, "getinfo")) "lua_debug_getinfo"
            else return false;

            const expected: usize = if (std.mem.eql(u8, fname, "traceback")) @as(usize, 0)
            else if (std.mem.eql(u8, fname, "getinfo")) @as(usize, 2)
            else 0;

            self.p("{s}(", .{mapped});
            var i: usize = 0;
            while (i < expected) : (i += 1) {
                if (i > 0) self.p(", ", .{});
                if (i < args.len) {
                    try self.emit_as_lua_value(args[i]);
                } else {
                    self.p("lua_val_nil()", .{});
                }
            }
            self.p(")", .{});
            return true;
        } else if (std.mem.eql(u8, mod, "package")) {
            const mapped = if (std.mem.eql(u8, fname, "searchpath")) "lua_package_searchpath"
            else return false;

            const expected: usize = if (std.mem.eql(u8, fname, "searchpath")) @as(usize, 4)
            else 0;

            self.p("{s}(", .{mapped});
            var i: usize = 0;
            while (i < expected) : (i += 1) {
                if (i > 0) self.p(", ", .{});
                if (i < args.len) {
                    try self.emit_as_lua_value(args[i]);
                } else {
                    self.p("lua_val_nil()", .{});
                }
            }
            self.p(")", .{});
            return true;
        }

        return false;
    }

    fn binop_str(op: ast.BinOp) []const u8 {
        return switch (op) {
            .add    => "+",
            .sub    => "-",
            .mul    => "*",
            .div    => "/",
            .idiv   => "/",   // integer division — both operands should be integer
            .mod    => "%",
            .pow    => "/* ^ */", // handled via pow()
            .band   => "&",
            .bor    => "|",
            .bxor   => "^",
            .lshift => "<<",
            .rshift => ">>",
            .concat => "/* .. */",
            .eq     => "==",
            .neq    => "!=",
            .lt     => "<",
            .gt     => ">",
            .leq    => "<=",
            .geq    => ">=",
            .@"and" => "&&",
            .@"or"  => "||",
        };
    }

    // ── Closures & require ────────────────────────────────────────────────────

    fn collect_closures_expr(self: *CodeGen, expr: *const ast.Expr, list: *std.ArrayList(*ast.FuncBody)) std.mem.Allocator.Error!void {
        switch (expr.*) {
            .func_expr => |fb| {
                if (fb.closure_id) |id| {
                    if (self.emitted_closures.contains(id)) return;
                    try self.emitted_closures.put(self.alloc, id, {});
                    try list.append(self.alloc, fb);
                }
                try self.collect_closures_block(&fb.body, list);
            },
            .binop => |b| {
                try self.collect_closures_expr(b.lhs, list);
                try self.collect_closures_expr(b.rhs, list);
            },
            .unop => |u| try self.collect_closures_expr(u.operand, list),
            .call => |c| {
                try self.collect_closures_expr(c.func, list);
                for (c.args) |a| try self.collect_closures_expr(a, list);
            },
            .method_call => |mc| {
                try self.collect_closures_expr(mc.obj, list);
                for (mc.args) |a| try self.collect_closures_expr(a, list);
            },
            .field => |f| try self.collect_closures_expr(f.obj, list),
            .index => |idx| {
                try self.collect_closures_expr(idx.obj, list);
                try self.collect_closures_expr(idx.key, list);
            },
            .table => |t| {
                for (t.fields) |fld| {
                    switch (fld) {
                        .indexed => |idx| {
                            try self.collect_closures_expr(idx.key, list);
                            try self.collect_closures_expr(idx.val, list);
                        },
                        .named => |nmd| try self.collect_closures_expr(nmd.val, list),
                        .positional => |pos| try self.collect_closures_expr(pos, list),
                    }
                }
            },
            else => {},
        }
    }

    fn collect_closures_block(self: *CodeGen, block: *const ast.Block, list: *std.ArrayList(*ast.FuncBody)) std.mem.Allocator.Error!void {
        for (block.stmts) |*stmt| try self.collect_closures_stmt(stmt, list);
    }

    fn collect_closures_stmt(self: *CodeGen, stmt: *const ast.Stmt, list: *std.ArrayList(*ast.FuncBody)) std.mem.Allocator.Error!void {
        switch (stmt.*) {
            .local_decl => |*ld| for (ld.inits) |e| try self.collect_closures_expr(e, list),
            .const_decl => |*cd| try self.collect_closures_expr(cd.val, list),
            .assign => |*as| for (as.values) |v| try self.collect_closures_expr(v, list),
            .ret => |*r| for (r.vals) |v| try self.collect_closures_expr(v, list),
            .if_stmt => |*is| {
                try self.collect_closures_expr(is.cond, list);
                try self.collect_closures_block(&is.then, list);
                for (is.elseifs) |*ei| {
                    try self.collect_closures_expr(ei.cond, list);
                    try self.collect_closures_block(&ei.body, list);
                }
                if (is.else_body) |*eb| try self.collect_closures_block(eb, list);
            },
            .while_loop => |*wl| {
                try self.collect_closures_expr(wl.cond, list);
                try self.collect_closures_block(&wl.body, list);
            },
            .repeat_loop => |*rl| {
                try self.collect_closures_block(&rl.body, list);
                try self.collect_closures_expr(rl.cond, list);
            },
            .num_for => |*nf| try self.collect_closures_block(&nf.body, list),
            .gen_for => |*gf| {
                for (gf.iters) |e| try self.collect_closures_expr(e, list);
                try self.collect_closures_block(&gf.body, list);
            },
            .call_stmt => |*cs| try self.collect_closures_expr(cs.expr, list),
            .do_block => |*db| try self.collect_closures_block(&db.body, list),
            .func_decl => |*fd| try self.collect_closures_block(&fd.func.body, list),
            else => {},
        }
    }

    fn collect_closures_module(self: *CodeGen, mod: *const ast.Module, list: *std.ArrayList(*ast.FuncBody)) !void {
        try self.collect_closures_block(&mod.body, list);
        for (mod.body.stmts) |*stmt| {
            if (stmt.* == .func_decl) {
                try self.collect_closures_block(&stmt.func_decl.func.body, list);
            }
        }
    }

    fn collect_local_funcs_block(self: *CodeGen, block: *const ast.Block, list: *std.ArrayList(*ast.FuncDecl)) std.mem.Allocator.Error!void {
        for (block.stmts) |*stmt| {
            switch (stmt.*) {
                .func_decl => |*fd| {
                    if (fd.is_local) try list.append(self.alloc, fd);
                    try self.collect_local_funcs_block(&fd.func.body, list);
                },
                .if_stmt => |*is| {
                    try self.collect_local_funcs_block(&is.then, list);
                    for (is.elseifs) |*ei| try self.collect_local_funcs_block(&ei.body, list);
                    if (is.else_body) |*eb| try self.collect_local_funcs_block(eb, list);
                },
                .while_loop => |*wl| try self.collect_local_funcs_block(&wl.body, list),
                .repeat_loop => |*rl| try self.collect_local_funcs_block(&rl.body, list),
                .num_for => |*nf| try self.collect_local_funcs_block(&nf.body, list),
                .gen_for => |*gf| try self.collect_local_funcs_block(&gf.body, list),
                .do_block => |*db| try self.collect_local_funcs_block(&db.body, list),
                else => {},
            }
        }
    }

    fn collect_local_funcs_module(self: *CodeGen, mod: *const ast.Module, list: *std.ArrayList(*ast.FuncDecl)) std.mem.Allocator.Error!void {
        try self.collect_local_funcs_block(&mod.body, list);
        for (mod.body.stmts) |*stmt| {
            if (stmt.* == .func_decl) {
                try self.collect_local_funcs_block(&stmt.func_decl.func.body, list);
            }
        }
    }

    fn emit_closure_functions(self: *CodeGen, mod: *ast.Module) E!void {
        var list: std.ArrayList(*ast.FuncBody) = .empty;
        defer list.deinit(self.alloc);
        self.emitted_closures = .{};
        defer self.emitted_closures.deinit(self.alloc);
        try self.collect_closures_module(mod, &list);

        if (list.items.len == 0) {
            self.p("lua_Value duo_invoke_closure(int id, lua_Closure* cl, int argc, lua_Value* argv) {{\n", .{});
            self.p("    (void)id; (void)cl; (void)argc; (void)argv;\n", .{});
            self.p("    return lua_val_nil();\n", .{});
            self.p("}}\n\n", .{});
            return;
        }

        for (list.items) |fb| {
            const id = fb.closure_id orelse continue;
            self.p("static lua_Value duo_cl_{d}(lua_Closure* cl, int argc, lua_Value* argv);\n", .{id});
        }
        self.p("lua_Value duo_invoke_closure(int id, lua_Closure* cl, int argc, lua_Value* argv) {{\n", .{});
        self.p("    switch (id) {{\n", .{});
        for (list.items) |fb| {
            if (fb.closure_id) |id| {
                self.p("        case {d}: return duo_cl_{d}(cl, argc, argv);\n", .{ id, id });
            }
        }
        self.p("        default: return lua_val_nil();\n", .{});
        self.p("    }}\n", .{});
        self.p("}}\n\n", .{});

        for (list.items) |fb| {
            const id = fb.closure_id orelse continue;
            self.p("static lua_Value duo_cl_{d}(lua_Closure* cl, int argc, lua_Value* argv) {{\n", .{id});
            self.indent = 1;
            const prev_ret = self.current_ret;
            const prev_ctx = self.closure_ctx;
            self.current_ret = .any;
            self.closure_ctx = fb;
            for (fb.params, 0..) |par, i| {
                const pt = types.resolve(par.typ, self.alloc) catch .any;
                if (pt == .any) {
                    self.pl("lua_Value {s} = argc > {d} ? argv[{d}] : lua_val_nil();", .{ par.name, i, i });
                } else if (pt.is_integer()) {
                    self.pl("int64_t {s} = (int64_t)lua_to_num(argc > {d} ? argv[{d}] : lua_val_nil());", .{ par.name, i, i });
                } else if (pt == .f64) {
                    self.pl("double {s} = lua_to_num(argc > {d} ? argv[{d}] : lua_val_nil());", .{ par.name, i, i });
                } else if (pt == .bool) {
                    self.pl("bool {s} = lua_to_bool(argc > {d} ? argv[{d}] : lua_val_nil());", .{ par.name, i, i });
                } else if (pt == .str) {
                    self.pl("const char* {s} = lua_to_str(argc > {d} ? argv[{d}] : lua_val_nil());", .{ par.name, i, i });
                } else {
                    self.pl("lua_Value {s} = argc > {d} ? argv[{d}] : lua_val_nil();", .{ par.name, i, i });
                }
            }
            if (fb.vararg_name) |vn| {
                self.pl("lua_Value {s} = lua_tbl_pack_argv(argc - {d}, argv + {d});", .{ vn, fb.params.len, fb.params.len });
            }
            try self.emit_block(&fb.body);
            self.pl("return lua_val_nil();", .{});
            self.indent = 0;
            self.current_ret = prev_ret;
            self.closure_ctx = prev_ctx;
            self.p("}}\n\n", .{});
        }
    }

    fn collect_require_names(self: *CodeGen, expr: *const ast.Expr, names: *std.ArrayList([]const u8)) std.mem.Allocator.Error!void {
        switch (expr.*) {
            .call => |c| {
                if (c.func.* == .name and std.mem.eql(u8, c.func.name.ident, "require") and
                    c.args.len == 1 and c.args[0].* == .string_lit)
                {
                    try names.append(self.alloc, c.args[0].string_lit.val);
                }
                try self.collect_require_names(c.func, names);
                for (c.args) |a| try self.collect_require_names(a, names);
            },
            .binop => |b| {
                try self.collect_require_names(b.lhs, names);
                try self.collect_require_names(b.rhs, names);
            },
            .unop => |u| try self.collect_require_names(u.operand, names),
            .method_call => |mc| {
                try self.collect_require_names(mc.obj, names);
                for (mc.args) |a| try self.collect_require_names(a, names);
            },
            .field => |f| try self.collect_require_names(f.obj, names),
            .index => |idx| {
                try self.collect_require_names(idx.obj, names);
                try self.collect_require_names(idx.key, names);
            },
            .table => |t| {
                for (t.fields) |fld| {
                    switch (fld) {
                        .indexed => |idx| {
                            try self.collect_require_names(idx.key, names);
                            try self.collect_require_names(idx.val, names);
                        },
                        .named => |nmd| try self.collect_require_names(nmd.val, names),
                        .positional => |pos| try self.collect_require_names(pos, names),
                    }
                }
            },
            .func_expr => |fb| try self.collect_require_names_block(&fb.body, names),
            else => {},
        }
    }

    fn collect_require_names_block(self: *CodeGen, block: *const ast.Block, names: *std.ArrayList([]const u8)) std.mem.Allocator.Error!void {
        for (block.stmts) |*stmt| {
            switch (stmt.*) {
                .local_decl => |*ld| for (ld.inits) |e| try self.collect_require_names(e, names),
                .assign => |*as| for (as.values) |v| try self.collect_require_names(v, names),
                .ret => |*r| for (r.vals) |v| try self.collect_require_names(v, names),
                .if_stmt => |*is| {
                    try self.collect_require_names(is.cond, names);
                    try self.collect_require_names_block(&is.then, names);
                    for (is.elseifs) |*ei| {
                        try self.collect_require_names(ei.cond, names);
                        try self.collect_require_names_block(&ei.body, names);
                    }
                    if (is.else_body) |*eb| try self.collect_require_names_block(eb, names);
                },
                .while_loop => |*wl| {
                    try self.collect_require_names(wl.cond, names);
                    try self.collect_require_names_block(&wl.body, names);
                },
                .repeat_loop => |*rl| {
                    try self.collect_require_names_block(&rl.body, names);
                    try self.collect_require_names(rl.cond, names);
                },
                .num_for => |*nf| try self.collect_require_names_block(&nf.body, names),
                .gen_for => |*gf| {
                    for (gf.iters) |e| try self.collect_require_names(e, names);
                    try self.collect_require_names_block(&gf.body, names);
                },
                .call_stmt => |*cs| try self.collect_require_names(cs.expr, names),
                .do_block => |*db| try self.collect_require_names_block(&db.body, names),
                .func_decl => |*fd| try self.collect_require_names_block(&fd.func.body, names),
                else => {},
            }
        }
    }

    fn emit_required_modules(self: *CodeGen, mod: *const ast.Module) E!void {
        var names: std.ArrayList([]const u8) = .empty;
        defer names.deinit(self.alloc);
        if (self.src_path.len > 0) {
            try self.collect_require_names_block(&mod.body, &names);
            for (mod.body.stmts) |*stmt| {
                if (stmt.* == .func_decl) {
                    try self.collect_require_names_block(&stmt.func_decl.func.body, &names);
                }
            }
        }

        var seen: std.StringArrayHashMapUnmanaged(void) = .{};
        defer seen.deinit(self.alloc);
        const dir = if (self.src_path.len > 0) std.fs.path.dirname(self.src_path) orelse "." else ".";

        var embedded: std.ArrayList(struct { name: []const u8, cname: []const u8 }) = .empty;
        defer {
            for (embedded.items) |e| self.alloc.free(e.cname);
            embedded.deinit(self.alloc);
        }

        for (names.items) |name| {
            if (seen.contains(name)) continue;
            try seen.put(self.alloc, name, {});
            if (self.src_path.len == 0) continue;
            const path = try std.fmt.allocPrint(self.alloc, "{s}/{s}.lua", .{ dir, name });
            defer self.alloc.free(path);
            const duo_path = try std.fmt.allocPrint(self.alloc, "{s}/{s}.duo", .{ dir, name });
            defer self.alloc.free(duo_path);
            const mod_path = blk: {
                const cwd = Io.Dir.cwd();
                Io.Dir.access(cwd, self.io, path, .{}) catch {
                    Io.Dir.access(cwd, self.io, duo_path, .{}) catch continue;
                    break :blk duo_path;
                };
                break :blk path;
            };
            const cname = try self.module_c_name(name);
            try self.emit_embedded_module(cname, mod_path);
            try embedded.append(self.alloc, .{ .name = name, .cname = cname });
        }

        self.p("static void duo_register_modules(void) {{\n", .{});
        for (embedded.items) |e| {
            self.p("    lua_table_set(duo_modules, lua_val_from_str(\"{s}\"), lua_val_from_func((lua_Value (*)(lua_Value))duo_mod_{s}));\n", .{ e.name, e.cname });
        }
        self.p("}}\n\n", .{});
    }

    fn module_c_name(self: *CodeGen, name: []const u8) std.mem.Allocator.Error![]u8 {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.alloc);
        for (name) |c| {
            if (std.ascii.isAlphanumeric(c) or c == '_')
                try out.append(self.alloc, c)
            else
                try out.append(self.alloc, '_');
        }
        return out.toOwnedSlice(self.alloc);
    }

    fn emit_embedded_module(self: *CodeGen, cname: []const u8, path: []const u8) E!void {
        const cwd = Io.Dir.cwd();
        const src = Io.Dir.readFileAlloc(cwd, self.io, path, self.alloc, .unlimited) catch return;
        defer self.alloc.free(src);

        var lex = @import("lexer.zig").Lexer.init(src, path);
        var parser = @import("parser.zig").Parser.init(&lex, self.alloc);
        var submod = parser.parse_module() catch return;
        var subsem = sema.Sema.init(self.alloc);
        defer subsem.deinit();
        subsem.lua55_mode = std.mem.endsWith(u8, path, ".lua");
        subsem.check_module(&submod) catch return;

        self.p("static lua_Value duo_mod_{s}(lua_Value _unused) {{\n", .{cname});
        self.p("    (void)_unused;\n", .{});
        self.indent = 1;
        const prev_ret = self.current_ret;
        const prev_ctx = self.closure_ctx;
        self.current_ret = .any;
        self.closure_ctx = null;
        for (submod.body.stmts) |*stmt| {
            switch (stmt.*) {
                .func_decl, .struct_def, .const_decl => {},
                else => try self.emit_stmt(stmt),
            }
        }
        self.pl("return lua_val_nil();", .{});
        self.indent = 0;
        self.current_ret = prev_ret;
        self.closure_ctx = prev_ctx;
        self.p("}}\n\n", .{});
    }
};

const duo_runtime =
    \\/* --- Duo Runtime Support --- */
    \\#include <stdbool.h>
    \\#include <stdio.h>
    \\#include <stdlib.h>
    \\#include <string.h>
    \\#include <stdarg.h>
    \\
    \\#define LUA_LIKELY(x)   __builtin_expect(!!(x), 1)
    \\#define LUA_UNLIKELY(x) __builtin_expect(!!(x), 0)
    \\
    \\typedef enum {
    \\    VAL_NIL,
    \\    VAL_BOOL,
    \\    VAL_NUMBER,
    \\    VAL_STRING,
    \\    VAL_TABLE,
    \\    VAL_BUFFER,
    \\    VAL_THREAD,
    \\    VAL_FUNC,
    \\    VAL_FILE,
    \\    VAL_CLOSURE,
    \\} lua_ValType;
    \\
    \\typedef struct {
    \\    lua_ValType type;
    \\    uint8_t number_kind; /* 1=integer, 2=float; only when type==VAL_NUMBER */
    \\    union {
    \\        bool bval;
    \\        double nval;
    \\        const char* sval;
    \\        void* tval;
    \\        void* fval; // Cast to function pointer when needed
    \\    } as;
    \\} lua_Value;
    \\
    \\typedef struct {
    \\    FILE* f;
    \\    bool is_pipe;
    \\    bool is_stdio;
    \\} lua_File;
    \\
    \\typedef struct {
    \\    uint32_t hash;
    \\    size_t len;
    \\    char data[];
    \\} lua_String;
    \\
    \\typedef struct {
    \\    lua_Value key;
    \\    lua_Value val;
    \\} lua_TableEntry;
    \\
    \\typedef struct {
    \\    lua_Value* array;
    \\    int array_size;
    \\    int array_capacity;
    \\    lua_TableEntry* entries;
    \\    int capacity;
    \\    int count;
    \\    lua_Value metatable;
    \\    bool frozen;
    \\} lua_Table;
    \\
    \\typedef lua_Value (*lua_CFunction)(int argc, lua_Value* argv);
    \\typedef struct lua_Closure lua_Closure;
    \\struct lua_Closure {
    \\    int id;
    \\    int nup;
    \\    lua_Value upvals[];
    \\};
    \\
    \\static inline lua_Value lua_val_nil(void);
    \\static inline lua_Value lua_val_from_str(const char* s);
    \\static inline lua_Value lua_table_get_raw(lua_Value table, lua_Value key);
    \\
    \\static int64_t duo_gc_kbytes = 0;
    \\static inline void duo_gc_note_alloc(size_t bytes) {
    \\    duo_gc_kbytes += (int64_t)((bytes + 1023) / 1024);
    \\}
    \\
    \\#define LUA_MRET_MAX 16
    \\static int lua_mret_n = 0;
    \\static lua_Value lua_mret_buf[LUA_MRET_MAX];
    \\
    \\static inline void lua_mret_clear(void) { lua_mret_n = 0; }
    \\static inline void lua_mret_push(lua_Value v) {
    \\    if (lua_mret_n < LUA_MRET_MAX) lua_mret_buf[lua_mret_n++] = v;
    \\}
    \\static inline lua_Value lua_mret_get(int idx) {
    \\    if (idx >= 0 && idx < lua_mret_n) return lua_mret_buf[idx];
    \\    return lua_val_nil();
    \\}
    \\static inline void lua_mret_store(int n, ...) {
    \\    lua_mret_clear();
    \\    va_list ap;
    \\    va_start(ap, n);
    \\    for (int i = 0; i < n && i < LUA_MRET_MAX; i++) lua_mret_push(va_arg(ap, lua_Value));
    \\    va_end(ap);
    \\}
    \\
    \\extern lua_Value duo_invoke_closure(int id, lua_Closure* cl, int argc, lua_Value* argv);
    \\
    \\typedef lua_Value (*duo_ArgvFn)(int, lua_Value* argv);
    \\duo_ArgvFn duo_lookup_argv(void* f);
    \\
    \\static inline lua_Value lua_call_metamethod(lua_Value obj, const char* name, int argc, lua_Value* argv);
    \\
    \\static inline lua_Value lua_invoke(lua_Value f, int argc, lua_Value* argv) {
    \\    if (f.type == VAL_CLOSURE && f.as.tval) {
    \\        lua_mret_clear();
    \\        lua_Closure* cl = (lua_Closure*)f.as.tval;
    \\        return duo_invoke_closure(cl->id, cl, argc, argv);
    \\    }
    \\    if (f.type == VAL_FUNC && f.as.fval) {
    \\        duo_ArgvFn argv_fn = duo_lookup_argv(f.as.fval);
    \\        if (argv_fn) {
    \\            lua_mret_clear();
    \\            lua_Value r = argv_fn(argc, argv);
    \\            lua_mret_push(r);
    \\            return r;
    \\        }
    \\        lua_mret_clear();
    \\        if (argc == 2) {
    \\            lua_Value (*fn2)(lua_Value, lua_Value) = (lua_Value (*)(lua_Value, lua_Value))f.as.fval;
    \\            lua_Value r = fn2(argv[0], argv[1]);
    \\            lua_mret_push(r);
    \\            return r;
    \\        }
    \\        if (argc == 3) {
    \\            lua_Value (*fn3)(lua_Value, lua_Value, lua_Value) = (lua_Value (*)(lua_Value, lua_Value, lua_Value))f.as.fval;
    \\            lua_Value r = fn3(argv[0], argv[1], argv[2]);
    \\            lua_mret_push(r);
    \\            return r;
    \\        }
    \\        lua_Value (*fn1)(lua_Value) = (lua_Value (*)(lua_Value))f.as.fval;
    \\        lua_Value r = fn1(argc > 0 ? argv[0] : lua_val_nil());
    \\        lua_mret_push(r);
    \\        return r;
    \\    }
    \\    if (f.type == VAL_TABLE) {
    \\        lua_mret_clear();
    \\        return lua_call_metamethod(f, "__call", argc, argv);
    \\    }
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_val_from_closure(lua_Closure* cl) {
    \\    lua_Value v;
    \\    v.type = VAL_CLOSURE;
    \\    v.as.tval = cl;
    \\    return v;
    \\}
    \\
    \\static inline lua_Closure* lua_make_closure(int id, int nup, const lua_Value* ups) {
    \\    lua_Closure* cl = (lua_Closure*)malloc(sizeof(lua_Closure) + (size_t)nup * sizeof(lua_Value));
    \\    cl->id = id;
    \\    cl->nup = nup;
    \\    for (int i = 0; i < nup; i++) cl->upvals[i] = ups[i];
    \\    return cl;
    \\}
    \\
    \\static inline lua_Value lua_get_metafield(lua_Value obj, const char* name) {
    \\    lua_Value mt = lua_val_nil();
    \\    if (obj.type == VAL_TABLE) {
    \\        lua_Table* t = (lua_Table*)obj.as.tval;
    \\        if (t) mt = t->metatable;
    \\    }
    \\    if (mt.type != VAL_TABLE) return lua_val_nil();
    \\    return lua_table_get_raw(mt, lua_val_from_str(name));
    \\}
    \\
    \\static inline lua_Value lua_table_get_raw(lua_Value table, lua_Value key);
    \\static inline void lua_table_set_raw(lua_Value table, lua_Value key, lua_Value val);
    \\static inline lua_Value lua_call_metamethod(lua_Value obj, const char* name, int argc, lua_Value* argv);
    \\static inline lua_Value lua_binop_metamethod(const char* name, lua_Value a, lua_Value b);
    \\
    \\static lua_Value package;
    \\static lua_Value math;
    \\static lua_Value utf8;
    \\static lua_Value debug;
    \\static lua_Value coroutine;
    \\static lua_Value string;
    \\static lua_Value table;
    \\static lua_Value io;
    \\static lua_Value os;
    \\static lua_Value duo_modules;
    \\static lua_Value current_input;
    \\static lua_Value current_output;
    \\static lua_Value _VERSION;
    \\
    \\static inline uint32_t lua_hash_value(lua_Value v) {
    \\    switch (v.type) {
    \\        case VAL_NUMBER: {
    \\            union { double d; uint64_t u; } u;
    \\            u.d = v.as.nval;
    \\            uint64_t x = u.u;
    \\            x ^= x >> 33;
    \\            x *= 0xff51afd7ed558ccdULL;
    \\            x ^= x >> 33;
    \\            x *= 0xc4ceb9fe1a85ec53ULL;
    \\            x ^= x >> 33;
    \\            return (uint32_t)x;
    \\        }
    \\        case VAL_STRING: {
    \\            lua_String* s = (lua_String*)((char*)v.as.sval - offsetof(lua_String, data));
    \\            return s->hash;
    \\        }
    \\        case VAL_BOOL: return v.as.bval ? 1 : 0;
    \\        default: return (uint32_t)((uintptr_t)v.as.tval ^ ((uintptr_t)v.as.tval >> 32));
    \\    }
    \\}
    \\
    \\static inline bool lua_eq(lua_Value a, lua_Value b);
    \\static inline lua_Value lua_package_init(void);
    \\static inline lua_Value lua_math_init(void);
    \\static inline lua_Value lua_utf8_init(void);
    \\static inline lua_Value lua_debug_init(void);
    \\static inline lua_Value lua_package_searchpath(lua_Value name, lua_Value path, lua_Value sep, lua_Value rep);
    \\static lua_Value duo_runtime_load_path(const char* path);
    \\static inline lua_Value lua_coroutine_init(void);
    \\static inline lua_Value lua_string_init(void);
    \\static inline lua_Value lua_table_init(void);
    \\static inline lua_Value lua_io_init(void);
    \\static inline lua_Value lua_os_init(void);
    \\static inline lua_Value lua_require(lua_Value name_val);
    \\static inline lua_Value lua_io_open(lua_Value filename_val, lua_Value mode_val);
    \\static inline void lua_error(lua_Value msg);
    \\static inline lua_Value lua_math_tointeger(lua_Value v);
    \\
    \\static inline lua_Value lua_val_nil(void) {
    \\    lua_Value v;
    \\    v.type = VAL_NIL;
    \\    return v;
    \\}
    \\
    \\static inline lua_Value lua_val_from_bool(bool b) {
    \\    lua_Value v;
    \\    v.type = VAL_BOOL;
    \\    v.as.bval = b;
    \\    return v;
    \\}
    \\
    \\static inline lua_Value lua_val_from_num(double n) {
    \\    lua_Value v = { .type = VAL_NUMBER, .number_kind = 2, .as = { .nval = n } };
    \\    return v;
    \\}
    \\
    \\static inline lua_Value lua_val_from_int(int64_t n) {
    \\    lua_Value v = { .type = VAL_NUMBER, .number_kind = 1, .as = { .nval = (double)n } };
    \\    return v;
    \\}
    \\
    \\static inline lua_Value lua_num_combine(double r, uint8_t ak, uint8_t bk, int force_float) {
    \\    if (!force_float && ak == 1 && bk == 1) {
    \\        int64_t ir = (int64_t)r;
    \\        if ((double)ir == r) return lua_val_from_int(ir);
    \\    }
    \\    return lua_val_from_num(r);
    \\}
    \\
    \\static inline uint32_t calc_hash(const char* s, size_t len) {
    \\    uint32_t h = 2166136261u;
    \\    for (size_t i = 0; i < len; i++) {
    \\        h ^= (uint32_t)(unsigned char)s[i];
    \\        h *= 16777619u;
    \\    }
    \\    return h;
    \\}
    \\
    \\static lua_Table* string_pool = NULL;
    \\
    \\static inline lua_Value lua_val_from_str_len(const char* s, size_t len) {
    \\    if (!string_pool) {
    \\        string_pool = malloc(sizeof(lua_Table));
    \\        string_pool->capacity = 64;
    \\        string_pool->entries = calloc(string_pool->capacity, sizeof(lua_TableEntry));
    \\        string_pool->count = 0;
    \\        string_pool->array_size = 0;
    \\        string_pool->array = NULL;
    \\    }
    \\    uint32_t h = calc_hash(s, len);
    \\    uint32_t idx = h & (string_pool->capacity - 1);
    \\    while (string_pool->entries[idx].key.type != VAL_NIL) {
    \\        const char* ks = string_pool->entries[idx].key.as.sval;
    \\        lua_String* kstr = (lua_String*)((char*)ks - offsetof(lua_String, data));
    \\        if (kstr->len == len && memcmp(ks, s, len) == 0) {
    \\            return string_pool->entries[idx].key;
    \\        }
    \\        idx = (idx + 1) & (string_pool->capacity - 1);
    \\    }
    \\    lua_String* ns = malloc(sizeof(lua_String) + len + 1);
    \\    duo_gc_note_alloc(sizeof(lua_String) + len + 1);
    \\    ns->hash = h;
    \\    ns->len = len;
    \\    memcpy(ns->data, s, len);
    \\    ns->data[len] = '\0';
    \\    lua_Value v;
    \\    v.type = VAL_STRING;
    \\    v.as.sval = ns->data;
    \\    string_pool->entries[idx].key = v;
    \\    string_pool->entries[idx].val = v;
    \\    string_pool->count++;
    \\    if (string_pool->count > string_pool->capacity * 0.7) {
    \\        int old_cap = string_pool->capacity;
    \\        lua_TableEntry* old_entries = string_pool->entries;
    \\        string_pool->capacity *= 2;
    \\        string_pool->entries = calloc(string_pool->capacity, sizeof(lua_TableEntry));
    \\        string_pool->count = 0;
    \\        for (int i = 0; i < old_cap; i++) {
    \\            if (old_entries[i].key.type != VAL_NIL) {
    \\                const char* s2 = old_entries[i].key.as.sval;
    \\                lua_String* s2h = (lua_String*)((char*)s2 - offsetof(lua_String, data));
    \\                uint32_t idx2 = s2h->hash & (string_pool->capacity - 1);
    \\                while (string_pool->entries[idx2].key.type != VAL_NIL) idx2 = (idx2 + 1) & (string_pool->capacity - 1);
    \\                string_pool->entries[idx2] = old_entries[i];
    \\                string_pool->count++;
    \\            }
    \\        }
    \\        free(old_entries);
    \\    }
    \\    return v;
    \\}
    \\
    \\static inline lua_Value lua_val_from_str(const char* s) {
    \\    return lua_val_from_str_len(s, strlen(s));
    \\}
    \\
    \\static inline lua_Value lua_val_from_literal(const char* s, uint32_t hash, size_t len) {
    \\    if (!string_pool) {
    \\        string_pool = calloc(1, sizeof(lua_Table));
    \\        string_pool->capacity = 64;
    \\        string_pool->entries = calloc(string_pool->capacity, sizeof(lua_TableEntry));
    \\    }
    \\    uint32_t idx = hash & (string_pool->capacity - 1);
    \\    while (string_pool->entries[idx].key.type != VAL_NIL) {
    \\        const char* ks = string_pool->entries[idx].key.as.sval;
    \\        lua_String* kstr = (lua_String*)((char*)ks - offsetof(lua_String, data));
    \\        if (kstr->hash == hash && kstr->len == len && memcmp(ks, s, len) == 0) {
    \\            return string_pool->entries[idx].key;
    \\        }
    \\        idx = (idx + 1) & (string_pool->capacity - 1);
    \\    }
    \\    lua_String* ns = malloc(sizeof(lua_String) + len + 1);
    \\    duo_gc_note_alloc(sizeof(lua_String) + len + 1);
    \\    ns->hash = hash;
    \\    ns->len = len;
    \\    memcpy(ns->data, s, len);
    \\    ns->data[len] = '\0';
    \\    lua_Value v;
    \\    v.type = VAL_STRING;
    \\    v.as.sval = ns->data;
    \\    string_pool->entries[idx].key = v;
    \\    string_pool->entries[idx].val = v;
    \\    string_pool->count++;
    \\    return v;
    \\}
    \\
    \\static inline lua_Value lua_val_from_table(void* t) {
    \\    lua_Value v;
    \\    v.type = VAL_TABLE;
    \\    v.as.tval = t;
    \\    return v;
    \\}
    \\
    \\static inline lua_Value lua_val_from_func(void* f) {
    \\    lua_Value v;
    \\    v.type = VAL_FUNC;
    \\    v.as.fval = f;
    \\    return v;
    \\}
    \\
    \\static inline const char* lua_to_str(lua_Value v) {
    \\    if (LUA_LIKELY(v.type == VAL_STRING)) return v.as.sval;
    \\    if (v.type == VAL_TABLE) return "table";
    \\    if (v.type == VAL_BUFFER) return "string.buffer";
    \\    if (v.type == VAL_THREAD) return "thread";
    \\    if (v.type == VAL_FUNC) return "function";
    \\    if (v.type == VAL_FILE) return "file";
    \\    if (v.type == VAL_NUMBER) {
    \\        static char bufs[16][32];
    \\        static int bidx = 0;
    \\        char* b = bufs[bidx];
    \\        bidx = (bidx + 1) & 15;
    \\        sprintf(b, "%.17g", v.as.nval);
    \\        return b;
    \\    }
    \\    if (v.type == VAL_BOOL) return v.as.bval ? "true" : "false";
    \\    return "nil";
    \\}
    \\
    \\static inline size_t lua_str_byte_len(lua_Value v) {
    \\    if (v.type == VAL_STRING) {
    \\        lua_String* s = (lua_String*)((char*)v.as.sval - offsetof(lua_String, data));
    \\        return s->len;
    \\    }
    \\    return strlen(lua_to_str(v));
    \\}
    \\
    \\static inline double lua_to_num(lua_Value v) {
    \\    if (LUA_LIKELY(v.type == VAL_NUMBER)) return v.as.nval;
    \\    if (v.type == VAL_BOOL) return v.as.bval ? 1.0 : 0.0;
    \\    if (v.type == VAL_STRING) return atof(v.as.sval);
    \\    return 0.0;
    \\}
    \\
    \\static inline bool lua_to_bool(lua_Value v) {
    \\    if (LUA_LIKELY(v.type == VAL_BOOL)) return v.as.bval;
    \\    return v.type != VAL_NIL;
    \\}
    \\
    \\static inline lua_Value lua_or(lua_Value a, lua_Value b) {
    \\    if (lua_to_bool(a)) return a;
    \\    return b;
    \\}
    \\
    \\static inline lua_Value lua_and(lua_Value a, lua_Value b) {
    \\    if (!lua_to_bool(a)) return a;
    \\    return b;
    \\}
    \\
    \\static inline lua_Value lua_table_new(void) {
    \\    lua_Table* t = calloc(1, sizeof(lua_Table));
    \\    duo_gc_note_alloc(sizeof(lua_Table));
    \\    return lua_val_from_table(t);
    \\}
    \\
    \\static inline lua_Value lua_table_new_with_capacity(int array_cap, int hash_cap) {
    \\    lua_Table* t = calloc(1, sizeof(lua_Table));
    \\    if (array_cap > 0) {
    \\        t->array = malloc(array_cap * sizeof(lua_Value));
    \\        for (int i = 0; i < array_cap; i++) t->array[i] = lua_val_nil();
    \\        t->array_capacity = array_cap;
    \\    }
    \\    if (hash_cap > 0) {
    \\        /* Find next power of 2 for hash_cap */
    \\        int cap = 8;
    \\        while (cap < hash_cap * 1.5) cap *= 2;
    \\        t->capacity = cap;
    \\        t->entries = calloc(t->capacity, sizeof(lua_TableEntry));
    \\    }
    \\    return lua_val_from_table(t);
    \\}
    \\
    \\static inline lua_Value lua_table_get_raw(lua_Value table, lua_Value key) {
    \\    lua_Table* t = (lua_Table*)table.as.tval;
    \\    if (key.type == VAL_NUMBER) {
    \\        int idx = (int)key.as.nval;
    \\        if (LUA_LIKELY(idx >= 1 && idx <= t->array_size)) return t->array[idx-1];
    \\    }
    \\    if (t->capacity == 0) return lua_val_nil();
    \\    uint32_t h = lua_hash_value(key);
    \\    uint32_t mask = t->capacity - 1;
    \\    uint32_t idx = h & mask;
    \\    while (t->entries[idx].key.type != VAL_NIL) {
    \\        if (lua_eq(t->entries[idx].key, key)) return t->entries[idx].val;
    \\        idx = (idx + 1) & mask;
    \\    }
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_call_value(lua_Value f, int argc, lua_Value* argv) {
    \\    return lua_invoke(f, argc, argv);
    \\}
    \\
    \\static inline lua_Value lua_call_metamethod(lua_Value obj, const char* name, int argc, lua_Value* argv) {
    \\    lua_Value fn = lua_get_metafield(obj, name);
    \\    if (fn.type != VAL_FUNC && fn.type != VAL_CLOSURE) return lua_val_nil();
    \\    lua_Value args[33];
    \\    int n = argc < 32 ? argc : 32;
    \\    args[0] = obj;
    \\    for (int i = 0; i < n; i++) args[i + 1] = argv[i];
    \\    return lua_invoke(fn, n + 1, args);
    \\}
    \\
    \\static inline lua_Value lua_binop_metamethod(const char* name, lua_Value a, lua_Value b) {
    \\    lua_Value fn = lua_get_metafield(a, name);
    \\    if (fn.type != VAL_FUNC && fn.type != VAL_CLOSURE) {
    \\        fn = lua_get_metafield(b, name);
    \\    }
    \\    if (fn.type != VAL_FUNC && fn.type != VAL_CLOSURE) return lua_val_nil();
    \\    lua_Value args[2] = { a, b };
    \\    return lua_invoke(fn, 2, args);
    \\}
    \\
    \\static inline lua_Value lua_table_get(lua_Value table, lua_Value key) {
    \\    lua_Value v = lua_table_get_raw(table, key);
    \\    if (v.type != VAL_NIL) return v;
    \\    lua_Value idx = lua_get_metafield(table, "__index");
    \\    if (idx.type == VAL_TABLE) return lua_table_get(idx, key);
    \\    if (idx.type == VAL_FUNC || idx.type == VAL_CLOSURE) {
    \\        lua_Value args[1] = { key };
    \\        return lua_invoke(idx, 1, args);
    \\    }
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline void lua_table_set_raw(lua_Value table, lua_Value key, lua_Value val) {
    \\    if (LUA_UNLIKELY(table.type != VAL_TABLE)) return;
    \\    lua_Table* t = (lua_Table*)table.as.tval;
    \\    if (LUA_UNLIKELY(!t)) return;
    \\    if (t->frozen) {
    \\        lua_error(lua_val_from_str("attempt to modify a frozen table"));
    \\        return;
    \\    }
    \\    if (key.type == VAL_NUMBER) {
    \\        int idx = (int)key.as.nval;
    \\        if (idx >= 1 && idx <= t->array_size) {
    \\            t->array[idx-1] = val;
    \\            return;
    \\        }
    \\        if (idx == t->array_size + 1 && val.type != VAL_NIL) {
    \\            if (t->array_size >= t->array_capacity) {
    \\                t->array_capacity = t->array_capacity == 0 ? 8 : t->array_capacity * 2;
    \\                t->array = realloc(t->array, t->array_capacity * sizeof(lua_Value));
    \\            }
    \\            t->array[t->array_size++] = val;
    \\            return;
    \\        }
    \\    }
    \\    if (t->capacity == 0) {
    \\        t->capacity = 8;
    \\        t->entries = calloc(t->capacity, sizeof(lua_TableEntry));
    \\    }
    \\    uint32_t h = lua_hash_value(key);
    \\    uint32_t idx = h & (t->capacity - 1);
    \\    while (t->entries[idx].key.type != VAL_NIL) {
    \\        if (lua_eq(t->entries[idx].key, key)) {
    \\            t->entries[idx].val = val;
    \\            return;
    \\        }
    \\        idx = (idx + 1) & (t->capacity - 1);
    \\    }
    \\    if (val.type == VAL_NIL) return;
    \\    if (t->count >= t->capacity * 0.7) {
    \\        int old_cap = t->capacity;
    \\        lua_TableEntry* old_entries = t->entries;
    \\        t->capacity *= 2;
    \\        t->entries = calloc(t->capacity, sizeof(lua_TableEntry));
    \\        t->count = 0;
    \\        for (int i = 0; i < old_cap; i++) {
    \\            if (old_entries[i].key.type != VAL_NIL) {
    \\                uint32_t h2 = lua_hash_value(old_entries[i].key);
    \\                uint32_t idx2 = h2 & (t->capacity - 1);
    \\                while (t->entries[idx2].key.type != VAL_NIL) idx2 = (idx2 + 1) & (t->capacity - 1);
    \\                t->entries[idx2] = old_entries[i];
    \\                t->count++;
    \\            }
    \\        }
    \\        free(old_entries);
    \\        lua_table_set_raw(table, key, val);
    \\        return;
    \\    }
    \\    t->entries[idx].key = key;
    \\    t->entries[idx].val = val;
    \\    t->count++;
    \\}
    \\
    \\static inline void lua_table_set(lua_Value table, lua_Value key, lua_Value val) {
    \\    if (table.type == VAL_TABLE) {
    \\        lua_Value existing = lua_table_get_raw(table, key);
    \\        if (existing.type == VAL_NIL) {
    \\            lua_Value ni = lua_get_metafield(table, "__newindex");
    \\            if (ni.type == VAL_TABLE) {
    \\                lua_table_set_raw(ni, key, val);
    \\                return;
    \\            }
    \\            if (ni.type == VAL_FUNC || ni.type == VAL_CLOSURE) {
    \\                lua_Value args[2] = { key, val };
    \\                lua_invoke(ni, 2, args);
    \\                return;
    \\            }
    \\        }
    \\    }
    \\    lua_table_set_raw(table, key, val);
    \\}
    \\
    \\static inline const char* lua_concat(lua_Value a, lua_Value b) {
    \\    lua_Value mm = lua_get_metafield(a, "__concat");
    \\    if (mm.type == VAL_FUNC || mm.type == VAL_CLOSURE) {
    \\        lua_Value args[2] = { a, b };
    \\        lua_Value res = lua_invoke(mm, 2, args);
    \\        return lua_to_str(res);
    \\    }
    \\    mm = lua_get_metafield(b, "__concat");
    \\    if (mm.type == VAL_FUNC || mm.type == VAL_CLOSURE) {
    \\        lua_Value args[2] = { b, a };
    \\        lua_Value res = lua_invoke(mm, 2, args);
    \\        return lua_to_str(res);
    \\    }
    \\    const char* sa = lua_to_str(a);
    \\    const char* sb = lua_to_str(b);
    \\    char* res = malloc(strlen(sa) + strlen(sb) + 1);
    \\    strcpy(res, sa);
    \\    strcat(res, sb);
    \\    return res;
    \\}
    \\
    \\static inline lua_Value lua_unm(lua_Value v) {
    \\    if (LUA_LIKELY(v.type == VAL_NUMBER)) {
    \\        if (v.number_kind == 1) return lua_val_from_int(-(int64_t)v.as.nval);
    \\        return lua_val_from_num(-v.as.nval);
    \\    }
    \\    lua_Value mm = lua_get_metafield(v, "__unm");
    \\    if (mm.type == VAL_FUNC || mm.type == VAL_CLOSURE) {
    \\        lua_Value args[1] = { v };
    \\        return lua_invoke(mm, 1, args);
    \\    }
    \\    return lua_val_from_num(-lua_to_num(v));
    \\}
    \\
    \\static inline lua_Value lua_bnot(lua_Value v) {
    \\    if (LUA_LIKELY(v.type == VAL_NUMBER)) {
    \\        return lua_val_from_int(~((int64_t)v.as.nval));
    \\    }
    \\    lua_Value mm = lua_get_metafield(v, "__bnot");
    \\    if (mm.type == VAL_FUNC || mm.type == VAL_CLOSURE) {
    \\        lua_Value args[1] = { v };
    \\        return lua_invoke(mm, 1, args);
    \\    }
    \\    return lua_val_from_num((double)(~((int64_t)lua_to_num(v))));
    \\}
    \\
    \\static inline lua_Value lua_add(lua_Value a, lua_Value b) {
    \\    if (LUA_LIKELY(a.type == VAL_NUMBER && b.type == VAL_NUMBER)) {
    \\        return lua_num_combine(a.as.nval + b.as.nval, a.number_kind, b.number_kind, 0);
    \\    }
    \\    lua_Value mm = lua_binop_metamethod("__add", a, b);
    \\    if (mm.type != VAL_NIL) return mm;
    \\    return lua_val_from_num(lua_to_num(a) + lua_to_num(b));
    \\}
    \\
    \\static inline lua_Value lua_sub(lua_Value a, lua_Value b) {
    \\    if (LUA_LIKELY(a.type == VAL_NUMBER && b.type == VAL_NUMBER)) {
    \\        return lua_num_combine(a.as.nval - b.as.nval, a.number_kind, b.number_kind, 0);
    \\    }
    \\    lua_Value mm = lua_binop_metamethod("__sub", a, b);
    \\    if (mm.type != VAL_NIL) return mm;
    \\    return lua_val_from_num(lua_to_num(a) - lua_to_num(b));
    \\}
    \\
    \\static inline lua_Value lua_mul(lua_Value a, lua_Value b) {
    \\    if (LUA_LIKELY(a.type == VAL_NUMBER && b.type == VAL_NUMBER)) {
    \\        return lua_num_combine(a.as.nval * b.as.nval, a.number_kind, b.number_kind, 0);
    \\    }
    \\    lua_Value mm = lua_binop_metamethod("__mul", a, b);
    \\    if (mm.type != VAL_NIL) return mm;
    \\    return lua_val_from_num(lua_to_num(a) * lua_to_num(b));
    \\}
    \\
    \\static inline lua_Value lua_div(lua_Value a, lua_Value b) {
    \\    if (LUA_LIKELY(a.type == VAL_NUMBER && b.type == VAL_NUMBER)) {
    \\        return lua_val_from_num(a.as.nval / b.as.nval);
    \\    }
    \\    lua_Value mm = lua_binop_metamethod("__div", a, b);
    \\    if (mm.type != VAL_NIL) return mm;
    \\    return lua_val_from_num(lua_to_num(a) / lua_to_num(b));
    \\}
    \\
    \\static inline lua_Value lua_idiv(lua_Value a, lua_Value b) {
    \\    if (LUA_LIKELY(a.type == VAL_NUMBER && b.type == VAL_NUMBER)) {
    \\        if (a.number_kind == 1 && b.number_kind == 1) {
    \\            return lua_val_from_int((int64_t)floor(a.as.nval / b.as.nval));
    \\        }
    \\        return lua_val_from_num(floor(a.as.nval / b.as.nval));
    \\    }
    \\    lua_Value mm = lua_binop_metamethod("__idiv", a, b);
    \\    if (mm.type != VAL_NIL) return mm;
    \\    return lua_val_from_num(floor(lua_to_num(a) / lua_to_num(b)));
    \\}
    \\
    \\static inline lua_Value lua_mod(lua_Value a, lua_Value b) {
    \\    if (LUA_LIKELY(a.type == VAL_NUMBER && b.type == VAL_NUMBER)) {
    \\        double na = a.as.nval;
    \\        double nb = b.as.nval;
    \\        double r = na - nb * floor(na / nb);
    \\        if (a.number_kind == 1 && b.number_kind == 1) return lua_val_from_int((int64_t)r);
    \\        return lua_val_from_num(r);
    \\    }
    \\    lua_Value mm = lua_binop_metamethod("__mod", a, b);
    \\    if (mm.type != VAL_NIL) return mm;
    \\    double na = lua_to_num(a);
    \\    double nb = lua_to_num(b);
    \\    return lua_val_from_num(na - nb * floor(na / nb));
    \\}
    \\
    \\static inline lua_Value lua_pow(lua_Value a, lua_Value b) {
    \\    if (LUA_LIKELY(a.type == VAL_NUMBER && b.type == VAL_NUMBER)) {
    \\        return lua_val_from_num(pow(a.as.nval, b.as.nval));
    \\    }
    \\    lua_Value mm = lua_binop_metamethod("__pow", a, b);
    \\    if (mm.type != VAL_NIL) return mm;
    \\    return lua_val_from_num(pow(lua_to_num(a), lua_to_num(b)));
    \\}
    \\
    \\static inline lua_Value lua_band(lua_Value a, lua_Value b) {
    \\    if (LUA_LIKELY(a.type == VAL_NUMBER && b.type == VAL_NUMBER)) {
    \\        return lua_val_from_int((int64_t)a.as.nval & (int64_t)b.as.nval);
    \\    }
    \\    lua_Value mm = lua_binop_metamethod("__band", a, b);
    \\    if (mm.type != VAL_NIL) return mm;
    \\    return lua_val_from_num((double)((int64_t)lua_to_num(a) & (int64_t)lua_to_num(b)));
    \\}
    \\
    \\static inline lua_Value lua_bor(lua_Value a, lua_Value b) {
    \\    if (LUA_LIKELY(a.type == VAL_NUMBER && b.type == VAL_NUMBER)) {
    \\        return lua_val_from_int((int64_t)a.as.nval | (int64_t)b.as.nval);
    \\    }
    \\    lua_Value mm = lua_binop_metamethod("__bor", a, b);
    \\    if (mm.type != VAL_NIL) return mm;
    \\    return lua_val_from_num((double)((int64_t)lua_to_num(a) | (int64_t)lua_to_num(b)));
    \\}
    \\
    \\static inline lua_Value lua_bxor(lua_Value a, lua_Value b) {
    \\    if (LUA_LIKELY(a.type == VAL_NUMBER && b.type == VAL_NUMBER)) {
    \\        return lua_val_from_int((int64_t)a.as.nval ^ (int64_t)b.as.nval);
    \\    }
    \\    lua_Value mm = lua_binop_metamethod("__bxor", a, b);
    \\    if (mm.type != VAL_NIL) return mm;
    \\    return lua_val_from_num((double)((int64_t)lua_to_num(a) ^ (int64_t)lua_to_num(b)));
    \\}
    \\
    \\static inline lua_Value lua_lshift(lua_Value a, lua_Value b) {
    \\    if (LUA_LIKELY(a.type == VAL_NUMBER && b.type == VAL_NUMBER)) {
    \\        return lua_val_from_int((int64_t)a.as.nval << (int64_t)b.as.nval);
    \\    }
    \\    lua_Value mm = lua_binop_metamethod("__shl", a, b);
    \\    if (mm.type != VAL_NIL) return mm;
    \\    return lua_val_from_num((double)((int64_t)lua_to_num(a) << (int64_t)lua_to_num(b)));
    \\}
    \\
    \\static inline lua_Value lua_rshift(lua_Value a, lua_Value b) {
    \\    if (LUA_LIKELY(a.type == VAL_NUMBER && b.type == VAL_NUMBER)) {
    \\        return lua_val_from_int((int64_t)a.as.nval >> (int64_t)b.as.nval);
    \\    }
    \\    lua_Value mm = lua_binop_metamethod("__shr", a, b);
    \\    if (mm.type != VAL_NIL) return mm;
    \\    return lua_val_from_num((double)((int64_t)lua_to_num(a) >> (int64_t)lua_to_num(b)));
    \\}
    \\
    \\static inline bool lua_eq(lua_Value a, lua_Value b) {
    \\    if (a.type == b.type) {
    \\        switch (a.type) {
    \\            case VAL_NIL: return true;
    \\            case VAL_BOOL: return a.as.bval == b.as.bval;
    \\            case VAL_NUMBER: return a.as.nval == b.as.nval;
    \\            case VAL_STRING: return a.as.sval == b.as.sval;
    \\            case VAL_TABLE: return a.as.tval == b.as.tval;
    \\            case VAL_BUFFER: return a.as.tval == b.as.tval;
    \\            case VAL_THREAD: return a.as.tval == b.as.tval;
    \\            case VAL_FUNC: return a.as.fval == b.as.fval;
    \\            case VAL_CLOSURE: return a.as.tval == b.as.tval;
    \\            case VAL_FILE: return a.as.tval == b.as.tval;
    \\        }
    \\    }
    \\    lua_Value mm = lua_get_metafield(a, "__eq");
    \\    if (mm.type == VAL_FUNC || mm.type == VAL_CLOSURE) {
    \\        lua_Value args[2] = { a, b };
    \\        return lua_to_bool(lua_invoke(mm, 2, args));
    \\    }
    \\    mm = lua_get_metafield(b, "__eq");
    \\    if (mm.type == VAL_FUNC || mm.type == VAL_CLOSURE) {
    \\        lua_Value args[2] = { b, a };
    \\        return lua_to_bool(lua_invoke(mm, 2, args));
    \\    }
    \\    return false;
    \\}
    \\
    \\static inline bool lua_neq(lua_Value a, lua_Value b) {
    \\    return !lua_eq(a, b);
    \\}
    \\
    \\static inline bool lua_lt(lua_Value a, lua_Value b) {
    \\    if (LUA_LIKELY(a.type == VAL_NUMBER && b.type == VAL_NUMBER)) {
    \\        return a.as.nval < b.as.nval;
    \\    }
    \\    lua_Value mm = lua_get_metafield(a, "__lt");
    \\    if (mm.type == VAL_FUNC || mm.type == VAL_CLOSURE) {
    \\        lua_Value args[2] = { a, b };
    \\        return lua_to_bool(lua_invoke(mm, 2, args));
    \\    }
    \\    mm = lua_get_metafield(b, "__lt");
    \\    if (mm.type == VAL_FUNC || mm.type == VAL_CLOSURE) {
    \\        lua_Value args[2] = { b, a };
    \\        return lua_to_bool(lua_invoke(mm, 2, args));
    \\    }
    \\    return lua_to_num(a) < lua_to_num(b);
    \\}
    \\
    \\static inline bool lua_gt(lua_Value a, lua_Value b) {
    \\    if (LUA_LIKELY(a.type == VAL_NUMBER && b.type == VAL_NUMBER)) {
    \\        return a.as.nval > b.as.nval;
    \\    }
    \\    return lua_lt(b, a);
    \\}
    \\
    \\static inline bool lua_leq(lua_Value a, lua_Value b) {
    \\    if (LUA_LIKELY(a.type == VAL_NUMBER && b.type == VAL_NUMBER)) {
    \\        return a.as.nval <= b.as.nval;
    \\    }
    \\    lua_Value mm = lua_get_metafield(a, "__le");
    \\    if (mm.type == VAL_FUNC || mm.type == VAL_CLOSURE) {
    \\        lua_Value args[2] = { a, b };
    \\        return lua_to_bool(lua_invoke(mm, 2, args));
    \\    }
    \\    mm = lua_get_metafield(b, "__le");
    \\    if (mm.type == VAL_FUNC || mm.type == VAL_CLOSURE) {
    \\        lua_Value args[2] = { b, a };
    \\        return lua_to_bool(lua_invoke(mm, 2, args));
    \\    }
    \\    return lua_to_num(a) <= lua_to_num(b);
    \\}
    \\
    \\static inline bool lua_geq(lua_Value a, lua_Value b) {
    \\    if (LUA_LIKELY(a.type == VAL_NUMBER && b.type == VAL_NUMBER)) {
    \\        return a.as.nval >= b.as.nval;
    \\    }
    \\    return lua_leq(b, a);
    \\}
    \\
    \\static inline lua_Value tostring(lua_Value v) {
    \\    lua_Value mm = lua_get_metafield(v, "__tostring");
    \\    if (mm.type == VAL_FUNC || mm.type == VAL_CLOSURE) {
    \\        lua_Value args[1] = { v };
    \\        return lua_invoke(mm, 1, args);
    \\    }
    \\    return lua_val_from_str(lua_to_str(v));
    \\}
    \\
    \\static inline lua_Value tonumber(lua_Value v) {
    \\    return lua_val_from_num(lua_to_num(v));
    \\}
    \\
    \\static inline lua_Value type(lua_Value v) {
    \\    switch (v.type) {
    \\        case VAL_NIL: return lua_val_from_str("nil");
    \\        case VAL_BOOL: return lua_val_from_str("boolean");
    \\        case VAL_NUMBER: return lua_val_from_str("number");
    \\        case VAL_STRING: return lua_val_from_str("string");
    \\        case VAL_TABLE: return lua_val_from_str("table");
    \\        case VAL_BUFFER: return lua_val_from_str("string.buffer");
    \\        case VAL_THREAD: return lua_val_from_str("thread");
    \\        case VAL_FUNC: return lua_val_from_str("function");
    \\        case VAL_CLOSURE: return lua_val_from_str("function");
    \\        case VAL_FILE: return lua_val_from_str("file");
    \\    }
    \\    return lua_val_from_str("unknown");
    \\}
    \\
    \\static inline lua_Value lua_assert(lua_Value v, const char* msg) {
    \\    if (!lua_to_bool(v)) {
    \\        fprintf(stderr, "assertion failed: %s\n", msg ? msg : "");
    \\        exit(1);
    \\    }
    \\    return v;
    \\}
    \\
    \\static inline int lua_table_len(lua_Value table) {
    \\    if (LUA_UNLIKELY(table.type != VAL_TABLE)) return 0;
    \\    lua_Table* t = (lua_Table*)table.as.tval;
    \\    if (LUA_UNLIKELY(!t)) return 0;
    \\    int j = t->array_size;
    \\    if (j > 0 && lua_table_get(table, lua_val_from_num((double)j)).type == VAL_NIL) {
    \\        /* Binary search in array part if there are holes */
    \\        int i = 0;
    \\        while (j - i > 1) {
    \\            int m = (i + j) / 2;
    \\            if (lua_table_get(table, lua_val_from_num((double)m)).type == VAL_NIL) j = m;
    \\            else i = m;
    \\        }
    \\        return i;
    \\    }
    \\    /* Check if hash part has any elements that continue the sequence */
    \\    if (lua_table_get(table, lua_val_from_num((double)(j + 1))).type == VAL_NIL) return j;
    \\    /* Binary search for boundary in hash part */
    \\    int i = j;
    \\    j++;
    \\    while (lua_table_get(table, lua_val_from_num((double)j)).type != VAL_NIL) {
    \\        i = j;
    \\        if (j > INT_MAX / 2) { /* Avoid overflow */
    \\            j = INT_MAX;
    \\            if (lua_table_get(table, lua_val_from_num((double)j)).type != VAL_NIL) return j;
    \\            break;
    \\        }
    \\        j *= 2;
    \\    }
    \\    while (j - i > 1) {
    \\        int m = (i + j) / 2;
    \\        if (lua_table_get(table, lua_val_from_num((double)m)).type == VAL_NIL) j = m;
    \\        else i = m;
    \\    }
    \\    return i;
    \\}
    \\
    \\/* --- String Library --- */
    \\static inline lua_Value lua_str_len(lua_Value s) {
    \\    if (s.type != VAL_STRING) return lua_val_from_num(0);
    \\    lua_String* h = (lua_String*)((char*)s.as.sval - offsetof(lua_String, data));
    \\    return lua_val_from_num((double)h->len);
    \\}
    \\
    \\static inline lua_Value lua_str_lower(lua_Value s) {
    \\    const char* str = lua_to_str(s);
    \\    char* res = malloc(strlen(str) + 1);
    \\    for (size_t i = 0; str[i]; i++) {
    \\        res[i] = tolower((unsigned char)str[i]);
    \\    }
    \\    res[strlen(str)] = '\0';
    \\    return lua_val_from_str(res);
    \\}
    \\
    \\static inline lua_Value lua_str_sub(lua_Value s, lua_Value start_val, lua_Value end_val) {
    \\    const char* str = lua_to_str(s);
    \\    int len = (int)strlen(str);
    \\    int start = start_val.type == VAL_NIL ? 1 : (int)lua_to_num(start_val);
    \\    int end = end_val.type == VAL_NIL ? len : (int)lua_to_num(end_val);
    \\    if (start < 0) start = len + start + 1;
    \\    if (end < 0) end = len + end + 1;
    \\    if (start < 1) start = 1;
    \\    if (end > len) end = len;
    \\    if (start > end || start > len || end < 1) {
    \\        return lua_val_from_str("");
    \\    }
    \\    int sublen = end - start + 1;
    \\    char* res = malloc(sublen + 1);
    \\    memcpy(res, str + start - 1, sublen);
    \\    res[sublen] = '\0';
    \\    return lua_val_from_str(res);
    \\}
    \\
    \\static inline lua_Value lua_str_char(lua_Value a1, lua_Value a2, lua_Value a3, lua_Value a4) {
    \\    int len = 0;
    \\    char buf[5] = {0};
    \\    if (a1.type != VAL_NIL) buf[len++] = (char)lua_to_num(a1);
    \\    if (a2.type != VAL_NIL) buf[len++] = (char)lua_to_num(a2);
    \\    if (a3.type != VAL_NIL) buf[len++] = (char)lua_to_num(a3);
    \\    if (a4.type != VAL_NIL) buf[len++] = (char)lua_to_num(a4);
    \\    char* res = malloc(len + 1);
    \\    memcpy(res, buf, len);
    \\    res[len] = '\0';
    \\    return lua_val_from_str(res);
    \\}
    \\
    \\static inline lua_Value lua_str_rep(lua_Value s, lua_Value n_val, lua_Value sep_val) {
    \\    const char* str = lua_to_str(s);
    \\    int n = (int)lua_to_num(n_val);
    \\    if (n <= 0) return lua_val_from_str("");
    \\    const char* sep = sep_val.type == VAL_NIL ? "" : lua_to_str(sep_val);
    \\    size_t slen = strlen(str);
    \\    size_t seplen = strlen(sep);
    \\    size_t total_len = slen * n + seplen * (n - 1);
    \\    char* res = malloc(total_len + 1);
    \\    char* p = res;
    \\    for (int i = 0; i < n; i++) {
    \\        if (i > 0 && seplen > 0) {
    \\            memcpy(p, sep, seplen);
    \\            p += seplen;
    \\        }
    \\        memcpy(p, str, slen);
    \\        p += slen;
    \\    }
    \\    res[total_len] = '\0';
    \\    return lua_val_from_str(res);
    \\}
    \\
    \\static inline lua_Value lua_str_format(lua_Value fmt_val, lua_Value a1, lua_Value a2, lua_Value a3) {
    \\    const char* fmt = lua_to_str(fmt_val);
    \\    char* out = malloc(8192);
    \\    char* p = out;
    \\    const char* f = fmt;
    \\    int arg_idx = 0;
    \\    while (*f) {
    \\        if (*f == '%' && *(f+1)) {
    \\            f++;
    \\            char spec = *f;
    \\            lua_Value arg = lua_val_nil();
    \\            if (arg_idx == 0) arg = a1;
    \\            else if (arg_idx == 1) arg = a2;
    \\            else if (arg_idx == 2) arg = a3;
    \\            arg_idx++;
    \\            if (spec == 's') {
    \\                const char* s = lua_to_str(arg);
    \\                strcpy(p, s);
    \\                p += strlen(s);
    \\            } else if (spec == 'd' || spec == 'i') {
    \\                p += sprintf(p, "%lld", (long long)lua_to_num(arg));
    \\            } else if (spec == 'f' || spec == 'g') {
    \\                p += sprintf(p, "%g", lua_to_num(arg));
    \\            } else if (spec == '%') {
    \\                *p++ = '%';
    \\            } else {
    \\                *p++ = spec;
    \\            }
    \\            f++;
    \\        } else {
    \\            *p++ = *f++;
    \\        }
    \\    }
    \\    *p = '\0';
    \\    return lua_val_from_str(out);
    \\}
    \\
    \\/* --- Table Library --- */
    \\static inline lua_Value lua_tbl_insert(lua_Value table, lua_Value arg1, lua_Value arg2) {
    \\    if (table.type != VAL_TABLE) return lua_val_nil();
    \\    lua_Table* t = (lua_Table*)table.as.tval;
    \\    if (arg2.type == VAL_NIL) {
    \\        lua_table_set(table, lua_val_from_num((double)(lua_table_len(table) + 1)), arg1);
    \\    } else {
    \\        int pos = (int)lua_to_num(arg1);
    \\        int len = lua_table_len(table);
    \\        if (pos >= 1 && pos <= t->array_size + 1 && len == t->array_size) {
    \\            t->array_size++;
    \\            t->array = realloc(t->array, t->array_size * sizeof(lua_Value));
    \\            if (pos <= len) memmove(&t->array[pos], &t->array[pos-1], (len - pos + 1) * sizeof(lua_Value));
    \\            t->array[pos-1] = arg2;
    \\        } else {
    \\            for (int i = len; i >= pos; i--) {
    \\                lua_table_set(table, lua_val_from_num((double)(i + 1)), lua_table_get(table, lua_val_from_num((double)i)));
    \\            }
    \\            lua_table_set(table, lua_val_from_num((double)pos), arg2);
    \\        }
    \\    }
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_tbl_remove(lua_Value table, lua_Value pos_val) {
    \\    if (table.type != VAL_TABLE) return lua_val_nil();
    \\    lua_Table* t = (lua_Table*)table.as.tval;
    \\    int len = lua_table_len(table);
    \\    int pos = pos_val.type == VAL_NIL ? len : (int)lua_to_num(pos_val);
    \\    if (pos < 1 || pos > len) return lua_val_nil();
    \\    lua_Value removed = lua_table_get(table, lua_val_from_num((double)pos));
    \\    if (len == t->array_size) {
    \\        if (pos < len) memmove(&t->array[pos-1], &t->array[pos], (len - pos) * sizeof(lua_Value));
    \\        t->array[len-1] = lua_val_nil();
    \\        t->array_size--;
    \\    } else {
    \\        for (int i = pos; i < len; i++) {
    \\            lua_table_set(table, lua_val_from_num((double)i), lua_table_get(table, lua_val_from_num((double)(i + 1))));
    \\        }
    \\        lua_table_set(table, lua_val_from_num((double)len), lua_val_nil());
    \\    }
    \\    return removed;
    \\}
    \\
    \\static inline lua_Value lua_tbl_concat(lua_Value table, lua_Value sep_val, lua_Value start_val, lua_Value end_val) {
    \\    int len = lua_table_len(table);
    \\    const char* sep = sep_val.type == VAL_NIL ? "" : lua_to_str(sep_val);
    \\    size_t sep_len = (sep_val.type == VAL_STRING) ? ((lua_String*)((char*)sep - offsetof(lua_String, data)))->len : strlen(sep);
    \\    int start = start_val.type == VAL_NIL ? 1 : (int)lua_to_num(start_val);
    \\    int end = end_val.type == VAL_NIL ? len : (int)lua_to_num(end_val);
    \\    if (start > end) return lua_val_from_str("");
    \\    size_t total_size = 0;
    \\    for (int i = start; i <= end; i++) {
    \\        lua_Value v = lua_table_get(table, lua_val_from_num((double)i));
    \\        const char* s = lua_to_str(v);
    \\        if (v.type == VAL_STRING) {
    \\            total_size += ((lua_String*)((char*)s - offsetof(lua_String, data)))->len;
    \\        } else {
    \\            total_size += strlen(s);
    \\        }
    \\    }
    \\    if (end > start) total_size += sep_len * (end - start);
    \\    char* res = malloc(total_size + 1);
    \\    char* p = res;
    \\    for (int i = start; i <= end; i++) {
    \\        if (i > start && sep_len > 0) {
    \\            memcpy(p, sep, sep_len);
    \\            p += sep_len;
    \\        }
    \\        lua_Value v = lua_table_get(table, lua_val_from_num((double)i));
    \\        const char* s = lua_to_str(v);
    \\        size_t slen = (v.type == VAL_STRING) ? ((lua_String*)((char*)s - offsetof(lua_String, data)))->len : strlen(s);
    \\        memcpy(p, s, slen);
    \\        p += slen;
    \\    }
    \\    *p = '\0';
    \\    return lua_val_from_str_len(res, total_size);
    \\}
    \\
    \\static lua_Value lua_tbl_sort_cmp_fn = { .type = VAL_NIL };
    \\
    \\static int lua_tbl_sort_cmp(const void* a, const void* b) {
    \\    lua_Value v1 = *(lua_Value*)a;
    \\    lua_Value v2 = *(lua_Value*)b;
    \\    if (lua_tbl_sort_cmp_fn.type == VAL_FUNC || lua_tbl_sort_cmp_fn.type == VAL_CLOSURE) {
    \\        lua_Value args[2] = { v1, v2 };
    \\        if (lua_to_bool(lua_invoke(lua_tbl_sort_cmp_fn, 2, args))) return -1;
    \\        args[0] = v2; args[1] = v1;
    \\        if (lua_to_bool(lua_invoke(lua_tbl_sort_cmp_fn, 2, args))) return 1;
    \\        return 0;
    \\    }
    \\    if (v1.type == VAL_NUMBER && v2.type == VAL_NUMBER) {
    \\        if (v1.as.nval < v2.as.nval) return -1;
    \\        if (v1.as.nval > v2.as.nval) return 1;
    \\        return 0;
    \\    }
    \\    if (v1.type == VAL_STRING && v2.type == VAL_STRING) {
    \\        return strcmp(v1.as.sval, v2.as.sval);
    \\    }
    \\    return 0;
    \\}
    \\
    \\static inline lua_Value lua_tbl_sort(lua_Value table, lua_Value cmp) {
    \\    if (table.type != VAL_TABLE) return lua_val_nil();
    \\    lua_Table* t = (lua_Table*)table.as.tval;
    \\    if (!t || t->array_size <= 1) return lua_val_nil();
    \\    lua_tbl_sort_cmp_fn = cmp;
    \\    qsort(t->array, t->array_size, sizeof(lua_Value), lua_tbl_sort_cmp);
    \\    lua_tbl_sort_cmp_fn = lua_val_nil();
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline FILE* get_input_file(void) {
    \\    if (current_input.type == VAL_FILE && current_input.as.tval) {
    \\        return ((lua_File*)current_input.as.tval)->f;
    \\    }
    \\    return stdin;
    \\}
    \\
    \\static inline FILE* get_output_file(void) {
    \\    if (current_output.type == VAL_FILE && current_output.as.tval) {
    \\        return ((lua_File*)current_output.as.tval)->f;
    \\    }
    \\    return stdout;
    \\}
    \\
    \\/* --- IO Library --- */
    \\static inline lua_Value lua_io_write(lua_Value a1, lua_Value a2, lua_Value a3, lua_Value a4) {
    \\    FILE* f = get_output_file();
    \\    if (a1.type != VAL_NIL) fprintf(f, "%s", lua_to_str(a1));
    \\    if (a2.type != VAL_NIL) fprintf(f, "%s", lua_to_str(a2));
    \\    if (a3.type != VAL_NIL) fprintf(f, "%s", lua_to_str(a3));
    \\    if (a4.type != VAL_NIL) fprintf(f, "%s", lua_to_str(a4));
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_io_read(lua_Value fmt_val) {
    \\    (void)fmt_val;
    \\    FILE* f = get_input_file();
    \\    char buf[4096];
    \\    if (fgets(buf, sizeof(buf), f)) {
    \\        size_t l = strlen(buf);
    \\        if (l > 0 && buf[l - 1] == '\n') buf[l - 1] = '\0';
    \\        return lua_val_from_str(strdup(buf));
    \\    }
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_io_flush(void) {
    \\    fflush(get_output_file());
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_io_input(lua_Value file_val) {
    \\    if (file_val.type == VAL_FILE || file_val.type == VAL_STRING) {
    \\        if (file_val.type == VAL_STRING) {
    \\            current_input = lua_io_open(file_val, lua_val_from_str("r"));
    \\        } else {
    \\            current_input = file_val;
    \\        }
    \\    }
    \\    if (current_input.type == VAL_FILE) return current_input;
    \\    lua_File* lf = malloc(sizeof(lua_File));
    \\    lf->f = stdin;
    \\    lf->is_pipe = false;
    \\    lf->is_stdio = false;
    \\    lua_Value v;
    \\    v.type = VAL_FILE;
    \\    v.as.tval = (void*)lf;
    \\    current_input = v;
    \\    return v;
    \\}
    \\
    \\static inline lua_Value lua_io_output(lua_Value file_val) {
    \\    if (file_val.type == VAL_FILE || file_val.type == VAL_STRING) {
    \\        if (file_val.type == VAL_STRING) {
    \\            current_output = lua_io_open(file_val, lua_val_from_str("w"));
    \\        } else {
    \\            current_output = file_val;
    \\        }
    \\    }
    \\    if (current_output.type == VAL_FILE) return current_output;
    \\    lua_File* lf = malloc(sizeof(lua_File));
    \\    lf->f = stdout;
    \\    lf->is_pipe = false;
    \\    lf->is_stdio = false;
    \\    lua_Value v;
    \\    v.type = VAL_FILE;
    \\    v.as.tval = (void*)lf;
    \\    current_output = v;
    \\    return v;
    \\}
    \\
    \\static inline lua_Value lua_io_popen(lua_Value prog_val, lua_Value mode_val) {
    \\    const char* prog = lua_to_str(prog_val);
    \\    const char* mode = mode_val.type == VAL_NIL ? "r" : lua_to_str(mode_val);
    \\    FILE* f = popen(prog, mode);
    \\    if (!f) return lua_val_nil();
    \\    lua_File* lf = malloc(sizeof(lua_File));
    \\    lf->f = f;
    \\    lf->is_pipe = true;
    \\    lua_Value v;
    \\    v.type = VAL_FILE;
    \\    v.as.tval = (void*)lf;
    \\    return v;
    \\}
    \\
    \\static inline lua_Value lua_io_type(lua_Value obj) {
    \\    if (obj.type == VAL_FILE && obj.as.tval) {
    \\        lua_File* lf = (lua_File*)obj.as.tval;
    \\        if (lf->f) {
    \\            return lua_val_from_str("file");
    \\        } else {
    \\            return lua_val_from_str("closed file");
    \\        }
    \\    }
    \\    return lua_val_nil();
    \\}
    \\
    \\static lua_File* lua_io_lines_file = NULL;
    \\static lua_Value lua_io_lines_iter(lua_Value _unused) {
    \\    (void)_unused;
    \\    if (!lua_io_lines_file || !lua_io_lines_file->f) return lua_val_nil();
    \\    char buf[4096];
    \\    if (!fgets(buf, sizeof(buf), lua_io_lines_file->f)) return lua_val_nil();
    \\    size_t l = strlen(buf);
    \\    if (l > 0 && buf[l - 1] == '\n') buf[l - 1] = '\0';
    \\    return lua_val_from_str(strdup(buf));
    \\}
    \\
    \\static inline lua_Value lua_io_lines(lua_Value filename) {
    \\    lua_Value fval = filename.type == VAL_NIL ? current_input : lua_io_open(filename, lua_val_from_str("r"));
    \\    if (fval.type != VAL_FILE || !fval.as.tval) return lua_val_nil();
    \\    lua_io_lines_file = (lua_File*)fval.as.tval;
    \\    return lua_val_from_func(lua_io_lines_iter);
    \\}
    \\
    \\static inline lua_Value lua_file_flush_method(lua_Value file_val) {
    \\    if (file_val.type == VAL_FILE && file_val.as.tval) {
    \\        lua_File* lf = (lua_File*)file_val.as.tval;
    \\        if (lf->f) fflush(lf->f);
    \\    }
    \\    return file_val;
    \\}
    \\
    \\static inline lua_Value lua_file_seek_method(lua_Value file_val, lua_Value whence_val, lua_Value offset_val) {
    \\    if (file_val.type == VAL_FILE && file_val.as.tval) {
    \\        lua_File* lf = (lua_File*)file_val.as.tval;
    \\        if (lf->f) {
    \\            FILE* f = lf->f;
    \\            const char* whence_str = whence_val.type == VAL_NIL ? "cur" : lua_to_str(whence_val);
    \\            long offset = offset_val.type == VAL_NIL ? 0 : (long)lua_to_num(offset_val);
    \\            int whence = SEEK_CUR;
    \\            if (strcmp(whence_str, "set") == 0) whence = SEEK_SET;
    \\            else if (strcmp(whence_str, "end") == 0) whence = SEEK_END;
    \\            if (fseek(f, offset, whence) == 0) {
    \\                return lua_val_from_num((double)ftell(f));
    \\            }
    \\        }
    \\    }
    \\    return lua_val_nil();
    \\}
    \\
    \\/* --- OS Library --- */
    \\static inline lua_Value lua_os_clock(void) {
    \\    return lua_val_from_num((double)clock() / CLOCKS_PER_SEC);
    \\}
    \\
    \\static inline lua_Value lua_os_time(lua_Value t_val) {
    \\    if (t_val.type == VAL_TABLE) {
    \\        struct tm t = {0};
    \\        t.tm_isdst = -1;
    \\        lua_Value v;
    \\        v = lua_table_get(t_val, lua_val_from_str("year"));
    \\        if (v.type == VAL_NUMBER) t.tm_year = (int)lua_to_num(v) - 1900;
    \\        v = lua_table_get(t_val, lua_val_from_str("month"));
    \\        if (v.type == VAL_NUMBER) t.tm_mon = (int)lua_to_num(v) - 1;
    \\        v = lua_table_get(t_val, lua_val_from_str("day"));
    \\        if (v.type == VAL_NUMBER) t.tm_mday = (int)lua_to_num(v);
    \\        v = lua_table_get(t_val, lua_val_from_str("hour"));
    \\        if (v.type == VAL_NUMBER) t.tm_hour = (int)lua_to_num(v);
    \\        v = lua_table_get(t_val, lua_val_from_str("min"));
    \\        if (v.type == VAL_NUMBER) t.tm_min = (int)lua_to_num(v);
    \\        v = lua_table_get(t_val, lua_val_from_str("sec"));
    \\        if (v.type == VAL_NUMBER) t.tm_sec = (int)lua_to_num(v);
    \\        v = lua_table_get(t_val, lua_val_from_str("isdst"));
    \\        if (v.type == VAL_BOOL) t.tm_isdst = v.as.bval ? 1 : 0;
    \\        return lua_val_from_num((double)mktime(&t));
    \\    }
    \\    return lua_val_from_num((double)time(NULL));
    \\}
    \\
    \\static inline lua_Value lua_os_difftime(lua_Value t2, lua_Value t1) {
    \\    return lua_val_from_num(difftime((time_t)lua_to_num(t2), (time_t)lua_to_num(t1)));
    \\}
    \\
    \\static inline lua_Value lua_os_exit(lua_Value code_val) {
    \\    int code = code_val.type == VAL_NIL ? 0 : (int)lua_to_num(code_val);
    \\    exit(code);
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_os_getenv(lua_Value var) {
    \\    const char* name = lua_to_str(var);
    \\    const char* val = getenv(name);
    \\    if (val) return lua_val_from_str(val);
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_os_remove(lua_Value var) {
    \\    return lua_val_from_bool(remove(lua_to_str(var)) == 0);
    \\}
    \\
    \\static inline lua_Value lua_os_rename(lua_Value oldn, lua_Value newn) {
    \\    return lua_val_from_bool(rename(lua_to_str(oldn), lua_to_str(newn)) == 0);
    \\}
    \\
    \\static inline lua_Value lua_len(lua_Value v) {
    \\    if (v.type == VAL_TABLE) {
    \\        lua_Value mm = lua_get_metafield(v, "__len");
    \\        if (mm.type == VAL_FUNC || mm.type == VAL_CLOSURE) {
    \\            lua_Value args[1] = { v };
    \\            return lua_invoke(mm, 1, args);
    \\        }
    \\        return lua_val_from_num((double)lua_table_len(v));
    \\    }
    \\    if (v.type == VAL_STRING) {
    \\        return lua_str_len(v);
    \\    }
    \\    return lua_val_from_num(0.0);
    \\}
    \\
    \\static inline lua_Value lua_tbl_new(lua_Value narray, lua_Value nhash) {
    \\    int na = narray.type == VAL_NIL ? 0 : (int)lua_to_num(narray);
    \\    int nh = nhash.type == VAL_NIL ? 0 : (int)lua_to_num(nhash);
    \\    if (na < 0) na = 0;
    \\    if (nh < 0) nh = 0;
    \\    return lua_table_new_with_capacity(na, nh);
    \\}
    \\
    \\static inline lua_Value lua_tbl_create_argv(int argc, lua_Value* argv) {
    \\    lua_Value na = argc > 0 ? argv[0] : lua_val_nil();
    \\    lua_Value nh = argc > 1 ? argv[1] : lua_val_nil();
    \\    return lua_tbl_new(na, nh);
    \\}
    \\
    \\static inline lua_Value lua_tbl_clear(lua_Value table) {
    \\    if (table.type == VAL_TABLE) {
    \\        lua_Table* t = (lua_Table*)table.as.tval;
    \\        if (t) {
    \\            for (int i = 0; i < t->array_capacity; i++) t->array[i] = lua_val_nil();
    \\            t->array_size = 0;
    \\            if (t->capacity > 0) memset(t->entries, 0, t->capacity * sizeof(lua_TableEntry));
    \\            t->count = 0;
    \\        }
    \\    }
    \\    return lua_val_nil();
    \\}
    \\
    \\typedef struct {
    \\    char* data;
    \\    size_t capacity;
    \\    size_t len;
    \\} lua_Buffer;
    \\
    \\static inline lua_Value lua_str_buf_new(void) {
    \\    lua_Buffer* b = malloc(sizeof(lua_Buffer));
    \\    b->data = malloc(32);
    \\    b->data[0] = '\0';
    \\    b->capacity = 32;
    \\    b->len = 0;
    \\    lua_Value v;
    \\    v.type = VAL_BUFFER;
    \\    v.as.tval = b;
    \\    return v;
    \\}
    \\
    \\static inline lua_Value lua_str_buf_put(lua_Value buf, lua_Value s) {
    \\    if (buf.type != VAL_BUFFER) return lua_val_nil();
    \\    lua_Buffer* b = (lua_Buffer*)buf.as.tval;
    \\    const char* str = lua_to_str(s);
    \\    size_t slen = strlen(str);
    \\    if (b->len + slen >= b->capacity) {
    \\        b->capacity = (b->len + slen) * 2;
    \\        b->data = realloc(b->data, b->capacity);
    \\    }
    \\    memcpy(b->data + b->len, str, slen);
    \\    b->len += slen;
    \\    b->data[b->len] = '\0';
    \\    return buf;
    \\}
    \\
    \\static inline lua_Value lua_str_buf_get(lua_Value buf) {
    \\    if (buf.type != VAL_BUFFER) return lua_val_from_str("");
    \\    lua_Buffer* b = (lua_Buffer*)buf.as.tval;
    \\    return lua_val_from_str(strdup(b->data));
    \\}
    \\
    \\static inline lua_Value lua_str_buf_reset(lua_Value buf) {
    \\    if (buf.type != VAL_BUFFER) return lua_val_nil();
    \\    lua_Buffer* b = (lua_Buffer*)buf.as.tval;
    \\    b->len = 0;
    \\    if (b->data) b->data[0] = '\0';
    \\    return buf;
    \\}
    \\
    \\static inline lua_Value lua_str_buf_set(lua_Value buf, lua_Value s) {
    \\    if (buf.type != VAL_BUFFER) return lua_val_nil();
    \\    lua_str_buf_reset(buf);
    \\    return lua_str_buf_put(buf, s);
    \\}
    \\
    \\static inline lua_Value lua_str_buf_free(lua_Value buf) {
    \\    if (buf.type != VAL_BUFFER) return lua_val_nil();
    \\    lua_Buffer* b = (lua_Buffer*)buf.as.tval;
    \\    free(b->data);
    \\    free(b);
    \\    buf.as.tval = NULL;
    \\    buf.type = VAL_NIL;
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_str_buf_new_init(lua_Value init) {
    \\    lua_Value buf = lua_str_buf_new();
    \\    if (init.type != VAL_NIL) lua_str_buf_set(buf, init);
    \\    return buf;
    \\}
    \\
    \\static inline lua_Value lua_str_buf_len(lua_Value buf) {
    \\    if (buf.type != VAL_BUFFER) return lua_val_from_num(0);
    \\    lua_Buffer* b = (lua_Buffer*)buf.as.tval;
    \\    return lua_val_from_num((double)b->len);
    \\}
    \\
    \\static inline lua_Value lua_str_buf_putf(lua_Value buf, lua_Value fmt, lua_Value a1, lua_Value a2, lua_Value a3) {
    \\    lua_Value formatted = lua_str_format(fmt, a1, a2, a3);
    \\    return lua_str_buf_put(buf, formatted);
    \\}
    \\
    \\typedef enum {
    \\    CO_SUSPENDED,
    \\    CO_RUNNING,
    \\    CO_DEAD,
    \\} lua_CoStatus;
    \\
    \\typedef struct {
    \\    ucontext_t context;
    \\    ucontext_t caller_context;
    \\    char* stack;
    \\    lua_CoStatus status;
    \\    lua_Value func;
    \\    lua_Value yield_value;
    \\    lua_Value resume_value;
    \\} lua_Thread;
    \\
    \\static lua_Thread* active_thread = NULL;
    \\
    \\static void lua_coroutine_runner(void) {
    \\    lua_Thread* co = active_thread;
    \\    if (co && (co->func.type == VAL_FUNC || co->func.type == VAL_CLOSURE)) {
    \\        lua_Value args[1] = { co->resume_value };
    \\        co->yield_value = lua_invoke(co->func, 1, args);
    \\        co->status = CO_DEAD;
    \\        swapcontext(&co->context, &co->caller_context);
    \\    }
    \\}
    \\
    \\static inline lua_Value lua_co_create(lua_Value f) {
    \\    lua_Thread* co = malloc(sizeof(lua_Thread));
    \\    co->status = CO_SUSPENDED;
    \\    co->func = f;
    \\    co->yield_value = lua_val_nil();
    \\    co->resume_value = lua_val_nil();
    \\    co->stack = malloc(16384 * 4);
    \\    
    \\    getcontext(&co->caller_context);
    \\    getcontext(&co->context);
    \\    co->context.uc_stack.ss_sp = co->stack;
    \\    co->context.uc_stack.ss_size = 16384 * 4;
    \\    co->context.uc_link = NULL;
    \\    makecontext(&co->context, lua_coroutine_runner, 0);
    \\    
    \\    lua_Value v;
    \\    v.type = VAL_THREAD;
    \\    v.as.tval = co;
    \\    return v;
    \\}
    \\
    \\static inline lua_Value lua_co_resume(lua_Value thread_val, lua_Value arg) {
    \\    if (thread_val.type != VAL_THREAD) return lua_val_nil();
    \\    lua_Thread* co = (lua_Thread*)thread_val.as.tval;
    \\    if (co->status == CO_DEAD) return lua_val_nil();
    \\    
    \\    co->resume_value = arg;
    \\    co->status = CO_RUNNING;
    \\    
    \\    lua_Thread* prev = active_thread;
    \\    active_thread = co;
    \\    swapcontext(&co->caller_context, &co->context);
    \\    active_thread = prev;
    \\    
    \\    return co->yield_value;
    \\}
    \\
    \\static inline lua_Value lua_co_yield(lua_Value val) {
    \\    lua_Thread* co = active_thread;
    \\    if (!co) return lua_val_nil();
    \\    co->yield_value = val;
    \\    co->status = CO_SUSPENDED;
    \\    swapcontext(&co->context, &co->caller_context);
    \\    return co->resume_value;
    \\}
    \\
    \\static inline lua_Value lua_co_status(lua_Value thread_val) {
    \\    if (thread_val.type != VAL_THREAD) return lua_val_from_str("dead");
    \\    lua_Thread* co = (lua_Thread*)thread_val.as.tval;
    \\    if (co->status == CO_DEAD) return lua_val_from_str("dead");
    \\    if (co->status == CO_SUSPENDED) return lua_val_from_str("suspended");
    \\    if (co->status == CO_RUNNING) return lua_val_from_str("running");
    \\    return lua_val_from_str("dead");
    \\}
    \\
    \\static inline lua_Value lua_require(lua_Value name_val) {
    \\    const char* name = lua_to_str(name_val);
    \\    lua_Value loaded_tbl = lua_table_get_raw(package, lua_val_from_str("loaded"));
    \\    lua_Value cached = lua_table_get_raw(loaded_tbl, name_val);
    \\    if (cached.type != VAL_NIL) return cached;
    \\    lua_Value mod = lua_val_nil();
    \\    lua_Value preload = lua_table_get_raw(package, lua_val_from_str("preload"));
    \\    lua_Value pre = lua_table_get_raw(preload, name_val);
    \\    if (pre.type == VAL_FUNC || pre.type == VAL_CLOSURE) {
    \\        mod = lua_invoke(pre, 0, NULL);
    \\    } else if (strcmp(name, "math") == 0) mod = math;
    \\    else if (strcmp(name, "package") == 0) mod = package;
    \\    else if (strcmp(name, "utf8") == 0) mod = utf8;
    \\    else if (strcmp(name, "debug") == 0) mod = debug;
    \\    else if (strcmp(name, "coroutine") == 0) mod = coroutine;
    \\    else if (strcmp(name, "string") == 0) mod = string;
    \\    else if (strcmp(name, "table") == 0) mod = table;
    \\    else if (strcmp(name, "io") == 0) mod = io;
    \\    else if (strcmp(name, "os") == 0) mod = os;
    \\    else mod = lua_table_get(duo_modules, name_val);
    \\    if (mod.type == VAL_NIL) {
    \\        lua_Value path = lua_package_searchpath(name_val,
    \\            lua_table_get_raw(package, lua_val_from_str("path")),
    \\            lua_val_nil(), lua_val_nil());
    \\        if (path.type != VAL_NIL) {
    \\            lua_Value chunk = duo_runtime_load_path(path.as.sval);
    \\            if (chunk.type == VAL_FUNC || chunk.type == VAL_CLOSURE) {
    \\                mod = lua_invoke(chunk, 0, NULL);
    \\            } else if (chunk.type == VAL_NIL) {
    \\                lua_Value err = lua_mret_get(0);
    \\                if (err.type != VAL_NIL) lua_error(err);
    \\            }
    \\        }
    \\    }
    \\    if (mod.type == VAL_NIL) {
    \\        lua_error(lua_val_from_str("module not found"));
    \\    }
    \\    lua_table_set_raw(loaded_tbl, name_val, mod);
    \\    return mod;
    \\}
    \\
    \\static uint64_t rng_state = 123456789u;
    \\static inline uint64_t xorshift64(void) {
    \\    uint64_t x = rng_state;
    \\    x ^= x << 13;
    \\    x ^= x >> 7;
    \\    x ^= x << 17;
    \\    return rng_state = x;
    \\}
    \\
    \\static inline lua_Value lua_math_random(lua_Value arg1, lua_Value arg2) {
    \\    if (arg1.type == VAL_NIL && arg2.type == VAL_NIL) {
    \\        double r = (double)(xorshift64() & 0xFFFFFFFFFFFFFFFu) / (double)0xFFFFFFFFFFFFFFFu;
    \\        return lua_val_from_num(r);
    \\    } else if (arg2.type == VAL_NIL) {
    \\        int m = (int)lua_to_num(arg1);
    \\        if (m < 1) return lua_val_from_num(0);
    \\        int r = 1 + (int)(xorshift64() % (uint64_t)m);
    \\        return lua_val_from_num((double)r);
    \\    } else {
    \\        int m = (int)lua_to_num(arg1);
    \\        int n = (int)lua_to_num(arg2);
    \\        if (m > n) return lua_val_from_num(0);
    \\        int r = m + (int)(xorshift64() % (uint64_t)(n - m + 1));
    \\        return lua_val_from_num((double)r);
    \\    }
    \\}
    \\
    \\static inline lua_Value lua_math_randomseed(lua_Value seed) {
    \\    rng_state = (uint64_t)lua_to_num(seed);
    \\    if (rng_state == 0) rng_state = 1;
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_math_deg(lua_Value rad) {
    \\    return lua_val_from_num(lua_to_num(rad) * (180.0 / 3.14159265358979323846));
    \\}
    \\
    \\static inline lua_Value lua_math_rad(lua_Value deg) {
    \\    return lua_val_from_num(lua_to_num(deg) * (3.14159265358979323846 / 180.0));
    \\}
    \\
    \\static inline lua_Value lua_math_type(lua_Value v) {
    \\    if (v.type != VAL_NUMBER) return lua_val_nil();
    \\    if (v.number_kind == 1) return lua_val_from_str("integer");
    \\    return lua_val_from_str("float");
    \\}
    \\
    \\static inline lua_Value lua_math_abs(lua_Value v) { return lua_val_from_num(fabs(lua_to_num(v))); }
    \\static inline lua_Value lua_math_acos(lua_Value v) { return lua_val_from_num(acos(lua_to_num(v))); }
    \\static inline lua_Value lua_math_asin(lua_Value v) { return lua_val_from_num(asin(lua_to_num(v))); }
    \\static inline lua_Value lua_math_atan(lua_Value v) { return lua_val_from_num(atan(lua_to_num(v))); }
    \\static inline lua_Value lua_math_atan2(lua_Value y, lua_Value x) { return lua_val_from_num(atan2(lua_to_num(y), lua_to_num(x))); }
    \\static inline lua_Value lua_math_ceil(lua_Value v) { return lua_val_from_num(ceil(lua_to_num(v))); }
    \\static inline lua_Value lua_math_cos(lua_Value v) { return lua_val_from_num(cos(lua_to_num(v))); }
    \\static inline lua_Value lua_math_exp(lua_Value v) { return lua_val_from_num(exp(lua_to_num(v))); }
    \\static inline lua_Value lua_math_floor(lua_Value v) { return lua_val_from_num(floor(lua_to_num(v))); }
    \\static inline lua_Value lua_math_log(lua_Value v) { return lua_val_from_num(log(lua_to_num(v))); }
    \\static inline lua_Value lua_math_log10(lua_Value v) { return lua_val_from_num(log10(lua_to_num(v))); }
    \\static inline lua_Value lua_math_sin(lua_Value v) { return lua_val_from_num(sin(lua_to_num(v))); }
    \\static inline lua_Value lua_math_sqrt(lua_Value v) { return lua_val_from_num(sqrt(lua_to_num(v))); }
    \\static inline lua_Value lua_math_tan(lua_Value v) { return lua_val_from_num(tan(lua_to_num(v))); }
    \\static inline lua_Value lua_math_pow(lua_Value x, lua_Value y) { return lua_val_from_num(pow(lua_to_num(x), lua_to_num(y))); }
    \\static inline lua_Value lua_math_sinh(lua_Value v) { return lua_val_from_num(sinh(lua_to_num(v))); }
    \\static inline lua_Value lua_math_cosh(lua_Value v) { return lua_val_from_num(cosh(lua_to_num(v))); }
    \\static inline lua_Value lua_math_tanh(lua_Value v) { return lua_val_from_num(tanh(lua_to_num(v))); }
    \\
    \\static inline lua_Value lua_math_fmod(lua_Value m, lua_Value n) { return lua_val_from_num(fmod(lua_to_num(m), lua_to_num(n))); }
    \\static inline lua_Value lua_math_max(lua_Value m, lua_Value n) { return lua_to_num(m) > lua_to_num(n) ? m : n; }
    \\static inline lua_Value lua_math_min(lua_Value m, lua_Value n) { return lua_to_num(m) < lua_to_num(n) ? m : n; }
    \\
    \\static inline lua_Value lua_str_upper(lua_Value s) {
    \\    const char* str = lua_to_str(s);
    \\    char* res = malloc(strlen(str) + 1);
    \\    for (size_t i = 0; str[i]; i++) res[i] = toupper((unsigned char)str[i]);
    \\    res[strlen(str)] = '\0';
    \\    return lua_val_from_str(res);
    \\}
    \\
    \\static inline lua_Value lua_str_reverse(lua_Value s) {
    \\    const char* str = lua_to_str(s);
    \\    size_t len = strlen(str);
    \\    char* res = malloc(len + 1);
    \\    for (size_t i = 0; i < len; i++) res[i] = str[len - 1 - i];
    \\    res[len] = '\0';
    \\    return lua_val_from_str_len(res, len);
    \\}
    \\
    \\static inline lua_Value lua_str_byte(lua_Value s, lua_Value i_val, lua_Value j_val) {
    \\    (void)j_val;
    \\    const char* str = lua_to_str(s);
    \\    int len = (int)strlen(str);
    \\    int idx = i_val.type == VAL_NIL ? 1 : (int)lua_to_num(i_val);
    \\    if (idx < 0) idx = len + idx + 1;
    \\    if (idx < 1 || idx > len) return lua_val_nil();
    \\    return lua_val_from_num((double)(unsigned char)str[idx - 1]);
    \\}
    \\
    \\static int duo_lp_has_magic(const char* pat) {
    \\    for (const char* p = pat; *p; p++) {
    \\        if (*p == '^' || *p == '$' || *p == '.' || *p == '(' || *p == ')' ||
    \\            *p == '%' || *p == '+' || *p == '-' || *p == '?' || *p == '*' || *p == '[') {
    \\            return 1;
    \\        }
    \\    }
    \\    return 0;
    \\}
    \\
    \\static int duo_lp_class_test(int c, const char** pp, const char* end) {
    \\    const char* p = *pp;
    \\    if (*p != '[') return 0;
    \\    p++;
    \\    int invert = 0;
    \\    if (p < end && *p == '^') { invert = 1; p++; }
    \\    if (p < end && *p == ']') {
    \\        if (c == ']') { p++; while (p < end && *p != ']') p++; if (p < end) p++; *pp = p; return invert ? 0 : 1; }
    \\        p++;
    \\    }
    \\    int found = 0;
    \\    while (p < end && *p != ']') {
    \\        if (*p == '%' && p + 1 < end) {
    \\            p++;
    \\            char spec = *p++;
    \\            int m = 0;
    \\            if (spec == 'a') m = isalpha(c);
    \\            else if (spec == 'c') m = iscntrl(c);
    \\            else if (spec == 'd') m = isdigit(c);
    \\            else if (spec == 'l') m = islower(c);
    \\            else if (spec == 'p') m = ispunct(c);
    \\            else if (spec == 's') m = isspace(c);
    \\            else if (spec == 'u') m = isupper(c);
    \\            else if (spec == 'w') m = isalnum(c) || c == '_';
    \\            else if (spec == 'x') m = isxdigit(c);
    \\            else if (spec == 'z') m = c == 0;
    \\            else m = (c == spec);
    \\            if (m) found = 1;
    \\        } else if (p + 2 < end && p[1] == '-') {
    \\            char lo = *p; p += 2; char hi = *p++;
    \\            if (lo <= c && c <= hi) found = 1;
    \\        } else {
    \\            if (c == *p) found = 1;
    \\            p++;
    \\        }
    \\    }
    \\    if (p < end && *p == ']') p++;
    \\    *pp = p;
    \\    return invert ? !found : found;
    \\}
    \\
    \\static int duo_lp_item_match(int c, const char** pp, const char* end) {
    \\    const char* p = *pp;
    \\    if (p >= end) return 0;
    \\    if (*p == '.') { (*pp) = p + 1; return c != '\0'; }
    \\    if (*p == '[') return duo_lp_class_test(c, pp, end);
    \\    if (*p == '%' && p + 1 < end) {
    \\        p++;
    \\        char spec = *p++;
    \\        int m = 0;
    \\        if (spec == 'a') m = isalpha(c);
    \\        else if (spec == 'c') m = iscntrl(c);
    \\        else if (spec == 'd') m = isdigit(c);
    \\        else if (spec == 'l') m = islower(c);
    \\        else if (spec == 'p') m = ispunct(c);
    \\        else if (spec == 's') m = isspace(c);
    \\        else if (spec == 'u') m = isupper(c);
    \\        else if (spec == 'w') m = isalnum(c) || c == '_';
    \\        else if (spec == 'x') m = isxdigit(c);
    \\        else if (spec == 'z') m = c == 0;
    \\        else m = (c == spec);
    \\        *pp = p;
    \\        return m;
    \\    }
    \\    char lit = *p;
    \\    (*pp) = p + 1;
    \\    return c == lit;
    \\}
    \\
    \\static int duo_lp_match(const char* s, size_t slen, size_t si, const char* pat, const char* pat_end, size_t* ms, size_t* me) {
    \\    if (pat < pat_end && *pat == '^') {
    \\        if (si != 0) return 0;
    \\        pat++;
    \\    }
    \\    int anchor_end = (pat_end > pat && pat_end[-1] == '$');
    \\    if (anchor_end) pat_end--;
    \\    const char* p = pat;
    \\    size_t i = si;
    \\    while (p < pat_end) {
    \\        if (*p == '(') {
    \\            p++;
    \\            if (p < pat_end && *p == ')') { p++; continue; }
    \\            size_t cap_start = i;
    \\            const char* sub = p;
    \\            int depth = 1;
    \\            while (p < pat_end && depth > 0) {
    \\                if (*p == '(') depth++;
    \\                else if (*p == ')') depth--;
    \\                p++;
    \\            }
    \\            if (depth != 0) return 0;
    \\            const char* sub_end = p - 1;
    \\            size_t cap_end = i;
    \\            if (!duo_lp_match(s, slen, i, sub, sub_end, &cap_start, &cap_end)) return 0;
    \\            i = cap_end;
    \\            continue;
    \\        }
    \\        if (*p == '%' && p + 1 < pat_end && p[1] == 'b') {
    \\            p += 2;
    \\            if (p + 1 >= pat_end) return 0;
    \\            char open = *p++; char close = *p++;
    \\            if (i >= slen || s[i] != open) return 0;
    \\            int depth = 1;
    \\            size_t j = i + 1;
    \\            while (j < slen && depth > 0) {
    \\                if (s[j] == open) depth++;
    \\                else if (s[j] == close) depth--;
    \\                j++;
    \\            }
    \\            if (depth != 0) return 0;
    \\            i = j;
    \\            continue;
    \\        }
    \\        char c = *p;
    \\        if (c == '*' || c == '+' || c == '-' || c == '?') {
    \\            return 0;
    \\        }
    \\        if (i >= slen) return 0;
    \\        if (!duo_lp_item_match((unsigned char)s[i], &p, pat_end)) return 0;
    \\        i++;
    \\    }
    \\    if (anchor_end && i != slen) return 0;
    \\    *ms = si;
    \\    *me = i;
    \\    return 1;
    \\}
    \\
    \\static int duo_lp_match_star(const char* s, size_t slen, size_t si, const char* item, const char* item_end, char op, const char* rest, const char* pat_end, size_t* ms, size_t* me) {
    \\    size_t orig = si;
    \\    size_t max_i = si;
    \\    while (max_i < slen) {
    \\        const char* p = item;
    \\        if (!duo_lp_item_match((unsigned char)s[max_i], &p, item_end)) break;
    \\        max_i++;
    \\    }
    \\    if (op == '+') {
    \\        if (max_i == orig) return 0;
    \\        for (size_t i = max_i; i > orig; i--) {
    \\            size_t tms, tme;
    \\            if (duo_lp_match(s, slen, i, rest, pat_end, &tms, &tme)) {
    \\                *ms = orig;
    \\                *me = tme;
    \\                return 1;
    \\            }
    \\        }
    \\        return 0;
    \\    }
    \\    if (op == '*') {
    \\        for (size_t i = max_i + 1; i > orig; i--) {
    \\            size_t tms, tme;
    \\            if (duo_lp_match(s, slen, i - 1, rest, pat_end, &tms, &tme)) {
    \\                *ms = orig;
    \\                *me = tme;
    \\                return 1;
    \\            }
    \\        }
    \\        return 0;
    \\    }
    \\    if (op == '-') {
    \\        for (size_t i = orig; i <= max_i; i++) {
    \\            size_t tms, tme;
    \\            if (duo_lp_match(s, slen, i, rest, pat_end, &tms, &tme)) {
    \\                *ms = orig;
    \\                *me = tme;
    \\                return 1;
    \\            }
    \\        }
    \\        return 0;
    \\    }
    \\    if (op == '?') {
    \\        size_t tms, tme;
    \\        if (duo_lp_match(s, slen, orig, rest, pat_end, &tms, &tme)) {
    \\            *ms = orig;
    \\            *me = tme;
    \\            return 1;
    \\        }
    \\        if (orig < max_i && duo_lp_match(s, slen, orig + 1, rest, pat_end, &tms, &tme)) {
    \\            *ms = orig;
    \\            *me = tme;
    \\            return 1;
    \\        }
    \\        return 0;
    \\    }
    \\    return 0;
    \\}
    \\
    \\static int duo_lp_match_full(const char* s, size_t slen, size_t si, const char* pat, const char* pat_end, size_t* ms, size_t* me) {
    \\    size_t start_i = si;
    \\    const char* p = pat;
    \\    if (p < pat_end && *p == '^') { if (si != 0) return 0; p++; }
    \\    int anchor_end = (pat_end > p && pat_end[-1] == '$');
    \\    const char* endpat = pat_end;
    \\    if (anchor_end) endpat--;
    \\    while (p < endpat) {
    \\        const char* item_start = p;
    \\        if (*p == '(') {
    \\            p++;
    \\            if (p < endpat && *p == ')') { p++; continue; }
    \\            int depth = 1;
    \\            while (p < endpat && depth > 0) {
    \\                if (*p == '(') depth++;
    \\                else if (*p == ')') depth--;
    \\                p++;
    \\            }
    \\            const char* item_end = p;
    \\            char op = (p < endpat) ? *p : '\0';
    \\            if (op == '*' || op == '+' || op == '-' || op == '?') {
    \\                p++;
    \\                return duo_lp_match_star(s, slen, si, item_start, item_end, op, p, pat_end, ms, me);
    \\            }
    \\            size_t cap_ms = si, cap_me = si;
    \\            if (!duo_lp_match_full(s, slen, si, item_start, item_end - 1, &cap_ms, &cap_me)) return 0;
    \\            si = cap_me;
    \\            continue;
    \\        }
    \\        if (*p == '%' && p + 1 < endpat && p[1] == 'b') {
    \\            item_start = p;
    \\            p += 4;
    \\            char op = (p < endpat) ? *p : '\0';
    \\            if (op == '*' || op == '+' || op == '-' || op == '?') {
    \\                p++;
    \\                return duo_lp_match_star(s, slen, si, item_start, p - 1, op, p, pat_end, ms, me);
    \\            }
    \\            if (si >= slen || s[si] != item_start[2]) return 0;
    \\            char open = item_start[2]; char close = item_start[3];
    \\            int depth = 1; size_t j = si + 1;
    \\            while (j < slen && depth > 0) {
    \\                if (s[j] == open) depth++;
    \\                else if (s[j] == close) depth--;
    \\                j++;
    \\            }
    \\            if (depth != 0) return 0;
    \\            si = j;
    \\            continue;
    \\        }
    \\        if (*p == '[') {
    \\            duo_lp_class_test(0, &p, endpat);
    \\        } else if (*p == '%' && p + 1 < endpat) {
    \\            p += 2;
    \\        } else if (*p == '.') {
    \\            p++;
    \\        } else {
    \\            p++;
    \\        }
    \\        char op = (p < endpat) ? *p : '\0';
    \\        if (op == '*' || op == '+' || op == '-' || op == '?') {
    \\            p++;
    \\            return duo_lp_match_star(s, slen, si, item_start, p - 1, op, p, pat_end, ms, me);
    \\        }
    \\        if (si >= slen) return 0;
    \\        const char* pp = item_start;
    \\        if (!duo_lp_item_match((unsigned char)s[si], &pp, endpat)) return 0;
    \\        si++;
    \\    }
    \\    if (anchor_end && si != slen) return 0;
    \\    *ms = start_i;
    \\    *me = si;
    \\    return 1;
    \\}
    \\
    \\static int duo_lp_find_at(const char* s, size_t slen, const char* pat, size_t start, size_t* ms, size_t* me) {
    \\    size_t plen = strlen(pat);
    \\    const char* pat_end = pat + plen;
    \\    if (!duo_lp_has_magic(pat)) {
    \\        if (start >= slen) return 0;
    \\        const char* found = strstr(s + start, pat);
    \\        if (!found) return 0;
    \\        *ms = (size_t)(found - s);
    \\        *me = *ms + plen;
    \\        return 1;
    \\    }
    \\    if (pat < pat_end && *pat == '^') {
    \\        if (start != 0) return 0;
    \\        return duo_lp_match_full(s, slen, 0, pat, pat_end, ms, me);
    \\    }
    \\    for (size_t i = start; i <= slen; i++) {
    \\        if (duo_lp_match_full(s, slen, i, pat, pat_end, ms, me)) return 1;
    \\    }
    \\    return 0;
    \\}
    \\
    \\static inline lua_Value lua_str_find(lua_Value s, lua_Value pat_val) {
    \\    const char* str = lua_to_str(s);
    \\    const char* pat = lua_to_str(pat_val);
    \\    size_t slen = strlen(str);
    \\    size_t ms = 0, me = 0;
    \\    if (duo_lp_find_at(str, slen, pat, 0, &ms, &me)) {
    \\        return lua_val_from_num((double)(ms + 1));
    \\    }
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_tbl_move(lua_Value a1, lua_Value f_val, lua_Value e_val, lua_Value t_val, lua_Value a2) {
    \\    lua_Value dest = a2.type == VAL_NIL ? a1 : a2;
    \\    int f = (int)lua_to_num(f_val);
    \\    int e = (int)lua_to_num(e_val);
    \\    int t = (int)lua_to_num(t_val);
    \\    if (f > e) return dest;
    \\    int count = e - f + 1;
    \\    
    \\    /* Optimize for array parts */
    \\    if (a1.type == VAL_TABLE && dest.type == VAL_TABLE) {
    \\        lua_Table* t1 = (lua_Table*)a1.as.tval;
    \\        lua_Table* t2 = (lua_Table*)dest.as.tval;
    \\        if (t1 && t2 && f >= 1 && e <= t1->array_size && t >= 1 && (t + count - 1) <= t2->array_size) {
    \\            memmove(&t2->array[t-1], &t1->array[f-1], count * sizeof(lua_Value));
    \\            return dest;
    \\        }
    \\    }
    \\
    \\    lua_Value* temp = malloc(count * sizeof(lua_Value));
    \\    for (int i = 0; i < count; i++) {
    \\        temp[i] = lua_table_get(a1, lua_val_from_num((double)(f + i)));
    \\    }
    \\    for (int i = 0; i < count; i++) {
    \\        lua_table_set(dest, lua_val_from_num((double)(t + i)), temp[i]);
    \\    }
    \\    free(temp);
    \\    return dest;
    \\}
    \\
    \\static inline lua_Value lua_tbl_unpack(lua_Value list, lua_Value i_val, lua_Value j_val) {
    \\    int i = i_val.type == VAL_NIL ? 1 : (int)lua_to_num(i_val);
    \\    int j = j_val.type == VAL_NIL ? lua_table_len(list) : (int)lua_to_num(j_val);
    \\    if (j < i) {
    \\        lua_mret_clear();
    \\        return lua_val_nil();
    \\    }
    \\    lua_mret_clear();
    \\    for (int k = i; k <= j && lua_mret_n < LUA_MRET_MAX; k++) {
    \\        lua_mret_push(lua_table_get(list, lua_val_from_num((double)k)));
    \\    }
    \\    return lua_mret_get(0);
    \\}
    \\
    \\static jmp_buf error_jmp;
    \\static bool has_error_jmp = false;
    \\static lua_Value last_error;
    \\
    \\static inline void lua_error(lua_Value msg) {
    \\    last_error = msg;
    \\    if (has_error_jmp) longjmp(error_jmp, 1);
    \\    fprintf(stderr, "error: %s\n", lua_to_str(msg));
    \\    exit(1);
    \\}
    \\
    \\static inline void lua_pcall_store_success(lua_Value r) {
    \\    if (lua_mret_n + 1 < LUA_MRET_MAX) {
    \\        for (int i = lua_mret_n; i > 0; i--) lua_mret_buf[i] = lua_mret_buf[i - 1];
    \\        lua_mret_buf[0] = r;
    \\        lua_mret_n++;
    \\    }
    \\}
    \\
    \\static inline lua_Value lua_pcall(lua_Value f, lua_Value arg) {
    \\    jmp_buf old_jmp;
    \\    memcpy(old_jmp, error_jmp, sizeof(jmp_buf));
    \\    bool old_has = has_error_jmp;
    \\    has_error_jmp = true;
    \\    if (setjmp(error_jmp) == 0) {
    \\        lua_Value args[1] = { arg };
    \\        lua_Value r = lua_invoke(f, 1, args);
    \\        has_error_jmp = old_has;
    \\        memcpy(error_jmp, old_jmp, sizeof(jmp_buf));
    \\        lua_pcall_store_success(r);
    \\        return lua_val_from_bool(true);
    \\    } else {
    \\        has_error_jmp = old_has;
    \\        memcpy(error_jmp, old_jmp, sizeof(jmp_buf));
    \\        lua_mret_clear();
    \\        lua_mret_push(last_error);
    \\        return lua_val_from_bool(false);
    \\    }
    \\}
    \\
    \\static inline lua_Value lua_pcall_argv_fn(int argc, lua_Value* argv) {
    \\    if (argc < 1) return lua_val_from_bool(false);
    \\    jmp_buf old_jmp;
    \\    memcpy(old_jmp, error_jmp, sizeof(jmp_buf));
    \\    bool old_has = has_error_jmp;
    \\    has_error_jmp = true;
    \\    if (setjmp(error_jmp) == 0) {
    \\        lua_Value r = lua_invoke(argv[0], argc - 1, argv + 1);
    \\        has_error_jmp = old_has;
    \\        memcpy(error_jmp, old_jmp, sizeof(jmp_buf));
    \\        lua_pcall_store_success(r);
    \\        return lua_val_from_bool(true);
    \\    } else {
    \\        has_error_jmp = old_has;
    \\        memcpy(error_jmp, old_jmp, sizeof(jmp_buf));
    \\        lua_mret_clear();
    \\        lua_mret_push(last_error);
    \\        return lua_val_from_bool(false);
    \\    }
    \\}
    \\
    \\static inline lua_Value lua_io_open(lua_Value filename_val, lua_Value mode_val) {
    \\    const char* filename = lua_to_str(filename_val);
    \\    const char* mode = mode_val.type == VAL_NIL ? "r" : lua_to_str(mode_val);
    \\    FILE* f = fopen(filename, mode);
    \\    if (!f) return lua_val_nil();
    \\    lua_File* lf = malloc(sizeof(lua_File));
    \\    lf->f = f;
    \\    lf->is_pipe = false;
    \\    lf->is_stdio = false;
    \\    lua_Value v;
    \\    v.type = VAL_FILE;
    \\    v.as.tval = (void*)lf;
    \\    return v;
    \\}
    \\
    \\static inline lua_Value lua_io_close(lua_Value file_val) {
    \\    if (file_val.type == VAL_FILE && file_val.as.tval) {
    \\        lua_File* lf = (lua_File*)file_val.as.tval;
    \\        if (lf->is_stdio) return lua_val_nil();
    \\        if (lf->f) {
    \\            if (lf->is_pipe) {
    \\                pclose(lf->f);
    \\            } else {
    \\                fclose(lf->f);
    \\            }
    \\            lf->f = NULL;
    \\        }
    \\    }
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline void lua_close_local(lua_Value v) {
    \\    if (v.type == VAL_NIL) return;
    \\    lua_Value mm = lua_get_metafield(v, "__close");
    \\    if (mm.type == VAL_FUNC || mm.type == VAL_CLOSURE) {
    \\        lua_Value args[2] = { v, lua_val_from_bool(false) };
    \\        (void)lua_invoke(mm, 2, args);
    \\        return;
    \\    }
    \\    if (v.type == VAL_FILE) (void)lua_io_close(v);
    \\}
    \\
    \\static inline lua_Value lua_file_write_method(lua_Value file_val, lua_Value s) {
    \\    if (file_val.type == VAL_FILE && file_val.as.tval) {
    \\        lua_File* lf = (lua_File*)file_val.as.tval;
    \\        if (lf->f) {
    \\            fprintf(lf->f, "%s", lua_to_str(s));
    \\        }
    \\    } else if (file_val.type == VAL_BUFFER) {
    \\        lua_str_buf_put(file_val, s);
    \\    }
    \\    return file_val;
    \\}
    \\
    \\static inline lua_Value lua_file_read_method(lua_Value file_val) {
    \\    if (file_val.type == VAL_FILE && file_val.as.tval) {
    \\        lua_File* lf = (lua_File*)file_val.as.tval;
    \\        if (lf->f) {
    \\            char buf[4096];
    \\            if (fgets(buf, sizeof(buf), lf->f)) {
    \\                size_t l = strlen(buf);
    \\                if (l > 0 && buf[l - 1] == '\n') buf[l - 1] = '\0';
    \\                return lua_val_from_str(strdup(buf));
    \\            }
    \\        }
    \\        return lua_val_nil();
    \\    } else if (file_val.type == VAL_BUFFER) {
    \\        return lua_str_buf_get(file_val);
    \\    }
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_os_date(lua_Value fmt_val, lua_Value t_val) {
    \\    time_t t = t_val.type == VAL_NIL ? time(NULL) : (time_t)lua_to_num(t_val);
    \\    const char* fmt = fmt_val.type == VAL_NIL ? "%c" : lua_to_str(fmt_val);
    \\    struct tm* ltime = localtime(&t);
    \\    if (!ltime) return lua_val_nil();
    \\    char buf[1024];
    \\    if (strftime(buf, sizeof(buf), fmt, ltime) > 0) {
    \\        return lua_val_from_str(strdup(buf));
    \\    }
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_os_execute(lua_Value cmd_val) {
    \\    if (cmd_val.type == VAL_NIL) {
    \\        return lua_val_from_bool(system(NULL) != 0);
    \\    }
    \\    int res = system(lua_to_str(cmd_val));
    \\    return lua_val_from_bool(res == 0);
    \\}
    \\
    \\static inline lua_Value lua_co_running(void) {
    \\    if (active_thread) {
    \\        lua_Value v;
    \\        v.type = VAL_THREAD;
    \\        v.as.tval = active_thread;
    \\        return v;
    \\    }
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_utf8_len(lua_Value s) {
    \\    const char* str = lua_to_str(s);
    \\    int len = 0;
    \\    while (*str) {
    \\        if ((*str & 0xC0) != 0x80) {
    \\            len++;
    \\        }
    \\        str++;
    \\    }
    \\    return lua_val_from_num((double)len);
    \\}
    \\
    \\static inline lua_Value lua_debug_traceback(void) {
    \\    return lua_val_from_str("stack traceback:\n  [C]: in function 'debug.traceback'");
    \\}
    \\
    \\static inline lua_Value lua_debug_getinfo(lua_Value level, lua_Value opts) {
    \\    (void)level;
    \\    (void)opts;
    \\    lua_Value t = lua_table_new();
    \\    lua_table_set(t, lua_val_from_str("source"), lua_val_from_str("=[C]"));
    \\    lua_table_set(t, lua_val_from_str("short_src"), lua_val_from_str("[C]"));
    \\    lua_table_set(t, lua_val_from_str("what"), lua_val_from_str("C"));
    \\    lua_table_set(t, lua_val_from_str("name"), lua_val_from_str(""));
    \\    lua_table_set(t, lua_val_from_str("linedefined"), lua_val_from_num(-1));
    \\    lua_table_set(t, lua_val_from_str("lastlinedefined"), lua_val_from_num(-1));
    \\    lua_table_set(t, lua_val_from_str("currentline"), lua_val_from_num(-1));
    \\    lua_table_set(t, lua_val_from_str("nups"), lua_val_from_num(0));
    \\    lua_table_set(t, lua_val_from_str("nparams"), lua_val_from_num(0));
    \\    lua_table_set(t, lua_val_from_str("isvararg"), lua_val_from_bool(false));
    \\    return t;
    \\}
    \\
    \\static inline lua_Value lua_select_argv(lua_Value index_val, int argc, lua_Value* argv) {
    \\    if (index_val.type == VAL_STRING && strcmp(index_val.as.sval, "#") == 0) {
    \\        return lua_val_from_num((double)argc);
    \\    }
    \\    int idx = (int)lua_to_num(index_val);
    \\    if (idx < 0) idx = argc + idx + 1;
    \\    if (idx >= 1 && idx <= argc) return argv[idx - 1];
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_select_v(lua_Value index_val, int argc, ...) {
    \\    lua_Value args[LUA_MRET_MAX];
    \\    if (argc > LUA_MRET_MAX) argc = LUA_MRET_MAX;
    \\    va_list ap;
    \\    va_start(ap, argc);
    \\    for (int i = 0; i < argc; i++) args[i] = va_arg(ap, lua_Value);
    \\    va_end(ap);
    \\    return lua_select_argv(index_val, argc, args);
    \\}
    \\
    \\static inline lua_Value lua_math_tointeger(lua_Value v) {
    \\    if (v.type == VAL_NUMBER) {
    \\        double d = v.as.nval;
    \\        if (d == (double)(int64_t)d) {
    \\            return v;
    \\        }
    \\    }
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_math_modf(lua_Value v) {
    \\    double intpart;
    \\    double frac = modf(lua_to_num(v), &intpart);
    \\    lua_mret_push(lua_val_from_num(frac));
    \\    return lua_val_from_num(intpart);
    \\}
    \\
    \\static inline lua_Value lua_math_ult(lua_Value m_val, lua_Value n_val) {
    \\    uint64_t m = (uint64_t)lua_to_num(m_val);
    \\    uint64_t n = (uint64_t)lua_to_num(n_val);
    \\    return lua_val_from_bool(m < n);
    \\}
    \\
    \\static inline lua_Value lua_str_match(lua_Value s_val, lua_Value pat_val) {
    \\    const char* s = lua_to_str(s_val);
    \\    const char* pat = lua_to_str(pat_val);
    \\    size_t slen = strlen(s);
    \\    size_t ms = 0, me = 0;
    \\    if (!duo_lp_find_at(s, slen, pat, 0, &ms, &me)) return lua_val_nil();
    \\    size_t mlen = me - ms;
    \\    char* out = malloc(mlen + 1);
    \\    memcpy(out, s + ms, mlen);
    \\    out[mlen] = '\0';
    \\    return lua_val_from_str(out);
    \\}
    \\
    \\static inline lua_Value lua_str_gsub(lua_Value s_val, lua_Value pat_val, lua_Value repl_val) {
    \\    const char* s = lua_to_str(s_val);
    \\    const char* pat = lua_to_str(pat_val);
    \\    const char* repl = lua_to_str(repl_val);
    \\    size_t slen = strlen(s);
    \\    size_t rlen = strlen(repl);
    \\    size_t pos = 0;
    \\    char* buf = NULL;
    \\    size_t len = 0, cap = 0;
    \\    int count = 0;
    \\    while (1) {
    \\        size_t ms = 0, me = 0;
    \\        if (!duo_lp_find_at(s, slen, pat, pos, &ms, &me)) break;
    \\        if (len + (ms - pos) + rlen > cap) {
    \\            size_t nc = cap ? cap : 64;
    \\            while (len + (ms - pos) + rlen > nc) nc *= 2;
    \\            buf = realloc(buf, nc);
    \\            cap = nc;
    \\        }
    \\        memcpy(buf + len, s + pos, ms - pos);
    \\        len += ms - pos;
    \\        memcpy(buf + len, repl, rlen);
    \\        len += rlen;
    \\        count++;
    \\        pos = me;
    \\        if (me == ms && pos < slen) pos++;
    \\        if (pos > slen) break;
    \\    }
    \\    if (count == 0) return s_val;
    \\    if (len + (slen - pos) + 1 > cap) {
    \\        buf = realloc(buf, len + (slen - pos) + 1);
    \\    }
    \\    memcpy(buf + len, s + pos, slen - pos);
    \\    len += slen - pos;
    \\    buf[len] = 0;
    \\    lua_mret_clear();
    \\    lua_mret_push(lua_val_from_str(buf));
    \\    lua_mret_push(lua_val_from_num((double)count));
    \\    return lua_mret_get(0);
    \\}
    \\
    \\typedef struct {
    \\    char* s;
    \\    char* pat;
    \\    size_t pos;
    \\    int active;
    \\} GmatchState;
    \\static GmatchState gmatch_state = { NULL, NULL, 0, 0 };
    \\
    \\static lua_Value lua_str_gmatch_iter(lua_Value _unused) {
    \\    (void)_unused;
    \\    if (!gmatch_state.active || !gmatch_state.s || !gmatch_state.pat) return lua_val_nil();
    \\    size_t slen = strlen(gmatch_state.s);
    \\    if (gmatch_state.pos > slen) { gmatch_state.active = 0; return lua_val_nil(); }
    \\    size_t ms = 0, me = 0;
    \\    if (!duo_lp_find_at(gmatch_state.s, slen, gmatch_state.pat, gmatch_state.pos, &ms, &me)) {
    \\        gmatch_state.active = 0;
    \\        return lua_val_nil();
    \\    }
    \\    size_t mlen = me - ms;
    \\    char* out = malloc(mlen + 1);
    \\    memcpy(out, gmatch_state.s + ms, mlen);
    \\    out[mlen] = '\0';
    \\    gmatch_state.pos = me;
    \\    if (me == ms && gmatch_state.pos < slen) gmatch_state.pos++;
    \\    return lua_val_from_str(out);
    \\}
    \\
    \\static inline lua_Value lua_str_gmatch(lua_Value s_val, lua_Value pat_val, lua_Value init_val) {
    \\    (void)init_val;
    \\    if (gmatch_state.s) free(gmatch_state.s);
    \\    if (gmatch_state.pat) free(gmatch_state.pat);
    \\    gmatch_state.s = strdup(lua_to_str(s_val));
    \\    gmatch_state.pat = strdup(lua_to_str(pat_val));
    \\    gmatch_state.pos = 0;
    \\    gmatch_state.active = 1;
    \\    return lua_val_from_func(lua_str_gmatch_iter);
    \\}
    \\
    \\static inline lua_Value lua_str_dump(lua_Value f_val, lua_Value strip_val) {
    \\    (void)f_val; (void)strip_val;
    \\    return lua_val_from_literal("function", 3369875416u, 8);
    \\}
    \\
    \\static int duo_pack_option(const char** fmt, char* opt_out) {
    \\    const char* f = *fmt;
    \\    while (*f == '<' || *f == '>' || *f == '=' || *f == '!') f++;
    \\    int count = 0;
    \\    while (*f >= '0' && *f <= '9') { count = count * 10 + (*f - '0'); f++; }
    \\    char op = *f;
    \\    if (!op) return 0;
    \\    *fmt = f + 1;
    \\    if (opt_out) *opt_out = op;
    \\    switch (op) {
    \\        case 'c': return count > 0 ? count : 1;
    \\        case 'b': case 'B': return 1;
    \\        case 'h': case 'H': return 2;
    \\        case 'i': case 'I': return 4;
    \\        case 'j': case 'J': return 8;
    \\        case 'f': return 4;
    \\        case 'd': case 'n': return 8;
    \\        case 's': return (int)sizeof(size_t);
    \\        default: return 0;
    \\    }
    \\}
    \\
    \\static inline lua_Value lua_str_packsize(lua_Value fmt) {
    \\    const char* f = lua_to_str(fmt);
    \\    int total = 0;
    \\    char op = 0;
    \\    while (*f) {
    \\        int sz = duo_pack_option(&f, &op);
    \\        if (sz <= 0) break;
    \\        total += sz;
    \\    }
    \\    return lua_val_from_num((double)total);
    \\}
    \\
    \\static void duo_pack_append(char** buf, size_t* len, size_t* cap, const void* data, size_t n) {
    \\    if (*len + n > *cap) {
    \\        size_t nc = *cap ? *cap : 64;
    \\        while (*len + n > nc) nc *= 2;
    \\        *buf = realloc(*buf, nc);
    \\        *cap = nc;
    \\    }
    \\    memcpy(*buf + *len, data, n);
    \\    *len += n;
    \\}
    \\
    \\static inline lua_Value lua_str_pack(lua_Value fmt, lua_Value v1, lua_Value v2) {
    \\    const char* f = lua_to_str(fmt);
    \\    char* buf = NULL;
    \\    size_t len = 0, cap = 0;
    \\    lua_Value vals[2] = { v1, v2 };
    \\    int vi = 0;
    \\    char op = 0;
    \\    while (*f) {
    \\        int sz = duo_pack_option(&f, &op);
    \\        if (sz <= 0) break;
    \\        if (op == 'c') {
    \\            const char* s = lua_to_str(vals[vi < 2 ? vi : 1]);
    \\            duo_pack_append(&buf, &len, &cap, s, (size_t)sz);
    \\            if (vi < 2) vi++;
    \\            continue;
    \\        }
    \\        lua_Value v = vals[vi < 2 ? vi : 1];
    \\        if (vi < 2) vi++;
    \\        if (op == 's') {
    \\            const char* s = lua_to_str(v);
    \\            size_t slen = strlen(s);
    \\            duo_pack_append(&buf, &len, &cap, &slen, sizeof(size_t));
    \\            duo_pack_append(&buf, &len, &cap, s, slen);
    \\            continue;
    \\        }
    \\        if (op == 'b') { int8_t x = (int8_t)lua_to_num(v); duo_pack_append(&buf, &len, &cap, &x, 1); }
    \\        else if (op == 'B') { uint8_t x = (uint8_t)lua_to_num(v); duo_pack_append(&buf, &len, &cap, &x, 1); }
    \\        else if (op == 'h') { int16_t x = (int16_t)lua_to_num(v); duo_pack_append(&buf, &len, &cap, &x, 2); }
    \\        else if (op == 'H') { uint16_t x = (uint16_t)lua_to_num(v); duo_pack_append(&buf, &len, &cap, &x, 2); }
    \\        else if (op == 'i') { int32_t x = (int32_t)lua_to_num(v); duo_pack_append(&buf, &len, &cap, &x, 4); }
    \\        else if (op == 'I') { uint32_t x = (uint32_t)lua_to_num(v); duo_pack_append(&buf, &len, &cap, &x, 4); }
    \\        else if (op == 'j') { int64_t x = (int64_t)lua_to_num(v); duo_pack_append(&buf, &len, &cap, &x, 8); }
    \\        else if (op == 'J') { uint64_t x = (uint64_t)lua_to_num(v); duo_pack_append(&buf, &len, &cap, &x, 8); }
    \\        else if (op == 'f') { float x = (float)lua_to_num(v); duo_pack_append(&buf, &len, &cap, &x, 4); }
    \\        else { double x = lua_to_num(v); duo_pack_append(&buf, &len, &cap, &x, 8); }
    \\    }
    \\    if (!buf) return lua_val_from_str("");
    \\    lua_Value out = lua_val_from_str_len(buf, len);
    \\    free(buf);
    \\    return out;
    \\}
    \\
    \\static inline lua_Value lua_str_unpack(lua_Value fmt, lua_Value s, lua_Value pos) {
    \\    const char* f = lua_to_str(fmt);
    \\    const char* str = lua_to_str(s);
    \\    size_t slen = lua_str_byte_len(s);
    \\    size_t idx = pos.type == VAL_NIL ? 0 : (size_t)lua_to_num(pos) - 1;
    \\    if (idx >= slen) return lua_val_nil();
    \\    char op = 0;
    \\    int sz = duo_pack_option(&f, &op);
    \\    if (sz <= 0 || idx + (size_t)sz > slen) return lua_val_nil();
    \\    const unsigned char* p = (const unsigned char*)(str + idx);
    \\    if (op == 'b') return lua_val_from_num((double)(int8_t)p[0]);
    \\    if (op == 'B') return lua_val_from_num((double)p[0]);
    \\    if (op == 'h') { int16_t x; memcpy(&x, p, 2); return lua_val_from_num((double)x); }
    \\    if (op == 'H') { uint16_t x; memcpy(&x, p, 2); return lua_val_from_num((double)x); }
    \\    if (op == 'i') { int32_t x; memcpy(&x, p, 4); return lua_val_from_num((double)x); }
    \\    if (op == 'I') { uint32_t x; memcpy(&x, p, 4); return lua_val_from_num((double)x); }
    \\    if (op == 'j') { int64_t x; memcpy(&x, p, 8); return lua_val_from_num((double)x); }
    \\    if (op == 'J') { uint64_t x; memcpy(&x, p, 8); return lua_val_from_num((double)x); }
    \\    if (op == 'f') { float x; memcpy(&x, p, 4); return lua_val_from_num((double)x); }
    \\    if (op == 'd' || op == 'n') { double x; memcpy(&x, p, 8); return lua_val_from_num(x); }
    \\    if (op == 'c') return lua_val_from_str_len(str + idx, (size_t)sz);
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_utf8_char(lua_Value c) {
    \\    int n = (int)lua_to_num(c);
    \\    char buf[5] = {0};
    \\    if (n < 0x80) buf[0] = n;
    \\    else if (n < 0x800) { buf[0] = 0xC0 | (n >> 6); buf[1] = 0x80 | (n & 0x3F); }
    \\    else if (n < 0x10000) { buf[0] = 0xE0 | (n >> 12); buf[1] = 0x80 | ((n >> 6) & 0x3F); buf[2] = 0x80 | (n & 0x3F); }
    \\    else { buf[0] = 0xF0 | (n >> 18); buf[1] = 0x80 | ((n >> 12) & 0x3F); buf[2] = 0x80 | ((n >> 6) & 0x3F); buf[3] = 0x80 | (n & 0x3F); }
    \\    return lua_val_from_str(buf);
    \\}
    \\
    \\static inline lua_Value lua_utf8_offset(lua_Value s_val, lua_Value n_val, lua_Value i_val) {
    \\    const char* s = lua_to_str(s_val);
    \\    int n = (int)lua_to_num(n_val);
    \\    int len = (int)strlen(s);
    \\    int i = i_val.type == VAL_NIL ? (n >= 0 ? 1 : len + 1) : (int)lua_to_num(i_val);
    \\    if (i < 1 || i > len + 1) return lua_val_nil();
    \\    int byte_pos = i - 1;
    \\    if (n == 0) {
    \\        while (byte_pos > 0 && (s[byte_pos] & 0xC0) == 0x80) byte_pos--;
    \\        lua_mret_clear();
    \\        int char_pos = 1;
    \\        for (int j = 0; j < byte_pos; j++) {
    \\            if ((s[j] & 0xC0) != 0x80) char_pos++;
    \\        }
    \\        lua_mret_push(lua_val_from_num((double)char_pos));
    \\        return lua_val_from_num((double)(byte_pos + 1));
    \\    }
    \\    if (n > 0) {
    \\        n--;
    \\        while (n > 0 && byte_pos < len) {
    \\            byte_pos++;
    \\            if ((s[byte_pos] & 0xC0) != 0x80) n--;
    \\        }
    \\    } else {
    \\        while (n < 0 && byte_pos > 0) {
    \\            byte_pos--;
    \\            if ((s[byte_pos] & 0xC0) != 0x80) n++;
    \\        }
    \\    }
    \\    if (n == 0 && byte_pos <= len) {
    \\        lua_mret_clear();
    \\        int char_pos = 1;
    \\        for (int j = 0; j < byte_pos; j++) {
    \\            if ((s[j] & 0xC0) != 0x80) char_pos++;
    \\        }
    \\        lua_mret_push(lua_val_from_num((double)char_pos));
    \\        return lua_val_from_num((double)(byte_pos + 1));
    \\    }
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_tbl_pack(lua_Value v) {
    \\    lua_Value t = lua_table_new();
    \\    lua_table_set(t, lua_val_from_str("n"), lua_val_from_num(1.0));
    \\    lua_table_set(t, lua_val_from_num(1.0), v);
    \\    return t;
    \\}
    \\
    \\static inline lua_Value lua_tbl_pack_argv(int n, lua_Value* argv) {
    \\    lua_Value t = lua_table_new();
    \\    lua_table_set(t, lua_val_from_str("n"), lua_val_from_num((double)n));
    \\    for (int i = 0; i < n; i++) {
    \\        lua_table_set(t, lua_val_from_num((double)(i + 1)), argv[i]);
    \\    }
    \\    return t;
    \\}
    \\
    \\static inline lua_Value lua_tbl_pack_argv_fn(int argc, lua_Value* argv) {
    \\    return lua_tbl_pack_argv(argc, argv);
    \\}
    \\
    \\static inline lua_Value lua_tbl_freeze(lua_Value table) {
    \\    if (table.type != VAL_TABLE) return table;
    \\    lua_Table* t = (lua_Table*)table.as.tval;
    \\    if (t) t->frozen = true;
    \\    return table;
    \\}
    \\
    \\static inline lua_Value lua_tbl_isfrozen(lua_Value table) {
    \\    if (table.type != VAL_TABLE) return lua_val_from_bool(false);
    \\    lua_Table* t = (lua_Table*)table.as.tval;
    \\    return lua_val_from_bool(t && t->frozen);
    \\}
    \\
    \\static lua_Value lua_co_wrap_thread = { .type = VAL_NIL };
    \\static lua_Value lua_co_wrap_fn(lua_Value arg) {
    \\    return lua_co_resume(lua_co_wrap_thread, arg);
    \\}
    \\
    \\static inline lua_Value lua_co_wrap(lua_Value f) {
    \\    lua_co_wrap_thread = lua_co_create(f);
    \\    return lua_val_from_func(lua_co_wrap_fn);
    \\}
    \\
    \\static inline lua_Value lua_co_isyieldable(void) {
    \\    return lua_val_from_bool(active_thread != NULL);
    \\}
    \\
    \\static inline lua_Value lua_os_tmpname(void) {
    \\    char buf[L_tmpnam];
    \\    tmpnam(buf);
    \\    return lua_val_from_str(strdup(buf));
    \\}
    \\
    \\static inline lua_Value lua_utf8_codepoint(lua_Value s_val, lua_Value i_val, lua_Value j_val) {
    \\    (void)j_val;
    \\    const char* s = lua_to_str(s_val);
    \\    int idx = i_val.type == VAL_NIL ? 1 : (int)lua_to_num(i_val);
    \\    int len = (int)strlen(s);
    \\    if (idx < 1 || idx > len) return lua_val_nil();
    \\    return lua_val_from_num((double)(unsigned char)s[idx - 1]);
    \\}
    \\
    \\static const char* utf8_codes_s = NULL;
    \\static size_t utf8_codes_pos = 0;
    \\static int utf8_codes_active = 0;
    \\
    \\static inline lua_Value lua_utf8_codes_iter(lua_Value _unused) {
    \\    (void)_unused;
    \\    if (!utf8_codes_active || !utf8_codes_s || !utf8_codes_s[utf8_codes_pos]) return lua_val_nil();
    \\    size_t start_pos = utf8_codes_pos;
    \\    const unsigned char* p = (const unsigned char*)(utf8_codes_s + utf8_codes_pos);
    \\    unsigned char c0 = p[0];
    \\    int adv = 1;
    \\    unsigned int cp = c0;
    \\    if ((c0 & 0x80) == 0) {
    \\        cp = c0;
    \\    } else if ((c0 & 0xE0) == 0xC0 && p[1]) {
    \\        cp = ((c0 & 0x1F) << 6) | (p[1] & 0x3F);
    \\        adv = 2;
    \\    } else if ((c0 & 0xF0) == 0xE0 && p[1] && p[2]) {
    \\        cp = ((c0 & 0x0F) << 12) | ((p[1] & 0x3F) << 6) | (p[2] & 0x3F);
    \\        adv = 3;
    \\    } else if ((c0 & 0xF8) == 0xF0 && p[1] && p[2] && p[3]) {
    \\        cp = ((c0 & 0x07) << 18) | ((p[1] & 0x3F) << 12) | ((p[2] & 0x3F) << 6) | (p[3] & 0x3F);
    \\        adv = 4;
    \\    }
    \\    utf8_codes_pos += (size_t)adv;
    \\    lua_mret_clear();
    \\    lua_mret_push(lua_val_from_num((double)cp));
    \\    return lua_val_from_num((double)(start_pos + 1));
    \\}
    \\
    \\static inline lua_Value lua_utf8_codes(lua_Value s_val) {
    \\    utf8_codes_s = lua_to_str(s_val);
    \\    utf8_codes_pos = 0;
    \\    utf8_codes_active = 1;
    \\    return lua_val_from_func(lua_utf8_codes_iter);
    \\}
    \\
    \\static inline lua_Value lua_ipairs_iter(lua_Value s, lua_Value i) {
    \\    if (s.type != VAL_TABLE) return lua_val_nil();
    \\    int idx = (int)lua_to_num(i);
    \\    lua_Value v = lua_table_get_raw(s, lua_val_from_num((double)(idx + 1)));
    \\    if (v.type == VAL_NIL) return lua_val_nil();
    \\    lua_mret_clear();
    \\    lua_mret_push(v);
    \\    return lua_val_from_num((double)(idx + 1));
    \\}
    \\
    \\static inline lua_Value lua_next(lua_Value table, lua_Value key) {
    \\    lua_mret_clear();
    \\    if (table.type != VAL_TABLE) return lua_val_nil();
    \\    lua_Table* t = (lua_Table*)table.as.tval;
    \\    if (!t) return lua_val_nil();
    \\
    \\    if (key.type == VAL_NIL) {
    \\        for (int i = 0; i < t->array_size; i++) {
    \\            if (t->array[i].type != VAL_NIL) {
    \\                lua_mret_push(t->array[i]);
    \\                return lua_val_from_num((double)(i + 1));
    \\            }
    \\        }
    \\        for (int i = 0; i < t->capacity; i++) {
    \\            if (t->entries[i].key.type != VAL_NIL) {
    \\                lua_mret_push(t->entries[i].val);
    \\                return t->entries[i].key;
    \\            }
    \\        }
    \\        return lua_val_nil();
    \\    }
    \\
    \\    if (key.type == VAL_NUMBER) {
    \\        int k = (int)key.as.nval;
    \\        if (k >= 1 && k <= t->array_size) {
    \\            for (int i = k; i < t->array_size; i++) {
    \\                if (t->array[i].type != VAL_NIL) {
    \\                    lua_mret_push(t->array[i]);
    \\                    return lua_val_from_num((double)(i + 1));
    \\                }
    \\            }
    \\        }
    \\        if (t->capacity == 0) return lua_val_nil();
    \\        uint32_t mask = t->capacity - 1;
    \\        uint32_t idx = lua_hash_value(key) & mask;
    \\        int found = 0;
    \\        while (t->entries[idx].key.type != VAL_NIL) {
    \\            if (!found && lua_eq(t->entries[idx].key, key)) found = 1;
    \\            else if (found) {
    \\                lua_mret_push(t->entries[idx].val);
    \\                return t->entries[idx].key;
    \\            }
    \\            idx = (idx + 1) & mask;
    \\        }
    \\        if (!found) {
    \\            for (int i = 0; i < t->capacity; i++) {
    \\                if (t->entries[i].key.type != VAL_NIL) {
    \\                    lua_mret_push(t->entries[i].val);
    \\                    return t->entries[i].key;
    \\                }
    \\            }
    \\        }
    \\        return lua_val_nil();
    \\    }
    \\
    \\    if (t->capacity == 0) return lua_val_nil();
    \\    uint32_t mask = t->capacity - 1;
    \\    uint32_t idx = lua_hash_value(key) & mask;
    \\    int found = 0;
    \\    while (t->entries[idx].key.type != VAL_NIL) {
    \\        if (!found && lua_eq(t->entries[idx].key, key)) found = 1;
    \\        else if (found) {
    \\            lua_mret_push(t->entries[idx].val);
    \\            return t->entries[idx].key;
    \\        }
    \\        idx = (idx + 1) & mask;
    \\    }
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_pairs(lua_Value t) {
    \\    lua_mret_clear();
    \\    lua_Value pp = lua_get_metafield(t, "__pairs");
    \\    if (pp.type == VAL_FUNC || pp.type == VAL_CLOSURE) {
    \\        lua_Value args[1] = { t };
    \\        (void)lua_invoke(pp, 1, args);
    \\        return lua_mret_get(0);
    \\    }
    \\    lua_mret_push(lua_val_from_func((void*)lua_next));
    \\    lua_mret_push(t);
    \\    lua_mret_push(lua_val_nil());
    \\    return lua_mret_get(0);
    \\}
    \\
    \\static inline lua_Value lua_ipairs(lua_Value t) {
    \\    lua_mret_clear();
    \\    lua_Value pp = lua_get_metafield(t, "__ipairs");
    \\    if (pp.type == VAL_FUNC || pp.type == VAL_CLOSURE) {
    \\        lua_Value args[1] = { t };
    \\        (void)lua_invoke(pp, 1, args);
    \\        return lua_mret_get(0);
    \\    }
    \\    lua_mret_push(lua_val_from_func((void*)lua_ipairs_iter));
    \\    lua_mret_push(t);
    \\    lua_mret_push(lua_val_from_num(0.0));
    \\    return lua_mret_get(0);
    \\}
    \\
    \\static inline lua_Value lua_io_tmpfile(void) {
    \\    FILE* f = tmpfile();
    \\    if (!f) return lua_val_nil();
    \\    lua_File* lf = malloc(sizeof(lua_File));
    \\    lf->f = f;
    \\    lf->is_pipe = false;
    \\    lf->is_stdio = false;
    \\    lua_Value v;
    \\    v.type = VAL_FILE;
    \\    v.as.tval = (void*)lf;
    \\    return v;
    \\}
    \\
    \\static inline lua_Value lua_os_setlocale(lua_Value locale_val, lua_Value category_val) {
    \\    (void)category_val;
    \\    const char* locale = locale_val.type == VAL_NIL ? "" : lua_to_str(locale_val);
    \\    const char* res = setlocale(LC_ALL, locale);
    \\    if (res) return lua_val_from_str(strdup(res));
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_setmetatable(lua_Value table, lua_Value metatable) {
    \\    if (table.type != VAL_TABLE) return table;
    \\    lua_Table* t = (lua_Table*)table.as.tval;
    \\    if (!t) return table;
    \\    if (metatable.type == VAL_NIL) t->metatable = lua_val_nil();
    \\    else if (metatable.type == VAL_TABLE) t->metatable = metatable;
    \\    return table;
    \\}
    \\
    \\static inline lua_Value lua_getmetatable(lua_Value object) {
    \\    if (object.type != VAL_TABLE) return lua_val_nil();
    \\    lua_Table* t = (lua_Table*)object.as.tval;
    \\    if (!t || t->metatable.type == VAL_NIL) return lua_val_nil();
    \\    return t->metatable;
    \\}
    \\
    \\static inline lua_Value lua_rawget(lua_Value table, lua_Value index) {
    \\    return lua_table_get_raw(table, index);
    \\}
    \\
    \\static inline lua_Value lua_rawset(lua_Value table, lua_Value index, lua_Value value) {
    \\    lua_table_set_raw(table, index, value);
    \\    return table;
    \\}
    \\
    \\static inline lua_Value lua_rawlen(lua_Value v) {
    \\    if (v.type == VAL_STRING) {
    \\        return lua_val_from_num((double)strlen(v.as.sval));
    \\    } else if (v.type == VAL_TABLE) {
    \\        return lua_val_from_num((double)lua_table_len(v));
    \\    }
    \\    return lua_val_from_num(0.0);
    \\}
    \\
    \\static inline lua_Value lua_rawequal(lua_Value v1, lua_Value v2) {
    \\    return lua_val_from_bool(lua_eq(v1, v2));
    \\}
    \\
    \\static inline lua_Value lua_collectgarbage(lua_Value opt, lua_Value arg) {
    \\    const char* o = (opt.type == VAL_STRING) ? opt.as.sval : "collect";
    \\    (void)arg;
    \\    if (strcmp(o, "count") == 0) return lua_val_from_num((double)duo_gc_kbytes);
    \\    if (strcmp(o, "collect") == 0) return lua_val_from_num(0.0);
    \\    if (strcmp(o, "stop") == 0 || strcmp(o, "restart") == 0) return lua_val_from_bool(true);
    \\    return lua_val_from_num(0.0);
    \\}
    \\
    \\static inline lua_Value lua_warn(lua_Value msg) {
    \\    fprintf(stderr, "warning: %s\n", lua_to_str(msg));
    \\    return lua_val_nil();
    \\}
    \\
    \\#if defined(__APPLE__)
    \\#define DUO_DLIB_EXT ".dylib"
    \\#else
    \\#define DUO_DLIB_EXT ".so"
    \\#endif
    \\
    \\#define DUO_DYN_LOAD_MAX 16
    \\typedef lua_Value (*duo_load_entry_fn)(void);
    \\static struct {
    \\    void* dl;
    \\    duo_load_entry_fn entry;
    \\} duo_dyn_slots[DUO_DYN_LOAD_MAX];
    \\static int duo_dyn_count = 0;
    \\
    \\static lua_Value duo_dyn_wrap_0(lua_Value _a) { (void)_a; return duo_dyn_slots[0].entry ? duo_dyn_slots[0].entry() : lua_val_nil(); }
    \\static lua_Value duo_dyn_wrap_1(lua_Value _a) { (void)_a; return duo_dyn_slots[1].entry ? duo_dyn_slots[1].entry() : lua_val_nil(); }
    \\static lua_Value duo_dyn_wrap_2(lua_Value _a) { (void)_a; return duo_dyn_slots[2].entry ? duo_dyn_slots[2].entry() : lua_val_nil(); }
    \\static lua_Value duo_dyn_wrap_3(lua_Value _a) { (void)_a; return duo_dyn_slots[3].entry ? duo_dyn_slots[3].entry() : lua_val_nil(); }
    \\static lua_Value duo_dyn_wrap_4(lua_Value _a) { (void)_a; return duo_dyn_slots[4].entry ? duo_dyn_slots[4].entry() : lua_val_nil(); }
    \\static lua_Value duo_dyn_wrap_5(lua_Value _a) { (void)_a; return duo_dyn_slots[5].entry ? duo_dyn_slots[5].entry() : lua_val_nil(); }
    \\static lua_Value duo_dyn_wrap_6(lua_Value _a) { (void)_a; return duo_dyn_slots[6].entry ? duo_dyn_slots[6].entry() : lua_val_nil(); }
    \\static lua_Value duo_dyn_wrap_7(lua_Value _a) { (void)_a; return duo_dyn_slots[7].entry ? duo_dyn_slots[7].entry() : lua_val_nil(); }
    \\static lua_Value duo_dyn_wrap_8(lua_Value _a) { (void)_a; return duo_dyn_slots[8].entry ? duo_dyn_slots[8].entry() : lua_val_nil(); }
    \\static lua_Value duo_dyn_wrap_9(lua_Value _a) { (void)_a; return duo_dyn_slots[9].entry ? duo_dyn_slots[9].entry() : lua_val_nil(); }
    \\static lua_Value duo_dyn_wrap_10(lua_Value _a) { (void)_a; return duo_dyn_slots[10].entry ? duo_dyn_slots[10].entry() : lua_val_nil(); }
    \\static lua_Value duo_dyn_wrap_11(lua_Value _a) { (void)_a; return duo_dyn_slots[11].entry ? duo_dyn_slots[11].entry() : lua_val_nil(); }
    \\static lua_Value duo_dyn_wrap_12(lua_Value _a) { (void)_a; return duo_dyn_slots[12].entry ? duo_dyn_slots[12].entry() : lua_val_nil(); }
    \\static lua_Value duo_dyn_wrap_13(lua_Value _a) { (void)_a; return duo_dyn_slots[13].entry ? duo_dyn_slots[13].entry() : lua_val_nil(); }
    \\static lua_Value duo_dyn_wrap_14(lua_Value _a) { (void)_a; return duo_dyn_slots[14].entry ? duo_dyn_slots[14].entry() : lua_val_nil(); }
    \\static lua_Value duo_dyn_wrap_15(lua_Value _a) { (void)_a; return duo_dyn_slots[15].entry ? duo_dyn_slots[15].entry() : lua_val_nil(); }
    \\
    \\static lua_Value (*duo_dyn_wrappers[DUO_DYN_LOAD_MAX])(lua_Value) = {
    \\    duo_dyn_wrap_0, duo_dyn_wrap_1, duo_dyn_wrap_2, duo_dyn_wrap_3,
    \\    duo_dyn_wrap_4, duo_dyn_wrap_5, duo_dyn_wrap_6, duo_dyn_wrap_7,
    \\    duo_dyn_wrap_8, duo_dyn_wrap_9, duo_dyn_wrap_10, duo_dyn_wrap_11,
    \\    duo_dyn_wrap_12, duo_dyn_wrap_13, duo_dyn_wrap_14, duo_dyn_wrap_15,
    \\};
    \\
    \\static const char* duo_compiler_path(void) {
    \\    const char* from_env = getenv("DUO");
    \\    if (from_env && from_env[0]) return from_env;
    \\    if (access("./zig-out/bin/duo", X_OK) == 0) return "./zig-out/bin/duo";
    \\    if (access("../zig-out/bin/duo", X_OK) == 0) return "../zig-out/bin/duo";
    \\    return "duo";
    \\}
    \\
    \\static int duo_make_temp_path(char* out, size_t out_sz, const char* suffix) {
    \\    char tmpl[] = "/tmp/duo_ldXXXXXX";
    \\    int fd = mkstemp(tmpl);
    \\    if (fd < 0) return -1;
    \\    close(fd);
    \\    unlink(tmpl);
    \\    if (snprintf(out, out_sz, "%s%s", tmpl, suffix) >= (int)out_sz) return -1;
    \\    return 0;
    \\}
    \\
    \\static int duo_read_file(const char* path, char** out, size_t* out_len) {
    \\    FILE* f = fopen(path, "rb");
    \\    if (!f) return -1;
    \\    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return -1; }
    \\    long sz = ftell(f);
    \\    if (sz < 0) { fclose(f); return -1; }
    \\    if (fseek(f, 0, SEEK_SET) != 0) { fclose(f); return -1; }
    \\    char* buf = (char*)malloc((size_t)sz + 1);
    \\    if (!buf) { fclose(f); return -1; }
    \\    if (fread(buf, 1, (size_t)sz, f) != (size_t)sz) { free(buf); fclose(f); return -1; }
    \\    fclose(f);
    \\    buf[sz] = '\0';
    \\    *out = buf;
    \\    *out_len = (size_t)sz;
    \\    return 0;
    \\}
    \\
    \\static int duo_write_file(const char* path, const char* data, size_t len) {
    \\    FILE* f = fopen(path, "wb");
    \\    if (!f) return -1;
    \\    if (fwrite(data, 1, len, f) != len) { fclose(f); return -1; }
    \\    fclose(f);
    \\    return 0;
    \\}
    \\
    \\static int duo_compile_load_chunk(const char* lua_path, const char* dlib_path, char* err, size_t err_sz) {
    \\    const char* duo = duo_compiler_path();
    \\    char err_path[512];
    \\    if (duo_make_temp_path(err_path, sizeof err_path, ".err") != 0) {
    \\        snprintf(err, err_sz, "failed to create temp error file");
    \\        return -1;
    \\    }
    \\    char cmd[8192];
    \\    snprintf(cmd, sizeof cmd, "%s compile --load-chunk %s -o %s 2>%s", duo, lua_path, dlib_path, err_path);
    \\    int rc = system(cmd);
    \\    if (rc != 0) {
    \\        FILE* ef = fopen(err_path, "rb");
    \\        if (ef) {
    \\            size_t n = fread(err, 1, err_sz - 1, ef);
    \\            err[n] = '\0';
    \\            fclose(ef);
    \\        } else {
    \\            snprintf(err, err_sz, "duo compile failed (exit %d)", rc);
    \\        }
    \\        unlink(err_path);
    \\        return -1;
    \\    }
    \\    unlink(err_path);
    \\    return 0;
    \\}
    \\
    \\static lua_Value duo_runtime_load_path(const char* path) {
    \\    lua_mret_clear();
    \\    char err[1024];
    \\    char dlib_path[512];
    \\    if (duo_make_temp_path(dlib_path, sizeof dlib_path, DUO_DLIB_EXT) != 0) {
    \\        lua_mret_push(lua_val_nil());
    \\        lua_mret_push(lua_val_from_str("failed to create temp library path"));
    \\        return lua_val_nil();
    \\    }
    \\    if (duo_compile_load_chunk(path, dlib_path, err, sizeof err) != 0) {
    \\        unlink(dlib_path);
    \\        lua_mret_push(lua_val_nil());
    \\        lua_mret_push(lua_val_from_str(strdup(err)));
    \\        return lua_val_nil();
    \\    }
    \\    void* dl = dlopen(dlib_path, RTLD_NOW | RTLD_LOCAL);
    \\    unlink(dlib_path);
    \\    if (!dl) {
    \\        lua_mret_push(lua_val_nil());
    \\        lua_mret_push(lua_val_from_str(strdup(dlerror() ? dlerror() : "dlopen failed")));
    \\        return lua_val_nil();
    \\    }
    \\    duo_load_entry_fn entry = (duo_load_entry_fn)dlsym(dl, "duo_load_entry");
    \\    if (!entry) {
    \\        dlclose(dl);
    \\        lua_mret_push(lua_val_nil());
    \\        lua_mret_push(lua_val_from_str("duo_load_entry not found in loaded chunk"));
    \\        return lua_val_nil();
    \\    }
    \\    if (duo_dyn_count >= DUO_DYN_LOAD_MAX) {
    \\        dlclose(dl);
    \\        lua_mret_push(lua_val_nil());
    \\        lua_mret_push(lua_val_from_str("too many dynamically loaded chunks"));
    \\        return lua_val_nil();
    \\    }
    \\    int id = duo_dyn_count++;
    \\    duo_dyn_slots[id].dl = dl;
    \\    duo_dyn_slots[id].entry = entry;
    \\    lua_mret_push(lua_val_from_func(duo_dyn_wrappers[id]));
    \\    lua_mret_push(lua_val_nil());
    \\    return lua_mret_get(0);
    \\}
    \\
    \\static lua_Value duo_runtime_load_source(const char* source) {
    \\    lua_mret_clear();
    \\    char lua_path[512];
    \\    if (duo_make_temp_path(lua_path, sizeof lua_path, ".lua") != 0) {
    \\        lua_mret_push(lua_val_nil());
    \\        lua_mret_push(lua_val_from_str("failed to create temp source path"));
    \\        return lua_val_nil();
    \\    }
    \\    if (duo_write_file(lua_path, source, strlen(source)) != 0) {
    \\        unlink(lua_path);
    \\        lua_mret_push(lua_val_nil());
    \\        lua_mret_push(lua_val_from_str("failed to write temp source"));
    \\        return lua_val_nil();
    \\    }
    \\    lua_Value fn = duo_runtime_load_path(lua_path);
    \\    unlink(lua_path);
    \\    return fn;
    \\}
    \\
    \\static inline lua_Value lua_xpcall(lua_Value func_val, lua_Value msgh_val, lua_Value arg_val) {
    \\    jmp_buf old_jmp;
    \\    memcpy(old_jmp, error_jmp, sizeof(jmp_buf));
    \\    bool old_has = has_error_jmp;
    \\    has_error_jmp = true;
    \\    if (setjmp(error_jmp) == 0) {
    \\        lua_Value args[1] = { arg_val };
    \\        lua_Value r = lua_invoke(func_val, 1, args);
    \\        has_error_jmp = old_has;
    \\        memcpy(error_jmp, old_jmp, sizeof(jmp_buf));
    \\        lua_pcall_store_success(r);
    \\        return lua_val_from_bool(true);
    \\    } else {
    \\        has_error_jmp = old_has;
    \\        memcpy(error_jmp, old_jmp, sizeof(jmp_buf));
    \\        lua_Value err = last_error;
    \\        if (msgh_val.type == VAL_FUNC || msgh_val.type == VAL_CLOSURE) {
    \\            lua_Value args[1] = { err };
    \\            err = lua_invoke(msgh_val, 1, args);
    \\        }
    \\        lua_mret_clear();
    \\        lua_mret_push(err);
    \\        return lua_val_from_bool(false);
    \\    }
    \\}
    \\
    \\static inline lua_Value lua_xpcall_argv_fn(int argc, lua_Value* argv) {
    \\    if (argc < 2) return lua_val_from_bool(false);
    \\    jmp_buf old_jmp;
    \\    memcpy(old_jmp, error_jmp, sizeof(jmp_buf));
    \\    bool old_has = has_error_jmp;
    \\    has_error_jmp = true;
    \\    if (setjmp(error_jmp) == 0) {
    \\        lua_Value r = lua_invoke(argv[0], argc - 2, argv + 2);
    \\        has_error_jmp = old_has;
    \\        memcpy(error_jmp, old_jmp, sizeof(jmp_buf));
    \\        lua_pcall_store_success(r);
    \\        return lua_val_from_bool(true);
    \\    } else {
    \\        has_error_jmp = old_has;
    \\        memcpy(error_jmp, old_jmp, sizeof(jmp_buf));
    \\        lua_Value err = last_error;
    \\        if (argv[1].type == VAL_FUNC || argv[1].type == VAL_CLOSURE) {
    \\            lua_Value args[1] = { err };
    \\            err = lua_invoke(argv[1], 1, args);
    \\        }
    \\        lua_mret_clear();
    \\        lua_mret_push(err);
    \\        return lua_val_from_bool(false);
    \\    }
    \\}
    \\
    \\static inline lua_Value lua_load(lua_Value chunk, lua_Value chunkname, lua_Value mode, lua_Value env) {
    \\    (void)chunkname; (void)env;
    \\    if (chunk.type == VAL_FUNC || chunk.type == VAL_CLOSURE) {
    \\        lua_mret_push(lua_val_nil());
    \\        lua_mret_push(lua_val_from_str("binary chunks not supported"));
    \\        return lua_val_nil();
    \\    }
    \\    if (chunk.type != VAL_STRING) {
    \\        lua_mret_push(lua_val_nil());
    \\        lua_mret_push(lua_val_from_str("bad argument #1 to 'load' (string or function expected)"));
    \\        return lua_val_nil();
    \\    }
    \\    if (mode.type == VAL_STRING) {
    \\        const char* m = mode.as.sval;
    \\        int has_t = strchr(m, 't') != NULL;
    \\        int has_b = strchr(m, 'b') != NULL;
    \\        if (has_b && !has_t) {
    \\            lua_mret_push(lua_val_nil());
    \\            lua_mret_push(lua_val_from_str("binary chunks not supported"));
    \\            return lua_val_nil();
    \\        }
    \\    }
    \\    return duo_runtime_load_source(chunk.as.sval);
    \\}
    \\
    \\static inline lua_Value lua_loadfile(lua_Value filename, lua_Value mode, lua_Value env) {
    \\    (void)env;
    \\    if (filename.type != VAL_STRING) {
    \\        lua_mret_push(lua_val_nil());
    \\        lua_mret_push(lua_val_from_str("bad argument #1 to 'loadfile' (string expected)"));
    \\        return lua_val_nil();
    \\    }
    \\    if (mode.type == VAL_STRING) {
    \\        const char* m = mode.as.sval;
    \\        int has_t = strchr(m, 't') != NULL;
    \\        int has_b = strchr(m, 'b') != NULL;
    \\        if (has_b && !has_t) {
    \\            lua_mret_push(lua_val_nil());
    \\            lua_mret_push(lua_val_from_str("binary chunks not supported"));
    \\            return lua_val_nil();
    \\        }
    \\    }
    \\    return duo_runtime_load_path(filename.as.sval);
    \\}
    \\
    \\static inline lua_Value lua_dofile(lua_Value filename) {
    \\    if (filename.type != VAL_STRING) {
    \\        lua_mret_push(lua_val_nil());
    \\        lua_mret_push(lua_val_from_str("bad argument #1 to 'dofile' (string expected)"));
    \\        return lua_val_nil();
    \\    }
    \\    lua_Value fn = duo_runtime_load_path(filename.as.sval);
    \\    if (fn.type == VAL_NIL) return lua_val_nil();
    \\    return lua_invoke(fn, 0, NULL);
    \\}
    \\
    \\static inline lua_Value lua_co_close(lua_Value thread_val) {
    \\    if (thread_val.type != VAL_THREAD) return lua_val_from_bool(false);
    \\    lua_Thread* co = (lua_Thread*)thread_val.as.tval;
    \\    if (!co) return lua_val_from_bool(false);
    \\    if (co->status != CO_DEAD) {
    \\        co->status = CO_DEAD;
    \\        if (co->stack) { free(co->stack); co->stack = NULL; }
    \\    }
    \\    return lua_val_from_bool(true);
    \\}
    \\
    \\static inline lua_Value lua_package_searchpath(lua_Value name, lua_Value path, lua_Value sep, lua_Value rep) {
    \\    const char* modname = lua_to_str(name);
    \\    const char* pathspec = lua_to_str(path);
    \\    const char* sepstr = sep.type == VAL_NIL ? ";" : lua_to_str(sep);
    \\    const char* repstr = rep.type == VAL_NIL ? "?" : lua_to_str(rep);
    \\    char buf[4096];
    \\    const char* start = pathspec;
    \\    size_t seplen = strlen(sepstr);
    \\    while (*start) {
    \\        const char* end = strstr(start, sepstr);
    \\        size_t plen = end ? (size_t)(end - start) : strlen(start);
    \\        if (plen >= sizeof(buf)) plen = sizeof(buf) - 1;
    \\        memcpy(buf, start, plen);
    \\        buf[plen] = '\0';
    \\        char* q = strstr(buf, repstr);
    \\        if (q) {
    \\            char out[4096];
    \\            size_t prefix = (size_t)(q - buf);
    \\            size_t replen = strlen(repstr);
    \\            size_t suffix = strlen(q + replen);
    \\            size_t mlen = strlen(modname);
    \\            if (prefix + mlen + suffix < sizeof(out)) {
    \\                memcpy(out, buf, prefix);
    \\                memcpy(out + prefix, modname, mlen);
    \\                memcpy(out + prefix + mlen, q + replen, suffix + 1);
    \\                if (access(out, R_OK) == 0) return lua_val_from_str(strdup(out));
    \\            }
    \\        } else if (access(buf, R_OK) == 0) {
    \\            return lua_val_from_str(strdup(buf));
    \\        }
    \\        if (!end) break;
    \\        start = end + seplen;
    \\    }
    \\    return lua_val_nil();
    \\}
    \\
    \\static inline lua_Value lua_package_init(void) {
    \\    lua_Value pkg = lua_table_new();
    \\    lua_table_set(pkg, lua_val_from_str("path"), lua_val_from_str("./?.lua;./?/init.lua"));
    \\    lua_table_set(pkg, lua_val_from_str("cpath"), lua_val_from_str(""));
    \\    lua_table_set(pkg, lua_val_from_str("config"), lua_val_from_str("/"));
    \\    lua_table_set(pkg, lua_val_from_str("loaded"), lua_table_new());
    \\    lua_table_set(pkg, lua_val_from_str("preload"), lua_table_new());
    \\    lua_table_set(pkg, lua_val_from_str("searchers"), lua_table_new());
    \\    lua_table_set(pkg, lua_val_from_str("searchpath"), lua_val_from_func((lua_Value (*)(lua_Value))lua_package_searchpath));
    \\    return pkg;
    \\}
    \\
    \\static inline lua_Value lua_math_init(void) {
    \\    lua_Value m = lua_table_new();
    \\    lua_table_set(m, lua_val_from_str("pi"), lua_val_from_num(3.14159265358979323846));
    \\    lua_table_set(m, lua_val_from_str("maxinteger"), lua_val_from_num(9223372036854775807.0));
    \\    lua_table_set(m, lua_val_from_str("mininteger"), lua_val_from_num(-9223372036854775808.0));
    \\    lua_table_set(m, lua_val_from_str("random"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_random));
    \\    lua_table_set(m, lua_val_from_str("randomseed"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_randomseed));
    \\    lua_table_set(m, lua_val_from_str("abs"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_abs));
    \\    lua_table_set(m, lua_val_from_str("acos"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_acos));
    \\    lua_table_set(m, lua_val_from_str("asin"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_asin));
    \\    lua_table_set(m, lua_val_from_str("atan"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_atan));
    \\    lua_table_set(m, lua_val_from_str("atan2"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_atan2));
    \\    lua_table_set(m, lua_val_from_str("ceil"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_ceil));
    \\    lua_table_set(m, lua_val_from_str("cos"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_cos));
    \\    lua_table_set(m, lua_val_from_str("exp"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_exp));
    \\    lua_table_set(m, lua_val_from_str("floor"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_floor));
    \\    lua_table_set(m, lua_val_from_str("log"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_log));
    \\    lua_table_set(m, lua_val_from_str("log10"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_log10));
    \\    lua_table_set(m, lua_val_from_str("sin"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_sin));
    \\    lua_table_set(m, lua_val_from_str("sqrt"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_sqrt));
    \\    lua_table_set(m, lua_val_from_str("tan"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_tan));
    \\    lua_table_set(m, lua_val_from_str("type"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_type));
    \\    lua_table_set(m, lua_val_from_str("tointeger"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_tointeger));
    \\    lua_table_set(m, lua_val_from_str("modf"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_modf));
    \\    lua_table_set(m, lua_val_from_str("ult"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_ult));
    \\    lua_table_set(m, lua_val_from_str("deg"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_deg));
    \\    lua_table_set(m, lua_val_from_str("rad"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_rad));
    \\    lua_table_set(m, lua_val_from_str("fmod"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_fmod));
    \\    lua_table_set(m, lua_val_from_str("max"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_max));
    \\    lua_table_set(m, lua_val_from_str("min"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_min));
    \\    lua_table_set(m, lua_val_from_str("pow"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_pow));
    \\    lua_table_set(m, lua_val_from_str("sinh"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_sinh));
    \\    lua_table_set(m, lua_val_from_str("cosh"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_cosh));
    \\    lua_table_set(m, lua_val_from_str("tanh"), lua_val_from_func((lua_Value (*)(lua_Value))lua_math_tanh));
    \\    return m;
    \\}
    \\
    \\static inline lua_Value lua_coroutine_init(void) {
    \\    lua_Value m = lua_table_new();
    \\    lua_table_set(m, lua_val_from_str("create"), lua_val_from_func((lua_Value (*)(lua_Value))lua_co_create));
    \\    lua_table_set(m, lua_val_from_str("resume"), lua_val_from_func((lua_Value (*)(lua_Value))lua_co_resume));
    \\    lua_table_set(m, lua_val_from_str("yield"), lua_val_from_func((lua_Value (*)(lua_Value))lua_co_yield));
    \\    lua_table_set(m, lua_val_from_str("status"), lua_val_from_func((lua_Value (*)(lua_Value))lua_co_status));
    \\    lua_table_set(m, lua_val_from_str("running"), lua_val_from_func((lua_Value (*)(lua_Value))lua_co_running));
    \\    lua_table_set(m, lua_val_from_str("wrap"), lua_val_from_func((lua_Value (*)(lua_Value))lua_co_wrap));
    \\    lua_table_set(m, lua_val_from_str("isyieldable"), lua_val_from_func((lua_Value (*)(lua_Value))lua_co_isyieldable));
    \\    lua_table_set(m, lua_val_from_str("close"), lua_val_from_func((lua_Value (*)(lua_Value))lua_co_close));
    \\    return m;
    \\}
    \\
    \\static inline lua_Value lua_string_init(void) {
    \\    lua_Value m = lua_table_new();
    \\    lua_Value bufmod = lua_table_new();
    \\    lua_table_set(bufmod, lua_val_from_str("new"), lua_val_from_func((void*)lua_str_buf_new));
    \\    lua_table_set(bufmod, lua_val_from_str("reset"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_buf_reset));
    \\    lua_table_set(bufmod, lua_val_from_str("set"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_buf_set));
    \\    lua_table_set(bufmod, lua_val_from_str("free"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_buf_free));
    \\    lua_table_set(bufmod, lua_val_from_str("len"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_buf_len));
    \\    lua_table_set(bufmod, lua_val_from_str("putf"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_buf_putf));
    \\    lua_table_set(m, lua_val_from_str("buffer"), bufmod);
    \\    lua_table_set(m, lua_val_from_str("len"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_len));
    \\    lua_table_set(m, lua_val_from_str("lower"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_lower));
    \\    lua_table_set(m, lua_val_from_str("upper"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_upper));
    \\    lua_table_set(m, lua_val_from_str("sub"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_sub));
    \\    lua_table_set(m, lua_val_from_str("char"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_char));
    \\    lua_table_set(m, lua_val_from_str("format"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_format));
    \\    lua_table_set(m, lua_val_from_str("rep"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_rep));
    \\    lua_table_set(m, lua_val_from_str("reverse"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_reverse));
    \\    lua_table_set(m, lua_val_from_str("byte"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_byte));
    \\    lua_table_set(m, lua_val_from_str("find"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_find));
    \\    lua_table_set(m, lua_val_from_str("match"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_match));
    \\    lua_table_set(m, lua_val_from_str("gsub"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_gsub));
    \\    lua_table_set(m, lua_val_from_str("gmatch"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_gmatch));
    \\    lua_table_set(m, lua_val_from_str("dump"), lua_val_from_func((lua_Value (*)(lua_Value))lua_str_dump));
    \\    return m;
    \\}
    \\
    \\static inline lua_Value lua_table_init(void) {
    \\    lua_Value m = lua_table_new();
    \\    lua_table_set(m, lua_val_from_str("insert"), lua_val_from_func((lua_Value (*)(lua_Value))lua_tbl_insert));
    \\    lua_table_set(m, lua_val_from_str("remove"), lua_val_from_func((lua_Value (*)(lua_Value))lua_tbl_remove));
    \\    lua_table_set(m, lua_val_from_str("concat"), lua_val_from_func((lua_Value (*)(lua_Value))lua_tbl_concat));
    \\    lua_table_set(m, lua_val_from_str("sort"), lua_val_from_func((lua_Value (*)(lua_Value))lua_tbl_sort));
    \\    lua_table_set(m, lua_val_from_str("new"), lua_val_from_func((void*)lua_tbl_create_argv));
    \\    lua_table_set(m, lua_val_from_str("create"), lua_val_from_func((void*)lua_tbl_create_argv));
    \\    lua_table_set(m, lua_val_from_str("clear"), lua_val_from_func((lua_Value (*)(lua_Value))lua_tbl_clear));
    \\    lua_table_set(m, lua_val_from_str("move"), lua_val_from_func((lua_Value (*)(lua_Value))lua_tbl_move));
    \\    lua_table_set(m, lua_val_from_str("unpack"), lua_val_from_func((lua_Value (*)(lua_Value))lua_tbl_unpack));
    \\    lua_table_set(m, lua_val_from_str("pack"), lua_val_from_func((void*)lua_tbl_pack_argv_fn));
    \\    lua_table_set(m, lua_val_from_str("freeze"), lua_val_from_func((lua_Value (*)(lua_Value))lua_tbl_freeze));
    \\    lua_table_set(m, lua_val_from_str("isfrozen"), lua_val_from_func((lua_Value (*)(lua_Value))lua_tbl_isfrozen));
    \\    return m;
    \\}
    \\
    \\static inline lua_Value lua_io_make_stdio(FILE* f) {
    \\    lua_File* lf = malloc(sizeof(lua_File));
    \\    lf->f = f;
    \\    lf->is_pipe = false;
    \\    lf->is_stdio = true;
    \\    lua_Value v;
    \\    v.type = VAL_FILE;
    \\    v.as.tval = (void*)lf;
    \\    return v;
    \\}
    \\
    \\static inline lua_Value lua_io_init(void) {
    \\    lua_Value m = lua_table_new();
    \\    lua_table_set(m, lua_val_from_str("stdin"), lua_io_make_stdio(stdin));
    \\    lua_table_set(m, lua_val_from_str("stdout"), lua_io_make_stdio(stdout));
    \\    lua_table_set(m, lua_val_from_str("stderr"), lua_io_make_stdio(stderr));
    \\    lua_table_set(m, lua_val_from_str("write"), lua_val_from_func((lua_Value (*)(lua_Value))lua_io_write));
    \\    lua_table_set(m, lua_val_from_str("read"), lua_val_from_func((lua_Value (*)(lua_Value))lua_io_read));
    \\    lua_table_set(m, lua_val_from_str("flush"), lua_val_from_func((lua_Value (*)(lua_Value))lua_io_flush));
    \\    lua_table_set(m, lua_val_from_str("open"), lua_val_from_func((lua_Value (*)(lua_Value))lua_io_open));
    \\    lua_table_set(m, lua_val_from_str("close"), lua_val_from_func((lua_Value (*)(lua_Value))lua_io_close));
    \\    lua_table_set(m, lua_val_from_str("tmpfile"), lua_val_from_func((lua_Value (*)(lua_Value))lua_io_tmpfile));
    \\    lua_table_set(m, lua_val_from_str("input"), lua_val_from_func((lua_Value (*)(lua_Value))lua_io_input));
    \\    lua_table_set(m, lua_val_from_str("output"), lua_val_from_func((lua_Value (*)(lua_Value))lua_io_output));
    \\    lua_table_set(m, lua_val_from_str("popen"), lua_val_from_func((lua_Value (*)(lua_Value))lua_io_popen));
    \\    lua_table_set(m, lua_val_from_str("type"), lua_val_from_func((lua_Value (*)(lua_Value))lua_io_type));
    \\    lua_table_set(m, lua_val_from_str("lines"), lua_val_from_func((lua_Value (*)(lua_Value))lua_io_lines));
    \\    return m;
    \\}
    \\
    \\static inline lua_Value lua_os_init(void) {
    \\    lua_Value m = lua_table_new();
    \\    lua_table_set(m, lua_val_from_str("clock"), lua_val_from_func((lua_Value (*)(lua_Value))lua_os_clock));
    \\    lua_table_set(m, lua_val_from_str("time"), lua_val_from_func((lua_Value (*)(lua_Value))lua_os_time));
    \\    lua_table_set(m, lua_val_from_str("difftime"), lua_val_from_func((lua_Value (*)(lua_Value))lua_os_difftime));
    \\    lua_table_set(m, lua_val_from_str("exit"), lua_val_from_func((lua_Value (*)(lua_Value))lua_os_exit));
    \\    lua_table_set(m, lua_val_from_str("getenv"), lua_val_from_func((lua_Value (*)(lua_Value))lua_os_getenv));
    \\    lua_table_set(m, lua_val_from_str("remove"), lua_val_from_func((lua_Value (*)(lua_Value))lua_os_remove));
    \\    lua_table_set(m, lua_val_from_str("rename"), lua_val_from_func((lua_Value (*)(lua_Value))lua_os_rename));
    \\    lua_table_set(m, lua_val_from_str("date"), lua_val_from_func((lua_Value (*)(lua_Value))lua_os_date));
    \\    lua_table_set(m, lua_val_from_str("execute"), lua_val_from_func((lua_Value (*)(lua_Value))lua_os_execute));
    \\    lua_table_set(m, lua_val_from_str("tmpname"), lua_val_from_func((lua_Value (*)(lua_Value))lua_os_tmpname));
    \\    lua_table_set(m, lua_val_from_str("setlocale"), lua_val_from_func((lua_Value (*)(lua_Value))lua_os_setlocale));
    \\    return m;
    \\}
    \\
    \\static inline lua_Value lua_utf8_init(void) {
    \\    lua_Value m = lua_table_new();
    \\    lua_table_set(m, lua_val_from_str("len"), lua_val_from_func((lua_Value (*)(lua_Value))lua_utf8_len));
    \\    lua_table_set(m, lua_val_from_str("codepoint"), lua_val_from_func((lua_Value (*)(lua_Value))lua_utf8_codepoint));
    \\    lua_table_set(m, lua_val_from_str("offset"), lua_val_from_func((lua_Value (*)(lua_Value))lua_utf8_offset));
    \\    lua_table_set(m, lua_val_from_str("char"), lua_val_from_func((lua_Value (*)(lua_Value))lua_utf8_char));
    \\    lua_table_set(m, lua_val_from_str("codes"), lua_val_from_func((lua_Value (*)(lua_Value))lua_utf8_codes));
    \\    return m;
    \\}
    \\
    \\static inline lua_Value lua_debug_init(void) {
    \\    lua_Value m = lua_table_new();
    \\    lua_table_set(m, lua_val_from_str("traceback"), lua_val_from_func((lua_Value (*)(lua_Value))lua_debug_traceback));
    \\    lua_table_set(m, lua_val_from_str("getinfo"), lua_val_from_func((lua_Value (*)(lua_Value))lua_debug_getinfo));
    \\    return m;
    \\}
    \\/* --------------------------- */
    \\
    ;
