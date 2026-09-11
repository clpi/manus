//! Shared graph-to-DNIR validation: computed aggregate projections, and the
//! shape of a relation's result pack.
//!
//! Native and Wasm consume the same physical schedule. This module is the one
//! admission question both ask before emitting bytes; neither backend may
//! reconstruct aggregate contents or accept a row the other rejects.
const std = @import("std");
const dnir = @import("native/ir.zig");

pub const Failure = struct {
    note: []const u8,
    application: ?dnir.SemanticId = null,
};

fn failed(note: []const u8, application: ?dnir.SemanticId) Failure {
    return .{ .note = note, .application = application };
}

fn aggregateRoot(
    graph: *const dnir.SemanticGraph,
    occurrence: dnir.SemanticId,
) ?dnir.SemanticId {
    var subject = graph.applicationSubject(occurrence) orelse return null;
    var traversed: usize = 0;
    while (graph.aggregateProducer(subject)) |producer| {
        if (traversed >= graph.aggregateCount()) return null;
        subject = graph.applicationSubject(producer) orelse return null;
        traversed += 1;
    }
    return if (graph.aggregate(subject) != null) subject else null;
}

fn denseRowFor(module: dnir.Module, root: dnir.SemanticId) ?*const dnir.DenseTable {
    var found: ?*const dnir.DenseTable = null;
    for (module.dense_tables) |*table| {
        if (table.value != root) continue;
        if (found != null) return null;
        found = table;
    }
    return found;
}

fn denseRowUsed(
    module: dnir.Module,
    graph: *const dnir.SemanticGraph,
    root: dnir.SemanticId,
) bool {
    for (module.functions) |function| {
        for (function.blocks) |block| {
            for (block.instrs) |instruction| {
                if (instruction.op != .load_index) continue;
                const occurrence = instruction.application orelse continue;
                if (graph.aggregateAccess(occurrence) == null) continue;
                if (aggregateRoot(graph, occurrence) == root) return true;
            }
        }
    }
    return false;
}

fn validateDenseRows(
    module: dnir.Module,
    graph: *const dnir.SemanticGraph,
) ?Failure {
    for (module.dense_tables, 0..) |table, i| {
        if (table.elem_ty != .i64 or table.values.len == 0)
            return failed("aggregate-dense-table-shape", null);
        if (graph.aggregate(table.value) == null or !graph.aggregateIsSoleImmutableBinding(table.value))
            return failed("aggregate-dense-table-facts", null);
        if (!graph.aggregateExactI64WordsMatch(table.value, table.values))
            return failed("aggregate-dense-table-content", null);
        for (module.dense_tables[0..i]) |prior| {
            if (prior.value == table.value)
                return failed("aggregate-dense-table-duplicate", null);
        }
        if (!denseRowUsed(module, graph, table.value))
            return failed("aggregate-dense-table-unused", null);
    }
    return null;
}

fn hasSemanticLineage(module: dnir.Module) bool {
    for (module.functions) |function| {
        for (function.blocks) |block| {
            for (block.instrs) |instruction| {
                if (instruction.application != null or instruction.relation != null or
                    instruction.subject != null or instruction.target != null or
                    instruction.value != null or instruction.realization_start != null)
                {
                    return true;
                }
            }
        }
    }
    return false;
}

fn validateRootMarker(
    module: dnir.Module,
    function: dnir.Function,
    graph: *const dnir.SemanticGraph,
    root: dnir.SemanticId,
) union(enum) { valid: u32, failure: Failure } {
    const dense = denseRowFor(module, root) orelse
        return .{ .failure = failed("aggregate-dense-table", null) };
    var base: ?u32 = null;
    for (function.blocks) |block| {
        for (block.instrs) |instruction| {
            if (instruction.aggregate != root) continue;
            if (instruction.op != .alloc_slots or instruction.result == null or
                instruction.ty != .i64 or instruction.lhs != .i64 or
                instruction.lhs.i64 != @as(i64, std.math.cast(u32, dense.values.len) orelse
                    return .{ .failure = failed("aggregate-dense-table-shape", null) }))
            {
                return .{ .failure = failed("aggregate-root-marker", null) };
            }
            if (base != null)
                return .{ .failure = failed("aggregate-root-marker-count", null) };
            base = instruction.result.?;
        }
    }
    _ = graph;
    return if (base) |slot|
        .{ .valid = slot }
    else
        .{ .failure = failed("aggregate-root-marker", null) };
}

