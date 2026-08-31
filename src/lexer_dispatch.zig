//! SH-03 production dispatch — the host consuming the Idol lexer's token stream.
//!
//! This is the production seam. It binds `duo_lexer_tokenize_full` from the
//! generated projection of `lib/compiler/lexer.id` and rebuilds host `Token`s
//! from the flat record
//! buffer, so the compiler can tokenize through Idol instead of `src/lexer.zig`.
//!
//! WHY `tokenize_full` AND NOT `tokenize_text`: `tokenize_text` writes six i64
//! per token and drops `float_val`. Dispatching on it would mis-read every float
//! literal while every kind- and text-based differential stayed green — which is
//! not hypothetical, it is exactly how GAP-021 hid for the whole life of  the Idol
//! lexer. The full entry carries the producer's eight projected fields.
//!
//! The generated-C bridge is produced directly from `lexer.id` with
//! `dump-c --lib`. GAP-020's former primary-module initialization workaround
//! is deleted; keeping that wrapper would leave an uncalled second ABI surface.
const std = @import("std");
const lexer = @import("lexer.zig");
const lexer_bridge = @import("lexer_bridge.zig");

/// Physical validation derived at comptime from the owner-generated sparse
/// enum. This is not an ordinal→semantic table: the accepted backing values are
/// the enum itself, and conversion below preserves the producer ordinal.
const token_kind_values = blk: {
    var values: std.StaticBitSet(256) = .empty;
    for (@typeInfo(lexer.TokenKind).@"enum".field_values) |value| values.set(value);
    break :blk values;
};

/// Producer schema queries (`law.schema.one`, `law.magic.zero`).
/// The host must not independently know slot positions, rejection codes, or
/// token kind ordinals. Query these facts instead of hardcoding.
extern fn recordslots() i64;
extern fn fieldkind() i64;
extern fn fieldline() i64;
extern fn fieldcol() i64;
extern fn fieldint() i64;
extern fn fieldoff() i64;
extern fn fieldlen() i64;
extern fn fieldfloat() i64;
extern fn _fieldintclass() i64;
extern fn rejectioncount() i64;
extern fn rejectioncode(i: i64) i64;
extern fn rejectionname(code: i64) [*:0]const u8;

extern fn duo_lexer_tokenize_full(
    src: [*:0]const u8,
    file: [*:0]const u8,
    family: i64,
    out: [*]i64,
    cap: i64,
    txt: i64,
    txtcap: i64,
) i64;

/// GAP-017 closed: the Idol lexer returns a REJECTION rather than aborting the
/// process. Host queries rejection identity by name, not magic code.
extern fn duo_lexer_error_line(src: [*:0]const u8, file: [*:0]const u8, family: i64) i64;

pub const DispatchError = error{
    BufferTooSmall,
    EmbeddedNul,
    InvalidBufferAddress,
    InvalidEndToken,
    InvalidRecordCount,
    InvalidRejectionCode,
    InvalidSourceSpan,
    InvalidTokenKind,
    InvalidTokenLocation,
    OutOfMemory,
    SourceTooLarge,
} || lexer.LexError;

/// Line of a source rejection. An invalid diagnostic record is an ABI failure,
/// not a fabricated source location.
pub fn errorLine(src: [:0]const u8, file: [:0]const u8, family: i64) error{InvalidTokenLocation}!u32 {
    const line = duo_lexer_error_line(src.ptr, file.ptr, family);
    if (line <= 0) return error.InvalidTokenLocation;
    return std.math.cast(u32, line) orelse error.InvalidTokenLocation;
}

fn rejectionNameToError(name: [*:0]const u8) ?lexer.LexError {
    const name_slice = std.mem.span(name);
    if (std.mem.eql(u8, name_slice, "UnterminatedString")) return error.UnterminatedString;
    if (std.mem.eql(u8, name_slice, "UnterminatedLongString")) return error.UnterminatedLongString;
    if (std.mem.eql(u8, name_slice, "InvalidEscape")) return error.InvalidEscape;
    if (std.mem.eql(u8, name_slice, "UnexpectedChar")) return error.UnexpectedChar;
    if (std.mem.eql(u8, name_slice, "InsufficientIndent")) return error.InsufficientIndent;
    return null;
}

fn slot(pos: i64, slots: usize) DispatchError!usize {
    const i = std.math.cast(usize, pos) orelse return DispatchError.InvalidRecordCount;
    if (i >= slots) return DispatchError.InvalidRecordCount;
    return i;
}

/// Producer record layout binds once (`law.schema.one`). `recordslots()` and
/// `field*()` are the same eight facts on every call; querying them per
/// tokenize is eight extra foreign calls on the compile hot path.
var record_slots: usize = 0;
var at_kind: usize = 0;
var at_line: usize = 0;
var at_col: usize = 0;
var at_int: usize = 0;
var at_off: usize = 0;
var at_len: usize = 0;
var at_float: usize = 0;
var at_int_class: usize = 0;
var record_bound = false;

