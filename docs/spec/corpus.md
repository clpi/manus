# SOURCE-ZERO transition manifest

| # | directive |
|---|---|
| 1 | Temporary deletion manifest for tracked noncanonical `.id` debt. |
| 2 | Not semantic law — `docs/spec/constitution.md` owns classification. |
| 3 | Git stores history; this file lists only **current** deletion actions (`law.zero.history`). |

| # | directive |
|---|---|
| 1 | Canonical project-owned source uses `.id` only. |
| 2 | New canonical `.id` is admitted. |
| 3 | Retained behavior migrates to executed `.id`, proves, then deletes the old noncanonical file. |
| 4 | Obsolete behavior deletes. |
| 5 | Compatibility cases become generated or external conformance material — not in-tree stale source libraries. |

| # | directive |
|---|---|
| 1 | The executable transition rows are owned by `lib/compiler/lexer.id` through `sourceentrycount`, `sourceentryrole`, and `sourceentrypattern`. |
| 2 | Production `sourcefactlaw` / `sourcefactprovenance` consume those rows. |
| 3 | This document does not repeat the roster: a copied list would be a second admission authority. `src/lexer_bridge.zig` only normalizes physical provenance relative to the tree carrying this marker and binds producer-returned names to the temporary host ABI. |

## Executed owner

| # | directive |
|---|---|
| 1 | The following block is the generated/audited projection consumed by the existing corpus tools. `lexer_bridge` mechanically compares every row with the executed producer, so drift fails a test instead of creating a second opinion. |

```text
negative       examples/compile_fail/
negative       examples/native_differential/unsupported/
negative       error_test.id
foreign        examples/native_differential/
generated      lib/token/classify.id
generated      lib/wasm/opcode_lookup.id
generated      lib/wasm/ward_mvp_opcodes.id
foreign        examples/wasm/
compatibility  examples/lua
compatibility  examples/test_lua
canonical      examples/json/
canonical      examples/conversion/
canonical      examples/projection/
canonical      examples/infer/
canonical      examples/demand/
canonical      examples/hash/
canonical      examples/native/
canonical      examples/control/
canonical      examples/nominal/
canonical      examples/layout/
canonical      examples/pack/
canonical      examples/anchor/
canonical      examples/case/
canonical      examples/read/
canonical      examples/boring/
canonical      examples/table/
compatibility  examples/luahost/
foreign        examples/parity/
foreign        examples/host/
foreign        examples/world/
foreign        examples/tailslot/
foreign        examples/shc/
foreign        examples/cfloor/
foreign        examples/benchmark.id
foreign        examples/mandelbrot.id
foreign        vendor/
foreign        test.id
foreign        test2.id
foreign        examples/
```

| # | directive |
|---|---|
| 1 | Roles mean only transition policy: canonical/generated rows use Idol law and canonical provenance; compatibility rows use Lua law and foreign provenance; negative and foreign rows retain their corpus role while source form selects the admitted law. |
| 2 | Unlisted source uses the producer's physical-form projection. |
| 3 | No role grants a world, authority, runtime, or realization. |

| # | directive |
|---|---|
| 1 | Each row is also a TEACHING STATUS under `law.canonicality` (docs/spec/law.md §115): `canonical` rows are the only canonical examples an agent may learn Idol from; `compatibility` is accepted-compatibility, `foreign` is foreign-law material, `generated` is implementation-only, and `negative` rows are fixture-only — intentionally-invalid controls whose spellings exist to be refused, never patterns to follow. |
| 2 | An agent treating a negative or compatibility row as a canonical example is a canonicality violation, and repository frequency has weight zero in language-law inference. |

| # | directive |
|---|---|
| 1 | The roster remains a deletion bridge. |
| 2 | It disappears as project-controlled compatibility and unclassified corpus debt reaches zero and source ingress can receive an explicit law fact directly from its launcher/provider. |

| # | directive |
|---|---|
| 1 | Blockers: `GAP-145`, `GAP-134`, `docs/bootstrap.md`. |
