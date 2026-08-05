#!/bin/sh
# Pass 10 A19 — public safety pre-scan (tracked + staged files).
# Exit 0 = no hits; exit 1 = review required.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAIL=0
report() {
  echo "public_safety_scan: $1"
  FAIL=1
}

if [ ! -f LICENSE ]; then
  report "missing LICENSE at repo root"
fi

# Patterns: API keys, private key blocks, common token prefixes
SECRET_RG='AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----'

# Personal / machine paths that should not appear in tracked public files
PATH_RG='/Users/[a-zA-Z0-9._-]+|/home/[a-zA-Z0-9._-]+|C:\\Users\\'

scan_files() {
  git ls-files -z "$@" | xargs -0 grep -nE "$1" 2>/dev/null || true
}

HITS=$(scan_files "$SECRET_RG" | head -20)
if [ -n "$HITS" ]; then
  echo "$HITS"
  report "possible secret material in tracked files (review above)"
fi

# Personal paths — production docs and source only (exclude agent/plan/ledger paths)
PATH_SCAN=$(git ls-files -z \
  '*.md' '*.duo' '*.zig' '*.lua' '*.sh' '*.yaml' '*.yml' '*.json' \
  | xargs -0 grep -nE "$PATH_RG" 2>/dev/null \
  | grep -vE '^(\.agents/|\.cursor/|\.poolside/|\.vscode/|docs/AGENT_|docs/plans/|docs/performance\.md|scripts/mcp/|AGENTS\.md|CLAUDE\.md)' \
  | head -20 || true)
if [ -n "$PATH_SCAN" ]; then
  echo "$PATH_SCAN"
  report "personal filesystem paths in public tracked files (review above)"
fi

# Large unexpected binaries in tracked tree
LARGE=$(git ls-files -z | xargs -0 -I{} sh -c 'test -f "{}" && test $(wc -c < "{}") -gt 5000000 && echo "{}"' 2>/dev/null | head -10 || true)
if [ -n "$LARGE" ]; then
  echo "$LARGE"
  report "tracked files >5MB (review above)"
fi

if [ "$FAIL" -ne 0 ]; then
  echo "public_safety_scan: FAIL"
  exit 1
fi

echo "public_safety_scan: PASS"
exit 0
