/// Attribute parsing for @test.*, @build.*, @time, @bench, and related
/// debugging/benchmark annotations.
///
/// EPOCH 2: every predicate here answers a question that wants asked
/// of the graph instead. See `docs/directive_erasure.md` for the per-directive
/// edge fact each one is standing in for, and the order in which they go.
/// Do not add new names here — add the fact to its owning relation.
const std = @import("std");
const ast = @import("ast.zig");
const meta_module = @import("meta_module.zig");

pub const ParseError = error{ InvalidDirective, OutOfMemory };

pub const ArgMap = struct {
    entries: std.StringHashMapUnmanaged([]const u8) = .{},

    pub fn deinit(self: *ArgMap, alloc: std.mem.Allocator) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            alloc.free(entry.value_ptr.*);
        }
        self.entries.deinit(alloc);
    }

    pub fn get(self: *const ArgMap, key: []const u8) ?[]const u8 {
        return self.entries.get(key);
    }

    pub fn getU32(self: *const ArgMap, key: []const u8, default: u32) u32 {
        const raw = self.entries.get(key) orelse return default;
        return std.fmt.parseInt(u32, raw, 10) catch default;
    }
};

/// Parsed options for a test/bench function annotation.
pub const TestOptions = struct {
    name: []const u8,
    skip: bool = false,
    only: bool = false,
    flaky: bool = false,
    should_panic: bool = false,
    bench: bool = false,
    time: bool = false,
    tag: ?[]const u8 = null,
    message: ?[]const u8 = null,
    timeout_ms: ?u32 = null,
    iterations: u32 = 1,
    warmup: u32 = 0,
};

/// `@comp.c.emit`, `@comp.c.include`, … — C interface metaprogramming under the
/// `@` prefix, in EVERY spelling rather than in the six that were written here.
///
/// THIS FUNCTION USED TO COMPARE AGAINST SIX SHORT LITERALS, and that is the
/// defect the whole file now guards against. `@comp.c.emit` — the CANONICAL
/// form, the one `parser.zig:warnDeprecatedAtQualified` tells you to write —
/// failed all six compares, fell through to `validateModuleDirective`, and was
/// rejected as `unknown module directive '@comp.c.emit'`. `sema.zig:2619`
/// patched around it by calling two MORE predicates alongside this one, which
/// is the same mistake one level up: three predicates that must be kept in
/// agreement instead of one that cannot disagree with itself.
///
/// `resolveBuiltin` is the alias table, and the table is the only place the set
/// of spellings is written down. Reading it answers for all twenty-eight at
/// once, so there is nothing left for the next caller to forget.
///
/// `c.link` is deliberately NOT in the set: it was absent from the six literals
/// this replaces, and widening the predicate is a separate ruling from
/// normalising it.
pub fn isCInterfaceDirective(name: []const u8) bool {
    const internal = meta_module.resolveBuiltin(name) orelse
        // `@cinclude` is the one C-interface spelling with no table entry.
        return std.mem.eql(u8, name, "cinclude");
    return std.mem.eql(u8, internal, "__emit") or
        std.mem.eql(u8, internal, "__c_include") or
        std.mem.eql(u8, internal, "__c_import") or
        std.mem.eql(u8, internal, "__c_export") or
        std.mem.eql(u8, internal, "__c_type") or
        std.mem.eql(u8, internal, "__c_call");
}

/// True when `@c.emit(...)` argument text is a raw C string/bracket literal,
/// not a Duo expression such as `@comp.expand(...)`.
pub fn isRawCEmitLiteral(raw: []const u8) bool {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len >= 4 and std.mem.startsWith(u8, trimmed, "[[")) return true;
    if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') return true;
    if (trimmed.len >= 2 and trimmed[0] == '\'' and trimmed[trimmed.len - 1] == '\'') return true;
    return false;
}

/// Strip delimiters from `@c.emit(...)` / `@c.include(...)` / `@c.import(...)` argument text.
pub fn extractCRawCode(raw: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len >= 4 and std.mem.startsWith(u8, trimmed, "[[") and std.mem.endsWith(u8, trimmed, "]]")) {
        return std.mem.trim(u8, trimmed[2 .. trimmed.len - 2], " \t\r\n");
    }
    if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
        return trimmed[1 .. trimmed.len - 1];
    }
    if (trimmed.len >= 2 and trimmed[0] == '\'' and trimmed[trimmed.len - 1] == '\'') {
        return trimmed[1 .. trimmed.len - 1];
    }
    return trimmed;
}

/// Extract and unescape @c.emit raw code. Uses the provided allocator
/// for the unescaped buffer if unescaping is needed.
pub fn extractAndUnescapeCRawCode(alloc: std.mem.Allocator, raw: []const u8) ![]const u8 {
    const extracted = extractCRawCode(raw);
    return unescapeCRawCode(alloc, extracted);
}

