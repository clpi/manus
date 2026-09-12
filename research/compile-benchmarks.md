# Compile benchmark report: `idol check` across `lib/`

Date: 2026-09-04 PDT

This note records the final findings from the `lib/*.id` compile-check benchmark and follow-up profiling pass. It is intended to let another developer reproduce the run, read the slow-file results without opening the raw artifacts, and decide where to investigate next.

## Scope

- Repository benchmarked: `/Users/clp/work/idol`
- Development worktree reported by `tools/node/dev/orient`: `/Users/clp/work/idol`
- Requested report path: `~/x/idol/research/compile-benchmarks.md`
- Benchmark source set: every file matched by `sorted(Path(repo / "lib").rglob("*.id"))`
- Files checked: 270
- Repeats: 3 runs per file, one fresh `idol` process per run
- Total process runs: 810
- Slow-set definition: slowest 10% by per-file median elapsed time, rounded up to 27 files

## Commands used

Benchmark driver:

```sh
cd /Users/clp/work/idol
./tools/node/dev/idol-lock -- \
  python3 /Users/clp/.hermes/kanban/workspaces/t_f6bca87379cc/bench_idol_check_lib.py \
    --repo /Users/clp/work/idol \
    --out-dir /Users/clp/.hermes/kanban/workspaces/t_f6bca87379cc/benchmark-results/full \
    --repeats 3 \
    --timeout 60
```

Per-file command template used by the driver:

```sh
./zig-out/bin/idol check <lib-relative-file>
```

Slow-set phase probe:

```sh
cd /Users/clp/work/idol
./tools/node/dev/idol-lock -- <phase-probe-driver>
IDOL_PHASE_PROFILE=1 <instrumented-debug-idol> check <lib-relative-file>
```

The phase probe used a scratch git worktree under the Kanban workspace. Its compiler source was modified only to emit `IDOL_PHASE_PROFILE` rows around these regions: `read_source`, `lexer_dispatch`, `parse_module`, `sem.check_module`, `contractScanModule`, `conversion_law`, and `HomeLoaderCtx.load`. It was built as a Debug-class compiler to match the parent benchmark's binary class.

Additional observations came from:

- 8 randomized round-robin phase repeats over the 27 slow files (216 process runs).
- 3 home-alias probe repeats over the 27 slow files (81 process runs).
- Built-in `--trace` samples for representative files (`parser`, `token_view`, `shader`, `arm64check`).

## Date and environment notes

- Benchmark date: 2026-09-04 PDT.
- Machine: `mm.local`, Darwin `25.5.0`, `arm64`.
- Parent benchmark repository HEAD at benchmark start: `a94d71262211ca0bf5992449c9056557f43ce334` (`a94d7126`).
- `tools/node/dev/orient` at report-write time reported HEAD `b1e9e4e1`, branch `main`, dirty entries `0`.
- Parent benchmark binary: `/Users/clp/work/idol/zig-out/bin/idol`.
- Parent benchmark binary sha256: `419646c051a9e4ab65aaf75c071ff66d749c668a132152363d06b0913594a7ee`.
- Phase probe binary sha256: `43f71975f0b29e98615b6933add7b43752cb6dec6e4eaaec2926c9bfd33ffe1a`.
- Upstream caveat from the benchmark handoff: after the benchmark, the main repo advanced to `b1e9e4e1`, changing only `src/lexer_tokenize.c`; the checked `lib/*.id` set remained 270 files and the live `zig-out/bin/idol` hash still matched the benchmark binary.

## Timing method

The benchmark script measured wall-clock elapsed time using Python `time.perf_counter()` around `subprocess.run([idol, "check", file], cwd=repo)`. Each timing is therefore a whole-process `idol check` time, not just compiler-internal work. That distinction matters: the profiling pass found a near-constant Debug process/CLI floor around 25 ms for successful files.

For each file, the aggregate reports median, best, mean, max, stable exit status, and final stderr-derived error/warning counts. Failures were retained rather than filtered out.

## Timing summary

| Metric | Value |
| --- | ---: |
| Files checked | 270 |
| Process runs | 810 |
| Repeats per file | 3 |
| Stable success files | 230 |
| Stable failure files | 40 |
| Timeout files | 0 |
| Median of per-file medians | 26.336 ms |
| P90 per-file median | 31.345 ms |
| P95 per-file median | 33.791 ms |
| Slowest per-file median | 101.054 ms |
| Slowest 10% count | 27 |

