//! NATIVE WEBASSEMBLY EMISSION FROM DNIR.
//!
//! THE SEAM IS THE IR, NOT THE AST. `dnir_lower.zig` already turns a checked
//! module into `native_ir.Module`; `native_backend.zig` turns that into AArch64
//! Mach-O. This file is the SECOND consumer of the same lowering, so both
//! realizations consume one fact stream. Every new DNIR fact still needs an
//! explicit consumer here: sharing the producer prevents semantic
//! reconstruction, while differential controls prevent consumer omission.
//!
//! WHAT THIS REPLACES. `--target wasm32-wasi` used to be the C emitter's tail —
//! `src/codegen.zig` wrote C and `zig cc --target=wasm32-wasi` compiled it. That
//! made the C backend load-bearing for a target that has nothing to do with C,
//! and it is the item blocking `--backend=c`'s retirement. Nothing here shells
//! out; the `.wasm` bytes are written by this file.
//!
//! ---------------------------------------------------------------------------
//! THREE THINGS DNIR ASSUMES THAT WEBASSEMBLY DOES NOT HAVE
//! ---------------------------------------------------------------------------
//!
//! 1. AN UNSTRUCTURED CFG. `Instr.branch_target` is a FLAT INSTRUCTION INDEX
//!    across the concatenation of every block in a function, and a `br` may jump
//!    anywhere — forward past an `if`, backward to a loop head, or to the
//!    one-past-the-end sentinel. WebAssembly has no `goto`. So a function with
//!    any branch at all is emitted as a DISPATCH LOOP: the flat stream is cut
//!    into basic blocks at leaders, a `pc` local names the next block, and one
//!    `br_table` inside `loop`/`block` nesting jumps to it. This is the standard
//!    general construction and it is correct for EVERY control-flow graph, which
//!    matters more here than the structured shapes a relooper would recover: the
//!    lowerer is under active development by other lanes, and a relooper that
//!    fails to reduce a new shape is a silent capability loss.
//!
//!    A function with NO `br` at all skips the dispatch entirely and is emitted
//!    straight-line, which is most of them.
//!
//! 2. REGISTERS. `mov_arg .result = k` means "stage this value in x{k}". There
//!    are no registers here, so the staged VALUES are remembered and pushed as
//!    operands, in index order, when the call that consumes them is reached.
//!    Remembering the `dnir.Value` rather than pushing eagerly is what keeps the
//!    operand stack empty at every basic-block boundary, which the dispatch loop
//!    requires.
//!
//! 3. A FRAME POINTER. `alloc_slots` reserves N i64 words in the current frame.
//!    WebAssembly locals have no addresses, so the words live in linear memory
//!    behind a SHADOW STACK: a mutable global holds the stack pointer, each
//!    function that allocates subtracts its whole frame ONCE in the prologue
//!    (never inside a loop — the AArch64 backend learned that the hard way, see
//!    its `compileDnirFunction` prologue comment), and every `ret` restores it.
//!
//! ---------------------------------------------------------------------------
//! ONE SLOT SPACE
//! ---------------------------------------------------------------------------
//! `Value.local` and `Value.temp` are THE SAME NUMBERING — `dnir_lower.freshTemp`
//! allocates both and `native_backend` resolves both through one map. So a DNIR
//! slot becomes exactly one WebAssembly local and no register allocation is
//! needed at all. What IS needed is a type per slot, because WebAssembly locals
//! are typed and DNIR's are not: `computeSlotTypes` propagates f64-ness from the
//! producers that declare it, to a fixed point, because a back edge can carry
//! f64-ness to a slot that has already been read.
//!
//! ---------------------------------------------------------------------------
//! WHAT IS REFUSED, AND WHY THAT IS THE SAFE DIRECTION
//! ---------------------------------------------------------------------------
//! An op this file does not implement returns `error.UnsupportedProgram` with
//! the construct named in the diagnostic. It NEVER emits an approximation. The
//! whole value of this backend is that its answers can be diffed against the
//! AArch64 build's, so a wrong `.wasm` that runs is worse than a refusal that
//! names its gap: the refusal is a number in the coverage table, the wrong
//! answer is a lie in a gate.
const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");
const dnir = @import("native_ir.zig");
const dnir_lower = @import("dnir_lower.zig");
const semantic_graph = @import("semantic_graph.zig");
const realization_validate = @import("realization_validate.zig");

const RT = types.ResolvedType;

pub const Error = error{ OutOfMemory, UnsupportedProgram };

/// Why emission refused, in the construct's own words rather than an error name.
pub const Diagnostic = struct {
    note_buf: [96]u8 = @splat(0),
    note_len: usize = 0,
    fn_buf: [96]u8 = @splat(0),
    fn_len: usize = 0,

    pub fn remember(self: *Diagnostic, text: []const u8) void {
        if (self.note_len != 0) return;
        const n = @min(text.len, self.note_buf.len);
        @memcpy(self.note_buf[0..n], text[0..n]);
        self.note_len = n;
    }

    pub fn rememberFunction(self: *Diagnostic, text: []const u8) void {
        if (self.fn_len != 0) return;
        const n = @min(text.len, self.fn_buf.len);
        @memcpy(self.fn_buf[0..n], text[0..n]);
        self.fn_len = n;
    }

    pub fn note(self: *const Diagnostic) ?[]const u8 {
        if (self.note_len == 0) return null;
        return self.note_buf[0..self.note_len];
    }

    pub fn functionName(self: *const Diagnostic) ?[]const u8 {
        if (self.fn_len == 0) return null;
        return self.fn_buf[0..self.fn_len];
    }
};

// ---------------------------------------------------------------------------
// LINEAR MEMORY MAP
//
// Fixed, and fixed HERE rather than per module, because every address below is
// baked into emitted code: a layout that moved between two builds of the same
// program would show up in a byte-comparison as a backend disagreement.
// ---------------------------------------------------------------------------

/// WASI `ciovec` — {ptr:i32, len:i32} — and the `nwritten` cell after it.
/// 0..64 is never addressed: a null `str` is a REAL VALUE in this IR (`os.env`
/// of an unset name) and `print_value` tests for it, so address 0 must not name
/// a legal object, exactly as it does not under Mach-O.
const addr_iovec: u32 = 64;
const addr_nwritten: u32 = 72;
/// Scratch for decimal and float formatting.
const addr_numbuf: u32 = 128;
const numbuf_len: u32 = 512;
/// Eight-byte cells for a variadic tail. Apple's ARM64 ABI passes that tail in
/// MEMORY rather than in registers, which is why `dnir_lower` marks it
/// `.field = "vararg"` at all; this is the same convention with the same shape,
/// so the two backends read one staging discipline and not two.
const addr_varargs: u32 = 640;
const max_varargs: u32 = 8;
/// The 256 one-byte strings `idol_str_at` answers with — two bytes each,
/// `{c, 0}`, so entry `c` is at `addr_onechar + c * 2`. The port of
/// `idol_str_runtime.zig` keeps its interning property: the same byte always
/// answers the same pointer.
const addr_onechar: u32 = 768;
/// `printf`'s staging buffer. Streaming a byte at a time through `fd_write`
/// would be one host call per character; this is one per 4 KiB.
const addr_outbuf: u32 = 1280;
const outbuf_len: u32 = 4096;
/// String literals and other read-only data start here.
///
/// ABOVE EVERY SCRATCH REGION, and the arithmetic is written out because it was
/// wrong once: `addr_onechar` at 768 with 512 bytes of table reaches 1280, and
/// the pool used to start at 1024. The two data segments overlapped by 256
/// bytes, the pool was written second and won, and every interned one-byte
/// string from 0x80 up was silently zero.
const addr_data: u32 = addr_outbuf + outbuf_len + 2816; // 8192

const shadow_stack_bytes: u32 = 1 << 20;
const heap_bytes: u32 = 4 << 20;
const wasm_page: u32 = 65536;

// ---------------------------------------------------------------------------
// ENCODING PRIMITIVES
// ---------------------------------------------------------------------------

const Buf = struct {
    alloc: std.mem.Allocator,
    items: std.ArrayListUnmanaged(u8) = .empty,

    fn deinit(self: *Buf) void {
        self.items.deinit(self.alloc);
    }

    fn byte(self: *Buf, b: u8) Error!void {
        try self.items.append(self.alloc, b);
    }

    fn bytes(self: *Buf, b: []const u8) Error!void {
        try self.items.appendSlice(self.alloc, b);
    }

    fn u32v(self: *Buf, value: u32) Error!void {
        var v = value;
        while (true) {
            var b: u8 = @intCast(v & 0x7f);
            v >>= 7;
            if (v != 0) b |= 0x80;
            try self.byte(b);
            if (v == 0) break;
        }
    }

    fn i64v(self: *Buf, value: i64) Error!void {
        var v = value;
        while (true) {
            const b: u8 = @intCast(@as(u64, @bitCast(v)) & 0x7f);
            v >>= 7;
            const sign_bit = (b & 0x40) != 0;
            if ((v == 0 and !sign_bit) or (v == -1 and sign_bit)) {
                try self.byte(b);
                break;
            }
            try self.byte(b | 0x80);
        }
    }

    fn i32v(self: *Buf, value: i32) Error!void {
        try self.i64v(value);
    }

    fn name(self: *Buf, s: []const u8) Error!void {
        try self.u32v(@intCast(s.len));
        try self.bytes(s);
    }

    // --- instruction shorthands ---------------------------------------------

    fn i32c(self: *Buf, v: i32) Error!void {
        try self.byte(op_i32_const);
        try self.i32v(v);
    }

    fn i64c(self: *Buf, v: i64) Error!void {
        try self.byte(op_i64_const);
        try self.i64v(v);
    }

    fn f64c(self: *Buf, v: f64) Error!void {
        try self.byte(op_f64_const);
        var raw: [8]u8 = undefined;
        std.mem.writeInt(u64, &raw, @bitCast(v), .little);
        try self.bytes(&raw);
    }

    fn get(self: *Buf, idx: u32) Error!void {
        try self.byte(op_local_get);
        try self.u32v(idx);
    }

    fn set(self: *Buf, idx: u32) Error!void {
        try self.byte(op_local_set);
        try self.u32v(idx);
    }

    fn tee(self: *Buf, idx: u32) Error!void {
        try self.byte(op_local_tee);
        try self.u32v(idx);
    }

    fn call(self: *Buf, idx: u32) Error!void {
        try self.byte(op_call);
        try self.u32v(idx);
    }

    fn op(self: *Buf, o: u8) Error!void {
        try self.byte(o);
    }

    /// `align` exponent then static offset — the memarg both load and store take.
    fn mem(self: *Buf, o: u8, alignment: u32, offset: u32) Error!void {
        try self.byte(o);
        try self.u32v(alignment);
        try self.u32v(offset);
    }
};

const op_unreachable: u8 = 0x00;
const op_block: u8 = 0x02;
const op_loop: u8 = 0x03;
const op_if: u8 = 0x04;
const op_else: u8 = 0x05;
const op_end: u8 = 0x0b;
const op_br: u8 = 0x0c;
const op_br_if: u8 = 0x0d;
const op_br_table: u8 = 0x0e;
const op_return: u8 = 0x0f;
const op_call: u8 = 0x10;
const op_drop: u8 = 0x1a;
const op_select: u8 = 0x1b;
const op_local_get: u8 = 0x20;
const op_local_set: u8 = 0x21;
const op_local_tee: u8 = 0x22;
const op_global_get: u8 = 0x23;
const op_global_set: u8 = 0x24;
const op_i32_load: u8 = 0x28;
const op_i64_load: u8 = 0x29;
const op_i64_load8_u: u8 = 0x31; // 0x30 is load8_S — the sign is the whole difference
const op_i32_store: u8 = 0x36;
const op_i64_store: u8 = 0x37;
const op_i32_store8: u8 = 0x3a;
const op_i64_store8: u8 = 0x3c;
const op_i32_const: u8 = 0x41;
const op_i64_const: u8 = 0x42;
const op_f64_const: u8 = 0x44;
const op_i32_eqz: u8 = 0x45;
const op_i32_eq: u8 = 0x46;
const op_i32_ne: u8 = 0x47;
const op_i32_lt_s: u8 = 0x48;
const op_i32_lt_u: u8 = 0x49;
const op_i32_gt_s: u8 = 0x4a;
const op_i32_ge_s: u8 = 0x4e;
const op_i64_eqz: u8 = 0x50;
const op_i64_eq: u8 = 0x51;
const op_i64_ne: u8 = 0x52;
const op_i64_lt_s: u8 = 0x53;
const op_i64_lt_u: u8 = 0x54;
const op_i64_gt_s: u8 = 0x55;
const op_i64_gt_u: u8 = 0x56;
const op_i64_le_s: u8 = 0x57;
const op_i64_ge_s: u8 = 0x59;
const op_f64_eq: u8 = 0x61;
const op_f64_ne: u8 = 0x62;
const op_f64_lt: u8 = 0x63;
const op_f64_gt: u8 = 0x64;
const op_f64_le: u8 = 0x65;
const op_f64_ge: u8 = 0x66;
const op_i32_add: u8 = 0x6a;
const op_i32_sub: u8 = 0x6b;
const op_i32_mul: u8 = 0x6c;
const op_i32_and: u8 = 0x71;
const op_i32_or: u8 = 0x72;
const op_i32_shl: u8 = 0x74;
const op_i64_clz: u8 = 0x79;
const op_i64_ctz: u8 = 0x7a;
const op_i64_popcnt: u8 = 0x7b;
const op_i64_add: u8 = 0x7c;
const op_i64_sub: u8 = 0x7d;
const op_i64_mul: u8 = 0x7e;
const op_i64_div_s: u8 = 0x7f;
const op_i64_div_u: u8 = 0x80;
const op_i64_rem_s: u8 = 0x81;
const op_i64_rem_u: u8 = 0x82;
const op_i64_and: u8 = 0x83;
const op_i64_or: u8 = 0x84;
const op_i64_xor: u8 = 0x85;
const op_i64_shl: u8 = 0x86;
const op_i64_shr_u: u8 = 0x88;
const op_f64_abs: u8 = 0x99;
const op_f64_neg: u8 = 0x9a;
const op_f64_ceil: u8 = 0x9b;
const op_f64_floor: u8 = 0x9c;
const op_f64_sqrt: u8 = 0x9f;
const op_f64_add: u8 = 0xa0;
const op_f64_sub: u8 = 0xa1;
const op_f64_mul: u8 = 0xa2;
const op_f64_div: u8 = 0xa3;
const op_i32_wrap_i64: u8 = 0xa7;
const op_i64_extend_i32_s: u8 = 0xac;
const op_i64_extend_i32_u: u8 = 0xad;
const op_f64_convert_i64_s: u8 = 0xb9;
const op_i64_reinterpret_f64: u8 = 0xbd;
const op_f64_reinterpret_i64: u8 = 0xbf;
const op_i64_extend8_s: u8 = 0xc2;
const op_i64_extend16_s: u8 = 0xc3;
const op_i64_extend32_s: u8 = 0xc4;

const vt_i32: u8 = 0x7f;
const vt_i64: u8 = 0x7e;
const vt_f64: u8 = 0x7c;
/// `blocktype` for a block that neither takes nor returns a value.
const bt_void: u8 = 0x40;

const SlotType = enum { i64, f64 };

fn slotValType(t: SlotType) u8 {
    return switch (t) {
        .i64 => vt_i64,
        .f64 => vt_f64,
    };
}

// ---------------------------------------------------------------------------
// SIGNATURE TABLE
// ---------------------------------------------------------------------------

const FuncType = struct {
    params: []const u8,
    results: []const u8,
};

const TypeTable = struct {
    alloc: std.mem.Allocator,
    list: std.ArrayListUnmanaged(FuncType) = .empty,

    fn deinit(self: *TypeTable) void {
        for (self.list.items) |t| {
            self.alloc.free(t.params);
            self.alloc.free(t.results);
        }
        self.list.deinit(self.alloc);
    }

    fn intern(self: *TypeTable, params: []const u8, results: []const u8) Error!u32 {
        for (self.list.items, 0..) |t, i| {
            if (std.mem.eql(u8, t.params, params) and std.mem.eql(u8, t.results, results)) {
                return @intCast(i);
            }
        }
        const p = try self.alloc.dupe(u8, params);
        errdefer self.alloc.free(p);
        const r = try self.alloc.dupe(u8, results);
        try self.list.append(self.alloc, .{ .params = p, .results = r });
        return @intCast(self.list.items.len - 1);
    }
};

// ---------------------------------------------------------------------------
// THE RUNTIME THIS BACKEND CARRIES
//
// wasm32-wasi has no libc. Everything `print_value` and the bootstrap externs
// needed from `_puts`/`_printf`/`_malloc` is written here, in WebAssembly, by
// `emitHelpers`. The ORDER of this enum IS the function-index order of the
// emitted module, so it is a declaration and not a convenience.
// ---------------------------------------------------------------------------

const Helper = enum {
    fd_write, // import 0
    proc_exit, // import 1
    strlen, //   (i64 ptr) -> i64
    write_bytes, // (i64 ptr, i64 len) -> ()
    write_cstr, // (i64 ptr) -> ()
    puts_cstr, //  (i64 ptr) -> ()
    print_i64, //  (i64 v, i64 nl) -> ()
    malloc, //     (i64 n) -> i64
    memset, //     (i64 p, i64 c, i64 n) -> i64
    memcpy, //     (i64 d, i64 s, i64 n) -> i64
    strcmp, //     (i64 a, i64 b) -> i64
    sn_put, //     (i64 ch) -> ()            one byte into the format cursor
    sn_puti, //    (i64 v) -> ()             one decimal integer likewise
    sn_format, //  (i64 fmt, i64 va) -> ()   the format walk, cursor already set
    snprintf, //   (i64 dst, i64 cap, i64 fmt, i64 va) -> i64
    printf, //     (i64 fmt, i64 va) -> ()
    str_at, //     (i64 s, i64 i) -> i64
    str_sub, //    (i64 s, i64 i, i64 j) -> i64
    str_to_i64, // (i64 s) -> i64
    die, //        (i64 msg) -> ()           message to fd 2, then trap
};

const helper_count: u32 = @typeInfo(Helper).@"enum".field_names.len;
const import_count: u32 = 2;

fn helperIndex(h: Helper) u32 {
    return @backingInt(h);
}

