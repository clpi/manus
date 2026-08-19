# Research GAP admission program

Every research GAP must be canonicalized into the existing semantic algebra
before implementation. C0's kind set is closed. By default, a new GAP adds zero
new kinds, zero registries, and zero syntax.

## Admission rule

Before a research GAP is promoted, its author must show which existing semantic
kinds own the meaning. The allowed owners are:

id, descriptor, relation, binding, place, demand, obligation, effect, world,
capability, lifetime, provenance, trust, origin, realization, witness.

No new semantic object, registry, rule language, optimizer space, context kind,
solver kind, pattern type, continuation object, or future type may be introduced
without a constitutional amendment.

## Admission schema

Every research GAP must contain the following non-normative schema:

| Field | Purpose |
| --- | --- |
| constitutional owners | which existing kinds own the meaning |
| new kind delta | must be 0 unless C0 amendment explicitly approved |
| new registry delta | must be 0 |
| source syntax delta | normally 0 |
| semantic invariant | what new fact/law becomes expressible |
| physical mechanism | candidate implementation only |
| prerequisites | exact upstream GAPs/facts |
| foreign implication | what boundary it can erase or constrain |
| world implication | authority/context impact |
| projection implication | projection/injection/interjection/update impact |
| demand implication | new quotient/cardinality behavior |
| realization implication | candidate-set expansion |
| evidence | test/proof/benchmark needed |
| deletion witness | old subsystem/bridge that should disappear |

## Structural mapping

Research capability must not become a new subsystem; it must become facts over
existing semantic owners.

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
| determinacy | Future<T> / Promise | fact on semantic id | dependency/wakeup realization |
| mode | mode types | facts on relation slots | forward/backward/dataflow execution |
| solution cardinality | iterator/generator ontology | relation/application cardinality facts | first/all/count/exists change algorithm |
| pattern | Pattern type system | ordinary relation with search/capture/update facts | DFA/NFA/parser/query/rewrite realizations |
| continuation | continuation object kingdom | semantic id + relation/lifetime/effect facts | branch/frame/state machine/persistent cont |
| recovery | exception hierarchy | obligation + available recovery relations | inline restart/result/unwind/trap |
| concurrency | Task/Actor/Future kingdoms | causality/effect/world relations | schedule/queue/network/direct call |
| hardware target | target-specific language subsystem | world/capability/realization | CPU/GPU/FPGA/CHERI etc. |

## Concrete rewrites

| Current GAP language | Better Idol-native wording |
| --- | --- |
| define Context | qualify world/id with contextual facts; amend C0 only if existing kinds provably insufficient |
| add solver registry | project applicable solver realizations from relation/domain/witness facts; physical index allowed |
| define Rule | ordinary inference relation whose application publishes/refines facts |
| Space semantic object | derived world/graph incarnation used as temporary search projection |
| deterministic producer class | relation/application fact describing determinacy |
| determinacy kind | fact qualifying id |
| Pattern | ordinary relation with mode/cardinality/span/update facts |
| Continuation | ordinary id/relation with resumption/lifetime/effect facts |
| foreign semantic fact format | use the same graph fact format as native semantics; origin/law qualifies it |
| cross-law optimizer | ordinary optimizer consuming witnessed equivalence across origins |

## Execution horizons

| Horizon | Work |
| --- | --- |
| H0 — authority repair | fix current C0 contradictions; rewrite GAP constitutional conflicts; establish research-GAP C0 mapping |
| H1 — compiler B critical path | GAP-145 -> GAP-134 -> first parser authority transfer -> binding -> exact graph -> demand -> realization |
| H2 — semantic substrate | GAP-187 + 175 + 176 + 177 + 178; these create the algebra later research depends on |
| H3 — exploitation frontier | 180-200 + foreign fusion + complexity/lower bounds + hardware/solver/search research |
