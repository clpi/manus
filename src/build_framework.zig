/// Inline `@build.*` project model — resolves targets from sema-collected directives.
const std = @import("std");
const ast = @import("ast.zig");
const directives = @import("directives.zig");
const Sema = @import("sema.zig").Sema;
const family = @import("lexer_bridge.zig");

const canonical = family.CANONICAL_SOURCE_SUFFIX;
const historical = family.HISTORICAL_SOURCE_SUFFIX;

const build_source_candidates = [_][]const u8{
    "build" ++ canonical,
    "src/build" ++ canonical,
    "build" ++ historical,
    "src/build" ++ historical,
    "src/main" ++ canonical,
    "main" ++ canonical,
    "src/main" ++ historical,
    "main" ++ historical,
    "src/main.lua",
    "main.lua",
    "src/init" ++ canonical,
    "init" ++ canonical,
    "src/init" ++ historical,
    "init" ++ historical,
    "src/init.lua",
    "init.lua",
};

const entrypoint_candidates = [_][]const u8{
    "src/main" ++ canonical,
    "main" ++ canonical,
    "src/main" ++ historical,
    "main" ++ historical,
    "src/main.lua",
    "main.lua",
    "src/init" ++ canonical,
    "init" ++ canonical,
    "src/init" ++ historical,
    "init" ++ historical,
    "src/init.lua",
    "init.lua",
};

pub fn buildSourceCandidates() []const []const u8 {
    return &build_source_candidates;
}

