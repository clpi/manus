#!/bin/sh
# gate/callfold.sh — `()` never reaches place folding, and an indexed write
# still produces observable place demand.
#
# ═══ WHAT WENT WRONG, MEASURED ═════════════════════════════════════════════
#
# `src/dnir_lower.zig`'s `placeFold` is the consumer that answers a module-scope
# projection from `place.zig`'s residency fact instead of emitting a load. It
# carried three arms. Two of them were rival authorities:
#
#   `.call`  folded `t(k)` to the k-th element of `t`'s initializer. `law.md`
#            §5 is one sentence long about this: "`()` is ordinary application.
#            It never means table indexing." `place.zig` ALREADY rules that way
#            in its own walk — its `.call` arm reads callee and operands and
#            says "it is never an index" — and pins it with
#            `test "place: an ordinary call is not an indexed read"`. So one
#            question had two producers answering it two different ways.
#
#   `.name`  answered a bare module scalar's VALUE by reaching into `p.init`,
#            the initializer AST hanging off the PLACE census. `law.md` §6:
#            "value != place", "binding != place", and "Scalars … are not
#            places merely because a compiler implementation stores them."
#
# Both arms cited "§18 residency" and "§19 constant index" as their authority.
# Current `law.md` ends at §17. They were justified by a retired edition.
#
# ═══ WHY THIS GATE IS NOT BEHAVIOURAL-ONLY, AND SAYS SO ════════════════════
#
# HONEST FINDING, RECORDED SO NOBODY RE-DERIVES IT: at the revision this gate
# landed, neither deleted arm could return a value. `place.residencyRefusal`
# answers `.shape` for every scalar, so `.name` was unreachable; and naming a
# collection as a callee drives `place.zig` to publish `escape:"unknown"`,
# which `residencyRefusal` answers `.escaped`, so `.call` was unreachable too.
#
# That is NOT a reason to leave them, and it IS the reason this gate has a
# structural arm. The wrong answer was withheld by a DIFFERENT producer's
# conservatism, never by the fold's own guard, which admitted it. Restoring
# either arm changes no observable behaviour today — so a purely behavioural
# gate would be green with the defect present, which is the hollow shape
# `gate/vacuity.sh` exists to convict. The structural arm is the one that
# catches the revert; the four measured arms are what stop the structural arm
# from being a spelling check on a fact nothing produces.
#
# ═══ THE FIVE ARMS ═════════════════════════════════════════════════════════
#
#   1  PRODUCER TWO-SIDEDNESS   `s(2)` and `s[2]` differ only in the delimiter,
#                               and `escape` must DISAGREE between them. A
#                               census that cannot tell application from
#                               projection fails whichever constant it picks.
#   2  RESIDENCY, REPRODUCED    the exported row, run through the same clauses
#                               `absentModulePlace` consults: the call subject
#                               must be REFUSED (the fold cannot answer it) and
#                               the projection subject ADMITTED (it can). This
#                               decides the compiler's question from the export.
#   3  INDEXED WRITE DEMAND     `s[2] = 99` must publish `mutation:"yes"` and be
#                               REFUSED by residency — the write face is never
#                               folded away — and must DIFFER from the read-only
#                               probe, so a constant `mutation` cannot pass.
#   4  BEHAVIOURAL, TWO-SIDED   `s[2]` admitted by the direct backend, `s(2)`
#                               refused. A compiler that admits everything fails
#                               the first; one that refuses everything fails the
#                               second.
#   5  STRUCTURAL               `placeFold` dispatches on `.index` and nothing
#                               else. Non-vacuous by construction: if the
#                               function or its arms cannot be found, that is a
#                               FAIL, not a pass (GAP-201).
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
idol="${IDOL_BIN:-$root/zig-out/bin/idol}"
[ -x "$idol" ] || { echo "callfold: no compiler at $idol" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "callfold: python3 absent" >&2; exit 2; }
lower="$root/src/dnir_lower.zig"
[ -f "$lower" ] || { echo "callfold: no $lower" >&2; exit 2; }

# THE PROBES ADMIT THROUGH THE DIRECT BACKEND FIRST. `s[2]` on a determined
# module collection has to compile and answer before its refusal of `s(2)` is
# evidence about `()` at all — which the gate already knew, and said: "with
# nothing admitted, the refusal below is not evidence about `()`". True, and it
# never mentions the host, so `gate/all.sh` read a correct CANNOT MEASURE as a
# law violation. Routed through the one producer instead, per the note at the
# top of `gate/realization/direct.sh` listing the six gates that each described
# this same fact in their own words.
. "$root/gate/realization/direct.sh"
direct_native_probe "$idol"
if direct_native_absent; then
    direct_native_note 'the `()` vs `[]` admission probes (each needs a direct-backend artifact that answers)'
    exit 1
