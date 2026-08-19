#!/bin/sh
# Idol main repo MCP server wrapper — ensures correct working directory
# (path-relative: the tracked launcher must not bake machine-local paths —
# public_safety_scan greps tracked .sh for /Users leakage)
cd "$(dirname "$0")/.."
exec ./zig-out/bin/idol run --backend=native tools/mcp/native.id