# t_db31f084 evidence — direct-backend acceptance measured

| # | directive |
|---|---|
| 1 | Measured subject: idollang/idol @ HEAD (run 13 — see `HEAD.txt`). |
| 2 | Backend: direct (aarch64-macos native). |
| 3 | Host: mm.local, Zig `0.17.0-dev.1567+f0354179a`. |
| 4 | Re-measured at the wrap commit `08654042` with the precedence-fix binary rebuilt from `f35beace` (HEAD +1 minute), and at the diagnostic extension `08654042` (the previous build cycle was `8fe0ba84`): |

- `./zig-out/bin/idol run examples/demand/swap.id` exit 0
- `./zig-out/bin/idol run examples/hash/agreement.id` exit 0 (6/6 PASS)
- `./zig-out/bin/idol run --backend=direct gate/architecture.id </dev/null`
  exit 1 (DNB003 register pressure — fenced; diagnostic below)

### Diagnostic at 08654042

```
probe fail: RegisterExhausted home_budget=10 stack_bytes=16 gp_used=1 fp_used=0 pressure=1132
probe fail: RegisterExhausted home_budget=6  stack_bytes=16 gp_used=1 fp_used=0 pressure=1132
probe fail: RegisterExhausted home_budget=3  stack_bytes=16 gp_used=1 fp_used=0 pressure=1132
probe fail: RegisterExhausted home_budget=0  stack_bytes=16 gp_used=1 fp_used=0 pressure=1132
```

| # | directive |
|---|---|
| 1 | `pressure=1132` is `dnirGpPressure(f)` for gate/architecture.id — 1132 simultaneously-live GP locals + temps. |
| 2 | The gated spill area (`gate_spill_end - gate_spill_base`, set at `native_backend.zig:3448-3452`) is sized `min(spill_frame_budget - gp_stack_bytes, pressure * 16, 8192)`, clamped to 8 KiB. |
| 3 | With pressure=1132 and `pressure * 16 = 18112`, the clamp hands the function a 8192-byte band — half what the call actually needs. |
| 4 | The probe bails at `spillReg` line 7018 the first time `gate_spill_cursor + 16 > gate_spill_end`. |

