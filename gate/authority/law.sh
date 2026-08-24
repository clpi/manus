#!/bin/sh
# gate/authority/law.sh -- ONE normalized law identity per fact, across every
# active projection. Two projections that answer the same identity differently
# is the defect; this file finds it mechanically instead of by reading.
#
# SCOPE, stated first so this is not confused with its sibling.
#   `gate/authority.sh` checks that NAMED files carry NAMED sentences: a fixed
#   `contains`/`rejects` list, one string per file. It cannot notice a
#   divergence in a file nobody thought to list, and every new projection page
#   arrives outside it.
#
#   This gate owns the CROSS-FILE side. It extracts a normalized VALUE for each
#   law identity from every active projection and fails when two projections
#   disagree. No file is named as a subject; the subject set is enumerated, so
#   a page added tomorrow is measured tomorrow.
#
# THE INVARIANT
#
#     A law identity has exactly one value. Two projections answering it
#     differently is not a documentation nit -- it is two laws.
#
# `docs/spec/AUTHORITY.md` already routes this: law.md is supreme, the
# constitution is its structured expansion, and everything else is a consumer
# that must agree. What did not exist was an instrument that CHECKED the
# consumers against each other. Measured at 0910d229 before this gate landed,
# with the extractor below:
#
#   law.root                 SPLIT -- 15 active projections named
#                            `docs/spec/constitution.md` as the sole semantic
#                            law while law.md, constitution.md, AUTHORITY.md,
#                            AUTHORITY.json and docs/spec/README.md all named
#                            `docs/spec/law.md`.
#   law.projection.computed  SPLIT -- `docs/spec/roles.md` declared "`[]`
#                            retired; brackets do not select another semantic
#                            operation" and gave computed retrieval to `()`,
#                            against law.md 5, CLAUDE.md, AUTHORITY.json
#                            (`"computed_projection": "[]"`), grammar.md,
#                            source.md, agent.md and canonical.md.
#
# THE IDENTITIES, and how a VALUE is derived
#
#   law.root -- the file a projection names as the top of the law hierarchy.
#     Recognized only where a supremacy phrase is SYNTACTICALLY BOUND to a
#     law-file path, in one of four forms (P1..P4 below). A sentence that says
#     "the sole law" and names no file names no root and cannot diverge, so it
#     is not a subject. Paths normalize by basename: `../spec/law.md`,
#     `[C0](spec/constitution.md)` and `docs/spec/law.md` all reduce to a
#     `docs/spec/*` identity, because a relative prefix is provenance.
#
#   law.projection.computed -- the delimiter face that performs computed or
#     indexed aggregate access. Taken from a delimiter-role declaration (`[]`
#     in role position at the head of a line or list item), from the predicate
#     form ("computed projection is X"), and from AUTHORITY.json's
#     machine-readable `computed_projection` key.
#
# AN UNRECOGNIZED ROLE IS A FINDING, NOT A PASS. The delimiter extractor
# normalizes a role phrase into {computed-projection, retired}; anything else
# is emitted as `UNCLASSIFIED:<phrase>` and fails. A gate whose defect list is
# a fixed set of bad spellings is escaped by the next bad spelling; this one
# has to be TAUGHT a new role before it will accept one.
#
# NON-NEGOTIABLES, from GAP-201/GAP-220 and gate/vacuity.sh:
#   * Subjects come from `gate/subject.sh`, the one fail-closed producer, and
#     its status is asserted OUTSIDE the pipe that consumes it.
#   * ANCHORS below must be present and non-empty. Zero subjects, a missing
#     anchor, or a witness count under its floor exits 3 -- the measurement
#     broke, and a ratchet that stops counting must never report clean.
#   * Every pattern carries a control in BOTH directions before anything real
#     is measured: it must see a planted divergence and decline the lawful
#     face.
#   * The stale-projection negative control runs on every invocation. A copy of
#     the real subject set is mutated -- one projected delimiter rule, one
#     routing sentence, one unteachable role phrase -- and the SAME verdict
#     routine must go red on each while staying green on the unmutated copy.
#     Mutating the copy proves the instrument; editing the gate would prove
#     nothing.
#   * LC_ALL=C. Tracked files carry bytes that abort a UTF-8 scan mid-stream.
#
# EXCLUDED, and named rather than left implicit:
#   * `gaps/**` -- GAP ledgers are dated obligation records, not active law
#     projections, and they are owned by a different lane. `gaps/RESEARCH-
#     SPINE.md` DOES still name the constitution as the sole semantic law; it
#     is a real residue, it is out of this gate's declared scope, and it is
#     recorded here so the hole is visible rather than discovered.
#   * `research/**`, `vendor/**`, `ext/**`, `benchmarks/**`, `out/**` --
#     historical, foreign, or build output. Not active law.
#   * `evidence/**` and the debt registers -- measurement artifacts. They quote
#     delimiters in violation censuses ("[] indexing: 15+ violations"), which
#     is a count, not a role declaration.
#
# USAGE:
#   sh gate/authority/law.sh              controls, controls, then the tree
#   sh gate/authority/law.sh --controls   pattern + stale-projection controls only
set -u
LC_ALL=C
export LC_ALL

