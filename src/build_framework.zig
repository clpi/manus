/// Inline `@build.*` project model — resolves targets from sema-collected directives.
const std = @import("std");
const ast = @import("ast.zig");
const directives = @import("directives.zig");
const Sema = @import("sema.zig").Sema;

pub const TargetKind = enum {
    exe,
    run,
    lib,
    @"test",
    bench,
    check,
    fmt,
    clean,
};

pub const Target = struct {
    name: []const u8,
    kind: TargetKind,
    src: ?[]const u8 = null,
    out: ?[]const u8 = null,
    cc: ?[]const u8 = null,
    opt: ?[]const u8 = null,
    target: ?[]const u8 = null,
    load_chunk: bool = false,
    pgo: bool = false,
    lib_mode: bool = false,
    shared_mem: bool = false,
    link: []const []const u8 = &.{},
    stage: i32 = 0,
    deps: []const []const u8 = &.{},

    pub fn test_mode(self: Target) bool {
        return self.kind == .@"test";
    }

    pub fn bench_mode(self: Target) bool {
        return self.kind == .bench;
    }

    pub fn needs_compile(self: Target) bool {
        return switch (self.kind) {
            .check, .fmt, .clean => false,
            else => true,
        };
    }
};

pub const Project = struct {
    build_source: []const u8,
    name: ?[]const u8 = null,
    version: ?[]const u8 = null,
    default_target: ?[]const u8 = null,
    targets: []Target,

    pub fn deinit(self: *Project, alloc: std.mem.Allocator) void {
        if (self.name) |n| alloc.free(n);
        if (self.version) |v| alloc.free(v);
        if (self.default_target) |d| alloc.free(d);
        for (self.targets) |*t| {
            alloc.free(t.name);
            if (t.src) |s| alloc.free(s);
            if (t.out) |o| alloc.free(o);
            if (t.cc) |c| alloc.free(c);
            if (t.opt) |o| alloc.free(o);
            if (t.target) |tg| alloc.free(tg);
            for (t.link) |l| alloc.free(l);
            alloc.free(t.link);
            for (t.deps) |d| alloc.free(d);
            alloc.free(t.deps);
        }
        alloc.free(self.targets);
    }
};

fn dupOpt(alloc: std.mem.Allocator, raw: ?[]const u8) !?[]const u8 {
    if (raw) |r| return try alloc.dupe(u8, r);
    return null;
}

fn parseBool(map: *const directives.ArgMap, key: []const u8, default: bool) bool {
    const raw = map.get(key) orelse return default;
    if (std.mem.eql(u8, raw, "true")) return true;
    if (std.mem.eql(u8, raw, "false")) return false;
    return default;
}

fn parseI32(map: *const directives.ArgMap, key: []const u8, default: i32) i32 {
    const raw = map.get(key) orelse return default;
    return std.fmt.parseInt(i32, raw, 10) catch default;
}

fn parseCsvList(alloc: std.mem.Allocator, raw: []const u8) ![]const []const u8 {
    var parts = std.mem.splitScalar(u8, raw, ',');
    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (list.items) |p| alloc.free(p);
        list.deinit(alloc);
    }
    while (parts.next()) |part| {
        const piece = std.mem.trim(u8, part, " \t");
        if (piece.len == 0) continue;
        try list.append(alloc, try alloc.dupe(u8, piece));
    }
    return try list.toOwnedSlice(alloc);
}

fn parseLinkList(alloc: std.mem.Allocator, map: *const directives.ArgMap) ![]const []const u8 {
    const raw = map.get("link") orelse return try alloc.alloc([]const u8, 0);
    return parseCsvList(alloc, raw);
}

fn parseDepsList(alloc: std.mem.Allocator, map: *const directives.ArgMap) ![]const []const u8 {
    const raw = map.get("deps") orelse return try alloc.alloc([]const u8, 0);
    return parseCsvList(alloc, raw);
}

