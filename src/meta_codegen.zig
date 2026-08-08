/// Compile-time metaprogramming hooks: concept sweeps, derive maps, cartesian products.
const std = @import("std");
const builtin = @import("builtin");
const ast = @import("ast.zig");
const sema = @import("sema.zig");
const types = @import("types.zig");
const comptime_eval = @import("comptime.zig");
const derive_eval = @import("derive_eval.zig");
const derive_registry = @import("derive_registry.zig");
const derive_bundles = @import("derive_bundles.zig");
const meta_directives = @import("meta_directives.zig");
const meta_module = @import("meta_module.zig");
const type_diff = @import("type_diff.zig");
const rewrite_rules = @import("rewrite_rules.zig");
const c_signatures = @import("c_signatures.zig");
const directives = @import("directives.zig");

const RT = types.ResolvedType;

pub const AliasMatch = struct {
    ad: *const ast.AliasDef,
    fields: []const types.FieldType,
};

pub const Host = struct {
    alloc: std.mem.Allocator,
    mod: ?*const ast.Module,
    record_aliases: *const std.StringHashMapUnmanaged(RT),
    alias_defs: *const std.StringHashMapUnmanaged(*const ast.AliasDef),
    concepts: ?*const std.StringHashMapUnmanaged(sema.ConceptInfo),
    bindings: comptime_eval.Bindings,
    options: comptime_eval.Options,
    /// Optional CodeGen pointer for expression-aware field introspection hooks.
    codegen_ctx: ?*anyopaque = null,
};

/// Heap-stable meta table for comptime callback invocation (matches comptimeEachHook).
fn metaCallbackTable(alloc: std.mem.Allocator, entries: []const comptime_eval.Value.TableEntry) !comptime_eval.Value {
    const owned = try alloc.dupe(comptime_eval.Value.TableEntry, entries);
    return .{ .table = owned };
}

pub fn splitConceptSpec(alloc: std.mem.Allocator, spec: []const u8) ![]const []const u8 {
    if (std.mem.indexOfScalar(u8, spec, '+') == null) {
        const single = try alloc.dupe(u8, std.mem.trim(u8, spec, " \t"));
        return try alloc.dupe([]const u8, &[_][]const u8{single});
    }
    var parts: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (parts.items) |p| alloc.free(p);
        parts.deinit(alloc);
    }
    var it = std.mem.splitScalar(u8, spec, '+');
    while (it.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t");
        if (trimmed.len == 0) continue;
        try parts.append(alloc, try alloc.dupe(u8, trimmed));
    }
    return try parts.toOwnedSlice(alloc);
}

pub fn aliasSatisfiesConcept(host: Host, ad: *const ast.AliasDef, concept_info: sema.ConceptInfo) bool {
    const rt = host.record_aliases.get(ad.name) orelse return false;
    if (rt != .table_type) return false;
    const fields = rt.table_type.fields;

    for (concept_info.required_fields) |req_field| {
        var found = false;
        for (fields) |rec_field| {
            if (std.mem.eql(u8, rec_field.name, req_field.name)) {
                if (req_field.typ != .any and !req_field.typ.eql(rec_field.typ)) {
                    found = false;
                } else {
                    found = true;
                }
                break;
            }
        }
        if (!found) return false;
    }

    for (concept_info.required_methods) |req_method| {
        var found = false;
        for (ad.methods) |m| {
            const mname = if (m.path.len > 0) m.path[m.path.len - 1] else "";
            if (std.mem.eql(u8, mname, req_method.name)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

pub fn aliasSatisfiesConceptSpec(host: Host, ad: *const ast.AliasDef, concept_spec: []const u8) bool {
    const concepts_map = host.concepts orelse return false;
    const names = splitConceptSpec(host.alloc, concept_spec) catch return false;
    defer {
        for (names) |n| host.alloc.free(n);
        host.alloc.free(names);
    }
    for (names) |cn| {
        const concept_info = concepts_map.get(cn) orelse return false;
        if (!aliasSatisfiesConcept(host, ad, concept_info)) return false;
    }
    return true;
}

pub const DeriveAllRule = struct {
    concept_spec: []const u8,
    derive_names: []const []const u8,
};

pub fn parseDeriveAllDirective(alloc: std.mem.Allocator, raw: []const u8) !?DeriveAllRule {
    var it = directives.attrArgs(raw);
    // A hand-rolled scanner here demanded `"` as the very first byte, so the
    // single-quoted spelling of a concept was dropped without a diagnostic.
    const first = it.next() orelse return null;
    if (!first.quoted or first.text.len == 0) return null;
    const concept_spec = try alloc.dupe(u8, first.text);
    errdefer alloc.free(concept_spec);

    const rest = std.mem.trim(u8, raw[it.pos..], " \t\r\n,");
    if (rest.len == 0) return .{ .concept_spec = concept_spec, .derive_names = &.{} };
    const derive_names = try derive_bundles.expandTraitsFromRawArgs(alloc, rest);
    return .{ .concept_spec = concept_spec, .derive_names = derive_names };
}

pub const OmniRule = struct {
    concept_a: []const u8,
    derive_names: []const []const u8,
    concept_b: []const u8,
};

/// `("ConceptA", Derive…, "ConceptB"[, "ConceptC"…])` — the one shape that
/// `@comp.omni`, `@comp.transcend`, `@comp.infinity` and `@comp.hyper` all
/// write, differing only in how many trailing concepts they take.
///
/// Four copies of this used to walk the raw text looking for the next `"` with
/// `mem.indexOf`, which is a SUBSTRING search: it cannot tell a quote that
/// opens the next concept from a quote inside the derive slot, and it rejects
/// the single-quoted spelling outright. Here the quoting is a property of a
/// TOKEN — `AttrArg.quoted` — so the derive run simply ends at the first
/// quoted argument.
const ConceptChain = struct {
    /// concepts[0] is the leading concept; [1..1+tail] are the trailing ones.
    concepts: [5][]const u8,
    derive_names: []const []const u8,
};

fn parseConceptChain(alloc: std.mem.Allocator, raw: []const u8, tail: usize) !?ConceptChain {
    std.debug.assert(tail + 1 <= 5);
    var args: [16]directives.AttrArg = undefined;
    var n: usize = 0;
    var it = directives.attrArgs(raw);
    while (it.next()) |arg| : (n += 1) {
        if (n == args.len) break;
        args[n] = arg;
    }
    if (n == 0 or !args[0].quoted or args[0].text.len == 0) return null;

    var i: usize = 1;
    while (i < n and !args[i].quoted) : (i += 1) {}
    const derive_count = i - 1;
    if (derive_count == 0) return null;
    if (n - i < tail) return null;

    var chain: ConceptChain = .{ .concepts = .{ "", "", "", "", "" }, .derive_names = &.{} };
    var owned: usize = 0;
    errdefer for (chain.concepts[0..owned]) |c| alloc.free(c);
    chain.concepts[0] = try alloc.dupe(u8, args[0].text);
    owned = 1;
    for (0..tail) |k| {
        if (args[i + k].text.len == 0) return null;
        chain.concepts[1 + k] = try alloc.dupe(u8, args[i + k].text);
        owned = 2 + k;
    }

    var seeds: std.ArrayListUnmanaged([]const u8) = .empty;
    defer seeds.deinit(alloc);
    for (args[1 .. 1 + derive_count]) |d| {
        if (d.text.len > 0) try seeds.append(alloc, d.text);
    }
    if (seeds.items.len == 0) return null;
    chain.derive_names = try derive_bundles.expandTraits(alloc, seeds.items);
    return chain;
}

pub const TranscendRule = struct {
    concept_a: []const u8,
    derive_names: []const []const u8,
    concept_b: []const u8,
    concept_c: []const u8,
};

/// Parse `@meta.transcend("ConceptA", Derive, "ConceptB", "ConceptC")` args.
pub fn parseTranscendDirective(alloc: std.mem.Allocator, raw: []const u8) !?TranscendRule {
    const chain = try parseConceptChain(alloc, raw, 2) orelse return null;
    return .{
        .concept_a = chain.concepts[0],
        .derive_names = chain.derive_names,
        .concept_b = chain.concepts[1],
        .concept_c = chain.concepts[2],
    };
}

/// Parse `@meta.emit.omni("ConceptA", Derive, "ConceptB")` directive args.
pub fn parseOmniDirective(alloc: std.mem.Allocator, raw: []const u8) !?OmniRule {
    const chain = try parseConceptChain(alloc, raw, 1) orelse return null;
    return .{
        .concept_a = chain.concepts[0],
        .derive_names = chain.derive_names,
        .concept_b = chain.concepts[1],
    };
}

pub fn collectDeriveAllRules(host: Host) ![]DeriveAllRule {
    var rules: std.ArrayListUnmanaged(DeriveAllRule) = .empty;
    errdefer {
        for (rules.items) |rule| {
            host.alloc.free(rule.concept_spec);
            for (rule.derive_names) |n| host.alloc.free(n);
            host.alloc.free(rule.derive_names);
        }
        rules.deinit(host.alloc);
    }
    const mod = host.mod orelse return rules.toOwnedSlice(host.alloc);
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .directive) continue;
        const attr_name = stmt.directive.attr.name;
        if (meta_module.directiveMatches(attr_name, "derive.all")) {
            const rule = try parseDeriveAllDirective(host.alloc, stmt.directive.attr.args orelse "") orelse continue;
            try rules.append(host.alloc, rule);
            continue;
        }
        // @meta.burst("ConceptA", Derive, "ConceptB") — derive.all + emit.omni in one directive.
        if (meta_module.directiveMatches(attr_name, "burst")) {
            const omni = try parseOmniDirective(host.alloc, stmt.directive.attr.args orelse "") orelse continue;
            defer {
                host.alloc.free(omni.concept_a);
                host.alloc.free(omni.concept_b);
            }
            const concept_spec = try host.alloc.dupe(u8, omni.concept_a);
            const derive_names = try host.alloc.dupe([]const u8, omni.derive_names);
            try rules.append(host.alloc, .{ .concept_spec = concept_spec, .derive_names = derive_names });
            continue;
        }
        if (meta_module.directiveMatches(attr_name, "transcend")) {
            const tr = try parseTranscendDirective(host.alloc, stmt.directive.attr.args orelse "") orelse continue;
            defer {
                host.alloc.free(tr.concept_a);
                host.alloc.free(tr.concept_b);
                host.alloc.free(tr.concept_c);
            }
            const concept_spec = try host.alloc.dupe(u8, tr.concept_a);
            const derive_names = try host.alloc.dupe([]const u8, tr.derive_names);
            try rules.append(host.alloc, .{ .concept_spec = concept_spec, .derive_names = derive_names });
            continue;
        }
        if (meta_module.directiveMatches(attr_name, "infinity")) {
            const inf = try parseInfinityDirective(host.alloc, stmt.directive.attr.args orelse "") orelse continue;
            defer {
                host.alloc.free(inf.concept_a);
                host.alloc.free(inf.concept_b);
                host.alloc.free(inf.concept_c);
                host.alloc.free(inf.concept_d);
            }
            const concept_spec = try host.alloc.dupe(u8, inf.concept_a);
            const derive_names = try host.alloc.dupe([]const u8, inf.derive_names);
            try rules.append(host.alloc, .{ .concept_spec = concept_spec, .derive_names = derive_names });
        }
    }
    return try rules.toOwnedSlice(host.alloc);
}

pub fn collectDeriveAllNamesForAlias(
    host: Host,
    ad: *const ast.AliasDef,
    rules: []const DeriveAllRule,
    out: *std.ArrayListUnmanaged([]const u8),
) !void {
    for (rules) |rule| {
        if (!aliasSatisfiesConceptSpec(host, ad, rule.concept_spec)) continue;
        for (rule.derive_names) |name| {
            try out.append(host.alloc, try host.alloc.dupe(u8, name));
        }
    }
}

fn collectMatchingTypes(
    host: Host,
    concept_spec: []const u8,
    out: *std.ArrayListUnmanaged(AliasMatch),
) !void {
    const mod = host.mod orelse return;
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .alias_def) continue;
        const ad = &stmt.alias_def;
        if (!aliasSatisfiesConceptSpec(host, ad, concept_spec)) continue;
        const rt = host.record_aliases.get(ad.name) orelse continue;
        if (rt != .table_type) continue;
        try out.append(host.alloc, .{ .ad = ad, .fields = rt.table_type.fields });
    }
}

/// Collect type names as strings. If record types match the concept spec,
/// use their names. If no matches, fall back to space-separated tokens in
/// the concept spec (for primitive type lists like "i64 f64 str").
/// This makes ALL combinators work with both declared types and primitive lists.
fn collectTypeNames(
    host: Host,
    concept_spec: []const u8,
    alloc: std.mem.Allocator,
) ![][]const u8 {
    var matches: std.ArrayListUnmanaged(AliasMatch) = .empty;
    defer matches.deinit(alloc);
    collectMatchingTypes(host, concept_spec, &matches) catch {};
    if (matches.items.len > 0) {
        const names = alloc.alloc([]const u8, matches.items.len) catch return error.OutOfMemory;
        for (matches.items, 0..) |m, i| names[i] = m.ad.name;
        return names;
    }
    // Fallback: space-separated tokens
    var tokens = std.mem.tokenizeScalar(u8, concept_spec, ' ');
    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    defer list.deinit(alloc);
    while (tokens.next()) |tok| {
        try list.append(alloc, tok);
    }
    return list.toOwnedSlice(alloc);
}

const ComptimeMapTask = struct {
    shared_alloc: std.mem.Allocator,
    entry: AliasMatch,
    callback: comptime_eval.Value,
    bindings: comptime_eval.Bindings,
    base_options: comptime_eval.Options,
    result: *?[]const u8,
};

fn comptimeMapWorker(task: *ComptimeMapTask) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const meta_value = derive_eval.metaValueFromFields(a, task.entry.ad.name, task.entry.fields) catch {
        return; // leave result null, same as original continue
    };

    var opts = task.base_options;
    opts.alloc = a;
    opts.comptime_cache = null; // shared cache is not thread-safe
    opts.persistent_cache_load_hook = null;
    opts.persistent_cache_store_hook = null;
    const piece = comptime_eval.callFunctionValue(task.callback, &.{meta_value}, task.bindings, opts) catch {
        task.result.* = std.fmt.allocPrint(task.shared_alloc, "{s};", .{task.entry.ad.name}) catch null;
        return;
    };

    if (piece == .string) {
        task.result.* = task.shared_alloc.dupe(u8, piece.string) catch null;
    }
}

