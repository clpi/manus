//! Physical bridge from the generated lexer artifact to the bootstrap host.
//! Lexer execution and legacy token records are owned upstream; canonical
//! lexical identity remains the GAP-145 frontier.
const std = @import("std");
const lexer = @import("lexer.zig");
const keyword_bridge = @import("keyword_bridge.zig");

/// Integer operand into production `tokenize()`. 1 = canonical Idol, 2 = compat.
/// Unknown is not a lexical family. `familyCode` retains the historical value
/// for allocator-free test helpers; production ingress must reject unknown
/// before constructing a lexer.
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

    /// A form the host cannot name, or an ordinal that publishes nothing, is
    /// the census changing under a walk the bind already established. The walk
    /// RECORDS that rather than skipping the entry: a skipped form is a shorter
    /// walk reported as a complete answer, and the recorded refusal is what
    /// makes every later `sourceFacts` answer unknown.
    pub fn next(self: *SourceFormIterator) ?SourceForm {
        if (self.next_index > self.count) return null;
        const index = self.next_index;
        self.next_index += 1;
        const law = sourceLawFromName(sourceformlaw(index)) orelse
            return refuseSourceForms(SourceFormError.UnnamedSourceLaw);
        const suffix = std.mem.span(sourceformsuffix(index));
        if (suffix.len == 0) return refuseSourceForms(SourceFormError.UnestablishedSourceForms);
        return .{ .law = law, .suffix = suffix, .canonical = sourceformcanonical(index) };
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
extern fn sourcepathformlaw(path: [*:0]const u8) [*:0]const u8;
extern fn sourcefactlaw(path: [*:0]const u8, role: [*:0]const u8) [*:0]const u8;
extern fn sourcefactprovenance(path: [*:0]const u8, role: [*:0]const u8) [*:0]const u8;

fn sourceLawFromName(name: [*:0]const u8) ?SourceLaw {
    return std.meta.stringToEnum(SourceLaw, std.mem.span(name));
}

fn sourceProvenanceFromName(name: [*:0]const u8) ?SourceProvenance {
    return std.meta.stringToEnum(SourceProvenance, std.mem.span(name));
}

pub const SourceFormError = error{
    /// The census answered with no walkable number of entries, or counted an
    /// ordinal it publishes nothing at.
    UnestablishedSourceForms,
    /// The census counts fewer forms than the producer publishes, so a walk of
    /// it covers a prefix and reports it as the whole census.
    PartialSourceFormCensus,
    /// The producer publishes a physical form whose law the host cannot name.
    UnnamedSourceLaw,
    /// Two published forms share a suffix, so one suffix would select two laws.
    AmbiguousSourceForm,
};

/// The producer's published physical source-form census, as the host consumes
/// it. Ingress binds the real externs and the controls bind planted ones
/// through this same shape, so a control exercises the walk ingress binds.
const SourceFormCensus = struct {
    count: i64,
    law: @TypeOf(&sourceformlaw),
    suffix: @TypeOf(&sourceformsuffix),
};

/// The host holds the published suffixes while it proves them distinct, so the
/// census it can establish is bounded by that table. A fact about the host's
/// scratch, not a roster of admitted forms.
const source_form_capacity = 64;

/// Census walks completed. `establishedSourceForms` is the only caller, so this
/// separates an ingress that walked the census from one that skipped it.
var source_form_walks: usize = 0;
var source_form_count: i64 = 0;
var source_form_refusal: ?SourceFormError = null;

/// Prove the host can name every physical source form the producer publishes,
/// and that the census covers all of them, before any path selects a law.
/// Returns the number of entries walked.
///
/// Every predicate downstream reads a NUMBER this census answered with, and a
/// census that answered with nothing used to arrive as a walk of zero forms —
/// which reads exactly like a producer that publishes none. An unestablished
/// census is unknown, and unknown stops law selection rather than counting as
/// an ordinary negative answer.
fn bindSourceFormCensus(census: SourceFormCensus) SourceFormError!i64 {
    // An empty or negative census is the absence of the fact law selection
    // consumes, not evidence that the host can name what the producer publishes.
    if (census.count <= 0) return SourceFormError.UnestablishedSourceForms;
    if (census.count > source_form_capacity) return SourceFormError.UnestablishedSourceForms;
    const count: usize = @intCast(census.count);

    var seen: [source_form_capacity][]const u8 = undefined;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const ordinal: i64 = @intCast(i + 1);
        if (sourceLawFromName(census.law(ordinal)) == null)
            return SourceFormError.UnnamedSourceLaw;
        const suffix = std.mem.span(census.suffix(ordinal));
        if (suffix.len == 0) return SourceFormError.UnestablishedSourceForms;
        for (seen[0..i]) |prior| {
            if (std.mem.eql(u8, prior, suffix)) return SourceFormError.AmbiguousSourceForm;
        }
        seen[i] = suffix;
    }

    // The count has to cover what the producer publishes rather than a prefix
    // of it. The producer answers nothing past its last form, so an ordinal
    // beyond the census that still publishes one is a short census — and the
    // walk it admits answers cleanly about forms it never saw.
    const past: i64 = @intCast(count + 1);
    if (sourceLawFromName(census.law(past)) != null or std.mem.span(census.suffix(past)).len != 0)
        return SourceFormError.PartialSourceFormCensus;

    source_form_walks += 1;
    return census.count;
}

