/// Generate fused C loops for `@pipeline` table descriptors.
const std = @import("std");
const directives = @import("directives.zig");

pub const Source = enum {
    array,
    range,
};

pub const Spec = struct {
    func_name: []const u8,
    elem_type: []const u8,
    kind: Kind,
    init: []const u8,
    data_name: []const u8 = "data",
    source: Source = .array,
    range_start: ?i64 = null,
    range_stop: ?i64 = null,
    map_fn: ?[]const u8 = null,
    filter_fn: ?[]const u8 = null,
    reduce_fn: ?[]const u8 = null,
    take: ?i64 = null,
    skip: ?i64 = null,
};

const Variant = struct {
    func_name: []const u8,
    elem_type: ?[]const u8 = null,
    init: ?[]const u8 = null,
};

const TypeAxis = struct {
    suffix: []const u8,
    elem_type: []const u8,
    init: ?[]const u8 = null,
};

const CountAxis = struct {
    suffix: []const u8,
    value: ?i64 = null,
};

const FunctionAxis = struct {
    suffix: []const u8,
    func_name: ?[]const u8 = null,
};

pub const Kind = enum {
    reduce,
    collect,
};

pub fn generateProductReduce(
    alloc: std.mem.Allocator,
    func_name: []const u8,
    types: []const u8,
    takes: []const u8,
    skips: []const u8,
    maps: []const u8,
    filters: []const u8,
    reducers: []const u8,
) ![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(alloc);
    errdefer aw.deinit();
    const w = &aw.writer;

    try w.writeAll("{ name = ");
    try writeQuotedAttr(w, func_name);
    try w.writeAll(", types = ");
    try writeQuotedAttr(w, types);
    try w.writeAll(", takes = ");
    try writeQuotedAttr(w, takes);
    try w.writeAll(", skips = ");
    try writeQuotedAttr(w, skips);
    try w.writeAll(", maps = ");
    try writeQuotedAttr(w, maps);
    try w.writeAll(", filters = ");
    try writeQuotedAttr(w, filters);
    try w.writeAll(", reducers = ");
    try writeQuotedAttr(w, reducers);
    try w.writeAll(", kind = \"reduce\" }");

    const table = try aw.toOwnedSlice();
    defer alloc.free(table);
    return generateFromTable(alloc, table);
}

fn writeQuotedAttr(w: *std.Io.Writer, value: []const u8) !void {
    try w.writeByte('"');
    for (value) |c| {
        switch (c) {
            '\\', '"' => {
                try w.writeByte('\\');
                try w.writeByte(c);
            },
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => try w.writeByte(c),
        }
    }
    try w.writeByte('"');
}

pub fn generateFromTable(alloc: std.mem.Allocator, raw: []const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0 or trimmed[0] != '{') return error.NotTableArgs;
    var map = try directives.parseAttrArgs(alloc, trimmed);
    defer map.deinit(alloc);

    if (map.get("types")) |raw_types| {
        return generateProductFamily(alloc, &map, raw_types);
    }

    if (map.get("variants")) |raw_variants| {
        return generateVariantFamily(alloc, &map, raw_variants);
    }

    const func_name = map.get("fn") orelse map.get("name") orelse return error.MissingPipelineFn;
    const spec = try specFromMap(&map, func_name);
    return generateFused(alloc, spec);
}

fn specFromMap(map: *const directives.ArgMap, func_name: []const u8) !Spec {
    const elem_type = map.get("elem") orelse "double";
    const kind_str = map.get("kind") orelse "reduce";
    const kind: Kind = if (std.mem.eql(u8, kind_str, "collect")) .collect else .reduce;
    const init = map.get("init") orelse "0";

    const source_str = map.get("source") orelse "array";
    const source: Source = if (std.mem.eql(u8, source_str, "range")) .range else .array;
    const range_start = parseOptionalI64(map.get("start"));
    const range_stop = parseOptionalI64(map.get("stop"));
    if (source == .range and (range_start == null or range_stop == null)) return error.MissingRangeBounds;

    return .{
        .func_name = func_name,
        .elem_type = elem_type,
        .kind = kind,
        .init = init,
        .source = source,
        .range_start = range_start,
        .range_stop = range_stop,
        .map_fn = map.get("map"),
        .filter_fn = map.get("filter"),
        .reduce_fn = map.get("reduce"),
        .take = parseOptionalI64(map.get("take")),
        .skip = parseOptionalI64(map.get("skip")),
    };
}

