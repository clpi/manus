const std = @import("std");
const Io = std.Io;
const File = Io.File;

var stderr_file: File = undefined;
var stderr_buf: [1024]u8 = undefined;
var wtr: File.Writer = undefined;
var initialized: bool = false;
pub var color: bool = false;
/// When true, diagnostics use `file:line:col: severity: message` (for LSP/CI).
pub var plain: bool = false;
/// When true, emit pipeline step traces during compilation.
pub var trace: bool = false;
/// When true, emit informational compiler notes (opt-in).
pub var info: bool = false;
/// When true, emit compiler hints (opt-in).
pub var hints: bool = false;

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
        "and",    "break",  "catch",    "concept", "const", "defer",
        "do",     "else",   "elseif",   "end",     "enum",  "extends",
        "for",    "fun",    "function", "global",  "goto",  "if",
        "in",     "local",  "match",    "not",     "or",    "private",
        "repeat", "return", "then",     "try",     "until", "while",
        "async",  "await",  "alias",
    }) |kw| {
        if (std.mem.eql(u8, word, kw)) return true;
    }
    return false;
}

fn isTypeWord(word: []const u8) bool {
    inline for (.{
        "bool", "f32", "f64", "f128",   "float", "i8",  "i16", "i32", "i64",
        "int",  "num", "str", "string", "u8",    "u16", "u32", "u64", "uint",
        "void",
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
        wprint("\x1b[2;4m{s}\x1b[0m", .{path[0..prefix_len]});
    }
    wprint("\x1b[1;4m{s}\x1b[0m", .{base});
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
        const label_color = if (std.mem.eql(u8, label, "help")) "\x1b[1;36m" else if (std.mem.eql(u8, label, "detail")) "\x1b[1;34m" else "\x1b[1;37m";
        const glyph: []const u8 = if (std.mem.eql(u8, label, "help")) "💡" else if (std.mem.eql(u8, label, "detail")) "ℹ" else "·";
        wprint("  \x1b[2m{s}\x1b[0m {s}{s} {s}\x1b[0m \x1b[2m→\x1b[0m \x1b[3m{s}\x1b[0m\n", .{
            branch,
            label_color,
            glyph,
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
    } else if (std.mem.eql(u8, label, "info")) {
        printDiagnosticNote("detail", "informational note from the compiler (enable with --info or DUO_INFO=1)", true);
    }
}

fn printLocDiagnostic(loc: anytype, comptime label: []const u8, color_code: []const u8, comptime fmt: []const u8, args: anytype) void {
    if (plain) {
        wprint("{s}:{}:{}: {s}: ", .{ loc.file, loc.line, loc.col, label });
        wprint(fmt, args);
        wprint("\n", .{});
        return;
    }
    if (color) {
        const sym = if (std.mem.eql(u8, label, "error")) "✗" else if (std.mem.eql(u8, label, "warning")) "⚠" else if (std.mem.eql(u8, label, "hint")) "💡" else "ℹ";
        wprint("{s}{s} {s}\x1b[0m\x1b[1m at \x1b[0m", .{ color_code, sym, label });
        printStyledLoc(loc);
        wprint("\n  \x1b[1mmessage\x1b[0m \x1b[2m→\x1b[0m \x1b[3m", .{});
        wprint(fmt, args);
        wprint("\x1b[0m\n", .{});
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
        wprint("\x1b[1;31m✗ error:\x1b[0m \x1b[3m" ++ fmt ++ "\x1b[0m\n", args);
    } else {
        wprint("error: " ++ fmt ++ "\n", args);
    }
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        wprint("\x1b[1;33m⚠ warning:\x1b[0m \x1b[3m" ++ fmt ++ "\x1b[0m\n", args);
    } else {
        wprint("warning: " ++ fmt ++ "\n", args);
    }
}

pub fn hint(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        wprint("\x1b[1;36m💡 hint:\x1b[0m \x1b[3m" ++ fmt ++ "\x1b[0m\n", args);
    } else {
        wprint("hint: " ++ fmt ++ "\n", args);
    }
}

pub fn ok(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        wprint("\x1b[1;32m✓ " ++ fmt ++ "\x1b[0m\n", args);
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

pub fn dim(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        wprint("\x1b[2m" ++ fmt ++ "\x1b[0m\n", args);
    } else {
        wprint(fmt ++ "\n", args);
    }
}

pub fn bold(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        wprint("\x1b[1m" ++ fmt ++ "\x1b[0m\n", args);
    } else {
        wprint(fmt ++ "\n", args);
    }
}

pub fn italic(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        wprint("\x1b[3m" ++ fmt ++ "\x1b[0m\n", args);
    } else {
        wprint(fmt ++ "\n", args);
    }
}

pub fn underline(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        wprint("\x1b[4m" ++ fmt ++ "\x1b[0m\n", args);
    } else {
        wprint(fmt ++ "\n", args);
    }
}

pub fn blink(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        wprint("\x1b[5m" ++ fmt ++ "\x1b[0m\n", args);
    } else {
        wprint(fmt ++ "\n", args);
    }
}

pub fn banner(title: []const u8) void {
    if (color) {
        wprint("\x1b[1;36m╭─ {s}\x1b[0m \x1b[2m┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\x1b[0m\n", .{title});
    } else {
        wprint("== {s} ==\n", .{title});
    }
}

pub fn section(title: []const u8) void {
    if (color) {
        wprint("\x1b[1;4m{s}\x1b[0m\n", .{title});
    } else {
        wprint("{s}\n", .{title});
    }
}

