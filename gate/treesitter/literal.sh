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
#      literal identity, no silent recognition hole; and
#   3. the `number` union is exactly the owner's non-quoted literal rows
#      (`.literal_kind = true` without `.quoted`), spelling-for-spelling; and
#   4. the keyword literal spellings — `nil`, `boolean` and the
#      `literal_pattern` members — are exactly the bridge's `.spell` values
#      for kw_nil / kw_true / kw_false; and
#   5. the EMITTER still derives all of it from the bridge — the four
#      registries exist, the bridge-row needle is built by interpolation,
#      and no hand-typed spelling literal has returned. Matching bytes in
#      grammar.js are derivation, not coincidence.
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
try:
    emitter_src = open(f"{root}/scripts/treesitter_emit.id").read()
except FileNotFoundError:
    emitter_src = None

# Owner side: one (spell, kind) per quoted row, in row order; and the
# non-quoted literal rows (.literal_kind = true without .quoted) separately.
owner = []
numeric = []
for row in bridge.split("\n"):
    km = re.search(r'\.kind = \.(\w+),', row)
    sm = re.search(r'\.spell = "([^"]+)"', row)
    if ".quoted = true" in row:
        if not km or not sm:
            print(f"FAIL-PARSE bridge row lacks kind/spell: {row.strip()}")
            sys.exit(1)
        owner.append((sm.group(1), km.group(1)))
    elif ".literal_kind = true" in row:
        if not km or not sm:
            print(f"FAIL-PARSE bridge row lacks kind/spell: {row.strip()}")
            sys.exit(1)
        numeric.append((sm.group(1), km.group(1)))

numeric_physical = {
    "int_lit": "integer",
    "float_lit": "float",
}

def kw_spell(kind):
    needle = f".kind = .{kind},"
    for row in bridge.split("\n"):
        if needle in row:
            sm = re.search(r'\.spell = "([^"]+)"', row)
            if not sm:
                print(f"FAIL-PARSE bridge row lacks .spell: {row.strip()}")
                sys.exit(1)
            return sm.group(1)
    print(f"FAIL-PARSE bridge has no row for kind {kind}")
    sys.exit(1)

kw_nil = kw_spell("kw_nil")
kw_true = kw_spell("kw_true")
kw_false = kw_spell("kw_false")

physical = {
    "text_lit": "double_quoted_string",
    "bytes_lit": "single_quoted_string",
    "compat_text_lit": "single_quoted_string",
    "compat_long_text_lit": "long_string",
}

# Emitter side (GAP-145 O1, derivation witness): tracked grammar.js matching
# the bridge is not enough — the EMITTER must still DERIVE those bytes from
# the bridge. If any registry was reverted to a hand-typed literal, authorship
# silently moved back even with matching bytes.
emitter_errors = []
if emitter_src is None:
    emitter_errors.append("emitter scripts/treesitter_emit.id is missing")
else:
    for needle in ("identities: str = ()", "numerics: str = ()",
                   "spell: str = (kind: str)", "literalpattern: str = ()"):
        if needle not in emitter_src:
            emitter_errors.append(
                f"emitter lacks the {needle.split(':')[0]} registry — "
                "literal authorship reverted to hand-typing")
    # The bridge-row needle must be BUILT, not spelled: the emitter constructs
    # `.kind = .{kind},` by interpolation. Its absence means kinds stopped
    # being read from the bridge.
    if '".kind = .{kind},"' not in emitter_src:
        emitter_errors.append(
            'emitter no longer builds the bridge-row needle ".kind = .{kind}," '
            "— kinds are no longer read from the bridge")
    # Each registry's BODY must still read its bridge row-facts. A gutted
    # registry — declaration kept, row-filters stripped — derives nothing;
    # scoping the needles to each registry's body catches that revert.
    registry_bodies = {}
    for reg in ("identities", "numerics", "spell", "literalpattern"):
        m = re.search(rf"^{reg}: str = \((?:kind: str)?\)\n((?:    .*\n|\n)+?)^\S", emitter_src, re.M)
        registry_bodies[reg] = m.group(1) if m else ""
    required_needles = {
        "identities": ('".quoted = true"', 'row:find(".spell = \\"")'),
        "numerics": ('".literal_kind = true"', '".quoted = true"'),
        "spell": ('".kind = .{kind},"', 'row:find(".spell = \\"")'),
        "literalpattern": ('".pattern = true"', '".literal_kind = true"',
                           '".keyword = true"', 'row:find(".spell = \\"")'),
    }
    for reg, needles in required_needles.items():
        body = registry_bodies[reg]
        if not body:
            emitter_errors.append(
                f"emitter registry `{reg}` has no body to read the bridge with")
        for needle in needles:
            if needle not in body:
                emitter_errors.append(
                    f"emitter registry `{reg}` no longer reads the bridge "
                    f"row-fact {needle} — its rows would be hand-chosen")
    # A hand-typed spelling literal must NOT appear: tokens() interpolates
    # '{nilspell}' / '{truespell}' / '{falsespell}'. The raw spelled forms
    # below can only appear if hand-typing returned.
    for typed in ("    nil: $ => 'nil',", "    boolean: $ => choice('true', 'false'),"):
        if typed in emitter_src:
            emitter_errors.append(
                f"emitter hand-types the literal spelling `{typed.strip()}` "
                "— spellings must be read from the bridge (.spell rows)")

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

# Numeric half: the `number` union must be exactly the owner's non-quoted
# literal rows, spelling-for-spelling and in row order.
number_union = re.search(
    r'^    number: \$ => choice\(\n((?:      \$\.\w+,\n)+)    \),$',
    grammar, re.M)
if not number_union:
    errors.append("grammar.js has no `number: $ => choice(...)` union over owner numeric rows")
