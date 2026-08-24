# ROOT-PROGRAM — the active-P0 surface collapsed onto eight programs

**Status:** OPEN · **Filed:** 2026-08-23
**Kind:** projection · **Normative for:** nothing — this is a projection of `gaps/GAP-*.md`
**Derived, not authored:** the membership below is a reading of the gaps; the
gaps are the authority and this file is stale the moment one of them moves.
**Not the per-gap frontier.** Each gap states its own machine-read frontier in
an `idol.gap.frontier.v1` block that `gate/frontier.sh` validates and fails
closed on. This file is an UNGATED reading ACROSS gaps, which is exactly why it
carries a derivation command instead of a census, and why it must never be
cited where a gap's own frontier block answers the question.

## Why this exists

The open-gap surface was too large to dispatch against. The census selector is

```sh
for gap in gaps/GAP-*.md; do h="$(sed -n '1,8p' "$gap")"
  printf '%s\n' "$h" | grep -Eiq '^\*\*Status:\*\*[[:space:]]*(OPEN|REOPENED)([[:space:]·(:—-]|$)' &&
  printf '%s\n' "$h" | grep -Eiq '^\*\*(Status|Priority):\*\*.*P0' && echo "$gap"
done
```

Run it. Do not read a count out of this file — that is the rule this whole pass
exists to enforce, and the number moved twice while the pass was being written.

## The two chokepoints

The collapse is real but it is not eight-way. Most current blockers funnel into
two gaps, and neither is a member of a program so much as the floor under
several of them.

**`GAP-124` — identity-based canonicality from graph facts.** Its own ledgers
say so out loud: `scripts/ledger/semantic.id` reports `WORLDGATE`, `VOCABGATE`,
`SENTINELGATE` and `CONTROLREDUCE` interned and `SUBJECTGATE waits on
application subject edges`; `scripts/ledger/graph.id` reports the func tag gate
open. `GAP-113`, `GAP-125`, `GAP-132`, `GAP-153`, `GAP-161` and `GAP-165` each
name it as their unblocker.

**`GAP-119` — process/execution world vocabulary.** `docs/spec/world.md` §313
specifies it (`command:run() requires process world`, "Not `io.popen`, not
`process.capture`"). Nothing implements it: no `command` subject in
`src/subject_home.zig`, no process world anywhere in `src/`, `lib/proc.id` still
reaching `io.popen` / `os.execute`, and `docs/spec/law.md` does not mention
process at all. `GAP-127`, `GAP-128`, `GAP-146` and `GAP-147` are all waiting on
it — three of them are "a gate reports success it did not earn", which is the
same missing fact seen from the evidence side.

Close those two and the dispatchable surface shrinks more than any other pair.

## The eight programs

**1 Lexical/Grammar One** — `GAP-134`, `GAP-145`, `GAP-092`, `GAP-163`.
The grammar-fact owner transfer is done (`lib/compiler/token.id`); what remains
is `docs/spec/grammar.md` not generating the parser, Tree-sitter as a second
authored authority whose byte-identity control cannot execute, the host
`TokenKind` enum, and the second keyword producer. `GAP-092`'s surviving half is
the `.call` / `.method_call` split; its identity half is crossed and gated by
`gate/delimiter-projection-law.sh`. `GAP-163` sits here for the `duo`/`DUO_`
name purge only.

**2 Application/Graph Sovereignty** — `GAP-124`, `GAP-137`, `GAP-201`,
`GAP-202`, `GAP-113`, `GAP-125`, `GAP-132`, `GAP-153`, `GAP-161`, `GAP-165`.
`GAP-201` is the umbrella that owns the remaining bridge inventory; `GAP-137`
owns one fact being optional and fail-open and is one row from closed;
`GAP-202` owns making the one application algebra complete enough that scalar
multiplication needs no subsystem of its own. `GAP-132` is the sharpest live
defect in the program and reproduces in one command.

**3 Demand + Laws** — `GAP-187` (root, research), `GAP-149`, `GAP-138`.
`GAP-187` declares `Kind: research_gap` and its own C0 block calls it "the P0
semantic-spine root"; it describes an unbuilt algebra, not a live defect.
`GAP-149`'s doc half is crossed (`docs/spec/numerics.md` is now a primitive-zero
projection) and its code half is not. `GAP-138` is here because a
`present | absent` result is a law question, and its regression is an in-band
`-1` sentinel.

**4 Transformation Algebra** — `GAP-217` (not P0), and the
`src/transform_engine.zig` / `src/explain_pipeline.zig` rows of `GAP-167`.
This is the thinnest program in the active-P0 set. That is itself a finding: the
transformation half of the architecture has almost no live P0 pressure on it.

**5 World/Stage Algebra** — `GAP-119` (chokepoint), `GAP-118`, `GAP-128`,
`GAP-146`, `GAP-147`, `GAP-155`, `GAP-157`, `GAP-203`.
`GAP-118` (absence erased into empty string) and `GAP-203` (the injection half
of the world algebra has no graph fact — `WorldFact` still carries no parent and
no delta range) are the two that are about the algebra itself. `GAP-157` is here
because `std.` reaches are vocabulary that should arrive through layout/home/
world projection, and its remaining bulk is `std.script.*` whose canonical
targets are vocabulary-blocked.

**6 Realization One** — `GAP-121`, `GAP-126`, `GAP-130`, `GAP-148`, `GAP-151`,
`GAP-174`, `GAP-204`, `GAP-205`, `GAP-207`.
`GAP-148` reproduces exactly (`spilled_regs` still keyed by a physical register).
`GAP-174` is one law with two realizations and only one migrated. `GAP-207` is a
live silent wrong answer — see below.

