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

## What is not a status

- `historical` — git stores history, the active tree does not
- `legacy` — same as migration
- `retired` — a migration or deleted classification
- `old` — not a status

## Enforcement

`gate/corpus-status.sh` scans `examples/`, `gate/`, `lib/`, `scripts/`,
`tools/**/*.id` and reports the count and identity of unclassified `.id` files.
The gate's total is pinned in the runner, not in prose.
