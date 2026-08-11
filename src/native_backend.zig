const std = @import("std");
const builtin = @import("builtin");
const ast = @import("ast.zig");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;
const dnir = @import("duo_native_ir.zig");
const c_signatures = @import("c_signatures.zig");
const native_types = @import("types.zig");
const dnir_lower = @import("dnir_lower.zig");
const dnir_hardware = @import("dnir_hardware.zig");
const semantic_graph = @import("semantic_graph.zig");
const region_graph = @import("region_graph.zig");
const region_transform = @import("region_transform.zig");
const realization = @import("realization.zig");

pub const Error = error{
    UnsupportedTarget,
    UnsupportedProgram,
    SemanticFactsInvalid,
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

/// Bootstrap projection from one realized application to emitted bytes.
/// Every semantic field is an exact id owned by the output's resident graph.
pub const MachineLineage = struct {
    relation: semantic_graph.id,
    application: semantic_graph.id,
    value: semantic_graph.id,
    subject: ?semantic_graph.id,
    descriptor: native_types.ResolvedType,
    caller: semantic_graph.id,
    instruction_start: u32,
    instruction_end: u32,
    text_start: u32,
    text_end: u32,
    object_start: u32 = 0,
    object_end: u32 = 0,
};

pub const ObjectWithLineage = struct {
    bytes: []u8,
    lineage: []MachineLineage,
    /// Borrowed physical context for the ids in `lineage`.
    graph: *const semantic_graph.SemanticGraph,

    pub fn deinit(self: *ObjectWithLineage, alloc: std.mem.Allocator) void {
        alloc.free(self.bytes);
        alloc.free(self.lineage);
    }
};

pub const AssemblyWithLineage = struct {
    assembly: []u8,
    machine: []u8,
    lineage: []MachineLineage,
    /// Borrowed physical context for the ids in `lineage`.
    graph: *const semantic_graph.SemanticGraph,

    pub fn deinit(self: *AssemblyWithLineage, alloc: std.mem.Allocator) void {
        alloc.free(self.assembly);
        alloc.free(self.machine);
        alloc.free(self.lineage);
    }
};

/// Caller-owned physical evidence for one native attempt. Lowering and backend
/// refusal evidence travel together without allocation or ambient state.
pub const Diagnostic = struct {
    site: ?std.builtin.SourceLocation = null,
    note_buffer: [64]u8 = undefined,
    note_len: u8 = 0,
    lowering: dnir_lower.Diagnostic = .{},

    pub fn reset(self: *Diagnostic) void {
        self.site = null;
        self.note_len = 0;
        self.lowering.reset();
    }

    pub fn note(self: *const Diagnostic) ?[]const u8 {
        if (self.note_len == 0) return null;
        return self.note_buffer[0..self.note_len];
    }

    fn record(self: *Diagnostic, site: std.builtin.SourceLocation, detail: ?[]const u8) void {
        self.site = site;
        const text = detail orelse {
            self.note_len = 0;
            return;
        };
        const len = @min(text.len, self.note_buffer.len);
        @memcpy(self.note_buffer[0..len], text[0..len]);
        self.note_len = @intCast(len);
    }
};

fn recordRefusal(diagnostic: *Diagnostic, src: std.builtin.SourceLocation) Error {
    diagnostic.record(src, null);
    return error.UnsupportedProgram;
}

/// Same treatment for the OTHER refusal error. `UndefinedName` means a slot or
/// temp had no register, and which one is the entire finding — exactly as
/// `UnknownSymbol` turned out to be two different problems wearing one code
/// once the symbol was printed.
/// Same as `undefinedAt` but for the keyed maps (fp_locals, fp_stack_slots,
/// locals), where the KEY is the finding rather than a slot number.
fn recordUndefinedKey(diagnostic: *Diagnostic, src: std.builtin.SourceLocation, kind: []const u8, key: []const u8) Error {
    diagnostic.site = src;
    const w = std.fmt.bufPrint(&diagnostic.note_buffer, "{s} '{s}' has no register", .{ kind, key }) catch {
        diagnostic.note_len = 0;
        return error.UndefinedName;
    };
    diagnostic.note_len = @intCast(w.len);
    return error.UndefinedName;
}

fn recordUndefinedAt(diagnostic: *Diagnostic, src: std.builtin.SourceLocation, kind: []const u8, id: u32) Error {
    diagnostic.site = src;
    const w = std.fmt.bufPrint(&diagnostic.note_buffer, "{s} {d} has no register", .{ kind, id }) catch {
        diagnostic.note_len = 0;
        return error.UndefinedName;
    };
    diagnostic.note_len = @intCast(w.len);
    return error.UndefinedName;
}

fn recordRefusalWith(diagnostic: *Diagnostic, src: std.builtin.SourceLocation, note: []const u8) Error {
    diagnostic.record(src, note);
    return error.UnsupportedProgram;
}

fn invalidFactsWith(diagnostic: *Diagnostic, src: std.builtin.SourceLocation, note: []const u8) Error {
    diagnostic.record(src, note);
    return error.SemanticFactsInvalid;
}

fn transformFailure(diagnostic: *Diagnostic, src: std.builtin.SourceLocation, err: region_transform.Error) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.ResidencyMismatch => invalidFactsWith(diagnostic, src, "region-transform-residency"),
        error.CoordinateOverflow => recordRefusalWith(diagnostic, src, "region-coordinate-capacity"),
    };
}

