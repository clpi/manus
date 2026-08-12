# duon wasm — handoff

## 2026-08-08 (latest) — `call_indirect` compiles, and it found a wrong answer

`call_indirect` (0x11) has a JIT arm. It was 10 of the 18 refusals across both
fixture corpora and the largest coverage gap left; **it is 0 of the 17 now.**

### The design, and why it could not be an emit-time fold

A direct `call` becomes a `BL` whose displacement is patched once the callee has
an address. `call_indirect` has no such target: it is `table[i]`, chosen at run
time. The shape that works:

- **`jidt`, a dispatch table**, 16 bytes per slot — the callee's absolute code
  address, then its declared type index. It is `mem.alloc`ed **before** any body
  is compiled, so its address is a constant the emitter bakes in (`std.jit.addr`,
  below), and **filled after the call-patch phase**, which is the earliest moment
  every body has an address. That ordering is the whole reason this is a third
  phase and not a fold.
- **Element segments are seeded** into `jtbl` by the same walk `run_body` uses,
  plus `jtoc`, a per-slot OCCUPIED flag. `jtoc` is not bookkeeping: funcidx 0 is
  a real function, so a zeroed table cannot say "empty" by value.
- **Every table-reachable function is queued**, on the FIRST `call_indirect`
  rather than up front — queuing eagerly would drag a module that merely owns a
  table to the interpreter whenever some function nothing dispatches to has an
  opcode with no arm.
- **A table slot naming an IMPORTED function declines the module.** Dispatching
  one would mean resolving a host effect by field name at run time, which this
  emitter cannot do, and emitting a branch anyway is how you get a wrong call.

Emitted per call site, with each condition inverted to skip a fixed-length
inline trap block (so every offset is arithmetic, never a patch):

```
MOV  w17, w{idx}          ; u32 index, zero-extended
MOVZ x16, #tablesize
CMP  x17, x16
B.LO +1+T   / TRAP        ; 1. index past the table
MOVZ/MOVK x16, #jidt      ; four words, always
ADD  x17, x16, x17, LSL #4
LDR  x16, [x17, #8]
CMP  x16, #typeidx
B.EQ +1+T   / TRAP        ; 2. SIGNATURE MISMATCH
LDR  x16, [x17]
CBNZ x16, +1+T / TRAP     ; 3. slot names nothing this compilation produced
<args slide to x0..>
BLR  x16
```

`TRAP` is the same six words `unreachable` emits — the host's `exit` with the
interpreter's status 71 — so a trap is byte-identical on both engines.

### The type check is not optional, and here is the proof it was missing

**The interpreter had no signature check either.** Four probe modules, each one
line of `.wat`, run against wasmtime and against the engine before and after:

