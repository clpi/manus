# Pass 105 — The Leverage Charter: The Business Case, Audited

**Epoch 2 · Amends Pass 100 §22 and §24 · Sequences Pass 101 §3 · Higher pass
number wins.**

This pass governs the ROADMAP, not the diff — with one exception, stated in §6
and effective immediately.

## 1. Anatomy of a language fortune

C++ won by an **unretrofittable property riding an incumbent's distribution**:
zero-cost abstraction *over the C ABI*. C could not add the abstraction, GC
languages could not match the cost, and every C shop was already a C++ prospect.
Rust won the same shape: **memory safety without GC**, a property C++
structurally cannot retrofit after forty years of trying, delivered with cargo
(distribution) into a decade of security-CVE pain (timing).

> The pattern: *a wedge workload in acute pain × a property competitors cannot
> copy × a distribution surface × timing.*

The instructive half is what they **failed to design early**, because those
failures priced in billions of ecosystem drag: C++ shipped without modules, a
package manager, or defined behaviour — each now unfixable at full strength.
Rust shipped async late (a fragmentation scar), compile-time cost structurally,
and orphan-rule friction.

**The lesson is not "move fast". It is that the properties which make the
fortune and the debts which drain it are both set in the first release.**

## 2. The pitch matrix

Each row: pitch · strongest objection · honest answer · proving fixture.

**Agent-native development — THE wedge.** Software throughput is becoming agent
throughput, and agent throughput is bottlenecked on **verification**. Duo is the
only language whose entire design — admission gates, witnesses, canonical form,
semantic emission, MCP-native toolchain — is a verification machine for
machine-written code; every competitor verifies agent output with vibes and code
review. *Objection:* agents write today's languages fine, and nobody adopts a
language for its reviewer. *Answer:* they adopt it for the
**defect-rate-per-agent-dollar** table, and distribution has inverted — agents
adopt languages by context file, not by decade, so the epoch-2 `CLAUDE.md` + MCP
server IS the go-to-market. *Fixture:* the synthesis harness demo — a spec'd
edge implemented, tested and admitted with zero human lines, defect-audited
against the same task given to Python/Rust agents.

**Embedded & safety-critical.** The dominant cost is not development, it is
**certification** (DO-178C, ISO 26262: $100+/line of evidence). Witnesses,
certified bounds, `ward@allocation_free`-class structural laws and deterministic
builds are *certification artifacts generated as a side effect of compiling*.
*Objection:* certification bodies move glacially and demand qualified
toolchains. *Answer:* correct — which is why the verified checker and the
witness-format freeze are day-0 commitments (§3), and the entry is *evidence
assist* (cutting the manual-evidence bill) before toolchain qualification.
*Fixture:* one LEB128-class module with machine-checked WCET + allocation proof
formatted as a DO-178C evidence packet.

**Security & critical infrastructure.** Rust took the memory-safety wedge; the
2030s wedge is **information safety** — IFC labels as refinements, capability
worlds with zero ambient authority, provenance. "This service *provably cannot*
log the token / reach the internet / read that table" as one anchored expression
in CI. *Objection:* IFC has failed commercially for thirty years. *Answer:* it
failed as a second type system with an annotation tax; here it is three labels
riding fact machinery that exists anyway — and the buyer is the **auditor**, not
the developer. *Fixture:* the token-cannot-leak proof, three lines, red-teamed.

**The Lua succession — WEDGE 1b (promoted by Pass 106).** Tiny embeddable
`libduo` for game engines, nginx/redis-class hosts, plugins. It is Duo's most
NATURAL first ecosystem: the shape is already Lua's, hosts adopt embedded
languages one engine at a time, and there is no ecosystem cold-start to survive.
It also feeds the wedge — embedded scripting is where agent-generated code meets
sandboxes and metered worlds. Flagged at Pass 72 and underweighted since.

