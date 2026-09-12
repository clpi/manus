#!/usr/bin/env python3
"""Executable audit catalog: ARM64 fusion misses in Idol's native backend.

Builds nativebench from lib/compiler/native.id, compiles the embedded
25-program corpus, disassembles, and scans for the cataloged miss patterns:

  madd   mul d,n,m  -> add d,...        (fuse into madd)
  msub   mul d,n,m  -> sub d,...        (fuse into msub)
  shift  lsl t,n,sh -> add/sub ..,t,..  (fold into shifted operand)
  sbr    cmp a,b    -> b.lt/gt/le/ge    (signed compare+branch; tbz/tbnz cand)

Prints a TSV catalog (program, madd, msub, shift, sbr, tbz) and asserts the
totals equal EXPECTED. Update EXPECTED as fusions land; the git history of
this file is the re-audit record. Exit 0 = catalog matches, 1 = drift.

The corpus is embedded so the gate is self-contained: no external .id
inputs are read. (bench/programs/*.id are untracked working copies.)

No-prose: this file replaces a Markdown audit report.
"""
import os
import re
import subprocess
import sys

# Baseline 2026-09-12 (vs clang -O3): 6 mul->add (mul11, mul13,
# reassocmul, upbr2, upbranch x2), 0 mul->sub, 1 lsl->sub (predbranch),
# 11 signed cmp+branch (2 while-x<0 tbnz cands: upbr2, upbranch).
# madd fused 2026-09-12: mul->add 6 -> 0.
# tbnz fused 2026-09-12: while-x<0 backedge cmp+b.lt -> tbnz x,#63;
# sbr 11 -> 9, tbz 0 -> 2.
# shfold fused 2026-09-12: lsl->add/sub -> shifted operand; shift 1 -> 0.
# Ported to main 2026-09-12: sbr 9 -> 7. Main's poly pass summarizes
# nestvar's nested loops (t = t + 7998000), eliminating its 2 cmp+branch.
# This is pre-existing main behavior, not a fusion regression.
EXPECTED = {"madd": 0, "msub": 0, "shift": 0, "sbr": 7, "tbz": 2}

PROGS = {
"arith": """x = 1
i = 0
while i < 50000000
  x = x * 3
  x = x + 7
  x = x - 2
  i = i + 1
x
""",
"bigconst": """x = 0
i = 0
while i < 50000000
  x = x + 5000
  x = x - 4000
  i = i + 1
x
""",
"bigconst2": """x = 0
i = 0
while i < 50000000
  x = x + 2000000000
  x = x - 1000000000
  i = i + 1
x
""",
"div": """x = 1000000
i = 0
while i < 20000000
  x = x / 3
  x = x + 5
  i = i + 1
x
""",
"divby7": """x = 1000000
i = 0
while i < 20000000
  x = x / 7
  x = x + 5
  i = i + 1
x
""",
"divmul": """x = 1000000
i = 0
while i < 20000000
  x = x / 3
  x = x * 3
  x = x + 1
  i = i + 1
x
""",
"fib": """t = 0
o = 0
while o < 2000
  a = 0
  b = 1
  i = 0
  while i < 35
    c = a + b
    a = b
    b = c
    i = i + 1
  t = t + a
  o = o + 1
t
""",
"mul11": """x = 1
i = 0
while i < 50000000
  x = x * 11
  x = x + 1
  i = i + 1
x
""",
"mul13": """x = 1
i = 0
while i < 50000000
  x = x * 13
  x = x + 1
  i = i + 1
x
""",
"nest": """t = 0
a = 0
while a < 2000
  b = 0
  while b < 2000
    t = t + 1
    b = b + 1
  a = a + 1
t
""",
"nest3": """t = 0
a = 0
while a < 200
  b = 0
  while b < 200
    c = 0
    while c < 200
      t = t + 1
      c = c + 1
    b = b + 1
  a = a + 1
t
""",
"nestvar": """t = 0
a = 0
while a < 4000
  b = 0
  while b < a
    t = t + 1
    b = b + 1
  a = a + 1
t
""",
"predbranch": """t = 0
o = 0
while o < 3000000
  h = o / 2
  d = h * 2
  x = o - d
  j = 0
  while j < x
    t = t + 1
    j = x
  o = o + 1
t
""",
"reassoc": """x = 12345
i = 0
while i < 50000000
  x = x + 7
  x = x + 9000
  x = x - 3
  i = i + 1
x
""",
"reassocmul": """x = 3
i = 0
while i < 50000000
  x = x * 3
  x = x * 5
  x = x + 1
  i = i + 1
x
""",
"startup": """42
""",
"startupbig": """x = 1
x = 2
x = 3
x = 4
x = 5
x = 6
x = 7
x = 8
x = 9
x = 10
x = 11
x = 12
x = 13
x = 14
x = 15
x = 16
x = 17
x = 18
x = 19
x = 20
x = 21
x = 22
x = 23
x = 24
x = 25
x = 26
x = 27
x = 28
x = 29
x = 30
x = 31
x = 32
x = 33
x = 34
x = 35
x = 36
x = 37
x = 38
x = 39
x = 40
x = 41
x = 42
x = 43
x = 44
x = 45
x = 46
x = 47
x = 48
x = 49
x = 50
x = 51
x = 52
x = 53
x = 54
x = 55
x = 56
x = 57
x = 58
x = 59
x = 60
x = 61
x = 62
x = 63
x = 64
x = 65
x = 66
x = 67
x = 68
x = 69
x = 70
x = 71
x = 72
x = 73
x = 74
x = 75
x = 76
x = 77
x = 78
x = 79
x = 80
x = 81
x = 82
x = 83
x = 84
x = 85
x = 86
x = 87
x = 88
x = 89
x = 90
x = 91
x = 92
x = 93
x = 94
x = 95
x = 96
x = 97
x = 98
x = 99
x = 100
42
""",
"stride2": """t = 0
i = 0
while i < 100000000
  t = t + 1
  i = i + 2
t
""",
"subbig": """x = 0
i = 0
while i < 50000000
  x = x - 9000
  x = x + 8000
  i = i + 1
x
""",
"sum": """s = 0
i = 1
while i < 100000001
  s = s + i
  i = i + 1
s
""",
"sumstride": """s = 0
i = 1
while i < 100000001
  s = s + i
  i = i + 2
s
""",
"upbr2": """t = 0
o = 0
x = 12345
while o < 3000000
  x = x * 1103515245
  x = x + 12345
  j = 0
  while x < 0
    t = t + 1000
    j = j + 1
    x = 0
  k = 0
  m = 1 - j
  while k < m
    t = t + 1
    k = m
  o = o + 1
t
""",
"upbranch": """t = 0
o = 0
while o < 3000000
  x = o * 1103515245
  x = x * 1103515245
  x = x + 12345
  c = 0
  while x < 0
    c = c + 1
    x = x * 1103515245
    x = x + 12345
  t = t + c
  o = o + 1
t
""",
"zerotrip": """t = 0
o = 0
while o < 10000000
  i = 10
  while i < 5
    t = t + 1
    i = i + 1
  o = o + 1
t
""",
"zerotrip2": """t = 0
o = 0
while o < 10000000
  b = o / 10000000
  i = 5
  while i < b
    t = t + 1
    i = i + 1
  o = o + 1
t
""",
}

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))
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
    assert len(PROGS) == 25, f"expected 25 programs, found {len(PROGS)}"
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
    for name in sorted(PROGS):
        src = PROGS[name]
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
