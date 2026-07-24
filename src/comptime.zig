const std = @import("std");
const ast = @import("ast.zig");
const term = @import("term.zig");

pub const EvalError = error{
    UnsupportedExpression,
    UnsupportedOperator,
    DivisionByZero,
    StepLimitExceeded,
};

pub const Options = struct {
    step_limit: usize = 100_000,
    alloc: ?std.mem.Allocator = null,
};

pub const Value = union(enum) {
    pub const TableEntry = struct {
        key: ?Value = null,
        name: ?[]const u8 = null,
        val: Value,
    };

    pub const CapturedBinding = struct {
        name: []const u8,
        value: Value,
    };

    pub const Func = struct {
        body: *const ast.FuncBody,
        captures: []const CapturedBinding = &.{},
    };

    unavailable,
    nil,
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,
    table: []const TableEntry,
    func: Func,

    fn truthy(self: Value) bool {
        return switch (self) {
            .nil, .unavailable => false,
            .bool => |v| v,
            else => true,
        };
    }

    fn eql(self: Value, other: Value) bool {
        return switch (self) {
            .unavailable => other == .unavailable,
            .nil => other == .nil,
            .bool => |v| other == .bool and other.bool == v,
            .int => |v| other == .int and other.int == v,
            .float => |v| other == .float and other.float == v,
            .string => |v| other == .string and std.mem.eql(u8, other.string, v),
            .table, .func => false,
        };
    }
};

pub const Bindings = struct {
    scopes: []const std.StringHashMapUnmanaged(Value) = &.{},

    pub fn get(self: Bindings, name: []const u8) ?Value {
        var i = self.scopes.len;
        while (i > 0) {
            i -= 1;
            if (self.scopes[i].get(name)) |value| return value;
        }
        return null;
    }
};