pub fn comptimeMapHook(host: Host, concept: []const u8, callback: comptime_eval.Value, alloc: std.mem.Allocator) ?comptime_eval.Value {
    var matches: std.ArrayListUnmanaged(AliasMatch) = .empty;
    defer matches.deinit(alloc);
    collectMatchingTypes(host, concept, &matches) catch return null;

    if (matches.items.len == 0) {
        // Fallback: if no record types match, treat the concept spec as a
        // space-separated list of type name strings. Call the callback with
        // each name as a comptime_eval.Value string. This makes @comp.map
        // work with primitive type lists like "i64 f64 str" without requiring
        // declared record types. O(n) from a simple type name list.
        if (concept.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
        var tokens = std.mem.tokenizeScalar(u8, concept, ' ');
        var pieces: std.ArrayListUnmanaged([]const u8) = .empty;
        defer pieces.deinit(alloc);
        while (tokens.next()) |tok| {
            const piece = comptime_eval.callFunctionValue(callback, &.{.{ .string = tok }}, host.bindings, host.options) catch continue;
            if (piece == .string) {
                pieces.append(alloc, alloc.dupe(u8, piece.string) catch continue) catch continue;
            }
        }
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        for (pieces.items) |s| buf.appendSlice(alloc, s) catch return null;
        return .{ .string = buf.toOwnedSlice(alloc) catch return null };
    }

    const results = alloc.alloc(?[]const u8, matches.items.len) catch return null;
    defer {
        for (results) |r| if (r) |s| alloc.free(s);
        alloc.free(results);
    }
    @memset(results, null);

    const parallel = false;
    if (parallel) {
        const tasks = alloc.alloc(ComptimeMapTask, matches.items.len) catch return null;
        defer alloc.free(tasks);
        var threads: std.ArrayListUnmanaged(std.Thread) = .empty;
        defer threads.deinit(alloc);
        threads.ensureTotalCapacity(alloc, matches.items.len) catch return null;

        var i: usize = 0;
        while (i < matches.items.len) : (i += 1) {
            tasks[i] = .{
                .shared_alloc = alloc,
                .entry = matches.items[i],
                .callback = callback,
                .bindings = host.bindings,
                .base_options = host.options,
                .result = &results[i],
            };
            const t = std.Thread.spawn(.{}, comptimeMapWorker, .{&tasks[i]}) catch break;
            threads.appendAssumeCapacity(t);
        }

        for (threads.items) |t| t.join();

        while (i < matches.items.len) : (i += 1) {
            const entry = matches.items[i];
            const meta_value = derive_eval.metaValueFromFields(alloc, entry.ad.name, entry.fields) catch continue;
            const piece = comptime_eval.callFunctionValue(callback, &.{meta_value}, host.bindings, host.options) catch {
                results[i] = std.fmt.allocPrint(alloc, "{s};", .{entry.ad.name}) catch continue;
                continue;
            };
            if (piece == .string) results[i] = alloc.dupe(u8, piece.string) catch continue;
        }
    } else {
        for (matches.items, 0..) |entry, j| {
            const meta_value = derive_eval.metaValueFromFields(alloc, entry.ad.name, entry.fields) catch continue;
            const piece = comptime_eval.callFunctionValue(callback, &.{meta_value}, host.bindings, host.options) catch {
                results[j] = std.fmt.allocPrint(alloc, "{s};", .{entry.ad.name}) catch continue;
                continue;
            };
            if (piece == .string) results[j] = alloc.dupe(u8, piece.string) catch continue;
        }
    }

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);
    for (results) |r| {
        if (r) |s| buf.appendSlice(alloc, s) catch return null;
    }
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@comp.weave(module, concept, fn)` — concept sweep over a foreign module's types.
pub fn weaveHook(
    foreign: Host,
    source_module: []const u8,
    concept: []const u8,
    callback: comptime_eval.Value,
    bindings: comptime_eval.Bindings,
    options: comptime_eval.Options,
    alloc: std.mem.Allocator,
) ?comptime_eval.Value {
    var matches: std.ArrayListUnmanaged(AliasMatch) = .empty;
    defer matches.deinit(alloc);
    collectMatchingTypes(foreign, concept, &matches) catch return null;
    if (matches.items.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);
    const count: i64 = @intCast(matches.items.len);
    var index: i64 = 0;
    for (matches.items) |entry| {
        const meta_base = derive_eval.metaValueFromFields(alloc, entry.ad.name, entry.fields) catch continue;
        const owned_source = alloc.dupe(u8, source_module) catch continue;
        var entries: [5]comptime_eval.Value.TableEntry = .{
            .{ .name = "name", .val = meta_base.table[0].val },
            .{ .name = "fields", .val = meta_base.table[1].val },
            .{ .name = "source_module", .val = .{ .string = owned_source } },
            .{ .name = "index", .val = .{ .int = index } },
            .{ .name = "count", .val = .{ .int = count } },
        };
        const meta = metaCallbackTable(alloc, &entries) catch continue;
        defer alloc.free(meta.table);
        const piece = comptime_eval.callFunctionValue(callback, &.{meta}, bindings, options) catch continue;
        if (piece == .string) buf.appendSlice(alloc, piece.string) catch return null;
        index += 1;
    }
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

const DeriveMapTask = struct {
    shared_alloc: std.mem.Allocator,
    fn_value: comptime_eval.Value,
    entry: AliasMatch,
    bindings: comptime_eval.Bindings,
    base_options: comptime_eval.Options,
    result: *?[]const u8,
};

fn deriveMapWorker(task: *DeriveMapTask) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const meta_value = derive_eval.metaValueFromFields(a, task.entry.ad.name, task.entry.fields) catch {
        return;
    };

    var opts = task.base_options;
    opts.alloc = a;
    opts.comptime_cache = null; // shared cache is not thread-safe
    opts.persistent_cache_load_hook = null;
    opts.persistent_cache_store_hook = null;
    const piece = comptime_eval.callFunctionValue(task.fn_value, &.{meta_value}, task.bindings, opts) catch {
        task.result.* = std.fmt.allocPrint(task.shared_alloc, "{s};", .{task.entry.ad.name}) catch null;
        return;
    };

    if (piece == .string) {
        task.result.* = task.shared_alloc.dupe(u8, piece.string) catch null;
    }
}

fn applyNativeDeriveToMatches(
    derive_name: []const u8,
    matches: []const AliasMatch,
    buf: *std.ArrayListUnmanaged(u8),
    alloc: std.mem.Allocator,
) void {
    const native_fn = derive_registry.getNativeDerive(derive_name) orelse return;
    for (matches) |entry| {
        const meta = derive_eval.metadataFromFields(alloc, entry.ad.name, entry.fields) catch continue;
        const code = native_fn(alloc, meta) catch continue;
        defer alloc.free(code);
        buf.appendSlice(alloc, code) catch return;
        buf.append(alloc, '\n') catch return;
    }
}

pub fn deriveMapHook(host: Host, concept: []const u8, derive_raw: []const u8, alloc: std.mem.Allocator) ?comptime_eval.Value {
    meta_directives.initModuleDeriveRegistry(alloc);
    derive_registry.initNativeDeriveRegistry(alloc);

    const derive_names = derive_bundles.expandTraitsFromRawArgs(alloc, derive_raw) catch blk: {
        const single = derive_bundles.trimArg(derive_raw);
        if (single.len == 0) return null;
        break :blk alloc.dupe([]const u8, &[_][]const u8{single}) catch return null;
    };
    defer {
        for (derive_names) |n| alloc.free(n);
        alloc.free(derive_names);
    }

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    var matches: std.ArrayListUnmanaged(AliasMatch) = .empty;
    defer matches.deinit(alloc);
    collectMatchingTypes(host, concept, &matches) catch return null;

    for (derive_names) |derive_name| {
        // Fast path: native derive (no Lua eval, no Value.table)
        if (derive_registry.hasNativeDerive(derive_name)) {
            applyNativeDeriveToMatches(derive_name, matches.items, &buf, alloc);
            continue;
        }
        // User-defined derive path (requires Lua-compatible eval)
        if (derive_registry.isBuiltinDerive(derive_name)) continue;
        const macro = meta_directives.module_derive_registry.get(derive_name) orelse continue;
        const func_body = derive_eval.parseDeriveFunction(alloc, macro.func_source) catch continue;
        const fn_value = comptime_eval.funcValue(func_body, host.bindings, host.options) catch continue;

        const parallel = false;
        if (parallel) {
            const n = matches.items.len;
            const results = alloc.alloc(?[]const u8, n) catch continue;
            defer {
                for (results) |r| if (r) |s| alloc.free(s);
                alloc.free(results);
            }
            @memset(results, null);

            const tasks = alloc.alloc(DeriveMapTask, n) catch continue;
            defer alloc.free(tasks);
            var threads: std.ArrayListUnmanaged(std.Thread) = .empty;
            defer threads.deinit(alloc);
            threads.ensureTotalCapacity(alloc, n) catch continue;

            var i: usize = 0;
            while (i < n) : (i += 1) {
                tasks[i] = .{
                    .shared_alloc = alloc,
                    .fn_value = fn_value,
                    .entry = matches.items[i],
                    .bindings = host.bindings,
                    .base_options = host.options,
                    .result = &results[i],
                };
                const t = std.Thread.spawn(.{}, deriveMapWorker, .{&tasks[i]}) catch break;
                threads.appendAssumeCapacity(t);
            }

            for (threads.items) |t| t.join();

            while (i < n) : (i += 1) {
                const meta_value = derive_eval.metaValueFromFields(alloc, matches.items[i].ad.name, matches.items[i].fields) catch continue;
                const piece = comptime_eval.callFunctionValue(fn_value, &.{meta_value}, host.bindings, host.options) catch continue;
                if (piece == .string) results[i] = alloc.dupe(u8, piece.string) catch continue;
            }

            for (results) |r| {
                if (r) |s| buf.appendSlice(alloc, s) catch return null;
            }
        } else {
            for (matches.items) |entry| {
                const meta_value = derive_eval.metaValueFromFields(alloc, entry.ad.name, entry.fields) catch continue;
                const piece = comptime_eval.callFunctionValue(fn_value, &.{meta_value}, host.bindings, host.options) catch continue;
                if (piece == .string) buf.appendSlice(alloc, piece.string) catch return null;
            }
        }
        buf.append(alloc, '\n') catch return null;
    }

    if (buf.items.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@meta.expand(concept, derive[, map_fn])` — stack derive sweep + optional concept map in one call.
/// Output size is O(types × derives × fields) + O(types) when map_fn is provided.
pub fn expandHook(
    host: Host,
    concept: []const u8,
    derive_raw: []const u8,
    map_callback: ?comptime_eval.Value,
    alloc: std.mem.Allocator,
) ?comptime_eval.Value {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    if (deriveMapHook(host, concept, derive_raw, alloc)) |derive_result| {
        if (derive_result == .string and derive_result.string.len > 0) {
            buf.appendSlice(alloc, derive_result.string) catch return null;
        }
    }

    if (map_callback) |cb| {
        if (comptimeMapHook(host, concept, cb, alloc)) |map_result| {
            if (map_result == .string and map_result.string.len > 0) {
                if (buf.items.len > 0) buf.append(alloc, '\n') catch return null;
                buf.appendSlice(alloc, "/* @meta.sweep: ") catch return null;
                buf.appendSlice(alloc, map_result.string) catch return null;
                buf.appendSlice(alloc, " */\n") catch return null;
            }
        }
    }

    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@meta.ceiling(concept_a, derive, concept_b)` — O(types² × fields) derive product + O(types × fields) sweep.
pub fn ceilingHook(
    host: Host,
    concept_a: []const u8,
    derive_raw: []const u8,
    concept_b: []const u8,
    alloc: std.mem.Allocator,
) ?comptime_eval.Value {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    if (expandHook(host, concept_a, derive_raw, null, alloc)) |exp| {
        if (exp == .string and exp.string.len > 0) {
            buf.appendSlice(alloc, exp.string) catch return null;
        }
    }

    const derive_names = derive_bundles.expandTraitsFromRawArgs(alloc, derive_raw) catch blk: {
        const single = derive_bundles.trimArg(derive_raw);
        if (single.len == 0) return .{ .string = buf.toOwnedSlice(alloc) catch return null };
        break :blk alloc.dupe([]const u8, &[_][]const u8{single}) catch return null;
    };
    defer {
        for (derive_names) |n| alloc.free(n);
        alloc.free(derive_names);
    }
    if (derive_names.len == 0) return .{ .string = buf.toOwnedSlice(alloc) catch return null };

    if (deriveProductHook(host, concept_a, concept_b, derive_names[0], alloc)) |prod| {
        if (prod == .string and prod.string.len > 0) {
            if (buf.items.len > 0) buf.append(alloc, '\n') catch return null;
            buf.appendSlice(alloc, prod.string) catch return null;
        }
    }

    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// Module-level `@meta.burst` emit: cartesian derive product only (derive.all handles linear sweep).
pub fn burstEmitHook(
    host: Host,
    concept_a: []const u8,
    derive_raw: []const u8,
    concept_b: []const u8,
    alloc: std.mem.Allocator,
) ?comptime_eval.Value {
    const derive_names = derive_bundles.expandTraitsFromRawArgs(alloc, derive_raw) catch blk: {
        const single = derive_bundles.trimArg(derive_raw);
        if (single.len == 0) return null;
        break :blk alloc.dupe([]const u8, &[_][]const u8{single}) catch return null;
    };
    defer {
        for (derive_names) |n| alloc.free(n);
        alloc.free(derive_names);
    }
    if (derive_names.len == 0) return null;
    return deriveProductHook(host, concept_a, concept_b, derive_names[0], alloc);
}

/// `@meta.omni / @meta.stack(concept_a, derive, concept_b[, map_fn])` — ceiling + optional sweep comment.
/// One agent line → O(types × fields) + O(types² × fields) output.
pub fn omniHook(
    host: Host,
    concept_a: []const u8,
    derive_raw: []const u8,
    concept_b: []const u8,
    map_callback: ?comptime_eval.Value,
    alloc: std.mem.Allocator,
) ?comptime_eval.Value {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    if (ceilingHook(host, concept_a, derive_raw, concept_b, alloc)) |ceil| {
        if (ceil == .string and ceil.string.len > 0) {
            buf.appendSlice(alloc, ceil.string) catch return null;
        }
    }

    if (map_callback) |cb| {
        if (comptimeMapHook(host, concept_a, cb, alloc)) |map_result| {
            if (map_result == .string and map_result.string.len > 0) {
                if (buf.items.len > 0) buf.append(alloc, '\n') catch return null;
                buf.appendSlice(alloc, "/* @meta.sweep: ") catch return null;
                buf.appendSlice(alloc, map_result.string) catch return null;
                buf.appendSlice(alloc, " */\n") catch return null;
            }
        }
    }

    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

const ComptimeProductTask = struct {
    shared_alloc: std.mem.Allocator,
    callback: comptime_eval.Value,
    a: AliasMatch,
    b: AliasMatch,
    bindings: comptime_eval.Bindings,
    base_options: comptime_eval.Options,
    result: *?[]const u8,
};

fn comptimeProductWorker(task: *ComptimeProductTask) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const meta_a = derive_eval.metaValueFromFields(a, task.a.ad.name, task.a.fields) catch return;
    const meta_b = derive_eval.metaValueFromFields(a, task.b.ad.name, task.b.fields) catch return;

    var opts = task.base_options;
    opts.alloc = a;
    opts.comptime_cache_alloc = null;
    const piece = comptime_eval.callFunctionValue(task.callback, &.{ meta_a, meta_b }, task.bindings, opts) catch return;
    if (piece == .string) {
        task.result.* = task.shared_alloc.dupe(u8, piece.string) catch null;
    }
}

pub fn comptimeProductHook(host: Host, concept_a: []const u8, concept_b: []const u8, callback: comptime_eval.Value, alloc: std.mem.Allocator) ?comptime_eval.Value {
    var left: std.ArrayListUnmanaged(AliasMatch) = .empty;
    var right: std.ArrayListUnmanaged(AliasMatch) = .empty;
    defer left.deinit(alloc);
    defer right.deinit(alloc);
    collectMatchingTypes(host, concept_a, &left) catch return null;
    collectMatchingTypes(host, concept_b, &right) catch return null;

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    const n = left.items.len * right.items.len;
    // `std.Thread.spawn` is a hard `@compileError` on a single-threaded target,
    // so the fan-out has to be excluded at COMPTIME, not merely skipped at
    // runtime — wasm32-wasi baseline is single-threaded and this one call was
    // the last Zig-side blocker in the cross-target matrix (GAP-040). The
    // `else` branch below computes the same product serially.
    const parallel = !builtin.single_threaded and callback == .func and n > 1;
    if (parallel) {
        const results = alloc.alloc(?[]const u8, n) catch return null;
        defer {
            for (results) |r| if (r) |s| alloc.free(s);
            alloc.free(results);
        }
        @memset(results, null);

        const tasks = alloc.alloc(ComptimeProductTask, n) catch return null;
        defer alloc.free(tasks);

        var threads: std.ArrayListUnmanaged(std.Thread) = .empty;
        defer threads.deinit(alloc);
        threads.ensureTotalCapacity(alloc, n) catch return null;

        var i: usize = 0;
        for (left.items) |a| {
            for (right.items) |b| {
                tasks[i] = .{
                    .shared_alloc = alloc,
                    .callback = callback,
                    .a = a,
                    .b = b,
                    .bindings = host.bindings,
                    .base_options = host.options,
                    .result = &results[i],
                };
                const t = std.Thread.spawn(.{}, comptimeProductWorker, .{&tasks[i]}) catch break;
                threads.appendAssumeCapacity(t);
                i += 1;
            }
        }

        for (threads.items) |t| t.join();

        while (i < n) : (i += 1) {
            const meta_a = derive_eval.metaValueFromFields(alloc, tasks[i].a.ad.name, tasks[i].a.fields) catch continue;
            const meta_b = derive_eval.metaValueFromFields(alloc, tasks[i].b.ad.name, tasks[i].b.fields) catch continue;
            const piece = comptime_eval.callFunctionValue(callback, &.{ meta_a, meta_b }, host.bindings, host.options) catch continue;
            if (piece == .string) results[i] = alloc.dupe(u8, piece.string) catch continue;
        }

        for (results) |r| {
            if (r) |s| buf.appendSlice(alloc, s) catch return null;
        }
    } else {
        for (left.items) |a| {
            const meta_a = derive_eval.metaValueFromFields(alloc, a.ad.name, a.fields) catch continue;
            for (right.items) |b| {
                const meta_b = derive_eval.metaValueFromFields(alloc, b.ad.name, b.fields) catch continue;
                const piece = comptime_eval.callFunctionValue(callback, &.{ meta_a, meta_b }, host.bindings, host.options) catch continue;
                if (piece != .string) continue;
                buf.appendSlice(alloc, piece.string) catch return null;
            }
        }
    }

    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

fn pairMetaValue(alloc: std.mem.Allocator, left: comptime_eval.Value, right: comptime_eval.Value, left_name: []const u8, right_name: []const u8) !comptime_eval.Value {
    var name_buf: [256]u8 = undefined;
    const pair_name = std.fmt.bufPrint(&name_buf, "{s}_{s}", .{ left_name, right_name }) catch return error.OutOfMemory;
    const owned_name = try alloc.dupe(u8, pair_name);

    var entries: [3]comptime_eval.Value.TableEntry = .{
        .{ .name = "name", .val = .{ .string = owned_name } },
        .{ .name = "left", .val = left },
        .{ .name = "right", .val = right },
    };
    const owned = try alloc.dupe(comptime_eval.Value.TableEntry, &entries);
    return .{ .table = owned };
}

fn applyNativeDeriveToUniqueTypes(
    derive_name: []const u8,
    lists: []const std.ArrayListUnmanaged(AliasMatch),
    buf: *std.ArrayListUnmanaged(u8),
    alloc: std.mem.Allocator,
) void {
    const native_fn = derive_registry.getNativeDerive(derive_name) orelse return;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(alloc);
    for (lists) |list| {
        for (list.items) |entry| {
            const gop = seen.getOrPut(alloc, entry.ad.name) catch continue;
            if (gop.found_existing) continue;
            const meta = derive_eval.metadataFromFields(alloc, entry.ad.name, entry.fields) catch continue;
            const code = native_fn(alloc, meta) catch continue;
            defer alloc.free(code);
            buf.appendSlice(alloc, code) catch return;
            buf.append(alloc, '\n') catch return;
        }
    }
}

pub fn deriveProductHook(host: Host, concept_a: []const u8, concept_b: []const u8, derive_name: []const u8, alloc: std.mem.Allocator) ?comptime_eval.Value {
    meta_directives.initModuleDeriveRegistry(alloc);
    derive_registry.initNativeDeriveRegistry(alloc);

    var left: std.ArrayListUnmanaged(AliasMatch) = .empty;
    var right: std.ArrayListUnmanaged(AliasMatch) = .empty;
    defer left.deinit(alloc);
    defer right.deinit(alloc);
    collectMatchingTypes(host, concept_a, &left) catch return null;
    collectMatchingTypes(host, concept_b, &right) catch return null;

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    // Native derive fast path: apply once per unique type
    if (derive_registry.hasNativeDerive(derive_name)) {
        applyNativeDeriveToUniqueTypes(derive_name, &[_]std.ArrayListUnmanaged(AliasMatch){ left, right }, &buf, alloc);
        if (buf.items.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
        return .{ .string = buf.toOwnedSlice(alloc) catch return null };
    }

    const macro = meta_directives.module_derive_registry.get(derive_name) orelse return null;

    for (left.items) |a| {
        const meta_a = derive_eval.metaValueFromFields(alloc, a.ad.name, a.fields) catch continue;
        for (right.items) |b| {
            const meta_b = derive_eval.metaValueFromFields(alloc, b.ad.name, b.fields) catch continue;
            const pair = pairMetaValue(alloc, meta_a, meta_b, a.ad.name, b.ad.name) catch continue;
            const c_code = derive_eval.evalDeriveMacroValue(alloc, macro.func_source, pair, host.bindings, host.options) catch continue;
            defer alloc.free(c_code);
            buf.appendSlice(alloc, c_code) catch return null;
            buf.append(alloc, '\n') catch return null;
        }
    }

    if (buf.items.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

fn tripleMetaValue(
    alloc: std.mem.Allocator,
    left: comptime_eval.Value,
    mid: comptime_eval.Value,
    right: comptime_eval.Value,
    left_name: []const u8,
    mid_name: []const u8,
    right_name: []const u8,
) !comptime_eval.Value {
    var name_buf: [384]u8 = undefined;
    const triple_name = std.fmt.bufPrint(&name_buf, "{s}_{s}_{s}", .{ left_name, mid_name, right_name }) catch return error.OutOfMemory;
    const owned_name = try alloc.dupe(u8, triple_name);

    var entries: [4]comptime_eval.Value.TableEntry = .{
        .{ .name = "name", .val = .{ .string = owned_name } },
        .{ .name = "left", .val = left },
        .{ .name = "mid", .val = mid },
        .{ .name = "right", .val = right },
    };
    const owned = try alloc.dupe(comptime_eval.Value.TableEntry, &entries);
    return .{ .table = owned };
}

/// `@meta.tensor(concept_a, concept_b, concept_c, fn)` — O(types³) callback sweep.
pub fn comptimeTensorHook(
    host: Host,
    concept_a: []const u8,
    concept_b: []const u8,
    concept_c: []const u8,
    callback: comptime_eval.Value,
    alloc: std.mem.Allocator,
) ?comptime_eval.Value {
    var a_list: std.ArrayListUnmanaged(AliasMatch) = .empty;
    var b_list: std.ArrayListUnmanaged(AliasMatch) = .empty;
    var c_list: std.ArrayListUnmanaged(AliasMatch) = .empty;
    defer a_list.deinit(alloc);
    defer b_list.deinit(alloc);
    defer c_list.deinit(alloc);
    collectMatchingTypes(host, concept_a, &a_list) catch return null;
    collectMatchingTypes(host, concept_b, &b_list) catch return null;
    collectMatchingTypes(host, concept_c, &c_list) catch return null;

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    for (a_list.items) |a| {
        const meta_a = derive_eval.metaValueFromFields(alloc, a.ad.name, a.fields) catch continue;
        for (b_list.items) |b| {
            const meta_b = derive_eval.metaValueFromFields(alloc, b.ad.name, b.fields) catch continue;
            for (c_list.items) |c| {
                const meta_c = derive_eval.metaValueFromFields(alloc, c.ad.name, c.fields) catch continue;
                const piece = comptime_eval.callFunctionValue(callback, &.{ meta_a, meta_b, meta_c }, host.bindings, host.options) catch continue;
                if (piece != .string) continue;
                buf.appendSlice(alloc, piece.string) catch return null;
            }
        }
    }

    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@meta.derive.tensor(concept_a, concept_b, concept_c, Derive)` — O(types³ × fields).
pub fn deriveTensorHook(
    host: Host,
    concept_a: []const u8,
    concept_b: []const u8,
    concept_c: []const u8,
    derive_name: []const u8,
    alloc: std.mem.Allocator,
) ?comptime_eval.Value {
    meta_directives.initModuleDeriveRegistry(alloc);
    derive_registry.initNativeDeriveRegistry(alloc);

    var a_list: std.ArrayListUnmanaged(AliasMatch) = .empty;
    var b_list: std.ArrayListUnmanaged(AliasMatch) = .empty;
    var c_list: std.ArrayListUnmanaged(AliasMatch) = .empty;
    defer a_list.deinit(alloc);
    defer b_list.deinit(alloc);
    defer c_list.deinit(alloc);
    collectMatchingTypes(host, concept_a, &a_list) catch return null;
    collectMatchingTypes(host, concept_b, &b_list) catch return null;
    collectMatchingTypes(host, concept_c, &c_list) catch return null;

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    // Native derive fast path: apply once per unique type across all concepts
    if (derive_registry.hasNativeDerive(derive_name)) {
        applyNativeDeriveToUniqueTypes(derive_name, &[_]std.ArrayListUnmanaged(AliasMatch){ a_list, b_list, c_list }, &buf, alloc);
        if (buf.items.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
        return .{ .string = buf.toOwnedSlice(alloc) catch return null };
    }

    const macro = meta_directives.module_derive_registry.get(derive_name) orelse return null;

    for (a_list.items) |a| {
        const meta_a = derive_eval.metaValueFromFields(alloc, a.ad.name, a.fields) catch continue;
        for (b_list.items) |b| {
            const meta_b = derive_eval.metaValueFromFields(alloc, b.ad.name, b.fields) catch continue;
            for (c_list.items) |c| {
                const meta_c = derive_eval.metaValueFromFields(alloc, c.ad.name, c.fields) catch continue;
                const triple = tripleMetaValue(alloc, meta_a, meta_b, meta_c, a.ad.name, b.ad.name, c.ad.name) catch continue;
                const c_code = derive_eval.evalDeriveMacroValue(alloc, macro.func_source, triple, host.bindings, host.options) catch continue;
                defer alloc.free(c_code);
                buf.appendSlice(alloc, c_code) catch return null;
                buf.append(alloc, '\n') catch return null;
            }
        }
    }

    if (buf.items.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@meta.transcend(concept_a, derive, concept_b, concept_c)` — omni + cubic derive product.
pub fn transcendHook(
    host: Host,
    concept_a: []const u8,
    derive_raw: []const u8,
    concept_b: []const u8,
    concept_c: []const u8,
    map_callback: ?comptime_eval.Value,
    alloc: std.mem.Allocator,
) ?comptime_eval.Value {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    if (omniHook(host, concept_a, derive_raw, concept_b, map_callback, alloc)) |omni| {
        if (omni == .string and omni.string.len > 0) {
            buf.appendSlice(alloc, omni.string) catch return null;
        }
    }

    const derive_names = derive_bundles.expandTraitsFromRawArgs(alloc, derive_raw) catch return .{ .string = buf.toOwnedSlice(alloc) catch return null };
    defer {
        for (derive_names) |n| alloc.free(n);
        alloc.free(derive_names);
    }
    if (derive_names.len > 0) {
        if (deriveTensorHook(host, concept_a, concept_b, concept_c, derive_names[0], alloc)) |tensor| {
            if (tensor == .string and tensor.string.len > 0) {
                if (buf.items.len > 0) buf.append(alloc, '\n') catch return null;
                buf.appendSlice(alloc, tensor.string) catch return null;
            }
        }
    }

    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// Module `@meta.transcend` emit: quadratic product + cubic derive (derive.all handles linear).
pub fn transcendEmitHook(
    host: Host,
    concept_a: []const u8,
    derive_raw: []const u8,
    concept_b: []const u8,
    concept_c: []const u8,
    alloc: std.mem.Allocator,
) ?comptime_eval.Value {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    if (burstEmitHook(host, concept_a, derive_raw, concept_b, alloc)) |prod| {
        if (prod == .string and prod.string.len > 0) {
            buf.appendSlice(alloc, prod.string) catch return null;
        }
    }

    const derive_names = derive_bundles.expandTraitsFromRawArgs(alloc, derive_raw) catch return .{ .string = buf.toOwnedSlice(alloc) catch return null };
    defer {
        for (derive_names) |n| alloc.free(n);
        alloc.free(derive_names);
    }
    if (derive_names.len > 0) {
        if (deriveTensorHook(host, concept_a, concept_b, concept_c, derive_names[0], alloc)) |tensor| {
            if (tensor == .string and tensor.string.len > 0) {
                if (buf.items.len > 0) buf.append(alloc, '\n') catch return null;
                buf.appendSlice(alloc, tensor.string) catch return null;
            }
        }
    }

    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

pub const HyperRule = struct {
    concept_a: []const u8,
    derive_names: []const []const u8,
    concept_b: []const u8,
    concept_c: []const u8,
    concept_d: []const u8,
    concept_e: []const u8,
};

pub const InfinityRule = struct {
    concept_a: []const u8,
    derive_names: []const []const u8,
    concept_b: []const u8,
    concept_c: []const u8,
    concept_d: []const u8,
};

/// Parse `@meta.infinity("ConceptA", Derive, "ConceptB", "ConceptC", "ConceptD")` args.
pub fn parseInfinityDirective(alloc: std.mem.Allocator, raw: []const u8) !?InfinityRule {
    const chain = try parseConceptChain(alloc, raw, 3) orelse return null;
    return .{
        .concept_a = chain.concepts[0],
        .derive_names = chain.derive_names,
        .concept_b = chain.concepts[1],
        .concept_c = chain.concepts[2],
        .concept_d = chain.concepts[3],
    };
}

/// Parse `@meta.hyper("ConceptA", Derive, "ConceptB", "ConceptC", "ConceptD", "ConceptE")` args.
pub fn parseHyperDirective(alloc: std.mem.Allocator, raw: []const u8) !?HyperRule {
    const chain = try parseConceptChain(alloc, raw, 4) orelse return null;
    return .{
        .concept_a = chain.concepts[0],
        .derive_names = chain.derive_names,
        .concept_b = chain.concepts[1],
        .concept_c = chain.concepts[2],
        .concept_d = chain.concepts[3],
        .concept_e = chain.concepts[4],
    };
}

pub fn conceptsFromTable(alloc: std.mem.Allocator, table_val: comptime_eval.Value) ?[]const []const u8 {
    if (table_val != .table) return null;
    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer list.deinit(alloc);
    for (table_val.table) |entry| {
        const v = entry.val;
        if (v != .string) continue;
        list.append(alloc, v.string) catch return null;
    }
    if (list.items.len == 0) return null;
    return list.toOwnedSlice(alloc) catch null;
}

fn nfoldDeriveMeta(
    alloc: std.mem.Allocator,
    metas: []const comptime_eval.Value,
    type_names: []const []const u8,
) !comptime_eval.Value {
    var name_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer name_buf.deinit(alloc);
    for (type_names, 0..) |n, i| {
        if (i > 0) try name_buf.append(alloc, '_');
        try name_buf.appendSlice(alloc, n);
    }
    const owned_name = try name_buf.toOwnedSlice(alloc);

    const part_entries = try alloc.alloc(comptime_eval.Value.TableEntry, metas.len);
    for (metas, 0..) |m, i| {
        part_entries[i] = .{ .key = .{ .int = @intCast(i + 1) }, .val = m };
    }

    var entries: std.ArrayListUnmanaged(comptime_eval.Value.TableEntry) = .empty;
    errdefer entries.deinit(alloc);
    try entries.append(alloc, .{ .name = "name", .val = .{ .string = owned_name } });
    try entries.append(alloc, .{ .name = "parts", .val = .{ .table = part_entries } });
    if (metas.len >= 1) try entries.append(alloc, .{ .name = "left", .val = metas[0] });
    if (metas.len >= 2) try entries.append(alloc, .{ .name = "right", .val = metas[metas.len - 1] });
    if (metas.len >= 3) try entries.append(alloc, .{ .name = "mid", .val = metas[1] });
    return .{ .table = try entries.toOwnedSlice(alloc) };
}

fn nfoldCallbackRecurse(
    host: Host,
    lists: []std.ArrayListUnmanaged(AliasMatch),
    k: usize,
    depth: usize,
    scratch_metas: []comptime_eval.Value,
    callback: comptime_eval.Value,
    buf: *std.ArrayListUnmanaged(u8),
    alloc: std.mem.Allocator,
) void {
    if (depth == k) {
        const piece = comptime_eval.callFunctionValue(callback, scratch_metas[0..k], host.bindings, host.options) catch return;
        if (piece != .string) return;
        buf.appendSlice(alloc, piece.string) catch return;
        return;
    }
    for (lists[depth].items) |match| {
        scratch_metas[depth] = derive_eval.metaValueFromFields(alloc, match.ad.name, match.fields) catch continue;
        nfoldCallbackRecurse(host, lists, k, depth + 1, scratch_metas, callback, buf, alloc);
    }
}

fn nfoldDeriveRecurse(
    host: Host,
    lists: []std.ArrayListUnmanaged(AliasMatch),
    k: usize,
    depth: usize,
    scratch_metas: []comptime_eval.Value,
    scratch_names: [][]const u8,
    macro_source: []const u8,
    buf: *std.ArrayListUnmanaged(u8),
    alloc: std.mem.Allocator,
) void {
    if (depth == k) {
        const bundle = nfoldDeriveMeta(alloc, scratch_metas[0..k], scratch_names[0..k]) catch return;
        const c_code = derive_eval.evalDeriveMacroValue(alloc, macro_source, bundle, host.bindings, host.options) catch return;
        defer alloc.free(c_code);
        buf.appendSlice(alloc, c_code) catch return;
        buf.append(alloc, '\n') catch return;
        return;
    }
    for (lists[depth].items) |match| {
        scratch_metas[depth] = derive_eval.metaValueFromFields(alloc, match.ad.name, match.fields) catch continue;
        scratch_names[depth] = match.ad.name;
        nfoldDeriveRecurse(host, lists, k, depth + 1, scratch_metas, scratch_names, macro_source, buf, alloc);
    }
}

/// `@meta.nfold({ "ConceptA", "ConceptB", ... }, fn)` — O(types^k) callback sweep.
pub fn comptimeNfoldHook(
    host: Host,
    concepts: []const []const u8,
    callback: comptime_eval.Value,
    alloc: std.mem.Allocator,
) ?comptime_eval.Value {
    if (concepts.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
    const lists = alloc.alloc(std.ArrayListUnmanaged(AliasMatch), concepts.len) catch return null;
    defer {
        for (lists) |*l| l.deinit(alloc);
        alloc.free(lists);
    }
    for (concepts, lists) |cn, *list| {
        list.* = .empty;
        collectMatchingTypes(host, cn, list) catch return null;
    }

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    const scratch = alloc.alloc(comptime_eval.Value, concepts.len) catch return null;
    defer alloc.free(scratch);

    nfoldCallbackRecurse(host, lists, concepts.len, 0, scratch, callback, &buf, alloc);
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@meta.derive.nfold({ "ConceptA", ... }, Derive)` — O(types^k × fields).
pub fn deriveNfoldHook(
    host: Host,
    concepts: []const []const u8,
    derive_name: []const u8,
    alloc: std.mem.Allocator,
) ?comptime_eval.Value {
    if (concepts.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
    meta_directives.initModuleDeriveRegistry(alloc);
    derive_registry.initNativeDeriveRegistry(alloc);

    const lists = alloc.alloc(std.ArrayListUnmanaged(AliasMatch), concepts.len) catch return null;
    defer {
        for (lists) |*l| l.deinit(alloc);
        alloc.free(lists);
    }
    for (concepts, lists) |cn, *list| {
        list.* = .empty;
        collectMatchingTypes(host, cn, list) catch return null;
    }

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    // Native derive fast path: apply once per unique type across all concepts
    if (derive_registry.hasNativeDerive(derive_name)) {
        applyNativeDeriveToUniqueTypes(derive_name, lists, &buf, alloc);
        if (buf.items.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
        return .{ .string = buf.toOwnedSlice(alloc) catch return null };
    }

    const macro = meta_directives.module_derive_registry.get(derive_name) orelse return null;

    const scratch_metas = alloc.alloc(comptime_eval.Value, concepts.len) catch return null;
    defer alloc.free(scratch_metas);
    const scratch_names = alloc.alloc([]const u8, concepts.len) catch return null;
    defer alloc.free(scratch_names);

    nfoldDeriveRecurse(host, lists, concepts.len, 0, scratch_metas, scratch_names, macro.func_source, &buf, alloc);
    if (buf.items.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@meta.infinity(concept_a, derive, concept_b, concept_c, concept_d)` — transcend + quartic derive.
pub fn infinityHook(
    host: Host,
    concept_a: []const u8,
    derive_raw: []const u8,
    concept_b: []const u8,
    concept_c: []const u8,
    concept_d: []const u8,
    map_callback: ?comptime_eval.Value,
    alloc: std.mem.Allocator,
) ?comptime_eval.Value {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    if (transcendHook(host, concept_a, derive_raw, concept_b, concept_c, map_callback, alloc)) |tr| {
        if (tr == .string and tr.string.len > 0) buf.appendSlice(alloc, tr.string) catch return null;
    }

    const concepts = [_][]const u8{ concept_a, concept_b, concept_c, concept_d };
    const derive_names = derive_bundles.expandTraitsFromRawArgs(alloc, derive_raw) catch return .{ .string = buf.toOwnedSlice(alloc) catch return null };
    defer {
        for (derive_names) |n| alloc.free(n);
        alloc.free(derive_names);
    }
    if (derive_names.len > 0) {
        if (deriveNfoldHook(host, &concepts, derive_names[0], alloc)) |nf| {
            if (nf == .string and nf.string.len > 0) {
                if (buf.items.len > 0) buf.append(alloc, '\n') catch return null;
                buf.appendSlice(alloc, nf.string) catch return null;
            }
        }
    }
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// Module `@meta.infinity` emit: transcend emit + quartic derive.nfold.
pub fn infinityEmitHook(
    host: Host,
    concept_a: []const u8,
    derive_raw: []const u8,
    concept_b: []const u8,
    concept_c: []const u8,
    concept_d: []const u8,
    alloc: std.mem.Allocator,
) ?comptime_eval.Value {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    if (transcendEmitHook(host, concept_a, derive_raw, concept_b, concept_c, alloc)) |tr| {
        if (tr == .string and tr.string.len > 0) buf.appendSlice(alloc, tr.string) catch return null;
    }

    const concepts = [_][]const u8{ concept_a, concept_b, concept_c, concept_d };
    const derive_names = derive_bundles.expandTraitsFromRawArgs(alloc, derive_raw) catch return .{ .string = buf.toOwnedSlice(alloc) catch return null };
    defer {
        for (derive_names) |n| alloc.free(n);
        alloc.free(derive_names);
    }
    if (derive_names.len > 0) {
        if (deriveNfoldHook(host, &concepts, derive_names[0], alloc)) |nf| {
            if (nf == .string and nf.string.len > 0) {
                if (buf.items.len > 0) buf.append(alloc, '\n') catch return null;
                buf.appendSlice(alloc, nf.string) catch return null;
            }
        }
    }
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@meta.hyper(concept_a, derive, concept_b, concept_c, concept_d, concept_e)` — O(n^5)
/// transcend (omni+tensor) + 5-way derive.nfold. Pushes the ladder one step beyond infinity.
pub fn hyperHook(
    host: Host,
    concept_a: []const u8,
    derive_raw: []const u8,
    concept_b: []const u8,
    concept_c: []const u8,
    concept_d: []const u8,
    concept_e: []const u8,
    map_callback: ?comptime_eval.Value,
    alloc: std.mem.Allocator,
) ?comptime_eval.Value {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    if (transcendHook(host, concept_a, derive_raw, concept_b, concept_c, map_callback, alloc)) |tr| {
        if (tr == .string and tr.string.len > 0) buf.appendSlice(alloc, tr.string) catch return null;
    }

    const concepts = [_][]const u8{ concept_a, concept_b, concept_c, concept_d, concept_e };
    const derive_names = derive_bundles.expandTraitsFromRawArgs(alloc, derive_raw) catch return .{ .string = buf.toOwnedSlice(alloc) catch return null };
    defer {
        for (derive_names) |n| alloc.free(n);
        alloc.free(derive_names);
    }
    if (derive_names.len > 0) {
        if (deriveNfoldHook(host, &concepts, derive_names[0], alloc)) |nf| {
            if (nf == .string and nf.string.len > 0) {
                if (buf.items.len > 0) buf.append(alloc, '\n') catch return null;
                buf.appendSlice(alloc, nf.string) catch return null;
            }
        }
    }
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// Module `@meta.hyper` emit: transcend emit + 5-way derive.nfold.
pub fn hyperEmitHook(
    host: Host,
    concept_a: []const u8,
    derive_raw: []const u8,
    concept_b: []const u8,
    concept_c: []const u8,
    concept_d: []const u8,
    concept_e: []const u8,
    alloc: std.mem.Allocator,
) ?comptime_eval.Value {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    if (transcendEmitHook(host, concept_a, derive_raw, concept_b, concept_c, alloc)) |tr| {
        if (tr == .string and tr.string.len > 0) buf.appendSlice(alloc, tr.string) catch return null;
    }

    const concepts = [_][]const u8{ concept_a, concept_b, concept_c, concept_d, concept_e };
    const derive_names = derive_bundles.expandTraitsFromRawArgs(alloc, derive_raw) catch return .{ .string = buf.toOwnedSlice(alloc) catch return null };
    defer {
        for (derive_names) |n| alloc.free(n);
        alloc.free(derive_names);
    }
    if (derive_names.len > 0) {
        if (deriveNfoldHook(host, &concepts, derive_names[0], alloc)) |nf| {
            if (nf == .string and nf.string.len > 0) {
                if (buf.items.len > 0) buf.append(alloc, '\n') catch return null;
                buf.appendSlice(alloc, nf.string) catch return null;
            }
        }
    }
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@meta.tower(concepts, derive)` — O(n^k) derive.nfold with dynamic k (k up to 16).
/// `concepts` is a table of concept name strings. Equivalent to `@meta.derive.nfold`
/// but accepts table form for programmatic construction.
pub fn deriveTowerHook(
    host: Host,
    concepts: []const []const u8,
    derive_name: []const u8,
    alloc: std.mem.Allocator,
) ?comptime_eval.Value {
    if (concepts.len > 16) return null;
    return deriveNfoldHook(host, concepts, derive_name, alloc);
}

// ─────────────────────────────────────────────────────────────────────────────
// Exponential combinators: power-set (2^n) and permutation (n!)
//
// These are the canonical *truly* exponential enumerations: a single source
// line produces 2^n (or n!) generated C fragments. They complete the scaling
// ladder above the fixed-k cartesian products (product/tensor/nfold). All
// generated output is native C — no lua_Value intermediaries at runtime.
// ─────────────────────────────────────────────────────────────────────────────

/// Cap to keep compile times sane: 2^24 subsets ≈ 16M fragments is the hard ceiling.
const MAX_POWERSET_SIZE: usize = 24;
/// Permutations blow up as n!; cap the type count (10! ≈ 3.6M, 12! ≈ 479M).
const MAX_PERMUTE_SIZE: usize = 10;

/// Build a comptime meta table describing a subset of types for `@meta.power`.
/// Layout mirrors nfoldDeriveMeta: { name="A_B", parts={A,B}, count=2, mask=0b11, left=A, right=B }.
fn subsetMeta(
    alloc: std.mem.Allocator,
    matches: []const AliasMatch,
    indices: []const usize,
    mask: usize,
) !comptime_eval.Value {
    var name_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer name_buf.deinit(alloc);
    for (indices, 0..) |idx, i| {
        if (i > 0) try name_buf.append(alloc, '_');
        try name_buf.appendSlice(alloc, matches[idx].ad.name);
    }
    const owned_name = try name_buf.toOwnedSlice(alloc);

    const part_entries = try alloc.alloc(comptime_eval.Value.TableEntry, indices.len);
    for (indices, 0..) |idx, i| {
        const m = derive_eval.metaValueFromFields(alloc, matches[idx].ad.name, matches[idx].fields) catch return error.OutOfMemory;
        part_entries[i] = .{ .key = .{ .int = @intCast(i + 1) }, .val = m };
    }

    var entries: std.ArrayListUnmanaged(comptime_eval.Value.TableEntry) = .empty;
    try entries.append(alloc, .{ .name = "name", .val = .{ .string = owned_name } });
    try entries.append(alloc, .{ .name = "parts", .val = .{ .table = part_entries } });
    try entries.append(alloc, .{ .name = "count", .val = .{ .int = @intCast(indices.len) } });
    try entries.append(alloc, .{ .name = "mask", .val = .{ .int = @intCast(mask) } });
    if (indices.len >= 1) try entries.append(alloc, .{ .name = "left", .val = part_entries[0].val });
    if (indices.len >= 2) try entries.append(alloc, .{ .name = "right", .val = part_entries[indices.len - 1].val });
    return .{ .table = try entries.toOwnedSlice(alloc) };
}

/// Like subsetMeta but works with type name strings (no record fields).
/// Used when @comp.power etc. fall back to primitive type name lists.
fn subsetMetaFromNames(
    alloc: std.mem.Allocator,
    type_names: []const []const u8,
    indices: []const usize,
    mask: usize,
) !comptime_eval.Value {
    var name_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer name_buf.deinit(alloc);
    for (indices, 0..) |idx, i| {
        if (i > 0) try name_buf.append(alloc, '_');
        try name_buf.appendSlice(alloc, type_names[idx]);
    }
    const owned_name = try name_buf.toOwnedSlice(alloc);

    const part_entries = try alloc.alloc(comptime_eval.Value.TableEntry, indices.len);
    for (indices, 0..) |idx, i| {
        part_entries[i] = .{
            .key = .{ .int = @intCast(i + 1) },
            .val = .{ .string = type_names[idx] },
        };
    }

    var entries: std.ArrayListUnmanaged(comptime_eval.Value.TableEntry) = .empty;
    try entries.append(alloc, .{ .name = "name", .val = .{ .string = owned_name } });
    try entries.append(alloc, .{ .name = "parts", .val = .{ .table = part_entries } });
    try entries.append(alloc, .{ .name = "count", .val = .{ .int = @intCast(indices.len) } });
    try entries.append(alloc, .{ .name = "mask", .val = .{ .int = @intCast(mask) } });
    if (indices.len >= 1) try entries.append(alloc, .{ .name = "left", .val = part_entries[0].val });
    if (indices.len >= 2) try entries.append(alloc, .{ .name = "right", .val = part_entries[indices.len - 1].val });
    return .{ .table = try entries.toOwnedSlice(alloc) };
}

/// `@meta.power(concept, fn)` — invoke `fn(subset_meta)` once per non-empty subset
/// of the matching types. Output size is O(2^n). Returns concatenated fragments.
pub fn comptimePowerHook(host: Host, concept: []const u8, callback: comptime_eval.Value, alloc: std.mem.Allocator) ?comptime_eval.Value {
    const type_names = collectTypeNames(host, concept, alloc) catch return null;
    defer if (type_names.len > 0) alloc.free(type_names);

    if (type_names.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
    if (type_names.len > MAX_POWERSET_SIZE) return null;

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    const n = type_names.len;
    const total: usize = @as(usize, 1) << @intCast(n);
    const scratch = alloc.alloc(usize, n) catch return null;
    defer alloc.free(scratch);

    // Iterate over all non-empty subsets via bitmasks 1..2^n-1.
    var mask: usize = 1;
    while (mask < total) : (mask += 1) {
        var len: usize = 0;
        var bit: usize = 0;
        while (bit < n) : (bit += 1) {
            if ((mask & (@as(usize, 1) << @intCast(bit))) != 0) {
                scratch[len] = bit;
                len += 1;
            }
        }
        const subset = subsetMetaFromNames(alloc, type_names, scratch[0..len], mask) catch continue;
        const piece = comptime_eval.callFunctionValue(callback, &.{subset}, host.bindings, host.options) catch continue;
        if (piece == .string) buf.appendSlice(alloc, piece.string) catch return null;
    }

    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@meta.derive.power(concept, DeriveName)` — apply a derive macro to every
/// non-empty subset of matching types. Output size is O(2^n × fields).
pub fn derivePowerHook(host: Host, concept: []const u8, derive_name: []const u8, alloc: std.mem.Allocator) ?comptime_eval.Value {
    meta_directives.initModuleDeriveRegistry(alloc);
    derive_registry.initNativeDeriveRegistry(alloc);

    var matches: std.ArrayListUnmanaged(AliasMatch) = .empty;
    defer matches.deinit(alloc);
    collectMatchingTypes(host, concept, &matches) catch return null;

    if (matches.items.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
    if (matches.items.len > MAX_POWERSET_SIZE) return null;

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    // Native derive fast path: apply once per unique type (avoids O(2^n) eval)
    if (derive_registry.hasNativeDerive(derive_name)) {
        applyNativeDeriveToUniqueTypes(derive_name, &[_]std.ArrayListUnmanaged(AliasMatch){matches}, &buf, alloc);
        if (buf.items.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
        return .{ .string = buf.toOwnedSlice(alloc) catch return null };
    }

    const macro = meta_directives.module_derive_registry.get(derive_name) orelse return null;

    const n = matches.items.len;
    const total: usize = @as(usize, 1) << @intCast(n);
    const scratch = alloc.alloc(usize, n) catch return null;
    defer alloc.free(scratch);

    var mask: usize = 1;
    while (mask < total) : (mask += 1) {
        var len: usize = 0;
        var bit: usize = 0;
        while (bit < n) : (bit += 1) {
            if ((mask & (@as(usize, 1) << @intCast(bit))) != 0) {
                scratch[len] = bit;
                len += 1;
            }
        }
        const subset = subsetMeta(alloc, matches.items, scratch[0..len], mask) catch continue;
        const c_code = derive_eval.evalDeriveMacroValue(alloc, macro.func_source, subset, host.bindings, host.options) catch continue;
        defer alloc.free(c_code);
        buf.appendSlice(alloc, c_code) catch return null;
        buf.append(alloc, '\n') catch return null;
    }

    if (buf.items.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

fn nextCombination(indices: []usize, n: usize) bool {
    if (indices.len == 0) return false;
    var i = indices.len;
    while (i > 0) {
        i -= 1;
        const max_at_i = n - indices.len + i;
        if (indices[i] < max_at_i) {
            indices[i] += 1;
            var j = i + 1;
            while (j < indices.len) : (j += 1) {
                indices[j] = indices[j - 1] + 1;
            }
            return true;
        }
    }
    return false;
}

fn combinationMask(indices: []const usize) usize {
    var mask: usize = 0;
    for (indices) |idx| {
        mask |= @as(usize, 1) << @intCast(idx);
    }
    return mask;
}

/// `@meta.choose(concept, k, fn)` — invoke `fn(combo_meta)` once per fixed-size
/// k-subset of the matching types. Output size is O(n choose k), which gives a
/// controlled exponential rung between product/tensor/nfold and full powersets.
pub fn comptimeChooseHook(host: Host, concept: []const u8, choose_k: usize, callback: comptime_eval.Value, alloc: std.mem.Allocator) ?comptime_eval.Value {
    var matches: std.ArrayListUnmanaged(AliasMatch) = .empty;
    defer matches.deinit(alloc);
    collectMatchingTypes(host, concept, &matches) catch return null;

    if (matches.items.len == 0 or choose_k == 0 or choose_k > matches.items.len) {
        return .{ .string = alloc.dupe(u8, "") catch return null };
    }
    if (matches.items.len > MAX_POWERSET_SIZE) return null;

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    const indices = alloc.alloc(usize, choose_k) catch return null;
    defer alloc.free(indices);
    for (0..choose_k) |i| indices[i] = i;

    while (true) {
        const subset = subsetMeta(alloc, matches.items, indices, combinationMask(indices)) catch return null;
        const piece = comptime_eval.callFunctionValue(callback, &.{subset}, host.bindings, host.options) catch comptime_eval.Value.unavailable;
        if (piece == .string) buf.appendSlice(alloc, piece.string) catch return null;
        if (!nextCombination(indices, matches.items.len)) break;
    }

    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@meta.derive.choose(concept, k, DeriveName)` — apply a derive macro to every
/// fixed-size k-subset. Output size is O(n choose k × fields).
pub fn deriveChooseHook(host: Host, concept: []const u8, choose_k: usize, derive_name: []const u8, alloc: std.mem.Allocator) ?comptime_eval.Value {
    meta_directives.initModuleDeriveRegistry(alloc);
    derive_registry.initNativeDeriveRegistry(alloc);

    var matches: std.ArrayListUnmanaged(AliasMatch) = .empty;
    defer matches.deinit(alloc);
    collectMatchingTypes(host, concept, &matches) catch return null;

    if (matches.items.len == 0 or choose_k == 0 or choose_k > matches.items.len) {
        return .{ .string = alloc.dupe(u8, "") catch return null };
    }
    if (matches.items.len > MAX_POWERSET_SIZE) return null;

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    if (derive_registry.hasNativeDerive(derive_name)) {
        applyNativeDeriveToUniqueTypes(derive_name, &[_]std.ArrayListUnmanaged(AliasMatch){matches}, &buf, alloc);
        if (buf.items.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
        return .{ .string = buf.toOwnedSlice(alloc) catch return null };
    }

    const macro = meta_directives.module_derive_registry.get(derive_name) orelse return null;
    const indices = alloc.alloc(usize, choose_k) catch return null;
    defer alloc.free(indices);
    for (0..choose_k) |i| indices[i] = i;

    while (true) {
        const subset = subsetMeta(alloc, matches.items, indices, combinationMask(indices)) catch return null;
        const c_code = derive_eval.evalDeriveMacroValue(alloc, macro.func_source, subset, host.bindings, host.options) catch null;
        if (c_code) |code| {
            defer alloc.free(code);
            if (code.len > 0) {
                buf.appendSlice(alloc, code) catch return null;
                buf.append(alloc, '\n') catch return null;
            }
        }
        if (!nextCombination(indices, matches.items.len)) break;
    }

    if (buf.items.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@meta.permute(concept, fn)` — invoke `fn(ordered_meta)` once per permutation
/// of the matching types. Output size is O(n!). Uses Heap's algorithm.
pub fn comptimePermuteHook(host: Host, concept: []const u8, callback: comptime_eval.Value, alloc: std.mem.Allocator) ?comptime_eval.Value {
    var matches: std.ArrayListUnmanaged(AliasMatch) = .empty;
    defer matches.deinit(alloc);
    collectMatchingTypes(host, concept, &matches) catch return null;

    if (matches.items.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
    if (matches.items.len > MAX_PERMUTE_SIZE) return null;

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    const n = matches.items.len;
    // Work on an index permutation buffer initialized to identity.
    const perm = alloc.alloc(usize, n) catch return null;
    defer alloc.free(perm);
    for (0..n) |i| perm[i] = i;

    // Heap's algorithm (iterative) generates all n! permutations.
    const stack = alloc.alloc(usize, n) catch return null;
    defer alloc.free(stack);
    @memset(stack, 0);

    var idx: usize = 0;
    while (true) {
        // Emit current permutation.
        const subset = subsetMeta(alloc, matches.items, perm[0..n], 0) catch {
            if (idx == 0) return null;
            break;
        };
        const piece = if (comptime_eval.callFunctionValue(callback, &.{subset}, host.bindings, host.options)) |p| p else |_| comptime_eval.Value.unavailable;
        if (piece == .string) buf.appendSlice(alloc, piece.string) catch return null;

        if (idx == 0 and n == 1) break; // single element: one permutation only

        // Advance Heap's algorithm.
        while (idx < n) {
            if (stack[idx] < idx) {
                if (idx % 2 == 0) {
                    const tmp = perm[0];
                    perm[0] = perm[idx];
                    perm[idx] = tmp;
                } else {
                    const tmp = perm[stack[idx]];
                    perm[stack[idx]] = perm[idx];
                    perm[idx] = tmp;
                }
                stack[idx] += 1;
                idx = 0;
                break;
            } else {
                stack[idx] = 0;
                idx += 1;
            }
        }
        if (idx >= n) break;
    }

    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}
/// `@meta.each(source, fn)` — universal composition glue. Splits a comptime string
/// (the concatenated output of any inner @meta.* combinator) into fragments on `;`
/// and newlines, then invokes `fn` once per fragment with a meta table
/// `{ name = fragment, index = 0-based, count = total }`, concatenating the returns.
///
/// This closes the combinator algebra: the output of @meta.map / @meta.power /
/// @meta.product / etc. can be nested, filtered, or re-expanded by a follow-up
/// callback, so a single declaration can chain multiple exponential stages.
/// Comptime-only — emits native C, never a lua_Value at runtime.
pub fn comptimeEachHook(host: Host, source: []const u8, callback: comptime_eval.Value, alloc: std.mem.Allocator) ?comptime_eval.Value {
    const ws = " \t\r";
    // First pass: count non-empty fragments so `count` is known up front.
    var count: i64 = 0;
    {
        var i: usize = 0;
        while (i < source.len) {
            while (i < source.len and (source[i] == ' ' or source[i] == '\t' or source[i] == '\r' or source[i] == ';' or source[i] == '\n')) i += 1;
            if (i >= source.len) break;
            count += 1;
            while (i < source.len and source[i] != ';' and source[i] != '\n') i += 1;
        }
    }
    if (count == 0) return .{ .string = alloc.dupe(u8, "") catch return null };

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    var index: i64 = 0;
    var i: usize = 0;
    while (i < source.len) {
        while (i < source.len and (source[i] == ' ' or source[i] == '\t' or source[i] == '\r' or source[i] == ';' or source[i] == '\n')) i += 1;
        if (i >= source.len) break;
        const start = i;
        while (i < source.len and source[i] != ';' and source[i] != '\n') i += 1;
        const frag = std.mem.trim(u8, source[start..i], ws);
        if (frag.len == 0) continue;

        const owned_name = alloc.dupe(u8, frag) catch return null;
        var entries: [3]comptime_eval.Value.TableEntry = .{
            .{ .name = "name", .val = .{ .string = owned_name } },
            .{ .name = "index", .val = .{ .int = index } },
            .{ .name = "count", .val = .{ .int = count } },
        };
        const owned_entries = alloc.dupe(comptime_eval.Value.TableEntry, &entries) catch return null;
        const meta_val: comptime_eval.Value = .{ .table = owned_entries };

        const piece = comptime_eval.callFunctionValue(callback, &.{meta_val}, host.bindings, host.options) catch {
            index += 1;
            continue;
        };
        if (piece == .string) buf.appendSlice(alloc, piece.string) catch return null;
        index += 1;
    }

    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@comp.match(patterns, callback)` — compile-time pattern-match codegen.
/// Splits the pattern spec on `|` and calls the callback for each alternative,
/// passing a table with {pattern, index, count}. The callback returns a string
/// fragment for each pattern, and all fragments are concatenated.
///
/// This is the "switch/case of codegen" — one declarative line produces N
/// specialized branches. Composes with @comp.each, @comp.burst, etc.
/// Comptime-only — folds to native C string, never `lua_Value`.
///
/// Example: `@comp.match("i32|i64|f64", fun(m) "typedef " .. m.pattern .. " variant_" .. m.index .. ";\n" end)`
/// → `typedef i32 variant_0;\ntypedef i64 variant_1;\ntypedef f64 variant_2;\n`
pub fn comptimeMatchHook(host: Host, patterns: []const u8, callback: comptime_eval.Value, alloc: std.mem.Allocator) ?comptime_eval.Value {
    // Split on `|` — each alternative is a pattern to match against.
    var alts: std.ArrayListUnmanaged([]const u8) = .empty;
    defer alts.deinit(alloc);
    {
        var start: usize = 0;
        var i: usize = 0;
        while (i < patterns.len) : (i += 1) {
            if (patterns[i] == '|') {
                const frag = std.mem.trim(u8, patterns[start..i], " \t\r\n");
                if (frag.len > 0) alts.append(alloc, frag) catch return null;
                start = i + 1;
            }
        }
        if (start < patterns.len) {
            const frag = std.mem.trim(u8, patterns[start..], " \t\r\n");
            if (frag.len > 0) alts.append(alloc, frag) catch return null;
        }
    }
    const count: i64 = @intCast(alts.items.len);
    if (count == 0) return .{ .string = alloc.dupe(u8, "") catch return null };

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    var index: i64 = 0;
    for (alts.items) |alt| {
        const owned_pattern = alloc.dupe(u8, alt) catch return null;
        var entries: [3]comptime_eval.Value.TableEntry = .{
            .{ .name = "pattern", .val = .{ .string = owned_pattern } },
            .{ .name = "index", .val = .{ .int = index } },
            .{ .name = "count", .val = .{ .int = count } },
        };
        const owned_entries = alloc.dupe(comptime_eval.Value.TableEntry, &entries) catch return null;
        const meta_val: comptime_eval.Value = .{ .table = owned_entries };

        const piece = comptime_eval.callFunctionValue(callback, &.{meta_val}, host.bindings, host.options) catch {
            index += 1;
            continue;
        };
        if (piece == .string) buf.appendSlice(alloc, piece.string) catch return null;
        index += 1;
    }

    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@comp.tabulate(count, callback)` — compile-time lookup table generator.
/// Calls the callback for each index 0..count-1, passing {index, count}.
/// Concatenates all callback outputs into one native C string (comma-separated).
///
/// This is the "unrolled loop of codegen" — replaces runtime array initialization
/// with compile-time computed static values. O(1) author input → O(count) output.
/// Comptime-only — folds to native C string, never `lua_Value`.
///
/// Example: `@comp.tabulate(16, fun(i) tostring(i * i) end)` → "0,1,4,9,16,25,36,49,64,81,100,121,144,169,196,225"
pub fn comptimeTabulateHook(host: Host, count: i64, callback: comptime_eval.Value, alloc: std.mem.Allocator) ?comptime_eval.Value {
    if (count <= 0) return .{ .string = alloc.dupe(u8, "") catch return null };

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    var index: i64 = 0;
    while (index < count) : (index += 1) {
        var entries: [2]comptime_eval.Value.TableEntry = .{
            .{ .name = "index", .val = .{ .int = index } },
            .{ .name = "count", .val = .{ .int = count } },
        };
        const owned_entries = alloc.dupe(comptime_eval.Value.TableEntry, &entries) catch return null;
        const meta_val: comptime_eval.Value = .{ .table = owned_entries };

        const piece = comptime_eval.callFunctionValue(callback, &.{meta_val}, host.bindings, host.options) catch {
            continue;
        };
        if (piece == .string) {
            if (index > 0) buf.appendSlice(alloc, ",") catch return null;
            buf.appendSlice(alloc, piece.string) catch return null;
        }
    }

    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@comp.interpolate(template, vars)` — compile-time string interpolation.
/// Takes a template string with `{name}` placeholders and a table of
/// {name: value} mappings. Substitutes all placeholders at compile time,
/// producing a native C string. Unknown placeholders are left as-is.
///
/// This is the "code template injection" combinator — write a C/Duo template
/// with comptime-evaluated holes. O(template_size) per call. Comptime-only.
///
/// Example: `@comp.interpolate("int64_t {name}(int64_t a) { return a + {delta}; }", {name="add_one", delta=1})`
/// → "int64_t add_one(int64_t a) { return a + 1; }"
pub fn comptimeInterpolateHook(host: Host, template: []const u8, vars: comptime_eval.Value, alloc: std.mem.Allocator) ?comptime_eval.Value {
    if (vars != .table) return .{ .string = alloc.dupe(u8, template) catch return null };

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    var i: usize = 0;
    while (i < template.len) {
        if (template[i] == '{') {
            // Look for closing }
            const start = i + 1;
            var j = start;
            while (j < template.len and template[j] != '}') j += 1;
            if (j < template.len) {
                // Only treat as a placeholder if the content is a valid
                // identifier (alphanumeric + underscore, no spaces/special).
                // This avoids matching C code braces like `{ return x; }`.
                const var_name = template[start..j];
                const is_valid_ident = var_name.len > 0 and blk: {
                    for (var_name) |c| {
                        if (!std.ascii.isAlphanumeric(c) and c != '_') break :blk false;
                    }
                    break :blk true;
                };
                if (is_valid_ident) {
                    var found = false;
                    for (vars.table) |entry| {
                        if (entry.name) |ename| {
                            if (std.mem.eql(u8, ename, var_name)) {
                                switch (entry.val) {
                                    .string => |s| buf.appendSlice(alloc, s) catch return null,
                                    .int => |n| {
                                        var num_buf: [32]u8 = undefined;
                                        const s = std.fmt.bufPrint(&num_buf, "{d}", .{n}) catch break;
                                        buf.appendSlice(alloc, s) catch return null;
                                    },
                                    .float => |f| {
                                        var num_buf: [32]u8 = undefined;
                                        const s = std.fmt.bufPrint(&num_buf, "{e}", .{f}) catch break;
                                        buf.appendSlice(alloc, s) catch return null;
                                    },
                                    .bool => |b| buf.appendSlice(alloc, if (b) "true" else "false") catch return null,
                                    else => buf.appendSlice(alloc, "nil") catch return null,
                                }
                                found = true;
                                break;
                            }
                        }
                    }
                    if (!found) {
                        buf.appendSlice(alloc, template[i .. j + 1]) catch return null;
                    }
                    i = j + 1;
                    continue;
                }
                // Not a valid identifier — output the { literally
                buf.append(alloc, template[i]) catch return null;
                i += 1;
                continue;
            } else {
                // No closing } found — output rest literally
                buf.appendSlice(alloc, template[i..]) catch return null;
                break;
            }
        }
        buf.append(alloc, template[i]) catch return null;
        i += 1;
    }

    _ = host;
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@comp.zip(spec_a, spec_b, callback)` — compile-time cartesian zip codegen.
/// Splits two pipe-separated specs, calls callback for every (a, b) pair,
/// passing {a, b, index, count}. Concatenates all outputs.
///
/// O(n*m) from one line — quadratic combinator. The callback decides
/// what code to generate for each pair. Comptime-only (no lua_Value).
///
/// Example: `@comp.zip("i32|i64", "add|sub", fun(p) p.a .. "_" .. p.b .. " " end)`
/// → "i32_add i32_sub i64_add i64_sub "
pub fn comptimeZipHook(host: Host, spec_a: []const u8, spec_b: []const u8, callback: comptime_eval.Value, alloc: std.mem.Allocator) ?comptime_eval.Value {
    // Split spec_a on |
    var alts_a: std.ArrayListUnmanaged([]const u8) = .empty;
    defer alts_a.deinit(alloc);
    {
        var start: usize = 0;
        var i: usize = 0;
        while (i < spec_a.len) : (i += 1) {
            if (spec_a[i] == '|') {
                const frag = std.mem.trim(u8, spec_a[start..i], " \t\r\n");
                if (frag.len > 0) alts_a.append(alloc, frag) catch return null;
                start = i + 1;
            }
        }
        if (start < spec_a.len) {
            const frag = std.mem.trim(u8, spec_a[start..], " \t\r\n");
            if (frag.len > 0) alts_a.append(alloc, frag) catch return null;
        }
    }
    // Split spec_b on |
    var alts_b: std.ArrayListUnmanaged([]const u8) = .empty;
    defer alts_b.deinit(alloc);
    {
        var start: usize = 0;
        var i: usize = 0;
        while (i < spec_b.len) : (i += 1) {
            if (spec_b[i] == '|') {
                const frag = std.mem.trim(u8, spec_b[start..i], " \t\r\n");
                if (frag.len > 0) alts_b.append(alloc, frag) catch return null;
                start = i + 1;
            }
        }
        if (start < spec_b.len) {
            const frag = std.mem.trim(u8, spec_b[start..], " \t\r\n");
            if (frag.len > 0) alts_b.append(alloc, frag) catch return null;
        }
    }
    const total: i64 = @intCast(alts_a.items.len * alts_b.items.len);
    if (total == 0) return .{ .string = alloc.dupe(u8, "") catch return null };

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    var index: i64 = 0;
    for (alts_a.items) |a| {
        for (alts_b.items) |b| {
            const owned_a = alloc.dupe(u8, a) catch return null;
            const owned_b = alloc.dupe(u8, b) catch return null;
            var entries: [4]comptime_eval.Value.TableEntry = .{
                .{ .name = "a", .val = .{ .string = owned_a } },
                .{ .name = "b", .val = .{ .string = owned_b } },
                .{ .name = "index", .val = .{ .int = index } },
                .{ .name = "count", .val = .{ .int = total } },
            };
            const owned_entries = alloc.dupe(comptime_eval.Value.TableEntry, &entries) catch return null;
            const meta_val: comptime_eval.Value = .{ .table = owned_entries };

            const piece = comptime_eval.callFunctionValue(callback, &.{meta_val}, host.bindings, host.options) catch {
                index += 1;
                continue;
            };
            if (piece == .string) buf.appendSlice(alloc, piece.string) catch return null;
            index += 1;
        }
    }

    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@comp.fixpoint(initial, fn[, max_iter])` — iterate a generator callback until
/// convergence (output == input) or max_iter reached. The ONLY unbounded combinator:
/// O(1) author input → O(max_iter) output. The callback receives a table with
/// {input: string, iteration: i64, converged: bool} and returns a table with
/// {output: string, continue: bool}. All outputs are concatenated into a single
/// string result. Comptime-only — folds to native C string, never `lua_Value`.
pub fn comptimeFixpointHook(host: Host, initial: []const u8, callback: comptime_eval.Value, max_iter: usize, alloc: std.mem.Allocator) ?comptime_eval.Value {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    var current: []const u8 = initial;
    var owned_current: ?[]u8 = null;
    defer if (owned_current) |s| alloc.free(s);

    var iteration: i64 = 0;
    var iter: usize = 0;
    while (iter < max_iter) : (iter += 1) {
        // Build the callback argument table: {input, iteration, converged}
        const input_owned = alloc.dupe(u8, current) catch return null;
        // We'll free input_owned after the call; but the table holds a reference.
        // Use a defer-free pattern: allocate, use, then free after call.
        var entries: [3]comptime_eval.Value.TableEntry = .{
            .{ .name = "input", .val = .{ .string = input_owned } },
            .{ .name = "iteration", .val = .{ .int = iteration } },
            .{ .name = "converged", .val = .{ .bool = iter > 0 and std.mem.eql(u8, current, initial) } },
        };
        const owned_entries = alloc.dupe(comptime_eval.Value.TableEntry, &entries) catch {
            alloc.free(input_owned);
            return null;
        };
        const meta_val: comptime_eval.Value = .{ .table = owned_entries };

        const result = comptime_eval.callFunctionValue(callback, &.{meta_val}, host.bindings, host.options) catch {
            alloc.free(owned_entries);
            alloc.free(input_owned);
            break;
        };

        // Extract output and continue from the returned table
        var output: ?[]const u8 = null;
        var should_continue: bool = false;
        if (result == .table) {
            for (result.table) |entry| {
                if (entry.name) |ename| {
                    if (std.mem.eql(u8, ename, "output") and entry.val == .string) {
                        output = entry.val.string;
                    } else if (std.mem.eql(u8, ename, "continue") and entry.val == .bool) {
                        should_continue = entry.val.bool;
                    }
                }
            }
        } else if (result == .string) {
            // If callback returns a plain string, treat it as output with continue=true
            output = result.string;
            should_continue = true;
        }

        // Clean up the input table allocations
        alloc.free(owned_entries);
        alloc.free(input_owned);

        const out_str = output orelse break;

        // Append this iteration's output to the result buffer
        buf.appendSlice(alloc, out_str) catch return null;

        // Check convergence: output == input means we've reached a fixed point
        const converged = std.mem.eql(u8, out_str, current);

        // Clean up previous owned_current if any
        if (owned_current) |s| {
            alloc.free(s);
            owned_current = null;
        }

        // Prepare for next iteration: current = out_str (need to own it since it may be from callback)
        owned_current = alloc.dupe(u8, out_str) catch return null;
        current = owned_current.?;

        iteration += 1;

        // Stop conditions: callback says stop, converged, or max_iter reached
        if (!should_continue or converged) break;
    }

    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@comp.fanout(seed, fn[, depth])` — tree-shaped generative expansion.
/// Each iteration applies the callback to ALL fragments from the previous
/// iteration, splitting results by newlines. O(branch^depth) output from O(1)
/// input. The callback receives a table with {fragment: string, depth: i64,
/// index: i64} and returns a string (which may contain multiple fragments
/// separated by newlines). After depth levels, all fragments are joined with
/// newlines. Comptime-only — folds to native C string, never `lua_Value`.
pub fn comptimeFanoutHook(host: Host, seed: []const u8, callback: comptime_eval.Value, depth: usize, alloc: std.mem.Allocator) ?comptime_eval.Value {
    // Start with a single fragment: the seed
    var fragments: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (fragments.items) |f| alloc.free(f);
        fragments.deinit(alloc);
    }

    // Seed fragment — allocate a copy so we can free uniformly later
    const seed_copy = alloc.dupe(u8, seed) catch return null;
    fragments.append(alloc, seed_copy) catch {
        alloc.free(seed_copy);
        return null;
    };

    var current_depth: i64 = 0;
    while (current_depth < @as(i64, @intCast(depth))) : (current_depth += 1) {
        var next_fragments: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer {
            for (next_fragments.items) |f| alloc.free(f);
            next_fragments.deinit(alloc);
        }

        var idx: i64 = 0;
        for (fragments.items) |frag| {
            // Build the callback argument table: {fragment, depth, index}
            const frag_owned = alloc.dupe(u8, frag) catch {
                for (next_fragments.items) |f| alloc.free(f);
                next_fragments.deinit(alloc);
                return null;
            };
            var entries: [3]comptime_eval.Value.TableEntry = .{
                .{ .name = "fragment", .val = .{ .string = frag_owned } },
                .{ .name = "depth", .val = .{ .int = current_depth } },
                .{ .name = "index", .val = .{ .int = idx } },
            };
            const owned_entries = alloc.dupe(comptime_eval.Value.TableEntry, &entries) catch {
                alloc.free(frag_owned);
                for (next_fragments.items) |f| alloc.free(f);
                next_fragments.deinit(alloc);
                return null;
            };
            const meta_val: comptime_eval.Value = .{ .table = owned_entries };

            const result = comptime_eval.callFunctionValue(callback, &.{meta_val}, host.bindings, host.options) catch {
                alloc.free(owned_entries);
                alloc.free(frag_owned);
                for (next_fragments.items) |f| alloc.free(f);
                next_fragments.deinit(alloc);
                return null;
            };

            // Clean up the table allocations
            alloc.free(owned_entries);
            alloc.free(frag_owned);

            // Extract the returned string
            const result_str: ?[]const u8 = switch (result) {
                .string => result.string,
                else => null,
            };

            if (result_str) |str| {
                // Split by newlines and add each sub-fragment to next_fragments
                var split_it = std.mem.splitScalar(u8, str, '\n');
                while (split_it.next()) |line| {
                    if (line.len == 0) continue; // skip empty lines
                    const line_owned = alloc.dupe(u8, line) catch {
                        for (next_fragments.items) |f| alloc.free(f);
                        next_fragments.deinit(alloc);
                        return null;
                    };
                    next_fragments.append(alloc, line_owned) catch {
                        alloc.free(line_owned);
                        for (next_fragments.items) |f| alloc.free(f);
                        next_fragments.deinit(alloc);
                        return null;
                    };
                }
            }

            idx += 1;
        }

        // Replace fragments with next_fragments
        for (fragments.items) |f| alloc.free(f);
        fragments.clearRetainingCapacity();
        // Move ownership: copy items from next_fragments to fragments
        fragments.appendSlice(alloc, next_fragments.items) catch {
            for (next_fragments.items) |f| alloc.free(f);
            next_fragments.deinit(alloc);
            return null;
        };
        // Don't free items in next_fragments since ownership transferred
        next_fragments.clearRetainingCapacity();
        next_fragments.deinit(alloc);

        if (fragments.items.len == 0) break;
    }

    // Join all fragments with newlines
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    for (fragments.items, 0..) |frag, i| {
        if (i > 0) buf.append(alloc, '\n') catch return null;
        buf.appendSlice(alloc, frag) catch return null;
    }

    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

/// `@meta.derive.permute(concept, DeriveName)` — apply a derive macro to every
/// permutation of matching types. Output size is O(n! × fields).
pub fn derivePermuteHook(host: Host, concept: []const u8, derive_name: []const u8, alloc: std.mem.Allocator) ?comptime_eval.Value {
    meta_directives.initModuleDeriveRegistry(alloc);
    const macro = meta_directives.module_derive_registry.get(derive_name) orelse return null;

    var matches: std.ArrayListUnmanaged(AliasMatch) = .empty;
    defer matches.deinit(alloc);
    collectMatchingTypes(host, concept, &matches) catch return null;

    if (matches.items.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
    if (matches.items.len > MAX_PERMUTE_SIZE) return null;

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    const n = matches.items.len;
    const perm = alloc.alloc(usize, n) catch return null;
    defer alloc.free(perm);
    for (0..n) |i| perm[i] = i;
    const stack = alloc.alloc(usize, n) catch return null;
    defer alloc.free(stack);
    @memset(stack, 0);

    var idx: usize = 0;
    while (true) {
        const subset = subsetMeta(alloc, matches.items, perm[0..n], 0) catch {
            if (idx == 0) return null;
            break;
        };
        if (derive_eval.evalDeriveMacroValue(alloc, macro.func_source, subset, host.bindings, host.options)) |c_code| {
            defer alloc.free(c_code);
            if (c_code.len > 0) {
                buf.appendSlice(alloc, c_code) catch return null;
                buf.append(alloc, '\n') catch return null;
            }
        } else |_| {
            // derive eval failed for this permutation; skip to next
        }

        if (idx == 0 and n == 1) break;

        while (idx < n) {
            if (stack[idx] < idx) {
                if (idx % 2 == 0) {
                    const tmp = perm[0];
                    perm[0] = perm[idx];
                    perm[idx] = tmp;
                } else {
                    const tmp = perm[stack[idx]];
                    perm[stack[idx]] = perm[idx];
                    perm[idx] = tmp;
                }
                stack[idx] += 1;
                idx = 0;
                break;
            } else {
                stack[idx] = 0;
                idx += 1;
            }
        }
        if (idx >= n) break;
    }

    if (buf.items.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

pub fn moduleTypesHook(host: Host, alloc: std.mem.Allocator) ?comptime_eval.Value {
    var entries: std.ArrayListUnmanaged(comptime_eval.Value.TableEntry) = .empty;
    errdefer entries.deinit(alloc);

    var idx: i64 = 1;
    const mod = host.mod orelse return null;
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .alias_def) continue;
        const ad = &stmt.alias_def;
        const rt = host.record_aliases.get(ad.name) orelse continue;
        if (rt != .table_type) continue;
        const meta_value = derive_eval.metaValueFromFields(alloc, ad.name, rt.table_type.fields) catch continue;
        entries.append(alloc, .{ .key = .{ .int = idx }, .val = meta_value }) catch return null;
        idx += 1;
    }

    return .{ .table = entries.toOwnedSlice(alloc) catch return null };
}

pub fn moduleTypeNamesHook(host: Host, alloc: std.mem.Allocator) ?comptime_eval.Value {
    return typeNamesForConcept(host, "", alloc);
}

pub fn conceptTypeNamesHook(host: Host, concept_spec: []const u8, alloc: std.mem.Allocator) ?comptime_eval.Value {
    return typeNamesForConcept(host, concept_spec, alloc);
}

fn typeNamesForConcept(host: Host, concept_spec: []const u8, alloc: std.mem.Allocator) ?comptime_eval.Value {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);

    var first = true;
    const mod = host.mod orelse return null;
    for (mod.body.stmts) |*stmt| {
        if (stmt.* != .alias_def) continue;
        const ad = &stmt.alias_def;
        if (concept_spec.len > 0 and !aliasSatisfiesConceptSpec(host, ad, concept_spec)) continue;
        const rt = host.record_aliases.get(ad.name) orelse continue;
        if (rt != .table_type) continue;
        if (!first) buf.append(alloc, ';') catch return null;
        first = false;
        buf.appendSlice(alloc, ad.name) catch return null;
    }

    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

pub fn typeDiffHook(host: Host, old_name: []const u8, new_name: []const u8, alloc: std.mem.Allocator) ?comptime_eval.Value {
    const old_rt = host.record_aliases.get(old_name) orelse return null;
    const new_rt = host.record_aliases.get(new_name) orelse return null;
    if (old_rt != .table_type or new_rt != .table_type) return null;
    const code = type_diff.emitMigration(alloc, old_name, old_rt.table_type.fields, new_name, new_rt.table_type.fields) catch return null;
    return .{ .string = code };
}

pub fn fieldsMapString(host: Host, args: []const *ast.Expr, fieldsMapFields: *const fn (Host, *const ast.Expr) ?[]const types.FieldType) ?[]const u8 {
    if (args.len < 2) return null;
    const fields = fieldsMapFields(host, args[0]) orelse return null;
    const tmpl = if (args[1].* == .string_lit) args[1].string_lit.val else return null;

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(host.alloc);

    for (fields, 0..) |f, i| {
        var row = tmpl;
        var cbuf: [64]u8 = undefined;
        const type_str = f.typ.c_type(&cbuf);
        const idx_str = std.fmt.bufPrint(&cbuf, "{d}", .{i}) catch return null;
        row = std.mem.replaceOwned(u8, host.alloc, row, "%n", f.name) catch return null;
        defer host.alloc.free(row);
        const row2 = std.mem.replaceOwned(u8, host.alloc, row, "%t", type_str) catch return null;
        defer host.alloc.free(row2);
        const row3 = std.mem.replaceOwned(u8, host.alloc, row2, "%i", idx_str) catch return null;
        buf.appendSlice(host.alloc, row3) catch return null;
        host.alloc.free(row3);
    }

    return buf.toOwnedSlice(host.alloc) catch null;
}

pub fn registerDeriveHook(_: Host, alloc: std.mem.Allocator, name: []const u8, func_source: []const u8) void {
    meta_directives.initModuleDeriveRegistry(alloc);
    meta_directives.module_derive_registry.register(name, func_source, .{ .file = "<register_derive>", .line = 1, .col = 1 }) catch {};
}

pub fn registerRewriteHook(_: Host, alloc: std.mem.Allocator, name: []const u8, pattern: []const u8, replacement: []const u8, priority: i32) void {
    rewrite_rules.registerRule(alloc, name, pattern, replacement, priority) catch {};
}

pub fn lookupDeriveHook(_: Host, alloc: std.mem.Allocator, name: []const u8) ?[]const u8 {
    meta_directives.initModuleDeriveRegistry(alloc);
    const macro = meta_directives.module_derive_registry.get(name) orelse return null;
    return alloc.dupe(u8, macro.func_source) catch null;
}

pub fn listDerivesHook(_: Host, alloc: std.mem.Allocator) ?comptime_eval.Value {
    meta_directives.initModuleDeriveRegistry(alloc);
    const names = meta_directives.module_derive_registry.listNames(alloc) catch return null;
    defer {
        for (names) |n| alloc.free(n);
        alloc.free(names);
    }
    var entries = alloc.alloc(comptime_eval.Value.TableEntry, names.len) catch return null;
    for (names, 0..) |n, i| {
        const owned = alloc.dupe(u8, n) catch return null;
        entries[i] = .{ .key = .{ .int = @intCast(i + 1) }, .val = .{ .string = owned } };
    }
    return .{ .table = entries };
}

pub fn evalDeriveHook(host: Host, alloc: std.mem.Allocator, name: []const u8, meta: comptime_eval.Value) ?[]const u8 {
    meta_directives.initModuleDeriveRegistry(alloc);
    if (meta_directives.module_derive_registry.get(name)) |macro| {
        return derive_eval.evalDeriveMacroValue(alloc, macro.func_source, meta, host.bindings, host.options) catch null;
    }
    return null;
}

pub fn writeFileHook(_: Host, alloc: std.mem.Allocator, path: []const u8, content: []const u8) bool {
    c_signatures.registerEmitFile(alloc, path, content) catch return false;
    return true;
}

pub fn emitUserDefinedDerives(
    host: Host,
    type_name: []const u8,
    attrs: []const ast.Attribute,
    fields: []const types.FieldType,
    extra_derives: []const []const u8,
    emitted: *std.StringHashMapUnmanaged(void),
    emitLine: *const fn (ctx: *anyopaque, line: []const u8) void,
    ctx: *anyopaque,
) void {
    var pending: std.ArrayListUnmanaged([]const u8) = .empty;
    defer pending.deinit(host.alloc);

    for (attrs) |attr| {
        const type_attr = meta_module.normalizeTypeAttribute(attr.name);
        if (std.mem.eql(u8, type_attr, "derive")) {
            var it = directives.attrArgs(attr.args);
            while (it.next()) |arg| {
                if (arg.text.len == 0) continue;
                pending.append(host.alloc, arg.text) catch continue;
            }
        } else if (std.mem.eql(u8, type_attr, "derive.bundle")) {
            const raw = attr.args orelse continue;
            // `pending` holds these slices until after the attribute loop, so
            // the expansion cannot be freed at the end of this branch — it was,
            // and a second `@derive.bundle` on the same type then reused the
            // block and rewrote the first bundle's names out from under it.
            const traits = derive_bundles.expandTraitsFromRawArgs(host.alloc, raw) catch continue;
            defer host.alloc.free(traits);
            for (traits) |t| pending.append(host.alloc, t) catch {};
        }
    }
    for (extra_derives) |name| pending.append(host.alloc, name) catch {};

    meta_directives.initModuleDeriveRegistry(host.alloc);

    for (pending.items) |derive_name| {
        // Native derive fast path: emit directly without Lua eval
        if (derive_registry.hasNativeDerive(derive_name)) {
            const meta = derive_eval.metadataFromFields(host.alloc, type_name, fields) catch continue;
            const native_fn = derive_registry.getNativeDerive(derive_name) orelse continue;
            const c_code = native_fn(host.alloc, meta) catch continue;
            defer host.alloc.free(c_code);
            var header_buf: [256]u8 = undefined;
            const header = std.fmt.bufPrint(&header_buf, "/* @derive({s}): native derive for {s} */\n", .{ derive_name, type_name }) catch continue;
            emitLine(ctx, header);
            emitLine(ctx, c_code);
            emitLine(ctx, "\n");
            continue;
        }
        if (derive_registry.isBuiltinDerive(derive_name)) continue;
        var key_buf: [256]u8 = undefined;
        const emit_key = std.fmt.bufPrint(&key_buf, "{s}:{s}", .{ type_name, derive_name }) catch continue;
        if (emitted.contains(emit_key)) continue;
        emitted.put(host.alloc, host.alloc.dupe(u8, emit_key) catch continue, {}) catch continue;

        const macro = meta_directives.module_derive_registry.get(derive_name) orelse continue;
        const meta = derive_eval.metadataFromFields(host.alloc, type_name, fields) catch continue;
        const c_code = derive_eval.evalDeriveMacro(host.alloc, macro.func_source, meta, host.bindings, host.options) catch continue;
        defer host.alloc.free(c_code);

        var header_buf: [256]u8 = undefined;
        const header = std.fmt.bufPrint(&header_buf, "/* @derive({s}): user-defined derive for {s} */\n", .{ derive_name, type_name }) catch continue;
        emitLine(ctx, header);
        emitLine(ctx, c_code);
        emitLine(ctx, "\n");
    }
}

/// Registered internal hooks owned by unified meta dispatch (P6-07 / G-061).
const combinator_hook_names = [_][]const u8{
    "__comptimemap",
    "__comptimeeach",
    "__comptimematch",
    "__comptimetabulate",
    "__comptimeinterpolate",
    "__comptimezip",
    "__comptimeproduct",
    "__comptimetensor",
    "__comptimepower",
    "__comptimechoose",
    "__comptimepermute",
    "__comptimenfold",
    "__comptimefixpoint",
    "__comptimefanout",
    "__metaexpand",
    "__metaceiling",
    "__metaomni",
    "__metaburst",
    "__metatranscend",
    "__metainfinity",
    "__metahyper",
    "__metagrammar",
    "__metaweave",
    "__metatemplate",
    "__metagenerate",
    "__metascheme",
    "__metaschemeclauses",
    "__derivemap",
    "__derivepower",
    "__deriveproduct",
    "__derivetensor",
    "__derivenfold",
    "__derivechoose",
    "__derivepermute",
    "__derivetower",
};

fn deriveNameFromValue(v: comptime_eval.Value) ?[]const u8 {
    return switch (v) {
        .string => v.string,
        else => null,
    };
}

fn optionalFuncValue(v: comptime_eval.Value) ?comptime_eval.Value {
    if (v == .func) return v;
    return null;
}

fn conceptsSliceFromSpec(
    _: std.mem.Allocator,
    spec: []const u8,
    scratch: *[16][]const u8,
) ![]const []const u8 {
    if (std.mem.indexOfScalar(u8, spec, '+') == null) {
        scratch[0] = std.mem.trim(u8, spec, " \t\r\n");
        return scratch[0..1];
    }
    var count: usize = 0;
    var it = std.mem.splitScalar(u8, spec, '+');
    while (it.next()) |part| : (count += 1) {
        scratch[count] = std.mem.trim(u8, part, " \t\r\n");
    }
    return scratch[0..count];
}

/// True when `applyMetaCombinatorHook` owns dispatch for an internal hook name (P6-07).
pub fn canApplyMetaCombinatorHook(internal: []const u8) bool {
    for (combinator_hook_names) |name| {
        if (std.mem.eql(u8, name, internal)) return true;
    }
    return false;
}

/// Provenance input string for a meta combinator call (hashed by transform_engine).
pub fn metaCombinatorProvenanceInput(
    internal: []const u8,
    args: []const comptime_eval.Value,
    buf: []u8,
) ?[]const u8 {
    if (std.mem.eql(u8, internal, "__comptimetabulate") and args.len >= 1 and args[0] == .int) {
        return std.fmt.bufPrint(buf, "{d}", .{args[0].int}) catch null;
    }
    if ((std.mem.eql(u8, internal, "__comptimeproduct") or
        std.mem.eql(u8, internal, "__deriveproduct")) and
        args.len >= 2 and args[0] == .string and args[1] == .string)
    {
        return std.fmt.bufPrint(buf, "{s}|{s}", .{ args[0].string, args[1].string }) catch args[0].string;
    }
    if (args.len >= 1 and args[0] == .string) return args[0].string;
    return null;
}

/// P6-07 unified hook execution — single dispatch table for all codegen/comptime sites.
pub fn applyMetaCombinatorHook(
    host: Host,
    internal: []const u8,
    args: []const comptime_eval.Value,
    alloc: std.mem.Allocator,
) ?comptime_eval.Value {
    if (std.mem.eql(u8, internal, "__comptimematch") and args.len == 2) {
        if (args[0] != .string or args[1] != .func) return null;
        return comptimeMatchHook(host, args[0].string, args[1], alloc);
    }
    if (std.mem.eql(u8, internal, "__comptimeinterpolate") and args.len == 2) {
        if (args[0] != .string) return null;
        return comptimeInterpolateHook(host, args[0].string, args[1], alloc);
    }
    if (std.mem.eql(u8, internal, "__comptimetabulate") and args.len == 2) {
        if (args[0] != .int or args[1] != .func) return null;
        return comptimeTabulateHook(host, args[0].int, args[1], alloc);
    }
    if (std.mem.eql(u8, internal, "__comptimezip") and args.len == 3) {
        if (args[0] != .string or args[1] != .string or args[2] != .func) return null;
        return comptimeZipHook(host, args[0].string, args[1].string, args[2], alloc);
    }
    if (std.mem.eql(u8, internal, "__comptimeproduct") and args.len == 3) {
        if (args[0] != .string or args[1] != .string or args[2] != .func) return null;
        return comptimeProductHook(host, args[0].string, args[1].string, args[2], alloc);
    }
    if (std.mem.eql(u8, internal, "__comptimemap") and args.len == 2) {
        if (args[0] != .string or args[1] != .func) return null;
        return comptimeMapHook(host, args[0].string, args[1], alloc);
    }
    if (std.mem.eql(u8, internal, "__comptimeeach") and args.len == 2) {
        if (args[0] != .string or args[1] != .func) return null;
        return comptimeEachHook(host, args[0].string, args[1], alloc);
    }
    if (std.mem.eql(u8, internal, "__comptimepower") and args.len == 2) {
        if (args[0] != .string or args[1] != .func) return null;
        return comptimePowerHook(host, args[0].string, args[1], alloc);
    }
    if (std.mem.eql(u8, internal, "__comptimechoose") and args.len == 3) {
        if (args[0] != .string or args[1] != .int or args[2] != .func) return null;
        return comptimeChooseHook(host, args[0].string, @intCast(args[1].int), args[2], alloc);
    }
    if (std.mem.eql(u8, internal, "__comptimepermute") and args.len == 2) {
        if (args[0] != .string or args[1] != .func) return null;
        return comptimePermuteHook(host, args[0].string, args[1], alloc);
    }
    if (std.mem.eql(u8, internal, "__comptimetensor") and args.len == 4) {
        if (args[0] != .string or args[1] != .string or args[2] != .string or args[3] != .func) return null;
        return comptimeTensorHook(host, args[0].string, args[1].string, args[2].string, args[3], alloc);
    }
    if (std.mem.eql(u8, internal, "__comptimenfold") and args.len == 2) {
        if (args[0] != .string or args[1] != .func) return null;
        var scratch: [16][]const u8 = undefined;
        const concepts = conceptsSliceFromSpec(alloc, args[0].string, &scratch) catch return null;
        return comptimeNfoldHook(host, concepts, args[1], alloc);
    }
    if (std.mem.eql(u8, internal, "__comptimefanout") and args.len == 3) {
        if (args[0] != .string or args[1] != .func or args[2] != .int) return null;
        return comptimeFanoutHook(host, args[0].string, args[1], @intCast(args[2].int), alloc);
    }
    if (std.mem.eql(u8, internal, "__derivepower") and args.len == 2) {
        if (args[0] != .string) return null;
        const derive_name = deriveNameFromValue(args[1]) orelse return null;
        return derivePowerHook(host, args[0].string, derive_name, alloc);
    }
    if (std.mem.eql(u8, internal, "__deriveproduct") and args.len == 3) {
        if (args[0] != .string or args[1] != .string) return null;
        const derive_name = deriveNameFromValue(args[2]) orelse return null;
        return deriveProductHook(host, args[0].string, args[1].string, derive_name, alloc);
    }
    if (std.mem.eql(u8, internal, "__derivetensor") and args.len == 4) {
        if (args[0] != .string or args[1] != .string or args[2] != .string) return null;
        const derive_name = deriveNameFromValue(args[3]) orelse return null;
        return deriveTensorHook(host, args[0].string, args[1].string, args[2].string, derive_name, alloc);
    }
    if (std.mem.eql(u8, internal, "__derivenfold") and args.len == 2) {
        if (args[0] != .string) return null;
        const derive_name = deriveNameFromValue(args[1]) orelse return null;
        var scratch: [16][]const u8 = undefined;
        const concepts = conceptsSliceFromSpec(alloc, args[0].string, &scratch) catch return null;
        return deriveNfoldHook(host, concepts, derive_name, alloc);
    }
    if (std.mem.eql(u8, internal, "__derivechoose") and args.len == 3) {
        if (args[0] != .string or args[1] != .int) return null;
        const derive_name = deriveNameFromValue(args[2]) orelse return null;
        return deriveChooseHook(host, args[0].string, @intCast(args[1].int), derive_name, alloc);
    }
    if (std.mem.eql(u8, internal, "__derivepermute") and args.len == 2) {
        if (args[0] != .string) return null;
        const derive_name = deriveNameFromValue(args[1]) orelse return null;
        return derivePermuteHook(host, args[0].string, derive_name, alloc);
    }
    if (std.mem.eql(u8, internal, "__derivetower") and args.len == 2) {
        if (args[0] != .string) return null;
        const derive_name = deriveNameFromValue(args[1]) orelse return null;
        var scratch: [16][]const u8 = undefined;
        const concepts = conceptsSliceFromSpec(alloc, args[0].string, &scratch) catch return null;
        return deriveTowerHook(host, concepts, derive_name, alloc);
    }
    if (std.mem.eql(u8, internal, "__derivemap") and args.len == 2) {
        if (args[0] != .string) return null;
        const derive_name = deriveNameFromValue(args[1]) orelse return null;
        return deriveMapHook(host, args[0].string, derive_name, alloc);
    }
    if (std.mem.eql(u8, internal, "__metaexpand") and args.len >= 2) {
        if (args[0] != .string or args[1] != .string) return null;
        const callback = if (args.len >= 3) optionalFuncValue(args[2]) else null;
        return expandHook(host, args[0].string, args[1].string, callback, alloc);
    }
    if (std.mem.eql(u8, internal, "__metaceiling") and args.len == 3) {
        if (args[0] != .string or args[1] != .string or args[2] != .string) return null;
        return ceilingHook(host, args[0].string, args[1].string, args[2].string, alloc);
    }
    if (std.mem.eql(u8, internal, "__metaomni") and args.len == 3) {
        if (args[0] != .string or args[1] != .string or args[2] != .string) return null;
        return omniHook(host, args[0].string, args[1].string, args[2].string, null, alloc);
    }
    if (std.mem.eql(u8, internal, "__metaomni") and args.len == 4) {
        if (args[0] != .string or args[1] != .string or args[2] != .string) return null;
        const callback = optionalFuncValue(args[3]);
        return omniHook(host, args[0].string, args[1].string, args[2].string, callback, alloc);
    }
    if (std.mem.eql(u8, internal, "__metaburst") and args.len == 3) {
        if (args[0] != .string or args[1] != .string or args[2] != .string) return null;
        return burstEmitHook(host, args[0].string, args[1].string, args[2].string, alloc);
    }
    if (std.mem.eql(u8, internal, "__metatranscend") and args.len == 4) {
        if (args[0] != .string or args[1] != .string or args[2] != .string or args[3] != .string) return null;
        return transcendHook(host, args[0].string, args[1].string, args[2].string, args[3].string, null, alloc);
    }
    if (std.mem.eql(u8, internal, "__metatranscend") and args.len == 5) {
        if (args[0] != .string or args[1] != .string or args[2] != .string or args[3] != .string) return null;
        const callback = optionalFuncValue(args[4]);
        return transcendHook(host, args[0].string, args[1].string, args[2].string, args[3].string, callback, alloc);
    }
    if (std.mem.eql(u8, internal, "__metainfinity") and args.len == 5) {
        if (args[0] != .string or args[1] != .string or args[2] != .string or args[3] != .string or args[4] != .string) return null;
        return infinityHook(host, args[0].string, args[1].string, args[2].string, args[3].string, args[4].string, null, alloc);
    }
    if (std.mem.eql(u8, internal, "__metahyper") and args.len == 6) {
        if (args[0] != .string or args[1] != .string or args[2] != .string or args[3] != .string or args[4] != .string or args[5] != .string) return null;
        return hyperHook(host, args[0].string, args[1].string, args[2].string, args[3].string, args[4].string, args[5].string, null, alloc);
    }
    if (std.mem.eql(u8, internal, "__metagrammar") and args.len == 2) {
        if (args[0] != .string or args[1] != .func) return null;
        return comptimeGrammarHook(host, args[0].string, args[1], alloc);
    }
    if (std.mem.eql(u8, internal, "__metaweave") and args.len == 3) {
        if (args[0] != .string or args[1] != .string or args[2] != .func) return null;
        return weaveHook(host, args[0].string, args[1].string, args[2], host.bindings, host.options, alloc);
    }
    if (std.mem.eql(u8, internal, "__metatemplate") and args.len >= 2) {
        if (args[0] != .string or args[1] != .string) return null;
        const callback = if (args.len >= 3) optionalFuncValue(args[2]) else null;
        return comptimeTemplateHook(host, args[0].string, args[1].string, callback, alloc);
    }
    if (std.mem.eql(u8, internal, "__metagenerate") and args.len >= 1) {
        if (args[0] != .string) return null;
        const body = if (args.len >= 2 and args[1] == .string) args[1].string else "";
        const callback = if (args.len >= 3) optionalFuncValue(args[2]) else null;
        return comptimeGenerateHook(host, args[0].string, body, callback, alloc);
    }
    if (std.mem.eql(u8, internal, "__metascheme") and args.len >= 1) {
        if (args[0] != .string) return null;
        const template = if (args.len >= 2 and args[1] == .string) args[1].string else "";
        const callback = if (args.len >= 3) optionalFuncValue(args[2]) else null;
        return comptimeSchemeHook(host, args[0].string, template, callback, alloc);
    }
    if (std.mem.eql(u8, internal, "__metaschemeclauses") and args.len >= 1) {
        if (args[0] != .string) return null;
        const callback = if (args.len >= 2) optionalFuncValue(args[1]) else null;
        return comptimeSchemeClausesHook(host, args[0].string, callback, alloc);
    }
    if (std.mem.eql(u8, internal, "__comptimefixpoint") and args.len == 3) {
        if (args[0] != .string) return null;
        const max_iter: usize = blk: {
            if (args[1] == .int) break :blk @intCast(args[1].int);
            if (args[2] == .int) break :blk @intCast(args[2].int);
            return null;
        };
        const callback = if (args[1] == .func) args[1] else if (args[2] == .func) args[2] else return null;
        return comptimeFixpointHook(host, args[0].string, callback, max_iter, alloc);
    }
    return null;
}

test "meta_codegen: canApplyMetaCombinatorHook tier-1 set" {
    try std.testing.expect(canApplyMetaCombinatorHook("__comptimemap"));
    try std.testing.expect(canApplyMetaCombinatorHook("__comptimefixpoint"));
    try std.testing.expect(!canApplyMetaCombinatorHook("__metacatalog"));
}

test "meta_codegen: metaCombinatorProvenanceInput product pair" {
    var buf: [64]u8 = undefined;
    const args = [_]comptime_eval.Value{ .{ .string = "A" }, .{ .string = "B" } };
    const input = metaCombinatorProvenanceInput("__comptimeproduct", &args, &buf) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("A|B", input);
}

test "meta_codegen: concept intersection parsing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const names = try splitConceptSpec(alloc, "HasXY+HasId");
    defer {
        for (names) |n| alloc.free(n);
        alloc.free(names);
    }
    try std.testing.expectEqual(@as(usize, 2), names.len);
    try std.testing.expectEqualStrings("HasXY", names[0]);
    try std.testing.expectEqualStrings("HasId", names[1]);
}

test "meta_codegen: a single-quoted concept reads the same as a double-quoted one" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const single = (try parseDeriveAllDirective(alloc, "'HasXY', TouchApi")) orelse
        return error.DirectiveSilentlyDropped;
    try std.testing.expectEqualStrings("HasXY", single.concept_spec);

    const double = (try parseDeriveAllDirective(alloc, "\"HasXY\", TouchApi")) orelse
        return error.DirectiveSilentlyDropped;
    try std.testing.expectEqualStrings("HasXY", double.concept_spec);

    // Positive control: a bare first argument is still not a concept.
    try std.testing.expect((try parseDeriveAllDirective(alloc, "HasXY, TouchApi")) == null);
}

test "meta_codegen: the concept chain ends its derive run at the first quoted argument" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // The corpus spelling: a trailing bare argument past the last concept is
    // surplus and must not be read as one.
    const omni = (try parseOmniDirective(alloc, "\"HasXY\", PairApi, \"HasTag\", registry_line")) orelse
        return error.DirectiveSilentlyDropped;
    try std.testing.expectEqualStrings("HasXY", omni.concept_a);
    try std.testing.expectEqualStrings("HasTag", omni.concept_b);
    try std.testing.expectEqual(@as(usize, 1), omni.derive_names.len);
    try std.testing.expectEqualStrings("PairApi", omni.derive_names[0]);

    const inf = (try parseInfinityDirective(alloc, "'HasXY', QuadApi, 'HasTag', 'HasId', 'HasExtra'")) orelse
        return error.DirectiveSilentlyDropped;
    try std.testing.expectEqualStrings("HasExtra", inf.concept_d);

    // Positive control: too few trailing concepts is still a dropped directive.
    try std.testing.expect((try parseInfinityDirective(alloc, "\"HasXY\", QuadApi, \"HasTag\"")) == null);
}

const MAX_GRAMMAR_EXPANSIONS: usize = 256;
const MAX_GRAMMAR_DEPTH: usize = 8;

fn grammarTrim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

fn grammarSplitAlts(alloc: std.mem.Allocator, rhs: []const u8) ![]const []const u8 {
    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (list.items) |a| alloc.free(a);
        list.deinit(alloc);
    }
    var start: usize = 0;
    var depth: u32 = 0;
    var i: usize = 0;
    while (i < rhs.len) : (i += 1) {
        switch (rhs[i]) {
            '(', '[', '{' => depth += 1,
            ')', ']', '}' => {
                if (depth > 0) depth -= 1;
            },
            '|' => if (depth == 0) {
                const piece = grammarTrim(rhs[start..i]);
                if (piece.len > 0) try list.append(alloc, try alloc.dupe(u8, piece));
                start = i + 1;
            },
            else => {},
        }
    }
    const tail = grammarTrim(rhs[start..]);
    if (tail.len > 0) try list.append(alloc, try alloc.dupe(u8, tail));
    return try list.toOwnedSlice(alloc);
}

fn grammarTokenizeAlt(alloc: std.mem.Allocator, alt: []const u8) ![]const []const u8 {
    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (list.items) |t| alloc.free(t);
        list.deinit(alloc);
    }
    var i: usize = 0;
    while (i < alt.len) {
        while (i < alt.len and alt[i] == ' ') i += 1;
        if (i >= alt.len) break;
        if (alt[i] == '"') {
            var j = i + 1;
            while (j < alt.len) {
                if (alt[j] == '\\' and j + 1 < alt.len) {
                    j += 2;
                    continue;
                }
                if (alt[j] == '"') break;
                j += 1;
            }
            try list.append(alloc, try alloc.dupe(u8, alt[i .. j + 1]));
            i = j + 1;
            continue;
        }
        var j = i;
        while (j < alt.len and alt[j] != ' ') : (j += 1) {}
        try list.append(alloc, try alloc.dupe(u8, alt[i..j]));
        i = j;
    }
    return try list.toOwnedSlice(alloc);
}

fn grammarParseRules(alloc: std.mem.Allocator, spec: []const u8) !std.StringHashMapUnmanaged([]const []const u8) {
    var rules: std.StringHashMapUnmanaged([]const []const u8) = .empty;
    errdefer {
        var it = rules.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |a| alloc.free(a);
            alloc.free(entry.value_ptr.*);
        }
        rules.deinit(alloc);
    }
    var rest = spec;
    while (rest.len > 0) {
        rest = grammarTrim(rest);
        if (rest.len == 0) break;
        const semi = std.mem.indexOfScalar(u8, rest, ';') orelse rest.len;
        const rule_text = grammarTrim(rest[0..semi]);
        rest = if (semi < rest.len) rest[semi + 1 ..] else "";
        const colon = std.mem.indexOfScalar(u8, rule_text, ':') orelse continue;
        const name = grammarTrim(rule_text[0..colon]);
        if (name.len == 0) continue;
        const alts = try grammarSplitAlts(alloc, grammarTrim(rule_text[colon + 1 ..]));
        const owned_name = try alloc.dupe(u8, name);
        try rules.put(alloc, owned_name, alts);
    }
    return rules;
}

fn grammarCartesianAppend(
    alloc: std.mem.Allocator,
    prefix: []const u8,
    choices: []const []const u8,
    out: *std.ArrayListUnmanaged([]const u8),
) !void {
    for (choices) |choice| {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        errdefer buf.deinit(alloc);
        if (prefix.len > 0) {
            try buf.appendSlice(alloc, prefix);
            if (!std.mem.endsWith(u8, prefix, " ")) try buf.append(alloc, ' ');
        }
        const trimmed = grammarTrim(choice);
        if (trimmed.len > 0) try buf.appendSlice(alloc, trimmed);
        try out.append(alloc, try buf.toOwnedSlice(alloc));
    }
}

fn grammarExpandRule(
    alloc: std.mem.Allocator,
    rules: *const std.StringHashMapUnmanaged([]const []const u8),
    rule_name: []const u8,
    depth: usize,
    out: *std.ArrayListUnmanaged([]const u8),
) !void {
    if (out.items.len >= MAX_GRAMMAR_EXPANSIONS) return;
    if (depth == 0) {
        try out.append(alloc, try alloc.dupe(u8, ""));
        return;
    }
    const alts = rules.get(rule_name) orelse {
        try out.append(alloc, try alloc.dupe(u8, rule_name));
        return;
    };
    for (alts) |alt| {
        const tokens = try grammarTokenizeAlt(alloc, alt);
        defer {
            for (tokens) |t| alloc.free(t);
            alloc.free(tokens);
        }
        var partials: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (partials.items) |p| alloc.free(p);
            partials.deinit(alloc);
        }
        try partials.append(alloc, try alloc.dupe(u8, ""));
        for (tokens) |tok| {
            const bare = if (tok.len >= 2 and tok[0] == '"') grammarTrim(tok[1 .. tok.len - 1]) else tok;
            var next: std.ArrayListUnmanaged([]const u8) = .empty;
            defer next.deinit(alloc);
            if (rules.get(bare)) |_| {
                var branch: std.ArrayListUnmanaged([]const u8) = .empty;
                defer {
                    for (branch.items) |b| alloc.free(b);
                    branch.deinit(alloc);
                }
                try grammarExpandRule(alloc, rules, bare, depth - 1, &branch);
                for (partials.items) |prefix| {
                    try grammarCartesianAppend(alloc, prefix, branch.items, &next);
                }
            } else {
                for (partials.items) |prefix| {
                    try grammarCartesianAppend(alloc, prefix, &[_][]const u8{bare}, &next);
                }
            }
            for (partials.items) |p| alloc.free(p);
            partials.clearRetainingCapacity();
            try partials.appendSlice(alloc, next.items);
            next.clearRetainingCapacity();
        }
        for (partials.items) |p| {
            const trimmed = grammarTrim(p);
            if (trimmed.len == 0) {
                alloc.free(p);
                continue;
            }
            try out.append(alloc, try alloc.dupe(u8, trimmed));
            alloc.free(p);
            if (out.items.len >= MAX_GRAMMAR_EXPANSIONS) break;
        }
        partials.clearRetainingCapacity();
    }
}

/// `@comp.grammar(spec, fn)` — parse a compact EBNF-ish spec (`Rule: a | b c; c: x`)
/// and invoke `fn(meta)` once per generated expansion (branching^depth, capped).
/// Comptime-only — folds to native C string fragments, never `lua_Value`.
pub fn comptimeGrammarHook(host: Host, spec: []const u8, callback: comptime_eval.Value, alloc: std.mem.Allocator) ?comptime_eval.Value {
    var rules = grammarParseRules(alloc, spec) catch return null;
    defer {
        var it = rules.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |a| alloc.free(a);
            alloc.free(entry.value_ptr.*);
        }
        rules.deinit(alloc);
    }
    var start: []const u8 = "S";
    var it = rules.keyIterator();
    if (it.next()) |k| start = k.*;

    var expansions: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (expansions.items) |e| alloc.free(e);
        expansions.deinit(alloc);
    }
    grammarExpandRule(alloc, &rules, start, MAX_GRAMMAR_DEPTH, &expansions) catch return null;
    if (expansions.items.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);
    const count: i64 = @intCast(expansions.items.len);
    var index: i64 = 0;
    for (expansions.items) |exp| {
        const owned = alloc.dupe(u8, exp) catch return null;
        defer alloc.free(owned);
        var entries: [4]comptime_eval.Value.TableEntry = .{
            .{ .name = "expansion", .val = .{ .string = owned } },
            .{ .name = "index", .val = .{ .int = index } },
            .{ .name = "count", .val = .{ .int = count } },
            .{ .name = "start", .val = .{ .string = start } },
        };
        const meta = metaCallbackTable(alloc, &entries) catch return null;
        defer alloc.free(meta.table);
        const piece = comptime_eval.callFunctionValue(callback, &.{meta}, host.bindings, host.options) catch continue;
        if (piece == .string) buf.appendSlice(alloc, piece.string) catch return null;
        index += 1;
    }
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

const TemplateInstance = struct {
    name: []const u8,
    ctype: []const u8,
    extra: ?[]const u8,
};

fn templateTrim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

fn templateSplitInstances(alloc: std.mem.Allocator, spec: []const u8) ![]TemplateInstance {
    var out: std.ArrayListUnmanaged(TemplateInstance) = .empty;
    errdefer out.deinit(alloc);
    var iter = std.mem.splitSequence(u8, spec, "|");
    while (iter.next()) |raw| {
        const trimmed = templateTrim(raw);
        if (trimmed.len == 0) continue;
        var colon_iter = std.mem.splitScalar(u8, trimmed, ':');
        const name_raw = colon_iter.next() orelse continue;
        const name_t = templateTrim(name_raw);
        const ctype_raw = colon_iter.next();
        const extra_raw = colon_iter.next();
        const name_owned = try alloc.dupe(u8, name_t);
        const ctype_owned = if (ctype_raw) |c| try alloc.dupe(u8, templateTrim(c)) else try alloc.dupe(u8, name_t);
        const extra_owned = if (extra_raw) |e| blk: {
            const t = templateTrim(e);
            if (t.len == 0) break :blk null;
            break :blk try alloc.dupe(u8, t);
        } else null;
        try out.append(alloc, .{ .name = name_owned, .ctype = ctype_owned, .extra = extra_owned });
    }
    return try out.toOwnedSlice(alloc);
}

fn templateReplaceAll(alloc: std.mem.Allocator, hay: []const u8, needle: []const u8, repl: []const u8) ![]u8 {
    if (needle.len == 0) return alloc.dupe(u8, hay);
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(alloc);
    var i: usize = 0;
    while (i < hay.len) {
        if (std.mem.startsWith(u8, hay[i..], needle)) {
            try out.appendSlice(alloc, repl);
            i += needle.len;
        } else {
            try out.append(alloc, hay[i]);
            i += 1;
        }
    }
    return try out.toOwnedSlice(alloc);
}

fn templateAppendFragment(buf: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, piece: []const u8) !void {
    try buf.appendSlice(alloc, piece);
    if (piece.len == 0 or piece[piece.len - 1] != '\n') try buf.append(alloc, '\n');
}

fn templateSubst(alloc: std.mem.Allocator, body: []const u8, inst: TemplateInstance) ![]u8 {
    var cur: []u8 = try alloc.dupe(u8, body);
    errdefer alloc.free(cur);
    const replacements = [_]struct { needle: []const u8, val: []const u8 }{
        .{ .needle = "$name", .val = inst.name },
        .{ .needle = "$ctype", .val = inst.ctype },
        .{ .needle = "$extra", .val = inst.extra orelse "" },
        .{ .needle = "$0", .val = inst.name },
        .{ .needle = "$1", .val = inst.ctype },
        .{ .needle = "$2", .val = inst.extra orelse "" },
    };
    for (replacements) |r| {
        const next = try templateReplaceAll(alloc, cur, r.needle, r.val);
        alloc.free(cur);
        cur = next;
    }
    return cur;
}

/// `@comp.template(instances, body)` or `(instances, body, fn)` — expand a template
/// once per instance axis entry (`name:ctype[:extra]`, pipe-separated).
/// Placeholders: `$0`/`$name`, `$1`/`$ctype`, `$2`/`$extra`. Comptime-only → native C string.
pub fn comptimeTemplateHook(host: Host, instances_spec: []const u8, body: []const u8, callback: ?comptime_eval.Value, alloc: std.mem.Allocator) ?comptime_eval.Value {
    const instances = templateSplitInstances(alloc, instances_spec) catch return null;
    defer {
        for (instances) |inst| {
            alloc.free(inst.name);
            alloc.free(inst.ctype);
            if (inst.extra) |e| alloc.free(e);
        }
        alloc.free(instances);
    }
    if (instances.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);
    const count: i64 = @intCast(instances.len);
    var index: i64 = 0;
    for (instances) |inst| {
        if (callback) |cb| {
            if (cb != .func) return null;
            var entries: [5]comptime_eval.Value.TableEntry = .{
                .{ .name = "name", .val = .{ .string = inst.name } },
                .{ .name = "ctype", .val = .{ .string = inst.ctype } },
                .{ .name = "extra", .val = .{ .string = inst.extra orelse "" } },
                .{ .name = "index", .val = .{ .int = index } },
                .{ .name = "count", .val = .{ .int = count } },
            };
            const meta = metaCallbackTable(alloc, &entries) catch return null;
            defer alloc.free(meta.table);
            const piece = comptime_eval.callFunctionValue(cb, &.{meta}, host.bindings, host.options) catch {
                index += 1;
                continue;
            };
            if (piece == .string) templateAppendFragment(&buf, alloc, piece.string) catch return null;
        } else {
            const expanded = templateSubst(alloc, body, inst) catch return null;
            defer alloc.free(expanded);
            templateAppendFragment(&buf, alloc, expanded) catch return null;
        }
        index += 1;
    }
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

// ── @comp.scheme: declarative program scheme → full native implementation ──
// One pipe-separated declaration list → struct typedefs + function signatures +
// derived operations, expanded through a template or callback. Comptime-only;
// folds to a native C string literal (no lua_Value).

const SchemeUnit = struct {
    kind: []const u8, // "type" | "fn" | "unit"
    name: []const u8,
    ctype: []const u8, // type: struct tag; fn: return ctype
    fields: []const u8, // type: "ctype name, ..."
    fieldnames: []const u8, // type: "name, name, ..."
    fieldcount: i64,
    params: []const u8, // fn: "ctype name, ..."
    ret: []const u8, // fn: return ctype
};

/// Parse a `name: ctype` comma-list into C-style `ctype name` field decls and a
/// bare name list. Used for both struct fields and function params.
fn schemeParseFields(a: std.mem.Allocator, block: []const u8) !struct { fields: []const u8, names: []const u8, count: i64 } {
    var fields_buf: std.ArrayListUnmanaged(u8) = .empty;
    var names_buf: std.ArrayListUnmanaged(u8) = .empty;
    var count: i64 = 0;
    var it = std.mem.splitScalar(u8, block, ',');
    while (it.next()) |raw| {
        const trimmed = std.mem.trim(u8, raw, " \t\r\n");
        if (trimmed.len == 0) continue;
        var fname: []const u8 = undefined;
        var ftype: []const u8 = undefined;
        if (std.mem.indexOfScalar(u8, trimmed, ':')) |colon| {
            fname = std.mem.trim(u8, trimmed[0..colon], " \t\r\n");
            ftype = std.mem.trim(u8, trimmed[colon + 1 ..], " \t\r\n");
        } else {
            // No colon: treat token as a type; synthesize a positional name.
            var nb: [24]u8 = undefined;
            fname = try std.fmt.bufPrint(&nb, "f{d}", .{count});
            ftype = trimmed;
        }
        if (count > 0) {
            try fields_buf.appendSlice(a, ", ");
            try names_buf.appendSlice(a, ", ");
        }
        try fields_buf.appendSlice(a, ftype);
        try fields_buf.append(a, ' ');
        try fields_buf.appendSlice(a, fname);
        try names_buf.appendSlice(a, fname);
        count += 1;
    }
    return .{
        .fields = try fields_buf.toOwnedSlice(a),
        .names = try names_buf.toOwnedSlice(a),
        .count = count,
    };
}

/// Split a pipe-separated scheme spec into typed units (`type Name{…}` / `fn n(…)->…`).
fn schemeSplitDecls(a: std.mem.Allocator, spec: []const u8) ![]SchemeUnit {
    var out: std.ArrayListUnmanaged(SchemeUnit) = .empty;
    var iter = std.mem.splitSequence(u8, spec, "|");
    while (iter.next()) |raw_decl| {
        const t = std.mem.trim(u8, raw_decl, " \t\r\n");
        if (t.len == 0) continue;
        var unit: SchemeUnit = .{
            .kind = "",
            .name = "",
            .ctype = "",
            .fields = "",
            .fieldnames = "",
            .fieldcount = 0,
            .params = "",
            .ret = "",
        };
        if (std.mem.startsWith(u8, t, "type") and (t.len == 4 or t[4] == ' ' or t[4] == '\t')) {
            const rest = std.mem.trim(u8, t[4..], " \t\r\n");
            const brace = std.mem.indexOfScalar(u8, rest, '{') orelse rest.len;
            const name_t = std.mem.trim(u8, rest[0..brace], " \t\r\n");
            unit.kind = "type";
            unit.name = try a.dupe(u8, name_t);
            unit.ctype = try a.dupe(u8, name_t); // struct tag == name
            if (brace < rest.len) {
                const rel_close = std.mem.indexOfScalar(u8, rest[brace..], '}') orelse (rest.len - brace);
                const block = rest[brace + 1 .. brace + rel_close];
                const fp = try schemeParseFields(a, block);
                unit.fields = fp.fields;
                unit.fieldnames = fp.names;
                unit.fieldcount = fp.count;
            }
        } else if (std.mem.startsWith(u8, t, "fn") and (t.len == 2 or t[2] == ' ' or t[2] == '\t')) {
            const rest = std.mem.trim(u8, t[2..], " \t\r\n");
            const paren = std.mem.indexOfScalar(u8, rest, '(') orelse rest.len;
            unit.kind = "fn";
            unit.name = try a.dupe(u8, std.mem.trim(u8, rest[0..paren], " \t\r\n"));
            if (paren < rest.len) {
                const rel_close = std.mem.indexOfScalar(u8, rest[paren..], ')') orelse (rest.len - paren);
                const close_abs = paren + rel_close;
                const pblock = rest[paren + 1 .. close_abs];
                const fp = try schemeParseFields(a, pblock);
                unit.params = fp.fields;
                const after = rest[close_abs..];
                if (std.mem.indexOf(u8, after, "->")) |arrow| {
                    unit.ret = try a.dupe(u8, std.mem.trim(u8, after[arrow + 2 ..], " \t\r\n"));
                } else {
                    unit.ret = try a.dupe(u8, "void");
                }
            } else {
                unit.ret = try a.dupe(u8, "void");
            }
            unit.ctype = try a.dupe(u8, unit.ret);
        } else {
            // Generic unit: `kind name` or bare token.
            const sp = std.mem.indexOfScalar(u8, t, ' ') orelse t.len;
            if (sp < t.len) {
                unit.kind = try a.dupe(u8, t[0..sp]);
                unit.name = try a.dupe(u8, std.mem.trim(u8, t[sp..], " \t\r\n"));
            } else {
                unit.kind = "unit";
                unit.name = try a.dupe(u8, t);
            }
            unit.ctype = try a.dupe(u8, unit.name);
        }
        try out.append(a, unit);
    }
    return out.toOwnedSlice(a);
}

/// Substitute `$kind`/`$name`/`$ctype`/`$fields`/`$fieldnames`/`$fieldcount`/
/// `$params`/`$ret` placeholders in `body` for one scheme unit.
fn schemeSubst(a: std.mem.Allocator, body: []const u8, unit: SchemeUnit) ![]u8 {
    var fc_buf: [32]u8 = undefined;
    const fc_str = std.fmt.bufPrint(&fc_buf, "{d}", .{unit.fieldcount}) catch "0";
    var cur = try a.dupe(u8, body);
    const Rep = struct { needle: []const u8, val: []const u8 };
    const reps = [_]Rep{
        .{ .needle = "$kind", .val = unit.kind },
        .{ .needle = "$name", .val = unit.name },
        .{ .needle = "$ctype", .val = unit.ctype },
        .{ .needle = "$fields", .val = unit.fields },
        .{ .needle = "$fieldnames", .val = unit.fieldnames },
        .{ .needle = "$fieldcount", .val = fc_str },
        .{ .needle = "$params", .val = unit.params },
        .{ .needle = "$ret", .val = unit.ret },
    };
    for (reps) |r| {
        const next = try templateReplaceAll(a, cur, r.needle, r.val);
        cur = next;
    }
    return cur;
}

/// `@comp.scheme(declarations, template[, fn])` — declarative program scheme →
/// full implementation. One pipe-separated spec yields a struct typedef + field
/// metadata + function signatures, expanded per unit. Comptime-only → native C.
pub fn comptimeSchemeHook(host: Host, declarations: []const u8, template: []const u8, callback: ?comptime_eval.Value, alloc: std.mem.Allocator) ?comptime_eval.Value {
    return comptimeSchemeDeclTemplateHook(host, declarations, template, callback, alloc);
}

fn comptimeSchemeDeclTemplateHook(host: Host, declarations: []const u8, template: []const u8, callback: ?comptime_eval.Value, alloc: std.mem.Allocator) ?comptime_eval.Value {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();
    const units = schemeSplitDecls(a, declarations) catch return null;
    if (units.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    const count: i64 = @intCast(units.len);
    var index: i64 = 0;
    for (units) |u| {
        if (callback) |cb| {
            if (cb != .func) return null;
            var entries: [10]comptime_eval.Value.TableEntry = .{
                .{ .name = "kind", .val = .{ .string = u.kind } },
                .{ .name = "name", .val = .{ .string = u.name } },
                .{ .name = "ctype", .val = .{ .string = u.ctype } },
                .{ .name = "fields", .val = .{ .string = u.fields } },
                .{ .name = "fieldnames", .val = .{ .string = u.fieldnames } },
                .{ .name = "fieldcount", .val = .{ .int = u.fieldcount } },
                .{ .name = "params", .val = .{ .string = u.params } },
                .{ .name = "ret", .val = .{ .string = u.ret } },
                .{ .name = "index", .val = .{ .int = index } },
                .{ .name = "count", .val = .{ .int = count } },
            };
            const meta = metaCallbackTable(a, &entries) catch return null;
            defer a.free(meta.table);
            const piece = comptime_eval.callFunctionValue(cb, &.{meta}, host.bindings, host.options) catch {
                index += 1;
                continue;
            };
            if (piece == .string) templateAppendFragment(&buf, alloc, piece.string) catch return null;
        } else {
            const expanded = schemeSubst(a, template, u) catch return null;
            templateAppendFragment(&buf, alloc, expanded) catch return null;
        }
        index += 1;
    }
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

test "meta_codegen: comptimeSchemeHook type+fn expansion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const record_aliases: std.StringHashMapUnmanaged(RT) = .empty;
    const alias_defs: std.StringHashMapUnmanaged(*const ast.AliasDef) = .empty;
    const host = Host{
        .alloc = alloc,
        .mod = null,
        .record_aliases = &record_aliases,
        .alias_defs = &alias_defs,
        .concepts = null,
        .bindings = .{ .scopes = &.{} },
        .options = .{ .alloc = alloc },
    };
    const decls = "type Point { x: double, y: double } | fn add(a: Point, b: Point) -> Point";
    const tmpl = "/* scheme[$kind $name] fields={$fields} params={$params} ret=$ret */\n";
    const result = comptimeSchemeDeclTemplateHook(host, decls, tmpl, null, alloc) orelse return error.TestExpectedEqual;
    defer alloc.free(result.string);
    try std.testing.expect(std.mem.indexOf(u8, result.string, "scheme[type Point]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.string, "fields={double x, double y}") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.string, "scheme[fn add]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.string, "params={Point a, Point b}") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.string, "ret=Point") != null);
}

test "meta_codegen: comptimeTemplateHook named callback" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const record_aliases: std.StringHashMapUnmanaged(RT) = .empty;
    const alias_defs: std.StringHashMapUnmanaged(*const ast.AliasDef) = .empty;
    var lex = @import("lexer.zig").Lexer.init(
        \\fun cb(m) "/* " .. m.name .. ":" .. m.ctype .. " */\n"
    , "test");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    var module = try parser.parse_module();
    var semantic = sema.Sema.init(alloc);
    defer semantic.deinit();
    try semantic.check_module(&module);
    const fd = &module.body.stmts[0].func_decl;
    const cb = comptime_eval.funcValue(&fd.func, .{ .scopes = &.{} }, .{ .alloc = alloc }) catch return error.TestExpectedEqual;
    const host = Host{
        .alloc = alloc,
        .mod = &module,
        .record_aliases = &record_aliases,
        .alias_defs = &alias_defs,
        .concepts = null,
        .bindings = .{ .scopes = &.{} },
        .options = .{ .alloc = alloc },
    };
    const result = comptimeTemplateHook(host, "i64:int64_t|f64:double", "", cb, alloc) orelse return error.TestExpectedEqual;
    defer alloc.free(result.string);
    try std.testing.expect(std.mem.indexOf(u8, result.string, "i64:int64_t") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.string, "f64:double") != null);
}

test "meta_codegen: comptimeTemplateHook substitution" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const record_aliases: std.StringHashMapUnmanaged(RT) = .empty;
    const alias_defs: std.StringHashMapUnmanaged(*const ast.AliasDef) = .empty;
    const host = Host{
        .alloc = alloc,
        .mod = null,
        .record_aliases = &record_aliases,
        .alias_defs = &alias_defs,
        .concepts = null,
        .bindings = .{ .scopes = &.{} },
        .options = .{ .alloc = alloc },
    };
    const instances = "i64:int64_t | f64:double";
    const body = "/* $0:$1 */\n";
    const result = comptimeTemplateHook(host, instances, body, null, alloc) orelse return error.TestExpectedEqual;
    defer alloc.free(result.string);
    try std.testing.expect(std.mem.indexOf(u8, result.string, "i64:int64_t") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.string, "f64:double") != null);
}

const GenerateConstraints = struct {
    instances: []const u8,
    template: []const u8,
};

fn generateKeyMatches(key: []const u8, target: []const u8) bool {
    if (key.len != target.len) return false;
    for (key, target) |a, b| {
        if (std.ascii.toLower(a) != std.ascii.toLower(b)) return false;
    }
    return true;
}

fn generateParseConstraints(alloc: std.mem.Allocator, spec: []const u8, fallback_body: []const u8) !GenerateConstraints {
    var instances: ?[]const u8 = null;
    var type_axis: ?[]const u8 = null;
    var template: ?[]const u8 = null;
    var iter = std.mem.splitSequence(u8, spec, "\n");
    while (iter.next()) |line| {
        const trimmed = templateTrim(line);
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse continue;
        const key = templateTrim(trimmed[0..colon]);
        const val = templateTrim(trimmed[colon + 1 ..]);
        if (generateKeyMatches(key, "ops") or generateKeyMatches(key, "requires") or generateKeyMatches(key, "instances")) {
            instances = try alloc.dupe(u8, val);
        } else if (generateKeyMatches(key, "types") or generateKeyMatches(key, "type") or generateKeyMatches(key, "ctype")) {
            type_axis = try alloc.dupe(u8, val);
        } else if (generateKeyMatches(key, "template") or generateKeyMatches(key, "body")) {
            template = try alloc.dupe(u8, val);
        }
    }
    if (instances == null and type_axis == null) return error.InvalidConstraints;
    defer if (instances) |ops| alloc.free(ops);
    defer if (type_axis) |tys| alloc.free(tys);

    var axis: std.ArrayListUnmanaged(u8) = .empty;
    errdefer axis.deinit(alloc);
    if (instances) |ops| {
        if (type_axis) |tys| {
            var oi = std.mem.splitSequence(u8, ops, "|");
            while (oi.next()) |oraw| {
                const oname = templateTrim(oraw);
                if (oname.len == 0) continue;
                var ti = std.mem.splitSequence(u8, tys, "|");
                while (ti.next()) |traw| {
                    const ttrim = templateTrim(traw);
                    if (ttrim.len == 0) continue;
                    const colon_pos = std.mem.indexOfScalar(u8, ttrim, ':');
                    const type_label = if (colon_pos) |cp| templateTrim(ttrim[0..cp]) else ttrim;
                    const ctype = if (colon_pos) |cp| templateTrim(ttrim[cp + 1 ..]) else ttrim;
                    if (axis.items.len > 0) try axis.append(alloc, '|');
                    try axis.appendSlice(alloc, oname);
                    try axis.append(alloc, '_');
                    try axis.appendSlice(alloc, type_label);
                    try axis.append(alloc, ':');
                    try axis.appendSlice(alloc, ctype);
                }
            }
        } else {
            try axis.appendSlice(alloc, ops);
        }
    } else if (type_axis) |tys| {
        try axis.appendSlice(alloc, tys);
    }

    const tmpl = template orelse try alloc.dupe(u8, fallback_body);
    return .{
        .instances = try axis.toOwnedSlice(alloc),
        .template = tmpl,
    };
}

fn generateLooksLikeConstraints(spec: []const u8) bool {
    if (std.mem.indexOfScalar(u8, spec, '\n') == null) return false;
    return std.mem.indexOf(u8, spec, "ops:") != null or
        std.mem.indexOf(u8, spec, "Ops:") != null or
        std.mem.indexOf(u8, spec, "requires:") != null or
        std.mem.indexOf(u8, spec, "instances:") != null or
        std.mem.indexOf(u8, spec, "types:") != null or
        std.mem.indexOf(u8, spec, "template:") != null;
}

/// `@comp.generate(spec, body[, fn])` — constraint block (multiline) or comma-list alias.
pub fn comptimeGenerateHook(host: Host, spec: []const u8, body: []const u8, callback: ?comptime_eval.Value, alloc: std.mem.Allocator) ?comptime_eval.Value {
    if (generateLooksLikeConstraints(spec)) {
        const parsed = generateParseConstraints(alloc, spec, body) catch return null;
        defer alloc.free(parsed.instances);
        const tmpl = parsed.template;
        const tmpl_owned = parsed.template.ptr != body.ptr;
        const out = comptimeTemplateHook(host, parsed.instances, tmpl, callback, alloc);
        if (tmpl_owned) alloc.free(tmpl);
        return out;
    }
    const normalized = alloc.dupe(u8, spec) catch return null;
    defer alloc.free(normalized);
    for (normalized) |*c| {
        if (c.* == ',') c.* = '|';
    }
    return comptimeTemplateHook(host, normalized, body, callback, alloc);
}

const SchemeClause = struct {
    name: []const u8,
    body: []const u8,
};

fn schemeParseClauses(alloc: std.mem.Allocator, spec: []const u8) ![]SchemeClause {
    var out: std.ArrayListUnmanaged(SchemeClause) = .empty;
    errdefer out.deinit(alloc);
    var iter = std.mem.splitSequence(u8, spec, ";");
    while (iter.next()) |raw| {
        const trimmed = templateTrim(raw);
        if (trimmed.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse continue;
        const name = templateTrim(trimmed[0..colon]);
        const body = templateTrim(trimmed[colon + 1 ..]);
        if (name.len == 0 or body.len == 0) continue;
        try out.append(alloc, .{
            .name = try alloc.dupe(u8, name),
            .body = try alloc.dupe(u8, body),
        });
    }
    return try out.toOwnedSlice(alloc);
}

/// `@comp.scheme.clauses("name: body; name2: body2"[, fn])` — named clause emission (O(clauses)).
pub fn comptimeSchemeClausesHook(host: Host, spec: []const u8, callback: ?comptime_eval.Value, alloc: std.mem.Allocator) ?comptime_eval.Value {
    const clauses = schemeParseClauses(alloc, spec) catch return null;
    defer {
        for (clauses) |c| {
            alloc.free(c.name);
            alloc.free(c.body);
        }
        alloc.free(clauses);
    }
    if (clauses.len == 0) return .{ .string = alloc.dupe(u8, "") catch return null };

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);
    const count: i64 = @intCast(clauses.len);
    var index: i64 = 0;
    for (clauses) |clause| {
        if (callback) |cb| {
            if (cb != .func) return null;
            var entries: [4]comptime_eval.Value.TableEntry = .{
                .{ .name = "name", .val = .{ .string = clause.name } },
                .{ .name = "body", .val = .{ .string = clause.body } },
                .{ .name = "index", .val = .{ .int = index } },
                .{ .name = "count", .val = .{ .int = count } },
            };
            const meta = metaCallbackTable(alloc, &entries) catch return null;
            defer alloc.free(meta.table);
            const piece = comptime_eval.callFunctionValue(cb, &.{meta}, host.bindings, host.options) catch {
                index += 1;
                continue;
            };
            if (piece == .string) templateAppendFragment(&buf, alloc, piece.string) catch return null;
        } else {
            templateAppendFragment(&buf, alloc, clause.body) catch return null;
        }
        index += 1;
    }
    return .{ .string = buf.toOwnedSlice(alloc) catch return null };
}

test "meta_codegen: comptimeSchemeClausesHook" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const record_aliases: std.StringHashMapUnmanaged(RT) = .empty;
    const alias_defs: std.StringHashMapUnmanaged(*const ast.AliasDef) = .empty;
    const host = Host{
        .alloc = alloc,
        .mod = null,
        .record_aliases = &record_aliases,
        .alias_defs = &alias_defs,
        .concepts = null,
        .bindings = .{ .scopes = &.{} },
        .options = .{ .alloc = alloc },
    };
    const spec = "a: /* a */; b: /* b */";
    const result = comptimeSchemeClausesHook(host, spec, null, alloc) orelse return error.TestExpectedEqual;
    defer alloc.free(result.string);
    try std.testing.expect(std.mem.indexOf(u8, result.string, "/* a */") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.string, "/* b */") != null);
}

test "meta_codegen: comptimeGenerateHook constraints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const record_aliases: std.StringHashMapUnmanaged(RT) = .empty;
    const alias_defs: std.StringHashMapUnmanaged(*const ast.AliasDef) = .empty;
    const host = Host{
        .alloc = alloc,
        .mod = null,
        .record_aliases = &record_aliases,
        .alias_defs = &alias_defs,
        .concepts = null,
        .bindings = .{ .scopes = &.{} },
        .options = .{ .alloc = alloc },
    };
    const spec =
        \\ops: add | sub
        \\types: i64:int64_t | f64:double
        \\template: /* $0:$1 */
    ;
    const result = comptimeGenerateHook(host, spec, "", null, alloc) orelse return error.TestExpectedEqual;
    defer alloc.free(result.string);
    try std.testing.expect(std.mem.indexOf(u8, result.string, "add_i64:int64_t") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.string, "sub_f64:double") != null);
    try std.testing.expect(result.string[result.string.len - 1] == '\n');
}

test "meta_codegen: grammarParseRules and expansion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const spec = "S: a | b c ; c: x | y";
    var rules = try grammarParseRules(alloc, spec);
    defer {
        var rit = rules.iterator();
        while (rit.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |a| alloc.free(a);
            alloc.free(entry.value_ptr.*);
        }
        rules.deinit(alloc);
    }
    try std.testing.expect(rules.get("S") != null);
    try std.testing.expect(rules.get("c") != null);
    var expansions: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (expansions.items) |e| alloc.free(e);
        expansions.deinit(alloc);
    }
    try grammarExpandRule(alloc, &rules, "S", 4, &expansions);
    try std.testing.expect(expansions.items.len >= 3);
}

test "meta_codegen: parseOmniDirective" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const rule = try parseOmniDirective(alloc, "\"HasXY\", TouchApi, \"HasTag\"");
    defer {
        alloc.free(rule.?.concept_a);
        alloc.free(rule.?.concept_b);
        for (rule.?.derive_names) |n| alloc.free(n);
        alloc.free(rule.?.derive_names);
    }
    try std.testing.expect(rule != null);
    try std.testing.expectEqualStrings("HasXY", rule.?.concept_a);
    try std.testing.expectEqualStrings("HasTag", rule.?.concept_b);
    try std.testing.expectEqual(@as(usize, 1), rule.?.derive_names.len);
    try std.testing.expectEqualStrings("TouchApi", rule.?.derive_names[0]);
}

test "meta_codegen: parseTranscendDirective" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const rule = try parseTranscendDirective(alloc, "\"HasXY\", TouchApi, \"HasTag\", \"HasId\"");
    defer {
        alloc.free(rule.?.concept_a);
        alloc.free(rule.?.concept_b);
        alloc.free(rule.?.concept_c);
        for (rule.?.derive_names) |n| alloc.free(n);
        alloc.free(rule.?.derive_names);
    }
    try std.testing.expect(rule != null);
    try std.testing.expectEqualStrings("HasXY", rule.?.concept_a);
    try std.testing.expectEqualStrings("HasTag", rule.?.concept_b);
    try std.testing.expectEqualStrings("HasId", rule.?.concept_c);
}

test "meta_codegen: parseInfinityDirective" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const rule = try parseInfinityDirective(alloc, "\"HasXY\", TouchApi, \"HasTag\", \"HasId\", \"HasExtra\"");
    defer {
        alloc.free(rule.?.concept_a);
        alloc.free(rule.?.concept_b);
        alloc.free(rule.?.concept_c);
        alloc.free(rule.?.concept_d);
        for (rule.?.derive_names) |n| alloc.free(n);
        alloc.free(rule.?.derive_names);
    }
    try std.testing.expect(rule != null);
    try std.testing.expectEqualStrings("HasExtra", rule.?.concept_d);
}
