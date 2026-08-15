# Idol WASM engine vs wasmtime — measured baseline

Everything below is a measurement with the command that produced it. Nothing
here is an estimate unless it says UNMEASURED.

    machine    Apple M2 Pro, 10 cores, 16 GiB, macOS 26.5.2
    revision   d4745587  (the tree also contains uncommitted edits by other
                          agents; those were NOT measured)
    control    wasmtime 47.0.3 (5554cc1a6 2026-07-31)
    also ran   wasmer 7.2.1, wasm3 v0.5.0
    toolchain  wabt 1.0.41, LLVM clang (brew llvm) + wasi-libc sysroot

## 0. The engine does not build from source

`zig build wasm-test` runs `idol compile src/engine.id --backend=c --emit exe`.
At d4745587 that fails, and so does every other backend:

    cd tools/wasm && ../../zig-out/bin/idol compile src/engine.id \
        --backend=c --emit exe -o /tmp/w
    # /tmp/duo_engine.c:7171: error: expected ')'
    # /tmp/duo_engine.c:7916: error: call to undeclared function 'db__floor'

    ../../zig-out/bin/idol compile src/engine.id --backend=native ...
    # error: direct backend: DNB001 application: 853 relation: err
    #        missing: keyed-table-export

These are compiler defects, not engine defects. Minimal repro of the first:

    printf 'main: i64 = ()\n  x: f64 = 3.7\n  y: f64 = x:floor()\n  0\n' > t.id
    idol compile t.id --backend=c --emit exe -o t.out
    # error: call to undeclared function 'x__floor'

`engine_workarounds.py` documents and applies the four smallest edits that get
past them (`:floor/:ceil/:sqrt` -> `math.*`, `:char()` -> `string.char()`,
`bytes:byte()` through a typed shim, and `:len()` -> `string.len()`).
`build_engine.sh` does the whole thing against a pristine `git archive` copy:

    ./build_engine.sh d4745587 /tmp/idol_wasm_engine

The fourth workaround is the load-bearing one. `x:len()` compiles to
`lua_str_buf_len_i64()`, which returns 0 for a string produced by an io read:

    method=0        # b:len()        on a 27791-byte fib.wasm
    string=27791    # string.len(b)  on the same value

Every wasm module is therefore shorter than 8 bytes as far as the engine is
concerned, so every module fails the magic-number check and the engine exits
1 — in silence, because the diagnostic goes through `iom.err` = `io.err`, which
the C runtime does not define. **Unpatched, the engine at d4745587 cannot load
any wasm module at all.**

## 1. Conformance, scored against the whole suite

    cd benchmarks/wasm_rt/conform
    WARD=/tmp/idol_wasm_engine/ward python3 spec_conformance.py \
        --suite /Users/clp/x/wart/third_party/testsuite

    .wast converted      : 159  (wast2json refused 98)

    FULL-SUITE DENOMINATOR (assert_return + assert_trap) : 55011
      attempted by engine (zero-arg invoke)              : 2450  (4.45%)
      UNRUNNABLE - engine has no argument channel        : 52560
      UNRUNNABLE - other                                 : 1

      pass  : 1702   = 3.09% OF THE FULL SUITE
      fail  : 748
      (pass rate within the attempted subset only: 69.5%)

    validation-only assertions (no validator entry point): 3837

**3.09%, not 69.5%.** The 4.45% ceiling is one capability: the engine has no
way to pass arguments to an exported function. `main()` reads
`DUO_WASM_MODULE` and `DUO_WASM_INVOKE` from the environment and the single
call site is `run_body(bytes, len, tgt, 0)` — no operands. 95.5% of the suite's
assertions invoke with arguments and are therefore unrunnable, not failing.

3.09% is an upper bound: wabt 1.0.41 could not convert 98 of the 257 `.wast`
files (newer proposals), and their assertions are not in the 55,011 denominator
at all.

Zero SIMD assertions pass in any `simd_*` suite except `simd_const` (62 of
261). `global` is 7 pass / 46 fail; `start` is 0 / 6.

The committed harness `conform/run_spec.id` cannot produce this number, or any
number: it does not parse (`run_spec.id:36:8: error: write ')' at this token
edge`), and it drives the engine through `WARD_INVOKE` / `WARD_ARGS`, which the
engine has never read.

## 2. Workloads

`./build.sh` compiles `kernels/*.c` to wasm32-wasip1 at -O2. Sizes and seeds
come from `volatile` globals so neither LLVM nor a consuming JIT can fold the
loop away — `benchmarks/wasm_rt/hot.c` shows the trap: LLVM unrolls it 248x and
strength-reduces its affine recurrence, so "60,000,000 iterations" is really
7.5M iterations of a 9-opcode body.

    k_startup  write one byte and exit
    k_int32    serial xorshift32 chain, 40M iterations
    k_int      serial xorshift64 chain, 40M iterations
    k_calls    6M indirect calls through an 8-entry funcref table
    k_mem32    bulk fill + strided read/write over a 1 MiB static arena
    k_mem      1200 malloc/free rounds, 48-64 KiB each
    k_data32   dependent pointer chase over 2 MiB static, 24 passes
    k_data     dependent pointer chase over 8 MiB (malloc), 12 passes

