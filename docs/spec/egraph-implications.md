| field | value |
|---|---|
| title | Currying and cross-world projection/injection as egraph consequences |
| status | Design specification. Structural tables only. |
| authority | docs/spec/canonical.md section 3 (one application algebra), docs/spec/law.md section 9 (application and projection) |
| revision | Corrected per 2026-09-13 review: removed invalid universal equations, acknowledged existing machinery, scoped equivalences |

| section |
|---|
| 1. The graph identity law that makes this possible |

| # | law |
|---|---|
| 1 | ONE THING -> ONE ID. A semantic entity has exactly one canonical identity. |
| 2 | FACTS QUALIFY THINGS. All variation is facts on the identity, not new identities. |
| 3 | RELATIONS ARE IDS. An application is an identity, not a syntax tree. |
| 4 | EDGES EXPRESS STRUCTURAL ROLES. Application has edges: relation, subject, operand, result. |
| 5 | THREE IDENTITIES DISTINCT. Relation identity (which operation). Occurrence identity (which particular application, with provenance/demand/effects). Equivalence-class coordinate (which terms established interchangeable within theory/scope). Eclass representative is derived index, not replacement for persistent identity. |

| section |
|---|
| 2. Currying: partial application as fact saturation |

| # | rule |
|---|---|
| 1 | f(a,b) constructs application identity A with edges: relation->f, operand->(a,b), result->R. |
| 2 | f(a) constructs application identity A2 with edges: relation->f, operand->(a), result->R2. |
| 3 | f(a)(b) constructs application identity A3 with edges: relation->A2, operand->(b), result->R. |
| 4 | Partial application is fact saturation, not automatic positional currying. Preserves exact supplied facts, open requirements, subject roles, descriptor/world/stage facts, capture. |
| 5 | Capture does not imply allocation. Fewer arguments do not automatically create lambda. |
| 6 | body:weight(kg) = (factor) supplies subject/projection facts in head; not runtime closure. |
| 7 | No curry operation exists. Partial application is application with fewer operands bound. |
| 8 | Demand determines realization: if all operands bound, emit direct call. If some unbound, retain established facts, leave input open, specialize when supplied. Physical closure only where semantics demand it. |

| # | lawful composition |
|---|---|
| 1 | Composition of genuinely partial relation may collapse when supplied/open roles, bindings, evaluation behavior, world requirements establish correspondence. |
| 2 | NOT VALID: apply(apply(f,a),b) = apply(f,(a,b)) as universal. Counterexample: f(a) may perform effects, return different callable. |
| 3 | NOT VALID: apply(f,()) = f as universal. Counterexample: answer = () 42; answer() produces 42, not callable. |
| 4 | Operand order significant unless commutativity fact present on relation. |
| 5 | Prerequisite: binding-aware substitution. Renaming bound variable must not change meaning; substituting value must not capture different binding. |

| section |
|---|
| 3. Descriptors: three contributions, one architecture |

| # | rule |
|---|---|
| 1 | A descriptor is a fact on an application identity qualifying how it realizes. |
| 2 | Descriptor contributes up to three distinguishable things: observable law, established knowledge, physical choice. |
| 3 | Observable law: exact vs wrapping arithmetic, units, permitted values, rounding, failure, ownership, layout contract. Example: 255+1 = 256 vs wrap 0 vs fail are different qualified computations. |
| 4 | Established knowledge: range proof, closed shape, known implementation, refinement enabling specialization. |
| 5 | Physical choice: register layout, closure representation, implementation strategy where not observable. |
| 6 | These three participate in one descriptor architecture without becoming interchangeable. |
| 7 | Semantic fact shared by eclass must be valid for equivalence represented. Candidate layout/allocation cost/instruction count not automatically property of every eclass member. |
| 8 | One class of equivalent meanings can have many differently priced realizations. Do not flatten physical facts. |

