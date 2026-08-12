# Corpus role classification (GAP-161)

Machine-visible roles for `.id` and teaching surfaces. Not semantic law — projection
of `law.source.not.proof`.

## Roles

| Role | Agent retrieval | Meaning |
|---|---|---|
| `canonical` | include default | teaches current Idol |
| `verified` | include with label | spec100/generated projection of C0 — fixture wrong if disagrees with C0 |
| `foreign` | exclude default | Lua/host/other lawset |
| `compat` | exclude default | compatibility spelling |
| `history` | exclude default | historical ontology (metatable, concept, etc.) |
| `migration` | exclude default | debt being ratcheted down |
| `generated` | exclude default | harness/config output |
| `proof` | include with label | proves one edge; not teaching vocabulary |
| `bootstrap` | exclude default | MCP/gate transport until decomposed |

## Marking (interim until GAP-124)

First line of `.id` file:

```id
# @corpus verified
# @corpus history
# @corpus proof
```

Agent MCP search should filter on `@corpus` tag. Files under `examples/spec100/`
default to `@corpus verified` unless tagged otherwise.

## Rules

- If spec100 fixture disagrees with C0: **fixture is wrong**.
- Never preserve spec100 behavior against constitution.
- Canonical agent search excludes `foreign compat history migration generated bootstrap`
  unless explicitly requested.
