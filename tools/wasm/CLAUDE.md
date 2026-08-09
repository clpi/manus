# duon wasm — the toolchain's WebAssembly engine

WASM runtime written in Duo, measured against `~/x/wart` (the Zig reference) and
`wasmtime`. Lives at `tools/wasm` inside the duo repo since 2026-08-08; it used to
be `~/x/ward`.

Read `HANDOFF.md` before anything else. It carries the measured state and the
bug lore, and it is the file to update when a number changes.

## Dependency

Requires the `duo` compiler from the enclosing repo:

```bash
cd ~/x/duo && zig build -Doptimize=ReleaseFast   # -> zig-out/bin/duo
```

## What actually builds

**`src/engine.duo` is the whole runtime** — 4584 lines, self-contained, pure Duo,
zero `@c.emit`. Its only `req` is `std.jit`.

```bash
duo compile src/engine.duo --backend=c --emit exe -o /tmp/duowasm   # ~30 s
```

It reads **`DUO_WASM_MODULE`, not argv** — duo-compiled binaries do not populate Lua's
`arg`. Passing a module as an argument measures nothing; this has faked two
whole benchmark sweeps.

```bash
DUO_WASM_MODULE=<abs path> DUO_WASM_INVOKE=<export> DUO_WASM_ENGINE=jit|interp /tmp/duowasm
```

`DUO_WASM_INVOKE` defaults to `run`. `DUO_WASM_DUMP=<path>` dumps the emitted JIT words;
`DUO_WASM_PHASES=1` prints read/walk/alloc/compile timings; **`DUO_WASM_JIT_TRACE=1`
names the reason the JIT declined a body** — it declines silently otherwise and
`main` runs the interpreter without saying so, which is how `hot_big` stayed 30x
behind wasmtime while printing the right answer.

## The test suite

```bash
zig build wasm-test          # from the repo root — builds the engine, then runs:
duo run test/conform.duo     # from tools/wasm, against DUO_WASM_BIN (default /tmp/duowasm)
```

`test/conform.duo` runs every `.wasm` fixture under **both engines and both
entry shapes** and differences the answer against wasmtime **by value**. It
refuses to print a score until five controls pass (exit 3, not 1): both
binaries respond, the module path reaches the runtime, the comparator can
return a red, a perturbed module is refused, a missing module is refused.
Read `HANDOFF.md` for what it found on its first run.

Note `tools/wasm/test/` is covered by the ROOT `.gitignore`'s bare `test`
pattern, so files there need `git add -f`.

## What does NOT build

`src/wasm/*.duo` (1406 code lines) and `test/main.duo` are **dead code**.
Nothing requires them; the modules they depend on (`src/main.duo`,
`src/cli.duo`, `src/wasm/runtime.duo`, `src/wasm/init.duo`, `src/lib.duo`) were
deleted. `test/main.duo` does not even parse — `test/conform.duo` replaces it
as the suite. The README's source layout describes that deleted architecture and
is historical.

Do not delete `src/wasm/jit_arm64.duo` without reading HANDOFF first — it is the
only surviving copy of the virtual-stack register-allocating JIT, which is a
better code generator than the one that ships.

## Harnesses — every claim comes from one of these

```bash
duo run bench/verify.duo      # correctness vs wasmtime; the oracle
duo run bench/wart.duo        # the engine vs wart, generated kernels, Pass 101 §4
duo run bench/derived.duo     # derived-lines / total-lines ratio
duo run bench/run.duo         # coverage sweep + per-engine timing
duo run bench/perf.duo        # interleaved median wall clock vs wasmtime
duo run bench/six.duo         # the engine vs wart/wasmtime/wasmer/wasm3/iwasm
```

`bench/six.duo` VERIFIES before it times: a runtime that cannot be driven to an
export, or that disagrees with wasmtime, gets `n/a`/`WRONG` and is never given a
millisecond. It also records the CLI facts that produce bogus rows if ignored —
`wasm3` writes its result to stderr, `iwasm` prints hex with a `:i32` suffix,
and `wart run` can only enter `_start`.

All of them take `DUO_WASM_BIN` (default `/tmp/duowasm`). `bench/run.duo` builds the engine;
the others expect it to exist.

## Opcode numbers are PROJECTED — never type one

```bash
duo run tools/opcodes.duo                     # rewrite the derived regions
DUO_WASM_DERIVE=1 duo run tools/opcodes.duo # gate: fail if engine.duo drifted
```

`tools/opcodes.duo` is the descriptor. It writes four
`-- derived(wasm.opcodes.*)` regions in `src/engine.duo`: the `OP_*` constants,
the `OP_NAMES` diagnostic table, and the JIT's `ALU_OPS` / `CMP_OPS`. **Do not
edit inside a derived region** — add a row to the descriptor and re-project.

It is answerable to duo's canonical table: it re-parses
`lib/std/wasm/ward_mvp_opcodes.duo` and refuses to project on any disagreement
over the 63 opcodes that file holds. the engine needs 184, which is the only reason
an extension table exists here at all.

Before this landed, the same opcode number was typed by hand in the
interpreter ladder AND again in the JIT emitter tables — 241 predicates, which
is exactly the drift the 2026-08-06 handoff warned against.

## Rules this project learned the hard way

- **"the engine produced a result" is NOT coverage.** A harness that counted any
  non-sentinel result reported 8/18; differencing against wasmtime showed 2 were
  plain wrong. Only oracle agreement counts.
- **Every range arm needs a terminal `else return -1`.** `i32.div_s`/`rem_s`
  silently returned **0** for months because they fell into a range whose inner
  chain had no arm for them. An honest bail is cheap; "executes but wrong" is not.
- **`result=nan` usually means a missing opcode**, not bad arithmetic: `-1` bitcast
  through an f64 return is NaN.
- **A result wrong by a round power of two** is a hardcoded initialiser, not an
  arithmetic bug.
- **A binop returning its first operand** means the result write missed the slot.
- **The JIT falls back to the interpreter silently.** Correctness gates stay
  green while the JIT is dead. Check the `engine=` line, and `bench/verify.duo`
  enforces a `JIT_FLOOR` under `DUO_WASM_ENGINE=jit` for exactly this reason.
- **Never quote the engine's printed `seconds=`** for a perf claim: it is `os.clock`,
  which on macOS accumulates CPU across threads. Use an interleaved harness.
- **Positive-control every zero**, and negative-control every oracle. A gate that
  cannot fail is not evidence.
- **Linear memory is the module's DECLARED page count.** It used to be a fixed
  one page with every address masked `& 0xFFFF`, which FOLDED a two-page
  module's upper half onto its lower half: one fixture answered 792579638 for
  3674599702 and seven printed nothing at all while exiting 0. An out-of-range
  access must bail, never wrap.
- **A JIT refusal must name itself.** `DUO_WASM_JIT_TRACE=1`. Four separate
  refusals were stacked behind the first one on `hot_big`, and nothing could
  see past the first until they did.

## Monoglot

`.duo` only. No new `.zig`, `.c`, `.sh`, or `.py` under `tools/wasm`. `.wasm`/
`.wat` fixtures in `bench/` are inputs, not source.
