| field | value |
|---|---|
| title | attempt: spec-private-prefix-test-property-12-2026-08-29 |

| # | directive |
|---|---|
| 1 | opened: 2026-08-29T05:10:00-07:00 closed: 2026-08-29T05:10:00-07:00 actor: self |

| section |
|---|---|
| observed fixture set |

| # | directive |
|---|---|
| 1 | `sh gate/gap-145-consumer.sh` (22 checks pass) |
| 2 | `sh gate/grammar-projection.sh` (control + entry + byte-identical) |
| 3 | `sh gate/posix.sh` (84 shell gates parse under dash) |

| section |
|---|---|
| what changed |

| # | directive |
|---|---|
| 1 | `scripts/test_property_12.id`: |
| 2 | ↳ `_seed` -> `seed` (the LCG state is a single-word 'seed' — the leading underscore was the private-marker convention that the spec §9 forbids) |
| 3 | ↳ `_next_rand` -> `rand` (the function returns the next random number; 'next' is a positional descriptor the call site already carries, and 'rand' is the irreducible word for the LCG step) |

| section |
|---|---|
| result |

| # | directive |
|---|---|
| 1 | Commit landed at `c0718aa3` on `clpi/idol/main`. |
| 2 | The property test's LCG seed is unchanged (305419896, the same glibc constants the shell version used). |
| 3 | The script still produces the SAME 64 cases in the SAME order, so the bitwise differential oracle still agrees. |

| section |
|---|---|
| if rejected (not applicable) |

| # | directive |
|---|---|
