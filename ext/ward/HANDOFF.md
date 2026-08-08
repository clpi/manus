# ward — handoff

Everything below is **measured**. The 2026-08-06 handoff's numbers were not
reproducible; two separate "it passes the whole corpus" results turned out to be
the same measurement bug (see "The trap"). Sections below the "state" block are
the bug lore from that session and are still accurate as CAUSES — the coverage
counts they quote (`8/18`, `11/18`) are superseded by the table here.

## State, re-measured 2026-08-08

Measured at `981b1f0`. `src/ward.duo` — 4976 lines, 4004 of them code; pure Duo,
zero `@c.emit` — builds clean in **~35 s** (the 2026-08-06 handoff's
"1177 lines / ~1.0 s" is four times out of date):

```
duo compile src/ward.duo --backend=c --emit exe -o /tmp/ward
```

**Conformance, `duo run bench/verify.duo` against wasmtime, 44 modules:**

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
grepped for in `src/ward.duo`: the only two hits (`4037913`, `70000`) are in
comments describing past bugs. `bench/wart.duo` regenerates the arbitrary-kernel
check on demand.

**Speed.** Interleaved, min-of-N wall clock. `bench/wart.duo` produces this
table; do not quote a number that did not come out of a harness.

| workload | ward JIT | wart | wasmtime | ward/wart |
| --- | ---: | ---: | ---: | ---: |
| 6 generated kernels, 100M iters | 205-229 ms | 203-211 ms | 190-200 ms | **103%** |
| FNV 200M (hand-written `.wat`) | 390 ms | 386 ms | 327 ms | **101%** |
| `bench/hash.wasm` `run` export | 388 ms | not reachable | 392 ms | — |
| `benchmarks/wasm_rt/hot_big.wasm` | 3400 ms (**interp**) | — | 119 ms | — |

So: **ward is ~1-3% slower than wart, not faster.** Pass 101 §4 asks for
measurably faster; that criterion is UNMET and `bench/wart.duo` exits non-zero
saying so. ward is at parity with wasmtime on `hash.wasm`, 19% behind it on the
same kernel written by hand, and **28x** behind it on `hot_big.wasm`, where the
JIT does not engage at all and ward falls back to the interpreter.

**Derived-lines ratio (Pass 101 §4, target >= 80%): `9%`** — was `0%` before
2026-08-08. Measured by `duo run bench/derived.duo`, which positive-controls
its own marker detection before reporting, because a scanner that reports 0 is
usually broken.

| | before | after |
| --- | ---: | ---: |
| shipped code lines | 4004 | 4365 |
| derived code lines | 0 | 418 |
| ratio | 0% | **9%** |
| hand-encoded opcode predicates | 241 | **3** |

The 3 are known false positives on a `f64op` width flag and are deliberately
left in as the scanner's floor: `bench/derived.duo` now FAILS if that count
reads below 3, because a detector tuned until it says 0 cannot be told apart
from a broken one.

**9%, not 80%.** The 80% criterion is still UNMET and the harness still exits
non-zero saying so. What closed is the population Pass 101 actually names —
opcode numbers hard-coded across the interpreter arms *and* the JIT emitters.
The remaining ~3900 hand-written lines are the interpreter and JIT *semantics*
(what each arm does), not format facts; projecting those is a rewrite, not a
table, and nothing here pretends otherwise.

Every parser / hang / `#s` / boxing blocker from earlier handoffs is **resolved**.

## `src/wasm/*.duo` is DEAD CODE — 1406 lines of it

`src/ward.duo` is self-contained: its only `req` is `std.jit`. Nothing in the
repo requires anything under `src/wasm/`, and the modules that used to
(`src/main.duo`, `src/cli.duo`, `src/wasm/runtime.duo`, `src/wasm/init.duo`)
were deleted. `test/main.duo` still requires `src.wasm`, `src.edge` and
`src.lib`, none of which exist, and it fails to parse besides — **ward has no
running test suite**; `bench/verify.duo` is doing that job.

This matters most for `src/wasm/jit_arm64.duo` (701 lines). It is the
**virtual-stack register-allocating JIT** landed in `55668dc` and written up in
`docs/performance.md` — `vs_pop` / `vs_alloc_not` / `flush_tos`, pinned locals
in x23..x28. It is a genuinely more advanced code generator than the one that
ships, and it is unreachable: its host modules are gone. The shipping JIT is
`jit_compile` inside `src/ward.duo` (lines 2712-4418, 1366 code lines), which
tracks two register aliases and has no liveness model.

**Do not treat `docs/performance.md`'s ward numbers as this ward's numbers.**
Its `hot_big` table (ward JIT 0.21 s, "beats wasm3 by 2.2x and iwasm by 2.0x")
was produced by that deleted architecture. Re-run today against the shipping
binary: ward **3.4 s on the interpreter**, wasm3 0.77 s, iwasm 0.74 s,
wasmtime 0.12 s — ward is **4.5x slower than wasm3**, the opposite of the claim.
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
ward-vs-wart row built on the other 42 is timing two runtimes with no evidence
either computed the right thing.

`bench/wart.duo` is the repair: generate the kernel, ask wasmtime for the value,
then emit a second module whose `_start` traps unless the value matches. wart's
exit status becomes a value check and ward's `-1` bail becomes one too. It
runs a deliberately-wrong assert first and refuses to report if either runtime
accepts it.

## The trap that invalidated two benchmark sweeps

ward does **not read argv** — duo-compiled binaries don't populate Lua's `arg`
(verified with a 10-line repro: `arg is nil`). ward reads `WARD_WASM`, and it
used to default to a hardcoded `/tmp/hash.wasm`, which existed on the dev box.

