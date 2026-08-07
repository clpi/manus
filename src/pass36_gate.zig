//! Pass 36/40/41 gate — final semantic access calculus, Phase 0 (recorded).
//!
//! Phase 0 proves the calculus is internally consistent before any parser or
//! sema change: the desugaring graph is closed and acyclic, the eight-rung
//! ladder is a strict total order, no access form or grammar rule resurrects a
//! buried spelling, retrieval is never receiver-bound anywhere, the `__`
//! namespace appears only inside the `@lua` adapter, and every conflict class is
//! decidable without falling through to the dynamic layer.
const std = @import("std");
const pass36_catalog = @import("pass36_catalog.zig");

pub const GateError = error{GateFailed};

pub fn validateCatalogSchema() GateError!void {
    if (!std.mem.eql(u8, pass36_catalog.SCHEMA_VERSION, "pass40-semantic-access-catalog-v2")) return error.GateFailed;
    if (pass36_catalog.access_forms.len != 18) return error.GateFailed;
    if (pass36_catalog.grammar_rules.len != 11) return error.GateFailed;
    if (pass36_catalog.graveyard.len != 14) return error.GateFailed;
    if (pass36_catalog.level_selectors.len != 7) return error.GateFailed;
    if (pass36_catalog.resolution_order.len != 9) return error.GateFailed;
    if (pass36_catalog.call_object_fields.len != 10) return error.GateFailed;
    if (pass36_catalog.sealed_world_conditions.len != 5) return error.GateFailed;
    if (pass36_catalog.sealed_world_guarantees.len != 6) return error.GateFailed;
    if (pass36_catalog.projection_families.len != 27) return error.GateFailed;
    if (pass36_catalog.operator_projections.len != 15) return error.GateFailed;
    if (pass36_catalog.lua_adapter_targets.len != 10) return error.GateFailed;
    if (pass36_catalog.demand_sources.len != 9) return error.GateFailed;
    if (pass36_catalog.erasure_obligations.len != 7) return error.GateFailed;
    if (pass36_catalog.conflict_rules.len != 8) return error.GateFailed;
    if (pass36_catalog.slot_rules.len != 4) return error.GateFailed;
    if (pass36_catalog.structural_requirements.len != 8) return error.GateFailed;
    if (pass36_catalog.directive_roots.len != 5) return error.GateFailed;
    if (pass36_catalog.idioms.len != 10) return error.GateFailed;
    if (pass36_catalog.smells.len != 5) return error.GateFailed;
    if (pass36_catalog.gains_ledger.len != 10) return error.GateFailed;
    if (pass36_catalog.kept_on_merit.len != 6) return error.GateFailed;
    if (pass36_catalog.completion_gates.len != 20) return error.GateFailed;
    if (pass36_catalog.execution_phases.len != 10) return error.GateFailed;
    if (pass36_catalog.supersessions.len != 4) return error.GateFailed;
}

/// Every equality spelling normalizing to one call identity is only true if the
/// desugaring graph is closed (every target exists) and acyclic (every chain
/// terminates at CANONICAL). Walk each chain with a bound equal to the form
/// count; exceeding it means a cycle.
pub fn proveDesugaringGraphClosedAndAcyclic() GateError!void {
    for (pass36_catalog.access_forms) |form| {
        var current = form;
        var steps: usize = 0;
        while (!std.mem.eql(u8, current.desugars_to, pass36_catalog.CANONICAL)) {
            if (steps > pass36_catalog.access_forms.len) return error.GateFailed; // cycle
            current = pass36_catalog.findAccessForm(current.desugars_to) orelse return error.GateFailed;
            steps += 1;
        }
    }
}

/// Gate 4: `@eq(a, b)` is the normal form and `a == b` reaches it.
pub fn proveOperatorNormalizesToInvocation() GateError!void {
    const op = pass36_catalog.findAccessForm("A-OP") orelse return error.GateFailed;
    const call = pass36_catalog.findAccessForm("A-CALL") orelse return error.GateFailed;
    if (!std.mem.eql(u8, op.desugars_to, "A-CALL")) return error.GateFailed;
    if (!std.mem.eql(u8, call.desugars_to, pass36_catalog.CANONICAL)) return error.GateFailed;
}

