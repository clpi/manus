// Root test aggregator.
// Importing each module causes the test runner to discover and execute all
// `test` blocks declared inside that module.
const std = @import("std");

test {
    _ = @import("lexer.zig");
    _ = @import("ast.zig");
    _ = @import("types.zig");
    _ = @import("parser.zig");
    _ = @import("sema.zig");
    _ = @import("comptime.zig");
    _ = @import("macro_expand.zig");
    _ = @import("mono.zig");
    _ = @import("arc.zig");
    _ = @import("async_lower.zig");
    _ = @import("escape.zig");
    _ = @import("property_tests.zig");
    _ = @import("pretty.zig");
    _ = @import("codegen.zig");
    _ = @import("directives.zig");
    _ = @import("term.zig");
    _ = @import("debug_trace.zig");
    _ = @import("build_framework.zig");
    _ = @import("ml_kernels.zig");
    _ = @import("jit.zig");
}
