const std = @import("std");
const builtin = @import("builtin");
const ast = @import("ast.zig");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;

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
    if (!isNativeObjectTarget(target)) return error.UnsupportedTarget;
    return emitObjectMode(alloc, mod, false);
}

pub fn emitSharedObjectInput(alloc: std.mem.Allocator, mod: *const ast.Module) Error![]u8 {
    return emitObjectMode(alloc, mod, true);
}

fn emitObjectMode(alloc: std.mem.Allocator, mod: *const ast.Module, allow_no_main: bool) Error![]u8 {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) {
        return error.UnsupportedTarget;
    }

    var output = try emitArm64Module(alloc, mod, allow_no_main);
    defer output.deinit(alloc);
    return emitMachOArm64Object(alloc, output.text, output.cstring, output.symbols, output.relocations);
}

pub fn emitAssembly(alloc: std.mem.Allocator, mod: *const ast.Module, target: []const u8) Error![]u8 {
    if (!isNativeAsmTarget(target)) return error.UnsupportedTarget;
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) {
        return error.UnsupportedTarget;
    }
    const output = try emitArm64Module(alloc, mod, false);
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
    if (!isNativeMachineTarget(target)) return "not a Duo native machine-code target";
    if (builtin.os.tag != .macos) return "first native object writer supports Mach-O on macOS";
    if (builtin.cpu.arch != .aarch64) return "first native object writer supports arm64";
    return "program is outside the current direct object subset";
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

fn collectFunctions(alloc: std.mem.Allocator, mod: *const ast.Module, allow_no_main: bool) Error!NativeModule {
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
    var seen_main = false;
    var seen_export = false;

    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        const fd = &stmt.func_decl;
        if (fd.path.len != 1 or fd.method or fd.is_local) continue;
        if (funcFfiName(fd.attributes)) |ffi_name| {
            if (std.mem.eql(u8, fd.path[0], "main")) return error.InvalidMainSignature;
            try appendUniqueExternal(alloc, &externs, fd.path[0], ffi_name);
            continue;
        }
        try validateFunction(fd, std.mem.eql(u8, fd.path[0], "main"));
        if (std.mem.eql(u8, fd.path[0], "main")) {
            seen_main = true;
        }
        const symbol_name = funcExportName(fd) orelse fd.path[0];
        if (funcExportName(fd) != null) seen_export = true;
        try funcs.append(alloc, .{ .decl = fd, .symbol_name = symbol_name });
    }
    if (!seen_main and !(allow_no_main and seen_export)) return error.MissingMain;
    return .{
        .functions = try funcs.toOwnedSlice(alloc),
        .externs = try externs.toOwnedSlice(alloc),
    };
}

fn validateFunction(fd: *const ast.FuncDecl, is_main: bool) Error!void {
    if (fd.func.vararg or fd.func.vararg_name != null) {
        return error.InvalidMainSignature;
    }
    if (is_main and fd.func.params.len != 0) return error.InvalidMainSignature;
    if (fd.func.params.len > 8) return error.UnsupportedProgram;
    for (fd.func.params) |param| {
        if (param.default_val != null) return error.UnsupportedProgram;
    }
    // main is the integer (exit-code) entry point — floats not allowed there.
    if (is_main) {
        for (fd.func.params) |param| {
            if (!isIntegerAnnotation(param.typ)) return error.InvalidMainSignature;
        }
        if (!returnsInteger(fd.func.ret_type) and !returnsVoid(fd.func.ret_type)) {
            return error.InvalidMainSignature;
        }
        return;
    }
    // non-main: accept a PURE-integer OR a PURE-f64 function (no mixing yet).
    const ret_float = returnsFloat(fd.func.ret_type);
    const ret_int = returnsInteger(fd.func.ret_type);
    if (!ret_int and !ret_float and !returnsVoid(fd.func.ret_type)) {
        return error.InvalidMainSignature;
    }
    for (fd.func.params) |param| {
        if (ret_float) {
            if (!isFloatAnnotation(param.typ)) return error.InvalidMainSignature;
        } else {
            if (!isIntegerAnnotation(param.typ)) return error.InvalidMainSignature;
        }
    }
}

