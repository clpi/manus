#!/bin/sh
# gate/layering.sh — the layer-import firewall.
#
# Three mechanical rules, none of which reads a comment or asks anyone's
# opinion about intent:
#
#   L1  DIRECTION.  A translation unit may not @import a layer below it.
#       Concretely: the backend must not import AST or Sema to recover
#       meaning. 75 such edges already exist; they are pinned exactly in
#       gate/layering.baseline. A new one fails. A removed one also fails,
#       so paying the debt down forces a re-pin and cannot silently reverse.
#
#   L2  PROJECTIONS.  A generated file may not be authored outside its
#       generator. Its do-not-edit marker must survive, and a diff that
#       touches it must touch its generator in the same diff.
#
#   L3  RELATION IDENTITY.  The AST layer owns shape, not semantic relation
#       identity. Ownership tokens in AST-layer files are pinned exactly in
#       gate/relation-ownership.baseline.
#
# Every classification comes from a checked-in manifest. Nothing is inferred
# from a filename: `native/ir.zig` (IR) and `native.zig` (BACKEND)
# share a prefix and sit in different layers, and a prefix rule gets both
# wrong. Coverage of src/*.zig is MANDATORY -- an unclassified new file fails,
# because routing a forbidden edge through an unclassified module is the
# cheapest way to defeat a direction rule.
#
# No `idol check`. This gate reads @import text and diff paths.
#
# USAGE:
#   gate/layering.sh                 all three rules, staged diff for L2
#   gate/layering.sh --base <rev>    L2 over <rev>..worktree
#   gate/layering.sh --diff <file>   L2 over a diff file
#   gate/layering.sh --static-only   L1 + L3 only (L2 needs a diff; stated)

set -eu

MIN_UNITS=100        # today: 117 tracked src/*.zig
MIN_EDGES=400        # today: 580 distinct import edges. If edge extraction
                     # collapses, every forbidden edge "disappears" and the
                     # baseline comparison would report a clean removal
                     # sweep. That must fail, not pass.

prog=$(basename "$0")
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
layers="$here/layers.manifest"
rules="$here/layering.rules"
baseline="$here/layering.baseline"
genman="$here/generated.manifest"
relbase="$here/relation-ownership.baseline"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/idol-layering.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

die() { printf '%s\n' "LAYERING BLOCKED -- $*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }
TAB=$(printf '\t')

for f in "$layers" "$rules" "$baseline" "$genman" "$relbase"; do
    [ -f "$f" ] || die "$(basename "$f") is missing. A firewall with no manifest is not a permissive firewall, it is a broken one."
done

mode=full
diff_file=""
base_rev=""
while [ $# -gt 0 ]; do
    case "$1" in
        --static-only) mode=static ;;
        --base) shift; [ $# -gt 0 ] || die "--base needs a revision"; base_rev="$1" ;;
        --diff) shift; [ $# -gt 0 ] || die "--diff needs a path"; diff_file="$1" ;;
        -h|--help) sed -n '1,32p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

# ================================================================ ENUMERATION ==
# gate/subject.sh is the one subject owner. A no-Git archive mirror is not
# evidence, and a candidate module is examined once it is staged/tracked. The
# prior filesystem-first path made layering the third incompatible answer to
# "what tree is being judged" and admitted sufficiently large archive mirrors.
units="$tmp/units.txt"
subject="$here/subject.sh"
[ -x "$subject" ] || die "gate/subject.sh is missing or not executable."
if ! (cd "$root" && sh "$subject" 'src/*.zig') >"$tmp/units.raw"; then
    die "compiler-unit enumeration failed (GAP-201/GAP-220)."
fi
LC_ALL=C sort "$tmp/units.raw" >"$units"
enum_via=subject
n_units=$(LC_ALL=C awk 'END { print NR }' "$units")
[ "$n_units" -gt 0 ] || die "ZERO compiler units enumerated (GAP-201). Examining nothing is a failure, not a clean report."
[ "$n_units" -ge "$MIN_UNITS" ] || die "only $n_units units via $enum_via, floor $MIN_UNITS (GAP-201/GAP-220). Enumeration is broken."

have_git=yes

# ======================================================= L1: LAYER DIRECTION ==
lmap="$tmp/lmap.txt"
if ! LC_ALL=C awk '/^[[:space:]]*(#|$)/ { next } { if (NF < 2) exit 3; print $2 "\t" $1 }' "$layers" >"$lmap"; then
    die "gate/layers.manifest is malformed."