pub fn kv(key: []const u8, value: []const u8) void {
    if (color) {
        wprint("  \x1b[2m{s}\x1b[0m \x1b[2m·\x1b[0m \x1b[36m{s}\x1b[0m\n", .{ key, value });
    } else {
        wprint("  {s} : {s}\n", .{ key, value });
    }
}

pub fn divider() void {
    if (color) {
        wprint("\x1b[2m┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈\x1b[0m\n", .{});
    } else {
        wprint("----------------------------------------\n", .{});
    }
}

pub fn infoMsg(comptime fmt: []const u8, args: anytype) void {
    if (!info) return;
    if (color) {
        wprint("\x1b[1;34mℹ info\x1b[0m \x1b[2m→\x1b[0m \x1b[3m" ++ fmt ++ "\x1b[0m\n", args);
    } else {
        wprint("info: " ++ fmt ++ "\n", args);
    }
}

pub fn locInfo(loc: anytype, comptime fmt: []const u8, args: anytype) void {
    if (!info) return;
    printLocDiagnostic(loc, "info", "\x1b[34m", fmt, args);
}

pub fn traceStep(comptime fmt: []const u8, args: anytype) void {
    if (!trace) return;
    if (richPipeline()) {
        var buf: [128]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, fmt, args) catch fmt;
        pipelinePhaseActive(label);
        return;
    }
    if (color) {
        wprint("\x1b[2;36m⟳\x1b[0m \x1b[3;36m", .{});
        wprint(fmt, args);
        wprint("\x1b[0m \x1b[2m…\x1b[0m\n", .{});
    } else {
        wprint("⟳ " ++ fmt ++ " …\n", args);
    }
}

pub fn traceDone(label: []const u8, elapsed_ms: u64, detail: ?[]const u8) void {
    if (!trace) return;
    if (richPipeline()) {
        pipelinePhaseComplete(label, elapsed_ms, detail);
        return;
    }
    // Color the elapsed time by intensity (green fast → yellow slow) — semantic signal.
    const ms_color = if (!color) "" else if (elapsed_ms < 50) "\x1b[32m" else if (elapsed_ms < 500) "\x1b[33m" else "\x1b[31m";
    if (detail) |d| {
        if (color) {
            wprint("\x1b[1;32m✓\x1b[0m \x1b[1m{s}\x1b[0m \x1b[2m(\x1b[0m{s}{d} ms\x1b[0m\x1b[2m — \x1b[3m{s}\x1b[0m\x1b[2m)\x1b[0m\n", .{ label, ms_color, elapsed_ms, d });
        } else {
            wprint("✓ {s} ({d} ms — {s})\n", .{ label, elapsed_ms, d });
        }
    } else if (color) {
        wprint("\x1b[1;32m✓\x1b[0m \x1b[1m{s}\x1b[0m \x1b[2m(\x1b[0m{s}{d} ms\x1b[0m\x1b[2m)\x1b[0m\n", .{ label, ms_color, elapsed_ms });
    } else {
        wprint("✓ {s} ({d} ms)\n", .{ label, elapsed_ms });
    }
}

pub fn traceSummary(label: []const u8, comptime fmt: []const u8, args: anytype) void {
    if (!trace) return;
    if (color) {
        wprint("\x1b[1;4m{s}\x1b[0m \x1b[2m┄▶\x1b[0m \x1b[3m", .{label});
        wprint(fmt, args);
        wprint("\x1b[0m\n", .{});
    } else {
        wprint("{s}: ", .{label});
        wprint(fmt, args);
        wprint("\n", .{});
    }
}

// ── Rich compile pipeline tree (opt-in: --trace with -v or --build-report verbose) ─

var pipeline_open: bool = false;
var pipeline_step: u32 = 0;
var pipeline_peak_ms: u64 = 0;

pub fn richPipeline() bool {
    return trace and (verbose_level > 0 or build_report == .verbose);
}

pub fn pipelineBegin(title: []const u8) void {
    if (!richPipeline()) return;
    pipeline_open = true;
    pipeline_step = 0;
    pipeline_peak_ms = 0;
    if (color) {
        wprint("\x1b[1;36m╭─ {s}\x1b[0m \x1b[2m┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\x1b[0m\n", .{title});
    } else {
        wprint("== {s} ==\n", .{title});
    }
}

fn microBar(elapsed_ms: u64, peak_ms: u64, width: usize) void {
    const pk = if (peak_ms == 0) 1 else peak_ms;
    const filled = @min(width, (elapsed_ms * width) / pk);
    // Intensity gradient: green (fast) → yellow → red (slowest phase seen).
    const bar_color: []const u8 = blk: {
        if (!color) break :blk "";
        if (elapsed_ms < 50) break :blk "\x1b[32m";
        if (elapsed_ms < 500) break :blk "\x1b[33m";
        break :blk "\x1b[31m";
    };
    if (color) {
        wprint("\x1b[2m ", .{});
        var i: usize = 0;
        while (i < width) : (i += 1) {
            if (i < filled) wprint("{s}▰\x1b[0m", .{bar_color}) else wprint("\x1b[2m▱\x1b[0m", .{});
        }
    } else {
        var i: usize = 0;
        while (i < width) : (i += 1) {
            if (i < filled) wprint("#", .{}) else wprint(".", .{});
        }
    }
}

pub fn pipelinePhaseActive(label: []const u8) void {
    if (!richPipeline()) return;
    pipeline_step += 1;
    if (color) {
        wprint("  \x1b[2m│\x1b[0m \x1b[2;36m#{}\x1b[0m \x1b[2;35m⠋\x1b[0m \x1b[1m{s}\x1b[0m \x1b[2m…\x1b[0m\n", .{ pipeline_step, label });
    } else {
        wprint("  {d}. {s} …\n", .{ pipeline_step, label });
    }
}

