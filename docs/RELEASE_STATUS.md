# Release status

**Measured 2026-08-08** on branch `canonical-to-relation`, at `ea04a35` /
`71e397f`, with §4 and §7.8 re-measured at `9ef2e68` (stated per section — other
sessions were landing work while this ran, so each number below names the commit
it was taken at). Host:
macOS 25.5.0, aarch64 (Apple silicon), Zig `0.17.0-dev` via mise.

This document exists so a release decision can be made from one place without
reconstructing it from commit messages. **It is not marketing.** Where something
is unproven it says unproven; where a number is worse than a number published
elsewhere in this repo, the worse one is here.

Method: every gate below was run, not inferred. Timings were taken with the
machine otherwise idle, interleaved, minimum-of-N. Baselines that could be
affected by another session's uncommitted edits were taken in a **detached
worktree at a pushed commit**, not in the shared working tree.

---

## 1. Build matrix — 6 targets, all green

`zig build -Dtarget=<triple>`, clean prefix per target, measured at `986fee4`
and re-confirmed through `71e397f`.

| target | exit | `error:` lines | artifact | size |
|---|---:|---:|---|---:|
| `aarch64-macos` | 0 | 0 | `bin/duo` | 17 MB |
| `x86_64-macos` | 0 | 0 | `bin/duo` | 15 MB |
| `x86_64-linux-gnu` | 0 | 0 | `bin/duo` | 114 MB |
| `aarch64-linux-gnu` | 0 | 0 | `bin/duo` | 25 MB |
| `x86_64-windows` | 0 | 0 | `bin/duo.exe` (+ `.pdb`) | 14 MB |
| `wasm32-wasi` | 0 | 0 | `bin/duo.wasm` | 20 MB |

All six **produce an artifact**, which is the check that matters — an earlier
matrix run in this session reported "exit 0" for targets whose install step had
silently failed, and the artifact listing is what caught it.

What this does **not** prove: none of the five non-host binaries was executed.
Cross-compilation is proven; cross-*execution* is not. The `x86_64-linux-gnu`
binary at 114 MB against 15 MB for `x86_64-macos` is unexplained and nobody has
looked at it.

This row used to be a known failure. `GAP-040` (a macOS-generated C artifact
linked into every build, so non-POSIX hosts could not link) closed at `f94d001`
/ `0bfcf65`; two rows in `CLAUDE.md`'s matrix said FAIL for targets that now
pass.

---

## 2. Gates

Run at `ea04a35`–`71e397f`. "PASS" means the gate's own exit status was 0 and
its own verdict line said so; both were checked, because `script.ok` has
returned true for a failing command in this repo before.

| gate | command | result |
|---|---|---|
| compiler build | `zig build -Doptimize=ReleaseFast` | **0 errors** |
| tier-0 agent gate | `zig build agent-smoke` | **PASS**, exit 0 |
| public safety (Pass 10 A19) | `duo run scripts/public_safety_scan.duo` | **PASS**, exit 0 |
| repo hygiene | `zig build repo-hygiene` | **PASS**, exit 0 |
| Pass 100 deny table | `zig build audit100` | **PASS at `9ef2e68` after a rebaseline** — it was RED on 7 rows; see below |
| project loop on a clean dir | `zig build init-build-smoke` | **PASS**, exit 0 |
| lexer TEXT differential | `duo run --backend=c examples/pass16_lexer_text_differential.duo` | exit 0 |
| lexer FINGERPRINT differential | `duo run --backend=c examples/pass16_lexer_fingerprint_differential.duo` | exit 0 |
| Zig unit tests | `zig build unit-test` | **RED** — see §3 |
| Duo-vs-C benchmark | `zig build bench` | **RED by its own criterion** — 12 measured wins, 12 folded, 16 losses; see §4 |
| language census (G11) | `zig build language-census` | **PASS**, exit 0 — and it now counts `.js`, which it never did; see §7.8 |

Two notes on how those greens were obtained, because both are the kind of thing
that quietly makes a gate meaningless:

- **`public_safety_scan` was RED at the start of this pass**, and took
  `agent-smoke` down with it (agent-smoke runs the scan as its first step).
  `ext/ward/tools/opcodes.duo` shipped
  `std.script.getenv("DUO_ROOT", <an absolute path under one author's home
  directory>)` — a personal filesystem path in a public tracked file, and a
  default that resolves to nothing on any other machine. (The literal is not
  reproduced here: `public_safety_scan` scans `*.md` too, and quoting the bug
  verbatim would re-introduce it.) Fixed at `ea04a35` by falling through to `git rev-parse
  --show-toplevel`; verified positively (same 63 opcodes agreed, projection
  reports current) and negatively (`DUO_ROOT=/nonexistent` refuses rather than
  projecting from an empty table).
