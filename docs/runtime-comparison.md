# ward against wart, wasmtime and wasmer

**Instrument:** `scripts/runtime_bench.id` · **Run it:** `zig build runtime-bench`
**Measured:** 2026-08-08, aarch64-macos (Darwin 25.5.0)
**Opponents:** wart `ad10076` (3 files dirty) · wasmtime v47.0.3 · wasmer
**duo repo:** `0e4eb29`

The claim this file exists to test is that ward is more performant than the
other WebAssembly runtimes available here, end to end. Before `runtime_bench`
nothing in this repository measured ward against anything but ward. That did not
make the claim weak; it made it **unmade**. This is the instrument, and this is
the first reading it produced.

**The headline, stated the way the numbers actually support it:** ward wins
decisively on the two axes that are about *size* — binary bytes and resident
memory — and on cold startup. On *execution* it is roughly at parity with wart
and wasmtime across the corpus, winning some rows and losing others, with one
row (`s-loopf64`) where it is consistently about twice as slow. It does not
dominate on execution and this document does not say it does.

---

## What is measured

| axis | how |
|---|---|
| `loc` | tracked source lines of the runtime, via `git ls-files` |
| `bytes` | size of the built binary |
| `startup` | process start to first answer on a module whose whole body prints `hi` |
| `rss` | peak resident set from `/usr/bin/time -l` on that same module |
| `exec` | wall time per workload, best of 5 |

Four runtimes: **ward** (`tools/wasm`, Duo), **wart** (`~/x/wart`, Zig, read-only —
it is the reference implementation ward was written against), **wasmtime**
v47.0.3, **wasmer**.

### Provenance is recorded, because it was not before

The report prints **wart's git revision and dirty-file count** on every run, and
warns when either the revision is unreadable or the tree is dirty. This is not
ceremony. `tools/wasm/bench/run.id:103` resolves wart through `$WART` or
`$HOME/x/wart` with no revision recorded at all, so **no number ever published
from that harness can say which wart it beat**. A comparison whose opponent
cannot be identified is not reproducible.

These numbers are against wart `ad10076`, which is the tip carrying
`perf(jit): compile WebAssembly SIMD to NEON on arm64`, the f64 JIT support and
the operand-stack fixes. Any ward-vs-wart figure taken before that commit is
stale, and wart's f64 row in particular moved.

**Building wart:** its `CLAUDE.md` documents `zig build -Doptimize=ReleaseFast`,
which **fails on current zig master** (`build.zig:275` passes
`preferred_optimize_mode`). Use `zig build -Drelease=true` with `--cache-dir`
and `--prefix` pointing outside the repo; `~/x/wart` is read-only here.

---

## Honesty controls, and why there are four of them

`CLAUDE.md` §3 records what this repository's benchmark suite did for months: it
reported "Duo beats C" on fabrication. Three kernels returned frozen literal
answers when the argument matched the benchmark, seven computed the benchmark's
own constants, and **three separate harness defects hid all of it** — a float
comparator that compared magnitudes so a sign flip differed by zero, a fail flag
that could not hold a value, and a timing collector that never seeded its
minimum.

Every control in `runtime_bench` exists because one of those three actually
happened here, and the report refuses to print a table if any control fails:

1. **The timer has units.** A 0.25 s sleep must measure to 0.25 s. "Non-zero" is
   not the test — a monotonically increasing garbage counter passes that and
   fails this one.
2. **The harness floor is measured and published.** Every timed cell forks a
   shell; that constant is reported (typically 4–8 ms) and **never subtracted**.
   Subtracting a noisy constant from a noisy measurement is how a benchmark
   starts printing negative times.
3. **The comparator discriminates.** Equal answers compare equal, differing
   answers compare unequal, the one tolerated normalization fires on the pair it
   was written for, and it does *not* fire on a near miss (`1` vs `4294967295`).
4. **ward's stdout trailer strip is real** — not a no-op, and not something that
   removed the answer along with the trailer.

And the ordering is fixed: **answers are verified across all four runtimes
before anything is timed.** A runtime that is fast and wrong is not fast. If any
answer disagrees, no timing table is printed at all.

### The one normalization, stated plainly

ward prints an i32 result **unsigned**; wasmtime prints it **signed**. On
`hash2b` ward says `3285959272` where wasmtime says `-1009008024` — the same 32
bits. The harness accepts two integers differing by exactly 2^32, marks that
cell `wrap` rather than `ok`, and rejects everything else. It is the only
difference tolerated anywhere in the table.

---

## Workload inventory

Every `.wasm` in both benchmark trees is enumerated and either measured or
accounted for. Nothing is silently skipped.