pub fn directDiagnostic(err: Error, target: []const u8) DirectDiag {
    _ = target;
    return switch (err) {
        error.UnsupportedTarget => .{ .code = "DNB004", .message = "target object format or host is unsupported by the direct backend" },
        error.UnsupportedProgram => .{ .code = "DNB001", .message = "program construct is outside the direct backend subset" },
        error.SemanticFactsInvalid => .{ .code = "DNB011", .message = "required graph facts or realization lineage are missing or inconsistent" },
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
        error.SemanticFactsInvalid,
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

/// Emit a graph-aware object together with the byte ranges of every DNIR
/// instruction that retained application facts. The symbol table remains a
/// physical linker projection; semantic correspondence is queried through this
/// sidecar, never reconstructed from symbol spelling.
pub fn emitObjectWithGraphLineage(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    target: []const u8,
    graph: *const semantic_graph.SemanticGraph,
) Error!ObjectWithLineage {
    var diagnostic: Diagnostic = .{};
    return emitObjectWithGraphLineageObserved(alloc, mod, target, graph, &diagnostic);
}

pub fn emitObjectWithGraphLineageObserved(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    target: []const u8,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error!ObjectWithLineage {
    diagnostic.reset();
    if (!isNativeObjectTarget(target)) return error.UnsupportedTarget;
    return emitObjectModeWithGraphLineage(alloc, mod, null, graph, diagnostic);
}

/// When `process_entry` is set the named zero-arg function
/// gets `fcvtzs x0, d0` on f64 returns so native executables receive an i64 exit code.
pub fn emitObjectForExecutableWithGraphLineage(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    process_entry: []const u8,
    graph: *const semantic_graph.SemanticGraph,
) Error!ObjectWithLineage {
    var diagnostic: Diagnostic = .{};
    return emitObjectForExecutableWithGraphLineageObserved(alloc, mod, process_entry, graph, &diagnostic);
}

pub fn emitObjectForExecutableWithGraphLineageObserved(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    process_entry: []const u8,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error!ObjectWithLineage {
    diagnostic.reset();
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) {
        return error.UnsupportedTarget;
    }
    return emitObjectModeWithGraphLineage(alloc, mod, process_entry, graph, diagnostic);
}

pub fn emitSharedObjectInputWithGraphLineage(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    graph: *const semantic_graph.SemanticGraph,
) Error!ObjectWithLineage {
    var diagnostic: Diagnostic = .{};
    return emitSharedObjectInputWithGraphLineageObserved(alloc, mod, graph, &diagnostic);
}

pub fn emitSharedObjectInputWithGraphLineageObserved(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error!ObjectWithLineage {
    diagnostic.reset();
    return emitObjectModeWithGraphLineage(alloc, mod, null, graph, diagnostic);
}

fn emitObjectModeWithGraphLineage(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    process_entry: ?[]const u8,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error!ObjectWithLineage {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) {
        return error.UnsupportedTarget;
    }

    var output = try emitArm64ModuleWithGraph(alloc, mod, process_entry, graph, diagnostic);
    defer output.deinit(alloc);
    if (output.graph != graph) return invalidFactsWith(diagnostic, @src(), "object-graph-context");
    const bytes = try emitMachOArm64Object(alloc, output.text, output.cstring, output.symbols, output.relocations, output.bss_size);
    errdefer alloc.free(bytes);

    const text_offset = machOTextOffset(output.cstring.len, output.bss_size);
    const lineage = try alloc.dupe(MachineLineage, output.lineage);
    errdefer alloc.free(lineage);
    for (lineage) |*entry| {
        entry.object_start = @intCast(text_offset + entry.text_start);
        entry.object_end = @intCast(text_offset + entry.text_end);
    }
    return .{
        .bytes = bytes,
        .lineage = lineage,
        .graph = graph,
    };
}

pub fn emitAssemblyWithGraphLineage(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    target: []const u8,
    graph: *const semantic_graph.SemanticGraph,
) Error!AssemblyWithLineage {
    var diagnostic: Diagnostic = .{};
    return emitAssemblyWithGraphLineageObserved(alloc, mod, target, graph, &diagnostic);
}

pub fn emitAssemblyWithGraphLineageObserved(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    target: []const u8,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error!AssemblyWithLineage {
    diagnostic.reset();
    if (!isNativeAsmTarget(target)) return error.UnsupportedTarget;
    return emitAssemblyModeWithGraphLineage(alloc, mod, null, graph, diagnostic);
}

pub fn emitAssemblyForExecutableWithGraphLineage(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    process_entry: []const u8,
    graph: *const semantic_graph.SemanticGraph,
) Error!AssemblyWithLineage {
    var diagnostic: Diagnostic = .{};
    return emitAssemblyForExecutableWithGraphLineageObserved(alloc, mod, process_entry, graph, &diagnostic);
}

pub fn emitAssemblyForExecutableWithGraphLineageObserved(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    process_entry: []const u8,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error!AssemblyWithLineage {
    diagnostic.reset();
    return emitAssemblyModeWithGraphLineage(alloc, mod, process_entry, graph, diagnostic);
}

fn emitAssemblyModeWithGraphLineage(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    process_entry: ?[]const u8,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error!AssemblyWithLineage {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) {
        return error.UnsupportedTarget;
    }
    var output = try emitArm64ModuleWithGraph(alloc, mod, process_entry, graph, diagnostic);
    errdefer output.deinit(alloc);
    if (output.graph != graph) return invalidFactsWith(diagnostic, @src(), "assembly-graph-context");
    const artifact: AssemblyWithLineage = .{
        .assembly = output.asm_text,
        .machine = output.text,
        .lineage = output.lineage,
        .graph = graph,
    };
    output.deinitExceptAssemblyMachineAndLineage(alloc);
    return artifact;
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

fn freeF64Records(alloc: std.mem.Allocator, map: *F64RecordMap) void {
    map.deinit(alloc);
}

fn freeScalRecords(alloc: std.mem.Allocator, map: *ScalRecordMap) void {
    var it = map.iterator();
    while (it.next()) |entry| {
        alloc.free(entry.value_ptr.field_kinds);
    }
    map.deinit(alloc);
}

fn scalRecordDesc(records: *const ScalRecordMap, typ: ast.TypeExpr) ?ScalRecordDesc {
    if (typ != .named) return null;
    return records.get(typ.named);
}

fn f64RecordDesc(records: *const F64RecordMap, typ: ast.TypeExpr) ?F64RecordDesc {
    if (typ != .named) return null;
    return records.get(typ.named);
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
    lineage: []MachineLineage = &.{},
    /// Borrowed physical context for the ids in `lineage`.
    graph: ?*const semantic_graph.SemanticGraph = null,
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
        if (self.lineage.len > 0) alloc.free(self.lineage);
    }

    fn deinitExceptAssembly(self: *Arm64Output, alloc: std.mem.Allocator) void {
        alloc.free(self.text);
        if (self.cstring.len > 0) alloc.free(self.cstring);
        for (self.symbols) |sym| alloc.free(sym.name);
        alloc.free(self.symbols);
        alloc.free(self.relocations);
        if (self.lineage.len > 0) alloc.free(self.lineage);
    }

    fn deinitExceptAssemblyMachineAndLineage(self: *Arm64Output, alloc: std.mem.Allocator) void {
        if (self.cstring.len > 0) alloc.free(self.cstring);
        for (self.symbols) |sym| alloc.free(sym.name);
        alloc.free(self.symbols);
        alloc.free(self.relocations);
    }
};

fn isFloatAnnotation(t: ast.TypeExpr) bool {
    return t.is_float(); // named == "f32" or "f64"
}

fn returnsFloat(t: ast.TypeExpr) bool {
    return isFloatAnnotation(t);
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

/// Linker entry for native executables. Idsem has no mandatory `main()` — file-scope
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
    // `main`, `@export` and `--entry` are DELIBERATE and still win above. Only
    // inference is refused here; absence of an explicit native entry is
    // terminal for both auto and direct machine requests.
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
    diagnostic: *Diagnostic,
    f64_records: *const F64RecordMap,
    scal_records: *const ScalRecordMap,
    code: std.ArrayList(u8) = .empty,
    asm_text: std.ArrayList(u8) = .empty,
    symbols: std.ArrayList(Symbol) = .empty,
    extern_symbols: std.StringHashMapUnmanaged(u32) = .empty,
    relocations: std.ArrayList(Relocation) = .empty,
    lineage: std.ArrayList(MachineLineage) = .empty,
    call_patches: std.ArrayList(CallPatch) = .empty,
    used_regs: [29]bool = @splat(false),
    returned: bool = false,
    strings: std.ArrayList(StringSymbol) = .empty,
    string_map: std.StringHashMapUnmanaged(u32) = .empty,
    next_string: u32 = 0,
    // f64 native emission: per-function physical FP state. FP params arrive
    // in d0-d7 (caller-saved) and the result returns in d0.
    cur_func_float: bool = false,
    /// Function returns f64 but is not a pure-f64 kernel (zero-param shell, etc.).
    cur_func_ret_float: bool = false,
    /// The function's DECLARED return type. `cur_func_float` is derived from
    /// parameters alone (`f64AbiParamSlots`), so on its own it cannot answer
    /// what a `ret` should do — see the `.ret` arm.
    cur_func_ret: native_types.ResolvedType = .any,
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
    /// Which `temps` entries hold an FP register. `temps` is ONE map for two
    /// register files and the reader picks the file, which worked only by
    /// numeric accident: GP values came from x9-x28 and FP values from d0-d7,
    /// so a register number implied its file. Moving FP values to d16-d30 (to
    /// get them out of the argument-staging range) made the ranges overlap and
    /// the accident vanished — `i < 100` began emitting `fcmp d10, d18` against
    /// x10's number. See gap[058].
    fp_temps: std.AutoHashMapUnmanaged(u32, void) = .empty,
    used_fp_regs: [32]bool = @splat(false),
    /// LIVENESS for the FP value range. `releaseFpReg` was a no-op, so
    /// allocation was a monotonic cursor and every float loop walked off the
    /// end of the pool; the standing answer was to raise the pool size, which
    /// converted honest DNB003 refusals into hangs twice (gap[057]).
    ///
    /// Three facts make a release safe:
    ///   * `fp reg owner` — which DNIR id currently reads out of this register.
    ///     A register with an owner is not scratch and cannot be handed back by
    ///     an operand-release at the point of use.
    ///   * `fp home regs` — this register is a LOCAL's home. A local keeps one
    ///     register for its whole lifetime, so a home is never freed.
    ///   * `value free at` — the last instruction index that READS an id, extended
    ///     across any enclosing back edge. Freeing on the last TEXTUAL use is
    ///     wrong inside a loop: a value defined before the loop and last read
    ///     inside it is read again on the next iteration, after the reuse has
    ///     already clobbered the register.
    fp_reg_owner: [32]?u32 = @splat(null),
    fp_home_regs: [32]bool = @splat(false),
    /// Last instruction that reads each DNIR value/slot id. The map is shared
    /// by both register files; physical file selection is a separate fact.
    value_free_at: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    fp_abi_passthrough: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Stack slots for sealed record fields (f64 or i64): "c.pos" -> slot meta.
    fp_stack_slots: std.StringHashMapUnmanaged(StackSlot) = .empty,
    stack_frame_bytes: u16 = 0,
    /// `alloc_slots` result temp -> sp-relative byte offset of its slot region.
    slot_bases: std.AutoHashMapUnmanaged(u32, u16) = .empty,
    spilled_regs: std.AutoHashMapUnmanaged(u5, u16) = .empty,
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

    const SaveSet = struct {
        regs: [20]u5 = @splat(0),
        count: u5 = 0,
        /// Live FP VALUE registers (d16-d30). Every d register is caller-saved
        /// on AAPCS64, so without this no float survives a call — which is why
        /// widening the FP pool before adding this hung mandelbrot (gap[057]).
        /// d0-d7 are NOT saved, matching the integer side's decision not to save
        /// x0-x8: those are argument and result registers, and saving the result
        /// register would clobber the value the call just produced.
        fp_regs: [16]u5 = @splat(0),
        fp_count: u5 = 0,
        stack_bytes: u16 = 0,
    };

    const StringSymbol = struct {
        bytes: []const u8,
        name: []const u8,
        symbol_index: u32,
    };

    const DnirBranchPatch = struct {
        patch_off: u32,
        target_instr: u32,
        is_cond: bool,
    };

    fn refuse(self: *Arm64Compiler, src: std.builtin.SourceLocation) Error {
        return recordRefusal(self.diagnostic, src);
    }

    fn refuseWith(self: *Arm64Compiler, src: std.builtin.SourceLocation, note: []const u8) Error {
        return recordRefusalWith(self.diagnostic, src, note);
    }

    fn undefinedKey(self: *Arm64Compiler, src: std.builtin.SourceLocation, kind: []const u8, key: []const u8) Error {
        return recordUndefinedKey(self.diagnostic, src, kind, key);
    }

    fn undefinedAt(self: *Arm64Compiler, src: std.builtin.SourceLocation, kind: []const u8, id: u32) Error {
        return recordUndefinedAt(self.diagnostic, src, kind, id);
    }

    fn deinit(self: *Arm64Compiler) void {
        self.code.deinit(self.alloc);
        self.asm_text.deinit(self.alloc);
        for (self.symbols.items) |sym| self.alloc.free(sym.name);
        self.symbols.deinit(self.alloc);
        self.extern_symbols.deinit(self.alloc);
        self.relocations.deinit(self.alloc);
        self.lineage.deinit(self.alloc);
        for (self.call_patches.items) |patch| self.alloc.free(patch.target);
        self.call_patches.deinit(self.alloc);
        for (self.strings.items) |s| {
            self.alloc.free(s.bytes);
            self.alloc.free(s.name);
        }
        self.strings.deinit(self.alloc);
        self.string_map.deinit(self.alloc);
        self.fp_locals.deinit(self.alloc);
        self.fp_temps.deinit(self.alloc);
        self.value_free_at.deinit(self.alloc);
        self.fp_abi_passthrough.deinit(self.alloc);
        self.fp_stack_slots.deinit(self.alloc);
        self.slot_bases.deinit(self.alloc);
        self.spilled_regs.deinit(self.alloc);
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
        if (self.strings.items.len > 0) {
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
        errdefer self.alloc.free(relocations);
        const lineage = try self.lineage.toOwnedSlice(self.alloc);
        self.lineage = .empty;
        return .{
            .text = text,
            .asm_text = asm_text,
            .cstring = cstring_bytes,
            .symbols = symbols,
            .relocations = relocations,
            .lineage = lineage,
        };
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

    fn needsProcessExitF64Coerce(self: *const Arm64Compiler) bool {
        const entry = self.process_entry orelse return false;
        const cur = self.cur_func_name orelse return false;
        if (!std.mem.eql(u8, entry, cur)) return false;
        return self.cur_func_float or self.cur_func_ret_float;
    }

    fn compileDnirModule(self: *Arm64Compiler, m: dnir.Module) Error!void {
        try self.emitAsmHeader();
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

    /// Every DNIR id this instruction READS. `vals` carries the fields of a
    /// wide record return that lhs/rhs/third cannot express, so a scan that
    /// stopped at `third` would call a fourth field dead while it is still read.
    fn forEachOperandId(ins: dnir.Instr, ctx: anytype, comptime visit: fn (@TypeOf(ctx), u32) void) void {
        const fixed = [_]dnir.Value{ ins.lhs, ins.rhs, ins.third };
        for (fixed) |v| switch (v) {
            .local, .temp => |id| visit(ctx, id),
            else => {},
        };
        for (ins.vals) |v| switch (v) {
            .local, .temp => |id| visit(ctx, id),
            else => {},
        };
    }

    fn instructionReadsId(ins: dnir.Instr, id: u32) bool {
        const fixed = [_]dnir.Value{ ins.lhs, ins.rhs, ins.third };
        for (fixed) |value| switch (value) {
            .local, .temp => |slot| if (slot == id) return true,
            else => {},
        };
        for (ins.vals) |value| switch (value) {
            .local, .temp => |slot| if (slot == id) return true,
            else => {},
        };
        return false;
    }

    /// Last instruction index that reads each id, widened so that no live range
    /// ends inside a loop it did not start in. See the `value free at` field.
    fn computeValueLastUse(self: *Arm64Compiler, f: dnir.Function) Error!void {
        self.value_free_at.clearRetainingCapacity();
        self.fp_abi_passthrough.clearRetainingCapacity();
        var def_at: std.AutoHashMapUnmanaged(u32, u32) = .empty;
        defer def_at.deinit(self.alloc);
        var back: std.ArrayList([2]u32) = .empty;
        defer back.deinit(self.alloc);

        var idx: u32 = 0;
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                const Sink = struct {
                    map: *std.AutoHashMapUnmanaged(u32, u32),
                    alloc: std.mem.Allocator,
                    at: u32,
                    failed: bool = false,
                    fn note(s: *@This(), id: u32) void {
                        s.map.put(s.alloc, id, s.at) catch {
                            s.failed = true;
                        };
                    }
                };
                var sink: Sink = .{ .map = &self.value_free_at, .alloc = self.alloc, .at = idx };
                forEachOperandId(ins, &sink, Sink.note);
                if (sink.failed) return error.OutOfMemory;
                if (ins.result) |r| {
                    if (!def_at.contains(r)) try def_at.put(self.alloc, r, idx);
                }
                switch (ins.op) {
                    .br => {
                        if (ins.branch_target <= idx) {
                            try back.append(self.alloc, .{ ins.branch_target, idx });
                        }
                    },
                    else => {},
                }
                idx += 1;
            }
        }

        // A range that STARTS before a loop and ENDS inside it must survive to
        // the back edge, or the next iteration reads a register that the tail of
        // the body has already reused. Nested loops make one pass insufficient:
        // widening to an inner back edge can drag a range into an outer one, so
        // iterate to a fixpoint (bounded — every step only moves ends forward).
        var changed = true;
        var rounds: u32 = 0;
        while (changed and rounds < 16) : (rounds += 1) {
            changed = false;
            var it = self.value_free_at.iterator();
            while (it.next()) |e| {
                const def = def_at.get(e.key_ptr.*) orelse 0;
                for (back.items) |edge| {
                    const head = edge[0];
                    const tail = edge[1];
                    if (def < head and e.value_ptr.* >= head and e.value_ptr.* < tail) {
                        e.value_ptr.* = tail;
                        changed = true;
                    }
                }
            }
        }
        // A fixpoint that did not settle means the widening is not conservative
        // enough to trust. Pin every range to the end of the function rather
        // than free anything on a guess.
        if (changed) {
            var it = self.value_free_at.valueIterator();
            while (it.next()) |v| v.* = std.math.maxInt(u32);
        }

        // Keep a checked f64 result in d0 only when the next instruction
        // immediately consumes it as an ABI argument or function result.
        // Otherwise a later call may overwrite d0, and store_local would
        // incorrectly make the ABI register look like stable storage.
        var previous_call_result: ?u32 = null;
        idx = 0;
        for (f.blocks) |block| {
            for (block.instrs) |instruction| {
                if (previous_call_result) |result| {
                    const direct_consumer = instruction.op == .fp_mov_arg or instruction.op == .ret;
                    if (direct_consumer and
                        self.value_free_at.get(result) == idx and
                        instructionReadsId(instruction, result))
                    {
                        try self.fp_abi_passthrough.put(self.alloc, result, {});
                    }
                }
                previous_call_result = switch (instruction.op) {
                    .call_direct, .call_extern => instruction.result,
                    else => null,
                };
                idx += 1;
            }
        }
    }

    /// This register is a local's home for the rest of the function.
    fn markFpHome(self: *Arm64Compiler, reg: u5) void {
        self.fp_home_regs[reg] = true;
        self.used_fp_regs[reg] = true;
    }

    /// Free every FP value register whose owner has no read left after `idx`.
    fn sweepFpLive(self: *Arm64Compiler, idx: u32) void {
        var reg: u5 = fp_value_reg_base;
        while (reg < fp_value_reg_base + fp_value_reg_count) : (reg += 1) {
            const owner = self.fp_reg_owner[reg] orelse continue;
            if (self.fp_home_regs[reg]) continue;
            const last = self.value_free_at.get(owner) orelse 0;
            if (last > idx) continue;
            self.fp_reg_owner[reg] = null;
            self.used_fp_regs[reg] = false;
        }
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
        self.fp_locals.clearRetainingCapacity();
        self.fp_temps.clearRetainingCapacity();
        // A staged variadic tail belongs to exactly one call. Carrying a
        // leftover across a function boundary would push a stale register onto
        // the next call's memory-argument area, so clear it with the rest of
        // the per-function register state.
        self.pending_vararg_count = 0;
        self.used_regs = @splat(false);
        self.used_fp_regs = @splat(false);
        self.fp_reg_owner = @splat(null);
        self.fp_home_regs = @splat(false);
        try self.computeValueLastUse(f);
        self.returned = false;
        self.fp_stack_slots.clearRetainingCapacity();
        self.stack_frame_bytes = 0;
        self.cur_func_ret_record = if (f.ret_record) |rn| scalRecordDesc(self.scal_records, .{ .named = rn }) else null;
        self.cur_func_ret_f64_record = if (f.ret_record) |rn| f64RecordDesc(self.f64_records, .{ .named = rn }) else null;
        self.cur_ret_indirect_reg = null;
        self.cur_func_float = f.is_float_kernel;
        self.cur_func_ret_float = f.ret == .f64 and !f.is_float_kernel;
        self.cur_func_ret = f.ret;

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
            // Exactly the move the integer path below makes, and for exactly
            // the same reason. d0-d7 are BOTH the f64 argument registers and
            // the staging registers for an outgoing call, so a parameter left
            // in its incoming register is destroyed the moment the body calls
            // anything: `p: f64 = 9.0; one(2.0)` overwrote p's home, and
            // `two(4.0, p)` swapped two registers through each other and passed
            // (4.0, 4.0). The integer side solved this long ago by copying
            // parameters out of x0-x7 into the x9+ value range; the FP side
            // never did, and lowering papered over it by REFUSING such calls
            // (`requireSafeFpStaging`).
            //
            // Leaf functions keep the incoming register and pay nothing, which
            // is both free and safe: with no call there is no staging.
            const fp_body_has_call = dnirFunctionHasCall(f);
            var dreg: u5 = 0;
            for (f.params, 0..) |p, i| {
                const slot: u32 = @intCast(i);
                if (p.ty == .f64) {
                    self.used_fp_regs[dreg] = true;
                    const home = if (fp_body_has_call) blk: {
                        const h = try self.allocFpReg();
                        try self.emitFmovReg(h, dreg);
                        break :blk h;
                    } else dreg;
                    self.markFpHome(home);
                    try self.fp_locals.put(self.alloc, p.name, home);
                    try temps.put(self.alloc, slot, home);
                    try self.markFpTemp(slot);
                    dreg += 1;
                } else if (p.record) |rec_name| {
                    const rec = f64RecordDesc(self.f64_records, .{ .named = rec_name }) orelse return self.refuse(@src());
                    for (rec.field_names) |fname| {
                        self.used_fp_regs[dreg] = true;
                        const home = if (fp_body_has_call) blk: {
                            const h = try self.allocFpReg();
                            try self.emitFmovReg(h, dreg);
                            break :blk h;
                        } else dreg;
                        self.markFpHome(home);
                        const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ p.name, fname });
                        try self.fp_locals.put(self.alloc, key, home);
                        dreg += 1;
                    }
                } else return self.refuse(@src());
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
                    if (slot_cursor >= 8) return self.refuse(@src());
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
                        .i64 => |v| if (v > 0 and v <= 4096) @intCast(v) else return self.refuse(@src()),
                        else => return self.refuse(@src()),
                    };
                    const bytes: u16 = @intCast(std.mem.alignForward(usize, @as(usize, n) * 8, 16));
                    if (@as(u32, slots_frame) + bytes > 32752) return self.refuse(@src());
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
        var flat_idx: u32 = 0;
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                const text_start: u32 = @intCast(self.code.items.len);
                try code_offsets.append(self.alloc, text_start);
                try self.compileDnirInstr(&temps, &pinned, ins, &branch_patches);
                const fact_count: u2 = @as(u2, @intFromBool(ins.relation != null)) +
                    @as(u2, @intFromBool(ins.application != null)) +
                    @as(u2, @intFromBool(ins.value != null));
                if (fact_count != 0 and fact_count != 3) {
                    return self.refuseWith(@src(), "partial-application-lineage");
                }
                if (fact_count == 0 and ins.subject != null) {
                    return self.refuseWith(@src(), "orphan-application-subject");
                }
                if ((fact_count == 3) != (ins.realization_start != null)) {
                    return self.refuseWith(@src(), "partial-realization-lineage");
                }
                if (ins.application) |application| {
                    const realization_start = ins.realization_start.?;
                    if (realization_start > flat_idx or realization_start >= code_offsets.items.len) {
                        return self.refuseWith(@src(), "invalid-realization-start");
                    }
                    try self.lineage.append(self.alloc, .{
                        .relation = ins.relation.?,
                        .application = application,
                        .value = ins.value.?,
                        .subject = ins.subject,
                        .descriptor = ins.ty,
                        .caller = f.id orelse
                            return self.refuseWith(@src(), "application-caller"),
                        .instruction_start = realization_start,
                        .instruction_end = flat_idx + 1,
                        .text_start = code_offsets.items[realization_start],
                        .text_end = @intCast(self.code.items.len),
                    });
                }
                // Ownership is recorded HERE, once, rather than at each of the
                // eight `temps.put` + `markFpTemp` pairs: the pair is exactly
                // "this id now reads out of this register", and one place
                // cannot drift out of step with another.
                if (ins.result) |t| {
                    if (self.fp_temps.contains(t)) {
                        if (temps.get(t)) |r| {
                            if (r >= fp_value_reg_base and
                                r < fp_value_reg_base + fp_value_reg_count and
                                !self.fp_home_regs[r])
                            {
                                self.fp_reg_owner[r] = t;
                            }
                        }
                    }
                }
                self.sweepFpLive(flat_idx);
                tail_terminates = switch (ins.op) {
                    .ret, .ret_record => true,
                    .br => ins.branch_condition == .unconditional,
                    else => false,
                };
                flat_idx += 1;
            }
        }
        // Sentinel: branch_target may equal instr count (fall-through past if-block).
        try code_offsets.append(self.alloc, @intCast(self.code.items.len));
        for (branch_patches.items) |p| {
            if (p.target_instr >= code_offsets.items.len) return self.refuse(@src());
            const target_off = code_offsets.items[p.target_instr];
            if (p.is_cond) {
                try self.patchCondBranch(p.patch_off, target_off);
            } else {
                try self.patchB(p.patch_off, target_off);
            }
        }
        if (!self.returned) return self.refuse(@src());
        // Falling off the end of a function is never recoverable at runtime:
        // execution continues into whatever symbol the linker placed next
        // (here, straight into _duo_keyword_classify → SIGSEGV). Refuse instead
        // of emitting it, so the honest DNB001 path reports the gap.
        if (!tail_terminates) return self.refuse(@src());
    }

    fn compileDnirInstr(
        self: *Arm64Compiler,
        temps: *std.AutoHashMapUnmanaged(u32, u5),
        pinned: *std.AutoHashMapUnmanaged(u32, u5),
        ins: dnir.Instr,
        branch_patches: *std.ArrayList(DnirBranchPatch),
    ) Error!void {
        switch (ins.op) {
            .@"const" => switch (ins.ty) {
                .f64 => {
                    const d = try self.allocFpReg();
                    const val = switch (ins.lhs) {
                        .f64 => |v| v,
                        else => return self.refuse(@src()),
                    };
                    try self.emitFmovImmFp(d, val);
                    if (ins.result) |t| try temps.put(self.alloc, t, d);
                    try self.markFpTemp(ins.result);
                },
                .str => {
                    const reg = try self.allocReg();
                    const s = switch (ins.lhs) {
                        .str => |v| v,
                        else => return self.refuse(@src()),
                    };
                    const sym = try self.internString(s);
                    try self.emitAdrpAdd(reg, sym);
                    if (ins.result) |t| try temps.put(self.alloc, t, reg);
                },
                else => {
                    if (!ins.ty.is_integer()) return self.refuse(@src());
                    const reg = try self.allocReg();
                    const val = switch (ins.lhs) {
                        .i64 => |v| v,
                        else => return self.refuse(@src()),
                    };
                    try self.emitMovImm(reg, val);
                    if (ins.result) |t| try temps.put(self.alloc, t, reg);
                },
            },
            .fp_mov_arg => {
                const d_slot: u5 = @intCast(ins.result orelse return self.refuse(@src()));
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
                    const idx: u5 = @intCast(ins.result orelse return self.refuse(@src()));
                    if (idx >= self.pending_varargs.len) return self.refuse(@src());
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
                const slot: u5 = @intCast(ins.result orelse return self.refuse(@src()));
                const reg = try self.evalDnirValue(temps, ins.lhs);
                if (reg != slot) try self.emitMovReg(slot, reg);
                // Same rule as the single-argument path: a register still owned
                // by the slot map must survive being passed. Releasing a table
                // base here handed it to the next argument's index constant.
                if (reg != slot) self.releaseDnirTemp(pinned, ins.lhs, reg);
            },
            .store_local => {
                // A binding with no DNIR consumer does not demand a physical
                // place. An integer immediate has no effect to preserve, so
                // omit both materialization and the permanent local home. This is
                // deliberately narrower than general dead-code elimination:
                // temp/local operands still carry ownership and may need their
                // producer register retired by the value allocator.
                if (ins.result) |slot| {
                    if (ins.application == null and !self.value_free_at.contains(slot)) switch (ins.lhs) {
                        .i64 => return,
                        else => {},
                    };
                }
                // Dispatch on what the VALUE is, not only on how the
                // instruction is typed. `x2: f64 = x * x` arrived with a
                // non-f64 `ty`, so the store took the integer path and emitted
                // `mov x9, x18` — a general-purpose move of an FP register's
                // NUMBER. The later `fadd` then read d9 instead of d18 and
                // mandelbrot's escape test never fired, answering 100 for a
                // point that escapes at 5.
                if (ins.ty == .f64 or self.valueIsFp(ins.lhs)) {
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
                        // Claim the home BEFORE releasing the value register:
                        // on a local's first store they are the same register,
                        // and a release that ran first would hand the local's
                        // home to the next allocation.
                        if (home >= fp_value_reg_base and home < fp_value_reg_base + fp_value_reg_count) {
                            self.fp_reg_owner[home] = null;
                            self.markFpHome(home);
                        }
                        if (home != d) {
                            try self.emitFmovReg(home, d);
                            self.releaseFpReg(d);
                        }
                        try pinned.put(self.alloc, slot, home);
                        try temps.put(self.alloc, slot, home);
                        // FP-ness has to travel through the local, not just
                        // through the temp. `x2: f64 = x * x` stores an FP temp
                        // into a slot; without this the later `x2 + y2 > 4.0`
                        // saw two operands it believed were integers, took the
                        // GP comparison path, and never fired — mandelbrot ran
                        // all 100 iterations and answered 100 instead of 5.
                        try self.markFpTemp(slot);
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
                            else => return self.refuseWith(@src(), @tagName(ins.binop)),
                        }
                        if (alhs != adst) self.releaseFpReg(alhs);
                        if (arhs != adst) self.releaseFpReg(arhs);
                        if (ins.result) |t| try temps.put(self.alloc, t, adst);
                        try self.markFpTemp(ins.result);
                        break :blk;
                    }
                    const lhs = try self.evalDnirValueFp(temps, ins.lhs);
                    const rhs = try self.evalDnirValueFp(temps, ins.rhs);
                    const dst = try self.allocReg();
                    try self.emitFcmpReg(lhs, rhs);
                    try self.emitCsetFp(dst, conditionForComparison(ast_op));
                    // The sibling comparison arm inside a float kernel already
                    // does this. Both operands are consumed by the `fcmp` and
                    // neither survives into the boolean, so an immediate staged
                    // here (the `4.0` of `x2 + y2 > 4.0`) is pure scratch. It
                    // was leaked, which mattered when nothing was ever freed.
                    self.releaseFpReg(lhs);
                    self.releaseFpReg(rhs);
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
                    // ...but only when the OPERANDS are floats. Being inside a
                    // float kernel says nothing about `i < 100`, whose operands
                    // are both integers. Comparing them with `fcmp` read the GP
                    // register NUMBER as an FP register — `i` lives in x10 and
                    // the loop condition became `fcmp d10, d18` — so the branch
                    // was decided by unrelated float state and mandelbrot's
                    // inner loop never terminated (gap[058]).
                    //
                    // `valueIsFp` answers from `fp_temps` instead of from the
                    // function's kind. One FP operand is enough: an integer on
                    // the other side is converted by `evalDnirValueFp` with
                    // `scvtf`, which is what makes `zx*zx + zy*zy < 4.0` — the
                    // shape this arm was written for — still work.
                    const cmp_op = dnirBinOpToAst(ins.binop);
                    const any_fp = self.valueIsFp(ins.lhs) or self.valueIsFp(ins.rhs);
                    if (isComparison(cmp_op) and any_fp) {
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
                    // An all-integer OPERATION inside a float kernel is an
                    // ordinary integer operation. Nothing about the enclosing
                    // function changes that.
                    //
                    // This used to say `isComparison(cmp_op)` and let every
                    // other integer op fall into the FP arithmetic below, which
                    // is the same confusion one step further along:
                    // `i += 1` on an i64 counter emitted
                    // `scvtf d28, x9 / fadd d29, d10, d28 / fmov d10, d29` —
                    // an FP add of `i`'s GENERAL-PURPOSE register number, x10
                    // read as d10. x10 never advanced, so the loop head
                    // `cmp x10, #100` was true forever and the escape test at
                    // iteration 6 answered with `i` still 0. gap[058] found the
                    // comparison half of this; the arithmetic half survived it.
                    if (!any_fp) {
                        const ilhs = try self.evalDnirValue(temps, ins.lhs);
                        const irhs = try self.evalDnirValue(temps, ins.rhs);
                        const idst = try self.allocReg();
                        try self.emitCompareOrBinop(idst, ilhs, irhs, cmp_op);
                        if (!Arm64Compiler.regIsPinned(pinned, ilhs)) self.releaseReg(ilhs);
                        if (!Arm64Compiler.regIsPinned(pinned, irhs)) self.releaseReg(irhs);
                        if (ins.result) |t| try temps.put(self.alloc, t, idst);
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
                        else => return self.refuseWith(@src(), @tagName(ins.binop)),
                    }
                    if (lhs != dst) self.releaseFpReg(lhs);
                    if (rhs != dst) self.releaseFpReg(rhs);
                    if (ins.result) |t| try temps.put(self.alloc, t, dst);
                    try self.markFpTemp(ins.result);
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
                    if (ins.result) |result| {
                        try self.markFpTemp(result);
                        if (ins.application != null and !self.fp_abi_passthrough.contains(result)) {
                            const home = try self.allocFpReg();
                            try self.emitFmovReg(home, 0);
                            try temps.put(self.alloc, result, home);
                            self.used_fp_regs[0] = false;
                        } else {
                            // A direct ABI consumer can read d0 without an
                            // intermediate value register. This keeps a tail
                            // call/return at the same C-equivalent realization.
                            self.used_fp_regs[0] = true;
                            try temps.put(self.alloc, result, 0);
                        }
                    } else {
                        self.used_fp_regs[0] = false;
                    }
                } else if (self.cur_func_float and ins.application == null) {
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
                    if (ins.result) |result| {
                        self.used_fp_regs[0] = true;
                        // This arm parked the result in d0 and left it UNRECORDED,
                        // so `fp_temps` disagreed with the register the code had
                        // actually written. An integer consumer then read x0 — the
                        // same file confusion `crossFile` refuses everywhere else,
                        // but invisible to it, because the record said nothing.
                        // Say what was emitted; the cross-file guard can then judge
                        // the consumer instead of guessing.
                        try self.markFpTemp(result);
                        try temps.put(self.alloc, result, 0);
                    } else {
                        self.used_fp_regs[0] = false;
                    }
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
                        } else return self.refuse(@src());
                    }
                    if (ins.result) |result| {
                        const dst = try self.allocReg();
                        try self.emitMovReg(dst, 0);
                        try temps.put(self.alloc, result, dst);
                    }
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
                    } else return self.refuse(@src());
                }
            },
            .ret => {
                // What comes BACK decides how it comes back. `cur_func_float`
                // is `is_float_kernel`, computed by `f64AbiParamSlots` from
                // PARAMETERS only — it means "this function's arguments arrive
                // in d0-d7" and says nothing about the result. Treating it as a
                // return property sent `f(p: Point): str` down the FP path
                // whenever Point had f64 fields, and the string died in
                // `evalDnirValueFp`. The i64-field spelling of the same
                // function compiled fine, which is what made it look like a
                // record bug rather than a return-classification one.
                //
                // So: the declared return type wins, and the kernel flag only
                // decides when the return type is unknown.
                const ret_via_fp = ins.ty == .f64 or
                    self.cur_func_ret == .f64 or
                    (self.cur_func_float and self.cur_func_ret == .any and ins.ty == .any);
                if (ret_via_fp) {
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
                    const rec = self.cur_func_ret_record orelse return self.refuse(@src());
                    if (vals.len != rec.field_names.len) return self.refuse(@src());
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
                    if (n == 0 or n > dnir_lower.max_reg_record_fields) return self.refuse(@src());
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
            .br => {
                switch (ins.branch_condition) {
                    .unconditional => {
                        const patch_off = try self.emitB(0);
                        try branch_patches.append(self.alloc, .{ .patch_off = patch_off, .target_instr = ins.branch_target, .is_cond = false });
                    },
                    .when_true, .when_false => {
                        const cond = try self.evalDnirValue(temps, ins.lhs);
                        // The condition is a materialized boolean; compare that
                        // value rather than reusing flags from its producer.
                        try self.emitCmpZero(cond);
                        const arm: Condition = if (ins.branch_condition == .when_true) .ne else .eq;
                        const patch_off = try self.emitBCond(arm, 0);
                        self.releaseReg(cond);
                        try branch_patches.append(self.alloc, .{ .patch_off = patch_off, .target_instr = ins.branch_target, .is_cond = true });
                    },
                }
            },
            .load_field => {
                const base = if (ins.req_alias.len > 0) ins.req_alias else "rec";
                const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ base, ins.field });
                defer self.alloc.free(key);
                if (self.cur_func_float) {
                    const d = self.fp_locals.get(key) orelse return self.undefinedKey(@src(), "fp local", key);
                    if (ins.result) |t| try temps.put(self.alloc, t, d);
                    try self.markFpTemp(ins.result);
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
                        // x2 carries this physical mixed-ABI source — no FP reg.
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
                const t = ins.result orelse return self.refuse(@src());
                const off = self.slot_bases.get(t) orelse return self.refuse(@src());
                const dst = try self.allocReg();
                try self.emitAddSpImm(dst, off);
                try temps.put(self.alloc, t, dst);
            },
            .load_index, .store_index => |op| if (ins.ty == .i64) {
                // Memory-backed positional table: 8-byte elements, Idsem-indexed
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
                // `string.byte(s, i)`: Idsem indexes strings from 1, C pointers
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
                } else return self.refuse(@src());
            },
            .hw_spin => {
                if (dnir_hardware.arm64FixedWord(.spin_wait)) |word| {
                    try self.emit(word, "yield");
                } else return self.refuse(@src());
            },
            .hw_unary => {
                const src = try self.evalDnirValue(temps, ins.lhs);
                const dst = try self.allocReg();
                try self.emitHwUnary(dst, src, ins.hw);
                if (!Arm64Compiler.regIsPinned(pinned, src)) self.releaseReg(src);
                if (ins.result) |t| try temps.put(self.alloc, t, dst);
            },
            else => return self.refuse(@src()),
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
            // RBIT **64-bit** is 0xdac00000. This read 0x5ac00000 -- the 32-bit
            // form -- until `zig build isa-fidelity` diffed the descriptor in
            // lib/std/target/arm64.duo against clang. A 32-bit reverse writes
            // w{tmp}, which zero-fills the top half of x{tmp}, so the `clz x`
            // below counted those 32 zeros as well: `@ctz(8)` answered 35
            // natively and 3 through the C backend. No corpus program takes ctz
            // of anything, so the native differential could not see it; a
            // generated per-instruction sweep could.
            try self.emitFmt(0xdac00000 | (@as(u32, src) << 5) | @as(u32, tmp), "rbit x{d}, x{d}", .{ tmp, src });
            try self.emitFmt(0xdac01000 | (@as(u32, tmp) << 5) | @as(u32, dst), "clz x{d}, x{d}", .{ dst, tmp });
            self.releaseReg(tmp);
            return;
        }
        const word = dnir_hardware.arm64UnaryWord(hw, dst, src) orelse return self.refuse(@src());
        const mnem = switch (hw) {
            .clz => "clz",
            else => return self.refuse(@src()),
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

    /// A read whose register FILE disagrees with the file the value lives in.
    ///
    /// `temps` is one map for two register files, so this is not a type error
    /// that some other layer would have caught — it is a plain integer that
    /// names d18 in one reader and x18 in the other, and the emitted
    /// instruction is well-formed nonsense. `render()` in
    /// `examples/mandelbrot.duo` reached both directions in one expression:
    /// `(col - WIDTH / 2) * 3.5 / WIDTH` emitted `fmul d17, d12, d16` for a
    /// `col - 40` that lives in x12, then `sdiv x13, x17, x9` for a product
    /// that lives in d17. It printed 80 lines where C printed 3280.
    ///
    /// Refusing is the whole point: DNB001 sends the program to the C backend,
    /// which is right, whereas emitting sends it to a plausible wrong answer.
    /// gap[058] asks for this by name.
    fn crossFile(self: *const Arm64Compiler, v: dnir.Value, want_fp: bool) bool {
        return switch (v) {
            .local, .temp => |id| self.fp_temps.contains(id) != want_fp,
            else => false,
        };
    }

    fn evalDnirValue(self: *Arm64Compiler, temps: *std.AutoHashMapUnmanaged(u32, u5), v: dnir.Value) Error!u5 {
        if (self.crossFile(v, false)) return self.refuse(@src());
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
                return self.undefinedAt(@src(), "local", slot);
            },
            .temp => |t| temps.get(t) orelse return self.undefinedAt(@src(), "temp", t),
            .record => return self.refuse(@src()),
        };
    }

    fn evalDnirValueFp(self: *Arm64Compiler, temps: *std.AutoHashMapUnmanaged(u32, u5), v: dnir.Value) Error!u5 {
        // gap[101]: an INTEGER-classed temp in a float position is a LOSSLESS
        // WIDENING, not a refusal. The `.i64` arm below already does exactly
        // this for an immediate, and its comment reads: "scvtf already existed
        // for exactly this and nothing reached it from here." A temp is the case
        // that never reached it — `(col - WIDTH/2) * 3.5` is a binop, so the
        // integer subexpression arrives as a temp and the immediate arm cannot
        // see it. Traced, not inferred: mandelbrot refuses here on temp 6,
        // defined by an integer binop and consumed by a float operand.
        //
        // Only this direction. float->int is NOT symmetric and must not be
        // added: it truncates, mandelbrot writes no conversion at all, and a
        // backend that truncates unasked still renders an image — the wrong
        // one, past a passing fixture. See gap[101].
        if (self.crossFile(v, true)) {
            switch (v) {
                .local, .temp => |id| {
                    if (temps.get(id)) |gp| {
                        const d = try self.allocFpReg();
                        try self.emitScvtfFromGpr(d, gp);
                        return d;
                    }
                    return self.refuse(@src());
                },
                else => return self.refuse(@src()),
            }
        }
        return switch (v) {
            .void => try self.allocFpReg(),
            .f64 => |n| blk: {
                const d = try self.allocFpReg();
                try self.emitFmovImmFp(d, n);
                break :blk d;
            },
            .local => |slot| temps.get(slot) orelse self.undefinedAt(@src(), "local", slot),
            .temp => |t| temps.get(t) orelse self.undefinedAt(@src(), "temp", t),
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
            else => self.refuse(@src()),
        };
    }

    fn evalDnirFpArg(self: *Arm64Compiler, temps: *std.AutoHashMapUnmanaged(u32, u5), v: dnir.Value) Error!u5 {
        if (self.crossFile(v, true)) return self.refuse(@src());
        return switch (v) {
            .f64 => |n| blk: {
                const d = try self.allocFpReg();
                try self.emitFmovImmFp(d, n);
                break :blk d;
            },
            .local => |slot| temps.get(slot) orelse self.undefinedAt(@src(), "local", slot),
            .temp => |t| temps.get(t) orelse self.undefinedAt(@src(), "temp", t),
            else => self.refuse(@src()),
        };
    }

    /// Hand a SCRATCH FP register back. Scratch means exactly: inside the value
    /// range, not a local's home, and not currently read by any id. Every
    /// caller passes the register an operand happened to arrive in, and that
    /// register is very often a live local or a temp with reads still ahead —
    /// which is why this function was a no-op, and why making it free
    /// unconditionally would clobber the loop state it is supposed to preserve.
    /// Owned registers retire in `sweepFpLive`, at the instruction index where
    /// their last read is behind them.
    fn releaseFpReg(self: *Arm64Compiler, reg: u5) void {
        if (reg < fp_value_reg_base) return;
        if (reg >= fp_value_reg_base + fp_value_reg_count) return;
        if (self.fp_home_regs[reg]) return;
        if (self.fp_reg_owner[reg] != null) return;
        self.used_fp_regs[reg] = false;
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
            else => return self.refuse(@src()),
        }
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
            // A SPILLED register is not free, however `used_regs` reads.
            //
            // `spillReg` stores the victim and clears `used_regs`, but the slot
            // that owned it still MAPS to it, and `ensureRegLive` reloads into
            // THAT SAME register. So handing it out here gives two owners one
            // register, and the later reload silently overwrites whichever
            // arrived second. Disassembled from a 3-read program answering 0:
            //
            //     add x22, x23, x25     ; a + b
            //     str x28, [sp, #0x8]   ; spill x28
            //     add x28, x22, x27     ; result computed INTO the freed x28
            //     ldr x28, [sp, #0x8]   ; reload clobbers it
            //     mov x0,  x28          ; returns the spilled garbage
            //
            // The real repair is a reload that may land in a DIFFERENT register
            // — `ensureRegLive` returning one instead of assuming the original.
            // That is an allocator change. Until then this keeps a spilled
            // register reserved to its owner: exhaustion then REFUSES, and a
            // refusal is a bail while the alternative is a wrong answer.
            if (self.spilled_regs.contains(reg)) continue;
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
        // SCVTF from a **64-bit** GPR is 0x9e620000. This read 0x1e620000, which
        // is the 32-bit source form, while both callers hand it an x register:
        // anything at or above 2^32 would have converted from its low half. The
        // asm text said `scvtf d, x` either way, so only a byte-level oracle
        // could tell the two apart -- `zig build isa-fidelity` is that oracle.
        try self.emitFmt(0x9e620000 | (@as(u32, xreg) << 5) | @as(u32, dreg), "scvtf d{d}, x{d}", .{ dreg, xreg });
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

    fn loadStackField(self: *Arm64Compiler, key: []const u8) Error!u5 {
        const slot = self.fp_stack_slots.get(key) orelse return self.undefinedKey(@src(), "fp stack slot", key);
        const reg = try self.allocReg();
        try self.emitLdrSp(reg, slot.off);
        return reg;
    }

    fn releaseReg(self: *Arm64Compiler, reg: u5) void {
        if (reg >= 9 and reg < 29) {
            self.used_regs[reg] = false;
        }
    }

    fn assignRecordFromAbiRegs(self: *Arm64Compiler, base: []const u8, desc: ScalRecordDesc) Error!void {
        const n = desc.field_names.len;
        if (n == 0 or n > 8) return self.refuse(@src());

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
        if (n == 0 or n > 8) return self.refuse(@src());
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

    fn emitBl(self: *Arm64Compiler, target: []const u8) Error!void {
        const offset: u32 = @intCast(self.code.items.len);
        const link_name = try linkerSymbolName(self.alloc, target);
        defer self.alloc.free(link_name);
        const owned_target = try self.alloc.dupe(u8, link_name);
        errdefer self.alloc.free(owned_target);
        try self.emitFmt(0x94000000, "bl _{s}", .{link_name});
        try self.call_patches.append(self.alloc, .{ .offset = offset, .target = owned_target });
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
        var fpr: u5 = fp_value_reg_base;
        while (fpr < fp_value_reg_base + fp_value_reg_count) : (fpr += 1) {
            if (self.used_fp_regs[fpr]) {
                save_set.fp_regs[save_set.fp_count] = fpr;
                save_set.fp_count += 1;
            }
        }
        var slots: u16 = @as(u16, save_set.count) + 1 + @as(u16, save_set.fp_count);
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
        // FP block sits after the GP block and x30.
        var fo: u16 = (@as(u16, save_set.count) + 1) * 8;
        var j: u5 = 0;
        while (j < save_set.fp_count) : ({
            j += 1;
            fo += 8;
        }) {
            try self.emitStrSpFp(save_set.fp_regs[j], fo);
        }
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
        var fo: u16 = (@as(u16, save_set.count) + 1) * 8;
        var j: u5 = 0;
        while (j < save_set.fp_count) : ({
            j += 1;
            fo += 8;
        }) {
            try self.emitLdrSpFp(save_set.fp_regs[j], fo);
        }
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
        if (offset % 8 != 0 or offset / 8 > 4095) return self.refuse(@src());
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
        const slot = self.fp_stack_slots.get(key) orelse return self.refuse(@src());
        return slot.off;
    }

    /// `add xd, sp, #imm` — materialize the address of a frame slot region.
    fn emitAddSpImm(self: *Arm64Compiler, dst: u5, bytes: u16) Error!void {
        if (bytes > 4095) return self.refuse(@src());
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
    /// Record that a temp/slot holds an FP register.
    fn markFpTemp(self: *Arm64Compiler, id: ?u32) Error!void {
        const t = id orelse return;
        try self.fp_temps.put(self.alloc, t, {});
    }

    /// Whether this operand is resident in the FP file. An `.f64` immediate
    /// counts: it materialises with `fmov`, not `mov`.
    fn valueIsFp(self: *const Arm64Compiler, v: dnir.Value) bool {
        return switch (v) {
            .f64 => true,
            .temp => |t| self.fp_temps.contains(t),
            .local => |sl| self.fp_temps.contains(sl),
            else => false,
        };
    }

    /// The FP VALUE range: d16-d30. Deliberately disjoint from d0-d7.
    ///
    /// This mirrors `allocRegExcluding`, which starts at x9 precisely so that a
    /// value never lives in an argument or result register. The FP allocator
    /// started at d0 instead, so values lived in the staging registers and were
    /// destroyed by any outgoing call — the defect `requireSafeFpStaging` in
    /// dnir_lower.zig currently refuses programs to avoid.
    ///
    /// d16-d31 are the caller-saved half of the FP file, so using them costs no
    /// prologue work. d8-d15 are deliberately skipped: they are CALLEE-saved
    /// (their low 64 bits must be preserved), so taking one without a
    /// prologue/epilogue save is a silent ABI violation rather than a refusal.
    /// d31 is left out as the staging scratch for a spill/restore that needs a
    /// register of its own.
    ///
    /// An earlier attempt simply widened the old d0-d7 pool to include d16-d31
    /// WITHOUT moving values out of the argument range or adding caller-save.
    /// That turned mandelbrot's honest DNB003 refusal into an infinite loop
    /// (gap[057]): more registers only meant the program got far enough to be
    /// wrong. Order matters — values out of the argument range first, then
    /// caller-save, then capacity.
    /// CAPACITY IS DELIBERATELY UNCHANGED AT EIGHT. d24-d30 are free and this
    /// loop could take them in one character, and it must not yet.
    ///
    /// `releaseFpReg` is still a no-op, so this is not allocation with liveness
    /// — it is a monotonic cursor, and every extra register only buys a longer
    /// run before the same wall. Widening it to 15 made
    /// `examples/mandelbrot.duo` compile and then HANG, producing no output,
    /// which is strictly worse than the DNB003 refusal it replaced. That is the
    /// second time capacity has been taken before correctness here (gap[057]
    /// records the first).
    ///
    /// So: same eight registers, different eight registers. The move that
    /// mattered was OUT of the argument range, not upward in count. Raising
    /// this bound is step three of three, and step two is liveness.
    const fp_value_reg_base: u5 = 16;
    const fp_value_reg_count: u5 = 15;

    fn allocFpReg(self: *Arm64Compiler) Error!u5 {
        var reg: u5 = fp_value_reg_base;
        while (reg < fp_value_reg_base + fp_value_reg_count) : (reg += 1) {
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
            self.diagnostic.record(@src(), patch.target);
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

const CheckedApplication = semantic_graph.ApplicationFact;

fn checkedApplications(
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error![]const CheckedApplication {
    const applications = graph.applications();
    for (applications) |*application| {
        if (graph.application(application.application) != application or
            graph.applicationArguments(application.application) == null or
            graph.applicationResults(application.application) == null)
        {
            return invalidFactsWith(diagnostic, @src(), "application-facts");
        }
    }
    return applications;
}

fn applicationResult(
    graph: *const semantic_graph.SemanticGraph,
    application: CheckedApplication,
    diagnostic: *Diagnostic,
) Error!semantic_graph.id {
    const results = graph.applicationResults(application.application) orelse
        return invalidFactsWith(diagnostic, @src(), "application-results");
    if (results.len != 1) return invalidFactsWith(diagnostic, @src(), "application-result-count");
    return results[0];
}

fn optionalIdEql(a: ?semantic_graph.id, b: ?semantic_graph.id) bool {
    if (a == null or b == null) return a == null and b == null;
    return std.meta.eql(a.?, b.?);
}

fn validateDnirApplications(
    alloc: std.mem.Allocator,
    module: dnir.Module,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error!void {
    const context = module.graph orelse return invalidFactsWith(diagnostic, @src(), "missing-graph-context");
    if (context != graph) return invalidFactsWith(diagnostic, @src(), "graph-context-mismatch");
    const applications = try checkedApplications(graph, diagnostic);
    var seen: std.AutoHashMapUnmanaged(semantic_graph.id, void) = .empty;
    defer seen.deinit(alloc);

    const LinkTarget = struct {
        id: semantic_graph.id,
        linkage: []const u8,
        result_record: ?[]const u8,
    };
    var targets: std.AutoHashMapUnmanaged(semantic_graph.id, LinkTarget) = .empty;
    defer targets.deinit(alloc);
    var link_symbols: std.StringHashMapUnmanaged(void) = .empty;
    defer link_symbols.deinit(alloc);
    for (module.functions) |function| {
        const id = function.id orelse continue;
        const symbol_slot = try link_symbols.getOrPut(alloc, function.name);
        if (symbol_slot.found_existing) return invalidFactsWith(diagnostic, @src(), "duplicate-link-symbol");
        const target = try targets.getOrPut(alloc, id);
        if (target.found_existing) return invalidFactsWith(diagnostic, @src(), "function-fact-collision");
        target.value_ptr.* = .{
            .id = id,
            .linkage = function.name,
            .result_record = function.ret_record,
        };
    }

    for (module.functions) |function| {
        var instruction_index: u32 = 0;
        for (function.blocks) |block| {
            for (block.instrs) |instruction| {
                defer instruction_index += 1;
                const fact_count: u2 = @as(u2, @intFromBool(instruction.relation != null)) +
                    @as(u2, @intFromBool(instruction.application != null)) +
                    @as(u2, @intFromBool(instruction.value != null));
                if (fact_count == 0) {
                    if (instruction.subject != null or instruction.realization_start != null) {
                        return invalidFactsWith(diagnostic, @src(), "orphan-realization-lineage");
                    }
                    if (instruction.op == .call_direct) {
                        return invalidFactsWith(diagnostic, @src(), "missing-application-lineage");
                    }
                    if (instruction.op == .call_extern) {
                        return invalidFactsWith(
                            diagnostic,
                            @src(),
                            "missing-foreign-application-lineage",
                        );
                    }
                    continue;
                }
                if (fact_count != 3) return invalidFactsWith(diagnostic, @src(), "partial-application-lineage");
                const realization_start = instruction.realization_start orelse
                    return invalidFactsWith(diagnostic, @src(), "partial-realization-lineage");
                if (realization_start > instruction_index) {
                    return invalidFactsWith(diagnostic, @src(), "invalid-realization-start");
                }

                // A checked call-to-constant or tail-call rewrite needs a
                // semantic transform witness that the current graph does not
                // publish. Until then, only the untransformed call is lawful.
                if (instruction.op != .call_direct) {
                    return invalidFactsWith(diagnostic, @src(), "unwitnessed-application-transform");
                }

                const application = graph.application(instruction.application.?) orelse
                    return invalidFactsWith(diagnostic, @src(), "unknown-application-lineage");
                const result = try applicationResult(graph, application.*, diagnostic);
                if (function.id == null or !std.meta.eql(function.id.?, application.caller)) {
                    return invalidFactsWith(diagnostic, @src(), "application-caller-mismatch");
                }
                if (!std.meta.eql(application.application, instruction.application.?) or
                    !std.meta.eql(application.relation, instruction.relation.?) or
                    !std.meta.eql(result, instruction.value.?) or
                    !optionalIdEql(application.subject, instruction.subject) or
                    !application.descriptor.eql(instruction.ty))
                {
                    return invalidFactsWith(diagnostic, @src(), "application-fact-mismatch");
                }
                const target = targets.get(application.relation) orelse
                    return invalidFactsWith(diagnostic, @src(), "missing-foreign-application-lineage");
                if (!std.meta.eql(target.id, application.relation)) {
                    return invalidFactsWith(diagnostic, @src(), "application-link-target");
                }
                if (!std.mem.eql(u8, target.linkage, instruction.callee)) {
                    return invalidFactsWith(diagnostic, @src(), "application-link-symbol");
                }
                if (target.result_record) |record| {
                    if (!std.mem.eql(u8, record, instruction.record)) {
                        return invalidFactsWith(diagnostic, @src(), "application-result-abi");
                    }
                } else if (instruction.record.len != 0) {
                    return invalidFactsWith(diagnostic, @src(), "application-result-abi");
                }
                const use = try seen.getOrPut(alloc, application.application);
                if (use.found_existing) return invalidFactsWith(diagnostic, @src(), "application-realization-count");
            }
        }
    }

    if (seen.count() != applications.len) return invalidFactsWith(diagnostic, @src(), "application-realization-count");
}

fn validateMachineLineage(
    alloc: std.mem.Allocator,
    output: Arm64Output,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error!void {
    if (output.graph != graph) return invalidFactsWith(diagnostic, @src(), "machine-graph-context");
    const applications = try checkedApplications(graph, diagnostic);
    if (output.lineage.len == 0 and applications.len == 0) return;
    if (output.lineage.len != applications.len) {
        return invalidFactsWith(diagnostic, @src(), "machine-lineage-count");
    }
    var seen: std.AutoHashMapUnmanaged(semantic_graph.id, void) = .empty;
    defer seen.deinit(alloc);
    for (output.lineage) |lineage| {
        const application = graph.application(lineage.application) orelse
            return invalidFactsWith(diagnostic, @src(), "machine-lineage-unknown");
        const result = try applicationResult(graph, application.*, diagnostic);
        if (!std.meta.eql(lineage.application, application.application) or
            !std.meta.eql(lineage.relation, application.relation) or
            !std.meta.eql(lineage.value, result) or
            !optionalIdEql(lineage.subject, application.subject) or
            !lineage.descriptor.eql(application.descriptor) or
            !std.meta.eql(lineage.caller, application.caller))
        {
            return invalidFactsWith(diagnostic, @src(), "machine-lineage-mismatch");
        }
        if (lineage.instruction_start >= lineage.instruction_end) {
            return invalidFactsWith(diagnostic, @src(), "machine-lineage-instruction-range");
        }
        if (lineage.text_start >= lineage.text_end or @as(usize, lineage.text_end) > output.text.len) {
            return invalidFactsWith(diagnostic, @src(), "machine-lineage-range");
        }
        const slot = try seen.getOrPut(alloc, lineage.application);
        if (slot.found_existing) return invalidFactsWith(diagnostic, @src(), "machine-lineage-count");
    }
    if (seen.count() != applications.len) return invalidFactsWith(diagnostic, @src(), "machine-lineage-count");
}

fn emitArm64FromDnir(alloc: std.mem.Allocator, m: dnir.Module, process_entry: ?[]const u8, diagnostic: *Diagnostic) Error!Arm64Output {
    var records = try collectF64RecordsFromDnir(alloc, m);
    defer freeF64Records(alloc, &records);
    var scal_records = try collectScalRecordsFromDnir(alloc, m);
    defer freeScalRecords(alloc, &scal_records);
    var compiler = Arm64Compiler{
        .alloc = alloc,
        .diagnostic = diagnostic,
        .f64_records = &records,
        .scal_records = &scal_records,
        .process_entry = process_entry,
    };
    defer compiler.deinit();
    try compiler.compileDnirModule(m);
    var output = try compiler.finish();
    output.graph = m.graph;
    return output;
}

fn collectScalRecordsFromDnir(alloc: std.mem.Allocator, m: dnir.Module) Error!ScalRecordMap {
    var map: ScalRecordMap = .empty;
    errdefer freeScalRecords(alloc, &map);
    for (m.records) |r| {
        var has_f64 = false;
        for (r.kinds) |k| {
            if (k == .f64) {
                has_f64 = true;
                break;
            }
        }
        if (has_f64) continue;
        try putScalRecordFromDnir(alloc, &map, r);
    }
    return map;
}

fn putScalRecordFromDnir(alloc: std.mem.Allocator, map: *ScalRecordMap, record: dnir.RecordDesc) Error!void {
    var kinds: std.ArrayListUnmanaged(ScalFieldKind) = .empty;
    defer kinds.deinit(alloc);
    for (record.kinds) |kind| {
        try kinds.append(alloc, if (kind == .str) .str else .i64);
    }
    const owned_kinds = try kinds.toOwnedSlice(alloc);
    errdefer alloc.free(owned_kinds);
    const entry = try map.getOrPut(alloc, record.name);
    if (entry.found_existing) return error.DuplicateSymbol;
    entry.value_ptr.* = .{
        .field_names = record.fields,
        .field_kinds = owned_kinds,
    };
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
        const entry = try map.getOrPut(alloc, r.name);
        if (entry.found_existing) return error.DuplicateSymbol;
        entry.value_ptr.* = .{ .field_names = r.fields };
    }
    return map;
}

fn collectDnirRecordMapsAllocationProbe(alloc: std.mem.Allocator) !void {
    const scalar_fields = [_][]const u8{ "count", "label" };
    const scalar_kinds = [_]dnir.FieldKind{ .i64, .str };
    const float_fields = [_][]const u8{ "x", "y" };
    const float_kinds = [_]dnir.FieldKind{ .f64, .f64 };
    const records = [_]dnir.RecordDesc{
        .{ .name = "Scalar", .fields = &scalar_fields, .kinds = &scalar_kinds },
        .{ .name = "Float", .fields = &float_fields, .kinds = &float_kinds },
    };
    const module: dnir.Module = .{ .functions = &.{}, .records = &records };
    var floats = try collectF64RecordsFromDnir(alloc, module);
    defer freeF64Records(alloc, &floats);
    var scalars = try collectScalRecordsFromDnir(alloc, module);
    defer freeScalRecords(alloc, &scalars);
    try std.testing.expect(scalars.get("Scalar").?.field_names.ptr == scalar_fields[0..].ptr);
    try std.testing.expect(floats.get("Float").?.field_names.ptr == float_fields[0..].ptr);
}

test "native backend: DNIR record projections release every failed allocation" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        collectDnirRecordMapsAllocationProbe,
        .{},
    );
}

fn emitArm64ModuleWithGraph(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    process_entry: ?[]const u8,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error!Arm64Output {
    _ = try checkedApplications(graph, diagnostic);
    if (graph.unresolvedApplicationCount(null) != 0) {
        return invalidFactsWith(diagnostic, @src(), "unresolved-application-facts");
    }

    const lowered_result = dnir_lower.lowerModuleWithGraphObserved(alloc, mod, graph, &diagnostic.lowering);
    if (lowered_result) |lowered| {
        var dnir_mut = lowered;
        defer dnir.deinitModule(alloc, dnir_mut);
        try validateDnirApplications(alloc, dnir_mut, graph, diagnostic);
        if (dnir.moduleIsNativeDirectReady(dnir_mut)) {
            if (region_graph.buildModuleRegions(alloc, dnir_mut)) |initial_regions| {
                defer region_graph.freeModuleRegions(alloc, initial_regions);
                const transform_report = region_transform.applyModuleRegionTransformsWithGraph(
                    alloc,
                    &dnir_mut,
                    initial_regions,
                    graph,
                ) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    if (err == error.CoordinateOverflow) return transformFailure(diagnostic, @src(), err);
                    return transformFailure(diagnostic, @src(), err);
                };
                _ = transform_report;
            } else |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.CoordinateOverflow => return recordRefusalWith(
                    diagnostic,
                    @src(),
                    "region-coordinate-capacity",
                ),
            }

            // Transformation changes realization, not meaning. Revalidate the
            // actual DNIR that will be emitted before selecting realization.
            try validateDnirApplications(alloc, dnir_mut, graph, diagnostic);
            if (realization.buildDeferredFromGraph(alloc, graph, "<native>")) |plan_val| {
                var plan = plan_val;
                defer plan.deinit(alloc);
                realization.commitModuleForTarget(alloc, &plan, "native") catch |err| return err;
            } else |err| return err;

            var output = try emitArm64FromDnir(alloc, dnir_mut, process_entry, diagnostic);
            errdefer output.deinit(alloc);
            output.graph = graph;
            try validateMachineLineage(alloc, output, graph, diagnostic);
            return output;
        }
        return recordRefusalWith(diagnostic, @src(), "graph-direct-not-ready");
    } else |e| {
        if (std.c.getenv("DUO_DNIR_TRACE") != null) {
            std.debug.print("DUO_DNIR_TRACE: graph DNIR lowering refused with {s}\n", .{@errorName(e)});
            if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
        }
        return switch (e) {
            error.OutOfMemory => error.OutOfMemory,
            error.GraphFactsInvalid => invalidFactsWith(diagnostic, @src(), "graph-dnir-facts"),
            error.UnsupportedConstruct => recordRefusalWith(diagnostic, @src(), "graph-dnir-unsupported"),
        };
    }
}

fn machOTextOffset(cstring_len: usize, bss_size: u64) usize {
    const header_size: usize = 32;
    const segment_size: usize = 72;
    const section_size: usize = 80;
    const symtab_size: usize = 24;
    const build_version_size: usize = 24;
    const nsects: usize = (if (cstring_len > 0) @as(usize, 2) else 1) +
        (if (bss_size > 0) @as(usize, 1) else 0);
    return header_size + segment_size + section_size * nsects + symtab_size + build_version_size;
}

fn emitMachOArm64Object(alloc: std.mem.Allocator, text: []const u8, cstring: []const u8, symbols: []const Symbol, relocations: []const Relocation, bss_size: u64) Error![]u8 {
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
    const text_offset = machOTextOffset(cstring.len, bss_size);
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

fn expectLineageCallTarget(
    alloc: std.mem.Allocator,
    output: Arm64Output,
    module: dnir.Module,
    lineage: MachineLineage,
) !void {
    var target_function: ?dnir.Function = null;
    for (module.functions) |function| {
        if (function.id != null and std.meta.eql(function.id.?, lineage.relation)) {
            target_function = function;
            break;
        }
    }
    const function = target_function orelse return error.TestExpectedEqual;
    const link_name = try linkerSymbolName(alloc, function.name);
    defer alloc.free(link_name);
    var target_offset: ?u32 = null;
    for (output.symbols) |symbol| {
        if (!symbol.defined or symbol.section != 1 or !std.mem.eql(u8, symbol.name, link_name)) continue;
        target_offset = symbol.offset;
        break;
    }

    var call_count: usize = 0;
    var offset: u32 = lineage.text_start;
    while (offset + 4 <= lineage.text_end) : (offset += 4) {
        const word = std.mem.readInt(u32, output.text[offset..][0..4], .little);
        if (word & 0xfc00_0000 != 0x9400_0000) continue;
        const shifted: i32 = @bitCast((word & 0x03ff_ffff) << 6);
        const destination = @as(i64, offset) + @as(i64, shifted >> 6) * 4;
        try std.testing.expectEqual(@as(i64, target_offset orelse return error.TestExpectedEqual), destination);
        call_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), call_count);
}

fn stageCompactGpApplication(
    alloc: std.mem.Allocator,
    compact: dnir.Module,
    application: semantic_graph.id,
) !dnir.Module {
    const functions = try alloc.dupe(dnir.Function, compact.functions);
    var found = false;
    for (functions) |*function| {
        var flat_index: u32 = 0;
        for (function.blocks) |block| {
            for (block.instrs) |instruction| {
                if (instruction.op == .br) return error.TestUnexpectedResult;
            }
        }

        const blocks = try alloc.dupe(dnir.Block, function.blocks);
        function.blocks = blocks;
        for (blocks) |*block| {
            for (block.instrs, 0..) |instruction, instruction_index| {
                if (instruction.application == null or
                    !std.meta.eql(instruction.application.?, application))
                {
                    flat_index += 1;
                    continue;
                }
                if (found or instruction.op != .call_direct or
                    instruction.realization_start == null or
                    instruction.realization_start.? != flat_index)
                {
                    return error.TestUnexpectedResult;
                }
                switch (instruction.lhs) {
                    .void, .f64 => return error.TestUnexpectedResult,
                    else => {},
                }

                const staged = try alloc.alloc(dnir.Instr, block.instrs.len + 1);
                @memcpy(staged[0..instruction_index], block.instrs[0..instruction_index]);
                staged[instruction_index] = .{
                    .op = .mov_arg,
                    .result = 0,
                    .lhs = instruction.lhs,
                    .ty = .i64,
                };
                staged[instruction_index + 1] = instruction;
                staged[instruction_index + 1].lhs = .void;
                staged[instruction_index + 1].realization_start = flat_index;
                @memcpy(
                    staged[instruction_index + 2 ..],
                    block.instrs[instruction_index + 1 ..],
                );
                block.instrs = staged;
                found = true;
                flat_index += 2;
            }
        }
    }
    if (!found) return error.TestExpectedEqual;
    var staged = compact;
    staged.functions = functions;
    return staged;
}

fn liftCheckedTestGraph(
    module: *const ast.Module,
    checked: *const Sema,
    graph: *semantic_graph.SemanticGraph,
) !void {
    _ = try graph.liftModuleWithCheckedCalls(module, checked, module.file);
}

fn emitCheckedTestAssembly(
    alloc: std.mem.Allocator,
    module: *const ast.Module,
    graph: *semantic_graph.SemanticGraph,
    process_entry: ?[]const u8,
) !AssemblyWithLineage {
    var diagnostic: Diagnostic = .{};
    if (process_entry) |entry| {
        return emitAssemblyForExecutableWithGraphLineageObserved(
            alloc,
            module,
            entry,
            graph,
            &diagnostic,
        );
    }
    return emitAssemblyWithGraphLineageObserved(
        alloc,
        module,
        "native-asm",
        graph,
        &diagnostic,
    );
}

fn emitCheckedTestObject(
    alloc: std.mem.Allocator,
    module: *const ast.Module,
    graph: *semantic_graph.SemanticGraph,
) !ObjectWithLineage {
    var diagnostic: Diagnostic = .{};
    return emitObjectWithGraphLineageObserved(
        alloc,
        module,
        "native-object",
        graph,
        &diagnostic,
    );
}

fn expectCheckedTestSemanticFailure(
    alloc: std.mem.Allocator,
    module: *const ast.Module,
    checked: *const Sema,
    expected: []const u8,
    expected_lowering: ?[]const u8,
) !void {
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(module, checked, &graph);
    var diagnostic: Diagnostic = .{};
    try std.testing.expectError(
        error.SemanticFactsInvalid,
        emitAssemblyWithGraphLineageObserved(
            alloc,
            module,
            "native-asm",
            &graph,
            &diagnostic,
        ),
    );
    try std.testing.expectEqualStrings(expected, diagnostic.note().?);
    if (expected_lowering) |note| {
        try std.testing.expectEqualStrings(note, diagnostic.lowering.note().?);
    } else {
        try std.testing.expect(diagnostic.lowering.note() == null);
    }
}

fn expectCheckedTestPhysicalRefusal(
    alloc: std.mem.Allocator,
    module: *const ast.Module,
    checked: *const Sema,
    expected: []const u8,
) !void {
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(module, checked, &graph);
    var diagnostic: Diagnostic = .{};
    try std.testing.expectError(
        error.UnsupportedProgram,
        emitAssemblyWithGraphLineageObserved(
            alloc,
            module,
            "native-asm",
            &graph,
            &diagnostic,
        ),
    );
    try std.testing.expectEqualStrings(expected, diagnostic.note().?);
}

test "native backend: folded module provenance does not select constant realization" {
    var diagnostic: Diagnostic = .{};
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const plain_instructions = [_]dnir.Instr{
        .{ .op = .@"const", .result = 0, .lhs = .{ .i64 = 14 }, .ty = .i64 },
        .{ .op = .ret, .lhs = .{ .temp = 0 }, .ty = .i64 },
    };
    const qualified_instructions = [_]dnir.Instr{
        .{
            .op = .@"const",
            .result = 0,
            .lhs = .{ .i64 = 14 },
            .req_alias = "token",
            .field = "kindfun",
            .ty = .i64,
        },
        .{ .op = .ret, .lhs = .{ .temp = 0 }, .ty = .i64 },
    };
    const plain_blocks = [_]dnir.Block{.{ .instrs = &plain_instructions }};
    const qualified_blocks = [_]dnir.Block{.{ .instrs = &qualified_instructions }};
    const plain_functions = [_]dnir.Function{.{
        .name = "main",
        .ret = .i64,
        .blocks = &plain_blocks,
    }};
    const qualified_functions = [_]dnir.Function{.{
        .name = "main",
        .ret = .i64,
        .blocks = &qualified_blocks,
    }};
    const plain = dnir.Module{ .functions = &plain_functions };
    const qualified = dnir.Module{ .functions = &qualified_functions };

    var plain_output = try emitArm64FromDnir(alloc, plain, null, &diagnostic);
    defer plain_output.deinit(alloc);
    var qualified_output = try emitArm64FromDnir(alloc, qualified, null, &diagnostic);
    defer qualified_output.deinit(alloc);
    try std.testing.expect(plain_output.graph == null);
    try std.testing.expectEqual(@as(usize, 0), plain_output.lineage.len);
    try std.testing.expect(qualified_output.graph == null);
    try std.testing.expectEqual(@as(usize, 0), qualified_output.lineage.len);
    try std.testing.expectEqualSlices(u8, plain_output.text, qualified_output.text);
    try std.testing.expectEqualStrings(plain_output.asm_text, qualified_output.asm_text);

    const plain_object = try emitMachOArm64Object(
        alloc,
        plain_output.text,
        plain_output.cstring,
        plain_output.symbols,
        plain_output.relocations,
        plain_output.bss_size,
    );
    defer alloc.free(plain_object);
    const qualified_object = try emitMachOArm64Object(
        alloc,
        qualified_output.text,
        qualified_output.cstring,
        qualified_output.symbols,
        qualified_output.relocations,
        qualified_output.bss_size,
    );
    defer alloc.free(qualified_object);
    try std.testing.expectEqualSlices(u8, plain_object, qualified_object);
}

test "native backend: compact checked call preserves staged machine realization" {
    var diagnostic: Diagnostic = .{};
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\observe: i64 = (value: i64)
        \\    value
        \\main: i64 = ()
        \\    observe(40 + 2)
    ;
    var lexer = Lexer.init(source, "gp-inline.id");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&ast_module);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "gp-inline.id");
    const applications = try checkedApplications(&graph, &diagnostic);
    try std.testing.expectEqual(@as(usize, 1), applications.len);

    const compact = try dnir_lower.lowerModuleWithGraph(alloc, &ast_module, &graph);
    try validateDnirApplications(alloc, compact, &graph, &diagnostic);
    var compact_call_count: usize = 0;
    var compact_mov_count: usize = 0;
    for (compact.functions) |function| {
        var instruction_index: u32 = 0;
        for (function.blocks) |block| {
            for (block.instrs) |instruction| {
                if (instruction.op == .mov_arg) compact_mov_count += 1;
                if (instruction.application != null) {
                    compact_call_count += 1;
                    try std.testing.expectEqual(dnir.Op.call_direct, instruction.op);
                    try std.testing.expectEqual(instruction_index, instruction.realization_start.?);
                    switch (instruction.lhs) {
                        .void, .f64 => return error.TestUnexpectedResult,
                        else => {},
                    }
                }
                instruction_index += 1;
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 1), compact_call_count);
    try std.testing.expectEqual(@as(usize, 0), compact_mov_count);

    const staged = try stageCompactGpApplication(alloc, compact, applications[0].application);
    try validateDnirApplications(alloc, staged, &graph, &diagnostic);
    var compact_output = try emitArm64FromDnir(alloc, compact, null, &diagnostic);
    defer compact_output.deinit(alloc);
    var staged_output = try emitArm64FromDnir(alloc, staged, null, &diagnostic);
    defer staged_output.deinit(alloc);
    try validateMachineLineage(alloc, compact_output, &graph, &diagnostic);
    try validateMachineLineage(alloc, staged_output, &graph, &diagnostic);
    try std.testing.expectEqualSlices(u8, staged_output.text, compact_output.text);
    try std.testing.expectEqualStrings(staged_output.asm_text, compact_output.asm_text);
    try std.testing.expectEqual(@as(usize, 1), compact_output.lineage.len);
    try std.testing.expectEqual(
        compact_output.lineage[0].instruction_start + 1,
        compact_output.lineage[0].instruction_end,
    );
    try std.testing.expectEqual(
        staged_output.lineage[0].instruction_start + 2,
        staged_output.lineage[0].instruction_end,
    );
    try std.testing.expectEqual(staged_output.lineage[0].text_start, compact_output.lineage[0].text_start);
    try std.testing.expectEqual(staged_output.lineage[0].text_end, compact_output.lineage[0].text_end);
    try expectLineageCallTarget(alloc, compact_output, compact, compact_output.lineage[0]);

    const compact_object = try emitMachOArm64Object(
        alloc,
        compact_output.text,
        compact_output.cstring,
        compact_output.symbols,
        compact_output.relocations,
        compact_output.bss_size,
    );
    defer alloc.free(compact_object);
    const staged_object = try emitMachOArm64Object(
        alloc,
        staged_output.text,
        staged_output.cstring,
        staged_output.symbols,
        staged_output.relocations,
        staged_output.bss_size,
    );
    defer alloc.free(staged_object);
    try std.testing.expectEqualSlices(u8, staged_object, compact_object);
}

test "native backend: nested compact checked calls retain direct region use and distinct lineage" {
    var diagnostic: Diagnostic = .{};
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\inner: i64 = (value: i64)
        \\    value
        \\outer: i64 = (value: i64)
        \\    value
        \\main: i64 = ()
        \\    outer(inner(42))
    ;
    var lexer = Lexer.init(source, "nested-gp-inline.id");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&ast_module);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "nested-gp-inline.id");
    const applications = try checkedApplications(&graph, &diagnostic);
    try std.testing.expectEqual(@as(usize, 2), applications.len);
    try std.testing.expect(!std.meta.eql(applications[0].application, applications[1].application));
    try std.testing.expect(!std.meta.eql(
        try applicationResult(&graph, applications[0], &diagnostic),
        try applicationResult(&graph, applications[1], &diagnostic),
    ));

    const module = try dnir_lower.lowerModuleWithGraph(alloc, &ast_module, &graph);
    try validateDnirApplications(alloc, module, &graph, &diagnostic);
    var call_applications: [2]semantic_graph.id = undefined;
    var call_count: usize = 0;
    for (module.functions) |function| {
        var instruction_index: u32 = 0;
        for (function.blocks) |block| {
            for (block.instrs) |instruction| {
                try std.testing.expect(instruction.op != .mov_arg);
                if (instruction.application != null) {
                    if (call_count >= call_applications.len) return error.TestUnexpectedResult;
                    call_applications[call_count] = instruction.application.?;
                    call_count += 1;
                    try std.testing.expectEqual(instruction_index, instruction.realization_start.?);
                    switch (instruction.lhs) {
                        .void, .f64 => return error.TestUnexpectedResult,
                        else => {},
                    }
                }
                instruction_index += 1;
            }
        }
    }
    try std.testing.expectEqual(call_applications.len, call_count);

    const regions = try region_graph.buildModuleRegions(alloc, module);
    defer region_graph.freeModuleRegions(alloc, regions);
    try region_graph.validateModuleRegions(alloc, regions, &graph, module);
    var inner_coordinate: ?u32 = null;
    var outer_coordinate: ?u32 = null;
    var direct_use = false;
    for (module.functions, regions.regions) |function, region| {
        var coordinate: u32 = 1;
        for (function.blocks) |block| {
            for (block.instrs) |instruction| {
                if (instruction.application) |application| {
                    if (std.meta.eql(application, call_applications[0])) inner_coordinate = coordinate;
                    if (std.meta.eql(application, call_applications[1])) outer_coordinate = coordinate;
                }
                coordinate += 1;
            }
        }
        if (inner_coordinate != null and outer_coordinate != null) {
            for (region.dependencies) |dependency| {
                if (dependency.producer == inner_coordinate.? and
                    dependency.consumer == outer_coordinate.?)
                {
                    direct_use = true;
                }
            }
        }
    }
    try std.testing.expect(direct_use);

    var output = try emitArm64FromDnir(alloc, module, null, &diagnostic);
    defer output.deinit(alloc);
    try validateMachineLineage(alloc, output, &graph, &diagnostic);
    try std.testing.expectEqual(@as(usize, 2), output.lineage.len);
    var inner_lineage: ?MachineLineage = null;
    var outer_lineage: ?MachineLineage = null;
    for (output.lineage) |lineage| {
        try std.testing.expectEqual(lineage.instruction_start + 1, lineage.instruction_end);
        try expectLineageCallTarget(alloc, output, module, lineage);
        if (std.meta.eql(lineage.application, call_applications[0])) inner_lineage = lineage;
        if (std.meta.eql(lineage.application, call_applications[1])) outer_lineage = lineage;
    }
    const inner = inner_lineage orelse return error.TestExpectedEqual;
    const outer = outer_lineage orelse return error.TestExpectedEqual;
    try std.testing.expect(inner.instruction_end <= outer.instruction_start);
    try std.testing.expect(inner.text_end <= outer.text_start);
}

