# Pass 120 — the adjudication record (EXPLANATORY, NOT LAW)

> **THIS FILE DOES NOT BIND.** `docs/spec/constitution.md` is C0 and is the only
> law. This is the reasoning behind a subset of its facts, kept because a fact
> records *what* was decided and a reader sometimes needs *why*. Where this file
> and the constitution differ, **the constitution wins and this file is the
> defect** (`law.representation`: prose explains, prose does not bind).
>
> **Two of this document's own rulings are already superseded** by the
> constitution, and are left in place as provenance rather than edited out:
>
> - **§3 RULE-CARRIER** — "a pass is law only while a tracked document carries
>   it" — is VOID. It treated the missing pass 109–119 documents as the bug.
>   `law.passes` rules that the pass LAYERING is the bug: rulings flatten into
>   current facts and pass numbers become provenance, which removes the temporal
>   legal research instead of making it citable. The stronger rule wins.
> - **§21 RULE-OWNER** is absorbed into `law.owner` and needs no separate home.

**Filed 2026-08-08.** Adjudicates a twenty-point owner review of branch
`canonical-to-relation` at `c62ad0c`. Its surviving contribution is the
*measurement* in §0 and the five rulings the constitution did not already carry:
`law.escape`, `law.cycle`, `law.wasm.workaround`, `law.wasm.release`,
`law.package`.

The review's thesis is accepted: **the failure mode has moved.** It is no longer
too many surviving mechanisms; it is elegant laws extended into places where the
counterexamples have not been beaten. Every ruling below narrows a law that was
stated too generally. None of them adds surface (A2/NNS holds).

---

## §0 What was checked before ruling, and what the check changed

Three of the review's claims were measured against the tree rather than adopted.
Two survived, one inverted, and the inversion changes the top-priority repair.

| claim | measured | verdict |
|---|---|---|
| grammar.md still admits `;` for inline `while` | line 61, verbatim | **CONFIRMED** — fixed in this commit |
| grammar.md still admits `end` | line 24: `END → "end" (accepted, DELETED by the reader — resync only)` | **NOT A CONFLICT** — that line already *is* the staged reading the review proposes |
| the branch tip flags `ward@dominates(wart)` as retired | `roles.md:413` flags it; **`CLAUDE.md:413` restores it as law** | **INVERTED** — see §21 |

The `end` row matters because it shows the reconciliation is narrower than it
looked. Of the eight forms the review lists as "the normative grammar still
says", **seven are not contradictions** — prefix `~` and `#`, the shift/xor/bor/
concat/exponent rungs, byte and raw strings, parameter descriptors, defaults and
packs, and postfix indexing are all present in `grammar.md` and denied nowhere.
They are absent from the rendered spec's EBNF, which is a different defect: that
EBNF is a SUBSET advertised as "the full surface". **One real conflict, seven
labelling errors, and they need opposite repairs** — the first amends the
grammar, the other seven amend the rendering.

---

## §1 RULING JURISDICTION — shared graph, separate law (amends RFC axiom 1)

The RFC states *"language origin is metadata, not type."* Accepted in direction,
**rejected as stated**, because it lets an optimizer prove a fact with duon's
laws over a node whose behaviour is governed by Lua's.

The counterexamples are not exotic. Table lookup versus sealed-shape field walk;
Lua equality versus a descriptor-defined `eq` relation; metamethod dispatch
versus relation resolution; `nil`-removes-the-key versus structural place
semantics; Lua's numeric coercion versus descriptor numerics; iteration-order
constraints versus realization facts. Each pair can present an **identical graph
shape under a different law**.

**THE AMENDED AXIOM:**

> Language origin does not determine representation. **Semantic-law membership
> is an ordinary graph fact and participates in proof.**

Provenance and jurisdiction are split, and only one of them is inert:

```
origin       = duo | lua | c | wasm      provenance. Inert. Never consulted by a proof.
law          = the semantic law set      a FACT. Consulted by every proof.
```