pub fn pipelinePhaseComplete(label: []const u8, elapsed_ms: u64, detail: ?[]const u8) void {
    if (!richPipeline()) return;
    if (elapsed_ms > pipeline_peak_ms) pipeline_peak_ms = elapsed_ms;
    const ms_color: []const u8 = blk: {
        if (!color) break :blk "";
        if (elapsed_ms < 50) break :blk "\x1b[32m";
        if (elapsed_ms < 500) break :blk "\x1b[33m";
        break :blk "\x1b[31m";
    };
    if (color) {
        wprint("  \x1b[2m│\x1b[0m \x1b[2;36m#{}\x1b[0m \x1b[1;32m✓\x1b[0m \x1b[1m{s}\x1b[0m ", .{ pipeline_step, label });
        microBar(elapsed_ms, pipeline_peak_ms, 12);
        wprint(" {s}\x1b[1m{d} ms\x1b[0m", .{ ms_color, elapsed_ms });
        if (detail) |d| wprint(" \x1b[2m⟶\x1b[0m \x1b[3;36m{s}\x1b[0m", .{d});
        wprint("\n", .{});
    } else {
        wprint("  {d}. ok {s} ({d} ms", .{ pipeline_step, label, elapsed_ms });
        if (detail) |d| wprint(" — {s}", .{d});
        wprint(")\n", .{});
    }
}

pub fn pipelineEnd(total_ms: u64, footer: []const u8) void {
    if (!pipeline_open) return;
    pipeline_open = false;
    if (color) {
        wprint("\x1b[2m╰─\x1b[0m \x1b[1;4m{d} ms\x1b[0m \x1b[1;36m⟶\x1b[0m \x1b[3;36m{s}\x1b[0m\n", .{ total_ms, footer });
    } else {
        wprint("total {d} ms → {s}\n", .{ total_ms, footer });
    }
}

pub const BuildTargetRow = struct {
    name: []const u8,
    kind: []const u8,
    glyph: []const u8,
    src: ?[]const u8,
    out: ?[]const u8,
    stage: i32,
    stage_name: ?[]const u8,
    is_default: bool,
    deps: []const []const u8,
};

pub fn buildProjectHero(name: ?[]const u8, version: ?[]const u8, build_source: []const u8) void {
    if (build_report == .plain) return;
    if (color) {
        wprint("\x1b[1;35m╭─ project\x1b[0m", .{});
        if (name) |n| wprint(" \x1b[1m{s}\x1b[0m", .{n});
        if (version) |v| wprint(" \x1b[2mv{s}\x1b[0m", .{v});
        wprint("\n", .{});
        wprint("  \x1b[2mbuild\x1b[0m \x1b[36m{s}\x1b[0m\n", .{build_source});
    } else {
        if (name) |n| {
            if (version) |v| wprint("project {s} v{s}\n", .{ n, v }) else wprint("project {s}\n", .{n});
        }
        wprint("  build {s}\n", .{build_source});
    }
}

pub fn buildTargetTable(rows: []const BuildTargetRow) void {
    if (build_report == .plain) return;
    if (color) {
        wprint("\x1b[2m╭─ targets ─────────────────────────────\x1b[0m\n", .{});
    } else {
        wprint("targets:\n", .{});
    }
    for (rows) |row| {
        const src = row.src orelse "—";
        const out = row.out orelse "—";
        if (color) {
            wprint("  \x1b[2m│\x1b[0m {s} ", .{row.glyph});
            if (row.is_default) {
                wprint("\x1b[1;36m{s}\x1b[0m", .{row.name});
            } else {
                wprint("\x1b[1m{s}\x1b[0m", .{row.name});
            }
            wprint(" \x1b[2m{s}\x1b[0m", .{row.kind});
            if (row.stage_name) |stage| {
                wprint(" \x1b[2mstage {s}", .{stage});
                if (row.stage != 0) wprint(":{d}", .{row.stage});
                wprint("\x1b[0m", .{});
            } else if (row.stage != 0) wprint(" \x1b[2mstage {d}\x1b[0m", .{row.stage});
            if (row.is_default) wprint(" \x1b[32m★ default\x1b[0m", .{});
            wprint("\n", .{});
            wprint("  \x1b[2m│   \x1b[0m \x1b[2msrc\x1b[0m \x1b[36m{s}\x1b[0m", .{src});
            if (row.out) |_| wprint(" \x1b[2m→\x1b[0m \x1b[36m{s}\x1b[0m", .{out});
            wprint("\n", .{});
            if (row.deps.len > 0) {
                wprint("  \x1b[2m│   \x1b[0m \x1b[2mdeps\x1b[0m ", .{});
                for (row.deps, 0..) |d, i| {
                    if (i > 0) wprint(",", .{});
                    wprint(" {s}", .{d});
                }
                wprint("\n", .{});
            }
        } else {
            wprint("  {s} {s} ({s})", .{ row.glyph, row.name, row.kind });
            if (row.stage_name) |stage| wprint(" [stage {s}]", .{stage}) else if (row.stage != 0) wprint(" [stage {d}]", .{row.stage});
            if (row.is_default) wprint(" [default]", .{});
            wprint("\n    src {s} → {s}\n", .{ src, out });
        }
    }
    if (color) {
        wprint("\x1b[2m╰─ {d} target(s) · duo build <name>\x1b[0m\n", .{rows.len});
    } else {
        wprint("{d} target(s)\n", .{rows.len});
    }
}