/// S6 / Pass 40 §0.1 — the decisive ruling. `.@name` retrieval is NEVER
/// receiver-bound, which is what makes the descriptor-vs-subject ambiguity class
/// non-existent rather than merely arbitrated. If any form ever sets
/// `receiver_bound`, the ambiguity class returns and R1 would have to be
/// resurrected, so the gate refuses the whole catalog.
pub fn proveNoFormIsReceiverBound() GateError!void {
    for (pass36_catalog.access_forms) |form| {
        if (form.receiver_bound) return error.GateFailed;
    }
    const member = pass36_catalog.findAccessForm("A-MEMBER") orelse return error.GateFailed;
    if (member.kind != .semantic_member) return error.GateFailed;
    if (std.mem.indexOf(u8, member.note, "RETRIEVAL") == null) return error.GateFailed;

    const s6 = pass36_catalog.findSupersession("S6") orelse return error.GateFailed;
    if (s6.status != .adopted) return error.GateFailed;
}

/// S4 — no access form and no grammar rule may spell a buried form. This is the
/// executable version of the graveyard: a rejection with no enforcement is a
/// comment, not a decision.
pub fn proveGraveyardStaysBuried() GateError!void {
    for (pass36_catalog.graveyard) |g| {
        if (g.syntax.len == 0 or g.reason.len == 0) return error.GateFailed;
    }
    for (pass36_catalog.access_forms) |form| {
        if (pass36_catalog.isRejected(form.syntax)) return error.GateFailed;
    }
    for (pass36_catalog.grammar_rules) |rule| {
        if (pass36_catalog.isRejected(rule.form)) return error.GateFailed;
    }

    // The postfix family specifically: these are the forms Pass 39 adopted and
    // Pass 40 reversed, so they get a named check rather than riding on the loop.
    if (!pass36_catalog.isRejected("value@name")) return error.GateFailed;
    if (!pass36_catalog.isRejected("value@(level)@name")) return error.GateFailed;
    if (!pass36_catalog.isRejected("value:@name")) return error.GateFailed;

    const s4 = pass36_catalog.findSupersession("S4") orelse return error.GateFailed;
    if (s4.status != .adopted) return error.GateFailed;
}

/// Every grammar form must begin with `@`, or be a `.`-access / table / meta
/// form whose `@` appears only after a `.` or `{`. No form may place `@` after a
/// value expression — that is the postfix shape S4 buried.
pub fn provePrefixOnlyDiscipline() GateError!void {
    for (pass36_catalog.grammar_rules) |rule| {
        if (rule.form.len == 0) return error.GateFailed;
        const at = std.mem.indexOfScalar(u8, rule.form, '@') orelse return error.GateFailed;
        if (at == 0) continue; // `@name`, `@(expr)`, `@{...}`
        const prev = rule.form[at - 1];
        // Only `.` (value.@name) and `{ ` (table slot) may precede an `@`.
        if (prev != '.' and prev != ' ') return error.GateFailed;
        if (prev == ' ') {
            // `{ @name = value }` — the only space-preceded form is a table slot.
            if (at < 2 or rule.form[at - 2] != '{') return error.GateFailed;
        }
    }
}

/// Pass 41 A3 — the ladder must be a strict total order with no repeated level
/// and `failure` last. A duplicated or reordered rung silently changes which
/// implementation wins.
pub fn proveResolutionLadderIsStrictTotal() GateError!void {
    var expected: u8 = 1;
    var seen: [16]bool = @splat(false);
    for (pass36_catalog.resolution_order) |step| {
        if (step.order != expected) return error.GateFailed;
        if (step.description.len == 0) return error.GateFailed;
        const idx = @intFromEnum(step.level);
        if (seen[idx]) return error.GateFailed;
        seen[idx] = true;
        expected += 1;
    }
    const last = pass36_catalog.resolution_order[pass36_catalog.resolution_order.len - 1];
    if (last.level != .failure) return error.GateFailed;

    // Rung 1 is lexical: a lexical override must beat everything, which is what
    // makes a scoped `@eq = ...` binding work at all.
    if (pass36_catalog.resolution_order[0].level != .lexical) return error.GateFailed;
    if (pass36_catalog.resolution_order[1].level != .instance) return error.GateFailed;
    // Rung 3 is the sealed-world collapse target (G5).
    if (pass36_catalog.resolution_order[2].level != .descriptor) return error.GateFailed;
}