Exit-status distribution:

| Exit tuple across 3 repeats | File count |
| --- | ---: |
| `(0, 0, 0)` | 230 |
| `(1, 1, 1)` | 40 |

The highest file-level timing was stable: `lib/compiler/parser.id` measured best/median/max of 100.571/101.054/102.028 ms in the parent benchmark. In the 8-run phase probe, `parser.id` had one high outlier at 122.49 ms, but its median stayed near 100.16 ms. No broad cold-start pattern appeared in the randomized round-robin probe.

## Slowest 10% table

The `prior median` columns are from the original 3-run benchmark. The `probe outer` and phase columns are from the 8-run instrumented probe. `home load` is inclusive inside `sema`; do not add those columns as independent phases. `local sema` is `sema - home load`.

| Rank | File | Prior median ms | Status | Probe outer ms | Parse ms | Sema ms | Home load ms | Local sema ms | Bottleneck category | Main observed homes / notes |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| 1 | `lib/compiler/parser.id` | 101.05 | 0 | 100.16 | 12.68 | 54.82 | 28.38 | 26.44 | mixed parser, home load, local sema | `token` 12.01 ms, `lexer` 11.15 ms, `token.grammarrole` 4.69 ms; 2,631 lines / ~13.4K rough tokens |
| 2 | `lib/compiler/token_view.id` | 52.59 | 0 | 53.11 | 0.22 | 27.16 | 26.57 | 0.59 | foreign-home dependency load | tiny local file; `token` 11.69 ms, `lexer` 10.59 ms, `token.grammarrole` 4.62 ms |
| 3 | `lib/compiler/graph.id` | 51.30 | 0 | 49.79 | 0.55 | 23.09 | 22.11 | 0.98 | foreign-home dependency load | `token` 11.61 ms, `lexer` 10.48 ms |
| 4 | `lib/compiler/bind.id` | 50.74 | 0 | 51.05 | 0.76 | 24.12 | 22.22 | 1.90 | foreign-home dependency load | `token` 11.59 ms, `lexer` 10.67 ms |
| 5 | `lib/graphics/shader.id` | 48.28 | 0, 8e/9w | 50.11 | 23.18 | 0.65 | 0.06 | 0.59 | parser/tokenization of local source | WGSL-like brace payloads in interpolating strings; parse recovery dominates |
| 6 | `lib/compiler/lexer.id` | 45.04 | 0 | 44.38 | 6.59 | 8.72 | 2.05 | 6.67 | mixed local parse/sema | 1,221 lines / ~7.7K rough tokens; `mem` home about 2.13 ms |
| 7 | `lib/compiler/arm64check.id` | 42.45 | 1, 3e/24w | 40.75 | 1.42 | 19.44 | 17.24 | 2.20 | failure path: cross-home sema + diagnostics | broad fanout: `meta`, `string`, `compiler.arm64`, `table`, `result`, and others before failure |
| 8 | `lib/compiler/token.id` | 42.20 | 0 | 42.18 | 9.50 | 5.31 | 0.00 | 5.31 | parser/tokenization of local source | no observed homes; 1,094 lines / ~3.6K rough tokens |
| 9 | `lib/graphics/audio.id` | 38.16 | 1, 3e/21w | 38.97 | 1.74 | 17.16 | 14.98 | 2.18 | failure path: cross-home sema + diagnostics | `meta` 6.49 ms, `string` 2.44 ms, `table` 2.02 ms, `result` 1.62 ms, `iter` 1.31 ms |
| 10 | `lib/ml/deploy.id` | 36.71 | 1, 3e/19w | 39.15 | 0.67 | 18.76 | 17.80 | 0.96 | failure path: cross-home sema + diagnostics | `meta`, `string`, `ml.quant`, `table`, `result`, `iter`, `math`, `ml.device`, and others |
| 11 | `lib/meta.id` | 36.05 | 0, 0e/9w | 37.52 | 5.61 | 4.60 | 0.00 | 4.60 | parser/tokenization of local source | no homes; 1,005 lines / ~5.7K rough tokens |
| 12 | `lib/ml/rnn.id` | 34.24 | 0 | 34.46 | 1.73 | 7.10 | 4.50 | 2.60 | process/startup floor plus tensor home | `ml.tensor` 4.56 ms |
| 13 | `lib/meta/derive.id` | 34.15 | 0, 0e/9w | 34.92 | 0.60 | 9.08 | 6.57 | 2.51 | foreign-home dependency load | `meta` about 6.66 ms |
| 14 | `lib/db.id` | 33.97 | 0, 0e/10w | 34.21 | 2.33 | 5.68 | 2.57 | 3.10 | process/startup floor | `sqlite` 2.58 ms; `q` negligible |
| 15 | `lib/agent.id` | 33.58 | 0, 2e/3w | 30.25 | 3.71 | 0.71 | 0.00 | 0.71 | parser/tokenization of local source | small local diagnostic/recovery component; no homes |
| 16 | `lib/check.id` | 33.01 | 0, 0e/4w | 30.29 | 2.16 | 2.00 | 0.00 | 2.00 | parser/tokenization of local source | no homes; compiler work under process floor |
| 17 | `lib/ml/tensor.id` | 32.54 | 0 | 33.54 | 3.21 | 3.58 | 0.00 | 3.58 | process/startup floor plus local size | no homes; 563 lines / ~4.1K rough tokens |
| 18 | `lib/meta/codegen.id` | 32.33 | 0, 1e/13w | 34.82 | 1.44 | 7.41 | 6.62 | 0.79 | foreign-home dependency load | `meta` about 6.61 ms |
| 19 | `lib/graphics/postprocess.id` | 32.31 | 0, 0e/2w | 34.31 | 1.93 | 6.24 | 4.26 | 1.98 | process/startup floor plus small home fanout | `image`, `config`, `color`, `original` |
| 20 | `lib/contracts.id` | 32.27 | 0, 0e/2w | 33.42 | 3.46 | 3.26 | 0.00 | 3.26 | parser/tokenization of local source | no homes; threshold-near |
| 21 | `lib/ml/attention.id` | 32.26 | 0 | 34.18 | 1.68 | 6.75 | 4.47 | 2.27 | process/startup floor plus tensor home | `ml.tensor` 4.50 ms |
| 22 | `lib/ml/norm.id` | 32.15 | 0 | 33.63 | 1.47 | 6.48 | 4.58 | 1.90 | process/startup floor plus tensor home | `ml.tensor` 4.52 ms; `variance`, `mean`, `ml` negligible |
| 23 | `lib/ml/conv.id` | 32.06 | 0 | 33.76 | 1.45 | 6.35 | 4.52 | 1.84 | process/startup floor plus tensor home | `ml.tensor` 4.43 ms |
| 24 | `lib/graphics/mesh.id` | 31.87 | 0 | 32.89 | 2.90 | 3.34 | 0.00 | 3.34 | process/startup floor | no homes; 614 lines / ~3.7K rough tokens |
| 25 | `lib/compiler/arm64.id` | 31.61 | 0, 0e/2w | 30.15 | 1.74 | 1.88 | 0.00 | 1.88 | process/startup floor | no homes; compiler work well below process floor |
| 26 | `lib/argparse.id` | 31.60 | 0, 0e/14w | 28.25 | 1.22 | 1.04 | 0.00 | 1.04 | parser/tokenization of local source | no homes; threshold-near with warnings |
| 27 | `lib/crypto/signature.id` | 31.49 | 0, 0e/6w | 31.30 | 1.55 | 3.60 | 2.24 | 1.35 | process/startup floor plus small home fanout | `crypto` 1.87 ms, `crypto.rand` 0.38 ms |

