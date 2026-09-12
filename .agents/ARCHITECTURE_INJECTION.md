| field | value |
|---|---|
| title | Idol architecture injection — agent orientation |
| status | durable agent orientation only. **Not language law.** If this file conflicts with  or , stop and repair this projection. |

| section |
|---|---|
| Preserve the strongest fact already known |

| # | directive |
|---|---|
| 1 | If an earlier stage knows token identity, relation identity, subject, descriptor, pack correspondence, world, effect, witness, demand, or source span, then a later stage **consumes** that fact. |
| 2 | It does not reconstruct it. |

| # | directive |
|---|---|
| 1 | A missing fact is preferable to a guessed fact. |
| 2 | Fail closed and identify its missing producer. |

| # | directive |
|---|---|
| 1 | **Paste at the top of every agent session (short form):** |

| # | directive |
|---|---|
| 1 | Do not port the host compiler. |
| 2 | Reduce the required observation to Idol semantics. |
| 3 | Preserve every exact fact already known. |
| 4 | One meaning has one id; facts qualify it; realization carries physical choice. |
| 5 | Source syntax, AST kinds, paths, names, hashes, opcodes, storage classes and backend distinctions are never semantic authority. |
| 6 | A value is not a place. |
| 7 | A binding is not storage. |
| 8 | A pack is not an aggregate. |
| 9 | A call is not an ABI. |
| 10 | A table is not a hash table. |
| 11 | A closure is not a heap object. |
| 12 | Unknown is not absent. |
| 13 | Demand determines what exists physically. |
| 14 | Prefer no execution, no allocation, no copy, no representation, no runtime and no instruction whenever semantics permit. |
| 15 | Never reconstruct downstream what upstream already knew. |
| 16 | Never add a parallel semantic taxonomy. |
| 17 | Never self-host host implementation patterns merely because they exist. |
| 18 | Semantic graph work must maximize facts while physically using dense ids, packed ranges, columns, views and exact dependencies. |
| 19 | Every transformation preserves application/value lineage and witness. |
| 20 | Every performance change preserves or expands lawful realizations and accounts for compile cost as well as runtime. |
| 21 | Every SHC claim names the exact production decision that moved from host ownership to executed Idol ownership. |
| 22 | If a required canonical relation/fact is missing, stop and identify the missing authority rather than inventing a helper or fallback. |

| # | directive |
|---|---|

| section |
|---|---|
| Mental model shift |

| # | directive |
|---|---|
| 1 | Idol is **not** a conventional multi-pass compiler with a pile of named IRs. |

| # | directive |
|---|---|
| 1 | Idol is an **information-propagation system**: |

```text
observations → identities + facts → demand → lawful realization space → minimum physical work
```

| # | directive |
|---|---|
| 1 | Stages exist only as **realization choices** over the same semantic graph. |
| 2 | A new stage is admissible only when irreducibility is proved; otherwise the capability belongs as relations, facts, observations, demands, laws, witnesses, transformations, worlds, or realizations in the one graph. |

| section |
|---|---|
| Universal optimization state |

| # | directive |
|---|---|
| 1 | Extend the working state beyond the early tuple: |

| Dimension | Question |
|---|---|
| **identity** | What semantic thing is this? |
| **facts** | What is known? |
| **observations** | What differences can matter? |
| **demand** | Which portions/qualities are required? |
| **laws** | What transformations/compositions are valid? |
| **change** | How do facts/outputs respond to input changes? |
| **correspondence** | What is equivalent across transformations/incarnations? |
| **search** | What alternative solutions are discoverable? |
| **proof** | Which alternatives are actually lawful? |
| **cost** | What physical resources does each consume? |
| **world** | Under what target/authority/deployment constraints? |
| **realization** | Which lawful physical choice wins? |

| # | directive |
|---|---|
| 1 | **Directionality is not a second relation identity.** Solving mode (forward/inverse/partial) is a fact over the same semantic relation. |

| section |
|---|---|
| Interoperable algebras (the moat) |

| # | directive |
|---|---|
| 1 | Make these **interoperable algebras over the same identities**: |

| # | directive |
|---|---|
| 1 | relational composition |
| 2 | observation projection |
| 3 | world injection |
| 4 | demand propagation |
| 5 | change propagation |
| 6 | equivalence |
| 7 | realization selection |

| # | directive |
|---|---|
| 1 | Then compiler optimization, query planning, partial evaluation, incremental computation, automatic differentiation, program synthesis, hardware synthesis, distributed placement, and foreign adaptation become **different queries over the same graph**, not separate semantic kingdoms. |

| section |
|---|---|
| Diagnostic and refusal shape (target) |

| # | directive |
|---|---|
| 1 | Failures should surface **explanation-minimal** missing or conflicting facts — not cascades of parser/backend symptoms. |
| 2 | Optimization refusals likewise: the smallest fact blocking realization R (`alias(x,y) unknown`, not forty downstream reasons). |
| 3 | Negative knowledge, exclusion sets, and contradiction as unreachable region are first-class graph facts (see census § XXXV). |

| section |
|---|---|
| Hard rules for agents |