| # | practical consequence |
|---|---|
| 1 | Describe required relationship once, derive every demanded consumer without restating contract. |
| 2 | When consumer demands one field, avoid constructing irrelevant representation where legal. |
| 3 | When unknown field must be validated, demand elimination preserves obligation. |
| 4 | When layout fixed by external interface, optimizer respects it as observable, not incidental. |

| section |
|---|
| 4. Worlds: closed semantic tables |

| # | rule |
|---|---|
| 1 | World is closed semantic table carrying bindings, descriptors, relations, stage/target facts, authority, requirements, witnesses, observer demand. |
| 2 | Authority is one fact world carries; world is not merely authority label. |
| 3 | Every identity exists in a world. World is fact on identity, not separate namespace. |
| 4 | x@w is identity x qualified with world fact w. |
| 5 | NOT VALID: x@w1 and x@w2 automatically in same eclass. Changed world can change binding, numerical law, accessible state, permitted behavior. |
| 6 | Lawful reuse: computation reusable across worlds when result/permitted behavior depend only on facts for which required correspondence established. |
| 7 | @ (bare) is current-world accessor: resolves to world fact of enclosing application. |

| section |
|---|
| 5. Projection: world-qualified read with witness |

| # | rule |
|---|---|
| 1 | Projection x@w where x in w2 constructs: identity P with edges: source->x, from->w2, to->w, kind->projection. |
| 2 | P in same eclass as x iff projection semantics-preserving (witness fact present). |
| 3 | If projection changes representation, P is new identity with equivalence edge to x, qualified by witness. |
| 4 | [] (computed) and . (static) are projection identities with different descriptor facts. |
| 5 | NOT VALID: (x@w1)@w2 = x@w2 as universal. Intermediate may discard info, round, validate, attenuate authority, evaluate under different bindings. |
| 6 | Composition lawful only when intermediate work proven unnecessary, not assumed. |
| 7 | Projection identity: x@w where x already in w = x (no-op canonicalized) when witness establishes no change. |

| section |
|---|
| 6. Injection: world-qualified write with formation contract |

| # | rule |
|---|---|
| 1 | Injection x@{k=v} constructs: identity I with edges: target->x, bindings->(k=v), kind->injection. |
| 2 | I is new world-qualified identity. Bindings are facts on I, not on x. |
| 3 | Reading particular injected member returns its value; whole derived world is not that value. |
| 4 | Injection does not mutate x. x retains identity; I is extended identity. |
| 5 | NOT VALID: unrestricted union. Combining conflicting bindings, dependent RHS, different formation-time captures requires actual injection law. |
| 6 | Existing foundation: graph defines derived worlds with parent, delta, witness records; formation contract rejects duplicate delta members, manufactured authority. |
| 7 | Nested injection lawful only when binding sets compatible per injection law. |

| section |
|---|
| 7. Cross-world application: the algebra |

| # | rule |
|---|---|
| 1 | Application f(a) where f in w1 and a in w2 requires world alignment. |
| 2 | Graph inserts projection identities: f(a@w1) - a projected to f world. |
| 3 | If world satisfies w1 requirements (witness fact), projection canonicalizes to identity. |
| 4 | Application identity carries world-requirement fact: world in which it executes. |
| 5 | Result world: application result in application world unless result-world fact specifies otherwise. |

| # | composition |
|---|---|
| 1 | project(w1->w2) compose project(w2->w3) lawful only with witness that intermediate unnecessary. |
| 2 | inject(b1) compose inject(b2) lawful only when binding sets compatible per injection law. |
| 3 | project(w->w2) compose inject(b) where b binds in w2 - order matters; not generally commutable. |
| 4 | project compose project-inverse = identity when round-trip witness present. |

| section |
|---|
| 8. Architectural center |

| # | notation |
|---|---|
| 1 | Γ; W; O ⊢ e1 ≃ e2 |
| 2 | Given established premises Γ, under world W and required observations O, computations e1/e2 interchangeable. |
| 3 | Descriptors contribute domain/law. Applications preserve bindings, operand/result packs, occurrences. Projection/injection transport facts under own contracts. Witnesses justify correspondence. Demand determines necessary realizations. |
| 4 | Algebra determines valid equalities. Egraph represents/propagates them. Egraph does not establish initial rewrite rules true. |
| 5 | Objective: exact identities/laws -> scoped justified equivalences -> congruence over compatible contexts -> demand-directed realization -> retained evidence. |