fn generateVariantFamily(alloc: std.mem.Allocator, map: *const directives.ArgMap, raw_variants: []const u8) ![]const u8 {
    const base_name = map.get("fn") orelse map.get("name") orelse "pipeline";
    const variants = try parseVariants(alloc, raw_variants);
    defer {
        for (variants) |v| alloc.free(v.func_name);
        alloc.free(variants);
    }

    var aw: std.Io.Writer.Allocating = .init(alloc);
    errdefer aw.deinit();
    const w = &aw.writer;
    try w.print("/* [pipeline.family] {s}: {d} variants */\n", .{ base_name, variants.len });

    for (variants) |variant| {
        var spec = try specFromMap(map, variant.func_name);
        if (variant.elem_type) |elem_type| spec.elem_type = elem_type;
        if (variant.init) |init| spec.init = init;

        const code = try generateFused(alloc, spec);
        defer alloc.free(code);
        try w.writeAll(code);
    }

    return aw.toOwnedSlice();
}

fn generateProductFamily(alloc: std.mem.Allocator, map: *const directives.ArgMap, raw_types: []const u8) ![]const u8 {
    const base_name = map.get("fn") orelse map.get("name") orelse "pipeline";
    const type_axis = try parseTypeAxis(alloc, raw_types);
    defer {
        for (type_axis) |axis| alloc.free(axis.suffix);
        alloc.free(type_axis);
    }
    const take_axis = try parseOptionalCountAxis(alloc, map.get("takes"));
    defer freeCountAxis(alloc, take_axis);
    const skip_axis = try parseOptionalCountAxis(alloc, map.get("skips"));
    defer freeCountAxis(alloc, skip_axis);
    const map_axis = try parseOptionalFunctionAxis(alloc, map.get("maps"));
    defer freeFunctionAxis(alloc, map_axis);
    const filter_axis = try parseOptionalFunctionAxis(alloc, map.get("filters"));
    defer freeFunctionAxis(alloc, filter_axis);
    const reduce_axis = try parseOptionalFunctionAxis(alloc, map.get("reducers"));
    defer freeFunctionAxis(alloc, reduce_axis);

    var aw: std.Io.Writer.Allocating = .init(alloc);
    errdefer aw.deinit();
    const w = &aw.writer;
    try w.print("/* [pipeline.product] {s}: {d} variants */\n", .{
        base_name,
        type_axis.len * take_axis.len * skip_axis.len * map_axis.len * filter_axis.len * reduce_axis.len,
    });

    for (type_axis) |ty| {
        for (take_axis) |take| {
            for (skip_axis) |skip| {
                for (map_axis) |map_fn| {
                    for (filter_axis) |filter_fn| {
                        for (reduce_axis) |reduce_fn| {
                            const func_name = try productFuncName(alloc, base_name, &.{
                                ty.suffix,
                                take.suffix,
                                skip.suffix,
                                map_fn.suffix,
                                filter_fn.suffix,
                                reduce_fn.suffix,
                            });
                            defer alloc.free(func_name);

                            var spec = try specFromMap(map, func_name);
                            spec.elem_type = ty.elem_type;
                            if (ty.init) |init| spec.init = init;
                            spec.take = take.value;
                            spec.skip = skip.value;
                            spec.map_fn = map_fn.func_name;
                            spec.filter_fn = filter_fn.func_name;
                            spec.reduce_fn = reduce_fn.func_name;

                            const code = try generateFused(alloc, spec);
                            defer alloc.free(code);
                            try w.writeAll(code);
                        }
                    }
                }
            }
        }
    }

    return aw.toOwnedSlice();
}