test "native backend: checked subject fact reaches object bytes" {
    var diagnostic: Diagnostic = .{};
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\observe: i64 = (subject: i64, left: i64, right: i64)
        \\    subject + left + right
        \\main: i64 = ()
        \\    40:observe(1, 1)
    ;
    var lexer = Lexer.init(source, "machine-lineage.duo");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&module);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, "machine-lineage.duo");
    const applications = try checkedApplications(&graph, &diagnostic);
    try std.testing.expectEqual(@as(usize, 1), applications.len);
    try std.testing.expect(applications[0].subject != null);

    const projected = try dnir_lower.lowerModuleWithGraph(alloc, &module, &graph);
    var instruction_index: u32 = 0;
    var spans_abi_staging = false;
    var dnir_caller: ?semantic_graph.id = null;
    var dnir_subject: ?semantic_graph.id = null;
    for (projected.functions) |function| {
        instruction_index = 0;
        for (function.blocks) |block| {
            for (block.instrs) |instruction| {
                if (instruction.application != null) {
                    spans_abi_staging = instruction.realization_start.? < instruction_index;
                    dnir_caller = function.id;
                    dnir_subject = instruction.subject;
                }
                instruction_index += 1;
            }
        }
    }
    try std.testing.expect(spans_abi_staging);
    try std.testing.expectEqual(applications[0].caller, dnir_caller.?);
    try std.testing.expect(std.meta.eql(applications[0].subject.?, dnir_subject.?));

    var output = try emitArm64ModuleWithGraph(alloc, &module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 1), output.lineage.len);
    const text_lineage = output.lineage[0];
    try std.testing.expectEqual(applications[0].relation, text_lineage.relation);
    try std.testing.expectEqual(applications[0].application, text_lineage.application);
    try std.testing.expectEqual(try applicationResult(&graph, applications[0], &diagnostic), text_lineage.value);
    try std.testing.expect(std.meta.eql(applications[0].subject.?, text_lineage.subject.?));
    try std.testing.expect(applications[0].descriptor.eql(text_lineage.descriptor));
    try std.testing.expectEqual(applications[0].caller, text_lineage.caller);
    try std.testing.expect(text_lineage.instruction_start + 1 < text_lineage.instruction_end);
    try expectLineageCallTarget(alloc, output, projected, text_lineage);
    const main_start = std.mem.indexOf(u8, output.asm_text, "_main:\n") orelse
        return error.TestExpectedEqual;
    const call_offset = std.mem.indexOf(u8, output.asm_text[main_start..], "bl _observe") orelse
        return error.TestExpectedEqual;
    const call_staging = output.asm_text[main_start .. main_start + call_offset];
    try std.testing.expect(std.mem.indexOf(u8, call_staging, "mov x0") != null);
    try std.testing.expect(std.mem.indexOf(u8, call_staging, "mov x1") != null);
    try std.testing.expect(std.mem.indexOf(u8, call_staging, "mov x2") != null);

    output.lineage[0].caller +%= 1;
    try std.testing.expectError(
        error.SemanticFactsInvalid,
        validateMachineLineage(alloc, output, &graph, &diagnostic),
    );
    output.lineage[0].caller -%= 1;
    output.lineage[0].subject.? +%= 1;
    try std.testing.expectError(
        error.SemanticFactsInvalid,
        validateMachineLineage(alloc, output, &graph, &diagnostic),
    );
    output.lineage[0].subject.? -%= 1;
    output.lineage[0].descriptor = .i32;
    try std.testing.expectError(
        error.SemanticFactsInvalid,
        validateMachineLineage(alloc, output, &graph, &diagnostic),
    );
    output.lineage[0].descriptor = applications[0].descriptor;

    var artifact = try emitObjectWithGraphLineage(alloc, &module, "native-object", &graph);
    defer artifact.deinit(alloc);
    try std.testing.expect(artifact.graph == &graph);
    try std.testing.expectEqual(@as(usize, 1), artifact.lineage.len);
    const object_lineage = artifact.lineage[0];
    try std.testing.expectEqual(text_lineage.relation, object_lineage.relation);
    try std.testing.expectEqual(text_lineage.application, object_lineage.application);
    try std.testing.expectEqual(text_lineage.value, object_lineage.value);
    try std.testing.expect(std.meta.eql(text_lineage.subject.?, object_lineage.subject.?));
    try std.testing.expect(text_lineage.descriptor.eql(object_lineage.descriptor));
    try std.testing.expectEqual(text_lineage.caller, object_lineage.caller);
    try std.testing.expectEqualSlices(
        u8,
        output.text[text_lineage.text_start..text_lineage.text_end],
        artifact.bytes[object_lineage.object_start..object_lineage.object_end],
    );

    var assembly = try emitAssemblyWithGraphLineage(alloc, &module, "native-asm", &graph);
    defer assembly.deinit(alloc);
    try std.testing.expect(assembly.graph == &graph);
    try std.testing.expectEqual(@as(usize, 1), assembly.lineage.len);
    try std.testing.expectEqual(object_lineage.application, assembly.lineage[0].application);
    try std.testing.expect(@as(usize, assembly.lineage[0].text_end) <= assembly.machine.len);
    try std.testing.expectEqualSlices(
        u8,
        output.text[text_lineage.text_start..text_lineage.text_end],
        assembly.machine[assembly.lineage[0].text_start..assembly.lineage[0].text_end],
    );
    try std.testing.expect(std.mem.indexOf(u8, assembly.assembly, "bl _observe") != null);
}

