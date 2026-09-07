#!/bin/sh
# gate/gap-145-identity-producer.sh — GAP-145: one producer owns token identity
# (law.fact.producer.one). It is lib/compiler/token.id via its generated
# projection src/grammar_role_table.zig. A host module may not carry a second
# spelling -> token identity table, and a deleted one may not come back.
#
# Deletion history, the two named specimens, and why a call-graph census cannot
# see a zero-consumer producer: gaps/GAP-145.md. Not repeated here.
#
# The gate refuses the CLASS (law.repair.class), so its predicate is a ROW —
# a brace group carrying a source spelling beside a token identity — matched
# after newlines are folded, at any depth, under any module name. Field order,
# field name, line breaks, and directory depth are spelling, not shape. The
# owner's own generated projection is admitted BY PATH; a copy of its rows
# anywhere else is a second producer.
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

bad() {
    violations=$((violations + 1))
    printf 'gap-145 identity-producer gate: FAIL %s\n' "$*"
}

report() {
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

# ── the walk ────────────────────────────────────────────────────────────────
#
# One implementation, used on the candidate tree and on every planted control,
# so a control exercises the code the verdict comes from. Writes
# `rows units owner` then the hit list. rows = -1 means the detector could not
# produce a count for some unit: unknown, never clean.

walk() {
    walkroot=$1
    walkout=$2
    walkrows=0
    walkseen=0
    walkowner=0
    walkhits=""
    find "$walkroot" -name '*.zig' 2>/dev/null | sort >"$walkout.units"
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
        n=$(tr '\n' ' ' <"$unit" | grep -oE '\.\{[^{}]*\}' | grep '"' | grep -c '\.kw_[a-z]')
        case $n in
            '' | *[!0-9]*)
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
    done <"$walkout.units"
    printf '%s %s %s\n%s\n' "$walkrows" "$walkseen" "$walkowner" "$walkhits" >"$walkout"
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
read rows seen ownerseen <"$scratch/real"
hits=$(sed -n '2p' "$scratch/real")

examined=$((examined + 1))
if [ "$rows" -lt 0 ]; then
    bad "the identity-row detector produced no count for:$hits"
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
# Sections 2, 3 and 5 all report zero on a clean tree. Plant, in a tree laid
# out like the candidate, every shape that got through the retired predicate,
# beside the shapes that must stay admitted, and require the walk to separate
# them. The five false-accept variants each carry ONE row.

plant="$scratch/planted/src"
mkdir -p "$plant/deep" || report

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

# An ordinary consumer: names an identity, holds a string, authors neither.
cat >"$plant/clean.zig" <<'PROBE'
const wanted = lexer.TokenKind.kw_while;
const note = "while";
pub fn spellOf(t: lexer.TokenKind) []const u8 {
    return table.rows[@intFromEnum(t)].spell;
}
PROBE

walk "$scratch/planted" "$scratch/plantedout"
read prows pseen powner <"$scratch/plantedout"
phits=$(sed -n '2p' "$scratch/plantedout")

examined=$((examined + 1))
if [ "$prows" -ne 7 ] || [ "$pseen" -ne 8 ] || [ "$powner" -ne 1 ]; then
    bad "the identity-row detector is broken: rows=$prows (want 7) units=$pseen (want 8) owner=$powner (want 1) hits:$phits"
fi

for variant in splitrow reorder renamefield tuple deep/nested ownercopy; do
    examined=$((examined + 1))
    case $phits in
        *"src/$variant.zig("*) ;;
        *) bad "src/$variant.zig is accepted by the identity-row detector" ;;
    esac
done

for admitted in grammar_role_table clean; do
    examined=$((examined + 1))
    case $phits in
        *"src/$admitted.zig("*)
            bad "src/$admitted.zig is reported by the identity-row detector, which refuses the admitted shape"
            ;;
        *) ;;
    esac
done

# The empty tree, which is exactly the state section 3's unit and owner
# predicates reject. Without this they are satisfied by a walk that never ran.
mkdir -p "$scratch/emptytree/src" || report
walk "$scratch/emptytree" "$scratch/emptyout"
read erows eseen eowner <"$scratch/emptyout"
examined=$((examined + 1))
if [ "$eseen" -ne 0 ] || [ "$erows" -ne 0 ] || [ "$eowner" -ne 0 ]; then
    bad "the empty-scan control is broken: units=$eseen rows=$erows owner=$eowner"
fi

# A unit the detector cannot read must be unknown, not clean.
mkdir -p "$scratch/unreadable/src" || report
ln -s "$scratch/unreadable/src/absent" "$scratch/unreadable/src/dangling.zig" || report
walk "$scratch/unreadable" "$scratch/unreadout"
read urows useen uowner <"$scratch/unreadout"
examined=$((examined + 1))
if [ "$urows" -ne -1 ] || [ "$useen" -ne 1 ]; then
    bad "a unit the detector cannot read is counted clean: rows=$urows units=$useen"
fi

# Section 5's census must follow the owner file it is handed, and refuse a file
# that declares no span rather than returning a number.
printf 'kindand = 4\nkindlet = 58\n' >"$scratch/driftowner.id"
: >"$scratch/spanless.id"
examined=$((examined + 1))
driftcount=$(census "$scratch/driftowner.id") || driftcount=""
if [ "${driftcount:-none}" != 55 ] || [ "$projnum" -eq 55 ]; then
    bad "the staleness control is broken: planted census=${driftcount:-none} (want 55), projection=$projnum not separated from it"
fi

examined=$((examined + 1))
if census "$scratch/spanless.id" >/dev/null 2>&1; then
    bad "the staleness control is broken: an owner declaring no keyword span still produced a census"
fi

report