/// Pass 41 A3 — the compaction is the point: Lua must NOT have its own rung, and
/// `dynamic` must be the single last resolution layer before structured failure.
/// If a Lua-specific rung reappears, the sealed-world proof gets more expensive
/// and gain #3 is silently reversed.
pub fn proveLadderCompactedToEightRungs() GateError!void {
    var resolving_rungs: usize = 0;
    for (pass36_catalog.resolution_order) |step| {
        if (step.level != .failure) resolving_rungs += 1;
    }
    if (resolving_rungs != 8) return error.GateFailed;

    // Lua appears in the ladder only as part of the generic `foreign` rung.
    for (pass36_catalog.resolution_order) |step| {
        const mentions_lua = std.mem.indexOf(u8, step.description, "Lua") != null;
        if (mentions_lua and step.level != .foreign and step.level != .dynamic) return error.GateFailed;
    }
    const dynamic_rung = pass36_catalog.resolution_order[7];
    if (dynamic_rung.level != .dynamic) return error.GateFailed;

    const s7 = pass36_catalog.findSupersession("S7") orelse return error.GateFailed;
    if (s7.status != .adopted) return error.GateFailed;
}

/// Pass 41 A2 — the `__` namespace is deleted from canon. Double-underscore
/// names may appear ONLY in `lua_adapter_targets` and in graveyard reasons. If
/// one leaks into an access form, a grammar rule, an operator projection, or an
/// idiom, the second namespace is back.
pub fn proveDoubleUnderscoreNamespaceDeleted() GateError!void {
    for (pass36_catalog.access_forms) |f| {
        if (std.mem.indexOf(u8, f.syntax, "__") != null) return error.GateFailed;
    }
    for (pass36_catalog.grammar_rules) |r| {
        if (std.mem.indexOf(u8, r.form, "__") != null) return error.GateFailed;
    }
    for (pass36_catalog.operator_projections) |o| {
        if (std.mem.indexOf(u8, o.root, "__") != null) return error.GateFailed;
        if (std.mem.indexOf(u8, o.syntax, "__") != null) return error.GateFailed;
    }
    for (pass36_catalog.idioms) |i| {
        if (std.mem.indexOf(u8, i.example, "__") != null) return error.GateFailed;
    }
    // The adapter is where they survive — as emission targets only.
    for (pass36_catalog.lua_adapter_targets) |t| {
        if (std.mem.indexOf(u8, t.emits, "__") == null) return error.GateFailed;
        if (std.mem.indexOf(u8, t.root, "__") != null) return error.GateFailed;
        if (t.root[0] != '@') return error.GateFailed;
    }
}

/// Pass 41 A5 — the operator inventory is chosen, not inherited: `!=` is present
/// and `~=` is buried. The set stays closed (compiler-owned) regardless.
pub fn proveOperatorInventoryChosenOnMerit() GateError!void {
    var saw_bang_eq = false;
    for (pass36_catalog.operator_projections) |op| {
        if (op.root.len == 0 or op.syntax.len == 0) return error.GateFailed;
        if (op.root[0] != '@') return error.GateFailed;
        if (std.mem.eql(u8, op.syntax, "!=")) {
            saw_bang_eq = true;
            if (!op.chosen_over_inherited) return error.GateFailed;
            if (!std.mem.eql(u8, op.root, "@eq")) return error.GateFailed;
        }
        if (std.mem.eql(u8, op.syntax, "~=")) return error.GateFailed;
    }
    if (!saw_bang_eq) return error.GateFailed;
    if (!pass36_catalog.isRejected("~=")) return error.GateFailed;
}

/// Pass 41 A8 — getmetatable/setmetatable do not exist in the language, and no
/// idiom or smell may present them as a supported boundary form.
pub fn proveMetatableApiDeleted() GateError!void {
    if (!pass36_catalog.isRejected("getmetatable / setmetatable")) return error.GateFailed;
    for (pass36_catalog.access_forms) |f| {
        if (std.mem.indexOf(u8, f.syntax, "getmetatable") != null) return error.GateFailed;
        if (std.mem.indexOf(u8, f.syntax, "setmetatable") != null) return error.GateFailed;
    }
    // meta(level)(value) is the replacement, and it must be an ordinary value:
    // the effective view is readable but never an assignment target.
    var saw_effective = false;
    for (pass36_catalog.level_selectors) |sel| {
        if (sel.spelling.len == 0) return error.GateFailed;
        if (std.mem.indexOf(u8, sel.spelling, "meta(") == null) return error.GateFailed;
        if (sel.level == .effective) {
            saw_effective = true;
            if (sel.assignable) return error.GateFailed;
        } else if (!sel.assignable) return error.GateFailed;
    }
    if (!saw_effective) return error.GateFailed;
}

