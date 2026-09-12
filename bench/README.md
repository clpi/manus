# Idol benchmark suite

A skeptical, reproducible performance suite for the Idol native compiler
(`lib/compiler/native.id`). Its job is to try to prove Idol is **not** the
fastest — and to report, loudly, every case where it succeeds.

## What it measures

Ten programs, each in Idol (`programs/*.id`, the compiler's integer subset)
and in C (`programs/*.c`, bit-identical semantics, exit code = result mod 256):

| program | what it stresses | why it is in the suite |
|---|---|---|
| `sum` | arithmetic series 1..100M | idiom probe: clang closes the loop to O(1); we do not (yet) |
| `arith` | `x*3+7-2` x50M, carried dep | strength reduction (`*3` -> shift-add) and immediate adds |
| `fib` | nested fib(35) x2000 | nested loops, carried dependency chain |
| `nest` | 2000x2000 counter | loop/branch overhead, per-level bound registers |
| `div` | `x/3+5` x20M | **adversarial**: division has no strength reduction |
| `mul13` | `x*13+1` x50M | **adversarial**: 13 is not a power of two nor a shift-add constant |
| `bigconst` | `x+5000-4000` x50M | **adversarial**: constants > 4095 defeat immediate-form add/sub |
| `zerotrip` | 10M zero-trip inner loops | **adversarial**: do-while form pays an extra initial jump |
| `upbranch` | LCG-driven unpredictable branches x3M | branch-misprediction stress |
| `startup` | `42` | process startup latency (dyld + runtime init) |

Plus, per program: object size (`.o` bytes) and source-to-executable
compile time (median of 5).

### Extended suite (opt-in)

Five more programs live in `programs/` but are **not** in the default
run list — the default list is frozen while the runtime-loss
workstream does its fixes. Run them explicitly:

```
./run.sh --progs "predbranch mul11 subbig stride2 startupbig"
```

| program | what it stresses | why it is in the suite |
|---|---|---|
| `predbranch` | strictly alternating data-dependent branch x3M | **predictable** branch: pairs with `upbranch` (unpredictable LCG); a history-based predictor learns the period-2 pattern |
| `mul11` | `x*11+1` x50M | **adversarial**: 11 is outside the strength-reduction set {2^k, 3, 5, 7, 9} |
| `subbig` | `x-9000+8000` x50M | **adversarial**: sub with constant > 4095 defeats immediate-form subi |
| `stride2` | `i = i + 2` loop x50M iters | **adversarial**: non-unit stride defeats the countdown transform (`purecount` needs exactly `i = i + 1`) |
| `startupbig` | 100 constant stores, then `42` | refined startup: scales static code size to separate per-byte load cost from fixed spawn cost |

Every extended program is correctness-gated the same way (Idol and C
exit codes must agree) before it may join the default list.

## How it runs

```
./run.sh                 # full: 21 interleaved rounds, ~10-20 min
./run.sh --quick         # smoke: 5 rounds
./run.sh --progs "sum fib" --compilers "clang"
```

1. **Builds the compiler from source.** `run.sh` recompiles
   `lib/compiler/native.id` with the repo's `idol` binary before timing
   anything, so results always reflect the current tree, never a stale binary.
2. **Builds every program** with Idol and with each available C compiler
   (`clang -O3`, `gcc -O3`).
3. **Correctness gate.** Every binary must exit with the same code. Any
   mismatch aborts the run: a wrong answer is a bug, not a data point.
4. **Warmup + interleaved timing.** 3 untimed warmup runs, then N timed
   rounds executed as idol, clang, gcc, idol, clang, gcc, ... so thermal
   drift, frequency scaling, and background load affect all competitors
   equally. No cherry-picked quiet window.
5. **Statistics** (`timing.py`): median (primary — robust, no outlier
   removal needed), mean, stddev, min, max, p95. Outliers are counted by
   Tukey's fence (Q3 + 3*IQR) and disclosed, never dropped.
6. **Significance**: Welch's t-test of Idol vs the best rival median,
   p < 0.05. Margin of victory reported on medians.
7. **RESULTS.md** is rewritten with every program x every compiler.
   There is no filter and no skip: losses appear in the same table.

## Reproducing by hand

```sh
cd /Users/clp/work/idol-main
zig build                                            # provides zig-out/bin/idol
./zig-out/bin/idol compile lib/compiler/native.id --backend native -o /tmp/nb
/tmp/nb < bench/programs/sum.id | xxd -r -p > /tmp/sum.o
SDK=$(xcrun --show-sdk-path)
ld -arch arm64 -e _idolmain -platform_version macos 14.0 14.0 \
   -syslibroot $SDK /tmp/sum.o -lSystem -o /tmp/sum.idol
clang -O3 bench/programs/sum.c -o /tmp/sum.clang
time /tmp/sum.idol; echo $?; time /tmp/sum.clang; echo $?
```

Both must print `128`. Repeat timing in interleaved order; compare medians.

## Platforms

| platform | status |
|---|---|
| ARM64 + macOS | supported (this suite runs here today) |
| ARM64 + Linux | backend not implemented — see `platforms/arm64-linux.sh` |
| x86_64 + Linux | backend not implemented — see `platforms/x86_64-linux.sh` |
| x86_64 + Windows | backend not implemented — see `platforms/arm64-windows.sh` |
| ARM64 + Windows | backend not implemented — see `platforms/x86_64-windows.sh` |

`run.sh` aborts on hosts without a backend instead of silently skipping.

### Shim interface

`bench/platforms/` holds one shim per host triple, plus `lib.sh`
(the loader and the interface contract). A shim is **sourced, never
executed**, and provides:

| symbol | meaning |
|---|---|
| `plat_triple` | e.g. `arm64-macos` |
| `plat_status` | `supported` or `planned` |
| `plat_idol_object SRC.id DST` | compile Idol source to a relocatable object (uses `$IDOL_NATIVE`) |
| `plat_link OBJ EXE` | link a relocatable object into an executable |
| `plat_c_exe SRC.c EXE` | compile C to an executable (`-O3`, best available compiler) |

```sh
source bench/platforms/lib.sh
SHIM="$(plat_shim)" || exit 3          # this host's shim, or failure
IDOL_NATIVE=/path/to/nativebench source "$SHIM"
plat_idol_object prog.id prog.o && plat_link prog.o prog.exe
```

Planned shims implement the same functions as stubs (print
`not implemented`, return 3) with comments telling the backend agent
exactly what to fill in. To land a backend: implement the three
functions, set `plat_status="supported"`, remove the host abort in
`run.sh`. `bench/verify/` already builds through this interface, so a
new supported shim lights up verification on that host with no other
changes.

## Optimization verification

`bench/verify/` differentially proves the compiler's optimizations
semantics-preserving: per optimization (constant folding, algebraic
simplification, immediate add/sub, multiply strength reduction,
countdown loops, copy propagation, division, nested-loop bound
registers), randomized + adversarial Idol programs are compiled with a
freshly built compiler and against bit-identical `clang -O3` oracles;
exit codes (and, with `--full`, all 8 bytes of the 64-bit result) must
agree. Any divergence is a compiler bug, saved with its reproducer.
See `bench/verify/README.md`. This is where the countdown loop's
soundness holes and the 32-bit constant-fold boundary are nailed down
as executable tests rather than folklore.

## Gated benchmark categories

`bench/gated/` holds benchmark categories the Idol subset cannot
express yet — floating point (`fp_dot`), indirect calls (`indirect`),
string ops (`strops`), data-structure traversal (`traverse`), and the
cache-friendly vs cache-hostile pair (`cache_seq`/`cache_stride`).
Each has a frozen C oracle and an `.id.future` sketch of the intended
Idol source, plus the exact compiler feature that unlocks it. They are
absent from the suite rather than faked, and each carries an adoption
checklist for the day its gate opens.

## Known limitations (not hidden)

- **Compile-time constants are 32-bit.** The host Idol runtime wraps
  compile-time integer arithmetic (`+`, `*`, `&`, `>>`, ...) at 32 bits, so
  integer literals above 4294967295 (and constant-folded results above it)
  are silently truncated in emitted code. Runtime values are full 64-bit.
  Every program in this suite uses constants below 2^32. Fixing this needs
  host-side 64-bit integers; it is tracked, not ignored.
  `bench/verify/opts/fold.py` contains directed cases at this boundary.
- **No floating point, memory ops, calls, or strings** in the compiled
  subset yet, so those benchmark categories cannot be expressed. They are
  absent from the suite rather than faked (see `bench/gated/`).
- **Executable tests link with the system `ld`** against libSystem. The
  measured code is the compiler's; the final linker-free executable path
  is separate work.
- Only compilers installed on the machine compete. On this host: Idol,
  clang `-O3`, gcc `-O3`. No rustc/go/swiftc here; their absence is
  reported, not concealed.

## Reading the results

- `verdict: win` means Idol's median was lower with p < 0.05.
- `verdict: loss` means a rival beat Idol. Per the suite's contract, that
  is a bug report: file it, fix the codegen, re-run.
- `sum` is *expected* to lose: clang recognizes the arithmetic series and
  runs O(1). Matching that needs loop-idiom recognition in the compiler.
  It stays in the suite as the honest gap it is.
- **RESULTS.md discipline:** every program x every compiler is listed —
  wins and losses, no filter. Extended-suite programs appear under the
  same rule whenever they are run; their results are published in the
  same table, never in a separate "good news only" file.
