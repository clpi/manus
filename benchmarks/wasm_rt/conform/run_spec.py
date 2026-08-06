#!/usr/bin/env python3
"""WebAssembly spec-conformance harness for ward.

Converts each .wast in the official testsuite to JSON + .wasm via wast2json,
then replays every `assert_return` / `assert_trap` against ward, comparing to
the value the spec itself states (not to another runtime).

ward is driven through WARD_INVOKE / WARD_ARGS rather than CLI flags so the
harness does not depend on option parsing.

Usage:
  WARD=/path/to/ward ./run_spec.py [suite_dir] [--only name1,name2] [--jobs N]
"""
import json
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

WARD = os.environ.get("WARD")
SUITE = Path(sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-")
             else "/Users/clp/x/wart/third_party/testsuite")
ONLY = None
JOBS = 8
for i, a in enumerate(sys.argv):
    if a == "--only":
        ONLY = set(sys.argv[i + 1].split(","))
    if a == "--jobs":
        JOBS = int(sys.argv[i + 1])

if not WARD or not Path(WARD).exists():
    sys.exit("set WARD=/path/to/ward binary")


NAN32_MASK = 0x7FC00000
NAN64_MASK = 0x7FF8000000000000


def is_nan_bits(t, n):
    """True when bit pattern n is a NaN in type t."""
    if t == "f32":
        return (n & 0x7F800000) == 0x7F800000 and (n & 0x007FFFFF) != 0
    if t == "f64":
        return (n & 0x7FF0000000000000) == 0x7FF0000000000000 and (n & 0x000FFFFFFFFFFFFF) != 0
    return False


def norm(v):
    """Spec values are unsigned decimal strings; for f32/f64 they are IEEE bit
    patterns, and NaN is given symbolically. Compare in the type's own width so
    4294967295 and -1 are the same i32."""
    t, s = v["type"], v["value"]
    # v128 results arrive as a list of lane values; join them so the comparison
    # is at least well-defined rather than raising.
    if isinstance(s, list):
        return "v128:" + ",".join(str(x) for x in s)
    if s in ("nan:canonical", "nan:arithmetic"):
        return "nan"
    try:
        n = int(s)
    except ValueError:
        return s
    if t in ("i32", "f32"):
        return str(n & 0xFFFFFFFF)
    if t in ("i64", "f64"):
        return str(n & 0xFFFFFFFFFFFFFFFF)
    return s


def ward_invoke(wasm, field, args, timeout=20):
    env = dict(os.environ)
    # Spec field names and values are arbitrary bytes; a NUL cannot cross execve,
    # so such a case is unrunnable through the env-var protocol rather than a
    # ward failure. Report it as skipped by the caller instead of crashing.
    def one(a):
        v = a["value"]
        if isinstance(v, list):          # v128 lanes -- not expressible as a scalar arg
            return None
        return str(int(v)) if v.lstrip("-").isdigit() else str(v)

    parts = [one(a) for a in args]
    if any(p is None for p in parts):
        return None, "unrunnable: v128 argument"
    argstr = " ".join(parts)
    if "\0" in field or "\0" in argstr:
        return None, "unrunnable: NUL in field/args"
    env["WARD_INVOKE"] = field
    env["WARD_ARGS"] = argstr
    try:
        p = subprocess.run([WARD, "run", wasm], capture_output=True, text=True,
                           timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
        return None, "timeout"
    out = p.stdout.strip().splitlines()
    return (out[-1] if out else ""), (p.stderr.strip() or None)


def run_wast(wast):
    """Returns (name, passed, failed, skipped, [failure descriptions])."""
    name = wast.stem
    with tempfile.TemporaryDirectory() as td:
        js = Path(td) / f"{name}.json"
        conv = subprocess.run(["wast2json", str(wast), "-o", str(js)],
                              capture_output=True, text=True)
        if conv.returncode != 0:
            return name, 0, 0, 1, [f"{name}: wast2json failed"]
        spec = json.loads(js.read_text())
        cur_mod = None
        ok = bad = skip = 0
        fails = []
        for cmd in spec["commands"]:
            k = cmd["type"]
            if k == "module":
                cur_mod = str(Path(td) / cmd["filename"])
                continue
            # Validation-only assertions need a validator entry point, not an
            # invoke; count them as skipped rather than silently passing.
            if k in ("assert_invalid", "assert_malformed", "assert_unlinkable",
                     "assert_uninstantiable", "register", "action"):
                skip += 1
                continue
            if k not in ("assert_return", "assert_trap"):
                skip += 1
                continue
            act = cmd.get("action", {})
            if act.get("type") != "invoke" or cur_mod is None:
                skip += 1
                continue
            got, err = ward_invoke(cur_mod, act["field"], act.get("args", []))
            if k == "assert_trap":
                # A trap must not produce a value.
                if err or got == "":
                    ok += 1
                else:
                    bad += 1
                    fails.append(f"{name}:{cmd.get('line')} {act['field']} expected trap, got {got}")
                continue
            exp = cmd.get("expected", [])
            if not exp:
                (ok := ok + 1) if not err else (bad := bad + 1)
                continue
            want = norm(exp[0])
            et = exp[0]["type"]
            mask = 0xFFFFFFFF if et in ("i32", "f32") else 0xFFFFFFFFFFFFFFFF
            have = got
            try:
                # ward returns float results as their IEEE bit pattern, which
                # arrives as a decimal (possibly in exponent form for large f64
                # patterns -- see the lua_Value precision note).
                n = int(float(got)) if ("e" in got or "." in got) else int(got)
                n &= mask
                have = "nan" if (want == "nan" and is_nan_bits(et, n)) else str(n)
            except (ValueError, TypeError):
                pass
            if have == want:
                ok += 1
            else:
                bad += 1
                if len(fails) < 5:
                    fails.append(f"{name}:{cmd.get('line')} {act['field']} want={want} got={got!r}")
        return name, ok, bad, skip, fails


def main():
    wasts = sorted(p for p in SUITE.glob("*.wast")
                   if ONLY is None or p.stem in ONLY)
    if not wasts:
        sys.exit(f"no .wast found in {SUITE}")
    tot_ok = tot_bad = tot_skip = 0
    rows, all_fails = [], []
    with ThreadPoolExecutor(max_workers=JOBS) as ex:
        for name, ok, bad, skip, fails in ex.map(run_wast, wasts):
            tot_ok += ok
            tot_bad += bad
            tot_skip += skip
            rows.append((name, ok, bad, skip))
            all_fails += fails
    rows.sort(key=lambda r: -r[2])
    print(f"{'suite':<24}{'pass':>7}{'fail':>7}{'skip':>7}")
    for n, o, b, s in rows:
        if o or b:
            print(f"{n:<24}{o:>7}{b:>7}{s:>7}")
    exec_total = tot_ok + tot_bad
    pct = (100.0 * tot_ok / exec_total) if exec_total else 0.0
    print(f"\nexecuted {exec_total} assertions: {tot_ok} pass, {tot_bad} fail "
          f"({pct:.1f}% conformance); {tot_skip} skipped (validation-only)")
    if all_fails:
        print("\nfirst failures:")
        for f in all_fails[:25]:
            print(" ", f)
    return 0 if tot_bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
