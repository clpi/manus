#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
idol=${IDOL_BIN:-"$repo/zig-out/bin/idol"}
source="$repo/scripts/idol_lock.id"
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

buildlock="$work/build-lock"
IDOL_BUILD_LOCK="$buildlock" "$shell" -- \
  "$idol" compile --backend=direct "$source" -o "$work/lock" >/dev/null
[ ! -e "$buildlock" ] || fail 'authoritative build lock remained'

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
waitfor "$nested/owner"
set +e
IDOL_LOCK_HELD=2 IDOL_BUILD_LOCK="$nested" "$shell" --timeout 0 -- \
  "$work/write" "$work/nested-overlap"
rc=$?
set -e
[ "$rc" -eq 75 ] || fail "non-one marker bypassed with $rc"
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

damaged="$work/idol-lock-damaged"
sed '/^if \[ "${IDOL_LOCK_HELD:-}" = "1" \]; then$/,/^fi$/d' \
  "$shell" >"$damaged"
chmod +x "$damaged"
if grep -Fq 'if [ "${IDOL_LOCK_HELD:-}" = "1" ]; then' "$damaged"; then
  fail 'reentrant-arm damage did not land'
fi
set +e
IDOL_BUILD_LOCK="$work/damaged-shell-lock" "$shell" -- \
  "$damaged" --timeout 0 -- "$work/write" "$work/damaged-shell-ran"
rc=$?
set -e
[ "$rc" -eq 75 ] || fail "damaged nested shell returned $rc"
[ ! -e "$work/damaged-shell-ran" ] || fail 'damaged nested shell ran its child'
[ ! -e "$work/damaged-shell-lock" ] || fail 'damaged outer shell left its lock'

for kind in replacement invalid ownerless; do
  shellheld="$work/shell-$kind"
  ready="$work/shell-$kind-ready"
  release="$work/shell-$kind-release"
  IDOL_BUILD_LOCK="$shellheld" "$shell" -- \
    "$work/hold" "$ready" "$release" &
  holder=$!
  children="$children $holder"
  waitfor "$ready"
  waitfor "$shellheld/owner"
  case "$kind" in
    replacement) printf 'replacement\n' >"$shellheld/owner" ;;
    invalid) printf 'not-a-process\n' >"$shellheld/owner" ;;
    ownerless) rm -f "$shellheld/owner" ;;
  esac
  touch "$release"
  wait "$holder"
  children=""
  [ -d "$shellheld" ] || fail "authoritative shell deleted $kind owner"
  case "$kind" in
    replacement) [ "$(cat "$shellheld/owner")" = replacement ] || fail 'replacement owner changed' ;;
    invalid) [ "$(cat "$shellheld/owner")" = not-a-process ] || fail 'invalid owner changed' ;;
    ownerless) [ ! -e "$shellheld/owner" ] || fail 'ownerless lock gained an owner' ;;
  esac
  rm -f "$shellheld/owner"
  rmdir "$shellheld"
done

cleanupdamage="$work/idol-lock-cleanup-damaged"
sed '/^cleanup() {$/,/^}$/c\
cleanup() {\
  rm -rf "$lockdir"\
}' "$shell" >"$cleanupdamage"
chmod +x "$cleanupdamage"
grep -Fq 'rm -rf "$lockdir"' "$cleanupdamage" || \
  fail 'replacement cleanup damage did not land'
shellheld="$work/shell-damaged-replacement"
ready="$work/shell-damaged-ready"
release="$work/shell-damaged-release"
IDOL_BUILD_LOCK="$shellheld" "$cleanupdamage" -- \
  "$work/hold" "$ready" "$release" &
holder=$!
children="$children $holder"
waitfor "$ready"
waitfor "$shellheld/owner"
printf 'replacement\n' >"$shellheld/owner"
touch "$release"
wait "$holder"
children=""
if [ -d "$shellheld" ]; then
  damage=REPLACEMENT_PRESERVED
  rm -f "$shellheld/owner"
  rmdir "$shellheld"
else
  damage=REPLACEMENT_DELETED
fi
printf 'lock gate damage: %s\n' "$damage"
[ "$damage" = REPLACEMENT_DELETED ] || fail 'replacement cleanup damage survived'

