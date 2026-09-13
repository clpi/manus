#!/bin/sh
# gate/demand-call.sh — a trapping call stays a trap; a diverging call stays
# a divergence. Neither may become a successful return.
#
# The demand optimizer deletes a dead call only when the graph proves all
# three: effect-free, trap-free, provably completing. These two programs are
# effect-free but FAIL the other proofs, so the calls must survive
# optimization. If the optimizer deletes either call, the program exits 7
# and this gate fails.
#
#   hang.id: `spin()` recurses forever. The completion fact stays unknown
#            (self-cycle), so the call is kept. A kept call never completes
#            inside the window; a deleted call returns 7.
#   trap.id: `100 // zero()` divides by a runtime zero. The divisor is not a
#            nonzero literal, so the trap fact stays unknown and the call is
#            kept. A kept call dies by the designated trap (SIGABRT); a
#            deleted call returns 7.
#
# ── why this file was rewritten (2026-09-12 external audit, repair stream H1)
#
# The previous revision classified only "exit 0" versus "everything else": any
# nonzero exit counted as "trap or hang preserved", and the executable was
# never required to exist. Two reproductions from the audit, both confirmed
# against this gate's old arms before the rewrite:
#
#   (a) a program that simply returns 7 passed the trap arm — exit 7 is
#       nonzero, so a DELETED dividing call read as a preserved trap;
#   (b) a missing executable passed the hang arm under GNU timeout semantics
#       (127 accepted as "hang preserved"); on this host's perl timeout shim
#       the same absence exits 0 and was MISREPORTED as an O4 violation.
#
# Both directions of the error come from one conflation: "nonzero exit" was
# read as "trap preserved". This revision never does that. Every run is
# classified into exactly one of four outcomes, and every observation names
# the executable it was read from — no unattributed exit codes:
#
#   normal-completion exit=N exe=PATH   the process exited with status N
#   designated-trap SIGABRT exe=PATH    the process died by the compiler's
#                                       designated divide-by-zero trap
#   bounded-noncompletion window=Ws     the process was still running when
#     exe=PATH                          the window elapsed and the harness
#                                       killed it
#   infrastructure-failure reason=...   the executable was missing, the
#     exe=PATH                          compile produced nothing, or the
#                                       process died in a way no probe explains
#
# THE DESIGNATED TRAP is SIGABRT, not "any signal". The backend emits an
# explicit zero-divisor guard for `//`: compare, branch to a diagnostic
# write, kill(self, SIGABRT), brk fallback. gate/divisor.sh independently
# records "SIGABRT, exit 134" as the owed fault for `//` by zero. Pinning the
# signal is the point: a future backend that answers 0, exits 3, or hangs
# must fail this gate loudly, not be absorbed into "nonzero, fine".
#
# HONESTY ABOUT THE WINDOW: a 5s timeout establishes noncompletion WITHIN 5s.
# It is not proof of divergence, and this gate never claims it is. The
# outcome is named bounded-noncompletion, and the verdict line says so.
#
# ── the probes and what each one is for ────────────────────────────────────
#
#   hang / trap   preservation probes: the facts withhold the deletion proof
#                 (trap and completion cards read `unknown`), so the call must
#                 be kept. Expected: bounded-noncompletion / designated-trap.
#   safe          safe-deletion probe: `dead = add(40, 2)` is effect-free and
#                 the compiler legitimately eliminates the dead call (inlined,
#                 folded, main answers 7 with no call in it). Expected:
#                 normal-completion exit 7. This is the anti-degeneration
#                 probe: the gate must not become "every program must trap".
#   control       deleted-call control: the audit's reproduction (a) frozen —
#                 the prohibited call deleted, the program returns 7. It is
#                 run through BOTH preservation expectations and the gate
#                 REQUIRES both to reject it. A classifier that ever accepts
#                 normal completion as "preserved" fails this gate.
#
# The control and the safe probe are behaviorally identical (both exit 7).
# That is deliberate: it proves the verdicts come from the expectation each
# probe carries — derived from source semantics plus the graph facts — and
# never from the raw exit code alone.
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
idol="${IDOL_BIN:-$root/zig-out/bin/idol}"
[ -x "$idol" ] || { echo "demand-call: no compiler at $idol" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "demand-call: python3 absent" >&2; exit 2; }

# One producer for "can this host realize direct native code". A host that
# cannot build the subjects measures nothing; that is exit 2, not a pass.
. "$root/gate/realization/direct.sh"
direct_native_probe "$idol"
if direct_native_absent; then
  direct_native_note 'the trap/hang/safe/control outcomes are read from four EXECUTED binaries, none of which can be built'
  exit 2
fi

