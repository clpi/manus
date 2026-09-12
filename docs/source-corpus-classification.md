| field | value |
|---|---|
| title | source-corpus-classification |

| section |
|---|---|
| statuses |

| status | meaning | examples |
| --- | --- | --- |
| `canonical` | current Idol law; safe to imitate | `gate/subject.id` |
| `compat` | accepted familiar syntax that canonical source avoids | Lua long strings, single-quoted text |
| `fixture` | deliberate negative control or measurement subject | `hash_agreement` intentional `any` tests |
| `foreign` | owned by another source law (C, Lua, Bash, Wasm) | `.duo` / `.duon` bridges |
| `migration` | being removed; do not extend | old `end`/`then` forms |
| `scenery` | supports a test or build but is not language law | census fixtures, harness helpers |

| Derived defaults |
|---|
```text
canonical   gate/subject.id
canonical   lib/compiler/
fixture     src/testdata/
fixture     tools/reduce/fixtures/
fixture     tests/
fixture     test/
migration   lib/
scenery     gate/
scenery     scripts/
scenery     tools/
scenery     benchmarks/
scenery     explore/
```

| section |
