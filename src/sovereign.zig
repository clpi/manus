//! GRAPH SOVEREIGNTY OVER MACHINE BYTES — the executable form of the clause
//! `gaps/GAP-202.md` buried in one gap's acceptance list:
//!
//!     poisoning/removing AST provenance after graph publication
//!     leaves machine bytes unchanged
//!
//! That is not a property of scalar multiplication. It is the whole of
//! `docs/spec/law.md` §1 ("Once known, a fact is carried forward; downstream
//! phases never reconstruct it from syntax or representation") and §12 ("AST
//! pointers, names, paths, strings, and opcode tags are temporary bridges
//! only"), stated in a form that can FAIL. So it is measured here as a global
//! gate over a family of verticals rather than as one gap's checkbox.
//!
//! ## The measurement
//!
//!     lift  -> freeze graph -> damage AST -> realize from the FROZEN graph
//!           -> compare object bytes against the undamaged realization
//!
//! Three controls stand around it, because a damage gate without them is the
//! defect it is supposed to catch:
//!
//! 1. **Determinism.** The undamaged realization is emitted TWICE and the two
//!    byte strings must be equal. Without this, every verdict is noise: a
//!    timestamp or an address in the object would read as a leak, and — worse —
//!    a gate that never diffs anything would read as a pass.
//! 2. **Observability (the positive control).** After damaging the tree, a
//!    SECOND graph is lifted from the DAMAGED tree and realized. Those bytes
//!    must DIFFER from the baseline. This is what proves the poison reached
//!    something semantic. A poison that changes a field nobody reads would make
//!    both the frozen and the control realization identical to the baseline, and
//!    the gate would report a triumphant pass while measuring nothing. That
//!    outcome is `vacuous` here, and `vacuous` is not a pass.
//! 3. **Non-empty enumeration.** `poison.poisonModule` returns the damaged-site
//!    count and a zero refuses; `test "sovereign: the subject census is not
//!    empty"` refuses an empty vertical table. Zero subjects is a FAILURE, never
//!    a pass.
//!
//! ## Reading a failure
//!
//! A `leak` row is the valuable output, not a bug in this file. It says: for
//! this vertical, this class of syntax is still being read AFTER the graph
//! published the corresponding fact, and the object bytes prove it. The repair
//! belongs to the consumer that read it, and until that repair lands the row is
//! the census entry.
//!
//! DELETION WITNESS (`law.bridge.death`): deleted together with `poison.zig`
//! when every vertical is `sovereign` for every poison class AND `dnir_lower` /
//! `native_backend` hold zero post-publication `ast_ref` / `valueExpression`
//! reads — at which point the property is structural and nothing is left to
//! falsify.

const std = @import("std");
const builtin = @import("builtin");
const ast = @import("ast.zig");
const poison = @import("poison.zig");
const semantic_graph = @import("semantic_graph.zig");
const native_backend = @import("native_backend.zig");
const subject_home = @import("subject_home.zig");
const table_apply = @import("table_apply.zig");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;

/// The one target whose bytes this gate compares. `native-object` is the
/// shortest path from a published graph to real machine bytes that does not
/// also drag in a linker: `emitObjectWithGraphLineage` is the same seam
/// `main.zig` uses for `--emit obj`.
const object_target = "native-object";

pub const Verdict = enum {
    /// Damage left the object bytes bit-identical, and the positive control
    /// proved the damage was observable. This is the only pass.
    sovereign,
    /// Damage changed the object bytes, or turned a successful realization into
    /// a refusal. A syntax read outlived graph publication.
    leak,
    /// The fixture contains no site of this class, so nothing was damaged and
    /// nothing was measured. Reported, never counted as evidence either way.
    absent,
    /// A site WAS damaged and the damage was invisible even to a full re-lift
    /// from the damaged tree. The comparison therefore proved nothing about
    /// sovereignty. NOT A PASS.
    vacuous,
    /// The vertical never reached machine bytes at all, so there was nothing to
    /// compare. NOT A PASS.
    blocked,

    pub fn label(self: Verdict) []const u8 {
        return @tagName(self);
    }
};

