#!/bin/sh
# gate/treesitter/literal.sh — GAP-145 O1 literal authorship witness.
#
# Tree-sitter LITERAL identity rules must come from the executable lexical
# owner, not from independent authorship. The owner is lib/compiler/token.id;
# its generated bridge src/grammar_role_table.zig carries one row per quoted
# literal identity with the owner's spelling (.spell) — reading that bridge is
# reading the owner, because gate/grammar-projection.sh regenerates it
# privately and fails unless the tracked bytes are identical.
#
# What this gate proves, on any host (no Idol execution required):
#   1. every literal identity rule in grammar.js is exactly one owner quoted
#      row (spelling and physical rule both agree), and
#   2. every owner quoted row appears in grammar.js — no extra authored
#      literal identity, no silent recognition hole.
#
# Run: sh gate/treesitter/literal.sh
# Exit 0  literal identity authorship is the owner's
#      1  an authored literal identity diverged from the owner
#      2  environment broken (missing files)
#      3  a control failed — the gate itself is broken, not the grammar
set -eu

cd -- "$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd)" || exit 2

broken() {
  printf 'treesitter literal gate: BROKEN — %s\n' "$*" >&2
  exit 3
}

bridge=src/grammar_role_table.zig
grammar=ext/tree-sitter-idol/grammar.js
emitter=scripts/treesitter_emit.id

[ -f "$bridge" ] || broken "missing owner bridge $bridge"
[ -f "$grammar" ] || broken "missing grammar $grammar"
[ -f "$emitter" ] || broken "missing emitter $emitter"

compare() {
  python3 - "$1" <<'PY'
import re, sys

root = sys.argv[1]
bridge = open(f"{root}/src/grammar_role_table.zig").read()
grammar = open(f"{root}/ext/tree-sitter-idol/grammar.js").read()

# Owner side: one (spell, kind) per quoted row, in row order.
owner = []
for row in bridge.split("\n"):
    if ".quoted = true" not in row:
        continue
    km = re.search(r'\.kind = \.(\w+),', row)
    sm = re.search(r'\.spell = "([^"]+)"', row)
    if not km or not sm:
        print(f"FAIL-PARSE bridge row lacks kind/spell: {row.strip()}")
        sys.exit(1)
    owner.append((sm.group(1), km.group(1)))

physical = {
    "text_lit": "double_quoted_string",
    "bytes_lit": "single_quoted_string",
    "compat_text_lit": "single_quoted_string",
    "compat_long_text_lit": "long_string",
}

# Grammar side: identity aliases `name: $ => $.rule,` and the string union.
# Scoped to the generated literal identity block — from the GAP-145 O1 marker
# to the end of the `string:` union — so aliases elsewhere in the grammar
# (e.g. `named_type`) are not mistaken for literal identities.
block = re.search(
    r'// GAP-145 O1: literal identities are not authored here.*?\n(.*?)^    string: \$ => choice\(\n(?:      \$\.\w+,\n)+    \),',
    grammar, re.S | re.M)
aliases = re.findall(r'^    (\w+): \$ => \$\.(\w+),$', block.group(1), re.M) if block else []
union = re.search(
    r'^    string: \$ => choice\(\n((?:      \$\.\w+,\n)+)    \),$', grammar, re.M)

errors = []
if not block:
    errors.append("grammar.js has no GAP-145 O1 literal identity block")
if not union:
    errors.append("grammar.js has no `string: $ => choice(...)` union over identity rows")
else:
    members = re.findall(r'\$\.(urn)?(\w+),', union.group(1))
    members = re.findall(r'\$\.(\w+),', union.group(1))
    owner_spells = {s for s, _ in owner}
    alias_names = {n for n, _ in aliases}
    for m in members:
        if m not in owner_spells:
            errors.append(f"string union member `{m}` is not an owner quoted row")
    for s, _ in owner:
        if s not in members:
            errors.append(f"owner quoted row `{s}` missing from the string union")
    # Union and alias set must be the same set: an alias outside the union is
    # an authored identity the union disowns, and vice versa.
    for n in alias_names - owner_spells:
        errors.append(f"alias `{n}` outside the union is not an owner quoted row")

# Every alias must be exactly one owner row (spelling AND physical rule).
for name, rule in aliases:
    match = [o for o in owner if o[0] == name]
    if not match:
        errors.append(f"authored literal identity `{name}` has no owner quoted row")
    else:
        spell, kind = match[0]
        if physical.get(kind) != rule:
            errors.append(
                f"literal identity `{name}` maps to physical rule `{rule}`, "
                f"owner kind `{kind}` demands `{physical.get(kind)}`")

# Every owner row must appear as an alias.
for spell, _ in owner:
    if not any(n == spell for n, _ in aliases):
        errors.append(f"owner quoted row `{spell}` has no grammar.js identity rule")

if errors:
    for e in errors:
        print(f"FAIL-LITERAL {e}")
    sys.exit(1)
print(f"OK {len(owner)}")
PY
}

# ── Controls. Two planted damages, one per direction, each of which the
# comparator must catch. A comparator that cannot fail is how
# scripts/grammarconvergence.id reported success on a damaged owner.
control=$(mktemp -d "${TMPDIR:-/tmp}/idol.treesitter.literal.XXXXXX") || exit 2
trap 'rm -rf -- "$control"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$control/ext/tree-sitter-idol" "$control/src"
cp "$bridge" "$control/src/grammar_role_table.zig"

# Direction 1: an EXTRA authored identity the owner does not own must fail.
sed 's/^    bytes: \$ => \$\.single_quoted_string,$/    bytes: $ => $.single_quoted_string,\n    xml_blob: $ => $.single_quoted_string,/' \
  "$grammar" >"$control/ext/tree-sitter-idol/grammar.js"
if compare "$control"; then
  broken "a planted EXTRA authored literal identity was not caught"
fi

# Direction 2: a DELETED identity (owner row without a grammar rule) must fail.
sed 's/^    compat_long_text: \$ => \$\.long_string,$//' "$grammar" \
  >"$control/ext/tree-sitter-idol/grammar.js"
if compare "$control"; then
  broken "a planted DELETED owner literal identity was not caught"
fi

# Live comparison.
compare .
printf 'treesitter literal gate: PASS — literal identities are the owner%s quoted rows\n' "'"
