const std = @import("std");
const Io = std.Io;
const File = Io.File;

var stderr_file: File = undefined;
var stderr_buf: [1024]u8 = undefined;
var wtr: File.Writer = undefined;
var initialized: bool = false;
pub var color: bool = false;

const SourceView = struct {
    path: []const u8,
    bytes: []const u8,
};

var active_source: ?SourceView = null;

pub fn init(io: Io) void {
    stderr_file = File.stderr();
    color = File.isTty(stderr_file, io) catch false;
    wtr = File.Writer.initStreaming(stderr_file, io, &stderr_buf);
    initialized = true;
}

pub fn setSource(path: []const u8, bytes: []const u8) void {
    active_source = .{ .path = path, .bytes = bytes };
}

pub fn clearSource() void {
    active_source = null;
}

fn wprint(comptime fmt: []const u8, args: anytype) void {
    if (initialized) {
        nosuspend (&wtr.interface).print(fmt, args) catch {};
        nosuspend wtr.flush() catch {};
    } else {
        nosuspend std.debug.print(fmt, args);
    }
}

fn printLoc(loc: anytype) void {
    wprint("{s}:{}:{}", .{ loc.file, loc.line, loc.col });
}

fn repeatByte(byte: u8, count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        wprint("{c}", .{byte});
    }
}

fn decimalDigits(n: u32) usize {
    var value = n;
    var digits: usize = 1;
    while (value >= 10) : (digits += 1) value /= 10;
    return digits;
}

fn lineBounds(src: []const u8, wanted: u32) ?struct { start: usize, end: usize } {
    var line: u32 = 1;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= src.len) : (i += 1) {
        if (i == src.len or src[i] == '\n') {
            if (line == wanted) {
                var end = i;
                if (end > start and src[end - 1] == '\r') end -= 1;
                return .{ .start = start, .end = end };
            }
            line += 1;
            start = i + 1;
        }
    }
    return null;
}

