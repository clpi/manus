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
| x86_64 + Windows | backend not implemented — see `platforms/x86_64-windows.sh` |
| ARM64 + Windows | backend not implemented — see `platforms/arm64-windows.sh` |

`run.sh` aborts on hosts without a backend instead of silently skipping.

## Known limitations (not hidden)

- **Compile-time constants are 32-bit.** The host Idol runtime wraps
  compile-time integer arithmetic (`+`, `*`, `&`, `>>`, ...) at 32 bits, so
  integer literals above 4294967295 (and constant-folded results above it)
  are silently truncated in emitted code. Runtime values are full 64-bit.
  Every program in this suite uses constants below 2^32. Fixing this needs
  host-side 64-bit integers; it is tracked, not ignored.
- **No floating point, memory ops, calls, or strings** in the compiled
  subset yet, so those benchmark categories cannot be expressed. They are
  absent from the suite rather than faked.
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
