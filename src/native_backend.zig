const std = @import("std");
const builtin = @import("builtin");
const ast = @import("ast.zig");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;
const native_req_support = @import("native_req_support.zig");
const dnir = @import("duo_native_ir.zig");
const c_signatures = @import("c_signatures.zig");
const dnir_lower = @import("dnir_lower.zig");
const dnir_hardware = @import("dnir_hardware.zig");
const semantic_graph = @import("semantic_graph.zig");
const region_graph = @import("region_graph.zig");
const region_transform = @import("region_transform.zig");
const region_schedule = @import("region_schedule.zig");
const realization = @import("realization.zig");

pub const Error = error{
    UnsupportedTarget,
    UnsupportedProgram,
    MissingMain,
    InvalidMainSignature,
    IntegerOutOfRange,
    RegisterExhausted,
    UndefinedName,
    DuplicateSymbol,
    UnknownSymbol,
    BranchOutOfRange,
} || std.mem.Allocator.Error;

/// Mach-O / ELF labels cannot contain `.`; DNIR keeps logical `Type.method` names.
fn linkerSymbolName(alloc: std.mem.Allocator, name: []const u8) Error![]const u8 {
    if (std.mem.indexOfScalar(u8, name, '.') == null) return try alloc.dupe(u8, name);
    return std.mem.replaceOwned(u8, alloc, name, ".", "_");
}

/// Pass 11 WP-02: structured direct-backend diagnostic.
pub const DirectDiag = struct {
    code: []const u8,
    message: []const u8,
};

/// Which of the 75 backend refusals fired.
///
/// The third and last layer to get this. dnir_lower and the native-scalar
/// precheck now name their bail sites, so a DNB001 that prints NO site at all
/// means the module lowered fine and the ARM64 emitter refused it — as opaque
/// as the original single bucket, one layer down. `@src()` for the same reason
/// as the others: a hand-written tag drifts from the line it labels, a source
/// location cannot.
///
/// Only `return` sites are rewritten. `error.UnsupportedProgram` also appears
/// as a SWITCH PRONG in describeError, and a prong must be comptime — a first
/// pass that rewrote every occurrence turned those into `refuse(@src()) =>`
/// and failed with "unable to evaluate comptime expression".
pub var refusal_site: std.builtin.SourceLocation = .{
    .module = "",
    .file = "",
    .fn_name = "",
    .line = 0,
    .column = 0,
};

fn refuse(src: std.builtin.SourceLocation) Error {
    refusal_site = src;
    refusal_note_len = 0;
    return error.UnsupportedProgram;
}

/// What the refusal was looking at. Same reasoning as dnir_lower's bailNote:
/// a source location says where the emitter stopped, never what it could not
/// emit, and for a switch over opcodes the opcode IS the finding.
var refusal_note_buf: [64]u8 = undefined;
var refusal_note_len: usize = 0;

pub fn refusalNote() ?[]const u8 {
    if (refusal_note_len == 0) return null;
    return refusal_note_buf[0..refusal_note_len];
}

/// Same treatment for the OTHER refusal error. `UndefinedName` means a slot or
/// temp had no register, and which one is the entire finding — exactly as
/// `UnknownSymbol` turned out to be two different problems wearing one code
/// once the symbol was printed.
/// Same as `undefinedAt` but for the keyed maps (fp_locals, fp_stack_slots,
/// locals), where the KEY is the finding rather than a slot number.
fn undefinedKey(src: std.builtin.SourceLocation, kind: []const u8, key: []const u8) Error {
    refusal_site = src;
    const w = std.fmt.bufPrint(&refusal_note_buf, "{s} '{s}' has no register", .{ kind, key }) catch {
        refusal_note_len = 0;
        return error.UndefinedName;
    };
    refusal_note_len = w.len;
    return error.UndefinedName;
}

fn undefinedAt(src: std.builtin.SourceLocation, kind: []const u8, id: u32) Error {
    refusal_site = src;
    const w = std.fmt.bufPrint(&refusal_note_buf, "{s} {d} has no register", .{ kind, id }) catch {
        refusal_note_len = 0;
        return error.UndefinedName;
    };
    refusal_note_len = w.len;
    return error.UndefinedName;
}

fn refuseWith(src: std.builtin.SourceLocation, note: []const u8) Error {
    refusal_site = src;
    const n = @min(note.len, refusal_note_buf.len);
    @memcpy(refusal_note_buf[0..n], note[0..n]);
    refusal_note_len = n;
    return error.UnsupportedProgram;
}

pub fn directDiagnostic(err: Error, target: []const u8) DirectDiag {
    _ = target;
    return switch (err) {
        error.UnsupportedTarget => .{ .code = "DNB004", .message = "target object format or host is unsupported by the direct backend" },
        error.UnsupportedProgram => .{ .code = "DNB001", .message = "program construct is outside the direct backend subset" },
        error.MissingMain => .{ .code = "DNB006", .message = "direct native module has no eligible functions" },
        error.InvalidMainSignature => .{ .code = "DNB002", .message = "function signature incompatible with direct ARM64 ABI" },
        error.RegisterExhausted => .{ .code = "DNB003", .message = "register pressure exceeds direct backend spill capacity" },
        error.UndefinedName, error.UnknownSymbol => .{ .code = "DNB007", .message = "undefined symbol in direct backend lowering" },
        error.DuplicateSymbol => .{ .code = "DNB008", .message = "duplicate symbol in direct backend output" },
        error.BranchOutOfRange => .{ .code = "DNB009", .message = "branch relocation out of range" },
        error.IntegerOutOfRange => .{ .code = "DNB010", .message = "integer literal out of range for direct backend" },
        else => .{ .code = "DNB000", .message = "direct backend internal error" },
    };
}

pub fn formatDirectError(err: Error, target: []const u8, buf: []u8) []const u8 {
    const d = directDiagnostic(err, target);
    return std.fmt.bufPrint(buf, "{s}: {s}", .{ d.code, d.message }) catch d.message;
}

pub fn describeError(err: anyerror, target: []const u8, buf: []u8) []const u8 {
    switch (err) {
        error.UnsupportedTarget,
        error.UnsupportedProgram,
        error.MissingMain,
        error.InvalidMainSignature,
        error.IntegerOutOfRange,
        error.RegisterExhausted,
        error.UndefinedName,
        error.DuplicateSymbol,
        error.UnknownSymbol,
        error.BranchOutOfRange,
        => return formatDirectError(@errorCast(err), target, buf),
        error.OutOfMemory => return "out of memory",
        else => return @errorName(err),
    }
}

pub fn isNativeMachineTarget(target: []const u8) bool {
    return std.mem.eql(u8, target, "native-object") or
        std.mem.eql(u8, target, "native-mach-o") or
        std.mem.eql(u8, target, "native-asm") or
        std.mem.eql(u8, target, "native-exe") or
        std.mem.eql(u8, target, "native-dylib");
}

pub fn isNativeObjectTarget(target: []const u8) bool {
    return std.mem.eql(u8, target, "native-object") or
        std.mem.eql(u8, target, "native-mach-o");
}

pub fn isNativeAsmTarget(target: []const u8) bool {
    return std.mem.eql(u8, target, "native-asm");
}

pub fn isNativeExecutableTarget(target: []const u8) bool {
    return std.mem.eql(u8, target, "native-exe");
}

pub fn isNativeSharedTarget(target: []const u8) bool {
    return std.mem.eql(u8, target, "native-dylib");
}

pub fn emitObject(alloc: std.mem.Allocator, mod: *const ast.Module, target: []const u8) Error![]u8 {
    refusal_site.line = 0;
    if (!isNativeObjectTarget(target)) return error.UnsupportedTarget;
    return emitObjectMode(alloc, mod, null);
}

/// Like `emitObject`, but when `process_entry` is set the named zero-arg function
/// gets `fcvtzs x0, d0` on f64 returns so native executables receive an i64 exit code.
pub fn emitObjectForExecutable(alloc: std.mem.Allocator, mod: *const ast.Module, process_entry: []const u8) Error![]u8 {
    // Seed the site with THIS function rather than clearing it. A refusal that
    // never reaches a `refuse()` call then reports "refused inside
    // emitObjectForExecutable, untagged" instead of reporting nothing — which
    // is what examples/pass23_canonical_syntax.duo does today: precheck true
    // (confirmed with DUO_NATIVE_DIAG), one linked module, backend called, and
    // every report branch falsy. Silence is the one answer a diagnostic must
    // never give.
    refusal_site = @src();
    refusal_note_len = 0;
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) {
        return error.UnsupportedTarget;
    }
    return emitObjectMode(alloc, mod, process_entry);
}

pub fn emitSharedObjectInput(alloc: std.mem.Allocator, mod: *const ast.Module) Error![]u8 {
    return emitObjectMode(alloc, mod, null);
}

fn emitObjectMode(alloc: std.mem.Allocator, mod: *const ast.Module, process_entry: ?[]const u8) Error![]u8 {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) {
        return error.UnsupportedTarget;
    }

    var output = try emitArm64Module(alloc, mod, process_entry);
    defer output.deinit(alloc);
    return emitMachOArm64Object(alloc, output.text, output.cstring, output.symbols, output.relocations, output.bss_size);
}

pub fn emitAssembly(alloc: std.mem.Allocator, mod: *const ast.Module, target: []const u8) Error![]u8 {
    refusal_site.line = 0;
    if (!isNativeAsmTarget(target)) return error.UnsupportedTarget;
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) {
        return error.UnsupportedTarget;
    }
    const output = try emitArm64Module(alloc, mod, null);
    defer {
        alloc.free(output.text);
        if (output.cstring.len > 0) alloc.free(output.cstring);
        for (output.symbols) |sym| alloc.free(sym.name);
        alloc.free(output.symbols);
        alloc.free(output.relocations);
    }
    return output.asm_text;
}

pub fn emitAssemblyForExecutable(alloc: std.mem.Allocator, mod: *const ast.Module, process_entry: []const u8) Error![]u8 {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) {
        return error.UnsupportedTarget;
    }
    const output = try emitArm64Module(alloc, mod, process_entry);
    defer {
        alloc.free(output.text);
        if (output.cstring.len > 0) alloc.free(output.cstring);
        for (output.symbols) |sym| alloc.free(sym.name);
        alloc.free(output.symbols);
        alloc.free(output.relocations);
    }
    return output.asm_text;
}

pub fn unsupportedReason(target: []const u8) []const u8 {
    if (!isNativeMachineTarget(target)) return "DNB004: not a direct machine-code target (use --backend=direct)";
    if (builtin.os.tag != .macos) return "DNB004: direct object writer currently supports Mach-O on macOS only";
    if (builtin.cpu.arch != .aarch64) return "DNB004: direct object writer currently supports AArch64 only";
    return "DNB001: program is outside the current direct backend subset (machine code is canonical; use --backend=c only for bootstrap C emit)";
}

const Symbol = struct {
    name: []const u8,
    offset: u32,
    defined: bool = true,
    section: u8 = 1, // 1 = __text, 2 = __cstring
    external: bool = true, // n_ext bit for nlist; local string symbols set this false
};

const RelocKind = enum(u3) { branch26, page21, pageoff12 };

const Relocation = struct {
    offset: u32,
    symbol_index: u32,
    kind: RelocKind = .branch26,
};

const ExternalSymbol = struct {
    local_name: []const u8,
    symbol_name: []const u8,
};

const NativeFunction = struct {
    decl: *const ast.FuncDecl,
    symbol_name: []const u8,
};

/// Sealed record descriptor lowered as consecutive f64 ABI slots (Pass 4 M1).
const F64RecordDesc = struct {
    field_names: []const []const u8,
};

const F64RecordMap = std.StringHashMapUnmanaged(F64RecordDesc);

const ScalFieldKind = enum { i64, str };

/// Record lowered as consecutive x-reg ABI slots (i64 / const char*).
const ScalRecordDesc = struct {
    field_names: []const []const u8,
    field_kinds: []const ScalFieldKind,
};

const ScalRecordMap = std.StringHashMapUnmanaged(ScalRecordDesc);

const FuncRecordReturns = std.StringHashMapUnmanaged(ScalRecordDesc);
const FuncF64RecordReturns = std.StringHashMapUnmanaged(F64RecordDesc);

const ByteBlob = struct {
    name: []const u8,
    bytes: []const u8,
};

fn tableExprToBytes(alloc: std.mem.Allocator, expr: *const ast.Expr) Error!?[]const u8 {
    if (expr.* != .table) return null;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);
    for (expr.table.fields) |fld| {
        const val: *const ast.Expr = switch (fld) {
            .named => |n| n.val,
            .positional => |v| v,
            else => return null,
        };
        if (val.* != .int_lit) return null;
        const v = val.int_lit.val;
        if (v < 0 or v > 255) return null;
        try out.append(alloc, @intCast(v));
    }
    if (out.items.len == 0) return null;
    return try out.toOwnedSlice(alloc);
}

fn collectByteBlobs(alloc: std.mem.Allocator, mod: *const ast.Module) Error![]ByteBlob {
    var blobs: std.ArrayList(ByteBlob) = .empty;
    errdefer {
        for (blobs.items) |b| alloc.free(b.bytes);
        blobs.deinit(alloc);
    }
    for (mod.body.stmts) |*stmt| {
        const parsed: ?struct { name: []const u8, val: *ast.Expr } = switch (stmt.*) {
            .assign => |as| blk: {
                if (as.targets.len != 1 or as.values.len != 1) break :blk null;
                if (as.targets[0].* != .name) break :blk null;
                break :blk .{ .name = as.targets[0].name.ident, .val = as.values[0] };
            },
            .const_decl => |cd| .{ .name = cd.ident, .val = cd.val },
            else => null,
        };
        const item = parsed orelse continue;
        const name = item.name;
        const val = item.val;
        const bytes = try tableExprToBytes(alloc, val) orelse continue;
        try blobs.append(alloc, .{ .name = name, .bytes = bytes });
    }
    return try blobs.toOwnedSlice(alloc);
}

fn freeByteBlobs(alloc: std.mem.Allocator, blobs: []const ByteBlob) void {
    for (blobs) |b| alloc.free(b.bytes);
}

fn collectF64Records(alloc: std.mem.Allocator, mod: *const ast.Module) Error!F64RecordMap {
    var map: F64RecordMap = .empty;
    errdefer freeF64Records(alloc, &map);
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .alias_def) continue;
        const ad = &stmt.alias_def;
        if (ad.type_params != null) continue;
        const target = ad.target orelse continue;
        const rec = switch (target) {
            .record => |r| r,
            else => continue,
        };
        if (rec.fields.len == 0) continue;
        var names: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer names.deinit(alloc);
        var all_f64 = true;
        for (rec.fields) |field| {
            if (!field.typ.is_float()) {
                all_f64 = false;
                break;
            }
            try names.append(alloc, field.name);
        }
        if (!all_f64) continue;
        try map.put(alloc, ad.name, .{
            .field_names = try names.toOwnedSlice(alloc),
        });
    }
    return map;
}

fn freeF64Records(alloc: std.mem.Allocator, map: *F64RecordMap) void {
    var it = map.iterator();
    while (it.next()) |entry| {
        alloc.free(entry.value_ptr.field_names);
    }
    map.deinit(alloc);
}

fn collectScalRecords(alloc: std.mem.Allocator, mod: *const ast.Module) Error!ScalRecordMap {
    var map: ScalRecordMap = .empty;
    errdefer freeScalRecords(alloc, &map);
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .alias_def) continue;
        const ad = &stmt.alias_def;
        if (ad.type_params != null) continue;
        const target = ad.target orelse continue;
        const rec = switch (target) {
            .record => |r| r,
            else => continue,
        };
        if (rec.fields.len == 0 or rec.fields.len > 8) continue;
        var names: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer names.deinit(alloc);
        var kinds: std.ArrayListUnmanaged(ScalFieldKind) = .empty;
        errdefer kinds.deinit(alloc);
        var ok = true;
        for (rec.fields) |field| {
            const kind: ScalFieldKind = if (field.typ == .named and std.mem.eql(u8, field.typ.named, "str"))
                .str
            else if (isIntegerAnnotation(field.typ))
                .i64
            else {
                ok = false;
                break;
            };
            try names.append(alloc, field.name);
            try kinds.append(alloc, kind);
        }
        if (!ok) continue;
        try map.put(alloc, ad.name, .{
            .field_names = try names.toOwnedSlice(alloc),
            .field_kinds = try kinds.toOwnedSlice(alloc),
        });
    }
    return map;
}

fn freeScalRecords(alloc: std.mem.Allocator, map: *ScalRecordMap) void {
    var it = map.iterator();
    while (it.next()) |entry| {
        alloc.free(entry.value_ptr.field_names);
        alloc.free(entry.value_ptr.field_kinds);
    }
    map.deinit(alloc);
}

fn scalRecordDesc(records: *const ScalRecordMap, typ: ast.TypeExpr) ?ScalRecordDesc {
    if (typ != .named) return null;
    return records.get(typ.named);
}

fn freeFuncRecordReturns(alloc: std.mem.Allocator, map: *FuncRecordReturns) void {
    map.deinit(alloc);
}

fn freeFuncF64RecordReturns(alloc: std.mem.Allocator, map: *FuncF64RecordReturns) void {
    map.deinit(alloc);
}

fn f64RecordDesc(records: *const F64RecordMap, typ: ast.TypeExpr) ?F64RecordDesc {
    if (typ != .named) return null;
    return records.get(typ.named);
}

fn paramFpSlotCount(records: *const F64RecordMap, typ: ast.TypeExpr) Error!usize {
    if (isFloatAnnotation(typ)) return 1;
    if (f64RecordDesc(records, typ)) |rec| return rec.field_names.len;
    return error.InvalidMainSignature;
}

fn totalParamFpSlots(records: *const F64RecordMap, fd: *const ast.FuncDecl) Error!usize {
    var total: usize = 0;
    for (fd.func.params) |param| {
        total += try paramFpSlotCount(records, param.typ);
    }
    return total;
}

fn isPureF64KernelFunction(records: *const F64RecordMap, fd: *const ast.FuncDecl) bool {
    if (!returnsFloat(fd.func.ret_type)) return false;
    var slots: usize = 0;
    for (fd.func.params) |param| {
        const n = paramFpSlotCount(records, param.typ) catch return false;
        if (n == 0) return false;
        slots += n;
    }
    return slots <= 8;
}

const Condition = enum(u4) {
    eq = 0x0,
    ne = 0x1,
    ge = 0xa,
    lt = 0xb,
    gt = 0xc,
    le = 0xd,
};

const Arm64Output = struct {
    text: []u8,
    asm_text: []u8,
    cstring: []u8 = &.{},
    symbols: []Symbol,
    relocations: []Relocation,
    /// Bytes of `__DATA,__bss` zerofill arena this module needs. 0 means the
    /// section is not emitted at all, which is the pre-arena behavior verbatim.
    bss_size: u64 = 0,

    fn deinit(self: *Arm64Output, alloc: std.mem.Allocator) void {
        alloc.free(self.text);
        alloc.free(self.asm_text);
        if (self.cstring.len > 0) alloc.free(self.cstring);
        for (self.symbols) |sym| alloc.free(sym.name);
        alloc.free(self.symbols);
        alloc.free(self.relocations);
    }
};

const NativeModule = struct {
    functions: []NativeFunction,
    externs: []ExternalSymbol,

    fn deinit(self: *NativeModule, alloc: std.mem.Allocator) void {
        alloc.free(self.functions);
        for (self.externs) |sym| {
            alloc.free(sym.local_name);
            alloc.free(sym.symbol_name);
        }
        alloc.free(self.externs);
    }
};

fn collectFunctions(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    scal_records: *const ScalRecordMap,
    func_record_returns: *FuncRecordReturns,
) Error!NativeModule {
    var records = try collectF64Records(alloc, mod);
    defer freeF64Records(alloc, &records);

    var funcs: std.ArrayList(NativeFunction) = .empty;
    errdefer funcs.deinit(alloc);
    var externs: std.ArrayList(ExternalSymbol) = .empty;
    errdefer {
        for (externs.items) |sym| {
            alloc.free(sym.local_name);
            alloc.free(sym.symbol_name);
        }
        externs.deinit(alloc);
    }
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        const fd = &stmt.func_decl;
        if (fd.path.len != 1 or fd.method or fd.is_local) continue;
        if (funcFfiName(fd.attributes)) |ffi_name| {
            try appendUniqueExternal(alloc, &externs, fd.path[0], ffi_name);
            continue;
        }
        try validateFunction(fd, &records, scal_records);
        if (scalRecordDesc(scal_records, fd.func.ret_type)) |rec| {
            try func_record_returns.put(alloc, fd.path[0], rec);
        }
        const symbol_name = funcExportName(fd) orelse fd.path[0];
        try funcs.append(alloc, .{ .decl = fd, .symbol_name = symbol_name });
    }
    if (funcs.items.len == 0) return error.MissingMain;
    return .{
        .functions = try funcs.toOwnedSlice(alloc),
        .externs = try externs.toOwnedSlice(alloc),
    };
}

fn validateFunction(
    fd: *const ast.FuncDecl,
    records: *const F64RecordMap,
    scal_records: *const ScalRecordMap,
) Error!void {
    if (fd.func.vararg or fd.func.vararg_name != null) {
        return error.InvalidMainSignature;
    }
    for (fd.func.params) |param| {
        if (param.default_val != null) return refuse(@src());
    }
    const ret_float = returnsFloat(fd.func.ret_type);
    const ret_int = returnsInteger(fd.func.ret_type);
    const ret_scal = scalRecordDesc(scal_records, fd.func.ret_type) != null;
    if (!ret_int and !ret_float and !ret_scal and !returnsVoid(fd.func.ret_type)) {
        return error.InvalidMainSignature;
    }
    if (ret_scal) {
        if (fd.func.params.len > 8) return refuse(@src());
        for (fd.func.params) |param| {
            if (!isIntegerAnnotation(param.typ) and !(param.typ == .named and std.mem.eql(u8, param.typ.named, "str"))) {
                return error.InvalidMainSignature;
            }
        }
        return;
    }
    if (ret_float) {
        const slots = try totalParamFpSlots(records, fd);
        if (slots > 8) return error.InvalidMainSignature;
        return;
    }
    if (fd.func.params.len > 8) return refuse(@src());
    for (fd.func.params) |param| {
        // `str` is a `const char*` — an integer-class argument that rides x0..x7
        // exactly like an i64. The record-returning path above already accepts
        // it; excluding it here was an oversight, and it rejected every
        // `f(s: str): i64` reaching the AST path (which is any function using
        // `and`/`or`, since DNIR lowering has no arm for them).
        // `ptr` is the base address of a memory-backed positional table — an
        // integer-class argument in x0..x7 like `i64` and `str`. Admitting it is
        // what lets a table cross a function boundary at all (SH-04).
        if (!isIntegerAnnotation(param.typ) and !isStrAnnotation(param.typ) and !isPtrAnnotation(param.typ)) {
            return error.InvalidMainSignature;
        }
    }
}

fn isPtrAnnotation(t: ast.TypeExpr) bool {
    return switch (t) {
        .named => |name| std.mem.eql(u8, name, "ptr") or std.mem.eql(u8, name, "void*"),
        else => false,
    };
}

fn isStrAnnotation(t: ast.TypeExpr) bool {
    return t == .named and std.mem.eql(u8, t.named, "str");
}

fn isFloatAnnotation(t: ast.TypeExpr) bool {
    return t.is_float(); // named == "f32" or "f64"
}

fn returnsFloat(t: ast.TypeExpr) bool {
    return isFloatAnnotation(t);
}

fn isPureFloatFunction(records: *const F64RecordMap, fd: *const ast.FuncDecl) bool {
    return isPureF64KernelFunction(records, fd);
}

fn appendUniqueExternal(alloc: std.mem.Allocator, externs: *std.ArrayList(ExternalSymbol), local_name: []const u8, symbol_name: []const u8) Error!void {
    for (externs.items) |ext| {
        if (std.mem.eql(u8, ext.local_name, local_name)) {
            if (std.mem.eql(u8, ext.symbol_name, symbol_name)) return;
            return error.DuplicateSymbol;
        }
    }
    const owned_local = try alloc.dupe(u8, local_name);
    errdefer alloc.free(owned_local);
    const owned_symbol = try alloc.dupe(u8, symbol_name);
    errdefer alloc.free(owned_symbol);
    try externs.append(alloc, .{ .local_name = owned_local, .symbol_name = owned_symbol });
}

fn funcFfiName(attrs: []const ast.Attribute) ?[]const u8 {
    for (attrs) |attr| {
        if (!std.mem.eql(u8, attr.name, "ffi")) continue;
        const raw = attr.args orelse return null;
        if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"') return raw[1 .. raw.len - 1];
        return raw;
    }
    return null;
}

fn funcExportName(fd: *const ast.FuncDecl) ?[]const u8 {
    for (fd.attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "export")) return fd.path[0];
        if (!std.mem.eql(u8, attr.name, "c.export")) continue;
        const raw = attr.args orelse return fd.path[0];
        if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"') return raw[1 .. raw.len - 1];
        return raw;
    }
    return null;
}

/// Zero-arg i64/void/f64 module function suitable as a native executable entry.
/// f64 entries coerce to i64 exit codes at link time via `fcvtzs x0, d0`.
fn isZeroArgEntryFunction(fd: *const ast.FuncDecl) bool {
    if (fd.path.len != 1 or fd.method or fd.is_local) return false;
    if (fd.func.params.len != 0) return false;
    if (funcFfiName(fd.attributes) != null) return false;
    return returnsInteger(fd.func.ret_type) or returnsVoid(fd.func.ret_type) or returnsFloat(fd.func.ret_type);
}

fn findModuleFunction(mod: *const ast.Module, name: []const u8) ?*const ast.FuncDecl {
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        const fd = &stmt.func_decl;
        if (fd.path.len == 1 and std.mem.eql(u8, fd.path[0], name)) return fd;
    }
    return null;
}

/// Linker entry for native executables. Duo has no mandatory `main()` — file-scope
/// functions export uniformly. Prefer an explicit `@export` zero-arg i64/void/f64 entry,
/// else a sole eligible zero-arg function, else a function literally named `main`.
/// When `override` is set (`--entry`), it must name an eligible zero-arg function.
/// Does the module have a file-scope BODY — statements that do something, as
/// opposed to declarations that merely bind?
///
/// This is the difference between a script and a library-shaped module, and it
/// decides whether the sole-zero-arg-function entry heuristic below is safe.
/// Bindings (`local`/`const`/`global`/`func`) and pure type/interface
/// declarations are not a program; calls, control flow and assignments are.
fn moduleHasFileScopeProgram(mod: *const ast.Module) bool {
    for (mod.body.stmts) |*stmt| switch (stmt.*) {
        .call_stmt, .expr_stmt, .assign, .do_block, .while_loop, .repeat_loop, .if_stmt, .num_for, .gen_for, .ret, .match_stmt, .try_stmt, .defer_stmt => return true,
        else => {},
    };
    return false;
}

