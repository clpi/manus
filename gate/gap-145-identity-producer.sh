#!/bin/sh
# gate/gap-145-identity-producer.sh — GAP-145: one producer owns token identity
# (law.fact.producer.one). It is lib/compiler/token.id via its generated
# projection src/grammar_role_table.zig. A host module may not carry a second
# spelling -> token identity table, and a deleted one may not come back.
#
# Deletion history, the two named specimens, and why a call-graph census cannot
# see a zero-consumer producer: gaps/GAP-145.md. Not repeated here.
#
# The gate refuses the CLASS (law.repair.class), so its predicate is a ROW
# recognised by shape: a brace group carrying a text literal beside an owner
# IDENTITY at its own nesting level. The identity side is a name the owner
# declares, read from its projection, not the `.kw_` spelling that name happens
# to wear — a prefix is a spelling, and matching a row by a spelling is the
# drift this gate has already been repaired for five times. So the identity is
# recognised as `.name`, as a bare `name`, and inside a text literal that spells
# it, which is how a row reconstructs identity from source text.
# `;` and `=>` disqualify it, because they
# are what separates a row from a BLOCK — a function body, a test, a switch
# prong all name identities and hold strings, and reporting those reports the
# ordinary consumers this tree is made of. A group enclosing a row is the list,
# not a further row. Section 6 plants every shape this replaces, so the shapes
# it refuses are enumerated by the controls that run, not here.
#
# The owner's generated projection is admitted BY PATH; a copy of its rows
# anywhere else is a second producer.
#
# Two boundaries the row predicate does NOT cross, both blocks by that test. A
# classifier answering from statements (`if (eql(s, "while")) return .kw_while;`)
# is not reported. Neither is a row holding its identities one group down:
# src/lexer_differential.zig pairs a `.source` string with an `.expected` token
# STREAM, which is an expectation oracle for the owner rather than a second
# answer about what a keyword is.
#
# Every detector is positive-controlled against planted shapes before any PASS,
# and a run that is not bound to a real candidate tree is a FAIL, not a zero
# (law.gate.protocol).
set -u