/// Unescape common Lua string escape sequences in @c.emit raw code.
/// The parser stores the raw source text; we need to convert \\\" -> " and \\\\ -> \\.
pub fn unescapeCRawCode(alloc: std.mem.Allocator, raw: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, raw, '\\') == null) return raw;
    var buf = try alloc.alloc(u8, raw.len);
    var j: usize = 0;
    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] == '\\' and i + 1 < raw.len) {
            switch (raw[i + 1]) {
                // Only unescape \\" -> " and \\\\ -> \\ — these are the Lua
                // string escapes that interfere with C code emission.
                // Leave \n, \t, \r, etc. as-is — they're valid C escapes.
                '"' => {
                    buf[j] = '"';
                    i += 2;
                    j += 1;
                },
                '\\' => {
                    buf[j] = '\\';
                    i += 2;
                    j += 1;
                },
                else => {
                    buf[j] = raw[i];
                    i += 1;
                    j += 1;
                },
            }
        } else {
            buf[j] = raw[i];
            i += 1;
            j += 1;
        }
    }
    return buf[0..j];
}

pub fn attrHasPrefix(attr: ast.Attribute, prefix: []const u8) bool {
    return std.mem.startsWith(u8, attr.name, prefix);
}

pub fn isTestDirective(name: []const u8) bool {
    return std.mem.eql(u8, name, "test") or std.mem.startsWith(u8, name, "test.");
}

pub fn isBuildDirective(name: []const u8) bool {
    return std.mem.eql(u8, name, "build") or std.mem.startsWith(u8, name, "build.");
}

pub fn isTimeDirective(name: []const u8) bool {
    return std.mem.eql(u8, name, "time") or std.mem.startsWith(u8, name, "time.");
}

pub fn isBenchDirective(name: []const u8) bool {
    return std.mem.eql(u8, name, "bench") or std.mem.startsWith(u8, name, "bench.");
}

pub fn isTraceDirective(name: []const u8) bool {
    return std.mem.eql(u8, name, "trace") or std.mem.startsWith(u8, name, "trace.");
}

pub fn isDebugDirective(name: []const u8) bool {
    return std.mem.eql(u8, name, "debug") or
        std.mem.startsWith(u8, name, "debug.") or
        isTraceDirective(name);
}

pub fn attrsHaveDebug(attrs: []const ast.Attribute) bool {
    for (attrs) |attr| {
        if (isDebugDirective(attr.name)) return true;
    }
    return false;
}

/// Whether this attribute marks a function as a test case (including @bench on tests).
pub fn attrsMarkTest(attrs: []const ast.Attribute) bool {
    for (attrs) |attr| {
        if (isTestDirective(attr.name)) return true;
        if (isBenchDirective(attr.name)) return true;
    }
    return false;
}

pub fn attrsWantBench(attrs: []const ast.Attribute) bool {
    for (attrs) |attr| {
        if (isBenchDirective(attr.name)) return true;
        if (attrHasPrefix(attr, "test.bench")) return true;
    }
    return false;
}

// ── The one place attribute argument text is interpreted ─────────────────────
//
// `ast.Attribute.args` is RAW SOURCE TEXT between the parens. Six consumers
// used to re-parse it and each guessed at a different syntax: `parseInt` on the
// whole string, `mem.eql(args, "false")`, `indexOf(args, "cuda")`,
// `indexOf(raw, ".metal")`. The guesses disagreed with each other and with the
// corpus — see the migrated call sites for the four bugs that produced.
//
// One tokenizer answers all of it. `attrArgs` is the POSITIONAL view
// (`@device(.metal)`, `@align(8)`, `@derive(Eq, Ord)`); `parseAttrArgs` is the
// MAP view (`@build.exe{ name = "app" }`) and is itself built on the tokenizer.
// Nothing outside this file may look at `attr.args` and decide what it means.

/// One positional argument, split at a comma that is not inside quotes or
/// brackets.
pub const AttrArg = struct {
    /// Trimmed, still carrying its quotes if the source wrote any.
    raw: []const u8,
    /// One layer of `"` / `'` quoting removed. A quoted argument is verbatim:
    /// nothing inside the quotes is trimmed.
    text: []const u8,
    quoted: bool,

    /// The enum-case spelling the corpus actually uses: `.metal` and `metal`
    /// and `"metal"` all read as `metal`. Compare the WHOLE result — a
    /// substring test here is what made `@device("cuda_helper")` a GPU target.
    pub fn tag(self: AttrArg) []const u8 {
        if (!self.quoted and self.text.len >= 2 and self.text[0] == '.') return self.text[1..];
        return self.text;
    }
};

/// A malformed migration attribute must stop before its raw spelling reaches
/// a C, Wasm, object, or linker projection. This quarantines compatibility
/// syntax only: `@` remains the world accessor, and this check publishes no
/// foreign relation, symbol identity, ABI, ownership, or lifetime fact.
pub const BoundaryAttributeError = struct {
    name: []const u8,
    reason: []const u8,
};