/// The established census, bound once. A refusal is held rather than retried:
/// the producer answers the same census on every call, so a second ask is a
/// second chance to read unknown as clean.
fn establishedSourceForms() SourceFormError!i64 {
    if (source_form_refusal) |refusal| return refusal;
    if (source_form_count > 0) return source_form_count;
    const count = bindSourceFormCensus(.{
        .count = sourceformcount(),
        .law = &sourceformlaw,
        .suffix = &sourceformsuffix,
    }) catch |refusal| {
        source_form_refusal = refusal;
        return refusal;
    };
    source_form_count = count;
    return count;
}

fn refuseSourceForms(refusal: SourceFormError) ?SourceForm {
    source_form_refusal = refusal;
    source_form_count = 0;
    return null;
}

/// The established census, or an empty walk that cannot be read as a clean one:
/// the same recorded refusal that empties it makes `sourceFacts` answer unknown
/// for every path, so no consumer acts on the difference between "the producer
/// publishes no form here" and "the host could not establish what it publishes".
pub fn sourceForms() SourceFormIterator {
    return .{ .count = establishedSourceForms() catch 0 };
}

pub const SourceEntryError = error{
    /// The census answered with no walkable number of entries, or counted an
    /// ordinal it publishes no role or no pattern at.
    UnestablishedSourceEntries,
    /// The census counts fewer entries than the producer publishes, so the
    /// role walk covers a prefix and reports it as the whole census.
    PartialSourceEntryCensus,
    /// Two published entries share a pattern, so one path would carry two
    /// corpus roles and iteration order would pick between them.
    AmbiguousSourceEntry,
    /// The census publishes a role at a counted ordinal that the producer's own
    /// fact relations answer no differently than they answer for no role at
    /// all, so the entry qualifies nothing and law falls to physical form.
    IndistinctSourceRole,
    /// The host could not ask the role question: the producer admits a physical
    /// form for the path it asks over, so a role that selects nothing would
    /// answer that form's law and be indistinguishable from one that does.
    UnaskableSourceRole,
};

/// The path the role question is asked over. Its physical form must be one the
/// producer admits NOTHING for, which is what makes an answer readable: on such
/// a path a role that selects no arm falls through to a producer naming no law,
/// so any role that selects one answers differently, and any role that does not
/// answers the same bytes as no role. The bind proves that property of the
/// probe rather than assuming it — against a producer that admitted this form,
/// every role would look distinct and the check would pass on nothing.
const role_probe: [:0]const u8 = "sourcerole";

/// Does asking with this role reach a different answer than asking with none?
///
/// `sourcefactlaw`/`sourcefactprovenance` recognize a fixed set of role names
/// and fall through to physical form for every other. Fall-through is not a
/// refusal the owner reports: it is the clean answer a path carrying no corpus
/// role gets, byte for byte. So a census entry publishing a role those
/// relations never learned counts, publishes, and binds — while the home it
/// names selects law on suffix alone, which is exactly the substitution the
/// entry census exists to stop, arriving through a census that passes it.
fn distinguishesRole(census: SourceEntryCensus, role: [*:0]const u8) bool {
    const law = std.mem.span(census.factlaw(role_probe.ptr, role));
    const provenance = std.mem.span(census.factprovenance(role_probe.ptr, role));
    return !std.mem.eql(u8, law, std.mem.span(census.factlaw(role_probe.ptr, ""))) or
        !std.mem.eql(u8, provenance, std.mem.span(census.factprovenance(role_probe.ptr, "")));
}

/// The producer's published corpus-entry census, as the host consumes it.
/// Ingress binds the real externs and the controls bind planted ones through
/// this same shape, so a control exercises the walk ingress binds.
const SourceEntryCensus = struct {
    count: i64,
    role: @TypeOf(&sourceentryrole),
    pattern: @TypeOf(&sourceentrypattern),
    /// The fact relations the published roles are proved answerable against,
    /// and the form projection the probe is proved unadmitted by. Production
    /// binds the producer's; a control overrides the one face it perturbs.
    formlaw: @TypeOf(&sourcepathformlaw) = &sourcepathformlaw,
    factlaw: @TypeOf(&sourcefactlaw) = &sourcefactlaw,
    factprovenance: @TypeOf(&sourcefactprovenance) = &sourcefactprovenance,
};