pub fn pickNativeEntrySymbol(mod: *const ast.Module) ?[]const u8 {
    var sole: ?[]const u8 = null;
    var sole_count: usize = 0;
    var named_main: ?[]const u8 = null;

    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        const fd = &stmt.func_decl;
        if (!isZeroArgEntryFunction(fd)) continue;

        if (std.mem.eql(u8, fd.path[0], "main")) named_main = fd.path[0];
        if (funcExportName(fd) != null) return fd.path[0];
        sole = fd.path[0];
        sole_count += 1;
    }
    if (named_main) |m| return m;
    // The sole-zero-arg-function rule is an INFERENCE, not a declaration, and
    // it is only sound when there is no file-scope body to lose. A script like
    //
    //     w = (): i64
    //         42
    //     end
    //     print("before")
    //     print(w())
    //
    // has exactly one zero-arg i64 function, so this used to promote `w` to the
    // process entry — which silently DISCARDED both prints and made the
    // program's exit status 42. No diagnostic, and the C backend printed the
    // right thing, so the two backends disagreed on what the program even was.
    // The native-differential harness compares exit status only, so it did not
    // catch this either.
    //
    // That is what `examples/native_abi_smoke.duo` was failing on: its
    // `use_native()` was the sole zero-arg i64 function, so the smoke test
    // exited 30 (the sum, as a status) having never run its own assertion. The
    // @native ABI it exists to test was working the whole time.
    //
    // `main`, `@export` and `--entry` are DELIBERATE and still win above; only
    // the inference is refused here, which falls back to the C emit bootstrap
    // under `--backend=auto` and to an honest "no linker entry" under
    // `--backend=direct`.
    if (sole_count == 1 and !moduleHasFileScopeProgram(mod)) return sole;
    return null;
}

pub fn resolveNativeEntrySymbol(mod: *const ast.Module, override: ?[]const u8) ?[]const u8 {
    if (override) |name| {
        const fd = findModuleFunction(mod, name) orelse return null;
        if (!isZeroArgEntryFunction(fd)) return null;
        return name;
    }
    return pickNativeEntrySymbol(mod);
}

