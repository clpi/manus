# duon 0.1 — Soundness: Proven, Runtime-Checked, Diagnostic

**Owed by Pass 100 §22 · commissioned by Pass 106 §1 · normative.**

Pass 106 asks the question a trained reader asks fifth: *"Is the fact system
decidable? What happens when the checker can't prove?"* — and answers it with
the shape of the required page: *"an explicit three-state outcome — proven /
runtime-checked / diagnostic — no silent fourth state, SMT optional and not
load-bearing. Say where the line is before someone finds it for you."*

§7 says where this repository is, measured. The short version, put at the top
because burying it would be the exact dishonesty this page exists to prevent:
**the fourth state exists in this tree today, and §7 names five instances of it
found in one afternoon.**

---

## 1. The three states

Every **obligation** — a claim the program's correctness depends on and the
source does not state as a literal fact — is discharged into exactly one of
three states, and the choice is recorded.

```
PROVEN            the checker has a derivation. No code is emitted for the
                  obligation. The derivation is a witness, addressable by
                  `why(proof)(site)`.

RUNTIME-CHECKED   the checker has no derivation, and the obligation is
                  representable as a check at a dominating program point. The
                  compiler INSERTS the check, its failure is discharged by the
                  position's contract (a routed failure, or a fault at a sealed
                  boundary), and the insertion is REPORTED — it appears in the
                  manifest and `why(check)(site)` names it. A runtime check is
                  never silent.

DIAGNOSTIC        the checker has no derivation and no admissible check site.
                  Compilation stops, naming the obligation, the site, and the
                  fact that is missing.
```

Two properties are claimed, and both are part of the rule rather than
decoration:

- **Totality.** Every obligation lands in exactly one state. There is no
  "assume and continue".
- **Recording.** The state is inspectable after the fact. A state that cannot
  be queried is indistinguishable from silence, which is why `why` is a
  soundness surface and not a debugging convenience.

### 1.1 The fourth state

```
SILENT            accepted; not proven; not checked; wrong at run time.
```

**There is no silent fourth state.** That is not an observation about the
current implementation — §7 shows it is false of the current implementation. It
is the specification's strongest single commitment, and its violations are a
defect class rather than a trade-off:

> A fourth-state instance is unconditionally blocking. It may not be traded
> against performance, against compile time, against ergonomics, or against
> schedule. It is repaired by moving the obligation into one of the three
> states — and moving it into DIAGNOSTIC is always available, so the repair is
> never blocked on research.

The last clause is what makes the commitment keepable. Every fourth-state bug
has a trivially available fix: refuse the program. The interesting engineering
is only in how many obligations reach PROVEN instead.

### 1.2 Faults are not a fourth state

A **fault** (Pass 107 §3) is a contract violation at a sealed boundary. It
unwinds the world — task-scope teardown, journals flushed, witnesses dumped —
and never the process by default. A fault is the *failure branch of a
RUNTIME-CHECKED obligation*, so it lives inside state 2. It is loud, it is
recorded, and its site was announced at compile time.

Likewise a **diagnosis** is state 3 and a **routed failure** (B-15) is ordinary
control flow. Pass 107's three categories and this page's three states are the
same partition seen from two directions.

---

## 2. Is the fact system decidable?

Yes, and the reason is that it is deliberately not a theorem prover.

```
D1  FINITE VOCABULARY. Facts are drawn from a fixed per-descriptor registry —
    the family registry (§10) plus the descriptor's declared refinements. A
    program adds EDGES; it cannot mint a new kind of fact. New customization
    points arrive as a registry row or nowhere, and that rule is what bounds
    the vocabulary.

D2  FINITE HEIGHT. The abstract state at a program point is a finite product of
    finite-height lattices: interval facts widen onto a fixed ladder, set facts
    are bounded by the program's own literal set, and structural facts are
    boolean. A monotone transfer function over a finite-height lattice reaches
    a fixpoint. Termination is by construction, not by timeout.

D3  NO ALIAS FIXPOINT. Aliasing is not inferred; it is DECLARED, as ownership
    and uniqueness facts. Pass 104's "semantics archaeology" — alias analysis,
    UB reasoning, idiom recognition, devirtualization — is the undecidable half
    of the incumbent problem, and Duo does not have it because the source never
    discarded the answers.

D4  PREDICATES ARE REGISTRY ENTRIES. `u16 & positive` names a REGISTERED
    refinement carrying a decision procedure, not an arbitrary Duo function
    evaluated at compile time. A predicate that is arbitrary Duo is not a
    refinement — it is a runtime check with a name, and it lands in state 2 by
    rule rather than by accident.

D5  THE ESCAPE HATCH IS REFUSAL, NOT SEARCH. When a query exceeds its budget
    the answer is "not proven", which routes to state 2 or state 3. It is never
    "assume true".
```