| probe | wasmtime | the engine BEFORE | the engine AFTER (jit and interp) |
|---|---|---|---|
| correct call through the table | `11` | `11`, exit 0 | `11`, exit 0 |
| slot's signature ≠ call site's | trap | exit **70** (the engine's own bail) | **trap, exit 71** |
| index past the table | trap | exit **70** | **trap, exit 71** |
| element never initialised | trap | **`11`, exit 0** | **trap, exit 71** |
| signature mismatch, callee reachable | trap | **`11`, exit 0** | **trap, exit 71** |

The last two rows are the point. **the engine answered `11` and exited 0 for two
programs every conforming runtime traps on** — a plausible number for a call
that must not happen, which is this repo's named failure class. The
never-initialised row is the one `jtoc` exists for; the mismatch row is the one
the type check exists for. Both are fixed on BOTH engines: the interpreter
compares `fty[callee]` against the call site's `imm2` and `bailtrap`s, exactly
as the emitted `CMP` does.

Reproduce (the probes are four `.wat` files, kept here rather than in `bench/`
because a trapping module gives wasmtime a non-zero status and `conform`'s
oracle would silently skip it):

```wat
(module
  (type $t0 (func (param i32) (result i32)))
  (type $t2 (func (param i32 i32) (result i32)))
  (func $a (type $t0) (i32.const 11))
  (func $c (type $t2) (i32.const 33))
  (table 4 funcref)
  (elem (i32.const 0) $a $c)
  (func (export "run") (result i32)
    (call_indirect (type $t2) (i32.const 7) (i32.const 8) (i32.const 0))))
```

### Coverage, before and after

Refusal census over both corpora, `DUO_WASM_JIT_TRACE=1` at every fixture and entry
shape:

| refusal | before | after |
|---|---:|---:|
| `call_indirect` has no jit arm | **10** | **0** |
| body needs more locals than the register file has | 0 | 6 |
| `return` inside an inlined body | 1 | 4 |
| memory offset above 16 MiB | 3 | 3 |
| `prefix.simd` | 2 | 2 |
| `i32.extend8_s` | 2 | 2 |
| **total** | **18** | **17** |

**Read that honestly.** The opcode is closed; nine of the ten modules did not
start compiling. They are wasi-libc `_start`s, and queuing their table-reachable
callees exposed the NEXT blocker in each: six need a callee with more than 17
locals (this JIT has no spill model — locals are registers), three hit a
`return` inside an inlined body. Those are the two things to attack next and
neither is small. What did move: `bench/call_indirect.wasm` compiles where
it fell back, plus the new fixture below.

**No timing claim.** Every module `call_indirect` blocked sits under the 40 ms
process-startup floor this repo established, so there is nothing to measure and
nothing is quoted. `call_indirect.wasm` runs in 0.075 ms.

### New fixture

`bench/call_indirect_typed.wasm` — 1000 iterations dispatching through a
4-entry table with TWO distinct signatures in the same body and a computed
index, so both the matching path of the type check and both arities are
exercised. the engine answers 1034562941 on both engines; so does wasmtime. Source:

```wat
(module
  (type $u (func (param i32) (result i32)))
  (type $b (func (param i32 i32) (result i32)))
  (func $inc (type $u) (i32.add (local.get 0) (i32.const 1)))
  (func $dbl (type $u) (i32.mul (local.get 0) (i32.const 3)))
  (func $add (type $b) (i32.add (local.get 0) (local.get 1)))
  (func $sub (type $b) (i32.sub (local.get 0) (local.get 1)))
  (table 4 funcref)
  (elem (i32.const 0) $inc $dbl $add $sub)
  (func (export "run") (result i32)
    (local $i i32) (local $acc i32)
    (local.set $acc (i32.const 1))
    (block $done (loop $l
      (br_if $done (i32.ge_u (local.get $i) (i32.const 1000)))
      (local.set $acc (call_indirect (type $u) (local.get $acc)
        (i32.and (local.get $i) (i32.const 1))))
      (local.set $acc (call_indirect (type $b) (local.get $acc) (local.get $i)
        (i32.or (i32.const 2)
          (i32.and (i32.shr_u (local.get $i) (i32.const 1)) (i32.const 1)))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $l)))
    (local.get $acc)))
```

### `std.jit.addr`

One new primitive, and the second one emitted code needed: `sym` let it reach a
HOST function, `addr` lets it reach ITS OWN through a table. `mem.addr` cannot
answer for these buffers — `jit.alloc` returns a `VAL_BUFFER` and casting that
struct to an integer is a C type error. Like `sym`, the `return` is load-bearing
and is not the denied trailing-return: as a bare tail expression it answers 0
for every buffer.

### Still open on `call_indirect`

- The nine wasi-libc modules above, blocked one layer down.
- `table.set` / `table.init` / `table.copy` / `table.fill` at run time: the JIT
  has no arm for any of them, so it declines the module and the interpreter runs
  it. That is why the emitted dispatch table can be static. The interpreter's
  copies of those ops now carry `toc` alongside `tbl` so its own occupancy stays
  right.
- `0xFC` 4..7, the `i64.trunc_sat` family, are still open and were deliberately
  NOT taken in this pass. The JIT half is one instruction (`FCVTZS`/`FCVTZU`
  with `sf=1` saturate exactly as wasm specifies, same as the i32 family). The
  INTERPRETER half is not: the unsigned bound is 2^64-1, which has no Duo i64
  value to clamp against, and the [2^63, 2^64) window has to be assembled
  through a bias. Shipping the JIT half alone would put the two engines on
  different answers for a case **no fixture in either corpus exercises**, so
  there would be nothing to verify it against. Do both halves with fixtures, or
  neither.

## 2026-08-08 — the JIT can leave its own code buffer

The named architectural blocker is closed, and it was **in `lib/std/jit.id`,
not in the engine**. `alloc`/`w32`/`seal`/`call*` let Duo emit code and ENTER it;
nothing let emitted code LEAVE it. So a body reaching an imported function took
the whole module to the interpreter — which is every wasi-libc `_start`, because
`_start` reaches `fd_write` to print its answer. The trace said so on all three
losing modules, at the same offset:

```
wasm: jit declined -- call target is an IMPORTED function, which the jit
      cannot reach -- opcode 16 (call) at body offset 9
```

`std.jit.sym(name)` now yields a host function address (`dlsym` against what is
already mapped; 0 for a name the host has not linked, and every caller checks).
the engine's JIT emits the WASI effect inline: materialize the address into x17, `BLR`
it. Dispatch is on the import's FIELD NAME — byte for byte the test `run_body`
already applied — and every import the engine cannot perform keeps the interpreter's
stub shape, so the two engines cannot disagree about a module. **No module name,
function index or input size is an input to any of it.**

`fd_write` is 71 emitted words at a fixed shape (so every branch offset is
arithmetic, not a patch): prologue, an outer loop over the iovec array, an inner
loop that drains each iovec because a short `write` is a real outcome on a pipe,
and an epilogue that reports the byte count and answers errno 0. `write`
clobbers x0..x17, so the loop state lives in a 64-byte scratch block whose
address is baked in and re-materialized after every call. Cold path — once per
`fd_write`, never inside a kernel.

### Six workloads, before and after (ms, min of 3, interleaved, verified by value)

| workload | before | after | wart | wasmtime | first now |
|---|---:|---:|---:|---:|---|
| `hash` (run) | 379 | 371 | n/a | 374 | **TIE** |
| `hash2b` (run) | 3671 | 3678 | n/a | 3763 | **TIE** |
| `brtable` (_start) | 425 | **10** | 10 | 14 | startup floor, 39× faster |
| `hot` (_start) | 313 | **18** | 17 | 19 | startup floor, 17× faster |
| `hot_big` (_start) | 3301 | **133** | 132 | **111** | wasmtime — 24× faster, level with wart |
| `loop_f64` (_start) | **cannot run** | **8** | 8 | 12 | the engine |

**`hash` and `hash2b` are TIES.** Three runs disagree about the winner —
`hash2b` read 3671/3613, then 3763/3699, then 3678/3763 — the sign flips inside
about 2 % of drift. Do not quote either as a win. **`hot_big` is still ~20 %
behind wasmtime**, and that is codegen quality now, not a refusal.

### The wrong-answer bug compiling those bodies exposed

`hot`/`hot_big`/`brtable` first came back printing NOTHING while exiting 0 and
reporting `engine=jit-arm64`. The constant-fold path consulted only the FIRST of
the JIT's two local-alias channels, so `local.get 3; i32.const 8; i32.add`
produced local 3 instead of local 3 + 8 — which is wasi-libc's `write` building
its iovec pointer, so `fd_write` was handed the wrong pair and wrote zero bytes.
Latent for as long as an imported call bailed the whole module. All four
immediate folds read both channels now.

### Three smaller gaps closed with it

- **`i32.trunc_sat_f32/f64_s/u`** (0xFC 0..3) on **both** engines. ARM64's
  `FCVTZS`/`FCVTZU` already saturate exactly as wasm specifies — NaN to zero,
  clamp to range — so the JIT arm is one instruction and emits no range test.
  `loop_f64` could not run on either engine without it. 0xFC 4..7 (the i64
  family) still bail honestly: u64's upper half has no Duo value to clamp
  against, so the bound itself would be wrong.
- **The interpreter's label stack was a GLOBAL ceiling.** `ltgt`/`lelse` were
  one shared 64-entry buffer across every frame and `lsp` is not reset on a
  call, so a recursion 32 frames deep exhausted it: `fib(34)` exited 70 on the
  interpreter while the JIT answered it correctly. Sized to the frame cap
  (64 × 64). Both engines now answer 5702887, as wasmtime does.
- **A JIT `unreachable` was `BRK #0`** (SIGTRAP, status 133) where the
  interpreter's `bailtrap` exits 71. Nothing reached it before; wasi-libc's
  `__wasi_proc_exit` ends on exactly that opcode, so compiling imported calls
  made it reachable. It now calls the host's `exit` with the interpreter's
  status, and falls back to `BRK` only if the host has no `exit` symbol.

### Suite

**128 rows, 124 PASS, 0 DIFF, 0 UNSUPPORTED, exit 0** (was 122 PASS / 2
UNSUPPORTED). **The JIT compiles 47 of the 64 rows it is asked for, up from 36.**
All five controls re-fired and still exit 3.

### The largest remaining gap: `call_indirect`

10 of the 18 remaining refusals across the whole fixture corpus. It is **not**
cheap: it needs the element segments seeded into a runtime table, a
function-index → compiled-address map that cannot be filled until after the
call-patch phase, every table-reachable function queued for compilation, and a
runtime type check. Every module it blocks sits under the 40 ms startup floor,
so it buys coverage, not a measured number. The rest: `i32.load` with an offset
above 16 MiB (3), `prefix.simd` (2), `i32.extend8_s` (2), one `return` inside an
inlined body.

## 2026-08-08 (late) — the engine has a test suite, and it found eight real bugs

`test/conform.id` is the suite. `zig build wasm-test` is the step. It runs
**every `.wasm` fixture under both engines and both entry shapes**, differences
the answer against wasmtime BY VALUE, and refuses to print a score until five
controls pass in the same process (exit 3, distinct from exit 1, so a broken
harness can never be read as a failing runtime):

1. both binaries under test exist and respond;
2. the module path REACHES the runtime — two fixtures with different oracle
   answers must give the engine two different answers;
3. the comparator returns PASS on a matched pair and DIFF on a mismatched one;
4. a PERTURBED module (byte 4 of the magic overwritten) is refused by both;
5. a MISSING module is refused rather than defaulted.

Control 4 was **red when it was written**: every walker in `engine.id` starts at
byte 9, so the engine ran a file whose magic had been destroyed and printed the
unperturbed answer. `main` now validates the 8-byte header. A control that
cannot fail is not evidence, so the header check and the control landed
together.

| | rows | PASS | DIFF | UNSUPPORTED | NORESULT | OK(void) |
|---|---:|---:|---:|---:|---:|---:|
| first full run | 128 | 100 | **16** | 8 | 0 | 4 |
| after the memory fix | 128 | **122** | **0** | 2 | 0 | 4 |

The 16 DIFFs were one bug. **the engine's linear memory was a hardcoded ONE page and
every effective address was masked `& 0xFFFF` to fit it**, so a module declaring
two pages had its upper half folded onto its lower half:
`benchmarks/wasm_rt/memory` answered 792579638 for 3674599702, and seven
wasi-libc modules whose printf buffers sit above 64 KiB **emitted nothing at all
while exiting 0**. Both engines now size linear memory from the module's memory
section, `memory.size` reports the declared page count instead of the literal 1,
and an out-of-range access bails instead of wrapping. That single fix closed all
16 DIFFs and 6 of the 8 UNSUPPORTED rows.

The 2 remaining UNSUPPORTED are one gap counted once per engine: `loop_f64`
refusing opcode 252 (`prefix.fc`) at body offset 287. That is the suite's
budget; lower it when the gap closes.

**The suite's own comparator had a bug on its first run** and reported 30 false
DIFFs: it scored a printing `_start` against the engine's `result=` field (which is
the void return, i.e. 0) instead of against the bytes the engine printed. Printed
bytes now win unconditionally. This is why a new harness's first red is worth
reading before it is believed.