probe="$(mktemp -d)" || { echo "demand-call: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$probe"' EXIT INT TERM

fail=0
note() { printf 'demand-call: %s\n' "$1"; }
bad()  { printf 'demand-call: FAIL — %s\n' "$1" >&2; fail=1; }

# ── subjects ──────────────────────────────────────────────────────────────
# hang.id and trap.id are byte-identical to the pre-audit gate: the
# legitimate cases this gate passed before must keep passing.

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

# THE SAFE DELETION. `add(40, 2)` is effect-free and dead; the compiler
# legitimately eliminates the call (inlined and folded — the shipped main
# is `mov x0, #7; ret` with no call in it) and the program answers 7.
cat > "$probe/safe.id" <<'ID'
add: i64 = (a: i64, b: i64)
    a + b

main: i64 = ()
    dead = add(40, 2)
    7
ID

# THE CONTROL. The audit's reproduction (a), frozen: the prohibited call
# deleted, the program returns 7 normally. Under a preservation expectation
# this MUST be rejected — it is what a deleted trap/hang call looks like.
cat > "$probe/control.id" <<'ID'
main: i64 = ()
    7
ID

# ── structural arm: the facts, by checked call index ──────────────────────
# The gate's premise is that the hang/trap calls are effect-free (effect
# card `none`) while the trap and completion proofs are WITHHELD (cards read
# `unknown`, never `none`) — that withholding is what obliges the optimizer
# to keep them. The graph spells the trap card `witness` and the completion
# card `realization`. Each checked call is identified by (target, caller)
# function name and its application index is reported, so no fact is ever
# attributed to "some call".
for f in hang trap safe control; do
  "$idol" graph "$probe/$f.id" > "$probe/$f.json" 2>/dev/null || {
    bad "$f.id: idol graph did not emit"; }
done
[ "$fail" -eq 0 ] || exit 1
python3 - "$probe" <<'PY'
import json, os, sys
probe = sys.argv[1]
# name -> (target fn, caller fn, required cards); None = expect no applications
specs = {
    "hang":    ("spin",   "main", {"effect": "none", "witness": "!none", "realization": "!none"}),
    "trap":    ("divide", "main", {"effect": "none", "witness": "!none", "realization": "!none"}),
    "safe":    ("add",    "main", {"effect": "none"}),
    "control": None,
}
bad = 0
for name, spec in specs.items():
    d = json.load(open(os.path.join(probe, name + ".json")))
    nodes = {n["id"]: n for n in d.get("nodes", [])}
    apps = d.get("applications", [])
    if spec is None:
        if apps:
            print(f"demand-call: FAIL — control.id exports {len(apps)} applications; "
                  f"the control must be the deleted form, with no call left to check")
            bad += 1
        else:
            print(f"demand-call: control.id exports no applications — the deleted form, as intended")
        continue
    target_fn, caller_fn, want = spec
    hit = None
    for a in apps:
        t = a.get("target", {})
        tid = t.get("id") if isinstance(t, dict) else None
        c = a.get("caller")
        if (isinstance(nodes.get(tid), dict) and nodes[tid].get("name") == target_fn
                and isinstance(nodes.get(c), dict) and nodes[c].get("name") == caller_fn):
            hit = a
            break
    if hit is None:
        print(f"demand-call: FAIL — {name}.id: no application calls {target_fn} from {caller_fn}; "
              f"the checked call is absent, so the facts below qualify nothing")
        bad += 1
        continue
    cards = {}
    for fact in ("effect", "witness", "realization"):
        v = hit.get(fact)
        cards[fact] = v.get("card") if isinstance(v, dict) else v
    for fact, need in want.items():
        got = cards.get(fact)
        if need == "!none":
            ok = got != "none"
        else:
            ok = got == need
        if not ok:
            print(f"demand-call: FAIL — {name}.id application {hit.get('application')}: "
                  f"{fact} card is {got!r}, required {need}")
            bad += 1
    label = {"witness": "trap", "realization": "completion"}.get
    print(f"demand-call: {name}.id checked call application {hit.get('application')} "
          f"({target_fn} from {caller_fn}): effect={cards.get('effect')} "
          f"trap={cards.get('witness')} completion={cards.get('realization')}")
if bad:
    sys.exit(1)
PY
[ $? -eq 0 ] || exit 1

# ── compile arm: the executable must exist ─────────────────────────────────
# A compile that "succeeds" without producing the executable is the audit's
# reproduction (b). The host was already proven capable above, so on this
# host that is a compiler defect, not a host limit.
for f in hang trap safe control; do
  if ! "$idol" compile "$probe/$f.id" -o "$probe/$f.bin" >"$probe/$f.build" 2>&1; then
    bad "$f.id did not compile — the subject does not exist, so nothing below is measured"
    tail -5 "$probe/$f.build" >&2
  elif [ ! -s "$probe/$f.bin" ]; then
    bad "$f.id: the compiler reported success but produced no executable at $probe/$f.bin"
  fi
done
[ "$fail" -eq 0 ] || exit 1

# ── behavioral arm: one of four outcomes, never "nonzero, fine" ────────────
# run_bounded <exe> <seconds> <outfile>
# Classifies the run into exactly one outcome. The executable is named in
# every observation. No `timeout(1)` is used: this host's `timeout` is a
# perl shim whose exit codes are unreliable (missing binary -> 0, timed-out
# process -> 142), so the harness implements its own bounded run and reads
# the wait status directly.
#
# A killer subshell touches <outfile>.marker when the window elapses. A
# SIGTERM/SIGKILL death counts as bounded-noncompletion ONLY if the marker
# fired — a process that kills itself with SIGTERM before the deadline is
# infrastructure-failure, not "did not complete". The window is reported
# honestly: noncompletion within it, never proof of divergence.
run_bounded() {
  _exe=$1; _secs=$2; _out=$3; _marker="$_out.marker"
  if [ ! -f "$_exe" ]; then
    echo "outcome=infrastructure-failure reason=executable-missing exe=$_exe"; return 0
  fi
  if [ ! -x "$_exe" ]; then
    echo "outcome=infrastructure-failure reason=executable-not-executable exe=$_exe"; return 0
  fi
  rm -f "$_marker"
  "$_exe" >"$_out" 2>&1 & _pid=$!
  ( sleep "$_secs"; touch "$_marker"; kill -TERM "$_pid" 2>/dev/null;
    sleep 2; kill -KILL "$_pid" 2>/dev/null ) & _killer=$!
  wait "$_pid"; _code=$?
  kill "$_killer" 2>/dev/null
  wait "$_killer" 2>/dev/null
  if [ "$_code" -lt 128 ]; then
    echo "outcome=normal-completion exit=$_code exe=$_exe"
  else
    _sig=$((_code - 128))
    if [ -f "$_marker" ] && { [ "$_sig" -eq 15 ] || [ "$_sig" -eq 9 ]; }; then
      echo "outcome=bounded-noncompletion window=${_secs}s exe=$_exe"
    elif [ "$_sig" -eq 6 ]; then
      echo "outcome=designated-trap signal=SIGABRT exe=$_exe"
    else
      echo "outcome=infrastructure-failure reason=signal-$_sig exe=$_exe"
    fi
  fi
}

_outcome_kind() { # <outcome line> -> kind
  case $1 in outcome=*) _k=${1%% *}; _k=${_k#outcome=}; printf '%s' "$_k";; *) printf 'malformed';; esac
}

# expect <label> <outcome> <kind> [detail]: the outcome must BE the kind.
expect() {
  _label=$1; _outcome=$2; _kind=$3; _detail=${4:-}
  _got=$(_outcome_kind "$_outcome")
  _ok=1
  [ "$_got" = "$_kind" ] || _ok=0
  if [ -n "$_detail" ] && [ $_ok -eq 1 ]; then
    case " $_outcome " in *" $_detail "*) ;; *) _ok=0;; esac
  fi
  if [ $_ok -eq 1 ]; then
    note "$_label: $_outcome"
  else
    bad "$_label: expected ${_kind}${_detail:+ }${_detail}, observed: $_outcome"
  fi
}

