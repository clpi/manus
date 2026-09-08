//! Exact decimal meaning: the value a decimal source spelling NAMES, owned once.
//!
//! `0.1` names one tenth. `f64` is a REALIZATION that cannot hold one tenth, so
//! ingesting through `parseFloat` destroys the fact before any consumer sees it.
//! This module is the fact producer (`law.fact.producer.one`); `toFloat` is the
//! projection to that realization, never the other way round.
//!
//! Every relation here is TOTAL and BOUNDED: it answers, or it declines with
//! `null`. It never traps and never iterates on a value-derived count.

const std = @import("std");

/// Beyond this the carrier declines rather than carry an exponent whose own
/// arithmetic it cannot check.
pub const exponent_limit: i32 = 1 << 30;

/// `units` is `u128`; 10^39 does not fit, so alignment past this is refused
/// before any multiply is attempted.
pub const shift_limit: u32 = 38;

pub const Decimal = struct {
    negative: bool = false,
    units: u128 = 0,
    exponent: i32 = 0,

    pub const zero: Decimal = .{};

    pub fn isZero(self: Decimal) bool {
        return self.units == 0;
    }

    pub fn neg(self: Decimal) Decimal {
        if (self.isZero()) return zero;
        return .{ .negative = !self.negative, .units = self.units, .exponent = self.exponent };
    }

    /// Two canonical decimals name the same value exactly when their three
    /// facts agree. `read` and every relation below return canonical form, so
    /// this is the whole of equality — no alignment, no tolerance, no loop.
    pub fn same(self: Decimal, other: Decimal) bool {
        return self.negative == other.negative and
            self.units == other.units and
            self.exponent == other.exponent;
    }

    pub fn toFloat(self: Decimal) f64 {
        if (self.isZero()) return 0.0;
        var buf: [64]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "{s}{d}e{d}", .{
            if (self.negative) "-" else "",
            self.units,
            self.exponent,
        }) catch return 0.0;
        return std.fmt.parseFloat(f64, text) catch 0.0;
    }

    /// The exact integer this names, or `null` when it names no integer or one
    /// no `i64` holds. `-9223372036854775808` is the reason `units` is unsigned
    /// and the sign is a separate fact: its magnitude is not an `i64`.
    pub fn toInt(self: Decimal) ?i64 {
        if (self.isZero()) return 0;
        var units = self.units;
        if (self.exponent < 0) {
            var drop = negateExponent(self.exponent) orelse return null;
            if (drop > shift_limit) return null;
            while (drop > 0) : (drop -= 1) {
                if (units % 10 != 0) return null;
                units /= 10;
            }
        } else if (self.exponent > 0) {
            const raise: u32 = @intCast(self.exponent);
            units = mulPow10(units, raise) orelse return null;
        }
        const ceiling: u128 = if (self.negative)
            @as(u128, 1) << 63
        else
            (@as(u128, 1) << 63) - 1;
        if (units > ceiling) return null;
        if (self.negative) {
            if (units == @as(u128, 1) << 63) return std.math.minInt(i64);
            return -@as(i64, @intCast(units));
        }
        return @as(i64, @intCast(units));
    }

    pub fn format(self: Decimal, writer: *std.io.Writer) std.io.Writer.Error!void {
        try writer.print("{s}{d}e{d}", .{
            if (self.negative) "-" else "",
            self.units,
            self.exponent,
        });
    }
};

fn negateExponent(exponent: i32) ?u32 {
    if (exponent >= 0) return 0;
    const widened: i64 = -@as(i64, exponent);
    if (widened > std.math.maxInt(u32)) return null;
    return @intCast(widened);
}

fn mulPow10(units: u128, raise: u32) ?u128 {
    if (raise > shift_limit) return null;
    var acc = units;
    var left = raise;
    while (left > 0) : (left -= 1) {
        const step = @mulWithOverflow(acc, @as(u128, 10));
        if (step[1] != 0) return null;
        acc = step[0];
    }
    return acc;
}