pub const Row = struct {
    vertical: []const u8,
    /// Null for the `Node.ast_ref` deletion measurement, which damages the
    /// GRAPH rather than the tree and therefore belongs to no poison class.
    kind: ?poison.Kind,
    sites: usize,
    verdict: Verdict,
    note: []const u8,
};

pub const Vertical = struct {
    /// One lowercase word naming the semantic construct under test.
    name: []const u8,
    file: []const u8,
    source: []const u8,
    expect: Ledger,
};

/// THE CENSUS, PINNED IN THE RUNNER. `AGENTS.md`: "state the COMMAND, not the
/// number, and when you must pin a number put it in the runner that checks it".
/// Every rule this project recorded as prose decayed within a day, so the
/// current per-vertical verdicts live here, where `zig build sovereign`
/// compares them against a live measurement on every run.
///
/// AN IMPROVEMENT FAILS THIS GATE TOO, and deliberately: a row that turned
/// `leak` into `sovereign` means a consumer stopped reading syntax, which is
/// exactly the movement `law.md` §17 asks every merge to record. It should be
/// recorded here, in the same diff that caused it, not absorbed silently.
pub const Ledger = struct {
    int: Verdict,
    text: Verdict,
    name: Verdict,
    relation: Verdict,
    /// Deleting `Node.ast_ref` from the published graph, measured by
    /// `measureReference`.
    reference: Verdict,

    pub fn of(self: Ledger, kind: poison.Kind) Verdict {
        return switch (kind) {
            .int => self.int,
            .text => self.text,
            .name => self.name,
            .relation => self.relation,
        };
    }
};

/// THE SUBJECT CENSUS. Each entry is one construct from the universal
/// realization chain in `gaps/GAP-202.md`:
///
///     one ordinary application -> ordered operands/results -> demand
///       -> world/effect -> overflow/trap/completion -> realization
///       -> machine range, without AST recovery
///
/// Every source here is verified to reach `native-object` undamaged; a fixture
/// that stopped compiling would report `blocked`, which is a failure and not a
/// silent skip.
pub const verticals = [_]Vertical{
    .{
        .name = "arith",
        .file = "sovereign-arith.id",
        .source =
        \\main: i64 = ()
        \\    x = 6
        \\    y = 7
        \\    x * y + 3
        ,
        .expect = .{ .int = .leak, .text = .absent, .name = .sovereign, .relation = .leak, .reference = .leak },
    },
    .{
        .name = "call",
        .file = "sovereign-call.id",
        .source =
        \\twice(n: i64): i64
        \\    n + n
        \\
        \\main: i64 = ()
        \\    twice(20) + twice(1)
        ,
        .expect = .{ .int = .leak, .text = .absent, .name = .leak, .relation = .leak, .reference = .leak },
    },
    .{
        .name = "projection",
        .file = "sovereign-projection.id",
        .source =
        \\main: i64 = ()
        \\    row = { 11, 22, 33 }
        \\    row[2] + row[3]
        ,
        .expect = .{ .int = .sovereign, .text = .absent, .name = .sovereign, .relation = .leak, .reference = .leak },
    },
    .{
        .name = "field",
        .file = "sovereign-field.id",
        .source =
        \\main: i64 = ()
        \\    p = { x = 4, y = 9 }
        \\    p.x * p.y
        ,
        .expect = .{ .int = .leak, .text = .absent, .name = .sovereign, .relation = .leak, .reference = .leak },
    },
    .{
        .name = "pack",
        .file = "sovereign-pack.id",
        .source =
        \\pair(n: i64): (i64, i64)
        \\    return n, n + 1
        \\
        \\main: i64 = ()
        \\    a, b = pair(40)
        \\    a + b
        ,
        .expect = .{ .int = .leak, .text = .absent, .name = .sovereign, .relation = .leak, .reference = .leak },
    },
    .{
        .name = "text",
        .file = "sovereign-text.id",
        .source =
        \\main: i64 = ()
        \\    s = "abcdef"
        \\    stdout:write(s)
        \\    s:len()
        ,
        .expect = .{ .int = .absent, .text = .leak, .name = .leak, .relation = .absent, .reference = .leak },
    },
    .{
        .name = "loop",
        .file = "sovereign-loop.id",
        .source =
        \\main: i64 = ()
        \\    total = 0
        \\    i = 1
        \\    while i <= 5
        \\        total += i
        \\        i += 1
        \\    total
        ,
        .expect = .{ .int = .leak, .text = .absent, .name = .leak, .relation = .leak, .reference = .leak },
    },
    .{
        .name = "world",
        .file = "sovereign-world.id",
        .source =
        \\main: i64 = ()
        \\    stdout:write("hi")
        \\    0
        ,
        .expect = .{ .int = .leak, .text = .leak, .name = .leak, .relation = .absent, .reference = .leak },
    },
    .{
        .name = "foreign",
        .file = "sovereign-foreign.id",
        .source =
        \\@ffi("abs")
        \\away(n: i32): i32
        \\
        \\main: i64 = ()
        \\    away(-5)
        ,
        .expect = .{ .int = .leak, .text = .absent, .name = .sovereign, .relation = .absent, .reference = .leak },
    },
};

