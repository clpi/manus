# ward — remaining opcode work, in execution order

Written blind (no shell) so a fresh session can execute mechanically. Every item lists
the stack effect and, where relevant, the ARM64 encoding, so no rediscovery is needed.
Verify each group against wasmtime before moving on — `wasmtime run --invoke run x.wasm`
prints a *signed* i32; compare against ward with `+ 2**32` when negative.

## 0. First: verify what is already written (blocks everything else)

`block`/`if` branch targets depend on the forward end-scanner in `src/ward.duo`. The
rewrite there is uncompiled. Until it is verified, **any** block containing an
immediate-carrying opcode may branch to the wrong place, which will look like a wrong
result in unrelated features.

- `/tmp/t8.wat` — `br_table` alone, expect 222
- `/tmp/t7.wat` — `store8`/`load8_u` alone, expect 171 (0xAB)
- `/tmp/t4.wat` — composite, expect 2413 (this is the one that returned 0)
- regression matrix: hash 1899277430, mix 3277377516, t1 2443361268, t2 364022666,
  t3 4218537313

## 1. i64 arithmetic (largest coverage win, nearly mechanical)

Mirrors the existing i32 group exactly, minus the `& M32` masking — i64 values already
occupy the full stack slot, so results need no truncation.

| op | code | effect |
| --- | --- | --- |
| i64.add/sub/mul | 0x7C/0x7D/0x7E | `a op b`, no mask |
| i64.and/or/xor | 0x83/0x84/0x85 | bitwise, no mask |
| i64.shl/shr_u/shr_s | 0x86/0x88/0x87 | shift by `b & 63` |
| i64.eqz | 0x50 | `a == 0` |
| i64.eq/ne | 0x51/0x52 | compare |
| i64.lt_s/gt_s/le_s/ge_s | 0x53/0x55/0x57/0x59 | signed |
| i64.lt_u/gt_u/le_u/ge_u | 0x54/0x56/0x58/0x5A | unsigned — compare as u64 |
| i64.const | 0x42 | signed LEB128, **no** `& M32` |

Care: `i64.mul` cannot use the i32 split-multiply — it needs the full 64-bit product,
which is what C `*` already gives. Unsigned i64 comparisons need care because Duo i64 is
signed; compare `(a < 0) ~= (b < 0)` first, then fall back to the signed compare.

## 2. Conversions / extends (cheap, unblocks mixed-width code)

`i32.wrap_i64` 0xA7 (`a & M32`), `i64.extend_i32_s` 0xAC (sign-extend from bit 31),
`i64.extend_i32_u` 0xAD (`a & M32`), `i32.extend8_s` 0xC0, `i32.extend16_s` 0xC1.

## 3. Remaining memory ops

`i64.load` 0x29, `i64.store` 0x37, and the i64 sub-word loads 0x30–0x35, plus
`i64.store8/16/32` 0x3C–0x3E. Same align+offset immediate pair as the i32 ones already
implemented. Also `memory.size` 0x3F / `memory.grow` 0x40 (one memidx byte; grow returns
old page count or -1).

## 4. `call` (0x10) — the architecturally awkward one

Needs a frame: save `sp`/`pc`/locals, run the callee body, restore. The pointer-local
constraint (a pointer local passed to a `ptr` param is emitted as `&local`, corrupting it)
means `run_body` cannot recurse through a helper taking the buffers. Two workable shapes:

- **Explicit frame stack inside `run_body`.** Keep `retpc`/`retsp`/`retlocals_base` arrays
  and a locals *region* (`lo` sized `frames * 64 * 8`), so a call pushes a frame and
  continues the same loop. No recursion, no pointers crossing a boundary. Recommended.
- Duo recursion on `run_body` itself, re-allocating buffers per call — simpler but
  allocates per call and loses the caller's linear memory unless `lin` is hoisted.

The decoder already locates function bodies (`find_run_body`); generalise it to return the
body offset for an arbitrary function index, which `call` needs.

## 5. f32/f64

Duo has native `float`. Stack slots are i64, so store bit patterns and convert at the op
boundary. `f64.const` 0x44 is 8 raw little-endian bytes (not LEB); `f32.const` 0x43 is 4.
Arithmetic 0xA0–0xA3 (f64 add/sub/mul/div), comparisons 0x61–0x66, and the
truncate/convert family 0xA8–0xB6.

## 6. Traps

`unreachable` 0x00 must trap, and `i32.div_s/rem_s` must trap on divide-by-zero and on
`INT_MIN / -1`. Currently these return -1 (the "unsupported" sentinel), which conflates a
trap with an unimplemented opcode — give traps a distinct return so the caller can report
them properly.

## 7. JIT parity

Each interpreter op above can be added to the JIT by appending one row to `ALU_OPS`
(opcode -> ARM64 base word) or `CMP_OPS` (opcode -> condition code). Useful encodings for
the i64 group: the same instructions with bit 31 set selects the 64-bit form
(e.g. ADD `0x0B000000` -> `0x8B000000`, SUB `0x4B000000` -> `0xCB000000`,
ORR `0x2A000000` -> `0xAA000000`, EOR `0x4A000000` -> `0xCA000000`,
AND `0x0A000000` -> `0x8A000000`, LSLV `0x1AC02000` -> `0x9AC02000`,
LSRV `0x1AC02400` -> `0x9AC02400`, MADD `0x1B007C00` -> `0x9B007C00`).

The JIT may lag the interpreter freely: `jit_compile` returns -1 on anything it cannot
emit and the caller falls back, so an opcode added only to the interpreter is always safe.

## Constraints (re-read before editing — each cost real time to find)

- No `req "std.mem"`; `mem.*` is name-intercepted by codegen.
- Hot buffers must be locals; a pointer local passed to a `ptr` param becomes `&local`.
- A branch may not end on a void call — hence the `sp = sp` tails.
- `|=` does not exist. `+=`/`-=`/`*=` do.
- A zero-arg function needs `fun`; with a typed param it can be bare (GR-001).
- Never use a named `const` as a `match` pattern — and `match` is deprecated; use
  `if`/`elseif`, which measured faster here anyway.
- Instrument with `io.stderr:write`, never `print` — stdout is block-buffered and the
  trace is lost on a fault.
