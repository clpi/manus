#!/bin/sh
# Exact two-compiler behavioural differential over a declared legacy-equivalent
# subject set. Each arm is observed ONCE. Status, stdout, stderr, timeout and
# signal therefore belong to one execution instead of being assembled from two
# different executions.
#
#   gate/differential.sh <base-idol> <candidate-idol> [file-list]
#   gate/differential.sh --null-control <idol> [file-list]
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
#
#   normalising EACH ARM'''S OWN TREE ROOT. The mirror-path rule above only ever
#     matched `/Volumes/.../tmp-<name>/`, which is the shape `mktemp -d` happens
#     to produce here. Two SIBLING MIRRORS — `.../idol` and `.../idol-native`,
#     or any two clones — are not that shape, so every diagnostic that quotes
#     the compiler'''s own lib/ root came out different and every such row was
#     scored CHANGED. It reported ~163 rows on any two-mirror run. That was
#     proven false only by a null control, and by hand: the identical 163-row
#     set appeared between a baseline and a severed build whose MACHINE CODE
#     WAS IDENTICAL. A per-arm substitution cannot be written as one global
#     `sed` because the two roots are different strings, so `norm` now takes
#     the arm it is normalising.
#
#   --null-control. The reasoning above had to be done by hand, once, by
#     someone who already suspected the harness. It is a mode now: the SAME
#     compiler is placed under two different mirror roots and compared with
#     itself. Every row it reports is harness noise by construction, because
#     the machine code on both arms is the same bytes. Zero rows is the only
#     lawful result, and a caller who sees rows from a real comparison can run
#     this to find out whether to believe them.
#
#   a scratch root per arm. `src/scratch.zig` honours TMPDIR for the build
#     cache, intermediate objects, emitted C and logs, so giving each arm its
#     own makes each arm actually compile rather than serving the other arm'''s
#     artifact out of a shared `/tmp/idol-cache-*`.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE="${IDOL_NATIVE:-$ROOT/../idol-native}"
LIMITER="${DIFFERENTIAL_LIMITER:-$NATIVE/gate/run_limited.pl}"
TMO="${DIFFERENTIAL_TIMEOUT:-90}"

[ -f "$LIMITER" ] || {
  echo "differential: shared outcome limiter absent at $LIMITER" >&2
  exit 2
}

# norm <arm-tree-root> <arm-working-directory> <arm-scratch-root>
#
# The three arm-owned strings are substituted FIRST and by exact text, because
# they are the ones that legitimately differ between two arms of the same
# comparison. Everything after them is a pattern rule that applies to both arms
# identically. `sed` has no fixed-string mode, so each root is escaped for the
# `#` delimiter; roots here are directory paths, and `#` and `\` in a path
# would break the expression rather than silently mis-normalise, which is the
# failure mode worth having.
norm() {
  _norm_root=$1
  _norm_cwd=$2
  _norm_scratch=$3
  sed -E -e "s#$(printf '%s' "$_norm_cwd" | sed 's#[\\&#]#\\&#g')#CWD#g" \
         -e "s#$(printf '%s' "$_norm_scratch" | sed 's#[\\&#]#\\&#g')#SCRATCH#g" \
         -e "s#$(printf '%s' "$_norm_root" | sed 's#[\\&#]#\\&#g')#TREE#g" \
         -e 's/\([0-9]+ ms/(MS/' \
         -e 's#/Volumes/.*/tmp-[A-Za-z0-9_-]+/#TREE/#g' \
         -e 's#duo_[A-Za-z0-9_]+_[0-9a-f]{6,}_[0-9]+#DUOTMP#g' \
         -e 's#^.*\(cached\)$#COMPILED#' \
         -e 's#^  ok compile.*#COMPILED#'
}

