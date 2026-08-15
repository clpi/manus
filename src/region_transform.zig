//! DNIR transformations selected from physical coordinates and dependencies.
//!
//! COST MONOTONICITY — the one rule every phase in this file answers to.
//!
//! A rewrite that can make the emitted program longer must not fire. Folding is
//! not free: an ARM64 register read is one instruction and a wide immediate is
//! up to four, so "replace a slot read with the constant it holds" ADDS
//! instructions whenever the producer survives to be read by somebody else.
//! That is not hypothetical — it is measured, twice, in this file's tests:
//! `sha.out` grew 8 instructions when propagation was allowed past a producer
//! with a second reader, and `p_wideshare.id` (an application keeping a wide
//! constant alive) grew 57 → 59 when a binop fold was allowed to orphan one.
//!
//! So every phase states what it removes and what it adds, in the same unit the
//! backend charges — `immediateCost`, mirrored from `native_backend.zig`'s own
//! `immCost` — and fires only when removed >= added. A phase that cannot
//! account for its own cost declines. Missing a fold is a measurement; growing
//! the program is a defect.
const std = @import("std");
const dnir = @import("native_ir.zig");
const region_graph = @import("region_graph.zig");
const semantic_graph = @import("semantic_graph.zig");
const types = @import("types.zig");

pub const TransformRecord = struct {
    function: u32,
    coordinate: u32,
    const_value: i64,
};

pub const ModuleTransformReport = struct {
    const_binop_fusions: u32 = 0,
    dead_const_pruned: u32 = 0,
    /// Slot operands rewritten to the immediate they physically resolve to.
    const_operands_propagated: u32 = 0,
    /// `store_local` instructions whose slot no consumer reads any more.
    dead_store_pruned: u32 = 0,
    /// Fixpoint rounds actually executed. One round cannot see a constant a
    /// previous round created, which is how `2 + 3 * 4` kept its outer `add`.
    rounds: u32 = 0,
};

pub const Error = error{
    OutOfMemory,
    ResidencyMismatch,
    CoordinateOverflow,
};

fn requireResidency(
    alloc: std.mem.Allocator,
    projection: region_graph.Projection,
    module: dnir.Module,
) Error!void {
    region_graph.validateModuleProjection(alloc, projection, module) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.CoordinateOverflow => return error.CoordinateOverflow,
        else => return error.ResidencyMismatch,
    };
}

const ConstantOrigin = struct {
    coordinate: u32,
    value: i64,
};

/// Instructions a `mov`/`movk` chain spends to materialize `value`: the count
/// of nonzero 16-bit lanes, minimum one. This mirrors `immCost` in
/// `native_backend.zig` — the backend's own model of what a constant costs —
/// deliberately, because a cost test that disagrees with the emitter is worse
/// than no cost test. It never underestimates: `movn` forms the emitter may
/// choose for negatives are cheaper than this says, so a fold that passes here
/// is at least as good as this claims.
fn immediateCost(value: i64) u8 {
    const bits: u64 = @bitCast(value);
    var lanes: u8 = 0;
    var shift: u6 = 0;
    while (true) {
        if (((bits >> shift) & 0xffff) != 0) lanes += 1;
        if (shift == 48) break;
        shift += 16;
    }
    return if (lanes == 0) 1 else lanes;
}

/// Whether this function's dead producers can actually be DELETED. Both prune
/// phases refuse the same two shapes, and every rewrite that pays for itself by
/// orphaning a producer has to agree with them: orphaning a producer nothing
/// will remove is how a fold turns into growth. One predicate so the three
/// cannot drift apart.
fn functionIsPrunable(function: dnir.Function) bool {
    return !functionHasApplicationLineage(&function) and !hasControlSplit(function);
}

/// A constant operand, and the slot it had to be read out of. A literal carries
/// no slot: nothing produces it, so folding it orphans nothing.
const ResolvedOperand = struct {
    value: i64,
    slot: ?u32,
};

fn resolveConstOperand(
    region: *const region_graph.Region,
    consumer: u32,
    value: dnir.Value,
    constants: *const std.AutoHashMapUnmanaged(u32, ConstantOrigin),
) ?ResolvedOperand {
    return switch (value) {
        .i64 => |number| .{ .value = number, .slot = null },
        .temp, .local => |slot| blk: {
            const origin = constants.get(slot) orelse break :blk null;
            const producer = region_graph.dependencyProducer(region, slot, consumer) orelse
                break :blk null;
            if (producer != origin.coordinate or producer >= consumer) break :blk null;
            break :blk .{ .value = origin.value, .slot = slot };
        },
        else => null,
    };
}

/// The only widths this pass may evaluate at. `evalConstBinop` wraps at 64
/// bits, which is the machine's own `add`/`sub`/`mul` shape, so a narrower
/// declared width would be folded at the wrong width and a float width would
/// be folded with the wrong arithmetic entirely. `.any` is admitted because
/// that is what `dnir_lower` writes on ordinary integer statements; an actual
/// float lands as `.f64` on the instruction AND as `.f64` on the operand
/// values, so both gates refuse it.
fn foldableIntType(ty: types.ResolvedType) bool {
    return ty == .i64 or ty == .any;
}

fn updateConstantOrigin(
    alloc: std.mem.Allocator,
    constants: *std.AutoHashMapUnmanaged(u32, ConstantOrigin),
    instruction: dnir.Instr,
    coordinate: u32,
) Error!void {
    const slot = dnir.definition(instruction) orelse return;
    const value = switch (instruction.op) {
        .@"const" => if (instruction.ty == .i64 and instruction.lhs == .i64)
            instruction.lhs.i64
        else
            null,
        .store_local => if (foldableIntType(instruction.ty) and instruction.lhs == .i64)
            instruction.lhs.i64
        else
            null,
        else => null,
    };
    if (value) |number| {
        try constants.put(alloc, slot, .{ .coordinate = coordinate, .value = number });
    } else {
        _ = constants.remove(slot);
    }
}

fn evalConstBinop(op: dnir.BinOpTag, left: i64, right: i64) ?i64 {
    return switch (op) {
        .add => left +% right,
        .sub => left -% right,
        .mul => left *% right,
        .div => if (right == 0 or (right == -1 and left == std.math.minInt(i64)))
            null
        else
            @divTrunc(left, right),
        .mod => if (right == 0 or (right == -1 and left == std.math.minInt(i64)))
            null
        else
            @rem(left, right),
        else => null,
    };
}

fn applicationFactsPresent(instruction: dnir.Instr) bool {
    return instruction.relation != null or instruction.application != null or
        instruction.value != null or instruction.subject != null or
        instruction.realization_start != null;
}

fn functionHasApplicationLineage(function: *const dnir.Function) bool {
    for (function.blocks) |block| {
        for (block.instrs) |instruction| {
            if (applicationFactsPresent(instruction)) return true;
        }
    }
    return false;
}

fn hasControlSplit(function: dnir.Function) bool {
    if (function.blocks.len != 1) return true;
    for (function.blocks[0].instrs) |instruction| {
        if (instruction.op == .br) return true;
    }
    return false;
}