success="$work/success"
[ "$(IDOL_BUILD_LOCK="$success" "$work/lock" status)" = FREE ] || \
  fail 'fresh lock did not report free'
IDOL_BUILD_LOCK="$success" "$work/lock" -- /usr/bin/true
[ ! -e "$success" ] || fail 'successful child left its lock'

exact="$work/exact"
set +e
IDOL_BUILD_LOCK="$exact" "$work/lock" -- "$work/exit37"
rc=$?
set -e
[ "$rc" -eq 37 ] || fail "child exit became $rc"
[ ! -e "$exact" ] || fail 'failed child left its lock'

live="$work/live"
ready="$work/live-ready"
release="$work/live-release"
IDOL_BUILD_LOCK="$live" "$work/lock" -- "$work/hold" "$ready" "$release" &
holder=$!
children="$children $holder"
waitfor "$ready"
waitfor "$live/owner"
owner=$(cat "$live/owner")
case "$owner" in
  ''|*[!0-9]*) fail 'live owner is not a process id' ;;
esac
kill -0 "$owner" 2>/dev/null || fail 'recorded owner is not the live wrapper'
[ "$(IDOL_BUILD_LOCK="$live" "$work/lock" status)" = "LOCKED by $owner" ] || \
  fail 'live lock status lost its owner'

set +e
IDOL_BUILD_LOCK="$live" "$work/lock" --timeout 0 -- \
  "$work/write" "$work/overlap"
rc=$?
set -e
[ "$rc" -eq 75 ] || fail "live exclusion returned $rc"
[ ! -e "$work/overlap" ] || fail 'contending child overlapped holder'
touch "$release"
wait "$holder"
children=""
[ ! -e "$live" ] || fail 'live holder left its lock'

for kind in empty invalid dead; do
  blocked="$work/$kind"
  mkdir "$blocked"
  case "$kind" in
    empty) : >"$blocked/owner" ;;
    invalid) printf 'not-a-process\n' >"$blocked/owner" ;;
    dead)
      dead=999999
      while kill -0 "$dead" 2>/dev/null; do dead=$((dead + 1)); done
      printf '%s\n' "$dead" >"$blocked/owner"
      ;;
  esac
  case "$(IDOL_BUILD_LOCK="$blocked" "$work/lock" status)" in
    LOCKED*) ;;
    *) fail "$kind owner reported free" ;;
  esac
  set +e
  IDOL_BUILD_LOCK="$blocked" "$work/lock" --timeout 0 -- /usr/bin/true
  rc=$?
  set -e
  [ "$rc" -eq 75 ] || fail "$kind owner returned $rc"
  [ -d "$blocked" ] || fail "$kind owner was reclaimed"
  rm -f "$blocked/owner"
  rmdir "$blocked"
done

replaced="$work/replaced"
ready="$work/replaced-ready"
release="$work/replaced-release"
IDOL_BUILD_LOCK="$replaced" "$work/lock" -- "$work/hold" "$ready" "$release" &
holder=$!
children="$children $holder"
waitfor "$ready"
waitfor "$replaced/owner"
printf 'replacement\n' >"$replaced/owner"
touch "$release"
wait "$holder"
children=""
[ -d "$replaced" ] || fail 'replacement owner lock was deleted'
[ "$(cat "$replaced/owner")" = replacement ] || fail 'replacement owner changed'
rm -f "$replaced/owner"
rmdir "$replaced"

sed 's/\$PPID/\$\$/g' "$source" >"$work/damaged.id"
IDOL_BUILD_LOCK="$buildlock" "$shell" -- \
  "$idol" compile --backend=direct "$work/damaged.id" -o "$work/damaged" >/dev/null
set +e
IDOL_BUILD_LOCK="$work/damaged-lock" "$work/damaged" -- \
  "$work/write" "$work/damaged-ran"
rc=$?
set -e
[ "$rc" -eq 75 ] || fail "damaged owner check returned $rc"
[ ! -e "$work/damaged-ran" ] || fail 'damaged owner ran its child'
[ ! -e "$work/damaged-lock" ] || fail 'damaged owner acquired the lock'

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