ROOT=${GAP145_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
SRC="$ROOT/src"
OWNERID="$ROOT/lib/compiler/token.id"
OWNERPROJ="src/grammar_role_table.zig"
CLASSIFIER="src/token_classify_gen.zig"

violations=0
examined=0
controlled=0

bad() {
    violations=$((violations + 1))
    printf 'gap-145 identity-producer gate: FAIL %s\n' "$*"
}

# A control that could not be BUILT proves nothing, so the step it stands in
# for is unknown rather than clean. Leaving early is therefore a violation and
# never a shortcut to the verdict.
cannot() {
    bad "$*"
    report
}

report() {
    if [ "$violations" -eq 0 ] && [ "$controlled" -ne 1 ]; then
        bad "a verdict was reached before section 6 ran — an uncontrolled run is not a clean tree"
    fi
    if [ "$violations" -eq 0 ]; then
        printf 'gap-145 identity-producer gate: PASS (%d check(s))\n' "$examined"
        exit 0
    fi
    printf 'gap-145 identity-producer gate: FAIL (%d violation(s), %d check(s))\n' \
        "$violations" "$examined"
    exit 1
}

scratch=$(mktemp -d) || {
    echo 'gap-145 identity-producer gate: cannot allocate scratch' >&2
    exit 2
}
trap 'rm -rf -- "$scratch"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# ── the row scanner ─────────────────────────────────────────────────────────
#
# Reads a list of unit paths and prints one line per unit, in list order: the
# row count, or `?` when that unit's structure could not be established. A unit
# whose braces do not balance after comments and literals are consumed is `?`,
# never 0 — the scanner reports what it proved, not what it hopes.

cat >"$scratch/row.awk" <<'ROWAWK'
function enter() { depth++; q[depth] = 0; k[depth] = 0; sc[depth] = 0; ch[depth] = 0 }

function leave(   qual) {
    if (depth < 1) { bad = 1; return 0 }
    qual = (q[depth] && k[depth] && !sc[depth] && !ch[depth])
    if (qual) count++
    if (depth > 1 && (qual || ch[depth])) ch[depth - 1] = 1
    depth--
    return 1
}

# One left-to-right pass. Comments and literals are consumed where they start,
# so a brace, a quote or a `.kw_` inside either cannot reach the row state.
# A text literal that spells one of the owner's identities is that identity
# being named through source text, not a keyword's spelling.
function text(s) {
    if (depth < 1) return
    if (s in id) k[depth] = 1
    else q[depth] = 1
}

function scan(line,   L, i, j, c, d, s) {
    L = length(line)
    for (i = 1; i <= L; i++) {
        c = substr(line, i, 1)
        if (c == "/") { if (substr(line, i + 1, 1) == "/") return }
        else if (c == "\\") {
            if (substr(line, i + 1, 1) == "\\") {
                s = substr(line, i + 2)
                sub(/^[ \t]+/, "", s)
                sub(/[ \t\r]+$/, "", s)
                text(s)
                return
            }
        }
        else if (c == "\"" || c == "'") {
            s = ""
            for (i++; i <= L; i++) {
                d = substr(line, i, 1)
                if (d == "\\") { s = s d substr(line, i + 1, 1); i++ }
                else if (d == c) break
                else s = s d
            }
            if (c == "\"") text(s)
        }
        else if (c == "{") enter()
        else if (c == "}") { if (!leave()) return }
        else if (c == ";") { if (depth > 0) sc[depth] = 1 }
        else if (c == "=") { if (substr(line, i + 1, 1) == ">" && depth > 0) sc[depth] = 1 }
        else if (c ~ /[A-Za-z_]/) {
            for (j = i + 1; j <= L && substr(line, j, 1) ~ /[A-Za-z0-9_]/; j++) ;
            if (depth > 0 && (substr(line, i, j - i) in id)) k[depth] = 1
            i = j - 1
        }
    }
}

BEGIN {
    idfile = ARGV[1]
    listfile = ARGV[2]
    ARGV[1] = ""
    ARGV[2] = ""
    while ((getline w < idfile) > 0) if (w != "") id[w] = 1
    close(idfile)
    while ((getline unit < listfile) > 0) {
        count = 0; depth = 0; bad = 0; r = 0
        while ((r = (getline line < unit)) > 0) scan(line)
        close(unit)
        if (r < 0 || bad || depth != 0) print "?"
        else print count
    }
}
ROWAWK

# ── reading a walk's answer ─────────────────────────────────────────────────
#
# Every count predicate in this gate tests a number a walk produced, and
# `[ "" -lt 0 ]` is not false — it is an ERROR, which `if` spends as false and
# a gate spends as CLEAN. A walk that answered with nothing would therefore
# retire twelve predicates at once and still reach PASS. An absent answer is
# worse: the read leaves the variables holding the PREVIOUS walk's numbers, so
# a later walk gets measured by an earlier one.
#
# So the numbers cross from the walk into the predicates here and nowhere else.
# Empty, short, non-numeric or over-long is a walk that measured nothing, and
# unknown stops the run rather than counting as zero.

counted() {
    case ${1:-} in
        '' | *[!0-9]*) return 1 ;;
    esac
    return 0
}

# rows carries the walk's own unknown as -1, so it alone may lead with a sign.
answered() {
    rows=''
    seen=''
    ownerseen=''
    hits=''
    read -r rows seen ownerseen <"$1" 2>/dev/null
    hits=$(sed -n '2p' -- "$1" 2>/dev/null)
    counted "${rows#-}" && counted "$seen" && counted "$ownerseen" ||
        cannot "the walk of $2 answered '$rows $seen $ownerseen' — a walk that did not answer in three numbers measured nothing"
}

# ── the walk ────────────────────────────────────────────────────────────────
#
# One implementation, used on the candidate tree and on every planted control,
# so a control exercises the code the verdict comes from. Writes
# `rows units owner` then the hit list, and reads its own answer back through
# `answered` into `rows seen ownerseen hits`. rows = -1 means the scanner did
# not establish a count for some unit: unknown, never clean.