fn isCKeyword(name: []const u8) bool {
    const keywords = [_][]const u8{
        "auto",         "break",      "case",           "char",          "const",
        "continue",     "default",    "do",             "double",        "else",
        "enum",         "extern",     "float",          "for",           "goto",
        "if",           "inline",     "int",            "long",          "register",
        "restrict",     "return",     "short",          "signed",        "sizeof",
        "static",       "struct",     "switch",         "typedef",       "union",
        "unsigned",     "void",       "volatile",       "while",         "_Alignas",
        "_Alignof",     "_Atomic",    "_Bool",          "_Complex",      "_Generic",
        "_Imaginary",   "_Noreturn",  "_Static_assert", "_Thread_local", "_BitInt",
        "_Decimal32",   "_Decimal64", "_Decimal128",    "alignas",       "alignof",
        "bool",         "constexpr",  "false",          "nullptr",       "static_assert",
        "thread_local", "true",       "typeof",         "typeof_unqual",
    };
    for (keywords) |keyword| {
        if (std.mem.eql(u8, name, keyword)) return true;
    }
    return false;
}

fn isCTransportName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!std.ascii.isAlphabetic(name[0]) and name[0] != '_') return false;
    for (name[1..]) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_') return false;
    }
    // `asm` is a compiler extension rather than ISO C. Admitting it would make
    // generated source dialect-dependent, so quarantine it at transport ingress.
    return !isCKeyword(name) and !std.mem.eql(u8, name, "asm");
}

fn isPortablePublicCName(name: []const u8) bool {
    // A foreign origin may already own a leading-underscore symbol (`_Exit`).
    // Idol must not mint a public C export in the implementation namespace.
    return name.len > 0 and std.ascii.isAlphabetic(name[0]) and isCTransportName(name);
}

fn isQuotedCIdentifier(raw: ?[]const u8, public_export: bool) bool {
    const source = std.mem.trim(u8, raw orelse return false, " \t\r\n");
    if (source.len < 3 or source[0] != '"' or source[source.len - 1] != '"') return false;
    const name = source[1 .. source.len - 1];
    return if (public_export) isPortablePublicCName(name) else isCTransportName(name);
}

fn hasNoAttributeArguments(raw: ?[]const u8) bool {
    return std.mem.trim(u8, raw orelse return true, " \t\r\n").len == 0;
}

fn isCExportMigrationAttribute(name: []const u8) bool {
    return std.mem.eql(u8, name, "c.export") or
        std.mem.eql(u8, name, "comp.c.export");
}

/// Exact compatibility faces admitted at the parser/sema quarantine. This is
/// deliberately not the normalized compiler-directive roster: accepting every
/// alias would silently grow a second language beneath world-only `@`.
pub fn isBoundaryMigrationAttribute(name: []const u8) bool {
    return std.mem.eql(u8, name, "ffi") or
        std.mem.eql(u8, name, "export") or
        isCExportMigrationAttribute(name);
}

/// Validate all boundary compatibility attributes attached to one declaration.
/// Plain `@export` is the existing Wasm export face and receives only arity and
/// ownership-conflict checks. C identifier/keyword policy applies exclusively
/// to `@ffi` and `@c.export`/`@comp.c.export`.
pub fn boundaryAttributeError(
    attrs: []const ast.Attribute,
    fallback_name: ?[]const u8,
) ?BoundaryAttributeError {
    var seen = false;
    var first_ffi = false;
    var first_export = false;
    var first_c_export = false;

    for (attrs) |attr| {
        const is_ffi = std.mem.eql(u8, attr.name, "ffi");
        const is_export = std.mem.eql(u8, attr.name, "export");
        const is_c_export = isCExportMigrationAttribute(attr.name);
        const normalized = meta_module.normalizeCompileAttribute(attr.name);
        const looks_like_boundary = std.mem.eql(u8, normalized, "ffi") or
            std.mem.eql(u8, normalized, "export") or
            std.mem.eql(u8, normalized, "c.export");

        if (!is_ffi and !is_export and !is_c_export) {
            if (looks_like_boundary) return .{
                .name = attr.name,
                .reason = "is not an admitted migration boundary attribute; only exact @ffi, @export, @c.export, and @comp.c.export compatibility faces are quarantined",
            };
            continue;
        }

        if (is_ffi and !isQuotedCIdentifier(attr.args, false)) return .{
            .name = attr.name,
            .reason = "requires exactly one nonempty double-quoted ASCII C identifier",
        };
        if (is_export and !hasNoAttributeArguments(attr.args)) return .{
            .name = attr.name,
            .reason = "accepts no arguments; it is the existing Wasm export compatibility face",
        };
        if (is_c_export and !hasNoAttributeArguments(attr.args) and !isQuotedCIdentifier(attr.args, true)) return .{
            .name = attr.name,
            .reason = "accepts zero or one nonempty double-quoted portable ASCII C identifier",
        };
        if (is_c_export and hasNoAttributeArguments(attr.args)) {
            if (!isPortablePublicCName(fallback_name orelse "")) return .{
                .name = attr.name,
                .reason = "requires a declaration whose implicit symbol is a portable public ASCII C identifier",
            };
        }

        if (seen) {
            const duplicate = (is_ffi and first_ffi) or
                (is_export and first_export) or
                (is_c_export and first_c_export);
            return .{
                .name = attr.name,
                .reason = if (duplicate)
                    "duplicates a migration boundary attribute on this declaration"
                else
                    "conflicts with another migration boundary attribute on this declaration",
            };
        }

        seen = true;
        first_ffi = is_ffi;
        first_export = is_export;
        first_c_export = is_c_export;
    }
    return null;
}