So `ward some_module.wasm` ran **`/tmp/hash.wasm`** and printed a correct-looking
`result=1899277430` — for a nonexistent path, and for `/dev/urandom` garbage. A
whole 18-module sweep came back "100% passing" that way.

**Fixed this session.** No default module; missing `WARD_WASM` is now an error.
Always drive ward as:

```
WARD_WASM=<abs path> WARD_INVOKE=<export> WARD_ENGINE=jit|interp  ward
```

## Also fixed this session

- **Export name is selectable.** `find_run_body` hardcoded a byte compare
  against `r`,`u`,`n`. It now matches `WARD_INVOKE` (default `run`), which is
  what makes the `_start`-exporting wart corpus reachable at all.
- **Removed the "largest body" fallback.** When no export matched, ward picked
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
grep -n 'mem.write_i64(st, (sp - 1)' src/ward.duo   # then check each for a
                                                    # preceding `sp -= 1`
```

Symptom to remember: **a binop returning its first operand** means the result
write missed the slot, not that the operator is wrong.

## THE HARDCODED GLOBAL 0

ward never parsed the **global section**. It unconditionally did

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

**"ward produced a result" is NOT coverage.** An earlier version of this harness
counted any non-sentinel result as a pass and reported **8/18**. A differential
check against wasmtime showed 2 of those were plain wrong and 1 was an f64 the
reporting path truncates. `bench/verify.duo` is now the oracle; `bench/run.duo` is
for timing only. Real score: **4 PASS, 3 DIFF, 9 UNSUPPORTED, 2 SKIP**.

| module | wasmtime | ward | |
| --- | --- | --- | --- |
| `hash` | 1899277430 | 1899277430 | PASS |
| `wart_arithmetic_bench` | -1000001 | 4293967295 | PASS (signed vs unsigned print) |
| `wart_compute_bench` | 832040 | 832040 | PASS (fib 30) |
| `wart_simple` | 100 | 100 | PASS |
| `wart_f64_bench` | 1000100048462729.9 | 1929046707 | **DIFF** — f64 return truncated to 32 bits by `last & M32` |
| `wart_mixed_type_bench` | 537630237 | 832587187 | **DIFF** |
| `wart_simple_bench` | 4037913 | 1 | **DIFF** |

Note wasmtime prints i32 **signed** and ward prints **unsigned**; `verify.sh`
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
`wart_f32_bench`, ward reports f32 and `wasm-tools print` confirms
`(func (;3;) (type 1) (result f32))`. So when ward and wasmtime disagree there,
it is **f32 arithmetic**, not the type plumbing. Do not re-debug the lookup.

Modules that went from `-1` (bail) to a wrong value — i.e. they now execute end
to end and need per-opcode differencing, which is a much better position:

| module | wasmtime | ward |
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

`-1` means ward genuinely could not execute it (unsupported opcode / stack
underflow). So the limiter is **opcode coverage**, not the decoder.

## Speed, on the one workload that stresses it — SUPERSEDED

| runtime | `hash.wasm` | re-measured 2026-08-08 |
| --- | --- | --- |
| ward `jit-arm64` | **0.45 s** | 0.382 s |
| ward `interp` | 5.26 s | **7.10 s** |
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
| `src/ward.duo` — the binary that actually works | **20** | **184 opcodes, all projected**; 3 hard-coded predicates left, all false positives |
| `ext/ward/tools/opcodes.duo` — ward's descriptor, new | — | 184 rows; answerable to duo's canonical 63 |
| `src/wasm/op.duo` — separate 8398-line tree, not what builds | 151 | 162 lines, dead code |
| duo canonical descriptors (`duo wasm-tables emit`) | **63** | 63, unchanged |
| full spec (MVP + SIMD + bulk/ref + WASI/WASIX) | ~450+ | unchanged |

The 2026-08-06 note said ward's 20 constants were a hand-copied subset of a
63-op subset, and that hand-writing the rest "across interpreter arms *and* JIT
emitters is the thing to avoid." **That is exactly what happened**, and it was
repaired the same day: ward had grown to 170 distinct hard-coded opcode
numbers, only 19 of them behind a name, the other 151 bare integers inside
dispatch predicates. All 184 are now projected — see below.

### The projection landed, 2026-08-08

**`duo wasm-tables emit` is idempotent now.** It used to re-write
`lib/std/wasm/opcode_lookup.duo` with `then`-keyword `if` bodies that Pass 100
§1 forbids, so the file could not be regenerated without failing the deny list
— eight lines, all in a Zig multiline literal in `src/wasm_semantic_gen.zig`.
Fixed there; two consecutive `duo wasm-tables emit` runs on a clean tree now
produce no diff. Positive-controlled: perturb the file first and the same
`git diff` check does fire, and the re-emit restores the canonical text.

**ward's opcode dispatch is projected from a descriptor.**
`tools/opcodes.duo` holds the table (184 opcodes, 24 ALU rows, 20 CMP rows)
and writes four `-- derived(ward.opcodes.*)` regions into `src/ward.duo`:

```
duo run tools/opcodes.duo                     # project
WARD_DERIVE_CHECK=1 duo run tools/opcodes.duo # fail if src/ward.duo drifted
```

It is not a second source of truth: it re-parses
`lib/std/wasm/ward_mvp_opcodes.duo` and refuses to project on any disagreement
over the 63 opcodes duo's canonical table holds (it reports the count it
checked — 63 — so a parser that matched nothing cannot read as unanimous).
ward needs 170, which is why the extension lives here. Both gates are
negative-controlled: perturbing a derived line makes `--check` fail, and
mis-typing an opcode in `tools/opcodes.duo` makes the projection refuse.

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
   writes **into** `ward.duo` rather than being required from it.