/// Zero is zero at every scale, so a zero coefficient answers BEFORE the
/// exponent band is consulted. `0.0e-2147483648` and `0e+2147483647` are the
/// two spellings that make an exponent-first carrier trap or spin; here they
/// are just zero.
fn settle(negative: bool, units: u128, exponent: i64) ?Decimal {
    if (units == 0) return Decimal.zero;
    var u = units;
    var e = exponent;
    while (u % 10 == 0 and e < exponent_limit) {
        u /= 10;
        e += 1;
    }
    if (e < -@as(i64, exponent_limit) or e > @as(i64, exponent_limit)) return null;
    return .{ .negative = negative, .units = u, .exponent = @intCast(e) };
}

/// Exponent digits are read into a SATURATING `i64`. `2147483648` is not an
/// `i32` and `0.0e-2147483648` subtracts a fraction count from it, so reading
/// into the carrier's own width is the trap; reading wide and range-checking at
/// the end is the answer.
const exponent_read_ceiling: i64 = @as(i64, 1) << 40;

pub fn fromInt(v: i64) Decimal {
    if (v == 0) return Decimal.zero;
    const magnitude: u128 = if (v < 0) @intCast(-@as(i128, v)) else @intCast(v);
    return settle(v < 0, magnitude, 0).?;
}

pub fn read(text: []const u8) ?Decimal {
    if (text.len == 0) return null;
    var i: usize = 0;
    var negative = false;
    if (text[i] == '+' or text[i] == '-') {
        negative = text[i] == '-';
        i += 1;
    }
    if (i + 1 < text.len and text[i] == '0' and (text[i + 1] == 'x' or text[i + 1] == 'X')) return null;

    var units: u128 = 0;
    var digits: u32 = 0;
    var seen = false;
    var fraction: i64 = 0;

    while (i < text.len and std.ascii.isDigit(text[i])) : (i += 1) {
        seen = true;
        units = appendDigit(units, text[i], &digits) orelse return null;
    }
    if (i < text.len and text[i] == '.') {
        i += 1;
        while (i < text.len and std.ascii.isDigit(text[i])) : (i += 1) {
            seen = true;
            units = appendDigit(units, text[i], &digits) orelse return null;
            fraction += 1;
        }
    }
    if (!seen) return null;

    var exponent: i64 = 0;
    if (i < text.len and (text[i] == 'e' or text[i] == 'E')) {
        i += 1;
        var exp_negative = false;
        if (i < text.len and (text[i] == '+' or text[i] == '-')) {
            exp_negative = text[i] == '-';
            i += 1;
        }
        var exp_seen = false;
        var magnitude: i64 = 0;
        while (i < text.len and std.ascii.isDigit(text[i])) : (i += 1) {
            exp_seen = true;
            if (magnitude < exponent_read_ceiling) {
                magnitude = magnitude * 10 + @as(i64, text[i] - '0');
            }
        }
        if (!exp_seen) return null;
        if (magnitude > exponent_read_ceiling) magnitude = exponent_read_ceiling;
        exponent = if (exp_negative) -magnitude else magnitude;
    }
    if (i != text.len) return null;

    return settle(negative, units, exponent - fraction);
}

fn appendDigit(units: u128, byte: u8, digits: *u32) ?u128 {
    if (units == 0 and byte == '0') return 0;
    if (digits.* >= shift_limit) return null;
    digits.* += 1;
    return units * 10 + @as(u128, byte - '0');
}

/// Alignment is refused before it is attempted when the gap exceeds what
/// `units` can hold, so no relation here iterates on an exponent difference.
fn align2(a: Decimal, b: Decimal) ?struct { a: u128, b: u128, exponent: i64 } {
    const low = @min(a.exponent, b.exponent);
    const gap_a: i64 = @as(i64, a.exponent) - low;
    const gap_b: i64 = @as(i64, b.exponent) - low;
    if (gap_a > shift_limit or gap_b > shift_limit) return null;
    const ua = mulPow10(a.units, @intCast(gap_a)) orelse return null;
    const ub = mulPow10(b.units, @intCast(gap_b)) orelse return null;
    return .{ .a = ua, .b = ub, .exponent = low };
}

