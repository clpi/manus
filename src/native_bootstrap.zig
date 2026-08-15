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
//!
//! Foreign-only namespace spellings (delete when graph publishes exact ids):
//!   string.byte/sub/match/len/char  → subject relations above
//!   mem.alloc/free/zero/read_*        → demanded place/allocation facts
//!   os.exit/execute                   → process world facts
//!   math.sqrt/sin/...                 → relation + selected target id
//!   gatecap(cmd)                      → command capture (host ingress only)
//!   print(v)                          → host stdout egress (one node with
//!                                       `stdout:write`; recognized everywhere)
//!   to(str)(integral)                 → demanded conversion (infer when unique)
//!
//! Ordinary module calls like `observe(41)` are NOT bootstrap. Checked lowering
//! must consume graph application/relation/target ids — never callee spelling.
const std = @import("std");
const ast = @import("ast.zig");
const Expr = ast.Expr;

pub fn receiverLooksStrish(obj: *const Expr) bool {
    return switch (obj.*) {
        .string_lit => true,
        .method_call => true,
        .name => true,
        else => false,
    };
}

fn methodApplication(expr: *const Expr) bool {
    const mc = expr.method_call;
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

fn inHome(path: []const u8, home: []const u8) bool {
    if (std.mem.startsWith(u8, path, home)) return true;
    if (std.mem.indexOf(u8, path, home)) |i| {
        return i > 0 and path[i - 1] == '/';
    }
    return false;
}

fn named(path: []const u8, file: []const u8) bool {
    return std.mem.eql(u8, path, file) or
        (file.len < path.len and
            std.mem.endsWith(u8, path, file) and
            path[path.len - file.len - 1] == '/');
}

/// Gate and ledger transport modules may lower `print` without graph facts until
/// the graph producer publishes host egress application ids (GAP-155 bridge).
pub fn gateTransport(path: []const u8) bool {
    if (inHome(path, "gate/") or
        inHome(path, "scripts/ledger/") or
        inHome(path, "scripts/census/") or
        inHome(path, "scripts/proof/"))
        return true;
    return named(path, "scripts/agent_smoke.id") or
        named(path, "scripts/public_safety_scan.id") or
        named(path, "scripts/module_surface_gate.id") or
        named(path, "scripts/luahost.id") or
        named(path, "scripts/explain.id") or
        named(path, "scripts/contract.id") or
        named(path, "scripts/realize.id") or
        named(path, "scripts/sim.id") or
        named(path, "scripts/transform.id");
}

fn callApplication(expr: *const Expr) bool {
    const c = expr.call;
    switch (c.func.*) {
        .name => |n| {
            if (std.mem.eql(u8, n.ident, "gatecap") and c.args.len == 1) return true;
            if (toStrIntegral(expr)) return true;
            return false;
        },
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

fn toStrIntegral(expr: *const Expr) bool {
    const c = expr.call;
    if (c.args.len != 1) return false;
    if (c.func.* != .call) return false;
    const inner = c.func.call;
    if (inner.func.* != .name or !std.mem.eql(u8, inner.func.name.ident, "to")) return false;
    if (inner.args.len != 1 or inner.args[0].* != .name) return false;
    if (!std.mem.eql(u8, inner.args[0].name.ident, "str")) return false;
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

/// Module-aware bootstrap recognition. `to(…)` inference stays gate-transport
/// only; host egress is admitted everywhere.
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
    if (printApplication(expr)) return true;
    if (module_path) |path| {
        if (gateTransport(path)) {
            if (toApplication(expr)) return true;
        }
    }
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
