# Pass 57 C2 — exports are scope

## The rule

**A module's top-level bindings are its surface.** There is no export keyword,
there never was one, and none is being added. A module is a scope; `req` hands
you that scope; what is bound at the top level is what you get.

**Privacy is a policy fact, not syntax.** A top-level binding whose name begins
with `_` is private. Nothing outside the defining module may reach through to
it. This is one convention and zero grammar — G3, de-magicked: the rule is
stated, checked, and projectable to a capability, and the parser never learns
about it.

With this pinned, the ambient-namespace story (Pass 47) is complete end to end:
`std.thread` resolves to a scope, that scope's top-level bindings are its API,
and `std.thread._tls_registry` is a violation rather than an undocumented door.

## What counts as reaching through

Only the **module root** matters. Two shapes violate:

```
alias._name      -- alias bound in this file by `req`
std.mod._name    -- the ambient form of the same reach-through
```

Everything else with an underscore is not module privacy:

```
ch._closed       -- an instance field on a channel value
kv._key          -- an instance field on a parsed node
m.obj._f         -- a field on a value the module handed out
```

That distinction is load-bearing, not pedantic. The corpus has **184** `X._y`
accesses and essentially all of them are instance fields. A gate that flagged
"underscore after a dot" would be ~100% false positives and would be switched
off within a day. The `_` segment must sit at exactly module-surface depth —
position 2 for a `req` alias, position 3 under `std` — and the alias set is
derived per-file from that file's own `req` bindings, because a file can only
reach through a surface it named.

## Current state

Enforced by `scripts/module_surface_gate.duo`, wired into `agent-smoke`.

```
module_surface: 610 files, 0 reach-throughs (control: 3/3 fired)
module_surface: PASS
```

The declared private surface today — 17 top-level `_` bindings:

| file | count |
| --- | --- |
| `lib/std/trace.duo` | 5 |
| `examples/pretty_trace.duo` | 4 |
| `lib/std/thread.duo` | 3 |
| `lib/std/fs_watch.duo` | 2 |
| `lib/std/sqlite.duo` | 1 |
| `examples/exponential_product_showcase.duo` | 1 |
| `scripts/run_benchmark.duo` | 1 |

No consumer reaches any of them. The convention was already being followed;
this pins it so it stays followed.

## Why the gate carries a positive control

`self_check()` runs three cases before the corpus — a reach-through that must
be found, a legitimate call that must not be, and an ambient reach-through
alongside an instance field. If any of them does not behave, the gate fails
with "the detector is broken" rather than reporting a clean corpus.

This is not decoration. The Pass 57 C3 census printed a confident
`chained-comparison sites: 0` while scanning zero files, and `0` is also what a
passing run prints — the bug and the expected answer were indistinguishable.
A gate whose whole output is an absence needs proof that it can produce a
presence.

The control covers the detector; it does not cover the corpus walk, which is
where C3 actually broke. That path was verified separately by dropping a real
violating file into `examples/` and confirming the gate went to
`611 files, 1 reach-throughs / FAIL`, then back to `PASS` on removal.

## Scope note

The gate checks consumers, not declarations. It does not require any module to
mark internals with `_` — that stays the author's call. It guarantees only that
when an author *has* marked something private, the marking means something.
