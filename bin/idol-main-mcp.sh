#!/bin/sh
# Idol main repo MCP server wrapper — ensures correct working directory
# (path-relative: the tracked launcher must not bake machine-local paths —
# public_safety_scan greps tracked .sh for /Users leakage)
cd "$(dirname "$0")/.."
# World binding: the launcher is the trust root for the execution world.
# It exports the world binary identity and records the build revision/hash
# in a sidecar at server start (provenance: launcher-observed at server start).
IDOL_WORLD_BIN="$PWD/zig-out/bin/idol"
IDOL_WORLD_ROOT="$PWD"
export IDOL_WORLD_BIN IDOL_WORLD_ROOT
if [ -x "$IDOL_WORLD_BIN" ]; then
  _rev=$(git rev-parse HEAD 2>/dev/null || printf 'unknown')
  _hash=$(sha256sum "$IDOL_WORLD_BIN" 2>/dev/null | cut -d' ' -f1)
  if [ -n "$_rev" ] && [ -n "$_hash" ]; then
    printf '{"revision":"%s","binhash":"%s"}\n' "$_rev" "$_hash" > "$IDOL_WORLD_BIN.buildid"
  fi
fi
exec ./zig-out/bin/idol run --backend=native tools/mcp/native.id
