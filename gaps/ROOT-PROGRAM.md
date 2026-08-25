# ROOT-PROGRAM — the active-P0 surface collapsed onto eight programs

**Status:** OPEN · **Filed:** 2026-08-23
**Kind:** projection · **Normative for:** nothing — this is a projection of `gaps/GAP-*.md`
**Derived, not authored:** the membership below is a reading of the gaps; the
gaps are the authority.
**Not the per-gap frontier.** Each gap states its own machine-read frontier in
an `idol.gap.frontier.v1` block that `gate/frontier.sh` validates and fails
closed on. This file is a reading ACROSS gaps, which is why it carries a
derivation command instead of a census, and why it must never be cited where a
gap's own frontier block answers the question.
**The membership is checked against the gaps, not trusted.**
`gate/frontier.sh` reads this file's program rosters and its reclassification
table and compares both against the live `GAP-*.md` headers on disk: a gap named
here must exist; a gap listed under a program must still be selected by the
active-P0 census unless the line marks it `(not P0)`; and a gap in the
reclassification table must NOT be selected. So dispatch cannot silently point
at closed or reopened work — that is a gate failure, not a stale paragraph. What
the gate does NOT check, and what therefore remains a reading, is WHICH program
a gap belongs to and the narrative under each heading.

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
`GAP-202`, `GAP-113`, `GAP-125`, `GAP-132`, `GAP-153`, `GAP-161`, `GAP-165`,
`GAP-221`.
`GAP-201` is the umbrella that owns the remaining bridge inventory; `GAP-137`
owns one fact being optional and fail-open and is one row from closed;
`GAP-202` owns making the one application algebra complete enough that scalar
multiplication needs no subsystem of its own. `GAP-132` is the sharpest live
defect in the program and reproduces in one command. `GAP-221` is a fact the
graph does not publish (per-body binding origin) read off a spelling instead;
its wrong ANSWER is crossed and its deletion witness and its pin are not.
The module-binding write that used to sit beside it — a write read off a
spelling because the lift minted a same-spelled local for it — is CLOSED and
reclassified below.

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

**6 Realization One** — `GAP-121`, `GAP-126`, `GAP-130`, `GAP-144`, `GAP-148`,
`GAP-151`, `GAP-174`, `GAP-204`, `GAP-205`, `GAP-207`.
`GAP-148` reproduces exactly (`spilled_regs` still keyed by a physical register).
`GAP-174` is one law with two realizations and only one migrated. `GAP-207` is a
live silent wrong answer — see below. `GAP-144` owns runtime-sized table
realization and `GAP-169` (not P0) routes to it by name; its rejection half is crossed
and its construction half is unstarted, so it is the growable-table hole rather
than a duplicate of `GAP-148`, which is register spilling and fixed-frame value
locations and covers none of it.

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

**A tracked prebuilt binary was a stale oracle that manufactured false greens —
CLOSED by deleting the binary.** `out/bin/idol` was last committed at `301ac0b0`
(2026-08-20). At `dec7d509` it disagreed with a fresh `zig build` on at least two
verdicts: it printed `abcZ` for the `GAP-207` reproduction where a fresh build
printed a pointer, and it reported `relation proof: pass` for
`scripts/proof/relation.id` where a fresh build refused with
`UnsupportedProgram` at `lowerExprCons() dnir_lower.zig:9769`. This was
`GAP-115`'s class arriving through a tracked artifact rather than a shared temp
path, and the class is closed the same way: the artifact is untracked and `out/`
is gone, so there is no second compiler in the tree for a verification to reach
by accident. Four documents that warned readers away from the path have been
reconciled to say it no longer exists rather than to keep steering around it.

**Four gaps state something about `HEAD` that is false in the dangerous
direction** — believing them produces a wrong CLOSED:

- ~~`GAP-127` declares `scripts/shcledger.id` and `scripts/selfhost_manifest.id`
  deleted. Both are tracked; `shcledger.id:17` still calls `io.popen`. Three SHC
  ledgers with contradicting counts coexist, which IS the contract drift the gap
  is named for, live and worse than filed.~~ **RESOLVED 2026-08-24 by deleting
  the files rather than the claim.** One SHC ledger remains,
  `scripts/ledger/shc.id`. The deciding measurement: `selfhost_manifest.id` does
  not compile (`idol check` refuses `_row` at `1:1`), and `shcledger.id`
  consumed it by `grep -c` rather than by running it, so its counts were a
  substring tally over a file the compiler rejects. See `gaps/GAP-127.md`
  § 2026-08-24.