fn parseVariants(alloc: std.mem.Allocator, raw: []const u8) ![]const Variant {
    const entries = try splitTopLevel(alloc, raw, '|');
    defer alloc.free(entries);

    var out: std.ArrayListUnmanaged(Variant) = .empty;
    errdefer {
        for (out.items) |v| alloc.free(v.func_name);
        out.deinit(alloc);
    }

    for (entries) |entry_raw| {
        const entry = std.mem.trim(u8, entry_raw, " \t\r\n");
        if (entry.len == 0) continue;

        const first_colon = findTopLevelScalar(entry, ':');
        const name_end = first_colon orelse entry.len;
        const name = std.mem.trim(u8, entry[0..name_end], " \t\r\n");
        if (name.len == 0) continue;

        var elem_type: ?[]const u8 = null;
        var init: ?[]const u8 = null;
        if (first_colon) |first| {
            const tail = entry[first + 1 ..];
            if (findTopLevelScalar(tail, ':')) |second_rel| {
                const elem = std.mem.trim(u8, tail[0..second_rel], " \t\r\n");
                const init_raw = std.mem.trim(u8, tail[second_rel + 1 ..], " \t\r\n");
                if (elem.len > 0) elem_type = elem;
                if (init_raw.len > 0) init = init_raw;
            } else {
                const elem = std.mem.trim(u8, tail, " \t\r\n");
                if (elem.len > 0) elem_type = elem;
            }
        }

        try out.append(alloc, .{
            .func_name = try alloc.dupe(u8, name),
            .elem_type = elem_type,
            .init = init,
        });
    }

    if (out.items.len == 0) return error.MissingPipelineFn;
    return try out.toOwnedSlice(alloc);
}

fn parseTypeAxis(alloc: std.mem.Allocator, raw: []const u8) ![]const TypeAxis {
    const entries = try splitTopLevel(alloc, raw, '|');
    defer alloc.free(entries);

    var out: std.ArrayListUnmanaged(TypeAxis) = .empty;
    errdefer {
        for (out.items) |axis| alloc.free(axis.suffix);
        out.deinit(alloc);
    }

    for (entries) |entry_raw| {
        const entry = std.mem.trim(u8, entry_raw, " \t\r\n");
        if (entry.len == 0) continue;

        const first_colon = findTopLevelScalar(entry, ':') orelse continue;
        const suffix = std.mem.trim(u8, entry[0..first_colon], " \t\r\n");
        const tail = entry[first_colon + 1 ..];
        const second_colon = findTopLevelScalar(tail, ':');
        const elem = if (second_colon) |second|
            std.mem.trim(u8, tail[0..second], " \t\r\n")
        else
            std.mem.trim(u8, tail, " \t\r\n");
        const init = if (second_colon) |second| blk: {
            const raw_init = std.mem.trim(u8, tail[second + 1 ..], " \t\r\n");
            break :blk if (raw_init.len > 0) raw_init else null;
        } else null;
        if (suffix.len == 0 or elem.len == 0) continue;

        try out.append(alloc, .{
            .suffix = try alloc.dupe(u8, suffix),
            .elem_type = elem,
            .init = init,
        });
    }

    if (out.items.len == 0) return error.MissingPipelineFn;
    return try out.toOwnedSlice(alloc);
}

