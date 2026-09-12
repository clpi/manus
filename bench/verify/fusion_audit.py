#!/usr/bin/env python3
"""Executable audit catalog: ARM64 fusion misses in Idol's native backend.

Builds nativebench from lib/compiler/native.id, compiles every program in
bench/programs/, disassembles, and scans for the cataloged miss patterns:

  madd   mul d,n,m  -> add d,...        (fuse into madd)
  msub   mul d,n,m  -> sub d,...        (fuse into msub)
  shift  lsl t,n,sh -> add/sub ..,t,..  (fold into shifted operand)
  sbr    cmp a,b    -> b.lt/gt/le/ge    (signed compare+branch; tbz/tbnz cand)

Prints a TSV catalog (program, madd, msub, shift, sbr, tbz) and asserts the
totals equal EXPECTED. Update EXPECTED as fusions land; the git history of
this file is the re-audit record. Exit 0 = catalog matches, 1 = drift.

No-prose: this file replaces a Markdown audit report.
"""
import os
import re
import subprocess
import sys

# Pre-fix baseline (2026-09-12, vs clang -O3): 6 mul->add sites (mul11,
# mul13, reassocmul, upbr2, upbranch x2), 0 mul->sub, 1 lsl->sub
# (predbranch), 11 signed cmp+branch (2 of which are while-x<0 tbz cands).
EXPECTED = {"madd": 6, "msub": 0, "shift": 1, "sbr": 11, "tbz": 0}

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))
PROGDIR = os.path.join(ROOT, "bench", "programs")
WORK = os.path.join(ROOT, "bench", "verify", ".work", "fusion_audit")
IDOL = os.path.join(ROOT, "zig-out", "bin", "idol")
NATIVE_ID = os.path.join(ROOT, "lib", "compiler", "native.id")

SBRANCH = {"b.lt", "b.gt", "b.le", "b.ge"}


def run(*args):
    p = subprocess.run(args, capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit(f"audit: command failed: {' '.join(args)}\n{p.stderr[-2000:]}")
    return p.stdout


def disasm(objpath):
    out = run("otool", "-tvV", objpath)
    ins = []
    for line in out.splitlines():
        m = re.match(r"^[0-9a-f]+\s+(\S+)\s*(.*)$", line.strip())
        if m:
            ins.append((m.group(1), m.group(2).strip()))
    return ins


def regs(operands):
    return [r.strip() for r in operands.split(",") if r.strip()]


def scan(ins):
    madd = msub = shift = sbr = tbz = 0
    for i, (m, o) in enumerate(ins):
        if m in ("tbz", "tbnz"):
            tbz += 1
        if i + 1 >= len(ins):
            continue
        m1, o1 = m, o
        m2, o2 = ins[i + 1]
        r1, r2 = regs(o1), regs(o2)
        if m1 == "mul" and len(r1) == 3 and m2 in ("add", "sub") and r2:
            d = r1[0]
            if r2[0] == d and d in r2[1:]:
                if m2 == "add":
                    madd += 1
                else:
                    msub += 1
        if m1 == "lsl" and len(r1) == 3 and m2 in ("add", "sub") and len(r2) == 3:
            if r1[0] != r2[0] and r1[0] in r2[1:]:
                shift += 1
        if m1 == "cmp" and m2 in SBRANCH:
            sbr += 1
    return madd, msub, shift, sbr, tbz


def main():
    os.makedirs(WORK, exist_ok=True)
    nb = os.path.join(WORK, "nativebench")
    if len(sys.argv) > 1 and sys.argv[1].startswith("--nb="):
        nb = sys.argv[1][5:]
        print(f"audit: using existing nativebench {nb}", file=sys.stderr)
    else:
        print(f"audit: building nativebench from {NATIVE_ID}", file=sys.stderr)
        run(IDOL, "compile", NATIVE_ID, "--backend", "native", "-o", nb)
    totals = {"madd": 0, "msub": 0, "shift": 0, "sbr": 0, "tbz": 0}
    rows = []
    progs = sorted(f for f in os.listdir(PROGDIR) if f.endswith(".id"))
    assert len(progs) == 25, f"expected 25 programs, found {len(progs)}"
    for prog in progs:
        name = prog[:-3]
        src = open(os.path.join(PROGDIR, prog)).read()
        obj = os.path.join(WORK, name + ".o")
        hexout = subprocess.run([nb], input=src, capture_output=True,
                                text=True).stdout
        open(obj, "wb").write(bytes.fromhex("".join(hexout.split())))
        madd, msub, shift, sbr, tbz = scan(disasm(obj))
        for k, v in zip(totals, (madd, msub, shift, sbr, tbz)):
            totals[k] += v
        rows.append((name, madd, msub, shift, sbr, tbz))
    print("program\tmadd\tmsub\tshift\tsbr\ttbz")
    for r in rows:
        print("\t".join(str(x) for x in r))
    print("TOTAL\t" + "\t".join(str(totals[k])
                                  for k in ("madd", "msub", "shift", "sbr",
                                            "tbz")))
    bad = {k: (totals[k], EXPECTED[k]) for k in EXPECTED
           if totals[k] != EXPECTED[k]}
    if bad:
        sys.exit(f"audit: CATALOG DRIFT {bad}")
    print("audit: catalog matches EXPECTED")


if __name__ == "__main__":
    main()