const Arm64Compiler = struct {
    alloc: std.mem.Allocator,
    f64_records: *const F64RecordMap,
    scal_records: *const ScalRecordMap,
    func_record_returns: *const FuncRecordReturns,
    func_f64_record_returns: *const FuncF64RecordReturns,
    req_ctx: *const native_req_support.Context,
    code: std.ArrayList(u8) = .empty,
    asm_text: std.ArrayList(u8) = .empty,
    locals: std.StringHashMapUnmanaged(u5) = .empty,
    symbols: std.ArrayList(Symbol) = .empty,
    extern_symbols: std.StringHashMapUnmanaged(u32) = .empty,
    relocations: std.ArrayList(Relocation) = .empty,
    call_patches: std.ArrayList(CallPatch) = .empty,
    loops: std.ArrayList(LoopContext) = .empty,
    used_regs: [29]bool = @splat(false),
    next_label: u32 = 0,
    returned: bool = false,
    strings: std.ArrayList(StringSymbol) = .empty,
    string_map: std.StringHashMapUnmanaged(u32) = .empty,
    next_string: u32 = 0,
    // f64 native lowering: per-function FP state. cur_func_float routes a
    // pure-f64 function (all params + return f64) through compileExprFp.
    // FP params arrive in d0-d7 (caller-saved) and the result returns in d0.
    cur_func_float: bool = false,
    /// Function returns f64 but is not a pure-f64 kernel (zero-param shell, etc.).
    cur_func_ret_float: bool = false,
    cur_func_name: ?[]const u8 = null,
    /// When set, this function's f64 return is coerced to i64 for process exit.
    process_entry: ?[]const u8 = null,
    cur_func_ret_record: ?ScalRecordDesc = null,
    cur_func_ret_f64_record: ?F64RecordDesc = null,
    /// Where this function parked the AAPCS64 indirect-result pointer it was
    /// handed in x8. Only set when `cur_func_ret_record` is wider than the
    /// argument register file. x8 is caller-saved, so a body containing any
    /// call would lose it; `emitSaveCallerRegs` preserves x9..x28, which is why
    /// the pointer moves there on entry rather than being read at `ret`.
    cur_ret_indirect_reg: ?u5 = null,
    /// Backing store for `dnirRetRecordVals`'s lhs/rhs/third fallback.
    ret_record_scratch: [3]dnir.Value = @splat(.void),
    fp_locals: std.StringHashMapUnmanaged(u5) = .empty,
    used_fp_regs: [32]bool = @splat(false),
    /// Stack slots for sealed record fields (f64 or i64): "c.pos" -> slot meta.
    fp_stack_slots: std.StringHashMapUnmanaged(StackSlot) = .empty,
    stack_frame_bytes: u16 = 0,
    /// `alloc_slots` result temp -> sp-relative byte offset of its slot region.
    slot_bases: std.AutoHashMapUnmanaged(u32, u16) = .empty,
    f64_kernel_names: std.StringHashMapUnmanaged(void) = .empty,
    blob_symbol_map: std.StringHashMapUnmanaged(u32) = .empty,
    spilled_regs: std.AutoHashMapUnmanaged(u5, u16) = .empty,
    /// Spill slots for integer regs when x9-x28 exhausted (Pass 11 WP-03).
    spill_offsets: std.ArrayList(u16) = .empty,
    spill_reg_count: u5 = 0,
    raw_blobs: std.ArrayList(RawBlobSymbol) = .empty,
    /// Arguments staged for the NEXT call's variadic tail. Apple's ARM64 ABI
    /// diverges from AAPCS64 here: every argument past a variadic function's
    /// last NAMED parameter travels on the STACK, 8-byte aligned, never in
    /// x0..x7. A `mov_arg` marked `.field = "vararg"` lands here instead of in
    /// a parameter register, and the call flushes the list to [sp, #i*8].
    pending_varargs: [8]VarArg = @splat(.{}),
    pending_vararg_count: u5 = 0,

    const VarArg = struct {
        reg: u5 = 0,
        /// The register was allocated for this argument alone (an immediate or
        /// a string address), so the call must hand it back. A `.temp`/`.local`
        /// register is owned by the slot map and outlives the call.
        scratch: bool = false,
    };

    const CallPatch = struct {
        offset: u32,
        target: []const u8,
    };

    const StackSlot = struct {
        off: u16,
        float: bool,
    };

    const LoopContext = struct {
        continue_label: u32,
        end_label: u32,
        continue_patches: std.ArrayList(u32),
        break_patches: std.ArrayList(u32),
    };

    const SaveSet = struct {
        regs: [20]u5 = @splat(0),
        count: u5 = 0,
        stack_bytes: u16 = 0,
    };

    const StringSymbol = struct {
        bytes: []const u8,
        name: []const u8,
        symbol_index: u32,
    };

    const RawBlobSymbol = struct {
        bytes: []const u8,
        name: []const u8,
        symbol_index: u32,
    };

    const DnirBranchPatch = struct {
        patch_off: u32,
        target_instr: u32,
        is_cond: bool,
    };

    fn deinit(self: *Arm64Compiler) void {
        self.code.deinit(self.alloc);
        self.asm_text.deinit(self.alloc);
        self.locals.deinit(self.alloc);
        for (self.symbols.items) |sym| self.alloc.free(sym.name);
        self.symbols.deinit(self.alloc);
        self.extern_symbols.deinit(self.alloc);
        self.relocations.deinit(self.alloc);
        self.call_patches.deinit(self.alloc);
        for (self.loops.items) |*loop| {
            loop.continue_patches.deinit(self.alloc);
            loop.break_patches.deinit(self.alloc);
        }
        self.loops.deinit(self.alloc);
        for (self.strings.items) |s| {
            self.alloc.free(s.bytes);
            self.alloc.free(s.name);
        }
        self.strings.deinit(self.alloc);
        self.string_map.deinit(self.alloc);
        self.fp_locals.deinit(self.alloc);
        self.fp_stack_slots.deinit(self.alloc);
        self.slot_bases.deinit(self.alloc);
        self.f64_kernel_names.deinit(self.alloc);
        self.blob_symbol_map.deinit(self.alloc);
        self.spilled_regs.deinit(self.alloc);
        self.spill_offsets.deinit(self.alloc);
        for (self.raw_blobs.items) |b| self.alloc.free(b.name);
        self.raw_blobs.deinit(self.alloc);
    }

    fn emitAsmHeader(self: *Arm64Compiler) Error!void {
        try self.asm_text.appendSlice(self.alloc,
            \\.section __TEXT,__text,regular,pure_instructions
            \\.p2align 2
        );
    }

    fn finish(self: *Arm64Compiler) Error!Arm64Output {
        try self.patchCalls();

        var cstring: std.ArrayList(u8) = .empty;
        errdefer cstring.deinit(self.alloc);
        if (self.strings.items.len > 0 or self.raw_blobs.items.len > 0) {
            try self.asm_text.appendSlice(self.alloc, "\n.section __TEXT,__cstring\n");
            var str_off: u32 = 0;
            for (self.strings.items) |s| {
                self.symbols.items[s.symbol_index].offset = @intCast(self.code.items.len + str_off);
                try self.asm_text.appendSlice(self.alloc, s.name);
                try self.asm_text.appendSlice(self.alloc, ":\n");
                try self.emitAscizAsm(s.bytes);
                try cstring.appendSlice(self.alloc, s.bytes);
                try cstring.append(self.alloc, 0);
                str_off += @intCast(s.bytes.len + 1);
            }
            for (self.raw_blobs.items) |b| {
                self.symbols.items[b.symbol_index].offset = @intCast(self.code.items.len + str_off);
                try self.asm_text.appendSlice(self.alloc, b.name);
                try self.asm_text.appendSlice(self.alloc, ":\n");
                try self.emitRawBytesAsm(b.bytes);
                try cstring.appendSlice(self.alloc, b.bytes);
                str_off += @intCast(b.bytes.len);
            }
        }
        const cstring_bytes = try cstring.toOwnedSlice(self.alloc);
        errdefer self.alloc.free(cstring_bytes);

        // Mach-O stores section relocations sorted by descending r_address.
        std.mem.sort(Relocation, self.relocations.items, {}, relocDescByOffset);

        const text = try self.code.toOwnedSlice(self.alloc);
        errdefer self.alloc.free(text);
        const asm_text = try self.asm_text.toOwnedSlice(self.alloc);
        errdefer self.alloc.free(asm_text);
        const symbols = try self.symbols.toOwnedSlice(self.alloc);
        self.symbols = .empty;
        errdefer {
            for (symbols) |sym| self.alloc.free(sym.name);
            self.alloc.free(symbols);
        }
        const relocations = try self.relocations.toOwnedSlice(self.alloc);
        self.relocations = .empty;
        return .{ .text = text, .asm_text = asm_text, .cstring = cstring_bytes, .symbols = symbols, .relocations = relocations };
    }

    fn internString(self: *Arm64Compiler, content: []const u8) Error!u32 {
        if (self.string_map.get(content)) |idx| return idx;
        const idx: u32 = @intCast(self.symbols.items.len);
        const owned_name = try std.fmt.allocPrint(self.alloc, "Lduo_str_{d}", .{self.next_string});
        self.next_string += 1;
        errdefer self.alloc.free(owned_name);
        try self.symbols.append(self.alloc, .{
            .name = owned_name,
            .offset = 0,
            .defined = true,
            .section = 2,
            .external = false,
        });
        const owned_bytes = try self.alloc.dupe(u8, content);
        errdefer self.alloc.free(owned_bytes);
        try self.strings.append(self.alloc, .{ .bytes = owned_bytes, .name = owned_name, .symbol_index = idx });
        try self.string_map.put(self.alloc, owned_bytes, idx);
        return idx;
    }

    fn emitAdrpAdd(self: *Arm64Compiler, reg: u5, symbol_index: u32) Error!void {
        const sname = self.symbols.items[symbol_index].name;
        const page_off: u32 = @intCast(self.code.items.len);
        try self.emitFmt(0x90000000 | @as(u32, reg), "adrp x{d}, {s}@PAGE", .{ reg, sname });
        try self.relocations.append(self.alloc, .{ .offset = page_off, .symbol_index = symbol_index, .kind = .page21 });
        const off_off: u32 = @intCast(self.code.items.len);
        try self.emitFmt(0x91000000 | (@as(u32, reg) << 5) | @as(u32, reg), "add x{d}, x{d}, {s}@PAGEOFF", .{ reg, reg, sname });
        try self.relocations.append(self.alloc, .{ .offset = off_off, .symbol_index = symbol_index, .kind = .pageoff12 });
    }

    fn emitRawBytesAsm(self: *Arm64Compiler, bytes: []const u8) Error!void {
        try self.asm_text.appendSlice(self.alloc, "\t.byte ");
        for (bytes, 0..) |b, i| {
            if (i > 0) try self.asm_text.appendSlice(self.alloc, ", ");
            try self.asm_text.print(self.alloc, "0x{x:0>2}", .{b});
        }
        try self.asm_text.appendSlice(self.alloc, "\n");
    }

    fn registerByteBlobs(self: *Arm64Compiler, blobs: []const ByteBlob) Error!void {
        for (blobs) |blob| {
            const idx: u32 = @intCast(self.symbols.items.len);
            const sym_name = try std.fmt.allocPrint(self.alloc, "Lduo_blob_{s}", .{blob.name});
            errdefer self.alloc.free(sym_name);
            try self.symbols.append(self.alloc, .{
                .name = sym_name,
                .offset = 0,
                .defined = true,
                .section = 2,
                .external = false,
            });
            try self.raw_blobs.append(self.alloc, .{
                .bytes = blob.bytes,
                .name = sym_name,
                .symbol_index = idx,
            });
            try self.blob_symbol_map.put(self.alloc, blob.name, idx);
        }
    }

    fn emitBlobPtr(self: *Arm64Compiler, reg: u5, symbol_index: u32) Error!void {
        try self.emitAdrpAdd(reg, symbol_index);
    }

    fn emitAscizAsm(self: *Arm64Compiler, bytes: []const u8) Error!void {
        try self.asm_text.appendSlice(self.alloc, "\t.asciz \"");
        for (bytes) |b| {
            switch (b) {
                '"' => try self.asm_text.appendSlice(self.alloc, "\\\""),
                '\\' => try self.asm_text.appendSlice(self.alloc, "\\\\"),
                '\n' => try self.asm_text.appendSlice(self.alloc, "\\n"),
                '\t' => try self.asm_text.appendSlice(self.alloc, "\\t"),
                '\r' => try self.asm_text.appendSlice(self.alloc, "\\r"),
                0x20...0x21, 0x23...0x5b, 0x5d...0x7e => try self.asm_text.append(self.alloc, b),
                else => try self.asm_text.print(self.alloc, "\\x{x:0>2}", .{b}),
            }
        }
        try self.asm_text.appendSlice(self.alloc, "\"\n");
    }

    fn compileModule(self: *Arm64Compiler, funcs: []const NativeFunction, externs: []const ExternalSymbol, blobs: []const ByteBlob) Error!void {
        try self.registerByteBlobs(blobs);
        for (funcs) |func| {
            if (isPureFloatFunction(self.f64_records, func.decl)) {
                try self.f64_kernel_names.put(self.alloc, func.symbol_name, {});
            }
        }
        try self.emitAsmHeader();
        for (funcs) |func| {
            try self.compileFunction(func);
        }
        for (externs) |ext| {
            if (self.symbolOffset(ext.symbol_name)) |_| return error.DuplicateSymbol;
            const owned_name = try self.alloc.dupe(u8, ext.symbol_name);
            errdefer self.alloc.free(owned_name);
            const symbol_index: u32 = @intCast(self.symbols.items.len);
            try self.symbols.append(self.alloc, .{ .name = owned_name, .offset = 0, .defined = false });
            try self.extern_symbols.put(self.alloc, ext.local_name, symbol_index);
        }
    }

    fn needsProcessExitF64Coerce(self: *const Arm64Compiler) bool {
        const entry = self.process_entry orelse return false;
        const cur = self.cur_func_name orelse return false;
        if (!std.mem.eql(u8, entry, cur)) return false;
        return self.cur_func_float or self.cur_func_ret_float;
    }

    fn compileDnirModule(self: *Arm64Compiler, m: dnir.Module) Error!void {
        try self.emitAsmHeader();
        for (m.functions) |f| {
            if (f.is_float_kernel) try self.f64_kernel_names.put(self.alloc, f.name, {});
        }
        if (m.functions.len == 0) return error.MissingMain;
        for (m.functions) |f| {
            try self.compileDnirFunction(f);
        }
        for (m.externs) |ext| {
            try self.ensureExternalSymbol(ext.symbol);
        }
    }

    /// True when the body contains any call, so parameters must be relocated out
    /// of the argument/return registers to survive it.
    fn dnirFunctionHasCall(f: dnir.Function) bool {
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.op == .call_direct or ins.op == .call_extern) return true;
            }
        }
        return false;
    }

    fn regIsPinned(pinned: *const std.AutoHashMapUnmanaged(u32, u5), reg: u5) bool {
        var it = pinned.valueIterator();
        while (it.next()) |slot_reg| {
            if (slot_reg.* == reg) return true;
        }
        return false;
    }

    fn compileDnirFunction(self: *Arm64Compiler, f: dnir.Function) Error!void {
        self.cur_func_name = f.name;
        self.locals.clearRetainingCapacity();
        self.fp_locals.clearRetainingCapacity();
        // A staged variadic tail belongs to exactly one call. Carrying a
        // leftover across a function boundary would push a stale register onto
        // the next call's memory-argument area, so clear it with the rest of
        // the per-function register state.
        self.pending_vararg_count = 0;
        self.used_regs = @splat(false);
        self.used_fp_regs = @splat(false);
        self.returned = false;
        self.fp_stack_slots.clearRetainingCapacity();
        self.stack_frame_bytes = 0;
        self.cur_func_ret_record = if (f.ret_record) |rn| scalRecordDesc(self.scal_records, .{ .named = rn }) else null;
        self.cur_func_ret_f64_record = if (f.ret_record) |rn| f64RecordDesc(self.f64_records, .{ .named = rn }) else null;
        self.cur_ret_indirect_reg = null;
        self.cur_func_float = f.is_float_kernel;
        self.cur_func_ret_float = f.ret == .f64 and !f.is_float_kernel;

        const offset: u32 = @intCast(self.code.items.len);
        const link_name = try linkerSymbolName(self.alloc, f.name);
        try self.symbols.append(self.alloc, .{ .name = link_name, .offset = offset, .defined = true });
        try self.asm_text.appendSlice(self.alloc, "\n.globl _");
        try self.asm_text.appendSlice(self.alloc, link_name);
        try self.asm_text.appendSlice(self.alloc, "\n.p2align 2\n_");
        try self.asm_text.appendSlice(self.alloc, link_name);
        try self.asm_text.appendSlice(self.alloc, ":\n");

        var temps: std.AutoHashMapUnmanaged(u32, u5) = .empty;
        defer temps.deinit(self.alloc);
        var pinned: std.AutoHashMapUnmanaged(u32, u5) = .empty;
        defer pinned.deinit(self.alloc);

        if (f.is_float_kernel) {
            var dreg: u5 = 0;
            for (f.params, 0..) |p, i| {
                const slot: u32 = @intCast(i);
                if (p.ty == .f64) {
                    self.used_fp_regs[dreg] = true;
                    try self.fp_locals.put(self.alloc, p.name, dreg);
                    try temps.put(self.alloc, slot, dreg);
                    dreg += 1;
                } else if (p.record) |rec_name| {
                    const rec = f64RecordDesc(self.f64_records, .{ .named = rec_name }) orelse return refuse(@src());
                    for (rec.field_names) |fname| {
                        self.used_fp_regs[dreg] = true;
                        const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ p.name, fname });
                        try self.fp_locals.put(self.alloc, key, dreg);
                        dreg += 1;
                    }
                } else return refuse(@src());
            }
        } else {
            // x0..x7 are both the argument registers and the return-value
            // register, and `emitSaveCallerRegs` only preserves x9..x28. A
            // parameter left in its incoming register is therefore destroyed by
            // any call: in `fib(n-1) + fib(n-2)` the second operand read x0
            // after the first call and computed `fib(n-1) - 2` instead of
            // `n - 2`. Copy parameters into the caller-saved range when the body
            // can call; leaf functions keep the incoming register and pay nothing.
            const body_has_call = dnirFunctionHasCall(f);
            // Claim the indirect-result pointer FIRST, while x8 still holds what
            // the caller put there. Everything after this can call, and x8 does
            // not survive a call.
            if (self.cur_func_ret_record) |rec| {
                if (rec.field_names.len > dnir_lower.max_reg_record_fields) {
                    const home = try self.allocReg();
                    try self.emitMovReg(home, 8);
                    self.cur_ret_indirect_reg = home;
                }
            }
            // A record parameter occupies one ABI slot per field, so slots are
            // not 1:1 with parameters; walk a cursor. This mirrors how the
            // lowerer assigns `p.field` locals.
            var slot_cursor: u32 = 0;
            for (f.params) |p| {
                var slots_for_param: u32 = 1;
                if (p.record) |rec_name| {
                    if (scalRecordDesc(self.scal_records, .{ .named = rec_name })) |rec| {
                        slots_for_param = @intCast(rec.field_names.len);
                    }
                }
                var k: u32 = 0;
                while (k < slots_for_param) : (k += 1) {
                    if (slot_cursor >= 8) return refuse(@src());
                    const slot = slot_cursor;
                    const arg_reg: u5 = @intCast(slot);
                    if (body_has_call) {
                        const home = try self.allocReg();
                        try self.emitMovReg(home, arg_reg);
                        try temps.put(self.alloc, slot, home);
                        try pinned.put(self.alloc, slot, home);
                    } else {
                        try temps.put(self.alloc, slot, arg_reg);
                        try pinned.put(self.alloc, slot, arg_reg);
                    }
                    slot_cursor += 1;
                }
            }
        }

        // Reserve every record's stack slot ONCE, here in the prologue.
        //
        // Reserving where the record is produced re-executes on each loop
        // iteration and is never balanced before the back-edge, so `sp` walks
        // down a frame per iteration and every field offset shifts — a record
        // built inside a loop then reads garbage. Offsets are sp-relative and
        // only meaningful against a frame reserved once, so size the frame by a
        // pre-pass and hand out fixed offsets.
        //
        // Skipped when the function also builds f64 records: those still reserve
        // at point of use, and their `sub sp` would shift offsets assigned here.
        var has_f64_record = false;
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.record.len == 0) continue;
                if (f64RecordDesc(self.f64_records, .{ .named = ins.record }) != null) has_f64_record = true;
            }
        }
        if (!has_f64_record) {
            var record_frame: u16 = 0;
            for (f.blocks) |b| {
                for (b.instrs) |ins| {
                    if (ins.record.len == 0) continue;
                    switch (ins.op) {
                        .init_record, .call_direct, .call_extern => {},
                        else => continue,
                    }
                    const rec = scalRecordDesc(self.scal_records, .{ .named = ins.record }) orelse continue;
                    // A record wider than the argument file is returned
                    // INDIRECTLY, and this reservation is the buffer the callee
                    // writes through — so it has to be made here too, not only
                    // for the records that arrive in x0..x7.
                    if (rec.field_names.len == 0 or rec.field_names.len > dnir_lower.max_record_fields) continue;
                    const base = if (ins.field.len > 0) ins.field else "rec";
                    const probe = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ base, rec.field_names[0] });
                    defer self.alloc.free(probe);
                    if (self.fp_stack_slots.contains(probe)) continue;
                    for (rec.field_names, 0..) |fname, i| {
                        const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ base, fname });
                        const off: u16 = record_frame + @as(u16, @intCast(i * 8));
                        try self.fp_stack_slots.put(self.alloc, key, .{ .off = off, .float = false });
                    }
                    record_frame += @intCast(std.mem.alignForward(usize, rec.field_names.len * 8, 16));
                }
            }
            if (record_frame > 0) {
                try self.emitSubSp(record_frame);
                self.stack_frame_bytes += record_frame;
            }
        }

        // Memory-backed positional tables. Same reasoning as records above: the
        // reservation must happen once, not at the point of use, or a table
        // built inside a loop walks `sp` down a frame per iteration. Each
        // `alloc_slots` gets a fixed sp-relative offset assigned here, keyed by
        // the instruction's own result temp.
        self.slot_bases.clearRetainingCapacity();
        {
            var slots_frame: u16 = 0;
            for (f.blocks) |b| {
                for (b.instrs) |ins| {
                    if (ins.op != .alloc_slots) continue;
                    const t = ins.result orelse continue;
                    const n: u16 = switch (ins.lhs) {
                        .i64 => |v| if (v > 0 and v <= 4096) @intCast(v) else return refuse(@src()),
                        else => return refuse(@src()),
                    };
                    const bytes: u16 = @intCast(std.mem.alignForward(usize, @as(usize, n) * 8, 16));
                    if (@as(u32, slots_frame) + bytes > 32752) return refuse(@src());
                    try self.slot_bases.put(self.alloc, t, slots_frame);
                    slots_frame += bytes;
                }
            }
            if (slots_frame > 0) {
                try self.emitSubSp(slots_frame);
                self.stack_frame_bytes += slots_frame;
                // Offsets were handed out relative to the base of this region,
                // which sits at the *bottom* of the frame reserved so far, so
                // they are already correct sp-relative displacements.
            }
        }

        var code_offsets: std.ArrayList(u32) = .empty;
        defer code_offsets.deinit(self.alloc);
        var branch_patches: std.ArrayList(DnirBranchPatch) = .empty;
        defer branch_patches.deinit(self.alloc);

        // Whether the LAST instruction emitted was a terminator. `self.returned`
        // is a single flag for the whole function, so an early `return` inside an
        // `if` marks it true even when the fall-through path just runs off the
        // end — the function then executes whatever symbol the linker placed
        // next. Track the final instruction separately.
        var tail_terminates = false;
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                try code_offsets.append(self.alloc, @intCast(self.code.items.len));
                try self.compileDnirInstr(&temps, &pinned, ins, &branch_patches);
                tail_terminates = switch (ins.op) {
                    .ret, .ret_record, .br => true,
                    else => false,
                };
            }
        }
        // Sentinel: branch_target may equal instr count (fall-through past if-block).
        try code_offsets.append(self.alloc, @intCast(self.code.items.len));
        for (branch_patches.items) |p| {
            if (p.target_instr >= code_offsets.items.len) return refuse(@src());
            const target_off = code_offsets.items[p.target_instr];
            if (p.is_cond) {
                try self.patchCondBranch(p.patch_off, target_off);
            } else {
                try self.patchB(p.patch_off, target_off);
            }
        }
        if (!self.returned) return refuse(@src());
        // Falling off the end of a function is never recoverable at runtime:
        // execution continues into whatever symbol the linker placed next
        // (here, straight into _duo_keyword_classify → SIGSEGV). Refuse instead
        // of emitting it, so the honest DNB001 path reports the gap.
        if (!tail_terminates) return refuse(@src());
    }

    fn compileDnirInstr(
        self: *Arm64Compiler,
        temps: *std.AutoHashMapUnmanaged(u32, u5),
        pinned: *std.AutoHashMapUnmanaged(u32, u5),
        ins: dnir.Instr,
        branch_patches: *std.ArrayList(DnirBranchPatch),
    ) Error!void {
        switch (ins.op) {
            .const_i64, .const_req => {
                const reg = try self.allocReg();
                const val: i64 = switch (ins.lhs) {
                    .i64 => |v| v,
                    else => if (ins.op == .const_req) ins.lhs.i64 else return refuse(@src()),
                };
                try self.emitMovImm(reg, val);
                if (ins.result) |t| try temps.put(self.alloc, t, reg);
            },
            .const_f64 => {
                const d = try self.allocFpReg();
                const val: f64 = switch (ins.lhs) {
                    .f64 => |v| v,
                    else => return refuse(@src()),
                };
                try self.emitFmovImmFp(d, val);
                if (ins.result) |t| try temps.put(self.alloc, t, d);
            },
            .const_str => {
                const reg = try self.allocReg();
                const s = ins.lhs.str;
                const sym = try self.internString(s);
                try self.emitAdrpAdd(reg, sym);
                if (ins.result) |t| try temps.put(self.alloc, t, reg);
            },
            .fp_mov_arg => {
                const d_slot: u5 = @intCast(ins.result orelse return refuse(@src()));
                self.used_fp_regs[d_slot] = true;
                switch (ins.lhs) {
                    .f64 => |n| try self.emitFmovImmFp(d_slot, n),
                    else => {
                        const src = try self.evalDnirFpArg(temps, ins.lhs);
                        if (src != d_slot) try self.emitFmovReg(d_slot, src);
                        if (src != d_slot) self.releaseFpReg(src);
                    },
                }
            },
            .mov_arg => {
                // `.field = "vararg"` means `result` is a VARIADIC-tail index,
                // not a parameter register. See `pending_varargs`: on Apple
                // ARM64 the tail is passed in memory, so staging it in x3 (as
                // the plain arm below would) leaves snprintf reading whatever
                // the stack happened to hold — the four-argument
                // `snprintf(buf, 24, "%lld", n)` printed a pointer, while the
                // three-argument `snprintf(buf, 24, "AB")` was already correct.
                if (std.mem.eql(u8, ins.field, "vararg")) {
                    const idx: u5 = @intCast(ins.result orelse return refuse(@src()));
                    if (idx >= self.pending_varargs.len) return refuse(@src());
                    const vreg = try self.evalDnirValue(temps, ins.lhs);
                    const owned = switch (ins.lhs) {
                        .local, .temp => true,
                        else => false,
                    };
                    self.used_regs[vreg] = true;
                    self.pending_varargs[idx] = .{
                        .reg = vreg,
                        .scratch = !owned and !Arm64Compiler.regIsPinned(pinned, vreg),
                    };
                    if (idx + 1 > self.pending_vararg_count) self.pending_vararg_count = idx + 1;
                    return;
                }
                const slot: u5 = @intCast(ins.result orelse return refuse(@src()));
                const reg = try self.evalDnirValue(temps, ins.lhs);
                if (reg != slot) try self.emitMovReg(slot, reg);
                // Same rule as the single-argument path: a register still owned
                // by the slot map must survive being passed. Releasing a table
                // base here handed it to the next argument's index constant.
                if (reg != slot) self.releaseDnirTemp(pinned, ins.lhs, reg);
            },
            .load_local => {
                if (ins.ty == .f64) {
                    const slot: u32 = switch (ins.lhs) {
                        .local => |s| s,
                        else => return refuse(@src()),
                    };
                    const d = pinned.get(slot) orelse temps.get(slot) orelse return undefinedAt(@src(), "local", slot);
                    if (ins.result) |t| try temps.put(self.alloc, t, d);
                } else {
                    const reg = try self.evalDnirValue(temps, ins.lhs);
                    if (ins.result) |t| try temps.put(self.alloc, t, reg);
                }
            },
            .store_local => {
                if (ins.ty == .f64) {
                    const d = try self.evalDnirValueFp(temps, ins.lhs);
                    if (ins.result) |slot| {
                        // Same rule the integer path below documents: a local
                        // keeps ONE register for its whole lifetime. This arm
                        // REBOUND the slot to whatever register the value
                        // happened to be in, so a consumer emitted against the
                        // local's original home read a register the store never
                        // wrote — `r = math.sqrt(x)` put the result in d1 and
                        // the comparison read d9.
                        const home = pinned.get(slot) orelse temps.get(slot) orelse d;
                        if (home != d) {
                            try self.emitFmovReg(home, d);
                            self.releaseFpReg(d);
                        }
                        try pinned.put(self.alloc, slot, home);
                        try temps.put(self.alloc, slot, home);
                    } else {
                        self.releaseFpReg(d);
                    }
                } else {
                    const val_reg = try self.evalDnirValue(temps, ins.lhs);
                    if (ins.result) |slot| {
                        // A local must keep ONE register for its whole lifetime.
                        // Allocating a fresh register per store is invisible in
                        // straight-line code but breaks loops: the loop head was
                        // already emitted reading the previous register, so the
                        // update never reaches the condition and the loop spins.
                        // Reuse the existing home register when the local has one.
                        const local_reg = pinned.get(slot) orelse temps.get(slot) orelse try self.allocReg();
                        if (local_reg != val_reg) try self.emitMovReg(local_reg, val_reg);
                        if (val_reg != local_reg and !Arm64Compiler.regIsPinned(pinned, val_reg)) self.releaseReg(val_reg);
                        try pinned.put(self.alloc, slot, local_reg);
                        try temps.put(self.alloc, slot, local_reg);
                    } else if (!Arm64Compiler.regIsPinned(pinned, val_reg)) {
                        self.releaseReg(val_reg);
                    }
                }
            },
            .binop => blk: {
                if (ins.ty == .f64) {
                    const ast_op = dnirBinOpToAst(ins.binop);
                    // f64 ARITHMETIC outside a float-returning function. The
                    // arm below emits exactly this and is gated on
                    // `cur_func_float`, a per-FUNCTION property — so
                    // `mandel(cx: f64, cy: f64): i64`, a float kernel that
                    // answers with a count, had nowhere to go and was refused.
                    //
                    // `temps` is disambiguated by the CONSUMING instruction's
                    // `ty`, not by the function's: a consumer typed f64 reads
                    // through evalDnirValueFp, an integer consumer through
                    // evalDnirValue. So an FP result is correct here regardless
                    // of what the function returns.
                    if (!isComparison(ast_op)) {
                        const alhs = try self.evalDnirValueFp(temps, ins.lhs);
                        const arhs = try self.evalDnirValueFp(temps, ins.rhs);
                        const adst = try self.allocFpReg();
                        switch (ins.binop) {
                            .add => try self.emitFaddReg(adst, alhs, arhs),
                            .sub => try self.emitFsubReg(adst, alhs, arhs),
                            .mul => try self.emitFmulReg(adst, alhs, arhs),
                            .div => try self.emitFdivReg(adst, alhs, arhs),
                            else => return refuseWith(@src(), @tagName(ins.binop)),
                        }
                        if (alhs != adst) self.releaseFpReg(alhs);
                        if (arhs != adst) self.releaseFpReg(arhs);
                        if (ins.result) |t| try temps.put(self.alloc, t, adst);
                        break :blk;
                    }
                    const lhs = try self.evalDnirValueFp(temps, ins.lhs);
                    const rhs = try self.evalDnirValueFp(temps, ins.rhs);
                    const dst = try self.allocReg();
                    try self.emitFcmpReg(lhs, rhs);
                    try self.emitCsetFp(dst, conditionForComparison(ast_op));
                    if (ins.result) |t| try temps.put(self.alloc, t, dst);
                } else if (self.cur_func_float) {
                    // A COMPARISON here answers with a boolean, not a double,
                    // so it belongs in a GP register via fcmp+cset — exactly
                    // what the `ins.ty == .f64` branch above already does. That
                    // branch is only selected when the instruction is TYPED
                    // f64, and an integer-valued comparison over float operands
                    // is not, so `zx*zx + zy*zy < 4.0` inside a float kernel
                    // reached this arm, which emits only arithmetic, and was
                    // refused with `lt`.
                    //
                    // Putting a GP index into `temps` inside a float function
                    // looks like a register-space confusion and is not: the
                    // branch above does the same thing for the same reason, and
                    // a comparison's consumer reads an integer.
                    const cmp_op = dnirBinOpToAst(ins.binop);
                    if (isComparison(cmp_op)) {
                        const clhs = try self.evalDnirValueFp(temps, ins.lhs);
                        const crhs = try self.evalDnirValueFp(temps, ins.rhs);
                        const cdst = try self.allocReg();
                        try self.emitFcmpReg(clhs, crhs);
                        try self.emitCsetFp(cdst, conditionForComparison(cmp_op));
                        self.releaseFpReg(clhs);
                        self.releaseFpReg(crhs);
                        if (ins.result) |t| try temps.put(self.alloc, t, cdst);
                        break :blk;
                    }
                    const lhs = try self.evalDnirValueFp(temps, ins.lhs);
                    const rhs = try self.evalDnirValueFp(temps, ins.rhs);
                    const dst = try self.allocFpReg();
                    switch (ins.binop) {
                        .add => try self.emitFaddReg(dst, lhs, rhs),
                        .sub => try self.emitFsubReg(dst, lhs, rhs),
                        .mul => try self.emitFmulReg(dst, lhs, rhs),
                        .div => try self.emitFdivReg(dst, lhs, rhs),
                        else => return refuseWith(@src(), @tagName(ins.binop)),
                    }
                    if (lhs != dst) self.releaseFpReg(lhs);
                    if (rhs != dst) self.releaseFpReg(rhs);
                    if (ins.result) |t| try temps.put(self.alloc, t, dst);
                } else {
                    const lhs = try self.evalDnirValue(temps, ins.lhs);
                    const rhs = try self.evalDnirValue(temps, ins.rhs);
                    const dst = try self.allocReg();
                    const op: ast.BinOp = dnirBinOpToAst(ins.binop);
                    try self.emitCompareOrBinop(dst, lhs, rhs, op);
                    if (!Arm64Compiler.regIsPinned(pinned, lhs)) self.releaseReg(lhs);
                    if (!Arm64Compiler.regIsPinned(pinned, rhs)) self.releaseReg(rhs);
                    if (ins.result) |t| try temps.put(self.alloc, t, dst);
                }
            },
            .call_extern, .call_direct => {
                if (ins.ty == .f64) {
                    // Move the ARGUMENT into d0. Every other call arm moves its
                    // first operand into the parameter register; this one called
                    // straight through, so a libm call ran on whatever was in d0.
                    if (ins.lhs != .void) {
                        const arg_d = try self.evalDnirValueFp(temps, ins.lhs);
                        if (arg_d != 0) try self.emitFmovReg(0, arg_d);
                        self.releaseFpReg(arg_d);
                    }
                    if (ins.op == .call_extern) try self.ensureExternalSymbol(ins.callee);
                    const save = try self.emitSaveCallerRegs();
                    const vbytes = try self.emitPushVarargs();
                    try self.emitBl(ins.callee);
                    try self.emitPopVarargs(vbytes);
                    try self.emitRestoreCallerRegs(save);
                    self.used_fp_regs[0] = true;
                    // The result stays in d0: that IS the ARM64 return register,
                    // and a copy-out here breaks the f64 return ABI (caught by
                    // "native backend lowers Pass 4 milestone with f64 return in
                    // d0"). A consumer that needs it to survive a later call is
                    // served by store_local giving the LOCAL a stable home.
                    if (ins.result) |t| try temps.put(self.alloc, t, 0);
                } else if (self.cur_func_float) {
                    if (ins.lhs != .void) {
                        const arg_d = try self.evalDnirValueFp(temps, ins.lhs);
                        if (arg_d != 0) try self.emitFmovReg(0, arg_d);
                        self.releaseFpReg(arg_d);
                    }
                    if (ins.op == .call_extern) try self.ensureExternalSymbol(ins.callee);
                    const save = try self.emitSaveCallerRegs();
                    const vbytes = try self.emitPushVarargs();
                    try self.emitBl(ins.callee);
                    try self.emitPopVarargs(vbytes);
                    try self.emitRestoreCallerRegs(save);
                    self.used_fp_regs[0] = true;
                    if (ins.result) |t| try temps.put(self.alloc, t, 0);
                } else {
                    if (ins.lhs != .void) {
                        const arg_reg = try self.evalDnirValue(temps, ins.lhs);
                        if (arg_reg != 0) try self.emitMovReg(0, arg_reg);
                        // Passing a local as an argument must not free the local:
                        // `t = g(a)` released a's home register, so the following
                        // emitSaveCallerRegs skipped it AND allocReg handed the
                        // same register to the call's result, clobbering `a`.
                        // `regIsPinned` covers parameter slots only; a temp still
                        // live in the slot map has the same problem, which is how
                        // a table base pointer got overwritten by the very call it
                        // was being passed to.
                        self.releaseDnirTemp(pinned, ins.lhs, arg_reg);
                    }
                    if (ins.op == .call_extern) try self.ensureExternalSymbol(ins.callee);
                    // The indirect-result pointer has to be materialized BEFORE
                    // `emitSaveCallerRegs`, which moves `sp` down by its own
                    // save area. `add x8, sp, #off` computed inside that window
                    // would name a slot in the save area instead of the buffer.
                    const indirect = try self.indirectResultBuffer(ins);
                    if (indirect) |off| try self.emitAddSpImm(8, off);
                    const save = try self.emitSaveCallerRegs();
                    const vbytes = try self.emitPushVarargs();
                    try self.emitBl(ins.callee);
                    try self.emitPopVarargs(vbytes);
                    try self.emitRestoreCallerRegs(save);
                    // An indirect return has already landed: the callee wrote
                    // the caller's buffer through x8, so there is nothing in
                    // x0..x7 to copy out.
                    if (ins.record.len > 0 and indirect == null) {
                        if (f64RecordDesc(self.f64_records, .{ .named = ins.record })) |frec| {
                            const base = if (ins.field.len > 0) ins.field else "rec";
                            try self.assignF64RecordFromFpAbiRegs(base, frec);
                        } else if (scalRecordDesc(self.scal_records, .{ .named = ins.record })) |rec| {
                            const base = if (ins.field.len > 0) ins.field else "rec";
                            try self.assignRecordFromAbiRegs(base, rec);
                        } else return refuse(@src());
                    }
                    const dst = try self.allocReg();
                    try self.emitMovReg(dst, 0);
                    if (ins.result) |t| try temps.put(self.alloc, t, dst);
                }
            },
            .init_record => {
                if (ins.record.len > 0) {
                    if (f64RecordDesc(self.f64_records, .{ .named = ins.record })) |frec| {
                        const base = if (ins.field.len > 0) ins.field else "rec";
                        try self.assignF64RecordFromFpAbiRegs(base, frec);
                    } else if (scalRecordDesc(self.scal_records, .{ .named = ins.record })) |rec| {
                        // A wide record never arrived in x0..x7. It is either
                        // the buffer a callee just filled through x8, or a
                        // literal whose fields already live in their own
                        // locals; copying eight argument registers over it
                        // would overwrite real data with call debris.
                        if (rec.field_names.len <= dnir_lower.max_reg_record_fields) {
                            const base = if (ins.field.len > 0) ins.field else "rec";
                            try self.assignRecordFromAbiRegs(base, rec);
                        }
                    } else return refuse(@src());
                }
            },
            .ret => {
                if (self.cur_func_float or ins.ty == .f64) {
                    const d = try self.evalDnirValueFp(temps, ins.lhs);
                    if (d != 0) try self.emitFmovReg(0, d);
                    if (self.needsProcessExitF64Coerce()) try self.emitFcvtzsX0FromD0();
                    self.releaseFpReg(d);
                } else {
                    const reg = try self.evalDnirValue(temps, ins.lhs);
                    if (reg != 0) try self.emitMovReg(0, reg);
                    // Register allocation is linear over the instruction stream
                    // and does not model control flow, so freeing a pinned local
                    // here leaks across the branch: after an early `return n`
                    // the parameter's register looks free and the fall-through
                    // path reuses it for a constant (`n - 1` became `1 - 1`).
                    // A local's register stays reserved for the whole function.
                    if (!Arm64Compiler.regIsPinned(pinned, reg)) self.releaseReg(reg);
                }
                try self.restoreStackFrame();
                try self.emitRet();
                self.returned = true;
            },
            .ret_record => {
                if (self.cur_func_ret_f64_record != null or
                    (ins.record.len > 0 and f64RecordDesc(self.f64_records, .{ .named = ins.record }) != null))
                {
                    try self.emitRetF64RecordFromDnir(temps, ins);
                } else if (self.cur_ret_indirect_reg) |buf| {
                    // AAPCS64 indirect result: the caller reserved the buffer
                    // and handed us its address in x8 (parked in `buf` on
                    // entry). Write every field through it. There is no
                    // parallel-move hazard here — a store cannot clobber a
                    // source register — but a field left UNWRITTEN is worse
                    // than a wrong register, because the caller reads the slot
                    // regardless and sees whatever the frame held. The lowerer
                    // guarantees one value per declared field; assert the count
                    // rather than trust it.
                    const vals = try self.dnirRetRecordVals(ins);
                    const rec = self.cur_func_ret_record orelse return refuse(@src());
                    if (vals.len != rec.field_names.len) return refuse(@src());
                    for (vals, 0..) |v, i| {
                        const src = try self.evalDnirValue(temps, v);
                        const off: u16 = @intCast(i * 8);
                        try self.emitStrBaseImm(src, buf, off);
                        if (!Arm64Compiler.regIsPinned(pinned, src)) self.releaseReg(src);
                    }
                } else {
                    // Returning a record is a PARALLEL move into x0..x7, not a
                    // sequential one. Writing x0 first and then reading a later
                    // field that still lives in x0 — a parameter, typically —
                    // substitutes the value just stored: `{ kind = 1, start = pos }`
                    // with `pos` in x0 returned `kind` for `start`.
                    //
                    // Evaluate every field, stage each through a scratch register
                    // (allocReg hands out x9+, so it can never alias an ABI
                    // destination), then commit. Redundant `mov`s here are folded
                    // by the peephole; a wrong answer is not recoverable.
                    //
                    // This used to read `lhs`/`rhs`/`third` and stop, so a
                    // 4th..8th field was simply never returned while the caller
                    // still copied x0..x7 out — `{ a=1 … e=5 }` handed back
                    // whatever x4 held. Walk every field.
                    const vals = try self.dnirRetRecordVals(ins);
                    const n = vals.len;
                    if (n == 0 or n > dnir_lower.max_reg_record_fields) return refuse(@src());
                    var srcs: [dnir_lower.max_reg_record_fields]u5 = @splat(0);
                    var staged: [dnir_lower.max_reg_record_fields]u5 = @splat(0);
                    for (vals, 0..) |v, i| srcs[i] = try self.evalDnirValue(temps, v);

                    var i: usize = 0;
                    while (i < n) : (i += 1) {
                        staged[i] = try self.allocReg();
                        try self.emitMovReg(staged[i], srcs[i]);
                    }
                    i = 0;
                    while (i < n) : (i += 1) {
                        try self.emitMovReg(@intCast(i), staged[i]);
                        self.releaseReg(staged[i]);
                    }
                    i = 0;
                    while (i < n) : (i += 1) {
                        if (!Arm64Compiler.regIsPinned(pinned, srcs[i])) self.releaseReg(srcs[i]);
                    }
                }
                try self.restoreStackFrame();
                try self.emitRet();
                self.returned = true;
            },
            .br_if_not => {
                const cond = try self.evalDnirValue(temps, ins.lhs);
                // `evalDnirValue` materializes the condition into a GPR (via
                // `cset`, which does not write NZCV). Without this compare the
                // branch below would consume whatever flags the condition's own
                // `cmp` left, turning every `if <comparison>` into
                // `if (lhs == rhs)`. Test the boolean itself: `b.eq` then means
                // "condition was false", which is br_if_not.
                try self.emitCmpZero(cond);
                const patch_off = try self.emitBCond(.eq, 0);
                self.releaseReg(cond);
                try branch_patches.append(self.alloc, .{ .patch_off = patch_off, .target_instr = ins.branch_target, .is_cond = true });
            },
            .br => {
                const patch_off = try self.emitB(0);
                try branch_patches.append(self.alloc, .{ .patch_off = patch_off, .target_instr = ins.branch_target, .is_cond = false });
            },
            .load_field => {
                const base = if (ins.req_alias.len > 0) ins.req_alias else "rec";
                const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ base, ins.field });
                defer self.alloc.free(key);
                if (self.cur_func_float) {
                    const d = self.fp_locals.get(key) orelse return undefinedKey(@src(), "fp local", key);
                    if (ins.result) |t| try temps.put(self.alloc, t, d);
                } else {
                    const reg = try self.loadStackField(key);
                    if (ins.result) |t| try temps.put(self.alloc, t, reg);
                }
            },
            .str_len => {
                // Inline byte-length scan — the sovereign form of `string.len`.
                // No libc `strlen`, no runtime helper: just a load/compare loop,
                // so a tokenizer using it stays in the direct backend subset.
                //
                //     len = 0
                //   loop: b = ldrb [base + len]
                //         if b == 0 goto done
                //         len += 1
                //         goto loop
                //   done:
                const base = try self.evalDnirValue(temps, ins.lhs);
                const len = try self.allocReg();
                try self.emitMovImm(len, 0);
                const one = try self.allocReg();
                try self.emitMovImm(one, 1);
                const addr = try self.allocReg();
                const byte = try self.allocReg();

                const loop_off: u32 = @intCast(self.code.items.len);
                try self.emitAddReg(addr, base, len);
                try self.emitLdrb(byte, addr);
                try self.emitCmpZero(byte);
                const done_patch = try self.emitBCond(.eq, 0);
                try self.emitAddReg(len, len, one);
                const back_patch = try self.emitB(0);
                const done_off: u32 = @intCast(self.code.items.len);

                try self.patchCondBranch(done_patch, done_off);
                try self.patchB(back_patch, loop_off);

                self.releaseReg(byte);
                self.releaseReg(addr);
                self.releaseReg(one);
                if (!Arm64Compiler.regIsPinned(pinned, base)) self.releaseReg(base);
                if (ins.result) |t| try temps.put(self.alloc, t, len);
            },
            .print_value => {
                // Native observable output — the construct that used to force
                // the C-emit bootstrap fallback. `print` lowers to libc
                // puts/printf (Mach-O `_puts`/`_printf` externs), so a program
                // whose only dynamic surface is output stays sovereign machine
                // code. `.ty` selects the call shape:
                //   .str  → puts(v)                 (puts appends \n, Lua print shape)
                //   .i64  → printf("%lld\n", v)
                //   .f64  → printf("%f\n", v)
                //   else  → printf("\n")            (zero-arg print → blank line;
                //           puts would append its own \n and print two lines)
                // ABI (Apple arm64 variadic convention): printf's variadic
                // arguments are passed ON THE STACK at the caller's sp, not in
                // x1/d0 (verified against xcrun clang -S output and raw asm:
                // passing in x1 prints garbage, storing at [sp,#0] prints
                // correctly). So the arg is parked in x2 (volatile — survives
                // the save) and stored at [sp,#0] after reserving the vararg
                // slot. w8 is NOT needed (Apple's printf ignores the AAPCS
                // FP-count register for the stack convention).
                var fmt_sym: u32 = 0;
                switch (ins.ty) {
                    .str => {
                        const reg = try self.evalDnirValue(temps, ins.lhs);
                        if (reg != 0) try self.emitMovReg(0, reg);
                        self.releaseDnirTemp(pinned, ins.lhs, reg);
                        fmt_sym = 0;
                    },
                    .i64 => {
                        const reg = try self.evalDnirValue(temps, ins.lhs);
                        if (reg != 2) try self.emitMovReg(2, reg);
                        self.releaseDnirTemp(pinned, ins.lhs, reg);
                        fmt_sym = try self.internString("%lld\n");
                    },
                    .f64 => switch (ins.lhs) {
                        // Literal: materialize the bit pattern directly into
                        // x2 (same trick compileExprFp uses) — no FP reg.
                        .f64 => |n| try self.emitMovImm(2, @bitCast(n)),
                        else => {
                            const d = try self.evalDnirValueFp(temps, ins.lhs);
                            try self.emitFmovToGpr(2, d);
                        },
                    },
                    else => fmt_sym = try self.internString("\n"),
                }
                if (ins.ty == .f64) fmt_sym = try self.internString("%f\n");
                if (fmt_sym != 0) try self.emitAdrpAdd(0, fmt_sym);
                const save = try self.emitSaveCallerRegs();
                if (ins.ty == .i64 or ins.ty == .f64) {
                    // Reserve a 16-byte slot so sp stays 16-byte aligned at the
                    // call; the vararg goes at [sp,#0], [sp,#8] is padding.
                    try self.emitSubSp(16);
                    try self.emitStrSp(2, 0);
                }
                try self.ensureExternalSymbol(if (ins.ty == .str) "puts" else "printf");
                try self.emitBl(if (ins.ty == .str) "puts" else "printf");
                if (ins.ty == .i64 or ins.ty == .f64) try self.emitAddSp(16);
                try self.emitRestoreCallerRegs(save);
            },
            .alloc_slots => {
                const t = ins.result orelse return refuse(@src());
                const off = self.slot_bases.get(t) orelse return refuse(@src());
                const dst = try self.allocReg();
                try self.emitAddSpImm(dst, off);
                try temps.put(self.alloc, t, dst);
            },
            .load_index, .store_index => |op| if (ins.ty == .i64) {
                // Memory-backed positional table: 8-byte elements, Duo-indexed
                // from 1, so element `i` is at `base + (i - 1) * 8`. The scaled
                // register form `[base, idx, lsl #3]` does the multiply for
                // free, so only the 1-based bias costs an instruction.
                const base = try self.evalDnirValue(temps, ins.lhs);
                const idx = try self.evalDnirValue(temps, ins.rhs);
                const biased = try self.allocReg();
                const one = try self.allocReg();
                try self.emitMovImm(one, 1);
                try self.emitSubReg(biased, idx, one);
                self.releaseReg(one);
                if (op == .load_index) {
                    const dst = try self.allocReg();
                    try self.emitLdrScaled(dst, base, biased);
                    if (ins.result) |t| try temps.put(self.alloc, t, dst);
                } else {
                    const val = try self.evalDnirValue(temps, ins.third);
                    try self.emitStrScaled(val, base, biased);
                    self.releaseDnirTemp(pinned, ins.third, val);
                }
                self.releaseReg(biased);
                // Only release registers this instruction owns. A base or index
                // that came from a slot is still live in `temps`: materializing a
                // table emits one store per element off the *same* base, and
                // releasing it after the first store handed x9 straight back to
                // the next index constant, so element 2 stored through `[2]` as
                // an address.
                self.releaseDnirTemp(pinned, ins.lhs, base);
                self.releaseDnirTemp(pinned, ins.rhs, idx);
            } else if (op == .store_index) {
                // Byte-width store: the mirror of the byte load below, sharing
                // ONE index origin (`base + (i - 1)`) so a raw buffer
                // normalizes at the lowering instead of giving the backend a
                // second convention.
                //
                // releaseDnirTemp, NOT releaseReg — the same discipline the
                // scaled path above documents. A base that came from a slot is
                // still live in `temps`, and string.char emits two stores off
                // the SAME base: releasing it after the first handed the
                // register straight to the second store's index constant, and
                // the write went through an address instead of a pointer.
                // That was the segfault.
                const sbase = try self.evalDnirValue(temps, ins.lhs);
                const sidx = try self.evalDnirValue(temps, ins.rhs);
                const sval = try self.evalDnirValue(temps, ins.third);
                const sone = try self.allocReg();
                try self.emitMovImm(sone, 1);
                const saddr = try self.allocReg();
                try self.emitSubReg(saddr, sidx, sone);
                try self.emitAddReg(saddr, sbase, saddr);
                self.releaseReg(sone);
                try self.emitStrb(sval, saddr);
                self.releaseReg(saddr);
                self.releaseDnirTemp(pinned, ins.lhs, sbase);
                self.releaseDnirTemp(pinned, ins.rhs, sidx);
                self.releaseDnirTemp(pinned, ins.third, sval);
            } else {
                // `string.byte(s, i)`: Duo indexes strings from 1, C pointers
                // from 0, so the byte lives at `base + (i - 1)`.
                const base = try self.evalDnirValue(temps, ins.lhs);
                const idx = try self.evalDnirValue(temps, ins.rhs);
                const one = try self.allocReg();
                try self.emitMovImm(one, 1);
                const addr = try self.allocReg();
                try self.emitSubReg(addr, idx, one);
                try self.emitAddReg(addr, base, addr);
                self.releaseReg(one);
                const dst = try self.allocReg();
                try self.emitLdrb(dst, addr);
                self.releaseReg(addr);
                if (!Arm64Compiler.regIsPinned(pinned, base)) self.releaseReg(base);
                if (!Arm64Compiler.regIsPinned(pinned, idx)) self.releaseReg(idx);
                if (ins.result) |t| try temps.put(self.alloc, t, dst);
            },
            .hw_fence => {
                if (dnir_hardware.arm64FixedWord(.fence)) |word| {
                    try self.emit(word, "dmb ish");
                } else return refuse(@src());
            },
            .hw_spin => {
                if (dnir_hardware.arm64FixedWord(.spin_wait)) |word| {
                    try self.emit(word, "yield");
                } else return refuse(@src());
            },
            .hw_unary => {
                const src = try self.evalDnirValue(temps, ins.lhs);
                const dst = try self.allocReg();
                try self.emitHwUnary(dst, src, ins.hw);
                if (!Arm64Compiler.regIsPinned(pinned, src)) self.releaseReg(src);
                if (ins.result) |t| try temps.put(self.alloc, t, dst);
            },
            else => return refuse(@src()),
        }
    }

    fn emitHwUnary(self: *Arm64Compiler, dst: u5, src: u5, hw: dnir.HwIntrinsic) Error!void {
        try self.ensureRegLive(src);
        if (hw == .popcount) {
            try self.emitPopcountReg(dst, src);
            return;
        }
        if (hw == .ctz) {
            const tmp = try self.allocReg();
            try self.emitFmt(0x5ac00000 | (@as(u32, src) << 5) | @as(u32, tmp), "rbit x{d}, x{d}", .{ tmp, src });
            try self.emitFmt(0xdac01000 | (@as(u32, tmp) << 5) | @as(u32, dst), "clz x{d}, x{d}", .{ dst, tmp });
            self.releaseReg(tmp);
            return;
        }
        const word = dnir_hardware.arm64UnaryWord(hw, dst, src) orelse return refuse(@src());
        const mnem = switch (hw) {
            .clz => "clz",
            else => return refuse(@src()),
        };
        try self.emitFmt(word, "{s} x{d}, x{d}", .{ mnem, dst, src });
    }

    /// Brian-Kernighan popcount — sovereign GPR loop (no `__builtin_popcountll`).
    fn emitPopcountReg(self: *Arm64Compiler, dst: u5, src: u5) Error!void {
        const val = if (dst != src) src else blk: {
            const copy = try self.allocReg();
            try self.emitMovReg(copy, src);
            break :blk copy;
        };
        try self.emitMovImm(dst, 0);
        const loop_off: u32 = @intCast(self.code.items.len);
        try self.emitCmpZero(val);
        const done = try self.emitBCond(.eq, 0);
        const one = try self.allocReg();
        try self.emitMovImm(one, 1);
        const tmp = try self.allocReg();
        try self.emitSubReg(tmp, val, one);
        try self.emitAndReg(val, val, tmp);
        try self.emitAddReg(dst, dst, one);
        self.releaseReg(one);
        self.releaseReg(tmp);
        const back = try self.emitB(0);
        try self.patchB(back, loop_off);
        try self.patchCondBranch(done, @intCast(self.code.items.len));
    }

    fn evalDnirValue(self: *Arm64Compiler, temps: *std.AutoHashMapUnmanaged(u32, u5), v: dnir.Value) Error!u5 {
        return switch (v) {
            .void => try self.allocReg(),
            .i64 => |n| blk: {
                const r = try self.allocReg();
                try self.emitMovImm(r, n);
                break :blk r;
            },
            .f64 => |n| blk: {
                const r = try self.allocReg();
                try self.emitMovImm(r, @bitCast(n));
                break :blk r;
            },
            .str => |s| blk: {
                const r = try self.allocReg();
                const sym = try self.internString(s);
                try self.emitAdrpAdd(r, sym);
                break :blk r;
            },
            .local => |slot| {
                if (temps.get(slot)) |r| {
                    try self.ensureRegLive(r);
                    return r;
                }
                return undefinedAt(@src(), "local", slot);
            },
            .temp => |t| temps.get(t) orelse return undefinedAt(@src(), "temp", t),
            .record => return refuse(@src()),
        };
    }

    fn evalDnirValueFp(self: *Arm64Compiler, temps: *std.AutoHashMapUnmanaged(u32, u5), v: dnir.Value) Error!u5 {
        return switch (v) {
            .void => try self.allocFpReg(),
            .f64 => |n| blk: {
                const d = try self.allocFpReg();
                try self.emitFmovImmFp(d, n);
                break :blk d;
            },
            .local => |slot| temps.get(slot) orelse undefinedAt(@src(), "local", slot),
            .temp => |t| temps.get(t) orelse undefinedAt(@src(), "temp", t),
            // An integer immediate in a float position. `(col - WIDTH / 2) *
            // 3.5 / WIDTH` folds `WIDTH / 2` to an i64 constant and then wants
            // it as a double; there is no fmov for an arbitrary integer, so it
            // materializes into a GP register and converts. scvtf already
            // existed for exactly this and nothing reached it from here.
            .i64 => |n| blk: {
                const x = try self.allocReg();
                try self.emitMovImm(x, n);
                const d = try self.allocFpReg();
                try self.emitScvtfFromGpr(d, x);
                self.releaseReg(x);
                break :blk d;
            },
            else => refuse(@src()),
        };
    }

    fn evalDnirFpArg(self: *Arm64Compiler, temps: *std.AutoHashMapUnmanaged(u32, u5), v: dnir.Value) Error!u5 {
        return switch (v) {
            .f64 => |n| blk: {
                const d = try self.allocFpReg();
                try self.emitFmovImmFp(d, n);
                break :blk d;
            },
            .temp => |t| temps.get(t) orelse undefinedAt(@src(), "temp", t),
            else => refuse(@src()),
        };
    }

    fn releaseFpReg(self: *Arm64Compiler, reg: u5) void {
        _ = self;
        _ = reg;
    }

    fn emitCompareOrBinop(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5, op: ast.BinOp) Error!void {
        if (isComparison(op)) {
            try self.emitCompareResult(dst, lhs, rhs, conditionForComparison(op));
            return;
        }
        switch (op) {
            .add => try self.emitAddReg(dst, lhs, rhs),
            .sub => try self.emitSubReg(dst, lhs, rhs),
            .mul => try self.emitMulReg(dst, lhs, rhs),
            .div, .idiv => try self.emitSdivReg(dst, lhs, rhs),
            .mod => {
                const q = try self.allocReg();
                try self.emitSdivReg(q, lhs, rhs);
                try self.emitMsubReg(dst, q, rhs, lhs);
                self.releaseReg(q);
            },
            // Bitwise and shift, register forms. AArch64 encodes all five with
            // the same field layout as add/sub, so they share one emitter.
            .band => try self.emitBitReg(0x8a000000, "and", dst, lhs, rhs),
            .bor => try self.emitBitReg(0xaa000000, "orr", dst, lhs, rhs),
            .bxor => try self.emitBitReg(0xca000000, "eor", dst, lhs, rhs),
            .lshift => try self.emitBitReg(0x9ac02000, "lsl", dst, lhs, rhs),
            .rshift => try self.emitBitReg(0x9ac02400, "lsr", dst, lhs, rhs),
            else => return refuse(@src()),
        }
    }

    fn assignRecordFromStackLocals(self: *Arm64Compiler, base: []const u8, desc: ScalRecordDesc) Error!void {
        const n = desc.field_names.len;
        const raw_frame: u16 = @intCast(n * 8);
        const frame: u16 = @intCast(std.mem.alignForward(u16, raw_frame, 16));
        try self.emitSubSp(frame);
        self.stack_frame_bytes += frame;
        for (desc.field_names, 0..) |fname, i| {
            const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ base, fname });
            defer self.alloc.free(key);
            // field values stored under loc.field keys from lowering
            const off: u16 = @intCast(i * 8);
            if (self.fp_stack_slots.get(key)) |_| {
                try self.fp_stack_slots.put(self.alloc, key, .{ .off = off, .float = false });
            } else {
                // search all locals ending with .field
                var it = self.locals.iterator();
                while (it.next()) |e| {
                    if (std.mem.endsWith(u8, e.key_ptr.*, fname)) {
                        const reg = e.value_ptr.*;
                        try self.emitStrSp(reg, off);
                        const fk = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ base, fname });
                        try self.fp_stack_slots.put(self.alloc, fk, .{ .off = off, .float = false });
                        break;
                    }
                }
            }
        }
    }

    fn compileFunction(self: *Arm64Compiler, func: NativeFunction) Error!void {
        const fd = func.decl;
        self.locals.clearRetainingCapacity();
        self.used_regs = @splat(false);
        self.returned = false;
        self.fp_locals.clearRetainingCapacity();
        self.used_fp_regs = @splat(false);
        self.fp_stack_slots.clearRetainingCapacity();
        self.stack_frame_bytes = 0;
        self.spill_offsets.clearRetainingCapacity();
        self.spill_reg_count = 0;
        self.spilled_regs.clearRetainingCapacity();
        self.cur_func_float = false;
        self.cur_func_ret_float = false;

        const name = func.symbol_name;
        self.cur_func_name = name;
        if (std.mem.eql(u8, name, "__native_load_u8")) {
            try self.compileIntrinsicLoadU8(func);
            return;
        }
        const offset: u32 = @intCast(self.code.items.len);
        for (self.symbols.items) |sym| {
            if (std.mem.eql(u8, sym.name, name)) return error.DuplicateSymbol;
        }
        const owned_name = try self.alloc.dupe(u8, name);
        errdefer self.alloc.free(owned_name);
        try self.symbols.append(self.alloc, .{ .name = owned_name, .offset = offset, .defined = true });

        try self.asm_text.appendSlice(self.alloc, "\n.globl _");
        try self.asm_text.appendSlice(self.alloc, name);
        try self.asm_text.appendSlice(self.alloc, "\n.p2align 2\n_");
        try self.asm_text.appendSlice(self.alloc, name);
        try self.asm_text.appendSlice(self.alloc, ":\n");

        self.cur_func_ret_record = scalRecordDesc(self.scal_records, fd.func.ret_type);
        self.cur_func_float = isPureFloatFunction(self.f64_records, fd);
        self.cur_func_ret_float = returnsFloat(fd.func.ret_type) and !self.cur_func_float;
        if (self.cur_func_float) {
            var dreg: u5 = 0;
            for (fd.func.params) |param| {
                if (isFloatAnnotation(param.typ)) {
                    self.used_fp_regs[dreg] = true;
                    try self.fp_locals.put(self.alloc, param.name, dreg);
                    dreg += 1;
                } else if (f64RecordDesc(self.f64_records, param.typ)) |rec| {
                    for (rec.field_names) |fname| {
                        self.used_fp_regs[dreg] = true;
                        const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ param.name, fname });
                        try self.fp_locals.put(self.alloc, key, dreg);
                        dreg += 1;
                    }
                } else {
                    return refuse(@src());
                }
            }
        } else {
            for (fd.func.params, 0..) |param, i| {
                const local_reg = try self.allocReg();
                const abi_reg: u5 = @intCast(i);
                try self.emitMovReg(local_reg, abi_reg);
                try self.locals.put(self.alloc, param.name, local_reg);
            }
        }

        try self.compileBlock(fd.func.body, fd.func.ret_type);
        if (!self.returned) return refuse(@src());
    }

    fn emit(self: *Arm64Compiler, word: u32, asm_line: []const u8) Error!void {
        try appendU32(&self.code, self.alloc, word);
        try self.asm_text.appendSlice(self.alloc, "\t");
        try self.asm_text.appendSlice(self.alloc, asm_line);
        try self.asm_text.appendSlice(self.alloc, "\n");
    }

    fn emitFmt(self: *Arm64Compiler, word: u32, comptime fmt: []const u8, args: anytype) Error!void {
        const line = try std.fmt.allocPrint(self.alloc, fmt, args);
        defer self.alloc.free(line);
        try self.emit(word, line);
    }

    /// ARM64 `str xN, [sp, #imm]` scaled offset is limited (~32 KiB frame).
    const max_spill_frame_bytes: u16 = 32752;

    fn ensureRegLive(self: *Arm64Compiler, reg: u5) Error!void {
        if (self.spilled_regs.get(reg)) |off| {
            const reload_off = self.stack_frame_bytes - off - 8;
            try self.emitLdrSp(reg, reload_off);
            _ = self.spilled_regs.remove(reg);
        }
    }

    fn spillReg(self: *Arm64Compiler, victim: u5) Error!void {
        if (self.stack_frame_bytes + 16 > max_spill_frame_bytes) return error.RegisterExhausted;
        const off = self.stack_frame_bytes;
        self.stack_frame_bytes += 16;
        try self.emitSubSp(16);
        try self.ensureRegLive(victim);
        try self.emitStrSp(victim, 8);
        try self.spilled_regs.put(self.alloc, victim, off);
        if (self.spill_reg_count < std.math.maxInt(u5)) self.spill_reg_count += 1;
        self.used_regs[victim] = false;
    }

    /// x18 is Apple's PLATFORM REGISTER. AAPCS64 leaves it to the platform and
    /// Apple's arm64 ABI reserves it outright — "don't use this register" —
    /// so it is not part of the allocatable pool even though it sits in the
    /// middle of x9..x28. The pool could always reach it under pressure; a
    /// record return staging eight fields at once reaches it reliably.
    const platform_reserved_reg: u5 = 18;

    fn allocRegExcluding(self: *Arm64Compiler, exclude: ?u5) Error!u5 {
        var reg: u5 = 9;
        while (reg < 29) : (reg += 1) {
            if (reg == platform_reserved_reg) continue;
            if (exclude != null and reg == exclude.?) continue;
            if (!self.used_regs[reg]) {
                self.used_regs[reg] = true;
                return reg;
            }
        }
        var victim: u5 = 28;
        while (victim >= 9) : (victim -= 1) {
            if (exclude != null and victim == exclude.?) continue;
            if (!self.used_regs[victim]) continue;
            try self.spillReg(victim);
            return self.allocRegExcluding(exclude);
        }
        return error.RegisterExhausted;
    }

    fn allocReg(self: *Arm64Compiler) Error!u5 {
        return self.allocRegExcluding(null);
    }

    fn compileIntrinsicLoadU8(self: *Arm64Compiler, func: NativeFunction) Error!void {
        _ = func;
        const offset: u32 = @intCast(self.code.items.len);
        const name = "__native_load_u8";
        for (self.symbols.items) |sym| {
            if (std.mem.eql(u8, sym.name, name)) return error.DuplicateSymbol;
        }
        const owned_name = try self.alloc.dupe(u8, name);
        errdefer self.alloc.free(owned_name);
        try self.symbols.append(self.alloc, .{ .name = owned_name, .offset = offset, .defined = true });
        try self.asm_text.appendSlice(self.alloc, "\n.globl _");
        try self.asm_text.appendSlice(self.alloc, name);
        try self.asm_text.appendSlice(self.alloc, "\n.p2align 2\n_");
        try self.asm_text.appendSlice(self.alloc, name);
        try self.asm_text.appendSlice(self.alloc, ":\n");
        const addr = try self.allocReg();
        try self.emitAddReg(addr, 0, 1);
        try self.emitLdrb(0, addr);
        self.releaseReg(addr);
        try self.emitRet();
    }

    fn emitLoadU8Intrinsic(self: *Arm64Compiler, base: u5, off: u5) Error!u5 {
        const addr = try self.allocReg();
        try self.emitAddReg(addr, base, off);
        const dst = try self.allocReg();
        try self.emitLdrb(dst, addr);
        self.releaseReg(addr);
        return dst;
    }

    fn restoreStackFrame(self: *Arm64Compiler) Error!void {
        if (self.stack_frame_bytes > 0) {
            try self.emitAddSp(self.stack_frame_bytes);
        }
    }

    fn emitStrSpFp(self: *Arm64Compiler, dreg: u5, offset: u16) Error!void {
        try self.emitFmt(0xfd0003e0 | ((@as(u32, offset) / 8) << 10) | @as(u32, dreg), "str d{d}, [sp, #{d}]", .{ dreg, offset });
    }

    fn emitLdrSpFp(self: *Arm64Compiler, dreg: u5, offset: u16) Error!void {
        try self.emitFmt(0xfd4003e0 | ((@as(u32, offset) / 8) << 10) | @as(u32, dreg), "ldr d{d}, [sp, #{d}]", .{ dreg, offset });
    }

    fn emitScvtfFromGpr(self: *Arm64Compiler, dreg: u5, xreg: u5) Error!void {
        try self.emitFmt(0x1e620000 | (@as(u32, xreg) << 5) | @as(u32, dreg), "scvtf d{d}, x{d}", .{ dreg, xreg });
    }

    fn emitFmovToGpr(self: *Arm64Compiler, xreg: u5, dreg: u5) Error!void {
        try self.emitFmt(0x9e660000 | (@as(u32, dreg) << 5) | @as(u32, xreg), "fmov x{d}, d{d}", .{ xreg, dreg });
    }

    fn emitFcvtzsFromFp(self: *Arm64Compiler, xreg: u5, dreg: u5) Error!void {
        try self.emitFmt(0x9e780000 | (@as(u32, dreg) << 5) | @as(u32, xreg), "fcvtzs x{d}, d{d}", .{ xreg, dreg });
    }

    fn emitFmovImmFp(self: *Arm64Compiler, dreg: u5, value: f64) Error!void {
        const tmp = try self.allocReg();
        try self.emitMovImm(tmp, @bitCast(value));
        try self.emitFmovFromGpr(dreg, tmp);
        self.releaseReg(tmp);
    }

    fn emitFcmpReg(self: *Arm64Compiler, lhs: u5, rhs: u5) Error!void {
        try self.emitFmt(0x1e602000 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5), "fcmp d{d}, d{d}", .{ lhs, rhs });
    }

    fn emitCsetFp(self: *Arm64Compiler, dst: u5, cond: Condition) Error!void {
        try self.emitFmt(encodeCset(dst, cond), "cset x{d}, {s}", .{ dst, conditionName(cond) });
    }

    fn assignRecordTable(self: *Arm64Compiler, base: []const u8, expr: *const ast.Expr) Error!void {
        const table = switch (expr.*) {
            .table => |t| t,
            else => return refuse(@src()),
        };
        const n = table.fields.len;
        if (n == 0 or n > 8) return refuse(@src());
        const raw_frame: u16 = @intCast(n * 8);
        const frame: u16 = @intCast(std.mem.alignForward(u16, raw_frame, 16));
        try self.emitSubSp(frame);
        self.stack_frame_bytes += frame;
        var i: usize = 0;
        for (table.fields) |fld| {
            const val: *const ast.Expr = switch (fld) {
                .named => |nf| nf.val,
                .positional => |v| v,
                else => return refuse(@src()),
            };
            const is_float = val.* == .float_lit;
            const off: u16 = @intCast(i * 8);
            if (is_float) {
                const d = try self.compileExprFp(val);
                try self.emitStrSpFp(d, off);
            } else {
                const r = try self.compileExpr(val);
                try self.emitStrSp(r, off);
                self.releaseReg(r);
            }
            const key = switch (fld) {
                .named => |nf| try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ base, nf.key }),
                .positional => try std.fmt.allocPrint(self.alloc, "{s}.{d}", .{ base, i }),
                else => return refuse(@src()),
            };
            try self.fp_stack_slots.put(self.alloc, key, .{ .off = off, .float = is_float });
            i += 1;
        }
    }

    fn loadStackField(self: *Arm64Compiler, key: []const u8) Error!u5 {
        const slot = self.fp_stack_slots.get(key) orelse return undefinedKey(@src(), "fp stack slot", key);
        const reg = try self.allocReg();
        try self.emitLdrSp(reg, slot.off);
        return reg;
    }

    fn storeStackField(self: *Arm64Compiler, key: []const u8, val_reg: u5) Error!void {
        const slot = self.fp_stack_slots.get(key) orelse return undefinedKey(@src(), "fp stack slot", key);
        try self.emitStrSp(val_reg, slot.off);
    }

    fn loadFpStackField(self: *Arm64Compiler, key: []const u8) Error!u5 {
        const slot = self.fp_stack_slots.get(key) orelse return undefinedKey(@src(), "fp stack slot", key);
        if (!slot.float) return refuse(@src());
        const d = try self.allocFpReg();
        try self.emitLdrSpFp(d, slot.off);
        return d;
    }

    fn emitF64KernelCall(self: *Arm64Compiler, expr: *const ast.Expr) Error!u5 {
        const call = switch (expr.*) {
            .call => |c| c,
            else => return refuse(@src()),
        };
        if (call.func.* != .name) return refuse(@src());
        const name = call.func.name.ident;
        if (self.f64_kernel_names.get(name) == null) return refuse(@src());
        var d_slot: u5 = 0;
        for (call.args) |arg| {
            try self.emitFpCallArgInt(arg, &d_slot);
        }
        const save_set = try self.emitSaveCallerRegs();
        try self.emitBl(name);
        try self.emitRestoreCallerRegs(save_set);
        self.used_fp_regs[0] = true;
        return 0;
    }

    fn emitFpCallArgInt(self: *Arm64Compiler, arg: *const ast.Expr, d_slot: *u5) Error!void {
        switch (arg.*) {
            .name => |name| {
                try self.loadFpStackRecord(name.ident, d_slot.*);
                d_slot.* += @intCast(self.countFpStackRecordFields(name.ident));
            },
            .table => |t| {
                var slot = d_slot.*;
                try self.emitFpCallArgFromTable(t.fields, &slot);
                d_slot.* = slot;
            },
            else => {
                const d = try self.compileExprFp(arg);
                if (d != d_slot.*) try self.emitFmovReg(d_slot.*, d);
                d_slot.* += 1;
            },
        }
    }

    fn loadFpStackRecord(self: *Arm64Compiler, base: []const u8, start_slot: u5) Error!void {
        const prefix = try std.fmt.allocPrint(self.alloc, "{s}.", .{base});
        defer self.alloc.free(prefix);
        var offs: [8]u16 = undefined;
        var n: usize = 0;
        var it = self.fp_stack_slots.iterator();
        while (it.next()) |entry| {
            if (!std.mem.startsWith(u8, entry.key_ptr.*, prefix)) continue;
            if (n >= offs.len) return refuse(@src());
            offs[n] = entry.value_ptr.*.off;
            n += 1;
        }
        // Zero record fields resolved. Naming it matters: this reads as a
        // missing symbol but is really "the record has no field offsets", and
        // the two want different fixes.
        if (n == 0) return undefinedKey(@src(), "record", "no field offsets resolved");
        // Insertion sort (n <= 8).
        var i: usize = 1;
        while (i < n) : (i += 1) {
            const key = offs[i];
            var j = i;
            while (j > 0 and offs[j - 1] > key) {
                offs[j] = offs[j - 1];
                j -= 1;
            }
            offs[j] = key;
        }
        var slot: u5 = start_slot;
        var k: usize = 0;
        while (k < n) : (k += 1) {
            const d = try self.allocFpReg();
            try self.emitLdrSpFp(d, offs[k]);
            if (d != slot) try self.emitFmovReg(slot, d);
            slot += 1;
        }
    }

    fn countFpStackRecordFields(self: *Arm64Compiler, base: []const u8) usize {
        const prefix = std.fmt.allocPrint(self.alloc, "{s}.", .{base}) catch return 0;
        defer self.alloc.free(prefix);
        var n: usize = 0;
        var it = self.fp_stack_slots.iterator();
        while (it.next()) |entry| {
            if (std.mem.startsWith(u8, entry.key_ptr.*, prefix)) n += 1;
        }
        return n;
    }

    fn emitFpCallArgFromTable(self: *Arm64Compiler, fields: []const ast.TableField, d_slot: *u5) Error!void {
        for (fields) |fld| {
            const val = switch (fld) {
                .named => |nf| nf.val,
                else => return refuse(@src()),
            };
            const d = try self.compileExprFp(val);
            if (d != d_slot.*) try self.emitFmovReg(d_slot.*, d);
            d_slot.* += 1;
        }
    }

    fn tryCompileF64Subexpr(self: *Arm64Compiler, expr: *const ast.Expr) Error!?u5 {
        if (self.cur_func_float) return try self.compileExprFp(expr);
        return switch (expr.*) {
            .float_lit => |fl| blk: {
                const d = try self.allocFpReg();
                try self.emitFmovImmFp(d, fl.val);
                break :blk d;
            },
            .field => |f| blk: {
                if (f.obj.* != .name) return null;
                const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ f.obj.name.ident, f.field });
                defer self.alloc.free(key);
                const slot = self.fp_stack_slots.get(key) orelse return null;
                if (!slot.float) return null;
                break :blk try self.loadFpStackField(key);
            },
            .call => |call| blk: {
                if (call.func.* != .name) return null;
                if (self.f64_kernel_names.get(call.func.name.ident) == null) return null;
                break :blk try self.emitF64KernelCall(expr);
            },
            else => null,
        };
    }

    fn releaseReg(self: *Arm64Compiler, reg: u5) void {
        if (reg >= 9 and reg < 29 and !self.isLocalReg(reg)) {
            self.used_regs[reg] = false;
        }
    }

    fn bindNewLocalReg(self: *Arm64Compiler, reg: u5) Error!u5 {
        if (!self.isLocalReg(reg)) return reg;
        const owned = try self.allocRegExcluding(reg);
        try self.ensureRegLive(reg);
        try self.emitMovReg(owned, reg);
        return owned;
    }

    fn isLocalReg(self: *Arm64Compiler, reg: u5) bool {
        var it = self.locals.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == reg) return true;
        }
        return false;
    }

    fn compileBlock(self: *Arm64Compiler, block: ast.Block, ret_type: ast.TypeExpr) Error!void {
        for (block.stmts) |*stmt| {
            try self.compileStmt(stmt, true);
            if (self.returned) return;
        }
        if (block.tail_expr) |expr| {
            try self.emitReturnExpr(expr);
            return;
        }
        if (returnsVoid(ret_type)) {
            try self.emitMovImm(0, 0);
            try self.restoreStackFrame();
            try self.emitRet();
            self.returned = true;
            return;
        }
        return refuse(@src());
    }

    fn compileStmtBlock(self: *Arm64Compiler, block: ast.Block) Error!bool {
        const outer_returned = self.returned;
        self.returned = false;
        for (block.stmts) |*stmt| {
            try self.compileStmt(stmt, false);
            if (self.returned) break;
        }
        if (!self.returned) {
            if (block.tail_expr) |expr| {
                const reg = try self.compileExpr(expr);
                self.releaseReg(reg);
            }
        }
        const block_returned = self.returned;
        self.returned = outer_returned;
        return block_returned;
    }

    fn compileStmt(self: *Arm64Compiler, stmt: *const ast.Stmt, allow_new_locals: bool) Error!void {
        switch (stmt.*) {
            .local_decl => |ld| {
                if (!allow_new_locals) return refuse(@src());
                if (ld.names.len != ld.inits.len) return refuse(@src());
                for (ld.names, 0..) |name, i| {
                    if (ld.inits[i].* == .call and ld.inits[i].call.func.* == .name) {
                        if (self.func_record_returns.get(ld.inits[i].call.func.name.ident)) |rec| {
                            const call = ld.inits[i].call;
                            if (call.args.len > 8) return refuse(@src());
                            for (call.args, 0..) |arg, j| {
                                const arg_reg = try self.compileExpr(arg);
                                const abi_reg: u5 = @intCast(j);
                                if (arg_reg != abi_reg) try self.emitMovReg(abi_reg, arg_reg);
                                self.releaseReg(arg_reg);
                            }
                            const save_set = try self.emitSaveCallerRegs();
                            try self.emitBl(call.func.name.ident);
                            try self.emitRestoreCallerRegs(save_set);
                            try self.assignRecordFromAbiRegs(name.ident, rec);
                            continue;
                        }
                    }
                    if (ld.inits[i].* == .table and !self.cur_func_float) {
                        try self.assignRecordTable(name.ident, ld.inits[i]);
                        continue;
                    }
                    if (!isIntegerAnnotation(name.typ) and name.typ != .inferred) return refuse(@src());
                    const reg = try self.compileExpr(ld.inits[i]);
                    const local_reg = try self.bindNewLocalReg(reg);
                    try self.locals.put(self.alloc, name.ident, local_reg);
                }
            },
            .assign => |as| {
                if (as.targets.len != as.values.len) return refuse(@src());
                for (as.targets, 0..) |target, i| {
                    const val = as.values[i];
                    switch (target.*) {
                        .name => |target_name| {
                            if (val.* == .call and val.call.func.* == .name) {
                                if (self.func_record_returns.get(val.call.func.name.ident)) |rec| {
                                    if (val.call.args.len > 8) return refuse(@src());
                                    for (val.call.args, 0..) |arg, ai| {
                                        const arg_reg = try self.compileExpr(arg);
                                        const abi_reg: u5 = @intCast(ai);
                                        if (arg_reg != abi_reg) try self.emitMovReg(abi_reg, arg_reg);
                                        self.releaseReg(arg_reg);
                                    }
                                    const save_set = try self.emitSaveCallerRegs();
                                    try self.emitBl(val.call.func.name.ident);
                                    try self.emitRestoreCallerRegs(save_set);
                                    try self.assignRecordFromAbiRegs(target_name.ident, rec);
                                    continue;
                                }
                            }
                            if (val.* == .table) {
                                try self.assignRecordTable(target_name.ident, val);
                                continue;
                            }
                            const new_reg = try self.compileExpr(val);
                            if (self.locals.get(target_name.ident)) |old_reg| {
                                try self.emitMovReg(old_reg, new_reg);
                                self.releaseReg(new_reg);
                            } else if (!allow_new_locals) {
                                return error.UndefinedName;
                            } else {
                                const local_reg = try self.bindNewLocalReg(new_reg);
                                try self.locals.put(self.alloc, target_name.ident, local_reg);
                            }
                        },
                        .field => |f| {
                            if (f.obj.* != .name) return refuse(@src());
                            const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ f.obj.name.ident, f.field });
                            defer self.alloc.free(key);
                            const new_reg = try self.compileExpr(val);
                            try self.storeStackField(key, new_reg);
                            self.releaseReg(new_reg);
                        },
                        else => return refuse(@src()),
                    }
                }
            },
            .ret => |ret| {
                if (ret.vals.len == 0) {
                    try self.emitMovImm(0, 0);
                    try self.restoreStackFrame();
                    try self.emitRet();
                    self.returned = true;
                    return;
                }
                if (ret.vals.len != 1) return refuse(@src());
                try self.emitReturnExpr(ret.vals[0]);
            },
            .expr_stmt => |expr_stmt| {
                const reg = try self.compileExpr(expr_stmt.expr);
                self.releaseReg(reg);
            },
            .call_stmt => |cs| {
                const reg = try self.compileExpr(cs.expr);
                self.releaseReg(reg);
            },
            .if_stmt => |if_stmt| try self.compileIf(if_stmt),
            .while_loop => |while_loop| try self.compileWhile(while_loop),
            .num_for => |num_for| try self.compileNumFor(num_for),
            .brk => {
                if (self.loops.items.len == 0) return refuse(@src());
                const loop = self.loops.items[self.loops.items.len - 1];
                const off = try self.emitB(loop.end_label);
                try self.loops.items[self.loops.items.len - 1].break_patches.append(self.alloc, off);
            },
            .cont => {
                if (self.loops.items.len == 0) return refuse(@src());
                const loop = self.loops.items[self.loops.items.len - 1];
                const off = try self.emitB(loop.continue_label);
                try self.loops.items[self.loops.items.len - 1].continue_patches.append(self.alloc, off);
            },
            else => return refuse(@src()),
        }
    }

    fn compileIf(self: *Arm64Compiler, if_stmt: anytype) Error!void {
        var end_branches: std.ArrayList(u32) = .empty;
        defer end_branches.deinit(self.alloc);

        const end_label = self.allocLabel();
        const first_next_label = self.allocLabel();
        const first_false = try self.emitCondBranchFalse(if_stmt.cond, first_next_label);
        const then_returned = try self.compileStmtBlock(if_stmt.then);
        var all_returned = then_returned;
        if (!then_returned) {
            const off = try self.emitB(end_label);
            try end_branches.append(self.alloc, off);
        }
        try self.emitAsmLabel(first_next_label);
        try self.patchCondBranch(first_false, @intCast(self.code.items.len));

        for (if_stmt.elseifs, 0..) |elseif, i| {
            const next_label = self.allocLabel();
            const false_branch = try self.emitCondBranchFalse(elseif.cond, next_label);
            const branch_returned = try self.compileStmtBlock(elseif.body);
            all_returned = all_returned and branch_returned;
            if (!branch_returned) {
                const off = try self.emitB(end_label);
                try end_branches.append(self.alloc, off);
            }
            try self.emitAsmLabel(next_label);
            try self.patchCondBranch(false_branch, @intCast(self.code.items.len));
            _ = i;
        }

        if (if_stmt.else_body) |else_body| {
            const else_returned = try self.compileStmtBlock(else_body);
            all_returned = all_returned and else_returned;
        } else {
            all_returned = false;
        }

        try self.emitAsmLabel(end_label);
        const end_offset: u32 = @intCast(self.code.items.len);
        for (end_branches.items) |off| try self.patchB(off, end_offset);
        self.returned = all_returned;
    }

    fn compileWhile(self: *Arm64Compiler, while_loop: anytype) Error!void {
        const start_label = self.allocLabel();
        const end_label = self.allocLabel();
        try self.emitAsmLabel(start_label);
        const start_offset: u32 = @intCast(self.code.items.len);

        const false_branch = try self.emitCondBranchFalse(while_loop.cond, end_label);
        var ctx = LoopContext{ .continue_label = start_label, .end_label = end_label, .continue_patches = .empty, .break_patches = .empty };
        try self.loops.append(self.alloc, ctx);
        const body_returned = try self.compileStmtBlock(while_loop.body);
        ctx = self.loops.pop().?;

        if (!body_returned) {
            const loop_branch = try self.emitB(start_label);
            try self.patchB(loop_branch, start_offset);
        }

        try self.emitAsmLabel(end_label);
        const end_offset: u32 = @intCast(self.code.items.len);
        try self.patchCondBranch(false_branch, end_offset);
        for (ctx.continue_patches.items) |off| try self.patchB(off, start_offset);
        for (ctx.break_patches.items) |off| try self.patchB(off, end_offset);
        ctx.continue_patches.deinit(self.alloc);
        ctx.break_patches.deinit(self.alloc);
        self.returned = false;
    }

    fn compileNumFor(self: *Arm64Compiler, num_for: anytype) Error!void {
        if (!isIntegerAnnotation(num_for.var_typ) and num_for.var_typ != .inferred) return refuse(@src());
        const start_reg = try self.compileExpr(num_for.start);
        const stop_reg = try self.compileExpr(num_for.stop);
        const step_reg = if (num_for.step) |step| try self.compileExpr(step) else blk: {
            const reg = try self.allocReg();
            try self.emitMovImm(reg, 1);
            break :blk reg;
        };
        const iter_reg = try self.allocReg();
        try self.emitMovReg(iter_reg, start_reg);
        self.releaseReg(start_reg);

        const old_iter = self.locals.get(num_for.var_name);
        try self.locals.put(self.alloc, num_for.var_name, iter_reg);
        defer {
            if (old_iter) |old| {
                self.locals.put(self.alloc, num_for.var_name, old) catch {};
            } else {
                _ = self.locals.remove(num_for.var_name);
            }
            self.releaseReg(iter_reg);
        }

        const cond_label = self.allocLabel();
        const neg_label = self.allocLabel();
        const body_label = self.allocLabel();
        const continue_label = self.allocLabel();
        const end_label = self.allocLabel();

        try self.emitAsmLabel(cond_label);
        const cond_offset: u32 = @intCast(self.code.items.len);
        try self.emitCmpZero(step_reg);
        const neg_branch = try self.emitBCond(.lt, neg_label);
        try self.emitCmpReg(iter_reg, stop_reg);
        const pos_exit = try self.emitBCond(.gt, end_label);
        const pos_body = try self.emitB(body_label);

        try self.emitAsmLabel(neg_label);
        const neg_offset: u32 = @intCast(self.code.items.len);
        try self.patchCondBranch(neg_branch, neg_offset);
        try self.emitCmpReg(iter_reg, stop_reg);
        const neg_exit = try self.emitBCond(.lt, end_label);

        try self.emitAsmLabel(body_label);
        const body_offset: u32 = @intCast(self.code.items.len);
        try self.patchB(pos_body, body_offset);

        var ctx = LoopContext{ .continue_label = continue_label, .end_label = end_label, .continue_patches = .empty, .break_patches = .empty };
        try self.loops.append(self.alloc, ctx);
        const body_returned = try self.compileStmtBlock(num_for.body);
        ctx = self.loops.pop().?;

        if (!body_returned) {
            try self.emitAsmLabel(continue_label);
            const continue_offset: u32 = @intCast(self.code.items.len);
            for (ctx.continue_patches.items) |off| try self.patchB(off, continue_offset);
            try self.emitAddReg(iter_reg, iter_reg, step_reg);
            const loop_branch = try self.emitB(cond_label);
            try self.patchB(loop_branch, cond_offset);
        }

        try self.emitAsmLabel(end_label);
        const end_offset: u32 = @intCast(self.code.items.len);
        try self.patchCondBranch(pos_exit, end_offset);
        try self.patchCondBranch(neg_exit, end_offset);
        for (ctx.break_patches.items) |off| try self.patchB(off, end_offset);
        if (body_returned) {
            for (ctx.continue_patches.items) |off| try self.patchB(off, end_offset);
        }
        self.releaseReg(stop_reg);
        self.releaseReg(step_reg);
        ctx.continue_patches.deinit(self.alloc);
        ctx.break_patches.deinit(self.alloc);
        self.returned = false;
    }

    fn emitRecordReturnFromTable(self: *Arm64Compiler, fields: []const ast.TableField, desc: ScalRecordDesc) Error!void {
        var reg_idx: u5 = 0;
        for (desc.field_names) |fname| {
            const val = findTableFieldValue(fields, fname) orelse return refuse(@src());
            const r = try self.compileExpr(val);
            if (r != reg_idx) try self.emitMovReg(reg_idx, r);
            self.releaseReg(r);
            reg_idx += 1;
        }
        try self.restoreStackFrame();
        try self.emitRet();
        self.returned = true;
    }

    fn assignRecordFromAbiRegs(self: *Arm64Compiler, base: []const u8, desc: ScalRecordDesc) Error!void {
        const n = desc.field_names.len;
        if (n == 0 or n > 8) return refuse(@src());

        // The slot is reserved once per record local, not once per execution.
        // This code runs again on every loop iteration, and emitting `sub sp`
        // each time walks the stack pointer down by a frame per iteration —
        // every field offset shifts and the loads return garbage. Reuse the
        // reservation when this base already has one.
        const first_key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ base, desc.field_names[0] });
        defer self.alloc.free(first_key);
        const already_reserved = self.fp_stack_slots.contains(first_key);

        var base_off: u16 = 0;
        if (already_reserved) {
            base_off = (self.fp_stack_slots.get(first_key) orelse unreachable).off;
        } else {
            const raw_frame: u16 = @intCast(n * 8);
            const frame: u16 = @intCast(std.mem.alignForward(u16, raw_frame, 16));
            try self.emitSubSp(frame);
            self.stack_frame_bytes += frame;
        }

        var i: usize = 0;
        while (i < n) : (i += 1) {
            const off: u16 = base_off + @as(u16, @intCast(i * 8));
            const abi_reg: u5 = @intCast(i);
            try self.emitStrSp(abi_reg, off);
            if (already_reserved) continue;
            const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ base, desc.field_names[i] });
            try self.fp_stack_slots.put(self.alloc, key, .{ .off = off, .float = false });
        }
    }

    fn assignF64RecordFromFpAbiRegs(self: *Arm64Compiler, base: []const u8, desc: F64RecordDesc) Error!void {
        const n = desc.field_names.len;
        if (n == 0 or n > 8) return refuse(@src());
        const raw_frame: u16 = @intCast(n * 8);
        const frame: u16 = @intCast(std.mem.alignForward(u16, raw_frame, 16));
        try self.emitSubSp(frame);
        self.stack_frame_bytes += frame;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const off: u16 = @intCast(i * 8);
            const abi_d: u5 = @intCast(i);
            self.used_fp_regs[abi_d] = true;
            try self.emitStrSpFp(abi_d, off);
            const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ base, desc.field_names[i] });
            try self.fp_locals.put(self.alloc, key, abi_d);
            try self.fp_stack_slots.put(self.alloc, key, .{ .off = off, .float = true });
        }
    }

    fn emitRetF64RecordFromDnir(self: *Arm64Compiler, temps: *std.AutoHashMapUnmanaged(u32, u5), ins: dnir.Instr) Error!void {
        const vals = [_]dnir.Value{ ins.lhs, ins.rhs, ins.third };
        const count = ins.result orelse 1;
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const d = try self.evalDnirValueFp(temps, vals[@intCast(i)]);
            const abi_d: u5 = @intCast(i);
            if (d != abi_d) try self.emitFmovReg(abi_d, d);
            if (d != abi_d) self.releaseFpReg(d);
            self.used_fp_regs[abi_d] = true;
        }
    }

    fn ensureExternalSymbol(self: *Arm64Compiler, symbol_name: []const u8) Error!void {
        if (self.definedSymbolOffset(symbol_name) != null) return;
        if (self.extern_symbols.contains(symbol_name)) return;
        if (self.symbolOffset(symbol_name)) |_| return error.DuplicateSymbol;
        const owned_name = try self.alloc.dupe(u8, symbol_name);
        errdefer self.alloc.free(owned_name);
        const symbol_index: u32 = @intCast(self.symbols.items.len);
        try self.symbols.append(self.alloc, .{ .name = owned_name, .offset = 0, .defined = false });
        try self.extern_symbols.put(self.alloc, symbol_name, symbol_index);
    }

    fn tryCompileReqFieldAccess(self: *Arm64Compiler, obj: []const u8, field: []const u8) Error!?u5 {
        if (self.req_ctx.constant(obj, field)) |val| {
            const reg = try self.allocReg();
            try self.emitMovImm(reg, val);
            return reg;
        }
        return null;
    }

    fn tryCompileReqFieldCall(self: *Arm64Compiler, call_expr: *const ast.Expr) Error!?u5 {
        if (call_expr.* != .call) return null;
        const call = call_expr.call;
        if (call.func.* != .field) return null;
        const f = call.func.field;
        if (f.obj.* != .name) return null;
        const alias = f.obj.name.ident;
        const sym = self.req_ctx.exportSymbol(alias, f.field) orelse return null;
        if (call.args.len > 8) return refuse(@src());
        for (call.args, 0..) |arg, i| {
            const arg_reg = try self.compileExpr(arg);
            const abi_reg: u5 = @intCast(i);
            if (arg_reg != abi_reg) try self.emitMovReg(abi_reg, arg_reg);
            self.releaseReg(arg_reg);
        }
        try self.ensureExternalSymbol(sym);
        const save_set = try self.emitSaveCallerRegs();
        try self.emitBl(sym);
        try self.emitRestoreCallerRegs(save_set);
        const dst = try self.allocReg();
        try self.emitMovReg(dst, 0);
        return dst;
    }

    fn emitReturnExpr(self: *Arm64Compiler, expr: *const ast.Expr) Error!void {
        if (self.cur_func_ret_record) |rec| {
            if (expr.* == .table) {
                try self.emitRecordReturnFromTable(expr.table.fields, rec);
                return;
            }
        }
        if (self.cur_func_float) {
            const d = try self.compileExprFp(expr);
            if (d != 0) try self.emitFmovReg(0, d);
            if (self.needsProcessExitF64Coerce()) try self.emitFcvtzsX0FromD0();
            try self.restoreStackFrame();
            try self.emitRet();
            self.returned = true;
            return;
        }
        if (self.cur_func_ret_float) {
            const d = try self.tryCompileF64Subexpr(expr) orelse return refuse(@src());
            if (d != 0) try self.emitFmovReg(0, d);
            if (self.needsProcessExitF64Coerce()) try self.emitFcvtzsX0FromD0();
            try self.restoreStackFrame();
            try self.emitRet();
            self.returned = true;
            return;
        }
        const reg = try self.compileExpr(expr);
        if (reg != 0) try self.emitMovReg(0, reg);
        self.releaseReg(reg);
        try self.restoreStackFrame();
        try self.emitRet();
        self.returned = true;
    }

    fn compileExprFp(self: *Arm64Compiler, expr: *const ast.Expr) Error!u5 {
        // Pure-f64 lowering. f64 literals materialize via emitMovImm (bit
        // pattern into an x-reg) + FMOV general->FP — no literal pool / data
        // section needed. Params arrive in d0-d7; arithmetic covers kernels.
        return switch (expr.*) {
            .float_lit => |fl| blk: {
                const tmp = try self.allocReg();
                try self.emitMovImm(tmp, @bitCast(fl.val));
                const dst = try self.allocFpReg();
                try self.emitFmovFromGpr(dst, tmp);
                self.releaseReg(tmp);
                break :blk dst;
            },
            .name => |name| self.fp_locals.get(name.ident) orelse error.UndefinedName,
            .field => |f| blk: {
                if (f.obj.* != .name) return refuse(@src());
                const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ f.obj.name.ident, f.field });
                break :blk self.fp_locals.get(key) orelse error.UndefinedName;
            },
            .binop => |bin| blk: {
                const lhs = try self.compileExprFp(bin.lhs);
                const rhs = try self.compileExprFp(bin.rhs);
                const dst = try self.allocFpReg();
                switch (bin.op) {
                    .add => try self.emitFaddReg(dst, lhs, rhs),
                    .sub => try self.emitFsubReg(dst, lhs, rhs),
                    .mul => try self.emitFmulReg(dst, lhs, rhs),
                    .div, .idiv => try self.emitFdivReg(dst, lhs, rhs),
                    else => return refuse(@src()),
                }
                break :blk dst;
            },
            .call => |call| blk: {
                if (call.func.* != .name) return refuse(@src());
                if (self.f64_kernel_names.get(call.func.name.ident)) |_| {
                    break :blk try self.emitF64KernelCall(expr);
                }
                var d_slot: u5 = 0;
                for (call.args) |arg| {
                    try self.emitFpCallArg(arg, &d_slot);
                }
                const save_set = try self.emitSaveCallerRegs();
                try self.emitBl(call.func.name.ident);
                try self.emitRestoreCallerRegs(save_set);
                self.used_fp_regs[0] = true;
                break :blk @as(u5, 0);
            },
            else => refuse(@src()),
        };
    }

    fn emitFpCallArg(self: *Arm64Compiler, arg: *const ast.Expr, d_slot: *u5) Error!void {
        switch (arg.*) {
            .table => |t| {
                for (t.fields) |fld| {
                    const val = switch (fld) {
                        .named => |nf| nf.val,
                        else => return refuse(@src()),
                    };
                    const d = try self.compileExprFp(val);
                    if (d != d_slot.*) try self.emitFmovReg(d_slot.*, d);
                    d_slot.* += 1;
                }
            },
            else => {
                const d = try self.compileExprFp(arg);
                if (d != d_slot.*) try self.emitFmovReg(d_slot.*, d);
                d_slot.* += 1;
            },
        }
    }

    fn tryEmitLuaAndOrTernary(self: *Arm64Compiler, op: ast.BinOp, lhs: *ast.Expr, rhs: *ast.Expr) Error!?u5 {
        // Lua idiom: `(cond) and then_val or else_val` — truthiness applies only to `cond`.
        if (op != .@"or" or lhs.* != .binop) return null;
        const and_b = lhs.binop;
        if (and_b.op != .@"and") return null;

        const dst = try self.allocReg();
        const else_label = self.allocLabel();
        const end_label = self.allocLabel();

        const cond_false = try self.emitCondBranchFalse(and_b.lhs, else_label);
        const then_reg = try self.compileExpr(and_b.rhs);
        try self.emitMovReg(dst, then_reg);
        self.releaseReg(then_reg);
        const to_end = try self.emitB(end_label);
        try self.emitAsmLabel(else_label);
        try self.patchCondBranch(cond_false, @intCast(self.code.items.len));
        const else_reg = try self.compileExpr(rhs);
        try self.emitMovReg(dst, else_reg);
        self.releaseReg(else_reg);
        try self.emitAsmLabel(end_label);
        try self.patchB(to_end, @intCast(self.code.items.len));
        return dst;
    }

    fn compileExpr(self: *Arm64Compiler, expr: *const ast.Expr) Error!u5 {
        if (self.cur_func_float) return self.compileExprFp(expr);
        return switch (expr.*) {
            .int_lit => |lit| blk: {
                const reg = try self.allocReg();
                try self.emitMovImm(reg, lit.val);
                break :blk reg;
            },
            .string_lit => |lit| blk: {
                const symbol_index = try self.internString(lit.val);
                const reg = try self.allocReg();
                try self.emitAdrpAdd(reg, symbol_index);
                break :blk reg;
            },
            .name => |name| blk: {
                if (self.blob_symbol_map.get(name.ident)) |sym_idx| {
                    const reg = try self.allocReg();
                    try self.emitBlobPtr(reg, sym_idx);
                    break :blk reg;
                }
                const reg = self.locals.get(name.ident) orelse return undefinedKey(@src(), "local", name.ident);
                break :blk try self.bindNewLocalReg(reg);
            },
            .field => |f| blk: {
                if (f.obj.* != .name) return refuse(@src());
                if (try self.tryCompileReqFieldAccess(f.obj.name.ident, f.field)) |reg| break :blk reg;
                const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ f.obj.name.ident, f.field });
                defer self.alloc.free(key);
                break :blk try self.loadStackField(key);
            },
            .unop => |un| switch (un.op) {
                .neg => blk: {
                    const src = try self.compileExpr(un.operand);
                    const dst = try self.allocReg();
                    try self.emitSubReg(dst, 31, src);
                    self.releaseReg(src);
                    break :blk dst;
                },
                .bnot => blk: {
                    const src = try self.compileExpr(un.operand);
                    const dst = try self.allocReg();
                    try self.emitFmt(0xaa2003e0 | (@as(u32, src) << 16) | @as(u32, dst), "mvn x{d}, x{d}", .{ dst, src });
                    self.releaseReg(src);
                    break :blk dst;
                },
                else => refuse(@src()),
            },
            .binop => |bin| blk: {
                if (try self.tryEmitLuaAndOrTernary(bin.op, bin.lhs, bin.rhs)) |ternary_reg| {
                    break :blk ternary_reg;
                }
                if (try self.tryCompileF64Subexpr(bin.lhs)) |d_lhs| {
                    const rhs_reg = try self.compileExpr(bin.rhs);
                    const d_rhs = try self.allocFpReg();
                    try self.emitScvtfFromGpr(d_rhs, rhs_reg);
                    self.releaseReg(rhs_reg);
                    const dst = try self.allocReg();
                    if (isComparison(bin.op)) {
                        try self.emitFcmpReg(d_lhs, d_rhs);
                        try self.emitCsetFp(dst, conditionForComparison(bin.op));
                    } else {
                        return refuse(@src());
                    }
                    break :blk dst;
                }
                if (bin.op == .@"and" or bin.op == .@"or") {
                    const lhs = try self.compileExpr(bin.lhs);
                    const dst = try self.allocReg();
                    const branch_label = self.allocLabel();
                    const end_label = self.allocLabel();
                    if (bin.op == .@"and") {
                        const skip_rhs = try self.emitBCond(.eq, branch_label);
                        const rhs_val = try self.compileExpr(bin.rhs);
                        const to_end = try self.emitB(end_label);
                        try self.emitAsmLabel(branch_label);
                        try self.patchCondBranch(skip_rhs, @intCast(self.code.items.len));
                        try self.emitMovReg(dst, lhs);
                        self.releaseReg(lhs);
                        try self.emitAsmLabel(end_label);
                        try self.patchB(to_end, @intCast(self.code.items.len));
                        try self.emitMovReg(dst, rhs_val);
                        self.releaseReg(rhs_val);
                    } else {
                        const skip_rhs = try self.emitBCond(.ne, branch_label);
                        const rhs_val = try self.compileExpr(bin.rhs);
                        const to_end = try self.emitB(end_label);
                        try self.emitAsmLabel(branch_label);
                        try self.patchCondBranch(skip_rhs, @intCast(self.code.items.len));
                        try self.emitMovReg(dst, lhs);
                        self.releaseReg(lhs);
                        try self.emitAsmLabel(end_label);
                        try self.patchB(to_end, @intCast(self.code.items.len));
                        try self.emitMovReg(dst, rhs_val);
                        self.releaseReg(rhs_val);
                    }
                    break :blk dst;
                }
                const lhs = try self.compileExpr(bin.lhs);
                const rhs = try self.compileExpr(bin.rhs);
                const dst = try self.allocReg();
                switch (bin.op) {
                    .add => try self.emitAddReg(dst, lhs, rhs),
                    .sub => try self.emitSubReg(dst, lhs, rhs),
                    .mul => try self.emitMulReg(dst, lhs, rhs),
                    .div, .idiv => try self.emitSdivReg(dst, lhs, rhs),
                    .mod => {
                        const q = try self.allocReg();
                        try self.emitSdivReg(q, lhs, rhs);
                        try self.emitMsubReg(dst, q, rhs, lhs);
                        self.releaseReg(q);
                    },
                    .band => try self.emitAndReg(dst, lhs, rhs),
                    .bor => try self.emitOrrReg(dst, lhs, rhs),
                    .bxor => try self.emitEorReg(dst, lhs, rhs),
                    .lshift => try self.emitLslReg(dst, lhs, rhs),
                    .rshift => try self.emitAsrReg(dst, lhs, rhs),
                    .eq, .neq, .lt, .gt, .leq, .geq => try self.emitCompareResult(dst, lhs, rhs, conditionForComparison(bin.op)),
                    else => return refuse(@src()),
                }
                self.releaseReg(lhs);
                self.releaseReg(rhs);
                break :blk dst;
            },
            .call => |call| blk: {
                if (call.func.* == .field) {
                    if (try self.tryCompileReqFieldCall(expr)) |req_reg| break :blk req_reg;
                    return refuse(@src());
                }
                if (call.func.* != .name) return refuse(@src());
                if (std.mem.eql(u8, call.func.name.ident, "__native_load_u8")) {
                    if (call.args.len != 2) return refuse(@src());
                    const base = try self.compileExpr(call.args[0]);
                    const off = try self.compileExpr(call.args[1]);
                    const dst = try self.emitLoadU8Intrinsic(base, off);
                    self.releaseReg(base);
                    self.releaseReg(off);
                    break :blk dst;
                }
                if (self.f64_kernel_names.get(call.func.name.ident)) |_| {
                    const d = try self.emitF64KernelCall(expr);
                    const xdst = try self.allocReg();
                    try self.emitFcvtzsFromFp(xdst, d);
                    break :blk xdst;
                }
                const rec_ret = self.func_record_returns.get(call.func.name.ident);
                if (call.args.len > 8) return refuse(@src());
                for (call.args, 0..) |arg, i| {
                    const arg_reg = try self.compileExpr(arg);
                    const abi_reg: u5 = @intCast(i);
                    if (arg_reg != abi_reg) try self.emitMovReg(abi_reg, arg_reg);
                    self.releaseReg(arg_reg);
                }
                const save_set = try self.emitSaveCallerRegs();
                try self.emitBl(call.func.name.ident);
                try self.emitRestoreCallerRegs(save_set);
                if (rec_ret) |rec| {
                    // Record return lands in x0..; caller only needs side-effect on stack slots
                    // when assigned — handled in compileStmt assign path.
                    _ = rec;
                    const dst = try self.allocReg();
                    try self.emitMovImm(dst, 0);
                    break :blk dst;
                }
                const dst = try self.allocReg();
                try self.emitMovReg(dst, 0);
                break :blk dst;
            },
            else => refuse(@src()),
        };
    }

    fn compileCondition(self: *Arm64Compiler, expr: *const ast.Expr) Error!Condition {
        if (expr.* == .binop and isComparison(expr.binop.op)) {
            const op = expr.binop.op;
            if (try self.tryCompileF64Subexpr(expr.binop.lhs)) |lhs_d| {
                if (try self.tryCompileF64Subexpr(expr.binop.rhs)) |rhs_d| {
                    try self.emitFcmpReg(lhs_d, rhs_d);
                    return conditionForComparison(op);
                }
                const rhs_reg = try self.compileExpr(expr.binop.rhs);
                const lhs_reg = try self.allocReg();
                try self.emitFcvtzsFromFp(lhs_reg, lhs_d);
                try self.emitCmpReg(lhs_reg, rhs_reg);
                self.releaseReg(lhs_reg);
                self.releaseReg(rhs_reg);
                return conditionForComparison(op);
            }
            const lhs = try self.compileExpr(expr.binop.lhs);
            const rhs = try self.compileExpr(expr.binop.rhs);
            try self.emitCmpReg(lhs, rhs);
            self.releaseReg(lhs);
            self.releaseReg(rhs);
            return conditionForComparison(op);
        }
        const reg = try self.compileExpr(expr);
        try self.emitCmpZero(reg);
        self.releaseReg(reg);
        return .ne;
    }

    fn emitCondBranchFalse(self: *Arm64Compiler, expr: *const ast.Expr, label: u32) Error!u32 {
        const cond = try self.compileCondition(expr);
        return self.emitBCond(invertCondition(cond), label);
    }

    fn emitMovImm(self: *Arm64Compiler, reg: u5, value: i64) Error!void {
        const unsigned = @as(u64, @bitCast(value));
        var emitted = false;
        var shift: u32 = 0;
        while (shift < 64) : (shift += 16) {
            const part: u16 = @intCast((unsigned >> @as(u6, @intCast(shift))) & 0xffff);
            const hw = shift / 16;
            if (!emitted) {
                const word = 0xd2800000 | (hw << 21) | (@as(u32, part) << 5) | @as(u32, reg);
                if (shift == 0) {
                    try self.emitFmt(word, "mov x{d}, #{d}", .{ reg, part });
                } else {
                    try self.emitFmt(word, "movz x{d}, #{d}, lsl #{d}", .{ reg, part, shift });
                }
                emitted = true;
            } else if (part != 0) {
                try self.emitFmt(0xf2800000 | (hw << 21) | (@as(u32, part) << 5) | @as(u32, reg), "movk x{d}, #{d}, lsl #{d}", .{ reg, part, shift });
            }
        }
        if (!emitted) try self.emitFmt(0xd2800000 | @as(u32, reg), "mov x{d}, #0", .{reg});
    }

    fn emitMovReg(self: *Arm64Compiler, dst: u5, src: u5) Error!void {
        try self.ensureRegLive(src);
        try self.emitFmt(0xaa0003e0 | (@as(u32, src) << 16) | @as(u32, dst), "mov x{d}, x{d}", .{ dst, src });
    }

    fn emitRet(self: *Arm64Compiler) Error!void {
        try self.emit(0xd65f03c0, "ret");
    }

    fn allocLabel(self: *Arm64Compiler) u32 {
        const label = self.next_label;
        self.next_label += 1;
        return label;
    }

    fn emitAsmLabel(self: *Arm64Compiler, label: u32) Error!void {
        try self.asm_text.print(self.alloc, ".Lduo_{d}:\n", .{label});
    }

    fn emitBl(self: *Arm64Compiler, target: []const u8) Error!void {
        const offset: u32 = @intCast(self.code.items.len);
        const link_name = try linkerSymbolName(self.alloc, target);
        const owned_target = try self.alloc.dupe(u8, link_name);
        try self.call_patches.append(self.alloc, .{ .offset = offset, .target = owned_target });
        try self.emitFmt(0x94000000, "bl _{s}", .{link_name});
    }

    fn emitB(self: *Arm64Compiler, label: u32) Error!u32 {
        const offset: u32 = @intCast(self.code.items.len);
        try self.emitFmt(0x14000000, "b .Lduo_{d}", .{label});
        return offset;
    }

    fn emitBCond(self: *Arm64Compiler, cond: Condition, label: u32) Error!u32 {
        const offset: u32 = @intCast(self.code.items.len);
        try self.emitFmt(0x54000000 | @as(u32, @intFromEnum(cond)), "b.{s} .Lduo_{d}", .{ conditionName(cond), label });
        return offset;
    }

    fn emitSaveCallerRegs(self: *Arm64Compiler) Error!SaveSet {
        var save_set = SaveSet{};
        var reg: u5 = 9;
        while (reg <= 28) : (reg += 1) {
            if (self.used_regs[reg]) {
                save_set.regs[save_set.count] = reg;
                save_set.count += 1;
            }
        }
        var slots: u16 = @as(u16, save_set.count) + 1;
        if ((slots % 2) != 0) slots += 1;
        save_set.stack_bytes = slots * 8;
        try self.emitSubSp(save_set.stack_bytes);
        var offset: u16 = 0;
        var i: u5 = 0;
        while (i < save_set.count) : ({
            i += 1;
            offset += 8;
        }) {
            try self.emitStrSp(save_set.regs[i], offset);
        }
        try self.emitStrSp(30, @as(u16, save_set.count) * 8);
        return save_set;
    }

    /// Lay the staged variadic tail out at [sp, #0], [sp, #8], … and return the
    /// number of bytes sp moved by. Emitted AFTER `emitSaveCallerRegs`, so the
    /// callee's memory-argument area starts exactly at sp — which is what
    /// `va_arg` reads on Apple ARM64 — while the save area sits above it and
    /// stays addressable at its original offsets once sp is restored.
    fn emitPushVarargs(self: *Arm64Compiler) Error!u16 {
        if (self.pending_vararg_count == 0) return 0;
        var bytes: u16 = @as(u16, self.pending_vararg_count) * 8;
        if ((bytes % 16) != 0) bytes += 8;
        try self.emitSubSp(bytes);
        var i: u5 = 0;
        while (i < self.pending_vararg_count) : (i += 1) {
            try self.emitStrSp(self.pending_varargs[i].reg, @as(u16, i) * 8);
        }
        return bytes;
    }

    /// Undo `emitPushVarargs` and clear the staging list. Registers allocated
    /// solely to carry a tail argument go back to the pool here; a `.temp` or
    /// `.local` register belongs to the slot map and is left alone.
    fn emitPopVarargs(self: *Arm64Compiler, bytes: u16) Error!void {
        if (bytes > 0) try self.emitAddSp(bytes);
        var i: u5 = 0;
        while (i < self.pending_vararg_count) : (i += 1) {
            if (self.pending_varargs[i].scratch) self.releaseReg(self.pending_varargs[i].reg);
            self.pending_varargs[i] = .{};
        }
        self.pending_vararg_count = 0;
    }

    fn emitRestoreCallerRegs(self: *Arm64Compiler, save_set: SaveSet) Error!void {
        var offset: u16 = 0;
        var i: u5 = 0;
        while (i < save_set.count) : ({
            i += 1;
            offset += 8;
        }) {
            try self.emitLdrSp(save_set.regs[i], offset);
        }
        try self.emitLdrSp(30, @as(u16, save_set.count) * 8);
        try self.emitAddSp(save_set.stack_bytes);
    }

    fn emitSubSp(self: *Arm64Compiler, bytes: u16) Error!void {
        try self.emitFmt(0xd10003ff | (@as(u32, bytes) << 10), "sub sp, sp, #{d}", .{bytes});
    }

    fn emitAddSp(self: *Arm64Compiler, bytes: u16) Error!void {
        try self.emitFmt(0x910003ff | (@as(u32, bytes) << 10), "add sp, sp, #{d}", .{bytes});
    }

    fn emitStrSp(self: *Arm64Compiler, reg: u5, offset: u16) Error!void {
        try self.emitFmt(0xf90003e0 | ((@as(u32, offset) / 8) << 10) | @as(u32, reg), "str x{d}, [sp, #{d}]", .{ reg, offset });
    }

    fn emitLdrSp(self: *Arm64Compiler, reg: u5, offset: u16) Error!void {
        try self.emitFmt(0xf94003e0 | ((@as(u32, offset) / 8) << 10) | @as(u32, reg), "ldr x{d}, [sp, #{d}]", .{ reg, offset });
    }

    /// Release `reg` only if it was scratch for this instruction. A `.local` or
    /// `.temp` operand's register is owned by the slot map and outlives us.
    fn releaseDnirTemp(
        self: *Arm64Compiler,
        pinned: *const std.AutoHashMapUnmanaged(u32, u5),
        v: dnir.Value,
        reg: u5,
    ) void {
        switch (v) {
            .local, .temp => return,
            else => {},
        }
        if (Arm64Compiler.regIsPinned(pinned, reg)) return;
        self.releaseReg(reg);
    }

    /// `str xs, [xbase, #imm]` — 8-byte store at a constant offset from an
    /// arbitrary base. `emitStrSp` is the same encoding pinned to x31/sp; the
    /// indirect-result buffer lives at a pointer the caller chose, so the base
    /// has to be a register.
    fn emitStrBaseImm(self: *Arm64Compiler, src: u5, base: u5, offset: u16) Error!void {
        if (offset % 8 != 0 or offset / 8 > 4095) return refuse(@src());
        try self.ensureRegLive(base);
        try self.ensureRegLive(src);
        try self.emitFmt(
            0xf9000000 | ((@as(u32, offset) / 8) << 10) | (@as(u32, base) << 5) | @as(u32, src),
            "str x{d}, [x{d}, #{d}]",
            .{ src, base, offset },
        );
    }

    /// Every field value of a `ret_record`, in descriptor order.
    ///
    /// `vals` is authoritative when the lowerer set it. The `lhs`/`rhs`/`third`
    /// fallback exists for DNIR built by hand in tests, and stops at three for
    /// the same reason it always did — there is no fourth inline slot.
    fn dnirRetRecordVals(self: *Arm64Compiler, ins: dnir.Instr) Error![]const dnir.Value {
        if (ins.vals.len > 0) return ins.vals;
        var n: usize = 0;
        self.ret_record_scratch[0] = ins.lhs;
        n = 1;
        if (ins.rhs != .void) {
            self.ret_record_scratch[1] = ins.rhs;
            n = 2;
        }
        if (ins.third != .void) {
            self.ret_record_scratch[2] = ins.third;
            n = 3;
        }
        return self.ret_record_scratch[0..n];
    }

    /// The frame offset of the buffer this call must fill through x8, or null
    /// when the call returns in registers (or returns no record at all).
    fn indirectResultBuffer(self: *Arm64Compiler, ins: dnir.Instr) Error!?u16 {
        if (ins.record.len == 0) return null;
        const rec = scalRecordDesc(self.scal_records, .{ .named = ins.record }) orelse return null;
        if (rec.field_names.len <= dnir_lower.max_reg_record_fields) return null;
        const base = if (ins.field.len > 0) ins.field else "rec";
        const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ base, rec.field_names[0] });
        defer self.alloc.free(key);
        // The prologue pre-pass reserves one region per record base. If it did
        // not, there is no buffer to point x8 at and the callee would write
        // through whatever x8 held on entry — refuse rather than emit that.
        const slot = self.fp_stack_slots.get(key) orelse return refuse(@src());
        return slot.off;
    }

    /// `add xd, sp, #imm` — materialize the address of a frame slot region.
    fn emitAddSpImm(self: *Arm64Compiler, dst: u5, bytes: u16) Error!void {
        if (bytes > 4095) return refuse(@src());
        try self.emitFmt(
            0x910003e0 | (@as(u32, bytes) << 10) | @as(u32, dst),
            "add x{d}, sp, #{d}",
            .{ dst, bytes },
        );
    }

    /// `ldr xd, [xbase, xidx, lsl #3]` — 8-byte scaled indexed load.
    fn emitLdrScaled(self: *Arm64Compiler, dst: u5, base: u5, idx: u5) Error!void {
        try self.ensureRegLive(base);
        try self.ensureRegLive(idx);
        try self.emitFmt(
            0xf8607800 | (@as(u32, idx) << 16) | (@as(u32, base) << 5) | @as(u32, dst),
            "ldr x{d}, [x{d}, x{d}, lsl #3]",
            .{ dst, base, idx },
        );
    }

    /// `str xs, [xbase, xidx, lsl #3]` — 8-byte scaled indexed store.
    fn emitStrScaled(self: *Arm64Compiler, src: u5, base: u5, idx: u5) Error!void {
        try self.ensureRegLive(base);
        try self.ensureRegLive(idx);
        try self.ensureRegLive(src);
        try self.emitFmt(
            0xf8207800 | (@as(u32, idx) << 16) | (@as(u32, base) << 5) | @as(u32, src),
            "str x{d}, [x{d}, x{d}, lsl #3]",
            .{ src, base, idx },
        );
    }

    /// STRB, immediate, unsigned offset — the write half of the pair emitLdrb
    /// has had all along. Same addressing form: 0x39000000 against LDRB's
    /// 0x39400000.
    fn emitStrb(self: *Arm64Compiler, src: u5, base: u5) Error!void {
        try self.ensureRegLive(base);
        try self.ensureRegLive(src);
        try self.emitFmt(0x39000000 | (@as(u32, base) << 5) | @as(u32, src), "strb w{d}, [x{d}]", .{ src, base });
    }

    fn emitLdrb(self: *Arm64Compiler, dst: u5, base: u5) Error!void {
        try self.ensureRegLive(base);
        try self.emitFmt(0x39400000 | (@as(u32, base) << 5) | @as(u32, dst), "ldrb x{d}, [x{d}]", .{ dst, base });
    }

    /// Bitwise and shift, register forms. Same field layout as add/sub:
    /// opcode | (Rm << 16) | (Rn << 5) | Rd.
    fn emitBitReg(self: *Arm64Compiler, op: u32, mnemonic: []const u8, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.ensureRegLive(lhs);
        try self.ensureRegLive(rhs);
        try self.emitFmt(op | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "{s} x{d}, x{d}, x{d}", .{ mnemonic, dst, lhs, rhs });
    }

    fn emitAddReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.ensureRegLive(lhs);
        try self.ensureRegLive(rhs);
        try self.emitFmt(0x8b000000 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "add x{d}, x{d}, x{d}", .{ dst, lhs, rhs });
    }

    fn emitSubReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.ensureRegLive(lhs);
        try self.ensureRegLive(rhs);
        try self.emitFmt(0xcb000000 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "sub x{d}, x{d}, x{d}", .{ dst, lhs, rhs });
    }

    fn emitCmpReg(self: *Arm64Compiler, lhs: u5, rhs: u5) Error!void {
        try self.ensureRegLive(lhs);
        try self.ensureRegLive(rhs);
        try self.emitFmt(0xeb00001f | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5), "cmp x{d}, x{d}", .{ lhs, rhs });
    }

    fn emitCmpZero(self: *Arm64Compiler, reg: u5) Error!void {
        try self.ensureRegLive(reg);
        try self.emitFmt(0xf100001f | (@as(u32, reg) << 5), "cmp x{d}, #0", .{reg});
    }

    fn emitCompareResult(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5, cond: Condition) Error!void {
        try self.emitCmpReg(lhs, rhs);
        try self.emitFmt(encodeCset(dst, cond), "cset x{d}, {s}", .{ dst, conditionName(cond) });
    }

    fn emitMulReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.ensureRegLive(lhs);
        try self.ensureRegLive(rhs);
        try self.emitFmt(0x9b007c00 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "mul x{d}, x{d}, x{d}", .{ dst, lhs, rhs });
    }

    fn emitSdivReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.ensureRegLive(lhs);
        try self.ensureRegLive(rhs);
        try self.emitFmt(0x9ac00c00 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "sdiv x{d}, x{d}, x{d}", .{ dst, lhs, rhs });
    }

    fn emitMsubReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5, acc: u5) Error!void {
        try self.ensureRegLive(lhs);
        try self.ensureRegLive(rhs);
        try self.ensureRegLive(acc);
        try self.emitFmt(0x9b008000 | (@as(u32, rhs) << 16) | (@as(u32, acc) << 10) | (@as(u32, lhs) << 5) | @as(u32, dst), "msub x{d}, x{d}, x{d}, x{d}", .{ dst, lhs, rhs, acc });
    }

    fn emitAndReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.ensureRegLive(lhs);
        try self.ensureRegLive(rhs);
        try self.emitFmt(0x8a000000 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "and x{d}, x{d}, x{d}", .{ dst, lhs, rhs });
    }

    fn emitOrrReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.ensureRegLive(lhs);
        try self.ensureRegLive(rhs);
        try self.emitFmt(0xaa000000 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "orr x{d}, x{d}, x{d}", .{ dst, lhs, rhs });
    }

    fn emitEorReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.ensureRegLive(lhs);
        try self.ensureRegLive(rhs);
        try self.emitFmt(0xca000000 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "eor x{d}, x{d}, x{d}", .{ dst, lhs, rhs });
    }

    // Variable (register-amount) shifts — Data-processing (2 source), 64-bit.
    // Rm=rhs (shift amount, bits 16-20), Rn=lhs (value, bits 5-9), Rd=dst.
    // Matches the C backend's int64_t << / >> (LSL / arithmetic ASR on arm64).
    fn emitLslReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.ensureRegLive(lhs);
        try self.ensureRegLive(rhs);
        try self.emitFmt(0x9ac02000 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "lsl x{d}, x{d}, x{d}", .{ dst, lhs, rhs });
    }

    fn emitAsrReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.ensureRegLive(lhs);
        try self.ensureRegLive(rhs);
        try self.emitFmt(0x9ac02800 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "asr x{d}, x{d}, x{d}", .{ dst, lhs, rhs });
    }

    // --- f64 (scalar double) lowering. Verified encodings (from `as`/objdump
    // ground truth): double FADD=0x1E602800, FSUB=0x1E603800, FMUL=0x1E600800,
    // FDIV=0x1E601800, FMOV <Dd>,<Dn>=0x1E604000. (0x1EE0xxxx is HALF-precision,
    // a trap from miscounting the type field.) Register layout matches the
    // integer 2-source ops: Rm=rhs (bits 16-20), Rn=lhs (bits 5-9), Rd (0-4).
    fn allocFpReg(self: *Arm64Compiler) Error!u5 {
        // d0-d7 are caller-saved; params occupy the low ones, scratch takes the
        // next free. Sufficient for leaf kernels with a handful of f64 params.
        var reg: u5 = 0;
        while (reg < 8) : (reg += 1) {
            if (!self.used_fp_regs[reg]) {
                self.used_fp_regs[reg] = true;
                return reg;
            }
        }
        return error.RegisterExhausted;
    }

    fn emitFaddReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.emitFmt(0x1e602800 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "fadd d{d}, d{d}, d{d}", .{ dst, lhs, rhs });
    }

    fn emitFsubReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.emitFmt(0x1e603800 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "fsub d{d}, d{d}, d{d}", .{ dst, lhs, rhs });
    }

    fn emitFmulReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.emitFmt(0x1e600800 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "fmul d{d}, d{d}, d{d}", .{ dst, lhs, rhs });
    }

    fn emitFdivReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.emitFmt(0x1e601800 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "fdiv d{d}, d{d}, d{d}", .{ dst, lhs, rhs });
    }

    fn emitFcvtzsX0FromD0(self: *Arm64Compiler) Error!void {
        try self.emit(0x9e780000, "fcvtzs x0, d0");
    }

    fn emitFmovReg(self: *Arm64Compiler, dst: u5, src: u5) Error!void {
        // FMOV <Dd>,<Dn> — ground-truth base 0x1E604000 (fmov d0,d2 => 0x1E604040).
        try self.emitFmt(0x1e604000 | (@as(u32, src) << 5) | @as(u32, dst), "fmov d{d}, d{d}", .{ dst, src });
    }

    fn emitFmovFromGpr(self: *Arm64Compiler, dreg: u5, xreg: u5) Error!void {
        // FMOV <Dd>,<Xn> — general-register to FP (64-bit). Ground-truth base
        // 0x9E670000 (fmov d0,x1 => 0x9E670020). Used to materialize an f64
        // literal: load its bit pattern into an x-reg, then transfer to d.
        try self.emitFmt(0x9e670000 | (@as(u32, xreg) << 5) | @as(u32, dreg), "fmov d{d}, x{d}", .{ dreg, xreg });
    }

    fn patchCalls(self: *Arm64Compiler) Error!void {
        for (self.call_patches.items) |patch| {
            if (self.definedSymbolOffset(patch.target)) |target_offset| {
                const diff = @as(i64, target_offset) - @as(i64, patch.offset);
                if (@mod(diff, 4) != 0) return error.BranchOutOfRange;
                const imm = @divTrunc(diff, 4);
                if (imm < -(1 << 25) or imm >= (1 << 25)) return error.BranchOutOfRange;
                const imm26: u32 = @intCast(@as(i32, @intCast(imm)) & 0x03ff_ffff);
                const word = 0x94000000 | imm26;
                std.mem.writeInt(u32, self.code.items[patch.offset..][0..4], word, .little);
                continue;
            }
            if (self.extern_symbols.get(patch.target)) |symbol_index| {
                try self.relocations.append(self.alloc, .{ .offset = patch.offset, .symbol_index = symbol_index });
                continue;
            }
            // A call target that is neither defined here nor registered extern
            // is an undefined symbol — DNB007. Reporting it as DNB001 claimed
            // the *program* was outside the subset, when lowering had in fact
            // fully succeeded and only relocation failed; that misdirects every
            // investigation to the wrong phase.
            // A well-known libc/libm name is not an undefined symbol, it is an
            // EXTERNAL one that nothing registered. `puts` and `llabs` reach
            // patchCalls as plain direct calls -- the emitter registers an
            // extern when it knows it is emitting one, and these arrive through
            // paths that do not -- so relocation failed on a symbol the linker
            // would have resolved without complaint. c_signatures already knows
            // the set; consulting it here turns three DNB007s into links.
            if (c_signatures.c_call_result_type(patch.target) != null) {
                try self.ensureExternalSymbol(patch.target);
                if (self.extern_symbols.get(patch.target)) |sym_index| {
                    try self.relocations.append(self.alloc, .{ .offset = patch.offset, .symbol_index = sym_index });
                    continue;
                }
            }
            // The symbol name was behind DUO_DNIR_TRACE, so the largest row in
            // the bail histogram (6 programs) said only "undefined symbol" and
            // named nothing. Every other refusal path reports unconditionally
            // now; this one has no reason to be different.
            refusal_site = @src();
            const n = @min(patch.target.len, refusal_note_buf.len);
            @memcpy(refusal_note_buf[0..n], patch.target[0..n]);
            refusal_note_len = n;
            return error.UnknownSymbol;
        }
    }

    fn patchB(self: *Arm64Compiler, offset: u32, target: u32) Error!void {
        const diff = @as(i64, target) - @as(i64, offset);
        if (@mod(diff, 4) != 0) return error.BranchOutOfRange;
        const imm = @divTrunc(diff, 4);
        if (imm < -(1 << 25) or imm >= (1 << 25)) return error.BranchOutOfRange;
        const imm26: u32 = @intCast(@as(i32, @intCast(imm)) & 0x03ff_ffff);
        std.mem.writeInt(u32, self.code.items[offset..][0..4], 0x14000000 | imm26, .little);
    }

    fn patchCondBranch(self: *Arm64Compiler, offset: u32, target: u32) Error!void {
        const diff = @as(i64, target) - @as(i64, offset);
        if (@mod(diff, 4) != 0) return error.BranchOutOfRange;
        const imm = @divTrunc(diff, 4);
        if (imm < -(1 << 18) or imm >= (1 << 18)) return error.BranchOutOfRange;
        const old = std.mem.readInt(u32, self.code.items[offset..][0..4], .little);
        const imm19: u32 = @intCast(@as(i32, @intCast(imm)) & 0x7ffff);
        std.mem.writeInt(u32, self.code.items[offset..][0..4], 0x54000000 | (imm19 << 5) | (old & 0xf), .little);
    }

    fn definedSymbolOffset(self: *const Arm64Compiler, name: []const u8) ?u32 {
        for (self.symbols.items) |sym| {
            if (sym.defined and std.mem.eql(u8, sym.name, name)) return sym.offset;
        }
        return null;
    }

    fn symbolOffset(self: *const Arm64Compiler, name: []const u8) ?u32 {
        for (self.symbols.items) |sym| {
            if (std.mem.eql(u8, sym.name, name)) return sym.offset;
        }
        return null;
    }
};