fn parseOptionalCountAxis(alloc: std.mem.Allocator, raw: ?[]const u8) ![]const CountAxis {
    const text = raw orelse {
        const out = try alloc.alloc(CountAxis, 1);
        out[0] = .{ .suffix = "", .value = null };
        return out;
    };
    const entries = try splitTopLevel(alloc, text, '|');
    defer alloc.free(entries);

    var out: std.ArrayListUnmanaged(CountAxis) = .empty;
    errdefer {
        for (out.items) |axis| alloc.free(axis.suffix);
        out.deinit(alloc);
    }

    for (entries) |entry_raw| {
        const entry = std.mem.trim(u8, entry_raw, " \t\r\n");
        if (entry.len == 0) continue;
        const colon = findTopLevelScalar(entry, ':');
        const suffix = if (colon) |pos| std.mem.trim(u8, entry[0..pos], " \t\r\n") else entry;
        const value_raw = if (colon) |pos| std.mem.trim(u8, entry[pos + 1 ..], " \t\r\n") else "";
        if (suffix.len == 0) continue;
        const value = if (value_raw.len == 0) null else std.fmt.parseInt(i64, value_raw, 10) catch null;
        try out.append(alloc, .{
            .suffix = try alloc.dupe(u8, suffix),
            .value = value,
        });
    }

    if (out.items.len == 0) {
        const fallback = try alloc.alloc(CountAxis, 1);
        fallback[0] = .{ .suffix = "", .value = null };
        return fallback;
    }
    return try out.toOwnedSlice(alloc);
}

fn freeCountAxis(alloc: std.mem.Allocator, axis: []const CountAxis) void {
    for (axis) |item| {
        if (item.suffix.len > 0) alloc.free(item.suffix);
    }
    alloc.free(axis);
}

fn parseOptionalFunctionAxis(alloc: std.mem.Allocator, raw: ?[]const u8) ![]const FunctionAxis {
    const text = raw orelse {
        const out = try alloc.alloc(FunctionAxis, 1);
        out[0] = .{ .suffix = "", .func_name = null };
        return out;
    };
    const entries = try splitTopLevel(alloc, text, '|');
    defer alloc.free(entries);

    var out: std.ArrayListUnmanaged(FunctionAxis) = .empty;
    errdefer {
        for (out.items) |axis| alloc.free(axis.suffix);
        out.deinit(alloc);
    }

    for (entries) |entry_raw| {
        const entry = std.mem.trim(u8, entry_raw, " \t\r\n");
        if (entry.len == 0) continue;
        const colon = findTopLevelScalar(entry, ':');
        const suffix = if (colon) |pos| std.mem.trim(u8, entry[0..pos], " \t\r\n") else entry;
        const func_raw = if (colon) |pos| std.mem.trim(u8, entry[pos + 1 ..], " \t\r\n") else entry;
        if (suffix.len == 0) continue;
        try out.append(alloc, .{
            .suffix = try alloc.dupe(u8, suffix),
            .func_name = if (func_raw.len == 0) null else func_raw,
        });
    }

    if (out.items.len == 0) {
        const fallback = try alloc.alloc(FunctionAxis, 1);
        fallback[0] = .{ .suffix = "", .func_name = null };
        return fallback;
    }
    return try out.toOwnedSlice(alloc);
}

fn freeFunctionAxis(alloc: std.mem.Allocator, axis: []const FunctionAxis) void {
    for (axis) |item| {
        if (item.suffix.len > 0) alloc.free(item.suffix);
    }
    alloc.free(axis);
}

fn productFuncName(alloc: std.mem.Allocator, base: []const u8, suffixes: []const []const u8) ![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(alloc);
    errdefer aw.deinit();
    const w = &aw.writer;
    try w.writeAll(base);
    for (suffixes) |suffix| {
        if (suffix.len > 0) try w.print("_{s}", .{suffix});
    }
    return aw.toOwnedSlice();
}

pub fn generateFused(alloc: std.mem.Allocator, spec: Spec) ![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(alloc);
    errdefer aw.deinit();
    const w = &aw.writer;

    try w.print("/* [pipeline.fused] {s} */\n", .{spec.func_name});
    try emitForwardDecls(w, spec);

    switch (spec.source) {
        .array => try emitArrayPipeline(w, spec),
        .range => try emitRangePipeline(w, spec),
    }

    return aw.toOwnedSlice();
}

