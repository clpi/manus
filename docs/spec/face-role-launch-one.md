# FACE / ROLE / APPLICATOR / HOME / LAUNCH ONE

| # | directive |
|---|---|
| 1 | **Filesystem structure may infer a semantic HOME and a LAUNCH ROLE. |
| 2 | A launch role may request a conventional world projection. |
| 3 | Only the launcher's actual WITNESSES grant authority.** |

| # | directive |
|---|---|
| 1 | That is the whole reconciliation. |
| 2 | It buys the convenience of `test/`, `bench/` and a shebang without letting path spelling become authority — because home, reach, world, authority and witness stay different facts. |

| # | directive |
|---|---|

## §1 NAMES ARE SOURCE FACES, NEVER SEMANTIC IDENTITIES

| # | directive |
|---|---|
| 1 | A spelling may help LOCATE a declaration during ingress. |
| 2 | It may not create, alter, or recover semantic identity downstream. **Never reason through English morphology:** |

| # | directive |
|---|---|
| 1 | tokenizer ends in -izer -> it implements token FORBIDDEN iterator ends in -ator -> it implements iteration FORBIDDEN stateless ends in -less -> it has no state FORBIDDEN items ends in -s -> it is a collection FORBIDDEN |

| # | directive |
|---|---|
| 1 | **The mandatory ordering is facts first, spelling last:** |

| # | directive |
|---|---|
| 1 | declaration / application / descriptor / shape / relation / world / demand -> exact semantic identity and role -> only THEN audit whether the spelling redundantly encoded those facts |

| # | directive |
|---|---|
| 1 | This repo already fixed one instance: a one-letter heuristic classified `R` as a generic parameter before consulting a real declaration. |
| 2 | The declaration now wins. |
| 3 | That is the general law. |

## §2 APPLICATOR, RELATION AND SUBJECT ARE DISTINCT

| # | directive |
|---|---|
| 1 | An **applicator** is a value that may be applied. |
| 2 | A **relation** is the operation the application denotes. |
| 3 | A **subject** is the value the relation is oriented around. |
| 4 | They may coincide; they must not collapse. |

| # | directive |
|---|---|
| 1 | tokenizer = rule familiar token = tokenizer(source) token = source:token(rule) canonical, when source is the true subject |

| # | directive |
|---|---|
| 1 | Both normalize to ONE application: `applied = rule-value`, `relation = token`, `subject = source`. **`tokenizer-id != token-id`** — the applicator id and the relation id are different entities, and the applicator survives as an identity only if the VALUE ITSELF IS OBSERVABLE. |
| 2 | If it is sealed and stateless: provider object 0, provider lookup 0, dynamic dispatch 0. |

| # | directive |
|---|---|
| 1 | The proof direction is one-way: |

| # | directive |
|---|---|
| 1 | application facts prove relation `token` + value occupies applied role -> the naming audit MAY classify `tokenizer` as an applicator-glued face the spelling `tokenizer` -> NEVER invents the relation `token` |

| # | directive |
|---|---|
| 1 | This matters for `perfectionist`, `journalist`, `register`, `filter`, `render`, `lens`. **Exact declaration always wins:** a declared `lens` is an optical lens, not the plural of `len`, and no suffix stripping is attempted. |

| # | directive |
|---|---|
| 1 | Only a CLOSED modifier algebra is admitted — cardinality, application role, state, stage, ordering, polarity, authority, specialization — each where its meaning is exact. `-ful`, `-ist`, `-ish`, `-like`, `-ly` and most `-ed` are NOT. |

## §3 PLURALITY IS SHAPE, NEVER IDENTITY

| # | directive |
|---|---|
| 1 | `items`, `tests`, `benchmarks`, `events`, `users`, `tokens` must not mint plural semantic kinds. |
| 2 | The graph says `descriptor = item-table, element = item, cardinality = many` — never `descriptor = items`. |
| 3 | Semantic homes stay singular: `item/ test/ bench/ event/ token/`. |

