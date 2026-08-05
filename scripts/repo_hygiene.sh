#!/usr/bin/env bash
# Pass 11 WP-12: repository hygiene gate (forbidden root artifacts).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAIL=0

fail() {
  echo "repo_hygiene: FAIL — $1" >&2
  FAIL=1
}

# Root file literally named "-" (1MB accident from Pass 10 audit).
if [[ -e "$ROOT/-" ]]; then
  fail "root file '-' must be removed"
fi

# Tracked benchmark scratch (should not be in release tree).
for f in .all_bench_output.log .run_all_bench_cmds.sh; do
  if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    fail "tracked scratch file $f (git rm or archive)"
  fi
done

# Root probe binaries from agent sessions.
if compgen -G "$ROOT/_*.out" >/dev/null 2>&1; then
  fail "root _*.out probe binaries present (delete or gitignore)"
fi
# Tracked root *.out must never ship (local gitignored copies are ok).
if git ls-files '*.out' 2>/dev/null | grep -q .; then
  fail "tracked *.out files in repository (git rm)"
fi

# Tracked benchmark/reference binaries (must not be in release tree).
for f in benchmark_c benchmark_c_fastmath benchmark_c_zigcc default.profraw; do
  if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    fail "tracked build artifact $f (git rm)"
  fi
done

# Local Duo cache must not be tracked.
if git ls-files .duo/ 2>/dev/null | grep -q .; then
  fail "tracked .duo/ cache directory (git rm -r --cached .duo/)"
fi

# Agent-local settings must not be tracked.
for d in .poolside .serena .antigravitycli .kiro .junie; do
  if git ls-files "$d" 2>/dev/null | grep -q .; then
    fail "tracked agent-local directory $d/"
  fi
done

if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi

echo "repo_hygiene: PASS"