`k_int32`, `k_mem32` and `k_data32` exist only because the i64 and malloc
versions do not run on the Idol engine; see §4.

## 3. The comparison

    WARD=/tmp/idol_wasm_engine/ward python3 run_bench.py --runs 5

Total wall time, best of 5, same machine, same module bytes, answers checked
against wasmtime's (all matching answers, no MISMATCH rows):

    workload         wasmtime        wasmer         wasm3          idol
    k_startup          7.2 ms       15.3 ms        8.3 ms        2.8 ms
    k_int32          116.5 ms      133.8 ms      329.8 ms     1979.5 ms
    k_int            119.5 ms      125.7 ms      309.1 ms    CANNOT RUN
    k_calls           74.5 ms       74.8 ms    CANNOT RUN      695.0 ms
    k_mem32            9.6 ms       27.7 ms       12.4 ms       20.8 ms
    k_mem             13.8 ms       28.1 ms       16.3 ms    CANNOT RUN
    k_data32         107.0 ms       97.4 ms      111.6 ms      508.8 ms
    k_data           210.6 ms      232.8 ms      276.7 ms    CANNOT RUN

Steady state, each runtime's own startup subtracted:

    workload       wasmtime        idol   idol/wasmtime
    k_int32        109.3 ms   1976.8 ms           18.1x
    k_calls         67.4 ms    692.2 ms           10.3x
    k_mem32          2.5 ms     18.0 ms            7.3x
    k_data32        99.8 ms    506.1 ms            5.1x

Startup alone:

    wasmtime       7.2 ms
    wasm3          8.3 ms
    wasmer        15.3 ms
    idol           2.8 ms      <- 2.6x faster than wasmtime

**Startup is the one axis where the Idol engine wins, and it wins clearly.**
Steady state it is 5.1x to 18.1x behind wasmtime, and behind wasm3 — a small
portable interpreter — by 6.0x on k_int32 (1979.5 vs 329.8 ms).

Correctness differential on the seven pre-existing fixtures in
`benchmarks/wasm_rt/`: all seven agree with wasmtime by value
(fib, hot, loop_i32, calls, memory, brtable, hot_big).

wasm3's `CANNOT RUN` on k_calls is wasm3's own limit, not a property of the
module: `wasm3 wasm/k_calls.wasm` reports `Error: LEB encoded value overflow`.
wasmtime, wasmer and the Idol engine all execute it and agree on the answer.

## 4. Where the time goes, ranked by measured contribution

### 1. There is no JIT. Everything runs on the interpreter. (the whole 5-18x)

The engine prints `engine=interp` for every module measured. The gate is
`jitm.arch() == "arm64"`, and `jit` is the compiler's builtin module, whose C
runtime provides only on/off/flush/status/version:

    printf 'main(): void\n  print("arch=" .. to(str)(jit.arch()))\n  c = jit.alloc(1024)\n  if c\n    print("alloc=ok")\n  else\n    print("alloc=nil")\n  end\n' > tjit.id
    idol compile tjit.id --backend=c --emit exe -o tjit.out && ./tjit.out
    # arch=nil
    # alloc=nil

So the ARM64 JIT in `engine.id` (~1,700 lines) and `src/wasm/jit_arm64.id` is
unreachable code in the build `build.zig` prescribes. `src/jit.zig` hardcodes
`arch` to the literal `"native"` in both of its emit paths, so the gate would
be false even where the module is fully provisioned. Closing this is the only
change that can plausibly reach wasmtime; nothing below can.

`src/wasm/jit.id` is a separate, unused stub (`// TODO: bytecode-to-C
translation`, returns 0) that `engine.id` does not import, and it is corrupted
at HEAD by a mechanical `#` -> `:len()` rewrite: it contains
`"include:len() <stdint.h>"` and `sig:len().params`.

### 2. Interpreter dispatch is a linear if/elseif chain (51 arms)

    WARD=/tmp/idol_wasm_engine/ward python3 dispatch_probe.py --iters 1000000

    opcode            arm      best   ns/unit    delta = chain cost
    i32.eqz             7   222.0 ms     6.94           (reference)
    i32.clz            18   366.7 ms    11.46  +4.52 ns = 0.411 ns/arm
    i32.extend8_s      44   626.9 ms    19.59 +12.65 ns = 0.342 ns/arm

Three opcodes with identical stack shape and identical one-ALU-op bodies differ
by 2.8x purely by position in the chain: ~0.35-0.41 ns per arm tested, about
1.3 cycles. An opcode at arm 44 spends **65% of its time being looked for**.

