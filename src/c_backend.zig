//! Portable C99 realization of graph-observed DNIR.
//!
//! This is an explicit physical output choice. It consumes `native_ir.Module`,
//! owns no semantic facts, and is not reachable from direct or automatic
//! backend selection.
const std = @import("std");
const dnir = @import("native_ir.zig");
const types = @import("types.zig");

const RT = types.ResolvedType;

pub const Error = std.mem.Allocator.Error || std.Io.Writer.Error || error{UnsupportedProgram};

pub const Diagnostic = struct {
    note_buf: [96]u8 = @splat(0),
    note_len: usize = 0,
    fn_buf: [96]u8 = @splat(0),
    fn_len: usize = 0,

    fn reset(self: *Diagnostic) void {
        self.* = .{};
    }

    fn remember(self: *Diagnostic, text: []const u8) void {
        if (self.note_len != 0) return;
        const n = @min(text.len, self.note_buf.len);
        @memcpy(self.note_buf[0..n], text[0..n]);
        self.note_len = n;
    }

    fn rememberFunction(self: *Diagnostic, name: []const u8) void {
        if (self.fn_len != 0) return;
        const n = @min(name.len, self.fn_buf.len);
        @memcpy(self.fn_buf[0..n], name[0..n]);
        self.fn_len = n;
    }

    pub fn note(self: *const Diagnostic) ?[]const u8 {
        return if (self.note_len == 0) null else self.note_buf[0..self.note_len];
    }

    pub fn functionName(self: *const Diagnostic) ?[]const u8 {
        return if (self.fn_len == 0) null else self.fn_buf[0..self.fn_len];
    }
};

const Emitter = struct {
    alloc: std.mem.Allocator,
    module: dnir.Module,
    diagnostic: *Diagnostic,
    out: std.Io.Writer.Allocating,
    current_function: []const u8 = "<module>",

    fn init(alloc: std.mem.Allocator, module: dnir.Module, diagnostic: *Diagnostic) Emitter {
        return .{
            .alloc = alloc,
            .module = module,
            .diagnostic = diagnostic,
            .out = .init(alloc),
        };
    }

    fn deinit(self: *Emitter) void {
        self.out.deinit();
    }

    fn refuse(self: *Emitter, why: []const u8) Error {
        self.diagnostic.remember(why);
        self.diagnostic.rememberFunction(self.current_function);
        return error.UnsupportedProgram;
    }

    fn writer(self: *Emitter) *std.Io.Writer {
        return &self.out.writer;
    }
};

fn scalarType(ty: RT) bool {
    return switch (ty) {
        .i64, .bool => true,
        else => false,
    };
}

fn writeFunctionName(w: *std.Io.Writer, name: []const u8) Error!void {
    try w.writeAll("idol_f_");
    for (name) |byte| try w.print("{x:0>2}", .{byte});
}

fn functionNamed(module: dnir.Module, name: []const u8) ?dnir.Function {
    for (module.functions) |function| {
        if (std.mem.eql(u8, function.name, name)) return function;
    }
    return null;
}

fn functionIndex(module: dnir.Module, name: []const u8) ?usize {
    for (module.functions, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, name)) return index;
    }
    return null;
}

fn markReachable(e: *Emitter, name: []const u8, reachable: []bool) Error!void {
    const index = functionIndex(e.module, name) orelse return e.refuse("call-target-not-in-module");
    if (reachable[index]) return;
    reachable[index] = true;
    const function = e.module.functions[index];
    e.current_function = function.name;
    for (function.blocks) |block| {
        for (block.instrs) |instruction| {
            if (instruction.op == .call_direct) try markReachable(e, instruction.callee, reachable);
        }
    }
}

fn flatInstructionCount(function: dnir.Function) usize {
    var count: usize = 0;
    for (function.blocks) |block| count += block.instrs.len;
    return count;
}

fn bumpSlot(max: *u32, value: dnir.Value) void {
    switch (value) {
        .local, .temp => |slot| max.* = @max(max.*, slot + 1),
        else => {},
    }
}

fn slotCount(function: dnir.Function) u32 {
    var count: u32 = @intCast(function.params.len);
    for (function.blocks) |block| {
        for (block.instrs) |instruction| {
            if (instruction.result) |slot| count = @max(count, slot + 1);
            bumpSlot(&count, instruction.lhs);
            bumpSlot(&count, instruction.rhs);
            bumpSlot(&count, instruction.third);
            for (instruction.vals) |value| bumpSlot(&count, value);
        }
    }
    return count;
}

