//! Req-module metadata for direct ARM64 lowering (constants + @c.export symbols).
const std = @import("std");
const Io = std.Io;
const ast = @import("ast.zig");
const duo_module_names = @import("duo_module_names.zig");
const source_family = @import("duo_lexer_bridge.zig");

const source_suffixes = [_][]const u8{
    source_family.CANONICAL_SOURCE_SUFFIX,
    source_family.HISTORICAL_SOURCE_SUFFIX,
};

pub const ModuleMeta = struct {
    mod_cname: []const u8,
    constants: std.StringHashMapUnmanaged(i64),
    exports: std.StringHashMapUnmanaged([]const u8),
    /// The Idsem source this module resolved to, when it was found on disk. The
    /// direct backend emits relocations against this module's `@comp.c.export`
    /// symbols, so it must be able to compile and link the file that defines
    /// them; the alias and C prefix alone do not say where that file lives.
    source_path: ?[]const u8 = null,

    pub fn deinit(self: *ModuleMeta, alloc: std.mem.Allocator) void {
        alloc.free(self.mod_cname);
        if (self.source_path) |sp| alloc.free(sp);
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

    /// Resolve a callee named by a DOTTED PATH rather than a single alias.
    /// `collectDottedCallee` loads the module; this finds its export.
    pub fn exportSymbolByPath(
        self: *const Context,
        alloc: std.mem.Allocator,
        path: []const u8,
        field: []const u8,
    ) ?[]const u8 {
        const mc = duo_module_names.moduleCName(alloc, path) catch return null;
        defer alloc.free(mc);
        const meta = self.modules.get(mc) orelse return null;
        return meta.exports.get(field);
    }

    pub fn exportSymbol(self: *const Context, alias: []const u8, field: []const u8) ?[]const u8 {
        const mc = self.bindings.get(alias) orelse return null;
        const meta = self.modules.get(mc) orelse return null;
        return meta.exports.get(field);
    }

    /// One `req` binding: the local alias and the `.duo` file it names.
    pub const AliasSource = struct { alias: []const u8, source_path: []const u8 };

    /// Every `req` binding that resolved to a readable `.duo` file, paired with
    /// the alias the caller uses. `exportingModuleSources` answers a different
    /// question — which modules need a SEPARATE object — and deliberately skips
    /// modules with no `@comp.c.export`. Those are exactly the modules the
    /// direct backend can absorb into its own object instead, so the splice
    /// needs the unfiltered list.
    pub fn aliasSources(
        self: *const Context,
        alloc: std.mem.Allocator,
        out: *std.ArrayListUnmanaged(AliasSource),
    ) !void {
        var it = self.bindings.iterator();
        while (it.next()) |e| {
            const meta = self.modules.get(e.value_ptr.*) orelse continue;
            const sp = meta.source_path orelse continue;
            try out.append(alloc, .{ .alias = e.key_ptr.*, .source_path = sp });
        }
    }

    /// True when this module supplies its own object via `@comp.c.export`, so
    /// splicing it would duplicate every symbol at link time.
    pub fn moduleExportsSymbols(self: *const Context, alias: []const u8) bool {
        const mc = self.bindings.get(alias) orelse return false;
        const meta = self.modules.get(mc) orelse return false;
        return meta.exports.count() != 0;
    }

    /// `.duo` files that define `@comp.c.export` symbols. A direct-backend call
    /// into one of these lowers to a relocation, so the linker needs an object
    /// built from each file — without them the link fails on undefined
    /// `duo_*` symbols even though lowering fully succeeded. Modules with no
    /// exports contribute only folded constants and need no object.
    pub fn exportingModuleSources(
        self: *const Context,
        alloc: std.mem.Allocator,
        out: *std.ArrayListUnmanaged([]const u8),
    ) !void {
        var it = self.modules.iterator();
        while (it.next()) |e| {
            const meta = e.value_ptr;
            if (meta.exports.count() == 0) continue;
            const sp = meta.source_path orelse continue;
            for (out.items) |seen| {
                if (std.mem.eql(u8, seen, sp)) break;
            } else try out.append(alloc, sp);
        }
    }
};

pub fn collectFromModule(alloc: std.mem.Allocator, mod: *const ast.Module) !Context {
    var ctx: Context = .{};
    errdefer ctx.deinit(alloc);

    const ReqBinding = struct {
        alias: []const u8,
        val: *const ast.Expr,
    };

    _ = ReqBinding;
    // `req` is idiomatically bound inside the function that uses it — every
    // Pass 16 lexer proof writes `main(): i64  Token = req "..."`. Scanning only
    // `mod.body.stmts` missed those bindings entirely, so `Token.KIND_FUN` fell
    // through to a runtime `load_field` and the direct backend reported DNB007.
    // Walk function bodies too. Aliases stay in one module-wide map, matching the
    // existing design; a re-bound alias resolves to its most recent binding.
    try collectReqBindingsFromBlock(alloc, &ctx, &mod.body);
    try collectDottedCallsInBlock(alloc, &ctx, &mod.body);
    return ctx;
}

fn collectReqBindingsFromBlock(
    alloc: std.mem.Allocator,
    ctx: *Context,
    block: *const ast.Block,
) !void {
    for (block.stmts) |*stmt| {
        var alias: ?[]const u8 = null;
        var val: ?*const ast.Expr = null;
        switch (stmt.*) {
            .assign => |as| {
                if (as.targets.len == 1 and as.values.len == 1 and as.targets[0].* == .name) {
                    alias = as.targets[0].name.ident;
                    val = as.values[0];
                }
            },
            .local_decl => |ld| {
                if (ld.names.len == 1 and ld.inits.len == 1) {
                    alias = ld.names[0].ident;
                    val = ld.inits[0];
                }
            },
            .func_decl => |fd| try collectReqBindingsFromBlock(alloc, ctx, &fd.func.body),
            .do_block => |db| try collectReqBindingsFromBlock(alloc, ctx, &db.body),
            .while_loop => |ws| try collectReqBindingsFromBlock(alloc, ctx, &ws.body),
            else => {},
        }
        const a = alias orelse continue;
        const v = val orelse continue;
        // A module is bound two ways, and only one was recognised here.
        // `Token = req "std.compiler.token"` is a CALL; the ambient
        // `Token = std.compiler.token` is a dotted NAME, and it was invisible.
        // So `Token.KIND_FUN` had no module to fold from and reached the
        // backend as a record field access, dying on a stack slot that never
        // existed. The consumer side already worked — `lowerField` consults
        // `ctx.req.constant` — so this collector was the whole gap.
        var ambient = false;
        const path = reqPathFromExpr(v) orelse blk: {
            const p = ambientModulePath(alloc, v) orelse continue;
            ambient = true;
            break :blk p;
        };
        const mod_cname = try duo_module_names.moduleCName(alloc, path);
        // For the ambient spelling, require that the path actually names a
        // module FILE. `p.x` on a record local is also a dotted name, and
        // without this it would be recorded as a module binding — quietly
        // shadowing a real field access. The `req` spelling keeps its old
        // behaviour: it is an explicit declaration of intent, so a missing
        // file there stays a link-time error rather than a silent skip.
        if (ambient) {
            var probe = try loadModuleMeta(alloc, path, mod_cname);
            if (probe.source_path == null) {
                probe.deinit(alloc);
                alloc.free(mod_cname);
                continue;
            }
            const owned_alias = try alloc.dupe(u8, a);
            try ctx.bindings.put(alloc, owned_alias, mod_cname);
            if (ctx.modules.contains(mod_cname)) {
                probe.deinit(alloc);
                continue;
            }
            try ctx.modules.put(alloc, try alloc.dupe(u8, mod_cname), probe);
            continue;
        }
        const owned_alias = try alloc.dupe(u8, a);
        try ctx.bindings.put(alloc, owned_alias, mod_cname);
        if (ctx.modules.contains(mod_cname)) continue;
        const meta = try loadModuleMeta(alloc, path, mod_cname);
        try ctx.modules.put(alloc, try alloc.dupe(u8, mod_cname), meta);
    }
}

/// Flatten `a.b.c` to "a.b.c". Null for anything that is not a pure chain of
/// names, so an indexed or called segment cannot pass as a module path.
fn dottedPath(alloc: std.mem.Allocator, e: *const ast.Expr, out: *std.ArrayList(u8)) !bool {
    switch (e.*) {
        .name => |n| {
            try out.appendSlice(alloc, n.ident);
            return true;
        },
        .field => |f| {
            if (!try dottedPath(alloc, f.obj, out)) return false;
            try out.append(alloc, '.');
            try out.appendSlice(alloc, f.field);
            return true;
        },
        else => return false,
    }
}

/// Load the module named by a DOTTED CALLEE, e.g. `std.compiler.lexer.new(…)`.
///
/// Only `X = req "…"` bindings were ever collected, so an ambient dotted call
/// resolved against an empty map. The split is ambiguous — `std.compiler.lexer`
/// + `new`, or `std.compiler` + a nested `lexer.new` — and nothing in the AST
/// says which, so the rule is LONGEST PREFIX THAT LOADS, stated here rather
/// than discovered: a wrong split fails silently by simply not resolving.
fn collectDottedCallee(alloc: std.mem.Allocator, ctx: *Context, callee: *const ast.Expr) !void {
    if (callee.* != .field) return;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(alloc);
    if (!try dottedPath(alloc, callee.field.obj, &buf)) return;
    if (std.mem.indexOfScalar(u8, buf.items, '.') == null) return; // single name: the alias path handles it
    var path = buf.items;
    while (true) {
        const mod_cname = try duo_module_names.moduleCName(alloc, path);
        if (ctx.modules.contains(mod_cname)) {
            alloc.free(mod_cname);
            return;
        }
        if (loadModuleMeta(alloc, path, mod_cname)) |meta| {
            try ctx.modules.put(alloc, mod_cname, meta);
            return;
        } else |_| {
            alloc.free(mod_cname);
        }
        const cut = std.mem.lastIndexOfScalar(u8, path, '.') orelse return;
        path = path[0..cut];
        if (std.mem.indexOfScalar(u8, path, '.') == null) return;
    }
}

fn collectDottedCallsInBlock(alloc: std.mem.Allocator, ctx: *Context, block: *const ast.Block) !void {
    for (block.stmts) |*stmt| {
        switch (stmt.*) {
            .func_decl => |fd| try collectDottedCallsInBlock(alloc, ctx, &fd.func.body),
            .do_block => |db| try collectDottedCallsInBlock(alloc, ctx, &db.body),
            .while_loop => |ws| try collectDottedCallsInBlock(alloc, ctx, &ws.body),
            .local_decl => |ld| for (ld.inits) |e| {
                if (e.* == .call) try collectDottedCallee(alloc, ctx, e.call.func);
            },
            .assign => |as| for (as.values) |e| {
                if (e.* == .call) try collectDottedCallee(alloc, ctx, e.call.func);
            },
            .call_stmt => |cs| {
                if (cs.expr.* == .call) try collectDottedCallee(alloc, ctx, cs.expr.call.func);
            },
            .ret => |r| for (r.vals) |e| {
                if (e.* == .call) try collectDottedCallee(alloc, ctx, e.call.func);
            },
            else => {},
        }
    }
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

/// `Token = std.compiler.token` — a module named by a bare dotted path rather
/// than by `req`. Requires at least one dot, so a plain `X = Y` alias cannot
/// pass as a module path. The caller still checks that the path resolves to a
/// real file before trusting it.
fn ambientModulePath(alloc: std.mem.Allocator, e: *const ast.Expr) ?[]const u8 {
    if (e.* != .field) return null;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(alloc);
    const ok = dottedPath(alloc, e, &buf) catch return null;
    if (!ok) return null;
    if (std.mem.indexOfScalar(u8, buf.items, '.') == null) return null;
    return alloc.dupe(u8, buf.items) catch null;
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
    var found_path: ?[]const u8 = null;
    const prefixes = [_][]const u8{ "lib/std/", "lib/" };
    for (prefixes) |prefix| {
        for (source_suffixes) |suffix| {
            const path = std.fmt.bufPrint(&path_buf, "{s}{s}{s}", .{ prefix, rel_path, suffix }) catch continue;
            owned_source = Io.Dir.readFileAlloc(cwd, io, path, alloc, .unlimited) catch null;
            if (owned_source != null) {
                found_path = try alloc.dupe(u8, path);
                break;
            }
        }
        if (owned_source != null) break;
    }
    errdefer if (found_path) |fp| alloc.free(fp);
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
        .source_path = found_path,
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
        // Canonical Duo declares functions bare: `name(params) ... end`. The
        // `fun` keyword is optional, so a scanner that matched only `fun ` lost
        // every export the moment a module was written idiomatically — and the
        // direct backend then had no symbol to relocate against.
        const decl = if (std.mem.startsWith(u8, line, "fun "))
            std.mem.trim(u8, line["fun ".len..], " \t")
        else
            line;
        if (std.mem.indexOfScalar(u8, decl, '(')) |open_paren| {
            const field = std.mem.trim(u8, decl[0..open_paren], " \t");
            // `X = foo(1)` is a constant, not a declaration: its text before the
            // paren is not a bare identifier.
            if (isIdent(field)) {
                if (pending_export) |sym| {
                    const owned_field = try alloc.dupe(u8, field);
                    const owned_sym = try alloc.dupe(u8, sym);
                    try exports.put(alloc, owned_field, owned_sym);
                }
                pending_export = null;
                continue;
            }
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

test "native_req_support: canonical source precedes historical source" {
    try std.testing.expectEqualStrings(".id", source_suffixes[0]);
    try std.testing.expectEqualStrings(".duo", source_suffixes[1]);
    try std.testing.expectEqual(source_family.SourceLaw.idsem, source_family.sourceFacts("module.id").law);
    try std.testing.expectEqual(source_family.SourceProvenance.canonical, source_family.sourceFacts("module.id").provenance);
    try std.testing.expectEqual(source_family.SourceProvenance.historical, source_family.sourceFacts("module.duo").provenance);
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