fn channelAccent(channel: []const u8) []const u8 {
    if (!color) return "";
    if (std.mem.eql(u8, channel, "lex")) return "\x1b[35m";
    if (std.mem.eql(u8, channel, "parse")) return "\x1b[36m";
    if (std.mem.eql(u8, channel, "sema")) return "\x1b[34m";
    if (std.mem.eql(u8, channel, "types")) return "\x1b[95m";
    if (std.mem.eql(u8, channel, "mono")) return "\x1b[33m";
    if (std.mem.eql(u8, channel, "arc")) return "\x1b[32m";
    if (std.mem.eql(u8, channel, "async")) return "\x1b[96m";
    if (std.mem.eql(u8, channel, "codegen")) return "\x1b[31m";
    if (std.mem.eql(u8, channel, "build")) return "\x1b[1;36m";
    if (std.mem.eql(u8, channel, "test")) return "\x1b[1;35m";
    if (std.mem.eql(u8, channel, "link")) return "\x1b[1;33m";
    return "\x1b[35m";
}

/// Per-channel glyph — gives the eye an anchor when scanning trace trees.
fn channelGlyph(channel: []const u8) []const u8 {
    if (std.mem.eql(u8, channel, "lex")) return "❖";
    if (std.mem.eql(u8, channel, "parse")) return "≻";
    if (std.mem.eql(u8, channel, "sema")) return "⊙";
    if (std.mem.eql(u8, channel, "types")) return "⊤";
    if (std.mem.eql(u8, channel, "mono")) return "◐";
    if (std.mem.eql(u8, channel, "arc")) return "↻";
    if (std.mem.eql(u8, channel, "async")) return "⧗";
    if (std.mem.eql(u8, channel, "codegen")) return "⚙";
    if (std.mem.eql(u8, channel, "build")) return "⚒";
    if (std.mem.eql(u8, channel, "test")) return "✓";
    if (std.mem.eql(u8, channel, "link")) return "⛓";
    return "✶";
}

/// Small structural mark beside a scope name — semantic signal, not decoration.
fn scopeMark(scope: []const u8) []const u8 {
    if (std.mem.eql(u8, scope, "module")) return "⬚";
    if (std.mem.eql(u8, scope, "function")) return "ƒ";
    if (std.mem.eql(u8, scope, "struct")) return "◧";
    if (std.mem.eql(u8, scope, "enum")) return "☰";
    if (std.mem.eql(u8, scope, "table")) return "▥";
    if (std.mem.eql(u8, scope, "macro")) return "⧉";
    if (std.mem.eql(u8, scope, "generic")) return "⟨⟩";
    if (std.mem.eql(u8, scope, "trait")) return "◆";
    if (std.mem.eql(u8, scope, "impl")) return "⚑";
    return "·";
}

fn debugTreePrefix(depth: u32) void {
    if (depth == 0) return;
    var i: u32 = 0;
    while (i + 1 < depth) : (i += 1) {
        if (color) wprint("\x1b[2m│  \x1b[0m", .{}) else wprint("| ", .{});
    }
    if (color) wprint("\x1b[2m├─\x1b[0m ", .{}) else wprint("+- ", .{});
}

var compact_line_open: bool = false;

fn testCompactChar(ch: u8) void {
    if (test_report != .compact) return;
    if (!compact_line_open) {
        if (color) wprint("  \x1b[2m[\x1b[0m", .{}) else wprint("  [", .{});
        compact_line_open = true;
    }
    if (color) {
        switch (ch) {
            'p' => wprint("\x1b[32m●\x1b[0m", .{}),
            'f' => wprint("\x1b[31m●\x1b[0m", .{}),
            's' => wprint("\x1b[33m○\x1b[0m", .{}),
            'b' => wprint("\x1b[35m◆\x1b[0m", .{}),
            else => wprint("{c}", .{ch}),
        }
    } else {
        wprint("{c}", .{ch});
    }
}

fn testCompactClose() void {
    if (!compact_line_open) return;
    compact_line_open = false;
    if (color) wprint("\x1b[2m]\x1b[0m\n", .{}) else wprint("]\n", .{});
}

// ── Report styles & structured output ─────────────────────────────────────────

pub const ReportStyle = enum { compact, pretty, verbose, plain, json };

pub var test_report: ReportStyle = .pretty;
pub var build_report: ReportStyle = .pretty;
pub var debug_enabled: bool = false;
pub var verbose_level: u8 = 0;

const TestStats = struct {
    run: u32 = 0,
    pass: u32 = 0,
    fail: u32 = 0,
    skip: u32 = 0,
    flaky: u32 = 0,
    bench: u32 = 0,
    timed: u32 = 0,
    active: bool = false,
    bench_mode: bool = false,
    current: ?[]const u8 = null,
};

var test_stats: TestStats = .{};

pub fn setTestReport(style: ReportStyle) void {
    test_report = style;
}

pub fn setBuildReport(style: ReportStyle) void {
    build_report = style;
}

pub fn testUsesStructuredOutput() bool {
    return test_report != .plain;
}

fn indent(depth: u32) void {
    var i: u32 = 0;
    while (i < depth) : (i += 1) {
        wprint("  ", .{});
    }
}