Four hot opcodes are tested first (`i32.const`, `local.get`, i32 arithmetic,
`local.tee`), which is why `k_int32` — whose loop is almost entirely those four
— is *not* dominated by chain walking, and is still 18.1x behind. Counting the
chain in source order from `run_body`: loads are arm 19, stores 20,
`call_indirect` 21, `memory.size`/`memory.grow` 45, the SIMD prefix 48, out of
51 arms total.

Closing this (jump table / computed goto) plausibly buys 1.3x-2.8x on anything
that is not in the four fast arms. It is not a path to parity.

### 3. Indirect-call dispatch: +29.1 ns per call

    WARD=/tmp/idol_wasm_engine/ward python3 call_probe.py --iters 4000000

    variant         best   ns/iteration                     delta
    inline       162.4 ms          40.6
    direct       212.3 ms          53.1           +12.5 ns = call
    indirect     328.8 ms          82.2      +29.1 ns = table+sig

On k_calls (6M indirect calls, 692 ms steady state) that is ~175 ms (25%) for
table lookup plus signature check beyond a plain call, and ~250 ms (36%) for
call machinery in total. The remaining ~64% is ordinary opcode dispatch.

### 4. Per-opcode interpretive overhead itself — the residual

LLVM unrolls `mix32` 2x, so 40M source iterations are 20M loop passes of a
44-opcode body:

    wasm-objdump -d wasm/k_int32.wasm \
      | awk '/func\[5\] <mix32>/,/func\[6\]/' \
      | awk '/\| *loop/{f=1;next} /\| *end/{if(f){print c; exit}} f{c++}'
    # 44

That is 880M wasm opcodes in 1976.8 ms = **2.25 ns/op, ~7.9 cycles at 3.5 GHz**,
using only fast-path arms. wasmtime runs the same 880M opcodes in 109.3 ms =
0.124 ns/op, ~0.43 cycles — it is executing fused native instructions, not
opcodes. This residual is what item 1 exists to remove.

A `sample(1)` profile confirms there is nothing else in the picture:

    sample <pid> 1 -mayDie      # while running k_int32
    # 768 Thread ... : 768 run_body (in ward)
    # Sort by top of stack: run_body (in ward)  768

768 of 768 samples are inside `run_body`, with no calls out — no allocator, no
boxing helpers, no host calls.

### 5. Memory bounds-checking strategy — UNMEASURED in isolation

`k_data32` (dependent chase, no hoistable check) has the *best* ratio of the
four at 5.1x, which argues bounds checking is not the dominant term relative to
dispatch. But it was not isolated with a checks-off build, so the split between
check cost and dispatch cost inside that 5.1x is UNMEASURED.

### 6. Missing SIMD — UNMEASURED as a time contribution

A capability gap, not a measured cost: zero assertions pass in every `simd_*`
suite except `simd_const`. No workload here uses SIMD, so it contributes
nothing to the numbers above.

### 7. Host-call overhead — measured as approximately zero

See the `sample` profile in item 4: no frames outside `run_body`.

## 5. Capability gaps (results, not timings)

| gap | evidence |
|---|---|
| No argument channel to exports | `run_body(bytes, len, tgt, 0)`; caps conformance at 4.45% of the suite |
| `memory.grow` always fails | `(memory.grow (i32.const 1))` returns `4294967295` (-1); wasmtime returns `1`. Any wasi-libc heap use therefore aborts: k_mem and k_data both trap |
| i64 kernel refuses | k_int: `wasm: cannot execute opcode 58 (i32.store8) at body offset 185 (unsupported operand shape...)` |
| All diagnostics are silent | `iom.err` is `io.err`; the C runtime has no such function, so bail/trap paths exit 70/71 printing nothing. Use `ward-diag` from `build_engine.sh` |
| f64 fixture fails | `benchmarks/wasm_rt/loop_f64.wasm` exits 70 |
| The engine's own JIT demo fails | `jitable.wasm` exports `compute(i32)`, which cannot be invoked without an argument channel |

## 6. Reproducing all of it

    cd benchmarks/wasm_rt/perf
    ./build_engine.sh d4745587 /tmp/idol_wasm_engine
    ./build.sh
    export WARD=/tmp/idol_wasm_engine/ward
    python3 ../conform/spec_conformance.py --suite /path/to/testsuite
    python3 run_bench.py --runs 5
    python3 dispatch_probe.py --iters 1000000
    python3 call_probe.py --iters 4000000

These harnesses are python3 rather than `.id`. That is deliberate and should be
revisited: `conform/run_spec.id` is the `.id` port of the old `run_spec.py`,
and it currently does not parse and does not match the engine's env protocol,
so the tree's only measurement harness produces nothing. A harness that cannot
be trusted to run is worse than one in the wrong language; port these back once
`.id` tooling builds reliably.
