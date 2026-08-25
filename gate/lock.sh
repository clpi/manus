#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
shell="$repo/tools/node/dev/idol-lock"
work=$(mktemp -d "${TMPDIR:-/tmp}/idol-lock-gate.XXXXXX")
children=""
unset IDOL_LOCK_HELD

cleanup() {
  for child in $children; do
    kill "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
  done
  rm -rf "$work"
}
trap cleanup EXIT INT TERM

fail() {
  printf 'lock gate: FAIL %s\n' "$1" >&2
  exit 1
}

waitfor() {
  path=$1
  tries=0
  while [ ! -e "$path" ]; do
    tries=$((tries + 1))
    [ "$tries" -lt 200 ] || fail "timed out waiting for $path"
    sleep 0.01
  done
}

tokenof() {
  for candidate in "$1"/owner.*.*; do
    [ -d "$candidate" ] || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

waittoken() {
  directory=$1
  tries=0
  while ! token=$(tokenof "$directory"); do
    tries=$((tries + 1))
    [ "$tries" -lt 200 ] || fail "timed out waiting for token in $directory"
    sleep 0.01
  done
  printf '%s\n' "$token"
}

printf '%s\n' '#!/bin/sh' 'exit 37' >"$work/exit37"
printf '%s\n' \
  '#!/bin/sh' \
  'printf ready >"$1"' \
  'while [ ! -e "$2" ]; do sleep 0.01; done' >"$work/hold"
printf '%s\n' '#!/bin/sh' 'printf ran >"$1"' >"$work/write"
printf '%s\n' '#!/bin/sh' 'kill -TERM $$' >"$work/signal"
chmod +x "$work/exit37" "$work/hold" "$work/write" "$work/signal"

nested="$work/nested"
ready="$work/nested-ready"
release="$work/nested-release"
IDOL_BUILD_LOCK="$nested" "$shell" -- \
  "$shell" -- "$work/hold" "$ready" "$release" &
holder=$!
children="$children $holder"
waitfor "$ready"
token=$(waittoken "$nested")
tokenname=${token##*/}
owner=${tokenname#owner.}
[ "$(IDOL_BUILD_LOCK="$nested" "$shell" status)" = "LOCKED by $owner" ] || \
  fail 'authoritative status lost its unique owner token'
set +e
waiting=$(IDOL_LOCK_HELD=2 IDOL_BUILD_LOCK="$nested" "$shell" --timeout 0 -- \
  "$work/write" "$work/nested-overlap" 2>&1)
rc=$?
set -e
[ "$rc" -eq 75 ] || fail "non-one marker bypassed with $rc"
case "$waiting" in
  *"$owner"*) ;;
  *) fail 'authoritative wait diagnostic lost its unique owner token' ;;
esac
[ ! -e "$work/nested-overlap" ] || fail 'nested child overlapped holder'
touch "$release"
wait "$holder"
children=""
[ ! -e "$nested" ] || fail 'nested holder left its lock'

nested="$work/nested-exit"
set +e
IDOL_BUILD_LOCK="$nested" "$shell" -- "$shell" -- "$work/exit37"
rc=$?
set -e
[ "$rc" -eq 37 ] || fail "nested child exit became $rc"
[ ! -e "$nested" ] || fail 'nested failed child left its lock'

nested="$work/nested-signal"
set +e
IDOL_BUILD_LOCK="$nested" "$shell" -- "$shell" -- "$work/signal" 2>/dev/null
rc=$?
set -e
[ "$rc" -eq 143 ] || fail "nested child signal became $rc"
[ ! -e "$nested" ] || fail 'nested signalled child left its lock'

# Reentrancy has TWO arms — the env marker and the holder-ancestry walk (added
# after a suite deadlocked 25 minutes against its own gate because `zig build`
# does not propagate the env marker). Fail-closed is proven only when BOTH are
# removed; removing just the env arm now correctly falls through to ancestry.
damaged="$work/idol-lock-damaged"
sed -e '/^if \[ "${IDOL_LOCK_HELD:-}" = "1" \]; then$/,/^fi$/d' \
    -e '/^  if held_by_ancestor; then$/,/^  fi$/d' \
  "$shell" >"$damaged"
chmod +x "$damaged"
if grep -Fq 'if [ "${IDOL_LOCK_HELD:-}" = "1" ]; then' "$damaged"; then
  fail 'reentrant-arm damage did not land'
fi
if grep -Fq 'if held_by_ancestor; then' "$damaged"; then
  fail 'ancestry-arm damage did not land'
fi
set +e
IDOL_BUILD_LOCK="$work/damaged-shell-lock" "$shell" -- \
  "$damaged" --timeout 0 -- "$work/write" "$work/damaged-shell-ran"
rc=$?
set -e
[ "$rc" -eq 75 ] || fail "damaged nested shell returned $rc"
[ ! -e "$work/damaged-shell-ran" ] || fail 'damaged nested shell ran its child'
[ ! -e "$work/damaged-shell-lock" ] || fail 'damaged outer shell left its lock'

# The ancestry arm itself: a nested shell whose env marker was SCRUBBED (the
# measured zig-build behavior) still recognizes the ancestor holder and execs
# through instead of deadlocking — and marks the lock held so a re-execing
# gate does not ping-pong.
nested="$work/nested-ancestry"
set +e
IDOL_BUILD_LOCK="$nested" "$shell" -- \
  env -u IDOL_LOCK_HELD IDOL_BUILD_LOCK="$nested" \
  "$shell" --timeout 0 -- "$work/write" "$work/ancestry-ran"
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "ancestor-held env-scrubbed nested shell returned $rc"
[ -e "$work/ancestry-ran" ] || fail 'ancestor-held nested shell never ran its child'
[ ! -e "$nested" ] || fail 'ancestry nested shell left its lock'

# A holder whose process is gone is reclaimed instead of waited on: a killed
# suite once queued the next run 13 minutes behind a corpse.
dead="$work/shell-dead-holder"
mkdir -p "$dead/owner.999999999.1"
set +e
IDOL_BUILD_LOCK="$dead" "$shell" --timeout 5 -- \
  "$work/write" "$work/dead-reclaim-ran" 2>/dev/null
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "dead-holder reclamation returned $rc"
[ -e "$work/dead-reclaim-ran" ] || fail 'dead-holder reclamation never ran its child'
[ ! -e "$dead" ] || fail 'dead-holder reclamation left the lock'

legacy="$work/shell-legacy"
mkdir "$legacy"
printf '424242\n' >"$legacy/owner"
[ "$(IDOL_BUILD_LOCK="$legacy" "$shell" status)" = 'LOCKED by 424242' ] || \
  fail 'authoritative status lost the legacy owner'
set +e
waiting=$(IDOL_BUILD_LOCK="$legacy" "$shell" --timeout 0 -- /usr/bin/true 2>&1)
rc=$?
set -e
[ "$rc" -eq 75 ] || fail "legacy owner returned $rc"
case "$waiting" in
  *424242*) ;;
  *) fail 'authoritative wait diagnostic lost the legacy owner' ;;
