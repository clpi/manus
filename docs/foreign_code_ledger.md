# Foreign Code Elimination Ledger

> Required by **§9** of `docs/plans/duo_self_hosting_foundation.md`.
>
> Every non-Duo file or embedded-C region declares: role, authority, replacement,
> prerequisites, migration stage, deletion gate, status.
>
> **Rule: no deletion gate = architectural debt.**
>
> Inventory measured 2026-08-05. Counts are `@c.emit` sites unless stated otherwise.

## Authority classes (§1.1)

| class | meaning | permanence |
| --- | --- | --- |
| **A — bootstrap** | S0 and temporary backends | temporary; frozen after S1 viability |
| **B — foreign boundary** | OS / ABI / external libs | replaced by Duo descriptors + adapters |
| **C — differential reference** | validation only, non-authoritative | may persist; never authoritative |
| **D — disposable** | scripts, generators, migration tools | needs deletion condition or Duo replacement |

---

## ward — `~/x/ward`

Ward is specified as pure Duo. C-level primitives belong in duo's `lib/std/`, never here.
Every row below is therefore debt by construction.

| file | sites | class | role | replacement | deletion gate | status |
| --- | ---: | --- | --- | --- | --- | --- |
| `src/ward.duo` | **0** | — | interpreter + ARM64 JIT, the build that ships | — | n/a | **compliant** |
| `src/duo_lexer_tokenize.c` | 8952 lines | **A** | SH-03 bootstrap: the Duo lexer compiled to C, linked into the production binary so the compiler can tokenize with `lib/std/compiler/lexer.duo` | regenerate from `lib/std/compiler/host.duo`; deleted when a Duo-hosted compiler can build itself without a C stage | **S1 viability — the compiler no longer needs a C bootstrap** | **declared 2026-08-07** |
| `src/duo_keyword_classify.c` | 72 lines | **A** | SH-02 bootstrap: the keyword table compiled to C; declares its symbol `weak` so the SH-03 artifact's strong definition overrides it | superseded IN PLACE by `src/duo_lexer_tokenize.c`, which already provides the strong symbol | **delete once nothing links the weak fallback** — measurable today | **declared 2026-08-07; retirable** |
| `src/lexer.zig` | 1300 lines | **C** | SH-03 differential reference: no longer authoritative — `tokenizeAuthority()` returns `.duo_native` as of 2026-08-07. Retained because `src/duo_lexer_dispatch.zig` differentials the Duo token stream against it field for field on every test run | none needed; class C may persist | **never authoritative; delete when the differential is retired at S1 closure** | **declared 2026-08-07; non-authoritative** |
| `src/wasm/jit_arm64.duo` | **0** | — | ARM64 template JIT | — | n/a | **compliant** |
| `src/wasm/{op,wasi,simd,aot,jit,memory,stack,table,value}.duo` | **0** | — | C-free leaves | — | n/a | **compliant** |
| ~~`src/wasm/runtime.duo`~~ | ~~278~~ | — | dead tree | — | — | **DELETED 2026-08-07** |
| ~~`src/wasm/module.duo`~~ | ~~9~~ | — | dead tree | — | — | **DELETED 2026-08-07** |
| ~~`src/main.duo`~~ | ~~5~~ | — | dead entry, did not compile | — | — | **DELETED 2026-08-07** |
| ~~`src/wasm/interp_ward.duo`~~ | ~~1~~ | — | dead shim | — | — | **DELETED 2026-08-07** |
| ~~`src/wasm/jit_ward.duo`~~ | ~~1~~ | — | dead shim | — | — | **DELETED 2026-08-07** |

### `runtime.duo` split (the 275)

| region | sites | replacement | deletion gate | status |
| --- | ---: | --- | --- | --- |
| SIMD lane ops (added 2026-08-05) | **118** | `src/wasm/simd.duo` — written, descriptor-driven, ~90 opcodes from ~12 rows | (1) root-cause the codegen failure that bisects into `lane.get`; (2) wire into dispatch; (3) SIMD spot checks stay 4/4 | **blocked — replacement exists but inert** |
| interpreter core (pre-existing) | 157 | Duo over a native value substrate | S1 substrate (§7 phase 1) + representation IR | open |

