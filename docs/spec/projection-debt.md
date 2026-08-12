# Projection debt classification (PROJECTION-ONE)

Live census snapshot for agent repair. **Classify each site — never bulk
replace** (`law.repair.infer`, `law.repair.class`). Graph removal verdicts
require GAP-124 application records.

Regenerate counts (from repository root):

```bash
idol run scripts/projection_census.id
idol run scripts/infer_census.id
# or bundled:
./tools/node/dev/projectioncensus
```

Application record contract: `docs/spec/application-record.md`.

## Debt classes

| class | pattern | repair | owner |
|---|---|---|---|
| explicit projection | `:to(` | infer when unique (INFER-ONE class A–L) | resolver + graph |
| inverse face | `:from(` in source | `value:to(target)` (FROM-ZERO) | per-site proof |
| std lookup | `std.` in canonical source | reachability fix (STD-ZERO) | home + scope |
| lib lookup | `lib.` in canonical source | same (LIB-ZERO) | home + scope |
| process namespace | `process.` | `command:run()` + world facts (GAP-159) | MCP bootstrap |
| adjective protocol | `: readable` etc. | relation projection constraint | graph |
| codegen reconstruction | literal `"to"` in Zig | relation edge from graph (GAP-082) | Poolside |
| gate teaching | idiomgate `:from(` rule text | keep — ratchet only | Cursor |

## `:from(` sites (canonical source = 0)

All remaining `:from(` hits are **comments, gate rules, or census labels** —
no live canonical conversion uses `:from(`:

| file | role | action |
|---|---|---|
| `examples/conversion/relation.id` | migration comment | keep — documents FROM-ZERO |
| `examples/nominal/measure.id` | historical comment | keep — pre-nominal debt story |
| `examples/compile_fail/relation_lossy_compose.id` | comment only | keep — proof fixture uses `5:to(milli)` |
| `scripts/idiomgate.id` | gate ratchet | keep until graph gate |
| `gates/idiom.id` | gate ratchet | keep until graph gate |
| `scripts/projection_census.id` | census label | keep |

**FROM-ZERO canonical source debt: clear.**

## Top `:to(` debt by file (migration / std-migration)

Highest counts live in `lib/std/*` and benchmark scripts — **std-migration
debt**, not canonical teaching:

| tier | paths | repair class |
|---|---|---|
| std-migration | `lib/std/trace.id`, `lib/std/inspect.id`, … | H — frozen distribution; do not extend |
| script/bench | `scripts/runtime_bench.id`, `scripts/audit100.id`, … | I — bootstrap measurement |
| mcp-agent | `tools/mcp/shared.id` (~11 `:to(`) | J — GAP-159 process/run migration |
| gate | `scripts/idiomgate.id`, `gates/idiom.id` | K — ratchet rules mentioning patterns |
| canonical-teaching | `examples/conversion/*`, `examples/projection/*`, … | verified — must match C0 |

## `process.*` namespace (GAP-159)

Bootstrap MCP and ingest still spell `process.run`, `process.capture`, etc.
Idiomgate blocks **new lines**; graph migration replaces with `run` relation +
world witness. Do not bulk-edit `tools/mcp/shared.id` without per-call world proof.

## Corpus tagging (GAP-161 interim)

| partition | tag | status |
|---|---|---|
| `examples/conversion/*`, `examples/projection/*`, … | `@corpus current` | tagged |
| `examples/compile_fail/*` | `@corpus current` | tagged |
| retired `examples/concept_introspect.id` | removed | foreign corpus deleted |
| retired `examples/metatable_class_semantics.id` | removed | foreign corpus deleted |

Gate: `tools/node/dev/corpuscensus`.

## Next repair steps

| step | work | blocked |
|---|---|---|
| 4 | application record in resolver | GAP-124 implementation (spec + bootstrap catalog done) |
| 5 | expected descriptor + result demand inference | GAP-124 |
| 6 | semantic canonicalization for redundant `:to(` | GAP-124 + step 5 |
| 11–12 | remove canonical std/lib source lookup | home reachability GAP-153 |
