# Authority repair program

P0 canonicality repair: close the authority projection ambiguities that cause
agents to independently regenerate the same forbidden classes. The semantic
direction is settled; the authoring contract is not yet mechanically total.

## Supreme law already rules

`docs/spec/law.md` is supreme over `docs/spec/constitution.md` (C0),
`docs/spec/agent.md`, `docs/spec/canonical.md`, `CLAUDE.md`, `AGENTS.md`, every
gate, and every copied prompt. Recent additions:

- §111 VOID is not a source descriptor
- §112 SELF-ZERO
- §113 ANY
- §114 BYTES
- §115 CANONICALITY

Where any lower projection diverges from those sections, the projection must be
repaired.

## Canonicality status relation

Every source spelling has exactly one status under a semantic role and source
law:

| status | meaning |
| --- | --- |
| canonical | lawful and preferred in this role and source law |
| accepted-compatibility | lawful for migration, not preferred for new source |
| migration-only | actively being removed from canonical source |
| foreign | owned by a foreign source law (C, Lua, Bash, Wasm, etc.) |
| fixture-only | deliberate negative control or compatibility test |
| implementation-only | a host/compiler implementation artifact, not source law |
| invalid | not lawful in this role |

A status is (spelling, role, source-law) → status, not a global token. The same
spelling can be canonical in one role and invalid in another.

## Closed classes and their owners

| Class | supreme owner | status |
| --- | --- | --- |
| directive @ (`@comp`, `@c`, `@meta`, `@host`, `@runtime`, etc.) | world law §4 | invalid in source |
| world @ (`@x`, `@{ k = v }`, `thing@world`, `thing@{ k = v }`) | world law §4, §5c | canonical |
| `void` source descriptor | §111 | invalid |
| `void` in C/foreign span | foreign law | foreign |
| `self` universal receiver | §112 | invalid |
| `any` existential relation (`xs:any(p)`) | §113 | canonical |
| `any` unconstrained descriptor | §113 | invalid in source; fixture/foreign allowed |
| `bytes` descriptor | §114 | invalid unless C0 amends one |
| byte-sequence value with element/shape facts | §114 | canonical |
| compound identity (`tokenview`, `perfledger`) | LAW-ONE / §16 | invalid |
| qualifier identity (`native`, `dynamic`, `resolved`) | §12 | invalid as identity, fact only |
| role nouns (`reader`, `parser`, `runner`) | §11 | invalid unless genuine domain entity |
| organizational nouns (`util`, `core`, `common`) | §15 | invalid as identity |

## What to do

1. Reconcile `AGENTS.md` and every lower projection against `docs/spec/law.md`.
2. Delete or reclassify any fixture that agents currently imitate as canonical.
3. Use `canon(spelling, role, source-law) -> status` to drive formatters, gates,
   and LSP, not word blacklists.
4. Add canonicality rows only via C0 amendment; never hand-curate another
   forbidden-word list.