pub fn debugEventChannel(channel: []const u8, scope: []const u8, comptime fmt: []const u8, args: anytype) void {
    if (!debug_enabled) return;
    const depth = @import("debug_trace.zig").filter().depth;
    if (test_report == .compact and depth > 0 and verbose_level == 0) return;
    const accent = channelAccent(channel);
    const glyph = channelGlyph(channel);
    const smark = scopeMark(scope);

    if (color) {
        // Depth tree (dim) — eye-anchor for nested traces.
        if (depth > 0) debugTreePrefix(depth) else wprint("\x1b[2m··\x1b[0m ", .{});

        // Glyph (accent + bold) signals which pipeline phase is emitting.
        wprint("{s}\x1b[1m{s}\x1b[0m ", .{ accent, glyph });
        // Bracket channel name bold+accent, scope-mark italic dim, scope italic accent.
        wprint("\x1b[2m[\x1b[0m{s}\x1b[1m{s}\x1b[0m \x1b[2m/\x1b[0m {s}\x1b[3m{s}\x1b[0m{s} \x1b[3m{s}\x1b[0m\x1b[2m]\x1b[0m", .{
            accent, channel, accent, smark, accent, scope,
        });
        // Dim arrow separates metadata from payload.
        wprint(" \x1b[2m→\x1b[0m ", .{});
        // Payload: italic + accent — semantic content stands apart from chrome.
        wprint("\x1b[3m{s}", .{accent});
        wprint(fmt, args);
        wprint("\x1b[0m\n", .{});
    } else {
        var i: u32 = 0;
        while (i < depth) : (i += 1) wprint("  ", .{});
        if (depth > 0) wprint("- ", .{});
        wprint("{s} debug [{s}/{s} {s}] ", .{ glyph, channel, scope, smark });
        wprint(fmt, args);
        wprint("\n", .{});
    }
}

pub fn debugEvent(comptime fmt: []const u8, args: anytype) void {
    debugEventChannel("all", "module", fmt, args);
}

pub fn buildPhaseStart(phase: []const u8, detail: ?[]const u8) void {
    if (build_report == .plain) return;
    if (build_report == .compact and verbose_level == 0) return;
    if (color) {
        wprint("  \x1b[2;36m▸\x1b[0m \x1b[1m{s}\x1b[0m", .{phase});
        if (detail) |d| wprint(" \x1b[2m·\x1b[0m \x1b[3;36m{s}\x1b[0m", .{d});
        wprint(" \x1b[2m…\x1b[0m\n", .{});
    } else {
        if (detail) |d| {
            wprint("  > {s} ({s}) …\n", .{ phase, d });
        } else {
            wprint("  > {s} …\n", .{phase});
        }
    }
}

pub fn buildPhaseDone(phase: []const u8, elapsed_ms: u64, detail: ?[]const u8) void {
    if (build_report == .plain) return;
    const ms_color: []const u8 = blk: {
        if (!color) break :blk "";
        if (elapsed_ms < 50) break :blk "\x1b[32m";
        if (elapsed_ms < 500) break :blk "\x1b[33m";
        break :blk "\x1b[31m";
    };
    if (color) {
        wprint("  \x1b[1;32m✓\x1b[0m \x1b[1m{s}\x1b[0m \x1b[2m(\x1b[0m{s}\x1b[1m{d} ms\x1b[0m", .{ phase, ms_color, elapsed_ms });
        if (detail) |d| wprint("\x1b[2m · \x1b[0m\x1b[3;36m{s}\x1b[0m", .{d});
        wprint("\x1b[2m)\x1b[0m\n", .{});
    } else {
        if (detail) |d| {
            wprint("  ok {s} ({d} ms — {s})\n", .{ phase, elapsed_ms, d });
        } else {
            wprint("  ok {s} ({d} ms)\n", .{ phase, elapsed_ms });
        }
    }
}

pub fn buildTargetCard(name: []const u8, src: []const u8, kind: []const u8) void {
    if (build_report == .plain) return;
    if (color) {
        wprint("\x1b[1;36m╭─ target\x1b[0m \x1b[1;4m{s}\x1b[0m \x1b[2m({s})\x1b[0m\n", .{ name, kind });
        wprint("  \x1b[2m│\x1b[0m \x1b[2msrc\x1b[0m \x1b[2m·\x1b[0m \x1b[4;36m{s}\x1b[0m\n", .{src});
    } else {
        wprint("target {s} ({s})\n  src {s}\n", .{ name, kind, src });
    }
}

pub fn testSessionBegin(bench_mode: bool) void {
    test_stats = .{ .active = true, .bench_mode = bench_mode };
    compact_line_open = false;
    if (test_report == .json) {
        emitTestJson(.{ .event = "session", .bench = bench_mode });
        return;
    }
    if (test_report == .plain) return;
    if (color) {
        wprint("\x1b[1;36m╭─ run\x1b[0m \x1b[2m┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄\x1b[0m\n", .{});
    } else {
        wprint("--- run ---\n", .{});
    }
}

pub fn testSessionEnd() void {
    if (!test_stats.active) return;
    testCompactClose();
    testSummary();
    test_stats.active = false;
}

fn testIconPass() []const u8 {
    return if (color) "\x1b[32m✓\x1b[0m" else "ok";
}

fn testIconFail() []const u8 {
    return if (color) "\x1b[31m✗\x1b[0m" else "FAIL";
}

fn testIconSkip() []const u8 {
    return if (color) "\x1b[33m⊘\x1b[0m" else "SKIP";
}

fn testIconRun() []const u8 {
    return if (color) "\x1b[36m▶\x1b[0m" else "RUN";
}

fn testIconBench() []const u8 {
    return if (color) "\x1b[35m⏱\x1b[0m" else "BENCH";
}

fn testIconFlaky() []const u8 {
    return if (color) "\x1b[33m~\x1b[0m" else "FLAKY";
}

fn testPrintRun(name: []const u8) void {
    if (test_report == .compact) return;
    wprint("  {s} \x1b[1m{s}\x1b[0m\n", .{ testIconRun(), name });
}

fn testPrintPass(name: []const u8, flaky: bool) void {
    if (test_report == .compact) return;
    if (flaky) {
        wprint("  {s} {s} \x1b[2m(flaky)\x1b[0m\n", .{ testIconFlaky(), name });
    } else if (color) {
        wprint("  {s} {s}\n", .{ testIconPass(), name });
    } else {
        wprint("  ok {s}\n", .{name});
    }
}