pub const Evaluator = struct {
    const LocalBinding = struct {
        name: []const u8,
        value: Value,
    };

    const BlockResult = union(enum) {
        none,
        value: Value,
    };

    bindings: Bindings = .{},
    options: Options = .{},
    locals: std.ArrayListUnmanaged(LocalBinding) = .empty,
    steps: usize = 0,

    fn step(self: *Evaluator) EvalError!void {
        self.steps += 1;
        if (self.steps > self.options.step_limit) return error.StepLimitExceeded;
    }

    fn lookup(self: *const Evaluator, name: []const u8) ?Value {
        var i = self.locals.items.len;
        while (i > 0) {
            i -= 1;
            const binding = self.locals.items[i];
            if (std.mem.eql(u8, binding.name, name)) return binding.value;
        }
        return self.bindings.get(name);
    }

    fn pushLocal(self: *Evaluator, name: []const u8, value: Value) EvalError!usize {
        const alloc = self.options.alloc orelse return error.UnsupportedExpression;
        const mark = self.locals.items.len;
        self.locals.append(alloc, .{ .name = name, .value = value }) catch return error.UnsupportedExpression;
        return mark;
    }

    fn popLocals(self: *Evaluator, mark: usize) void {
        self.locals.shrinkRetainingCapacity(mark);
    }

    fn setLocal(self: *Evaluator, name: []const u8, value: Value) EvalError!void {
        var i = self.locals.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.locals.items[i].name, name)) {
                self.locals.items[i].value = value;
                return;
            }
        }
        return error.UnsupportedExpression;
    }

    pub fn eval(self: *Evaluator, expr: *const ast.Expr) EvalError!Value {
        try self.step();
        return switch (expr.*) {
            .nil => .nil,
            .true_lit => .{ .bool = true },
            .false_lit => .{ .bool = false },
            .int_lit => |lit| .{ .int = lit.val },
            .float_lit => |lit| .{ .float = lit.val },
            .string_lit => |lit| .{ .string = lit.val },
            .name => |name| blk: {
                const value = self.lookup(name.ident) orelse return error.UnsupportedExpression;
                if (value == .unavailable) return error.UnsupportedExpression;
                break :blk value;
            },
            .call => |call| blk: {
                if (call.func.* == .name and std.mem.eql(u8, call.func.name.ident, "__constexpr") and call.args.len == 1) {
                    break :blk try self.eval(call.args[0]);
                }
                break :blk try self.evalCall(call.func, call.args);
            },
            .index => |index| blk: {
                const obj = try self.eval(index.obj);
                const key = try self.eval(index.key);
                break :blk try tableLookup(obj, key);
            },
            .field => |field| blk: {
                const obj = try self.eval(field.obj);
                break :blk try tableFieldLookup(obj, field.field);
            },
            .unop => |unop| try self.evalUnop(unop.op, unop.operand),
            .binop => |binop| try self.evalBinop(binop.op, binop.lhs, binop.rhs),
            .table => |table| try self.evalTable(table.fields),
            .func_expr => |func| try self.makeFunc(func),
            .match_expr => |match_expr| try self.evalMatch(match_expr),
            .sequence => |seq| blk: {
                // Evaluate all expressions, return the first (multi-value semantics)
                if (seq.exprs.len == 0) break :blk .nil;
                break :blk try self.eval(seq.exprs[0]);
            },
            else => error.UnsupportedExpression,
        };
    }

    fn makeFunc(self: *Evaluator, func: *const ast.FuncBody) EvalError!Value {
        const captures = try self.snapshotCaptures();
        return .{ .func = .{ .body = func, .captures = captures } };
    }

    fn snapshotCaptures(self: *Evaluator) EvalError![]const Value.CapturedBinding {
        const alloc = self.options.alloc orelse return &.{};
        var count = self.locals.items.len;
        for (self.bindings.scopes) |*scope| count += scope.count();
        if (count == 0) return &.{};

        const captures = alloc.alloc(Value.CapturedBinding, count) catch return error.UnsupportedExpression;
        var out_i: usize = 0;
        for (self.bindings.scopes) |*scope| {
            var it = scope.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.* == .unavailable) continue;
                captures[out_i] = .{ .name = entry.key_ptr.*, .value = entry.value_ptr.* };
                out_i += 1;
            }
        }
        for (self.locals.items) |local| {
            if (local.value == .unavailable) continue;
            captures[out_i] = .{ .name = local.name, .value = local.value };
            out_i += 1;
        }
        return captures[0..out_i];
    }

    fn evalCall(self: *Evaluator, func_expr: *const ast.Expr, args: []const *ast.Expr) EvalError!Value {
        // Handle math.* stdlib at compile time
        if (func_expr.* == .field) {
            const f = func_expr.field;
            if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "math")) {
                return self.evalMathBuiltin(f.field, args);
            }
            if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "string")) {
                return self.evalStringBuiltin(f.field, args);
            }
            if (f.obj.* == .name and std.mem.eql(u8, f.obj.name.ident, "table")) {
                return self.evalTableBuiltin(f.field, args);
            }
        }
        // Handle global builtins: type(), tostring(), tonumber()
        if (func_expr.* == .name) {
            const name = func_expr.name.ident;
            if (std.mem.eql(u8, name, "__constexpr") and args.len == 1) {
                return try self.eval(args[0]);
            }
            if (std.mem.eql(u8, name, "type") and args.len == 1) {
                const val = try self.eval(args[0]);
                return .{ .string = switch (val) {
                    .nil, .unavailable => "nil",
                    .bool => "boolean",
                    .int, .float => "number",
                    .string => "string",
                    .table => "table",
                    .func => "function",
                } };
            }
            if (std.mem.eql(u8, name, "tonumber") and args.len == 1) {
                const val = try self.eval(args[0]);
                return switch (val) {
                    .int => val,
                    .float => val,
                    else => error.UnsupportedExpression,
                };
            }
            if (std.mem.eql(u8, name, "tostring") and args.len == 1) {
                const val = try self.eval(args[0]);
                const alloc = self.options.alloc orelse return error.UnsupportedExpression;
                return switch (val) {
                    .string => val,
                    .int => blk: {
                        var buf: [20]u8 = undefined;
                        const written = std.fmt.bufPrint(&buf, "{d}", .{val.int}) catch "??";
                        const owned = alloc.dupe(u8, written) catch return error.UnsupportedExpression;
                        break :blk .{ .string = owned };
                    },
                    .float => blk: {
                        var buf: [30]u8 = undefined;
                        const written = std.fmt.bufPrint(&buf, "{d}", .{val.float}) catch "??";
                        const owned = alloc.dupe(u8, written) catch return error.UnsupportedExpression;
                        break :blk .{ .string = owned };
                    },
                    .bool => .{ .string = if (val.bool) "true" else "false" },
                    .nil => .{ .string = "nil" },
                    .func => .{ .string = "<function>" },
                    .table => .{ .string = "<table>" },
                    .unavailable => .{ .string = "<unavailable>" },
                };
            }
            // __has_field / __has_method — compile-time structural queries
            // At the comptime level these return bool based on table structure
            if (std.mem.eql(u8, name, "__has_field") and args.len == 2) {
                const tbl = try self.eval(args[0]);
                const field_name = try self.eval(args[1]);
                if (tbl == .table and field_name == .string) {
                    for (tbl.table) |entry| {
                        if (entry.name) |ename| {
                            if (std.mem.eql(u8, ename, field_name.string)) return .{ .bool = true };
                        }
                    }
                    return .{ .bool = false };
                }
                return error.UnsupportedExpression;
            }
            if (std.mem.eql(u8, name, "__type_name") and args.len == 1) {
                const val = try self.eval(args[0]);
                return .{ .string = switch (val) {
                    .nil, .unavailable => "nil",
                    .bool => "bool",
                    .int => "i64",
                    .float => "f64",
                    .string => "str",
                    .table => "table",
                    .func => "function",
                } };
            }
            if (std.mem.eql(u8, name, "__type_id") and args.len == 1) {
                const val = try self.eval(args[0]);
                const type_str: []const u8 = switch (val) {
                    .nil, .unavailable => "nil",
                    .bool => "bool",
                    .int => "int64_t",
                    .float => "double",
                    .string => "const char*",
                    .table => "lua_Value",
                    .func => "lua_Value",
                };
                // FNV-1a hash for stable type ID
                var hash: u64 = 14695981039346656037;
                for (type_str) |byte| {
                    hash ^= @as(u64, byte);
                    hash *%= 1099511628211;
                }
                return .{ .int = @bitCast(hash) };
            }
            if (std.mem.eql(u8, name, "__is_type") and args.len == 2) {
                const val = try self.eval(args[0]);
                const expected = try self.eval(args[1]);
                if (expected != .string) return error.UnsupportedExpression;
                const actual: []const u8 = switch (val) {
                    .nil, .unavailable => "nil",
                    .bool => "bool",
                    .int => "i64",
                    .float => "f64",
                    .string => "str",
                    .table => "table",
                    .func => "function",
                };
                return .{ .bool = std.mem.eql(u8, actual, expected.string) };
            }
            // __comptimeprint — compile-time debug printing (returns nil)
            if (std.mem.eql(u8, name, "__comptimeprint") and args.len >= 1) {
                const val = try self.eval(args[0]);
                if (val == .string) {
                    term.locHint(args[0].loc(), "{s}", .{val.string});
                }
                return .nil;
            }
            // __comptimewarn — compile-time warning (returns nil)
            if (std.mem.eql(u8, name, "__comptimewarn") and args.len >= 1) {
                const val = try self.eval(args[0]);
                if (val == .string) {
                    term.locWarn(args[0].loc(), "{s}", .{val.string});
                }
                return .nil;
            }
            // __comptimeerror — abort with message
            if (std.mem.eql(u8, name, "__comptimeerror") and args.len >= 1) {
                const val = try self.eval(args[0]);
                if (val == .string) {
                    term.locErr(args[0].loc(), "{s}", .{val.string});
                }
                return error.UnsupportedExpression;
            }
        }
        const callee = try self.eval(func_expr);
        if (callee != .func) return error.UnsupportedExpression;
        const func = callee.func.body;
        if (func.vararg or args.len > func.params.len) return error.UnsupportedExpression;

        const mark = self.locals.items.len;
        defer self.popLocals(mark);
        for (callee.func.captures) |capture| {
            _ = try self.pushLocal(capture.name, capture.value);
        }
        for (func.params, 0..) |param, i| {
            const value = if (i < args.len)
                try self.eval(args[i])
            else if (param.default_val) |default_val|
                try self.eval(default_val)
            else
                Value.nil;
            _ = try self.pushLocal(param.name, value);
        }
        return try self.evalBlockValue(&func.body);
    }

    /// Evaluate string.* standard library functions at compile time.
    fn evalStringBuiltin(self: *Evaluator, name: []const u8, args: []const *ast.Expr) EvalError!Value {
        if (args.len >= 1) {
            const a = try self.eval(args[0]);
            if (a != .string) return error.UnsupportedExpression;
            if (std.mem.eql(u8, name, "len")) return .{ .int = @intCast(a.string.len) };
            if (std.mem.eql(u8, name, "upper")) {
                const alloc = self.options.alloc orelse return error.UnsupportedExpression;
                const buf = alloc.alloc(u8, a.string.len) catch return error.UnsupportedExpression;
                for (a.string, 0..) |c, i| buf[i] = std.ascii.toUpper(c);
                return .{ .string = buf };
            }
            if (std.mem.eql(u8, name, "lower")) {
                const alloc = self.options.alloc orelse return error.UnsupportedExpression;
                const buf = alloc.alloc(u8, a.string.len) catch return error.UnsupportedExpression;
                for (a.string, 0..) |c, i| buf[i] = std.ascii.toLower(c);
                return .{ .string = buf };
            }
            if (std.mem.eql(u8, name, "rev") or std.mem.eql(u8, name, "reverse")) {
                const alloc = self.options.alloc orelse return error.UnsupportedExpression;
                const buf = alloc.alloc(u8, a.string.len) catch return error.UnsupportedExpression;
                for (a.string, 0..) |c, i| buf[a.string.len - 1 - i] = c;
                return .{ .string = buf };
            }
            if (std.mem.eql(u8, name, "byte") and args.len == 1) {
                if (a.string.len == 0) return .nil;
                return .{ .int = @intCast(a.string[0]) };
            }
            if (std.mem.eql(u8, name, "byte") and args.len >= 2) {
                const idx_val = try self.eval(args[1]);
                const idx = numericAsInt(idx_val) orelse return error.UnsupportedExpression;
                if (idx < 1 or idx > @as(i64, @intCast(a.string.len))) return .nil;
                return .{ .int = @intCast(a.string[@intCast(idx - 1)]) };
            }
            if (std.mem.eql(u8, name, "rep") and args.len == 2) {
                const count_val = try self.eval(args[1]);
                const count = numericAsInt(count_val) orelse return error.UnsupportedExpression;
                if (count <= 0) return .{ .string = "" };
                const alloc = self.options.alloc orelse return error.UnsupportedExpression;
                const n: usize = @intCast(count);
                const buf = alloc.alloc(u8, a.string.len * n) catch return error.UnsupportedExpression;
                var off: usize = 0;
                for (0..n) |_| {
                    @memcpy(buf[off .. off + a.string.len], a.string);
                    off += a.string.len;
                }
                return .{ .string = buf };
            }
            if (std.mem.eql(u8, name, "sub") and args.len >= 2) {
                const start_val = try self.eval(args[1]);
                const start_raw = numericAsInt(start_val) orelse return error.UnsupportedExpression;
                const len_i: i64 = @intCast(a.string.len);
                const s: i64 = if (start_raw < 0) @max(len_i + start_raw + 1, 1) else @max(start_raw, 1);
                var e: i64 = len_i;
                if (args.len >= 3) {
                    const end_val = try self.eval(args[2]);
                    const end_raw = numericAsInt(end_val) orelse return error.UnsupportedExpression;
                    e = if (end_raw < 0) len_i + end_raw + 1 else @min(end_raw, len_i);
                }
                if (s > e) return .{ .string = "" };
                const si: usize = @intCast(s - 1);
                const ei: usize = @intCast(e);
                return .{ .string = a.string[si..ei] };
            }
            if (std.mem.eql(u8, name, "find") and args.len >= 2) {
                const pattern = try self.eval(args[1]);
                if (pattern != .string) return error.UnsupportedExpression;
                const start_i: usize = if (args.len >= 3) blk: {
                    const sv = try self.eval(args[2]);
                    const s = numericAsInt(sv) orelse 1;
                    break :blk @max(1, @as(usize, @intCast(s - 1)));
                } else 0;
                if (start_i >= a.string.len) return .{ .int = 0 };
                if (pattern.string.len == 0) return .{ .int = @intCast(start_i + 1) };
                if (pattern.string.len > a.string.len - start_i) return .{ .int = 0 };
                const limit = a.string.len - pattern.string.len;
                var pos: usize = start_i;
                while (pos <= limit) : (pos += 1) {
                    if (std.mem.eql(u8, a.string[pos .. pos + pattern.string.len], pattern.string)) {
                        return .{ .int = @intCast(pos + 1) };
                    }
                }
                return .{ .int = 0 };
            }
            if (std.mem.eql(u8, name, "char") and args.len >= 2) {
                const byte_val = try self.eval(args[1]);
                const byte_num = numericAsInt(byte_val) orelse return error.UnsupportedExpression;
                if (byte_num < 0 or byte_num > 255) return error.UnsupportedExpression;
                const alloc = self.options.alloc orelse return error.UnsupportedExpression;
                const buf = alloc.alloc(u8, 1) catch return error.UnsupportedExpression;
                buf[0] = @intCast(byte_num);
                return .{ .string = buf };
            }
            if (std.mem.eql(u8, name, "format")) {
                return self.evalStringFormat(a, args[1..]);
            }
        }
        return error.UnsupportedExpression;
    }

    fn evalStringFormat(self: *Evaluator, fmt: Value, extra_args: []const *ast.Expr) EvalError!Value {
        const alloc = self.options.alloc orelse return error.UnsupportedExpression;
        var result: std.ArrayListUnmanaged(u8) = .empty;
        defer result.deinit(alloc);
        var arg_idx: usize = 0;
        var i: usize = 0;
        while (i < fmt.string.len) : (i += 1) {
            const c = fmt.string[i];
            if (c != '%') {
                result.append(alloc, c) catch return error.UnsupportedExpression;
                continue;
            }
            i += 1;
            if (i >= fmt.string.len) break;
            const spec = fmt.string[i];
            if (spec == '%') {
                result.append(alloc, '%') catch return error.UnsupportedExpression;
                continue;
            }
            if (arg_idx >= extra_args.len) return error.UnsupportedExpression;
            const arg = try self.eval(extra_args[arg_idx]);
            arg_idx += 1;
            var buf: [30]u8 = undefined;
            switch (spec) {
                's' => {
                    const s = switch (arg) {
                        .string => arg.string,
                        .int => blk: {
                            const written = std.fmt.bufPrint(&buf, "{d}", .{arg.int}) catch "??";
                            break :blk written;
                        },
                        .float => blk: {
                            const written = std.fmt.bufPrint(&buf, "{d}", .{arg.float}) catch "??";
                            break :blk written;
                        },
                        .bool => if (arg.bool) "true" else "false",
                        .nil => "nil",
                        else => "??",
                    };
                    result.appendSlice(alloc, s) catch return error.UnsupportedExpression;
                },
                'd', 'i' => {
                    const written = switch (arg) {
                        .int => std.fmt.bufPrint(&buf, "{d}", .{arg.int}) catch "??",
                        .float => std.fmt.bufPrint(&buf, "{d}", .{@as(i64, @intFromFloat(arg.float))}) catch "??",
                        else => "??",
                    };
                    result.appendSlice(alloc, written) catch return error.UnsupportedExpression;
                },
                'f' => {
                    const written = switch (arg) {
                        .float => std.fmt.bufPrint(&buf, "{d}", .{arg.float}) catch "??",
                        .int => std.fmt.bufPrint(&buf, "{d}", .{@as(f64, @floatFromInt(arg.int))}) catch "??",
                        else => "??",
                    };
                    result.appendSlice(alloc, written) catch return error.UnsupportedExpression;
                },
                'x' => {
                    const written = switch (arg) {
                        .int => std.fmt.bufPrint(&buf, "{x}", .{@as(u64, @bitCast(arg.int))}) catch "??",
                        else => "??",
                    };
                    result.appendSlice(alloc, written) catch return error.UnsupportedExpression;
                },
                else => return error.UnsupportedExpression,
            }
        }
        return .{ .string = result.toOwnedSlice(alloc) catch return error.UnsupportedExpression };
    }

    /// Evaluate table.* standard library functions at compile time.
    fn evalTableBuiltin(self: *Evaluator, name: []const u8, args: []const *ast.Expr) EvalError!Value {
        if (args.len == 0) return error.UnsupportedExpression;
        const tbl = try self.eval(args[0]);
        if (tbl != .table) return error.UnsupportedExpression;
        if (std.mem.eql(u8, name, "insert") and args.len == 2) {
            const val = try self.eval(args[1]);
            const alloc = self.options.alloc orelse return error.UnsupportedExpression;
            var new_entries = alloc.alloc(Value.TableEntry, tbl.table.len + 1) catch return error.UnsupportedExpression;
            @memcpy(new_entries[0..tbl.table.len], tbl.table);
            new_entries[tbl.table.len] = .{ .key = .{ .int = @intCast(tbl.table.len + 1) }, .val = val };
            return .{ .table = new_entries };
        }
        if (std.mem.eql(u8, name, "insert") and args.len == 3) {
            const pos_val = try self.eval(args[1]);
            const pos = numericAsInt(pos_val) orelse return error.UnsupportedExpression;
            const val = try self.eval(args[2]);
            const alloc = self.options.alloc orelse return error.UnsupportedExpression;
            const new_len = tbl.table.len + 1;
            var new_entries = alloc.alloc(Value.TableEntry, new_len) catch return error.UnsupportedExpression;
            const insert_idx: usize = @intCast(@max(0, @min(pos - 1, @as(i64, @intCast(tbl.table.len)))));
            if (insert_idx > 0) @memcpy(new_entries[0..insert_idx], tbl.table[0..insert_idx]);
            new_entries[insert_idx] = .{ .key = .{ .int = pos }, .val = val };
            if (insert_idx < tbl.table.len) @memcpy(new_entries[insert_idx + 1 .. new_len], tbl.table[insert_idx..tbl.table.len]);
            return .{ .table = new_entries };
        }
        if (std.mem.eql(u8, name, "remove") and args.len >= 2) {
            const pos_val = try self.eval(args[1]);
            const pos = numericAsInt(pos_val) orelse return error.UnsupportedExpression;
            const idx: usize = if (pos >= 1 and pos <= @as(i64, @intCast(tbl.table.len)))
                @intCast(pos - 1)
            else
                return .nil;
            const alloc = self.options.alloc orelse return error.UnsupportedExpression;
            if (tbl.table.len <= 1) return .{ .table = &.{} };
            var new_entries = alloc.alloc(Value.TableEntry, tbl.table.len - 1) catch return error.UnsupportedExpression;
            if (idx > 0) @memcpy(new_entries[0..idx], tbl.table[0..idx]);
            const rest = tbl.table.len - idx - 1;
            if (rest > 0) @memcpy(new_entries[idx .. idx + rest], tbl.table[idx + 1 .. tbl.table.len]);
            return .{ .table = new_entries };
        }
        if (std.mem.eql(u8, name, "concat")) {
            var result: std.ArrayListUnmanaged(u8) = .empty;
            const result_alloc = self.options.alloc orelse return error.UnsupportedExpression;
            defer result.deinit(result_alloc);
            var i: usize = 0;
            const sep_val: ?Value = if (args.len >= 2) try self.eval(args[1]) else null;
            const sep: []const u8 = if (sep_val) |sv| switch (sv) {
                .string => sv.string,
                else => "",
            } else "";
            while (i < tbl.table.len) : (i += 1) {
                if (i > 0 and sep.len > 0) result.appendSlice(result_alloc, sep) catch return error.UnsupportedExpression;
                const v = tbl.table[i].val;
                const s = switch (v) {
                    .string => v.string,
                    .int => blk: {
                        var buf: [32]u8 = undefined;
                        const written = std.fmt.bufPrint(&buf, "{d}", .{v.int}) catch return error.UnsupportedExpression;
                        const out = result_alloc.dupe(u8, written) catch return error.UnsupportedExpression;
                        break :blk out;
                    },
                    .float => blk: {
                        var buf: [32]u8 = undefined;
                        const written = std.fmt.bufPrint(&buf, "{d}", .{v.float}) catch return error.UnsupportedExpression;
                        const out = result_alloc.dupe(u8, written) catch return error.UnsupportedExpression;
                        break :blk out;
                    },
                    .bool => if (v.bool) "true" else "false",
                    .nil => "nil",
                    else => return error.UnsupportedExpression,
                };
                result.appendSlice(result_alloc, s) catch return error.UnsupportedExpression;
            }
            return .{ .string = result.toOwnedSlice(result_alloc) catch return error.UnsupportedExpression };
        }
        if (std.mem.eql(u8, name, "sort") and args.len == 1) {
            const alloc = self.options.alloc orelse return error.UnsupportedExpression;
            var entries = alloc.alloc(Value.TableEntry, tbl.table.len) catch return error.UnsupportedExpression;
            @memcpy(entries, tbl.table);
            var j: usize = 1;
            while (j < entries.len) : (j += 1) {
                const key = entries[j];
                var k = j;
                while (k > 0) : (k -= 1) {
                    const prev = entries[k - 1];
                    const dominated = switch (prev.val) {
                        .int => |pv| switch (key.val) {
                            .int => |kv| pv > kv,
                            .float => |kvf| @as(f64, @floatFromInt(pv)) > kvf,
                            else => false,
                        },
                        .float => |pv| switch (key.val) {
                            .int => |kv| pv > @as(f64, @floatFromInt(kv)),
                            .float => |kv| pv > kv,
                            else => false,
                        },
                        .string => |ps| switch (key.val) {
                            .string => |ks| std.mem.order(u8, ps, ks) == .gt,
                            else => false,
                        },
                        .bool => |pb| switch (key.val) {
                            .bool => !pb and key.val.bool,
                            else => false,
                        },
                        else => false,
                    };
                    if (!dominated) break;
                    entries[k] = entries[k - 1];
                    entries[k - 1] = key;
                }
            }
            return .{ .table = entries };
        }
        if (std.mem.eql(u8, name, "sort") and args.len == 2) {
            _ = try self.eval(args[1]);
            const alloc = self.options.alloc orelse return error.UnsupportedExpression;
            const entries = alloc.alloc(Value.TableEntry, tbl.table.len) catch return error.UnsupportedExpression;
            @memcpy(entries, tbl.table);
            return .{ .table = entries };
        }
        return error.UnsupportedExpression;
    }

    /// Evaluate math.* standard library functions at compile time.
    fn evalMathBuiltin(self: *Evaluator, name: []const u8, args: []const *ast.Expr) EvalError!Value {
        if (args.len == 1) {
            const a = try self.eval(args[0]);
            const v = numericAsFloat(a) orelse return error.UnsupportedExpression;
            if (std.mem.eql(u8, name, "abs")) return if (a == .int) .{ .int = if (a.int < 0) -a.int else a.int } else .{ .float = @abs(v) };
            if (std.mem.eql(u8, name, "floor")) return .{ .float = @floor(v) };
            if (std.mem.eql(u8, name, "ceil")) return .{ .float = @ceil(v) };
            if (std.mem.eql(u8, name, "sqrt")) return .{ .float = @sqrt(v) };
            if (std.mem.eql(u8, name, "sin")) return .{ .float = @sin(v) };
            if (std.mem.eql(u8, name, "cos")) return .{ .float = @cos(v) };
            if (std.mem.eql(u8, name, "tan")) return .{ .float = std.math.tan(v) };
            if (std.mem.eql(u8, name, "exp")) return .{ .float = @exp(v) };
            if (std.mem.eql(u8, name, "log")) return .{ .float = @log(v) };
            return error.UnsupportedExpression;
        }
        if (args.len == 2) {
            const a = try self.eval(args[0]);
            const b = try self.eval(args[1]);
            if (std.mem.eql(u8, name, "max")) {
                if (a == .int and b == .int) return .{ .int = if (a.int > b.int) a.int else b.int };
                const av = numericAsFloat(a) orelse return error.UnsupportedExpression;
                const bv = numericAsFloat(b) orelse return error.UnsupportedExpression;
                return .{ .float = if (av > bv) av else bv };
            }
            if (std.mem.eql(u8, name, "min")) {
                if (a == .int and b == .int) return .{ .int = if (a.int < b.int) a.int else b.int };
                const av = numericAsFloat(a) orelse return error.UnsupportedExpression;
                const bv = numericAsFloat(b) orelse return error.UnsupportedExpression;
                return .{ .float = if (av < bv) av else bv };
            }
            if (std.mem.eql(u8, name, "pow")) {
                const av = numericAsFloat(a) orelse return error.UnsupportedExpression;
                const bv = numericAsFloat(b) orelse return error.UnsupportedExpression;
                return .{ .float = std.math.pow(f64, av, bv) };
            }
            return error.UnsupportedExpression;
        }
        return error.UnsupportedExpression;
    }

    fn evalTable(self: *Evaluator, fields: []const ast.TableField) EvalError!Value {
        const alloc = self.options.alloc orelse return error.UnsupportedExpression;
        const entries = alloc.alloc(Value.TableEntry, fields.len) catch return error.UnsupportedExpression;
        var pos: i64 = 1;
        for (fields, 0..) |field, i| {
            entries[i] = switch (field) {
                .positional => |expr| blk: {
                    const value = try self.eval(expr);
                    const entry = Value.TableEntry{ .key = .{ .int = pos }, .val = value };
                    pos += 1;
                    break :blk entry;
                },
                .named => |named| .{ .name = named.key, .val = try self.eval(named.val) },
                .indexed => |indexed| .{ .key = try self.eval(indexed.key), .val = try self.eval(indexed.val) },
            };
        }
        return .{ .table = entries };
    }

    fn evalUnop(self: *Evaluator, op: ast.UnOp, operand: *const ast.Expr) EvalError!Value {
        const value = try self.eval(operand);
        return switch (op) {
            .compile => value,
            .not => .{ .bool = !value.truthy() },
            .neg => switch (value) {
                .int => |v| .{ .int = -v },
                .float => |v| .{ .float = -v },
                else => error.UnsupportedOperator,
            },
            .bnot => switch (value) {
                .int => |v| .{ .int = ~v },
                else => error.UnsupportedOperator,
            },
            .len => switch (value) {
                .string => |v| .{ .int = @intCast(v.len) },
                else => error.UnsupportedOperator,
            },
        };
    }

    fn evalBinop(self: *Evaluator, op: ast.BinOp, lhs: *const ast.Expr, rhs: *const ast.Expr) EvalError!Value {
        if (op == .@"and") {
            const left = try self.eval(lhs);
            return if (left.truthy()) try self.eval(rhs) else left;
        }
        if (op == .@"or") {
            const left = try self.eval(lhs);
            return if (left.truthy()) left else try self.eval(rhs);
        }

        const left = try self.eval(lhs);
        const right = try self.eval(rhs);
        return switch (op) {
            .add, .sub, .mul, .div, .idiv, .mod, .pow => try evalNumeric(op, left, right),
            .band, .bor, .bxor, .lshift, .rshift => try evalInteger(op, left, right),
            .concat => try self.evalConcat(left, right),
            .eq => .{ .bool = left.eql(right) },
            .neq => .{ .bool = !left.eql(right) },
            .lt, .gt, .leq, .geq => try evalComparison(op, left, right),
            .contains, .@"and", .@"or" => error.UnsupportedOperator,
            .matmul => error.UnsupportedOperator,
            .pipeline => error.UnsupportedOperator,
        };
    }

    fn evalConcat(self: *Evaluator, left: Value, right: Value) EvalError!Value {
        if (left != .string or right != .string) return error.UnsupportedOperator;
        if (left.string.len == 0) return right;
        if (right.string.len == 0) return left;
        const alloc = self.options.alloc orelse return error.UnsupportedOperator;
        const joined = alloc.alloc(u8, left.string.len + right.string.len) catch return error.UnsupportedExpression;
        @memcpy(joined[0..left.string.len], left.string);
        @memcpy(joined[left.string.len..], right.string);
        return .{ .string = joined };
    }

    fn evalMatch(self: *Evaluator, match_expr: *const ast.MatchExpr) EvalError!Value {
        const scrutinee = try self.eval(match_expr.scrutinee);
        for (match_expr.arms) |arm| {
            const mark = self.locals.items.len;
            const matched = try self.matchPattern(arm.pattern, scrutinee);
            if (!matched) {
                self.popLocals(mark);
                continue;
            }
            if (arm.guard) |guard| {
                if (!(try self.eval(guard)).truthy()) {
                    self.popLocals(mark);
                    continue;
                }
            }
            const result = self.evalBlockValue(&arm.body);
            self.popLocals(mark);
            return result;
        }
        return error.UnsupportedExpression;
    }

    fn matchPattern(self: *Evaluator, pattern: ast.Pattern, value: Value) EvalError!bool {
        return switch (pattern) {
            .wildcard => true,
            .literal => |lit| (try self.eval(lit)).eql(value),
            .binding => |binding| blk: {
                _ = try self.pushLocal(binding.name, value);
                break :blk true;
            },
            .table_destr => |entries| try self.matchTablePattern(entries, value),
            .array_destr => |patterns| try self.matchArrayPattern(patterns, value),
            .rest => |name| blk: {
                _ = try self.pushLocal(name, value);
                break :blk true;
            },
            else => error.UnsupportedExpression,
        };
    }

    fn matchTablePattern(self: *Evaluator, entries: []const ast.Pattern.TableDestrEntry, value: Value) EvalError!bool {
        if (value != .table) return false;
        for (entries) |entry| {
            const field_value = try tableFieldLookup(value, entry.key);
            if (!(try self.matchPattern(entry.pat, field_value))) return false;
        }
        return true;
    }

    fn matchArrayPattern(self: *Evaluator, patterns: []const ast.Pattern, value: Value) EvalError!bool {
        if (value != .table) return false;
        for (patterns, 0..) |pattern, i| {
            if (pattern == .rest) {
                const rest = try self.arrayRest(value, @intCast(i + 1));
                _ = try self.pushLocal(pattern.rest, rest);
                return true;
            }
            const elem = try tableLookup(value, .{ .int = @intCast(i + 1) });
            if (!(try self.matchPattern(pattern, elem))) return false;
        }
        return true;
    }

    fn arrayRest(self: *Evaluator, value: Value, start_index: i64) EvalError!Value {
        const alloc = self.options.alloc orelse return error.UnsupportedExpression;
        if (value != .table) return error.UnsupportedExpression;
        var count: usize = 0;
        for (value.table) |entry| {
            if (entry.key) |key| {
                if (key == .int and key.int >= start_index) count += 1;
            }
        }
        const entries = alloc.alloc(Value.TableEntry, count) catch return error.UnsupportedExpression;
        var out_i: usize = 0;
        for (value.table) |entry| {
            if (entry.key) |key| {
                if (key == .int and key.int >= start_index) {
                    entries[out_i] = .{ .key = .{ .int = key.int - start_index + 1 }, .val = entry.val };
                    out_i += 1;
                }
            }
        }
        return .{ .table = entries };
    }

    fn evalBlockValue(self: *Evaluator, block: *const ast.Block) EvalError!Value {
        const result = try self.evalBlockScoped(block);
        return switch (result) {
            .value => |value| value,
            .none => error.UnsupportedExpression,
        };
    }

    fn evalBlockScoped(self: *Evaluator, block: *const ast.Block) EvalError!BlockResult {
        const mark = self.locals.items.len;
        defer self.popLocals(mark);
        return self.evalBlock(block);
    }

    fn evalBlock(self: *Evaluator, block: *const ast.Block) EvalError!BlockResult {
        for (block.stmts) |stmt| {
            const result = try self.evalStmt(stmt);
            if (result == .value) return result;
        }
        if (block.tail_expr) |expr| return .{ .value = try self.eval(expr) };
        return .none;
    }

    fn evalStmt(self: *Evaluator, stmt: ast.Stmt) EvalError!BlockResult {
        try self.step();
        return switch (stmt) {
            .local_decl => |decl| blk: {
                for (decl.names, 0..) |name, i| {
                    const value = if (i < decl.inits.len) try self.eval(decl.inits[i]) else Value.nil;
                    _ = try self.pushLocal(name.ident, value);
                }
                break :blk .none;
            },
            .const_decl => |decl| blk: {
                _ = try self.pushLocal(decl.ident, try self.eval(decl.val));
                break :blk .none;
            },
            .assign => |assign| blk: {
                for (assign.targets, 0..) |target, i| {
                    if (target.* != .name) return error.UnsupportedExpression;
                    const value = if (i < assign.values.len) try self.eval(assign.values[i]) else Value.nil;
                    try self.setLocal(target.name.ident, value);
                }
                break :blk .none;
            },
            .ret => |ret| blk: {
                if (ret.vals.len != 1) return error.UnsupportedExpression;
                break :blk .{ .value = try self.eval(ret.vals[0]) };
            },
            .expr_stmt => |expr_stmt| .{ .value = try self.eval(expr_stmt.expr) },
            .call_stmt => |call_stmt| .{ .value = try self.eval(call_stmt.expr) },
            .do_block => |do_block| try self.evalBlockScoped(&do_block.body),
            .if_stmt => |if_stmt| try self.evalIf(if_stmt),
            .while_loop => |while_loop| try self.evalWhile(while_loop),
            .num_for => |num_for| try self.evalNumFor(num_for),
            else => error.UnsupportedExpression,
        };
    }

    fn evalIf(self: *Evaluator, if_stmt: anytype) EvalError!BlockResult {
        if ((try self.eval(if_stmt.cond)).truthy()) return self.evalBlockScoped(&if_stmt.then);
        for (if_stmt.elseifs) |elseif| {
            if ((try self.eval(elseif.cond)).truthy()) return self.evalBlockScoped(&elseif.body);
        }
        if (if_stmt.else_body) |*else_body| return self.evalBlockScoped(else_body);
        return .none;
    }

    fn evalWhile(self: *Evaluator, while_loop: anytype) EvalError!BlockResult {
        while ((try self.eval(while_loop.cond)).truthy()) {
            try self.step();
            const result = try self.evalBlockScoped(&while_loop.body);
            if (result == .value) return result;
        }
        return .none;
    }

    fn evalNumFor(self: *Evaluator, num_for: anytype) EvalError!BlockResult {
        const start = numericAsInt(try self.eval(num_for.start)) orelse return error.UnsupportedOperator;
        const stop = numericAsInt(try self.eval(num_for.stop)) orelse return error.UnsupportedOperator;
        const step_value = if (num_for.step) |step_expr| numericAsInt(try self.eval(step_expr)) orelse return error.UnsupportedOperator else 1;
        if (step_value == 0) return error.UnsupportedOperator;
        const mark = self.locals.items.len;
        defer self.popLocals(mark);
        _ = try self.pushLocal(num_for.var_name, .{ .int = start });
        var i = start;
        while (if (step_value > 0) i <= stop else i >= stop) : (i += step_value) {
            try self.step();
            try self.setLocal(num_for.var_name, .{ .int = i });
            const result = try self.evalBlockScoped(&num_for.body);
            if (result == .value) return result;
        }
        return .none;
    }
};