fn validateInstruction(
    module: dnir.Module,
    function: dnir.Function,
    graph: *const dnir.SemanticGraph,
    occurrence: dnir.SemanticId,
    instruction: dnir.Instr,
) ?Failure {
    const fact = graph.aggregateAccess(occurrence) orelse
        return failed("aggregate-access-facts", occurrence);
    const relation = graph.applicationRelation(occurrence) orelse
        return failed("aggregate-access-relation", occurrence);
    const subject = graph.applicationSubject(occurrence) orelse
        return failed("aggregate-access-subject", occurrence);
    const target = graph.applicationTarget(occurrence) orelse
        return failed("aggregate-access-target", occurrence);
    const applied = graph.applicationApplied(occurrence) orelse
        return failed("aggregate-access-applied", occurrence);
    const results = graph.applicationResults(occurrence) orelse
        return failed("aggregate-result-pack", occurrence);
    if (results.len != 1) return failed("aggregate-access-pack-arity", occurrence);
    const result = results[0];
    const descriptor = graph.applicationDescriptor(occurrence) orelse
        return failed("aggregate-result-descriptor", occurrence);
    if (instruction.application != occurrence or instruction.relation != relation or
        instruction.subject != subject or instruction.target != target or
        instruction.value != result or !instruction.ty.eql(descriptor) or
        fact.application != occurrence or applied != subject or target != relation or
        instruction.realization_start == null)
    {
        return failed("aggregate-access-lineage", occurrence);
    }
    const root = aggregateRoot(graph, occurrence) orelse
        return failed("aggregate-access-root", occurrence);
    if (!graph.aggregateIsSoleImmutableBinding(root))
        return failed("aggregate-access-place", occurrence);
    const root_node = graph.get(root) orelse
        return failed("aggregate-access-root", occurrence);
    const root_descriptor = root_node.descriptor orelse
        return failed("aggregate-access-root", occurrence);
    if (root_descriptor != .array)
        return failed("aggregate-access-root", occurrence);
    if (instruction.aggregate != null or instruction.callee.len != 0 or
        instruction.record.len != 0 or instruction.pack_results.len != 0)
    {
        return failed("aggregate-access-realization", occurrence);
    }

    switch (descriptor) {
        .array => {
            if (instruction.op != .store_local or instruction.result == null or
                instruction.lhs == .void or instruction.rhs != .void)
            {
                return failed("aggregate-access-realization-op", occurrence);
            }
        },
        .i64 => switch (instruction.op) {
            .@"const" => {
                if (root_descriptor.array.elem.* == .array or instruction.result == null or
                    instruction.lhs != .i64 or instruction.rhs != .void)
                {
                    return failed("aggregate-access-realization-op", occurrence);
                }
                const content = graph.exactI64(result) orelse
                    return failed("aggregate-access-realization-op", occurrence);
                if (instruction.lhs.i64 != content)
                    return failed("aggregate-access-realization-op", occurrence);
            },
            .load_index => {
                const marker = validateRootMarker(module, function, graph, root);
                const base = switch (marker) {
                    .valid => |slot| slot,
                    .failure => |failure| return failure,
                };
                if (instruction.result == null or instruction.lhs != .temp or
                    instruction.lhs.temp != base or
                    (instruction.rhs != .temp and instruction.rhs != .local))
                {
                    return failed("aggregate-access-realization-op", occurrence);
                }
            },
            else => return failed("aggregate-access-realization-op", occurrence),
        },
        else => return failed("aggregate-access-realization-descriptor", occurrence),
    }
    return null;
}

fn absentCount(module: dnir.Module, occurrence: dnir.SemanticId) usize {
    var count: usize = 0;
    for (module.functions) |function| {
        for (function.absent_applications) |absent| {
            if (absent == occurrence) count += 1;
        }
    }
    return count;
}