fn flattenedLength(function: dnir.Function) Error!u32 {
    var total: u32 = 0;
    for (function.blocks) |block| {
        if (block.instrs.len > std.math.maxInt(u32)) return error.CoordinateOverflow;
        total = std.math.add(u32, total, @intCast(block.instrs.len)) catch
            return error.CoordinateOverflow;
    }
    return total;
}

/// Coordinates at which a previously established constant stops being known.
///
/// `br.branch_target` is a FLAT INSTRUCTION INDEX into the function, not a
/// block id: `dnir_lower` builds exactly one `Block` per function
/// (`dnir_lower.zig:1631`, `:1727`) and patches indices into that one list. So
/// a DNIR block is NOT a basic block, control lands wherever a target points,
/// and the straight-line runs have to be recovered here before anything may be
/// assumed to flow from one instruction to the next.
///
/// A leader is the first coordinate, the coordinate following any `br` (the
/// fall-through edge), and every `br` destination. Control can arrive at a
/// leader without having executed the instructions above it, so every constant
/// learned above it is dropped there.
fn markLeaders(
    alloc: std.mem.Allocator,
    function: dnir.Function,
    limit: u32,
) Error!std.DynamicBitSetUnmanaged {
    // One past `limit` so a branch to the fall-through end is representable
    // without a bounds test at every set site.
    var leaders = try std.DynamicBitSetUnmanaged.initEmpty(alloc, limit + 2);
    errdefer leaders.deinit(alloc);
    if (limit == 0) return leaders;
    leaders.set(1);

    var coordinate: u32 = 1;
    for (function.blocks) |block| {
        for (block.instrs) |instruction| {
            if (instruction.op == .br) {
                // Destination: flat index is 0-based, coordinates are 1-based.
                const destination = std.math.add(u32, instruction.branch_target, 1) catch
                    return error.CoordinateOverflow;
                if (destination <= limit + 1) leaders.set(destination);
                // Fall-through edge out of the branch.
                const next = std.math.add(u32, coordinate, 1) catch
                    return error.CoordinateOverflow;
                if (next <= limit + 1) leaders.set(next);
            }
            coordinate = std.math.add(u32, coordinate, 1) catch
                return error.CoordinateOverflow;
        }
    }
    return leaders;
}

/// One admissible-looking fold, with the cost account that decides it.
///
/// `slots` are the operands that had to be READ out of a slot; each carries the
/// cost of the producer that would be orphaned. A literal operand contributes
/// to `literal_relief` instead — there is no producer, only the immediate the
/// binop itself would have to encode.
const FusionCandidate = struct {
    function: u32,
    coordinate: u32,
    value: i64,
    slots: [2]?u32 = .{ null, null },
    producer_cost: [2]u8 = .{ 0, 0 },
    /// Materialization the operand literals stop charging once folded. An
    /// AArch64 add/sub immediate field is 12 bits and `mul` has no immediate
    /// form at all, so every `movk` past the first is certainly a real
    /// instruction that disappears; the first lane is charged as free because
    /// it may have been encoded in the operation.
    literal_relief: u8 = 0,
    admitted: bool = true,
};

/// COST TEST for one fold: `removed >= added`, where
///
///   added   = `immediateCost(result)` — the `const` that replaces the binop
///   removed = 1 (the binop instruction itself)
///           + for each orphaned producer that will actually be deleted, its
///             own materialization plus the one store that held it
///           + the literal relief above
///
/// A producer only counts as removed when the whole slot dies: EVERY reader of
/// it in this function is itself an admitted fold, and this function is one the
/// prune phases are allowed to touch. That is the `sha.out` lesson stated as
/// arithmetic — a producer with a surviving reader contributes nothing, so a
/// wide result has nothing to pay with and the fold declines.
fn candidateIsCostMonotone(
    function: dnir.Function,
    prunable: bool,
    candidate: FusionCandidate,
    folded_readers: *const std.AutoHashMapUnmanaged(u32, u32),
) bool {
    var removed: u32 = 1 + candidate.literal_relief;
    for (candidate.slots, candidate.producer_cost) |maybe_slot, cost| {
        const slot = maybe_slot orelse continue;
        if (!prunable) continue;
        const folded = folded_readers.get(slot) orelse 0;
        if (folded != tempUseCount(function, slot)) continue;
        removed += @as(u32, cost) + 1;
    }
    return immediateCost(candidate.value) <= removed;
}

fn collectFusionCandidates(
    alloc: std.mem.Allocator,
    projection: region_graph.Projection,
    module: dnir.Module,
) Error![]FusionCandidate {
    var candidates: std.ArrayListUnmanaged(FusionCandidate) = .empty;
    errdefer candidates.deinit(alloc);

    for (module.functions, projection.regions, 0..) |function, region, function_index| {
        const limit = try flattenedLength(function);
        var leaders = try markLeaders(alloc, function, limit);
        defer leaders.deinit(alloc);
        var constants: std.AutoHashMapUnmanaged(u32, ConstantOrigin) = .empty;
        defer constants.deinit(alloc);

        var coordinate: u32 = 1;
        for (function.blocks) |block| {
            for (block.instrs) |instruction| {
                if (leaders.isSet(coordinate)) constants.clearRetainingCapacity();
                if (instruction.op == .binop and foldableIntType(instruction.ty) and
                    !applicationFactsPresent(instruction) and instruction.result != null)
                {
                    const left = resolveConstOperand(&region, coordinate, instruction.lhs, &constants);
                    const right = resolveConstOperand(&region, coordinate, instruction.rhs, &constants);
                    const fused = if (left != null and right != null)
                        evalConstBinop(instruction.binop, left.?.value, right.?.value)
                    else
                        null;
                    if (fused) |value| {
                        var candidate: FusionCandidate = .{
                            .function = @intCast(function_index),
                            .coordinate = coordinate,
                            .value = value,
                        };
                        for ([_]ResolvedOperand{ left.?, right.? }, 0..) |operand, position| {
                            if (operand.slot) |slot| {
                                candidate.slots[position] = slot;
                                candidate.producer_cost[position] = immediateCost(operand.value);
                            } else {
                                candidate.literal_relief += immediateCost(operand.value) - 1;
                            }
                        }
                        try candidates.append(alloc, candidate);
                    }
                }
                try updateConstantOrigin(alloc, &constants, instruction, coordinate);
                coordinate = std.math.add(u32, coordinate, 1) catch
                    return error.CoordinateOverflow;
            }
        }
    }
    return try candidates.toOwnedSlice(alloc);
}

/// Withdraw candidates until every survivor pays for itself.
///
/// One pass is not enough: withdrawing a fold puts a live reader back on the
/// slot it read, which can be the reader that was keeping some OTHER fold's
/// producer accounted for. Admission only ever shrinks, so this settles.
fn admitCostMonotoneFusions(
    alloc: std.mem.Allocator,
    module: dnir.Module,
    candidates: []FusionCandidate,
) Error!void {
    var folded_readers: std.AutoHashMapUnmanaged(u32, u32) = .empty;
    defer folded_readers.deinit(alloc);

    var settled = false;
    while (!settled) {
        settled = true;
        for (module.functions, 0..) |function, function_index| {
            const prunable = functionIsPrunable(function);
            folded_readers.clearRetainingCapacity();
            for (candidates) |candidate| {
                if (candidate.function != function_index or !candidate.admitted) continue;
                for (candidate.slots) |maybe_slot| {
                    const slot = maybe_slot orelse continue;
                    const entry = try folded_readers.getOrPut(alloc, slot);
                    entry.value_ptr.* = if (entry.found_existing) entry.value_ptr.* + 1 else 1;
                }
            }
            for (candidates) |*candidate| {
                if (candidate.function != function_index or !candidate.admitted) continue;
                if (candidateIsCostMonotone(function, prunable, candidate.*, &folded_readers)) continue;
                candidate.admitted = false;
                settled = false;
            }
        }
    }
}

