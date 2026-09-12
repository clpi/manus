# Establishing "literal optimum" for Idol benchmarks

## Why this document exists

The Idol project wants to claim, for some benchmarks, that the compiler
**exceeds the literal optimum** — i.e. beats the best code that could
possibly be written. That claim is paradoxical on its face: if you beat
the optimum, your optimum wasn't optimal. This document defines the
methodology that makes the claim *falsifiable* instead of rhetorical:

1. How a "literal optimum" (the oracle) is established per benchmark.
2. What it means — and what must happen — when Idol beats the oracle.
3. The statistical protocol that decides "beats", and how it extends
   across platforms.

## 1. Levels of optimum

An oracle is always versioned (`bench/oracle/<prog>.s`, `<prog>.md`
with the optimality argument). Four levels, weakest to strongest:

**L1 — Idiom ceiling.** The best output of a production compiler
(`clang -O3`, `gcc -O3`) on the same source. This is a *practical*
optimum, not a literal one: it measures "beats the industry", and the
existing suite already reports it. It must never be called "literal
optimum".

**L2 — Hand-written oracle assembly.** An expert writes what they
believe is the optimal instruction sequence for the benchmark's hot
loop, with a written argument: instruction count, data-dependency
critical path, port/retire pressure on the target microarchitecture.
Reviewed by a second person. Versioned. This is the *candidate*
literal optimum.

**L3 — Superoptimizer bound.** Exhaustive (or equality-saturation)
search over instruction sequences up to length N proves no shorter
sequence is *equivalent* on the target ISA semantics. Establishes
optimality **within the bound** (length ≤ N, no exotic instructions).
The bound is part of the claim: "optimal among sequences of ≤ N
instructions".

**L4 — Lower-bound proof.** An analytic or machine-checked lower bound:
e.g. the loop-carried dependency chain forces ≥ k cycles/iteration on
any implementation, and the oracle achieves k. When an L4 bound holds,
"exceeds optimum" is *impossible by proof* — beating the oracle then
means the bound's assumptions were wrong (new information!), which is
reported as a correction to the bound, not as a marketing claim.

The project's use of "literal optimum" means **L2 at minimum, L3/L4
where claimed**. An L1-only comparison is reported as "beats clang",
never as "exceeds optimum".

## 2. What "exceeds optimum" means — the protocol

Beating the oracle is treated as **falsifying the oracle first**:

1. **Freeze.** The Idol binary, the oracle binary, the machine, and the
   environment are frozen and disclosed (see §4).
2. **Re-run** under the statistical protocol (§3). The bar is
   Idol median < oracle median with p < 0.05, same as any win — plus
   the margin must exceed the measurement floor (§3.4).
3. **Default hypothesis: the oracle was not optimal.** The burden is
   on the claimant to find *why* — usually a missed instruction-level
   trick (a superoptimizer find, a better schedule, a microarchitectural
   effect like µop fusion the L2 author missed).
4. **Revise the oracle** to incorporate the finding, bump its version,
   re-run. The new oracle is the optimum again.
5. Only if the oracle **stands** — i.e. it carries an L3 bound covering
   the technique Idol used, or an L4 lower bound that Idol provably
   cannot violate yet empirically does (assumption hunt!) — may the
   claim "exceeds literal optimum" be published, with:
   - the oracle version and its optimality argument,
   - the technique Idol used that the bound missed,
   - a correction to the bound (this is the actual contribution).

In short: **"exceeds optimum" is never the end of the story; it is
always the start of a better optimum.** Any publication that stops at
step 2 is rejected by this methodology.

## 3. Statistical protocol (shared with bench/, extended)

The timing protocol is the one already enforced by `bench/timing.py`:

- **Correctness gate first.** Both binaries must produce identical
  observable behavior (exit code today; byte-slices in verify). A
  faster wrong answer is a bug, not a data point.
- **Warmup:** 3 untimed runs per binary (page faults, branch-predictor
  and cache warmup, frequency ramp).
- **Interleaving:** timed rounds run idol, oracle, idol, oracle, …
  so thermal drift, frequency scaling, and background load affect all
  competitors equally. No cherry-picked quiet window.
