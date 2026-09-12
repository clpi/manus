# Optimization verification (`bench/verify`)

Differential proof that the Idol native compiler's optimizations are
semantics-preserving. For each optimization, randomized and adversarial
Idol programs are compiled with the compiler-under-test (built fresh
from `lib/compiler/native.id` for every run) and against bit-identical
C oracles compiled with `clang -O3`; both binaries run and their
observable behavior must agree. **Any divergence is a compiler bug**:
the failing case is saved under `.work/failures/<opt>/<case>/` as
`case.id` + `oracle.c` + `result.json`, and the run exits 1.

## Optimizations covered

| module | optimization (native.id) | what is tested |
|---|---|---|
| `fold` | constant folding (`foldop`: `+,-,*` on literals) | folded == runtime 64-bit result, incl. 32-bit boundary |
| `simp` | algebraic identities (`simpadd`/`simpmul`) | `x+0`,`x-0`,`x-x`,`x*1`,`x*0` (+ mirrored) |
| `imm` | immediate add/sub (`addi`/`subi` for C<4096) | 4095/4096 boundary, both lowering paths, 64-bit wrap |
| `mulred` | multiply strength reduction | `*2^k`->shift, `*3/5/7/9`->shift-add, others->`mul` |
| `countdown` | pure-counter countdown loops (`purecount`, v5) | soundness + adversarial defeat cases |
| `copy` | `term()`: copies and constant loads | register mapping, shared name prefixes |
| `div` | integer division (`sdiv`, never folded) | trunc-toward-zero, literal division, negatives |
| `nest` | nested loops, per-level bound registers | 3-deep nests, variable bounds, zero-trip inner |

## Observability

The harness observes the process exit code — the low 8 bits of the
return register. Two modes:

- **exit-code mode** (default): one run per case. Fast; blind to bugs
  that only affect bits 8..63 (e.g. the known 32-bit compile-time wrap,
  which preserves the low 8 bits by construction).
- **--full**: each case is additionally compiled 8 times returning
  `(value / 256^k)` for k=0..7, so the exit code exposes byte k of the
  full 64-bit result. Division truncates toward zero on both sides
  (ARM64 `sdiv`, C signed `/`), so byte slices agree even for negative
  values. Cases whose bug class needs this (32-bit wrap, negative
  folds) carry `full=True` individually.

Generators must end their Idol source with a bare variable (the `ret`
contract in `opts/__init__.py`) and must not use the variable `q`.

## Adversarial cases

`countdown` and `fold` include cases *designed to defeat* the
optimization (double increment per iteration, counter read after the
loop, constants at the 32-bit wrap boundary). These are tagged
`EXPECTED-ADVERSARIAL`: a mismatch there confirms a suspected
unsoundness and is reported as a bug with the tag attached — the suite
working as designed, not a suite failure.

## Known-limitation buckets

Mismatches labelled `known-32bit-limitation` map to the documented
limitation in `bench/README.md` (host-side compile-time arithmetic
wraps at 32 bits; negative folded constants are zero-extended). They
are reported, not suppressed — the day the limitation is fixed, these
cases flip to passing and prove it.

## Running

```
./verify.py                      # all opts, 30 random seeds each (~5-10 min)
./verify.py --quick              # smoke: 8 seeds each
./verify.py --opts fold,countdown --seeds 100 --full
./verify.py --list-opts
```

Builds go through the platform shim interface (`bench/platforms/`),
so this suite runs on any host whose shim reports `supported`. All
artifacts live in `bench/verify/.work/` (git-ignored) — the timing
workstream's `bench/.work/` is never touched.

## Results discipline

Same as the benchmark suite: every mismatch is published. `RESULTS.md`
(in this directory) is rewritten on any run that finds a mismatch,
with per-opt tables and the full mismatch list. A clean run prints
`verify: all cases pass.` and exits 0.
