#!/bin/sh
# Exact two-compiler behavioural differential over a declared legacy-equivalent
# subject set. Each arm is observed ONCE. Status, stdout, stderr, timeout and
# signal therefore belong to one execution instead of being assembled from two
# different executions.
#
#   gate/differential.sh <base-idol> <candidate-idol> [file-list]
#   gate/differential.sh --selftest
#   gate/differential.sh                 # mandatory controls; comparison UNMEASURED
#
# A changed row is red. A timeout or broken outcome channel is infrastructure,
# never a semantic refusal. The oracle is intentionally bounded: callers must
# supply only programs expected to retain legacy behaviour (law.oracle.bounded).
#
# WHY EACH MECHANISM BELOW EXISTS. Every one was written after a hand-rolled
# differential in this tree produced a CONFIDENT WRONG ANSWER. Preserved as
# provenance so none is removed as redundant ceremony:
#
#   normalising `([0-9]+ ms` — compiler progress lines carry per-run timings.
#     Comparing raw stderr reported 279 of 943 files changed when nothing had.
#
#   normalising mirror paths — `detectCompilerLibRoot(..., args[0])`
#     (src/main.zig) resolves the compiler's lib/ from the BINARY's location,
#     not the cwd, so two arms from different mirrors compare two different
#     lib/ trees and diagnostics carry the mirror path. 126 false rows. Note
#     the pattern must cross a SPACE: an earlier `[^ ]*` could not match
#     "/Volumes/d 1/" and silently normalised nothing.
#
#   a working directory per arm — both arms otherwise write ./<name>.out into
#     one directory and the second hits the first's cached artifact. 28 false
#     rows INCLUDING apparent exit-code regressions (0 -> 1) on programs whose
#     stdout was byte-identical.
#
#   infrastructure classification — a killed run emits NO diagnostic, so a
#     naive census scores it as a CLEAN COMPILE. The error is silent and
#     OPTIMISTIC: under load this moved a measured refusal count from 445 to
#     345 with no signal at all.
#
#   the same-binary guard — a patched build that never finished linking
#     reports zero differences and reads as success. Related: copying a mirror
#     WITH its .zig-cache makes `zig build` emit a byte-identical binary from
#     changed sources (observed: 8584af5eb14f1ace on both arms). Hash both.
#
#   the zero-subject guard — run where the list resolves empty, an earlier
#     version printed "compared 0 ... CHANGED 0" and exited 0. GAP-201: a gate
#     examining zero subjects must fail.
#
#   Reading `$?` after a pipe reports the PIPE's status. This hid a genuinely
#     failing gate here; bash PIPESTATUS[0] and zsh pipestatus[1] differ in
#     BOTH name and index, so a snippet copied between shells is silently wrong.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE="${IDOL_NATIVE:-$ROOT/../idol-native}"
LIMITER="${DIFFERENTIAL_LIMITER:-$NATIVE/gate/run_limited.pl}"
TMO="${DIFFERENTIAL_TIMEOUT:-90}"

[ -f "$LIMITER" ] || {
  echo "differential: shared outcome limiter absent at $LIMITER" >&2
  exit 2
}

norm() {
  sed -E -e 's/\([0-9]+ ms/(MS/' \
         -e 's#/Volumes/.*/tmp-[A-Za-z0-9_-]+/#TREE/#g' \
         -e 's#duo_[A-Za-z0-9_]+_[0-9a-f]{6,}_[0-9]+#DUOTMP#g' \
         -e 's#^.*\(cached\)$#COMPILED#' \
         -e 's#^  ok compile.*#COMPILED#'
}

hash256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

# Print one tab-separated record:
#   event  status  stdout-path  normalized-stderr-path
# The caller owns all four paths. The child is never invoked a second time to
# recover another observation.
observe() {
  _obs_tag=$1
  _obs_cwd=$2
  _obs_bin=$3
  _obs_subject=$4
  _obs_record=$5
  _obs_event="$WORK/$_obs_tag.event"
  _obs_stdout="$WORK/$_obs_tag.stdout"
  _obs_stderr_raw="$WORK/$_obs_tag.stderr.raw"
  _obs_stderr="$WORK/$_obs_tag.stderr"
  rm -f "$_obs_event" "$_obs_stdout" "$_obs_stderr_raw" "$_obs_stderr"
  (
    cd "$_obs_cwd" || exit 125
    perl "$LIMITER" "$TMO" "$_obs_event" \
      "$_obs_bin" run "$_obs_subject" </dev/null >"$_obs_stdout" 2>"$_obs_stderr_raw"
  )
  _obs_status=$?
  if [ ! -s "$_obs_event" ]; then
    printf 'missing\t%s\t%s\t%s\n' "$_obs_status" "$_obs_stdout" "$_obs_stderr" >"$_obs_record"
    return
  fi
  _obs_kind=$(sed -n '1p' "$_obs_event")
  norm <"$_obs_stderr_raw" >"$_obs_stderr"
  printf '%s\t%s\t%s\t%s\n' "$_obs_kind" "$_obs_status" "$_obs_stdout" "$_obs_stderr" >"$_obs_record"
}

