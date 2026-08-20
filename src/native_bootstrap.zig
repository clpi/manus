//! Closed bootstrap application faces for direct native lowering (GAP-155).
//!
//! LEGACY MIGRATION CLOSURE — realization lane only. Every face recognized here
//! is either already canonical subject-first syntax or an explicitly foreign-only
//! bridge awaiting deletion. Nothing in this module is admissible as permanent
//! Idol semantics.
//!
//! Canonical subject-first (graph must own relation/target before bridge death):
//!   stdin:read()        host stdin endpoint
//!   stdout:write(text)  host stdout egress
//!   text:len()          length relation on subject
//!   text:has(needle)    membership via nil refinement
//!   text:sub(a,b)       slice relation on subject
//!   text:read()         read relation on path-shaped subject
//!   text:tail()         tail relation on subject
//!   xs:any((x) p)       existential relation on a collection subject
//!
//! `xs:any(…)` IS ON THAT LIST AND THE DEBT IS THE SAME ONE, stated so it is
//! not read as a design: the collection relations resolve in sema and lower in
//! `dnir_lower`, and the graph publishes NO application for them, exactly as it
//! publishes none for `text:len()`. The iteration facts
//! `protocol-projection-one.md` §3 enumerates — source, result pack, body
//! relation, ordering, termination, effects, demand, world — therefore live in
//! `collection_relation.Shape` and in the lowering, which is a weaker home than
//! the graph. Deleting this row means giving `any` a real relation node, and it
//! is the same deletion every other row above is waiting on.
//!
//! Foreign-only namespace spellings (delete when graph publishes exact ids):
//!   string.byte/sub/match/len/char  → subject relations above
//!   mem.alloc/free/zero/read_*/write_*  → demanded place/allocation facts
//!   os.exit/execute                   → process world facts
//!   math.sqrt/sin/...                 → relation + selected target id
//!   gatecap(cmd)                      → command capture (host ingress only)
//!   print(v)                          → host stdout egress (one node with
//!                                       `stdout:write`; recognized everywhere)
//!   to(T)(x)                          → demanded conversion (infer when unique)
//!
//! Ordinary module calls like `observe(41)` are NOT bootstrap. Checked lowering
//! must consume graph application/relation/target ids — never callee spelling.
//!
//! NOTHING HERE IS DECIDED BY A DIRECTORY. It was, for four days, and
//! `docs/transport.md` in the surface repo records what that cost. The short
//! version: `gateTransport` returned true for any path under `gate/`, which set
//! `require_graph_facts = false`, which made `dnir_lower.lowerSubjectCall` skip
//! the CHECKED path even when the graph had published the fact — so
//! `v:scale(7)` was refused in `gate/` and ran at the repo root, one directory
//! apart, same bytes. The waiver is now REQUESTED BY THE FILE (see
//! `gateTransport` below) and the request is part of the bytes, so every
//! spelling of a path that names the same file gets the same law.
const std = @import("std");
const ast = @import("ast.zig");
const subject_home = @import("subject_home.zig");
const collection_relation = @import("collection_relation.zig");
const Expr = ast.Expr;

pub fn receiverLooksStrish(obj: *const Expr) bool {
    return switch (obj.*) {
        .quoted => true,
        .method_call => true,
        .name => true,
        // A RECORD FIELD IS AS STRISH AS A LOCAL, and leaving it out cost the
        // self-hosted lexer.
        //
        // This predicate is a SPELLING test, not a type test — `.name` admits
        // every local of every type, which is far broader than anything `.field`
        // adds. What it did not admit was `self.src`, and that is the receiver
        // the self-hosted compiler is written against:
        //
        //     L: { src: str, pos: i64 }
        //     at: i64 = (self: L)
        //       self.src:byte(self.pos)
        //
        // MEASURED at idol 448f877b, `--emit obj`: `s:byte(i)` on a parameter
        // built, `self.src:len()` on the same field built (`len` is answered
        // above this switch, before any receiver test), and `self.src:byte(...)`
        // was refused `DNB011 … relation: byte missing:
        // unresolved-application-facts`. One method, one receiver shape, and
        // `lib/compiler/lexer.id` has ten such sites — its refusal named
        // `relation: byte` exactly.
        //
        // WHAT THIS DOES AND DOES NOT CLAIM. Recognising the shape here does not
        // teach the graph anything; it stops `OccurrenceBridge` counting the site
        // as a BLOCKING unresolved application, which is the third column in the
        // `FactCoverage` doc comment below and the one the module-wide bail reads.
        // The code emitted is the same bootstrap emit `s:byte(i)` already got.
        //
        // SCORED ON ITS ANSWER, not on whether it built. Two `@comp.c.export`ed
        // relations over `L{src="ABC"}` read through a C driver print `65 66` —
        // 'A' and 'B' at pos 1 and 2 — where the refusal printed nothing.
        // Corpus effect, both sweeps of 817 files: three files move FORWARD to a
        // deeper blocker (`lib/compiler/parser.id`, `lib/bytes.id`,
        // `lib/text/scanner.id`) and zero move backward. That near-zero corpus
        // delta is survivor bias and not evidence of low value: nobody writes
        // what will not compile, and the self-hosted compiler is the corpus that
        // was written anyway.
        .field => true,
        else => false,
    };
}