fn testPrintSkip(name: []const u8, reason: ?[]const u8) void {
    if (test_report == .compact and reason == null) return;
    if (reason) |r| {
        wprint("  {s} {s} \x1b[2m— {s}\x1b[0m\n", .{ testIconSkip(), name, r });
    } else {
        wprint("  {s} {s}\n", .{ testIconSkip(), name });
    }
}

fn testPrintBench(name: []const u8, warmup: u32, iter: u32, elapsed: f64, per_us: f64) void {
    if (test_report == .compact) {
        wprint("  {s} {s} \x1b[2m{d:.3} µs/iter\x1b[0m\n", .{ testIconBench(), name, per_us });
        return;
    }
    if (color) {
        wprint("  {s} \x1b[1m{s}\x1b[0m warmup={} iter={} \x1b[2melapsed={d:.6}s\x1b[0m \x1b[36m{d:.3} µs/iter\x1b[0m\n", .{
            testIconBench(),
            name,
            warmup,
            iter,
            elapsed,
            per_us,
        });
    } else {
        wprint("  BENCH {s} warmup={} iter={} elapsed={d:.6}s {d:.3} us/iter\n", .{
            name, warmup, iter, elapsed, per_us,
        });
    }
}

fn testPrintTime(name: []const u8, elapsed: f64) void {
    if (test_report == .compact) return;
    if (color) {
        wprint("  \x1b[36m⏱\x1b[0m {s} \x1b[2m{d:.6}s\x1b[0m\n", .{ name, elapsed });
    } else {
        wprint("  TIME {s}: {d:.6}s\n", .{ name, elapsed });
    }
}

fn testPrintFail(name: []const u8, reason: ?[]const u8) void {
    if (reason) |r| {
        wprint("  {s} \x1b[1m{s}\x1b[0m \x1b[31m{s}\x1b[0m\n", .{ testIconFail(), name, r });
    } else {
        wprint("  {s} \x1b[1m{s}\x1b[0m\n", .{ testIconFail(), name });
    }
}

pub fn testSummary() void {
    if (test_report == .json) {
        emitTestJson(.{
            .event = "summary",
            .run = test_stats.run,
            .pass = test_stats.pass,
            .fail = test_stats.fail,
            .skip = test_stats.skip,
            .flaky = test_stats.flaky,
            .bench = test_stats.bench > 0,
            .timed = test_stats.timed,
        });
        return;
    }
    if (test_report == .plain) return;
    testCompactClose();
    const s = test_stats;
    if (color) {
        wprint("\x1b[2m╰─ summary ───────────────────────────\x1b[0m\n", .{});
        if (s.fail == 0 and s.pass > 0) {
            const pct: u32 = if (s.run > 0) @intCast((s.pass * 100) / s.run) else 100;
            wprint("  \x1b[32m▰▰▰▰▰▰▰▰▰▰\x1b[0m \x1b[32m{} passed\x1b[0m ({d}%)\n", .{ s.pass, pct });
        } else if (s.fail > 0) {
            wprint("  \x1b[31m{} failed\x1b[0m", .{s.fail});
            if (s.pass > 0) wprint(" · \x1b[32m{} passed\x1b[0m", .{s.pass});
            wprint("\n", .{});
        } else {
            wprint("  {} run\n", .{s.run});
        }
        wprint(" · {} run", .{s.run});
        if (s.skip > 0) wprint(" · \x1b[33m{} skipped\x1b[0m", .{s.skip});
        if (s.flaky > 0) wprint(" · \x1b[33m{} flaky\x1b[0m", .{s.flaky});
        if (s.bench > 0) wprint(" · \x1b[35m{} bench\x1b[0m", .{s.bench});
        if (s.timed > 0) wprint(" · \x1b[36m{} timed\x1b[0m", .{s.timed});
        wprint("\n", .{});
    } else {
        wprint("summary: {} run, {} pass, {} fail, {} skip\n", .{ s.run, s.pass, s.fail, s.skip });
    }
}

fn parseEvtFields(line: []const u8) struct {
    name: ?[]const u8 = null,
    reason: ?[]const u8 = null,
    warmup: ?u32 = null,
    iter: ?u32 = null,
    elapsed: ?f64 = null,
    per_us: ?f64 = null,
    run: ?u32 = null,
    pass: ?u32 = null,
    skipped: ?u32 = null,
    failed: ?u32 = null,
} {
    var out: @TypeOf(parseEvtFields("")) = .{};
    var i: usize = 0;
    while (i < line.len) {
        const remaining = line[i..];
        const tab = std.mem.indexOfScalar(u8, remaining, '\t') orelse remaining.len;
        const field = remaining[0..tab];
        if (std.mem.indexOfScalar(u8, field, '=')) |eq| {
            const k = field[0..eq];
            const v = field[eq + 1 ..];
            if (std.mem.eql(u8, k, "name")) out.name = v else if (std.mem.eql(u8, k, "reason")) out.reason = v else if (std.mem.eql(u8, k, "warmup")) out.warmup = std.fmt.parseInt(u32, v, 10) catch null else if (std.mem.eql(u8, k, "iter")) out.iter = std.fmt.parseInt(u32, v, 10) catch null else if (std.mem.eql(u8, k, "elapsed")) out.elapsed = std.fmt.parseFloat(f64, v) catch null else if (std.mem.eql(u8, k, "per_us")) out.per_us = std.fmt.parseFloat(f64, v) catch null else if (std.mem.eql(u8, k, "run")) out.run = std.fmt.parseInt(u32, v, 10) catch null else if (std.mem.eql(u8, k, "pass")) out.pass = std.fmt.parseInt(u32, v, 10) catch null else if (std.mem.eql(u8, k, "skipped")) out.skipped = std.fmt.parseInt(u32, v, 10) catch null else if (std.mem.eql(u8, k, "failed")) out.failed = std.fmt.parseInt(u32, v, 10) catch null;
        }
        i += tab + 1;
    }
    return out;
}