else:
    number_members = re.findall(r'\$\.(\w+),', number_union.group(1))
    owner_number_rules = [numeric_physical.get(k, f"<unmapped kind {k}>") for _, k in numeric]
    if number_members != owner_number_rules:
        errors.append(
            f"`number` union members {number_members} are not exactly the owner's "
            f"numeric rows {owner_number_rules}")
    if not re.search(r'// GAP-145 O1: numeric literal identities are not authored here',
                     grammar):
        errors.append("grammar.js lacks the GAP-145 O1 numeric identity marker")

# Keyword literal spellings: nil / boolean / literal_pattern must read the
# bridge's kw_nil/kw_true/kw_false .spell values, character for character.
if f"    nil: $ => '{kw_nil}'," not in grammar:
    errors.append(f"`nil` rule does not spell the owner's kw_nil .spell `{kw_nil}`")
if f"    boolean: $ => choice('{kw_true}', '{kw_false}')," not in grammar:
    errors.append(
        f"`boolean` rule does not spell the owner's kw_true/kw_false .spell "
        f"`{kw_true}`/`{kw_false}`")
lp = re.search(
    r'^    literal_pattern: \$ => choice\(\n(?:      .*\n)+?    \),$',
    grammar, re.M)
if not lp:
    errors.append("grammar.js has no `literal_pattern` rule")
else:
    # GAP-145 O1: the whole membership — members AND their order — is the
    # owner's `.pattern` literal/keyword row sequence, not a set to re-choose.
    expected = []
    number_emitted = string_emitted = False
    for row in bridge.split("\n"):
        if ".pattern = true" not in row:
            continue
        if ".literal_kind = true" in row:
            if ".quoted = true" in row:
                if not string_emitted:
                    expected.append("      $.string,")
                    string_emitted = True
            else:
                if not number_emitted:
                    expected.append("      $.number,")
                    number_emitted = True
        elif ".keyword = true" in row:
            sm = re.search(r'\.spell = "([^"]+)"', row)
            if not sm:
                print(f"FAIL-PARSE keyword pattern row lacks .spell: {row.strip()}")
                sys.exit(1)
            expected.append(f"      '{sm.group(1)}',")
    body_lines = lp.group(0).split("\n")
    got = body_lines[1:-1]
    if got != expected:
        errors.append(
            f"`literal_pattern` members {got} are not exactly the owner's "
            f"pattern rows in order {expected}")

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

errors.extend(emitter_errors)

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

mkdir -p "$control/ext/tree-sitter-idol" "$control/src" "$control/scripts"
cp "$bridge" "$control/src/grammar_role_table.zig"
cp "$emitter" "$control/scripts/treesitter_emit.id"

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

# Direction 3: an authored NUMERIC union member the owner does not own.
sed 's/^      \$\.float,$/      $.float,\n      $.xml_number,/' "$grammar" \
  >"$control/ext/tree-sitter-idol/grammar.js"
if compare "$control"; then
  broken "a planted EXTRA numeric union member was not caught"
fi

# Direction 4: a DELETED numeric row (owner row missing from the union).
sed 's/^      \$\.integer,$//' "$grammar" \
  >"$control/ext/tree-sitter-idol/grammar.js"
if compare "$control"; then
  broken "a planted DELETED numeric union member was not caught"
fi

# Direction 5: a hand-edited keyword spelling the owner does not spell.
sed "s/^    nil: \$ => 'nil',$/    nil: \$ => 'null',/" "$grammar" \
  >"$control/ext/tree-sitter-idol/grammar.js"
if compare "$control"; then
  broken "a planted WRONG keyword spelling (nil -> null) was not caught"
fi

# Direction 6: a deleted literal_pattern member.
sed "s/^      'false',$//" "$grammar" \
  >"$control/ext/tree-sitter-idol/grammar.js"
if compare "$control"; then
  broken "a planted DELETED literal_pattern member was not caught"
fi

# Direction 7: derivation, not coincidence — the EMITTER must read the
# bridge, not type literal facts. Each revert below must fail the gate even
# while the tracked grammar.js bytes still match the owner. The comparator
# loads scripts/treesitter_emit.id under its root, so each control rewrites
# the COPY only.
for needle in "literalpattern: str = ()" "identities: str = ()" "numerics: str = ()" "spell: str = (kind: str)"; do
  sed "s/^${needle}\$/REVERTED (planted for control)/" "$emitter" \
    >"$control/scripts/treesitter_emit.id"
  cp "$grammar" "$control/ext/tree-sitter-idol/grammar.js"
  if compare "$control"; then
    broken "a planted REVERTED registry ($needle) in the emitter was not caught"
  fi
done

# Direction 8: the bridge-row needle construction itself reverted.
sed 's/".kind = .{kind},"/"REVERTED"/' "$emitter" \
  >"$control/scripts/treesitter_emit.id"
cp "$grammar" "$control/ext/tree-sitter-idol/grammar.js"
if compare "$control"; then
  broken "a planted REVERTED bridge-row needle in the emitter was not caught"
fi

# Direction 9: spellings hand-typed again in the emitter (interpolation
# replaced by literals) while grammar.js bytes still match.
sed "s/'{nilspell}'/'nil'/; s/'{truespell}', '{falsespell}'/'true', 'false'/" "$emitter" \
  >"$control/scripts/treesitter_emit.id"
cp "$grammar" "$control/ext/tree-sitter-idol/grammar.js"
if compare "$control"; then
  broken "planted HAND-TYPED spellings in the emitter were not caught"
fi

# Live comparison.
compare .
printf 'treesitter literal gate: PASS — literal identities are the owner%s quoted rows\n' "'"