fn bindRecordSchema() DispatchError!void {
    if (record_bound) return;
    const slots = std.math.cast(usize, recordslots()) orelse return DispatchError.InvalidRecordCount;
    if (slots == 0) return DispatchError.InvalidRecordCount;
    const kind = try slot(fieldkind(), slots);
    const line = try slot(fieldline(), slots);
    const col = try slot(fieldcol(), slots);
    const intv = try slot(fieldint(), slots);
    const off = try slot(fieldoff(), slots);
    const len = try slot(fieldlen(), slots);
    const flt = try slot(fieldfloat(), slots);
    const int_class = try slot(_fieldintclass(), slots);
    at_kind = kind;
    at_line = line;
    at_col = col;
    at_int = intv;
    at_off = off;
    at_len = len;
    at_float = flt;
    at_int_class = int_class;
    record_slots = slots;
    record_bound = true;
}

fn decodeRecords(
    allocator: std.mem.Allocator,
    src: []const u8,
    file: []const u8,
    records: []const i64,
    record_count: i64,
) DispatchError![]lexer.Token {
    try bindRecordSchema();
    const slots = record_slots;
    const kind_at = at_kind;
    const line_at = at_line;
    const col_at = at_col;
    const int_at = at_int;
    const off_at = at_off;
    const len_at = at_len;
    const float_at = at_float;
    const int_class_at = at_int_class;

    const count = std.math.cast(usize, record_count) orelse return DispatchError.InvalidRecordCount;
    if (count == 0) return DispatchError.InvalidRecordCount;
    const used_slots = std.math.mul(usize, count, slots) catch
        return DispatchError.InvalidRecordCount;
    if (used_slots > records.len) return DispatchError.InvalidRecordCount;

    const tokens = try allocator.alloc(lexer.Token, count);
    var rec = records;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const r = rec[0..slots];
        rec = rec[slots..];
        const tok = tokenFromRecord(
            r,
            src,
            file,
            kind_at,
            line_at,
            col_at,
            int_at,
            off_at,
            len_at,
            float_at,
            int_class_at,
            i + 1 == count,
        ) catch |e| {
            allocator.free(tokens);
            return e;
        };
        tokens[i] = tok;
    }
    return tokens;
}

fn tokenFromRecord(
    r: []const i64,
    src: []const u8,
    file: []const u8,
    kind_at: usize,
    line_at: usize,
    col_at: usize,
    int_at: usize,
    off_at: usize,
    len_at: usize,
    float_at: usize,
    int_class_at: usize,
    final: bool,
) DispatchError!lexer.Token {
    const raw_kind = std.math.cast(u8, r[kind_at]) orelse return DispatchError.InvalidTokenKind;
    if (!token_kind_values.isSet(raw_kind)) return DispatchError.InvalidTokenKind;
    const kind = @as(lexer.TokenKind, @fromBackingInt(raw_kind));
    const line = std.math.cast(u32, r[line_at]) orelse
        return DispatchError.InvalidTokenLocation;
    const col = std.math.cast(u32, r[col_at]) orelse
        return DispatchError.InvalidTokenLocation;
    if (line == 0 or col == 0) return DispatchError.InvalidTokenLocation;
    if (r[off_at] < 0 or r[len_at] < 0) return DispatchError.InvalidSourceSpan;
    const off = std.math.cast(usize, r[off_at]) orelse return DispatchError.InvalidSourceSpan;
    const len = std.math.cast(usize, r[len_at]) orelse return DispatchError.InvalidSourceSpan;
    if (off > src.len or len > src.len - off) return DispatchError.InvalidSourceSpan;
    if (kind == .eof) {
        if (!final or len != 0) return DispatchError.InvalidEndToken;
        const end_ok = off == src.len or (src.len > 0 and off + 1 == src.len and src[src.len - 1] == 0);
        if (!end_ok) return DispatchError.InvalidEndToken;
    } else if (final) {
        return DispatchError.InvalidEndToken;
    }
    const int_class: lexer.DecimalIntegerClass = switch (r[int_class_at]) {
        0 => .ordinary,
        1 => .min_magnitude,
        2 => .u64_bits,
        3 => .wider,
        else => return DispatchError.InvalidRecordCount,
    };
    switch (int_class) {
        .ordinary => {},
        .min_magnitude => if (kind != .int_lit or r[int_at] != std.math.minInt(i64))
            return DispatchError.InvalidRecordCount,
        .u64_bits => if (kind != .int_lit or r[int_at] >= 0)
            return DispatchError.InvalidRecordCount,
        .wider => if (kind != .int_lit or r[int_at] != 0)
            return DispatchError.InvalidRecordCount,
    }
    return .{
        .kind = kind,
        .loc = .{ .file = file, .line = line, .col = col },
        .text = src[off .. off + len],
        .int_val = r[int_at],
        .int_class = int_class,
        .float_val = @bitCast(r[float_at]),
    };
}

/// Tokenize `src` through the Idol lexer, returning host `Token`s.
///
/// `text` slices point into `view`, using source offsets published by the Idol
/// lexer. The host does not reconstruct provenance from copied token bytes.
/// `csrc`/`cfile` are the sentinel forms the generated-C entry requires;
/// `view`/`name` are the caller-owned spans tokens must observe.
pub fn tokenize(
    allocator: std.mem.Allocator,
    src: [:0]const u8,
    file: [:0]const u8,
    family: i64,
) DispatchError![]lexer.Token {
    if (std.mem.indexOfScalar(u8, src, 0) != null or
        std.mem.indexOfScalar(u8, file, 0) != null)
        return DispatchError.EmbeddedNul;
    return tokenizeTrusted(allocator, src, file, src, file, family);
}

