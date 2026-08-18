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

/// One physical source form projected from the existing source-law ingress.
/// This is deliberately not another language enum or resolver-owned suffix
/// roster: `SourceLaw` remains the identity, and every physical discovery
/// consumer walks this one projection.
pub const SourceForm = struct {
    law: SourceLaw,
    suffix: []const u8,
    canonical: bool,
};

pub const SourceFormIterator = struct {
    next_index: i64 = 1,
    count: i64,

    pub fn next(self: *SourceFormIterator) ?SourceForm {
        while (self.next_index <= self.count) {
            const index = self.next_index;
            self.next_index += 1;
            const law = sourceLawFromName(sourceformlaw(index)) orelse continue;
            const suffix = std.mem.span(sourceformsuffix(index));
            if (suffix.len == 0) continue;
            return .{ .law = law, .suffix = suffix, .canonical = sourceformcanonical(index) };
        }
        return null;
    }
};

/// Executed producer schema. Names bind to the temporary host enum once at the
/// bootstrap boundary exactly like token identities in `lexer_dispatch`.
extern fn sourceformcount() i64;
extern fn sourceformlaw(i: i64) [*:0]const u8;
extern fn sourceformsuffix(i: i64) [*:0]const u8;
extern fn sourceformcanonical(i: i64) bool;
extern fn sourceentrycount() i64;
extern fn sourceentryrole(i: i64) [*:0]const u8;
extern fn sourceentrypattern(i: i64) [*:0]const u8;
extern fn sourcepathrole(path: [*:0]const u8) [*:0]const u8;
extern fn sourcefactlaw(path: [*:0]const u8, role: [*:0]const u8) [*:0]const u8;
extern fn sourcefactprovenance(path: [*:0]const u8, role: [*:0]const u8) [*:0]const u8;

fn sourceLawFromName(name: [*:0]const u8) ?SourceLaw {
    return std.meta.stringToEnum(SourceLaw, std.mem.span(name));
}

fn sourceProvenanceFromName(name: [*:0]const u8) ?SourceProvenance {
    return std.meta.stringToEnum(SourceProvenance, std.mem.span(name));
}

pub fn sourceForms() SourceFormIterator {
    const count = sourceformcount();
    return .{ .count = if (count > 0 and count <= 64) count else 0 };
}

/// Physical anchor for the repo-relative provenance spelling consumed by the
/// executed source producer. This file contains no admission roster; it merely
/// identifies the source tree, like a filesystem witness. Law/provenance come
/// only from `sourcefact*()`.
const CORPUS_RULES = "docs/spec/corpus.md";

/// The spelling the corpus rules are written in: the file's real location,
/// relative to the root of the tree that carries `CORPUS_RULES`.
///
/// WHY THIS EXISTS. The executed producer compares the characters it was handed. Handed
/// `examples/compile_fail/x.lua` it found the negative home; handed
/// `./examples/compile_fail/x.lua`, the absolute path, or the bare name from a
/// cwd inside that directory, it found nothing and the former host classifier
/// fell through to suffix discovery — a DIFFERENT policy for the same bytes, silently
/// substituted. Measured on `examples/compile_fail/implicit_global_read.lua`:
/// one spelling checked clean, three refused `use of undeclared global 'x'`.
/// That is the shape `law.fallback.zero` forbids — the owner is uncertain, the
/// old fallback answers, and execution continues as if it had been asked.
///
/// Resolution, not string surgery, because the bare-name spelling carries no
/// directory at all and a symlink carries the wrong one. Identity of the FILE
/// is the only thing all four spellings share.
///
/// Returns null at the two boundaries where the physical tree genuinely has nothing to
/// say: the path does not resolve to anything on disk, or no ancestor of it
/// carries the rules. Those are the owner REPORTING an unsupported boundary,
/// which is the one fallback shape `law.fallback.zero` admits.
fn corpusRelative(path: []const u8, out: []u8) ?[]const u8 {
    var in_z: [std.fs.max_path_bytes]u8 = undefined;
    if (path.len == 0 or path.len >= in_z.len) return null;
    @memcpy(in_z[0..path.len], path);
    in_z[path.len] = 0;

    var real_buf: [std.fs.max_path_bytes]u8 = undefined;
    const resolved = std.c.realpath(in_z[0..path.len :0].ptr, &real_buf) orelse return null;
    const real = std.mem.sliceTo(resolved, 0);

    var probe: [std.fs.max_path_bytes]u8 = undefined;
    var dir = std.fs.path.dirname(real) orelse return null;
    while (true) {
        const need = dir.len + 1 + CORPUS_RULES.len;
        if (need + 1 > probe.len) return null;
        @memcpy(probe[0..dir.len], dir);
        probe[dir.len] = '/';
        @memcpy(probe[dir.len + 1 ..][0..CORPUS_RULES.len], CORPUS_RULES);
        probe[need] = 0;
        if (std.c.access(probe[0..need :0].ptr, 0) == 0) {
            // `dirname` of a top-level entry is "/", which carries no separator
            // to step over. Getting this wrong eats the first byte of the name.
            const cut = if (dir.len == 1 and dir[0] == '/') dir.len else dir.len + 1;
            if (real.len <= cut) return null;
            const rel = real[cut..];
            if (rel.len > out.len) return null;
            @memcpy(out[0..rel.len], rel);
            return out[0..rel.len];
        }
        const parent = std.fs.path.dirname(dir) orelse return null;
        if (parent.len == dir.len) return null;
        dir = parent;
    }
}

