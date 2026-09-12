# t_9571b66e evidence — direct-backend acceptance for hash/agreement.id

Measured subject: idollang/idol @ HEAD `edf72377` + commit `82e09616`.
Backend: direct (aarch64-macos native).
Host: mm.local, Zig `0.17.0-dev.1567+f0354179a`.

## Acceptance

```
$ ./zig-out/bin/idol run examples/hash/agreement.id
> compile (examples/hash/agreement.id) …
  ok compile (503 ms — ./agreement.out)
hash agreement: 6 checks ran
hash agreement: PASS
EXIT=0
```

All six rows green:
- `shortlit == shortbuilt` (8-char content equality after content-equal sub)
- `longlit == longbuilt` (72-char content equality after precedence fix)
- `t[shortlit] == 11` (hash lookup of short key by literal — short-key
  bucket walked correctly)
- `t[longlit] == 22` (hash lookup of long key by literal — long-key
  bucket walked correctly with same first-32 bytes)
- `200 distinct long keys` (each `"x":rep(500) .. i:to(str)` hashes to a
  unique bucket because the `i:to(str)` tail varies)
- control: a long key never inserted answers nil

## Triage finding

At HEAD `edf72377`:
```
$ ./zig-out/bin/idol run examples/hash/agreement.id
error: direct backend: DNB001 application: unknown missing: param-type:any
        consumer: native realization producer: dnir lower
hint: bail site: native-scalar precheck — param-type:any
EXIT=1
```

The `param-type:any` refusal was introduced by commit `fb24b037` (Sept 5)
with the documented goal of sealing the door while architecture-side
register pressure work lands. The door sealed — but the
`examples/hash/agreement.id` path regressed because the earlier
Sept-4 commits (`db7d30cd`, `9dbf410c`) had added the runtime support
the agreement fixture needs (FNV-1a hash via `duo_hash_store` /
`duo_hash_load` in `src/idol_str_runtime.zig`, `lowerIndexAssignTarget`
and `lowerDynamicIndex` routing in `dnir_lower.zig`, the `.call`-arm
identity fallback in `exprIsStr`) WITHOUT the codegen-side admission
the runtime now lets through.

## Fix shape

The patch reopens the `param-type:any` bail ONLY for the closed
identity-forwarder shape — a single-parameter, no-default-value,
body-is-single-tail-expression-IS-the-parameter-name function:

```zig
const is_pure_identity_forwarder = blk: {
    if (fd.func.params.len != 1) break :blk false;
    const only = &fd.func.params[0];
    if (only.default_val != null) break :blk false;
    const body = fd.func.body;
    if (body.stmts.len != 0) break :blk false;
    const tail = body.tail_expr orelse break :blk false;
    if (tail.* != .name) break :blk false;
    break :blk std.mem.eql(u8, tail.name.ident, param.name);
};
if (!(measured_rt == .any and is_pure_identity_forwarder)) {
    self.nativeDiagFailFmt("param-type:{s}", .{typeLabel(param.typ)});
    return self.nofit(@src());
}
```

This is NOT the call-site inference that `31808eb9` measured and
declined. The closed identity forwarder carries the boxing through the
existing `lua_Value` path at the call site
(`callArgUsesNativeLowering` returns false when `param_type == .any`),
so admitting the function-level declaration does NOT widen what
`lower.native` sees; it widens what may be refused, and only on shapes
the body cannot prove native.

## Preserved refusals (re-measured)

- `examples/cfloor/weak.id`:
  ```
  error: direct backend: DNB001 application: unknown missing: param-type:any
  hint: bail site: native-scalar precheck — param-type:any
  ```
  `mix: any = (a: any, b: any) (a * 31 + b) % 1000003` has TWO `: any`
  params and a binop body — fails the single-param and tail-shape tests.
  The premise of `law.perf.dominance` (the weak half of the `cfloor.id`
  pair) — that an `any` parameter makes `lower.native` an invalid
  candidate for `mix` — is preserved exactly.

- `examples/cfloor/fact.id` (paired with weak.id): binop body, no
  identity — preserved.

- `examples/demand/swap.id`: no `: any` params, untouched.

- `gate/architecture.id`: still fails on `DNB003 register pressure`
  (sibling card `t_4293535f` / `t_daed572a` owns this; the fix here
  does not move that bail).

## Verified invariants preserved

- `zig build` exits 0.
- `zig build test`: `33/42 steps succeeded (7 failed); 2073/2073 tests
  passed` — was `32/42 steps succeeded (8 failed); 2073/2073 tests
  passed` at `edf72377` baseline. The single step that flipped from
  failing to passing is `cd . && ./zig-out/bin/idol run examples/hash/
  agreement.id`. No new step fails. The unit-test binary is byte-
  identical in its pass set: 2073/2073 in both runs.
- `scripts/run_compile_fail_tests.id` exits 0 (same pre-existing
  `barecase_*.id` corpus-message drift as before).
- `examples/demand/swap.id` exits 0.

## Out of scope (sibling cards)

- `t_4293535f` / `t_daed572a`: `gate/architecture.id` register pressure
  (DNB003) — unchanged.
- The 11 codegen unit-test fixtures that pinned the `duo_fallback_*`
  fallback macros (`typed dynamic field projections flow through
  assignments params and returns`, etc.) are NOT changed by this
  patch — they probe functions whose body is NOT a single-name tail
  (`fun get(box: any): i64 box.n end`), so they continue to bail at
  `param-type:any` and the fallback-macro C output they assert is
  preserved.
