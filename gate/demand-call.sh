#!/bin/sh
# gate/demand-call.sh — a trapping call stays a trap; a diverging call stays
# a divergence. Neither may become a successful return.
#
# The demand optimizer deletes a dead call only when the graph proves all
# three: effect-free, trap-free, provably completing. These two programs are
# effect-free but FAIL the other proofs, so the calls must survive
# optimization. If the optimizer deletes either call, the program exits 0
# and this gate fails.
#
#   hang.id: `spin()` recurses forever. The completion fact stays unknown
#            (self-cycle), so the call is kept. Run under `timeout`: a kept
#            call never exits 0; a deleted call does.
#   trap.id: `100 // zero()` divides by a runtime zero. The divisor is not a
#            nonzero literal, so the trap fact stays unknown and the call is
#            kept. A kept call traps (nonzero exit); a deleted call exits 0.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
idol="${IDOL_BIN:-$root/zig-out/bin/idol}"
[ -x "$idol" ] || { echo "demand-call: no compiler at $idol" >&2; exit 2; }
for candidate in timeout gtimeout; do
  if command -v "$candidate" >/dev/null 2>&1; then limit="$candidate"; break; fi
done
[ -n "${limit:-}" ] || { echo "demand-call: timeout command unavailable" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "demand-call: python3 absent" >&2; exit 2; }

probe="$(mktemp -d)" || { echo "demand-call: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$probe"' EXIT

# THE HANG. Effect-free, but the self-cycle withholds the completion proof.
cat > "$probe/hang.id" <<'ID'
spin: i64 = ()
    spin()

main: i64 = ()
    dead = spin()
    7
ID

# THE TRAP. Effect-free, but the divisor is a call, not a nonzero literal,
# so the trap proof is withheld. `zero` is opaque: the compiler cannot see
# through it to the zero at compile time.
cat > "$probe/trap.id" <<'ID'
zero: i64 = ()
    0

divide: i64 = (d: i64)
    100 // d

main: i64 = ()
    dead = divide(zero())
    7
ID

# ── structural arm: both applications publish effect = "none" ─────────────
# The gate's premise is that these calls are effect-free; if the graph ever
# stops saying so, the behavioral arms below prove nothing about demand.
for f in hang trap; do
  "$idol" graph "$probe/$f.id" > "$probe/$f.json" 2>/dev/null || {
    echo "demand-call: FAIL — idol graph did not emit for $f" >&2; exit 1; }
done
python3 - "$probe" <<'PY'
import json, os, sys
probe = sys.argv[1]
bad = 0
for name in ("hang", "trap"):
    d = json.load(open(os.path.join(probe, name + ".json")))
    apps = []
    for b in d.get("bodies", []):
        apps.extend(b.get("applications", []))
    apps.extend(d.get("applications", []))
    if not apps:
        print(f"demand-call: FAIL — {name}.id exported no applications; "
              f"the effect-free premise was not examined")
        bad += 1
        continue
    for a in apps:
        eff = a.get("effect")
        card = eff.get("card") if isinstance(eff, dict) else eff
        if card != "none":
            print(f"demand-call: FAIL — {name}.id application effect="
                  f"{eff!r}, not 'none'; the call is not "
                  f"effect-free and this gate's premise fails")
            bad += 1
if bad:
    sys.exit(1)
print("demand-call: both probes effect-free per graph export")
PY
[ $? -eq 0 ] || exit 1

# ── behavioral arms ───────────────────────────────────────────────────────
"$idol" compile "$probe/hang.id" -o "$probe/hang.bin" 2>"$probe/hang.build" || {
  echo "demand-call: FAIL — hang.id did not compile" >&2
  tail -5 "$probe/hang.build" >&2; exit 1; }
"$idol" compile "$probe/trap.id" -o "$probe/trap.bin" 2>"$probe/trap.build" || {
  echo "demand-call: FAIL — trap.id did not compile" >&2
  tail -5 "$probe/trap.build" >&2; exit 1; }

# The hang: a kept call never returns. `timeout` kills it (124). Exit 0
# means the optimizer deleted the recursion — the O4 violation.
"$limit" 5 "$probe/hang.bin" >"$probe/hang.out" 2>&1
hang_code=$?
if [ "$hang_code" -eq 0 ]; then
  echo "demand-call: FAIL — hang.id exited 0: the recursive call was deleted, "
  echo "  turning a hang into a return (O4 violation)" >&2
  exit 1
fi

# The trap: a kept call divides by zero. Any nonzero/abnormal exit is the
# trap surviving. Exit 0 means the optimizer deleted the division — the O2
# violation.
"$probe/trap.bin" >"$probe/trap.out" 2>&1
trap_code=$?
if [ "$trap_code" -eq 0 ]; then
  echo "demand-call: FAIL — trap.id exited 0: the dividing call was deleted, "
  echo "  turning a trap into a return (O2 violation)" >&2
  exit 1
fi

echo "demand-call: hang kept (exit $hang_code, not 0); trap kept (exit $trap_code, not 0)"