prog=authority/law
root=${AUTHORITYLAWROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)}
cd "$root" || exit 3

die()  { printf '%s: REFUSING TO REPORT -- %s\n' "$prog" "$*" >&2; exit 3; }
fail() { viol=$((viol + 1)); printf '  FAIL %s\n' "$*"; }
ok()   { printf '  ok   %s\n' "$*"; }
viol=0

# THE INVOCATION MODE IS READ BEFORE `set --` REPLACES THE ARGUMENT LIST. It
# was read after, so `--controls` was never seen and every run tripped the
# unknown-argument refusal on the first pathspec.
mode=${1:-}

# ---------------------------------------------------------------- subjects --
# The declared active-projection set. Pathspecs, not a file list: a page added
# under docs/spec/ is measured without editing this gate.
set -- \
  AGENTS.md CLAUDE.md README.md \
  'docs/*.md' 'docs/spec/*.md' docs/spec/AUTHORITY.json 'docs/src/*.md' \
  '.agents/*.md' tools/wasm/README.md src/meta_module.zig

# ANCHORS. Each is a projection that MUST answer at least one identity. If one
# vanishes the subject set is no longer the thing this gate was calibrated on,
# and a smaller set agreeing with itself is not the same fact.
ANCHORS='docs/spec/law.md docs/spec/constitution.md docs/spec/AUTHORITY.md docs/spec/AUTHORITY.json docs/spec/README.md docs/spec/roles.md docs/spec/grammar.md docs/spec/source.md docs/spec/canonical.md CLAUDE.md'

# FLOORS. Pinned from the run that landed this gate. Re-derive, do not guess:
#   sh gate/authority/law.sh   # the census line prints both counts
# A count BELOW a floor means the extractor, the pathspecs or the tree broke.
# Above is fine and needs no edit -- projections are expected to multiply.
FLOOR_ROOT=20
FLOOR_COMPUTED=8

[ -r gate/subject.sh ] || die 'subject producer gate/subject.sh is absent'
command -v python3 >/dev/null 2>&1 || die 'python3 is required for identity normalization'

tmp=$(mktemp -d "${TMPDIR:-/tmp}/idolauthlaw.XXXXXX") || die 'mktemp failed'
trap 'rm -rf "$tmp"' EXIT INT TERM

# STATUS OUTSIDE THE PIPE. `sh gate/subject.sh ... > file` then read `$?`;
# a pipeline would report the reader's status and a zero-subject refusal would
# arrive as an empty, clean-looking list.
sh gate/subject.sh "$@" >"$tmp/subjects" 2>"$tmp/subjects.err"
subject_rc=$?
if [ "$subject_rc" -ne 0 ]; then
  sed 's/^/  /' <"$tmp/subjects.err" >&2
  die "gate/subject.sh exited $subject_rc"
fi
[ -s "$tmp/subjects" ] || die 'subject enumeration produced no bytes'