fn kindFromAttr(name: []const u8) ?TargetKind {
    if (std.mem.eql(u8, name, "build.exe")) return .exe;
    if (std.mem.eql(u8, name, "build.run")) return .run;
    if (std.mem.eql(u8, name, "build.lib")) return .lib;
    if (std.mem.eql(u8, name, "build.test")) return .@"test";
    if (std.mem.eql(u8, name, "build.bench")) return .bench;
    if (std.mem.eql(u8, name, "build.check")) return .check;
    if (std.mem.eql(u8, name, "build.fmt")) return .fmt;
    if (std.mem.eql(u8, name, "build.clean")) return .clean;
    return null;
}

fn targetFromAttr(alloc: std.mem.Allocator, attr: ast.Attribute) !?Target {
    const kind = kindFromAttr(attr.name) orelse return null;
    var map = try directives.parseAttrArgs(alloc, attr.args);
    defer map.deinit(alloc);

    const src = try dupOpt(alloc, map.get("src"));
    const default_name = if (src) |s| std.fs.path.stem(s) else "target";
    const name_raw = map.get("name") orelse default_name;
    const name = try alloc.dupe(u8, name_raw);

    var lib_mode = kind == .lib or parseBool(&map, "lib", false);
    if (kind == .lib) lib_mode = true;

    const link = try parseLinkList(alloc, &map);
    const deps = try parseDepsList(alloc, &map);

    return Target{
        .name = name,
        .kind = kind,
        .src = src,
        .out = try dupOpt(alloc, map.get("out")),
        .cc = try dupOpt(alloc, map.get("cc")),
        .opt = try dupOpt(alloc, map.get("opt")),
        .target = try dupOpt(alloc, map.get("target")),
        .load_chunk = parseBool(&map, "load_chunk", false),
        .pgo = parseBool(&map, "pgo", false),
        .lib_mode = lib_mode,
        .shared_mem = parseBool(&map, "shared_memory", false) or parseBool(&map, "shared_mem", false),
        .link = link,
        .stage = parseI32(&map, "stage", 0),
        .deps = deps,
    };
}

pub fn kindLabel(kind: TargetKind) []const u8 {
    return switch (kind) {
        .exe => "exe",
        .run => "run",
        .lib => "lib",
        .@"test" => "test",
        .bench => "bench",
        .check => "check",
        .fmt => "fmt",
        .clean => "clean",
    };
}

pub fn kindGlyph(kind: TargetKind) []const u8 {
    return switch (kind) {
        .exe, .run => "◆",
        .lib => "◇",
        .@"test" => "▸",
        .bench => "⏱",
        .check => "✓",
        .fmt => "¶",
        .clean => "⌫",
    };
}

pub fn loadFromSema(alloc: std.mem.Allocator, build_source: []const u8, sem: *const Sema) !Project {
    var targets: std.ArrayListUnmanaged(Target) = .empty;
    errdefer {
        for (targets.items) |*t| {
            alloc.free(t.name);
            if (t.src) |s| alloc.free(s);
            if (t.out) |o| alloc.free(o);
            if (t.cc) |c| alloc.free(c);
            if (t.opt) |o| alloc.free(o);
            if (t.target) |tg| alloc.free(tg);
            for (t.link) |l| alloc.free(l);
            alloc.free(t.link);
            for (t.deps) |d| alloc.free(d);
            alloc.free(t.deps);
        }
        targets.deinit(alloc);
    }

    var project_name: ?[]const u8 = null;
    var project_version: ?[]const u8 = null;
    var default_target: ?[]const u8 = null;

    for (sem.build_directives.items) |attr| {
        if (std.mem.eql(u8, attr.name, "build.project")) {
            var map = try directives.parseAttrArgs(alloc, attr.args);
            defer map.deinit(alloc);
            project_name = try dupOpt(alloc, map.get("name"));
            project_version = try dupOpt(alloc, map.get("version"));
            default_target = try dupOpt(alloc, map.get("default"));
            continue;
        }
        if (try targetFromAttr(alloc, attr)) |t| {
            try targets.append(alloc, t);
        }
    }

    return .{
        .build_source = build_source,
        .name = project_name,
        .version = project_version,
        .default_target = default_target,
        .targets = try targets.toOwnedSlice(alloc),
    };
}