fn sourceFor(file: []const u8) ?SourceView {
    const src = active_source orelse return null;
    if (std.mem.eql(u8, src.path, file)) return src;
    if (std.mem.eql(u8, std.fs.path.basename(src.path), std.fs.path.basename(file))) return src;
    return null;
}

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentContinue(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn isKeyword(word: []const u8) bool {
    inline for (.{
        "and",      "break", "catch",  "concept", "const",  "defer",
        "do",       "else",  "elseif", "end",     "enum",   "extends",
        "for",      "fun",   "function", "global", "goto",  "if",
        "in",       "local", "match",  "not",     "or",     "private",
        "repeat",   "return", "then",  "try",     "until",  "while",
        "async",    "await", "alias",
    }) |kw| {
        if (std.mem.eql(u8, word, kw)) return true;
    }
    return false;
}

fn isTypeWord(word: []const u8) bool {
    inline for (.{
        "bool", "f32", "f64", "f128", "float", "i8", "i16", "i32", "i64",
        "int", "num", "str", "string", "u8", "u16", "u32", "u64", "uint", "void",
    }) |kw| {
        if (std.mem.eql(u8, word, kw)) return true;
    }
    return false;
}

fn isLiteralWord(word: []const u8) bool {
    return std.mem.eql(u8, word, "true") or
        std.mem.eql(u8, word, "false") or
        std.mem.eql(u8, word, "nil");
}

fn isOperatorChar(c: u8) bool {
    return switch (c) {
        '+', '-', '*', '/', '%', '^', '#', '&', '|', '<', '>', '=', '~', ':', '.', '?', '!' => true,
        else => false,
    };
}

fn printPathStyled(path: []const u8) void {
    if (!color) {
        wprint("{s}", .{path});
        return;
    }
    const base = std.fs.path.basename(path);
    const prefix_len = path.len - base.len;
    if (prefix_len > 0) {
        wprint("\x1b[2m{s}\x1b[0m", .{path[0..prefix_len]});
    }
    wprint("\x1b[1m{s}\x1b[0m", .{base});
}

fn printLineCol(line: u32, col: u32) void {
    if (color) {
        wprint("\x1b[36m{}\x1b[0m:\x1b[35m{}\x1b[0m", .{ line, col });
    } else {
        wprint("{}:{}", .{ line, col });
    }
}

fn printStyledLoc(loc: anytype) void {
    printPathStyled(loc.file);
    wprint(":", .{});
    printLineCol(loc.line, loc.col);
}

fn printHighlightedLine(line: []const u8) void {
    if (!color) {
        wprint("{s}", .{line});
        return;
    }

    var i: usize = 0;
    while (i < line.len) {
        const c = line[i];
        if (c == '-' and i + 1 < line.len and line[i + 1] == '-') {
            wprint("\x1b[2;32m{s}\x1b[0m", .{line[i..]});
            return;
        }
        if (c == '"' or c == '\'') {
            const quote = c;
            const start = i;
            i += 1;
            while (i < line.len) : (i += 1) {
                if (line[i] == '\\' and i + 1 < line.len) {
                    i += 1;
                    continue;
                }
                if (line[i] == quote) {
                    i += 1;
                    break;
                }
            }
            wprint("\x1b[32m{s}\x1b[0m", .{line[start..i]});
            continue;
        }
        if (std.ascii.isDigit(c)) {
            const start = i;
            i += 1;
            while (i < line.len and (std.ascii.isAlphanumeric(line[i]) or line[i] == '.' or line[i] == '_')) : (i += 1) {}
            wprint("\x1b[35m{s}\x1b[0m", .{line[start..i]});
            continue;
        }
        if (isIdentStart(c)) {
            const start = i;
            i += 1;
            while (i < line.len and isIdentContinue(line[i])) : (i += 1) {}
            const word = line[start..i];
            if (isKeyword(word)) {
                wprint("\x1b[1;34m{s}\x1b[0m", .{word});
            } else if (isTypeWord(word)) {
                wprint("\x1b[36m{s}\x1b[0m", .{word});
            } else if (isLiteralWord(word)) {
                wprint("\x1b[1;35m{s}\x1b[0m", .{word});
            } else {
                wprint("{s}", .{word});
            }
            continue;
        }
        if (isOperatorChar(c)) {
            wprint("\x1b[33m{c}\x1b[0m", .{c});
            i += 1;
            continue;
        }
        wprint("{c}", .{c});
        i += 1;
    }
}

fn printBar(width: usize) void {
    repeatByte(' ', width);
    if (color) {
        wprint(" \x1b[2m│\x1b[0m\n", .{});
    } else {
        wprint(" |\n", .{});
    }
}

fn printSourceLine(line_no: u32, line: []const u8, width: usize) void {
    const digits = decimalDigits(line_no);
    repeatByte(' ', width - digits);
    if (color) {
        wprint("\x1b[36m{}\x1b[0m \x1b[2m│\x1b[0m ", .{line_no});
        printHighlightedLine(line);
        wprint("\n", .{});
    } else {
        wprint("{} | {s}\n", .{ line_no, line });
    }
}

fn printCaret(col: u32, line: []const u8, width: usize, severity_color: []const u8) void {
    repeatByte(' ', width);
    if (color) {
        wprint(" \x1b[2m│\x1b[0m ", .{});
    } else {
        wprint(" | ", .{});
    }
    const zero_col: usize = if (col > 0) col - 1 else 0;
    var i: usize = 0;
    while (i < zero_col and i < line.len) : (i += 1) {
        if (line[i] == '\t') {
            wprint("\t", .{});
        } else {
            wprint(" ", .{});
        }
    }
    if (color) {
        wprint("{s}╰─ here\x1b[0m\n", .{severity_color});
    } else {
        wprint("^\n", .{});
    }
}

fn printSourceContext(loc: anytype, severity_color: []const u8) void {
    const src = sourceFor(loc.file) orelse return;
    const width = @max(decimalDigits(loc.line), @as(usize, 1));

    if (color) {
        wprint("  \x1b[2m╭─[\x1b[0m", .{});
        printStyledLoc(loc);
        wprint("\x1b[2m]\x1b[0m\n", .{});
    } else {
        wprint("  --> {s}:{}:{}\n", .{ loc.file, loc.line, loc.col });
    }
    printBar(width);

    if (loc.line > 1) {
        if (lineBounds(src.bytes, loc.line - 1)) |prev| {
            printSourceLine(loc.line - 1, src.bytes[prev.start..prev.end], width);
        }
    }
    if (lineBounds(src.bytes, loc.line)) |current| {
        const line = src.bytes[current.start..current.end];
        printSourceLine(loc.line, line, width);
        printCaret(loc.col, line, width, severity_color);
    }
    if (lineBounds(src.bytes, loc.line + 1)) |next| {
        printSourceLine(loc.line + 1, src.bytes[next.start..next.end], width);
    }
    printBar(width);
}

fn printDiagnosticNote(comptime label: []const u8, body: []const u8, is_last: bool) void {
    if (color) {
        const branch = if (is_last) "╰─" else "├─";
        const label_color = if (std.mem.eql(u8, label, "help")) "\x1b[1;36m" else "\x1b[1;37m";
        wprint("  \x1b[2m{s}\x1b[0m {s}{s}\x1b[0m \x1b[2m→\x1b[0m {s}\n", .{
            branch,
            label_color,
            label,
            body,
        });
    } else {
        wprint("  = {s}: {s}\n", .{ label, body });
    }
}

fn printDiagnosticHelp(comptime label: []const u8) void {
    if (std.mem.eql(u8, label, "error")) {
        printDiagnosticNote("detail", "the marked source construct is the one Duo rejected", false);
        printDiagnosticNote("help", "fix this diagnostic first; later messages may be caused by this one", true);
    } else if (std.mem.eql(u8, label, "warning")) {
        printDiagnosticNote("detail", "Duo accepted the code, but this construct may be fragile or deprecated", false);
        printDiagnosticNote("help", "consider updating this location before relying on it long-term", true);
    } else if (std.mem.eql(u8, label, "hint")) {
        printDiagnosticNote("detail", "this note points at source that helps explain the preceding diagnostic", true);
    }
}

fn printLocDiagnostic(loc: anytype, comptime label: []const u8, color_code: []const u8, comptime fmt: []const u8, args: anytype) void {
    if (color) {
        wprint("{s}● {s}\x1b[0m\x1b[1m at \x1b[0m", .{ color_code, label });
        printStyledLoc(loc);
        wprint("\n  \x1b[1mmessage\x1b[0m \x1b[2m→\x1b[0m ", .{});
        wprint(fmt, args);
        wprint("\n", .{});
    } else {
        wprint("{s}:{}:{}: {s}: ", .{ loc.file, loc.line, loc.col, label });
        wprint(fmt, args);
        wprint("\n", .{});
    }
    printSourceContext(loc, color_code);
    printDiagnosticHelp(label);
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
    printLocDiagnostic(loc, "error", "\x1b[31m", fmt, args);
}

pub fn locWarn(loc: anytype, comptime fmt: []const u8, args: anytype) void {
    printLocDiagnostic(loc, "warning", "\x1b[33m", fmt, args);
}

pub fn locHint(loc: anytype, comptime fmt: []const u8, args: anytype) void {
    printLocDiagnostic(loc, "hint", "\x1b[36m", fmt, args);
}

pub fn locBare(loc: anytype, comptime fmt: []const u8, args: anytype) void {
    if (color) {
        wprint("\x1b[2m", .{});
        printLoc(loc);
        wprint("\x1b[0m: ", .{});
        wprint(fmt, args);
        wprint("\n", .{});
    } else {
        printLoc(loc);
        wprint(": " ++ fmt ++ "\n", args);
    }
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    wprint(fmt ++ "\n", args);
}

pub fn printRaw(comptime fmt: []const u8, args: anytype) void {
    wprint(fmt, args);
}