for a in $ANCHORS; do
  grep -Fqx "$a" "$tmp/subjects" || die "anchor '$a' is not in the enumerated subject set"
  [ -s "$a" ] || die "anchor '$a' is missing or empty"
done

# --------------------------------------------------------------- extractor --
cat >"$tmp/identity.py" <<'PYEOF'
"""Normalize law identities out of active projections.

argv: <floor_root> <floor_computed> <file>...
stdout: a census, then one line per identity value with its witnesses.
exit:   0 every identity has exactly one value and clears its floor
        1 an identity is SPLIT, or a role phrase could not be normalized
        3 an identity fell below its floor -- the measurement broke
"""
import os
import re
import sys

# A law-file path, optionally wrapped in a markdown link, backticks, quotes or
# brackets. Only law.md and constitution.md qualify: those are the two tiers
# `docs/spec/AUTHORITY.md` defines, and a claim naming anything else is naming
# a projection, not a root.
PATH = r'(?:\[[^\]\n]{0,80}\]\()?[`\'"\[(]{0,2}((?:[\w.\-]+/)*(?:law|constitution)\.md)'
# A supremacy phrase: sole/supreme/only, then at most three words, then `law`.
SUP = r'(?:sole|supreme|only)(?:\s+\w+){0,3}\s+law'

# P1  "the sole semantic law is <path>"      (prose routing, and the `law:` form)
# P2  "<path> is the sole supreme compact law"
# P3  "<path> -- supreme compact law"        (router tables; the dash binds)
# P4  law.md's own self-declaration, which names no path because it IS the path
P1 = re.compile(SUP + r'(?:\s+is|:)\s*' + PATH, re.I)
P2 = re.compile(PATH + r'[`\'")\]]{0,3}(?:\([^)]*\))?[`\'")\]]{0,3}\s+is\s+(?:the\s+)?\**' + SUP, re.I)
P3 = re.compile(PATH + r'[`\'")\]]{0,3}\s*[—-]\s*\**(?:sole|supreme)(?:\s+\w+){0,3}\s+law', re.I)
P4 = re.compile(r'This is the \*\*sole supreme compact law\*\*')

# `[]` in ROLE POSITION: head of a line, or head of a list item. Anywhere else
# it is being quoted, not declared -- `## 8. `.get` / `[]` host rule` is a
# heading and `reinterpret `()` as `[]`` is a prohibition.
BRACKET_ROLE = re.compile(r'^\s{0,4}(?:[-*]\s+)?(?:`\[\]`|\[\])\s+(?:is\s+)?\**([A-Za-z][A-Za-z/ -]{2,44})')
# ... but a COUNT is not a ROLE. `[] indexing: 15+ violations` is a census row
# in an evidence bundle; the word after the delimiter is the thing being
# counted, not the role being declared. Out of the declared scope today, and
# declined here so widening the scope does not manufacture a finding.
BRACKET_CENSUS = re.compile(r'^\s{0,4}(?:[-*]\s+)?(?:`\[\]`|\[\])\s+[A-Za-z][A-Za-z/ -]{0,44}:\s*\d')
# The predicate form, which states the delimiter rather than the role.
PRED = re.compile(
    r'computed(?:/indexed| or indexed| and indexed)?\s+(?:aggregate\s+)?'
    r'(?:access|projection)\s+is\s+\**([^.;\n]{3,60})', re.I)
# The machine-readable key in docs/spec/AUTHORITY.json.
JSONKEY = re.compile(r'"computed_projection"\s*:\s*"([^"]*)"')

ROOT = 'law.root'
COMPUTED = 'law.projection.computed'


def norm_path(p):
    # Basename normalization. A relative prefix is provenance, not identity.
    return 'docs/spec/' + os.path.basename(p)


def classify_role(role):
    role = role.lower()
    if 'computed' in role or 'indexed' in role:
        return '[]'
    if 'retired' in role or 'removed' in role or role.startswith('not '):
        return '()'
    return 'UNCLASSIFIED:' + ' '.join(role.split())


