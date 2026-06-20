#!/usr/bin/env bash
# Build the duo-lsp server binary from the Duo source.
# Requires the `duo` compiler on PATH or at ../../zig-out/bin/duo.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"
DUO="${DUO_LSP_DUO_BIN:-$ROOT/zig-out/bin/duo}"
if [ ! -x "$DUO" ]; then
  DUO="$(command -v duo || true)"
fi
if [ -z "$DUO" ] || [ ! -x "$DUO" ]; then
  echo "error: duo compiler not found. Build it with 'zig build' or set DUO_LSP_DUO_BIN." >&2
  exit 1
fi

echo "compiling duo-lsp with: $DUO"
"$DUO" compile -o duo-lsp src/server.duo
chmod +x duo-lsp
echo "built: $(pwd)/duo-lsp"