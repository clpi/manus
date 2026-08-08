# Pass 49 — operational plan

Canonical spec: `docs/plans/duo_sums_protocols_demand.md`
Catalog: `src/pass49_catalog.zig` (schema `pass49-sums-protocols-demand-v1`)
Gate: `src/pass49_gate.zig` — 16 proofs, run by `zig build unit-test`

## Status: Phase 0 (records + gate only)

No compiler behaviour changes yet. The catalog records the pass's claims and the
gate asserts the properties that would be false if the pass had smuggled in a
production, a keyword, or a special case.

## What the gate actually defends

| Proof | Would fail if |
|---|---|
| `no-construct-needs-a-new-carrier` | any construct needed a seventh carrier |
| `cases-are-ordinary-values` | a case were not simultaneously descriptor, value, anchor target, dispatch key |
| `no-match-construct` | a fourth consumption form or `match`/`case`/`switch` appeared |
| `relations-lift-and-stay-overridable` | a lifted relation were built-in rather than a derived projection |
| `representation-is-demand-selected` | branch-only or erased representation stopped being reachable |
| `protocol-composition-is-spread` | protocol composition became an inheritance mechanism |
| `negative-requirements-exist` | protocols could only require, never forbid |
| `four-operations-reuse-existing-machinery` | an operation named no pre-existing machinery |
| `verification-tiers-are-the-usual-three` | protocols got a checking mode of their own |
| `pass48-tail-demand-superseded` | the blessed-binding model survived |
| `both-realizations-exist` | one source edge could not realize both void and consuming |
| `consuming-realization-does-not-duplicate-effects` | demand changed semantics instead of materialization |
| `pinned-boundaries-are-recorded` | a non-propagating boundary went unrecorded |
| `no-result-plumbing-idiom` | `result =` were spelled as canonical |
| `canonical-function-form` | the pass's own examples used `fun`/`function` |
| `demand-gates-survive` | G5 or G6 were dropped |

## Phases

- **Phase 0 (done)** — canonical doc, catalog, gate, test registration.
- **Phase 1** — sum declaration and case identity in sema; cases as frozen
  distinct values; dispatch-table lowering to a branch with an exhaustiveness
  diagnostic.
- **Phase 2** — `satisfies` as a stdlib relation over frozen protocol tables;
  compile-time folding for sealed descriptors; the missing-set diagnostic.
- **Phase 3** — demand-return: void vs consuming realization per call site,
  construction elision, `return_shape: pinned(reason)` in the manifest,
  `@comp.why.return(f, site)`.
- **Phase 4** — representation selection (niche-packed, tag+payload, branch-only,
  erased) driven by observed demand.

## Idiom note

All Pass 49 source is written in canonical value-binding form — `add = (a, b) a + b`.
The repo-wide idiom gate (`zig build idiom-gate`) enforces this at zero across
every `.duo` file, so the pass's examples and the language's own corpus agree.
