# wart in the duo toolchain — the classification decision, measured

**Filed:** 2026-08-08 · **Status:** assessment, no code moved · **Gap:** gap[072]

The owner wants wart to be part of the duon toolchain and ward to be provably
more performant than wart and every other WASM runtime, end to end. This
document measures what that costs and what it can honestly claim today.

Nothing here was taken on a label. Every number below has the command that
produced it, and two long-standing beliefs in the session notes turned out to
be false when checked.

---

## 0. The two headline findings, before the options

### 0.1 wart builds and runs on this machine. The SIGILL note is stale.

The standing note says wart's ARM64 JIT emits `ldp xzr,xzr,[sp],#16`, SIGILLs on
ARM64 macOS, and that no local wart baseline exists. **All three are false as of
2026-08-08.** A clean ReleaseFast build from source, cache and prefix outside
the repo:

```
$ cd ~/x/wart
$ zig build -Drelease=true --cache-dir <scratch>/wartcache -p <scratch>/wartout
BUILD_EXIT=0     # zero lines of output
$ <scratch>/wartout/bin/wart version
0.1.0
```

The documented command in `~/x/wart/CLAUDE.md` — `zig build
-Doptimize=ReleaseFast` — **fails** on the current zig master
(`0.17.0-dev.1099+7db2ef610`): wart's `build.zig:275` passes
`preferred_optimize_mode`, which makes zig expose `-Drelease=[bool]` instead of
`-Doptimize`. That is a stale doc line, not a broken build, and it is the most
likely reason a previous session concluded wart could not be built here.

The JIT runs and is correct:

```
$ wart -V 1 -j run hot_big.wasm
   JIT enabled: true
arm64 JIT initialized
2331661441
```

`2331661441` is the same value wasmtime, wasmer, and ward produce. Verified by
value, not by exit status.

### 0.2 wart's JIT is ON BY DEFAULT, so `-j` is a no-op and every published "wart interpreter" number is mislabeled

`src/config/types.zig:25` reads `jit: bool = true`. There is no `--no-jit` flag
in `src/cmd.zig`, and a `wart.toml` with `jit = false` in the working directory
is not picked up (verified: `-V 1` still prints `JIT: true`). So:

- `wart run <mod>` already JITs.
- `wart -j run <mod>` is the same run.
- The two rows I first recorded as "wart-interp 1.36s" and "wart-jit 1.37s" are
  **the same configuration measured twice**, and their agreement is not evidence
  the JIT does nothing — it is evidence I could not turn it off.

Any ward-vs-wart table that has ever carried a "wart interpreter" column is
reporting wart's JIT under an interpreter's name. `tools/wasm/bench/run.duo:87`
also still special-cases exit status 132 (`128+SIGILL`) as wart's expected
failure mode; that arm is now dead code guarding a condition that does not
occur.

---

## 1. The measurement: five runtimes, one kernel, verified by value

Kernel: `benchmarks/wasm_rt/hot.c` with the loop bound raised to 1e9, compiled
`clang --target=wasm32-wasip1 -O1 -fno-unroll-loops` (wasi-sdk 33). i32
multiply-add in a loop with locals only — the shape both JITs claim to cover.

**Positive control first**, because a kernel the compiler folded away measures
process startup and nothing else. Doubling the loop bound must roughly double
the time:

```
n=500000000  wasmtime real=0.52s  val=1888162433
n=1000000000 wasmtime real=1.19s  val=3725993217
```

It does. (An earlier attempt at `-O2` with n=2e9 ran in 0.26s — LLVM had
strength-reduced the loop. That run is discarded; it was measuring nothing.)

Best-of-N wall clock at n=1e9. **All five runtimes return `3725993217`.**

| runtime | best wall | vs wasmtime |
|---|---|---|
| wasmtime | **1.05 s** | 1.00× |
| wasmer | 1.21 s | 1.15× |
| **ward** (Duo, `engine=jit-arm64`) | **1.32 s** | 1.26× |
| wart (JIT, default) | 1.36 s | 1.30× |
| wart (`-j`, same config) | 1.37 s | 1.30× |