fn collectConstBinopFusions(
    alloc: std.mem.Allocator,
    projection: region_graph.Projection,
    module: dnir.Module,
) Error![]TransformRecord {
    const candidates = try collectFusionCandidates(alloc, projection, module);
    defer alloc.free(candidates);
    try admitCostMonotoneFusions(alloc, module, candidates);

    var records: std.ArrayListUnmanaged(TransformRecord) = .empty;
    errdefer records.deinit(alloc);
    for (candidates) |candidate| {
        if (!candidate.admitted) continue;
        try records.append(alloc, .{
            .function = candidate.function,
            .coordinate = candidate.coordinate,
            .const_value = candidate.value,
        });
    }
    return try records.toOwnedSlice(alloc);
}

pub fn findConstBinopFusions(
    alloc: std.mem.Allocator,
    projection: region_graph.Projection,
    module: dnir.Module,
) Error![]TransformRecord {
    try requireResidency(alloc, projection, module);
    return collectConstBinopFusions(alloc, projection, module);
}

pub fn freeTransformRecords(alloc: std.mem.Allocator, records: []TransformRecord) void {
    alloc.free(records);
}

const InstructionLocation = struct {
    block: usize,
    instruction: usize,
};

fn locateInstruction(function: dnir.Function, target: u32) ?InstructionLocation {
    var coordinate: u32 = 1;
    for (function.blocks, 0..) |block, block_index| {
        for (block.instrs, 0..) |_, instruction_index| {
            if (coordinate == target) return .{
                .block = block_index,
                .instruction = instruction_index,
            };
            coordinate = std.math.add(u32, coordinate, 1) catch return null;
        }
    }
    return null;
}

/// Replaces ONE instruction with a `const` of the same result slot at the same
/// coordinate. Nothing moves, so `br.branch_target` and `realization_start` —
/// both flat instruction indices — stay valid, which is why this may run in a
/// function that carries application lineage elsewhere. The instruction being
/// replaced must still carry none of its own.
pub fn applyConstBinopFusion(
    alloc: std.mem.Allocator,
    function: *dnir.Function,
    coordinate: u32,
    value: i64,
) Error!bool {
    const location = locateInstruction(function.*, coordinate) orelse return false;
    const blocks: []dnir.Block = @constCast(function.blocks);
    const block = &blocks[location.block];
    const selected = block.instrs[location.instruction];
    if (selected.op != .binop or applicationFactsPresent(selected) or
        !foldableIntType(selected.ty) or selected.result == null)
    {
        return false;
    }

    const owned = try alloc.dupe(dnir.Instr, block.instrs);
    owned[location.instruction] = .{
        .op = .@"const",
        .result = selected.result,
        .lhs = .{ .i64 = value },
        .ty = .i64,
    };
    dnir.deinitInstr(alloc, selected);
    const old = block.instrs;
    block.instrs = owned;
    alloc.free(old);
    return true;
}

fn applyModuleConstBinopFusionsValidated(
    alloc: std.mem.Allocator,
    module: *dnir.Module,
    projection: region_graph.Projection,
) Error!u32 {
    const records = try collectConstBinopFusions(alloc, projection, module.*);
    defer freeTransformRecords(alloc, records);

    const functions: []dnir.Function = @constCast(module.functions);
    var applied: u32 = 0;
    for (records) |record| {
        if (record.function >= functions.len) return error.ResidencyMismatch;
        if (try applyConstBinopFusion(
            alloc,
            &functions[record.function],
            record.coordinate,
            record.const_value,
        )) {
            applied += 1;
        }
    }
    return applied;
}

pub fn applyModuleConstBinopFusions(
    alloc: std.mem.Allocator,
    module: *dnir.Module,
    projection: region_graph.Projection,
) Error!u32 {
    try requireResidency(alloc, projection, module.*);
    return applyModuleConstBinopFusionsValidated(alloc, module, projection);
}

/// The two `lhs` positions DNIR already admits an immediate in, so rewriting a
/// slot read into the immediate it resolves to produces a form the lowerer
/// itself emits. `store_local L = {i64}` and `ret {i64}` both appear verbatim
/// in ordinary lowered output, which is why the list is exactly these two: a
/// third entry would be a form nothing has ever emitted.
fn admitsImmediateLhs(instruction: dnir.Instr) bool {
    return switch (instruction.op) {
        .store_local, .ret => foldableIntType(instruction.ty),
        else => false,
    };
}

/// True when this operand is the ONLY reader of its slot.
///
/// COST ACCOUNT for propagation, which needs no threshold because the
/// materialization MOVES rather than duplicating: the destination pays
/// `immediateCost(v)`, which is exactly what the dying producer stops paying,
/// and the producer's store and this operand's read both disappear. Removed
/// exceeds added by two instructions on every firing, for every width.
///
/// The moment a second reader exists that account inverts: the producer keeps
/// its materialization AND the destination grows one, so a `0x6a09e667` costs a
/// `mov` and a `movk` twice over. Measured: `sha.out` 4221 → 4229 for the same
/// answer.
fn soleReader(function: dnir.Function, operand: dnir.Value) bool {
    const slot = switch (operand) {
        .temp, .local => |candidate| candidate,
        else => return false,
    };
    return tempUseCount(function, slot) == 1;
}

fn collectConstOperandPropagations(
    alloc: std.mem.Allocator,
    projection: region_graph.Projection,
    module: dnir.Module,
) Error![]TransformRecord {
    var records: std.ArrayListUnmanaged(TransformRecord) = .empty;
    errdefer records.deinit(alloc);

    for (module.functions, projection.regions, 0..) |function, region, function_index| {
        // PROPAGATION IS ONLY A WIN WHEN IT KILLS THE PRODUCER, so it runs only
        // where the producer can be deleted at all. Measured: allowing it
        // everywhere grew `sha.out` by 8 instructions, because eight
        // `ldr x9, [sp, #off]` became two-instruction `mov`/`movk` wide
        // immediates while the loads' producers stayed exactly where they were.
        if (!functionIsPrunable(function)) continue;
        const limit = try flattenedLength(function);
        var leaders = try markLeaders(alloc, function, limit);
        defer leaders.deinit(alloc);
        var constants: std.AutoHashMapUnmanaged(u32, ConstantOrigin) = .empty;
        defer constants.deinit(alloc);

        var coordinate: u32 = 1;
        for (function.blocks) |block| {
            for (block.instrs) |instruction| {
                if (leaders.isSet(coordinate)) constants.clearRetainingCapacity();
                if (admitsImmediateLhs(instruction) and !applicationFactsPresent(instruction) and
                    instruction.lhs != .i64 and soleReader(function, instruction.lhs))
                {
                    if (resolveConstOperand(
                        &region,
                        coordinate,
                        instruction.lhs,
                        &constants,
                    )) |operand| {
                        try records.append(alloc, .{
                            .function = @intCast(function_index),
                            .coordinate = coordinate,
                            .const_value = operand.value,
                        });
                    }
                }
                try updateConstantOrigin(alloc, &constants, instruction, coordinate);
                coordinate = std.math.add(u32, coordinate, 1) catch
                    return error.CoordinateOverflow;
            }
        }
    }
    return try records.toOwnedSlice(alloc);
}

