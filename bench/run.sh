#!/bin/bash
# bench/run.sh — skeptical benchmark harness for the Idol native compiler.
#
# Usage:
#   ./run.sh                 # full run: 21 interleaved rounds per benchmark
#   ./run.sh --quick         # smoke run: 5 rounds
#   ./run.sh --progs "sum fib" --compilers "clang"
#   ./run.sh --route production   # --route is REQUIRED (restricted|production); there is no default.
#   A bare invocation is not a production-compiler campaign.
#
# Pipeline per benchmark program P and compiler C:
#   1. Build P with the Idol compiler for this run's route. Restricted route:
#      nativebench is built from lib/compiler/native.id at the start of this
#      run with --no-cache (never a stale binary); P.id is piped through it,
#      hex-decoded, and linked with `ld -e _idolmain`. Production route: P.id
#      is compiled directly by the production compiler
#      (zig-out/bin/idol compile P.id --backend native --no-cache), which
#      emits a linked Mach-O executable directly. The EXACT producer binary
#      is hashed (PRODUCER_SHA) and the timer must attribute those exact
#      bytes every program, or the run aborts (producer binding).
#   2. Build P with each C compiler (clang -O3, gcc -O3 where present).
#   3. CORRECTNESS GATE: every binary must exit with the same code AND emit
#      byte-identical stdout vs the oracle (first of clang, gcc; idol only if
#      no C compiler is present). A wrong answer is a bug, not data.
#   4. Timing via the Idol benchmark timer (bench/timing.id, authoritative):
#      3 warmup runs, then N INTERLEAVED timed rounds
#      (idol, clang, gcc, idol, clang, gcc, ...) so thermal drift and
#      background load affect all competitors equally. The timer validates
#      exit code and stdout on every invocation, captures t1 immediately
#      after procrun returns, and reduces with separator-aware median,
#      Welford variance, and percentiles. The timer FAILS CLOSED when it
#      cannot hash the compiler binary (empty sha256 = unattributed subject).
#   5. timing.py is an independent cross-check verifier (not a timer): it
#      recomputes every statistic from the timer's raw samples, verifies
#      exact agreement, rejects unattributed timer output, and emits the
#      vs_best verdict on the DECLARED ESTIMAND median(idol)-median(rival)
#      as % of the rival median. Decision: win/loss iff the 95% bootstrap
#      percentile CI (B=2000, fixed seed) excludes 0; 'equivalent' iff the
#      90% CI lies WHOLLY inside the predeclared band [-2%,+2%]; otherwise
#      "inconclusive" (never "tie"). Welch's t with Welch-Satterthwaite df
#      on the means is reported as a DIAGNOSTIC only; a mean/median
#      disagreement is flagged, never silently resolved.
#   6. Static metrics, like-for-like only: LINKED EXECUTABLE sizes
#      (idol .idol vs clang/gcc executables) and OBJECT sizes
#      (clang/gcc -c objects; idol object only on the restricted route,
#      where it is raw emitted code bytes, labeled as such). No single
#      size ratio across unequal artifact boundaries. Plus source-to-
#      executable compile time (median of 5 interleaved attempts per
#      compiler, produced by bench/ctime.py under a hard validation
#      contract, with the idol producer binary hashed into the record).
#   7. RESULTS.md is rewritten with the full table — wins AND losses — plus
#      the standing corrections section emitted from bench/corrections.json
#      on EVERY run (no regeneration can delete it), the run-time
#      discovered comparator identities, the qualification banner, and the
#      producer binding record.
#
# Honesty rules, enforced in code:
#   - set -e -o pipefail: any build failure aborts, including a failed
#     producer behind a pipe (decoder-after-failed-producer cannot report
#     success); no benchmark is silently skipped.
#   - A compile-time duration counts as a success ONLY after every required
#     stage succeeded and the artifact was validated (exists, nonzero size).
#     Failed attempts are recorded as FAILED work, never in success medians.
#   - The correctness gate aborts on exit-code OR stdout mismatch.
#   - Comparator identity comes from `cc --version` at run time, recorded
#     per run; never assumed from command names.
#   - RESULTS.md lists every program x every compiler. No filter exists.
#   - Primary metric is the median (robust; outlier removal unnecessary).
#   - A QUALIFIED comparison claim requires observed load conditions
#     (readable load, below threshold at start, re-sampled before each
#     program). An unavailable observation marks the run UNQUALIFIED
#     (exploratory): the campaign still runs, but no qualified claim may
#     be drawn from it.
set -e -u -o pipefail
BENCH="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$BENCH/.." && pwd)"
WORK="$BENCH/.work"
mkdir -p "$WORK"
rm -f "$WORK/.unqualified" "$WORK/.load_samples"

ROUNDS=21
PROGS="sum arith fib nest div mul13 bigconst zerotrip upbranch startup brm1 brm2 brm3 divv divm divd dgcd divpow2 ceildiv mulc mulh madd sred1 powmod popc bitr xsft absd cltz nest3d unroll mixop loopinv satadd regp ilp stride3"
WANT_COMPILERS="clang gcc"
ROUTE=""
ROUTE_EXPLICIT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --quick) ROUNDS=5 ;;
    --progs) PROGS="$2"; shift ;;
    --compilers) WANT_COMPILERS="$2"; shift ;;
    --route) ROUTE="$2"; ROUTE_EXPLICIT=1; shift ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done
