| field | value |
|---|---|
| title | SUBJECT-SECTION-ONE, and the control-exit correction |

| # | directive |
|---|---|
| 1 | **This is not "the closure moves scope."** It is: **a one-subject expression section whose missing subject is uniquely supplied by the consuming relation.** That framing is the whole ruling — it avoids implicit-scope magic, invents no placeholder, and changes no existing law. |

| # | directive |
|---|---|
| 1 | users:any((user) user.id == id) -> users:any(.id == id) |

| section |
|---|---|
| §1 SUBJECT-SECTION-ONE |

> Where an expression is demanded as a relation with **exactly one uniquely
> recoverable semantic subject**, a receiver-less `.member` projects that
> subject. All receiver-less projections in the same section share that one
> subject unless another explicit subject is written. The section creates **no
> lexical binding, no scope mutation, no implicit identifier, and no runtime
> closure**. If the demanded relation admits zero, several, or incomparable
> subject assignments, resolution **FAILS CLOSED**.

| # | directive |
|---|---|
| 1 | **`.` IS NOT REINTERPRETED.** It still means exactly one static projection — *given the one subject supplied here, project member `id`.* Canonical now, subject to the one-subject rule: |

| # | directive |
|---|---|
| 1 | users:map((user) user.email) -> users:map(.email) users:filter((user) user.active) -> users:filter(.active) users:any((user) user.id == id) -> users:any(.id == id) users:find((user) user.id == id) -> users:find(.id == id) |

| section |
|---|---|
| §1.1 Why this is STRONGER for FTCFTW, not merely shorter |

| # | directive |
|---|---|
| 1 | The explicit form carries parser-level baggage the compiler must later prove irrelevant: a binder spelling, a parameter binding, a closure body, a projection, a capture. |
| 2 | The section states the irreducible structure directly, so the graph can publish it immediately: |

| # | directive |
|---|---|
| 1 | predicate { subject: hole-0, projection: id, relation: eq, operand: outer-id } |

| # | directive |
|---|---|
| 1 | And the graph then knows something valuable: **the left side depends on the iterated subject; the right side is invariant across iteration.** That is loop-invariant hoisting, index probing and hash lookup exposed at the source face. `users:find(.id == id)` can become a **primary-key index probe with zero iteration** — which is exactly why keeping `find`/`any` semantically explicit matters. |
| 2 | Physical closure representation stays **0** unless something genuinely escapes. |

| section |
|---|---|
| §1.2 It must FAIL CLOSED — this is not ambient scope |

| # | directive |
|---|---|
| 1 | pairs:any(.left == .right) lawful IF one record yields both fields something:map(.id == .id) REFUSED — two parameters, and nothing says whether the two `.id` are a.id/a.id, a.id/b.id, or b.id/a.id |

| # | directive |
|---|---|
| 1 | Where the demanded relation has several semantic parameters or more than one valid subject assignment, **retain explicit parameters**: |

| # | directive |
|---|---|
| 1 | something:map((a, b) a.id == b.id) |

| section |
|---|---|
| §1.3 Capture is unambiguous and carries information |

| # | directive |
|---|---|
| 1 | id = request.id user = users:find(.id == id) |

| # | directive |
|---|---|
| 1 | `.id` is a projection from the supplied subject; bare `id` is the ordinary lexical binding. |
| 2 | No ambiguity, and the distinction is the fact that enables the index probe. |

| section |
|---|---|
| §2 RELATION-SECTION-ONE — RESEARCH ONLY, NOT YET LAW |

| # | directive |
|---|---|
| 1 | users:each((user) user:send(message)) -> users:each(:send(message)) |

| # | directive |
|---|---|
| 1 | A leading `:relation(args)` would denote a relation application section with one unsatisfied subject slot. |
| 2 | Attractive because it **invents nothing** — `:` keeps its existing meaning, subject orientation, with the subject supplied by context rather than by an implicit identifier. |
| 3 | Compare the alternatives it avoids: `(user) user:send(message)`, `_:send(message)`, `it:send(message)`. |

| # | directive |
|---|---|
| 1 | **Admit only after all four hold:** it is a GENERAL expression law and not collection-helper magic; subject demand is unique; relation identity is exact; and an explicit-lambda graph-equivalence gate passes. |