/// The host holds the published patterns while it proves them distinct, so the
/// census it can establish is bounded by that table. A fact about the host's
/// scratch, not a roster of admitted homes.
const source_entry_capacity = 128;

/// Census walks completed. `establishedSourceEntries` is the only caller, so
/// this separates an ingress that walked the census from one that skipped it.
var source_entry_walks: usize = 0;
var source_entry_count: i64 = 0;
var source_entry_refusal: ?SourceEntryError = null;

/// Prove the producer publishes a distinguishing role and a distinct pattern at
/// every ordinal its corpus-entry census counts, and that the census covers all
/// of them, before any path selects a law. Returns the number of entries walked.
///
/// `sourcepathrole` walks THIS census inside the producer and answers with the
/// role of the longest matching pattern, or `""` when none matches. A census
/// that counts nothing, counts something that is not a number of entries, or
/// stops short makes that walk answer `""` for every path — byte-for-byte the
/// answer a path carrying no corpus role gives. `sourcefactlaw(path, "")` then
/// selects on physical form alone, which silently substitutes canonical Idol
/// for the Lua compatibility home and canonical provenance for foreign. The
/// host establishes the census first so unknown stops law selection instead of
/// arriving as an ordinary "this path has no role".
fn bindSourceEntryCensus(census: SourceEntryCensus) SourceEntryError!i64 {
    if (census.count <= 0) return SourceEntryError.UnestablishedSourceEntries;
    if (census.count > source_entry_capacity) return SourceEntryError.UnestablishedSourceEntries;
    const count: usize = @intCast(census.count);

    if (std.mem.span(census.formlaw(role_probe.ptr)).len != 0)
        return SourceEntryError.UnaskableSourceRole;

    var seen: [source_entry_capacity][]const u8 = undefined;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const ordinal: i64 = @intCast(i + 1);
        // An entry that publishes no role is the census carrying an ordinal
        // whose answer is the same bytes as "no entry matched", so the role
        // walk returns it as a clean negative from a pattern that DID match.
        if (std.mem.span(census.role(ordinal)).len == 0)
            return SourceEntryError.UnestablishedSourceEntries;
        // Publishing a role is not qualifying with one: the fact relations must
        // also be able to answer differently for it than for none.
        if (!distinguishesRole(census, census.role(ordinal)))
            return SourceEntryError.IndistinctSourceRole;
        const pattern = std.mem.span(census.pattern(ordinal));
        // An empty pattern is not a home that matches nothing: the producer's
        // prefix comparison admits it against any path, so a hole in the table
        // hands its role to paths that carry no such home.
        if (pattern.len == 0) return SourceEntryError.UnestablishedSourceEntries;
        for (seen[0..i]) |prior| {
            if (std.mem.eql(u8, prior, pattern)) return SourceEntryError.AmbiguousSourceEntry;
        }
        seen[i] = pattern;
    }

    const past: i64 = @intCast(count + 1);
    if (std.mem.span(census.role(past)).len != 0 or std.mem.span(census.pattern(past)).len != 0)
        return SourceEntryError.PartialSourceEntryCensus;

    source_entry_walks += 1;
    return census.count;
}

/// The established census, bound once. A refusal is held rather than retried,
/// exactly as for the physical form census.
fn establishedSourceEntries() SourceEntryError!i64 {
    if (source_entry_refusal) |refusal| return refusal;
    if (source_entry_count > 0) return source_entry_count;
    const count = bindSourceEntryCensus(.{
        .count = sourceentrycount(),
        .role = &sourceentryrole,
        .pattern = &sourceentrypattern,
    }) catch |refusal| {
        source_entry_refusal = refusal;
        return refusal;
    };
    source_entry_count = count;
    return count;
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
fn corpusRelative(path: []const u8, out: []u8) ?[:0]const u8 {
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
            if (rel.len >= out.len) return null;
            @memcpy(out[0..rel.len], rel);
            out[rel.len] = 0;
            return out[0..rel.len :0];
        }
        const parent = std.fs.path.dirname(dir) orelse return null;
        if (parent.len == dir.len) return null;
        dir = parent;
    }
}

fn producerPath(path: []const u8, out: []u8) ?[:0]const u8 {
    if (path.len >= out.len) return null;
    @memcpy(out[0..path.len], path);
    out[path.len] = 0;
    return out[0..path.len :0];
}