fn handleTestEvt(event: []const u8, fields_line: []const u8) void {
    const f = parseEvtFields(fields_line);
    const show_pretty = test_report != .json;
    if (test_report == .json) {
        emitTestJson(.{
            .event = event,
            .name = f.name,
            .reason = f.reason,
            .warmup = f.warmup,
            .iter = f.iter,
            .elapsed = f.elapsed,
            .per_us = f.per_us,
            .run = f.run,
            .pass = f.pass,
            .skip = f.skipped,
            .fail = f.failed,
        });
    }
    if (std.mem.eql(u8, event, "run")) {
        test_stats.run += 1;
        test_stats.current = f.name;
        if (show_pretty) if (f.name) |n| testPrintRun(n);
    } else if (std.mem.eql(u8, event, "pass")) {
        test_stats.pass += 1;
        if (show_pretty) if (f.name) |n| {
            if (test_report == .compact) testCompactChar('p') else testPrintPass(n, false);
        };
    } else if (std.mem.eql(u8, event, "skip")) {
        test_stats.skip += 1;
        if (show_pretty) if (f.name) |n| {
            if (test_report == .compact) testCompactChar('s') else testPrintSkip(n, f.reason);
        };
    } else if (std.mem.eql(u8, event, "fail")) {
        test_stats.fail += 1;
        if (show_pretty) if (f.name) |n| {
            if (test_report == .compact) testCompactChar('f') else testPrintFail(n, f.reason);
        };
    } else if (std.mem.eql(u8, event, "flaky")) {
        test_stats.flaky += 1;
        test_stats.pass += 1;
        if (show_pretty) if (f.name) |n| {
            if (test_report == .compact) testCompactChar('p') else testPrintPass(n, true);
        };
    } else if (std.mem.eql(u8, event, "bench")) {
        test_stats.bench += 1;
        if (show_pretty) if (f.name) |n| {
            if (test_report == .compact) {
                testCompactChar('b');
            } else {
                const w = f.warmup orelse 0;
                const it = f.iter orelse 1;
                const el = f.elapsed orelse 0;
                const pu = f.per_us orelse 0;
                testPrintBench(n, w, it, el, pu);
            }
        };
    } else if (std.mem.eql(u8, event, "time")) {
        test_stats.timed += 1;
        if (show_pretty) if (f.name) |n| testPrintTime(n, f.elapsed orelse 0);
    } else if (std.mem.eql(u8, event, "summary")) {
        if (f.run) |r| test_stats.run = r;
        if (f.pass) |p| test_stats.pass = p else if (f.run) |r| {
            if (f.failed) |fl| test_stats.pass = r - fl;
        }
        if (f.skipped) |s| test_stats.skip = s;
        if (f.failed) |fl| test_stats.fail = fl;
    }
}

fn handleLegacyTestLine(line: []const u8) void {
    if (std.mem.startsWith(u8, line, "RUN  ") or std.mem.startsWith(u8, line, "RUN ")) {
        const name = std.mem.trim(u8, line[4..], " ");
        test_stats.run += 1;
        testPrintRun(name);
    } else if (std.mem.startsWith(u8, line, "SKIP ")) {
        const rest = std.mem.trim(u8, line[5..], " ");
        test_stats.skip += 1;
        testPrintSkip(rest, null);
    } else if (std.mem.startsWith(u8, line, "ok   ") or std.mem.startsWith(u8, line, "ok ")) {
        const name = std.mem.trim(u8, if (line.len > 4 and line[3] == ' ') line[4..] else line[3..], " ");
        test_stats.pass += 1;
        testPrintPass(name, false);
    } else if (std.mem.startsWith(u8, line, "FLAKY ")) {
        const name = std.mem.trim(u8, line[6..], " ");
        test_stats.flaky += 1;
        test_stats.pass += 1;
        testPrintPass(name, true);
    } else if (std.mem.startsWith(u8, line, "BENCH ")) {
        test_stats.bench += 1;
        if (test_report != .compact) wprint("  {s} {s}\n", .{ testIconBench(), line[6..] });
    } else if (std.mem.startsWith(u8, line, "TIME ")) {
        test_stats.timed += 1;
        if (test_report != .compact) wprint("  \x1b[36m⏱\x1b[0m {s}\n", .{line[5..]});
    } else if (std.mem.indexOf(u8, line, " run, ") != null and std.mem.indexOf(u8, line, " skipped") != null) {
        // legacy summary: "N run, M skipped, K failed"
        // leave stats from individual lines
        if (test_report == .verbose) wprint("  \x1b[2m{s}\x1b[0m\n", .{line});
    }
}

