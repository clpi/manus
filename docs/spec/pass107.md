# Pass 107 — The Name, the Memory Decision, and the Boring Rulings

**Epoch 2 · Closes Pass 106's name item and the E1 memory bridge · Amends
Pass 100 §11 and §12 · Higher pass number wins.**

## 1. The name: `duon`

Criteria: unique token (greppable, no incumbent collision), ≤5 letters,
pronounceable, keeps the heritage — the language is *named for its two copulas*,
IS and HAS, and should stay named for them — and clean across the registries
that function as the modern namespace.

Measured (HTTP status; 404 = free):

```
name      pypi   npm    verdict
duon      FREE   FREE   ✓ candidate #1 — contains "duo", 4 letters,
                        pronounced DOO-on, near-zero collision surface
duolang   FREE   FREE   ✓ safe compound fallback
gemel     FREE   taken  ✗ (npm)
dyad      taken  taken  ✗
twain     taken  taken  ✗ (also the TWAIN imaging standard — hard kill)
vau       taken  taken  ✗
```

crates.io blocks anonymous probes — recheck authenticated. GitHub org pages
return 200 for users and orgs alike — recheck via API.

**Decision: `duon`**, with `duolang` as the compound fallback if the whois pass
on `duon.dev` / `duon.org` fails.

Toolchain names follow mechanically: the `duon` binary, `duonsh`, `libduon`.
**`.duo` files keep their extension** — the copula story survives intact:
*duon, the language of two copulas.*

Register the trinity — domain, org, package names on all three registries — in
one sitting before anything is public. **Pass 106's name item closes when the
receipts exist, not when this decision is written.**

## 2. The memory decision record

Pass 106 §1 observed that "undecided in a footnote" reads as hand-waving while
"undecided with a process" reads as rigour. This is the record.

**Candidates weighed:**

- (a) tracing generational GC
- (b) pure ownership / borrowing, Rust-shaped
- (c) full naive reference counting
- (d) **precise reference counting with static elision and reuse
  (Perceus-class, as Koka proved) + regions/arenas + the existing drop ladder**

**Criteria, from the charter:** determinism (U2 — certification and
reproducibility forbid stop-the-world nondeterminism); embeddability (wedge 1b
— hosts demand bounded, pause-free behaviour); no runtime hosting (Pass 103);
agent legibility (`why` must explain every free); throughput honesty.

**Decision: (d).** The tiered model, now permanent:

```
tier 1  PROVEN DROPS      ownership/last-use facts insert frees statically —
                          the majority under demand; zero runtime cost
tier 2  REGIONS           effect-scoped arenas (message/request/frame scopes)
                          — bulk free, allocation-free steady states provable
tier 3  MANAGED RC        precise counts ONLY where sharing facts require;
                          counts elided by borrow proofs (Perceus-class reuse:
                          uniqueness ⇒ in-place update, no count traffic);
                          cycles: deferred trial-deletion confined to
                          cycle-POSSIBLE shapes (a static fact — acyclic
                          descriptors never pay)
never   a tracing stop-the-world collector. Latency is a language property.
```

**Consequences now ruleable:**

- **Weak references** — the Pass 81 gap closes. `ref(weak)` is a non-owning
  place with an invalidation fact; reads yield `t | nil`, honestly.
- **Finalization** — tier-3 `release` runs deterministically at last drop. No
  async finalizer queue exists.
- **The honest risk, ledgered:** RC-with-elision versus tracing on share-heavy
  graph workloads is the one open performance question. It enters the benchmark
  corpus BY NAME, and Koka/Perceus citations enter related work — independent
  convergence, and we say so.

The E1 bridge retires. **`why(free)(x)` is the acceptance fixture: every
deallocation explains itself.**

## 3. The boring rulings

The small tables experts check first (Pass 106 §2 item 4), decided now.

**Hashing vs determinism.** Hash functions are keyed, SipHash-class, and the key
is a **world fact** — a deterministic default key per build, so U2 holds and
replays reproduce; DoS-exposed services inject a secret key world-fact, getting
resistance without losing within-world determinism. The conflict every other
language has here is dissolved by machinery that exists anyway.

**Panics.** *There is no panic.* There are **diagnoses** (compile time),
**routed failures** (runtime, B-15), and **faults** — contract violations at
sealed boundaries. A fault unwinds the **world**: task-scope teardown, journals
flushed, witnesses dumped. Never the process by default. `abort` is a
capability.

**Recursion and stack.** TAIL is guaranteed (B-TAIL). Non-tail depth is metered
by a world fact with a routed `error.depth`. **No SIGSEGV as an API.**

**Float rendering.** Shortest round-trip (Ryu-class) is the `to(str)` edge.
Locale is never involved — the sibling of B-11's byte-lexicographic string
comparison.

Each lands in the spec's numerics/text pages as their first rows.

## 4. What this means for this repository today

- **The rename is not a bulk `sed`.** `.duo` keeps its extension, so the corpus
  is untouched; what changes is the BINARY name, the org, and the package names
  — none of which exist publicly yet. The cheapest moment to do this is before
  the receipts, which is now. Nothing in this commit renames anything: the
  decision is recorded, the registration is owed.
- **Tier 1 is the only tier this tree has.** `release` exists as a family row
  and the drop ladder is described; there is no RC, no region allocator, and no
  `ref(weak)`. The decision record does not change that — it makes the target
  unambiguous so the ledger can measure distance to it.
- **`why(free)(x)` does not exist**, and it is the acceptance fixture for this
  ruling. Recorded as owed rather than implied.
- **The boring rulings are decided but unimplemented.** Hash keying, faults,
  depth metering, and Ryu-class float rendering are all absent from the current
  toolchain. Deciding them costs nothing today and prevents the expensive thing:
  discovering at ecosystem scale that two of them were settled differently in
  two places.