pub fn add(a: Decimal, b: Decimal) ?Decimal {
    if (a.isZero()) return b;
    if (b.isZero()) return a;
    const parts = align2(a, b) orelse return null;
    if (a.negative == b.negative) {
        const sum = @addWithOverflow(parts.a, parts.b);
        if (sum[1] != 0) return null;
        return settle(a.negative, sum[0], parts.exponent);
    }
    if (parts.a >= parts.b) return settle(a.negative, parts.a - parts.b, parts.exponent);
    return settle(b.negative, parts.b - parts.a, parts.exponent);
}

pub fn sub(a: Decimal, b: Decimal) ?Decimal {
    return add(a, b.neg());
}

pub fn mul(a: Decimal, b: Decimal) ?Decimal {
    if (a.isZero() or b.isZero()) return Decimal.zero;
    const product = @mulWithOverflow(a.units, b.units);
    if (product[1] != 0) return null;
    return settle(a.negative != b.negative, product[0], @as(i64, a.exponent) + @as(i64, b.exponent));
}

const testing = std.testing;

test "decimal: the tenth a source spelling names survives ingestion" {
    const tenth = read("0.1").?;
    try testing.expect(tenth.same(.{ .negative = false, .units = 1, .exponent = -1 }));
    try testing.expect(read("0.10").?.same(tenth));
    try testing.expect(read("1e-1").?.same(tenth));
    try testing.expect(read("10e-2").?.same(tenth));
    try testing.expect(!read("0.2").?.same(tenth));
}

test "decimal: a small negative exponent is a value, not an absence" {
    const small = read("1e-19");
    try testing.expect(small != null);
    try testing.expectEqual(@as(u128, 1), small.?.units);
    try testing.expectEqual(@as(i32, -19), small.?.exponent);
    try testing.expect(!small.?.isZero());
    try testing.expect(!small.?.same(Decimal.zero));

    try testing.expect(read("1e-1").?.same(.{ .units = 1, .exponent = -1 }));
    try testing.expect(read("1e-38").?.same(.{ .units = 1, .exponent = -38 }));
    try testing.expect(read("0.0000000000000000001").?.same(small.?));
}

test "decimal: the integer floor is a magnitude with a sign, not a signed magnitude" {
    const floor_magnitude = read("9223372036854775808");
    try testing.expect(floor_magnitude != null);
    try testing.expectEqual(@as(u128, 9223372036854775808), floor_magnitude.?.units);
    try testing.expectEqual(@as(?i64, null), floor_magnitude.?.toInt());
    try testing.expectEqual(@as(?i64, std.math.minInt(i64)), floor_magnitude.?.neg().toInt());

    try testing.expectEqual(@as(?i64, std.math.maxInt(i64)), read("9223372036854775807").?.toInt());
    try testing.expectEqual(@as(?i64, null), read("9223372036854775809").?.neg().toInt());
    try testing.expectEqual(@as(?i64, -1), read("-1").?.toInt());
    try testing.expectEqual(@as(?i64, 0), read("-0").?.toInt());
}

test "decimal: a zero coefficient answers before the exponent band is consulted" {
    for ([_][]const u8{
        "0.0e-2147483648",
        "0e+2147483647",
        "0.0e-2147483647",
        "0e-99999999999999999999",
        "0.000e+99999999999999999999",
        "0.0",
        "0",
    }) |spelling| {
        const value = read(spelling);
        try testing.expect(value != null);
        try testing.expect(value.?.isZero());
        try testing.expect(value.?.same(Decimal.zero));
        try testing.expectEqual(@as(i32, 0), value.?.exponent);
        try testing.expectEqual(@as(f64, 0.0), value.?.toFloat());
    }
}

test "decimal: a nonzero coefficient outside the exponent band declines" {
    try testing.expectEqual(@as(?Decimal, null), read("1e-2147483648"));
    try testing.expectEqual(@as(?Decimal, null), read("1e+2147483647"));
    try testing.expectEqual(@as(?Decimal, null), read("1e99999999999999999999"));
    try testing.expect(read("1e1073741825") == null);
    try testing.expect(read("1e1073741824") != null);
}