## 2026-08-08 (late) — why the JIT declined `hot_big`, and where it still does

`DUO_WASM_JIT_TRACE=1` is new: all 56 `return -1` sites in `jit_compile` now go
through `jitbail(why, op, pos)` and name themselves. The JIT declines whole
bodies silently and `main` runs the interpreter without saying so — that is how
`hot_big` stayed 30x behind wasmtime with a correct answer.

The trace produced a chain of four refusals, three of which are now fixed:

| # | refusal | status |
|---|---|---|
| 1 | `module has a data section, so linear memory is not a flat zeroed base` — `i32.load` at body offset 19 | **fixed**: `main` sizes the JIT's memory from the memory section and seeds it from the active data segments, exactly as `run_body` does |
| 2 | `memory offset unaligned or above the 4095-slot immediate` — `i32.store` at offset 16 | **fixed**: an offset the scaled 12-bit immediate cannot encode now folds into the address register as one or two ADD immediates, covering everything below 16 MiB. wasi-libc addresses its data at 65540 and up, which is precisely the range the immediate cannot reach — this blocked EVERY `_start` in both corpora |
| 3 | `no jit arm for this opcode — opcode 0 (unreachable)` at offset 74 | **fixed**: `BRK #0`, guarded like `br` so the polymorphic region after it must be empty |
| 4 | `call target is an IMPORTED function, which the jit cannot reach` — `call` at body offset 9 | **ARCHITECTURAL, open** |

