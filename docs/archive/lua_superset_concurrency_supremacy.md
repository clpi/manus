> **HISTORICAL — superseded by `docs/spec/pass100.md`. Not an architecture input.**

# Lua Superset & Concurrency — Index

> **Authority:** [`pass24_execution_concurrency_lua_supremacy.md`](pass24_execution_concurrency_lua_supremacy.md)  
> This file is a navigational index only. Do not treat it as the design source.

Pass 24 is the **full design constitution** for:

- **Call architecture** — `a` is a value; `a()` / `a x` invoke; command context is explicit  
- **Lua superset maximization** — long strings, accepted Lua syntax, deprecation threshold  
- **Execution-graph concurrency** — `@spawn`, `@all`, `@race`, `@parallel`, streams, elimination, Go-class performance model  

## Quick links

| Artifact | Role |
| --- | --- |
| [`pass24_execution_concurrency_lua_supremacy.md`](pass24_execution_concurrency_lua_supremacy.md) | Full pass (philosophy, syntax, lowering, tooling, examples, rejected alternatives) |
| [`docs/catalogs/lua_superset_compatibility.md`](../catalogs/lua_superset_compatibility.md) | Human-readable compatibility matrix |
| [`src/pass24_catalog.zig`](../../src/pass24_catalog.zig) | Machine-readable workstreams + gates |
| [`src/lua_superset_catalog.zig`](../../src/lua_superset_catalog.zig) | Syntax classification + P0–P9 priorities |
| [`src/lua_superset_corpus.zig`](../../src/lua_superset_corpus.zig) | Parse/lex compatibility corpus (P1) |

## Validate

```bash
zig build pass24-gate          # full Pass 24 gate (includes lua superset P0)
zig build lua-superset-gate    # alias
duo catalog | jq '.pass24'
```

## Non-negotiable reminders

1. `[[ ... ]]` is Lua long-string syntax — never shell conditionals.  
2. Bare `a` does **not** mean `a()` — functions are first-class values.  
3. Canonical Duo ≠ exclusive; Lua forms remain valid permanently unless superset exception documented.  
