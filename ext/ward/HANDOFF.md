# ward — handoff (2026-08-06, evening)

Everything below is **measured**, via `./bench/run.duo`. The previous handoff's
numbers were not reproducible; two separate "it passes the whole corpus" results
turned out to be the same measurement bug (see "The trap").

## State

`src/ward.duo` (1177 lines, pure Duo, zero `@c.emit`) **builds clean in ~1.0 s**:

```
duo compile src/ward.duo --backend=c --emit exe -o /tmp/ward
```

Every parser / hang / `#s` / boxing blocker from earlier handoffs is **resolved**.

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

## Measured coverage: 11/18 VERIFIED (11/16 of modules that have a wasmtime reference) (use bench/verify.duo)

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

## Speed, on the one workload that stresses it

| runtime | `hash.wasm` |
| --- | --- |
| ward `jit-arm64` | **0.45 s** |
| ward `interp` | 5.26 s |
| wasmtime | **0.436 s** |
| wart | **SIGILL** |

ward's JIT is ~3% behind wasmtime here. The interpreter runs ~38M iters/s.

## There is no local wart baseline

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

| layer | ops |
| --- | --- |
| `src/ward.duo` — the binary that actually works | **20** |
| `src/wasm/op.duo` — separate 8398-line tree, not what builds | 151 |
| duo canonical descriptors (`duo wasm-tables emit`) | **63** |
| full spec (MVP + SIMD + bulk/ref + WASI/WASIX) | ~450+ |

ward's 20 constants are a hand-copied subset of a 63-op subset. Hand-writing the
remaining ~430 across interpreter arms *and* JIT emitters is the thing to avoid.

**Next: project dispatch from one canonical table** via `@comp.define.derive`
rather than growing three hand-maintained copies. Two constraints:

1. The current generator is `src/wasm_semantic_gen.zig` — **Zig**, which
   collides with the standing "no zig no c only duo" directive. The table needs
   to move into Duo.
2. Cross-file module embedding is currently broken in duo, so the projection
   has to stay **single-file** inside `ward.duo` for now.
