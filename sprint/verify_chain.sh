#!/usr/bin/env bash
# verify_chain.sh <chain.manifest> — fail-closed verification of a difftest chain.
# Manifest columns (tab-separated): role, sha256, path, producer-path, producer-sha256.
# For every entry: the path must exist and re-hash to the recorded digest.
# For entries naming a producer: the producer path must exist and re-hash to the
# recorded producer digest — a swapped producer binary fails, even when the
# artifact itself is untouched. The qualification chain roles (source, B, C, C2,
# and at least one c2qual-*) must all be present: a manifest with no proof that
# C2 executed the declared compilation cannot pass.
# Exit 0 iff the whole chain verifies.
set -euo pipefail

M="${1:?usage: sprint/verify_chain.sh <chain.manifest>}"
[ -f "$M" ] || { echo "[verify] FATAL: manifest not found: $M" >&2; exit 1; }

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}
TAB="$(printf '\t')"

fail=0
while IFS="$TAB" read -r role h path ppath ph || [ -n "${role:-}" ]; do
  [ -n "${role:-}" ] || continue
  if [ ! -f "$path" ]; then
    echo "[verify] MISSING artifact: role=$role path=$path" >&2
    fail=1; continue
  fi
  cur=$(sha256 "$path")
  if [ "$cur" != "$h" ]; then
    echo "[verify] ARTIFACT-CHANGED: role=$role path=$path" >&2
    echo "[verify]   manifest=$h actual=$cur" >&2
    fail=1
  fi
  if [ -n "${ppath:-}" ]; then
    if [ ! -f "$ppath" ]; then
      echo "[verify] PRODUCER-MISSING: role=$role producer=$ppath" >&2
      fail=1
    else
      pcur=$(sha256 "$ppath")
      if [ "$pcur" != "${ph:-}" ]; then
        echo "[verify] PRODUCER-SWAPPED: role=$role was built by $ppath" >&2
        echo "[verify]   manifest-producer-hash=${ph:-} actual=$pcur" >&2
        fail=1
      fi
    fi
  fi
done < "$M"

for need in source B C C2; do
  grep -q "^${need}${TAB}" "$M" || { echo "[verify] CHAIN-INCOMPLETE: no '$need' entry" >&2; fail=1; }
done
grep -q '^c2qual-' "$M" || { echo "[verify] CHAIN-INCOMPLETE: no c2qual-* entry (C2 execution unproven)" >&2; fail=1; }

if [ "$fail" -eq 0 ]; then echo "[verify] CHAIN-LINEAGE PASS"; fi
exit "$fail"