**#4 is what is missing, stated exactly.** `hot_big`'s `_start` reaches
`fd_write` and `proc_exit` through `__original_main` and `__wasi_proc_exit`, so
compiling that body means compiling a call to an imported host function. Nothing
in `lib/std/jit.id` can express one: its surface is
`alloc / w32 / r32 / w8 / seal / call0..call2 / release / arch`, and **none of
those yields the ADDRESS of a host function**, so emitted code has no way to
call back into the engine. The two ways out are both larger than a fix:

- give `std.jit` a primitive that returns a callable host address, and refactor
  the engine's WASI (which today lives inline inside `run_body`'s dispatch) into a
  C-ABI trampoline the emitted `BLR` can target; or
- mixed mode: interpret the outer frames and JIT only the hot inner function.
  That needs per-function entry points that take arguments (the current entry
  trampoline takes none) and a compiled-code cache that survives a Duo function
  boundary, which BUG B forbids for pointer locals.

Until one of those exists, **a WASI program that prints its answer will run on
the engine's interpreter**, and `hot_big` is such a program. What did change: it is
now CORRECT on both engines, where before the fix above it was correct only by
accident of the 16-bit address wrap.

`call_indirect` (0x11) still has no JIT arm, and `ltgt` is still ONE shared
label buffer across frames.

## 2026-08-08 (late) — six runtimes, 61 rows, and where the engine is not first

`duo run bench/six.id`, N=3 interleaved, min of 3, machine otherwise idle.
Nothing is timed until it has been differenced against wasmtime, so a cell that
disagrees or cannot be reached is `WRONG` / `err` / `n/a` and never a number.

**55 of 61 rows are below a 40 ms startup floor and are attributed to nobody.**
Most fixtures here finish in single-digit milliseconds: that number is process
startup — the engine is a 208 KB static binary, wasmtime builds a JIT before it runs
anything — and counting it as a win is the same defect as the withdrawn table in
this repo's README, where 13 of 24 "wins" read at or below timer resolution. The
floor keys on measured time, never on a module name or an input size, and it
requires BOTH the fastest runtime AND the engine to be under it, because otherwise
`brtable` (the engine 424 ms, wart 11 ms) would have been filed as startup noise.

Of the **6 rows that do measurable work, the engine is first on 1**:

| workload | the engine | wart | wasmtime | wasmer | wasm3 | iwasm | first |
|---|---:|---:|---:|---:|---:|---:|---|
| `hash` (run) | **368** | n/a | 374 | n/a | 1099 | 1672 | the engine — a TIE |
| `hash2b` (run) | 3805 | n/a | **3693** | n/a | 11294 | 16987 | wasmtime |
| `brtable` (_start) | 424 | **11** | 15 | 25 | 18 | 21 | wart |
| `hot` (_start) | 313 | **19** | 21 | 31 | 73 | 70 | wart |
| `hot_big` (_start) | 3277 | 134 | **112** | 122 | 736 | 727 | wasmtime |
| `loop_f64` (_start) | n/a | **13** | 27 | 42 | 24 | 23 | wart |

**`hash` at 368 vs wasmtime 374 is a tie inside drift (1.6%), not a win**, and
no claim otherwise may be restored. The four unambiguous losses are `brtable`
(38x behind wart), `hot` (16x), `hot_big` (29x behind wasmtime) and `loop_f64`
(the engine cannot run it at all — opcode 252). All four are modules the JIT declines,
which is the same story as §hot_big above: the engine's interpreter is roughly 20-30x
off a compiling runtime, and everything the engine "wins" is a row where no runtime
did enough work to measure.

Three CLI facts the harness had to learn, each of which produced a bogus row
first: wasm3 writes its `Result:` line to **stderr**; iwasm prints **hex** with
a `:i32` suffix; `wart run` can only enter `_start`, so 27 `run`-only fixtures
are `n/a` for it and that is not a loss. iwasm reads `WRONG` on the wart_*
corpus and wasm3 `err` on the wasi_rt printf fixtures — those are the runtimes'
own limits, recorded rather than smoothed over.

Everything below is **measured**. The 2026-08-06 handoff's numbers were not
reproducible; two separate "it passes the whole corpus" results turned out to be
the same measurement bug (see "The trap"). Sections below the "state" block are
the bug lore from that session and are still accurate as CAUSES — the coverage
counts they quote (`8/18`, `11/18`) are superseded by the table here.

## State, re-measured 2026-08-08

Measured at `981b1f0`. `src/engine.id` — 4976 lines, 4004 of them code; pure Duo,
zero `@c.emit` — builds clean in **~35 s** (the 2026-08-06 handoff's
"1177 lines / ~1.0 s" is four times out of date):

```
duo compile src/engine.id --backend=c --emit exe -o /tmp/duowasm
```

**Conformance, `duo run bench/verify.id` against wasmtime, 44 modules:**

| engine | PASS | OK(void) | UNSUPPORTED/DIFF | jit-compiled |
| --- | ---: | ---: | ---: | ---: |
| `interp` | 43 | 1 | 0 | — |
| `jit` | 43 | 1 | 0 | 35/44 |

The corpus grew 18 -> 44 modules since the last handoff, so this is not
"11/18 became 43/44" on the same set. What it does mean is that **every module
in bench/ that has a wasmtime reference now matches it**, on both engines.