def facts(path, text):
    out = []
    flat = re.sub(r'\s+', ' ', text)
    if P4.search(flat):
        out.append((ROOT, norm_path(path)))
    for rx in (P1, P2, P3):
        for m in rx.finditer(flat):
            out.append((ROOT, norm_path(m.group(1))))
    for line in text.splitlines():
        if BRACKET_CENSUS.match(line):
            continue
        m = BRACKET_ROLE.match(line)
        if m:
            out.append((COMPUTED, classify_role(m.group(1))))
    for m in PRED.finditer(flat):
        tail = m.group(1).lower()
        if '[' in tail:
            out.append((COMPUTED, '[]'))
        elif 'ordinary application' in tail or '(' in tail:
            out.append((COMPUTED, '()'))
    for m in JSONKEY.finditer(text):
        out.append((COMPUTED, m.group(1)))
    return out


def probe(path):
    with open(path, encoding='utf-8', errors='replace') as fh:
        out = facts(path, fh.read())
    print(';'.join('%s=%s' % (i, v) for i, v in out) or '-')
    return 0


def main(argv):
    if argv and argv[0] == '--facts':
        return probe(argv[1])
    floors = {ROOT: int(argv[0]), COMPUTED: int(argv[1])}
    rows = {}
    read = 0
    for f in argv[2:]:
        try:
            with open(f, encoding='utf-8', errors='replace') as fh:
                text = fh.read()
        except OSError as exc:
            print('  FAIL unreadable subject %s: %s' % (f, exc))
            return 3
        read += 1
        for ident, val in facts(f, text):
            rows.setdefault(ident, {}).setdefault(val, set()).add(f)
    if read == 0:
        print('  FAIL zero subjects read')
        return 3

    rc = 0
    for ident in sorted(floors):
        values = rows.get(ident, {})
        witnesses = sorted({f for fs in values.values() for f in fs})
        print('  census %-24s %d witnesses, %d distinct value(s)'
              % (ident, len(witnesses), len(values)))
        if len(witnesses) < floors[ident]:
            print('  FAIL %s: %d witnesses is BELOW the pinned floor of %d -- the '
                  'extractor, the pathspecs or the tree broke; a ratchet that stops '
                  'counting must never report clean'
                  % (ident, len(witnesses), floors[ident]))
            rc = 3
            continue
        bad = [v for v in values if v.startswith('UNCLASSIFIED:')]
        for v in sorted(bad):
            print('  FAIL %s: role phrase not in the normalization vocabulary -- [%s] in %s'
                  % (ident, v.split(':', 1)[1], ' '.join(sorted(values[v]))))
            rc = rc or 1
        if len(values) > 1:
            print('  FAIL %s is SPLIT across %d values:' % (ident, len(values)))
            for v in sorted(values):
                print('       %-28s %s' % (v, ' '.join(sorted(values[v]))))
            rc = rc or 1
        elif not bad:
            (only,) = list(values)
            print('  ok   %-24s = %-26s agreed by %d projections'
                  % (ident, only, len(witnesses)))
    return rc


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
PYEOF

# THE EXIT STATUS IS THE ANSWER, so nothing may launder it. This read
# `xargs python3 ... <list`, and xargs maps EVERY status in 1..125 to 123 --
# SPLIT (1) and MEASUREMENT-BROKE (3) would have arrived as the same number,
# and the stale controls below distinguish exactly those. LAW-ONE forbids a
# space in a tracked path, so unquoted word splitting is exact here.
verdict() {
  # $1 tree to measure in, $2 subject-list file, $3 root floor, $4 computed floor
  ( cd "$1" && python3 "$tmp/identity.py" "$3" "$4" $(cat "$2") )
}

# ------------------------------------------------------- pattern controls --
# Synthetic pages with a KNOWN answer, run before anything real is measured. A
# pattern that cannot be shown to see its defect and decline its lawful face is
# not measuring.
printf '%s: pattern controls\n' "$prog"
ctl="$tmp/ctl"
probe() {
  # $1 label, $2 expected `IDENT=VALUE;...` or `-` for no fact, $3 file body
  rm -rf "$ctl"; mkdir -p "$ctl/docs/spec"
  printf '%s\n' "$3" >"$ctl/docs/spec/probe.md"
  got=$(cd "$ctl" && python3 "$tmp/identity.py" --facts docs/spec/probe.md) || {
    fail "control $1: extractor crashed"; return
  }
  if [ "$got" != "$2" ]; then
    fail "control $1: expected [$2], extractor said [$got]"
  fi
}

