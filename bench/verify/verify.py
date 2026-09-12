#!/usr/bin/env python3
"""Differential verification of Idol native-compiler optimizations.

For each optimization (constant folding, algebraic simplification,
immediate add/sub, multiply strength reduction, countdown loops, copy
propagation, division, nested-loop bound registers), this script:

  1. builds the compiler fresh from lib/compiler/native.id,
  2. compiles randomized + adversarial Idol programs with it,
  3. compiles bit-identical C oracles with clang/gcc -O3,
  4. runs both and asserts identical observable behavior.

Observable behavior = process exit code (low 8 bits of the return
register); with --full, each case is additionally re-run 8 times
returning (value / 256^k) so all 8 bytes of the 64-bit result are
compared. Any divergence is a compiler bug: the case is saved under
failures/ and reported. Exit status: 0 all pass, 1 mismatches found,
2 infrastructure error.

Usage:
  ./verify.py                      # all opts, 30 random seeds each
  ./verify.py --quick              # smoke: 8 seeds each
  ./verify.py --opts fold,countdown --seeds 100 --full
  ./verify.py --list-opts

Never touches bench/.work/ (the timing workstream's directory); all
build artifacts live in bench/verify/.work/ (git-ignored).
"""
import argparse
import importlib
import json
import os
import random
import sys
import time

import common
from common import InfraError

OPTS = ["fold", "simp", "imm", "mulred", "countdown", "copy", "div", "nest"]


def check_case(shim, native, work, case, full, timeout):
    """Returns (verdict, detail). verdict in pass|mismatch|build_fail|hang."""
    tag = "v_" + case["id"].replace("/", "_")
    variants_idol = {0: case["idol"]}
    if full or case.get("full"):
        variants_idol = common.idol_byte_variants(case["idol"], case["ret"])
    variants_c = {0: common.c_plain(case["cbody"], case["cret"],
                                    case["signed"])}
    if full or case.get("full"):
        variants_c = common.c_byte_variants(case["cbody"], case["cret"],
                                            case["signed"])
    results = {}
    for k in sorted(variants_idol):
        iexe, ilog = common.build_idol(shim, native, work,
                                       f"{tag}_b{k}", variants_idol[k])
        if iexe is None:
            return ("build_fail", f"idol build failed (byte {k}): {ilog}")
        cexe, clog = common.build_c(shim, native, work,
                                    f"{tag}_b{k}", variants_c[k])
        if cexe is None:
            return ("build_fail", f"C build failed (byte {k}): {clog}")
        ist, irc = common.run_exe(iexe, timeout)
        cst, crc = common.run_exe(cexe, timeout)
        if ist == "timeout" or cst == "timeout":
            return ("hang", f"timeout after {timeout}s (byte {k}): "
                            f"idol={ist}/{irc} clang={cst}/{crc}")
        if ist != "ok" or cst != "ok":
            return ("hang", f"abnormal termination (byte {k}): "
                            f"idol={ist}/{irc} clang={cst}/{crc}")
        results[k] = (irc, crc)
        if irc != crc:
            return ("mismatch", f"byte {k}: idol exit {irc} != "
                                f"clang exit {crc}")
    return ("pass", f"{len(results)} byte-slices agree"
            if len(results) > 1 else "exit codes agree")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--opts", default="all",
                    help="comma list or 'all' (default)")
    ap.add_argument("--seeds", type=int, default=30)
    ap.add_argument("--quick", action="store_true",
                    help="smoke run: 8 seeds per opt")
    ap.add_argument("--full", action="store_true",
                    help="byte-slice observability for every case")
    ap.add_argument("--timeout", type=int, default=30,
                    help="per-run timeout seconds")
    ap.add_argument("--work", default=None)
    ap.add_argument("--list-opts", action="store_true")
    args = ap.parse_args()

    if args.list_opts:
        for o in OPTS:
            m = importlib.import_module("opts." + o)
            print(f"{m.OPT:10s} {m.DESC}")
        return 0

    want = OPTS if args.opts == "all" else args.opts.split(",")
    for o in want:
        if o not in OPTS:
            print(f"unknown opt: {o}", file=sys.stderr)
            return 2
    seeds = 8 if args.quick else args.seeds
    work = args.work or os.path.join(common.THIS, ".work")
    faildir = os.path.join(work, "failures")

    try:
        shim = common.load_shim()
        native = common.ensure_native(work)
    except InfraError as e:
        print(f"verify: infrastructure error: {e}", file=sys.stderr)
        return 2

    print(f"verify: platform {common.host_triple()}, "
          f"native={native}, seeds={seeds}, full={args.full}")
    total = {"pass": 0, "mismatch": 0, "build_fail": 0, "hang": 0}
    per_opt = {}
    mismatches = []
    t0 = time.time()

    for oi, oname in enumerate(want):
        mod = importlib.import_module("opts." + oname)
        rng = random.Random(0xC10C + oi)
        cases = list(mod.directed()) + list(mod.gen(rng, seeds))
        oc = {"pass": 0, "mismatch": 0, "build_fail": 0, "hang": 0}
        for case in cases:
            verdict, detail = check_case(shim, native, work, case,
                                         args.full, args.timeout)
            oc[verdict] += 1
            total[verdict] += 1
            if verdict != "pass":
                expected = case.get("expect", "pass")
                mismatches.append((oname, case, verdict, detail, expected))
                cdir = os.path.join(faildir, oname,
                                    case["id"].replace("/", "_"))
                os.makedirs(cdir, exist_ok=True)
                with open(os.path.join(cdir, "case.id"), "w") as f:
                    f.write(case["idol"])
                with open(os.path.join(cdir, "oracle.c"), "w") as f:
                    f.write(common.c_plain(case["cbody"], case["cret"],
                                           case["signed"]))
                with open(os.path.join(cdir, "result.json"), "w") as f:
                    json.dump({"id": case["id"], "verdict": verdict,
                               "detail": detail, "note": case.get("note", ""),
                               "expected": expected}, f, indent=2)
                flag = " (EXPECTED-ADVERSARIAL)" if expected != "pass" else ""
                print(f"  [{verdict.upper()}]{flag} {case['id']}: {detail}")
                if case.get("note"):
                    print(f"      note: {case['note']}")
        per_opt[oname] = oc
        print(f"verify: [{oname}] {len(cases)} cases: "
              + ", ".join(f"{k}={v}" for k, v in oc.items() if v))

    dt = time.time() - t0
    print(f"\nverify: TOTAL {sum(total.values())} cases in {dt:.1f}s: "
          + ", ".join(f"{k}={v}" for k, v in total.items()))
    if mismatches:
        print("\nMismatches are compiler bugs. Reproducibles saved under "
              f"{faildir}/<opt>/<case>/ (case.id, oracle.c, result.json).")
    write_results_md(want, per_opt, mismatches, seeds, args)
    if mismatches:
        return 1
    print("verify: all cases pass.")
    return 0