if [ "$ROUTE_EXPLICIT" -ne 1 ]; then
  echo "bench: FATAL: --route is required (restricted|production)." >&2
  echo "bench: a bare invocation is not a production-compiler campaign: the restricted route" >&2
  echo "bench: is a research path, not the production compiler. Pass --route production" >&2
  echo "bench: for release/performance admission." >&2
  exit 2
fi
case "$ROUTE" in
  restricted|production) ;;
  *) echo "unknown route: $ROUTE (expected restricted|production)" >&2; exit 2 ;;
esac
echo "bench: route=$ROUTE (explicit)"

# --- 0a. Hang watchdog for the restricted-route producer ---
# The restricted route pipes program source through nativebench, which has a
# known defect: it hangs on ANY stdin (pre-existing .id-runtime stdin:read()
# hang, same class as the lib/linker/link.id hang). pipefail catches failed
# producers but NOT hung ones, so one hung producer would silently hang the
# whole campaign forever. The producer therefore runs under `timeout`; a hang
# (timeout rc 124 on GNU, 142 on the mini's POSIX shim) fails the campaign
# LOUDLY (exit 7), never silently.
# Override: BENCH_PRODUCER_TIMEOUT (seconds, default 300).
PRODUCER_TIMEOUT="${BENCH_PRODUCER_TIMEOUT:-300}"
if ! command -v timeout >/dev/null 2>&1; then
  echo "bench: FATAL: 'timeout' not found; the restricted-route hang watchdog cannot run." >&2
  exit 4
fi

# --- 0. Load observation and qualification gate ---
# QUALIFIED=1 requires: load readable AND numeric, threshold numeric, load
# below threshold at start, and re-sampled (still readable and below) before
# each program's timing. ANY unavailable observation or mid-run exceedance
# marks the run UNQUALIFIED (exploratory): the campaign continues, but the
# report carries the banner and no qualified claim may be drawn.
# High load at start still aborts (known-bad condition, not an unavailable
# observation). Test overrides: BENCH_LOAD forces the compared value;
# BENCH_MAXLOAD overrides the threshold.
QUALIFIED=1
QUALIFY_NOTE=""
bench_load_read() {
    local load=""
    if [ "$(uname -s)" = "Darwin" ]; then
        # '|| true': with pipefail a failing sysctl must degrade to the
        # empty-load (unqualified) path below, not abort the harness.
        load="$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}' || true)"
    elif [ -r /proc/loadavg ]; then
        load="$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || true)"
    fi
    [ -n "${BENCH_LOAD:-}" ] && load="$BENCH_LOAD"
    printf '%s' "$load"
}
bench_load_valid() { # $1=load $2=maxload -> 0 iff both are valid numbers
    # A genuine numeric parse, not a character whitelist: rejects "", ".",
    # "1.2.3", "-1", "1e3", and anything with whitespace. Malformed
    # observations must not count as valid load measurements.
    local re='^[0-9]+(\.[0-9]+)?$'
    [[ "$1" =~ $re ]] && [[ "$2" =~ $re ]]
}
mark_unqualified() { # $1=reason
    QUALIFIED=0
    QUALIFY_NOTE="$1"
    echo "$1" > "$WORK/.unqualified"
    echo "bench: UNQUALIFIED (exploratory): $1" >&2
}
MAXLOAD="${BENCH_MAXLOAD:-8}"
LOAD_START="$(bench_load_read)"
if ! bench_load_valid "$LOAD_START" "$MAXLOAD"; then
    mark_unqualified "load observation unavailable at start (load='${LOAD_START:-unreadable}', threshold='$MAXLOAD')"
elif awk -v l="$LOAD_START" -v m="$MAXLOAD" 'BEGIN{exit !(l >= m)}'; then
    echo "bench: 1-min load average $LOAD_START is not below $MAXLOAD; aborting." >&2
    echo "bench: wait for the machine to idle, or override with BENCH_LOAD/BENCH_MAXLOAD for testing." >&2
    exit 5
else
    echo "bench: load gate ok (1-min avg $LOAD_START < $MAXLOAD)"
fi
# A BENCH_LOAD override replaces the observed load with a synthetic value.
# Test controls may use it, but the run can never be a qualified real-world
# observation: force EXPLORATORY/UNQUALIFIED.
if [ -n "${BENCH_LOAD:-}" ]; then
    mark_unqualified "BENCH_LOAD='${BENCH_LOAD}' override active: compared load is synthetic, not an observed machine load"
fi
echo "$LOAD_START" > "$WORK/.load_start"

ARCH="$(uname -m)"; OS="$(uname -s)"
echo "bench: host ${ARCH}-${OS}, rounds=${ROUNDS}"
if [ "${ARCH}-${OS}" != "arm64-Darwin" ] && [ "${ARCH}-${OS}" != "aarch64-Linux" ]; then
  echo "bench: no backend for ${ARCH}-${OS} yet (see platforms/). aborting." >&2
  exit 3