fn isFloatAnnotation(t: ast.TypeExpr) bool {
    return t.is_float(); // named == "f32" or "f64"
}

fn returnsFloat(t: ast.TypeExpr) bool {
    return isFloatAnnotation(t);
}

fn isPureFloatFunction(fd: *const ast.FuncDecl) bool {
    if (!returnsFloat(fd.func.ret_type)) return false;
    for (fd.func.params) |param| {
        if (!isFloatAnnotation(param.typ)) return false;
    }
    return true;
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

const Arm64Compiler = struct {
    alloc: std.mem.Allocator,
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
    fp_locals: std.StringHashMapUnmanaged(u5) = .empty,
    used_fp_regs: [32]bool = @splat(false),

    const CallPatch = struct {
        offset: u32,
        target: []const u8,
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

    fn compileModule(self: *Arm64Compiler, funcs: []const NativeFunction, externs: []const ExternalSymbol) Error!void {
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

    fn compileFunction(self: *Arm64Compiler, func: NativeFunction) Error!void {
        const fd = func.decl;
        self.locals.clearRetainingCapacity();
        self.used_regs = @splat(false);
        self.returned = false;
        self.fp_locals.clearRetainingCapacity();
        self.used_fp_regs = @splat(false);
        self.cur_func_float = false;

        const name = func.symbol_name;
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

        self.cur_func_float = isPureFloatFunction(fd);
        if (self.cur_func_float) {
            // f64 params arrive in d0-d7 (AAPCS); bind names directly to those
            // d-regs and mark them used so FP scratch allocates above them.
            for (fd.func.params, 0..) |param, i| {
                const dreg: u5 = @intCast(i);
                self.used_fp_regs[dreg] = true;
                try self.fp_locals.put(self.alloc, param.name, dreg);
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
        if (!self.returned) return error.UnsupportedProgram;
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

    fn allocReg(self: *Arm64Compiler) Error!u5 {
        var reg: u5 = 9;
        while (reg < 29) : (reg += 1) {
            if (!self.used_regs[reg]) {
                self.used_regs[reg] = true;
                return reg;
            }
        }
        return error.RegisterExhausted;
    }

    fn releaseReg(self: *Arm64Compiler, reg: u5) void {
        if (reg >= 9 and reg < 29 and !self.isLocalReg(reg)) {
            self.used_regs[reg] = false;
        }
    }

    fn bindNewLocalReg(self: *Arm64Compiler, reg: u5) Error!u5 {
        if (!self.isLocalReg(reg)) return reg;
        const owned = try self.allocReg();
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
            try self.emitRet();
            self.returned = true;
            return;
        }
        return error.UnsupportedProgram;
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
                if (!allow_new_locals) return error.UnsupportedProgram;
                if (ld.names.len != ld.inits.len) return error.UnsupportedProgram;
                for (ld.names, 0..) |name, i| {
                    if (!isIntegerAnnotation(name.typ) and name.typ != .inferred) return error.UnsupportedProgram;
                    const reg = try self.compileExpr(ld.inits[i]);
                    const local_reg = try self.bindNewLocalReg(reg);
                    try self.locals.put(self.alloc, name.ident, local_reg);
                }
            },
            .assign => |as| {
                if (as.targets.len != as.values.len) return error.UnsupportedProgram;
                for (as.targets, 0..) |target, i| {
                    if (target.* != .name) return error.UnsupportedProgram;
                    const new_reg = try self.compileExpr(as.values[i]);
                    if (self.locals.get(target.name.ident)) |old_reg| {
                        try self.emitMovReg(old_reg, new_reg);
                        self.releaseReg(new_reg);
                    } else if (!allow_new_locals) {
                        return error.UndefinedName;
                    } else {
                        const local_reg = try self.bindNewLocalReg(new_reg);
                        try self.locals.put(self.alloc, target.name.ident, local_reg);
                    }
                }
            },
            .ret => |ret| {
                if (ret.vals.len == 0) {
                    try self.emitMovImm(0, 0);
                    try self.emitRet();
                    self.returned = true;
                    return;
                }
                if (ret.vals.len != 1) return error.UnsupportedProgram;
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
                if (self.loops.items.len == 0) return error.UnsupportedProgram;
                const loop = self.loops.items[self.loops.items.len - 1];
                const off = try self.emitB(loop.end_label);
                try self.loops.items[self.loops.items.len - 1].break_patches.append(self.alloc, off);
            },
            .cont => {
                if (self.loops.items.len == 0) return error.UnsupportedProgram;
                const loop = self.loops.items[self.loops.items.len - 1];
                const off = try self.emitB(loop.continue_label);
                try self.loops.items[self.loops.items.len - 1].continue_patches.append(self.alloc, off);
            },
            else => return error.UnsupportedProgram,
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
        if (!isIntegerAnnotation(num_for.var_typ) and num_for.var_typ != .inferred) return error.UnsupportedProgram;
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

    fn emitReturnExpr(self: *Arm64Compiler, expr: *const ast.Expr) Error!void {
        if (self.cur_func_float) {
            const d = try self.compileExprFp(expr);
            if (d != 0) try self.emitFmovReg(0, d);
            try self.emitRet();
            self.returned = true;
            return;
        }
        const reg = try self.compileExpr(expr);
        if (reg != 0) try self.emitMovReg(0, reg);
        self.releaseReg(reg);
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
            .binop => |bin| blk: {
                const lhs = try self.compileExprFp(bin.lhs);
                const rhs = try self.compileExprFp(bin.rhs);
                const dst = try self.allocFpReg();
                switch (bin.op) {
                    .add => try self.emitFaddReg(dst, lhs, rhs),
                    .sub => try self.emitFsubReg(dst, lhs, rhs),
                    .mul => try self.emitFmulReg(dst, lhs, rhs),
                    .div, .idiv => try self.emitFdivReg(dst, lhs, rhs),
                    else => return error.UnsupportedProgram,
                }
                break :blk dst;
            },
            else => error.UnsupportedProgram,
        };
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
            .name => |name| self.locals.get(name.ident) orelse error.UndefinedName,
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
                else => error.UnsupportedProgram,
            },
            .binop => |bin| blk: {
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
                    else => return error.UnsupportedProgram,
                }
                self.releaseReg(lhs);
                self.releaseReg(rhs);
                break :blk dst;
            },
            .call => |call| blk: {
                if (call.func.* != .name) return error.UnsupportedProgram;
                if (call.args.len > 8) return error.UnsupportedProgram;
                for (call.args, 0..) |arg, i| {
                    const arg_reg = try self.compileExpr(arg);
                    const abi_reg: u5 = @intCast(i);
                    if (arg_reg != abi_reg) try self.emitMovReg(abi_reg, arg_reg);
                    self.releaseReg(arg_reg);
                }
                const save_set = try self.emitSaveCallerRegs();
                try self.emitBl(call.func.name.ident);
                try self.emitRestoreCallerRegs(save_set);
                const dst = try self.allocReg();
                try self.emitMovReg(dst, 0);
                break :blk dst;
            },
            else => error.UnsupportedProgram,
        };
    }

    fn compileCondition(self: *Arm64Compiler, expr: *const ast.Expr) Error!Condition {
        if (expr.* == .binop and isComparison(expr.binop.op)) {
            const lhs = try self.compileExpr(expr.binop.lhs);
            const rhs = try self.compileExpr(expr.binop.rhs);
            try self.emitCmpReg(lhs, rhs);
            self.releaseReg(lhs);
            self.releaseReg(rhs);
            return conditionForComparison(expr.binop.op);
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
        try self.call_patches.append(self.alloc, .{ .offset = offset, .target = target });
        try self.emitFmt(0x94000000, "bl _{s}", .{target});
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

    fn emitAddReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.emitFmt(0x8b000000 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "add x{d}, x{d}, x{d}", .{ dst, lhs, rhs });
    }

    fn emitSubReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.emitFmt(0xcb000000 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "sub x{d}, x{d}, x{d}", .{ dst, lhs, rhs });
    }

    fn emitCmpReg(self: *Arm64Compiler, lhs: u5, rhs: u5) Error!void {
        try self.emitFmt(0xeb00001f | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5), "cmp x{d}, x{d}", .{ lhs, rhs });
    }

    fn emitCmpZero(self: *Arm64Compiler, reg: u5) Error!void {
        try self.emitFmt(0xf100001f | (@as(u32, reg) << 5), "cmp x{d}, #0", .{reg});
    }

    fn emitCompareResult(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5, cond: Condition) Error!void {
        try self.emitCmpReg(lhs, rhs);
        try self.emitFmt(0x9a9f17e0 | (@as(u32, @intFromEnum(conditionForCset(cond))) << 12) | @as(u32, dst), "cset x{d}, {s}", .{ dst, conditionName(cond) });
    }

    fn emitMulReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.emitFmt(0x9b007c00 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "mul x{d}, x{d}, x{d}", .{ dst, lhs, rhs });
    }

    fn emitSdivReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.emitFmt(0x9ac00c00 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "sdiv x{d}, x{d}, x{d}", .{ dst, lhs, rhs });
    }

    fn emitMsubReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5, acc: u5) Error!void {
        try self.emitFmt(0x9b008000 | (@as(u32, rhs) << 16) | (@as(u32, acc) << 10) | (@as(u32, lhs) << 5) | @as(u32, dst), "msub x{d}, x{d}, x{d}, x{d}", .{ dst, lhs, rhs, acc });
    }

    fn emitAndReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.emitFmt(0x8a000000 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "and x{d}, x{d}, x{d}", .{ dst, lhs, rhs });
    }

    fn emitOrrReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.emitFmt(0xaa000000 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "orr x{d}, x{d}, x{d}", .{ dst, lhs, rhs });
    }

    fn emitEorReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.emitFmt(0xca000000 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "eor x{d}, x{d}, x{d}", .{ dst, lhs, rhs });
    }

    // Variable (register-amount) shifts — Data-processing (2 source), 64-bit.
    // Rm=rhs (shift amount, bits 16-20), Rn=lhs (value, bits 5-9), Rd=dst.
    // Matches the C backend's int64_t << / >> (LSL / arithmetic ASR on arm64).
    fn emitLslReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
        try self.emitFmt(0x9ac02000 | (@as(u32, rhs) << 16) | (@as(u32, lhs) << 5) | @as(u32, dst), "lsl x{d}, x{d}, x{d}", .{ dst, lhs, rhs });
    }

    fn emitAsrReg(self: *Arm64Compiler, dst: u5, lhs: u5, rhs: u5) Error!void {
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
            return error.UnsupportedProgram;
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

fn emitArm64Module(alloc: std.mem.Allocator, mod: *const ast.Module, allow_no_main: bool) Error!Arm64Output {
    var native_mod = try collectFunctions(alloc, mod, allow_no_main);
    defer native_mod.deinit(alloc);
    var compiler = Arm64Compiler{ .alloc = alloc };
    defer compiler.deinit();

    try compiler.compileModule(native_mod.functions, native_mod.externs);
    return compiler.finish();
}

fn emitMachOArm64Object(alloc: std.mem.Allocator, text: []const u8, cstring: []const u8, symbols: []const Symbol, relocations: []const Relocation) Error![]u8 {
    const header_size: usize = 32;
    const segment_size: usize = 72;
    const section_size: usize = 80;
    const symtab_size: usize = 24;
    const build_version_size: usize = 24;
    const has_cstring = cstring.len > 0;
    const nsects: u32 = if (has_cstring) 2 else 1;
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
    try appendU64(&out, alloc, text.len + cstring.len); // vmsize
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
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "\tcmp x") != null);
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "\tb.ge .Lduo_") != null);
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "\tb.ne .Lduo_") != null);

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

    const output = try emitArm64Module(alloc, &mod, false);
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

    const output = try emitArm64Module(alloc, &mod, false);
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

test "native backend emits assembly listing for arithmetic" {
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\main(): i64
        \\    x = 6
        \\    y = 7
        \\    x * y
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

test "native backend rejects unsupported dynamic body" {
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

    try std.testing.expectError(error.UnsupportedProgram, emitObject(alloc, &mod, "native-object"));
}