**7 Foreign One** — `GAP-107`, `GAP-141`, `GAP-154`, `GAP-166`, `GAP-211`.
`GAP-141`'s security headline is crossed and gated with a real damage control.
`GAP-211` has a gate that pins it OPEN by name rather than closing it, and the
gate's fixture is declaration-vs-declaration, not the headline shape (a user
export capturing the compiler's own bootstrap extern), so the bootstrap symbol
set still has no control at all.

**8 Bootstrap/Evidence** — `GAP-050`, `GAP-115`, `GAP-127`, `GAP-136`,
`GAP-139`, `GAP-152`, `GAP-172`.
`GAP-152`'s aggregate FTCFTW pass EXISTS and is green, and correctly prints
`complete FTCFTW proof: NOT PROVEN` — its honesty defect is that it indexes
`scripts/runtime_bench.id`, which `GAP-128` proves measures nothing.
`GAP-172` is the frontier machinery that `GAP-152` is one row of.

## What resists

**`GAP-167` (COLLISION-ZERO machinery ownership)** does not reduce to one
program. Its eleven audit targets belong to four different programs
(`lexer_dispatch`/`lexer_bridge`/`meta_dispatch` to 1, `transform_engine`/
`explain_pipeline` to 4, `c_frontend` to 7, `derive_registry`/`context` to 2).
It is a naming law that cuts across the algebras rather than an algebra. Nine of
its eleven targets are still present; the gate enforces on ADDED lines only, so
the nine are grandfathered.

**`GAP-168` (`scripts/` plural root rehome)** is path and identity hygiene
(`law.singular.one`), not a semantic algebra at all. Filing it as P0 beside
soundness defects is a priority error, not a classification one.

**`GAP-151`** is a coordination request between two owners rather than a defect,
and its own text says so. It is parked under Realization One because the
interface it asks for (`semantic application -> selected realization -> machine
range`) is a realization-side export, but nothing in it will move until someone
owns that export.

## Findings that outrank the classification

**A P0 silent wrong answer is live at `HEAD`, and the commit is named.**
`GAP-207` was filed about uncommitted work and opens "`HEAD` is correct". It is
not. `s = 'abc'; print(s .. "Z")` prints a pointer, exit 0, no diagnostic,
address varying per run. Bisected across two isolated worktrees with private
caches: correct at `ae5fea3b^`, wrong at `ae5fea3b`. See `gaps/GAP-207.md`.

**A tracked prebuilt binary is a stale oracle that manufactures false greens.**
`out/bin/idol` was last committed at `301ac0b0` (2026-08-20). At `dec7d509` it
disagrees with a fresh `zig build` on at least two verdicts: it prints `abcZ`
for the `GAP-207` reproduction where a fresh build prints a pointer, and it
reports `relation proof: pass` for `scripts/proof/relation.id` where a fresh
build refuses with `UnsupportedProgram` at `lowerExprCons() dnir_lower.zig:9769`.
Verification that runs `./out/bin/idol` is verification against a three-day-old
compiler. This is `GAP-115`'s class, arriving through a tracked artifact rather
than a shared temp path.

**Four gaps state something about `HEAD` that is false in the dangerous
direction** — believing them produces a wrong CLOSED:

- `GAP-127` declares `scripts/shcledger.id` and `scripts/selfhost_manifest.id`
  deleted. Both are tracked; `shcledger.id:17` still calls `io.popen`. Three SHC
  ledgers with contradicting counts coexist, which IS the contract drift the gap
  is named for, live and worse than filed.
- `GAP-128` cites `tools/wasm/src/ward.id` as the environment reader. That file
  does not exist; the engine was renamed to `engine.id`.
- `GAP-168` asserts `gate/path.id` `list(staged)` rejects plural roots via
  `plural(root(...))`. No such check exists, and `scripts/ledger/perf.id` is a
  positive control the gate must ACCEPT.
- `GAP-203`'s "Crossed 2026-08-21" credits `at_is_glued_world_face` in
  `src/parser.zig`. Only `at_is_glued_anchor` exists here.

**Static presence of a repair symbol is not evidence the defect is gone.** Two
supersession verdicts reached by reading the code were refuted by running it:
`GAP-204` (the positional-text table lowering landed, but the harness still
refuses at `runtime-global-call:tostring`, which is the gap's actual headline
consequence) and `GAP-207` (above). Both had a named, plausible superseding
commit. Neither was superseded.

## Reclassified in this pass, with the superseding commit named

| gap | verdict | superseded by |
| --- | --- | --- |
| `GAP-123` | CLOSED | `ace5f7d5` deleted `scripts/duo_lock.id`; `97753361` rerouted AGENTS item 4 to `tools/node/dev/idol-lock`; pinned by `tools/node/dev/census/convergence` |
| `GAP-135` | SUPERSEDED | `3cd3f07b` "revert gap[126]: remove textual relation reconstruction" |
| `GAP-142` | SUPERSEDED | `gate/admission.id` + `gate/admission.sh` + `evidence/mop/merge/readiness.md`; every adjudicated branch retired |
| `GAP-144` | SUPERSEDED | `5f08600a` "audit: reject name-selected table lowering" |
| `GAP-221` | SUPERSEDED | `5b93df17` "Binding origin: a shadowed field write no longer finds the module's word", verified by running `examples/shadowstore.id` |

Each carries its evidence in its own file. No gap was reclassified on the
strength of its own prose.

## Everything else stays OPEN

A gap that could not be verified cheaply stays OPEN. `GAP-126` and `GAP-147` are
explicitly UNVERIFIED: the first because its trigger shape is absent from the
tree so the original failure cannot be re-executed, the second because
reproducing it requires filling a transport buffer during `zig build test`.
Absence of a trigger is not a repair.
