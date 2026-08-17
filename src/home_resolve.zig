//! ONE AUTHORITY for "which file does this HOME name?" — and for the symbol a
//! relation in that home is realized as.
//!
//! ===========================================================================
//! WHY THIS FILE EXISTS
//! ===========================================================================
//! The home-to-file map already existed. It lived in `codegen.zig`
//! (`find_module_file_for_req` / `find_module_path`), it worked, it searched
//! five roots — and it was computed FOR THE C BOOTSTRAP AND THROWN AWAY.
//! `sema` never saw it, so a dotted callee reached no declaration, published no
//! `ApplicationFact`, and the direct backend refused the module with
//! `unresolved-application-facts`. HPLS §99 class: *fact true, represented, and
//! not propagated* — the map was right there, in the authority being retired.
//!
//! MEASURED, and this is the framing measurement for the whole gap: at
//! `c8d1b137`, `idol check` accepts
//!
//!     f: i64 = (x: i64)
//!       nosuchmodule.nosuchrelation(x)
//!
//! with `✓ checked — no errors`, exit 0. No resolution was attempted at all.
//!
//! ===========================================================================
//! THE SIBLING RULE, WHICH `find_module_file_for_req` DID NOT HAVE
//! ===========================================================================
//! `find_module_file_for_req` is keyed on a `req "a.b"` STRING, so it only ever
//! searched from the project root down. `lib/compiler/**` contains no import
//! statements at all — `bind.id` writes `lexer.new(src, file, family)` and
//! means the file NEXT TO IT. A home written bare, with no dots, is a SIBLING
//! first: it is the same directory, which is the smallest home there is. Only
//! then do the shared roots apply.
//!
//! ===========================================================================
//! THE MANGLING LAW — A DECISION, NOT A DISCOVERY
//! ===========================================================================
//! THE SYMBOL A RELATION IS REALIZED AS IS A FUNCTION OF ITS IDENTITY, AND ITS
//! IDENTITY IS `(home, name)`. It is never a function of `name` alone.
//!
//! Two authorities disagreed about this and the surviving one had no home:
//!
//!   * `codegen.zig:mangled_name` produces `{module_cname}__{name}` — home
//!     qualified, on the C path being retired.
//!   * `dnir_lower.zig:funcExportName` returns `fd.path[0]` — the BARE name,
//!     on the direct backend, the only backend there is.
//!
//! The bare name is not merely inelegant, and this is MEASURED rather than
//! argued. `lib/compiler/record.id` compiles today to `_emits _field _named
//! _positional _typename`. A second ordinary module that names one relation
//! `field` compiles to `_field`. `ld -r` over the two objects:
//!
//!     duplicate symbol '_field' in: mysym.o / record.o
//!
//! Self-hosting REQUIRES linking the 18 modules of `lib/compiler/` into one
//! image. Under home-blind symbols that link cannot exist, independent of every
//! sema and graph question in front of it. The self-hosted compiler's own
//! `lib/compiler/symbol.id` records the identical defect one layer out, in its
//! header, measured 2026-08-08: an idol relation named `abs` emitted unmangled
//! into C, libc had already declared it, and `abs(21)` printed **21** — libc's
//! answer, not idol's. "Not a build failure. A wrong number."
//!
//! So:
//!
//!     THE LAW. A relation declared as `name` in home `h` is realized as the
//!     symbol `idol_<h'>__<name>`, where `h'` is the home's dotted path with
//!     every `.` replaced by `_`. Any caller, in any home, derives the same
//!     string from the same two facts and needs nothing else.
//!
//!     THE EXEMPTIONS, and there are exactly two, both FOREIGN BOUNDARIES in
//!     the §34 sense — "internal ABI is realization; only foreign boundaries
//!     require foreign ABI". At a foreign boundary the name is not ours to
//!     choose:
//!
//!       1. the process entry `main`, whose name belongs to the C runtime;
//!       2. a relation carrying `@ffi(n)` / `@comp.c.export(n)`, where the
//!          foreign name IS the declaration.
//!
//!     Nothing else is exempt. In particular "the program has one file" is NOT
//!     an exemption: a one-file program's relations are still `(home, name)`,
//!     and a law with a special case for small programs is a law that stops
//!     being true exactly when a second file arrives.
//!
//! `homeSymbol` below is that law, in one place, callable by the DEFINER
//! (emitting its own relations) and by the CALLER (referring to a foreign one).
//! The two agree by construction because they call the same function with the
//! same two arguments — which is the whole point, and the reason this is not
//! two string builders in two files.
//!
//! STAGING NOTE, stated so nobody reads silence as completeness: applying the
//! law to the DEFINER side renames every symbol every object in the tree
//! exports. That is a corpus-wide ABI change and it is deliberately NOT bundled
//! with the resolution change — see `docs/cross-home-identity.md`. What is
//! wired today is the CALLER side for cross-home references only, which is
//! additive: a symbol that did not exist before now exists.

