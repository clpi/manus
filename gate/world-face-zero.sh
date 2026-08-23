#!/bin/sh
# WORLD-FACE-ZERO — the `@` sigil belongs to the world algebra, and to nothing else.
#
# `law.injection.only` (C0 §2761, §2199, and the GAP-110 reconciliation) rules
# `@{ … }` EXCLUSIVELY world-deriving. A descriptor is an ordinary table: the
# copula `name: { … }`, the applied form `name{ … }`, the case-set
# `name: { a, b, c }`. fd85e7b8 retired the descriptor face and migrated the
# 69 corpus lines GAP-203 measured across 36 files.
#
# The parser refuses the retired spellings TODAY. This gate is what stops them
# coming back, and it is built so it cannot pass vacuously:
#
#   §1 REFUSAL      each retired spelling is planted and must be refused BY NAME.
#   §2 ADMISSION    each migrated spelling must CHECK CLEAN — without this half
#                   a compiler that refused every program would read green.
#   §3 RESIDUE      zero live descriptor sigils in the tracked .id corpus, with
#                   the scanner controlled against a planted violation so a
#                   rotted regex cannot report a clean zero.
#   §4 FORMATTER    `idol fmt` may never emit a spelling the parser will not
#                   take back. The descriptor SPREAD is the case that mattered:
#                   `..parent` was only spellable on the sigil face, so the
#                   printer reprinted `@{` and formatting a legal file produced
#                   an illegal one.
#
# GAP-203 owns what remains: freeing the sigil is NOT closing the algebra. No
# face of the five compiles yet. This gate asserts the sigil is FREE, never that
# injection works.
set -eu
root=${WORLD_FACE_ZERO_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}
if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi
idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-world-face-zero.XXXXXX")
cleanup() { rm -rf "$work"; }
trap cleanup EXIT INT TERM
fail() { printf 'world-face-zero gate: FAIL %s\n' "$1" >&2; exit 1; }
[ -x "$idol" ] || fail "compiler is not executable: $idol"

# ---------------------------------------------------------------- §1 REFUSAL
# Each row plants the violation and demands BOTH a non-zero exit and the exact
# diagnostic. Exit alone is not enough: every one of these spellings would also
# exit non-zero if the parser simply broke, and a gate that cannot tell refusal
# from breakage is decoration.
refuse() {
    name=$1; src=$2; want=$3
    printf '%s\n' "$src" >"$work/$name.id"
    set +e
    out=$("$idol" check "$work/$name.id" 2>&1)
    ec=$?
    set -e
    if [ "$ec" -eq 0 ]; then
        printf '%s\n' "$out" >&2
        fail "§1 $name: the retired descriptor sigil CHECKED CLEAN — the sigil is occupied again: $src"
    fi
    case $out in
        *"$want"*) : ;;
        *)
            printf '%s\n' "$out" >&2
            fail "§1 $name: refused, but not by name — expected \"$want\"; a bare refusal cannot tell the reader the sigil is world-only"
            ;;
    esac
}

# The copula face. GAP-203 measured this as the DOMINANT one — 24 live
# DECL_COLON sites, including the self-hosting frontier itself
# (`lib/compiler/parser.id`, `lib/cursor.id`) — and `grep '= *@{'` never saw it.
refuse decl_colon \
    'point: @{ x: f64, y: f64 }' \
    "'@{ … }' is world injection, not descriptor construction"

# The case-set face: a keywordless enum written on the sigil.
refuse decl_caseset \
    'kind: @{ eof, ident, number }' \
    "'@{ … }' is world injection, not descriptor construction"

# The bind face — the 11 sites the original undercount DID see, "frozen constant
# tables that depend on the staging" per the parser's own retired comment.
refuse bind_frozen \
    'kind = @{ eof = 0, ident = 1 }' \
    "injection '@{ … }' has no derived-world fact yet"

# C0 §2884 denies this spelling BY NAME
# (`deny = "p: point = @{ x, y } — @{ … } is world injection, not a descriptor
# construction face (law.injection.only)"`) and GAP-203 measured the compiler
# accepting it. That is the exact live law violation; it stays planted here.
refuse deny_by_name \
    'p: point = @{ x, y }' \
    "injection '@{ … }' has no derived-world fact yet"

# --------------------------------------------------------------- §2 ADMISSION
# The migration is only behaviour-preserving if the sigil-free spelling of each
# migrated site still resolves. These are the three shapes fd85e7b8 migrated to.
admit() {
    name=$1; src=$2
    printf '%s\n' "$src" >"$work/$name.id"
    set +e
    out=$("$idol" check "$work/$name.id" 2>&1)
    ec=$?
    set -e
    if [ "$ec" -ne 0 ]; then
        printf '%s\n' "$out" >&2
        fail "§2 $name: the MIGRATED spelling does not check — §1 would then be passing by refusing everything: $src"
    fi
}
admit ok_record  'point: { x: f64, y: f64 }'
admit ok_caseset 'kind: { eof, ident, number }'
admit ok_spread  'base: { x: i64 }
derived: { ..base, y: i64 }'
admit ok_pack    'p = { x = 1, y = 2 }'