The consequence is a hard obligation on every rewrite: **a rewrite must name the
law set it is legal under, and a node may only be rewritten under its own.** A
rewrite legal in `law.duo` applied to a `law.lua` node is a soundness bug even
when the shapes match exactly, and it is now a statable one rather than an
invisible one. Sharing is preserved everywhere it was real — representation
selection, specialization, register allocation, the JIT, effect modelling,
witnesses — because none of those are law membership.

---

## §2 RULING LUA — Lua gets a constitution, not a fallback

The review is right that Lua is underrepresented against Rust/Python/JVM
ingestion, and right about why it matters: the headline is *drop a `.lua` file
into the same compiler and get an aggressive VM/JIT/AOT with no language
change*. That is not a foreign-ingestion story, and `lua_Value` demoted to a
dynamic leaf is necessary but nowhere near sufficient.

Nine invariants, normative:

```
LUA-SEMANTICS   exact source behaviour is non-negotiable
LUA-ADAPT       representation may specialize arbitrarily if behaviour is preserved
LUA-DESCENT     every speculative optimization carries deopt / invalidation
LUA-META        metatable identity AND mutation participate in guards
LUA-SHAPE       tables specialize through observed shape facts
LUA-CLOSURE     environments specialize but remain observationally Lua
LUA-PACK        multiple returns preserve Lua adjustment rules exactly
LUA-COROUTINE   coroutine semantics stay Lua even when implemented by native tasks
LUA-PROOF       every specialization carries behavioural differential evidence
```

`LUA-SEMANTICS` + `LUA-ADAPT` are the pair that make this a supremacy claim
rather than a compatibility claim: behaviour is frozen, representation is
unbounded. `LUA-PROOF` is what keeps it honest, and it inherits §3 MEASUREMENT
HONESTY without amendment — this repository has already shipped a benchmark
suite that answered from frozen literals, so a Lua speed claim without a
differential is presumed fabricated.

Owed: `docs/spec/lua.md` carrying the invariants, the deopt model, and the
differential corpus.

---

## §3 RULING AUTHORITY — three layers, and the carrier bug underneath them

The proposed layering is adopted:

```
semantic law        pass documents
grammar law         generated grammar data
rendered document   a generated projection of both
```

But it **cannot be implemented as stated today**, and the reason is the finding:

> `docs/spec/README.md`'s precedence list ends at **Pass 108**. Passes 109–119
> have no tracked document. Their sole carrier is `CLAUDE.md`, which that same
> list ranks at **2 — "its operative summary"**. The rendered HTML spec is not
> in the repository at all (`find . -name '*.html'` = 0).

So "no two Epoch-2 truths" understates it: the newest law is carried by a file
that outranks nothing, and compared against a document that is not under version
control. Drift between them is undiffable by construction. `GAP-073` reached the
same conclusion from the role taxonomy — *"Passes 113-119 have no document in
`docs/spec/` — `CLAUDE.md` §0d and §0g are the entire surviving text"* — and
that was read as a documentation gap when it is an authority gap.

**RULE-CARRIER:** a pass is law only while a tracked document in `docs/spec/`
carries it. A ruling surviving only as `CLAUDE.md` prose is an UNSHIPPED ruling
and may be cited only as intent. This is the existing "a ruling without
regeneration is unshipped" rule applied in the direction nobody applied it: not
just *regenerate the summary from the pass*, but **the pass must exist to be
summarized from.**

Consequence, and it is deliberately uncomfortable: passes 109–119 are **intent,
not law**, until landed. This document is one of them and lands itself.

---

## §4 RULING NNS-TEST — the closed grammar is a veto, not a theology

A2/NNS is retained as the default veto and given a stated defeat condition,
because the review correctly identifies a live reasoning error:

> *we can express X somehow with existing syntax → therefore adding syntax for X
> would violate NNS*

Those are not the same claim. NNS reads:

> **No new surface unless it carries a semantic distinction that existing
> surface cannot communicate cleanly.**

Not *"surface can never change."* The repository's own CHAIN-CMP ruling is the
counterexample that proves it: `a < b < c` added semantic interpretation to an
existing sequence because correctness and density improved, and it was ruled
without pretending nothing changed.

**THE TEST.** A proposal defeats the veto only by carrying all four, each
independently evidenced: (a) an irreducible semantic distinction, stated as the
pair of programs the existing surface cannot separate; (b) frequency, measured
on the corpus and not asserted; (c) an error class it removes, with a fixture;
(d) compaction, measured. Against the costs: grammar ambiguity, tooling cost
across every enumerated front-end, and conceptual duplication. **No ratio is
computed** — a formula here would invite tuning the number, the exact failure
`GAP-073` refused a ratchet over. The four are shown or the veto stands.

---

## §5 RULING SELF-ESCAPE — the ambient subject is an ordinary value

SELF-ZERO is retained. Its escape hatch is specified, because unspecified it
creates a second borrowing mechanism by accident.

```
capture = () .          -- what does this produce?
f = () () .             -- what does a nested closure capture?
```

**RULE:** the ambient subject is an ORDINARY SEMANTIC VALUE. Capture, escape,
aliasing, mutation and lifetime are governed by exactly the same representation
and lifetime proofs as any other place. **There is no implicit borrow, no
implicit copy, and no lifetime extension.** `.` is the zero-length walk, and a
walk of length zero is not a special form — it names the subject place, and
naming a place is already fully ruled.

The corollary is the point: **SELF-ZERO deletes a parameter, not a proof.** If
the subject escapes a closure, the closure's world fragment records the capture
like any other, and region inference sees it. Anything else would make `.`
cheaper than a named binding, and a surface that is cheaper than the thing it
abbreviates is how implicit borrowing gets in.

---

## §6 RULING ANCHOR-LATTICE — context-sensitivity with no circular resolution

`.` now carries field walk, inferred case, subject, spread, and lens
(`map(.name)`). Pass 108 R2 is right that the parser emits one `anchorref` node
and semantics decides. The missing rule is the one that keeps deciding from
becoming guessing:

> **Context-sensitive meaning is legal only where the context is proven
> independently of the token being interpreted.**

Circular resolution is FORBIDDEN by name:

```
we need .foo's meaning to infer the expected descriptor
but the expected descriptor is what decides .foo's meaning
```

The lattice, resolved in strict order, first match winning:

```
1  subject-place      the empty walk
2  lens               argument position (P98: always)
3  case               descriptor-expected position, case-set known
4  descriptor-walk    the anchor names a descriptor home
5  ordinary-field     a subject is in scope with the field
--  otherwise         DIAGNOSTIC. Never speculative backtracking.
```

Unknown resolves to a diagnostic, never a guess — which is G-TOTAL's
"two candidates is a mixed-space DIAGNOSTIC" applied one level down. This is
load-bearing for incremental LSP parsing, where backtracking over a半-typed
buffer produces exactly the flickering meaning the role stream must not have.
It also closes the hole `CLAUDE.md` §0d admits: a leading `.` at a clause head
was *"a genuine hole in the law"*; rows 1–5 close it by order.

---

## §7 RULING CHAIN-CARRIER — what `:` threads, for every realization