pub const ArgIter = struct {
    src: []const u8,
    pos: usize = 0,

    pub fn next(self: *ArgIter) ?AttrArg {
        while (self.pos < self.src.len) {
            const start = self.pos;
            var i = start;
            var depth: usize = 0;
            var quote: u8 = 0;
            while (i < self.src.len) {
                const c = self.src[i];
                if (quote != 0) {
                    if (c == '\\' and i + 1 < self.src.len) {
                        i += 2;
                        continue;
                    }
                    if (c == quote) quote = 0;
                    i += 1;
                    continue;
                }
                if (c == ',' and depth == 0) break;
                switch (c) {
                    '"', '\'' => quote = c,
                    '(', '[', '{' => depth += 1,
                    ')', ']', '}' => {
                        if (depth > 0) depth -= 1;
                    },
                    else => {},
                }
                i += 1;
            }
            const piece = self.src[start..i];
            self.pos = if (i < self.src.len) i + 1 else self.src.len;
            const arg = normalizeArg(piece);
            if (arg.raw.len == 0) continue;
            return arg;
        }
        return null;
    }
};

fn normalizeArg(piece: []const u8) AttrArg {
    const raw = std.mem.trim(u8, piece, " \t\r\n");
    if (raw.len >= 2 and (raw[0] == '"' or raw[0] == '\'') and raw[raw.len - 1] == raw[0]) {
        return .{ .raw = raw, .text = raw[1 .. raw.len - 1], .quoted = true };
    }
    return .{ .raw = raw, .text = raw, .quoted = false };
}

/// Iterate the positional arguments of an attribute argument list.
pub fn attrArgs(raw: ?[]const u8) ArgIter {
    return .{ .src = raw orelse "" };
}

/// Positional argument `index`, or null when the list is shorter.
pub fn attrArg(raw: ?[]const u8, index: usize) ?AttrArg {
    var it = attrArgs(raw);
    var n: usize = 0;
    while (it.next()) |arg| : (n += 1) {
        if (n == index) return arg;
    }
    return null;
}

/// First positional argument as text, unquoted. `@ffi("memcpy", void, {any})`
/// answers `memcpy`, not the whole argument list.
pub fn attrText(raw: ?[]const u8) ?[]const u8 {
    const arg = attrArg(raw, 0) orelse return null;
    if (arg.text.len == 0) return null;
    return arg.text;
}

/// First positional argument as an enum-case tag. See `AttrArg.tag`.
pub fn attrTag(raw: ?[]const u8) ?[]const u8 {
    const arg = attrArg(raw, 0) orelse return null;
    const t = arg.tag();
    if (t.len == 0) return null;
    return t;
}

/// First positional argument as an integer. `@align( 8 )` answers 8; an
/// exact-text `parseInt` on the untrimmed source answered null.
pub fn attrInt(comptime T: type, raw: ?[]const u8) ?T {
    const t = attrText(raw) orelse return null;
    const body = std.mem.trim(u8, t, " \t\r\n()");
    if (body.len == 0) return null;
    return std.fmt.parseInt(T, body, 10) catch null;
}

/// First positional argument as a boolean. `@arc(false)`, `@arc( false )` and
/// `@arc("false")` are one intent; anything else answers null rather than
/// silently reading as `true`.
pub fn attrFlag(raw: ?[]const u8) ?bool {
    const t = attrText(raw) orelse return null;
    const body = std.mem.trim(u8, t, " \t\r\n");
    if (std.mem.eql(u8, body, "false")) return false;
    if (std.mem.eql(u8, body, "true")) return true;
    return null;
}

pub fn parseAttrArgs(alloc: std.mem.Allocator, raw: ?[]const u8) ParseError!ArgMap {
    var map: ArgMap = .{};
    errdefer map.deinit(alloc);
    const text = raw orelse return map;
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return map;

    // Table literal: { name = "app", src = "main.id", iterations = 1000 }
    if (std.mem.startsWith(u8, trimmed, "{") and std.mem.endsWith(u8, trimmed, "}")) {
        try parseKvArgs(alloc, trimmed[1 .. trimmed.len - 1], &map);
        return map;
    }

    const first = attrArg(trimmed, 0) orelse return map;

    // Quoted string positional: @test("integration")
    if (first.quoted) {
        const key = try alloc.dupe(u8, "name");
        const s = try alloc.dupe(u8, first.text);
        try map.entries.put(alloc, key, s);
        return map;
    }

    // key=value pairs: iterations=1000, warmup=10
    if (topLevelEq(first.raw) != null) {
        try parseKvArgs(alloc, trimmed, &map);
        return map;
    }

    // Bare integer positional (iterations)
    if (std.fmt.parseInt(u32, first.text, 10)) |n| {
        const key = try alloc.dupe(u8, "iterations");
        const val = try std.fmt.allocPrint(alloc, "{d}", .{n});
        try map.entries.put(alloc, key, val);
        return map;
    } else |_| {}

    // Bare identifier positional (tag/name)
    const key = try alloc.dupe(u8, "name");
    const val = try alloc.dupe(u8, first.text);
    try map.entries.put(alloc, key, val);
    return map;
}

