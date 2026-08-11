//! Physical bridge from the generated lexer artifact to the bootstrap host.
//! Lexer execution and legacy token records are owned upstream; canonical
//! lexical identity remains the GAP-145 frontier.
const std = @import("std");
const lexer = @import("lexer.zig");
const duo_keyword_bridge = @import("duo_keyword_bridge.zig");

/// Rebuilds bootstrap `Token` records from the generated lexer transport.
pub const dispatch = @import("duo_lexer_dispatch.zig");

pub const CANONICAL_SOURCE_SUFFIX = ".id";
pub const HISTORICAL_SOURCE_SUFFIX = ".duo";

pub const SourceLaw = enum {
    idsem,
    lua,
    unknown,
};

pub const SourceProvenance = enum {
    canonical,
    historical,
    foreign,
    unknown,
};

pub const SourceFacts = struct {
    law: SourceLaw,
    provenance: SourceProvenance,
};

/// Temporary suffix-only ingress classification. It cannot identify complete
/// compatibility lawsets and is not source-family authority. GAP-145's explicit
/// lawset transport is a prerequisite to deleting this projection. Later stages
/// must not use the path as semantic identity.
pub fn sourceFacts(path: []const u8) SourceFacts {
    if (std.mem.endsWith(u8, path, CANONICAL_SOURCE_SUFFIX)) {
        return .{ .law = .idsem, .provenance = .canonical };
    }
    if (std.mem.endsWith(u8, path, HISTORICAL_SOURCE_SUFFIX)) {
        return .{ .law = .idsem, .provenance = .historical };
    }
    if (std.mem.endsWith(u8, path, ".lua")) {
        return .{ .law = .lua, .provenance = .foreign };
    }
    return .{ .law = .unknown, .provenance = .unknown };
}

pub fn isIdsemSourcePath(path: []const u8) bool {
    return sourceFacts(path).law == .idsem;
}

pub fn isLuaSourcePath(path: []const u8) bool {
    return sourceFacts(path).law == .lua;
}

pub const TokenizeAuthority = enum {
    host_zig,
    duo_native,
};

/// Physical routing state for the production compile driver. The historical
/// enum tag is a bootstrap label, not language identity or authority.
pub fn tokenizeAuthority() TokenizeAuthority {
    return .duo_native;
}

/// Production keyword lookup through the generated Idsem projection.
pub fn lookupKeyword(text: []const u8) ?lexer.TokenKind {
    return duo_keyword_bridge.lookupKeyword(text);
}

test "lexer bridge: production split" {
    try std.testing.expect(tokenizeAuthority() == .duo_native);
    try std.testing.expectEqual(lexer.TokenKind.kw_fun, lookupKeyword("fun").?);
    try std.testing.expectEqual(@as(?lexer.TokenKind, null), lookupKeyword("notkw"));
}

test "lexer bridge: suffix changes provenance not language law" {
    const canonical = sourceFacts("compiler.id");
    const historical = sourceFacts("compiler.duo");
    try std.testing.expectEqual(SourceLaw.idsem, canonical.law);
    try std.testing.expectEqual(SourceLaw.idsem, historical.law);
    try std.testing.expectEqual(SourceProvenance.canonical, canonical.provenance);
    try std.testing.expectEqual(SourceProvenance.historical, historical.provenance);
    try std.testing.expectEqual(SourceLaw.lua, sourceFacts("compiler.lua").law);
    try std.testing.expectEqual(SourceLaw.unknown, sourceFacts("compiler.txt").law);
}

test "lexer bridge: the dispatch consumer is analyzed with the seam" {
    std.testing.refAllDecls(dispatch);
}
