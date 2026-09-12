"""Nested loops and per-level bound registers.

`while` with a constant bound loads it into register 11+wopen (one bound
register per nesting level); with a variable bound it uses that
variable's register. These cases stress that bound registers neither
clobber each other nor leak across nesting levels, and that inner
countdown loops reload their bound on every outer iteration.
"""
import random as _random

OPT = "nest"
DESC = "nested loops, per-level bound registers, variable bounds"


def _mk(cid, idol, cbody, full=False, note=""):
    return {"id": f"nest/{cid}", "idol": idol, "ret": "t",
            "cbody": cbody, "cret": "t", "signed": False,
            "full": full, "note": note}


def directed():
    return [
        _mk("three_deep",
            "t = 0\na = 0\nwhile a < 10\n  b = 0\n  while b < 20\n"
            "    c = 0\n    while c < 30\n      t = t + 1\n      c = c + 1\n"
            "    b = b + 1\n  a = a + 1\nt\n",
            "unsigned long long t=0;for(unsigned long long a=0;a<10;a++)"
            "for(unsigned long long b=0;b<20;b++)"
            "for(unsigned long long c=0;c<30;c++){t++;}",
            note="3 levels, const bounds (bound regs 11,12,13)"),
        _mk("triangular",
            "t = 0\ni = 0\nwhile i < 25\n  j = 0\n  while j < i\n"
            "    t = t + 1\n    j = j + 1\n  i = i + 1\nt\n",
            "unsigned long long t=0;for(unsigned long long i=0;i<25;i++)"
            "for(unsigned long long j=0;j<i;j++){t++;}",
            note="variable inner bound"),
        _mk("var_outer",
            "t = 0\nn = 17\ni = 0\nwhile i < n\n  j = 0\n  while j < 5\n"
            "    t = t + 1\n    j = j + 1\n  i = i + 1\nt\n",
            "unsigned long long t=0,n=17;for(unsigned long long i=0;i<n;i++)"
            "for(unsigned long long j=0;j<5;j++){t++;}",
            note="variable outer bound"),
        _mk("zero_trip_inner",
            "t = 0\no = 0\nwhile o < 100\n  i = 10\n  while i < 5\n"
            "    t = t + 1\n    i = i + 1\n  o = o + 1\nt\n",
            "unsigned long long t=0;for(unsigned long long o=0;o<100;o++)"
            "{unsigned long long i=10;while(i<5){t++;i++;}}",
            note="zero-trip inner loop (cf. bench zerotrip)"),
    ]


def gen(rng, n):
    cases = []
    for i in range(n):
        A = rng.randrange(2, 60)
        B = rng.randrange(2, 60)
        idol = (f"t = 0\na = 0\nwhile a < {A}\n  b = 0\n  while b < {B}\n"
                f"    t = t + 1\n    b = b + 1\n  a = a + 1\nt\n")
        cbody = (f"unsigned long long t=0;for(unsigned long long a=0;a<{A};a++)"
                 f"for(unsigned long long b=0;b<{B};b++){{t++;}}")
        cases.append(_mk(f"r{i:04d}", idol, cbody))
    return cases
