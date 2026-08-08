# ward — WASM runtime in Duo

WASM runtime written in Duo, measured against `~/x/wart` (the Zig reference) and
`wasmtime`. Lives at `ext/ward` inside the duo repo since 2026-08-08; it used to
be `~/x/ward`.

Read `HANDOFF.md` before anything else. It carries the measured state and the
bug lore, and it is the file to update when a number changes.

## Dependency

Requires the `duo` compiler from the enclosing repo:

```bash
cd ~/x/duo && zig build -Doptimize=ReleaseFast   # -> zig-out/bin/duo
```

## What actually builds

**`src/ward.duo` is the whole runtime** — 4584 lines, self-contained, pure Duo,
zero `@c.emit`. Its only `req` is `std.jit`.

```bash
duo compile src/ward.duo --backend=c --emit exe -o /tmp/ward   # ~30 s
```

It reads **`WARD_WASM`, not argv** — duo-compiled binaries do not populate Lua's
`arg`. Passing a module as an argument measures nothing; this has faked two
whole benchmark sweeps.

```bash
WARD_WASM=<abs path> WARD_INVOKE=<export> WARD_ENGINE=jit|interp /tmp/ward
```

`WARD_INVOKE` defaults to `run`. `WARD_DUMP=<path>` dumps the emitted JIT words;
`WARD_PHASES=1` prints read/walk/alloc/compile timings.

## What does NOT build

`src/wasm/*.duo` (1406 code lines) and `test/main.duo` are **dead code**.
Nothing requires them; the modules they depend on (`src/main.duo`,
`src/cli.duo`, `src/wasm/runtime.duo`, `src/wasm/init.duo`, `src/lib.duo`) were
deleted. `test/main.duo` does not even parse. The README's source layout
describes that deleted architecture and is historical.

Do not delete `src/wasm/jit_arm64.duo` without reading HANDOFF first — it is the
only surviving copy of the virtual-stack register-allocating JIT, which is a
better code generator than the one that ships.

## Harnesses — every claim comes from one of these

```bash
duo run bench/verify.duo      # correctness vs wasmtime; the oracle
duo run bench/wart.duo        # ward vs wart, generated kernels, Pass 101 §4
duo run bench/derived.duo     # derived-lines / total-lines ratio
duo run bench/run.duo         # coverage sweep + per-engine timing
duo run bench/perf.duo        # interleaved median wall clock vs wasmtime
```

All of them take `WARD_BIN` (default `/tmp/ward`). `bench/run.duo` builds ward;
the others expect it to exist.

## Opcode numbers are PROJECTED — never type one

```bash
duo run tools/opcodes.duo                     # rewrite the derived regions
WARD_DERIVE_CHECK=1 duo run tools/opcodes.duo # gate: fail if ward.duo drifted
```

`tools/opcodes.duo` is the descriptor. It writes four
`-- derived(ward.opcodes.*)` regions in `src/ward.duo`: the `OP_*` constants,
the `OP_NAMES` diagnostic table, and the JIT's `ALU_OPS` / `CMP_OPS`. **Do not
edit inside a derived region** — add a row to the descriptor and re-project.

It is answerable to duo's canonical table: it re-parses
`lib/std/wasm/ward_mvp_opcodes.duo` and refuses to project on any disagreement
over the 63 opcodes that file holds. ward needs 184, which is the only reason
an extension table exists here at all.

Before this landed, the same opcode number was typed by hand in the
interpreter ladder AND again in the JIT emitter tables — 241 predicates, which
is exactly the drift the 2026-08-06 handoff warned against.

## Rules this project learned the hard way

- **"ward produced a result" is NOT coverage.** A harness that counted any
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
  enforces a `JIT_FLOOR` under `WARD_ENGINE=jit` for exactly this reason.
- **Never quote ward's printed `seconds=`** for a perf claim: it is `os.clock`,
  which on macOS accumulates CPU across threads. Use an interleaved harness.
- **Positive-control every zero**, and negative-control every oracle. A gate that
  cannot fail is not evidence.

## Monoglot

`.duo` only. No new `.zig`, `.c`, `.sh`, or `.py` under `ext/ward`. `.wasm`/
`.wat` fixtures in `bench/` are inputs, not source.
