//! Runtime JIT for Duo closures (tier-2 recompile via `duo compile --load-chunk`).
//!
//! Hot closures (call-count threshold or `jit.on(f)`) are pretty-printed to Lua
//! source, recompiled as a shared library, and invoked through `lua_invoke` on
//! the returned function value.

const std = @import("std");
const ast = @import("ast.zig");
const pretty = @import("pretty.zig");
const types = @import("types.zig");

const E = std.mem.Allocator.Error || std.Io.Writer.Error;

pub const max_closures: u32 = 4096;

pub fn emitClosureSourceTable(cg: anytype, list: []const *ast.FuncBody) E!void {
    var max_id: u32 = 0;
    for (list) |fb| {
        if (fb.closure_id) |id| max_id = @max(max_id, id);
    }
    const table_len = @max(max_id + 1, 1);

    var sources = try cg.alloc.alloc(?[]const u8, table_len);
    defer {
        for (sources) |s| {
            if (s) |txt| cg.alloc.free(txt);
        }
        cg.alloc.free(sources);
    }
    @memset(sources, null);

    const mode: pretty.Mode = if (cg.idol_mode) .idol else .lua;
    for (list) |fb| {
        const id = fb.closure_id orelse continue;
        if (id >= table_len) continue;
        sources[id] = try pretty.formatJitClosureSource(cg.alloc, fb, mode);
    }

    cg.p("#ifndef DUO_JIT_MAX_CLOSURES\n", .{});
    cg.p("#define DUO_JIT_MAX_CLOSURES {d}\n", .{max_closures});
    cg.p("#endif\n\n", .{});

    cg.p("static const char* const duo_jit_sources[{d}] = {{\n", .{table_len});
    for (0..table_len) |i| {
        if (sources[i]) |src| {
            cg.p("    ", .{});
            try emitCStringLiteral(cg, src);
            cg.p(",\n", .{});
        } else {
            cg.p("    NULL,\n", .{});
        }
    }
    cg.p("}};\n\n", .{});
}

/// Must stay in lockstep with `codegen.upvalue_uses_pointer` — this is a second
/// copy of that decision, and when the two disagreed the closure struct was
/// emitted by value while this pack function still dereferenced it
/// ("indirection requires pointer operand").
///
/// The pointer path is disabled for the same reason as in codegen: `&local` is
/// the address of a stack slot in the enclosing frame, which is gone once the
/// closure escapes. Shared mutation needs a heap cell; until then, by value.
fn upvalue_uses_pointer(uv: ast.Upvalue) bool {
    if (!uv.mutable) return false;
    if (uv.typ) |t| {
        if (t != .any) return false;
    } else return false;
    return false;
}

fn emitUpvalueAsLuaValue(cg: anytype, uv: ast.Upvalue, i: u32) void {
    if (upvalue_uses_pointer(uv)) {
        cg.p("    out[{d}] = *cl->up{d};\n", .{ i, i });
        return;
    }
    if (uv.typ) |t| {
        if (t.is_integer()) {
            cg.p("    out[{d}] = lua_val_from_num((double)cl->up{d});\n", .{ i, i });
            return;
        }
        switch (t) {
            .f64, .f32 => cg.p("    out[{d}] = lua_val_from_num((double)cl->up{d});\n", .{ i, i }),
            .bool => cg.p("    out[{d}] = lua_val_from_bool(cl->up{d});\n", .{ i, i }),
            .str => cg.p("    out[{d}] = lua_val_from_literal(cl->up{d});\n", .{ i, i }),
            .func, .any => cg.p("    out[{d}] = cl->up{d};\n", .{ i, i }),
            else => cg.p("    out[{d}] = cl->up{d};\n", .{ i, i }),
        }
        return;
    }
    cg.p("    out[{d}] = cl->up{d};\n", .{ i, i });
}