fi
if [ "$OS" = "Darwin" ]; then
  if ! SDK="$(xcrun --show-sdk-path)"; then
    echo "bench: FATAL: xcrun --show-sdk-path failed on Darwin; cannot locate the macOS SDK." >&2
    exit 4
  fi
else
  # Non-Darwin hosts (e.g. aarch64-Linux) need no macOS SDK: the native
  # backend emits linked executables directly and no link step reads $SDK.
  SDK=""
fi

# --- 1. Build the Idol compiler for this run's route (never stale) ---
IDOL_BIN="$REPO/zig-out/bin/idol"
if [ ! -x "$IDOL_BIN" ]; then
  echo "bench: $IDOL_BIN missing; run 'zig build' in the repo first." >&2; exit 4
fi
NATIVE="$WORK/nativebench"
if [ "$ROUTE" = "restricted" ]; then
  echo "bench: compiling lib/compiler/native.id -> nativebench (--no-cache)"
  "$IDOL_BIN" compile "$REPO/lib/compiler/native.id" --backend native --no-cache -o "$NATIVE"
  if [ ! -x "$NATIVE" ] || [ ! -s "$NATIVE" ]; then
    echo "bench: nativebench build failed (missing or empty)." >&2; exit 4
  fi
else
  echo "bench: production route: programs compile directly with $IDOL_BIN"
fi

# --- 1b. Producer binding: the exact binary whose bytes become the programs.
# Restricted route: $NATIVE (nativebench) emits the program bytes; it was
# itself built by $IDOL_BIN from lib/compiler/native.id --no-cache.
# Production route: $IDOL_BIN emits the program bytes directly.
# The timer is handed the EXACT path (never a bare name) and must attribute
# its sha256; run.sh cross-checks the attribution every program.
REPO_REV="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo "unknown")"
if [ "$ROUTE" = "restricted" ]; then
  PRODUCER_BIN="$NATIVE"
  PRODUCER_BUILD="nativebench built by $IDOL_BIN from lib/compiler/native.id --no-cache at rev $REPO_REV"
else
  PRODUCER_BIN="$IDOL_BIN"
  PRODUCER_BUILD="programs compiled by $IDOL_BIN --backend native --no-cache at rev $REPO_REV"
fi
IDOL_BIN_SHA="$(sha256sum "$IDOL_BIN" | awk '{print $1}')"
if [ "$ROUTE" = "restricted" ]; then
  PRODUCER_SHA="$(sha256sum "$NATIVE" | awk '{print $1}')"
else
  PRODUCER_SHA="$IDOL_BIN_SHA"
fi
case "$PRODUCER_SHA" in ''|MISSING|*[!0-9a-f]* )
  echo "bench: FATAL: cannot hash producer binary $PRODUCER_BIN" >&2; exit 4;;
esac
echo "bench: producer $PRODUCER_BIN sha256=${PRODUCER_SHA:0:16}... rev=$REPO_REV"

# --- Build the Idol benchmark timer (authoritative timing path) ---
# The timer (bench/timing.id) does all timing: interleaved rounds, per-invocation
# validation, and statistical reduction. timing.py is now a verifier only.
TIMER="$WORK/idol-timer"
echo "bench: compiling bench/timing.id -> idol-timer (--no-cache)"
"$IDOL_BIN" compile "$BENCH/timing.id" --backend native --no-cache -o "$TIMER"
if [ ! -x "$TIMER" ] || [ ! -s "$TIMER" ]; then
  echo "bench: idol-timer build failed (missing or empty)." >&2; exit 4
fi

# --- compiler discovery: identity from --version at run time, never assumed ---
COMPILERS="idol"
CLANG_VERSION=""; GCC_VERSION=""
if command -v clang >/dev/null 2>&1; then
  COMPILERS="$COMPILERS clang"
  CLANG_VERSION="$(clang --version 2>/dev/null | head -1 || true)"
fi
if command -v gcc >/dev/null 2>&1; then
  GCC_VERSION="$(gcc --version 2>/dev/null | head -1 || true)"
  if [ -n "$GCC_VERSION" ]; then COMPILERS="$COMPILERS gcc"; fi
fi
# honor --compilers filter
FILTERED="idol"
for c in $WANT_COMPILERS; do
  case " $COMPILERS " in *" $c "*) FILTERED="$FILTERED $c";; esac
done
COMPILERS="$FILTERED"
echo "bench: compilers:$COMPILERS"
[ -n "$CLANG_VERSION" ] && echo "bench: clang identity: $CLANG_VERSION"
[ -n "$GCC_VERSION" ] && echo "bench: gcc identity: $GCC_VERSION"
# The oracle for the correctness gate: first trusted C compiler, else idol
# (vacuous single-compiler case, disclosed in the report).
ORACLE="idol"
for c in clang gcc; do case " $COMPILERS " in *" $c "*) ORACLE="$c"; break;; esac; done
echo "bench: correctness oracle: $ORACLE"

