#!/usr/bin/env python3
"""Independent cross-check verifier for the Idol benchmark timer.

Reads the Idol timer's JSON output from stdin (which contains raw per-binary
nanosecond samples plus the timer's own computed stats). Independently
recomputes every statistic from the raw samples, verifies exact agreement
with the timer's reported values, and emits the vs_best verdict.

This is NOT a timer: it performs no measurements. It is an explicit
independent cross-check over the SAME raw samples produced by the Idol
timer (bench/timing.id), which is the authoritative timing path.

Verdict language: nonsignificance is "inconclusive", never "tie".
A tolerance margin cannot prove equivalence.
"""
import json
import math
import sys

SIGNIFICANCE_LEVEL = 0.05


def phi(x):
    return 0.5 * (1.0 + math.erf(x / math.sqrt(2.0)))


def welch_pvalue(a, b):
    """Two-sided p-value, Welch's t-test with normal approximation."""
    n1, n2 = len(a), len(b)
    m1, m2 = sum(a) / n1, sum(b) / n2
    v1 = sum((x - m1) ** 2 for x in a) / (n1 - 1) if n1 > 1 else 0.0
    v2 = sum((x - m2) ** 2 for x in b) / (n2 - 1) if n2 > 1 else 0.0
    denom = math.sqrt(v1 / n1 + v2 / n2)
    if denom == 0:
        return 1.0 if m1 == m2 else 0.0
    t = (m1 - m2) / denom
    return 2.0 * (1.0 - phi(abs(t)))