/// The injected TEST world reached on its own subject — `test:assert(c, m)`.
///
/// This is an application on a world, and it confers no reach that is not
/// already conferred: `subject_home` injects the test world BY FILE STRUCTURE
/// (`*_test.id`, `test_*`, `test/`), and sema refuses the same three lines in a
/// file the world is not injected into — measured: "'assert' is neither a
/// descriptor nor a callable". So by the time lowering sees this shape the file
/// is a test file, and recognizing it here only stops `OccurrenceBridge`
/// counting it as an unresolved fact. `dnir_lower.lowerTestRelation` already
/// answered these calls unconditionally; the module-wide bail is what refused
/// them, which is why `gate/injection_test.id` was the one file under `gate/`
/// that the directory waiver was load-bearing for.
///
/// The roster comes from the world's own declaration, so an edge added there is
/// recognized here with no edit — the mechanism `subject_home` exists to avoid
/// duplicating.
fn testWorldApplication(mc: anytype) bool {
    if (mc.obj.* != .name) return false;
    if (!std.mem.eql(u8, mc.obj.name.ident, "test")) return false;
    return subject_home.homeProvides(.testing, mc.method);
}

fn methodApplication(expr: *const Expr) bool {
    const mc = expr.method_call;
    if (testWorldApplication(mc)) return true;
    // COLLECTION-RELATION-ONE. Asked through `collection_relation.shapeOf` and
    // not by re-testing the spelling here, so this reader and the three others
    // cannot drift about which shapes are collection applications.
    if (collection_relation.shapeOf(expr) != null) return true;
    if (mc.obj.* == .name and std.mem.eql(u8, mc.obj.name.ident, "stdin") and
        std.mem.eql(u8, mc.method, "read") and mc.args.len == 0)
    {
        return true;
    }
    if (mc.obj.* == .name and std.mem.eql(u8, mc.obj.name.ident, "stdin") and
        std.mem.eql(u8, mc.method, "line") and mc.args.len == 0)
    {
        return true;
    }
    if (mc.obj.* == .name and std.mem.eql(u8, mc.obj.name.ident, "stdout") and
        std.mem.eql(u8, mc.method, "write") and mc.args.len == 1)
    {
        return true;
    }
    // `os.env:remove(k)` — THE ENVIRONMENT PROJECTION'S REMOVAL EDGE, the same
    // class as `stdout:write` above: a world projection lowered to a foreign
    // call (`unsetenv`), with no relation in the graph for the application to
    // bind to. `table_apply` converges the bare `env:remove(k)` onto this
    // anchored subject, so one shape is enough here — and the bare face is
    // admitted there only where the program does not bind `env`.
    if (std.mem.eql(u8, mc.method, "remove") and mc.args.len == 1 and
        mc.obj.* == .field and mc.obj.field.obj.* == .name and
        std.mem.eql(u8, mc.obj.field.obj.name.ident, "os") and
        std.mem.eql(u8, mc.obj.field.field, "env"))
    {
        return true;
    }
    if (std.mem.eql(u8, mc.method, "read") and mc.args.len == 0 and receiverLooksStrish(mc.obj)) {
        return true;
    }
    if (std.mem.eql(u8, mc.method, "len") and mc.args.len == 0) return true;
    if (std.mem.eql(u8, mc.method, "to") and mc.args.len == 1 and receiverLooksStrish(mc.obj)) return true;
    if (std.mem.eql(u8, mc.method, "has") and mc.args.len == 1) return true;
    if (std.mem.eql(u8, mc.method, "tail") and mc.args.len == 0 and receiverLooksStrish(mc.obj)) {
        return true;
    }
    if (receiverLooksStrish(mc.obj) or
        (std.mem.eql(u8, mc.method, "sub") and mc.args.len >= 1 and mc.args.len <= 2))
    {
        const string_methods = [_][]const u8{ "sub", "match", "byte", "len", "find", "char", "at" };
        for (string_methods) |method| {
            if (std.mem.eql(u8, mc.method, method)) return true;
        }
    }
    return false;
}