const std = @import("std");
const Io = std.Io;
const lexer_bridge = @import("lexer_bridge.zig");

/// Where a home reference is written, and which roots its file may live under.
/// `from` is the source path of the referring file — the sibling rule needs it,
/// and so does the project-root walk.
pub const Roots = struct {
    from: []const u8,
    stdlib_root: ?[]const u8 = null,
};

/// The home path spelled as a relative file path: `compiler.lexer` ->
/// `compiler/lexer`. Returns null when the name cannot be one (empty, or longer
/// than any path this resolver will build).
fn homeAsPath(buf: []u8, home: []const u8) ?[]const u8 {
    if (home.len == 0 or home.len > buf.len) return null;
    for (home, 0..) |c, i| buf[i] = if (c == '.') '/' else c;
    return buf[0..home.len];
}

/// The nearest ancestor of `from` that contains a `src/` directory, or `from`'s
/// own directory when there is none. Same walk `codegen.project_root_dir` does;
/// this is the shared copy, not a second opinion.
fn projectRoot(io: Io, from: []const u8) []const u8 {
    if (from.len == 0) return ".";
    const dir = std.fs.path.dirname(from) orelse ".";
    var d = dir;
    while (d.len > 0) {
        var pbuf: [1024]u8 = undefined;
        const probe = std.fmt.bufPrint(&pbuf, "{s}/src", .{d}) catch break;
        const cwd = Io.Dir.cwd();
        var fd = Io.Dir.openDir(cwd, io, probe, .{}) catch {
            if (std.mem.eql(u8, d, ".")) break;
            d = std.fs.path.dirname(d) orelse ".";
            continue;
        };
        fd.close(io);
        return d;
    }
    return dir;
}

/// The four spellings a module file may take under one base directory.
/// `.lua` remains because 585 `.lua` modules are still tracked in the sibling
/// tree; it is de-Lua debt, owned by the de-Lua lane, not silently dropped here.
pub fn moduleFileUnder(
    alloc: std.mem.Allocator,
    io: Io,
    base_dir: []const u8,
    mod_path: []const u8,
) ?[]const u8 {
    const templates = .{
        "{s}/{s}" ++ lexer_bridge.CANONICAL_SOURCE_SUFFIX,
        "{s}/{s}.lua",
        "{s}/{s}/init" ++ lexer_bridge.CANONICAL_SOURCE_SUFFIX,
        "{s}/{s}/init.lua",
    };
    const cwd = Io.Dir.cwd();
    inline for (templates) |tmpl| {
        const path = std.fmt.allocPrint(alloc, tmpl, .{ base_dir, mod_path }) catch return null;
        if (Io.Dir.access(cwd, io, path, .{})) |_| {
            return path;
        } else |_| {
            alloc.free(path);
        }
    }
    return null;
}