pub fn funcValue(func: *const ast.FuncBody, bindings: Bindings, options: Options) EvalError!Value {
    var evaluator: Evaluator = .{ .bindings = bindings, .options = options };
    defer if (options.alloc) |alloc| evaluator.locals.deinit(alloc);
    return evaluator.makeFunc(func);
}

fn tableFieldLookup(obj: Value, field: []const u8) EvalError!Value {
    if (obj != .table) return error.UnsupportedOperator;
    for (obj.table) |entry| {
        if (entry.name) |name| {
            if (std.mem.eql(u8, name, field)) return entry.val;
        } else if (entry.key) |key| {
            if (key == .string and std.mem.eql(u8, key.string, field)) return entry.val;
        }
    }
    return .nil;
}

fn tableLookup(obj: Value, key: Value) EvalError!Value {
    if (obj != .table) return error.UnsupportedOperator;
    for (obj.table) |entry| {
        if (entry.name) |name| {
            if (key == .string and std.mem.eql(u8, key.string, name)) return entry.val;
        } else if (entry.key) |entry_key| {
            if (entry_key.eql(key)) return entry.val;
        }
    }
    return .nil;
}

fn numericAsFloat(value: Value) ?f64 {
    return switch (value) {
        .int => |v| @floatFromInt(v),
        .float => |v| v,
        else => null,
    };
}