**The budget rule.** Budgets exist — the closure is a memoized query engine with
tombstones (§11) — and budget exhaustion must be *indistinguishable from* "not
proven". A budget may cost precision. It may never cost soundness, and it may
never be observable in a program's meaning. Two builds with different budgets
must produce programs with identical behaviour, differing only in how many
checks are emitted.

---

## 3. Flow-sensitive refinement checking

### 3.1 What is decided (state 1)

An obligation at a use site is PROVEN when it follows from any of:

- a literal, and the literal is in range
- the declared contract of the enclosing parameter, at the callee boundary
- a guard that **dominates** the use — inside `if digit(b) …`, `b` is a digit
- the success arm of a binding condition, including the correlated pack
  (`if v, err = f(x)` proves `v` present in the first arm)
- a guard-chain link (Pass 101): links to the left dominate links to the right,
  which is precisely why `and` after a binding is a *correlated* guard and not
  a coincidence
- a loop-invariant established at entry and preserved by the body, where the
  induction fact comes from the iterator (`range`, `iterate`) rather than from
  inference
- a fact upgraded by a family edge carrying a legality witness — sortedness
  after `sort`, uniqueness after a dedup edge, density after a fill

### 3.2 What is deferred to a runtime check (state 2)

DEFERRED when the obligation is not derivable **and all three hold**:

1. there is a single dominating point at which the value enters the refined
   position, so one check suffices;
2. the refinement's predicate is executable at that point; and
3. the position has a failure discharge — a declared contract to route into, or
   a sealed boundary where the violation is a fault.

The check is emitted at the dominating point, not at every use. Its cost is a
row in the cost model (`docs/spec/cost.md` §3) and its existence is a manifest
entry.

**State 2 is a choice the programmer may forbid.** `world@{ checks = false }` is
not "skip the checks" — it converts every state-2 outcome into state 3. That is
the realtime and certification mode: *refuse rather than check*, so that a
worst-case budget contains no inserted branch the programmer did not see.

**State 2 is also the proof engine's positive control.** `world@{ checks = all }`
converts state-1 sites back into state-2 sites and emits the check anyway. A
check that fires in that mode is a **compiler bug**, by definition, because the
site was proven. This gives the fact system the thing CLAUDE.md §3 demands of
every zero: a way to distinguish "proved everything" from "the prover is
broken". A soundness claim with no positive control is a claim that reports 0/N
and hopes.

### 3.3 What is refused (state 3)

REFUSED when any of:

- the predicate is not executable — an abstract fact like `sorted` over an
  unbounded stream, or a layout fact like `at(a)` that has no runtime witness
- there is no admissible check site: the value crosses a boundary the checker
  cannot instrument, such as a rung-6 ingested value with no layout proof
- the position has no failure discharge, so a violation would have to be silent
  — refusing is the only outcome that preserves §1.1
- two facts in scope are contradictory, making the point unreachable-by-fact
  while the program reaches it

A state-3 diagnostic names the obligation, the site, and **the fact that would
discharge it** — the repair-first layout the diagnostics spec owes (Pass 106 §1).
"Cannot prove `positive`" is a failure; "cannot prove `positive`; add
`if v > 0` before line 12, or declare the parameter `u16 & positive`" is the
product.

---

## 4. SMT is optional and not load-bearing

An SMT solver may be attached as an **oracle for state 1 only**. Its contract:

```
O1  it MAY move an obligation from state 2 or state 3 into state 1
O2  it MAY NOT move an obligation OUT of state 1
O3  it MAY NOT move an obligation into state 3 that would otherwise be state 2
O4  its answer MUST come with a proof term the core checker can replay WITHOUT
    the solver
```

**What degrades if it is absent.** The PROVEN column shrinks. The
RUNTIME-CHECKED column grows by the same amount, except for obligations with no
admissible check site (§3.3), which move to DIAGNOSTIC and require an explicit
guard from the programmer. Programs get slower; a few programs stop compiling
until a guard is written.

**No program changes meaning.** That is the load-bearing sentence, and O2 and O3
are what buy it. A language whose semantics depend on whether a solver was
installed does not have semantics.

**How SMT stays compatible with U2 (deterministic build).** A solver's answer is
nondeterministic in time and version-dependent in content. O4 is the fix: the
solver's result is recorded as a **witness in the artifact** and replayed on
subsequent builds. A build that reaches a different state than the recorded
witness is a build-determinism failure — loud — and never a silent
re-decision. The solver participates in the *first* build and in no other.

---

## 5. Soundness statements

Each is a claim, what it rules out, and how it is falsified. None of them is
machine-checked today (§6, last row).

**S1 — FACTS.** *If a fact `p` is in the checker's abstract state at a program
point, then `p` holds of the concrete value at that point in every execution
reaching it.*