# STDOUT gets the arm-owned substitutions and NOTHING ELSE. The pattern rules
# in `norm` describe compiler diagnostics; a program's own output is the thing
# being compared and must not be reshaped. But the three strings below name
# THIS ARM'S PRIVATE DIRECTORIES, which exist only for this run, so a program
# that prints one of them is printing the harness, not a difference.
#
#   `examples/shc/cwd.id` is the whole reason. Its body is `stdout:write(os.cwd)`
#   and each arm gets its own directory by design, so it was carried as a
#   PERMANENT false row that every reader had to know about and subtract by
#   hand. A row a reader must remember to ignore is a row that will one day be
#   ignored when it is real.
normout() {
  _no_root=$1
  _no_cwd=$2
  _no_scratch=$3
  sed -e "s#$(printf '%s' "$_no_cwd" | sed 's#[\\&#]#\\&#g')#CWD#g" \
      -e "s#$(printf '%s' "$_no_scratch" | sed 's#[\\&#]#\\&#g')#SCRATCH#g" \
      -e "s#$(printf '%s' "$_no_root" | sed 's#[\\&#]#\\&#g')#TREE#g"
}

# The tree an arm's compiler resolves its lib/ from. `detectCompilerLibRoot`
# (src/main.zig) walks bin/ -> zig-out/ -> repo, so that is what a diagnostic
# from this arm will quote. A binary somewhere else owns only its directory.
armroot() {
  _ar_bin=$1
  _ar_dir=$(cd "$(dirname "$_ar_bin")" && pwd)
  case "$_ar_dir" in
    */zig-out/bin) (cd "$_ar_dir/../.." && pwd) ;;
    *) printf '%s' "$_ar_dir" ;;
  esac
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
  _obs_root=$6
  _obs_scratch=$7
  _obs_event="$WORK/$_obs_tag.event"
  _obs_stdout_raw="$WORK/$_obs_tag.stdout.raw"
  _obs_stdout="$WORK/$_obs_tag.stdout"
  _obs_stderr_raw="$WORK/$_obs_tag.stderr.raw"
  _obs_stderr="$WORK/$_obs_tag.stderr"
  rm -f "$_obs_event" "$_obs_stdout_raw" "$_obs_stdout" "$_obs_stderr_raw" "$_obs_stderr"
  (
    cd "$_obs_cwd" || exit 125
    TMPDIR="$_obs_scratch"
    export TMPDIR
    perl "$LIMITER" "$TMO" "$_obs_event" \
      "$_obs_bin" run "$_obs_subject" </dev/null >"$_obs_stdout_raw" 2>"$_obs_stderr_raw"
  )
  _obs_status=$?
  if [ ! -s "$_obs_event" ]; then
    printf 'missing\t%s\t%s\t%s\n' "$_obs_status" "$_obs_stdout_raw" "$_obs_stderr" >"$_obs_record"
    return
  fi
  _obs_kind=$(sed -n '1p' "$_obs_event")
  normout "$_obs_root" "$_obs_cwd" "$_obs_scratch" <"$_obs_stdout_raw" >"$_obs_stdout"
  norm "$_obs_root" "$_obs_cwd" "$_obs_scratch" <"$_obs_stderr_raw" >"$_obs_stderr"
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
  if [ "${NULL_CONTROL:-0}" = 1 ]; then
    # The guard is INVERTED here, not waived. A null control whose arms are
    # not the same bytes proves nothing at all, and it is exactly the mistake
    # this mode exists to catch elsewhere.
    [ "$_cmp_base_hash" = "$_cmp_cand_hash" ] || {
      echo "differential: null control arms differ ($_cmp_base_hash vs $_cmp_cand_hash)" >&2
      return 2
    }
  else
    [ "$_cmp_base_hash" != "$_cmp_cand_hash" ] || {
      echo "differential: both arms are the same binary ($_cmp_base_hash)" >&2
      return 2
    }
  fi
  printf 'differential: base sha256 %s\n' "$_cmp_base_hash"
  printf 'differential: candidate sha256 %s\n' "$_cmp_cand_hash"

  _cmp_a="$WORK/base.cwd"
  _cmp_b="$WORK/candidate.cwd"
  mkdir -p "$_cmp_a" "$_cmp_b" || return 2
  # Each arm's own tree root, and each arm's own scratch root. The first is
  # what its diagnostics quote; the second is where its build cache,
  # intermediate objects and emitted C live. Neither may leak into the other
  # arm's observation.
  _cmp_aroot=$(armroot "$_cmp_base")
  _cmp_broot=$(armroot "$_cmp_cand")
  _cmp_atmp="$WORK/base.scratch"
  _cmp_btmp="$WORK/candidate.scratch"
  mkdir -p "$_cmp_atmp" "$_cmp_btmp" || return 2
  printf 'differential: base tree %s\n' "$_cmp_aroot"
  printf 'differential: candidate tree %s\n' "$_cmp_broot"

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
    observe "base.$_cmp_seen" "$_cmp_a" "$_cmp_base" "$_cmp_subject" "$_cmp_ar" \
      "$_cmp_aroot" "$_cmp_atmp"
    observe "candidate.$_cmp_seen" "$_cmp_b" "$_cmp_cand" "$_cmp_subject" "$_cmp_br" \
      "$_cmp_broot" "$_cmp_btmp"
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

  # ---------------------------------------------------------------------
  # SIBLING MIRROR ROOTS. Two arms in two different trees, each quoting its
  # OWN root in a diagnostic exactly as a real compiler does — that is what
  # `detectCompilerLibRoot` makes every arm do. Before per-arm normalisation
  # this pair was scored CHANGED, and on the real corpus that shape produced
  # ~163 false rows. It must now be identical.
  mkdir -p "$_self/mirror/a/zig-out/bin" "$_self/mirror/b/zig-out/bin" || return 2
  # The diagnostic shape matters. `norm` already collapses a whole line that
  # begins "  ok compile", so a fake that emitted only that line would be
  # normalised to COMPILED and this control would pass without the per-arm
  # rule ever running. Emit the root inside a line no other rule touches.
  _self_mirror='#!/bin/sh
