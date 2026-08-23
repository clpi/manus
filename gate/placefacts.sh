#!/bin/sh
# gate/placefacts.sh — the place row must publish every fact a consumer decides from.
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
# It asserts the KEYS and the VERSION FLOOR, not any particular value —
# values are the compiler's business and change with the program.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
idol="${IDOL_BIN:-$root/zig-out/bin/idol}"
[ -x "$idol" ] || { echo "placefacts: no compiler at $idol" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "placefacts: python3 absent" >&2; exit 2; }

probe="$(mktemp -d)"; trap 'rm -rf "$probe"' EXIT
cat > "$probe/p.id" <<'ID'
xs = { 3, 5, 8 }
main: i64 = ()
    if xs[1] > 2
        return 7
    0
ID

"$idol" graph "$probe/p.id" > "$probe/g.json" 2>/dev/null || {
  echo "placefacts: FAIL — idol graph did not emit for the probe" >&2; exit 1; }

python3 - "$probe/g.json" <<'PY'
import json, sys
FLOOR = 10
NEED = ["mutation", "escape", "immutability", "alias", "contents_known", "bind_origin"]
d = json.load(open(sys.argv[1]))
ver = d.get("version")
rows = d.get("places", [])
bad = 0
if not isinstance(ver, int) or ver < FLOOR:
    print(f"placefacts: FAIL — export version {ver!r}, floor {FLOOR}"); bad += 1
# GAP-201: a gate examining zero subjects must fail, not pass.
if not rows:
    print("placefacts: FAIL — probe produced ZERO place rows; nothing was examined"); bad += 1
for i, r in enumerate(rows):
    missing = [k for k in NEED if k not in r]
    if missing:
        print(f"placefacts: FAIL — place row {i} is missing {missing}"); bad += 1
if bad:
    print(f"placefacts: {len(rows)} place row(s) checked, {bad} finding(s)")
    sys.exit(1)
print(f"placefacts: {len(rows)} place row(s), version {ver}, all {len(NEED)} decision facts published")
PY