pub fn emitUpvaluePackTable(cg: anytype, list: []const *ast.FuncBody) E!void {
    var max_id: u32 = 0;
    for (list) |fb| {
        if (fb.closure_id) |id| max_id = @max(max_id, id);
    }
    const table_len = @max(max_id + 1, 1);

    var nups = try cg.alloc.alloc(u8, table_len);
    defer cg.alloc.free(nups);
    @memset(nups, 0);
    for (list) |fb| {
        const id = fb.closure_id orelse continue;
        if (id >= table_len) continue;
        if (fb.upvalues.len > 255) return error.OutOfMemory;
        nups[id] = @intCast(fb.upvalues.len);
    }

    for (list) |fb| {
        const id = fb.closure_id orelse continue;
        if (fb.upvalues.len == 0) continue;
        cg.p("static int duo_jit_pack_{d}(lua_Closure* cl_raw, lua_Value* out, int* nout) {{\n", .{id});
        cg.p("    duo_closure_{d}* cl = (duo_closure_{d}*)cl_raw;\n", .{ id, id });
        for (fb.upvalues, 0..) |uv, i| {
            emitUpvalueAsLuaValue(cg, uv, @intCast(i));
        }
        cg.p("    *nout = {d};\n", .{fb.upvalues.len});
        cg.p("    return 0;\n", .{});
        cg.p("}}\n\n", .{});
    }

    cg.p("static const uint8_t duo_jit_nup[{d}] = {{\n", .{table_len});
    for (nups) |n| cg.p("    {d},\n", .{n});
    cg.p("}};\n\n", .{});

    cg.p("typedef int (*duo_jit_pack_fn)(lua_Closure*, lua_Value*, int*);\n", .{});
    cg.p("static duo_jit_pack_fn duo_jit_pack[{d}] = {{\n", .{table_len});
    for (0..table_len) |i| {
        if (nups[i] > 0) {
            cg.p("    duo_jit_pack_{d},\n", .{i});
        } else {
            cg.p("    NULL,\n", .{});
        }
    }
    cg.p("}};\n\n", .{});
}

