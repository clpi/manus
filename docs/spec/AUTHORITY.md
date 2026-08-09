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

The archive is **DELETED** (Pass 121 owner directive: archival material is
deleted or not considered). Git history records how the design arrived where it
is. It is NOT an architecture input, and nothing may cite it as authority.

Moving those documents out of `docs/plans/` reduced their pull but did not remove
it: a stamped file is still a file grep reaches, and this repository measured the
consequence — a CI gate cluster that spent months mechanically defending prefix-@
and the Lua-superset doctrine, both retired law, because the searchable text
taught them. Deletion is the only version of this rule that holds.

Those 59 documents used to sit in `docs/plans/`, whose name taught every search
that they were live. They were moved with `git mv` (history preserved), each
stamped `HISTORICAL — superseded by docs/spec/pass100.md`, and indexed in
git history. `docs/spec/README.md` carries the precedence rule.

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
      `docs/plans/` out of the search path, then DELETED outright
- [x] tracked session/agent state removed; `.agents/AGENT_COORDINATION.md` went
      4619 lines → 102 (subsystem/owner map, gate table, four protocol rules).
      The original is frozen verbatim at
      `docs/history/agent-coordination-2026-07-to-08.md`, historical evidence
      on the same footing as the deleted archive. The five MCP write sites that
      grew it now target the gitignored `.agents/session/`; reducing the
      document without moving the writers would have regrown it in a week
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

## blocks-passing/blocks-total now has a reading (2026-08-08)

§19 lists it as a metric and §22 calls it "the project's first honest number".
It was never computed. `zig build spec-corpus` computes it, and reports a
second number beside it:

- **blocks** — §20's five golden files, EXTRACTED from `docs/spec/pass100.md`
  on every run and checked verbatim. No tracked copy exists, because a tracked
  copy of the spec's own text is a second source of truth whose drift is
  invisible. Each failing block prints its exact diagnostic, so the report is
  the ordered work list and not a score.
- **forms** — one fixture per §20 construct in `examples/spec100/`, each
  printing a value the fixture itself declares. This is the number that moves
  while a block is still red. It is checked BY VALUE: the guard-chain fixture
  compiles under either reading of `while b = f() and p(b)` and only the
  printed total distinguishes them.

Both ratchet from the measured baseline. Do not transcribe the numbers here —
read them from a run, for the same reason §22's repository note gives.

`gaps/GAP-025.md` carries the measured table: which block, which diagnostic,
which construct, and three SPEC DEFECTS the corpus revealed about itself
(a shebang below a comment; two `for` clauses nested on one line against §6;
and two `audit100` deny rows that convict §20's own text).

This does not replace `audit100`. That gate counts deny lines over the
canonical corpus and is the LAGGING measure — how much old code still spells
things the old way. `spec-corpus` is the LEADING one: whether the new spelling
exists at all. §3 tells agents to pattern-match only from §20, so a block that
does not compile is an instruction to write source the compiler rejects.