/// Every conflict class maps to exactly one resolution, and genuine ambiguity
/// must not resolve to the dynamic layer: that would silently defeat G5.
pub fn proveConflictAlgebraDecidable() GateError!void {
    inline for (@typeInfo(pass36_catalog.ConflictClass).@"enum".field_values) |v| {
        const class: pass36_catalog.ConflictClass = @enumFromInt(v);
        var matches: usize = 0;
        for (pass36_catalog.conflict_rules) |rule| {
            if (rule.class == class) matches += 1;
        }
        if (matches != 1) return error.GateFailed;
    }
    for (pass36_catalog.conflict_rules) |rule| {
        if (rule.rationale.len == 0) return error.GateFailed;
    }
    if (pass36_catalog.resolutionFor(.ambiguous) != .reject_with_candidates) return error.GateFailed;
    if (pass36_catalog.resolutionFor(.incompatible) != .reject_with_candidates) return error.GateFailed;
    if (pass36_catalog.resolutionFor(.explicitly_blocked) != .drop_projection) return error.GateFailed;
}

/// Authority must be a total order with `canonical` strictly on top and
/// `observed` strictly at the bottom.
pub fn proveAuthorityOrderingTotal() GateError!void {
    const A = pass36_catalog.ProjectionAuthority;
    inline for (@typeInfo(A).@"enum".field_values) |v| {
        const a: A = @enumFromInt(v);
        if (a != .canonical and !A.canonical.outranks(a)) return error.GateFailed;
        if (a != .observed and !a.outranks(.observed)) return error.GateFailed;
    }
    if (!A.source_owned.outranks(.generated)) return error.GateFailed;
    if (!A.local_override.outranks(.generated)) return error.GateFailed;
}

/// Pass 39 R4 — three intentional slot states plus absence. Blocking must be
/// distinguishable from yielding, or `= false` and `= nil` collapse into one
/// meaning and the user loses a control.
pub fn proveThreeValuedSlots() GateError!void {
    var saw: [4]bool = @splat(false);
    for (pass36_catalog.slot_rules) |rule| {
        if (rule.syntax.len == 0 or rule.effect.len == 0) return error.GateFailed;
        saw[@intFromEnum(rule.state)] = true;
    }
    for (saw) |s| {
        if (!s) return error.GateFailed;
    }
    for (pass36_catalog.slot_rules) |rule| {
        switch (rule.state) {
            .blocked => if (std.mem.indexOf(u8, rule.syntax, "false") == null) return error.GateFailed,
            .revealed => if (std.mem.indexOf(u8, rule.syntax, "nil") == null) return error.GateFailed,
            else => {},
        }
    }
}

/// Maximum projection surface, minimum emission. A family that is not
/// demand-driven must not be able to materialize an artifact, or an unconsumed
/// projection could still emit a symbol (gate 13).
pub fn proveEagerFamiliesNeverMaterialize() GateError!void {
    for (pass36_catalog.projection_families) |fam| {
        if (fam.id.len == 0 or fam.section.len == 0 or fam.title.len == 0) return error.GateFailed;
        if (!fam.demand_driven and fam.materializes) return error.GateFailed;
    }
    // The operator projection is the one always-available family; it is
    // normalizing, so it must never materialize.
    var saw_operator = false;
    for (pass36_catalog.projection_families) |fam| {
        if (std.mem.eql(u8, fam.id, "P-OPERATOR")) {
            saw_operator = true;
            if (fam.demand_driven or fam.materializes) return error.GateFailed;
        }
    }
    if (!saw_operator) return error.GateFailed;

    // A1 — the Lua adapter is a demand-driven foreign projection family, not an
    // always-on invariant. If it ever became eager, gate 13 would be unprovable.
    var saw_lua = false;
    for (pass36_catalog.projection_families) |fam| {
        if (std.mem.eql(u8, fam.id, "P-FOREIGN-LUA")) {
            saw_lua = true;
            if (!fam.demand_driven) return error.GateFailed;
        }
    }
    if (!saw_lua) return error.GateFailed;
}

