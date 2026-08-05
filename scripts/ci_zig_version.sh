#!/usr/bin/env bash
# Pass 11 WP-13: single source for CI Zig pin (read from build.zig.zon).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -E 'minimum_zig_version' "$ROOT/build.zig.zon" \
  | sed -E 's/.*"([^"]+)".*/\1/' \
  | head -1