compare_subjects() {
  _cmp_base=$1
  _cmp_cand=$2
  _cmp_list=$3
  _cmp_source=$4

  for _cmp_bin in "$_cmp_base" "$_cmp_cand"; do
    [ -x "$_cmp_bin" ] || {
      echo "differential: not executable: $_cmp_bin" >&2
      return 2
    }
  done

  _cmp_base_hash=$(hash256 "$_cmp_base") || return 2
  _cmp_cand_hash=$(hash256 "$_cmp_cand") || return 2
  [ "$_cmp_base_hash" != "$_cmp_cand_hash" ] || {
    echo "differential: both arms are the same binary ($_cmp_base_hash)" >&2
    return 2
  }
  printf 'differential: base sha256 %s\n' "$_cmp_base_hash"
  printf 'differential: candidate sha256 %s\n' "$_cmp_cand_hash"

  _cmp_a="$WORK/base.cwd"
  _cmp_b="$WORK/candidate.cwd"
  mkdir -p "$_cmp_a" "$_cmp_b" || return 2

  _cmp_changed=0
  _cmp_identical=0
  _cmp_infra=0
  _cmp_seen=0
  while IFS= read -r _cmp_rel || [ -n "$_cmp_rel" ]; do
    [ -n "$_cmp_rel" ] || continue
    _cmp_subject="$_cmp_source/$_cmp_rel"
    if [ ! -f "$_cmp_subject" ]; then
      printf '%s infrastructure: subject absent\n' "$_cmp_rel" >&2
      _cmp_infra=$((_cmp_infra + 1))
      continue
    fi
    _cmp_seen=$((_cmp_seen + 1))

    _cmp_ar="$WORK/base.$_cmp_seen.record"
    _cmp_br="$WORK/candidate.$_cmp_seen.record"
    observe "base.$_cmp_seen" "$_cmp_a" "$_cmp_base" "$_cmp_subject" "$_cmp_ar"
    observe "candidate.$_cmp_seen" "$_cmp_b" "$_cmp_cand" "$_cmp_subject" "$_cmp_br"
    IFS="$(printf '\t')" read -r _cmp_ak _cmp_arc _cmp_ao _cmp_ae <"$_cmp_ar"
    IFS="$(printf '\t')" read -r _cmp_bk _cmp_brc _cmp_bo _cmp_be <"$_cmp_br"

    case "$_cmp_ak" in
      ok|signal:*) : ;;
      *)
        printf '%s infrastructure base-event:%s status:%s\n' \
          "$_cmp_rel" "$_cmp_ak" "$_cmp_arc" >&2
        _cmp_infra=$((_cmp_infra + 1))
        continue
        ;;
    esac
    case "$_cmp_bk" in
      ok|signal:*) : ;;
      *)
        printf '%s infrastructure candidate-event:%s status:%s\n' \
          "$_cmp_rel" "$_cmp_bk" "$_cmp_brc" >&2
        _cmp_infra=$((_cmp_infra + 1))
        continue
        ;;
    esac

    if [ "$_cmp_ak" = "$_cmp_bk" ] && \
       [ "$_cmp_arc" = "$_cmp_brc" ] && \
       cmp -s "$_cmp_ao" "$_cmp_bo" && \
       cmp -s "$_cmp_ae" "$_cmp_be"; then
      _cmp_identical=$((_cmp_identical + 1))
    else
      _cmp_changed=$((_cmp_changed + 1))
      printf '%s CHANGED event:%s->%s status:%s->%s\n' \
        "$_cmp_rel" "$_cmp_ak" "$_cmp_bk" "$_cmp_arc" "$_cmp_brc"
    fi
  done <"$_cmp_list"

  _cmp_measured=$((_cmp_changed + _cmp_identical))
  printf 'differential: compared %s — changed %s, identical %s, infrastructure %s (subjects %s)\n' \
    "$_cmp_measured" "$_cmp_changed" "$_cmp_identical" "$_cmp_infra" "$_cmp_seen"
  [ "$_cmp_seen" -gt 0 ] || {
    echo "differential: zero subjects examined — vacuous" >&2
    return 2
  }
  [ "$_cmp_infra" -eq 0 ] || return 2
  [ "$_cmp_changed" -eq 0 ] || return 1
  [ "$_cmp_measured" -eq "$_cmp_seen" ] || return 2

  [ "$(hash256 "$_cmp_base")" = "$_cmp_base_hash" ] || {
    echo "differential: base compiler moved during measurement" >&2
    return 2
  }
  [ "$(hash256 "$_cmp_cand")" = "$_cmp_cand_hash" ] || {
    echo "differential: candidate compiler moved during measurement" >&2
    return 2
  }
  return 0
}

