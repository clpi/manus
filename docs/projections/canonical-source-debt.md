| field | value |
|---|---|
| title | Canonical source debt projection (lib/compiler) |
| status | CURRENT PROJECTION — not language law. |

| # | directive |
|---|---|
| 1 | **Do not treat a direct-build green row as architectural acceptance.** Each module may compile while still carrying bootstrap workaround source. |

| section |
|---|---|
| Construct states |

| # | directive |
|---|---|
| 1 | Every compiler-source construct should be tagged one of: |

| State | Meaning | Agent rule |
|---|---|---|
| **canonical** | Required under current `docs/spec/law.md`; final self-host must retain | Do not rewrite toward host patterns |
| **migratable** | Lawful today but spelling/shape will change; semantics preserved | OK to touch only when migrating to canonical form |
| **debt** | Bootstrap workaround, host transcription, or backend appeasement | Fix realization/graph facts; delete when replacement lands |

| section |
|---|---|
| Module ledger (initial projection) |

| # | directive |
|---|---|
| 1 | Executable reach: `gate/selfhost.sh`. |
| 2 | Authority quality: manual until graph-native audit exists. |

| Module | Physical (direct) | Authority | Notes |
|---|---|---|---|
| `token.id` | varies | migratable | Host token enum bridge |
| `parser.id` | varies | migratable | Retired `type =` / `(typedecl … (type …))` / `alias` keyword; descriptor axis only |
| `bind.id` | blocked / partial | **debt** | Textual binder; not identity-oriented |
| `graph.id` | varies | migratable | AST-shaped producer regions |
| `sema.id` | host | canonical path | Subject-first cross-home must stay fact-driven |
| `comptime.id` | partial | migratable | Removed global C alias — good authority move |
| `rewrite.id` | partial | migratable | Same |
| lowering (Zig) | host | debt | DNIR re-derives types (exprIsStr, recordFieldsPresent) |
| `monolith.id` | probe | **debt by design** | Capability probe only — never compiler B |

| # | directive |
|---|---|
| 1 | Update this table from `gate/selfhost.sh` output, not from static prose elsewhere. |

| section |
|---|---|
| Historical reports |

| # | directive |
|---|---|
| 1 | Any document with frozen counts must carry: |

```text
HISTORICAL — DO NOT USE FOR CURRENT COUNTS
```

| # | directive |
|---|---|
| 1 | Live counts come only from executable projections. |

| section |
|---|---|
| Negative controls |

| # | directive |
|---|---|
| 1 | When editing `lib/compiler/**`, run: |

```sh
sh gate/architecture-negative.sh
sh gate/architecture-companion.sh
```

| # | directive |
|---|---|
| 1 | If the fix required shaping source for an immature backend, tag the change as **debt** here and prefer graph/realization repair. |
