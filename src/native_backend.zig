const std = @import("std");
const builtin = @import("builtin");
const ast = @import("ast.zig");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;
const dnir = @import("native_ir.zig");
const c_signatures = @import("c_signatures.zig");
const native_types = @import("types.zig");
const dnir_lower = @import("dnir_lower.zig");
const dnir_hardware = @import("dnir_hardware.zig");
const semantic_graph = @import("semantic_graph.zig");
const table_apply = @import("table_apply.zig");
const const_table = @import("const_table.zig");
const region_graph = @import("region_graph.zig");

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
    target: semantic_graph.id,
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
    /// Physical undefined linker names (no leading `_`). Owned. Not semantic
    /// identity — the link line consumes these to select bootstrap objects.
    need: [][]const u8 = &.{},

    pub fn deinit(self: *ObjectWithLineage, alloc: std.mem.Allocator) void {
        alloc.free(self.bytes);
        alloc.free(self.lineage);
        for (self.need) |name| alloc.free(name);
        alloc.free(self.need);
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
    /// Exact application id when the refusal is about one occurrence.
    /// Null is unknown — never a sentinel zero.
    application: ?semantic_graph.id = null,
    /// Diagnostic projection of the occurrence's relation/method face.
    /// Borrowed from the resident graph or AST; not a second identity.
    relation: ?[]const u8 = null,
    lowering: dnir_lower.Diagnostic = .{},

    pub fn reset(self: *Diagnostic) void {
        self.site = null;
        self.note_len = 0;
        self.application = null;
        self.relation = null;
        self.lowering.reset();
    }

    pub fn bindOccurrence(
        self: *Diagnostic,
        graph: *const semantic_graph.SemanticGraph,
        occurrence: semantic_graph.id,
    ) void {
        self.application = occurrence;
        self.relation = occurrenceFace(graph, occurrence);
    }

    pub fn remember(self: *Diagnostic, detail: []const u8) void {
        self.record(@src(), detail);
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

fn occurrenceFace(graph: *const semantic_graph.SemanticGraph, entity: semantic_graph.id) ?[]const u8 {
    const node = graph.get(entity) orelse return null;
    if (node.ast_ref) |raw| {
        const expr: *const ast.Expr = @ptrCast(@alignCast(raw));
        return switch (expr.*) {
            .call => |c| switch (c.func.*) {
                .name => |n| n.ident,
                .field => |f| f.field,
                else => node.name,
            },
            .method_call => |mc| mc.method,
            else => node.name,
        };
    }
    return node.name;
}

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

/// `law.crash.first`: DNB001/DNB011 name application, missing fact, consumer, producer.
/// Category prose is the fallback when the attempt recorded no cause.
pub fn formatDirectCause(
    err: Error,
    target: []const u8,
    buf: []u8,
    diagnostic: ?*const Diagnostic,
) []const u8 {
    const d = directDiagnostic(err, target);
    const causal = err == error.SemanticFactsInvalid or err == error.UnsupportedProgram;
    if (!causal) {
        return std.fmt.bufPrint(buf, "{s}: {s}", .{ d.code, d.message }) catch d.message;
    }
    const missing = if (diagnostic) |diag|
        diag.lowering.note() orelse diag.note()
    else
        null;
    const application = if (diagnostic) |diag|
        diag.application orelse diag.lowering.application
    else
        null;
    const relation = if (diagnostic) |diag| diag.relation orelse diag.lowering.relation else null;
    const producer: []const u8 = if (err == error.SemanticFactsInvalid)
        "graph"
    else
        "dnir lower";
    const miss = missing orelse "unspecified";
    if (application) |id| {
        if (relation) |rel| {
            return std.fmt.bufPrint(
                buf,
                "{s} application: {d} relation: {s} missing: {s} consumer: native realization producer: {s}",
                .{ d.code, id, rel, miss, producer },
            ) catch d.message;
        }
        return std.fmt.bufPrint(
            buf,
            "{s} application: {d} missing: {s} consumer: native realization producer: {s}",
            .{ d.code, id, miss, producer },
        ) catch d.message;
    }
    if (relation) |rel| {
        return std.fmt.bufPrint(
            buf,
            "{s} application: unknown relation: {s} missing: {s} consumer: native realization producer: {s}",
            .{ d.code, rel, miss, producer },
        ) catch d.message;
    }
    return std.fmt.bufPrint(
        buf,
        "{s} application: unknown missing: {s} consumer: native realization producer: {s}",
        .{ d.code, miss, producer },
    ) catch d.message;
}

pub fn formatDirectError(err: Error, target: []const u8, buf: []u8) []const u8 {
    return formatDirectCause(err, target, buf, null);
}

pub fn describeError(err: anyerror, target: []const u8, buf: []u8) []const u8 {
    return describeCause(err, target, buf, null);
}

pub fn describeCause(
    err: anyerror,
    target: []const u8,
    buf: []u8,
    diagnostic: ?*const Diagnostic,
) []const u8 {
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
        => return formatDirectCause(@errorCast(err), target, buf, diagnostic),
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

/// When `entry` is set the named zero-arg function
/// gets `fcvtzs x0, d0` on f64 returns so native executables receive an i64 exit code.
pub fn emitObjectForExecutableWithGraphLineage(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    entry: []const u8,
    graph: *const semantic_graph.SemanticGraph,
) Error!ObjectWithLineage {
    var diagnostic: Diagnostic = .{};
    return emitObjectForExecutableWithGraphLineageObserved(alloc, mod, entry, graph, &diagnostic);
}

pub fn emitObjectForExecutableWithGraphLineageObserved(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    entry: []const u8,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error!ObjectWithLineage {
    diagnostic.reset();
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) {
        return error.UnsupportedTarget;
    }
    return emitObjectModeWithGraphLineage(alloc, mod, entry, graph, diagnostic);
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
    entry: ?[]const u8,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error!ObjectWithLineage {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) {
        return error.UnsupportedTarget;
    }

    var output = try emitArm64ModuleWithGraph(alloc, mod, entry, graph, diagnostic);
    defer output.deinit(alloc);
    if (output.graph != graph) return invalidFactsWith(diagnostic, @src(), "object-graph-context");
    const bytes = try emitMachOArm64ObjectWithConst(
        alloc,
        output.text,
        output.cstring,
        output.const_data,
        output.symbols,
        output.relocations,
        output.bss_size,
    );
    errdefer alloc.free(bytes);

    const text_offset = machOTextOffset(output.cstring.len, output.const_data.len, output.bss_size);
    const lineage = try alloc.dupe(MachineLineage, output.lineage);
    errdefer alloc.free(lineage);
    for (lineage) |*row| {
        row.object_start = @intCast(text_offset + row.text_start);
        row.object_end = @intCast(text_offset + row.text_end);
    }
    var need = try std.ArrayListUnmanaged([]const u8).initCapacity(alloc, output.symbols.len);
    errdefer {
        for (need.items) |name| alloc.free(name);
        need.deinit(alloc);
    }
    for (output.symbols) |sym| {
        if (sym.defined) continue;
        need.appendAssumeCapacity(try alloc.dupe(u8, sym.name));
    }
    return .{
        .bytes = bytes,
        .lineage = lineage,
        .graph = graph,
        .need = try need.toOwnedSlice(alloc),
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
    entry: []const u8,
    graph: *const semantic_graph.SemanticGraph,
) Error!AssemblyWithLineage {
    var diagnostic: Diagnostic = .{};
    return emitAssemblyForExecutableWithGraphLineageObserved(alloc, mod, entry, graph, &diagnostic);
}

pub fn emitAssemblyForExecutableWithGraphLineageObserved(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    entry: []const u8,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error!AssemblyWithLineage {
    diagnostic.reset();
    return emitAssemblyModeWithGraphLineage(alloc, mod, entry, graph, diagnostic);
}

fn emitAssemblyModeWithGraphLineage(
    alloc: std.mem.Allocator,
    mod: *const ast.Module,
    entry: ?[]const u8,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error!AssemblyWithLineage {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) {
        return error.UnsupportedTarget;
    }
    var output = try emitArm64ModuleWithGraph(alloc, mod, entry, graph, diagnostic);
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
    // Section index, 1-based over the sections this object actually emits:
    // 1 = __TEXT,__text, then __TEXT,__cstring and __TEXT,__const in that order
    // when they are non-empty. A promoted table's index is therefore not a
    // constant — `finish` stamps it once it knows whether any string exists.
    section: u8 = 1,
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

fn scalRecordDesc(records: *const ScalRecordMap, name: []const u8) ?ScalRecordDesc {
    return records.get(name);
}

fn f64RecordDesc(records: *const F64RecordMap, name: []const u8) ?F64RecordDesc {
    return records.get(name);
}

const Condition = enum(u4) {
    eq = 0x0,
    ne = 0x1,
    // UNSIGNED. `hi`/`ls` are not spellings of `gt`/`le` — they read the carry
    // flag, not the sign, which is what makes ONE compare answer a two-sided
    // range test: `(i - 1) <=u (len - 1)` is false for every i below 1 as well
    // as every i above len, because 0 - 1 wraps to the largest unsigned value.
    // No DNIR binop maps to either; they exist for the index bounds check.
    hi = 0x8,
    ls = 0x9,
    ge = 0xa,
    lt = 0xb,
    gt = 0xc,
    le = 0xd,
};

const Arm64Output = struct {
    text: []u8,
    asm_text: []u8,
    cstring: []u8 = &.{},
    /// Bytes of `__TEXT,__const` — determined positional tables that became
    /// read-only data instead of being built word by word at run time.
    ///
    /// NOT `__cstring`, AND NOT `__text`. `__cstring` is `S_CSTRING_LITERALS`:
    /// the linker splits and dedups it at NUL bytes, and a table of i64 literals
    /// is full of them, so a blob put there would be silently corrupted. `__text`
    /// would make the data count as INSTRUCTIONS under `otool -tV`, corrupting
    /// every measurement on this surface — the collapse gate, the perf baseline,
    /// the frontier rows. `S_REGULAR` in its own section is the only placement
    /// that is neither.
    const_data: []u8 = &.{},
    symbols: []Symbol,
    relocations: []Relocation,
    lineage: []MachineLineage = &.{},
    /// Borrowed physical context for the ids in `lineage`.
    graph: ?*const semantic_graph.SemanticGraph = null,
    /// Bytes of `__DATA,__bss` zerofill arena this module needs. 0 means the
    /// section is not emitted at all, which is the pre-arena behavior verbatim.
    bss_size: u64 = 0,
    cost: []CostEntry = &.{},

    fn deinit(self: *Arm64Output, alloc: std.mem.Allocator) void {
        alloc.free(self.text);
        alloc.free(self.asm_text);
        if (self.cstring.len > 0) alloc.free(self.cstring);
        if (self.const_data.len > 0) alloc.free(self.const_data);
        for (self.symbols) |sym| alloc.free(sym.name);
        alloc.free(self.symbols);
        alloc.free(self.relocations);
        if (self.lineage.len > 0) alloc.free(self.lineage);
        for (self.cost) |entry| alloc.free(entry.reason);
        if (self.cost.len > 0) alloc.free(self.cost);
    }

    fn deinitExceptAssembly(self: *Arm64Output, alloc: std.mem.Allocator) void {
        alloc.free(self.text);
        if (self.cstring.len > 0) alloc.free(self.cstring);
        if (self.const_data.len > 0) alloc.free(self.const_data);
        for (self.symbols) |sym| alloc.free(sym.name);
        alloc.free(self.symbols);
        alloc.free(self.relocations);
        if (self.lineage.len > 0) alloc.free(self.lineage);
    }

    fn deinitExceptAssemblyMachineAndLineage(self: *Arm64Output, alloc: std.mem.Allocator) void {
        if (self.cstring.len > 0) alloc.free(self.cstring);
        if (self.const_data.len > 0) alloc.free(self.const_data);
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

/// Linker ABI name for a native executable. Not a source binding.
/// `@export`, a declared `main`, and `--entry` are deliberate. A file-scope
/// tail is the program: physical `main` without a source `main`. A sole
/// zero-arg function is an inference only when there is no file-scope body.
pub fn abi(mod: *const ast.Module, want: ?[]const u8) ?[]const u8 {
    if (want) |name| {
        const fd = findModuleFunction(mod, name) orelse return null;
        if (!isZeroArgEntryFunction(fd)) return null;
        return name;
    }
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
    if (mod.program()) return "main";
    if (sole_count == 1) return sole;
    return null;
}

pub const CostKind = enum {
    extern_call,
    string_intern_hash,
    spill,
    stack_local,
};

pub const CostEntry = struct {
    kind: CostKind,
    reason: []const u8,
};

pub const CostLedger = struct {
    entries: std.ArrayList(CostEntry) = .empty,

    pub fn deinit(self: *CostLedger, alloc: std.mem.Allocator) void {
        for (self.entries.items) |entry| alloc.free(entry.reason);
        self.entries.deinit(alloc);
    }

    pub fn record(self: *CostLedger, alloc: std.mem.Allocator, kind: CostKind, reason: []const u8) !void {
        try self.entries.append(alloc, .{
            .kind = kind,
            .reason = try alloc.dupe(u8, reason),
        });
    }
};

/// GP value registers the allocator may hand out: x9–x17 (nine — x18 is Apple's
/// reserved platform register) and x19–x28 (ten).
const gp_allocatable: u32 = 19;
/// Registers held back from long-lived homes so every instruction has somewhere
/// to compute. Five is what a record store-and-index sequence peaks at.
const gp_scratch_floor: u32 = 5;

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
    /// What the SOURCE facts permit to become read-only data. Borrowed; empty
    /// when the caller had no source module in hand, and an empty licence
    /// promotes nothing, so every DNIR-only entry point keeps today's emission
    /// byte for byte.
    const_licence: ?*const const_table.Licence = null,
    /// Promoted tables of the function being compiled: `alloc_slots` result temp
    /// -> the `__TEXT,__const` symbol its base address relocates against.
    /// Cleared per function.
    const_bases: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    /// The module's `__TEXT,__const` payload, one i64 word per entry.
    const_words: std.ArrayList(i64) = .empty,
    const_tables: std.ArrayList(ConstTableSymbol) = .empty,
    next_const: u32 = 0,
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
    entry: ?[]const u8 = null,
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
    /// GP temp ownership and local homes — same contract as the FP fields above.
    gp_reg_owner: [32]?u32 = @splat(null),
    gp_home_regs: [32]bool = @splat(false),
    /// Argument registers (x0..x7) already STAGED for the call currently being
    /// marshaled. A multi-argument call stages a2→x0, a1→x1, … in order; a later
    /// argument whose operand must be LOADED needs a scratch register, and once
    /// x9..x28 are exhausted `allocRegExcluding` falls back into x0..x7 — handing
    /// out a low register that already holds a staged earlier argument. That
    /// clobbers the earlier arg silently (the callee then reads x0 = q instead of
    /// a2), a wrong answer rather than a refusal. Each bit set here is a staged
    /// arg register that must not be reallocated as scratch until the `bl`
    /// consumes it; `emitBl` clears the mask. Zero outside argument marshaling,
    /// so it never perturbs code that is not staging a call.
    pending_arg_regs: u8 = 0,
    /// How many locals may keep a REGISTER home for the whole function.
    ///
    /// This has to be smaller than the pool, and it was not: x9–x17 and x19–x28
    /// are nineteen allocatable registers (x18 is Apple's reserved platform
    /// register), and the budget was twenty. Every instruction also needs
    /// scratch, so a body that actually claimed its allowance had nothing left
    /// to compute with and refused DNB003.
    ///
    /// It never showed, because the budget is only consulted when locals are NOT
    /// all being spilled — that is, in a function with no call — and until the
    /// bounds trap stopped being `call_extern abort` a function that indexed a
    /// table dynamically was a "caller" and never reached this path. A
    /// twenty-element select-chain loop is the smallest program that does:
    /// leaf, ~20 locals, and it went straight from 33 to DNB003.
    ///
    /// Gate transport raises it (`m.graph.gateTransportModule()`), which is safe
    /// for the same structural reason: those bodies call `gatecap`, so their
    /// locals are stack-homed and this number is never read.
    gp_local_home_budget: u32 = gp_allocatable - gp_scratch_floor,
    spill_frame_budget: u16 = 65520,
    /// Gate/ledger transport: allow reclaiming spilled temp registers when the
    /// pool is exhausted instead of refusing with DNB003.
    gate_transport: bool = false,
    /// Param slot count for the function being compiled; used to stack-spill
    /// incoming str/any params in gate transport (x0-x7 do not survive gatecap).
    gate_param_slots: u32 = 0,
    /// Active `pinned` map while lowering one function; `evalDnirValue` consults
    /// it before `temps` so gatecap cannot serve stale register homes.
    eval_pinned: ?*const std.AutoHashMapUnmanaged(u32, u5) = null,
    cur_func_has_call: bool = false,
    /// Last instruction that reads each DNIR value/slot id. The map is shared
    /// by both register files; physical file selection is a separate fact.
    value_free_at: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    fp_abi_passthrough: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Loop-invariant immediate hoisting (FTCFTW debt (1); GAP-172 / GAP-169).
    /// A `.i64` constant used inside a loop is otherwise re-materialized by a
    /// fresh `mov`/`movk` chain every iteration (evidence/recurrence.txt: ~13 of
    /// ~21 hot-loop instructions). `hoist_plan` records, per loop head, the
    /// distinct constants worth pre-materializing into a reserved register in the
    /// preheader; `imm_hoist` maps a currently-hoisted constant to that register
    /// so `evalDnirValue` returns it instead of re-emitting. Constants are
    /// loop-invariant by definition, so this is the safest possible motion — no
    /// aliasing, effect, or order obligation is involved (law.observation.minimum).
    imm_hoist: std.AutoHashMapUnmanaged(i64, u5) = .empty,
    hoist_plan: std.AutoHashMapUnmanaged(u32, HoistPlan) = .empty,
    hoist_active: [max_hoist_depth]HoistActive = @splat(.{}),
    hoist_depth: u8 = 0,
    /// Loop head flat index -> code offset where that head's preheader `mov`s
    /// begin. The preheader is emitted BEFORE the head's `code_offsets` entry so
    /// the back edge re-enters after it, which is right for the back edge and
    /// WRONG for every other way in. A loop preceded by an `if` is entered by a
    /// FORWARD branch to the head — both the `b.cond` that skips the then-block
    /// and the `b` that ends it target the head — and both landed past the
    /// preheader, so the loop ran against registers that were never initialized.
    /// That is the declare/branch/loop silent wrong answer. Forward branches are
    /// re-pointed at this offset in the patch pass; back edges keep the head's
    /// own offset. Emptied per function with the rest of the hoist state.
    hoist_preheader: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    /// Stack slots for sealed record fields (f64 or i64): "c.pos" -> slot meta.
    fp_stack_slots: std.StringHashMapUnmanaged(StackSlot) = .empty,
    stack_frame_bytes: u16 = 0,
    /// x19–x28 belong to the caller. Saved under the locals/spill frame so
    /// `[sp,#off]` homes stay zero-based. Without this, `strip`'s `i += 1`
    /// left x19–x21 in the caller's registers and `callfirstrel` SIGSEGV'd.
    callee_save_bytes: u16 = 0,
    /// STICKY record of every callee-saved register (x19–x28) this function's
    /// body has claimed. `used_regs` is cleared on release, so it answers "is
    /// this register busy right now", which is not the question the prologue
    /// asks. Bit `r` set means x`r` was written at some point and its incoming
    /// value therefore has to be preserved.
    callee_touched: u32 = 0,
    /// The set the prologue actually saves. `callee_save_all` is the old
    /// unconditional block; a probe pass narrows it to `callee_touched`.
    callee_save_plan: u32 = 0,
    /// `alloc_slots` result temp -> sp-relative byte offset of its slot region.
    slot_bases: std.AutoHashMapUnmanaged(u32, u16) = .empty,
    spilled_regs: std.AutoHashMapUnmanaged(u5, u16) = .empty,
    /// Spill slots returned to the pool when a spilled register reloads.
    free_spill_slots: std.ArrayList(u16) = .empty,
    /// Locals spilled to the stack frame when the GP home budget is exhausted.
    gp_stack_locals: std.AutoHashMapUnmanaged(u32, u16) = .empty,
    /// Pre-reserved temp spill pool when GP locals already occupy [sp,#off].
    /// Mid-function `sub sp` would invalidate those fixed offsets (gate scripts).
    gate_spill_base: u16 = 0,
    gate_spill_end: u16 = 0,
    gate_spill_cursor: u16 = 0,
    /// `snprintf(buf, …)` returns a length in x0 and clobbers caller-saved
    /// registers that may still own `buf` in the temp map.
    extern_preserve_x0: bool = false,
    extern_preserve_x0_temp: ?u32 = null,
    cost: CostLedger = .{},
    /// Arguments staged for the NEXT call's variadic tail. Apple's ARM64 ABI
    /// diverges from AAPCS64 here: every argument past a variadic function's
    /// last NAMED parameter travels on the STACK, 8-byte aligned, never in
    /// x0..x7. A `mov_arg` marked `.field = "vararg"` lands here instead of in
    /// a parameter register, and the call flushes the list to [sp, #i*8].
    pending_varargs: [8]VarArg = @splat(.{}),
    pending_vararg_count: u5 = 0,

    /// Max distinct constants hoisted per loop, and max loop-nest depth tracked.
    /// Bounded so hoisting never starves the scratch pool into a spill; deeper
    /// or wider loops simply hoist their most expensive constants and leave the
    /// rest to inline materialization.
    const max_hoist_per_loop = 8;
    const max_hoist_depth = 8;

    const HoistPlan = struct {
        latch: u32 = 0,
        count: u8 = 0,
        values: [max_hoist_per_loop]i64 = @splat(0),
    };

    const HoistActive = struct {
        latch: u32 = 0,
        count: u8 = 0,
        values: [max_hoist_per_loop]i64 = @splat(0),
        regs: [max_hoist_per_loop]u5 = @splat(0),
    };

    const VarArg = struct {
        reg: u5 = 0,
        /// When set, the operand is evaluated immediately before the tail is
        /// written to the stack — after named `mov_arg` slots and any
        /// `preserve_x0` staging for `snprintf`, so a hole is not read from a
        /// register that was clobbered between `mov_arg` and `emitPushVarargs`.
        operand: ?dnir.Value = null,
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
        regs: [28]u5 = @splat(0),
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

    /// One promoted table's place in `__TEXT,__const`. It owns NO memory: the
    /// name belongs to `symbols` and the words to `const_words`, so there is
    /// exactly one owner of each and nothing to double-free when `finish`
    /// hands the symbol table to the output.
    const ConstTableSymbol = struct {
        symbol_index: u32,
        word_off: u32,
        word_len: u32,
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
        self.const_bases.deinit(self.alloc);
        self.const_words.deinit(self.alloc);
        self.const_tables.deinit(self.alloc);
        self.fp_locals.deinit(self.alloc);
        self.fp_temps.deinit(self.alloc);
        self.value_free_at.deinit(self.alloc);
        self.imm_hoist.deinit(self.alloc);
        self.hoist_plan.deinit(self.alloc);
        self.hoist_preheader.deinit(self.alloc);
        self.fp_abi_passthrough.deinit(self.alloc);
        self.fp_stack_slots.deinit(self.alloc);
        self.slot_bases.deinit(self.alloc);
        self.spilled_regs.deinit(self.alloc);
        self.free_spill_slots.deinit(self.alloc);
        self.gp_stack_locals.deinit(self.alloc);
        self.cost.deinit(self.alloc);
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
        // `__TEXT,__const` — the determined tables, as data.
        //
        // THE VM LAYOUT THE SYMBOLS ARE MEASURED AGAINST. A relocatable object's
        // sections are laid out here at __text, then __cstring, then __const, and
        // a defined local symbol's `n_value` is its ABSOLUTE address in that
        // layout — never a section-relative offset, which clang's linker rejects
        // (the same rule the string labels above already obey). `__const` is
        // 8-byte aligned because every element is an 8-byte word and the access
        // path is `ldr x, [base, idx, lsl #3]`.
        var const_data: std.ArrayList(u8) = .empty;
        errdefer const_data.deinit(self.alloc);
        if (self.const_words.items.len > 0) {
            // Section INDEX, not a constant: __cstring only exists when this
            // module has a string literal, so __const is section 2 or 3.
            const section_index: u8 = if (self.strings.items.len > 0) 3 else 2;
            const base_addr = alignForward(self.code.items.len + cstring.items.len, 8);
            try self.asm_text.appendSlice(self.alloc, "\n.section __TEXT,__const\n.p2align 3\n");
            for (self.const_tables.items) |entry| {
                const sym = &self.symbols.items[entry.symbol_index];
                sym.offset = @intCast(base_addr + @as(usize, entry.word_off) * 8);
                sym.section = section_index;
                try self.asm_text.appendSlice(self.alloc, sym.name);
                try self.asm_text.appendSlice(self.alloc, ":\n");
                const words = self.const_words.items[entry.word_off..][0..entry.word_len];
                for (words) |w| try self.asm_text.print(self.alloc, "\t.quad {d}\n", .{w});
            }
            for (self.const_words.items) |w| {
                var buf: [8]u8 = undefined;
                std.mem.writeInt(i64, &buf, w, .little);
                try const_data.appendSlice(self.alloc, &buf);
            }
        }
        const const_bytes = try const_data.toOwnedSlice(self.alloc);
        errdefer self.alloc.free(const_bytes);

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
        const cost = try self.cost.entries.toOwnedSlice(self.alloc);
        self.cost.entries = .empty;
        return .{
            .text = text,
            .asm_text = asm_text,
            .cstring = cstring_bytes,
            .const_data = const_bytes,
            .symbols = symbols,
            .relocations = relocations,
            .lineage = lineage,
            .cost = cost,
        };
    }

    fn recordBootstrapExternCost(self: *Arm64Compiler, ins: dnir.Instr) !void {
        if (ins.op != .call_extern or ins.application != null) return;
        try self.cost.record(
            self.alloc,
            .extern_call,
            "bootstrap extern call without graph application lineage",
        );
    }

    fn internString(self: *Arm64Compiler, content: []const u8) Error!u32 {
        if (self.string_map.get(content)) |idx| return idx;
        try self.cost.record(
            self.alloc,
            .string_intern_hash,
            "literal string dedup table miss before rodata emission",
        );
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

    /// The `__TEXT,__const` symbol for these words, creating it if this is the
    /// first table with these contents.
    ///
    /// Deduped by contents for the same reason string literals are: two bindings
    /// of the same determined table are the same data, and the address is all
    /// either one can observe. Nothing writes the section, so sharing it cannot
    /// be witnessed.
    fn internConstTable(self: *Arm64Compiler, values: []const i64) Error!u32 {
        for (self.const_tables.items) |entry| {
            const have = self.const_words.items[entry.word_off..][0..entry.word_len];
            if (std.mem.eql(i64, have, values)) return entry.symbol_index;
        }
        const idx: u32 = @intCast(self.symbols.items.len);
        const owned_name = try std.fmt.allocPrint(self.alloc, "Lduo_const_{d}", .{self.next_const});
        errdefer self.alloc.free(owned_name);
        self.next_const += 1;
        // `.section` is stamped in `finish`, which is the only place that knows
        // whether a __cstring section exists to sit between this and __text.
        try self.symbols.append(self.alloc, .{
            .name = owned_name,
            .offset = 0,
            .defined = true,
            .section = 2,
            .external = false,
        });
        const word_off: u32 = @intCast(self.const_words.items.len);
        try self.const_words.appendSlice(self.alloc, values);
        try self.const_tables.append(self.alloc, .{
            .symbol_index = idx,
            .word_off = word_off,
            .word_len = @intCast(values.len),
        });
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
        const entry = self.entry orelse return false;
        const cur = self.cur_func_name orelse return false;
        if (!std.mem.eql(u8, entry, cur)) return false;
        return self.cur_func_float or self.cur_func_ret_float;
    }

    fn compileDnirModule(self: *Arm64Compiler, m: dnir.Module) Error!void {
        try self.emitAsmHeader();
        if (m.functions.len == 0) return error.MissingMain;
        for (m.functions) |f| {
            // `dnirNeedsCalleeSave` decides whether to MEASURE, and it is a census
            // of DNIR names -- the same census `probeCalleeSaveUse`'s own comment
            // says "is not a bound on it in either direction". The emitter's
            // `ret_record` parallel move stages n field values into fresh scratch
            // registers before committing them to x0..x7, a demand for ~2n
            // registers that no census of names counts; at six fields the staging
            // reaches x19 and the check below refuses a correct program. Measure
            // every function: the probe already answers `callee_save_all` when it
            // cannot compile, and a leaf that touches nothing still plans 0.
            self.callee_save_plan = self.probeCalleeSaveUse(f);
            try self.compileDnirFunction(f);
            // The plan was measured, not guessed, so a body that reached outside
            // it means the measurement and the emission disagreed — and the
            // artifact just written would hand the CALLER back a register it
            // clobbered. That is invisible to any test of this function. Refuse
            // instead: a refusal falls back to the C emit path and still runs.
            if (self.callee_touched & ~self.callee_save_plan != 0) return self.refuse(@src());
        }
        for (m.externs) |ext| {
            try self.ensureExternalSymbol(ext.symbol);
        }
    }

    /// Which callee-saved registers this function's body actually writes.
    ///
    /// The answer is MEASURED, by compiling the function once into a throwaway
    /// compiler and reading back what its allocator claimed. Nothing else can
    /// answer it: the highest register reached is decided by the allocator's own
    /// spill-and-reuse behaviour over the whole body, and `dnirGpPressure` — a
    /// census of names MENTIONED anywhere, with no notion of liveness — is not a
    /// bound on it in either direction. That census is what made one extra local
    /// (5 -> 6, liveness never above 2) turn 16 instructions into 41, all of the
    /// difference being twenty saves and restores of registers the function did
    /// not go on to use.
    ///
    /// The probe runs with `callee_save_plan = callee_save_all`, i.e. EXACTLY
    /// today's prologue, so the two passes differ only in which `str`/`ldr` pairs
    /// the prologue emits. Register allocation reads no code offset and no frame
    /// size, so the second pass claims the same registers as the first — and the
    /// caller verifies that rather than trusting it.
    ///
    /// The probe gets its own `Diagnostic`: a refusal encountered while probing
    /// is not this compilation's refusal, and must not be left behind for the
    /// real pass's error to be read from. If the probe cannot compile the
    /// function at all, this answers `callee_save_all` — the old behaviour — and
    /// the real pass reports the real failure.
    fn probeCalleeSaveUse(self: *Arm64Compiler, f: dnir.Function) u32 {
        var scratch: Diagnostic = .{};
        var probe = Arm64Compiler{
            .alloc = self.alloc,
            .diagnostic = &scratch,
            .f64_records = self.f64_records,
            .scal_records = self.scal_records,
            .entry = self.entry,
        };
        probe.gate_transport = self.gate_transport;
        probe.gp_local_home_budget = self.gp_local_home_budget;
        probe.spill_frame_budget = self.spill_frame_budget;
        // THE PROBE MUST COMPILE THE SAME BODY THE REAL PASS WILL. Its whole
        // premise (see above) is that the two passes differ only in the prologue's
        // save/restore pairs. A licence in one and not the other would give the
        // probe a table built word by word — one value register per element —
        // against a real pass that emits none of it, so the measurement would be
        // of a different function.
        probe.const_licence = self.const_licence;
        probe.callee_save_plan = callee_save_all;
        defer probe.deinit();
        probe.compileDnirFunction(f) catch return callee_save_all;
        return probe.callee_touched;
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

    /// x9–x18 are caller-save GP homes. Pressure past that lands in x19–x28,
    /// which AAPCS64 requires saving even in a leaf.
    const gp_caller_save_homes: u32 = 10;

    fn dnirNeedsCalleeSave(f: dnir.Function) bool {
        if (dnirFunctionHasCall(f)) return true;
        return dnirGpPressure(f) > gp_caller_save_homes;
    }

    fn dnirGpPressure(f: dnir.Function) u32 {
        var locals = std.mem.zeroes([256]u8);
        var temps = std.mem.zeroes([256]u8);
        var n: u32 = 0;
        const mark = struct {
            fn slot(map: *[256]u8, count: *u32, id: u32) void {
                if (id >= 256) {
                    count.* += 1;
                    return;
                }
                if (map.*[id] != 0) return;
                map.*[id] = 1;
                count.* += 1;
            }
            fn value(loc: *[256]u8, tmp: *[256]u8, count: *u32, v: dnir.Value) void {
                switch (v) {
                    .local => |id| slot(loc, count, id),
                    .temp => |id| slot(tmp, count, id),
                    else => {},
                }
            }
        };
        for (f.params, 0..) |p, i| {
            if (p.ty == .f64) continue;
            mark.slot(&locals, &n, @intCast(i));
        }
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                // A defined value only demands a GP home when it is read. A dead
                // immediate binding (defined, never consumed) needs no register
                // or stack slot, so it must not inflate pressure into a spurious
                // callee-save frame (`law.profile.evidence` — spill only the live).
                if (dnir.definition(ins)) |id| {
                    const want_local = ins.op == .store_local;
                    if (dnirDefinitionUsed(f, want_local, id)) {
                        if (want_local) {
                            mark.slot(&locals, &n, id);
                        } else {
                            mark.slot(&temps, &n, id);
                        }
                    }
                }
                mark.value(&locals, &temps, &n, ins.lhs);
                mark.value(&locals, &temps, &n, ins.rhs);
                mark.value(&locals, &temps, &n, ins.third);
                for (ins.vals) |v| mark.value(&locals, &temps, &n, v);
            }
        }
        return n;
    }

    fn dnirValueMatches(v: dnir.Value, want_local: bool, id: u32) bool {
        return switch (v) {
            .local => |slot| want_local and slot == id,
            .temp => |slot| !want_local and slot == id,
            else => false,
        };
    }

    fn dnirInstrReadsValue(ins: dnir.Instr, want_local: bool, id: u32) bool {
        const fixed = [_]dnir.Value{ ins.lhs, ins.rhs, ins.third };
        for (fixed) |v| if (dnirValueMatches(v, want_local, id)) return true;
        for (ins.vals) |v| if (dnirValueMatches(v, want_local, id)) return true;
        return false;
    }

    fn dnirDefinitionUsed(f: dnir.Function, want_local: bool, id: u32) bool {
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (dnirInstrReadsValue(ins, want_local, id)) return true;
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

        // Staged GP marshaling (`mov_arg` slot 0 → `call_direct` void lhs) must
        // keep the operand live through the call — same regalloc contract as an
        // inline lhs on `call_direct`. Otherwise compact and staged DNIR diverge
        // in emitted bytes even when the physical ABI work is identical.
        idx = 0;
        for (f.blocks) |block| {
            const instrs = block.instrs;
            for (instrs, 0..) |ins, i| {
                if (i + 1 < instrs.len) {
                    const next = instrs[i + 1];
                    if (ins.op == .mov_arg and ins.result == 0 and next.op == .call_direct and
                        next.lhs == .void and next.application != null)
                    {
                        const operand_id: ?u32 = switch (ins.lhs) {
                            .local, .temp => |id| id,
                            else => null,
                        };
                        if (operand_id) |id| {
                            if (self.value_free_at.get(id)) |last| {
                                if (last == idx) {
                                    try self.value_free_at.put(self.alloc, id, idx + 1);
                                }
                            }
                        }
                    }
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

    /// Instructions a `mov`/`movk` chain needs to materialize `value` — the
    /// count of nonzero 16-bit lanes (minimum one). Used to spend a bounded
    /// hoist-register budget on the constants whose re-materialization costs the
    /// most per loop iteration.
    fn immCost(value: i64) u8 {
        const u: u64 = @bitCast(value);
        var parts: u8 = 0;
        var shift: u6 = 0;
        while (true) {
            if (((u >> shift) & 0xffff) != 0) parts += 1;
            if (shift == 48) break;
            shift += 16;
        }
        return if (parts == 0) 1 else parts;
    }

    /// Plan loop-invariant immediate hoisting: for every natural loop (a `br`
    /// whose target is at or before it), collect the distinct `.i64` constants
    /// its body re-materializes and keep the most expensive up to the budget.
    /// Constants are loop-invariant by definition, so no dependence analysis is
    /// required — the only question is register budget.
    fn planImmHoist(self: *Arm64Compiler, f: dnir.Function) Error!void {
        self.hoist_plan.clearRetainingCapacity();
        if (self.gate_transport) return;

        var heads: std.AutoHashMapUnmanaged(u32, u32) = .empty; // head -> furthest latch
        defer heads.deinit(self.alloc);
        var idx: u32 = 0;
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.op == .br and ins.branch_target <= idx) {
                    const head = ins.branch_target;
                    const prev = heads.get(head) orelse 0;
                    if (idx > prev) try heads.put(self.alloc, head, idx);
                }
                idx += 1;
            }
        }
        if (heads.count() == 0) return;

        var hit = heads.iterator();
        while (hit.next()) |e| {
            const head = e.key_ptr.*;
            const latch = e.value_ptr.*;
            var plan: HoistPlan = .{ .latch = latch };
            idx = 0;
            scan: for (f.blocks) |b| {
                for (b.instrs) |ins| {
                    if (idx >= head and idx <= latch) {
                        for ([_]dnir.Value{ ins.lhs, ins.rhs }) |v| {
                            switch (v) {
                                .i64 => |n| self.considerHoist(&plan, n),
                                else => {},
                            }
                        }
                    }
                    idx += 1;
                    if (idx > latch) break :scan;
                }
            }
            if (plan.count > 0) try self.hoist_plan.put(self.alloc, head, plan);
        }
    }

    /// Add constant `n` to a loop's hoist plan, deduping and — once the budget
    /// is full — evicting the cheapest resident constant when `n` costs more.
    fn considerHoist(self: *Arm64Compiler, plan: *HoistPlan, n: i64) void {
        _ = self;
        var k: u8 = 0;
        while (k < plan.count) : (k += 1) if (plan.values[k] == n) return;
        if (plan.count < max_hoist_per_loop) {
            plan.values[plan.count] = n;
            plan.count += 1;
            return;
        }
        var mink: u8 = 0;
        var mincost = immCost(plan.values[0]);
        var j: u8 = 1;
        while (j < plan.count) : (j += 1) {
            const c = immCost(plan.values[j]);
            if (c < mincost) {
                mincost = c;
                mink = j;
            }
        }
        if (immCost(n) > mincost) plan.values[mink] = n;
    }

    /// At a loop head (in emission order, once per compile), pre-materialize the
    /// planned constants into reserved home registers. Emitting BEFORE the head's
    /// `code_offsets` entry means the back edge re-enters AFTER these movs, so the
    /// constants are computed once on fall-in and reused every iteration.
    ///
    /// FALL-IN IS NOT THE ONLY WAY IN, and assuming it was is what made this a
    /// wrong answer rather than a missed optimization. A head is also entered by
    /// any FORWARD branch that targets it, and an `if` immediately before a loop
    /// produces two of them. Record where the preheader starts so the patch pass
    /// can send those entries through it; a head that hoisted nothing records
    /// nothing and every branch to it keeps the head offset.
    fn immHoistEnter(self: *Arm64Compiler, flat_idx: u32) Error!void {
        const plan = self.hoist_plan.get(flat_idx) orelse return;
        if (self.hoist_depth >= max_hoist_depth) return;
        const preheader_off: u32 = @intCast(self.code.items.len);
        var active: HoistActive = .{ .latch = plan.latch };
        var k: u8 = 0;
        while (k < plan.count) : (k += 1) {
            const v = plan.values[k];
            if (self.imm_hoist.contains(v)) continue; // enclosing loop already holds it
            const r = try self.allocReg();
            if (r < 9 or r >= 29 or r == platform_reserved_reg) {
                self.releaseReg(r);
                continue;
            }
            self.markGpHome(r);
            try self.emitMovImm(r, v);
            try self.imm_hoist.put(self.alloc, v, r);
            active.values[active.count] = v;
            active.regs[active.count] = r;
            active.count += 1;
        }
        if (self.code.items.len != preheader_off) {
            try self.hoist_preheader.put(self.alloc, flat_idx, preheader_off);
        }
        self.hoist_active[self.hoist_depth] = active;
        self.hoist_depth += 1;
    }

    /// Once emission has passed a loop's latch, release its reserved registers
    /// so the loop-exit code and any sibling loop can reuse them.
    fn immHoistExit(self: *Arm64Compiler, flat_idx: u32) void {
        while (self.hoist_depth > 0) {
            const top = self.hoist_active[self.hoist_depth - 1];
            if (flat_idx <= top.latch) break;
            var k: u8 = 0;
            while (k < top.count) : (k += 1) {
                const v = top.values[k];
                const r = top.regs[k];
                if (self.imm_hoist.get(v)) |cur| {
                    if (cur == r) _ = self.imm_hoist.remove(v);
                }
                self.gp_home_regs[r] = false;
                self.gp_reg_owner[r] = null;
                self.used_regs[r] = false;
            }
            self.hoist_depth -= 1;
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

    /// This register is a local's home for the rest of the function.
    fn markGpHome(self: *Arm64Compiler, reg: u5) void {
        if (reg < 9 or reg >= 29) return;
        if (reg == platform_reserved_reg) return;
        self.gp_home_regs[reg] = true;
        self.claimReg(reg);
        self.gp_reg_owner[reg] = null;
    }

    fn countGpHomes(self: *const Arm64Compiler) u32 {
        var n: u32 = 0;
        var reg: u5 = 9;
        while (reg < 29) : (reg += 1) {
            if (reg == platform_reserved_reg) continue;
            if (self.gp_home_regs[reg]) n += 1;
        }
        return n;
    }

    fn gpLocalNeedsStack(self: *const Arm64Compiler) bool {
        return self.countGpHomes() >= self.gp_local_home_budget;
    }

    /// Pre-pass: decide which GP locals spill to the stack when register homes
    /// are exhausted. Reserving at first store on one branch and restoring the
    /// whole frame on every `ret` imbalanced paths — `endpos = j` on the true
    /// branch reserved 8 bytes while the false branch still ran `add sp, #8`.
    fn planGpStackLocals(self: *Arm64Compiler, f: dnir.Function, body_has_call: bool) Error!void {
        self.gp_stack_locals.clearRetainingCapacity();
        var home_count: u32 = 0;
        var homed_slots: std.AutoHashMapUnmanaged(u32, void) = .empty;
        defer homed_slots.deinit(self.alloc);
        var param_slots: u32 = 0;
        for (f.params) |p| {
            var slots_for_param: u32 = 1;
            if (p.record) |rec_name| {
                if (scalRecordDesc(self.scal_records, rec_name)) |rec| {
                    slots_for_param = @intCast(rec.field_names.len);
                }
            }
            param_slots += slots_for_param;
        }
        // Any call clobbers x0–x17. Locals left in caller-saved homes made
        // `bare`'s `n` a heap pointer, so `sub` malloc'd gigabytes.
        const gate_spill_all_locals = body_has_call;
        self.gate_param_slots = if (gate_spill_all_locals) @max(param_slots, 1) else 0;

        const planSlot = struct {
            fn go(
                ctx: *Arm64Compiler,
                slot: u32,
                homes_used: *u32,
                homed: *std.AutoHashMapUnmanaged(u32, void),
                gate_spill: bool,
            ) Error!void {
                if (homed.contains(slot)) return;
                // Gate scripts call gatecap/sh repeatedly; every local must
                // reload from the prologue stack frame after each call.
                if (gate_spill) {
                    // Offset is the slot id, not insertion order. A bump from
                    // `count()*8` gave `i` and the `and` temp the same home.
                    if (slot > 4094) return error.RegisterExhausted;
                    const off: u16 = @intCast(slot * 8);
                    try ctx.gp_stack_locals.put(ctx.alloc, slot, off);
                    try ctx.cost.record(
                        ctx.alloc,
                        .stack_local,
                        "gate transport local spilled to stack frame",
                    );
                } else if (homes_used.* >= ctx.gp_local_home_budget) {
                    if (slot > 4094) return error.RegisterExhausted;
                    const off: u16 = @intCast(slot * 8);
                    try ctx.gp_stack_locals.put(ctx.alloc, slot, off);
                    try ctx.cost.record(
                        ctx.alloc,
                        .stack_local,
                        "GP home budget exhausted; local spilled to stack frame",
                    );
                } else {
                    try homed.put(ctx.alloc, slot, {});
                    homes_used.* += 1;
                }
            }
        }.go;

        var slot_cursor: u32 = 0;
        for (f.params) |p| {
            var slots_for_param: u32 = 1;
            if (p.record) |rec_name| {
                if (scalRecordDesc(self.scal_records, rec_name)) |rec| {
                    slots_for_param = @intCast(rec.field_names.len);
                }
            }
            var k: u32 = 0;
            while (k < slots_for_param) : (k += 1) {
                if (body_has_call) {
                    try planSlot(self, slot_cursor, &home_count, &homed_slots, gate_spill_all_locals);
                } else {
                    try homed_slots.put(self.alloc, slot_cursor, {});
                }
                slot_cursor += 1;
            }
        }

        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.op != .store_local) continue;
                const slot = ins.result orelse continue;
                if (ins.ty == .f64 or self.valueIsFp(ins.lhs)) continue;
                if (ins.application == null and !self.value_free_at.contains(slot)) switch (ins.lhs) {
                    .i64 => continue,
                    else => {},
                };
                try planSlot(self, slot, &home_count, &homed_slots, gate_spill_all_locals);
            }
        }
    }

    fn reserveGpStackLocal(self: *Arm64Compiler, slot: u32) Error!u16 {
        return self.gp_stack_locals.get(slot) orelse error.RegisterExhausted;
    }

    fn loadGpStackLocal(self: *Arm64Compiler, off: u16) Error!u5 {
        const reg = try self.allocReg();
        // GP spill slots live in the prologue's bottom `sub sp` region; offsets
        // are assigned from sp upward (0, 8, 16, …), not from the frame top.
        try self.emitLdrSp(reg, off);
        return reg;
    }

    fn storeGpStackLocal(self: *Arm64Compiler, off: u16, src: u5) Error!void {
        try self.emitStrSp(src, off);
    }

    /// Free every GP temp register whose owner has no read left after `idx`.
    fn sweepGpLive(self: *Arm64Compiler, idx: u32) void {
        var reg: u5 = 0;
        while (reg < 29) : (reg += 1) {
            if (reg == platform_reserved_reg) continue;
            const owner = self.gp_reg_owner[reg] orelse continue;
            if (reg >= 9 and self.gp_home_regs[reg]) continue;
            const last = self.value_free_at.get(owner) orelse 0;
            if (last > idx) continue;
            self.gp_reg_owner[reg] = null;
            self.used_regs[reg] = false;
            if (self.spilled_regs.fetchRemove(reg)) |entry| {
                self.free_spill_slots.append(self.alloc, entry.value) catch {};
            }
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
        self.gp_reg_owner = @splat(null);
        self.gp_home_regs = @splat(false);
        try self.computeValueLastUse(f);
        self.imm_hoist.clearRetainingCapacity();
        self.hoist_preheader.clearRetainingCapacity();
        self.hoist_depth = 0;
        try self.planImmHoist(f);
        self.returned = false;
        self.fp_stack_slots.clearRetainingCapacity();
        self.stack_frame_bytes = 0;
        self.callee_save_bytes = 0;
        // `callee_save_plan` is set by the CALLER from the probe and must
        // survive this reset; what it measures must not.
        self.callee_touched = 0;
        self.spilled_regs.clearRetainingCapacity();
        self.free_spill_slots.clearRetainingCapacity();
        self.gp_stack_locals.clearRetainingCapacity();
        self.gate_spill_base = 0;
        self.gate_spill_end = 0;
        self.gate_spill_cursor = 0;
        self.gate_param_slots = 0;
        self.eval_pinned = null;
        self.cur_func_has_call = false;
        self.extern_preserve_x0 = false;
        self.extern_preserve_x0_temp = null;
        self.cur_func_ret_record = if (f.ret_record) |rn| scalRecordDesc(self.scal_records, rn) else null;
        self.cur_func_ret_f64_record = if (f.ret_record) |rn| f64RecordDesc(self.f64_records, rn) else null;
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
        const scalar_body_has_call = if (!f.is_float_kernel) dnirFunctionHasCall(f) else false;
        self.cur_func_has_call = scalar_body_has_call or dnirFunctionHasCall(f);
        self.eval_pinned = &pinned;
        // `dnirNeedsCalleeSave` no longer decides here: it gates the PROBE (see
        // `compileDnirModule`), and the probe's answer is the plan. An empty plan
        // emits nothing at all.
        try self.emitSaveCalleeRegs();

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
                    const rec = f64RecordDesc(self.f64_records, rec_name) orelse return self.refuse(@src());
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
            try self.planGpStackLocals(f, scalar_body_has_call);
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
                if (f64RecordDesc(self.f64_records, ins.record) != null) has_f64_record = true;
            }
        }
        // Does anything in this body address a record region under the FALLBACK
        // base "rec"? `load_field` uses `req_alias` and falls back to "rec" when
        // it is empty; `indirectResultBuffer` does the same with `.field`. Those
        // are the only readers. A record LITERAL binding (dnir_lower.zig:4317,
        // :4415) emits `init_record` with `.field` empty and keeps its fields in
        // ordinary locals under `x.a`, so it reserves a region nothing can name.
        // That region is not free: it costs `sub sp`/`add sp`, every table and
        // GP-local offset is rebased around it, and a non-empty `fp_stack_slots`
        // makes the mid-body spill path refuse outright.
        var bare_rec_demand = false;
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                switch (ins.op) {
                    .load_field => if (ins.req_alias.len == 0) {
                        bare_rec_demand = true;
                    },
                    .call_direct, .call_extern => if (ins.record.len > 0 and ins.field.len == 0) {
                        bare_rec_demand = true;
                    },
                    else => {},
                }
            }
        }
        if (!has_f64_record) {
            var record_frame: u16 = 0;
            for (f.blocks) |b| {
                for (b.instrs) |ins| {
                    if (ins.record.len == 0) continue;
                    switch (ins.op) {
                        .init_record => if (ins.field.len == 0 and !bare_rec_demand) continue,
                        .call_direct, .call_extern => {},
                        else => continue,
                    }
                    const rec = scalRecordDesc(self.scal_records, ins.record) orelse continue;
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

        // WHICH TABLES NEED NO STORAGE AT ALL, and therefore no frame region and
        // no instructions to fill one. `const_table.zig` states the whole rule;
        // the precondition itself comes from `table_facts.zig` and is not
        // restated. This runs BEFORE the slot-base pass below because its answer
        // is what that pass has to skip.
        self.const_bases.clearRetainingCapacity();
        if (self.const_licence) |lic| {
            var promotions = try const_table.recognize(self.alloc, f, lic);
            defer promotions.deinit();
            for (promotions.items) |p| {
                const sym = try self.internConstTable(p.values);
                try self.const_bases.put(self.alloc, p.base, sym);
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
                    // A promoted table lives in `__TEXT,__const`. Reserving a
                    // frame region for it as well would not merely waste stack —
                    // the region shifts every sp-relative offset handed out
                    // afterwards, which is the exact mechanism behind the
                    // overlap that made a scalar read 50 instead of 33.
                    if (self.const_bases.contains(t)) continue;
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
                // EVERY sp-RELATIVE OFFSET ALREADY HANDED OUT IS NOW WRONG BY
                // THIS MUCH. That is the invariant this prologue kept breaking:
                // each region is measured from the `sp` that existed when the
                // region was reserved, and every later `sub sp` silently
                // renumbers all of them. Three regions are reserved in sequence
                // (records, tables, GP locals + spill), so each `sub sp` must
                // rebase everything handed out before it — here and below.
                //
                // Left unrebased, the regions do not merely shift, they OVERLAP:
                // GP stack locals are addressed from the FINAL `sp` starting at
                // [sp,#0], which is exactly where an unrebased table region also
                // claims to start. Measured on a 33-element table in a relation
                // that also makes a call (the call is what forces locals to
                // memory at all): `t(3) + ident(3)` answered 50 instead of 33,
                // the scalar reading element 2 of the table. No refusal, no
                // diagnostic, a program that compiles and runs and is wrong.
                //
                // WHY IT SURVIVED THE GATES: tables are covered, calls are
                // covered, and nothing covered BOTH IN ONE RELATION. Below 33
                // elements the table is a select chain — registers, not frame —
                // so the corpus's tables never met the spill area.
                try self.emitSubSp(slots_frame);
                self.stack_frame_bytes += slots_frame;
                // Every region reserved EARLIER is now that much further from
                // `sp`. The record region is the only one, and it is rebased
                // here for the same reason the table region is rebased below.
                var rec_it = self.fp_stack_slots.valueIterator();
                while (rec_it.next()) |slot| {
                    const rebased: u32 = @as(u32, slot.off) + slots_frame;
                    if (rebased > 32752) return self.refuse(@src());
                    slot.off = @intCast(rebased);
                }
            }
        }

        if (!f.is_float_kernel) {
            var gp_need: usize = 0;
            var git = self.gp_stack_locals.valueIterator();
            while (git.next()) |off| {
                const end = @as(usize, off.*) + 8;
                if (end > gp_need) gp_need = end;
            }
            const gp_stack_bytes: u16 = @intCast(std.mem.alignForward(usize, gp_need, 16));
            // Locals sit at [sp,#0]…; spill temps sit above them. One `sub sp`
            // for both — a second sub moved sp and left local offsets pointing
            // into the spill pit, so `bare`'s `i` and the `c != " "` bool shared
            // a slot and the walk never advanced.
            // SPILL SPACE IS NOT A PROPERTY OF CALLING, and reserving it only
            // for callers was an accident that held because something else was
            // wrong. A dynamic table index emits a bounds trap; the trap used to
            // be `call_extern abort`; so every function that indexed a table
            // dynamically counted as a caller and got a spill area it needed for
            // an entirely unrelated reason — register pressure. Making the trap a
            // real trap took the area away with it, and a 20-element select-chain
            // loop with no call in it went from answering 33 to DNB003.
            //
            // The two facts are now asked separately. A CALL forces locals out of
            // caller-saved homes (`gate_spill_all_locals`, above). PRESSURE is
            // what needs somewhere to spill to, and it is `dnirNeedsCalleeSave`
            // — the same question the prologue asks about x19–x28 — that says a
            // function has more live values than caller-saved homes.
            //
            // Over-reserving costs one `sub sp`/`add sp` pair and some untouched
            // stack; under-reserving costs a working program. The budget check
            // still HARD-FAILS for a caller, because a caller that cannot spill
            // really is out of capacity; for a leaf it simply reserves what is
            // left, which may be nothing.
            const wants_spill = scalar_body_has_call or dnirNeedsCalleeSave(f);
            var spill_reserve: u16 = 0;
            if (wants_spill) {
                const used: u32 = @as(u32, self.stack_frame_bytes) + gp_stack_bytes;
                if (used >= self.spill_frame_budget) {
                    if (scalar_body_has_call) return error.RegisterExhausted;
                } else {
                    const remain: u32 = self.spill_frame_budget - used;
                    spill_reserve = @min(@as(u16, @intCast(@min(remain, 8192))), @as(u16, 8192));
                    if (spill_reserve < 64) spill_reserve = 0;
                }
            }
            const frame: u16 = gp_stack_bytes + spill_reserve;
            if (frame > 0) {
                if (@as(u32, self.stack_frame_bytes) + frame > self.spill_frame_budget) {
                    return error.RegisterExhausted;
                }
                try self.emitSubSp(frame);
                self.stack_frame_bytes += frame;
                // REBASE the memory-backed table regions.
                //
                // `slot_bases` was measured against the `sp` that existed before
                // this reservation, and GP stack locals are addressed from the
                // NEW `sp` starting at [sp,#0]. Without this shift the two name
                // the same bytes: a 40-element table sat at [sp,#0..320) while
                // the loop counter's home sat at [sp,#0xb0] — inside it, element
                // 23 — so every iteration's `i` store overwrote a table element.
                //
                // That is a WRONG ANSWER, not a crash, and it hid for a long
                // time behind test data: the corpus tables are `{1,2,3,…}`, and
                // storing `i` over element `i` writes the value that was already
                // there. It only becomes visible when the elements stop equalling
                // their own index (`t[k] = k + 100`) or when something reads the
                // region at a different point in the loop.
                //
                // Records (`fp_stack_slots`) are reserved BEFORE the table
                // region, so they are stale by `slots_frame + frame` and are
                // rebased by the same rule immediately below.
                var slot_it = self.slot_bases.valueIterator();
                while (slot_it.next()) |off| {
                    const rebased: u32 = @as(u32, off.*) + frame;
                    if (rebased > 32752) return self.refuse(@src());
                    off.* = @intCast(rebased);
                }
                var rec_it = self.fp_stack_slots.valueIterator();
                while (rec_it.next()) |slot| {
                    const rebased: u32 = @as(u32, slot.off) + frame;
                    if (rebased > 32752) return self.refuse(@src());
                    slot.off = @intCast(rebased);
                }
            }
            if (spill_reserve >= 64) {
                self.gate_spill_base = gp_stack_bytes;
                self.gate_spill_end = gp_stack_bytes + spill_reserve;
                self.gate_spill_cursor = self.gate_spill_base;
            }
            // Parameter homes are set up after the prologue so stack-relative
            // displacements match `storeGpStackLocal` / `loadGpStackLocal`.
            var slot_cursor: u32 = 0;
            for (f.params) |p| {
                var slots_for_param: u32 = 1;
                if (p.record) |rec_name| {
                    if (scalRecordDesc(self.scal_records, rec_name)) |rec| {
                        slots_for_param = @intCast(rec.field_names.len);
                    }
                }
                var k: u32 = 0;
                while (k < slots_for_param) : (k += 1) {
                    const slot = slot_cursor;
                    if (slot >= 8) {
                        // AAPCS64 stack argument: the ninth and later GP params
                        // arrive in the caller's outgoing area, which now sits
                        // just above this frame (callee-saves + locals + spill).
                        // A record parameter is never stacked (the lowering keeps
                        // records inside x0..x7), so each stacked slot is one
                        // scalar word at [sp, #(callee_save+frame)+(slot-8)*8].
                        const frame_total: u32 = @as(u32, self.callee_save_bytes) + @as(u32, self.stack_frame_bytes);
                        const off: u32 = frame_total + (slot - 8) * 8;
                        if (off > 32760) return self.refuse(@src());
                        const home = try self.allocReg();
                        try self.emitLdrSp(home, @intCast(off));
                        if (self.gpSlotUsesStack(slot)) {
                            const soff = try self.reserveGpStackLocal(slot);
                            try self.storeGpStackLocal(soff, home);
                            if (!Arm64Compiler.regIsPinned(&pinned, home)) self.releaseReg(home);
                        } else {
                            self.markGpHome(home);
                            try temps.put(self.alloc, slot, home);
                            try pinned.put(self.alloc, slot, home);
                        }
                        slot_cursor += 1;
                        continue;
                    }
                    const arg_reg: u5 = @intCast(slot);
                    if (scalar_body_has_call) {
                        const home = try self.allocReg();
                        try self.emitMovReg(home, arg_reg);
                        if (self.gpSlotUsesStack(slot)) {
                            const off = try self.reserveGpStackLocal(slot);
                            try self.storeGpStackLocal(off, home);
                            if (!Arm64Compiler.regIsPinned(&pinned, home)) self.releaseReg(home);
                        } else {
                            self.markGpHome(home);
                            try temps.put(self.alloc, slot, home);
                            try pinned.put(self.alloc, slot, home);
                        }
                    } else {
                        // A LEAF KEEPS ITS PARAMETER IN THE INCOMING REGISTER,
                        // AND THAT REGISTER IS THEN LIVE FOR THE WHOLE BODY.
                        // `pinned` stops the release paths from freeing it, but
                        // `allocRegExcluding` does not read `pinned` -- when
                        // x9..x28 are all busy it falls through to x0..x7 and asks
                        // only `used_regs`. Nothing ever set `used_regs[x0]` here,
                        // so the allocator handed out the live trip count: an
                        // 8-field record literal in a `while` loop exhausted
                        // x9..x28 on its fields, `s + x.a + x.h` was computed INTO
                        // x0, and the back edge's `cmp i, x0` compared the
                        // induction variable against the running sum. The loop ran
                        // to signed overflow (~3e9 iterations, 3.8 s) and returned
                        // a value INDEPENDENT OF ITS ARGUMENT. Claim it, and
                        // exhaustion refuses instead.
                        self.claimReg(arg_reg);
                        try temps.put(self.alloc, slot, arg_reg);
                        try pinned.put(self.alloc, slot, arg_reg);
                    }
                    slot_cursor += 1;
                }
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
            var bi: usize = 0;
            while (bi < b.instrs.len) : (bi += 1) {
                const ins = b.instrs[bi];
                // Pre-materialize loop-invariant constants into reserved
                // registers in the preheader — before this head's code offset,
                // so the back edge re-enters after the movs (FTCFTW debt (1)).
                try self.immHoistEnter(flat_idx);
                const text_start: u32 = @intCast(self.code.items.len);
                try code_offsets.append(self.alloc, text_start);
                // Peephole: fold `binop(cmp) -> T ; br when_x T` into `cmp; b.cond`
                // when T's only reader is that branch. The branch instruction is
                // then consumed below with no bytes of its own.
                const fuse_branch = ins.op == .binop and bi + 1 < b.instrs.len and
                    self.compareBranchFusible(ins, b.instrs[bi + 1], flat_idx);
                // R15: the SAME compare, given a name. `c = a > b ; if c` puts a
                // `store_local` between the two, which the adjacency test above
                // cannot see past; `namedCompareBranchFusible` counts the name's
                // readers instead and folds to the identical `cmp; b.cond`.
                const fuse_named = !fuse_branch and ins.op == .binop and bi + 2 < b.instrs.len and
                    self.namedCompareBranchFusible(f, ins, b.instrs[bi + 1], b.instrs[bi + 2], flat_idx);
                // Peephole: fold `mul -> T ; add(T, c) -> D` into `madd D,a,b,c`
                // when T's only reader is that add (FTCFTW debt (2)).
                const fuse_madd = !fuse_branch and !fuse_named and ins.op == .binop and bi + 1 < b.instrs.len and
                    self.mulAddFusible(ins, b.instrs[bi + 1], flat_idx);
                // W7: the whole one-sided `if` becomes `csel`, on top of
                // whichever of the three condition shapes reached here.
                const ifconv: ?IfConvPlan = if (fuse_branch)
                    self.ifConversionArm(f, b.instrs[bi + 1 ..], flat_idx + 1, ins, 1)
                else if (fuse_named)
                    self.ifConversionArm(f, b.instrs[bi + 2 ..], flat_idx + 2, ins, 2)
                else if (ins.op == .br and ins.branch_condition != .unconditional)
                    self.ifConversionArm(f, b.instrs[bi..], flat_idx, null, 0)
                else
                    null;
                // DNIR instructions this iteration consumes BEYOND `ins`. Each
                // one still gets a code offset below so branch targets resolve.
                var extra_consumed: u32 = 0;
                if (ifconv) |plan| {
                    try self.emitIfConverted(&temps, &pinned, plan, &branch_patches);
                    extra_consumed = plan.extra;
                } else if (fuse_branch) {
                    try self.emitFusedCompareBranch(&temps, &pinned, ins, b.instrs[bi + 1], &branch_patches);
                    extra_consumed = 1;
                } else if (fuse_named) {
                    try self.emitFusedCompareBranch(&temps, &pinned, ins, b.instrs[bi + 2], &branch_patches);
                    extra_consumed = 2;
                } else if (fuse_madd) {
                    try self.emitFusedMulAdd(&temps, &pinned, ins, b.instrs[bi + 1]);
                    extra_consumed = 1;
                } else {
                    try self.compileDnirInstr(&temps, &pinned, ins, &branch_patches);
                }
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
                        .target = ins.target orelse return self.refuseWith(@src(), "missing-application-target"),
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
                // `mov_arg`/`fp_mov_arg` alone carry a PHYSICAL ABI register slot
                // (0..7) in `result`, not a value id. The value-id space (locals +
                // temps) is one shared unique counter, so a low slot index like 0
                // aliases real value id 0: looking it up in `temps` returned the
                // register of a live call result that happened to hold value 0's
                // home, and the ownership rebind below then handed that live
                // register to a long-dead value — the very next `sweepGpLive` freed
                // it mid-use, collapsing multi-argument marshaling (both operands of
                // an inner call read the same clobbered register). Every other op
                // reports a genuine value id in `result` (or none), so gate only the
                // two ABI-slot ops; gating more would leak `cmp`/`load_global`
                // registers that never get swept, exhausting the pool.
                const owned_value: ?u32 = switch (ins.op) {
                    .mov_arg, .fp_mov_arg => null,
                    else => ins.result,
                };
                if (owned_value) |t| {
                    if (temps.get(t)) |r| {
                        if (self.fp_temps.contains(t)) {
                            if (r >= fp_value_reg_base and
                                r < fp_value_reg_base + fp_value_reg_count and
                                !self.fp_home_regs[r])
                            {
                                self.fp_reg_owner[r] = t;
                            }
                        } else if (r >= 9 and r < 29 and r != platform_reserved_reg and
                            !self.gp_home_regs[r])
                        {
                            self.gp_reg_owner[r] = t;
                        }
                    }
                }
                self.sweepFpLive(flat_idx);
                self.sweepGpLive(flat_idx);
                tail_terminates = switch (ins.op) {
                    .ret, .ret_record => true,
                    .br => ins.branch_condition == .unconditional,
                    else => false,
                };
                flat_idx += 1;
                var consumed: u32 = 0;
                while (consumed < extra_consumed) : (consumed += 1) {
                    // The following instructions (a conditional `br` folded into
                    // the compare, the `add` folded into the `madd`, or the whole
                    // arm of an if-converted `if`) emitted no bytes of their own.
                    // Consume them while preserving the one-code-offset-per-
                    // instruction alignment that DNIR branch targets resolve
                    // against. Each recognizer has already proved that nothing
                    // branches INTO the window it collapses.
                    bi += 1;
                    try code_offsets.append(self.alloc, @intCast(self.code.items.len));
                    self.sweepFpLive(flat_idx);
                    self.sweepGpLive(flat_idx);
                    tail_terminates = false;
                    flat_idx += 1;
                }
                // Release hoist registers once emission has passed a loop latch.
                self.immHoistExit(flat_idx);
            }
        }
        // Sentinel: branch_target may equal instr count (fall-through past if-block).
        try code_offsets.append(self.alloc, @intCast(self.code.items.len));
        for (branch_patches.items) |p| {
            if (p.target_instr >= code_offsets.items.len) return self.refuse(@src());
            var target_off = code_offsets.items[p.target_instr];
            // A loop head whose constants were pre-materialized has TWO entry
            // points, and which one a branch wants is decided by the direction of
            // the branch, not by the target. The back edge is already past the
            // preheader and must stay past it, or the movs run every iteration
            // and the hoist buys nothing. Everything else — the `b.cond` that
            // skips an `if` and the `b` that closes it are the two that mattered
            // — is entering the loop for the first time and MUST run them.
            //
            // Direction is read off the offsets rather than carried on the patch:
            // emission is strictly in order, so a branch emitted before the
            // preheader is exactly a branch from before the head. Keeping
            // `code_offsets` pointing at the head itself leaves instruction
            // lineage spans (`text_start`) measuring the instruction and not its
            // preheader.
            if (self.hoist_preheader.get(p.target_instr)) |pre_off| {
                if (p.patch_off < pre_off) target_off = pre_off;
            }
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
        self.eval_pinned = null;
        self.cur_func_has_call = false;
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
                    self.pending_varargs[idx] = .{ .operand = ins.lhs };
                    if (idx + 1 > self.pending_vararg_count) self.pending_vararg_count = idx + 1;
                    return;
                }
                const slot: u5 = @intCast(ins.result orelse return self.refuse(@src()));
                if (slot >= 8) {
                    // AAPCS64 stack argument: the ninth and later GP arguments
                    // travel on the stack at [sp,#(slot-8)*8]. Defer them through
                    // the same stack-flush the variadic tail uses — the call arms
                    // materialize and push the block between the caller-save area
                    // and `bl`, and the callee prologue loads them back. No packing.
                    const idx: u5 = slot - 8;
                    if (idx >= self.pending_varargs.len) return self.refuse(@src());
                    self.pending_varargs[idx] = .{ .operand = ins.lhs };
                    if (idx + 1 > self.pending_vararg_count) self.pending_vararg_count = idx + 1;
                    return;
                }
                switch (ins.lhs) {
                    .i64 => |n| {
                        try self.preserveArgReg(temps, pinned, slot);
                        try self.emitMovImm(slot, n);
                        self.markStagedArgReg(slot);
                        return;
                    },
                    .str => |s| {
                        try self.preserveArgReg(temps, pinned, slot);
                        const sym = try self.internString(s);
                        try self.emitAdrpAdd(slot, sym);
                        self.markStagedArgReg(slot);
                        return;
                    },
                    else => {},
                }
                const reg = try self.evalDnirValue(temps, ins.lhs);
                if (reg != slot) {
                    try self.preserveArgReg(temps, pinned, slot);
                    try self.emitMovReg(slot, reg);
                }
                if (slot == 0 and ins.lhs == .temp) {
                    self.extern_preserve_x0 = true;
                    self.extern_preserve_x0_temp = ins.lhs.temp;
                }
                // Match `call_direct` inline-lhs cleanup when the operand already
                // occupies the target ABI slot.
                self.releaseDnirTemp(pinned, ins.lhs, reg);
                // Now this argument occupies `slot`; keep the scratch allocator out
                // of it until the call is emitted (see `pending_arg_regs`).
                self.markStagedArgReg(slot);
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
                        if (self.gp_stack_locals.get(slot)) |off| {
                            try self.storeGpStackLocal(off, val_reg);
                            _ = pinned.remove(slot);
                            _ = temps.remove(slot);
                            if (!Arm64Compiler.regIsPinned(pinned, val_reg)) self.releaseReg(val_reg);
                        } else if (pinned.get(slot) orelse temps.get(slot)) |local_reg| {
                            if (local_reg != val_reg) try self.emitMovReg(local_reg, val_reg);
                            if (val_reg != local_reg and !Arm64Compiler.regIsPinned(pinned, val_reg)) {
                                self.releaseReg(val_reg);
                            }
                            self.markGpHome(local_reg);
                            try pinned.put(self.alloc, slot, local_reg);
                            try temps.put(self.alloc, slot, local_reg);
                        } else if (self.gpSlotUsesStack(slot)) {
                            const off = try self.reserveGpStackLocal(slot);
                            try self.storeGpStackLocal(off, val_reg);
                            if (!Arm64Compiler.regIsPinned(pinned, val_reg)) self.releaseReg(val_reg);
                        } else {
                            const local_reg = try self.allocReg();
                            if (local_reg != val_reg) try self.emitMovReg(local_reg, val_reg);
                            if (val_reg != local_reg and !Arm64Compiler.regIsPinned(pinned, val_reg)) {
                                self.releaseReg(val_reg);
                            }
                            self.markGpHome(local_reg);
                            try pinned.put(self.alloc, slot, local_reg);
                            try temps.put(self.alloc, slot, local_reg);
                        }
                    } else if (!Arm64Compiler.regIsPinned(pinned, val_reg)) {
                        self.releaseReg(val_reg);
                    }
                }
            },
            .binop => blk: {
                if (ins.ty == .f64) {
                    const comparison = comparisonCondition(ins.binop);
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
                    if (comparison == null) {
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
                    try self.emitCsetFp(dst, comparison.?);
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
                    const any_fp = self.valueIsFp(ins.lhs) or self.valueIsFp(ins.rhs);
                    if (comparisonCondition(ins.binop)) |condition| {
                        if (any_fp) {
                            const clhs = try self.evalDnirValueFp(temps, ins.lhs);
                            const crhs = try self.evalDnirValueFp(temps, ins.rhs);
                            const cdst = try self.allocReg();
                            try self.emitFcmpReg(clhs, crhs);
                            try self.emitCsetFp(cdst, condition);
                            self.releaseFpReg(clhs);
                            self.releaseFpReg(crhs);
                            if (ins.result) |t| try temps.put(self.alloc, t, cdst);
                            break :blk;
                        }
                    }
                    // An all-integer OPERATION inside a float kernel is an
                    // ordinary integer operation. Nothing about the enclosing
                    // function changes that.
                    //
                    // This used to classify comparisons and let every
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
                        try self.emitCompareOrBinop(idst, ilhs, irhs, ins.binop);
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
                    try self.emitCompareOrBinop(dst, lhs, rhs, ins.binop);
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
                    if (ins.op == .call_extern) {
                        try self.ensureExternalSymbol(ins.callee);
                        try self.recordBootstrapExternCost(ins);
                    }
                    try self.materializePendingVarargs(temps, pinned);
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
                    if (ins.op == .call_extern) {
                        try self.ensureExternalSymbol(ins.callee);
                        try self.recordBootstrapExternCost(ins);
                    }
                    try self.materializePendingVarargs(temps, pinned);
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
                        if (arg_reg != 0) {
                            try self.preserveArgReg(temps, pinned, 0);
                            try self.emitMovReg(0, arg_reg);
                        }
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
                    if (ins.op == .call_extern) {
                        try self.ensureExternalSymbol(ins.callee);
                        try self.recordBootstrapExternCost(ins);
                    }
                    try self.materializePendingVarargs(temps, pinned);
                    // The indirect-result pointer has to be materialized BEFORE
                    // `emitSaveCallerRegs`, which moves `sp` down by its own
                    // save area. `add x8, sp, #off` computed inside that window
                    // would name a slot in the save area instead of the buffer.
                    const indirect = try self.indirectResultBuffer(ins);
                    if (indirect) |off| try self.emitAddSpImm(8, off);
                    const preserve_x0 = self.extern_preserve_x0 and ins.op == .call_extern and
                        std.mem.eql(u8, ins.callee, "snprintf");
                    if (preserve_x0) {
                        try self.emitSubSp(16);
                        try self.emitStrSp(0, 0);
                    }
                    const save = try self.emitSaveCallerRegs();
                    const vbytes = try self.emitPushVarargs();
                    try self.emitBl(ins.callee);
                    try self.emitPopVarargs(vbytes);
                    var call_result: ?u5 = null;
                    var call_result_on_stack = false;
                    if (ins.result != null) {
                        if (!saveSetContains(save, 0)) {
                            self.used_regs[0] = true;
                            call_result = 0;
                        } else if (self.allocRegOutsideSaveSet(save)) |dst| {
                            try self.emitMovReg(dst, 0);
                            call_result = dst;
                        } else |_| {
                            // Every allocatable register was live at save time.
                            // Park the return just above the save block; after
                            // restore that slot sits at [sp, #0].
                            try self.emitStrSp(0, save.stack_bytes);
                            call_result_on_stack = true;
                        }
                    }
                    try self.emitRestoreCallerRegs(save);
                    try self.syncGateLocalTempsAfterCall(temps, pinned);
                    if (preserve_x0) {
                        if (self.extern_preserve_x0_temp) |t| {
                            const reg = try self.allocReg();
                            try self.emitLdrSp(reg, 0);
                            try temps.put(self.alloc, t, reg);
                        }
                        try self.emitAddSp(16);
                        self.extern_preserve_x0 = false;
                        self.extern_preserve_x0_temp = null;
                    }
                    // An indirect return has already landed: the callee wrote
                    // the caller's buffer through x8, so there is nothing in
                    // x0..x7 to copy out.
                    if (ins.record.len > 0 and indirect == null) {
                        if (f64RecordDesc(self.f64_records, ins.record)) |frec| {
                            const base = if (ins.field.len > 0) ins.field else "rec";
                            try self.assignF64RecordFromFpAbiRegs(base, frec);
                        } else if (scalRecordDesc(self.scal_records, ins.record)) |rec| {
                            const base = if (ins.field.len > 0) ins.field else "rec";
                            try self.assignRecordFromAbiRegs(base, rec);
                        } else return self.refuse(@src());
                    }
                    if (ins.result) |result| {
                        if (call_result_on_stack) {
                            const dst = try self.allocReg();
                            try self.emitLdrSp(dst, 0);
                            call_result = dst;
                        }
                        if (call_result) |dst| {
                            try temps.put(self.alloc, result, dst);
                        }
                    }
                }
            },
            .init_record => {
                if (ins.record.len > 0) {
                    if (f64RecordDesc(self.f64_records, ins.record)) |frec| {
                        const base = if (ins.field.len > 0) ins.field else "rec";
                        try self.assignF64RecordFromFpAbiRegs(base, frec);
                    } else if (scalRecordDesc(self.scal_records, ins.record)) |rec| {
                        // A wide record never arrived in x0..x7. It is either
                        // the buffer a callee just filled through x8, or a
                        // literal whose fields already live in their own
                        // locals; copying eight argument registers over it
                        // would overwrite real data with call debris.
                        //
                        // NEITHER DID A NARROW LITERAL. `.field` is the fact, and it is
                        // already in the IR: `lowerRecordCallAssign` (dnir_lower.zig:3484) is
                        // the ONLY site that names the binding, and the only one that follows
                        // a `call_direct` whose record result is really in x0..x7. The two
                        // literal sites (:4317, :4415) leave `.field` empty and their fields
                        // are already in their own locals under `x.a`, never under `rec.a`.
                        // Copying the argument file over `rec.*` was n stores nothing can
                        // load -- argc/argv/envp for `_main`, live call debris anywhere else.
                        if (ins.field.len > 0 and rec.field_names.len <= dnir_lower.max_reg_record_fields) {
                            try self.assignRecordFromAbiRegs(ins.field, rec);
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
                } else if (constRetImm(self, ins.lhs)) |n| {
                    // A constant return materializes DIRECTLY into x0. Routing it
                    // through evalDnirValue allocates a scratch register first, so
                    // the emitted floor was `mov x9,#k ; mov x0,x9 ; ret` where the
                    // actual floor — and what clang -O3 emits — is `mov x0,#k ; ret`.
                    // One wasted instruction on the single hottest shape the direct
                    // backend produces (every folded recognizer result returns this
                    // way), so it is worth the special case.
                    try self.emitMovImm(0, n);
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
                    (ins.record.len > 0 and f64RecordDesc(self.f64_records, ins.record) != null))
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
                // GAP-118: NULL is unknown, not "". A strlen walk must not
                // `ldrb` it — `cited(path)` after `hits += flag(...)` saw
                // address 0 and SIGSEGV'd.
                try self.emitCmpZero(base);
                const null_patch = try self.emitBCond(.eq, 0);
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
                try self.patchCondBranch(null_patch, done_off);
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
                // Unknown str (NULL from missing os.args / os.env) is not a
                // C "(null)" sentinel. Skip puts. Present empty still prints.
                var skip: ?u32 = null;
                if (ins.ty == .str) {
                    try self.emitCmpZero(0);
                    skip = try self.emitBCond(.eq, 0);
                }
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
                if (skip) |off| try self.patchCondBranch(off, @intCast(self.code.items.len));
                try self.syncGateLocalTempsAfterCall(temps, pinned);
            },
            .alloc_slots => {
                const t = ins.result orelse return self.refuse(@src());
                if (self.const_bases.get(t)) |symbol_index| {
                    // DETERMINED, NEVER WRITTEN, NEVER ESCAPING. The words are
                    // already in `__TEXT,__const`, so there is nothing to build:
                    // two instructions place the section's address and the
                    // element stores below are not emitted at all. `load_index`
                    // needs no change — it indexes this base exactly as it
                    // indexed a frame base.
                    const dst = try self.allocReg();
                    try self.emitAdrpAdd(dst, symbol_index);
                    try temps.put(self.alloc, t, dst);
                    return;
                }
                const off = self.slot_bases.get(t) orelse return self.refuse(@src());
                const dst = try self.allocReg();
                try self.emitAddSpImm(dst, off);
                try temps.put(self.alloc, t, dst);
            },
            .load_index, .store_index => |op| if (ins.ty == .i64) {
                // THE INITIALIZING RUN OF A PROMOTED TABLE IS NOT EMITTED.
                //
                // This is the whole win: `mov` the literal / `str` it at a folded
                // offset, twice per element, replaced by nothing. It is only safe
                // because `const_table.recognize` proved these stores are the ONLY
                // writes this base ever receives and that they all precede every
                // read — a table that is written anywhere else never reaches here,
                // it keeps its frame region and every one of these instructions.
                //
                // BOTH FACES OF THE BASE. The initializing run addresses the
                // region as a `.temp`; once the table's name is bound to the same
                // id every later mention arrives as a `.local`. They are one
                // storage (`evalDnirValue` resolves both through `temps`), so
                // both have to be recognized here.
                if (op == .store_index) {
                    const base_id: ?u32 = switch (ins.lhs) {
                        .temp, .local => |id| id,
                        else => null,
                    };
                    if (base_id) |id| if (self.const_bases.contains(id)) return;
                }
                // Memory-backed positional table: 8-byte elements, Idol-indexed
                // from 1, so element `i` is at `base + (i - 1) * 8`. The scaled
                // register form `[base, idx, lsl #3]` does the multiply for
                // free, so only the 1-based bias costs an instruction.
                const base = try self.evalDnirValue(temps, ins.lhs);

                // A CONSTANT INDEX NEEDS NO INDEX REGISTER AT ALL.
                //
                // `base + (k - 1) * 8` is a compile-time number when `k` is, so
                // the whole address computation collapses into the load/store's
                // own unsigned-offset field. That removed three instructions per
                // element from the materialization of a positional table — the
                // binding emits one `store_index` per element with a LITERAL
                // index, and was paying `mov idx / mov one / sub` to rediscover
                // a number the compiler already had. A 32-element table cost 160
                // instructions to set up; it now costs 64. Same for a constant
                // read: `t(3)` is one `ldr`.
                //
                // The guard is the encoding's, not a heuristic: the offset field
                // is a 12-bit count of 8-byte units, so `k` must be at least 1
                // (Idol's own lower bound) and no more than 4096. Anything else
                // falls through to the register form below, which is correct at
                // every index.
                const const_off: ?u16 = blk: {
                    const k = switch (ins.rhs) {
                        .i64 => |n| n,
                        else => break :blk null,
                    };
                    if (k < 1 or k > 4096) break :blk null;
                    break :blk @intCast((k - 1) * 8);
                };
                if (const_off) |off| {
                    if (op == .load_index) {
                        const dst = try self.allocReg();
                        try self.emitLdrBaseImm(dst, base, off);
                        if (ins.result) |t| try temps.put(self.alloc, t, dst);
                    } else {
                        const val = try self.evalDnirValue(temps, ins.third);
                        try self.emitStrBaseImm(val, base, off);
                        self.releaseDnirTemp(pinned, ins.third, val);
                    }
                    // Same ownership rule as the register path: the base is
                    // shared by every element's store and is released by whoever
                    // owns it, not here.
                    self.releaseDnirTemp(pinned, ins.lhs, base);
                    return;
                }

                const idx = try self.evalDnirValue(temps, ins.rhs);
                const biased = try self.allocReg();
                try self.emitSubImm(biased, idx, 1);
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
                const saddr = try self.allocReg();
                try self.emitSubImm(saddr, sidx, 1);
                try self.emitAddReg(saddr, sbase, saddr);
                try self.emitStrb(sval, saddr);
                self.releaseReg(saddr);
                self.releaseDnirTemp(pinned, ins.lhs, sbase);
                self.releaseDnirTemp(pinned, ins.rhs, sidx);
                self.releaseDnirTemp(pinned, ins.third, sval);
            } else {
                // `string.byte(s, i)`: Idol indexes strings from 1, C pointers
                // from 0, so the byte lives at `base + (i - 1)`.
                const base = try self.evalDnirValue(temps, ins.lhs);
                const idx = try self.evalDnirValue(temps, ins.rhs);
                const addr = try self.allocReg();
                try self.emitSubImm(addr, idx, 1);
                try self.emitAddReg(addr, base, addr);
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
                // The tags are checked BEFORE `.hw`, so a trap or a vector
                // reduction never reaches `emitHwUnary` and `.hw` stays `.none`
                // for every other consumer of this instruction. See
                // `dnir_lower.trap_abort_tag` / `vec_reduce_add_i64_tag`.
                if (std.mem.eql(u8, ins.field, dnir_lower.trap_abort_tag)) {
                    try self.emitTrapAbort();
                    return;
                }
                if (std.mem.eql(u8, ins.field, dnir_lower.vec_reduce_add_i64_tag)) {
                    try self.emitVecReduceAddI64(temps, pinned, ins);
                    return;
                }
                if (std.mem.eql(u8, ins.field, dnir_lower.index_bounds_tag)) {
                    try self.emitIndexBoundsCheck(temps, pinned, ins);
                    return;
                }
                const src = try self.evalDnirValue(temps, ins.lhs);
                const dst = try self.allocReg();
                try self.emitHwUnary(dst, src, ins.hw);
                if (!Arm64Compiler.regIsPinned(pinned, src)) self.releaseReg(src);
                if (ins.result) |t| try temps.put(self.alloc, t, dst);
            },
            else => return self.refuse(@src()),
        }
    }

    /// The expansion of `dnir_lower.trap_abort_tag` — `abort()` WITHOUT a call.
    ///
    /// Six words, no `bl`, no x30, no relocation, no import:
    ///
    ///     mov x16, #20      ; SYS_getpid
    ///     svc #0x80         ; -> x0 = pid
    ///     mov x1,  #6       ; SIGABRT
    ///     mov x16, #37      ; SYS_kill
    ///     svc #0x80         ; kill(getpid(), SIGABRT)
    ///     brk #1            ; unreachable; SIGTRAP if the kernel ever returns
    ///
    /// WHY THE SIGNAL AND NOT JUST `brk`. `brk` alone is one word and terminates,
    /// but it raises SIGTRAP, so the process exits 133 where `abort()` exited
    /// 134. The exit code is this subset's ONLY observable — it is how every gate
    /// on the surface states its answer — so silently renumbering the trap would
    /// change observable behaviour to buy five words in a block that never
    /// executes. `kill(getpid(), SIGABRT)` reproduces `abort()`'s exit code
    /// EXACTLY, and the trailing `brk` means even a kernel that returned from
    /// `kill` (it cannot for an unblocked SIGABRT, but the register allocator has
    /// no way to know that) still stops here rather than falling through into the
    /// success path with a clobbered x0/x1/x16.
    ///
    /// WHY CLOBBERING x0/x1/x16 IS SAFE, which is the only thing that makes six
    /// unallocated registers acceptable: control never leaves this sequence.
    /// There is no path from here to any later instruction, so no live value can
    /// be read after it, so nothing needs saving — which is precisely the
    /// property `call_extern` did NOT have and precisely why it cost so much.
    ///
    /// `svc` is a kernel entry, not a procedure call: it does not write x30 and
    /// does not consume a frame, so a function whose only "call" was this one is
    /// still a leaf.
    fn emitTrapAbort(self: *Arm64Compiler) Error!void {
        const movz = struct {
            fn word(reg: u5, imm: u16) u32 {
                return 0xd2800000 | (@as(u32, imm) << 5) | @as(u32, reg);
            }
        }.word;
        try self.emitFmt(movz(16, 20), "mov x16, #{d}", .{20});
        try self.emit(0xd4001001, "svc #0x80");
        try self.emitFmt(movz(1, 6), "mov x1, #{d}", .{6});
        try self.emitFmt(movz(16, 37), "mov x16, #{d}", .{37});
        try self.emit(0xd4001001, "svc #0x80");
        try self.emit(0xd4200020, "brk #1");
    }

    /// The expansion of `dnir_lower.index_bounds_tag` — `1 <= i <= len` in ONE
    /// compare.
    ///
    /// The two-sided test used to be two DNIR comparisons and three branches,
    /// which the backend fused into five instructions on the path that is taken:
    ///
    ///     cmp x15, x13        ; x13 hoisted #1
    ///     b.lt  trap
    ///     cmp x15, x14        ; x14 hoisted #len
    ///     b.gt  trap
    ///     b     ok            ; jump over the trap block
    ///
    /// plus two `mov`s outside the loop to hold the two constants. Three of
    /// those five run on EVERY subscript of EVERY iteration, and a subscript is
    /// the single hottest idiom in this tree — an exact dynamic attribution put
    /// array indexing at 66.3% of all executed instructions in `native.out`.
    ///
    /// One UNSIGNED compare answers both sides. `i - 1` wraps for every `i <= 0`
    /// to a value at the top of the range, so
    ///
    ///     sub x16, x15, #1
    ///     cmp x16, #len-1
    ///     b.ls  ok            ; unsigned: in range
    ///     <trap>
    ///     ok:
    ///
    /// rejects `i = 0` and `i = -1` by the same comparison that rejects
    /// `i = len + 1`. Three instructions on the taken path, no hoisted
    /// constants, and the trap block is jumped over by the SAME branch that
    /// tests the range rather than by an extra unconditional one.
    ///
    /// THE SIGNED FORM WOULD BE WRONG HERE, which is why `Condition` grew `ls`
    /// rather than reusing `le`: `-1 <= len - 1` is true signed and false
    /// unsigned, so a signed `b.le` would let `xs(0 - 1)` through to read the
    /// word below the region — the exact defect gap[063] exists to stop.
    ///
    /// `len` is the table's static extent, so `len - 1` is a compile-time
    /// number; the 12-bit immediate covers extents to 4096. Anything wider
    /// refuses rather than guessing, and `guardedTableIndex` never emits this
    /// for a table whose extent is unknown.
    fn emitIndexBoundsCheck(
        self: *Arm64Compiler,
        temps: *std.AutoHashMapUnmanaged(u32, u5),
        pinned: *const std.AutoHashMapUnmanaged(u32, u5),
        ins: dnir.Instr,
    ) Error!void {
        const len = switch (ins.rhs) {
            .i64 => |n| n,
            else => return self.refuse(@src()),
        };
        if (len < 1 or len > 4096) return self.refuse(@src());
        const idx = try self.evalDnirValue(temps, ins.lhs);
        const biased = try self.allocReg();
        try self.emitSubImm(biased, idx, 1);
        try self.emitCmpImm(biased, @intCast(len - 1));
        const in_range = try self.emitBCond(.ls, 0);
        try self.emitTrapAbort();
        try self.patchCondBranch(in_range, @intCast(self.code.items.len));
        self.releaseReg(biased);
        self.releaseDnirTemp(pinned, ins.lhs, idx);
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
            // lib/target/arm64.id against clang. A 32-bit reverse writes
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
    /// `examples/mandelbrot.id` reached both directions in one expression:
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

    /// An i64 constant that can be materialized straight into the return register.
    /// Null when the value is not a plain constant, or when it is already hoisted
    /// into a reserved register (reusing that register is cheaper than re-emitting
    /// the mov/movk chain).
    fn constRetImm(self: *Arm64Compiler, v: dnir.Value) ?i64 {
        return switch (v) {
            .i64 => |n| if (self.imm_hoist.get(n) == null) n else null,
            else => null,
        };
    }

    fn evalDnirValue(self: *Arm64Compiler, temps: *std.AutoHashMapUnmanaged(u32, u5), v: dnir.Value) Error!u5 {
        if (self.crossFile(v, false)) return self.refuse(@src());
        return switch (v) {
            .void => try self.allocReg(),
            .i64 => |n| blk: {
                // A loop-invariant constant already sits in a reserved register;
                // reuse it instead of re-emitting a mov/movk chain (FTCFTW debt (1)).
                if (self.imm_hoist.get(n)) |r| break :blk r;
                const r = try self.allocReg();
                try self.emitMovImm(r, n);
                break :blk r;
            },
            .f64 => |n| blk: {
                const bits: i64 = @bitCast(n);
                if (self.imm_hoist.get(bits)) |r| break :blk r;
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
                if (self.gp_stack_locals.get(slot)) |off| {
                    return try self.loadGpStackLocal(off);
                }
                if (self.eval_pinned) |p| {
                    if (p.get(slot)) |r| {
                        return try self.ensureRegLiveRemap(temps, r);
                    }
                }
                if (temps.get(slot)) |r| {
                    return try self.ensureRegLiveRemap(temps, r);
                }
                return self.undefinedAt(@src(), "local", slot);
            },
            .temp => |t| {
                const r = temps.get(t) orelse return self.undefinedAt(@src(), "temp", t);
                return try self.ensureRegLiveRemap(temps, r);
            },
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

    fn emitCompareOrBinop(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5, op: dnir.BinOpTag) Error!void {
        if (comparisonCondition(op)) |condition| {
            try self.emitCompareResult(dst, lhs, rhs, condition);
            return;
        }
        switch (op) {
            .add => try self.emitAddReg(dst, lhs, rhs),
            .sub => try self.emitSubReg(dst, lhs, rhs),
            .mul => try self.emitMulReg(dst, lhs, rhs),
            .div => try self.emitSdivReg(dst, lhs, rhs),
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
            .shl => try self.emitBitReg(0x9ac02000, "lsl", dst, lhs, rhs),
            .shr => try self.emitBitReg(0x9ac02400, "lsr", dst, lhs, rhs),
            .eq, .neq, .lt, .gt, .leq, .geq => unreachable,
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

    fn gpSlotUsesStack(self: *const Arm64Compiler, slot: u32) bool {
        return self.gp_stack_locals.contains(slot);
    }

    /// After gatecap/sh calls, `temps` may still name caller-saved registers the
    /// call clobbered. Stack locals must reload from the frame; register homes in
    /// `pinned` survived `emitSaveCallerRegs` and must be republished to `temps`.
    fn syncGateLocalTempsAfterCall(
        self: *const Arm64Compiler,
        temps: *std.AutoHashMapUnmanaged(u32, u5),
        pinned: *std.AutoHashMapUnmanaged(u32, u5),
    ) Error!void {
        if (self.gp_stack_locals.count() == 0 or !self.cur_func_has_call) return;
        var sit = self.gp_stack_locals.keyIterator();
        while (sit.next()) |slot| {
            _ = temps.remove(slot.*);
            _ = pinned.remove(slot.*);
        }
        var pit = pinned.keyIterator();
        while (pit.next()) |slot| {
            if (pinned.get(slot.*)) |reg| {
                try temps.put(self.alloc, slot.*, reg);
            }
        }
    }

    /// ARM64 `str xN, [sp, #imm]` scaled offset is limited (~32 KiB frame).
    fn ensureRegLive(self: *Arm64Compiler, reg: u5) Error!void {
        if (self.spilled_regs.get(reg)) |off| {
            const reload_off = self.stack_frame_bytes - off - 8;
            try self.emitLdrSp(reg, reload_off);
            _ = self.spilled_regs.remove(reg);
            try self.free_spill_slots.append(self.alloc, off);
        }
    }

    /// Reload a spilled register into a fresh register and remap every temp
    /// that still names the old one. Without this, a spilled register stays
    /// reserved in `spilled_regs` until its owner is read again into the same
    /// physical register, which caps live values at the allocatable pool size.
    fn ensureRegLiveRemap(
        self: *Arm64Compiler,
        temps: *std.AutoHashMapUnmanaged(u32, u5),
        reg: u5,
    ) Error!u5 {
        const off = self.spilled_regs.get(reg) orelse return reg;
        const reload_off = self.stack_frame_bytes - off - 8;
        const fresh = self.allocRegExcluding(null) catch |e| {
            if (e != error.RegisterExhausted or !self.gate_transport) return e;
            return try self.reclaimSpilledReg();
        };
        try self.emitLdrSp(fresh, reload_off);
        _ = self.spilled_regs.remove(reg);
        try self.free_spill_slots.append(self.alloc, off);
        var it = temps.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == reg) entry.value_ptr.* = fresh;
        }
        return fresh;
    }

    fn spillReg(self: *Arm64Compiler, victim: u5) Error!void {
        try self.cost.record(
            self.alloc,
            .spill,
            "register pool exhausted; spilled live temp to stack frame",
        );
        const off: u16 = if (self.free_spill_slots.pop()) |slot|
            slot
        else if (self.gate_spill_end > self.gate_spill_base) blk: {
            if (self.gate_spill_cursor + 16 > self.gate_spill_end) return error.RegisterExhausted;
            const slot = self.gate_spill_cursor;
            self.gate_spill_cursor += 16;
            break :blk slot;
        } else blk: {
            // LAST RESORT, AND ONLY WHEN NOTHING ELSE LIVES IN THE FRAME.
            //
            // This moves `sp` in the MIDDLE of the body, and every offset the
            // prologue handed out is measured from the `sp` the prologue left
            // behind. Gate transport was already excluded for exactly this
            // reason (`digits(gatecap(...))` read `12` out of `181` after the
            // first loop iteration, from a local whose slot had shifted under
            // it), but the exclusion named one symptom instead of the rule.
            //
            // The rule: a frame with ANY other resident — GP stack locals, a
            // memory-backed table region, a record region — cannot have `sp`
            // moved under it. Refusing falls back to the C emit path, which is
            // slower and CORRECT; the alternative is an artifact that computes
            // the wrong answer and reports success, which is the failure this
            // whole area has produced twice already.
            //
            // Reachable much less often than it looks: spilling requires all
            // nineteen allocatable registers to be busy, which implies pressure
            // above the caller-save homes, which now reserves a spill area in
            // the prologue (see `wants_spill`) and takes the branch above.
            if (self.gate_transport) return error.RegisterExhausted;
            if (self.gp_stack_locals.count() > 0 or
                self.slot_bases.count() > 0 or
                self.fp_stack_slots.count() > 0) return error.RegisterExhausted;
            if (self.stack_frame_bytes + 16 > self.spill_frame_budget) return error.RegisterExhausted;
            const slot = self.stack_frame_bytes;
            self.stack_frame_bytes += 16;
            try self.emitSubSp(16);
            break :blk slot;
        };
        try self.ensureRegLive(victim);
        const store_off = self.stack_frame_bytes - off - 8;
        try self.emitStrSp(victim, store_off);
        try self.spilled_regs.put(self.alloc, victim, off);
        self.used_regs[victim] = false;
    }

    /// x18 is Apple's PLATFORM REGISTER. AAPCS64 leaves it to the platform and
    /// Apple's arm64 ABI reserves it outright — "don't use this register" —
    /// so it is not part of the allocatable pool even though it sits in the
    /// middle of x9..x28. The pool could always reach it under pressure; a
    /// record return staging eight fields at once reaches it reliably.
    const platform_reserved_reg: u5 = 18;

    fn reclaimSpilledReg(self: *Arm64Compiler) Error!u5 {
        var it = self.spilled_regs.keyIterator();
        while (it.next()) |reg_ptr| {
            const reg = reg_ptr.*;
            _ = self.spilled_regs.remove(reg);
            self.claimReg(reg);
            return reg;
        }
        return error.RegisterExhausted;
    }

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
                self.claimReg(reg);
                return reg;
            }
        }
        reg = 0;
        while (reg < 8) : (reg += 1) {
            if (exclude != null and reg == exclude.?) continue;
            if (self.pending_arg_regs & (@as(u8, 1) << @as(u3, @intCast(reg))) != 0) continue;
            if (self.spilled_regs.contains(reg)) continue;
            if (!self.used_regs[reg]) {
                self.claimReg(reg);
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
        victim = 7;
        while (true) : (victim -= 1) {
            if (exclude != null and victim == exclude.?) {
                if (victim == 0) break;
                continue;
            }
            // A staged argument register is not a spill candidate: its live value
            // belongs to the call being marshaled, not to a temp we can park.
            if (self.pending_arg_regs & (@as(u8, 1) << @as(u3, @intCast(victim))) != 0) {
                if (victim == 0) break;
                continue;
            }
            if (!self.used_regs[victim]) {
                if (victim == 0) break;
                continue;
            }
            try self.spillReg(victim);
            return self.allocRegExcluding(exclude);
        }
        if (self.gate_transport) return self.reclaimSpilledReg();
        return error.RegisterExhausted;
    }

    fn allocReg(self: *Arm64Compiler) Error!u5 {
        return self.allocRegExcluding(null);
    }

    fn restoreStackFrame(self: *Arm64Compiler) Error!void {
        if (self.stack_frame_bytes > 0) {
            try self.emitAddSp(self.stack_frame_bytes);
        }
        try self.emitRestoreCalleeRegs();
    }

    /// Apple AAPCS64: x19–x28 belong to the caller. Save them under the
    /// locals/spill frame so `[sp,#off]` homes stay zero-based.
    const callee_save_first: u5 = 19;
    const callee_save_last: u5 = 28;
    const callee_save_count: u16 = @as(u16, callee_save_last - callee_save_first + 1);
    const callee_save_span: u16 = callee_save_count * 8;
    /// Every callee-saved register, i.e. what the prologue used to save
    /// unconditionally.
    const callee_save_all: u32 = blk: {
        var m: u32 = 0;
        var r: u5 = callee_save_first;
        while (r <= callee_save_last) : (r += 1) m |= @as(u32, 1) << r;
        break :blk m;
    };

    /// Mark a register as claimed, remembering it if the ABI makes it ours to
    /// give back. One funnel, because a claim that skips this is a register
    /// saved by nobody — an ABI violation in the CALLER, which is the class of
    /// defect that cannot be found by running the callee.
    fn claimReg(self: *Arm64Compiler, reg: u5) void {
        self.used_regs[reg] = true;
        if (reg >= callee_save_first and reg <= callee_save_last) {
            self.callee_touched |= @as(u32, 1) << reg;
        }
    }

    /// Save exactly the callee-saved registers in `callee_save_plan`.
    ///
    /// This block used to be ten stores and ten loads in every function that
    /// reached x19 at all, whether it reached x28 or stopped at x19. Measured
    /// across the surface's artifacts, 737 of 790 saved registers were never
    /// written — 1,474 instructions preserving values nothing touched, and in
    /// five artifacts (`lex`, `array`, `branch`, `control`, `match`) not a single
    /// saved register was used by anything.
    ///
    /// The SPAN is deliberately NOT narrowed with the set. Every register keeps
    /// its fixed slot at `(r - 19) * 8`, so `callee_save_bytes` stays 80 whenever
    /// anything is saved and no stacked-parameter displacement moves as a
    /// function of WHICH registers were needed. Only the empty plan collapses
    /// the frame, and then it collapses completely — no `sub sp`, no `add sp`,
    /// nothing.
    fn emitSaveCalleeRegs(self: *Arm64Compiler) Error!void {
        if (self.callee_save_plan == 0) return;
        try self.emitSubSp(callee_save_span);
        var reg: u5 = callee_save_first;
        while (reg <= callee_save_last) : (reg += 1) {
            if (self.callee_save_plan & (@as(u32, 1) << reg) == 0) continue;
            try self.emitStrSp(reg, (@as(u16, reg) - callee_save_first) * 8);
        }
        self.callee_save_bytes = callee_save_span;
    }

    fn emitRestoreCalleeRegs(self: *Arm64Compiler) Error!void {
        if (self.callee_save_bytes == 0) return;
        var reg: u5 = callee_save_first;
        while (reg <= callee_save_last) : (reg += 1) {
            if (self.callee_save_plan & (@as(u32, 1) << reg) == 0) continue;
            try self.emitLdrSp(reg, (@as(u16, reg) - callee_save_first) * 8);
        }
        try self.emitAddSp(self.callee_save_bytes);
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
        if (reg >= 29) return;
        if (reg == platform_reserved_reg) return;
        if (reg >= 9 and reg < 29 and self.gp_home_regs[reg]) return;
        if (self.gp_reg_owner[reg] != null) return;
        self.used_regs[reg] = false;
        _ = self.spilled_regs.remove(reg);
    }

    /// Before an argument is written into a caller-saved ABI register (x0-x7),
    /// move any live temp that still occupies it into an owned register (x9-x28).
    /// The first of two calls in `f(a) + f(b)` — e.g. `fib(n-1) + fib(n-2)` —
    /// homes its result in x0 as the fast path, and x0 is never tracked in
    /// `gp_reg_owner`. Without this relocation the second call's argument
    /// marshaling overwrote that result BEFORE `emitSaveCallerRegs` could
    /// preserve it, so the `+` read the second argument in place of the first
    /// result: recursion collapsed to `f(n) = (n-2) + f(n-2)` and returned
    /// wrong values for fib(n) >= 7. An owned register is preserved across the
    /// call by the ordinary save/restore and freed by the liveness sweep.
    /// Reserve `slot` (an x0..x7 argument register) as holding a staged argument
    /// for the call being marshaled, so `allocRegExcluding` will not hand it out
    /// as scratch while a later argument's operand is loaded. Cleared by `emitBl`.
    fn markStagedArgReg(self: *Arm64Compiler, slot: u5) void {
        if (slot < 8) self.pending_arg_regs |= (@as(u8, 1) << @as(u3, @intCast(slot)));
    }

    fn preserveArgReg(
        self: *Arm64Compiler,
        temps: *std.AutoHashMapUnmanaged(u32, u5),
        pinned: *const std.AutoHashMapUnmanaged(u32, u5),
        slot: u5,
    ) Error!void {
        if (slot >= 8) return;
        if (Arm64Compiler.regIsPinned(pinned, slot)) return;
        var victim: ?u32 = null;
        var it = temps.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == slot) {
                victim = entry.key_ptr.*;
                break;
            }
        }
        const t = victim orelse return;
        const fresh = try self.allocReg();
        if (fresh == slot) {
            self.releaseReg(fresh);
            return;
        }
        try self.emitMovReg(fresh, slot);
        try temps.put(self.alloc, t, fresh);
        if (fresh >= 9 and fresh < 29 and fresh != platform_reserved_reg and !self.gp_home_regs[fresh]) {
            self.gp_reg_owner[fresh] = t;
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
        // The call has consumed its argument registers; they are ordinary scratch
        // again for the result marshaling and the code that follows.
        self.pending_arg_regs = 0;
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

    fn saveSetContains(save: SaveSet, reg: u5) bool {
        var i: u5 = 0;
        while (i < save.count) : (i += 1) {
            if (save.regs[i] == reg) return true;
        }
        return false;
    }

    /// Pick a GP register that `emitRestoreCallerRegs` will not reload. A return
    /// value parked in a register that was live at save time is overwritten by
    /// restore even when the mov ran after `bl`.
    fn allocRegOutsideSaveSet(self: *Arm64Compiler, save: SaveSet) Error!u5 {
        var reg: u5 = 9;
        while (reg < 29) : (reg += 1) {
            if (reg == platform_reserved_reg) continue;
            if (saveSetContains(save, reg)) continue;
            if (self.spilled_regs.contains(reg)) continue;
            if (!self.used_regs[reg]) {
                self.claimReg(reg);
                return reg;
            }
        }
        reg = 0;
        while (reg < 8) : (reg += 1) {
            if (saveSetContains(save, reg)) continue;
            if (self.spilled_regs.contains(reg)) continue;
            if (!self.used_regs[reg]) {
                self.claimReg(reg);
                return reg;
            }
        }
        return error.RegisterExhausted;
    }

    fn emitSaveCallerRegs(self: *Arm64Compiler) Error!SaveSet {
        var save_set = SaveSet{};
        var reg: u5 = 0;
        while (reg < 8) : (reg += 1) {
            if (self.used_regs[reg]) {
                save_set.regs[save_set.count] = reg;
                save_set.count += 1;
            }
        }
        reg = 9;
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
    fn materializePendingVarargs(
        self: *Arm64Compiler,
        temps: *std.AutoHashMapUnmanaged(u32, u5),
        pinned: *const std.AutoHashMapUnmanaged(u32, u5),
    ) Error!void {
        var i: u5 = 0;
        while (i < self.pending_vararg_count) : (i += 1) {
            var slot = &self.pending_varargs[i];
            const v = slot.operand orelse continue;
            var reg = try self.evalDnirValue(temps, v);
            // A STACK-homed local is read by loadGpStackLocal into a FRESH register
            // that no map owns, so treating it as owned leaks one register per
            // stack argument per call — the pool drains and the body refuses with
            // DNB003 even though nothing is genuinely live. Same rule releaseDnirTemp
            // already applies on the register-argument path.
            const owned = switch (v) {
                .temp => true,
                .local => |home| !self.gp_stack_locals.contains(home),
                else => false,
            };
            if (reg < 8) {
                const fresh = try self.allocReg();
                try self.emitMovReg(fresh, reg);
                if (!owned and !Arm64Compiler.regIsPinned(pinned, reg)) self.releaseReg(reg);
                reg = fresh;
            }
            slot.reg = reg;
            slot.operand = null;
            slot.scratch = !owned and !Arm64Compiler.regIsPinned(pinned, reg);
        }
    }

    fn emitPushVarargs(self: *Arm64Compiler) Error!u16 {
        if (self.pending_vararg_count == 0) return 0;
        var bytes: u16 = @as(u16, self.pending_vararg_count) * 8;
        if ((bytes % 16) != 0) bytes += 8;
        try self.emitSubSp(bytes);
        var i: u5 = 0;
        while (i < self.pending_vararg_count) : (i += 1) {
            const slot = self.pending_varargs[i];
            if (slot.operand != null) return self.refuse(@src());
            try self.emitStrSp(slot.reg, @as(u16, i) * 8);
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

    /// Largest 16-byte-aligned `sub/add sp` immediate on AArch64 (imm12 max 4095).
    const sp_imm_max: u16 = 4080;

    fn emitSubSp(self: *Arm64Compiler, bytes: u16) Error!void {
        var rem: u32 = bytes;
        while (rem > 0) {
            const chunk: u16 = if (rem > sp_imm_max) sp_imm_max else @intCast(rem);
            try self.emitFmt(0xd10003ff | (@as(u32, chunk) << 10), "sub sp, sp, #{d}", .{chunk});
            rem -= chunk;
        }
    }

    fn emitAddSp(self: *Arm64Compiler, bytes: u16) Error!void {
        var rem: u32 = bytes;
        while (rem > 0) {
            const chunk: u16 = if (rem > sp_imm_max) sp_imm_max else @intCast(rem);
            try self.emitFmt(0x910003ff | (@as(u32, chunk) << 10), "add sp, sp, #{d}", .{chunk});
            rem -= chunk;
        }
    }

    fn emitStrSp(self: *Arm64Compiler, reg: u5, offset: u16) Error!void {
        try self.emitFmt(0xf90003e0 | ((@as(u32, offset) / 8) << 10) | @as(u32, reg), "str x{d}, [sp, #{d}]", .{ reg, offset });
    }

    fn emitLdrSp(self: *Arm64Compiler, reg: u5, offset: u16) Error!void {
        try self.emitFmt(0xf94003e0 | ((@as(u32, offset) / 8) << 10) | @as(u32, reg), "ldr x{d}, [sp, #{d}]", .{ reg, offset });
    }

    /// Release `reg` only if it was scratch for this instruction. A `.temp` or a
    /// register-homed `.local` operand's register is owned by the slot map and
    /// outlives us. A STACK `.local`, however, is reloaded into a fresh scratch
    /// register by `loadGpStackLocal` on every read — that copy is owned by no
    /// map and the liveness sweep (which only frees OWNED registers) can never
    /// reclaim it. Freeing it here is the operand's only exit: staging a stack
    /// local into an argument slot otherwise orphans one register per argument
    /// until the pool is exhausted (surfaced as DNB003 in a call-dense body like
    /// `dorec4` once the mov_arg ownership-rebind that used to mask it was
    /// removed).
    fn releaseDnirTemp(
        self: *Arm64Compiler,
        pinned: *const std.AutoHashMapUnmanaged(u32, u5),
        v: dnir.Value,
        reg: u5,
    ) void {
        switch (v) {
            .temp => return,
            .local => |slot| if (!self.gp_stack_locals.contains(slot)) return,
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

    /// `ldr xd, [xbase, #imm]` — the read half of `emitStrBaseImm`, same
    /// unsigned-offset form. Used when a table subscript's index is known at
    /// compile time: `base + (k - 1) * 8` is then a constant and needs no
    /// register, no `mov` and no `sub`.
    fn emitLdrBaseImm(self: *Arm64Compiler, dst: u5, base: u5, offset: u16) Error!void {
        if (offset % 8 != 0 or offset / 8 > 4095) return self.refuse(@src());
        try self.ensureRegLive(base);
        try self.emitFmt(
            0xf9400000 | ((@as(u32, offset) / 8) << 10) | (@as(u32, base) << 5) | @as(u32, dst),
            "ldr x{d}, [x{d}, #{d}]",
            .{ dst, base, offset },
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
        const rec = scalRecordDesc(self.scal_records, ins.record) orelse return null;
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
    ///
    /// `add` immediates are 12 bits, and a frame can be deeper than 4095 bytes,
    /// so a displacement past that is CHAINED rather than refused. It has to be:
    /// the slot region now sits above the GP local/spill region (see the rebase
    /// in the prologue), which pushes ordinary table bases past 4095 in any
    /// function that both builds a table and spills. Refusing there would turn
    /// working programs into fallbacks purely as a side effect of the rebase.
    /// No scratch register is used — each step adds into `dst` itself.
    fn emitAddSpImm(self: *Arm64Compiler, dst: u5, bytes: u16) Error!void {
        const first: u16 = @min(bytes, 4095);
        try self.emitFmt(
            0x910003e0 | (@as(u32, first) << 10) | @as(u32, dst),
            "add x{d}, sp, #{d}",
            .{ dst, first },
        );
        var rest: u16 = bytes - first;
        while (rest > 0) {
            const step: u16 = @min(rest, 4095);
            try self.emitFmt(
                0x91000000 | (@as(u32, step) << 10) | (@as(u32, dst) << 5) | @as(u32, dst),
                "add x{d}, x{d}, #{d}",
                .{ dst, dst, step },
            );
            rest -= step;
        }
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

    // -----------------------------------------------------------------------
    // NEON. The first vector instructions this backend has ever emitted.
    //
    // Every word below was checked against the system assembler rather than
    // read off a table, because the failure mode is silent: a wrong lane size
    // still assembles, still runs, and answers with the wrong number. The
    // reference assembly and its bytes:
    //
    //     eor.16b  v16, v16, v16      6e301e10
    //     ldr      q17, [x9], #0x10   3cc10531
    //     add.2d   v16, v16, v17      4ef18610
    //     addp.2d  d16, v16           5ef1ba10
    //     fmov     x9, d16            9e660209
    //     subs     x9, x9, #0x1       f1000529
    //
    // Note the arm64 spelling: the LANE SUFFIX IS ON THE MNEMONIC, not on the
    // operands. `docs/hardware-baseline.md` records two probes that reported a
    // clean zero for densely vectorized code because they searched for
    // `v0\.4s`. The listing strings here are written the way the disassembler
    // prints them so the two agree.
    // -----------------------------------------------------------------------

    /// `eor.16b vd, vd, vd` — zero a whole 128-bit register.
    fn emitVecZero(self: *Arm64Compiler, v: u5) Error!void {
        try self.emitFmt(
            0x6e201c00 | (@as(u32, v) << 16) | (@as(u32, v) << 5) | @as(u32, v),
            "eor.16b v{d}, v{d}, v{d}",
            .{ v, v, v },
        );
    }

    /// `ldr qt, [xn], #16` — load two i64 lanes and post-increment the pointer.
    fn emitVecLdrQPost16(self: *Arm64Compiler, t: u5, n: u5) Error!void {
        try self.ensureRegLive(n);
        // imm9 = 16, then the `01` post-index selector in bits 11:10.
        try self.emitFmt(
            0x3cc00400 | (@as(u32, 16) << 12) | (@as(u32, n) << 5) | @as(u32, t),
            "ldr q{d}, [x{d}], #16",
            .{ t, n },
        );
    }

    /// `add.2d vd, vn, vm` — two lanes of 64-bit integer addition. Wraps exactly
    /// as the scalar `add` does, which is what makes regrouping a reduction
    /// exact rather than approximate.
    fn emitVecAdd2d(self: *Arm64Compiler, d: u5, n: u5, m: u5) Error!void {
        try self.emitFmt(
            0x4ee08400 | (@as(u32, m) << 16) | (@as(u32, n) << 5) | @as(u32, d),
            "add.2d v{d}, v{d}, v{d}",
            .{ d, n, m },
        );
    }

    /// `addp.2d dd, vn` — horizontal add of the two lanes into the low double.
    fn emitVecAddp2d(self: *Arm64Compiler, d: u5, n: u5) Error!void {
        try self.emitFmt(
            0x5ef1b800 | (@as(u32, n) << 5) | @as(u32, d),
            "addp.2d d{d}, v{d}",
            .{ d, n },
        );
    }

    /// `fmov xd, dn` — move lane 0 into a general-purpose register.
    fn emitFmovGpFromFp(self: *Arm64Compiler, d: u5, n: u5) Error!void {
        try self.emitFmt(
            0x9e660000 | (@as(u32, n) << 5) | @as(u32, d),
            "fmov x{d}, d{d}",
            .{ d, n },
        );
    }

    /// `subs xd, xn, #imm` — decrement and set flags, so the loop latch needs no
    /// separate compare and no immediate staged in a register per iteration.
    fn emitSubsImm(self: *Arm64Compiler, d: u5, n: u5, imm: u12) Error!void {
        try self.ensureRegLive(n);
        try self.emitFmt(
            0xf1000000 | (@as(u32, imm) << 10) | (@as(u32, n) << 5) | @as(u32, d),
            "subs x{d}, x{d}, #{d}",
            .{ d, n, imm },
        );
    }

    /// The expansion of `dnir_lower.vec_reduce_add_i64_tag`: sum `count`
    /// consecutive i64 words starting at 1-based element `lo` of the table whose
    /// base is `ins.lhs`, and leave the total in `ins.result`.
    ///
    /// `count` is an exact multiple of the lane width and `lo`/`count` were
    /// proven inside the table's extent by the recognizer, so there is no
    /// prologue, no epilogue and no in-loop guard here — the odd element, if
    /// there is one, is handled by the ordinary scalar loop that follows this
    /// instruction. The conditions are re-checked anyway: this is the only place
    /// that knows the load width, and a malformed operand must refuse rather
    /// than read past the region.
    ///
    /// The vector registers come from `allocFpReg`, i.e. the SAME pool the f64
    /// path uses. `d16` and `v16` are one physical register, so allocating from
    /// anywhere else would be the mixed-representation bug in another form.
    /// They are freed here because their whole lifetime is this expansion — no
    /// slot ever names one.
    fn emitVecReduceAddI64(
        self: *Arm64Compiler,
        temps: *std.AutoHashMapUnmanaged(u32, u5),
        pinned: *std.AutoHashMapUnmanaged(u32, u5),
        ins: dnir.Instr,
    ) Error!void {
        const lo: i64 = switch (ins.rhs) {
            .i64 => |v| v,
            else => return self.refuse(@src()),
        };
        const count: i64 = switch (ins.third) {
            .i64 => |v| v,
            else => return self.refuse(@src()),
        };
        if (lo < 1 or count < 2 or @rem(count, 2) != 0) return self.refuse(@src());
        const byte_off: i64 = (lo - 1) * 8;
        if (byte_off > 0xffff) return self.refuse(@src());

        const base = try self.evalDnirValue(temps, ins.lhs);
        try self.ensureRegLive(base);

        const cursor = try self.allocReg();
        const pairs = try self.allocReg();
        if (byte_off == 0) {
            try self.emitMovReg(cursor, base);
        } else {
            try self.emitMovImm(cursor, byte_off);
            try self.emitAddReg(cursor, base, cursor);
        }
        try self.emitMovImm(pairs, @divTrunc(count, 2));

        const acc_v = try self.allocFpReg();
        const dat_v = try self.allocFpReg();
        try self.emitVecZero(acc_v);

        const loop_off: u32 = @intCast(self.code.items.len);
        try self.emitVecLdrQPost16(dat_v, cursor);
        try self.emitVecAdd2d(acc_v, acc_v, dat_v);
        try self.emitSubsImm(pairs, pairs, 1);
        const latch = try self.emitBCond(.ne, 0);
        try self.patchCondBranch(latch, loop_off);

        try self.emitVecAddp2d(acc_v, acc_v);
        self.used_fp_regs[dat_v] = false;

        // Retire the cursor and the trip counter BEFORE claiming the result
        // register. Both are dead once the loop has fallen through, and holding
        // them across the allocation raises this instruction's peak GP demand by
        // two for no reason — which in a register-tight function is the
        // difference between compiling and a DNB003 refusal that the scalar
        // lowering of the same loop would not have hit.
        self.releaseReg(cursor);
        self.releaseReg(pairs);

        const dst = try self.allocReg();
        try self.emitFmovGpFromFp(dst, acc_v);
        self.used_fp_regs[acc_v] = false;
        self.releaseDnirTemp(pinned, ins.lhs, base);
        if (ins.result) |t| try temps.put(self.alloc, t, dst);
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

    /// `sub xd, xn, #imm12` — SUB immediate, 64-bit, no shift.
    ///
    /// The register form needs a second register holding the constant AND the
    /// `mov` that puts it there. Every 1-based table subscript pays that bias,
    /// so the pair was two instructions on the hottest path in the tree. This is
    /// one, and it frees the register the `mov` was consuming.
    fn emitSubImm(self: *Arm64Compiler, dst: u5, lhs: u5, imm: u12) Error!void {
        try self.ensureRegLive(lhs);
        try self.emitFmt(
            0xd1000000 | (@as(u32, imm) << 10) | (@as(u32, lhs) << 5) | @as(u32, dst),
            "sub x{d}, x{d}, #{d}",
            .{ dst, lhs, imm },
        );
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

    /// `cmp xn, #imm12` — SUBS xzr, xn, #imm, the same form `emitCmpZero`
    /// emits with a zero immediate.
    fn emitCmpImm(self: *Arm64Compiler, reg: u5, imm: u12) Error!void {
        try self.ensureRegLive(reg);
        try self.emitFmt(
            0xf100001f | (@as(u32, imm) << 10) | (@as(u32, reg) << 5),
            "cmp x{d}, #{d}",
            .{ reg, imm },
        );
    }

    fn emitCompareResult(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5, cond: Condition) Error!void {
        try self.emitCmpReg(lhs, rhs);
        try self.emitFmt(encodeCset(dst, cond), "cset x{d}, {s}", .{ dst, conditionName(cond) });
    }

    /// `csel xd, xn, xm, cond` — `xd = cond ? xn : xm`.
    ///
    /// Nothing between the `cmp` that set the flags and this instruction may
    /// write NZCV. `ensureRegLive` can only emit a reload (`ldr`), which does
    /// not, so calling it here is safe; an emitter that could touch the flags
    /// would not be.
    fn emitCselReg(self: *Arm64Compiler, dst: u5, n: u5, m: u5, cond: Condition) Error!void {
        try self.ensureRegLive(n);
        try self.ensureRegLive(m);
        try self.emitFmt(
            encodeCsel(dst, n, m, cond),
            "csel x{d}, x{d}, x{d}, {s}",
            .{ dst, n, m, conditionName(cond) },
        );
    }

    /// Peephole precondition for folding `binop(cmp) -> T ; br when_x T` into a
    /// single `cmp; b.cond`. The stock lowering materializes the boolean with
    /// `cset` and then the branch re-tests it with `cmp T, #0` — four
    /// instructions where two suffice. Fusing is admissible only when the
    /// comparison result is an integer boolean consumed by the immediately
    /// following conditional branch and by nothing else, so the materialized
    /// value has no other reader whose register the fold would erase.
    fn compareBranchFusible(self: *const Arm64Compiler, ins: dnir.Instr, nx: dnir.Instr, flat_idx: u32) bool {
        if (ins.op != .binop) return false;
        if (comparisonCondition(ins.binop) == null) return false;
        if (ins.ty == .f64) return false;
        if (ins.application != null or ins.relation != null or ins.value != null) return false;
        if (self.cur_func_float) return false;
        if (self.valueIsFp(ins.lhs) or self.valueIsFp(ins.rhs)) return false;
        const t = ins.result orelse return false;
        if (nx.op != .br) return false;
        switch (nx.branch_condition) {
            .when_true, .when_false => {},
            .unconditional => return false,
        }
        if (nx.lhs != .temp or nx.lhs.temp != t) return false;
        // The comparison result may have exactly one reader: this branch. A
        // widened live range (loop-crossing) or a second consumer leaves the
        // last-use index past the branch, and the conservative answer is to
        // keep the materialized boolean rather than erase a value still read.
        const last = self.value_free_at.get(t) orelse return false;
        return last == flat_idx + 1;
    }

    // ------------------------------------------------------------------
    // R15 — A NAMED CONDITION IS THE SAME CONDITION.
    //
    // `compareBranchFusible` above states its precondition as "consumed by the
    // IMMEDIATELY FOLLOWING conditional branch". That is a syntactic adjacency
    // standing in for the fact it means — SINGLE READER, NO INTERVENING EFFECT
    // — and the two come apart the moment the condition is given a name:
    //
    //     if a > b        ->  cmp ; b.le                    (2)
    //     c = a > b       ->  cmp ; cset ; str ; ldr ; cmp ; b.eq   (6)
    //     if c
    //
    // Measured on a 1e8-trip loop with identical answers: 1.26x instructions,
    // 1.35x cycles (`docs/optimization-space.md` R15). The defect shape is the
    // one this project has closed twice already — a fixed rule standing in for
    // a fact — and the fact is available exactly: the DNIR of the whole
    // function is in hand, so "read once, written once" can be COUNTED.
    // ------------------------------------------------------------------

    /// Reads of local slot `id` across the whole function, and `store_local`
    /// writes to it. Counted rather than inferred: the naming store may only be
    /// erased when this branch is the binding's ONLY reader.
    fn dnirLocalUseCensus(f: dnir.Function, id: u32, reads: *u32, writes: *u32, read_at: *u32, write_at: *u32) void {
        reads.* = 0;
        writes.* = 0;
        read_at.* = 0;
        write_at.* = 0;
        var idx: u32 = 0;
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (dnirInstrReadsValue(ins, true, id)) {
                    reads.* += 1;
                    read_at.* = idx;
                }
                if (ins.op == .store_local and ins.result != null and ins.result.? == id) {
                    writes.* += 1;
                    write_at.* = idx;
                }
                idx += 1;
            }
        }
    }

    /// Does any branch in the function land strictly inside `[lo, hi]`? A fold
    /// that erases instructions must not erase a landing site: every consumed
    /// index collapses onto one code offset, so a branch INTO the window would
    /// arrive somewhere the window never meant.
    fn dnirBranchLandsWithin(f: dnir.Function, lo: u32, hi: u32) bool {
        for (f.blocks) |b| {
            for (b.instrs) |ins| {
                if (ins.op != .br) continue;
                if (ins.branch_target >= lo and ins.branch_target <= hi) return true;
            }
        }
        return false;
    }

    /// Precondition for folding `binop(cmp) -> T ; store_local L <- T ;
    /// br when_x L` into the same `cmp; b.cond` the unnamed form gets.
    ///
    /// Admissible only when, over the WHOLE function: `T`'s single reader is the
    /// naming store, `L` is written exactly once (by that store) and read
    /// exactly once (by this branch), and nothing branches into the two
    /// instructions being erased. Then the stored boolean is dead the instant it
    /// is written, and the name has no observer left to disagree with the flags.
    ///
    /// Where it stops: a binding read anywhere else — later in the body, on
    /// another path, across a loop back edge — keeps its store, because the
    /// value is then genuinely live and erasing it is the miscompile this repo
    /// has already shipped once. `L`'s frame slot is still reserved either way,
    /// so the frame layout does not move.
    fn namedCompareBranchFusible(
        self: *const Arm64Compiler,
        f: dnir.Function,
        cmp_ins: dnir.Instr,
        st: dnir.Instr,
        br: dnir.Instr,
        flat_idx: u32,
    ) bool {
        if (cmp_ins.op != .binop) return false;
        if (comparisonCondition(cmp_ins.binop) == null) return false;
        if (cmp_ins.ty == .f64) return false;
        if (cmp_ins.application != null or cmp_ins.relation != null or cmp_ins.value != null) return false;
        if (self.cur_func_float) return false;
        if (self.valueIsFp(cmp_ins.lhs) or self.valueIsFp(cmp_ins.rhs)) return false;
        const t = cmp_ins.result orelse return false;

        if (st.op != .store_local) return false;
        if (st.ty == .f64) return false;
        // The naming store carries no application lineage of its own to lose.
        if (st.application != null or st.relation != null or st.value != null) return false;
        if (st.lhs != .temp or st.lhs.temp != t) return false;
        const l = st.result orelse return false;

        if (br.op != .br) return false;
        switch (br.branch_condition) {
            .when_true, .when_false => {},
            .unconditional => return false,
        }
        if (br.lhs != .local or br.lhs.local != l) return false;

        // The comparison result's only reader is the naming store.
        const last = self.value_free_at.get(t) orelse return false;
        if (last != flat_idx + 1) return false;

        var reads: u32 = 0;
        var writes: u32 = 0;
        var read_at: u32 = 0;
        var write_at: u32 = 0;
        dnirLocalUseCensus(f, l, &reads, &writes, &read_at, &write_at);
        if (reads != 1 or writes != 1) return false;
        if (read_at != flat_idx + 2 or write_at != flat_idx + 1) return false;

        if (dnirBranchLandsWithin(f, flat_idx + 1, flat_idx + 2)) return false;
        return true;
    }

    // ------------------------------------------------------------------
    // W7 — IF-CONVERSION.
    //
    // A one-sided `if` whose whole body assigns one pure value to one binding
    // is a SELECT, and AArch64 has had the instruction all along: `csel`
    // appears nowhere in this backend, yet `encodeCset` is already the same
    // conditional-select family with `Rn`/`Rm` pinned to `xzr`.
    //
    // Measured worth, `docs/ftc.md` W7 written both ways by hand with identical
    // answers over 0/1/7/1001/65535: 2.15x CYCLES on an unpredictable branch,
    // where the instruction count barely moves. The whole difference is
    // mispredicts — IPC doubles from 1.00 to 2.03.
    //
    // ADMISSION RULE, and it has two independent halves.
    //
    // SOUNDNESS. If-conversion executes the arm that the branch would have
    // skipped, so anything the arm can do on a path it never took becomes real.
    // Admitted: exactly one integer ALU `binop` from a closed whitelist —
    // add, sub, mul, and, or, xor, shl, shr, and the six comparisons — feeding
    // exactly one `store_local` of a scalar local. Everything else is refused,
    // and the refusals are the point:
    //   - `div`/`mod`: division is THE trapping arithmetic. This backend's
    //     `sdiv` happens not to fault on zero today, which is precisely why it
    //     must be excluded — the exclusion has to survive a future divide check.
    //   - `load_index`/`store_index`: bounds-checked, and a check that fails
    //     ends in `brk`. An out-of-range index in an untaken arm would become a
    //     crash that did not exist.
    //   - `load_field`/`store_field`/`str_len`/`alloc_slots`: memory that may
    //     not be there on the untaken path.
    //   - `call_direct`/`call_extern`/`print_value`/`hw_*`: effects, and a call
    //     clobbers the flags between the compare and the select.
    //   - f64 anywhere: `fcsel` is a different encoding and is not emitted here.
    // The one store the arm does perform is made safe rather than forbidden:
    // the select feeds it the binding's OWN CURRENT VALUE when the condition is
    // false, so the write-back is a no-op on the path that used to skip it.
    //
    // PROFITABILITY, and it is a real boundary, not a formality. Converting
    // pays for the arm on every iteration and saves a mispredict only when the
    // branch is unpredictable. With the arm capped at ONE ALU op the trade is
    // bounded on both sides: at most +3 executed instructions when the branch
    // was never taken (~0.6 cycles at this stream's measured IPC of 4.74),
    // against ~13 cycles per mispredict avoided. Break-even is a misprediction
    // rate near 5%, so the conversion loses only on a branch predicted better
    // than ~95% — and there it loses less than a cycle. A LONGER arm has no
    // such bound: its cost grows with its length while the saving stays capped
    // at one mispredict, which is why the cap is the rule and not a tuning knob.
    // Idol has no edge-probability fact (`ApplicationFact.authority` is still
    // unpopulated), so a profile-driven widening is a separate decision that
    // needs a fact this compiler does not yet have.
    // ------------------------------------------------------------------

    const IfConvPlan = struct {
        /// Comparison feeding the branch, when it is fusible into `cmp`.
        cmp: ?dnir.Instr,
        /// The conditional branch itself.
        br: dnir.Instr,
        /// The arm's single ALU operation.
        op: dnir.Instr,
        /// The arm's terminating `store_local`.
        store: dnir.Instr,
        /// DNIR instructions consumed AFTER the one the driver is holding.
        extra: u32,
    };

    fn ifConvArmOpAdmissible(self: *const Arm64Compiler, ins: dnir.Instr) bool {
        if (ins.op != .binop) return false;
        if (ins.ty == .f64 or self.cur_func_float) return false;
        if (self.valueIsFp(ins.lhs) or self.valueIsFp(ins.rhs)) return false;
        if (ins.application != null or ins.relation != null or ins.value != null) return false;
        if (ins.result == null) return false;
        return switch (ins.binop) {
            .add, .sub, .mul, .band, .bor, .bxor, .shl, .shr => true,
            .eq, .neq, .lt, .gt, .leq, .geq => true,
            // Division is the trapping one. See the admission rule above.
            .div, .mod => false,
        };
    }

    /// Recognize `br when_x C -> J ; <one ALU op> ; store_local L ;
    /// br unconditional -> J` with `J` the instruction just past the window.
    ///
    /// `at` is the flat index of `body[0]`; `body` is the remainder of the
    /// current block starting there. Returns the plan, or null.
    fn ifConversionArm(
        self: *const Arm64Compiler,
        f: dnir.Function,
        body: []const dnir.Instr,
        at: u32,
        cmp: ?dnir.Instr,
        consumed_before: u32,
    ) ?IfConvPlan {
        if (body.len < 4) return null;
        const br = body[0];
        if (br.op != .br) return null;
        switch (br.branch_condition) {
            .when_true, .when_false => {},
            .unconditional => return null,
        }
        const op = body[1];
        if (!self.ifConvArmOpAdmissible(op)) return null;
        const st = body[2];
        if (st.op != .store_local) return null;
        if (st.ty == .f64) return null;
        if (st.application != null or st.relation != null or st.value != null) return null;
        const t = op.result.?;
        if (st.lhs != .temp or st.lhs.temp != t) return null;
        const l = st.result orelse return null;
        if (self.valueIsFp(.{ .local = l }) or self.valueIsFp(.{ .temp = t })) return null;
        const join = body[3];
        if (join.op != .br or join.branch_condition != .unconditional) return null;

        // The join must be the instruction immediately past the window, and the
        // conditional branch must go to the SAME place — otherwise there is an
        // `else` arm this shape does not model.
        const join_idx = at + 4;
        if (join.branch_target != join_idx) return null;
        if (br.branch_target != join_idx) return null;

        // The arm's value has no reader outside the arm.
        const last = self.value_free_at.get(t) orelse return null;
        if (last != at + 2) return null;

        // Nothing may branch into the arm.
        if (dnirBranchLandsWithin(f, at + 1, at + 3)) return null;

        return .{ .cmp = cmp, .br = br, .op = op, .store = st, .extra = consumed_before + 3 };
    }

    /// Emit the `csel` form of a recognized one-sided `if`.
    ///
    /// Emission ORDER is load-bearing. The flags are set last before the select
    /// because the arm's own operation may write them (`emitCompareResult` is
    /// `cmp` + `cset`), and the binding's old value is read first because a
    /// reload between the compare and the select would be the same hazard. What
    /// is left between `cmp` and `csel` is at most an `ldr` from
    /// `ensureRegLive`, which does not touch NZCV.
    fn emitIfConverted(
        self: *Arm64Compiler,
        temps: *std.AutoHashMapUnmanaged(u32, u5),
        pinned: *std.AutoHashMapUnmanaged(u32, u5),
        plan: IfConvPlan,
        branch_patches: *std.ArrayList(DnirBranchPatch),
    ) Error!void {
        const l = plan.store.result.?;
        const t = plan.op.result.?;

        // (1) The binding's current value — the arm's "else".
        const old = try self.evalDnirValue(temps, .{ .local = l });

        // (2) The arm's operation, now unconditional. An accumulator update
        //     (`a = a + k`) READS the same binding the select falls back to, so
        //     that operand reuses the register already loaded rather than
        //     emitting a second `ldr` of the same frame slot — which is what the
        //     first version of this emitter did, and it is the redundant-reload
        //     class this document measures at 8.9% of the program elsewhere.
        const lhs_is_dest = plan.op.lhs == .local and plan.op.lhs.local == l;
        const rhs_is_dest = plan.op.rhs == .local and plan.op.rhs.local == l;
        const a = if (lhs_is_dest) old else try self.evalDnirValue(temps, plan.op.lhs);
        const b = if (rhs_is_dest) old else try self.evalDnirValue(temps, plan.op.rhs);
        const dst = try self.allocRegExcluding(old);
        try self.emitCompareOrBinop(dst, a, b, plan.op.binop);
        if (a != old and !Arm64Compiler.regIsPinned(pinned, a)) self.releaseReg(a);
        if (b != old and !Arm64Compiler.regIsPinned(pinned, b)) self.releaseReg(b);

        // (3) The condition. Nothing below this line may write the flags.
        var arm_cond: Condition = undefined;
        if (plan.cmp) |c| {
            const clhs = try self.evalDnirValue(temps, c.lhs);
            const crhs = try self.evalDnirValue(temps, c.rhs);
            try self.emitCmpReg(clhs, crhs);
            if (clhs != old and clhs != dst and !Arm64Compiler.regIsPinned(pinned, clhs)) self.releaseReg(clhs);
            if (crhs != old and crhs != dst and !Arm64Compiler.regIsPinned(pinned, crhs)) self.releaseReg(crhs);
            arm_cond = comparisonCondition(c.binop).?;
        } else {
            const cr = try self.evalDnirValue(temps, plan.br.lhs);
            try self.emitCmpZero(cr);
            if (cr != old and cr != dst and !Arm64Compiler.regIsPinned(pinned, cr)) self.releaseReg(cr);
            arm_cond = .ne;
        }
        // `when_false -> join` skips the arm when the condition is FALSE, so the
        // arm runs ON the condition; `when_true -> join` is its mirror.
        if (plan.br.branch_condition == .when_true) arm_cond = invertCondition(arm_cond);

        // (4) The select, in place of the branch.
        try self.emitCselReg(dst, dst, old, arm_cond);
        if (old != dst and !Arm64Compiler.regIsPinned(pinned, old)) self.releaseReg(old);

        // (5) The write-back, through the ordinary `store_local` path so that a
        //     register-homed local and a frame-homed one stay exactly as they
        //     were — this fold changes WHAT is stored, never WHERE.
        try temps.put(self.alloc, t, dst);
        if (dst >= 9 and dst < 29 and dst != platform_reserved_reg and !self.gp_home_regs[dst]) {
            self.gp_reg_owner[dst] = t;
        }
        try self.compileDnirInstr(temps, pinned, plan.store, branch_patches);
    }

    /// Peephole precondition for folding `mul -> T ; add(T, c) -> D` into a
    /// single `madd D, a, b, c` (a*b + c). Admissible only when the product is a
    /// pure integer `mul` whose result feeds the immediately following pure
    /// integer `add` as exactly one operand and has no other reader — so the
    /// intermediate register the fold erases held nothing else. `add` is
    /// commutative, so either operand may be the product; `sub` is intentionally
    /// excluded (only `c - a*b` maps to `msub`, not `a*b - c`).
    fn mulAddFusible(self: *const Arm64Compiler, ins: dnir.Instr, nx: dnir.Instr, flat_idx: u32) bool {
        if (ins.op != .binop or ins.binop != .mul) return false;
        if (ins.ty == .f64 or self.cur_func_float) return false;
        if (self.valueIsFp(ins.lhs) or self.valueIsFp(ins.rhs)) return false;
        if (ins.application != null or ins.relation != null or ins.value != null) return false;
        const t = ins.result orelse return false;
        if (nx.op != .binop or nx.binop != .add) return false;
        if (nx.ty == .f64) return false;
        if (nx.application != null or nx.relation != null or nx.value != null) return false;
        if (self.valueIsFp(nx.lhs) or self.valueIsFp(nx.rhs)) return false;
        if (nx.result == null) return false;
        const lhs_is_t = nx.lhs == .temp and nx.lhs.temp == t;
        const rhs_is_t = nx.rhs == .temp and nx.rhs.temp == t;
        if (lhs_is_t == rhs_is_t) return false; // both or neither — not a clean accumulate
        // The product may have exactly one reader: this add. A widened
        // (loop-crossing) or second-consumer range keeps the last use past the
        // add, and the conservative answer is to materialize the product.
        const last = self.value_free_at.get(t) orelse return false;
        return last == flat_idx + 1;
    }

    /// Emit the fused `madd` for a `mulAddFusible` pair and record the sum's
    /// register ownership (the product temp is never materialized).
    fn emitFusedMulAdd(
        self: *Arm64Compiler,
        temps: *std.AutoHashMapUnmanaged(u32, u5),
        pinned: *const std.AutoHashMapUnmanaged(u32, u5),
        ins: dnir.Instr,
        nx: dnir.Instr,
    ) Error!void {
        const t = ins.result.?;
        const a = try self.evalDnirValue(temps, ins.lhs);
        const b = try self.evalDnirValue(temps, ins.rhs);
        const acc_val = if (nx.lhs == .temp and nx.lhs.temp == t) nx.rhs else nx.lhs;
        const c = try self.evalDnirValue(temps, acc_val);
        const dst = try self.allocReg();
        try self.emitMaddReg(dst, a, b, c);
        if (!Arm64Compiler.regIsPinned(pinned, a)) self.releaseReg(a);
        if (!Arm64Compiler.regIsPinned(pinned, b)) self.releaseReg(b);
        if (!Arm64Compiler.regIsPinned(pinned, c)) self.releaseReg(c);
        const d = nx.result.?;
        try temps.put(self.alloc, d, dst);
        if (dst >= 9 and dst < 29 and dst != platform_reserved_reg and !self.gp_home_regs[dst]) {
            self.gp_reg_owner[dst] = d;
        }
    }

    /// Emit the fused `cmp; b.cond` for a `compareBranchFusible` pair. `when_true`
    /// branches on the comparison condition; `when_false` branches on its
    /// inverse (the branch is taken when the boolean would have been zero).
    fn emitFusedCompareBranch(
        self: *Arm64Compiler,
        temps: *std.AutoHashMapUnmanaged(u32, u5),
        pinned: *const std.AutoHashMapUnmanaged(u32, u5),
        ins: dnir.Instr,
        nx: dnir.Instr,
        branch_patches: *std.ArrayList(DnirBranchPatch),
    ) Error!void {
        const lhs = try self.evalDnirValue(temps, ins.lhs);
        const rhs = try self.evalDnirValue(temps, ins.rhs);
        try self.emitCmpReg(lhs, rhs);
        if (!Arm64Compiler.regIsPinned(pinned, lhs)) self.releaseReg(lhs);
        if (!Arm64Compiler.regIsPinned(pinned, rhs)) self.releaseReg(rhs);
        const cond = comparisonCondition(ins.binop).?;
        const arm: Condition = if (nx.branch_condition == .when_true) cond else invertCondition(cond);
        const patch_off = try self.emitBCond(arm, 0);
        try branch_patches.append(self.alloc, .{ .patch_off = patch_off, .target_instr = nx.branch_target, .is_cond = true });
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

    /// `madd xd, xn, xm, xa` = xa + xn*xm. Same 3-source encoding as `msub`
    /// with bit 15 clear. Fuses a `mul` feeding an `add` (FTCFTW debt (2)).
    fn emitMaddReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5, acc: u5) Error!void {
        try self.ensureRegLive(lhs);
        try self.ensureRegLive(rhs);
        try self.ensureRegLive(acc);
        try self.emitFmt(0x9b000000 | (@as(u32, rhs) << 16) | (@as(u32, acc) << 10) | (@as(u32, lhs) << 5) | @as(u32, dst), "madd x{d}, x{d}, x{d}, x{d}", .{ dst, lhs, rhs, acc });
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
    /// `examples/mandelbrot.id` compile and then HANG, producing no output,
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

fn comparisonCondition(op: dnir.BinOpTag) ?Condition {
    return switch (op) {
        .eq => .eq,
        .neq => .ne,
        .lt => .lt,
        .gt => .gt,
        .leq => .le,
        .geq => .ge,
        else => null,
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
        .hi => .ls,
        .ls => .hi,
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

/// `CSEL Xd, Xn, Xm, cond` — `Xd = cond ? Xn : Xm`, no branch.
///
/// Same conditional-select family as `CSET` above and one bit away from it:
/// `CSINC` sets bit 10, `CSEL` clears it. `0x9A800000 | Rm<<16 | cond<<12 |
/// Rn<<5 | Rd`, and `encodeCset`'s own literal `0x9a9f07e0` is this base with
/// `Rm = Rn = 31`, bit 10 set — which is the cross-check the unit test below
/// runs rather than trusting either constant on its own.
///
/// The condition field must start at zero here for exactly the reason recorded
/// above `encodeCset`: a pre-set bit ORs into the condition and corrupts every
/// condition whose encoding has that bit clear.
fn encodeCsel(dst: u5, n: u5, m: u5, cond: Condition) u32 {
    const CSEL_BASE: u32 = 0x9a800000;
    return CSEL_BASE | (@as(u32, m) << 16) |
        (@as(u32, @intFromEnum(cond)) << 12) | (@as(u32, n) << 5) | @as(u32, dst);
}

fn conditionName(cond: Condition) []const u8 {
    return switch (cond) {
        .eq => "eq",
        .ne => "ne",
        .lt => "lt",
        .ge => "ge",
        .gt => "gt",
        .le => "le",
        .hi => "hi",
        .ls => "ls",
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

fn nextMachineInstructionCoordinate(current: u32, diagnostic: *Diagnostic) Error!u32 {
    return std.math.add(u32, current, 1) catch
        return recordRefusalWith(
            diagnostic,
            @src(),
            "machine-instruction-coordinate-capacity",
        );
}

/// Foreign calls emitted by bootstrap lowering in `dnir_lower.zig` without
/// graph application facts (GAP-155). Validation admits only this closed set
/// when lineage is absent; every other bare `call_extern` stays unlawful.
fn isBootstrapForeignCall(callee: []const u8) bool {
    return dnir.isBootstrapForeignCall(callee);
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
                const next_instruction_index = try nextMachineInstructionCoordinate(
                    instruction_index,
                    diagnostic,
                );
                defer instruction_index = next_instruction_index;
                if (instruction.application) |application_id| {
                    diagnostic.application = application_id;
                }
                const fact_count: u2 = @as(u2, @intFromBool(instruction.relation != null)) +
                    @as(u2, @intFromBool(instruction.application != null)) +
                    @as(u2, @intFromBool(instruction.value != null));
                if (fact_count == 0) {
                    if (instruction.subject != null or instruction.realization_start != null) {
                        return invalidFactsWith(diagnostic, @src(), "orphan-realization-lineage");
                    }
                    if (instruction.op == .call_direct) {
                        var module_local = false;
                        for (module.functions) |local_fn| {
                            if (std.mem.eql(u8, local_fn.name, instruction.callee)) {
                                module_local = true;
                                break;
                            }
                        }
                        if (module_local) continue;
                        return invalidFactsWith(diagnostic, @src(), "missing-application-lineage");
                    }
                    if (instruction.op == .call_extern) {
                        if (isBootstrapForeignCall(instruction.callee)) continue;
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
                const caller = graph.applicationCaller(application.application) orelse
                    return invalidFactsWith(diagnostic, @src(), "application-caller-mismatch");
                if (function.id == null or !std.meta.eql(function.id.?, caller)) {
                    return invalidFactsWith(diagnostic, @src(), "application-caller-mismatch");
                }
                const descriptor = graph.applicationDescriptor(application.application) orelse
                    return invalidFactsWith(diagnostic, @src(), "application-fact-mismatch");
                const relation = graph.applicationRelation(application.application) orelse
                    return invalidFactsWith(diagnostic, @src(), "application-fact-mismatch");
                if (!std.meta.eql(application.application, instruction.application.?) or
                    !std.meta.eql(relation, instruction.relation.?) or
                    !std.meta.eql(result, instruction.value.?) or
                    !optionalIdEql(graph.applicationSubject(application.application), instruction.subject) or
                    !descriptor.eql(instruction.ty))
                {
                    return invalidFactsWith(diagnostic, @src(), "application-fact-mismatch");
                }
                const target_id = instruction.target orelse
                    return invalidFactsWith(diagnostic, @src(), "missing-application-target");
                if (!std.meta.eql(target_id, relation)) {
                    return invalidFactsWith(diagnostic, @src(), "application-target-mismatch");
                }
                const target = targets.get(target_id) orelse
                    return invalidFactsWith(diagnostic, @src(), "missing-application-target");
                if (!std.meta.eql(target.id, target_id)) {
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

    var expected: usize = 0;
    for (applications) |application| {
        if (!graph.isBootstrapApplicationNode(application.application)) expected += 1;
    }
    if (seen.count() != expected) return invalidFactsWith(diagnostic, @src(), "application-realization-count");
}

fn validateMachineLineage(
    alloc: std.mem.Allocator,
    output: Arm64Output,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error!void {
    if (output.graph != graph) return invalidFactsWith(diagnostic, @src(), "machine-graph-context");
    const applications = try checkedApplications(graph, diagnostic);
    var expected: usize = 0;
    for (applications) |application| {
        if (!graph.isBootstrapApplicationNode(application.application)) expected += 1;
    }
    if (output.lineage.len == 0 and expected == 0) return;
    if (output.lineage.len != expected) {
        return invalidFactsWith(diagnostic, @src(), "machine-lineage-count");
    }
    var seen: std.AutoHashMapUnmanaged(semantic_graph.id, void) = .empty;
    defer seen.deinit(alloc);
    for (output.lineage) |lineage| {
        const application = graph.application(lineage.application) orelse
            return invalidFactsWith(diagnostic, @src(), "machine-lineage-unknown");
        const result = try applicationResult(graph, application.*, diagnostic);
        const descriptor = graph.applicationDescriptor(application.application) orelse
            return invalidFactsWith(diagnostic, @src(), "machine-lineage-mismatch");
        const caller = graph.applicationCaller(application.application) orelse
            return invalidFactsWith(diagnostic, @src(), "machine-lineage-mismatch");
        const relation = graph.applicationRelation(application.application) orelse
            return invalidFactsWith(diagnostic, @src(), "machine-lineage-mismatch");
        if (!std.meta.eql(lineage.application, application.application) or
            !std.meta.eql(lineage.relation, relation) or
            !std.meta.eql(lineage.target, relation) or
            !std.meta.eql(lineage.value, result) or
            !optionalIdEql(lineage.subject, graph.applicationSubject(application.application)) or
            !lineage.descriptor.eql(descriptor) or
            !std.meta.eql(lineage.caller, caller))
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
    if (seen.count() != expected) return invalidFactsWith(diagnostic, @src(), "machine-lineage-count");
}

/// DNIR in, machine code out, with NO source facts in hand.
///
/// Nothing is promoted to `__TEXT,__const` on this path — a determined table
/// needs the source-level precondition from `table_facts.zig`, and a caller
/// holding only DNIR cannot supply it. That is a deliberate absence, not an
/// oversight: it keeps every oracle test below measuring the emission it was
/// written against.
fn emitArm64FromDnir(alloc: std.mem.Allocator, m: dnir.Module, entry: ?[]const u8, diagnostic: *Diagnostic) Error!Arm64Output {
    return emitArm64FromDnirLicensed(alloc, m, entry, diagnostic, null);
}

fn emitArm64FromDnirLicensed(
    alloc: std.mem.Allocator,
    m: dnir.Module,
    entry: ?[]const u8,
    diagnostic: *Diagnostic,
    licence: ?*const const_table.Licence,
) Error!Arm64Output {
    var records = try collectF64RecordsFromDnir(alloc, m);
    defer freeF64Records(alloc, &records);
    var scal_records = try collectScalRecordsFromDnir(alloc, m);
    defer freeScalRecords(alloc, &scal_records);
    var compiler = Arm64Compiler{
        .alloc = alloc,
        .diagnostic = diagnostic,
        .f64_records = &records,
        .scal_records = &scal_records,
        .entry = entry,
        .const_licence = licence,
    };
    if (m.graph) |graph| {
        if (graph.gateTransportModule()) {
            compiler.gate_transport = true;
            compiler.gp_local_home_budget = 32;
        }
    }
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
    try std.testing.expect(scalRecordDesc(&scalars, "Scalar").?.field_names.ptr == scalar_fields[0..].ptr);
    try std.testing.expect(f64RecordDesc(&floats, "Float").?.field_names.ptr == float_fields[0..].ptr);
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
    entry: ?[]const u8,
    graph: *const semantic_graph.SemanticGraph,
    diagnostic: *Diagnostic,
) Error!Arm64Output {
    if (!graph.gateTransportModule()) {
        _ = try checkedApplications(graph, diagnostic);
    }
    if (!graph.gateTransportModule()) {
        if (graph.firstUnresolvedApplicationExcludingBootstrap(null)) |occurrence| {
            diagnostic.bindOccurrence(graph, occurrence);
            return invalidFactsWith(diagnostic, @src(), "unresolved-application-facts");
        }
    }

    // WHICH TABLES THE SOURCE PERMITS TO BECOME DATA. Computed here, from the
    // AST, because `table_facts.zig` answers over a function body and this is the
    // last place that has one. The DNIR carries no binding names, so the backend
    // could not ask this question for itself.
    var licence = try const_table.licenceForModule(alloc, mod);
    defer licence.deinit();

    const lowered_result = dnir_lower.lowerModuleWithGraphObserved(alloc, mod, graph, &diagnostic.lowering);
    if (lowered_result) |lowered| {
        defer dnir.deinitModule(alloc, lowered);
        if (!graph.gateTransportModule()) {
            try validateDnirApplications(alloc, lowered, graph, diagnostic);
        }
        if (dnir.moduleIsNativeDirectReady(lowered) or graph.gateTransportModule()) {
            var output = try emitArm64FromDnirLicensed(alloc, lowered, entry, diagnostic, &licence);
            errdefer output.deinit(alloc);
            output.graph = graph;
            if (!graph.gateTransportModule()) {
                try validateMachineLineage(alloc, output, graph, diagnostic);
            }
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
            error.GraphFactsInvalid => blk: {
                if (diagnostic.application == null) diagnostic.application = diagnostic.lowering.application;
                break :blk invalidFactsWith(
                    diagnostic,
                    @src(),
                    diagnostic.lowering.note() orelse "graph-dnir-facts",
                );
            },
            error.UnsupportedConstruct => blk: {
                if (diagnostic.application == null) diagnostic.application = diagnostic.lowering.application;
                break :blk recordRefusalWith(
                    diagnostic,
                    @src(),
                    diagnostic.lowering.note() orelse "graph-dnir-unsupported",
                );
            },
        };
    }
}

fn machOTextOffset(cstring_len: usize, const_len: usize, bss_size: u64) usize {
    const header_size: usize = 32;
    const segment_size: usize = 72;
    const section_size: usize = 80;
    const symtab_size: usize = 24;
    const build_version_size: usize = 24;
    const nsects: usize = 1 +
        (if (cstring_len > 0) @as(usize, 1) else 0) +
        (if (const_len > 0) @as(usize, 1) else 0) +
        (if (bss_size > 0) @as(usize, 1) else 0);
    return header_size + segment_size + section_size * nsects + symtab_size + build_version_size;
}

/// The object writer at its established arity. Emits no `__TEXT,__const`, which
/// is exactly what a module with no promoted table needs — kept so every DNIR-
/// only caller and every oracle test below reads the same bytes it always did.
fn emitMachOArm64Object(alloc: std.mem.Allocator, text: []const u8, cstring: []const u8, symbols: []const Symbol, relocations: []const Relocation, bss_size: u64) Error![]u8 {
    return emitMachOArm64ObjectWithConst(alloc, text, cstring, &.{}, symbols, relocations, bss_size);
}

fn emitMachOArm64ObjectWithConst(
    alloc: std.mem.Allocator,
    text: []const u8,
    cstring: []const u8,
    const_data: []const u8,
    symbols: []const Symbol,
    relocations: []const Relocation,
    bss_size: u64,
) Error![]u8 {
    const segment_size: usize = 72;
    const section_size: usize = 80;
    const symtab_size: usize = 24;
    const build_version_size: usize = 24;
    const has_cstring = cstring.len > 0;
    // `__TEXT,__const` is S_REGULAR read-only data with its own section index.
    //
    // NEITHER OF THE TWO OBVIOUS PLACES WOULD DO. `__cstring` is
    // S_CSTRING_LITERALS — ld splits and dedups its contents at NUL bytes, and a
    // table of i64 literals is mostly NUL bytes, so a blob put there is silently
    // rearranged. `__text` would be counted as INSTRUCTIONS by `otool -tV`,
    // which is the measurement every gate and baseline on this surface is stated
    // in; moving data there would corrupt the numbers rather than improve them.
    const has_const = const_data.len > 0;
    // `__DATA,__bss` is S_ZEROFILL: it has a VM size but NO file bytes, so it
    // adds one section header and leaves every file offset below untouched.
    // That is what makes a writable arena affordable here.
    const has_bss = bss_size > 0;
    const nsects: u32 = 1 +
        (if (has_cstring) @as(u32, 1) else 0) +
        (if (has_const) @as(u32, 1) else 0) +
        (if (has_bss) @as(u32, 1) else 0);
    const sizeofcmds = segment_size + section_size * nsects + symtab_size + build_version_size;
    const text_offset = machOTextOffset(cstring.len, const_data.len, bss_size);
    const reloff: usize = text_offset + text.len;
    const after_relocs: usize = reloff + relocations.len * 8;
    const cstring_fileoff: usize = after_relocs;
    const after_cstring: usize = if (has_cstring) cstring_fileoff + cstring.len else after_relocs;
    // 8-byte aligned in the FILE as well as in the VM layout: every element is an
    // 8-byte word and the access path is `ldr x, [base, idx, lsl #3]`.
    const const_fileoff: usize = alignForward(after_cstring, 8);
    const after_const: usize = if (has_const) const_fileoff + const_data.len else after_cstring;
    const symoff: usize = alignForward(after_const, 8);
    const stroff: usize = symoff + symbols.len * 16;
    const strtab = try buildStringTable(alloc, symbols);
    defer alloc.free(strtab);

    // The VM addresses the defined local symbols were measured against in
    // `Arm64Compiler.finish`. Both sides compute this the same way — sections in
    // emission order, `__const` rounded up to 8 — because a symbol's n_value and
    // its section's addr must agree or ld resolves the relocation to the wrong
    // word.
    const cstring_addr: usize = text.len;
    const const_addr: usize = alignForward(text.len + cstring.len, 8);
    const bss_addr: usize = if (has_const) const_addr + const_data.len else text.len + cstring.len;

    // Relocation entries live in the file between __text and __cstring but not
    // in the VM layout. llvm-objdump and ld reject LC_SEGMENT_64 when filesize >
    // vmsize, which large gate modules hit once adrp/add relocations accumulate.
    const segment_filesize = symoff - text_offset;
    const segment_vmsize = @max(bss_addr + bss_size, segment_filesize);

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
    try appendU64(&out, alloc, segment_vmsize); // vmsize
    try appendU64(&out, alloc, text_offset); // fileoff
    try appendU64(&out, alloc, segment_filesize); // filesize: section data + their relocations
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
        try appendU64(&out, alloc, cstring_addr); // addr (immediately after __text in VM)
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

    // __TEXT,__const (determined positional tables, as read-only data)
    if (has_const) {
        try appendName16(&out, alloc, "__const");
        try appendName16(&out, alloc, "__TEXT");
        try appendU64(&out, alloc, const_addr); // addr
        try appendU64(&out, alloc, const_data.len); // size
        try appendU32(&out, alloc, @intCast(const_fileoff)); // offset
        try appendU32(&out, alloc, 3); // align (2^3 = 8)
        try appendU32(&out, alloc, 0); // reloff — the data holds no addresses
        try appendU32(&out, alloc, 0); // nreloc
        // S_REGULAR, and NO instruction attributes. `__text` carries
        // S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS above; a section
        // without them is data to every disassembler, which is what keeps
        // `otool -tV` counting instructions and not table elements.
        try appendU32(&out, alloc, 0x0);
        try appendU32(&out, alloc, 0);
        try appendU32(&out, alloc, 0);
        try appendU32(&out, alloc, 0);
    }

    // __DATA,__bss (zerofill arena — writable storage for string ops)
    if (has_bss) {
        try appendName16(&out, alloc, "__bss");
        try appendName16(&out, alloc, "__DATA");
        try appendU64(&out, alloc, bss_addr); // addr (after the __TEXT sections)
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
    if (has_const) {
        if (const_fileoff > out.items.len) try appendZeroes(&out, alloc, const_fileoff - out.items.len);
        try out.appendSlice(alloc, const_data);
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
        if (function.id != null and std.meta.eql(function.id.?, lineage.target)) {
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

/// Graph lift has a PRECONDITION: the module has been canonicalized by
/// `table_apply`, so that every lawful spelling of a world projection is the one
/// node the recognizers look for. `os.args(1)` and `os.env("PATH")` parse as
/// `.call`; the projection recognizers in `dnir_lower` only fire on `.index`.
///
/// This was driver-only (`main.zig`), so tests that build their own
/// parse -> check -> lift pipeline skipped it and asserted against an AST no
/// user ever compiles. Demagix (`a[i]` canonicalizes to `a(i)`) then rewrote
/// two fixtures into the spelling only the driver could resolve, and the tests
/// failed for a reason that had nothing to do with what they were testing.
/// Normalizing here keeps the precondition attached to the stage that needs it.
fn liftCheckedTestGraph(
    module: *ast.Module,
    checked: *const Sema,
    graph: *semantic_graph.SemanticGraph,
) !void {
    table_apply.normalizeModule(checked.alloc, module, &checked.type_map);
    _ = try graph.liftModuleWithCheckedCalls(module, checked, module.file);
}

fn emitCheckedTestAssembly(
    alloc: std.mem.Allocator,
    module: *const ast.Module,
    graph: *semantic_graph.SemanticGraph,
    entry: ?[]const u8,
) !AssemblyWithLineage {
    var diagnostic: Diagnostic = .{};
    if (entry) |name| {
        return emitAssemblyForExecutableWithGraphLineageObserved(
            alloc,
            module,
            name,
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
    module: *ast.Module,
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
    const primary = expected_lowering orelse expected;
    try std.testing.expectEqualStrings(primary, diagnostic.note().?);
    if (std.mem.eql(u8, expected, "unresolved-application-facts") or
        std.mem.eql(u8, primary, "unresolved-application-facts"))
    {
        try std.testing.expect(diagnostic.application != null);
    }
    if (expected_lowering) |note| {
        try std.testing.expectEqualStrings(note, diagnostic.lowering.note().?);
    } else {
        try std.testing.expect(diagnostic.lowering.note() == null);
    }
}

fn expectCheckedTestPhysicalRefusal(
    alloc: std.mem.Allocator,
    module: *ast.Module,
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
    if (diagnostic.lowering.note()) |note| {
        try std.testing.expectEqualStrings(note, diagnostic.note().?);
    } else {
        try std.testing.expectEqualStrings(expected, diagnostic.note().?);
    }
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
    parser.idol_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
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
    parser.idol_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
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
    var lexer = Lexer.init(source, "machine-lineage.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&module, &checked, "machine-lineage.id");
    const applications = try checkedApplications(&graph, &diagnostic);
    try std.testing.expectEqual(@as(usize, 1), applications.len);
    try std.testing.expect(graph.applicationSubject(applications[0].application) != null);

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
    try std.testing.expectEqual(graph.applicationCaller(applications[0].application).?, dnir_caller.?);
    try std.testing.expect(std.meta.eql(graph.applicationSubject(applications[0].application).?, dnir_subject.?));

    var output = try emitArm64ModuleWithGraph(alloc, &module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 1), output.lineage.len);
    const text_lineage = output.lineage[0];
    try std.testing.expectEqual(graph.applicationRelation(applications[0].application).?, text_lineage.relation);
    try std.testing.expectEqual(applications[0].application, text_lineage.application);
    try std.testing.expectEqual(try applicationResult(&graph, applications[0], &diagnostic), text_lineage.value);
    try std.testing.expect(std.meta.eql(graph.applicationSubject(applications[0].application).?, text_lineage.subject.?));
    try std.testing.expect(graph.applicationDescriptor(applications[0].application).?.eql(text_lineage.descriptor));
    try std.testing.expectEqual(graph.applicationCaller(applications[0].application).?, text_lineage.caller);
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
    output.lineage[0].descriptor = graph.applicationDescriptor(applications[0].application).?;

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
    var lexer = Lexer.init(source, "missing-lineage.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&ast_module);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "missing-lineage.id");
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
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
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
    parser.idol_mode = true;
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
    parser.idol_mode = true;
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
    try std.testing.expect(diagnostic.application != null);
    try std.testing.expectEqualStrings("observe", diagnostic.relation.?);
}

test "native backend: stdout write is bootstrap egress not unresolved print" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\stdout:write("hi")
    ;
    var lexer = Lexer.init(source, "egress.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&module, &checked, &graph);
    try std.testing.expectEqual(@as(usize, 0), graph.unresolvedApplicationCountExcludingBootstrap(null));
    var output = try emitArm64ModuleWithGraph(alloc, &module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(output.text.len != 0);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "bl _puts") != null);
}

test "native backend: stdin read is bootstrap ingress not unresolved" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\stdin:read()
    ;
    var lexer = Lexer.init(source, "ingress.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&module, &checked, &graph);
    try std.testing.expectEqual(@as(usize, 0), graph.unresolvedApplicationCountExcludingBootstrap(null));
    var output = try emitArm64ModuleWithGraph(alloc, &module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(output.text.len != 0);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "bl _idol_io_read_stdin") != null);
}

test "native backend: shc application example is source to machine" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const source = try std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        "examples/shc/application.id",
        alloc,
        .unlimited,
    );
    defer alloc.free(source);
    var lexer = Lexer.init(source, "examples/shc/application.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&module, &checked, &graph);
    try std.testing.expectEqual(@as(usize, 0), graph.unresolvedApplicationCountExcludingBootstrap(null));
    const applications = try checkedApplications(&graph, &diagnostic);
    try std.testing.expectEqual(@as(usize, 1), applications.len);
    const fact = applications[0];
    try std.testing.expectEqualStrings("read", graph.get(graph.applicationRelation(fact.application).?).?.name.?);
    try std.testing.expect(graph.applicationSubject(fact.application) != null);

    const projected = try dnir_lower.lowerModuleWithGraph(alloc, &module, &graph);
    var dnir_application: ?semantic_graph.id = null;
    var dnir_subject: ?semantic_graph.id = null;
    var dnir_caller: ?semantic_graph.id = null;
    for (projected.functions) |function| {
        for (function.blocks) |block| {
            for (block.instrs) |instruction| {
                if (instruction.application == null) continue;
                dnir_application = instruction.application;
                dnir_subject = instruction.subject;
                dnir_caller = function.id;
            }
        }
    }
    try std.testing.expectEqual(fact.application, dnir_application.?);
    try std.testing.expect(std.meta.eql(graph.applicationSubject(fact.application).?, dnir_subject.?));
    try std.testing.expectEqual(graph.applicationCaller(fact.application).?, dnir_caller.?);

    var output = try emitArm64ModuleWithGraph(alloc, &module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try validateMachineLineage(alloc, output, &graph, &diagnostic);
    try std.testing.expectEqual(@as(usize, 1), output.lineage.len);
    const text_lineage = output.lineage[0];
    try std.testing.expectEqual(graph.applicationRelation(fact.application).?, text_lineage.relation);
    try std.testing.expectEqual(fact.application, text_lineage.application);
    try std.testing.expectEqual(try applicationResult(&graph, fact, &diagnostic), text_lineage.value);
    try std.testing.expect(std.meta.eql(graph.applicationSubject(fact.application).?, text_lineage.subject.?));
    try std.testing.expectEqual(graph.applicationCaller(fact.application).?, text_lineage.caller);
    try expectLineageCallTarget(alloc, output, projected, text_lineage);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "bl _read") != null);

    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return;
    var artifact = try emitObjectWithGraphLineage(alloc, &module, "native-object", &graph);
    defer artifact.deinit(alloc);
    try std.testing.expect(artifact.graph == &graph);
    try std.testing.expectEqual(@as(usize, 1), artifact.lineage.len);
    const object_lineage = artifact.lineage[0];
    try std.testing.expectEqual(text_lineage.relation, object_lineage.relation);
    try std.testing.expectEqual(text_lineage.application, object_lineage.application);
    try std.testing.expectEqual(text_lineage.value, object_lineage.value);
    try std.testing.expect(std.meta.eql(text_lineage.subject.?, object_lineage.subject.?));
    try std.testing.expectEqual(text_lineage.caller, object_lineage.caller);
    try std.testing.expectEqualSlices(
        u8,
        output.text[text_lineage.text_start..text_lineage.text_end],
        artifact.bytes[object_lineage.object_start..object_lineage.object_end],
    );
    try std.testing.expectEqual(@as(usize, 0), artifact.need.len);
}

test "native backend: shc bind example keeps the helper off the process" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const source = try std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        "examples/shc/bind.id",
        alloc,
        .unlimited,
    );
    defer alloc.free(source);
    var lexer = Lexer.init(source, "examples/shc/bind.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    try std.testing.expect(module.program());
    try std.testing.expectEqualStrings("main", abi(&module, null).?);
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&module, &checked, &graph);
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return;
    var artifact = try emitObjectWithGraphLineage(alloc, &module, "native-object", &graph);
    defer artifact.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 0), artifact.need.len);
}

test "native backend: shc write example is egress not exit" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const source = try std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        "examples/shc/write.id",
        alloc,
        .unlimited,
    );
    defer alloc.free(source);
    var lexer = Lexer.init(source, "examples/shc/write.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&module, &checked, &graph);
    try std.testing.expectEqual(@as(usize, 0), graph.unresolvedApplicationCountExcludingBootstrap(null));
    var output = try emitArm64ModuleWithGraph(alloc, &module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "bl _puts") != null);
    try std.testing.expectEqualStrings("main", abi(&module, null).?);
}

test "native backend: shc read example is ingress not exit" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const source = try std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        "examples/shc/read.id",
        alloc,
        .unlimited,
    );
    defer alloc.free(source);
    var lexer = Lexer.init(source, "examples/shc/read.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&module, &checked, &graph);
    try std.testing.expectEqual(@as(usize, 0), graph.unresolvedApplicationCountExcludingBootstrap(null));
    var output = try emitArm64ModuleWithGraph(alloc, &module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "bl _idol_io_read_stdin") != null);
    try std.testing.expectEqualStrings("main", abi(&module, null).?);
}

test "native backend: shc arg example is root argv not a call" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const source = try std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        "examples/shc/arg.id",
        alloc,
        .unlimited,
    );
    defer alloc.free(source);
    var lexer = Lexer.init(source, "examples/shc/arg.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&module, &checked, &graph);
    try std.testing.expectEqual(@as(usize, 0), graph.unresolvedApplicationCountExcludingBootstrap(null));
    var output = try emitArm64ModuleWithGraph(alloc, &module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "bl _idol_os_arg") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "bl _puts") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "b.eq") != null);
    try std.testing.expectEqualStrings("main", abi(&module, null).?);
}

test "native backend: shc env example is root table not getenv call" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const source = try std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        "examples/shc/env.id",
        alloc,
        .unlimited,
    );
    defer alloc.free(source);
    var lexer = Lexer.init(source, "examples/shc/env.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&module, &checked, &graph);
    try std.testing.expectEqual(@as(usize, 0), graph.unresolvedApplicationCountExcludingBootstrap(null));
    var output = try emitArm64ModuleWithGraph(alloc, &module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "bl _getenv") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "bl _puts") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "b.eq") != null);
    try std.testing.expectEqualStrings("main", abi(&module, null).?);
}

test "native backend: shc cwd example is root directory not getcwd call" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const source = try std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        "examples/shc/cwd.id",
        alloc,
        .unlimited,
    );
    defer alloc.free(source);
    var lexer = Lexer.init(source, "examples/shc/cwd.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&module, &checked, &graph);
    try std.testing.expectEqual(@as(usize, 0), graph.unresolvedApplicationCountExcludingBootstrap(null));
    var output = try emitArm64ModuleWithGraph(alloc, &module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "bl _idol_os_cwd") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "bl _getcwd") == null);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "bl _puts") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "b.eq") != null);
    try std.testing.expectEqualStrings("main", abi(&module, null).?);
}

test "native backend: shc compose example is ingress to egress not status" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const source = try std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        "examples/shc/compose.id",
        alloc,
        .unlimited,
    );
    defer alloc.free(source);
    var lexer = Lexer.init(source, "examples/shc/compose.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&module, &checked, &graph);
    try std.testing.expectEqual(@as(usize, 0), graph.unresolvedApplicationCountExcludingBootstrap(null));
    var output = try emitArm64ModuleWithGraph(alloc, &module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "bl _idol_io_read_stdin") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "bl _puts") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "b.eq") != null);
    try std.testing.expectEqualStrings("main", abi(&module, null).?);
}

test "native backend: shc path example is subject read not a pointer" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const source = try std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        "examples/shc/path.id",
        alloc,
        .unlimited,
    );
    defer alloc.free(source);
    var lexer = Lexer.init(source, "examples/shc/path.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&module, &checked, &graph);
    try std.testing.expectEqual(@as(usize, 0), graph.unresolvedApplicationCountExcludingBootstrap(null));
    var output = try emitArm64ModuleWithGraph(alloc, &module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "bl _idol_io_read_path") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "bl _puts") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "b.eq") != null);
    try std.testing.expectEqualStrings("main", abi(&module, null).?);
}

test "native backend: character walk uses at not a slice malloc" {
    var diagnostic: Diagnostic = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\w: bool = (code: str)
        \\    t = ""
        \\    n = code:len()
        \\    i = 1
        \\    while i <= n
        \\        c = code:sub(i, i)
        \\        if c != " "
        \\            t = "{t}{c}"
        \\        i += 1
        \\    t == "end"
        \\
        \\go: i64 = ()
        \\    if w("    end")
        \\        return 0
        \\    1
        \\
        \\go()
    ;
    var lexer = Lexer.init(source, "examples/shc/char.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&module, &checked, &graph);
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return;
    var output = try emitArm64ModuleWithGraph(alloc, &module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "bl _idol_str_at") != null);
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
    parser.idol_mode = true;
    var module = try parser.parse_module();

    // This resident graph deliberately has no declaration fact for `main`.
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try std.testing.expectEqual(@as(usize, 0), graph.unresolvedApplicationCount(null));

    try std.testing.expectError(
        error.SemanticFactsInvalid,
        emitArm64ModuleWithGraph(alloc, &module, null, &graph, &diagnostic),
    );
    const missing = diagnostic.lowering.note() orelse "graph-dnir-facts";
    try std.testing.expectEqualStrings(missing, diagnostic.note().?);
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
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
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

test "native backend: machine instruction coordinate capacity stays physical" {
    var diagnostic: Diagnostic = .{};
    try std.testing.expectEqual(
        std.math.maxInt(u32),
        try nextMachineInstructionCoordinate(std.math.maxInt(u32) - 1, &diagnostic),
    );
    try std.testing.expectError(
        error.UnsupportedProgram,
        nextMachineInstructionCoordinate(std.math.maxInt(u32), &diagnostic),
    );
    try std.testing.expectEqualStrings(
        "machine-instruction-coordinate-capacity",
        diagnostic.note().?,
    );
}

test "native backend: checked graph preserves physical native entry" {
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
    parser.idol_mode = true;
    var module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
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

test "native backend: DNB011 names application missing fact consumer producer" {
    var diagnostic: Diagnostic = .{};
    diagnostic.application = 8127;
    try std.testing.expect(invalidFactsWith(&diagnostic, @src(), "platform-output-witness") == error.SemanticFactsInvalid);
    var buf: [256]u8 = undefined;
    const msg = formatDirectCause(error.SemanticFactsInvalid, "native-object", &buf, &diagnostic);
    try std.testing.expectEqualStrings(
        "DNB011 application: 8127 missing: platform-output-witness consumer: native realization producer: graph",
        msg,
    );
    diagnostic.relation = "write";
    const named = formatDirectCause(error.SemanticFactsInvalid, "native-object", &buf, &diagnostic);
    try std.testing.expectEqualStrings(
        "DNB011 application: 8127 relation: write missing: platform-output-witness consumer: native realization producer: graph",
        named,
    );
    const opaque_msg = formatDirectError(error.SemanticFactsInvalid, "native-object", &buf);
    try std.testing.expect(std.mem.indexOf(u8, opaque_msg, "application: unknown") != null);
    try std.testing.expect(std.mem.indexOf(u8, opaque_msg, "missing: unspecified") != null);

    var wrapped: Diagnostic = .{};
    wrapped.application = 3;
    try std.testing.expect(invalidFactsWith(&wrapped, @src(), "graph-dnir-facts") == error.SemanticFactsInvalid);
    const fact = "missing-application-id";
    @memcpy(wrapped.lowering.note_buffer[0..fact.len], fact);
    wrapped.lowering.note_len = fact.len;
    wrapped.lowering.application = 3;
    const promoted = formatDirectCause(error.SemanticFactsInvalid, "native-object", &buf, &wrapped);
    try std.testing.expectEqualStrings(
        "DNB011 application: 3 missing: missing-application-id consumer: native realization producer: graph",
        promoted,
    );
}

test "native backend: caller diagnostics are isolated and observed attempts reset" {
    var first: Diagnostic = .{};
    var second: Diagnostic = .{};

    try std.testing.expect(invalidFactsWith(&second, @src(), "second-attempt-facts") == error.SemanticFactsInvalid);
    try std.testing.expectEqualStrings("second-attempt-facts", second.note().?);

    first.lowering.site = @src();
    first.lowering.note_buffer[0] = 'x';
    first.lowering.note_len = 1;
    var lexer = Lexer.init("", "diagnostic-reset.id");
    var parser = Parser.init(&lexer, std.testing.allocator);
    parser.idol_mode = true;
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
    try std.testing.expectEqualStrings("second-attempt-facts", second.note().?);
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
    parser.idol_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&ast_module);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "ordinary-lineage.id");
    const applications = try checkedApplications(&graph, &diagnostic);
    try std.testing.expectEqual(@as(usize, 2), applications.len);
    try std.testing.expect(std.meta.eql(
        graph.applicationRelation(applications[0].application).?,
        graph.applicationRelation(applications[1].application).?,
    ));
    try std.testing.expect(!std.meta.eql(applications[0].application, applications[1].application));
    try std.testing.expect(!std.meta.eql(
        try applicationResult(&graph, applications[0], &diagnostic),
        try applicationResult(&graph, applications[1], &diagnostic),
    ));
    try std.testing.expectEqual(@as(?semantic_graph.id, null), graph.applicationSubject(applications[0].application));
    try std.testing.expectEqual(@as(?semantic_graph.id, null), graph.applicationSubject(applications[1].application));

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
            const span = graph.applicationProvenance(application.application) orelse
                return error.TestExpectedEqual;
            try std.testing.expectEqualStrings("ordinary-lineage.id", span.file);
            try std.testing.expect(span.start < span.end);
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
    var lexer = Lexer.init(source, "record-lineage.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "record-lineage.id");
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
    try std.testing.expect(instruction.ty.eql(graph.applicationDescriptor(applications[0].application).?));

    const regions = try region_graph.buildModuleRegions(alloc, module);
    defer region_graph.freeModuleRegions(alloc, regions);
    try region_graph.validateModuleRegions(alloc, regions, &graph, module);

    var output = try emitArm64ModuleWithGraph(alloc, &ast_module, null, &graph, &diagnostic);
    defer output.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 1), output.lineage.len);
    try std.testing.expect(std.meta.eql(output.lineage[0].application, applications[0].application));
    try std.testing.expect(output.lineage[0].descriptor.eql(graph.applicationDescriptor(applications[0].application).?));
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
    var lexer = Lexer.init(source, "record-f64-refusal.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "record-f64-refusal.id");

    try std.testing.expectError(
        error.SemanticFactsInvalid,
        emitArm64ModuleWithGraph(alloc, &ast_module, null, &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("application-result-abi", diagnostic.note().?);
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
    var lexer = Lexer.init(source, "callee-mismatch.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "callee-mismatch.id");
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
        if (std.meta.eql(id, graph.applicationRelation(applications[0].application).?)) {
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
    try std.testing.expectEqualStrings("missing-application-target", diagnostic.note().?);
    selected.id = selected_id;

    instruction.callee = "impostor";
    try std.testing.expect(std.meta.eql(graph.applicationRelation(applications[0].application).?, relation_before));
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
    var lexer = Lexer.init(source, "call-abi.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "call-abi.id");
    const applications = try checkedApplications(&graph, &diagnostic);
    try std.testing.expectEqual(@as(usize, 1), applications.len);
    try std.testing.expect(graph.applicationDescriptor(applications[0].application).?.eql(.f64));

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
    var lexer = Lexer.init(source, "nested-lineage.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "nested-lineage.id");
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
    var lexer = Lexer.init(source, "nested-f64-lineage.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "nested-f64-lineage.id");
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
    var lexer = Lexer.init(source, "discarded-calls.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&ast_module);
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "discarded-calls.id");
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
    , "pass4_native_milestone.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.idol_mode = true;
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
    , "run.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.idol_mode = true;
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
    , "entry.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const mod = try parser.parse_module();
    try std.testing.expectEqualStrings("entry", abi(&mod, null).?);

    var lex2 = Lexer.init(
        \\run(): i64
        \\    42
        \\end
    , "sole.id");
    var parser2 = Parser.init(&lex2, alloc);
    parser2.idol_mode = true;
    const mod2 = try parser2.parse_module();
    try std.testing.expectEqualStrings("run", abi(&mod2, null).?);

    var lex3 = Lexer.init(
        \\a(): i64
        \\    1
        \\end
        \\b(): i64
        \\    2
        \\end
    , "ambiguous.id");
    var parser3 = Parser.init(&lex3, alloc);
    parser3.idol_mode = true;
    const mod3 = try parser3.parse_module();
    try std.testing.expect(abi(&mod3, null) == null);

    var lex4 = Lexer.init(
        \\a(): i64
        \\    1
        \\end
        \\b(): i64
        \\    2
        \\end
    , "override.id");
    var parser4 = Parser.init(&lex4, alloc);
    parser4.idol_mode = true;
    const mod4 = try parser4.parse_module();
    try std.testing.expectEqualStrings("b", abi(&mod4, "b").?);
    try std.testing.expect(abi(&mod4, "missing") == null);

    var lex5 = Lexer.init(
        \\run(): f64
        \\    42.0
        \\end
    , "f64_entry.id");
    var parser5 = Parser.init(&lex5, alloc);
    parser5.idol_mode = true;
    const mod5 = try parser5.parse_module();
    try std.testing.expectEqualStrings("run", abi(&mod5, null).?);
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
    , "libshaped.id");
    var parser_lib = Parser.init(&lex_lib, alloc);
    parser_lib.idol_mode = true;
    const mod_lib = try parser_lib.parse_module();
    try std.testing.expectEqualStrings("w", abi(&mod_lib, null).?);

    // Same sole function, but the file-scope statements ARE the program.
    var lex_script = Lexer.init(
        \\w(): i64
        \\    42
        \\end
        \\print("before")
        \\print(w())
    , "script.id");
    var parser_script = Parser.init(&lex_script, alloc);
    parser_script.idol_mode = true;
    const mod_script = try parser_script.parse_module();
    try std.testing.expectEqualStrings("main", abi(&mod_script, null).?);

    // A DECLARED entry still wins over the body — `main` is deliberate.
    var lex_main = Lexer.init(
        \\main(): i64
        \\    0
        \\end
        \\print("side effect")
    , "declared_main.id");
    var parser_main = Parser.init(&lex_main, alloc);
    parser_main.idol_mode = true;
    const mod_main = try parser_main.parse_module();
    try std.testing.expectEqualStrings("main", abi(&mod_main, null).?);

    var lex_keep = Lexer.init(
        \\main: i64 = ()
        \\    7
        \\0
    , "keep.id");
    var parser_keep = Parser.init(&lex_keep, alloc);
    parser_keep.idol_mode = true;
    const mod_keep = try parser_keep.parse_module();
    try std.testing.expectEqualStrings("main", abi(&mod_keep, null).?);

    // As does an explicit --entry override.
    try std.testing.expectEqualStrings("w", abi(&mod_script, "w").?);
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
    , "f64_run.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.idol_mode = true;
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
    , "pass4_native_milestone.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.idol_mode = true;
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
    , "native.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
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
    var lex = Lexer.init(source, "pass11_record_proof.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.idol_mode = true;
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
        \\    x += y * 8
        \\    x - 1
        \\end
    , "native.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
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
    , "native.id");
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
    , "math_add_multi.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.idol_mode = true;
    try sem.check_module(&mod);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&mod, &sem, "math_add_multi.id");
    try std.testing.expectEqual(@as(usize, 0), graph.applications().len);
    try std.testing.expectEqual(@as(usize, 1), graph.unresolvedApplicationCount(null));

    var diagnostic: Diagnostic = .{};
    try std.testing.expectError(
        error.SemanticFactsInvalid,
        emitAssemblyWithGraphLineageObserved(alloc, &mod, "native-asm", &graph, &diagnostic),
    );
    try std.testing.expectEqualStrings("unresolved-application-facts", diagnostic.note().?);
    try std.testing.expect(diagnostic.application != null);
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

// Regression: a two-argument call whose BOTH operands are prior call results
// must stage the two arguments from DISTINCT source registers. The mov_arg
// ownership recorder once read `result` (a PHYSICAL ABI slot 0/1 for mov_arg) as
// a value id; slot 1 aliased temp id 1, so staging the second argument rebound
// and then freed the first result's live register, and both `mov x0`/`mov x1`
// read the same clobbered register — `add2(id(a), id(b))` collapsed to
// `add2(v, v)`. Two callees keep the results out of x0 so the collision, if it
// returns, shows up as one shared source register here.
test "native backend stages two call-result arguments from distinct registers" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    const id_params = [_]dnir.Param{.{ .name = "x", .ty = .i64 }};
    const g_params = [_]dnir.Param{
        .{ .name = "a", .ty = .i64 },
        .{ .name = "b", .ty = .i64 },
    };
    const id_instructions = [_]dnir.Instr{
        .{ .op = .ret, .lhs = .{ .temp = 0 }, .ty = .i64 },
    };
    const g_instructions = [_]dnir.Instr{
        .{ .op = .binop, .result = 2, .lhs = .{ .temp = 0 }, .rhs = .{ .temp = 1 }, .binop = .add, .ty = .i64 },
        .{ .op = .ret, .lhs = .{ .temp = 2 }, .ty = .i64 },
    };
    const main_instructions = [_]dnir.Instr{
        .{ .op = .@"const", .result = 0, .lhs = .{ .i64 = 5 }, .ty = .i64 },
        .{ .op = .@"const", .result = 1, .lhs = .{ .i64 = 7 }, .ty = .i64 },
        .{ .op = .mov_arg, .result = 0, .lhs = .{ .temp = 0 }, .ty = .i64 },
        .{ .op = .call_direct, .result = 2, .callee = "id", .ty = .i64 },
        .{ .op = .mov_arg, .result = 0, .lhs = .{ .temp = 1 }, .ty = .i64 },
        .{ .op = .call_direct, .result = 3, .callee = "id", .ty = .i64 },
        .{ .op = .mov_arg, .result = 0, .lhs = .{ .temp = 2 }, .ty = .i64 },
        .{ .op = .mov_arg, .result = 1, .lhs = .{ .temp = 3 }, .ty = .i64 },
        .{ .op = .call_direct, .result = 4, .callee = "g", .ty = .i64 },
        .{ .op = .ret, .lhs = .{ .temp = 4 }, .ty = .i64 },
    };
    const id_blocks = [_]dnir.Block{.{ .instrs = &id_instructions }};
    const g_blocks = [_]dnir.Block{.{ .instrs = &g_instructions }};
    const main_blocks = [_]dnir.Block{.{ .instrs = &main_instructions }};
    const functions = [_]dnir.Function{
        .{ .name = "id", .ret = .i64, .params = &id_params, .blocks = &id_blocks },
        .{ .name = "g", .ret = .i64, .params = &g_params, .blocks = &g_blocks },
        .{ .name = "main", .ret = .i64, .blocks = &main_blocks },
    };
    const module = dnir.Module{ .functions = &functions };

    var diagnostic: Diagnostic = .{};
    var output = try emitArm64FromDnir(alloc, module, null, &diagnostic);
    defer output.deinit(alloc);

    const main_start = std.mem.indexOf(u8, output.asm_text, "_main:\n") orelse
        return error.TestExpectedEqual;
    const tail = output.asm_text[main_start..];
    const call_g = std.mem.indexOf(u8, tail, "bl _g") orelse return error.TestExpectedEqual;
    const staging = tail[0..call_g];
    // The final argument staged into x1 must read a register that is not the
    // same one x0's argument was moved from. Find the last `mov x0, xN` and
    // `mov x1, xM` in the staging window and require N != M.
    const x0_at = std.mem.lastIndexOf(u8, staging, "mov x0, x") orelse return error.TestExpectedEqual;
    const x1_at = std.mem.lastIndexOf(u8, staging, "mov x1, x") orelse return error.TestExpectedEqual;
    const x0_src = staging[x0_at + "mov x0, x".len ..];
    const x1_src = staging[x1_at + "mov x1, x".len ..];
    const x0_end = std.mem.indexOfAny(u8, x0_src, "\n ,") orelse x0_src.len;
    const x1_end = std.mem.indexOfAny(u8, x1_src, "\n ,") orelse x1_src.len;
    try std.testing.expect(!std.mem.eql(u8, x0_src[0..x0_end], x1_src[0..x1_end]));
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
    , "to_str_vararg.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.idol_mode = true;
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
        \\pick: i64 = (n: i64)
        \\    out = 0
        \\    if n < 0
        \\        out = 11
        \\    elseif n == 0
        \\        out = 13
        \\    elseif n > 10
        \\        out = 17
        \\    else
        \\        out = 19
        \\    out
        \\
        \\main: i64 = ()
        \\    pick(11)
    , "native.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.idol_mode = true;
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

test "native backend lowers source while with break and continue through checked path" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\sum_to: i64 = (n: i64)
        \\    total = 0
        \\    i = 0
        \\    while i < n
        \\        i += 1
        \\        if i == 3
        \\            continue
        \\        if i > 5
        \\            break
        \\        total += i
        \\    total
        \\
        \\main: i64 = ()
        \\    sum_to(8)
    , "native.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.idol_mode = true;
    try sem.check_module(&mod);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&mod, &sem, &graph);
    var assembly = try emitCheckedTestAssembly(alloc, &mod, &graph, null);
    defer assembly.deinit(alloc);
    const asm_text = assembly.assembly;
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "\tb .Lduo_") != null);
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "b.eq") != null or
        std.mem.indexOf(u8, asm_text, "b.ne") != null);
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "_sum_to") != null);
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
        \\        total += i
        \\    end
        \\    for j = n, 1, -2
        \\        if j < 2
        \\            break
        \\        end
        \\        total += j
        \\    end
        \\    total
        \\end
        \\
        \\main(): i64
        \\    counted(5)
        \\end
    , "native.id");
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
    , "native.id");
    var parser = Parser.init(&lex, alloc);
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    try sem.check_module(&mod);

    try expectCheckedTestSemanticFailure(
        alloc,
        &mod,
        &sem,
        "missing-application-target",
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
    , "native.id");
    var parser = Parser.init(&lex, alloc);
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    try sem.check_module(&mod);

    try expectCheckedTestSemanticFailure(
        alloc,
        &mod,
        &sem,
        "missing-application-target",
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
        \\fun native_add(a: i64, b: i64): i64
        \\    a + b
        \\end
    , "native.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
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
    try std.testing.expect(std.mem.indexOf(u8, object.bytes, "_native_add") != null);
    try std.testing.expect(std.mem.indexOf(u8, object.bytes, "_main") == null);
}