test "native backend: removing checked facts refuses before machine emission" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\observe: i64 = (subject: i64)
        \\    subject
        \\main: i64 = ()
        \\    42:observe()
    ;
    var lexer = Lexer.init(source, "missing-lineage.duo");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&ast_module);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "missing-lineage.duo");
    const applications = try checkedApplications(&graph, &diagnostic);
    try std.testing.expectEqual(@as(usize, 1), applications.len);

    const module = try dnir_lower.lowerModuleWithGraph(alloc, &ast_module, &graph);
    var removed = false;
    for (module.functions) |function| {
        for (function.blocks) |block| {
            const instructions: []dnir.Instr = @constCast(block.instrs);
            for (instructions) |*instruction| {
                if (instruction.application == null) continue;
                instruction.relation = null;
                instruction.application = null;
                instruction.value = null;
                instruction.subject = null;
                instruction.realization_start = null;
                removed = true;
            }
        }
    }
    try std.testing.expect(removed);
    try std.testing.expectError(
        error.SemanticFactsInvalid,
        validateDnirApplications(alloc, module, &graph, &diagnostic),
    );
}

test "native backend: graph coordinates stay in resident context" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\observe: i64 = (value: i64)
        \\    value
        \\main: i64 = ()
        \\    observe(42)
    ;
    var lexer = Lexer.init(source, "graph-context.id");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&module);

    var graph_a = semantic_graph.SemanticGraph.init(alloc);
    defer graph_a.deinit();
    _ = try graph_a.liftModuleWithCheckedCalls(&module, &checked, "graph-context.id");
    var graph_b = semantic_graph.SemanticGraph.init(alloc);
    defer graph_b.deinit();
    _ = try graph_b.liftModuleWithCheckedCalls(&module, &checked, "graph-context.id");

    const projected = try dnir_lower.lowerModuleWithGraph(alloc, &module, &graph_a);
    defer dnir.deinitModule(alloc, projected);
    try std.testing.expect(projected.graph == &graph_a);
    try std.testing.expectError(
        error.SemanticFactsInvalid,
        validateDnirApplications(alloc, projected, &graph_b, &diagnostic),
    );
    try std.testing.expectEqualStrings("graph-context-mismatch", diagnostic.note().?);

    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return;
    var output = try emitArm64FromDnir(alloc, projected, null, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(output.graph == &graph_a);
    try validateMachineLineage(alloc, output, &graph_a, &diagnostic);
    try std.testing.expectError(
        error.SemanticFactsInvalid,
        validateMachineLineage(alloc, output, &graph_b, &diagnostic),
    );
    try std.testing.expectEqualStrings("machine-graph-context", diagnostic.note().?);

    var artifact = try emitObjectWithGraphLineage(alloc, &module, "native-object", &graph_a);
    defer artifact.deinit(alloc);
    try std.testing.expect(artifact.graph == &graph_a);
}

