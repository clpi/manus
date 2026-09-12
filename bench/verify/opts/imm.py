"""Immediate-form add/sub: `x + C` / `x - C` with C < 4096 compiles to a
single addi/subi; C >= 4096 falls back to movz(+movk) + add/sub.

The critical edge is 4095/4096. Both paths must compute the same 64-bit
result for arbitrary x (including x near 2^64-1, where add wraps).
"""
import random as _random

OPT = "imm"
DESC = "immediate add/sub for C<4096 vs movz+add/sub for C>=4096"

_EDGE = [0, 1, 2, 4094, 4095, 4096, 4097, 8192, 65535, 1000000]


def _mk(cid, op, c1, c2, note=""):
    cop = "+" if op == "+" else "-"
    idol = f"x = {c1}\nr = x {cop} {c2}\nr\n"
    cbody = (f"unsigned long long x = {c1}ULL; "
             f"unsigned long long r = x {cop} {c2}ULL;")
    return {"id": f"imm/{cid}", "idol": idol, "ret": "r",
            "cbody": cbody, "cret": "r", "signed": False,
            "full": True, "note": note}


def directed():
    cases = []
    for i, c2 in enumerate(_EDGE):
        cases.append(_mk(f"add_edge{i}", "+", 123456789, c2,
                         note="immediate-form boundary"))
        cases.append(_mk(f"sub_edge{i}", "-", 987654321, c2,
                         note="immediate-form boundary"))
    # wrap-around: x + C crossing 2^64
    cases.append(_mk("add_wrap", "+", 18446744073709551610, 10,
                     note="64-bit wrap on immediate add"))
    cases.append(_mk("sub_wrap", "-", 3, 10,
                     note="64-bit wrap on immediate sub"))
    return cases


def gen(rng, n):
    cases = []
    for i in range(n):
        op = rng.choice(["+", "-"])
        c1 = rng.choice([0, rng.randrange(0, 2**32), rng.randrange(0, 2**64)])
        # bias toward the boundary
        c2 = rng.choice(_EDGE + [rng.randrange(0, 2**20)])
        cases.append(_mk(f"r{i:04d}", op, c1, c2))
    return cases
