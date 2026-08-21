#!/bin/sh
# Runs every shell gate that EXISTS, and measures the citation debt gap[212]
# records. AGENTS.md has told every reader `sh gate/all.sh runs the lot` since
# before this file was written; `git log --all -- gate/all.sh` was empty until
# this commit, so the instruction named a file that had never existed. This is
# that file, and it claims only what it measures.
set -u

repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo" || exit 64

pass=0
fail=0
failed=

for gate in gate/*.sh; do
  case $gate in
    gate/all.sh) continue ;;
  esac
  [ -r "$gate" ] || continue
  if sh "$gate" >/dev/null 2>&1; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failed="$failed $gate"
  fi
done

# CITATION DEBT. gap[212]: a citation to a gate that has never existed is
# indistinguishable, to a reader, from a citation to a passing one. This counts
# them rather than asserting a number, so the figure cannot rot the way the one
# in AGENTS.md line 60 did.
cited=0
ghost_cites=0
ghost_files=0
for path in $(grep -rhoE 'gate/[a-z0-9_-]+\.sh' src gate docs AGENTS.md CLAUDE.md 2>/dev/null | sort -u); do
  n=$(grep -rhoE "$(printf '%s' "$path" | sed 's/\./\\./g')" src gate docs AGENTS.md CLAUDE.md 2>/dev/null | wc -l | tr -d ' ')
  cited=$((cited + n))
  if [ -z "$(git log --all --oneline -- "$path" 2>/dev/null | head -1)" ]; then
    ghost_cites=$((ghost_cites + n))
    ghost_files=$((ghost_files + 1))
  fi
done

printf 'gate/all.sh: ran %s gate(s): %s passed, %s failed\n' \
  "$((pass + fail))" "$pass" "$fail"
[ -n "$failed" ] && printf 'gate/all.sh: FAILED:%s\n' "$failed"
printf 'gate/all.sh: citation debt: %s of %s gate citations name %s gate(s) with no commit in any history (gap[212])\n' \
  "$ghost_cites" "$cited" "$ghost_files"

# This gate does NOT fail on the citation debt. gap[212] records the budget and
# owns the ratchet; failing here would make `sh gate/all.sh` red on day one,
# which is exactly how build.zig records that audit100 and capability-scan came
# to be skipped. It fails only when a gate that exists fails.
[ "$fail" -eq 0 ] || exit 1
exit 0