test "native backend lowers scalar-local operand across a call via spill-all-locals" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // `x` and `b` are body locals; `y = id(x)` passes a local operand across a
    // call and `y + b` reuses a local defined before the call. Any body holding a
    // call spills every GP local to the frame (`planGpStackLocals`,
    // gate_spill_all_locals = body_has_call), so the operand load and the
    // post-call reload survive the callee's caller-saved clobber. The lowering is
    // therefore admitted — no operand-ABI refusal is warranted — and the program
    // evaluates to (1+…+20) + 1 = 211.
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
    , "native.id");
    var parser = Parser.init(&lex, alloc);
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
    try std.testing.expect(std.mem.indexOf(u8, object.bytes, "_id") != null);
    try std.testing.expect(std.mem.indexOf(u8, object.bytes, "_main") != null);
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

test "native backend: every DNIR integer binop selects its exact machine operation" {
    const Case = struct {
        op: dnir.BinOpTag,
        assembly: []const u8,
    };
    const cases = [_]Case{
        .{ .op = .add, .assembly = "\tadd x9, x10, x11\n" },
        .{ .op = .sub, .assembly = "\tsub x9, x10, x11\n" },
        .{ .op = .mul, .assembly = "\tmul x9, x10, x11\n" },
        .{ .op = .div, .assembly = "\tsdiv x9, x10, x11\n" },
        .{ .op = .mod, .assembly = "\tsdiv x12, x10, x11\n\tmsub x9, x12, x11, x10\n" },
        .{ .op = .band, .assembly = "\tand x9, x10, x11\n" },
        .{ .op = .bor, .assembly = "\torr x9, x10, x11\n" },
        .{ .op = .bxor, .assembly = "\teor x9, x10, x11\n" },
        .{ .op = .shl, .assembly = "\tlsl x9, x10, x11\n" },
        .{ .op = .shr, .assembly = "\tlsr x9, x10, x11\n" },
        .{ .op = .eq, .assembly = "\tcmp x10, x11\n\tcset x9, eq\n" },
        .{ .op = .neq, .assembly = "\tcmp x10, x11\n\tcset x9, ne\n" },
        .{ .op = .lt, .assembly = "\tcmp x10, x11\n\tcset x9, lt\n" },
        .{ .op = .gt, .assembly = "\tcmp x10, x11\n\tcset x9, gt\n" },
        .{ .op = .leq, .assembly = "\tcmp x10, x11\n\tcset x9, le\n" },
        .{ .op = .geq, .assembly = "\tcmp x10, x11\n\tcset x9, ge\n" },
    };

    for (cases) |case| {
        var diagnostic: Diagnostic = .{};
        var floats: F64RecordMap = .empty;
        var scalars: ScalRecordMap = .empty;
        var compiler: Arm64Compiler = .{
            .alloc = std.testing.allocator,
            .diagnostic = &diagnostic,
            .f64_records = &floats,
            .scal_records = &scalars,
        };
        defer compiler.deinit();
        compiler.used_regs[9] = true;
        compiler.used_regs[10] = true;
        compiler.used_regs[11] = true;
        try compiler.emitCompareOrBinop(9, 10, 11, case.op);
        try std.testing.expectEqualStrings(case.assembly, compiler.asm_text.items);
    }
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

// Same reasoning one instruction over: the listing says `csel` while the object
// file carries the bits, and a `csel` with the condition inverted answers with
// the WRONG ARM every time — a silent wrong answer, not a crash. Decode every
// field back out, and cross-check the base against `encodeCset`'s own literal,
// which is this encoding with Rn = Rm = 31 and the CSINC bit set. Note the
// condition is NOT inverted here: `cset` is `csinc … invert(cond)` precisely
// because it selects between 0 and 1; a general select takes the condition as
// written.
test "native backend: csel encodes dst/n/m and the UNinverted condition" {
    const cases = [_]Condition{ .eq, .ne, .lt, .ge, .gt, .le, .hi, .ls };
    for (cases) |c| {
        const word = encodeCsel(9, 10, 11, c);
        try std.testing.expectEqual(@as(u32, 9), word & 0x1f);
        try std.testing.expectEqual(@as(u32, 10), (word >> 5) & 0x1f);
        try std.testing.expectEqual(@as(u32, 11), (word >> 16) & 0x1f);
        try std.testing.expectEqual(@intFromEnum(c), @as(u4, @truncate(word >> 12)));
        // CSEL clears bit 10; CSINC (which CSET aliases) sets it.
        try std.testing.expectEqual(@as(u32, 0b00), (word >> 10) & 0b11);
        try std.testing.expectEqual(@as(u32, 0x9a800000), word & 0xffe00000);
    }
    // `CSET Xd, cond` IS `CSINC Xd, XZR, XZR, invert(cond)` — build it out of
    // the general encoder and require the two constants to agree, so neither
    // literal can drift on its own.
    for ([_]Condition{ .eq, .ne, .lt, .ge, .gt, .le }) |c| {
        const from_general = encodeCsel(10, 31, 31, conditionForCset(c)) | (1 << 10);
        try std.testing.expectEqual(encodeCset(10, c), from_general);
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
    , "native.id");
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
    , "native.id");
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
    , "native.id");
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