# The restricted-route producer runs under the hang watchdog: producer and
# decoder are separate steps with explicit checks, so a failed (or hung)
# producer can never be concealed by a successful decode. A hang (rc 124/142,
# the timeout-shim kill codes) aborts the campaign LOUDLY (exit 7) instead of
# hanging it silently.
idol_build() { # $1=prog -> $WORK/$1.idol (executable)
  if [ "$ROUTE" = "restricted" ]; then
    # Hang watchdog: nativebench hangs on any stdin (known .id-runtime
    # defect); pipefail cannot catch a hang, so the producer runs under
    # timeout and a hang (rc 124/142) aborts the campaign LOUDLY (exit 7).
    set +e
    timeout "$PRODUCER_TIMEOUT" "$NATIVE" < "$BENCH/programs/$1.id" > "$WORK/$1.hex"
    rc=$?
    set -e
    if [ "$rc" -eq 124 ] || [ "$rc" -eq 142 ]; then
      echo "bench: FATAL: restricted-route producer HUNG for $1 (nativebench stdin hang; killed by watchdog after ${PRODUCER_TIMEOUT}s, rc=$rc). Campaign aborted loudly." >&2
      exit 7
    elif [ "$rc" -ne 0 ]; then
      echo "bench: FATAL: restricted-route producer failed for $1 (rc=$rc)." >&2
      exit 7
    fi
    # The mini's `timeout` shim can return 0 when the command cannot even be
    # exec'd; an empty producer output is never a successful build.
    if [ ! -s "$WORK/$1.hex" ]; then
      echo "bench: FATAL: restricted-route producer emitted no bytes for $1 (rc=$rc)." >&2
      exit 7
    fi
    xxd -r -p "$WORK/$1.hex" > "$WORK/$1.o" \
      || { echo "bench: FATAL: hex decode failed for $1." >&2; exit 7; }
    ld -arch arm64 -e _idolmain -platform_version macos 14.0 14.0 \
       -syslibroot "$SDK" "$WORK/$1.o" -lSystem -o "$WORK/$1.idol"
  else
    # Production route: the production compiler emits a linked Mach-O
    # executable directly (--no-cache keeps every program compile hermetic).
    PLOG="$WORK/$1.prod-compile.log"
    if ! "$IDOL_BIN" compile "$BENCH/programs/$1.id" --backend native --no-cache \
        -o "$WORK/$1.idol" >"$PLOG" 2>&1; then
      echo "bench: production compile of $1 FAILED:" >&2
      tail -5 "$PLOG" >&2
      exit 4
    fi
    if [ ! -x "$WORK/$1.idol" ] || [ ! -s "$WORK/$1.idol" ]; then
      echo "bench: production compile of $1 produced no valid artifact." >&2; exit 4
    fi
  fi
}
clang_build() { clang -O3 "$BENCH/programs/$1.c" -o "$WORK/$1.clang"; }
gcc_build()   { gcc -O3 "$BENCH/programs/$1.c" -o "$WORK/$1.gcc"; }
size_of() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1"; }
# best-effort __TEXT/__DATA split from `size -m`; prints "text data" or "0 0"
seg_text_data() {
  size -m "$1" 2>/dev/null | awk '/^Segment/{if($2=="__TEXT:")t=$3; else if($2 ~ /^__DATA/)d+=$3} END{print (t+0)" "(d+0)}'
}

RESULT_JSON="$WORK/results.json"
python3 - << 'PYEOF' > "$RESULT_JSON"
import json
print(json.dumps({"meta": {}, "programs": {}}))
PYEOF