fn printApplication(expr: *const Expr) bool {
    if (expr.* != .call) return false;
    const c = expr.call;
    if (c.func.* != .name) return false;
    return std.mem.eql(u8, c.func.name.ident, "print");
}

fn toApplication(expr: *const Expr) bool {
    return switch (expr.*) {
        .method_call => |mc| std.mem.eql(u8, mc.method, "to") and mc.args.len == 1,
        .call => |c| {
            if (c.func.* != .name or !std.mem.eql(u8, c.func.name.ident, "to")) return false;
            // `faceAsCall` rebuilds subject-first `:to(T)` as `to(subject, T)`.
            return c.args.len == 1 or c.args.len == 2;
        },
        else => false,
    };
}

/// The exact text a module writes to REQUEST the graph-fact waiver.
///
/// Spelled as the directive it should become. When the parser learns
/// `@bootstrap.waive(graph-facts)` for real, the text in every file that
/// carries it does not change — only where this module reads it from.
pub const waiver_request = "@bootstrap.waive(graph-facts)";

/// How far into a file the request may appear. A waiver is a claim the reader
/// of the file has to see, so it belongs in the header with everything else
/// that governs the file. Buried at line 900 it is not a request, it is a
/// hiding place, and this bound is what makes that distinction enforceable
/// rather than a matter of style.
const waiver_request_window = 4096;

/// Does the module at `path` REQUEST to be lowered without graph application
/// facts?
///
/// WHY THIS IS NOT A DIRECTORY ANY MORE. This predicate used to answer yes for
/// anything under `gate/`, `scripts/ledger/`, `scripts/census/` or
/// `scripts/proof/`, plus nine files named one by one. Nothing recorded who
/// decided that or why; the whole list arrived in a commit whose message is
/// about the lexer and does not mention this file. What it bought was real but
/// small, and what it cost was a SECOND LANGUAGE in the directory this project
/// keeps its executable rulings in: `require_graph_facts` was false there, and
/// `dnir_lower.lowerSubjectCall` consults the graph's published application
/// fact only when that flag is true — so subject-first application on a
/// user-declared relation, the canonical face, was refused under `gate/` while
/// the retired operand-first face ran. Measured, same bytes, one directory
/// apart: `v:scale(7)` -> refused in `gate/`, 6 at the root.
///
/// Measured cost of the list itself, both trees, every file it covered: 86
/// files, 52 of which compile at all, 12 of which the waiver was load-bearing
/// for, 40 of which carried it for nothing. `docs/transport.md` has the rows.
///
/// A REQUEST, NOT AN INHERITANCE. The file that needs the waiver says so, in
/// its own header, in one line. That line is a diff line: adding a waiver is
/// now a reviewable edit to the file that takes it, and `gate/waive.sh`
/// refuses any file that takes one without being on the ledger.
///
/// IDENTITY OF THE FILE, NOT SPELLING OF THE PATH — the same principle
/// `lexer_bridge.corpusRelative` arrived at for the other path-dependent fork
/// found this week ("Resolution, not string surgery... Identity of the FILE is
/// the only thing all four spellings share"), taken one step further: the
/// answer is read out of the file's own bytes, so there is no path spelling
/// left to canonicalize. `gate/x.id`, `./gate/x.id`, the absolute path and a
/// symlink to it all name one inode and therefore one answer, by construction
/// rather than by test.
///
/// FAIL-SAFE DIRECTION. A path that cannot be opened answers NO, which means
/// full graph-fact checking, which means a REFUSAL rather than a silent
/// unchecked lowering. The unreadable case fails toward the strict law.
///
/// The name is kept for now because `semantic_graph`, `native_backend` and
/// `main` call it and those files belong to other lanes; `docs/transport.md`
/// carries the rename patch.
pub fn gateTransport(path: []const u8) bool {
    if (path.len == 0) return false;
    var buf: [waiver_request_window]u8 = undefined;
    const head = readHead(path, &buf) orelse return false;
    return waiverRequestedIn(head);
}

