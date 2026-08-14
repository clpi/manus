//! Physical bridge from the generated lexer artifact to the bootstrap host.
//! Lexer execution and legacy token records are owned upstream; canonical
//! lexical identity remains the GAP-145 frontier.
const std = @import("std");
const lexer = @import("lexer.zig");
const keyword_bridge = @import("keyword_bridge.zig");

pub const CANONICAL_SOURCE_SUFFIX = ".id";

/// Integer operand into production `tokenize()`. 1 = canonical Idol, 2 = compat.
/// Unknown retired suffixes are not a third law; they keep the historical
/// non-`.id` default until ingress classifies them.
pub const family_canon: i64 = 1;
pub const family_compat: i64 = 2;

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

/// Path discovery for CLI/file filters. Suffix is provenance, not tokenize
/// family (`law.family.one`). Remaining host ingress until an Idol source-family
/// fact exists.
pub fn discover(path: []const u8) SourceLaw {
    if (std.mem.endsWith(u8, path, CANONICAL_SOURCE_SUFFIX)) return .idol;
    if (std.mem.endsWith(u8, path, ".lua")) return .lua;
    return .unknown;
}

pub fn provenanceOf(path: []const u8) SourceProvenance {
    return switch (discover(path)) {
        .idol => .canonical,
        .lua => .foreign,
        .unknown => .unknown,
    };
}

/// Family producer (`law.family.one`). Law is an operand; path supplies
/// provenance only and must not change the admitted law.
pub fn admit(law: SourceLaw, path: []const u8) SourceFacts {
    return .{ .law = law, .provenance = provenanceOf(path) };
}

const HomeClass = enum { canonical, generated, compatibility, foreign, negative };

/// Bridge projection of `docs/spec/corpus.md` machine rules (`law.bridge.death`).
/// Corpus.md remains the admission owner; this table is not a second suffix helper.
const homes = [_]struct { class: HomeClass, pattern: []const u8 }{
    .{ .class = .negative, .pattern = "examples/compile_fail/" },
    .{ .class = .negative, .pattern = "examples/native_differential/unsupported/" },
    .{ .class = .negative, .pattern = "error_test.id" },
    .{ .class = .foreign, .pattern = "examples/native_differential/" },
    .{ .class = .negative, .pattern = "fixtures/highlight/mixed/" },
    .{ .class = .foreign, .pattern = "fixtures/highlight/surface/" },
    .{ .class = .canonical, .pattern = "fixtures/highlight/" },
    .{ .class = .generated, .pattern = "lib/token/classify.id" },
    .{ .class = .generated, .pattern = "lib/wasm/opcode_lookup.id" },
    .{ .class = .generated, .pattern = "lib/wasm/ward_mvp_opcodes.id" },
    .{ .class = .foreign, .pattern = "examples/wasm/" },
    .{ .class = .compatibility, .pattern = "examples/lua" },
    .{ .class = .compatibility, .pattern = "examples/test_lua" },
    .{ .class = .canonical, .pattern = "examples/json/" },
    .{ .class = .canonical, .pattern = "examples/conversion/" },
    .{ .class = .canonical, .pattern = "examples/projection/" },
    .{ .class = .canonical, .pattern = "examples/infer/" },
    .{ .class = .canonical, .pattern = "examples/demand/" },
    .{ .class = .canonical, .pattern = "examples/hash/" },
    .{ .class = .canonical, .pattern = "examples/native/" },
    .{ .class = .canonical, .pattern = "examples/control/" },
    .{ .class = .canonical, .pattern = "examples/nominal/" },
    .{ .class = .canonical, .pattern = "examples/layout/" },
    .{ .class = .canonical, .pattern = "examples/pack/" },
    .{ .class = .canonical, .pattern = "examples/anchor/" },
    .{ .class = .canonical, .pattern = "examples/case/" },
    .{ .class = .canonical, .pattern = "examples/read/" },
    .{ .class = .canonical, .pattern = "examples/boring/" },
    .{ .class = .canonical, .pattern = "examples/table/" },
    .{ .class = .compatibility, .pattern = "examples/luahost/" },
    .{ .class = .foreign, .pattern = "examples/parity/" },
    .{ .class = .foreign, .pattern = "examples/host/" },
    .{ .class = .foreign, .pattern = "examples/world/" },
    .{ .class = .foreign, .pattern = "examples/tailslot/" },
    .{ .class = .foreign, .pattern = "examples/shc/" },
    .{ .class = .foreign, .pattern = "examples/cfloor/" },
    .{ .class = .foreign, .pattern = "examples/benchmark.id" },
    .{ .class = .foreign, .pattern = "examples/mandelbrot.id" },
    .{ .class = .foreign, .pattern = "vendor/" },
    .{ .class = .foreign, .pattern = "test.id" },
    .{ .class = .foreign, .pattern = "test2.id" },
    .{ .class = .foreign, .pattern = "examples/" },
};