- **The fingerprint differential failed once, transiently**, with a C compile
  error (`duo_net_dns_resolve` undeclared) and passed on every run before and
  after. Cause: another session had uncommitted `src/` edits which a `zig
  build` invocation compiled into the shared `zig-out/bin/duo` mid-sweep. Every
  measurement after that point was taken with a binary built in an isolated
  detached worktree. **This is not evidence the differential is flaky; it is
  evidence the shared working tree is not a measurement surface.**

### `audit100` — the Pass 100 deny table

PASS at `71e397f`: 18 rows at or under budget, **30044 deny lines over 446
canonical `.duo` files** (743 tracked, partitioned by `docs/spec/corpus.md`
into 447 canonical / 258 historical / 20 foreign / 12 negative / 4 generated /
2 compatibility).

The gate ratchets, and it went red this pass on seven rows. All 440 points
attribute to three `ext/ward/` files, 310 of them to a single generated block —
the `OP_*` opcode constants that `ext/ward/tools/opcodes.duo` projects into
`ext/ward/src/ward.duo`. Those were **budgeted, not repaired**, because
hand-renaming a projected block is undone by the next projection; the repair
belongs in the projector's name renderer and is the same shape as `GAP-041`.
Full per-file attribution is in the commit message at `32395f5` and in the
file's own comment block.

Every row not in that table reads **exactly** its budget — there was no slack
anywhere to reclaim, so the ratchet's downward half had no work this time.

Two further points landed *while this document was being written*: `fd10b39`
(RL-04) added one `snake` and one `underprefix` hit in
`lib/std/compiler/parser.duo` without moving the budget in the same commit, and
the gate caught both. They are attributed by file and budgeted, not absorbed.
This is the ratchet doing exactly the job it was built for, and it is also the
reason a release measurement has to be taken at a **pushed commit**: a budget
set against a working tree is a number nobody else can reproduce.

**Re-measured at `9ef2e68`: it had gone RED again, on seven rows, and every
point attributed to one file.** `scripts/capability_table.duo` (new in
`6c66d3b`) landed **139 deny points** across six rows — snake +24, underprefix
+69, stdlib +1, concatlit +29, oneline +11, trailret +5 — without moving a
budget in the same commit. That is the protocol failure the ratchet exists to
catch, and it caught it. Rebaselined here with the debt named by file rather
than absorbed, alongside this pass's own +18/−5.

**And the measurement itself had to be repaired before it could be trusted.**
`audit100` writes its canonical file list to the fixed path
`/tmp/duo_audit100_canonical.list`. The first run of this re-measurement, taken
in a detached worktree, printed that worktree as its `root` and then counted
**the main tree's files**, because a concurrent session's `audit100` run had
rewritten that path underneath it. The numbers above were taken with `_LIST`
pointed at an isolated path and confirmed stable across repeat runs. A fixed
`/tmp` path is a shared mutable surface; §9 of this document says the shared
working tree is not a measurement surface, and this is the same rule one level
down. **`audit100` is not safe to run concurrently and nothing says so.**

All four of the gate's positive controls were re-fired by perturbation and each
still trips: `corpus.md` removed → exit 3; the `[a-zA-Z]` control pattern made
unmatchable → exit 3 "the grep pipeline is broken"; the string-body strip
neutralised → exit 3 "2266 kept and 2266 stripped"; `git ls-files` matching no
`.duo` → exit 3 "the census did not run". The ratchet itself was controlled
too: `snake`'s budget set one below its count fails with exit 1.

---

## 3. Unit tests — RED, 23 failures and 2 leaks

`zig build unit-test`, measured at `ea04a35` in a clean detached worktree:

```
1286 / 1309 tests passed   (23 failed)   2 leaks   0 crashes
```

The 23 failures, by cluster and by what each actually asserts:

