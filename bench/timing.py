#!/usr/bin/env python3
"""Independent cross-check verifier for the Idol benchmark timer.

Reads the Idol timer's JSON output from stdin (which contains raw per-binary
nanosecond samples plus the timer's own computed stats). Independently
recomputes every statistic from the raw samples, verifies exact agreement
with the timer's reported values, and emits the vs_best verdict.

DECLARED ESTIMAND (median difference):
    D = median(idol) - median(rival), reported as a percentage of the rival
    median. The reported margin is -D (positive margin = idol faster).

DECISION PROCEDURE (also documented in the emitted JSON and the report):
    * Uncertainty: B=2000 bootstrap resamples with fixed seed 20260915;
      percentile confidence interval for D.
    * win / loss: the 95% CI for D excludes 0; direction from the sign of D.
    * equivalent: the 90% CI for D lies WHOLLY inside the predeclared
      equivalence band [-2%, +2%] of the rival median.
    * otherwise: "inconclusive". Nonsignificance is NEVER "tie", "parity",
      or equivalence-by-default. The old rule "abs(median diff) <= 2% and
      Welch p >= 0.05 => parity" is retired.

MEAN-BASED DIAGNOSTIC (not the verdict):
    Welch's t with Welch-Satterthwaite degrees of freedom on the means is
    reported as welch_p_mean. When the mean-based and median-based
    conclusions disagree, mean_median_conflict=true is flagged. The normal
    approximation previously used for the Welch p-value is retired.

This is NOT a timer: it performs no measurements. It is an explicit
independent cross-check over the SAME raw samples produced by the Idol
timer (bench/timing.id), which is the authoritative timing path.
"""
import json
import math
import random
import sys

ALPHA = 0.05
BOOT_B = 2000
BOOT_SEED = 20260915
EQUIV_BAND_PCT = 2.0

DECISION_RULE = (
    "declared estimand: median(idol)-median(rival) as % of rival median "
    "(positive margin = idol faster). win/loss iff 95% bootstrap percentile "
    "CI (B=2000, seed 20260915) excludes 0. 'equivalent' iff 90% CI lies "
    "wholly inside predeclared band [-2%,+2%]. else 'inconclusive' (never "
    "'tie'). Welch t with Satterthwaite df reported as mean-based diagnostic "
    "only; mean_median_conflict flags disagreement."
)


def _betacf(a, b, x):
    """Continued fraction for the incomplete beta function (NR betacf)."""
    MAXIT, EPS, FPMIN = 200, 3.0e-12, 1.0e-300
    qab, qap, qam = a + b, a + 1.0, a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    if abs(d) < FPMIN:
        d = FPMIN
    d = 1.0 / d
    h = d
    for m in range(1, MAXIT + 1):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        if abs(d) < FPMIN:
            d = FPMIN
        c = 1.0 + aa / c
        if abs(c) < FPMIN:
            c = FPMIN
        d = 1.0 / d
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        if abs(d) < FPMIN:
            d = FPMIN
        c = 1.0 + aa / c
        if abs(c) < FPMIN:
            c = FPMIN
        d = 1.0 / d
        dl = d * c
        h *= dl
        if abs(dl - 1.0) < EPS:
            break
    return h


def _betai(a, b, x):
    """Regularized incomplete beta function I_x(a, b)."""
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    bt = math.exp(math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
                  + a * math.log(x) + b * math.log(1.0 - x))
    if x < (a + 1.0) / (a + b + 2.0):
        return bt * _betacf(a, b, x) / a
    return 1.0 - bt * _betacf(b, a, 1.0 - x) / b


def t_cdf(t, df):
    """CDF of Student's t with df degrees of freedom, for t >= 0."""
    x = df / (df + t * t)
    return 1.0 - 0.5 * _betai(df / 2.0, 0.5, x)


def welch_t_satterthwaite(a, b):
    """Welch's t with Welch-Satterthwaite df. Returns (t, df, two-sided p).

    This is the MEAN-based diagnostic only; it does not drive the verdict.
    """
    n1, n2 = len(a), len(b)
    m1, m2 = sum(a) / n1, sum(b) / n2
    v1 = sum((x - m1) ** 2 for x in a) / (n1 - 1) if n1 > 1 else 0.0
    v2 = sum((x - m2) ** 2 for x in b) / (n2 - 1) if n2 > 1 else 0.0
    se2 = v1 / n1 + v2 / n2
    if se2 == 0.0:
        return 0.0, float("inf"), (1.0 if m1 == m2 else 0.0)
    t = (m1 - m2) / math.sqrt(se2)
    if n1 > 1 and n2 > 1:
        den = (v1 / n1) ** 2 / (n1 - 1) + (v2 / n2) ** 2 / (n2 - 1)
        df = se2 ** 2 / den if den > 0 else float("inf")
    else:
        df = float("inf")
    if math.isinf(df):
        p = math.erfc(abs(t) / math.sqrt(2.0))
    else:
        p = 2.0 * (1.0 - t_cdf(abs(t), df))
    return t, df, min(max(p, 0.0), 1.0)


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