fn numericAsInt(value: Value) ?i64 {
    return switch (value) {
        .int => |v| v,
        else => null,
    };
}

fn evalNumeric(op: ast.BinOp, left: Value, right: Value) EvalError!Value {
    if (left == .int and right == .int and op != .div and op != .pow) {
        const l = left.int;
        const r = right.int;
        return switch (op) {
            .add => .{ .int = l +% r },
            .sub => .{ .int = l -% r },
            .mul => .{ .int = l *% r },
            .idiv => if (r == 0) error.DivisionByZero else .{ .int = @divFloor(l, r) },
            .mod => if (r == 0) error.DivisionByZero else .{ .int = @mod(l, r) },
            else => error.UnsupportedOperator,
        };
    }

    const l = numericAsFloat(left) orelse return error.UnsupportedOperator;
    const r = numericAsFloat(right) orelse return error.UnsupportedOperator;
    return switch (op) {
        .add => .{ .float = l + r },
        .sub => .{ .float = l - r },
        .mul => .{ .float = l * r },
        .div => if (r == 0.0) error.DivisionByZero else .{ .float = l / r },
        .pow => .{ .float = std.math.pow(f64, l, r) },
        else => error.UnsupportedOperator,
    };
}

fn evalInteger(op: ast.BinOp, left: Value, right: Value) EvalError!Value {
    const l = numericAsInt(left) orelse return error.UnsupportedOperator;
    const r = numericAsInt(right) orelse return error.UnsupportedOperator;
    return switch (op) {
        .band => .{ .int = l & r },
        .bor => .{ .int = l | r },
        .bxor => .{ .int = l ^ r },
        .lshift => if (r >= 0 and r < 64) .{ .int = l << @intCast(r) } else error.UnsupportedOperator,
        .rshift => if (r >= 0 and r < 64) .{ .int = @as(i64, @bitCast(@as(u64, @bitCast(l)) >> @intCast(r))) } else error.UnsupportedOperator,
        else => error.UnsupportedOperator,
    };
}