pub fn findConstOperandPropagations(
    alloc: std.mem.Allocator,
    projection: region_graph.Projection,
    module: dnir.Module,
) Error![]TransformRecord {
    try requireResidency(alloc, projection, module);
    return collectConstOperandPropagations(alloc, projection, module);
}

/// Rewrites ONE operand in place. Index-preserving for the same reason
/// `applyConstBinopFusion` is, and gated per instruction rather than per
/// function for the same reason.
pub fn applyConstOperandPropagation(
    alloc: std.mem.Allocator,
    function: *dnir.Function,
    coordinate: u32,
    value: i64,
) Error!bool {
    const location = locateInstruction(function.*, coordinate) orelse return false;
    const blocks: []dnir.Block = @constCast(function.blocks);
    const block = &blocks[location.block];
    const selected = block.instrs[location.instruction];
    if (!admitsImmediateLhs(selected) or applicationFactsPresent(selected) or
        selected.lhs == .i64)
    {
        return false;
    }

    const owned = try alloc.dupe(dnir.Instr, block.instrs);
    owned[location.instruction].lhs = .{ .i64 = value };
    const old = block.instrs;
    block.instrs = owned;
    alloc.free(old);
    return true;
}

fn applyModuleConstOperandPropagationsValidated(
    alloc: std.mem.Allocator,
    module: *dnir.Module,
    projection: region_graph.Projection,
) Error!u32 {
    const records = try collectConstOperandPropagations(alloc, projection, module.*);
    defer freeTransformRecords(alloc, records);

    const functions: []dnir.Function = @constCast(module.functions);
    var applied: u32 = 0;
    for (records) |record| {
        if (record.function >= functions.len) return error.ResidencyMismatch;
        if (try applyConstOperandPropagation(
            alloc,
            &functions[record.function],
            record.coordinate,
            record.const_value,
        )) {
            applied += 1;
        }
    }
    return applied;
}

pub fn applyModuleConstOperandPropagations(
    alloc: std.mem.Allocator,
    module: *dnir.Module,
    projection: region_graph.Projection,
) Error!u32 {
    try requireResidency(alloc, projection, module.*);
    return applyModuleConstOperandPropagationsValidated(alloc, module, projection);
}

fn valueUsesSlot(value: dnir.Value, slot: u32) bool {
    return switch (value) {
        .temp, .local => |candidate| candidate == slot,
        else => false,
    };
}

fn tempUseCount(function: dnir.Function, slot: u32) u32 {
    var count: u32 = 0;
    for (function.blocks) |block| {
        for (block.instrs) |instruction| {
            if (instruction.op == .ret_record and instruction.vals.len != 0) {
                for (instruction.vals) |value| {
                    if (valueUsesSlot(value, slot)) count += 1;
                }
            } else {
                if (valueUsesSlot(instruction.lhs, slot)) count += 1;
                if (valueUsesSlot(instruction.rhs, slot)) count += 1;
                if (valueUsesSlot(instruction.third, slot)) count += 1;
            }
        }
    }
    return count;
}

pub fn pruneDeadConstProducers(
    alloc: std.mem.Allocator,
    function: *dnir.Function,
) Error!u32 {
    // Positional application lineage prevents deletion until transformations
    // have their own exact graph witness; and DELETION RENUMBERS EVERY LATER
    // INSTRUCTION, while `br.branch_target` is a flat instruction index into
    // exactly that numbering. Removing one dead `const` above a branch silently
    // retargets the branch by one instruction — a jump into the middle of
    // whatever now occupies the slot. `functionIsPrunable` is both tests, and
    // is the same predicate the folds consult before spending a producer's
    // death in their cost account.
    if (!functionIsPrunable(function.*)) return 0;
    var pruned: u32 = 0;
    const blocks: []dnir.Block = @constCast(function.blocks);
    for (blocks) |*block| {
        var instructions: std.ArrayListUnmanaged(dnir.Instr) = .empty;
        errdefer instructions.deinit(alloc);
        var block_changed = false;

        for (block.instrs) |instruction| {
            if (instruction.op == .@"const" and instruction.ty == .i64) {
                const result = instruction.result orelse {
                    try instructions.append(alloc, instruction);
                    continue;
                };
                if (tempUseCount(function.*, result) == 0) {
                    pruned += 1;
                    block_changed = true;
                    continue;
                }
            }
            try instructions.append(alloc, instruction);
        }

        if (!block_changed) {
            instructions.deinit(alloc);
            continue;
        }
        const owned = try instructions.toOwnedSlice(alloc);
        const old = block.instrs;
        for (old) |instruction| {
            if (instruction.op != .@"const" or instruction.ty != .i64) continue;
            const result = instruction.result orelse continue;
            if (tempUseCount(function.*, result) == 0) dnir.deinitInstr(alloc, instruction);
        }
        block.instrs = owned;
        alloc.free(old);
    }
    return pruned;
}

pub fn applyModuleDeadConstPrune(alloc: std.mem.Allocator, module: *dnir.Module) Error!u32 {
    var pruned: u32 = 0;
    const functions: []dnir.Function = @constCast(module.functions);
    for (functions) |*function| pruned += try pruneDeadConstProducers(alloc, function);
    return pruned;
}

/// Delete a `store_local` whose slot no instruction anywhere in the function
/// reads. This is what makes constant propagation an ELIMINATION rather than a
/// rewrite: `a = 10` survives folding `a + b` only because something still
/// writes the slot, and nothing reads it.
///
/// Gated on a single block with no branch on purpose. A store that is dead on
/// the straight line can be live on a back edge, and the counting here is
/// whole-function occurrence counting, not liveness — the two agree only when
/// there is exactly one path.
pub fn pruneDeadStores(alloc: std.mem.Allocator, function: *dnir.Function) Error!u32 {
    if (!functionIsPrunable(function.*)) return 0;
    const blocks: []dnir.Block = @constCast(function.blocks);
    const block = &blocks[0];

    var instructions: std.ArrayListUnmanaged(dnir.Instr) = .empty;
    errdefer instructions.deinit(alloc);
    var pruned: u32 = 0;

    for (block.instrs) |instruction| {
        if (deadStore(function.*, instruction)) {
            pruned += 1;
            continue;
        }
        try instructions.append(alloc, instruction);
    }
    if (pruned == 0) {
        instructions.deinit(alloc);
        return 0;
    }

    const owned = try instructions.toOwnedSlice(alloc);
    const old = block.instrs;
    for (old) |instruction| {
        if (deadStore(function.*, instruction)) dnir.deinitInstr(alloc, instruction);
    }
    block.instrs = owned;
    alloc.free(old);
    return pruned;
}

fn deadStore(function: dnir.Function, instruction: dnir.Instr) bool {
    if (instruction.op != .store_local or applicationFactsPresent(instruction)) return false;
    const slot = instruction.result orelse return false;
    return tempUseCount(function, slot) == 0;
}