esac
[ "$(cat "$legacy/owner")" = 424242 ] || fail 'legacy owner changed'
rm -f "$legacy/owner"
rmdir "$legacy"

ownerless="$work/shell-ownerless-diagnostic"
mkdir "$ownerless"
[ "$(IDOL_BUILD_LOCK="$ownerless" "$shell" status)" = 'LOCKED by unavailable' ] || \
  fail 'authoritative status treated ownerless lock as free'
set +e
waiting=$(IDOL_BUILD_LOCK="$ownerless" "$shell" --timeout 0 -- /usr/bin/true 2>&1)
rc=$?
set -e
[ "$rc" -eq 75 ] || fail "ownerless shell lock returned $rc"
case "$waiting" in
  *unavailable*) ;;
  *) fail 'authoritative wait diagnostic hid ownerless lock' ;;
esac
[ -d "$ownerless" ] || fail 'authoritative shell reclaimed ownerless lock'
rmdir "$ownerless"

for kind in replacement invalid ownerless; do
  shellheld="$work/shell-$kind"
  ready="$work/shell-$kind-ready"
  release="$work/shell-$kind-release"
  IDOL_BUILD_LOCK="$shellheld" "$shell" -- \
    "$work/hold" "$ready" "$release" &
  holder=$!
  children="$children $holder"
  waitfor "$ready"
  token=$(waittoken "$shellheld")
  rmdir "$token"
  case "$kind" in
    replacement) mkdir "$shellheld/owner.replacement.precleanup" ;;
    invalid) printf 'not-a-process\n' >"$shellheld/owner" ;;
    ownerless) : ;;
  esac
  touch "$release"
  wait "$holder"
  children=""
  [ -d "$shellheld" ] || fail "authoritative shell deleted $kind owner"
  case "$kind" in
    replacement) [ -d "$shellheld/owner.replacement.precleanup" ] || fail 'replacement token changed' ;;
    invalid) [ "$(cat "$shellheld/owner")" = not-a-process ] || fail 'invalid owner changed' ;;
    ownerless) [ -z "$(find "$shellheld" -mindepth 1 -maxdepth 1 -print -quit)" ] || fail 'ownerless lock gained an owner' ;;
  esac
  case "$kind" in
    replacement) rmdir "$shellheld/owner.replacement.precleanup" ;;
    invalid) rm -f "$shellheld/owner" ;;
    ownerless) : ;;
  esac
  rmdir "$shellheld"
