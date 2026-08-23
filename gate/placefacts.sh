#!/bin/sh
# gate/placefacts.sh — the place row must publish every fact a consumer decides
# from, AND must exist for every binding a consumer decides ABOUT.
#
# WHY THIS EXISTS. Three landed changes are individually easy to revert by
# hand and impossible to notice afterwards:
#
#   v9  added `immutability`, `alias`, `contents_known` to place rows, because
#       v8 published `mutation` and `escape` but not the three siblings
#       `aggregateIsSoleImmutableBinding` reads ALONGSIDE them — so no reader
#       could reproduce an admission decision from the export, and auditing
#       one required an instrumented compiler.
#   v10 added `bind_origin`, which is what stops a shadowed field write
#       finding the module's word (GAP-221).
#   and the one-producer change removed a rival `p.facts.contents_known`
#       consult that disagreed with the graph's own answer on 48 sites.
#
# A working tree carrying a -91 line revert of src/semantic_graph.zig was
# observed while these landed. Reverting them breaks no test: the export just
# gets quieter, and every audit that depends on it silently returns to
# needing an instrumented build. This gate makes that loud.
#
# ═══ THE HOLE THIS GATE USED TO HAVE ═══════════════════════════════════════
#
# It asserted six keys on every row THAT EXISTS, and could not notice that an
# entire class of binding had no row at all. Measured: `place.zig`'s
# `bindPlace` returned early on `candidateShape(...) == .unknown`, and that
# function answered `.collection`/`.record` only, so a SCALAR MODULE BINDING
# GOT NO ROW — `idol graph` printed `"places":[]` for the exact loop kernel
# whose induction variable and accumulator carry the whole cost of the program.
# Every fact was absent for exactly the bindings a register-promotion consumer
# has to decide about, and this gate reported a pass. A gate that examines the
# wrong subjects thoroughly is GAP-201 with extra steps.
#
# ═══ WHAT IT ASSERTS, AND WHAT IT REFUSES TO ═══════════════════════════════
#
# KEYS and a VERSION FLOOR, never a value for one program: values are the
# compiler's business and change with the program.
#
# But PRESENCE alone is not enough either, and this gate now says so. A fact
# published as `"unknown"` on every row — or as the same constant on every row
# — is producer-hollow, and it is WORSE than an absent key, because a consumer
# trusts it. So the value assertions here are DISTINCTIONS between two probes,
# never a pinned answer for one: two programs that differ only in whether a
# relation names a module word must publish DIFFERENT `escape`. That fails when
# the producer goes constant and passes for any honest producer, whatever it
# decides.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
idol="${IDOL_BIN:-$root/zig-out/bin/idol}"
[ -x "$idol" ] || { echo "placefacts: no compiler at $idol" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "placefacts: python3 absent" >&2; exit 2; }

probe="$(mktemp -d)"; trap 'rm -rf "$probe"' EXIT

# (1) AGGREGATE probe — the original subject. Keeps the v10 key/floor cover.
cat > "$probe/agg.id" <<'ID'
xs = { 3, 5, 8 }
main: i64 = ()
    if xs[1] > 2
        return 7
    0
ID

# (2) SCALAR probe — the class that had no rows. TWO module scalars, chosen so
#     one is stored to and one is not, inside ONE program: a producer that
#     answers `mutation` from a constant cannot pass this even by luck.
cat > "$probe/scalar.id" <<'ID'
i: i64 = 0
fixed: i64 = 7
while i < 3
    i = i + 1
print(fixed)
ID

# (3) and (4) ESCAPE PAIR — the same module word, differing only in whether a
#     relation body names it. This is the two-directional control: the pair must
#     disagree, and a producer that publishes one constant for `escape` fails
#     whichever constant it picks.
cat > "$probe/esc_no.id" <<'ID'
g: i64 = 1
print(g)
ID
cat > "$probe/esc_yes.id" <<'ID'
g: i64 = 1
peek: i64 = ()
    g
print(peek())
ID

# (5) OVER-PRODUCTION CONTROL — a module with no module SCALAR binding, but two
#     tempting near-misses: a module `str` (it has contents and a location this
#     walk does not model) and a relation-local `i64` (it dies with its frame,
#     so no second region can name it). A producer that mints a scalar row for
#     every name it sees fails here, so "add rows until the gate passes" is not
#     a way through it.
cat > "$probe/none.id" <<'ID'
ys = { 1, 2 }
label: str = "n"
main: i64 = ()
    local t: i64 = 1
    ys[1] + t