fn tokenizeTrusted(
    allocator: std.mem.Allocator,
    csrc: [:0]const u8,
    cfile: [:0]const u8,
    view: []const u8,
    name: []const u8,
    family: i64,
) DispatchError![]lexer.Token {
    try bindRecordSchema();
    const slots = record_slots;
    const max_tokens = std.math.add(usize, view.len, 2) catch return DispatchError.SourceTooLarge;
    // Dense operator streams (`a+b+c`) exceed `len/4` tokens. First-fit
    // `len/2+16` avoids a full re-lex on typical source; the loop still
    // doubles to `len+2` on the cold BufferTooSmall path.
    var cap: usize = view.len / 2 + 16;
    if (cap > max_tokens) cap = max_tokens;
    if (cap < 8) cap = @min(@as(usize, 8), max_tokens);

    while (true) {
        const slot_count = std.math.mul(usize, cap, slots) catch
            return DispatchError.SourceTooLarge;
        const cap_i64 = std.math.cast(i64, cap) orelse return DispatchError.SourceTooLarge;
        const records = try allocator.alloc(i64, slot_count);
        const n = duo_lexer_tokenize_full(
            csrc.ptr,
            cfile.ptr,
            family,
            records.ptr,
            cap_i64,
            0,
            0,
        );
        if (n == -1) {
            allocator.free(records);
            if (cap >= max_tokens) return DispatchError.BufferTooSmall;
            const doubled = std.math.mul(usize, cap, 2) catch max_tokens;
            cap = @min(doubled, max_tokens);
            continue;
        }
        defer allocator.free(records);
        if (n < 0) {
            const name_err = rejectionname(n);
            return rejectionNameToError(name_err) orelse DispatchError.InvalidRejectionCode;
        }
        return decodeRecords(allocator, view, name, records, n);
    }
}

/// Drive `lex` from the Idol lexer's token stream instead of the host scanner.
///
/// This is the ONE production routing entry. It used to live in main.zig as a
/// private helper, which is why the compile driver tokenized through Idol while
/// codegen's module-embed paths — which build their own `Lexer` + `Parser` to
/// decide native embedding and to emit required modules — still ran the host
/// scanner. Two scanners deciding one compilation is exactly the shape that
/// hides a divergence: the driver would accept a source the embed path lexed
/// differently, and nothing would report it.
///
/// Every failure is returned. The host scanner is a differential oracle, not a
/// production fallback: resource pressure must not silently restore host
/// lexical authority.
///
/// Sentinel view for the generated-C `strlen` ABI. Fits in `buf` with no
/// heap; otherwise one heap copy. Tokens still observe the caller `src`.
const SentinelCopy = struct {
    z: [:0]const u8,
    heap: ?[:0]u8,
};

fn copySentinel(alloc: std.mem.Allocator, src: []const u8, buf: []u8) DispatchError!SentinelCopy {
    if (src.len < buf.len) {
        @memcpy(buf[0..src.len], src);
        buf[src.len] = 0;
        return .{ .z = buf[0..src.len :0], .heap = null };
    }
    const heap = std.mem.concatWithSentinel(alloc, u8, &.{src}, 0) catch
        return DispatchError.OutOfMemory;
    return .{ .z = heap, .heap = heap };
}

/// The token pack outlives `lex`. The NUL-terminated source and file copies are
/// needed only for the generated-C call (`strlen` ABI). Decode writes views
/// into the caller-owned source and file — no rebase walk after tokenize.
/// Typical files and every path fit in the stack buffers; heap only when
/// source exceeds that.
pub fn route(
    alloc: std.mem.Allocator,
    lex: *lexer.Lexer,
    src: []const u8,
    file: []const u8,
) !void {
    if (std.mem.indexOfScalar(u8, src, 0) != null or
        std.mem.indexOfScalar(u8, file, 0) != null)
        return DispatchError.EmbeddedNul;

    var src_buf: [32768]u8 = undefined;
    var file_buf: [512]u8 = undefined;
    const src_copy = try copySentinel(alloc, src, &src_buf);
    const file_copy = copySentinel(alloc, file, &file_buf) catch |e| {
        if (src_copy.heap) |p| alloc.free(p);
        return e;
    };
    const zsrc = src_copy.z;
    const zfile = file_copy.z;

    // Production tokens come from the Idol lexer. Family is the operand already
    // on `lex` — do not re-parse the path here (`law.family.one`).
    const family = lex.family;
    const toks: []lexer.Token = tokenizeTrusted(alloc, zsrc, zfile, src, file, family) catch |e| {
        switch (e) {
            error.UnterminatedString,
            error.UnterminatedLongString,
            error.InvalidNumber,
            error.UnexpectedChar,
            error.InvalidEscape,
            error.InsufficientIndent,
            => {
                const line = errorLine(zsrc, zfile, family) catch |le| {
                    if (src_copy.heap) |p| alloc.free(p);
                    if (file_copy.heap) |p| alloc.free(p);
                    return le;
                };
                lex.last_error_loc = .{ .file = file, .line = line, .col = 1 };
            },
            else => {},
        }
        if (src_copy.heap) |p| alloc.free(p);
        if (file_copy.heap) |p| alloc.free(p);
        return e;
    };
    if (src_copy.heap) |p| alloc.free(p);
    if (file_copy.heap) |p| alloc.free(p);
    lex.useDuoTokens(toks) catch |e| {
        alloc.free(toks);
        return e;
    };
}

