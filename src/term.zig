const std = @import("std");
const Io = std.Io;
const File = Io.File;

var stderr_file: File = undefined;
var stderr_buf: [1024]u8 = undefined;
var wtr: File.Writer = undefined;
var initialized: bool = false;
pub var color: bool = false;

pub fn init(io: Io) void {
    stderr_file = File.stderr();
    color = File.isTty(stderr_file, io) catch false;
    wtr = File.Writer.initStreaming(stderr_file, io, &stderr_buf);
    initialized = true;
}

fn wprint(comptime fmt: []const u8, args: anytype) void {
    if (initialized) {
        nosuspend (&wtr.interface).print(fmt, args) catch {};
    } else {
        nosuspend std.debug.print(fmt, args);
    }
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        wprint("\x1b[31merror:\x1b[0m " ++ fmt ++ "\n", args);
    } else {
        wprint("error: " ++ fmt ++ "\n", args);
    }
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        wprint("\x1b[33mwarning:\x1b[0m " ++ fmt ++ "\n", args);
    } else {
        wprint("warning: " ++ fmt ++ "\n", args);
    }
}

pub fn hint(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        wprint("\x1b[36mhint:\x1b[0m " ++ fmt ++ "\n", args);
    } else {
        wprint("hint: " ++ fmt ++ "\n", args);
    }
}

pub fn ok(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        wprint("\x1b[32m" ++ fmt ++ "\x1b[0m\n", args);
    } else {
        wprint(fmt ++ "\n", args);
    }
}

pub fn locErr(loc: anytype, comptime fmt: []const u8, args: anytype) void {
    if (color) {
        wprint("\x1b[2m", .{});
        wprint("{}", .{loc});
        wprint("\x1b[0m \x1b[31merror:\x1b[0m ", .{});
        wprint(fmt, args);
        wprint("\n", .{});
    } else {
        wprint("{}: error: " ++ fmt ++ "\n", .{loc} ++ args);
    }
}

pub fn locWarn(loc: anytype, comptime fmt: []const u8, args: anytype) void {
    if (color) {
        wprint("\x1b[2m", .{});
        wprint("{}", .{loc});
        wprint("\x1b[0m \x1b[33mwarning:\x1b[0m ", .{});
        wprint(fmt, args);
        wprint("\n", .{});
    } else {
        wprint("{}: warning: " ++ fmt ++ "\n", .{loc} ++ args);
    }
}

pub fn locHint(loc: anytype, comptime fmt: []const u8, args: anytype) void {
    if (color) {
        wprint("\x1b[2m", .{});
        wprint("{}", .{loc});
        wprint("\x1b[0m \x1b[36mhint:\x1b[0m ", .{});
        wprint(fmt, args);
        wprint("\n", .{});
    } else {
        wprint("{}: hint: " ++ fmt ++ "\n", .{loc} ++ args);
    }
}

pub fn locBare(loc: anytype, comptime fmt: []const u8, args: anytype) void {
    if (color) {
        wprint("\x1b[2m", .{});
        wprint("{}", .{loc});
        wprint("\x1b[0m: ", .{});
        wprint(fmt, args);
        wprint("\n", .{});
    } else {
        wprint("{}: " ++ fmt ++ "\n", .{loc} ++ args);
    }
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    wprint(fmt ++ "\n", args);
}

pub fn printRaw(comptime fmt: []const u8, args: anytype) void {
    wprint(fmt, args);
}