pub const TargetKind = enum {
    exe,
    run,
    lib,
    @"test",
    bench,
    check,
    fmt,
    clean,
    command,
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
    stage_name: ?[]const u8 = null,
    deps: []const []const u8 = &.{},
    command: ?[]const u8 = null,

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

pub const Stage = struct {
    name: []const u8,
    order: i32 = 0,
    desc: ?[]const u8 = null,
};

pub const Project = struct {
    build_source: []const u8,
    name: ?[]const u8 = null,
    version: ?[]const u8 = null,
    default_target: ?[]const u8 = null,
    stages: []Stage,
    targets: []Target,

    pub fn deinit(self: *Project, alloc: std.mem.Allocator) void {
        if (self.name) |n| alloc.free(n);
        if (self.version) |v| alloc.free(v);
        if (self.default_target) |d| alloc.free(d);
        for (self.stages) |*s| {
            alloc.free(s.name);
            if (s.desc) |d| alloc.free(d);
        }
        alloc.free(self.stages);
        for (self.targets) |*t| {
            alloc.free(t.name);
            if (t.src) |s| alloc.free(s);
            if (t.out) |o| alloc.free(o);
            if (t.cc) |c| alloc.free(c);
            if (t.opt) |o| alloc.free(o);
            if (t.target) |tg| alloc.free(tg);
            if (t.stage_name) |s| alloc.free(s);
            if (t.command) |c| alloc.free(c);
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

fn parseOpt(alloc: std.mem.Allocator, map: *const directives.ArgMap) !?[]const u8 {
    if (map.get("opt")) |raw| return try alloc.dupe(u8, raw);
    if (map.get("optimize")) |raw| {
        if (std.mem.startsWith(u8, raw, "-O")) return try alloc.dupe(u8, raw);
        if (std.mem.startsWith(u8, raw, "O")) return try std.fmt.allocPrint(alloc, "-{s}", .{raw});
        return try std.fmt.allocPrint(alloc, "-O{s}", .{raw});
    }
    return null;
}

fn appendOptValue(alloc: std.mem.Allocator, buf: *std.ArrayListUnmanaged(u8), raw: []const u8) !void {
    if (std.mem.startsWith(u8, raw, "-O")) {
        try buf.appendSlice(alloc, raw);
    } else if (std.mem.startsWith(u8, raw, "O")) {
        try buf.append(alloc, '-');
        try buf.appendSlice(alloc, raw);
    } else {
        try buf.appendSlice(alloc, "-O");
        try buf.appendSlice(alloc, raw);
    }
}

fn parseI32(map: *const directives.ArgMap, key: []const u8, default: i32) i32 {
    const raw = map.get(key) orelse return default;
    return std.fmt.parseInt(i32, raw, 10) catch default;
}

fn parseStageName(alloc: std.mem.Allocator, map: *const directives.ArgMap) !?[]const u8 {
    if (map.get("stage_name")) |raw| return try alloc.dupe(u8, raw);
    const raw = map.get("stage") orelse return null;
    _ = std.fmt.parseInt(i32, raw, 10) catch return try alloc.dupe(u8, raw);
    return null;
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

fn cloneStringList(alloc: std.mem.Allocator, values: []const []const u8) ![]const []const u8 {
    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (list.items) |item| alloc.free(item);
        list.deinit(alloc);
    }
    for (values) |value| {
        try list.append(alloc, try alloc.dupe(u8, value));
    }
    return try list.toOwnedSlice(alloc);
}

pub fn cloneTarget(alloc: std.mem.Allocator, target: Target) !Target {
    return .{
        .name = try alloc.dupe(u8, target.name),
        .kind = target.kind,
        .src = try dupOpt(alloc, target.src),
        .out = try dupOpt(alloc, target.out),
        .cc = try dupOpt(alloc, target.cc),
        .opt = try dupOpt(alloc, target.opt),
        .target = try dupOpt(alloc, target.target),
        .load_chunk = target.load_chunk,
        .pgo = target.pgo,
        .lib_mode = target.lib_mode,
        .shared_mem = target.shared_mem,
        .link = try cloneStringList(alloc, target.link),
        .stage = target.stage,
        .stage_name = try dupOpt(alloc, target.stage_name),
        .deps = try cloneStringList(alloc, target.deps),
        .command = try dupOpt(alloc, target.command),
    };
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
    if (std.mem.eql(u8, name, "build.command")) return .command;
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
    const command = if (map.get("command")) |cmd| try alloc.dupe(u8, cmd) else try dupOpt(alloc, map.get("cmd"));

    return Target{
        .name = name,
        .kind = kind,
        .src = src,
        .out = try dupOpt(alloc, map.get("out")),
        .cc = try dupOpt(alloc, map.get("cc")),
        .opt = try parseOpt(alloc, &map),
        .target = try dupOpt(alloc, map.get("target")),
        .load_chunk = parseBool(&map, "load_chunk", false),
        .pgo = parseBool(&map, "pgo", false),
        .lib_mode = lib_mode,
        .shared_mem = parseBool(&map, "shared_memory", false) or parseBool(&map, "shared_mem", false),
        .link = link,
        .stage = parseI32(&map, "stage", 0),
        .stage_name = try parseStageName(alloc, &map),
        .deps = deps,
        .command = command,
    };
}

fn stringLiteralAfterKey(alloc: std.mem.Allocator, source: []const u8, key: []const u8) !?[]const u8 {
    var start: usize = 0;
    while (std.mem.indexOfPos(u8, source, start, key)) |idx| {
        const before_ok = idx == 0 or (!std.ascii.isAlphanumeric(source[idx - 1]) and source[idx - 1] != '_');
        const after_idx = idx + key.len;
        const after_ok = after_idx >= source.len or (!std.ascii.isAlphanumeric(source[after_idx]) and source[after_idx] != '_');
        start = after_idx;
        if (!before_ok or !after_ok) continue;
        var i = after_idx;
        while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}
        if (i >= source.len or source[i] != '=') continue;
        i += 1;
        while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}
        if (i >= source.len or (source[i] != '"' and source[i] != '\'')) continue;
        const quote = source[i];
        i += 1;
        const value_start = i;
        while (i < source.len and source[i] != quote) : (i += 1) {}
        if (i >= source.len) return null;
        return try alloc.dupe(u8, source[value_start..i]);
    }
    return null;
}

fn findMatchingBrace(source: []const u8, open_idx: usize) ?usize {
    var depth: usize = 0;
    var i = open_idx;
    var quote: ?u8 = null;
    while (i < source.len) : (i += 1) {
        const c = source[i];
        if (quote) |q| {
            if (c == '\\' and i + 1 < source.len) {
                i += 1;
                continue;
            }
            if (c == q) quote = null;
            continue;
        }
        if (c == '"' or c == '\'') {
            quote = c;
            continue;
        }
        if (c == '{') {
            depth += 1;
        } else if (c == '}') {
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    return null;
}

fn tableBodyAfterKey(source: []const u8, key: []const u8) ?[]const u8 {
    const key_idx = std.mem.indexOf(u8, source, key) orelse return null;
    const eq_idx = std.mem.indexOfScalarPos(u8, source, key_idx + key.len, '=') orelse return null;
    const open_idx = std.mem.indexOfScalarPos(u8, source, eq_idx + 1, '{') orelse return null;
    const close_idx = findMatchingBrace(source, open_idx) orelse return null;
    return source[open_idx + 1 .. close_idx];
}

fn legacyTargetKind(name: []const u8, block: []const u8) TargetKind {
    if (std.mem.eql(u8, name, "test")) return .@"test";
    if (std.mem.eql(u8, name, "bench")) return .bench;
    if (std.mem.eql(u8, name, "lib")) return .lib;
    if (std.mem.indexOf(u8, block, "mode") != null and std.mem.indexOf(u8, block, "shared") != null) return .lib;
    return .run;
}

fn appendLegacyTarget(alloc: std.mem.Allocator, list: *std.ArrayListUnmanaged(Target), name: []const u8, block: []const u8) !void {
    const src = try stringLiteralAfterKey(alloc, block, "src") orelse try stringLiteralAfterKey(alloc, block, "entry");
    const kind = legacyTargetKind(name, block);
    var map_text: std.ArrayListUnmanaged(u8) = .empty;
    defer map_text.deinit(alloc);
    try map_text.appendSlice(alloc, "{ name = \"");
    try map_text.appendSlice(alloc, name);
    try map_text.appendSlice(alloc, "\"");
    if (src) |s| {
        try map_text.appendSlice(alloc, ", src = \"");
        try map_text.appendSlice(alloc, s);
        try map_text.appendSlice(alloc, "\"");
    }
    if (try stringLiteralAfterKey(alloc, block, "target")) |target| {
        defer alloc.free(target);
        try map_text.appendSlice(alloc, ", target = \"");
        try map_text.appendSlice(alloc, target);
        try map_text.appendSlice(alloc, "\"");
    }
    if (try stringLiteralAfterKey(alloc, block, "optimize") orelse try stringLiteralAfterKey(alloc, block, "opt")) |opt| {
        defer alloc.free(opt);
        try map_text.appendSlice(alloc, ", opt = \"");
        try appendOptValue(alloc, &map_text, opt);
        try map_text.appendSlice(alloc, "\"");
    }
    if (kind == .lib) try map_text.appendSlice(alloc, ", lib = true");
    try map_text.appendSlice(alloc, " }");
    const attr_name = switch (kind) {
        .lib => "build.lib",
        .@"test" => "build.test",
        .bench => "build.bench",
        else => "build.run",
    };
    const t = (try targetFromAttr(alloc, .{ .name = attr_name, .args = map_text.items })) orelse return;
    try list.append(alloc, t);
}

pub fn loadLegacyManifest(alloc: std.mem.Allocator, build_source: []const u8, source: []const u8) !Project {
    var targets: std.ArrayListUnmanaged(Target) = .empty;
    errdefer {
        for (targets.items) |*t| {
            alloc.free(t.name);
            if (t.src) |s| alloc.free(s);
            if (t.out) |o| alloc.free(o);
            if (t.cc) |c| alloc.free(c);
            if (t.opt) |o| alloc.free(o);
            if (t.target) |tg| alloc.free(tg);
            if (t.stage_name) |s| alloc.free(s);
            if (t.command) |c| alloc.free(c);
            for (t.link) |l| alloc.free(l);
            alloc.free(t.link);
            for (t.deps) |d| alloc.free(d);
            alloc.free(t.deps);
        }
        targets.deinit(alloc);
    }

    const targets_body = tableBodyAfterKey(source, "targets");
    if (targets_body) |body| {
        var i: usize = 0;
        while (i < body.len) : (i += 1) {
            while (i < body.len and (std.ascii.isWhitespace(body[i]) or body[i] == ',')) : (i += 1) {}
            if (i >= body.len or !(std.ascii.isAlphabetic(body[i]) or body[i] == '_')) continue;
            const name_start = i;
            i += 1;
            while (i < body.len and (std.ascii.isAlphanumeric(body[i]) or body[i] == '_')) : (i += 1) {}
            const name = body[name_start..i];
            while (i < body.len and std.ascii.isWhitespace(body[i])) : (i += 1) {}
            if (i >= body.len or body[i] != '=') continue;
            i += 1;
            while (i < body.len and std.ascii.isWhitespace(body[i])) : (i += 1) {}
            if (i >= body.len or body[i] != '{') continue;
            const close = findMatchingBrace(body, i) orelse break;
            try appendLegacyTarget(alloc, &targets, name, body[i + 1 .. close]);
            i = close;
        }
    } else if (try stringLiteralAfterKey(alloc, source, "entry")) |entry| {
        defer alloc.free(entry);
        try appendLegacyTarget(alloc, &targets, "default", source);
    }

    return .{
        .build_source = build_source,
        .name = try stringLiteralAfterKey(alloc, source, "name"),
        .version = try stringLiteralAfterKey(alloc, source, "version"),
        .default_target = if (targets.items.len > 0) try alloc.dupe(u8, targets.items[0].name) else null,
        .stages = try alloc.alloc(Stage, 0),
        .targets = try targets.toOwnedSlice(alloc),
    };
}

fn stageFromAttr(alloc: std.mem.Allocator, attr: ast.Attribute) !?Stage {
    if (!std.mem.eql(u8, attr.name, "build.stage")) return null;
    var map = try directives.parseAttrArgs(alloc, attr.args);
    defer map.deinit(alloc);
    const name_raw = map.get("name") orelse map.get("id") orelse "stage";
    return .{
        .name = try alloc.dupe(u8, name_raw),
        .order = parseI32(&map, "order", parseI32(&map, "stage", 0)),
        .desc = try dupOpt(alloc, map.get("desc") orelse map.get("description")),
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
        .command => "command",
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
        .command => "›",
    };
}

fn pathExists(io: std.Io, path: []const u8) bool {
    const cwd = std.Io.Dir.cwd();
    cwd.access(io, path, .{}) catch return false;
    return true;
}

fn isEntrypointPath(path: []const u8) bool {
    for (entrypoint_candidates) |candidate| {
        if (std.mem.eql(u8, path, candidate)) return true;
    }
    return false;
}

fn implicitTargetForSource(alloc: std.mem.Allocator, build_source: []const u8) !?Target {
    if (!isEntrypointPath(build_source)) return null;
    const base = std.fs.path.basename(build_source);
    const is_init = std.mem.startsWith(u8, base, "init.");
    const name = if (is_init) "lib" else "app";
    return .{
        .name = try alloc.dupe(u8, name),
        .kind = if (is_init) .lib else .run,
        .src = try alloc.dupe(u8, build_source),
        .out = null,
        .cc = null,
        .opt = null,
        .target = null,
        .load_chunk = false,
        .pgo = false,
        .lib_mode = is_init,
        .shared_mem = false,
        .link = try alloc.alloc([]const u8, 0),
        .stage = 0,
        .stage_name = null,
        .deps = try alloc.alloc([]const u8, 0),
        .command = null,
    };
}

pub fn loadFromSema(alloc: std.mem.Allocator, build_source: []const u8, sem: *const Sema) !Project {
    var targets: std.ArrayListUnmanaged(Target) = .empty;
    var stages: std.ArrayListUnmanaged(Stage) = .empty;
    errdefer {
        for (stages.items) |*s| {
            alloc.free(s.name);
            if (s.desc) |d| alloc.free(d);
        }
        stages.deinit(alloc);
        for (targets.items) |*t| {
            alloc.free(t.name);
            if (t.src) |s| alloc.free(s);
            if (t.out) |o| alloc.free(o);
            if (t.cc) |c| alloc.free(c);
            if (t.opt) |o| alloc.free(o);
            if (t.target) |tg| alloc.free(tg);
            if (t.stage_name) |s| alloc.free(s);
            if (t.command) |c| alloc.free(c);
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
        if (try stageFromAttr(alloc, attr)) |s| {
            try stages.append(alloc, s);
            continue;
        }
        if (try targetFromAttr(alloc, attr)) |t| {
            try targets.append(alloc, t);
        }
    }
    if (targets.items.len == 0) {
        if (try implicitTargetForSource(alloc, build_source)) |t| {
            try targets.append(alloc, t);
        }
    }

    return .{
        .build_source = build_source,
        .name = project_name,
        .version = project_version,
        .default_target = default_target,
        .stages = try stages.toOwnedSlice(alloc),
        .targets = try targets.toOwnedSlice(alloc),
    };
}

pub fn findBuildSource(io: std.Io, requested: ?[]const u8) []const u8 {
    if (requested) |r| {
        if (family.sourceFacts(r).law != .unknown) return r;
    }
    for (build_source_candidates) |c| {
        if (!pathExists(io, c)) continue;
        return c;
    }
    return "build" ++ canonical;
}

pub fn findEntrypoint(io: std.Io) ?[]const u8 {
    for (entrypoint_candidates) |c| {
        if (pathExists(io, c)) return c;
    }
    return null;
}

pub fn stageLabel(project: *const Project, target: Target) ?[]const u8 {
    if (target.stage_name) |name| return name;
    for (project.stages) |stage| {
        if (stage.order == target.stage) return stage.name;
    }
    return null;
}

pub fn stageOrder(project: *const Project, target: Target) i32 {
    if (target.stage_name) |name| {
        for (project.stages) |stage| {
            if (std.mem.eql(u8, stage.name, name)) return stage.order;
        }
    }
    return target.stage;
}

pub fn targetMatchesStage(project: *const Project, target: Target, raw: []const u8) bool {
    if (target.stage_name) |name| {
        if (std.mem.eql(u8, name, raw)) return true;
    }
    if (stageLabel(project, target)) |name| {
        if (std.mem.eql(u8, name, raw)) return true;
    }
    const wanted = std.fmt.parseInt(i32, raw, 10) catch return false;
    return stageOrder(project, target) == wanted;
}

pub const ResolveError = error{ TargetNotFound, NoTargets };

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
            const sa = stageOrder(ctx, ta);
            const sb = stageOrder(ctx, tb);
            if (sa != sb) return sa < sb;
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
                const sa = stageOrder(ctx, ta);
                const sb = stageOrder(ctx, tb);
                if (sa != sb) return sa < sb;
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
        \\@build.stage({ name = "prepare", order = -10, desc = "prepare assets" })
        \\@build.command({ name = "assets", command = "echo assets", stage = "prepare" })
        \\@build.run({ name = "app", src = "main.id" })
        \\@build.test({ name = "test", src = "tests.id", out = "zig-out/bin/t" })
        \\@build.clean({ name = "clean" })
        \\
    ;
    var lex = @import("lexer.zig").Lexer.init(src, "build.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);

    var project = try loadFromSema(alloc, "build.id", &sem);
    defer project.deinit(alloc);

    try std.testing.expectEqualStrings("demo", project.name.?);
    try std.testing.expectEqualStrings("app", project.default_target.?);
    try std.testing.expect(project.stages.len == 1);
    try std.testing.expectEqualStrings("prepare", project.stages[0].name);
    try std.testing.expect(project.targets.len == 4);

    const app = try resolveTarget(&project, "app", null);
    try std.testing.expect(app.kind == .run);
    try std.testing.expectEqualStrings("main.id", app.src.?);

    const assets = try resolveTarget(&project, "assets", null);
    try std.testing.expect(assets.kind == .command);
    try std.testing.expectEqualStrings("echo assets", assets.command.?);
    try std.testing.expectEqualStrings("prepare", assets.stage_name.?);

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
        .build_source = "build.id",
        .name = null,
        .version = null,
        .default_target = null,
        .stages = try alloc.alloc(Stage, 0),
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

test "build_framework: implicit entrypoint target" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src = "main: i64 = ()\n    0\n";
    var lex = @import("lexer.zig").Lexer.init(src, "src/main.id");
    var parser = @import("parser.zig").Parser.init(&lex, alloc);
    parser.duo_mode = true;
    var mod = try parser.parse_module();
    var sem = Sema.init(alloc);
    defer sem.deinit();
    sem.duo_mode = true;
    try sem.check_module(&mod);

    var project = try loadFromSema(alloc, "src/main.id", &sem);
    defer project.deinit(alloc);
    try std.testing.expect(project.targets.len == 1);
    try std.testing.expect(project.targets[0].kind == .run);
    try std.testing.expectEqualStrings("app", project.targets[0].name);
    try std.testing.expectEqualStrings("src/main.id", project.targets[0].src.?);
}

test "build_framework: canonical entry precedes historical entry" {
    try std.testing.expectEqualStrings("build.id", build_source_candidates[0]);
    try std.testing.expectEqualStrings("src/build.id", build_source_candidates[1]);
    try std.testing.expectEqualStrings("build.duo", build_source_candidates[2]);
    try std.testing.expectEqualStrings("src/main.id", entrypoint_candidates[0]);
    try std.testing.expect(isEntrypointPath("src/main.id"));
    try std.testing.expect(isEntrypointPath("src/main.duo"));
}