fn producerPath(path: []const u8, out: []u8) ?[*:0]const u8 {
    if (path.len >= out.len) return null;
    @memcpy(out[0..path.len], path);
    out[path.len] = 0;
    return out[0..path.len :0].ptr;
}

/// Normalize physical provenance once, then ask the executed Idol producer for
/// law and provenance. Zig owns no corpus roster, role→law mapping, or suffix
/// fallback. Later stages consume this returned fact / `lex.family`; they never
/// inspect the path again to select source meaning.
pub fn sourceFacts(path: []const u8) SourceFacts {
    var rel_buf: [std.fs.max_path_bytes]u8 = undefined;
    const canon = corpusRelative(path, &rel_buf) orelse path;
    var producer_buf: [std.fs.max_path_bytes]u8 = undefined;
    const producer_path = producerPath(canon, &producer_buf) orelse return .{ .law = .unknown, .provenance = .unknown };
    const role = sourcepathrole(producer_path);
    const law = sourceLawFromName(sourcefactlaw(producer_path, role)) orelse return .{ .law = .unknown, .provenance = .unknown };
    const provenance = sourceProvenanceFromName(sourcefactprovenance(producer_path, role)) orelse return .{ .law = .unknown, .provenance = .unknown };
    return .{ .law = law, .provenance = provenance };
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

test "lexer bridge: executed ingress produces unlisted law and provenance" {
    const canonical = sourceFacts("compiler.id");
    try std.testing.expectEqual(SourceLaw.idol, canonical.law);
    try std.testing.expectEqual(SourceProvenance.canonical, canonical.provenance);
    try std.testing.expectEqual(family_canon, familyCode(canonical));
    const lua = sourceFacts("compiler.lua");
    try std.testing.expectEqual(SourceLaw.lua, lua.law);
    try std.testing.expectEqual(SourceProvenance.foreign, lua.provenance);
    try std.testing.expectEqual(family_compat, familyCode(lua));
    try std.testing.expectEqual(SourceLaw.unknown, sourceFacts("compiler.duo").law);
    try std.testing.expectEqual(SourceProvenance.unknown, sourceFacts("compiler.txt").provenance);
}

test "lexer bridge: one source-law producer owns physical form order" {
    try std.testing.expectEqual(@as(i64, 2), sourceformcount());
    try std.testing.expectEqualStrings("", std.mem.span(sourceformlaw(0)));
    try std.testing.expectEqualStrings("", std.mem.span(sourceformsuffix(3)));
    var forms = sourceForms();
    const idol = forms.next().?;
    try std.testing.expectEqual(SourceLaw.idol, idol.law);
    try std.testing.expectEqualStrings(CANONICAL_SOURCE_SUFFIX, idol.suffix);
    try std.testing.expect(idol.canonical);
    const lua = forms.next().?;
    try std.testing.expectEqual(SourceLaw.lua, lua.law);
    try std.testing.expectEqualStrings(".lua", lua.suffix);
    try std.testing.expect(!lua.canonical);
    try std.testing.expectEqual(SourceLaw.unknown, sourceFacts("compiler.txt").law);
    try std.testing.expect(forms.next() == null);
    try std.testing.expect(sourceLawFromName("bash") == null);
}

test "lexer bridge: corpus document is only a checked producer projection" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        CORPUS_RULES,
        std.testing.allocator,
        .unlimited,
    );
    defer std.testing.allocator.free(bytes);

    const opening = "```text\n";
    const start = (std.mem.indexOf(u8, bytes, opening) orelse return error.CorpusProjectionMissing) + opening.len;
    const rest = bytes[start..];
    const end = std.mem.indexOf(u8, rest, "```") orelse return error.CorpusProjectionUnterminated;
    var lines = std.mem.splitScalar(u8, rest[0..end], '\n');
    var index: i64 = 1;
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t\r");
        const role = fields.next() orelse continue;
        const pattern = fields.next() orelse return error.CorpusProjectionMalformed;
        try std.testing.expect(fields.next() == null);
        try std.testing.expect(index <= sourceentrycount());
        try std.testing.expectEqualStrings(std.mem.span(sourceentryrole(index)), role);
        try std.testing.expectEqualStrings(std.mem.span(sourceentrypattern(index)), pattern);
        index += 1;
    }
    try std.testing.expectEqual(sourceentrycount() + 1, index);
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

    const generated = sourceFacts("lib/token/classify.id");
    try std.testing.expectEqual(SourceLaw.idol, generated.law);
    try std.testing.expectEqual(SourceProvenance.canonical, generated.provenance);

    const foreign_unknown = sourceFacts("vendor/opaque.bin");
    try std.testing.expectEqual(SourceLaw.idol, foreign_unknown.law);
    try std.testing.expectEqual(SourceProvenance.foreign, foreign_unknown.provenance);

    const negative_unknown = sourceFacts("examples/compile_fail/opaque.bin");
    try std.testing.expectEqual(SourceLaw.idol, negative_unknown.law);
    try std.testing.expectEqual(SourceProvenance.canonical, negative_unknown.provenance);

    const exact_foreign = sourceFacts("test.id");
    try std.testing.expectEqual(SourceLaw.idol, exact_foreign.law);
    try std.testing.expectEqual(SourceProvenance.foreign, exact_foreign.provenance);
}