const StringPool = struct {
    alloc: std.mem.Allocator,
    data: std.ArrayListUnmanaged(u8) = .empty,
    map: std.StringHashMapUnmanaged(u32) = .empty,

    fn deinit(self: *StringPool) void {
        var it = self.map.keyIterator();
        while (it.next()) |k| self.alloc.free(k.*);
        self.map.deinit(self.alloc);
        self.data.deinit(self.alloc);
    }

    /// NUL-terminated and interned; returns the ABSOLUTE address.
    fn intern(self: *StringPool, s: []const u8) Error!u32 {
        if (self.map.get(s)) |a| return a;
        const addr: u32 = addr_data + @as(u32, @intCast(self.data.items.len));
        try self.data.appendSlice(self.alloc, s);
        try self.data.append(self.alloc, 0);
        const key = try self.alloc.dupe(u8, s);
        errdefer self.alloc.free(key);
        try self.map.put(self.alloc, key, addr);
        return addr;
    }
};

const FuncSig = struct {
    /// One entry per DNIR slot consumed as a parameter, in slot order.
    params: []SlotType,
    /// Empty for a void function, one entry for a scalar, and ONE PER FIELD for
    /// a record return.
    ///
    /// AArch64 splits a record return two ways — up to
    /// `dnir_lower.max_reg_record_fields` in x0..x7, wider through the x8
    /// indirect-result buffer — because it has eight registers and then runs
    /// out. WebAssembly's multi-value returns have no such ceiling, so BOTH
    /// widths take the same path here and the field count is the whole story.
    results: []SlotType,
};

const Emitter = struct {
    alloc: std.mem.Allocator,
    diagnostic: *Diagnostic,
    module: dnir.Module,

    types: TypeTable,
    strings: StringPool,
    /// Interned BEFORE the first body, so the type section written at assembly
    /// time already carries them. Interning them at assembly time meant writing
    /// the type section twice, which is one more place for the two copies to
    /// disagree.
    ty_fd_write: u32 = 0,
    ty_proc_exit: u32 = 0,
    func_index: std.StringHashMapUnmanaged(u32) = .empty,
    func_sig: std.StringHashMapUnmanaged(FuncSig) = .empty,
    /// `load_global` / `store_global` name -> offset from `globals_base`.
    globals: std.StringHashMapUnmanaged(u32) = .empty,
    globals_used: u32 = 0,
    /// Immutable aggregate id -> fixed linear-memory address. These are the
    /// Wasm realization of the same `DenseTable` rows AArch64 places in
    /// `__TEXT,__const`; `alloc_slots` becomes a pointer to these statically
    /// initialized bytes rather
    /// than rebuilding the aggregate in a shadow-stack frame.
    dense_addr: std.AutoHashMapUnmanaged(semantic_graph.id, u32) = .empty,
    dense_used: u32 = 0,

    /// Bodies in module function-index order, after the imports.
    bodies: std.ArrayListUnmanaged([]u8) = .empty,
    body_types: std.ArrayListUnmanaged(u32) = .empty,

    // --- per-function state ---
    cur_name: []const u8 = "<module>",
    cur_op: ?dnir.Op = null,
    cur_ret: RT = .void,
    cur_results: []const SlotType = &.{},
    slot_ty: std.AutoHashMapUnmanaged(u32, SlotType) = .empty,
    slot_count: u32 = 0,
    scratch_i32: u32 = 0,
    scratch_a: u32 = 0,
    scratch_b: u32 = 0,
    /// The TRUNCATED remainder, held so the floored correction can test it
    /// twice without recomputing a divide. See the `.mod` arm.
    scratch_c: u32 = 0,
    /// `//` needs the truncated QUOTIENT and the truncated REMAINDER live at the
    /// same time — the correction is `q - 1` decided by a test on `r` — and
    /// `.mod` needs only the remainder. One more i64 local is the whole cost of
    /// the fourth scratch; the alternative is dividing twice.
    scratch_d: u32 = 0,
    pc_local: u32 = 0,
    frame_local: u32 = 0,
    frame_off: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    frame_bytes: u32 = 0,
    /// RECORD FIELDS ARE NAMED, NOT NUMBERED. `load_field` carries
    /// `req_alias` + `field` and no slot at all, so the AArch64 backend keys a
    /// stack region by `"base.field"` and this file keys a WebAssembly local the
    /// same way. One local per key, allocated in a pre-pass so the declaration
    /// count is known before the first byte of the body is written.
    field_local: std.StringHashMapUnmanaged(u32) = .empty,
    /// Staged call operands from `mov_arg` / `fp_mov_arg`, by ABI index.
    pending: [16]?dnir.Value = @splat(null),
    pending_n: u32 = 0,
    /// The VARIADIC TAIL, staged separately because it is a separate storage:
    /// `.field = "vararg"` names a memory cell, not an argument register, and
    /// merging the two numbering spaces is how a four-argument `snprintf`
    /// printed a pointer.
    pending_va: [max_varargs]?dnir.Value = @splat(null),
    pending_va_n: u32 = 0,
    /// Depth of `$again` from the body currently being emitted, for the
    /// dispatch loop. Zero outside one.
    again_depth: u32 = 0,
    cur_block: u32 = 0,
    n_blocks: u32 = 0,
    in_dispatch: bool = false,

    fn deinit(self: *Emitter) void {
        self.types.deinit();
        self.strings.deinit();
        self.func_index.deinit(self.alloc);
        var sit = self.func_sig.valueIterator();
        while (sit.next()) |s| {
            self.alloc.free(s.params);
            self.alloc.free(s.results);
        }
        self.func_sig.deinit(self.alloc);
        self.globals.deinit(self.alloc);
        self.dense_addr.deinit(self.alloc);
        for (self.bodies.items) |b| {
            if (b.len > 0) self.alloc.free(b);
        }
        self.bodies.deinit(self.alloc);
        self.body_types.deinit(self.alloc);
        self.slot_ty.deinit(self.alloc);
        self.frame_off.deinit(self.alloc);
        freeFieldLocals(self);
        self.field_local.deinit(self.alloc);
    }

    fn refuse(self: *Emitter, why: []const u8) Error {
        if (self.cur_op) |o| {
            var buf: [96]u8 = undefined;
            self.diagnostic.remember(std.fmt.bufPrint(&buf, "{s}/{s}", .{ @tagName(o), why }) catch why);
        } else {
            self.diagnostic.remember(why);
        }
        self.diagnostic.rememberFunction(self.cur_name);
        return error.UnsupportedProgram;
    }
};

// ---------------------------------------------------------------------------
// SLOT TYPING
// ---------------------------------------------------------------------------

fn markF64(e: *Emitter, slot: ?u32, changed: *bool) Error!void {
    const s = slot orelse return;
    const got = try e.slot_ty.getOrPut(e.alloc, s);
    if (got.found_existing and got.value_ptr.* == .f64) return;
    got.value_ptr.* = .f64;
    changed.* = true;
}

fn valueIsF64(e: *const Emitter, v: dnir.Value) bool {
    return switch (v) {
        .f64 => true,
        .local, .temp => |s| (e.slot_ty.get(s) orelse .i64) == .f64,
        else => false,
    };
}

fn slotTypeOf(e: *const Emitter, slot: u32) SlotType {
    return e.slot_ty.get(slot) orelse .i64;
}

/// Fixed point, not one forward pass: a back edge can carry f64-ness to a slot
/// that has already been read.
fn computeSlotTypes(e: *Emitter, instrs: []const dnir.Instr, params: []const SlotType) Error!void {
    e.slot_ty.clearRetainingCapacity();
    for (params, 0..) |p, i| {
        if (p == .f64) try e.slot_ty.put(e.alloc, @intCast(i), .f64);
    }
    var rounds: u32 = 0;
    while (rounds < 128) : (rounds += 1) {
        var changed = false;
        for (instrs) |ins| {
            switch (ins.op) {
                .@"const" => if (ins.ty == .f64 or ins.lhs == .f64) try markF64(e, ins.result, &changed),
                .store_local => if (ins.ty == .f64 or valueIsF64(e, ins.lhs)) {
                    try markF64(e, ins.result, &changed);
                },
                .binop => {
                    // A COMPARISON ANSWERS WITH A BOOLEAN whatever its operands
                    // are — the exact confusion `native_backend` records at
                    // gap[058], where an f64 comparison was given an FP
                    // destination and the branch then read unrelated float state.
                    if (comparisonOf(ins.binop) != null) continue;
                    if (ins.ty == .f64 or valueIsF64(e, ins.lhs) or valueIsF64(e, ins.rhs)) {
                        try markF64(e, ins.result, &changed);
                    }
                },
                .call_direct, .call_extern, .load_global => if (ins.ty == .f64) {
                    try markF64(e, ins.result, &changed);
                },
                else => {},
            }
        }
        if (!changed) break;
    }
}

fn comparisonOf(tag: dnir.BinOpTag) ?u8 {
    return switch (tag) {
        .eq => op_i64_eq,
        .neq => op_i64_ne,
        .lt => op_i64_lt_s,
        .gt => op_i64_gt_s,
        .leq => op_i64_le_s,
        .geq => op_i64_ge_s,
        else => null,
    };
}

fn comparisonOfF64(tag: dnir.BinOpTag) ?u8 {
    return switch (tag) {
        .eq => op_f64_eq,
        .neq => op_f64_ne,
        .lt => op_f64_lt,
        .gt => op_f64_gt,
        .leq => op_f64_le,
        .geq => op_f64_ge,
        else => null,
    };
}

// ---------------------------------------------------------------------------
// SIGNATURES
// ---------------------------------------------------------------------------

/// The DNIR slot layout of a function's parameters, reproduced EXACTLY as
/// `dnir_lower.zig` assigns it: one slot per scalar parameter, one slot per
/// FIELD of an all-scalar record parameter. Anything else has no slot layout
/// this file can reproduce and is refused rather than guessed.
fn paramSlotTypes(e: *Emitter, f: dnir.Function) Error![]SlotType {
    var out: std.ArrayListUnmanaged(SlotType) = .empty;
    errdefer out.deinit(e.alloc);
    for (f.params) |p| {
        if (p.record) |rec_name| {
            const rec = dnir.findRecord(e.module, rec_name) orelse
                return e.refuse("record-param-unknown");
            var all_scalar = rec.kinds.len > 0;
            for (rec.kinds) |k| {
                if (k == .f64) all_scalar = false;
            }
            if (!all_scalar) return e.refuse("record-param-f64");
            for (rec.kinds) |_| try out.append(e.alloc, .i64);
            continue;
        }
        try out.append(e.alloc, if (p.ty == .f64) .f64 else .i64);
    }
    return out.toOwnedSlice(e.alloc);
}

fn returnSlotTypes(e: *Emitter, f: dnir.Function) Error![]SlotType {
    if (f.ret_record) |rec_name| {
        const rec = dnir.findRecord(e.module, rec_name) orelse return e.refuse("record-return-unknown");
        var out: std.ArrayListUnmanaged(SlotType) = .empty;
        errdefer out.deinit(e.alloc);
        for (rec.kinds) |k| {
            if (k == .f64) return e.refuse("record-return-f64");
            try out.append(e.alloc, .i64);
        }
        if (out.items.len == 0) return e.refuse("record-return-empty");
        return out.toOwnedSlice(e.alloc);
    }
    return switch (f.ret) {
        .void, .nil, .never => try e.alloc.dupe(SlotType, &.{}),
        .f64, .f32 => try e.alloc.dupe(SlotType, &.{.f64}),
        else => try e.alloc.dupe(SlotType, &.{.i64}),
    };
}

// ---------------------------------------------------------------------------
// PUBLIC ENTRY
// ---------------------------------------------------------------------------

/// Lower `mod` through DNIR and emit a complete wasm32-wasi module.
/// `graph` must be the SAME lift the direct backend uses; that is what makes the
/// two columns comparable.
pub fn emitWasmModule(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    entry: ?[]const u8,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error![]u8 {
    var lowering: dnir_lower.Diagnostic = .{};
    const lowered = dnir_lower.lowerModuleWithGraphObserved(alloc, mod, graph, &lowering) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        diagnostic.remember(lowering.note() orelse switch (err) {
            error.GraphFactsInvalid => "graph-dnir-facts",
            else => "graph-dnir-unsupported",
        });
        return error.UnsupportedProgram;
    };
    defer dnir.deinitModule(alloc, lowered);
    if (!dnir.moduleIsNativeDirectReady(lowered)) {
        diagnostic.remember("graph-direct-not-ready");
        return error.UnsupportedProgram;
    }
    return emitFromDnir(alloc, lowered, entry, diagnostic);
}

/// The DNIR-in / bytes-out half on its own, so a test can hand it a hand-built
/// module without going through parse and sema.
pub fn emitFromDnir(
    alloc: std.mem.Allocator,
    m: dnir.Module,
    entry: ?[]const u8,
    diagnostic: *Diagnostic,
) Error![]u8 {
    var e = Emitter{
        .alloc = alloc,
        .diagnostic = diagnostic,
        .module = m,
        .types = .{ .alloc = alloc },
        .strings = .{ .alloc = alloc },
    };
    defer e.deinit();
    if (realization_validate.aggregateSchedule(m)) |failure| {
        return e.refuse(failure.note);
    }

    e.ty_fd_write = try e.types.intern(&.{ vt_i32, vt_i32, vt_i32, vt_i32 }, &.{vt_i32});
    e.ty_proc_exit = try e.types.intern(&.{vt_i32}, &.{});

    const entry_name = entry orelse return e.refuse("no-entry-function");

    // ---- 1. Index every program function BEFORE emitting any body, so a call
    // to a function declared later resolves.
    var next_index: u32 = helper_count;
    for (m.functions) |f| {
        if (f.name.len == 0) return e.refuse("unnamed-function");
        if (e.func_index.contains(f.name)) return e.refuse("duplicate-function");
        const params = try paramSlotTypes(&e, f);
        errdefer alloc.free(params);
        const results = try returnSlotTypes(&e, f);
        errdefer alloc.free(results);
        try e.func_sig.put(alloc, f.name, .{ .params = params, .results = results });
        try e.func_index.put(alloc, f.name, next_index);
        next_index += 1;
    }
    const entry_index = e.func_index.get(entry_name) orelse return e.refuse("entry-not-lowered");
    const entry_sig = e.func_sig.get(entry_name).?;
    if (entry_sig.params.len != 0) return e.refuse("entry-takes-parameters");

    // ---- 2. One 8-byte word per module-scope global, discovered from the
    // instructions exactly as `native_backend.internGlobal` discovers them.
    // `assemble` consumes `m.globals` into these same offsets; words without a
    // published initializer retain WebAssembly's implicit zero initialization.
    for (m.functions) |f| {
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                switch (ins.op) {
                    .load_global, .store_global => {
                        if (ins.field.len == 0) continue;
                        if (e.globals.contains(ins.field)) continue;
                        try e.globals.put(alloc, ins.field, e.globals_used);
                        e.globals_used += 8;
                    },
                    else => {},
                }
            }
        }
    }

    // ---- 3. Give every graph-selected immutable dense table one exact
    // statically initialized address. The aggregate semantic id is the key; source binding
    // names and `alloc_slots` temporaries never decide which bytes are read.
    for (m.dense_tables) |table| {
        // Semantic shape, contents and uniqueness were admitted once by the
        // shared graph-to-DNIR validator above. This loop selects only the
        // physical linear-memory address and refuses arithmetic overflow.
        const word_count = std.math.cast(u32, table.values.len) orelse
            return e.refuse("dense-table-capacity");
        const bytes = std.math.mul(u32, word_count, 8) catch
            return e.refuse("dense-table-capacity");
        if (bytes > dense_cap - e.dense_used) return e.refuse("dense-table-capacity");
        const slot = try e.dense_addr.getOrPut(alloc, table.value);
        if (slot.found_existing) return e.refuse("dense-table-duplicate");
        slot.value_ptr.* = dense_base + e.dense_used;
        e.dense_used += bytes;
    }

    // ---- 4. Reserve the helper slots so program bodies land at the right index.
    try e.bodies.resize(alloc, helper_count - import_count);
    try e.body_types.resize(alloc, helper_count - import_count);
    for (e.bodies.items) |*b| b.* = &.{};
    for (e.body_types.items) |*t| t.* = 0;

    // ---- 5. Program bodies.
    for (m.functions) |f| {
        const body = try emitFunctionBody(&e, f);
        errdefer alloc.free(body);
        const sig = e.func_sig.get(f.name).?;
        var ps: std.ArrayListUnmanaged(u8) = .empty;
        defer ps.deinit(alloc);
        for (sig.params) |p| try ps.append(alloc, slotValType(p));
        var rs: std.ArrayListUnmanaged(u8) = .empty;
        defer rs.deinit(alloc);
        for (sig.results) |r| try rs.append(alloc, slotValType(r));
        const ti = try e.types.intern(ps.items, rs.items);
        try e.bodies.append(alloc, body);
        try e.body_types.append(alloc, ti);
    }

    // ---- 5. `_start`.
    const start_index: u32 = helper_count + @as(u32, @intCast(m.functions.len));
    {
        if (entry_sig.results.len > 1) return e.refuse("entry-returns-record");
        const body = try emitStart(&e, entry_index, if (entry_sig.results.len == 1) entry_sig.results[0] else null);
        errdefer alloc.free(body);
        const ti = try e.types.intern(&.{}, &.{});
        try e.bodies.append(alloc, body);
        try e.body_types.append(alloc, ti);
    }

    // ---- 6. The runtime, into the reserved slots.
    try emitHelpers(&e);

    return assemble(&e, start_index);
}

// ---------------------------------------------------------------------------
// BASIC BLOCKS
// ---------------------------------------------------------------------------

const Flat = struct {
    instrs: []const dnir.Instr,
    /// Sorted, deduplicated leader indices.
    leaders: []const u32,

    fn blockOfLeader(self: Flat, target: u32) ?u32 {
        for (self.leaders, 0..) |l, i| {
            if (l == target) return @intCast(i);
        }
        return null;
    }
};

fn flatten(e: *Emitter, f: dnir.Function) Error![]dnir.Instr {
    var out: std.ArrayListUnmanaged(dnir.Instr) = .empty;
    errdefer out.deinit(e.alloc);
    for (f.blocks) |b| try out.appendSlice(e.alloc, b.instrs);
    return out.toOwnedSlice(e.alloc);
}

/// A leader is instruction 0, any branch target, and any instruction following a
/// `br`. Nothing else can be entered from more than one place, because DNIR has
/// no other control transfer.
fn leadersOf(e: *Emitter, instrs: []const dnir.Instr) Error![]u32 {
    var set: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer set.deinit(e.alloc);
    try set.put(e.alloc, 0, {});
    // The one-past-the-end sentinel is a legal target — `compileDnirFunction`
    // documents it as fall-through past an `if` block — so it gets a block of
    // its own.
    try set.put(e.alloc, @intCast(instrs.len), {});
    for (instrs, 0..) |ins, i| {
        if (ins.op != .br) continue;
        if (ins.branch_target > instrs.len) return e.refuse("branch-target-out-of-range");
        try set.put(e.alloc, ins.branch_target, {});
        try set.put(e.alloc, @intCast(i + 1), {});
    }
    var list: std.ArrayListUnmanaged(u32) = .empty;
    errdefer list.deinit(e.alloc);
    var it = set.keyIterator();
    while (it.next()) |k| try list.append(e.alloc, k.*);
    std.mem.sort(u32, list.items, {}, comptime std.sort.asc(u32));
    return list.toOwnedSlice(e.alloc);
}

