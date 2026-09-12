#!/usr/bin/env python3
"""Interleaved benchmark timing with statistical analysis.

Reads a JSON spec from stdin:
  {"binaries": {"idol": "/path/a", "clang": "/path/b"}, "rounds": 21, "warmup": 3}

Protocol:
  - warmup runs per binary (untimed, discarded)
  - timed rounds are INTERLEAVED (a,b,c,a,b,c...) so thermal drift,
    frequency scaling, and background load hit every binary equally
  - primary metric is the MEDIAN (robust; no outlier removal needed)
  - outliers are counted (Tukey: > Q3 + 3*IQR) and disclosed, never dropped

Writes JSON to stdout with per-binary stats and a Welch t-test of
idol vs the best competitor, plus win/loss/tie verdicts.
"""
import json
import math
import subprocess
import sys
import time


def run_once(binary):
    p = subprocess.run([binary], capture_output=True)
    return p.returncode


def time_once(binary):
    t0 = time.perf_counter()
    rc = run_once(binary)
    t1 = time.perf_counter()
    return (t1 - t0), rc


def phi(x):
    return 0.5 * (1.0 + math.erf(x / math.sqrt(2.0)))


def welch_pvalue(a, b):
    """Two-sided p-value, Welch's t-test with normal approximation (n>=20)."""
    n1, n2 = len(a), len(b)
    m1, m2 = sum(a) / n1, sum(b) / n2
    v1 = sum((x - m1) ** 2 for x in a) / (n1 - 1) if n1 > 1 else 0.0
    v2 = sum((x - m2) ** 2 for x in b) / (n2 - 1) if n2 > 1 else 0.0
    denom = math.sqrt(v1 / n1 + v2 / n2)
    if denom == 0:
        return 1.0 if m1 == m2 else 0.0
    t = (m1 - m2) / denom
    return 2.0 * (1.0 - phi(abs(t)))


def stats(ts):
    s = sorted(ts)
    n = len(s)
    mean = sum(s) / n
    median = s[n // 2]
    var = sum((x - mean) ** 2 for x in s) / n
    std = math.sqrt(var)
    q1 = s[n // 4]
    q3 = s[3 * n // 4]
    iqr = q3 - q1
    fence = q3 + 3.0 * iqr
    outliers = sum(1 for x in s if x > fence)
    return {
        "rounds": n,
        "mean": mean,
        "median": median,
        "stddev": std,
        "min": s[0],
        "max": s[-1],
        "p95": s[min(n - 1, int(0.95 * n))],
        "q1": q1,
        "q3": q3,
        "outliers": outliers,
    }


def main():
    spec = json.load(sys.stdin)
    binaries = spec["binaries"]
    rounds = int(spec.get("rounds", 21))
    warmup = int(spec.get("warmup", 3))
    names = list(binaries.keys())

    for _ in range(warmup):
        for n in names:
            run_once(binaries[n])

    times = {n: [] for n in names}
    codes = {n: set() for n in names}
    for _ in range(rounds):
        for n in names:
            dt, rc = time_once(binaries[n])
            times[n].append(dt)
            codes[n].add(rc)

    out = {"binaries": {}, "rounds": rounds, "warmup": warmup}
    for n in names:
        st = stats(times[n])
        st["exit_codes"] = sorted(codes[n])
        out["binaries"][n] = st

    if "idol" in times:
        idol = times["idol"]
        rivals = {n: times[n] for n in names if n != "idol"}
        if rivals:
            best = min(rivals, key=lambda n: stats(times[n])["median"])
            p = welch_pvalue(idol, rivals[best])
            im = stats(idol)["median"]
            bm = stats(rivals[best])["median"]
            margin = (bm - im) / bm if bm else 0.0
            verdict = "win" if im < bm else ("loss" if im > bm else "tie")
            out["vs_best"] = {
                "rival": best,
                "idol_median": im,
                "rival_median": bm,
                "margin": margin,
                "p_value": p,
                "significant": p < 0.05,
                "verdict": verdict,
            }

    json.dump(out, sys.stdout, indent=2)


if __name__ == "__main__":
    main()