pub fn applyModuleDeadStorePrune(alloc: std.mem.Allocator, module: *dnir.Module) Error!u32 {
    var pruned: u32 = 0;
    const functions: []dnir.Function = @constCast(module.functions);
    for (functions) |*function| pruned += try pruneDeadStores(alloc, function);
    return pruned;
}

fn applyModuleRegionTransformsValidated(
    alloc: std.mem.Allocator,
    module: *dnir.Module,
    projection: region_graph.Projection,
) Error!ModuleTransformReport {
    const fusions = try applyModuleConstBinopFusionsValidated(alloc, module, projection);
    const pruned = try applyModuleDeadConstPrune(alloc, module);
    return .{
        .const_binop_fusions = fusions,
        .dead_const_pruned = pruned,
    };
}

pub fn applyModuleRegionTransforms(
    alloc: std.mem.Allocator,
    module: *dnir.Module,
    projection: region_graph.Projection,
) Error!ModuleTransformReport {
    try requireResidency(alloc, projection, module.*);
    return applyModuleRegionTransformsValidated(alloc, module, projection);
}

/// A fold cannot see a constant a later fold creates, so `2 + 3 * 4` folds the
/// inner product on round one and the outer sum on round two. The cap bounds
/// compile time; every round after the last productive one costs two region
/// builds and finds nothing, so the loop exits on the first idle round and the
/// cap is a backstop, not the normal exit.
pub const max_fold_rounds: u32 = 8;

/// THE NATIVE-PATH ENTRY POINT. Everything else in this file is a phase.
///
/// Owns the physical region projection for the whole run: each phase gets a
/// FRESHLY BUILT and re-validated projection, because a phase that rewrites an
/// operand changes the dependency set the next phase would read, and a stale
/// dependency is exactly how a fold reads a value some other instruction
/// produced.
///
/// `module` is taken by value on purpose: no phase writes the `Module` struct.
/// The blocks and instruction arrays it points at are shared with the caller
/// and ARE rewritten in place, so the caller's `deinitModule` still owns and
/// releases everything, including the arrays installed here.
pub fn foldModuleConstants(
    alloc: std.mem.Allocator,
    module: dnir.Module,
) Error!ModuleTransformReport {
    var owned = module;
    var report: ModuleTransformReport = .{};

    while (report.rounds < max_fold_rounds) {
        report.rounds += 1;
        var changed: u32 = 0;

        {
            const projection = try region_graph.buildModuleRegions(alloc, owned);
            defer region_graph.freeModuleRegions(alloc, projection);
            try requireResidency(alloc, projection, owned);
            const fused = try applyModuleConstBinopFusionsValidated(alloc, &owned, projection);
            report.const_binop_fusions += fused;
            changed += fused;
        }
        {
            const projection = try region_graph.buildModuleRegions(alloc, owned);
            defer region_graph.freeModuleRegions(alloc, projection);
            try requireResidency(alloc, projection, owned);
            const moved = try applyModuleConstOperandPropagationsValidated(
                alloc,
                &owned,
                projection,
            );
            report.const_operands_propagated += moved;
            changed += moved;
        }

        const consts = try applyModuleDeadConstPrune(alloc, &owned);
        report.dead_const_pruned += consts;
        changed += consts;

        const stores = try applyModuleDeadStorePrune(alloc, &owned);
        report.dead_store_pruned += stores;
        changed += stores;

        if (changed == 0) break;
    }
    return report;
}

fn functionHasBinop(function: *const dnir.Function, op: dnir.BinOpTag) bool {
    for (function.blocks) |block| {
        for (block.instrs) |instruction| {
            if (instruction.op == .binop and instruction.binop == op and instruction.ty != .f64) {
                return true;
            }
        }
    }
    return false;
}

test "region_transform: folds constants from physical coordinates and dependencies" {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const dnir_lower = @import("dnir_lower.zig");

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source =
        \\main: i64 = ()
        \\    x = 10
        \\    y = 32
        \\    x + y
    ;
    var lexer = Lexer.init(source, "region-transform.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    const ast_module = try parser.parse_module();
    var module = try dnir_lower.lowerModule(alloc, &ast_module);
    const projection = try region_graph.buildModuleRegions(alloc, module);
    defer region_graph.freeModuleRegions(alloc, projection);

    const records = try findConstBinopFusions(alloc, projection, module);
    defer freeTransformRecords(alloc, records);
    try std.testing.expectEqual(@as(usize, 1), records.len);
    try std.testing.expectEqual(@as(i64, 42), records[0].const_value);

    const report = try applyModuleRegionTransforms(alloc, &module, projection);
    try std.testing.expectEqual(@as(u32, 1), report.const_binop_fusions);
    try std.testing.expectEqual(@as(usize, 1), module.functions.len);
    try std.testing.expect(!functionHasBinop(&module.functions[0], .add));
}

test "region_transform: rejects equal coordinates from another graph" {
    var graph_a = semantic_graph.SemanticGraph.init(std.testing.allocator);
    defer graph_a.deinit();
    var graph_b = semantic_graph.SemanticGraph.init(std.testing.allocator);
    defer graph_b.deinit();
    const functions = [_]dnir.Function{.{
        .name = "probe",
        .ret = .void,
        .blocks = &.{.{ .instrs = &.{.{ .op = .ret }} }},
    }};
    const module_a: dnir.Module = .{ .graph = &graph_a, .functions = &functions };
    var module_b: dnir.Module = .{ .graph = &graph_b, .functions = &functions };
    const projection = try region_graph.buildModuleRegions(std.testing.allocator, module_a);
    defer region_graph.freeModuleRegions(std.testing.allocator, projection);
    try std.testing.expectError(
        error.ResidencyMismatch,
        applyModuleRegionTransforms(std.testing.allocator, &module_b, projection),
    );
}

test "region_transform: stale constants across blocks and redefinitions decline" {
    const cross_blocks = [_]dnir.Block{
        .{ .instrs = &.{.{ .op = .@"const", .result = 0, .lhs = .{ .i64 = 10 }, .ty = .i64 }} },
        .{ .instrs = &.{
            .{ .op = .call_extern, .result = 0, .callee = "value", .ty = .i64 },
            .{ .op = .binop, .result = 1, .lhs = .{ .temp = 0 }, .rhs = .{ .i64 = 1 }, .ty = .i64 },
        } },
    };
    const same_block = [_]dnir.Block{.{ .instrs = &.{
        .{ .op = .@"const", .result = 0, .lhs = .{ .i64 = 10 }, .ty = .i64 },
        .{ .op = .call_extern, .result = 0, .callee = "value", .ty = .i64 },
        .{ .op = .binop, .result = 1, .lhs = .{ .temp = 0 }, .rhs = .{ .i64 = 1 }, .ty = .i64 },
    } }};
    const functions = [_]dnir.Function{
        .{ .name = "cross", .ret = .i64, .blocks = &cross_blocks },
        .{ .name = "same", .ret = .i64, .blocks = &same_block },
    };
    const module: dnir.Module = .{ .functions = &functions };
    const projection = try region_graph.buildModuleRegions(std.testing.allocator, module);
    defer region_graph.freeModuleRegions(std.testing.allocator, projection);
    const records = try findConstBinopFusions(std.testing.allocator, projection, module);
    defer freeTransformRecords(std.testing.allocator, records);
    try std.testing.expectEqual(@as(usize, 0), records.len);
}

test "region_transform: exact coordinate selects one duplicate result slot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var functions = [_]dnir.Function{.{
        .name = "duplicate",
        .ret = .i64,
        .blocks = &.{.{ .instrs = &.{
            .{ .op = .store_local, .result = 0, .lhs = .{ .i64 = 10 }, .ty = .i64 },
            .{ .op = .binop, .result = 5, .lhs = .{ .local = 0 }, .rhs = .{ .i64 = 1 }, .ty = .i64 },
            .{ .op = .binop, .result = 5, .lhs = .{ .temp = 99 }, .rhs = .{ .i64 = 2 }, .ty = .i64 },
            .{ .op = .ret, .lhs = .{ .temp = 5 }, .ty = .i64 },
        } }},
    }};
    const module: dnir.Module = .{ .functions = &functions };
    const projection = try region_graph.buildModuleRegions(alloc, module);
    defer region_graph.freeModuleRegions(alloc, projection);
    const records = try findConstBinopFusions(alloc, projection, module);
    defer freeTransformRecords(alloc, records);
    try std.testing.expectEqual(@as(usize, 1), records.len);
    try std.testing.expectEqual(@as(u32, 2), records[0].coordinate);
    try std.testing.expect(try applyConstBinopFusion(
        alloc,
        &functions[0],
        records[0].coordinate,
        records[0].const_value,
    ));
    try std.testing.expectEqual(dnir.Op.@"const", functions[0].blocks[0].instrs[1].op);
    try std.testing.expectEqual(dnir.Op.binop, functions[0].blocks[0].instrs[2].op);
}