// ---------------------------------------------------------------------------
// FUNCTION BODY
// ---------------------------------------------------------------------------

fn maxSlotOf(instrs: []const dnir.Instr, nparams: usize) u32 {
    var max_slot: u32 = if (nparams == 0) 0 else @intCast(nparams - 1);
    for (instrs) |ins| {
        // `mov_arg .result` is an ABI REGISTER NUMBER, not a slot. Counting it
        // would both oversize the frame and, worse, suggest slot 3 and argument
        // register 3 are the same storage. They are not.
        if (ins.op != .mov_arg and ins.op != .fp_mov_arg) {
            if (ins.result) |r| max_slot = @max(max_slot, r);
        }
        for ([_]dnir.Value{ ins.lhs, ins.rhs, ins.third }) |v| {
            switch (v) {
                .local, .temp => |s| max_slot = @max(max_slot, s),
                else => {},
            }
        }
        for (ins.vals) |v| {
            switch (v) {
                .local, .temp => |s| max_slot = @max(max_slot, s),
                else => {},
            }
        }
    }
    return max_slot;
}

fn freeFieldLocals(e: *Emitter) void {
    var it = e.field_local.keyIterator();
    while (it.next()) |k| e.alloc.free(k.*);
    e.field_local.clearRetainingCapacity();
}

fn fieldKey(e: *Emitter, base: []const u8, field: []const u8) Error![]u8 {
    return std.fmt.allocPrint(e.alloc, "{s}.{s}", .{ base, field }) catch error.OutOfMemory;
}

/// The local holding `base.field`. Refuses rather than inventing one: a read of
/// a key nothing defined is the AArch64 backend's `undefinedKey`, and answering
/// it with a zero would turn a shape this file has not been taught into a
/// plausible wrong answer.
fn fieldLocal(e: *Emitter, base: []const u8, field: []const u8) Error!u32 {
    const key = try fieldKey(e, base, field);
    defer e.alloc.free(key);
    return e.field_local.get(key) orelse e.refuse("record-field-undefined");
}

/// One local per `base.field` a call or an `init_record` DEFINES. Reads are not
/// enough to create one — see `fieldLocal`.
fn planFieldLocals(e: *Emitter, instrs: []const dnir.Instr, first: u32) Error!u32 {
    freeFieldLocals(e);
    var next = first;
    for (instrs) |ins| {
        switch (ins.op) {
            .call_direct, .call_extern, .init_record => {},
            else => continue,
        }
        if (ins.record.len == 0) continue;
        const rec = dnir.findRecord(e.module, ins.record) orelse return e.refuse("record-unknown");
        const base = if (ins.field.len > 0) ins.field else "rec";
        for (rec.kinds) |k| {
            if (k == .f64) return e.refuse("record-f64-field");
        }
        for (rec.fields) |fname| {
            const key = try fieldKey(e, base, fname);
            const got = try e.field_local.getOrPut(e.alloc, key);
            if (got.found_existing) {
                e.alloc.free(key);
                continue;
            }
            got.value_ptr.* = next;
            next += 1;
        }
    }
    return next;
}

fn emitFunctionBody(e: *Emitter, f: dnir.Function) Error![]u8 {
    e.cur_name = f.name;
    e.cur_ret = f.ret;
    const sig = e.func_sig.get(f.name) orelse return e.refuse("missing-signature");
    e.cur_results = sig.results;
    for (f.params) |p| {
        if (p.record != null) return e.refuse("record-param");
    }

    const instrs = try flatten(e, f);
    defer e.alloc.free(instrs);
    const leaders = try leadersOf(e, instrs);
    defer e.alloc.free(leaders);
    const flat = Flat{ .instrs = instrs, .leaders = leaders };

    try computeSlotTypes(e, instrs, sig.params);
    e.slot_count = maxSlotOf(instrs, sig.params.len) + 1;

    const n_slots = e.slot_count;
    e.scratch_i32 = n_slots;
    e.scratch_a = n_slots + 1;
    e.scratch_b = n_slots + 2;
    e.scratch_c = n_slots + 3;
    e.scratch_d = n_slots + 4;
    e.pc_local = n_slots + 5;
    e.frame_local = n_slots + 6;
    const n_field_locals = try planFieldLocals(e, instrs, n_slots + 7) - (n_slots + 7);

    // Frame layout for `alloc_slots`, assigned ONCE here. Reserving where the
    // table is produced re-executes on each loop iteration and walks the stack
    // pointer down a frame per iteration — the defect the AArch64 prologue
    // comment records.
    e.frame_off.clearRetainingCapacity();
    e.frame_bytes = 0;
    for (instrs) |ins| {
        if (ins.op != .alloc_slots) continue;
        if (ins.aggregate) |aggregate| {
            if (e.dense_addr.contains(aggregate)) continue;
        }
        const t = ins.result orelse return e.refuse("alloc-slots-no-result");
        const n = switch (ins.lhs) {
            .i64 => |v| v,
            else => return e.refuse("alloc-slots-dynamic-count"),
        };
        if (n < 0 or n > (1 << 16)) return e.refuse("alloc-slots-count-range");
        if (e.frame_off.contains(t)) continue;
        try e.frame_off.put(e.alloc, t, e.frame_bytes);
        e.frame_bytes += @as(u32, @intCast(n)) * 8;
    }
    e.frame_bytes = (e.frame_bytes + 15) & ~@as(u32, 15);

    var b = Buf{ .alloc = e.alloc };
    errdefer b.deinit();

    // ---- locals. Params are 0..P-1 and are not declared here.
    var decls: std.ArrayListUnmanaged(struct { n: u32, t: u8 }) = .empty;
    defer decls.deinit(e.alloc);
    {
        var i: u32 = @intCast(sig.params.len);
        while (i < n_slots) {
            const t = slotValType(slotTypeOf(e, i));
            var j = i;
            while (j < n_slots and slotValType(slotTypeOf(e, j)) == t) j += 1;
            try decls.append(e.alloc, .{ .n = j - i, .t = t });
            i = j;
        }
        try decls.append(e.alloc, .{ .n = 1, .t = vt_i32 }); // scratch_i32
        try decls.append(e.alloc, .{ .n = 4, .t = vt_i64 }); // scratch_a, scratch_b, scratch_c, scratch_d
        try decls.append(e.alloc, .{ .n = 1, .t = vt_i32 }); // pc
        try decls.append(e.alloc, .{ .n = 1, .t = vt_i32 }); // frame
        if (n_field_locals > 0) try decls.append(e.alloc, .{ .n = n_field_locals, .t = vt_i64 });
    }
    try b.u32v(@intCast(decls.items.len));
    for (decls.items) |d| {
        try b.u32v(d.n);
        try b.byte(d.t);
    }

    // ---- prologue: claim the frame.
    if (e.frame_bytes > 0) {
        try b.byte(op_global_get);
        try b.u32v(0);
        try b.i32c(@intCast(e.frame_bytes));
        try b.op(op_i32_sub);
        try b.tee(e.frame_local);
        try b.byte(op_global_set);
        try b.u32v(0);
    }

    var has_branch = false;
    for (instrs) |ins| {
        if (ins.op == .br) has_branch = true;
    }

    e.in_dispatch = has_branch;
    if (!has_branch) {
        e.pending_n = 0;
        for (instrs) |ins| try emitInstr(e, &b, ins, flat);
        // A DNIR function terminates on `ret`; falling off the end is what the
        // AArch64 backend refuses at the same point. This traps rather than
        // returning whatever the stack held.
        try b.byte(op_unreachable);
    } else {
        try emitDispatch(e, &b, flat);
    }

    try b.byte(op_end);
    return b.items.toOwnedSlice(e.alloc);
}

/// THE DISPATCH LOOP. See the file header for why this shape and not a relooper.
///
///     block                      ; $exit
///       loop                     ; $again
///         block … block          ; n of them, B0 innermost
///           br_table [0…n-1] 0 (local.get $pc)
///         end   ; body of B0
///         end   ; body of B1
///         …
///         end   ; body of B{n-1}
///         br $again
///       end
///     end
///     unreachable
///
/// From inside the body of block k, exactly (n-1-k) of the n blocks are still
/// open, so `$again` sits at depth (n-1-k). That number is the whole correctness
/// of the construction and is computed in one place, `e.again_depth`.
fn emitDispatch(e: *Emitter, b: *Buf, flat: Flat) Error!void {
    const n: u32 = @intCast(flat.leaders.len);
    e.n_blocks = n;

    try b.byte(op_block);
    try b.byte(bt_void);
    try b.byte(op_loop);
    try b.byte(bt_void);

    var i: u32 = 0;
    while (i < n) : (i += 1) {
        try b.byte(op_block);
        try b.byte(bt_void);
    }
    // ONE `br_table`. The first version of this file used a chain of `i32.eq` /
    // `br_if` and justified it as buying portability to this project's own
    // engine (`tools/wasm/src/engine.id`), which refused opcode 0x0E on an
    // earlier build. THAT JUSTIFICATION WAS MEASURED AND IT WAS FALSE: swept
    // over all 142 agreeing modules, the two forms give the ENGINE THE SAME
    // COVERAGE — 127 agree, 12 refused by an engine limit, 3 timeouts, for both.
    // The 2 modules the table form loses to `br_table` are the same 2 the chain
    // form loses to `br_if`. The chain bought nothing and cost 73 bytes on the
    // benchmark below (2861 against 2788) at identical wall time (0.07 s each,
    // best of 7, same run).
    //
    // Cycles are the tiebreaker, so: the smaller one, and no chain to walk when
    // a function does have many blocks. Only a loop BACK EDGE reaches this
    // dispatch at all — fall-through and every forward jump leave it entirely
    // (see the two rules below) — so this is the cold path either way, which is
    // exactly why the byte count is what decides it.
    //
    // Label k is the block whose body follows the (k+1)-th `end`. The default
    // arm is block 0; `pc` is only ever written by this file.
    try b.get(e.pc_local);
    try b.byte(op_br_table);
    try b.u32v(n);
    var k: u32 = 0;
    while (k < n) : (k += 1) try b.u32v(k);
    try b.u32v(0);

    var blk: u32 = 0;
    while (blk < n) : (blk += 1) {
        try b.byte(op_end);
        e.cur_block = blk;
        e.again_depth = n - 1 - blk;
        e.pending_n = 0;
        const start = flat.leaders[blk];
        const stop = if (blk + 1 < n) flat.leaders[blk + 1] else @as(u32, @intCast(flat.instrs.len));
        var idx = start;
        var terminated = false;
        while (idx < stop) : (idx += 1) {
            const ins = flat.instrs[idx];
            try emitInstr(e, b, ins, flat);
            if (ins.op == .ret or ins.op == .ret_record) terminated = true;
            if (ins.op == .br and ins.branch_condition == .unconditional) terminated = true;
        }
        if (!terminated) {
            // FALL-THROUGH IS FREE AND WAS BEING PAID FOR. The body of block k
            // sits immediately inside block k+1, so running off its end hits
            // `end $B{k+1}` and continues into the body of block k+1 — which is
            // exactly the successor. This used to emit `pc = k+1; br $again`
            // and then walk the dispatch chain to arrive at the instruction it
            // was already standing next to: three instructions plus k+2
            // compares, on the most common edge in the program.
            if (blk + 1 >= n) try b.byte(op_unreachable);
        }
    }

    try b.byte(op_br);
    try b.u32v(0); // $again — all n blocks are closed here
    try b.byte(op_end); // loop
    try b.byte(op_end); // $exit
    try b.byte(op_unreachable);
}

/// A FORWARD JUMP NEEDS NO DISPATCH AT ALL. From the body of block k the blocks
/// B{k+1}..B{n-1} are still open, innermost first, so `br d` lands on the body
/// of block `k + 1 + d` — the target itself. Every `if`-skip and every `break`
/// in the corpus is one of these, and each used to cost `i32.const` +
/// `local.set` + `br` + a walk of the dispatch chain to reach a label that was
/// already in scope.
///
/// Only a BACK EDGE — a target at or before the current block — still needs the
/// `pc` round trip, because its label has already been closed.
fn forwardDepth(e: *const Emitter, target_block: u32) ?u32 {
    if (target_block <= e.cur_block) return null;
    return target_block - e.cur_block - 1;
}

/// The back-edge form: publish the target and re-enter the dispatch. `bias` is
/// the number of labels opened between the enclosing dispatch block and this
/// branch.
fn emitGotoBlock(e: *Emitter, b: *Buf, block_index: u32, bias: u32) Error!void {
    try b.i32c(@intCast(block_index));
    try b.set(e.pc_local);
    try b.byte(op_br);
    try b.u32v(e.again_depth + bias);
}

// ---------------------------------------------------------------------------
// VALUES
// ---------------------------------------------------------------------------

fn pushValue(e: *Emitter, b: *Buf, v: dnir.Value, want: SlotType) Error!void {
    switch (want) {
        .i64 => switch (v) {
            .i64 => |n| try b.i64c(n),
            // The AArch64 path materializes an f64 literal's BIT PATTERN into a
            // general register in exactly this position (`evalDnirValue`), and
            // `print_value` reads it back the same way.
            .f64 => |x| try b.i64c(@bitCast(x)),
            .str => |s| try b.i64c(@intCast(try e.strings.intern(s))),
            .local, .temp => |s| {
                if (s >= e.slot_count) return e.refuse("slot-out-of-range");
                // float -> int is NOT symmetric with the widening below and must
                // not be added: it truncates silently. `evalDnirValueFp` in the
                // AArch64 backend says the same at gap[101].
                if (slotTypeOf(e, s) == .f64) return e.refuse("f64-slot-in-integer-position");
                try b.get(s);
            },
            .void => return e.refuse("void-operand"),
            .record => return e.refuse("record-operand"),
        },
        .f64 => switch (v) {
            .f64 => |x| try b.f64c(x),
            // An integer immediate in a float position is a LOSSLESS WIDENING —
            // `scvtf` on AArch64, `f64.convert_i64_s` here.
            .i64 => |n| {
                try b.i64c(n);
                try b.op(op_f64_convert_i64_s);
            },
            .local, .temp => |s| {
                if (s >= e.slot_count) return e.refuse("slot-out-of-range");
                try b.get(s);
                if (slotTypeOf(e, s) == .i64) try b.op(op_f64_convert_i64_s);
            },
            .str => return e.refuse("str-in-float-position"),
            .void => return e.refuse("void-operand"),
            .record => return e.refuse("record-operand"),
        },
    }
}

/// Push a value already knowing the slot type it must land in.
fn pushValueTyped(e: *Emitter, b: *Buf, v: dnir.Value, dest: SlotType) Error!void {
    try pushValue(e, b, v, dest);
}

/// `str`/pointer operand as a wasm32 address.
fn pushAddr(e: *Emitter, b: *Buf, v: dnir.Value) Error!void {
    try pushValue(e, b, v, .i64);
    try b.op(op_i32_wrap_i64);
}

/// The DECLARED width of a result applies at the store, exactly as the C backend
/// spells `x = ((uint32_t)(expr))` on every assignment to a narrow binding.
fn emitNarrowFit(b: *Buf, ty: RT) Error!void {
    const fit = dnir_lower.narrowFit(ty) orelse return;
    if (fit.signed) {
        try b.op(switch (fit.bits) {
            8 => op_i64_extend8_s,
            16 => op_i64_extend16_s,
            else => op_i64_extend32_s,
        });
    } else {
        const mask: i64 = switch (fit.bits) {
            8 => 0xff,
            16 => 0xffff,
            else => 0xffff_ffff,
        };
        try b.i64c(mask);
        try b.op(op_i64_and);
    }
}

// ---------------------------------------------------------------------------
// INSTRUCTIONS
// ---------------------------------------------------------------------------

