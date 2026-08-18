# SOURCE-ZERO transition manifest

Temporary deletion manifest for tracked noncanonical `.id` debt. Not semantic
law — `docs/spec/constitution.md` owns classification. Git stores history;
this file lists only **current** deletion actions (`law.zero.history`).

Canonical project-owned source uses `.id` only. New canonical `.id` is
admitted. Retained behavior migrates to executed `.id`, proves, then deletes
the old noncanonical file. Obsolete behavior deletes. Compatibility cases
become generated or external conformance material — not in-tree stale source
libraries.

Machine rules are legacy input tokens for `scripts/audit100.id`. They
authorize audit actions only; no token permits a file to remain. The rule
block disappears when the reader deletes and tracked noncanonical `.id` debt
reaches zero.

## Machine rules

```text
negative       examples/compile_fail/
negative       examples/native_differential/unsupported/
negative       error_test.id
foreign        examples/native_differential/
generated      lib/token/classify.id
generated      lib/wasm/opcode_lookup.id
generated      lib/wasm/ward_mvp_opcodes.id
foreign        examples/bash_
foreign        examples/c_emit
foreign        examples/c_interop
foreign        examples/ffi
foreign        examples/wasm/
compatibility  examples/lua
compatibility  examples/test_lua
canonical      examples/json/
canonical      examples/conversion/
canonical      examples/projection/
canonical      examples/infer/
canonical      examples/demand/
canonical      examples/hash/
canonical      examples/native/
canonical      examples/control/
canonical      examples/nominal/
canonical      examples/layout/
canonical      examples/pack/
canonical      examples/anchor/
canonical      examples/case/
canonical      examples/read/
canonical      examples/boring/
canonical      examples/table/
compatibility  examples/luahost/
foreign        examples/parity/
foreign        examples/host/
foreign        examples/world/
foreign        examples/tailslot/
foreign        examples/shc/
foreign        examples/cfloor/
foreign        examples/benchmark.id
foreign        examples/mandelbrot.id
foreign        vendor/
foreign        test.id
foreign        test2.id
foreign        examples/
```

Unclassified root-level `examples/*.id` files are **foreign** until migrated into a
canonical teaching home (`examples/boring/`, `examples/layout/`, …) or deleted.
Negative fixtures stay under `examples/compile_fail/` only.

Blockers: `GAP-145`, `GAP-134`, `docs/bootstrap.md`.