And the number that says ward's JIT is real and load-bearing:

| ward configuration | wall | self-reported |
|---|---|---|
| `engine=jit-arm64` (default) | 1.32 s | `seconds=1.314667` |
| `DUO_WASM_ENGINE=interp` | 43.04 s | `seconds=38.625673` |

**29× from ward's own ARM64 JIT.** That is not a fallback; that is the product.

At a smaller size (`benchmarks/wasm_rt/hot_big.wasm`, ~0.12 s, all five agree on
`2331661441`) the ordering is the same and the spread is inside process-startup
noise: wasmtime 0.10, wasmer 0.11, wart 0.12, ward 0.13.

### What the dominance claim can and cannot say today

**Can say, with evidence:**
- ward computes the same answer as wasmtime, wasmer, and wart on this kernel.
- ward is **3% faster than wart** on it (1.32 vs 1.36).
- ward's JIT delivers 29× over its own interpreter.

**Cannot say:**
- "ward is more performant than wart" as a general claim. One kernel, one shape,
  a 3% margin — that is inside the range a different `-O` flag would move.
- "…and all other WASM runtimes." ward is **26% slower than wasmtime** and 9%
  slower than wasmer on the same kernel. It is currently last of the five.
- Anything about a wart *interpreter*, because §0.2 says that configuration is
  not reachable from the CLI.
- Anything end-to-end. `duo run tools/wasm/src/engine.duo` spends **65.8 s
  compiling** before it runs anything; only the compiled `engine.out` binary is a
  runtime measurement. A harness that times `duo run` is timing the Duo
  compiler.

The honest one-line claim available today: *on a 1e9-iteration i32 kernel,
verified by value against three independent runtimes, ward is within 3% of wart
and within 26% of wasmtime, on an ARM64 JIT written in Duo.* That is a good
claim. It is not the claim that was asked for, and the gap is measurable rather
than rhetorical.

---

## 2. The census arithmetic — it is three failing rows, not one

The brief anticipated one red row. Measured, it is three.

Today (`zig build language-census`, exit 0):

```
duo   824   zig 237   lua 41   c/h 25   sh/py 0   js 2
PASS (sh/py 0 <= 0, js 2 <= 2, zig 237 <= 237)
```

wart's tracked population — **422 files**, and `third_party/` is fetched, not
tracked (1 tracked file: `spec-lock.json`), so the pinned spec suites do not
come with it:

```
182 zig · 45 md · 44 wat · 29 wast · 21 sh · 18 wasm · 17 c · 8 yml · 1 py · 1 js · …
```

Copied in as-is under `ext/wart/`, `language_census.duo` goes red on **three**
ratchets:

| row | today | with wart | ratchet | result |
|---|---|---|---|---|
| zig | 237 | **419** | `CENSUS_ZIG_CEILING=237` | **FAIL** |
| sh/py | 0 | **22** | `CENSUS_FLOOR=0` | **FAIL** |
| js | 2 | **3** | `CENSUS_JS_FLOOR=2` | **FAIL** |
| c/h | 25 | 42 | none (reported only) | passes |
| duo | 824 | 824 | — | wart has no `.duo` |

The sh/py row is the sharpest. It reached zero on 2026-08-08 — that day —
`CENSUS_FLOOR` was lowered to 0 in the same commit, and the census header says
"There is no headroom left to spend and that is the point." Importing wart puts
21 shell scripts and one Python script back. That is not a ceiling being raised;
it is a row that reached its stated target being un-reached on the next commit.

### The mechanism the brief is looking for already exists

`docs/spec/foreign.md` + `scripts/foreign_census.duo` (`zig build
foreign-census`, Pass 105 U8) already implements exactly "classified oracle, not
debt". Two classes, no silent default:

| class | meaning | requires |
|---|---|---|
| `ledger` | bootstrap debt; shrinks | `until:` a termination condition |
| `oracle` | test equipment; never on the shipping path; may persist | `license:` the authority granting it |