/// Index of an `=` that is not inside quotes or brackets.
fn topLevelEq(piece: []const u8) ?usize {
    var i: usize = 0;
    var depth: usize = 0;
    var quote: u8 = 0;
    while (i < piece.len) {
        const c = piece[i];
        if (quote != 0) {
            if (c == '\\' and i + 1 < piece.len) {
                i += 2;
                continue;
            }
            if (c == quote) quote = 0;
            i += 1;
            continue;
        }
        switch (c) {
            '"', '\'' => quote = c,
            '(', '[', '{' => depth += 1,
            ')', ']', '}' => {
                if (depth > 0) depth -= 1;
            },
            '=' => if (depth == 0) return i,
            else => {},
        }
        i += 1;
    }
    return null;
}

fn parseKvArgs(alloc: std.mem.Allocator, text: []const u8, map: *ArgMap) ParseError!void {
    var it = attrArgs(text);
    while (it.next()) |arg| {
        const eq = topLevelEq(arg.raw) orelse continue;
        const key = std.mem.trim(u8, arg.raw[0..eq], " \t");
        const val_raw = std.mem.trim(u8, arg.raw[eq + 1 ..], " \t");
        const val = try unquote(alloc, val_raw);
        const key_dup = try alloc.dupe(u8, key);
        try map.entries.put(alloc, key_dup, val);
    }
}

fn unquote(alloc: std.mem.Allocator, raw: []const u8) ParseError![]const u8 {
    return try alloc.dupe(u8, normalizeArg(raw).text);
}

pub fn parseTestOptions(alloc: std.mem.Allocator, attrs: []const ast.Attribute) ParseError!TestOptions {
    var opts: TestOptions = .{ .name = try alloc.dupe(u8, "test") };
    var args_map: ArgMap = .{};
    defer args_map.deinit(alloc);

    for (attrs) |attr| {
        if (isTimeDirective(attr.name)) opts.time = true;
        if (isBenchDirective(attr.name)) opts.bench = true;

        if (std.mem.eql(u8, attr.name, "test")) {
            // plain @test
        } else if (std.mem.eql(u8, attr.name, "test.skip")) {
            opts.skip = true;
        } else if (std.mem.eql(u8, attr.name, "test.only")) {
            opts.only = true;
        } else if (std.mem.eql(u8, attr.name, "test.flaky")) {
            opts.flaky = true;
        } else if (std.mem.eql(u8, attr.name, "test.should_panic")) {
            opts.should_panic = true;
        } else if (std.mem.eql(u8, attr.name, "test.bench") or std.mem.eql(u8, attr.name, "test.time")) {
            if (std.mem.eql(u8, attr.name, "test.bench")) opts.bench = true;
            if (std.mem.eql(u8, attr.name, "test.time")) opts.time = true;
        } else if (std.mem.startsWith(u8, attr.name, "test.")) {
            const suffix = attr.name["test.".len..];
            if (std.mem.eql(u8, suffix, "unit") or std.mem.eql(u8, suffix, "integration") or std.mem.eql(u8, suffix, "e2e")) {
                opts.tag = try alloc.dupe(u8, suffix);
            }
        }

        if (attr.args) |raw| {
            args_map.deinit(alloc);
            args_map = .{};
            args_map = try parseAttrArgs(alloc, raw);
            if (args_map.get("name")) |n| {
                alloc.free(opts.name);
                opts.name = try alloc.dupe(u8, n);
            }
            if (args_map.get("tag")) |t| {
                if (opts.tag) |old| alloc.free(old);
                opts.tag = try alloc.dupe(u8, t);
            }
            if (args_map.get("message")) |m| {
                if (opts.message) |old| alloc.free(old);
                opts.message = try alloc.dupe(u8, m);
            }
            if (args_map.get("timeout")) |t| opts.timeout_ms = std.fmt.parseInt(u32, t, 10) catch null;
            if (args_map.get("timeout_ms")) |t| opts.timeout_ms = std.fmt.parseInt(u32, t, 10) catch null;
            opts.iterations = args_map.getU32("iterations", opts.iterations);
            opts.warmup = args_map.getU32("warmup", opts.warmup);
        }
    }

    if (opts.bench and opts.iterations == 1) opts.iterations = 1000;
    if (opts.bench) opts.time = true;
    return opts;
}

/// `@device(.auto)` / `@device(.metal)` / `@device(cpu)` — one enum case.
/// This used to substring-search the raw text for `".metal"`, which made
/// `@device(x.metal.helper)` a Metal target. `attrTag` compares the whole
/// argument, and `deviceFromTag` is the single spelling table both this and
/// `semantic_algebra` read.
pub fn parseDeviceTarget(args: ?[]const u8) ast.DeviceTarget {
    return deviceFromTag(attrTag(args) orelse return .auto) orelse .auto;
}

