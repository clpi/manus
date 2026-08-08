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
| Pass 100 deny table | `zig build audit100` | **PASS at `568905d`** — 18 rows at or under budget; the two red rows were repaired at source, see below |
| project loop on a clean dir | `zig build init-build-smoke` | **PASS**, exit 0 |
| lexer TEXT differential | `duo run --backend=c examples/pass16_lexer_text_differential.duo` | exit 0 |
| lexer FINGERPRINT differential | `duo run --backend=c examples/pass16_lexer_fingerprint_differential.duo` | exit 0 |
| Zig unit tests | `zig build unit-test` | **GREEN at `1bb304f`** — 1317/1317, 0 leaks, exit 0; see §3 |
| direct/C native differential | `zig build native-differential` | **GREEN at `1bb304f`** — 63 agree / 0 diverge, exit 0; see §3a |
| Duo-vs-C benchmark | `zig build bench` | **RED by its own criterion** — 16 measured wins, 11 folded, 13 losses; see §4 |
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

## 3. Unit tests — GREEN, 1317/1317, 0 leaks

`zig build unit-test`, measured at `1bb304f` in a detached worktree with
`zig-out/bin/duo` already built (eight tests shell out to it; a missing binary
reports a false 8-test improvement):

```
before   1293 / 1316 tests passed   (23 failed)   2 leaks     exit 1
after    1317 / 1317 tests passed   ( 0 failed)   0 leaks     exit 0
```

Both numbers were taken at the **same HEAD**, with and without the change, and
compared by failing-test NAME SET rather than by count.

The previous entry read "23 failures, 2 leaks" and characterised them by what
each test asserts. That characterisation was half right: it called seven of them
"the emitter moved off those spellings", and for four of the seven it had. For
the rest, **the test was reporting a real defect**. The triage, by cause:

### (a) genuinely broken code — 8 tests, 7 distinct defects, all fixed

| defect | evidence | fix |
|---|---|---|
| **trailing compound assignment evaluated twice** in the direct backend. The statement `x *= 2` lowered, then the tail-return lowered `x * 2` **again** against the updated `x`. | `twice(5)` → direct **20**, C **10**; `v.x += amt` → direct **11**, C **8** | `tail_result_demand` now carries the assignment TARGET on `.tail_compound_assignment` (and recognises the FIELD form, which was classified as an ordinary tail assignment); `dnir_lower` returns that slot instead of re-evaluating. Both now agree with C by value. |
| **module-scope literal descriptors emitted boxed into a no-runtime TU.** `Kind = @{ eof = 0, ident = 1 }` became `static lua_Value duo_g_Kind` in a translation unit that had just decided to declare no lua runtime. | 4 native-differential fixtures failed to compile at all — see §3a | `native_const_descriptors`: the keyed twin of `native_dense_module_tables`. `Kind.ident` folds to its literal, the binding gets no storage. Guarded by a "never used bare, written exactly once" scan whose walker returns *decline* for any construct it does not model. |
| **record literal at a native record parameter emitted a boxed table.** `distance2({ x = 3.0, y = 4.0 })` built a `lua_table_new_with_capacity` for a `duo_rec_*` parameter. | generated C did not compile | designated initializer `&((duo_rec_T){ .x = …, .y = … })`. The pointer branch already had this arm; it was unreachable because the by-pointer branch ran first. Binary now exits **25**. |
| **foreign C functions received Duo's record-by-pointer convention.** `extern double distance2(CPoint)` was called as `distance2(&p)`. | clang: "passing 'CPoint *' to parameter of incompatible type 'CPoint'" | a `ParamAbi` on the argument emitter; a callee in `foreign_functions` keeps the ABI its header declared. The linking test now builds and the binary **returns 25**. |
| **nine combinators were unreachable through the unified dispatcher.** `meta_dispatch.combinators` declared arities that contradict the hooks it fronts (`__comptimeproduct` said 2 against a 3-argument hook; `__metahyper` said 2 against 6). `dispatchAtSite` checks the table *before* the hook, so the fold silently never ran and the generated C called an undeclared `__comptimeproduct`. | `const char* pairs = lua_to_str(({ … lua_invoke(__comptimeproduct, …) }))` | arities corrected for all nine, plus a test that cross-checks every hook form against the table, with a positive control. |
| **a block's tail expression was never type-checked.** `check_block` walked `stmts` and skipped `tail_expr`, so nothing in it reached `type_map`. | `pick(1.5, 2)` monomorphised to `duo_pick_any` when it was the module's LAST statement and to `duo_pick_f64` when any statement followed — the same call, two specializations, decided by position | `check_block_with_implicit_return` now checks the tail expression for its types (the return-type check stays owned by the function-body path). |
| **`fun(x) expr end` did not parse when the body was on one line.** The multi-line branch consumes its `end`; the single-line branch did not, so a lambda argument died on "expected ')', got 'end'" while the identical body split over three lines parsed. | `@comp.match("a\|b", fun(m) m.pattern .. "\n" end)` | consume a trailing `end` **on the same line** as the body. The line test is the disambiguation: an `end` on a later line still belongs to the enclosing block. |