walk() {
    walkroot=$1
    walkout=$2
    walkrows=0
    walkseen=0
    walkowner=0
    walkhits=""
    find "$walkroot" \( -name '*.zig' -o -name '*.zon' \) 2>/dev/null |
        sort >"$walkout.units"
    : >"$walkout.scanned"
    while IFS= read -r unit; do
        walkseen=$((walkseen + 1))
        rel=${unit#"$walkroot"/}
        if [ ! -f "$unit" ] || [ ! -r "$unit" ]; then
            walkrows=-1
            walkhits="$walkhits $rel(unreadable)"
            continue
        fi
        if [ "$rel" = "$OWNERPROJ" ]; then
            walkowner=1
            continue
        fi
        printf '%s\n' "$unit" >>"$walkout.scanned"
    done <"$walkout.units"

    awk -f "$scratch/row.awk" "$scratch/ids" "$walkout.scanned" \
        >"$walkout.counts" 2>/dev/null

    # Paired in list order. A short, absent or unparsable count file leaves
    # units without a count, and an uncounted unit is unknown, never clean.
    exec 7<"$walkout.scanned" 8<"$walkout.counts"
    while IFS= read -r unit <&7; do
        rel=${unit#"$walkroot"/}
        IFS= read -r n <&8 || n=""
        case ${n:-x} in
            *[!0-9]*)
                walkrows=-1
                walkhits="$walkhits $rel(nocount)"
                continue
                ;;
        esac
        if [ "$n" -gt 0 ]; then
            if [ "$walkrows" -ge 0 ]; then
                walkrows=$((walkrows + n))
            fi
            walkhits="$walkhits $rel($n)"
        fi
    done
    exec 7<&- 8<&-

    printf '%s %s %s\n%s\n' "$walkrows" "$walkseen" "$walkowner" "$walkhits" >"$walkout"
    answered "$walkout" "$walkroot"
}

# Keyword census the owner DECLARES: the closed slot span kindand..kindlet that
# lib/compiler/token.id emits `.keyword = true` for. Refuses rather than
# guessing when the span is unreadable.
census() {
    cfirst=$(sed -n 's/^kindand = \([0-9][0-9]*\)$/\1/p' "$1" 2>/dev/null | head -1)
    clast=$(sed -n 's/^kindlet = \([0-9][0-9]*\)$/\1/p' "$1" 2>/dev/null | head -1)
    case ${cfirst:-x}${clast:-x} in
        *[!0-9]*) return 1 ;;
    esac
    [ "$clast" -ge "$cfirst" ] || return 1
    echo $((clast - cfirst + 1))
}

# The identity names the owner DECLARES as keywords, one per line, from the row
# it marks `.keyword = true`. Refuses rather than returning a short set: an
# empty set makes every row's identity side false, and the walk would then
# measure nothing and report it as a clean tree.
identities() {
    sed -n 's/^.*\.kind = \.\([a-z][a-z0-9_]*\),.*\.keyword = true.*$/\1/p' \
        "$1" 2>/dev/null | sort -u
}

# ── 1. the run is bound to a real candidate tree ────────────────────────────
#
# Every section below reports zero against an absent tree. A zero from a tree
# that is not there is the report this gate exists to refuse, so bind first and
# stop: the sections after this one would be measuring nothing.

bound=1

examined=$((examined + 1))
if [ ! -d "$SRC" ]; then
    bad "no candidate tree at $SRC — an absent tree is not a clean tree"
    bound=0
fi

examined=$((examined + 1))
if [ ! -f "$OWNERID" ]; then
    bad "no owner at $OWNERID — this run is not bound to the tree the gate is about"
    bound=0
fi

examined=$((examined + 1))
if [ ! -f "$ROOT/$OWNERPROJ" ] || [ ! -f "$ROOT/$CLASSIFIER" ]; then
    bad "$OWNERPROJ or $CLASSIFIER absent — the single producer is not present to be held to anything"
    bound=0
fi

examined=$((examined + 1))
identities "$ROOT/$OWNERPROJ" >"$scratch/ids" 2>/dev/null
idcount=$(grep -c . "$scratch/ids" 2>/dev/null)
rowcount=$(grep -c '\.keyword = true' "$ROOT/$OWNERPROJ" 2>/dev/null)
case ${idcount:-x}${rowcount:-x} in
    *[!0-9]*) idcount=-1; rowcount=-1 ;;