/// Tokenize `src` with the HOST lexer — the differential's other side.
fn tokenizeHost(
    allocator: std.mem.Allocator,
    src: [:0]const u8,
    file: [:0]const u8,
    family: i64,
) ![]lexer.Token {
    var lx = lexer.Lexer.initFamily(src, file, family);
    var out: std.ArrayList(lexer.Token) = .empty;
    errdefer out.deinit(allocator);
    while (true) {
        const tok = try lx.next_tok();
        try out.append(allocator, tok);
        if (tok.kind == .eof) break;
    }
    return out.toOwnedSlice(allocator);
}

/// The property production dispatch rests on: for any source, the Idol lexer and
/// `src/lexer.zig` produce the SAME token stream — every field, not just kinds.
///
/// Existing SH-03 differentials compare fingerprints, which fold kinds (and,
/// separately, text). Neither reads `int_val` or `float_val`, which is how
/// GAP-021 survived — every float literal lexed to its integer part while all
/// gates stayed green. This compares the whole record.
pub fn differential(
    allocator: std.mem.Allocator,
    src: [:0]const u8,
    file: [:0]const u8,
    family: i64,
) !void {
    const host = try tokenizeHost(allocator, src, file, family);
    defer allocator.free(host);

    const idol = try tokenize(allocator, src, file, family);
    defer allocator.free(idol);

    if (host.len != idol.len) return error.TokenCountMismatch;
    for (host, idol) |h, d| {
        if (h.kind != d.kind) return error.TokenKindMismatch;
        if (h.loc.line != d.loc.line) return error.TokenLineMismatch;
        if (h.loc.col != d.loc.col) return error.TokenColMismatch;
        if (!std.mem.eql(u8, h.text, d.text)) return error.TokenTextMismatch;
        if (h.int_val != d.int_val) return error.TokenIntMismatch;
        if (h.int_class != d.int_class) return error.TokenIntClassMismatch;
        if (h.float_val != d.float_val) return error.TokenFloatMismatch;
    }
}

test "lexer_dispatch: record fields are producer positions" {
    try std.testing.expect(!@hasField(lexer.TokenKind, "string_lit"));
    try std.testing.expectEqual(
        @typeInfo(lexer.TokenKind).@"enum".field_values.len,
        token_kind_values.count(),
    );
    try std.testing.expect(!token_kind_values.isSet(3));
    try std.testing.expect(token_kind_values.isSet(@backingInt(lexer.TokenKind.eof)));
    const slots = recordslots();
    try std.testing.expect(slots > 0);
    const positions = [_]i64{
        fieldkind(), fieldline(), fieldcol(),   fieldint(),
        fieldoff(),  fieldlen(),  fieldfloat(), _fieldintclass(),
    };
    var seen: [16]bool = undefined;
    inline for (0..16) |j| seen[j] = false;
    for (positions) |pos| {
        try std.testing.expect(pos >= 0 and pos < slots);
        const i: usize = @intCast(pos);
        try std.testing.expect(!seen[i]);
        seen[i] = true;
    }
    try std.testing.expect(rejectioncount() > 0);
    const last = rejectioncode(rejectioncount());
    try std.testing.expectEqualStrings("InsufficientIndent", std.mem.span(rejectionname(last)));
    try std.testing.expectEqual(lexer.LexError.InsufficientIndent, rejectionNameToError(rejectionname(last)).?);
    try std.testing.expect(rejectionNameToError(rejectionname(-199)) == null);
}