`x:a():b():c()` is specified only for the void case (*"a void realization yields
its RECEIVER"*). Generalized, so no backend invents the rest:

| realization | chain subject | note |
|---|---|---|
| value | the value | ordinary |
| void | the PRIOR subject | chain threading, already law |
| pack | the demanded primary position | B-9; the rest stay bound to their positions |
| failure | **routes before continuation** | B-14/B-15; the chain does not continue |
| place | the place | preserved, not decayed — a chain must not silently copy |
| view / transient | the view, with its validity fact | the fact rides the chain |
| suspend | the continuation subject | resumption is a chain step, not a new chain |
| world action | the world's result, action italic | capability unchanged by chaining |

The failure row is the one with teeth: a failure in chain position does **not**
produce a subject at all. It routes. Which is §8.

---

## §8 RULING ROUTE-EDGE — B-15 is surface elision, never a lowering

B-15 lets `tok = lx:token()` route its failure invisibly inside a declared
failure contract. Invisible control flow is the correct SURFACE and a hazard
everywhere below it: destructor placement, release, rollback, instrumentation,
lock scopes, region exits, tracing, and vector-region legality all depend on
seeing the edge.

**RULE:** B-15 is **surface elision only.** The semantic graph and DNIR ALWAYS
carry an explicit failure-route edge, materialized before lifetime, region and
effect analysis run. **No front-end may lower a routed failure directly into CFG
jumps from parser or sema.** An optimization that cannot see the route is
unsound and will be wrong about drops first — which, under a drop ladder with
deterministic finalization, means a resource leak or a double release rather
than a wrong number.

The diagnostics work already hints at this with a `routed` token modifier; that
modifier is now the *rendering of a real edge*, not an annotation.

---

## §9 RULING CYCLE-ENVELOPE — the memory doctrine's load-bearing undefined term

Pass 107's ladder (proven drops → regions → managed RC → deferred trial deletion
confined to cycle-POSSIBLE shapes) stands. **"Cycle-possible" is doing enormous
work and is undefined**, and the open questions are the ones that decide whether
the doctrine survives contact: dynamic tables, closures capturing tables
capturing closures, foreign Python/JVM objects, weak references, finalizers,
resurrection, cross-thread shared graphs, detection latency, behaviour under
memory pressure, and per-object metadata cost.

**RULE:** *"never a tracing stop-the-world collector"* is retained as a LATENCY
PROMISE and is therefore a **measured claim, not a mechanism list**. It ships
with benchmarked latency and throughput envelopes or it is not a property.

**The Lua corpus is the designated pressure test** (§2), because Lua hosting
generates pathological cyclic graphs as a matter of routine — which makes the
supremacy story and the memory doctrine the same experiment. That is a
convenience worth naming: the hardest available adversary is already a goal.

---

## §10 RULING IDENTITY-THREE — one identity is not enough for what is built on it

The RFC notes a session arena plus a Wyhash-derived stable identity and lists
persistent identity as unresolved. This is more fundamental than an open item.
**Three identities, never collapsed:**

```
semantic identity     "this declaration / value / relation is logically the same thing"
content identity      "this normalized subgraph has the same contents"
incarnation identity  "this particular occurrence / build / version"
```

Two structurally identical pure functions share CONTENT and must not thereby
share provenance, breakpoint identity, capability ownership, exported symbol
identity, or mutation history.

**RULE:** dedup shares **content/realization** nodes. It may **never** collapse
semantic-identity nodes. The RFC's proposed content dedup in `addNode` is
unsound as written for exactly this reason.

This also re-reads an item `AUTHORITY.md` has carried as owed all along —
*"stable semantic identity across scope/module/codegen — textual names are still
doing semantic-identity work, which is the root of a whole family of current
bugs."* Textual names are serving as all three identities at once. Splitting the
concept is the prerequisite for that repair, not a parallel task.

---

## §11 RULING DEDUP-CLASS — normalization needs node classes

DAG dedup is what keeps exponential metaprogramming tractable, and it is safe
only over structurally transparent nodes. Four classes, and only the first
deduplicates:

```
structural       transparent, pure, contents ARE the identity     dedup: YES
identity-bearing carries semantic identity                        dedup: NO
effect-bearing   carries an effect fact                           dedup: NO
place            denotes storage                                  dedup: NO
```

Without this, `counter{0}` and `counter{0}` become one object under an
aggressively normalized graph. This belongs in the spec even where it is obvious
to an implementer, because A3 ONE EDGE plus a persistent graph plus dedup makes
it an **architectural invariant** — and an invariant that lives only in an
implementer's head is the thing this repository keeps paying for.