- Rules out: a fact-keyed optimization producing a different answer than the
  same program with the optimization disabled.
- Falsifier: the differential harness. A fact-keyed rewrite must agree with the
  unrewritten program on the same inputs; disagreement falsifies S1 and names
  the fact. This is the generalized form of the rule CLAUDE.md §3 paid for the
  hard way — *a detector must verify every constant its emitter assumes*.

**S2 — REFINEMENTS.** *For every use of a value in a position declared `T & r`,
at least one holds: (a) the checker has a derivation of `r`; (b) a check of `r`
dominates the use and its failure is discharged; (c) the program did not
compile.*

- Rules out: the fourth state, for refinements specifically.
- Falsifier: a program that compiles, emits no check, and violates `r` at run
  time.

**S3 — CDR (B-13).** *A declared shape at a position realizes through exactly
ONE direct edge, per position. No transitive search, ever. Bare positions never
coerce. Failure positions never convert.*

- Rules out: two conversion paths with different results, selected by
  optimization level or by edge-registration order. Uniqueness is what makes
  CDR-erasure sound: erasing a conversion that restates the contract cannot
  change the value, because the only edge available was the identity.
- Also rules out: a conversion silently succeeding between incompatible shapes.
- Falsifier: a position where registering an additional, unrelated edge changes
  the program's output.

**S4 — DEMAND-ROUTE (B-15).** *Inside a declared failure contract, an unbound
failure position early-exits with the pack. Callee failures are a SUBSET of the
contract's declared failures or the program does not compile. No contract, no
routing.*

- Rules out: a failure being dropped; and a failure being widened past what the
  caller declared, which is the quiet half and the one that turns a typed error
  union into a lie.
- Falsifier: a program that compiles and produces a success value on a path
  where a callee failed. **§7 exhibits exactly this.**

**S5 — OBLIGATION (B-14).** *An unconsumed failure position is a diagnostic.
Bind it, route it, or drop it by name. Silent loss is unexpressible.*

- Together with S4, the set of programs in which a failure can be lost is
  **empty**. S4 covers the contracted case; S5 covers the uncontracted one.
  Neither alone is sufficient, which is why removing either is a soundness
  change and not a convenience change.

---

## 6. Where the line is

Stated here so that nobody has to find it. None of the following is claimed.

| not claimed | what is claimed instead |
| --- | --- |
| **Termination.** Duo does not prove your loop halts. | Nothing. There is no totality checker and none is planned. |
| **Absence of the allocation fault.** Memory exhaustion is a fault. | `ward@allocation_free` proves no allocation *edge* is reachable — stronger and narrower than "will not run out". |
| **Overflow with non-constant inputs.** | CHECKED (state 2), announced, and proven away only where an interval fact covers it (§12 OVFL). |
| **Data-race freedom.** | Nothing. The concurrency memory model is a bridged open decision (§22). |
| **Foreign values.** Ingested C / Rust / TS descriptors. | Rung-6 with provenance and trust. A layout proof makes the ADAPTER zero-cost; it does not make the foreign contract true. Facts crossing that boundary are ASSUMPTIONS, labelled as such in the witness. |
| **`lower(target)` edges and the ISA descriptors.** | Oracle-checked (Pass 103 §5: foreign toolchains are CI oracles), not proven. An admitted rewrite carries legality DATA; the data is checked, the checker is not verified. |
| **Generated edges.** `graph.*` iteration and the `add` family. | A generated edge is checked like any other edge when it lands. The GENERATOR is not proven to emit only well-formed edges. |
| **Layout assertions about the world:** `at(a)`, `volatile`, `packed & le` over an ingested buffer. | These are assertions the programmer makes about memory the compiler cannot see. **This is the deliberate hole.** It is spelled visibly, it is the only place a fact is admitted with neither a derivation nor a check, and it is the one construct where the fourth state is legal — because the programmer took the state explicitly. |
| **The checker itself.** | Not verified. Pass 105 names a verified checker as a day-0 commitment for the safety wedge; it does not exist. Until it does, S1–S5 are properties of a specification and a test suite, not of a machine-checked artifact. |

One more line, because it is the one an expert probes for: **soundness here is a
property of the FRONT END, and the descent has its own.** S1 says the checker's
facts are true of the source semantics. It says nothing about whether
`lower(arm64)` preserved them. That second obligation is discharged by the
differential harness against a CI oracle, which is testing, not proof, and the
distance between those two words is not being papered over.

---

## 7. Status in this repository

Measured **2026-08-08**, branch `canonical-to-relation`, `zig build` debug
binary at `zig-out/bin/duo`. Every row below is a probe that was run; exit codes
were read without a pipe and values were read from output, never inferred from
"it compiled".

### Specified and implemented