for P in $PROGS; do
  echo "bench: [$P] building..."
  for C in $COMPILERS; do "${C}_build" "$P"; done

  # --- 3. correctness gate: exit code AND byte-identical stdout vs oracle ---
  # The oracle runs first so the reference exists before any comparison,
  # regardless of compiler ordering. The `|| RC=$?` idiom is load-bearing:
  # benchmark programs legitimately exit nonzero (e.g. sum exits 128), and a
  # bare `cmd; RC=$?` under `set -e` would abort the harness here instead of
  # recording the code.
  REF_OUT="$WORK/$P.oracle.out"
  REF_RC=0
  timeout 120 "$WORK/$P.$ORACLE" > "$REF_OUT" 2>/dev/null || REF_RC=$?
  for C in $COMPILERS; do
    [ "$C" = "$ORACLE" ] && continue
    RC=0
    timeout 120 "$WORK/$P.$C" > "$WORK/$P.$C.out" 2>/dev/null || RC=$?
    if [ "$RC" != "$REF_RC" ] || ! cmp -s "$WORK/$P.$C.out" "$REF_OUT"; then
      echo "bench: CORRECTNESS FAIL [$P]: $C differs from oracle $ORACLE (rc $RC vs $REF_RC, stdout compared byte-identical). aborting." >&2
      exit 5
    fi
  done
  echo "bench: [$P] correctness ok vs oracle $ORACLE (exit $REF_RC, stdout byte-identical)"

  # --- 0b. per-program load re-sample: conditions across the measured
  # intervals, not one pre-campaign sample. A violation marks the run
  # UNQUALIFIED (exploratory) but does not stop useful work.
  LOAD_BEFORE="$(bench_load_read)"
  if ! bench_load_valid "$LOAD_BEFORE" "$MAXLOAD" \
      || awk -v l="$LOAD_BEFORE" -v m="$MAXLOAD" 'BEGIN{exit !(l >= m)}'; then
    mark_unqualified "load condition violated before program $P timing (load='${LOAD_BEFORE:-unreadable}' vs threshold $MAXLOAD)"
  fi
  echo "$P ${LOAD_BEFORE:-unreadable}" >> "$WORK/.load_samples"

  # --- 4/5. timing via the Idol timer (authoritative); Python verifies ---
  # The Idol timer does the timing: interleaved rounds, per-invocation exit/stdout
  # validation, Welford variance, and percentile reduction. The timer receives
  # the EXACT producer binary path and hashes its bytes; it fails closed when
  # the hash is unavailable. timing.py independently recomputes every stat
  # from the timer's raw samples (cross-check), rejects unattributed output,
  # and emits the report JSON with the vs_best verdict on the declared
  # median-difference estimand. Nonsignificance is "inconclusive", never "tie".
  REF_HEX=$(xxd -p "$REF_OUT" | tr -d '\n')
  TIMER_NBIN=0
  TIMER_BINS=""
  for C in $COMPILERS; do
    TIMER_BINS="$TIMER_BINS $C $WORK/$P.$C"
    TIMER_NBIN=$((TIMER_NBIN+1))
  done
  "$TIMER" $ROUNDS 3 $REF_RC "$REF_HEX" "$PRODUCER_BIN" "$ROUTE" "$REPO_REV" \
    $TIMER_NBIN $TIMER_BINS > "$WORK/$P.timer.json"

  # --- 4b. producer binding check: the timer's attribution must name the
  # exact hashed binary this run used. A changed/mismatched/unattributed
  # subject aborts the campaign — the main entry path enforces this, not
  # just a standalone control.
  TIMER_COMP="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("compiler",""))' "$WORK/$P.timer.json")"
  TIMER_SHA="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("compiler_sha256",""))' "$WORK/$P.timer.json")"
  if [ -z "$TIMER_SHA" ] || [ "$TIMER_SHA" != "$PRODUCER_SHA" ] || [ "$TIMER_COMP" != "$PRODUCER_BIN" ]; then
    echo "bench: PRODUCER BINDING FAIL [$P]: timer attributes compiler='$TIMER_COMP' sha256='${TIMER_SHA:-empty}'; run used '$PRODUCER_BIN' sha256='$PRODUCER_SHA'. Subject changed mid-run or unattributed. aborting." >&2
    exit 6
  fi
  python3 "$BENCH/timing.py" < "$WORK/$P.timer.json" > "$WORK/$P.time.json"

  # --- 6a. artifact sizes: like-for-like boundaries only ---
  # Executables: idol .idol, clang .clang, gcc .gcc — all linked executables.
  # Objects: clang/gcc -c objects. Idol object exists only on the restricted
  # route, where it is RAW EMITTED CODE BYTES (not a Mach-O object) and is
  # labeled as such. The report never emits one ratio across unequal
  # boundaries; code/data are identified separately via `size -m`.
  SZ_IDOL_EXE=$(size_of "$WORK/$P.idol")
  SZ_CLANG_EXE=""; SZ_GCC_EXE=""
  case " $COMPILERS " in *" clang "*) SZ_CLANG_EXE=$(size_of "$WORK/$P.clang");; esac
  case " $COMPILERS " in *" gcc "*) SZ_GCC_EXE=$(size_of "$WORK/$P.gcc");; esac
  SZ_IDOL_OBJ=""; IDOL_OBJ_KIND="none"
  if [ "$ROUTE" = "restricted" ]; then
    SZ_IDOL_OBJ=$(size_of "$WORK/$P.o")
    IDOL_OBJ_KIND="raw-code-bytes (not a Mach-O object)"
  fi
  SZ_CLANG_OBJ=""; SZ_GCC_OBJ=""
  if case " $COMPILERS " in *" clang "*) true;; *) false;; esac; then
    clang -O3 -c "$BENCH/programs/$P.c" -o "$WORK/$P.clang.o" 2>/dev/null && SZ_CLANG_OBJ=$(size_of "$WORK/$P.clang.o")
  fi
  if case " $COMPILERS " in *" gcc "*) true;; *) false;; esac; then
    gcc -O3 -c "$BENCH/programs/$P.c" -o "$WORK/$P.gcc.o" 2>/dev/null && SZ_GCC_OBJ=$(size_of "$WORK/$P.gcc.o")
  fi
  SEG_IDOL="$(seg_text_data "$WORK/$P.idol")"
  SEG_CLANG=""; SEG_GCC=""
  case " $COMPILERS " in *" clang "*) SEG_CLANG="$(seg_text_data "$WORK/$P.clang")";; esac
  case " $COMPILERS " in *" gcc "*) SEG_GCC="$(seg_text_data "$WORK/$P.gcc")";; esac

  # --- 6b. compile time: source -> executable, 5 interleaved attempts ---
  # bench/ctime.py: a duration counts as a success ONLY after every required
  # stage succeeded and the artifact was validated (exists, nonzero size).
  # Failed attempts are recorded as FAILED work, never in success medians.
  # ctime.py hashes the idol producer binary into its own record.
  CTIME="$WORK/$P.ctime.json"
  python3 "$BENCH/ctime.py" "$NATIVE" "$BENCH" "$P" "$SDK" "$WORK" "$CTIME" "$COMPILERS" "$ROUTE" "$IDOL_BIN"

  # --- merge into results ---
  python3 - "$RESULT_JSON" "$WORK/$P.time.json" "$CTIME" "$P" \
          "$CLANG_VERSION" "$GCC_VERSION" "$ORACLE" \
          "$PRODUCER_BIN" "$PRODUCER_SHA" "$IDOL_BIN_SHA" "$PRODUCER_BUILD" "$REPO_REV" \
          "$LOAD_BEFORE" "$MAXLOAD" \
          "$SZ_IDOL_EXE" "$SZ_CLANG_EXE" "$SZ_GCC_EXE" \
          "$SZ_IDOL_OBJ" "$IDOL_OBJ_KIND" "$SZ_CLANG_OBJ" "$SZ_GCC_OBJ" \
          "$SEG_IDOL" "$SEG_CLANG" "$SEG_GCC" << 'PYEOF'