---

## §12 RULING EFFECT-RESOURCE — order is derived, never primitive

Promoting `orders.before` into durable cross-language effect edges is the right
seed and the wrong primitive. A total effect order **over-constrains**: it
forfeits load/store reordering, parallelism, vectorization, effect commuting,
task scheduling, and cross-function purity proofs — the entire optimization
surface Pass 104 says is supposed to be READ rather than inferred.

```
effect      touches(resource, mode)      the primitive fact
ordering    derived where dependence requires it
```

Modes: `read` · `write` · `alloc(region)` · `atomic(order)` · `io(world)` ·
`foreign(unknown)`. `foreign(unknown)` is the correct pessimism and the only one
that orders against everything.

**RULE:** the semantic graph does NOT commit to *effect = ordering*. It records
what an operation touches and in which mode; happens-before is **computed**.
This also fits A3 ONE EDGE better than the ordering formulation did — an
ordering edge between two operations is a derived fact wearing an edge's
clothing, while `touches` is a genuine one.

---

## §13 RULING WORLD-BOUNDARY — worlds are not the new junk drawer

Worlds correctly absorbed fs, net, clock, rand, shell, python and jvm. The risk
named is real: having deleted arbitrary activity modules, the pressure is to
make `world` mean "namespace for anything awkward".

**RULE:** a world is an **effect and capability boundary**. Membership requires a
capability or an effect. **A pure foreign function does not need a world merely
because it is foreign** — a pure C function is `abi-native`, capability-free,
and reaches the graph as a VALUE EDGE like any other pure operation. Python is a
world because *running* Python has interpreter state and effects, not because it
is foreign.

The §17 trust regimes are hereby **normative**, and they are the defense that
keeps this line drawable: trust and capability are different axes, and only the
second creates a world.

---

## §14 RULING STD-NAV — navigation ships before namespaces are deleted

`x:abs()` over `std.math.abs` is right, and it deletes something real: a module
tree is also a NAVIGATION structure, and the questions it answered do not go
away. What operations exist on `f64`? Where did this edge come from? Standard or
package? Which package added this relation? Why did coherence pick this
implementation? What is stable across epochs?

**RULE:** the semantic browser is **not optional tooling** — it is the
replacement for a deleted feature, and it ships first. Ordinary queries, not a
special surface:

```
f64@edges          x@why(abs)          graph.home(abs)
graph.origin(abs)  graph.version(abs)
```

`GAP-071` already proves the dependency from the implementation side and its
sequencing is ratified without change: the `pure` row (512 sites, 73 files)
cannot move while BLOCKER 1 probes ABSENT, because `x:abs()` does not build —
the compiler lowers the receiver away and emits a zero-argument call to an
undeclared name that would bind to any same-named free function. **`duo check`
exits 0 on it.** Deleting the namespaces before the edges exist would convert a
working call into a silent subject drop at 512 sites.

Also ratified: the foreclosed shortcut. Moving pure ops to `std.numeric` or a
renamed `math` drives the row to zero and repairs nothing. The only legal
destination is the descriptor.

---

## §15 RULING COHERENCE-P0 — package composition is a semantic exercise

`registry.open = gate(coherence.closed)` is already an anchored protocol; this
ruling says what must be closed, and that it is **semantics owed now**, not
package-system implementation detail owed later.

```
package a introduces  to(json)(foo)
package b introduces  to(json)(foo)
```

The law must state, exactly: relation ownership · descriptor ownership ·
extension authority · version coexistence · dependency-private extensions ·
local overrides · conflicting implication chains.

This is the orphan/coherence problem plus package-resolution scope, and both
halves have known-hard failure modes in the languages that shipped them without
a law. Solve it before registry scale, as the repository's own gate already
says — the gate is currently a promise with no referent.