test "lexer_dispatch: malformed generated records fail closed" {
    const a = std.testing.allocator;
    const source: [:0]const u8 = "";
    const file: [:0]const u8 = "record.id";
    var record = [_]i64{
        @backingInt(lexer.TokenKind.eof),
        1,
        1,
        0,
        0,
        0,
        0,
        0,
    };

    const valid = try decodeRecords(a, source, file, &record, 1);
    defer a.free(valid);
    try std.testing.expectEqual(lexer.TokenKind.eof, valid[0].kind);

    const kind_at: usize = @intCast(fieldkind());
    record[kind_at] = 3; // unpublished physical slot: not an enum identity
    try std.testing.expectError(DispatchError.InvalidTokenKind, decodeRecords(a, source, file, &record, 1));
    record[kind_at] = -1;
    try std.testing.expectError(DispatchError.InvalidTokenKind, decodeRecords(a, source, file, &record, 1));
    record[kind_at] = 256;
    try std.testing.expectError(DispatchError.InvalidTokenKind, decodeRecords(a, source, file, &record, 1));
    record[kind_at] = @backingInt(lexer.TokenKind.eof);

    const int_class_at: usize = @intCast(_fieldintclass());
    record[int_class_at] = 4;
    try std.testing.expectError(
        DispatchError.InvalidRecordCount,
        decodeRecords(a, source, file, &record, 1),
    );
    record[int_class_at] = 1;
    try std.testing.expectError(
        DispatchError.InvalidRecordCount,
        decodeRecords(a, source, file, &record, 1),
    );
    record[int_class_at] = 3;
    try std.testing.expectError(
        DispatchError.InvalidRecordCount,
        decodeRecords(a, source, file, &record, 1),
    );
    record[int_class_at] = 2;
    try std.testing.expectError(
        DispatchError.InvalidRecordCount,
        decodeRecords(a, source, file, &record, 1),
    );
    record[int_class_at] = 0;

    try std.testing.expectError(
        DispatchError.InvalidEndToken,
        decodeRecords(a, "x", file, &record, 1),
    );
    record[5] = 1;
    try std.testing.expectError(
        DispatchError.InvalidEndToken,
        decodeRecords(a, "x", file, &record, 1),
    );
    record[5] = 0;
    record[0] = @backingInt(lexer.TokenKind.name);
    try std.testing.expectError(
        DispatchError.InvalidEndToken,
        decodeRecords(a, source, file, &record, 1),
    );
    record[0] = @backingInt(lexer.TokenKind.eof);

    try std.testing.expectError(
        DispatchError.InvalidRecordCount,
        decodeRecords(a, source, file, &record, 0),
    );
    try std.testing.expectError(
        DispatchError.InvalidRecordCount,
        decodeRecords(a, source, file, &record, -1),
    );
    try std.testing.expectError(
        DispatchError.InvalidRecordCount,
        decodeRecords(a, source, file, &record, 2),
    );
    try std.testing.expectError(
        DispatchError.InvalidRecordCount,
        decodeRecords(a, source, file, &record, std.math.maxInt(i64)),
    );

    record[0] = std.math.maxInt(i64);
    try std.testing.expectError(
        DispatchError.InvalidTokenKind,
        decodeRecords(a, source, file, &record, 1),
    );
    record[0] = -1;
    try std.testing.expectError(
        DispatchError.InvalidTokenKind,
        decodeRecords(a, source, file, &record, 1),
    );
    record[0] = @backingInt(lexer.TokenKind.eof);

    record[1] = -1;
    try std.testing.expectError(
        DispatchError.InvalidTokenLocation,
        decodeRecords(a, source, file, &record, 1),
    );
    record[1] = 0;
    try std.testing.expectError(
        DispatchError.InvalidTokenLocation,
        decodeRecords(a, source, file, &record, 1),
    );
    record[1] = 1;
    record[2] = 0;
    try std.testing.expectError(
        DispatchError.InvalidTokenLocation,
        decodeRecords(a, source, file, &record, 1),
    );
    record[2] = std.math.maxInt(i64);
    try std.testing.expectError(
        DispatchError.InvalidTokenLocation,
        decodeRecords(a, source, file, &record, 1),
    );
    record[2] = 1;

    record[4] = 1;
    try std.testing.expectError(
        DispatchError.InvalidSourceSpan,
        decodeRecords(a, source, file, &record, 1),
    );
    record[4] = 0;
    record[5] = -1;
    try std.testing.expectError(
        DispatchError.InvalidSourceSpan,
        decodeRecords(a, source, file, &record, 1),
    );
    record[4] = -1;
    record[5] = 0;
    try std.testing.expectError(
        DispatchError.InvalidSourceSpan,
        decodeRecords(a, source, file, &record, 1),
    );
    record[4] = 0;
    record[5] = std.math.maxInt(i64);
    try std.testing.expectError(
        DispatchError.InvalidSourceSpan,
        decodeRecords(a, source, file, &record, 1),
    );

    var premature = [_]i64{
        @backingInt(lexer.TokenKind.eof), 1, 1, 0, 0, 0, 0, 0, 0, 0,
        @backingInt(lexer.TokenKind.eof), 1, 1, 0, 0, 0, 0, 0, 0, 0,
    };
    try std.testing.expectError(
        DispatchError.InvalidEndToken,
        decodeRecords(a, source, file, &premature, 2),
    );

    const last = rejectioncode(rejectioncount());
    try std.testing.expectEqual(
        lexer.LexError.InsufficientIndent,
        rejectionNameToError(rejectionname(last)).?,
    );
    try std.testing.expectEqual(
        DispatchError.InvalidRejectionCode,
        rejectionNameToError(rejectionname(-199)) orelse DispatchError.InvalidRejectionCode,
    );

    var double_eof = [_]i64{
        @backingInt(lexer.TokenKind.eof), 1, 1, 0, 0, 0, 0, 0, 0, 0,
        @backingInt(lexer.TokenKind.eof), 1, 1, 0, 0, 0, 0, 0, 0, 0,
    };
    try std.testing.expectError(
        DispatchError.InvalidEndToken,
        decodeRecords(a, source, file, &double_eof, 2),
    );
}

test "lexer_dispatch: production route rejects embedded NUL" {
    const a = std.testing.allocator;
    const source: []const u8 = "x\x00y";
    var lex = lexer.Lexer.init(source, "nul.id");

    try std.testing.expectError(
        DispatchError.EmbeddedNul,
        route(a, &lex, source, "nul.id"),
    );
    try std.testing.expect(!lex.isDuoBacked());
    try std.testing.expectEqual(@as(?lexer.Loc, null), lex.last_error_loc);

    var file_lex = lexer.Lexer.init("", "bad\x00file.id");
    try std.testing.expectError(
        DispatchError.EmbeddedNul,
        route(a, &file_lex, "", "bad\x00file.id"),
    );
    try std.testing.expect(!file_lex.isDuoBacked());
}

test "lexer_dispatch: backtick identity then canon parser stream refuses" {
    const a = std.testing.allocator;
    const src: []const u8 = "`\n";
    var scan = lexer.Lexer.initFamily(src, "t.id", lexer_bridge.family_canon);
    const bang = try scan.next_tok();
    try std.testing.expectEqual(lexer.TokenKind.backtick, bang.kind);
    try std.testing.expectError(
        lexer.LexError.UnexpectedChar,
        tokenize(a, "`\n", "t.id", lexer_bridge.family_canon),
    );
    var lex = lexer.Lexer.initFamily(src, "t.id", lexer_bridge.family_canon);
    try std.testing.expectError(lexer.LexError.UnexpectedChar, route(a, &lex, src, "t.id"));
}