/// A published graph plus the exact tree it was published from. The tree is
/// mutable BECAUSE the graph is not: everything after `lift` is supposed to be
/// reading the graph.
const Lifted = struct {
    module: ast.Module,
    checked: Sema,
    graph: semantic_graph.SemanticGraph,
};

fn lift(alloc: std.mem.Allocator, v: Vertical) !*Lifted {
    const out = try alloc.create(Lifted);
    var lexer = Lexer.init(v.source, v.file);
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    out.module = try parser.parse_module();
    out.checked = Sema.init(alloc);
    out.checked.idol_mode = true;
    out.checked.worlds = subject_home.injectedWorlds();
    try out.checked.check_module(&out.module);
    if (out.checked.errors != 0) return error.SovereignFixtureRejected;
    // `main.zig` normalizes before the lift and before the native walk, so the
    // gate must too: a fixture measured through a different pipeline would be
    // measuring a different compiler.
    table_apply.normalizeModule(alloc, &out.module, &out.checked.type_map);
    out.graph = semantic_graph.SemanticGraph.init(alloc);
    _ = try out.graph.liftModuleWithCheckedCalls(&out.module, &out.checked, v.file);
    return out;
}

/// Object bytes, or null when this pairing refuses. A refusal is a legitimate
/// OUTCOME of damage and is compared as such — it is not an error to propagate,
/// because "the poison turned bytes into a diagnostic" is exactly a byte change.
fn emitBytes(
    alloc: std.mem.Allocator,
    module: *const ast.Module,
    graph: *const semantic_graph.SemanticGraph,
) ?[]const u8 {
    const artifact = native_backend.emitObjectWithGraphLineage(alloc, module, object_target, graph) catch return null;
    return artifact.bytes;
}

fn sameBytes(a: ?[]const u8, b: ?[]const u8) bool {
    if (a == null or b == null) return a == null and b == null;
    return std.mem.eql(u8, a.?, b.?);
}