fn absentConsumerExists(
    module: dnir.Module,
    graph: *const dnir.SemanticGraph,
    value: dnir.SemanticId,
) bool {
    for (module.functions) |function| {
        for (function.absent_applications) |occurrence| {
            const subject = graph.applicationSubject(occurrence) orelse continue;
            if (subject == value) return true;
        }
    }
    return false;
}

/// Validate lawful nonexecution once for every backend. A named absence is not
/// a bookkeeping exemption: it must be one graph-owned aggregate projection,
/// belong to the exact caller function, occur once, and carry either the exact
/// result that removed it or an absent downstream projection consuming that
/// result. The per-occurrence schedule below separately proves it emitted no
/// instruction.
fn validateAbsentApplications(
    module: dnir.Module,
    graph: *const dnir.SemanticGraph,
) ?Failure {
    for (module.functions) |function| {
        for (function.absent_applications) |occurrence| {
            if (absentCount(module, occurrence) != 1)
                return failed("absent-application-count", occurrence);
            if (graph.application(occurrence) == null or
                graph.isBootstrapApplicationNode(occurrence))
            {
                return failed("absent-application-unpublished", occurrence);
            }
            _ = graph.aggregateAccess(occurrence) orelse
                return failed("absent-application-witness", occurrence);
            const caller = graph.applicationCaller(occurrence) orelse
                return failed("absent-application-caller", occurrence);
            if (function.id == null or function.id.? != caller)
                return failed("absent-application-caller", occurrence);
            const results = graph.applicationResults(occurrence) orelse
                return failed("absent-application-witness", occurrence);
            if (results.len != 1)
                return failed("absent-application-witness", occurrence);
            if (graph.exactI64(results[0]) == null and
                !absentConsumerExists(module, graph, results[0]))
            {
                return failed("absent-application-witness", occurrence);
            }
        }
    }
    return null;
}

/// Validate every graph-owned computed aggregate projection and every dense
/// row before any backend emits bytes. Null means the schedule is exact.
pub fn aggregateSchedule(module: dnir.Module) ?Failure {
    const graph = module.graph orelse {
        if (module.dense_tables.len != 0)
            return failed("aggregate-dense-table-graph", null);
        if (hasSemanticLineage(module))
            return failed("realization-graph", null);
        return null;
    };
    if (validateDenseRows(module, graph)) |failure| return failure;
    if (validateAbsentApplications(module, graph)) |failure| return failure;

    for (graph.nodes.items, 0..) |_, coordinate| {
        const occurrence: dnir.SemanticId = @intCast(coordinate);
        if (!graph.isAggregateAccessApplication(occurrence)) continue;
        _ = graph.aggregateAccess(occurrence) orelse
            return failed("aggregate-access-facts", occurrence);

        var realized: usize = 0;
        var folded = false;
        const absent = absentCount(module, occurrence);
        const caller = graph.applicationCaller(occurrence) orelse
            return failed("aggregate-access-caller", occurrence);
        for (module.functions) |function| {
            if (function.id == caller and function.folded_to_constant) folded = true;
            for (function.blocks) |block| {
                for (block.instrs) |instruction| {
                    if (instruction.application != occurrence) continue;
                    realized += 1;
                    if (function.id != caller)
                        return failed("aggregate-access-caller", occurrence);
                    if (validateInstruction(module, function, graph, occurrence, instruction)) |failure|
                        return failure;
                }
            }
        }
        if (folded) {
            if (realized != 0 or absent != 0)
                return failed("folded-application-lineage", occurrence);
        } else if (absent == 1) {
            if (realized != 0)
                return failed("absent-application-count", occurrence);
        } else if (realized != 1) {
            return failed("application-realization-count", occurrence);
        }
    }
    return null;
}