- `GAP-128` was said here to cite `tools/wasm/src/ward.id` as the environment
  reader. **Re-read 2026-08-24: it does not.** The gap's `**Files:**` line and
  its body both name `tools/wasm/src/engine.id`, and the only `ward` tokens in it
  are the two ENV VARIABLE names `WARD_WASM`/`WARD_INVOKE`, which are what the
  gap is about. The stale `ward.id` path was in the SCRIPTS: a paragraph in
  `scripts/runtime_bench.id` asserting that `ward.id` reads those two names, and
  comment rows in `scripts/audit100.id`.

  Chasing it there found a live wrong number rather than only stale prose. The
  `AXIS loc` row measured the Idol runtime core as
  `'tools/wasm/src/ward.id' 'tools/wasm/src/wasm/*.id'`. `git ls-files` answers a
  nonexistent pathspec with silence, so the engine contributed 0 and the wasm
  partition kept the total nonzero — past the row's own `<= 0` guard, whose
  comment says "a zero here is a broken pathspec, not a small runtime". The row
  under-reported the Idol runtime by 6,886 of 10,192 lines, 68%, in the
  flattering direction, in a table whose whole subject is Idol versus wart. Each
  component is now counted separately and the guard fires per component.

  Also measured while there: `WARD_WASM`/`WARD_INVOKE` appear nowhere in this
  tree except that script and `GAP-128`, and `build.zig` has no `ward` step. So
  the ward axis has no in-tree producer for either the binary or the variable
  names. It refuses honestly at its `exists(wardbin)` check; restoring it means
  naming a producer, which is `GAP-128`'s actual remaining work.
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
| `GAP-225` | CLOSED | the lift names the module binding a relation writes and `publishApplicationMutations` publishes its cardinality; the census movement and the hazard row are what `sh gate/effect.sh` and `sh gate/speculation.sh` print, and the floors are pinned in those runners; regression `examples/place/mutate.id` |

Each carries its evidence in its own file. No gap was reclassified on the
strength of its own prose.

## Two proposed reclassifications withdrawn, and why

`GAP-144` and `GAP-221` were proposed for SUPERSEDED in this pass and are NOT.
Both proposals had a true measurement under them and drew the wrong verdict from
it, in the same way: **a gap's headline going quiet is not its closure
condition.**

- `GAP-144` — the rejected branch really is out of the tree
  (`git grep -n 'collectIndexedNames' -- src/` is empty). But rejecting a
  name-selected implementation is not supplying a graph-authoritative one, and
  the receiving owner named in the proposal, `GAP-148`, is register spilling and
  fixed-frame value locations. It carries none of `GAP-144`'s eight
  required-boundary items and none of its six negative controls, and
  `gaps/GAP-169.md` routes "runtime-sized table realization" AT `GAP-144` by
  name. Superseding it would have dropped a P0 obligation and dangled that
  pointer.
- `GAP-221` — `examples/shadowstore.id` really does answer `7 99 7` on a fresh
  build. But this gap's stated deletion witness is unmet, and NOTHING pins the
  answer: `git grep -n shadowstore -- gate/ build.zig tests/ tools/ scripts/` is
  empty, so a re-regression would be silent. One manual run at one revision is
  the evidentiary shape that produced the false SUPERSEDED reading of `GAP-207`,
  which is the live wrong answer this same pass found.

Both now carry gated `idol.gap.frontier.v1` blocks that say which half is
crossed, so the measurement is kept and the obligation is not.

## Everything else stays OPEN

A gap that could not be verified cheaply stays OPEN. `GAP-126` and `GAP-147` are
explicitly UNVERIFIED: the first because its trigger shape is absent from the
tree so the original failure cannot be re-executed, the second because
reproducing it requires filling a transport buffer during `zig build test`.
Absence of a trigger is not a repair.