## Profiling observations

### 1. Process/CLI floor is material

Successful one-file checks have a near-constant Debug process/CLI floor of about 25.19 ms. This explains many files clustered just above the p90 threshold. Several files in the slowest 10% have only 3-10 ms of measured compiler work; their wall time is dominated by starting a fresh process and running the CLI path.

This benchmark intentionally timed one fresh process per file. That is useful for user-facing `idol check <file>` latency, but it overstates the marginal compiler cost of checking another file inside an already-running compiler.

### 2. Foreign-home loading dominates tiny compiler adapter files

`token_view.id`, `graph.id`, and `bind.id` are small local files, but they load compiler homes inside sema. The repeated home loads explain their rank:

- `token_view.id`: 36 lines, local sema about 0.59 ms, but home load about 26.57 ms.
- `graph.id`: local sema about 0.98 ms, home load about 22.11 ms.
- `bind.id`: local sema about 1.90 ms, home load about 22.22 ms.

The recurring homes are `token`, `lexer`, and `token.grammarrole`. Because the benchmark starts a new process for every checked file, no cross-file cache can amortize those loads.

### 3. `parser.id` is a real local outlier

`lib/compiler/parser.id` is not just process floor or dependency load. It is 111 KB, 2,631 lines, and roughly 13.4K tokens. The phase probe measured about 74.56 ms of parse+check work after the process/CLI floor is excluded. Sema inclusive was about 54.82 ms, of which about 28.38 ms was home loading and about 26.44 ms was local sema. Parse-module was about 12.68 ms and lexer dispatch about 6.48 ms.