/// One (vertical, poison class) measurement. Allocations live in the caller's
/// arena; two full graphs and up to four object images are retained on purpose
/// so the comparison never reuses a freed buffer.
pub fn measure(alloc: std.mem.Allocator, v: Vertical, kind: poison.Kind) !Row {
    const subject = lift(alloc, v) catch |err| return .{
        .vertical = v.name,
        .kind = kind,
        .sites = 0,
        .verdict = .blocked,
        .note = @errorName(err),
    };

    const baseline = emitBytes(alloc, &subject.module, &subject.graph) orelse return .{
        .vertical = v.name,
        .kind = kind,
        .sites = 0,
        .verdict = .blocked,
        .note = "baseline-refused",
    };

    // Control 1 — determinism. Two realizations of the SAME tree and the SAME
    // graph must agree, or no later difference can be attributed to the damage.
    const repeat = emitBytes(alloc, &subject.module, &subject.graph);
    if (!sameBytes(baseline, repeat)) return .{
        .vertical = v.name,
        .kind = kind,
        .sites = 0,
        .verdict = .blocked,
        .note = "nondeterministic-baseline",
    };

    const sites = try poison.poisonModule(alloc, &subject.module, kind);
    if (sites == 0) return .{
        .vertical = v.name,
        .kind = kind,
        .sites = 0,
        .verdict = .absent,
        .note = "fixture-has-no-site",
    };

    // THE MEASUREMENT. Same published graph, damaged tree.
    const frozen = emitBytes(alloc, &subject.module, &subject.graph);

    // Control 2 — observability. A graph lifted from the DAMAGED tree must
    // realize differently, or the damage was semantically invisible and the
    // frozen comparison above proved nothing.
    var control_graph = semantic_graph.SemanticGraph.init(alloc);
    const control: ?[]const u8 = if (control_graph.liftModuleWithCheckedCalls(
        &subject.module,
        &subject.checked,
        v.file,
    )) |_|
        emitBytes(alloc, &subject.module, &control_graph)
    else |_|
        null;
    if (sameBytes(control, baseline)) return .{
        .vertical = v.name,
        .kind = kind,
        .sites = sites,
        .verdict = .vacuous,
        .note = "damage-not-observable",
    };

    if (frozen == null) return .{
        .vertical = v.name,
        .kind = kind,
        .sites = sites,
        .verdict = .leak,
        .note = "refused-under-damage",
    };
    if (!sameBytes(frozen, baseline)) return .{
        .vertical = v.name,
        .kind = kind,
        .sites = sites,
        .verdict = .leak,
        // HOW COMPLETE THE LEAK IS, not merely that there is one. `control` is
        // the object of the DAMAGED PROGRAM — the graph re-lifted from the
        // damaged tree, so every fact downstream agrees with the new spelling.
        // When realizing from the FROZEN graph reproduces those bytes exactly,
        // the published graph contributed nothing this class of syntax did not
        // already decide: realization read the tree. When the two differ, the
        // graph still owns part of the outcome and only part of it was
        // recovered from syntax.
        .note = if (sameBytes(frozen, control))
            "damaged-source-object"
        else
            "object-bytes-differ",
    };
    return .{
        .vertical = v.name,
        .kind = kind,
        .sites = sites,
        .verdict = .sovereign,
        .note = "",
    };
}

/// `Node.ast_ref` deletion, the other half of the acceptance clause. The tree is
/// untouched; the graph simply stops POINTING at it. Any consumer still
/// dereferencing that pointer loses its input.
///
/// Its positive control is structural rather than differential: the row is only
/// meaningful when the graph actually carried provenance to delete, so
/// `sites` is the number of nulled references and zero refuses.
pub fn measureReference(alloc: std.mem.Allocator, v: Vertical) !Row {
    const kind: ?poison.Kind = null;
    const subject = lift(alloc, v) catch |err| return .{
        .vertical = v.name,
        .kind = kind,
        .sites = 0,
        .verdict = .blocked,
        .note = @errorName(err),
    };
    const baseline = emitBytes(alloc, &subject.module, &subject.graph) orelse return .{
        .vertical = v.name,
        .kind = kind,
        .sites = 0,
        .verdict = .blocked,
        .note = "baseline-refused",
    };
    var sites: usize = 0;
    for (subject.graph.nodes.items) |*node| {
        if (node.ast_ref != null) {
            node.ast_ref = null;
            sites += 1;
        }
    }
    if (sites == 0) return .{
        .vertical = v.name,
        .kind = kind,
        .sites = 0,
        .verdict = .vacuous,
        .note = "graph-carried-no-provenance",
    };
    const after = emitBytes(alloc, &subject.module, &subject.graph);
    if (after == null) return .{
        .vertical = v.name,
        .kind = kind,
        .sites = sites,
        .verdict = .leak,
        .note = "refused-without-provenance",
    };
    if (!sameBytes(after, baseline)) return .{
        .vertical = v.name,
        .kind = kind,
        .sites = sites,
        .verdict = .leak,
        .note = "object-bytes-differ",
    };
    return .{ .vertical = v.name, .kind = kind, .sites = sites, .verdict = .sovereign, .note = "" };
}

