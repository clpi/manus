# Pass 25 — Semantic Unification Index

> **Authority:** [`pass25_native_semantic_unification.md`](pass25_native_semantic_unification.md)

Pass 25 reconciles descriptor construction, lifetimes, views, ownership, return realization, and bidirectional metaprogramming into one model — without fragmenting the language.

## Related passes

| Pass | Relationship |
| --- | --- |
| [Pass 23](pass23_unified_metaprotocols.md) | Metaprotocols, function syntax, return consumption (open lifetime/borrow → Pass 25) |
| [Pass 24](pass24_execution_concurrency_lua_supremacy.md) | Calls, Lua superset, concurrency; views compose with `@all` / `@parallel` |
| [Pass 22](pass22_compiler_architecture_expansion.md) | Semantic graph, transformations, delta compilation |
| [Pass 20](pass20_universal_metaprogramming_harness.md) | Foreign snapshots, provenance-linked output |

## Machine-readable

| Artifact | Path |
| --- | --- |
| Catalog | `src/pass25_catalog.zig` |
| Gate | `src/pass25_gate.zig` |
| Semantic categories | `src/pass25_semantic_category.zig` |
| Lifetime model | `src/pass25_lifetime_model.zig` |
| Projection model | `src/pass25_projection_model.zig` |
| Tail-demand / result lineage | [`pass25_tail_result_demand.md`](pass25_tail_result_demand.md), `src/pass25_tail_result_model.zig` |

## Validate

```bash
zig build pass25-gate
duo catalog | jq '.pass25'
```
