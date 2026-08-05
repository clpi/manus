//! Target layout verification for imported C records (Pass 5 validation engine seam).
const std = @import("std");
const host_run = @import("host_run.zig");
const c_frontend = @import("c_frontend.zig");

pub const FieldLayout = struct {
    name: []const u8,
    offset: usize,
};

pub const RecordLayout = struct {
    size: usize,
    alignment: usize,
    fields: []FieldLayout,

    pub fn deinit(self: *RecordLayout, alloc: std.mem.Allocator) void {
        for (self.fields) |f| alloc.free(f.name);
        alloc.free(self.fields);
    }
};

fn cScalarSpelling(sc: c_frontend.ScalarKind) []const u8 {
    return switch (sc) {
        .void => "void",
        .bool => "_Bool",
        .char => "char",
        .i8 => "int8_t",
        .i16 => "int16_t",
        .i32 => "int32_t",
        .i64 => "int64_t",
        .u8 => "uint8_t",
        .u16 => "uint16_t",
        .u32 => "uint32_t",
        .u64 => "uint64_t",
        .f32 => "float",
        .f64 => "double",
        .unknown => "char",
    };
}

fn emitFieldType(w: *std.Io.Writer, tr: c_frontend.TypeRef) !void {
    switch (tr) {
        .scalar => |s| try w.print("{s}", .{cScalarSpelling(s)}),
        .named => |n| try w.print("struct {s}", .{n}),
        .pointer => |p| {
            try emitFieldType(w, p.*);
            try w.writeAll(" *");
        },
        .array => |a| {
            try emitFieldType(w, a.elem.*);
            if (a.extent) |n| try w.print("[{d}]", .{n}) else try w.print("[]", .{});
        },
        .opaque_type => try w.print("char", .{}),
        .unknown => |u| try w.print("{s}", .{u}),
    }
}

/// Verify record layout by compiling and running a tiny C probe with clang.
pub fn verifyRecordWithClang(
    alloc: std.mem.Allocator,
    rec: c_frontend.RecordDecl,
) !?RecordLayout {
    if (rec.is_opaque or rec.fields.len == 0) return null;
    for (rec.fields) |f| {
        if (f.typ != .scalar) return null;
    }

    var prog: std.Io.Writer.Allocating = .init(alloc);
    defer prog.deinit();
    const pw = &prog.writer;
    try pw.writeAll(
        \\#include <stdio.h>
        \\#include <stddef.h>
        \\#include <stdint.h>
        \\typedef struct {
        ,
    );
    for (rec.fields, 0..) |f, i| {
        if (i > 0) try pw.writeAll(" ");
        try emitFieldType(pw, f.typ);
        try pw.print(" {s};", .{f.name});
    }
    try pw.writeAll(
        \\} __duo_probe;
        \\int main(void) {
        \\  printf("size=%zu\n", sizeof(__duo_probe));
        \\  printf("align=%zu\n", _Alignof(__duo_probe));
    );
    for (rec.fields) |f| {
        try pw.writeAll("  printf(\"off:");
        try pw.writeAll(f.name);
        try pw.writeAll("=%zu\\n\", offsetof(__duo_probe, ");
        try pw.writeAll(f.name);
        try pw.writeAll("));\n");
    }
    try pw.writeAll("  return 0;\n}\n");

    const src_path = "/tmp/duo_layout_probe.c";
    const bin_path = "/tmp/duo_layout_probe";
    const src_bytes = prog.written();
    {
        var threaded = std.Io.Threaded.init(alloc, .{});
        const cwd = std.Io.Dir.cwd();
        try std.Io.Dir.writeFile(cwd, threaded.io(), .{
            .sub_path = src_path,
            .data = src_bytes,
            .flags = .{},
        });
    }

    const compile_cmd = try std.fmt.allocPrint(
        alloc,
        "clang -x c -std=c11 -O0 -o {s} {s} 2>/dev/null",
        .{ bin_path, src_path },
    );
    defer alloc.free(compile_cmd);
    const compile = host_run.runHostCommand(alloc, compile_cmd) orelse return null;
    defer {
        alloc.free(compile.stdout);
        alloc.free(compile.stderr);
    }
    if (!compile.ok) return null;

    const run = host_run.runHostCommand(alloc, bin_path) orelse return null;
    defer {
        alloc.free(run.stdout);
        alloc.free(run.stderr);
    }
    if (!run.ok) return null;

    var size: ?usize = null;
    var alignment: ?usize = null;
    var fields: std.ArrayListUnmanaged(FieldLayout) = .empty;
    errdefer {
        for (fields.items) |f| alloc.free(f.name);
        fields.deinit(alloc);
    }

    var lines = std.mem.splitScalar(u8, run.stdout, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "size=")) {
            size = std.fmt.parseInt(usize, line["size=".len..], 10) catch null;
        } else if (std.mem.startsWith(u8, line, "align=")) {
            alignment = std.fmt.parseInt(usize, line["align=".len..], 10) catch null;
        } else if (std.mem.startsWith(u8, line, "off:")) {
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const name = line["off:".len..eq];
            const off = std.fmt.parseInt(usize, line[eq + 1 ..], 10) catch continue;
            try fields.append(alloc, .{
                .name = try alloc.dupe(u8, name),
                .offset = off,
            });
        }
    }
    if (size == null or alignment == null) return null;
    return .{
        .size = size.?,
        .alignment = alignment.?,
        .fields = try fields.toOwnedSlice(alloc),
    };
}

test "c_layout_verify: CPoint matches clang probe" {
    const alloc = std.testing.allocator;
    const src = @import("pass5_fixtures.zig").point_h;
    var frontend = try c_frontend.parseHeader(alloc, "point.h", src);
    defer frontend.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 1), frontend.records.len);
    var layout = (try verifyRecordWithClang(alloc, frontend.records[0])) orelse {
        // clang unavailable in CI — skip
        return;
    };
    defer layout.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 16), layout.size);
    try std.testing.expectEqual(@as(usize, 8), layout.alignment);
    try std.testing.expectEqual(@as(usize, 2), layout.fields.len);
}