/// Normalize physical provenance once, then ask the executed Idol producer for
/// law and provenance. Zig owns no corpus roster, role→law mapping, or suffix
/// fallback. Later stages consume this returned fact / `lex.family`; they never
/// inspect the path again to select source meaning.
pub fn sourceFacts(path: []const u8) SourceFacts {
    // The producer's published physical forms are what a law is selected from,
    // and `sourcepathformlaw` walks that same census inside the producer. Until
    // the host has established it, no path names a source law: nothing
    // tokenizes through a producer whose form census the host could not read.
    _ = establishedSourceForms() catch return .{ .law = .unknown, .provenance = .unknown };
    // The corpus role below is what qualifies that form law into the exact
    // law/provenance pair, and `sourcepathrole` walks a SECOND published census
    // inside the producer to find it. A census the host could not establish
    // makes that walk answer `""` for every path, which the fact relations read
    // as "carries no corpus role" and answer on physical form alone.
    _ = establishedSourceEntries() catch return .{ .law = .unknown, .provenance = .unknown };

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const producer_path = corpusRelative(path, &path_buf) orelse
        producerPath(path, &path_buf) orelse
        return .{ .law = .unknown, .provenance = .unknown };

    // A corpus role qualifies an admitted source; it cannot invent a source
    // law for bytes whose physical form the producer does not admit. Ask the
    // executed producer twice: the form projection must be present and must
    // agree with the same fact query absent a corpus role. Only then may the
    // role-qualified query select the exact law/provenance pair. This keeps
    // compatibility homes lawful while making foreign/negative `.bin`, stdin,
    // and every other unadmitted form fail closed before tokenization.
    const form_law = sourceLawFromName(sourcepathformlaw(producer_path.ptr)) orelse
        return .{ .law = .unknown, .provenance = .unknown };
    const discovered_law = sourceLawFromName(sourcefactlaw(producer_path.ptr, "")) orelse
        return .{ .law = .unknown, .provenance = .unknown };
    if (form_law != discovered_law) return .{ .law = .unknown, .provenance = .unknown };

    const role = sourcepathrole(producer_path.ptr);
    const law = sourceLawFromName(sourcefactlaw(producer_path.ptr, role)) orelse return .{ .law = .unknown, .provenance = .unknown };
    const provenance = sourceProvenanceFromName(sourcefactprovenance(producer_path.ptr, role)) orelse return .{ .law = .unknown, .provenance = .unknown };
    return .{ .law = law, .provenance = provenance };
}

pub fn familyCode(facts: SourceFacts) i64 {
    return switch (facts.law) {
        .idol => family_canon,
        .lua, .unknown => family_compat,
    };
}

/// Production keyword lookup through the generated Idol lexer projection.
pub fn lookupKeyword(text: []const u8) ?lexer.TokenKind {
    return keyword_bridge.lookupKeyword(text);
}

test "lexer bridge: generated keyword projection" {
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
    const retired = sourceFacts("compiler.duo");
    try std.testing.expectEqual(SourceLaw.unknown, retired.law);
    try std.testing.expectEqual(SourceProvenance.unknown, sourceFacts("compiler.txt").provenance);
}