fn emitInstr(e: *Emitter, b: *Buf, ins: dnir.Instr, flat: Flat) Error!void {
    // The op is recorded before the arms run so that a refusal raised deep in a
    // shared helper — `pushValue` sees a `.void` operand from a dozen different
    // places — still names the instruction that asked for it. A note of
    // "void-operand" alone cost an hour.
    e.cur_op = ins.op;
    switch (ins.op) {
        .@"const" => {
            const t = ins.result orelse return;
            const want = slotTypeOf(e, t);
            try pushValueTyped(e, b, ins.lhs, want);
            if (want == .i64) try emitNarrowFit(b, ins.ty);
            try b.set(t);
        },

        .store_local => {
            const t = ins.result orelse {
                // A store with no destination is a discarded value. It cannot
                // have an effect of its own — every effectful op names one — so
                // there is nothing to emit.
                return;
            };
            const want = slotTypeOf(e, t);
            try pushValueTyped(e, b, ins.lhs, want);
            if (want == .i64) try emitNarrowFit(b, ins.ty);
            try b.set(t);
        },

        .binop => try emitBinop(e, b, ins),

        .br => {
            if (!e.in_dispatch) return e.refuse("branch-outside-dispatch");
            const target_block = flat.blockOfLeader(ins.branch_target) orelse
                return e.refuse("branch-target-not-a-leader");
            switch (ins.branch_condition) {
                .unconditional => {
                    if (forwardDepth(e, target_block)) |d| {
                        try b.byte(op_br);
                        try b.u32v(d);
                    } else {
                        try emitGotoBlock(e, b, target_block, 0);
                    }
                },
                .when_true, .when_false => {
                    // The condition is a MATERIALIZED BOOLEAN; compare the value
                    // rather than reusing flags from its producer, which is what
                    // the AArch64 arm does with `cmp #0`.
                    //
                    // `br_if`, NOT `if`/`br`. The `if` form costs a label, a
                    // block entry and an extra branch, and it opened a depth
                    // that a `br` inside it then had to compensate for — an
                    // off-by-one that sent `fib` to the sentinel block and
                    // trapped. Publishing `pc` BEFORE the test rather than
                    // inside it is what removes the label: `pc` is dead on every
                    // path that does not take the branch, because every
                    // `br $again` in this file writes it immediately first.
                    if (forwardDepth(e, target_block)) |d| {
                        try pushBranchCondition(e, b, ins);
                        try b.byte(op_br_if);
                        try b.u32v(d);
                    } else {
                        try b.i32c(@intCast(target_block));
                        try b.set(e.pc_local);
                        try pushBranchCondition(e, b, ins);
                        try b.byte(op_br_if);
                        try b.u32v(e.again_depth);
                    }
                },
            }
        },

        .ret => {
            if (e.cur_results.len > 1) return e.refuse("scalar-ret-from-record-relation");
            if (e.cur_results.len == 1) {
                const want = e.cur_results[0];
                if (ins.lhs == .void) {
                    // A VALUELESS RETURN OUT OF A VALUE-RETURNING RELATION.
                    // `os.exit(1)` as a path's last statement lowers to
                    // `call_extern exit` then `ret .void`, and the AArch64 arm
                    // answers it with `allocReg()` — an UNDEFINED register whose
                    // contents cannot be read, because the path is dead. Zero is
                    // the same nothing, said deterministically.
                    if (want == .f64) try b.f64c(0) else try b.i64c(0);
                } else if (want == .i64) {
                    try pushValue(e, b, ins.lhs, .i64);
                    try emitNarrowFit(b, e.cur_ret);
                } else {
                    try pushValue(e, b, ins.lhs, .f64);
                }
            }
            try emitFrameRestore(e, b);
            try b.byte(op_return);
        },

        .mov_arg, .fp_mov_arg => {
            const idx = ins.result orelse return e.refuse("mov-arg-no-index");
            if (std.mem.eql(u8, ins.field, "vararg")) {
                if (idx >= max_varargs) return e.refuse("vararg-index-range");
                e.pending_va[idx] = ins.lhs;
                if (idx + 1 > e.pending_va_n) e.pending_va_n = idx + 1;
                return;
            }
            if (idx >= e.pending.len) return e.refuse("mov-arg-index-range");
            e.pending[idx] = ins.lhs;
            if (idx + 1 > e.pending_n) e.pending_n = idx + 1;
        },

        .call_direct => try emitCallDirect(e, b, ins),
        .call_extern => try emitCallExtern(e, b, ins),

        .print_value => try emitPrint(e, b, ins),

        .str_len => {
            const t = ins.result orelse return e.refuse("str-len-no-result");
            try pushValue(e, b, ins.lhs, .i64);
            try b.call(helperIndex(.strlen));
            try b.set(t);
        },

        .alloc_slots => {
            const t = ins.result orelse return e.refuse("alloc-slots-no-result");
            if (ins.aggregate) |aggregate| {
                if (e.dense_addr.get(aggregate)) |address| {
                    try b.i64c(address);
                    try b.set(t);
                    return;
                }
            }
            const off = e.frame_off.get(t) orelse return e.refuse("alloc-slots-unplanned");
            try b.get(e.frame_local);
            try b.i32c(@intCast(off));
            try b.op(op_i32_add);
            try b.op(op_i64_extend_i32_u);
            try b.set(t);
        },

        .load_index => {
            const t = ins.result orelse return e.refuse("load-index-no-result");
            try emitIndexAddress(e, b, ins);
            if (ins.ty == .i64) {
                try b.mem(op_i64_load, 3, 0);
            } else {
                // `string.byte(s, i)`: Idol indexes strings from 1, C pointers
                // from 0, and the byte is zero-extended exactly as `ldrb` does.
                try b.mem(op_i64_load8_u, 0, 0);
            }
            try b.set(t);
        },

        .store_index => {
            try emitIndexAddress(e, b, ins);
            try pushValue(e, b, ins.third, .i64);
            if (ins.ty == .i64) {
                try b.mem(op_i64_store, 3, 0);
            } else {
                try b.mem(op_i64_store8, 0, 0);
            }
        },

        .load_global => {
            const t = ins.result orelse return e.refuse("load-global-no-result");
            if (ins.field.len == 0) return e.refuse("load-global-unnamed");
            const off = e.globals.get(ins.field) orelse return e.refuse("load-global-unknown");
            try b.i32c(0);
            try b.mem(op_i64_load, 3, globals_base + off);
            if (slotTypeOf(e, t) == .f64) try b.op(op_f64_reinterpret_i64);
            try b.set(t);
        },

        .store_global => {
            if (ins.field.len == 0) return e.refuse("store-global-unnamed");
            const off = e.globals.get(ins.field) orelse return e.refuse("store-global-unknown");
            try b.i32c(0);
            if (valueIsF64(e, ins.lhs)) {
                try pushValue(e, b, ins.lhs, .f64);
                try b.op(op_i64_reinterpret_f64);
            } else {
                try pushValue(e, b, ins.lhs, .i64);
            }
            try b.mem(op_i64_store, 3, globals_base + off);
        },

        // A fence and a spin hint are both no-ops in a single-threaded module.
        // They are ACCEPTED rather than refused because their meaning — "no
        // reordering is required beyond what the engine already guarantees" — is
        // satisfied by emitting nothing, and refusing would drop a program that
        // is entirely correct here.
        .hw_fence, .hw_spin => {},

        .hw_unary => try emitHwUnary(e, b, ins),

        // A RECORD LITERAL's `init_record` carries no base name and DEFINES
        // NOTHING: its fields already live in ordinary slots under `x.a`
        // (`dnir_lower` :4317, :4415). One that DOES carry a base follows a
        // record-returning call, and that call has already published every
        // field — the AArch64 arm re-copies x0..x7 there because the registers
        // still hold them; there is no second copy to make here.
        .init_record => {},

        .load_field => {
            const t = ins.result orelse return e.refuse("load-field-no-result");
            const base = if (ins.req_alias.len > 0) ins.req_alias else "rec";
            const local = try fieldLocal(e, base, ins.field);
            try b.get(local);
            try b.set(t);
        },

        .ret_record => {
            // EVERY DECLARED FIELD, in descriptor order. `lhs`/`rhs`/`third`
            // mirror the first three for older consumers and CANNOT express a
            // fourth — a 5-field record return wrote x0..x2 on AArch64 and left
            // the caller reading whatever x3/x4 held until `vals` existed. Read
            // `vals`.
            // `three` is declared in the ARM, not in the block below: a slice
            // of a block-scoped array outlives the array.
            var three: [3]dnir.Value = .{ ins.lhs, ins.rhs, ins.third };
            const vals = if (ins.vals.len > 0) ins.vals else blk: {
                var n: usize = 0;
                while (n < 3 and three[n] != .void) n += 1;
                break :blk three[0..n];
            };
            if (vals.len != e.cur_results.len) return e.refuse("ret-record-arity");
            for (vals) |v| try pushValue(e, b, v, .i64);
            try emitFrameRestore(e, b);
            try b.byte(op_return);
        },

        // NOT an exhaustive switch, deliberately. `native_ir.Op` gains members
        // while other lanes are working (`store_global` arrived mid-write), and
        // an exhaustive switch here turns their commit into a build break in a
        // file they do not own. An unknown op REFUSES, by name, which is the
        // same answer this file gives for any construct it cannot realize.
        else => return e.refuse(@tagName(ins.op)),
    }
}

/// A memarg offset is an IMMEDIATE and a wasm body carries no relocations, so
/// the globals region cannot be placed after a string pool whose size is only
/// known once every body has been walked. It is placed at a FIXED address
/// instead: the pool is capped, the globals begin at the cap, and a pool that
/// would overflow is REFUSED in `assemble` rather than silently overlapping the
/// globals it would then corrupt.
const string_pool_cap: u32 = 1 << 18;
const globals_base: u32 = addr_data + string_pool_cap;
const globals_cap: u32 = 1 << 16;
const dense_base: u32 = globals_base + globals_cap;
const dense_cap: u32 = 1 << 20;

fn emitFrameRestore(e: *Emitter, b: *Buf) Error!void {
    if (e.frame_bytes == 0) return;
    try b.get(e.frame_local);
    try b.i32c(@intCast(e.frame_bytes));
    try b.op(op_i32_add);
    try b.byte(op_global_set);
    try b.u32v(0);
}

/// `base + (index - 1) * width`, the one index origin both faces of a positional
/// table share. Leaves an i32 address on the stack.
fn emitIndexAddress(e: *Emitter, b: *Buf, ins: dnir.Instr) Error!void {
    const scale: i32 = if (ins.ty == .i64) 8 else 1;
    try pushAddr(e, b, ins.lhs);
    try pushValue(e, b, ins.rhs, .i64);
    try b.op(op_i32_wrap_i64);
    try b.i32c(1);
    try b.op(op_i32_sub);
    if (scale != 1) {
        try b.i32c(scale);
        try b.op(op_i32_mul);
    }
    try b.op(op_i32_add);
}

fn emitBinop(e: *Emitter, b: *Buf, ins: dnir.Instr) Error!void {
    const t = ins.result orelse return e.refuse("binop-no-result");
    const f64_operands = ins.ty == .f64 or valueIsF64(e, ins.lhs) or valueIsF64(e, ins.rhs);

    if (comparisonOf(ins.binop)) |int_op| {
        // A COMPARISON ANSWERS 0 OR 1 and is never refitted, whatever the width
        // of its operands — `emitCompareOrBinop` says the same.
        if (f64_operands) {
            try pushValue(e, b, ins.lhs, .f64);
            try pushValue(e, b, ins.rhs, .f64);
            try b.op(comparisonOfF64(ins.binop).?);
        } else {
            try pushValue(e, b, ins.lhs, .i64);
            try pushValue(e, b, ins.rhs, .i64);
            try b.op(int_op);
        }
        try b.op(op_i64_extend_i32_u);
        try b.set(t);
        return;
    }

    if (f64_operands) {
        try pushValue(e, b, ins.lhs, .f64);
        try pushValue(e, b, ins.rhs, .f64);
        try b.op(switch (ins.binop) {
            .add => op_f64_add,
            .sub => op_f64_sub,
            .mul => op_f64_mul,
            .div => op_f64_div,
            else => return e.refuse("f64-binop"),
        });
        try b.set(t);
        return;
    }

    switch (ins.binop) {
        .div, .mod => {
            // AArch64 `sdiv` DOES NOT TRAP: division by zero answers 0, and
            // `INT64_MIN / -1` answers `INT64_MIN`. `i64.div_s` traps on both.
            // Reproducing the AArch64 answer exactly is not an optimization
            // question — the exit code is this subset's only observable, and a
            // trap where the native build returns a number is a differing answer.
            //
            //   div: b == 0 -> 0 ; b == -1 -> 0 - a ; else a / b
            //   mod: b == 0 -> a ; b == -1 -> 0     ; else a % b
            //
            // The `mod` column follows from the AArch64 expansion `a - (a/b)*b`
            // with the two special quotients above substituted in.
            try pushValue(e, b, ins.lhs, .i64);
            try b.set(e.scratch_a);
            try pushValue(e, b, ins.rhs, .i64);
            try b.set(e.scratch_b);

            try b.get(e.scratch_b);
            try b.op(op_i64_eqz);
            try b.byte(op_if);
            try b.byte(vt_i64);
            if (ins.binop == .div) {
                try b.i64c(0);
            } else {
                try b.get(e.scratch_a);
            }
            try b.byte(op_else);
            try b.get(e.scratch_b);
            try b.i64c(-1);
            try b.op(op_i64_eq);
            try b.byte(op_if);
            try b.byte(vt_i64);
            if (ins.binop == .div) {
                try b.i64c(0);
                try b.get(e.scratch_a);
                try b.op(op_i64_sub);
            } else {
                try b.i64c(0);
            }
            try b.byte(op_else);
            try b.get(e.scratch_a);
            try b.get(e.scratch_b);
            try b.op(if (ins.binop == .div) op_i64_div_s else op_i64_rem_s);
            if (ins.binop == .mod) {
                // THE FLOOR CORRECTION, so the two realizers answer one law.
                //
                // `i64.rem_s` is TRUNCATING — the remainder takes the sign of
                // the dividend — and `docs/rulings.md` rules Idol's `%`
                // FLOORED, taking the sign of the divisor. They agree exactly
                // when the operand signs agree, so:
                //
                //     r != 0 && (r ^ b) < 0   ->   r + b     else   r
                //
                // Written with `select` rather than a branch because both arms
                // are already on the stack and neither can trap.
                //
                // THE TWO SPECIAL ARMS ABOVE NEED NO CORRECTION and are
                // deliberately untouched: floored and truncating both answer 0
                // for `x % -1`, and the `b == 0` arm answers `a` in both,
                // because AArch64's `sdiv` yields quotient 0 there and the
                // correction's own `r == 0` select then keeps `a`. Checked
                // against the AArch64 sequence case by case, not assumed.
                try b.set(e.scratch_c);
                try b.get(e.scratch_c);
                try b.get(e.scratch_b);
                try b.op(op_i64_add);
                try b.get(e.scratch_c);
                try b.get(e.scratch_c);
                try b.i64c(0);
                try b.op(op_i64_ne);
                try b.get(e.scratch_c);
                try b.get(e.scratch_b);
                try b.op(op_i64_xor);
                try b.i64c(0);
                try b.op(op_i64_lt_s);
                try b.op(op_i32_and);
                try b.op(op_select);
            }
            try b.byte(op_end);
            try b.byte(op_end);
        },
        // `//` — FLOOR DIVISION, and it now ANSWERS instead of refusing by name.
        //
        // The refusal it replaces was the right state while the correction was
        // unwritten: `i64.div_s` is truncating, floor division is a different
        // value, and emitting the truncating one would have made this realizer
        // disagree with the AArch64 one on `(0-7) // 10` — 0 against -1 — which
        // is a silent wrong answer, the one outcome this surface does not
        // tolerate.
        //
        // THE THREE ARMS ARE MEASURED AGAINST THE AArch64 BUILD, NOT DERIVED
        // FROM THE C STANDARD. `--backend=direct`, one program, opaque operands
        // so nothing folds (idol 0f7d6d00):
        //
        //     7//2 -7//2 7//-2 -7//-2   ->   3 -4 -4  3
        //     6//3 -6//3 6//-3 -6//-3   ->   2 -2 -2  2      exact: no correction
        //     7//0 -7//0 0//0           ->   0 -1  0         a < 0 ? -1 : 0
        //     7//-1 -7//-1              ->  -7  7            0 - a
        //
        //   b == 0  -> a < 0 ? -1 : 0. NOT 0. AArch64's `sdiv` answers 0 there
        //             and the floor correction then fires on the nonzero
        //             remainder `a`, which is why the negative dividend lands on
        //             -1 and why copying `.div`'s `b == 0` arm would have been
        //             wrong in exactly one quadrant.
        //   b == -1 -> 0 - a. Division is exact, so floor and truncation agree,
        //             and INT64_MIN wraps to itself as it does on the chip.
        //   else    -> q = a/b, r = a%b, and q-1 when the remainder is nonzero
        //             and its sign differs from the divisor's — the same
        //             predicate `(r != 0) && ((r ^ b) < 0)` the `.mod` arm uses,
        //             because floored `%` and floored `//` are corrections of
        //             the same truncating pair and must fire together or the
        //             ruled identity `x == (x // y) * y + (x % y)` breaks.
        //
        // `select` rather than a branch: both arms are already on the stack and
        // neither can trap.
        .idiv => {
            try pushValue(e, b, ins.lhs, .i64);
            try b.set(e.scratch_a);
            try pushValue(e, b, ins.rhs, .i64);
            try b.set(e.scratch_b);

            try b.get(e.scratch_b);
            try b.op(op_i64_eqz);
            try b.byte(op_if);
            try b.byte(vt_i64);
            // b == 0: a < 0 ? -1 : 0
            try b.i64c(-1);
            try b.i64c(0);
            try b.get(e.scratch_a);
            try b.i64c(0);
            try b.op(op_i64_lt_s);
            try b.op(op_select);
            try b.byte(op_else);
            try b.get(e.scratch_b);
            try b.i64c(-1);
            try b.op(op_i64_eq);
            try b.byte(op_if);
            try b.byte(vt_i64);
            // b == -1: 0 - a
            try b.i64c(0);
            try b.get(e.scratch_a);
            try b.op(op_i64_sub);
            try b.byte(op_else);
            // q into scratch_c, r into scratch_d, then the floor correction.
            try b.get(e.scratch_a);
            try b.get(e.scratch_b);
            try b.op(op_i64_div_s);
            try b.set(e.scratch_c);
            try b.get(e.scratch_a);
            try b.get(e.scratch_b);
            try b.op(op_i64_rem_s);
            try b.set(e.scratch_d);
            try b.get(e.scratch_c);
            try b.i64c(1);
            try b.op(op_i64_sub);
            try b.get(e.scratch_c);
            try b.get(e.scratch_d);
            try b.i64c(0);
            try b.op(op_i64_ne);
            try b.get(e.scratch_d);
            try b.get(e.scratch_b);
            try b.op(op_i64_xor);
            try b.i64c(0);
            try b.op(op_i64_lt_s);
            try b.op(op_i32_and);
            try b.op(op_select);
            try b.byte(op_end);
            try b.byte(op_end);
        },
        else => {
            try pushValue(e, b, ins.lhs, .i64);
            try pushValue(e, b, ins.rhs, .i64);
            try b.op(switch (ins.binop) {
                .add => op_i64_add,
                .sub => op_i64_sub,
                .mul => op_i64_mul,
                .band => op_i64_and,
                .bor => op_i64_or,
                .bxor => op_i64_xor,
                // `lsl`/`lsr` register forms, so LOGICAL right shift — not
                // arithmetic. AArch64 masks the amount to 6 bits for a 64-bit
                // register and so does `i64.shl`/`i64.shr_u`.
                .shl => op_i64_shl,
                .shr => op_i64_shr_u,
                else => return e.refuse("binop"),
            });
        },
    }
    try emitNarrowFit(b, ins.ty);
    try b.set(t);
}

/// The branch condition as an i32 truth value.
fn pushBranchCondition(e: *Emitter, b: *Buf, ins: dnir.Instr) Error!void {
    try pushValue(e, b, ins.lhs, .i64);
    if (ins.branch_condition == .when_false) {
        try b.op(op_i64_eqz);
    } else {
        try b.i64c(0);
        try b.op(op_i64_ne);
    }
}

fn clearStaged(e: *Emitter) void {
    e.pending_n = 0;
    e.pending = @splat(null);
    e.pending_va_n = 0;
    e.pending_va = @splat(null);
}

fn emitHwUnary(e: *Emitter, b: *Buf, ins: dnir.Instr) Error!void {
    if (std.mem.eql(u8, ins.field, dnir_lower.index_bounds_tag)) {
        // ONE UNSIGNED COMPARE, exactly as the AArch64 fused form: `idx - 1`
        // read as unsigned is above `len - 1` for a zero or negative index as
        // well as for one past the end, so the two-sided check costs one
        // instruction. Out of range aborts, and `unreachable` is the engine's
        // abort — both exit 134.
        const len = switch (ins.rhs) {
            .i64 => |n| n,
            else => return e.refuse("index-bounds-extent"),
        };
        if (len < 1 or len > 4096) return e.refuse("index-bounds-range");
        try pushValue(e, b, ins.lhs, .i64);
        try b.i64c(1);
        try b.op(op_i64_sub);
        try b.i64c(len - 1);
        try b.op(op_i64_gt_u);
        try b.byte(op_if);
        try b.byte(bt_void);
        try b.byte(op_unreachable);
        try b.byte(op_end);
        return;
    }
    if (std.mem.eql(u8, ins.field, dnir_lower.trap_abort_tag)) {
        // `abort()` without a call. The AArch64 expansion raises SIGABRT so the
        // process exits 134; a wasm module has no signals, and `unreachable` is
        // the engine's own abort. The exit codes differ and that difference is
        // recorded in the coverage table rather than papered over.
        try b.byte(op_unreachable);
        return;
    }
    const t = ins.result orelse return e.refuse("hw-unary-no-result");
    try pushValue(e, b, ins.lhs, .i64);
    try b.op(switch (ins.hw) {
        .clz => op_i64_clz,
        .ctz => op_i64_ctz,
        .popcount => op_i64_popcnt,
        else => return e.refuse("hw-unary"),
    });
    try b.set(t);
}