def write_results_md(want, per_opt, mismatches, seeds, args):
    """Write bench/verify/RESULTS.md in structural format (tables only).

    The performance-history section is re-rendered from
    bench/results/history.jsonl on every write, so regenerating this
    file never erases it. Called on every run, mismatches or not.
    """
    summ = os.path.join(common.THIS, "RESULTS.md")
    with open(summ, "w") as f:
        f.write("| field | value |\n|---|---|\n"
                "| title | Optimization verification results |\n\n")
        f.write("| # | directive |\n|---|---|\n"
                f"| 1 | Generated {time.strftime('%Y-%m-%dT%H:%M:%S')} by "
                f"`bench/verify/verify.py` (platform {common.host_triple()}, "
                f"seeds={seeds}, full={args.full}). |\n\n")
        f.write("| # | directive |\n|---|---|\n"
                "| 1 | Policy: every mismatch is a compiler bug report. |\n"
                "| 2 | Cases tagged EXPECTED-ADVERSARIAL were designed to defeat "
                "a specific optimization; their mismatch confirms the suspected "
                "unsoundness. |\n\n")
        f.write("| opt | cases | pass | mismatch | build_fail | hang |\n"
                "|---|---|---|---|---|---|\n")
        for oname in want:
            oc = per_opt[oname]
            nc = sum(oc.values())
            f.write(f"| {oname} | {nc} | {oc['pass']} | "
                    f"{oc['mismatch']} | {oc['build_fail']} | "
                    f"{oc['hang']} |\n")
        f.write("\n| section |\n|---|---|\n| Mismatches |\n\n")
        if mismatches:
            for oname, case, verdict, detail, expected in mismatches:
                text = f"[{verdict}] {case['id']}: {detail}"
                if expected != "pass":
                    text += " (expected adversarial)"
                if case.get("note"):
                    text += f" — {case['note']}"
                f.write("| # | directive |\n|---|---|\n"
                        f"| 1 | {text} |\n\n")
        else:
            f.write("| # | directive |\n|---|---|\n"
                    "| 1 | No mismatches: all cases pass. |\n\n")
        f.write("| section |\n|---|---|\n| performance history |\n\n")
        f.write("| # | directive |\n|---|---|\n"
                "| 1 | Per-case benchmark verdict history across runs. Any commit "
                "that regresses a case is visible here. |\n"
                "| 2 | margin% = (rival_median - idol_median) / rival_median; "
                "negative = idol slower. |\n"
                "| 3 | Source: bench/results/history.jsonl, one entry appended "
                "per bench/run.sh run. |\n\n")
        render_history_table(f)
    print(f"wrote {summ}")


def render_history_table(f):
    """Append the per-case verdict-history table from history.jsonl."""
    hist_path = os.path.join(common.THIS, "..", "results", "history.jsonl")
    agg = {}
    try:
        with open(hist_path) as hf:
            for line in hf:
                line = line.strip()
                if not line:
                    continue
                e = json.loads(line)
                # schema: {"ts", "commit", "rounds",
                #          "verdicts": {case: {"verdict", "margin_pct", ...}}}
                for case, r in e["verdicts"].items():
                    m = r["margin_pct"]
                    a = agg.setdefault(case, {"runs": 0, "first": None,
                                              "last_verdict": None,
                                              "last_margin": None,
                                              "worst": None, "best": None})
                    a["runs"] += 1
                    if a["first"] is None:
                        a["first"] = e["ts"]
                    a["last_verdict"] = r["verdict"]
                    a["last_margin"] = m
                    a["worst"] = m if a["worst"] is None else min(a["worst"], m)
                    a["best"] = m if a["best"] is None else max(a["best"], m)
    except FileNotFoundError:
        pass
    f.write("| case | runs | first seen | last verdict | last margin% | worst margin% | best margin% |\n"
            "|---|---|---|---|---|---|---|\n")
    for case in sorted(agg):
        a = agg[case]
        f.write(f"| {case} | {a['runs']} | {a['first']} | {a['last_verdict']} | "
                f"{a['last_margin']:+.2f}% | {a['worst']:+.2f}% | "
                f"{a['best']:+.2f}% |\n")


if __name__ == "__main__":
    sys.exit(main())