| tree | count | measured | why the rest are not |
|---|---:|---:|---|
| `benchmarks/wasm_rt/scaled` | 6 | 6 | — |
| `benchmarks/wasm_rt` | 21 | 4 | WASI-shape probes (`a b c d1 f1`–`f5 g jitable`) and unscaled duplicates of the scaled six |
| `benchmarks/wasm_rt/conform` | 89 | 0 | spec conformance fixtures — a correctness corpus, not workloads |
| `tools/wasm/bench` | 45 | 3 | the rest are 57–354 byte JIT and opcode fixtures |

**13 workloads measured**, in two entry families:

- **`start`** (10) — WASI command modules. All four runtimes qualify; the answer
  is stdout.
- **`invoke`** (3) — modules exporting `run` with no `_start`, from ward's own
  bench corpus. Only ward and wasmtime can reach them.

### Why two runtimes are `n/a` on the invoke family

Not a skip, and it does not count as agreement:

- **wart** has no invoke flag in its CLI. `wart run --invoke run f.wasm` reads
  `--invoke` as the *filename* and exits 1.
- **wasmer**'s `--invoke` exits 118 on these modules.

---

## Results, 2026-08-08

### Size axes — ward wins these outright

```
runtime         whole      core   files   language
ward             8519      8124      14   duo
wart           107311     92817     120   zig
wasmtime          n/a       n/a     n/a   upstream source is not vendored here
wasmer            n/a       n/a     n/a   upstream source is not vendored here

runtime             bytes      size
ward               262712    256.6K
wart              2044600   1996.7K
wasmtime         49641488  48478.0K
wasmer          175792160 171672.0K
```

**Read the caveat before quoting these.** `loc` and `bytes` are *not*
like-for-like. wart's tree carries a CLI, a package manager, WIT tooling, OCI
container packaging, an interactive shell and an AOT pipeline that ward has no
counterpart for; wasmtime and wasmer ship one binary holding an optimizing
compiler and a package client. That is why a **core** column exists — the module
subtree that actually executes WebAssembly on each side — and the core row is
the one to quote: **8,124 Duo lines against 92,817 Zig lines, 11.4×**. It is
still not a perfect match. It is honest about not being one.

The `bytes` axis has no comparable correction available, so read it as what it
is: ward's shipped binary is **7.8× smaller than wart's** and **189× smaller
than wasmtime's**, on binaries that do not carry the same feature sets.

### startup and rss — ward wins these too

```
runtime         startup  over floor         rss
ward             0.0061      0.0025      976.0K
wart             0.0069      0.0033     3056.0K
wasmtime         0.0096      0.0061     9664.0K
wasmer           0.0245      0.0209    36352.0K
```

`rss` is the cleanest win in the whole report and the least caveated:
**ward at 960 K against wasmtime's 9.7 MB and wasmer's 36.8 MB** — 10× and 38×.
Startup is a genuine win but a narrow one, and the 4 ms harness floor is a large
share of it, so it should be quoted as "comparable to wart, ahead of wasmtime"
rather than as a multiple.

### Execution — parity, with one real loss

Against freshly built wart `ad10076` (best of 5), on the quietest run obtained
— harness floor 3.6 ms:

```
workload          ward      wart  wasmtime    wasmer    spread   vs best  verdict
min             0.0066    0.0066    0.0084    0.0182    0.0005       99%  tie floor
tiny            0.0091    0.0071    0.0089    0.0204    0.0006      126%  loss floor
hot             0.0167    0.0159    0.0155    0.0260    0.0013      107%  loss
hotbig          0.1333    0.1319    0.1075    0.1186    0.0403      124%  loss noisy
s-brtable       0.0856    0.0921    0.1005    0.1127    0.0012       92%  win
s-calls         0.0217    0.0210    0.0206    0.0322    0.0048      105%  tie noisy
s-fib           0.0067    0.0077    0.0090    0.0201    0.0007       87%  win floor
s-loopf64       0.0273    0.0199    0.0143    0.0267    0.0848      190%  loss noisy
s-loopi32       0.0074    0.0076    0.0097    0.0222    0.0005       97%  tie floor
s-memory        0.0210    0.0202    0.0221    0.0337    0.0022      104%  tie
w-hash          0.3721       n/a    0.3782       n/a    0.0152       98%  tie
w-hash2b        3.9598       n/a    3.8037       n/a    0.4543      104%  tie
w-fib           0.0158       n/a    0.0185       n/a    0.0048       85%  win noisy

wins 3 · losses 4 · ties 6
runtime bench: PASS — 5 of 13 rows were clean enough to ratchet, none regressed
```

`vs best` is ward's time as a percentage of the **fastest other runtime** on
that row. Within 5% either way is a tie.

Two flags mark rows that **should not be quoted as results**:

- **`floor`** — the shell-spawn floor is over a quarter of the cell, so the
  ratio is dragged toward 100% by the harness, not by either runtime.
- **`noisy`** — ward's own slowest-minus-fastest sample exceeds a fifth of its
  time, so run-to-run variation rivals the number being compared.