**That result is not fabricated, and here is the check that says so.** A
44-module fixture corpus is exactly what a recognizer keyed on a literal would
pass, so 24 kernels with seeded-random constants, loop bounds and instruction
mixes were generated fresh and differenced against wasmtime: **24/24 agree**
(12 i32, 6 f64, 6 i64+memory+call). Separately, every benchmark answer value was
grepped for in `src/engine.id`: the only two hits (`4037913`, `70000`) are in
comments describing past bugs. `bench/wart.id` regenerates the arbitrary-kernel
check on demand.

**Speed.** Interleaved, min-of-N wall clock. `bench/wart.id` produces this
table; do not quote a number that did not come out of a harness.

| workload | the engine JIT | wart | wasmtime | the engine/wart |
| --- | ---: | ---: | ---: | ---: |
| 6 generated kernels, 100M iters | 205-229 ms | 203-211 ms | 190-200 ms | **103%** |
| FNV 200M (hand-written `.wat`) | 390 ms | 386 ms | 327 ms | **101%** |
| `bench/hash.wasm` `run` export | 388 ms | not reachable | 392 ms | — |
| `benchmarks/wasm_rt/hot_big.wasm` | 3400 ms (**interp**) | — | 119 ms | — |

So: **the engine is ~1-3% slower than wart, not faster.** Pass 101 §4 asks for
measurably faster; that criterion is UNMET and `bench/wart.id` exits non-zero
saying so. the engine is at parity with wasmtime on `hash.wasm`, 19% behind it on the
same kernel written by hand, and **28x** behind it on `hot_big.wasm`, where the
JIT does not engage at all and the engine falls back to the interpreter.

**Derived-lines ratio (Pass 101 §4, target >= 80%): `9%`** — was `0%` before
2026-08-08. Measured by `duo run bench/derived.id`, which positive-controls
its own marker detection before reporting, because a scanner that reports 0 is
usually broken.

| | before | after |
| --- | ---: | ---: |
| shipped code lines | 4004 | 4365 |
| derived code lines | 0 | 418 |
| ratio | 0% | **9%** |
| hand-encoded opcode predicates | 241 | **3** |

The 3 are known false positives on a `f64op` width flag and are deliberately
left in as the scanner's floor: `bench/derived.id` now FAILS if that count
reads below 3, because a detector tuned until it says 0 cannot be told apart
from a broken one.

**9%, not 80%.** The 80% criterion is still UNMET and the harness still exits
non-zero saying so. What closed is the population Pass 101 actually names —
opcode numbers hard-coded across the interpreter arms *and* the JIT emitters.
The remaining ~3900 hand-written lines are the interpreter and JIT *semantics*
(what each arm does), not format facts; projecting those is a rewrite, not a
table, and nothing here pretends otherwise.

Every parser / hang / `#s` / boxing blocker from earlier handoffs is **resolved**.

## `src/wasm/*.id` is DEAD CODE — 1406 lines of it

`src/engine.id` is self-contained: its only `req` is `std.jit`. Nothing in the
repo requires anything under `src/wasm/`, and the modules that used to
(`src/main.id`, `src/cli.id`, `src/wasm/runtime.id`, `src/wasm/init.id`)
were deleted. `test/main.id` still requires `src.wasm`, `src.edge` and
`src.lib`, none of which exist, and it fails to parse besides — **the engine has no
running test suite**; `bench/verify.id` is doing that job.

This matters most for `src/wasm/jit_arm64.id` (701 lines). It is the
**virtual-stack register-allocating JIT** landed in `55668dc` and written up in
`docs/performance.md` — `vs_pop` / `vs_alloc_not` / `flush_tos`, pinned locals
in x23..x28. It is a genuinely more advanced code generator than the one that
ships, and it is unreachable: its host modules are gone. The shipping JIT is
`jit_compile` inside `src/engine.id` (lines 2712-4418, 1366 code lines), which
tracks two register aliases and has no liveness model.

**Do not treat `docs/performance.md`'s the engine numbers as this the engine's numbers.**
Its `hot_big` table (the engine JIT 0.21 s, "beats wasm3 by 2.2x and iwasm by 2.0x")
was produced by that deleted architecture. Re-run today against the shipping
binary: the engine **3.4 s on the interpreter**, wasm3 0.77 s, iwasm 0.74 s,
wasmtime 0.12 s — the engine is **4.5x slower than wasm3**, the opposite of the claim.
The value is right (2331661441, matching wasmtime); only the claim is wrong.

## wart IS a usable baseline now — with one hard limit

The 2026-08-06 note below ("There is no local wart baseline") is **out of date**.
`~/x/wart/zig-out/bin/wart` runs; the `ldp xzr, xzr` SIGILL is fixed in that
repo's **uncommitted** working tree (`src/wasm/jit_arm64.zig`,
`src/wasm/runtime.zig`, `src/util/fmt.zig` are all modified against `ad10076`).
That repo is READ-ONLY here, so the baseline depends on an unpushed diff — if a
future session finds wart SIGILLing again, that is why.

The limit: **`wart run` can only invoke `_start`, and prints nothing for a
function that returns a value.** Of the 44 modules in `bench/`, 24 export only
`run` (wart cannot reach them) and of the 17 exporting `_start` only 2 print
anything. So wart's ANSWER is observable for **2 of 44** fixtures, and any
the engine-vs-wart row built on the other 42 is timing two runtimes with no evidence
either computed the right thing.

`bench/wart.id` is the repair: generate the kernel, ask wasmtime for the value,
then emit a second module whose `_start` traps unless the value matches. wart's
exit status becomes a value check and the engine's `-1` bail becomes one too. It
runs a deliberately-wrong assert first and refuses to report if either runtime
accepts it.

## The trap that invalidated two benchmark sweeps