test "native backend: empty application facts do not admit a direct call" {
    var diagnostic: Diagnostic = .{};
    const alloc = std.testing.allocator;
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    const instructions = [_]dnir.Instr{.{
        .op = .call_direct,
        .callee = "unowned",
    }};
    const blocks = [_]dnir.Block{.{ .instrs = &instructions }};
    const functions = [_]dnir.Function{.{
        .name = "main",
        .ret = .void,
        .blocks = &blocks,
    }};
    const module = dnir.Module{
        .functions = &functions,
        .graph = &graph,
    };

    try std.testing.expectEqual(@as(usize, 0), graph.applications().len);
    try std.testing.expectError(
        error.SemanticFactsInvalid,
        validateDnirApplications(alloc, module, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("missing-application-lineage", diagnostic.note().?);
}

test "native backend: empty application facts do not admit a foreign call" {
    var diagnostic: Diagnostic = .{};
    const alloc = std.testing.allocator;
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    const instructions = [_]dnir.Instr{.{
        .op = .call_extern,
        .callee = "unowned",
    }};
    const blocks = [_]dnir.Block{.{ .instrs = &instructions }};
    const functions = [_]dnir.Function{.{
        .name = "main",
        .ret = .void,
        .blocks = &blocks,
    }};
    const module = dnir.Module{
        .functions = &functions,
        .graph = &graph,
    };

    try std.testing.expectEqual(@as(usize, 0), graph.applications().len);
    try std.testing.expectError(
        error.SemanticFactsInvalid,
        validateDnirApplications(alloc, module, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("missing-foreign-application-lineage", diagnostic.note().?);
}

test "native backend: strict graph physical refusal stays unsupported" {
    var diagnostic: Diagnostic = .{};
    const alloc = std.testing.allocator;
    var lexer = Lexer.init("", "empty.id");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var module = try parser.parse_module();

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCalls(&module, "empty.id");

    try std.testing.expectError(
        error.UnsupportedProgram,
        emitArm64ModuleWithGraph(alloc, &module, null, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("graph-dnir-unsupported", diagnostic.note().?);
}

test "native backend: strict graph unresolved application stays semantic" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\observe: i64 = (value: i64)
        \\    value
        \\main: i64 = ()
        \\    observe(42)
    ;
    var lexer = Lexer.init(source, "unresolved.id");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var module = try parser.parse_module();

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCalls(&module, "unresolved.id");
    try std.testing.expect(graph.unresolvedApplicationCount(null) != 0);

    try std.testing.expectError(
        error.SemanticFactsInvalid,
        emitArm64ModuleWithGraph(alloc, &module, null, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("unresolved-application-facts", diagnostic.note().?);
}

test "native backend: lowerer graph fact failure stays semantic" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\main: i64 = ()
        \\    0
    ;
    var lexer = Lexer.init(source, "missing-function-fact.id");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var module = try parser.parse_module();

    // This resident graph deliberately has no declaration fact for `main`.
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try std.testing.expectEqual(@as(usize, 0), graph.unresolvedApplicationCount(null));

    try std.testing.expectError(
        error.SemanticFactsInvalid,
        emitArm64ModuleWithGraph(alloc, &module, null, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("graph-dnir-facts", diagnostic.note().?);
}

test "native backend: strict graph allocation failure stays allocation failure" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\main: i64 = ()
        \\    0
    ;
    var lexer = Lexer.init(source, "allocation.id");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&module);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, "allocation.id");

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 0,
    });
    try std.testing.expectError(
        error.OutOfMemory,
        emitArm64ModuleWithGraph(failing.allocator(), &module, null, &graph, &diagnostic),
    );
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}

test "native backend: graph-resident region validation preserves physical native entry" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\main: i64 = ()
        \\    x = 10
        \\    y = 32
        \\    x + y
    ;
    var lexer = Lexer.init(source, "region-entry.id");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&module, &checked, &graph);
    var output = try emitArm64ModuleWithGraph(alloc, &module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(output.graph == &graph);
    try std.testing.expectEqual(@as(usize, 0), output.lineage.len);
    try std.testing.expect(output.text.len != 0);
}

test "native backend: transform outcomes retain their category" {
    var diagnostic: Diagnostic = .{};
    try std.testing.expect(transformFailure(&diagnostic, @src(), error.OutOfMemory) == error.OutOfMemory);
    try std.testing.expect(transformFailure(&diagnostic, @src(), error.ResidencyMismatch) == error.SemanticFactsInvalid);
    try std.testing.expect(transformFailure(&diagnostic, @src(), error.CoordinateOverflow) == error.UnsupportedProgram);
    try std.testing.expectEqualStrings("region-coordinate-capacity", diagnostic.note().?);
}

test "native backend: caller diagnostics are isolated and observed attempts reset" {
    var first: Diagnostic = .{};
    var second: Diagnostic = .{};

    try std.testing.expect(transformFailure(&second, @src(), error.ResidencyMismatch) == error.SemanticFactsInvalid);
    try std.testing.expectEqualStrings("region-transform-residency", second.note().?);

    first.lowering.site = @src();
    first.lowering.note_buffer[0] = 'x';
    first.lowering.note_len = 1;
    var lexer = Lexer.init("", "diagnostic-reset.id");
    var parser = Parser.init(&lexer, std.testing.allocator);
    parser.duo_mode = true;
    var module = try parser.parse_module();
    var graph = semantic_graph.SemanticGraph.init(std.testing.allocator);
    defer graph.deinit();
    try std.testing.expectError(
        error.UnsupportedTarget,
        emitObjectWithGraphLineageObserved(
            std.testing.allocator,
            &module,
            "unsupported-target",
            &graph,
            &first,
        ),
    );
    try std.testing.expect(first.site == null);
    try std.testing.expect(first.note() == null);
    try std.testing.expect(first.lowering.site == null);
    try std.testing.expect(first.lowering.note() == null);
    try std.testing.expectEqualStrings("region-transform-residency", second.note().?);
}

test "native backend: checked ordinary call reaches regions and machine lineage" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\observe: i64 = (value: i64)
        \\    value
        \\main: i64 = ()
        \\    observe(41)
        \\    observe(42)
    ;
    var lexer = Lexer.init(source, "ordinary-lineage.id");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&ast_module);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "ordinary-lineage.id");
    const applications = try checkedApplications(&graph, &diagnostic);
    try std.testing.expectEqual(@as(usize, 2), applications.len);
    try std.testing.expect(std.meta.eql(applications[0].relation, applications[1].relation));
    try std.testing.expect(!std.meta.eql(applications[0].application, applications[1].application));
    try std.testing.expect(!std.meta.eql(
        try applicationResult(&graph, applications[0], &diagnostic),
        try applicationResult(&graph, applications[1], &diagnostic),
    ));
    try std.testing.expectEqual(@as(?semantic_graph.id, null), applications[0].subject);
    try std.testing.expectEqual(@as(?semantic_graph.id, null), applications[1].subject);

    const module = try dnir_lower.lowerModuleWithGraph(alloc, &ast_module, &graph);
    try validateDnirApplications(alloc, module, &graph, &diagnostic);

    const regions = try region_graph.buildModuleRegions(alloc, module);
    defer region_graph.freeModuleRegions(alloc, regions);
    try region_graph.validateModuleRegions(alloc, regions, &graph, module);

    if (builtin.os.tag == .macos and builtin.cpu.arch == .aarch64) {
        var output = try emitArm64ModuleWithGraph(alloc, &ast_module, null, &graph, &diagnostic);
        defer output.deinit(alloc);
        try std.testing.expectEqual(@as(usize, 2), output.lineage.len);
        try std.testing.expect(std.meta.eql(output.lineage[0].relation, output.lineage[1].relation));
        try std.testing.expect(!std.meta.eql(output.lineage[0].application, output.lineage[1].application));
        try std.testing.expect(!std.meta.eql(output.lineage[0].value, output.lineage[1].value));
        try std.testing.expectEqual(@as(?semantic_graph.id, null), output.lineage[0].subject);
        try std.testing.expectEqual(@as(?semantic_graph.id, null), output.lineage[1].subject);
        try std.testing.expect(output.lineage[0].descriptor.eql(.i64));
        try std.testing.expect(output.lineage[1].descriptor.eql(.i64));
        for (output.lineage) |lineage| {
            try expectLineageCallTarget(alloc, output, module, lineage);
        }

        var artifact = try emitObjectWithGraphLineage(alloc, &ast_module, "native-object", &graph);
        defer artifact.deinit(alloc);
        try std.testing.expectEqual(@as(usize, 2), artifact.lineage.len);
        for (artifact.lineage) |lineage| {
            const application = graph.application(lineage.application) orelse
                return error.TestExpectedEqual;
            try std.testing.expectEqual(lineage.application, application.application);
            try std.testing.expectEqualStrings("ordinary-lineage.id", application.provenance.file);
            try std.testing.expect(application.provenance.start < application.provenance.end);
            try std.testing.expect(lineage.object_start < lineage.object_end);
            try std.testing.expect(@as(usize, lineage.object_end) <= artifact.bytes.len);
            var text_lineage: ?MachineLineage = null;
            for (output.lineage) |candidate| {
                if (std.meta.eql(candidate.application, lineage.application)) text_lineage = candidate;
            }
            const text = text_lineage orelse return error.TestExpectedEqual;
            try std.testing.expectEqualSlices(
                u8,
                output.text[text.text_start..text.text_end],
                artifact.bytes[lineage.object_start..lineage.object_end],
            );
        }
    }
}