---

## §16 RULING COMPAT-CONTRACT — semver is computed from contracts, not edges

"Added edges = minor, changed contracts = major" is the right ambition with the
wrong input. Behavioural compatibility does not reduce to graph shape.
Counterexamples that leave the edge set untouched: complexity class changes ·
the effect set grows · allocation appears · determinism changes · the error set
expands · numeric precision changes · ordering becomes unstable · a sealed
descriptor becomes open · timing shifts observably through a foreign interface.

**RULE:** computed compatibility compares SEMANTIC CONTRACTS AND WITNESSES:

```
surface · effects · failure set · complexity class
representation promises where public · determinism · capability requirements
```

Kept as a headline feature rather than trimmed, because the graph genuinely can
compute this and no incumbent does — but a computed number that misses an effect
growth is worse than a declared one, since it is trusted.

---

## §17 RULING TOTAL-THREE — coverage is not comprehension

G-TOTAL is valuable and is currently one gate carrying three different claims.
**100% role coverage ≠ 100% semantic understanding**: a token can be
beautifully hued `t-v` while its binding resolution is wrong.

```
ROLE-TOTAL         every source byte has an unambiguous role
SEMANTIC-TOTAL     every reference/edge has resolved identity, or an EXPLICIT unresolved node
PROVENANCE-TOTAL   every generated/optimized fact carries a source/witness chain
```

Three gates, three numbers, no averaging. `roles.md` currently reports coverage
"should rise from 20% once `t-v` and the punctuation roles are admitted" and
flags it **not yet re-measured** — correct discipline, and the split is what
stops a rising ROLE-TOTAL from reading as semantic progress it does not contain.

---

## §18 RULING PROJECTION-DIRECTION — highlighting is never a source of truth

```
graph truth  →  role stream  →  LSP / HTML / tree-sitter / TTY
```

**Never the reverse.** Tree-sitter in particular remains an APPROXIMATION and a
projection; it must not acquire semantic authority by successfully reproducing
colours. This matters now because substantial tree-sitter and highlight
generation is landing on this branch, and a generated grammar that reproduces
the right hues is precisely the artifact most likely to be mistaken for a parser
that understands the language.

H-7's *"provenance maps are bidirectional DATA"* is not a counterexample:
bidirectional lookup is not bidirectional authority.

---

## §19 RULING RENDER-FIX — the rendered spec's concrete defects

Each is a defect in the RENDERED document, which per §3 is not yet a tracked
artifact — so these are the acceptance criteria for landing it, not edits to an
existing file.

1. **`end`** — "There is no end" and "accepted-and-removed" are different
   stages, not a contradiction. Canonical wording: *canonical grammar emits no
   `end`; the transition reader consumes it as compatibility syntax until the
   retirement gate reaches zero.* `grammar.md:24` already says this and is the
   model. The gate must exist and report.
2. **"The full surface"** — the displayed EBNF omits forms the document itself
   uses and `grammar.md` carries. **Label it "core grammar" or complete it.**
   Seven of the review's eight conflicts are this one defect (§0).
3. **Pass numbering** — the mast reads "consolidated through pass 114" over a
   body containing P115–P119 rulings. An authority bug; the mast states the
   highest pass it actually carries.
4. **`ward@dominates(wart)`** — delete. See §21.
5. **duon vs Duo** — already answered by `CLAUDE.md` §-1 and not reopened: the
   language is **duon**, files stay `.duo`, the repository's `duo` spelling is
   MIGRATION DEBT behind a gate. The rendered spec must say this rather than
   leave the reader to infer it, because naming ambiguity leaks into extensions,
   package names, search, CLI, LSP ids and MIME types.
6. **`;`** — `grammar.md:61` carried the inline-`while` tail against Pass 119.
   **Fixed in this commit**, higher pass winning.

---

## §20 RULING KINDS-NOT-KINGDOMS — structural unity, semantic typing