test "decimal: ingestion refuses what it cannot carry exactly" {
    try testing.expectEqual(@as(?Decimal, null), read(""));
    try testing.expectEqual(@as(?Decimal, null), read("."));
    try testing.expectEqual(@as(?Decimal, null), read("1e"));
    try testing.expectEqual(@as(?Decimal, null), read("1e+"));
    try testing.expectEqual(@as(?Decimal, null), read("0x1f"));
    try testing.expectEqual(@as(?Decimal, null), read("0x1.8p3"));
    try testing.expectEqual(@as(?Decimal, null), read("1.0.0"));
    try testing.expectEqual(@as(?Decimal, null), read("1 "));
    try testing.expectEqual(@as(?Decimal, null), read("nan"));
    try testing.expectEqual(@as(?Decimal, null), read("123456789012345678901234567890123456789"));
    try testing.expect(read("12345678901234567890123456789012345678") != null);
}

test "decimal: the sum of two tenths is the value a third names" {
    const sum = add(read("0.1").?, read("0.2").?).?;
    try testing.expect(sum.same(read("0.3").?));
    try testing.expect(!sum.same(read("0.30000000000000004").?));
    try testing.expect(read("0.1").?.toFloat() + read("0.2").?.toFloat() != read("0.3").?.toFloat());

    try testing.expect(add(read("1").?, read("2").?).?.same(read("3").?));
    try testing.expect(add(read("0.1").?, read("-0.1").?).?.same(Decimal.zero));
    try testing.expect(sub(read("0.3").?, read("0.1").?).?.same(read("0.2").?));
    try testing.expect(mul(read("0.1").?, read("0.2").?).?.same(read("0.02").?));
    try testing.expect(add(read("1e-19").?, read("0").?).?.same(read("1e-19").?));
    try testing.expect(add(read("1e-30").?, read("1e-30").?).?.same(read("2e-30").?));
}

test "decimal: alignment declines a gap it cannot hold instead of spinning on it" {
    try testing.expectEqual(@as(?Decimal, null), add(read("1e1000000000").?, read("1e-1000000000").?));
    try testing.expectEqual(@as(?Decimal, null), add(read("1e40").?, read("1").?));
    try testing.expect(add(read("1e39").?, read("1").?) == null);
    try testing.expect(add(read("1e38").?, read("1").?) != null);
    try testing.expect(add(read("1e1000000000").?, read("0").?).?.same(read("1e1000000000").?));
    try testing.expectEqual(@as(?Decimal, null), mul(read("1e1000000000").?, read("1e1000000000").?));
    try testing.expect(mul(read("1e1000000000").?, read("0").?).?.isZero());
}

test "decimal: the float projection is the realization, and it is not the fact" {
    try testing.expectEqual(@as(f64, 0.1), read("0.1").?.toFloat());
    try testing.expectEqual(@as(f64, 0.3), read("0.3").?.toFloat());
    try testing.expectEqual(@as(f64, 1e-19), read("1e-19").?.toFloat());
    try testing.expectEqual(@as(f64, -1.5), read("1.5").?.neg().toFloat());
    try testing.expectEqual(
        @as(f64, @floatFromInt(std.math.minInt(i64))),
        read("9223372036854775808").?.neg().toFloat(),
    );
}

test "decimal: an integer names a decimal, in the same canonical form" {
    try testing.expect(fromInt(0).same(Decimal.zero));
    try testing.expect(fromInt(1).same(read("1").?));
    try testing.expect(fromInt(100).same(read("100").?));
    try testing.expect(fromInt(100).same(read("1e2").?));
    try testing.expect(fromInt(-100).same(read("-1e2").?));
    try testing.expect(fromInt(std.math.minInt(i64)).same(read("9223372036854775808").?.neg()));
    try testing.expectEqual(@as(?i64, std.math.minInt(i64)), fromInt(std.math.minInt(i64)).toInt());
    try testing.expectEqual(@as(?i64, std.math.maxInt(i64)), fromInt(std.math.maxInt(i64)).toInt());
}