### Startup rows are not throughput rows

`min`, `tiny`, `hot`, `s-fib` and `s-loopi32` finish in 6–20 ms against a 4–8 ms
shell-fork floor. They are measuring **process start and module load**, not any
JIT's steady state, and the harness flags them `floor` for exactly that reason.
Do not quote them as execution results and do not conflate them with the
throughput rows in one column. The only true steady-state row in this corpus is
**`w-hash2b` at ~4 s**; `hotbig` and `s-brtable` at 0.1 s are intermediate.

### The ranked worklist

This is the useful half of the report. Across five full runs the stable entries:

| workload | ward vs best | notes |
|---|---:|---|
| `s-loopf64` | **155–201%** | the largest consistent loss, reproducing in every run. f64 loop arithmetic. **This is the row to work on.** |
| `hotbig` | 112–159% | real, frequently un-flagged; ward trails wasmtime on a sustained i32 loop |
| `tiny` / `min` | 125–140% | `floor`-flagged; startup rows, ratio largely an artifact |
| `w-hash2b` | 92–111% | the true throughput row; ward is at parity with wasmtime |
| `s-calls`, `hot`, `w-hash` | 99–114% | in or near the tie band, moving run to run |

**`s-loopf64` is the finding.** It reproduces at 180–201% in every run, and it
still reproduces against wart `ad10076` — the revision that just *added* f64 JIT
support, which moved wart from 0.0239 s to 0.0147 s on that row and widened the
gap rather than closing it. ward runs f64 loop arithmetic at roughly half the
speed of both wart and wasmtime.

**`w-hash2b` is the reassuring one.** On the only workload long enough to be
measuring steady-state execution rather than process startup, ward is at parity
with wasmtime (92–111% across runs). Ward's problem is not throughput in
general; it is f64.

---

## What fails the gate

**A regression against the baselines recorded in `scripts/runtime_bench.id`
— not a loss to another runtime.** ward loses rows today; making that fail the
gate would make it red on day one for reasons nobody can act on in one sitting,
and it would be switched off within a week. A gate nobody runs measures nothing.

**Only unflagged rows can fail it.** A row the report has just flagged `floor` or
`noisy` is a row it has said should not be quoted — it cannot then be allowed to
fail the gate four lines later. Regressions on flagged rows are printed and not
counted. This was not a theoretical concern: between two runs twenty minutes
apart the harness floor doubled from 4 ms to 7 ms and three rows went red
without ward changing at all.

**And a run where nothing was eligible reports `INCONCLUSIVE`, not `PASS`.** If
every row is flagged, the machine was too busy for the measurement to mean
anything, and a gate that checked nothing must not come out green.

- Baselines: the **worst** best-of-5 ward produced across four full runs on
  2026-08-08 — not a single quiet reading, which fires the moment somebody else
  starts a build.
- Tolerance: `BENCH_SLACK`, default **40** percent.
- Also override: `BENCH_RUNS` (default 5), `BENCH_BASELINE` (a file of
  `name ns` lines replacing the embedded table), `DUO_WASM_BIN`, `WART_BIN`,
  `WART_ROOT`.

**Why 40 and not 25.** Half these rows finish in under 10 ms and every cell
carries a 4–8 ms shell fork, so a 25% band on `s-fib` is about 1.5 ms — well
inside what this machine varies by between runs minutes apart. The rows where
40% is still a real constraint are `hotbig` and `w-hash2b`. The rows flagged
`floor` are exactly the rows this paragraph is about.

Improvements are also reported: a cell more than 30% under its baseline prints
`improved … lower it here`. Lowering a baseline when a number improves is the
other half of a ratchet and the half usually skipped.

## What this instrument does not do

- **It does not build ward.** A benchmark that builds its own subject reports
  the build. It prints the binary's timestamp, and warns when `tools/wasm/src` is
  dirty in the working tree, so a stale measurement announces itself.
- **It does not subtract the harness floor** from any published number.
- **It measures whole-process wall time**, so every cell includes process
  startup. For a runtime whose selling point is startup that is the right
  choice, but it means the short rows are not measuring the interpreter.
- **It has no in-process timing** and therefore cannot separate compile time
  from execution time inside a runtime.
- **wasmtime is the oracle** for every answer. If wasmtime is wrong about a
  module, this table is wrong with it.

## Reproducing

```bash
zig build runtime-bench                 # default: 5 runs, 40% slack
BENCH_RUNS=9 zig build runtime-bench    # quieter numbers, slower
BENCH_SLACK=0 zig build runtime-bench   # strict ratchet against the baseline
```

Roughly 300 process spawns and about two minutes, dominated by `w-hash2b` at
~4 s per sample. It is deliberately **not** part of `zig build test` or
`agent-smoke`.