# ----------------------------------------------------------------- §3 RESIDUE
# A live site is a `@` glued to `{` in CODE. Comments carry the migration
# narrative and string literals carry gate fixtures and generator payloads;
# both are read, so the scanner strips them rather than pretending they do not
# exist. Byte strings ('…') do not interpolate and decode no escapes, so they
# are stripped whole; interpolating strings ("…") may hold `\"`, which is
# removed before the span match so an escaped quote cannot end a span early.
# A live site is a `@` glued to `{` in CODE. Comments carry the migration
# narrative and string literals carry gate fixtures and generator payloads;
# both are read, so the scanner strips them rather than pretending they do not
# exist. Byte strings ('…') do not interpolate and decode no escapes, so they
# are stripped whole; interpolating strings ("…") may hold `\"`, which is
# removed before the span match so an escaped quote cannot end a span early.
#
# `#FILE` is emitted per subject so the scan can be asked what it actually
# READ. That is not decoration: the first version of this gate ran under the
# ambient locale, `awk` aborted on `examples/table/str/invalid.id` — a fixture
# that is deliberately invalid UTF-8 — and the residue came back EMPTY. A
# planted violation passed. The locale is pinned to C so bytes are bytes, the
# exit status is read instead of discarded, and the subject count is compared
# against the corpus, because any one of the three alone still admits a scan
# that quietly stopped early.
cat >"$work/scan.awk" <<'AWK'
FNR == 1 { printf "#FILE\n" }
{
    line = $0
    gsub(/\\./, "", line)                   # escapes first: \" must not close a span
    gsub(/"[^"]*"/, "", line)               # interpolating string bodies
    gsub(/\047[^\047]*\047/, "", line)      # byte-string bodies
    h = index(line, "#")
    if (h > 0) line = substr(line, 1, h - 1)
    if (line ~ /@[ \t]*\{/) printf "%s:%d:%s\n", FILENAME, FNR, $0
}
AWK
scan() { LC_ALL=C awk -f "$work/scan.awk" "$@"; }

# POSITIVE CONTROL. The corpus reads zero, which is exactly the condition under
# which a rotted scanner is invisible — it would report the same zero on a tree
# full of violations. So the scanner is proved against planted ones first, and
# proved to DECLINE the forms that must survive.
mkdir -p "$work/control"
cat >"$work/control/violation.id" <<'PLANT'
point: @{ x: f64, y: f64 }
kind = @{ eof = 0 }
PLANT
cat >"$work/control/clean.id" <<'PLANT'
# the retired face is `name: @{ … }` — this comment must NOT convict
point: { x: f64, y: f64 }
sample = "x = @{ name = 1 }"
byte = 'p: point = @{ x, y }'
escaped = "a \" then @{ still inside the string }"
PLANT
# And a control for the failure that actually happened: a subject the scanner
# cannot decode must not be able to end the scan silently.
printf 'x = "\376\377bad"\npoint: @{ y: i64 }\n' >"$work/control/undecodable.id"

planted=$(scan "$work/control/violation.id" | grep -cv '^#FILE$' || true)
[ "$planted" = 2 ] || fail "§3 control: the scanner saw $planted of 2 planted violations; it would read a clean zero over a corpus full of them"
declined=$(scan "$work/control/clean.id" | grep -cv '^#FILE$' || true)
[ "$declined" = 0 ] || fail "§3 control: the scanner convicted $declined comment/string line(s); it is too broad and would drive the repair backwards"
undec=$(scan "$work/control/undecodable.id" | grep -cv '^#FILE$' || true)
[ "$undec" = 1 ] || fail "§3 control: the scanner saw $undec of 1 violation in an undecodable subject; a non-UTF-8 fixture can abort the scan and hide the corpus"

cd "$root"
subjects=$(git ls-files -- '*.id' | grep -c . || true)
[ "$subjects" -gt 500 ] || fail "§3 subject: the corpus resolved to $subjects .id file(s) — NOT MEASURED"

git ls-files -z -- '*.id' >"$work/subjects.z"
if ! xargs -0 <"$work/subjects.z" env LC_ALL=C awk -f "$work/scan.awk" >"$work/scan.out" 2>"$work/scan.err"; then
    cat "$work/scan.err" >&2
    fail "§3 the residue scan FAILED — its zero means nothing"
fi
read_files=$(grep -c '^#FILE$' "$work/scan.out" || true)
[ "$read_files" = "$subjects" ] || fail "§3 the residue scan read $read_files of $subjects subjects — it stopped early and its zero means nothing"

grep -v '^#FILE$' "$work/scan.out" >"$work/residue" || true
n=$(grep -c . "$work/residue" || true)
if [ "$n" -ne 0 ]; then
    cat "$work/residue" >&2
    fail "§3 residue: $n live descriptor sigil site(s) in the tracked .id corpus — the migration regressed"
fi

# --------------------------------------------------------------- §4 FORMATTER
# Formatting a legal file must not produce an illegal one. `..parent` had no
# home in a record TYPE, so the printer kept the sigil face to keep the parent
# and `Derived: @{ ..Base, y: i64 }` was what came back out. Round-trip is the
# assertion: reprint, demand no sigil, and demand the reprint still checks.
cat >"$work/fmt_spread.id" <<'FMT'
base: { x: i64 }
derived: { ..base, y: i64 }
FMT
cp "$work/fmt_spread.id" "$work/fmt_spread.before"
"$idol" fmt "$work/fmt_spread.id" >/dev/null 2>&1 || fail "§4 fmt refused a legal descriptor spread"
if grep -q '@[ 	]*{' "$work/fmt_spread.id"; then
    cat "$work/fmt_spread.id" >&2
    fail "§4 the formatter emitted the retired sigil — formatting a legal file now produces one the parser refuses"
fi
grep -q '\.\.base' "$work/fmt_spread.id" || {
    cat "$work/fmt_spread.id" >&2
    fail "§4 the formatter DROPPED the '..base' spread — the reprint silently deletes every inherited field"
}
"$idol" check "$work/fmt_spread.id" >/dev/null 2>&1 || {
    cat "$work/fmt_spread.id" >&2
    fail "§4 the reprint does not check — the formatter produced a file the parser will not take back"
}

# gap[223]. The spread was not the only printer path to the sigil. `@(expr)` is
# comptime eval and `{ a = 1 }` is an ordinary pack, so `@({ a = 1 })` composes
# two live faces — and the printer had an arm that wrote the sigil bare for a
# table operand, so formatting this legal file produced one the parser refuses.
# The assertion is the ROUND TRIP: reprint, re-check, reprint again and demand
# byte identity. A grep for `@{` alone would pass against any printer that
# happens to avoid the bytes for the wrong reason.
printf 'x = @({ a = 1 })\n' >"$work/fmt_comptime.id"
"$idol" check "$work/fmt_comptime.id" >/dev/null 2>&1 || fail "§4 subject: '@({ … })' does not check — the round-trip control has no legal input and would pass vacuously"
"$idol" fmt "$work/fmt_comptime.id" >/dev/null 2>&1 || fail "§4 fmt refused comptime eval over a pack"
if grep -q '@[ 	]*{' "$work/fmt_comptime.id"; then
    cat "$work/fmt_comptime.id" >&2
    fail "§4 the formatter emitted the retired sigil for a comptime-evaluated pack (gap[223])"
fi
"$idol" check "$work/fmt_comptime.id" >/dev/null 2>&1 || {
    cat "$work/fmt_comptime.id" >&2
    fail "§4 the reprint of '@({ … })' does not check — fmt turned a legal file into an illegal one (gap[223])"
}
cp "$work/fmt_comptime.id" "$work/fmt_comptime.once"
"$idol" fmt "$work/fmt_comptime.id" >/dev/null 2>&1 || fail "§4 fmt refused its own output"
cmp -s "$work/fmt_comptime.once" "$work/fmt_comptime.id" || {
    diff -u "$work/fmt_comptime.once" "$work/fmt_comptime.id" >&2 || true
    fail "§4 fmt is not a fixed point on '@({ … })' — the damage merely moved one pass later"
}

# NEGATIVE CONTROL on the repair's direction. `@(64)` printed bare gives `@64`,
# which does not lex. Deleting the sigil-glued arm must not be read as licence
# to delete the parens.
printf 'x = @(64)\n' >"$work/fmt_scalar.id"
"$idol" fmt "$work/fmt_scalar.id" >/dev/null 2>&1 || fail "§4 fmt refused '@(64)'"
grep -q '@(64)' "$work/fmt_scalar.id" || {
    cat "$work/fmt_scalar.id" >&2
    fail "§4 the formatter dropped the parens from '@(64)' — the reprint does not lex"
}

printf 'world-face-zero gate: PASS — sigil free (4 retired spellings refused by name, 4 migrated spellings admitted, 0 live corpus sites, formatter sigil-free)\n'
printf 'world-face-zero gate: NOTE — a free sigil is not a closed algebra; 0 of 5 world faces compile (gap[203])\n'