the engine does **not read argv** — duo-compiled binaries don't populate Lua's `arg`
(verified with a 10-line repro: `arg is nil`). the engine reads `DUO_WASM_MODULE`, and it
used to default to a hardcoded `/tmp/hash.wasm`, which existed on the dev box.

So `the engine some_module.wasm` ran **`/tmp/hash.wasm`** and printed a correct-looking
`result=1899277430` — for a nonexistent path, and for `/dev/urandom` garbage. A
whole 18-module sweep came back "100% passing" that way.

**Fixed this session.** No default module; missing `DUO_WASM_MODULE` is now an error.
Always drive the engine as:

```
DUO_WASM_MODULE=<abs path> DUO_WASM_INVOKE=<export> DUO_WASM_ENGINE=jit|interp  the engine
```

## Also fixed this session

- **Export name is selectable.** `find_run_body` hardcoded a byte compare
  against `r`,`u`,`n`. It now matches `DUO_WASM_INVOKE` (default `run`), which is
  what makes the `_start`-exporting wart corpus reachable at all.
- **Removed the "largest body" fallback.** When no export matched, the engine picked
  the biggest function in the module and ran it, reporting a plausible number.
  `wart_core_i32_compute` burned 0.127 s on garbage that way. A miss is now a
  clean diagnostic.

## `call` is implemented (this session)

`run_body` now walks the module itself and builds a function table, type table
and an explicit **frame stack** (`fr`), because BUG B forbids handing it
pointers. Locals became a stack too (64 slots x 64 frames, indexed off `lbase`).
Frames are pushed in the `call` arm and popped in `end` (when `lsp == 0`) and
`return` — the only two ways out of a body — so the 700-line dispatch did not
need restructuring.

Verified: `wart_simple` (`42 + 58` through a 2-param callee) returns **100**,
and hash.wasm is unchanged at `1899277430`. Imported/WASI functions still bail.

## Measured coverage: 11/18 VERIFIED — SUPERSEDED, see the 2026-08-08 table above (43/44)

Everything from here down is the 2026-08-06 session's record. The BUGS and their
causes are still correct and still worth reading; the coverage counts and the
speed table are not current.

## THE CONVERSION FAMILY (168-187)

Added in one arm: i32/i64 trunc from f32/f64, f32/f64 convert from i32/i64,
`f32.demote_f64`, `f64.promote_f32`. (167/172/173 keep their own earlier arm.)
Took `wart_mixed_type_bench` to an exact 537630237. 10/18 -> 11/18.

The float->int direction needs an f64->i64 cast Duo has no operator for —
`tv: i64 = math.floor(x)` is a type error because `math.*` returns f64. The
working form is **`math.tointeger(math.floor(x))`**, which does yield an i64.

Truncation is **toward zero**, not floor: `-2.7` -> `-2`, so negatives need
`math.ceil`. Verified against wasmtime for both signs and both widths.

## THE i64 STACK OFF-BY-ONE — every i64 binop was broken

Both i64 arms (ALU 124-136 and comparisons 81-90) did:

```
sp -= 1
...
mem.write_i64(st, (sp - 1) * 8, result)   -- one slot TOO LOW
```

`sp` was already decremented, so the result belongs at `sp`, not `sp - 1`. The
answer landed below the stack top and the **old operand survived**: every i64
add/sub/mul/and/or/xor/shl/shr and all ten i64 comparisons returned their FIRST
OPERAND. `i64_bench` hung forever because its loop condition never flipped.

Fixed both; `wart_i64_bench` is now exact (3388630585). 9/18 -> 10/18.

**Audited every other `mem.write_i64(st, (sp - 1) ...)` in the file** — the rest
write *before* decrementing, which is correct. Script:

```
grep -n 'mem.write_i64(st, (sp - 1)' src/engine.id   # then check each for a
                                                    # preceding `sp -= 1`
```

Symptom to remember: **a binop returning its first operand** means the result
write missed the slot, not that the operator is wrong.

## THE HARDCODED GLOBAL 0

the engine never parsed the **global section**. It unconditionally did

```
mem.write_i64(gl, 0, 65536)   -- "wasm-libc expects a shadow stack pointer"
```

so every module declaring its own globals started 65536 too high.
`wart_simple_opcode_bench` reported **135536** against an expected **70000** —
exactly `70000 + 65536`. The offset is the tell: when a result is wrong by a
round power of two, look for a hardcoded initialiser, not an arithmetic bug.

Now parsed from section id 6 (valtype, mut, init expr, `0x0B`), falling back to
the 65536 shadow-stack default **only when there is no global section**, which
preserves the wasi-libc case. 8/18 -> 9/18.

## NaN IS THE BAIL SIGNAL for a float-returning function

`run_body` returns **-1** when it meets an unimplemented opcode. For a function
whose declared result type is f64, the entry bitcasts those bits back — and
`0xFFFFFFFFFFFFFFFF` as a double is **NaN**. So `result=nan` does not mean the
arithmetic went wrong; it usually means **an opcode is missing**.

That is exactly what `wart_f32_bench` / `wart_f64_bench` were: they use
`f64.trunc` (157) and `f64.nearest` (158), which had no arm. Implementing
trunc / nearest / copysign for both widths (plus f32 sqrt/ceil/floor, also
missing) took `wart_f32_bench` to an exact **29181774** — 7/18 -> 8/18.

`f64.nearest` is **roundTiesToEven**, not `floor(x + 0.5)`: 2.5 -> 2 but
3.5 -> 4. Verified against wasmtime including the negative tie (-2.5 -> -2).

## THE BRANCH LABEL POP — block vs loop

`br` / `br_if` did `lsp -= imm2`. Wrong for a **block**: branching to a block's
label EXITS the block, so every label from the target up must go (`lsp = lb`).
Only a **loop** keeps its label (`lsp = lb + 1`), because a backward branch
re-enters it. Distinguish by direction: target <= pc means backward/loop.