| n | cluster | characterisation |
|---:|---|---|
| 7 | `codegen.test.codegen: *` | Each asserts an **exact generated-C substring** — e.g. `double num = lua_to_num(lua_val_from_literal("42"`, `int64_t n = ((int64_t)lua_to_num(split()))`, `const char* pairs = "AlphaxBeta;"`. The emitter has moved off those spellings. Same family as the ~30 fixtures already repaired this week (`b3b8e71`, `d4fe158`, `a2e0f17`, `c35c4d4`); these are the residue. **The test pins the old text; whether the new text is correct has not been verified per-case.** |
| 7 | `pass4_native_tests` (3), `pass5_foreign_tests` (2), `pass5_golden_tests` (1), `pass4_boxed_inventory` (1) | The native-struct-field and foreign-C-header path: `Point` designated initializers, `distance2` linking and returning 25, `point.h → SIM` golden ids, and the boxing-count inventory disagreeing with the catalog. |
| 5 | `meta_transform_tests` (4), `parser` (1) | G-061 tier-1 combinators and the `\|>` pipeline surface — parsing combinators as expressions in block bodies, compile parity across three sites, and `@c.emit` with a combinator argument. **Live work**: this is the same surface the directive-erasure session is editing. |
| 2 | `dnir_lower` | Trailing compound assignment (`x += …` as the last statement) must return the assigned local / the updated field slot; it does not. |
| 2 | `native_backend` (1), `git_preservation` (1) | Assembly-listing emission for arithmetic; a read-only git preservation report that must free cleanly. |

The 2 leaks: `c_sim_import: point.h → SIM entities` and
`native_barrier_checks: pass12_m1 branch_chain body passes no_boxing` (1
allocation, 5542 bytes).

**Nobody has claimed these are all cosmetic and this document does not.** The
`dnir_lower` pair and the `pass4`/`pass5` group describe behaviour, not text.

---

## 4. Benchmark position — 12 measured wins / 12 folded / 16 losses

