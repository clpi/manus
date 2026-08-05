//! Req-module metadata for direct ARM64 lowering (constants + @c.export symbols).
const std = @import("std");
const Io = std.Io;
const ast = @import("ast.zig");
const duo_module_names = @import("duo_module_names.zig");

pub const ModuleMeta = struct {
    mod_cname: []const u8,
    constants: std.StringHashMapUnmanaged(i64),
    exports: std.StringHashMapUnmanaged([]const u8),

    pub fn deinit(self: *ModuleMeta, alloc: std.mem.Allocator) void {
        alloc.free(self.mod_cname);
        var cit = self.constants.iterator();
        while (cit.next()) |e| alloc.free(e.key_ptr.*);
        self.constants.deinit(alloc);
        var eit = self.exports.iterator();
        while (eit.next()) |e| {
            alloc.free(e.key_ptr.*);
            alloc.free(e.value_ptr.*);
        }
        self.exports.deinit(alloc);
    }
};

pub const Context = struct {
    /// Duo alias → module C prefix (`Classify` → `std_token_classify`).
    bindings: std.StringHashMapUnmanaged([]const u8) = .empty,
    /// Module C prefix → parsed metadata.
    modules: std.StringHashMapUnmanaged(ModuleMeta) = .empty,

    pub fn deinit(self: *Context, alloc: std.mem.Allocator) void {
        var bit = self.bindings.iterator();
        while (bit.next()) |e| {
            alloc.free(e.key_ptr.*);
            alloc.free(e.value_ptr.*);
        }
        self.bindings.deinit(alloc);
        var mit = self.modules.iterator();
        while (mit.next()) |e| {
            e.value_ptr.deinit(alloc);
            alloc.free(e.key_ptr.*);
        }
        self.modules.deinit(alloc);
    }

    pub fn modCName(self: *const Context, alias: []const u8) ?[]const u8 {
        return self.bindings.get(alias);
    }

    pub fn constant(self: *const Context, alias: []const u8, field: []const u8) ?i64 {
        const mc = self.bindings.get(alias) orelse return null;
        const meta = self.modules.get(mc) orelse return null;
        return meta.constants.get(field);
    }

    pub fn exportSymbol(self: *const Context, alias: []const u8, field: []const u8) ?[]const u8 {
        const mc = self.bindings.get(alias) orelse return null;
        const meta = self.modules.get(mc) orelse return null;
        return meta.exports.get(field);
    }
};

pub fn collectFromModule(alloc: std.mem.Allocator, mod: *const ast.Module) !Context {
    var ctx: Context = .{};
    errdefer ctx.deinit(alloc);

    const ReqBinding = struct {
        alias: []const u8,
        val: *const ast.Expr,
    };

    for (mod.body.stmts) |*stmt| {
        const parsed: ?ReqBinding = switch (stmt.*) {
            .assign => |as| blk: {
                if (as.targets.len != 1 or as.values.len != 1) break :blk null;
                if (as.targets[0].* != .name) break :blk null;
                break :blk ReqBinding{ .alias = as.targets[0].name.ident, .val = as.values[0] };
            },
            .local_decl => |ld| blk: {
                if (ld.names.len != 1 or ld.inits.len != 1) break :blk null;
                break :blk ReqBinding{ .alias = ld.names[0].ident, .val = ld.inits[0] };
            },
            else => null,
        };
        const item = parsed orelse continue;
        const path = reqPathFromExpr(item.val) orelse continue;
        const mod_cname = try duo_module_names.moduleCName(alloc, path);
        const owned_alias = try alloc.dupe(u8, item.alias);
        try ctx.bindings.put(alloc, owned_alias, mod_cname);
        if (ctx.modules.contains(mod_cname)) continue;
        const meta = try loadModuleMeta(alloc, path, mod_cname);
        try ctx.modules.put(alloc, try alloc.dupe(u8, mod_cname), meta);
    }
    return ctx;
}

fn reqPathFromExpr(expr: *const ast.Expr) ?[]const u8 {
    if (expr.* != .call) return null;
    const c = expr.call;
    if (c.func.* != .name or !std.mem.eql(u8, c.func.name.ident, "req")) return null;
    if (c.args.len != 1) return null;
    return switch (c.args[0].*) {
        .string_lit => |s| s.val,
        else => null,
    };
}