fn evalComparison(op: ast.BinOp, left: Value, right: Value) EvalError!Value {
    if (numericAsFloat(left)) |l| {
        const r = numericAsFloat(right) orelse return error.UnsupportedOperator;
        return .{ .bool = switch (op) {
            .lt => l < r,
            .gt => l > r,
            .leq => l <= r,
            .geq => l >= r,
            else => unreachable,
        } };
    }
    if (left == .string and right == .string) {
        const order = std.mem.order(u8, left.string, right.string);
        return .{ .bool = switch (op) {
            .lt => order == .lt,
            .gt => order == .gt,
            .leq => order != .gt,
            .geq => order != .lt,
            else => unreachable,
        } };
    }
    return error.UnsupportedOperator;
}

pub fn eval(expr: *const ast.Expr) EvalError!Value {
    var evaluator: Evaluator = .{};
    return evaluator.eval(expr);
}

pub fn evalWithBindings(expr: *const ast.Expr, bindings: Bindings, options: Options) EvalError!Value {
    var evaluator: Evaluator = .{ .bindings = bindings, .options = options };
    defer if (options.alloc) |alloc| evaluator.locals.deinit(alloc);
    return evaluator.eval(expr);
}

test "comptime eval: pure arithmetic" {
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var two = ast.Expr{ .int_lit = .{ .loc = loc, .val = 2 } };
    var three = ast.Expr{ .int_lit = .{ .loc = loc, .val = 3 } };
    var four = ast.Expr{ .int_lit = .{ .loc = loc, .val = 4 } };
    var mul = ast.Expr{ .binop = .{ .loc = loc, .op = .mul, .lhs = &three, .rhs = &four } };
    var add = ast.Expr{ .binop = .{ .loc = loc, .op = .add, .lhs = &two, .rhs = &mul } };
    try std.testing.expectEqual(Value{ .int = 14 }, try eval(&add));
}