/// Staged operands, in index order, for the call about to be emitted.
fn pushStagedArgs(e: *Emitter, b: *Buf, ins: dnir.Instr, want: []const SlotType) Error!void {
    if (ins.lhs != .void) {
        // The single-operand fast path: `dnir_lower` hands the lone argument back
        // as `.lhs` and emits no `mov_arg` at all.
        if (want.len != 1) return e.refuse("call-arity-lhs");
        if (e.pending_n != 0) return e.refuse("call-lhs-and-staged");
        try pushValueTyped(e, b, ins.lhs, want[0]);
        return;
    }
    if (e.pending_n != want.len) return e.refuse("call-arity");
    var i: u32 = 0;
    while (i < want.len) : (i += 1) {
        const v = e.pending[i] orelse return e.refuse("call-arg-gap");
        try pushValueTyped(e, b, v, want[i]);
    }
}

fn emitCallDirect(e: *Emitter, b: *Buf, ins: dnir.Instr) Error!void {
    const idx = e.func_index.get(ins.callee) orelse return e.refuse("call-target-unknown");
    const sig = e.func_sig.get(ins.callee) orelse return e.refuse("call-signature-unknown");
    try pushStagedArgs(e, b, ins, sig.params);
    clearStaged(e);
    try b.call(idx);
    try finishCallResult(e, b, ins, sig.results);
}

fn finishCallResult(e: *Emitter, b: *Buf, ins: dnir.Instr, results: []const SlotType) Error!void {
    // A RECORD RESULT lands as several values, and they come off the stack in
    // REVERSE declaration order — the last field is on top. Storing them
    // forwards would transpose the record, which is the same defect the AArch64
    // arm calls "a parallel move, not a sequential one".
    if (results.len > 1) {
        const base = if (ins.field.len > 0) ins.field else "rec";
        const rec = dnir.findRecord(e.module, ins.record) orelse return e.refuse("call-record-unknown");
        if (rec.fields.len != results.len) return e.refuse("call-record-arity");
        var i: usize = rec.fields.len;
        while (i > 0) {
            i -= 1;
            const local = try fieldLocal(e, base, rec.fields[i]);
            try b.set(local);
        }
        if (ins.result) |t| {
            // The record's own slot names the aggregate, which has no single
            // value here. `init_record` publishes the fields; the slot is only
            // ever an alias for the base name, so give it a defined zero rather
            // than leaving a wasm local read before it is written.
            try b.i64c(0);
            try b.set(t);
        }
        return;
    }
    if (ins.result) |t| {
        if (results.len == 0) return e.refuse("call-result-from-void");
        const want = slotTypeOf(e, t);
        if (results[0] != want) {
            if (results[0] == .i64 and want == .f64) {
                try b.op(op_f64_convert_i64_s);
            } else {
                return e.refuse("call-result-type");
            }
        }
        try b.set(t);
    } else if (results.len == 1) {
        try b.op(op_drop);
    }
}

const ExternSig = struct {
    params: []const SlotType,
    result: ?SlotType,
    helper: ?Helper = null,
    /// Emitted inline instead of as a call, when the operation IS one opcode.
    inline_op: ?u8 = null,
};

fn externSignature(callee: []const u8) ?ExternSig {
    const one_i = &[_]SlotType{.i64};
    const two_i = &[_]SlotType{ .i64, .i64 };
    const three_i = &[_]SlotType{ .i64, .i64, .i64 };
    const one_f = &[_]SlotType{.f64};
    if (std.mem.eql(u8, callee, "malloc")) return .{ .params = one_i, .result = .i64, .helper = .malloc };
    if (std.mem.eql(u8, callee, "memset")) return .{ .params = three_i, .result = .i64, .helper = .memset };
    if (std.mem.eql(u8, callee, "strlen")) return .{ .params = one_i, .result = .i64, .helper = .strlen };
    if (std.mem.eql(u8, callee, "strcmp")) return .{ .params = two_i, .result = .i64, .helper = .strcmp };
    if (std.mem.eql(u8, callee, "free")) return .{ .params = one_i, .result = null };
    if (std.mem.eql(u8, callee, "memcpy")) return .{ .params = three_i, .result = .i64, .helper = .memcpy };
    if (std.mem.eql(u8, callee, "idol_str_at")) return .{ .params = two_i, .result = .i64, .helper = .str_at };
    if (std.mem.eql(u8, callee, "duo_str_sub")) return .{ .params = three_i, .result = .i64, .helper = .str_sub };
    if (std.mem.eql(u8, callee, "duo_str_to_i64")) return .{ .params = one_i, .result = .i64, .helper = .str_to_i64 };
    if (std.mem.eql(u8, callee, "sqrt")) return .{ .params = one_f, .result = .f64, .inline_op = op_f64_sqrt };
    if (std.mem.eql(u8, callee, "fabs")) return .{ .params = one_f, .result = .f64, .inline_op = op_f64_abs };
    if (std.mem.eql(u8, callee, "floor")) return .{ .params = one_f, .result = .f64, .inline_op = op_f64_floor };
    if (std.mem.eql(u8, callee, "ceil")) return .{ .params = one_f, .result = .f64, .inline_op = op_f64_ceil };
    return null;
}

fn emitCallExtern(e: *Emitter, b: *Buf, ins: dnir.Instr) Error!void {
    if (ins.record.len > 0) return e.refuse("record-returning-extern");

    // `exit(n)` and `abort()` terminate; they are not calls with a result.
    if (std.mem.eql(u8, ins.callee, "exit")) {
        if (ins.lhs != .void) {
            try pushValue(e, b, ins.lhs, .i64);
        } else if (e.pending_n == 1) {
            try pushValue(e, b, e.pending[0].?, .i64);
        } else return e.refuse("exit-arity");
        clearStaged(e);
        try b.op(op_i32_wrap_i64);
        try b.call(helperIndex(.proc_exit));
        try b.byte(op_unreachable);
        return;
    }
    if (std.mem.eql(u8, ins.callee, "abort")) {
        try b.byte(op_unreachable);
        return;
    }

    if (std.mem.eql(u8, ins.callee, "snprintf")) return emitSnprintf(e, b, ins);
    if (std.mem.eql(u8, ins.callee, "printf")) return emitPrintf(e, b, ins);

    const sig = externSignature(ins.callee) orelse return externRefusal(e, ins.callee);
    if (e.pending_va_n != 0) return e.refuse("vararg-tail");
    try pushStagedArgs(e, b, ins, sig.params);
    clearStaged(e);
    if (sig.inline_op) |o| {
        try b.op(o);
    } else if (sig.helper) |h| {
        try b.call(helperIndex(h));
    } else {
        // A declared no-op with a value argument: drop it.
        var i: usize = 0;
        while (i < sig.params.len) : (i += 1) try b.op(op_drop);
    }
    var one: [1]SlotType = undefined;
    var n: usize = 0;
    if (sig.result) |r| {
        one[0] = r;
        n = 1;
    }
    try finishCallResult(e, b, ins, one[0..n]);
}

/// `snprintf(dst, cap, fmt, ...)` — the ONE variadic call this IR produces, and
/// the reason 30 corpus programs could not reach wasm at all: every `..` chain
/// and every `to(str)` of an integer goes through it (`dnir_lower.lowerConcatChain`,
/// `emitIntToStr`).
///
/// THE FORMAT IS A COMPILE-TIME CONSTANT, so its directives are CHECKED HERE
/// rather than trusted at run time. `dnir_lower` produces exactly three:
/// literal text, `%%`, `%s` and `%lld`. A format carrying anything else is a
/// lowering this file has not been taught, and it refuses by name instead of
/// letting a runtime walker print something plausible. The hole count is checked
/// against the staged tail for the same reason: `snprintf` reading one cell past
/// what was staged is exactly the defect `.field = "vararg"` exists to prevent.
fn checkFormat(e: *Emitter, fmt_val: dnir.Value) Error![]const u8 {
    const fmt = switch (fmt_val) {
        .str => |t| t,
        else => return e.refuse("format-not-constant"),
    };
    var holes: u32 = 0;
    var i: usize = 0;
    while (i < fmt.len) {
        if (fmt[i] != '%') {
            i += 1;
            continue;
        }
        if (i + 1 < fmt.len and fmt[i + 1] == '%') {
            i += 2;
            continue;
        }
        if (i + 1 < fmt.len and fmt[i + 1] == 's') {
            holes += 1;
            i += 2;
            continue;
        }
        if (i + 3 < fmt.len and std.mem.eql(u8, fmt[i + 1 ..][0..3], "lld")) {
            holes += 1;
            i += 4;
            continue;
        }
        return e.refuse("format-directive");
    }
    if (holes != e.pending_va_n) return e.refuse("format-hole-count");
    return fmt;
}

/// Stage the tail into the fixed cells the helper reads. One i64 per hole,
/// which is both a pointer and an integer here — the same 64-bit slot AArch64
/// pushes onto its own stack.
fn stageVarargs(e: *Emitter, b: *Buf) Error!void {
    var k: u32 = 0;
    while (k < e.pending_va_n) : (k += 1) {
        const v = e.pending_va[k] orelse return e.refuse("vararg-gap");
        try b.i32c(0);
        try pushValue(e, b, v, .i64);
        try b.mem(op_i64_store, 3, addr_varargs + k * 8);
    }
}

fn emitSnprintf(e: *Emitter, b: *Buf, ins: dnir.Instr) Error!void {
    if (ins.lhs != .void) return e.refuse("snprintf-lhs");
    if (e.pending_n != 3) return e.refuse("snprintf-arity");
    const fmt_val = e.pending[2] orelse return e.refuse("snprintf-no-format");
    _ = try checkFormat(e, fmt_val);
    try stageVarargs(e, b);
    try pushValue(e, b, e.pending[0].?, .i64);
    try pushValue(e, b, e.pending[1].?, .i64);
    try pushValue(e, b, fmt_val, .i64);
    try b.i64c(@intCast(addr_varargs));
    clearStaged(e);
    try b.call(helperIndex(.snprintf));
    try finishCallResult(e, b, ins, &[_]SlotType{.i64});
}

/// `printf(fmt, ...)` — `dnir_lower.lowerPrintConcat` hands the format as the
/// call's `.lhs` and stages every hole in the tail.
fn emitPrintf(e: *Emitter, b: *Buf, ins: dnir.Instr) Error!void {
    if (e.pending_n != 0) return e.refuse("printf-staged-fixed-args");
    if (ins.lhs == .void) return e.refuse("printf-no-format");
    _ = try checkFormat(e, ins.lhs);
    try stageVarargs(e, b);
    try pushValue(e, b, ins.lhs, .i64);
    try b.i64c(@intCast(addr_varargs));
    clearStaged(e);
    try b.call(helperIndex(.printf));
    if (ins.result != null) return e.refuse("printf-result-used");
}

/// The refusal note carries the SYMBOL, because "extern" alone cannot be acted
/// on and the coverage table is written from these notes.
fn externRefusal(e: *Emitter, callee: []const u8) Error {
    var buf: [80]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "extern:{s}", .{callee}) catch "extern";
    return e.refuse(text);
}

/// `print(v)` — the observable output edge, reproducing `native_backend`'s shape
/// table exactly:
///   `.str`  → puts(v)         (appends a newline; skipped entirely when null)
///   `.i64`  → printf("%lld\n", v)
///   void    → printf("\n")
/// and with `.field == "nonl"` (`stdout:write`) the same egress without the
/// line ending, where a valueless write is NOTHING AT ALL rather than an empty
/// call.
fn emitPrint(e: *Emitter, b: *Buf, ins: dnir.Instr) Error!void {
    // A byte sequence is not an integer-shaped pointer. Until the shared
    // carrier preserves base, extent, element law, and lifetime, the lawful
    // cross-backend result is the same named refusal as direct lowering.
    if (ins.byte_sequence) return e.refuse("print-byte-sequence");
    const nonl = std.mem.eql(u8, ins.field, "nonl");
    switch (ins.ty) {
        .str => {
            try pushValue(e, b, ins.lhs, .i64);
            try b.call(helperIndex(if (nonl) .write_cstr else .puts_cstr));
        },
        .i64, .i32, .u32, .u64, .i8, .i16, .u8, .u16, .bool => {
            try pushValue(e, b, ins.lhs, .i64);
            try b.i64c(if (nonl) 0 else 1);
            try b.call(helperIndex(.print_i64));
        },
        .f64 => return e.refuse("print-f64"),
        else => {
            if (nonl) return;
            try b.i64c(@intCast(try e.strings.intern("\n")));
            try b.call(helperIndex(.write_cstr));
        },
    }
}

test "wasm backend refuses byte-sequence print without an extent carrier" {
    var diagnostic: Diagnostic = .{};
    var emitter = Emitter{
        .alloc = std.testing.allocator,
        .diagnostic = &diagnostic,
        .module = .{ .functions = &.{}, .globals = &.{} },
        .types = .{ .alloc = std.testing.allocator },
        .strings = .{ .alloc = std.testing.allocator },
    };
    defer emitter.deinit();
    var buffer = Buf{ .alloc = std.testing.allocator };
    defer buffer.deinit();
    const instruction = dnir.Instr{
        .op = .print_value,
        .lhs = .{ .str = "abc" },
        .ty = .i64,
        .byte_sequence = true,
    };
    try std.testing.expectError(
        error.UnsupportedProgram,
        emitPrint(&emitter, &buffer, instruction),
    );
    try std.testing.expectEqualStrings("print-byte-sequence", diagnostic.note().?);
}

// ---------------------------------------------------------------------------
// `_start`
// ---------------------------------------------------------------------------

fn emitStart(e: *Emitter, entry_index: u32, entry_result: ?SlotType) Error![]u8 {
    e.cur_name = "_start";
    var b = Buf{ .alloc = e.alloc };
    errdefer b.deinit();
    try b.u32v(0); // no locals
    try b.call(entry_index);
    if (entry_result) |r| {
        // The exit code IS the answer for this subset — every gate on the
        // surface states its verdict that way — so `main`'s result must reach
        // `proc_exit` and not be dropped. WASI takes a 32-bit code and the
        // kernel takes the low 8 bits of it, which is exactly what the AArch64
        // build's `exit(main())` gets.
        if (r == .f64) {
            try b.op(op_i64_reinterpret_f64);
        }
        // `& 0xFF` — THE POSIX EXIT CONTRACT, not a convenience. The AArch64
        // build ends in `exit(main())` and the kernel keeps the LOW EIGHT BITS:
        // `main` returning 333 exits 77. Handing wasmtime the untruncated 333
        // did not merely differ from that, it made the module UNRUNNABLE — WASI
        // rejects any `proc_exit` argument outside [0,126) — so five corpus
        // programs whose native exit codes are perfectly ordinary (77, 5, 118,
        // 104) failed to produce an answer at all.
        try b.i64c(0xff);
        try b.op(op_i64_and);
        try b.op(op_i32_wrap_i64);
    } else {
        try b.i32c(0);
    }
    try b.call(helperIndex(.proc_exit));
    try b.byte(op_unreachable);
    try b.byte(op_end);
    return b.items.toOwnedSlice(e.alloc);
}

// ---------------------------------------------------------------------------
// THE RUNTIME
// ---------------------------------------------------------------------------

fn emitHelpers(e: *Emitter) Error!void {
    e.cur_name = "<runtime>";
    try putHelper(e, .strlen, &.{vt_i64}, &.{vt_i64}, helperStrlen);
    try putHelper(e, .write_bytes, &.{ vt_i64, vt_i64 }, &.{}, helperWriteBytes);
    try putHelper(e, .write_cstr, &.{vt_i64}, &.{}, helperWriteCstr);
    try putHelper(e, .puts_cstr, &.{vt_i64}, &.{}, helperPutsCstr);
    try putHelper(e, .print_i64, &.{ vt_i64, vt_i64 }, &.{}, helperPrintI64);
    try putHelper(e, .malloc, &.{vt_i64}, &.{vt_i64}, helperMalloc);
    try putHelper(e, .memset, &.{ vt_i64, vt_i64, vt_i64 }, &.{vt_i64}, helperMemset);
    try putHelper(e, .memcpy, &.{ vt_i64, vt_i64, vt_i64 }, &.{vt_i64}, helperMemcpy);
    try putHelper(e, .strcmp, &.{ vt_i64, vt_i64 }, &.{vt_i64}, helperStrcmp);
    try putHelper(e, .sn_put, &.{vt_i64}, &.{}, helperSnPut);
    try putHelper(e, .sn_puti, &.{vt_i64}, &.{}, helperSnPutI);
    try putHelper(e, .sn_format, &.{ vt_i64, vt_i64 }, &.{}, helperSnFormat);
    try putHelper(e, .snprintf, &.{ vt_i64, vt_i64, vt_i64, vt_i64 }, &.{vt_i64}, helperSnprintf);
    try putHelper(e, .printf, &.{ vt_i64, vt_i64 }, &.{}, helperPrintf);
    try putHelper(e, .str_at, &.{ vt_i64, vt_i64 }, &.{vt_i64}, helperStrAt);
    try putHelper(e, .str_sub, &.{ vt_i64, vt_i64, vt_i64 }, &.{vt_i64}, helperStrSub);
    try putHelper(e, .str_to_i64, &.{vt_i64}, &.{vt_i64}, helperStrToI64);
    try putHelper(e, .die, &.{vt_i64}, &.{}, helperDie);
}

// --- the snprintf cursor lives in module globals -----------------------------
// Three globals rather than three extra parameters on every helper: `sn_put` is
// called once per OUTPUT BYTE, and threading a cursor through it would make the
// call shape the expensive part. Not reentrant, and it does not need to be —
// every hole is already a computed value by the time staging begins, so one
// `snprintf` can never be inside another.
const g_sp: u32 = 0;
const g_heap: u32 = 1;
const g_sn_d: u32 = 2;
const g_sn_n: u32 = 3;
const g_sn_cap: u32 = 4;
/// Digit scratch for `sn_puti`, disjoint from the region `print_i64` writes
/// backwards from the top of.
const addr_snbuf: u32 = addr_numbuf;
const snbuf_end: u32 = addr_numbuf + 64;