/// Every completion gate must name an execution phase that exists, and every
/// phase from PH2 onward must be reachable from at least one gate.
pub fn proveCompletionGatesRouteToPhases() GateError!void {
    var expected: u8 = 1;
    for (pass36_catalog.completion_gates) |g| {
        if (g.number != expected) return error.GateFailed;
        if (g.statement.len == 0 or g.evidence.len == 0) return error.GateFailed;
        var found = false;
        for (pass36_catalog.execution_phases) |ph| {
            if (std.mem.eql(u8, ph.id, g.phase)) found = true;
        }
        if (!found) return error.GateFailed;
        expected += 1;
    }

    for (pass36_catalog.execution_phases) |ph| {
        if (ph.phase < 2) continue; // PH0 records, PH1 buries; neither closes a gate
        var referenced = false;
        for (pass36_catalog.completion_gates) |g| {
            if (std.mem.eql(u8, g.phase, ph.id)) referenced = true;
        }
        if (!referenced) return error.GateFailed;
    }
}

/// Phase 0 discipline: nothing is implemented yet, and nothing claims to be
/// blocked by a supersession that has already been adopted.
pub fn proveGrammarPhase0Status() GateError!void {
    for (pass36_catalog.grammar_rules) |rule| {
        if (rule.form.len == 0 or rule.meaning.len == 0) return error.GateFailed;
        switch (rule.status) {
            .blocked => {
                const s = pass36_catalog.findSupersession(rule.blocked_by) orelse return error.GateFailed;
                if (s.status == .adopted) return error.GateFailed;
            },
            .recorded, .implemented => {
                if (!std.mem.eql(u8, rule.blocked_by, "NONE")) return error.GateFailed;
            },
        }
    }
}

/// Every supersession must state what it supersedes and why. Pass 39's
/// governance rule made explicit: a contradiction without a record is not canon.
pub fn proveSupersessionsRecorded() GateError!void {
    const required = [_][]const u8{ "S4", "S5", "S6", "S7" };
    for (required) |id| {
        const s = pass36_catalog.findSupersession(id) orelse return error.GateFailed;
        if (s.ruling.len == 0 or s.supersedes.len == 0 or s.rationale.len == 0) return error.GateFailed;
        if (s.status != .adopted) return error.GateFailed;
    }
}

/// The sealed-world collapse is the performance thesis; both its preconditions
/// and its guarantees must be recorded, or G5 has nothing to check against.
pub fn proveSealedWorldCollapseRecorded() GateError!void {
    if (pass36_catalog.sealed_world_conditions.len == 0) return error.GateFailed;
    if (pass36_catalog.sealed_world_guarantees.len == 0) return error.GateFailed;
    for (pass36_catalog.sealed_world_conditions) |c| {
        if (c.len == 0) return error.GateFailed;
    }
    for (pass36_catalog.sealed_world_guarantees) |g| {
        if (g.len == 0) return error.GateFailed;
    }
    // Gate 20 is the one that fails the build on hot-path regression.
    const g20 = pass36_catalog.findCompletionGate(20) orelse return error.GateFailed;
    if (std.mem.indexOf(u8, g20.evidence, "rung 3") == null) return error.GateFailed;
}

pub fn proveCanonicalDocsLinked() GateError!void {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();
    cwd.access(io, pass36_catalog.CANONICAL_PATH, .{}) catch return error.GateFailed;
    cwd.access(io, pass36_catalog.PLAN_PATH, .{}) catch return error.GateFailed;
}

pub fn validatePass36Gate(_: std.mem.Allocator) GateError!void {
    try validateCatalogSchema();
    try proveDesugaringGraphClosedAndAcyclic();
    try proveOperatorNormalizesToInvocation();
    try proveNoFormIsReceiverBound();
    try proveGraveyardStaysBuried();
    try provePrefixOnlyDiscipline();
    try proveResolutionLadderIsStrictTotal();
    try proveLadderCompactedToEightRungs();
    try proveDoubleUnderscoreNamespaceDeleted();
    try proveOperatorInventoryChosenOnMerit();
    try proveMetatableApiDeleted();
    try proveConflictAlgebraDecidable();
    try proveAuthorityOrderingTotal();
    try proveThreeValuedSlots();
    try proveEagerFamiliesNeverMaterialize();
    try proveCompletionGatesRouteToPhases();
    try proveGrammarPhase0Status();
    try proveSupersessionsRecorded();
    try proveSealedWorldCollapseRecorded();
    try proveCanonicalDocsLinked();
}

test "pass36 gate: Phase 0 final semantic access calculus proofs" {
    try validatePass36Gate(std.testing.allocator);
}