| # | directive |
|---|---|
| 1 | A collection binding and an element binding remain DISTINCT entities that share an element descriptor. `counted` is not a relation — completion is a witness/provenance fact on the `count` application. `callable` is not an identity — callability is "exactly one lawful application exists". |

## §4 ITERATOR IS A REALIZATION, NOT ITERATION — AND THE COST IS NOT WHERE IT LOOKS

| # | directive |
|---|---|
| 1 | An iterator value exists only if a cursor/stateful applicator is itself semantically observable. `cursor:next()` may be a PROJECTED one-step face of the iteration algebra; a relation merely NAMED `next` must not establish iteration, and an iteration law with no `next` must still make `for` work. |

| # | directive |
|---|---|
| 1 | **MEASURED CORRECTION — do not delete iterator objects because they sound abstract.** On Apple M2 Pro, per element: |

| # | directive |
|---|---|
| 1 | iterator object / state in memory ~ZERO vtable / indirect dispatch ~ZERO (+0.4%) THE CALL BOUNDARY +199% |

| # | directive |
|---|---|
| 1 | **The actionable optimization is inlining the advance, not erasing the object.** Which is exactly why applicator, relation and realization must stay distinguishable: the win is on one of them and not the others. |

## §5 APPEND AND PREPEND ARE POSITION FACTS

| # | directive |
|---|---|
| 1 | item:append(value) -> relation insert, subject item-sequence, position tail item:prepend(value) -> relation insert, subject item-sequence, position head |

| # | directive |
|---|---|
| 1 | The faces communicate a real distinction compactly and must NOT create unrelated ontologies. |
| 2 | Representation follows demand: dynamic array for tail-heavy, deque for mixed, rope for persistent, static data when compile-time known, **nothing when the result is unobserved.** If `append` might mean concatenation rather than one-element insertion, descriptors must distinguish it — never spelling. |

## §6 COMPOUNDS ARE NEVER MECHANICALLY SPLIT

| # | directive |
|---|---|
| 1 | This repo already proved why: lowercasing `KINDALIAS` to `kindalias` converts a DETECTABLE violation into an UNDETECTABLE one, and 92 such blind renames were refused. `readbyte` may be classified as subject-glued ONLY IF graph facts already prove relation `read` and subject `byte`. `perfectionist` cannot be classified from a dictionary. |

| # | directive |
|---|---|
| 1 | Every declaration classifies as exactly one of: **irreducible** (the only automatically canonical class), subject-glued, applicator-glued, plurality-glued, fact-glued, historical/serial, or **unknown — which must never be auto-rewritten.** |

| # | directive |
|---|---|
| 1 | A naming gate must consume SEMANTIC FACTS, not regex. |
| 2 | A grep count is a candidate upper bound only — the same rule already applied to the 6,449 dot-shaped calls. |

## §7 THE ROLE / AUTHORITY MATRIX — the load-bearing distinction

| physical fact | MAY infer | MUST NOT infer |
|---|---|---|
| `test/` | semantic home; test launch-role candidate | testing authority |
| `bench/` | semantic home; bench launch-role candidate | hardware counters |
| shebang | script launch request | filesystem/process authority |
| `compiler/` | home, reach, provenance | a compiler world |
| external dependency | provider reach | network/fs authority |
| `shell/` home | shell-related values | host shell authority |

| # | directive |
|---|---|
| 1 | **Only the launcher supplies a world and witnesses.** `home != world`, `path != world`, `reach != authority`. |

| # | directive |
|---|---|
| 1 | `idol test compiler` selects home `compiler.test`, role `test`, and the launcher's exact test world. `idol run compiler.test.lexer` is an ORDINARY home under the caller's ordinary world. **Opt-out is choosing ordinary launch, not source ceremony** — no `@test`, no `test("name", …)`, no `register_test`. |
| 2 | A relation under the selected home is inferred as a case when its descriptor and application facts satisfy the test-case algebra, and **fails closed** when several interpretations exist. |

