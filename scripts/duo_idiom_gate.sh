#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="${DUO:-$ROOT/zig-out/bin/duo}"
if [ -x "$DUO" ] && "$DUO" run "$ROOT/scripts/duo_idiom_gate.duo" >/dev/null 2>&1; then
  exec "$DUO" run "$ROOT/scripts/duo_idiom_gate.duo" "$@"
fi
exec bash "$ROOT/scripts/duo_idiom_gate.bash" "$@"
