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

/// Corpus home admission. Longest prefix wins, over a path already resolved to
/// the spelling corpus.md is written in (see `corpusRelative`). Compatibility
/// homes are lua law; canonical and generated homes are Idol law; MIXED homes —
/// `.foreign` and `.negative` — state a role and take law from the suffix.
/// Unlisted paths do not reconstruct family here.
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
        .canonical, .generated => .{ .law = .idol, .provenance = .canonical },
        .compatibility => .{ .law = .lua, .provenance = .foreign },
        // A NEGATIVE home is a corpus ROLE — "every file here must be refused
        // for its own stated reason" — and corpus.md states the role only. It
        // says nothing about which language the files are written in, and
        // `examples/compile_fail/` holds both `.id` rows and `.lua`. The `.lua`
        // half is the TWIN corpus: byte-identical files that must still
        // COMPILE, because that pair is the only thing that can tell "Idol
        // refuses it" apart from "the compiler lost the construct". Handing
        // them Idol law because of the DIRECTORY is the bridge answering a
        // question corpus.md never asked, and it killed the twin it was meant
        // to protect: `sema.zig`'s `check_infix_at` guards on `idol_mode` and
        // names `anchor_infix_at.lua` as "the positive control that fails if
        // that guard is ever dropped" — the guard was never dropped, the file
        // was carried across the language boundary underneath it, and the
        // control reported an `.id` diagnostic about a `.lua` file. So a mixed
        // negative home resolves law the same way `.foreign` does.
        .negative => switch (discover(path)) {
            .lua => .{ .law = .lua, .provenance = .foreign },
            .idol, .unknown => .{ .law = .idol, .provenance = .canonical },
        },
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

/// `docs/spec/corpus.md` IS the admission owner (`law.bridge.death`), and its
/// rules are written repo-relative. So the tree a file is admitted by is the
/// tree that CARRIES those rules, and this file is the anchor that finds it.
/// Any other anchor (`.git`, a hardcoded root, the cwd) would be a second
/// authority for a fact corpus.md already owns.
const CORPUS_RULES = "docs/spec/corpus.md";

/// The spelling the corpus rules are written in: the file's real location,
/// relative to the root of the tree that carries `CORPUS_RULES`.
///
/// WHY THIS EXISTS. `homeFacts` compares the characters it was handed. Handed
/// `examples/compile_fail/x.lua` it found the negative home; handed
/// `./examples/compile_fail/x.lua`, the absolute path, or the bare name from a
/// cwd inside that directory, it found nothing and `sourceFacts` fell through
/// to suffix `discover` — a DIFFERENT policy for the same bytes, silently
/// substituted. Measured on `examples/compile_fail/implicit_global_read.lua`:
/// one spelling checked clean, three refused `use of undeclared global 'x'`.
/// That is the shape `law.fallback.zero` forbids — the owner is uncertain, the
/// old fallback answers, and execution continues as if it had been asked.
///
/// Resolution, not string surgery, because the bare-name spelling carries no
/// directory at all and a symlink carries the wrong one. Identity of the FILE
/// is the only thing all four spellings share.
///
/// Returns null at the two boundaries where corpus.md genuinely has nothing to
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

/// Corpus home first, asked in the ONE spelling corpus.md is written in.
/// Suffix `discover` is only the unlisted-path fallback (`law.bridge.death`),
/// and "unlisted" now means the corpus does not cover the file — never that the
/// path happened to be spelled with a leading `./`. Later stages consume facts
/// / `lex.family`.
pub fn sourceFacts(path: []const u8) SourceFacts {
    var rel_buf: [std.fs.max_path_bytes]u8 = undefined;
    const canon = corpusRelative(path, &rel_buf) orelse path;
    if (homeFacts(canon)) |facts| return facts;
    return admit(discover(canon), canon);
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
