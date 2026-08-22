//! Shared graph-to-DNIR validation for computed aggregate projections.
//!
//! Native and Wasm consume the same physical schedule. This module is the one
//! admission question both ask before emitting bytes; neither backend may
//! reconstruct aggregate contents or accept a row the other rejects.
const std = @import("std");
const dnir = @import("native_ir.zig");

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
