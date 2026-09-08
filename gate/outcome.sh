#!/bin/sh
# gate/outcome.sh — `idol run` reports the GUEST's outcome, or refuses to report one.
#
#   sh gate/outcome.sh
#
# Compilation, artifact, and execution are three facts. This gate exists
# because the wasm branch returned after writing the artifact: every program
# `idol run` compiled on this host reported the COMPILE's status, so a source
# whose whole body is `7` answered 0 while wasmtime read 7 out of the very file
# that run had just called a success.
#
# Every arm below discriminates on the ACTUAL GUEST. Two of them cannot be
# satisfied by any compile-time constant at all: the argument arm's status is a
# length chosen at run time, and the cancel arm requires the guest to be
# observably alive before it is stopped.

set -eu

root=${OUTCOME_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

fail() {
    printf 'outcome gate: FAIL %s\n' "$1" >&2
    exit 1
}

blocked() {
    printf 'outcome gate: NOT MEASURED — %s\n' "$1" >&2
    exit 3
}

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
case "$idol" in /*) ;; *) idol="$root/${idol#./}" ;; esac
[ -x "$idol" ] || fail "compiler is not executable: $idol (run zig build)"

runner=${WASMTIME_BIN:-$(command -v wasmtime 2>/dev/null || true)}
[ -n "$runner" ] && [ -x "$runner" ] ||
    blocked "no wasm runner: this host cannot observe an execution outcome at all"

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-outcome.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fixture="$root/examples/outcome"
for f in zero seven hold miss trap arg; do
    [ -f "$fixture/$f.id" ] || fail "fixture $fixture/$f.id is missing"
done

cd "$work" || fail "cannot enter $work"

# The spinning guest lives HERE and not in `examples/`: it never terminates by
# design, and every corpus walker in this tree runs what it finds there.
cat >spin.id <<'ID'
main: i64 = ()
    print("live")
    n = 0
    while n > -1
        n = n + 1
    0
ID

# The wasm realization is NAMED, not inherited: `idol run` happens to default to
# it on a host with no native backend, and a gate that relied on that default
# would stop measuring this seam the day the default moved.
realization="--backend=wasm --target wasm32-wasi"

answers() {
    [ "$1" = "$2" ]
}

# `outcome NAME SRC [ARG...]` — the status `idol run` reports, with its stderr
# left in NAME.err and the guest's stdout in NAME.out.
outcome() {
    _name=$1
    _src=$2
    shift 2
    _status=0
    if [ "$#" -gt 0 ]; then
        "$idol" run $realization "$_src" -- "$@" >"$_name.out" 2>"$_name.err" || _status=$?
    else
        "$idol" run $realization "$_src" >"$_name.out" 2>"$_name.err" || _status=$?
    fi
    printf '%s\n' "$_status"
}

named() {
    grep -q "$2" "$1.err"
}

# ===================== ARM 0: THE COMPARISON'S CONTROLS =====================

answers 7 7 || fail "arm 0: answers rejected an agreeing pair"
if answers 7 0; then
    fail "arm 0: answers accepted 7 as 0 — the comparison is dead"
fi
printf 'RUN110: a named refusal\n' >probe.err
named probe RUN110 || fail "arm 0: the identity check missed an identity that is present"
if named probe RUN111; then
    fail "arm 0: the identity check matched an identity that is absent"
fi

# ================== ARM 1: THE GUEST'S OWN EXIT, BOTH WAYS ==================

# `zero`/`seven` answer by explicit result; `hold`/`miss` are one smoke with one
# expectation true and one false, reaching the same two answers through a
# branch. A collapse to 0 fails seven and miss; a collapse to nonzero fails zero
# and hold; no single wrong constant survives all four.
for pair in zero:0 seven:7 hold:0 miss:7; do
    src=${pair%:*}
    want=${pair##*:}
    got=$(outcome "$src" "$fixture/$src.id")
    answers "$got" "$want" ||
        fail "arm 1: $src.id reported $got, its outcome is $want"
done
if named seven RUN; then
    fail "arm 1: a program that exited named a refusal identity"
fi

printf 'outcome gate: arm 1 four paired guests discriminated exit 0 from exit 7\n'

# =============== ARM 2: THE ARGUMENTS REACH THE RUNNING GUEST ===============
#
# arg.id exits with the LENGTH of its first argument. No constant the compiler
# could have folded produces both 7 and 2 from one artifact, and the absent
# argument stays UNKNOWN (0) rather than becoming "".

got=$(outcome arglong "$fixture/arg.id" abcdefg)
answers "$got" 7 || fail "arm 2: arg.id on a 7-byte argument reported $got, not 7"
got=$(outcome argshort "$fixture/arg.id" ab)
answers "$got" 2 || fail "arm 2: arg.id on a 2-byte argument reported $got, not 2"
got=$(outcome argnone "$fixture/arg.id")
answers "$got" 0 || fail "arm 2: arg.id with no argument reported $got, not 0"

printf 'outcome gate: arm 2 run-time arguments changed the guest outcome 7/2/0\n'

# ==================== ARM 3: A TRAP IS NOT AN EXIT CODE =====================

got=$(outcome trap "$fixture/trap.id")
answers "$got" 134 || fail "arm 3: trap.id reported $got, a trap is 134"
named trap RUN110 || fail "arm 3: the trap was not named RUN110: $(head -2 trap.err | tr '\n' ' ')"

printf 'outcome gate: arm 3 trap reported as RUN110/134, distinct from every exit\n'

# ================= ARM 4: A CANCELLED GUEST IS NOT AN EXIT ==================
#
# spin.id prints one line and then never stops. The line is the proof that a
# guest is executing; the signal goes to the runner process that carries it.

"$idol" run $realization "$work/spin.id" >live.out 2>live.err &
held=$!
alive=0
i=0
while [ "$i" -lt 80 ]; do
    if grep -q live live.out 2>/dev/null; then
        alive=1
        break
    fi
    i=$((i + 1))
    sleep 0.25
done
[ "$alive" = 1 ] || {
    kill -KILL "$held" 2>/dev/null || true
    fail "arm 4: no guest output appeared, so nothing was executing to cancel"
}
carrier=$(pgrep -P "$held" 2>/dev/null | head -1)
[ -n "$carrier" ] || {
    kill -KILL "$held" 2>/dev/null || true
    fail "arm 4: idol run holds no child process while its guest is running"
}
kill -TERM "$carrier"
got=0
wait "$held" || got=$?
answers "$got" 143 || fail "arm 4: the cancelled guest reported $got, a SIGTERM cancel is 143"
grep -q RUN111 live.err || fail "arm 4: the cancel was not named RUN111: $(head -2 live.err | tr '\n' ' ')"

printf 'outcome gate: arm 4 live guest cancelled to RUN111/143, distinct from every exit\n'

# ============ ARM 5: COMPILATION AND ARTIFACT ARE NOT AN OUTCOME ============

"$idol" compile $realization "$fixture/seven.id" -o "$work/seven.artifact" \
    >compile.log 2>&1 ||
    fail "arm 5: seven.id did not compile: $(head -3 compile.log | tr '\n' ' ')"
[ -s "$work/seven.artifact" ] || fail "arm 5: compile succeeded without leaving an artifact"
got=$(outcome again "$fixture/seven.id")
answers "$got" 7 ||
    fail "arm 5: the source that compiles 0 and leaves an artifact ran to $got, not 7"

printf 'outcome gate: arm 5 compile 0, artifact present, run 7 — three separate facts\n'

# ============= ARM 6: AN UNOBSERVED OUTCOME IS NEVER REPORTED ===============
#
# The runner's status 1 is the one value a guest exit and a runner failure
# share. The pair below differs only in whether the runner accepts the
# artifact, so a seam that passed the status straight through would answer 1
# to both and a seam that refused blindly would answer neither.

cat >reject <<'SH'
#!/bin/sh
exit 1
SH
cat >carry <<'SH'
#!/bin/sh
case "$1" in compile) exit 0 ;; esac
exit 1
SH
chmod +x reject carry

got=0
WASMTIME_BIN=/nonexistent/wasm-runner "$idol" run $realization "$fixture/zero.id" \
    >absent.out 2>absent.err || got=$?
answers "$got" 127 || fail "arm 6: with no runner idol run reported $got, not a refusal"
named absent RUN101 || fail "arm 6: the missing runner was not named RUN101"

got=0
WASMTIME_BIN="$work/reject" "$idol" run $realization "$fixture/zero.id" \
    >reject.out 2>reject.err || got=$?
answers "$got" 126 || fail "arm 6: a rejected artifact reported $got, not a refusal"
named reject RUN102 || fail "arm 6: the rejected artifact was not named RUN102"

got=0
WASMTIME_BIN="$work/carry" "$idol" run $realization "$fixture/zero.id" \
    >carry.out 2>carry.err || got=$?
answers "$got" 1 || fail "arm 6: an accepted artifact's exit 1 reported $got, not 1"
if named carry RUN; then
    fail "arm 6: a guest that exited 1 was refused as unobserved"
fi

printf 'outcome gate: arm 6 status 1 attributed by the artifact question, not passed through\n'

# ========= ARM 7: AN EXIT CODE THIS REALIZATION CANNOT CARRY IS NOT 1 =======
#
# WASI proc_exit takes [0,126). 125 crosses; 200 — and every negative result,
# which the POSIX mask turns into 130..255 — does not. The rejected call exits
# the runner 1, a code programs also ask for on purpose, so the guest refuses
# by name instead of letting a wrong exit be indistinguishable from a right one.

cat >edge.id <<'ID'
main: i64 = ()
    125
ID
cat >over.id <<'ID'
main: i64 = ()
    200
ID

got=$(outcome edge "$work/edge.id")
answers "$got" 125 || fail "arm 7: the last code WASI carries reported $got, not 125"
got=$(outcome over "$work/over.id")
if answers "$got" 1; then
    fail "arm 7: an exit code WASI cannot carry was reported as the guest's own exit 1"
fi
answers "$got" 134 || fail "arm 7: an uncarryable exit code reported $got, not a refusal"
named over RUN110 || fail "arm 7: the uncarryable exit code was not named RUN110"
grep -q 'outside WASI' over.out ||
    grep -q 'outside WASI' over.err ||
    fail "arm 7: the guest refused without saying which code it could not carry"

printf 'outcome gate: arm 7 exit 125 carried, exit 200 refused rather than answered as 1\n'
printf 'outcome gate: PASS\n'
