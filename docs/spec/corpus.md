# SOURCE-ZERO transition manifest

Temporary deletion manifest for tracked project-owned `.id` debt. Not semantic
law — `docs/spec/constitution.md` owns classification. Git stores history;
this file lists only **current** deletion actions (`law.zero.history`).

Canonical project-owned source uses `.id` only. Retained behavior migrates to
executed `.id`, proves, then deletes the old file. Obsolete behavior deletes.
Compatibility cases become generated or external conformance material — not
in-tree stale source libraries.

Machine rules are legacy input tokens for `scripts/audit100.id`. They
authorize audit actions only; no token permits a file to remain. The rule block
disappears when the reader deletes and tracked project-owned `.id` reaches zero.

## Machine rules

```text
negative       examples/compile_fail/
negative       examples/native_differential/unsupported/
negative       error_test.id
canonical      examples/native_differential/
negative       fixtures/highlight/mixed/
foreign        fixtures/highlight/surface/
canonical      fixtures/highlight/
generated      lib/std/token/classify.id
generated      lib/std/wasm/opcode_lookup.id
generated      lib/std/wasm/ward_mvp_opcodes.id
foreign        examples/bash_
foreign        examples/c_emit
foreign        examples/c_interop
foreign        examples/ffi
foreign        examples/wasm/
compatibility  examples/lua
compatibility  examples/test_lua
canonical      examples/conversion/
canonical      examples/projection/
canonical      examples/infer/
canonical      examples/demand/
canonical      examples/nominal/
canonical      examples/layout/
canonical      examples/pack/
canonical      examples/anchor/
canonical      examples/case/
canonical      examples/read/
canonical      examples/boring/
canonical      examples/table/
foreign        vendor/
foreign        test.id
foreign        test2.id
```

Blockers: `GAP-145`, `GAP-134`, `docs/bootstrap.md`.
