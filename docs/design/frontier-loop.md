# Frontier Loop: the permanent research process

**Status:** process spec. **Invariant: this never stops.** The Idol compiler
wins by staying ahead of the field, not by catching up to it once. A
one-time survey (`docs/design/frontier-research.md`, F1–F24) decays the day
it is written; this document specifies the loop that keeps it current.

## 1. The loop

```
SCAN (weekly) → EVALUATE (≤48h) → DECIDE (integrate / watch / reject)
      → LOG (frontier-log.md, append-only) → SCAN …
```

- **Scan:** sweep the source list (§3) for items since the last scan that are
  `[NEW]` (published recently) or `[MISSED]` (any age, not covered by
  F1–F24 or any later finding). Dedupe by topic, not by title.
- **Evaluate:** every candidate finding gets an Idol-integration evaluation
  within **48 hours** of being logged: summary, applicability verdict,
  concrete integration sketch naming the workstream, expected measurable win.
  The top tier gets the full rigor of the baseline survey's §1–§6 format;
  the rest get short evaluations. Nothing is logged without a verdict.
- **Decide:** against the criteria in §6. Outcomes: integrate (enters the
  P0/P1/P2 plan, possibly displacing a lower-win item), watch (logged with a
  revisit trigger, e.g. "IME/AME freeze"), or reject (logged with the reason
  — rejected findings are not re-scanned).
- **Log:** append a dated entry to `docs/design/frontier-log.md` per §7.
  The log is the institutional memory; the survey is the baseline.

**Escalation:** if a finding's expected win beats a current P0 item on the
same axis (runtime, size, compile time, or power), it is flagged
`P0-CANDIDATE` in the log and brought to the coordinator immediately — it
does not wait for the next planning cycle.

## 2. Cadence

| Rhythm | What | Owner |
|---|---|---|
| **Weekly** (Mon 06:00 America/Los_Angeles) | Automated scan job (§9): sweep → dedupe → draft entry | scan job |
| **Within 48h of scan** | Evaluation of every candidate finding | loop agent |
| **Monthly** (first Mon) | Deep scan: conference proceedings + journal issues in full, not just keyword sweeps | loop agent |
| **Continuous** | Watchlist triggers (e.g. "IME/AME ratified", "Nova Lake hardware on bench") fire evaluations out of band | coordinator |

The weekly scan is cheap by design (keyword sweeps + tracker diffs). The
monthly deep scan is where proceedings get read properly. A quiet week still
produces a log entry ("no new findings") — silence is data.

## 3. Source list

**Conferences (proceedings + talks):** PLDI, POPL, ASPLOS, MICRO, HPCA, ISCA,
CGO, OOPSLA, ICFP, EuroSys, OSDI, USENIX ATC, NeurIPS (ML-for-systems
track), ICML (same).

**Preprints:** arXiv cs.PL, cs.PF (performance), cs.AR (architecture),
cs.AI/cs.LG filtered to code/optimization, cs.CR for hardware safety
(CHERI-class).

**Industry compiler teams:** LLVM Discourse + llvm-project PRs (PGO, BOLT,
vectorizer, backends), LLVM Dev Meetings, GCC mailing lists / Cauldron,
Apple tech talks / WWDC compiler sessions, ARM tech blogs + KleidiAI repo,
NVIDIA / AMD GPU compiler blogs, Google Research + DeepMind publications,
Modular/Mojo kernel work, Meta engineering (BOLT/FDO).

**Proof / formal methods:** Lean community (leanprover Zulip, Lean Together),
Rocq/Coq releases, SMT Workshop + SMT-COMP results, cvc5/Z3 changelogs,
Verus releases.

**Hardware (for the bench-relevant targets):** Apple Silicon (M-series SME/
AMX notes), Intel (APX/AVX10/AMX enablement in GCC/LLVM/Linux), AMD Zen
roadmap, RISC-V International (profiles, IME/AME/VME task groups),
CHERI Alliance / Morello / FreeBSD CHERI.

**Trackers (diffed weekly, not browsed):** llvm-project, egglog, cranelift,
Verus, kleidiai, riscv non-ISA specs. New RFCs and merged PRs in the
PGO/vectorizer/outliner/BOLT areas are findings until evaluated otherwise.

## 4. Scan procedure (what the weekly job does)

1. Pull the source list (§3): fetch what's new since the last log entry's
   scan window (proceedings tables of contents, arXiv listings, tracker
   diffs, release notes).
2. Filter to compiler / PL / formal-methods / architecture / performance /
   AI-for-code relevance to Idol's axes: runtime, object size, compile
   time, power/capability.
3. Dedupe: search `frontier-research.md` and `frontier-log.md` for the topic;
   if covered, skip; if partially covered, the delta is the finding.
4. Draft candidate findings with pre-assigned F-numbers (continuing the
   global sequence), each marked `[NEW]` or `[MISSED]`.
5. Hand to evaluation (§5). The scan does not decide; it surfaces.

## 5. 48-hour evaluation SLA

Clock starts when a candidate finding is drafted. Within 48h it must carry:

- **Summary** (one paragraph, with citation: paper/DOI/URL + date).
- **Applicability verdict:** Yes / Yes (Pn) / Watch / No — with a one-line
  reason. "No" requires the honest-evaluation treatment (cf. the survey's
  §9): state what would change the verdict.
