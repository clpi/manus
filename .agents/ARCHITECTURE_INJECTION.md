# Idol architecture injection — agent orientation

**Status:** durable agent orientation only. **Not language law.** If this file
conflicts with `docs/spec/law.md` or `docs/spec/constitution.md`, stop and repair
this projection.

## Mental model shift

Idol is **not** a conventional multi-pass compiler with a pile of named IRs.

Idol is an **information-propagation system**:

```text
observations → identities + facts → demand → lawful realization space → minimum physical work
```

Stages exist only as **realization choices** over the same semantic graph. A new
stage is admissible only when irreducibility is proved; otherwise the capability
belongs as relations, facts, observations, demands, laws, witnesses,
transformations, worlds, or realizations in the one graph.

## Universal optimization state

Extend the working state beyond the early tuple:

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

**Directionality is not a second relation identity.** Solving mode
(forward/inverse/partial) is a fact over the same semantic relation.

## Interoperable algebras (the moat)

Make these **interoperable algebras over the same identities**:

- relational composition
- observation projection
- world injection
- demand propagation
- change propagation
- equivalence
- realization selection

Then compiler optimization, query planning, partial evaluation, incremental
computation, automatic differentiation, program synthesis, hardware synthesis,
distributed placement, and foreign adaptation become **different queries over the
same graph**, not separate semantic kingdoms.

## Diagnostic and refusal shape (target)

Failures should surface **explanation-minimal** missing or conflicting facts —
not cascades of parser/backend symptoms. Optimization refusals likewise: the
smallest fact blocking realization R (`alias(x,y) unknown`, not forty downstream
reasons). Negative knowledge, exclusion sets, and contradiction as unreachable
region are first-class graph facts (see census § XXXV).

## Hard rules for agents

1. **Do not filter semantic facts at DNIR.** DNIR is a realization artifact;
   facts lost there must be justified by demand, not backend convenience.
2. **Do not choose relations by hard-coded names in Sema.** Names are subjects;
   meaning is relation identity + facts.
3. **Do not alter canonical source for immature backends.** Fix realization or
   add facts; do not weaken law-facing source to silence a backend.
4. **Plugins may propose realization; they may not define meaning.** External
   providers supply candidates, laws, witnesses, costs, and applicability — not
   identities or relation semantics.
5. **Trusted core stays small.** Expensive or learned machinery sits outside;
   certificates refine into a small checker (eBPF/Kops/Jitterbug pattern).
6. **Boundary contraction is generic.** When an intermediate representation is
   unobserved, optimize `g ∘ f` as one semantic unit; cancellation and adjoint
   pairs are relation-algebra laws, not ad hoc peephole rules.
7. **Observation-relative equivalence is first-class.** Two states may differ in
   full value but coincide for the demanded observation (`x ≡_demand y`); this
   extends recurrence quotient and supercompilation generalization.

## Supercompilation-shaped engine (target shape)

Over any demanded graph region:

```text
observe region
→ unfold semantic relations
→ propagate exact facts
→ recognize recurring semantic state
→ generalize when growth threatens (whistle / homeomorphic embedding)
→ fold equivalent state
→ residualize only demanded semantics
```

Homeomorphic embedding, memoized configurations, constructor specialization,
deforestation-as-consequence, interprocedural fusion, and demand-aware
equivalence are **one engine**, not named passes.

The same engine admits a **generalize ↔ specialize** axis (anti-unification upward,
specialization downward) and **semantic factoring** — store `common skeleton +
varying facts` instead of N expanded copies. Re-generalization is a first-class
response to specialization explosion and code-size FTCFTW, not an afterthought.

## Relational solving (target shape)

Same relation, multiple solving modes as facts:

- known inputs → outputs
- known output → possible inputs
- partial input + constraint → complete value
- relation + desired property → synthesize witness
- “what fact is missing to make this application legal?”

## Realization below the binary

World/effect facts may select realization at:

```text
process · unikernel · WASI component · eBPF · firmware · bare-metal · kernel module · GPU · FPGA
```

Same semantics; different deployment realization. Syscall elimination/fusion,
storage topology, network protocol choice, and NUMA/device placement are ordinary
physical domains — not new source APIs.

## Where to look next

- **Capability map:** `docs/history/optimization-frontier-census.md`
- **Priority compass:** `docs/AGENT_ALIGNMENT.md`
- **Open obligations:** exact current `gaps/GAP-*.md` files
- **Supreme law:** `docs/spec/law.md` then `docs/spec/constitution.md`