def idol_median(s):
    """Mirror bench/timing.id medianstr: average of two middles when even."""
    n = len(s)
    if (n // 2) * 2 == n:
        return (s[n // 2 - 1] + s[n // 2]) // 2
    else:
        return s[n // 2]


def idol_pctl(s, which, n):
    """Mirror bench/timing.id pctlstr which-codes."""
    if which == 1:
        k = 1
    elif which == 2:
        k = n
    elif which == 3:
        k = (95 * n + 99) // 100
    elif which == 4:
        k = n // 4 + 1
    elif which == 5:
        k = 3 * n // 4 + 1
    else:
        raise ValueError(f"bad which: {which}")
    return s[k - 1]


def verify_stats(name, reported, samples_ns):
    """Recompute stats from raw samples; return (ok, recomputed_dict)."""
    s = sorted(samples_ns)
    n = len(s)
    errors = []
    # median
    med = idol_median(s)
    if med != reported["median_ns"]:
        errors.append(f"median_ns: timer={reported['median_ns']} recomputed={med}")
    # min/max
    if s[0] != reported["min_ns"]:
        errors.append(f"min_ns: timer={reported['min_ns']} recomputed={s[0]}")
    if s[-1] != reported["max_ns"]:
        errors.append(f"max_ns: timer={reported['max_ns']} recomputed={s[-1]}")
    # p95, q1, q3
    p95 = idol_pctl(s, 3, n)
    if p95 != reported["p95_ns"]:
        errors.append(f"p95_ns: timer={reported['p95_ns']} recomputed={p95}")
    q1 = idol_pctl(s, 4, n)
    if q1 != reported["q1_ns"]:
        errors.append(f"q1_ns: timer={reported['q1_ns']} recomputed={q1}")
    q3 = idol_pctl(s, 5, n)
    if q3 != reported["q3_ns"]:
        errors.append(f"q3_ns: timer={reported['q3_ns']} recomputed={q3}")
    # outliers (Tukey: > Q3 + 3*IQR, disclosed not dropped)
    iqr = q3 - q1
    fence = q3 + 3 * iqr
    outliers = sum(1 for x in s if x > fence)
    if outliers != reported["outliers"]:
        errors.append(f"outliers: timer={reported['outliers']} recomputed={outliers}")
    # rounds
    if n != reported["rounds"]:
        errors.append(f"rounds: timer={reported['rounds']} recomputed={n}")
    return errors


def main():
    timer_out = json.load(sys.stdin)
    if timer_out.get("timer") != "idol-bench-timer":
        print("verifier: FATAL: stdin is not idol-bench-timer JSON", file=sys.stderr)
        sys.exit(10)

    binaries = timer_out["binaries"]
    rounds = timer_out["rounds"]
    warmup = timer_out["warmup"]

    # --- Independent cross-check: recompute every stat from raw samples ---
    all_errors = []
    for name, rep in binaries.items():
        samples_ns = rep["samples_ns"]
        errs = verify_stats(name, rep, samples_ns)
        for e in errs:
            all_errors.append(f"[{name}] {e}")
    if all_errors:
        print("verifier: FATAL: timer stats do not match recomputation:", file=sys.stderr)
        for e in all_errors:
            print(f"verifier:   {e}", file=sys.stderr)
        sys.exit(11)
    print(f"verifier: cross-check ok: {len(binaries)} binaries, "
          f"{rounds} rounds each, all stats agree", file=sys.stderr)

    # --- Emit run.sh-compatible JSON (float seconds) ---
    out = {"binaries": {}, "rounds": rounds, "warmup": warmup,
           "significance_level": SIGNIFICANCE_LEVEL,
           "timer_identity": {
               "timer": timer_out["timer"],
               "version": timer_out["version"],
               "timing_boundary": timer_out["timing_boundary"],
               "decision_rule": timer_out["decision_rule"],
           }}
    times_s = {}
    for name, rep in binaries.items():
        s_ns = sorted(rep["samples_ns"])
        n = len(s_ns)
        # float-second stats for the report (raw ns retained separately)
        s_s = [x / 1e9 for x in s_ns]
        mean_s = sum(s_s) / n
        # sample variance (Welford-equivalent, for the report only)
        var_s = sum((x - mean_s) ** 2 for x in s_s) / (n - 1) if n > 1 else 0.0
        out["binaries"][name] = {
            "rounds": n,
            "mean": mean_s,
            "median": idol_median(s_ns) / 1e9,
            "stddev": math.sqrt(var_s),
            "min": s_ns[0] / 1e9,
            "max": s_ns[-1] / 1e9,
            "p95": idol_pctl(s_ns, 3, n) / 1e9,
            "q1": idol_pctl(s_ns, 4, n) / 1e9,
            "q3": idol_pctl(s_ns, 5, n) / 1e9,
            "outliers": rep["outliers"],
            "exit_codes": [timer_out["expected_exit"]],
            "samples": s_s,
            "samples_ns": rep["samples_ns"],
        }
        times_s[name] = s_s

    # --- vs_best: idol vs fastest rival, significance-gated ---
    # Nonsignificance is "inconclusive", never "tie" or equivalence.
    if "idol" in times_s:
        idol = times_s["idol"]
        rivals = {n: t for n, t in times_s.items() if n != "idol"}
        if rivals:
            best = min(rivals, key=lambda n: idol_median(sorted(
                [int(x * 1e9) for x in rivals[n]])))
            p = welch_pvalue(idol, rivals[best])
            im = idol_median(sorted([int(x * 1e9) for x in idol])) / 1e9
            bm = idol_median(sorted([int(x * 1e9) for x in rivals[best]])) / 1e9
            margin = (bm - im) / bm if bm else 0.0
            significant = p < SIGNIFICANCE_LEVEL
            if significant:
                if im < bm:
                    verdict = "win"
                elif im > bm:
                    verdict = "loss"
                else:
                    verdict = "inconclusive"
            else:
                verdict = "inconclusive"
            out["vs_best"] = {
                "rival": best,
                "idol_median": im,
                "rival_median": bm,
                "margin": margin,
                "p_value": p,
                "significant": significant,
                "verdict": verdict,
            }

    json.dump(out, sys.stdout, indent=2)


if __name__ == "__main__":
    main()