That makes `parser.id` the strongest candidate for deeper sema instrumentation once home caching and process floor are isolated.

### 4. Shader parsing and diagnostic recovery are a separate shape

`lib/graphics/shader.id` exits 0 but records eight errors and nine warnings in the check output. The probe shows parse-module dominates at about 23.18 ms, with only about 0.06 ms of home load. Built-in trace confirmed the time is inside parse+sema while stderr shows expected-expression and string-interpolation brace diagnostics.

Likely cause: WGSL-like brace-heavy shader payloads in interpolating strings trigger interpolation-hole scanning and parser diagnostic recovery. This should be investigated separately from normal successful-source check latency.

### 5. Failure-path files mix sema, home loading, and diagnostics

`lib/compiler/arm64check.id`, `lib/graphics/audio.id`, and `lib/ml/deploy.id` all exit 1 consistently. Their timings include work done before diagnostics plus the diagnostic path itself. Each has broad home fanout and sizable sema time before failure:

- `arm64check.id`: sema about 19.44 ms, home load about 17.24 ms.
- `audio.id`: sema about 17.16 ms, home load about 14.98 ms.
- `deploy.id`: sema about 18.76 ms, home load about 17.80 ms.

These are not apples-to-apples with clean success files. They should be tracked as a failure/diagnostic cluster.

### 6. ML files share `ml.tensor` home cost

`rnn.id`, `attention.id`, `norm.id`, and `conv.id` all load `ml.tensor`, costing about 4.4-4.6 ms. Their total wall time is mostly the 25 ms process floor plus that shared tensor home and a few milliseconds of local parse/sema. `tensor.id` itself has no observed home loads and is mostly local source size.

### 7. Conversion law and contract scan are not current bottlenecks

The instrumentation found `conversion_law` generally in the single-digit microsecond range across the slow set. `contract_scan` is sub-millisecond except for `parser.id`, where it is still only about 0.30 ms. Neither should be prioritized from this benchmark.

## Bottleneck categories

| Category | Count | Files |
| --- | ---: | --- |
| Process/startup floor | 10 | `lib/ml/rnn.id`, `lib/db.id`, `lib/ml/tensor.id`, `lib/graphics/postprocess.id`, `lib/ml/attention.id`, `lib/ml/norm.id`, `lib/ml/conv.id`, `lib/graphics/mesh.id`, `lib/compiler/arm64.id`, `lib/crypto/signature.id` |
| Parser/tokenization of local source | 7 | `lib/graphics/shader.id`, `lib/compiler/token.id`, `lib/meta.id`, `lib/agent.id`, `lib/check.id`, `lib/contracts.id`, `lib/argparse.id` |
| Foreign-home dependency load | 5 | `lib/compiler/token_view.id`, `lib/compiler/graph.id`, `lib/compiler/bind.id`, `lib/meta/derive.id`, `lib/meta/codegen.id` |
| Failure path: cross-home sema + diagnostics | 3 | `lib/compiler/arm64check.id`, `lib/graphics/audio.id`, `lib/ml/deploy.id` |
| Mixed parser + home + local sema | 2 | `lib/compiler/parser.id`, `lib/compiler/lexer.id` |

## Caveats

