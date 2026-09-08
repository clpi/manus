#!/bin/sh
# gate/place/existence.sh — the existence freedom is taken from its own gate,
# not from place facts that never ask the question.
#
# ═══ WHAT WENT WRONG, MEASURED ═════════════════════════════════════════════
#
# `dnir_lower.absentModulePlace` admits a fold with exactly one guard:
#
#     if (place.residencyRefusal(p) != .none) return null;
#
# and `residencyRefusal` decides PLACE facts only — shape, value, mutation and
# rebind, alias, escape, determinacy. Physical nonexistence is a REALIZATION
# FREEDOM (law §104), and the gate on it is
# `observation.permits(report, .existence)`, whose one gating class is
# `allocation_identity`. `residencyRefusal` never consulted it. GAP-170's floor
# named this consumer by name and recorded it open: *no backend consults
# `permits`*.
#
# The two are not the same question, and this gate's second probe is a program
# where they DISAGREE: every place fact admits, and the walk cannot prove the
# module's one applied relation boundary-local, so `allocation_identity` reads
# `unknown` and the freedom is refused. Before the ruling reached the row, the
# fold answered that read as an immediate on evidence nobody had.
#
# ═══ WHY THE EXPORT AND NOT THE BACKEND ════════════════════════════════════
#
# `absentModulePlace` reads `graph.placeNamed(name)`, and the graph publishes
# that census. So the decision is reproducible from `idol graph` alone, on any
# host — including one with no direct-native realization, where the fold's
# behavioural face cannot be measured at all (`gate/realization/direct.sh`).
# The structural arm keeps that from becoming a spelling check: it requires the
# clause to be IN `residencyRefusal` and the consumer to still route through it.
#
# ═══ THE FIVE ARMS ═════════════════════════════════════════════════════════
#
#   1  PUBLISHED           every module-collection row carries `existence`.
#                          A missing key is a reader told nothing, never
#                          agreement (GAP-201: zero subjects is a FAIL).
#   2  FEATURE-USE         the folding program is `permitted` and its whole
#                          residency decision is `none`. The freedom the fold exists for
#                          is still granted, so this gate is not a ratchet that
#                          deletes the feature.
#   3  THE HOLE            the opaque-call program's PLACE clauses admit and its
#                          WHOLE decision refuses. The two reproductions must
#                          disagree on exactly this program.
#   4  THREE-VALUED        `blocked_unknown` and `blocked_observed` are different
#                          answers on different programs, so a constant refusal
#                          cannot pass arm 3; and the written probe is
#                          `permitted` while residency still refuses it, so a
#                          constant permit cannot pass arm 2 and the ruling is
#                          not an override.
#   5  STRUCTURAL          `residencyRefusal` carries the `existence` clause and
#                          `absentModulePlace` still routes through
#                          `residencyRefusal`. Not found is a FAIL.
set -u
root="$(cd "$(dirname "$0")/../.." && pwd)"
idol="${IDOL_BIN:-$root/zig-out/bin/idol}"
[ -x "$idol" ] || { echo "existence: no compiler at $idol" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "existence: python3 absent" >&2; exit 2; }
place="$root/src/place.zig"
lower="$root/src/graph/lower.zig"
[ -f "$place" ] || { echo "existence: no $place" >&2; exit 2; }
[ -f "$lower" ] || { echo "existence: no $lower" >&2; exit 2; }