esac
if [ "$idcount" -lt 1 ] || [ "$idcount" -ne "$rowcount" ]; then
    bad "the owner declares ${idcount} keyword identities against ${rowcount} keyword rows in $OWNERPROJ — the identity side of the row predicate is not established"
    bound=0
fi

[ "$bound" -eq 1 ] || report

# ── 2. deleted duplicate identity producers stay deleted ────────────────────
#
# The named specimens, at any depth. A resurrection under a different module
# name is section 3's job; these two are named because the record names them.

for gone in token_semantic lexical_identity; do
    examined=$((examined + 1))
    hit=$(find "$SRC" -name "$gone.zig" 2>/dev/null | head -1)
    if [ -n "$hit" ]; then
        bad "${hit#"$ROOT"/} is back — one producer owns token identity; it is lib/compiler/token.id via $OWNERPROJ"
    fi
done

# ── 3. no host unit reconstructs token identity from source spelling ────────

walk "$ROOT" "$scratch/real"

examined=$((examined + 1))
if [ "$rows" -lt 0 ]; then
    bad "the row scanner established no count for:$hits"
elif [ "$rows" -ne 0 ]; then
    bad "host spelling -> keyword identity rows outside the owner projection:$hits"
fi

examined=$((examined + 1))
if [ "$seen" -lt 1 ]; then
    bad "the class walk visited no unit under $SRC — an empty scan is not a clean tree"
fi

examined=$((examined + 1))
if [ "$ownerseen" -ne 1 ]; then
    bad "the class walk never reached $OWNERPROJ — the walk is not looking at the candidate tree"
fi

# ── 4. the owner projection still answers both directions ──────────────────
#
# Deleting the duplicate is only correct while the remaining producer still
# carries what the duplicate carried: spelling -> kind and kind -> spelling.

examined=$((examined + 1))
if ! grep -Fq 'return rows[@backingInt(self)].spell;' "$ROOT/$OWNERPROJ"; then
    bad "$OWNERPROJ no longer projects kind -> spelling; a host table would look necessary again"
fi

examined=$((examined + 1))
if ! grep -Fq 'pub const TokenKind = enum(u8)' "$ROOT/$OWNERPROJ"; then
    bad "$OWNERPROJ no longer carries the owner-generated token identity"
fi

examined=$((examined + 1))
if ! grep -Fq 'kws[i] = .{ .text = row.spell, .kind = row.kind.? };' "$ROOT/$CLASSIFIER"; then
    bad "$CLASSIFIER no longer derives its keyword census from the owner rows"
fi

# ── 5. the projection is not stale against its owner ───────────────────────
#
# Section 4 reads the projection. A projection that has drifted from the Idol
# owner answers about a tree that no longer exists, so its answers prove
# nothing — the correct verdict is FAIL, not a pass earned from stale bytes.

examined=$((examined + 1))
ownercount=$(census "$OWNERID") || ownercount=""
projcount=$(grep -c '\.keyword = true' "$ROOT/$OWNERPROJ")
projnum=-1
case ${ownercount:-x}${projcount:-x} in
    *[!0-9]*)
        bad "cannot read the keyword census (owner=${ownercount:-none} projection=${projcount:-none})"
        ;;
    *)
        projnum=$projcount
        if [ "$projcount" -ne "$ownercount" ]; then
            bad "$OWNERPROJ carries $projcount keyword rows against the owner's $ownercount — the projection is stale"
        fi
        ;;
esac

# ── 6. positive controls ────────────────────────────────────────────────────
#
# Sections 2, 3 and 5 all report zero on a clean tree. Plant, in a tree laid out
# like the candidate, every shape that got through a predecessor of this
# predicate, beside the shapes that must stay admitted, and require the walk to
# separate them. Each planted violation carries ONE row except the owner copy,
# which carries the two it copied.

plant="$scratch/planted/src"
mkdir -p "$plant/deep" || cannot "the planted control tree could not be built at $plant — section 6 did not run"

# split: the row spans lines, so a line-anchored match never sees both halves.
cat >"$plant/splitrow.zig" <<'PROBE'
pub const keywords = .{
    .{ .text = "while",
       .kind = .kw_while },
};
PROBE

