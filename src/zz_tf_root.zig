// SCRATCH — SAFE TO DELETE. Untracked test root used to run `table_facts`
// tests in isolation (`zig test src/zz_tf_root.zig -lc src/keyword_classify.c
// src/lexer_tokenize.c --test-filter table_facts`) without pulling in
// dnir_lower.zig, which other lanes were editing at the time.
//
// Nothing imports this file, so it is not compiled by `zig build` or by
// `zig build test`, and the language census counts `git ls-files` only
// (scripts/language_census.id:143), so an untracked file cannot trip it.
comptime {
    _ = @import("table_facts.zig");
}