/// Feed one line from test runner stderr (DUO_EVT protocol or legacy).
pub fn feedTestLine(line: []const u8) void {
    if (test_report == .plain) {
        wprint("{s}\n", .{line});
        return;
    }
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len == 0) return;

    if (std.mem.startsWith(u8, trimmed, "DUO_EVT\t")) {
        const rest = trimmed["DUO_EVT\t".len..];
        const kind_end = std.mem.indexOfScalar(u8, rest, '\t') orelse return;
        const kind = rest[0..kind_end];
        const after_kind = rest[kind_end + 1 ..];
        const evt_end = std.mem.indexOfScalar(u8, after_kind, '\t') orelse return;
        const event = after_kind[0..evt_end];
        const fields = after_kind[evt_end + 1 ..];
        if (std.mem.eql(u8, kind, "test")) {
            handleTestEvt(event, fields);
        } else if (std.mem.eql(u8, kind, "build") and (test_report == .verbose or test_report == .json)) {
            if (test_report == .json) {
                emitTestJson(.{ .event = "build", .name = event, .reason = fields });
            } else {
                wprint("  \x1b[2mbuild\x1b[0m {s} {s}\n", .{ event, fields });
            }
        }
        return;
    }
    if (test_report == .json) return;
    handleLegacyTestLine(trimmed);
    if (test_report == .verbose and (std.mem.startsWith(u8, trimmed, "assertion failed:") or std.mem.startsWith(u8, trimmed, "error:"))) {
        wprint("    \x1b[2m{s}\x1b[0m\n", .{trimmed});
    }
}

pub fn parseReportStyle(name: []const u8) ?ReportStyle {
    if (std.mem.eql(u8, name, "compact")) return .compact;
    if (std.mem.eql(u8, name, "pretty")) return .pretty;
    if (std.mem.eql(u8, name, "verbose")) return .verbose;
    if (std.mem.eql(u8, name, "plain")) return .plain;
    if (std.mem.eql(u8, name, "json")) return .json;
    return null;
}

const TestJsonFields = struct {
    event: []const u8,
    name: ?[]const u8 = null,
    reason: ?[]const u8 = null,
    bench: bool = false,
    warmup: ?u32 = null,
    iter: ?u32 = null,
    elapsed: ?f64 = null,
    per_us: ?f64 = null,
    run: ?u32 = null,
    pass: ?u32 = null,
    fail: ?u32 = null,
    skip: ?u32 = null,
    flaky: ?u32 = null,
    timed: ?u32 = null,
};

fn jsonEscape(buf: *std.ArrayList(u8), alloc: std.mem.Allocator, s: []const u8) !void {
    for (s) |c| switch (c) {
        '"' => try buf.appendSlice(alloc, "\\\""),
        '\\' => try buf.appendSlice(alloc, "\\\\"),
        '\n' => try buf.appendSlice(alloc, "\\n"),
        '\r' => try buf.appendSlice(alloc, "\\r"),
        '\t' => try buf.appendSlice(alloc, "\\t"),
        else => try buf.append(alloc, c),
    };
}

fn emitTestJson(fields: TestJsonFields) void {
    const alloc = std.heap.page_allocator;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(alloc);
    buf.appendSlice(alloc, "{\"kind\":\"test\",\"event\":\"") catch return;
    jsonEscape(&buf, alloc, fields.event) catch return;
    buf.appendSlice(alloc, "\"") catch return;
    if (fields.name) |n| {
        buf.appendSlice(alloc, ",\"name\":\"") catch return;
        jsonEscape(&buf, alloc, n) catch return;
        buf.appendSlice(alloc, "\"") catch return;
    }
    if (fields.reason) |r| {
        buf.appendSlice(alloc, ",\"reason\":\"") catch return;
        jsonEscape(&buf, alloc, r) catch return;
        buf.appendSlice(alloc, "\"") catch return;
    }
    if (fields.bench) {
        buf.appendSlice(alloc, ",\"bench\":true") catch return;
    }
    if (fields.warmup) |w| {
        var tmp: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, ",\"warmup\":{d}", .{w}) catch return;
        buf.appendSlice(alloc, s) catch return;
    }
    if (fields.iter) |it| {
        var tmp: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, ",\"iter\":{d}", .{it}) catch return;
        buf.appendSlice(alloc, s) catch return;
    }
    if (fields.elapsed) |el| {
        var tmp: [48]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, ",\"elapsed\":{d}", .{el}) catch return;
        buf.appendSlice(alloc, s) catch return;
    }
    if (fields.per_us) |pu| {
        var tmp: [48]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, ",\"per_us\":{d}", .{pu}) catch return;
        buf.appendSlice(alloc, s) catch return;
    }
    if (fields.run) |r| {
        var tmp: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, ",\"run\":{d}", .{r}) catch return;
        buf.appendSlice(alloc, s) catch return;
    }
    if (fields.pass) |p| {
        var tmp: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, ",\"pass\":{d}", .{p}) catch return;
        buf.appendSlice(alloc, s) catch return;
    }
    if (fields.fail) |f| {
        var tmp: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, ",\"fail\":{d}", .{f}) catch return;
        buf.appendSlice(alloc, s) catch return;
    }
    if (fields.skip) |sk| {
        var tmp: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, ",\"skip\":{d}", .{sk}) catch return;
        buf.appendSlice(alloc, s) catch return;
    }
    if (fields.flaky) |fl| {
        var tmp: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, ",\"flaky\":{d}", .{fl}) catch return;
        buf.appendSlice(alloc, s) catch return;
    }
    if (fields.timed) |t| {
        var tmp: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, ",\"timed\":{d}", .{t}) catch return;
        buf.appendSlice(alloc, s) catch return;
    }
    buf.appendSlice(alloc, "}\n") catch return;
    wprint("{s}", .{buf.items});
}

test "feedTestLine DUO_EVT pass in pretty mode" {
    test_report = .pretty;
    test_stats = .{};
    feedTestLine("DUO_EVT\ttest\tpass\tname=foo");
    try std.testing.expectEqual(@as(u32, 1), test_stats.pass);
}

test "feedTestLine DUO_EVT json mode" {
    test_report = .json;
    test_stats = .{};
    feedTestLine("DUO_EVT\ttest\tfail\tname=bar\treason=boom");
    try std.testing.expectEqual(@as(u32, 1), test_stats.fail);
}