// ---------------------------------------------------------------------------
// RESULT PACKS
//
// A relation that answers with SEVERAL VALUES has one declared shape and two
// physical spellings of it: `Function.ret_pack` (a tuple result type) and
// `Function.ret_record` (a named record result type). Source cannot be both at
// once, so exactly one is populated — and each backend used to validate only
// the spelling it happened to consume. AArch64 checked `ret_pack` arity at the
// return and never the record's; wasm rebuilt the arity from `ret_record` and
// refused `ret_pack` outright. NOTHING checked that the two agreed with each
// other or with the call sites that project them, so a lowering that
// disagreed with itself would have produced two different arities on the two
// targets with neither backend objecting. That is the divergence this section
// removes: one producer of "how many values does this relation answer with",
// asked once, before either backend emits a byte.
//
// WHAT IS DELIBERATELY *NOT* HERE. `dnir_lower.max_reg_record_fields` (8) is
// AAPCS64's register-return window, and crossing it selects the x8
// indirect-result convention; wasm multi-value has no such window and needs no
// such choice. An all-f64 record return is realized on AArch64 through the FP
// register file and is refused by the wasm emitter. Both are TARGET facts
// about a shape that is semantically legal, so both stay in their backend —
// moving them here would make one target's ABI into Idol's semantics.
// ---------------------------------------------------------------------------

/// A relation's declared result pack: how many values it answers with, and the
/// record naming them when it has one. THE ONE PRODUCER of that fact; a
/// backend that re-derives it is the defect this exists to prevent.
pub const ResultPack = struct {
    arity: usize,
    record: ?dnir.RecordDesc = null,
};

/// Null means the relation names a result record this module does not define.
/// `resultPackShape` reports that as a refusal, so a backend calling this
/// after the shared validation has passed may treat null as impossible input
/// rather than a second independent admission question.
pub fn resultPackOf(module: dnir.Module, function: dnir.Function) ?ResultPack {
    if (function.ret_record) |name| {
        const record = dnir.findRecord(module, name) orelse return null;
        return .{ .arity = record.fields.len, .record = record };
    }
    return .{ .arity = function.ret_pack.len };
}

fn moduleFunction(module: dnir.Module, name: []const u8) ?dnir.Function {
    if (name.len == 0) return null;
    for (module.functions) |function| {
        if (std.mem.eql(u8, function.name, name)) return function;
    }
    return null;
}

/// The values a pack return answers with. `vals` is authoritative; the
/// `lhs`/`rhs`/`third` prefix is the older three-member spelling and CANNOT
/// express a fourth member, which is why a five-field record return once left
/// the caller reading whatever x3/x4 held.
fn returnPackValues(instruction: dnir.Instr, three: *[3]dnir.Value) []const dnir.Value {
    if (instruction.vals.len > 0) return instruction.vals;
    three.* = .{ instruction.lhs, instruction.rhs, instruction.third };
    var n: usize = 0;
    while (n < 3 and three[n] != .void) n += 1;
    return three[0..n];
}

fn validateResultPacks(module: dnir.Module) ?Failure {
    for (module.functions) |function| {
        if (function.ret_pack.len > 0 and function.ret_record != null)
            return failed("result-pack-dual-source", function.id);
        const pack = resultPackOf(module, function) orelse
            return failed("result-pack-record-unknown", function.id);
        if (pack.record) |record| {
            if (record.fields.len == 0)
                return failed("result-pack-record-empty", function.id);
            if (record.fields.len != record.kinds.len)
                return failed("result-pack-record-shape", function.id);
        }
        for (function.blocks) |block| {
            for (block.instrs) |instruction| switch (instruction.op) {
                .ret => {
                    // A value-carrying scalar return out of a relation that
                    // declared several results answers one of them and leaves
                    // the rest to whatever the ABI slot held.
                    if (pack.arity > 1 and instruction.lhs != .void)
                        return failed("result-pack-scalar-return", function.id);
                },
                .ret_pack => {
                    if (function.ret_pack.len == 0)
                        return failed("result-pack-form", function.id);
                    if (instruction.vals.len != pack.arity)
                        return failed("result-pack-declared-arity", function.id);
                },
                .ret_record => {
                    const record = pack.record orelse
                        return failed("result-pack-form", function.id);
                    var three: [3]dnir.Value = undefined;
                    if (returnPackValues(instruction, &three).len != pack.arity)
                        return failed("result-pack-declared-arity", function.id);
                    if (instruction.record.len != 0 and
                        !std.mem.eql(u8, instruction.record, record.name))
                    {
                        return failed("result-pack-record-mismatch", function.id);
                    }
                },
                .call_direct => {
                    // A foreign or not-yet-lowered callee has no declared pack
                    // here to disagree with; its boundary is checked elsewhere.
                    const callee = moduleFunction(module, instruction.callee) orelse continue;
                    const callee_pack = resultPackOf(module, callee) orelse
                        return failed("result-pack-record-unknown", function.id);
                    if (instruction.pack_results.len != 0 and
                        instruction.pack_results.len != callee_pack.arity)
                    {
                        return failed("result-pack-call-arity", function.id);
                    }
                    if (instruction.record.len != 0) {
                        const record = callee_pack.record orelse
                            return failed("result-pack-call-record", function.id);
                        if (!std.mem.eql(u8, instruction.record, record.name))
                            return failed("result-pack-call-record", function.id);
                    }
                },
                else => {},
            };
        }
    }
    return null;
}

