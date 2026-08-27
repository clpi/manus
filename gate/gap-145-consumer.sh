#!/bin/sh
# gate/gap-145-consumer.sh — GAP-145: nothing may hold a second answer about
# what a token IS.
#
# Three classes of observer, one runner:
#
#   (1) QUOTE COLLAPSE.   A consumer that answers `.str` for every `.quoted`
#       has thrown away the producer's text/bytes distinction.
#   (2) DUPLICATE PRODUCER. A host module that classifies quotes, comments,
#       shebang or backtick beside `lib/compiler/lexer.id`.
#   (3) SECOND GRAMMAR AUTHORITY. The tree-sitter grammar is an independently
#       authored operator table. GAP-145's closure bullet allows it to be
#       "generated or mechanically verified from the same grammar/lexical
#       authority". Nothing verified it: the check inside the generator
#       compared against a hand-copied restatement of docs/spec/grammar.md 2 --
#       a file whose own first paragraph says it is not a grammar authority --
#       and compared only ADJACENT rows. Section 3 below compares EVERY PAIR
#       against `src/grammar_role_table.zig`, the generated projection of
#       `lib/compiler/token.id` (law.grammar.one).
#
# Every section positive-controls its own detector. A gate that cannot fail
# reports a number that proves nothing (law.gate.protocol).
set -u

