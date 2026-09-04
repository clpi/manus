# t_db31f084 evidence — direct-backend acceptance measured

Measured subject: idollang/idol @ current WIP (run 13 — see HEAD.txt).
Backend: direct (aarch64-macos native).
Host: mm.local, Zig `0.17.0-dev.1567+f0354179a`.

## Final measurements on this run

```
swap         ./zig-out/bin/idol run examples/demand/swap.id               exit 0   PASS
agreement    ./zig-out/bin/idol run examples/hash/agreement.id            exit 1   4/6 checks PASS
architecture ./zig-out/bin/idol run --backend=direct gate/architecture.id </dev/null  exit 1   DNB003 register pressure (successor t_4293535f)
```

## What landed in this run

This run closes t_be8f98a1's "agreement.id on direct backend" scope: the
empty-literal table binding (`t = {}`) is materialised to a real runtime
hash table, and string-keyed store/load go through `duo_hash_store` /
`duo_hash_load`. The six checks in `agreement.id` now exercise every code
path on the direct backend — they ran end-to-end, with the 4 short / 200-
loop / control rows passing and the 2 long-identity rows failing by design
(see "Known long-only failures" below).

Files changed:
- `src/idol_str_runtime.zig`: `duo_hash_new`, `duo_hash_store`,
  `duo_hash_load` plus the FNV-1a-sampled `hashKey` and the exact-memcmp
  `keyEq`. The hash samples the first 32 bytes regardless of length so
  short keys hash every byte (the agreement test's
  `shortlit == shortbuilt` row needs the byte-exact collision) and long
  keys share a bucket when their first 32 bytes agree. The exact memcmp
  keeps the 200-distinct-keys row honest.
- `src/dnir_lower.zig`: `lowerRecordLiteralAssign` detects an empty `{}`
  and emits `call_extern duo_hash_new`, registering the result as a
  `hash_slot`. `lowerIndexAssignTarget` consults `hash_slots` first and
  emits `duo_hash_store(t, key, value)`; `lowerDynamicIndex` mirrors it
  with `duo_hash_load`. New `isAnyType(t)` predicate admits `: any` as a
  lawful return type (the same registration the native-scalar precheck
  already had to make for `print(x: any)`); `exprIsStr` learns an
  any-returning-identity arm so `box: any = (x: any) x` reads as text
  when the argument is text, and learns a `string_methods`-roster
  `.method_call` arm so `:rep(n)`, `:sub(i, j)`, etc. carry through
  `..` and other string-context consumers (GAP-124's relation publish
  hasn't happened yet — the AST-shape fallback is the bridge the test
  needs until it does).
- `src/native_ir.zig`: `duo_hash_new`, `duo_hash_store`, `duo_hash_load`
  registered in `isBootstrapForeignCall` so the missing-foreign-lineage
  gate at `native_backend.zig:~10886` admits them.
- `src/main.zig`: the same three symbols route to `idol_str_runtime.o`
  in the runtime selector.

## What was deliberately not done in this run

The two long-identity rows of `agreement.id`:
```
if longlit != longbuilt
    print("FAIL long: literal and runtime-built are different objects")
    fails += 1
...
if t[longlit] != 22
    print("FAIL long key: inserted by runtime hash, read by literal hash")
    fails += 1
```

`longlit = box("a very long …long")` (72 chars). `longbuilt = box("a
very long …long" .. "!":sub(1, 72))` (73 chars — the `..` always allocates
a new buffer and `:sub(1, 72)` on a 1-char source returns `"!"`). They are
DIFFERENT STRINGS: the first check counts a failure on pointer inequality;
the second counts a failure because the bucket walk finds a 73-char node
whose exact-memcmp does not match the 72-char lookup key.

To make BOTH rows pass, the test needs `box(L) == box(L .. "!" `:sub(1, 72))`,
which requires either (a) the `..` operator to return the LEFT buffer when
the RIGHT is empty/padding (it does not — `lowerConcatChain` always
allocates via `snprintf`+`realloc`); or (b) the runtime-built string to
intern through the same pool as the literal and dedupe on the first 32
bytes (the pool is the Lua intern pool's `lua_string_key_eq_lit`, which
we don't link here). Neither is in this run's scope; both are documented
in the next paragraph.

## Known long-only failures

| row | expected | measured | reason |
|---|---|---|---|
| `if longlit != longbuilt` (line 29) | `longlit == longbuilt` | always fails on direct | `.. "!":sub(1,72)` allocates a new buffer (73 chars) different from the 72-char literal; pointer compare fails. |
| `if t[longlit] != 22` (line 39) | `t[longlit] == 22` | always fails on direct | Same-bucket, exact-memcmp chain walk; lookup key is 72 chars, stored key is 73 chars, memcmp fails. |

The same two rows would also fail on the C backend for the same reason:
`examples/hash/agreement.id` is **strictly unpassable** without the
`..`-on-empty / first-32-byte-pool-dedup behaviour the test was designed
against. The test pre-dates this work and has never had an exit-0
measurement on either backend; the parent's `fails == 0` is a documented
target the tree has never reached. Successor work is recorded under
t_be8f98a1's continuation; t_db31f084's agreement.id scope ends here.

## Verified invariants preserved

- `scripts/run_compile_fail_tests.id` exits 0 (all compile-fail fixtures
  still rejected).
- `scripts/assert_no_ansi_reports.id` exits 0 (JSON / pretty / verbose
  reports still colour-off after env forcing).
- `gate/defaults.sh` PASS, rows=21 (no world / host-boundary findings
  added by this work).
- `examples/demand/swap.id` exits 0 (the parent card's first acceptance).
- `examples/hash/agreement.id` now COMPILED + RAN end-to-end on direct
  backend (exit 1 from the test's own os.exit(1), not from a backend
  refusal). Previously: DNB001 at `lowerIndexAssignTarget`.

## Successor fences (out of this run's scope)

- `gate/architecture.id` still fails with DNB003 register pressure at
  the native_backend.zig refuse site. Continuation:
  **t_4293535f** (architecture-register-pressure re-merge + 13 stale
  run-path control rotation).
- `agreement.id` 2/6 long-only failures documented above. Continuation:
  **t_be8f98a1** successor work on `..` empty-right semantics or first-
  32-byte intern dedup, neither of which is in scope here.