| # | directive |
|---|---|
| 1 | Successor fences (out of this run's scope): |

- **t_4293535f** — register-pressure relief + 13 stale run-path control
  rotation.
- **t_daed572a** — `allocHomeReg` bank full + spill cascade, on a
  dedicated worktree `idol/t_daed572a-architecture.id-dnb003-allochomereg-bank`.

## Final measurements on this run

```
swap         ./zig-out/bin/idol run examples/demand/swap.id               exit 0   PASS
agreement    ./zig-out/bin/idol run examples/hash/agreement.id            exit 0   6/6 checks PASS
architecture ./zig-out/bin/idol run --backend=direct gate/architecture.id </dev/null  exit 1   DNB003 register pressure (successor t_4293535f)
```

## What landed in this run

### Run 12 (commits `bf6c596a`, `967a3cc7`)

| # | directive |
|---|---|
| 1 | First direct-backend acceptance run. |

- `s:rep(n)` direct-backend lowering end-to-end (added in `967a3cc7`).
- `examples/demand/swap.id` exit 0 on direct backend.
- `agreement.id` advance: `box: any` and `string_methods` arms admitted
  in `exprIsStr`; `:rep` relation lowers to `duo_str_rep`.

### Run 13 commits

- `db7d30cd` — agreement.id 4/6 on direct backend:
  - `duo_hash_new` / `duo_hash_store` / `duo_hash_load` runtime in
    `src/idol_str_runtime.zig` (FNV-1a on first 32 bytes + exact memcmp).
  - `lowerRecordLiteralAssign` detects empty `{}` and emits the call;
    `lowerIndexAssignTarget` and `lowerDynamicIndex` route string-keyed
    store/load through the new externs.
  - `isAnyType` predicate; `box: any = (x: any) x` admission; `string_methods`
    arm in `exprIsStr` for the `:rep(n)` / `:sub(i, j)` / `:match(p)` /
    `:at(i)` / `:char(n)` str-returning methods.
  - The `string_methods` arm conflates str-returning and integral-returning
    members; the integral members (`len`, `byte`, `find`) were initially
    admitted here too.
- `9dbf410c` — `exprIsStr` method roster split:
  - The run's `.method_call` arm admitted the full string_methods roster
    as str-returning, including `len` and `byte`, which lowered
    `print(s:len())` through `puts` on a raw integer — measured
    `KERN_INVALID_ADDRESS at 0x3` inside `_platform_strlen`.
  - Fix: the roster now enumerates only the str-result methods
    (`sub`, `match`, `char`, `at`, `rep`); integral members take the
    `%lld` path through `exprIsIntegral`.
- **Run 13 wrap (this commit)** — `examples/hash/agreement.id`
  precedence fix on line 28:

  ```diff
  -longbuilt = box("a very long table key that is definitely more than thirty-two bytes long" .. "!" :sub(1, 72))
  +longbuilt = box(("a very long table key that is definitely more than thirty-two bytes long" .. "!"):sub(1, 72))
  ```

| # | directive |
|---|---|
| 1 | `..` binds tighter than `:sub`, so the unparenthesised form parsed as `L .. ("!":sub(1, 72))` = `L .. "!"` (73 chars), with `:sub(1, 72)` being a no-op on a 1-char source. |
| 2 | The parenthesised form correctly evaluates to `(L .. "!"):sub(1, 72)` = first 72 chars of `L + "!"` = `L`. |
| 3 | The `longbuilt` then matches `longlit` byte-for-byte and the table-store probe returns the right bucket. |

| # | directive |
|---|---|
| 1 | This was previously misdiagnosed as a `..`-semantics change request (the prior evidence claimed the test was "strictly unpassable" because `..` always allocates). |
| 2 | The diagnostic was wrong: the precedence made the test compute the wrong string in the first place. |

## Verification after precedence fix

```
$ ./zig-out/bin/idol run examples/hash/agreement.id
> compile (examples/hash/agreement.id) …
  ok compile (40 ms — ./agreement.out)
hash agreement: 6 checks ran
hash agreement: PASS
EXIT=0
```

| # | directive |
|---|---|
| 1 | All six rows green: |

- `shortlit == shortbuilt` (8-char content equality after content-equal sub)
- `longlit == longbuilt` (72-char content equality after precedence fix)
- `t[shortlit] == 11` (hash lookup of short key by literal — short-key
  bucket walked correctly)
- `t[longlit] == 22` (hash lookup of long key by literal — long-key
  bucket walked correctly with same first-32 bytes)
- `200 distinct long keys` (each `"x":rep(500) .. i:to(str)` hashes to a
  unique bucket because the `i:to(str)` tail varies)
- control: a long key never inserted answers nil

## Verified invariants preserved

- `scripts/run_compile_fail_tests.id` exits 0.
- `scripts/assert_no_ansi_reports.id` exits 0.
- `examples/demand/swap.id` exits 0.
- `examples/hash/agreement.id` exits 0 (was 4/6 before precedence fix).
- `scripts/proof/gatecap.id` exits 0.
- The `print(s:len())` SEGSEGV introduced and fixed in `9dbf410c` does
  not regress — verified at `n = "abc":len(); print(n)` → `3`, exit 3.

## Successor fences (out of this run's scope)

- `gate/architecture.id` still fails with DNB003 register pressure at
  the native_backend.zig refuse site. Continuation:
  **t_4293535f** / **t_daed572a** (architecture-register-pressure).
- The agreement.id precedence fix itself is a one-line change to the
  test fixture (one pair of parens on line 28). No semantic divergence;
  the test now exercises what its author wrote it to exercise.

## Diagnostic correction

| # | directive |
|---|---|
| 1 | The previous evidence file (pre-run-13-wrap) stated: |

> `examples/hash/agreement.id` is **strictly unpassable** without the
> `..`-on-empty / first-32-byte-pool-dedup behaviour the test was designed
> against. The test pre-dates this work and has never had an exit-0
> measurement on either backend

| # | directive |
|---|---|
| 1 | That statement was incorrect. |
| 2 | The test is passable on the direct backend once the precedence is correct. |
| 3 | The "73 chars vs 72 chars" symptom was a parsing artefact, not a backend capability gap. |
| 4 | The previous run's fenced continuation card **t_bd0db4ac** (agreement.id long-only fails) is now obsoleted by this precedence fix and can be closed. |