test "comptime eval: scoped bindings and shadowing" {
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var outer: std.StringHashMapUnmanaged(Value) = .empty;
    defer outer.deinit(std.testing.allocator);
    var inner: std.StringHashMapUnmanaged(Value) = .empty;
    defer inner.deinit(std.testing.allocator);
    try outer.put(std.testing.allocator, "base", .{ .int = 10 });
    try inner.put(std.testing.allocator, "base", .{ .int = 20 });
    try inner.put(std.testing.allocator, "offset", .{ .int = 2 });
    const scopes = [_]std.StringHashMapUnmanaged(Value){ outer, inner };
    var base = ast.Expr{ .name = .{ .loc = loc, .ident = "base" } };
    var offset = ast.Expr{ .name = .{ .loc = loc, .ident = "offset" } };
    var add = ast.Expr{ .binop = .{ .loc = loc, .op = .add, .lhs = &base, .rhs = &offset } };
    try std.testing.expectEqual(Value{ .int = 22 }, try evalWithBindings(&add, .{ .scopes = &scopes }, .{}));
}

test "comptime eval: runtime-only names are unsupported" {
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var name = ast.Expr{ .name = .{ .loc = loc, .ident = "x" } };
    try std.testing.expectError(error.UnsupportedExpression, eval(&name));
}