fn returnsInteger(t: ast.TypeExpr) bool {
    return isIntegerAnnotation(t);
}

fn isIntegerAnnotation(t: ast.TypeExpr) bool {
    return switch (t) {
        .named => |name| std.mem.eql(u8, name, "i32") or
            std.mem.eql(u8, name, "i64") or
            std.mem.eql(u8, name, "u32") or
            std.mem.eql(u8, name, "u64"),
        else => false,
    };
}

fn returnsVoid(t: ast.TypeExpr) bool {
    return switch (t) {
        .named => |name| std.mem.eql(u8, name, "void"),
        else => false,
    };
}

fn isComparison(op: ast.BinOp) bool {
    return switch (op) {
        .eq, .neq, .lt, .gt, .leq, .geq => true,
        else => false,
    };
}

fn dnirBinOpToAst(tag: dnir.BinOpTag) ast.BinOp {
    return switch (tag) {
        .add => .add,
        .sub => .sub,
        .mul => .mul,
        .div => .div,
        .mod => .mod,
        .eq => .eq,
        .neq => .neq,
        .lt => .lt,
        .gt => .gt,
        .leq => .leq,
        .geq => .geq,
        .band => .band,
        .bor => .bor,
        .bxor => .bxor,
        .shl => .lshift,
        .shr => .rshift,
    };
}