/// Validate every relation's declared result pack and every realization of it
/// before any backend emits bytes. Null means the pack shape is exact.
pub fn resultPackShape(module: dnir.Module) ?Failure {
    return validateResultPacks(module);
}

// ---------------------------------------------------------------------------
// RESULT-PACK CONTROLS
//
// Every case below is stated as a HAND-BUILT physical module rather than as
// source, because the question is whether the validator refuses a schedule the
// two backends would have realized differently — and only one of them could
// ever be reached from lowering at a time. A control that can only be produced
// by breaking lowering is exactly the one worth pinning.
// ---------------------------------------------------------------------------

const control_pair = dnir.RecordDesc{
    .name = "Pair",
    .fields = &.{ "a", "b" },
    .kinds = &.{ .i64, .i64 },
};

fn controlModule(functions: []const dnir.Function) dnir.Module {
    return .{ .functions = functions, .records = &.{control_pair} };
}

fn controlBlocks(instrs: []const dnir.Instr) [1]dnir.Block {
    return .{.{ .instrs = instrs }};
}

test "result pack: an exact record return is admitted" {
    var blocks = controlBlocks(&.{
        .{ .op = .ret_record, .record = "Pair", .vals = &.{ .{ .i64 = 1 }, .{ .i64 = 2 } } },
    });
    const module = controlModule(&.{.{
        .name = "pair",
        .ret = .i64,
        .ret_record = "Pair",
        .blocks = &blocks,
    }});
    try std.testing.expect(resultPackShape(module) == null);
}

test "result pack: a record return short of its declared arity is refused" {
    var blocks = controlBlocks(&.{
        .{ .op = .ret_record, .record = "Pair", .vals = &.{.{ .i64 = 1 }} },
    });
    const module = controlModule(&.{.{
        .name = "pair",
        .ret = .i64,
        .ret_record = "Pair",
        .blocks = &blocks,
    }});
    const failure = resultPackShape(module) orelse return error.TestExpectedRefusal;
    try std.testing.expectEqualStrings("result-pack-declared-arity", failure.note);
}

test "result pack: the three-member spelling counts the same as vals" {
    // `lhs`/`rhs`/`third` is the older encoding of the same return, and both
    // backends decode it. Two members present, two declared: admitted.
    var blocks = controlBlocks(&.{
        .{ .op = .ret_record, .record = "Pair", .lhs = .{ .i64 = 1 }, .rhs = .{ .i64 = 2 } },
    });
    const module = controlModule(&.{.{
        .name = "pair",
        .ret = .i64,
        .ret_record = "Pair",
        .blocks = &blocks,
    }});
    try std.testing.expect(resultPackShape(module) == null);
}

test "result pack: a tuple return declared as a record is refused" {
    // THE DIVERGENCE THIS SECTION EXISTS FOR. AArch64 measured this return
    // against `ret_pack` and wasm against `ret_record`; with both populated
    // the two targets read two different arities and neither objected.
    var blocks = controlBlocks(&.{
        .{ .op = .ret_pack, .vals = &.{ .{ .i64 = 1 }, .{ .i64 = 2 } } },
    });
    const module = controlModule(&.{.{
        .name = "pair",
        .ret = .i64,
        .ret_pack = &.{ .i64, .i64 },
        .ret_record = "Pair",
        .blocks = &blocks,
    }});
    const failure = resultPackShape(module) orelse return error.TestExpectedRefusal;
    try std.testing.expectEqualStrings("result-pack-dual-source", failure.note);
}

