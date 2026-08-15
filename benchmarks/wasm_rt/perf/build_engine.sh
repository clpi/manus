#!/bin/sh
# Build a RUNNABLE copy of tools/wasm/src/engine.id.
#
# The committed engine does not build.  `zig build wasm-test` runs
#     idol compile src/engine.id --backend=c --emit exe
# and that command fails at HEAD with malformed C, and fails on every other
# backend with DNB001.  engine_workarounds.py applies the smallest set of
# source edits that get past those compiler defects; see that file for what
# each one is and why it is a compiler bug rather than an engine bug.
#
# Nothing here is committed back: the workarounds are applied to a pristine
# `git archive HEAD` copy in a scratch directory, so the tree is untouched and
# the measured binary is reproducible from a named revision.
#
# Usage:  ./build_engine.sh [REV] [OUTDIR]
set -e

REV="${1:-HEAD}"
OUT="${2:-/tmp/idol_wasm_engine}"
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"

rm -rf "$OUT/src"
mkdir -p "$OUT/src"
(cd "$REPO" && git archive "$REV") | tar -x -C "$OUT/src"

# The compiler must come from the same revision: zig-out/bin/idol in a working
# tree drifts, and a drifted compiler rejects the committed engine outright
# (measured: `:char()` unresolved).
(cd "$OUT/src" && zig build -Doptimize=ReleaseFast)

python3 "$HERE/engine_workarounds.py" "$OUT/src/tools/wasm/src/engine.id"

cd "$OUT/src/tools/wasm"
"$OUT/src/zig-out/bin/idol" compile src/engine.id --backend=c --emit exe \
    -o "$OUT/ward"
echo "built $OUT/ward   (revision $REV + engine_workarounds.py)"

# A second binary with the engine's own diagnostics routed to stdout.  Every
# refusal in engine.id goes through `iom.err`, i.e. `io.err`, which the C
# runtime does not provide -- so the engine currently exits 1/70/71 in total
# silence and every gap is invisible.  This variant is how the capability gaps
# in RESULTS.md were named.
python3 - "$OUT/src/tools/wasm/src/engine.id" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
open(p, 'w').write(s.replace('iom.err(', 'print('))
PY
"$OUT/src/zig-out/bin/idol" compile src/engine.id --backend=c --emit exe \
    -o "$OUT/ward-diag"
echo "built $OUT/ward-diag  (same, with diagnostics visible)"