test "lexer_dispatch: shebang identity then program" {
    const a = std.testing.allocator;
    const toks = try tokenize(a, "#!/usr/bin/env idol\n1\n", "t.id", lexer_bridge.family_canon);
    defer a.free(toks);
    try std.testing.expectEqual(lexer.TokenKind.shebang, toks[0].kind);
    try std.testing.expectEqualStrings("#!/usr/bin/env idol", toks[0].text);
    try std.testing.expectEqual(lexer.TokenKind.int_lit, toks[1].kind);
    try std.testing.expectEqual(@as(i64, 1), toks[1].int_val);
}

test "lexer_dispatch: long dash comment identity then program" {
    const a = std.testing.allocator;
    const toks = try tokenize(a, "--[[note]]\n1\n", "t.id", lexer_bridge.family_canon);
    defer a.free(toks);
    try std.testing.expectEqual(lexer.TokenKind.compat_long_comment, toks[0].kind);
    try std.testing.expectEqual(lexer.TokenKind.int_lit, toks[1].kind);
}

test "lexer_dispatch: dash comment identity then program" {
    const a = std.testing.allocator;
    const toks = try tokenize(a, "-- note\n1\n", "t.id", lexer_bridge.family_canon);
    defer a.free(toks);
    try std.testing.expectEqual(lexer.TokenKind.compat_comment, toks[0].kind);
    try std.testing.expectEqualStrings("-- note", toks[0].text);
    try std.testing.expectEqual(lexer.TokenKind.int_lit, toks[1].kind);
}

test "lexer_dispatch: comment identity then program" {
    const a = std.testing.allocator;
    const toks = try tokenize(a, "# note\n1\n", "t.id", lexer_bridge.family_canon);
    defer a.free(toks);
    try std.testing.expectEqual(lexer.TokenKind.comment, toks[0].kind);
    try std.testing.expectEqualStrings("# note", toks[0].text);
    try std.testing.expectEqual(lexer.TokenKind.int_lit, toks[1].kind);
    try std.testing.expectEqual(@as(i64, 1), toks[1].int_val);
}

test "lexer_dispatch: Idol lexer drives a host token stream" {
    const a = std.testing.allocator;
    const toks = try tokenize(a, "fun add(a: i64): i64 = a + 1 end", "t.id", lexer_bridge.family_canon);
    defer a.free(toks);
    try std.testing.expectEqual(@as(usize, 15), toks.len);
    try std.testing.expectEqual(lexer.TokenKind.kw_fun, toks[0].kind);
    try std.testing.expectEqualStrings("add", toks[1].text);
    try std.testing.expectEqual(@as(u32, 1), toks[0].loc.line);
}

test "lexer_dispatch: route publishes shebang and hides it from the parser pack" {
    const a = std.testing.allocator;
    const src: []const u8 = "#!/usr/bin/env idol\n# note\n1\n";
    var lex = lexer.Lexer.init(src, "t.id");
    try route(a, &lex, src, "t.id");
    const toks = lex.duo_tokens.?;
    defer a.free(toks);
    const first = try lex.next();
    try std.testing.expectEqualStrings("#!/usr/bin/env idol", lex.shebang);
    try std.testing.expectEqual(lexer.TokenKind.int_lit, first.kind);
    try std.testing.expectEqual(@as(i64, 1), first.int_val);
}

test "lexer_dispatch: production route fails closed on storage failure" {
    const src = "main: i64 = ()\n    0";
    // Sentinel copies fit on the stack; heap is records then tokens.
    for ([_]usize{ 0, 1 }) |fail_index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
            .fail_index = fail_index,
        });
        var lex = lexer.Lexer.init(src, "lexer.id");

        try std.testing.expectError(
            error.OutOfMemory,
            route(failing.allocator(), &lex, src, "lexer.id"),
        );
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        try std.testing.expect(!lex.isDuoBacked());
    }
}

test "lexer_dispatch: production route releases temporary source copies" {
    const a = std.testing.allocator;
    const src: []const u8 = "main: i64 = ()\n    0";
    const file: []const u8 = "lexer.id";
    var lex = lexer.Lexer.init(src, file);

    try route(a, &lex, src, file);
    const toks = lex.duo_tokens.?;
    defer a.free(toks);

    try std.testing.expectEqual(@intFromPtr(src.ptr), @intFromPtr(toks[0].text.ptr));
    try std.testing.expectEqual(@intFromPtr(file.ptr), @intFromPtr(toks[0].loc.file.ptr));
}

test "lexer_dispatch: long text publishes delimiter level" {
    const a = std.testing.allocator;
    const source: [:0]const u8 = "[[a]] [=[b]=]";
    const toks = try tokenize(a, source, "span.id", lexer_bridge.family_compat);
    defer a.free(toks);
    try std.testing.expectEqual(lexer.TokenKind.compat_long_text_lit, toks[0].kind);
    try std.testing.expectEqual(@as(i64, 0), toks[0].int_val);
    try std.testing.expectEqualStrings("a", toks[0].text);
    try std.testing.expectEqual(lexer.TokenKind.compat_long_text_lit, toks[1].kind);
    try std.testing.expectEqual(@as(i64, 1), toks[1].int_val);
    try std.testing.expectEqualStrings("b", toks[1].text);
}