ID

for f in agg scalar esc_no esc_yes none; do
  "$idol" graph "$probe/$f.id" > "$probe/$f.json" 2>/dev/null || {
    echo "placefacts: FAIL — idol graph did not emit for probe $f" >&2; exit 1; }
done

python3 - "$probe" <<'PY'
import json, os, sys
FLOOR = 10
NEED = ["mutation", "escape", "immutability", "alias", "contents_known", "bind_origin"]
probe = sys.argv[1]
bad = 0
def load(n):
    return json.load(open(os.path.join(probe, n + ".json")))
def fail(msg):
    global bad
    print("placefacts: FAIL — " + msg)
    bad += 1

docs = {n: load(n) for n in ("agg", "scalar", "esc_no", "esc_yes", "none")}

# EVERY PLACE ROW THE EXPORT CARRIES, module census AND relation-body censuses.
# Looking only at `places[]` is how the previous version of this file let an
# over-producing walk through: a row minted for a relation-local lands in
# `bodies[*].places[]`, which nothing here read.
def rows(name):
    d = docs[name]
    out = list(d.get("places", []))
    for b in d.get("bodies", []):
        out.extend(b.get("places", []))
    return out

# ── keys and version floor, on every row of every probe ────────────────────
checked = 0
for name, d in docs.items():
    ver = d.get("version")
    if not isinstance(ver, int) or ver < FLOOR:
        fail(f"probe {name}: export version {ver!r}, floor {FLOOR}")
    for i, r in enumerate(rows(name)):
        checked += 1
        missing = [k for k in NEED if k not in r]
        if missing:
            fail(f"probe {name}: place row {i} is missing {missing}")

# GAP-201: a gate examining zero subjects must fail, not pass.
if not docs["agg"].get("places"):
    fail("probe agg produced ZERO place rows; nothing was examined")

def scalars(name):
    return [p for p in rows(name) if p.get("shape") == "scalar"]

# ── THE HOLE: a module scalar binding must HAVE a row ──────────────────────
sc = scalars("scalar")
mod_sc = [p for p in sc if p.get("region") == "module"]
if len(mod_sc) < 2:
    fail(f"probe scalar declares 2 module scalar bindings and published "
         f"{len(mod_sc)} module scalar place row(s); a binding a consumer "
         f"decides about must have a row to decide from")

# ── NON-HOLLOWNESS: the facts must vary where the program varies ───────────
muts = {p["mutation"] for p in mod_sc}
if len(muts) < 2:
    fail(f"probe scalar stores to one of its two module words and not the "
         f"other, and `mutation` answered {sorted(muts)} for both — a fact "
         f"that cannot tell them apart is published, not produced")

no_rows, yes_rows = scalars("esc_no"), scalars("esc_yes")
if not no_rows or not yes_rows:
    fail("the escape pair published no scalar rows to compare")
else:
    a = {p["escape"] for p in no_rows}
    b = {p["escape"] for p in yes_rows}
    if a == b:
        fail(f"the escape pair differs only in whether a relation names the "
             f"module word, and `escape` answered {sorted(a)} for both")

# `alias` on a scalar is two-valued on this surface — no expression produces
# the address of a binding — so `yes` is unreachable and is NOT asserted here.
# What IS asserted is that it is not stuck on `unknown`, which is the shape a
# hollow producer takes.
if mod_sc and all(p["alias"] == "unknown" for p in mod_sc):
    fail("every module scalar published alias=\"unknown\"; an unknown on every "
         "row is a fact a consumer trusts and nothing produced")

# ── OVER-PRODUCTION CONTROL ────────────────────────────────────────────────
if scalars("none"):
    fail(f"probe none has no module scalar binding — only a module `str` and a "
         f"relation-local `i64` — and published {len(scalars('none'))} scalar "
         f"place row(s)")

if bad:
    print(f"placefacts: {checked} place row(s) checked across 5 probes, {bad} finding(s)")
    sys.exit(1)
print(f"placefacts: {checked} place row(s) across 5 probes, version "
      f"{docs['agg']['version']}, all {len(NEED)} decision facts published; "
      f"{len(mod_sc)} module scalar row(s) present and two-sided")
PY
