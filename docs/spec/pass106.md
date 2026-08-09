# Pass 106 — The Blind-Spot Audit: What You Didn't Ask For

**Epoch 2 · Amends Pass 100 §22 · Amends Pass 105 wedge list · Sequences the
toolchain plan · Higher pass number wins.**

The most valuable audit is the one against the questions never posed. Each item
lands with its artifact — the thing to *make*, not the thing to feel bad about.

## 1. The five-minute attacks, in the order they will arrive

**"Where's the grammar?"** The first question from anyone trained, and the
answer today is a hundred prose passes. Offside + binding conditions + guard
chains + inferred case + parenless inventory *reads* unambiguous, but that is a
claim requiring an artifact: **a published formal grammar with an ambiguity
argument**, and the parser generated from it — the grammar is data, so this is
dogfood, not chore. **First credibility artifact.**

**"What are the cost semantics?"** Fifty years of "sufficiently smart compiler"
burns — Haskell's space leaks specifically — mean *demand* triggers a trained
allergy. The answer cannot be "trust the witnesses". Needed: a **cost model
document** — strict evaluation order as small-step semantics; demand governs
*materialization, never evaluation order*; the guaranteed-erasure list (what is
*always* free) separated from best-effort optimization; worst-case behaviour of
every construct on one page. This converts the doctrine's biggest liability into
its most distinctive artifact.

**"Is the fact system decidable? What happens when the checker can't prove?"**
One honest page: flow-sensitive refinement checking with an explicit three-state
outcome — proven / runtime-checked / diagnostic — **no silent fourth state**,
SMT optional and not load-bearing. Say where the line is before someone finds it
for you.

**"Show me quicksort. Show me a JSON parser. Show me fizzbuzz."** The corpus is
lexers and LEB128 — expert-flavoured. People calibrate on *mundane* programs.
Ship a **boring corpus**: twenty everyday programs beside the golden one.

**"What does the first error message look like?"** Languages are judged in five
minutes by one diagnostic. Elm and Rust set the bar; Duo has the machinery to
clear it (facts, repairs, counterexamples) and no **diagnostics specification**:
format, tone, repair-first layout, the counterexample block. Design it like the
language — to a newcomer, it *is* the language.

**"You wrote 105 passes and haven't decided on garbage collection?"** The
bridged-decision honesty that works inside the project reads as damning outside
it. Invert the external framing: publish the memory decision **record** — the
bridge contract, the candidates, the criteria, the date. Undecided-with-a-process
reads as rigour; undecided-in-a-footnote reads as hand-waving.

**"Can I call libcurl on day one?"** No-foreign-waist governs the *pipeline*;
readers will hear "no C interop". The FFI answer needs its own crisp page:
ingestion makes C libraries **callable** (rung-6, provenance, zero-adapter on
layout proof). The waist rule bans C as *our* intermediary, not C as *your*
library.

**"It's called Duo? Like Duolingo? Like the MFA company? Like the Google app?"**
An unsearchable, triple-collided name is a permanent marketing tax and a
trademark letter waiting to happen. Decide **now**: rename, or commit to a
searchable compound (`duolang`) everywhere public and register it before the
first post.

## 2. The missing formal core

1. Formal grammar + generated parser + ambiguity argument.
2. Operational semantics + cost model (the erasure guarantees table).
3. Soundness statement for facts / refinements / CDR / routing — three-state,
   explicit.
4. **The numerics page** (i64/u64 mixing, float semantics, NaN ordering,
   division/modulo signs, literal typing) and **the text page** (grapheme edge
   cases, normalization stance, invalid-UTF8 at boundaries). The boring tables
   experts check *first*, because they reveal whether the designer has met the
   edge cases.
5. The diagnostics spec.
6. The boring corpus.

## 3. Toolchain pieces not yet considered

- **REPL** — the graph makes it exceptional (definitions are graph ops, `why`
  inline, world snapshots as undo) and it is the adoption front door.
- **Debugger** — the oblivious gap. With fusion and erasure, what does
  *stepping* mean? Needs **debug realization** as a first-class mode: a world
  fact pinning observability (deopt-to-observable per scope), giving time-travel
  over journaled places rather than gdb cosplay.
- **Documentation generator** — falls out free (docs are graph queries) and
  should be claimed loudly: always-accurate docs as a *property*.
- **The playground** — browser Duo. The wasm target's real deadline is
  marketing, not embedded.
- **`duo upgrade`** — the deprecation-edge runner that makes U6's "no Python-3
  event" a command.
- **Semantic review surface** — post-canonical diffs + witness deltas as a
  review UI: the "I didn't write that" mitigation, and a genuinely novel PR
  experience.
- **Supply chain** — lockfiles, vendoring, sigstore-class signing: mostly
  *derived* here (see §4).
- **Linguist / highlighting / CI actions / editor plugin distribution** — the
  mundane presence work that signals aliveness.

## 4. Business surfaces that fall out of the design

**Supply-chain security as a product.** Content-addressed artifacts carrying
witnesses and provenance ARE the SBOM/SLSA/provenance market's asks, generated
by compiling, while the industry bolts them on. Possibly the most immediately
monetizable derivation in the whole design, and it was never named.