/// True when `source` carries the request on a comment line of its own.
///
/// A COMMENT LINE, not a substring: `print("@bootstrap.waive(graph-facts)")` is
/// a program printing a string and must not waive anything. Requiring the line
/// to begin with `#` is what separates the two, and it is why this is a
/// function with its own test rather than an `indexOf`.
pub fn waiverRequestedIn(source: []const u8) bool {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] != '#') continue;
        const body = std.mem.trimStart(u8, line[1..], " \t");
        if (std.mem.startsWith(u8, body, waiver_request)) return true;
    }
    return false;
}

/// The first `buf.len` bytes of `path`, or null if it cannot be read.
///
/// libc rather than `std.Io`: every other reader in this compiler is handed an
/// `Io` and an allocator by its caller, and this predicate is called from three
/// places that have neither. It reads a bounded prefix into the caller's
/// buffer, so there is nothing to allocate and nothing to free.
fn readHead(path: []const u8, buf: []u8) ?[]const u8 {
    var z: [std.fs.max_path_bytes]u8 = undefined;
    if (path.len == 0 or path.len >= z.len) return null;
    @memcpy(z[0..path.len], path);
    z[path.len] = 0;
    const fd = std.c.open(z[0..path.len :0].ptr, .{ .ACCMODE = .RDONLY });
    if (fd < 0) return null;
    defer _ = std.c.close(fd);
    var filled: usize = 0;
    while (filled < buf.len) {
        const n = std.c.read(fd, buf[filled..].ptr, buf.len - filled);
        if (n < 0) return null;
        if (n == 0) break;
        filled += @intCast(n);
    }
    return buf[0..filled];
}