fn loadModuleMeta(alloc: std.mem.Allocator, req_path: []const u8, mod_cname: []const u8) !ModuleMeta {
    const makeEmpty = struct {
        fn call(a: std.mem.Allocator, mc: []const u8) !ModuleMeta {
            return .{
                .mod_cname = try a.dupe(u8, mc),
                .constants = .empty,
                .exports = .empty,
            };
        }
    }.call;

    const core_prefix = "std.core.";
    const strip_len: usize = if (std.mem.startsWith(u8, req_path, core_prefix)) core_prefix.len else 0;
    const s = req_path[strip_len..];
    var rel: [512]u8 = undefined;
    if (s.len > rel.len) return makeEmpty(alloc, mod_cname);
    for (s, 0..) |c, i| rel[i] = if (c == '.') '/' else c;
    const rel_path = rel[0..s.len];

    var threaded = std.Io.Threaded.init(alloc, .{});
    const io = threaded.io();
    const cwd = Io.Dir.cwd();
    var path_buf: [768]u8 = undefined;
    var owned_source: ?[]const u8 = null;
    const prefixes = [_][]const u8{ "lib/std/", "lib/" };
    for (prefixes) |prefix| {
        const path = std.fmt.bufPrint(&path_buf, "{s}{s}.duo", .{ prefix, rel_path }) catch continue;
        owned_source = Io.Dir.readFileAlloc(cwd, io, path, alloc, .unlimited) catch null;
        if (owned_source != null) break;
    }
    const source = owned_source orelse return makeEmpty(alloc, mod_cname);
    defer alloc.free(source);

    var constants: std.StringHashMapUnmanaged(i64) = .empty;
    errdefer {
        var it = constants.iterator();
        while (it.next()) |e| alloc.free(e.key_ptr.*);
        constants.deinit(alloc);
    }
    var exports: std.StringHashMapUnmanaged([]const u8) = .empty;
    errdefer {
        var it = exports.iterator();
        while (it.next()) |e| {
            alloc.free(e.key_ptr.*);
            alloc.free(e.value_ptr.*);
        }
        exports.deinit(alloc);
    }

    try scanModuleSource(alloc, source, &constants, &exports);

    return ModuleMeta{
        .mod_cname = try alloc.dupe(u8, mod_cname),
        .constants = constants,
        .exports = exports,
    };
}

fn scanModuleSource(
    alloc: std.mem.Allocator,
    source: []const u8,
    constants: *std.StringHashMapUnmanaged(i64),
    exports: *std.StringHashMapUnmanaged([]const u8),
) !void {
    var pending_export: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        if (raw_line.len > 0 and (raw_line[0] == ' ' or raw_line[0] == '\t')) continue;
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or std.mem.startsWith(u8, line, "--")) continue;
        if (std.mem.startsWith(u8, line, "@c.export") or std.mem.startsWith(u8, line, "@comp.c.export")) {
            pending_export = parseExportFromLine(line);
            continue;
        }
        if (std.mem.startsWith(u8, line, "fun ")) {
            const rest = line["fun ".len..];
            const end = std.mem.indexOfScalar(u8, rest, '(') orelse {
                pending_export = null;
                continue;
            };
            const field = std.mem.trim(u8, rest[0..end], " \t");
            if (pending_export) |sym| {
                const owned_field = try alloc.dupe(u8, field);
                const owned_sym = try alloc.dupe(u8, sym);
                try exports.put(alloc, owned_field, owned_sym);
            }
            pending_export = null;
            continue;
        }
        if (std.mem.indexOf(u8, line, " = ")) |eq| {
            pending_export = null;
            const name = std.mem.trim(u8, line[0..eq], " \t");
            if (name.len == 0 or name[0] == '@' or !isIdent(name)) continue;
            const rhs = std.mem.trim(u8, line[eq + 3 ..], " \t");
            if (parseIntLiteral(rhs)) |val| {
                const owned_key = try alloc.dupe(u8, name);
                try constants.put(alloc, owned_key, val);
            }
        } else {
            pending_export = null;
        }
    }
}

fn parseExportFromLine(line: []const u8) ?[]const u8 {
    const open = std.mem.indexOf(u8, line, "(") orelse return null;
    const close = std.mem.lastIndexOf(u8, line, ")") orelse return null;
    if (close <= open + 1) return null;
    const raw = std.mem.trim(u8, line[open + 1 .. close], " \t");
    return parseExportArg(raw);
}

fn parseIntLiteral(text: []const u8) ?i64 {
    if (text.len == 0) return null;
    return std.fmt.parseInt(i64, text, 10) catch null;
}

fn isIdent(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name, 0..) |c, i| {
        if (i == 0) {
            if (!((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_')) return false;
        } else {
            if (!((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_')) return false;
        }
    }
    return true;
}

fn parseExportArg(raw: []const u8) ?[]const u8 {
    if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"') return raw[1 .. raw.len - 1];
    return raw;
}

test "native_req_support: token constants" {
    const alloc = std.testing.allocator;
    const path = "std.compiler.token";
    const mod_cname = try duo_module_names.moduleCName(alloc, path);
    defer alloc.free(mod_cname);
    const meta = try loadModuleMeta(alloc, path, mod_cname);
    defer {
        var m = meta;
        m.deinit(alloc);
    }
    try std.testing.expectEqual(@as(i64, 14), meta.constants.get("KIND_FUN").?);
    try std.testing.expectEqual(@as(i64, 105), meta.constants.get("KIND_EOF").?);
}

test "native_req_support: classify export" {
    const alloc = std.testing.allocator;
    const path = "std.token.classify";
    const mod_cname = try duo_module_names.moduleCName(alloc, path);
    defer alloc.free(mod_cname);
    const meta = try loadModuleMeta(alloc, path, mod_cname);
    defer {
        var m = meta;
        m.deinit(alloc);
    }
    try std.testing.expectEqualStrings("duo_keyword_classify", meta.exports.get("classify").?);
}
