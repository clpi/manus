# Pass 104 — The Compression Thesis: Why the Descent Is Fast

**Epoch 2 · Supersedes Pass 103 §5 · Amends Pass 100 §13 and §22 · Higher pass
number wins.**

Pass 103 priced the backend in the incumbent's currency ("decades of lore").
That framing is corrected here, because the mandate is right on the merits:
**Duo does not inherit their timeline because it does not inherit their
problem.** The decades were not spent on the essential difficulty of turning
dataflow into instructions — that part is textbooks. They were spent on four
structural sinks, of which Duo deletes three by construction and industrializes
the fourth.

## 1. Where the decades actually went

**Sink 1 — recovering discarded semantics (the largest).** A plurality of
mature-compiler engineering is *archaeology*: alias analysis, UB reasoning,
loop-idiom recognition, devirtualization — heroic reconstruction of facts the
source language threw away. **Duo never discards them.** Demand, ownership,
order, range, layout and sealing arrive at the backend as node data. The
hardest half of optimization is not solved faster; it is **not a task**.

> The compression theorem in one line: **their optimizer infers; ours reads.**

**Sink 2 — mutable-IR coupling.** Passes over a mutable IR interact through
implicit invariants; every new pass multiplies against every old one;
verification arrived fifteen years late (Alive) as a research retrofit. In Duo a
transformation is an **edge with its legality as data** — side conditions
declared, witnesses deposited, admission checked. The pass-interaction matrix
(N passes × M invariants × K targets of quadratic-and-worse coupling — the true
source of the person-decades) collapses to **admission of independent, checked
rewrites**. Multiplicative becomes additive.

**Sink 3 — the compatibility museum.** Dialects, flag matrices, legacy targets,
ABI archaeology: a combinatorial test surface that consumed careers. Duo ships
**one canonical form** (the canonicalizer deletes the dialect axis), an epoch
discipline instead of eternal backward compatibility, data-described ISAs
instead of per-target code forests, and semantic linking instead of ABI
folklore. The museum is not maintained faster; **it is not built**.

**Sink 4 — serial human lore.** Peephole wisdom, scheduling heuristics,
allocation tricks, accumulated one engineer-insight at a time and deployable
only as trusted hand-written code. This is the sink that remains, and it is the
one the era transforms: **lore becomes search under gates.** A lowering rule, a
peephole, a cost weight is an *edge-shaped, law-bounded, oracle-checkable unit*
— exactly what superoptimizers mine and agent swarms propose in parallel, and
exactly what the enforcement stack was accidentally built to dispose of: laws
check, generated properties test, oracles compare, witnesses record, Ward
measures. Souper-class mining never deployed safely into LLVM because LLVM had
no admission gate. **Duo is an admission gate with a language attached.** The
serial-human bottleneck WAS the timeline, and it is gone.

## 2. The compression law

```
incumbent cost ≈ (passes × invariant coupling) × targets × dialects × legacy
                 + semantics archaeology + serial lore accumulation

duo cost       ≈ Σ independent checked edges  +  data-described targets
                 + 0 (archaeology deleted) + parallel mined lore / gate throughput
```

Every multiplicative axis is made additive or made data. That is the complexity
claim in auditable form — and §4 gives it a velocity metric, so it can be
falsified rather than believed.

## 3. What "fast" concretely looks like, honestly sized

- **The evaluator** is a fold over tables — days-class, plus its
  self-evaluation fixture.
- **The flow realizer** is graph traversal over data the middle already
  produces.
- **Selection for one target** is a set of `lower` edges against a *generated*
  ISA. The descriptors come from vendor machine-readable specs, and
  encode/decode/execute property tests are **generated per instruction** and
  checked against oracle assemblers and silicon — the test suite incumbents took
  years to accrete is a derivation here.
- **Allocation** is linear-scan over places: a textbook algorithm, made clean
  precisely because places carry their facts.

Baseline correctness end-to-end is therefore **weeks-class work under the
gates**. Everything past baseline is the mining loop:

```
propose (agents, superoptimization, ported literature)
  → check legality (Alive-style checking is the DEFAULT ADMISSION, not a retrofit)
  → differential + property tests
  → admit with witness
  → Ward measures
  → blame ranks the next gap
```

Performance stops being a mountain and becomes a **worklist sorted by measured
impact**. That is what "fast across the board, proved at every level" cashes out
to: the parity ladder — beat `-O0`; beat `-O1` on Ward, where fact-wins alone
should suffice; track `-O2` per workload — climbed by admission throughput, with
every rung a published table.

## 4. The gates (speed claims pay the toll like all others)

```
G-D1  evaluator fixed-point fixture (evaluates itself)          days-class
G-D2  flow differential vs evaluator over the full corpus       with G-D1
G-D3  ISA fidelity: generated per-instruction encode/exec       continuous,
      tests vs oracle assembler AND hardware                    automatic
G-D4  end-to-end: corpus binaries byte-run-identical to         weeks-class
      oracle -O0 behavior; ward@allocation_free holds
G-D5  the mining loop live: REWRITES-ADMITTED-PER-WEEK is a     the velocity
      published number; each admission = legality data +        metric — the
      witness + measured Ward delta                             thesis's
G-D6  parity ladder entries published per workload with         falsifier
      blame-ranked gap worklists
```

**If G-D5's number is low, the Compression Thesis is WRONG and the ledger says
so.** That is the difference between this pass and a pep talk.

## 5. Amendments

- **Pass 103 §5 is superseded.** The bill exists; the currency changed — from
  serial engineer-decades to gate throughput.
- **Pass 100 §13** gains the compression law.
- **Pass 100 §22**'s marquee line is reframed: *backend maturity = the mining
  loop's throughput, metered by G-D1..6* — days/weeks-class to baseline,
  worklist-shaped past it, with the velocity metric as the standing falsifier.
- **`CLAUDE.md`** unchanged except the descent row's closing clause:
  *performance work is edge admission — propose, prove, measure; never hand-tune
  without a witness.*

## 6. What this means for this repository today

Recorded so the pass is operative rather than aspirational:

- **Correctness repair is not performance work**, and the "never hand-tune
  without a witness" clause does not forbid it. Fixing a register allocator that
  passes f64 arguments in GP registers is closing Sink 1's *absence* — the
  backend reading facts it already has — not accumulating Sink 4's lore. The
  distinction is whether a witness is available: a miscompilation has an oracle
  (the differential), so the fix is admissible by measurement.
- **`zig build abi-matrix` is a G-D3-shaped gate in miniature** — generated
  shapes, oracle-checked, per-row. It was built because a hand-written corpus
  cannot cover an argument classifier. Generating ISA property tests per
  instruction is the same move one level down, and the existing gate is the
  precedent to extend.
- **The velocity metric has no counter yet.** G-D5 asks for
  rewrites-admitted-per-week as a published number. Nothing in this tree
  currently counts admissions, and until something does, the Compression Thesis
  is unfalsified rather than confirmed. That is an owed gate, not a claim.
- **The gap register is already blame-shaped.** `gaps/GAP-0NN.md` with
  reproductions, and `native-census` / `abi-matrix` / `capability-rows` as
  ranked worklists, are the substrate G-D6 asks for; what is missing is the
  parity ladder table per workload.
