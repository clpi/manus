#!/bin/sh
# gate/vocabulary.sh — fail-closed graph-backed declaration admission.
#
# Added module-scope declarations remain frozen unless the production semantic
# graph proves the exact relation identity. A relation witness requires one
# module-scope graph entity selected only as provenance, plus an exact Idol
# callable-linkage fact and an exact body fact keyed by that same id under the
# current source-law edition. Removing any one of those facts is a planted
# negative control and must make the witness disappear.
#
# Cases, descriptors, and value bindings remain fail-closed: their corresponding
# graph reach/cardinality projection is not exported yet. This gate keeps no
# admitted-word list, never treats source spelling as identity, and never reads
# NodeKind alone as semantic proof.
#
# A graph entity proves that the parser accepted a spelling. It does not prove
# the spelling is a NAME. LAW-16 admits one irreducible lowercase word; a
# spelling outside that class is FOREIGN EXACT BYTES, and the only fact that
# makes those bytes meaningful is a real foreign binding carrying them --
# `c` origin, `c_import` exposure, symbol byte-equal to the name. Measured on
# this tree: `first_value` and `firstvalue` were both graph-proven for the same
# file, which is admission by parser theater rather than by identity.
#
# Mashing is NOT decided here and cannot be: `strlen` carries no seam, so no
# lexical test separates it from a word. What IS decided is that two byte-
# different spellings are two identities. Nothing below folds, strips, or
# normalizes a spelling, so neither `first_value` nor `firstvalue` can ever
# inherit the other's witness.
#
# A refusal is SEMANTIC-VOCABULARY-BLOCKED: improve the fact producer and this
# consumer. Do not edit a registry to make a word pass.

set -eu

