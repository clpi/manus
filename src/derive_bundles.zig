/// Named @derive_bundle expansions — one attribute → many trait implementations.
const std = @import("std");
const meta_module = @import("meta_module.zig");
const ast = @import("ast.zig");
const directives = @import("directives.zig");

fn isDeriveBundleAttr(name: []const u8) bool {
    const norm = meta_module.normalizeTypeAttribute(name);
    return std.mem.eql(u8, norm, "derive.bundle");
}

pub const Bundle = struct {
    name: []const u8,
    traits: []const []const u8,
    description: []const u8,
};

pub const builtin_bundles = [_]Bundle{
    .{
        .name = "Serializable",
        .traits = &.{ "Display", "Eq", "Hash", "Serialize", "Deserialize" },
        .description = "Display + Eq + Hash + Serialize + Deserialize",
    },
    .{
        .name = "Comparable",
        .traits = &.{ "Eq", "Ord", "Hash" },
        .description = "Eq + Ord + Hash",
    },
    .{
        .name = "Numeric",
        .traits = &.{ "Add", "Sub", "Mul", "Div", "Neg", "Eq", "Default" },
        .description = "Add + Sub + Mul + Div + Neg + Eq + Default",
    },
    .{
        .name = "Collection",
        .traits = &.{ "Len", "Clone", "Eq", "Display" },
        .description = "Len + Clone + Eq + Display",
    },
    .{
        .name = "Debug",
        .traits = &.{ "Display", "Eq", "Clone" },
        .description = "Display + Eq + Clone",
    },
    .{
        .name = "Full",
        .traits = &.{ "Debug", "Comparable", "Default" },
        .description = "Debug + Comparable + Default (nested bundles)",
    },
};

pub const UserBundleRegistry = struct {
    bundles: std.StringHashMapUnmanaged([]const []const u8) = .{},
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) UserBundleRegistry {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *UserBundleRegistry) void {
        var it = self.bundles.iterator();
        while (it.next()) |entry| {
            self.alloc.free(entry.key_ptr.*);
            self.alloc.free(entry.value_ptr.*);
        }
        self.bundles.deinit(self.alloc);
    }

    pub fn register(self: *UserBundleRegistry, name: []const u8, traits: []const []const u8) !void {
        const owned_name = try self.alloc.dupe(u8, name);
        errdefer self.alloc.free(owned_name);
        const owned_traits = try self.alloc.dupe([]const u8, traits);
        errdefer self.alloc.free(owned_traits);
        if (self.bundles.fetchRemove(name)) |kv| {
            self.alloc.free(kv.key);
            self.alloc.free(kv.value);
        }
        try self.bundles.put(self.alloc, owned_name, owned_traits);
    }
};

pub var user_registry: UserBundleRegistry = undefined;
var user_registry_inited = false;

pub fn initUserRegistry(alloc: std.mem.Allocator) void {
    if (!user_registry_inited) {
        user_registry = UserBundleRegistry.init(alloc);
        user_registry_inited = true;
    }
}

pub fn deinitUserRegistry() void {
    if (user_registry_inited) {
        user_registry.deinit();
        user_registry_inited = false;
    }
}

/// Normalize ONE already-isolated token — a bundle-table entry, or a name a
/// caller holds on its own. It is NOT an argument-list reader: everything that
/// starts from `attr.args` goes through `directives.attrArgs` instead, and the
/// tokens that come back are already normalized this way.
pub fn trimArg(raw: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len >= 2 and (trimmed[0] == '"' or trimmed[0] == '\'') and trimmed[trimmed.len - 1] == trimmed[0]) {
        return trimmed[1 .. trimmed.len - 1];
    }
    return trimmed;
}

pub fn findBuiltin(name: []const u8) ?Bundle {
    const key = trimArg(name);
    for (builtin_bundles) |bundle| {
        if (std.mem.eql(u8, bundle.name, key)) return bundle;
    }
    return null;
}