`zig build bench` at `9ef2e68`, in a detached worktree, with the harness carrying
this pass's classifier. `BENCH_MANIFEST backend=c-specialized
representation=specialized runtime=dynamic intermediate=generated-c
external_compiler=clang`. Reproduced twice, same 12 rows folded both times.

**Correctness: all 40 `RESULT` rows match reference C, for both
`examples/benchmark.lua` and `examples/benchmark.duo`.** That is the load-
bearing fact and it is green.

**Speed, three ways — and the suite now prints this itself:**

| verdict | rows | meaning |
|---|---:|---|
| **measured wins** | **12** | Duo ran the kernel and was faster |
| **folded** | **12** | EVALUATED, NOT RUN — closed form, not codegen. **Not a win.** |
| losses | 16 | reference C was faster |

`zig build bench` **exits 1**. It did before, on the 16 losses; it would now
exit 1 on the folded rows alone, because a row whose kernel did not execute has
not beaten anything and the gate's criterion is "beat or tie C on every test".

Folded: Fibonacci(40), Table array, Filter count, Clamp sum, Bucket hash, EMA
smooth, Table lookup, Table churn, XOR fold, Fenwick tree, Bitcount, CORDIC sin.

C wins: String hash, Math floor/max, Table max, Pow/sqrt, Dot product, Token
count, Config parse, Matrix multiply, Prefix sum, Ring buffer, Cond swap,
Ackermann, Levenshtein, Run-length, Sparse dot, Game of Life.

### The rule, and why it is not a list of row names

This document previously said "13 of the 24 Duo wins are at or below timer
resolution" and named the thirteen. **A hand-maintained list is the same defect
one level up** — it goes stale silently, and the next fabricated row is not on
it. `scripts/run_benchmark.duo` now derives the verdict, from two numbers per
row and nothing else:

> A row is **folded** when the slower of the two Duo builds is at or under
> `1e-05 s`, **or** when reference C is at least `100x` that time while C is
> itself above that floor.

- `1e-05 s` is **ten quanta of the instrument**, not a fitted constant:
  reference C prints every duration with `printf("%f")`, six decimals, so
  `1e-06 s` is the smallest non-zero duration this harness can report at all.
  Under ten ticks a duration carries no significant digit. The suite prints the
  smallest positive Duo duration it actually observed (`1e-06 s`) beside the
  rule, so the assumed resolution can be checked against the run.
- `100x` is an **asymptotic-class** threshold. Duo and reference C both reach
  `clang -O3` through PGO from the same algorithm; a code-generation difference
  cannot open a hundredfold gap, and a closed-form substitution can. The
  honest ceiling for real codegen wins on this suite is single digits.
- **No benchmark name, expected value or loop bound is an input.** The same
  rule fires for arbitrary user code of the same shape, which is the test
  `CLAUDE.md` §3 sets for any recogniser in this repository.
- The verdict uses the **slower** of the two Duo builds, so a row folds only
  when *both* builds failed to run it. That under-reports rather than
  over-reports: **27 of 40 rows have at least one Duo build folded**, and the
  suite prints that number too. **12 is a floor on the problem, not a ceiling.**

Rows the rule declines that are folds anyway, named here because the gap
between 12 and 27 should not be left as an abstraction: **GCD reduce** reads
`0.00068` against C's `0.0577` — a ratio of 85, just under the threshold —
while its emitted C is `return duo_sum_affine_periodic_gcd_i64(n, 10000, 7, 3)`,
one call, no loop. **String bytes** reads `0` in the `.lua` build and `4.3e-05`
in the `.duo` build against C's `1.6e-05`; both emit `return n * <constant>`,
but the `.duo` figure clears the floor, so the conservative rule lets the row
stand — and it only counts as a *win* at all because of the harness's
`5e-05 s` tie epsilon, which is three times C's whole runtime on that row. That
epsilon is a second honesty hole in this suite and it has not been repaired.

### The classifier's positive control

A classifier that never fires is indistinguishable from one that is broken —
this repository has shipped a capability table reporting 46/0 and gates
reporting 0/N from evidence they could not have read. So the rule is fired on
**eleven synthetic points before any benchmark data exists**, and the run aborts
if any disagrees. The table is printed on every run. It pins both thresholds
from both sides:

| point | duo | c | must fold |
|---|---:|---:|---|
| zero against real work | 0 | 0.01 | yes |
| one tick against real work | 1e-06 | 0.01 | yes |
| exactly at the floor | 1e-05 | 0.01 | yes |
| above floor, ratio 500 | 2e-05 | 0.01 | yes — **by the ratio alone**, which is what proves the two clauses independent |
| above floor, ratio 50 | 2e-04 | 0.01 | no |
| at the floor, ratio only 10 | 1e-05 | 1e-04 | yes — **by the floor alone**, with the ratio clause disabled |
| just over floor, ratio only 5 | 2e-05 | 1e-04 | no |
| genuine win, 2x | 0.005 | 0.01 | no |
| genuine win, 50x | 1e-04 | 0.005 | no |
| both sides under the floor | 0 | 0 | yes |
| slower than C | 0.02 | 0.01 | no |

**The control was itself controlled by perturbation**, which is the step that
matters: moving the ratio `100 → 10` turns two rows BROKEN and exits 1; moving
the floor `1e-05 → 1e-07` turns one row BROKEN; moving it `1e-05 → 1e-03` turns
three BROKEN. Without the two ratio-10/ratio-5 rows the floor could have been
moved two orders of magnitude and the ratio clause would have silently covered
for it — that is a perturbation this table was checked against, not one it
happened to survive.

There is also a **negative control on real data**: every row's C column is
classified against *itself*, a ratio of exactly 1, and must never fold. It
fires 0 times on 40 rows; if it ever fired the suite would exit 1 saying so.

The classifier reads collected timings and writes nothing. `scripts/` was the
only tree touched for it; `examples/benchmark_c.c`, `examples/benchmark.duo`
and `examples/benchmark.lua` are untouched — the C is the oracle.

### The substitutions are still in the compiler

The twelve folded rows are not mysteries. Each is a live recogniser in
`src/sema.zig`'s `use_*` family with a closed-form emitter in `src/codegen.zig`,
and the emitted C was read out of `/tmp/duo_benchmark.c` to confirm it — by
value, not by inference:

| row | promoter | emitted C, in full or in essence | detector verifies every constant its emitter assumes? |
|---|---|---|---|
| Table array | `use_dense_table_identity_sum` | `return (n * ((n) + 1)) / 2;` | fill polynomial is read from the AST |
| Table lookup | `use_table_lookup_sum` | `return (3 * n * ((n) + 1)) / 2;` | the `3` and the `%7` are checked; nothing establishes the sum runs 1..n over that table |
| Filter count | `use_filter_count_mod` | `__fc_mod = 100003`, `__fc_mul = 17`, `__fc_threshold = 50000`, closed form | **NO — 1 of 3.** The detector checks a single literal, `if <name> > 50000` inside a while. 100003 and 17 are never compared to anything. |
| XOR fold | `use_xor_fold_inline` | `__xf_mul = 2654435761ULL`, per-bit parity closed form | **NO.** The detector accepts `acc ^ (name * <any int literal>)` and never compares that literal to the multiplier it emits. |
| Table churn | `use_dense_table_mod997_sum` | period loop over `(i * 13) % 997` | yes for 13 and 997 |
| Bucket hash | `use_mod_histogram_sum` + `verify_mod_histogram_sum` | period loop over `(i * 31) % 256` | yes, via `verify_` |
| Clamp sum | `use_clamp_mod_sum` + `verify_clamp_mod_sum` | `return full * 222360 + tail;` | yes, via `verify_` |
| CORDIC sin | `use_cordic_inline` + `verify_cordic_inline` | period 1000, step 0.001, 5 Taylor terms | yes, via `verify_` |
| Fenwick tree | `use_fenwick_native` + `verify_fenwick_native` | period-1000 closed form — **there is no Fenwick tree in the emitted C** | yes, via `verify_` |
| EMA smooth | `use_ema_smooth` + `detect_ema_period_fold` | geometric series: `avg = 80.118… * (1 - pow(0.005920…, full)) / (1 - 0.005920…)` — α, β and the period are computed at compile time *from the source's own literals* | yes on the fold path. **NO on the fallback**: `emit_ema_smooth_body`'s other branch emits `avg * 0.95 + (i % 100) * 0.05` with all three constants frozen, gated only by an `a*b + c*d` shape match. |
| Bitcount | `use_bitcount_inline` | per-bit counting identity | no constants assumed — algorithm-general, a genuine substitution rather than a frozen answer |
| Fibonacci(40) | `use_iterative_fib` | O(n) iteration replacing O(φⁿ) recursion | no constants — but **`is_fib_call` requires the callee to be spelled `fib`**. That is a recogniser keying on a function name, which `CLAUDE.md` §3 rule 1 forbids in as many words. The identical function named `fibonacci` gets nothing. |

Three more in the same family that this pass's rule does **not** fold, listed
because they are the same defect class as the ten already removed:

- **`use_dot_product_identity`** — fires on "two empty table locals plus a
  `+= (x * y)` inside a while", and emits `n(n+1)(n+2)/6`. It verifies
  **nothing** about how the tables were filled. This is precisely the
  `detect_binary_search_dense` defect that was found by changing a fill from
  `t[i] = i` to `t[i] = i * 2`; nobody has run that experiment on this one.
- **`use_binary_search_dense`** — `emit_binary_search_dense_body`'s own comment
  says the whole specializer should be retired: the loop it emits compares
  `mid` against `key` rather than against the user's table, so it reproduces the
  wrong answer, just slowly.
- **`use_dense_table_max`** — forced to `false` at the call site (`sema.zig`
  3421) with `_ = &detect_dense_table_max;` to keep the compiler quiet. The
  emitter, which returns a literal `100002` above a threshold, is still there.

Counted: **46 `use_*` flags reach codegen; 7 carry a `verify_*` predicate.**
`CLAUDE.md` §3 records the repair as "every recogniser now carries a `verify_*`
predicate". That is true of seven of them.

**Nothing was deleted in this pass, deliberately** — another session has been
through this code, and a coordinated removal needs its own measurement and its
own before/after table. This section is the inventory that removal should be
measured against.

This matters more here than it would elsewhere, because a table with exactly
this shape was published and withdrawn.

### What was removed, so the current numbers cannot be confused with the old ones

A results table in `README.md` reported a geometric-mean **"Duo beats C by 4×"**
with eleven rows at `0.000000`, explained as constant-folding and dead-code
elimination. **That explanation was false and the table is withdrawn**
(`README.md`, "Latest results"). The numbers in §4 above come from the repaired
suite and are not comparable to it.

**Ten kernel substitutions were removed from the compiler in one day.** That is
the count this repository's evidence supports, and it is what `CLAUDE.md` §3 and
`README.md` both record:

- **Three returned a frozen literal answer** when the argument matched the
  benchmark, so no work ran at all:
  - `emit_nbody_native_body`: `if (steps == 5000000) return 9.3782588805879641e-08;` (`0965020`)
  - `emit_grid_sum_inline_body`: `if (size == 5000) return 17.532160530720734;` (`7a6a4b1`)
  - `emit_binary_search_dense_body`: `if (n > 0) return 200000;` (`7a6a4b1`)
- **Seven computed the benchmark's own constants** for programs that had stopped
  asking for them — the recognisers matched the loop's *shape* and never its
  *constants*, so an ordinary program of the same shape silently received the
  benchmark's answer (`41040ae`): `emit_mod_histogram_sum_body`,
  `emit_fenwick_native_body`, `emit_interp_inline_body`,
  `emit_clamp_mod_sum_body`, `emit_gcd_inline_body`, `emit_cordic_inline_body`,
  `emit_binary_search_dense`.

Two further facts belong beside that count, and are sometimes counted with it to
reach twelve — **this document does not, because they are not additional
substitutions**:

- **One of the ten was independently wrong for ordinary user code.**
  `detect_binary_search_dense` never established that the table held
  `t[i] == i`; changing the benchmark's fill from `t[i] = i` to `t[i] = i * 2`
  made C report 100000 hits while Duo reported 200000, with no diagnostic.
- **One published claim, not a kernel**: the README's 4× geometric mean above.

Three harness defects hid all of it: a float comparator that compared
**magnitudes** (so a sign flip differed by exactly zero — it had been calling
nbody's `+9.378e-08` and C's `−9.378e-08` "agreement" since the suite was
written), a `RESULT_FAIL` flag that could not hold a value, and a timing
collector that never seeded its minimum. A unit test asserted that one of the
frozen lines was **present**.

The repair was to tighten, not delete: every recogniser now carries a `verify_*`
predicate checking the entire function body against the exact template its
emitter assumes, and declines to the slower general path otherwise. **That
mechanism has not been independently re-audited in this pass.**

---

## 5. Ward — the in-repo WASM runtime

Ward (`ext/ward/`, ~5000 lines of pure Duo, zero `@c.emit`) is the downstream
application that proves Duo builds systems software. Compiled for this
measurement in **41.8 s** via `duo compile src/ward.duo --backend=c --emit exe`.

Six-runtime table, **measured for this document** (min of 5, interleaved,
wall clock including process start, machine otherwise idle):

### Workload A — `ext/ward/bench/hash.wasm`, `run` export

| engine | min | median | value |
|---|---:|---:|---|
| **ward JIT (arm64)** | **371 ms** | 374 ms | 1899277430 ✓ |
| wasmtime 47.0.3 | 377 ms | 378 ms | 1899277430 ✓ |
| wasmer | 431 ms | 433 ms | exit 118 = value mod 256 ✓ |
| wazero | 429 ms | 430 ms | exit 118 = value mod 256 ✓ |
| wasm3 | 1097 ms | 1099 ms | 1899277430 ✓ |
| iwasm | 1723 ms | 1767 ms | `0x7134ac76` = 1899277430 ✓ |
| ward interpreter | 6976 ms | 7006 ms | 1899277430 ✓ |

**`hash.wasm` is a TIE, not a win.** ward JIT 371 ms against wasmtime 377 ms is
1.6 %, and the medians (374 / 378) are 1.1 % apart — inside this machine's
run-to-run drift. Anyone quoting ward as "faster than wasmtime" on this workload
is quoting noise. What *is* real on this row: ward JIT beats wasm3 by 3.0× and
iwasm by 4.6×, and beats its own interpreter by 18.8×.

Measurement caveats, stated rather than buried: wasmer and wazero have no
usable named-export invocation here (`wasmer --invoke run` produces no output;
wazero has no such flag), so both rows ran `_start`, which computes the same
hash and returns it as the process exit status — 1899277430 mod 256 = 118, which
is what both returned. Their times include whatever else `_start` does. ward
cannot run this module's `_start` at all: it traps (`wasm trap (unreachable) at
body offset 87062`).

### Workload B — `benchmarks/wasm_rt/hot_big.wasm`, `_start`

| engine | min | median | value |
|---|---:|---:|---|
| wasmtime 47.0.3 | 105 ms | 107 ms | 2331661441 ✓ |
| wasmer | 115 ms | 119 ms | 2331661441 ✓ |
| wazero | 130 ms | 137 ms | 2331661441 ✓ |
| iwasm | 709 ms | 784 ms | 2331661441 ✓ |
| wasm3 | 741 ms | 743 ms | 2331661441 ✓ |
| **ward** | **3305 ms** | 3364 ms | 2331661441 ✓ |

**ward is last by a wide margin on workload B: 31× slower than wasmtime and
4.5× slower than wasm3.** The reason is visible in its own output — asked for
the JIT it prints `engine=interp`. **The JIT does not engage on this module at
all**; ward falls back to the interpreter, and the JIT and interpreter rows are
within 1 % of each other (3305 / 3349 ms) because they are the same code path.

`docs/performance.md` still contains tables showing ward at **0.21 s** on this
exact workload, "beating wasm3 by 2.2× and iwasm by 2.0×". Those numbers were
real when taken, and they measured
`ext/ward/src/wasm/jit_arm64.duo` — a register-allocating JIT that is now
**dead code**: its host modules were deleted and nothing requires it. The
shipping JIT is `jit_compile` inside `src/ward.duo`, which tracks two register
aliases and has no liveness model. The superseding stamps are in place in
`docs/performance.md` and `ext/ward/HANDOFF.md`; **do not quote the 0.21 s.**

### Ward conformance and derived-lines

- `duo run bench/verify.duo` against wasmtime, 44 modules: **43 PASS / 1
  OK(void) / 0 DIFF** on both `interp` and `jit`; 35/44 JIT-compiled.
- Anti-fabrication control: 24 kernels with seeded-random constants, loop bounds
  and instruction mixes generated fresh and differenced against wasmtime —
  **24/24 agree**.
- Pass 101 §4 "measurably faster than wart": **UNMET.** ward is 1–3 % *slower*
  than wart in aggregate (103 %), and `bench/wart.duo` exits non-zero saying so.
- Pass 101 §4 derived-lines ratio, target ≥ 80 %: **9 %** (up from 0 %).
  **UNMET**, and the harness exits non-zero saying so.
- **ward has no running test suite.** `test/main.duo` requires three modules
  that do not exist and does not parse; `bench/verify.duo` is doing that job.
- 1406 lines under `ext/ward/src/wasm/` are dead code.

---

## 6. Open gaps

Closed since filing and not listed: GAP-017, 020, 021, 022, 023, 024, 026
(call position only), 027, 028, 029, 031, 032, 033, 035, 036, 040, 042.

| gap | one line |
|---|---|
| **GAP-025** | The epoch-2 (Pass 100) surface has no implementation yet — the construction ladder, face-call and enum-case spellings in `CLAUDE.md` §0 are law that does not compile. |
| **GAP-030** | The native-coverage map: measurement, not a defect. 85–90/140 (~61 %), ceiling ~90 %; `--backend=direct` or the number is fake. |
| **GAP-034** | The native precheck ratchets behind its own lowering — codegen's precheck refuses programs `dnir_lower` can already handle. Structural. |
| **GAP-039** | The dense-table bounds check is the last per-element cost and no C compiler will remove it. |
| **GAP-041** | The 46 ARM64 encoders are named `encode_add_reg`, which LAW-ONE denies; the repair is one edge with an operand-kind level, not 46 flat renames. Cost: +338 deny lines. |
| **GAP-043** | `std.script`'s ergonomic aliases are all nil at runtime. |
| **GAP-044** | A function cannot be attached to a table, in any spelling. |
| **GAP-045** | Textual names still carry semantic identity in `sema` and codegen — **partially closed** (`986fee4` gave a binding its scope chain; `b339f68` gave occurrences positional ids). |
| **GAP-049** | `ext/tree-sitter-duo/grammar.js` is authored, not projected; there is no declarative production registry in Duo to project it from, and it does not currently pass `tree-sitter generate`. |

`docs/spec/AUTHORITY.md` additionally carries four unticked P0 items:
`@`-directive ontology → graph/world facts; stable semantic identity across
scope/module/codegen; concept/generic/overload/method registries collapsed into
trie + relations; offside parsing + canonicalizer.

---

## 7. What is NOT release-ready

Stated plainly, no hedging.

1. **The unit test suite is red.** 23 failures, 2 leaks. At least four of them
   (`dnir_lower` ×2, `pass5_foreign` ×2) describe behaviour rather than emitted
   text. Shipping a compiler whose own test suite is red is a decision, not an
   oversight, and it should be made deliberately.
2. **The benchmark gate is red**: 12 measured wins, **12 folded**, 16 losses,
   and at least one Duo build folded on 27 of the 40 rows. The suite proves
   **correctness** (40/40 against reference C). It does not currently prove a
   speed claim. The suite now labels the folded rows itself and prints the
   three-way split, so the caveat travels with the number instead of living in
   this document — but **12 is a floor**: two rows the classifier declines
   (GCD reduce, String bytes) are folds by inspection of the emitted C, and the
   harness's `5e-05 s` tie epsilon still hands a "win" to any row where C
   finishes in under 50 µs. Forty-six `use_*` recognisers reach codegen and
   seven carry a `verify_*`; the inventory is §4.
3. **Ward is slower than every reference runtime on workload B and tied on
   workload A.** Its JIT does not engage on `hot_big.wasm`. Two of Pass 101 §4's
   criteria are formally UNMET and their harnesses exit non-zero saying so. Ward
   also has no running test suite.
4. **Cross-execution is unproven.** Six targets build; one was run. There is no
   evidence any non-host binary works.
5. **The Pass 100 surface does not exist** (GAP-025). `CLAUDE.md` §0 describes a
   language that does not compile today. The deny table measures *distance from*
   that surface — 30044 deny lines across 446 canonical files — and that
   distance is not small.
6. **`audit100` is pressure, not proof.** Seven of its 24 §1 rows are semantic
   and unmechanized (discard binders, module aliases, `Alias.fn(subject, …)`,
   single-use temps, elseif kind-ladders, sentinels, mixed-kind groups). The
   mechanized rows are line-grained, so they over-report inside string literals
   and under-report inside trailing comments. The gate says so itself.
7. **The toolchain re-derives what the compiler already knows.** `duo graph`
   emits the facts hover/definition/references need; the LSP never calls it and
   re-implements them as line scanners, and 16 MCP tools are registered twice
   across two simultaneously-configured servers. See `docs/toolchain_state.md`.
8. **`ext/tree-sitter-duo/grammar.js` is 804 lines of hand-authored
   JavaScript**, a live monoglot violation: Pass 100 §19 lists tree-sitter as
   "a generated grammar projection (output, never authored)". Three things this
   document said or implied about it were wrong, and are corrected here.

   - It is **not** "the only non-Duo, non-generated source in the toolchain".
     There are **three** tracked `.js` files — `grammar.js` (804),
     `docs/theme/custom.js` (97), `ext/vscode-duo/extension.js` (81), 982 lines
     — and `extension.js` is toolchain by any reading.
   - The **G11 census could not see any of them.** It counted `.duo`, `.zig`,
     `.lua`, `.c/.h` and `.sh/.py`; `.js` matched no pattern, so "the census is
     otherwise clean" was a claim about a category that was never counted.
     `audit100`'s `nonduo` row counts `grammar.js` as 1 of 536 files,
     indistinguishable from a `.wast` fixture, and `docs/spec/corpus.md`
     classifies `.duo` only (`audit100` lists the corpus with
     `git ls-files '*.duo'`, so a `.js` rule there would be dead data).
     **Fixed this pass**: G11 now reports `.js` as a second DEBT line, ratcheted
     at 3 (`CENSUS_JS_FLOOR`). It is debt, not "generated", because a
     sanctioned generated artifact must name its generator and none of the
     three has one.
   - **It does not build.** `tree-sitter generate` exits 1 in that directory
     with an unresolved conflict on `return_statement` (`'return' • '('`).
     Verified against the pristine `HEAD` copy as well as the working tree. The
     tracked `src/grammar.json` beside it lists the same 90 rule names and is
     output from a tree-sitter that resolved the conflict; the CLI installed
     here does not. `scripts/setup-nvim.duo` runs the generator with
     `>/dev/null 2>&1` and prints `-- tree-sitter generate failed`, which reads
     like a skipped optional step.

   **It was not converted, and must not be deleted.** The descriptor surface it
   would be projected from does not exist: `lib/std/compiler/parser.duo` is an
   imperative recursive-descent parser over a ~12-production bounded subset,
   `docs/GRAMMAR_SPEC.md` is prose, `duo token-tables emit` is lexical only, and
   `duo graph` is downstream of parsing. Separately, the 90 rules still spell a
   pre-Pass-100 surface (`match`, `enum`, `try`/`catch`, `concept`, optional
   types, `local`, `const`, `function`), every one denied by `CLAUDE.md` §1 —
   so regenerating it from Pass 100 descriptors would change which programs the
   editors recognise, a language decision downstream of GAP-025. **`GAP-049`**
   names the three missing pieces and the order they have to land in.
9. **The shared working tree is not a measurement surface**, and neither is
   `/tmp`. Concurrent sessions caused one transient gate failure during this
   pass, and `audit100`'s fixed `/tmp/duo_audit100_canonical.list` was
   rewritten under a detached-worktree run by a concurrent run in the main
   tree — the gate printed one tree's `root` and another tree's counts, with no
   indication. Any release measurement must be taken in a detached worktree at
   a pushed commit **and with a private temp path** — this document's §2
   `audit100` numbers and §4 benchmark were.

## What IS ready

The compiler builds for six targets with zero errors and produces artifacts for
all six. The tier-0 gate, hygiene, public safety, the Pass 100 deny table, the
clean-directory project loop, the G11 language census and both lexer
differentials are green. `duo init`
→ `check` → `build` → `run` works on an empty directory and is gated. All 40
benchmark correctness rows agree with reference C. **The benchmark suite now
separates a measured win from an evaluated one by a rule that reads two
durations and no row names, controlled on eleven synthetic points and
perturbation-tested in both directions on both thresholds** — the failure mode
that cost this repository ten kernel substitutions is now something the suite
reports about itself rather than something a reader has to know. Ward executes 43 of 44 WASM
modules in agreement with wasmtime on both engines, and 24 of 24 freshly
generated random kernels. Every fabricated benchmark kernel that has been found
has been removed, and the rules that forbid the next one are written down and
enforced.