fi
n_class=$(LC_ALL=C awk 'END { print NR }' "$lmap")
[ "$n_class" -gt 0 ] || die "gate/layers.manifest classifies nothing."

# Duplicate classification is ambiguity, and ambiguity is an escape hatch.
if ! LC_ALL=C awk -F'\t' '{ if ($1 in seen) { print "  duplicate: " $1 > "/dev/stderr"; bad = 1 } seen[$1] = 1 } END { exit bad ? 1 : 0 }' "$lmap"; then
    die "gate/layers.manifest classifies a file more than once."
fi

# COVERAGE. Deny by default: every tracked unit must be classified.
LC_ALL=C sed 's|^src/||' "$units" | LC_ALL=C sort >"$tmp/have.txt"
LC_ALL=C awk -F'\t' '{ print $1 }' "$lmap" | LC_ALL=C sort >"$tmp/known.txt"
LC_ALL=C comm -23 "$tmp/have.txt" "$tmp/known.txt" >"$tmp/unclassified.txt"
if [ -s "$tmp/unclassified.txt" ]; then
    note "compiler units with no layer:"
    LC_ALL=C sed 's/^/  src\//' "$tmp/unclassified.txt" >&2
    die "$(LC_ALL=C awk 'END{print NR}' "$tmp/unclassified.txt") src/*.zig file(s) present in the tree are unclassified.
  Classify them in gate/layers.manifest. An unclassified module is the cheapest way to route a forbidden edge, so it fails rather than being ignored."
fi
LC_ALL=C comm -13 "$tmp/have.txt" "$tmp/known.txt" >"$tmp/ghost.txt"
if [ -s "$tmp/ghost.txt" ]; then
    LC_ALL=C sed 's/^/  /' "$tmp/ghost.txt" >&2
    die "gate/layers.manifest classifies file(s) that do not exist. Stale classification hides a real one."
fi

forbid="$tmp/forbid.txt"
if ! LC_ALL=C awk '/^[[:space:]]*(#|$)/ { next } { if (NF < 2) exit 3; print $1 "\t" $2 }' "$rules" >"$forbid"; then
    die "gate/layering.rules is malformed."
fi
[ -s "$forbid" ] || die "gate/layering.rules forbids nothing. An empty rule set is not a lenient firewall, it is an absent one."