# reorder: identity before spelling.
printf 'pub const keywords = .{ .{ .kind = .kw_while, .text = "while" } };\n' \
    >"$plant/reorder.zig"

# renamefield: the spelling field wears the owner projection's field name.
printf 'pub const keywords = .{ .{ .spell = "while", .kind = .kw_while } };\n' \
    >"$plant/renamefield.zig"

# tuple: a kv pair with no field names at all.
printf 'pub const keywords = .{ .{ "while", .kw_while } };\n' \
    >"$plant/tuple.zig"

# deep: the retired shape one directory down, where a flat glob never looks.
printf 'pub const keywords = .{ .{ .text = "while", .kind = .kw_while } };\n' \
    >"$plant/deep/nested.zig"

# inner: the row carries a nested descriptor group, which is what a predicate
# that delimits a row with `[^{}]*` cannot match.
printf 'pub const keywords = .{ .{ .text = "while", .kind = .kw_while, .flags = .{ .lua = true } } };\n' \
    >"$plant/inner.zig"

# typed: a named struct literal, so the row does not open with `.{`.
printf 'pub const keywords = [_]Entry{ Entry{ .text = "while", .kind = .kw_while } };\n' \
    >"$plant/typed.zig"

# atfield: the identity is reached through its own name as source text, which
# is the shape a `.kw_` prefix cannot see and the one law.identity.projection
# refuses most directly — a name selecting meaning after resolution.
printf 'pub const keywords = .{ .{ .text = "while", .kind = @field(TokenKind, "kw_while") } };\n' \
    >"$plant/atfield.zig"

# bareid: the identity carries no leading dot, because the enum was aliased in.
printf 'const kw_while = TokenKind.kw_while;\npub const keywords = .{ .{ .text = "while", .kind = kw_while } };\n' \
    >"$plant/bareid.zig"

# zon: the rows leave .zig entirely. A second producer is a second producer at
# whatever extension it is imported through.
printf '.{ .{ .text = "while", .kind = .kw_while } }\n' \
    >"$plant/table.zon"

# The owner projection's rows. Admitted at the owner's path...
cat >"$plant/grammar_role_table.zig" <<'PROBE'
pub const rows = [_]Row{
    .{ .kind = .kw_while, .spell = "while", .keyword = true },
    .{ .kind = .kw_match, .spell = "match", .keyword = true },
};
PROBE

# ...and a violation anywhere else. Shape is not what admits it.
cat >"$plant/ownercopy.zig" <<'PROBE'
pub const rows = [_]Row{
    .{ .kind = .kw_while, .spell = "while", .keyword = true },
    .{ .kind = .kw_match, .spell = "match", .keyword = true },
};
PROBE

# The admitted side, which is most of this tree: blocks that name identities and
# hold strings — a function body, a test, a switch — and an expectation row that
# holds its identities one group down. A predicate that reports these reports
# ordinary consumers, and a gate that fails on its own tree gets switched off.
cat >"$plant/clean.zig" <<'PROBE'
const wanted = lexer.TokenKind.kw_while;
const note = "while";

pub fn spellOf(t: lexer.TokenKind) []const u8 {
    return table.rows[@backingInt(t)].spell;
}

pub fn render(t: lexer.TokenKind) []const u8 {
    return switch (t) {
        .kw_while => "while",
        else => "",
    };
}

pub fn classify(s: []const u8) ?lexer.TokenKind {
    if (eql(s, "while")) return .kw_while;
    return null;
}

pub const cases = [_]Case{
    .{ .id = "kw-while", .source = "while", .expected = &.{ .kw_while, .eof } },
};

test "lexes a keyword" {
    var l = Lexer.init("while", "test");
    try testing.expectEqual(TokenKind.kw_while, (try l.next()).kind);
}
PROBE

walk "$scratch/planted" "$scratch/plantedout"

examined=$((examined + 1))
if [ "$rows" -ne 12 ] || [ "$seen" -ne 13 ] || [ "$ownerseen" -ne 1 ]; then
    bad "the row scanner is broken: rows=$rows (want 12) units=$seen (want 13) owner=$ownerseen (want 1) hits:$hits"