fn argumentCount(e: *Emitter, function: dnir.Function) Error!u32 {
    var count: u32 = 0;
    for (function.blocks) |block| {
        for (block.instrs) |instruction| switch (instruction.op) {
            .mov_arg => {
                const argument = instruction.result orelse return e.refuse("argument-slot-missing");
                count = @max(count, argument + 1);
            },
            .call_direct => {
                const callee = functionNamed(e.module, instruction.callee) orelse return e.refuse("call-target-not-in-module");
                count = @max(count, @as(u32, @intCast(callee.params.len)));
            },
            else => {},
        };
    }
    if (count > 16) return e.refuse("too-many-call-operands");
    return count;
}

fn emitValue(e: *Emitter, value: dnir.Value) Error!void {
    const w = e.writer();
    switch (value) {
        .i64 => |number| try w.print("idol_bits_i64(UINT64_C(0x{x}))", .{@as(u64, @bitCast(number))}),
        .local, .temp => |slot| try w.print("s{d}", .{slot}),
        else => return e.refuse("value-not-i64"),
    }
}

fn emitWrappedBinary(e: *Emitter, op: []const u8, lhs: dnir.Value, rhs: dnir.Value) Error!void {
    const w = e.writer();
    try w.writeAll("idol_bits_i64(idol_u64(");
    try emitValue(e, lhs);
    try w.print(") {s} idol_u64(", .{op});
    try emitValue(e, rhs);
    try w.writeAll("))");
}

fn emitComparison(e: *Emitter, op: []const u8, lhs: dnir.Value, rhs: dnir.Value) Error!void {
    const w = e.writer();
    try w.writeAll("((int64_t)(");
    try emitValue(e, lhs);
    try w.print(" {s} ", .{op});
    try emitValue(e, rhs);
    try w.writeAll("))");
}

fn emitBinop(e: *Emitter, instruction: dnir.Instr) Error!void {
    switch (instruction.binop) {
        .add => try emitWrappedBinary(e, "+", instruction.lhs, instruction.rhs),
        .sub => try emitWrappedBinary(e, "-", instruction.lhs, instruction.rhs),
        .mul => try emitWrappedBinary(e, "*", instruction.lhs, instruction.rhs),
        .eq => try emitComparison(e, "==", instruction.lhs, instruction.rhs),
        .neq => try emitComparison(e, "!=", instruction.lhs, instruction.rhs),
        .lt => try emitComparison(e, "<", instruction.lhs, instruction.rhs),
        .gt => try emitComparison(e, ">", instruction.lhs, instruction.rhs),
        .leq => try emitComparison(e, "<=", instruction.lhs, instruction.rhs),
        .geq => try emitComparison(e, ">=", instruction.lhs, instruction.rhs),
        else => return e.refuse("binop-not-in-c99-slice"),
    }
}

fn emitPrototype(e: *Emitter, function: dnir.Function) Error!void {
    if (!scalarType(function.ret) or function.ret_pack.len != 0 or function.ret_record != null)
        return e.refuse("result-not-i64");
    const w = e.writer();
    try w.writeAll("static inline int64_t ");
    try writeFunctionName(w, function.name);
    try w.writeByte('(');
    if (function.params.len == 0) {
        try w.writeAll("void");
    } else for (function.params, 0..) |param, i| {
        if (!scalarType(param.ty) or param.record != null) return e.refuse("parameter-not-i64");
        if (i != 0) try w.writeAll(", ");
        try w.print("int64_t s{d}", .{i});
    }
    try w.writeAll(");\n");
}

fn emitCall(e: *Emitter, instruction: dnir.Instr) Error!void {
    const callee = functionNamed(e.module, instruction.callee) orelse return e.refuse("call-target-not-in-module");
    const w = e.writer();
    if (instruction.result) |result| try w.print("s{d} = ", .{result});
    try writeFunctionName(w, callee.name);
    try w.writeByte('(');
    for (callee.params, 0..) |_, index| {
        if (index != 0) try w.writeAll(", ");
        try w.print("a{d}", .{index});
    }
    try w.writeAll(");\n");
}