test "lexer_dispatch: Idol owns exact token source spans" {
    const a = std.testing.allocator;
    const source: [:0]const u8 = "a a \"a\" [[a]]";
    const toks = try tokenize(a, source, "span.id", lexer_bridge.family_canon);
    defer a.free(toks);

    const base = @intFromPtr(source.ptr);
    const expected = [_]usize{ 0, 2, 5, 10, source.len };
    try std.testing.expectEqual(expected.len, toks.len);
    for (toks, expected) |tok, offset| {
        try std.testing.expectEqual(offset, @intFromPtr(tok.text.ptr) - base);
    }
}

test "lexer_dispatch: token streams agree field for field" {
    const a = std.testing.allocator;
    const cases = [_][:0]const u8{
        "",
        "fun add(a: i64): i64 = a + 1 end",
        "x = 1.5 y = 42 z = 0xFF",
        "s = \"a\\tb\\nc\"",
        "a<=b and c>=d or e~=f",
        "a = 1e3 b = 2.5e-2 c = 0.5",
    };
    for (cases) |case| try differential(a, case, "t.id", lexer_bridge.family_canon);
}

// The float case is the one that was silently wrong. Name it separately so a
// regression breaks a test that says WHY, rather than shifting a count.
test "lexer_dispatch: float literals carry their value" {
    const a = std.testing.allocator;
    const toks = try tokenize(a, "1.5", "t.id", lexer_bridge.family_canon);
    defer a.free(toks);
    try std.testing.expectEqual(lexer.TokenKind.float_lit, toks[0].kind);
    try std.testing.expectEqual(@as(f64, 1.5), toks[0].float_val);
}

// GAP-017's regression test. Before the fix these aborted the process, so the
// compiler could not be routed through this lexer at all: every malformed
// source would have become a bare abort with no location instead of a
// diagnostic. Each must now be a catchable error.
test "lexer_dispatch: malformed sources reject instead of aborting" {
    const a = std.testing.allocator;
    try std.testing.expectError(
        lexer.LexError.UnterminatedString,
        tokenize(a, "s = \"unterminated", "bad.duo", lexer_bridge.family_compat),
    );
    try std.testing.expectError(
        lexer.LexError.UnterminatedLongString,
        tokenize(a, "s = [[unterminated", "bad.id", lexer_bridge.family_canon),
    );
}

test "lexer_dispatch: a rejection carries its line" {
    try std.testing.expectEqual(@as(u32, 2), try errorLine("x = 1\ns = \"bad", "bad.duo", lexer_bridge.family_compat));
}

// GAP-023: do the shapes those proofs are built from — corpus data held as
// string literals, escapes included — tokenize identically? This compiles and
// runs (the first attempt used std.fs.cwd(), which this Zig version lacks, so it
// never built and its empty failure list read as a pass).
test "lexer_dispatch: corpus-data-as-literals tokenizes identically" {
    const a = std.testing.allocator;
    try differential(a, "corpus = { \"a == b ~= c\", \"-- line\\nfun\", \"\\\"hi\\\" 'there'\" }", "proof.id", lexer_bridge.family_canon);
    try differential(a, "h = 0 s = \"a\\tb\\nc\\\\d\" n = #s", "proof.duo", lexer_bridge.family_compat);
}

// gap[042]. GAP-024 fixed `_int_of`'s DECIMAL accumulator and left the HEX one
// as `i64`, so `v * 16` on a hex literal at or above 2^63 was signed overflow
// and the Idol lexer ABORTED THE PROCESS rather than returning a token.
//
// Nothing caught it because no differential case contained such a literal —
// lib/std does (`0xcbf29ce484222325` in heap.id, `0x8000000000000000` in
// encoding/varint.id and ml/gguf.id), but only the compile DRIVER routed
// through the Idol lexer and a driver never lexes the stdlib. It surfaced the
// moment codegen's module-embed paths were routed through the same lexer.
//
// These three are the literals actually in the tree, plus the boundary either
// side of it. Field-for-field, so a wrong VALUE fails as loudly as an abort.
test "lexer_dispatch: gap[042] — hex literals at and above 2^63" {
    const a = std.testing.allocator;
    const cases = [_][:0]const u8{
        "h = 0xcbf29ce484222325",
        "m = 0xFFFFFFFFFFFFFFFF",
        "s = 0x8000000000000000",
        "b = 0x7FFFFFFFFFFFFFFF",
        "x = 0xff y = 0x10 z = 0x0",
    };
    for (cases) |case| try differential(a, case, "hex.id", lexer_bridge.family_canon);
}

// The same literal, asserted by VALUE rather than by agreement, so a change
// that broke BOTH lexers identically would still fail here. 0xcbf29ce484222325
// is 14695981039346656037, which as an i64 bit pattern is -3750763034362895579.
test "lexer_dispatch: gap[042] — the FNV offset basis carries its bits" {
    const a = std.testing.allocator;
    const toks = try tokenize(a, "0xcbf29ce484222325", "hex.id", lexer_bridge.family_canon);
    defer a.free(toks);
    try std.testing.expectEqual(lexer.TokenKind.int_lit, toks[0].kind);
    try std.testing.expectEqual(@as(i64, -3750763034362895579), toks[0].int_val);
}