/// The file a home names, or null. Caller owns the returned path.
///
/// Search order, and the FIRST entry is the one `find_module_file_for_req`
/// could not have: sibling of the referring file · project root · stdlib root ·
/// `lib/` · `vendor/` (for a `vendor.` home) · `lib/core/` (for a `std.core.`
/// home).
pub fn resolve(
    alloc: std.mem.Allocator,
    io: Io,
    roots: Roots,
    home: []const u8,
) ?[]const u8 {
    const vendor_prefix = "vendor.";
    const core_prefix = "std.core.";
    const has_vendor = std.mem.startsWith(u8, home, vendor_prefix);
    const has_core = std.mem.startsWith(u8, home, core_prefix);
    const strip: usize = if (has_vendor) vendor_prefix.len else if (has_core) core_prefix.len else 0;

    var buf: [512]u8 = undefined;
    const mod_path = homeAsPath(&buf, home[strip..]) orelse return null;

    if (roots.from.len > 0) {
        const sibling_dir = std.fs.path.dirname(roots.from) orelse ".";
        if (moduleFileUnder(alloc, io, sibling_dir, mod_path)) |p| return p;
    }
    const project_root = projectRoot(io, roots.from);
    if (moduleFileUnder(alloc, io, project_root, mod_path)) |p| return p;
    if (roots.stdlib_root) |root| {
        if (moduleFileUnder(alloc, io, root, mod_path)) |p| return p;
    }
    // THE SHARED ROOTS HANG OFF THE PROJECT, NOT OFF THE PROCESS.
    //
    // `find_module_file_for_req` searched a bare `"lib"`, which `Io.Dir.access`
    // resolves against the CURRENT WORKING DIRECTORY. MEASURED: compiling
    // `/Users/clp/x/idol/lib/compiler/host.id` from `/Users/clp/x/idol-native`
    // — which is exactly how `gate/selfhost.sh` invokes it — made `compiler.lexer`
    // look for `./lib/compiler/lexer.id` under the GATE's tree, found nothing,
    // and the home was unresolvable purely because of where the shell was
    // standing. A home is a property of the program, and the CWD is not.
    //
    // The CWD spelling is kept AFTER the project one, not instead of it: a
    // single-file invocation with no `src/` anywhere above it has no project
    // root to speak of and `./lib` is then the only thing `lib` can mean.
    for ([_][]const u8{ project_root, "." }) |base| {
        var joined: [1024]u8 = undefined;
        const lib_dir = std.fmt.bufPrint(&joined, "{s}/lib", .{base}) catch continue;
        if (moduleFileUnder(alloc, io, lib_dir, mod_path)) |p| return p;
        if (has_vendor) {
            const vendor_dir = std.fmt.bufPrint(&joined, "{s}/vendor", .{base}) catch continue;
            if (moduleFileUnder(alloc, io, vendor_dir, mod_path)) |p| return p;
        }
        if (has_core) {
            const core_dir = std.fmt.bufPrint(&joined, "{s}/lib/core", .{base}) catch continue;
            if (moduleFileUnder(alloc, io, core_dir, mod_path)) |p| return p;
        }
    }
    return null;
}

/// Remove spelling-only `.` and `..` components before a path contributes a
/// home. A parent component must cancel one component from the same spelling;
/// leading relative parents and absolute-root underflow have no lexical home
/// to name, so they fail closed.
fn lexicalPath(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0) return error.AmbiguousHomePath;

    const absolute = std.fs.path.isAbsolute(path);
    var parts: std.ArrayList([]const u8) = .empty;
    defer parts.deinit(alloc);

    var it = std.mem.tokenizeScalar(u8, path, '/');
    while (it.next()) |part| {
        if (std.mem.eql(u8, part, ".")) continue;
        if (std.mem.eql(u8, part, "..")) {
            if (parts.items.len == 0) return error.HomePathEscape;
            _ = parts.pop();
            continue;
        }
        try parts.append(alloc, part);
    }
    if (parts.items.len == 0) return error.AmbiguousHomePath;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);
    if (absolute) try out.append(alloc, '/');
    for (parts.items, 0..) |part, index| {
        if (index != 0) try out.append(alloc, '/');
        try out.appendSlice(alloc, part);
    }
    return out.toOwnedSlice(alloc);
}