fn conditionForComparison(op: ast.BinOp) Condition {
    return switch (op) {
        .eq => .eq,
        .neq => .ne,
        .lt => .lt,
        .gt => .gt,
        .leq => .le,
        .geq => .ge,
        else => unreachable,
    };
}

fn invertCondition(cond: Condition) Condition {
    return switch (cond) {
        .eq => .ne,
        .ne => .eq,
        .lt => .ge,
        .ge => .lt,
        .gt => .le,
        .le => .gt,
    };
}

fn conditionForCset(cond: Condition) Condition {
    return invertCondition(cond);
}

/// `CSET Xd, cond` is an alias for `CSINC Xd, XZR, XZR, invert(cond)`.
///
/// Base encoding is `0x9A800400 | Rm<<16 | cond<<12 | Rn<<5 | Rd`; with
/// `Rm = Rn = XZR (31)` that is `0x9A9F07E0`. The condition field MUST start at
/// zero — a base with any cond bit pre-set silently ORs into the condition and
/// corrupts every condition whose encoding has that bit clear (`ge`, `eq`,
/// `gt`), which is why this is one function rather than a repeated literal.
fn encodeCset(dst: u5, cond: Condition) u32 {
    const CSINC_XZR_XZR: u32 = 0x9a9f07e0;
    return CSINC_XZR_XZR | (@as(u32, @intFromEnum(conditionForCset(cond))) << 12) | @as(u32, dst);
}