test "lexer bridge: one source-law producer owns physical form order" {
    try std.testing.expectEqual(@as(i64, 2), sourceformcount());
    try std.testing.expectEqualStrings("", std.mem.span(sourceformlaw(0)));
    try std.testing.expectEqualStrings("", std.mem.span(sourceformsuffix(3)));
    var forms = sourceForms();
    const idol = forms.next().?;
    try std.testing.expectEqual(SourceLaw.idol, idol.law);
    try std.testing.expectEqualStrings(".id", idol.suffix);
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
    try std.testing.expectEqual(SourceLaw.unknown, foreign_unknown.law);
    try std.testing.expectEqual(SourceProvenance.unknown, foreign_unknown.provenance);

    const negative_unknown = sourceFacts("examples/compile_fail/opaque.bin");
    try std.testing.expectEqual(SourceLaw.unknown, negative_unknown.law);
    try std.testing.expectEqual(SourceProvenance.unknown, negative_unknown.provenance);

    const stdin = sourceFacts("/dev/stdin");
    try std.testing.expectEqual(SourceLaw.unknown, stdin.law);
    try std.testing.expectEqual(SourceProvenance.unknown, stdin.provenance);

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

// Each planted census below differs from the producer's real one in exactly one
// respect and must fail closed with its own identity.

/// The producer publishes a first form whose law the host has no name for.
fn unnamedSourceFormLaw(i: i64) callconv(.c) [*:0]const u8 {
    if (i == 1) return "bash";
    return sourceformlaw(i);
}

/// The same, at the last entry: only a walk that reaches the end sees it.
fn lastUnnamedSourceFormLaw(i: i64) callconv(.c) [*:0]const u8 {
    if (i == sourceformcount()) return "bash";
    return sourceformlaw(i);
}

/// An ordinal the census counts but publishes nothing at.
fn absentSourceFormSuffix(i: i64) callconv(.c) [*:0]const u8 {
    if (i == sourceformcount()) return "";
    return sourceformsuffix(i);
}

/// The last form repeats the first form's suffix, so one suffix would select
/// two laws and proving "every form is named" would prove one form twice.
fn repeatedSourceFormSuffix(i: i64) callconv(.c) [*:0]const u8 {
    if (i == sourceformcount()) return sourceformsuffix(1);
    return sourceformsuffix(i);
}

test "lexer bridge: the producer's source-form census governs law selection" {
    const real: SourceFormCensus = .{
        .count = sourceformcount(),
        .law = &sourceformlaw,
        .suffix = &sourceformsuffix,
    };
    // Both ends of the walk have to be reachable, and the short-census control
    // needs an ordinal to drop.
    try std.testing.expect(real.count >= 2);

    // The bound census is total, and the walk covers all of it rather than a
    // prefix: without this the refusals below are satisfied by a walk that
    // visited nothing.
    const before = source_form_walks;
    try std.testing.expectEqual(real.count, try bindSourceFormCensus(real));
    try std.testing.expectEqual(before + 1, source_form_walks);

    // empty: a census that publishes nothing arrived as a walk of zero forms,
    // which reads exactly like a producer that admits none.
    try std.testing.expectError(SourceFormError.UnestablishedSourceForms, bindSourceFormCensus(.{
        .count = 0,
        .law = real.law,
        .suffix = real.suffix,
    }));

    // not a count: a census answering with something that is not a number of
    // entries is unknown, never zero.
    try std.testing.expectError(SourceFormError.UnestablishedSourceForms, bindSourceFormCensus(.{
        .count = -1,
        .law = real.law,
        .suffix = real.suffix,
    }));

    // over-long: a census the host cannot hold cannot be proved distinct.
    try std.testing.expectError(SourceFormError.UnestablishedSourceForms, bindSourceFormCensus(.{
        .count = source_form_capacity + 1,
        .law = real.law,
        .suffix = real.suffix,
    }));

    // short: the census counts fewer forms than the producer publishes, so a
    // walk of it answers cleanly about a form it never saw.
    try std.testing.expectError(SourceFormError.PartialSourceFormCensus, bindSourceFormCensus(.{
        .count = real.count - 1,
        .law = real.law,
        .suffix = real.suffix,
    }));

    // Unnamed at both ends, so neither a walk that stops after the first entry
    // nor one that checks only the last can pass.
    try std.testing.expectError(SourceFormError.UnnamedSourceLaw, bindSourceFormCensus(.{
        .count = real.count,
        .law = &unnamedSourceFormLaw,
        .suffix = real.suffix,
    }));
    try std.testing.expectError(SourceFormError.UnnamedSourceLaw, bindSourceFormCensus(.{
        .count = real.count,
        .law = &lastUnnamedSourceFormLaw,
        .suffix = real.suffix,
    }));

    // Malformed evidence rather than a law the host failed to name, and the two
    // are separable: an ordinal that publishes nothing, and two forms sharing a
    // suffix.
    try std.testing.expectError(SourceFormError.UnestablishedSourceForms, bindSourceFormCensus(.{
        .count = real.count,
        .law = real.law,
        .suffix = &absentSourceFormSuffix,
    }));
    try std.testing.expectError(SourceFormError.AmbiguousSourceForm, bindSourceFormCensus(.{
        .count = real.count,
        .law = real.law,
        .suffix = &repeatedSourceFormSuffix,
    }));

    // A refused census is not a walk. Without this a bind that counted its own
    // refusals would satisfy the separability the ingress control below rests on.
    try std.testing.expectEqual(before + 1, source_form_walks);
}

test "lexer bridge: ingress binds through the governed census" {
    const held_count = source_form_count;
    const held_refusal = source_form_refusal;
    defer {
        source_form_count = held_count;
        source_form_refusal = held_refusal;
    }

    // `sourceFacts` is the one ingress that selects a source law and it is on
    // the path of every production tokenize. Selecting a law must ADVANCE the
    // walk; asserting only that it answers stays green with the census call
    // deleted, which is the shape that makes a transfer decorative. An earlier
    // test may have bound the census already, so unbind.
    source_form_count = 0;
    source_form_refusal = null;
    const before = source_form_walks;
    try std.testing.expectEqual(SourceLaw.idol, sourceFacts("compiler.id").law);
    try std.testing.expectEqual(before + 1, source_form_walks);

    // Bound once, so a second ingress walks nothing further.
    try std.testing.expectEqual(SourceLaw.lua, sourceFacts("compiler.lua").law);
    try std.testing.expectEqual(before + 1, source_form_walks);

    // ...and a census the host could not establish is not a clean one: no path
    // names a law, and the form walk every consumer reads is empty for the same
    // recorded reason rather than for a fact about the tree.
    source_form_count = 0;
    source_form_refusal = SourceFormError.UnestablishedSourceForms;
    try std.testing.expectEqual(SourceLaw.unknown, sourceFacts("compiler.id").law);
    var forms = sourceForms();
    try std.testing.expect(forms.next() == null);

    // A walk that outruns the census is the producer changing under one the
    // bind established. The iterator records that instead of skipping the
    // ordinal, so the walk ends AND no path names a law afterwards — one fact,
    // not two. A walk that skipped instead would end in the same place and
    // leave law selection answering.
    source_form_count = 0;
    source_form_refusal = null;
    var past: SourceFormIterator = .{ .count = sourceformcount() + 1 };
    var walked: usize = 0;
    while (past.next()) |_| walked += 1;
    try std.testing.expectEqual(@as(usize, @intCast(sourceformcount())), walked);
    try std.testing.expectEqual(SourceLaw.unknown, sourceFacts("compiler.id").law);
}

// Each planted census below differs from the producer's real corpus-entry
// census in exactly one respect and must fail closed with its own identity.

/// The producer counts a first entry it publishes no role at.
fn absentSourceEntryRole(i: i64) callconv(.c) [*:0]const u8 {
    if (i == 1) return "";
    return sourceentryrole(i);
}

/// The same, at the last entry: only a walk that reaches the end sees it.
fn lastAbsentSourceEntryRole(i: i64) callconv(.c) [*:0]const u8 {
    if (i == sourceentrycount()) return "";
    return sourceentryrole(i);
}

/// An ordinal the census counts but publishes no pattern at. The producer's
/// prefix comparison admits an empty pattern against a path, so this hands the
/// ordinal's role to paths that carry no such home.
fn absentSourceEntryPattern(i: i64) callconv(.c) [*:0]const u8 {
    if (i == sourceentrycount()) return "";
    return sourceentrypattern(i);
}

/// The last entry repeats the first entry's pattern, so one path would carry
/// two corpus roles and the producer's `n >= bestlen` walk picks the later one.
fn repeatedSourceEntryPattern(i: i64) callconv(.c) [*:0]const u8 {
    if (i == sourceentrycount()) return sourceentrypattern(1);
    return sourceentrypattern(i);
}

/// The first entry publishes a role spelled a way the producer's fact relations
/// never learned. Nothing about the census is malformed: it counts, it publishes
/// at every ordinal, its patterns are distinct.
fn indistinctSourceEntryRole(i: i64) callconv(.c) [*:0]const u8 {
    if (i == 1) return "compat";
    return sourceentryrole(i);
}

/// The same, at the last entry: only a walk that reaches the end sees it.
fn lastIndistinctSourceEntryRole(i: i64) callconv(.c) [*:0]const u8 {
    if (i == sourceentrycount()) return "compat";
    return sourceentryrole(i);
}

/// The producer admits a physical form for the path the role question is asked
/// over. Every role then reaches that form's law where a role selecting nothing
/// would too, so the question stops separating the two and the walk would pass
/// a census of roles it proved nothing about.
fn probeAdmittedFormLaw(path: [*:0]const u8) callconv(.c) [*:0]const u8 {
    if (std.mem.eql(u8, std.mem.span(path), role_probe)) return "idol";
    return sourcepathformlaw(path);
}

test "lexer bridge: the producer's corpus-entry census governs role selection" {
    const real: SourceEntryCensus = .{
        .count = sourceentrycount(),
        .role = &sourceentryrole,
        .pattern = &sourceentrypattern,
    };
    // Both ends of the walk have to be reachable, and the short-census control
    // needs an ordinal to drop.
    try std.testing.expect(real.count >= 2);

    // The bound census is total, and the walk covers all of it rather than a
    // prefix: without this the refusals below are satisfied by a walk that
    // visited nothing.
    const before = source_entry_walks;
    try std.testing.expectEqual(real.count, try bindSourceEntryCensus(real));
    try std.testing.expectEqual(before + 1, source_entry_walks);

    // THE FALSE ACCEPT this census closes. An unestablished census makes the
    // producer's role walk answer `""` for every path. Asked without a role,
    // the same compatibility-home path selects a DIFFERENT law and a DIFFERENT
    // provenance from the ones ingress answers with — so the substitution is
    // silent and total, not a boundary the owner reports.
    const home = "examples/lua/host.id";
    try std.testing.expectEqual(SourceLaw.lua, sourceLawFromName(sourcefactlaw(home, sourcepathrole(home))).?);
    try std.testing.expectEqual(SourceLaw.idol, sourceLawFromName(sourcefactlaw(home, "")).?);
    const vendored = "vendor/opaque.id";
    try std.testing.expectEqual(SourceProvenance.foreign, sourceProvenanceFromName(sourcefactprovenance(vendored, sourcepathrole(vendored))).?);
    try std.testing.expectEqual(SourceProvenance.canonical, sourceProvenanceFromName(sourcefactprovenance(vendored, "")).?);

    // empty: a census that counts nothing leaves the producer's role walk
    // answering `""`, which reads exactly like a path carrying no corpus role.
    try std.testing.expectError(SourceEntryError.UnestablishedSourceEntries, bindSourceEntryCensus(.{
        .count = 0,
        .role = real.role,
        .pattern = real.pattern,
    }));

    // not a count: a census answering with something that is not a number of
    // entries is unknown, never zero.
    try std.testing.expectError(SourceEntryError.UnestablishedSourceEntries, bindSourceEntryCensus(.{
        .count = -1,
        .role = real.role,
        .pattern = real.pattern,
    }));

    // over-long: a census the host cannot hold cannot be proved distinct.
    try std.testing.expectError(SourceEntryError.UnestablishedSourceEntries, bindSourceEntryCensus(.{
        .count = source_entry_capacity + 1,
        .role = real.role,
        .pattern = real.pattern,
    }));

    // short: the census counts fewer entries than the producer publishes, so
    // the role walk answers cleanly about homes it never saw.
    try std.testing.expectError(SourceEntryError.PartialSourceEntryCensus, bindSourceEntryCensus(.{
        .count = real.count - 1,
        .role = real.role,
        .pattern = real.pattern,
    }));

    // Roleless at both ends, so neither a walk that stops after the first entry
    // nor one that checks only the last can pass.
    try std.testing.expectError(SourceEntryError.UnestablishedSourceEntries, bindSourceEntryCensus(.{
        .count = real.count,
        .role = &absentSourceEntryRole,
        .pattern = real.pattern,
    }));
    try std.testing.expectError(SourceEntryError.UnestablishedSourceEntries, bindSourceEntryCensus(.{
        .count = real.count,
        .role = &lastAbsentSourceEntryRole,
        .pattern = real.pattern,
    }));

    // Malformed evidence rather than a missing role, and the two are separable:
    // an ordinal that publishes no pattern, and two entries sharing one.
    try std.testing.expectError(SourceEntryError.UnestablishedSourceEntries, bindSourceEntryCensus(.{
        .count = real.count,
        .role = real.role,
        .pattern = &absentSourceEntryPattern,
    }));
    try std.testing.expectError(SourceEntryError.AmbiguousSourceEntry, bindSourceEntryCensus(.{
        .count = real.count,
        .role = real.role,
        .pattern = &repeatedSourceEntryPattern,
    }));

    // A refused census is not a walk. Without this a bind that counted its own
    // refusals would satisfy the separability the ingress control below rests on.
    try std.testing.expectEqual(before + 1, source_entry_walks);
}

test "lexer bridge: a published role the fact relations cannot answer for is not a role" {
    const real: SourceEntryCensus = .{
        .count = sourceentrycount(),
        .role = &sourceentryrole,
        .pattern = &sourceentrypattern,
    };
    try std.testing.expect(real.count >= 2);

    // THE FALSE ACCEPT this closes, executed on the real producer and a real
    // corpus path. `compat` is not malformed evidence — it is a role spelled a
    // way `sourcefactlaw` never learned, and the relations answer it with the
    // physical-form law, byte for byte what they answer a path carrying NO
    // role. The compatibility home disappears and nothing reports a boundary.
    const home = "examples/lua/host.id";
    try std.testing.expectEqualStrings("lua", std.mem.span(sourcefactlaw(home, sourcepathrole(home))));
    try std.testing.expectEqualStrings("idol", std.mem.span(sourcefactlaw(home, "compat")));
    try std.testing.expectEqualStrings(
        std.mem.span(sourcefactlaw(home, "")),
        std.mem.span(sourcefactlaw(home, "compat")),
    );

    // The question is asked over a path the producer admits no form for, which
    // is the property that makes its answer readable. Assert it of the probe
    // rather than of the spelling: a producer that admitted this form is the
    // control below, and it must refuse rather than pass on nothing.
    try std.testing.expectEqualStrings("", std.mem.span(sourcepathformlaw(role_probe.ptr)));
    try std.testing.expect(!distinguishesRole(real, "compat"));

    // Every role the real census publishes IS answerable, so the closure is a
    // fact about published roles and not a refusal of the producer as it stands.
    const before = source_entry_walks;
    try std.testing.expectEqual(real.count, try bindSourceEntryCensus(real));
    try std.testing.expectEqual(before + 1, source_entry_walks);
    var ordinal: i64 = 1;
    while (ordinal <= real.count) : (ordinal += 1) {
        try std.testing.expect(distinguishesRole(real, sourceentryrole(ordinal)));
    }

    // Indistinct at both ends, so neither a walk that stops after the first
    // entry nor one that checks only the last can pass. Separate identity from
    // the roleless controls above: this census publishes a role everywhere.
    try std.testing.expectError(SourceEntryError.IndistinctSourceRole, bindSourceEntryCensus(.{
        .count = real.count,
        .role = &indistinctSourceEntryRole,
        .pattern = real.pattern,
    }));
    try std.testing.expectError(SourceEntryError.IndistinctSourceRole, bindSourceEntryCensus(.{
        .count = real.count,
        .role = &lastIndistinctSourceEntryRole,
        .pattern = real.pattern,
    }));

    // A probe whose form the producer admits cannot separate a role that
    // selects an arm from one that selects nothing, so the host refuses to ask
    // rather than walking a census the question passes vacuously.
    try std.testing.expectError(SourceEntryError.UnaskableSourceRole, bindSourceEntryCensus(.{
        .count = real.count,
        .role = real.role,
        .pattern = real.pattern,
        .formlaw = &probeAdmittedFormLaw,
    }));

    // ...and that refusal is not the walk answering: it precedes every ordinal,
    // including the indistinct one the previous control caught.
    try std.testing.expectError(SourceEntryError.UnaskableSourceRole, bindSourceEntryCensus(.{
        .count = real.count,
        .role = &indistinctSourceEntryRole,
        .pattern = real.pattern,
        .formlaw = &probeAdmittedFormLaw,
    }));

    // An unwalkable census is still unwalkable: the absent, non-numeric and
    // short controls fail closed on their own identity BEFORE any role is
    // asked about, so this closure never reports a pass one of them owns.
    try std.testing.expectError(SourceEntryError.UnestablishedSourceEntries, bindSourceEntryCensus(.{
        .count = 0,
        .role = &indistinctSourceEntryRole,
        .pattern = real.pattern,
    }));
    try std.testing.expectError(SourceEntryError.UnestablishedSourceEntries, bindSourceEntryCensus(.{
        .count = -1,
        .role = &indistinctSourceEntryRole,
        .pattern = real.pattern,
    }));
    try std.testing.expectError(SourceEntryError.PartialSourceEntryCensus, bindSourceEntryCensus(.{
        .count = real.count - 1,
        .role = &lastIndistinctSourceEntryRole,
        .pattern = real.pattern,
    }));

    // No refusal above walked. Without this the counts the ingress control
    // separates on would be satisfied by a bind that counted its own refusals.
    try std.testing.expectEqual(before + 1, source_entry_walks);
}

test "lexer bridge: ingress binds through the governed corpus-entry census" {
    const held_forms = source_form_count;
    const held_form_refusal = source_form_refusal;
    const held_entries = source_entry_count;
    const held_entry_refusal = source_entry_refusal;
    defer {
        source_form_count = held_forms;
        source_form_refusal = held_form_refusal;
        source_entry_count = held_entries;
        source_entry_refusal = held_entry_refusal;
    }

    // Selecting a law must ADVANCE the entry walk; asserting only that ingress
    // answers stays green with the census call deleted, which is the shape that
    // makes a transfer decorative. An earlier test may have bound it, so unbind.
    source_form_count = 0;
    source_form_refusal = null;
    source_entry_count = 0;
    source_entry_refusal = null;
    const before = source_entry_walks;
    try std.testing.expectEqual(SourceLaw.lua, sourceFacts("examples/lua/host.id").law);
    try std.testing.expectEqual(before + 1, source_entry_walks);

    // Bound once, so a second ingress walks nothing further.
    try std.testing.expectEqual(SourceLaw.idol, sourceFacts("examples/json/pack.id").law);
    try std.testing.expectEqual(before + 1, source_entry_walks);

    // A census the host could not establish is not a clean one. The path whose
    // law the role decides answers unknown rather than the physical-form law it
    // would otherwise be silently given, and so does one whose role only
    // decides provenance.
    source_entry_count = 0;
    source_entry_refusal = SourceEntryError.UnestablishedSourceEntries;
    const refused_home = sourceFacts("examples/lua/host.id");
    try std.testing.expectEqual(SourceLaw.unknown, refused_home.law);
    try std.testing.expectEqual(SourceProvenance.unknown, refused_home.provenance);
    try std.testing.expectEqual(SourceProvenance.unknown, sourceFacts("vendor/opaque.id").provenance);

    // A census the host walked but whose roles it could not prove answerable is
    // held the same way. Without this the new refusal would bind as a value
    // ingress never reads, and every path would keep selecting on a role the
    // fact relations answer nothing for.
    source_entry_count = 0;
    source_entry_refusal = SourceEntryError.IndistinctSourceRole;
    try std.testing.expectEqual(SourceLaw.unknown, sourceFacts("examples/lua/host.id").law);
    source_entry_count = 0;
    source_entry_refusal = SourceEntryError.UnaskableSourceRole;
    try std.testing.expectEqual(SourceLaw.unknown, sourceFacts("examples/lua/host.id").law);

    // The two censuses are separate facts: an establishable entry census does
    // not answer for an unestablishable form census, or the other way round.
    source_entry_count = 0;
    source_entry_refusal = null;
    source_form_count = 0;
    source_form_refusal = SourceFormError.UnestablishedSourceForms;
    try std.testing.expectEqual(SourceLaw.unknown, sourceFacts("examples/lua/host.id").law);
}
