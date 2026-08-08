# The `.duo` corpus, classified

Epoch 2. This file is **machine-read** by `scripts/audit100.duo` (`zig build
audit100`). Editing the prose is free; editing a rule line changes what the
deny table is enforced against.

## Why this file exists

`CLAUDE.md` §1 is a deny table. A deny table is only pressure if it can reach
zero, and it cannot reach zero over 737 tracked `.duo` files, because a large
part of that corpus exists **in order to** contain the denied text:

- `examples/compile_fail/` must fail to compile — that is the assertion.
- `examples/bash_*.duo` embeds shell; `examples/c_emit_*.duo` embeds C.
- `lib/std/token/classify.duo` is emitted by `duo token-tables emit`; rewriting
  it by hand is the one thing its header forbids.
- Duo is a **Lua superset**, so Lua-shaped fixtures are INPUT that proves the
  claim, not debt that violates it.

Counting those as violations produces a gate that is red on the day it ships,
which is a gate nobody runs. So the corpus is partitioned first, and the deny
table is enforced against the `canonical` partition only.

## The six classes

| class | meaning | deny table applies |
|---|---|---|
| `canonical` | authored Duo that must converge on Pass 100 | **yes** |
| `compatibility` | proves the Lua superset still accepts Lua-shaped input | no |
| `foreign` | embeds another language (C, shell, ERE) by design, or is vendored | no |
| `negative` | must be rejected — the denied text is the assertion | no |
| `historical` | evidence of a past epoch; not maintained, not exemplary | no |
| `generated` | machine-emitted; the generator is the thing to fix | no |

## Mechanism: a manifest of ordered prefix rules, not per-file markers

The two candidates were a one-line marker comment at the top of every file, and
this. Markers were rejected:

1. They require editing 737 files, four of which are open in other sessions
   right now. A classification commit that collides with live compiler work
   costs more than it buys.
2. A marker is only as good as the check that every file has one — so a marker
   scheme *still* needs a gate that fails on absence. It buys no rot-resistance
   the manifest does not already have.
3. Markers put session metadata inside source files, which is the same category
   error as `.agents/AGENT_COORDINATION.md`.

The manifest is rot-resistant by the same rule that would have made markers
work: **a tracked `.duo` file matching no rule is a gate FAILURE.** A new file
must be classified or `audit100` goes red. There is no silent default.

Rules are **first match wins**, so order is meaningful: put the specific
prefixes above the general ones. A prefix ending in `/` matches a directory; a
prefix not ending in `/` matches any path starting with that text, which is how
`examples/bash_` picks out a family by filename.

To promote a file, add a one-line rule above the rule that currently catches it.

## Known soft spots, stated rather than hidden

- `examples/` defaults to `historical`. That is a **policy default**, not a
  measurement: 262 of the 354 example files have no inbound reference from
  `build.zig`, `scripts/`, `src/` or CI, and read as accumulated session probes.
  Some of them (`*_showcase.duo`) were written to be exemplary and should be
  re-adjudicated to `canonical` one at a time as they are revived.
- `scripts/` is `canonical` even though every gate in it shells out. Shelling
  out is a library call, not a foreign file.
- `examples/spec100/` is `canonical` and is the one place in `examples/` that
  is promoted by construction rather than case by case: each file is the
  fixture for one Pass 100 §20 construct, checked by `zig build spec-corpus`.
  The §20 blocks themselves are NOT here — the gate extracts them from
  `docs/spec/pass100.md` on every run, because a tracked copy of the spec's
  own text is a second source of truth and its drift is invisible.
- `scripts/audit100.duo` is excluded from its own scan by the gate itself, and
  the gate prints that it did. Its deny patterns are DATA; a corpus walker whose
  data is the thing it greps for reports its own source. This repo has already
  paid for that lesson once — see GAP-16, where `scripts/spec_conformance.duo`
  had its own test programs interpolated as if they were harness source.

## Rules

```
negative       examples/compile_fail/
negative       examples/native_differential/unsupported/
negative       error_test.duo
canonical      examples/native_differential/
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