Existing oracle rows already cite `license:pass103-§5`, including
`oracle benchmarks/ … performance baselines; the foreign compiler is the
referee`. **wart is that sentence.** One rule line —

```
oracle   ext/wart/   license:pass103-§5 — the reference WASM runtime Ward is measured against
```

— classifies every wart file that enters the foreign population (the census
selects by extension, so the `.md`/`.wat`/`.wasm` files never enter it at all),
leaves `unclassified` at 2, and `foreign-census` stays green. One line.

**So the two gates disagree, and that is the whole decision.** `foreign-census`
is class-aware and already says yes. `language-census` is extension-only, has
never heard of `foreign.md`, and says no three times. Bringing wart in-tree is
not a request to raise a ceiling; it is a request to decide whether the debt
counter should learn about classes.

---

## 3. What ward lacks that wart has

wart: **182 tracked `.zig`, 121,283 lines** (107,311 under `src/`, 12,777 under
`test/`). ward: **29 `.duo`, 11,350 lines**, of which `src/ward.duo` alone is
6,312. wart is **10.7× ward's line count**, not the 1,000× that
`tools/wasm/README.md` claims.

> `tools/wasm/README.md` opens with "Reimplements wart (~1.3M lines of Zig) in
> ~1,500 lines of Duo". Measured: 121,283 and 11,350. Both figures are wrong by
> about an order of magnitude and they are wrong in the flattering direction.
> The comparison table under them ("Binary size ~8MB vs <1MB", "Startup ~5ms vs
> <1ms") carries no measurement either. This is a CLAUDE.md §3 problem sitting
> in the first paragraph of the runtime's front page, and it should be fixed
> before anything about wart's classification is decided — the 10.7× ratio is a
> genuinely strong result and does not need inflating.

The JIT, specifically:

| | lines |
|---|---|
| `src/wasm/jit_compile.zig` | 18,184 |
| `src/wasm/jit_arm64.zig` | 12,654 |
| `src/wasm/jit_x64.zig` | 3,556 |
| `src/wasm/jit_x64_engine.zig` | 606 |
| `src/jit_arm64_tests.zig` | 33 |
| **total** | **35,033** (29% of all wart Zig) |

ward's equivalent: `src/wasm/jit_arm64.duo` 701 + `src/wasm/jit.duo` 119 = 820
lines, ARM64 only. And ward's ARM64 JIT is 29× its interpreter (§1), so the
small number is not a stub.

Beyond the JIT, grepped against `src/ward.duo` (6,312 lines) — **zero hits each**
for component, thread, atomic, exception, `gc.`, multi_memory, tail_call,
memory64, relaxed:

| capability | wart | ward |
|---|---|---|
| Component model + WIT | `component.zig` 3,361 · `component_binary.zig` 3,090 · `component_linker.zig` 1,492 · `component_types.zig` · `wit.zig` | absent |
| WASI P2 / P3 | `wasi_preview2.zig` · `wasi/preview2.zig` · `wasi/preview3.zig` · `cli/http/sockets/clocks/random/poll/nn` | `wasi.duo`, 285 lines, P1 |
| threads + atomics | `threads.zig` 1,949 | absent |
| exceptions, GC, multi-memory, memory64, tail-call, relaxed-SIMD | present (and pinned suites for each) | absent |
| AOT | `aot.zig` 1,710 | `aot.duo` — **10 lines, `compile()` returns `""`** |
| x86-64 JIT | 4,162 lines | absent (ARM64 only) |
| spec conformance runner | `conformance/spectest.zig` 2,171 + 17 pinned suites | `test/conform.duo` 480 |
| packaging (OCI, registry, manifest) | `pack.zig` · `manifest.zig` · `container` · `deploy` | absent |

wart is also **actively developed by cloud sessions**: `~/x/wart` is on `main`
with three uncommitted files (`src/util/fmt.zig`, `src/wasm/jit_arm64.zig`,
`src/wasm/runtime.zig`), and `HEAD` is `ad10076 perf(jit): compile WebAssembly
SIMD to NEON on arm64 (232 opcodes)`. Whatever classification is chosen has to
survive a repo that moves under it.

---

## 4. The four options, costed

### Option 1 — in-tree, classified `oracle`

Add `ext/wart/` with one `foreign.md` rule; teach `language_census.duo` to
subtract oracle-classified files from the debt rows (or add a separate `oracle`
row the way `lua` is separate).

- **Cost:** `language_census.duo` must consult `foreign.md`, which today it
  deliberately does not — the two gates were split so a classification failure
  and a debt-count failure stay distinguishable. Coupling them is a real
  regression in that property.
- **Cost:** the argument "an oracle is not debt" must survive 21 shell scripts.
  wart's `.sh` files are `bench.sh`, `docker.sh`, `examples/build-*.sh` — build
  and demo scripts, not differential equipment. Classifying them `oracle` to
  keep a row green is the "giving one of them a rule without changing what it
  IS" failure `foreign.md` names explicitly in its own closing paragraph.
- **Cost:** 460 MB working tree, 29 MB `.git`.
- **Buys:** one `zig build` reaches both runtimes. Atomic ward+wart commits. The
  dominance harness stops depending on a path outside the repo.

### Option 2 — in-tree as ordinary `zig`, row → 419

- **Cost:** destroys G9's meaning. The zig row's termination condition is "the
  ledger shrinks to zero as the self-hosting matrix advances". An oracle never
  shrinks to zero, so the row can never be satisfied and the ratchet becomes
  decoration. `foreign.md` would also need a `ledger ext/wart/ until:…` row —
  and there is no honest `until:` to write.
- **Cost:** still red on sh/py and js.
- **Buys:** honesty about file counts, at the price of the number meaning
  anything.

### Option 3 — submodule at `ext/wart`

`.gitmodules` already carries seven (`ext/duo.nvim`, `ext/duo.el`,
`ext/duo.vim`, `ext/duo-lsp`, `ext/vscode-duo`, `ext/zed-duo`,
`ext/tree-sitter-duo`), so the pattern is established and the tooling exists.

- **Zero census impact, and this is a fact not a loophole:** every census here
  runs on `git ls-files`, and a submodule contributes exactly one gitlink entry
  with no extension. All three ratchets stay green with no gate changed.
- **Buys:** a pinned SHA — the dominance harness names a commit instead of
  "whatever is in `~/x/wart` today", which is the actual reproducibility
  problem. Full history. `zig build` can drive it.
- **Cost:** "part of the toolchain" means version-locked and buildable from a
  duo checkout, not co-committed. A ward change and the wart commit it is
  measured against land in two commits, not one.
- **Cost:** the CLAUDE.md argument for keeping ward's oracle out of tree — "an
  oracle should not share a repo with the thing it validates" — is *weakened*,
  not answered. A submodule is closer than a sibling directory.

### Option 4 — stay separate; only the harness reaches across

- **Cost:** the status quo, which is what produced this document's two false
  beliefs. `tools/wasm/bench/run.duo:103` resolves wart through
  `$WART` / `$HOME/x/wart/zig-out/bin/wart` — an unpinned path to an
  uncommitted working tree. There is no commit anywhere recording which wart a
  ward number was measured against.
- **Buys:** nothing changes, and the oracle-separation argument stays intact.

---

## 5. Recommendation — Option 3, submodule at `ext/wart`

Pin wart as a submodule. Do not change any census. Then do the three things that
actually block the dominance claim, none of which need wart's files in-tree:

1. **Fix `tools/wasm/README.md`.** 1.3M → 121,283; 1,500 → 11,350. The real 10.7×
   is a better number than a fabricated 1,000×, and §3's line is the first thing
   a reader sees.
2. **Retire the SIGILL arm** in `tools/wasm/bench/run.duo:87` and the
   "wart interpreter" column everywhere it appears. wart JITs by default
   (§0.2); a column labelled interpreter that reports a JIT is a §3 violation
   already shipped.
3. **Make the harness pin.** Record the wart submodule SHA in every emitted
   table. A ward-vs-wart number without a wart commit is not reproducible, and
   that is true whether wart lives in-tree, in a submodule, or next door.

**Why 3 over 1**, given that Option 1 is what "part of the toolchain" most
naturally means: the thing preventing a credible dominance claim today is not
that wart lives in another directory. It is that (a) nobody records *which* wart
a number came from, (b) the runtime being compared was mislabeled, and (c) the
comparison is one kernel wide. A submodule fixes (a) outright and costs nothing
against any gate. Options 1 and 2 fix none of (a)(b)(c) and each spend a ratchet
to do it.

### The strongest argument against my own recommendation

**A submodule is the shape that lets the wart baseline rot, and it is the shape
CLAUDE.md's own reasoning predicts will rot.** CLAUDE.md justifies pulling
`duo-lsp`/`duo-mcp` in-tree precisely because they version-lock to the compiler
and out-of-tree "that surfaces when someone next runs the MCP server; in tree it
is caught by duo's gates on the commit that changes lowering." A pinned SHA
updates when someone remembers to update it. wart is under active cloud-session
development — `ad10076` landed 232 NEON SIMD opcodes — so a pin left alone for a
month is a comparison against a runtime nobody uses, and it will still print a
confident number. In-tree, a wart that stops building breaks the commit that
broke it. That is a real advantage and my recommendation gives it up.

There is a second, sharper form of it: if the owner's goal is that wart *is* part
of the duon toolchain, then the census rows are measuring the wrong thing and
should be told so, rather than routed around. A gate that a correct architectural
decision has to dodge is a gate with a bug. My answer is that this is true but
premature — the sh/py row hit zero on the same day, and the first use of that
argument should not be the commit that puts 21 shell scripts back. Revisit
Option 1 once wart's own `.sh`/`.py`/`.js` are gone or classified on their own
merits, at which point Option 1 costs one ceiling instead of three and the
argument is clean.

---

## 6. Reproducing every number here

```bash
# wart builds (cache/prefix outside the repo; ~/x/wart is READ-ONLY)
cd ~/x/wart && zig build -Drelease=true --cache-dir /tmp/wc -p /tmp/wo   # NOT -Doptimize

# the kernel + its positive control
sed 's/60000000u/1000000000u/' ~/x/duo/benchmarks/wasm_rt/hot.c > /tmp/k.c
$(mise where wasi-sdk)/wasi-sdk/bin/clang --target=wasm32-wasip1 -O1 \
    -fno-unroll-loops -o /tmp/k.wasm /tmp/k.c
# halve the bound; the time must halve, or the loop was folded and the run is void

# five runtimes, all must print 3725993217
wasmtime /tmp/k.wasm
wasmer run /tmp/k.wasm
~/x/wart/zig-out/bin/wart run /tmp/k.wasm        # already JITs — see §0.2
duo compile tools/wasm/src/engine.duo -o /tmp/engine.out   # ~66s; do NOT time `duo run`
DUO_WASM_MODULE=/tmp/k.wasm DUO_WASM_INVOKE=_start /tmp/engine.out
DUO_WASM_ENGINE=interp DUO_WASM_MODULE=/tmp/k.wasm DUO_WASM_INVOKE=_start /tmp/engine.out   # 43s

# the census arithmetic
zig build language-census
cd ~/x/wart && git ls-files | sed 's/.*\.//' | sort | uniq -c | sort -rn
```

Two traps that cost time here, recorded so they cost nobody else any:
`duo run <script>` drops a `<script>.out` binary in the repo root (repo-hygiene
forbids root artifacts — move it or delete it), and `{ /usr/bin/time -p cmd >f
2>/dev/null; }` silently discards the timing, because `time` writes to the same
stderr. Both produced confident empty results before they were caught.