| # | directive |
|---|---|
| 1 | **Do not filter semantic facts at DNIR.** DNIR is a realization artifact; facts lost there must be justified by demand, not backend convenience. |
| 2 | **Do not choose relations by hard-coded names in Sema.** Names are subjects; meaning is relation identity + facts. |
| 3 | **Do not alter canonical source for immature backends.** Fix realization or add facts; do not weaken law-facing source to silence a backend. |
| 4 | **Plugins may propose realization; they may not define meaning.** External providers supply candidates, laws, witnesses, costs, and applicability — not identities or relation semantics. |
| 5 | **Trusted core stays small.** Expensive or learned machinery sits outside; certificates refine into a small checker (eBPF/Kops/Jitterbug pattern). |
| 6 | **Boundary contraction is generic.** When an intermediate representation is unobserved, optimize `g ∘ f` as one semantic unit; cancellation and adjoint pairs are relation-algebra laws, not ad hoc peephole rules. |
| 7 | **Observation-relative equivalence is first-class.** Two states may differ in full value but coincide for the demanded observation (`x ≡_demand y`); this extends recurrence quotient and supercompilation generalization. |

| section |
|---|---|
| Supercompilation-shaped engine (target shape) |

| # | directive |
|---|---|
| 1 | Over any demanded graph region: |

```text
observe region
→ unfold semantic relations
→ propagate exact facts
→ recognize recurring semantic state
→ generalize when growth threatens (whistle / homeomorphic embedding)
→ fold equivalent state
→ residualize only demanded semantics
```

| # | directive |
|---|---|
| 1 | Homeomorphic embedding, memoized configurations, constructor specialization, deforestation-as-consequence, interprocedural fusion, and demand-aware equivalence are **one engine**, not named passes. |

| # | directive |
|---|---|
| 1 | The same engine admits a **generalize ↔ specialize** axis (anti-unification upward, specialization downward) and **semantic factoring** — store `common skeleton + varying facts` instead of N expanded copies. |
| 2 | Re-generalization is a first-class response to specialization explosion and code-size FTCFTW, not an afterthought. |

| section |
|---|---|
| Relational solving (target shape) |

| # | directive |
|---|---|
| 1 | Same relation, multiple solving modes as facts: |

| # | directive |
|---|---|
| 1 | known inputs → outputs |
| 2 | known output → possible inputs |
| 3 | partial input + constraint → complete value |
| 4 | relation + desired property → synthesize witness |
| 5 | “what fact is missing to make this application legal?” |

| section |
|---|---|
| Realization below the binary |

| # | directive |
|---|---|
| 1 | World/effect facts may select realization at: |

```text
process · unikernel · WASI component · eBPF · firmware · bare-metal · kernel module · GPU · FPGA
```

| # | directive |
|---|---|
| 1 | Same semantics; different deployment realization. |
| 2 | Syscall elimination/fusion, storage topology, network protocol choice, and NUMA/device placement are ordinary physical domains — not new source APIs. |

| section |
|---|---|
| Tonight's priority injection (supersedes fixture-chasing) |

| # | directive |
|---|---|
| 1 | Read this before any code change. |
| 2 | A **passing fixture is not the objective.** |

| # | directive |
|---|---|
| 1 | **Never repair a downstream consumer when its upstream authoritative fact is wrong.** If lowering needs to filter, reinterpret, recover, or correct graph facts, stop and move the missing fact upstream. |

| Anti-pattern | Required response |
|---|---|
| `filterCheckedCallOperands` / AST call recovery in DNIR | Fix `graph.application.arguments` producer; DNIR must trust the pack |
| Hard-coded home priority (`iter` before `table`) | Exact descriptor/world/relation facts, or **ambiguous** — never first-match |
| `expandableRecordForName` / local-name record inference | Structured value id + descriptor + field facts from the graph |
| Shaping canonical `.id` for immature direct lowering | Fix realization unless source violates current law |
| Expanding `lib/compiler/monolith.id` toward compiler B | Probe only — B must exercise real home/module composition |
| Self-host score green without authority gain | Name the semantic fact gained, not merely the DNB removed |

| # | directive |
|---|---|
| 1 | **Commit review question (mandatory before push):** |

> If I deleted all source spelling, AST shape, filesystem names, and host-local
> variable names after resolution, would my change still know enough to make this
> decision?

| # | directive |
|---|---|
| 1 | If **no**, the change is almost certainly at the wrong layer. |

| # | directive |
|---|---|
| 1 | **Scoreboard discipline:** treat `gate/selfhost.sh` as a coarse probe with two dimensions — physical reach **and** semantic authority quality. |
| 2 | Never copy counts from static reports; use executable ledgers only. |

| # | directive |
|---|---|
| 1 | **Focused experiment ≠ aggregate evidence.** A gate success on a dirty tree is not proof of incarnation closure. |

| # | directive |
|---|---|
| 1 | **Central overnight rule (mandatory):** every time a blocker disappears, ask what authority you added. |
| 2 | If the answer is "the backend now recognizes another source/AST/storage pattern," the architecture got worse. |
| 3 | If the answer is "the graph now knows an exact fact earlier and downstream code became simpler," you are moving toward Idol. |
| 4 | Pipeline traversal success is not progress; removing the need for pipeline stages is. |

| # | directive |
|---|---|
| 1 | See `docs/architecture-negative-controls.md` for the full systemic-misunderstanding catalog and companion gate IDs. |

| section |
|---|---|
| Where to look next |

| # | directive |
|---|---|
| 1 | **Negative controls:** `docs/architecture-negative-controls.md` · `gate/architecture-negative.sh` · `gate/architecture-companion.sh` |
| 2 | **Canonical source debt:** `docs/projections/canonical-source-debt.md` |
| 3 | **Capability map:** `docs/history/optimization-frontier-census.md` |
| 4 | **Priority compass:** `docs/AGENT_ALIGNMENT.md` |
| 5 | **Open obligations:** exact current `gaps/GAP-*.md` files |
| 6 | **Supreme law:** `docs/spec/law.md` then `docs/spec/constitution.md` |
