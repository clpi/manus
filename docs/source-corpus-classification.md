# Source corpus classification

Every `.id` file in the active tree that is read by agents or tests must carry
an explicit teaching status in its first four source lines, so an agent cannot
mistake a fixture, migration, or foreign example for canonical Idol.

## Statuses

| status | meaning | examples |
| --- | --- | --- |
| `canonical` | current Idol law; safe to imitate | `gate/subject.id` |
| `compat` | accepted familiar syntax that canonical source avoids | Lua long strings, single-quoted text |
| `fixture` | deliberate negative control or measurement subject | `hash_agreement` intentional `any` tests |
| `foreign` | owned by another source law (C, Lua, Bash, Wasm) | `.duo` / `.duon` bridges |
| `migration` | being removed; do not extend | old `end`/`then` forms |
| `scenery` | supports a test or build but is not language law | census fixtures, harness helpers |

## Marking convention

The first four lines of an `.id` file may contain a comment of the form:

```id
## TEACHING-STATUS: canonical
```

or, with a reason:

```id
## TEACHING-STATUS: fixture — exercises the boxed any boundary
```

`TEACHING-STATUS` must appear in the first four lines. A missing status is a
corpus-status finding until the file is classified.

## Derived defaults (tier 2)

The executed ingress manifest (`docs/spec/corpus.md`, owned by
`lib/compiler/lexer.id` `sourceentry*`) classifies the `examples/` partition
and stops there. Teaching status for the rest of the tree is DERIVED from the
prefix defaults below — same first-match-wins walk, specific before general.
These are TEACHING statuses only: they are not ingress roles, they grant no
source law, and a per-file `## TEACHING-STATUS:` header always overrides
them. Per SOURCE-INFER-ONE, a header that restates its derived default is
debt; write headers only where the finer fact disagrees.

```text
canonical   gate/subject.id
canonical   lib/compiler/
fixture     src/testdata/
fixture     tools/reduce/fixtures/
fixture     tests/
migration   lib/
scenery     gate/
scenery     scripts/
scenery     tools/
scenery     benchmarks/
scenery     explore/
```

`src/testdata/` holds compiler test fixtures, exactly like `tests/`.
There is no row for `out/`, because `out/` no longer exists. It used to hold one
teaching artifact (`gap111_probe3.id`, a name that violates `law.path.name`
twice) beside a tracked prebuilt `idol` binary, and that binary was a documented
false-green oracle — `gaps/GAP-207.md` records a gap being read as superseded
because someone verified it with the stale binary instead of a fresh build. The
gate that read the artifact now writes it inline, exactly as it already wrote
its negative control, so both the fixture and the stale oracle are gone rather
than classified.

`lib/compiler/` is the executed self-host producer (canonical Idol);
`lib/` otherwise is migration distribution — frozen std debt, do not extend;
runners, gates, censuses, and harnesses are scenery; reducers' and plugin
test corpora are fixtures.

KNOWN GAP (for the GAP-145 owner): the ingress manifest's 39 rows leave 471
tracked `.id` files unmatched, so `scripts/audit100.id`'s no-silent-default
census would FAIL today if it could run (it is DNB001-blocked repo-wide).
Teaching status does not repair that; only new `sourceentry` rows do, and
those change source-law admission — an ingress decision, not a
classification one.

## What is not a status

- `historical` — git stores history, the active tree does not
- `legacy` — same as migration
- `retired` — a migration or deleted classification
- `old` — not a status

## Enforcement

`gate/corpus-status.sh` classifies every tracked `.id` file by three tiers —
per-file header override, ingress manifest (mapped: compatibility→compat,
generated→scenery, negative→fixture), derived defaults above — validates
header status words, and fails on any unclassifiable file. Totals and the
status distribution print on every run; the totals live in the runner, not
in prose.