probe root/prose   'law.root=docs/spec/law.md' \
  'The supreme law is [`docs/spec/law.md`](law.md); the rest are projections.'
probe root/stale   'law.root=docs/spec/constitution.md' \
  'The sole semantic law is [`docs/spec/constitution.md`](constitution.md).'
probe root/relative 'law.root=docs/spec/law.md' \
  'The sole law is [`docs/spec/law.md`](../spec/law.md), and canonical source uses `.id`.'
probe root/c-zero  'law.root=docs/spec/constitution.md' \
  'The sole semantic law is [C0](spec/constitution.md).'
probe root/predicate 'law.root=docs/spec/law.md' \
  '`docs/spec/law.md` is the **sole supreme compact law**.'
probe root/router  'law.root=docs/spec/law.md' \
  '1. `docs/spec/law.md` — supreme compact law.'
probe root/self    'law.root=docs/spec/probe.md' \
  'This is the **sole supreme compact law** of Idol. It governs the active tree.'
probe root/unnamed '-' \
  'It routes to the sole law, this priority projection, and live ownership.'
probe root/expansion '-' \
  '`docs/spec/constitution.md` — structured expansion and stable `law.*` identity owner.'
probe root/authority '-' \
  '`clpi/idol` `main` is the sole living semantic authority for Idol.'

probe computed/table  'law.projection.computed=[]' \
  '[]  computed or indexed projection'
probe computed/bullet 'law.projection.computed=[]' \
  '- `[]` computed/indexed projection;'
probe computed/stale  'law.projection.computed=()' \
  '- `[]` retired; brackets do not select another semantic operation;'
probe computed/pred   'law.projection.computed=[]' \
  'Canonical computed projection is indexed projection: `table[key]`.'
probe computed/callform 'law.projection.computed=()' \
  'Canonical computed projection is ordinary application: `table(key)`.'
probe computed/unknown 'law.projection.computed=UNCLASSIFIED:bracket sugar for host arrays' \
  '- `[]` bracket sugar for host arrays;'
probe computed/heading '-' \
  '## 8. `.get` / `[]` host rule'
probe computed/quoted  '-' \
  'It explicitly **does not** reinterpret `()` as `[]` or use type_map for semantics.'
probe computed/census  '-' \
  '[] indexing: 15+ violations (string-indexed dispatch tables)'

[ "$viol" -eq 0 ] || { printf '%s: PATTERN CONTROLS FAILED (%d)\n' "$prog" "$viol" >&2; exit 3; }
ok '19 pattern controls: every form is seen, every lawful face declined'

# -------------------------------------------- stale-projection controls --
# THE POINT OF THE WHOLE FILE. The verdict routine is run against a small tree
# this gate WRITES, in which one projection page is then deliberately made
# stale -- a projected delimiter rule, a routing sentence, an unteachable role
# phrase -- and it must go RED on each while staying GREEN on the same tree
# undamaged. Damaging the subject proves the instrument; editing the gate would
# prove nothing.
#
# THE CONTROL TREE IS SYNTHETIC, AND THAT IS DELIBERATE. The first version
# mirrored the REAL subject set and mutated `docs/spec/roles.md` in the copy by
# matching its current wording. Measured: damaging that line in the real tree
# then made the CONTROL's anchor vanish, so the gate exited 3 "anchor absent"
# instead of 1 "law.projection.computed is SPLIT" -- red for the wrong reason,
# naming the wrong file. A control whose meaning depends on the state of the
# thing under test is not a control. This tree is written from scratch on every
# run, so each case means exactly one thing forever, and the real corpus is
# measured separately below where a SPLIT is reported as a SPLIT.
printf '%s: stale-projection controls\n' "$prog"
ct="$tmp/ctltree"
rm -rf "$ct"; mkdir -p "$ct/docs/spec"
cat >"$ct/docs/spec/law.md" <<'EOF'
# Idol — supreme compact law