selftest() {
  _self="$WORK/selftest"
  mkdir -p "$_self/source" || return 2
  printf 'main: i64 = ()\n  0\n' >"$_self/source/control.id"
  printf 'control.id\n' >"$_self/list"

  # Different bytes, one identical observation. Each fake records its own
  # invocation count; a future second-run stderr probe makes this control red.
  _self_fake='#!/bin/sh
count=$0.count
n=0
[ ! -f "$count" ] || n=$(sed -n "1p" "$count")
n=$((n + 1))
printf "%s\n" "$n" > "$count"
printf "answer\n"
printf "  ok compile (123 ms — /Volumes/d 1/tmp-self/base.out)\n" >&2
exit 7
'
  printf '%s\n# base\n' "$_self_fake" >"$_self/base"
  printf '%s\n# candidate\n' "$_self_fake" >"$_self/candidate"
  chmod +x "$_self/base" "$_self/candidate"

  compare_subjects "$_self/base" "$_self/candidate" \
    "$_self/list" "$_self/source" >/dev/null || return 1
  [ "$(sed -n '1p' "$_self/base.count")" = 1 ] || return 1
  [ "$(sed -n '1p' "$_self/candidate.count")" = 1 ] || return 1

  # Comparator damage: one candidate emits another value, and the differential
  # must turn red rather than merely print CHANGED and return success.
  sed 's/printf "answer\\n"/printf "damaged\\n"/' \
    "$_self/candidate" >"$_self/candidate.damaged"
  chmod +x "$_self/candidate.damaged"
  compare_subjects "$_self/base" "$_self/candidate.damaged" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 1 ] || return 1

  # Zero-subject damage remains infrastructure, never a green comparison.
  : >"$_self/empty.list"
  compare_subjects "$_self/base" "$_self/candidate" \
    "$_self/empty.list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 2 ] || return 1

  # A normal exit 143 and SIGTERM are distinct even though shells commonly
  # project both to status 143. The out-of-band event must make this a changed
  # semantic observation rather than comparing the status integers equal.
  printf '#!/bin/sh\nexit 143\n# ordinary\n' >"$_self/exit143"
  printf '#!/bin/sh\nkill -TERM $$\n# signal\n' >"$_self/signal15"
  chmod +x "$_self/exit143" "$_self/signal15"
  compare_subjects "$_self/exit143" "$_self/signal15" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 1 ] || return 1

  # A timed-out arm is infrastructure and its private process group is reaped.
  printf '#!/bin/sh\nsleep 10\n# timeout\n' >"$_self/timeout"
  chmod +x "$_self/timeout"
  _self_old_tmo=$TMO
  TMO=1
  compare_subjects "$_self/base" "$_self/timeout" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  TMO=$_self_old_tmo
  [ "$_self_rc" -eq 2 ] || return 1

  echo "differential: selftest PASS — one observation, comparator damage, zero-subject, signal and timeout controls"
  return 0
}

WORK=$(mktemp -d) || exit 2
trap 'rm -rf "$WORK"' EXIT

if [ "${1:-}" = "--selftest" ]; then
  selftest || {
    echo "differential: selftest FAIL" >&2
    exit 1
  }
  exit 0
fi

selftest || {
  echo "differential: mandatory controls FAIL" >&2
  exit 1
}

if [ "$#" -eq 0 ]; then
  echo "differential: compiler comparison UNMEASURED — supply base and candidate"
  exit 0
fi
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || {
  echo "usage: gate/differential.sh <base-idol> <candidate-idol> [file-list]" >&2
  exit 2
}

[ -x "$1" ] && [ -x "$2" ] || {
  echo "differential: compiler path absent or not executable" >&2
  exit 2
}
BASE=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
CAND=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
if [ "$#" -eq 3 ]; then
  LIST=$3
else
  LIST="$WORK/subjects"
  (cd "$ROOT" && find examples lib scripts -name '*.id' -type f 2>/dev/null | sort) >"$LIST" || exit 2
fi
[ -r "$LIST" ] || {
  echo "differential: unreadable subject list: $LIST" >&2
  exit 2
}

compare_subjects "$BASE" "$CAND" "$LIST" "$ROOT"
exit $?
