#!/usr/bin/env sh
# ANY-TYPE RATCHET — GAP-235. The owner ruling, verbatim:
#
#   "Any should never be explicit since a non specified type is by default
#    compiler inferred any or void based on demand. Any should be an edge
#    (a method) of any iterable injected algebraically."
#
# So the word `any` has exactly one canonical source face: the RELATION
# `xs:any(p)` — the existential edge on an iterable, resolved subject-first
# (COLLECTION-RELATION-ONE, src/collection_relation.zig). The TYPE-position
# spelling `x: any` is non-canonical: absence of an annotation already means
# compiler-inferred, and demand decides any-vs-void (SOURCE-INFER-ONE,
# `law.infer.one` — no source spelling survives merely to restate a fact the
# compiler recovers uniquely).
#
# This gate does not migrate the population — that is per-site semantic work
# recorded in gaps/GAP-235.md, and a removal is lawful only where inference
# recovers the same fact. It stops the population GROWING, which is the part a
# reviewer cannot be expected to catch by reading a diff.
#
# ONE RULE, monotonic: the code-position count of type-position `any` may only
# shrink. Lowering the pin below is the intended way to record migration
# progress; a count above the pin fails.
#
# COUNTS ARE CODE POSITIONS ONLY. `#` comments are stripped before matching,
# because prose describing the spelling is not a use of it. String literals are
# NOT stripped — the same accepted limit gate/directive.sh documents; a string
# mention counts until the lexical identities in GAP-145 give a truer census.
#
# THE RELATION FACE IS NOT COUNTED. `xs:any(p)` is canonical and must never
# score: the pattern excludes `any` immediately followed by `(`. Both
# directions are proven by the controls below before anything is measured.
#
# ZERO SUBJECTS IS A FAILURE, NOT A PASS (GAP-201): enumeration goes through
# gate/subject.sh, the one fail-closed subject producer.
set -u
LC_ALL=C
export LC_ALL

# THE PIN. Code positions of type-position `any` across tracked .id files at
# the ratchet's last tightening. May only be lowered, and only together with
# the migration that earned it.
pin=5038

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
subject="$repo/gate/subject.sh"
[ -f "$subject" ] || { echo "any.sh: missing $subject" >&2; exit 2; }
tmp="$(mktemp "${TMPDIR:-/tmp}/idolany.XXXXXX")"; trap 'rm -f "$tmp" "$tmp.files" "$tmp.ctl"' EXIT

# Type-position `any` in one file: strip comments, then count occurrences of
# `:` `any` NOT followed by `(` (the relation face) and not part of a longer
# word. Occurrences, not lines — `(a: any, b: any)` is two positions, which is
# why this is `grep -o` piped to a line count and never `grep -c`. One
# function, used by the controls and the census both, so they cannot drift.
positions() {
  # The relation face is neutralized FIRST — `xs:any(p)` and the spaced
  # spelling `xs:any (p)` are both the canonical existential edge, and a
  # lookahead-free grep cannot exclude the spaced form, so the face is
  # substituted away before counting. `x: any = (v) …` survives because the
  # `=` breaks the face shape.
  sed -e 's/#.*//' -e 's/:[[:space:]]*any[[:space:]]*(/:relationface(/g' "$1" \
    | grep -oE ':[[:space:]]*any([^([:alnum:]_]|$)' | grep -c .
}

# ---------------------------------------------------------------------------
# CONTROLS IN BOTH DIRECTIONS, run before the census. A counter that cannot be
# shown to score the retired face and to ignore the canonical one proves
# nothing about a clean tree.
ctl_expect() {
  # $1 expected count, $2 control label; the subject text is on stdin.
  cat > "$tmp.ctl"
  got=$(positions "$tmp.ctl")
  if [ "$got" -ne "$1" ]; then
    echo "any.sh: CONTROL FAILED [$2] counted $got, want $1" >&2
    exit 2
  fi
}

ctl_expect 1 "type-position param" <<'EOF'
f: str = (v: any)
EOF
ctl_expect 2 "two params one line" <<'EOF'
mix = (a: any, b: any)
EOF
ctl_expect 1 "binding at end of line" <<'EOF'
t: any
EOF
ctl_expect 1 "result annotation" <<'EOF'
box: any = (x: i64)
EOF
ctl_expect 0 "relation face is canonical" <<'EOF'
hit = xs:any((x) x % 2 == 0)
EOF
ctl_expect 0 "tight relation face" <<'EOF'
ok = zs:any(p)
EOF
ctl_expect 0 "comment is prose" <<'EOF'
# a: any is described here, not used
EOF
ctl_expect 0 "longer word is not any" <<'EOF'
q = s:anything(1)
EOF
ctl_expect 0 "spaced relation face is canonical" <<'EOF'
hit = xs:any (p)
EOF
ctl_expect 1 "annotated callable binding still counts" <<'EOF'
box: any = (x: i64)
    x
EOF

# ---------------------------------------------------------------------------
# THE CENSUS. Consume the one fail-closed repository subject producer; do not
# restore a gate-local find/Git fallback beside it.
if ! sh "$subject" '*.id' >"$tmp.files"; then
  echo "any.sh: Idol source enumeration failed (GAP-201/GAP-220)" >&2
  exit 2
fi
subjects=$(grep -c . <"$tmp.files")
[ "$subjects" -gt 0 ] || { echo "any.sh: ZERO subjects enumerated — census proves nothing" >&2; exit 2; }

total=0
while IFS= read -r f; do
  n=$(positions "$f")
  total=$((total + n))
done < "$tmp.files"

echo "any.sh: $subjects .id subjects, $total type-position 'any' code position(s); pin $pin."
if [ "$total" -gt "$pin" ]; then
  echo "any.sh: type-position 'any' GREW ($pin -> $total) — the spelling is closed (GAP-235):" >&2
  echo "  the absence of an annotation already means compiler-inferred; write nothing," >&2
  echo "  and keep 'any' for the relation face 'xs:any(p)' only." >&2
  echo "any.sh: ANY RATCHET BROKEN." >&2
  exit 1
fi
if [ "$total" -lt "$pin" ]; then
  echo "any.sh: migration progress — $((pin - total)) position(s) below the pin; lower the pin to lock it in."
fi
echo "any.sh: ANY OK."
exit 0