fn gget(b: *Buf, g: u32) Error!void {
    try b.byte(op_global_get);
    try b.u32v(g);
}

fn gset(b: *Buf, g: u32) Error!void {
    try b.byte(op_global_set);
    try b.u32v(g);
}

/// One byte into the snprintf cursor. Written only when it FITS — `n + 1 < cap`
/// keeps room for the terminator and is false for `cap == 0`, which is exactly
/// the measuring call `lowerConcatChain` makes first.
fn helperSnPut(e: *Emitter, b: *Buf) Error!void {
    _ = e;
    try b.u32v(0);
    // STREAM MODE. `cap == -1` means the cursor is `printf`'s buffer rather
    // than a caller's: every byte is kept, and the buffer is handed to
    // `fd_write` whenever it fills. One host call per 4 KiB instead of one per
    // character, and no capacity to run out of.
    try gget(b, g_sn_cap);
    try b.i32c(-1);
    try b.op(op_i32_eq);
    try b.byte(op_if);
    try b.byte(bt_void);
    try gget(b, g_sn_d);
    try gget(b, g_sn_n);
    try b.op(op_i32_add);
    try b.get(0);
    try b.mem(op_i64_store8, 0, 0);
    try gget(b, g_sn_n);
    try b.i32c(1);
    try b.op(op_i32_add);
    try gset(b, g_sn_n);
    try gget(b, g_sn_n);
    try b.i32c(@intCast(outbuf_len));
    try b.op(op_i32_ge_s);
    try b.byte(op_if);
    try b.byte(bt_void);
    try gget(b, g_sn_d);
    try b.op(op_i64_extend_i32_u);
    try gget(b, g_sn_n);
    try b.op(op_i64_extend_i32_u);
    try b.call(helperIndex(.write_bytes));
    try b.i32c(0);
    try gset(b, g_sn_n);
    try b.byte(op_end);
    try b.byte(op_return);
    try b.byte(op_end);

    try gget(b, g_sn_n);
    try b.i32c(1);
    try b.op(op_i32_add);
    try gget(b, g_sn_cap);
    try b.op(op_i32_lt_s);
    try b.byte(op_if);
    try b.byte(bt_void);
    try gget(b, g_sn_d);
    try gget(b, g_sn_n);
    try b.op(op_i32_add);
    try b.get(0);
    try b.mem(op_i64_store8, 0, 0);
    try b.byte(op_end);
    try gget(b, g_sn_n);
    try b.i32c(1);
    try b.op(op_i32_add);
    try gset(b, g_sn_n);
}

/// One decimal integer into the same cursor. UNSIGNED digit arithmetic, for the
/// reason `print_i64` records: `-(INT64_MIN)` is still negative.
fn helperSnPutI(e: *Emitter, b: *Buf) Error!void {
    _ = e;
    // params: 0 v ; locals: 1 cur(i32), 2 neg(i32), 3 n(i64)
    try b.u32v(2);
    try b.u32v(2);
    try b.byte(vt_i32);
    try b.u32v(1);
    try b.byte(vt_i64);

    try b.i32c(@intCast(snbuf_end));
    try b.set(1);
    try b.get(0);
    try b.i64c(0);
    try b.op(op_i64_lt_s);
    try b.set(2);
    try b.get(2);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.i64c(0);
    try b.get(0);
    try b.op(op_i64_sub);
    try b.set(3);
    try b.byte(op_else);
    try b.get(0);
    try b.set(3);
    try b.byte(op_end);

    try b.byte(op_loop);
    try b.byte(bt_void);
    try b.get(1);
    try b.i32c(1);
    try b.op(op_i32_sub);
    try b.tee(1);
    try b.get(3);
    try b.i64c(10);
    try b.op(op_i64_rem_u);
    try b.i64c('0');
    try b.op(op_i64_add);
    try b.mem(op_i64_store8, 0, 0);
    try b.get(3);
    try b.i64c(10);
    try b.op(op_i64_div_u);
    try b.tee(3);
    try b.i64c(0);
    try b.op(op_i64_ne);
    try b.byte(op_br_if);
    try b.u32v(0);
    try b.byte(op_end);

    try b.get(2);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.get(1);
    try b.i32c(1);
    try b.op(op_i32_sub);
    try b.tee(1);
    try b.i64c('-');
    try b.mem(op_i64_store8, 0, 0);
    try b.byte(op_end);

    // Replay the digits through `sn_put`, so capacity is honoured one byte at a
    // time and the measuring call still counts them all.
    try b.byte(op_block);
    try b.byte(bt_void);
    try b.byte(op_loop);
    try b.byte(bt_void);
    try b.get(1);
    try b.i32c(@intCast(snbuf_end));
    try b.op(op_i32_lt_u);
    try b.op(op_i32_eqz);
    try b.byte(op_br_if);
    try b.u32v(1);
    try b.get(1);
    try b.mem(op_i64_load8_u, 0, 0);
    try b.call(helperIndex(.sn_put));
    try b.get(1);
    try b.i32c(1);
    try b.op(op_i32_add);
    try b.set(1);
    try b.byte(op_br);
    try b.u32v(0);
    try b.byte(op_end);
    try b.byte(op_end);
}

/// `snprintf(dst, cap, fmt, va)` over the three directives `dnir_lower` emits.
/// Returns the length the answer NEEDS, excluding the terminator — the C
/// contract `lowerConcatChain` measures with before it allocates.
fn helperSnFormat(e: *Emitter, b: *Buf) Error!void {
    const null_str: i64 = @intCast(try e.strings.intern("(null)"));
    // params: 0 fmt, 1 va
    // locals: 4 f(i32), 5 v(i32), 6 sp(i32), 7 c(i64)
    // The local NUMBERS are kept at 4..7 so the walk below reads the same way it
    // did when it lived inside `snprintf`; 2 and 3 are simply unused. FIVE i32s
    // then ONE i64: locals 2,3,4,5,6 are i32 and 7 is the i64 character. Two
    // params fewer than `snprintf` had means the split moves, and getting it
    // wrong put an i64 where the walk reads a pointer.
    try b.u32v(2);
    try b.u32v(5);
    try b.byte(vt_i32);
    try b.u32v(1);
    try b.byte(vt_i64);

    try b.get(0);
    try b.op(op_i32_wrap_i64);
    try b.set(4);
    try b.get(1);
    try b.op(op_i32_wrap_i64);
    try b.set(5);

    try b.byte(op_block); // $done   (depth 1 from inside $L)
    try b.byte(bt_void);
    try b.byte(op_loop); // $L
    try b.byte(bt_void);

    try b.get(4);
    try b.mem(op_i64_load8_u, 0, 0);
    try b.tee(7);
    try b.op(op_i64_eqz);
    try b.byte(op_br_if);
    try b.u32v(1); // -> $done

    try b.get(7);
    try b.i64c('%');
    try b.op(op_i64_eq);
    try b.byte(op_if);
    try b.byte(bt_void);

    // %%
    try b.get(4);
    try b.mem(op_i64_load8_u, 0, 1);
    try b.i64c('%');
    try b.op(op_i64_eq);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.i64c('%');
    try b.call(helperIndex(.sn_put));
    try b.get(4);
    try b.i32c(2);
    try b.op(op_i32_add);
    try b.set(4);
    try b.byte(op_br);
    // $L is at depth 2 here: the `%%` if, the `%` if, then the loop. It said 3,
    // which is `$done` — so a format branched OUT of the walk after its FIRST
    // directive and `"{t}{c}!"` rendered as `"x"`. The two `br`s below had the
    // same off-by-one and the same symptom.
    try b.u32v(2);
    try b.byte(op_end);

    // %s
    try b.get(4);
    try b.mem(op_i64_load8_u, 0, 1);
    try b.i64c('s');
    try b.op(op_i64_eq);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.get(5);
    try b.mem(op_i64_load, 3, 0);
    try b.op(op_i32_wrap_i64);
    try b.tee(6);
    try b.op(op_i32_eqz);
    try b.byte(op_if);
    try b.byte(bt_void);
    // A null through `%s` is macOS libc's "(null)", which is what the AArch64
    // build prints. Writing nothing here would be a quieter answer and a
    // different one.
    try b.i32c(@intCast(null_str));
    try b.set(6);
    try b.byte(op_end);
    try b.get(5);
    try b.i32c(8);
    try b.op(op_i32_add);
    try b.set(5);
    try b.get(4);
    try b.i32c(2);
    try b.op(op_i32_add);
    try b.set(4);
    try b.byte(op_block);
    try b.byte(bt_void);
    try b.byte(op_loop);
    try b.byte(bt_void);
    try b.get(6);
    try b.mem(op_i64_load8_u, 0, 0);
    try b.tee(7);
    try b.op(op_i64_eqz);
    try b.byte(op_br_if);
    try b.u32v(1);
    try b.get(7);
    try b.call(helperIndex(.sn_put));
    try b.get(6);
    try b.i32c(1);
    try b.op(op_i32_add);
    try b.set(6);
    try b.byte(op_br);
    try b.u32v(0);
    try b.byte(op_end);
    try b.byte(op_end);
    try b.byte(op_br);
    try b.u32v(2);
    try b.byte(op_end);

    // %lld
    try b.get(4);
    try b.mem(op_i64_load8_u, 0, 1);
    try b.i64c('l');
    try b.op(op_i64_eq);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.get(5);
    try b.mem(op_i64_load, 3, 0);
    try b.call(helperIndex(.sn_puti));
    try b.get(5);
    try b.i32c(8);
    try b.op(op_i32_add);
    try b.set(5);
    try b.get(4);
    try b.i32c(4);
    try b.op(op_i32_add);
    try b.set(4);
    try b.byte(op_br);
    try b.u32v(2);
    try b.byte(op_end);

    try b.byte(op_end); // end of the `%` if

    try b.get(7);
    try b.call(helperIndex(.sn_put));
    try b.get(4);
    try b.i32c(1);
    try b.op(op_i32_add);
    try b.set(4);
    try b.byte(op_br);
    try b.u32v(0); // -> $L
    try b.byte(op_end); // loop
    try b.byte(op_end); // $done
}

/// `snprintf(dst, cap, fmt, va)` — the C contract `lowerConcatChain` depends on:
/// with `dst == NULL` and `cap == 0` it writes nothing and answers the length
/// the result NEEDS, which is how the chain sizes its buffer before allocating.
fn helperSnprintf(e: *Emitter, b: *Buf) Error!void {
    _ = e;
    try b.u32v(0);
    try b.get(0);
    try b.op(op_i32_wrap_i64);
    try gset(b, g_sn_d);
    try b.i32c(0);
    try gset(b, g_sn_n);
    try b.get(1);
    try b.op(op_i32_wrap_i64);
    try gset(b, g_sn_cap);
    try b.get(2);
    try b.get(3);
    try b.call(helperIndex(.sn_format));

    // Terminate at `min(n, cap - 1)`, and only when there is a buffer at all.
    try gget(b, g_sn_cap);
    try b.i32c(0);
    try b.op(op_i32_gt_s);
    try b.byte(op_if);
    try b.byte(bt_void);
    try gget(b, g_sn_d);
    try gget(b, g_sn_n);
    try gget(b, g_sn_cap);
    try b.i32c(1);
    try b.op(op_i32_sub);
    try gget(b, g_sn_n);
    try gget(b, g_sn_cap);
    try b.i32c(1);
    try b.op(op_i32_sub);
    try b.op(op_i32_lt_s);
    try b.byte(op_select);
    try b.op(op_i32_add);
    try b.i64c(0);
    try b.mem(op_i64_store8, 0, 0);
    try b.byte(op_end);

    try gget(b, g_sn_n);
    try b.op(op_i64_extend_i32_u);
}

/// `printf(fmt, ...)` — the SAME walk, streaming. `print(a .. b)` lowers to this
/// rather than to a chain plus a `puts`, so 28 corpus programs reach the target
/// through it and through nothing else.
fn helperPrintf(e: *Emitter, b: *Buf) Error!void {
    _ = e;
    try b.u32v(0);
    try b.i32c(@intCast(addr_outbuf));
    try gset(b, g_sn_d);
    try b.i32c(0);
    try gset(b, g_sn_n);
    try b.i32c(-1);
    try gset(b, g_sn_cap);
    try b.get(0);
    try b.get(1);
    try b.call(helperIndex(.sn_format));
    try gget(b, g_sn_n);
    try b.i32c(0);
    try b.op(op_i32_gt_s);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.i32c(@intCast(addr_outbuf));
    try b.op(op_i64_extend_i32_u);
    try gget(b, g_sn_n);
    try b.op(op_i64_extend_i32_u);
    try b.call(helperIndex(.write_bytes));
    try b.byte(op_end);
    // Leave the cursor OUT of stream mode: a later `snprintf` sets every field
    // it reads, but a `sn_put` reached by any other route must not stream into
    // a buffer nobody is going to flush.
    try b.i32c(0);
    try gset(b, g_sn_cap);
}

/// `idol_str_at(s, i)` — the one-byte string at a 1-based index, interned, so
/// the same byte always answers the same pointer. Port of `idol_str_runtime.zig`.
fn helperStrAt(e: *Emitter, b: *Buf) Error!void {
    _ = e;
    // params: 0 s, 1 i ; locals: 2 p(i32), 3 k(i64), 4 c(i64)
    try b.u32v(2);
    try b.u32v(1);
    try b.byte(vt_i32);
    try b.u32v(2);
    try b.byte(vt_i64);

    try b.get(0);
    try b.op(op_i64_eqz);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.i64c(@intCast(addr_onechar));
    try b.byte(op_return);
    try b.byte(op_end);
    try b.get(1);
    try b.i64c(1);
    try b.op(op_i64_lt_s);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.i64c(@intCast(addr_onechar));
    try b.byte(op_return);
    try b.byte(op_end);

    try b.get(0);
    try b.op(op_i32_wrap_i64);
    try b.set(2);
    try b.i64c(1);
    try b.set(3);
    try b.byte(op_block);
    try b.byte(bt_void);
    try b.byte(op_loop);
    try b.byte(bt_void);
    try b.get(2);
    try b.mem(op_i64_load8_u, 0, 0);
    try b.tee(4);
    try b.op(op_i64_eqz);
    try b.byte(op_br_if);
    try b.u32v(1);
    try b.get(3);
    try b.get(1);
    try b.op(op_i64_eq);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.get(4);
    try b.i64c(2);
    try b.op(op_i64_mul);
    try b.i64c(@intCast(addr_onechar));
    try b.op(op_i64_add);
    try b.byte(op_return);
    try b.byte(op_end);
    try b.get(2);
    try b.i32c(1);
    try b.op(op_i32_add);
    try b.set(2);
    try b.get(3);
    try b.i64c(1);
    try b.op(op_i64_add);
    try b.set(3);
    try b.byte(op_br);
    try b.u32v(0);
    try b.byte(op_end);
    try b.byte(op_end);
    try b.i64c(@intCast(addr_onechar));
}

/// `duo_str_sub(s, i, j)` — Lua's 1-based inclusive slice with negative indices
/// counting from the end. Port of `idol_str_runtime.zig`, INCLUDING the
/// `start == end and start >= 1` shortcut that fires before any length is taken.
fn helperStrSub(e: *Emitter, b: *Buf) Error!void {
    _ = e;
    // params: 0 s, 1 i, 2 j
    // locals: 3 str(i64), 4 start(i64), 5 end(i64), 6 len(i64), 7 sublen(i64), 8 raw(i64)
    try b.u32v(1);
    try b.u32v(6);
    try b.byte(vt_i64);

    try b.get(0);
    try b.op(op_i64_eqz);
    try b.byte(op_if);
    try b.byte(vt_i64);
    try b.i64c(@intCast(addr_onechar));
    try b.byte(op_else);
    try b.get(0);
    try b.byte(op_end);
    try b.set(3);
    try b.get(1);
    try b.set(4);
    try b.get(2);
    try b.set(5);

    try b.get(4);
    try b.get(5);
    try b.op(op_i64_eq);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.get(4);
    try b.i64c(1);
    try b.op(op_i64_ge_s);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.get(3);
    try b.get(4);
    try b.call(helperIndex(.str_at));
    try b.byte(op_return);
    try b.byte(op_end);
    try b.byte(op_end);

    try b.get(3);
    try b.call(helperIndex(.strlen));
    try b.set(6);

    try b.get(4);
    try b.i64c(0);
    try b.op(op_i64_lt_s);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.get(6);
    try b.get(4);
    try b.op(op_i64_add);
    try b.i64c(1);
    try b.op(op_i64_add);
    try b.set(4);
    try b.byte(op_end);
    try b.get(5);
    try b.i64c(0);
    try b.op(op_i64_lt_s);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.get(6);
    try b.get(5);
    try b.op(op_i64_add);
    try b.i64c(1);
    try b.op(op_i64_add);
    try b.set(5);
    try b.byte(op_end);
    try b.get(4);
    try b.i64c(1);
    try b.op(op_i64_lt_s);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.i64c(1);
    try b.set(4);
    try b.byte(op_end);
    try b.get(5);
    try b.get(6);
    try b.op(op_i64_gt_s);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.get(6);
    try b.set(5);
    try b.byte(op_end);

    // Empty answer: an OWNED zero byte, not the interned "", because the C this
    // ports from returned a fresh allocation and a caller may write to it.
    try b.get(4);
    try b.get(5);
    try b.op(op_i64_gt_s);
    try b.get(4);
    try b.get(6);
    try b.op(op_i64_gt_s);
    try b.op(op_i32_or);
    try b.get(5);
    try b.i64c(1);
    try b.op(op_i64_lt_s);
    try b.op(op_i32_or);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.i64c(1);
    try b.call(helperIndex(.malloc));
    try b.set(8);
    try b.get(8);
    try b.op(op_i32_wrap_i64);
    try b.i64c(0);
    try b.mem(op_i64_store8, 0, 0);
    try b.get(8);
    try b.byte(op_return);
    try b.byte(op_end);

    try b.get(4);
    try b.get(5);
    try b.op(op_i64_eq);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.get(3);
    try b.get(4);
    try b.call(helperIndex(.str_at));
    try b.byte(op_return);
    try b.byte(op_end);

    try b.get(5);
    try b.get(4);
    try b.op(op_i64_sub);
    try b.i64c(1);
    try b.op(op_i64_add);
    try b.set(7);
    try b.get(7);
    try b.i64c(1);
    try b.op(op_i64_add);
    try b.call(helperIndex(.malloc));
    try b.set(8);
    try b.get(8);
    try b.get(3);
    try b.get(4);
    try b.op(op_i64_add);
    try b.i64c(1);
    try b.op(op_i64_sub);
    try b.get(7);
    try b.call(helperIndex(.memcpy));
    try b.op(op_drop);
    try b.get(8);
    try b.get(7);
    try b.op(op_i64_add);
    try b.op(op_i32_wrap_i64);
    try b.i64c(0);
    try b.mem(op_i64_store8, 0, 0);
    try b.get(8);
}