fn emitArrayPipeline(w: *std.Io.Writer, spec: Spec) !void {
    switch (spec.kind) {
        .reduce => {
            const ret = spec.elem_type;
            try w.print("static {s} {s}(const {s}* {s}, size_t len) {{\n", .{ ret, spec.func_name, spec.elem_type, spec.data_name });
            try w.print("    {s} acc = {s};\n", .{ ret, spec.init });
            try w.print("    size_t _duo_i = 0;\n", .{});
            try w.print("    for (size_t i = 0; i < len; ++i) {{\n", .{});
            try w.print("        {s} elem = {s}[i];\n", .{ spec.elem_type, spec.data_name });
            try emitStageBody(w, spec);
            try w.print("    }}\n", .{});
            try w.print("    return acc;\n", .{});
            try w.print("}}\n", .{});
        },
        .collect => {
            try w.print("typedef struct {{ {s}* data; size_t len; size_t cap; }} {s}_result_t;\n", .{ spec.elem_type, spec.func_name });
            try w.print("static {s}_result_t {s}(const {s}* src, size_t src_len) {{\n", .{ spec.func_name, spec.func_name, spec.elem_type });
            try w.print("    {s} out_buf[src_len > 0 ? src_len : 1];\n", .{spec.elem_type});
            try w.print("    size_t out_len = 0;\n", .{});
            try w.print("    size_t _duo_i = 0;\n", .{});
            try w.print("    for (size_t i = 0; i < src_len; ++i) {{\n", .{});
            try w.print("        {s} elem = src[i];\n", .{spec.elem_type});
            if (spec.skip) |n| try w.print("        if (i < {d}) continue;\n", .{n});
            if (spec.take) |n| try w.print("        if (_duo_i >= {d}) break;\n", .{n});
            if (spec.filter_fn) |f| try w.print("        if (!{s}(elem)) continue;\n", .{f});
            if (spec.map_fn) |f| try w.print("        elem = {s}(elem);\n", .{f});
            try w.print("        out_buf[out_len++] = elem;\n", .{});
            try w.print("        _duo_i++;\n", .{});
            try w.print("    }}\n", .{});
            try w.print("    {s}_result_t r = {{ out_buf, out_len, src_len }};\n", .{spec.func_name});
            try w.print("    return r;\n", .{});
            try w.print("}}\n", .{});
        },
    }
}

fn emitRangePipeline(w: *std.Io.Writer, spec: Spec) !void {
    const start = spec.range_start.?;
    const stop = spec.range_stop.?;
    switch (spec.kind) {
        .reduce => {
            const ret = spec.elem_type;
            try w.print("static {s} {s}(void) {{\n", .{ ret, spec.func_name });
            try w.print("    {s} acc = {s};\n", .{ ret, spec.init });
            try w.print("    size_t _duo_i = 0;\n", .{});
            try w.print("    for ({s} elem = {d}; elem < {d}; ++elem) {{\n", .{ spec.elem_type, start, stop });
            try emitStageBody(w, spec);
            try w.print("    }}\n", .{});
            try w.print("    return acc;\n", .{});
            try w.print("}}\n", .{});
        },
        .collect => return error.RangeCollectUnsupported,
    }
}

fn emitStageBody(w: *std.Io.Writer, spec: Spec) !void {
    if (spec.skip) |n| try w.print("        if (_duo_i < {d}) {{ _duo_i++; continue; }}\n", .{n});
    if (spec.take) |n| try w.print("        if (_duo_i >= {d}) break;\n", .{n});
    if (spec.map_fn != null or spec.source == .range) {
        try w.print("        {s} _duo_v = elem;\n", .{spec.elem_type});
        if (spec.filter_fn) |f| try w.print("        if (!{s}(_duo_v)) {{ _duo_i++; continue; }}\n", .{f});
        if (spec.map_fn) |f| try w.print("        _duo_v = {s}(_duo_v);\n", .{f});
        if (spec.reduce_fn) |f| {
            try w.print("        acc = {s}(acc, _duo_v);\n", .{f});
        } else {
            try w.print("        acc += _duo_v;\n", .{});
        }
    } else {
        if (spec.filter_fn) |f| try w.print("        if (!{s}(elem)) {{ _duo_i++; continue; }}\n", .{f});
        if (spec.reduce_fn) |f| {
            try w.print("        acc = {s}(acc, elem);\n", .{f});
        } else {
            try w.print("        acc += elem;\n", .{});
        }
    }
    try w.print("        _duo_i++;\n", .{});
}