test "comptime eval: pure table literals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var one = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    var two = ast.Expr{ .int_lit = .{ .loc = loc, .val = 2 } };
    var key = ast.Expr{ .string_lit = .{ .loc = loc, .val = "answer" } };
    var forty_two = ast.Expr{ .int_lit = .{ .loc = loc, .val = 42 } };
    const fields = try alloc.alloc(ast.TableField, 3);
    fields[0] = .{ .positional = &one };
    fields[1] = .{ .named = .{ .key = "name", .val = &two } };
    fields[2] = .{ .indexed = .{ .key = &key, .val = &forty_two } };
    var table = ast.Expr{ .table = .{ .loc = loc, .fields = fields } };

    const value = try evalWithBindings(&table, .{}, .{ .alloc = alloc });
    try std.testing.expect(value == .table);
    try std.testing.expectEqual(@as(usize, 3), value.table.len);
    try std.testing.expectEqual(Value{ .int = 1 }, value.table[0].key.?);
    try std.testing.expectEqual(Value{ .int = 1 }, value.table[0].val);
    try std.testing.expectEqualStrings("name", value.table[1].name.?);
    try std.testing.expectEqual(Value{ .int = 2 }, value.table[1].val);
    try std.testing.expectEqual(Value{ .string = "answer" }, value.table[2].key.?);
    try std.testing.expectEqual(Value{ .int = 42 }, value.table[2].val);
}

test "comptime eval: table field and index lookups" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var one = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    var name_value = ast.Expr{ .string_lit = .{ .loc = loc, .val = "duo" } };
    var key = ast.Expr{ .string_lit = .{ .loc = loc, .val = "answer" } };
    var forty_two = ast.Expr{ .int_lit = .{ .loc = loc, .val = 42 } };
    const fields = try alloc.alloc(ast.TableField, 3);
    fields[0] = .{ .positional = &one };
    fields[1] = .{ .named = .{ .key = "name", .val = &name_value } };
    fields[2] = .{ .indexed = .{ .key = &key, .val = &forty_two } };
    var table = ast.Expr{ .table = .{ .loc = loc, .fields = fields } };

    var field = ast.Expr{ .field = .{ .loc = loc, .obj = &table, .field = "name" } };
    var index_key = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    var index = ast.Expr{ .index = .{ .loc = loc, .obj = &table, .key = &index_key } };
    var named_index_key = ast.Expr{ .string_lit = .{ .loc = loc, .val = "answer" } };
    var named_index = ast.Expr{ .index = .{ .loc = loc, .obj = &table, .key = &named_index_key } };
    var missing = ast.Expr{ .field = .{ .loc = loc, .obj = &table, .field = "missing" } };

    try std.testing.expectEqual(Value{ .string = "duo" }, try evalWithBindings(&field, .{}, .{ .alloc = alloc }));
    try std.testing.expectEqual(Value{ .int = 1 }, try evalWithBindings(&index, .{}, .{ .alloc = alloc }));
    try std.testing.expectEqual(Value{ .int = 42 }, try evalWithBindings(&named_index, .{}, .{ .alloc = alloc }));
    try std.testing.expectEqual(Value.nil, try evalWithBindings(&missing, .{}, .{ .alloc = alloc }));
}

test "comptime eval: string concat allocates deterministic literals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var left = ast.Expr{ .string_lit = .{ .loc = loc, .val = "du" } };
    var right = ast.Expr{ .string_lit = .{ .loc = loc, .val = "o" } };
    var concat = ast.Expr{ .binop = .{ .loc = loc, .op = .concat, .lhs = &left, .rhs = &right } };
    const value = try evalWithBindings(&concat, .{}, .{ .alloc = alloc });
    try std.testing.expect(value == .string);
    try std.testing.expectEqualStrings("duo", value.string);
}

test "comptime eval: match expression with literal and guarded binding arms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };

    var scrutinee = ast.Expr{ .int_lit = .{ .loc = loc, .val = 4 } };
    var one = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    var one_result = ast.Expr{ .string_lit = .{ .loc = loc, .val = "one" } };
    var binding_name = ast.Expr{ .name = .{ .loc = loc, .ident = "n" } };
    var guard_min = ast.Expr{ .int_lit = .{ .loc = loc, .val = 2 } };
    var guard = ast.Expr{ .binop = .{ .loc = loc, .op = .gt, .lhs = &binding_name, .rhs = &guard_min } };
    var forty = ast.Expr{ .int_lit = .{ .loc = loc, .val = 40 } };
    var body_name = ast.Expr{ .name = .{ .loc = loc, .ident = "n" } };
    var add = ast.Expr{ .binop = .{ .loc = loc, .op = .add, .lhs = &body_name, .rhs = &forty } };

    const first_stmts = try alloc.alloc(ast.Stmt, 1);
    first_stmts[0] = .{ .ret = .{ .loc = loc, .vals = try alloc.dupe(*ast.Expr, &.{&one_result}) } };
    const second_stmts = try alloc.alloc(ast.Stmt, 1);
    second_stmts[0] = .{ .ret = .{ .loc = loc, .vals = try alloc.dupe(*ast.Expr, &.{&add}) } };
    const arms = try alloc.alloc(ast.MatchArm, 2);
    arms[0] = .{
        .pattern = .{ .literal = &one },
        .guard = null,
        .body = .{ .loc = loc, .stmts = first_stmts },
    };
    arms[1] = .{
        .pattern = .{ .binding = .{ .name = "n", .typ = null } },
        .guard = &guard,
        .body = .{ .loc = loc, .stmts = second_stmts },
    };
    var match_expr = ast.MatchExpr{ .loc = loc, .scrutinee = &scrutinee, .arms = arms };
    var expr = ast.Expr{ .match_expr = &match_expr };

    try std.testing.expectEqual(Value{ .int = 44 }, try evalWithBindings(&expr, .{}, .{ .alloc = alloc }));
}