- **Rounds:** 21 minimum. Primary metric is the **median** (robust;
  no outlier removal). Also reported: mean, stddev, min, max, p95,
  and Tukey-fence outlier counts (disclosed, never dropped).
- **Significance:** Welch's t-test of Idol vs oracle, p < 0.05.
  Verdicts: `win` (Idol median lower, significant), `loss`, `tie`.
- **Margin:** reported on medians: `(oracle − idol) / oracle`.

### 3.1 What "beats" requires beyond p < 0.05

1. **The measurement floor.** If |margin| is below the run-to-run
   variation of the *oracle against itself* (A/A test: run the oracle
   binary twice through the protocol; the observed |margin| is the
   floor), the win is not claimed regardless of p-value. p-values
   detect *consistent* differences; the floor guards against
   *meaninglessly small* ones.
2. **No single-round heroics.** The win must reproduce on a fresh
   process invocation of the whole protocol (new `run.sh` run).
3. **Disassembly check.** The oracle and Idol hot loops are
   disassembled and the difference is explainable in ≤ 1 paragraph
   (fewer instructions, better schedule, fewer memory uops…).
   An unexplained win is a measurement artifact until explained.

### 3.2 Worked example: `arith`

Hot loop (per iteration): `x = x*3; x = x+7; x = x-2`, carried on `x`.

- **L4 sketch:** the three ALU ops form a single dependency chain on
  `x`; no iteration can retire faster than the chain latency. On
  Apple Silicon (wide, ~1-cycle integer ALU latency) the lower bound
  is ~3 cycles/iteration for the chain *as written*.
- **Where "exceeds" could honestly come from:** algebraic
  simplification *across* iterations is impossible (the chain is the
  semantics), but strength reduction (`*3` → `x + (x<<1)`, already in
  the compiler) shortens nothing latency-wise — it changes *which*
  ports are used, not the chain length. A genuine exceed would need,
  e.g., discovering that `x*3+7-2` ≡ `x*3+5` (constant folding across
  statements — a real, planned optimization), cutting the chain to 2.
  The L2 oracle must then be revised to the 2-cycle form; the claim
  becomes "Idol found the cross-statement fold", not magic.
- This is the template: every "exceeds" resolves to a *named
  technique* the oracle missed.

## 4. Cross-platform extension

Timing comparisons are **per-platform only**. Cycle counts and seconds
never cross machine boundaries.

- Each platform (see `bench/platforms/`) gets its **own oracle** —
  different ISAs have different optima. An x86_64 oracle is not the
  ARM64 oracle recompiled.
- Each platform's results disclose: CPU model, core count, OS build,
  SDK/toolchain versions, power settings (e.g. "plugged in, high
  power mode"), and the shim triple.
- Minimum rounds scale with timer granularity: 21 rounds at
  `perf_counter` resolution is the floor; platforms with coarser
  timers increase rounds until the oracle's A/A floor is stable.
- x86_64 note: prefer `perf_counter` (OS) over `rdtsc` (frequency
  scaling lies); document the choice.
- A claim made on one platform is *not* a claim about another. The
  per-platform table in RESULTS shows each platform's verdict
  independently.

## 5. Threats to validity (and mitigations)

| threat | mitigation |
|---|---|
| thermal throttling / frequency scaling | interleaved rounds; medians; disclose power settings |
| ASLR / code alignment effects | A/A floor test; note alignment-sensitive cases |
| background load | interleaving; Tukey outlier disclosure; re-run on suspicion |
| page-cache warmth (startup benchmarks) | cold-start protocol TBD: drop caches or reboot between rounds |
| oracle author blind spots | L2 review by second person; L3 superoptimizer cross-check |
| p-hacking (re-running until p<0.05) | fixed 21-round protocol; re-runs disclosed and counted |

## 6. Relationship to the skeptical suite

`bench/` tries to prove Idol is *not* the fastest and publishes every
loss. This document governs the opposite end: what it takes to claim
Idol is faster than *possible*. The two are consistent — both make
strong claims expensive. A win against clang is routine data; a win
against a versioned L2+ oracle triggers the §2 protocol, not a press
release.