pub fn rawTraitsForBundle(name: []const u8) ?[]const []const u8 {
    if (findBuiltin(name)) |bundle| return bundle.traits;
    if (!user_registry_inited) return null;
    const key = trimArg(name);
    return user_registry.bundles.get(key);
}

pub fn traitsForBundle(name: []const u8) ?[]const []const u8 {
    return rawTraitsForBundle(name);
}

fn isBundleName(name: []const u8) bool {
    const key = trimArg(name);
    if (findBuiltin(key) != null) return true;
    if (!user_registry_inited) return false;
    return user_registry.bundles.contains(key);
}

/// Expand bundle names (including nested bundles) into deduplicated leaf traits.
pub fn expandTraits(alloc: std.mem.Allocator, seeds: []const []const u8) ![]const []const u8 {
    var out: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (out.items) |t| alloc.free(t);
        out.deinit(alloc);
    }
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(alloc);

    var stack: std.ArrayListUnmanaged([]const u8) = .empty;
    defer stack.deinit(alloc);
    for (seeds) |seed| try stack.append(alloc, seed);

    while (stack.pop()) |item| {
        const key = trimArg(item);
        if (key.len == 0) continue;
        if (isBundleName(key)) {
            const nested = rawTraitsForBundle(key) orelse continue;
            for (nested) |t| try stack.append(alloc, t);
            continue;
        }
        const gop = try seen.getOrPut(alloc, key);
        if (gop.found_existing) continue;
        try out.append(alloc, try alloc.dupe(u8, key));
    }
    return try out.toOwnedSlice(alloc);
}

pub fn expandTraitsFromRawArgs(alloc: std.mem.Allocator, raw: []const u8) ![]const []const u8 {
    var seeds: std.ArrayListUnmanaged([]const u8) = .empty;
    defer seeds.deinit(alloc);
    var it = directives.attrArgs(raw);
    while (it.next()) |arg| {
        if (arg.text.len > 0) try seeds.append(alloc, arg.text);
    }
    return expandTraits(alloc, seeds.items);
}

pub fn bundleHasTrait(bundle_name: []const u8, trait: []const u8) bool {
    const traits = rawTraitsForBundle(bundle_name) orelse return false;
    var stack: [32][]const u8 = undefined;
    var depth: usize = 0;
    for (traits) |t| {
        stack[depth] = t;
        depth += 1;
    }
    while (depth > 0) {
        depth -= 1;
        const item = stack[depth];
        const key = trimArg(item);
        if (std.mem.eql(u8, key, trait)) return true;
        if (isBundleName(key)) {
            const nested = rawTraitsForBundle(key) orelse continue;
            for (nested) |t| {
                if (depth >= stack.len) return false;
                stack[depth] = t;
                depth += 1;
            }
        }
    }
    return false;
}

pub fn attributesHaveTrait(attrs: []const ast.Attribute, trait: []const u8) bool {
    for (attrs) |attr| {
        if (std.mem.eql(u8, attr.name, "derive")) {
            var it = directives.attrArgs(attr.args);
            while (it.next()) |arg| {
                if (std.mem.eql(u8, arg.text, trait)) return true;
            }
        } else if (isDeriveBundleAttr(attr.name)) {
            var it = directives.attrArgs(attr.args);
            while (it.next()) |arg| {
                if (bundleHasTrait(arg.text, trait)) return true;
            }
        }
    }
    return false;
}

pub fn attributesHaveAnyDerive(attrs: []const ast.Attribute) bool {
    for (attrs) |attr| {
        if (std.mem.eql(u8, attr.name, "derive") or isDeriveBundleAttr(attr.name)) return true;
    }
    return false;
}

pub fn deriveTraitCount(attrs: []const ast.Attribute) usize {
    var count: usize = 0;
    for (attrs) |attr| {
        if (std.mem.eql(u8, attr.name, "derive")) {
            var it = directives.attrArgs(attr.args);
            while (it.next()) |arg| {
                if (arg.text.len > 0) count += 1;
            }
        } else if (isDeriveBundleAttr(attr.name)) {
            var it = directives.attrArgs(attr.args);
            while (it.next()) |arg| {
                if (arg.text.len == 0) continue;
                if (rawTraitsForBundle(arg.text)) |traits| count += traits.len;
            }
        }
    }
    return count;
}