fn conditionName(cond: Condition) []const u8 {
    return switch (cond) {
        .eq => "eq",
        .ne => "ne",
        .lt => "lt",
        .ge => "ge",
        .gt => "gt",
        .le => "le",
    };
}

fn findTableFieldValue(fields: []const ast.TableField, name: []const u8) ?*const ast.Expr {
    for (fields) |fld| {
        switch (fld) {
            .named => |nf| {
                if (std.mem.eql(u8, nf.key, name)) return nf.val;
            },
            else => {},
        }
    }
    return null;
}

fn freeDnirModule(alloc: std.mem.Allocator, m: dnir.Module) void {
    for (m.records) |r| {
        alloc.free(r.name);
        for (r.fields) |f| alloc.free(f);
        alloc.free(r.fields);
        alloc.free(r.kinds);
    }
    alloc.free(m.records);
    for (m.functions) |f| {
        alloc.free(f.name);
        for (f.params) |p| {
            alloc.free(p.name);
            if (p.record) |rn| alloc.free(rn);
        }
        alloc.free(f.params);
        if (f.ret_record) |rn| alloc.free(rn);
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.callee.len > 0) alloc.free(ins.callee);
                if (ins.req_alias.len > 0) alloc.free(ins.req_alias);
                if (ins.field.len > 0) alloc.free(ins.field);
                if (ins.record.len > 0) alloc.free(ins.record);
                if (ins.vals.len > 0) alloc.free(ins.vals);
            }
            alloc.free(b.instrs);
        }
        alloc.free(f.blocks);
    }
    alloc.free(m.functions);
    for (m.externs) |e| {
        alloc.free(e.duo_name);
        alloc.free(e.symbol);
    }
    alloc.free(m.externs);
}