/// The device spelling table. Null means "not a device this compiler knows",
/// which is what `@device("cuda_helper")` must answer.
pub fn deviceFromTag(tag: []const u8) ?ast.DeviceTarget {
    if (std.mem.eql(u8, tag, "metal")) return .metal;
    if (std.mem.eql(u8, tag, "cuda")) return .cuda;
    if (std.mem.eql(u8, tag, "webgpu")) return .webgpu;
    if (std.mem.eql(u8, tag, "wasm")) return .wasm;
    if (std.mem.eql(u8, tag, "tpu")) return .tpu;
    if (std.mem.eql(u8, tag, "cpu")) return .cpu;
    if (std.mem.eql(u8, tag, "auto")) return .auto;
    return null;
}

/// True when the device runs the body on a GPU. One answer, so the effect set
/// and the hardware set cannot disagree the way they did.
pub fn deviceIsGpu(target: ast.DeviceTarget) bool {
    return switch (target) {
        .metal, .cuda, .webgpu => true,
        .none, .cpu, .auto, .wasm, .tpu => false,
    };
}

pub fn parseUnrollCount(args: ?[]const u8) ?u32 {
    return attrInt(u32, args);
}

/// Apply ML-related function attributes from `@device`, `@autodiff`, etc.
pub fn applyMlFuncAttrs(attrs: []const ast.Attribute, fb: *ast.FuncBody) void {
    for (attrs) |attr| {
        const norm = meta_module.normalizeCompileAttribute(attr.name);
        if (std.mem.eql(u8, norm, "device")) {
            fb.device_target = parseDeviceTarget(attr.args);
        } else if (std.mem.eql(u8, norm, "autodiff")) {
            fb.autodiff = true;
        } else if (std.mem.eql(u8, norm, "differentiable")) {
            fb.differentiable = true;
            fb.autodiff = true;
        } else if (std.mem.eql(u8, norm, "profile")) {
            fb.profile_attr = true;
        } else if (std.mem.eql(u8, norm, "unroll")) {
            fb.unroll_count = parseUnrollCount(attr.args);
        } else if (std.mem.eql(u8, norm, "compile.only")) {
            fb.is_compile_only = true;
        } else if (std.mem.eql(u8, norm, "inline")) {
            fb.use_force_always_inline = true;
        }
    }
}

pub fn deviceTargetName(target: ast.DeviceTarget) []const u8 {
    return switch (target) {
        .none => "none",
        .cpu => "cpu",
        .auto => "auto",
        .metal => "metal",
        .cuda => "cuda",
        .webgpu => "webgpu",
        .wasm => "wasm",
        .tpu => "tpu",
    };
}

pub fn validateFuncAttrs(attrs: []const ast.Attribute) ?[]const u8 {
    for (attrs) |attr| {
        if (isTestDirective(attr.name) or isTimeDirective(attr.name) or isBenchDirective(attr.name) or isDebugDirective(attr.name)) {
            continue;
        }
        const norm = meta_module.normalizeCompileAttribute(attr.name);
        if (std.mem.eql(u8, norm, "inline") or
            std.mem.eql(u8, norm, "cold") or
            std.mem.eql(u8, norm, "hot") or
            std.mem.eql(u8, norm, "noinline") or
            std.mem.eql(u8, norm, "export") or
            std.mem.eql(u8, norm, "c.export") or
            std.mem.eql(u8, norm, "ffi") or
            std.mem.eql(u8, norm, "derive") or
            std.mem.eql(u8, norm, "arc") or
            std.mem.eql(u8, norm, "nopanic") or
            std.mem.eql(u8, norm, "packed") or
            std.mem.eql(u8, norm, "raw") or
            std.mem.eql(u8, norm, "align") or
            std.mem.eql(u8, norm, "deprecated") or
            std.mem.eql(u8, norm, "device") or
            std.mem.eql(u8, norm, "autodiff") or
            std.mem.eql(u8, norm, "differentiable") or
            std.mem.eql(u8, norm, "profile") or
            std.mem.eql(u8, norm, "unroll") or
            std.mem.eql(u8, norm, "compile.only") or
            std.mem.eql(u8, norm, "pure") or
            std.mem.eql(u8, norm, "noalloc") or
            std.mem.eql(u8, norm, "flatten") or
            std.mem.eql(u8, norm, "noreturn") or
            std.mem.eql(u8, norm, "restrict") or
            std.mem.eql(u8, norm, "target") or
            std.mem.eql(u8, norm, "section") or
            std.mem.eql(u8, norm, "consteval") or
            std.mem.startsWith(u8, norm, "concurrent") or
            std.mem.startsWith(u8, norm, "implements"))
        {
            continue;
        }
        if (isBuildDirective(attr.name)) {
            return "build directives belong at module scope (@build.project, @build.exe, …), not on functions";
        }
        return attr.name;
    }
    return null;
}