const supported = builtin.os.tag == .macos and builtin.cpu.arch == .aarch64;

test "sovereign: the subject census is not empty" {
    // ENUMERATE ZERO SUBJECTS => FAIL. A census that measured nothing is the
    // failure mode this whole file exists to avoid, so it is checked before any
    // verdict is read.
    try std.testing.expect(verticals.len > 0);
    try std.testing.expect(std.enums.values(poison.Kind).len > 0);
}

test "sovereign: machine bytes survive AST damage after graph publication" {
    if (!supported) return error.SkipZigTest;

    var measured: usize = 0;
    var sovereignty: usize = 0;
    var leaks: usize = 0;
    var vacuous: usize = 0;
    var absent: usize = 0;
    var blocked: usize = 0;
    var mismatch: usize = 0;

    for (verticals) |v| {
        inline for (comptime std.enums.values(poison.Kind)) |kind| {
            var case = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer case.deinit();
            const row = try measure(case.allocator(), v, kind);
            measured += 1;
            switch (row.verdict) {
                .sovereign => sovereignty += 1,
                .leak => leaks += 1,
                .vacuous => vacuous += 1,
                .absent => absent += 1,
                .blocked => blocked += 1,
            }
            const want = v.expect.of(kind);
            if (row.verdict != want) mismatch += 1;
            std.debug.print(
                "sovereign  {s: <11} {s: <9} sites={d: <4} {s: <10} {s: <22} ledger={s}{s}\n",
                .{
                    v.name,
                    kind.label(),
                    row.sites,
                    row.verdict.label(),
                    row.note,
                    want.label(),
                    if (row.verdict == want) "" else "   <- LEDGER STALE",
                },
            );
        }
    }
    std.debug.print(
        "sovereign  TOTAL measured={d} sovereign={d} leak={d} vacuous={d} absent={d} blocked={d}\n",
        .{ measured, sovereignty, leaks, vacuous, absent, blocked },
    );

    // THE INSTRUMENT MUST BE ABLE TO SAY BOTH WORDS. A gate that can only
    // report one verdict is not measuring; five instruments passed in one
    // session here while measuring nothing. `sovereignty > 0` proves a clean
    // pass is reachable through this exact code path, and `leaks > 0` proves a
    // failure is too — on the same fixtures, with the same comparison.
    try std.testing.expect(sovereignty > 0);
    try std.testing.expect(leaks > 0);
    // A vacuous row is a measurement that proved nothing, and there is no
    // reason for one to exist: every poison class either has a site in a
    // fixture (and the positive control shows it) or has none (`absent`).
    try std.testing.expectEqual(@as(usize, 0), vacuous);
    try std.testing.expectEqual(@as(usize, 0), blocked);
    // And the pinned census must still describe this compiler.
    try std.testing.expectEqual(@as(usize, 0), mismatch);
}

test "sovereign: machine bytes survive deletion of graph AST provenance" {
    if (!supported) return error.SkipZigTest;
    var carried: usize = 0;
    var mismatch: usize = 0;
    for (verticals) |v| {
        var case = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer case.deinit();
        const row = try measureReference(case.allocator(), v);
        if (row.sites > 0) carried += 1;
        if (row.verdict != v.expect.reference) mismatch += 1;
        std.debug.print(
            "provenance {s: <11} {s: <9} nulled={d: <3} {s: <10} {s: <22} ledger={s}{s}\n",
            .{
                v.name,
                "astref",
                row.sites,
                row.verdict.label(),
                row.note,
                v.expect.reference.label(),
                if (row.verdict == v.expect.reference) "" else "   <- LEDGER STALE",
            },
        );
    }
    // Positive control for THIS measurement: there was provenance to delete.
    // Deleting nothing and reporting a pass is the vacuity the gate exists to
    // refuse.
    try std.testing.expectEqual(verticals.len, carried);
    try std.testing.expectEqual(@as(usize, 0), mismatch);
}
