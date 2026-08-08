> **HISTORICAL — superseded by `docs/spec/pass100.md`. Not an architecture input.**

# Pass 48 — operational plan (the consolidation)

Canonical spec: `docs/archive/duo_canonical_specification.md`
Catalog: `src/pass48_catalog.zig` (schema `pass48-canonical-spec-v1`)
Gate: `src/pass48_gate.zig` — 17 proofs, `zig build pass48-gate`

## Status: Phase 0 (records + gate only)

Pass 48 folds Passes 34–47 into one authoritative grammar, semantic model, idiom
canon and SHC contract. Its authority rule is the thing the gate checks hardest:

> Where any prior pass conflicts with this document, this document wins **and the
> conflict is a supersession to record**. Where this document is silent, the
> source pass remains normative.

A consolidation that silently overrode its sources would be worse than none, so
`proveAuthorityRuleRequiresRecording` fails unless both halves are stated.

## Cross-pass agreement is enforced, not assumed

The real risk in a consolidation is not being wrong alone — it is drifting from
the documents it claims authority over. Five proofs import Pass 49 and Pass 52
directly:

| Proof | Checks against |
|---|---|
| `shc-families-use-identical-machinery` | every Pass 52 hook family is a known relation family |
| `conflicts-classify-never-last-write-wins` | Pass 52's hook conflict rule |
| `canonical-function-form-agrees-across-passes` | Passes 48/49/52 state the same form |
| `g3-carries-the-demagicking-test` | Pass 52's de-magicking test still names side registries |
| `demand-gates-agree-with-pass49` | G5/G6 present in both catalogs |

**This already paid.** `shc-families-use-identical-machinery` failed on first run:
§2.6 lists the SHC families as `lower validate canonicalize realize rewrite
measure`, but §2.8 names `derive` and `observe` as extension points and Pass 52
builds its whole hook algebra on them. The two lists in the same document
disagreed. Consolidated in the catalog with the discrepancy noted.

## What else the gate defends

`ten-axioms-present` and `nns-axiom-is-stated` (A2 is what every other pass leans
on when claiming zero new grammar) · `operator-inventory-matches-graveyard`
(`!=` in, `~=` buried — matching the 950 sites the repo migrated) ·
`at-is-position-disambiguated` (prefix staging vs postfix anchoring never
collide) · `ladder-is-eight-rungs-in-order` (rung numbers are load-bearing; G6
says hot paths live at rung 3) · `false-blocks-and-nil-does-not` (collapsing them
would erase "forbidden here" vs "no local decision") · `ten-idioms-in-order` ·
`ten-gates-present` · `registries-are-forbidden-architecture` ·
`bootstrap-lifecycle-is-five-states` (the self-hosting matrix uses these names) ·
`graveyard-covers-enforced-idioms` (the six the repo enforces at zero).

## Phases

- **Phase 0 (done)** — canonical doc, catalog, 17-proof gate, cross-pass checks.
- **Phase 1** — supersession ledger: every Pass 34–47 conflict recorded as a
  typed entry, so "this document wins" is auditable rather than asserted.
- **Phase 2** — G1/G4/G7/G8/G10 as executable build gates over the SHC corpus.
- **Phase 3** — the representation and idiom/leverage manifests as build artifacts.