**Note:** `jit_arm64.duo` is the existence proof that ward's hot path does not require C —
a full ARM64 template JIT with zero `@c.emit`. The 118-site SIMD block was written against
that precedent and violates it; it is the newest debt in the tree, not the oldest.

### RESOLVED 2026-08-07 — ward is 100% C-free; the dead tree is retired

All 294 `@c.emit` sites are **gone**. runtime.duo (278), module.duo (9),
main.duo (5), interp_ward.duo and jit_ward.duo (1 each) were removed along with
the entry/wrapper modules that required them. `src/` went from 28 tracked files
to 14, and `bench/verify.sh` is unchanged at 42 PASS / 0 wrong on both engines
with 34 modules JIT-compiled.

This had been recorded as blocked by a parallel session holding uncommitted
changes in `src/wasm/`. **That was too coarse.** Those three files —
`jit_arm64.duo`, `op.duo`, `wasi.duo` — carry ZERO `@c.` directives and require
only `std.*`; every C site was in a file nobody else was editing, and
`runtime.duo` depended on *them*, not the reverse. All three were left untouched.

The lesson: "the directory is blocked" was never true — only three files were,
and they were not the ones holding the debt. Check the actual file set before
concluding a cleanup is unreachable.

### Historical: ward has TWO parallel runtimes, and the C is all in the dead one

The `src/ward.duo` row previously read "2 sites". Both hits are inside **comments**
that assert *"Pure Duo: no @c.emit"* — a grep false positive. `src/ward.duo` contains
**zero** `@c.` directives of any kind. It is also the build that ships: 2978 lines,
interpreter + ARM64 JIT, verified 20 PASS / 0 wrong against a wasmtime oracle.

So ward carries two ~2900-line implementations of the same runtime:

| tree | entry | lines | `@c.emit` | verified |
|---|---|---:|---:|---|
| `src/ward.duo` | standalone | 2978 | **0** | **20/20 vs wasmtime** |
| `src/wasm/*.duo` | `src/main.duo` → `src.wasm` | 2890 | **275** | not exercised by `bench/verify.sh` |

**All of ward's C debt lives in the tree that does not ship.** Retiring `src/wasm/`
would delete every one of the 275 sites at a stroke and halve ward's line count —
but it is an architectural call about which entry point is canonical, not a cleanup,
so it needs an explicit decision rather than a unilateral delete.

### Perf reality check (2026-08-07)

`src/ward.duo`'s JIT covers **2 of 21** corpus modules (`hash`, `hash2b`); the other
19 fall back to the interpreter because `jit_compile` bails on op 16 (`call`). Every
ward-vs-wasmtime headline number to date was therefore measured on one of the only
two modules the JIT handles. ward still wins **2.3-2.6x** on startup-bound modules,
where its microsecond template-JIT compile beats Cranelift's milliseconds.

---

## duo — `~/x/duo`

| item | count | class | role | replacement | deletion gate | status |
| --- | ---: | --- | --- | --- | --- | --- |
| `src/*.zig` | **224 files** | **A** | S0 bootstrap compiler | S1 (§2) | S1 viability, then **freeze** | open |
| `lib/std/*.duo` with `@c.emit` | 10 files | **B** | OS/ABI primitives | permitted location per §1.1-B | remain until Duo has native syscall descriptors | **allowed** |
| `benchmarks/wasm_rt/conform/run_spec.py` | 1 | **C** | spec-conformance harness | Duo harness | non-authoritative; may persist | **allowed** |
| `benchmarks/wasm_rt/bench.c` | 1 | **C** | C baseline for differential timing | none — it *is* the reference | never deleted; comparison target | **allowed** |
| `scripts/*.sh` / `scripts/*.bash` | — | **D** | CI gates, build lock | Duo build system + `std.script` | per-script gate in `removal_ledger.zig` RL-07..RL-10 | **partial** — proof matrix + idiom gate Duo-native |