fi

for variant in splitrow.zig reorder.zig renamefield.zig tuple.zig deep/nested.zig \
    inner.zig typed.zig ownercopy.zig atfield.zig bareid.zig table.zon; do
    examined=$((examined + 1))
    case $hits in
        *"src/$variant("*) ;;
        *) bad "src/$variant is accepted by the row scanner" ;;
    esac
done

for admitted in grammar_role_table clean; do
    examined=$((examined + 1))
    case $hits in
        *"src/$admitted.zig("*)
            bad "src/$admitted.zig is reported by the row scanner, which refuses the admitted shape"
            ;;
        *) ;;
    esac
done

# The identity side of the row predicate. It is read from the owner rather than
# spelled here, so what has to be controlled is the read: that it recovers the
# names a projection declares, that it recovers none from a projection that
# declares none, and that the empty set it would then hand the scanner makes
# every row's identity side false. That last arm is why section 1b stops the run
# instead of letting the zero it produces be reported as a clean tree.

cat >"$scratch/idsource.zig" <<'PROBE'
pub const rows = [_]Row{
    .{ .kind = .kw_while, .spell = "while", .keyword = true },
    .{ .kind = .kw_match, .spell = "match", .keyword = true },
    .{ .kind = .name, .spell = "", .keyword = false },
};
PROBE
: >"$scratch/idnone.zig"

examined=$((examined + 1))
if [ "$(identities "$scratch/idsource.zig" | tr '\n' ' ')" != "kw_match kw_while " ]; then
    bad "the identity-set control is broken: a projection declaring kw_while and kw_match read as '$(identities "$scratch/idsource.zig" | tr '\n' ' ')'"
fi

examined=$((examined + 1))
if [ -n "$(identities "$scratch/idnone.zig")" ]; then
    bad "the identity-set control is broken: a projection declaring no keyword row still produced identities"
fi

examined=$((examined + 1))
cp "$scratch/ids" "$scratch/ids.held" || cannot "the identity-set control could not hold the established set"
: >"$scratch/ids"
walk "$scratch/planted" "$scratch/blindout"
cp "$scratch/ids.held" "$scratch/ids" || cannot "the identity-set control could not restore the established set"
if [ "$rows" -ne 0 ]; then
    bad "the identity-set control is broken: an empty identity set still counted rows=$rows, so its refusal in section 1b proves nothing"
fi

walk "$scratch/planted" "$scratch/plantedout"
examined=$((examined + 1))
if [ "$rows" -ne 12 ]; then
    bad "the identity-set control is broken: the established set did not restore the planted count (rows=$rows, want 12)"
fi

# The empty tree, which is exactly the state section 3's unit and owner
# predicates reject. Without this they are satisfied by a walk that never ran.
mkdir -p "$scratch/emptytree/src" || cannot "the empty-tree control could not be built — the unit and owner predicates went unexercised"
walk "$scratch/emptytree" "$scratch/emptyout"
examined=$((examined + 1))
if [ "$seen" -ne 0 ] || [ "$rows" -ne 0 ] || [ "$ownerseen" -ne 0 ]; then
    bad "the empty-scan control is broken: units=$seen rows=$rows owner=$ownerseen"
fi

# A unit the scanner cannot read, and a unit whose braces do not balance, are
# both unknown rather than clean.
mkdir -p "$scratch/unreadable/src" || cannot "the unreadable-unit control could not be built — the unknown-not-clean predicate went unexercised"
ln -s "$scratch/unreadable/src/absent" "$scratch/unreadable/src/dangling.zig" || cannot "the unreadable-unit control could not plant a unit the scanner cannot read"
printf 'pub const keywords = .{ .{ .text = "while", .kind = .kw_while }\n' \
    >"$scratch/unreadable/src/unbalanced.zig"
walk "$scratch/unreadable" "$scratch/unreadout"
examined=$((examined + 1))
if [ "$rows" -ne -1 ] || [ "$seen" -ne 2 ]; then
    bad "a unit the scanner cannot establish is counted clean: rows=$rows units=$seen hits:$hits"
fi

examined=$((examined + 1))
case $hits in
    *"src/unbalanced.zig(nocount)"*) ;;
    *) bad "an unbalanced unit did not reach the scanner as unknown: hits:$hits" ;;