test "lexer_dispatch: decimal magnitude class is producer-owned and lossless" {
    const a = std.testing.allocator;
    const cases = [_][:0]const u8{
        "9223372036854775807",
        "9223372036854775808",
        "18446744073709551608",
        "18446744073709551615",
        "18446744073709551616",
        "0009223372036854775808",
    };
    for (cases) |case| try differential(a, case, "magnitude.id", lexer_bridge.family_canon);

    const fit = try tokenize(a, cases[0], "magnitude.id", lexer_bridge.family_canon);
    defer a.free(fit);
    try std.testing.expectEqual(std.math.maxInt(i64), fit[0].int_val);
    try std.testing.expectEqual(lexer.DecimalIntegerClass.ordinary, fit[0].int_class);

    const magnitude = try tokenize(a, cases[1], "magnitude.id", lexer_bridge.family_canon);
    defer a.free(magnitude);
    try std.testing.expectEqual(std.math.minInt(i64), magnitude[0].int_val);
    try std.testing.expectEqual(lexer.DecimalIntegerClass.min_magnitude, magnitude[0].int_class);

    const u64_bits = try tokenize(a, cases[2], "magnitude.id", lexer_bridge.family_canon);
    defer a.free(u64_bits);
    try std.testing.expectEqual(@as(i64, -8), u64_bits[0].int_val);
    try std.testing.expectEqual(lexer.DecimalIntegerClass.u64_bits, u64_bits[0].int_class);

    const wide = try tokenize(a, cases[4], "magnitude.id", lexer_bridge.family_canon);
    defer a.free(wide);
    try std.testing.expectEqual(@as(i64, 0), wide[0].int_val);
    try std.testing.expectEqual(lexer.DecimalIntegerClass.wider, wide[0].int_class);

    const leading = try tokenize(a, cases[5], "magnitude.id", lexer_bridge.family_canon);
    defer a.free(leading);
    try std.testing.expectEqual(lexer.DecimalIntegerClass.min_magnitude, leading[0].int_class);
}

test "lexer_dispatch: decimal class preserves contextual alias token spans" {
    const a = std.testing.allocator;
    const source: [:0]const u8 = "alias Point = { x: f64, y: f64 }";
    try differential(a, source, "alias.id", lexer_bridge.family_canon);
    const tokens = try tokenize(a, source, "alias.id", lexer_bridge.family_canon);
    defer a.free(tokens);
    const expected_kinds = [_]lexer.TokenKind{
        .kw_alias, .name,  .assign, .lbrace, .name,   .colon,
        .kw_f64,   .comma, .name,   .colon,  .kw_f64, .rbrace,
        .eof,
    };
    const expected_text = [_][]const u8{
        "alias", "Point", "=", "{", "x", ":", "f64", ",", "y", ":", "f64", "}", "",
    };
    const expected_offsets = [_]usize{ 0, 6, 12, 14, 16, 17, 19, 22, 24, 25, 27, 31, 32 };
    try std.testing.expectEqual(expected_kinds.len, tokens.len);
    for (tokens, expected_kinds, expected_text, expected_offsets) |token, kind, text, offset| {
        try std.testing.expectEqual(kind, token.kind);
        try std.testing.expectEqualStrings(text, token.text);
        try std.testing.expectEqual(offset, @intFromPtr(token.text.ptr) - @intFromPtr(source.ptr));
        try std.testing.expectEqual(text.len, token.text.len);
        try std.testing.expectEqual(lexer.DecimalIntegerClass.ordinary, token.int_class);
    }
}

test "lexer_dispatch: family is tokenize operand not suffix" {
    const a = std.testing.allocator;
    const src: [:0]const u8 = "x = 'a'";
    const crossed_lua: [:0]const u8 = "x.lua";
    const crossed_id: [:0]const u8 = "x.id";

    const canon = try tokenize(a, src, crossed_lua, lexer_bridge.family_canon);
    defer a.free(canon);
    try std.testing.expectEqual(lexer.TokenKind.bytes_lit, canon[2].kind);

    const compat = try tokenize(a, src, crossed_id, lexer_bridge.family_compat);
    defer a.free(compat);
    try std.testing.expectEqual(lexer.TokenKind.compat_text_lit, compat[2].kind);
}

test "lexer_dispatch: route consumes lex.family not path" {
    const a = std.testing.allocator;
    const src: []const u8 = "x = 'a'";
    var lex = lexer.Lexer.initFamily(src, "x.lua", lexer_bridge.family_canon);
    try route(a, &lex, src, "x.lua");
    defer a.free(lex.duo_tokens.?);
    try std.testing.expectEqual(lexer.TokenKind.bytes_lit, lex.duo_tokens.?[2].kind);
}

// GAP-024, found while probing GAP-023 and NOT its cause: the host lexer
// overflows on a u64 literal above i64 max, which is a value Idol's u64 can
// represent. This is a real divergence in its own right; it does NOT explain the
// two regressing proofs, whose u64 fingerprint appears only in a COMMENT.
//
// Left failing on purpose — it is the only thing that makes the divergence
// visible, and deleting it to keep a count green restores the blindness.
test "lexer_dispatch: GAP-024 — u64 literal above i64 max" {
    const a = std.testing.allocator;
    try differential(a, "fingerprint = 6061832201901611285", "u64.id", lexer_bridge.family_canon);
}
