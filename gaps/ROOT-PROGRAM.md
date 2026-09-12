| field | value |
|---|---|
| title | ROOT-PROGRAM — the active-P0 surface collapsed onto eight programs |
| status | OPEN |
| filed | 2026-08-23 |
| kind | projection |
| normative for | nothing — this is a projection of |
| derived, not authored | the membership below is a reading of the gaps; the gaps are the authority. **Not the per-gap frontier.** Each gap states its own machine-read frontier in an  block that  validates and fails closed on. |

| # | directive |
|---|---|
| 2 | This file is a reading ACROSS gaps, which is why it carries a derivation command instead of a census, and why it must never be cited where a gap's own frontier block answers the question. **The membership is checked against the gaps, not trusted.** `gate/frontier.sh` reads this file's program rosters and its reclassification table and compares both against the live `GAP-*.md` headers on disk: a gap named here must exist; a gap listed under a program must still be selected by the active-P0 census unless the line marks it `(not P0)`; and a gap in the reclassification table must NOT be selected. |
| 3 | So dispatch cannot silently point at closed or reopened work — that is a gate failure, not a stale paragraph. |
| 4 | What the gate does NOT check, and what therefore remains a reading, is WHICH program a gap belongs to and the narrative under each heading. |

| section |
|---|---|
| Why this exists |

| # | directive |
|---|---|
| 1 | The open-gap surface was too large to dispatch against. |
| 2 | The census selector is |

```sh
for gap in gaps/GAP-*.md; do h="$(sed -n '1,8p' "$gap")"
  printf '%s\n' "$h" | grep -Eiq '^\*\*Status:\*\*[[:space:]]*(OPEN|REOPENED)([[:space:]·(:—-]|$)' &&
  printf '%s\n' "$h" | grep -Eiq '^\*\*(Status|Priority):\*\*.*P0' && echo "$gap"
done
```

| # | directive |
|---|---|
| 1 | Do not read a count out of this file — that is the rule this whole pass exists to enforce, and the number moved twice while the pass was being written. |

<!-- idol-projection-roster:v1:begin -->

| # | directive |
|---|---|
| 1 | The collapse is real but it is not eight-way. |
| 2 | Most current blockers funnel into two gaps, and neither is a member of a program so much as the floor under several of them. |

| # | directive |
|---|---|
| 1 | **`GAP-124` — identity-based canonicality from graph facts.** Its own ledgers say so out loud: `scripts/ledger/semantic.id` reports `WORLDGATE`, `VOCABGATE`, `SENTINELGATE` and `CONTROLREDUCE` interned and `SUBJECTGATE waits on application subject edges`; `scripts/ledger/graph.id` reports the func tag gate open. `GAP-125`, `GAP-132`, `GAP-153`, `GAP-161` and `GAP-165` each name it as their unblocker. |

| # | directive |
|---|---|
| 1 | **`GAP-119` — process/execution world vocabulary.** `docs/spec/world.md` §313 specifies it (`command:run() requires process world`, "Not `io.popen`, not `process.capture`"). |
| 2 | Nothing implements it: no `command` subject in `src/subject_home.zig`, no process world anywhere in `src/`, `lib/proc.id` still reaching `io.popen` / `os.execute`, and `docs/spec/law.md` does not mention process at all. `GAP-127`, `GAP-128`, `GAP-146` and `GAP-147` are all waiting on it — three of them are "a gate reports success it did not earn", which is the same missing fact seen from the evidence side. |

| # | directive |
|---|---|
| 1 | Close those two and the dispatchable surface shrinks more than any other pair. |

| section |
|---|---|
| The eight programs |

| # | directive |
|---|---|
| 1 | **1 Lexical/Grammar One** — `GAP-134`, `GAP-145`, `GAP-092`, `GAP-163`. |
| 2 | The grammar-fact owner transfer is done (`lib/compiler/token.id`); what remains is `docs/spec/grammar.md` not generating the parser, Tree-sitter as a second authored authority whose byte-identity control cannot execute, the host `TokenKind` enum, and the second keyword producer. `GAP-092`'s surviving half is the `.call` / `.method_call` split; its identity half is crossed and gated by `gate/delimiter-projection-law.sh`. `GAP-163` sits here for the `duo`/`DUO_` name purge only. |