fn isWithinRoot(path: []const u8, root: []const u8) bool {
    if (std.mem.eql(u8, path, root)) return true;
    if (!std.mem.startsWith(u8, path, root)) return false;
    if (root.len == 0 or root[root.len - 1] == '/') return true;
    return path.len > root.len and path[root.len] == '/';
}

/// The HOME a file inhabits, as a dotted path, derived from the file path.
///
/// Both sides of a cross-home reference must land on the same string or the
/// symbols do not meet, so this is derived from ONE place — the path — and
/// never from a header comment. `lib/compiler/lexer.id` -> `compiler.lexer`;
/// `examples/boring/primes.id` -> `boring.primes`; a bare `probe.id` ->
/// `probe`. The leading `lib/` is dropped because it is a SEARCH ROOT, not a
/// home: `lib/compiler/lexer.id` and a project-root `compiler/lexer.id` are the
/// same home reached two ways, and they must mangle alike.
pub fn homeOfPath(alloc: std.mem.Allocator, io: Io, path: []const u8) ![]const u8 {
    const normalized = try lexicalPath(alloc, path);
    defer alloc.free(normalized);
    const stem = std.fs.path.stem(normalized);
    var dir = std.fs.path.dirname(normalized) orelse "";
    // THE HOME MAY NOT CONTAIN THE FILESYSTEM. Compiling
    // `/Users/clp/x/idol/lib/compiler/lexer.id` and compiling
    // `lib/compiler/lexer.id` are the same module, and if the two produce
    // `Users_clp_x_idol_compiler_lexer` and `compiler_lexer` then the symbol
    // depends on how the shell spelled the argument — the definer and the
    // caller stop agreeing and the law is void. MEASURED before this line
    // existed: `test.assert_eq(…)` resolved to home `Users.clp.x.idol.test`.
    //
    // The project root is the same walk the resolver uses to FIND the file, so
    // stripping it here cannot disagree with the search that produced it.
    const root = projectRoot(io, normalized);
    if (root.len > 0 and !std.mem.eql(u8, root, ".") and isWithinRoot(dir, root)) {
        dir = dir[root.len..];
    }
    var parts: std.ArrayList([]const u8) = .empty;
    defer parts.deinit(alloc);
    var it = std.mem.tokenizeScalar(u8, dir, '/');
    while (it.next()) |part| {
        try parts.append(alloc, part);
    }
    // Drop every leading search-root segment. These name WHERE the compiler
    // looked, not WHOSE the relation is.
    const roots = [_][]const u8{ "lib", "vendor", "core", "std" };
    var start: usize = 0;
    outer: while (start < parts.items.len) {
        for (roots) |r| {
            if (std.mem.eql(u8, parts.items[start], r)) {
                start += 1;
                continue :outer;
            }
        }
        break;
    }
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);
    for (parts.items[start..]) |part| {
        try out.appendSlice(alloc, part);
        try out.append(alloc, '.');
    }
    try out.appendSlice(alloc, stem);
    return out.toOwnedSlice(alloc);
}

/// A SYMBOL IS AN IDENTIFIER, so every byte outside `[A-Za-z0-9_]` becomes `_`.
///
/// This is the `.` -> `_` rule stated over the alphabet a symbol actually has,
/// and it SUBSUMES it rather than sitting beside it. The dot was not special:
/// it was simply the first non-identifier byte anyone hit.
///
/// MEASURED, and this is why it is not decoration: the corpus contains
/// `scripts/gatecap-probe.id` and `scripts/setup-nvim.id`. Their homes carry a
/// HYPHEN, and `idol compile --target native-asm` on such a file emitted
///
///     .globl _idol_odd-name__f
///
/// which `xcrun clang -c` refuses with `unexpected token` — the object path
/// was fine and the assembly path was not, one law with two answers. A file
/// name is not required to be an identifier; a symbol is.
fn appendSymbolBytes(out: *std.ArrayList(u8), alloc: std.mem.Allocator, text: []const u8) !void {
    for (text) |c| {
        const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or c == '_';
        try out.append(alloc, if (ok) c else '_');
    }
}