done

realrmdir=$(command -v rmdir)
mkdir "$work/interpose-rmdir"
printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'if [ ! -e "$IDOL_RMDIR_STATE" ]; then' \
  '  : >"$IDOL_RMDIR_STATE"' \
  '  : >"$IDOL_RMDIR_PAUSED"' \
  '  while [ ! -e "$IDOL_RMDIR_RESUME" ]; do sleep 0.01; done' \
  'fi' \
  'exec "$IDOL_REAL_RMDIR" "$@"' >"$work/interpose-rmdir/rmdir"
chmod +x "$work/interpose-rmdir/rmdir"

race="$work/shell-cleanup-race"
paused="$work/shell-cleanup-paused"
resume="$work/shell-cleanup-resume"
state="$work/shell-cleanup-state"
PATH="$work/interpose-rmdir:$PATH" \
IDOL_REAL_RMDIR="$realrmdir" \
IDOL_RMDIR_STATE="$state" \
IDOL_RMDIR_PAUSED="$paused" \
IDOL_RMDIR_RESUME="$resume" \
IDOL_BUILD_LOCK="$race" "$shell" -- /usr/bin/true &
holder=$!
children="$children $holder"
waitfor "$paused"
token=$(waittoken "$race")
replacement="$race/owner.replacement.race"
mkdir "$replacement"
touch "$resume"
wait "$holder"
children=""
[ ! -e "$token" ] || fail 'authoritative cleanup left its own token'
[ -d "$replacement" ] || fail 'authoritative cleanup deleted in-window replacement'
rmdir "$replacement"
rmdir "$race"

cleanupdamage="$work/idol-lock-cleanup-damaged"
sed '/^cleanup() {$/,/^}$/c\
cleanup() {\
  rm -rf "$lockdir"\
}' "$shell" >"$cleanupdamage"
chmod +x "$cleanupdamage"
grep -Fq 'rm -rf "$lockdir"' "$cleanupdamage" || \
  fail 'replacement cleanup damage did not land'

realrm=$(command -v rm)
mkdir "$work/interpose-rm"
printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'if [ ! -e "$IDOL_RM_STATE" ]; then' \
  '  : >"$IDOL_RM_STATE"' \
  '  : >"$IDOL_RM_PAUSED"' \
  '  while [ ! -e "$IDOL_RM_RESUME" ]; do sleep 0.01; done' \
  'fi' \
  'exec "$IDOL_REAL_RM" "$@"' >"$work/interpose-rm/rm"
chmod +x "$work/interpose-rm/rm"

shellheld="$work/shell-damaged-race"
paused="$work/shell-damaged-paused"
resume="$work/shell-damaged-resume"
state="$work/shell-damaged-state"
PATH="$work/interpose-rm:$PATH" \
IDOL_REAL_RM="$realrm" \
IDOL_RM_STATE="$state" \
IDOL_RM_PAUSED="$paused" \
IDOL_RM_RESUME="$resume" \
IDOL_BUILD_LOCK="$shellheld" "$cleanupdamage" -- /usr/bin/true &
holder=$!
children="$children $holder"
waitfor "$paused"
waittoken "$shellheld" >/dev/null
mkdir "$shellheld/owner.replacement.race"
touch "$resume"
wait "$holder"
children=""
if [ -d "$shellheld" ]; then
  damage=REPLACEMENT_PRESERVED
  rm -rf "$shellheld"
else
  damage=REPLACEMENT_DELETED
fi
printf 'lock gate damage: %s\n' "$damage"
[ "$damage" = REPLACEMENT_DELETED ] || fail 'replacement cleanup damage survived'

one='space and tab'
two='semi;star*question?'
three='dollar$()backtick`'
four='single'\''double"'
five='line one
line two'
six=''
export one two three four five six
shelllock="$work/shell-lock"
output=$(IDOL_BUILD_LOCK="$shelllock" "$shell" -- "$shell" -- sh -c '
  [ "$#" -eq 6 ] &&
  [ "$1" = "$one" ] &&
  [ "$2" = "$two" ] &&
  [ "$3" = "$three" ] &&
  [ "$4" = "$four" ] &&
  [ "$5" = "$five" ] &&
  [ "$6" = "$six" ] &&
  printf nested-output
' argv "$one" "$two" "$three" "$four" "$five" "$six")
[ "$output" = nested-output ] || fail 'nested child output changed'
[ ! -e "$shelllock" ] || fail 'authoritative shell lock remained'

printf 'lock gate: PASS\n'
