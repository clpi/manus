const std = @import("std");
const grammar = @import("grammar_role_gen.zig");

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    if (args.len == 2 and std.mem.eql(u8, args[1], "emit")) {
        try grammar.emitGrammarRoleFile(alloc, init.io, "lib/token/grammarrole.id");
        try grammar.emitGrammarRoleManifestFile(alloc, init.io, grammar.MANIFEST_PATH);
        return;
    }
    if (args.len != 1) return error.GrammarRoleUsage;
    const cwd = std.Io.Dir.cwd();
    const projection = try grammar.renderGrammarRole(alloc);
    const manifest = try grammar.renderGrammarRoleManifest(alloc);
    const tracked_projection = cwd.readFileAlloc(init.io, "lib/token/grammarrole.id", alloc, .unlimited) catch
        return error.GrammarRoleProjectionAbsent;
    const tracked_manifest = cwd.readFileAlloc(init.io, grammar.MANIFEST_PATH, alloc, .unlimited) catch
        return error.GrammarRoleManifestAbsent;
    if (!std.mem.eql(u8, projection, tracked_projection) or !std.mem.eql(u8, manifest, tracked_manifest))
        return error.GrammarRoleProjectionStale;
}