| section |
|---|
| 9. Existing machinery inventory (at 07929cda) |

| # | exists | location | status |
|---|---|---|---|
| 1 | World facts | Draw record keyed by application occurrence, WorldDelta, DerivedWorldFact | Present; world not stored as field on application record by design |
| 2 | Descriptor/pack facts | Descriptor relationships, result descriptors, semantic packs, member demand, aggregate-to-pack | Present; higher-order propagation incomplete |
| 3 | Egraph machinery | src/obseq.zig: bounded egraph, parent/use lists, memoization, insertion, class lookup, merging | Present; congruence tied to fixed demanded projection |
| 4 | Cross-revision relations | Incarnation-qualified refs, dependencies, witnessed correspondences, exact vs refinement | Structural; operational coverage incomplete |
| 5 | Derived world formation | Parent/delta/witness records, duplicate rejection, authority validation | Present; source-to-production coverage incomplete |

| section |
|---|
| 10. What remains: precise gaps |

| # | gap | precise formulation |
|---|---|---|
| 1 | Application eclass consumer | Which equivalence consumer reads application identities? What machine decision changes? |
| 2 | Operand canonicalization scope | Under which exact conditions does f(a)(b) unify with f(a,b)? Which facts establish correspondence? |
| 3 | World fact production | Which exact world facts produced on real application path? Which consumer reads them? |
| 4 | Projection persistence | Do [], ., @ persist as graph identities with edges post-lowering? What is lost? |
| 5 | Descriptor propagation | Which descriptor facts reach realization selection? Where does higher-order propagation break? |
| 6 | Demand-driven selection | What selects realization from eclass? How does demand query work? |
| 7 | Binding-aware egraph | How are binders handled? Renaming vs substitution vs capture? |
| 8 | Premise invalidation | When premise expires, which equivalences depend on it? How is congruence recomputed? |

| section |
|---|
| 11. Corrected implementation order |

| # | step | accepted result |
|---|---|---|
| 1 | Reconcile laws, inventory owners | Invalid universal equations removed; existing machinery catalogued with exact consumers. |
| 2 | Close partial-relation facts | Supplied facts, open roles, bindings, captures, ordered packs survive production path. Missing args not silently closed. |
| 3 | Close world/descriptor continuity | Semantic laws, world deps, authority, formation facts, witnesses reach application/consumers. |
| 4 | Admit scoped congruence | Justified equality propagates only through compatible contexts; provenance survives; contradictions visible. |
| 5 | Compose lawfully | Remove only witnessed redundant stages, adapters, setup, projection chains. |
| 6 | Select/validate realization | Demand/target cost choose among lawful candidates without forced allocation/materialization. |
| 7 | Demonstrate selective reuse | Irrelevant change preserves evidence; relevant change invalidates necessary consequences; both measured. |

| section |
|---|
| 12. Business gaps: relationship to model |

| # | gap | relationship |
|---|---|---|
| A | Specification discrimination | Retain competing interpretations; search distinguishing situation. Different eclasses = equality not established, not proof of difference. |
| B | Stateful upgrades | Permitted transition between code/state/obligations. May require simulation/refinement, not equality. |
| C | Permission at execution | World/authority facts constrain application/operands. Equality does not mint permission. |
| D | Uncertain effects | Preserve occurrence/effect/outcome/recovery. Unknown != succeeded. |
| E | Fact lifetimes | Track proof/realization dependencies; invalidate on expiry. |
| F | Model contracts | Attach epistemic status/evidence/quality. Not three universes; stats != proof. |
| G | Personalization | Authorized change proving preserved obligations. Behavior change != equality. |
| H | Coordination | Prove concurrent composition preserves invariant. Local validity insufficient. |