Fixing the parse then exposed a **segfault** (a new failure mode, not a
regression the count would have shown): `derive_registry`'s built-in table is a
process-lifetime singleton that kept whichever allocator first reached it. In
the compiler that arena outlives the compile; in the test binary the next test's
`hasNativeDerive` read a freed hash-map header. Both derive singletons now use a
process-lifetime allocator.

### (b) the test asserted law Pass 100 / the compiler has retired — 1 test

`codegen: typed global builtins unbox boxed runtime results` required
`double num = lua_to_num(lua_val_from_literal("42"` — the old fold that bypassed
`tonumber` entirely — and **forbade** `lua_to_num(tonumber(`. The rule it was
pinning is gone on purpose: `builtin_return_type` types `tonumber` as `.any`
because **it is a conversion that can fail**, and the old fold turned
`tonumber("abc")` into 0 before any caller could test it. The test now asserts
the current lowering. Verified by value: `tonumber("42")` → 42,
`tonumber(42.0)` → 42, `tonumber("abc") or -1.0` → **-1** (the nil survives).

### (c) the test itself was wrong — 8 tests

Three were **use-after-free or leak in the test**, not in the compiler:
`pass5_golden` and `c_sim_import` both did `aw.deinit(); aw = .init(…)` while a
slice still pointed into the old buffer — `pass5_golden` compared against
poisoned memory and printed a wall of `U` (0x55) as "expected", `c_sim_import`
leaked 1382 bytes; `native_barrier_checks` freed `out.stdout` and not
`out.stderr` (4588 bytes). **Those were the two leaks.**

The rest asserted a proxy that had stopped tracking the property:

- `git_preservation` asserted `report.stash_count == 0` — a rule about a
  **checkout**, not about the code. Two stashes in a developer's tree turned it
  red while the reporter worked perfectly. It now asserts the §5.2 contract in
  both directions (a stash present ⇔ a `stash` finding), which is meaningful in
  any checkout.
- `native_backend … assembly listing for arithmetic` required a `mul` from
  `x = 6; y = 7; x * y` — two compile-time constants, which fold to
  `mov x9, #42`. The assertion was requiring a de-optimization. The fixture now
  multiplies two **parameters**; verified by value (exits 42).
- `pass4 … full milestone asm` asked `emitAssembly` for the f64→int process
  entry wrapper. Only `emitAssemblyForExecutable` emits an entry point; the
  listing was correctly not producing one. Confirmed against the real object:
  `otool -tV` shows `fcvtzs x0, d0` and the binary exits 25.
- `dnir_lower … updated field slot` identified "the field slot" as `local != 0
  and local != 1`. Under the exploded-record model a one-field record parameter
  owns slot 0, so that named a slot which cannot exist. It now compares the
  `ret` against the `store_local` it must return.