ROOT=${GAP145_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
TYPES="$ROOT/src/types.zig"
SEMA="$ROOT/src/sema.zig"
CODEGEN="$ROOT/src/codegen.zig"
AST="$ROOT/src/ast.zig"
DNIR="$ROOT/src/dnir_lower.zig"
PARSER="$ROOT/src/parser.zig"

violations=0
examined=0

bad() {
    violations=$((violations + 1))
    printf 'gap-145 consumer gate: FAIL %s\n' "$*"
}

has() {
    file=$1
    pattern=$2
    msg=$3
    examined=$((examined + 1))
    if ! grep -Fq "$pattern" "$file"; then
        bad "$msg"
    fi
}

forbid() {
    file=$1
    pattern=$2
    msg=$3
    examined=$((examined + 1))
    if grep -Fq "$pattern" "$file"; then
        bad "$msg"
    fi
}

# ── 1. quote identity reaches the consumers ─────────────────────────────────

has "$AST" 'pub fn quotedLiteralIsByteSequence' \
    'ast.zig lost quotedLiteralIsByteSequence helper'
has "$TYPES" 'pub fn quotedLiteralType' \
    'types.zig lost quotedLiteralType helper'
has "$SEMA" 'types.quotedLiteralType(lit.quote)' \
    'sema.zig must type quoted literals via quotedLiteralType'
has "$CODEGEN" 'types.quotedLiteralType(lit.quote)' \
    'codegen.zig must recover quoted literal types via quotedLiteralType'
has "$DNIR" 'types.quotedLiteralType(lit.quote)' \
    'dnir_lower.zig must type quoted globals via quotedLiteralType'

forbid "$SEMA" '.quoted => .str,' \
    'sema.zig reintroduced bare `.quoted => .str` collapse'
forbid "$CODEGEN" '.quoted => .str,' \
    'codegen.zig reintroduced bare `.quoted => .str` collapse'
forbid "$DNIR" '.quoted => .str,' \
    'dnir_lower.zig reintroduced bare `.quoted => .str` collapse'

# ── 2. one producer of lexical identity ─────────────────────────────────────
#
# `src/lexical_identity.zig` called itself "canonical lexical token identities
# (production source of truth)" and had ZERO consumers, which is exactly why no
# call-graph census ever saw it. Its `classifyQuote` keyed on
# `facts.law` x `facts.provenance`; the producer's `classify_quote` keys on
# `family`. Two answers, and the divergence was invisible only because nothing
# asked. Deleted 2026-08-23. This is the ratchet that keeps it deleted.
examined=$((examined + 1))
if [ -e "$ROOT/src/lexical_identity.zig" ]; then
    bad 'src/lexical_identity.zig is back — one producer owns lexical identity (law.fact.producer.one); it is lib/compiler/lexer.id'
fi

# Source spelling has one owner too. `src/lexer.zig` `spelling()` used to be a
# 60-arm switch falling through to `src/token_semantic.zig`; it now reads the
# generated projection of `lib/compiler/token.id` `kindspell`.
examined=$((examined + 1))
if ! grep -Fq 'grammar_role_table.zig").rows[@intFromEnum(self)].spell' "$ROOT/src/lexer.zig"; then
    bad 'src/lexer.zig spelling() no longer reads the generated owner projection — a second spelling table is back'
fi

# ── 2b. the parser holds no raw-byte delimiter scan (GAP-145 O6) ─────────────
#
# `findMatchingParen` and `interpolationHoleEnd` answered "where does this
# delimiter close?" by walking QUOTED BYTES with a hand-rolled quote-state
# guesser — a second observation of literal structure the producer had already
# produced. Both were deleted 2026-08-26: delimiter extent is now observed over
# the producer pack through `matchingTokenClose` + `token_view.fromLexer`, which
# balances depth on the PRODUCER'S tokens and masks decoded braces the producer
# marked protected.
#
# That deletion was measured, reported, and then left with NOTHING enforcing
# it: this gate held the ceilings on the quote/text/byte surface and never
# refused a raw-byte scan coming back. Every assertion this project has ever
# written down without a runner has decayed; this one had not even the runner.
# A reintroduction in `src/parser.zig` must FAIL here, not merely become
# possible to notice.
#
# The remaining `findMatchingParen` sites (`src/c_frontend.zig`,
# `src/c_header_parse.zig`) are FOREIGN C HEADER INGRESS, upstream of any Idol
# token: there is no producer pack there to observe. They are out of this seam
# and are not counted.
forbid "$PARSER" 'findMatchingParen' \
    'parser.zig reacquired findMatchingParen — delimiter extent belongs to the producer pack (matchingTokenClose), not a raw-byte quote guesser'
forbid "$PARSER" 'interpolationHoleEnd' \
    'parser.zig reacquired interpolationHoleEnd — hole extent belongs to the producer pack, not a raw-byte scan'
has "$PARSER" 'fn matchingTokenClose(' \
    'parser.zig lost matchingTokenClose — the token-view delimiter-extent relation the O6 deletion replaced the raw scans with'
has "$PARSER" 'token_view.fromLexer(' \
    'parser.zig stopped observing delimiter extent through the immutable token view'

# POSITIVE CONTROL ON THE REFUSALS (law.gate.protocol). A `forbid` that cannot
# fail is the `tools/parity/grammar` defect: green for months while matching
# nothing. Plant both retired scans beside the live replacement in a scratch
# parser.zig — the detectors above must convict it, and must NOT convict a
# clean scratch that carries only the replacement.
o6probe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate scratch' >&2; exit 2; }
{
    printf '%s\n' 'fn findMatchingParen(s: []const u8) ?usize { }'
    printf '%s\n' 'fn interpolationHoleEnd(s: []const u8) ?usize { }'
    printf '%s\n' 'fn matchingTokenClose(self: *Parser) ?usize { }'
} >"$o6probe/planted.zig"
: >"$o6probe/clean.zig"
o6_planted=$(grep -cE 'findMatchingParen|interpolationHoleEnd' "$o6probe/planted.zig")
o6_clean=$(grep -cE 'findMatchingParen|interpolationHoleEnd' "$o6probe/clean.zig")
o6_live=$(grep -cE 'fn matchingTokenClose\(' "$o6probe/planted.zig")
rm -rf -- "$o6probe"
examined=$((examined + 1))
if [ "$o6_planted" -ne 2 ] || [ "$o6_clean" -ne 0 ]; then
    bad "the raw-scan detector is broken: 2 planted scanned as $o6_planted, clean as $o6_clean"
elif [ "$o6_live" -ne 1 ]; then
    bad "the replacement detector is broken: matchingTokenClose planted once, counted $o6_live"
fi

# ── 3. tree-sitter agrees with the one grammar-fact owner ───────────────────

python3 - "$ROOT" <<'PY'
import re, sys, os

root = sys.argv[1]

# `~=` and `!=` are ONE producer identity (`neq`, slot 89) with two source
# spellings. `kindspell` carries one field per slot, so the compat spelling has
# no row of its own. Declared here, printed on every run, rather than silently
# skipped -- an unresolved operator must be visible, not absent.
ALIAS = {'~=': '!='}

# Owner infix identities that tree-sitter does NOT render as a
# `binary_expression` row, each with the rule that owns it instead. This is a
# PROJECTION BOUNDARY, not a precedence fact: the owner says these have binding
# power, and the editor grammar spends it somewhere else.
#
# It exists so the check can demand SET EQUALITY. Requiring the tree-sitter set
# to be merely nonempty passed when an operator was DELETED -- drop `^` from
# grammar.js and its generator and the remaining 23 rows still agree with each
# other, so the editor grammar loses exponentiation and the gate says PASS.
# Every owner infix identity must now be in the table or in this list.
EXCLUDED = {
    '=':  'assignment statement, not an expression operator',
    '+=': 'compound assignment statement',
    '-=': 'compound assignment statement',
    '*=': 'compound assignment statement',
    '/=': 'compound assignment statement',
    '%=': 'compound assignment statement',
    '^=': 'compound assignment statement',
    '.':  'field_projection / field_expression',
    '@':  'attribute and world-access rules',
    'not': 'unary_expression',
    '!':  'unary_expression',
}

def owner_rows(path):
    src = open(path).read()
    body = re.search(r'pub const rows = \[slot_count\]RoleRow\{(.*)\n\};', src, re.S).group(1)
    by_spell = {}
    for line in (l for l in body.splitlines() if l.strip().startswith('.{')):
        if '.kind = null' in line:
            continue
        sp = re.search(r'\.spell = "((?:[^"\\]|\\.)*)"', line)
        if not sp or not sp.group(1):
            continue
        prec = re.search(r'\.precedence = (-?\d+)', line)
        asc = re.search(r'\.assoc = \.([a-z]+)', line)
        by_spell[sp.group(1)] = (
            int(prec.group(1)) if prec else 0,
            asc.group(1) if asc else 'none',
        )
    return by_spell

def ts_rows(path):
    src = open(path).read()
    body = re.search(r'binary_expression: \$ => choice\((.*?)\n    \),', src, re.S).group(1)
    out = []
    for m in re.finditer(r"prec\.(left|right)\((\d+), seq\(\$\.expression, '((?:[^'\\]|\\.)*)', \$\.expression\)\)", body):
        out.append((m.group(3), int(m.group(2)), m.group(1)))
    return out

def compare(owner, ts):
    """Returns (problems, pairs, resolved-count). Set equality first, then order."""
    problems = []
    resolved = []
    covered = set()
    for spell, level, side in ts:
        key = ALIAS.get(spell, spell)
        if key not in owner:
            problems.append('tree-sitter operator %r has no identity in the owner projection' % spell)
            continue
        if owner[key][0] == 0:
            problems.append('tree-sitter renders %r as an infix operator; the owner gives it no binding power' % spell)
            continue
        covered.add(key)
        resolved.append((spell, level, side, owner[key][0], owner[key][1]))

    # SET EQUALITY, the half that a nonempty check cannot see.
    infix = {sp for sp, (prec, _) in owner.items() if prec != 0}
    for sp in sorted(infix - covered - set(EXCLUDED)):
        problems.append(
            'owner infix identity %r is MISSING from tree-sitter binary_expression '
            'and is not a declared projection exclusion' % sp)
    for sp in sorted(set(EXCLUDED) - infix):
        problems.append(
            'declared exclusion %r is not an owner infix identity — the exclusion '
            'list has drifted from the owner' % sp)

    pairs = 0
    for i in range(len(resolved)):
        for j in range(i + 1, len(resolved)):
            a, b = resolved[i], resolved[j]
            pairs += 1
            ts_ord = (a[1] > b[1]) - (a[1] < b[1])
            au_ord = (a[3] > b[3]) - (a[3] < b[3])
            if ts_ord != au_ord:
                problems.append(
                    'binding order: %r (ts %d / owner %d) vs %r (ts %d / owner %d)'
                    % (a[0], a[1], a[3], b[0], b[1], b[3]))
    for spell, level, side, prec, asc in resolved:
        # tree-sitter has no nonassoc; `prec.left` is its only rendering of one.
        want = {'left': 'left', 'right': 'right', 'nonassoc': 'left', 'none': 'left'}[asc]
        if side != want:
            problems.append('associativity: %r is prec.%s, owner says %s' % (spell, side, asc))
    return problems, pairs, len(resolved)

owner_path = os.path.join(root, 'src/grammar_role_table.zig')
ts_path = os.path.join(root, 'ext/tree-sitter-idol/grammar.js')
owner = owner_rows(owner_path)
ts = ts_rows(ts_path)
if not ts:
    print('gap-145 consumer gate: FAIL tree-sitter binary_expression yielded 0 operators — '
          'the reader is broken, and a broken reader reports agreement')
    sys.exit(1)

infix_total = len([1 for _, (prec, _) in owner.items() if prec != 0])
problems, pairs, resolved = compare(owner, ts)
print('  owner infix identities: %d = %d rendered + %d declared exclusions'
      % (infix_total, infix_total - len(EXCLUDED), len(EXCLUDED)))
print('  tree-sitter operators: %d, resolved against the owner: %d, pairs compared: %d'
      % (len(ts), resolved, pairs))
print('  declared compat spellings sharing one identity: %s'
      % ', '.join('%s->%s' % kv for kv in sorted(ALIAS.items())))

# POSITIVE CONTROLS. Two, because the two failure modes are independent: a row
# that MOVED and a row that VANISHED. The second one is here because the first
# version of this check had only the nonempty guard, and a deleted operator
# passed it.
planted_move = [(sp, (99 if sp == '..' else lv), a) for (sp, lv, a) in ts]
ctl_move, _, _ = compare(owner, planted_move)
if not any(p.startswith('binding order') for p in ctl_move):
    print('gap-145 consumer gate: FAIL the comparator did not see a planted inversion — '
          'it cannot fail, so its pass means nothing')
    sys.exit(1)

planted_drop = [(sp, lv, a) for (sp, lv, a) in ts if sp != '^']
ctl_drop, _, _ = compare(owner, planted_drop)
if not any(p.startswith('owner infix identity') for p in ctl_drop):
    print("gap-145 consumer gate: FAIL the comparator did not see a planted DELETION of "
          "'^' — an editor grammar can lose an operator and still report agreement")
    sys.exit(1)
print('  positive controls: planted inversion detected (%d finding(s)); '
      'planted deletion of %r detected (%d finding(s))'
      % (len(ctl_move), '^', len(ctl_drop)))

if problems:
    for p in problems:
        print('gap-145 consumer gate: FAIL tree-sitter vs lib/compiler/token.id — %s' % p)
    sys.exit(1)
print('  tree-sitter operator table agrees with lib/compiler/token.id on every pair, '
      'and covers every owner infix identity')
sys.exit(0)
PY
ts_status=$?
examined=$((examined + 1))
if [ "$ts_status" -ne 0 ]; then
    bad 'tree-sitter is a second grammar authority that disagrees with lib/compiler/token.id'
fi

# ── 3b. the quote-blind arm count is a CEILING that falls ───────────────────
#
# 34 `.quoted =>` arms; 12 read the producer quote. The other 22 are mostly
# span, truthiness and emit-side realization and carry no text/byte claim, so
# this is not a demand for zero today. It is a demand that the number not GROW
# while GAP-145 is open, and it is COUNTED on every run rather than asserted in
# a comment, because every count this project wrote down as prose has decayed.
#
# Lower the ceiling as arms are converted. The pattern is
# `src/dnir_lower.zig` `graphTextConst`, which reads `sourceQuoteValue` off the
# graph instead of assuming text. Raising it is the edit that must be argued
# for.
#
# A DISCARD IS NOT AN OBSERVATION. This section was defeated once, measured
# 2026-08-26: 21 blind arms were rewritten as `blk: { _ = s.quote; ... }` — a
# Zig DISCARD that observes nothing — and the observing regex below counted
# every one of them, taking blind from 10 to 0 with zero semantic change. The
# planted control here is that exact shape. An arm observes the producer quote
# only by a route that can answer differently for the two faces.
QUOTE_BLIND_CEILING=15

# 2026-08-27 O5: six text claims in src/codegen.zig stopped guessing the face
# from AST shape and now observe the producer quote via
# `ast.quotedLiteralIsByteSequence(lit.quote)` — fold_meta_string_expr (≈19817),
# metaStringFromExpr (≈20979, ≈20989), deriveNameValueFromExpr (≈21005),
# __comptimefixpoint (≈21253), and the generic emit_expr arm (≈17113, byte face
# now emits an honest commented placeholder instead of a text literal) — taking
# blind 21 → 15. The graph routes (`graphTextConst`/`sourceQuoteValue`) are
# unreachable in codegen: codegen has no graph handle (zero `semantic_graph`
# imports; the deletion witness is the `graphTextConst` prologue at
# src/dnir_lower.zig:2054). The producer-quote observation route was already
# canonical in codegen at 11155/16593/22546 and the fail-closed byte refusal
# follows comptime.zig:451. Lower the ceiling as the remaining face-neutral
# arms (span, truthy, emit, inert, carrier, test, name) are adjudicated away.

armregex='^[[:space:]]*(\.[a-z_, .]*)?\.quoted =>'
arms=$(grep -hE "$armregex" "$ROOT"/src/*.zig | wc -l | tr -d ' ')
# `.quoted` CONTAINS `.quote`, so a naive `grep -c '\.quote'` matches every arm
# and reports 0 blind ones. It did, on the first run of this check. `[^d]` is
# what separates reading the fact from naming the node. Discards `_ = x.quote`
# are STRIPPED before this count — see the block comment above.
observing=$(grep -hE "$armregex" "$ROOT"/src/*.zig \
    | grep -vE '_ = [A-Za-z_][A-Za-z0-9_]*\.quote;' \
    | grep -cE '\.quote[^d]|Quote|graphTextConst|graphByteSequenceConst')
blind=$((arms - observing))
examined=$((examined + 1))
if [ "$arms" -eq 0 ]; then
    bad 'the quoted-arm census matched nothing — a reader that examines zero subjects reports agreement'
else
    printf '  quoted arms: %s, observing the producer quote: %s, blind: %s (ceiling %s)\n' \
        "$arms" "$observing" "$blind" "$QUOTE_BLIND_CEILING"
    if [ "$blind" -gt "$QUOTE_BLIND_CEILING" ]; then
        bad "quote-blind .quoted arms ROSE to $blind, ceiling $QUOTE_BLIND_CEILING"
    fi
fi

# POSITIVE CONTROL ON THE CLASSIFIER (law.gate.protocol). The planted defect is
# the shape that defeated this section, verbatim: a discard that the old
# observing regex counted. Two planted arms, no real observation between them,
# must classify as two BLIND arms — or this census again reports a zero it was
# never given.
ctl=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate scratch' >&2; exit 2; }
{
    printf '%s\n' '        .quoted => |s| blk: { _ = s.quote; break :blk .{ .str = s.val }; },'
    printf '%s\n' '        .quoted => |lit| blk: { _ = lit.quote; break :blk true; },'
    printf '%s\n' '        .quoted => |s| graphTextConst(ctx.graph, expr),'
} >"$ctl/planted.zig"
: >"$ctl/clean.zig"
planted_arms=$(grep -hE "$armregex" "$ctl/planted.zig" | wc -l | tr -d ' ')
planted_obs=$(grep -hE "$armregex" "$ctl/planted.zig" \
    | grep -vE '_ = [A-Za-z_][A-Za-z0-9_]*\.quote;' \
    | grep -cE '\.quote[^d]|Quote|graphTextConst|graphByteSequenceConst')
rm -rf -- "$ctl"
planted_blind=$((planted_arms - planted_obs))
if [ "$planted_arms" -ne 3 ] || [ "$planted_blind" -ne 2 ]; then
    bad "the arm classifier is broken: 3 planted arms counted as $planted_arms, the 2 discard baits as $planted_blind blind — a discard must never count as observing"
elif [ "$planted_obs" -ne 1 ]; then
    bad "the arm classifier no longer recognises the graph route: 1 observing arm counted as $planted_obs"
fi

# A DISCARD OF THE QUOTE FIELD IS BAIT, OUTRIGHT. Stripping discards from the
# observing count (above) closes the ADD-an-arm hole, but rewriting one of the
# 21 existing blind arms as a discard would still pass both §3b (blind stays at
# ceiling) and §3d (the line is stripped). There is no legitimate reason to
# write `_ = x.quote;` inside a `.quoted` arm: the field is either OBSERVED by
# a route that can answer differently for the two faces, or the arm is
# face-neutral and should not mention the field at all. The only use of the
# shape ever measured in this tree was census bait. Zero tolerance, positive
# control below.
baits=$(grep -hE '_ = [A-Za-z_][A-Za-z0-9_]*\.quote;' "$ROOT"/src/*.zig | wc -l | tr -d ' ')
examined=$((examined + 1))
if [ "$baits" -ne 0 ]; then
    bad "$baits .quoted arm(s) DISCARD the quote field ('_ = x.quote;') — a discard observes nothing; read the face or drop the mention"
fi

# ── 3d. DIVERGENT QUOTE ARMS: the zero GAP-145 actually demands ─────────────
#
# §3b counts a SURFACE (blind arms) and §3c counts a FORM (tag tests); neither
# judges a member. The task seam is sharper than both: an arm is DIVERGENT when
# it can answer differently for the text face and the byte face of one quoted
# literal — the class GAP-207 measured printing a pointer at exit 0. Those are
# the arms that must be ZERO while the surface census may stay a ratchet.
#
# A grep cannot judge divergence line-locally, so the judgement lives in an
# allowlist ledger: an arm is divergent unless its line is classified here as
# one of the face-neutral kinds the gap enumerates ("span, truthiness, or
# emit-side realization and carry no text/byte claim"). The ledger is derived
# from the live tree, so a re-classification is a diff you can read, not a
# number you have to trust.
#
# Kinds:
#   observe     the arm asks the producer face (graph/descriptor route)
#   span        the answer is a location; no value law is touched
#   truthy      presence/non-nil law; identical for both faces
#   emit        emit-side realization; the physical carrier is shared by design
#   name        the literal is used as a NAME (identifier), not as a value
#   inert       the arm claims no effect and no value shape
#   carrier     the one deliberate `.str` carrier, adjudicated in GAP-145
#              "What this section does NOT claim"
#   test        inside a unit test, not a consumer decision
DIVERGENT_QUOTE_ARMS=0

divergent=$(grep -hE "$armregex" "$ROOT"/src/*.zig \
    | grep -vE '_ = [A-Za-z_][A-Za-z0-9_]*\.quote;' \
    | grep -vE '\.quote[^d]|Quote|graphTextConst|graphByteSequenceConst' \
    | grep -vE '=> \|(\*?x\| x\.loc,|s\| s\.val,|x\| x\.val,|lit\| lit\.val,)|=> return true,|=> true,|=> \{\},|=> null,|\.str = s\.val \}, // both faces share this carrier|=> \|lit\| \.\{ \.named = lit\.val \},|=> non_numeric_out\.\* = true,|=> \|v\| \{$|=> \{$|=> \|s\| \.\{ \.string = s\.val \},|=> try self\.emit_c_string_literal\(expr\.quoted\.val\),|=> \|\*x\| if \(d\.kind == \.text\) \{$')
examined=$((examined + 1))
divcount=$(printf '%s' "$divergent" | grep -c . )
if [ "$divcount" -ne "$DIVERGENT_QUOTE_ARMS" ]; then
    bad "DIVERGENT quote arms ROSE to $divcount, must be $DIVERGENT_QUOTE_ARMS — classify the new arm in this ledger or convert it to a producer route"
fi
printf '  divergent quote arms: %s (must be %s)\n' "$divcount" "$DIVERGENT_QUOTE_ARMS"

# ── 3c. THE FORM THE ARM CENSUS CANNOT SEE ──────────────────────────────────
#
# Section 3b greps for a SWITCH ARM, `.quoted =>`. A consumer can reach the
# same node through a TAG TEST -- `p.* == .quoted`, `args[0].* == .quoted` --
# and every one of those was invisible to the census that has been reported as
# GAP-145's O5 number since it was first taken.
#
# This is not a hypothetical blind spot. `planConcat` in `src/dnir_lower.zig`
# is written in that form, and it folded the bytes of EVERY quoted part
# straight into a printf format string without asking which face it had:
#
#     print('abc' .. "Z")            answered abcZ   (folded, tag-test site)
#     x = 'abc' .. "Z" ; print(x)    refused         (switch-arm site)
#
# One fact with two answers, and the census that was supposed to be counting
# exactly this class could not see the site that carried it.
#
# WHAT THIS SECTION DOES AND DOES NOT CLAIM. It counts the surface; it does not
# judge each member. Most of these sites read a literal as a NAME -- a concept
# name, a `__emit` template, a field spelling -- where no text/byte law is
# observable, and deciding that line-locally is not something a grep can do
# honestly. So the number is a CEILING on the surface, not a blind count: it
# makes the form visible, which it was not, and refuses growth while GAP-145 is
# open. A site added here has to be argued for by raising the number.
QUOTE_TAGTEST_CEILING=88

tagtests=$(grep -h '== \.quoted\b' "$ROOT"/src/*.zig | wc -l | tr -d ' ')
examined=$((examined + 1))

# POSITIVE CONTROL ON THE COUNTER. The counter is the instrument; a ceiling
# reported by a pattern that matches nothing is the exact defect this whole
# file exists for (`tools/parity/grammar` grepped `ROLEIDENTITYCOUNT` at a file
# that writes `roleidentitycount` and was green for months). Two planted sites
# in a scratch file must be counted as two, and a file with none as none.
tagprobe=$(mktemp -d) || { echo 'gap-145 consumer gate: cannot allocate scratch' >&2; exit 2; }
cat > "$tagprobe/planted.zig" <<'PLANT'
    if (p.* == .quoted) return null;
    const v = if (args[0].* == .quoted) args[0].quoted.val else null;
    if (p.* == .int_lit) return null;
PLANT
: > "$tagprobe/clean.zig"
planted=$(grep -h '== \.quoted\b' "$tagprobe/planted.zig" | wc -l | tr -d ' ')
cleaned=$(grep -h '== \.quoted\b' "$tagprobe/clean.zig" | wc -l | tr -d ' ')
rm -rf -- "$tagprobe"
if [ "$planted" -ne 2 ] || [ "$cleaned" -ne 0 ]; then
    bad "the tag-test counter is broken: planted 2 counted as $planted, empty counted as $cleaned"
elif [ "$tagtests" -eq 0 ]; then
    bad 'the tag-test census matched nothing while its own control counted 2 -- it is reading the wrong tree'
else
    printf '  .quoted tag-test sites: %s (ceiling %s); counter control: 2 planted, 0 in empty\n' \
        "$tagtests" "$QUOTE_TAGTEST_CEILING"
    if [ "$tagtests" -gt "$QUOTE_TAGTEST_CEILING" ]; then
        bad "the .quoted tag-test surface ROSE to $tagtests, ceiling $QUOTE_TAGTEST_CEILING"
    fi
fi

# ── 3e. comment rules are EMITTED, not authored (GAP-145 O1 comments) ───────
#
# §3 closed the operator half of the second-grammar-authority seam. The comment
# half stood open until this section: `tail()` in scripts/treesitter_emit.id
# emitted ONE collapsed Lua `--` comment rule while the tracked grammar.js
# carried three hand-authored GAP-145 identities. The generator disclaimed
# authorship of rules that existed only as hand edits, and nothing compared
# them — the exact shape §3's header describes, one registry later.
#
# Three demands, in order of strength:
#
#   BYTE IDENTITY. The comment rules in the tracked artifact must be the exact
#   rendering of `tail()`'s Comments registry — same lines, same bytes. A hand
#   edit to grammar.js's comment rules, or a generator edit that does not
#   reproduce them, fails here.
#
#   OWNER RESOLUTION. Every comment identity the emission carries must resolve
#   against src/grammar_role_table.zig — the generated projection of
#   lib/compiler/token.id, the one grammar-fact owner (law.grammar.one):
#
#       hash_comment         -> .comment             spell "#",    canonical
#       compat_comment       -> .compat_comment      spell "--",   compat_only
#       compat_long_comment  -> .compat_long_comment spell "--[[", compat_only
#
#   SET EQUALITY both ways: an owner comment identity missing from the emission
#   fails (deleted rule), and an emitted rule with no owner identity fails
#   (invented grammar). The rule-name -> kind mapping is a declared projection
#   boundary, printed on every run, exactly like ALIAS in §3.
#
#   NO COLLAPSE. The emitted union must reference each identity by its own rule
#   name. Re-collapsing to one `token(choice(seq('--', ...)))` rule — the old
#   shape, which folded all three identities into one Lua comment — fails the
#   byte comparison, and this comment says why it must.
#
# Positive controls, both failure modes §3 learned separately: a rule whose
# TEXT moves, and a rule that VANISHES from the tracked artifact.
python3 - "$ROOT" <<'PY'
import re, sys, os

root = sys.argv[1]

# Declared projection boundary: tree-sitter rule name -> owner kind.
COMMENT_ALIAS = {
    'hash_comment': 'comment',
    'compat_comment': 'compat_comment',
    'compat_long_comment': 'compat_long_comment',
}

def unescape(s):
    # .id double-quoted escapes, left to right: \\ -> \, \n -> newline,
    # \' -> ', \" -> ".
    out, i = [], 0
    while i < len(s):
        if s[i] == '\\' and i + 1 < len(s) and s[i+1] in ('\\', 'n', "'", '"'):
            out.append({'\\': '\\', 'n': '\n', "'": "'", '"': '"'}[s[i+1]])
            i += 2
            continue
        out.append(s[i]); i += 1
    return ''.join(out)

def emitted_comment_rules(path):
    """Render tail()'s Comments registry: the b-accumulated lines after the
    'Comments {cbar}' banner line, up to (not including) the '  },' closer."""
    src = open(path).read().split('\n')
    anchors = [n for n, l in enumerate(src) if 'Comments {cbar}' in l]
    if len(anchors) != 1:
        return None, 'found %d "Comments" banner anchors, expected exactly 1' % len(anchors)
    rendered = []
    for l in src[anchors[0]+1:]:
        m = re.match(r'^\s*b = "\{b\}(.*)\\n"$', l)
        if not m:
            break
        rendered.append(unescape(m.group(1)))
    # drop the leading blank line of the section, stop before the closer
    body = [r for r in rendered]
    if body and body[0] == '':
        body = body[1:]
    if '  },' in body:
        body = body[:body.index('  },')]
    return body, None

def tracked_comment_rules(path):
    """The comment rules in grammar.js: from 'comment: $ =>' through the
    terminating \"']')),\" line, byte-exact, comments and all."""
    js = open(path).read().split('\n')
    starts = [n for n, l in enumerate(js) if l.strip().startswith('comment: $ =>')]
    if not starts:
        return None, 'no comment rule in the tracked grammar'
    i = starts[-1]
    ends = [n for n, l in enumerate(js) if n > i and "']'))," in l]
    if not ends:
        return None, 'comment rule in the tracked grammar does not terminate'
    return js[i:ends[0]+1], None

def owner_comment_rows(path):
    src = open(path).read()
    rows = {}
    for m in re.finditer(
            r'\.\{ \.kind = \.([a-z_]*comment[a-z_]*), \.spell = "([^"]*)"(.*?)\},',
            src, re.S):
        kind, spell, rest = m.group(1), m.group(2), m.group(3)
        rows[kind] = (spell, '.compat_only = true' in rest)
    return rows

def compare(gen, tracked, owner):
    problems = []
    if gen != tracked:
        for n in range(max(len(gen), len(tracked))):
            g = gen[n] if n < len(gen) else '<missing>'
            t = tracked[n] if n < len(tracked) else '<missing>'
            if g != t:
                problems.append(
                    'comment rule line %d differs — generator emits %r, '
                    'tracked grammar has %r' % (n, g, t))
                break
        if not problems:
            problems.append('comment rule blocks differ in length: generator %d '
                            'lines, tracked %d' % (len(gen), len(tracked)))
    # identity extraction from the EMITTED block. The union head `comment:` is
    # the query-compatible projection face, not a member identity; members are
    # the $.name references in its choice arms, and DEFINED identities are the
    # 4-space-indented rules that are union members.
    names = set(re.findall(r'\$\.([a-z_]*comment[a-z_]*),', '\n'.join(gen)))
    defined = set(re.findall(r'^\s{4}([a-z_]*comment[a-z_]*): \$ =>', '\n'.join(gen), re.M)) - {'comment'}
    if names != defined:
        problems.append('the comment union references %s but defines %s — a '
                        'referenced identity has no rule, or a rule is unreferenced'
                        % (sorted(names), sorted(defined)))
    owner_family = {k for k in owner if 'comment' in k}
    emitted_kinds = {COMMENT_ALIAS.get(n) for n in defined}
    for n in sorted(defined - set(COMMENT_ALIAS)):
        problems.append('emitted comment rule %r has no declared owner mapping — '
                        'invented grammar or a drifted projection boundary' % n)
    for k in sorted(owner_family - emitted_kinds):
        problems.append('owner comment identity %r is MISSING from the emitted '
                        'comment rules' % k)
    for k in sorted(emitted_kinds - owner_family):
        problems.append('emitted comment rule maps to %r, which the owner '
                        'projection does not carry' % k)
    # spelling and compat facts flow from the owner. compat_long_comment's
    # opener is spelled as three JS literals ('--', '[', '['), so the
    # spell-occurrence needle is the owner spell's first two characters for
    # spells three characters or longer.
    for n, k in sorted(COMMENT_ALIAS.items()):
        if k not in owner:
            continue
        spell, compat = owner[k]
        needle = spell if len(spell) < 3 else spell[:2]
        if needle not in '\n'.join(gen):
            problems.append('owner spell %r for %s does not occur in the emitted '
                            'rules' % (spell, k))
        want_compat = 'compat' in k
        if want_compat and not compat:
            problems.append('owner marks %s canonical, the emission treats it as '
                            'compat' % k)
        if not want_compat and compat:
            problems.append('owner marks %s compat_only, the emission treats it '
                            'as canonical' % k)
    return problems

gen_path = os.path.join(root, 'scripts/treesitter_emit.id')
js_path = os.path.join(root, 'ext/tree-sitter-idol/grammar.js')
owner_path = os.path.join(root, 'src/grammar_role_table.zig')

gen, err = emitted_comment_rules(gen_path)
if err:
    print('gap-145 consumer gate: FAIL comment-emission reader: %s' % err)
    sys.exit(1)
tracked, err = tracked_comment_rules(js_path)
if err:
    print('gap-145 consumer gate: FAIL tracked-comment reader: %s' % err)
    sys.exit(1)
if not gen or not tracked:
    print('gap-145 consumer gate: FAIL a comment reader yielded zero rules — '
          'a broken reader reports agreement')
    sys.exit(1)
owner = owner_comment_rows(owner_path)
if not owner:
    print('gap-145 consumer gate: FAIL owner projection carries no comment rows — '
          'reading the wrong tree')
    sys.exit(1)

problems = compare(gen, tracked, owner)

# POSITIVE CONTROLS. Two, because §3 proved the failure modes are independent:
# text that MOVES and rules that VANISH.
ctl_move = list(gen)
if len(ctl_move) > 6:
    ctl_move[6] = ctl_move[6].replace('prec(-1,', 'prec(-2,')
ctl_move_p = compare(ctl_move, tracked, owner)
if not any(p.startswith('comment rule line') for p in ctl_move_p):
    print('gap-145 consumer gate: FAIL the comment comparator did not see a '
          'planted text move — it cannot fail, so its pass means nothing')
    sys.exit(1)

ctl_drop = [l for l in gen if 'hash_comment' not in l]
ctl_drop_p = compare(ctl_drop, tracked, owner)
if not any('MISSING' in p or 'union references' in p or 'differ' in p for p in ctl_drop_p):
    print("gap-145 consumer gate: FAIL the comment comparator did not see the "
          "planted DELETION of 'hash_comment' — an editor grammar can lose a "
          "comment identity and still report agreement")
    sys.exit(1)

print('  comment rules: generator emission is byte-identical to the tracked '
      'grammar (%d lines)' % len(gen))
print('  comment identities: %s' % ', '.join(
    '%s->%s(%r)' % (n, k, owner[k][0] if k in owner else '?')
    for n, k in sorted(COMMENT_ALIAS.items())))
print('  positive controls: planted text move detected (%d finding(s)); planted '
      'deletion of hash_comment detected (%d finding(s))'
      % (len(ctl_move_p), len(ctl_drop_p)))

if problems:
    for p in problems:
        print('gap-145 consumer gate: FAIL comment authorship — %s' % p)
    sys.exit(1)
sys.exit(0)
PY
cmt_status=$?
examined=$((examined + 1))
if [ "$cmt_status" -ne 0 ]; then
    bad 'tree-sitter comment rules are authored or drifted, not emitted from the lexical owner'
fi

# ── 4. the identity-count parity probe must be able to run ──────────────────

if [ -x "$ROOT/tools/parity/grammar" ] || [ -r "$ROOT/tools/parity/grammar" ]; then
    examined=$((examined + 1))
    if ! sh "$ROOT/tools/parity/grammar" >/dev/null 2>&1; then
        bad 'tools/parity/grammar reports drift between host TokenKind identity and the generated projection'
    fi
fi

if [ "$violations" -eq 0 ]; then
    printf 'gap-145 consumer gate: PASS (%d check(s))\n' "$examined"
    exit 0
fi

printf 'gap-145 consumer gate: FAIL (%d violation(s), %d check(s))\n' "$violations" "$examined"
exit 1