fn emitArm64FromDnir(alloc: std.mem.Allocator, m: dnir.Module, process_entry: ?[]const u8) Error!Arm64Output {
    var records = try collectF64RecordsFromDnir(alloc, m);
    defer freeF64Records(alloc, &records);
    var scal_records = try collectScalRecordsFromDnir(alloc, m);
    defer freeScalRecords(alloc, &scal_records);
    var req_ctx = native_req_support.Context{};
    var func_record_returns: FuncRecordReturns = .empty;
    defer freeFuncRecordReturns(alloc, &func_record_returns);
    var func_f64_record_returns: FuncF64RecordReturns = .empty;
    defer freeFuncF64RecordReturns(alloc, &func_f64_record_returns);
    for (m.functions) |f| {
        if (f.ret_record) |rn| {
            if (f64RecordDesc(&records, .{ .named = rn })) |rec| {
                const owned_fn = try alloc.dupe(u8, f.name);
                try func_f64_record_returns.put(alloc, owned_fn, rec);
            } else if (scalRecordDesc(&scal_records, .{ .named = rn })) |rec| {
                const owned_fn = try alloc.dupe(u8, f.name);
                try func_record_returns.put(alloc, owned_fn, rec);
            }
        }
    }
    var compiler = Arm64Compiler{
        .alloc = alloc,
        .f64_records = &records,
        .scal_records = &scal_records,
        .func_record_returns = &func_record_returns,
        .func_f64_record_returns = &func_f64_record_returns,
        .req_ctx = &req_ctx,
        .process_entry = process_entry,
    };
    defer compiler.deinit();
    try compiler.compileDnirModule(m);
    return compiler.finish();
}

fn collectScalRecordsFromDnir(alloc: std.mem.Allocator, m: dnir.Module) Error!ScalRecordMap {
    var map: ScalRecordMap = .empty;
    for (m.records) |r| {
        var has_f64 = false;
        for (r.kinds) |k| {
            if (k == .f64) {
                has_f64 = true;
                break;
            }
        }
        if (has_f64) continue;
        var kinds: std.ArrayListUnmanaged(ScalFieldKind) = .empty;
        errdefer kinds.deinit(alloc);
        var names: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer names.deinit(alloc);
        for (r.kinds, r.fields) |k, fname| {
            try kinds.append(alloc, if (k == .str) .str else .i64);
            try names.append(alloc, try alloc.dupe(u8, fname));
        }
        try map.put(alloc, try alloc.dupe(u8, r.name), .{
            .field_names = try names.toOwnedSlice(alloc),
            .field_kinds = try kinds.toOwnedSlice(alloc),
        });
    }
    return map;
}

fn collectF64RecordsFromDnir(alloc: std.mem.Allocator, m: dnir.Module) Error!F64RecordMap {
    var map: F64RecordMap = .empty;
    errdefer freeF64Records(alloc, &map);
    for (m.records) |r| {
        if (r.kinds.len == 0) continue;
        var all_f64 = true;
        for (r.kinds) |k| {
            if (k != .f64) {
                all_f64 = false;
                break;
            }
        }
        if (!all_f64) continue;
        var names: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer names.deinit(alloc);
        for (r.fields) |fname| try names.append(alloc, try alloc.dupe(u8, fname));
        try map.put(alloc, try alloc.dupe(u8, r.name), .{
            .field_names = try names.toOwnedSlice(alloc),
        });
    }
    return map;
}

fn emitArm64Module(alloc: std.mem.Allocator, mod: *const ast.Module, process_entry: ?[]const u8) Error!Arm64Output {
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = graph.liftModuleWithCalls(mod, "<native>") catch {};

    if (dnir_lower.lowerModuleWithGraph(alloc, mod, &graph)) |dnir_mod| {
        defer freeDnirModule(alloc, dnir_mod);
        if (dnir.moduleIsNativeDirectReady(dnir_mod)) {
            const regions = region_graph.buildModuleRegions(alloc, dnir_mod, &graph) catch null;
            if (regions) |rs| {
                defer region_graph.freeModuleRegions(alloc, rs);
                region_graph.validateModuleRegions(rs, &graph, dnir_mod, alloc) catch {
                    if (region_schedule.regionGateStrictEnabled()) {
                        return refuse(@src());
                    }
                };
                if (realization.buildDeferredFromGraph(alloc, &graph, "<native>")) |plan_val| {
                    var plan = plan_val;
                    defer plan.deinit(alloc);
                    realization.commitModuleForTarget(alloc, &plan, "native") catch {};
                    region_graph.attachRealizationPlan(alloc, rs, &plan) catch {};
                } else |_| {}
                var dnir_mut = dnir_mod;
                _ = region_transform.applyModuleRegionTransforms(alloc, &dnir_mut, rs) catch .{};
                if (region_schedule.buildModuleSchedules(alloc, rs)) |schedules| {
                    defer region_schedule.freeModuleSchedules(alloc, schedules);
                } else |_| {}
            }
            return emitArm64FromDnir(alloc, dnir_mod, process_entry);
        }
    } else |e| {
        // Without this the only trace a developer sees is the *AST fallback's*
        // failure, which is a different and usually less informative site. The
        // DNIR bail is the one that decides whether a program lowers natively.
        if (std.c.getenv("DUO_DNIR_TRACE") != null) {
            std.debug.print("DUO_DNIR_TRACE: DNIR lowering bailed with {s}; falling back to the AST path\n", .{@errorName(e)});
            if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
        }
    }

    var records = try collectF64Records(alloc, mod);
    defer freeF64Records(alloc, &records);
    var scal_records = try collectScalRecords(alloc, mod);
    defer freeScalRecords(alloc, &scal_records);
    var func_record_returns: FuncRecordReturns = .empty;
    defer freeFuncRecordReturns(alloc, &func_record_returns);
    var func_f64_record_returns: FuncF64RecordReturns = .empty;
    defer freeFuncF64RecordReturns(alloc, &func_f64_record_returns);
    var req_ctx = try native_req_support.collectFromModule(alloc, mod);
    defer req_ctx.deinit(alloc);
    const blobs = try collectByteBlobs(alloc, mod);
    defer freeByteBlobs(alloc, blobs);
    var native_mod = try collectFunctions(alloc, mod, &scal_records, &func_record_returns);
    defer native_mod.deinit(alloc);
    var compiler = Arm64Compiler{
        .alloc = alloc,
        .f64_records = &records,
        .scal_records = &scal_records,
        .func_record_returns = &func_record_returns,
        .func_f64_record_returns = &func_f64_record_returns,
        .req_ctx = &req_ctx,
        .process_entry = process_entry,
    };
    defer compiler.deinit();

    try compiler.compileModule(native_mod.functions, native_mod.externs, blobs);
    return compiler.finish();
}

fn emitMachOArm64Object(alloc: std.mem.Allocator, text: []const u8, cstring: []const u8, symbols: []const Symbol, relocations: []const Relocation, bss_size: u64) Error![]u8 {
    const header_size: usize = 32;
    const segment_size: usize = 72;
    const section_size: usize = 80;
    const symtab_size: usize = 24;
    const build_version_size: usize = 24;
    const has_cstring = cstring.len > 0;
    // `__DATA,__bss` is S_ZEROFILL: it has a VM size but NO file bytes, so it
    // adds one section header and leaves every file offset below untouched.
    // That is what makes a writable arena affordable here.
    const has_bss = bss_size > 0;
    const nsects: u32 = (if (has_cstring) @as(u32, 2) else 1) + (if (has_bss) @as(u32, 1) else 0);
    const sizeofcmds = segment_size + section_size * nsects + symtab_size + build_version_size;
    const text_offset: usize = header_size + sizeofcmds;
    const reloff: usize = text_offset + text.len;
    const after_relocs: usize = reloff + relocations.len * 8;
    const cstring_fileoff: usize = after_relocs;
    const symoff: usize = alignForward(if (has_cstring) cstring_fileoff + cstring.len else after_relocs, 8);
    const stroff: usize = symoff + symbols.len * 16;
    const strtab = try buildStringTable(alloc, symbols);
    defer alloc.free(strtab);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);

    // mach_header_64
    try appendU32(&out, alloc, 0xfeedfacf);
    try appendU32(&out, alloc, 0x0100000c); // CPU_TYPE_ARM64
    try appendU32(&out, alloc, 0); // CPU_SUBTYPE_ARM64_ALL
    try appendU32(&out, alloc, 1); // MH_OBJECT
    try appendU32(&out, alloc, 3);
    try appendU32(&out, alloc, @intCast(sizeofcmds));
    try appendU32(&out, alloc, 0);
    try appendU32(&out, alloc, 0);

    // LC_SEGMENT_64 (covers __text and, when present, __cstring).
    try appendU32(&out, alloc, 0x19);
    try appendU32(&out, alloc, @intCast(segment_size + section_size * nsects));
    try appendName16(&out, alloc, "");
    try appendU64(&out, alloc, 0); // vmaddr
    try appendU64(&out, alloc, text.len + cstring.len + bss_size); // vmsize (bss is zerofill: VM only)
    try appendU64(&out, alloc, text_offset); // fileoff
    try appendU64(&out, alloc, symoff - text_offset); // filesize: section data + their relocations
    try appendU32(&out, alloc, 7); // maxprot
    try appendU32(&out, alloc, 5); // initprot
    try appendU32(&out, alloc, nsects);
    try appendU32(&out, alloc, 0); // flags

    // section 1: __TEXT,__text
    try appendName16(&out, alloc, "__text");
    try appendName16(&out, alloc, "__TEXT");
    try appendU64(&out, alloc, 0); // addr
    try appendU64(&out, alloc, text.len); // size
    try appendU32(&out, alloc, @intCast(text_offset)); // offset
    try appendU32(&out, alloc, 2); // align (2^2 = 4)
    try appendU32(&out, alloc, @intCast(reloff));
    try appendU32(&out, alloc, @intCast(relocations.len));
    try appendU32(&out, alloc, 0x80000400); // S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS
    try appendU32(&out, alloc, 0);
    try appendU32(&out, alloc, 0);
    try appendU32(&out, alloc, 0);

    // section 2: __TEXT,__cstring (string literals)
    if (has_cstring) {
        try appendName16(&out, alloc, "__cstring");
        try appendName16(&out, alloc, "__TEXT");
        try appendU64(&out, alloc, text.len); // addr (immediately after __text in VM)
        try appendU64(&out, alloc, cstring.len); // size
        try appendU32(&out, alloc, @intCast(cstring_fileoff)); // offset
        try appendU32(&out, alloc, 0); // align (byte)
        try appendU32(&out, alloc, 0); // reloff
        try appendU32(&out, alloc, 0); // nreloc
        try appendU32(&out, alloc, 0x2); // S_CSTRING_LITERALS
        try appendU32(&out, alloc, 0);
        try appendU32(&out, alloc, 0);
        try appendU32(&out, alloc, 0);
    }

    // section 3: __DATA,__bss (zerofill arena — writable storage for string ops)
    if (has_bss) {
        try appendName16(&out, alloc, "__bss");
        try appendName16(&out, alloc, "__DATA");
        try appendU64(&out, alloc, text.len + cstring.len); // addr (after the __TEXT sections)
        try appendU64(&out, alloc, bss_size); // size
        try appendU32(&out, alloc, 0); // offset: zerofill occupies no file bytes
        try appendU32(&out, alloc, 3); // align (2^3 = 8)
        try appendU32(&out, alloc, 0); // reloff
        try appendU32(&out, alloc, 0); // nreloc
        try appendU32(&out, alloc, 0x1); // S_ZEROFILL
        try appendU32(&out, alloc, 0);
        try appendU32(&out, alloc, 0);
        try appendU32(&out, alloc, 0);
    }

    // LC_SYMTAB
    try appendU32(&out, alloc, 0x2);
    try appendU32(&out, alloc, @intCast(symtab_size));
    try appendU32(&out, alloc, @intCast(symoff));
    try appendU32(&out, alloc, @intCast(symbols.len));
    try appendU32(&out, alloc, @intCast(stroff));
    try appendU32(&out, alloc, @intCast(strtab.len));

    // LC_BUILD_VERSION: platform macOS, minos/sdk 11.0.0, no tool records.
    try appendU32(&out, alloc, 0x32);
    try appendU32(&out, alloc, @intCast(build_version_size));
    try appendU32(&out, alloc, 1);
    try appendU32(&out, alloc, 0x000b0000);
    try appendU32(&out, alloc, 0x000b0000);
    try appendU32(&out, alloc, 0);

    try out.appendSlice(alloc, text);
    for (relocations) |reloc| {
        const flags: u32 = switch (reloc.kind) {
            .branch26 => reloc.symbol_index | (1 << 24) | (2 << 25) | (1 << 27) | (2 << 28), // pcrel, BR26
            .page21 => reloc.symbol_index | (1 << 24) | (2 << 25) | (1 << 27) | (3 << 28), // pcrel, PAGE21
            .pageoff12 => reloc.symbol_index | (0 << 24) | (2 << 25) | (1 << 27) | (4 << 28), // PAGEOFF12
        };
        try appendU32(&out, alloc, reloc.offset);
        try appendU32(&out, alloc, flags);
    }
    if (has_cstring) {
        try out.appendSlice(alloc, cstring);
    }
    if (symoff > out.items.len) try appendZeroes(&out, alloc, symoff - out.items.len);

    var strx: u32 = 1;
    for (symbols) |sym| {
        try appendU32(&out, alloc, strx);
        const add_underscore = !(sym.defined and !sym.external);
        if (!sym.defined) {
            try out.append(alloc, 0x01); // N_EXT | N_UNDF
            try out.append(alloc, 0); // n_sect = NO_SECT
        } else if (!sym.external) {
            try out.append(alloc, 0x0e); // N_SECT (local section symbol)
            try out.append(alloc, sym.section);
        } else {
            try out.append(alloc, 0x0f); // N_EXT | N_SECT
            try out.append(alloc, sym.section);
        }
        try appendU16(&out, alloc, 0);
        try appendU64(&out, alloc, sym.offset);
        strx += @intCast(sym.name.len + 1 + (@as(u32, if (add_underscore) 1 else 0)));
    }

    try out.appendSlice(alloc, strtab);
    return out.toOwnedSlice(alloc);
}

fn buildStringTable(alloc: std.mem.Allocator, symbols: []const Symbol) Error![]u8 {
    var table: std.ArrayList(u8) = .empty;
    errdefer table.deinit(alloc);
    try table.append(alloc, 0);
    for (symbols) |sym| {
        // Local string-literal labels are stored without the C-symbol underscore;
        // external/undefined symbols keep the leading underscore by convention.
        if (!(sym.defined and !sym.external)) try table.append(alloc, '_');
        try table.appendSlice(alloc, sym.name);
        try table.append(alloc, 0);
    }
    return table.toOwnedSlice(alloc);
}

fn relocDescByOffset(_: void, a: Relocation, b: Relocation) bool {
    // Mach-O object relocation entries are sorted by descending r_address.
    return a.offset > b.offset;
}

fn appendName16(out: *std.ArrayList(u8), alloc: std.mem.Allocator, name: []const u8) !void {
    var buf: [16]u8 = @splat(0);
    @memcpy(buf[0..@min(name.len, buf.len)], name[0..@min(name.len, buf.len)]);
    try out.appendSlice(alloc, &buf);
}

fn appendZeroes(out: *std.ArrayList(u8), alloc: std.mem.Allocator, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) try out.append(alloc, 0);
}

fn appendU16(out: *std.ArrayList(u8), alloc: std.mem.Allocator, value: u16) !void {
    var buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &buf, value, .little);
    try out.appendSlice(alloc, &buf);
}

fn appendU32(out: *std.ArrayList(u8), alloc: std.mem.Allocator, value: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .little);
    try out.appendSlice(alloc, &buf);
}

fn appendU64(out: *std.ArrayList(u8), alloc: std.mem.Allocator, value: u64) !void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, value, .little);
    try out.appendSlice(alloc, &buf);
}

fn alignForward(value: usize, alignment: usize) usize {
    return (value + alignment - 1) & ~(alignment - 1);
}

test "native backend lowers Pass 4 milestone with f64 return in d0 (no main exit hack)" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): f64
        \\    distance2({ x = 3.0, y = 4.0 })
        \\end
    , "pass4_native_milestone.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);

    const listing = try emitAssembly(alloc, &mod, "native-asm");
    defer alloc.free(listing);
    try std.testing.expect(std.mem.indexOf(u8, listing, "_main") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "fcvtzs x0, d0") == null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "_distance2") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "fmov d2, d0") == null);
    const main_pos = std.mem.indexOf(u8, listing, "_main:") orelse return error.TestExpectedEqual;
    const bl_off = std.mem.indexOf(u8, listing[main_pos..], "bl _distance2") orelse return error.TestExpectedEqual;
    const after_bl = listing[main_pos + bl_off ..];
    try std.testing.expect(std.mem.indexOf(u8, after_bl, "fmov d") == null);

    const obj = try emitObject(alloc, &mod, "native-object");
    try std.testing.expect(obj.len > 0);
}

test "native backend: no mandatory main — run() entry compiles" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\run(): i64
        \\    42
        \\end
    , "run.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();

    const listing = try emitAssembly(alloc, &mod, "native-asm");
    defer alloc.free(listing);
    try std.testing.expect(std.mem.indexOf(u8, listing, "_run") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "_main") == null);
}

test "native backend: pickNativeEntrySymbol prefers export then sole zero-arg" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\@export
        \\fun entry(): i64
        \\    1
        \\end
        \\other(): i64
        \\    2
        \\end
    , "entry.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    try std.testing.expectEqualStrings("entry", pickNativeEntrySymbol(&mod).?);

    var lex2 = Lexer.init(
        \\run(): i64
        \\    42
        \\end
    , "sole.duo");
    var parser2 = Parser.init(&lex2, alloc);
    parser2.duo_mode = true;
    const mod2 = try parser2.parse_module();
    try std.testing.expectEqualStrings("run", pickNativeEntrySymbol(&mod2).?);

    var lex3 = Lexer.init(
        \\a(): i64
        \\    1
        \\end
        \\b(): i64
        \\    2
        \\end
    , "ambiguous.duo");
    var parser3 = Parser.init(&lex3, alloc);
    parser3.duo_mode = true;
    const mod3 = try parser3.parse_module();
    try std.testing.expect(pickNativeEntrySymbol(&mod3) == null);

    var lex4 = Lexer.init(
        \\a(): i64
        \\    1
        \\end
        \\b(): i64
        \\    2
        \\end
    , "override.duo");
    var parser4 = Parser.init(&lex4, alloc);
    parser4.duo_mode = true;
    const mod4 = try parser4.parse_module();
    try std.testing.expectEqualStrings("b", resolveNativeEntrySymbol(&mod4, "b").?);
    try std.testing.expect(resolveNativeEntrySymbol(&mod4, "missing") == null);

    var lex5 = Lexer.init(
        \\run(): f64
        \\    42.0
        \\end
    , "f64_entry.duo");
    var parser5 = Parser.init(&lex5, alloc);
    parser5.duo_mode = true;
    const mod5 = try parser5.parse_module();
    try std.testing.expectEqualStrings("run", pickNativeEntrySymbol(&mod5).?);
}

// The sole-zero-arg-function rule is an inference. When the module has a
// file-scope BODY, that body is the program, and promoting a helper to the
// process entry silently deletes it — `print("before"); print(w())` produced no
// output at all and exited 42. This is the regression test for that: same sole
// function, with and without a body.
test "native backend: sole-zero-arg entry is refused when a file-scope body exists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // No file-scope body: the inference is sound, and still applies.
    var lex_lib = Lexer.init(
        \\w(): i64
        \\    42
        \\end
    , "libshaped.duo");
    var parser_lib = Parser.init(&lex_lib, alloc);
    parser_lib.duo_mode = true;
    const mod_lib = try parser_lib.parse_module();
    try std.testing.expectEqualStrings("w", pickNativeEntrySymbol(&mod_lib).?);

    // Same sole function, but the file-scope statements ARE the program.
    var lex_script = Lexer.init(
        \\w(): i64
        \\    42
        \\end
        \\print("before")
        \\print(w())
    , "script.duo");
    var parser_script = Parser.init(&lex_script, alloc);
    parser_script.duo_mode = true;
    const mod_script = try parser_script.parse_module();
    try std.testing.expect(pickNativeEntrySymbol(&mod_script) == null);

    // A DECLARED entry still wins over the body — `main` is deliberate.
    var lex_main = Lexer.init(
        \\main(): i64
        \\    0
        \\end
        \\print("side effect")
    , "declared_main.duo");
    var parser_main = Parser.init(&lex_main, alloc);
    parser_main.duo_mode = true;
    const mod_main = try parser_main.parse_module();
    try std.testing.expectEqualStrings("main", pickNativeEntrySymbol(&mod_main).?);

    // As does an explicit --entry override.
    try std.testing.expectEqualStrings("w", resolveNativeEntrySymbol(&mod_script, "w").?);
}

