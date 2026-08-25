#!/bin/sh
# gate/public-safety.sh — the tracked-file secret/personal-path scan, or the
# exact host fact when the scan cannot execute here.
#
# The subject is scripts/public_safety_scan.id executed by the compiler itself
# (`idol run`), and that execution is a direct-native realization: the scan's
# gatecap round-trip needs process capture, which the C realizer (portable
# source only today) and wasm32-wasi (no idol_process_capture extern) both
# refuse. On a host the direct backend refuses, `zig build public-safety`
# reported `run ./zig-out/bin/idol failure` — a sentence about the subject,
# when the fact is about the host. `law.fact.producer.one`: the host fact has
# one producer, and this gate consults it and says the uniform sentence.
set -u

root=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd) || exit 2
idol=${IDOL_BIN:-$root/zig-out/bin/idol}
[ -x "$idol" ] || { printf 'public-safety: no compiler at %s\n' "$idol" >&2; exit 2; }

. "$root/gate/realization/direct.sh"
direct_native_probe "$idol"
if direct_native_absent; then
  direct_native_note 'the tracked-file public-safety scan (its gatecap round-trip runs through the auto backend)'
  exit 1
fi

cd "$root" || exit 2
exec "$idol" run scripts/public_safety_scan.id