fi

probe="$(mktemp -d)" || { echo "callfold: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$probe"' EXIT

# ORDINARY APPLICATION. `s` is a module collection named as a callee.
cat > "$probe/call.id" <<'ID'
s = { 10, 20, 30 }
main: i64 = ()
    s(2)
ID

# PROJECTION. The same program, one delimiter apart.
cat > "$probe/index.id" <<'ID'
s = { 10, 20, 30 }
main: i64 = ()
    s[2]
ID

# INDEXED WRITE. The write face of the same projected place.
cat > "$probe/write.id" <<'ID'
s = { 10, 20, 30 }
main: i64 = ()
    s[2] = 99
    s[2]
ID

for f in call index write; do
  "$idol" graph "$probe/$f.id" > "$probe/$f.json" 2>/dev/null || {
    echo "callfold: FAIL — idol graph did not emit for probe $f" >&2; exit 1; }
done

# ── arm 4, measured here so python sees one verdict per probe ──────────────
# The direct backend's verdict on each spelling. Recorded as `admit`/`refuse`;
# python asserts they DISAGREE and asserts which way round.
for f in call index; do
  if ( cd "$probe" && "$idol" run "$probe/$f.id" --backend=direct >"$probe/$f.run" 2>&1 ); then
    echo admit > "$probe/$f.verdict"
  else
    echo refuse > "$probe/$f.verdict"
  fi
done

# ── arm 5 input: the `placeFold` body, sliced by brace depth ───────────────
python3 - "$lower" > "$probe/arms.txt" <<'PY'
import sys, re
src = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r'^fn placeFold\(', src, re.M)
if not m:
    print("NOFUNC"); raise SystemExit(0)
i = src.index("{", m.start())
depth, j = 0, i
while j < len(src):
    if src[j] == "{": depth += 1
    elif src[j] == "}":
        depth -= 1
        if depth == 0: break
    j += 1
body = src[i + 1:j]
# Strip comments and string literals before looking for arms, so prose about
# the DELETED arms (this file's ruling is quoted there) is never mistaken for
# one. An arm is a `.tag =>` at switch-arm depth 1 of the body.
body = re.sub(r'//[^\n]*', '', body)
body = re.sub(r'"(?:\\.|[^"\\])*"', '""', body)
depth, out, k = 0, [], 0
while k < len(body):
    c = body[k]
    if c == "{": depth += 1
    elif c == "}": depth -= 1
    elif depth == 1:
        a = re.match(r'\.([a-z_]+)\s*=>', body[k:])
        if a: out.append(a.group(1))
        e = re.match(r'else\s*=>', body[k:])
        if e: out.append("else")
    k += 1
print("\n".join(out) if out else "NOARMS")
PY

python3 - "$probe" <<'PY'
import json, os, sys

probe = sys.argv[1]
bad = 0
def fail(msg):
    global bad
    print("callfold: FAIL — " + msg)
    bad += 1

def rows(name):
    d = json.load(open(os.path.join(probe, name + ".json")))
    out = list(d.get("places", []))
    for b in d.get("bodies", []):
        out.extend(b.get("places", []))
    return [r for r in out if r.get("region") == "module"
            and r.get("shape") == "collection"]

R = {n: rows(n) for n in ("call", "index", "write")}

# GAP-201 — a gate examining zero subjects must FAIL, not pass.
for n, rs in R.items():
    if len(rs) != 1:
        fail(f"probe {n} declares exactly one module collection and the export "
             f"published {len(rs)} row(s) for it; there is nothing to decide from")
if bad:
    print("callfold: no subjects to examine"); sys.exit(1)
call, index, write = R["call"][0], R["index"][0], R["write"][0]

NEED = ("escape", "mutation", "immutability", "alias", "determinacy",
        "contents_known")
for n, r in (("call", call), ("index", index), ("write", write)):
    miss = [k for k in NEED if k not in r]
    if miss:
        fail(f"probe {n}: place row is missing {miss}; the residency clauses "
             f"cannot be reproduced from an export that does not carry them")
if bad:
    sys.exit(1)