| # | directive |
|---|---|
| 1 | `bench/` works identically: the benchmark world supplies exact clock/counter witnesses and the relation never mentions a timer — the runner places measurement demand AROUND the application. |
| 2 | Production never reaches `compiler.bench`, so harness 0, measurement world 0, counter lookup 0. |

## §8 SHELL IS ORDINARY SEMANTICS — AND `sh("…")` IS NOT A FACE

| # | directive |
|---|---|
| 1 | A line-one shebang REQUESTS a script launch role. |
| 2 | The launcher may then supply a shell world carrying cwd place, process witness, filesystem witness, stdio witnesses and a command-provider reach. **Shebang text never manufactures authority**; if a required witness is absent, the application fails. |

| # | directive |
|---|---|
| 1 | cd(path) path:cd() -> relation cd, subject path, effect mutate cwd, authority process/fs ls(path) path:ls() -> relation ls, result item table file = ls() -> subject inferred = shell-world.cwd git("status") git:run("status")-> applied git-command, relation run |

| # | directive |
|---|---|
| 1 | **There is no shell command string.** An external command is an APPLICATOR; realization may spawn a process, call a builtin, call a linked library, reuse a resident service, or fold to a constant. |
| 2 | If `git` is absent from the supplied world the result is an unresolved command provider — **never a fallback to arbitrary string execution.** The binding stays singular: `file`, not `files`. |

| # | directive |
|---|---|

## §9 MEASURED BASELINE — 2026-08-16, idol `19cda086`

| # | directive |
|---|---|
| 1 | The owner's ruling cites idol `bf6b0508` / native `f9f9dd9`; the tree has since moved to `19cda086` / `d3a7d95`, which is where these were taken. |

| # | directive |
|---|---|
| 1 | **§8's forbidden face is LIVE: `sh("…")` occurs at 47 SITES IN 7 FILES.** Examples in the corpus today: `sh("cat /tmp/duo_abi_matrix/wrong…")`, `sh("test -f {path}")`, `sh("cmp -s {a} {b}")`. |
| 2 | That is arbitrary string execution, the exact thing §8 says must never be a fallback, and it is the largest single item this ruling opens. |

| # | directive |
|---|---|
| 1 | **The structured shell face does not exist:** |

| # | directive |
|---|---|
| 1 | cd 0 sites exec 17 sites ls 0 sites spawn 16 sites cwd 1 site |

| # | directive |
|---|---|
| 1 | **Directory topology — three plural homes, one already correct:** |

| # | directive |
|---|---|
| 1 | tests/ 11 files PLURAL — §3 violation benchmarks/ 161 files PLURAL — §3 violation examples/ 544 files PLURAL — §3 violation src/ 8 .id §7 rejects the name outright bench/ 8 .id SINGULAR — already conformant |

| # | directive |
|---|---|
| 1 | **The shebang IS first-class, confirmed in both compilers:** `src/lexer.zig:130` declares a `.shebang` token spelled `#!`, and `lib/compiler/lexer.id:1126` agrees — one of the few places host and self-hosted source already converge. |
| 2 | A line-one shebang program compiles and answers. |

| # | directive |
|---|---|
| 1 | **Not yet distinguished, and it matters for gate 16:** a `#!` on line 2 also answers, because `#` opens an ordinary comment. |
| 2 | So a non-line-one shebang is absorbed as a comment rather than recognized as a shebang — which satisfies the INTENT (no launch role is manufactured) but not by an explicit rule. |
| 3 | Whether the lexer emits `.shebang` only at line 1, or the comment path merely masks it, is unmeasured. |

| # | directive |
|---|---|
| 1 | **Everything the owner lists as open remains open**, and none of it should be claimed closed: application world and applied identity are not graph-owned; graph dumps cannot distinguish ten different programs; generic iteration and control regions are absent from the graph; `break` reconstructs its target from an AST stack; protocol implication is one narrow conversion path; only `any` exists of the collection family; bootstrap spelling-based lowering survives at 36 spellings; and subject-first record and mutually-recursive results still refuse. |