pub fn findBuildSource(io: std.Io, requested: ?[]const u8) []const u8 {
    if (requested) |r| {
        if (std.mem.endsWith(u8, r, ".duo") or std.mem.endsWith(u8, r, ".lua")) return r;
    }
    const cwd = std.Io.Dir.cwd();
    const candidates = [_][]const u8{ "build.duo", "src/main.duo", "main.duo" };
    for (candidates) |c| {
        cwd.access(io, c, .{}) catch continue;
        return c;
    }
    return "build.duo";
}

pub const ResolveError = error{TargetNotFound, NoTargets};

pub fn resolveTarget(project: *const Project, requested: ?[]const u8, prefer_kind: ?TargetKind) !Target {
    // Explicit name request takes priority
    if (requested) |name| {
        for (project.targets) |t| {
            if (std.mem.eql(u8, t.name, name)) return t;
        }
        return ResolveError.TargetNotFound;
    }
    // Prefer kind (e.g. looking for a test target when running `duo test`)
    if (prefer_kind) |pk| {
        for (project.targets) |t| {
            if (t.kind == pk) return t;
        }
    }
    // Fall back to default target name
    if (project.default_target) |name| {
        for (project.targets) |t| {
            if (std.mem.eql(u8, t.name, name)) return t;
        }
    }
    if (project.targets.len == 0) return ResolveError.NoTargets;
    return project.targets[0];
}

/// Indices into `project.targets` in build order: topological on `deps`, then `stage`, then name.
pub fn sortBuildOrder(alloc: std.mem.Allocator, project: *const Project) ![]usize {
    const n = project.targets.len;
    if (n == 0) return try alloc.alloc(usize, 0);

    var name_to_idx = std.StringHashMap(usize).init(alloc);
    defer name_to_idx.deinit();
    for (project.targets, 0..) |t, i| {
        try name_to_idx.put(t.name, i);
    }

    var in_degree = try alloc.alloc(u32, n);
    defer alloc.free(in_degree);
    @memset(in_degree, 0);

    var dependents = try alloc.alloc(std.ArrayListUnmanaged(usize), n);
    defer {
        for (dependents) |*d| d.deinit(alloc);
        alloc.free(dependents);
    }
    for (dependents) |*d| d.* = .empty;

    for (project.targets, 0..) |t, i| {
        for (t.deps) |dep_name| {
            const dep_idx = name_to_idx.get(dep_name) orelse continue;
            try dependents[dep_idx].append(alloc, i);
            in_degree[i] += 1;
        }
    }

    var ready: std.ArrayListUnmanaged(usize) = .empty;
    defer ready.deinit(alloc);
    for (in_degree, 0..) |deg, i| {
        if (deg == 0) try ready.append(alloc, i);
    }

    const lessReady = struct {
        fn cmp(ctx: *const Project, a: usize, b: usize) bool {
            const ta = ctx.targets[a];
            const tb = ctx.targets[b];
            if (ta.stage != tb.stage) return ta.stage < tb.stage;
            return std.mem.order(u8, ta.name, tb.name) == .lt;
        }
    }.cmp;

    var order: std.ArrayListUnmanaged(usize) = .empty;
    errdefer order.deinit(alloc);

    while (ready.items.len > 0) {
        std.mem.sort(usize, ready.items, project, lessReady);
        const idx = ready.orderedRemove(0);
        try order.append(alloc, idx);
        for (dependents[idx].items) |dep| {
            in_degree[dep] -= 1;
            if (in_degree[dep] == 0) try ready.append(alloc, dep);
        }
    }

    if (order.items.len != n) {
        order.deinit(alloc);
        const fallback = try alloc.alloc(usize, n);
        for (fallback, 0..) |*idx, i| idx.* = i;
        const lessThan = struct {
            fn cmp(ctx: *const Project, a: usize, b: usize) bool {
                const ta = ctx.targets[a];
                const tb = ctx.targets[b];
                if (ta.stage != tb.stage) return ta.stage < tb.stage;
                return std.mem.order(u8, ta.name, tb.name) == .lt;
            }
        }.cmp;
        std.mem.sort(usize, fallback, project, lessThan);
        return fallback;
    }

    return try order.toOwnedSlice(alloc);
}