test "comptime eval: match expression with table and array destructuring" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };

    var kind_key = ast.Expr{ .string_lit = .{ .loc = loc, .val = "kind" } };
    var kind_val = ast.Expr{ .string_lit = .{ .loc = loc, .val = "pair" } };
    var left_val = ast.Expr{ .int_lit = .{ .loc = loc, .val = 2 } };
    var right_val = ast.Expr{ .int_lit = .{ .loc = loc, .val = 3 } };
    const table_fields = try alloc.alloc(ast.TableField, 3);
    table_fields[0] = .{ .indexed = .{ .key = &kind_key, .val = &kind_val } };
    table_fields[1] = .{ .named = .{ .key = "left", .val = &left_val } };
    table_fields[2] = .{ .named = .{ .key = "right", .val = &right_val } };
    var table = ast.Expr{ .table = .{ .loc = loc, .fields = table_fields } };

    var literal_pair = ast.Expr{ .string_lit = .{ .loc = loc, .val = "pair" } };
    const table_entries = try alloc.alloc(ast.Pattern.TableDestrEntry, 3);
    table_entries[0] = .{ .key = "kind", .pat = .{ .literal = &literal_pair } };
    table_entries[1] = .{ .key = "left", .pat = .{ .binding = .{ .name = "a", .typ = null } } };
    table_entries[2] = .{ .key = "right", .pat = .{ .binding = .{ .name = "b", .typ = null } } };
    var a_name = ast.Expr{ .name = .{ .loc = loc, .ident = "a" } };
    var b_name = ast.Expr{ .name = .{ .loc = loc, .ident = "b" } };
    var sum = ast.Expr{ .binop = .{ .loc = loc, .op = .add, .lhs = &a_name, .rhs = &b_name } };
    const table_body = try alloc.alloc(ast.Stmt, 1);
    table_body[0] = .{ .ret = .{ .loc = loc, .vals = try alloc.dupe(*ast.Expr, &.{&sum}) } };
    const table_arms = try alloc.alloc(ast.MatchArm, 1);
    table_arms[0] = .{
        .pattern = .{ .table_destr = table_entries },
        .guard = null,
        .body = .{ .loc = loc, .stmts = table_body },
    };
    var table_match = ast.MatchExpr{ .loc = loc, .scrutinee = &table, .arms = table_arms };
    var table_expr = ast.Expr{ .match_expr = &table_match };
    try std.testing.expectEqual(Value{ .int = 5 }, try evalWithBindings(&table_expr, .{}, .{ .alloc = alloc }));

    var one = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    var two = ast.Expr{ .int_lit = .{ .loc = loc, .val = 2 } };
    var three = ast.Expr{ .int_lit = .{ .loc = loc, .val = 3 } };
    const array_fields = try alloc.alloc(ast.TableField, 3);
    array_fields[0] = .{ .positional = &one };
    array_fields[1] = .{ .positional = &two };
    array_fields[2] = .{ .positional = &three };
    var array = ast.Expr{ .table = .{ .loc = loc, .fields = array_fields } };
    const array_patterns = try alloc.alloc(ast.Pattern, 2);
    array_patterns[0] = .{ .binding = .{ .name = "head", .typ = null } };
    array_patterns[1] = .{ .rest = "tail" };
    var head_name = ast.Expr{ .name = .{ .loc = loc, .ident = "head" } };
    var tail_name = ast.Expr{ .name = .{ .loc = loc, .ident = "tail" } };
    var tail_first_key = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    var tail_first = ast.Expr{ .index = .{ .loc = loc, .obj = &tail_name, .key = &tail_first_key } };
    var array_sum = ast.Expr{ .binop = .{ .loc = loc, .op = .add, .lhs = &head_name, .rhs = &tail_first } };
    const array_body = try alloc.alloc(ast.Stmt, 1);
    array_body[0] = .{ .ret = .{ .loc = loc, .vals = try alloc.dupe(*ast.Expr, &.{&array_sum}) } };
    const array_arms = try alloc.alloc(ast.MatchArm, 1);
    array_arms[0] = .{
        .pattern = .{ .array_destr = array_patterns },
        .guard = null,
        .body = .{ .loc = loc, .stmts = array_body },
    };
    var array_match = ast.MatchExpr{ .loc = loc, .scrutinee = &array, .arms = array_arms };
    var array_expr = ast.Expr{ .match_expr = &array_match };
    try std.testing.expectEqual(Value{ .int = 3 }, try evalWithBindings(&array_expr, .{}, .{ .alloc = alloc }));
}

test "comptime eval: do blocks with bounded loops and local mutation" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\local for_total = __constexpr(match true
        \\  case _ then do
        \\    local acc = 0
        \\    for i = 1, 4 do
        \\      acc = acc + i
        \\    end
        \\    acc
        \\  end
        \\end)
        \\local while_total = __constexpr(match true
        \\  case _ then do
        \\    local n = 4
        \\    local acc = 0
        \\    while n > 0 do
        \\      acc = acc + n
        \\      n = n - 1
        \\    end
        \\    acc
        \\  end
        \\end)
    , "test");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();
    const first = module.body.stmts[0].local_decl.inits[0];
    const second = module.body.stmts[1].local_decl.inits[0];

    try std.testing.expectEqual(Value{ .int = 10 }, try evalWithBindings(first, .{}, .{ .alloc = alloc }));
    try std.testing.expectEqual(Value{ .int = 10 }, try evalWithBindings(second, .{}, .{ .alloc = alloc }));
}

test "comptime eval: pure function calls and recursion" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\function fact(n: i64): i64
        \\  if n <= 1 then
        \\    return 1
        \\  end
        \\  return n * fact(n - 1)
        \\end
        \\local folded = __constexpr(fact(5))
    , "test");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();
    const func = &module.body.stmts[0].func_decl.func;
    var scope: std.StringHashMapUnmanaged(Value) = .empty;
    defer scope.deinit(alloc);
    try scope.put(alloc, "fact", try funcValue(func, .{}, .{ .alloc = alloc }));
    const scopes = [_]std.StringHashMapUnmanaged(Value){scope};
    const init = module.body.stmts[1].local_decl.inits[0];

    try std.testing.expectEqual(Value{ .int = 120 }, try evalWithBindings(init, .{ .scopes = &scopes }, .{ .alloc = alloc }));
}

test "comptime eval: function values snapshot lexical captures" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = Lexer.init(
        \\local base = 10
        \\local add = function(n: i64): i64
        \\  return base + n
        \\end
        \\local folded = __constexpr(add(5))
    , "test");
    var parser = Parser.init(&lex, alloc);
    const module = try parser.parse_module();
    const base_init = module.body.stmts[0].local_decl.inits[0];
    const add_init = module.body.stmts[1].local_decl.inits[0];
    const folded_init = module.body.stmts[2].local_decl.inits[0];

    var scope: std.StringHashMapUnmanaged(Value) = .empty;
    defer scope.deinit(alloc);
    try scope.put(alloc, "base", try evalWithBindings(base_init, .{}, .{ .alloc = alloc }));
    const scopes = [_]std.StringHashMapUnmanaged(Value){scope};
    const add_value = try evalWithBindings(add_init, .{ .scopes = &scopes }, .{ .alloc = alloc });
    try scope.put(alloc, "add", add_value);
    try scope.put(alloc, "base", .{ .int = 20 });

    try std.testing.expectEqual(Value{ .int = 15 }, try evalWithBindings(folded_init, .{ .scopes = &scopes }, .{ .alloc = alloc }));
}

test "comptime eval: step limit" {
    const loc = ast.Loc{ .file = "test", .line = 1, .col = 1 };
    var one = ast.Expr{ .int_lit = .{ .loc = loc, .val = 1 } };
    try std.testing.expectError(error.StepLimitExceeded, evalWithBindings(&one, .{}, .{ .step_limit = 0 }));
}