- **The checker is not inert — positive control passes.** `x: u8 = "hello"`
  fails with exit 1 and `type mismatch: variable 'x' declared as 'u8', but
  initializer has type 'str'`. Every negative result below is therefore a hole
  in the checker, not an absent checker.
- **The `&` refinement edge exists for LAYOUT facts.** A descriptor declared
  `& packed` checks clean, exit 0. The spelling LAW-STRATA gives the refinement
  edge is real; it is wired to layout only.
- **The failure PACK works one level deep.** A callee declared `: i64 | str`
  returning `nil, "over"`, consumed through a binding condition, correctly
  selects the else arm and yields the detail. This is the positive control that
  makes the B-15 result below meaningful rather than a broken probe.

### Specified and NOT implemented

- **Value refinements do not parse.** `v: u16 & positive` in a parameter gives
  `expected ')', got '&'`; in a binding shape it gives `expected expression,
  got '&'`. §3 of this page describes a decision procedure over a surface that
  does not exist. Not "unimplemented checking" — **no surface at all**, so
  there is no state 1, 2, or 3 for a value refinement.
- **`check`, `why`, and `todo` are undeclared functions.** The RECORDING half
  of §1 has no surface. Even where the compiler did make a three-state decision,
  it could not be inspected — which is the precise condition under which silence
  is undetectable. This is why the missing `why` is a soundness gap and not a
  tooling gap.
- **No SMT anywhere in the tree** (the only matches are `smtp`). Consistent with
  "optional" — but note the shape of the consistency: §4 promises that absence
  shrinks the PROVEN column, and today there is no PROVEN column to shrink.
- **B-14 is unenforced.** A caller with no declared contract binds a failing
  callee's success value and ignores the failure position: `duo check` exits 0
  with "no errors". S5's diagnostic does not exist.

### The fourth state, found

Five instances, from roughly twenty probes. The density is the finding: this was
not a search.

1. **B-15 does not route, and the failure becomes a wrong success value.**
   `use = (n: i64): i64 | str` calls a `scan` that fails, binds `v = scan(n)`,
   and returns `v + 1`. Expected: the failure routes and the caller reports
   `err over`. Measured: **`ok 1`**, exit 0, `duo check` green. The generated C
   takes only the first value from the invoke and adds 1 to nil. The positive
   control — the same `scan(99)` consumed directly through a binding condition —
   correctly reports `direct err over`, so the probe is sound and the routing is
   not. *A declared failure was silently converted into a wrong success value.*
   This is S4's falsifier, exhibited.

   The same program under `--backend=direct` **refuses**, exit 1, bail site
   `native-scalar precheck — ret-pack:i64|error`. That is state 3 and it is the
   correct outcome. So the two backends disagree about which state this program
   is in, and the default path is the one that picks the fourth. A soundness
   property that holds only on the backend the toolchain does not default to is
   not a property the language has.

2. **`x: u8 = 300` prints 44.** Exit 0 from `duo check`, exit 0 from the run.

3. **`y: i8 = 200` prints -56.** Same.

4. **`z: u16 = 70000` prints 4464.** Same. Rows 2–4 are one defect with three
   witnesses: a range-violating initializer is neither proven, nor checked, nor
   diagnosed — it is truncated.

5. **`7 / 0` with `i64` operands prints 9218868437227405312** — the bit pattern
   of IEEE `+inf` read as an integer, exit 0. B-4 says `i64/i64` truncates;
   measured, the operands took the float path and the result was reinterpreted.

Adjacent, in the same class and recorded in `docs/spec/cost.md` §7: `i64`
overflow wraps silently, and a 5,000,000-deep tail call exits 139 (SIGSEGV)
against Pass 107's "No SIGSEGV as an API".

None of these had a gap file at the time of writing.

### A false green worth naming

`gaps/GAP-025.md` records `blocks 5/5` for §20, with `shc/parse.duo` — the
spec's own DEMAND-ROUTE exhibit, headed *"demand-route shown"* — checking clean
once joined with its module. Finding 1 shows routing is not emitted. Both are
true: `duo check` admits the *construct*, and the default backend drops the
*semantics*. **A green `duo check` on the routing block is not evidence that
routing happens**, and anyone reading the corpus ladder as a soundness signal
will read it wrong. Checking clean and routing correctly are two measurements;
only the second was ever the claim.

### What would make this page operative

The rule in §1.1 needs a number, for the same reason `blocks-passing/
blocks-total` needed one. The gate is an **obligation ledger**: per compilation,
the count of obligations in each of the three states, plus the fourth-state
count, which must be zero. Today the first three are unmeasurable because there
is no `why` and no refinement surface, and the fourth is at least five. A page
that says "no silent fourth state" while the tree carries five is not a lie
only as long as it says so in the same document — which is what this section is
for.