import json, sys
(res_path, time_path, ctime_path, prog,
 clang_v, gcc_v, oracle,
 producer_bin, producer_sha, idol_bin_sha, producer_build, repo_rev,
 load_before, maxload,
 sz_idol_exe, sz_clang_exe, sz_gcc_exe,
 sz_idol_obj, idol_obj_kind, sz_clang_obj, sz_gcc_obj,
 seg_idol, seg_clang, seg_gcc) = sys.argv[1:25]
res = json.load(open(res_path))
tj = json.load(open(time_path))
ct = json.load(open(ctime_path))
def opt_int(x):
    return int(x) if x and x.strip() else None
def seg_pair(s):
    try:
        t, d = s.split()
        return {"text": int(t), "data": int(d)}
    except Exception:
        return {"text": None, "data": None}
res["programs"][prog] = {
    "timing": tj,
    "compile_time": ct,
    "producer": {
        "compiler_path": producer_bin,
        "compiler_sha256": producer_sha,
        "idol_bin_sha256": idol_bin_sha,
        "build": producer_build,
        "route": tj.get("timer_identity", {}).get("config"),
        "repo_rev": repo_rev,
        "timer_attributed_path": tj.get("timer_identity", {}).get("compiler"),
        "timer_attributed_sha256": tj.get("timer_identity", {}).get("compiler_sha256"),
    },
    "load_before": load_before or "unreadable",
    "load_threshold": maxload,
    "sizes": {
        "executable_bytes": {"idol": opt_int(sz_idol_exe),
                             "clang": opt_int(sz_clang_exe),
                             "gcc": opt_int(sz_gcc_exe)},
        "object_bytes": {"idol": opt_int(sz_idol_obj),
                         "clang": opt_int(sz_clang_obj),
                         "gcc": opt_int(sz_gcc_obj)},
        "idol_object_kind": idol_obj_kind,
        "segments_text_data": {"idol": seg_pair(seg_idol),
                               "clang": seg_pair(seg_clang),
                               "gcc": seg_pair(seg_gcc)},
    },
    # discovered comparator identity, per row: never assumed from names.
    "oracle_versions": {"clang": clang_v or None, "gcc": gcc_v or None},
    "correctness_oracle": oracle,
}
json.dump(res, open(res_path, "w"), indent=2)
PYEOF
  echo "bench: [$P] done."
done

# --- 7. render RESULTS.md (structural format; no prose) ---
# --- 8. append this run's per-program verdicts to bench/results/history.jsonl ---
# The standing corrections section is emitted from bench/corrections.json on
# EVERY run: the evidence producer owns it, so no report regeneration can
# delete it. Amend corrections only by committing a change to that file.
python3 - "$RESULT_JSON" "$BENCH/RESULTS.md" "$ROUNDS" "$BENCH/results/history.jsonl" "$REPO" \
        "$BENCH/corrections.json" "$CLANG_VERSION" "$GCC_VERSION" "$ORACLE" "$ROUTE" \
        "$QUALIFIED" "$QUALIFY_NOTE" "$LOAD_START" "$MAXLOAD" << 'PYEOF'
import json, sys, datetime, subprocess
(res_path, out_path, rounds, hist_path, repo, corr_path, clang_v, gcc_v,
 oracle, route, qual_state, qual_note, load0, maxload) = sys.argv[1:15]
# History is kept per route: restricted and production verdicts must never
# mix in one per-program history table.
if route != "restricted":
    hist_path = hist_path.replace("history.jsonl", "history-production.jsonl")
res = json.load(open(res_path))

try:
    corr = json.load(open(corr_path))
    directives = corr["directives"]
    assert isinstance(directives, list) and directives
