#!/bin/bash
# bench/run.sh — skeptical benchmark harness for the Idol native compiler.
#
# Usage:
#   ./run.sh                 # full run: 21 interleaved rounds per benchmark
#   ./run.sh --quick         # smoke run: 5 rounds
#   ./run.sh --progs "sum fib" --compilers "clang"
#
# Pipeline per benchmark program P and compiler C:
#   1. Build P with the Idol native compiler (built from lib/compiler/native.id
#      at the start of this run — never a stale binary).
#   2. Build P with each C compiler (clang -O3, gcc -O3 where present).
#   3. CORRECTNESS GATE: every binary must exit with the same code.
#      Any mismatch aborts the whole run. A wrong answer is a bug, not data.
#   4. Timing: 3 warmup runs, then N INTERLEAVED timed rounds
#      (idol, clang, gcc, idol, clang, gcc, ...) so thermal drift and
#      background load affect all competitors equally.
#   5. timing.py computes median/mean/stddev/min/max/p95, counts outliers
#      (Tukey fence, disclosed not dropped), and runs Welch's t-test.
#   6. Static metrics: object size (.o bytes) and source-to-executable
#      compile time (median of 5).
#   7. RESULTS.md is rewritten with the full table — wins AND losses.
#
# Honesty rules, enforced in code:
#   - set -e: any build failure aborts; no benchmark is silently skipped.
#   - The correctness gate aborts on exit-code mismatch.
#   - RESULTS.md lists every program x every compiler. No filter exists.
#   - Primary metric is the median (robust; outlier removal unnecessary).
set -e -u
BENCH="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$BENCH/.." && pwd)"
WORK="$BENCH/.work"
mkdir -p "$WORK"

ROUNDS=21
PROGS="sum arith fib nest div mul13 bigconst zerotrip upbranch startup brm1 brm2 brm3 divv divm divd dgcd divpow2 ceildiv mulc mulh madd sred1 powmod popc bitr xsft absd cltz nest3d unroll mixop loopinv satadd regp ilp stride3"
WANT_COMPILERS="clang gcc"
while [ $# -gt 0 ]; do
  case "$1" in
    --quick) ROUNDS=5 ;;
    --progs) PROGS="$2"; shift ;;
    --compilers) WANT_COMPILERS="$2"; shift ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

# --- 0. Load-average gate: refuse to time on a loaded machine ---
# Compares the 1-minute load average against a fixed threshold of 8 and
# aborts when load is not below 8. Portable: sysctl on Darwin, /proc on
# Linux. Test override: BENCH_LOAD forces the compared value; BENCH_MAXLOAD
# overrides the threshold.
bench_load_gate() {
    load=""; maxload="${BENCH_MAXLOAD:-8}"
    if [ "$(uname -s)" = "Darwin" ]; then
        load="$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}')"
    elif [ -r /proc/loadavg ]; then
        load="$(cut -d' ' -f1 /proc/loadavg 2>/dev/null)"
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

# --- 1. Build the Idol native compiler from repo source ---
IDOL_BIN="$REPO/zig-out/bin/idol"
if [ ! -x "$IDOL_BIN" ]; then
  echo "bench: $IDOL_BIN missing; run 'zig build' in the repo first." >&2; exit 4
fi
NATIVE="$WORK/nativebench"
echo "bench: compiling lib/compiler/native.id -> nativebench"
"$IDOL_BIN" compile "$REPO/lib/compiler/native.id" --backend native -o "$NATIVE"
if [ ! -x "$NATIVE" ]; then echo "bench: nativebench build failed." >&2; exit 4; fi

# --- compiler discovery ---
COMPILERS="idol"
command -v clang >/dev/null 2>&1 && COMPILERS="$COMPILERS clang"
command -v gcc >/dev/null 2>&1 && [ "$(gcc --version 2>/dev/null | head -1)" != "" ] && COMPILERS="$COMPILERS gcc"
# honor --compilers filter
FILTERED="idol"
for c in $WANT_COMPILERS; do
  case " $COMPILERS " in *" $c "*) FILTERED="$FILTERED $c";; esac
done
COMPILERS="$FILTERED"
echo "bench: compilers:$COMPILERS"

idol_build() { # $1=prog -> $WORK/$1.idol (executable)
  "$NATIVE" < "$BENCH/programs/$1.id" | xxd -r -p > "$WORK/$1.o"
  ld -arch arm64 -e _idolmain -platform_version macos 14.0 14.0 \
     -syslibroot "$SDK" "$WORK/$1.o" -lSystem -o "$WORK/$1.idol"
}
clang_build() { clang -O3 "$BENCH/programs/$1.c" -o "$WORK/$1.clang"; }
gcc_build()   { gcc -O3 "$BENCH/programs/$1.c" -o "$WORK/$1.gcc"; }

RESULT_JSON="$WORK/results.json"
echo '{"programs":{}}' > "$RESULT_JSON"

