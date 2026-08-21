#!/bin/sh
# gate/retention.sh — the observation retention law, executable.
#
#   sh gate/retention.sh            # judge
#   IDOL_BIN=/path/to/idol sh gate/retention.sh
#
# Exit 0 = every row matches the ledger. Non-zero = rows that MOVED.
#
# WHY THIS GATE EXISTS. The transformation law (FTCFTW performance program,
# "effect + trap + completion + identity closure") says the optimizer may only
# erase an application when observation facts license it:
#
#   unused PURE TOTAL call        -> erased
#   same call with a WRITE        -> retained
#   same call MAY TRAP            -> retained
#   same call MAY DIVERGE         -> retained
#   effectful INITIALIZER         -> retained even if the variable is dead
#
# Every row here is scored on an EXTERNAL observable — bytes written, signal
# death, process exit — never on introspection, so the law holds against the
# real production path (unwaived, graph-facts published):
#
#   pure-total-unused-erased   deep non-tail recursion, result discarded.
#                              Erasure => clean exit; retention => stack
#                              overflow kills the process. Measured BROKEN:
#                              the call executes today because no
#                              effect/completion-driven deletion exists. This
#                              row is the deletion milestone; it flips ONLY
#                              when facts license the erase.
#   may-trap-unused-retained   same overflow shape, depth computed by a loop
#                              so totality is not provable. Death PROVES the
#                              call ran — retention is correct today and must
#                              stay correct after deletion lands. This row is
#                              the guard that deletion stays lawful.
#   divergent-call-retained    discarded call whose body is `while 1 == 1`
#                              with an empty arm. Measured BROKEN: the loop
#                              is erased and the program EXITS — divergence
#                              is observable from outside, so exiting is a
#                              retention violation today.
#   write-stmt-retained        discarded `stdout:write` still emits bytes.
#   effectful-init-retained    `x = noisy()` with x dead still emits noisy()'s
#                              bytes.
#
# The pair (pure-total-unused-erased, may-trap-unused-retained) is the point
# of the whole gate: both die identically TODAY, and the law requires them to
# DIVERGE once deletion exists — one clean, one dead. A deletion that makes
# both clean is unsound and fails this gate; a deletion that makes neither
# clean is inert and fails the first row.

set -eu

root=${RETENTION_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}
idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}

fail() {
    printf 'retention gate: FAIL %s\n' "$1" >&2
    exit 1
}

[ -x "$idol" ] || fail "compiler is not executable: $idol"

work=$(mktemp -d "${TMPDIR:-/tmp}/retention.XXXXXX") || fail "no workdir"
trap 'rm -rf "$work"' EXIT

LEDGER='
pure-total-unused-erased   broken
may-trap-unused-retained   works
divergent-call-retained    broken
write-stmt-retained        works
effectful-init-retained    works
'

pass=0; failcount=0; notes=""
judge() {
    want=$(printf '%s\n' "$LEDGER" | awk -v r="$1" '$1==r{print $2}')
    if [ -z "$want" ]; then
        notes="$notes$1: NOT IN LEDGER — measured $2
"
        failcount=$((failcount + 1)); return
    fi
    if [ "$want" = "$2" ]; then pass=$((pass + 1)); return; fi
    notes="$notes$1: MOVED — ledger says $want, measured $2
"
    failcount=$((failcount + 1))
}

run_prog() { # run_prog <name> ; program on stdin; echoes rc
    cat > "$work/$1.id"
    "$idol" run "$work/$1.id" >/dev/null 2>&1 && echo 0 || echo $?
}

# A row whose lawful future is a HANG would wedge the gate; run it with a
# watchdog and report `hung` when the watchdog fires. Today no row hangs
# (the divergent loop is erased, so everything terminates), but the harness
# must already be able to observe retention-by-hanging or it could never
# witness this row flip to works.
run_with_watchdog() { # run_with_watchdog <name> <seconds>
    cat > "$work/$1.id"
    "$idol" run "$work/$1.id" >/dev/null 2>&1 &
    pid=$!
    (
        sleep "$2" 2>/dev/null
        kill -9 "$pid" 2>/dev/null || true
    ) &
    dog=$!
    rc=0
    wait "$pid" 2>/dev/null || rc=$?
    kill "$dog" 2>/dev/null || true
    wait "$dog" 2>/dev/null || true
    if [ "$rc" -ge 128 ]; then echo hung; else echo "$rc"; fi
}

# -- pure-total-unused-erased ------------------------------------------------
# Non-tail recursion (`inc + spin(...)`) forces a real frame per level; the
# discarded call must consume the stack unless deleted. Pure (no writes, no
# reads of anything external), total (counts down to base).
rc=$(run_prog pure <<'EOF'
spin: i64 = (n: i64)
  base = 0
  inc = 1
  if n == base
    base
  else
    inc + spin(n - inc)
main: i64 = ()
  big = 100000000
  spin(big)
  zero = 0
EOF
)
[ "$rc" = "0" ] && v=works || v=broken
judge pure-total-unused-erased "$v"

# -- may-trap-unused-retained ------------------------------------------------
# Same shape; depth comes out of a loop so no totality proof applies. Death is
# the CORRECT outcome: the call may not be erased, and its execution is what
# the death certifies.
rc=$(run_prog maytrap <<'EOF'
spin: i64 = (n: i64)
  base = 0
  inc = 1
  if n == base
    base
  else
    inc + spin(n - inc)
depth: i64 = ()
  n = 0
  i = 0
  while i < 200000
    n = n + 1
    i = i + 1
  n
main: i64 = ()
  d = depth()
  spin(d)
  zero = 0
EOF
)
[ "$rc" = "0" ] && v=broken || v=works
judge may-trap-unused-retained "$v"

# -- divergent-call-retained -------------------------------------------------
# An unbounded loop with an empty arm is externally observable: a program
# containing it must never exit. Watchdog reports `hung` when retention holds.
v=$(run_with_watchdog divergent 4 <<'EOF'
hang: i64 = ()
  while 1 == 1
    0
main: i64 = ()
  zero = 0
  hang()
  zero
EOF
)
[ "$v" = "hung" ] && v=works || v=broken
judge divergent-call-retained "$v"

# -- write-stmt-retained -----------------------------------------------------
cat > "$work/write.id" <<'EOF'
main: i64 = ()
  stdout:write("keep-me")
  0
EOF
out=$("$idol" run "$work/write.id" 2>/dev/null)
case "$out" in *keep-me*) v=works ;; *) v=broken ;; esac
judge write-stmt-retained "$v"

# -- effectful-init-retained -------------------------------------------------
cat > "$work/init.id" <<'EOF'
noisy: i64 = ()
  stdout:write("init-side")
  42
main: i64 = ()
  x = noisy()
  0
EOF
out=$("$idol" run "$work/init.id" 2>/dev/null)
case "$out" in *init-side*) v=works ;; *) v=broken ;; esac
judge effectful-init-retained "$v"

if [ "$failcount" -eq 0 ]; then
    printf 'retention gate: PASS (%s rows) observation retention law held\n' "$pass"
    exit 0
fi
printf 'retention gate: FAIL (%s moved / %s held)\n' "$failcount" "$pass"
[ -n "$notes" ] && printf '%s\n' "$notes"
exit 1
