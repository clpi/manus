| field | value |
|---|---|
| title | Corpus role (ZERO-HISTORY) |

| # | directive |
|---|---|
| 1 | Projection of `law.zero.history`. |
| 2 | Git is the sole historical archive. |

| section |
|---|---|
| Durable states |

| # | directive |
|---|---|
| 1 | Only two corpus states exist in the active tree: |

| state | meaning | agent retrieval |
|---|---|---|
| `current` | teaches or exercises current Idol law | include by default |
| `foreign` | current foreign law (Lua, C, Wasm, host oracle) | exclude unless requested |

| # | directive |
|---|---|
| 1 | A bootstrap bridge is an **implementation dependency**, not a corpus state. |

| # | directive |
|---|---|
| 1 | Deleted durable labels: `historical`, `legacy`, `migration`, `compat`, `verified`, `proof`, `deprecated`, `old`, pass-number archive. |

| section |
|---|---|
| Marking |

| # | directive |
|---|---|
| 1 | First line of `.id` when classification matters: |

```id
# @corpus current
# @corpus foreign
```

| # | directive |
|---|---|
| 1 | Mechanical check: `tools/node/dev/corpuscensus`. |

| section |
|---|---|
| Rules |

| # | directive |
|---|---|
| 1 | Current tree source is not proof merely because it is `.id` or builds. |
| 2 | If a current fixture disagrees with C0, the fixture is wrong. |
| 3 | Never preserve behavior against the constitution to retain provenance. |
| 4 | Organizational directories (`examples/compile_fail/`) may exist; canonical Idol inside them uses `@corpus current` when they prove current law edges. |
