#!/bin/bash
# bench/run.sh — skeptical benchmark harness for the Idol native compiler.
#
# Usage:
#   ./run.sh                 # full run: 21 interleaved rounds per benchmark
#   ./run.sh --quick         # smoke run: 5 rounds
#   ./run.sh --progs "sum fib" --compilers "clang"
#   ./run.sh --route production   # production compiler route (default: restricted)
#
# Pipeline per benchmark program P and compiler C:
#   1. Build P with the Idol compiler for this run's route. Restricted route:
#      nativebench is built from lib/compiler/native.id at the start of this
#      run with --no-cache (never a stale binary); P.id is piped through it,
#      hex-decoded, and linked with `ld -e _idolmain`. Production route: P.id
#      is compiled directly by the production compiler
#      (zig-out/bin/idol compile P.id --backend native --no-cache), which
#      emits a linked Mach-O executable.
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
#      Welford variance, and percentiles.
#   5. timing.py is now an independent cross-check verifier (not a timer):
#      it recomputes every statistic from the timer's raw samples, verifies
#      exact agreement, and emits the vs_best verdict via Welch's t-test.
#      A win/loss verdict is emitted ONLY when the test is significant
#      (p < 0.05); otherwise the verdict is "inconclusive" (never "tie").
#   6. Static metrics: object size (.o bytes) and source-to-executable
#      compile time (median of 5 interleaved attempts per compiler, produced
#      by bench/ctime.py under a hard validation contract).
#   7. RESULTS.md is rewritten with the full table — wins AND losses — plus
#      the standing corrections section emitted from bench/corrections.json
#      on EVERY run (no regeneration can delete it) and the run-time
#      discovered comparator identities.
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
set -e -u -o pipefail
BENCH="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$BENCH/.." && pwd)"
WORK="$BENCH/.work"
mkdir -p "$WORK"

ROUNDS=21
PROGS="sum arith fib nest div mul13 bigconst zerotrip upbranch startup brm1 brm2 brm3 divv divm divd dgcd divpow2 ceildiv mulc mulh madd sred1 powmod popc bitr xsft absd cltz nest3d unroll mixop loopinv satadd regp ilp stride3"
WANT_COMPILERS="clang gcc"
ROUTE="restricted"
while [ $# -gt 0 ]; do
  case "$1" in
    --quick) ROUNDS=5 ;;
    --progs) PROGS="$2"; shift ;;
    --compilers) WANT_COMPILERS="$2"; shift ;;
    --route) ROUTE="$2"; shift ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done
case "$ROUTE" in
  restricted|production) ;;
  *) echo "unknown route: $ROUTE (expected restricted|production)" >&2; exit 2 ;;
esac
echo "bench: route=$ROUTE"

# --- 0. Load-average gate: refuse to time on a loaded machine ---
# Compares the 1-minute load average against a fixed threshold of 8 and
# aborts when load is not below 8. Portable: sysctl on Darwin, /proc on
# Linux. Test override: BENCH_LOAD forces the compared value; BENCH_MAXLOAD
# overrides the threshold.
bench_load_gate() {
    load=""; maxload="${BENCH_MAXLOAD:-8}"
    if [ "$(uname -s)" = "Darwin" ]; then
        # '|| true': with pipefail a failing sysctl must degrade to the
        # graceful empty-load path below, not abort the harness.
        load="$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}' || true)"
    elif [ -r /proc/loadavg ]; then
        load="$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || true)"
    fi
    [ -n "${BENCH_LOAD:-}" ] && load="$BENCH_LOAD"
    case "$load" in ''|*[!0-9.]* ) echo "bench: cannot read load average; skipping load gate." >&2; return 0;; esac
    case "$maxload" in ''|*[!0-9.]* ) echo "bench: bad BENCH_MAXLOAD; skipping load gate." >&2; return 0;; esac
    if awk -v l="$load" -v m="$maxload" 'BEGIN{exit !(l >= m)}'; then
        echo "bench: 1-min load average $load is not below $maxload; aborting." >&2
        echo "bench: wait for the machine to idle, or override with BENCH_LOAD/BENCH_MAXLOAD for testing." >&2
        exit 5
    fi
    echo "bench: load gate ok (1-min avg $load < $maxload)"
}
bench_load_gate

ARCH="$(uname -m)"; OS="$(uname -s)"
echo "bench: host ${ARCH}-${OS}, rounds=${ROUNDS}"
if [ "${ARCH}-${OS}" != "arm64-Darwin" ]; then
  echo "bench: no backend for ${ARCH}-${OS} yet (see platforms/). aborting." >&2
  exit 3
fi
SDK="$(xcrun --show-sdk-path)"

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