| section |
|---|---|
| §3 WHAT MUST NOT BE INTRODUCED |

| # | directive |
|---|---|
| 1 | **No operator sections yet.** `numbers:map(+ bias)` collides with unary plus; `> threshold` has grammar ambiguity. |
| 2 | New grammar semantics to save a short binder fails the source-floor test until a benefit is proven. `numbers:map((x) x + bias)` is fine. `numbers:map(add(bias))` only if `add(bias)` genuinely yields an applicable relation under its explicit descriptor — **do not bend CURRY-EXPLICIT to make this prettier.** |

| # | directive |
|---|---|
| 1 | **No implicit lifting of scalar relations over collections.** `numbers:add(5)` means relation `add` with `numbers` as subject, which may legitimately mean append, set union, or vector addition depending on the descriptor. |
| 2 | Reading it as elementwise map **hides a change in semantic level**. |
| 3 | Lift only on exact algebraic proof, and fail closed on competing collection-level meanings. |

| # | directive |
|---|---|
| 1 | **No placeholder variables, no implicit `it`, no ambient `self`, no automatic currying.** |

| section |
|---|---|
| §4 QUESTION-DENSITY-ONE — removing a parameter is SUBORDINATE |

| # | directive |
|---|---|
| 1 | found = false -> users:any(.id == id) for(users) (user) if(user.id == id) found = true break |

| # | directive |
|---|---|
| 1 | **This reduction matters far more than the parameter one, because it changes the QUESTION, not the character count.** `any` states existential demand; the manual form states "scan and mutate a flag" and forces the compiler to rediscover the question. |
| 2 | Changing the demanded question has already produced hundredfold reductions in this project. |

| # | directive |
|---|---|
| 1 | **Therefore do NOT compress away the relation words.** `any` (existential), `all` (universal), `find` (witness), `filter` (subset), `map` (transformed iteration), `each` (effects), `fold` (reduction under explicit algebra) are different questions. `users(.id == id)` would lose all of it — filter? find? any? count? `users:any(.id == id)` is likely very close to the semantic source floor. |

| section |
|---|---|
| §4.1 The reduction ladder |

| # | directive |
|---|---|
| 1 | explicit closure v if the unique subject is recoverable subject/projection section v if a stronger domain relation states the actual question stronger domain relation |

| # | directive |
|---|---|
| 1 | **Do not point-free everything.** Where names carry distinct semantic roles they are information, not debt: |

| # | directive |
|---|---|
| 1 | transactions:fold(0, (balance, transaction) balance + transaction.amount) |

| # | directive |
|---|---|
| 1 | `balance` is carried state, `transaction` is the iteration result. |
| 2 | INTERMEDIATE-ZERO says eliminate *reconstructible* names — not all names. |

| section |
|---|---|
| §5 PARAMETER-OMISSION GATE — all six, or retain the parameter |

| # | directive |
|---|---|
| 1 | the demanded role is uniquely supplied by the consuming relation |
| 2 | every use is expressible as projection/relation sections over that same role |
| 3 | no ambiguity between multiple subjects or packs |
| 4 | no meaningful distinction is lost for humans |
| 5 | the normalized graph is IDENTICAL |
| 6 | closure/capture representation cannot worsen |

| section |
|---|---|
| §6 THE CONTROL-EXIT CORRECTION — `break()` / `continue()` ARE REVERSED |

| # | directive |
|---|---|
| 1 | **SOURCE-CONTROL-ONE §6 had this backwards and is corrected.** Bare `break` and bare `continue` are **canonical**. `()` on a zero-payload region exit carries no information and falsely suggests ordinary APPLICATION-ONE behaviour — which is precisely why the compiler refuses `break()` as `expr-unhandled:func_expr`. |
| 2 | The measurement was first read as "a canonical face is broken"; the correct reading is **the compiler was right and the parenthesized face was the wrong design.** |

| # | directive |
|---|---|
| 1 | `return` keeps both faces: `return(value)` carries a result pack, so the parentheses carry real structure. |
| 2 | That asymmetry is principled, not inconsistent. |

| # | directive |
|---|---|
| 1 | **Graph meaning is structural, never a mandatory machine branch:** |

| # | directive |
|---|---|
| 1 | region exit { target: exact iteration exit \| exact step boundary, result pack: empty } |

