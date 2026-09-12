#!/bin/sh
# thin driver: the gate logic lives in gate/gap-111-subject-first.id
# (native Idol). This wrapper only resolves the repo root, takes the
# gate lock, and execs the compiler on the .id.
set -eu
root=${GAP111_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}
if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi
idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
if [ ! -x "$idol" ]; then
    printf 'gap-111-subject-first gate: FAIL compiler is not executable: %s\n' "$idol" >&2
    exit 1
fi
CDPATH='' cd -- "$root" || exit 2
exec "$idol" run --backend native gate/gap-111-subject-first.id