test "region_transform: prunes orphaned constant temps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var function = dnir.Function{
        .name = "dead",
        .ret = .i64,
        .blocks = &.{.{ .instrs = &.{
            .{ .op = .@"const", .result = 1, .lhs = .{ .i64 = 10 }, .ty = .i64 },
            .{ .op = .@"const", .result = 2, .lhs = .{ .i64 = 32 }, .ty = .i64 },
            .{ .op = .@"const", .result = 3, .lhs = .{ .i64 = 42 }, .ty = .i64 },
            .{ .op = .ret, .lhs = .{ .temp = 3 } },
        } }},
    };
    const pruned = try pruneDeadConstProducers(alloc, &function);
    try std.testing.expectEqual(@as(u32, 2), pruned);
    try std.testing.expectEqual(@as(usize, 2), function.blocks[0].instrs.len);
}


/// Lower `source` the way the NATIVE path lowers it — through sema and the
/// semantic graph, not through the graphless convenience entry — so a test
/// here measures the module the machine backend would actually receive.
fn lowerNativeShape(
    alloc: std.mem.Allocator,
    graph: *semantic_graph.SemanticGraph,
    source: []const u8,
) !dnir.Module {
    const Lexer = @import("lexer.zig").Lexer;
    const Parser = @import("parser.zig").Parser;
    const Sema = @import("sema.zig").Sema;
    const dnir_lower = @import("dnir_lower.zig");

    var lexer = Lexer.init(source, "region-transform-native.id");
    var parser = Parser.init(&lexer, alloc);
    parser.idol_mode = true;
    var ast_module = try parser.parse_module();
    var checked = Sema.init(alloc);
    defer checked.deinit();
    checked.idol_mode = true;
    try checked.check_module(&ast_module);
    _ = try graph.liftModuleWithCheckedCalls(&ast_module, &checked, "region-transform-native.id");
    return dnir_lower.lowerModuleWithGraph(alloc, &ast_module, graph);
}

fn onlyBlock(module: dnir.Module, name: []const u8) []const dnir.Instr {
    for (module.functions) |function| {
        if (std.mem.eql(u8, function.name, name)) return function.blocks[0].instrs;
    }
    return &.{};
}

test "region_transform: a straight-line constant statement collapses to its answer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();

    const module = try lowerNativeShape(alloc, &graph,
        \\main: i64 = ()
        \\    s = 1 + 2
        \\    s
    );
    // binop, store_local, ret start life as three DNIR instructions and were
    // measured emitting SIX — `mov x9,#1 ; mov x10,#2 ; add x11,x9,x10 ;
    // mov x9,x11 ; mov x0,x9 ; ret` — where two are the answer. Measured after
    // this pass runs on the native path: 2.
    _ = try foldModuleConstants(alloc, module);

    const after = onlyBlock(module, "main");
    try std.testing.expectEqual(@as(usize, 1), after.len);
    try std.testing.expectEqual(dnir.Op.ret, after[0].op);
    try std.testing.expectEqual(@as(i64, 3), after[0].lhs.i64);

    // IDEMPOTENCE, asserted rather than assumed: this is the property that lets
    // the pass be routed into `lowerModuleWithGraphObserved` without any test
    // above it needing to know whether the module it was handed is folded
    // already. A second run finds a fixed point and changes nothing.
    const again = try foldModuleConstants(alloc, module);
    try std.testing.expectEqual(@as(u32, 0), again.const_binop_fusions);
    try std.testing.expectEqual(@as(u32, 0), again.const_operands_propagated);
    try std.testing.expectEqual(@as(u32, 0), again.dead_const_pruned);
    try std.testing.expectEqual(@as(u32, 0), again.dead_store_pruned);
    try std.testing.expectEqual(@as(u32, 1), again.rounds);
}

test "region_transform: a nested constant expression needs more than one round" {
    // `2 + 3 * 4` as the lowerer writes it, built here rather than lowered: the
    // count this test makes is about the FIXPOINT, and a caller that already
    // folded would leave nothing to count. The shape is the one
    // `lowerNativeShape` produces for that source.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var functions = [_]dnir.Function{.{
        .name = "nested",
        .ret = .i64,
        .blocks = &.{.{ .instrs = &.{
            .{ .op = .binop, .binop = .mul, .result = 0, .lhs = .{ .i64 = 3 }, .rhs = .{ .i64 = 4 }, .ty = .i64 },
            .{ .op = .binop, .binop = .add, .result = 1, .lhs = .{ .i64 = 2 }, .rhs = .{ .temp = 0 }, .ty = .i64 },
            .{ .op = .ret, .lhs = .{ .temp = 1 }, .ty = .i64 },
        } }},
    }};
    const module: dnir.Module = .{ .functions = &functions };
    const report = try foldModuleConstants(alloc, module);
    try std.testing.expectEqual(@as(u32, 2), report.const_binop_fusions);
    try std.testing.expect(report.rounds >= 2);

    const after = functions[0].blocks[0].instrs;
    try std.testing.expectEqual(@as(usize, 1), after.len);
    try std.testing.expectEqual(dnir.Op.ret, after[0].op);
    try std.testing.expectEqual(@as(i64, 14), after[0].lhs.i64);
}