In a single frame the off-by-one was invisible — the function's own `end`
absorbed the stray label. Across a **call** it was fatal: the callee's
function-level `end` saw `lsp > lsp_base`, decremented instead of popping the
frame, and the interpreter fell out early. A caller loop calling a callee that
also loops returned **1** instead of 10.

Two related pieces landed with it, both required:
- `ltgt` is ONE shared buffer, so a callee must NOT reset `lsp = 0` — its labels
  stack above the caller's.
- therefore `end` cannot use `lsp > 0` to mean "block end". Frames now carry
  **`lsp_base`** (frame slot 4, widened 4->8 slots) and `end` tests
  `lsp > lsp_base`.

Took coverage 6/18 -> 7/18 (`wart_simple_bench` = 4037913 exact).

Note `wart_f32_bench`/`wart_f64_bench` moved to `nan` and `wart_mixed_type_bench`
to `-1` afterwards. That is not a regression: their loops now run to completion
instead of exiting early, so the previous near-looking numbers were partial sums.

## THE SILENT-ZERO BUG — read before adding any range arm

`i32.div_s/div_u/rem_s/rem_u` returned **0** for months. Not `-1`, not a crash:
**zero**, which looks like a plausible answer.

Cause: the hot-path arm matched `op >= OP_i32_add and op <= OP_i32_shr_u`, i.e.
**106-118**, which *swallows* 109-112. Its inner if/elseif chain has no arm for
them, so they fell through to the `r: i64 = 0` initializer and wrote 0 to the
stack. The dedicated div/rem arm further down was unreachable. `i32.shr_s` (117)
had the same fate.

Fixed by narrowing the range to `(106-108) or (113-118)` **and adding
`else return -1`** to the inner chain, so an opcode inside a range with no arm
now bails honestly instead of inventing a value. That single fix took verified
coverage from **4/18 to 6/18** (`wart_comprehensive_bench` 3985 and
`wart_opcode_test_simple` 22 both went green).

**Rule: every range arm needs a terminal `else return -1`.** A range that
silently yields 0 produces "executes but wrong", which is far more expensive to
find than an honest bail. Audit any new range arm for this.

**"the engine produced a result" is NOT coverage.** An earlier version of this harness
counted any non-sentinel result as a pass and reported **8/18**. A differential
check against wasmtime showed 2 of those were plain wrong and 1 was an f64 the
reporting path truncates. `bench/verify.id` is now the oracle; `bench/run.id` is
for timing only. Real score: **4 PASS, 3 DIFF, 9 UNSUPPORTED, 2 SKIP**.

| module | wasmtime | the engine | |
| --- | --- | --- | --- |
| `hash` | 1899277430 | 1899277430 | PASS |
| `wart_arithmetic_bench` | -1000001 | 4293967295 | PASS (signed vs unsigned print) |
| `wart_compute_bench` | 832040 | 832040 | PASS (fib 30) |
| `wart_simple` | 100 | 100 | PASS |
| `wart_f64_bench` | 1000100048462729.9 | 1929046707 | **DIFF** — f64 return truncated to 32 bits by `last & M32` |
| `wart_mixed_type_bench` | 537630237 | 832587187 | **DIFF** |
| `wart_simple_bench` | 4037913 | 1 | **DIFF** |

Note wasmtime prints i32 **signed** and the engine prints **unsigned**; `verify.sh`
folds both to unsigned 32-bit before comparing, so that is not a real mismatch.

**Return-type handling is FIXED** (`find_run_body(... , 2)` reports the target's
declared result type; `run_body` no longer masks with `M32`; the entry formats
f64 by bitcasting the bits back). `wart_f64_bench` went `1929046707` ->
`1000100019002752` against wasmtime's `1000100048462729.9` — the magnitude is
now right, so what remains is an **accumulation difference**, not truncation.
No perf regression: hash.wasm 0.457-0.464 s.

## f32 + f64 + i64 all execute now; correctness is the gate

f32 landed as a mirror of the f64 arm (`mem.load("f32", fb)` reads the low 4
bytes of the same scratch buffer). Result formatting is type-aware for f32
(0x7D), f64 (0x7C) and i64 (0x7E).

**The `which == 2` result-type lookup is CORRECT — verified.** For
`wart_f32_bench`, the engine reports f32 and `wasm-tools print` confirms
`(func (;3;) (type 1) (result f32))`. So when the engine and wasmtime disagree there,
it is **f32 arithmetic**, not the type plumbing. Do not re-debug the lookup.

Modules that went from `-1` (bail) to a wrong value — i.e. they now execute end
to end and need per-opcode differencing, which is a much better position:

| module | wasmtime | the engine |
| --- | --- | --- |
| `wart_f32_bench` | 29181774 | 1001001.875 |
| `wart_f64_bench` | 1000100048462729.9 | 1000100019002752 |
| `wart_opcode_test_simple` | 22 | 0 |
| `wart_mixed_type_bench` | 537630237 | 4794153070560822272 |
| `wart_simple_bench` | 4037913 | 1 |

`wart_f64_bench` is the closest — same magnitude, so one op in the chain drifts.
Bisect by building single-opcode .wat probes and differencing against wasmtime,
the way `/tmp/ftest.wat` validated f64 add/mul/sqrt/gt exactly (107 == 107).

**Next three bugs, in order:** (1) `wart_f64_bench`'s residual drift — every f64 op needs
checking against wasmtime individually, most likely a missing f32/f64
conversion silently taking a fallback; (2) `wart_simple_bench` returning 1 suggests a comparison/branch arm is wrong;
(3) `wart_mixed_type_bench` mixes i64/f64 and needs the i64 family finished.

