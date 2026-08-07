#!/usr/bin/env bash
# P0 — Pass 27 benchmark proof matrix (3 profiles + emission audit).
# Canonical entry: scripts/run_benchmark_proof.duo (this file is a thin wrapper).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO="${DUO:-$ROOT/zig-out/bin/duo}"
if [ ! -x "$DUO" ]; then (cd "$ROOT" && zig build); fi
exec "$DUO" run "$ROOT/scripts/run_benchmark_proof.duo" "$@"