fn emitInstruction(e: *Emitter, instruction: dnir.Instr, count: usize) Error!void {
    const w = e.writer();
    switch (instruction.op) {
        .@"const", .store_local => {
            const result = instruction.result orelse return e.refuse("result-slot-missing");
            try w.print("  s{d} = ", .{result});
            try emitValue(e, instruction.lhs);
            try w.writeAll(";\n");
        },
        .binop => {
            const result = instruction.result orelse return e.refuse("result-slot-missing");
            try w.print("  s{d} = ", .{result});
            try emitBinop(e, instruction);
            try w.writeAll(";\n");
        },
        .cmp => {
            switch (instruction.binop) {
                .eq, .neq, .lt, .gt, .leq, .geq => {},
                else => return e.refuse("cmp-not-comparison"),
            }
            const result = instruction.result orelse return e.refuse("result-slot-missing");
            try w.print("  s{d} = ", .{result});
            try emitBinop(e, instruction);
            try w.writeAll(";\n");
        },
        .mov_arg => {
            const argument = instruction.result orelse return e.refuse("argument-slot-missing");
            if (argument >= 16) return e.refuse("too-many-call-operands");
            try w.print("  a{d} = ", .{argument});
            try emitValue(e, instruction.lhs);
            try w.writeAll(";\n");
        },
        .call_direct => {
            try w.writeAll("  ");
            try emitCall(e, instruction);
        },
        .br => {
            if (instruction.branch_target > count) return e.refuse("branch-target-out-of-range");
            switch (instruction.branch_condition) {
                .unconditional => {
                    if (instruction.lhs != .void) return e.refuse("unconditional-branch-has-condition");
                    try w.print("  goto L{d};\n", .{instruction.branch_target});
                },
                .when_true, .when_false => {
                    if (instruction.lhs == .void) return e.refuse("conditional-branch-has-no-condition");
                    try w.writeAll("  if (");
                    if (instruction.branch_condition == .when_false) try w.writeByte('!');
                    try emitValue(e, instruction.lhs);
                    try w.print(") goto L{d};\n", .{instruction.branch_target});
                },
            }
        },
        .ret => {
            try w.writeAll("  return ");
            try emitValue(e, instruction.lhs);
            try w.writeAll(";\n");
        },
        else => return e.refuse("operation-not-in-c99-slice"),
    }
}

fn emitFunction(e: *Emitter, function: dnir.Function) Error!void {
    e.current_function = function.name;
    const w = e.writer();
    try w.writeAll("static inline int64_t ");
    try writeFunctionName(w, function.name);
    try w.writeByte('(');
    if (function.params.len == 0) {
        try w.writeAll("void");
    } else for (function.params, 0..) |_, i| {
        if (i != 0) try w.writeAll(", ");
        try w.print("int64_t s{d}", .{i});
    }
    try w.writeAll(") {\n");

    const slots = slotCount(function);
    var slot: u32 = @intCast(function.params.len);
    while (slot < slots) : (slot += 1) try w.print("  int64_t s{d} = 0;\n", .{slot});
    for (0..try argumentCount(e, function)) |argument| try w.print("  int64_t a{d} = 0;\n", .{argument});

    const count = flatInstructionCount(function);
    const labels = try e.alloc.alloc(bool, count + 1);
    defer e.alloc.free(labels);
    @memset(labels, false);
    for (function.blocks) |block| {
        for (block.instrs) |instruction| {
            if (instruction.op != .br) continue;
            if (instruction.branch_target > count) return e.refuse("branch-target-out-of-range");
            labels[instruction.branch_target] = true;
        }
    }
    var index: usize = 0;
    for (function.blocks) |block| {
        for (block.instrs) |instruction| {
            if (labels[index]) try w.print("L{d}:;\n", .{index});
            try emitInstruction(e, instruction, count);
            index += 1;
        }
    }
    if (labels[count]) try w.print("L{d}:;\n", .{count});
    try w.writeAll("  return INT64_C(0);\n}\n\n");
}

