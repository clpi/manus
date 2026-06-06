#!/bin/bash
# Verify that the Neovim plugin files are structurally valid.
# Checks that required files exist and that Neovim can load the ftdetect
# script without errors (headless mode).  Does NOT require a full Neovim
# installation — missing nvim just skips the live test and reports the
# file-existence results.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

ok()  { echo "OK:   $*"; PASS=$((PASS + 1)); }
fail(){ echo "FAIL: $*"; FAIL=$((FAIL + 1)); }

# ── 1. Required plugin files exist ───────────────────────────────────────────

for f in \
    "ftdetect/duo.vim" \
    "syntax/duo.vim" \
    "plugin/duo.vim" \
    "lua/duo/init.lua"
do
    if [ -f "$ROOT/$f" ]; then
        ok "$f exists"
    else
        fail "$f is missing"
    fi
done

# ── 2. Syntax file contains at least one syntax keyword ──────────────────────

SYN="$ROOT/syntax/duo.vim"
if grep -q 'syntax keyword\|syn keyword' "$SYN" 2>/dev/null; then
    ok "syntax/duo.vim defines keywords"
else
    fail "syntax/duo.vim has no 'syntax keyword' definitions"
fi

# ── 3. ftdetect registers .duo extension ─────────────────────────────────────

FTD="$ROOT/ftdetect/duo.vim"
if grep -qE '\.duo' "$FTD" 2>/dev/null; then
    ok "ftdetect/duo.vim references .duo extension"
else
    fail "ftdetect/duo.vim does not reference .duo extension"
fi

# ── 4. Optional: headless nvim smoke-test ────────────────────────────────────

if command -v nvim &>/dev/null; then
    if nvim --headless \
        -c "set rtp+=$ROOT" \
        -c "source $ROOT/ftdetect/duo.vim" \
        -c "qa" 2>/dev/null; then
        ok "nvim loads ftdetect without errors"
    else
        fail "nvim exited non-zero loading ftdetect"
    fi
else
    echo "SKIP: nvim not found — skipping live Neovim test"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