**Ranked worklist** (opcode frequency across the 15 still-failing modules).
Floats dominate — they are the next unlock, not exotic opcodes:

| family | count | status |
| --- | --- | --- |
| `f64.const/add/mul/sub/div/abs` | ~80 | missing |
| `f32.const/add/mul` | ~63 | missing |
| `i64.const/add/extend_i32_s` | ~28 | partial |
| `i32.ge_u` / `gt_u` | ~19 | missing |
| `i32.load/store`, `global.get/set` | ~21 | partial |

`-1` means the engine genuinely could not execute it (unsupported opcode / stack
underflow). So the limiter is **opcode coverage**, not the decoder.

## Speed, on the one workload that stresses it — SUPERSEDED

| runtime | `hash.wasm` | re-measured 2026-08-08 |
| --- | --- | --- |
| the engine `jit-arm64` | **0.45 s** | 0.382 s |
| the engine `interp` | 5.26 s | **7.10 s** |
| wasmtime | **0.436 s** | 0.384 s |
| wart | **SIGILL** | runs, but cannot invoke `run` |

Note the interpreter went **backwards**, 5.26 s -> 7.10 s, while the JIT
improved. That is the cost of the dispatch growing from 20 opcodes to 170
hard-coded predicates on one `if`/`elseif` ladder, and it is the same fact the
derived-lines ratio is measuring from the other side.

## There is no local wart baseline — NO LONGER TRUE, see above

`wart` @ `bab0ea2` **SIGILLs on 17 of 18 modules in its own `bench/wasm/`
corpus** on this ARM64 Mac. `wart inspect`/`verify` work, so the decoder is fine
— the fault is JIT-emitted. Decoded from the crash report:

```
0xa8c17fff = ldp xzr, xzr, [sp], #16     (Rt == Rt2 == 31)
```

`Rt == Rt2` in LDP is UNPREDICTABLE and Apple silicon traps it — a function
epilogue where both destination registers were allocated as index 31. There is
no interpreter escape hatch (`--no-jit`/`--interp` are not real flags).

**Consequence: "beat wart" is not locally measurable. Use wasmtime as the
reference.** wart is READ-ONLY here; report this upstream rather than patching.

Also note: wart's `build.zig` rejects `-Doptimize`; use **`-Drelease=true`**.
`zig build ... | tail` hides the failure because `$status` then reads `tail`.

## Critical path

Opcode coverage, counted:

| layer | ops | re-counted 2026-08-08 |
| --- | --- | --- |
| `src/engine.id` — the binary that actually works | **20** | **184 opcodes, all projected**; 3 hard-coded predicates left, all false positives |
| `tools/wasm/tools/opcodes.id` — the engine's descriptor, new | — | 184 rows; answerable to duo's canonical 63 |
| `src/wasm/op.id` — separate 8398-line tree, not what builds | 151 | 162 lines, dead code |
| duo canonical descriptors (`duo wasm-tables emit`) | **63** | 63, unchanged |
| full spec (MVP + SIMD + bulk/ref + WASI/WASIX) | ~450+ | unchanged |

The 2026-08-06 note said the engine's 20 constants were a hand-copied subset of a
63-op subset, and that hand-writing the rest "across interpreter arms *and* JIT
emitters is the thing to avoid." **That is exactly what happened**, and it was
repaired the same day: the engine had grown to 170 distinct hard-coded opcode
numbers, only 19 of them behind a name, the other 151 bare integers inside
dispatch predicates. All 184 are now projected — see below.

### The projection landed, 2026-08-08

**`duo wasm-tables emit` is idempotent now.** It used to re-write
`lib/std/wasm/opcode_lookup.id` with `then`-keyword `if` bodies that Pass 100
§1 forbids, so the file could not be regenerated without failing the deny list
— eight lines, all in a Zig multiline literal in `src/wasm_semantic_gen.zig`.
Fixed there; two consecutive `duo wasm-tables emit` runs on a clean tree now
produce no diff. Positive-controlled: perturb the file first and the same
`git diff` check does fire, and the re-emit restores the canonical text.

**the engine's opcode dispatch is projected from a descriptor.**
`tools/opcodes.id` holds the table (184 opcodes, 24 ALU rows, 20 CMP rows)
and writes four `-- derived(wasm.opcodes.*)` regions into `src/engine.id`:

```
duo run tools/opcodes.id                     # project
DUO_WASM_DERIVE=1 duo run tools/opcodes.id # fail if src/engine.id drifted
```

It is not a second source of truth: it re-parses
`lib/std/wasm/ward_mvp_opcodes.id` and refuses to project on any disagreement
over the 63 opcodes duo's canonical table holds (it reports the count it
checked — 63 — so a parser that matched nothing cannot read as unanimous).
the engine needs 170, which is why the extension lives here. Both gates are
negative-controlled: perturbing a derived line makes `--check` fail, and
mis-typing an opcode in `tools/opcodes.id` makes the projection refuse.

363 numeric literals across 231 dispatch predicates became derived names.
`bail`/`bailop` now print the name too — `opcode 252 (prefix.fc)`, verified by
value against a `i32.trunc_sat_f32_s` probe — which is the ranked-worklist
signal a bare number never gave.

No conformance or speed cost: 43/44 on both engines before and after,
jit-compiled unchanged at 35/44, `hash.wasm` JIT 0.37 s both, `fib.wasm`
interp 0.63 s -> 0.59 s.

Two constraints still shape this, and both held:

1. The upstream generator is `src/wasm_semantic_gen.zig` — **Zig**, which
   collides with the standing "no zig no c only duo" directive. `tools/` is
   Duo; only the eight-word `then` fix touched the Zig.
2. Cross-file module embedding is still broken in duo, so the projection
   writes **into** `engine.id` rather than being required from it.