pub fn validateModuleDirective(attr: ast.Attribute) ?[]const u8 {
    if (isBuildDirective(attr.name)) {
        const known = std.mem.eql(u8, attr.name, "build.project") or
            std.mem.eql(u8, attr.name, "build.exe") or
            std.mem.eql(u8, attr.name, "build.lib") or
            std.mem.eql(u8, attr.name, "build.test") or
            std.mem.eql(u8, attr.name, "build.run") or
            std.mem.eql(u8, attr.name, "build.clean") or
            std.mem.eql(u8, attr.name, "build.bench") or
            std.mem.eql(u8, attr.name, "build.command") or
            std.mem.eql(u8, attr.name, "build.stage") or
            std.mem.eql(u8, attr.name, "build.fmt") or
            std.mem.eql(u8, attr.name, "build.check");
        if (!known) return attr.name;
        return null;
    }
    if (isDebugDirective(attr.name)) return null;
    if (meta_module.isMetaAttribute(attr.name)) return null;
    if (std.mem.eql(u8, attr.name, "specialize")) return null;
    return attr.name;
}

test "directives: parse table args" {
    const alloc = std.testing.allocator;
    var map = try parseAttrArgs(alloc, "{ name = \"app\", iterations = 42 }");
    defer map.deinit(alloc);
    try std.testing.expectEqualStrings("app", map.get("name").?);
    try std.testing.expectEqualStrings("42", map.get("iterations").?);
}

test "directives: positional split respects quotes and brackets" {
    var it = attrArgs("\"duo_read\", i64, {i64, str, i64}");
    const a = it.next().?;
    try std.testing.expectEqualStrings("duo_read", a.text);
    try std.testing.expect(a.quoted);
    try std.testing.expectEqualStrings("i64", it.next().?.text);
    try std.testing.expectEqualStrings("{i64, str, i64}", it.next().?.text);
    try std.testing.expect(it.next() == null);
}

test "directives: attrTag reads every device spelling the corpus writes" {
    try std.testing.expectEqualStrings("metal", attrTag(".metal").?);
    try std.testing.expectEqualStrings("cpu", attrTag("cpu").?);
    try std.testing.expectEqualStrings("auto", attrTag("\"auto\"").?);
    // Positive control: a longer name is NOT the device it contains.
    try std.testing.expect(deviceFromTag(attrTag("cuda_helper").?) == null);
    try std.testing.expectEqual(ast.DeviceTarget.cuda, deviceFromTag(attrTag(".cuda").?).?);
}

test "directives: attrInt and attrFlag ignore surrounding noise" {
    try std.testing.expectEqual(@as(usize, 8), attrInt(usize, " 8 ").?);
    try std.testing.expectEqual(@as(u32, 4), parseUnrollCount("(4)").?);
    try std.testing.expect(attrInt(u32, "nope") == null);
    try std.testing.expectEqual(false, attrFlag(" false ").?);
    try std.testing.expectEqual(false, attrFlag("\"false\"").?);
    try std.testing.expectEqual(true, attrFlag("true").?);
    // Neither true nor false: answer null rather than defaulting to on.
    try std.testing.expect(attrFlag("maybe") == null);
    try std.testing.expect(attrFlag(null) == null);
}

test "directives: C boundary migration symbols are exact quoted identifiers" {
    const accepted = [_]ast.Attribute{
        .{ .name = "ffi", .args = "\"puts\"" },
        .{ .name = "ffi", .args = "\"idol_9\"" },
        .{ .name = "ffi", .args = "\"_Exit\"" },
        .{ .name = "c.export", .args = null },
        .{ .name = "comp.c.export", .args = "\"idol_add\"" },
    };
    for (accepted) |attr| try std.testing.expect(boundaryAttributeError(&.{attr}, "idol_decl") == null);

    const rejected = [_]ast.Attribute{
        .{ .name = "ffi", .args = null },
        .{ .name = "ffi", .args = "\"\"" },
        .{ .name = "ffi", .args = "'puts'" },
        .{ .name = "ffi", .args = "\"9puts\"" },
        .{ .name = "ffi", .args = "\"put-s\"" },
        .{ .name = "ffi", .args = "\"switch\"" },
        .{ .name = "ffi", .args = "\"idé\"" },
        .{ .name = "ffi", .args = "\"puts\", \"fputs\"" },
        .{ .name = "c.export", .args = "\"_idol9\"" },
        .{ .name = "c.export", .args = "\"static\"" },
        .{ .name = "comp.c.export", .args = "\"idol.add\"" },
        .{ .name = "meta.c.export", .args = "\"idol_add\"" },
        .{ .name = "compiler.c.export", .args = "\"idol_add\"" },
        .{ .name = "comp.ffi", .args = "\"idol_add\"" },
    };
    for (rejected) |attr| try std.testing.expect(boundaryAttributeError(&.{attr}, "idol_decl") != null);

    const implicit = ast.Attribute{ .name = "c.export", .args = null };
    try std.testing.expect(boundaryAttributeError(&.{implicit}, "static") != null);
    try std.testing.expect(boundaryAttributeError(&.{implicit}, null) != null);
}