test "result pack: a named result record this module never defines is refused" {
    var blocks = controlBlocks(&.{
        .{ .op = .ret_record, .vals = &.{.{ .i64 = 1 }} },
    });
    const module = controlModule(&.{.{
        .name = "pair",
        .ret = .i64,
        .ret_record = "Absent",
        .blocks = &blocks,
    }});
    const failure = resultPackShape(module) orelse return error.TestExpectedRefusal;
    try std.testing.expectEqualStrings("result-pack-record-unknown", failure.note);
}

test "result pack: a scalar return carrying one member of a pack is refused" {
    var blocks = controlBlocks(&.{
        .{ .op = .ret, .lhs = .{ .i64 = 1 } },
    });
    const module = controlModule(&.{.{
        .name = "pair",
        .ret = .i64,
        .ret_record = "Pair",
        .blocks = &blocks,
    }});
    const failure = resultPackShape(module) orelse return error.TestExpectedRefusal;
    try std.testing.expectEqualStrings("result-pack-scalar-return", failure.note);
}

test "result pack: a return form the relation did not declare is refused" {
    var blocks = controlBlocks(&.{
        .{ .op = .ret_record, .record = "Pair", .vals = &.{ .{ .i64 = 1 }, .{ .i64 = 2 } } },
    });
    const module = controlModule(&.{.{
        .name = "pair",
        .ret = .i64,
        .ret_pack = &.{ .i64, .i64 },
        .blocks = &blocks,
    }});
    const failure = resultPackShape(module) orelse return error.TestExpectedRefusal;
    try std.testing.expectEqualStrings("result-pack-form", failure.note);
}

test "result pack: a call projecting the wrong number of members is refused" {
    var callee_blocks = controlBlocks(&.{
        .{ .op = .ret_pack, .vals = &.{ .{ .i64 = 1 }, .{ .i64 = 2 } } },
    });
    var caller_blocks = controlBlocks(&.{
        .{
            .op = .call_direct,
            .callee = "pair",
            .pack_results = &.{.{ .value = 0, .temp = 0, .ty = .i64 }},
        },
        .{ .op = .ret, .lhs = .{ .temp = 0 } },
    });
    const module = controlModule(&.{
        .{ .name = "pair", .ret = .i64, .ret_pack = &.{ .i64, .i64 }, .blocks = &callee_blocks },
        .{ .name = "main", .ret = .i64, .blocks = &caller_blocks },
    });
    const failure = resultPackShape(module) orelse return error.TestExpectedRefusal;
    try std.testing.expectEqualStrings("result-pack-call-arity", failure.note);
}

test "result pack: a call naming a record its callee does not answer is refused" {
    var callee_blocks = controlBlocks(&.{
        .{ .op = .ret, .lhs = .{ .i64 = 1 } },
    });
    var caller_blocks = controlBlocks(&.{
        .{ .op = .call_direct, .callee = "one", .record = "Pair", .result = 0 },
        .{ .op = .ret, .lhs = .{ .temp = 0 } },
    });
    const module = controlModule(&.{
        .{ .name = "one", .ret = .i64, .blocks = &callee_blocks },
        .{ .name = "main", .ret = .i64, .blocks = &caller_blocks },
    });
    const failure = resultPackShape(module) orelse return error.TestExpectedRefusal;
    try std.testing.expectEqualStrings("result-pack-call-record", failure.note);
}

test "result pack: a scalar module is untouched by the pack validator" {
    var blocks = controlBlocks(&.{
        .{ .op = .ret, .lhs = .{ .i64 = 7 } },
    });
    const module = dnir.Module{ .functions = &.{.{
        .name = "main",
        .ret = .i64,
        .blocks = &blocks,
    }} };
    try std.testing.expect(resultPackShape(module) == null);
}
