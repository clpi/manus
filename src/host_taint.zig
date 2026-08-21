//! Host-taint / authority-taint ledger for production outcomes.
//!
//! Answers, per lowered realization decision: was this outcome derived only from
//! authoritative graph facts, or did it consult host AST/name/path/table spellings
//! after facts exist? See `idol-native/docs/shc-host-taint.md` (native projection).

const std = @import("std");
const semantic_graph = @import("semantic_graph.zig");

/// When true (`DUO_TAINT_ZERO=1`), non-waived B-boundary compiles fail if any
/// HOST-TAINTED witness was recorded in the lowering ledger.
pub var enforce_enabled: bool = false;

pub const Class = enum {
    clean,
    host_tainted,
    bridge_tainted,

    pub fn name(self: Class) []const u8 {
        return @tagName(self);
    }
};

/// Which host influence channel was observed.
pub const Channel = enum {
    ast_name,
    ast_kind,
    method_string,
    module_alias,
    storage_path,
    opaque_path,
    host_table,
    opcode,
    bridge_translation,

    pub fn name(self: Channel) []const u8 {
        return @tagName(self);
    }
};

pub const Stage = enum {
    lexer,
    grammar,
    parser,
    sema,
    graph,
    demand,
    lower,
    codegen,
    link,

    pub fn name(self: Stage) []const u8 {
        return @tagName(self);
    }
};

pub const Event = struct {
    stage: Stage,
    class: Class,
    channel: Channel,
    /// Static site label (function or pattern name); not source text authority.
    site: []const u8,
    application: ?semantic_graph.id = null,
};

pub const Ledger = struct {
    events: std.ArrayListUnmanaged(Event) = .empty,
    /// Aggregate counts keyed by `stage.channel.class` for gate ratchets.
    counts: std.StringHashMapUnmanaged(u32) = .empty,

    pub fn deinit(self: *Ledger, alloc: std.mem.Allocator) void {
        self.events.deinit(alloc);
        var it = self.counts.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
        }
        self.counts.deinit(alloc);
    }

    pub fn reset(self: *Ledger, alloc: std.mem.Allocator) void {
        self.deinit(alloc);
        self.* = .{};
    }

    fn countKey(stage: Stage, channel: Channel, class: Class, buf: []u8) ?[]const u8 {
        return std.fmt.bufPrint(buf, "{s}.{s}.{s}", .{ stage.name(), channel.name(), class.name() }) catch null;
    }

    pub fn record(self: *Ledger, alloc: std.mem.Allocator, event: Event) !void {
        try self.events.append(alloc, event);
        var key_buf: [96]u8 = undefined;
        const key_tmp = countKey(event.stage, event.channel, event.class, &key_buf) orelse return;
        const owned_key = try alloc.dupe(u8, key_tmp);
        const gop = try self.counts.getOrPut(alloc, owned_key);
        if (gop.found_existing) {
            alloc.free(owned_key);
            gop.value_ptr.* +%= 1;
        } else {
            gop.key_ptr.* = owned_key;
            gop.value_ptr.* = 1;
        }
    }

    pub fn count(self: *const Ledger, stage: Stage, channel: Channel, class: Class) u32 {
        var total: u32 = 0;
        for (self.events.items) |ev| {
            if (ev.stage == stage and ev.channel == channel and ev.class == class) total +%= 1;
        }
        return total;
    }

    pub fn hostTaintTotal(self: *const Ledger) u32 {
        var total: u32 = 0;
        for (self.events.items) |ev| {
            if (ev.class == .host_tainted) total +%= 1;
        }
        return total;
    }

    pub fn mergedHostTaintTotal(lower: *const Ledger, codegen: ?*const Ledger) u32 {
        var total = lower.hostTaintTotal();
        if (codegen) |cg| total +%= cg.hostTaintTotal();
        return total;
    }

    pub fn writeLedgerLines(self: *const Ledger, w: *std.Io.Writer) !void {
        try w.print("TAINT host.total={d} events={d}\n", .{ self.hostTaintTotal(), self.events.items.len });
        var it = self.counts.iterator();
        while (it.next()) |entry| {
            try w.print("TAINT {s}={d}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }

    pub fn printLedgerLines(self: *const Ledger) void {
        std.debug.print("TAINT host.total={d} events={d}\n", .{ self.hostTaintTotal(), self.events.items.len });
        var it = self.counts.iterator();
        while (it.next()) |entry| {
            std.debug.print("TAINT {s}={d}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }

    fn jsonEscape(w: *std.Io.Writer, s: []const u8) !void {
        for (s) |c| switch (c) {
            '"', '\\' => try w.print("\\{c}", .{c}),
            else => try w.writeAll(&.{c}),
        };
    }

    pub fn writeJson(self: *const Ledger, w: *std.Io.Writer) !void {
        try w.print("{{\"host_total\":{d},\"events\":[", .{self.hostTaintTotal()});
        for (self.events.items, 0..) |ev, i| {
            if (i > 0) try w.print(",", .{});
            try w.print(
                "{{\"stage\":\"{s}\",\"class\":\"{s}\",\"channel\":\"{s}\",\"site\":\"",
                .{ ev.stage.name(), ev.class.name(), ev.channel.name() },
            );
            try jsonEscape(w, ev.site);
            try w.print("\"", .{});
            if (ev.application) |app| {
                try w.print(",\"application\":{d}", .{app});
            }
            try w.print("}}", .{});
        }
        try w.print("],\"counts\":{{", .{});
        var first = true;
        var it = self.counts.iterator();
        while (it.next()) |entry| {
            if (!first) try w.print(",", .{});
            first = false;
            try w.print("\"", .{});
            try jsonEscape(w, entry.key_ptr.*);
            try w.print("\":{d}", .{entry.value_ptr.*});
        }
        try w.print("}}}}", .{});
    }
};

test "host_taint: ledger aggregates host taint counts" {
    var ledger: Ledger = .{};
    defer ledger.deinit(std.testing.allocator);

    try ledger.record(std.testing.allocator, .{
        .stage = .lower,
        .class = .host_tainted,
        .channel = .opaque_path,
        .site = "opaque_path.load_field",
    });
    try ledger.record(std.testing.allocator, .{
        .stage = .lower,
        .class = .host_tainted,
        .channel = .opaque_path,
        .site = "opaque_path.load_field",
        .application = 42,
    });

    try std.testing.expectEqual(@as(u32, 2), ledger.count(.lower, .opaque_path, .host_tainted));
    try std.testing.expectEqual(@as(u32, 2), ledger.hostTaintTotal());
}

test "host_taint: merged totals include codegen ledger" {
    var lower: Ledger = .{};
    defer lower.deinit(std.testing.allocator);
    var codegen: Ledger = .{};
    defer codegen.deinit(std.testing.allocator);
    try lower.record(std.testing.allocator, .{
        .stage = .lower,
        .class = .host_tainted,
        .channel = .ast_name,
        .site = "world_symbol",
    });
    try codegen.record(std.testing.allocator, .{
        .stage = .codegen,
        .class = .host_tainted,
        .channel = .method_string,
        .site = "stream_method.arity",
    });
    try std.testing.expectEqual(@as(u32, 2), Ledger.mergedHostTaintTotal(&lower, &codegen));
}