# expect_reject <label> <outcome> <kind>: the outcome must NOT be the kind.
# Used for the deleted-call control: normal completion presented where
# preservation was demanded must be rejected, never absorbed.
expect_reject() {
  _label=$1; _outcome=$2; _kind=$3
  _got=$(_outcome_kind "$_outcome")
  if [ "$_got" = "$_kind" ]; then
    bad "$_label: the control was ACCEPTED as '$_kind' — observed: $_outcome. The gate has no teeth."
  else
    note "$_label: control rejected as required (observed: $_outcome)"
  fi
}

WINDOW=5

hang_outcome=$(run_bounded "$probe/hang.bin" "$WINDOW" "$probe/hang.out")
# A kept recursive call never completes inside the window. Exit 0/7 here
# would mean the optimizer deleted the recursion — the O4 violation — and
# anything else (trap, missing binary) is its own named outcome, not "kept".
expect "hang" "$hang_outcome" "bounded-noncompletion"
note "hang: did not complete within ${WINDOW}s — the window, not proof of divergence"

trap_outcome=$(run_bounded "$probe/trap.bin" "$WINDOW" "$probe/trap.out")
# A kept dividing call dies by the designated trap. Exit 7 here would mean
# the optimizer deleted the division — the O2 violation — and the old gate
# would have passed it as "trap preserved" (audit reproduction (a)).
expect "trap" "$trap_outcome" "designated-trap" "signal=SIGABRT"

safe_outcome=$(run_bounded "$probe/safe.bin" "$WINDOW" "$probe/safe.out")
# The safely deleted call: the program answers 7. The gate must pass this —
# legitimate optimization is not a violation.
expect "safe-deletion" "$safe_outcome" "normal-completion" "exit=7"

control_outcome=$(run_bounded "$probe/control.bin" "$WINDOW" "$probe/control.out")
# The deleted-call control, through both preservation expectations. It
# completes normally with exit 7 — exactly what the old gate accepted — and
# both expectations must reject it.
expect_reject "control-as-deleted-hang" "$control_outcome" "bounded-noncompletion"
expect_reject "control-as-deleted-trap" "$control_outcome" "designated-trap"

if [ "$fail" -eq 0 ]; then
  note "DEMAND-CALL OK — hang kept (bounded noncompletion), trap kept (SIGABRT), safe deletion passes, deleted-call control rejected"
  exit 0
fi
note "DEMAND-CALL BLOCKED."
exit 1