test "lexer bridge: a negative home is a corpus role, not a language" {
    // `negative examples/compile_fail/` in corpus.md states a ROLE — every file
    // here must be refused for its own reason. It does not say the files are
    // written in Idol, and eleven of them are the `.lua` twins that must still
    // COMPILE. Promoting those to Idol law by directory killed the positive
    // control `sema.zig` names in `check_infix_at`.
    const twin = sourceFacts("examples/compile_fail/anchor_infix_at.lua");
    try std.testing.expectEqual(SourceLaw.lua, twin.law);
    try std.testing.expectEqual(SourceProvenance.foreign, twin.provenance);
    try std.testing.expectEqual(family_compat, familyCode(twin));

    const row = sourceFacts("examples/compile_fail/anchor_infix_at.id");
    try std.testing.expectEqual(SourceLaw.idol, row.law);
    try std.testing.expectEqual(SourceProvenance.canonical, row.provenance);
    try std.testing.expectEqual(family_canon, familyCode(row));
}

test "lexer bridge: one file, one law, however the path is spelled" {
    // `examples/luahost/lc0.id` is the sharpest witness in the tree: a
    // COMPATIBILITY home holding an `.id` file, so the home says lua law and
    // the suffix says idol law. Before this ingress normalized the spelling,
    // `examples/luahost/lc0.id` was lua and `./examples/luahost/lc0.id` was
    // idol — the same bytes under two languages, chosen by two characters.
    //
    // The test SKIPS rather than passes when the file cannot be resolved from
    // the current directory: every spelling would then take the same
    // raw-path fallback and agree for the wrong reason. An assertion that
    // cannot fail is the shape this whole repair is about.
    const rel = "examples/luahost/lc0.id";
    var probe: [std.fs.max_path_bytes]u8 = undefined;
    const anchored = corpusRelative(rel, &probe) orelse return error.SkipZigTest;
    if (!std.mem.eql(u8, anchored, rel)) return error.SkipZigTest;

    const want = sourceFacts(rel);
    try std.testing.expectEqual(SourceLaw.lua, want.law);
    try std.testing.expectEqual(SourceProvenance.foreign, want.provenance);

    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    _ = std.c.getcwd(&cwd_buf, cwd_buf.len) orelse return error.SkipZigTest;
    const cwd = std.mem.sliceTo(&cwd_buf, 0);
    var abs_buf: [std.fs.max_path_bytes]u8 = undefined;
    const abs = try std.fmt.bufPrint(&abs_buf, "{s}/{s}", .{ cwd, rel });

    const spellings = [_][]const u8{
        "./examples/luahost/lc0.id",
        "examples/./luahost/lc0.id",
        "examples/luahost/../luahost/lc0.id",
        "./examples/../examples/luahost/lc0.id",
        abs,
    };
    for (spellings) |s| {
        const got = sourceFacts(s);
        try std.testing.expectEqual(want.law, got.law);
        try std.testing.expectEqual(want.provenance, got.provenance);
        try std.testing.expectEqual(familyCode(want), familyCode(got));
    }
}

test "lexer bridge: an unresolvable path still reaches its unlisted fallback" {
    // The two boundaries `corpusRelative` reports rather than guesses. Nothing
    // named here exists on disk, so resolution fails and the raw path is used —
    // which must still produce the documented `discover` answer and never a
    // crash or an `unknown`.
    const gone = sourceFacts("no/such/place/absent.lua");
    try std.testing.expectEqual(SourceLaw.lua, gone.law);
    try std.testing.expectEqual(SourceProvenance.foreign, gone.provenance);
    const gone_id = sourceFacts("no/such/place/absent.id");
    try std.testing.expectEqual(SourceLaw.idol, gone_id.law);
    try std.testing.expectEqual(SourceLaw.unknown, sourceFacts("no/such/place/absent.txt").law);
    try std.testing.expectEqual(SourceLaw.unknown, sourceFacts("").law);
}
