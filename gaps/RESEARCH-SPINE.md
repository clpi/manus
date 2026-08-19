# RESEARCH-SPINE — C0 alignment of the research GAP set

**Status:** OPEN · **Filed:** 2026-08-18
**Kind:** research_gap projection · **Normative for:** nothing — this is a projection of C0
**Enforced by:** `tools/node/dev/gapc0` (fails closed)

C0 (`docs/spec/constitution.md`) is the sole semantic law. §14 closes the semantic
kind set; §15 pins the mechanism delta to zeros; `law.injection.only` reserves
`@{ … }` for world injection. A research GAP that needs a new kind, registry,
syntax, keyword, or operator to mean what it says is not a GAP — it is a
constitutional amendment request, and it must say so instead of drifting.

This file states, once, the admission test and the field semantics every
research GAP (GAP-175 onward) carries inline. Each GAP's `## C0 alignment`
block is a per-GAP instance of the schema defined here.

## The admission test

For every frontier idea, the question is never *"should Idol add a context /
solver / rule / future / pattern / continuation subsystem?"* It is:

> Which **existing** semantic identities and facts already express the
> underlying meaning, and which **physical mechanism** realizes it?

## Structural mapping

Research capability must not become a new subsystem; it becomes facts over
existing semantic owners (converged from docs/research-gap-admission.md, which
this spine replaces — one admission program, one census):

| Research capability | Do not introduce | Idol-native semantic owner | Physical/optimization consequence |
| --- | --- | --- | --- |
| abstract interpretation | analysis framework as semantic subsystem | facts qualifying id, produced by relation, justified by witness/trust/provenance | common refinement engine |
| range/congruence/shape/alias | separate analysis ontologies | descriptor/relation/value facts | specialization, bounds deletion, layout |
| information order | Information kind | demand + descriptor facts + witness | compute only distinguishable information |
| observer quotient | observer object hierarchy | demand facts describing required distinction | legal quotient-specific reductions |
| change/delta | reactive subsystem | derivative/change facts on relation | incremental compile, AD, streaming |
| persistent equivalence | second semantic graph | witnessed relation between existing ids | e-graph/search/validation index |
| lower-bound knowledge | optimizer metadata ontology | witness + provenance qualifying realization/problem | distance-to-floor optimization |
| value of information | profiling subsystem | demand, trust, witness, realization facts | decide whether learning a fact pays |
| runtime guard | JIT-specific concept | conditional witness under an effectful relation | specialized realization + invalidation |
| foreign-language support | separate compiler IR | origin/law/provenance + ordinary semantic ids | foreign code enters same semantic universe |
| FFI | wrapper/API kingdom | representation relation + witness | zero-copy/delete adapter |
| context | new Context kind | facts on world / relevant ids | stage/target/revision/place specialization |
| solver | Solver semantic kind | realization of an obligation/relation | SAT/SMT/interval/direct code interchangeable |
| CHR rule | new Rule language | ordinary relations that publish/refine facts | fixed-point inference |
| optimizer space | semantic Space object | derived world / graph incarnation / projection | speculative search without mutating authority |
| determinacy | Future/Promise objects | fact on semantic id | dependency/wakeup realization |
| mode | mode types | facts on relation slots | forward/backward/dataflow execution |
| solution cardinality | iterator/generator ontology | relation/application cardinality facts | first/all/any/count change algorithm |
| pattern | Pattern type system | ordinary relation with search/capture/update facts | DFA/NFA/parser/query/rewrite realizations |
| continuation | continuation object kingdom | semantic id + relation/lifetime/effect facts | branch/frame/state machine/persistent cont |
| recovery | exception hierarchy | obligation + available recovery relations | inline restart/result/unwind/trap |
| concurrency | Task/Actor/Future kingdoms | causality/effect/world relations | schedule/queue/network/direct call |
| hardware target | target-specific language subsystem | world/capability/realization | CPU/GPU/FPGA/CHERI etc. |

The canonical rewordings this test has already produced:

| retired research wording | Idol-native wording |
|---|---|
| "define `Context`" | qualify world/id with contextual facts; amend C0 only if existing kinds are provably insufficient |
| "add a solver registry" | project applicable solver realizations from relation/domain/witness facts; a physical index may accelerate the projection |
| "define `Rule`" | an ordinary inference relation whose application publishes/refines facts |
| "`Space` semantic object" | a derived world / graph incarnation used as a temporary search projection |
| "deterministic producer class" | a relation/application fact describing determinacy |
| "`Pattern` kind" | an ordinary relation with mode/cardinality/span/update facts |
| "`Continuation` kind" | an ordinary id with resumption/lifetime/effect facts |
| "foreign semantic fact format" | the same graph fact format as native semantics; origin/law qualifies it |
| "cross-law optimizer" | the ordinary optimizer consuming witnessed equivalence across origins |

Solver realization discharges an obligation. CHR saturation schedules ordinary
relations over facts. Optimizer spaces are derived worlds. Futures are
unresolved ids. Patterns are relations. Continuations are ids with resumption
facts. Foreign interfaces are representation/equivalence proofs. JIT guards are
runtime evidence. Stages are world/context facts. AD is change. Incremental
compilation is change. Concurrency is causality. Hardware is realization.
Complexity theory is evidence about the reachable floor. Agents are untrusted
producers of candidate facts/witnesses — never authorities.

## Schema fields (defined once; instantiated per GAP)

- **constitutional owners** — the existing C0 kinds that own the meaning.
- **kind delta** — must be `0`. A nonzero value is a constitutional amendment
  request and fails `gapc0` until C0 itself is amended.
- **registry delta** — must be `0`. Physical `index`/`cache` roles are lawful;
  semantic registries are not.
- **source syntax delta** — `0` by default. If a face is genuinely needed, name
  the existing face it reuses.
- **semantic invariant** — the new fact/law that becomes expressible, stated
  over existing kinds.
- **physical mechanism** — candidate implementation only; never semantic
  authority.
- **prerequisites** — exact upstream GAPs.
- **foreign implication** — which boundary this can erase or constrain, and
  under what witness.
- **world implication** — authority/context impact.
- **projection implication** — impact on projection/injection/interjection/
  update.
- **demand implication** — new quotient/cardinality behavior.
- **realization implication** — the candidate-set expansion or deletion. This is
  the performance consequence; a reconciliation with none is scenery.
- **evidence** — the measurement, proof, or refusal that closes or refutes.
- **deletion witness** — the old subsystem, bridge, or spelling that disappears
  when this lands.

## Dependency architecture

```
                 P0 SEMANTIC SPINE
                     GAP-187
                  mode / solution
                       │
             ┌─────────┴─────────┐
             │                   │
        GAP-175             GAP-176 ← GAP-179
       fact algebra      information/demand
             │                   │
             └─────────┬─────────┘
                       │
                   GAP-177
                 change/delta
                       │
              ┌────────┴────────┐
              │                 │
          GAP-178           GAP-186
       equivalence        bidirectionality
              │                 │
              └────────┬────────┘
                       │
              GAP-180/181/182
           floor/frontier/experiments
                       │
          ┌────────────┴────────────┐
          │                         │
     GAP-183/184/185           GAP-188/189
  foreign/fusion/hardware    pattern/recovery
          │                         │
          └────────────┬────────────┘
                       │
                   GAP-195
                contextual eduction
                       │
                  GAP-196
             constraint realization
                       │
                  GAP-197
               fact saturation
                       │
                  GAP-198
             determinacy-first search
                       │
                  GAP-199
           transactional search worlds
                       │
                  GAP-200
         unresolved-id synchronization
```

GAP-179 (observer quotient) is the compilation-phase face of GAP-176 and sits
beside it. No new research GAP is filed until its block exists and its place in
this graph is stated.

## Horizons

- **H0 — authority repair.** C0 internal contradictions; GAP wording that
  violates §14/§15; this spine. Landed 2026-08-18.
- **H1 — compiler B critical path.** GAP-145 → GAP-134 → parser authority
  transfer → binding → exact graph → demand → one representation decision →
  realization → B. Research architecture must never substitute for this path.
- **H2 — semantic substrate.** GAP-187 + 175 + 176 + 177 + 178; the algebra
  later research depends on.
- **H3 — exploitation frontier.** GAP-179–200 + foreign fusion + complexity /
  lower bounds + hardware, solver, and search research.

Research GAPs are meanings awaiting owners that already exist. The bootstrap
frontier (S0: executed lexer boundary; parser and later stages host-owned) is
the path that makes them real; 200 specified capabilities around a compiler
that does not compile its own parser is the wrong success metric, and this spine
exists so none of them forks the semantic universe while that path is walked.