// Source `print` reaches machine code, and it reaches the SAME machine code as
// `stdout:write`.
//
// This test used to assert the opposite — that `print(1)` in an ordinary module
// refused with `unresolved-application-facts` — and that refusal was the single
// largest hole in the direct backend: measured over the 1005 tracked `.id`
// files, 110 programs that `idol check` accepts and the C bootstrap compiles
// were refused by direct naming exactly this one relation. `print(v)` and
// `stdout:write(v)` are one host-egress node (`dnir_lower.lowerPrint`), and the
// only thing separating them was WHERE the file lived. The physical
// `print_value` oracle below is unchanged: it is the DNIR-level control that
// the egress op still lowers to a real libc call.
test "native backend lowers source print to host egress and retains physical print oracle" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\main(): i64
        \\    print(1)
        \\    0
        \\end
    , "native.id");
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
    try std.testing.expect(std.mem.indexOf(u8, assembly.assembly, ".globl _main") != null);
    try std.testing.expect(std.mem.indexOf(u8, assembly.assembly, "bl _printf") != null);

    // The subject-first spelling of the same egress, in a module with the same
    // name, must produce the same call — one node, not two.
    var stream_lex = Lexer.init(
        \\main: i64 = ()
        \\    stdout:write("1")
        \\    0
    , "native.id");
    var stream_parser = Parser.init(&stream_lex, alloc);
    stream_parser.idol_mode = true;
    var stream_mod = try stream_parser.parse_module();
    var stream_sem = Sema.init(alloc);
    defer stream_sem.deinit();
    stream_sem.idol_mode = true;
    try stream_sem.check_module(&stream_mod);
    var stream_graph = semantic_graph.SemanticGraph.init(alloc);
    defer stream_graph.deinit();
    try liftCheckedTestGraph(&stream_mod, &stream_sem, &stream_graph);
    var stream_assembly = try emitCheckedTestAssembly(alloc, &stream_mod, &stream_graph, null);
    defer stream_assembly.deinit(alloc);
    try std.testing.expect(std.mem.indexOf(u8, stream_assembly.assembly, "bl _puts") != null);

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
    , "pass11_record_proof.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.idol_mode = true;
    try sem.check_module(&mod);

    // A record literal (`{ x = 3.0, y = 4.0 }`) passed as an operand cannot cross
    // the scalar application ABI, so the checked-operand law rejects it at the
    // precise site — `application-operand-abi` — before any generic missing-id
    // refusal. Surfacing the operand-shape reason first is strictly more
    // informative than the earlier catch-all `missing-application-id`.
    try expectCheckedTestSemanticFailure(
        alloc,
        &mod,
        &sem,
        "graph-dnir-facts",
        "application-operand-abi",
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
        \\    if b0 != 0 return 1001 end
        \\    if b3 != 0x6D return 1004 end
        \\    0
        \\end
    ;
    var lex = Lexer.init(source, "pass11_wasm_blob_direct.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.idol_mode = true;
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

test "WP-04: i64 record field assign with binop" {
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
    var lex = Lexer.init(source, "field_assign.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.idol_mode = true;
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
        \\    if b0 != 0 return 1001 end
        \\    c.pos = c.pos + 1
        \\    if c.pos != 1 return 1006 end
        \\    0
        \\end
    ;
    var lex = Lexer.init(source, "pass11_wasm_blob_direct.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.idol_mode = true;
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
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.idol_mode = true;
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
    minimal_parser.idol_mode = true;
    var minimal_mod = try minimal_parser.parse_module();
    var minimal_sem = Sema.init(alloc);
    defer minimal_sem.deinit();
    minimal_sem.idol_mode = true;
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

test "native backend spills GP locals past home budget without aliasing owners" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // THE VALUES ARE PARAMETER-DERIVED ON PURPOSE. Every binding used to be
    // `= 1`, and that stopped probing anything the day constant folding reached
    // USED bindings: the whole body collapses to a single immediate, there is
    // nothing left to spill, and `saw_stack_local` is false. The test would then
    // report a failure for a pass WORKING.
    //
    // The neighbouring test at "unused immediate bindings do not demand register
    // or stack places" asserts exactly the opposite for the same 21-binding
    // shape — no `str`, no `ldr`, no `sub sp` — so the two are only telling
    // different stories while one of them is opaque to the folder. Deriving
    // every value from `n` makes this one opaque by construction: the folder
    // cannot know `n`, all 21 stay live to the sum, and register pressure is
    // real rather than notional.
    //
    // This matters more than it looks. The GP home budget was measured at 20
    // against a pool of 19 allocatable registers (x9-x17, x19-x28; x18 is
    // Apple's reserved platform register), and that mismatch stayed invisible
    // for as long as every table-indexing function looked like a caller and
    // spilled everything anyway. A test whose body folds cannot see a
    // register-pressure bug at all.
    const source =
        \\pressure: i64 = (n: i64)
        \\    v0 = n + 1
        \\    v1 = n + 2
        \\    v2 = n + 3
        \\    v3 = n + 4
        \\    v4 = n + 5
        \\    v5 = n + 6
        \\    v6 = n + 7
        \\    v7 = n + 8
        \\    v8 = n + 9
        \\    v9 = n + 10
        \\    v10 = n + 11
        \\    v11 = n + 12
        \\    v12 = n + 13
        \\    v13 = n + 14
        \\    v14 = n + 15
        \\    v15 = n + 16
        \\    v16 = n + 17
        \\    v17 = n + 18
        \\    v18 = n + 19
        \\    v19 = n + 20
        \\    v20 = n + 21
        \\    v0 + v1 + v2 + v3 + v4 + v5 + v6 + v7 + v8 + v9 + v10 + v11 + v12 + v13 + v14 + v15 + v16 + v17 + v18 + v19 + v20
        \\
        \\main: i64 = ()
        \\    pressure(1)
    ;
    var lex = Lexer.init(source, "live-register-pressure.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.idol_mode = true;
    try sem.check_module(&mod);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    try liftCheckedTestGraph(&mod, &sem, &graph);
    var diagnostic: Diagnostic = .{};
    var output = try emitArm64ModuleWithGraph(
        alloc,
        &mod,
        null,
        &graph,
        &diagnostic,
    );
    defer output.deinit(alloc);
    var saw_stack_local = false;
    for (output.cost) |entry| {
        if (entry.kind == .stack_local) saw_stack_local = true;
    }
    try std.testing.expect(saw_stack_local);
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "_main") != null);
    // The body must NOT have folded — if it did, `saw_stack_local` above is
    // measuring nothing and this test has quietly stopped being a test. 21 live
    // parameter-derived values cannot collapse to one immediate, so the relation
    // has to still be emitted.
    try std.testing.expect(std.mem.indexOf(u8, output.asm_text, "pressure") != null);
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
    var lex = Lexer.init(source, "indirect_ret.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.idol_mode = true;
    try sem.check_module(&mod);

    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();
    _ = try graph.liftModuleWithCheckedCalls(&mod, &sem, "indirect_ret.id");
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
    var lex = Lexer.init(source, "explode8.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.idol_mode = true;
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
