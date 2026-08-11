# SOURCE-ZERO transition manifest

This file is machine-read by the current bootstrap audit. It is a temporary
deletion manifest, not source-family authority, a compatibility archive, or a
pattern catalog.

Canonical project-owned Idsem source uses `.id`. Every tracked project-owned
`.duo` file is SOURCE-ZERO debt. Retained behavior must be reduced to current
semantics, executed from canonical `.id`, proved, and followed by deletion of
the old source. Obsolete behavior is deleted. Compatibility cases move to
generated, structured, or external conformance material rather than an in-tree
stale source library.

The class words below are legacy input tokens consumed by
`scripts/audit100.duo`. They authorize only the current audit action; none
authorizes a file to remain. Their deletion actions are:

| reader token | required migration action |
| --- | --- |
| `canonical` | migrate retained project behavior to executed `.id`, then delete the old file |
| `compatibility` | generate, structure, or externalize the compatibility case, then delete the stale source |
| `foreign` | retain only genuinely foreign material outside the native pattern surface or externalize it |
| `negative` | derive the rejection case from grammar/law facts or a machine-owned fixture, then delete the ordinary stale program |
| `historical` | delete; Git already preserves history |
| `generated` | fix the generator to emit canonical `.id`, regenerate, then delete the old output |

Rules are ordered and first match wins because the existing reader uses prefix
matching. A tracked `.duo` path matching no rule currently fails that reader.
That protects against silent omission but is not the final new-source ratchet:
adding another rule can still admit a new file. SOURCE-ZERO therefore remains
open until the exact-tree gate rejects every new `.duo`, includes untracked
files, and the tracked count reaches zero.

No path in the rule block is an implementation example. Agents and generators
must not open it as a pattern source. The rule block disappears with the reader
after all retained behavior has moved and every tracked project-owned `.duo`
file has been deleted.

The living law is [`constitution.md`](constitution.md). The complete source
family, lexical identity, generated grammar-role, and compiler-B migration
blockers remain recorded in `GAP-145`, `GAP-134`, and
[`docs/bootstrap.md`](../bootstrap.md). This manifest must not invent a second
classification authority to work around them.

## Machine rules

```text
negative       examples/compile_fail/
negative       examples/native_differential/unsupported/
negative       error_test.duo
canonical      examples/native_differential/
negative       fixtures/highlight/mixed/
foreign        fixtures/highlight/surface/
canonical      fixtures/highlight/
generated      examples/pass12_m1_diff.duo
generated      lib/std/token/classify.duo
generated      lib/std/wasm/opcode_lookup.duo
generated      lib/std/wasm/ward_mvp_opcodes.duo
historical     examples/pass5/
historical     examples/pass7/
historical     examples/pass8/
historical     examples/pass9/
foreign        examples/bash_
foreign        examples/c_emit
foreign        examples/c_interop
foreign        examples/ffi
foreign        examples/wasm/
compatibility  examples/lua
compatibility  examples/test_lua
canonical      examples/spec100/
canonical      examples/boring/
canonical      examples/table/
historical     examples/
foreign        vendor/
historical     test.duo
historical     test2.duo
canonical      benchmarks/
canonical      ext/ward/
canonical      lib/
canonical      scripts/
canonical      tests/
canonical      tools/
```