fn callApplication(expr: *const Expr) bool {
    const c = expr.call;
    switch (c.func.*) {
        .name => |n| {
            if (std.mem.eql(u8, n.ident, "gatecap") and c.args.len == 1) return true;
            return false;
        },
        // `to(str)(n)` — A CALL WHOSE CALLEE IS A CALL, which is the whole
        // reason this arm has to exist separately. `curriedTo` asks
        // `c.func.* != .call` and was called from the `.name` arm above, where
        // `c.func.*` IS `.name` by construction — so the predicate could not
        // return true from any input and the face was NEVER recognized.
        //
        // The lowering it gates was never the missing part: `dnir_lower`
        // carries `lowerToStr` in full, malloc + snprintf with the value staged
        // on the VARIADIC TAIL, and a comment explaining which operand shapes
        // it refuses rather than mis-lowers. Nothing could reach it, because
        // `firstUnresolvedApplicationExcludingBootstrap` runs BEFORE lowering
        // and refused the whole module first. Measured across the tracked `.id`
        // of this tree: 598 occurrences of `to(str)(` in 143 files, every one
        // of them answering DNB011 `unresolved-application-facts` in front of a
        // realization that was already written.
        .call => return curriedTo(expr),
        // FOREIGN-ONLY: namespace-first spellings retired from canonical Idol.
        // Delete each arm when graph + DNIR consume the exact relation/target id.
        .field => |f| {
            if (f.obj.* != .name) return false;
            const home = f.obj.name.ident;
            if (std.mem.eql(u8, home, "mem")) {
                if (std.mem.eql(u8, f.field, "alloc") and c.args.len == 1) return true;
                if (std.mem.eql(u8, f.field, "free") and c.args.len == 1) return true;
                if (std.mem.eql(u8, f.field, "zero") and c.args.len == 2) return true;
                if (std.mem.eql(u8, f.field, "read_byte") and c.args.len == 2) return true;
                if (std.mem.eql(u8, f.field, "read_i64") and c.args.len == 2) return true;
                if (std.mem.eql(u8, f.field, "addr") and c.args.len == 1) return true;
                // THE WRITE HALF OF A FACE SET THAT ONLY HAD ITS READ HALF.
                // `read_byte`/`read_i64` are indexed loads and were admitted;
                // their stores were not, so a module could read a raw buffer
                // and never fill one. That is not a subset, it is a buffer the
                // direct backend can only observe — and the host bridges in
                // `lib/compiler/lexer.id` exist precisely to FILL a
                // caller-supplied buffer, which is why the beachhead module
                // refuses on `mem.write_i64` 16 times over.
                //
                // `ptr_from_addr(T, a)` belongs with them: it is `mem.addr`
                // read backwards, and at this width it is the same no-op —
                // the address IS the pointer. The type operand is a
                // DESCRIPTOR, not a value, so it is never lowered.
                if (std.mem.eql(u8, f.field, "write_byte") and c.args.len == 3) return true;
                if (std.mem.eql(u8, f.field, "write_i64") and c.args.len == 3) return true;
                if (std.mem.eql(u8, f.field, "ptr_from_addr") and c.args.len == 2) return true;
            }
            if (std.mem.eql(u8, home, "os")) {
                if (std.mem.eql(u8, f.field, "exit") and c.args.len == 1) return true;
                if (std.mem.eql(u8, f.field, "execute") and c.args.len == 1) return true;
                if (std.mem.eql(u8, f.field, "env") and c.args.len == 1) return true;
            }
            if (std.mem.eql(u8, home, "string")) {
                if (std.mem.eql(u8, f.field, "byte") and c.args.len >= 1 and c.args.len <= 2) return true;
                if (std.mem.eql(u8, f.field, "sub") and c.args.len == 3) return true;
                if (std.mem.eql(u8, f.field, "match") and c.args.len == 2) return true;
                if (std.mem.eql(u8, f.field, "len") and c.args.len == 1) return true;
                if (std.mem.eql(u8, f.field, "char") and c.args.len == 1) return true;
            }
            if (std.mem.eql(u8, home, "math") and c.args.len == 1) {
                return std.mem.eql(u8, f.field, "sqrt") or
                    std.mem.eql(u8, f.field, "sin") or
                    std.mem.eql(u8, f.field, "cos") or
                    std.mem.eql(u8, f.field, "fabs") or
                    std.mem.eql(u8, f.field, "floor") or
                    std.mem.eql(u8, f.field, "ceil");
            }
            return false;
        },
        else => return false,
    }
}

/// `to(T)(x)` — the CURRIED spelling of the conversion `x:to(T)` and
/// `to(x, T)` already wear. All three name one edge, so all three have to
/// reach the one conversion table; `dnir_lower.lowerSubjectTo` is that table
/// and refuses by target and by subject class, which is where a conversion
/// that cannot be performed belongs.
///
/// `str` KEEPS ITS SYNTACTIC OPERAND TEST and the other targets do not, and
/// that asymmetry is deliberate rather than an oversight. `to(str)(n)` lowers
/// through `snprintf` with a `"%lld"` this emitter ASSUMES — a wrong operand
/// class there PRINTS AN ADDRESS instead of refusing, measured — so it is
/// admitted only for operands whose integrality is visible in the syntax. The
/// text-consuming targets have no such hazard: their lowering asks the type
/// tracker (`exprIsStr`) and refuses `unsupported-conversion` on anything else.
fn curriedTo(expr: *const Expr) bool {
    const c = expr.call;
    if (c.args.len != 1) return false;
    if (c.func.* != .call) return false;
    const inner = c.func.call;
    if (inner.func.* != .name or !std.mem.eql(u8, inner.func.name.ident, "to")) return false;
    if (inner.args.len != 1 or inner.args[0].* != .name) return false;
    const target = inner.args[0].name.ident;
    if (std.mem.eql(u8, target, "i64") or std.mem.eql(u8, target, "f64")) return true;
    if (!std.mem.eql(u8, target, "str")) return false;
    return switch (c.args[0].*) {
        .int_lit, .true_lit, .false_lit => true,
        .unop => |u| u.op == .len,
        .binop => |b| b.op != .concat,
        .index => true,
        else => false,
    };
}

/// True when `expr` is a GAP-155 bootstrap face that `dnir_lower` realizes
/// without graph application facts. Ordinary module calls return false.
pub fn applicationExpr(expr: *const Expr) bool {
    return applicationExprInModule(expr, null);
}

