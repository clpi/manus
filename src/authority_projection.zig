//! Checked compiler projection of `docs/spec/AUTHORITY.json`.
//!
//! This module owns no language law. `gate/authority.sh` derives the edition
//! from the exact authority inputs and refuses whenever these bytes disagree.
//! Compiler ingress, graph export, and evidence consume this typed projection
//! so `.id` alone never masquerades as an exact historical/current law epoch.
const std = @import("std");

pub const source_law_schema = "idol.source.law.v1";
pub const source_law_sha256 = "58d8eecc38988c70e1d9fa442f8003dbc6488f96c1df63bce48aef981a1bfd61";

pub const ExactSourceLaw = struct {
    family: []const u8,
    schema: []const u8,
    sha256: []const u8,
};

/// Exact source-law knowledge at ingress. A foreign source can be admitted
/// while its edition remains unknown; it must never inherit Idol's edition
/// merely because the same compiler parses it.
pub const SourceLawEdition = union(enum) {
    unknown,
    exact: ExactSourceLaw,
    foreign_unversioned,

    pub fn idolCurrent() SourceLawEdition {
        return .{ .exact = .{
            .family = "idol",
            .schema = source_law_schema,
            .sha256 = source_law_sha256,
        } };
    }

    pub fn eql(a: SourceLawEdition, b: SourceLawEdition) bool {
        return switch (a) {
            .unknown => b == .unknown,
            .foreign_unversioned => b == .foreign_unversioned,
            .exact => |left| switch (b) {
                .exact => |right| std.mem.eql(u8, left.family, right.family) and
                    std.mem.eql(u8, left.schema, right.schema) and
                    std.mem.eql(u8, left.sha256, right.sha256),
                else => false,
            },
        };
    }

    pub fn family(self: SourceLawEdition) ?[]const u8 {
        return switch (self) {
            .unknown => null,
            .exact => |edition| edition.family,
            .foreign_unversioned => "foreign",
        };
    }

    pub fn schema(self: SourceLawEdition) ?[]const u8 {
        return switch (self) {
            .exact => |edition| edition.schema,
            .unknown, .foreign_unversioned => null,
        };
    }

    pub fn sha256(self: SourceLawEdition) ?[]const u8 {
        return switch (self) {
            .exact => |edition| edition.sha256,
            .unknown, .foreign_unversioned => null,
        };
    }

    /// Reject malformed exact editions before they become graph knowledge.
    /// Current production ingress constructs only `idolCurrent` or
    /// `foreign_unversioned`; this also makes the future historical/imported
    /// ingress fail closed rather than accepting an arbitrary label as law.
    pub fn validate(self: SourceLawEdition) !void {
        const edition = switch (self) {
            .unknown, .foreign_unversioned => return,
            .exact => |edition| edition,
        };
        if (edition.family.len == 0 or edition.schema.len == 0 or edition.sha256.len != 64) {
            return error.InvalidSourceLawEdition;
        }
        for (edition.sha256) |byte| {
            if (!((byte >= '0' and byte <= '9') or (byte >= 'a' and byte <= 'f'))) {
                return error.InvalidSourceLawEdition;
            }
        }
    }
};

/// Artifact-query surface. The executable compiler contains and can report the
/// same edition graph export uses; scripts never scrape a source filename or
/// repository path to reconstruct it.
pub fn writeCurrentJson(writer: *std.Io.Writer) !void {
    try writer.print(
        "{{\"schema\":\"idol.authority.projection.v1\",\"source_law\":{{\"card\":\"one\",\"family\":\"idol\",\"schema\":\"{s}\",\"sha256\":\"{s}\"}}}}\n",
        .{ source_law_schema, source_law_sha256 },
    );
}

test "authority projection carries one full sha256 source-law edition" {
    try std.testing.expectEqual(@as(usize, 64), source_law_sha256.len);
    for (source_law_sha256) |byte| {
        try std.testing.expect((byte >= '0' and byte <= '9') or (byte >= 'a' and byte <= 'f'));
    }
    const current = SourceLawEdition.idolCurrent();
    try std.testing.expectEqualStrings("idol", current.family().?);
    try std.testing.expectEqualStrings(source_law_schema, current.schema().?);
    try std.testing.expect(current.eql(SourceLawEdition.idolCurrent()));
    try std.testing.expect(!current.eql(.foreign_unversioned));
    const foreign: SourceLawEdition = .foreign_unversioned;
    const unknown: SourceLawEdition = .unknown;
    try std.testing.expect(foreign.sha256() == null);
    try std.testing.expect(unknown.family() == null);
}

test "authority projection JSON distinguishes exact from unknown" {
    var storage: [512]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&storage);
    try writeCurrentJson(&writer);
    const bytes = writer.buffered();
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, bytes, .{});
    defer parsed.deinit();
    const source_law = parsed.value.object.get("source_law").?.object;
    try std.testing.expectEqualStrings("one", source_law.get("card").?.string);
    try std.testing.expectEqualStrings(source_law_sha256, source_law.get("sha256").?.string);
}

test "source-law edition rejects malformed exact identities" {
    try SourceLawEdition.idolCurrent().validate();
    try (SourceLawEdition{ .exact = .{
        .family = "idol",
        .schema = "idol.source.law.historical-test",
        .sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    } }).validate();
    try std.testing.expectError(error.InvalidSourceLawEdition, (SourceLawEdition{ .exact = .{
        .family = "",
        .schema = "idol.source.law.v1",
        .sha256 = source_law_sha256,
    } }).validate());
    try std.testing.expectError(error.InvalidSourceLawEdition, (SourceLawEdition{ .exact = .{
        .family = "idol",
        .schema = "",
        .sha256 = source_law_sha256,
    } }).validate());
    try std.testing.expectError(error.InvalidSourceLawEdition, (SourceLawEdition{ .exact = .{
        .family = "idol",
        .schema = "idol.source.law.v1",
        .sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcde",
    } }).validate());
    try std.testing.expectError(error.InvalidSourceLawEdition, (SourceLawEdition{ .exact = .{
        .family = "idol",
        .schema = "idol.source.law.v1",
        .sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0",
    } }).validate());
    try std.testing.expectError(error.InvalidSourceLawEdition, (SourceLawEdition{ .exact = .{
        .family = "idol",
        .schema = "idol.source.law.v1",
        .sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdeF",
    } }).validate());
    try std.testing.expectError(error.InvalidSourceLawEdition, (SourceLawEdition{ .exact = .{
        .family = "idol",
        .schema = "idol.source.law.v1",
        .sha256 = "g123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    } }).validate());
}