No permanent compiler subsystem may be named `generic system`, `concept system`,
`protocol system`, `failure system`, `module system`, `foreign system`,
`metaprogramming system` or `package system`. That is settled direction and
`canonical-to-relation` is executing it.

The ruling is the guard on the other side, and it is the review's sharpest
point: **the danger of over-convergence is replacing "too many systems" with
"one graph node whose semantics are implicit."** Distinctions do not disappear;
they stop being kingdoms and become facts:

```
one graph, with facts about:
  identity · relation · descriptor · demand · effect · place
  provenance · trust · capability · lifetime · law · realization
```

**Structurally unified, semantically typed by ordinary facts.** Note `law` in
that list — §1's amendment, and the reason this ruling is not merely a
restatement of ONE EDGE.

---

## §21 RULING OWNER — a directive outranks a pass, and G-DOM is why

`ward@dominates(wart)` was retired on owner directive on 2026-08-08
(*"dominates shouldnt be a thing its just an artifact of claude"*) and removed
in `e717f89`. `docs/spec/roles.md:413` still records that retirement. **A later
session restored it to `CLAUDE.md` as law**, citing Pass 116 §2 and the epoch-2
rule "higher pass wins" — and wrote *"the retirement is void."*

The restoration was procedurally correct under the protocol as written, which is
the finding. **The protocol had no rule ranking an owner directive against a
pass document, so "higher pass wins" ranked agent-authored text above the person
the passes are written for.** The review's own belief that the tip flags G-DOM
as retired shows the cost: the owner cannot see that a directive was reversed.

```
PRECEDENCE:  owner directive  >  pass document  >  CLAUDE.md summary  >  code
```

**RULE-OWNER:** a pass text contradicting a recorded directive is VOID on its
face and requires no adjudication. Directives are recorded in
`docs/spec/directives.md` — date, verbatim wording, scope. **A ruling that
cannot cite a directive there may not overturn one.** Without the record the
rule is unenforceable, because the next session will again find only the pass.

G-DOM is retired. The wasm runtime lives in `tools/wasm/` and is measured by
`zig build runtime-bench` against wasmtime, wasmer and wart, publishing its
LOSSES, with every runtime required to produce the SAME ANSWER before any speed
number is compared.

---

## §22 The revised order, ratified

Adopted as given, with §3's carrier repair folded into item 1 because the
reconciliation cannot otherwise hold:

1. Reconcile the rendered spec with the normative grammar — **and land passes
   109–119 as tracked documents**, without which there is no second authority to
   reconcile against, only a summary.
2. Semantic-law worlds for duon / Lua / C / WASM over the shared substrate (§1).
3. Split graph identity three ways before persistent graph and dedup go deeper
   (§10, §11).
4. Effect-resource facts, not effect ordering (§12).
5. B-15 routing as explicit graph control flow, through release and region
   proofs (§8).
6. Value-edge realization + `why(realization)` **before** any std namespace
   deletion (§14; `GAP-071` blockers 1 and 3).
7. SELF-ZERO capture / escape / lifetime (§5).
8. Package coherence before registry work (§15).
9. Lua's constitution and differential (§2).
10. Then self-hosting acceleration and the graph-as-owner transition.

**Surface compaction is explicitly NOT on this list.** The review's closing
judgment is accepted: the surface is already unusually compressed, and the
remaining leverage is underneath it — identity, jurisdiction, effects, and
lifetime under invisible routing. Those are where "one graph" becomes stronger
than AST→IR rather than a more unified vocabulary for it.

---

## §23 Falsifier

If in a month `docs/spec/` still ends its precedence list at Pass 108 while
`CLAUDE.md` carries passes 109–120, then RULE-CARRIER was written and not
enforced, and this document is itself the thing it diagnoses.

If `ward@dominates(wart)` reappears in any tracked file, RULE-OWNER failed and
`docs/spec/directives.md` was not consulted — check whether the file exists
before blaming the session.