test "region_transform: named constant bindings fold and their stores die" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();

    const module = try lowerNativeShape(alloc, &graph,
        \\main: i64 = ()
        \\    a = 10
        \\    b = 32
        \\    a + b
    );
    _ = try foldModuleConstants(alloc, module);

    // Two named bindings, two stores, one add, one return — four DNIR
    // instructions and seven emitted — collapse to the answer alone.
    const after = onlyBlock(module, "main");
    try std.testing.expectEqual(@as(usize, 1), after.len);
    try std.testing.expectEqual(dnir.Op.ret, after[0].op);
    try std.testing.expectEqual(@as(i64, 42), after[0].lhs.i64);
}

test "region_transform: float arithmetic is never folded here" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();

    const module = try lowerNativeShape(alloc, &graph,
        \\main: i64 = ()
        \\    x = 7.5 + 1.5
        \\    3
    );
    const report = try foldModuleConstants(alloc, module);
    try std.testing.expectEqual(@as(u32, 0), report.const_binop_fusions);
    try std.testing.expectEqual(@as(u32, 0), report.const_operands_propagated);
    // The `x` binding is unread, so its store dies — but the ADDITION itself
    // survives untouched, at full f64 width, with both operands still where
    // the lowerer put them. Reassociating or evaluating it here would change
    // the result the machine computes.
    const after = onlyBlock(module, "main");
    try std.testing.expectEqual(dnir.Op.binop, after[0].op);
    try std.testing.expectEqual(@as(f64, 7.5), after[0].lhs.f64);
    try std.testing.expectEqual(@as(f64, 1.5), after[0].rhs.f64);
}

test "region_transform: an applied relation keeps every instruction" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var graph = semantic_graph.SemanticGraph.init(alloc);
    defer graph.deinit();

    const module = try lowerNativeShape(alloc, &graph,
        \\add: i64 = (a: i64, b: i64)
        \\    a + b
        \\main: i64 = ()
        \\    add(1, 2)
    );
    const before = onlyBlock(module, "main").len;
    const report = try foldModuleConstants(alloc, module);
    try std.testing.expectEqual(before, onlyBlock(module, "main").len);
    // `add`'s own body reads parameters, so nothing there is constant either.
    try std.testing.expectEqual(@as(u32, 0), report.const_binop_fusions);
}

test "region_transform: a declared width narrower than the fold width declines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var functions = [_]dnir.Function{.{
        .name = "narrow",
        .ret = .i32,
        .blocks = &.{.{ .instrs = &.{
            .{ .op = .binop, .result = 0, .lhs = .{ .i64 = 2 }, .rhs = .{ .i64 = 3 }, .ty = .i32 },
            .{ .op = .ret, .lhs = .{ .temp = 0 }, .ty = .i32 },
        } }},
    }};
    const module: dnir.Module = .{ .functions = &functions };
    const report = try foldModuleConstants(alloc, module);
    try std.testing.expectEqual(@as(u32, 0), report.const_binop_fusions);
    try std.testing.expectEqual(dnir.Op.binop, functions[0].blocks[0].instrs[0].op);
}

test "region_transform: nothing is deleted from a body that branches" {
    // Real DNIR is one flat block per function with `br` carrying a flat
    // instruction index (`dnir_lower.zig:1631`), so this is the shape the
    // native path actually presents. Instruction 0 is a dead constant and
    // instruction 4 branches back to index 2: deleting the dead constant would
    // renumber index 2 onto a different instruction, and the loop would then
    // re-enter one instruction late, forever.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var functions = [_]dnir.Function{.{
        .name = "loops",
        .ret = .i64,
        .blocks = &.{.{ .instrs = &.{
            .{ .op = .@"const", .result = 9, .lhs = .{ .i64 = 111 }, .ty = .i64 },
            .{ .op = .store_local, .result = 0, .lhs = .{ .i64 = 7 }, .ty = .i64 },
            .{ .op = .binop, .result = 1, .lhs = .{ .local = 0 }, .rhs = .{ .i64 = 1 }, .ty = .i64 },
            .{ .op = .store_local, .result = 0, .lhs = .{ .temp = 1 }, .ty = .i64 },
            .{ .op = .br, .lhs = .{ .temp = 1 }, .branch_target = 2, .branch_condition = .when_true },
            .{ .op = .ret, .lhs = .{ .local = 0 }, .ty = .i64 },
        } }},
    }};
    const module: dnir.Module = .{ .functions = &functions };
    const report = try foldModuleConstants(alloc, module);

    try std.testing.expectEqual(@as(u32, 0), report.dead_const_pruned);
    try std.testing.expectEqual(@as(u32, 0), report.dead_store_pruned);
    const after = functions[0].blocks[0].instrs;
    try std.testing.expectEqual(@as(usize, 6), after.len);
    try std.testing.expectEqual(@as(u32, 2), after[4].branch_target);
    try std.testing.expectEqual(dnir.Op.store_local, after[1].op);

    // Index 2 is the branch destination, so the `7` stored at index 1 may not
    // be carried into it — the back edge reaches index 2 without passing index
    // 1, and the slot then holds whatever the previous trip left.
    try std.testing.expectEqual(@as(u32, 0), report.const_binop_fusions);
    try std.testing.expectEqual(@as(u32, 0), report.const_operands_propagated);
}

test "region_transform: a back edge that re-establishes the constant still folds" {
    // Same shape, one instruction different: the branch lands ON the store, so
    // the slot holds 7 on every path that reaches the arithmetic. The leader
    // set is what tells these two apart, and getting it backwards in either
    // direction is a wrong answer rather than a missed fold.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var functions = [_]dnir.Function{.{
        .name = "reseeds",
        .ret = .i64,
        .blocks = &.{.{ .instrs = &.{
            .{ .op = .@"const", .result = 9, .lhs = .{ .i64 = 111 }, .ty = .i64 },
            .{ .op = .store_local, .result = 0, .lhs = .{ .i64 = 7 }, .ty = .i64 },
            .{ .op = .binop, .result = 1, .lhs = .{ .local = 0 }, .rhs = .{ .i64 = 1 }, .ty = .i64 },
            .{ .op = .store_local, .result = 0, .lhs = .{ .temp = 1 }, .ty = .i64 },
            .{ .op = .br, .lhs = .{ .temp = 1 }, .branch_target = 1, .branch_condition = .when_true },
            .{ .op = .ret, .lhs = .{ .local = 0 }, .ty = .i64 },
        } }},
    }};
    const module: dnir.Module = .{ .functions = &functions };
    const report = try foldModuleConstants(alloc, module);

    try std.testing.expectEqual(@as(u32, 1), report.const_binop_fusions);
    const after = functions[0].blocks[0].instrs;
    try std.testing.expectEqual(@as(usize, 6), after.len);
    try std.testing.expectEqual(dnir.Op.@"const", after[2].op);
    try std.testing.expectEqual(@as(i64, 8), after[2].lhs.i64);
    try std.testing.expectEqual(@as(u32, 1), after[4].branch_target);
}

