//! Pass 24 P1 — Lua superset compatibility corpus (parse + lex smoke).
//!
//! Differential execution against reference Lua 5.5 is future work; this corpus
//! proves Duo accepts canonical Lua constructs without repurposing tokens.
const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

pub const SCHEMA_VERSION = "lua-superset-corpus-v0";

pub const CorpusCase = struct {
    id: []const u8,
    /// Construct matrix id from lua_superset_catalog / compatibility doc.
    matrix_id: []const u8,
    source: []const u8,
    /// When set, module must contain at least this many top-level statements.
    min_stmts: usize = 1,
};

pub const lex_cases: []const CorpusCase = &.{
    .{ .id = "lex-ls0", .matrix_id = "LS-0", .source = "x = [[alpha\nbeta]]", .min_stmts = 0 },
    .{ .id = "lex-ls1", .matrix_id = "LS-1", .source = "x = [=[contains ]] without ending]=]", .min_stmts = 0 },
    .{ .id = "lex-ls2", .matrix_id = "LS-2", .source = "x = [==[nested ]=] ok ]==]", .min_stmts = 0 },
    .{ .id = "lex-lc0", .matrix_id = "LC-0", .source = "--[[ block ]]\nx = 1", .min_stmts = 0 },
    .{ .id = "lex-lc1", .matrix_id = "LC-1", .source = "--[=[ has ]] inside ]=]\ny = 2", .min_stmts = 0 },
};

pub const parse_cases: []const CorpusCase = &.{
    .{
        .id = "parse-ls-control",
        .matrix_id = "LS-1",
        .source =
        \\block = [[alpha
        \\beta]]
        \\bracket = [=[contains ]] without ending]=]
        ,
        .min_stmts = 2,
    },
    .{
        .id = "parse-if-then-long-comment",
        .matrix_id = "LC-0",
        .source =
        \\block = [[alpha
        \\beta]]
        \\--[[ long-string regression ]]
        \\if block ~= "alpha\nbeta" then
        \\    x = 1
        \\end
        ,
        .min_stmts = 2,
    },
    .{
        .id = "parse-if-then",
        .matrix_id = "CF-0",
        .source =
        \\if ready then
        \\    run()
        \\end
        ,
        .min_stmts = 1,
    },
    .{
        .id = "parse-local-function",
        .matrix_id = "FN-0",
        .source =
        \\local function add(a, b)
        \\    return a + b
        \\end
        ,
        .min_stmts = 1,
    },
    .{
        .id = "parse-paren-call",
        .matrix_id = "CL-0",
        .source = "print(\"hi\", 42)",
        .min_stmts = 1,
    },
    .{
        .id = "parse-repeat-until",
        .matrix_id = "CF-1",
        .source =
        \\repeat
        \\    n = n - 1
        \\until n <= 0
        ,
        .min_stmts = 1,
    },
    .{
        .id = "parse-shell-boundary",
        .matrix_id = "LS-1",
        .source =
        \\script = [=[
        \\if [[ -f "$file" ]]; then
        \\    echo "$file"
        \\fi
        \\]=]
        ,
        .min_stmts = 1,
    },
};

pub fn validateLexCase(case: CorpusCase) !void {
    var lex = Lexer.init(case.source, case.id);
    var tokens: usize = 0;
    while (true) {
        const tok = try lex.next();
        tokens += 1;
        if (tok.kind == .eof) break;
    }
    if (tokens < 2) return error.CorpusLexEmpty;
}

pub fn validateParseCase(alloc: std.mem.Allocator, case: CorpusCase) !void {
    var lex = Lexer.init(case.source, case.id);
    var parser = Parser.init(&lex, alloc);
    parser.duo_mode = true;
    const mod = try parser.parse_module();
    const stmt_count = mod.body.stmts.len + if (mod.body.tail_expr != null) @as(usize, 1) else 0;
    if (stmt_count < case.min_stmts) return error.CorpusParseTooFewStmts;
}

pub fn validateCorpus(alloc: std.mem.Allocator) !void {
    for (lex_cases) |case| try validateLexCase(case);
    for (parse_cases) |case| try validateParseCase(alloc, case);
}

test "lua_superset_corpus: lex + parse smoke" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try validateCorpus(arena.allocator());
}