/// THE MANGLING LAW, applied. `home` is a dotted home path, `name` a relation
/// spelling. Caller owns the result.
pub fn homeSymbol(alloc: std.mem.Allocator, home: []const u8, name: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);
    try out.appendSlice(alloc, "idol_");
    try appendSymbolBytes(&out, alloc, home);
    try out.appendSlice(alloc, "__");
    try appendSymbolBytes(&out, alloc, name);
    return out.toOwnedSlice(alloc);
}

/// THE LAW AND ITS TWO EXEMPTIONS, IN ONE PLACE, FOR ONE RELATION.
///
/// `homeSymbol` above is the STRING. This is the DECISION of whether a relation
/// gets it, and it exists because the decision was about to be made twice: once
/// in `dnir_lower` (which names every definition and every same-home callee) and
/// once in `main` (which names the process entry for `-Wl,-e` and for the f64
/// exit coercion). Two copies of an exemption list is how a definer and a caller
/// stop agreeing, which is the exact failure this whole law exists to prevent.
///
///   * `foreign` — the name a FOREIGN BOUNDARY declares, from `@ffi(n)` or
///     `@comp.c.export(n)`. At a foreign boundary the name is not ours to
///     choose: the declaration IS the name. HPLS §34 — internal ABI is
///     realization; only foreign boundaries require foreign ABI.
///   * `main` — the process entry, whose name belongs to the C runtime.
///
/// Nothing else. In particular "the program has one file" is NOT an exemption:
/// a law with a special case for small programs stops being true exactly when a
/// second file arrives.
///
/// A NULL HOME IS THE ONE HOLE, AND IT IS NAMED RATHER THAN HIDDEN. The home is
/// derived from the module's path (`homeOfPath`), so it is absent only where
/// there is no path at all — a graph built in a unit test from a literal AST.
/// Such a module is never linked against another, so the bare name cannot
/// collide with anything; every path that reaches a real object has a path and
/// therefore a home. `docs/cross-home-identity.md` §5 records the OTHER half of
/// this — that the home a path yields is only stable where a project root is
/// detectable — and that half is `place`'s, not this function's.
pub fn relationSymbol(
    alloc: std.mem.Allocator,
    home: ?[]const u8,
    name: []const u8,
    foreign: ?[]const u8,
) ![]const u8 {
    if (foreign) |declared| return alloc.dupe(u8, declared);
    if (std.mem.eql(u8, name, "main")) return alloc.dupe(u8, "main");
    const h = home orelse return alloc.dupe(u8, name);
    if (h.len == 0) return alloc.dupe(u8, name);
    return homeSymbol(alloc, h, name);
}

test "home_resolve: homeOfPath drops search roots and keeps the home chain" {
    const alloc = std.testing.allocator;
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const cases = [_]struct { path: []const u8, want: []const u8 }{
        .{ .path = "lib/compiler/lexer.id", .want = "compiler.lexer" },
        .{ .path = "compiler/lexer.id", .want = "compiler.lexer" },
        .{ .path = "./lib/compiler/bind.id", .want = "compiler.bind" },
        .{ .path = "probe.id", .want = "probe" },
        // `examples` is an ordinary directory, NOT a search root — the four
        // roots are where the compiler LOOKS, and nobody passes `-Iexamples`.
        // The home therefore keeps it, and that is the answer, not a wart.
        .{ .path = "examples/boring/primes.id", .want = "examples.boring.primes" },
    };
    for (cases) |c| {
        const got = try homeOfPath(alloc, io, c.path);
        defer alloc.free(got);
        try std.testing.expectEqualStrings(c.want, got);
    }
}