| # | directive |
|---|---|
| 1 | **2 Application/Graph Sovereignty** — `GAP-124`, `GAP-137`, `GAP-201`, `GAP-202`, `GAP-125`, `GAP-132`, `GAP-153`, `GAP-161`, `GAP-165`, `GAP-221`. `GAP-201` is the umbrella that owns the remaining bridge inventory; `GAP-137` owns one fact being optional and fail-open and is one row from closed; `GAP-202` owns making the one application algebra complete enough that scalar multiplication needs no subsystem of its own. `GAP-132` is the sharpest live defect in the program and reproduces in one command. `GAP-221` — a fact the graph did not publish (per-body binding origin) read off a spelling instead — was reclassified CLOSED in this pass and is REOPENED at `29d77ed0`. |
| 2 | Its deletion witness holds and is not in question. |
| 3 | Its guard is dead: `moduleFieldWord` admits the module's word only for a binding `bindingNamedIn` resolves AND whose scope is `module_root`, and those two cannot both hold, so it returns null in every relation body — including the one that wrote the field. |
| 4 | Measured by the unit test `dnir_lower: GAP-221 a module field base is unresolvable from a relation body`, which carries its own control. |
| 5 | The reclassification said `gate/gap-221-shadowstore.sh` pinned the answer; the gate ran four `grep`s and no program, and the repair it certified was landed with "Fixture execution requires backend support" in its own commit message. |
| 6 | The gate now runs the four fixtures and reports BLOCKED rather than PASS while they refuse at parse, and checks first that they still match HEAD byte for byte. |
| 7 | The host half of that blocker is narrower than it was recorded: `.id` programs DO execute here via `--backend=c --emit=c` plus `tools/node/dev/grammar/idol_c_runtime_shim.c` plus `cc` — `print(7)` prints 7 — so what is missing is not execution but table field access, which the C99 slice refuses and the direct backend has no aarch64-linux realization for. |
| 8 | The module-binding write that used to sit beside it — a write read off a spelling because the lift minted a same-spelled local for it — is CLOSED and reclassified below. |

| # | directive |
|---|---|
| 1 | **3 Demand + Laws** — `GAP-187` (root, research), `GAP-149`, `GAP-138`. `GAP-187` declares `Kind: research_gap` and its own C0 block calls it "the P0 semantic-spine root"; it describes an unbuilt algebra, not a live defect. `GAP-149`'s doc half is crossed (`docs/spec/numerics.md` is now a primitive-zero projection) and its code half is not. `GAP-138` is here because a `present \| absent` result is a law question, and its regression is an in-band `-1` sentinel. |

| # | directive |
|---|---|
| 1 | **4 Transformation Algebra** — `GAP-217` (not P0), and the `src/transform_engine.zig` / `src/explain_pipeline.zig` rows of `GAP-167`. |
| 2 | This is the thinnest program in the active-P0 set. |
| 3 | That is itself a finding: the transformation half of the architecture has almost no live P0 pressure on it. |

| # | directive |
|---|---|
| 1 | **5 World/Stage Algebra** — `GAP-119` (chokepoint), `GAP-128`, `GAP-146`, `GAP-147`, `GAP-157`, `GAP-203`. of the world algebra has no graph fact — `WorldFact` still carries no parent and no delta range) are the two that are about the algebra itself. `GAP-157` is here because `std.` reaches are vocabulary that should arrive through layout/home/ world projection, and its remaining bulk is `std.script.*` whose canonical targets are vocabulary-blocked. |

| # | directive |
|---|---|
| 1 | **6 Realization One** — `GAP-121`, `GAP-126`, `GAP-130`, `GAP-144`, `GAP-148`, `GAP-151`, `GAP-174`, `GAP-204` (not P0), `GAP-205`, `GAP-207`. `GAP-148` reproduces exactly (`spilled_regs` still keyed by a physical register). `GAP-174` — one law with two realizations and only one migrated — was reclassified CLOSED in this pass on `9e59d168`, which preserves the value-carrying tail of a multi-statement branch in the lowering both non-direct emitters share, recorded by `23e0a53e`. **Its owner reopened it at `ac05e4ea` ("GAP-174: reopen discarded branch result") and its header reads OPEN · P0**, so the marker and the reclassification row are withdrawn here and the evidence is kept in prose below. |
| 2 | This is bookkeeping in the projection, not a verdict on `GAP-174`: the census the gate computes reads the gap's own header, and the projection was the half that had gone stale. `GAP-207` is a live silent wrong answer — see below. `GAP-144` owns runtime-sized table realization and `GAP-169` (not P0) routes to it by name; its rejection half is crossed and its construction half is unstarted, so it is the growable-table hole rather than a duplicate of `GAP-148`, which is register spilling and fixed-frame value locations and covers none of it. |