test "native backend: checked record result keeps application lineage" {
    var diagnostic: Diagnostic = .{};
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\pair: {
        \\    left: i64
        \\    right: i64
        \\}
        \\make: pair = (value: i64)
        \\    { left = value, right = value + 1 }
        \\main: i64 = ()
        \\    result: pair = make(41)
        \\    result.left + 1
    ;
    var lexer = Lexer.init(source, "record-lineage.duo");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "record-lineage.duo");
    const applications = try checkedApplications(&graph, &diagnostic);
    try std.testing.expectEqual(@as(usize, 1), applications.len);

    const module = try dnir_lower.lowerModuleWithGraph(alloc, &ast_module, &graph);
    try validateDnirApplications(alloc, module, &graph, &diagnostic);
    var call: ?*dnir.Instr = null;
    var anonymous_record_realizations: usize = 0;
    for (module.functions) |function| {
        for (function.blocks) |block| {
            const instructions: []dnir.Instr = @constCast(block.instrs);
            for (instructions) |*instruction| {
                if (instruction.application != null) call = instruction;
                if (instruction.op == .init_record) anonymous_record_realizations += 1;
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 0), anonymous_record_realizations);
    const instruction = call orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("pair", instruction.record);
    try std.testing.expect(std.meta.eql(instruction.application.?, applications[0].application));
    try std.testing.expect(std.meta.eql(
        instruction.value.?,
        try applicationResult(&graph, applications[0], &diagnostic),
    ));
    try std.testing.expect(instruction.ty.eql(applications[0].descriptor));

    const regions = try region_graph.buildModuleRegions(alloc, module);
    defer region_graph.freeModuleRegions(alloc, regions);
    try region_graph.validateModuleRegions(alloc, regions, &graph, module);

    var output = try emitArm64ModuleWithGraph(alloc, &ast_module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 1), output.lineage.len);
    try std.testing.expect(std.meta.eql(output.lineage[0].application, applications[0].application));
    try std.testing.expect(output.lineage[0].descriptor.eql(applications[0].descriptor));
    try expectLineageCallTarget(alloc, output, module, output.lineage[0]);

    var artifact = try emitObjectWithGraphLineage(alloc, &ast_module, "native-object", &graph);
    defer artifact.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 1), artifact.lineage.len);
    try std.testing.expectEqualSlices(
        u8,
        output.text[output.lineage[0].text_start..output.lineage[0].text_end],
        artifact.bytes[artifact.lineage[0].object_start..artifact.lineage[0].object_end],
    );

    instruction.record = "other";
    try std.testing.expectError(
        error.SemanticFactsInvalid,
        validateDnirApplications(alloc, module, &graph, &diagnostic),
    );
}