| # | directive |
|---|---|
| 1 | `continue` does not mean "jump to the loop header" — realization may be a branch, predication, a filtered iteration, **a SIMD lane mask**, or nothing. |

| # | directive |
|---|---|
| 1 | **Prefer stronger relations where they state the real demand** — break-on-first- truth is `any`, break-to-return-a-witness is `find`, and an absorbing reduction (`values:min()` where the domain infimum is reachable) should let the compiler **synthesize** early exit with no `break` written. *Source `break` and realized early termination stay distinct concepts.* |

| # | directive |
|---|---|
| 1 | **But keep them where iteration is genuinely general and effectful.** Neither of these should be tortured into a chain: |

| # | directive |
|---|---|
| 1 | for(commands) (command) for(records) (record) command:execute() if(record.deleted) continue if(shutdown) break if(!record.valid) log(record) ; continue audit(command) process(record) |

| # | directive |
|---|---|
| 1 | **Canonical means semantic clarity, not "no control keywords."** |

| section |
|---|---|
| §7 MANDATORY GATES |

| # | directive |
|---|---|
| 1 | explicit lambda vs `.field` section -> identical graph |
| 2 | explicit lambda vs `.field == capture` -> identical graph |
| 3 | `:relation(args)` section vs explicit subject lambda -> identical graph |
| 4 | two-parameter demanded relation + `.field` shorthand -> **ambiguity/refusal** |
| 5 | outer lexical `id` plus `.id` -> capture vs subject-projection distinction proven |
| 6 | same answers, different relation/subject/capture graphs -> **gate RED** |
| 7 | both forms benchmarked -> **no source-form performance divergence** |

| # | directive |
|---|---|
| 1 | Gate 7 is architectural, not aspirational: machine selection never sees which spelling was used, so a runtime difference between the two faces is **compiler debt by definition.** |

| # | directive |
|---|---|

| section |
|---|---|
| §8 MEASURED BASELINE — 2026-08-16, idol `ee8e29c3` |

| # | directive |
|---|---|
| 1 | **THE CANONICAL EXAMPLES IN §1 CANNOT BE WRITTEN TODAY — AND THE BLOCKER IS NOT THE SECTION SYNTAX.** |

| # | directive |
|---|---|
| 1 | xs:map((x) x * 2) error: 'map' is neither a descriptor nor a callable xs:any((x) x == 7) error: 'any' is neither a descriptor nor a callable ps:map(.a) same refusal — it never reaches the section xs:len() REFUSED (direct backend) s:len() answers 3 |

| # | directive |
|---|---|
| 1 | Corpus census of collection-relation call sites: |

| # | directive |
|---|---|
| 1 | :find( 279 ALL STRING FIND — `s:find("Duo", 1, true)`, not collection :each( 6 :map( 2 :filter( 1 :any( :all( :fold( ZERO |

| # | directive |
|---|---|
| 1 | The `find`/`fold` declared in the corpus are operand-first relations (`find: i64 = (xs, n: i64, key: i64)`), not subject-oriented collection relations. **A table does not even admit `:len()`, while a string does.** |

| # | directive |
|---|---|
| 1 | **THE ORDERING CONSEQUENCE, AND IT INVERTS THE OBVIOUS PRIORITY.** A subject section is *defined* as the section whose missing subject is supplied by the CONSUMING RELATION. |
| 2 | With no consuming relation, there is nothing to supply the hole. **The collection relation algebra is a prerequisite for SUBJECT-SECTION-ONE, not a consumer of it.** Building the section grammar first would produce syntax with nothing to attach to — and §7's gates would all be vacuous, since every one compares a section against an explicit lambda that also does not compile. |

| # | directive |
|---|---|
| 1 | So the executable order is: **collection relations (`any`, `all`, `find`, `filter`, `map`, `fold`, `each`) as real subject-oriented relations on tables**, carrying the iteration algebra of PROTOCOL-PROJECTION-ONE §3 — *then* the sections, *then* `RELATION-SECTION-ONE`. |

| # | directive |
|---|---|
| 1 | **Not measured:** whether the explicit-lambda face (`xs:map((x) x * 2)`) has any lowering path at all behind the resolution failure, or whether the refusal is purely a missing relation. |
| 2 | That is the first question for the lane, and it decides whether this is one job or two. |