### S0 freeze status — **NOT ENFORCED**

§2 requires S0 to receive only correctness, reproducibility, and security fixes after S1
viability, with **no architectural evolution**. This is currently violated:

- `src/pass26_wiring.zig`, `src/pass26_descriptor_intern.zig`, `src/debug_trace.zig`,
  `src/sema.zig` are under active architectural change.
- The tree has not compiled for an extended period as a result
  (`hash_map has no member 'identity_context'`, `Scope has no member 'call'`,
  `local variable is never mutated`, plus `file contents changed during update`).

`pass16_self_hosted_compiler.md` contains **no mention** of the freeze, so nothing in the
execution plan enforces it. This is the highest-priority governance gap: an unbuildable S0
blocks every downstream item in this ledger, because replacements cannot be compiled or
tested.

---

## Summary

| | count |
| --- | ---: |
| ward `@c.emit` sites (all debt) | **0 — RETIRED 2026-08-07** |
| ...compliant modules | ALL of `src/` (14 files, zero `@c.` directives) |
| duo S0 Zig files (class A) | 224 |
| entries with a real deletion gate | ward SIMD, ward decoder, S0 |
| entries **without** a deletion gate | remaining `scripts/*.sh` not in `removal_ledger.zig` |

### Ordered by unblocking value

1. **Enforce the S0 freeze.** Nothing else in this ledger can progress while the bootstrap
   compiler does not build.
2. ~~Wire in `simd.duo`.~~ **Moot.** ward's C debt was retired wholesale on
   2026-08-07 by deleting the dead tree; the shipping `src/ward.duo` carries a
   descriptor-driven SIMD executor (30 opcodes from 30 rows) with no C at all.
3. **Slice/bytes substrate in `lib/std`.** Unblocks `module.duo` (9) and is §7 phase 1
   regardless.
4. **Give `scripts/*.sh` a deletion gate** or accept it as permanent class-D.

---

## Progress on gate #2 (wire in `simd.duo`) — 2026-08-05

Root-caused one blocker, found two more. The 118-site removal is **still blocked**, but the
obstacles are now specific rather than "codegen fails somewhere in `lane.get`".

### duo bug — any `std.bit` call from a `req`'d module fails C codegen

Reproduced with three different functions, so it is the call mechanism, not one function:

```duo
-- src/wasm/probe.duo
bit = req "std.bit"
p = {}
p.f = (v: any, w: i64): i64
  bit.popcount(w)      -- also: bit.set_bit, bit.extract -- all fail
end
p
```

`req "std.bit"` on its own is fine; the same calls work from a **top-level script**
(`bit.extract(0xFF00, 15, 8)` -> 255). Only a call from inside a module that is itself
`req`'d breaks. No diagnostic — just `C compiler failed`.

**Worked around** in `simd.duo` by inlining the two operations needed:

```duo
extract:  (half >> off) & ((1 << w) - 1)
insert:   (v.lo & (~(m << off))) | ((x & m) << off)
```

This removes the std.bit dependency entirely (0 residual refs) and is the reason the
module no longer needs a stdlib import at all.

### Blocker A — ROOT-CAUSED: *any* local referenced in a table-literal field

Minimal reproduction:

```duo
-- src/wasm/probe.duo  (a req'd module)
p = {}
p.g = (v: any, w: i64, i: i64, x: i64): any
  m: i64 = 15
  { lo = m, hi = 0 }        -- error: C compiler failed
end
p
```

Bisected precisely:

| construct | result |
| --- | --- |
| `{ lo = x, hi = v.hi }` (params only) | works |
| `{ lo = v.lo, hi = v.hi }` (field reads) | works |
| `m: i64 = 15` then `{ lo = m, hi = 0 }` | **fails** |
| `m: i64 = 15` then `{ lo = v.lo & m, ... }` | **fails** |
| `m = 15` (**untyped**) then `{ lo = m, hi = 0 }` | **fails** |
| `{ lo = v.lo & ((1 << w) - 1), hi = 0 }` (fully inlined) | works |

