# ward — handoff (2026-08-05 ~03:15)

Session ended because the bash tool died (EAGAIN-on-fork / `ChildProcess.spawn`
exhaustion — `echo alive` returns exit 1 with no output). I caused it with runaway
background trace jobs; one emitted 2.1 GB. The repo's own mandate for this condition is
**hard stop, not a retry loop**. Everything below the "UNVERIFIED" line was written but
never compiled or run.

## Verified working (built + measured before the shell died)

Binary: `/tmp/w2`. Source at the matching commit is `src/ward.duo`.

ward is **exact against wasmtime on 5/5 workloads**:

| workload | ward | wasmtime | engine |
| --- | --- | --- | --- |
| hash.wasm (200M iters) | 1899277430 | 1899277430 | jit-arm64 |
| mix.wasm (clang -O2) | 3277377516 | 3277377516 | interp |
| t1.wat (rotl + select) | 2443361268 | 2443361268 | interp |
| t2.wat (mul/shr_u/xor loop) | 364022666 | 364022666 | jit-arm64 |
| t3.wat (full mix loop, 200k) | 4218537313 | 4218537313 | interp |

hash.wasm via the JIT: **0.49–0.51 s** vs wasmtime 0.41–0.55 s.
Also verified individually: `if`/`else`, `i32.clz`, `i32.popcnt`.

`src/ward.duo` is pure Duo — 0 `@c.emit` / `@c.include` / `__emit`, 0 `fun`, 0
`match`/`case`, 0 `then`/`do` in code (only in comments). C-level primitives come from
`lib/std/jit.duo`, where `__emit` is legitimate.

## UNVERIFIED — written but never compiled

1. **`br_table`, `i32.load8_s/8_u/16_s/16_u`, `i32.store8/16`.** A composite test
   (`/tmp/t4.wat`, expects 2413) returned 0. I was bisecting when the shell died.
2. **Forward end-scanner rewrite** (the `block`/`if` target scan). This is the likely
   cause of (1) and the fix is reasoned but untested: the old scanner skipped immediates
   only for opcodes present in `himm`, so it missed `local.get`/`local.tee` (decoded
   inline, deliberately absent from `himm`), `br_table` (variable length), memory ops
   (two LEBs), `call`, and the blocktype byte after a nested `block`/`loop`/`if`. Any
   unskipped operand byte is read as an opcode and the scan desyncs, giving the block a
   wrong branch target. The rewrite makes the skip opcode-aware.
   **`block`/`if` are only trustworthy for bodies with no immediates until this is
   verified** — which is why the simple `if`/`else` test passed while the composite failed.

**Next step:** rebuild, run the 5-workload matrix above for regressions, then bisect
`/tmp/t8.wat` (br_table alone) and `/tmp/t7.wat` (store8/load8_u alone).

## Not implemented (gap to wasmtime parity)

`call` / `call_indirect` (needs frame management; the one-function constraint below makes
this the awkward one), f32/f64, i64 ops, `memory.grow`/`size`, imports/WASI, traps,
component model. The JIT covers a narrower subset than the interpreter and falls back
automatically, so adding an opcode to the interpreter alone is always safe.

## Constraints that shape this code (do not "clean up" without reading)

- No `req "std.mem"`; `mem.*` is name-intercepted by codegen.
- Hot buffers must be **locals** — passing a pointer local to a `ptr` param emits
  `&local` and corrupts it. Hence one big function.
- A branch may not end on a void call (hence the `sp = sp` tails).
- Never use a named `const` as a `match` pattern; `match` is deprecated anyway — use
  `if`/`elseif`, which is also faster here.
- **Instrument with `io.stderr:write`, never `print`.** stdout is block-buffered and the
  trace is lost on a fault; this cost hours.

## Compiler fixes landed in ~/x/duo this session (all verified)

- **BUG C fixed** — `req` of a std module works again. Embedded-module functions were
  filtered by native-scalar eligibility in **three** places; the decisive gate was inside
  `emit_func_def`, which is why fixing only the two in `emit_embedded_module` did nothing.
- 64-bit variable shifts (`1 << sh` with sh >= 32 was wrapping to 32-bit). This is what
  let ward restore signed-LEB128 sign extension — `i32.const -1` is the byte `0x7F` and
  was decoding as 127, the cause of the last `mix.wasm` mismatch.
- `detect_sieve_native` tightened — it was replacing any 1-param `while`>`if`>`while`
  function body with a prime sieve, which silently turned ward's dispatch loop into a
  prime counter.
- Implicit Lua/Python-style entry points (top-level `return` in the `main` driver).
- `match`/`case` deprecation warning per pass3's 53->30 keyword target.
- `.expr_stmt`/`.call_stmt` capture-group build break (was blocking every agent).
