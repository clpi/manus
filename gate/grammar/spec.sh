#!/bin/sh
# gate/grammar/spec.sh — GAP-134 item 5 counterfactual.
#
# docs/spec/grammar.md carries a GENERATED region projected from the one
# grammar-fact owner (lib/compiler/token.id), read through its generated
# bridge src/grammar_role_table.zig — the same read target
# gate/treesitter/agreement.id uses. This gate refuses when:
#   - the tracked markdown drifted from what the owner regenerates (exit 1);
#   - a damaged owner fact does NOT change the projection (exit 1) — the
#     vacuity control: a projection that ignores its owner is decoration;
#   - the generator or any subject is missing (exit 2/3).
#
# On DNB004 hosts the projection is produced by tools/node/dev/grammar/spec,
# which reads the owner's generated bridge; scripts/grammar/spec.id carries
# the Idol front for when direct-native execution lifts.
set -u
cd -- "$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd)" || exit 2

refuse() {
  printf 'grammar spec: FAIL — %s\n' "$*" >&2
  exit 2
}

gen=./tools/node/dev/grammar/spec
md=docs/spec/grammar.md
bridge=src/grammar_role_table.zig
for subject in "$gen" "$md" "$bridge"; do
  [ -s "$subject" ] || refuse "subject absent or empty: $subject"
done
[ -x "$gen" ] || refuse "generator not executable: $gen"

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-grammar-spec.XXXXXX") || exit 2
trap 'rm -rf -- "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# ── regeneration must SAY what it compared ────────────────────────────────
"$gen" >"$work/gen.md" 2>"$work/gen.err" || {
  cat -- "$work/gen.err" >&2
  exit 3
}
[ -s "$work/gen.md" ] || refuse "generator produced no output"
if cmp -s "$work/gen.md" "$md"; then
  :
else
  printf 'grammar spec: FAIL — %s does not regenerate byte-identically\n' "$md" >&2
  diff "$work/gen.md" "$md" | sed -n '1,15p' >&2
  exit 1
fi

# ── vacuity control: a damaged owner fact MUST move the projection ────────
ctrl=$(mktemp -d "${TMPDIR:-/tmp}/idol-grammar-spec-ctl.XXXXXX") || exit 2
mkdir -p "$ctrl/src" "$ctrl/docs/spec"
cp "$bridge" "$ctrl/src/grammar_role_table.zig"
cp "$md" "$ctrl/docs/spec/grammar.md"
# Damage ONE owner fact the projection definitely carries: `plus` loses its
# precedence (17). One precise edit; if it did not land, refuse rather than
# silently pass a vacuous control (law.evidence.subject.one).
perl -0pi -e 's/(\.kind = \.plus, [^\n]*?), \.precedence = 17/$1/' "$ctrl/src/grammar_role_table.zig"
cmp -s "$ctrl/src/grammar_role_table.zig" "$bridge" &&
  refuse "could not damage the owner bridge for the vacuity control"
GEN_ROOT="$ctrl" "$gen" >"$work/gen2.md" 2>"$work/gen2.err" || {
  cat -- "$work/gen2.err" >&2
  exit 3
}
if cmp -s "$work/gen2.md" "$work/gen.md"; then
  printf 'grammar spec: FAIL — damaged owner fact did not change the projection (vacuous)\n' >&2
  exit 1
fi
printf 'grammar spec control: PASS — damaged owner fact changed the projection\n'

printf 'grammar spec: PASS — %s regenerates byte-identically from %s\n' "$md" "$bridge"
exit 0
