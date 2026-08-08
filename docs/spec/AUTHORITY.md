# Epoch 2 — what is law in this repository

**Pass 100 (Duo 0.1) is the sole living semantic authority.** `CLAUDE.md` is
its operative summary and is what agents read.

## The problem this file exists to fix

An external audit of tip `8e1e45c` found the repository's sources of truth had
NOT converged on Pass 100 even though the implementation was moving toward it:

> the implementation is moving toward Pass 100 faster than the repository's
> sources of truth are converging around it ... old mechanisms, old
> specifications, compatibility machinery, pass-shaped scaffolding, and the new
> graph-native direction all coexist as partially authoritative systems.

Measured at the time of writing: **47 tracked `docs/plans/pass*.md` documents,
and zero files mentioning Pass 100.** `CLAUDE.md` still carried the Pass 64
contract. Every agent reading this repository was learning superseded law, which
is why retired concepts kept being reintroduced — the searchable context taught
them.

## The rule

Everything under `docs/archive/` is **HISTORICAL EVIDENCE**. They record how the
design arrived where it is. They are NOT architecture inputs, and nothing may
cite them as authority.

Those 59 documents used to sit in `docs/plans/`, whose name taught every search
that they were live. They were moved with `git mv` (history preserved), each
stamped `HISTORICAL — superseded by docs/spec/pass100.md`, and indexed in
`docs/archive/README.md`. `docs/spec/README.md` carries the precedence rule.

Refusal protocol: if a rule you would cite appears only in an archived pass,
your objection is void. Comply with Pass 100 and repair toward it. Genuine
epoch-2 conflicts cite the rule ID, use the canonical spelling, and proceed.

## What is still owed

The audit's P0 list:

- [x] Pass 100 named as sole authority; `CLAUDE.md` regenerated to epoch 2
- [x] the spec itself committed at `docs/spec/pass100.md` (it was referenced but absent)
- [x] `audit100` built from the deny table so the spec becomes executable pressure
      (`zig build audit100`, `scripts/audit100.duo`)
- [x] every `.duo` corpus file classified
      canonical / compatibility / foreign / negative / historical / generated,
      so deny-greps can reach literal zero on the canonical set without
      rewriting deliberate compatibility fixtures (`docs/spec/corpus.md`)
- [x] superseded pass documents removed from the search path: 59 moved
      `docs/plans/` → `docs/archive/`, stamped, indexed, precedence rule written
- [ ] tracked session/agent state removed; `.agents/AGENT_COORDINATION.md` is
      4619 lines of mutable markdown acting as a control plane
- [ ] `@`-directive ontology replaced by graph/world facts (`ast.Attribute`,
      `has_*_attr`, layout attrs, `@comp.*` parsing all still structural)
- [ ] stable semantic identity across scope/module/codegen — textual names are
      still doing semantic-identity work, which is the root of a whole family
      of current bugs
- [ ] concept/generic/overload/method registries collapsed into trie + relations
- [ ] offside parsing + canonicalizer (not optional-`end` lookahead hacks)

`§22` of Pass 100 says "Running: nothing." That is now too conservative in
places and inconsistent in others; the replacement is a GENERATED capability
table — described → parsed → semantically checked → C path → direct-native →
differentially proven → canonical — populated from the native differential
corpus rather than asserted.