def bootstrap_median_diff_ci(idol_ns, rival_ns, cl):
    """Percentile bootstrap CI for (median(idol)-median(rival)) as % of rival median.

    Returns (lo, hi). Fixed seed so verdicts are exactly reproducible.
    """
    rng = random.Random(BOOT_SEED)
    n1, n2 = len(idol_ns), len(rival_ns)
    diffs = []
    for _ in range(BOOT_B):
        s1 = sorted(idol_ns[rng.randrange(n1)] for _ in range(n1))
        s2 = sorted(rival_ns[rng.randrange(n2)] for _ in range(n2))
        m1, m2 = idol_median(s1), idol_median(s2)
        if m2:
            diffs.append((m1 - m2) / m2 * 100.0)
    if not diffs:
        return 0.0, 0.0
    diffs.sort()
    alpha = 1.0 - cl
    lo = diffs[int(len(diffs) * alpha / 2)]
    hi = diffs[int(len(diffs) * (1.0 - alpha / 2))]
    return lo, hi


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

    # --- Producer binding: the timer must attribute the exact compiler bytes.
    # An empty or malformed digest means the subject is unattributed: refuse.
    chash = timer_out.get("compiler_sha256") or ""
    if len(chash) != 64 or any(c not in "0123456789abcdef" for c in chash):
        print("verifier: FATAL: timer compiler_sha256 is missing or malformed "
              f"({chash!r}); refusing unattributed timings", file=sys.stderr)
        sys.exit(12)

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
           "alpha": ALPHA,
           "bootstrap": {"B": BOOT_B, "seed": BOOT_SEED, "method": "percentile"},
           "equivalence_band_pct": [-EQUIV_BAND_PCT, EQUIV_BAND_PCT],
           "decision_rule": DECISION_RULE,
           "timer_identity": {
               "timer": timer_out["timer"],
               "version": timer_out["version"],
               "timing_boundary": timer_out["timing_boundary"],
               "decision_rule": timer_out["decision_rule"],
               "compiler": timer_out.get("compiler"),
               "compiler_sha256": chash,
               "config": timer_out.get("config"),
               "revision": timer_out.get("revision"),
           }}
    times_s = {}
    samples_by_name = {}
    for name, rep in binaries.items():
        s_ns = sorted(rep["samples_ns"])
        n = len(s_ns)
        samples_by_name[name] = s_ns
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

    # --- vs_best: idol vs fastest rival, median-difference estimand ---
    # win/loss iff the 95% bootstrap CI for the median difference excludes 0;
    # 'equivalent' iff the 90% CI lies wholly inside the predeclared band;
    # otherwise 'inconclusive' (never 'tie'). Welch's t on the means is a
    # diagnostic only; disagreement with the median verdict is flagged.
    if "idol" in times_s:
        idol = times_s["idol"]
        rivals = {n: t for n, t in times_s.items() if n != "idol"}
        if rivals:
            best = min(rivals, key=lambda n: idol_median(sorted(
                [int(x * 1e9) for x in rivals[n]])))
            idol_ns = samples_by_name["idol"]
            rival_ns = samples_by_name[best]
            im = idol_median(sorted(idol_ns)) / 1e9
            bm = idol_median(sorted(rival_ns)) / 1e9
            margin = (bm - im) / bm if bm else 0.0
            lo95, hi95 = bootstrap_median_diff_ci(idol_ns, rival_ns, 0.95)
            lo90, hi90 = bootstrap_median_diff_ci(idol_ns, rival_ns, 0.90)
            median_significant = (hi95 < 0.0) or (lo95 > 0.0)
            equivalent = (lo90 >= -EQUIV_BAND_PCT) and (hi90 <= EQUIV_BAND_PCT)
            t_w, df_w, p_w = welch_t_satterthwaite(idol, rivals[best])
            welch_sig = p_w < ALPHA
            mean_diff = sum(idol) / len(idol) - sum(rivals[best]) / len(rivals[best])
            median_diff = im - bm
            conflict = (welch_sig != median_significant) or (
                welch_sig and median_significant
                and (mean_diff > 0) != (median_diff > 0))
            if median_significant:
                verdict = "win" if median_diff < 0 else "loss"
            elif equivalent:
                verdict = "equivalent"
            else:
                verdict = "inconclusive"
            out["vs_best"] = {
                "rival": best,
                "estimand": ("median(idol)-median(rival) as % of rival median; "
                             "positive margin = idol faster"),
                "idol_median": im,
                "rival_median": bm,
                "margin": margin,
                "margin_pct": margin * 100.0,
                "ci95_median_diff_pct": [lo95, hi95],
                "ci90_median_diff_pct": [lo90, hi90],
                "median_significant": median_significant,
                "equivalent": equivalent,
                "welch_t_mean": t_w,
                "welch_df": df_w,
                "welch_p_mean": p_w,
                "welch_significant_mean": welch_sig,
                "mean_median_conflict": conflict,
                "p_value": p_w,
                "significant": median_significant,
                "verdict": verdict,
                "decision_rule": DECISION_RULE,
            }
            if conflict:
                print("verifier: WARNING: mean/median diagnostic conflict "
                      f"(welch p={p_w:.4f} sig={welch_sig}, median 95% CI "
                      f"[{lo95:+.2f}%, {hi95:+.2f}%] sig={median_significant})",
                      file=sys.stderr)

    json.dump(out, sys.stdout, indent=2)


if __name__ == "__main__":
    main()