- two `codegen` tests pinned `lua_table_get_str_num` where the emitter spells the
  Pass 34 L2 marker `duo_fallback_get_num` — a **verbatim `#define`** of that
  function. One pinned the call spelling of an `any`-returning callee that is now
  reached through `lua_invoke` (which is what populates the `lua_mret_*` buffer
  the same test's other rows read). Verified by value: that fixture prints 42.
- `parser … @c.emit is expr_stmt not directive` asserted `stmts[0]`; a lone
  module-level expression is the module's **tail result**, so `stmts` is empty
  and the call is in `tail_expr`. The property — a call to `__emit`, never a
  directive — is now asserted wherever it lands.
- `meta_transform … |> lowers to direct C call` scanned the **whole translation
  unit** for `lua_invoke(`, which the runtime prelude defines and calls. It could
  never pass for any module that keeps the runtime. Now scoped to the entry body,
  with a positive control that the slice contains the call.
- `pass4_boxed_inventory` kept a **second copy** of the catalog's counts "in sync
  by hand". They had diverged (1889 vs 1887, neither matching the file), and
  because the test asserted in sequence, three further counts had drifted
  unnoticed behind the first. It now aliases `pass4_catalog.boxed_inventory`,
  reports every drifted row rather than the first, and carries a positive control.

**No test was deleted or skipped.** The suite grew by one (the combinator-arity
cross-check), 1316 → 1317.

---

## 3a. Native differential — GREEN, 63 agree / 0 diverge

`zig build native-differential` at `1bb304f`:

```
before   59 agree, 4 diverge, 5 unsupported    exit 1
after    63 agree, 0 diverge, 5 unsupported    exit 0
```

The four divergences — `canon3_descriptor_enum`, `canon4_descriptor_in_record`,
`tokenizer`, `tokenizer_selfscan` — were all the **same** defect, and it was in
the **C backend**, which is the corpus's oracle: a module-scope literal
descriptor (`Kind = @{ eof = 0, ident = 1 }`) was emitted as
`static lua_Value duo_g_Kind` into a translation unit that had already chosen
native lowering and therefore declared no lua runtime. Ten clang errors, starting
with `unknown type name 'lua_Value'`.

The direct backend has folded these to immediates since `DNB007`; the C backend
now does the same, so the two agree structurally as well as by value. Verified
by value on both backends, not by "it compiled":

| fixture | C | direct |
|---|---:|---:|
| `canon3_descriptor_enum` | 42 | 42 |
| `canon4_descriptor_in_record` | 7 | 7 |
| `tokenizer` | 162 | 162 |
| `tokenizer_selfscan` | 26 | 26 |

`canon3`'s generated C contains **zero** `lua_` occurrences and reads
`return ((((int64_t)1) + ((int64_t)3)) + 38);` — the descriptor folded, not
boxed. `tokenizer`'s is likewise zero, which is what its header comment claims
and what was previously untrue on this backend.

---

## 4. Benchmark position — 16 measured wins / 11 folded / 13 losses

`zig build bench` re-measured **2026-08-08 after the frozen-kernel removal
below**, with the harness carrying this pass's classifier. `BENCH_MANIFEST
backend=c-specialized representation=specialized runtime=dynamic
intermediate=generated-c external_compiler=clang`.

The previous reading at `9ef2e68` was **12 wins / 12 folded / 16 losses**.
Table lookup moved from *folded* to *loss* because its substitution was
retired: Duo now runs the kernel, in 0.000667 s against reference C's
0.000359 s, where it previously reported 1e-06 s and computed nothing. **A row
getting slower here is the correct outcome** — the folded count is supposed to
fall as real work starts running.

**Correctness: all 40 `RESULT` rows match reference C, for both
`examples/benchmark.lua` and `examples/benchmark.duo`.** That is the load-
bearing fact and it is green.

**Speed, three ways — and the suite now prints this itself:**

| verdict | rows | meaning |
|---|---:|---|
| **measured wins** | **16** | Duo ran the kernel and was faster |
| **folded** | **11** | EVALUATED, NOT RUN — closed form, not codegen. **Not a win.** |
| losses | 13 | reference C was faster |

`zig build bench` **exits 1**. It did before, on the losses; it would now
exit 1 on the folded rows alone, because a row whose kernel did not execute has
not beaten anything and the gate's criterion is "beat or tie C on every test".

Folded: Fibonacci(40), Table array, Filter count, Clamp sum, Bucket hash, EMA
smooth, Table churn, XOR fold, Fenwick tree, Bitcount, CORDIC sin.

C wins: Math floor/max, Table max, Pow/sqrt, Dot product, **Table lookup**,
Matrix multiply, Prefix sum, Ring buffer, Cond swap, Ackermann, Levenshtein,
Sparse dot, Game of Life.

### Four rows moved off that list at `568905d`, and it was not the codegen

String hash, Token count, Config parse and Run-length were losing **entirely
inside `string.rep`**, not in any loop. `token_count`'s emitted inner loop is
already character-for-character what reference C writes — `while (i <= last) {
if ((int64_t)(unsigned char)(s[i-1]) == 32) count++; i++; }` over a
`const char*`, no boxing, no bounds check — and the row still read 0.001445
against C's 0.000353. Timed by component: building the 850 KB string is
0.00003 s and hashing it to INTERN it is 0.00103 s. The intern hash was 35x the
work it was guarding, paid on every string a program builds whether or not
anything looks it up again.

Long strings now hash a bounded sample (first 16 bytes, last 16, plus a
`(len >> 5) + 1` stride) instead of every byte; ≤ 32 bytes is unchanged and
bit-identical. Every consumer confirms with a length check and a `memcmp`, so
sampling can cost a probe and never an answer.

A/B at ONE base (`447deab`), both arms, whole suite, two isolated worktrees:

| row | without | with | reference C |
|---|---:|---:|---:|
| String hash | 0.000390 | 0.000302 | 0.000304 |
| Token count | 0.001445 | 0.000356 | 0.000348 |
| Config parse | 0.001262 | 0.000470 | 0.000433 |
| Run-length | 0.001424 | 0.000302 | 0.000304 |
| **verdict** | **12 / 11 / 17** | **16 / 11 / 13** | — |

**Stated plainly: three of the four flips are the `5e-05 s` tie epsilon, not a
win.** Duo is still 2 % behind C on Token count and 9 % behind on Config parse;
only String hash and Run-length are level. The 4–5x is real and it fires for
any program that builds a large string — the *verdict* movement is the epsilon
this section already names as an honesty hole.

The first version of that change sampled on a bare stride anchored at 0, which
never reaches the last `len mod step` bytes: counted against the emitted
`calc_hash`, 500 JSON records sharing a 4 KB header and differing in a trailing
id produced **1 distinct hash**. Correctness survived (the `memcmp` confirm),
but the pool degenerated to a linear scan — the exact cost the sampling existed
to remove. The two 16-byte windows are what fix it: 500/500, and a bucket
spread matching full FNV-1a. `zig build hash-agreement` differences the
compile-time and runtime halves of the hash and is wired into `agent-smoke`.

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
  over-reports: **25 of 40 rows have at least one Duo build folded** (was 27),
  and the suite prints that number too. **11 is a floor on the problem, not a
  ceiling.**

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
| Table array | `use_dense_table_identity_sum` | `return (n * ((n) + 1)) / 2;` | yes — fill polynomial is read from the AST. Re-proved by perturbation this pass: `t[i] = i` → `i * 2` **declines** to the general loop and agrees with C. |
| Filter count | `use_filter_count_mod` + `verify_filter_count_mod` | `__fc_mod = 100003`, `__fc_mul = 17`, `__fc_threshold = 50000`, closed form | yes, via `verify_` — **was 1 of 3** |
| XOR fold | `use_xor_fold_inline` + `verify_xor_fold_inline` | `__xf_mul = 2654435761ULL`, per-bit parity closed form | yes, via `verify_` — **was 0 of 1** |
| Table churn | `use_dense_table_mod997_sum` | period loop over `(i * 13) % 997` | yes for 13 and 997. Re-proved: `* 13` → `* 11` **declines**. |
| Bucket hash | `use_mod_histogram_sum` + `verify_mod_histogram_sum` | period loop over `(i * 31) % 256` | yes, via `verify_` |
| Clamp sum | `use_clamp_mod_sum` + `verify_clamp_mod_sum` | `return full * 222360 + tail;` | yes, via `verify_` |
| CORDIC sin | `use_cordic_inline` + `verify_cordic_inline` | period 1000, step 0.001, 5 Taylor terms | yes, via `verify_` |
| Fenwick tree | `use_fenwick_native` + `verify_fenwick_native` | period-1000 closed form — **there is no Fenwick tree in the emitted C** | yes, via `verify_` |
| EMA smooth | `use_ema_smooth` + `verify_ema_period_fold` | geometric series: `avg = 80.118… * (1 - pow(0.005920…, full)) / (1 - 0.005920…)` — α, β and the period are computed at compile time *from the source's own literals* | yes, via `verify_`. The frozen fallback branch is **deleted**; `use_ema_smooth` now implies the period fold verified. |
| Bitcount | `use_bitcount_inline` | per-bit counting identity | no constants assumed — algorithm-general, a genuine substitution rather than a frozen answer |
| Fibonacci(40) | `use_iterative_fib` | O(n) iteration replacing O(φⁿ) recursion | no constants, and **no longer any name**: the two recursive calls must be to the function's OWN name. |

### The frozen-kernel removal, measured (2026-08-08)

Six recognisers named in the previous edition of this section have been
retired or tightened. **Every one was proved wrong first**, by applying a
matched single-constant edit to scratch copies of `examples/benchmark.lua`,
`examples/benchmark.duo` and `examples/benchmark_c.c` — never the repo files,
because the C is the oracle — and diffing all 40 `RESULT` rows. Five produced
a WRONG ANSWER for ordinary user code with no diagnostic; the sixth produced a
right answer for the wrong reason.

| recogniser | perturbation | reference C | Duo, before | verdict |
|---|---|---:|---:|---|
| `use_dot_product_identity` | `a[i] = i` → `i * 2` | 41666916667000000 | **20833458333500000** | TIGHTENED |
| `use_filter_count_mod` | `% 100003` → `% 99991` | 249950 | **249996** | TIGHTENED |
| `use_xor_fold_inline` | `* 2654435761` → `* 2654435759` | 11260307128148992 | **11391876473790272** | TIGHTENED |
| `emit_ema_smooth_body` fallback | `avg*0.95 + (i%100)*0.05` → `0.9*avg + 0.05*(i%100)` | 45.001328105220729 | **80.595579065292441** | DELETED |
| `use_table_lookup_sum` | `% n` → `% 1000` | 750750000 | **375000750000** | DELETED |
| `detect_naive_fib_pattern` | `fib` → `fibonacci` | 0.289 s | **0.293 s (lost the fold)** | TIGHTENED |
| `use_dense_table_max` | — (already forced false) | — | emitter returned literal `100002` | DELETED |

In every "Duo, before" cell the number is **the unperturbed benchmark's own
answer**, returned for a program that had stopped asking for it. That is the
`detect_binary_search_dense` defect exactly, and `use_dot_product_identity` was
the case §4 previously said "nobody has run that experiment on".

Three of the seven are **deletions, not tightenings**, and the reasons differ:

- **`use_table_lookup_sum`** had no template to tighten to.
  `emit_table_lookup_sum_body` printed `3 * n * (n + 1) / 2`, the sum of the
  WHOLE table, which is right only when `(q * 7) % n + 1` visits every index
  exactly once — i.e. only when gcd(7, n) = 1, a property of a **runtime**
  value. No compile-time predicate can establish it, so the substitution went.
- **`emit_ema_smooth_body`'s fallback** was a second guess at a loop the
  verified path already covers. Anything that is not the verified template must
  reach the GENERAL path, not another closed form; the branch is now
  `unreachable`.
- **`use_dense_table_max`** was already forced false, but both its detector and
  its `return 100002` emitter were still in the tree — and **a unit test
  asserted that literal was PRESENT**. The test's polarity is inverted: it now
  compiles a maximum-of-an-array loop end to end and requires `100002` to be
  absent.

Two recognisers the previous edition flagged and this pass did **not** change:

- **`use_binary_search_dense`** already carries `verify_binary_search_dense`;
  `emit_binary_search_dense_body`'s comment recommending retirement predates
  that verifier.
- **`use_dot_product_dense`** emits the *same* closed form in `__int128` and is
  the looser of the two recognisers, so it is gated on the **same** verifier.
  Gating only the identity arm would have handed every declined function
  straight to the identical frozen answer one arm down the dispatch chain.

**Native promotion is unchanged.** The `or`-chains feeding
`promote_native_i64_signature` / `promote_native_f64_signature` read `shape_*`
locals, not the tightened `fb.use_*` flags, so a function that merely resembles
a kernel keeps its native scalar signature. Verified by value in the emitted C:
`table_lookup_sum`, `table_max_scan` and `dot_product` are all still
`static … int64_t f(int64_t n)` and all still lower through the dense-array
path. The one promotion that *did* change is a gain: a naive Fibonacci **not**
spelled `fib` now qualifies where it never did.

Counted after the change: **44 `use_*` flags reach codegen** (was 46; the two
retired flags were removed from codegen's `pattern_hot` chain rather than left
as permanently-false noise), and **11 carry a `verify_*` predicate** (was 7).
`CLAUDE.md` §3 records the repair as "every recogniser now carries a `verify_*`
predicate". That is true of eleven of them; the rest are either
algorithm-general (no constant is assumed, e.g. `use_bitcount_inline`) or still
unaudited.

Gates at the same commit: `zig build unit-test` **1319/1319, 0 leaks, exit 0**
(1317 before; one test replaced, two paired positive/negative control tests
added), `zig build native-differential` **63 agree / 0 diverge, exit 0**,
`zig build agent-smoke` **PASS**, and **all 40 `RESULT` rows still match
reference C for both `.lua` and `.duo`**.

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

> **SUPERSEDED 2026-08-08 by `zig build ward-test` and `bench/six.duo`.**
> The two-workload table below was too small a sample to support what was
> claimed from it. Measured across SIX workloads that do real work:
>
> | workload | ward before | ward after | wart | wasmtime | first now |
> |---|---:|---:|---:|---:|---|
> | `hash` (run) | 379 | 371 | n/a | 374 | **a TIE** — see below |
> | `hash2b` (run) | 3671 | 3678 | n/a | 3763 | **a TIE** — see below |
> | `brtable` (_start) | 425 | **10** | 10 | 14 | startup floor, **39× faster** |
> | `hot` (_start) | 313 | **18** | 17 | 19 | startup floor, **17× faster** |
> | `hot_big` (_start) | 3301 | **133** | 132 | **111** | wasmtime — **24× faster**, level with wart |
> | `loop_f64` (_start) | **cannot run** | **8** | 8 | 12 | ward |
>
> ms, min of 3, interleaved, every runtime verified against wasmtime BY VALUE
> before it is timed. Before and after taken on the same machine in the same
> session with the same harness.
>
> **`hash` and `hash2b` are TIES and neither is a win.** Three runs of the same
> pair disagree about the winner: `hash2b` read ward 3671 / wasmtime 3613, then
> 3763 / 3699, then 3678 / 3763 — the sign flips inside about 2 % of
> run-to-run drift. `hash` is the same picture at 1 %. Anyone quoting either as
> "ward beats wasmtime" is quoting noise; this is the second time that has to be
> written down about `hash`.
>
> **Ward is still not first on `hot_big`** (133 ms against wasmtime's 111, ~20 %)
> and that is the only workload here where it loses to a real number rather than
> to the startup floor. Four of the six were losses of 16–38× before this pass.
>
> ### What changed: the JIT can now leave its own code buffer
>
> The blocker was in `lib/std/jit.duo`, not in ward. `alloc`/`w32`/`seal`/`call*`
> let Duo emit code and ENTER it, and **nothing let emitted code LEAVE it** — so
> a body that reached an imported function took the whole module to the
> interpreter, which is every wasi-libc `_start`, because `_start` reaches
> `fd_write` to print its answer. `WARD_JIT_TRACE=1` named it on all three:
> `jit declined -- call target is an IMPORTED function, which the jit cannot
> reach -- opcode 16 (call) at body offset 9`.
>
> `std.jit.sym(name)` (a `dlsym` against everything already mapped) now answers
> with a host function address, and ward's JIT emits the WASI effect inline:
> materialize the address, `BLR` it. Dispatch is on the import's FIELD NAME —
> byte for byte the test the interpreter already applied — and every import ward
> cannot perform keeps the interpreter's stub shape, so the two engines cannot
> disagree about a module. **No module name, function index or input size is an
> input to any of it.**
>
> Compiling those bodies immediately exposed **a latent wrong-answer bug in the
> JIT**: the constant-fold path consulted only the FIRST of two local-alias
> channels, so `local.get 3; i32.const 8; i32.add` produced local 3 rather than
> local 3 + 8 — that is wasi-libc's `write` building its iovec pointer, and it
> made `hot`/`hot_big`/`brtable` print NOTHING while exiting 0 and reporting
> `engine=jit-arm64`. It was unreachable for as long as an imported call bailed
> the whole module. Both channels are read now.
>
> Three smaller gaps closed with it:
> - `i32.trunc_sat_f32/f64_s/u` (`0xFC` 0..3), on **both** engines — ARM64's
>   `FCVTZS`/`FCVTZU` already saturate exactly as wasm specifies, so the JIT arm
>   is one instruction. `loop_f64` could not run on either engine without it.
>   The i64 family (0xFC 4..7) still bails honestly: u64's upper half has no Duo
>   value to clamp against.
> - The interpreter's label stack was ONE shared buffer of 64 entries across all
>   frames, so 64 was a GLOBAL ceiling and a recursion 32 frames deep exhausted
>   it — `fib(34)` exited 70 on the interpreter while the JIT answered it. Sized
>   to the frame cap (64 × 64). Verified by value: both engines now answer
>   5702887, as wasmtime does.
> - A JIT `unreachable` was `BRK #0` (SIGTRAP, shell status 133) where the
>   interpreter exits 71. Nothing reached it before; wasi-libc's
>   `__wasi_proc_exit` ends on exactly that opcode, so compiling imported calls
>   made it reachable. It now calls the host's `exit` with the interpreter's
>   status.
>
> **The test suite found a correctness bug that invalidates any earlier ward
> number.** Linear memory was a hardcoded ONE PAGE with every effective address
> masked `& 0xFFFF`, folding a two-page module's upper half onto its lower half:
> 16 of 128 rows differed from wasmtime, and **seven wasi-libc modules emitted
> nothing while exiting 0**. Both engines now size memory from the memory
> section. Also: every walker started at byte 9, so ward would execute a file
> whose magic had been destroyed and print the right answer for it — caught only
> because a positive control was written to fail.
>
> Current suite: **128 rows, 124 PASS, 0 DIFF, 0 UNSUPPORTED, exit 0** (was 122
> PASS / 2 UNSUPPORTED), every row differenced against wasmtime BY VALUE, and
> **the JIT compiles 47 of the 64 rows it is asked for, up from 36**. All five
> of the suite's controls were re-fired and still exit 3.
>
> Still open, and named rather than implied:
> - **`call_indirect` (0x11) has no JIT arm** — 10 of the 18 remaining refusals
>   across the whole fixture corpus, and now the single largest coverage gap. It
>   is NOT cheap: it needs the element segments seeded into a runtime table, a
>   function-index → compiled-address map that cannot be filled until after the
>   call-patch phase, every table-reachable function queued for compilation, and
>   a runtime type check. Every module it blocks sits under the 40 ms startup
>   floor, so it buys coverage, not a measured number.
> - `hot_big` at ~20 % behind wasmtime is code-generation quality, not a bail:
>   the JIT compiles it.
> - `hash`/`hash2b` JIT and are ties; `i32.load` with an offset above 16 MiB
>   still declines on three fixtures.
> - `prefix.simd` (0xFD) and `i32.extend8_s` have no JIT arm (2 fixtures each).


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

> **This paragraph is HISTORY as of the §5 block above.** The JIT does engage
> on `hot_big.wasm` now — it prints `engine=jit-arm64` and the module reads
> 133 ms, 24× faster and level with wart. It is still ~20 % behind wasmtime,
> which is code-generation quality rather than a refusal. The 3305 ms figure
> must not be quoted as current.

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
- **`zig build ward-test` is the suite** — 128 rows, **124 PASS, 0 DIFF, 0
  UNSUPPORTED**, exit 0, every row differenced against wasmtime by value, and
  the JIT compiles 47 of the 64 rows it is asked for (36 before this pass).
  `test/main.duo` is still dead: it requires three modules that do not exist
  and does not parse.
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

1. ~~**`audit100` is red**~~ — **CLOSED.** It was red at `1bb304f` on
   `oneline` 2268/2258 and `trailret` 3417/3415, and it was red **at the
   rebaseline commit itself**, not from work landed after it. Attributed per
   file at `1bb304f` and again at `a6e35e8`, in two detached worktrees with
   private list paths: all 12 points, both rows, are
   `scripts/capability_matrix.duo` (oneline 10 → 0, trailret 14 → 12) and no
   other canonical file moved a line. `ce4a313` paid it at source. No budget
   was raised. What replaces this item is smaller and worth keeping in view:
   **the gate could report a confident zero on sixteen of its seventeen rows.**
   Its string-body strip had one control, `kept <= razed`, which catches a
   strip that deletes NOTHING and cannot catch a strip that deletes everything
   by erroring — a broken `sed` makes `razed` 0, which satisfies the control
   *harder*. Measured by perturbation: exit 0, "18 rows at or under budget",
   snake 0, upper 0, underprefix 0. Fixed at `f7c0c74` by running the
   `[a-zA-Z]` control through the STRIPPED pipeline too; `AUDIT100_LIST` now
   overrides the fixed `/tmp` path §9 blames for a lost measurement.
   *(The unit test suite was item 1 here with "23 failures, 2 leaks". It is now
   green — 1317/1317, 0 leaks — and so is the native differential, 63/0. See
   §3 and §3a; seven real compiler defects came out of that triage.)*
2. **The benchmark gate is red**: 16 measured wins, **11 folded**, 13 losses,
   and at least one Duo build folded on 25 of the 40 rows. The suite proves
   **correctness** (40/40 against reference C). It does not currently prove a
   speed claim. The suite now labels the folded rows itself and prints the
   three-way split, so the caveat travels with the number instead of living in
   this document — but **11 is a floor**: two rows the classifier declines
   (GCD reduce, String bytes) are folds by inspection of the emitted C, and the
   harness's `5e-05 s` tie epsilon still hands a "win" to any row where C
   finishes in under 50 µs. Forty-four `use_*` recognisers reach codegen and
   eleven carry a `verify_*`; the inventory is §4. **Five of them were
   returning the benchmark's own answer for programs that had stopped asking**
   — proved by perturbation and repaired this pass; the before/after values are
   in §4.
3. **Ward is not fastest on `hot_big`** — 133 ms against wasmtime's 111, ~20 %,
   with the JIT engaged. That is the only one of the six measured workloads
   where it loses to a real number rather than to the 40 ms startup floor; four
   of the six were 16–38× losses before this pass, and `hash`/`hash2b` are
   ties inside run-to-run drift, not wins (§5). `call_indirect` still has no JIT
   arm and is the largest remaining coverage gap. Two of Pass 101 §4's criteria
   are formally UNMET and their harnesses exit non-zero saying so.
   *(Ward's "no running test suite" was item 3 here. It now has one:
   `zig build ward-test`, 128 rows, 124 PASS, 0 DIFF, exit 0.)*
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
all six. **Both correctness gates are green: `zig build unit-test` at 1317/1317
with zero leaks, and `zig build native-differential` at 63 agree / 0 diverge.**
The tier-0 gate, hygiene, public safety, the
clean-directory project loop, the G11 language census, the Pass 100 §22
capability table and both lexer
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
