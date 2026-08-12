/* GENERATED from src/token_classify_gen.zig — do not edit by hand.
 * Regenerate: duo token-tables emit
 * Canonical Duo projection: lib/std/token/classify.id (@c.export classify)
 * Production consumer: src/keyword_bridge.zig → src/lexer.zig
 */
#include <stdint.h>
#include <string.h>

/* weak: this generated table is the PROJECTION of
 * lib/std/token/classify.id. A program that embeds the canonical Duo
 * source emits its own definition of the same symbol, and A3 ONE EDGE
 * says there is one fact behind both — so the Duo-emitted one must be
 * allowed to win rather than colliding. Without this, anything pulling
 * in SH-02's artifact AND SH-03's lexer fails to link with
 * `duplicate symbol '_duo_keyword_classify'`. */
__attribute__((weak)) int64_t duokeywordclassify(const char *w) {
    if (strcmp(w, "and") == 0) return 4;
    if (strcmp(w, "break") == 0) return 5;
    if (strcmp(w, "continue") == 0) return 6;
    if (strcmp(w, "do") == 0) return 7;
    if (strcmp(w, "else") == 0) return 8;
    if (strcmp(w, "elseif") == 0) return 9;
    if (strcmp(w, "end") == 0) return 10;
    if (strcmp(w, "false") == 0) return 11;
    if (strcmp(w, "for") == 0) return 12;
    if (strcmp(w, "function") == 0) return 13;
    if (strcmp(w, "fun") == 0) return 14;
    if (strcmp(w, "global") == 0) return 15;
    if (strcmp(w, "goto") == 0) return 16;
    if (strcmp(w, "if") == 0) return 17;
    if (strcmp(w, "in") == 0) return 18;
    if (strcmp(w, "local") == 0) return 19;
    if (strcmp(w, "nil") == 0) return 20;
    if (strcmp(w, "not") == 0) return 21;
    if (strcmp(w, "or") == 0) return 22;
    if (strcmp(w, "repeat") == 0) return 23;
    if (strcmp(w, "return") == 0) return 24;
    if (strcmp(w, "then") == 0) return 25;
    if (strcmp(w, "true") == 0) return 26;
    if (strcmp(w, "until") == 0) return 27;
    if (strcmp(w, "while") == 0) return 28;
    if (strcmp(w, "const") == 0) return 29;
    if (strcmp(w, "enum") == 0) return 30;
    if (strcmp(w, "i8") == 0) return 31;
    if (strcmp(w, "i16") == 0) return 32;
    if (strcmp(w, "i32") == 0) return 33;
    if (strcmp(w, "i64") == 0) return 34;
    if (strcmp(w, "u8") == 0) return 35;
    if (strcmp(w, "u16") == 0) return 36;
    if (strcmp(w, "u32") == 0) return 37;
    if (strcmp(w, "u64") == 0) return 38;
    if (strcmp(w, "f32") == 0) return 39;
    if (strcmp(w, "f64") == 0) return 40;
    if (strcmp(w, "bool") == 0) return 41;
    if (strcmp(w, "void") == 0) return 42;
    if (strcmp(w, "str") == 0) return 43;
    if (strcmp(w, "match") == 0) return 44;
    if (strcmp(w, "try") == 0) return 45;
    if (strcmp(w, "catch") == 0) return 46;
    if (strcmp(w, "defer") == 0) return 47;
    if (strcmp(w, "async") == 0) return 48;
    if (strcmp(w, "await") == 0) return 49;
    if (strcmp(w, "concept") == 0) return 50;
    if (strcmp(w, "alias") == 0) return 51;
    if (strcmp(w, "private") == 0) return 52;
    if (strcmp(w, "extends") == 0) return 53;
    if (strcmp(w, "macro") == 0) return 54;
    if (strcmp(w, "comptime") == 0) return 55;
    if (strcmp(w, "by") == 0) return 56;
    if (strcmp(w, "let") == 0) return 57;
    return 0;
}
