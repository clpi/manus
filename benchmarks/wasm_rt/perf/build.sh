#!/bin/sh
# Build the wasm benchmark kernels.  Every number in perf/README-RESULTS.md
# comes from modules produced by exactly this script.
#
# Apple's bundled clang has no WebAssembly target; use LLVM's.  wasi-libc is
# the sysroot (`brew install wasi-libc llvm`).
set -e

CLANG="${CLANG:-/opt/homebrew/opt/llvm/bin/clang}"
SYSROOT="${SYSROOT:-/opt/homebrew/opt/wasi-libc/share/wasi-sysroot}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/wasm"

mkdir -p "$OUT"
for f in "$HERE"/kernels/*.c; do
    n=$(basename "$f" .c)
    "$CLANG" --target=wasm32-wasip1 --sysroot="$SYSROOT" -O2 \
        -o "$OUT/$n.wasm" "$f"
    echo "built $OUT/$n.wasm"
done