/// Bootstrap recognition. NO FACE HERE DEPENDS ON WHERE THE FILE LIVES.
///
/// `module_path` is still in the signature because `semantic_graph` passes it
/// and that file belongs to another lane; it is no longer consulted, and
/// `native_bootstrap: the face set does not depend on the module path` holds it
/// to that.
///
/// WHY `to(…)` IS NO LONGER PATH-DEPENDENT — the same argument as `print`
/// below, one step later. `subject:to(T)` was admitted only under the directory
/// waiver, so `cap(cmd):to(i64)` in `scripts/agent_smoke.id` — a file `zig
/// build test` runs — compiled because of the directory it sat in. The face is
/// a CONVERSION, not a relation lookup, and the risk of admitting it everywhere
/// is a module that declares its own relation named `to` having its call
/// answered by the conversion instead. Measured across both trees: `:to(` is
/// used 896 times and `to` is declared as a relation ZERO times, so that
/// collision has no instance to protect. When it acquires one, the guard is the
/// one `lowerCall` already uses for `print` — force the checked path when the
/// graph published a fact — not a directory list.
///
/// WHY `print` IS NO LONGER PATH-DEPENDENT. `stdout:write(text)` and `print(v)`
/// are the SAME host egress — `dnir_lower` sends both to `lowerPrint`, and they
/// emit byte-identical DNIR. Admitting one in every module and the other only
/// under `gate/`, `scripts/ledger/` and friends did not make the second face
/// safer; it made the direct backend unable to produce output at all outside a
/// handful of directories. Measured over the 1005 tracked `.id` files: 308
/// programs that `idol check` accepts and the C bootstrap compiles were refused
/// by direct, 229 of them on `unresolved-application-facts`, and 110 of THOSE
/// named exactly one relation — `print`. That is 36% of the whole bridge gap
/// held open by a directory list.
///
/// The egress face is still a bootstrap face, not Idol semantics: the graph does
/// not yet publish host-egress relation/target ids, which is why this lives here
/// and not in the application vocabulary. What changed is only WHERE it is
/// recognized. A module that declares its own `print` relation is unaffected —
/// sema publishes application facts for that call, and `dnir_lower` prefers
/// published facts over this face (see `lowerCall`).
pub fn applicationExprInModule(expr: *const Expr, module_path: ?[]const u8) bool {
    _ = module_path;
    if (printApplication(expr)) return true;
    if (toApplication(expr)) return true;
    return switch (expr.*) {
        .method_call => methodApplication(expr),
        .call => callApplication(expr),
        else => false,
    };
}

fn collectCallExprs(alloc: std.mem.Allocator, block: ast.Block, out: *std.ArrayListUnmanaged(*const Expr)) !void {
    for (block.stmts) |*bstmt| {
        switch (bstmt.*) {
            .expr_stmt => |es| try out.append(alloc, es.expr),
            .call_stmt => |cs| try out.append(alloc, cs.expr),
            else => {},
        }
    }
    if (block.tail_expr) |tail| try out.append(alloc, tail);
}

test "native_bootstrap: ordinary calls are not bootstrap faces" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\observe: i64 = (value: i64)
        \\    value
        \\main: i64 = ()
        \\    observe(41)
        \\    gatecap("x")
        \\    stdin:read()
        \\    stdout:write("hi")
    ;
    var lex = Lexer.init(src, "bootstrap.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const module = try parser.parse_module();
    var exprs: std.ArrayListUnmanaged(*const Expr) = .empty;
    defer exprs.deinit(alloc);
    for (module.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        if (!std.mem.eql(u8, stmt.func_decl.path[0], "main")) continue;
        try collectCallExprs(alloc, stmt.func_decl.func.body, &exprs);
    }
    var ordinary: ?*const Expr = null;
    var gate: ?*const Expr = null;
    var stdin: ?*const Expr = null;
    var stdout: ?*const Expr = null;
    for (exprs.items) |expr| {
        switch (expr.*) {
            .call => |c| {
                if (c.func.* == .name and std.mem.eql(u8, c.func.name.ident, "observe")) ordinary = expr;
                if (c.func.* == .name and std.mem.eql(u8, c.func.name.ident, "gatecap")) gate = expr;
            },
            .method_call => |mc| {
                if (std.mem.eql(u8, mc.method, "read") and mc.obj.* == .name and
                    std.mem.eql(u8, mc.obj.name.ident, "stdin"))
                {
                    stdin = expr;
                }
                if (std.mem.eql(u8, mc.method, "write") and mc.obj.* == .name and
                    std.mem.eql(u8, mc.obj.name.ident, "stdout"))
                {
                    stdout = expr;
                }
            },
            else => {},
        }
    }
    try std.testing.expect(ordinary != null);
    try std.testing.expect(gate != null);
    try std.testing.expect(stdin != null);
    try std.testing.expect(stdout != null);
    try std.testing.expect(!applicationExpr(ordinary.?));
    try std.testing.expect(applicationExpr(gate.?));
    try std.testing.expect(applicationExpr(stdin.?));
    try std.testing.expect(applicationExpr(stdout.?));
}

