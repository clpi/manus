# Projection debt classification (PROJECTION-ONE)

| # | directive |
|---|---|
| 1 | Live census snapshot for agent repair. **Classify each site — never bulk replace** (`law.repair.infer`, `law.repair.class`). |
| 2 | Graph removal verdicts require GAP-124 application records. |

| # | directive |
|---|---|
| 1 | Regenerate counts (from repository root): |

```bash
idol run scripts/census/projection.id
idol run scripts/census/infer.id
# or bundled:
./tools/node/dev/projectioncensus
```

| # | directive |
|---|---|
| 1 | Application record contract: `docs/spec/application-record.md`. |

## Debt classes

| class | pattern | repair | owner |
|---|---|---|---|
| explicit projection | `:to(` | infer when unique (INFER-ONE class A–L) | resolver + graph |
| inverse face | `:from(` in source | `value:to(target)` (FROM-ZERO) | per-site proof |
| std lookup | `std.` in canonical source | reachability fix (STD-ZERO) | home + scope |
| lib lookup | `lib.` in canonical source | same (LIB-ZERO) | home + scope |
| adjective protocol | `: readable` etc. | relation projection constraint | graph |
| codegen reconstruction | literal `"to"` in Zig | relation edge from graph (GAP-082) | Poolside |
| gate teaching | `gate/idiom.id` `:from(` rule text | keep — law/ratchet text; direct run DNB001-blocked | graph-owned admission |

## `:from(` sites (canonical source = 0)

| # | directive |
|---|---|
| 1 | All remaining `:from(` hits are **comments, gate rules, or census labels** — no live canonical conversion uses `:from(`: |

| file | role | action |
|---|---|---|
| `examples/conversion/relation.id` | subject-first `to` | keep — FROM-ZERO teaching |
| `examples/nominal/measure.id` | historical comment | keep — pre-nominal debt story |
| `examples/compile_fail/relation_lossy_compose.id` | comment only | keep — proof fixture uses `5:to(milli)` |
| `gate/idiom.id` | gate ratchet | keep until graph gate |
| `scripts/census/projection.id` | census label | keep |

| # | directive |
|---|---|
| 1 | **FROM-ZERO canonical source debt: clear.** |

## Top `:to(` debt by file (migration / std-migration)

| # | directive |
|---|---|
| 1 | Highest counts live in `lib/*` and benchmark scripts — **std-migration debt**, not canonical teaching: |

| tier | paths | repair class |
|---|---|---|
| std-migration | `lib/trace.id`, `lib/inspect.id`, … | H — frozen distribution; do not extend |
| script/bench | `scripts/runtime_bench.id`, `scripts/audit100.id`, … | I — bootstrap measurement |
| gate | `gate/idiom.id` | K — ratchet rules mentioning patterns |
| canonical-teaching | `examples/conversion/*`, `examples/projection/*`, … | verified — must match C0 |

## Corpus tagging (GAP-161 interim)

| partition | tag | status |
|---|---|---|
| `examples/conversion/*`, `examples/projection/*`, … | `@corpus current` | tagged |
| `examples/compile_fail/*` | `@corpus current` | tagged |
| retired `examples/concept_introspect.id` | removed | foreign corpus deleted |
| retired `examples/metatable_class_semantics.id` | removed | foreign corpus deleted |

| # | directive |
|---|---|
| 1 | Gate: `tools/node/dev/corpuscensus`. |

## Next repair steps

| step | work | blocked |
|---|---|---|
| 4 | application record in resolver | GAP-124 implementation (spec + bootstrap catalog done) |
| 5 | expected descriptor + result demand inference | GAP-124 |
| 6 | semantic canonicalization for redundant `:to(` | GAP-124 + step 5 |
| 11–12 | remove canonical std/lib source lookup | home reachability GAP-153 |
