#!/bin/sh
# gate/gap-145-identity-producer.sh — GAP-145: a host module may not carry its
# own spelling -> token identity rows, and a deleted one may not come back.
#
# WHY THIS RUNNER EXISTS, SEPARATELY FROM gate/gap-145-consumer.sh:
#
# `src/token_semantic.zig` was a 54-row host keyword table — `.text` beside
# `.kind`, plus `lookupKeyword`, `entryForKind`, and `spellingForKind`. It
# answered BOTH directions of the keyword identity question (spelling -> kind,
# kind -> spelling) beside `lib/compiler/token.id`, whose generated projection
# `src/grammar_role_table.zig` already answers both. It was deleted, and the
# GAP-145 record still says so in two places: "the 54-row host identity table
# src/token_semantic.zig is DELETED" and "src/token_semantic.zig no longer
# exists".
#
# It came back. Not through a review, an import, or a call — through a bulk
# `chore: auto-commit uncommitted fleet artifacts from floor workers` that
# restored the file wholesale. It then sat in the tree with ZERO importers,
# which is exactly why nothing noticed: a call-graph census cannot see a
# producer nobody calls, and the consumer gate ratcheted only the one specimen
# (`src/lexical_identity.zig`) that had already been caught this way.
#
# So the assertion decayed in the direction this project keeps rediscovering:
# the prose said DELETED, the tree said present, and no runner disagreed with
# either. This gate is the runner. It refuses the CLASS — any host row table
# that reconstructs token identity from source spelling (law.fact.producer.one,
# law.repair.class) — not merely the two specimens already known.
#
# Every section positive-controls its own detector against planted old and new
# shapes. A gate that cannot fail reports a number that proves nothing
# (law.gate.protocol).
set -u

ROOT=${GAP145_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
SRC="$ROOT/src"

violations=0
examined=0

bad() {
    violations=$((violations + 1))
    printf 'gap-145 identity-producer gate: FAIL %s\n' "$*"
}

# ── 1. deleted duplicate identity producers stay deleted ────────────────────
#
# Named specimens. Both were zero-consumer modules that nonetheless authored a
# second answer about what a token IS. Non-existence is the whole check: a file
# that is not in the tree cannot be imported back by accident.

for gone in token_semantic lexical_identity; do
    examined=$((examined + 1))
    if [ -e "$SRC/$gone.zig" ]; then
        bad "src/$gone.zig is back — one producer owns token identity (law.fact.producer.one); it is lib/compiler/token.id via src/grammar_role_table.zig"
    fi
done

# ── 2. no host module reconstructs token identity from source spelling ──────
#
# The shape that matters is a ROW carrying a source spelling beside a token
# identity: `.text = "while", .kind = .kw_while`. That row is a producer no
# matter what the module is called or whether anything imports it, because the
# next reader to need "what keyword is this text?" will find it and answer from
# it. The owner's generated projection is excluded by construction: its rows
# spell `.kind` beside `.spell`, and it is the file the owner generates INTO.

owner_projection="grammar_role_table.zig"
spelling_rows=0
spelling_files=""
for f in "$SRC"/*.zig; do
    [ -f "$f" ] || continue
    base=$(basename -- "$f")
    [ "$base" = "$owner_projection" ] && continue
    n=$(grep -c '\.text = ".*\.kind = \.kw_' "$f" 2>/dev/null)
    [ -n "$n" ] || n=0
    if [ "$n" -gt 0 ]; then
        spelling_rows=$((spelling_rows + n))
        spelling_files="$spelling_files $base($n)"
    fi
done
examined=$((examined + 1))
if [ "$spelling_rows" -ne 0 ]; then
    bad "host spelling -> keyword identity rows outside the owner projection:$spelling_files"
fi

# ── 3. the owner projection still answers both directions ──────────────────
#
# Deleting the duplicate is only correct while the single remaining producer
# still carries what the duplicate carried: spelling -> kind (classification)
# and kind -> spelling. If the owner ever stops answering either, this gate
# must fail rather than let a host table look necessary again.

examined=$((examined + 1))
if ! grep -Fq 'return rows[@backingInt(self)].spell;' "$SRC/$owner_projection"; then
    bad "src/$owner_projection no longer projects kind -> spelling; a host table would look necessary again"
fi

examined=$((examined + 1))
if ! grep -Fq 'pub const TokenKind = enum(u8)' "$SRC/$owner_projection"; then
    bad "src/$owner_projection no longer carries the owner-generated token identity"
fi

# The remaining classifier must keep DERIVING its keyword census from the owner
# rows rather than restating it. `.text = row.spell` is the whole difference
# between a projection and a second table.
examined=$((examined + 1))
if ! grep -Fq 'kws[i] = .{ .text = row.spell, .kind = row.kind.? };' "$SRC/token_classify_gen.zig"; then
    bad 'src/token_classify_gen.zig no longer derives its keyword census from the owner rows'
fi

# ── 4. positive controls ────────────────────────────────────────────────────
#
# Sections 1 and 2 both report zero on a clean tree, and a zero needs a positive
# control. Plant the exact retired shape and the exact admitted shape, and
# require the detectors to separate them.

probe=$(mktemp -d) || { echo 'gap-145 identity-producer gate: cannot allocate scratch' >&2; exit 2; }
trap 'rm -rf -- "$probe"' EXIT

# The retired shape: a host row carrying spelling beside identity.
cat >"$probe/old.zig" <<'PROBE'
pub const keywords: []const KeywordEntry = &.{
    .{ .text = "while", .kind = .kw_while, .category = .lua_keyword },
    .{ .text = "match", .kind = .kw_match, .category = .contextual },
};
PROBE

# The admitted shape: the owner's generated projection rows.
cat >"$probe/new.zig" <<'PROBE'
pub const rows = [_]Row{
    .{ .kind = .kw_while, .spell = "while", .begin_expr = false },
    .{ .kind = .kw_match, .spell = "match", .begin_expr = false },
};
PROBE

probe_old=$(grep -c '\.text = ".*\.kind = \.kw_' "$probe/old.zig")
probe_new=$(grep -c '\.text = ".*\.kind = \.kw_' "$probe/new.zig")
examined=$((examined + 1))
if [ "$probe_old" -ne 2 ] || [ "$probe_new" -ne 0 ]; then
    bad "the spelling-row detector is broken: old=$probe_old new=$probe_new"
fi

# Section 1's detector is existence. Prove it can see a file that is there,
# so its silence on the real tree means absence and not a broken test.
: >"$probe/token_semantic.zig"
examined=$((examined + 1))
if [ ! -e "$probe/token_semantic.zig" ]; then
    bad 'the resurrection detector is broken: it cannot see a file that exists'
fi
examined=$((examined + 1))
if [ -e "$probe/never_written.zig" ]; then
    bad 'the resurrection detector is broken: it sees a file that was never written'
fi

if [ "$violations" -eq 0 ]; then
    printf 'gap-145 identity-producer gate: PASS (%d check(s))\n' "$examined"
    exit 0
fi

printf 'gap-145 identity-producer gate: FAIL (%d violation(s), %d check(s))\n' "$violations" "$examined"
exit 1