test "native_bootstrap: print is host egress in every module, not just gate transport" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main: i64 = ()
        \\    print("ledger/shc: pass")
        \\    0
    ;
    var lex = Lexer.init(src, "scripts/ledger/shc.id");
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const module = try parser.parse_module();
    var exprs: std.ArrayListUnmanaged(*const Expr) = .empty;
    defer exprs.deinit(alloc);
    for (module.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        if (!std.mem.eql(u8, stmt.func_decl.path[0], "main")) continue;
        try collectCallExprs(alloc, stmt.func_decl.func.body, &exprs);
    }
    var print_expr: ?*const Expr = null;
    for (exprs.items) |expr| {
        if (printApplication(expr)) print_expr = expr;
    }
    try std.testing.expect(print_expr != null);
    // The directory the file lives in is not a fact about the call. Both of
    // these were once one true and one false, and the false one is what left
    // the direct backend with no output path outside `gate/`.
    try std.testing.expect(applicationExprInModule(print_expr.?, "native.id"));
    try std.testing.expect(applicationExprInModule(print_expr.?, "scripts/ledger/shc.id"));
    try std.testing.expect(applicationExprInModule(print_expr.?, null));
}

/// Parse `src` and hand back every call/method-call expression in `main`.
fn facesOf(alloc: std.mem.Allocator, src: []const u8, file: []const u8) ![]const *const Expr {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    var lex = Lexer.init(src, file);
    var parser = Parser.init(&lex, alloc);
    parser.idol_mode = true;
    const module = try parser.parse_module();
    var exprs: std.ArrayListUnmanaged(*const Expr) = .empty;
    for (module.body.stmts) |*stmt| {
        if (stmt.* != .func_decl) continue;
        if (!std.mem.eql(u8, stmt.func_decl.path[0], "main")) continue;
        try collectCallExprs(alloc, stmt.func_decl.func.body, &exprs);
    }
    return exprs.items;
}

test "native_bootstrap: the face set does not depend on the module path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    // Every face this module recognizes, in one body, asked from four paths —
    // one of which used to waive and three of which never did. A single
    // disagreement here IS the fork this file was rewritten to remove.
    const src =
        \\main: i64 = ()
        \\    print("x")
        \\    stdin:read()
        \\    stdout:write("hi")
        \\    gatecap("echo 1")
        \\    "12":to(i64)
        \\    "abc":len()
        \\    observe(41)
        \\    0
    ;
    const paths = [_][]const u8{ "gate/probe.id", "probe.id", "./gate/probe.id", "/tmp/probe.id" };
    for (try facesOf(alloc, src, "gate/probe.id")) |expr| {
        const first = applicationExprInModule(expr, paths[0]);
        for (paths[1..]) |p| {
            try std.testing.expectEqual(first, applicationExprInModule(expr, p));
        }
        try std.testing.expectEqual(first, applicationExprInModule(expr, null));
    }
}

test "native_bootstrap: the injected test world is a face, in any directory" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const src =
        \\main: i64 = ()
        \\    test:assert(1 == 1, "one")
        \\    test:equal(1, 1, "one")
        \\    other:assert(1 == 1, "one")
        \\    0
    ;
    var seen: usize = 0;
    for (try facesOf(alloc, src, "gate/injection_test.id")) |expr| {
        if (expr.* != .method_call) continue;
        const mc = expr.method_call;
        if (mc.obj.* != .name) continue;
        seen += 1;
        // `test` is the world subject; `other` is an ordinary name that happens
        // to spell one of the world's edges, and it must NOT be a face.
        const want = std.mem.eql(u8, mc.obj.name.ident, "test");
        try std.testing.expectEqual(want, applicationExprInModule(expr, "gate/injection_test.id"));
        try std.testing.expectEqual(want, applicationExprInModule(expr, "injection_test.id"));
    }
    try std.testing.expectEqual(@as(usize, 3), seen);
}