# With set -o pipefail, a failed producer behind the pipe fails the build:
# a successful decoder can no longer conceal a failed producer.
idol_build() { # $1=prog -> $WORK/$1.idol (executable)
  if [ "$ROUTE" = "restricted" ]; then
    "$NATIVE" < "$BENCH/programs/$1.id" | xxd -r -p > "$WORK/$1.o"
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

  # --- 4/5. timing via the Idol timer (authoritative); Python verifies ---
  # The Idol timer does the timing: interleaved rounds, per-invocation exit/stdout
  # validation, Welford variance, and percentile reduction. timing.py no longer
  # times anything; it independently recomputes every stat from the timer's raw
  # samples (cross-check) and emits the report JSON with the vs_best verdict.
  # Nonsignificance is "inconclusive", never "tie".
  REF_HEX=$(xxd -p "$REF_OUT" | tr -d '\n')
  TIMER_NBIN=0
  TIMER_BINS=""
  for C in $COMPILERS; do
    TIMER_BINS="$TIMER_BINS $C $WORK/$P.$C"
    TIMER_NBIN=$((TIMER_NBIN+1))
  done
  TIMER_REV=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo "unknown")
  "$TIMER" $ROUNDS 3 $REF_RC "$REF_HEX" "idol" "$ROUTE" "$TIMER_REV" \
    $TIMER_NBIN $TIMER_BINS > "$WORK/$P.timer.json"
  python3 "$BENCH/timing.py" < "$WORK/$P.timer.json" > "$WORK/$P.time.json"

  # --- 6a. code size: object bytes ---
  if [ "$ROUTE" = "restricted" ]; then
    SZ_IDOL=$(stat -f%z "$WORK/$P.o" 2>/dev/null || stat -c%s "$WORK/$P.o")
  else
    # Production route emits a linked executable, not an object file.
    SZ_IDOL=$(stat -f%z "$WORK/$P.idol" 2>/dev/null || stat -c%s "$WORK/$P.idol")
  fi
  SZ_CLANG=""; SZ_GCC=""
  clang -O3 -c "$BENCH/programs/$P.c" -o "$WORK/$P.clang.o" 2>/dev/null && SZ_CLANG=$(stat -f%z "$WORK/$P.clang.o" 2>/dev/null || stat -c%s "$WORK/$P.clang.o")
  command -v gcc >/dev/null 2>&1 && gcc -O3 -c "$BENCH/programs/$P.c" -o "$WORK/$P.gcc.o" 2>/dev/null && SZ_GCC=$(stat -f%z "$WORK/$P.gcc.o" 2>/dev/null || stat -c%s "$WORK/$P.gcc.o")

  # --- 6b. compile time: source -> executable, 5 interleaved attempts ---
  # bench/ctime.py: a duration counts as a success ONLY after every required
  # stage succeeded and the artifact was validated (exists, nonzero size).
  # Failed attempts are recorded as FAILED work, never in success medians.
  CTIME="$WORK/$P.ctime.json"
  python3 "$BENCH/ctime.py" "$NATIVE" "$BENCH" "$P" "$SDK" "$WORK" "$CTIME" "$COMPILERS" "$ROUTE" "$IDOL_BIN"

  # --- merge into results ---
  python3 - "$RESULT_JSON" "$WORK/$P.time.json" "$CTIME" "$P" "$SZ_IDOL" "$SZ_CLANG" "$SZ_GCC" \
          "$CLANG_VERSION" "$GCC_VERSION" "$ORACLE" << 'PYEOF'
import json, sys
(res_path, time_path, ctime_path, prog, sz_idol, sz_clang, sz_gcc,
 clang_v, gcc_v, oracle) = sys.argv[1:11]
res = json.load(open(res_path))
tj = json.load(open(time_path))
ct = json.load(open(ctime_path))
res["programs"][prog] = {
    "timing": tj,
    "compile_time": ct,
    "obj_bytes": {"idol": int(sz_idol),
                  "clang": int(sz_clang) if sz_clang else None,
                  "gcc": int(sz_gcc) if sz_gcc else None},
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
        "$BENCH/corrections.json" "$CLANG_VERSION" "$GCC_VERSION" "$ORACLE" "$ROUTE" << 'PYEOF'
import json, sys, datetime, subprocess
(res_path, out_path, rounds, hist_path, repo, corr_path, clang_v, gcc_v,
 oracle, route) = sys.argv[1:11]
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
        "p": vb.get("p_value"),
        "sig": bool(vb.get("significant", False)),
        "rival": vb.get("rival", "?"),
        "idol_med": vb.get("idol_median"),
        "rival_med": vb.get("rival_median"),
    }
entry = {
    "ts": datetime.datetime.now().isoformat(timespec="seconds"),
    "commit": commit_of(repo),
    "rounds": int(rounds),
    "route": route,
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

L = []
L.append("| field | value |")
L.append("|---|---|")
L.append("| title | Benchmark results |")
L.append(f"| oracle_versions | clang: {clang_v or 'absent'} ; gcc: {gcc_v or 'absent'} |")
L.append(f"| correctness_oracle | {oracle} (exit code + byte-identical stdout) |")
L.append(f"| route | {route} |")
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
L.append("| 4 | No win/loss without significance: a verdict of win/loss requires Welch p < 0.05; otherwise the verdict is tie. |")
L.append("| 5 | Raw per-round samples are retained in bench results.json per row; every verdict is re-derivable. |")
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
        sig_word = "significant" if vb["significant"] else "not significant"
        L.append("| # | directive |")
        L.append("|---|---|")
        L.append(f"| 1 | Idol vs best rival ({vb['rival']}): {vb['verdict']}, "
                 f"margin {vb['margin']*100:+.2f}%, p={vb['p_value']:.4f} "
                 f"({sig_word}; win/loss requires p<0.05). |")
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
             "FAILED attempts are failed work, never in the median): " + "; ".join(parts) + ". |")
    L.append("")
    L.append("| # | directive |")
    L.append("|---|---|")
    if route == "restricted":
        sizelabel = "Object size (bytes)"
    else:
        sizelabel = ("Artifact size (bytes; idol = linked executable, "
                     "production route emits no separate object)")
    L.append("| 1 | " + sizelabel + ": " +
             ", ".join(f"{k} {v}" for k, v in d["obj_bytes"].items() if v) + ". |")
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

echo "bench: complete. see $BENCH/RESULTS.md"