/// Corpus home admission. Longest prefix wins. Compatibility homes are lua
/// law; other listed homes are Idol law. Unlisted paths do not reconstruct
/// family here.
fn homeFacts(path: []const u8) ?SourceFacts {
    var best_len: usize = 0;
    var best: ?HomeClass = null;
    for (homes) |home| {
        if (!pathMatches(path, home.pattern)) continue;
        if (home.pattern.len >= best_len) {
            best_len = home.pattern.len;
            best = home.class;
        }
    }
    const class = best orelse return null;
    return switch (class) {
        .canonical, .generated, .negative => .{ .law = .idol, .provenance = .canonical },
        .compatibility => .{ .law = .lua, .provenance = .foreign },
        // Foreign homes mix Idol `.id` and Lua fixtures. Layout admits the
        // home; discovery supplies only which law that file was handed as.
        .foreign => switch (discover(path)) {
            .lua => .{ .law = .lua, .provenance = .foreign },
            .idol, .unknown => .{ .law = .idol, .provenance = .foreign },
        },
    };
}

fn pathMatches(path: []const u8, pattern: []const u8) bool {
    if (std.mem.eql(u8, path, pattern)) return true;
    if (std.mem.startsWith(u8, path, pattern)) {
        if (pattern[pattern.len - 1] == '/') return true;
        if (path.len > pattern.len and path[pattern.len] == '/') return true;
    }
    if (path.len > pattern.len and path[path.len - pattern.len - 1] == '/' and
        std.mem.endsWith(u8, path, pattern))
        return true;
    return false;
}

/// Corpus home first. Suffix `discover` is only the unlisted-path fallback
/// (`law.bridge.death`). Later stages consume facts / `lex.family`.
pub fn sourceFacts(path: []const u8) SourceFacts {
    if (homeFacts(path)) |facts| return facts;
    return admit(discover(path), path);
}

pub fn familyCode(facts: SourceFacts) i64 {
    return switch (facts.law) {
        .idol => family_canon,
        .lua, .unknown => family_compat,
    };
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

test "lexer bridge: admit law is the operand" {
    const canonical = admit(.idol, "compiler.id");
    try std.testing.expectEqual(SourceLaw.idol, canonical.law);
    try std.testing.expectEqual(SourceProvenance.canonical, canonical.provenance);
    try std.testing.expectEqual(family_canon, familyCode(canonical));
    const lua = admit(.lua, "compiler.lua");
    try std.testing.expectEqual(SourceLaw.lua, lua.law);
    try std.testing.expectEqual(family_compat, familyCode(lua));
}

test "lexer bridge: discover is path provenance not family authority" {
    try std.testing.expectEqual(SourceLaw.idol, discover("compiler.id"));
    try std.testing.expectEqual(SourceLaw.lua, discover("compiler.lua"));
    try std.testing.expectEqual(SourceLaw.unknown, discover("compiler.duo"));
    try std.testing.expectEqual(SourceLaw.unknown, discover("compiler.txt"));
}

test "lexer bridge: admit law is not path-derived" {
    const facts = admit(.idol, "compiler.lua");
    try std.testing.expectEqual(SourceLaw.idol, facts.law);
    try std.testing.expectEqual(SourceProvenance.foreign, facts.provenance);
    try std.testing.expectEqual(family_canon, familyCode(facts));
}

test "lexer bridge: corpus home admits family not suffix" {
    const lua_home = sourceFacts("examples/lua/host.id");
    try std.testing.expectEqual(SourceLaw.lua, lua_home.law);
    try std.testing.expectEqual(SourceProvenance.foreign, lua_home.provenance);
    try std.testing.expectEqual(family_compat, familyCode(lua_home));
    const json_home = sourceFacts("examples/json/pack.id");
    try std.testing.expectEqual(SourceLaw.idol, json_home.law);
    try std.testing.expectEqual(SourceProvenance.canonical, json_home.provenance);
    try std.testing.expectEqual(family_canon, familyCode(json_home));
    const foreign_lua = sourceFacts("examples/hello.lua");
    try std.testing.expectEqual(SourceLaw.lua, foreign_lua.law);
    try std.testing.expectEqual(SourceProvenance.foreign, foreign_lua.provenance);
    const foreign_id = sourceFacts("examples/shc/path.id");
    try std.testing.expectEqual(SourceLaw.idol, foreign_id.law);
    try std.testing.expectEqual(SourceProvenance.foreign, foreign_id.provenance);
}