**Wire, data, serialization (Ward's home).** The codec matrix: declare a shape
once with layout facts; encode/decode/validators/generators/printers for
binary + JSON + text *derive*, fused and zero-copy. protobuf / serde /
parser-combinators as one deleted category, faster than hand code — wart is the
referee. *Objection:* schema ecosystems have gravity. *Answer:* ingestion
(proto / JSON-schema → descriptors) makes gravity an on-ramp. *Fixture:*
Ward-vs-wart table + round-trip proto interop.

**Fintech, audit, regulated computation.** Computational provenance: "where did
this number come from" as a world constructor; the audit trail IS the execution,
erased entirely outside regulated worlds. *Objection:* performance-paranoid
buyers. *Answer:* demand-erasure means the unregulated build is byte-identical;
the regulated build's overhead is measured and witnessed. *Fixture:* a pipeline
figure that unfolds to its input rows, with the erased-build binary diff = ∅.

**Enterprise migration (the sleeping giant).** Verified porting — the
multi-billion COBOL/C++/Java modernization market, currently sold on prayer,
delivered with **per-function differential equivalence evidence**. Agents do the
porting; the harness does the proving. *Objection:* ingesting messy legacy
semantics is the hard 90%. *Answer:* true, which is why S0's own Zig deletion is
the first customer and the honesty gate. *Fixture:* the bootstrap ledger
shrinking with evidence attached.

**Second wave, funded by the wedge.** Databases and proxies buy the performance
doctrine when the oracle-parity tables exist (G-D6) and not before; gamedev buys
deterministic simulation worlds + virtual time (replay and netcode as
constructors); science buys provenance + content-addressed reproducibility. Each
is real; none is the wedge.

## 3. The unretrofittable list

Chosen by one test: *has any language ever successfully added this after
release?* The answer below each is no.

```
U1  CAPABILITY-CLEAN CORE. Zero ambient authority in std from the first
    release (fs/net/clock/rand reach programs only through worlds). Java and
    Node both tried to retrofit; both failed. Duo has the mechanism; the
    commitment is that NOTHING ships with ambient reach — ever.
U2  DETERMINISM BY DEFAULT. Bit-reproducible builds AND defined execution
    (no UB category at all; iteration orders defined or unordered-by-fact).
    C/C++'s UB debt is permanent; reproducibility retrofits (a decade of
    Debian work) prove the point.
U3  THE WITNESS & DNIR FORMATS AS PUBLIC CONTRACTS. Content addressing,
    certification evidence, semantic linking and the content store are only
    worth billions if the formats are stable — so they version through
    migrate edges from 0.1, and schema changes pay the same toll as
    semantics changes.
U4  EFFECTS AND FAILURES IN SIGNATURES FROM DAY 0 (via facts — no colored
    functions, no async fork later). Rust's async scar is the exhibit.
U5  THE COHERENCE LAW BEFORE THE ECOSYSTEM. The orphan bridge CLOSES before
    the package registry OPENS — ecosystem splits (Haskell, Scala) are
    forever. This sequences the roadmap, not just the spec.
U6  EPOCHS AS THE COMPATIBILITY MECHANISM + THE STD FREEZE DISCIPLINE: the
    pinned surface changes only through deprecation edges with auto-repairs.
    There is no Python-3 event in Duo's future because there is no mechanism
    by which one could occur.
U7  TELEMETRY FROM THE FIRST RELEASE: fire counts, collapse rates, velocity
    metrics public from 0.1 — the empirical loop cannot be bolted onto an
    ecosystem that grew up unmeasured.
U8  NO FOREIGN WAIST (Pass 103 — already law; listed because it is the one
    most tempting to "temporarily" violate under schedule pressure, and
    temporary waists are permanent).
```

## 4. Conformance from the start: the strategy IS the enforcement

Strategic invariants become **anchored protocols on the toolchain itself** — red
in CI until true, published always:

```
std@{ ambient = false }                    U1: the capability audit, one anchor,
                                           run on every std module, forever
build@deterministic                        U2: double-build fingerprint identity
dnir@migratable(v_prev)                    U3: every schema change ships its
                                           migrate edge or does not merge
graph@{ colored = false }                  U4: no callable's effect placement
                                           leaks into its call syntax
registry.open = gate(coherence.closed)     U5: sequencing as a build fact
std@deprecation_only                       U6: surface diffs must be
                                           deprecation edges
release@published(metrics)                 U7: a release without its numbers
                                           is unshipped
toolchain@{ foreign = ledger | oracle }    U8: the census, gated
```

Plus the market-facing instrument: the **public claims dashboard** —
blocks-passing/blocks-total, oracle-parity tables, admission velocity, collapse
rate, ledger size. In a category where every language over-promises,
**auditable claims are the moat's second layer**: the pitch deck and the CI
dashboard are the same artifact, which is a sentence no incumbent can say.

## 5. The investable thesis

Rust proved a language property can capture a decade of infrastructure spend.
The next property is not about memory — it is about **trust in machine-produced
software**: verification, evidence, provenance and admission at agent speed. Duo
is that property implemented as a language rather than bolted on as tooling,
with its distribution surface (agent context + MCP) native to how languages are
now adopted, its claims auditable by construction, and its unretrofittable
commitments locked where C++ and Rust teach us fortunes are made and lost: in
the first release. The ledger stays honest (§22: nothing runs yet), and that
honesty is itself the strategy — **every competitor's pitch is adjectives; this
one is gates.**

## 6. Updates

- Pass 100 **§24** gains the strategic invariants as release gates.
- Pass 100 **§22** gains the public claims dashboard as an owed artifact.
- **U5's sequencing** into the toolchain plan: registry after coherence.
- `CLAUDE.md` untouched **except one row, effective immediately**:
  `std@{ ambient = false }` joins AUDIT v3 as the capability scan.

## 7. The capability scan, measured on the day it became law

U1 says zero ambient authority in std *from the first release*. The honest
starting number, measured rather than assumed, is recorded in
`gaps/GAP-061.md`. It is not zero. Recording it here so the charter cannot be
read as describing a property this repository already has: U1 is a COMMITMENT
with a measured distance to it, and the scan is the instrument that keeps the
distance visible.