/// `duo_str_to_i64(s)` — leading and trailing whitespace allowed, an optional
/// sign, decimal digits, and NOTHING ELSE. Every rejection is the same fatal the
/// native runtime raises, message included, because the message is observable.
fn helperStrToI64(e: *Emitter, b: *Buf) Error!void {
    const m_nostr: i64 = @intCast(try e.strings.intern("to(i64): no string"));
    const m_nonum: i64 = @intCast(try e.strings.intern("to(i64): not a number"));
    const m_trail: i64 = @intCast(try e.strings.intern("to(i64): trailing text after number"));
    const m_range: i64 = @intCast(try e.strings.intern("to(i64): out of range"));
    // params: 0 s ; locals: 1 p(i32), 2 start(i32), 3 neg(i32), 4 acc(i64), 5 c(i64)
    try b.u32v(2);
    try b.u32v(3);
    try b.byte(vt_i32);
    try b.u32v(2);
    try b.byte(vt_i64);

    try b.get(0);
    try b.op(op_i64_eqz);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.i64c(m_nostr);
    try b.call(helperIndex(.die));
    try b.byte(op_unreachable);
    try b.byte(op_end);

    try b.get(0);
    try b.op(op_i32_wrap_i64);
    try b.set(1);
    try skipSpace(b, 1, 5);

    try b.get(1);
    try b.mem(op_i64_load8_u, 0, 0);
    try b.i64c('-');
    try b.op(op_i64_eq);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.i32c(1);
    try b.set(3);
    try b.get(1);
    try b.i32c(1);
    try b.op(op_i32_add);
    try b.set(1);
    try b.byte(op_else);
    try b.get(1);
    try b.mem(op_i64_load8_u, 0, 0);
    try b.i64c('+');
    try b.op(op_i64_eq);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.get(1);
    try b.i32c(1);
    try b.op(op_i32_add);
    try b.set(1);
    try b.byte(op_end);
    try b.byte(op_end);

    try b.get(1);
    try b.set(2);
    try b.byte(op_block);
    try b.byte(bt_void);
    try b.byte(op_loop);
    try b.byte(bt_void);
    try b.get(1);
    try b.mem(op_i64_load8_u, 0, 0);
    try b.set(5);
    try b.get(5);
    try b.i64c('0');
    try b.op(op_i64_lt_s);
    try b.byte(op_br_if);
    try b.u32v(1);
    try b.get(5);
    try b.i64c('9');
    try b.op(op_i64_gt_s);
    try b.byte(op_br_if);
    try b.u32v(1);
    // Overflow before it happens: 922337203685477580 is the largest accumulator
    // that can still take a digit.
    try b.get(4);
    try b.i64c(922337203685477580);
    try b.op(op_i64_gt_s);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.i64c(m_range);
    try b.call(helperIndex(.die));
    try b.byte(op_end);
    try b.get(4);
    try b.i64c(10);
    try b.op(op_i64_mul);
    try b.get(5);
    try b.op(op_i64_add);
    try b.i64c('0');
    try b.op(op_i64_sub);
    try b.set(4);
    try b.get(1);
    try b.i32c(1);
    try b.op(op_i32_add);
    try b.set(1);
    try b.byte(op_br);
    try b.u32v(0);
    try b.byte(op_end);
    try b.byte(op_end);

    try b.get(1);
    try b.get(2);
    try b.op(op_i32_eq);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.i64c(m_nonum);
    try b.call(helperIndex(.die));
    try b.byte(op_end);

    try skipSpace(b, 1, 5);
    try b.get(1);
    try b.mem(op_i64_load8_u, 0, 0);
    try b.op(op_i64_eqz);
    try b.op(op_i32_eqz);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.i64c(m_trail);
    try b.call(helperIndex(.die));
    try b.byte(op_end);

    try b.get(3);
    try b.byte(op_if);
    try b.byte(vt_i64);
    try b.i64c(0);
    try b.get(4);
    try b.op(op_i64_sub);
    try b.byte(op_else);
    try b.get(4);
    try b.byte(op_end);
}

/// Advance `cur` past space, tab, newline and carriage return.
fn skipSpace(b: *Buf, cur: u32, ch: u32) Error!void {
    try b.byte(op_block);
    try b.byte(bt_void);
    try b.byte(op_loop);
    try b.byte(bt_void);
    try b.get(cur);
    try b.mem(op_i64_load8_u, 0, 0);
    try b.set(ch);
    try b.get(ch);
    try b.i64c(' ');
    try b.op(op_i64_eq);
    try b.get(ch);
    try b.i64c('\t');
    try b.op(op_i64_eq);
    try b.op(op_i32_or);
    try b.get(ch);
    try b.i64c('\n');
    try b.op(op_i64_eq);
    try b.op(op_i32_or);
    try b.get(ch);
    try b.i64c('\r');
    try b.op(op_i64_eq);
    try b.op(op_i32_or);
    try b.op(op_i32_eqz);
    try b.byte(op_br_if);
    try b.u32v(1);
    try b.get(cur);
    try b.i32c(1);
    try b.op(op_i32_add);
    try b.set(cur);
    try b.byte(op_br);
    try b.u32v(0);
    try b.byte(op_end);
    try b.byte(op_end);
}

/// The native runtime's `strFatal`: the message and a newline on fd 2, then
/// abort. `unreachable` is wasm's abort and exits 134, the same code
/// `kill(getpid(), SIGABRT)` produces.
fn helperDie(e: *Emitter, b: *Buf) Error!void {
    const nl: i64 = @intCast(try e.strings.intern("\n"));
    try b.u32v(0);
    try b.i32c(@intCast(addr_iovec));
    try b.get(0);
    try b.op(op_i32_wrap_i64);
    try b.mem(op_i32_store, 2, 0);
    try b.i32c(@intCast(addr_iovec));
    try b.get(0);
    try b.call(helperIndex(.strlen));
    try b.op(op_i32_wrap_i64);
    try b.mem(op_i32_store, 2, 4);
    try b.i32c(2);
    try b.i32c(@intCast(addr_iovec));
    try b.i32c(1);
    try b.i32c(@intCast(addr_nwritten));
    try b.call(helperIndex(.fd_write));
    try b.op(op_drop);
    try b.i32c(@intCast(addr_iovec));
    try b.i32c(@intCast(nl));
    try b.mem(op_i32_store, 2, 0);
    try b.i32c(@intCast(addr_iovec));
    try b.i32c(1);
    try b.mem(op_i32_store, 2, 4);
    try b.i32c(2);
    try b.i32c(@intCast(addr_iovec));
    try b.i32c(1);
    try b.i32c(@intCast(addr_nwritten));
    try b.call(helperIndex(.fd_write));
    try b.op(op_drop);
    try b.byte(op_unreachable);
}

fn helperMemcpy(e: *Emitter, b: *Buf) Error!void {
    _ = e;
    // params: 0 d, 1 s, 2 n ; locals: 3 dp(i32), 4 sp(i32), 5 end(i32)
    try b.u32v(1);
    try b.u32v(3);
    try b.byte(vt_i32);
    try b.get(0);
    try b.op(op_i32_wrap_i64);
    try b.set(3);
    try b.get(1);
    try b.op(op_i32_wrap_i64);
    try b.set(4);
    try b.get(3);
    try b.get(2);
    try b.op(op_i32_wrap_i64);
    try b.op(op_i32_add);
    try b.set(5);
    try b.byte(op_block);
    try b.byte(bt_void);
    try b.byte(op_loop);
    try b.byte(bt_void);
    try b.get(3);
    try b.get(5);
    try b.op(op_i32_lt_u);
    try b.op(op_i32_eqz);
    try b.byte(op_br_if);
    try b.u32v(1);
    try b.get(3);
    try b.get(4);
    try b.mem(op_i64_load8_u, 0, 0);
    try b.mem(op_i64_store8, 0, 0);
    try b.get(3);
    try b.i32c(1);
    try b.op(op_i32_add);
    try b.set(3);
    try b.get(4);
    try b.i32c(1);
    try b.op(op_i32_add);
    try b.set(4);
    try b.byte(op_br);
    try b.u32v(0);
    try b.byte(op_end);
    try b.byte(op_end);
    try b.get(0);
}

fn putHelper(
    e: *Emitter,
    h: Helper,
    params: []const u8,
    results: []const u8,
    build: *const fn (*Emitter, *Buf) Error!void,
) Error!void {
    var b = Buf{ .alloc = e.alloc };
    errdefer b.deinit();
    try build(e, &b);
    try b.byte(op_end);
    const body = try b.items.toOwnedSlice(e.alloc);
    errdefer e.alloc.free(body);
    const ti = try e.types.intern(params, results);
    const slot = helperIndex(h) - import_count;
    if (e.bodies.items[slot].len > 0) e.alloc.free(e.bodies.items[slot]);
    e.bodies.items[slot] = body;
    e.body_types.items[slot] = ti;
}

/// `strlen(p)` — 0 for a null pointer. GAP-118 in the AArch64 backend: NULL is
/// unknown, not "", and a walk that dereferences it faults.
fn helperStrlen(e: *Emitter, b: *Buf) Error!void {
    _ = e;
    // locals: 0 = p (i64 param), 1 = cur (i32), 2 = start (i32)
    try b.u32v(1);
    try b.u32v(2);
    try b.byte(vt_i32);

    try b.get(0);
    try b.op(op_i32_wrap_i64);
    try b.tee(1);
    try b.set(2);

    try b.get(1);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.byte(op_block);
    try b.byte(bt_void);
    try b.byte(op_loop);
    try b.byte(bt_void);
    try b.get(1);
    try b.mem(op_i64_load8_u, 0, 0);
    try b.op(op_i64_eqz);
    try b.byte(op_br_if);
    try b.u32v(1);
    try b.get(1);
    try b.i32c(1);
    try b.op(op_i32_add);
    try b.set(1);
    try b.byte(op_br);
    try b.u32v(0);
    try b.byte(op_end);
    try b.byte(op_end);
    try b.byte(op_end);

    try b.get(1);
    try b.get(2);
    try b.op(op_i32_sub);
    try b.op(op_i64_extend_i32_u);
}

/// `write_bytes(p, len)` — one `fd_write` on fd 1 through the fixed iovec.
fn helperWriteBytes(e: *Emitter, b: *Buf) Error!void {
    _ = e;
    try b.u32v(0);
    // iov.ptr = p
    try b.i32c(@intCast(addr_iovec));
    try b.get(0);
    try b.op(op_i32_wrap_i64);
    try b.mem(op_i32_store, 2, 0);
    // iov.len = len
    try b.i32c(@intCast(addr_iovec));
    try b.get(1);
    try b.op(op_i32_wrap_i64);
    try b.mem(op_i32_store, 2, 4);
    // fd_write(1, iov, 1, nwritten)
    try b.i32c(1);
    try b.i32c(@intCast(addr_iovec));
    try b.i32c(1);
    try b.i32c(@intCast(addr_nwritten));
    try b.call(helperIndex(.fd_write));
    try b.op(op_drop);
}

fn helperWriteCstr(e: *Emitter, b: *Buf) Error!void {
    _ = e;
    try b.u32v(0);
    // A null string is not a "(null)" sentinel — it prints nothing at all.
    try b.get(0);
    try b.op(op_i64_eqz);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.byte(op_return);
    try b.byte(op_end);
    try b.get(0);
    try b.get(0);
    try b.call(helperIndex(.strlen));
    try b.call(helperIndex(.write_bytes));
}

fn helperPutsCstr(e: *Emitter, b: *Buf) Error!void {
    try b.u32v(0);
    try b.get(0);
    try b.op(op_i64_eqz);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.byte(op_return);
    try b.byte(op_end);
    try b.get(0);
    try b.call(helperIndex(.write_cstr));
    try b.i64c(@intCast(try e.strings.intern("\n")));
    try b.call(helperIndex(.write_cstr));
}

/// `printf("%lld", v)` with an optional trailing newline, written backwards into
/// the scratch buffer. UNSIGNED arithmetic throughout the digit loop, because
/// `-(INT64_MIN)` is still negative and a signed remainder would emit a `-`
/// digit for the one value the AArch64 build prints correctly.
fn helperPrintI64(e: *Emitter, b: *Buf) Error!void {
    _ = e;
    // params: 0 = v (i64), 1 = nl (i64)
    // locals: 2 = cur (i32), 3 = neg (i32), 4 = n (i64)
    try b.u32v(2);
    try b.u32v(2);
    try b.byte(vt_i32);
    try b.u32v(1);
    try b.byte(vt_i64);

    const end_addr: i32 = @intCast(addr_numbuf + numbuf_len);
    try b.i32c(end_addr);
    try b.set(2);

    // trailing newline
    try b.get(1);
    try b.op(op_i64_eqz);
    try b.op(op_i32_eqz);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.get(2);
    try b.i32c(1);
    try b.op(op_i32_sub);
    try b.tee(2);
    try b.i64c('\n');
    try b.mem(op_i64_store8, 0, 0);
    try b.byte(op_end);

    // neg = v < 0 ; n = |v| as unsigned
    try b.get(0);
    try b.i64c(0);
    try b.op(op_i64_lt_s);
    try b.set(3);
    try b.get(3);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.i64c(0);
    try b.get(0);
    try b.op(op_i64_sub);
    try b.set(4);
    try b.byte(op_else);
    try b.get(0);
    try b.set(4);
    try b.byte(op_end);

    // do { *--cur = '0' + n % 10; n /= 10 } while (n)
    try b.byte(op_loop);
    try b.byte(bt_void);
    try b.get(2);
    try b.i32c(1);
    try b.op(op_i32_sub);
    try b.tee(2);
    try b.get(4);
    try b.i64c(10);
    try b.op(op_i64_rem_u);
    try b.i64c('0');
    try b.op(op_i64_add);
    try b.mem(op_i64_store8, 0, 0);
    try b.get(4);
    try b.i64c(10);
    try b.op(op_i64_div_u);
    try b.tee(4);
    try b.i64c(0);
    try b.op(op_i64_ne);
    try b.byte(op_br_if);
    try b.u32v(0);
    try b.byte(op_end);

    try b.get(3);
    try b.byte(op_if);
    try b.byte(bt_void);
    try b.get(2);
    try b.i32c(1);
    try b.op(op_i32_sub);
    try b.tee(2);
    try b.i64c('-');
    try b.mem(op_i64_store8, 0, 0);
    try b.byte(op_end);

    try b.get(2);
    try b.op(op_i64_extend_i32_u);
    try b.i32c(end_addr);
    try b.get(2);
    try b.op(op_i32_sub);
    try b.op(op_i64_extend_i32_u);
    try b.call(helperIndex(.write_bytes));
}

/// A bump allocator. `free` is a no-op, which is the same contract the direct
/// backend's string helpers already run under: nothing they allocate is ever
/// released.
fn helperMalloc(e: *Emitter, b: *Buf) Error!void {
    _ = e;
    // locals: 1 = out (i32)
    try b.u32v(1);
    try b.u32v(1);
    try b.byte(vt_i32);
    try b.byte(op_global_get);
    try b.u32v(1); // $__heap
    try b.set(1);
    try b.byte(op_global_get);
    try b.u32v(1);
    try b.get(0);
    try b.op(op_i32_wrap_i64);
    try b.i32c(15);
    try b.op(op_i32_add);
    try b.i32c(-16);
    try b.op(op_i32_and);
    try b.op(op_i32_add);
    try b.byte(op_global_set);
    try b.u32v(1);
    try b.get(1);
    try b.op(op_i64_extend_i32_u);
}

fn helperMemset(e: *Emitter, b: *Buf) Error!void {
    _ = e;
    // params: 0 = p, 1 = c, 2 = n ; locals: 3 = cur (i32), 4 = end (i32)
    try b.u32v(1);
    try b.u32v(2);
    try b.byte(vt_i32);
    try b.get(0);
    try b.op(op_i32_wrap_i64);
    try b.set(3);
    try b.get(3);
    try b.get(2);
    try b.op(op_i32_wrap_i64);
    try b.op(op_i32_add);
    try b.set(4);
    try b.byte(op_block);
    try b.byte(bt_void);
    try b.byte(op_loop);
    try b.byte(bt_void);
    try b.get(3);
    try b.get(4);
    try b.op(op_i32_lt_u);
    try b.op(op_i32_eqz);
    try b.byte(op_br_if);
    try b.u32v(1);
    try b.get(3);
    try b.get(1);
    try b.mem(op_i64_store8, 0, 0);
    try b.get(3);
    try b.i32c(1);
    try b.op(op_i32_add);
    try b.set(3);
    try b.byte(op_br);
    try b.u32v(0);
    try b.byte(op_end);
    try b.byte(op_end);
    try b.get(0);
}

/// `strcmp` with C's sign contract: the difference of the first differing byte,
/// compared as UNSIGNED chars.
fn helperStrcmp(e: *Emitter, b: *Buf) Error!void {
    _ = e;
    // params: 0 = a, 1 = b ; locals: 2 = pa, 3 = pb (i32), 4 = ca, 5 = cb (i64)
    try b.u32v(2);
    try b.u32v(2);
    try b.byte(vt_i32);
    try b.u32v(2);
    try b.byte(vt_i64);
    try b.get(0);
    try b.op(op_i32_wrap_i64);
    try b.set(2);
    try b.get(1);
    try b.op(op_i32_wrap_i64);
    try b.set(3);
    try b.byte(op_block);
    try b.byte(bt_void);
    try b.byte(op_loop);
    try b.byte(bt_void);
    try b.get(2);
    try b.mem(op_i64_load8_u, 0, 0);
    try b.set(4);
    try b.get(3);
    try b.mem(op_i64_load8_u, 0, 0);
    try b.set(5);
    try b.get(4);
    try b.get(5);
    try b.op(op_i64_ne);
    try b.byte(op_br_if);
    try b.u32v(1);
    try b.get(4);
    try b.op(op_i64_eqz);
    try b.byte(op_br_if);
    try b.u32v(1);
    try b.get(2);
    try b.i32c(1);
    try b.op(op_i32_add);
    try b.set(2);
    try b.get(3);
    try b.i32c(1);
    try b.op(op_i32_add);
    try b.set(3);
    try b.byte(op_br);
    try b.u32v(0);
    try b.byte(op_end);
    try b.byte(op_end);
    try b.get(4);
    try b.get(5);
    try b.op(op_i64_sub);
}

// ---------------------------------------------------------------------------
// MODULE ASSEMBLY
// ---------------------------------------------------------------------------

