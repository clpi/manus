"""Copy propagation / term(): `r = x` emits a register move, `r = C`
emits an immediate load. No arithmetic, so this mostly guards the
register allocator's name->register mapping (reg/names registry),
including variables whose names share prefixes.
"""
import random as _random

OPT = "copy"
DESC = "term(): variable copies and constant loads (mov/movz)"


def _mk(cid, idol, cbody, cret="r", full=False, note=""):
    return {"id": f"copy/{cid}", "idol": idol, "ret": "r",
            "cbody": cbody, "cret": cret, "signed": False,
            "full": full, "note": note}


def directed():
    return [
        _mk("chain", "a = 12345\nb = a\nr = b\nr\n",
            "unsigned long long a=12345ULL,b=a,r=b;"),
        _mk("const", "r = 999\nr\n",
            "unsigned long long r=999ULL;"),
        _mk("const_big", "r = 70000\nr\n",
            "unsigned long long r=70000ULL;", full=True,
            note="needs movz+movk"),
        # shared name prefixes: the names registry must not confuse
        # `xa` with `xab` (regression area for the v5 names-registry fix).
        _mk("prefix",
            "xa = 5\nxab = 7\nr = xa\nr = r + xab\nr\n",
            "unsigned long long xa=5ULL,xab=7ULL,r=xa;r=r+xab;",
            note="shared name prefixes"),
        _mk("self", "x = 41\nx = x\nr = x\nr\n",
            "unsigned long long x=41ULL;x=x;unsigned long long r=x;",
            note="self copy"),
    ]


def gen(rng, n):
    cases = []
    names = ["a", "b", "c", "d", "e", "f"]
    for i in range(n):
        v = rng.randrange(0, 2**32)
        a, b = rng.sample(names, 2)
        idol = f"{a} = {v}\n{b} = {a}\nr = {b}\nr\n"
        cbody = (f"unsigned long long {a}={v}ULL,{b}={a},r={b};")
        cases.append(_mk(f"r{i:04d}", idol, cbody))
    return cases

# Round-2 expansion (2026-09-11): copy-propagation chains -- longer
# chains, copies of big constants, and copies feeding arithmetic, so a
# propagator that stops after one hop is caught. Appended additively;
# the original directed() is preserved as _base_directed.

_base_directed = directed


def directed():
    cases = _base_directed()
    cases.extend([
        _mk("longchain", "a = 7\nb = a\nc = b\nd = c\nr = d\nr\n",
            "unsigned long long a=7ULL,b=a,c=b,d=c,r=d;",
            note="four-hop copy chain"),
        _mk("bigconst_copy", "r = 70000\ns = r\nr = s\nr\n",
            "unsigned long long r=70000ULL,s=r;r=s;", full=True,
            note="copy of a movz+movk constant"),
        _mk("prefix3", "xa = 1\nxab = 2\nxabc = 3\nr = xa\nr = r + xab\n"
            "r = r + xabc\nr\n",
            "unsigned long long xa=1ULL,xab=2ULL,xabc=3ULL,r=xa;"
            "r=r+xab;r=r+xabc;",
            note="three shared name prefixes"),
        _mk("selfcopy2", "x = 41\nx = x\nx = x\nr = x\nr\n",
            "unsigned long long x=41ULL;x=x;x=x;unsigned long long r=x;",
            note="repeated self copy"),
        _mk("copyop", "a = 100\nb = a\nr = b + 1\nr\n",
            "unsigned long long a=100ULL,b=a,r=b+1ULL;",
            note="copy feeding arithmetic"),
        _mk("indep", "p = 3\ns = p\nr = s + 10\nr\n",
            "unsigned long long p=3ULL,s=p,r=s+10ULL;",
            note="short chain with constant add"),
    ])
    return cases
