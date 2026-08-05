const std = @import("std");
const transform_engine = @import("transform_engine.zig");

test "pass6: tier-1 meta hooks require registry before dispatch" {
    const tier1 = transform_engine.parity_tier1;
    for (tier1) |public_name| {
        const d = transform_engine.descriptor(public_name) orelse return error.TestExpectedEqual;
        try std.testing.expect(d.contract.native_only);
        try std.testing.expect(transform_engine.parityContractSatisfied(d));
    }
}

test "pass6: internal tier-1 hooks pass dispatch gate" {
    const internals = [_][]const u8{
        "__comptimemap",
        "__comptimematch",
        "__comptimepower",
        "__derivepower",
        "__comptimefixpoint",
        "__comptimetabulate",
        "__comptimeinterpolate",
        "__comptimeeach",
    };
    for (internals) |internal| {
        try std.testing.expect(transform_engine.requireMetaDispatchBeforeHook(internal));
    }
}

test "pass6: strict mode keeps registered tier-1 hooks" {
    transform_engine.setMetaDispatchStrict(true);
    defer transform_engine.setMetaDispatchStrict(false);
    try std.testing.expect(transform_engine.requireMetaDispatchBeforeHook("__comptimemap"));
    try std.testing.expect(transform_engine.requireMetaDispatchBeforeHook("__metacatalog"));
}

test "pass6: dispatchMetaCombinator ignores unregistered internals" {
    const alloc = std.testing.allocator;
    transform_engine.deinitProvenance(alloc);
    transform_engine.setProvenanceEnabled(true);
    defer transform_engine.deinitProvenance(alloc);
    transform_engine.dispatchMetaCombinator(alloc, "__not_a_real_hook", .block_body, "in", "out");
    try std.testing.expectEqual(@as(usize, 0), transform_engine.provenanceEntries().len);
    transform_engine.dispatchMetaCombinator(alloc, "__comptimemap", .block_body, "in", "out");
    try std.testing.expectEqual(@as(usize, 1), transform_engine.provenanceEntries().len);
}