fn section(out: *Buf, id: u8, payload: []const u8) Error!void {
    try out.byte(id);
    try out.u32v(@intCast(payload.len));
    try out.bytes(payload);
}

/// Append the load-time bytes already published by `dnir.Module.globals` for
/// words this realization actually allocated. The name-to-offset map is the
/// storage decision consumed by `load_global` and `store_global`; consulting it
/// here keeps initialization, reads, and writes on one physical word without
/// re-deriving which source declaration was a global.
fn appendGlobalData(e: *Emitter, out: *Buf) Error!u32 {
    var count: u32 = 0;
    for (e.module.globals) |global| {
        const off = e.globals.get(global.name) orelse continue;
        const word: u64 = switch (global.init) {
            .i64 => |value| @bitCast(value),
            .f64 => |value| @bitCast(value),
            else => {
                e.diagnostic.remember("global-init-kind");
                return error.UnsupportedProgram;
            },
        };
        try out.u32v(0); // active, memory 0
        try out.i32c(@intCast(globals_base + off));
        try out.byte(op_end);
        try out.u32v(8);
        var raw: [8]u8 = undefined;
        std.mem.writeInt(u64, &raw, word, .little);
        try out.bytes(&raw);
        count += 1;
    }
    return count;
}

fn assemble(e: *Emitter, start_index: u32) Error![]u8 {
    const alloc = e.alloc;
    const pool_len: u32 = @intCast(e.strings.data.items.len);
    if (pool_len > string_pool_cap) return e.refuse("string-pool-overflow");
    if (e.globals_used > globals_cap) return e.refuse("globals-overflow");
    // Reserve only the bytes selected by this module. A fixed `dense_cap`
    // hole would raise every program's declared Wasm memory by 1 MiB even
    // when it has no dense realization, turning a bounded new capability into
    // a universal startup/residency regression.
    const heap_base = dense_base + e.dense_used;
    const stack_top = heap_base + heap_bytes + shadow_stack_bytes;

    var out = Buf{ .alloc = alloc };
    errdefer out.deinit();
    try out.bytes(&[_]u8{ 0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00 });

    // SECTION ORDER IS NORMATIVE: type, import, function, memory, global,
    // export, code, data. A module whose data section precedes its code section
    // is not a late-validating module, it is not a module at all.

    // --- 1 type
    {
        var s = Buf{ .alloc = alloc };
        defer s.deinit();
        try s.u32v(@intCast(e.types.list.items.len));
        for (e.types.list.items) |t| {
            try s.byte(0x60);
            try s.u32v(@intCast(t.params.len));
            try s.bytes(t.params);
            try s.u32v(@intCast(t.results.len));
            try s.bytes(t.results);
        }
        try section(&out, 1, s.items.items);
    }

    // --- 2 import: exactly the two WASI calls this runtime needs. Their type
    // indices were interned before the first body was emitted, so the table
    // written above already contains them.
    {
        var s = Buf{ .alloc = alloc };
        defer s.deinit();
        try s.u32v(2);
        try s.name("wasi_snapshot_preview1");
        try s.name("fd_write");
        try s.byte(0x00);
        try s.u32v(e.ty_fd_write);
        try s.name("wasi_snapshot_preview1");
        try s.name("proc_exit");
        try s.byte(0x00);
        try s.u32v(e.ty_proc_exit);
        try section(&out, 2, s.items.items);
    }

    // --- 3 function
    {
        var s = Buf{ .alloc = alloc };
        defer s.deinit();
        try s.u32v(@intCast(e.body_types.items.len));
        for (e.body_types.items) |t| try s.u32v(t);
        try section(&out, 3, s.items.items);
    }

    // --- 5 memory
    const pages = (stack_top + wasm_page - 1) / wasm_page;
    {
        var s = Buf{ .alloc = alloc };
        defer s.deinit();
        try s.u32v(1);
        try s.byte(0x00); // min only
        try s.u32v(pages);
        try section(&out, 5, s.items.items);
    }

    // --- 6 global: the shadow stack pointer and the heap cursor.
    {
        var s = Buf{ .alloc = alloc };
        defer s.deinit();
        try s.u32v(5);
        try s.byte(vt_i32);
        try s.byte(0x01); // $__sp, mutable
        try s.i32c(@intCast(stack_top));
        try s.byte(op_end);
        try s.byte(vt_i32);
        try s.byte(0x01); // $__heap
        try s.i32c(@intCast(heap_base));
        try s.byte(op_end);
        try s.byte(vt_i32);
        try s.byte(0x01); // $sn_d
        try s.i32c(0);
        try s.byte(op_end);
        try s.byte(vt_i32);
        try s.byte(0x01); // $sn_n
        try s.i32c(0);
        try s.byte(op_end);
        try s.byte(vt_i32);
        try s.byte(0x01); // $sn_cap
        try s.i32c(0);
        try s.byte(op_end);
        try section(&out, 6, s.items.items);
    }

    // --- 7 export
    {
        var s = Buf{ .alloc = alloc };
        defer s.deinit();
        try s.u32v(2);
        try s.name("memory");
        try s.byte(0x02);
        try s.u32v(0);
        try s.name("_start");
        try s.byte(0x00);
        try s.u32v(start_index);
        try section(&out, 7, s.items.items);
    }

    // --- 10 code
    {
        var s = Buf{ .alloc = alloc };
        defer s.deinit();
        try s.u32v(@intCast(e.bodies.items.len));
        for (e.bodies.items) |body| {
            try s.u32v(@intCast(body.len));
            try s.bytes(body);
        }
        try section(&out, 10, s.items.items);
    }

    // --- 11 data: the 256 interned one-byte strings, the string pool, then the
    // demanded non-zero module-global words and graph-selected immutable dense
    // tables. Zero global words remain physically absent and therefore keep
    // WebAssembly's implicit zero initialization.
    {
        var s = Buf{ .alloc = alloc };
        defer s.deinit();
        var globals = Buf{ .alloc = alloc };
        defer globals.deinit();
        const global_count = try appendGlobalData(e, &globals);
        const dense_segments = std.math.cast(u32, e.module.dense_tables.len) orelse
            return e.refuse("dense-table-capacity");
        const segment_count = 1 + @as(u32, @intFromBool(pool_len > 0)) + global_count + dense_segments;
        try s.u32v(segment_count);
        try s.u32v(0); // active, memory 0
        try s.i32c(@intCast(addr_onechar));
        try s.byte(op_end);
        try s.u32v(512);
        var c: u32 = 0;
        while (c < 256) : (c += 1) {
            try s.byte(@intCast(c));
            try s.byte(0);
        }
        if (pool_len > 0) {
            try s.u32v(0);
            try s.i32c(@intCast(addr_data));
            try s.byte(op_end);
            try s.u32v(pool_len);
            try s.bytes(e.strings.data.items);
        }
        try s.bytes(globals.items.items);
        for (e.module.dense_tables) |table| {
            const address = e.dense_addr.get(table.value) orelse
                return e.refuse("dense-table-address");
            const word_count = std.math.cast(u32, table.values.len) orelse
                return e.refuse("dense-table-capacity");
            const byte_count = std.math.mul(u32, word_count, 8) catch
                return e.refuse("dense-table-capacity");
            try s.u32v(0);
            try s.i32c(@intCast(address));
            try s.byte(op_end);
            try s.u32v(byte_count);
            for (table.values) |word| {
                const bits: u64 = @bitCast(word);
                var byte_index: u6 = 0;
                while (byte_index < 8) : (byte_index += 1) {
                    try s.byte(@truncate(bits >> byte_index * 8));
                }
            }
        }
        try section(&out, 11, s.items.items);
    }

    return out.items.toOwnedSlice(alloc);
}

test "wasm backend consumes the DNIR global initializer at its storage word" {
    const testing = std.testing;
    const globals = [_]dnir.Global{
        .{ .name = "z", .ty = .i64, .init = .{ .i64 = 30 } },
        // No load/store names this word, so demand gives it no physical slot.
        .{ .name = "unused", .ty = .i64, .init = .{ .i64 = 99 } },
    };
    const floats = [_]dnir.Global{
        .{ .name = "z", .ty = .f64, .init = .{ .f64 = -1.5 } },
    };
    var diagnostic: Diagnostic = .{};
    var emitter = Emitter{
        .alloc = testing.allocator,
        .diagnostic = &diagnostic,
        .module = .{ .functions = &.{}, .globals = &globals },
        .types = .{ .alloc = testing.allocator },
        .strings = .{ .alloc = testing.allocator },
    };
    defer emitter.deinit();
    try emitter.globals.put(testing.allocator, "z", 8);
    emitter.globals_used = 16;

    var data = Buf{ .alloc = testing.allocator };
    defer data.deinit();
    try testing.expectEqual(@as(u32, 1), try appendGlobalData(&emitter, &data));
    try testing.expect(data.items.items.len >= 8);
    const word = data.items.items[data.items.items.len - 8 ..];
    try testing.expectEqual(@as(u64, 30), std.mem.readInt(u64, word[0..8], .little));

    emitter.module.globals = &floats;
    data.items.clearRetainingCapacity();
    try testing.expectEqual(@as(u32, 1), try appendGlobalData(&emitter, &data));
    const float_word = data.items.items[data.items.items.len - 8 ..];
    try testing.expectEqual(
        @as(u64, @bitCast(@as(f64, -1.5))),
        std.mem.readInt(u64, float_word[0..8], .little),
    );

    // Damage control: removing the producer fact must remove the segment even
    // though the same physical word remains allocated for loads and stores.
    emitter.module.globals = &.{};
    data.items.clearRetainingCapacity();
    try testing.expectEqual(@as(u32, 0), try appendGlobalData(&emitter, &data));
    try testing.expectEqual(@as(usize, 0), data.items.items.len);
}

test "wasm backend realizes graph flat projection as exact dense data" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\pick: i64 = (i: i64)
        \\    values = {10, 20, 30}
        \\    other = {40, 50}
        \\    values[i] + other[1]
        \\main: i64 = ()
        \\    pick(2)
    ;
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    const lowered = try dnir_lower.lowerTestSourceWithGraph(
        alloc,
        source,
        "flat-wasm.id",
        &graph,
    );
    defer dnir.deinitModule(alloc, lowered);
    try std.testing.expectEqual(@as(usize, 1), lowered.dense_tables.len);
    const entry_name = for (lowered.functions) |function| {
        if (function.params.len == 0) break function.name;
    } else return error.TestExpectedEqual;

    var diagnostic: Diagnostic = .{};
    const bytes = try emitFromDnir(alloc, lowered, entry_name, &diagnostic);
    defer alloc.free(bytes);
    try std.testing.expect(std.mem.startsWith(u8, bytes, "\x00asm"));
    var dense_bytes: [24]u8 = undefined;
    for ([_]i64{ 10, 20, 30 }, 0..) |word, word_index| {
        const bits: u64 = @bitCast(word);
        var byte_index: u6 = 0;
        while (byte_index < 8) : (byte_index += 1) {
            dense_bytes[word_index * 8 + byte_index] = @truncate(bits >> byte_index * 8);
        }
    }
    try std.testing.expect(std.mem.indexOf(u8, bytes, &dense_bytes) != null);

    // Damage the physical table while keeping the graph exact. Wasm must ask
    // the graph owner and refuse; accepting 10/99/30 would make the data
    // segment a second semantic contents producer.
    const mutable_values = @constCast(lowered.dense_tables[0].values);
    const saved = mutable_values[1];
    mutable_values[1] = 99;
    var damage_diagnostic: Diagnostic = .{};
    try std.testing.expectError(
        error.UnsupportedProgram,
        emitFromDnir(alloc, lowered, entry_name, &damage_diagnostic),
    );
    try std.testing.expectEqualStrings("aggregate-dense-table-content", damage_diagnostic.note().?);
    mutable_values[1] = saved;

    var duplicate_rows = [_]dnir.DenseTable{
        lowered.dense_tables[0],
        lowered.dense_tables[0],
    };
    var damaged_module = lowered;
    damaged_module.dense_tables = &duplicate_rows;
    damage_diagnostic = .{};
    try std.testing.expectError(
        error.UnsupportedProgram,
        emitFromDnir(alloc, damaged_module, entry_name, &damage_diagnostic),
    );
    try std.testing.expectEqualStrings("aggregate-dense-table-duplicate", damage_diagnostic.note().?);

    var unknown_rows = [_]dnir.DenseTable{lowered.dense_tables[0]};
    unknown_rows[0].value = std.math.maxInt(semantic_graph.id);
    damaged_module.dense_tables = &unknown_rows;
    damage_diagnostic = .{};
    try std.testing.expectError(
        error.UnsupportedProgram,
        emitFromDnir(alloc, damaged_module, entry_name, &damage_diagnostic),
    );
    try std.testing.expectEqualStrings("aggregate-dense-table-facts", damage_diagnostic.note().?);

    var empty_rows = [_]dnir.DenseTable{lowered.dense_tables[0]};
    empty_rows[0].values = &.{};
    damaged_module.dense_tables = &empty_rows;
    damage_diagnostic = .{};
    try std.testing.expectError(
        error.UnsupportedProgram,
        emitFromDnir(alloc, damaged_module, entry_name, &damage_diagnostic),
    );
    try std.testing.expectEqualStrings("aggregate-dense-table-shape", damage_diagnostic.note().?);

    damaged_module = lowered;
    damaged_module.graph = null;
    damage_diagnostic = .{};
    try std.testing.expectError(
        error.UnsupportedProgram,
        emitFromDnir(alloc, damaged_module, entry_name, &damage_diagnostic),
    );
    try std.testing.expectEqualStrings("aggregate-dense-table-graph", damage_diagnostic.note().?);

    var other_root: ?semantic_graph.id = null;
    for (graph.applications()) |application| {
        if (graph.aggregateAccess(application.application) == null) continue;
        const subject = graph.applicationSubject(application.application) orelse continue;
        if (subject != lowered.dense_tables[0].value) other_root = subject;
    }
    const exact_root = other_root orelse return error.TestExpectedEqual;
    const extra_values = [_]i64{ 40, 50 };
    var unused_rows = [_]dnir.DenseTable{
        lowered.dense_tables[0],
        .{ .value = exact_root, .elem_ty = .i64, .values = &extra_values },
    };
    damaged_module = lowered;
    damaged_module.dense_tables = &unused_rows;
    damage_diagnostic = .{};
    try std.testing.expectError(
        error.UnsupportedProgram,
        emitFromDnir(alloc, damaged_module, entry_name, &damage_diagnostic),
    );
    try std.testing.expectEqualStrings("aggregate-dense-table-unused", damage_diagnostic.note().?);
}

test "wasm backend validates exact flat projection lineage without dense storage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\pick: i64 = (unused: i64)
        \\    values = {10, 20, 30}
        \\    values[2]
        \\main: i64 = ()
        \\    pick(0)
    ;
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    const lowered = try dnir_lower.lowerTestSourceWithGraph(
        alloc,
        source,
        "flat-exact-wasm.id",
        &graph,
    );
    defer dnir.deinitModule(alloc, lowered);
    try std.testing.expectEqual(@as(usize, 0), lowered.dense_tables.len);
    const entry_name = for (lowered.functions) |function| {
        if (function.params.len == 0) break function.name;
    } else return error.TestExpectedEqual;

    var diagnostic: Diagnostic = .{};
    const bytes = try emitFromDnir(alloc, lowered, entry_name, &diagnostic);
    alloc.free(bytes);

    var graphless = lowered;
    graphless.graph = null;
    diagnostic = .{};
    try std.testing.expectError(
        error.UnsupportedProgram,
        emitFromDnir(alloc, graphless, entry_name, &diagnostic),
    );
    try std.testing.expectEqualStrings("realization-graph", diagnostic.note().?);

    var exact_instruction: ?*dnir.Instr = null;
    for (lowered.functions) |function| {
        for (function.blocks) |block| {
            for (@constCast(block.instrs)) |*instruction| {
                const application = instruction.application orelse continue;
                if (graph.aggregateAccess(application) == null or instruction.op != .@"const") continue;
                exact_instruction = instruction;
            }
        }
    }
    const instruction = exact_instruction orelse return error.TestExpectedEqual;
    const saved = instruction.*;
    instruction.lhs = .{ .i64 = 99 };
    diagnostic = .{};
    try std.testing.expectError(
        error.UnsupportedProgram,
        emitFromDnir(alloc, lowered, entry_name, &diagnostic),
    );
    try std.testing.expectEqualStrings("aggregate-access-realization-op", diagnostic.note().?);
    instruction.* = saved;

    instruction.value = saved.subject;
    diagnostic = .{};
    try std.testing.expectError(
        error.UnsupportedProgram,
        emitFromDnir(alloc, lowered, entry_name, &diagnostic),
    );
    try std.testing.expectEqualStrings("aggregate-access-lineage", diagnostic.note().?);
    instruction.* = saved;

    const result = saved.value orelse return error.TestExpectedEqual;
    const content_row = graph.exact_i64_rows.get(result) orelse return error.TestExpectedEqual;
    const saved_content = graph.exact_i64_facts.items[content_row].content;
    graph.exact_i64_facts.items[content_row].content = 99;
    diagnostic = .{};
    try std.testing.expectError(
        error.UnsupportedProgram,
        emitFromDnir(alloc, lowered, entry_name, &diagnostic),
    );
    try std.testing.expectEqualStrings("aggregate-access-realization-op", diagnostic.note().?);
    graph.exact_i64_facts.items[content_row].content = saved_content;

    const saved_descriptor = graph.nodes.items[result].descriptor;
    graph.nodes.items[result].descriptor = .f64;
    diagnostic = .{};
    try std.testing.expectError(
        error.UnsupportedProgram,
        emitFromDnir(alloc, lowered, entry_name, &diagnostic),
    );
    try std.testing.expectEqualStrings("aggregate-access-facts", diagnostic.note().?);
    graph.nodes.items[result].descriptor = saved_descriptor;

    const application = saved.application orelse return error.TestExpectedEqual;
    const application_row = graph.application_rows.items[application];
    const saved_target = graph.application_facts.items[application_row].target;
    graph.application_facts.items[application_row].target = .unknown;
    diagnostic = .{};
    try std.testing.expectError(
        error.UnsupportedProgram,
        emitFromDnir(alloc, lowered, entry_name, &diagnostic),
    );
    try std.testing.expectEqualStrings("aggregate-access-facts", diagnostic.note().?);
    graph.application_facts.items[application_row].target = saved_target;

    graph.application_presence.unset(application);
    diagnostic = .{};
    try std.testing.expectError(
        error.UnsupportedProgram,
        emitFromDnir(alloc, lowered, entry_name, &diagnostic),
    );
    try std.testing.expectEqualStrings("aggregate-access-facts", diagnostic.note().?);
    graph.application_presence.set(application);
}
