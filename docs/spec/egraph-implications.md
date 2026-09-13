| field | value |
|---|---|
| title | Currying and cross-world projection/injection as egraph consequences |
| status | Design specification. Structural tables only. |
| authority | docs/spec/canonical.md section 3 (one application algebra), docs/spec/law.md section 9 (application and projection) |

| section |
|---|
| 1. The graph identity law that makes this possible |

| # | law |
|---|---|
| 1 | ONE THING -> ONE ID. A semantic entity has exactly one canonical identity. |
| 2 | FACTS QUALIFY THINGS. All variation is facts on the identity, not new identities. |
| 3 | RELATIONS ARE IDS. An application is an identity, not a syntax tree. |
| 4 | EDGES EXPRESS STRUCTURAL ROLES. Application has edges: relation, subject, operand, result. |

| section |
|---|
| 2. Currying: application with unbound operands is the same eclass |

| # | rule |
|---|---|
| 1 | f(a,b) constructs application identity A with edges: relation->f, operand->(a,b), result->R. |
| 2 | f(a) constructs application identity A2 with edges: relation->f, operand->(a), result->R2. |
| 3 | f(a)(b) constructs application identity A3 with edges: relation->A2, operand->(b), result->R. |
| 4 | Canonicalization: A3 unifies with A when operand concatenation (a)+(b) = (a,b) and relation resolution f of f = f. |
| 5 | No curry operation exists. Partial application is application with fewer operands bound. |
| 6 | The eclass for f(a) contains: the partial application node, and any lambda/closure that eta-expands to the same relation+operand facts. |
| 7 | Demand determines realization: if all operands bound, emit direct call. If some unbound, emit closure capturing bound operands. Same eclass, different realization selected by demand. |

| # | canonicalization |
|---|---|
| 1 | apply(apply(f,a),b) = apply(f,(a,b)) when f arity admits (a,b). |
| 2 | apply(f,()) = f (empty application is identity). |
| 3 | apply(f,(a)) where f has arity 1 = apply(f,a) (singleton collapse). |
| 4 | Operand order is significant unless commutativity fact present on relation. |

| section |
|---|
| 3. Descriptors: the fact that selects realization |

| # | rule |
|---|---|
| 1 | A descriptor is a fact on an application identity qualifying how it realizes. |
| 2 | f(a) with descriptor arity=2 means: one operand bound, one demanded. |
| 3 | Descriptors do not create new identities. f(a) with descriptor D1 and f(a) with descriptor D2 are the same eclass with different qualifying facts. |
| 4 | Realization selection reads descriptors as demand, not as semantic difference. |
| 5 | A descriptor naming a calling convention, closure layout, or specialization is a realization fact, not a semantic fact. |

| section |
|---|
| 4. Worlds: labels on identities, not containers |

| # | rule |
|---|---|
| 1 | Every identity exists in a world. World is a fact on the identity, not a separate namespace. |
| 2 | x@w is identity x qualified with world fact w. Same x, different world = different qualified identity. |
| 3 | The unqualified identity x is the cross-world eclass. x@w1 and x@w2 are both members via world-qualification facts. |
| 4 | @ (bare) is the current-world accessor: resolves to the world fact of the enclosing application. |

| section |
|---|
| 5. Projection: world-qualified read as eclass rewrite |

| # | rule |
|---|---|
| 1 | Projection x@w where x is in world w2 constructs: identity P with edges: source->x, from->w2, to->w, kind->projection. |
| 2 | P is in the same eclass as x iff the projection is semantics-preserving (witness fact present). |
| 3 | If projection changes representation (not just world label), P is a new identity with an equivalence edge to x, qualified by the projection witness. |
| 4 | [] (computed projection) and . (static projection) are both projection identities with different descriptor facts (computed vs static). |
| 5 | Projection composition: (x@w1)@w2 = x@w2 via transitivity of world-qualification. The intermediate is canonicalized away. |
| 6 | Projection identity: x@w where x already in w = x (no-op canonicalized). |

| section |
|---|
| 6. Injection: world-qualified write as eclass rewrite |

| # | rule |
|---|---|
| 1 | Injection x@{k=v} constructs: identity I with edges: target->x, bindings->(k=v), kind->injection. |
| 2 | I is a new world-qualified identity. The bindings are facts on I, not on x. |
| 3 | Injection followed by projection: (x@{k=v})@w where w sees k - canonicalizes to the bound value v. |
| 4 | Injection does not mutate x. x retains its identity; I is the extended identity. |
| 5 | Nested injection: (x@{a=1})@{b=2} = x@{a=1,b=2} via binding-set union canonicalization. |

| section |
|---|
| 7. Cross-world application: the algebra |

| # | rule |
|---|---|
| 1 | Application f(a) where f in world w1 and a in world w2 requires world alignment. |
| 2 | The graph inserts projection identities: f(a@w1) - a is projected to f world. |
| 3 | If a world already satisfies w1 requirements (witness fact), the projection canonicalizes to identity. |
| 4 | The application identity carries a world-requirement fact: the world in which it executes. |
| 5 | Result world: the application result is in the application world unless a result-world fact specifies otherwise. |

| # | composition |
|---|---|
| 1 | project(w1->w2) compose project(w2->w3) = project(w1->w3) (projection composition). |
| 2 | inject(b1) compose inject(b2) = inject(b1 union b2) (injection composition via union). |
| 3 | project(w->w2) compose inject(b) where b binds in w2 - order matters; not generally commutable. |
| 4 | project compose project-inverse = identity when the round-trip witness is present. |

| section |
|---|
| 8. What the current model is missing |

| # | gap | structural cause |
|---|---|---|
| 1 | No eclass for application identities | Applications are lowered directly without an equivalence structure. src/graph/lower.zig constructs application nodes but does not maintain congruence classes. |
| 2 | Operand-list canonicalization absent | f(a)(b) vs f(a,b) are different syntax trees; no rewrite unifies them because there is no eclass to unify in. |
| 3 | World is not a graph fact | Worlds exist in syntax (@) and in resolver logic, but are not reified as facts on identities. Cannot query what world is x in from the graph. |
| 4 | Projection/injection not in graph | [], ., @ are resolved during lowering but do not persist as graph identities with edges. Post-lowering, the projection history is lost. |
| 5 | No descriptor-as-fact | Descriptors are either syntax or resolver state; not facts on the application eclass that realization selection can read. |
| 6 | Demand does not select from eclass | Realization is chosen during lowering, not by demand-driven selection from an eclass of equivalent forms. |

| section |
|---|
| 9. Concrete next steps |

| # | step | depends on |
|---|---|---|
| 1 | Reify application as graph identity with relation/subject/operand/result edges | Current lower.zig constructs these; needs identity interning. |
| 2 | Add eclass table: identity -> canonical representative | New structure; congruence on operand lists. |
| 3 | Reify world as fact on identity | Resolver already tracks worlds; needs to emit as graph facts. |
| 4 | Reify projection/injection as identities with source/target edges | Lowering already handles these; needs to persist them. |
| 5 | Implement operand-concatenation canonicalization | Requires steps 1-2. |
| 6 | Implement projection composition/injection union rewrites | Requires steps 3-4. |
| 7 | Move realization selection to demand-driven eclass query | Requires steps 1-6; replaces lowering-time choice. |