root=$(cd "$(dirname "$0")/../.." && pwd)
printf "answer\n"
printf "error: cannot open %s/lib/std.id\n" "$root" >&2
printf "note: scratch at %s\n" "${TMPDIR:-/tmp}" >&2
exit 0
'
  printf '%s' "$_self_mirror" >"$_self/mirror/a/zig-out/bin/idol"
  printf '%s' "$_self_mirror" >"$_self/mirror/b/zig-out/bin/idol"
  chmod +x "$_self/mirror/a/zig-out/bin/idol" "$_self/mirror/b/zig-out/bin/idol"
  NULL_CONTROL=1 compare_subjects \
    "$_self/mirror/a/zig-out/bin/idol" "$_self/mirror/b/zig-out/bin/idol" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 0 ] || {
    echo "differential: selftest FAIL — sibling mirror roots scored as a difference" >&2
    return 1
  }

  # THE `examples/shc/cwd.id` SHAPE: a program whose entire output is its own
  # working directory. Each arm has its own by construction, so this is a
  # harness fact and must not be a row.
  mkdir -p "$_self/cwd/a/zig-out/bin" "$_self/cwd/b/zig-out/bin" || return 2
  _self_cwd='#!/bin/sh
pwd
'
  printf '%s' "$_self_cwd" >"$_self/cwd/a/zig-out/bin/idol"
  printf '%s\n# b\n' "$_self_cwd" >"$_self/cwd/b/zig-out/bin/idol"
  chmod +x "$_self/cwd/a/zig-out/bin/idol" "$_self/cwd/b/zig-out/bin/idol"
  compare_subjects "$_self/cwd/a/zig-out/bin/idol" "$_self/cwd/b/zig-out/bin/idol" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 0 ] || {
    echo "differential: selftest FAIL — per-arm working directory scored as a difference" >&2
    return 1
  }

  # ...AND THE NORMALISER MUST NOT EAT A REAL DIFFERENCE THAT HAPPENS TO
  # CONTAIN A PATH. Same two roots, different diagnostic text. If per-arm
  # substitution were written loosely enough to erase this, every genuine
  # diagnostic regression would go unreported — the optimistic direction, and
  # the one that costs the most.
  mkdir -p "$_self/mirror/c/zig-out/bin" || return 2
  printf '%s' "$_self_mirror" | sed 's#cannot open#REFUSED, cannot open#' \
    >"$_self/mirror/c/zig-out/bin/idol"
  chmod +x "$_self/mirror/c/zig-out/bin/idol"
  compare_subjects "$_self/mirror/a/zig-out/bin/idol" \
    "$_self/mirror/c/zig-out/bin/idol" \
    "$_self/list" "$_self/source" >/dev/null 2>&1
  _self_rc=$?
  [ "$_self_rc" -eq 1 ] || {
    echo "differential: selftest FAIL — per-arm normalisation erased a real row" >&2
    return 1
  }

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

  echo "differential: selftest PASS — sibling-mirror null row, per-arm cwd, real row survives normalisation, one observation, comparator damage, zero-subject, signal and timeout controls"
  return 0
}

