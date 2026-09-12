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
# Round-2 expansion (2026-09-11): reassociation chains across the
# immediate-form boundary (4095/4096). Two imm adds can fold to one
# non-imm add; cancellation (net zero) must survive. 64-bit wrap cases
# use full observability. Appended additively; the original directed()
# is preserved as _base_directed.

_base_directed = directed

_KNOWN32 = ("known-32bit-limitation: integer literals above 4294967295 "
            "are truncated at compile time (bench/README.md); this 64-bit "
            "wrap probe mismatches until literals go 64-bit")


def _chain2(cid, x0, op1, c1, op2, c2, note=""):
    idol = f"x = {x0}\nr = x {op1} {c1}\nr = r {op2} {c2}\nr\n"
    cbody = (f"unsigned long long x = {x0}ULL; "
             f"unsigned long long r = x {op1} {c1}ULL; r = r {op2} {c2}ULL;")
    return {"id": f"imm/{cid}", "idol": idol, "ret": "r",
            "cbody": cbody, "cret": "r", "signed": False,
            "full": True, "note": note}


def directed():
    cases = _base_directed()
    chains = [
        # (cid, x0, op1, c1, op2, c2, note)
        ("chain0", 0, "+", 4095, "+", 1, "imm+imm folds to +4096 (non-imm)"),
        ("chain1", 0, "+", 4096, "+", 4096, "two non-imm adds"),
        ("chain2", 0, "+", 1, "+", 4095, "imm+imm = 4096, reversed order"),
        ("chain3", 0, "+", 2048, "+", 2048, "imm+imm = 4096 exactly"),
        ("chain4", 0, "+", 4095, "+", 4095, "imm+imm = 8190"),
        ("chain5", 100000, "-", 4096, "-", 1, "two non-imm subs"),
        ("chain6", 100000, "-", 1, "-", 4096, "imm sub then non-imm"),
        ("chain7", 100000, "-", 4095, "-", 1, "net -4096"),
        ("chain8", 5000, "+", 5000, "-", 1000, "big add then small sub"),
        ("chain9", 123456789, "+", 4095, "-", 4095,
         "cancellation: net zero across the boundary"),
        ("wrap0", 18446744073709551615, "+", 1, "+", 0,
         "64-bit wrap to 0 on imm add. " + _KNOWN32),
        ("wrap1", 18446744073709551614, "+", 2, "+", 0,
         "64-bit wrap to 0 on non-imm add. " + _KNOWN32),
        ("wrap2", 18446744073709551615, "-", 1, "-", 0,
         "no wrap on sub from max. " + _KNOWN32),
        ("chain10", 0, "+", 65536, "+", 65536, "movk-range chain"),
        ("chain11", 123456789, "+", 4096, "-", 4096, "cancellation, net zero"),
        ("chain12", 4294967295, "+", 1, "+", 1, "crossing 2^32 via imm"),
        ("chain13", 4294967295, "-", 1, "-", 1, "imm sub pair at 2^32-1"),
        ("chain14", 100, "+", 8192, "-", 4096, "non-imm then imm"),
        ("chain15", 3000000, "+", 1000000, "-", 2000000,
         "big consts through addi/subi"),
        ("chain16", 0, "+", 4097, "+", 4097, "just over the boundary twice"),
        ("chain17", 4294967295, "+", 4294967295, "+", 0,
         "movk+movk chain, full 64-bit"),
        ("chain18", 0, "+", 4095, "-", 1, "net +4094 across boundary"),
        ("chain19", 18446744073709551615, "+", 4096, "+", 0,
         "wrap: max+4096 = 4095. " + _KNOWN32),
        ("chain20", 1000, "+", 4095, "-", 4095, "cancellation at 1000"),
        ("chain21", 18446744073709551615, "-", 4095, "-", 1,
         "wrap: max-4096 across the boundary. " + _KNOWN32),
    ]
    for cid, x0, op1, c1, op2, c2, note in chains:
        cases.append(_chain2(cid, x0, op1, c1, op2, c2, note=note))
    return cases