esac

# Section 5's census must follow the owner file it is handed, and refuse a file
# that declares no span rather than returning a number.
#
# The planted span is sized off the projection, so the difference the control
# needs is built rather than hoped for. A literal here separated the two only
# while the tree happened not to carry that many keywords: at 55 the control
# fired "broken" on a tree whose owner and projection agreed. When section 5
# established no projection count the span is the smallest one a census can
# have, which no row count it could have read is equal to.
if [ "$projnum" -ge 0 ]; then
    driftwant=$((projnum + 1))
else
    driftwant=1
fi
printf 'kindand = 4\nkindlet = %d\n' "$((4 + driftwant - 1))" >"$scratch/driftowner.id"
: >"$scratch/spanless.id"
examined=$((examined + 1))
driftcount=$(census "$scratch/driftowner.id") || driftcount=""
if [ "${driftcount:-none}" != "$driftwant" ] || [ "$driftcount" -eq "$projnum" ]; then
    bad "the staleness control is broken: planted census=${driftcount:-none} (want $driftwant), projection=$projnum"
fi

examined=$((examined + 1))
if census "$scratch/spanless.id" >/dev/null 2>&1; then
    bad "the staleness control is broken: an owner declaring no keyword span still produced a census"
fi

# The walk-answer reader. Its refusals are facts about the ANSWER rather than
# about a tree, so no `src/` plant can reach them — drive the real reader in a
# subshell over each malformed shape instead, the way section 7 drives the real
# `report`. Every count predicate above is downstream of this reader, so a
# reader that returned instead of stopping would hand them empty numbers and
# they would all go on reporting clean.

for shape in 'nothing:' 'short:0 10' 'wordy:0 ten 1' 'overlong:0 10 1 junk' 'signed:0 -10 1'; do
    examined=$((examined + 1))
    printf '%s\n%s\n' "${shape#*:}" ' src/x.zig(1)' >"$scratch/answer"
    if (trap - EXIT; answered "$scratch/answer" "control") >/dev/null 2>&1; then
        bad "the walk-answer control is broken: a ${shape%%:*} answer '${shape#*:}' was read as a measurement"
    fi
done

# An answer that is not there must not be read as the PREVIOUS walk's numbers,
# which is what the variables still hold when the redirection fails.
examined=$((examined + 1))
rm -f -- "$scratch/answer"
if (trap - EXIT; rows=9; seen=10; ownerseen=1; answered "$scratch/answer" "control") \
    >/dev/null 2>&1; then
    bad "the walk-answer control is broken: an absent answer was read as the previous walk's numbers"
fi

# ...and a well-formed answer reaches the predicates unchanged, including the
# walk's own -1 unknown. Without this arm a reader that refused everything, or
# one that zeroed what it read, would satisfy every arm above.
examined=$((examined + 1))
printf '%s\n%s\n' '-1 10 1' ' src/x.zig(1)' >"$scratch/answer"
if (trap - EXIT
    answered "$scratch/answer" "control"
    [ "$rows" -eq -1 ] && [ "$seen" -eq 10 ] && [ "$ownerseen" -eq 1 ] &&
        [ "$hits" = " src/x.zig(1)" ]) >/dev/null 2>&1; then
    :
else
    bad "the walk-answer control is broken: a three-number answer was refused or misread"
fi

# ── 7. the verdict path refuses an uncontrolled clean run ───────────────────
#
# The shape detectors are controlled by planting. This one cannot be planted:
# it fires on a run that reached a verdict without section 6, which is a fact
# about the run rather than about the tree. So drive the real `report` in a
# subshell — the same implementation the verdict comes from — from each side.

examined=$((examined + 1))
if (trap - EXIT; violations=0; controlled=0; report) >/dev/null 2>&1; then
    bad "the verdict control is broken: a clean count reached before section 6 still reported PASS"
fi

examined=$((examined + 1))
if (trap - EXIT; violations=0; controlled=1; report) >/dev/null 2>&1; then
    :
else
    bad "the verdict control is broken: a controlled run with no violation cannot report PASS"
fi

controlled=1

report