test "region_transform: a constant established after the last leader still folds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var functions = [_]dnir.Function{.{
        .name = "tail",
        .ret = .i64,
        .blocks = &.{.{ .instrs = &.{
            .{ .op = .br, .lhs = .{ .local = 0 }, .branch_target = 3, .branch_condition = .when_true },
            .{ .op = .store_local, .result = 1, .lhs = .{ .i64 = 20 }, .ty = .i64 },
            .{ .op = .binop, .result = 2, .lhs = .{ .local = 1 }, .rhs = .{ .i64 = 22 }, .ty = .i64 },
            .{ .op = .ret, .lhs = .{ .temp = 2 }, .ty = .i64 },
        } }},
    }};
    const module: dnir.Module = .{ .functions = &functions };
    const report = try foldModuleConstants(alloc, module);

    // Instruction 1 is the fall-through leader; instruction 2 is reachable only
    // from it, so 20 + 22 is the same on every path that reaches it.
    try std.testing.expectEqual(@as(u32, 1), report.const_binop_fusions);
    const after = functions[0].blocks[0].instrs;
    try std.testing.expectEqual(@as(usize, 4), after.len);
    try std.testing.expectEqual(dnir.Op.@"const", after[2].op);
    try std.testing.expectEqual(@as(i64, 42), after[2].lhs.i64);
    try std.testing.expectEqual(@as(u32, 3), after[0].branch_target);
}

test "region_transform: the fold loop stops when a round changes nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var functions = [_]dnir.Function{.{
        .name = "settled",
        .ret = .i64,
        .blocks = &.{.{ .instrs = &.{.{ .op = .ret, .lhs = .{ .i64 = 1 }, .ty = .i64 }} }},
    }};
    const module: dnir.Module = .{ .functions = &functions };
    const report = try foldModuleConstants(alloc, module);
    try std.testing.expectEqual(@as(u32, 1), report.rounds);
}

test "region_transform: a constant with a second reader is left in its slot" {
    // The `sha.out` regression, reduced. Propagating `0x6a09e667` into both
    // readers replaces one register read each with a two-instruction `mov` +
    // `movk`, and the producer stays because something still reads it. Measured
    // cost of allowing this: sha.out 4221 -> 4229 instructions for the same
    // answer.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var functions = [_]dnir.Function{.{
        .name = "shared",
        .ret = .i64,
        .blocks = &.{.{ .instrs = &.{
            .{ .op = .store_local, .result = 0, .lhs = .{ .i64 = 0x6a09e667 }, .ty = .i64 },
            .{ .op = .store_local, .result = 1, .lhs = .{ .local = 0 }, .ty = .i64 },
            .{ .op = .store_local, .result = 2, .lhs = .{ .local = 0 }, .ty = .i64 },
            .{ .op = .binop, .result = 3, .lhs = .{ .local = 1 }, .rhs = .{ .local = 2 }, .ty = .i64 },
            .{ .op = .ret, .lhs = .{ .temp = 3 }, .ty = .i64 },
        } }},
    }};
    const module: dnir.Module = .{ .functions = &functions };
    const report = try foldModuleConstants(alloc, module);

    try std.testing.expectEqual(@as(u32, 0), report.const_operands_propagated);
    const after = functions[0].blocks[0].instrs;
    try std.testing.expectEqual(@as(usize, 5), after.len);
    try std.testing.expectEqual(@as(u32, 0), after[1].lhs.local);
    try std.testing.expectEqual(@as(u32, 0), after[2].lhs.local);
}

test "region_transform: a fold wider than what it removes declines" {
    // The same lesson as the test above, on the FOLD path instead of the
    // propagation path, and it is the one the earlier fix missed. Measured on
    // `p_wideshare.id` — a wide constant held alive by an application, with two
    // `a + k` readers — the fold grew the artifact 57 -> 59 instructions for an
    // unchanged exit of 208, because each `ldr`+`add` pair became a four-word
    // `mov`/`movk` chain while the producer stayed exactly where it was.
    //
    // Slot 0 has a second reader, so its producer cannot be spent; the fold has
    // nothing to pay four instructions with and declines. The narrow case below
    // is the control: same shape, same surviving producer, but the answer fits
    // one `mov`, so replacing a one-instruction `add` with a one-instruction
    // `mov` cannot grow anything and it fires.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wide = [_]dnir.Function{.{
        .name = "held_wide",
        .ret = .i64,
        .blocks = &.{.{ .instrs = &.{
            .{ .op = .store_local, .result = 0, .lhs = .{ .i64 = 0x0123456789ABCDEF }, .ty = .i64 },
            .{ .op = .binop, .result = 1, .lhs = .{ .local = 0 }, .rhs = .{ .i64 = 1 }, .ty = .i64 },
            .{ .op = .store_local, .result = 2, .lhs = .{ .local = 0 }, .ty = .i64 },
            .{ .op = .binop, .result = 3, .lhs = .{ .temp = 1 }, .rhs = .{ .local = 2 }, .ty = .i64 },
            .{ .op = .ret, .lhs = .{ .temp = 3 }, .ty = .i64 },
        } }},
    }};
    const wide_report = try foldModuleConstants(alloc, .{ .functions = &wide });
    try std.testing.expectEqual(@as(u32, 0), wide_report.const_binop_fusions);
    try std.testing.expectEqual(dnir.Op.binop, wide[0].blocks[0].instrs[1].op);

    var narrow = [_]dnir.Function{.{
        .name = "held_narrow",
        .ret = .i64,
        .blocks = &.{.{ .instrs = &.{
            .{ .op = .store_local, .result = 0, .lhs = .{ .i64 = 7 }, .ty = .i64 },
            .{ .op = .binop, .result = 1, .lhs = .{ .local = 0 }, .rhs = .{ .i64 = 1 }, .ty = .i64 },
            .{ .op = .store_local, .result = 2, .lhs = .{ .local = 0 }, .ty = .i64 },
            .{ .op = .binop, .result = 3, .lhs = .{ .temp = 1 }, .rhs = .{ .local = 2 }, .ty = .i64 },
            .{ .op = .ret, .lhs = .{ .temp = 3 }, .ty = .i64 },
        } }},
    }};
    const narrow_report = try foldModuleConstants(alloc, .{ .functions = &narrow });
    try std.testing.expect(narrow_report.const_binop_fusions >= 1);
    // 7 + 1 folds, which frees the second reader, which folds the rest: the
    // whole body becomes `(7 + 1) + 7`.
    const narrow_after = narrow[0].blocks[0].instrs;
    try std.testing.expectEqual(@as(usize, 1), narrow_after.len);
    try std.testing.expectEqual(dnir.Op.ret, narrow_after[0].op);
    try std.testing.expectEqual(@as(i64, 15), narrow_after[0].lhs.i64);
}

test "region_transform: a constant with one reader moves and its producer dies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var functions = [_]dnir.Function{.{
        .name = "sole",
        .ret = .i64,
        .blocks = &.{.{ .instrs = &.{
            .{ .op = .store_local, .result = 0, .lhs = .{ .i64 = 0x6a09e667 }, .ty = .i64 },
            .{ .op = .ret, .lhs = .{ .local = 0 }, .ty = .i64 },
        } }},
    }};
    const module: dnir.Module = .{ .functions = &functions };
    const report = try foldModuleConstants(alloc, module);

    try std.testing.expectEqual(@as(u32, 1), report.const_operands_propagated);
    try std.testing.expectEqual(@as(u32, 1), report.dead_store_pruned);
    const after = functions[0].blocks[0].instrs;
    try std.testing.expectEqual(@as(usize, 1), after.len);
    try std.testing.expectEqual(dnir.Op.ret, after[0].op);
    try std.testing.expectEqual(@as(i64, 0x6a09e667), after[0].lhs.i64);
}
