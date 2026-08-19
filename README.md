# Idsem

Idsem is the language and project: public command identity `idsem`, canonical
source suffix `.id`. The executable is still spelled `bin/idol` and the
repository remote `idollang/idol` — bootstrap-bridge host identifiers retained
until their own deletion gates; the former name Idol is historical Git
provenance, not current identity. One durable semantic identity space:

```text
source/import -> graph -> demand -> realization -> machine
```

Semantic identity persists while representation specializes. Bounded bootstrap
bridges may remain only while executed with known deletion conditions
(`law.bridge.death`, `docs/bootstrap.md`).

## Current State

The repository is at bootstrap stage S0. The production Idsem lexer owns the
legacy token-kind/content/span projection; canonical lexical identities remain
open in `GAP-145`. Parser recognition is still host-owned: no compiler B or
production `idol` binary exists. The exact current ownership,
blockers, and measured aggregate outcome live in
[`docs/bootstrap.md`](docs/bootstrap.md); do not infer progress from file counts
or generated artifacts.

`GAP-131` makes the session-start P0 count unknown. An authority-independent
scan is exposed by `tools/node/dev/orient`; a fresh session must inspect every
matching record under `gaps/GAP-*.md` directly rather than trust a zero, copied
count, or this snapshot after the tree changes.

The path to the first compiler B is:

```text
lexical identity
-> generated grammar roles
-> immutable token view
-> executed Idsem parser recognition
-> binding and scope
-> graph and application
-> demand
-> realization and machine
-> compiler B
-> B builds C
```

## Source

Canonical Idsem is deliberately compact while its semantic graph remains
compositional:

```id
main: i64 = ()
    0
```

New source uses `.id`, offside bodies, lowercase one-word native identities,
double-quoted text, single-quoted bytes, and `#` comments. The exact law is
[`docs/spec/constitution.md`](docs/spec/constitution.md). It is structured law
documentation, not executable source or an implementation template.

`std` is migration distribution, not semantic architecture. `std.script` is
frozen debt. New native meaning belongs to admitted relations, subject values,
world facts, demand, and realization, never to a new `std.*` API or replacement
universal namespace.

## Build And Evidence

The bootstrap executable is `./zig-out/bin/idol` (`idol check`, `idol run`). Build the seed transport with:

```bash
zig build
```

Then canonical source can be checked:

```bash
./zig-out/bin/idol check main.id
```

Use repository-locked gates for evidence. Process completion, a focused fixture,
or the existence of an `.id` file does not prove semantic ownership. Known red
aggregate results remain red until the exact current-tree gate passes.

## Orientation

Agents and contributors start at [`AGENTS.md`](AGENTS.md). It routes to the one
law, current bootstrap ledger, live claims, gaps, and validation protocol.
Historical pass documents and compatibility source are evidence only.

Useful current projections:

- [`docs/spec/AUTHORITY.md`](docs/spec/AUTHORITY.md) - authority and conflict protocol
- [`docs/AGENT_ALIGNMENT.md`](docs/AGENT_ALIGNMENT.md) - current priority compass
- [`docs/bootstrap.md`](docs/bootstrap.md) - executed production ownership
- [`docs/performance.md`](docs/performance.md) - measured performance ledger