test "native backend: f64 process entry coerces d0 to x0 exit code" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\run(): f64
        \\    42.0
        \\end
    , "f64_run.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);

    const listing = try emitAssemblyForExecutable(alloc, &mod, "run");
    defer alloc.free(listing);
    try std.testing.expect(std.mem.indexOf(u8, listing, "fcvtzs x0, d0") != null);

    const plain = try emitAssembly(alloc, &mod, "native-asm");
    defer alloc.free(plain);
    try std.testing.expect(std.mem.indexOf(u8, plain, "fcvtzs x0, d0") == null);
}

test "native backend lowers sealed f64 record distance2 kernel" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\Point: @{ x: f64, y: f64 }
        \\distance2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    0
        \\end
    , "pass4_native_milestone.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);

    const obj = try emitObject(alloc, &mod, "native-object");
    try std.testing.expect(obj.len > 0);
    const listing = try emitAssembly(alloc, &mod, "native-asm");
    defer alloc.free(listing);
    try std.testing.expect(std.mem.indexOf(u8, listing, "_distance2") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "fmul") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "fadd") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "lua_") == null);
}

test "native backend emits arm64 Mach-O object for constant main" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\main(): i64
        \\    40 + 2
        \\end
    , "native.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    try sem.check_module(&mod);

    const obj = try emitObject(alloc, &mod, "native-object");
    try std.testing.expect(obj.len > 0);
    try std.testing.expectEqual(@as(u32, 0xfeedfacf), std.mem.readInt(u32, obj[0..4], .little));
    try std.testing.expect(std.mem.indexOf(u8, obj, "_main") != null);
    try std.testing.expect(std.mem.indexOf(u8, obj, "\xc0\x03\x5f\xd6") != null);
}

test "Pass 11 WP-04: length2 record local + and-or ternary exits 0 on direct backend" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source =
        \\Point: @{ x: f64, y: f64 }
        \\length2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    p = { x = 3.0, y = 4.0 }
        \\    length2(p) == 25 and 0 or 1
        \\end
    ;
    var lex = Lexer.init(source, "pass11_record_proof.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);

    const obj = try emitObject(alloc, &mod, "native-object");
    defer alloc.free(obj);
    try std.testing.expect(obj.len > 0);
    try std.testing.expectEqual(@as(u32, 0xfeedfacf), std.mem.readInt(u32, obj[0..4], .little));

    const listing = try emitAssembly(alloc, &mod, "native-asm");
    defer alloc.free(listing);
    try std.testing.expect(std.mem.indexOf(u8, listing, "_length2") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "fmul") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "lua_") == null);
}

test "native backend target classification includes executable target" {
    try std.testing.expect(isNativeMachineTarget("native-exe"));
    try std.testing.expect(isNativeExecutableTarget("native-exe"));
    try std.testing.expect(!isNativeObjectTarget("native-exe"));
    try std.testing.expect(!isNativeAsmTarget("native-exe"));
    try std.testing.expect(isNativeMachineTarget("native-dylib"));
    try std.testing.expect(isNativeSharedTarget("native-dylib"));
    try std.testing.expect(!isNativeObjectTarget("native-dylib"));
    try std.testing.expect(!isNativeExecutableTarget("native-dylib"));
}

test "native backend lowers locals and integer arithmetic" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\main(): i64
        \\    x = 10
        \\    y = 4
        \\    x = x + y * 8
        \\    x - 1
        \\end
    , "native.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    try sem.check_module(&mod);

    const obj = try emitObject(alloc, &mod, "native-object");
    try std.testing.expect(obj.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, obj, "_main") != null);
    try std.testing.expect(std.mem.indexOf(u8, obj, "\xc0\x03\x5f\xd6") != null);
}

test "native backend lowers direct calls and emits multiple symbols" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\add(a: i64, b: i64): i64
        \\    a + b
        \\end
        \\
        \\main(): i64
        \\    x = add(20, 22)
        \\    x
        \\end
    , "native.duo");
    var parser = Parser.init(&lex, alloc);
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    try sem.check_module(&mod);

    const obj = try emitObject(alloc, &mod, "native-object");
    try std.testing.expect(std.mem.indexOf(u8, obj, "_add") != null);
    try std.testing.expect(std.mem.indexOf(u8, obj, "_main") != null);
}

test "native backend lowers qualified multi-arg call with mov_arg ABI slots" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\math.add = (a: i64, b: i64): i64
        \\    a + b
        \\end
        \\main(): i64
        \\    math.add(10, 20)
        \\end
    , "math_add_multi.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);

    const listing = try emitAssembly(alloc, &mod, "native-asm");
    defer alloc.free(listing);
    try std.testing.expect(std.mem.indexOf(u8, listing, "_math_add") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "bl _math_add") != null);

    const main_pos = std.mem.indexOf(u8, listing, "_main:") orelse return error.TestExpectedEqual;
    const bl_off = std.mem.indexOf(u8, listing[main_pos..], "bl _math_add") orelse return error.TestExpectedEqual;
    const before_bl = listing[main_pos .. main_pos + bl_off];
    try std.testing.expect(std.mem.indexOf(u8, before_bl, "mov x0") != null);
    try std.testing.expect(std.mem.indexOf(u8, before_bl, "mov x1") != null);

    const obj = try emitObject(alloc, &mod, "native-object");
    try std.testing.expect(std.mem.indexOf(u8, obj, "_math_add") != null);
    try std.testing.expect(obj.len > 0);
}

test "native backend passes a variadic tail argument on the stack, not in x3" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\main(): i64
        \\    s = to(str)(42)
        \\    return #s
        \\end
    , "to_str_vararg.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);

    const listing = try emitAssembly(alloc, &mod, "native-asm");
    defer alloc.free(listing);

    const main_pos = std.mem.indexOf(u8, listing, "_main:") orelse return error.TestExpectedEqual;
    const bl_off = std.mem.indexOf(u8, listing[main_pos..], "bl _snprintf") orelse return error.TestExpectedEqual;
    const staging = listing[main_pos .. main_pos + bl_off];

    // The three NAMED parameters travel in registers, as AAPCS64 says.
    try std.testing.expect(std.mem.indexOf(u8, staging, "mov x0,") != null);
    try std.testing.expect(std.mem.indexOf(u8, staging, "mov x1,") != null);
    try std.testing.expect(std.mem.indexOf(u8, staging, "mov x2,") != null);

    // The tail argument does NOT. Apple's ARM64 ABI reads it from memory at
    // sp, so a fourth register argument is silently ignored: `snprintf(buf,
    // 24, "%lld", n)` staged into x3 assembles correctly and prints a POINTER.
    try std.testing.expect(std.mem.indexOf(u8, staging, "mov x3,") == null);

    // Immediately before the branch: reserve the memory-argument area and
    // write the tail into its first slot.
    const tail = staging[staging.len - 40 ..];
    try std.testing.expect(std.mem.indexOf(u8, tail, "sub sp, sp, #16") != null);
    try std.testing.expect(std.mem.indexOf(u8, tail, ", [sp, #0]") != null);
}

test "native backend lowers if elseif else branches" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\pick(n: i64): i64
        \\    out = 0
        \\    if n < 0
        \\        out = 11
        \\    elseif n == 0
        \\        out = 13
        \\    elseif n > 10
        \\        out = 17
        \\    else
        \\        out = 19
        \\    end
        \\    out
        \\end
        \\
        \\main(): i64
        \\    pick(11)
        \\end
    , "native.duo");
    var parser = Parser.init(&lex, alloc);
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    try sem.check_module(&mod);

    const asm_text = try emitAssembly(alloc, &mod, "native-asm");
    defer alloc.free(asm_text);
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "\tcmp x") != null);
    var cmp_count: usize = 0;
    var branch_count: usize = 0;
    var lines = std.mem.splitScalar(u8, asm_text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "\tcmp x")) cmp_count += 1;
        if (std.mem.startsWith(u8, line, "\tb.") and std.mem.indexOf(u8, line, ".Lduo_") != null) branch_count += 1;
    }
    try std.testing.expect(cmp_count >= 3);
    try std.testing.expect(branch_count >= 3);

    const obj = try emitObject(alloc, &mod, "native-object");
    try std.testing.expect(std.mem.indexOf(u8, obj, "_pick") != null);
}

test "native backend lowers while break and continue" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\sum_to(n: i64): i64
        \\    total = 0
        \\    i = 0
        \\    while i < n
        \\        i = i + 1
        \\        if i == 3
        \\            continue
        \\        end
        \\        if i > 5
        \\            break
        \\        end
        \\        total = total + i
        \\    end
        \\    total
        \\end
        \\
        \\main(): i64
        \\    sum_to(8)
        \\end
    , "native.duo");
    var parser = Parser.init(&lex, alloc);
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    try sem.check_module(&mod);

    const asm_text = try emitAssembly(alloc, &mod, "native-asm");
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "\tb.ge .Lduo_") != null);
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "\tb .Lduo_") != null);

    const obj = try emitObject(alloc, &mod, "native-object");
    try std.testing.expect(std.mem.indexOf(u8, obj, "_sum_to") != null);
}

test "native backend lowers numeric for loops" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\counted(n: i64): i64
        \\    total = 0
        \\    for i = 1, n
        \\        if i == 3
        \\            continue
        \\        end
        \\        total = total + i
        \\    end
        \\    for j = n, 1, -2
        \\        if j < 2
        \\            break
        \\        end
        \\        total = total + j
        \\    end
        \\    total
        \\end
        \\
        \\main(): i64
        \\    counted(5)
        \\end
    , "native.duo");
    var parser = Parser.init(&lex, alloc);
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    try sem.check_module(&mod);

    const asm_text = try emitAssembly(alloc, &mod, "native-asm");
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "\tb.lt .Lduo_") != null);
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "\tb.gt .Lduo_") != null);
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "_counted:") != null);

    const obj = try emitObject(alloc, &mod, "native-object");
    try std.testing.expect(std.mem.indexOf(u8, obj, "_counted") != null);
}

test "native backend emits external call relocation" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\@ffi("llabs")
        \\fun llabs(n: i64): i64
        \\
        \\main(): i64
        \\    x = llabs(-37)
        \\    x + 5
        \\end
    , "native.duo");
    var parser = Parser.init(&lex, alloc);
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    try sem.check_module(&mod);

    const obj = try emitObject(alloc, &mod, "native-object");
    try std.testing.expect(std.mem.indexOf(u8, obj, "_llabs") != null);

    const output = try emitArm64Module(alloc, &mod, null);
    defer {
        alloc.free(output.text);
        alloc.free(output.asm_text);
        for (output.symbols) |sym| alloc.free(sym.name);
        alloc.free(output.symbols);
        alloc.free(output.relocations);
    }
    try std.testing.expectEqual(@as(usize, 1), output.relocations.len);
    try std.testing.expectEqualStrings("llabs", output.symbols[output.relocations[0].symbol_index].name);
    try std.testing.expect(!output.symbols[output.relocations[0].symbol_index].defined);
}

test "native backend lowers string literals to cstring with adrp/add relocations" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\@ffi("puts")
        \\fun puts(s: str): i64
        \\
        \\main(): i64
        \\    puts("Hello")
        \\    0
        \\end
    , "native.duo");
    var parser = Parser.init(&lex, alloc);
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    try sem.check_module(&mod);

    const obj = try emitObject(alloc, &mod, "native-object");
    // A __cstring section appears alongside __text when a string literal is present.
    try std.testing.expect(std.mem.indexOf(u8, obj, "__cstring") != null);
    try std.testing.expect(std.mem.indexOf(u8, obj, "_puts") != null);

    const output = try emitArm64Module(alloc, &mod, null);
    defer {
        alloc.free(output.text);
        alloc.free(output.asm_text);
        if (output.cstring.len > 0) alloc.free(output.cstring);
        for (output.symbols) |sym| alloc.free(sym.name);
        alloc.free(output.symbols);
        alloc.free(output.relocations);
    }
    // Interned literal materializes in the cstring section.
    try std.testing.expect(output.cstring.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output.cstring, "Hello") != null);

    // Three relocations: one branch26 to puts, plus a page21/pageoff12 pair to the string label.
    try std.testing.expectEqual(@as(usize, 3), output.relocations.len);
    var saw_branch_puts = false;
    var saw_page21 = false;
    var saw_pageoff12 = false;
    for (output.relocations) |reloc| {
        const sym = output.symbols[reloc.symbol_index];
        switch (reloc.kind) {
            .branch26 => {
                try std.testing.expectEqualStrings("puts", sym.name);
                try std.testing.expect(!sym.defined);
                saw_branch_puts = true;
            },
            .page21 => {
                try std.testing.expect(sym.defined and !sym.external and sym.section == 2);
                saw_page21 = true;
            },
            .pageoff12 => {
                try std.testing.expect(sym.defined and !sym.external and sym.section == 2);
                saw_pageoff12 = true;
            },
        }
    }
    try std.testing.expect(saw_branch_puts);
    try std.testing.expect(saw_page21);
    try std.testing.expect(saw_pageoff12);

    // The string section symbol's n_value is the absolute VM address (text.len + cstring offset),
    // never a bare cstring-relative offset — clang's linker rejects the latter.
    const text_len: u32 = @intCast(output.text.len);
    for (output.symbols) |sym| {
        if (sym.defined and !sym.external and sym.section == 2) {
            try std.testing.expect(sym.offset >= text_len);
        }
    }
}

test "native backend emits shared object input for exported function without main" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\@export
        \\fun duo_native_add(a: i64, b: i64): i64
        \\    a + b
        \\end
    , "native.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    try sem.check_module(&mod);

    const obj = try emitSharedObjectInput(alloc, &mod);
    try std.testing.expect(std.mem.indexOf(u8, obj, "_duo_native_add") != null);
    try std.testing.expect(std.mem.indexOf(u8, obj, "_main") == null);
}

test "native backend reuses expression registers and narrows call saves" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\id(n: i64): i64
        \\    n
        \\end
        \\
        \\main(): i64
        \\    a = 1
        \\    b = a
        \\    a = 9
        \\    x = (((((((((((((((((((1 + 2) + 3) + 4) + 5) + 6) + 7) + 8) + 9) + 10) + 11) + 12) + 13) + 14) + 15) + 16) + 17) + 18) + 19) + 20)
        \\    y = id(x)
        \\    y + b
        \\end
    , "native.duo");
    var parser = Parser.init(&lex, alloc);
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    try sem.check_module(&mod);

    const asm_text = try emitAssembly(alloc, &mod, "native-asm");
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "\tsub sp, sp, #176\n") == null);
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "\tstr x30, [sp, #") != null);

    const obj = try emitObject(alloc, &mod, "native-object");
    try std.testing.expect(std.mem.indexOf(u8, obj, "_id") != null);
}

// The asm listing prints the *intended* mnemonic while the object file carries
// the *encoded* bits, so a wrong encoding is invisible to any text assertion.
// Decode the condition field back out and check it against the CSET alias rule.
test "native backend: cset encodes the inverted condition in bits 15:12" {
    const cases = [_]struct { cond: Condition, want: Condition }{
        .{ .cond = .eq, .want = .ne },
        .{ .cond = .ne, .want = .eq },
        .{ .cond = .lt, .want = .ge },
        .{ .cond = .ge, .want = .lt },
        .{ .cond = .gt, .want = .le },
        .{ .cond = .le, .want = .gt },
    };
    for (cases) |c| {
        const word = encodeCset(10, c.cond);
        const field: u4 = @truncate(word >> 12);
        try std.testing.expectEqual(@intFromEnum(c.want), field);
        // Rd, Rn=XZR, Rm=XZR and the CSINC op bits must survive untouched.
        try std.testing.expectEqual(@as(u32, 10), word & 0x1f);
        try std.testing.expectEqual(@as(u32, 0x1f), (word >> 5) & 0x1f);
        try std.testing.expectEqual(@as(u32, 0x1f), (word >> 16) & 0x1f);
        try std.testing.expectEqual(@as(u32, 0b01), (word >> 10) & 0b11);
    }
}

// `cset` writes a GPR but leaves NZCV untouched. A conditional branch that
// immediately follows one is therefore testing whatever flags the *previous*
// `cmp` left behind, not the boolean `cset` just produced — so every
// `if <comparison>` silently degenerates into `if (lhs == rhs)`.
//
// The existing branch tests only count `cmp`/`b.` occurrences, which this bug
// satisfies perfectly. Assert the flag-dependency invariant instead.
test "native backend: conditional branch never consumes stale flags after cset" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\f(n: i64): i64
        \\    if n < 0
        \\        return 111
        \\    end
        \\    return 222
        \\end
        \\
        \\main(): i64
        \\    f(7)
        \\end
    , "native.duo");
    var parser = Parser.init(&lex, alloc);
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    try sem.check_module(&mod);

    const asm_text = try emitAssembly(alloc, &mod, "native-asm");
    defer alloc.free(asm_text);

    var prev_was_cset = false;
    var lines = std.mem.splitScalar(u8, asm_text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or std.mem.endsWith(u8, line, ":")) continue;
        if (prev_was_cset and std.mem.startsWith(u8, line, "b.")) {
            std.debug.print(
                "\nflag-clobber bug: conditional branch '{s}' follows a cset with no intervening cmp\n{s}\n",
                .{ line, asm_text },
            );
            return error.TestUnexpectedResult;
        }
        prev_was_cset = std.mem.startsWith(u8, line, "cset ");
    }
}

test "native backend emits assembly listing for arithmetic" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // The fixture used to be `x = 6; y = 7; x * y` inside `main`, and asserted a
    // `mul` in the listing. Both operands are compile-time constants, so the
    // backend folds the product to `mov x9, #42` and there is no `mul` to find —
    // the assertion was requiring a de-optimization. Multiplying two PARAMETERS
    // is arithmetic nothing can fold, which is what this test means to pin.
    // Verified by value: the same program run through `--emit exe` exits 42.
    var lex = Lexer.init(
        \\prod(a: i64, b: i64): i64
        \\    a * b
        \\end
        \\main(): i64
        \\    prod(6, 7)
        \\end
    , "native.duo");
    var parser = Parser.init(&lex, alloc);
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    try sem.check_module(&mod);

    const asm_text = try emitAssembly(alloc, &mod, "native-asm");
    try std.testing.expect(std.mem.indexOf(u8, asm_text, ".globl _main") != null);
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "mul x") != null);
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "\tret\n") != null);
}

test "native backend assembly lists helper call labels" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\add(a: i64, b: i64): i64
        \\    a + b
        \\end
        \\
        \\main(): i64
        \\    add(1, 2)
        \\end
    , "native.duo");
    var parser = Parser.init(&lex, alloc);
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    try sem.check_module(&mod);

    const asm_text = try emitAssembly(alloc, &mod, "native-asm");
    try std.testing.expect(std.mem.indexOf(u8, asm_text, ".globl _add") != null);
    try std.testing.expect(std.mem.indexOf(u8, asm_text, ".globl _main") != null);
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "\tbl _add\n") != null);
}

test "native backend lowers sovereign print (no DNB007 fallback)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\main(): i64
        \\    print(1)
        \\    0
        \\end
    , "native.duo");
    var parser = Parser.init(&lex, alloc);
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    try sem.check_module(&mod);

    // `print` is sovereign native output now: the direct backend lowers it to
    // Mach-O `_printf`/`_puts` externs instead of rejecting with DNB007
    // ("undefined symbol"). Emitting the object proves the DNIR path fires.
    const obj = try emitObject(alloc, &mod, "native-object");
    try std.testing.expect(obj.len > 0);
}

test "native backend Pass 11 sealed record proof (integer main + f64 kernel)" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\Point: @{ x: f64, y: f64 }
        \\length2(p: Point): f64
        \\    p.x * p.x + p.y * p.y
        \\end
        \\main(): i64
        \\    if length2({ x = 3.0, y = 4.0 }) == 25.0
        \\        return 0
        \\    else
        \\        return 1
        \\    end
        \\end
    , "pass11_record_proof.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);

    const listing = try emitAssembly(alloc, &mod, "native-asm");
    defer alloc.free(listing);
    try std.testing.expect(std.mem.indexOf(u8, listing, "_length2") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "fmul") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "fcmp") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "lua_") == null);

    const obj = try emitObject(alloc, &mod, "native-object");
    try std.testing.expect(obj.len > 0);
}

test "Pass 11 WP-05: byte blob + load_u8 intrinsic on direct backend" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source =
        \\wasm_header = { 0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00 }
        \\read_u8_at(base: i64, off: i64): i64
        \\    __native_load_u8(base, off)
        \\end
        \\main(): i64
        \\    base = wasm_header
        \\    b0 = read_u8_at(base, 0)
        \\    b3 = read_u8_at(base, 3)
        \\    if b0 ~= 0 return 1001 end
        \\    if b3 ~= 0x6D return 1004 end
        \\    0
        \\end
    ;
    var lex = Lexer.init(source, "pass11_wasm_blob_direct.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);

    const listing = try emitAssembly(alloc, &mod, "native-asm");
    defer alloc.free(listing);
    try std.testing.expect(std.mem.indexOf(u8, listing, "Lduo_blob_wasm_header") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "ldrb") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "lua_") == null);

    const obj = try emitObject(alloc, &mod, "native-object");
    try std.testing.expect(obj.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, obj, "\x00asm") != null);
}

test "Pass 11 WP-04: i64 record field assign with binop" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source =
        \\main(): i64
        \\    c = { data = 0, pos = 0, len = 8 }
        \\    c.pos = c.pos + 1
        \\    c.pos
        \\end
    ;
    var lex = Lexer.init(source, "field_assign.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);

    const obj = try emitObject(alloc, &mod, "native-object");
    defer alloc.free(obj);
    try std.testing.expect(obj.len > 0);
}

test "Pass 11 WP-05: if-return then i64 field assign" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source =
        \\wasm_header = { 0x00, 0x61, 0x73, 0x6D }
        \\read_u8_at(base: i64, off: i64): i64
        \\    __native_load_u8(base, off)
        \\end
        \\main(): i64
        \\    c = { data = wasm_header, pos = 0, len = 8 }
        \\    b0 = read_u8_at(c.data, 0)
        \\    if b0 ~= 0 return 1001 end
        \\    c.pos = c.pos + 1
        \\    if c.pos ~= 1 return 1006 end
        \\    0
        \\end
    ;
    var lex = Lexer.init(source, "pass11_wasm_blob_direct.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);

    const obj = try emitObject(alloc, &mod, "native-object");
    defer alloc.free(obj);
    try std.testing.expect(obj.len > 0);
}

test "Pass 11 WP-03: register spills with >20 live locals" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source =
        \\main(): i64
        \\    v0 = 1
        \\    v1 = 1
        \\    v2 = 1
        \\    v3 = 1
        \\    v4 = 1
        \\    v5 = 1
        \\    v6 = 1
        \\    v7 = 1
        \\    v8 = 1
        \\    v9 = 1
        \\    v10 = 1
        \\    v11 = 1
        \\    v12 = 1
        \\    v13 = 1
        \\    v14 = 1
        \\    v15 = 1
        \\    v16 = 1
        \\    v17 = 1
        \\    v18 = 1
        \\    v19 = 1
        \\    v20 = 1
        \\    v21 = 1
        \\    v0 + v21
        \\end
    ;
    var lex = Lexer.init(source, "pass11_spill_proof.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);

    const listing = try emitAssembly(alloc, &mod, "native-asm");
    defer alloc.free(listing);
    try std.testing.expect(std.mem.indexOf(u8, listing, "\tstr x") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "\tldr x") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "lua_") == null);

    const obj = try emitObject(alloc, &mod, "native-object");
    defer alloc.free(obj);
    try std.testing.expect(obj.len > 0);
}

test "record return wider than x0..x7 uses the AAPCS64 x8 indirect result" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Nine i64 fields: one more than the argument register file, so the record
    // cannot be exploded and the caller must hand over a buffer address.
    // Verified by VALUE, not only by shape: the same program built with
    // `--emit exe` reads all nine fields back (11,22,…,99) and agrees with
    // `--backend=c` field for field.
    const source =
        \\big: @{ a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64, i: i64 }
        \\mk(): big
        \\    return { a = 11, b = 22, c = 33, d = 44, e = 55, f = 66, g = 77, h = 88, i = 99 }
        \\end
        \\main(): i64
        \\    v = mk()
        \\    return v.a + v.i
        \\end
    ;
    var lex = Lexer.init(source, "indirect_ret.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);

    const listing = try emitAssembly(alloc, &mod, "native-asm");
    defer alloc.free(listing);

    // Caller: reserve the buffer and point x8 at it BEFORE the branch.
    const x8_setup = std.mem.indexOf(u8, listing, "add x8, sp,") orelse
        return error.MissingIndirectResultPointer;
    const call_site = std.mem.indexOf(u8, listing, "\tbl _mk\n") orelse
        return error.MissingCall;
    try std.testing.expect(x8_setup < call_site);

    // Callee: park x8 while it is still live, then write through the parked
    // copy. `mov x9, x8` is the parking move; the last field lands at +64.
    try std.testing.expect(std.mem.indexOf(u8, listing, ", x8\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, ", #64]\n") != null);

    // And it is genuinely indirect: nothing is returned in the argument file.
    const mk_start = std.mem.indexOf(u8, listing, "_mk:\n") orelse return error.MissingCallee;
    const mk_body = listing[mk_start..call_site];
    try std.testing.expect(std.mem.indexOf(u8, mk_body, "mov x0,") == null);

    const obj = try emitObject(alloc, &mod, "native-object");
    defer alloc.free(obj);
    try std.testing.expect(obj.len > 0);
}

test "an eight-field record return still explodes into x0..x7" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // The no-regression control for the register path, and the case that was
    // silently WRONG: `ret_record` carried three values in lhs/rhs/third and
    // stopped, while the caller copied x0..x7 out regardless — so field five
    // onward was whatever the frame left behind. Exercised by value: this
    // program exits 18 (1*10 + 8) under both backends; it exited 10 before.
    const source =
        \\eight: @{ a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64 }
        \\mk(): eight
        \\    return { a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7, h = 8 }
        \\end
        \\main(): i64
        \\    v = mk()
        \\    return v.a * 10 + v.h
        \\end
    ;
    var lex = Lexer.init(source, "explode8.duo");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);

    const listing = try emitAssembly(alloc, &mod, "native-asm");
    defer alloc.free(listing);

    // Every one of the eight ABI registers is written, including the eighth.
    try std.testing.expect(std.mem.indexOf(u8, listing, "mov x7,") != null);
    // And no indirect buffer is set up — this path stays in registers.
    try std.testing.expect(std.mem.indexOf(u8, listing, "add x8, sp,") == null);
    // x18 is Apple's reserved platform register; eight staged fields is the
    // pressure that used to reach it.
    try std.testing.expect(std.mem.indexOf(u8, listing, "x18") == null);

    const obj = try emitObject(alloc, &mod, "native-object");
    defer alloc.free(obj);
    try std.testing.expect(obj.len > 0);
}