This is the **sole supreme compact law** of Idol. It governs the active tree.

```text
[]  computed or indexed projection
```
EOF
cat >"$ct/docs/spec/constitution.md" <<'EOF'
# Idol constitution projection

`docs/spec/law.md` is the **sole supreme compact law**. This file is its
structured long-form expansion.
EOF
cat >"$ct/CLAUDE.md" <<'EOF'
# operative projection

1. `docs/spec/law.md` — supreme compact law.
- `[]` computed/indexed projection;
EOF
printf 'docs/spec/law.md\ndocs/spec/constitution.md\nCLAUDE.md\ndocs/spec/roles.md\n' >"$tmp/ctl.list"
CTL_FLOOR_ROOT=3
CTL_FLOOR_COMPUTED=2

write_target() {
  # $1 the routing sentence, $2 the delimiter role line
  cat >"$ct/docs/spec/roles.md" <<EOF
# Idol grammar-role projection

$1

Current delimiter roles remain:

$2
EOF
}
LAWFUL_ROUTE='The supreme law is [`docs/spec/law.md`](law.md).'
LAWFUL_DELIM='- `[]` computed or indexed projection;'

stale_case() {
  # $1 label, $2 want-rc, $3 routing sentence, $4 delimiter line,
  # $5 root floor, $6 computed floor
  write_target "$3" "$4"
  out=$(verdict "$ct" "$tmp/ctl.list" "$5" "$6" 2>&1)
  rc=$?
  if [ "$rc" -ne "$2" ]; then
    fail "stale control $1: expected exit $2, got $rc"
    printf '%s\n' "$out" | sed 's/^/       /'
  else
    ok "stale control $1 -> exit $rc"
  fi
}

stale_case undamaged  0 "$LAWFUL_ROUTE" "$LAWFUL_DELIM" "$CTL_FLOOR_ROOT" "$CTL_FLOOR_COMPUTED"
stale_case delimiter  1 "$LAWFUL_ROUTE" \
  '- `[]` retired; brackets do not select another semantic operation;' \
  "$CTL_FLOOR_ROOT" "$CTL_FLOOR_COMPUTED"
stale_case routing    1 \
  'The sole semantic law is [`docs/spec/constitution.md`](constitution.md).' \
  "$LAWFUL_DELIM" "$CTL_FLOOR_ROOT" "$CTL_FLOOR_COMPUTED"
stale_case vocabulary 1 "$LAWFUL_ROUTE" '- `[]` bracket sugar for host arrays;' \
  "$CTL_FLOOR_ROOT" "$CTL_FLOOR_COMPUTED"
# THE FLOOR IS A CONTROL TOO. A witness count that silently collapses to two
# agreeing pages is the vacuity shape this repository keeps catching, so the
# floor is shown to bite on a tree that is otherwise perfectly consistent.
stale_case floor      3 "$LAWFUL_ROUTE" "$LAWFUL_DELIM" 99 99

[ "$viol" -eq 0 ] || { printf '%s: STALE-PROJECTION CONTROLS FAILED (%d)\n' "$prog" "$viol" >&2; exit 3; }
ok 'the gate discriminates: green undamaged, red on each stale projection and on a collapsed floor'

case "$mode" in
  --controls) printf '%s: controls only, tree not measured\n' "$prog"; exit 0 ;;
  '') : ;;
  *) die "unknown argument: $mode" ;;
esac

# ------------------------------------------------------------- the tree --
printf '%s: active projections (%d subjects)\n' "$prog" "$(wc -l <"$tmp/subjects" | tr -d ' ')"
verdict "$root" "$tmp/subjects" "$FLOOR_ROOT" "$FLOOR_COMPUTED"
tree_rc=$?
case "$tree_rc" in
  0) printf '%s: PASS\n' "$prog"; exit 0 ;;
  3) printf '%s: REFUSING TO REPORT -- the measurement broke\n' "$prog" >&2; exit 3 ;;
  *) printf '%s: FAIL -- active projections disagree\n' "$prog" >&2; exit 1 ;;
esac