fn emitForwardDecls(w: *std.Io.Writer, spec: Spec) !void {
    if (spec.filter_fn) |f| {
        try w.print("static int {s}({s});\n", .{ f, spec.elem_type });
    }
    if (spec.map_fn) |f| {
        try w.print("static {s} {s}({s});\n", .{ spec.elem_type, f, spec.elem_type });
    }
    if (spec.reduce_fn) |f| {
        try w.print("static {s} {s}({s}, {s});\n", .{ spec.elem_type, f, spec.elem_type, spec.elem_type });
    }
}

fn parseOptionalI64(raw: ?[]const u8) ?i64 {
    const text = raw orelse return null;
    return std.fmt.parseInt(i64, std.mem.trim(u8, text, " \t\r\n"), 10) catch null;
}

fn splitTopLevel(alloc: std.mem.Allocator, raw: []const u8, delim: u8) ![]const []const u8 {
    var parts: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer parts.deinit(alloc);

    var start: usize = 0;
    var depth: usize = 0;
    var quote: ?u8 = null;
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        const c = raw[i];
        if (quote) |q| {
            if (c == '\\' and i + 1 < raw.len) {
                i += 1;
                continue;
            }
            if (c == q) quote = null;
            continue;
        }

        switch (c) {
            '"', '\'' => quote = c,
            '(', '[', '{' => depth += 1,
            ')', ']', '}' => {
                if (depth > 0) depth -= 1;
            },
            else => {
                if (c == delim and depth == 0) {
                    try parts.append(alloc, raw[start..i]);
                    start = i + 1;
                }
            },
        }
    }
    try parts.append(alloc, raw[start..]);
    return try parts.toOwnedSlice(alloc);
}

fn findTopLevelScalar(raw: []const u8, needle: u8) ?usize {
    var depth: usize = 0;
    var quote: ?u8 = null;
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        const c = raw[i];
        if (quote) |q| {
            if (c == '\\' and i + 1 < raw.len) {
                i += 1;
                continue;
            }
            if (c == q) quote = null;
            continue;
        }

        switch (c) {
            '"', '\'' => quote = c,
            '(', '[', '{' => depth += 1,
            ')', ']', '}' => {
                if (depth > 0) depth -= 1;
            },
            else => {
                if (c == needle and depth == 0) return i;
            },
        }
    }
    return null;
}

test "pipeline_gen: reduce pipeline" {
    const alloc = std.testing.allocator;
    const code = try generateFromTable(alloc,
        \\{ name = "sum_pos", elem = "int64_t", kind = "reduce", init = "0", filter = "is_pos", map = "double_it", reduce = "acc_add" }
    );
    defer alloc.free(code);
    try std.testing.expect(std.mem.indexOf(u8, code, "[pipeline.fused] sum_pos") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "static int is_pos(int64_t);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "static int64_t double_it(int64_t);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "static int64_t acc_add(int64_t, int64_t);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "if (!is_pos(_duo_v))") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "_duo_v = double_it(_duo_v);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "acc = acc_add(acc, _duo_v);") != null);
}

test "pipeline_gen: range reduce pipeline" {
    const alloc = std.testing.allocator;
    const code = try generateFromTable(alloc,
        \\{ fn = "sum_sq", source = "range", start = 1, stop = 6, elem = "int64_t", kind = "reduce", init = "0", map = "square", reduce = "acc_add" }
    );
    defer alloc.free(code);
    try std.testing.expect(std.mem.indexOf(u8, code, "for (int64_t elem = 1; elem < 6; ++elem)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "static int64_t sum_sq(void)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "elem = square(elem);") == null);
    try std.testing.expect(std.mem.indexOf(u8, code, "_duo_v = square(_duo_v);") != null);
}