# ── arm 1: PRODUCER TWO-SIDEDNESS ──────────────────────────────────────────
# `s(2)` and `s[2]` are one delimiter apart. `place.zig` rules that a
# collection named as a CALLEE hands its location to semantics its bounded
# walk cannot model, and that this is never an index. So `escape` must move.
if call["escape"] == index["escape"]:
    fail(f"`s(2)` and `s[2]` differ only in the delimiter and `escape` "
         f"answered {call['escape']!r} for both — a census that cannot tell "
         f"ordinary application from projection is publishing, not producing")
if index["escape"] != "no":
    fail(f"`s[2]` is a projection of a module collection nothing else names, "
         f"and `escape` answered {index['escape']!r}; if the projection side "
         f"escapes too, arm 1 above passes for the wrong reason")

# ── arm 2: RESIDENCY, REPRODUCED FROM THE EXPORT ───────────────────────────
# The same clauses `place.residencyRefusal` applies, decided here from the
# published row. This is what `absentModulePlace` consults before `placeFold`
# may answer at all.
def refusal(r):
    if r["mutation"] != "no" or r["immutability"] != "yes": return "mutated"
    if r["alias"] != "no": return "aliased"
    if r["escape"] != "no": return "escaped"
    if r["determinacy"] != "exact": return "indeterminate"
    return "none"

rc, ri, rw = refusal(call), refusal(index), refusal(write)
if rc == "none":
    fail("`s(2)` is ORDINARY APPLICATION and its place row is admitted by "
         "residency, so a fold keyed on `.call` would be reachable and would "
         "answer it — `law.md` §5: `()` never means table indexing")
if ri != "none":
    fail(f"`s[2]` is the one face `law.md` §5 gives to projection and residency "
         f"refused it ({ri}); with the projection side refused this gate's "
         f"call-side arm proves nothing")

# ── arm 3: AN INDEXED WRITE STILL PRODUCES OBSERVABLE PLACE DEMAND ─────────
if write["mutation"] != "yes":
    fail(f"`s[2] = 99` stores through a projected place and `mutation` "
         f"answered {write['mutation']!r}; an indexed write that publishes no "
         f"mutation is a place demand the census dropped")
if write["mutation"] == index["mutation"]:
    fail(f"the read-only and the written probe both answered mutation="
         f"{write['mutation']!r}; a fact that cannot tell a store from a load "
         f"is published, not produced")
if rw == "none":
    fail("`s[2] = 99` was ADMITTED by residency, so the written collection "
         "would be folded to its initializer and the store would vanish; a "
         "place with a write face is never physically absent")

# ── arm 4: BEHAVIOURAL, TWO-SIDED ──────────────────────────────────────────
v = {n: open(os.path.join(probe, n + ".verdict")).read().strip()
     for n in ("call", "index")}
if v["index"] != "admit":
    fail(f"`s[2]` on a determined module collection was {v['index']}d by the "
         f"direct backend; with nothing admitted, the refusal below is not "
         f"evidence about `()`")
if v["call"] != "refuse":
    fail(f"`s(2)` was {v['call']}ted by the direct backend — an ordinary "
         f"application of a table answered as a projection")

# ── arm 5: STRUCTURAL — the arms `placeFold` actually dispatches on ────────
arms = [a for a in open(os.path.join(probe, "arms.txt")).read().split() if a]
if arms == ["NOFUNC"]:
    fail("`fn placeFold` was not found in src/dnir_lower.zig; this gate's "
         "structural arm examined nothing")
elif arms == ["NOARMS"]:
    fail("`placeFold` was found and no switch arm could be read out of it; "
         "this gate's structural arm examined nothing")
else:
    banned = [a for a in arms if a not in ("index", "else")]
    if banned:
        fail(f"`placeFold` dispatches on {banned} beside `.index`. It is the "
             f"PLACE-PROJECTION consumer and `law.md` §5 gives projection to "
             f"`[]` alone: `.call` would make `()` mean indexing, `.name` "
             f"would answer a binding's VALUE off a place row (§6: "
             f"`value != place`). Arms read: {arms}")
    if "index" not in arms:
        fail(f"`placeFold` no longer dispatches on `.index`, so the genuinely "
             f"computed projection this consumer exists for has no arm at all. "
             f"Arms read: {arms}")

if bad:
    print(f"callfold: 3 probes, {bad} finding(s)")
    sys.exit(1)
print(f"callfold: `()` refused and `[]` admitted on one program pair "
      f"(escape {call['escape']!r} vs {index['escape']!r}; residency {rc} vs "
      f"{ri}); indexed write keeps place demand (mutation "
      f"{write['mutation']!r}, residency {rw}); placeFold arms {arms}")
PY