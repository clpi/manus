"""Multiply strength reduction (mulred in calc()):
    x * 2^k -> lsl (shift)
    x * 3   -> addsh (x + x<<1)
    x * 5   -> addsh (x + x<<2)
    x * 7   -> lsl + sub (x<<3 - x)
    x * 9   -> addsh (x + x<<3)
    anything else -> generic mul

Both operand orders are tested (mulred is consulted for `x*C` and `C*x`).
All rewrites are exact over 64-bit wrapping arithmetic, so randomized x
up to 2^64-1 must agree bit-for-bit (full=True throughout).
"""
import random as _random

OPT = "mulred"
DESC = "multiply strength reduction: shifts and shift-adds (mulred)"

_REDUCED = [2, 3, 4, 5, 7, 8, 9, 16, 32, 64]
_GENERIC = [6, 10, 11, 12, 13, 14, 15, 17, 100, 1000]


def _mk(cid, c2, c1, swap, note=""):
    if swap:
        iexpr, cexpr = f"{c2} * x", f"{c2}ULL * x"
    else:
        iexpr, cexpr = f"x * {c2}", f"x * {c2}ULL"
    idol = f"x = {c1}\nr = {iexpr}\nr\n"
    cbody = f"unsigned long long x = {c1}ULL; unsigned long long r = {cexpr};"
    return {"id": f"mulred/{cid}", "idol": idol, "ret": "r",
            "cbody": cbody, "cret": "r", "signed": False,
            "full": True, "note": note}


def directed():
    cases = []
    for i, c2 in enumerate(_REDUCED + _GENERIC):
        cases.append(_mk(f"c{i}", c2, 123456789012345, False,
                         note="reduced" if c2 in _REDUCED else "generic"))
        cases.append(_mk(f"c{i}s", c2, 123456789012345, True,
                         note="swapped operand order"))
    # wrap: reduced forms must wrap identically to mul
    cases.append(_mk("wrap3", 3, 18446744073709551615, False,
                     note="x*3 near 2^64-1"))
    cases.append(_mk("wrap7", 7, 18446744073709551615, False,
                     note="x*7 near 2^64-1"))
    return cases


def gen(rng, n):
    cases = []
    for i in range(n):
        c2 = rng.choice(_REDUCED + _GENERIC)
        c1 = rng.choice([0, 1, rng.randrange(0, 2**32),
                         rng.randrange(0, 2**64)])
        swap = rng.random() < 0.5
        cases.append(_mk(f"r{i:04d}", c2, c1, swap))
    return cases