**Corrected root cause.** My first reading was "typed `i64` local", which is wrong —
untyped locals fail identically. The actual rule is that **any local variable referenced
in a table-literal field value** breaks C codegen. Only expressions built purely from
parameters and field reads survive.

It is not `~` (a two's-complement rewrite `(0 - m) - 1` fails identically), not the number
of `return` statements, not `any` field access, and not the local's type annotation. No
diagnostic — just `C compiler failed`.

This is very broad. "Compute intermediate values into locals, return them in a record" is
one of the most ordinary shapes in any language, so this likely affects a large fraction of
idiomatic Duo that returns aggregates.

### Blocker A — TRUE ROOT CAUSE: table-literal call sugar swallows the tail expression

**This supersedes both earlier readings** ("typed local in a table literal", then "any local
in a table literal", then "unterminated initializer"). All three were symptoms.

Lua permits `f{...}` as sugar for `f({...})`. Duo applies it **across a newline**, so a
bare table literal in tail position is parsed as a *call on the preceding expression*:

```duo
g = (x: i64): any
  m: i64 = 15
  { lo = m, hi = 0 }      -- parsed as  15{ lo = m, hi = 0 }  -- calling 15
end
```

which emits `lua_to_num(15(({ ... })))` and fails with
`called object type 'int' is not a function or function pointer`.

| form | result |
| --- | --- |
| `m: i64 = 15` then `{ ... }` | **fails** |
| `s = "a"` then `{ ... }` (string init) | **fails** |
| `m: i64 = x + 14` then `{ ... }` (expression init) | **fails** |
| `m: i64 = 15` then **`return { ... }`** | **works** |

The initializer's type is irrelevant — literal, string, and computed all fail. Only the
absence of an explicit `return` matters.

**Workaround: write `return` before tail table literals.** Applied to `simd.duo` (4 sites).

### Second blocker, now identified: dotted-namespace functions are not callable in-module

With `duo run -v` (which reveals the C errors the driver suppresses):

```
duo_simdtest.c:6370: called object type 'lua_Value' is not a function or function pointer
  ... _closure_10(&lane, &sign))(((int64_t)lua_to_num(({
duo_simdtest.c:6665: ...
  if (cl->up2(lua_table_get_str_cstr(..., "k", ...), x, y)) {
```

`simd.duo` defines functions as namespace-table fields (`lane.get = (...)`,
`sign.extend = (...)`, `run.bin = (...)`). Calling one of those **from another function in
the same module** emits a call against a `lua_Value` / captured upvalue rather than a
direct call, and fails to compile.

**Fix is a design change, not a patch:** flatten the namespaces to plain file-scope
functions (`lane_get`, `lane_put`, `sign_extend`, ...). That is also closer to GR-001 bare
functions; the dotted grouping was my stylistic choice and it is what broke.

**Not applied** — it is a mechanical rewrite of every definition and call site in the
module, and doing that without budget to verify is how the earlier retractions happened.

**Why this matters beyond SIMD:** "compute locals, return a record" is one of the most
ordinary shapes in the language, and Duo's own idioms favour bare tail expressions over
explicit `return`. This defect therefore penalises exactly the style the idioms prescribe.
Candidate fix: do not apply `f{...}` call sugar when a newline separates the callee from
the `{`, or when the callee is not callable.

### Superseded: earlier codegen-level diagnosis

Surfaced with `duo run -v` (the C compiler's output is suppressed by default):

```
/tmp/duo_n.c:5610:40: error: called object type 'int' is not a function or function pointer
```

Generated C for `g = (x: i64): any  m: i64 = 15  { lo = m, hi = 0 } end`:

```c
static inline lua_Value g(int64_t x) {
    int64_t m = ((int64_t)lua_to_num(15(({          // <-- 15 called as a function
        lua_Value tmp = lua_table_new_with_capacity(0, 2);
        lua_table_set_raw_lit(tmp, "lo", ..., lua_val_from_int((int64_t)(m)));
```

**The typed local's initializer is never closed.** `((int64_t)lua_to_num(15` is emitted
without its trailing `))`, so the function's tail expression (the table literal) is parsed
by C as an argument list applied to the literal `15`.

So this is *not* "locals cannot appear in table literals" — that was the observable
symptom. The defect is that a **local declaration whose initializer is a bare literal is
left unterminated when the function's tail expression follows it**. The table literal is
incidental; it is simply the next thing emitted.

Not yet located in `codegen.zig`. Search from the local-decl emission path for where the
`lua_to_num(` wrapper is opened, and confirm the matching close is emitted before the tail
expression. `src/codegen.zig:2868` is the native-scalar *check* for `.local_decl`, not the
emitter.

**Verified on the current compiler** (rebuilt 2026-08-05 17:48), so it is a live bug, not a
`duo_old` artifact.

### Superseded workaround note

**Workaround is narrow and unpleasant:** every table-literal field must be fully inlined
from parameters and field reads. For `lane.put` that means inlining the mask, which
collides with the `1 << w` literal-width bug above (an inlined `1` is 32-bit, so `w = 32`
zeroes the mask). The two bugs are mutually constraining: bug 2's fix wants a local, bug 3
forbids locals in the literal.

Escaping both needs either a codegen fix, or restructuring `lane.put` to return via
something other than a table literal. **Not applied** — this is a design change to the
v128 representation, not a patch.

### Ledger status unchanged

ward: **288** `@c.emit` sites; 118 have a written replacement that remains inert.

---

## CRITICAL duo codegen bug — 2 parameters + 2 `if` statements returns garbage

Found 2026-08-05 while debugging why `simd.duo` produced wrong lane values. **Present in
both `duo_old` and the current compiler, in both `fun` and bare-function syntax.**

### Minimal reproduction

```duo
fun two_if(x: i64, w: i64): i64
  r: i64 = 333
  if w == 64 r = 111 end
  if x == 5 r = 222 end
  return r
end

print(two_if(5, 32))   -- prints 65533, expected 222
```

`65533` is `0xFFFD`. No diagnostic; the program compiles and runs.

### Trigger matrix (measured)

| parameters | `if` statements | result |
| ---: | ---: | --- |
| 2 | 2 | **65533 — WRONG** |
| 2 | 1 | 222 correct |
| 2 | 0 | correct |
| 1 | 2 | 222 correct |
| 3 | 2 | 222 correct |

The trigger is **exactly two parameters** combined with **two or more `if` statements**.
Neither alone is sufficient. Early `return` vs assignment makes no difference; one-line vs
multi-line `if` makes no difference; `elseif` and `if/else` fail identically.

### Why it matters

"Two arguments, a couple of branches" is one of the most ordinary function shapes in any
codebase. Every affected function silently returns `65533` instead of its value — a wrong
answer, not a crash, so it corrupts results rather than failing loudly.

The `exactly 2` signature suggests a two-argument calling-convention or multi-return
(`lua_mret`) path rather than anything about branching itself; the `if` count is likely
just what pushes the body past some threshold in that path. Not yet located in
`codegen.zig`.

### It fully explains the `simd.duo` failures

`sign_extend = (x: i64, w: i64): i64` has exactly 2 parameters and 2 `if` statements. It
returned 34 for input 1 and 67 for input 2 — which is why `run_bin` produced 101 instead of
3, and why the pure-Duo SIMD module appeared to be wrong. **The module's logic was correct
all along**; every value passing through `sign_extend` (and `sign_wrap`, same shape) was
corrupted by the compiler.

Verified step by step: `spec.w`=32, `spec.k`="add", `lane_get` returns 1 and 2 correctly,
manual `lane_put` gives 3 — only `sign_extend` is wrong.

### Status

- Workaround exists (add a third parameter, or reduce to one `if`) but is **not applied** —
  papering over this in `simd.duo` would leave the compiler bug live for every other caller.
- This outranks everything else in this ledger: it is a **silent wrong-answer bug in the
  production compiler**, affecting an extremely common shape, in both compiler versions.
- Under Pass 34 §1 this is a barrier record with `class: process`, `impact.runtime: dominant`,
  `frequency: pervasive`, `evidence: measured`, `status: DISCOVERED`.

### ROOT CAUSE FOUND AND FIXED — a benchmark pattern-matcher was rewriting user functions

The generated C for the minimal repro explained everything:

```c
static inline int64_t two_if(int64_t x, int64_t w) {
    return __ack_impl(x, w);      // <-- the whole body, replaced
}
```

`sema.zig:detect_ack_inline` matched **any** function with exactly 2 integer parameters, an
integer return, no loops, and >=2 `if` statements — then codegen discarded the body and
called a hardcoded Ackermann implementation. It never checked the function actually
computes Ackermann. `65533` is `ack(3,13)` = 2^16-3.

This sits in a family (`sema.zig:3370`, comment *"Benchmarks 24-40 native pattern
detections"*): `gcd`, `collatz`, `xor_fold`, `bitcount`, `cordic`, `ack`, `matmul`,
`prefix_sum`, `ring_buf`, `cond_swap`. **Each should be audited for the same
over-matching.** Only `ack` was investigated here.

**Fix applied** (`sema.zig`): Ackermann is defined by recursion, so a body containing no
call at all cannot be it. Added `block_has_call` / `expr_has_call` and required a call
before the pattern matches.

| check | result |
| --- | --- |
| `two_if(5, 32)` | 65533 -> **222** (correct) |
| real `ack(2,3)` | **9** (correct) |
| `__ack_impl` still emitted for real Ackermann | **yes, 5 refs** — optimization preserved |
| `__ack_impl` emitted for `two_if` | 1 -> **0** |
| unit tests with fix | 1197 pass / 53 fail |
| unit tests **without** fix (baseline) | 1197 pass / 53 fail — **identical, zero regressions** |

### Consequence: `simd.duo` was never wrong

`sign_extend = (x: i64, w: i64)` was the only function in the module matching the pattern.
With the second `if` nested (keeping the top-level if-count at 1, which also works under the
un-fixed `duo_old`), the module is correct:

**17/17 SIMD operations pass** — i32x4 add/sub/mul, i64x2 add, i16x8 add, splat, i32x4
eq/lt_s, v128 and/or/xor, i32x4 neg — all matching expected values.

The descriptor-driven pure-Duo implementation (~90 opcodes from ~12 descriptor rows) is
**validated**. Next step is wiring it into the interpreter dispatch and deleting the 118
`@c.emit` sites, which is now an integration task rather than a debugging one.

### Trap for the catalog (Pass 34 §6)

Add **T8 — benchmark pattern-matchers that rewrite user code.** A detector keyed on
*shape* rather than *semantics* silently returns another function's answer. This is worse
than a slow path: it is a wrong-answer bug that scales with how ordinary the matched shape
is, and it inflates exactly the benchmarks it was written for. Any such detector must
verify semantics, not structure — and must leave a witness (Pass 34 charter).

---

## SIMD migrated to pure Duo and WIRED IN (2026-08-05)

The descriptor-driven module is now the live implementation. `runtime.duo` routes `0xFD` to
a Duo dispatch; all C SIMD code is deleted.

| | |
| --- | --- |
| `runtime.duo` diff | **201 deletions, 140 insertions** |
| C removed | `WardV128` union, 9 `WV_*` macros, wasm min/max helpers, the whole `case 0xFD` block (132 `WV_`/`WardV128` refs) |
| Duo added | `src/wasm/simd.duo` (237 lines) + `simd_step`/`simd_pop`/`simd_push` marshalling |
| opcode coverage | ~90 opcodes from **12 descriptor rows** (compare/arith/unary tables are folds over wasm's opcode-block regularity) |
| hot_big | 0.18s — **unchanged**; SIMD is not on that path |
| bench modules | 21/21 |
| real C programs | 10/10 |

Integer SIMD verified end-to-end through ward: `i32x4.add` + `extract_lane`, `i32x4.splat`,
`i64x2.sub` all match wasmtime. Module-level battery is 17/17.

### Correction to an earlier figure in this ledger

I repeatedly wrote "118 `@c.emit` sites" for the SIMD block. That was wrong: the block lived
*inside one* `@c.emit`, and 118/132 was a count of `WV_`/`WardV128` references. `runtime.duo`
still has 275 `@c.emit` calls — the SIMD migration removed C *lines*, not `@c.emit` *sites*.
The ledger's headline ward count should be read as "lines of embedded C", not call sites.

### Regression I introduced: float SIMD is no longer supported

The deleted C block implemented f32x4/f64x2 arithmetic and compares. `simd.duo` does not,
because lane-wise float work needs bit reinterpretation between i64 and f32/f64, and pure
Duo has no such operation (`string.pack` returns nil under `duo_old`).

`f64x2.lt` (opcode 73) now errors `unsupported SIMD opcode: 73` where the C path computed it.
**This is a real capability regression, traded for removing C.** It is recorded rather than
hidden because the trade was mine to make and should be reviewed.

**Correct fix, per §1.1-B:** a bit-reinterpret primitive belongs in duo's stdlib
(`lib/std/`), which is the sanctioned home for C-level primitives — not in ward. With
`f64_from_bits` / `f64_to_bits` in `lib/std`, `simd.duo` gains float lanes with no C in ward
and the descriptor tables extend by a few rows.

Until then: **integer SIMD is pure Duo and live; float SIMD is unimplemented.**

### Float SIMD regression CLOSED — all SIMD is now pure Duo

The correct fix was the one §1.1-B implies: put the primitive in the **stdlib**, not in ward.

**Added to `lib/std/bit.duo`** (the sanctioned home for C-level primitives):
`f64_to_bits`, `f64_from_bits`, `f32_to_bits`, `f32_from_bits` — IEEE bit
reinterpretation, 4 one-line `@c.emit` bodies. Verified: `f64_to_bits(1.5)` ->
4609434218613702656, round-trips exactly; f32 round-trips through single precision.

**`simd.duo` gained float lanes** as three more descriptor tables (`FBIN`, `FCMP`, `FUN`)
plus three executors that reinterpret via `std.bit`, compute in f64, and reinterpret back.
wasm `min`/`max` NaN and signed-zero semantics are handled explicitly; `pmin`/`pmax` use
the spec's asymmetric definition.

**11/11 float ops verified numerically**: f64x2 add/sub/mul/div/min/max/pmin/neg/abs/sqrt/lt.
End-to-end through ward, `f32x4.mul` and `f64x2.lt` match wasmtime (as bit patterns, ward's
documented convention).

### Retraction: "std.bit calls fail from a req'd module" was wrong

Recorded earlier as a duo codegen bug. It was a **missing `global`**. A module-level `req`
binding must be `global` or the name is not visible in the embedded module's generated C
(`use of undeclared identifier 'bit'`). `runtime.duo` already did this correctly
(`global mem_mod = req "std.mem"`); my probe did not.

Consequence: the inlined bit arithmetic in `simd.duo` was never necessary, and one entry in
this ledger's duo-bug list is withdrawn. That makes **two** of the four bugs I reported this
session retractions — the other being the "locals in table literals" family, which was the
Ackermann pattern-matcher.

### Final state of the SIMD migration

| | |
| --- | --- |
| `runtime.duo` | **201 deletions, 157 insertions** — all C SIMD gone |
| `simd.duo` | 370 lines pure Duo, integer **and** float |
| descriptor rows | ~19 rows covering ~110 opcodes |
| `jit_arm64.duo` | 0 `@c.emit` — still compliant |
| hot_big | 0.18s (unchanged; SIMD is off that path) |
| bench modules | 21/21 |
| real C programs | 10/10 |
| module battery | 17/17 integer, 11/11 float |

C-level primitives now live where the spec says they belong (`lib/std`), and ward's SIMD
path contains none.

### Compaction: six executors collapsed to one (net code now NEGATIVE)

The previous entry claimed a metaprogramming win while the line count had gone *up*
(370 Duo lines replacing ~200 C lines). That was an overclaim. The six executors
(`run_bin`/`run_un`/`run_cmp` x integer/float) were structurally identical lane walks, and
the six descriptor tables were the same shape.

Collapsed to **one executor over one table**:

- `OPS` — a single table; each row carries `w` (lane width), `k` (kernel), `n` (arity),
  `sg` (signed), `fl` (float), `c` (produces a mask).
- `run(spec, a, b)` — one lane walk. Arity, signedness, float-ness and compare-vs-arith are
  descriptor fields, not separate functions.
- Kernels reduce to three: `int_k`, `flt_k`, `cmp_ok`.
- `simd_step` in `runtime.duo` becomes a single `OPS[sub]` lookup instead of six.

| | before C removal | after migration | after compaction |
| --- | ---: | ---: | ---: |
| `simd.duo` lines | 0 | 370 | **268** |
| `runtime.duo` net | baseline | -44 | **-66** |
| executors | (C macros) | 6 | **1** |
| descriptor tables | (C switch) | 6 | **1** |
| generated rows -> opcodes | — | ~19 -> ~110 | **~20 -> ~110** |

**Net effect on ward: 268 lines of Duo replace 201 lines of C *and* the 6-way structural
duplication, with `runtime.duo` down 66 lines.** Combined, ward's SIMD support is smaller
than before the migration started and contains no C.

Re-verified after compaction, no behaviour change:

| check | result |
| --- | --- |
| integer battery | **17/17** |
| float battery | **11/11** |
| SIMD end-to-end vs wasmtime | 5/5 (2 as bit patterns, ward's convention) |
| bench modules | **21/21** |
| real C programs | **10/10** |

---

## URGENT: the committed duo tree cannot parse basic programs (not mine)

Found 2026-08-05 while testing metamethods.

```duo
p = 1
print(p)
print("after")
```

| compiler | result |
| --- | --- |
| `duo_old` (00:48 snapshot) | prints `1`, `after` — correct |
| **current duo (committed tree)** | **`error: expected 'end', got '<eof>'`** |

Nested calls are also broken: `print(tostring(p))` -> `expected ')', got '('`.

**Verified not caused by my changes.** Both of my working-tree edits (`sema.zig` Ackermann
detector, `codegen.zig` forward declarations) were stashed and the tree rebuilt — the parse
failure persists without them. `parser.zig` shows no working-tree modification, so the
defect is in committed code.

**Severity: the compiler cannot compile a three-line program.** Anything built from the
current tree is suspect. `duo_old` is unaffected, which is why ward continues to build and
pass (bench 21/21) — ward is pinned to `duo_old`.

This blocks: verifying metamethod behaviour on current duo, any migration of ward off the
pin, and both of my compiler fixes reaching production use.

## Metamethods: measured state (via `duo_old`)

Implicit dispatch **already works** for the headline cases:

| surface | result |
| --- | --- |
| `print(p)` calls `__tostring` implicitly | works |
| `"v=" .. p` calls `__tostring` implicitly | works |

So "shouldn't have to call tostring" is satisfied for print and concatenation.

### Gap found: dotted bare function declarations produce no table field

The canonical bare form on a dotted path is broken end-to-end:

```duo
Pt = {}
Pt.greet = (self: any): str
  return "hi"
end
print(Pt.greet(p))      -- nil
print(Pt["greet"])      -- nil
print(rawget(Pt, "greet"))  -- nil
```

It compiles a C function `Pt____greet` that nothing calls, and never stores the value in
the table — so metamethods defined this way are invisible to metatable lookup.

**Partial fix applied** (`codegen.zig`): the forward-declaration loop only covered
`path.len == 1` and methods, so dotted non-methods got no declaration and produced
`static declaration follows non-static declaration`. That is fixed; the function now
compiles. **The remaining half — storing the function into the table field — is not fixed.**

**Working canonical idiom meanwhile** (fully bare, no `fun`/`function`):

```duo
pt_tostring = (self: any): str
  return "Pt(" .. tostring(self.x) .. ")"
end
Pt.__tostring = pt_tostring
```

Two lines instead of one, and it works today.