fn isHexDigit(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

fn emitCStringLiteral(cg: anytype, s: []const u8) E!void {
    cg.p("\"", .{});
    for (s, 0..) |c, i| {
        switch (c) {
            '\\' => cg.p("\\\\", .{}),
            '"' => cg.p("\\\"", .{}),
            '\n' => cg.p("\\n", .{}),
            '\r' => cg.p("\\r", .{}),
            '\t' => cg.p("\\t", .{}),
            else => {
                if (c >= 32 and c < 127) {
                    cg.p("{c}", .{c});
                } else {
                    const hex = "0123456789abcdef";
                    cg.p("\\x", .{});
                    cg.p("{c}{c}", .{ hex[c >> 4], hex[c & 15] });
                    // C's \x escape greedily consumes any following hex
                    // digits, so a raw hex-digit byte right after this
                    // escape would silently merge into it (and can overflow
                    // char range, which clang rejects outright). Split the
                    // string literal here; adjacent literals concatenate.
                    if (i + 1 < s.len and isHexDigit(s[i + 1])) {
                        cg.p("\"\"", .{});
                    }
                }
            },
        }
    }
    cg.p("\"", .{});
}

pub fn emitJitRuntime(cg: anytype) E!void {
    if (cg.load_chunk) {
        const stub =
            \\static inline lua_Value lua_jit_on(lua_Value f) { (void)f; return lua_val_nil(); }
            \\static inline lua_Value lua_jit_off(lua_Value f) { (void)f; return lua_val_nil(); }
            \\static inline lua_Value lua_jit_flush(lua_Value f) { (void)f; return lua_val_nil(); }
            \\static inline bool lua_jit_status_bool(void) { return false; }
            \\static inline lua_Value lua_jit_status(void) { return lua_val_from_bool(0); }
            \\static inline lua_Value lua_jit_version_num(void) { return lua_val_from_num(20100.0); }
            \\static inline lua_Value lua_jit_opt(lua_Value cmd, lua_Value val) { (void)cmd; (void)val; return lua_val_nil(); }
            \\static inline lua_Value duo_jit_dispatch(int id, lua_Closure* cl, int argc, lua_Value* argv,
            \\                                    lua_Value (*fallback)(int, lua_Closure*, int, lua_Value*)) {
            \\    return fallback(id, cl, argc, argv);
            \\}
            \\static inline lua_Value lua_jit_init(void) {
            \\    lua_Value m = lua_table_new_with_capacity(0, 8);
            \\    lua_table_init_lit(m, "on", lua_val_from_func((lua_Value (*)(lua_Value))lua_jit_on));
            \\    lua_table_init_lit(m, "off", lua_val_from_func((lua_Value (*)(lua_Value))lua_jit_off));
            \\    lua_table_init_lit(m, "flush", lua_val_from_func((lua_Value (*)(lua_Value))lua_jit_flush));
            \\    lua_table_init_lit(m, "status", lua_val_from_func((lua_Value (*)(lua_Value))lua_jit_status));
            \\    lua_table_init_lit(m, "version", lua_val_lit("Duo JIT 1.0"));
            \\    lua_table_init_lit(m, "version_num", lua_val_from_num(10000.0));
            \\    lua_table_init_lit(m, "opt", lua_val_from_func((lua_Value (*)(lua_Value, lua_Value))lua_jit_opt));
            \\    lua_table_init_lit(m, "os", lua_val_lit("Other"));
            \\    lua_table_init_lit(m, "arch", lua_val_lit("native"));
            \\    return m;
            \\}
            \\
        ;
        cg.p("{s}\n", .{stub});
        return;
    }
    const src =
        \\#ifndef __wasm__
        \\static int duo_jit_enabled = 1;
        \\static int duo_jit_hot_threshold = 100;
        \\static uint32_t duo_jit_call_count[DUO_JIT_MAX_CLOSURES];
        \\static unsigned char duo_jit_marked[(DUO_JIT_MAX_CLOSURES + 7) / 8];
        \\static unsigned char duo_jit_tier2[(DUO_JIT_MAX_CLOSURES + 7) / 8];
        \\static unsigned char duo_jit_tier2_busy[(DUO_JIT_MAX_CLOSURES + 7) / 8];
        \\static unsigned char duo_jit_tier2_failed[(DUO_JIT_MAX_CLOSURES + 7) / 8];
        \\static lua_Value duo_jit_replacement[DUO_JIT_MAX_CLOSURES];
        \\static void* duo_jit_dl[DUO_JIT_MAX_CLOSURES];
        \\
        \\static int duo_jit_bit_get(const unsigned char* bits, int id) {
        \\    if (id < 0 || id >= (int)DUO_JIT_MAX_CLOSURES) return 0;
        \\    return (bits[id >> 3] >> (id & 7)) & 1;
        \\}
        \\static void duo_jit_bit_set(unsigned char* bits, int id, int on) {
        \\    if (id < 0 || id >= (int)DUO_JIT_MAX_CLOSURES) return;
        \\    if (on) bits[id >> 3] |= (unsigned char)(1u << (id & 7));
        \\    else bits[id >> 3] &= (unsigned char)~(1u << (id & 7));
        \\}
        \\
        \\static int duo_jit_closure_id(lua_Value f) {
        \\    if (f.type == VAL_CLOSURE && f.as.tval)
        \\        return ((lua_Closure*)f.as.tval)->id;
        \\    return -1;
        \\}
        \\
        \\static void duo_jit_flush_id(int id) {
        \\    if (id < 0 || id >= (int)DUO_JIT_MAX_CLOSURES) return;
        \\    if (duo_jit_dl[id]) { dlclose(duo_jit_dl[id]); duo_jit_dl[id] = NULL; }
        \\    duo_jit_replacement[id] = lua_val_nil();
        \\    duo_jit_bit_set(duo_jit_tier2, id, 0);
        \\    duo_jit_bit_set(duo_jit_tier2_busy, id, 0);
        \\    duo_jit_bit_set(duo_jit_tier2_failed, id, 0);
        \\    duo_jit_call_count[id] = 0;
        \\    duo_jit_bit_set(duo_jit_marked, id, 0);
        \\}
        \\
        \\static int duo_jit_try_tier2(int id, lua_Closure* cl_raw) {
        \\    if (id < 0 || id >= (int)DUO_JIT_MAX_CLOSURES) return -1;
        \\    if (duo_jit_bit_get(duo_jit_tier2, id)) return 0;
        \\    if (duo_jit_bit_get(duo_jit_tier2_failed, id)) return -1;
        \\    if (duo_jit_bit_get(duo_jit_tier2_busy, id)) return -1;
        \\    if (id >= (int)(sizeof(duo_jit_sources) / sizeof(duo_jit_sources[0]))) return -1;
        \\    const char* src = duo_jit_sources[id];
        \\    if (!src || !src[0]) return -1;
        \\    duo_jit_bit_set(duo_jit_tier2_busy, id, 1);
        \\    char lua_path[512];
        \\    char dlib_path[512];
        \\    char err[1024];
        \\    int rc = -1;
        \\    if (duo_make_temp_path(lua_path, sizeof lua_path, ".lua") != 0) goto tier2_fail;
        \\    if (duo_write_file(lua_path, src, strlen(src)) != 0) { unlink(lua_path); goto tier2_fail; }
        \\    if (duo_make_temp_path(dlib_path, sizeof dlib_path, DUO_DLIB_EXT) != 0) { unlink(lua_path); goto tier2_fail; }
        \\    if (duo_compile_load_chunk(lua_path, dlib_path, err, sizeof err) != 0) {
        \\        unlink(lua_path);
        \\        unlink(dlib_path);
        \\        goto tier2_fail;
        \\    }
        \\    unlink(lua_path);
        \\    void* dl = dlopen(dlib_path, RTLD_NOW | RTLD_LOCAL);
        \\    unlink(dlib_path);
        \\    if (!dl) goto tier2_fail;
        \\    duo_load_entry_fn entry = (duo_load_entry_fn)dlsym(dl, "duo_load_entry");
        \\    if (!entry) { dlclose(dl); goto tier2_fail; }
        \\    lua_Value fn = entry();
        \\    if (fn.type != VAL_FUNC && fn.type != VAL_CLOSURE) { dlclose(dl); goto tier2_fail; }
        \\    if (id < (int)(sizeof(duo_jit_nup) / sizeof(duo_jit_nup[0])) && duo_jit_nup[id] > 0) {
        \\        lua_Value ups[16];
        \\        int nup = 0;
        \\        if (!duo_jit_pack[id] || duo_jit_pack[id](cl_raw, ups, &nup) != 0) { dlclose(dl); goto tier2_fail; }
        \\        fn = lua_invoke(fn, nup, ups);
        \\        if (fn.type != VAL_FUNC && fn.type != VAL_CLOSURE) { dlclose(dl); goto tier2_fail; }
        \\    }
        \\    duo_jit_dl[id] = dl;
        \\    duo_jit_replacement[id] = fn;
        \\    duo_jit_bit_set(duo_jit_tier2, id, 1);
        \\    duo_jit_bit_set(duo_jit_tier2_busy, id, 0);
        \\    return 0;
        \\tier2_fail:
        \\    duo_jit_bit_set(duo_jit_tier2_busy, id, 0);
        \\    duo_jit_bit_set(duo_jit_tier2_failed, id, 1);
        \\    return -1;
        \\}
        \\
        \\static lua_Value duo_jit_dispatch(int id, lua_Closure* cl, int argc, lua_Value* argv,
        \\                                    lua_Value (*fallback)(int, lua_Closure*, int, lua_Value*)) {
        \\    if (duo_jit_enabled && id >= 0 && id < (int)DUO_JIT_MAX_CLOSURES) {
        \\        if (duo_jit_bit_get(duo_jit_tier2, id)) {
        \\            lua_mret_clear();
        \\            return lua_invoke(duo_jit_replacement[id], argc, argv);
        \\        }
        \\        int hot = duo_jit_bit_get(duo_jit_marked, id);
        \\        if (!hot) {
        \\            duo_jit_call_count[id] += 1;
        \\            if (duo_jit_call_count[id] >= (uint32_t)duo_jit_hot_threshold) hot = 1;
        \\        }
        \\        if (hot && !duo_jit_bit_get(duo_jit_tier2_failed, id) && duo_jit_try_tier2(id, cl) == 0) {
        \\            lua_mret_clear();
        \\            return lua_invoke(duo_jit_replacement[id], argc, argv);
        \\        }
        \\    }
        \\    return fallback(id, cl, argc, argv);
        \\}
        \\
        \\static inline lua_Value lua_jit_on(lua_Value f) {
        \\    int id = duo_jit_closure_id(f);
        \\    if (id >= 0) duo_jit_bit_set(duo_jit_marked, id, 1);
        \\    return lua_val_nil();
        \\}
        \\static inline lua_Value lua_jit_off(lua_Value f) {
        \\    int id = duo_jit_closure_id(f);
        \\    if (id >= 0) duo_jit_flush_id(id);
        \\    return lua_val_nil();
        \\}
        \\static inline lua_Value lua_jit_flush(lua_Value f) {
        \\    if (f.type == VAL_NIL) {
        \\        for (int i = 0; i < (int)DUO_JIT_MAX_CLOSURES; i++) duo_jit_flush_id(i);
        \\    } else {
        \\        duo_jit_flush_id(duo_jit_closure_id(f));
        \\    }
        \\    return lua_val_nil();
        \\}
        \\static inline bool lua_jit_status_bool(void) { return duo_jit_enabled != 0; }
        \\static inline lua_Value lua_jit_status(void) { return lua_val_from_bool(lua_jit_status_bool()); }
        \\static inline lua_Value lua_jit_version_num(void) { return lua_val_from_num(20100.0); }
        \\static inline lua_Value lua_jit_opt(lua_Value cmd, lua_Value val) {
        \\    if (cmd.type == VAL_STRING && cmd.as.sval) {
        \\        if (strcmp(cmd.as.sval, "hotloop") == 0 || strcmp(cmd.as.sval, "hotexit") == 0) {
        \\            if (val.type == VAL_NUMBER)
        \\                duo_jit_hot_threshold = (int)val.as.nval;
        \\        } else if (strcmp(cmd.as.sval, "enable") == 0) {
        \\            duo_jit_enabled = (val.type == VAL_BOOL) ? (val.as.bval ? 1 : 0) : 1;
        \\        } else if (strcmp(cmd.as.sval, "compile") == 0 && val.type == VAL_STRING && val.as.sval) {
        \\            snprintf(duo_jit_compile_flags, sizeof duo_jit_compile_flags, " %s", val.as.sval);
        \\        }
        \\    }
        \\    return lua_val_nil();
        \\}
        \\#else
        \\static inline lua_Value lua_jit_on(lua_Value f) { (void)f; return lua_val_nil(); }
        \\static inline lua_Value lua_jit_off(lua_Value f) { (void)f; return lua_val_nil(); }
        \\static inline lua_Value lua_jit_flush(lua_Value f) { (void)f; return lua_val_nil(); }
        \\static inline bool lua_jit_status_bool(void) { return false; }
        \\static inline lua_Value lua_jit_status(void) { return lua_val_from_bool(0); }
        \\static inline lua_Value lua_jit_version_num(void) { return lua_val_from_num(20100.0); }
        \\static inline lua_Value lua_jit_opt(lua_Value cmd, lua_Value val) { (void)cmd; (void)val; return lua_val_nil(); }
        \\static inline lua_Value duo_jit_dispatch(int id, lua_Closure* cl, int argc, lua_Value* argv,
        \\                                    lua_Value (*fallback)(int, lua_Closure*, int, lua_Value*)) {
        \\    return fallback(id, cl, argc, argv);
        \\}
        \\#endif
        \\
        \\static inline lua_Value lua_jit_init(void) {
        \\    lua_Value m = lua_table_new_with_capacity(0, 8);
        \\    lua_table_init_lit(m, "on", lua_val_from_func((lua_Value (*)(lua_Value))lua_jit_on));
        \\    lua_table_init_lit(m, "off", lua_val_from_func((lua_Value (*)(lua_Value))lua_jit_off));
        \\    lua_table_init_lit(m, "flush", lua_val_from_func((lua_Value (*)(lua_Value))lua_jit_flush));
        \\    lua_table_init_lit(m, "status", lua_val_from_func((lua_Value (*)(lua_Value))lua_jit_status));
        \\    lua_table_init_lit(m, "version", lua_val_lit("Duo JIT 1.0"));
        \\    lua_table_init_lit(m, "version_num", lua_val_from_num(10000.0));
        \\    lua_table_init_lit(m, "opt", lua_val_from_func((lua_Value (*)(lua_Value, lua_Value))lua_jit_opt));
        \\    lua_table_init_lit(m, "os", lua_val_lit("Other"));
        \\    lua_table_init_lit(m, "arch", lua_val_lit("native"));
        \\    return m;
        \\}
        \\
    ;
    cg.p("{s}\n", .{src});
}

pub fn emitInvokeWrapperPrologue(cg: anytype) E!void {
    cg.p("static lua_Value duo_invoke_closure_impl(int id, lua_Closure* cl, int argc, lua_Value* argv) {{\n", .{});
    cg.p("    switch (id) {{\n", .{});
}

pub fn emitInvokeWrapperEpilogue(cg: anytype) E!void {
    cg.p("        default: return lua_val_nil();\n", .{});
    cg.p("    }}\n", .{});
    cg.p("}}\n\n", .{});
    cg.p("lua_Value duo_invoke_closure(int id, lua_Closure* cl, int argc, lua_Value* argv) {{\n", .{});
    cg.p("    return duo_jit_dispatch(id, cl, argc, argv, duo_invoke_closure_impl);\n", .{});
    cg.p("}}\n\n", .{});
}