pub fn emitSource(
    alloc: std.mem.Allocator,
    module: dnir.Module,
    entry: ?[]const u8,
    diagnostic: *Diagnostic,
) Error![]u8 {
    diagnostic.reset();
    var e = Emitter.init(alloc, module, diagnostic);
    defer e.deinit();
    const reachable = try alloc.alloc(bool, module.functions.len);
    defer alloc.free(reachable);
    if (entry) |name| {
        @memset(reachable, false);
        e.current_function = name;
        try markReachable(&e, name, reachable);
    } else {
        @memset(reachable, true);
    }
    const w = e.writer();
    try w.writeAll(
        \\#include <stdint.h>
        \\#include <string.h>
        \\
        \\#define idol_u64(value) ((uint64_t)(value))
        \\static inline int64_t idol_bits_i64(uint64_t bits) {
        \\  int64_t value;
        \\  memcpy(&value, &bits, sizeof value);
        \\  return value;
        \\}
        \\
    );
    for (module.functions, 0..) |function, index| {
        if (!reachable[index]) continue;
        e.current_function = function.name;
        try emitPrototype(&e, function);
    }
    try w.writeByte('\n');
    for (module.functions, 0..) |function, index| {
        if (reachable[index]) try emitFunction(&e, function);
    }

    if (entry) |name| {
        const function = functionNamed(module, name) orelse return e.refuse("entry-not-in-module");
        if (function.params.len != 0) return e.refuse("entry-has-operands");
        try w.writeAll("int main(void) { return (int)");
        try writeFunctionName(w, function.name);
        try w.writeAll("(); }\n");
    }
    return try alloc.dupe(u8, e.out.written());
}

test "C backend emits i64 calls arithmetic control and return" {
    const instructions = [_]dnir.Instr{
        .{ .op = .mov_arg, .result = 0, .lhs = .{ .i64 = 20 } },
        .{ .op = .call_direct, .result = 0, .callee = "twice" },
        .{ .op = .binop, .result = 1, .binop = .eq, .lhs = .{ .temp = 0 }, .rhs = .{ .i64 = 40 } },
        .{ .op = .br, .lhs = .{ .temp = 1 }, .branch_target = 5, .branch_condition = .when_false },
        .{ .op = .ret, .lhs = .{ .i64 = 42 } },
        .{ .op = .ret, .lhs = .{ .i64 = 1 } },
    };
    const twice_instructions = [_]dnir.Instr{
        .{ .op = .binop, .result = 1, .binop = .mul, .lhs = .{ .local = 0 }, .rhs = .{ .i64 = 2 } },
        .{ .op = .ret, .lhs = .{ .temp = 1 } },
    };
    const params = [_]dnir.Param{.{ .name = "value", .ty = .i64 }};
    const functions = [_]dnir.Function{
        .{ .name = "main", .ret = .i64, .blocks = &.{.{ .instrs = &instructions }} },
        .{ .name = "twice", .ret = .i64, .params = &params, .blocks = &.{.{ .instrs = &twice_instructions }} },
    };
    var diagnostic: Diagnostic = .{};
    const source = try emitSource(std.testing.allocator, .{ .functions = &functions }, "main", &diagnostic);
    defer std.testing.allocator.free(source);
    try std.testing.expect(std.mem.indexOf(u8, source, "lua_Value") == null);
    try std.testing.expect(std.mem.indexOf(u8, source, "goto L5") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "idol_bits_i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "int main(void)") != null);
}

test "C backend refuses damaged operation and control" {
    const damaged_operation = [_]dnir.Instr{
        .{ .op = .hw_spin },
        .{ .op = .ret, .lhs = .{ .i64 = 0 } },
    };
    const damaged_control = [_]dnir.Instr{
        .{ .op = .br, .branch_target = 3 },
        .{ .op = .ret, .lhs = .{ .i64 = 0 } },
    };
    const damaged_cmp = [_]dnir.Instr{
        .{ .op = .cmp, .result = 0, .binop = .add, .lhs = .{ .i64 = 1 }, .rhs = .{ .i64 = 2 } },
        .{ .op = .ret, .lhs = .{ .temp = 0 } },
    };
    var diagnostic: Diagnostic = .{};
    try std.testing.expectError(error.UnsupportedProgram, emitSource(std.testing.allocator, .{
        .functions = &.{.{ .name = "badop", .ret = .i64, .blocks = &.{.{ .instrs = &damaged_operation }} }},
    }, null, &diagnostic));
    try std.testing.expectEqualStrings("operation-not-in-c99-slice", diagnostic.note().?);

    try std.testing.expectError(error.UnsupportedProgram, emitSource(std.testing.allocator, .{
        .functions = &.{.{ .name = "badbr", .ret = .i64, .blocks = &.{.{ .instrs = &damaged_control }} }},
    }, null, &diagnostic));
    try std.testing.expectEqualStrings("branch-target-out-of-range", diagnostic.note().?);

    try std.testing.expectError(error.UnsupportedProgram, emitSource(std.testing.allocator, .{
        .functions = &.{.{ .name = "badcmp", .ret = .i64, .blocks = &.{.{ .instrs = &damaged_cmp }} }},
    }, null, &diagnostic));
    try std.testing.expectEqualStrings("cmp-not-comparison", diagnostic.note().?);
}