# NULL CONTROL. One compiler, placed under two mirror roots, compared with
# itself over the real subject list. Every row it reports is harness noise, by
# construction: the machine code on the two arms is the same bytes. The two
# roots are DIFFERENT SPELLINGS because that is the condition being controlled
# for — a null control run from one root would exercise nothing.
#
# The copy is a copy and not a symlink on purpose: `detectCompilerLibRoot`
# calls realpath on argv[0], so a symlinked arm resolves back to the original
# tree and the mirror roots collapse into one. `lib` IS a symlink, because it
# is only opened by path and copying a stdlib per arm buys nothing.
null_control() {
  _nc_bin=$1
  _nc_list=$2
  _nc_source=$3
  _nc_home=$(cd "$(dirname "$_nc_bin")" && pwd)
  case "$_nc_home" in
    */zig-out/bin) _nc_home=$(cd "$_nc_home/../.." && pwd) ;;
    *)
      echo "differential: null control needs a compiler at <tree>/zig-out/bin/, got $_nc_bin" >&2
      return 2
      ;;
  esac
  [ -f "$_nc_home/lib/std.id" ] || {
    echo "differential: null control cannot find $_nc_home/lib/std.id" >&2
    return 2
  }
  for _nc_arm in a b; do
    mkdir -p "$WORK/null.$_nc_arm/zig-out/bin" || return 2
    cp "$_nc_bin" "$WORK/null.$_nc_arm/zig-out/bin/idol" || return 2
    ln -s "$_nc_home/lib" "$WORK/null.$_nc_arm/lib" || return 2
  done
  printf 'differential: NULL CONTROL — one compiler under two mirror roots\n'
  NULL_CONTROL=1 compare_subjects \
    "$WORK/null.a/zig-out/bin/idol" "$WORK/null.b/zig-out/bin/idol" \
    "$_nc_list" "$_nc_source"
  _nc_rc=$?
  if [ "$_nc_rc" -eq 0 ]; then
    printf 'differential: NULL CONTROL PASS — the harness reports zero rows for identical machine code\n'
  else
    printf 'differential: NULL CONTROL FAIL (status %s) — every row above is harness noise, and a real comparison on this list cannot be believed until it is zero\n' "$_nc_rc" >&2
  fi
  return $_nc_rc
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

subjectlist() {
  # The default subject list. `find`, not `git ls-files`: this runs against a
  # mirror root that may be a plain copy, and an enumerator that answers zero
  # in such a tree is the GAP-220 failure. Zero here is still a failure — the
  # zero-subject guard in compare_subjects owns that — but it is reached
  # honestly.
  _sl_out=$1
  (cd "$ROOT" && find examples lib scripts -name '*.id' -type f 2>/dev/null | sort) >"$_sl_out"
  [ -s "$_sl_out" ] || {
    echo "differential: default subject list resolved to zero files under $ROOT" >&2
    return 2
  }
  return 0
}

if [ "${1:-}" = "--null-control" ]; then
  shift
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || {
    echo "usage: gate/differential.sh --null-control <idol> [file-list]" >&2
    exit 2
  }
  [ -x "$1" ] || {
    echo "differential: compiler path absent or not executable: $1" >&2
    exit 2
  }
  NCBIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
  if [ "$#" -eq 2 ]; then
    NCLIST=$2
    [ -r "$NCLIST" ] || {
      echo "differential: unreadable subject list: $NCLIST" >&2
      exit 2
    }
  else
    NCLIST="$WORK/subjects"
    subjectlist "$NCLIST" || exit 2
  fi
  null_control "$NCBIN" "$NCLIST" "$ROOT"
  exit $?
fi

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
  subjectlist "$LIST" || exit 2
fi
[ -r "$LIST" ] || {
  echo "differential: unreadable subject list: $LIST" >&2
  exit 2
}

compare_subjects "$BASE" "$CAND" "$LIST" "$ROOT"
exit $?