probe="$(mktemp -d)" || { echo "existence: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$probe"' EXIT

# THE FOLD'S OWN PROGRAM. One module collection, one relation, one determined
# projection — the shape `gate/callfold.sh` admits through `[]`.
cat > "$probe/fold.id" <<'ID'
t = { 10, 20, 30 }
main: i64 = ()
    t[2]
ID

# THE SAME PLACE, ONE APPLIED RELATION AWAY. Every place fact is identical;
# the walk cannot prove `step` boundary-local, so nothing proves an observer
# cannot distinguish `t` existing from `t` not existing.
cat > "$probe/opaque.id" <<'ID'
t = { 10, 20, 30 }
step: i64 = (x: i64)
    x + 1
main: i64 = ()
    step(1)
    t[2]
ID

# IDENTITY CAPTURED. Handing the collection to an effect is OBSERVED, which is
# a different answer from unproven and must not collapse into it.
cat > "$probe/capture.id" <<'ID'
t = { 10, 20, 30 }
main: i64 = ()
    print(t)
    t[2]
ID

# THE WRITE FACE. The existence freedom is granted and the place is mutated:
# a permit is not an override, and the place clauses still refuse.
cat > "$probe/write.id" <<'ID'
t = { 10, 20, 30 }
main: i64 = ()
    t[2] = 99
    t[2]
ID

for f in fold opaque capture write; do
  "$idol" graph "$probe/$f.id" > "$probe/$f.json" 2>/dev/null || {
    echo "existence: FAIL — idol graph did not emit for probe $f" >&2; exit 1; }
done

# ── arm 5 input: the two source facts, read out rather than asserted ───────
python3 - "$place" "$lower" > "$probe/structure.txt" <<'PY'
import re, sys

place_src = open(sys.argv[1], encoding="utf-8", errors="replace").read()
lower_src = open(sys.argv[2], encoding="utf-8", errors="replace").read()


def body(src, head):
    m = re.search(head, src, re.M)
    if not m:
        return None
    i = src.index("{", m.start())
    depth, j = 0, i
    while j < len(src):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                break
        j += 1
    text = src[i + 1:j]
    text = re.sub(r'//[^\n]*', '', text)
    return re.sub(r'"(?:\\.|[^"\\])*"', '""', text)


refusal = body(place_src, r'^pub fn residencyRefusal\(')
absent = body(lower_src, r'^fn absentModulePlace\(')
print("refusal:" + ("MISSING" if refusal is None else
                    ("yes" if "existence" in refusal else "no")))
print("consumer:" + ("MISSING" if absent is None else
                     ("yes" if "residencyRefusal" in absent else "no")))
PY

python3 - "$probe" <<'PY'
import json, os, sys

probe = sys.argv[1]
bad = 0


def fail(msg):
    global bad
    print("existence: FAIL — " + msg)
    bad += 1


def row(name):
    d = json.load(open(os.path.join(probe, name + ".json")))
    out = list(d.get("places", []))
    for b in d.get("bodies", []):
        out.extend(b.get("places", []))
    rs = [r for r in out if r.get("region") == "module"
          and r.get("shape") == "collection"]
    if len(rs) != 1:
        fail(f"probe {name} declares exactly one module collection and the "
             f"export published {len(rs)} row(s); there is nothing to decide "
             f"from")
        return None
    return rs[0]


R = {n: row(n) for n in ("fold", "opaque", "capture", "write")}
if bad:
    print("existence: no subjects to examine")
    sys.exit(1)

# ── arm 1: PUBLISHED ───────────────────────────────────────────────────────
# Absence of the key is a v17 export answering a v18 question. It is not
# "unasked" and it is not "permitted"; it is a reader that was told nothing.
PLACE_KEYS = ("escape", "mutation", "immutability", "alias", "determinacy",
              "contents_known")
for n, r in R.items():
    miss = [k for k in PLACE_KEYS + ("existence",) if k not in r]
    if miss:
        fail(f"probe {n}: place row is missing {miss}; the residency decision "
             f"cannot be reproduced from an export that does not carry it")
if bad:
    sys.exit(1)


def places_only(r):
    """`residencyRefusal` WITHOUT its existence clause — the place facts alone,
    which is the whole decision the fold used to be admitted by."""
    if r["mutation"] != "no" or r["immutability"] != "yes":
        return "mutated"
    if r["alias"] != "no":
        return "aliased"
    if r["escape"] != "no":
        return "escaped"
    if r["determinacy"] != "exact":
        return "indeterminate"
    return "none"


def refusal(r):
    """The whole decision, existence clause last."""
    only = places_only(r)
    if only != "none":
        return only
    return "none" if r["existence"] == "permitted" else "observed"


# ── arm 2: FEATURE-USE ─────────────────────────────────────────────────────
if R["fold"]["existence"] != "permitted":
    fail(f"the folding program's module collection answered existence="
         f"{R['fold']['existence']!r}; one relation, one determined projection, "
         f"nothing written, aliased or escaping is the case the freedom exists "
         f"for, and refusing it deletes the feature this gate protects")
if refusal(R["fold"]) != "none":
    fail(f"the folding program's whole residency decision refused "
         f"({refusal(R['fold'])}); with the fold's own program refused the "
         f"disagreement below proves nothing")

# ── arm 3: THE HOLE ────────────────────────────────────────────────────────
places, whole = places_only(R["opaque"]), refusal(R["opaque"])
if places != "none":
    fail(f"the opaque-call program's place clauses answered {places!r}; this "
         f"probe exists to hold every place fact equal to the folding program "
         f"and move only the observation ruling, and it no longer does")
if whole == "none":
    fail(f"the opaque-call program was ADMITTED. Its place facts are identical "
         f"to the folding program's and the walk proved nothing about the one "
         f"relation it applies, so `allocation_identity` is unproven and the "
         f"existence freedom is not the compiler's to take "
         f"(existence={R['opaque']['existence']!r})")
if places == whole:
    fail("the place-only and whole decisions agreed on the opaque-call "
         "program, so the existence ruling changed nothing anywhere and this "
         "gate is measuring a fact no consumer reads")

# ── arm 4: THREE-VALUED ────────────────────────────────────────────────────
if R["capture"]["existence"] != "blocked_observed":
    fail(f"handing the collection to an effect answered "
         f"{R['capture']['existence']!r}; a captured identity is OBSERVED, and "
         f"a ruling that cannot tell that from unproven is published, not "
         f"produced")
if R["capture"]["existence"] == R["opaque"]["existence"]:
    fail(f"the captured and the unproven program both answered "
         f"{R['opaque']['existence']!r}; a constant refusal passes arm 3 for "
         f"the wrong reason")
if R["write"]["existence"] != "permitted":
    fail(f"the written program answered existence={R['write']['existence']!r}; "
         f"this probe exists to carry a GRANTED freedom beside a refusing place "
         f"fact, and without it a constant permit passes arm 2")
if refusal(R["write"]) == "none":
    fail("the written program was admitted; `t[2] = 99` stores through the "
         "place, and a granted existence freedom is not permission to overrule "
         "a place fact")

# ── arm 5: STRUCTURAL ──────────────────────────────────────────────────────
st = dict(line.split(":", 1) for line in
          open(os.path.join(probe, "structure.txt")).read().split())
if st.get("refusal") == "MISSING":
    fail("`pub fn residencyRefusal` was not found in src/place.zig; this "
         "gate's structural arm examined nothing")
elif st.get("refusal") != "yes":
    fail("`residencyRefusal` no longer reads `existence`, so the ruling the "
         "rows above carry reaches no consumer and the place clauses are the "
         "whole decision again")
if st.get("consumer") == "MISSING":
    fail("`fn absentModulePlace` was not found in src/graph/lower.zig; this "
         "gate's structural arm examined nothing")
elif st.get("consumer") != "yes":
    fail("`absentModulePlace` no longer routes through `residencyRefusal`, so "
         "the fold takes the existence freedom from somewhere this gate cannot "
         "see")

if bad:
    print(f"existence: 4 probes, {bad} finding(s)")
    sys.exit(1)
print(f"existence: fold {R['fold']['existence']}/{refusal(R['fold'])}, "
      f"opaque {R['opaque']['existence']} (places {places_only(R['opaque'])}, "
      f"whole {refusal(R['opaque'])}), capture {R['capture']['existence']}, "
      f"write {R['write']['existence']}/{refusal(R['write'])}")
PY