test "native backend: checked f64 record result refuses unstable ABI homes" {
    var diagnostic: Diagnostic = .{};
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\pair: {
        \\    left: f64
        \\    right: f64
        \\}
        \\make: pair = (value: f64)
        \\    { left = value, right = value }
        \\main: f64 = ()
        \\    result: pair = make(1.5)
        \\    result.left
    ;
    var lexer = Lexer.init(source, "record-f64-refusal.duo");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "record-f64-refusal.duo");

    try std.testing.expectError(
        error.SemanticFactsInvalid,
        emitArm64ModuleWithGraph(alloc, &ast_module, null, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("graph-dnir-facts", diagnostic.note().?);
    try std.testing.expectEqualStrings("application-result-abi", diagnostic.lowering.note().?);
}

test "native backend: callee spelling cannot redirect a checked application" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\observe: i64 = (value: i64)
        \\    value
        \\impostor: i64 = (value: i64)
        \\    value + 1
        \\main: i64 = ()
        \\    observe(42)
    ;
    var lexer = Lexer.init(source, "callee-mismatch.duo");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "callee-mismatch.duo");
    const applications = try checkedApplications(&graph, &diagnostic);
    try std.testing.expectEqual(@as(usize, 1), applications.len);

    const module = try dnir_lower.lowerModuleWithGraph(alloc, &ast_module, &graph);
    try validateDnirApplications(alloc, module, &graph, &diagnostic);
    var baseline = try emitArm64FromDnir(alloc, module, null, &diagnostic);
    defer baseline.deinit(alloc);
    var identified: ?*dnir.Instr = null;
    for (module.functions) |function| {
        for (function.blocks) |block| {
            const instructions: []dnir.Instr = @constCast(block.instrs);
            for (instructions) |*instruction| {
                if (instruction.application == null) continue;
                identified = instruction;
            }
        }
    }
    const instruction = identified orelse return error.TestExpectedEqual;
    const relation_before = instruction.relation.?;
    const descriptor_before = instruction.ty;
    instruction.ty = .i32;
    try std.testing.expect(std.meta.eql(relation_before, instruction.relation.?));
    try std.testing.expectError(
        error.SemanticFactsInvalid,
        validateDnirApplications(alloc, module, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("application-fact-mismatch", diagnostic.note().?);
    instruction.ty = descriptor_before;

    const functions: []dnir.Function = @constCast(module.functions);
    var selected_function: ?*dnir.Function = null;
    var other_function: ?*dnir.Function = null;
    for (functions) |*function| {
        const id = function.id orelse continue;
        if (std.meta.eql(id, applications[0].relation)) {
            selected_function = function;
        } else if (std.mem.eql(u8, function.name, "impostor")) {
            other_function = function;
        }
    }
    const selected = selected_function orelse return error.TestExpectedEqual;
    const other = other_function orelse return error.TestExpectedEqual;
    const selected_id = selected.id.?;
    const other_id = other.id.?;

    const other_name = other.name;
    other.name = selected.name;
    try std.testing.expectError(
        error.SemanticFactsInvalid,
        validateDnirApplications(alloc, module, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("duplicate-link-symbol", diagnostic.note().?);
    other.name = other_name;

    other.id = selected_id;
    try std.testing.expectError(
        error.SemanticFactsInvalid,
        validateDnirApplications(alloc, module, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("function-fact-collision", diagnostic.note().?);
    other.id = other_id;

    // Repeated projection from the same exact ids is deterministic.
    if (builtin.os.tag == .macos and builtin.cpu.arch == .aarch64) {
        var before = try emitObjectWithGraphLineage(alloc, &ast_module, "native-object", &graph);
        defer before.deinit(alloc);
        var after = try emitObjectWithGraphLineage(alloc, &ast_module, "native-object", &graph);
        defer after.deinit(alloc);
        try std.testing.expectEqualSlices(u8, before.bytes, after.bytes);
        try std.testing.expectEqual(before.lineage.len, after.lineage.len);
        try std.testing.expectEqual(@as(usize, 1), before.lineage.len);
        try std.testing.expect(std.meta.eql(before.lineage[0].relation, after.lineage[0].relation));
        try std.testing.expect(std.meta.eql(before.lineage[0].application, after.lineage[0].application));
        try std.testing.expect(std.meta.eql(before.lineage[0].value, after.lineage[0].value));
    }
    try validateDnirApplications(alloc, module, &graph, &diagnostic);

    // Redirecting the target to another valid entity in the same graph must
    // fail even when all textual linkage remains unchanged.
    selected.id = applications[0].application;
    try std.testing.expectError(
        error.SemanticFactsInvalid,
        validateDnirApplications(alloc, module, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("missing-foreign-application-lineage", diagnostic.note().?);
    selected.id = selected_id;

    instruction.callee = "impostor";
    try std.testing.expect(std.meta.eql(applications[0].relation, relation_before));
    try std.testing.expectError(
        error.SemanticFactsInvalid,
        validateDnirApplications(alloc, module, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("application-link-symbol", diagnostic.note().?);

    // A physical symbol may be renamed when the exact target identity moves
    // with it. The semantic relation remains the graph-selected relation.
    instruction.callee = "observe_alias";
    selected.name = "observe_alias";
    try std.testing.expect(std.meta.eql(relation_before, instruction.relation.?));
    try std.testing.expect(std.meta.eql(selected.id.?, selected_id));
    try validateDnirApplications(alloc, module, &graph, &diagnostic);

    var renamed = try emitArm64FromDnir(alloc, module, null, &diagnostic);
    defer renamed.deinit(alloc);
    try std.testing.expectEqualSlices(u8, baseline.text, renamed.text);
    try std.testing.expect(std.mem.indexOf(u8, baseline.asm_text, "bl _observe") != null);
    try std.testing.expect(std.mem.indexOf(u8, renamed.asm_text, "bl _observe_alias") != null);
    try std.testing.expectEqual(baseline.lineage.len, renamed.lineage.len);
    try std.testing.expectEqual(@as(usize, 1), renamed.lineage.len);
    try std.testing.expect(std.meta.eql(baseline.lineage[0].relation, renamed.lineage[0].relation));
    try std.testing.expect(std.meta.eql(baseline.lineage[0].application, renamed.lineage[0].application));
    try std.testing.expect(std.meta.eql(baseline.lineage[0].value, renamed.lineage[0].value));
    try std.testing.expect(std.meta.eql(baseline.lineage[0].caller, renamed.lineage[0].caller));
}

test "native backend: checked call result descriptor does not select argument ABI" {
    var diagnostic: Diagnostic = .{};
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\choose: f64 = (value: i64)
        \\    1.5
        \\main: f64 = ()
        \\    choose(42)
    ;
    var lexer = Lexer.init(source, "call-abi.duo");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "call-abi.duo");
    const applications = try checkedApplications(&graph, &diagnostic);
    try std.testing.expectEqual(@as(usize, 1), applications.len);
    try std.testing.expect(applications[0].descriptor.eql(.f64));

    const module = try dnir_lower.lowerModuleWithGraph(alloc, &ast_module, &graph);
    var saw_gp_stage = false;
    var saw_fp_stage = false;
    for (module.functions) |function| {
        for (function.blocks) |block| {
            for (block.instrs) |instruction| {
                if (instruction.op == .mov_arg) saw_gp_stage = true;
                if (instruction.op == .fp_mov_arg) saw_fp_stage = true;
                if (instruction.application != null) {
                    try std.testing.expectEqual(dnir.Value.void, instruction.lhs);
                    try std.testing.expect(instruction.ty.eql(.f64));
                }
            }
        }
    }
    try std.testing.expect(saw_gp_stage);
    try std.testing.expect(!saw_fp_stage);
    try validateDnirApplications(alloc, module, &graph, &diagnostic);

    var output = try emitArm64ModuleWithGraph(alloc, &ast_module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 1), output.lineage.len);
    try std.testing.expect(output.lineage[0].descriptor.eql(.f64));
    try expectLineageCallTarget(alloc, output, module, output.lineage[0]);
}

test "native backend: nested checked call machine ranges do not overlap" {
    var diagnostic: Diagnostic = .{};
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\inner: i64 = (value: i64)
        \\    value
        \\outer: i64 = (left: i64, right: i64)
        \\    left + right
        \\main: i64 = ()
        \\    outer(inner(40), inner(2))
    ;
    var lexer = Lexer.init(source, "nested-lineage.duo");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "nested-lineage.duo");
    const applications = try checkedApplications(&graph, &diagnostic);
    try std.testing.expectEqual(@as(usize, 3), applications.len);
    const module = try dnir_lower.lowerModuleWithGraph(alloc, &ast_module, &graph);

    var output = try emitArm64ModuleWithGraph(alloc, &ast_module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 3), output.lineage.len);
    var outer: ?MachineLineage = null;
    var inner: [2]MachineLineage = undefined;
    var inner_count: usize = 0;
    for (output.lineage) |lineage| {
        try expectLineageCallTarget(alloc, output, module, lineage);
        var parameter_count: ?usize = null;
        for (module.functions) |function| {
            if (function.id != null and std.meta.eql(function.id.?, lineage.relation)) {
                parameter_count = function.params.len;
            }
        }
        if (parameter_count == 2) {
            outer = lineage;
        } else if (parameter_count == 1) {
            if (inner_count >= inner.len) return error.TestExpectedEqual;
            inner[inner_count] = lineage;
            inner_count += 1;
        }
    }
    try std.testing.expectEqual(inner.len, inner_count);
    const outer_lineage = outer orelse return error.TestExpectedEqual;
    for (inner) |inner_lineage| {
        try std.testing.expect(inner_lineage.instruction_end <= outer_lineage.instruction_start);
        try std.testing.expect(inner_lineage.text_end <= outer_lineage.text_start);
    }
}

test "native backend: nested checked f64 results survive later operand calls" {
    var diagnostic: Diagnostic = .{};
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\inner: f64 = (value: f64)
        \\    value
        \\outer: f64 = (left: f64, right: f64)
        \\    left + right
        \\main: f64 = ()
        \\    outer(inner(1.0), inner(2.0))
    ;
    var lexer = Lexer.init(source, "nested-f64-lineage.duo");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "nested-f64-lineage.duo");
    const applications = try checkedApplications(&graph, &diagnostic);
    try std.testing.expectEqual(@as(usize, 3), applications.len);
    const module = try dnir_lower.lowerModuleWithGraph(alloc, &ast_module, &graph);

    var output = try emitArm64ModuleWithGraph(alloc, &ast_module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 3), output.lineage.len);
    const main_start = std.mem.indexOf(u8, output.asm_text, "_main:\n") orelse
        return error.TestExpectedEqual;
    const main_assembly = output.asm_text[main_start..];
    try std.testing.expect(std.mem.indexOf(u8, main_assembly, "fmov d16, d0") != null);
    try std.testing.expect(std.mem.indexOf(u8, main_assembly, "fmov d17, d0") != null);

    var outer: ?MachineLineage = null;
    var latest_inner_end: u32 = 0;
    for (output.lineage) |lineage| {
        try expectLineageCallTarget(alloc, output, module, lineage);
        var parameter_count: ?usize = null;
        for (module.functions) |function| {
            if (function.id != null and std.meta.eql(function.id.?, lineage.relation)) {
                parameter_count = function.params.len;
            }
        }
        if (parameter_count == 2) {
            outer = lineage;
        } else if (parameter_count == 1) {
            latest_inner_end = @max(latest_inner_end, lineage.text_end);
        }
    }
    try std.testing.expect(latest_inner_end <= (outer orelse return error.TestExpectedEqual).text_start);
}

test "native backend: discarded checked calls do not retain return registers" {
    var diagnostic: Diagnostic = .{};
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\observe: i64 = (value: i64)
        \\    value
        \\main: i64 = ()
        \\    observe(1)
        \\    observe(2)
        \\    observe(3)
        \\    observe(4)
        \\    observe(5)
        \\    observe(6)
        \\    observe(7)
        \\    observe(8)
        \\    observe(9)
        \\    observe(10)
        \\    observe(11)
        \\    observe(12)
        \\    observe(13)
        \\    observe(14)
        \\    observe(15)
        \\    observe(16)
        \\    observe(17)
        \\    observe(18)
        \\    observe(19)
        \\    observe(20)
        \\    0
    ;
    var lexer = Lexer.init(source, "discarded-calls.duo");
    var parser = Parser.init(&lexer, alloc);
    parser.duo_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.duo_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "discarded-calls.duo");
    const applications = try checkedApplications(&graph, &diagnostic);
    try std.testing.expectEqual(@as(usize, 20), applications.len);
    const module = try dnir_lower.lowerModuleWithGraph(alloc, &ast_module, &graph);

    var output = try emitArm64ModuleWithGraph(alloc, &ast_module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expectEqual(applications.len, output.lineage.len);
    for (output.lineage) |lineage| {
        try expectLineageCallTarget(alloc, output, module, lineage);
    }
}

test "native backend refuses source f64 aggregate application absent operand ABI facts" {
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

    try expectCheckedTestSemanticFailure(
        alloc,
        &mod,
        &sem,
        "graph-dnir-facts",
        "application-operand-abi",
    );
}

test "native backend physical oracle retains f64 aggregate ABI and branch return" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const fields = [_][]const u8{ "x", "y" };
    const kinds = [_]dnir.FieldKind{ .f64, .f64 };
    const records = [_]dnir.RecordDesc{.{ .name = "Point", .fields = &fields, .kinds = &kinds }};
    const parameters = [_]dnir.Param{.{ .name = "p", .ty = .any, .record = "Point" }};
    const distance_instructions = [_]dnir.Instr{
        .{ .op = .load_field, .result = 2, .req_alias = "p", .field = "x", .ty = .f64 },
        .{ .op = .load_field, .result = 3, .req_alias = "p", .field = "y", .ty = .f64 },
        .{ .op = .binop, .result = 4, .lhs = .{ .temp = 2 }, .rhs = .{ .temp = 2 }, .binop = .mul, .ty = .f64 },
        .{ .op = .binop, .result = 5, .lhs = .{ .temp = 3 }, .rhs = .{ .temp = 3 }, .binop = .mul, .ty = .f64 },
        .{ .op = .binop, .result = 6, .lhs = .{ .temp = 4 }, .rhs = .{ .temp = 5 }, .binop = .add, .ty = .f64 },
        .{ .op = .ret, .lhs = .{ .temp = 6 }, .ty = .f64 },
    };
    const main_instructions = [_]dnir.Instr{
        .{ .op = .fp_mov_arg, .result = 0, .lhs = .{ .f64 = 3.0 }, .ty = .f64 },
        .{ .op = .fp_mov_arg, .result = 1, .lhs = .{ .f64 = 4.0 }, .ty = .f64 },
        .{ .op = .call_direct, .result = 0, .callee = "distance2", .ty = .f64 },
        .{ .op = .ret, .lhs = .{ .temp = 0 }, .ty = .f64 },
    };
    const compare_instructions = [_]dnir.Instr{
        .{ .op = .fp_mov_arg, .result = 0, .lhs = .{ .f64 = 3.0 }, .ty = .f64 },
        .{ .op = .fp_mov_arg, .result = 1, .lhs = .{ .f64 = 4.0 }, .ty = .f64 },
        .{ .op = .call_direct, .result = 0, .callee = "distance2", .ty = .f64 },
        .{ .op = .@"const", .result = 1, .lhs = .{ .f64 = 25.0 }, .ty = .f64 },
        .{ .op = .binop, .result = 2, .lhs = .{ .temp = 0 }, .rhs = .{ .temp = 1 }, .binop = .eq, .ty = .f64 },
        .{ .op = .br, .lhs = .{ .temp = 2 }, .branch_target = 7, .branch_condition = .when_true },
        .{ .op = .ret, .lhs = .{ .i64 = 1 }, .ty = .i64 },
        .{ .op = .ret, .lhs = .{ .i64 = 0 }, .ty = .i64 },
    };
    const distance_blocks = [_]dnir.Block{.{ .instrs = &distance_instructions }};
    const main_blocks = [_]dnir.Block{.{ .instrs = &main_instructions }};
    const compare_blocks = [_]dnir.Block{.{ .instrs = &compare_instructions }};
    const functions = [_]dnir.Function{
        .{ .name = "distance2", .ret = .f64, .params = &parameters, .is_float_kernel = true, .blocks = &distance_blocks },
        .{ .name = "main", .ret = .f64, .is_float_kernel = true, .blocks = &main_blocks },
        .{ .name = "compare", .ret = .i64, .is_float_kernel = true, .blocks = &compare_blocks },
    };
    const module = dnir.Module{ .functions = &functions, .records = &records };

    // This schedule is authority-false: it preserves the physical ABI and
    // encoder obligation while aggregate application facts remain producer-blocked.
    var diagnostic: Diagnostic = .{};
    var output = try emitArm64FromDnir(alloc, module, null, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(output.graph == null);
    try std.testing.expectEqual(@as(usize, 0), output.lineage.len);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "_distance2") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "fmul") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "fadd") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "fcmp") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "fcvtzs x0, d0") == null);
    const main_start = std.mem.indexOf(u8, output.asm_text, "_main:\n") orelse return error.TestExpectedEqual;
    const compare_start = std.mem.indexOf(u8, output.asm_text, "_compare:\n") orelse return error.TestExpectedEqual;
    const main_body = output.asm_text[main_start..compare_start];
    const call = std.mem.indexOf(u8, main_body, "bl _distance2") orelse return error.TestExpectedEqual;
    try std.testing.expect(std.mem.indexOf(u8, main_body[call..], "fmov d") == null);

    const object = try emitMachOArm64Object(
        alloc,
        output.text,
        output.cstring,
        output.symbols,
        output.relocations,
        output.bss_size,
    );
    defer alloc.free(object);
    try std.testing.expectEqual(@as(u32, 0xfeedfacf), std.mem.readInt(u32, object[0..4], .little));
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
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&mod, &sem, &graph);
    var artifact = try emitCheckedTestAssembly(alloc, &mod, &graph, null);
    defer artifact.deinit(alloc);
    const listing = artifact.assembly;
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

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&mod, &sem, &graph);
    var executable = try emitCheckedTestAssembly(alloc, &mod, &graph, "run");
    defer executable.deinit(alloc);
    const listing = executable.assembly;
    try std.testing.expect(std.mem.indexOf(u8, listing, "fcvtzs x0, d0") != null);

    var plain_artifact = try emitCheckedTestAssembly(alloc, &mod, &graph, null);
    defer plain_artifact.deinit(alloc);
    const plain = plain_artifact.assembly;
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

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&mod, &sem, &graph);
    var object = try emitCheckedTestObject(alloc, &mod, &graph);
    defer object.deinit(alloc);
    try std.testing.expect(object.bytes.len > 0);
    var assembly = try emitCheckedTestAssembly(alloc, &mod, &graph, null);
    defer assembly.deinit(alloc);
    const listing = assembly.assembly;
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

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&mod, &sem, &graph);
    var artifact = try emitCheckedTestObject(alloc, &mod, &graph);
    defer artifact.deinit(alloc);
    try std.testing.expect(artifact.bytes.len > 0);
    try std.testing.expectEqual(@as(u32, 0xfeedfacf), std.mem.readInt(u32, artifact.bytes[0..4], .little));
    try std.testing.expect(std.mem.indexOf(u8, artifact.bytes, "_main") != null);
    try std.testing.expect(std.mem.indexOf(u8, artifact.bytes, "\xc0\x03\x5f\xd6") != null);
}

test "native backend refuses source length2 short-circuit absent physical lowering" {
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

    try expectCheckedTestPhysicalRefusal(
        alloc,
        &mod,
        &sem,
        "graph-dnir-unsupported",
    );
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

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&mod, &sem, &graph);
    var artifact = try emitCheckedTestObject(alloc, &mod, &graph);
    defer artifact.deinit(alloc);
    try std.testing.expect(artifact.bytes.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, artifact.bytes, "_main") != null);
    try std.testing.expect(std.mem.indexOf(u8, artifact.bytes, "\xc0\x03\x5f\xd6") != null);
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

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&mod, &sem, &graph);
    var artifact = try emitCheckedTestObject(alloc, &mod, &graph);
    defer artifact.deinit(alloc);
    try std.testing.expect(std.mem.indexOf(u8, artifact.bytes, "_add") != null);
    try std.testing.expect(std.mem.indexOf(u8, artifact.bytes, "_main") != null);
}

test "native backend refuses a qualified call absent graph application facts" {
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

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&mod, &sem, "math_add_multi.duo");
    try std.testing.expectEqual(@as(usize, 0), graph.applications().len);
    try std.testing.expectEqual(@as(usize, 1), graph.unresolvedApplicationCount(null));

    var diagnostic: Diagnostic = .{};
    try std.testing.expectError(
        error.SemanticFactsInvalid,
        emitAssemblyWithGraphLineageObserved(alloc, &mod, "native-asm", &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("unresolved-application-facts", diagnostic.note().?);
    try std.testing.expect(diagnostic.lowering.note() == null);
}

test "native backend physical oracle retains qualified link symbol and two-register call ABI" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    const parameters = [_]dnir.Param{
        .{ .name = "a", .ty = .i64 },
        .{ .name = "b", .ty = .i64 },
    };
    const add_instructions = [_]dnir.Instr{
        .{
            .op = .binop,
            .result = 2,
            .lhs = .{ .temp = 0 },
            .rhs = .{ .temp = 1 },
            .binop = .add,
            .ty = .i64,
        },
        .{ .op = .ret, .lhs = .{ .temp = 2 }, .ty = .i64 },
    };
    const main_instructions = [_]dnir.Instr{
        .{ .op = .@"const", .result = 0, .lhs = .{ .i64 = 10 }, .ty = .i64 },
        .{ .op = .@"const", .result = 1, .lhs = .{ .i64 = 20 }, .ty = .i64 },
        .{ .op = .mov_arg, .result = 0, .lhs = .{ .temp = 0 }, .ty = .i64 },
        .{ .op = .mov_arg, .result = 1, .lhs = .{ .temp = 1 }, .ty = .i64 },
        .{ .op = .call_direct, .result = 2, .callee = "math.add", .ty = .i64 },
        .{ .op = .ret, .lhs = .{ .temp = 2 }, .ty = .i64 },
    };
    const add_blocks = [_]dnir.Block{.{ .instrs = &add_instructions }};
    const main_blocks = [_]dnir.Block{.{ .instrs = &main_instructions }};
    const functions = [_]dnir.Function{
        .{ .name = "math.add", .ret = .i64, .params = &parameters, .blocks = &add_blocks },
        .{ .name = "main", .ret = .i64, .blocks = &main_blocks },
    };
    const module = dnir.Module{ .functions = &functions };

    // This schedule is an authority-false physical oracle: it proves only the
    // linker spelling and ABI moves after meaning has already been selected.
    var diagnostic: Diagnostic = .{};
    var output = try emitArm64FromDnir(alloc, module, null, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(output.graph == null);
    try std.testing.expectEqual(@as(usize, 0), output.lineage.len);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "_math_add") != null);
    const main_start = std.mem.indexOf(u8, output.asm_text, "_main:\n") orelse
        return error.TestExpectedEqual;
    const call_offset = std.mem.indexOf(u8, output.asm_text[main_start..], "bl _math_add") orelse
        return error.TestExpectedEqual;
    const staging = output.asm_text[main_start .. main_start + call_offset];
    try std.testing.expect(std.mem.indexOf(u8, staging, "mov x0") != null);
    try std.testing.expect(std.mem.indexOf(u8, staging, "mov x1") != null);

    const object = try emitMachOArm64Object(
        alloc,
        output.text,
        output.cstring,
        output.symbols,
        output.relocations,
        output.bss_size,
    );
    defer alloc.free(object);
    try std.testing.expect(std.mem.indexOf(u8, object, "_math_add") != null);
}

test "native backend refuses source conversion absent application facts and retains variadic ABI oracle" {
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

    try expectCheckedTestSemanticFailure(
        alloc,
        &mod,
        &sem,
        "unresolved-application-facts",
        null,
    );

    const instructions = [_]dnir.Instr{
        .{ .op = .alloc_slots, .result = 0, .lhs = .{ .i64 = 3 } },
        .{ .op = .@"const", .result = 1, .lhs = .{ .i64 = 24 }, .ty = .i64 },
        .{ .op = .@"const", .result = 2, .lhs = .{ .str = "%lld" }, .ty = .str },
        .{ .op = .@"const", .result = 3, .lhs = .{ .i64 = 42 }, .ty = .i64 },
        .{ .op = .mov_arg, .result = 0, .lhs = .{ .temp = 0 }, .ty = .i64 },
        .{ .op = .mov_arg, .result = 1, .lhs = .{ .temp = 1 }, .ty = .i64 },
        .{ .op = .mov_arg, .result = 2, .lhs = .{ .temp = 2 }, .ty = .str },
        .{ .op = .mov_arg, .result = 0, .lhs = .{ .temp = 3 }, .field = "vararg", .ty = .i64 },
        .{ .op = .call_extern, .callee = "snprintf", .ty = .i64 },
        .{ .op = .ret, .lhs = .{ .i64 = 0 }, .ty = .i64 },
    };
    const blocks = [_]dnir.Block{.{ .instrs = &instructions }};
    const functions = [_]dnir.Function{.{ .name = "main", .ret = .i64, .blocks = &blocks }};
    const module = dnir.Module{ .functions = &functions };
    var diagnostic: Diagnostic = .{};
    var output = try emitArm64FromDnir(alloc, module, null, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(output.graph == null);
    try std.testing.expectEqual(@as(usize, 0), output.lineage.len);
    const listing = output.asm_text;

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

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&mod, &sem, &graph);
    var assembly = try emitCheckedTestAssembly(alloc, &mod, &graph, null);
    defer assembly.deinit(alloc);
    const asm_text = assembly.assembly;
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

    var object = try emitCheckedTestObject(alloc, &mod, &graph);
    defer object.deinit(alloc);
    try std.testing.expect(std.mem.indexOf(u8, object.bytes, "_pick") != null);
}

test "native backend refuses source while break and continue absent physical lowering" {
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

    try expectCheckedTestPhysicalRefusal(alloc, &mod, &sem, "graph-dnir-unsupported");
}

test "native backend refuses source numeric loops absent physical lowering" {
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

    try expectCheckedTestPhysicalRefusal(alloc, &mod, &sem, "graph-dnir-unsupported");
}

test "native backend authority-false physical loop oracle retains continue break and backedge" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    const instructions = [_]dnir.Instr{
        .{ .op = .@"const", .result = 0, .lhs = .{ .i64 = 0 }, .ty = .i64 },
        .{ .op = .store_local, .result = 0, .lhs = .{ .temp = 0 }, .ty = .i64 },
        .{ .op = .@"const", .result = 1, .lhs = .{ .i64 = 0 }, .ty = .i64 },
        .{ .op = .store_local, .result = 1, .lhs = .{ .temp = 1 }, .ty = .i64 },
        .{ .op = .@"const", .result = 2, .lhs = .{ .i64 = 5 }, .ty = .i64 },
        .{ .op = .binop, .result = 3, .lhs = .{ .local = 0 }, .rhs = .{ .temp = 2 }, .binop = .lt, .ty = .i64 },
        .{ .op = .br, .lhs = .{ .temp = 3 }, .branch_target = 19, .branch_condition = .when_false },
        .{ .op = .@"const", .result = 4, .lhs = .{ .i64 = 2 }, .ty = .i64 },
        .{ .op = .binop, .result = 5, .lhs = .{ .local = 0 }, .rhs = .{ .temp = 4 }, .binop = .eq, .ty = .i64 },
        .{ .op = .br, .lhs = .{ .temp = 5 }, .branch_target = 15, .branch_condition = .when_true },
        .{ .op = .@"const", .result = 6, .lhs = .{ .i64 = 4 }, .ty = .i64 },
        .{ .op = .binop, .result = 7, .lhs = .{ .local = 0 }, .rhs = .{ .temp = 6 }, .binop = .eq, .ty = .i64 },
        .{ .op = .br, .lhs = .{ .temp = 7 }, .branch_target = 19, .branch_condition = .when_true },
        .{ .op = .binop, .result = 8, .lhs = .{ .local = 1 }, .rhs = .{ .local = 0 }, .binop = .add, .ty = .i64 },
        .{ .op = .store_local, .result = 1, .lhs = .{ .temp = 8 }, .ty = .i64 },
        .{ .op = .@"const", .result = 9, .lhs = .{ .i64 = 1 }, .ty = .i64 },
        .{ .op = .binop, .result = 10, .lhs = .{ .local = 0 }, .rhs = .{ .temp = 9 }, .binop = .add, .ty = .i64 },
        .{ .op = .store_local, .result = 0, .lhs = .{ .temp = 10 }, .ty = .i64 },
        .{ .op = .br, .branch_target = 4, .branch_condition = .unconditional },
        .{ .op = .ret, .lhs = .{ .local = 1 }, .ty = .i64 },
    };
    const blocks = [_]dnir.Block{.{ .instrs = &instructions }};
    const functions = [_]dnir.Function{.{ .name = "main", .ret = .i64, .blocks = &blocks }};
    const module = dnir.Module{ .functions = &functions };
    var diagnostic: Diagnostic = .{};
    var output = try emitArm64FromDnir(alloc, module, null, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(output.graph == null);
    try std.testing.expectEqual(@as(usize, 0), output.lineage.len);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "b.eq") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "\tb .Lduo_") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "add x") != null);
    const object = try emitMachOArm64Object(
        alloc,
        output.text,
        output.cstring,
        output.symbols,
        output.relocations,
        output.bss_size,
    );
    defer alloc.free(object);
    try std.testing.expectEqual(@as(u32, 0xfeedfacf), std.mem.readInt(u32, object[0..4], .little));
}