pub fn nearestTargetName(name: []const u8, project: *const Project) ?[]const u8 {
    var best: ?[]const u8 = null;
    var best_score: usize = 0;
    for (project.targets) |t| {
        if (std.mem.eql(u8, t.name, name)) return t.name;
        if (std.mem.startsWith(u8, t.name, name) or std.mem.startsWith(u8, name, t.name)) {
            const score = @min(t.name.len, name.len);
            if (score > best_score) {
                best_score = score;
                best = t.name;
            }
        }
    }
    return best;
}

pub fn listTargetNames(alloc: std.mem.Allocator, project: *const Project) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(alloc);
    for (project.targets, 0..) |t, i| {
        if (i > 0) try buf.append(alloc, ',');
        try buf.appendSlice(alloc, t.name);
    }
    return try buf.toOwnedSlice(alloc);
}

test "build_framework: load targets from sema directives" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\@build.project({ name = "demo", default = "app" })
        \\@build.run({ name = "app", src = "main.duo" })
        \\@build.test({ name = "test", src = "tests.duo", out = "zig-out/bin/t" })
        \\@build.clean({ name = "clean" })
        \\
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "build.duo");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);

    var project = try loadFromSema(alloc, "build.duo", &sem);
    defer project.deinit(alloc);

    try std.testing.expectEqualStrings("demo", project.name.?);
    try std.testing.expectEqualStrings("app", project.default_target.?);
    try std.testing.expect(project.targets.len == 3);

    const app = try resolveTarget(&project, "app", null);
    try std.testing.expect(app.kind == .run);
    try std.testing.expectEqualStrings("main.duo", app.src.?);

    const test_t = try resolveTarget(&project, null, .@"test");
    try std.testing.expect(test_t.kind == .@"test");

    const clean = try resolveTarget(&project, "clean", null);
    try std.testing.expect(clean.kind == .clean);
    try std.testing.expect(!clean.needs_compile());
}

test "build_framework: lua --- @build module directives" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\--- @build.project({ name = "luaapp", default = "app" })
        \\--- @build.test({ name = "test", src = "main.lua" })
        \\function hello()
        \\end
        \\
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "main.lua");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    try sem.check_module(&mod);

    var project = try loadFromSema(alloc, "main.lua", &sem);
    defer project.deinit(alloc);

    try std.testing.expectEqualStrings("luaapp", project.name.?);
    try std.testing.expect(project.targets.len == 1);
    const test_t = try resolveTarget(&project, null, .@"test");
    try std.testing.expect(test_t.kind == .@"test");
}

test "build_framework: sortBuildOrder respects deps" {
    const alloc = std.testing.allocator;
    const lib_dep = try alloc.dupe(u8, "lib");
    const lib_name = try alloc.dupe(u8, "lib");
    const app_name = try alloc.dupe(u8, "app");
    const tools_name = try alloc.dupe(u8, "tools");
    const app_deps = try alloc.dupe([]const u8, &.{lib_dep});
    var project = Project{
        .build_source = "build.duo",
        .name = null,
        .version = null,
        .default_target = null,
        .targets = try alloc.alloc(Target, 3),
    };
    defer project.deinit(alloc);
    project.targets[0] = .{ .name = app_name, .kind = .run, .deps = app_deps };
    project.targets[1] = .{ .name = lib_name, .kind = .lib, .deps = try alloc.alloc([]const u8, 0) };
    project.targets[2] = .{ .name = tools_name, .kind = .exe, .stage = 1, .deps = try alloc.alloc([]const u8, 0) };

    const order = try sortBuildOrder(alloc, &project);
    defer alloc.free(order);
    try std.testing.expect(order.len == 3);
    try std.testing.expectEqualStrings("lib", project.targets[order[0]].name);
    try std.testing.expectEqualStrings("app", project.targets[order[1]].name);
}
