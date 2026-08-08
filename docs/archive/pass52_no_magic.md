> **HISTORICAL — superseded by `docs/spec/pass100.md`. Not an architecture input.**

# Pass 52 — operational plan

Canonical spec: `docs/archive/duo_no_magic.md`
Catalog: `src/pass52_catalog.zig` (schema `pass52-no-magic-v1`)
Gate: `src/pass52_gate.zig` — 16 proofs, `zig build pass52-gate`

## Status: Phase 0 (records + gate only)

## Why the catalog can express failure

`Justification` has three values — `user_definable`, `relation_family`,
`side_registry` — and only the first two pass. The third exists so a violation is
*representable*: a catalog that cannot express failure proves nothing about the
gate it claims to enforce. `proveEveryStdNameIsJustified` is therefore a real
check, not a tautology.

## What the gate defends

| Proof | Would fail if |
|---|---|
| `every-std-name-is-justified` | any std name were a side registry |
| `classification-matches-justification` | a semantics-answering name were justified as merely user-definable — magic in disguise |
| `no-third-category` | the binary classification grew a third case |
| `satisfies-is-deleted` | the primitive survived, **including in the Pass 49 catalog** |
| `graveyard-names-the-deletion` | the deletion were not recorded where future work looks |
| `three-faces-of-one-fact` | satisfaction grew machinery of its own |
| `homomorphism-distributes-both-ways` | the failure path (missing-sets union) went unstated |
| `every-hook-is-inspectable` | a hook could not be enumerated by trie reflection |
| `compiler-ships-its-own-edges` | "browsable as data" were an empty claim |
| `hook-algebra-is-complete` | override/block/remove/inject were not all trie operations |
| `no-last-write-wins-and-always-witnessed` | conflicts resolved by last write, or edges went unwitnessed |
| `plugin-shapes-are-buried` | plugin APIs / callback registries / macro hooks survived |
| `algebra-is-stated` | the monoid or the homomorphism went unstated |
| `point-free-boundary-holds` | implicit-parameter lambdas were readmitted |
| `anchored-bundles-preferred` | hand-built dictionaries were idiomatic — reintroducing dictionary passing |
| `canonical-function-form` | the pass's own examples used `fun`/`function` |

## Cross-pass amendment

Pass 52 supersedes Pass 49 §2. `src/pass49_catalog.zig` is amended: OP-01 now
reads `Point@ordering`, OP-02 `descriptors:filter((d) d@ordering)`, and SUP-04
records the deletion. `proveSatisfiesIsDeleted` imports the Pass 49 catalog and
fails if the primitive reappears there — the two passes cannot drift apart
silently.

## Phases

- **Phase 0 (done)** — canonical doc, catalog, gate, cross-pass amendment, tests.
- **Phase 1** — `@` distribution over constraint tables in sema; bundle
  construction; missing-set diagnostics with counterexamples.
- **Phase 2** — `has`/`get` as relation families with derivable, blockable edges.
- **Phase 3** — hook families (`derive`, `rewrite`, `lower`) as inspectable
  tries; the compiler ships its own edges; `derive[eq]` enumerable in-language
  as a conformance fixture.
- **Phase 4** — law-licensed `rewrite` fusion with witnesses and suppression.