test "pipeline_gen: range requires bounds" {
    const alloc = std.testing.allocator;
    try std.testing.expectError(error.MissingRangeBounds, generateFromTable(alloc,
        \\{ fn = "bad", source = "range", elem = "int64_t", kind = "reduce" }
    ));
}

test "pipeline_gen: variants generate fused family" {
    const alloc = std.testing.allocator;
    const code = try generateFromTable(alloc,
        \\{ name = "sum_family", variants = "sum_i64:int64_t:0 | sum_f64:double:0.0", kind = "reduce" }
    );
    defer alloc.free(code);
    try std.testing.expect(std.mem.indexOf(u8, code, "[pipeline.family] sum_family: 2 variants") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "static int64_t sum_i64(const int64_t* data, size_t len)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "int64_t acc = 0;") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "static double sum_f64(const double* data, size_t len)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "double acc = 0.0;") != null);
}

test "pipeline_gen: variant init keeps later top-level colons" {
    const alloc = std.testing.allocator;
    const code = try generateFromTable(alloc,
        \\{ variants = "pick:int64_t:(1 ? 2 : 3)", kind = "reduce" }
    );
    defer alloc.free(code);
    try std.testing.expect(std.mem.indexOf(u8, code, "int64_t acc = (1 ? 2 : 3);") != null);
}

test "pipeline_gen: product family crosses types and takes" {
    const alloc = std.testing.allocator;
    const code = try generateFromTable(alloc,
        \\{ name = "sum", types = "i64:int64_t:0 | f64:double:0.0", takes = "all: | first2:2", kind = "reduce" }
    );
    defer alloc.free(code);
    try std.testing.expect(std.mem.indexOf(u8, code, "[pipeline.product] sum: 4 variants") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "static int64_t sum_i64_all(const int64_t* data, size_t len)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "static int64_t sum_i64_first2(const int64_t* data, size_t len)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "static double sum_f64_all(const double* data, size_t len)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "static double sum_f64_first2(const double* data, size_t len)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "if (_duo_i >= 2) break;") != null);
}

test "pipeline_gen: product family crosses types takes and skips" {
    const alloc = std.testing.allocator;
    const code = try generateFromTable(alloc,
        \\{ name = "scan", types = "i64:int64_t:0 | u64:uint64_t:0", takes = "all: | first3:3", skips = "from0: | from2:2", kind = "reduce" }
    );
    defer alloc.free(code);
    try std.testing.expect(std.mem.indexOf(u8, code, "[pipeline.product] scan: 8 variants") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "scan_i64_first3_from2") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "scan_u64_all_from0") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "if (_duo_i < 2)") != null);
}

test "pipeline_gen: product family crosses operation policies" {
    const alloc = std.testing.allocator;
    const code = try generateFromTable(alloc,
        \\{ name = "fold", types = "i64:int64_t:0", maps = "id: | dbl:double_it", filters = "all: | pos:is_pos", reducers = "sum: | max:max_i64", kind = "reduce" }
    );
    defer alloc.free(code);
    try std.testing.expect(std.mem.indexOf(u8, code, "[pipeline.product] fold: 8 variants") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "static int64_t fold_i64_id_all_sum(const int64_t* data, size_t len)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "static int64_t fold_i64_dbl_pos_max(const int64_t* data, size_t len)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "static int64_t double_it(int64_t);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "static int is_pos(int64_t);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "static int64_t max_i64(int64_t, int64_t);") != null);
}

test "pipeline_gen: product reduce helper builds descriptor safely" {
    const alloc = std.testing.allocator;
    const code = try generateProductReduce(
        alloc,
        "fold",
        "i64:int64_t:0",
        "all: | first2:2",
        "",
        "id: | dbl:double_it",
        "all: | pos:is_pos",
        "sum: | max:max_i64",
    );
    defer alloc.free(code);
    try std.testing.expect(std.mem.indexOf(u8, code, "[pipeline.product] fold: 16 variants") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "fold_i64_first2_dbl_pos_max") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "lua_Value") == null);
}
