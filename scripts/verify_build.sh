#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="${DUO:-$ROOT/zig-out/bin/duo}"
if [ ! -x "$DUO" ]; then (cd "$ROOT" && zig build); fi
exec "$DUO" run "$ROOT/scripts/verify_build.duo" "$@"