except Exception as e:
    print(f"bench: FATAL: cannot load producer corrections from {corr_path}: {e}",
          file=sys.stderr)
    sys.exit(3)

def commit_of(repo):
    try:
        p = subprocess.run(["git", "-C", repo, "rev-parse", "--short", "HEAD"],
                           capture_output=True, text=True, timeout=20)
        return p.stdout.strip() or "unknown"
    except Exception:
        return "unknown"

verdicts = {}
for prog, d in res["programs"].items():
    vb = d["timing"].get("vs_best") or {}
    verdicts[prog] = {
        "verdict": vb.get("verdict", "?"),
        "margin_pct": round(vb.get("margin", 0.0) * 100, 2),
        "p_mean_diag": vb.get("welch_p_mean"),
        "sig": bool(vb.get("significant", False)),
        "equivalent": bool(vb.get("equivalent", False)),
        "mean_median_conflict": bool(vb.get("mean_median_conflict", False)),
        "rival": vb.get("rival", "?"),
        "idol_med": vb.get("idol_median"),
        "rival_med": vb.get("rival_median"),
        "ci95": vb.get("ci95_median_diff_pct"),
        "ci90": vb.get("ci90_median_diff_pct"),
    }
entry = {
    "ts": datetime.datetime.now().isoformat(timespec="seconds"),
    "commit": commit_of(repo),
    "rounds": int(rounds),
    "route": route,
    "qualified": qual_state == "1",
    "qualify_note": qual_note or None,
    "load_start": load0 or None,
    "load_threshold": maxload,
    "oracle": oracle,
    "oracle_versions": {"clang": clang_v or None, "gcc": gcc_v or None},
    "verdicts": verdicts,
}
with open(hist_path, "a") as f:
    f.write(json.dumps(entry) + "\n")

hist = []
for line in open(hist_path):
    line = line.strip()
    if line:
        hist.append(json.loads(line))
agg = {}
for e in hist:
    for prog, v in e["verdicts"].items():
        a = agg.setdefault(prog, {"runs": 0, "first": e["ts"], "margins": [],
                                  "last_verdict": "?", "last_margin": 0.0})
        a["runs"] += 1
        a["margins"].append(v["margin_pct"])
        a["last_verdict"] = v["verdict"]
        a["last_margin"] = v["margin_pct"]

def fmt_bytes(m):
    return ", ".join(f"{k} {v}" for k, v in m.items() if v)

L = []
L.append("| field | value |")
L.append("|---|---|")
L.append("| title | Benchmark results |")
L.append(f"| oracle_versions | clang: {clang_v or 'absent'} ; gcc: {gcc_v or 'absent'} |")
L.append(f"| correctness_oracle | {oracle} (exit code + byte-identical stdout) |")
L.append(f"| route | {route} |")
L.append(f"| load_threshold | {maxload} (1-min avg; re-sampled before each program) |")
qualified = (qual_state == "1")
L.append(f"| qualification | {'QUALIFIED' if qualified else 'UNQUALIFIED (exploratory)'}: "
         f"load at start {load0 or 'unreadable'} vs threshold {maxload}"
         f"{'' if qualified else '; ' + (qual_note or 'see per-program load records')}"
         ". Load re-sampled before each program's timing. |")
if not qualified:
    L.append("")
    L.append("| UNQUALIFIED RUN | No qualified comparison claim may be drawn from this run. "
             "All verdicts are exploratory. |")
L.append("")
L.append("| # | directive |")
L.append("|---|---|")
L.append(f"| 1 | Generated {entry['ts']} by `bench/run.sh` (route {route}, {rounds} interleaved rounds, 3 warmup, median is primary). |")
L.append("")
L.append("| section |")
L.append("|---|---|")
L.append("| corrections |")
L.append("")
L.append("| # | directive |")
L.append("|---|---|")
for i, d in enumerate(directives, 1):
    L.append(f"| {i} | [{d['id']}] {d['text']} |")
L.append("")
L.append("| # | directive |")
L.append("|---|---|")
L.append("| 1 | Honesty policy: every program x every compiler is listed. |")
L.append("| 2 | Losses are reported, not hidden. |")
L.append("| 3 | A loss is a bug report against the compiler. |")
L.append("| 4 | No win/loss without a median-difference 95% bootstrap CI excluding zero; "
         "no 'equivalent' without a 90% CI wholly inside the predeclared +/-2% band; "
         "otherwise the verdict is inconclusive — never 'tie'. The retired rule "
         "'abs(median diff) <= 2% and Welch p >= 0.05 => parity' must not appear in any verdict. |")
L.append("| 5 | Raw per-round samples are retained in bench results.json per row; every verdict is re-derivable. |")
L.append("| 6 | Producer binding: the timer's compiler attribution is cross-checked "
         "against the exact hashed binary every program; a mismatch aborts. |")
L.append("| 7 | Sizes are like-for-like only: executables vs executables, objects vs "
         "objects. No single ratio across unequal artifact boundaries. |")
L.append("| 8 | An UNQUALIFIED run yields exploratory verdicts only; no qualified "
         "comparison claim may be drawn from it. |")