- **Integration sketch:** the Idol workstream, the concrete change in Idol
  terms (which `.id` file or pass, what the transformation looks like), and
  what must exist first (dependencies on other findings).
- **Expected measurable win:** a number on a bench axis (%, ×, absolute),
  with the reference class named (e.g. "LLVM-measured 3% on Clang/LLD over
  -Oz"). "Unknown, needs measurement" is acceptable only with a proposed
  microbenchmark.

Evaluation output goes into the log entry. If the evaluator cannot finish in
48h (e.g. needs hardware), the finding is logged as `EVAL-PENDING` with the
blocker named — the SLA is then on unblocking, not on guessing.

## 6. Integration decision criteria

A finding is integrated when it clears **all** of:

1. **Measurable win threshold** — at least one of:
   - ≥2% runtime geomean on the bench corpus, or ≥10% on a benchmark class;
   - ≥3% object-size reduction;
   - compile-time improvement, or <5% compile-time cost for a runtime win;
   - a power/capability win no percentage captures (effect systems, proofs,
     safety), judged by the coordinator.
2. **No brand regression:** the 35–45% compile-time lead and 45–50% size lead
   over clang -O3 are floors, not aspirations. Anything threatening them
   needs coordinator sign-off with a measured trade-off.
3. **Cost gate:** free / prepaid / local-only. No paid APIs, no keyed
   services, no new credentials anywhere in the toolchain (matches the
   F24 rule: learning offline, tables in the compiler).
4. **Falsifiability:** the win must be expressible as a bench oracle or
   microbenchmark *before* integration starts (per `optimum.md`) — if we
   can't measure it, we can't claim it.

**Priority assignment:** P0 = implementable now, measurable win, clears all
four gates (a P0-candidate that beats a current P0 on expected win escalates
per §1). P1 = near-term (needs another finding first, or a workstream
cycle). P2 = research bet (high ceiling, needs infrastructure or hardware
that doesn't exist yet). Watch = logged with a revisit trigger.

## 7. Logging rules (`frontier-log.md`)

- **Append-only.** Entries are never edited. Corrections are new entries
  referencing the finding number (`F25`, …).
- **One global F-sequence**, continuing the survey's F1–F24.
- **Entry format:** date + title; scan window; method/sources; findings
  (full evaluations for the top tier, short evaluations otherwise);
  explicitly-considered-and-deferred items; next scan due date.
- **Status tags** on findings where useful: `P0-CANDIDATE`, `EVAL-PENDING`,
  `WATCH(<trigger>)`, `REJECTED(<reason>)`, `SUPERSEDED-BY(Fn)`.
- A quiet week gets a dated entry saying so — the cadence is the product.

## 8. Roles

- **Loop agent** (this spec's executor): runs scans, evaluates within 48h,
  appends log entries, maintains the source list, fires watchlist triggers.
- **Coordinator:** installs the automation (§9), triages `P0-CANDIDATE`
  escalations, assigns accepted findings to workstream owners, owns the
  P0/P1/P2 plan the findings feed.
- **Workstream owners:** receive integrated findings with the evaluation
  attached; report measured wins back (which become log follow-ups).

## 9. Automation spec — for the coordinator to install (NOT yet installed)

**Job name:** `frontier-scan-weekly`.

**Schedule:** weekly, Monday 06:00 America/Los_Angeles. Monthly deep scan:
first Monday of the month, same time, with the deep-scan source set (§3,
conference proceedings in full).

**What it runs:** a loop agent session with this document and the latest
`frontier-log.md` entry as context, executing the scan procedure (§4). The
evaluation (§5) may run in the same session or a follow-up, but the 48h
clock starts at draft time either way.

**What it produces:**
1. A new entry appended to `docs/design/frontier-log.md` (entry number =
   previous + 1), following the §7 format, with F-numbers pre-assigned from
   the global sequence. Draft evaluations may ship in the entry and be
   upgraded to full evaluations within the 48h SLA.
2. A short report to the coordinator: findings count, any `P0-CANDIDATE`
   flags, any `WATCH` triggers that fired, next scan date.

**How it files findings:** append-only writes to `docs/design/frontier-log.md`
only. It never edits the survey, the log's past entries, `native.id`, the
bench harness, or any other file.

**Guardrails (non-negotiable, restated for the job):**
- Prepaid/free providers and local inference only. Never touch
  keys, credentials, or secrets.
- Additive files only: `docs/design/frontier-log.md` appends (and, if the
  process spec itself must change, `docs/design/frontier-loop.md` — by
  coordinator approval, never silently).
- Git hygiene: `git pull --rebase origin main` before push; **never
  force-push**; commit only the log file
  (`frontier: log entry #N (weekly scan YYYY-MM-DD)`); on rebase conflict,
  abort and report — never resolve by discarding others' work.
- A failed scan still logs: append the entry noting the failure and the
  blocker, so the cadence is visible.

**Installation (coordinator action):** create the scheduled job per the
runtime's scheduler with the schedule above, pointing at this spec. The
spec author (this subagent) did not install anything.

---

*Process established 2026-09-11. First scan: `frontier-log.md` entry #1
(F25–F34). Next weekly scan due 2026-09-18.*
