//! Physical bridge from the generated lexer artifact to the bootstrap host.
//! Lexer execution and legacy token records are owned upstream; canonical
//! lexical identity remains the GAP-145 frontier.
const std = @import("std");
const lexer = @import("lexer.zig");
const keyword_bridge = @import("keyword_bridge.zig");

/// Rebuilds bootstrap `Token` records from the generated lexer transport.
pub const dispatch = @import("lexer_dispatch.zig");

pub const CANONICAL_SOURCE_SUFFIX = ".id";

pub const SourceLaw = enum {
    idol,
    lua,
    unknown,
};

pub const SourceProvenance = enum {
    canonical,
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
        return .{ .law = .idol, .provenance = .canonical };
    }
    if (std.mem.endsWith(u8, path, ".lua")) {
        return .{ .law = .lua, .provenance = .foreign };
    }
    return .{ .law = .unknown, .provenance = .unknown };
}

pub fn isIdolSourcePath(path: []const u8) bool {
    return sourceFacts(path).law == .idol;
}

pub fn isLuaSourcePath(path: []const u8) bool {
    return sourceFacts(path).law == .lua;
}

pub const TokenizeAuthority = enum {
    host_zig,
    generated_native,
};

/// Physical routing state for the production compile driver.
pub fn tokenizeAuthority() TokenizeAuthority {
    return .generated_native;
}

/// Production keyword lookup through the generated Idol lexer projection.
pub fn lookupKeyword(text: []const u8) ?lexer.TokenKind {
    return keyword_bridge.lookupKeyword(text);
}

test "lexer bridge: production split" {
    try std.testing.expect(tokenizeAuthority() == .generated_native);
    try std.testing.expectEqual(lexer.TokenKind.kw_fun, lookupKeyword("fun").?);
    try std.testing.expectEqual(@as(?lexer.TokenKind, null), lookupKeyword("notkw"));
}

test "lexer bridge: suffix classifies canonical and foreign only" {
    const canonical = sourceFacts("compiler.id");
    try std.testing.expectEqual(SourceLaw.idol, canonical.law);
    try std.testing.expectEqual(SourceProvenance.canonical, canonical.provenance);
    const retired = sourceFacts("compiler.duo");
    try std.testing.expectEqual(SourceLaw.unknown, retired.law);
    try std.testing.expectEqual(SourceProvenance.unknown, retired.provenance);
    try std.testing.expectEqual(SourceLaw.lua, sourceFacts("compiler.lua").law);
    try std.testing.expectEqual(SourceLaw.unknown, sourceFacts("compiler.txt").law);
}

test "lexer bridge: the dispatch consumer is analyzed with the seam" {
    std.testing.refAllDecls(dispatch);
}