edges="$tmp/edges.txt"
: >"$edges"
while IFS= read -r rel; do
    [ -f "$root/$rel" ] || continue
    b=${rel#src/}
    if ! LC_ALL=C awk -v MF="$lmap" -v BASE="$b" '
        function resolve(path, part, count, i, depth, result, segment) {
            count = split(path, part, "/")
            depth = 0
            for (i = 1; i <= count; i++) {
                if (part[i] == "." || part[i] == "") continue
                if (part[i] == "..") {
                    if (!depth) exit 3
                    depth--
                } else segment[++depth] = part[i]
            }
            result = segment[1]
            for (i = 2; i <= depth; i++) result = result "/" segment[i]
            return result
        }
        BEGIN { while ((getline l < MF) > 0) { split(l, a, "\t"); layer[a[1]] = a[2] }; home = BASE; sub(/[^\/]+$/, "", home) }
        {
            s = $0
            while (match(s, /@import\("[A-Za-z0-9_.\/-]+\.zig"\)/)) {
                m = substr(s, RSTART, RLENGTH)
                gsub(/@import\("|"\)/, "", m)
                if (substr(m, 1, 1) == "/") exit 3
                m = resolve(home m)
                if (m != BASE && (m in layer)) print layer[BASE] "\t" BASE "\t" layer[m] "\t" m
                s = substr(s, RSTART + RLENGTH)
            }
        }
    ' "$root/$rel" >>"$edges"; then
        die "edge extraction aborted on $rel. A short edge list makes every violation vanish; refusing to report a pass."
    fi
done <"$units"

LC_ALL=C sort -u "$edges" >"$tmp/uedges.txt"
n_edges=$(LC_ALL=C awk 'END { print NR }' "$tmp/uedges.txt")
[ "$n_edges" -ge "$MIN_EDGES" ] || die "only $n_edges distinct import edges extracted, floor $MIN_EDGES (GAP-201).
  Extraction collapsed. Every forbidden edge would read as removed and the run would look like a triumphant cleanup. It is not one."

LC_ALL=C awk -F'\t' -v FB="$forbid" '
    BEGIN { while ((getline l < FB) > 0) { split(l, a, "\t"); bad[a[1] "\t" a[2]] = 1 } }
    ($1 "\t" $3) in bad { print }
' "$tmp/uedges.txt" | LC_ALL=C sort >"$tmp/actual.txt"

LC_ALL=C awk '/^[[:space:]]*(#|$)/ { next } { print }' "$baseline" | LC_ALL=C sort >"$tmp/pinned.txt"
n_actual=$(LC_ALL=C awk 'END { print NR }' "$tmp/actual.txt")
n_pinned=$(LC_ALL=C awk 'END { print NR }' "$tmp/pinned.txt")
[ "$n_pinned" -gt 0 ] || die "gate/layering.baseline pins nothing. An empty baseline would make the whole existing debt read as new -- or, if inverted, make anything permissible."

LC_ALL=C comm -23 "$tmp/actual.txt" "$tmp/pinned.txt" >"$tmp/new_edges.txt"
LC_ALL=C comm -13 "$tmp/actual.txt" "$tmp/pinned.txt" >"$tmp/gone_edges.txt"

note "$prog: L1 -- $n_units units via $enum_via, $n_edges distinct import edges, $n_actual forbidden (baseline pins $n_pinned)."

if [ -s "$tmp/new_edges.txt" ]; then
    note ""
    note "NEW forbidden dependency edge(s):"
    LC_ALL=C awk -F'\t' '{ printf "  src/%-28s (%s)  ->  src/%-24s (%s)\n", $2, $1, $4, $3 }' "$tmp/new_edges.txt" >&2
    note ""
    die "the dependency direction was violated in a way it was not violated before.
  A backend that imports AST or Sema is not consuming a decided answer, it is
  re-deriving meaning at emission time -- which is how two places come to decide
  the same thing and disagree. Take the fact from IR, or have the layer above
  hand it over. gate/layering.rules, gate/layers.manifest."
fi

if [ -s "$tmp/gone_edges.txt" ]; then
    note ""
    note "forbidden edge(s) in the baseline that no longer exist:"
    LC_ALL=C awk -F'\t' '{ printf "  src/%s (%s) -> src/%s (%s)\n", $2, $1, $4, $3 }' "$tmp/gone_edges.txt" >&2
    note ""
    die "you paid debt down. Re-pin gate/layering.baseline in this same commit ($n_actual edges, was $n_pinned).
  The baseline is a ratchet; ground taken is not given back by accident."
fi

# ==================================================== L3: RELATION OWNERSHIP ==
relpin="$tmp/relpin.txt"
LC_ALL=C awk '/^[[:space:]]*(#|$)/ { next } { print $1 "\t" $2 }' "$relbase" >"$relpin"
[ -s "$relpin" ] || die "gate/relation-ownership.baseline pins nothing."

reltok='relation_edge|relation_id|RelationId|relation_family|relation_symbol'
: >"$tmp/relactual.txt"
LC_ALL=C awk -F'\t' '$2 == "AST" { print $1 }' "$lmap" | LC_ALL=C sort >"$tmp/astfiles.txt"
n_ast=$(LC_ALL=C awk 'END { print NR }' "$tmp/astfiles.txt")
[ "$n_ast" -gt 0 ] || die "zero AST-layer files (GAP-201). The relation-ownership rule would examine nothing."

while IFS= read -r b; do
    p="src/$b"
    [ -f "$root/$p" ] || continue
    n=$(LC_ALL=C awk -v re="$reltok" 'BEGIN { n = 0 } { s = $0; while (match(s, re)) { n++; s = substr(s, RSTART + RLENGTH) } } END { print n }' "$root/$p")
    [ "$n" -gt 0 ] && printf '%s\t%s\n' "$p" "$n" >>"$tmp/relactual.txt"
done <"$tmp/astfiles.txt"
LC_ALL=C sort -o "$tmp/relactual.txt" "$tmp/relactual.txt"
LC_ALL=C sort -o "$relpin" "$relpin"

if ! LC_ALL=C diff "$relpin" "$tmp/relactual.txt" >"$tmp/reldiff.txt"; then
    note ""
    note "relation-identity ownership in the AST layer changed (pinned <, actual >):"
    LC_ALL=C sed 's/^/  /' "$tmp/reldiff.txt" >&2
    note ""
    die "the parser owns shape, not semantic relation identity.
  src/parser.zig:2884 already mints \"{name}__{level}\" itself, and
  src/parser.zig:2941 records what that costs: an edge declared in another
  module is not in the parser's map, so it does not resolve (gap[025]).
  The authority is src/relation.zig. If you moved ownership out, re-pin
  gate/relation-ownership.baseline in this same commit."
fi
note "$prog: L3 -- $n_ast AST-layer files scanned, relation-identity ownership matches the pin."

# ====================================================== L2: GENERATED FILES ==
if [ "$mode" = static ]; then
    note "$prog: --static-only -- L2 (generated-file authorship) was SKIPPED, not passed."
fi

gen="$tmp/gen.txt"
if ! LC_ALL=C awk -F'\t' '/^[[:space:]]*(#|$)/ { next } { if (NF < 3) exit 3; print $1 "\t" $2 "\t" $3 }' "$genman" >"$gen"; then
    die "gate/generated.manifest is malformed (need <generated>\\t<generator>\\t<marker>)."
fi
n_gen=$(LC_ALL=C awk 'END { print NR }' "$gen")
[ "$n_gen" -gt 0 ] || die "gate/generated.manifest lists no projections. If nothing is generated, delete the rule; do not ship an inert one."

# L2a -- the marker must survive. Removing it is the first move of anyone
# about to author inside a projection. This half needs no diff.
missing=0
while IFS="$TAB" read -r g gen_src marker; do
    if [ ! -f "$root/$g" ]; then
        die "gate/generated.manifest names $g, which does not exist. A stale projection entry hides a live one."
    fi
    if [ ! -f "$root/$gen_src" ]; then
        die "generator $gen_src for $g does not exist."
    fi
    if ! LC_ALL=C awk -v m="$marker" 'index($0, m) { f = 1; exit } END { exit f ? 0 : 1 }' "$root/$g"; then
        note "  $g has lost its marker: \"$marker\""
        missing=$((missing + 1))
    fi
done <"$gen"
[ "$missing" -eq 0 ] || die "$missing generated file(s) no longer carry their do-not-edit marker.
  Deleting the banner does not make the file authored; it makes the next generator run delete your work silently."

note "$prog: L2a -- $n_gen projections checked, all markers intact."

if [ "$mode" = static ]; then
    note "$prog: LAYERING OK (static rules only; L2b co-change SKIPPED, not passed)."
    exit 0
fi

# L2b -- a diff touching a projection must touch its generator.
cand="$tmp/candidate.diff"
if [ -n "$diff_file" ]; then
    [ -f "$diff_file" ] || die "--diff $diff_file does not exist."
    cp "$diff_file" "$cand"
elif [ "$have_git" != yes ]; then
    die "no .git here, so the generated-file co-change rule cannot be evaluated. Pass --diff <file>, or --static-only to say so out loud."
elif [ -n "$base_rev" ]; then
    git -C "$root" rev-parse --verify "${base_rev}^{commit}" >/dev/null 2>&1 || die "--base $base_rev is not a commit."
    if ! git -C "$root" diff -U0 --no-renames "$base_rev" >"$cand"; then die "could not diff against $base_rev."; fi
else
    if ! git -C "$root" diff --cached -U0 --no-renames >"$cand"; then die "could not produce the staged diff."; fi
fi

touched="$tmp/touched.txt"
LC_ALL=C awk '/^\+\+\+ / { p = $2; sub(/^b\//, "", p); if (p != "/dev/null") print p }' "$cand" | LC_ALL=C sort -u >"$touched"
n_touched=$(LC_ALL=C awk 'END { print NR }' "$touched")

: >"$tmp/orphan.txt"
while IFS="$TAB" read -r g gen_src marker; do
    if LC_ALL=C awk -v p="$g" '$0 == p { f = 1 } END { exit f ? 0 : 1 }' "$touched"; then
        if ! LC_ALL=C awk -v p="$gen_src" '$0 == p { f = 1 } END { exit f ? 0 : 1 }' "$touched"; then
            printf '%s\t%s\n' "$g" "$gen_src" >>"$tmp/orphan.txt"
        fi
    fi
done <"$gen"

if [ -s "$tmp/orphan.txt" ]; then
    note ""
    note "generated file(s) edited without their generator:"
    LC_ALL=C awk -F'\t' '{ printf "  %s\n    generator not in this diff: %s\n", $1, $2 }' "$tmp/orphan.txt" >&2
    note ""
    die "a projection was authored outside its generator.
  The edit will work, the tests will pass, and the next generator run will
  delete it -- after the hand edit has quietly become the authority the
  generator disagrees with. Change the generator and re-project."
fi

note "$prog: L2b -- $n_touched path(s) in the candidate diff, no projection authored outside its generator."
note "$prog: LAYERING OK."
exit 0
