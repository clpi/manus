# Compiler source debt projection (`lib/compiler/**`)

**Disposition:** research / audit projection — not semantic law.

Every construct in self-host compiler source must be classified before agents
treat a green module as architectural progress.

## Classification legend

| Class | Meaning |
|---|---|
| **canonical** | Required by current law; must survive compiler B |
| **compatibility** | Migrating spelling or bridge; delete when successor lands |
| **bootstrap-debt** | Temporary executable bridge; must carry deletion witness |
| **probe** | Diagnostic slice; never compiler-B architecture |
| **historical** | Superseded or wrong-but-green; do not copy patterns |

**Rule:** direct self-host green proves **physical reach**, not **authority quality**.

## Seed compiler modules (initial projection)

| Module | Class | Notes |
|---|---|---|
| `lexer.id`, `token.id` | bootstrap-debt → canonical target | GAP-145 lexical authority closure |
| `parser.id` | bootstrap-debt | Host recognition still owns production path |
| `bind.id` | bootstrap-debt | Textual name/token scan; destination = occurrence ids |
| `graph.id`, `application.id` | canonical | Must become sole semantic spine |
| `monolith.id` | **probe** | Capability probe only — not B composition |
| `_*.id`, `out/*` probes | probe | Scratch; never canonical surface |

## Agent obligations

1. Before changing `lib/compiler/**` for direct-backend limits, answer:
   **source violates law** vs **backend lacks lawful capability**.
2. Do not expand monolith to "get B" — B must use real homes/bindings/worlds.
3. Do not treat bind.id green as graph-native resolution.
4. Record new bootstrap debt in the owning `gaps/GAP-*.md` with deletion condition.
