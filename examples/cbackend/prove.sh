#!/bin/sh
# C-REALIZER-TEST: explicit graph-observed DNIR to portable C99, isolated from direct and auto
set -eu

repo=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
compiler=${IDOL_C_REALIZER_COMPILER:-"$repo/zig-out/bin/idol"}
cc=${CC:-/usr/bin/clang}
poison=/definitely/not/an/idol-c-compiler
scratch=$(mktemp -d /tmp/idol-c-realizer.XXXXXX)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM

locked() {
    "$repo/tools/node/dev/idol-lock" -- "$@"
}

fixture="$repo/examples/cbackend/graphslice.id"

# The explicit graph-backed source route must return before either the retired
# AST/Lua bridge or a configured C compiler can be reached.
locked "$compiler" compile "$fixture" --backend=c --emit=c --cc "$poison" -o "$scratch/graph.c"
if grep -Eq 'lua_Value|lua_|CodeGen|codegen\.zig' "$scratch/graph.c"; then
    echo "generated C contains retired AST/Lua bridge residue" >&2
    exit 1
fi
if grep -Eq '@import\("codegen\.zig"\)' "$repo/src/c_backend.zig"; then
    echo "C physical realizer imports the retired emitter" >&2
    exit 1
fi
locked "$cc" -std=c99 -O2 -Wall -Wextra -Werror "$scratch/graph.c" -o "$scratch/graph"
if "$scratch/graph"; then c_answer=0; else c_answer=$?; fi
test "$c_answer" -eq 42

# Neither half of the source-realizer selection may be inferred.
if locked "$compiler" compile "$fixture" --emit=c -o "$scratch/inferred-c.c" >"$scratch/inferred-c.log" 2>&1; then
    echo "auto selected C from --emit=c" >&2
    exit 1
fi
grep -q 'explicit orthogonal realization' "$scratch/inferred-c.log"
if locked "$compiler" compile "$fixture" --backend=c -o "$scratch/inferred-emit" >"$scratch/inferred-emit.log" 2>&1; then
    echo "--backend=c inferred an output kind" >&2
    exit 1
fi
grep -q 'portable source only' "$scratch/inferred-emit.log"

# Retired AST/Lua C benchmark profiles stay exact refusals. They may not select
# the orthogonal source realizer or turn benchmark execution back into C.
if locked "$compiler" compile "$fixture" --bench-backend=c-specialized -o "$scratch/retired-bench" >"$scratch/retired-bench.log" 2>&1; then
    echo "retired C benchmark profile executed" >&2
    exit 1
fi
grep -q 'retired with the AST/Lua C bridge' "$scratch/retired-bench.log"
grep -q 'not an execution backend' "$scratch/retired-bench.log"
test ! -e "$scratch/retired-bench"

# A poisoned C compiler does not change direct or automatic object emission.
# The configured compiler is used only afterward as an independent linker.
locked "$compiler" compile "$fixture" --backend=direct --emit=obj --lib --cc "$poison" -o "$scratch/direct-poison.o"
locked "$compiler" compile "$fixture" --backend=direct --emit=obj --lib --cc "$cc" -o "$scratch/direct-control.o"
locked "$compiler" compile "$fixture" --backend=auto --emit=obj --lib --cc "$poison" -o "$scratch/auto-poison.o"
locked "$compiler" compile "$fixture" --bench-backend=direct --emit=obj --lib --cc "$poison" -o "$scratch/bench-direct.o"
cmp "$scratch/direct-poison.o" "$scratch/direct-control.o"
cmp "$scratch/direct-poison.o" "$scratch/auto-poison.o"
cmp "$scratch/direct-poison.o" "$scratch/bench-direct.o"

locked "$cc" "$scratch/direct-poison.o" -o "$scratch/direct"
locked "$cc" "$scratch/auto-poison.o" -o "$scratch/auto"
if "$scratch/direct"; then direct_answer=0; else direct_answer=$?; fi
if "$scratch/auto"; then auto_answer=0; else auto_answer=$?; fi
test "$direct_answer" -eq 42
test "$auto_answer" -eq 42

# This is a semantic program that reaches the direct capability boundary.
# Auto must preserve that refusal instead of trying either C realization.
#
# THE SUBJECT MUST EXIST, and that line is the whole point of this paragraph.
# Until 2026-08-22 this pointed at g066_written_file_scope_global.id, which
# 4cb1fd1c had DELETED on 2026-08-18 when written file-scope bindings gained
# storage. A missing path makes `compile` exit non-zero with `FileNotFound`,
# which is indistinguishable from the refusal this control is asserting -- so
# the `if` below read a vacuous success for 324 commits and only the grep on
# the (empty) log kept the step red. A negative control whose subject can
# vanish silently is not a control, so the existence check is asserted first
# and by itself.
refusal="$repo/examples/native_differential/unsupported/p09_closure.id"
test -f "$refusal" || { echo "refusal subject is missing: $refusal" >&2; exit 1; }
if locked "$compiler" compile "$refusal" --backend=auto -o "$scratch/auto-refusal.out" >"$scratch/auto-refusal.log" 2>&1; then
    echo "auto hid a direct-native refusal" >&2
    exit 1
fi
grep -q 'outside the current direct-native subset' "$scratch/auto-refusal.log"
grep -q 'never falls back to C' "$scratch/auto-refusal.log"
test ! -e "$scratch/auto-refusal.out"

printf 'C99=%s direct=%s auto=%s artifact=' "$c_answer" "$direct_answer" "$auto_answer"
shasum -a 256 "$scratch/direct-poison.o" | awk '{print $1}'