test "home_resolve: lexical parents do not become home components" {
    const alloc = std.testing.allocator;
    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const canonical = try homeOfPath(alloc, io, "right/probe.id");
    defer alloc.free(canonical);
    const parent = try homeOfPath(alloc, io, "left/../right/probe.id");
    defer alloc.free(parent);
    try std.testing.expectEqualStrings(canonical, parent);
    try std.testing.expectEqualStrings("right.probe", parent);

    try std.testing.expectError(error.HomePathEscape, homeOfPath(alloc, io, "../../escape.id"));
    try std.testing.expectError(error.HomePathEscape, homeOfPath(alloc, io, "/../../escape.id"));

    // Damage control: deleting the parent token leaves the cancelled component
    // alive and therefore names another home.
    const damaged = try homeOfPath(alloc, io, "left/right/probe.id");
    defer alloc.free(damaged);
    try std.testing.expect(!std.mem.eql(u8, parent, damaged));
}

test "home_resolve: the symbol is a function of home AND name" {
    const alloc = std.testing.allocator;
    const a = try homeSymbol(alloc, "compiler.record", "field");
    defer alloc.free(a);
    const b = try homeSymbol(alloc, "probe.mysym", "field");
    defer alloc.free(b);
    try std.testing.expectEqualStrings("idol_compiler_record__field", a);
    // THE POINT OF THE LAW: same relation spelling, different home, different
    // symbol. Measured `ld -r` refuses the bare-name pair with `duplicate
    // symbol '_field'`, so this inequality is the link becoming possible.
    try std.testing.expect(!std.mem.eql(u8, a, b));
}

test "home_resolve: the law has exactly two exemptions" {
    const alloc = std.testing.allocator;
    // The ordinary case: identity is `(home, name)`.
    const ordinary = try relationSymbol(alloc, "compiler.record", "field", null);
    defer alloc.free(ordinary);
    try std.testing.expectEqualStrings("idol_compiler_record__field", ordinary);

    // EXEMPTION 1 — the process entry. `main` belongs to the C runtime, in
    // every home, including a home that also declares ordinary relations.
    const entry = try relationSymbol(alloc, "compiler.host", "main", null);
    defer alloc.free(entry);
    try std.testing.expectEqualStrings("main", entry);

    // EXEMPTION 2 — a foreign boundary. The declaration IS the name, and it
    // wins over the home even for a relation the home would otherwise mangle.
    const foreign = try relationSymbol(alloc, "compiler.lexer", "tokenize", "duo_lexer_tokenize");
    defer alloc.free(foreign);
    try std.testing.expectEqualStrings("duo_lexer_tokenize", foreign);

    // NOT AN EXEMPTION — "the program has one file". A one-file program's
    // relations are still `(home, name)`; the home is just short.
    const one_file = try relationSymbol(alloc, "probe", "field", null);
    defer alloc.free(one_file);
    try std.testing.expectEqualStrings("idol_probe__field", one_file);
    try std.testing.expect(!std.mem.eql(u8, one_file, ordinary));

    // The named hole: no path, no home, no collision to protect against.
    const homeless = try relationSymbol(alloc, null, "field", null);
    defer alloc.free(homeless);
    try std.testing.expectEqualStrings("field", homeless);

    // A FILE NAME IS NOT REQUIRED TO BE AN IDENTIFIER; A SYMBOL IS.
    // `scripts/gatecap-probe.id` is in the corpus, and its home's hyphen made
    // `--target native-asm` emit `.globl _idol_odd-name__f`, which the
    // assembler refuses. Object emission accepted it, so one law had two
    // answers depending on the emit mode.
    const hyphen = try relationSymbol(alloc, "scripts.gatecap-probe", "f", null);
    defer alloc.free(hyphen);
    try std.testing.expectEqualStrings("idol_scripts_gatecap_probe__f", hyphen);

    // The method spelling's dot is the same case, one level in.
    const method = try relationSymbol(alloc, "pkg.vec", "Vec.xplus", null);
    defer alloc.free(method);
    try std.testing.expectEqualStrings("idol_pkg_vec__Vec_xplus", method);
}

test "home_resolve: a home name cannot exceed the path buffer" {
    var buf: [8]u8 = undefined;
    try std.testing.expect(homeAsPath(&buf, "abcdefghij") == null);
    try std.testing.expect(homeAsPath(&buf, "") == null);
    try std.testing.expectEqualStrings("a/b", homeAsPath(&buf, "a.b").?);
}