**The Lua succession — re-ranked to wedge 1b.** Tiny embeddable `libduo` for
game engines, nginx/redis-class hosts, plugins. Flagged at Pass 72 and
underweighted since. Skeptically: it is Duo's *most natural* first ecosystem —
the shape is already Lua's, hosts adopt embedded languages one engine at a time,
and there is no ecosystem cold-start. It also feeds the wedge: embedded
scripting is where agent-generated code meets sandboxes and metered worlds.

**Compliance-as-code** (anchored protocols as a policy engine — the OPA-shaped
market), **living documentation as a service**, **education** (the
ceremony-free first language).

## 5. The related-work document

Nothing separates outsider-with-a-vision from crank faster than demonstrating
you know your neighbours. One page, one line each — what they proved, what Duo
does differently:

- **Unison** — content-addressed code works; Duo addresses *semantics*,
  post-face.
- **Koka / Effekt / Flix** — effect types work; Duo carries effects as facts,
  uncoloured.
- **Zig** — comptime + no-hidden-control-flow audience IS Duo's audience.
  *"Zig shows you everything; Duo can tell you anything."*
- **Jai / Odin** — the anti-ceremony systems crowd exists.
- **Hylo / Val** — mutable value semantics ≈ ownership-driven mutation,
  discovered independently. **Say so.**
- **Mojo** — proves the market believes a new systems language can win; also
  proves claims-before-benchmarks gets punished.
- **Lean / Dafny** — verification UX lessons.
- **Erlang / Elixir** — worlds / living-systems ancestry.
- **Lua** — the body plan.

Publishing this *before* launch converts every "have you heard of X?" gotcha
into "yes — section 5."

## 6. The social layer

**Governance and bus factor.** One designer, no code, no succession is an
adoption blocker for anyone serious. Artifact: a governance page — the decision
process is the pass/epoch system *formalized*, which is genuinely novel
governance (evidence-based rule changes with fire-count telemetry); a license
picked early (Apache-2 or MIT+patent grant; the graph service's server side
needs a deliberate choice); a trademark/name resolution; a stated path from BDFL
to structure.

**Release strategy against the vaporware pattern-match.** A hundred specs lose
to two hundred running lines. **Ship the evaluator first** — G-D1 is days-class
by our own claim — with the REPL as its face, and sequence the public story as
running-thing → spec → thesis, inverting how it was built.

**The feedback asymmetry.** 105 passes of one dialogue is a monoculture. The
epoch system's telemetry needs *other people's* fire counts: a private alpha of
five sharp critics before any public claim, their objections filed as passes.

## 7. The marketing map

```
PL/HN skeptics      "here's the grammar, the cost model, and 200 running
                    lines" — the formal core + evaluator REPL · HN/lobste.rs
Lua users           "the heir: your shape, with proofs" — libduo demo in a
                    game engine · Lua workshop / gamedev discords
Rust users          "after the borrow checker: facts, not lifetimes;
                    uncolored effects" — the ownership-mutation page · r/rust
                    (bring humility and benchmarks or don't go)
Agent/AI tooling    "the language whose compiler is the reviewer" — the
                    synthesis-harness demo + MCP server · AI-eng twitter/X
Embedded/safety     "certification evidence as a compiler side effect" —
                    the DO-178C packet fixture · trade conferences
Enterprise          "migration with per-function proof" — the S0 ledger
                    shrinking publicly · direct sales, later
Academia            "witness economy, demand-routing, semantic addressing —
                    three papers" — PLDI/OOPSLA (peer review is marketing
                    here, and the crank-filter)
Educators/curious   the philosopher spec, verbatim · blog/newsletter
Everyone            the claims dashboard link under every single claim
```

## 8. Updates

- Pass 100 **§22** gains the owed artifacts by name, with the release-sequencing
  note (evaluator first).
- The **toolchain plan** gains REPL, debug realization, doc generator,
  playground, `duo upgrade`, review surface, supply-chain derivation.
- The **Leverage Charter's wedge list** is amended: embedding promoted to
  **wedge 1b**.

> **The residue line:** the language was designed by asking *"what is true"*;
> the launch must be designed by asking *"what will they check first"* — and now
> both lists exist.

## 9. What this repository can already answer, and what it cannot

Recorded so the audit is operative rather than a mood:

**Partly answerable today.** The boring-corpus gap is smaller than it looks —
`examples/` holds ~135 reachable programs, and `zig build capability-rows`
already reports per-capability rungs from fixtures. What is missing is not
programs but the *mundane* ones and the framing. The claims dashboard has real
inputs already: native census, differential agree/differ, `abi-matrix`
miscompile count, capability rungs, `audit100` rows.

**Not answerable today, and the honest list.** There is no formal grammar, no
cost model, no soundness page, no numerics or text page, no diagnostics spec, no
related-work page, no governance page, and no name resolution. None of these are
blocked on implementation; all are blocked on being written. They are now named
in §22 rather than living only here.

**The one with a deadline attached.** The name. `duo` collides with Duolingo, a
well-known MFA vendor, and a Google product — it is unsearchable today, not at
launch, and every artifact published under it accrues the tax. This is the
cheapest item on the list and the only one that gets *more* expensive with every
commit.