prog=$(basename "$0")
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
subject="$here/subject.sh"
extract="$here/vocab-extract.awk"
idol=${IDOL:-$root/zig-out/bin/idol}
case "$idol" in
    /*) ;;
    *) idol="$root/${idol#./}" ;;
esac

tmp=$(mktemp -d "${TMPDIR:-/tmp}/idol-vocabulary.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM
die() { printf '%s\n' "VOCABULARY BLOCKED -- $*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

[ -x "$subject" ] || die "gate/subject.sh is missing or not executable"
[ -f "$extract" ] || die "the conservative declaration classifier is missing"
(cd "$root" && sh "$subject" --tree) >/dev/null || die "candidate admission requires a real Git work tree (GAP-220)"
(cd "$root" && sh "$subject" '*.id') >/dev/null || die "Idol source enumeration failed or produced zero subjects (GAP-201)"

diff_file=""
base_rev=""
selftest=0
while [ $# -gt 0 ]; do
    case "$1" in
        --base) shift; [ $# -gt 0 ] || die "--base needs a revision"; base_rev=$1 ;;
        --diff) shift; [ $# -gt 0 ] || die "--diff needs a path"; diff_file=$1 ;;
        --selftest) selftest=1 ;;
        -h|--help) sed -n '1,26p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done
[ -z "$diff_file" ] || [ -z "$base_rev" ] || die "--base and --diff are mutually exclusive"
[ "$selftest" -eq 0 ] || { [ -z "$diff_file" ] && [ -z "$base_rev" ]; } || die "--selftest takes no --base/--diff"

if [ "$selftest" -eq 1 ]; then
    positive="$tmp/positive.diff"
    missing="$tmp/missing.diff"
    descriptor="$tmp/descriptor.diff"
    outside="$tmp/outside.id"
    escape="$tmp/escape.diff"
    # Three declarations that ALREADY EXIST in this tree, so each case is the
    # real graph answering rather than a fixture agreeing with itself.
    bound="$tmp/bound.diff"
    aliased="$tmp/aliased.diff"
    bytes="$tmp/bytes.diff"
    printf '%s\n' \
        'diff --git a/lib/compiler/parser.id b/lib/compiler/parser.id' \
        '--- a/lib/compiler/parser.id' \
        '+++ b/lib/compiler/parser.id' \
        '@@ -0,0 +1 @@' \
        '+eval: i64 = (src: str)' >"$positive"
    printf '%s\n' \
        'diff --git a/lib/compiler/parser.id b/lib/compiler/parser.id' \
        '--- a/lib/compiler/parser.id' \
        '+++ b/lib/compiler/parser.id' \
        '@@ -0,0 +1 @@' \
        '+ghost = (value: i64)' >"$missing"
    printf '%s\n' \
        'diff --git a/lib/compiler/parser.id b/lib/compiler/parser.id' \
        '--- a/lib/compiler/parser.id' \
        '+++ b/lib/compiler/parser.id' \
        '@@ -0,0 +1 @@' \
        '+ghost: { value: i64 }' >"$descriptor"
    printf '%s\n' \
        'eval: i64 = (src: str)' \
        '  0' >"$outside"
    printf '%s\n' \
        'diff --git a/lib/sqlite.id b/lib/sqlite.id' \
        '--- a/lib/sqlite.id' \
        '+++ b/lib/sqlite.id' \
        '@@ -0,0 +1 @@' \
        '+sqlite3_open: int = (path: str, db: any)' >"$bound"
    printf '%s\n' \
        'diff --git a/vendor/mathc.id b/vendor/mathc.id' \
        '--- a/vendor/mathc.id' \
        '+++ b/vendor/mathc.id' \
        '@@ -0,0 +1 @@' \
        '+sin_c: f64 = (x: f64)' >"$aliased"
    printf '%s\n' \
        'diff --git a/lib/compiler/parser.id b/lib/compiler/parser.id' \
        '--- a/lib/compiler/parser.id' \
        '+++ b/lib/compiler/parser.id' \
        '@@ -0,0 +1 @@' \
        '+is_digit: i64 = (c: i64)' >"$bytes"
    printf '%s\n' \
        'diff --git a/lib/compiler/parser.id b/lib/compiler/parser.id' \
        '--- a/lib/compiler/parser.id' \
        "+++ $outside" \
        '@@ -0,0 +1 @@' \
        '+eval: i64 = (src: str)' >"$escape"
    IDOL="$idol" sh "$0" --diff "$positive" >/dev/null 2>&1 \
        || die "selftest: a real graph-proven relation was refused"
    if IDOL="$idol" sh "$0" --diff "$missing" >/dev/null 2>&1; then
        die "selftest: a relation absent from the graph was admitted"
    fi
    if IDOL="$idol" sh "$0" --diff "$descriptor" >/dev/null 2>&1; then
        die "selftest: a descriptor without a graph reach projection was admitted"
    fi
    if IDOL="$tmp/missing-idol" sh "$0" --diff "$positive" >/dev/null 2>&1; then
        die "selftest: a missing graph producer was accepted"
    fi
    if IDOL="$idol" sh "$0" --diff "$escape" >/dev/null 2>&1; then
        die "selftest: a diff path outside the repository was admitted"
    fi
    IDOL="$idol" sh "$0" --diff "$bound" >/dev/null 2>&1 \
        || die "selftest: a real foreign binding was refused its own exact bytes"
    if IDOL="$idol" sh "$0" --diff "$aliased" >/dev/null 2>&1; then
        die "selftest: foreign bytes were admitted against a different bound symbol"
    fi
    if IDOL="$idol" sh "$0" --diff "$bytes" >/dev/null 2>&1; then
        die "selftest: foreign exact bytes were admitted on an Idol callable"
    fi
    note "vocabulary selftest: PASS (real relation; missing relation; descriptor; missing compiler; path escape; bound foreign bytes; aliased symbol; unbound foreign bytes)"
    exit 0
fi

cand="$tmp/candidate.diff"
if [ -n "$diff_file" ]; then
    [ -f "$diff_file" ] || die "--diff $diff_file does not exist"
    cp "$diff_file" "$cand"
elif [ -n "$base_rev" ]; then
    git -C "$root" rev-parse --verify "${base_rev}^{commit}" >/dev/null 2>&1 || die "--base $base_rev is not a commit"
    git -C "$root" diff --no-ext-diff --no-textconv -U0 --no-renames --diff-filter=ACMR "$base_rev" -- '*.id' >"$cand" \
        || die "could not produce the candidate diff"
else
    git -C "$root" diff --cached --no-ext-diff --no-textconv -U0 --no-renames --diff-filter=ACMR -- '*.id' >"$cand" \
        || die "could not produce the staged diff"
fi

new="$tmp/declarations"
LC_ALL=C awk -v MODE=diff -f "$extract" "$cand" >"$new" || die "declaration scan aborted"
n_new=$(LC_ALL=C awk 'END { print NR + 0 }' "$new")
n_lines=$(LC_ALL=C awk 'END { print NR + 0 }' "$cand")

if [ "$n_new" -gt 0 ]; then
    [ -x "$idol" ] || die "graph witness needs an executable compiler: $idol"
    witness="$tmp/witness"
    if python3 - "$new" "$root" "$idol" >"$witness" 2>&1 <<'PY'
from copy import deepcopy
from pathlib import Path
import json
import re
import subprocess
import sys

rows_path, root_text, idol = sys.argv[1:]
root = Path(root_text).resolve()
rows = []
for raw in Path(rows_path).read_text().splitlines():
    if not raw:
        continue
    kind, name, file = raw.split("\t", 2)
    rows.append((kind, name, file))

graphs = {}
proven = []
unproven = []


def validate_graph(graph):
    if graph.get("schema") != "idol.graph.v1" or graph.get("version") != 17:
        raise ValueError("graph schema/version")
    law = graph.get("root_source_law")
    if not isinstance(law, dict):
        raise ValueError("root source law absent")
    if law.get("card") != "one" or law.get("family") != "idol":
        raise ValueError("root source law cardinality/family")
    if law.get("schema") != "idol.source.law.v1":
        raise ValueError("root source law schema")
    if re.fullmatch(r"[0-9a-f]{64}", str(law.get("sha256", ""))) is None:
        raise ValueError("root source law digest")
    nodes = graph.get("nodes")
    links = graph.get("callable_linkages")
    bodies = graph.get("bodies")
    if not isinstance(nodes, list) or not isinstance(links, list) or not isinstance(bodies, list):
        raise ValueError("relation fact columns absent")
    if not any(n.get("id") == 0 and n.get("kind") == "module" for n in nodes):
        raise ValueError("module root absent")


NATIVE_WORD = re.compile(r"[a-z][a-z0-9]*")
NATIVE_EXPOSURE = {"internal", "compat_export", "c_export"}


def admits(name, linkage):
    """Why this linkage cannot admit this exact spelling, or None when it can.

    The asymmetry is the point. A native word is VOCABULARY and the symbol
    behind it is REALIZATION, so `open` stays admissible in front of a
    `sqlite3_open` import -- refusing that would push authors toward the
    foreign spelling, which is the opposite of the law. Foreign bytes have no
    such freedom: the one fact that makes them a name is a binding that IS
    them, so a name aliasing a different symbol (`sin_c` over `sin`, live in
    vendor/mathc.id) is refused with the repair named.
    """
    origin = linkage.get("origin")
    exposure = linkage.get("exposure")
    native = NATIVE_WORD.fullmatch(name) is not None
    if origin == "idol" and exposure in NATIVE_EXPOSURE:
        if native:
            return None
        return "foreign exact bytes on an Idol callable; LAW-16 admits one lowercase word, or bind the bytes"
    if origin == "c" and exposure == "c_import":
        symbol = linkage.get("symbol")
        if native or symbol == name:
            return None
        return f"foreign spelling is not the bound symbol {symbol!r}; spell the bytes or spell a word"
    return f"linkage {origin!r}/{exposure!r} is not an admitted callable boundary"


def relation_witness(graph, name):
    validate_graph(graph)
    body_ids = {row.get("relation") for row in graph["bodies"]}
    links = {}
    for row in graph["callable_linkages"]:
        links.setdefault(row.get("callable"), []).append(row)
    candidates = []
    refused = []
    for node in graph["nodes"]:
        # Name selects the source occurrence for this gate only. Exact graph id,
        # body, linkage, root scope, and source law establish the witness.
        if node.get("name") != name or node.get("scope") != 0:
            continue
        entity = node.get("id")
        if entity not in body_ids:
            continue
        rows = links.get(entity, [])
        if len(rows) != 1:
            continue
        linkage = rows[0]
        why = admits(name, linkage)
        if why is not None:
            refused.append(why)
            continue
        candidates.append(entity)
    if len(candidates) == 1:
        return candidates[0], None
    if candidates:
        return None, "ambiguous root-scoped witness"
    if refused:
        return None, refused[0]
    return None, "no unique root-scoped Idol linkage+body witness"


def graph_for(file):
    if file in graphs:
        return graphs[file]
    path = (root / file).resolve()
    if not path.is_relative_to(root):
        raise ValueError(f"source escapes repository: {file}")
    if not path.is_file():
        raise ValueError(f"source missing: {file}")
    run = subprocess.run([idol, "graph", str(path)], capture_output=True, text=True)
    if run.returncode != 0:
        first = run.stderr.splitlines()[0] if run.stderr.splitlines() else "no diagnostic"
        raise ValueError(f"graph refused {file}: rc={run.returncode}: {first}")
    try:
        graph = json.loads(run.stdout)
    except Exception as exc:
        raise ValueError(f"graph JSON refused {file}: {type(exc).__name__}") from exc
    validate_graph(graph)
    graphs[file] = graph
    return graph

for kind, name, file in rows:
    if kind != "relation":
        unproven.append((kind, name, file, "no graph-backed admission for this declaration kind"))
        continue
    try:
        graph = graph_for(file)
        entity, why = relation_witness(graph, name)
    except Exception as exc:
        unproven.append((kind, name, file, str(exc)))
        continue
    if entity is None:
        unproven.append((kind, name, file, why))
    else:
        proven.append((kind, name, file, entity, graph))

if unproven:
    print("unproven module-scope declarations:")
    for kind, name, file, why in unproven:
        print(f"  {kind:12} {name:28} {file} — {why}")
    raise SystemExit(1)

# Non-vacuity controls over the first real witness. Each damaged graph must lose
# the witness; otherwise a missing semantic column could still pass this gate.
kind, name, file, entity, graph = proven[0]
for label, damage in (
    ("body", lambda g: g.__setitem__("bodies", [x for x in g["bodies"] if x.get("relation") != entity])),
    ("linkage", lambda g: g.__setitem__("callable_linkages", [x for x in g["callable_linkages"] if x.get("callable") != entity])),
    ("exposure", lambda g: [x.__setitem__("exposure", "unknown") for x in g["callable_linkages"] if x.get("callable") == entity]),
    ("root-scope", lambda g: [n.__setitem__("scope", entity) for n in g["nodes"] if n.get("id") == entity]),
):
    damaged = deepcopy(graph)
    damage(damaged)
    if relation_witness(damaged, name)[0] is not None:
        print(f"control failed: damaged {label} still witnesses {name}")
        raise SystemExit(1)
damaged = deepcopy(graph)
damaged["version"] = 16
try:
    validate_graph(damaged)
except ValueError:
    pass
else:
    print("control failed: future graph schema version was accepted")
    raise SystemExit(1)
damaged = deepcopy(graph)
damaged["root_source_law"]["card"] = "unknown"
try:
    validate_graph(damaged)
except ValueError:
    pass
else:
    print("control failed: damaged source-law cardinality was accepted")
    raise SystemExit(1)

# IDENTITY CONTROLS over the same first witness. The four above prove a missing
# semantic column loses the witness; these prove a spelling cannot borrow one.
# `seam` and `mash` are two byte-different neighbours of the proven name, and
# the pair is the counterexample this gate exists for: one carries foreign
# bytes, the other does not, and neither is the other.
seam = name + "_x"
mash = seam.replace("_", "")


def respell(g, spelling, **linkage):
    out = deepcopy(g)
    for node in out["nodes"]:
        if node.get("id") == entity:
            node["name"] = spelling
    for row in out["callable_linkages"]:
        if row.get("callable") == entity:
            row.update(linkage)
    return out


renamed = respell(graph, seam)
for borrower in (name, mash):
    if relation_witness(renamed, borrower)[0] is not None:
        print(f"control failed: {seam} witnessed the different identity {borrower}")
        raise SystemExit(1)
if relation_witness(renamed, seam)[0] is not None:
    print(f"control failed: foreign exact bytes {seam} were admitted with no foreign binding")
    raise SystemExit(1)
bound = respell(graph, seam, origin="c", exposure="c_import", symbol=seam)
if relation_witness(bound, seam)[0] is None:
    print(f"control failed: a real foreign binding did not admit its own bytes {seam}")
    raise SystemExit(1)
for other in (name, mash):
    if relation_witness(bound, other)[0] is not None:
        print(f"control failed: the foreign binding for {seam} also witnessed {other}")
        raise SystemExit(1)
aliased = respell(graph, seam, origin="c", exposure="c_import", symbol=mash)
if relation_witness(aliased, seam)[0] is not None:
    print(f"control failed: foreign bytes {seam} were admitted against the symbol {mash}")
    raise SystemExit(1)

for kind, name, file, entity, _ in proven:
    print(f"graph-proven {kind:12} {name:28} {file} id={entity}")
print("vocabulary graph controls: PASS (body, linkage, exposure, root scope, schema version, source law)")
print("vocabulary identity controls: PASS (no normalization, foreign bytes need a binding, binding admits only its own bytes)")
PY
    then
        cat "$witness" >&2
    else
        cat "$witness" >&2
        die "SEMANTIC-VOCABULARY-BLOCKED: $n_new declaration(s); only exact graph-proven module relations are admitted. Cases, descriptors, bindings, missing/ambiguous linkage, missing body, invalid source-law evidence, and foreign exact bytes without a real foreign binding remain refused."
    fi
fi

note "$prog: $n_lines diff lines examined; $n_new graph-proven module-scope declaration(s)."
note "$prog: VOCABULARY GRAPH WITNESS OK."