pub fn registerUserBundleFromRaw(alloc: std.mem.Allocator, raw: []const u8) !void {
    var it = directives.attrArgs(raw);
    const name_arg = it.next() orelse return error.InvalidBundle;
    const name = name_arg.text;
    if (name.len == 0) return error.InvalidBundle;

    var traits: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer traits.deinit(alloc);
    while (it.next()) |arg| {
        if (arg.text.len == 0) continue;
        try traits.append(alloc, try alloc.dupe(u8, arg.text));
    }
    if (traits.items.len == 0) return error.InvalidBundle;
    initUserRegistry(alloc);
    try user_registry.register(name, try traits.toOwnedSlice(alloc));
}

pub const RegisterError = error{ InvalidBundle, OutOfMemory };

test "derive_bundles: Serializable contains Serialize" {
    try std.testing.expect(bundleHasTrait("Serializable", "Serialize"));
    try std.testing.expect(!bundleHasTrait("Serializable", "Add"));
}

test "derive_bundles: nested Full bundle expands Debug traits" {
    try std.testing.expect(bundleHasTrait("Full", "Display"));
    try std.testing.expect(bundleHasTrait("Full", "Ord"));
}

test "derive_bundles: attributesHaveTrait via bundle" {
    const attrs = [_]ast.Attribute{
        .{ .name = "derive.bundle", .args = "Comparable" },
    };
    try std.testing.expect(attributesHaveTrait(&attrs, "Ord"));
    try std.testing.expect(!attributesHaveTrait(&attrs, "Display"));
}

test "derive_bundles: multi bundle attribute" {
    const attrs = [_]ast.Attribute{
        .{ .name = "derive.bundle", .args = "Debug, Comparable" },
    };
    try std.testing.expect(attributesHaveTrait(&attrs, "Clone"));
    try std.testing.expect(attributesHaveTrait(&attrs, "Ord"));
}

test "derive_bundles: register user bundle with nested bundle members" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    deinitUserRegistry();
    initUserRegistry(alloc);
    defer deinitUserRegistry();
    try registerUserBundleFromRaw(alloc, "\"Api\", CStruct, GetterBundle, Debug");
    try std.testing.expect(bundleHasTrait("Api", "Display"));
    try std.testing.expect(bundleHasTrait("Api", "CStruct"));
}

// A derive name may carry its own argument list. Five readers here used to
// split the attribute text on every comma, so `@derive(Tensor(2, 3))` counted
// as TWO traits named `Tensor(2` and `3)` — neither of which exists.
test "derive_bundles: a derive name with its own argument list is ONE trait" {
    const attrs = [_]ast.Attribute{.{ .name = "derive", .args = "Tensor(2, 3)" }};
    try std.testing.expectEqual(@as(usize, 1), deriveTraitCount(&attrs));
    try std.testing.expect(attributesHaveTrait(&attrs, "Tensor(2, 3)"));
    // Positive control: the plain multi-trait list still counts every entry.
    const plain = [_]ast.Attribute{.{ .name = "derive", .args = "Eq, Ord, Hash" }};
    try std.testing.expectEqual(@as(usize, 3), deriveTraitCount(&plain));
}

test "derive_bundles: expandTraits deduplicates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    deinitUserRegistry();
    initUserRegistry(alloc);
    defer deinitUserRegistry();
    const expanded = try expandTraits(alloc, &[_][]const u8{ "Debug", "Comparable" });
    defer {
        for (expanded) |t| alloc.free(t);
        alloc.free(expanded);
    }
    var eq_count: usize = 0;
    for (expanded) |t| {
        if (std.mem.eql(u8, t, "Eq")) eq_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), eq_count);
}
