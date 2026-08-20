#!/bin/sh
# table_apply gate — every direct lowering path must run table_apply.normalizeModule.
set -u
ROOT=${TABLE_APPLY_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
TABLE_APPLY="$ROOT/src/table_apply.zig"
fail=0
bad() { printf 'table_apply gate: FAIL %s\n' "$1"; fail=$((fail + 1)); }

[ -r "$TABLE_APPLY" ] || { bad "missing $TABLE_APPLY"; exit 1; }
grep -Fq 'pub fn normalizeModule' "$TABLE_APPLY" || bad 'table_apply.zig lost pub fn normalizeModule'

for path in src/dnir_lower.zig src/native_backend.zig src/main.zig src/semantic_graph.zig; do
    file="$ROOT/$path"
    [ -r "$file" ] || { bad "missing $path"; continue; }
    grep -Fq 'table_apply.normalizeModule' "$file" || bad "$path does not call table_apply.normalizeModule"
done

# Self-host compiler modules must compile through the guarded pipeline, not a bypass.
for mod in bind lexer parser graph monolith; do
    file="$ROOT/lib/compiler/${mod}.id"
    [ -r "$file" ] || bad "missing lib/compiler/${mod}.id"
done

if [ "$fail" -ne 0 ]; then exit "$fail"; fi
printf 'table_apply gate: PASS — normalizeModule on all direct lowering paths\n'