for prog, d in res["programs"].items():
    tj = d["timing"]
    L.append("")
    L.append("| section |")
    L.append("|---|---|")
    L.append(f"| {prog} |")
    L.append("")
    L.append("| compiler | median (s) | mean (s) | stddev | min | max | p95 | outliers |")
    L.append("|---|---|---|---|---|---|---|---|")
    for c, s in tj["binaries"].items():
        L.append(f"| {c} | {s['median']:.6f} | {s['mean']:.6f} | {s['stddev']:.6f} | "
                 f"{s['min']:.6f} | {s['max']:.6f} | {s['p95']:.6f} | {s['outliers']} |")
    L.append("")
    vb = tj.get("vs_best")
    if vb:
        ci95 = vb.get("ci95_median_diff_pct") or [float("nan"), float("nan")]
        ci90 = vb.get("ci90_median_diff_pct") or [float("nan"), float("nan")]
        L.append("| # | directive |")
        L.append("|---|---|")
        L.append(f"| 1 | Idol vs best rival ({vb['rival']}): {vb['verdict']}, "
                 f"median margin {vb['margin']*100:+.2f}% "
                 f"[95% CI {ci95[0]:+.2f}%, {ci95[1]:+.2f}%]; "
                 f"equivalent={str(bool(vb['equivalent'])).lower()} "
                 f"(90% CI [{ci90[0]:+.2f}%, {ci90[1]:+.2f}%] vs band [-2%,+2%]); "
                 f"mean/median conflict={str(bool(vb['mean_median_conflict'])).lower()}; "
                 f"Welch p (mean diagnostic)={vb['welch_p_mean']:.4f}. |")
        L.append(f"| 2 | Decision rule: {vb['decision_rule']} |")
        L.append("")
    prod = d.get("producer", {})
    L.append("| # | directive |")
    L.append("|---|---|")
    L.append(f"| 1 | Producer: {prod.get('compiler_path','?')} "
             f"sha256={str(prod.get('compiler_sha256','?'))[:16]}... "
             f"(route {prod.get('route','?')}, rev {prod.get('repo_rev','?')}). "
             f"Load before timing: {d.get('load_before','?')}. |")
    L.append("")
    ct = d["compile_time"]["compilers"]
    parts = []
    for c in ("idol", "clang", "gcc"):
        e = ct.get(c)
        if not e:
            continue
        if e["status"] == "success":
            parts.append(f"{c} {e['median_s']:.3f}s ({e['succeeded']}/{e['attempts']} ok)")
        else:
            stages = ",".join(f"{f['stage']}:{f['rc']}" for f in e["failures"][:3])
            parts.append(f"{c} FAILED ({e['succeeded']}/{e['attempts']} ok; e.g. {stages})")
    L.append("| # | directive |")
    L.append("|---|---|")
    L.append("| 1 | Compile time, source to executable (median of successful attempts; "
             "FAILED attempts are failed work, never in the median): " + "; ".join(parts) + ". "
             f"Idol compiler sha256={str(d['compile_time'].get('producer',{}).get('sha256','?'))[:16]}... |")
    L.append("")
    sz = d["sizes"]
    L.append("| # | directive |")
    L.append("|---|---|")
    L.append("| 1 | Executable size, bytes (linked executables, like-for-like): "
             + fmt_bytes(sz["executable_bytes"]) + ". |")
    L.append("| 2 | Object size, bytes (relocatable objects, like-for-like; "
             f"idol object kind: {sz['idol_object_kind']}): " + fmt_bytes(sz["object_bytes"]) + ". |")
    segparts = []
    for k in ("idol", "clang", "gcc"):
        s = (sz["segments_text_data"] or {}).get(k) or {}
        if s.get("text") is not None:
            segparts.append(f"{k} __TEXT {s['text']} __DATA {s['data']}")
    if segparts:
        L.append("| 3 | Code/data identification (`size -m` __TEXT/__DATA, best-effort): "
                 + "; ".join(segparts) + ". |")
L.append("")
L.append("| section |")
L.append("|---|---|")
L.append("| history |")
L.append("")
L.append("| # | directive |")
L.append("|---|---|")
L.append("| 1 | Per-case verdict history across runs. Any commit that regresses a case is visible here. |")
L.append("| 2 | margin% = (rival_median - idol_median) / rival_median; negative = idol slower. |")
L.append("| 3 | Source: bench/results/history.jsonl, one entry appended per run. |")
L.append("")
L.append("| case | runs | first seen | last verdict | last margin% | worst margin% | best margin% |")
L.append("|---|---|---|---|---|---|---|")
for prog in sorted(agg):
    a = agg[prog]
    L.append(f"| {prog} | {a['runs']} | {a['first']} | {a['last_verdict']} | "
             f"{a['last_margin']:+.2f}% | {min(a['margins']):+.2f}% | {max(a['margins']):+.2f}% |")
open(out_path, "w").write("\n".join(L) + "\n")
print(f"wrote {out_path} (+ history entry {entry['commit']} {entry['ts']})")
PYEOF

echo "bench: complete (qualified=$QUALIFIED). see $BENCH/RESULTS.md"