test "native_bootstrap: the waiver is a request on a comment line, not a substring" {
    // Asked for.
    try std.testing.expect(waiverRequestedIn("# " ++ waiver_request ++ " — GAP-155\nmain: i64 = ()\n"));
    try std.testing.expect(waiverRequestedIn("# header\n#" ++ waiver_request ++ "\n"));
    try std.testing.expect(waiverRequestedIn("   #  " ++ waiver_request ++ "\r\n"));
    // Not asked for. The third is the one that matters: a program that PRINTS
    // the request has not made it, and an `indexOf` over the source would have
    // said it had.
    try std.testing.expect(!waiverRequestedIn("main: i64 = ()\n    0\n"));
    try std.testing.expect(!waiverRequestedIn("# @bootstrap.waive(something-else)\n"));
    try std.testing.expect(!waiverRequestedIn("main: i64 = ()\n    print(\"" ++ waiver_request ++ "\")\n"));
    try std.testing.expect(!waiverRequestedIn("x = \"" ++ waiver_request ++ "\"\n"));
}

test "native_bootstrap: an unreadable path answers no, so it fails toward the strict law" {
    // A waiver that cannot be read is not granted. The direction matters: the
    // other direction turns a missing file into unchecked lowering.
    try std.testing.expect(!gateTransport(""));
    try std.testing.expect(!gateTransport("gate/"));
    try std.testing.expect(!gateTransport("no/such/file/anywhere.id"));
    var over_long: [std.fs.max_path_bytes + 8]u8 = undefined;
    @memset(&over_long, 'a');
    try std.testing.expect(!gateTransport(&over_long));
}

test "native_bootstrap: same bytes, every spelling — path, directory and symlink" {
    // THE WHOLE RULING IN ONE TEST. Two files with the same name in two
    // directories, one asking for the waiver and one not, then the asking one
    // reached through four spellings and a symlink. The old predicate answered
    // by directory and would fail the first pair; anything that answers by path
    // spelling fails the second.
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "gate");

    try tmp.dir.writeFile(io, .{
        .sub_path = "gate/quiet.id",
        .data = "# an ordinary gate file\nmain: i64 = ()\n    0\n",
    });
    try tmp.dir.writeFile(io, .{
        .sub_path = "asking.id",
        .data = "# asking.id\n# " ++ waiver_request ++ " — boundary-curried relation edges\nmain: i64 = ()\n    0\n",
    });

    var root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buf[0..try tmp.dir.realPath(io, &root_buf)];

    var join: [std.fs.max_path_bytes]u8 = undefined;
    const under_gate = try std.fmt.bufPrint(&join, "{s}/gate/quiet.id", .{root});
    // Living under `gate/` is not a request. This is the line the old
    // predicate got wrong, and it is the whole fork.
    try std.testing.expect(!gateTransport(under_gate));

    var join2: [std.fs.max_path_bytes]u8 = undefined;
    const direct = try std.fmt.bufPrint(&join2, "{s}/asking.id", .{root});
    try std.testing.expect(gateTransport(direct));

    var join3: [std.fs.max_path_bytes]u8 = undefined;
    const dotted = try std.fmt.bufPrint(&join3, "{s}/./asking.id", .{root});
    try std.testing.expect(gateTransport(dotted));

    var join4: [std.fs.max_path_bytes]u8 = undefined;
    const round_trip = try std.fmt.bufPrint(&join4, "{s}/gate/../asking.id", .{root});
    try std.testing.expect(gateTransport(round_trip));

    // Through a symlink, and through one that lands INSIDE `gate/` — the
    // spelling now says `gate/` and the answer must still come from the bytes.
    try tmp.dir.symLink(io, "../asking.id", "gate/linked.id", .{});
    var join5: [std.fs.max_path_bytes]u8 = undefined;
    const linked = try std.fmt.bufPrint(&join5, "{s}/gate/linked.id", .{root});
    try std.testing.expect(gateTransport(linked));
}
