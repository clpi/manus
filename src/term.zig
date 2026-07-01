const std = @import("std");

pub var color: bool = false;

pub fn init() void {
    color = std.posix.isatty(std.posix.STDERR_FILENO);
}

fn wtr() std.fs.File.Writer {
    return std.io.getStdErr().writer();
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        nosuspend wtr().print("\x1b[31merror:\x1b[0m " ++ fmt ++ "\n", args) catch {};
    } else {
        nosuspend wtr().print("error: " ++ fmt ++ "\n", args) catch {};
    }
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        nosuspend wtr().print("\x1b[33mwarning:\x1b[0m " ++ fmt ++ "\n", args) catch {};
    } else {
        nosuspend wtr().print("warning: " ++ fmt ++ "\n", args) catch {};
    }
}

pub fn hint(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        nosuspend wtr().print("\x1b[36mhint:\x1b[0m " ++ fmt ++ "\n", args) catch {};
    } else {
        nosuspend wtr().print("hint: " ++ fmt ++ "\n", args) catch {};
    }
}

pub fn ok(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        nosuspend wtr().print("\x1b[32m" ++ fmt ++ "\x1b[0m\n", args) catch {};
    } else {
        nosuspend wtr().print(fmt ++ "\n", args) catch {};
    }
}

pub fn locErr(loc: anytype, comptime fmt: []const u8, args: anytype) void {
    if (color) {
        nosuspend wtr().print("\x1b[2m", .{}) catch {};
        nosuspend wtr().print("{}", .{loc}) catch {};
        nosuspend wtr().print("\x1b[0m \x1b[31merror:\x1b[0m ", .{}) catch {};
        nosuspend wtr().print(fmt, args) catch {};
        nosuspend wtr().print("\n", .{}) catch {};
    } else {
        nosuspend wtr().print("{}: error: " ++ fmt ++ "\n", .{loc} ++ args) catch {};
    }
}

pub fn locWarn(loc: anytype, comptime fmt: []const u8, args: anytype) void {
    if (color) {
        nosuspend wtr().print("\x1b[2m", .{}) catch {};
        nosuspend wtr().print("{}", .{loc}) catch {};
        nosuspend wtr().print("\x1b[0m \x1b[33mwarning:\x1b[0m ", .{}) catch {};
        nosuspend wtr().print(fmt, args) catch {};
        nosuspend wtr().print("\n", .{}) catch {};
    } else {
        nosuspend wtr().print("{}: warning: " ++ fmt ++ "\n", .{loc} ++ args) catch {};
    }
}

pub fn locHint(loc: anytype, comptime fmt: []const u8, args: anytype) void {
    if (color) {
        nosuspend wtr().print("\x1b[2m", .{}) catch {};
        nosuspend wtr().print("{}", .{loc}) catch {};
        nosuspend wtr().print("\x1b[0m \x1b[36mhint:\x1b[0m ", .{}) catch {};
        nosuspend wtr().print(fmt, args) catch {};
        nosuspend wtr().print("\n", .{}) catch {};
    } else {
        nosuspend wtr().print("{}: hint: " ++ fmt ++ "\n", .{loc} ++ args) catch {};
    }
}

pub fn locBare(loc: anytype, comptime fmt: []const u8, args: anytype) void {
    if (color) {
        nosuspend wtr().print("\x1b[2m", .{}) catch {};
        nosuspend wtr().print("{}", .{loc}) catch {};
        nosuspend wtr().print("\x1b[0m: ", .{}) catch {};
        nosuspend wtr().print(fmt, args) catch {};
        nosuspend wtr().print("\n", .{}) catch {};
    } else {
        nosuspend wtr().print("{}: " ++ fmt ++ "\n", .{loc} ++ args) catch {};
    }
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    nosuspend wtr().print(fmt ++ "\n", args) catch {};
}

pub fn printRaw(comptime fmt: []const u8, args: anytype) void {
    nosuspend wtr().print(fmt, args) catch {};
}