- The parent benchmark timed whole-process invocations. It should be read as current `idol check <file>` latency, not a pure compiler-phase profile.
- The phase probe compiler was intentionally instrumented in a scratch worktree and was not a production compiler change. It was built Debug-class to match the parent benchmark class, but its binary hash differs because it emits phase rows.
- Home-load time is included in sema-check time. Tables report both sema inclusive and home-load time; local sema is computed by subtracting home-load time.
- Failure rows exit before the normal parse-and-check-total emission. Their phase rows remain useful, but the process-rest column includes early-exit and diagnostic effects.
- The run covered the `lib/*.id` files present at the benchmark HEAD. The handoff revalidated that the `lib/*.id` set remained 270 after the repo advanced to `b1e9e4e1`.
- Some successful rows still report warnings or parser diagnostics. For performance triage, those should not be mixed blindly with warning-free success files.

## Suggested next investigations and optimizations

1. Prototype an in-process `lib` batch-check command or daemonized checker, then rerun the same 27 files. This isolates the roughly 25 ms process/CLI floor from true compiler work.
2. Cache parsed/checked foreign homes within a process. Expected biggest wins are `token_view.id`, `graph.id`, `bind.id`, `parser.id`, ML files, and meta adapter files.
3. If `parser.id` remains slow after home caching and batch execution, split `sem.check_module` timing around `check_block`, `check_expr`, relation/application handling, and foreign-home boundary registration. Current evidence says `parser.id` still has about 26 ms of local sema after excluding homes, but not which sema arm owns it.
4. Treat diagnostic-heavy and failure-path files separately from normal check performance. `shader.id` is parse/diagnostic-recovery dominated, while `arm64check.id`, `audio.id`, and `deploy.id` fail after loading many homes.
5. Add a cache-effect benchmark matrix: cold fresh-process, warm fresh-process, in-process batch with no home cache, and in-process batch with home cache. That would distinguish OS cache effects, compiler cache effects, and CLI/process overhead.
6. Keep the benchmark driver and aggregate schema as the reproducible baseline for future optimizer claims. Any claim should name the binary hash, repo HEAD, source-file census, and command line.

## Kept intermediate result files

Durable Kanban attachments from task `t_05cb584e`:

- `/Users/clp/.hermes/kanban/attachments/t_05cb584e/idol-check-lib-aggregate.json`
- `/Users/clp/.hermes/kanban/attachments/t_05cb584e/idol-check-lib-runs.jsonl`
- `/Users/clp/.hermes/kanban/attachments/t_05cb584e/idol-check-lib-methodology.json`
- `/Users/clp/.hermes/kanban/attachments/t_05cb584e/idol-check-lib-slowest-10pct.csv`
- `/Users/clp/.hermes/kanban/attachments/t_05cb584e/idol-check-lib-summary.md`
- `/Users/clp/.hermes/kanban/attachments/t_05cb584e/bench_idol_check_lib.py`

Durable Kanban attachments from task `t_44c380b5`:

- `/Users/clp/.hermes/kanban/attachments/t_44c380b5/slowest-lib-bottleneck-profile.md`
- `/Users/clp/.hermes/kanban/attachments/t_44c380b5/slowest-lib-bottleneck-classification.json`
- `/Users/clp/.hermes/kanban/attachments/t_44c380b5/phase-profile-summary.json`
- `/Users/clp/.hermes/kanban/attachments/t_44c380b5/phase-profile-summary.csv`
- `/Users/clp/.hermes/kanban/attachments/t_44c380b5/phase-profile-runs.jsonl`
- `/Users/clp/.hermes/kanban/attachments/t_44c380b5/home-alias-summary.json`
- `/Users/clp/.hermes/kanban/attachments/t_44c380b5/home-alias-runs.jsonl`
- `/Users/clp/.hermes/kanban/attachments/t_44c380b5/builtin-trace-samples.txt`

Original scratch-workspace paths recorded in the handoffs, if still present:

- `/Users/clp/.hermes/kanban/workspaces/t_f6bca87379cc/benchmark-results/full/`
- `/Users/clp/.hermes/kanban/workspaces/t_f6bca87379cc/phase-profile-results-debug/`
- `/Users/clp/.hermes/kanban/workspaces/t_f6bca87379cc/phase-profile-results-alias/`