test "directives: plain export keeps Wasm naming law separate from C policy" {
    const wasm_export = ast.Attribute{ .name = "export", .args = null };
    // Leading underscore is a current Wasm-facing parser/codegen control. A C
    // public export with this fallback is refused by the separate row below.
    try std.testing.expect(boundaryAttributeError(&.{wasm_export}, "_api") == null);
    const c_export = ast.Attribute{ .name = "c.export", .args = null };
    try std.testing.expect(boundaryAttributeError(&.{c_export}, "_api") != null);
    const export_with_name = ast.Attribute{ .name = "export", .args = "\"_api\"" };
    try std.testing.expect(boundaryAttributeError(&.{export_with_name}, "ignored") != null);
}

test "directives: migration boundary attributes reject duplicate and conflicting owners" {
    const duplicate = [_]ast.Attribute{
        .{ .name = "c.export", .args = null },
        .{ .name = "comp.c.export", .args = "\"idol_add\"" },
    };
    const duplicate_error = boundaryAttributeError(&duplicate, "idol_add").?;
    try std.testing.expect(std.mem.indexOf(u8, duplicate_error.reason, "duplicates") != null);

    const conflict = [_]ast.Attribute{
        .{ .name = "ffi", .args = "\"idol_add\"" },
        .{ .name = "export", .args = null },
    };
    const conflict_error = boundaryAttributeError(&conflict, "idol_add").?;
    try std.testing.expect(std.mem.indexOf(u8, conflict_error.reason, "conflicts") != null);
}

test "directives: a comma inside a value no longer splits the map" {
    const alloc = std.testing.allocator;
    var map = try parseAttrArgs(alloc, "{ name = \"a, b\", iterations = 3 }");
    defer map.deinit(alloc);
    try std.testing.expectEqualStrings("a, b", map.get("name").?);
    try std.testing.expectEqual(@as(u32, 3), map.getU32("iterations", 0));
}

test "directives: dotted test names" {
    try std.testing.expect(isTestDirective("test.unit"));
    try std.testing.expect(isBuildDirective("build.exe"));
    try std.testing.expect(attrsWantBench(&[_]ast.Attribute{.{ .name = "test.bench", .args = null }}));
}

test "directives: test options bench defaults" {
    const alloc = std.testing.allocator;
    const attrs = [_]ast.Attribute{.{ .name = "bench", .args = "{ iterations = 5 }" }};
    const opts = try parseTestOptions(alloc, &attrs);
    defer {
        alloc.free(opts.name);
        if (opts.tag) |t| alloc.free(t);
        if (opts.message) |m| alloc.free(m);
    }
    try std.testing.expect(opts.bench);
    try std.testing.expectEqual(@as(u32, 5), opts.iterations);
}

test "directives: the C interface answers to every spelling, not the six short ones" {
    // The regression this pins: `@comp.c.emit` — the CANONICAL spelling — used
    // to fail this predicate and be rejected as an unknown module directive,
    // while `@c.emit` passed. One operation cannot have two answers here.
    const one_operation = [_][2][]const u8{
        .{ "c.emit", "comp.c.emit" },
        .{ "c.include", "comp.c.include" },
        .{ "c.import", "comp.c.import" },
        .{ "c.export", "comp.c.export" },
        .{ "c.type", "comp.c.type" },
        .{ "c.call", "comp.c.call" },
    };
    for (one_operation) |pair| {
        try std.testing.expect(isCInterfaceDirective(pair[0]));
        try std.testing.expect(isCInterfaceDirective(pair[1]));
    }
    // `@meta.*` and `@compiler.*` are deprecated spellings of the same
    // operations, not different ones — they were invisible here too.
    try std.testing.expect(isCInterfaceDirective("meta.c.emit"));
    try std.testing.expect(isCInterfaceDirective("compiler.c.export"));
    try std.testing.expect(isCInterfaceDirective("comp.emit"));
    try std.testing.expect(isCInterfaceDirective("emit"));
    // `@cinclude` has no alias-table entry; the literal tail is what covers it.
    try std.testing.expect(isCInterfaceDirective("cinclude"));
    // NEGATIVE CONTROLS. A predicate that answers true for everything proves
    // nothing, which is how the six-literal version looked green for months.
    try std.testing.expect(!isCInterfaceDirective("comp.map"));
    try std.testing.expect(!isCInterfaceDirective("c.link"));
    try std.testing.expect(!isCInterfaceDirective("c.emitx"));
    try std.testing.expect(!isCInterfaceDirective("test"));
}

test "directives: isRawCEmitLiteral distinguishes raw C from expressions" {
    try std.testing.expect(isRawCEmitLiteral("\"int x = 1;\""));
    try std.testing.expect(isRawCEmitLiteral("[[ static inline void f() {} ]]"));
    try std.testing.expect(!isRawCEmitLiteral("@comp.expand(\"HasXY\", TouchApi)"));
    try std.testing.expect(!isRawCEmitLiteral("__metaexpand(\"HasXY\", TouchApi)"));
}
