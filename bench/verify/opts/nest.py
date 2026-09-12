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

# Round-2 expansion (2026-09-11): nested-loop shapes for the loop-eval
# workstream -- deeper nests, zero-trip middles, variable/scaled bounds,
# purity-killing inner bodies, and sequential inner loops. Appended
# additively; the original directed() is preserved as _base_directed.

_base_directed = directed


def directed():
    cases = _base_directed()
    cases.extend([
        _mk("four_deep",
            "t = 0\na = 0\nwhile a < 2\n  b = 0\n  while b < 2\n"
            "    c = 0\n    while c < 2\n      d = 0\n      while d < 3\n"
            "        t = t + 1\n        d = d + 1\n"
            "      c = c + 1\n    b = b + 1\n  a = a + 1\nt\n",
            "unsigned long long t=0;for(unsigned long long a=0;a<2;a++)"
            "for(unsigned long long b=0;b<2;b++)"
            "for(unsigned long long c=0;c<2;c++)"
            "for(unsigned long long d=0;d<3;d++){t++;}",
            note="4-deep nest, 2*2*2*3=24"),
        _mk("zero_trip_middle",
            "t = 0\na = 0\nwhile a < 5\n  b = 10\n  while b < 5\n"
            "    c = 0\n    while c < 3\n      t = t + 1\n      c = c + 1\n"
            "    b = b + 1\n  a = a + 1\nt\n",
            "unsigned long long t=0;for(unsigned long long a=0;a<5;a++)"
            "{unsigned long long b=10;while(b<5){"
            "for(unsigned long long c=0;c<3;c++){t++;}b++;}}",
            note="zero-trip middle loop hides an inner loop"),
        _mk("var_bound_3deep",
            "t = 0\na = 0\nwhile a < 10\n  b = 0\n  while b < 4\n"
            "    c = 0\n    while c < b\n      t = t + 1\n      c = c + 1\n"
            "    b = b + 1\n  a = a + 1\nt\n",
            "unsigned long long t=0;for(unsigned long long a=0;a<10;a++)"
            "for(unsigned long long b=0;b<4;b++)"
            "for(unsigned long long c=0;c<b;c++){t++;}",
            note="innermost bound is the middle counter: 10*(0+1+2+3)=60"),
        _mk("scaled_bound",
            "t = 0\na = 0\nwhile a < 6\n  m = a * 2\n  b = 0\n  while b < m\n"
            "    t = t + 1\n    b = b + 1\n  a = a + 1\nt\n",
            "unsigned long long t=0;for(unsigned long long a=0;a<6;a++)"
            "{unsigned long long m=a*2ULL;"
            "for(unsigned long long b=0;b<m;b++){t++;}}",
            note="inner bound computed from outer counter: 2*(0+..+5)=30"),
        _mk("mentions_inner",
            "t = 0\na = 0\nwhile a < 5\n  b = 0\n  while b < 4\n"
            "    t = t + b\n    b = b + 1\n  a = a + 1\nt\n",
            "unsigned long long t=0;for(unsigned long long a=0;a<5;a++)"
            "for(unsigned long long b=0;b<4;b++){t=t+b;}",
            note="inner body reads its own counter (purity kill): 5*6=30"),
        _mk("const_zero_inner",
            "t = 0\na = 0\nwhile a < 7\n  b = 0\n  while b < 0\n"
            "    t = t + 1\n    b = b + 1\n  a = a + 1\nt\n",
            "unsigned long long t=0;for(unsigned long long a=0;a<7;a++)"
            "{unsigned long long b=0;while(b<0){t++;b++;}}",
            note="constant zero-trip inner loop"),
        _mk("triangular_3deep",
            "t = 0\na = 0\nwhile a < 10\n  b = 0\n  while b < a\n"
            "    c = 0\n    while c < b\n      t = t + 1\n      c = c + 1\n"
            "    b = b + 1\n  a = a + 1\nt\n",
            "unsigned long long t=0;for(unsigned long long a=0;a<10;a++)"
            "for(unsigned long long b=0;b<a;b++)"
            "for(unsigned long long c=0;c<b;c++){t++;}",
            note="triangular 3-deep: 120"),
        _mk("sequential_inners",
            "t = 0\na = 0\nwhile a < 4\n  b = 0\n  while b < 3\n"
            "    t = t + 1\n    b = b + 1\n  c = 0\n  while c < 2\n"
            "    t = t + 10\n    c = c + 1\n  a = a + 1\nt\n",
            "unsigned long long t=0;for(unsigned long long a=0;a<4;a++)"
            "{for(unsigned long long b=0;b<3;b++){t++;}"
            "for(unsigned long long c=0;c<2;c++){t=t+10ULL;}}",
            note="two sequential inner loops: 4*(3+20)=92"),
    ])
    return cases
