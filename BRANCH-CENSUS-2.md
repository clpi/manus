# BRANCH-CENSUS-2 — second-wave reconciliation of the 16 remaining `codex/*` branches

Census worktree: `/Volumes/d 1/lanes/recon2` (detached on `origin/main`).
Baseline: `origin/main` = `b8073cef` ("The @ sigil belongs to the world, and a gate that
says so"). Main moved once mid-census (`debad1df` -> `b8073cef`); every count below was
re-verified against `b8073cef` and none changed.

Remote note: `origin` and `idol` are both `git@github.com:clpi/idol.git`, so each remote
branch appears twice in `git branch -r`. Counted once.

## Headline

**None of the 16 branches carries an unlanded change of its own except one, and that one
change is carried by four branches as three patch-identical copies.**

Thirteen distinct change-units exist across the 16 branches' 42 `git cherry '+'` commits.
Twelve of the thirteen are already on main under a different sha (rebased, reworked, or
superseded by a strictly better form). One is genuinely unlanded.

| Classification (branch level) | Count | Branches |
| --- | --- | --- |
| `ALREADY-IN` | 0 | — |
| `CONTENT-IN` | 7 | abi-mainzero-20260822, authority-edition, callable-linkage-20260822, flat-scalar-application, foreign-symbol-obseq, obseq-entry-id, typed-entry |
| `SUPERSEDED` | 5 | audit-final-20260823, audit-integration-20260823, foreign-symbol-quarantine-20260821, nul-quote-extent-20260823, p0a-integration-20260823 |
| `MERGEABLE-CONFLICT` (partial; carries the one live unit) | 4 | grammar-main-zero, integrate-chain-09b, main-zero-graphslice, main-zero-smokes |
| `RESEARCH-ONLY` / `ABANDONED` / `UNKNOWN` | 0 | — |

**LAND: 1 operation. DROP: 16 branches (all of them, after the one landing).**

## Method, and why `git cherry` and `merge-tree` both mislead here

* `git cherry origin/main <b>` marks a commit `+` whenever no patch-id match exists on
  main. Main advanced 102 commits this session and most of those landings were reworks,
  not patch-identical replays, so `+` here means "sha absent", never "content absent".
* `git merge-tree --write-tree origin/main <b>` **conflicts for all 16 branches** (4–18
  conflicting paths each) and equals `origin/main^{tree}` for none. That is an artifact of
  the branches' merge-bases being 30–150 commits behind, not evidence of live content. The
  no-op test that retired branches in wave 1 retires nothing here.
* `git cherry-pick -n <c>` onto pristine main conflicts for **all 24** distinct unique
  commits, for the same reason.

So the load-bearing test in this census is a **content-presence measurement**: for each
unique commit, every added line longer than 12 characters is searched for, literally, in
main's current version of the same file. A commit at 88–100% presence whose misses are
version numerals and comments is on main. A commit at 7–20% presence was answered by main
in a different shape. Both were then confirmed by naming main's commit and reading it.

## The thirteen distinct change-units

| # | Subject | Branch shas | On main as | Verdict | Evidence |
| --- | --- | --- | --- | --- | --- |
| 1 | `authority: bind exact source-law edition` | `98a1ac5d`, `89dfe981` | `c4d31bad` | CONTENT-IN | 832/862 added lines present (96%). All misses are graph-version numerals (branch pins 9/10, main is at **12**) and the branch's hard-fail `archive_valid` block, which main replaced with the richer complete/corrupt classifier in `b83a42e3` (`gate/authority.sh:373-439`). |
| 2 | `semantic: fail closed on invalid process entry` | `8749c205`, `4486964b`, `ed983177`, `d545243c` | `2a2f3a19` | CONTENT-IN | 78/84 (92%). Misses: one `ProcessEntryError!ProcessEntry` signature line and a 5-line TRANSITIONAL LINKAGE BRIDGE comment. Main additionally registers `authority_projection.zig` in `gate/layers.manifest`, which the branch form does not. |
| 3 | `gate: distinguish corrupt archive provenance from admission` | `c40e5346` | `b83a42e3` | CONTENT-IN | 80/81 (98%). Sole miss: `if graph["version"] != 10:`; main asserts `!= 12`. |
| 4 | `cli: add physical no-cache compile mode` | `d89647d8`, `93226204`, `27f3dfac` | `40493a63` | CONTENT-IN | 22/25 (88%). The three misses are the `--no-cache is valid only with compile **or run**` guard — which the branches themselves reverted one commit later in `aa5822a8 cli: keep no-cache compile-only`, and main has that too as `ee435ade`. Main's `src/main.zig:1067` reads `only with compile`. Fully converged. |
| 5 | `semantic: make callable linkage graph-owned` | `c2f68186` | `320c2433` | CONTENT-IN | 568/574 (98%). All six misses are the string `"version":11`; main's `semantic_graph.zig` emits 12 and carries `callable_linkages` (13 occurrences). |
| 6 | `graph: carry flat scalar projection into native and wasm` | `165ddf92`, `6bddb274`, `156f662f` | `c670e5db` | CONTENT-IN | `6bddb274` 1145/1148 (99%), `156f662f` 1145/1155 (99%), `165ddf92` 1005/1099 (91% — it is the oldest of the three). `examples/native/flat_scalar_projection.id` exists on main. **This corrects the working hypothesis**: `codex/flat-scalar-application`'s one remaining `+` commit is not an older base commit, it is `165ddf92` itself — the head — still marked `+` because `c670e5db` is a rework rather than a patch-identical replay. |
| 7 | `Quarantine malformed foreign boundary symbols` | `6bea7135` | `0e6ed62c` | CONTENT-IN | 470/477 (98%), including all 76 lines of `gate/foreign-symbol-quarantine.sh`, which exists on main. Misses are a doc comment and a GAP-211 scoping test. |
| 8 | `Refuse malformed foreign boundary symbols` | `aa388437` | `0e6ed62c` (rework of #7) | SUPERSEDED | 305/511 (59%): `src/tests.zig` 1/89, `gate/architecture-negative.sh` 1/8. This is the earlier draft that `6bea7135` replaced and that `0e6ed62c` landed. **Confirms the already-taken closure of PR #45.** |
| 9 | `Ask the divisor-nonzero obligation of the relation, not of a spelling` | `099db4d9` | `28ab0ed2` + `c2f02b3d` (+ gate work `28e4a765`/`f9121770`/`9c58463c`/`835a1aab`) | SUPERSEDED | 8/40 (20%) by line, but main has the *obligation form itself*: `native_ir.zig:126 pub fn requiresNonzeroDivisor`, asked at `dnir_lower.zig:12364` and three sites in `native_backend.zig`, with the exhaustive-switch law table in `tests.zig:123-167` and `gate/divisor.sh:204`. Main's is strictly the better realization (it also has a gate). Same subject as the deliberately-unlanded `d4f21357` on `reconcile/shadow-clean-20260822`. |
| 10 | `Count the std ratchet at code positions; budget 473 -> 350` | `8a036b59` | `85fb8457 The std ratchet counts reaches, not bytes` | SUPERSEDED — **do not reintroduce** | 18/233 (7%). Main pins `STD_BUDGET=311` at code positions (`gate/admission.sh:100`) and reconciles the 473/350/311 arithmetic in a 40-line comment at lines 78-99. Twin of `8c0796f4`, on the known do-not-land list. |
| 11 | `p0: close numeric and cache wrong-answer paths` | `c283f2ea` (50%), `0bf7f54e` (71%) | decomposed across `01552790`, `ec8cd93d`, `a9128ef7`, `28ab0ed2`, `c2f02b3d` | SUPERSEDED, and partly **REJECTED** | These are integration squashes. Every residual line falls in one of three buckets: (a) the **rejected** INT_MIN form — `ast.negatedIntLiteral` returning `i64` and wrapping at `minInt`; main's `src/ast.zig:510` returns `?i64` and yields `null`, with the parse-time refusal in `src/parser.zig:548-563` via `DecimalIntegerClass.min_magnitude` (`01552790`). Twin of the rejected `466e2002`. (b) the superseded divisor form (#9). (c) `SDKROOT` + `env-census`, which main has as `src/main.zig:367 .{ "SDKROOT", .modelled }`, `do_env_census` at `:392`, and `gate/envcache.sh` (`ec8cd93d`, `a9128ef7`) — twin of the do-not-land `6845d47d`. Also the lexer `int_class` plumbing, which main spells `_fieldintclass()` at `lexer_dispatch.zig:159` rather than the branch's `position()`. |
| 12 | `Consume graph initializer for checked integer operands` | `508270ad` | `2ee24a52 Consume binding initializer identity in checked calls` | SUPERSEDED | 152/171 (88%). Main has `checkedBindingI64` at `dnir_lower.zig:10338`, but returns a `BindingI64Decision` union (`unvisited` / `value`) instead of the branch's `?dnir.Value`, and adds a physical-module-word load path plus five `invalidGraphFacts` refusals the branch answers with a bare `null`. Consumed at `:10549` through an exhaustive switch. Strictly better; do not replay the optional form. |
| 13 | `evidence: preserve exact process outcomes` | `d80a401f`, `7af5b0fc`, `613e3dca` — **all three patch-identical** (patch-id `34c60e44`, identical blobs for all four files, identical parent subject) | **NOT ON MAIN** | **LAND** | 24/257 (9%). Main's `scripts/native_differential.id` is still the pre-rework file: `bounded = ""`, `rc: i64 = (bin: str)`, and the "THE STATUS READ IS LOAD-BEARING" header. See below. |

## The one live unit: `evidence: preserve exact process outcomes`

Files: `gate/differential.sh`, `scripts/capability_rows.id`, `scripts/capability_table.id`,
`scripts/native_differential.id` (+290 / -143).

What it does: replaces the shell-status-only observation in the three Idol report scripts
with a one-run **event + status** observation driven by a shared perl limiter, so ordinary
exit 154 is distinguishable from signal 26, and ordinary exit 124 from a watchdog timeout.
Adds `eventof`, `observe`, `usableevent`, `hashfile`, and threads an `event` argument
through `exitmatch`.

Why it is still live: main already carries the *shell* half of this. `gate/differential.sh`
on main has `LIMITER`, `observe()` at line 152, and `ok|signal:*` cases at 255/264, and its
selftest banner already names the `exit154/signal26/partial-output and exit124/timeout`
controls. What main does **not** have is the same discipline in the three `.id` mirrors,
which are live build steps (`zig build capability-rows`, `zig build capability-table`, and
the native-differential step at `build.zig:998`). The branch commit closes exactly that gap.

Conflict profile — `git cherry-pick -n 613e3dca` onto `b8073cef`:

| Path | Conflict hunks | Resolution |
| --- | --- | --- |
| `gate/differential.sh` | 1 | **Take HEAD.** The only conflict is the selftest banner string; main's is a strict superset (adds `sibling-mirror null row, per-arm cwd, real row survives normalisation`). The branch has nothing to add to this file. |
| `scripts/capability_rows.id` | 1 | Take the branch's `probetext` limiter/event block, re-escaped to main's convention. |
| `scripts/capability_table.id` | 4 | Rework required — see below. |
| `scripts/native_differential.id` | 3 | Rework required — see below. |

The two `.id` files need a **rework, not a mechanical resolve**, because main has since
changed their spelling in ways the branch predates:

* `d0303cbf canonical: keep integration identities private` renamed `exitmatch` ->
  `_exitmatch` and `exitcontrols` -> `_exitcontrols` in both files. The landing must keep
  the underscore prefix.
* Brace escaping moved from `\\{` to `\{` (`capability_rows.id:336`, `capability_table.id`
  `hasint`).
* `std.script.*` -> `script.*` migration on several call sites.
* `bfd07c2f teaching: 21 comments still taught the sigil as the descriptor spelling` and
  `bce75f47 evidence: require empty output for exit oracles` also touched these files after
  the branch point.

Main-side delta since the branch's parent is small — 3 lines in `capability_rows.id`,
9 in `capability_table.id`, 9 in `native_differential.id` — so the rework is bounded.

## Per-branch table

| Branch | `+` | Distinct units | Classification | Disposition |
| --- | --- | --- | --- | --- |
| `codex/abi-mainzero-20260822` (`48adf22f`, mb `7483b1b4`) | 4 | 1,2,3,4 | CONTENT-IN | DROP |
| `codex/audit-final-20260823` (`f4a7ae83`, mb `15cbdc25`) | 2 | 9,6 | SUPERSEDED | DROP |
| `codex/audit-integration-20260823` (`156f662f`, mb `c77dea60`) | 3 | 10,11,6 | SUPERSEDED (10 is do-not-land) | DROP |
| `codex/authority-edition` (`89dfe981`, mb `31453966`) | 1 | 1 | CONTENT-IN | DROP |
| `codex/callable-linkage-20260822` (`c2f68186`, mb `7483b1b4`) | 5 | 1,2,3,4,5 | CONTENT-IN | DROP |
| `codex/flat-scalar-application` (`165ddf92`, mb `31453966`) | 1 | 6 | CONTENT-IN | DROP |
| `codex/foreign-symbol-obseq` (`6bea7135`, mb `31453966`) | 3 | 1,2,7 | CONTENT-IN | DROP |
| `codex/foreign-symbol-quarantine-20260821` (`aa388437`, mb `6025f9d5`) | 1 | 8 | SUPERSEDED (PR #45, already closed) | DROP |
| `codex/grammar-main-zero` (`623bfd36`, mb `f1ba66f1`) | 3 | 2,4,**13** | MERGEABLE-CONFLICT (partial) | **LAND unit 13**, then DROP |
| `codex/integrate-chain-09b` (`79be9e07`, mb `929b6ba1`) | 3 | 2,4,**13** | MERGEABLE-CONFLICT (partial) | DROP (payload identical to above) |
| `codex/main-zero-graphslice` (`f013c5b3`, mb `7483b1b4`) | 5 | 1,2,3,4,**13** | MERGEABLE-CONFLICT (partial) | DROP (payload identical) |
| `codex/main-zero-smokes` (`0c1173aa`, mb `7483b1b4`) | 5 | 1,2,3,4,**13** | MERGEABLE-CONFLICT (partial) | DROP (payload identical) |
| `codex/nul-quote-extent-20260823` (`508270ad`, mb `f9fbeada`) | 1 | 12 | SUPERSEDED | DROP |
| `codex/obseq-entry-id` (`06ca206d`, mb `31453966`) | 2 | 1,2 | CONTENT-IN | DROP |
| `codex/p0a-integration-20260823` (`0bf7f54e`, mb `ce03c7eb`) | 1 | 11 | SUPERSEDED, partly REJECTED | DROP |
| `codex/typed-entry` (`4486964b`, mb `31453966`) | 2 | 1,2 | CONTENT-IN | DROP |

`codex/main-zero-graphslice` and `codex/main-zero-smokes` have *identical* unique-commit
sets; only their trees differ.

## Ordered landing plan

Main enforces `required_linear_history`, PR-only, `enforce_admins`, and no force-push.
So the landing is a **cherry-pick onto a fresh branch off `origin/main` + PR**, never a
merge commit. GitHub Actions is dead on billing (`recent account payments have failed`), so
`zig build --summary all` + `zig build unit-test` run locally is the only merge signal.

### Step 1 (and only step) — `evidence: preserve exact process outcomes`

```
git -C "/Volumes/d 1/lanes/recon2" checkout -B land/evidence-process-outcomes origin/main
git cherry-pick -n 613e3dca        # == d80a401f == 7af5b0fc
```

Expected conflicts, in the order git reports them:

1. `gate/differential.sh` — 1 hunk. **Take HEAD.** `git checkout --ours gate/differential.sh`
   is the whole resolution; the branch contributes nothing here that main lacks.
2. `scripts/capability_rows.id` — 1 hunk, in `probetext`. Take the branch's
   limiter/`eventof`/`observe`/5-arg `exitmatch` block; change `\\{` to `\{` to match main's
   current escaping.
3. `scripts/native_differential.id` — 3 hunks. Take the branch's `eventof` / `observe` /
   `usableevent` / `hashfile` / `outtext(path)` rework, then rename `exitmatch` ->
   `_exitmatch` and `exitcontrols` -> `_exitcontrols` per `d0303cbf`, and keep main's
   `script.*` (not `std.script.*`) spelling at the migrated call sites.
4. `scripts/capability_table.id` — 4 hunks. Same rework and same two renames; also preserve
   main's `hasint` body (`awk '/^--/ \{c++\} END\{print c+0\}'`, `script.chomp`/`script.capture`).

Then:

```
zig build --summary all
zig build unit-test
zig build capability-rows
zig build capability-table
```

The last two are the steps this commit actually changes; a green `zig build` alone does not
exercise them.

No later step depends on this one, and no other branch needs landing, so there is no
ordering beyond "step 1".

### Step 2 — delete

After step 1 merges, all 16 branches are droppable. The three sibling copies of unit 13
(`d80a401f` on `grammar-main-zero`, `7af5b0fc` on `integrate-chain-09b`, `613e3dca` on
`main-zero-graphslice` and `main-zero-smokes`) become `ALREADY-IN` under `git cherry` only
if the landing is patch-identical; after the rework above it will not be, so delete them by
name rather than by re-running `git cherry`.

## NEEDS-HUMAN

1. **Does unit 13 land at all, given its own commit body disclaims measurement?** The
   commit says: *"EVIDENCE STATUS: this source route is currently UNMEASURED end to end.
   The native expect gate is the executable typed-outcome authority; checking this report
   source proves only that the source repair remains accepted."* The `.id` mirrors are real
   build steps, but if the shell gate is the authority and the mirrors are advisory, this
   is a rework of an advisory artifact. **Land it, or close it as an artifact of a route
   that is being retired?** (Note: `git ls-tree origin/main | grep -i expect` finds no
   expect gate in this repo at all — the "native expect gate" it defers to is not on main.)

2. **Whose convention wins in the reworked `.id` scripts?** The branch predates
   `d0303cbf canonical: keep integration identities private`. I am assuming main's
   underscore-prefixed `_exitmatch`/`_exitcontrols` and `script.*` spelling survive and the
   branch's *semantics* are grafted onto them. Confirm before the resolve, because the
   alternative reading — that `d0303cbf` deliberately privatised these helpers on the way to
   deleting them — would make the landing pointless.

3. **`codex/nul-quote-extent-20260823` is named for work that is not in it.** Its single
   unique commit is `508270ad`, the checked-integer binding initializer, superseded by
   `2ee24a52`. No NUL/quote-extent change survives on it above main. If there was a
   nul-quote-extent deliverable expected from that session, it is either already on main
   under another name or it was never committed — worth one look before the branch is
   deleted.

## Appendix — non-`codex/*` refs still carrying unique commits

Outside the assigned 16, and outside this census's scope, but enumerated as requested.
Counts here are from a moving target: `lane/*` refs were being rewritten by live sessions
during the census and two of them changed count mid-run.

| Ref | `+` | Note |
| --- | --- | --- |
| `origin/audit/macmini-live-20260820` (= `idol/...`) | 5 | CI/runner probing commits from 2026-08-20; no compiler content. Likely `ABANDONED`. |
| `origin/fix/gap134-binop-owner` (= `idol/...`, = local `lane/gap134-20260823`) | 5 | GAP-134 grammar-owner work, live lane. Not mine to classify. |
| `origin/fix/directive-ratchet` | 0 | Was 1 at census start; landed or rebased mid-run. |
| `lane/demand-20260823` | 1 | `b1cba9da effect: the card must be able to name the observation…`. Live lane. |
| `lane/directive-20260823` | 0 | |
| `lane/integrated-20260823` | 3 | Evidence/status commits at `c77dea60`. Live lane. |
| `reconcile/shadow-clean-20260822` | 6 | The five deliberately-unlanded commits (`8c0796f4`, `d4f21357`, `e37348d4`, `6845d47d`, `466e2002`) plus `d2e8df89`, owned by another lane. Three of the five are the upstream twins of units 9, 10 and the INT_MIN half of 11 above, which is how those were recognised. |

Every other remote branch fetched from `git@github.com:clpi/idol.git` — including
`fix/cache-env-closure`, `fix/world-face-zero`, `fix/intmin-one-producer`,
`fix/divisor-one-producer`, `fix/std-code-position-budget`, `fix/gap145-observers`,
`fix/application-continuity`, `fix/oracle-string-order-unsigned`,
`gaps/declare-kind-218-222` — has **zero** unique commits against `b8073cef`.