| # | directive |
|---|---|
| 1 | **7 Foreign One** — `GAP-107`, `GAP-141`, `GAP-154`, `GAP-166`, `GAP-211`. `GAP-141`'s security headline is crossed and gated with a real damage control. `GAP-211` has a gate that pins it OPEN by name rather than closing it, and the gate's fixture is declaration-vs-declaration, not the headline shape (a user export capturing the compiler's own bootstrap extern), so the bootstrap symbol set still has no control at all. |

| # | directive |
|---|---|
| 1 | **8 Bootstrap/Evidence** — `GAP-050`, `GAP-127`, `GAP-136`, `GAP-139`, `GAP-152`, `GAP-172`. `GAP-152`'s aggregate FTCFTW pass EXISTS and is green, and correctly prints `complete FTCFTW proof: NOT PROVEN` — its honesty defect is that it indexes `scripts/runtime_bench.id`, which `GAP-128` proves measures nothing. `GAP-172` is the frontier machinery that `GAP-152` is one row of. |

| section |
|---|---|
| What resists |

| # | directive |
|---|---|
| 1 | **`GAP-167` (COLLISION-ZERO machinery ownership)** does not reduce to one program. |
| 2 | Its eleven audit targets belong to four different programs (`lexer_dispatch`/`lexer_bridge`/`meta_dispatch` to 1, `transform_engine`/ `explain_pipeline` to 4, `c_frontend` to 7, `derive_registry`/`context` to 2). |
| 3 | It is a naming law that cuts across the algebras rather than an algebra. |
| 4 | Nine of its eleven targets are still present; the gate enforces on ADDED lines only, so the nine are grandfathered. |

| # | directive |
|---|---|
| 1 | **`GAP-168` (`scripts/` plural root rehome)** is path and identity hygiene (`law.singular.one`), not a semantic algebra at all. |
| 2 | Filing it as P0 beside soundness defects is a priority error, not a classification one. |

| # | directive |
|---|---|
| 1 | **`GAP-151`** is a coordination request between two owners rather than a defect, and its own text says so. |
| 2 | It is parked under Realization One because the interface it asks for (`semantic application -> selected realization -> machine range`) is a realization-side export, but nothing in it will move until someone owns that export. |

<!-- idol-projection-roster:v1:end -->

| # | directive |
|---|---|
| 1 | **A P0 silent wrong answer is live at `HEAD`, and the commit is named.** `GAP-207` was filed about uncommitted work and opens "`HEAD` is correct". |
| 2 | It is not. `s = 'abc'; print(s .. "Z")` prints a pointer, exit 0, no diagnostic, address varying per run. |
| 3 | Bisected across two isolated worktrees with private caches: correct at `ae5fea3b^`, wrong at `ae5fea3b`. |
| 4 | See `gaps/GAP-207.md`. |

| # | directive |
|---|---|
| 1 | **A tracked prebuilt binary was a stale oracle that manufactured false greens — CLOSED by deleting the binary.** `out/bin/idol` was last committed at `301ac0b0` (2026-08-20). |
| 2 | At `dec7d509` it disagreed with a fresh `zig build` on at least two verdicts: it printed `abcZ` for the `GAP-207` reproduction where a fresh build printed a pointer, and it reported `relation proof: pass` for `scripts/proof/relation.id` where a fresh build refused with `UnsupportedProgram` at `lowerExprCons() dnir_lower.zig:9769`. |
| 3 | This was `GAP-115`'s class arriving through a tracked artifact rather than a shared temp path, and the class is closed the same way: the artifact is untracked and `out/` is gone, so there is no second compiler in the tree for a verification to reach by accident. |
| 4 | Four documents that warned readers away from the path have been reconciled to say it no longer exists rather than to keep steering around it. |

| # | directive |
|---|---|
| 1 | **Four gaps state something about `HEAD` that is false in the dangerous direction** — believing them produces a wrong CLOSED: |

| # | directive |
|---|---|
| 1 | ~~`GAP-127` declares `scripts/shcledger.id` and `scripts/selfhost_manifest.id` deleted. Both are tracked; `shcledger.id:17` still calls `io.popen`. Three SHC ledgers with contradicting counts coexist, which IS the contract drift the gap is named for, live and worse than filed.~~ **RESOLVED 2026-08-24 by deleting the files rather than the claim.** One SHC ledger remains, `scripts/ledger/shc.id`. The deciding measurement: `selfhost_manifest.id` does not compile (`idol check` refuses `_row` at `1:1`), and `shcledger.id` consumed it by `grep -c` rather than by running it, so its counts were a substring tally over a file the compiler rejects. See `gaps/GAP-127.md` § 2026-08-24. |
| 2 | `GAP-128` was said here to cite `tools/wasm/src/ward.id` as the environment reader. **Re-read 2026-08-24: it does not.** The gap's `**Files:**` line and its body both name `tools/wasm/src/engine.id`, and the only `ward` tokens in it are the two ENV VARIABLE names `WARD_WASM`/`WARD_INVOKE`, which are what the gap is about. The stale `ward.id` path was in the SCRIPTS: a paragraph in `scripts/runtime_bench.id` asserting that `ward.id` reads those two names, and comment rows in `scripts/audit100.id`. |

| # | directive |
|---|---|
| 1 | Chasing it there found a live wrong number rather than only stale prose. |
| 2 | The `AXIS loc` row measured the Idol runtime core as `'tools/wasm/src/ward.id' 'tools/wasm/src/wasm/*.id'`. `git ls-files` answers a nonexistent pathspec with silence, so the engine contributed 0 and the wasm partition kept the total nonzero — past the row's own `<= 0` guard, whose comment says "a zero here is a broken pathspec, not a small runtime". |
| 3 | The row under-reported the Idol runtime by 6,886 of 10,192 lines, 68%, in the flattering direction, in a table whose whole subject is Idol versus wart. |
| 4 | Each component is now counted separately and the guard fires per component. |

| # | directive |
|---|---|
| 1 | Also measured while there: `WARD_WASM`/`WARD_INVOKE` appear nowhere in this tree except that script and `GAP-128`, and `build.zig` has no `ward` step. |
| 2 | So the ward axis has no in-tree producer for either the binary or the variable names. |
| 3 | It refuses honestly at its `exists(wardbin)` check; restoring it means naming a producer, which is `GAP-128`'s actual remaining work. |

| # | directive |
|---|---|
| 1 | `GAP-168` asserts `gate/path.id` `list(staged)` rejects plural roots via `plural(root(...))`. No such check exists, and `scripts/ledger/perf.id` is a positive control the gate must ACCEPT. |
| 2 | `GAP-203`'s "Crossed 2026-08-21" credits `at_is_glued_world_face` in `src/parser.zig`. Only `at_is_glued_anchor` exists here. |

| # | directive |
|---|---|
| 1 | **Static presence of a repair symbol is not evidence the defect is gone.** Two supersession verdicts reached by reading the code were refuted by running it: `GAP-204` (the positional-text table lowering landed, but the harness still refuses at `runtime-global-call:tostring`, which is the gap's actual headline consequence) and `GAP-207` (above). |
| 2 | Both had a named, plausible superseding commit. |
| 3 | Neither was superseded. |

| section |
|---|---|
| Reclassified in this pass, with the superseding commit named |

| gap | verdict | superseded by |
| --- | --- | --- |
| `GAP-123` | CLOSED | `ace5f7d5` deleted `scripts/duo_lock.id`; `97753361` rerouted AGENTS item 4 to `tools/node/dev/idol-lock`; pinned by `tools/node/dev/census/convergence` |
| `GAP-135` | SUPERSEDED | `3cd3f07b` "revert gap[126]: remove textual relation reconstruction" |
| `GAP-142` | SUPERSEDED | `gate/admission.id` + `gate/admission.sh` + `evidence/mop/merge/readiness.md`; every adjudicated branch retired |
| `GAP-225` | CLOSED | the lift names the module binding a relation writes and `publishApplicationMutations` publishes its cardinality; the census movement and the hazard row are what `sh gate/effect.sh` and `sh gate/speculation.sh` print, and the floors are pinned in those runners; regression `examples/place/mutate.id` |
| `GAP-115` | CLOSED | `99673d63` "evidence: a fixed /tmp name is a fact any concurrent session can rewrite"; doctor/census/projection/positive-controls now mint run-private mktemp roots, pinned by `gate/gap-115-evidence.sh` |
| # | directive |
|---|---|
| 1 | `GAP-174`'s row stood here and is withdrawn: `9e59d168` preserves the value-carrying tail of a multi-statement branch in a saved-answering context in `src/dnir_lower.zig` — the lowering both non-direct emitters share, which is upstream of each of them, as the row-for-row identical wrongness said it had to be; recorded by `23e0a53e`. |
| 2 | That evidence stands. |
| 3 | The verdict does not: the gap was reopened at `ac05e4ea` and the census selects it again. |
| 4 | A row left behind a reopening is the same half-edit `31676024` had to repair for `GAP-221`, and it had the same effect — `gate/frontier.sh` BLOCKED, so `gate/admission-all.sh` refused every commit in the repository for reasons no staged diff could fix. |

| # | directive |
|---|---|
| 1 | Each carries its evidence in its own file. |
| 2 | No gap was reclassified on the strength of its own prose. |

| section |
|---|---|
| Two proposed reclassifications withdrawn, and why |

| # | directive |
|---|---|
| 1 | `GAP-144` and `GAP-221` were proposed for SUPERSEDED in this pass and are NOT. |
| 2 | Both proposals had a true measurement under them and drew the wrong verdict from it, in the same way: **a gap's headline going quiet is not its closure condition.** |

| # | directive |
|---|---|
| 1 | `GAP-144` — the rejected branch really is out of the tree (`git grep -n 'collectIndexedNames' -- src/` is empty). But rejecting a name-selected implementation is not supplying a graph-authoritative one, and the receiving owner named in the proposal, `GAP-148`, is register spilling and fixed-frame value locations. It carries none of `GAP-144`'s eight required-boundary items and none of its six negative controls, and `gaps/GAP-169.md` routes "runtime-sized table realization" AT `GAP-144` by name. Superseding it would have dropped a P0 obligation and dangled that pointer. |
| 2 | `GAP-221` — `examples/shadowstore.id` really does answer `7 99 7` on a fresh build. But this gap's stated deletion witness is unmet, and NOTHING pins the answer: `git grep -n shadowstore -- gate/ build.zig tests/ tools/ scripts/` is empty, so a re-regression would be silent. One manual run at one revision is the evidentiary shape that produced the false SUPERSEDED reading of `GAP-207`, which is the live wrong answer this same pass found. **Half crossed, then reopened:** the withdrawal named two missing things and `aa936dfa` supplied one. The deletion witness is met. The pin is not a pin — `gate/gap-221-shadowstore.sh` made that `git grep` non-empty with four `grep`s over `src/dnir_lower.zig` and no program, so the answer stayed exactly as unpinned as the withdrawal found it, and the repair certified by it was landed with "Fixture execution requires backend support" in its own commit message. `2954038e` and `29d77ed0` both measure the guard that repair installed to be dead. The gap is OPEN. The withdrawal stands as the RULING it was, and reads further than it was written: a quiet headline is not a closure, and neither is a met deletion witness when the acceptance it was supposed to unblock was never run. **And the reopening's own first draft made the same mistake one layer out:** it quoted a compile diagnostic that had been read off a corpus file `idol fmt` had silently rewritten, not off the file in Git. `idol fmt` ends in an unconditional `writeFile` with no `--check`, so on a mid-transfer grammar it exits 0 having written a DIFFERENT legal program — seven of the first sixty `examples/*.id` and this gap's own acceptance fixture, reproduced deterministically. `GAP-223` closed this corruption mode for its specific cause and its "Blast radius" predicted this recurrence verbatim; the hazard is live and is now the quieter shape, since the rewrite parses. The eight files are reverted and `gate/gap-221-shadowstore.sh` arm 0 now refuses to report an answer about a fixture that does not match HEAD. |

| # | directive |
|---|---|
| 1 | Both now carry gated `idol.gap.frontier.v1` blocks that say which half is crossed, so the measurement is kept and the obligation is not. |

| section |
|---|---|
| Everything else stays OPEN |

| # | directive |
|---|---|
| 1 | A gap that could not be verified cheaply stays OPEN. `GAP-126` and `GAP-147` are explicitly UNVERIFIED: the first because its trigger shape is absent from the tree so the original failure cannot be re-executed, the second because reproducing it requires filling a transport buffer during `zig build test`. |
| 2 | Absence of a trigger is not a repair. |