for P in $PROGS; do
  echo "bench: [$P] building..."
  for C in $COMPILERS; do "${C}_build" "$P"; done

  # --- 3. correctness gate ---
  REF=""
  for C in $COMPILERS; do
    RC=0
    "$WORK/$P.$C" >/dev/null 2>&1 || RC=$?
    if [ -z "$REF" ]; then REF=$RC; fi
    if [ "$RC" != "$REF" ]; then
      echo "bench: CORRECTNESS FAIL [$P]: $C exits $RC, expected $REF. aborting." >&2
      exit 5
    fi
  done
  echo "bench: [$P] correctness ok (exit $REF)"

  # --- 4/5. timing ---
  SPEC="$WORK/$P.spec.json"
  { echo '{"binaries":{'; SEP="";
    for C in $COMPILERS; do echo "${SEP}\"$C\":\"$WORK/$P.$C\""; SEP=","; done
    echo "},\"rounds\":$ROUNDS,\"warmup\":3}"; } > "$SPEC"
  python3 "$BENCH/timing.py" < "$SPEC" > "$WORK/$P.time.json"

  # --- 6a. code size: object bytes ---
  SZ_IDOL=$(stat -f%z "$WORK/$P.o" 2>/dev/null || stat -c%s "$WORK/$P.o")
  SZ_CLANG=""; SZ_GCC=""
  clang -O3 -c "$BENCH/programs/$P.c" -o "$WORK/$P.clang.o" 2>/dev/null && SZ_CLANG=$(stat -f%z "$WORK/$P.clang.o" 2>/dev/null || stat -c%s "$WORK/$P.clang.o")
  command -v gcc >/dev/null 2>&1 && gcc -O3 -c "$BENCH/programs/$P.c" -o "$WORK/$P.gcc.o" 2>/dev/null && SZ_GCC=$(stat -f%z "$WORK/$P.gcc.o" 2>/dev/null || stat -c%s "$WORK/$P.gcc.o")

  # --- 6b. compile time: source -> executable, median of 5 ---
  CTIME="$WORK/$P.ctime.json"
  python3 - "$NATIVE" "$BENCH" "$P" "$SDK" "$WORK" << 'PYEOF' > "$CTIME"
import json, subprocess, sys, time
native, bench, prog, sdk, work = sys.argv[1:6]
def med(ts):
    s = sorted(ts); return s[len(s)//2]
def t_idol():
    t0 = time.perf_counter()
    p1 = subprocess.run([native], stdin=open(f"{bench}/programs/{prog}.id","rb"), capture_output=True)
    open(f"{work}/{prog}.cto.o","wb").write(bytes.fromhex(p1.stdout.decode()))
    subprocess.run(["ld","-arch","arm64","-e","_idolmain","-platform_version","macos","14.0","14.0",
                    "-syslibroot",sdk,f"{work}/{prog}.cto.o","-lSystem","-o",f"{work}/{prog}.cto"],
                   capture_output=True)
    return time.perf_counter() - t0
def t_clang():
    t0 = time.perf_counter()
    subprocess.run(["clang","-O3",f"{bench}/programs/{prog}.c","-o",f"{work}/{prog}.ctc"], capture_output=True)
    return time.perf_counter() - t0
def t_gcc():
    t0 = time.perf_counter()
    subprocess.run(["gcc","-O3",f"{bench}/programs/{prog}.c","-o",f"{work}/{prog}.ctcg"], capture_output=True)
    return time.perf_counter() - t0
out = {"idol": med([t_idol() for _ in range(5)]), "clang": med([t_clang() for _ in range(5)])}
try:
    out["gcc"] = med([t_gcc() for _ in range(5)])
except Exception:
    pass
json.dump(out, sys.stdout)
PYEOF

  # --- merge into results ---
  python3 - "$RESULT_JSON" "$WORK/$P.time.json" "$CTIME" "$P" "$SZ_IDOL" "$SZ_CLANG" "$SZ_GCC" << 'PYEOF'
import json, sys
res_path, time_path, ctime_path, prog, sz_idol, sz_clang, sz_gcc = sys.argv[1:8]
res = json.load(open(res_path))
tj = json.load(open(time_path))
ct = json.load(open(ctime_path))
res["programs"][prog] = {
    "timing": tj,
    "compile_time_s": ct,
    "obj_bytes": {"idol": int(sz_idol),
                  "clang": int(sz_clang) if sz_clang else None,
                  "gcc": int(sz_gcc) if sz_gcc else None},
}
json.dump(res, open(res_path, "w"), indent=2)
PYEOF
  echo "bench: [$P] done."
done

# --- 7. render RESULTS.md (structural format; no prose) ---
# --- 8. append this run's per-program verdicts to bench/results/history.jsonl ---
python3 - "$RESULT_JSON" "$BENCH/RESULTS.md" "$ROUNDS" "$BENCH/results/history.jsonl" "$REPO" << 'PYEOF'
import json, sys, datetime, subprocess
res_path, out_path, rounds, hist_path, repo = sys.argv[1:6]
res = json.load(open(res_path))

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
L.append("")
L.append("| # | directive |")
L.append("|---|---|")
L.append(f"| 1 | Generated {entry['ts']} by `bench/run.sh` ({rounds} interleaved rounds, 3 warmup, median is primary). |")
L.append("")
L.append("| # | directive |")
L.append("|---|---|")
L.append("| 1 | Honesty policy: every program x every compiler is listed. |")
L.append("| 2 | Losses are reported, not hidden. |")
L.append("| 3 | A loss is a bug report against the compiler. |")
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
        L.append("| # | directive |")
        L.append("|---|---|")
        L.append(f"| 1 | Idol vs best rival ({vb['rival']}): {vb['verdict']}, "
                 f"margin {vb['margin']*100:+.2f}%, p={vb['p_value']:.4f} "
                 f"({'significant' if vb['significant'] else 'not significant'}). |")
        L.append("")
    ct = d["compile_time_s"]
    L.append("| # | directive |")
    L.append("|---|---|")
    L.append("| 1 | Compile time, source to executable (median of 5): " +
             ", ".join(f"{k} {v:.3f}s" for k, v in ct.items()) + ". |")
    L.append("")
    L.append("| # | directive |")
    L.append("|---|---|")
    L.append("| 1 | Object size (bytes): " +
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

echo "bench: complete. see $BENCH/RESULTS.md"