test "native backend refuses source foreign call without graph lineage and retains relocation oracle" {
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

    try expectCheckedTestSemanticFailure(
        alloc,
        &mod,
        &sem,
        "missing-foreign-application-lineage",
        null,
    );

    const instructions = [_]dnir.Instr{
        .{ .op = .@"const", .result = 0, .lhs = .{ .i64 = -37 }, .ty = .i64 },
        .{ .op = .mov_arg, .result = 0, .lhs = .{ .temp = 0 }, .ty = .i64 },
        .{ .op = .call_extern, .result = 1, .callee = "llabs", .ty = .i64 },
        .{ .op = .@"const", .result = 2, .lhs = .{ .i64 = 5 }, .ty = .i64 },
        .{ .op = .binop, .result = 3, .lhs = .{ .temp = 1 }, .rhs = .{ .temp = 2 }, .binop = .add, .ty = .i64 },
        .{ .op = .ret, .lhs = .{ .temp = 3 }, .ty = .i64 },
    };
    const blocks = [_]dnir.Block{.{ .instrs = &instructions }};
    const functions = [_]dnir.Function{.{ .name = "main", .ret = .i64, .blocks = &blocks }};
    const module = dnir.Module{ .functions = &functions };
    var diagnostic: Diagnostic = .{};
    var output = try emitArm64FromDnir(alloc, module, null, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(output.graph == null);
    try std.testing.expectEqual(@as(usize, 0), output.lineage.len);
    try std.testing.expectEqual(@as(usize, 1), output.relocations.len);
    try std.testing.expectEqualStrings("llabs", output.symbols[output.relocations[0].symbol_index].name);
    try std.testing.expect(!output.symbols[output.relocations[0].symbol_index].defined);
    const object = try emitMachOArm64Object(
        alloc,
        output.text,
        output.cstring,
        output.symbols,
        output.relocations,
        output.bss_size,
    );
    defer alloc.free(object);
    try std.testing.expect(std.mem.indexOf(u8, object, "_llabs") != null);
}

test "native backend refuses source foreign string call and retains cstring relocation oracle" {
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

    try expectCheckedTestSemanticFailure(
        alloc,
        &mod,
        &sem,
        "missing-foreign-application-lineage",
        null,
    );

    const instructions = [_]dnir.Instr{
        .{ .op = .@"const", .result = 0, .lhs = .{ .str = "Hello" }, .ty = .str },
        .{ .op = .mov_arg, .result = 0, .lhs = .{ .temp = 0 }, .ty = .str },
        .{ .op = .call_extern, .result = 1, .callee = "puts", .ty = .i64 },
        .{ .op = .ret, .lhs = .{ .i64 = 0 }, .ty = .i64 },
    };
    const blocks = [_]dnir.Block{.{ .instrs = &instructions }};
    const functions = [_]dnir.Function{.{ .name = "main", .ret = .i64, .blocks = &blocks }};
    const module = dnir.Module{ .functions = &functions };
    var diagnostic: Diagnostic = .{};
    var output = try emitArm64FromDnir(alloc, module, null, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(output.graph == null);
    try std.testing.expectEqual(@as(usize, 0), output.lineage.len);
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

    const object = try emitMachOArm64Object(
        alloc,
        output.text,
        output.cstring,
        output.symbols,
        output.relocations,
        output.bss_size,
    );
    defer alloc.free(object);
    try std.testing.expect(std.mem.indexOf(u8, object, "__cstring") != null);
    try std.testing.expect(std.mem.indexOf(u8, object, "_puts") != null);
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

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&mod, &sem, &graph);
    var diagnostic: Diagnostic = .{};
    var object = try emitSharedObjectInputWithGraphLineageObserved(
        alloc,
        &mod,
        &graph,
        &diagnostic,
    );
    defer object.deinit(alloc);
    try std.testing.expect(std.mem.indexOf(u8, object.bytes, "_duo_native_add") != null);
    try std.testing.expect(std.mem.indexOf(u8, object.bytes, "_main") == null);
}

test "native backend refuses source register reuse absent application operand ABI facts" {
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

    try expectCheckedTestSemanticFailure(
        alloc,
        &mod,
        &sem,
        "graph-dnir-facts",
        "application-operand-abi",
    );
}

test "native backend authority-false physical call oracle narrows register saves" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    const parameters = [_]dnir.Param{.{ .name = "n", .ty = .i64 }};
    const id_instructions = [_]dnir.Instr{
        .{ .op = .ret, .lhs = .{ .temp = 0 }, .ty = .i64 },
    };
    const main_instructions = [_]dnir.Instr{
        .{ .op = .@"const", .result = 0, .lhs = .{ .i64 = 40 }, .ty = .i64 },
        .{ .op = .store_local, .result = 0, .lhs = .{ .temp = 0 }, .ty = .i64 },
        .{ .op = .@"const", .result = 1, .lhs = .{ .i64 = 2 }, .ty = .i64 },
        .{ .op = .store_local, .result = 1, .lhs = .{ .temp = 1 }, .ty = .i64 },
        .{ .op = .mov_arg, .result = 0, .lhs = .{ .local = 0 }, .ty = .i64 },
        .{ .op = .call_direct, .result = 2, .callee = "id", .ty = .i64 },
        .{ .op = .binop, .result = 3, .lhs = .{ .temp = 2 }, .rhs = .{ .local = 1 }, .binop = .add, .ty = .i64 },
        .{ .op = .ret, .lhs = .{ .temp = 3 }, .ty = .i64 },
    };
    const id_blocks = [_]dnir.Block{.{ .instrs = &id_instructions }};
    const main_blocks = [_]dnir.Block{.{ .instrs = &main_instructions }};
    const functions = [_]dnir.Function{
        .{ .name = "id", .ret = .i64, .params = &parameters, .blocks = &id_blocks },
        .{ .name = "main", .ret = .i64, .blocks = &main_blocks },
    };
    const module = dnir.Module{ .functions = &functions };
    var diagnostic: Diagnostic = .{};
    var output = try emitArm64FromDnir(alloc, module, null, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(output.graph == null);
    try std.testing.expectEqual(@as(usize, 0), output.lineage.len);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "\tsub sp, sp, #176\n") == null);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "\tstr x30, [sp, #") != null);
    const object = try emitMachOArm64Object(
        alloc,
        output.text,
        output.cstring,
        output.symbols,
        output.relocations,
        output.bss_size,
    );
    defer alloc.free(object);
    try std.testing.expect(std.mem.indexOf(u8, object, "_id") != null);
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

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&mod, &sem, &graph);
    var assembly = try emitCheckedTestAssembly(alloc, &mod, &graph, null);
    defer assembly.deinit(alloc);
    const asm_text = assembly.assembly;

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

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&mod, &sem, &graph);
    var assembly = try emitCheckedTestAssembly(alloc, &mod, &graph, null);
    defer assembly.deinit(alloc);
    const asm_text = assembly.assembly;
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

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&mod, &sem, &graph);
    var assembly = try emitCheckedTestAssembly(alloc, &mod, &graph, null);
    defer assembly.deinit(alloc);
    const asm_text = assembly.assembly;
    try std.testing.expect(std.mem.indexOf(u8, asm_text, ".globl _add") != null);
    try std.testing.expect(std.mem.indexOf(u8, asm_text, ".globl _main") != null);
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "\tbl _add\n") != null);
}

test "native backend refuses source print absent application facts and retains physical print oracle" {
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

    try expectCheckedTestSemanticFailure(
        alloc,
        &mod,
        &sem,
        "unresolved-application-facts",
        null,
    );

    const instructions = [_]dnir.Instr{
        .{ .op = .@"const", .result = 0, .lhs = .{ .i64 = 1 }, .ty = .i64 },
        .{ .op = .print_value, .lhs = .{ .temp = 0 }, .ty = .i64 },
        .{ .op = .ret, .lhs = .{ .i64 = 0 }, .ty = .i64 },
    };
    const blocks = [_]dnir.Block{.{ .instrs = &instructions }};
    const functions = [_]dnir.Function{.{ .name = "main", .ret = .i64, .blocks = &blocks }};
    const module = dnir.Module{ .functions = &functions };
    var diagnostic: Diagnostic = .{};
    var output = try emitArm64FromDnir(alloc, module, null, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(output.graph == null);
    try std.testing.expectEqual(@as(usize, 0), output.lineage.len);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "bl _printf") != null);
    const object = try emitMachOArm64Object(
        alloc,
        output.text,
        output.cstring,
        output.symbols,
        output.relocations,
        output.bss_size,
    );
    defer alloc.free(object);
    try std.testing.expect(std.mem.indexOf(u8, object, "_printf") != null);
}

test "native backend refuses source sealed record application absent graph identity facts" {
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

    try expectCheckedTestSemanticFailure(
        alloc,
        &mod,
        &sem,
        "graph-dnir-facts",
        "missing-application-id",
    );
}

test "native backend refuses raw byte source absent graph byte facts" {
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

    try expectCheckedTestSemanticFailure(
        alloc,
        &mod,
        &sem,
        "unresolved-application-facts",
        null,
    );
}

test "native backend authority-false physical byte load oracle" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    const parameters = [_]dnir.Param{.{ .name = "base", .ty = .i64 }};
    const instructions = [_]dnir.Instr{
        .{ .op = .@"const", .result = 1, .lhs = .{ .i64 = 3 }, .ty = .i64 },
        .{ .op = .load_index, .result = 2, .lhs = .{ .temp = 0 }, .rhs = .{ .temp = 1 }, .ty = .u8 },
        .{ .op = .ret, .lhs = .{ .temp = 2 }, .ty = .i64 },
    };
    const blocks = [_]dnir.Block{.{ .instrs = &instructions }};
    const functions = [_]dnir.Function{.{
        .name = "read",
        .ret = .i64,
        .params = &parameters,
        .blocks = &blocks,
    }};
    const module = dnir.Module{ .functions = &functions };
    var diagnostic: Diagnostic = .{};
    var output = try emitArm64FromDnir(alloc, module, null, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(output.graph == null);
    try std.testing.expectEqual(@as(usize, 0), output.lineage.len);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "ldrb") != null);
    try std.testing.expectEqual(@as(usize, 0), output.cstring.len);
    try std.testing.expectEqual(@as(usize, 0), output.relocations.len);
    const object = try emitMachOArm64Object(
        alloc,
        output.text,
        output.cstring,
        output.symbols,
        output.relocations,
        output.bss_size,
    );
    defer alloc.free(object);
    try std.testing.expectEqual(@as(u32, 0xfeedfacf), std.mem.readInt(u32, object[0..4], .little));
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

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&mod, &sem, &graph);
    var object = try emitCheckedTestObject(alloc, &mod, &graph);
    defer object.deinit(alloc);
    try std.testing.expect(object.bytes.len > 0);
}

test "native backend refuses unresolved byte call and retains branch-field physical oracle" {
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

    try expectCheckedTestSemanticFailure(
        alloc,
        &mod,
        &sem,
        "unresolved-application-facts",
        null,
    );

    const instructions = [_]dnir.Instr{
        .{ .op = .@"const", .result = 0, .lhs = .{ .str = "\x00asm" }, .ty = .str },
        .{ .op = .@"const", .result = 1, .lhs = .{ .i64 = 1 }, .ty = .i64 },
        .{ .op = .load_index, .result = 2, .lhs = .{ .temp = 0 }, .rhs = .{ .temp = 1 }, .ty = .u8 },
        .{ .op = .@"const", .result = 3, .lhs = .{ .i64 = 0 }, .ty = .i64 },
        .{ .op = .binop, .result = 4, .lhs = .{ .temp = 2 }, .rhs = .{ .temp = 3 }, .binop = .neq, .ty = .i64 },
        .{ .op = .br, .lhs = .{ .temp = 4 }, .branch_target = 7, .branch_condition = .when_false },
        .{ .op = .ret, .lhs = .{ .i64 = 1001 }, .ty = .i64 },
        .{ .op = .@"const", .result = 5, .lhs = .{ .i64 = 0 }, .ty = .i64 },
        .{ .op = .store_local, .result = 10, .lhs = .{ .temp = 5 }, .record = "Cursor", .field = "pos", .ty = .i64 },
        .{ .op = .@"const", .result = 6, .lhs = .{ .i64 = 1 }, .ty = .i64 },
        .{ .op = .binop, .result = 7, .lhs = .{ .local = 10 }, .rhs = .{ .temp = 6 }, .binop = .add, .ty = .i64 },
        .{ .op = .store_local, .result = 10, .lhs = .{ .temp = 7 }, .record = "Cursor", .field = "pos", .ty = .i64 },
        .{ .op = .@"const", .result = 8, .lhs = .{ .i64 = 1 }, .ty = .i64 },
        .{ .op = .binop, .result = 9, .lhs = .{ .local = 10 }, .rhs = .{ .temp = 8 }, .binop = .neq, .ty = .i64 },
        .{ .op = .br, .lhs = .{ .temp = 9 }, .branch_target = 16, .branch_condition = .when_false },
        .{ .op = .ret, .lhs = .{ .i64 = 1006 }, .ty = .i64 },
        .{ .op = .ret, .lhs = .{ .i64 = 0 }, .ty = .i64 },
    };
    const blocks = [_]dnir.Block{.{ .instrs = &instructions }};
    const functions = [_]dnir.Function{.{ .name = "main", .ret = .i64, .blocks = &blocks }};
    const module = dnir.Module{ .functions = &functions };
    var diagnostic: Diagnostic = .{};
    var output = try emitArm64FromDnir(alloc, module, null, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(output.graph == null);
    try std.testing.expectEqual(@as(usize, 0), output.lineage.len);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "ldrb") != null);
    try std.testing.expect(std.mem.count(u8, output.asm_text, "add x") >= 2);
    try std.testing.expect(std.mem.count(u8, output.asm_text, "b.eq") >= 2);
    const object = try emitMachOArm64Object(
        alloc,
        output.text,
        output.cstring,
        output.symbols,
        output.relocations,
        output.bss_size,
    );
    defer alloc.free(object);
    try std.testing.expectEqual(@as(u32, 0xfeedfacf), std.mem.readInt(u32, object[0..4], .little));
}

test "unused immediate bindings do not demand register or stack places" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source =
        \\main: i64 = ()
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
    ;
    var lex = Lexer.init(source, "pass11_spill_proof.id");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&mod, &sem, &graph);
    var assembly = try emitCheckedTestAssembly(alloc, &mod, &graph, null);
    defer assembly.deinit(alloc);
    const listing = assembly.assembly;
    try std.testing.expect(std.mem.indexOf(u8, listing, "\tstr x") == null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "\tldr x") == null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "\tsub sp") == null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "lua_") == null);

    var object = try emitCheckedTestObject(alloc, &mod, &graph);
    defer object.deinit(alloc);
    try std.testing.expect(object.bytes.len > 0);

    const minimal_source =
        \\main: i64 = ()
        \\    v0 = 1
        \\    v21 = 1
        \\    v0 + v21
    ;
    var minimal_lex = Lexer.init(minimal_source, "unused-binding-minimal.id");
    var minimal_parser = Parser.init(&minimal_lex, alloc);
    minimal_parser.duo_mode = true;
    var minimal_mod = try minimal_parser.parse_module();
    var minimal_sem = Sema.init(alloc);
    defer minimal_sem.deinit();
    minimal_sem.duo_mode = true;
    try minimal_sem.check_module(&minimal_mod);

    var minimal_graph = semantic_graph.SemanticGraph.init(alloc);
    defer minimal_graph.deinit();
    try liftCheckedTestGraph(&minimal_mod, &minimal_sem, &minimal_graph);
    var minimal_assembly = try emitCheckedTestAssembly(alloc, &minimal_mod, &minimal_graph, null);
    defer minimal_assembly.deinit(alloc);
    try std.testing.expectEqualStrings(minimal_assembly.assembly, listing);
    var minimal_object = try emitCheckedTestObject(alloc, &minimal_mod, &minimal_graph);
    defer minimal_object.deinit(alloc);
    try std.testing.expectEqualSlices(u8, minimal_object.bytes, object.bytes);
}

test "more live integer values than registers refuses without aliasing owners" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source =
        \\main: i64 = ()
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
        \\    v0 + v1 + v2 + v3 + v4 + v5 + v6 + v7 + v8 + v9 + v10 + v11 + v12 + v13 + v14 + v15 + v16 + v17 + v18 + v19
    ;
    var lex = Lexer.init(source, "live-register-pressure.id");
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&mod, &sem, &graph);
    var diagnostic: Diagnostic = .{};
    try std.testing.expectError(
        error.RegisterExhausted,
        emitAssemblyWithGraphLineageObserved(
            alloc,
            &mod,
            "native-asm",
            &graph,
            &diagnostic,
        ),
    );
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

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&mod, &sem, "indirect_ret.duo");
    try std.testing.expectEqual(@as(usize, 1), graph.applications().len);

    var assembly = try emitAssemblyWithGraphLineage(alloc, &mod, "native-asm", &graph);
    defer assembly.deinit(alloc);
    const listing = assembly.assembly;

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

    var object = try emitObjectWithGraphLineage(alloc, &mod, "native-object", &graph);
    defer object.deinit(alloc);
    try std.testing.expect(object.bytes.len > 0);
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

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&mod, &sem, &graph);
    var assembly = try emitCheckedTestAssembly(alloc, &mod, &graph, null);
    defer assembly.deinit(alloc);
    const listing = assembly.assembly;

    // Every one of the eight ABI registers is written, including the eighth.
    try std.testing.expect(std.mem.indexOf(u8, listing, "mov x7,") != null);
    // And no indirect buffer is set up — this path stays in registers.
    try std.testing.expect(std.mem.indexOf(u8, listing, "add x8, sp,") == null);
    // x18 is Apple's reserved platform register; eight staged fields is the
    // pressure that used to reach it.
    try std.testing.expect(std.mem.indexOf(u8, listing, "x18") == null);

    var object = try emitCheckedTestObject(alloc, &mod, &graph);
    defer object.deinit(alloc);
    try std.testing.expect(object.bytes.len > 0);
}
